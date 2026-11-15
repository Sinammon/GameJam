extends Node
# V3 screenshots (not part of the game). SHOT_MODE = morning | bunker | stations | utility | hud | mine | crater | book
# python3 ~/.claude/skills/godot/scripts/debug/run_scenario.py bunker-7 bunker-7/tools/shots/shot_v3.json --godot-bin "$GODOT"
# with SHOT_MODE set; the picture lands in user://shot_v3.png.

var mode := "hud"

func _ready() -> void:
	mode = OS.get_environment("SHOT_MODE") if OS.get_environment("SHOT_MODE") != "" else "hud"
	SettingsStore.path = "user://shot_v3_settings.cfg"
	SettingsStore.reset(true)
	SettingsStore.set_value("tutorial_seen", true)
	var gs := GameState
	gs.seed_rng(7)
	gs.day = 4 if mode in ["crater", "stations", "bunker", "utility"] else 2
	gs.water = 3
	gs.food = 2
	gs.dirty_water = 4
	gs.raw_meat = 1
	gs.mushroom = 3
	gs.wood = 5
	gs.concrete = 4
	gs.scrap = 9
	gs.circuits = 1
	gs.water_meter = 64.0
	gs.food_meter = 41.0
	gs.unlocked_rooms.assign(["bedroom", "utility", "storage"])
	gs.built = {"purifier": true, "stove": true, "door": true}
	gs.show_tutorial = false
	gs.bunker_arrival = "cot"
	gs.today = {"banked": {"scrap": 3}}
	match mode:
		"morning":
			add_child(load("res://scenes/morning.tscn").instantiate())
		"bunker", "stations", "book", "utility":
			var b: Node2D = load("res://scenes/bunker.tscn").instantiate()
			add_child(b)
			_bunker_stage.call_deferred(b)
		_:
			var ex: Node2D = load("res://scenes/expedition.tscn").instantiate()
			ex.zombies_enabled = false
			ex.location = "surface" if mode == "hud" else mode
			add_child(ex)
			_ex_stage.call_deferred(ex)

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _bunker_stage(b: Node2D) -> void:
	await _wait(0.8)
	match mode:
		"stations":
			b.walker.position.x = b.station_x("stove", "utility") - 20
			await _wait(0.6)
			b.use_station({"kind": "stove", "x": b.station_x("stove", "utility"), "room": "utility"})
		"utility":
			b.walker.position.x = b.station_x("stove", "utility") + 30
			b.banner("")
		"book":
			b.pause_menu.open()
			b.pause_menu.open_book()
			if OS.get_environment("SHOT_BOOK") != "":   # e.g. SHOT_BOOK=recipes:0 (section : scroll px)
				var a := OS.get_environment("SHOT_BOOK").split(":")
				await _wait(0.2)
				b.pause_menu.book.show_section(a[0])
				await _wait(0.2)
				b.pause_menu.book.scroll.scroll_vertical = int(a[1]) if a.size() > 1 else 0
		_:
			b.walker.position.x = b.station_x("locker")

func _ex_stage(ex: Node2D) -> void:
	await _wait(0.3)
	var p: Node2D = ex.player
	p.add_item("dirty_water", 2)
	p.add_item("raw_meat", 1)
	p.add_item("scrap", 3)
	var x: float = ex.HATCH_X + (150.0 if mode == "hud" else 260.0)
	if OS.get_environment("SHOT_DX") != "":   # e.g. SHOT_DX=0 shows the exit
		x = ex.HATCH_X + float(OS.get_environment("SHOT_DX"))
	p.global_position = Vector2(x, ex.floor_y(x) - 1)
	if mode == "mine":
		ex.inventory.select(2)   # flashlight
	if mode == "crater":
		ex.radiation = 55.0
	ex.survival.water = 22.0
	ex.survival.food = 47.0
