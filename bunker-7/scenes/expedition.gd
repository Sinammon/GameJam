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
#
# V3: one scene for every location. The layout values below are variables filled from the
# location's config (scenes/locations.gd) in _configure(): the surface keeps the V2 numbers,
# the Old Mine is a dark tunnel (rock ceiling, rope exit), the Bomb Crater a short, very
# radioactive pit (ladder exit). Hunger/thirst (scenes/survival.gd) drain outside: Q eats,
# R drinks (also the canteen slot), the medkit slot uses a bandage. The expedition still ends
# only through GSBridge.bank_loot / player_died (it reports the meters just before).

const TILE := 16
const BOTTOM_ROW := 21       # fill the ground down to here (exclusive); the last row is bedrock
const CAM_BOTTOM_MIN := 270  # camera bottom on the surface (one screen tall) ..
const CAM_BOTTOM_MAX := BOTTOM_ROW * 16   # .. follows the player down into holes

# Set from the location config (surface values shown). Upper case because they were constants in V2
# and other scripts and tests read them as ex.HATCH_X etc.
var COLS := 300              # 300 * 16 = 4800 px = 10 screens of 480
var WORLD_W := COLS * TILE
var BASE_ROW := 14           # ground surface row on flat land (y = 224)
var HATCH_COL := 150
var HATCH_X := 2408.0        # centre of the exit column (the middle of the map)
var HALF_W := 2400.0         # exit -> edge, the "how far out" scale (0..1)
var AREA_COLS := 50          # per side: near, middle, far third (suburb, market, depot on the surface)
# Hills: [column offset from the hatch, half width in columns, height in tiles].
var HILLS: Array = []
# Crate x positions (px), nearest first. Circuits only appear in the far ones
# (more than 70% of the way to an edge). On the surface the last two are the farthest.
var CRATE_XS: Array = []
var location := ""           # Locations id; "" = ask GSBridge (tests may set it before adding the scene)
var loc: Dictionary = {}     # the location config
var ceiling_rows: Array[int] = []   # per column: first open row under the rock ceiling (0 = sky)
var survival: RefCounted = null     # scenes/survival.gd (hunger / thirst)

const CrateScript := preload("res://actors/crate.gd")
const RadiationScript := preload("res://scenes/radiation.gd")
const InventoryScript := preload("res://scenes/inventory.gd")
const MiningScript := preload("res://scenes/mining.gd")
const SwingScript := preload("res://scenes/tool_swing.gd")
const SpawnerScript := preload("res://scenes/zombie_spawner.gd")
const SourceScript := preload("res://actors/source.gd")
const CritterScript := preload("res://actors/critter.gd")
const SurvivalScript := preload("res://scenes/survival.gd")
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
# below the location's min_light. darkness = DARK_DIST x distance + DARK_RAD x radiation.
# DUSK / ZONE_TINT / DARK_DIST come from the location config (surface values here).
var DUSK := Color(0.86, 0.8, 0.9)
var ZONE_TINT: Array = [Color(1.0, 0.92, 0.82), Color(0.96, 0.96, 1.0), Color(0.82, 1.0, 0.8)]   # suburb warm, market, depot green
var DARK_DIST := 0.42
const DARK_RAD := 0.3
const HATCH_LAMP := [Color(1.0, 0.72, 0.38), 1.1, 100.0, 0.12]   # colour, energy, radius, flicker
const PACK_LAMP := [Color(1.0, 0.9, 0.3), 0.8, 44.0, 1.2]        # colour, energy, radius, pulses/s
const TOXIC_GLOW := [Color(0.55, 1.0, 0.3), 0.9, 40.0, 3]       # colour, energy, radius, pool size
const RAD_LINES := ["Radiation rising. Head home.", "Radiation high! Go home now!", "Radiation sickness! Losing health!"]
const MINE_LAMP := [Color(1.0, 0.8, 0.45), 0.9, 80.0, 0.1]
const EXIT_HINT := {"hatch": "E: climb down (bank loot)", "rope": "E: climb the rope home (bank loot)", "ladder": "E: climb the ladder home (bank loot)"}
const METER_LINES := {"water": "Thirsty! Drink something (R).", "food": "Hungry! Eat something (Q)."}

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

@onready var ground: TileMapLayer = $Ground
@onready var hatch: Area2D = $Hatch
@onready var player: CharacterBody2D = $Player
@onready var crates: Node2D = $Crates
@onready var hud: CanvasLayer = $HUD
@onready var fade: ColorRect = $HUD/Fade
@onready var camera: Camera2D = $Player/Camera2D

