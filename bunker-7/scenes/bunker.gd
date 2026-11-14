extends Control
# Evening in the bunker: side-view cutaway of the five rooms, unlock / build / repair, then Sleep.
# All rules live in GameState; this screen only calls can_*/unlock_room/build/repair_room.

const ROOM_W := 92
const ROOM_GAP := 3
const ROOM_TOP := 20
const ROOM_H := 212

const ROOM_COLORS := {
	"bedroom": Color(0.30, 0.24, 0.20),
	"utility": Color(0.22, 0.27, 0.30),
	"garden":  Color(0.20, 0.30, 0.20),
	"storage": Color(0.29, 0.27, 0.20),
	"radio":   Color(0.26, 0.21, 0.30),
}
const BUILDING_COLORS := {
	"cot":      Color(0.55, 0.40, 0.30),
	"door":     Color(0.50, 0.50, 0.55),
	"purifier": Color(0.30, 0.55, 0.80),
	"filter":   Color(0.60, 0.65, 0.65),
	"garden":   Color(0.35, 0.70, 0.35),
	"radio":    Color(0.85, 0.55, 0.25),
}
const LOCKED_COLOR := Color(0.11, 0.09, 0.07)   # packed dirt

var _hud: Label
var _rooms_root: Control

func _ready() -> void:
	UIKit.background(self, Color(0.16, 0.12, 0.09))
	var strip := ColorRect.new()
	strip.color = UIKit.PANEL
	strip.position = Vector2.ZERO
	strip.size = Vector2(480, 16)
	add_child(strip)
	_hud = UIKit.label("", 8)
	_hud.position = Vector2(0, 2)
	_hud.size = Vector2(480, 12)
	add_child(_hud)

	_rooms_root = Control.new()
	_rooms_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rooms_root)

	var sleep := UIKit.button("Sleep", Vector2(120, 24), 10)
	sleep.position = Vector2(180, 240)
	sleep.pressed.connect(_sleep)
	add_child(sleep)

	GameState.changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	var gs := GameState
	_hud.text = "Day %d/%d   Bounces %d   Health %d/%d   Water %d   Food %d   Wood %d  Concrete %d  Scrap %d  Circuits %d" % [
		gs.day, gs.MAX_DAY, gs.bounces, gs.health, gs.MAX_HEALTH, gs.water, gs.food,
		gs.wood, gs.concrete, gs.scrap, gs.circuits]
	for c in _rooms_root.get_children():
		c.queue_free()
	for i in GameState.ROOM_ORDER.size():
		_add_room(GameState.ROOM_ORDER[i], 4 + i * (ROOM_W + ROOM_GAP))

func _add_room(id: String, x: int) -> void:
	var gs := GameState
	var unlocked: bool = gs.is_room_unlocked(id)
	var rect := ColorRect.new()
	rect.color = ROOM_COLORS[id] if unlocked else LOCKED_COLOR
	rect.position = Vector2(x, ROOM_TOP)
	rect.size = Vector2(ROOM_W, ROOM_H)
	_rooms_root.add_child(rect)

	var box := VBoxContainer.new()
	box.position = Vector2(3, 3)
	box.size = Vector2(ROOM_W - 6, ROOM_H - 6)
	box.add_theme_constant_override("separation", 3)
	rect.add_child(box)
	box.add_child(UIKit.label(gs.ROOMS[id].name, 8, UIKit.ACCENT if unlocked else UIKit.DIM))

	if not unlocked:
		box.add_child(UIKit.label("Locked", 8, UIKit.DIM))
		if id == "storage":
			box.add_child(UIKit.label("Unlock to carry\n16 items (now 12)", 7, UIKit.DIM))
		_spacer(box)
		var cost: Dictionary = gs.ROOMS[id].cost
		var b := _small_button("Unlock\n" + _cost_lines(cost))
		b.disabled = not gs.can_unlock(id)
		b.pressed.connect(func(): GameState.unlock_room(id))
		box.add_child(b)
		return

	if gs.is_room_damaged(id):
		box.add_child(UIKit.label("Damaged", 8, UIKit.BAD))
		var r := _small_button("Repair\n" + _cost_lines(gs.REPAIR_COST))
		r.disabled = not gs.can_repair(id)
		r.pressed.connect(func(): GameState.repair_room(id))
		box.add_child(r)
	if id == "storage":
		box.add_child(UIKit.label("Carry limit\n%d items" % gs.get_carry_limit(), 7, UIKit.GOOD))

	# Built things, drawn as colored blocks.
	if id == "bedroom":
		_building_block(box, "cot", "Cot")
	for b_id in gs.buildings_in(id):
		if gs.is_built(b_id):
			_building_block(box, b_id, gs.BUILDINGS[b_id].name)

	_spacer(box)
	# Build menu for the buildings that are not built yet.
	for b_id in gs.buildings_in(id):
		if gs.is_built(b_id):
			continue
		var b := _small_button("%s\n%s" % [gs.BUILDINGS[b_id].name, _cost_lines(gs.BUILDINGS[b_id].cost)])
		b.disabled = not gs.can_build(b_id)
		b.pressed.connect(func(): GameState.build(b_id))
		box.add_child(b)

func _building_block(box: VBoxContainer, b_id: String, text: String) -> void:
	var block := ColorRect.new()
	block.color = BUILDING_COLORS[b_id]
	if GameState.is_room_damaged(GameState.BUILDINGS[b_id].room if GameState.BUILDINGS.has(b_id) else "bedroom"):
		block.color = block.color.darkened(0.5)
	block.custom_minimum_size = Vector2(0, 20)
	var l := UIKit.label(text, 7, Color(0.05, 0.05, 0.05))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	block.add_child(l)
	box.add_child(block)

func _small_button(text: String) -> Button:
	var b := UIKit.button(text, Vector2(ROOM_W - 6, 24), 7)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return b

func _spacer(box: VBoxContainer) -> void:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(s)

# "6 wood\n6 concrete" -> joined with spaces, short enough for a narrow button
func _cost_lines(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts: PackedStringArray = []
	for kind in GameState.ITEM_KINDS:
		if cost.has(kind):
			parts.append("%d %s" % [int(cost[kind]), kind])
	return " ".join(parts)

func _sleep() -> void:
	GameState.sleep()
