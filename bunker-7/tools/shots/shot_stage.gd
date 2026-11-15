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
	if mode.begins_with("light_"):
		await _light_stage(p)
		return
	if mode == "zombie":   # close-up: the player holding the flashlight, a zombie winding up next to them
		var x: float = ex.HATCH_X + 400.0
		p.global_position = Vector2(x, ex.floor_y(x) - 1)
		p.face(1.0)
		ex.inventory.select(2)
		ex.camera.zoom = Vector2(2, 2)
		p.health.invuln_left = 99.0
		var z: Node2D = ex.spawner.spawn_at(x + 22.0)
		ex.spawner.spawn_at(x - 64.0)   # a second one walking in from the left
		await _frames(40)
		if z:
			z.global_position.x = x + 22.0
		return
	if mode == "ore":   # a pit whose walls show every ore tile, one cracked
		var mo: Node2D = ex.mining
		var oc := 0
		for col in range(ex.HATCH_COL + 40, ex.COLS - 10):
			if not mo.protected_cols.has(col) and not mo.protected_cols.has(col + 1) and not mo.protected_cols.has(col + 2) and ex.surface_rows[col] == ex.BASE_ROW and ex.surface_rows[col + 2] == ex.BASE_ROW:
				oc = col
				break
		for d in 2: mo.hit(Vector2i(oc, ex.BASE_ROW + d), 99.0)
		for d in 3: mo.hit(Vector2i(oc + 1, ex.BASE_ROW + d), 99.0)
		var kinds := ["scrap_ore", "concrete", "circuits", "bedrock", "planks", "pipe", "bones", "toxic"]
		var cells := [Vector2i(oc - 1, ex.BASE_ROW + 1), Vector2i(oc - 1, ex.BASE_ROW + 2), Vector2i(oc, ex.BASE_ROW + 2),
			Vector2i(oc + 1, ex.BASE_ROW + 3), Vector2i(oc + 2, ex.BASE_ROW + 1), Vector2i(oc + 2, ex.BASE_ROW + 2),
			Vector2i(oc + 3, ex.BASE_ROW + 1), Vector2i(oc + 2, ex.BASE_ROW + 3)]
		for i in kinds.size():
			mo.place(cells[i], kinds[i], Vector2i.ZERO)
		mo.damage[Vector2i(oc + 2, ex.BASE_ROW)] = 2.0
		mo.damage[Vector2i(oc + 3, ex.BASE_ROW)] = 4.0
		mo.queue_redraw()
		p.global_position = Vector2((oc + 1) * 16 + 8, (ex.BASE_ROW + 3) * 16 - 1)
		p.face(-1.0)
		ex.camera.zoom = Vector2(2, 2)
		await _frames(10)
		ex.inventory.select(1)
		ex.swing.aim_override = p.global_position + Vector2(-20, 0)
		ex.swing.use("pickaxe")
		return
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

# Lighting shots (Phase 3): quality from the SHOT_QUALITY env var (full/simple/off).
func _light_stage(p: Node2D) -> void:
	var q := OS.get_environment("SHOT_QUALITY")
	if ex.lighting and q != "":
		ex.lighting.set_quality(q)
	var m: Node2D = ex.mining
	match mode:
		"light_hatch":   # just outside the hatch, radiation low
			p.global_position = Vector2(ex.HATCH_X + 60, ex.floor_y(ex.HATCH_X + 60) - 1)
			p.face(-1.0)
			ex.radiation = 10.0
		"light_depot":   # far out in the depot, radiation high, an exposed toxic crystal
			var target := Vector2i(-1, -1)
			for c in ex.toxic_cells:
				if c.x < 40 and c.x > 14 and (target.x < 0 or c.y > target.y):
					target = c
			if target.x >= 0:
				for y in range(m.floor_rows[target.x], target.y):
					m._break(Vector2i(target.x, y), m.kind_at(Vector2i(target.x, y)))
				ex._update_toxic_glow()
			var x := target.x * 16.0 + 40.0 if target.x >= 0 else 300.0
			p.global_position = Vector2(x, ex.floor_y(x) - 1)
			p.face(-1.0)
			ex.radiation = 80.0
			print("[shot] toxic cell ", target)
		"light_hole":   # at the bottom of a mined pit with the flashlight, middle of the market
			var c := 0
			for col in range(ex.HATCH_COL + 60, ex.COLS - 10):
				if not m.protected_cols.has(col) and not m.protected_cols.has(col + 1) and not m.protected_cols.has(col + 2) and ex.surface_rows[col] == ex.BASE_ROW and ex.surface_rows[col + 2] == ex.BASE_ROW:
					c = col
					break
			for d in 2: m.hit(Vector2i(c, ex.BASE_ROW + d), 99.0)
			for d in 4: m.hit(Vector2i(c + 1, ex.BASE_ROW + d), 99.0)
			for d in 2: m.hit(Vector2i(c + 2, ex.BASE_ROW + d), 99.0)
			await _frames(2)
			p.global_position = Vector2((c + 1) * 16 + 8, (ex.BASE_ROW + 4) * 16 - 1)
			p.face(1.0)
			ex.inventory.select(2)
			ex.radiation = 50.0
			ex.spawner.spawn_at((c + 6) * 16 + 8)
	await _frames(90)   # let the ambient settle
	if ex.lighting:
		ex.lighting.ambient = ex.lighting.ambient_target
