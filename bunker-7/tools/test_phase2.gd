# Headless test for phase 2 (trees, mining, zombies). Exit 0 = all PASS:
#   Godot --headless --fixed-fps 60 --path bunker-7 --script res://tools/test_phase2.gd
# Uses the GameState recorder (tools/fake_game_state.gd). Zombies are switched
# off in the spawner and placed by hand, except in the spawner tests.
extends SceneTree

const FAKE := preload("res://tools/fake_game_state.gd")
const TreeScript := preload("res://actors/tree.gd")
var fails := 0
var ex: Node2D
var p: CharacterBody2D
var gs: Node

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok: fails += 1

func frames(n: int) -> void:
	for i in n: await physics_frame

func key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func tap(code: Key) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(2)

func click() -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		Input.parse_input_event(e)
		await frames(2)

func fresh_gs() -> Node:
	var old: Node = root.get_node_or_null("GameState")
	if old:
		root.remove_child(old)
		old.free()
	gs = FAKE.new()
	gs.name = "GameState"
	root.add_child(gs)
	return gs

func start(zombies := false) -> void:
	if ex:
		ex.queue_free()
		await frames(2)
	ex = load("res://scenes/expedition.tscn").instantiate()
	ex.zombies_enabled = zombies
	root.add_child(ex)
	current_scene = ex
	p = ex.player
	await frames(20)

# Puts the player standing at x (on the current ground), facing dir.
func stand(x: float, dir := 1.0) -> void:
	p.global_position = Vector2(x, ex.floor_y(x) - 1.0)
	p.velocity = Vector2.ZERO
	p.face(dir)
	await frames(10)

# Swings the tool once (waits out the cooldown first).
func swing(tool_id: String) -> String:
	await frames(26)
	return ex.swing.use(tool_id)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	await test_trees()
	await test_tree_carry_limit()
	await test_mining()
	await test_dig_rules()
	await test_escape()
	await test_zombie_fight()
	await test_zombie_kills_player()
	await test_safe_zone_and_spawner()
	await test_soak()
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)

func trees_by_size(size: String) -> Array:
	return get_nodes_in_group("trees").filter(func(t: Node) -> bool: return t.size == size and not t.fallen)

func test_trees() -> void:
	fresh_gs()
	await start()
	var all := get_nodes_in_group("trees")
	check(all.size() >= 8, "trees placed (%d)" % all.size())
	var ok_place := true
	for t in all:
		var col := int(t.position.x / 16)
		if ex.area_of(col) == 2 or absi(col - ex.HATCH_COL) < ex.TREE_MIN_COL or not ex.mining.protected_cols.has(col):
			ok_place = false
	check(ok_place, "trees only in suburb/market, away from the hatch, ground under them protected")
	var sizes := {}
	for t in all: sizes[t.size] = true
	check(sizes.size() == 3, "3 tree sizes present (%s)" % str(sizes.keys()))
	var t: Node2D = trees_by_size("medium")[0]
	await stand(t.position.x - 14, 1.0)
	# one real left click with the axe selected
	check(ex.inventory.selected_tool() == "axe", "axe selected at start")
	await click()
	check(ex.swing.last_result == "tree" and t.hp < TreeScript.SIZES["medium"]["hp"], "left click with the axe chops the tree (hp %.2f)" % t.hp)
	var r: String = ex.swing.use("axe")
	check(r == "", "swing cooldown (%s)" % r)
	var hits := 1
	while not t.fallen and hits < 20:
		await swing("axe")
		hits += 1
	check(t.fallen and hits == int(TreeScript.SIZES["medium"]["hp"]), "medium tree falls after %d axe hits" % hits)
	await frames(90)
	check(p.items["wood"] == 2 and t.logs_dropped == 2, "logs picked up: %d wood (dropped %d)" % [p.items["wood"], t.logs_dropped])
	for i in 3:
		await swing("axe")
	await frames(60)
	check(p.items["wood"] == 2 and t.logs_dropped == 2, "stump gives no more wood")
	check(t._stump.visible, "stump left behind")
	# pickaxe on a tree (aimed at it): little damage
	var t2: Node2D = trees_by_size("large")[0]
	await stand(t2.position.x - 14, 1.0)
	ex.swing.aim_override = t2.position + Vector2(0, -20)
	var res := await swing("pickaxe")
	ex.swing.aim_override = null
	check(res == "tree" and t2.hp > TreeScript.SIZES["large"]["hp"] - 0.5, "pickaxe barely hurts a tree (hp %.2f)" % t2.hp)

