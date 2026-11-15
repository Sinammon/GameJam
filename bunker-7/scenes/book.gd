class_name CraftsBook
extends CanvasLayer
# Crafts / Book screen (V3), opened from the pause menu. Lists every item, station, recipe, place
# and tool from GuideData (scenes/guide_data.gd), which builds them from the game's own tables.
# Tabs along the top, a scrollable list below. Esc / Back closes it (emits `closed`).

signal closed

var tab := "Items"
var tab_buttons := {}          # section -> Button
var list: VBoxContainer
var scroll: ScrollContainer
var back_button: Button
var is_open := true

func _init() -> void:
	layer = 110
	name = "CraftsBook"
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(6))
	panel.position = Vector2(12, 8)
	panel.size = Vector2(456, 254)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	panel.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 3)
	v.add_child(top)
	var title := UIKit.outlined("CRAFTS / BOOK", 12, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	title.custom_minimum_size = Vector2(96, 0)
	top.add_child(title)
	for s in GuideData.SECTIONS:
		var b := UIKit.button(s, Vector2(58, 16), 8)
		b.focus_mode = Control.FOCUS_ALL
		b.toggle_mode = true
		b.pressed.connect(show_section.bind(s))
		top.add_child(b)
		tab_buttons[s] = b
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	back_button = UIKit.set_click_sfx(UIKit.button("Back (Esc)", Vector2(90, 16), 8), "ui_back")
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.focus_mode = Control.FOCUS_ALL
	back_button.pressed.connect(close)
	v.add_child(back_button)
	show_section(tab)

func show_section(section: String) -> void:
	tab = section
	for s in tab_buttons:
		(tab_buttons[s] as Button).button_pressed = s == section
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for e in GuideData.entries(section):
		list.add_child(_entry(e))
	scroll.scroll_vertical = 0
	(tab_buttons[section] as Button).grab_focus.call_deferred()

func _entry(e: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.name = "Entry_" + str(e.id)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	box.add_child(head)
	var pic := UIKit.picture("world_clean/" + UIKit.item_icon(str(e.id)))
	if pic != null:
		pic.custom_minimum_size = Vector2(12, 12)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.add_child(pic)
	head.add_child(UIKit.label(str(e.name), 9, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT))
	if str(e.where) != "":
		head.add_child(UIKit.label("- " + str(e.where), 8, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT))
	for pair in [["use", UIKit.TEXT], ["recipe", UIKit.GOOD]]:
		var t := str(e.get(pair[0], ""))
		if t == "":
			continue
		var l := UIKit.label(("Cost / recipe: " if pair[0] == "recipe" else "") + t, 8, pair[1], HORIZONTAL_ALIGNMENT_LEFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(430, 0)
		box.add_child(l)
	return box

func close() -> void:
	if not is_open:
		return
	is_open = false
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if not is_open or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	var k := event as InputEventKey
	if k and (k.physical_keycode == KEY_DOWN or k.physical_keycode == KEY_S) and not get_viewport().gui_get_focus_owner() is Button:
		scroll.scroll_vertical += 24
