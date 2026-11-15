extends Node2D
# The survivor inside the bunker: walks left/right on one flat floor (no physics, no
# health, no inventory) and climbs the ladder in scripted moves. The bunker scene
# decides what E does; this node only moves and animates.
# Art: survivor_idle/walk/climb/wakeup frames via actors/art.gd; missing art = orange box.

signal climb_finished

const SPEED := 85.0
const CLIMB_SPEED := 110.0      # px/s on the ladder
const FRAMES := "res://art/characters_clean/survivor_%s"
# animation -> [fps, loop]
const ANIMS := {"idle": [4.0, true], "walk": [8.0, true], "climb": [8.0, true], "wakeup": [3.0, false]}

var min_x := 0.0
var max_x := 1000.0
var can_walk := true            # the bunker turns this off for popups, the tutorial, transitions
var climbing := false
var facing := 1.0
var moving := false
var sprite: AnimatedSprite2D = null
var body: ColorRect = null
var _climb_tween: Tween
var _step_left := 0.0
var _step_alt := false

func _ready() -> void:
	_build_sprite()

func _build_sprite() -> void:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim in ANIMS:
		var tex := Art.frames(FRAMES % anim, 6)
		if tex.is_empty():
			continue
		if anim == "wakeup":
			tex.reverse()   # the frames go standing -> lying; we want to get up
		sf.add_animation(anim)
		sf.set_animation_speed(anim, ANIMS[anim][0])
		sf.set_animation_loop(anim, ANIMS[anim][1])
		for t in tex:
			sf.add_frame(anim, t)
	if sf.has_animation("idle") and sf.has_animation("walk"):
		sprite = AnimatedSprite2D.new()
		sprite.name = "Sprite"
		sprite.sprite_frames = sf
		sprite.centered = false
		add_child(sprite)
		play("idle")
		return
	body = ColorRect.new()   # placeholder survivor
	body.name = "Body"
	body.color = Color(0.9, 0.55, 0.2)
	body.size = Vector2(10, 24)
	body.position = Vector2(-5, -24)
	add_child(body)

# Feet at (0, 0) whatever the frame size.
func play(anim: String) -> void:
	if sprite == null or not sprite.sprite_frames.has_animation(anim):
		return
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)
	var tex := sprite.sprite_frames.get_frame_texture(anim, 0)
	sprite.offset = Vector2(-floorf(tex.get_width() / 2.0), -tex.get_height())

func has_anim(anim: String) -> bool:
	return sprite != null and sprite.sprite_frames.has_animation(anim)

func _physics_process(delta: float) -> void:
	if climbing:
		return
	var dir := Input.get_axis("move_left", "move_right") if can_walk else 0.0
	moving = dir != 0.0
	if moving:
		facing = signf(dir)
		position.x = clampf(position.x + dir * SPEED * delta, min_x, max_x)
		_step_left -= delta
		if _step_left <= 0.0:
			_step_left = 0.34
			_step_alt = not _step_alt
			Sfx.play("footstep_2" if _step_alt else "footstep_1", -2.0, 0.08)
	else:
		_step_left = 0.05
	if sprite:
		if sprite.animation == "wakeup" and sprite.is_playing() and not moving:
			return
		sprite.flip_h = facing < 0.0
		play("walk" if moving else "idle")

# Climb from where we are to `to` (straight line, ladder speed). Emits climb_finished.
func climb_to(to: Vector2) -> void:
	climbing = true
	moving = false
	if sprite:
		sprite.flip_h = false
		if has_anim("climb"):
			play("climb")
	if _climb_tween:
		_climb_tween.kill()
	var time := maxf(0.2, position.distance_to(to) / CLIMB_SPEED)
	Sfx.play("ladder_climb")
	_climb_tween = create_tween()
	_climb_tween.tween_property(self, "position", to, time)
	_climb_tween.tween_callback(_on_climb_done)

func _on_climb_done() -> void:
	climbing = false
	play("idle")
	climb_finished.emit()

# Getting up from the cot (new day). Plays once; walking cuts it short.
func wake_up() -> void:
	if has_anim("wakeup"):
		play("wakeup")
