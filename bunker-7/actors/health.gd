extends Node
# Hit points in half-hearts (10 = 5 hearts). Owned by the player; zombies and
# radiation call take_damage() through the player. Emits `depleted` once.

signal changed(hp: int, max_hp: int)
signal damaged(amount: int, source: String)
signal depleted(source: String)

const INVULN_TIME := 0.6        # seconds of i-frames after a hit
# Damage from these ignores i-frames (a steady drain must never be swallowed by a hit).
const IGNORES_INVULN := ["radiation"]

var max_hp := 10
var hp := 10
var invuln_left := 0.0
var last_source := ""            # what hit last; the death reason

func setup(max_value: int) -> void:
	max_hp = maxi(1, max_value)
	hp = max_hp
	changed.emit(hp, max_hp)

func _process(delta: float) -> void:
	invuln_left = maxf(0.0, invuln_left - delta)

func is_dead() -> bool:
	return hp <= 0

func is_invulnerable() -> bool:
	return invuln_left > 0.0

# Returns true if the damage landed.
func take_damage(amount: int, source: String) -> bool:
	if amount <= 0 or is_dead():
		return false
	if is_invulnerable() and not source in IGNORES_INVULN:
		return false
	hp = maxi(0, hp - amount)
	last_source = source
	if not source in IGNORES_INVULN:
		invuln_left = INVULN_TIME
	damaged.emit(amount, source)
	changed.emit(hp, max_hp)
	if hp == 0:
		depleted.emit(source)
	return true

func heal(amount: int) -> void:
	if amount <= 0 or is_dead():
		return
	hp = mini(max_hp, hp + amount)
	changed.emit(hp, max_hp)
