extends Node2D
# The outside level: tile world, hatch, crates, radiation, HUD hookup.
# This scene never changes scenes. It only calls GameState.bank_loot / player_died.
# Systems live in their own scripts: radiation (scenes/radiation.gd), health
# (actors/health.gd), inventory (scenes/inventory.gd), HUD (scenes/hud.tscn),
# digging (scenes/mining.gd), tool swings (scenes/tool_swing.gd), zombies
# (actors/zombie.gd + scenes/zombie_spawner.gd), trees (actors/tree.gd).
#
# Layout (V2): 10 screens wide, the hatch in the middle, zones mirrored:
#   depot | market | suburb | HATCH | suburb | market | depot
# Radiation and loot get better with distance from the hatch, both ways.

const TILE := 16
const COLS := 300            # 300 * 16 = 4800 px = 10 screens of 480
const WORLD_W := COLS * TILE
const BASE_ROW := 14         # ground surface row on flat land (y = 224)
const BOTTOM_ROW := 21       # fill the ground down to here (exclusive); the last row is bedrock
const CAM_BOTTOM_MIN := 270  # camera bottom on the surface (one screen tall) ..
const CAM_BOTTOM_MAX := BOTTOM_ROW * 16   # .. follows the player down into holes
const HATCH_COL := 150
const HATCH_X := 2408.0      # centre of column 150 (the middle of the map)
const HALF_W := 2400.0       # hatch -> edge, the "how far out" scale (0..1)

# Hills: [column offset from the hatch, half width in columns, height in tiles].
# Mirrored with small changes so the two sides don't look identical.
const HILLS := [[25, 9, 2], [60, 12, 3], [92, 8, 2], [120, 14, 3], [142, 6, 1],
	[-30, 8, 2], [-62, 12, 3], [-95, 9, 2], [-118, 13, 3], [-140, 6, 1]]
# Crate x positions (px), nearest first. Circuits only appear in the far ones
# (more than 70% of the way to an edge). The last two are the farthest, one per
# edge, both 2350 px from the hatch; the last one is at the right edge.
const CRATE_XS := [2640, 2140, 2910, 1860, 3240, 1520, 3560, 1180, 3900, 820, 4230, 520, 4520, 250, 58, 4758]

const CrateScript := preload("res://actors/crate.gd")
const RadiationScript := preload("res://scenes/radiation.gd")
const InventoryScript := preload("res://scenes/inventory.gd")
const MiningScript := preload("res://scenes/mining.gd")
const SwingScript := preload("res://scenes/tool_swing.gd")
const SpawnerScript := preload("res://scenes/zombie_spawner.gd")
const TREE_SCENE := "res://actors/tree.tscn"
# Trees: dead trees on the surface of the suburb and market (not the depot),
# never within TREE_MIN_COL columns of the hatch or next to a crate.
const TREE_MIN_COL := 12
const TREE_GAP := [5, 11]    # columns between trees (random in this range)

const PAUSE_MENU := "res://scenes/pause_menu.tscn"
# Banking: the survivor climbs down the hatch ladder and the screen fades, then GameState
# changes the scene (it waits GameState.HATCH_TRANSITION = 0.9 s after bank_loot).
const CLIMB_TIME := 0.75
const CLIMB_DEPTH := 30.0
const FADE_IN := 0.35        # black -> picture when the expedition starts (coming up the ladder)
const LIGHTING := "res://scenes/lighting.gd"   # optional: the game runs without it

# Lighting tuning (Phase 3). Ambient = DUSK x zone tint x (1 - darkness), never
# below Lighting.MIN_BRIGHTNESS. darkness = DARK_DIST x distance + DARK_RAD x radiation.
const DUSK := Color(0.86, 0.8, 0.9)
const ZONE_TINT := [Color(1.0, 0.92, 0.82), Color(0.96, 0.96, 1.0), Color(0.82, 1.0, 0.8)]   # suburb warm, market, depot green
const DARK_DIST := 0.42
const DARK_RAD := 0.3
const HATCH_LAMP := [Color(1.0, 0.72, 0.38), 1.1, 100.0, 0.12]   # colour, energy, radius, flicker
const PACK_LAMP := [Color(1.0, 0.9, 0.3), 0.8, 44.0, 1.2]        # colour, energy, radius, pulses/s
const TOXIC_GLOW := [Color(0.55, 1.0, 0.3), 0.9, 40.0, 3]       # colour, energy, radius, pool size
const RAD_LINES := ["Radiation rising. Head home.", "Radiation high! Go home now!", "Radiation sickness! Losing health!"]

