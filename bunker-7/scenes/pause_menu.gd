class_name PauseMenu
extends CanvasLayer
# Pause menu with settings. Add it to any scene:
#
#   add_child(preload("res://scenes/pause_menu.tscn").instantiate())
#
# Esc ("pause" action, or ui_cancel if that action does not exist) opens and closes it and
# pauses the game while it is open. Connect show_tutorial if you want to open the slideshow
# yourself; otherwise the menu opens its own.

signal show_tutorial
signal resumed
signal settings_changed(key: String, value: Variant)

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const ACTION := &"pause"

## Set false to ignore the pause key (for example during a cutscene).
var enabled: bool = true
var is_open: bool = false

var main_page: VBoxContainer
var settings_page: VBoxContainer
var resume_button: Button
var settings_button: Button
var tutorial_button: Button
var book_button: Button
var book: CanvasLayer = null      # scenes/book.gd while open
var menu_button: Button
var quit_button: Button
var music_slider: HSlider
var sfx_slider: HSlider
var fullscreen_check: CheckBox
var lights_option: OptionButton
var back_button: Button

var _root: Control
var _was_paused: bool = false
var _music_value: Label
var _sfx_value: Label

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	SettingsStore.apply()

# The key that toggles the menu.
static func toggle_action() -> StringName:
	return ACTION if InputMap.has_action(ACTION) else &"ui_cancel"

# ---------------------------------------------------------------- building

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(12))
	center.add_child(panel)
	var holder := VBoxContainer.new()
	panel.add_child(holder)

	# Main page
	main_page = VBoxContainer.new()
	main_page.add_theme_constant_override("separation", 5)
	holder.add_child(main_page)
	main_page.add_child(UIKit.outlined("PAUSED", 16, UIKit.ACCENT))
	resume_button = _button(main_page, "Resume", _on_resume)
	settings_button = _button(main_page, "Settings", open_settings)
	tutorial_button = _button(main_page, "Tutorial", _on_tutorial)
	book_button = _button(main_page, "Crafts / Book", open_book)
	menu_button = _button(main_page, "Main menu", _on_main_menu)
	quit_button = _button(main_page, "Quit", _on_quit)
	quit_button.visible = not OS.has_feature("web")

	# Settings page
	settings_page = VBoxContainer.new()
	settings_page.add_theme_constant_override("separation", 5)
	settings_page.visible = false
	holder.add_child(settings_page)
	settings_page.add_child(UIKit.outlined("SETTINGS", 16, UIKit.ACCENT))
	music_slider = _slider_row("Music volume", float(SettingsStore.get_value("music_volume")), "music_volume")
	_music_value = music_slider.get_meta("value_label")
	sfx_slider = _slider_row("Effects volume", float(SettingsStore.get_value("sfx_volume")), "sfx_volume")
	_sfx_value = sfx_slider.get_meta("value_label")

	var fs_row := HBoxContainer.new()
	settings_page.add_child(fs_row)
	fs_row.add_child(_row_label("Fullscreen"))
	fullscreen_check = CheckBox.new()
	fullscreen_check.text = "On"
	fullscreen_check.add_theme_font_size_override("font_size", UIKit.fs(9))
	fullscreen_check.button_pressed = bool(SettingsStore.get_value("fullscreen"))
	fullscreen_check.toggled.connect(_on_fullscreen)
	fs_row.add_child(fullscreen_check)

	var lq_row := HBoxContainer.new()
	settings_page.add_child(lq_row)
	lq_row.add_child(_row_label("Lights quality"))
	lights_option = OptionButton.new()
	lights_option.add_theme_font_size_override("font_size", UIKit.fs(9))
	lights_option.custom_minimum_size = Vector2(90, 16)
	for q in SettingsStore.LIGHTS_QUALITIES:
		lights_option.add_item(str(q).capitalize())
	lights_option.select(maxi(SettingsStore.LIGHTS_QUALITIES.find(SettingsStore.get_value("lights_quality")), 0))
	lights_option.item_selected.connect(_on_lights)
	lq_row.add_child(lights_option)

	back_button = _button(settings_page, "Back", close_settings)

