class_name LocationDressing
extends RefCounted
# Looks for the V3 locations (Old Mine, Bomb Crater) until their real art exists.
# Every function first tries art/world_clean/<name>.png (so the designer's files drop in by name)
# and otherwise draws a placeholder from coloured shapes. Called by scenes/expedition.gd.

const ART := "res://art/world_clean/%s.png"

static func _box(parent: Node, r: Rect2, c: Color) -> ColorRect:
	var b := ColorRect.new()
	b.position = r.position
	b.size = r.size
	b.color = c
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b

# A dark rock wall behind a tunnel (the mine has no sky): dirt tiles, darkened, over the whole world.
class CaveWall extends Node2D:
	var tex: Texture2D
	var cols := 0
	var rows := 0
	var tint := Color(0.3, 0.27, 0.3)
	func _draw() -> void:
		for x in cols:
			for y in rows:
				var r := Rect2(x * 16, y * 16, 16, 16)
				var k := 0.85 + 0.15 * float((x * 7 + y * 13) % 5) / 4.0
				if tex:
					draw_texture_rect_region(tex, r, Rect2(0, 0, 16, 16) if (x + y) % 3 else Rect2(16, 16, 16, 16), tint * k)
				else:
					draw_rect(r, Color(0.12, 0.1, 0.1) * k)

static func cave_wall(ex: Node2D, tex: Texture2D, tint: Color) -> Node2D:
	var w := CaveWall.new()
	w.name = "CaveWall"
	w.tex = tex
	w.cols = ex.COLS
	w.rows = ex.BOTTOM_ROW
	w.tint = tint
	w.z_index = -9
	w.light_mask = 2   # Lighting.MASK_BACKGROUND: world lamps only
	ex.add_child(w)
	ex.move_child(w, 0)
	return w

# One prop standing on the ground at x. ceil_y: y of the tunnel ceiling there (0 = open sky).
# Returns the node; lamps get a light from the lighting module when one is passed in.
static func prop(ex: Node2D, art: String, x: float, ground_y: float, ceil_y: float) -> Node2D:
	var n := Node2D.new()
	n.name = art
	n.position = Vector2(x, ground_y)
	n.z_index = -1
	ex.add_child(n)
	if Art.sprite(n, ART % art) != null:
		return n
	match art:
		"obj_mine_support":   # two posts up to the ceiling and a beam
			var h := ground_y - ceil_y if ceil_y > 0.0 else 64.0
			_box(n, Rect2(-14, -h, 4, h), Color(0.42, 0.3, 0.18))
			_box(n, Rect2(10, -h, 4, h), Color(0.42, 0.3, 0.18))
			_box(n, Rect2(-17, -h, 34, 4), Color(0.36, 0.25, 0.15))
		"obj_mine_lamp":      # a lamp hanging from the ceiling
			var top := -(ground_y - ceil_y) if ceil_y > 0.0 else -60.0
			_box(n, Rect2(0, top, 1, 12), Color(0.2, 0.2, 0.2))
			_box(n, Rect2(-2, top + 12, 5, 4), Color(1.0, 0.82, 0.45))
			n.set_meta("lamp_at", Vector2(0, top + 14))
		"obj_mine_cart":
			_box(n, Rect2(-12, -13, 24, 10), Color(0.32, 0.3, 0.3))
			_box(n, Rect2(-12, -13, 24, 2), Color(0.45, 0.42, 0.4))
			_box(n, Rect2(-9, -4, 4, 4), Color(0.12, 0.12, 0.12))
			_box(n, Rect2(5, -4, 4, 4), Color(0.12, 0.12, 0.12))
			_box(n, Rect2(-9, -16, 14, 3), Color(0.45, 0.4, 0.35))   # ore heap
		"obj_girder":
			var g := _box(n, Rect2(-22, -6, 44, 5), Color(0.5, 0.3, 0.2))
			g.pivot_offset = Vector2(22, 2)
			g.rotation = -0.35
		"obj_car_wreck":
			_box(n, Rect2(-20, -12, 40, 9), Color(0.22, 0.2, 0.18))
			_box(n, Rect2(-11, -19, 20, 7), Color(0.18, 0.16, 0.15))
			_box(n, Rect2(-15, -4, 6, 4), Color(0.08, 0.08, 0.08))
			_box(n, Rect2(9, -4, 6, 4), Color(0.08, 0.08, 0.08))
		"obj_crater_crystal":
			var poly := Polygon2D.new()
			poly.polygon = PackedVector2Array([Vector2(-4, 0), Vector2(-2, -12), Vector2(1, -16), Vector2(3, -9), Vector2(5, 0)])
			poly.color = Color(0.55, 1.0, 0.4)
			n.add_child(poly)
			n.add_to_group("light_glow")
			n.set_meta("glow", true)
		_:
			_box(n, Rect2(-6, -10, 12, 10), Color(0.4, 0.4, 0.4))
	return n

# What the way home looks like when it isn't the bunker hatch: a rope (mine) or a ladder (crater)
# going up out of the picture. Added to the hatch Area2D (which still does the banking).
static func exit_visual(hatch: Node2D, style: String, art: String, height: float) -> Node2D:
	var n := Node2D.new()
	n.name = "ExitVisual"
	hatch.add_child(n)
	if art != "" and Art.sprite(n, ART % art) != null:
		return n
	if style == "rope":
		_box(n, Rect2(-1, -height, 2, height - 6), Color(0.62, 0.5, 0.3))
		_box(n, Rect2(-3, -10, 6, 4), Color(0.5, 0.38, 0.22))   # knot
		_box(n, Rect2(-8, -2, 16, 2), Color(0.35, 0.28, 0.2))   # coil on the floor
		_box(n, Rect2(-14, -height, 28, 4), Color(0.36, 0.25, 0.15))   # beam at the top
	else:
		for side in [-7, 5]:
			_box(n, Rect2(side, -height, 2, height), Color(0.5, 0.48, 0.44))
		var y := -6.0
		while y > -height:
			_box(n, Rect2(-7, y, 14, 2), Color(0.58, 0.55, 0.5))
			y -= 8.0
	return n