var rad: RefCounted = RadiationScript.new()
var radiation: float:        # percent; a property so tests and the debug key can set it
	get:
		return rad.value
	set(v):
		rad.value = v
var ended := false           # true once banking or dying has started (only one may ever run)
var rad_mult := 1.0
var inventory: Node = null
var warning_sound: AudioStreamPlayer = null   # optional: audio/sfx_rad_warning.* if present
var pause_menu: Node = null  # scenes/pause_menu.tscn (Esc), if present
var surface_rows: Array[int] = []   # natural surface; mining.floor_rows is the current one
var use_art_tiles := false   # false = drawn placeholder tiles (tiles_outside.png missing)
var zombies_enabled := true  # tests switch this off before adding the scene
var mining: Node2D = null
var swing: Node2D = null
var spawner: Node = null
var _shake_tween: Tween
var last_stand_pack: Area2D = null
var lighting: Node2D = null  # scenes/lighting.gd, if present
var toxic_cells: Array[Vector2i] = []   # glowing toxic tiles (lit once exposed)

# tiles_outside.png atlas (4x2)
const T_DIRT := Vector2i(0, 0)
const T_GRASS := Vector2i(1, 0)
const T_ASPHALT := Vector2i(3, 0)
const T_GRAVEL := Vector2i(1, 1)
const T_SCRAP := Vector2i(2, 1)
const T_TOXIC := Vector2i(3, 1)
const AREA_COLS := 50        # per side: suburb, market, depot (50 columns = 800 px each)

@onready var ground: TileMapLayer = $Ground
@onready var hatch: Area2D = $Hatch
@onready var player: CharacterBody2D = $Player
@onready var crates: Node2D = $Crates
@onready var hud: CanvasLayer = $HUD
@onready var fade: ColorRect = $HUD/Fade
@onready var camera: Camera2D = $Player/Camera2D

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.35, 0.4, 0.38))
	rad_mult = GSBridge.radiation_multiplier()
	build_background()
	mining = MiningScript.new()
	mining.name = "Mining"
	mining.ground = ground
	add_child(mining)
	use_art_tiles = build_tileset()
	build_terrain()
	mining.setup(ground, surface_rows, player, GSBridge.loot_multiplier(), GSBridge.dig_speed_bonus())
	hatch.position = Vector2(HATCH_X, surface_y(HATCH_X))
	player.position = hatch.position + Vector2(0, -2)
	mining.protect_x(HATCH_X, 3)   # the hatch and the spawn can't be dug out
	spawn_crates()
	spawn_last_stand_pack()
	spawn_trees()
	inventory = InventoryScript.new()
	inventory.name = "Inventory"
	add_child(inventory)
	inventory.setup(player)
	player.held_tool = inventory.selected_tool()
	inventory.selection_changed.connect(func(_i: int) -> void: player.held_tool = inventory.selected_tool())
	swing = SwingScript.new()
	swing.name = "ToolSwing"
	add_child(swing)
	swing.setup(self)
	inventory.tool_used.connect(swing.use)
	spawner = SpawnerScript.new()
	spawner.name = "ZombieSpawner"
	add_child(spawner)
	spawner.enabled = zombies_enabled
	spawner.setup(self)
	spawner.first_seen.connect(func() -> void: hud.hint_once("first_zombie", "Zombie! Hit it with the pickaxe or axe (left click), or outrun it."))
	hud.setup(player, inventory, rad, HATCH_X)
	player.hurt.connect(func(_a: int, src: String) -> void: if src != "radiation": shake(3.0, 0.2))
	camera.limit_smoothed = true
	hatch.bank_requested.connect(_on_bank_requested)
	player.message.connect(show_message)
	player.out_of_health.connect(_die)
	rad.warning.connect(_on_rad_warning)
	rad.drain_tick.connect(_on_rad_drain)
	_setup_warning_sound()
	if ResourceLoader.exists(PAUSE_MENU):
		pause_menu = load(PAUSE_MENU).instantiate()
		add_child(pause_menu)
	_setup_lighting()
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, FADE_IN)