func _ready() -> void:
	_configure()
	RenderingServer.set_default_clear_color(loc.get("sky", Color(0.35, 0.4, 0.38)))
	rad_mult = GSBridge.radiation_multiplier() * float(loc.get("rad", 1.0))
	build_background()
	mining = MiningScript.new()
	mining.name = "Mining"
	mining.ground = ground
	add_child(mining)
	use_art_tiles = build_tileset()
	if int(loc.get("ceiling", 0)) > 0 and not Art.texture("res://art/world_clean/%s.png" % str(loc.get("art", {}).get("backdrop", ""))):
		LocationDressing.cave_wall(self, mining._outside_tex, loc.get("bg_tint", Color(0.3, 0.27, 0.3)))
	mining.ore_cfg = loc.get("ores", {})
	build_terrain()
	ground.modulate = loc.get("ground_tint", Color(1, 1, 1))
	mining.setup(ground, surface_rows, player, GSBridge.loot_multiplier(), GSBridge.dig_speed_bonus())
	hatch.position = Vector2(HATCH_X, surface_y(HATCH_X))
	player.position = hatch.position + Vector2(0, -2)
	mining.protect_x(HATCH_X, 3)   # the hatch and the spawn can't be dug out
	_setup_exit()
	spawn_crates()
	spawn_last_stand_pack()
	if loc.get("trees", false):
		spawn_trees()
	spawn_sources()
	spawn_decor()
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
	inventory.tool_used.connect(_on_tool_used)
	_setup_survival()
	spawner = SpawnerScript.new()
	spawner.name = "ZombieSpawner"
	add_child(spawner)
	spawner.enabled = zombies_enabled
	spawner.setup(self)
	spawner.first_seen.connect(func() -> void: hud.hint_once("first_zombie", "Zombie! Hit it with the pickaxe or axe (left click), or outrun it."))
	hud.setup(player, inventory, rad, HATCH_X)
	hud.survival = survival
	hud.goal_text = GSBridge.goal_text()
	hud.location_name = Locations.display_name(location)
	player.hurt.connect(func(_a: int, src: String) -> void: if not src in ["radiation", "hunger", "thirst", "sickness"]: shake(3.0, 0.2))
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
	if location != "surface":
		show_message(Locations.display_name(location))

# --- location (V3) -------------------------------------------------------------

# Reads the location config into the layout variables (before anything is built).
func _configure() -> void:
	if location == "" or not Locations.has(location):
		location = GSBridge.location()
	loc = Locations.get_config(location)
	COLS = int(loc.cols)
	WORLD_W = COLS * TILE
	BASE_ROW = int(loc.base_row)
	HATCH_COL = int(loc.get("hatch_col", COLS >> 1))
	HATCH_X = HATCH_COL * TILE + 8.0
	HALF_W = (COLS >> 1) * TILE
	AREA_COLS = maxi(1, floori((COLS >> 1) / 3.0))
	HILLS = loc.get("hills", [])
	DUSK = loc.get("ambient", DUSK)
	ZONE_TINT = loc.get("zone_tint", ZONE_TINT)
	DARK_DIST = float(loc.get("dark_dist", DARK_DIST))
	CRATE_XS = loc.get("crate_xs", [])
	if CRATE_XS.is_empty():   # a count spread from near to far, alternating sides, farthest last
		var n := int(loc.get("crates", 6))
		var xs: Array = []
		for i in n:
			var f := lerpf(0.18, 0.93, float(i) / maxf(1.0, n - 1.0))
			var side := 1.0 if i % 2 == 0 else -1.0
			xs.append(roundf(HATCH_X + side * f * (HALF_W - 24.0)))
		CRATE_XS = xs

# The way home: the hatch, or a rope (mine) / ladder (crater) using the same banking Area2D.
func _setup_exit() -> void:
	var style := str(loc.get("exit", "hatch"))
	if style == "hatch" or not hatch.has_method("set_exit_style"):
		return
	hatch.set_exit_style(style)
	var top := float(ceiling_rows[HATCH_COL] * TILE) if int(loc.get("ceiling", 0)) > 0 else 0.0
	var art: Dictionary = loc.get("art", {})
	LocationDressing.exit_visual(hatch, style, str(art.get("exit", "")), hatch.position.y - top + 4.0)

# Puddles, barrels, mine pools, mushrooms (actors/source.gd) and rats (actors/critter.gd).
func spawn_sources() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("sources" + location) + GSBridge.day()
	var used := {}
	for entry in loc.get("sources", []):
		for side in [-1, 1]:
			for i in int(entry[1]):
				var col := _free_col(rng, side, int(entry[2]), int(entry[3]), used)
				if col < 0:
					continue
				var s: Area2D = SourceScript.new()
				s.setup(str(entry[0]))
				var x := col * TILE + 8.0
				s.position = Vector2(x, surface_y(x))
				add_child(s)
				mining.protect_col(col)
	var rats := int(loc.get("critters", 0))
	for side in [-1, 1]:
		for i in rats:
			var col := _free_col(rng, side, 0, 2, used)
			if col < 0:
				continue
			var c: Node2D = CritterScript.new()
			var x := col * TILE + 8.0
			c.position = Vector2(x, surface_y(x))
			c.setup(player, floor_y, 24.0, WORLD_W - 24.0, GSBridge.loot_multiplier())
			add_child(c)

