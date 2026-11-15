extends Node2D
# A one-shot burst of tiny chips (wood splinters, dirt, sparks, toxic splats).
# Uses fx_chips.png pieces if the sheet exists, else small coloured squares.
# Frees itself when done. Cheap: a handful of points moved in _process.

const SHEET := "res://art/world_clean/fx_chips.png"   # optional art # lint:ignore res_path
# fx_chips.png order (left to right): dirt, stone, scrap, concrete, wood, spark, dust, toxic
const KINDS := ["dirt", "stone", "scrap", "concrete", "wood", "spark", "dust", "toxic"]
const COLORS := {
	"dirt": Color(0.45, 0.32, 0.2), "stone": Color(0.55, 0.55, 0.6), "scrap": Color(0.6, 0.4, 0.25),
	"concrete": Color(0.75, 0.75, 0.72), "wood": Color(0.62, 0.42, 0.22), "spark": Color(1.0, 0.85, 0.3),
	"dust": Color(0.8, 0.75, 0.6), "toxic": Color(0.71, 0.89, 0.12),
}
const LIFE := 0.5
const GRAVITY := 500.0

var kind := "dirt"
var _vel: Array[Vector2] = []
var _pos: Array[Vector2] = []
var _t := 0.0
var _tex: Texture2D = null

static func burst(parent: Node, at: Vector2, chip_kind: String, count := 6) -> Node2D:
	var c: Node2D = load("res://actors/chips.gd").new()
	c.kind = chip_kind
	c.position = at
	c.z_index = 5
	parent.add_child(c)
	c.start(count)
	return c

func start(count: int) -> void:
	var pieces := Art.split_sheet(SHEET)
	var i := KINDS.find(kind)
	if i >= 0 and i < pieces.size():
		_tex = pieces[i]
	for n in count:
		_pos.append(Vector2.ZERO)
		_vel.append(Vector2(randf_range(-70, 70), randf_range(-140, -50)))

func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	for n in _pos.size():
		_vel[n].y += GRAVITY * delta
		_pos[n] += _vel[n] * delta
	queue_redraw()

func _draw() -> void:
	var a := 1.0 - _t / LIFE
	for p in _pos:
		if _tex:
			draw_texture(_tex, (p - _tex.get_size() / 2.0).floor(), Color(1, 1, 1, a))
		else:
			var col: Color = COLORS.get(kind, Color.WHITE)
			col.a = a
			draw_rect(Rect2(p.floor(), Vector2(2, 2)), col)
