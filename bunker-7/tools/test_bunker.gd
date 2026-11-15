# Headless test of the walkable bunker with the REAL GameState (exit 0 = all PASS):
#   Godot --headless --fixed-fps 60 --path bunker-7 --script res://tools/test_bunker.gd
# Drives the survivor with real key events (A/D walk, E use, Esc, Enter on the focused popup button)
# and follows the real scene changes (GameState.go_to): new game -> tutorial, stations, build,
# unlock, backpack tiers, sleep -> overnight -> bunker, ladder -> expedition, hatch -> bunker,
# death -> scar pick -> bunker, popups closing with Esc without the pause menu.
# Uses its own settings file (hints / tutorial flags), never the player's.
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
	e.keycode = code   # ui_accept / ui_cancel match by keycode
	e.pressed = down
	Input.parse_input_event(e)

func tap(code: Key) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(2)

func scene_path() -> String:
	return current_scene.scene_file_path if current_scene else ""

# Waits (up to `secs`) until the current scene is `path`. Returns true when it got there.
func wait_scene(path: String, secs := 6.0) -> bool:
	for i in int(secs * 60):
		if scene_path() == path and current_scene.is_node_ready():
			return true
		await frames(1)
	return false

func bunker() -> Node2D:
	return current_scene as Node2D if scene_path() == BUNKER else null

# Walks with A/D (real key presses) until the walker stands within 2 px of x.
func walk_to(x: float) -> bool:
	var b := bunker()
	if b == null:
		return false
	for i in 900:
		var dx: float = x - b.walker.position.x
		if absf(dx) <= 1.5:
			break
		var k := KEY_D if dx > 0 else KEY_A
		key(k, true)
		await frames(1)
		key(k, false)
	await frames(2)
	return absf(x - b.walker.position.x) <= 2.0

func wait_idle(b: Node2D, secs := 4.0) -> void:
	for i in int(secs * 60):
		if not b.busy and not b.walker.climbing:
			return
		await frames(1)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	SettingsStore.path = "user://test_bunker_settings.cfg"
	SettingsStore.reset(true)
	gs = root.get_node("GameState")
	gs.seed_rng(12345)
	await test_new_game_tutorial()
	await test_rules()
	await test_stations_and_popups()
	await test_build()
	await test_unlock()
	await test_backpack()
	await test_sleep()
	await test_ladder_and_hatch()
	await test_death_flow()
	SettingsStore.reset(true)
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)

func no_events() -> void:
	gs.settings = (gs.settings as Dictionary).duplicate()
	gs.settings["event"] = 0.0   # no night event cards in these flows

func clear_stock() -> void:
	for k in ["wood", "concrete", "scrap", "circuits"]:
		gs.set(k, 0)

# ---------------------------------------------------------------- new game
func test_new_game_tutorial() -> void:
	gs.start_game(gs.Difficulty.NORMAL)
	check(await wait_scene(BUNKER), "new game opens the walkable bunker")
	await frames(10)
	var b := bunker()
	check(b != null and b.tutorial != null and not get_nodes_in_group("tutorial_open").is_empty(),
			"first new game opens the tutorial slideshow")
	check(absf(b.walker.position.x - b.station_x("cot")) < 20.0 and is_equal_approx(b.walker.position.y, b.FLOOR_Y),
			"Day 1 starts at the cot")
	check(not b.walker.can_walk, "no walking while the tutorial is open")
	await tap(KEY_ESCAPE)
	await frames(3)
	check(b.tutorial == null and get_nodes_in_group("tutorial_open").is_empty(), "Esc closes the tutorial")
	check(not b.pause_menu.is_open and not paused, "...without opening the pause menu")
	check(b.walker.can_walk, "walking again after the tutorial")
	# second new game: no tutorial
	gs.start_game(gs.Difficulty.NORMAL)
	await frames(3)
	check(await wait_scene(BUNKER), "second new game: bunker again")
	await frames(5)
	check(bunker().tutorial == null, "tutorial only on the very first new game")

