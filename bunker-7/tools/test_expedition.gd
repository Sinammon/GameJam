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

func mouse(button: MouseButton) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)
		await frames(2)

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
	await test_round_trip_left()
	await test_terrain()
	await test_supplies()
	await test_health_drain()
	await test_damage()
	await test_hotbar()
	await test_both_ways()
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)

# GameState without any contract function: must not crash, uses defaults.
func test_missing_contract() -> void:
	set_gs(Node.new())
	await start_expedition()
	check(p.is_on_floor(), "[bare GS] player lands")
	check(p.carry_limit == 12 and is_equal_approx(p.speed, 100.0), "[bare GS] defaults used")
	check(p.health.max_hp == 10 and p.health.hp == 10, "[bare GS] 10 half-hearts by default")
	check(ex.inventory.tier == 1 and ex.inventory.slots_total() == 12, "[bare GS] backpack tier 1 by default")
	p.add_item("wood", 3)
	ex._on_bank_requested(p)
	check(ex.ended, "[bare GS] bank without bank_loot does not crash")

func test_input_and_bank() -> void:
	var gs = set_gs(FAKE.new())
	gs.pack = {"items": {"wood": 3, "circuits": 1, "junk": 9}, "position": Vector2(2708, 0)}
	await start_expedition()
	check(p.is_on_floor(), "player lands on ground")
	check(ex.hatch.player_inside, "player starts inside hatch")
	check(absf(p.position.x - ex.WORLD_W / 2.0) < 32.0, "hatch is in the middle of the world (x=%.0f of %d)" % [p.position.x, ex.WORLD_W])
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
	# Last Stand Pack: unknown key "junk" dropped, partial pickup takes rarest first
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
	check(p.add_item("junk", 1) == 0, "unknown item kind refused")
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
	p.global_position.x = ex.HATCH_X + 600
	await frames(150)
	check(gs.bank_calls.size() == 1 and gs.died_calls.is_empty(), "no second bank, no death after banking")

func test_death() -> void:
	var gs = set_gs(FAKE.new())
	await start_expedition()
	var dx: float = ex.HATCH_X + 500
	p.global_position = Vector2(dx, ex.surface_y(dx) - 2)
	p.add_item("scrap", 4)
	await frames(5)
	ex.radiation = 99.99
	await frames(3)
	check(not ex.ended and not p.dead, "100% radiation does not kill at once")
	check(p.health.hp == 9, "first half-heart drained on reaching 100%% (hp %d)" % p.health.hp)
	p.health.hp = 1
	await frames(130)
	check(ex.ended and p.dead, "death when radiation drains the last half-heart")
	check(p.death_reason == "radiation", "death reason is radiation (%s)" % p.death_reason)
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
	await frames(60)
	check(ex.hud.death_box.visible and "Radiation" in ex.hud.death_box.get_node("Label").text, "HUD says why you died")
	await frames(140)
	check(gs.died_calls.size() == 1, "player_died called exactly once (%d)" % gs.died_calls.size())
	check(gs.bank_calls.is_empty(), "no bank during death")
	check(is_equal_approx(ex.fade.color.a, 1.0), "screen faded to black")
	if gs.died_calls.size() == 1:
		var items: Dictionary = gs.died_calls[0][0]
		var pos: Vector2 = gs.died_calls[0][1]
		check(items == {"wood": 0, "concrete": 0, "scrap": 4, "circuits": 0, "water": 0, "food": 0}, "died with %s" % str(items))
		check(absf(pos.x - dx) < 5, "death position %s" % str(pos))

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

# Crates also hold water/food; they count toward the carry limit and are banked.
func test_supplies() -> void:
	var gs = set_gs(FAKE.new())
	await start_expedition()
	var kinds := {}
	for i in 300:
		var c = load("res://actors/crate.gd").new()
		c.setup(randf(), 1.0)
		for k in c.contents: kinds[k] = true
		c.free()
	check(kinds.has("water") and kinds.has("food") and kinds.keys().all(func(k): return k in GSBridge.ITEM_KINDS), "crates roll supplies: %s" % str(kinds.keys()))
	var cr = ex.crates.get_child(1)
	cr.contents = {"water": 2, "food": 1, "wood": 2}
	p.add_item("scrap", 9)   # 3 slots left
	p.global_position = cr.global_position + Vector2(0, -2)
	await frames(5)
	await tap(KEY_E)
	check(p.items["water"] == 2 and p.items["food"] == 1 and p.total_items() == 12 and cr.contents == {"wood": 2}, "supplies before wood, count toward limit (%s)" % str(p.items))
	p.global_position = ex.hatch.global_position + Vector2(0, -2)
	await frames(5)
	await tap(KEY_E)
	check(gs.bank_calls.size() == 1 and gs.bank_calls[0]["water"] == 2 and gs.bank_calls[0]["food"] == 1, "water/food banked")

