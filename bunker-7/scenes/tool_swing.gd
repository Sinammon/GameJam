extends Node2D
# Left click with a tool (Inventory.tool_used): one swing every COOLDOWN seconds.
# Aim: towards the mouse once the mouse has moved, else the facing direction.
# Axe:     hits zombies (lightly), chops trees.
# Pickaxe: hits zombies, digs the block in reach (scenes/mining.gd), barely scratches trees.
# Other tools do nothing yet.
# Swing picture: survivor_chop / survivor_mine animation, or a small drawn arc.

# Tuning (see V2_NOTES.md)
const COOLDOWN := 0.4
const REACH := 26.0              # px in front of the player's centre (~1.5 tiles)
const ZOMBIE_DAMAGE := {"axe": 1.0, "pickaxe": 2.0}
const TREE_DAMAGE := {"axe": 1.0, "pickaxe": 0.34}
const MSG_EVERY := 1.5
const WHY_TEXT := {
	"too deep": "Too deep to dig here.",
	"unsafe": "Too steep: you couldn't climb back out.",
	"bedrock": "Bedrock. It won't break.",
	"protected": "Can't dig here.",
}

var ex: Node2D = null
var player: Node = null
var mining: Node = null
var mouse_aim := false           # true after the mouse moved (tests leave it false)
var aim_override: Variant = null # tests/scenarios: a world point to aim at instead of the mouse
var last_result := ""            # "zombie", "tree", "block", "" (read by tests)
var _cooldown := 0.0
var _msg_left := 0.0
var _arc_left := 0.0
var _arc_dir := 1.0

func setup(expedition: Node2D) -> void:
	ex = expedition
	player = ex.player
	mining = ex.mining
	z_index = 4

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_msg_left = maxf(0.0, _msg_left - delta)
	if _arc_left > 0.0:
		_arc_left -= delta
		queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_aim = true

func ready_to_swing() -> bool:
	return _cooldown <= 0.0

# Inventory.tool_used handler. Returns what was hit ("" = nothing / not ready).
func use(tool_id: String) -> String:
	last_result = ""
	if not tool_id in ["axe", "pickaxe"] or player.dead or player.frozen or ex.ended:
		return ""
	if _cooldown > 0.0:
		return ""
	_cooldown = COOLDOWN
	var aim: Variant = get_global_mouse_position() if mouse_aim else null
	if aim_override is Vector2:
		aim = aim_override
	var dir: float = player.facing
	if aim is Vector2 and absf(aim.x - player.global_position.x) > 2.0:
		dir = signf(aim.x - player.global_position.x)
	player.face(dir)
	if not player.use_tool(tool_id):
		_arc_left = 0.15
		_arc_dir = dir
		queue_redraw()
	last_result = _apply(tool_id, dir, aim)
	return last_result

func swing_rect(dir: float) -> Rect2:
	var feet: Vector2 = player.global_position
	var x0 := feet.x - 4.0 if dir > 0.0 else feet.x - REACH
	return Rect2(Vector2(x0, feet.y - 30.0), Vector2(REACH + 4.0, 32.0))

func _apply(tool_id: String, dir: float, aim: Variant) -> String:
	var box := swing_rect(dir)
	# 1. zombies in the swing
	var hit_any := false
	for z in get_tree().get_nodes_in_group("zombies"):
		if not z.is_dead() and box.intersects(z.hit_rect()):
			z.take_hit(ZOMBIE_DAMAGE[tool_id], player.global_position.x)
			hit_any = true
	if hit_any:
		ex.shake(1.5, 0.1)
		return "zombie"
	# 2. pickaxe: the block in reach (or a tree if the mouse is on it)
	if tool_id == "pickaxe":
		var tree := _tree_in(box)
		if tree and aim is Vector2 and tree.hit_rect().grow(4.0).has_point(aim):
			tree.hit(TREE_DAMAGE[tool_id], player.global_position.x)
			return "tree"
		var target: Array = mining.pick_target(player.global_position, dir, aim)
		if target[1] == "":
			mining.hit(target[0])
			return "block"
		if tree:
			tree.hit(TREE_DAMAGE[tool_id], player.global_position.x)
			return "tree"
		_say(WHY_TEXT.get(target[1], ""))
		return ""
	# 3. axe: a tree
	var t := _tree_in(box)
	if t:
		t.hit(TREE_DAMAGE[tool_id], player.global_position.x)
		return "tree"
	return ""

func _tree_in(box: Rect2) -> Node:
	for t in get_tree().get_nodes_in_group("trees"):
		if t.can_be_hit() and box.intersects(t.hit_rect()):
			return t
	return null

func _say(text: String) -> void:
	if text != "" and _msg_left <= 0.0:
		_msg_left = MSG_EVERY
		player.say(text)

# Placeholder swing: a short white arc in front of the player.
func _draw() -> void:
	if _arc_left <= 0.0 or player == null:
		return
	var c: Vector2 = player.global_position + Vector2(0, -14)
	var a := clampf(_arc_left / 0.15, 0.0, 1.0)
	var from := -1.2 if _arc_dir > 0.0 else PI + 1.2
	var to := 0.6 if _arc_dir > 0.0 else PI - 0.6
	draw_arc(c, 16.0, from, to, 8, Color(1, 1, 0.9, 0.8 * a), 2.0)
