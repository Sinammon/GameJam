# Headless test (exit 0 = all PASS):
#   Godot --headless --fixed-fps 60 --path bunker-7 --script res://tools/test_expedition.gd
# Swaps GameState for a recorder (tools/fake_game_state.gd) and drives the player
# with real key events through Input.parse_input_event.
extends SceneTree

const FAKE := preload("res://tools/fake_game_state.gd")
var fails := 0
var ex: Node2D
var p: CharacterBody2D

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

# Replace the GameState autoload with `gs` (a Node named GameState).
func set_gs(gs: Node) -> Node:
	var old: Node = root.get_node_or_null("GameState")
	if old:
		root.remove_child(old)
		old.free()
	gs.name = "GameState"
	root.add_child(gs)
	return gs

func start_expedition() -> void:
	if ex:
		ex.queue_free()
		await frames(1)
	ex = load("res://scenes/expedition.tscn").instantiate()
	root.add_child(ex)
	current_scene = ex
	p = ex.player
	await frames(20)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	await test_missing_contract()
	await test_input_and_bank()
	await test_death()
	await test_empty_bank_confirm()
	await test_round_trip()
	await test_terrain()
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)

# GameState without any contract function: must not crash, uses defaults.
func test_missing_contract() -> void:
	set_gs(Node.new())
	await start_expedition()
	check(p.is_on_floor(), "[bare GS] player lands")
	check(p.carry_limit == 12 and is_equal_approx(p.speed, 100.0), "[bare GS] defaults used")
	p.add_item("wood", 3)
	ex._on_bank_requested(p)
	check(ex.ended, "[bare GS] bank without bank_loot does not crash")

func test_input_and_bank() -> void:
	var gs = set_gs(FAKE.new())
	gs.pack = {"items": {"wood": 3, "circuits": 1, "food": 9}, "position": Vector2(300, 0)}
	await start_expedition()
	check(p.is_on_floor(), "player lands on ground")
	check(ex.hatch.player_inside, "player starts inside hatch")
	# E at spawn with an empty backpack only asks, doesn't end the expedition
	await tap(KEY_E)
	check(gs.bank_calls.is_empty() and not ex.ended, "empty E at spawn asks instead of banking")
	await frames(130)   # let the confirm window run out
	# walk right with the D key
	var x0 := p.position.x
	key(KEY_D, true)
	await frames(60)
	key(KEY_D, false)
	check(p.position.x > x0 + 80, "D key walks right (%.0f -> %.0f)" % [x0, p.position.x])
	check(not ex.hatch.player_inside, "left the hatch")
	var r0: float = ex.radiation
	await frames(60)
	check(ex.radiation > r0, "radiation grows outside (%.2f -> %.2f)" % [r0, ex.radiation])
	# jump with Space
	await tap(KEY_SPACE)
	check(p.velocity.y < 0.0 or not p.is_on_floor(), "Space jumps")
	await frames(60)
	# walk left with the Left arrow
	x0 = p.position.x
	key(KEY_LEFT, true)
	await frames(20)
	key(KEY_LEFT, false)
	check(p.position.x < x0 - 20, "Left arrow walks left")
	# Last Stand Pack: unknown key "food" dropped, partial pickup takes rarest first
	var packs := get_nodes_in_group("last_stand_pack")
	check(packs.size() == 1, "pack spawned")
	if packs.size() == 1:
		var pack = packs[0]
		check(pack.items == {"wood": 3, "circuits": 1}, "pack items cleaned: %s" % str(pack.items))
		p.add_item("concrete", 10)   # 2 slots left
		p.global_position = pack.global_position + Vector2(0, -2)
		await frames(5)
		await tap(KEY_E)
		check(p.items["circuits"] == 1 and p.items["wood"] == 1, "partial pickup: circuit first, then wood (%s)" % str(p.items))
		check(is_instance_valid(pack) and pack.items == {"wood": 2}, "rest stays in pack")
		await tap(KEY_E)
		check(is_instance_valid(pack) and pack.items == {"wood": 2} and p.total_items() == 12, "full backpack: pack untouched")
		p.items["concrete"] = 0   # make room, then E takes the rest
		await tap(KEY_E)
		await frames(2)
		check(not is_instance_valid(pack), "pack removed once empty")
	# crate: E opens it
	var c = ex.crates.get_child(0)
	p.clear_items()
	p.global_position = c.global_position + Vector2(0, -2)
	await frames(5)
	await tap(KEY_E)
	check(p.total_items() > 0 and c.is_empty(), "E opens crate (%s)" % str(p.items))
	check(not c.contents.has("circuits"), "near crate has no circuits")
	for i in 20: p.add_item("wood", 5)
	check(p.total_items() == 12, "carry limit enforced (%d)" % p.total_items())
	check(p.add_item("food", 1) == 0, "unknown item kind refused")
	# back to the hatch, E banks exactly what was carried
	p.global_position = ex.hatch.global_position + Vector2(0, -2)
	await frames(5)
	check(ex.hatch.player_inside, "hatch detects player")
	var rr: float = ex.radiation
	await frames(30)
	check(is_equal_approx(ex.radiation, rr), "radiation paused inside hatch")
	var carried: Dictionary = p.items.duplicate()
	await tap(KEY_E)
	check(gs.bank_calls.size() == 1, "bank_loot called once")
	if gs.bank_calls.size() == 1:
		check(gs.bank_calls[0] == carried, "bank_loot got %s" % str(gs.bank_calls[0]))
	check(p.total_items() == 0, "loot cleared after banking")
	check(p.frozen, "player frozen after banking")
	await tap(KEY_E)
	ex.radiation = 100.0
	p.global_position.x = 600
	await frames(150)
	check(gs.bank_calls.size() == 1 and gs.died_calls.is_empty(), "no second bank, no death after banking")

