extends CharacterBody2D
# A slow irradiated zombie. States: idle (wander), chase, attack (windup, hit),
# hurt (knockback), dead (fade, maybe drop food/scrap).
# No pathfinding: walks, falls, hops 1-block steps. Never steps into the hatch
# safe zone (|x - safe_x| < safe_radius). Passes through the player and other
# zombies (collides with the world only); hits are distance checks.
# Art: art/characters_clean/zombie_{walk,attack,death,hurt}_N.png, else a
# green-grey box with two bright eyes.

signal died(zombie: Node)

enum State { IDLE, CHASE, ATTACK, HURT, DEAD }

const Chips := preload("res://actors/chips.gd")
const PickupScript := preload("res://actors/pickup.gd")
const ART := "res://art/characters_clean/zombie_%s"

# Tuning (see V2_NOTES.md)
const MAX_HP := 4.0              # pickaxe 2 per hit, axe 1
const WANDER_SPEED := 18.0
const CHASE_SPEED := 60.0        # the player runs 100, so you can outrun them
const SIGHT := 96.0              # 6 tiles
const LOSE_SIGHT := 200.0
const ATTACK_RANGE := 18.0       # start the windup this close (centre to centre)
const HIT_RANGE := 24.0          # still this close when the windup ends = hit
const WINDUP := 0.4
const COOLDOWN := 1.0
const DAMAGE := 1                # half-hearts
const HURT_TIME := 0.3
const KNOCKBACK := 90.0
const STEP_JUMP := -235.0        # enough for a 1-block step, not for 2
const DROP_CHANCE := 0.3
const DEATH_TIME := 0.8

var state := State.IDLE
var hp := MAX_HP
var player: Node = null
var safe_x := 0.0
var safe_radius := 96.0
var floor_at: Callable
var loot_mult := 1.0
var facing := 1.0
var _timer := 0.0                # time left in the current state (windup, hurt, cooldown)
var _cooldown := 0.0
var _wander_dir := 1.0
var _wander_left := 0.0
var sprite: AnimatedSprite2D = null
var body: Node2D = null          # placeholder visual

func setup(p: Node, hatch_x: float, radius: float, floor_fn: Callable, mult := 1.0) -> void:
	player = p
	safe_x = hatch_x
	safe_radius = radius
	floor_at = floor_fn
	loot_mult = mult

func _ready() -> void:
	add_to_group("zombies")
	_wander_dir = -1.0 if randf() < 0.5 else 1.0
	_build_visual()

func _build_visual() -> void:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim in [["walk", 6.0, true], ["attack", 8.0, false], ["death", 6.0, false], ["hurt", 8.0, false]]:
		var tex := Art.frames(ART % anim[0])
		if tex.is_empty():
			continue
		sf.add_animation(anim[0])
		sf.set_animation_speed(anim[0], anim[1])
		sf.set_animation_loop(anim[0], anim[2])
		for t in tex:
			sf.add_frame(anim[0], t)
	if sf.has_animation("walk"):
		sprite = AnimatedSprite2D.new()
		sprite.sprite_frames = sf
		sprite.centered = false
		add_child(sprite)
		_play("walk")
		return
	body = Node2D.new()
	add_child(body)
	var skin := ColorRect.new()
	skin.color = Color(0.42, 0.5, 0.42)
	skin.position = Vector2(-6, -24)
	skin.size = Vector2(12, 24)
	body.add_child(skin)
	var shirt := ColorRect.new()
	shirt.color = Color(0.55, 0.35, 0.25)
	shirt.position = Vector2(-6, -15)
	shirt.size = Vector2(12, 8)
	body.add_child(shirt)
	for ex in [-3, 2]:
		var eye := ColorRect.new()
		eye.color = Color(0.75, 1.0, 0.25)
		eye.position = Vector2(ex, -21)
		eye.size = Vector2(2, 2)
		eye.name = "Eye"
		body.add_child(eye)

func _play(anim: String) -> void:
	if sprite == null or not sprite.sprite_frames.has_animation(anim):
		return
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)
	var tex := sprite.sprite_frames.get_frame_texture(anim, 0)
	sprite.offset = Vector2(-floorf(tex.get_width() / 2.0), -tex.get_height())

func is_dead() -> bool:
	return state == State.DEAD

# Rect a swing has to touch.
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-6, -24), Vector2(12, 24))

