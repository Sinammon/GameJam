# V3 survival / locations / days / book test with the REAL GameState (exit 0 = all PASS):
#   Godot --headless --fixed-fps 60 --path bunker-7 --script res://tools/test_survival.gd
# Covers: dirty -> clean water (filter, stove), cooking, eating in the bunker, the night upkeep on
# the meters, hunger/thirst drain and damage outside, eat/drink keys, sickness from dirty water,
# location unlock days, entering and leaving every location (bank loot), death in the crater
# (pack remembers the place), carry limit, the Radio Beacon needing the radio part, daily goals,
# forced horde night, the Crafts / Book listing every item, and API playthroughs: Normal reaches
# the rescue ending, Hard can be survived with care and lost without.
extends SceneTree

const BUNKER := "res://scenes/bunker.tscn"
const EXPEDITION := "res://scenes/expedition.tscn"
var fails := 0
var gs: Node

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func tap(code: Key) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(2)

func scene_path() -> String:
	return current_scene.scene_file_path if current_scene else ""

func wait_scene(path: String, secs := 8.0) -> bool:
	for i in int(secs * 60):
		if scene_path() == path and current_scene.is_node_ready():
			return true
		await frames(1)
	return false

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	SettingsStore.path = "user://test_survival_settings.cfg"
	SettingsStore.reset(true)
	SettingsStore.hint_once("tutorial_seen")
	gs = root.get_node("GameState")
	gs.seed_rng(777)
	await test_stations()
	await test_night_meters()
	test_unlock_days()
	test_goals_and_beacon()
	await test_locations()
	await test_drain_and_damage()
	await test_crater_death()
	await test_book()
	await test_playthrough(gs.Difficulty.NORMAL, true, "Normal with care")
	await test_playthrough(gs.Difficulty.HARD, true, "Hard with care")
	await test_playthrough(gs.Difficulty.HARD, false, "Hard careless")
	SettingsStore.reset(true)
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)

func fresh(d: int = 1) -> void:
	gs.start_game(d)
	gs.show_tutorial = false
	gs.settings = (gs.settings as Dictionary).duplicate()
	gs.settings["event"] = 0.0
	await wait_scene(BUNKER)
	await frames(5)

# ---------------------------------------------------------------- filter, stove, eating
func test_stations() -> void:
	await fresh(gs.Difficulty.NORMAL)
	gs.dirty_water = 3
	check(not gs.can_filter() and gs.filter_water(1) == 0, "no filter without the Water Filter")
	gs.unlocked_rooms.append("utility")
	gs.built["purifier"] = true
	var w0: int = gs.water
	check(gs.filter_water(2) == 2 and gs.dirty_water == 1 and gs.water == w0 + 2, "Water Filter: 2 dirty -> 2 clean")
	check(not gs.can_cook("cook_meat"), "no cooking without the Stove")
	gs.built["stove"] = true
	gs.raw_meat = 1
	gs.mushroom = 2
	gs.wood = 3
	gs.dirty_water = 2
	var f0: int = gs.food
	check(gs.cook("cook_meat") and gs.raw_meat == 0 and gs.food == f0 + 1 and gs.wood == 2, "Stove: meat + wood -> meal")
	check(gs.cook("mushroom_stew") and gs.mushroom == 0 and gs.food == f0 + 2, "Stove: 2 mushrooms -> meal")
	check(gs.cook("boil_water") and gs.dirty_water == 0, "Stove: boil 2 dirty water -> 1 clean")
	check(not gs.cook("cook_meat"), "can't cook without raw meat")
	gs.water_meter = 30.0
	check(gs.consume_stock("water") and is_equal_approx(gs.water_meter, 80.0), "drinking in the bunker fills thirst")
	gs.health = 5
	gs.bandage = 1
	check(gs.consume_stock("bandage") and gs.health == 8, "bandage heals 3")
	# the bunker shows the stations once built
	gs.changed.emit()
	await frames(2)
	var b: Node = current_scene
	check(b.station_x("purifier", "utility") > 0.0 and b.station_x("stove", "utility") > 0.0, "Water Filter and Stove are bunker stations")
	b.use_station({"kind": "stove", "x": b.station_x("stove", "utility"), "room": "utility"})
	await frames(2)
	check(b.popup != null and b.popup.buttons.has("cook_cook_meat"), "E at the Stove opens the cook popup")
	b.close_popup()
	await frames(2)
	b.use_station({"kind": "locker", "x": 0, "room": "bedroom"})
	await frames(2)
	check(b.popup != null and b.popup.buttons.has("drink") and b.popup.buttons.has("pack_water"), "locker: eat/drink/pack buttons")
	b.close_popup()

