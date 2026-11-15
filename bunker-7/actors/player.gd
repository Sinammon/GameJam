extends CharacterBody2D
# The survivor: walk, jump, carry loot, interact with E.
# Art: AnimatedSprite2D built from art/characters_clean/survivor_*.png. If the
# frames are missing, the old orange ColorRect ("Body") is shown instead.

signal message(text: String)   # HUD shows these
signal items_changed
signal collapse_done           # emitted when the death "animation" ends
signal hurt(amount: int, source: String)
signal out_of_health(reason: String)   # health hit 0; the expedition runs the death sequence

const BASE_SPEED := 100.0
const JUMP_VELOCITY := -290.0

# What the player carries. Keys match the GameState contract.
var items := {"wood": 0, "concrete": 0, "scrap": 0, "circuits": 0, "water": 0, "food": 0}
var dead := false
var frozen := false            # true after banking: no more input
var speed := BASE_SPEED
var carry_limit := 12
var death_reason := ""         # "radiation", "zombie", ... kept for the HUD death line
var health: Node = null        # actors/health.gd, created in _ready
var _stun_left := 0.0          # > 0 after knockback: input doesn't steer
var facing := 1.0              # -1 left, +1 right (last walking direction or swing aim)

const HealthScript := preload("res://actors/health.gd")
const KNOCKBACK_SPEED := 170.0
const KNOCKBACK_TIME := 0.25

@onready var interact_area: Area2D = $InteractArea
@onready var body_rect: ColorRect = $Body

const ART_DIR := "res://art/characters_clean/survivor_%s_%d.png"
# animation -> [frames, fps, loop]
const ANIMS := {
	"idle": [4, 4.0, true], "walk": [4, 8.0, true], "jump": [4, 0.0, false],
	"mine": [4, 10.0, false], "collapse": [4, 4.5, false], "hurt": [2, 8.0, false],
	"chop": [4, 10.0, false],
}
# tool -> swing animation (played by use_tool if the frames exist)
const TOOL_ANIMS := {"axe": "chop", "pickaxe": "mine"}
const COLLAPSE_TIME := 0.9     # seconds before collapse_done (art or not)

var sprite: AnimatedSprite2D = null   # null = placeholder rectangle
var _action_left := 0.0                # > 0 while a one-shot "mine"/"hurt" plays
var _action_anim := "mine"

func _ready() -> void:
	# Upgrades don't change mid-expedition, so read them once.
	speed = BASE_SPEED * (1.0 + GSBridge.move_speed_bonus())
	carry_limit = GSBridge.carry_limit()
	health = HealthScript.new()
	health.name = "Health"
	add_child(health)
	health.setup(GSBridge.max_health())
	health.depleted.connect(_on_depleted)
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
	sprite.flip_h = facing < 0.0
	if not is_on_floor() and sprite.sprite_frames.has_animation("jump"):
		_play("jump")
		sprite.pause()
		# crouch, rise, peak, fall by vertical speed
		sprite.frame = 1 if velocity.y < -120.0 else (2 if velocity.y < 60.0 else 3)
	elif _action_left > 0.0:
		_play(_action_anim)
	elif absf(velocity.x) > 1.0:
		_play("walk")
	else:
		_play("idle")
	if not sprite.is_playing() and not sprite.animation in ["jump", "mine", "hurt"]:
		sprite.play()

# Short pickaxe swing when something is looted. Returns false without art.
func play_action(anim := "mine", time := 0.4) -> bool:
	if sprite and sprite.sprite_frames.has_animation(anim):
		_action_left = time
		_action_anim = anim
		_play(anim)
		sprite.set_frame_and_progress(0, 0.0)
		sprite.play(anim)
		return true
	return false

# Swing animation for a tool (scenes/tool_swing.gd decides what it hits).
# Returns false if there is no animation (the swing then draws an arc).
func use_tool(tool_id: String) -> bool:
	if dead or frozen or not TOOL_ANIMS.has(tool_id):
		return false
	return play_action(TOOL_ANIMS[tool_id], 0.35)

func face(dir: float) -> void:
	if dir != 0.0:
		facing = signf(dir)

# --- health ------------------------------------------------------------------

# amount in half-hearts. from_pos (optional) = where the hit came from, for knockback.
# Returns true if it landed (i-frames swallow repeated hits, except radiation).
func take_damage(amount: int, source: String, from_pos: Variant = null) -> bool:
	if dead or frozen or health == null:
		return false
	if not health.take_damage(amount, source):
		return false
	hurt.emit(amount, source)
	if dead:
		return true   # this hit was the last one
	_flash()
	if from_pos is Vector2:
		knockback(signf(global_position.x - from_pos.x))
	if source != "radiation":
		play_action("hurt", 0.3)
	return true

# Pushes the player away (dir -1 = left, +1 = right) with a small hop.
func knockback(dir: float, force := KNOCKBACK_SPEED) -> void:
	if dead or frozen:
		return
	velocity.x = (dir if dir != 0.0 else 1.0) * force
	if is_on_floor():
		velocity.y = -force * 0.6
	_stun_left = KNOCKBACK_TIME

func _flash() -> void:
	var node: CanvasItem = body_rect
	if sprite:
		node = sprite
	var tw := create_tween()
	for i in 3:
		tw.tween_property(node, "modulate", Color(1.6, 0.5, 0.5, 0.6), 0.05)
		tw.tween_property(node, "modulate", Color(1, 1, 1, 1), 0.05)

func _on_depleted(source: String) -> void:
	death_reason = source
	out_of_health.emit(source)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	if dead or frozen:
		velocity.x = 0.0
		move_and_slide()
		return
	if _stun_left > 0.0:   # knocked back: keep the push, no steering
		_stun_left -= delta
		move_and_slide()
		return
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	velocity.x = Input.get_axis("move_left", "move_right") * speed
	face(velocity.x)
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
func die(reason := "") -> void:
	if dead:
		return
	dead = true
	if reason != "":
		death_reason = reason
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