# 0 = suburb (next to the hatch), 1 = market, 2 = depot (edges). Same on both sides.
func area_of(col: int) -> int:
	return clampi(floori(absi(col - HATCH_COL) / float(AREA_COLS)), 0, 2)

# 0 at the hatch .. 1 at either edge.
func distance_frac(x: float) -> float:
	return clampf(absf(x - HATCH_X) / HALF_W, 0.0, 1.0)

# --- background --------------------------------------------------------------

# Parallax layers, back to front. The camera never moves vertically (the world is
# one screen tall), so only x scrolls. Near layers: one panel per area, scroll 0.8,
# mirrored around the middle like the zones: depot, market, suburb | suburb,
# market, depot. far: mirrored copies so the repeat is seamless. Missing textures
# are skipped and the plain Sky rect stays.
func build_background() -> void:
	var sky := Art.texture("res://art/world_clean/bg_sky.png")
	if sky:
		$Sky.visible = false
		_parallax(0.1, [sky], 0.0, false, Color(1, 1, 1))
	var far := Art.texture("res://art/world_clean/bg_far.png")
	if far:
		_parallax(0.4, [far], -14.0, true, Color(0.8, 0.75, 0.75))
	var near: Array[Texture2D] = []
	for area in ["depot", "market", "suburb"]:
		var t := Art.texture("res://art/world_clean/bg_near_%s.png" % area)
		if t:
			near.append(t)
	if near.size() == 3:
		near.append_array([near[2], near[1], near[0]])
		_parallax(0.8, near, -26.0, false, Color(0.62, 0.58, 0.6), 3)

var _bg_layers := 0

# tint darkens the layer so the player and crates stand out against it.
# mirror_from: panels whose index (mod the list) is >= this are flipped.
func _parallax(scroll: float, textures: Array, y: float, mirror: bool, tint: Color, mirror_from := -1) -> void:
	var layer := Parallax2D.new()
	layer.modulate = tint
	layer.scroll_scale = Vector2(scroll, 1.0)
	layer.z_index = -10
	add_child(layer)
	move_child(layer, _bg_layers)   # behind everything, in call order
	_bg_layers += 1
	var x := 0.0
	$Sky.light_mask = 2   # Lighting.MASK_BACKGROUND: world lamps only, not the headlamp
	# enough panels to cover what the camera can show at this scroll speed
	var need := (WORLD_W - 480.0) * scroll + 480.0
	var i := 0
	while x < need:
		var tex: Texture2D = textures[i % textures.size()]
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.position = Vector2(x, y)
		s.light_mask = 2   # Lighting.MASK_BACKGROUND
		s.flip_h = (mirror and i % 2 == 1) or (mirror_from >= 0 and i % textures.size() >= mirror_from)
		layer.add_child(s)
		x += tex.get_width()
		i += 1

# --- terrain ---------------------------------------------------------------

# Ground TileSet (built by mining.gd): tiles_outside.png + tiles_ore.png, or drawn
# placeholders. Every block collides (blocks can be dug out, so any may become
# exposed). Returns false if tiles_outside.png is missing.
func build_tileset() -> bool:
	return mining.build_tileset()

# Which art tile goes where: grass in the suburb, gravel/asphalt at the market,
# scrap and toxic dirt at the depot; dirt with a few stones below.
func art_tile(x: int, y: int) -> Vector2i:
	var n := (x * 7 + y * 13) % 11   # cheap deterministic noise
	if y == surface_rows[x]:
		match area_of(x):
			0: return T_GRASS
			1: return T_ASPHALT if surface_rows[x] == BASE_ROW and n < 7 else T_GRAVEL
			_: return T_TOXIC if n == 0 else T_SCRAP
	return T_DIRT