# ---------------------------------------------------------------- night upkeep
func test_night_meters() -> void:
	await fresh(gs.Difficulty.NORMAL)
	gs.went_outside = true
	gs.water_meter = 20.0
	gs.food_meter = 50.0
	gs.water = 0
	gs.food = 3
	var h0: int = gs.health
	gs.sleep()
	check(gs.water_meter == 0.0 and gs.health == h0 - 2, "night: no water, thirst runs empty -> -2 health (once)")
	check(gs.food == 2 and is_equal_approx(gs.food_meter, 75.0), "night: one meal eaten from the locker (+50 after the 25 burn)")
	await wait_scene("res://scenes/overnight.tscn")
	gs.start_day()
	await wait_scene(BUNKER)

func test_unlock_days() -> void:
	gs.day = 1
	check(gs.is_location_unlocked("surface") and not gs.is_location_unlocked("mine") and not gs.is_location_unlocked("crater"), "day 1: surface only")
	gs.day = 2
	check(gs.is_location_unlocked("mine") and gs.location_lock_text("crater") == "Opens on day 4.", "day 2: mine open, crater locked text")
	gs.day = 4
	check(gs.is_location_unlocked("crater"), "day 4: crater open")
	gs.day = 2
	gs.went_outside = false
	gs.skip_expedition = false
	check(not gs.go_outside("crater") and not gs.went_outside, "can't go to a locked place")

func test_goals_and_beacon() -> void:
	gs.unlocked_rooms.assign(["bedroom", "radio"])
	gs.scrap = 20
	gs.radio_part = 0
	gs.damaged_rooms.clear()
	check(not gs.can_build("radio"), "Radio Beacon needs the radio part")
	gs.radio_part = 1
	check(gs.build("radio") and gs.radio_part == 0 and gs.is_rescued(), "with the part the beacon builds (rescue)")
	gs.built.erase("radio")
	gs.day = 1
	gs.today = {}
	gs.goal_done = false
	var w0: int = gs.water
	gs.today["banked"] = {"scrap": 8}
	check(gs.check_goal() and gs.water == w0 + 2 and gs.get_goal_text().begins_with("Done"), "day goal done: reward added once")
	check(gs.check_goal() and gs.water == w0 + 2, "reward not given twice")
	check(not gs.event_by_id("horde").is_empty() and gs.event_by_id("horde").get("forced_only", false), "horde event exists (forced only)")
	var random_horde := false
	for i in 60:
		if gs.pick_event().get("id", "") == "horde":
			random_horde = true
	check(not random_horde, "horde never picked at random")
	var ids := []
	for e in gs.load_events():
		ids.append(e.id)
	check(["poisoned_can", "rain", "trader_rat", "spoiled", "mushroom_patch"].all(func(x): return x in ids), "new food/water events load")

