extends CharacterBody2D
# The survivor: walk, jump, carry loot, interact with E.
# Art: AnimatedSprite2D built from art/characters_clean/survivor_*.png. If the
# frames are missing, the old orange ColorRect ("Body") is shown instead.

signal message(text: String)   # HUD shows these
signal items_changed
signal collapse_done           # emitted when the death "animation" ends

const BASE_SPEED := 100.0
const JUMP_VELOCITY := -290.0

# What the player carries. Keys match the GameState contract.
var items := {"wood": 0, "concrete": 0, "scrap": 0, "circuits": 0, "water": 0, "food": 0}
var dead := false
var frozen := false            # true after banking: no more input
var speed := BASE_SPEED
var carry_limit := 12

@onready var interact_area: Area2D = $InteractArea
@onready var body_rect: ColorRect = $Body

const ART_DIR := "res://art/characters_clean/survivor_%s_%d.png"
# animation -> [frames, fps, loop]
const ANIMS := {
	"idle": [4, 4.0, true], "walk": [4, 8.0, true], "jump": [4, 0.0, false],
	"mine": [4, 10.0, false], "collapse": [4, 4.5, false],
}
const COLLAPSE_TIME := 0.9     # seconds before collapse_done (art or not)

var sprite: AnimatedSprite2D = null   # null = placeholder rectangle
var _action_left := 0.0                # > 0 while a one-shot "mine" plays

func _ready() -> void:
	# Upgrades don't change mid-expedition, so read them once.
	speed = BASE_SPEED * (1.0 + GSBridge.move_speed_bonus())
	carry_limit = GSBridge.carry_limit()
	_build_sprite()

# Builds the survivor SpriteFrames. Any missing frame drops that animation;
# without idle/walk the placeholder rectangle stays.
func _build_sprite() -> void:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim in ANIMS:
		var tex: Array[Texture2D] = []
		for i in ANIMS[anim][0]:
			var path := ART_DIR % [anim, i]
			if not ResourceLoader.exists(path):
				tex.clear()
				break
			tex.append(load(path))
		if tex.is_empty():
			continue
		sf.add_animation(anim)
		sf.set_animation_speed(anim, ANIMS[anim][1])
		sf.set_animation_loop(anim, ANIMS[anim][2])
		for t in tex:
			sf.add_frame(anim, t)
	if not (sf.has_animation("idle") and sf.has_animation("walk")):
		return
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = sf
	sprite.centered = false
	add_child(sprite)
	body_rect.visible = false
	_play("idle")

# Plays anim with its feet at (0,0). Frame sizes differ per animation.
func _play(anim: String) -> void:
	if sprite == null or not sprite.sprite_frames.has_animation(anim):
		return
	if sprite.animation != anim:
		sprite.play(anim)
	var tex := sprite.sprite_frames.get_frame_texture(anim, 0)
	sprite.offset = Vector2(-floorf(tex.get_width() / 2.0), -tex.get_height())

func _process(delta: float) -> void:
	if sprite == null or dead:
		return
	_action_left = maxf(0.0, _action_left - delta)
	if velocity.x != 0.0:
		sprite.flip_h = velocity.x < 0.0
	if not is_on_floor() and sprite.sprite_frames.has_animation("jump"):
		_play("jump")
		sprite.pause()
		# crouch, rise, peak, fall by vertical speed
		sprite.frame = 1 if velocity.y < -120.0 else (2 if velocity.y < 60.0 else 3)
	elif _action_left > 0.0:
		_play("mine")
	elif absf(velocity.x) > 1.0:
		_play("walk")
	else:
		_play("idle")
	if not sprite.is_playing() and sprite.animation != "jump" and sprite.animation != "mine":
		sprite.play()

# Short pickaxe swing when something is looted.
func play_action() -> void:
	if sprite and sprite.sprite_frames.has_animation("mine"):
		_action_left = 0.4
		_play("mine")
		sprite.set_frame_and_progress(0, 0.0)
		sprite.play("mine")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	if dead or frozen:
		velocity.x = 0.0
		move_and_slide()
		return
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	velocity.x = Input.get_axis("move_left", "move_right") * speed
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if dead or frozen or not event.is_action_pressed("interact"):
		return
	var target := pick_interactable()
	if target:
		get_viewport().set_input_as_handled()
		var before := total_items()
		target.interact(self)
		if total_items() > before:
			play_action()

# Nearest thing in reach that has something to do (full crate, pack, hatch).
# The hatch loses ties so loot lying in the hatch is picked up before banking.
# If nothing is "ready", fall back to any interactable (e.g. "Empty crate").
func pick_interactable() -> Area2D:
	var best: Area2D = null
	var best_d := INF
	var fallback: Area2D = null
	for area in interact_area.get_overlapping_areas():
		if not area.has_method("interact"):
			continue
		if fallback == null:
			fallback = area
		if area.has_method("can_interact") and not area.can_interact(self):
			continue
		var d := global_position.distance_to(area.global_position)
		if area.is_in_group("hatch"):
			d += 10000.0
		if d < best_d:
			best_d = d
			best = area
	return best if best else fallback

func say(text: String) -> void:
	message.emit(text)

func total_items() -> int:
	var n := 0
	for k in items:
		n += items[k]
	return n

func capacity_left() -> int:
	return maxi(0, carry_limit - total_items())

# Adds up to n of a kind, respecting the carry limit. Returns how many were added.
# Unknown kinds are refused so the dict always matches the contract.
func add_item(kind: String, n: int) -> int:
	if not items.has(kind):
		return 0
	var added := clampi(n, 0, capacity_left())
	if added > 0:
		items[kind] += added
		items_changed.emit()
	return added

func clear_items() -> void:
	for k in items:
		items[k] = 0
	items_changed.emit()

# Collapse: plays survivor_collapse (holds the last frame), or tips the placeholder
# rectangle over. collapse_done fires after COLLAPSE_TIME either way.
# Only the visual changes; the collision box stays upright so it can't clip the floor.
func die() -> void:
	if dead:
		return
	dead = true
	if sprite and sprite.sprite_frames.has_animation("collapse"):
		_play("collapse")
		sprite.modulate = Color(1.0, 0.75, 0.6)   # radiation-sick tint
		var t := create_tween()
		t.tween_interval(COLLAPSE_TIME)
		t.tween_callback(collapse_done.emit)
		return
	body_rect.pivot_offset = Vector2(body_rect.size.x * 0.5, body_rect.size.y)   # feet
	var tw := create_tween()
	tw.tween_property(body_rect, "rotation_degrees", 90.0, 0.6)
	tw.parallel().tween_property(body_rect, "modulate:a", 0.3, 0.9)
	tw.tween_callback(collapse_done.emit)