func _player_ok() -> bool:
	return player != null and is_instance_valid(player) and not player.dead and not player.frozen

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	_cooldown = maxf(0.0, _cooldown - delta)
	_timer -= delta
	match state:
		State.IDLE: _idle(delta)
		State.CHASE: _chase()
		State.ATTACK: _attack()
		State.HURT:
			if _timer <= 0.0:
				state = State.CHASE
		State.DEAD:
			velocity.x = 0.0
	_keep_out_of_safe_zone(delta)
	var want_x := velocity.x
	move_and_slide()
	# hop up 1-block steps while walking
	if state in [State.IDLE, State.CHASE] and is_on_floor() and is_on_wall() and want_x != 0.0:
		velocity.y = STEP_JUMP
		if state == State.IDLE and randf() < 0.3:
			_wander_dir = -_wander_dir
	_update_visual()

func _dist_to_player() -> Vector2:
	return player.global_position - global_position

func _sees_player() -> bool:
	if not _player_ok():
		return false
	var d := _dist_to_player()
	return absf(d.x) < SIGHT and absf(d.y) < 48.0

func _idle(delta: float) -> void:
	_wander_left -= delta
	if _wander_left <= 0.0:
		_wander_left = randf_range(1.5, 3.5)
		_wander_dir = [-1.0, 0.0, 1.0][randi() % 3]
	velocity.x = _wander_dir * WANDER_SPEED
	if _sees_player():
		state = State.CHASE

func _chase() -> void:
	if not _player_ok():
		state = State.IDLE
		return
	var d := _dist_to_player()
	if absf(d.x) > LOSE_SIGHT or absf(d.y) > 80.0:
		state = State.IDLE
		return
	facing = signf(d.x) if d.x != 0.0 else facing
	if absf(d.x) < ATTACK_RANGE and absf(d.y) < 20.0:
		velocity.x = 0.0
		if _cooldown <= 0.0:
			state = State.ATTACK
			_timer = WINDUP
			_play("attack")
		return
	velocity.x = facing * CHASE_SPEED

# Stands still for WINDUP (the telegraph), then hits if the player is still close.
func _attack() -> void:
	velocity.x = 0.0
	if _timer > 0.0:
		return
	if _player_ok():
		var d := _dist_to_player()
		if absf(d.x) < HIT_RANGE and absf(d.y) < 24.0:
			player.take_damage(DAMAGE, "zombie", global_position)
	_cooldown = COOLDOWN
	state = State.CHASE

# The hatch safe zone works like a wall: no step may end inside it.
func _keep_out_of_safe_zone(delta: float) -> void:
	var next := global_position.x + velocity.x * delta
	if absf(next - safe_x) < safe_radius and absf(next - safe_x) < absf(global_position.x - safe_x) + 0.01:
		velocity.x = 0.0
		if state == State.IDLE:
			_wander_dir = signf(global_position.x - safe_x)

# damage from a swing; from_x = where it came from (knockback away from it).
func take_hit(amount: float, from_x: float) -> bool:
	if state == State.DEAD:
		return false
	hp -= amount
	Chips.burst(get_parent(), global_position + Vector2(0, -14), "toxic", 5)
	_flash()
	var dir := signf(global_position.x - from_x)
	if dir == 0.0:
		dir = 1.0
	if hp <= 0.0:
		_die()
		return true
	state = State.HURT
	_timer = HURT_TIME
	velocity = Vector2(dir * KNOCKBACK, -90.0)
	_play("hurt")
	return true

func _flash() -> void:
	var node: CanvasItem = sprite if sprite else body
	var tw := create_tween()
	tw.tween_property(node, "modulate", Color(2, 2, 2), 0.05)
	tw.tween_property(node, "modulate", Color(1, 1, 1), 0.1)

func _die() -> void:
	state = State.DEAD
	collision_layer = 0
	_play("death")
	if randf() < DROP_CHANCE:
		var p: Node2D = PickupScript.new()
		p.position = global_position + Vector2(0, -8)
		get_parent().add_child(p)
		p.setup("food" if randf() < 0.5 else "scrap", player, floor_at, Vector2(randf_range(-20, 20), -100))
	var tw := create_tween()
	if sprite == null:
		tw.tween_property(body, "rotation", -facing * PI / 2.0, 0.3)
	tw.tween_interval(DEATH_TIME * 0.5)
	tw.tween_property(self, "modulate:a", 0.0, DEATH_TIME * 0.5)
	tw.tween_callback(queue_free)
	died.emit(self)

func _update_visual() -> void:
	if velocity.x != 0.0 and state != State.HURT:
		facing = signf(velocity.x)
	if sprite:
		sprite.flip_h = facing < 0.0
		if state in [State.IDLE, State.CHASE]:
			_play("walk")
			sprite.speed_scale = 0.4 if absf(velocity.x) < 1.0 else (1.5 if state == State.CHASE else 0.8)
	elif body:
		body.scale.x = facing
		# windup telegraph: lean forward and eyes glow brighter
		body.rotation = facing * 0.25 if state == State.ATTACK else (body.rotation if state == State.DEAD else 0.0)
