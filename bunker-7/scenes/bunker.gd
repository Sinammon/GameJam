extends Control
# Evening in the bunker: side-view cutaway of the five rooms, unlock / build / repair, then Sleep.
# All rules live in GameState; this screen only calls can_*/unlock_room/build/repair_room.
# Rooms are 234x78 cells in a 2-column grid; the 6th cell holds the Sleep button.
# Art: art/world_clean/room_*.png, bld_*.png, icon_*.png (flat placeholder colours if missing).

const ROOM_W := 234
const ROOM_H := 78
const ROOM_GAP := 3
const ROOM_TOP := 20
const ROOM_LEFT := 4
const FLOOR_Y := 71          # where buildings stand inside a room picture
const BUTTON_W := 90          # build / unlock / repair column on the right of each room

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
# Left edge of each building inside its room (room pictures leave these floor spots free).
const BUILDING_X := {"cot": 50, "door": 118, "purifier": 40, "filter": 76, "garden": 60, "radio": 64}
const PLACEHOLDER_SIZE := Vector2(26, 22)
const LOCKED_COLOR := Color(0.11, 0.09, 0.07)   # packed dirt

var _hud: HBoxContainer
var _rooms_root: Control

func _ready() -> void:
	UIKit.background(self, Color(0.16, 0.12, 0.09))
	var dirt := UIKit.tex("world_clean/tiles_bunker_dirt_packed")
	if dirt != null:   # packed earth around the rooms
		var fill := TextureRect.new()
		fill.texture = dirt
		fill.stretch_mode = TextureRect.STRETCH_TILE
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
		fill.modulate = Color(0.55, 0.5, 0.5)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)
	var strip := ColorRect.new()
	strip.color = UIKit.PANEL
	strip.position = Vector2.ZERO
	strip.size = Vector2(480, 18)
	add_child(strip)

	_rooms_root = Control.new()
	_rooms_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rooms_root)

	var cell := _cell_rect(5)   # free 6th cell: Sleep
	var sleep := UIKit.button("Sleep", Vector2(120, 26), 11)
	sleep.position = cell.position + Vector2((ROOM_W - 120) / 2.0, 30)
	sleep.pressed.connect(_sleep)
	add_child(sleep)
	var hint := UIKit.outlined("Unlock rooms, build, then sleep.\nThe night may bring trouble.", 7, UIKit.DIM)
	hint.position = cell.position + Vector2(0, 2)
	hint.size = Vector2(ROOM_W, 24)
	add_child(hint)

	GameState.changed.connect(_refresh)
	_refresh()

func _cell_rect(i: int) -> Rect2:
	var col := i % 2
	var row := i / 2
	return Rect2(ROOM_LEFT + col * (ROOM_W + ROOM_GAP + 1), ROOM_TOP + row * (ROOM_H + ROOM_GAP), ROOM_W, ROOM_H)

func _refresh() -> void:
	var gs := GameState
	if _hud != null:
		_hud.queue_free()
	_hud = UIKit.icon_row([
		["icon_day", "Day", "%d/%d" % [gs.day, gs.MAX_DAY]],
		["icon_bounce", "Bounces", str(gs.bounces)],
		["icon_health", "Health", "%d/%d" % [gs.health, gs.MAX_HEALTH]],
		["icon_water", "Water", str(gs.water)],
		["icon_food", "Food", str(gs.food)],
		["icon_wood", "Wood", str(gs.wood)],
		["icon_concrete", "Concrete", str(gs.concrete)],
		["icon_scrap", "Scrap", str(gs.scrap)],
		["icon_circuits", "Circuits", str(gs.circuits)]], 8, 9)
	_hud.position = Vector2(0, 1)
	_hud.size = Vector2(480, 16)
	add_child(_hud)
	for c in _rooms_root.get_children():
		c.queue_free()
	for i in GameState.ROOM_ORDER.size():
		_add_room(GameState.ROOM_ORDER[i], _cell_rect(i))

func _room_picture(name: String, fallback: Color, rect: Rect2) -> Control:
	var pic := UIKit.picture("world_clean/" + name)
	if pic == null:
		var c := ColorRect.new()
		c.color = fallback
		c.position = rect.position
		c.size = rect.size
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return c
	pic.position = rect.position
	pic.size = rect.size
	return pic

