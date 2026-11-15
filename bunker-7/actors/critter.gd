extends Node2D
# A rat (V3): wanders on the ground, runs from the player, one hit kills it and drops raw meat.
# No physics body: it follows the ground height (floor_at(x)) like pickups do. Hit by the axe or
# pickaxe through scenes/tool_swing.gd (group "critters": hit_rect / take_hit / is_dead).
# Art: art/characters_clean/rat_run_N.png frames if present, else a drawn placeholder.

const PickupScript := preload("res://actors/pickup.gd")
const WANDER_SPEED := 22.0
const FLEE_SPEED := 75.0
const SCARE_DIST := 56.0
const ART := "res://art/characters_clean/rat_run"

var player: Node = null
var floor_at: Callable
var min_x := 0.0
var max_x := 4800.0
var dead := false
var meat := 1
var _dir := 1.0
var _left := 0.0
var _body: Node2D

func setup(p: Node, floor_fn: Callable, lo: float, hi: float, loot_mult := 1.0) -> void:
	player = p
	floor_at = floor_fn
	min_x = lo
	max_x = hi
	meat = maxi(1, roundi(loot_mult))

func _ready() -> void:
	add_to_group("critters")
	z_index = 2
	_dir = -1.0 if randf() < 0.5 else 1.0
	var frames := Art.frames(ART)
	if not frames.is_empty():
		var sf := SpriteFrames.new()
		sf.set_animation_speed("default", 10.0)
		for t in frames:
			sf.add_frame("default", t)
		var s := AnimatedSprite2D.new()
		s.sprite_frames = sf
		s.centered = false
		s.offset = Vector2(-floorf(frames[0].get_width() / 2.0), -frames[0].get_height())
		s.play()
		_body = s
	else:
		_body = Node2D.new()
		for r in [[Rect2(-5, -5, 10, 5), Color(0.45, 0.4, 0.38)], [Rect2(4, -6, 4, 4), Color(0.5, 0.45, 0.42)],
				[Rect2(-9, -2, 4, 1), Color(0.75, 0.55, 0.55)], [Rect2(7, -5, 1, 1), Color(0.05, 0.05, 0.05)]]:
			var b := ColorRect.new()
			b.position = r[0].position
			b.size = r[0].size
			b.color = r[1]
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_body.add_child(b)
	add_child(_body)

func is_dead() -> bool:
	return dead

func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-7, -8), Vector2(14, 9))

func take_hit(_amount: float, _from_x: float) -> bool:
	if dead:
		return false
	dead = true
	Sfx.play("zombie_hit", -4.0, 0.1)
	remove_from_group("critters")
	for i in meat:
		var p: Node2D = PickupScript.new()
		p.position = global_position + Vector2(0, -6)
		get_parent().add_child(p)
		p.setup("raw_meat", player, floor_at, Vector2(randf_range(-20, 20), -90))
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
	return true

func _process(delta: float) -> void:
	if dead or not floor_at.is_valid():
		return
	var speed := WANDER_SPEED
	if player and is_instance_valid(player) and absf(player.global_position.x - global_position.x) < SCARE_DIST \
			and absf(player.global_position.y - global_position.y) < 40.0:
		_dir = signf(global_position.x - player.global_position.x)
		if _dir == 0.0:
			_dir = 1.0
		speed = FLEE_SPEED
	else:
		_left -= delta
		if _left <= 0.0:
			_left = randf_range(0.8, 2.5)
			_dir = [-1.0, 0.0, 1.0][randi() % 3]
	var nx := clampf(global_position.x + _dir * speed * delta, min_x, max_x)
	var ny: float = floor_at.call(nx)
	if ny < global_position.y - 17.0:   # a wall of more than one block: turn around
		_dir = -_dir
		return
	global_position = Vector2(nx, ny)
	if _dir != 0.0:
		_body.scale.x = -1.0 if _dir < 0.0 else 1.0
