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

@onready var interact_area: Area2D = $InteractArea
@onready var body_rect: ColorRect = $Body

func _physics_process(delta: float) -> void:
	if dead:
		velocity.x = 0.0
		velocity += get_gravity() * delta
		move_and_slide()
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	var speed := BASE_SPEED * (1.0 + GameState.get_move_speed_bonus())
	velocity.x = Input.get_axis("move_left", "move_right") * speed
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if dead or not event.is_action_pressed("interact"):
		return
	# Use the first thing in reach that can be interacted with (crate, hatch, pack).
	for area in interact_area.get_overlapping_areas():
		if area.has_method("interact"):
			area.interact(self)
			return

func total_items() -> int:
	var n := 0
	for k in items:
		n += items[k]
	return n

func capacity_left() -> int:
	return maxi(0, GameState.get_carry_limit() - total_items())

# Adds up to n of a kind, respecting the carry limit. Returns how many were added.
func add_item(kind: String, n: int) -> int:
	var added := mini(n, capacity_left())
	if added > 0:
		items[kind] += added
		items_changed.emit()
	return added

func clear_items() -> void:
	for k in items:
		items[k] = 0
	items_changed.emit()

# Placeholder collapse: tip over and fade. Swap for an animation later.
func die() -> void:
	if dead:
		return
	dead = true
	var tw := create_tween()
	tw.tween_property(self, "rotation_degrees", 90.0, 0.6)
	tw.parallel().tween_property(body_rect, "modulate:a", 0.3, 0.9)
	tw.tween_callback(collapse_done.emit)