# A random column on `side` in areas a0..a1, not near the exit, a crate, the pack or another source.
func _free_col(rng: RandomNumberGenerator, side: int, a0: int, a1: int, used: Dictionary) -> int:
	for attempt in 30:
		var off := rng.randi_range(maxi(a0 * AREA_COLS, 8), mini((a1 + 1) * AREA_COLS - 1, (COLS >> 1) - 3))
		var col := HATCH_COL + side * off
		if col < 2 or col >= COLS - 2 or _near_crate(col) or used.has(col) or used.has(col - 1) or used.has(col + 1):
			continue
		used[col] = true
		return col
	return -1

# Props from the location's decor list (placeholders until the real art exists).
func spawn_decor() -> void:
	for entry in loc.get("decor", []):
		var every := maxi(4, int(entry[1]))
		var col := (every >> 1) + 3
		while col < COLS - 3:
			if absi(col - HATCH_COL) > 4 and not _near_crate(col):
				var x := col * TILE + 8.0
				var ceil_y := float(ceiling_rows[col] * TILE) if int(loc.get("ceiling", 0)) > 0 else 0.0
				var n := LocationDressing.prop(self, str(entry[0]), x, surface_y(x), ceil_y)
				if n.has_meta("lamp_at"):
					n.set_meta("lamp", true)
			col += every

# --- hunger and thirst (V3, scenes/survival.gd) ------------------------------------

func _setup_survival() -> void:
	SurvivalScript.ensure_actions()
	survival = SurvivalScript.new()
	var m := GSBridge.meters()
	survival.setup(float(m.water), float(m.food))
	survival.starving_tick.connect(func(meter: String) -> void:
		if not ended:
			player.take_damage(SurvivalScript.STARVE_DAMAGE, SurvivalScript.REASON[meter]))
	survival.low.connect(func(meter: String) -> void: show_message(METER_LINES[meter]))
	var packed := GSBridge.trip_supplies()   # supplies packed in the locker start in the backpack
	for k in packed:
		if int(packed[k]) > 0:
			player.add_item(k, int(packed[k]))

# Eat (Q) or drink (R) the safest thing carried. Returns the item used ("" = nothing).
func consume(what: String) -> String:
	if ended or player.dead or player.frozen:
		return ""
	var order: Array = SurvivalScript.EAT_ORDER if what == "eat" else SurvivalScript.DRINK_ORDER
	var kind: String = SurvivalScript.best(order, player.items)
	if kind == "":
		show_message("Nothing to eat." if what == "eat" else "Nothing to drink.")
		return ""
	return use_item(kind)

# Uses one carried item (food, water, bandage...). Returns its kind, or "" if not possible.
func use_item(kind: String) -> String:
	var c: Dictionary = SurvivalScript.CONSUMABLES.get(kind, {})
	if c.is_empty() or int(player.items.get(kind, 0)) <= 0:
		return ""
	if c.has("heal") and player.health.hp >= player.health.max_hp:
		show_message("You are not hurt.")
		return ""
	player.use_item(kind)
	var line := "%s: " % kind.replace("_", " ").capitalize()
	if c.has("heal"):
		player.health.heal(int(c.heal))
		line += "+%d health" % int(c.heal)
	else:
		survival.add(str(c.meter), float(c.gain))
		line += "+%d %s" % [int(c.gain), "thirst" if c.meter == "water" else "hunger"]
	if c.has("rad"):
		radiation = minf(radiation + float(c.rad), 99.0)
		line += ", +%d%% radiation" % int(c.rad)
	if c.has("sick") and randf() < float(c.sick):
		line += ". It makes you sick!"
		player.take_damage(SurvivalScript.SICK_DAMAGE, "sickness")
	show_message(line)
	return kind

# Hotbar slots 4 and 5: the canteen drinks, the medkit uses a bandage.
func _on_tool_used(tool_id: String) -> void:
	match tool_id:
		"canteen":
			consume("drink")
		"medkit":
			if int(player.items.get("bandage", 0)) <= 0:
				show_message("No bandages. Find them in crates.")
			else:
				use_item("bandage")

