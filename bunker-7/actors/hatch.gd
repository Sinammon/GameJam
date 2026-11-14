extends Area2D
# The bunker hatch. Stand in it and press E to bank loot.
# Also tells the expedition whether the player is "inside" (safe from radiation).

signal bank_requested(player: Node)

var player_inside := false

func _ready() -> void:
	body_entered.connect(func(b): if b.is_in_group("player"): player_inside = true)
	body_exited.connect(func(b): if b.is_in_group("player"): player_inside = false)

func interact(player: Node) -> void:
	if player_inside:
		bank_requested.emit(player)
