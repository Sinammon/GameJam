extends Control
# Morning screen (optional since the walkable bunker): shows the state of the run and the "Go Outside" button.
# New days now start in the bunker (GameState.start_day); this screen still works if opened directly.

var _title: Label
var _bounces: HBoxContainer
var _stats: HBoxContainer
var _materials: HBoxContainer
var _note: Label
var _goal: Label
var _go: Button
var _wait: Button
var _box: VBoxContainer

func _ready() -> void:
	UIKit.backdrop(self, "characters_clean/title_art", UIKit.BG, 0.35)
	_box = UIKit.center_panel(self, UIKit.panel_style(12), 7)
	_title = UIKit.outlined("", 22, UIKit.ACCENT)
	_box.add_child(_title)
	_bounces = HBoxContainer.new()
	_box.add_child(_bounces)
	_stats = HBoxContainer.new()
	_box.add_child(_stats)
	_materials = HBoxContainer.new()
	_box.add_child(_materials)

	_goal = UIKit.outlined("", 9, UIKit.ACCENT)
	_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal.custom_minimum_size = Vector2(300, 0)
	_box.add_child(_goal)
	_note = UIKit.outlined("", 9, UIKit.BAD)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(300, 0)
	_box.add_child(_note)

	_go = UIKit.button("Go Outside", Vector2(160, 28), 12)
	_go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_go.pressed.connect(_go_outside)
	_box.add_child(_go)
	_wait = UIKit.button("Wait inside", Vector2(160, 24), 10)
	_wait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_wait.pressed.connect(_wait_inside)
	_box.add_child(_wait)

	if OS.is_debug_build():
		var cheats := UIKit.label("cheats: F2/7 +10 materials   F3/8 skip day   F4/9 +bounce", 7, UIKit.DIM)
		cheats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cheats.custom_minimum_size = Vector2(240, 0)
		_box.add_child(cheats)

	GameState.changed.connect(_refresh)
	_refresh()

# Swap an icon row in place (rows are rebuilt on every refresh).
func _set_row(old: HBoxContainer, items: Array, font_size: int) -> HBoxContainer:
	var row := UIKit.icon_row(items, font_size, 12)
	_box.add_child(row)
	_box.move_child(row, old.get_index())
	old.queue_free()
	return row

func _refresh() -> void:
	var gs := GameState
	_title.text = "DAY %d / %d" % [gs.day, gs.MAX_DAY]
	_bounces = _set_row(_bounces, [["icon_bounce", "", "Bounces left: %d" % gs.bounces, UIKit.BAD]], 11)
	_stats = _set_row(_stats, [
		["icon_health", "Health", "%d/%d" % [gs.health, gs.MAX_HEALTH]],
		["icon_water", "Water", str(gs.water)],
		["icon_food", "Food", str(gs.food)]], 11)
	_materials = _set_row(_materials, [
		["icon_wood", "Wood", str(gs.wood), UIKit.DIM],
		["icon_concrete", "Concrete", str(gs.concrete), UIKit.DIM],
		["icon_scrap", "Scrap", str(gs.scrap), UIKit.DIM],
		["icon_circuits", "Circuits", str(gs.circuits), UIKit.DIM]], 11)
	_goal.text = gs.get_goal_text()
	_goal.visible = _goal.text != ""
	var notes: PackedStringArray = []
	if DayPlan.note_text(gs.day) != "":
		notes.append(DayPlan.note_text(gs.day))
	elif gs.tomorrow_rad_mult > 1.0:
		notes.append("Storm: radiation x%s today" % str(gs.tomorrow_rad_mult))
	if gs.bonus_crate:
		notes.append("Stranger's supplies: +50% loot today")
	_note.text = " ".join(notes)
	_note.visible = not notes.is_empty()
	_go.disabled = gs.skip_expedition
	_go.text = "Storm outside: stay in" if gs.skip_expedition else "Go Outside"
	_wait.visible = gs.skip_expedition

func _go_outside() -> void:
	_go.disabled = true
	if not GameState.go_outside():
		_go.disabled = false

func _wait_inside() -> void:
	_wait.disabled = true   # one night per click
	GameState.wait_inside()