# ---------------------------------------------------------------- GameState rules
func test_rules() -> void:
	gs.start_game(gs.Difficulty.NORMAL)
	await wait_scene(BUNKER)
	await frames(3)
	check(gs.get_backpack_tier() == 1 and gs.get_carry_limit() == 12, "tier 1 carries 12")
	check(gs.max_health() == 10 and gs.get_day() == 1, "max_health 10, get_day 1")
	check(gs.backpack_upgrade_cost(2) == {"scrap": 6, "wood": 4} and gs.backpack_upgrade_cost(1).is_empty()
			and gs.backpack_upgrade_cost(5).is_empty(), "backpack_upgrade_cost per tier")
	check(GSBridge.backpack_tier() == 1 and GSBridge.max_health() == 10 and GSBridge.day() == 1, "GSBridge reads the new contract")
	gs.unlocked_rooms.append("storage")
	check(gs.get_carry_limit() == 16, "storage room adds +4 on top of the tier (12 + 4)")
	gs.scars.append("steady")
	check(gs.get_carry_limit() == 18, "Steady Hands adds +2 more")
	gs.backpack_tier = 4
	check(gs.get_carry_limit() == 30, "tier 4 + storage + steady = 30")
	check(gs.carry_limit_for_tier(2) == 22, "carry_limit_for_tier uses the same rule")
	gs.start_game(gs.Difficulty.NORMAL)
	await wait_scene(BUNKER)
	# bank_loot takes water and food too, and remembers what came in
	var w0: int = gs.water
	gs.went_outside = true
	gs.bank_loot({"wood": 2, "water": 1, "food": 3, "junk": 5})
	check(gs.wood == 2 and gs.water == w0 + 1 and gs.last_banked == {"wood": 2, "water": 1, "food": 3},
			"bank_loot adds materials, water and food")
	await frames(int(gs.HATCH_TRANSITION * 60) + 10)   # its delayed scene change
	check(await wait_scene(BUNKER), "bank_loot goes to the bunker")
	await frames(5)

# ---------------------------------------------------------------- stations, popups, Esc
func test_stations_and_popups() -> void:
	gs.start_game(gs.Difficulty.NORMAL)
	check(await wait_scene(BUNKER), "bunker for the station tests")
	await frames(5)
	var b := bunker()
	await wait_idle(b)
	var x0: float = b.walker.position.x
	key(KEY_D, true)
	await frames(20)
	key(KEY_D, false)
	check(b.walker.position.x > x0 + 15.0, "D walks right (%.0f -> %.0f)" % [x0, b.walker.position.x])
	for kind in ["locker", "calendar", "cot", "upgrade", "workbench"]:
		check(await walk_to(b.station_x(kind)), "walked to the %s" % kind)
		check(b.near.get("kind", "") == kind and b._prompt.visible, "%s prompt shows" % kind)
		await tap(KEY_E)
		check(b.popup != null and b.popup_kind.begins_with(kind), "E opens the %s popup" % kind)
		check(not b.walker.can_walk, "no walking with a popup open")
		await tap(KEY_ESCAPE)
		await frames(3)
		check(b.popup == null, "Esc closes the %s popup" % kind)
		check(not b.pause_menu.is_open and not paused, "...and the pause menu stays shut")
	# E closes a popup too
	await tap(KEY_E)
	check(b.popup != null, "E opens the workbench again")
	await tap(KEY_E)
	check(b.popup == null, "E closes it")
	# Esc with no popup = pause menu
	await tap(KEY_ESCAPE)
	check(b.pause_menu.is_open and paused, "Esc with no popup opens the pause menu")
	await tap(KEY_ESCAPE)
	check(not b.pause_menu.is_open and not paused, "Esc closes the pause menu")
	# the walker cannot leave the reachable rooms
	key(KEY_D, true)
	await frames(240)
	key(KEY_D, false)
	check(b.walker.position.x <= b.walker.max_x + 0.1 and b.walker.position.x < b.room_x("utility"),
			"a locked door stops the walker (x %.0f)" % b.walker.position.x)

# ---------------------------------------------------------------- build
func test_build() -> void:
	var b := bunker()
	clear_stock()
	gs.wood = 5
	gs.scrap = 3
	check(await walk_to(b.station_x("workbench")), "at the bedroom workbench")
	await tap(KEY_E)
	var btn: Button = b.popup.buttons.get("build_door")
	check(btn != null and not btn.disabled, "Reinforced Door can be built")
	await tap(KEY_ENTER)   # the first enabled button has focus
	check(gs.is_built("door") and gs.wood == 1 and gs.scrap == 1, "Enter builds it and spends 4 wood + 2 scrap")
	btn = b.popup.buttons.get("build_door")
	check(btn != null and btn.disabled and btn.text == "Built", "popup now says Built (disabled)")
	btn.pressed.emit()
	check(gs.wood == 1 and gs.scrap == 1 and not gs.build("door"), "cannot build twice")
	await tap(KEY_ESCAPE)
	await frames(2)
	var room: Node = b._rooms.get_node("Room_bedroom")
	var bld: CanvasItem = room.get_node("ReinforcedDoor/Bld_door")
	check(bld != null and bld.modulate.a > 0.9, "the built door appears in the world")

