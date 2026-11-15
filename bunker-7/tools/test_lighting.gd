# Headless test for Phase 3 lighting (scenes/lighting.gd). Exit 0 = all PASS:
#   Godot --headless --fixed-fps 60 --path bunker-7 --script res://tools/test_lighting.gd
# Uses a separate settings file, so the player's real settings are never touched.
extends SceneTree

const FAKE := preload("res://tools/fake_game_state.gd")
const TEST_CFG := "user://test_lighting_settings.cfg"
var fails := 0
var ex: Node2D
var p: CharacterBody2D
var L: Node2D

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok: fails += 1

func frames(n: int) -> void:
	for i in n: await physics_frame

func start() -> void:
	if ex:
		ex.queue_free()
		await frames(2)
	ex = load("res://scenes/expedition.tscn").instantiate()
	ex.zombies_enabled = false
	root.add_child(ex)
	current_scene = ex
	p = ex.player
	await frames(20)
	L = ex.lighting

func count_mods(n: Node) -> int:
	var c := 1 if n is CanvasModulate and not n.is_queued_for_deletion() else 0
	for k in n.get_children():
		c += count_mods(k)
	return c

func enabled_lights(n: Node) -> int:
	var c := 1 if n is Light2D and n.enabled and n.is_visible_in_tree() and not n.is_queued_for_deletion() else 0
	for k in n.get_children():
		c += enabled_lights(k)
	return c

func ground_occluders() -> int:
	var c := 0
	for o in L._ground_occ:
		if is_instance_valid(o) and not o.is_queued_for_deletion() and o.visible:
			c += 1
	return c

func in_canvas_layer(n: Node) -> bool:
	var q := n.get_parent()
	while q:
		if q is CanvasLayer:
			return true
		q = q.get_parent()
	return false

func set_q(q: String) -> void:   # the pause menu path: store + signal, applied live
	SettingsStore.set_value("lights_quality", q)
	ex.pause_menu.settings_changed.emit("lights_quality", q)
	await frames(15)

func _initialize() -> void:
	run.call_deferred()

func _watchdog() -> void:   # a script error aborts run(): fail instead of hanging
	print("FAIL watchdog: test did not finish")
	quit(1)

