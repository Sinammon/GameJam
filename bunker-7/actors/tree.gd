extends Node2D
# A dead tree on the surface. Chop it with the axe (the pickaxe barely scratches it).
# Hits shake it and throw wood chips; at 0 hp it falls over, drops logs (wood
# pickups) once, and a stump stays behind (stumps ignore further hits).
# Origin = bottom centre of the trunk, on the ground.
# Art (art/world_clean/, each optional, missing = drawn placeholder):
#   small  = obj_tree_dead.png   (50x80, a bare dead tree, 3 hits)
#   medium = obj_tree_oak.png / obj_tree_oak_orange.png (~80x112, 5 hits; orange
#            on every third column so rows of oaks don't all look the same)
#   large  = obj_tree_pine.png   (82x128, 7 hits)
#   stump  = obj_stump.png after it falls; logs drop as wood pickups drawn with obj_logs.png.
# (obj_tree_sapling / obj_bush / obj_branch exist too, unused for now.)

signal felled(tree: Node2D)

const Chips := preload("res://actors/chips.gd")
const PickupScript := preload("res://actors/pickup.gd")
const ART := "res://art/world_clean/%s.png"

# size -> hp (axe hits), logs dropped (before the loot multiplier), placeholder trunk
# height/width (also the hit box: the trunk, not the crown), picture(s)
const SIZES := {
	"small": {"hp": 3.0, "logs": 1, "h": 30, "w": 6, "art": ["obj_tree_dead"]},
	"medium": {"hp": 5.0, "logs": 2, "h": 48, "w": 8, "art": ["obj_tree_oak", "obj_tree_oak_orange"]},
	"large": {"hp": 7.0, "logs": 3, "h": 64, "w": 10, "art": ["obj_tree_pine"]},
}
const STUMP_ART := "obj_stump"
const LOG_ART := "obj_logs"
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
	_trunk = Node2D.new()
	add_child(_trunk)
	var arts: Array = SIZES[size]["art"]
	var pick: String = arts[0] if arts.size() == 1 or posmod(int(position.x / 16.0), 3) != 0 else arts[1]
	if Art.sprite(_trunk, ART % pick) == null:
		_trunk.draw.connect(_draw_trunk)
	_stump = Node2D.new()
	_stump.visible = false
	add_child(_stump)
	if Art.sprite(_stump, ART % STUMP_ART) == null:
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
	Sfx.play("axe_chop", 0.0, 0.08)
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
	Sfx.play("tree_fall")
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
		p.setup("wood", player, floor_at, Vector2(randf_range(-30, 30), -120), ART % LOG_ART)
	felled.emit(self)