func test_tree_carry_limit() -> void:
	fresh_gs()
	await start()
	var t: Node2D = trees_by_size("medium")[0]
	await stand(t.position.x - 14, 1.0)
	p.add_item("scrap", 11)   # 1 slot left of 12
	while not t.fallen:
		await swing("axe")
	await frames(120)
	check(p.items["wood"] == 1 and p.total_items() == 12, "carry limit: only 1 of 2 logs taken (%s)" % str(p.items))
	check(get_nodes_in_group("pickups").size() == 1, "the other log stays on the ground")
	p.items["scrap"] = 0
	await frames(90)
	check(p.items["wood"] == 2 and get_nodes_in_group("pickups").is_empty(), "log picked up once there is room")
	# loot multiplier: x2 doubles the logs
	fresh_gs().loot_mult = 2.0
	await start()
	t = trees_by_size("small")[0]
	await stand(t.position.x - 14, 1.0)
	while not t.fallen:
		await swing("axe")
	await frames(90)
	check(t.logs_dropped == 2 and p.items["wood"] == 2, "loot multiplier x2: small tree gives 2 logs (%d)" % t.logs_dropped)

# A flat, unprotected column (and its neighbours) at least `from` columns out.
func flat_col(from: int) -> int:
	var m = ex.mining
	for c in range(ex.HATCH_COL + from, ex.COLS - 10):
		var ok := true
		for d in range(-4, 5):
			if m.protected_cols.has(c + d) or ex.surface_rows[c + d] != ex.BASE_ROW:
				ok = false
		if ok:
			return c
	return -1

func test_mining() -> void:
	fresh_gs()
	await start()
	var m = ex.mining
	var c := flat_col(20)
	check(c > 0, "found a flat column to dig (%d)" % c)
	var top := Vector2i(c + 1, ex.BASE_ROW)
	m.place(top, "surface", Vector2i(1, 0))   # plain surface block: 3 hits
	await stand(c * 16 + 8.0, 1.0)
	check(m.pick_target(p.global_position, 1.0, null)[0] == top, "pickaxe targets the block in front")
	await swing("pickaxe")
	check(ex.swing.last_result == "block" and m.crack_stage(top) == 1, "1st hit: crack stage 1 (%d)" % m.crack_stage(top))
	await swing("pickaxe")
	check(m.crack_stage(top) == 2, "2nd hit: crack stage 2")
	await swing("pickaxe")
	await frames(2)
	check(ex.ground.get_cell_source_id(top) == -1 and m.floor_rows[top.x] == ex.BASE_ROW + 1, "3rd hit breaks the block")
	check(m.crack_stage(top) == -1 and m.kind_at(top) == "", "block forgotten after breaking")
	# ore drops: a concrete block under the player's front column
	var ore := Vector2i(c + 1, ex.BASE_ROW + 1)
	m.place(ore, "concrete", Vector2i(0, 0))
	var before: int = p.items["concrete"]
	var n := 0
	while ex.ground.get_cell_source_id(ore) != -1 and n < 10:
		m.hit(ore)
		n += 1
	check(n == 5, "concrete takes 5 hits (%d)" % n)
	await stand(ore.x * 16 + 8.0)
	await frames(60)
	check(p.items["concrete"] == before + 1, "concrete block drops 1 concrete (%d)" % p.items["concrete"])
	m.rng.seed = 1
	var kinds := {}
	for i in 200:
		kinds[m.kind_for(3, 0.9, 2)] = true
	check(kinds.has("circuits") and kinds.has("scrap_ore"), "deep far blocks hold circuits and scrap (%s)" % str(kinds.keys()))
	var near_circuits := false
	for i in 300:
		if m.kind_for(3, 0.3, 0) == "circuits" or m.kind_for(1, 0.9, 2) == "circuits":
			near_circuits = true
	check(not near_circuits, "no circuits near the hatch or right under the surface")
	var ore_cells := 0
	var circuit_ok := true
	for cell in m.kinds:
		var k: String = m.kinds[cell]
		if k in m.ORE_ATLAS and k != "bedrock":
			ore_cells += 1
			if k == "circuits" and ex.distance_frac(cell.x * 16) < 0.6:
				circuit_ok = false
	check(ore_cells > 50 and circuit_ok, "terrain has ores underground (%d), circuits only far out" % ore_cells)
	# placeholder tiles when the art is missing
	var ph: Image = m._placeholder_ore(m._placeholder_outside().get_region(Rect2i(0, 0, 16, 16)))
	check(ph.get_size() == Vector2i(64, 32) and ph.get_pixel(40, 8) != ph.get_pixel(8, 8), "placeholder ore atlas drawn (64x32)")
	check(ex.ground.tile_set.get_source_count() == 2, "ground tileset: outside + ore sources")
	# dig speed bonus shortens digging
	fresh_gs().dig_bonus = 0.5
	await start()
	m = ex.mining
	c = flat_col(20)
	var cell := Vector2i(c, ex.BASE_ROW)
	m.place(cell, "dirt", Vector2i(0, 0))
	n = 0
	while ex.ground.get_cell_source_id(cell) != -1 and n < 10:
		m.hit(cell)
		n += 1
	check(n == 2, "dig speed +50%%: dirt in 2 hits instead of 3 (%d)" % n)