func _button(parent: Control, text: String, handler: Callable) -> Button:
	var b := UIKit.button(text, Vector2(150, 22), 10)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(handler)
	parent.add_child(b)
	return b

func _row_label(text: String) -> Label:
	var l := UIKit.label(text, 9, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(90, 0)
	return l

func _slider_row(text: String, value: float, key: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	settings_page.add_child(row)
	row.add_child(_row_label(text))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(100, 14)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	row.add_child(s)
	var v := UIKit.label("%d%%" % roundi(value * 100.0), 9, UIKit.DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	v.custom_minimum_size = Vector2(28, 0)
	row.add_child(v)
	s.set_meta("value_label", v)
	s.value_changed.connect(_on_slider.bind(key, v))
	return s

# ---------------------------------------------------------------- open / close

func _tutorial_is_open() -> bool:
	# Another full-screen overlay (the tutorial) handles Esc itself.
	return not get_tree().get_nodes_in_group("tutorial_open").is_empty()

func _input(event: InputEvent) -> void:
	if not enabled or not event.is_pressed() or event.is_echo():
		return
	var toggled := event.is_action_pressed(toggle_action())
	var back := is_open and event.is_action_pressed(&"ui_cancel")
	if not (toggled or back):
		return
	if _tutorial_is_open():
		return
	get_viewport().set_input_as_handled()
	if book != null and is_instance_valid(book):
		book.close()   # Esc closes the book first, back to the menu
		return
	if not is_open:
		open()
	elif settings_page.visible:
		close_settings()
	else:
		close()

func open() -> void:
	if is_open:
		return
	is_open = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	main_page.visible = true
	settings_page.visible = false
	_root.visible = true
	resume_button.grab_focus()

func close() -> void:
	if not is_open:
		return
	if book != null and is_instance_valid(book):
		book.close()
	is_open = false
	_root.visible = false
	get_tree().paused = _was_paused
	resumed.emit()

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open_settings() -> void:
	main_page.visible = false
	settings_page.visible = true
	music_slider.grab_focus()

func close_settings() -> void:
	settings_page.visible = false
	main_page.visible = true
	settings_button.grab_focus()

# Crafts / Book: every item, station, recipe and place (scenes/book.gd, data from GuideData).
func open_book() -> void:
	if book != null and is_instance_valid(book):
		return
	book = load("res://scenes/book.gd").new()
	add_child(book)
	book.closed.connect(_on_book_closed)

func _on_book_closed() -> void:
	book = null
	if is_open and book_button != null:
		book_button.grab_focus.call_deferred()

# ---------------------------------------------------------------- button handlers

func _on_resume() -> void:
	close()

func _on_tutorial() -> void:
	show_tutorial.emit()
	if get_signal_connection_list("show_tutorial").is_empty():
		var t := Tutorial.open(self)
		t.finished.connect(_focus_after_tutorial)

func _focus_after_tutorial() -> void:
	if is_open and tutorial_button != null:
		tutorial_button.grab_focus()

func _on_main_menu() -> void:
	is_open = false
	_root.visible = false
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _on_quit() -> void:
	get_tree().quit()

# ---------------------------------------------------------------- settings handlers

func _on_slider(value: float, key: String, value_label: Label) -> void:
	value_label.text = "%d%%" % roundi(value * 100.0)
	_changed(key, value)

func _on_fullscreen(on: bool) -> void:
	SettingsStore.set_value("fullscreen", on)
	SettingsStore.apply(true)
	settings_changed.emit("fullscreen", on)

func _on_lights(i: int) -> void:
	_changed("lights_quality", SettingsStore.LIGHTS_QUALITIES[i])

func _changed(key: String, value: Variant) -> void:
	SettingsStore.set_value(key, value)
	SettingsStore.apply(true)
	settings_changed.emit(key, value)