# ---------------------------------------------------------------- every location
func test_locations() -> void:
	await fresh(gs.Difficulty.NORMAL)
	for id in ["surface", "mine", "crater"]:
		gs.day = 4
		gs.went_outside = false
		gs.skip_expedition = false
		gs.last_stand_pack = {}
		check(gs.go_outside(id), "go outside to %s" % id)
		check(await wait_scene(EXPEDITION), "%s loads" % id)
		await frames(20)
		var ex: Node = current_scene
		ex.spawner.enabled = false
		check(ex.location == id and ex.COLS == int(Locations.get_config(id).cols), "%s: layout from the location table (%d cols)" % [id, ex.COLS])
		check(ex.crates.get_child_count() == ex.CRATE_XS.size() and ex.CRATE_XS.size() > 0, "%s: crates placed" % id)
		var srcs := get_nodes_in_group("sources").filter(func(n): return n.is_inside_tree())
		check(srcs.size() > 0, "%s: water / mushroom sources (%d)" % [id, srcs.size()])
		check(ex.hatch.player_inside, "%s: starts at the exit" % id)
		if id == "mine":
			check(ex.ceiling_rows[ex.HATCH_COL + 10] > 0 and ex.ground.get_cell_source_id(Vector2i(ex.HATCH_COL + 10, 0)) != -1, "mine: rock ceiling")
			check(ex.lighting == null or ex.lighting.min_brightness < 0.3, "mine: darker")
			var rocks := 0
			for c in ex.COLS:
				if ex.mining.kind_at(Vector2i(c, ex.mining.floor_rows[c])) in ["scrap_ore", "concrete", "circuits", "pipe", "bones", "toxic"]:
					rocks += 1
			check(rocks > 5, "mine: exposed ore rocks to mine (%d)" % rocks)
		if id == "crater":
			var has_part := false
			for c in ex.crates.get_children():
				if c.contents.has("radio_part"):
					has_part = true
			check(has_part, "crater: a crate holds the radio part")
			check(ex.rad_mult > gs.get_radiation_multiplier() * 1.5, "crater: very high radiation")
		# a source gives dirty water / mushrooms
		var s: Node = srcs[0]
		var p: Node = ex.player
		var before: int = p.total_items()
		s.interact(p)
		check(p.total_items() == before + 1, "%s: E at a %s gives %s" % [id, s.kind, s.item])
		p.add_item("scrap", 2)
		var scrap0: int = gs.scrap
		var dirty0: int = gs.dirty_water + gs.mushroom
		p.global_position = ex.hatch.global_position + Vector2(0, -2)
		await frames(3)
		await tap(KEY_E)
		check(ex.ended, "%s: E at the exit banks" % id)
		check(await wait_scene(BUNKER), "%s: back in the bunker" % id)
		check(gs.scrap == scrap0 + 2 and gs.dirty_water + gs.mushroom == dirty0 + 1, "%s: loot banked" % id)
		await frames(10)

# ---------------------------------------------------------------- hunger and thirst outside
func test_drain_and_damage() -> void:
	gs.day = 1
	gs.went_outside = false
	gs.water_meter = 80.0
	gs.food_meter = 80.0
	gs.go_outside("surface")
	check(await wait_scene(EXPEDITION), "out for the drain test")
	await frames(10)
	var ex: Node = current_scene
	ex.spawner.enabled = false
	var sv: RefCounted = ex.survival
	check(sv != null and absf(sv.water - 80.0) < 1.0, "meters start from GameState")
	var w0: float = sv.water
	await create_timer(2.0).timeout
	check(sv.water < w0 and sv.food < 80.0, "meters drain outside (%.1f)" % sv.water)
	var p: Node = ex.player
	p.add_item("water", 1)
	p.add_item("canned_food", 1)
	sv.water = 10.0
	sv.food = 10.0
	await tap(KEY_R)
	check(sv.water > 55.0 and p.items.water == 0, "R drinks clean water")
	await tap(KEY_Q)
	check(sv.food > 55.0 and p.items.canned_food == 0, "Q eats canned food")
	p.add_item("dirty_water", 1)
	var r0: float = ex.radiation
	await tap(KEY_R)
	check(ex.radiation > r0 + 5.0, "dirty water adds radiation")
	sv.water = 0.0
	sv.food = 0.0
	var hp0: int = p.health.hp
	await create_timer(4.6).timeout
	check(p.health.hp <= hp0 - 2, "empty meters drain health (%d -> %d)" % [hp0, p.health.hp])
	p.take_damage(99, "thirst")
	check(await wait_scene("res://scenes/scar_pick.tscn") or scene_path() == "res://scenes/game_over.tscn", "dying of thirst ends the trip")
	check(gs.water_meter >= gs.DEATH_MIN_METER, "you wake up with some water")
	await _through_night()

