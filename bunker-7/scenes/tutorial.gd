class_name Tutorial
extends CanvasLayer
# 7-slide "how to play" slideshow. Works while the game is paused.
#
#   var t := Tutorial.open(self)            # adds it to the scene and shows slide 1
#   t.finished.connect(_on_tutorial_done)   # fires on Done, Skip or Esc
#
# Keys: Left / Right (or Back / Next buttons), Enter on the focused button, Esc closes.

signal finished

const SLIDE_SCENE := "res://scenes/tutorial.tscn"

# Picture names are looked up in art/world_clean then art/characters_clean (null-safe).
const SLIDES := [
	{"title": "Story", "pic": "tut_1_story", "color": Color(0.35, 0.22, 0.18),
		"lines": ["The bombs fell. You are the last survivor in Bunker 7.",
			"Survive 7 days. On Day 7 a convoy comes, if your radio beacon is built."]},
	{"title": "Controls", "pic": "tut_2_controls", "color": Color(0.20, 0.30, 0.40),
		"lines": ["A / D walk. W or Space jump.",
			"E opens crates and uses the hatch.",
			"Mouse click swings your tool."]},
	{"title": "Radiation", "pic": "tut_3_radiation", "color": Color(0.30, 0.42, 0.18),
		"lines": ["Radiation rises while you are outside.",
			"The farther from the hatch, the faster it rises.",
			"At 100% you start losing hearts. Go home before it fills!"]},
	{"title": "Loot", "pic": "tut_4_loot", "color": Color(0.45, 0.33, 0.15),
		"lines": ["Open crates, chop trees and mine blocks for wood, scrap and concrete.",
			"Your backpack holds only so much. Choose what to carry."]},
	{"title": "Bunker", "pic": "tut_5_bunker", "color": Color(0.25, 0.27, 0.32),
		"lines": ["Climb down the hatch to reach your bunker.",
			"Eat, sleep, unlock rooms and build machines. Bring loot home to use it."]},
	{"title": "Bounce back", "pic": "tut_6_bounce", "color": Color(0.42, 0.18, 0.20),
		"lines": ["If you die you wake up in your bunker.",
			"You drop your backpack where you fell and gain a permanent Scar perk. Go get your pack!"]},
	{"title": "Goal", "pic": "tut_7_goal", "color": Color(0.40, 0.34, 0.12),
		"lines": ["Build the Radio Beacon, survive until Day 7, and the convoy will rescue you."]},
]

## Free this node after it finishes (turn off if you want to reuse it).
var auto_free: bool = true
## Pause the game while open (restored on close). Not needed when the pause menu opens it.
var pause_game: bool = false
var index: int = 0
var closed: bool = false

var panel: PanelContainer
var title_label: Label
var body_box: VBoxContainer
var picture_holder: Control
var dots_box: HBoxContainer
var back_button: Button
var next_button: Button
var skip_button: Button

var _was_paused: bool = false
var _dots: Array[ColorRect] = []

# Adds a new tutorial to `parent` and returns it.
static func open(parent: Node, pause: bool = false) -> Tutorial:
	var scene: PackedScene = load(SLIDE_SCENE)
	var t: Tutorial = scene.instantiate()
	t.pause_game = pause
	parent.add_child(t)
	return t

# True until the player has seen (finished or skipped) the slideshow once.
static func is_first_time() -> bool:
	return not bool(SettingsStore.get_value("tutorial_seen"))

func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("tutorial_open")
	_build()
	if pause_game:
		_was_paused = get_tree().paused
		get_tree().paused = true
	show_slide(0)

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # blocks clicks on the game behind
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.03, 0.04, 0.96)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(8))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	picture_holder = Control.new()
	picture_holder.custom_minimum_size = Vector2(420, 96)
	box.add_child(picture_holder)

	title_label = UIKit.outlined("", 14, UIKit.ACCENT)
	box.add_child(title_label)

	body_box = VBoxContainer.new()
	body_box.add_theme_constant_override("separation", 3)
	body_box.custom_minimum_size = Vector2(420, 62)
	box.add_child(body_box)

	dots_box = HBoxContainer.new()
	dots_box.alignment = BoxContainer.ALIGNMENT_CENTER
	dots_box.add_theme_constant_override("separation", 5)
	for i in SLIDES.size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(6, 6)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots_box.add_child(d)
		_dots.append(d)
	box.add_child(dots_box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	back_button = _make_button("Back", Vector2(80, 20))
	back_button.pressed.connect(prev)
	row.add_child(back_button)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	skip_button = _make_button("Skip", Vector2(70, 20))
	skip_button.pressed.connect(close)
	row.add_child(skip_button)
	var gap2 := Control.new()
	gap2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap2)
	next_button = _make_button("Next", Vector2(80, 20))
	next_button.pressed.connect(next)
	row.add_child(next_button)

func _make_button(text: String, min_size: Vector2) -> Button:
	var b := UIKit.button(text, min_size, 9)
	b.focus_mode = Control.FOCUS_ALL
	return b

func _find_art(pic: String) -> Texture2D:
	for folder in ["world_clean", "characters_clean"]:
		var t := UIKit.tex("%s/%s" % [folder, pic])
		if t != null:
			return t
	return null

func show_slide(i: int) -> void:
	index = clampi(i, 0, SLIDES.size() - 1)
	var s: Dictionary = SLIDES[index]
	title_label.text = "%d/%d  %s" % [index + 1, SLIDES.size(), s.title]
	for c in picture_holder.get_children():
		picture_holder.remove_child(c)
		c.queue_free()
	var tex := _find_art(s.pic)
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture_holder.add_child(r)
	else:
		var block := ColorRect.new()
		block.color = s.color
		block.set_anchors_preset(Control.PRESET_FULL_RECT)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture_holder.add_child(block)
		var big := UIKit.outlined(str(index + 1), 48, Color(1, 1, 1, 0.55))
		big.set_anchors_preset(Control.PRESET_FULL_RECT)
		big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		block.add_child(big)
	for c in body_box.get_children():
		body_box.remove_child(c)
		c.queue_free()
	for line in s.lines:
		var l := UIKit.label(line, 9, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(420, 0)
		body_box.add_child(l)
	for j in _dots.size():
		_dots[j].color = UIKit.ACCENT if j == index else UIKit.DIM
	var last := index == SLIDES.size() - 1
	back_button.disabled = index == 0
	skip_button.visible = not last
	next_button.text = "Done" if last else "Next"
	next_button.grab_focus()

func next() -> void:
	if closed:
		return
	if index >= SLIDES.size() - 1:
		close()
	else:
		show_slide(index + 1)

func prev() -> void:
	if not closed and index > 0:
		show_slide(index - 1)

# Done, Skip and Esc all end up here.
func close() -> void:
	if closed:
		return
	closed = true
	SettingsStore.set_value("tutorial_seen", true)
	remove_from_group("tutorial_open")
	if pause_game:
		get_tree().paused = _was_paused
	visible = false
	finished.emit()
	if auto_free:
		queue_free()

func _input(event: InputEvent) -> void:
	if closed:
		return
	if event.is_action_pressed("ui_right"):
		next()
	elif event.is_action_pressed("ui_left"):
		prev()
	elif event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("ui_accept") and get_viewport().gui_get_focus_owner() == null:
		next()
	else:
		return
	get_viewport().set_input_as_handled()