func test_terrain() -> void:
	var maxstep := 0
	for i in range(1, ex.COLS):
		maxstep = maxi(maxstep, absi(ex.surface_rows[i] - ex.surface_rows[i - 1]))
	check(maxstep <= 1, "max terrain step %d" % maxstep)
	for x in [40.0, 4760.0]:
		p.global_position = Vector2(x, ex.surface_y(x) - 2)
		await frames(30)
		check(p.is_on_floor(), "ground at x=%d" % x)
	# art present in the repo: survivor sprite and art tileset are used
	check(p.sprite != null and not p.body_rect.visible, "survivor sprite replaces placeholder")
	check(ex.use_art_tiles, "art tileset used")

# Walk hatch -> farthest LEFT crate -> hatch: the left side is as far and as deadly.
func test_round_trip_left() -> void:
	set_gs(FAKE.new())
	await start_expedition()
	var far_x: float = ex.CRATE_XS[-2]
	check(absf(absf(far_x - ex.HATCH_X) - absf(ex.CRATE_XS[-1] - ex.HATCH_X)) < 1.0, "far crates equally far on both sides")
	var t_out := await walk_to(far_x)
	check(ex.hud.home_arrow_visible, "go-home arrow shown far from the hatch")
	var t_back := await walk_to(ex.HATCH_X)
	await frames(5)
	print("  left round trip to x=%d: %.1fs out, %.1fs back, radiation %.1f%%" % [far_x, t_out / 60.0, t_back / 60.0, ex.radiation])
	check(not ex.ended and ex.radiation > 70.0 and ex.radiation < 95.0, "left round trip survivable but tight (%.1f%%)" % ex.radiation)
	check(not ex.hud.home_arrow_visible, "no go-home arrow at the hatch")

# Above 100%: 1 half-heart per 2 s, paused in the hatch.
func test_health_drain() -> void:
	set_gs(FAKE.new())
	await start_expedition()
	var x: float = ex.HATCH_X + 400
	p.global_position = Vector2(x, ex.surface_y(x) - 2)
	await frames(5)
	ex.radiation = 100.0
	await frames(2)
	check(p.health.hp == 9, "drain starts at 100%% (hp %d)" % p.health.hp)
	await frames(300)   # 5 s: ticks at 2 s and 4 s
	check(p.health.hp == 7, "1 half-heart per 2 s (hp %d after 5 s)" % p.health.hp)
	check(ex.radiation == 100.0, "radiation capped at 100")
	p.global_position = ex.hatch.global_position + Vector2(0, -2)
	await frames(200)
	check(p.health.hp == 7 and not ex.ended, "no drain inside the hatch (hp %d)" % p.health.hp)

# take_damage: i-frames, knockback away from the hit, radiation ignores i-frames.
func test_damage() -> void:
	set_gs(FAKE.new())
	await start_expedition()
	var x: float = ex.HATCH_X + 300
	p.global_position = Vector2(x, ex.surface_y(x) - 2)
	await frames(10)
	check(p.take_damage(2, "zombie", p.global_position + Vector2(20, 0)), "zombie hit lands")
	check(p.velocity.x < 0.0, "knockback pushes away from the hit (vx %.0f)" % p.velocity.x)
	check(not p.take_damage(2, "zombie"), "i-frames block a second hit")
	check(p.take_damage(1, "radiation"), "radiation ignores i-frames")
	check(p.health.hp == 7, "hp after hits %d" % p.health.hp)
	await frames(60)
	p.take_damage(10, "zombie")
	await frames(3)
	check(p.dead and ex.ended and p.death_reason == "zombie", "zombie kill: reason zombie (%s)" % p.death_reason)