func test_dig_rules() -> void:
	fresh_gs()
	await start()
	var m = ex.mining
	var c := flat_col(30)
	check(m.why_not(Vector2i(c, ex.BOTTOM_ROW - 1)) == "bedrock", "bedrock row can't be dug")
	check(m.kind_at(Vector2i(c, ex.BOTTOM_ROW - 1)) == "bedrock", "bottom row is bedrock")
	check(m.why_not(Vector2i(ex.HATCH_COL, ex.surface_rows[ex.HATCH_COL])) == "protected", "ground under the hatch can't be dug")
	check(m.why_not(Vector2i(c, ex.BASE_ROW + 1)) == "buried", "only the top block of a column can be dug")
	# a single shaft: 2 deep is fine, the 3rd block would trap you
	m.hit(Vector2i(c, ex.BASE_ROW), 99.0)
	m.hit(Vector2i(c, ex.BASE_ROW + 1), 99.0)
	check(m.dug_depth(c) == 2, "1-wide shaft 2 deep")
	check(m.why_not(Vector2i(c, ex.BASE_ROW + 2)) == "unsafe", "3rd block of a 1-wide shaft refused (escape rule)")
	# a staircase goes down to the depth limit
	for d in 4:
		var cell := Vector2i(c + 1, ex.BASE_ROW + d)
		check(m.hit(cell, 99.0), "staircase: column %d dug to depth %d" % [c + 1, d + 1])
	check(m.dug_depth(c + 1) == 4, "staircase reaches depth 4")
	check(m.why_not(Vector2i(c + 1, ex.BASE_ROW + 4)) == "too deep", "5th block refused: max depth 4")
	# deepening the step would cut off the deep column
	check(m.why_not(Vector2i(c, ex.BASE_ROW + 2)) == "unsafe", "deepening the step would cut off both columns: refused")
	var floors: Array = m.floor_rows.duplicate()
	check(m.escapable(floors), "current world escapable")
	floors[c] = ex.BASE_ROW + 4
	floors[c - 1] = ex.BASE_ROW + 1
	check(not m.escapable(floors), "escape check catches a 3-block wall")
	# standing at the bottom, the swing explains why it can't dig deeper
	var msgs := []
	p.message.connect(func(t: String) -> void: msgs.append(t))
	await stand((c + 1) * 16 + 8.0, 1.0)
	await frames(30)
	var res := await swing("pickaxe")
	check(res == "" and msgs.has("Too deep to dig here."), "swing at the depth limit: no dig, message (%s)" % str(msgs))