func _report_meters() -> void:
	if survival:
		GSBridge.set_meters(survival.water, survival.food)

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
	# V3: a location's own backdrop picture (art/world_clean/bg_mine.png ...) when it exists;
	# else the surface art tinted (crater), or a dark rock wall behind the tunnel (mine).
	var art: Dictionary = loc.get("art", {})
	var own := Art.texture("res://art/world_clean/%s.png" % str(art.get("backdrop", ""))) if art.has("backdrop") else null
	if own:
		$Sky.visible = false
		_parallax(0.3, [own], 0.0, true, Color(1, 1, 1))
		return
	if location != "surface":
		$Sky.color = loc.get("sky", $Sky.color)
	if int(loc.get("ceiling", 0)) > 0:
		$Sky.visible = false   # the rock wall is added once the ground tiles exist (_ready)
		return
	_bg_tint = loc.get("bg_tint", Color(1, 1, 1))
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
var _bg_tint := Color(1, 1, 1)   # V3: location tint over the reused surface art

# tint darkens the layer so the player and crates stand out against it.
# mirror_from: panels whose index (mod the list) is >= this are flipped.
func _parallax(scroll: float, textures: Array, y: float, mirror: bool, tint: Color, mirror_from := -1) -> void:
	var layer := Parallax2D.new()
	layer.modulate = tint * _bg_tint
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
			_: return T_TOXIC if n == 0 or (location == "crater" and n < 4) else T_SCRAP
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
			if absi(x - HATCH_COL) <= 3 and y == surface_rows[x] and kind != "surface":
				kind = "surface"   # no ore rocks at the spawn
			var at := art_tile(x, y)
			mining.place(Vector2i(x, y), kind, at)
			if kind == "toxic" or (kind == "surface" and at == T_TOXIC):
				toxic_cells.append(Vector2i(x, y))
	# Tunnel locations: unbreakable rock above (the ceiling follows the floor, `ceiling` tiles up).
	var ceiling := int(loc.get("ceiling", 0))
	ceiling_rows.clear()
	for x in COLS:
		var top := maxi(0, surface_rows[x] - ceiling) if ceiling > 0 else 0
		ceiling_rows.append(top)
		for y in top:
			ground.set_cell(Vector2i(x, y), 1, mining.ORE_ATLAS["bedrock"])

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
	var cfg: Dictionary = loc.get("loot", {})
	var far_i := 0
	for i in CRATE_XS.size():
		if distance_frac(CRATE_XS[i]) >= distance_frac(CRATE_XS[far_i]):
			far_i = i
	for i in CRATE_XS.size():
		var x: float = CRATE_XS[i]
		var c: Area2D = crate_scene.instantiate()
		c.position = Vector2(x, surface_y(x))
		crates.add_child(c)
		c.setup(distance_frac(x), loot_mult, cfg)
		if i == far_i and loc.get("guaranteed") is Dictionary:
			c.add_guaranteed(loc.guaranteed)
		if location != "surface" and c.art == null:   # placeholder box: tint per location
			c.get_node("Sprite").color = Color(0.55, 0.5, 0.3) if location == "mine" else Color(0.45, 0.55, 0.35)
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
	if data.is_empty() or str(data.get("location", "surface")) != location:
		return   # the pack lies where you fell (another location: it waits there)
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
	if survival:
		survival.tick(delta, GSBridge.meter_drain())
	hud.set_hint(EXIT_HINT.get(str(loc.get("exit", "hatch")), EXIT_HINT.hatch) if hatch.player_inside else "")
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
	if "min_brightness" in lighting:
		lighting.min_brightness = float(loc.get("min_light", 0.35))
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
	for n in get_children():   # mine lamps (decor placeholders or art)
		if n.has_meta("lamp"):
			var ml: Node2D = script.add_lamp(n, n.get_meta("lamp_at"), MINE_LAMP[0], MINE_LAMP[1], MINE_LAMP[2], MINE_LAMP[3])
			ml.name = "MineLamp"
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
	_report_meters()
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
	_report_meters()
	GSBridge.bank_loot(loot)   # banks once now; GameState changes the scene after the climb
	_climb_down(p)

# The survivor climbs down the hatch ladder while the screen fades to black.
func _climb_down(p: Node) -> void:
	if hatch.has_method("hold_open"):
		hatch.hold_open()   # obj_hatch_open.png, drawn over the survivor
	if p.has_method("climb_into"):
		var depth := CLIMB_DEPTH if str(loc.get("exit", "hatch")) == "hatch" else -CLIMB_DEPTH * 2.0   # rope / ladder: up
		p.climb_into(Vector2(hatch.global_position.x, hatch.global_position.y - 1.0), depth, CLIMB_TIME)
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
	if event.is_action_pressed("eat") and not event.is_echo():
		get_viewport().set_input_as_handled()
		consume("eat")
		return
	if event.is_action_pressed("drink") and not event.is_echo():
		get_viewport().set_input_as_handled()
		consume("drink")
		return
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:   # fill radiation to test the health drain
			radiation = 100.0
