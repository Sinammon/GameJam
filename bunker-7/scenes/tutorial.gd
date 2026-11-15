class_name Tutorial
extends CanvasLayer
# 7-slide "how to play" slideshow. Works while the game is paused.
#
#   var t := Tutorial.open(self)            # adds it to the scene and shows slide 1
#   t.finished.connect(_on_tutorial_done)   # fires on Done, Skip or Esc
#
# Keys: Left / Right (or Back / Next buttons), Enter on the focused button, Esc closes.
#
# Layout: the slide picture fills the screen (480x270); title, text, dots and buttons sit in a
# dark see-through panel along the bottom, so the picture's subject belongs in the top ~165 px.
# Pictures: slide 3 = art/world_clean/tut_3_radiation.png; slides 1 and 7 = title_art /
# ending_rescue; slides 2, 4, 5, 6 are composed at runtime from existing art (_compose_*).
# Any missing art falls back to the old coloured placeholder with the slide number.

signal finished

const SLIDE_SCENE := "res://scenes/tutorial.tscn"

# Picture names are looked up in art/world_clean then art/characters_clean (null-safe);
# "compose" names a _compose_<name>() builder tried first (null when its art is missing).
const SLIDES := [
	{"title": "Story", "pic": "tut_1_story", "alt": "title_art", "color": Color(0.35, 0.22, 0.18),
		"lines": ["The bombs fell. You are the last survivor in Bunker 7.",
			"Survive 7 days. On Day 7 a convoy comes, if your radio beacon is built."]},
	{"title": "Controls", "pic": "tut_2_controls", "compose": "controls", "color": Color(0.20, 0.30, 0.40),
		"lines": ["A / D walk. W or Space jump.",
			"E opens crates and uses the hatch.",
			"Mouse click swings your tool."]},
	{"title": "Radiation", "pic": "tut_3_radiation", "color": Color(0.30, 0.42, 0.18),
		"lines": ["Radiation rises while you are outside.",
			"The farther from the hatch, the faster it rises.",
			"At 100% you start losing hearts. Go home before it fills!"]},
	{"title": "Loot", "pic": "tut_4_loot", "compose": "loot", "color": Color(0.45, 0.33, 0.15),
		"lines": ["Open crates, chop trees and mine blocks for wood, scrap and concrete.",
			"Your backpack holds only so much. Choose what to carry."]},
	{"title": "Bunker", "pic": "tut_5_bunker", "compose": "bunker", "color": Color(0.25, 0.27, 0.32),
		"lines": ["Climb down the hatch to reach your bunker.",
			"Eat, sleep, unlock rooms and build machines. Bring loot home to use it."]},
	{"title": "Bounce back", "pic": "tut_6_bounce", "compose": "bounce", "color": Color(0.42, 0.18, 0.20),
		"lines": ["If you die you wake up in your bunker.",
			"You drop your backpack where you fell and gain a permanent Scar perk. Go get your pack!"]},
	{"title": "Goal", "pic": "tut_7_goal", "alt": "ending_rescue", "color": Color(0.40, 0.34, 0.12),
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

	# the slide picture: a 480x270 area in the middle of the screen
	picture_holder = Control.new()
	picture_holder.set_anchors_preset(Control.PRESET_CENTER)
	picture_holder.offset_left = -PIC_SIZE.x / 2.0
	picture_holder.offset_top = -PIC_SIZE.y / 2.0
	picture_holder.offset_right = PIC_SIZE.x / 2.0
	picture_holder.offset_bottom = PIC_SIZE.y / 2.0
	picture_holder.clip_contents = true
	picture_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(picture_holder)

	# text panel along the bottom (grows upwards with its content)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _text_panel_style())
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -4
	panel.offset_top = -4
	panel.custom_minimum_size = Vector2(PIC_SIZE.x - 8, 0)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	title_label = UIKit.outlined("", 14, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	dots_box = HBoxContainer.new()
	dots_box.alignment = BoxContainer.ALIGNMENT_END
	dots_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dots_box.add_theme_constant_override("separation", 5)
	for i in SLIDES.size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(6, 6)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots_box.add_child(d)
		_dots.append(d)
	head.add_child(dots_box)

	body_box = VBoxContainer.new()
	body_box.add_theme_constant_override("separation", 1)
	body_box.custom_minimum_size = Vector2(TEXT_W, 36)
	box.add_child(body_box)

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

# Dark, mostly opaque box so the text stays readable on any picture.
static func _text_panel_style() -> StyleBox:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.035, 0.03, 0.86)
	s.border_color = Color(0.32, 0.27, 0.2, 0.9)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 5
	return s

func _find_art(pic: String) -> Texture2D:
	for folder in ["world_clean", "characters_clean"]:
		var t := UIKit.tex("%s/%s" % [folder, pic])
		if t != null:
			return t
	return null

# The picture for slide s: a composed scene, the slide's own file, its alternative, or null.
func _slide_picture(s: Dictionary) -> Control:
	if s.has("compose"):
		var c: Control = call("_compose_" + str(s.compose))
		if c != null:
			return c
	for key in ["pic", "alt"]:
		if not s.has(key):
			continue
		var tex := _find_art(s[key])
		if tex != null:
			var pic := _canvas()
			_cover(pic, tex, Rect2(Vector2.ZERO, PIC_SIZE))
			return pic
	return null

# --- composed pictures (480x270, subject in the top ~165 px above the text panel) ---------

const PIC_SIZE := Vector2(480, 270)
const TEXT_W := 452.0
const GROUND_Y := 150.0     # feet line of the composed scenes

func _canvas() -> Control:
	var c := Control.new()
	c.size = PIC_SIZE
	c.clip_contents = true
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func _t(file: String) -> Texture2D:
	return UIKit.tex(file)

# Texture filling `rect` (cropped to keep its aspect), tinted by `tint`.
static func _cover(parent: Control, tex: Texture2D, rect: Rect2, tint := Color.WHITE) -> TextureRect:
	if tex == null:
		return null
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.position = rect.position
	r.size = rect.size
	r.clip_contents = true
	r.modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r

# Texture at a whole-number zoom with its bottom-centre at `foot`.
static func _put(parent: Control, tex: Texture2D, foot: Vector2, zoom := 1, flip := false) -> TextureRect:
	if tex == null:
		return null
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.flip_h = flip
	r.size = tex.get_size() * zoom
	r.position = (foot - Vector2(r.size.x / 2.0, r.size.y)).floor()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r

static func _caption(parent: Control, text: String, centre: Vector2) -> void:
	var l := UIKit.outlined(text, 10, UIKit.ACCENT)
	l.position = centre - Vector2(60, 7)
	l.size = Vector2(120, 14)
	parent.add_child(l)

# Dusk sky + far city + a strip of ground tiles under GROUND_Y.
func _dusk(c: Control) -> void:
	var sky := _t("world_clean/bg_sky")
	if sky:
		_cover(c, sky, Rect2(Vector2.ZERO, PIC_SIZE))
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.45, 0.25, 0.18)
		bg.size = PIC_SIZE
		c.add_child(bg)
	var far := _t("world_clean/bg_far")
	if far:   # 810x270 layer: show its left part 1:1, horizon just above the ground
		var r := TextureRect.new()
		r.texture = far
		r.position = Vector2(0, GROUND_Y - 270 + 40)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(r)
	var under := ColorRect.new()   # the text panel covers the rest
	under.color = Color(0.2, 0.13, 0.1)
	under.position = Vector2(0, GROUND_Y)
	under.size = Vector2(PIC_SIZE.x, PIC_SIZE.y - GROUND_Y)
	c.add_child(under)
	var top := _t("world_clean/tiles_outside_dirt_grass")
	var fill := _t("world_clean/tiles_outside_dirt")
	for x in range(0, int(PIC_SIZE.x), 16):
		_put(c, top, Vector2(x + 8, GROUND_Y + 16))
		_put(c, fill, Vector2(x + 8, GROUND_Y + 32))

# Slide 2: walk, jump, mine frames in a row on the dusk sky.
func _compose_controls() -> Control:
	var walk := _t("characters_clean/survivor_walk_1")
	var jump := _t("characters_clean/survivor_jump_2")
	var mine := _t("characters_clean/survivor_mine_2")
	if walk == null and jump == null and mine == null:
		return null
	var c := _canvas()
	_dusk(c)
	var items := [[walk, 0.0, "A / D"], [jump, -22.0, "W / Space"], [mine, 0.0, "Click"]]
	for i in items.size():
		var x := 96.0 + i * 144.0
		_put(c, items[i][0], Vector2(x, GROUND_Y + items[i][1]), 3)
		_caption(c, items[i][2], Vector2(x, 26))
	return c

# Slide 4: the survivor chopping next to an open crate with materials popping out.
func _compose_loot() -> Control:
	var chop := _t("characters_clean/survivor_chop_2")
	var crate := _t("world_clean/obj_crate_open")
	if chop == null and crate == null:
		return null
	var c := _canvas()
	_dusk(c)
	_put(c, chop, Vector2(150, GROUND_Y), 3)
	_put(c, crate, Vector2(300, GROUND_Y), 3)
	var icons := ["wood", "scrap", "concrete", "water", "food"]
	for i in icons.size():
		var a := PI * (0.9 - 0.2 * i)   # an arc over the crate
		_put(c, _t("world_clean/icon_" + icons[i]), Vector2(300, 82) + Vector2(cos(a), -sin(a)) * Vector2(70, 46), 2)
	return c

# Slide 5: the bunker cross-section with the survivor in the first room.
func _compose_bunker() -> Control:
	var bunker := _t("world_clean/bunker_overview")
	if bunker == null:
		return null
	var c := _canvas()
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.07, 0.06)
	bg.size = PIC_SIZE
	c.add_child(bg)
	_put(c, bunker, Vector2(PIC_SIZE.x / 2.0, 164))
	_put(c, _t("characters_clean/survivor_idle_0"), Vector2(70, 144))   # 1:1, on the first room's floor
	return c