# The player gets out of a mined hole with real keys (walk + jump).
func climb_out(dir: float, seconds := 4.0) -> bool:
	var k := KEY_D if dir > 0.0 else KEY_A
	key(k, true)
	var goal_y: float = ex.BASE_ROW * 16 + 1
	var ok := false
	for i in int(seconds * 60):
		if p.is_on_floor() and (p.is_on_wall() or i % 20 == 0):
			key(KEY_W, true)
			await frames(3)
			key(KEY_W, false)
		await frames(1)
		if p.global_position.y <= goal_y and p.is_on_floor():
			ok = true
			break
	key(k, false)
	await frames(5)
	return ok

func test_escape() -> void:
	fresh_gs()
	await start()
	var m = ex.mining
	var c := flat_col(40)
	# 2-deep single shaft
	m.hit(Vector2i(c, ex.BASE_ROW), 99.0)
	m.hit(Vector2i(c, ex.BASE_ROW + 1), 99.0)
	await frames(2)
	await stand(c * 16 + 8.0)
	await frames(30)
	check(p.global_position.y > ex.BASE_ROW * 16 + 20, "player fell into the 2-deep shaft (y %.0f)" % p.global_position.y)
	check(ex.camera.limit_bottom > 270, "camera follows into the hole (limit %d)" % ex.camera.limit_bottom)
	check(await climb_out(1.0), "jumps out of a 2-deep shaft")
	# staircase to depth 4: dig c+3 to 2 and c+4 to 4, then climb out both ways
	var s := flat_col(60)
	for d in 2: m.hit(Vector2i(s, ex.BASE_ROW + d), 99.0)
	for d in 4: m.hit(Vector2i(s + 1, ex.BASE_ROW + d), 99.0)
	for d in 2: m.hit(Vector2i(s + 2, ex.BASE_ROW + d), 99.0)
	await frames(2)   # tile collision updates at the end of the frame
	await stand((s + 1) * 16 + 8.0)
	await frames(30)
	check(absf(p.global_position.y - (ex.BASE_ROW + 4) * 16) < 2.0, "player at the bottom of a 4-deep hole (y %.0f)" % p.global_position.y)
	check(await climb_out(-1.0), "climbs out of a 4-deep hole to the left")
	await stand((s + 1) * 16 + 8.0)
	await frames(30)
	check(await climb_out(1.0), "climbs out of a 4-deep hole to the right")
	# random digging never traps: dig random allowed blocks, then check the rule holds
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var dug := 0
	for i in 400:
		var col := rng.randi_range(c - 30, c + 30)
		if m.hit(Vector2i(col, m.floor_rows[col]), 99.0):
			dug += 1
	check(dug > 30 and m.escapable(m.floor_rows), "400 random digs (%d dug) leave every column escapable" % dug)
	var max_step := 0
	for col in range(c - 31, c + 31):
		max_step = maxi(max_step, m.dug_depth(col))
	check(max_step <= m.MAX_DIG_DEPTH, "no column deeper than %d (%d)" % [m.MAX_DIG_DEPTH, max_step])

# Waits out the cooldown and (up to 2 s) until the zombie, done flinching, is
# back in swing range, then swings.
func swing_at(z: Node, tool_id: String) -> String:
	await frames(26)
	for i in 120:
		if not is_instance_valid(z) or (z.state != z.State.HURT and absf(z.global_position.x - p.global_position.x) < 20.0):
			break
		await frames(1)
	return ex.swing.use(tool_id)

func spawn_zombie(x: float) -> Node:
	var z: Node = ex.spawner.spawn_at(x)
	await frames(5)
	return z