# ---------------------------------------------------------------- unlock
func test_unlock() -> void:
	var b := bunker()
	clear_stock()
	var door_x: float = b.station_x("door", "utility")
	check(door_x > 0.0, "the utility door is a station")
	check(await walk_to(door_x), "at the utility door")
	await tap(KEY_E)
	check(b.popup != null and b.popup_kind == "door:utility", "E opens the unlock popup")
	check(b.popup.buttons.has("unlock") and b.popup.buttons["unlock"].disabled, "Unlock is disabled without materials")
	await tap(KEY_ESCAPE)
	gs.wood = 6
	gs.concrete = 7
	await tap(KEY_E)
	check(not b.popup.buttons["unlock"].disabled, "Unlock enabled with 6 wood + 6 concrete")
	await tap(KEY_ENTER)
	await frames(3)
	check(gs.is_room_unlocked("utility") and gs.wood == 0 and gs.concrete == 1, "unlocked, cost spent")
	check(b.popup == null, "unlock closes the popup")
	check(b.station_x("door", "utility") < 0.0 and b.station_x("door", "radio") > 0.0, "the utility door is open, the radio door is next")
	check(not gs.unlock_room("utility") and gs.concrete == 1, "cannot unlock twice")
	check(await walk_to(b.station_x("workbench", "utility")), "walked into the utility room")
	# a damaged room: no building, repair instead
	gs.scrap = 20
	gs.concrete = 2   # V3: the Water Filter also needs concrete and a circuit
	gs.circuits = 1
	gs.damaged_rooms.append("utility")
	gs.changed.emit()
	await frames(2)
	await tap(KEY_E)
	check(b.popup_kind == "workbench:utility", "utility workbench popup")
	check(b.popup.buttons["build_purifier"].disabled and b.popup.buttons.has("repair"), "damaged room: no build, a Repair button")
	b.popup.buttons["repair"].pressed.emit()
	await frames(2)
	check(not gs.is_room_damaged("utility") and gs.scrap == 17, "repair works and costs 3 scrap")
	check(not b.popup.buttons["build_purifier"].disabled, "after repair: Build is enabled")
	await tap(KEY_ESCAPE)
	gs.scrap = 0
	gs.concrete = 0
	gs.circuits = 0

# ---------------------------------------------------------------- backpack
func test_backpack() -> void:
	var b := bunker()
	clear_stock()
	check(await walk_to(b.station_x("upgrade")), "at the upgrade bench")
	var limits := [12, 16, 20, 24]
	check(gs.get_carry_limit() == 12, "tier 1: carry 12")
	await tap(KEY_E)
	check(b.popup.buttons.has("upgrade") and b.popup.buttons["upgrade"].disabled, "no materials: Upgrade disabled")
	b.popup.buttons["upgrade"].pressed.emit()
	check(gs.get_backpack_tier() == 1 and not gs.upgrade_backpack(), "refused without materials")
	await tap(KEY_ESCAPE)
	for tier in [2, 3, 4]:
		var cost: Dictionary = gs.backpack_upgrade_cost(tier)
		clear_stock()
		for k in cost:
			gs.set(k, int(cost[k]))
		await tap(KEY_E)
		check(not b.popup.buttons["upgrade"].disabled, "tier %d affordable" % tier)
		await tap(KEY_ENTER)
		check(gs.get_backpack_tier() == tier and gs.get_carry_limit() == limits[tier - 1],
				"tier %d: carry %d" % [tier, gs.get_carry_limit()])
		var left := 0
		for k in ["wood", "concrete", "scrap", "circuits"]:
			left += int(gs.get(k))
		check(left == 0, "tier %d spent exactly %s" % [tier, str(cost)])
		await tap(KEY_ESCAPE)
	await tap(KEY_E)
	check(not b.popup.buttons.has("upgrade"), "tier 4: no more upgrades")
	await tap(KEY_ESCAPE)
	gs.scrap = 50
	gs.concrete = 50
	gs.circuits = 50
	check(not gs.upgrade_backpack() and gs.get_backpack_tier() == 4, "upgrade_backpack refuses past tier 4")
	clear_stock()

