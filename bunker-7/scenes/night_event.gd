extends Control
# Night event card: title, description, two choices, then the result line and Continue.

var _options_box: VBoxContainer
var _result: Label
var _continue: Button

func _ready() -> void:
	UIKit.background(self)
	var ev: Dictionary = GameState.current_event
	if ev.is_empty():
		GameState.show_overnight()
		return
	var panel := ColorRect.new()
	panel.color = UIKit.PANEL
	panel.position = Vector2(60, 24)
	panel.size = Vector2(360, 222)
	add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(12, 10)
	box.size = Vector2(336, 202)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	box.add_child(UIKit.label("NIGHT %d" % (GameState.day - 1), 8, UIKit.DIM))
	box.add_child(UIKit.label(str(ev.get("title", "Something happens")), 16, UIKit.ACCENT))
	var desc := UIKit.label(str(ev.get("description", "")), 9)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)

	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 6)
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
	_finish(GameState.choose_event_option(i))

func _finish(text: String) -> void:
	_options_box.visible = false
	_result.text = text
	_result.visible = true
	_continue.visible = true