func test_zombie_fight() -> void:
	fresh_gs()
	await start()
	var x: float = ex.HATCH_X + 500
	await stand(x, 1.0)
	var z: Node = await spawn_zombie(x + 80)
	check(z != null and z.is_in_group("zombies"), "zombie spawned")
	await frames(20)
	check(z.state == z.State.CHASE, "zombie sees the player 5 tiles away and chases (state %d)" % z.state)
	var x0: float = z.global_position.x
	await frames(30)
	var speed: float = absf(z.global_position.x - x0) * 2.0
	check(speed > 40.0 and speed < p.speed, "chase speed %.0f px/s (< player %.0f)" % [speed, p.speed])
	var hits := []
	p.hurt.connect(func(a: int, s: String) -> void: hits.append([a, s]))
	for i in 120:
		await frames(1)
		if not hits.is_empty():
			break
	check(hits.size() == 1 and hits[0] == [1, "zombie"], "zombie hits for 1 half-heart (%s)" % str(hits))
	check(p.health.hp == 9, "player hp 9 after a zombie hit (%d)" % p.health.hp)
	# kill it with the pickaxe: 2 hits
	ex.inventory.select(1)
	p.health.invuln_left = 99.0   # keep the test about our hits
	await stand(z.global_position.x - 12, 1.0)
	var r1 := await swing_at(z, "pickaxe")
	check(r1 == "zombie" and not z.is_dead(), "pickaxe hit 1 lands (%s, hp %.1f)" % [r1, z.hp])
	await swing_at(z, "pickaxe")
	check(z.is_dead(), "pickaxe kills a zombie in 2 hits")
	await frames(70)
	check(not is_instance_valid(z), "dead zombie fades out and is removed")
	# the axe needs 4
	var z2: Node = await spawn_zombie(p.global_position.x + 14)
	var n := 0
	while is_instance_valid(z2) and not z2.is_dead() and n < 10:
		await swing_at(z2, "axe")
		n += 1
	check(n == 4, "axe kills a zombie in 4 hits (%d)" % n)
	# drops: 30%, food or scrap
	var drops := {}
	var dead := 0
	for i in 40:
		var zz: Node = ex.spawner.spawn_at(x + 200)
		zz.take_hit(99.0, x)
		dead += 1
	await frames(5)
	for pk in get_nodes_in_group("pickups"):
		drops[pk.kind] = drops.get(pk.kind, 0) + 1
	var total := 0
	for k in drops: total += drops[k]
	check(drops.keys().all(func(k: String) -> bool: return k in ["raw_meat", "scrap"]) and total > 2 and total < 25,
		"zombie drops: %d of %d (%s)" % [total, dead, str(drops)])

func test_zombie_kills_player() -> void:
	fresh_gs()
	await start()
	var x: float = ex.HATCH_X - 600
	await stand(x, -1.0)
	p.health.hp = 1
	var shaken := false
	var cam_off: Vector2 = ex.camera.offset
	var z: Node = await spawn_zombie(x - 40)
	for i in 240:
		await frames(1)
		if ex.camera.offset != cam_off:
			shaken = true
		if p.dead:
			break
	check(p.dead and p.death_reason == "zombie", "a zombie kills the player: reason %s" % p.death_reason)
	await frames(300)
	check(gs.died_calls.size() == 1, "player_died called once (%d)" % gs.died_calls.size())
	check(ex.hud.death_box.visible and "zombie" in ex.hud.death_box.get_node("Label").text, "HUD says a zombie did it")
	check(is_instance_valid(z) and z.state != z.State.ATTACK, "zombie stops attacking a dead player")
	# hit feedback: screen shake on a hit
	fresh_gs()
	await start()
	await stand(ex.HATCH_X + 400)
	p.take_damage(1, "zombie", p.global_position + Vector2(10, 0))
	await frames(2)
	check(ex.camera.offset != Vector2.ZERO, "screen shakes when hit")
	await frames(30)
	check(ex.camera.offset == Vector2.ZERO, "shake settles")