# ---------------------------------------------------------------- crater death
func test_crater_death() -> void:
	gs.bounces = 3
	gs.day = 4
	gs.went_outside = false
	gs.skip_expedition = false
	gs.go_outside("crater")
	check(await wait_scene(EXPEDITION), "into the crater")
	await frames(10)
	var ex: Node = current_scene
	ex.spawner.enabled = false
	var p: Node = ex.player
	# carry limit
	var added: int = p.add_item("scrap", 99)
	check(added == p.carry_limit and p.capacity_left() == 0 and p.add_item("wood", 1) == 0, "carry limit holds (%d)" % added)
	p.global_position = Vector2(ex.HATCH_X + 400, ex.floor_y(ex.HATCH_X + 400) - 1)
	ex.radiation = 100.0
	check(await wait_scene("res://scenes/scar_pick.tscn", 20.0), "radiation kills you in the crater")
	check(gs.last_stand_pack.get("location", "") == "crater", "the pack stays in the crater")
	await _through_night()

func _through_night() -> void:
	for i in 3:
		if scene_path() == "res://scenes/scar_pick.tscn":
			var ch: Array = gs.scar_choices()
			if ch.is_empty():
				gs.continue_after_scar()
			else:
				gs.pick_scar(ch[0])
		await frames(10)
		if scene_path() == "res://scenes/night_event.tscn":
			gs.choose_event_option(1 if gs.can_choose_option(gs.current_event.options[1]) else 0)
			gs.show_overnight()
		await frames(10)
		if scene_path() == "res://scenes/overnight.tscn":
			gs.start_day()
			await wait_scene(BUNKER)
			return

# ---------------------------------------------------------------- crafts / book
func test_book() -> void:
	var ids: Array = GuideData.all_ids()
	for k in gs.ITEMS:
		if not k in ids:
			check(false, "book lists item %s" % k)
	check(gs.ITEMS.keys().all(func(k): return k in ids), "book lists every item (%d)" % gs.ITEMS.size())
	check(gs.LOOT_KINDS.all(func(k): return gs.ITEMS.has(k)) and gs.STOCK_KINDS.all(func(k): return gs.ITEMS.has(k)), "every stock / loot kind has a book entry")
	check(gs.BUILDINGS.keys().all(func(k): return k in ids) and gs.RECIPES.keys().all(func(k): return k in ids), "book lists every building and recipe")
	check(Locations.ORDER.all(func(k): return k in ids), "book lists every place")
	var b: Node = current_scene
	if scene_path() != BUNKER:
		gs.start_day()
		await wait_scene(BUNKER)
		b = current_scene
	await frames(5)
	b.pause_menu.open()
	await frames(2)
	check(b.pause_menu.book_button != null and b.pause_menu.book_button.visible, "pause menu has Crafts / Book")
	b.pause_menu.book_button.pressed.emit()
	await frames(3)
	var book: Node = b.pause_menu.book
	check(book != null and book.list.get_child_count() == gs.ITEMS.size(), "book opens on the items (%d entries)" % (book.list.get_child_count() if book else 0))
	for s in GuideData.SECTIONS:
		book.show_section(s)
		await frames(2)
		check(book.list.get_child_count() > 0, "book tab %s has entries" % s)
	await tap(KEY_ESCAPE)
	await frames(2)
	check(b.pause_menu.book == null and b.pause_menu.is_open, "Esc closes the book, the menu stays")
	await tap(KEY_ESCAPE)
	await frames(2)
	check(not b.pause_menu.is_open and not paused, "Esc again resumes")

