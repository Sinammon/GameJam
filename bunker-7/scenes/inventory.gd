extends Node
# Terraria-style inventory for the expedition.
# - Hotbar: 5 tool slots (always present), picked with 1-5 or the mouse wheel.
#   Left click (`attack`) emits tool_used(tool_id) for the selected tool; trees,
#   mining and combat hook into that signal later.
# - Backpack: Tab toggles the grid. Materials are shown as stacks.
#   The player's `items` dict stays the single source of truth (it is what is
#   banked or dropped on death). The carry limit counts items, as before
#   (GSBridge.carry_limit()); the grid shows that many unlocked slots, and the
#   backpack tier only sets how big the whole grid is (locked slots show a padlock).

signal selection_changed(index: int)
signal tool_used(tool_id: String)
signal backpack_toggled(open: bool)

const TOOLS := ["axe", "pickaxe", "flashlight", "canteen", "medkit"]
const TIER_SLOTS := [12, 16, 20, 24]     # backpack tiers 1..4
const MATERIALS := ["wood", "concrete", "scrap", "circuits", "water", "food",
	"canned_food", "dirty_water", "raw_meat", "mushroom", "bandage", "radio_part"]

var player: Node = null
var selected := 0
var backpack_open := false
var tier := 1

func setup(p: Node) -> void:
	player = p
	tier = clampi(GSBridge.backpack_tier(), 1, TIER_SLOTS.size())

func selected_tool() -> String:
	return TOOLS[selected]

func select(index: int) -> void:
	var i := posmod(index, TOOLS.size())
	if i == selected:
		return
	selected = i
	selection_changed.emit(i)

func toggle_backpack() -> void:
	backpack_open = not backpack_open
	backpack_toggled.emit(backpack_open)

# Unlocked slots = the carry limit. The grid is at least as big as the tier says.
func slots_unlocked() -> int:
	return player.carry_limit if player else 12

func slots_total() -> int:
	return maxi(TIER_SLOTS[tier - 1], slots_unlocked())

func used() -> int:
	return player.total_items() if player else 0

# [[kind, count], ...] in a fixed order, only kinds that are carried.
func stacks() -> Array:
	var out := []
	if player == null:
		return out
	for k in MATERIALS:
		var n: int = player.items.get(k, 0)
		if n > 0:
			out.append([k, n])
	return out

func _blocked() -> bool:
	return player == null or player.dead or player.frozen

func _unhandled_input(event: InputEvent) -> void:
	if _blocked():
		return
	for i in TOOLS.size():
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			select(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("inventory"):
		toggle_backpack()
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			select(selected - 1)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select(selected + 1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("attack"):
		tool_used.emit(selected_tool())
		get_viewport().set_input_as_handled()