# ---------------------------------------------------------------- sleep
func test_sleep() -> void:
	var b := bunker()
	no_events()
	gs.went_outside = true
	var day0: int = gs.day
	check(await walk_to(b.station_x("cot")), "at the cot")
	await tap(KEY_E)
	check(b.popup_kind.begins_with("cot") and b.popup.buttons.has("sleep"), "E at the cot asks to sleep")
	await tap(KEY_ENTER)
	check(await wait_scene("res://scenes/overnight.tscn"), "sleeping goes to the overnight summary")
	check(gs.day == day0 + 1 and not gs.went_outside, "the day advanced (%d -> %d)" % [day0, gs.day])
	var cont: Button = null
	for n in current_scene.find_children("*", "Button", true, false):
		if (n as Button).text == "Continue":
			cont = n
	check(cont != null, "overnight has Continue")
	if cont:
		cont.pressed.emit()
	check(await wait_scene(BUNKER), "Continue wakes you in the bunker")
	await frames(5)
	b = bunker()
	check(absf(b.walker.position.x - b.station_x("cot")) < 20.0, "...at the cot")
	check(b._banner.visible and b._banner_label.text.begins_with("Day %d" % gs.day), "day summary banner shows")

# ---------------------------------------------------------------- ladder, hatch
func test_ladder_and_hatch() -> void:
	var b := bunker()
	await wait_idle(b)
	clear_stock()
	var w0: int = gs.water
	check(await walk_to(b.shaft_x()), "at the foot of the ladder")
	check(b.near.get("kind", "") == "ladder", "ladder prompt")
	await tap(KEY_E)
	if gs.is_location_unlocked("mine"):   # V3: from day 2 the ladder asks where to go
		check(b.popup != null and b.popup_kind.begins_with("ladder") and b.popup.buttons.has("go_mine")
				and b.popup.buttons["go_crater"].disabled == not gs.is_location_unlocked("crater"), "ladder asks where to go (crater locked until day 4)")
		await frames(3)
		await tap(KEY_ENTER)   # the first button: the surface
		await frames(2)
	check(b.walker.climbing and b.busy, "E climbs up the ladder")
	check(await wait_scene(EXPEDITION), "the climb starts the expedition")
	check(gs.went_outside, "today's trip is marked")
	await frames(30)
	var ex: Node = current_scene
	ex.spawner.enabled = false
	var p: Node = ex.player
	check(ex.hatch.player_inside, "the expedition starts in the hatch")
	p.add_item("wood", 3)
	p.add_item("water", 1)
	await tap(KEY_E)
	check(ex.ended, "E in the hatch banks")
	check(await wait_scene(BUNKER, 4.0), "banking climbs down into the bunker")
	check(gs.wood == 3 and gs.water == w0 + 1, "stock updated once (wood %d, water %d)" % [gs.wood, gs.water])
	await frames(5)
	b = bunker()
	check(b.walker.climbing and absf(b.walker.position.x - b.shaft_x()) < 1.0, "arrives climbing down the shaft")
	await wait_idle(b)
	check(is_equal_approx(b.walker.position.y, b.FLOOR_Y) and b.walker.can_walk, "down at the foot of the ladder, walking")
	check(b._banner_label.text.contains("+3 wood") or b._banner_label.text.contains("ladder"), "banked loot / ladder hint shown")
	await frames(60)
	check(gs.wood == 3, "banked only once")
	await tap(KEY_E)
	await frames(5)
	check(not b.walker.climbing and scene_path() == BUNKER and b._banner_label.text.contains("Sleep"),
			"after the trip the ladder says sleep first")

# ---------------------------------------------------------------- death
func test_death_flow() -> void:
	no_events()
	gs.went_outside = false
	var bounces0: int = gs.bounces
	var b := bunker()
	await walk_to(b.shaft_x())
	await tap(KEY_E)
	if b.popup != null:   # destination popup (day 2+): the surface
		await frames(3)
		await tap(KEY_ENTER)
	check(await wait_scene(EXPEDITION), "out again for the death test")
	await frames(30)
	var ex: Node = current_scene
	ex.spawner.enabled = false
	ex.player.add_item("scrap", 2)
	ex.player.take_damage(99, "zombie")
	check(await wait_scene("res://scenes/scar_pick.tscn", 6.0), "death goes to the scar pick")
	check(gs.bounces == bounces0 - 1 and not gs.last_stand_pack.is_empty(), "bounce lost, pack left outside")
	await frames(5)
	var card: Button = null
	for n in current_scene.find_children("*", "Button", true, false):
		card = n
		break
	check(card != null, "a scar card")
	if card:
		card.pressed.emit()
	check(await wait_scene("res://scenes/overnight.tscn"), "the night runs after the scar pick")
	for n in current_scene.find_children("*", "Button", true, false):
		if (n as Button).text == "Continue":
			(n as Button).pressed.emit()
	check(await wait_scene(BUNKER), "...and you wake up in the bunker")
	await frames(5)
	check(gs.bunker_arrival == "cot" and absf(bunker().walker.position.x - bunker().station_x("cot")) < 20.0, "at the cot")