# ---------------------------------------------------------------- playthroughs (API level)
# One trip a day, hauls about what a careful player brings home on that difficulty (scaled by the
# loot multiplier and the carry limit); outside time drains the meters. Careful play eats and drinks
# from the locker in the morning, filters / cooks, and builds toward the beacon.
func test_playthrough(d: int, careful: bool, label: String) -> void:
	gs.start_game(d)
	gs.show_tutorial = false
	gs.seed_rng(4242 + d)
	await wait_scene(BUNKER)
	# hauls of at most 12 (tier 1 carry), what a careful run brings home; scaled by the loot multiplier
	var plan := {
		1: ["surface", {"wood": 6, "concrete": 6}],
		2: ["mine", {"concrete": 4, "scrap": 5, "circuits": 2, "mushroom": 1}],
		3: ["surface", {"scrap": 7, "concrete": 3, "dirty_water": 2}],
		4: ["mine", {"concrete": 5, "scrap": 4, "mushroom": 2, "dirty_water": 1}],
		5: ["crater", {"scrap": 8, "radio_part": 1, "canned_food": 1, "dirty_water": 2}],
		6: ["surface", {"scrap": 3, "wood": 3, "dirty_water": 4, "raw_meat": 2}],
		7: ["mine", {"scrap": 4, "mushroom": 4, "dirty_water": 4}],
	}
	if d == gs.Difficulty.HARD:   # Hard: what you actually get there (already scaled), survival first
		plan = {
			1: ["surface", {"wood": 6, "concrete": 4, "dirty_water": 2}],
			2: ["mine", {"concrete": 4, "scrap": 3, "mushroom": 3, "dirty_water": 2}],
			3: ["surface", {"scrap": 4, "concrete": 2, "circuits": 1, "dirty_water": 3, "raw_meat": 2}],
			4: ["mine", {"dirty_water": 4, "mushroom": 4, "scrap": 2, "wood": 2}],
			5: ["surface", {"dirty_water": 4, "raw_meat": 2, "scrap": 4, "wood": 2}],
			6: ["mine", {"dirty_water": 4, "mushroom": 4, "scrap": 2, "wood": 2}],
			7: ["mine", {"dirty_water": 4, "mushroom": 4, "scrap": 2, "wood": 2}],
		}
	var trip_secs := 150.0
	var guard := 0
	while guard < 40:
		guard += 1
		var sp := scene_path()
		if sp == "res://scenes/ending.tscn" or sp == "res://scenes/game_over.tscn":
			break
		if sp == "res://scenes/scar_pick.tscn" or sp == "res://scenes/night_event.tscn" or sp == "res://scenes/overnight.tscn":
			await _through_night()
			continue
		if sp != BUNKER:
			await frames(10)
			continue
		var day: int = gs.day
		print("  [%s] day %d bounces %d health %d water %d food %d meters %d/%d dirty %d stock w%d c%d s%d ci%d built %s notes %s" % [label, day, gs.bounces, gs.health, gs.water, gs.food, gs.water_meter, gs.food_meter, gs.dirty_water, gs.wood, gs.concrete, gs.scrap, gs.circuits, str(gs.built.keys()), str(gs.last_night_summary)])
		if careful:
			_morning_care()
		var p: Array = plan.get(day, plan[7])
		var haul: Dictionary = {}
		var mult: float = (1.0 if d == gs.Difficulty.HARD else gs.get_loot_multiplier()) if careful else 0.3
		var room: int = gs.get_carry_limit()
		for k in p[1]:
			var n := roundi(int(p[1][k]) * mult) if k != "radio_part" else (1 if careful else 0)
			n = mini(n, room)
			room -= n
			if n > 0:
				haul[k] = n
		# the trip: meters drain (careful players drink / eat a packed water and meal on the way)
		var drain: Dictionary = gs.get_meter_drain()
		var wm: float = gs.water_meter - Survival.DRAIN.water * drain.water * trip_secs
		var fm: float = gs.food_meter - Survival.DRAIN.food * drain.food * trip_secs
		if careful:
			if wm < 25.0 and gs.water > gs.night_water_need():
				gs.water -= 1
				wm += 40.0
			if fm < 25.0 and gs.food > gs.night_food_need():
				gs.food -= 1
				fm += 40.0
			# out of clean supplies: drink dirty water / eat raw finds from the haul (risky, but alive)
			while wm < 20.0 and int(haul.get("dirty_water", 0)) > 1:
				haul.dirty_water -= 1
				wm += Survival.CONSUMABLES.dirty_water.gain
			for raw in ["mushroom", "raw_meat"]:
				while fm < 20.0 and int(haul.get(raw, 0)) > 1:
					haul[raw] -= 1
					fm += Survival.CONSUMABLES[raw].gain
		if wm < 0.0 or fm < 0.0:   # starving outside: about a heart per 8 s below zero
			var lost := int((-minf(wm, 0.0) / (Survival.DRAIN.water * drain.water) + -minf(fm, 0.0) / (Survival.DRAIN.food * drain.food)) / Survival.STARVE_EVERY)
			if lost >= 10:
				gs.water_meter = 0.0
				gs.food_meter = 0.0
				gs.went_outside = true
				gs.current_location = p[0]
				gs.player_died(haul, Vector2(100, 0))
				await frames(10)
				continue
		gs.went_outside = true
		gs.current_location = p[0]
		gs.set_meters(wm, fm)
		gs.bank_loot(haul)
		await wait_scene(BUNKER)
		await frames(3)
		if careful:
			_evening_build()
		gs.sleep()
		await frames(5)
	var sp2 := scene_path()
	if careful and d == gs.Difficulty.NORMAL:
		check(sp2 == "res://scenes/ending.tscn" and gs.is_rescued(), "%s: reaches the rescue ending (bounces left %d, scene %s)" % [label, gs.bounces, sp2])
	elif careful:
		check(sp2 == "res://scenes/ending.tscn", "%s: survives the week (rescued %s, bounces left %d, scene %s)" % [label, gs.is_rescued(), gs.bounces, sp2])
	else:
		check(sp2 == "res://scenes/game_over.tscn" or not gs.is_rescued(), "%s: lost (no rescue) (%s, bounces %d)" % [label, sp2, gs.bounces])