func build_terrain() -> void:
	# Surface row per column: flat, plus triangle hills (1 tile steps at most).
	for x in COLS:
		var h := 0
		for hill in HILLS:
			var slope: float = float(hill[1]) / float(hill[2])
			h = maxi(h, int(hill[2] - absf(x - (HATCH_COL + hill[0])) / slope))
		surface_rows.append(BASE_ROW - maxi(h, 0))
	# Blocks: surface, dirt with ores (mining.kind_for: deeper and farther = richer), bedrock.
	mining.rng.seed = hash("bunker7") + GSBridge.day()
	for x in COLS:
		for y in range(surface_rows[x], BOTTOM_ROW):
			var kind := "bedrock"
			if y < BOTTOM_ROW - 1:
				kind = mining.kind_for(y - surface_rows[x], distance_frac(x * TILE + 8.0), area_of(x))
			var at := art_tile(x, y)
			mining.place(Vector2i(x, y), kind, at)
			if kind == "toxic" or (kind == "surface" and at == T_TOXIC):
				toxic_cells.append(Vector2i(x, y))

# y (px) of the top of the natural ground at world x (before any digging)
func surface_y(x: float) -> float:
	var col := clampi(int(x / TILE), 0, COLS - 1)
	return float(surface_rows[col] * TILE)

# y (px) of the top of the ground now (holes included)
func floor_y(x: float) -> float:
	return mining.floor_y(x)

# --- trees -------------------------------------------------------------------------

func spawn_trees() -> void:
	var scene: PackedScene = load(TREE_SCENE)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("trees") + GSBridge.day()
	var mult := GSBridge.loot_multiplier()
	for side in [-1, 1]:
		var off := TREE_MIN_COL + rng.randi_range(0, 3)
		while off < AREA_COLS * 2 - 2:   # suburb + market only
			var col: int = HATCH_COL + side * off
			off += rng.randi_range(TREE_GAP[0], TREE_GAP[1])
			if _near_crate(col):
				continue
			var big := area_of(col) == 1
			var roll := rng.randf()
			var size := "large" if roll < (0.45 if big else 0.15) else ("medium" if roll < 0.7 else "small")
			var t: Node2D = scene.instantiate()
			var x := col * TILE + 8.0
			t.position = Vector2(x, surface_y(x))
			t.setup(size, player, floor_y, mult)
			add_child(t)
			mining.protect_col(col)   # no digging under a tree

func _near_crate(col: int) -> bool:
	for cx in CRATE_XS:
		if absi(int(cx / TILE) - col) <= 2:
			return true
	return last_stand_pack != null and absi(int(last_stand_pack.position.x / TILE) - col) <= 2

# --- crates & pack ---------------------------------------------------------

func spawn_crates() -> void:
	var crate_scene: PackedScene = load("res://actors/crate.tscn")
	var loot_mult := GSBridge.loot_multiplier()
	for x in CRATE_XS:
		var c: Area2D = crate_scene.instantiate()
		c.position = Vector2(x, surface_y(x))
		crates.add_child(c)
		c.setup(distance_frac(x), loot_mult)
		mining.protect_x(x, 1)

# The backpack left where the player died last time. Gives items back when E is pressed.
# Partial pickup rule: take what fits (rarest first, like crates); the rest stays
# in the pack for the rest of THIS expedition only. GameState clears the pack
# when this expedition ends (bank or death), so leftovers are then gone.
# If you die again, whatever you carry becomes the new pack.
class Pack extends Area2D:
	var items: Dictionary
	func can_interact(_player: Node) -> bool:
		return not items.is_empty()
	func interact(player: Node) -> void:
		if player.capacity_left() <= 0:
			player.say("Backpack full!")
			return
		CrateScript.take_into(items, player)
		if items.is_empty():
			player.say("Recovered your Last Stand Pack")
			queue_free()
		else:
			player.say("Pack partly recovered (backpack full)")

