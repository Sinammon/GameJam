extends Node
# Stages the expedition for screenshots (run through run_scenario.py, see
# COMMANDS_CODER1.md). mode "tree": chopping a tree. mode "hole": a mined hole
# with a zombie next to it. Not part of the game.
# V3 art modes save their own captures (user://shot_<mode>_<n>.png) at exact moments:
# "zombie_death" (death frames side by side), "hud" (geiger levels, hotbar, backpack),
# "hatch" (closed / open in reach / climbing down), "tutorial" (all 7 slides, no expedition).

@export var mode := "tree"
var ex: Node2D

func _ready() -> void:
	if mode == "tutorial":
		_tutorial_stage.call_deferred()
		return
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
	if mode in ["zombie_death", "hud", "hatch"]:
		await _v3_stage(p)
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

# --- V3 art captures --------------------------------------------------------------

func _capture(n: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://shot_%s_%d.png" % [mode, n]
	img.save_png(path)
	print("[shot] saved ", ProjectSettings.globalize_path(path))

func _tutorial_stage() -> void:
	var t: Tutorial = Tutorial.open(self)
	t.auto_free = false
	for i in Tutorial.SLIDES.size():
		t.show_slide(i)
		await _frames(6)
		await _capture(i + 1)

func _v3_stage(p: Node2D) -> void:
	if ex.lighting:
		ex.lighting.set_quality("off")   # plain colours for judging the art
	p.health.invuln_left = 99.0
	match mode:
		"zombie_death":   # an idle walker + the 4 death frames (zombies killed 1/8 s apart), close-up
			var x := _flat_spot(12) * 16.0
			p.global_position = Vector2(x, ex.floor_y(x) - 1)
			p.face(1.0)
			ex.camera.zoom = Vector2(2, 2)
			var zs: Array = []
			for i in 5:
				var z: Node = ex.spawner.spawn_at(x + 30.0 + i * 22.0)
				z.player = null            # no chasing: stand still where placed
				z._wander_dir = 0.0
				z._wander_left = 99.0
				zs.append(z)
			await _frames(30)
			await _capture(0)
			for i in range(4, 0, -1):   # rightmost dies first = furthest into the animation
				zs[i].take_hit(99.0, zs[i].global_position.x - 10.0)
				await _frames(8)
			await _capture(1)
			await _frames(14)
			await _capture(2)   # all lying, the first ones fading
		"hud":
			var x: float = ex.HATCH_X + 300.0
			p.global_position = Vector2(x, ex.floor_y(x) - 1)
			p.items = {"wood": 3, "scrap": 2, "water": 1, "food": 1}
			ex.inventory.select(1)
			var n := 0
			for v in [10.0, 40.0, 70.0, 90.0, 100.0]:
				ex.radiation = v
				await _frames(4)
				await _capture(n)
				n += 1
			ex.inventory.toggle_backpack()
			await _frames(4)
			await _capture(n)
		"hatch":
			ex.camera.zoom = Vector2(2, 2)
			var hx: float = ex.HATCH_X
			p.global_position = Vector2(hx + 70.0, ex.floor_y(hx + 70.0) - 1)
			p.face(-1.0)
			await _frames(10)
			print("[shot] hatch open (far): ", ex.hatch.is_open)
			await _capture(0)
			p.global_position = Vector2(hx + 30.0, ex.floor_y(hx + 30.0) - 1)
			await _frames(10)
			print("[shot] hatch open (in reach): ", ex.hatch.is_open)
			await _capture(1)
			p.global_position = Vector2(hx, ex.floor_y(hx) - 1)
			await _frames(10)
			await _capture(2)
			ex.hatch.hold_open()
			p.frozen = true
			p.climb_into(Vector2(hx, ex.hatch.global_position.y - 1.0), ex.CLIMB_DEPTH, ex.CLIMB_TIME)
			await _frames(int(ex.CLIMB_TIME * 30))
			await _capture(3)

# First column right of the hatch zone with `n` flat columns and no tree or crate near.
func _flat_spot(n: int) -> int:
	var blocked := []
	for t in get_tree().get_nodes_in_group("trees"):
		blocked.append(t.position.x)
	for c in ex.crates.get_children():
		blocked.append(c.position.x)
	for col in range(ex.HATCH_COL + 20, ex.COLS - n - 2):
		var ok := true
		for k in n:
			if ex.surface_rows[col + k] != ex.surface_rows[col]:
				ok = false
				break
		for bx in blocked:
			if bx > col * 16.0 - 48.0 and bx < (col + n) * 16.0 + 48.0:
				ok = false
		if ok:
			return col
	return ex.HATCH_COL + 30