# Hotbar: keys 1-5 and the wheel select, Tab toggles the backpack grid.
func test_hotbar() -> void:
	set_gs(FAKE.new())
	await start_expedition()
	var inv = ex.inventory
	check(inv.TOOLS == ["axe", "pickaxe", "flashlight", "canteen", "medkit"], "hotbar tools")
	await tap(KEY_3)
	check(inv.selected == 2 and inv.selected_tool() == "flashlight", "key 3 selects slot 3")
	await mouse(MOUSE_BUTTON_WHEEL_DOWN)
	check(inv.selected == 3, "wheel down selects next (%d)" % inv.selected)
	await tap(KEY_5)
	await mouse(MOUSE_BUTTON_WHEEL_DOWN)
	check(inv.selected == 0, "wheel wraps around (%d)" % inv.selected)
	await mouse(MOUSE_BUTTON_WHEEL_UP)
	check(inv.selected == 4, "wheel up wraps back (%d)" % inv.selected)
	var used := []
	inv.tool_used.connect(func(t: String) -> void: used.append(t))
	await mouse(MOUSE_BUTTON_LEFT)
	check(used == ["medkit"], "left click uses the selected tool (%s)" % str(used))
	check(not inv.backpack_open, "backpack closed at start")
	await tap(KEY_TAB)
	check(inv.backpack_open, "Tab opens the backpack")
	p.add_item("wood", 3)
	p.add_item("circuits", 1)
	check(inv.stacks() == [["wood", 3], ["circuits", 1]] and inv.used() == 4, "materials as stacks %s" % str(inv.stacks()))
	check(inv.slots_unlocked() == 12 and inv.slots_total() == 12, "12 unlocked slots = carry limit")
	await frames(2)
	await tap(KEY_TAB)
	check(not inv.backpack_open, "Tab closes the backpack")
	# Esc = `pause` action: opens the pause menu (no debug quit any more)
	check(ex.pause_menu != null, "pause menu added to the expedition")
	if ex.pause_menu:
		await tap(KEY_ESCAPE)
		check(ex.pause_menu.is_open and paused, "Esc opens the pause menu and pauses")
		await tap(KEY_ESCAPE)
		check(not ex.pause_menu.is_open and not paused, "Esc again resumes")

# Radiation grows with distance from the hatch on both sides, the same way.
func test_both_ways() -> void:
	var gs = set_gs(FAKE.new())
	gs.carry = 16
	gs.tier = 2
	gs.max_hp = 12
	await start_expedition()
	check(p.health.max_hp == 12 and ex.inventory.slots_total() == 16, "max_health / backpack_tier read from GameState")
	var near: float = ex.distance_frac(ex.HATCH_X - 200)
	var far_l: float = ex.distance_frac(ex.HATCH_X - 2000)
	var far_r: float = ex.distance_frac(ex.HATCH_X + 2000)
	check(is_equal_approx(far_l, far_r) and far_l > near, "distance from the hatch is symmetric")
	check(ex.RadiationScript.rate_at(far_l) > ex.RadiationScript.rate_at(near) * 2.0, "rate grows with distance")
	for side in [-1.0, 1.0]:
		ex.radiation = 0.0
		var x: float = ex.HATCH_X + side * 2000
		p.global_position = Vector2(x, ex.surface_y(x) - 2)
		await frames(60)
		var far_gain: float = ex.radiation
		ex.radiation = 0.0
		x = ex.HATCH_X + side * 200
		p.global_position = Vector2(x, ex.surface_y(x) - 2)
		await frames(60)
		check(far_gain > ex.radiation * 2.0, "side %d: far %.2f vs near %.2f per s" % [side, far_gain, ex.radiation])
	check(ex.area_of(ex.HATCH_COL - 20) == 0 and ex.area_of(ex.HATCH_COL + 20) == 0 and ex.area_of(5) == 2 and ex.area_of(295) == 2, "zones mirrored: suburb in the middle, depot at both edges")
	# warnings at 60 / 85 / 100
	var msgs := []
	ex.rad.warning.connect(func(l: int) -> void: msgs.append(l))
	ex.radiation = 59.9
	await frames(30)
	ex.radiation = 84.9
	await frames(30)
	check(msgs == [0, 1], "warnings at 60%% and 85%% (%s)" % str(msgs))
	check(ex.rad.level() == 3 and ex.hud.vignette.modulate.a > 0.0, "geiger state 3 and vignette pulsing")