func test_death() -> void:
	var gs = set_gs(FAKE.new())
	await start_expedition()
	p.global_position = Vector2(500, ex.surface_y(500) - 2)
	p.add_item("scrap", 4)
	await frames(5)
	ex.radiation = 99.99
	await frames(3)
	check(ex.ended and p.dead, "death triggered at 100%")
	# input while dead does nothing
	var x0 := p.position.x
	key(KEY_D, true)
	await frames(20)
	key(KEY_D, false)
	check(absf(p.position.x - x0) < 1.0, "no movement while dead")
	p.add_item("wood", 2)   # picked up after death must not count
	var rad: float = ex.radiation
	ex._die()               # second death attempt
	ex._on_bank_requested(p)   # bank during fade
	await frames(60)
	check(gs.died_calls.is_empty(), "player_died waits for collapse + fade")
	check(ex.radiation == rad, "radiation frozen during fade")
	await frames(120)
	check(gs.died_calls.size() == 1, "player_died called exactly once (%d)" % gs.died_calls.size())
	check(gs.bank_calls.is_empty(), "no bank during death")
	check(is_equal_approx(ex.fade.color.a, 1.0), "screen faded to black")
	if gs.died_calls.size() == 1:
		var items: Dictionary = gs.died_calls[0][0]
		var pos: Vector2 = gs.died_calls[0][1]
		check(items == {"wood": 0, "concrete": 0, "scrap": 4, "circuits": 0}, "died with %s" % str(items))
		check(absf(pos.x - 500) < 5, "death position %s" % str(pos))

# E twice at the hatch with nothing carried = go home empty-handed.
func test_empty_bank_confirm() -> void:
	var gs = set_gs(FAKE.new())
	await start_expedition()
	await tap(KEY_E)
	await frames(30)
	await tap(KEY_E)
	check(gs.bank_calls.size() == 1 and gs.bank_calls[0]["wood"] == 0, "second E within 2 s banks empty-handed")

# Walk hatch -> farthest crate -> hatch with real input, jumping when blocked.
func walk_to(target_x: float) -> int:
	var right := target_x > p.position.x
	var k := KEY_D if right else KEY_A
	key(k, true)
	var n := 0
	while (p.position.x < target_x) == right and n < 3000:
		if p.is_on_wall() and p.is_on_floor():
			await tap(KEY_W)
			n += 4
		else:
			await frames(1)
			n += 1
	key(k, false)
	return n

func test_round_trip() -> void:
	var gs = set_gs(FAKE.new())
	await start_expedition()
	var far_x: float = ex.CRATE_XS[-1]
	var t_out := await walk_to(far_x)
	var rad_out: float = ex.radiation
	var t_back := await walk_to(ex.HATCH_X)
	await frames(5)
	print("  round trip to x=%d: %.1fs out, %.1fs back, radiation %.1f%% (out %.1f%%)" % [far_x, t_out / 60.0, t_back / 60.0, ex.radiation, rad_out])
	check(not ex.ended and ex.radiation < 95.0, "farthest crate round trip survivable on Normal (%.1f%%)" % ex.radiation)
	check(ex.radiation > 70.0, "farthest crate round trip is tight (%.1f%%)" % ex.radiation)
	# Hard (x1.5) should not allow the full trip without upgrades
	check(ex.radiation * 1.5 > 100.0, "Hard makes the farthest crate a gamble")

func test_terrain() -> void:
	var maxstep := 0
	for i in range(1, ex.COLS):
		maxstep = maxi(maxstep, absi(ex.surface_rows[i] - ex.surface_rows[i - 1]))
	check(maxstep <= 1, "max terrain step %d" % maxstep)
	p.global_position = Vector2(2800, ex.surface_y(2800) - 2)
	await frames(30)
	check(p.is_on_floor(), "far right has ground")
	# art present in the repo: survivor sprite and art tileset are used
	check(p.sprite != null and not p.body_rect.visible, "survivor sprite replaces placeholder")
	check(ex.use_art_tiles, "art tileset used")