func spawn_last_stand_pack() -> void:
	var data := GSBridge.last_stand_pack()
	if data.is_empty():
		return
	var pack := Pack.new()
	last_stand_pack = pack
	pack.name = "LastStandPack"
	pack.add_to_group("last_stand_pack")
	for k in data["items"]:
		if data["items"][k] > 0:
			pack.items[k] = data["items"][k]
	pack.collision_layer = 4
	pack.collision_mask = 0
	var pos: Vector2 = data.get("position", Vector2(HATCH_X + 100, 0))
	var x := clampf(pos.x, 8.0, WORLD_W - 8.0)
	pack.position = Vector2(x, surface_y(x))   # sit on the ground
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 18)
	shape.shape = rect
	shape.position = Vector2(0, -9)
	pack.add_child(shape)
	var art := Art.sprite(pack, "res://art/world_clean/obj_last_stand_pack.png", 1.0)
	if art == null:
		var glow := ColorRect.new()          # placeholder: glowing yellow backpack
		glow.color = Color(1.0, 0.9, 0.2)
		glow.position = Vector2(-5, -12)
		glow.size = Vector2(10, 12)
		pack.add_child(glow)
	add_child(pack)
	mining.protect_x(x, 1)
	if art:   # gentle pulse so it reads as "your stuff"
		var tw := pack.create_tween().set_loops()
		tw.tween_property(art, "modulate", Color(1.4, 1.3, 0.8), 0.6)
		tw.tween_property(art, "modulate", Color(1, 1, 1), 0.6)

# --- radiation, death, banking ---------------------------------------------

# Radiation fills outside (faster farther out, both ways). At 100% it drains
# health (rad.drain_tick); health 0 -> player.out_of_health -> _die().
func _process(delta: float) -> void:
	if ended:
		return   # no radiation during the death fade or after banking
	rad.tick(delta, distance_frac(player.position.x), rad_mult, hatch.player_inside)
	hud.set_hint("E: climb down (bank loot)" if hatch.player_inside else "")
	if lighting:
		lighting.set_ambient(dusk_ambient())
	# the camera follows the player down into holes, else shows one screen from the top
	camera.limit_bottom = clampi(int(player.global_position.y) + 46, CAM_BOTTOM_MIN, CAM_BOTTOM_MAX)

# --- lighting (scenes/lighting.gd) -------------------------------------------------

# Everything is optional: without lighting.gd (or with quality "off") the plain look stays.
func _setup_lighting() -> void:
	if not ResourceLoader.exists(LIGHTING):
		return
	var script: GDScript = load(LIGHTING)
	if script == null:
		return
	lighting = script.setup_scene(self, dusk_ambient())
	lighting.watch(pause_menu)
	lighting.follow_player(player, func() -> bool: return inventory != null and inventory.selected_tool() == "flashlight")
	var lamp: Node2D = script.add_lamp(self, hatch.position + Vector2(0, -18), HATCH_LAMP[0], HATCH_LAMP[1], HATCH_LAMP[2], HATCH_LAMP[3])
	lamp.name = "HatchLamp"
	lamp.priority = 10000.0   # the safe-zone marker always wins the cap
	if last_stand_pack and is_instance_valid(last_stand_pack):
		var pl: Node2D = script.add_lamp(last_stand_pack, Vector2(0, -8), PACK_LAMP[0], PACK_LAMP[1], PACK_LAMP[2])
		pl.name = "PackLamp"
		pl.pulse = PACK_LAMP[3]
		pl.priority = 200.0
	lighting.setup_glow(TOXIC_GLOW[3], TOXIC_GLOW[0], TOXIC_GLOW[1], TOXIC_GLOW[2])
	_update_toxic_glow()
	lighting.add_heightmap_occluders(mining.floor_rows, BOTTOM_ROW * TILE, TILE)
	mining.block_broken.connect(_on_block_broken_light)

func _on_block_broken_light(cell: Vector2i, _kind: String) -> void:
	if lighting:
		lighting.refresh_ground_col(cell.x)
		_update_toxic_glow()

# Toxic tiles glow once exposed: top of their column, or a side open to a dug neighbour.
func _update_toxic_glow() -> void:
	var spots := PackedVector2Array()
	for c in toxic_cells:
		if mining.kind_at(c) == "":
			continue   # dug out
		var open: bool = c.y == mining.floor_rows[c.x]
		for n in [c.x - 1, c.x + 1]:
			if n >= 0 and n < COLS and mining.floor_rows[n] <= c.y:
				open = true
		if open:
			spots.append(Vector2(c) * TILE + Vector2(8, 4))
	lighting.set_glow_spots(spots)