func test_safe_zone_and_spawner() -> void:
	fresh_gs()
	await start()
	check(ex.spawner.spawn_at(ex.HATCH_X + 60) == null, "no zombie can be placed inside the safe zone")
	# a zombie chasing the player into the hatch stops at the safe-zone edge
	await stand(ex.HATCH_X + 120, 1.0)
	var z: Node = await spawn_zombie(ex.HATCH_X + 190)
	await frames(30)
	p.global_position = ex.hatch.global_position + Vector2(0, -2)
	var hp: int = p.health.hp
	var closest := 9999.0
	for i in 360:
		await frames(1)
		closest = minf(closest, absf(z.global_position.x - ex.HATCH_X))
	check(closest >= ex.spawner.SAFE_RADIUS - 1.0, "zombie never enters the 6-tile safe zone (closest %.0f px)" % closest)
	check(p.health.hp == hp and ex.hatch.player_inside, "player safe inside the hatch")
	# spawner slots: never in the safe zone, more far out
	fresh_gs()
	await start(true)
	var seen := []
	ex.spawner.first_seen.connect(func() -> void: seen.append(1))
	var slots: Array = ex.spawner.slots
	var near_ok: bool = slots.all(func(s: Dictionary) -> bool: return absf(s["x"] - ex.HATCH_X) >= ex.spawner.SPAWN_MIN_DIST)
	check(near_ok and ex.spawner.SPAWN_MIN_DIST >= 96.0, "no spawn slot within 6 tiles of the hatch (%d slots)" % slots.size())
	var per_area := [0, 0, 0]
	for s in slots: per_area[ex.area_of(int(s["x"] / 16))] += 1
	check(per_area[0] < per_area[1] and per_area[1] < per_area[2], "suburb < market < depot (%s)" % str(per_area))
	await frames(60)
	var offscreen: bool = ex.spawner.alive().all(func(zz: Node) -> bool: return absf(zz.global_position.x - p.global_position.x) > 240.0)
	check(offscreen and seen.is_empty(), "zombies only spawn off-screen (%d alive)" % ex.spawner.alive().size())
	# go to the depot: zombies appear, capped
	await stand(ex.HATCH_X + 2000)
	var most := 0
	for i in 12:
		p.global_position.x += 15.0 * (1 if i % 2 == 0 else -1)
		await frames(30)
		most = maxi(most, ex.spawner.alive_near(p.global_position.x))
	check(most > 0 and most <= ex.spawner.CAP, "zombies spawn in the depot, at most %d near (max %d)" % [ex.spawner.CAP, most])
	var dist_ok: bool = ex.spawner.alive().all(func(zz: Node) -> bool: return absf(zz.global_position.x - ex.HATCH_X) >= ex.spawner.SAFE_RADIUS)
	check(dist_ok, "no spawned zombie in the safe zone")
	ex.spawner.spawn_at(p.global_position.x + 120)
	await frames(10)
	ex.spawner.spawn_at(p.global_position.x - 120)
	await frames(10)
	check(seen.size() == 1, "first-zombie hint fired once (%d)" % seen.size())
	# far away: despawned
	await stand(ex.HATCH_X - 2000)
	await frames(60)
	var far: Array = ex.spawner.alive().filter(func(zz: Node) -> bool: return absf(zz.global_position.x - p.global_position.x) > ex.spawner.DESPAWN_DIST)
	check(far.is_empty(), "far zombies despawned")
	# more days = more zombies
	var day1: int = slots.size()
	fresh_gs().day = 5
	await start(true)
	check(ex.spawner.slots.size() > day1, "day 5 has more zombie slots (%d > %d)" % [ex.spawner.slots.size(), day1])

# Random keys and swings with zombies on, in all zones: nothing breaks, the
# player stays inside the world and can always walk out of what was dug.
func test_soak() -> void:
	fresh_gs().max_hp = 40
	await start(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var keys := [KEY_A, KEY_D, KEY_W]
	var swings := 0
	for spot in [ex.HATCH_X + 300, ex.HATCH_X - 900, ex.HATCH_X + 1500, ex.HATCH_X - 2100]:
		await stand(spot)
		for i in 300:
			if i % 15 == 0:
				for k in keys: key(k, false)
				key(keys[rng.randi() % keys.size()], true)
			if i % 7 == 0:
				ex.inventory.select(rng.randi() % 2)
				if ex.swing.use(ex.inventory.selected_tool()) != "":
					swings += 1
			p.health.hp = p.health.max_hp   # keep it about the systems, not survival
			await frames(1)
		for k in keys: key(k, false)
	await frames(5)
	var inside: bool = p.global_position.y <= (ex.BOTTOM_ROW - 1) * 16 and p.global_position.x > 0 and p.global_position.x < ex.WORLD_W
	check(inside and not p.dead, "soak: player inside the world after random play (%s)" % str(p.global_position))
	check(swings > 5 and ex.mining.escapable(ex.mining.floor_rows), "soak: %d swings landed, world still escapable" % swings)
	check(ex.spawner.alive_near(p.global_position.x) <= ex.spawner.CAP, "soak: zombie cap held")
