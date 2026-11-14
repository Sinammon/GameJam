extends Control
# Night event card: picture, title, description, two choices, then the result line and Continue.
# Picture: art/world_clean/event_<id>.png (88x64) if it exists, else the card has no picture.

var _options_box: VBoxContainer
var _result: Label
var _continue: Button

func _ready() -> void:
	UIKit.backdrop(self, "characters_clean/game_over", UIKit.BG, 0.25)   # the dark bunker at night
	var ev: Dictionary = GameState.current_event
	if ev.is_empty():
		GameState.show_overnight()
		return
	var box := UIKit.center_panel(self, UIKit.panel_style(12), 6)
	box.custom_minimum_size = Vector2(356, 0)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)
	var pic := UIKit.picture("world_clean/event_%s" % str(ev.get("id", "")))
	if pic != null:
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(pic)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	header.add_child(text)
	var align := HORIZONTAL_ALIGNMENT_LEFT if pic != null else HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(UIKit.label("NIGHT %d" % (GameState.day - 1), 8, UIKit.DIM, align))
	var title := UIKit.label(str(ev.get("title", "Something happens")), 15, UIKit.ACCENT, align)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(title)
	var desc := UIKit.label(str(ev.get("description", "")), 9, UIKit.TEXT, align)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(desc)

	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 5)
	box.add_child(_options_box)
	var options: Array = ev.get("options", [])
	var any_ok := false
	for i in options.size():
		var b := _wide_button(str(options[i].get("label", "Option %d" % (i + 1))))
		b.disabled = not GameState.can_choose_option(options[i])
		any_ok = any_ok or not b.disabled
		b.pressed.connect(_choose.bind(i))
		_options_box.add_child(b)
	if not any_ok:   # broken data safety net: never leave the player stuck
		var skip := _wide_button("Do nothing")
		skip.pressed.connect(_finish.bind("You wait for morning."))
		_options_box.add_child(skip)

	_result = UIKit.label("", 10, UIKit.GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.visible = false
	box.add_child(_result)
	_continue = _wide_button("Continue")
	_continue.visible = false
	_continue.pressed.connect(GameState.show_overnight)
	box.add_child(_continue)

func _wide_button(text: String) -> Button:
	var b := UIKit.button(text, Vector2(220, 24), 10)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b

func _choose(i: int) -> void:
	var before: Dictionary = GameState._snapshot()
	var text: String = GameState.choose_event_option(i)
	var after: Dictionary = GameState._snapshot()
	# Colour the result by what happened: green = net gain, red = net loss, grey = neutral.
	var net := 0
	for k in GameState.STAT_KEYS:
		net += int(after.get(k, 0)) - int(before.get(k, 0))
	var color := UIKit.GOOD if net > 0 else (UIKit.BAD if net < 0 else UIKit.TEXT)
	_result.add_theme_color_override("font_color", color)
	_finish(text)

func _finish(text: String) -> void:
	_options_box.visible = false
	_result.text = text
	_result.visible = true
	_continue.visible = true