func run() -> void:
	create_timer(90.0).timeout.connect(_watchdog)
	SettingsStore.path = TEST_CFG
	SettingsStore.reset()
	SettingsStore.set_value("lights_quality", "full")
	var old: Node = root.get_node_or_null("GameState")
	if old:
		root.remove_child(old)
		old.free()
	var gs: Node = FAKE.new()
	gs.name = "GameState"
	root.add_child(gs)
	await start()

	# --- full ------------------------------------------------------------------
	check(L != null and L.quality == "full", "lighting set up in full")
	check(count_mods(ex) == 1, "one CanvasModulate")
	check(not in_canvas_layer(L.canvas_mod), "CanvasModulate is in the world canvas")
	check(ex.hud is CanvasLayer and ex.pause_menu is CanvasLayer, "HUD and pause menu are CanvasLayers (not darkened)")
	check(L.headlamp != null and L.headlamp.get_parent() == p and L.headlamp.shadow_enabled, "headlamp on the player, with shadows")
	check(L.headlamp.shadow_filter == Light2D.SHADOW_FILTER_NONE, "shadow filter none")
	check(ground_occluders() == L._ground_occ.size() and ground_occluders() >= 15, "ground occluders built (%d)" % ground_occluders())
	var hatch_lamp: Node = ex.get_node_or_null("HatchLamp")
	check(hatch_lamp != null and hatch_lamp.enabled and not hatch_lamp.shadow_enabled, "hatch lamp on, no shadows")
	check(not L.cone.enabled, "flashlight cone off with the axe")
	ex.inventory.select(2)
	await frames(3)
	check(ex.inventory.selected_tool() == "flashlight" and L.cone.enabled, "flashlight selected -> cone on")
	p.face(-1.0)
	await frames(3)
	check(absf(absf(L.cone.rotation) - (PI - L.CONE_TILT)) < 0.01, "cone points left when facing left")
	ex.inventory.select(0)
	await frames(3)
	check(not L.cone.enabled, "cone off again")

	# --- cap -------------------------------------------------------------------
	for i in 20:
		Lighting.add_lamp(ex, p.position + Vector2(-100 + i * 10, -30), Color(1, 0.6, 0.3), 1.0, 50.0, 0.2)
	await frames(20)
	check(L.enabled_sources() <= 6 and L.enabled_sources() >= 6, "cap full: %d world lights on" % L.enabled_sources())
	check(hatch_lamp.enabled, "hatch lamp kept under the cap (priority)")
	check(enabled_lights(ex) <= 6 + 2, "total enabled lights <= cap + player lights (%d)" % enabled_lights(ex))

	# --- simple (live via the pause menu signal) --------------------------------
	await set_q("simple")
	check(L.quality == "simple", "quality switched live to simple")
	check(count_mods(ex) == 1, "simple keeps the ambient")
	check(L.headlamp != null and not L.headlamp.shadow_enabled and not L.cone.shadow_enabled, "simple: no shadows")
	check(ground_occluders() == 0, "simple: occluders removed")
	check(L.enabled_sources() == 3 and hatch_lamp.enabled, "cap simple: %d on, hatch lamp kept" % L.enabled_sources())

	# --- off (picked up by the settings poll, no signal) -------------------------
	SettingsStore.set_value("lights_quality", "off")
	await frames(45)
	check(L.quality == "off", "settings poll applied off")
	check(count_mods(ex) == 0, "off: no CanvasModulate")
	check(L.headlamp == null and p.get_node_or_null("Headlamp") == null or p.get_node("Headlamp").is_queued_for_deletion(), "off: headlamp removed")
	await frames(2)
	check(enabled_lights(ex) == 0, "off: no lights on (%d)" % enabled_lights(ex))
	check(ground_occluders() == 0, "off: no occluders")

	# --- F2 debug cycle (off -> full) ------------------------------------------
	var e := InputEventKey.new()
	e.keycode = KEY_F2
	e.pressed = true
	Input.parse_input_event(e)
	await frames(5)
	check(L.quality == "full" and count_mods(ex) == 1 and L.headlamp != null and ground_occluders() > 0, "F2 cycles off -> full and rebuilds everything")
	await frames(40)
	check(L.quality == "full", "F2 override survives the poll")
	await set_q("full")

	# --- mining removes the occluder ---------------------------------------------
	var m: Node2D = ex.mining
	var col := -1
	for c in range(ex.HATCH_COL + 30, ex.COLS - 10):
		if m.can_mine(Vector2i(c, m.floor_rows[c])):
			col = c
			break
	var row: int = m.floor_rows[col]
	var probe := Vector2(col * 16 + 8, row * 16 + 10)
	var ch: int = col / L._ground_chunk
	var before := Geometry2D.is_point_in_polygon(probe, L._ground_occ[ch].occluder.polygon)
	m.hit(Vector2i(col, row), 99.0)
	await frames(2)
	var after := Geometry2D.is_point_in_polygon(probe, L._ground_occ[ch].occluder.polygon)
	check(before and not after, "mined block stops occluding (col %d row %d)" % [col, row])
	check(Geometry2D.is_point_in_polygon(Vector2(col * 16 + 8, (row + 1) * 16 + 10), L._ground_occ[ch].occluder.polygon), "the block below still occludes")

	# --- glow pool ----------------------------------------------------------------
	var spots := PackedVector2Array()
	for i in 8:
		spots.append(p.global_position + Vector2(i * 30 - 100, 0))
	spots.append(p.global_position + Vector2(2000, 0))
	L.set_glow_spots(spots)
	await frames(15)
	var wanted := 0
	for g in L.glow_pool:
		if g.wanted:
			wanted += 1
			check(g.position.distance_to(p.global_position) < 120.0, "glow light on a near spot")
	check(wanted == L.glow_pool.size() and wanted == 3, "glow pool uses its %d lights" % wanted)
	check(ex.toxic_cells.size() > 0, "toxic tiles known (%d)" % ex.toxic_cells.size())

	# --- ambient -------------------------------------------------------------------
	var near: Color = ex.dusk_ambient()
	p.global_position.x = 150.0
	ex.radiation = 100.0
	var far: Color = ex.dusk_ambient()
	check(far.get_luminance() < near.get_luminance() - 0.2, "darker far out and at high radiation")
	check(L._clamped(far).get_luminance() >= L.MIN_BRIGHTNESS - 0.01, "never below the minimum brightness")
	check(far.g > far.r, "depot ambient is greener")
	p.global_position.x = ex.HATCH_X + 200.0
	ex.radiation = 0.0
	var sub: Color = ex.dusk_ambient()
	check(sub.r > sub.b, "suburb ambient is warmer")
	ex.radiation = 0.0

	# --- zombie eyes -------------------------------------------------------------
	p.global_position.x = 300.0
	await frames(120)
	var z: Node = ex.spawner.spawn_at(360.0)
	await frames(15)
	var eye: CanvasItem = null
	if z:
		for n in get_nodes_in_group("light_glow"):
			eye = n
	check(eye != null and eye.self_modulate.r > 1.2, "zombie eyes boosted in the dark (%s)" % (eye.self_modulate if eye else "none"))
	await set_q("off")
	await frames(15)
	check(eye != null and is_equal_approx(eye.self_modulate.r, 1.0), "no eye boost with lights off")

	SettingsStore.reset()
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
