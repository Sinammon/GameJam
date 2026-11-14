extends Node2D
# The outside level: tile world, hatch, crates, radiation timer, HUD.
# This scene never changes scenes. It only calls GameState.bank_loot / player_died.

const TILE := 16
const COLS := 180            # 180 * 16 = 2880 px = 6 screens of 480
const WORLD_W := COLS * TILE
const BASE_ROW := 14         # ground surface row on flat land (y = 224)
const BOTTOM_ROW := 19       # fill dirt down to here
const HATCH_X := 48.0

# Radiation per second (percent). Grows the further right of the hatch you are.
# Tuned so a straight round trip to the farthest crate (~54 s of walking at
# 100 px/s) costs about 85% on Normal: possible, but no time to dawdle.
const RAD_NEAR := 0.8
const RAD_FAR := 2.4

# Hills: [center column, half width in columns, height in tiles]
const HILLS := [[40, 9, 2], [75, 12, 3], [110, 8, 2], [140, 14, 3], [165, 6, 1]]
# Crate x positions (px). Circuits can only appear in the far ones.
const CRATE_XS := [260, 520, 840, 1150, 1500, 1850, 2150, 2450, 2750]

const CrateScript := preload("res://actors/crate.gd")

var radiation := 0.0
var ended := false           # true once banking or dying has started (only one may ever run)
var rad_mult := 1.0
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
const AREA_COLS := 60        # suburb | market | depot, one third of the map each

@onready var ground: TileMapLayer = $Ground
@onready var hatch: Area2D = $Hatch
@onready var player: CharacterBody2D = $Player
@onready var crates: Node2D = $Crates
@onready var rad_bar: ProgressBar = $HUD/RadBar
@onready var carry_label: Label = $HUD/CarryLabel
@onready var msg_label: Label = $HUD/MessageLabel
@onready var hint_label: Label = $HUD/HintLabel
@onready var fade: ColorRect = $HUD/Fade

var msg_tween: Tween

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
	hatch.bank_requested.connect(_on_bank_requested)
	player.message.connect(show_message)
	player.items_changed.connect(update_hud)
	update_hud()
	msg_label.text = ""

# --- background --------------------------------------------------------------

# Parallax layers, back to front. The camera never moves vertically (the world is
# one screen tall), so only x scrolls. Near layers: one panel per area, side by
# side, scroll 0.8 so all three are crossed over the 2880 px level.
# far: mirrored copies so the repeat is seamless. Missing textures are skipped
# and the plain Sky rect stays.
func build_background() -> void:
	var sky := Art.texture("res://art/world_clean/bg_sky.png")
	if sky:
		$Sky.visible = false
		_parallax(0.1, [sky], 0.0, false, Color(1, 1, 1))
	var far := Art.texture("res://art/world_clean/bg_far.png")
	if far:
		_parallax(0.4, [far], -14.0, true, Color(0.8, 0.75, 0.75))
	var near: Array[Texture2D] = []
	for area in ["suburb", "market", "depot"]:
		var t := Art.texture("res://art/world_clean/bg_near_%s.png" % area)
		if t:
			near.append(t)
	if near.size() == 3:
		_parallax(0.8, near, -26.0, false, Color(0.62, 0.58, 0.6))

var _bg_layers := 0

# tint darkens the layer so the player and crates stand out against it.
func _parallax(scroll: float, textures: Array, y: float, mirror: bool, tint: Color) -> void:
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
		s.flip_h = mirror and i % 2 == 1
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
		match x / AREA_COLS:
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
			h = maxi(h, int(hill[2] - absf(x - hill[0]) / slope))
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
		var far := clampf((x - HATCH_X) / (WORLD_W - HATCH_X), 0.0, 1.0)
		c.setup(far, loot_mult)

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

func _process(delta: float) -> void:
	if ended:
		return   # no radiation during the death fade or after banking
	if not hatch.player_inside:
		var dist := clampf((player.position.x - HATCH_X) / (WORLD_W - HATCH_X), 0.0, 1.0)
		var rate := lerpf(RAD_NEAR, RAD_FAR, dist) * rad_mult
		radiation = minf(radiation + rate * delta, 100.0)
	rad_bar.value = radiation
	hint_label.text = "E: bank loot" if hatch.player_inside else ""
	if radiation >= 100.0:
		_die()

func _die() -> void:
	if ended:
		return
	ended = true
	hint_label.text = ""
	var items: Dictionary = player.items.duplicate()   # snapshot at the moment of death
	var where: Vector2 = player.global_position
	player.die()
	# One sequence: wait for the collapse, then fade. (Awaiting two signals in a
	# row can hang forever if the second one already fired.)
	await player.collapse_done
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 1.0)
	await tw.finished
	GSBridge.player_died(items, where)

func _on_bank_requested(p: Node) -> void:
	if ended:
		return
	ended = true
	hint_label.text = ""
	p.frozen = true
	var loot: Dictionary = p.items.duplicate()
	p.clear_items()
	GSBridge.bank_loot(loot)

# --- HUD -------------------------------------------------------------------

func update_hud() -> void:
	var it: Dictionary = player.items
	carry_label.text = "Carry %d/%d   wood %d  concrete %d  scrap %d  circuit %d  water %d  food %d" % [
		player.total_items(), player.carry_limit,
		it["wood"], it["concrete"], it["scrap"], it["circuits"], it["water"], it["food"]]

func show_message(text: String) -> void:
	msg_label.text = text
	msg_label.modulate.a = 1.0
	if msg_tween:
		msg_tween.kill()
	msg_tween = create_tween()
	msg_tween.tween_property(msg_label, "modulate:a", 0.0, 0.6).set_delay(1.5)

# Debug keys, only in debug builds (editor / debug export), never in the shipped game.
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event.keycode == KEY_F1:   # fill radiation to test dying
			radiation = 100.0
