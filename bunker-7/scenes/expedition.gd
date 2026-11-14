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
const RAD_NEAR := 1.5
const RAD_FAR := 4.5

# Hills: [center column, half width in columns, height in tiles]
const HILLS := [[40, 9, 2], [75, 12, 3], [110, 8, 2], [140, 14, 3], [165, 6, 1]]
# Crate x positions (px). Circuits can only appear in the far ones.
const CRATE_XS := [260, 520, 840, 1150, 1500, 1850, 2150, 2450, 2750]

var radiation := 0.0
var ended := false           # true once banking or dying has started
var surface_rows: Array[int] = []

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

# --- terrain ---------------------------------------------------------------

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
			var atlas := Vector2i(0, 0) if y <= solid_to else Vector2i(1, 0)
			ground.set_cell(Vector2i(x, y), 0, atlas)

# y (px) of the top of the ground at world x
func surface_y(x: float) -> float:
	var col := clampi(int(x / TILE), 0, COLS - 1)
	return float(surface_rows[col] * TILE)

# --- crates & pack ---------------------------------------------------------

func spawn_crates() -> void:
	var crate_scene: PackedScene = load("res://actors/crate.tscn")
	for x in CRATE_XS:
		var c: Area2D = crate_scene.instantiate()
		c.position = Vector2(x, surface_y(x))
		crates.add_child(c)
		var far := clampf((x - HATCH_X) / (WORLD_W - HATCH_X), 0.0, 1.0)
		c.setup(far, GameState.get_loot_multiplier())

# The backpack left where the player died last time. Gives items back when E is pressed.
class Pack extends Area2D:
	var items: Dictionary
	func interact(player: Node) -> void:
		if player.capacity_left() <= 0:
			player.message.emit("Backpack full!")
			return
		for kind in items.keys():
			var added: int = player.add_item(kind, items[kind])
			items[kind] -= added
			if items[kind] <= 0:
				items.erase(kind)
		if items.is_empty():
			player.message.emit("Recovered your Last Stand Pack")
			queue_free()
		else:
			player.message.emit("Pack partly recovered (backpack full)")

func spawn_last_stand_pack() -> void:
	var data: Dictionary = GameState.get_last_stand_pack()
	if data.is_empty() or not data.has("items"):
		return
	var pack := Pack.new()
	pack.items = data["items"].duplicate()
	pack.collision_layer = 4
	pack.collision_mask = 0
	var pos: Vector2 = data.get("position", Vector2(HATCH_X + 100, 0))
	pack.position = Vector2(pos.x, surface_y(pos.x))   # sit on the ground
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 18)
	shape.shape = rect
	shape.position = Vector2(0, -9)
	pack.add_child(shape)
	var glow := ColorRect.new()          # placeholder: glowing yellow backpack
	glow.color = Color(1.0, 0.9, 0.2)
	glow.position = Vector2(-5, -12)
	glow.size = Vector2(10, 12)
	pack.add_child(glow)
	add_child(pack)

# --- radiation, death, banking ---------------------------------------------

func _process(delta: float) -> void:
	if ended:
		return
	if not hatch.player_inside:
		var dist := clampf((player.position.x - HATCH_X) / (WORLD_W - HATCH_X), 0.0, 1.0)
		var rate := lerpf(RAD_NEAR, RAD_FAR, dist) * GameState.get_radiation_multiplier()
		radiation = minf(radiation + rate * delta, 100.0)
	rad_bar.value = radiation
	hint_label.text = "E: bank loot" if hatch.player_inside else ""
	if radiation >= 100.0:
		_die()

func _die() -> void:
	ended = true
	player.die()
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 1.2).set_delay(0.5)
	await player.collapse_done
	await tw.finished
	GameState.player_died(player.items.duplicate(), player.global_position)

func _on_bank_requested(p: Node) -> void:
	if ended:
		return
	ended = true
	var loot: Dictionary = p.items.duplicate()
	p.clear_items()
	GameState.bank_loot(loot)

# --- HUD -------------------------------------------------------------------

func update_hud() -> void:
	var it: Dictionary = player.items
	carry_label.text = "Carry %d/%d   wood %d  concrete %d  scrap %d  circuit %d" % [
		player.total_items(), GameState.get_carry_limit(),
		it["wood"], it["concrete"], it["scrap"], it["circuits"]]

func show_message(text: String) -> void:
	msg_label.text = text
	msg_label.modulate.a = 1.0
	if msg_tween:
		msg_tween.kill()
	msg_tween = create_tween()
	msg_tween.tween_property(msg_label, "modulate:a", 0.0, 0.6).set_delay(1.5)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event.keycode == KEY_F1:   # debug: fill radiation to test dying
			radiation = 100.0