func _add_room(id: String, rect: Rect2) -> void:
	var gs := GameState
	var unlocked: bool = gs.is_room_unlocked(id)
	var room := _room_picture("room_" + id if unlocked else "room_locked",
			ROOM_COLORS[id] if unlocked else LOCKED_COLOR, rect)
	_rooms_root.add_child(room)

	var info := VBoxContainer.new()   # name and short notes, top-left
	info.position = Vector2(10, 7)
	info.size = Vector2(ROOM_W - BUTTON_W - 20, 40)
	info.add_theme_constant_override("separation", 0)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.add_child(info)
	info.add_child(UIKit.outlined(gs.ROOMS[id].name, 8, UIKit.ACCENT if unlocked else UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT))

	var buttons := VBoxContainer.new()   # actions, right column
	buttons.position = Vector2(ROOM_W - BUTTON_W - 8, 7)
	buttons.size = Vector2(BUTTON_W, ROOM_H - 14)
	buttons.add_theme_constant_override("separation", 2)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	room.add_child(buttons)

	if not unlocked:
		info.add_child(UIKit.outlined("Locked", 7, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT))
		if id == "storage":
			info.add_child(UIKit.outlined("Unlock to carry\n16 items (now 12)", 7, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT))
		var cost: Dictionary = gs.ROOMS[id].cost
		var b := _small_button("Unlock\n" + _cost_lines(cost))
		b.disabled = not gs.can_unlock(id)
		b.pressed.connect(func(): GameState.unlock_room(id))
		buttons.add_child(b)
		return

	var damaged: bool = gs.is_room_damaged(id)
	if damaged:
		var cracks := UIKit.picture("world_clean/room_damaged_overlay")
		if cracks != null:
			cracks.size = rect.size
			room.add_child(cracks)
			room.move_child(cracks, 0)   # under the labels and buttons
		info.add_child(UIKit.outlined("Damaged", 8, UIKit.BAD, HORIZONTAL_ALIGNMENT_LEFT))
		var r := _small_button("Repair\n" + _cost_lines(gs.REPAIR_COST))
		r.disabled = not gs.can_repair(id)
		r.pressed.connect(func(): GameState.repair_room(id))
		buttons.add_child(r)
	if id == "storage":
		info.add_child(UIKit.outlined("Carry limit %d items" % gs.get_carry_limit(), 7, UIKit.GOOD, HORIZONTAL_ALIGNMENT_LEFT))

	# Built things standing on the floor.
	if id == "bedroom":
		_building(room, "cot", "Cot", damaged)
	for b_id in gs.buildings_in(id):
		if gs.is_built(b_id):
			_building(room, b_id, gs.BUILDINGS[b_id].name, damaged)

	# Build menu for the buildings that are not built yet.
	for b_id in gs.buildings_in(id):
		if gs.is_built(b_id):
			continue
		var b := _small_button("%s\n%s" % [gs.BUILDINGS[b_id].name, _cost_lines(gs.BUILDINGS[b_id].cost)])
		b.disabled = not gs.can_build(b_id)
		b.tooltip_text = str(gs.BUILDINGS[b_id].get("desc", ""))
		b.pressed.connect(func(): GameState.build(b_id))
		buttons.add_child(b)

func _building(room: Control, b_id: String, text: String, damaged: bool) -> void:
	var node: Control = UIKit.picture("world_clean/bld_" + b_id)
	if node == null:   # placeholder block with the name on it
		var block := ColorRect.new()
		block.color = BUILDING_COLORS[b_id]
		block.size = PLACEHOLDER_SIZE
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UIKit.label(text, 7, Color(0.05, 0.05, 0.05))
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		block.add_child(l)
		node = block
	node.position = Vector2(BUILDING_X.get(b_id, 40), FLOOR_Y - node.size.y)
	node.tooltip_text = text if b_id == "cot" else "%s: %s" % [text, gs_desc(b_id)]
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	if damaged:
		node.modulate = Color(0.5, 0.45, 0.45)
	room.add_child(node)
	room.move_child(node, 0)   # behind labels and buttons

func gs_desc(b_id: String) -> String:
	return str(GameState.BUILDINGS[b_id].get("desc", ""))

func _small_button(text: String) -> Button:
	var b := UIKit.button(text, Vector2(BUTTON_W, 21), 7)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_constant_override("line_spacing", -2)
	return b

# "6 wood\n6 concrete" -> joined with spaces, short enough for a narrow button
func _cost_lines(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts: PackedStringArray = []
	for kind in GameState.ITEM_KINDS:
		if cost.has(kind):
			parts.append("%d %s" % [int(cost[kind]), kind])
	return " ".join(parts)

var _slept := false

func _sleep() -> void:
	if _slept:   # one night per click, even if the scene change is still pending
		return
	_slept = true
	GameState.sleep()
