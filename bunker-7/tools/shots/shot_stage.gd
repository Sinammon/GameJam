extends Node
# Stages the expedition for screenshots (run through run_scenario.py, see
# COMMANDS_CODER1.md). mode "tree": chopping a tree. mode "hole": a mined hole
# with a zombie next to it. Not part of the game.

@export var mode := "tree"
var ex: Node2D

func _ready() -> void:
	ex = load("res://scenes/expedition.tscn").instantiate()
	ex.zombies_enabled = false
	add_child(ex)
	_stage.call_deferred()

func _frames(n: int) -> void:   # n frames' worth of real time (60 fps)
	await get_tree().create_timer(n / 60.0).timeout

func _stage() -> void:
	await _frames(5)
	var p: Node2D = ex.player
	if mode == "tree":
		var t: Node2D = get_tree().get_nodes_in_group("trees").filter(func(n: Node) -> bool: return n.size == "large")[0]
		p.global_position = Vector2(t.position.x - 14, ex.floor_y(t.position.x - 14) - 1)
		p.face(1.0)
		ex.camera.zoom = Vector2(2, 2)   # closer look at the tree
		await _frames(10)
		ex.swing.aim_override = t.position + Vector2(0, -20)   # ignore the real mouse
		for i in 7:   # the last hit fells it; the screenshot catches it falling
			print("[shot] swing ", ex.swing.use("axe"), " tree hp ", t.hp)
			await _frames(27)
		return
	# hole: a staircase pit 4 deep, the player at the bottom, a zombie at the edge
	var m: Node2D = ex.mining
	var c := 0
	for col in range(ex.HATCH_COL + 40, ex.COLS - 10):
		if not m.protected_cols.has(col) and not m.protected_cols.has(col + 1) and not m.protected_cols.has(col + 2) and ex.surface_rows[col] == ex.BASE_ROW and ex.surface_rows[col + 2] == ex.BASE_ROW:
			c = col
			break
	for d in 2: m.hit(Vector2i(c, ex.BASE_ROW + d), 99.0)
	for d in 4: m.hit(Vector2i(c + 1, ex.BASE_ROW + d), 99.0)
	for d in 2: m.hit(Vector2i(c + 2, ex.BASE_ROW + d), 99.0)
	m.damage[Vector2i(c + 3, ex.BASE_ROW)] = 2.0   # a cracked block next to the pit
	m.queue_redraw()
	await _frames(2)
	p.global_position = Vector2((c + 1) * 16 + 8, (ex.BASE_ROW + 4) * 16 - 1)
	p.face(1.0)
	ex.spawner.spawn_at((c + 5) * 16 + 8)
	await _frames(10)
	ex.inventory.select(1)
	ex.swing.aim_override = p.global_position + Vector2(20, 0)
	ex.swing.use("pickaxe")
