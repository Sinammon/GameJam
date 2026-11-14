extends CharacterBody2D
# Placeholder player: walk, jump, carry loot, interact with E.

signal message(text: String)   # HUD shows these
signal items_changed
signal collapse_done           # emitted when the death "animation" ends

const BASE_SPEED := 100.0
const JUMP_VELOCITY := -290.0

# What the player carries. Keys match the GameState contract.
var items := {"wood": 0, "concrete": 0, "scrap": 0, "circuits": 0}
var dead := false
var frozen := false            # true after banking: no more input
var speed := BASE_SPEED
var carry_limit := 12

@onready var interact_area: Area2D = $InteractArea
@onready var body_rect: ColorRect = $Body

func _ready() -> void:
	# Upgrades don't change mid-expedition, so read them once.
	speed = BASE_SPEED * (1.0 + GSBridge.move_speed_bonus())
	carry_limit = GSBridge.carry_limit()

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
		target.interact(self)

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

# Placeholder collapse: tip the sprite over and fade. Swap for the
# survivor_collapse animation later (emit collapse_done when it ends).
# Only the visual rotates; the collision box stays upright so it can't clip the floor.
func die() -> void:
	if dead:
		return
	dead = true
	body_rect.pivot_offset = Vector2(body_rect.size.x * 0.5, body_rect.size.y)   # feet
	var tw := create_tween()
	tw.tween_property(body_rect, "rotation_degrees", 90.0, 0.6)
	tw.parallel().tween_property(body_rect, "modulate:a", 0.3, 0.9)
	tw.tween_callback(collapse_done.emit)
