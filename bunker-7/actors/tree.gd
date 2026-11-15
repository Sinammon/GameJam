extends Node2D
# A dead tree on the surface. Chop it with the axe (the pickaxe barely scratches it).
# Hits shake it and throw wood chips; at 0 hp it falls over, drops logs (wood
# pickups) once, and a stump stays behind (stumps ignore further hits).
# Origin = bottom centre of the trunk, on the ground.
# Art: obj_trees.png, 6 objects left to right: tall tree, medium tree, short
# broken tree, stump, fallen log, bush (cut by Art.split_sheet). Missing = drawn.

signal felled(tree: Node2D)

const Chips := preload("res://actors/chips.gd")
const PickupScript := preload("res://actors/pickup.gd")
const SHEET := "res://art/world_clean/obj_trees.png"   # optional art # lint:ignore res_path

# size -> hp (axe hits), logs dropped (before the loot multiplier), placeholder trunk height/width,
# sheet index of its picture
const SIZES := {
	"small": {"hp": 3.0, "logs": 1, "h": 30, "w": 6, "art": 2},
	"medium": {"hp": 5.0, "logs": 2, "h": 48, "w": 8, "art": 1},
	"large": {"hp": 7.0, "logs": 3, "h": 64, "w": 10, "art": 0},
}
const STUMP_ART := 3
const FALL_TIME := 0.6

var size := "medium"
var hp := 5.0
var fallen := false           # true once chopped down (only a stump left)
var logs_dropped := 0         # read by tests: must happen only once
var loot_mult := 1.0
var player: Node = null
var floor_at: Callable
var _trunk: Node2D            # what falls over (sprite or drawn trunk)
var _stump: Node2D

func setup(tree_size: String, p: Node, floor_fn: Callable, mult := 1.0) -> void:
	size = tree_size if SIZES.has(tree_size) else "medium"
	hp = SIZES[size]["hp"]
	player = p
	floor_at = floor_fn
	loot_mult = mult
	add_to_group("trees")

func _ready() -> void:
	z_index = -1   # behind the player and crates
	var pieces := Art.split_sheet(SHEET)
	_trunk = Node2D.new()
	add_child(_trunk)
	var idx: int = SIZES[size]["art"]
	if idx < pieces.size():
		var s := Sprite2D.new()
		s.texture = pieces[idx]
		s.centered = false
		s.offset = Vector2(-floorf(s.texture.get_width() / 2.0), -s.texture.get_height())
		_trunk.add_child(s)
	else:
		_trunk.draw.connect(_draw_trunk)
	_stump = Node2D.new()
	_stump.visible = false
	add_child(_stump)
	if STUMP_ART < pieces.size():
		var st := Sprite2D.new()
		st.texture = pieces[STUMP_ART]
		st.centered = false
		st.offset = Vector2(-floorf(st.texture.get_width() / 2.0), -st.texture.get_height())
		_stump.add_child(st)
	else:
		var r := ColorRect.new()
		r.color = Color(0.32, 0.22, 0.14)
		r.position = Vector2(-5, -6)
		r.size = Vector2(10, 6)
		_stump.add_child(r)

# Placeholder: charred trunk with a few bare branches.
func _draw_trunk() -> void:
	var h: float = SIZES[size]["h"]
	var w: float = SIZES[size]["w"]
	var bark := Color(0.28, 0.2, 0.15)
	_trunk.draw_rect(Rect2(-w / 2.0, -h, w, h), bark)
	_trunk.draw_rect(Rect2(-w / 2.0, -h, 2, h), Color(0.2, 0.14, 0.1))
	for i in 3:
		var y := -h * (0.45 + 0.18 * i)
		var dir := -1.0 if i % 2 == 0 else 1.0
		_trunk.draw_line(Vector2(0, y), Vector2(dir * (w + 6 - i * 2), y - 8), bark, 2.0)
	_trunk.draw_line(Vector2(0, -h), Vector2(3, -h - 6), bark, 2.0)

# World rect that a swing has to touch.
func hit_rect() -> Rect2:
	var h: float = SIZES[size]["h"]
	var w: float = maxf(SIZES[size]["w"], 10)
	if fallen:
		return Rect2(global_position + Vector2(-5, -6), Vector2(10, 6))
	return Rect2(global_position + Vector2(-w / 2.0, -h), Vector2(w, h))

func can_be_hit() -> bool:
	return not fallen

# damage: 1 per axe hit, less from the pickaxe. from_x: where the swing came from.
func hit(damage: float, from_x: float) -> void:
	if fallen:
		return
	hp -= damage
	Chips.burst(get_parent(), global_position + Vector2(0, -14), "wood", 5)
	if hp <= 0.0:
		fall(signf(global_position.x - from_x))
		return
	# shake
	var tw := create_tween()
	for i in 3:
		tw.tween_property(_trunk, "position:x", 1.5 if i % 2 == 0 else -1.5, 0.03)
	tw.tween_property(_trunk, "position:x", 0.0, 0.03)

# Falls away from the chopper, then the logs pop out and the stump shows.
func fall(dir: float) -> void:
	if fallen:
		return
	fallen = true
	if dir == 0.0:
		dir = 1.0
	_stump.visible = true
	var tw := create_tween()
	tw.tween_property(_trunk, "rotation", dir * PI / 2.0, FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_drop_logs.bind(dir))
	tw.tween_property(_trunk, "modulate:a", 0.0, 0.3)
	tw.tween_callback(_trunk.hide)

func _drop_logs(dir: float) -> void:
	if logs_dropped > 0:
		return
	var n := maxi(1, roundi(SIZES[size]["logs"] * loot_mult))
	logs_dropped = n
	Chips.burst(get_parent(), global_position + Vector2(dir * 12, -4), "dust", 6)
	for i in n:
		var p: Node2D = PickupScript.new()
		p.position = global_position + Vector2((i - (n - 1) / 2.0) * 5.0, -10)
		get_parent().add_child(p)
		p.setup("wood", player, floor_at, Vector2(randf_range(-30, 30), -120))
	felled.emit(self)
