extends Area2D
# The bunker hatch. Stand in it and press E to bank loot.
# Also tells the expedition whether the player is "inside" (safe from radiation).
# Art: obj_hatch.png (closed) normally; obj_hatch_open.png (lid raised) while the player
# is within interact reach or inside, and for good once hold_open() is called (climbing down).

signal bank_requested(player: Node)

const CONFIRM_TIME := 2.0      # seconds to press E again when carrying nothing
const CLOSED_LIFT := 3.0       # px the art sinks below the ground line
const OPEN_LIFT := 4.0         # the open hatch's dirt base sits in the ground

var player_inside := false
var is_open := false           # read by tests / screenshots
var _confirm_left := 0.0
var _closed: Sprite2D = null
var _open: Sprite2D = null
var _held := false
var _player: Node = null
var exit_style := "hatch"      # V3: "rope" (Old Mine) / "ladder" (Bomb Crater) hide the hatch art

# The way home in another location: hide the hatch pictures (the expedition adds the rope/ladder).
func set_exit_style(style: String) -> void:
	exit_style = style
	if style == "hatch":
		return
	for n in [$Sprite, $Frame, _closed, _open]:
		if n:
			n.visible = false

func _ready() -> void:
	_closed = Art.sprite(self, "res://art/world_clean/obj_hatch.png", CLOSED_LIFT)
	if _closed:
		$Sprite.visible = false
		$Frame.visible = false
	_open = Art.sprite(self, "res://art/world_clean/obj_hatch_open.png", OPEN_LIFT)
	if _open:
		_open.visible = false
	body_entered.connect(func(b): if b.is_in_group("player"): player_inside = true)
	body_exited.connect(func(b): if b.is_in_group("player"): player_inside = false)

func _process(delta: float) -> void:
	_confirm_left = maxf(0.0, _confirm_left - delta)
	_set_open(_held or player_inside or _player_in_reach())

func _player_in_reach() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return false
	var area: Variant = _player.get("interact_area")
	return area is Area2D and (area as Area2D).overlaps_area(self)

func _set_open(open: bool) -> void:
	is_open = open
	if _open == null or exit_style != "hatch":
		return
	_open.visible = open
	if _closed:
		_closed.visible = not open
	else:
		$Sprite.visible = not open
		$Frame.visible = not open

# Climbing down: stays open and is drawn over the survivor so they sink into the shaft.
func hold_open() -> void:
	_held = true
	if exit_style != "hatch":
		return
	_set_open(true)
	if _open:
		_open.z_index = 1

func can_interact(_player_node: Node) -> bool:
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
