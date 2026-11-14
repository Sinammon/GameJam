extends Area2D
# The bunker hatch. Stand in it and press E to bank loot.
# Also tells the expedition whether the player is "inside" (safe from radiation).

signal bank_requested(player: Node)

const CONFIRM_TIME := 2.0      # seconds to press E again when carrying nothing

var player_inside := false
var _confirm_left := 0.0

func _ready() -> void:
	body_entered.connect(func(b): if b.is_in_group("player"): player_inside = true)
	body_exited.connect(func(b): if b.is_in_group("player"): player_inside = false)

func _process(delta: float) -> void:
	_confirm_left = maxf(0.0, _confirm_left - delta)

func can_interact(_player: Node) -> bool:
	return player_inside

func interact(player: Node) -> void:
	if not player_inside:
		return
	# Going home empty-handed ends the expedition, so ask once: this stops an
	# accidental E right after spawning (you start inside the hatch).
	if player.total_items() == 0 and _confirm_left <= 0.0:
		_confirm_left = CONFIRM_TIME
		player.say("Nothing to bank. Press E again to go inside")
		return
	_confirm_left = 0.0
	bank_requested.emit(player)