# Slide 6: three panels: collapsed outside -> waking up in the bunker -> standing again.
func _compose_bounce() -> Control:
	var down := _t("characters_clean/survivor_collapse_3")
	var wake := _t("characters_clean/survivor_wakeup_2")
	var stand := _t("characters_clean/survivor_idle_0")
	if down == null and wake == null and stand == null:
		return null
	var c := _canvas()
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.05)
	bg.size = PIC_SIZE
	c.add_child(bg)
	var backs := ["world_clean/bg_sky", "world_clean/room_bedroom", "world_clean/room_bedroom"]
	var figs := [down, wake, stand]
	for i in 3:
		var r := Rect2(12 + i * 156, 14, 144, 144)
		var frame := ColorRect.new()
		frame.color = Color(0.35, 0.29, 0.22)
		frame.position = r.position - Vector2(2, 2)
		frame.size = r.size + Vector2(4, 4)
		c.add_child(frame)
		var back := _cover(c, _t(backs[i]), r, Color(0.8, 0.8, 0.8) if i == 0 else Color.WHITE)
		if back == null:
			var fill := ColorRect.new()
			fill.color = Color(0.2, 0.17, 0.15)
			fill.position = r.position
			fill.size = r.size
			c.add_child(fill)
		var floor_y := r.end.y - 14.0
		var ground := ColorRect.new()
		ground.color = Color(0.16, 0.12, 0.1) if i == 0 else Color(0.22, 0.21, 0.2)
		ground.position = Vector2(r.position.x, floor_y)
		ground.size = Vector2(r.size.x, r.end.y - floor_y)
		c.add_child(ground)
		_put(c, figs[i], Vector2(r.get_center().x, floor_y), 3)
		if i < 2:
			_caption(c, ">", Vector2(r.end.x + 6, r.get_center().y))
	return c

func show_slide(i: int) -> void:
	index = clampi(i, 0, SLIDES.size() - 1)
	var s: Dictionary = SLIDES[index]
	title_label.text = "%d/%d  %s" % [index + 1, SLIDES.size(), s.title]
	for c in picture_holder.get_children():
		picture_holder.remove_child(c)
		c.queue_free()
	var pic := _slide_picture(s)
	if pic != null:
		picture_holder.add_child(pic)
	else:   # placeholder: coloured block with the slide number above the text panel
		var block := ColorRect.new()
		block.color = s.color
		block.set_anchors_preset(Control.PRESET_FULL_RECT)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture_holder.add_child(block)
		var big := UIKit.outlined(str(index + 1), 48, Color(1, 1, 1, 0.55))
		big.position = Vector2(0, 30)
		big.size = Vector2(PIC_SIZE.x, 100)
		big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		block.add_child(big)
	for c in body_box.get_children():
		body_box.remove_child(c)
		c.queue_free()
	for line in s.lines:
		var l := UIKit.label(line, 9, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(TEXT_W, 0)
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
