extends Node2D
# One item lying in the world (a log from a tree, ore from a block, zombie loot).
# Pops out, falls onto the ground (floor_at(x) -> y of the ground top) and goes
# into the backpack when the player walks over it. A full backpack leaves it lying
# there (with a "Backpack full!" message, at most once every few seconds).
# Picture: art/world_clean/pickup_<kind>.png, else a small coloured box.

const PICK_DIST := 16.0         # px between the player's feet and the item
const MAGNET_DIST := 36.0       # closer than this (and room in the pack): drifts to the player
const MAGNET_SPEED := 90.0
const GRAVITY := 600.0
const FULL_MSG_EVERY := 3.0
const COLORS := {
	"wood": Color(0.6, 0.4, 0.2), "concrete": Color(0.7, 0.7, 0.67), "scrap": Color(0.55, 0.5, 0.45),
	"circuits": Color(0.3, 0.75, 0.4), "water": Color(0.35, 0.6, 0.95), "food": Color(0.85, 0.55, 0.3),
}

var kind := "wood"
var floor_at: Callable          # x -> ground top y
var player: Node = null
var vel := Vector2.ZERO
var grounded := false
var _age := 0.0
var _msg_left := 0.0

func setup(item_kind: String, p: Node, floor_fn: Callable, pop := Vector2.ZERO) -> void:
	kind = item_kind
	player = p
	floor_at = floor_fn
	vel = pop
	add_to_group("pickups")
	if Art.sprite(self, "res://art/world_clean/pickup_%s.png" % kind) == null:
		var box := ColorRect.new()
		box.color = COLORS.get(kind, Color.WHITE)
		box.position = Vector2(-3, -6)
		box.size = Vector2(6, 6)
		add_child(box)

func _physics_process(delta: float) -> void:
	_age += delta
	_msg_left = maxf(0.0, _msg_left - delta)
	_fall(delta)
	if player == null or not is_instance_valid(player) or _age < 0.25:
		return
	if player.dead or player.frozen:
		return
	var d: float = player.global_position.distance_to(global_position)
	if d > PICK_DIST:
		if d < MAGNET_DIST and grounded and player.capacity_left() > 0:
			position.x = move_toward(position.x, player.global_position.x, MAGNET_SPEED * delta)
		return
	if player.add_item(kind, 1) == 1:
		player.say("+1 %s" % kind)
		queue_free()
	elif _msg_left <= 0.0:
		_msg_left = FULL_MSG_EVERY
		player.say("Backpack full!")

# Simple fall onto the ground; re-falls if the block under it is mined away.
func _fall(delta: float) -> void:
	var ground := position.y
	if floor_at.is_valid():
		ground = floor_at.call(position.x)
	if position.y >= ground and vel.y >= 0.0:
		position.y = ground
		vel = Vector2.ZERO
		grounded = true
		return
	grounded = false
	vel.y += GRAVITY * delta
	position += vel * delta
	if position.y > ground:
		position.y = ground
