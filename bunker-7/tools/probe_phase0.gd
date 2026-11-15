# Phase 0 probe (V2_NOTES.md): real GameState, Normal difficulty.
extends SceneTree
var ex: Node2D
var p: CharacterBody2D
func frames(n: int) -> void:
	for i in n: await physics_frame
func key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var gs: Node = root.get_node("GameState")
	gs.start_game(1)
	gs.set_process_unhandled_key_input(false)
	ex = load("res://scenes/expedition.tscn").instantiate()
	root.add_child(ex)
	p = ex.player
	await frames(20)
	print("hatch x=%.0f world_w=%d player x=%.0f" % [ex.hatch.position.x, ex.WORLD_W, p.position.x])
	key(KEY_A, true)
	await frames(120)
	key(KEY_A, false)
	print("after 2 s holding A: player x=%.0f (left wall at 0), radiation %.2f" % [p.position.x, ex.radiation])
	# stand still just outside the hatch: how long until death?
	p.global_position = Vector2(ex.HATCH_X + 60, ex.surface_y(ex.HATCH_X + 60) - 2)
	ex.radiation = 0.0
	var t := 0
	while not ex.ended and t < 60 * 300:
		await physics_frame
		t += 1
	print("standing near hatch: death after %.1f s (ended=%s)" % [t / 60.0, ex.ended])
	quit(0)