# Dusk outside: darker farther from the hatch and as radiation rises; warmer in
# the suburb, greener in the depot (smooth between zones).
func dusk_ambient() -> Color:
	var f := distance_frac(player.position.x) if player else 0.0
	var z := clampf(f * 3.0 - 0.5, 0.0, 2.0)   # 0 suburb .. 1 market .. 2 depot, blended
	var i := mini(int(z), 1)
	var tint: Color = (ZONE_TINT[i] as Color).lerp(ZONE_TINT[i + 1], smoothstep(0.0, 1.0, z - i))
	var dark := DARK_DIST * f + DARK_RAD * clampf(rad.value / 100.0, 0.0, 1.0)
	var c := DUSK * tint * (1.0 - dark)
	c.a = 1.0
	return c

# Small camera shake (getting hit, landing a hit).
func shake(strength: float, time: float) -> void:
	if _shake_tween:
		_shake_tween.kill()
	_shake_tween = create_tween()
	var steps := maxi(2, int(time / 0.03))
	for i in steps:
		var k := strength * (1.0 - float(i) / steps)
		_shake_tween.tween_property(camera, "offset", Vector2(randf_range(-k, k), randf_range(-k, k)), 0.03)
	_shake_tween.tween_property(camera, "offset", Vector2.ZERO, 0.03)

func _on_rad_drain() -> void:
	if not ended:
		player.take_damage(RadiationScript.DRAIN_DAMAGE, "radiation")

func _on_rad_warning(level: int) -> void:
	show_message(RAD_LINES[level])
	if warning_sound:
		warning_sound.pitch_scale = 1.0 + 0.25 * level
		warning_sound.play()

func _setup_warning_sound() -> void:
	for ext in ["wav", "ogg", "mp3"]:
		var path := "res://audio/sfx_rad_warning.%s" % ext
		if ResourceLoader.exists(path):
			warning_sound = AudioStreamPlayer.new()
			warning_sound.stream = load(path)
			add_child(warning_sound)
			return

# reason: "radiation", "zombie", ... shown on the HUD during the fade.
func _die(reason := "") -> void:
	if ended:
		return
	ended = true
	_disable_pause()
	if reason == "":
		reason = player.death_reason if player.death_reason != "" else "radiation"
	hud.set_hint("")
	var items: Dictionary = player.items.duplicate()   # snapshot at the moment of death
	var where: Vector2 = player.global_position
	player.die(reason)
	# One sequence: wait for the collapse, then fade. (Awaiting two signals in a
	# row can hang forever if the second one already fired.)
	await player.collapse_done
	hud.show_death(reason)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 1.0)
	await tw.finished
	await get_tree().create_timer(0.8, false).timeout   # let the reason be read
	GSBridge.player_died(items, where)

func _on_bank_requested(p: Node) -> void:
	if ended:
		return
	ended = true
	_disable_pause()
	hud.set_hint("")
	p.frozen = true
	var loot: Dictionary = p.items.duplicate()
	p.clear_items()
	GSBridge.bank_loot(loot)   # banks once now; GameState changes the scene after the climb
	_climb_down(p)

# The survivor climbs down the hatch ladder while the screen fades to black.
func _climb_down(p: Node) -> void:
	var open_lid := Art.sprite(hatch, "res://art/world_clean/obj_hatch_open.png", 3.0)
	if open_lid:
		open_lid.z_index = 1
		for n in hatch.get_children():
			if n is Sprite2D and n != open_lid:
				n.visible = false
	if p.has_method("climb_into"):
		p.climb_into(Vector2(hatch.global_position.x, hatch.global_position.y - 1.0), CLIMB_DEPTH, CLIMB_TIME)
	var tw := create_tween()
	tw.tween_interval(CLIMB_TIME * 0.35)
	tw.tween_property(fade, "color:a", 1.0, CLIMB_TIME * 0.65)

# No pausing once the expedition is ending (death fade / scene change).
func _disable_pause() -> void:
	if pause_menu and "enabled" in pause_menu:
		pause_menu.enabled = false

# --- HUD -------------------------------------------------------------------

func show_message(text: String) -> void:
	hud.show_message(text)

# Debug key, only in debug builds (editor / debug export), never in the shipped game.
# (Esc is the `pause` action now; the pause menu listens to it.)
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:   # fill radiation to test the health drain
			radiation = 100.0
