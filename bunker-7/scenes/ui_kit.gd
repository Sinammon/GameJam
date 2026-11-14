class_name UIKit
extends RefCounted
# Tiny helpers so every menu screen looks the same.
# Art comes from res://art/*_clean (made by art_tools/clean_art.py). Every helper falls back
# to the old flat placeholder look when a picture is missing, so nothing breaks without art.

const BG := Color(0.07, 0.08, 0.10)
const PANEL := Color(0.13, 0.15, 0.18)
const TEXT := Color(0.88, 0.90, 0.86)
const DIM := Color(0.55, 0.58, 0.60)
const ACCENT := Color(0.95, 0.72, 0.25)
const GOOD := Color(0.45, 0.80, 0.45)
const BAD := Color(0.90, 0.35, 0.30)
const SHADE := Color(0.04, 0.03, 0.03, 0.72)     # dark see-through box for text on top of art
const BUTTON_TEXT := Color(0.13, 0.07, 0.03)     # dark brown on the orange button art

# ---------------------------------------------------------------- art loading

# tex("world_clean/icon_wood") -> Texture2D, or null when the file isn't there.
static func tex(name: String) -> Texture2D:
	var path := "res://art/%s.png" % name
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

# A picture at its own pixel size (scale = whole-number zoom), or null if missing.
static func picture(name: String, scale: int = 1) -> TextureRect:
	var t := tex(name)
	if t == null:
		return null
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED if scale == 1 else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = t.get_size() * scale
	r.size = t.get_size() * scale
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# Full-screen background picture (480x270 art), or a flat colour when the picture is missing.
static func backdrop(parent: Control, name: String, fallback: Color = BG, dim: float = 1.0) -> Control:
	var t := tex(name)
	if t == null:
		return background(parent, fallback)
	background(parent, Color.BLACK)
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.modulate = Color(dim, dim, dim)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r

static func background(parent: Control, color: Color = BG) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

# ---------------------------------------------------------------- text

static func label(text: String, size: int = 10, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align as HorizontalAlignment
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

# Label with a dark outline, readable on top of busy art.
static func outlined(text: String, size: int = 10, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := label(text, size, color, align)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	l.add_theme_constant_override("outline_size", 3)
	return l

# [icon] value  -- e.g. icon_text("icon_water", "Water", "5"). Without the icon: "Water 5".
static func icon_text(icon: String, word: String, value: String, size: int = 10, color: Color = TEXT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := picture("world_clean/" + icon)
	if pic != null:
		pic.custom_minimum_size = Vector2(16, 16)
		pic.tooltip_text = word
		row.add_child(pic)
		row.add_child(outlined(value, size, color))
	else:
		row.add_child(outlined(("%s %s" % [word, value]).strip_edges(), size, color))
	return row

# A centred row of icon_text items, e.g. [["icon_water", "Water", "5"], ...]
static func icon_row(items: Array, size: int = 10, gap: int = 10) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", gap)
	for it in items:
		row.add_child(icon_text(it[0], it[1], it[2], size, it[3] if it.size() > 3 else TEXT))
	return row

# ---------------------------------------------------------------- boxes and buttons

static func _box(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(2)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s

static func _tex_box(name: String, margin_x: int, margin_y: int, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var t := tex(name)
	if t == null:
		return null
	var s := StyleBoxTexture.new()
	s.texture = t
	s.texture_margin_left = margin_x
	s.texture_margin_right = margin_x
	s.texture_margin_top = margin_y
	s.texture_margin_bottom = margin_y
	s.modulate_color = modulate
	return s

# The rusty riveted steel panel (ui_panel art), or a flat dark box.
static func panel_style(pad: int = 10) -> StyleBox:
	var s: StyleBox = _tex_box("world_clean/ui_panel", 9, 9)
	if s == null:
		s = _box(PANEL)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

# See-through dark box for text over full-screen art.
static func shade_style(pad: int = 8) -> StyleBoxFlat:
	var s := _box(SHADE)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

# PanelContainer with the given style at a fixed spot; add children to the returned VBox.
static func panel_box(parent: Control, rect: Rect2, style: StyleBox, gap: int = 6) -> VBoxContainer:
	var p := PanelContainer.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", style)
	parent.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	p.add_child(box)
	return box

static func button(text: String, min_size: Vector2 = Vector2(120, 24), size: int = 10) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE   # keeps keyboard cheats from clicking buttons
	b.add_theme_font_size_override("font_size", size)
	var normal := _tex_box("world_clean/ui_button_normal", 7, 5)
	var pressed := _tex_box("world_clean/ui_button_pressed", 7, 5)
	if normal != null and pressed != null:
		var hover := _tex_box("world_clean/ui_button_normal", 7, 5, Color(1.18, 1.12, 1.05))
		var disabled := _tex_box("world_clean/ui_button_normal", 7, 5, Color(0.42, 0.40, 0.40))
		for s in [normal, pressed, hover, disabled]:
			s.content_margin_left = 6
			s.content_margin_right = 6
			s.content_margin_top = 2
			s.content_margin_bottom = 2
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_stylebox_override("hover_pressed", pressed)
		b.add_theme_stylebox_override("disabled", disabled)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, BUTTON_TEXT)
		b.add_theme_color_override("font_disabled_color", Color(0.70, 0.66, 0.60))
		return b
	b.add_theme_stylebox_override("normal", _box(Color(0.22, 0.26, 0.30)))
	b.add_theme_stylebox_override("hover", _box(Color(0.32, 0.38, 0.44)))
	b.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.3)))
	b.add_theme_stylebox_override("disabled", _box(Color(0.14, 0.15, 0.17)))
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.42, 0.44))
	return b

# A centered column that fills the screen. Add your labels/buttons to the returned box.
static func center_column(parent: Control, gap: int = 6) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	center.add_child(box)
	return box

# Like center_column, but the column sits inside a styled panel.
static func center_panel(parent: Control, style: StyleBox, gap: int = 6) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	center.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	p.add_child(box)
	return box
