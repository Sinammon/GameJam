extends Node
# Stages the walkable bunker for screenshots (run_scenario.py, see COMMANDS_CODER1.md). Not part of the game.
# mode: "overview" (bedroom, a few rooms open, a building), "popup" (utility workbench popup),
# "ladder" (arriving down the shaft), "upgrade" (upgrade bench popup), "door" (locked door popup).
# Uses its own settings file so the player's hints / tutorial flags are never touched.

@export var mode := "overview"
var b: Node2D

func _ready() -> void:
	SettingsStore.path = "user://shot_bunker_settings.cfg"
	SettingsStore.reset(true)
	SettingsStore.set_value("tutorial_seen", true)
	var gs := GameState
	gs.seed_rng(7)
	gs.day = 3
	gs.water = 4
	gs.food = 3
	gs.wood = 9
	gs.concrete = 7
	gs.scrap = 12
	gs.circuits = 1
	gs.unlocked_rooms = ["bedroom", "utility", "storage"]
	gs.built = {"purifier": true, "door": true}
	gs.backpack_tier = 2
	gs.show_tutorial = false
	gs.bunker_arrival = "hatch" if mode == "ladder" else "cot"
	gs.last_banked = {"wood": 3, "scrap": 2}
	b = load("res://scenes/bunker.tscn").instantiate()
	add_child(b)
	_stage.call_deferred()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _stage() -> void:
	if mode == "ladder":
		await _wait(0.75)
		b.set_process(false)   # freeze mid-climb
		if b.walker._climb_tween:
			b.walker._climb_tween.pause()
		return
	await _wait(0.6)
	match mode:
		"overview":
			b.walker.position.x = b.station_x("workbench", "bedroom") - 2
			b.banner("")
		"popup":
			b.walker.position.x = b.station_x("workbench", "utility")
			await _wait(0.3)
			b.use_station(b.near)
		"upgrade":
			b.walker.position.x = b.station_x("upgrade", "bedroom")
			await _wait(0.3)
			b.use_station(b.near)
		"door":
			b.walker.position.x = b.room_x("storage") + b.DOOR_STAND
			await _wait(0.3)
			b.use_station(b.near)