func _morning_care() -> void:
	while gs.water_meter < 75.0 and gs.water > gs.night_water_need() and gs.consume_stock("water"):
		pass
	while gs.food_meter < 70.0 and gs.food > gs.night_food_need() and gs.consume_stock("food"):
		pass
	if gs.health < 7 and gs.bandage > 0:
		gs.consume_stock("bandage")

func _evening_build() -> void:
	# build order: Utility Room, Stove, Water Filter, Radio Room, Beacon (then extras)
	for step in [["room", "utility"], ["b", "stove"], ["b", "purifier"], ["room", "radio"], ["b", "radio"], ["b", "door"]]:
		if step[0] == "room" and gs.can_unlock(step[1]):
			gs.unlock_room(step[1])
		elif step[0] == "b" and gs.can_build(step[1]):
			gs.build(step[1])
		elif step[0] == "room" and not gs.is_room_unlocked(step[1]):
			break   # save up for it
	while gs.can_filter() and gs.filter_water(1) > 0:
		pass
	for r in ["cook_meat", "cook_meat", "mushroom_stew", "mushroom_stew"]:
		if gs.can_cook(r):
			gs.cook(r)
	while not gs.is_working("purifier") and gs.water < gs.night_water_need() + 1 and gs.can_cook("boil_water"):
		gs.cook("boil_water")
	for room in ["utility", "radio"]:
		if gs.is_room_damaged(room) and gs.can_repair(room):
			gs.repair_room(room)
