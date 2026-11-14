class_name UIKit
extends RefCounted
# Tiny helpers so every menu screen looks the same (placeholder look, no art needed).

const BG := Color(0.07, 0.08, 0.10)
const PANEL := Color(0.13, 0.15, 0.18)
const TEXT := Color(0.88, 0.90, 0.86)
const DIM := Color(0.55, 0.58, 0.60)
const ACCENT := Color(0.95, 0.72, 0.25)
const GOOD := Color(0.45, 0.80, 0.45)
const BAD := Color(0.90, 0.35, 0.30)

static func background(parent: Control, color: Color = BG) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

static func label(text: String, size: int = 10, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align as HorizontalAlignment
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func _box(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(2)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s

static func button(text: String, min_size: Vector2 = Vector2(120, 24), size: int = 10) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE   # keeps keyboard cheats from clicking buttons
	b.add_theme_font_size_override("font_size", size)
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
