class_name BunkerPopup
extends CanvasLayer
# Small panel over the walkable bunker (a station's menu: build, unlock, backpack, stock).
# The bunker fills it with rows and buttons, and rebuilds it after every button press.
# Esc, E (interact) or the Close button close it. The Esc that closes it is marked handled,
# so the pause menu never opens from that same key press (the bunker also disables the pause
# menu while a popup is open).

signal closed

const WIDTH := 260

var buttons := {}            # id -> Button (tests and the bunker look buttons up here)
var is_open := true
var box: VBoxContainer
var _panel: PanelContainer

func _init() -> void:
	layer = 60
	name = "Popup"

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UIKit.panel_style(8))
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	center.add_child(_panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_panel.add_child(box)
	Sfx.play("popup_open")

# Removes all rows (the bunker refills the popup after a change).
func clear() -> void:
	buttons.clear()
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func title(text: String) -> void:
	box.add_child(UIKit.outlined(text, 12, UIKit.ACCENT))

func line(text: String, color: Color = UIKit.TEXT, size: int = 8) -> Label:
	var l := UIKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 16, 0)
	box.add_child(l)
	return l

# A row: text on the left, a button on the right. Returns the button.
func row(text: String, note: String, button_text: String, id: String, enabled: bool, on_press: Callable) -> Button:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	box.add_child(h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UIKit.label(text, 8, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	if note != "":
		var n := UIKit.label(note, 7, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size = Vector2(WIDTH - 100, 0)
		v.add_child(n)
	var b := UIKit.button(button_text, Vector2(70, 18), 8)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(on_press)
	h.add_child(b)
	buttons[id] = b
	return b

# Several small buttons side by side: [[text, id, enabled, on_press], ...]. Returns the row.
func button_row(items: Array, width := 60) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 4)
	box.add_child(h)
	for it in items:
		var b := UIKit.button(str(it[0]), Vector2(width, 16), 8)
		b.disabled = not bool(it[2])
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(it[3])
		h.add_child(b)
		buttons[str(it[1])] = b
	return h

func add_node(n: Control) -> void:
	box.add_child(n)

# Close button at the bottom + focus on the first enabled button.
func finish() -> void:
	var close_b := UIKit.set_click_sfx(UIKit.button("Close (Esc)", Vector2(90, 16), 8), "")   # close() plays popup_close
	close_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_b.focus_mode = Control.FOCUS_ALL
	close_b.pressed.connect(close)
	box.add_child(close_b)
	buttons["close"] = close_b
	var first: Button = close_b
	for id in buttons:
		var b: Button = buttons[id]
		if not b.disabled and id != "close":
			first = b
			break
	first.grab_focus.call_deferred()

func close() -> void:
	if not is_open:
		return
	is_open = false
	Sfx.play("popup_close")
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if not is_open or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		close()
