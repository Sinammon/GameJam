extends Node2D
# The outside level: tile world, hatch, crates, radiation, HUD hookup.
# This scene never changes scenes. It only calls GameState.bank_loot / player_died.
# Systems live in their own scripts: radiation (scenes/radiation.gd), health
# (actors/health.gd), inventory (scenes/inventory.gd), HUD (scenes/hud.tscn).
#
# Layout (V2): 10 screens wide, the hatch in the middle, zones mirrored:
#   depot | market | suburb | HATCH | suburb | market | depot
# Radiation and loot get better with distance from the hatch, both ways.

const TILE := 16
const COLS := 300            # 300 * 16 = 4800 px = 10 screens of 480
const WORLD_W := COLS * TILE
const BASE_ROW := 14         # ground surface row on flat land (y = 224)
const BOTTOM_ROW := 19       # fill dirt down to here
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

const PAUSE_MENU := "res://scenes/pause_menu.tscn"
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
var surface_rows: Array[int] = []
var use_art_tiles := false   # false = placeholder tileset from the scene

const TILES_TEX := "res://art/world_clean/tiles_outside.png"
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

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.35, 0.4, 0.38))
	rad_mult = GSBridge.radiation_multiplier()
	build_background()
	use_art_tiles = build_tileset()
	build_terrain()
	hatch.position = Vector2(HATCH_X, surface_y(HATCH_X))
	player.position = hatch.position + Vector2(0, -2)
	spawn_crates()
	spawn_last_stand_pack()
	inventory = InventoryScript.new()
	inventory.name = "Inventory"
	add_child(inventory)
	inventory.setup(player)
	inventory.tool_used.connect(player.use_tool)
	hud.setup(player, inventory, rad, HATCH_X)
	hatch.bank_requested.connect(_on_bank_requested)
	player.message.connect(show_message)
	player.out_of_health.connect(_die)
	rad.warning.connect(_on_rad_warning)
	rad.drain_tick.connect(_on_rad_drain)
	_setup_warning_sound()
	if ResourceLoader.exists(PAUSE_MENU):
		pause_menu = load(PAUSE_MENU).instantiate()
		add_child(pause_menu)

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
	# enough panels to cover what the camera can show at this scroll speed
	var need := (WORLD_W - 480.0) * scroll + 480.0
	var i := 0
	while x < need:
		var tex: Texture2D = textures[i % textures.size()]
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.position = Vector2(x, y)
		s.flip_h = (mirror and i % 2 == 1) or (mirror_from >= 0 and i % textures.size() >= mirror_from)
		layer.add_child(s)
		x += tex.get_width()
		i += 1

# --- terrain ---------------------------------------------------------------

# Builds a TileSet from tiles_outside.png. Alternative 0 of each tile has
# collision, alternative 1 has none (deep fill). Returns false if the art is missing.
func build_tileset() -> bool:
	var tex := Art.texture(TILES_TEX)
	if tex == null:
		return false
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE, TILE)
	var square := PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)])
	ts.add_source(src, 0)
	for y in 2:
		for x in 4:
			var c := Vector2i(x, y)
			src.create_tile(c)
			src.create_alternative_tile(c, 1)
			var td := src.get_tile_data(c, 0)
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, square)
	ground.tile_set = ts
	return true

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
	for x in COLS:
		var left := surface_rows[maxi(x - 1, 0)]
		var right := surface_rows[mini(x + 1, COLS - 1)]
		var solid_to := maxi(surface_rows[x], maxi(left, right) - 1)
		for y in range(surface_rows[x], BOTTOM_ROW):
			# Tile 0 (atlas 0,0) = solid ground with collision, tile 1 = dirt (no collision).
			# Surface and exposed hill sides are solid so they can't be walked through.
			var solid := y <= solid_to
			if use_art_tiles:
				ground.set_cell(Vector2i(x, y), 0, art_tile(x, y), 0 if solid else 1)
			else:
				ground.set_cell(Vector2i(x, y), 0, Vector2i(0, 0) if solid else Vector2i(1, 0))

# y (px) of the top of the ground at world x
func surface_y(x: float) -> float:
	var col := clampi(int(x / TILE), 0, COLS - 1)
	return float(surface_rows[col] * TILE)

# --- crates & pack ---------------------------------------------------------

func spawn_crates() -> void:
	var crate_scene: PackedScene = load("res://actors/crate.tscn")
	var loot_mult := GSBridge.loot_multiplier()
	for x in CRATE_XS:
		var c: Area2D = crate_scene.instantiate()
		c.position = Vector2(x, surface_y(x))
		crates.add_child(c)
		c.setup(distance_frac(x), loot_mult)

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
	hud.set_hint("E: bank loot" if hatch.player_inside else "")

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
	GSBridge.bank_loot(loot)

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
