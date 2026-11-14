# Headless test: godot --headless --path bunker-7 --script res://tools/test_expedition.gd
extends SceneTree

var fails := 0
func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok: fails += 1

func frames(n: int) -> void:
	for i in n: await physics_frame

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var gs = root.get_node("GameState")
	var ex: Node2D = load("res://scenes/expedition.tscn").instantiate()
	root.add_child(ex)
	current_scene = ex
	await frames(30)
	var p: CharacterBody2D = ex.player
	check(p.is_on_floor(), "player lands on ground")
	# walk right 1 second
	var x0 := p.position.x
	Input.action_press("move_right")
	await frames(60)
	check(p.position.x > x0 + 50, "walks right (%.0f -> %.0f)" % [x0, p.position.x])
	Input.action_release("move_right")
	# jump
	await frames(10)
	Input.action_press("jump")
	await frames(3)
	Input.action_release("jump")
	check(p.velocity.y < 0 or not p.is_on_floor(), "jumps")
	await frames(60)
	# crates and carry limit
	check(ex.crates.get_child_count() >= 3, "crates spawned: %d" % ex.crates.get_child_count())
	var c = ex.crates.get_child(0)
	var before: int = c.contents.values().reduce(func(a, b): return a + b, 0)
	p.global_position = c.global_position
	await frames(3)
	c.interact(p)
	check(p.total_items() > 0, "crate gives loot (%s)" % str(p.items))
	for i in 20:
		p.add_item("wood", 5)
	check(p.total_items() == gs.get_carry_limit(), "carry limit enforced (%d)" % p.total_items())
	# far crate has no circuits except far right; near crate never
	check(not ex.crates.get_child(0).contents.has("circuits"), "near crate has no circuits")
	# walk through the whole world: no wall stuck? teleport to far right and check floor
	p.global_position = Vector2(2800, ex.surface_y(2800) - 2)
	await frames(30)
	check(p.is_on_floor(), "far right has ground")
	# radiation grows outside
	var r0: float = ex.radiation
	await frames(60)
	check(ex.radiation > r0, "radiation grows outside (%.2f -> %.2f)" % [r0, ex.radiation])
	# bank at hatch
	p.global_position = ex.hatch.global_position
	await frames(5)
	check(ex.hatch.player_inside, "hatch detects player")
	var before_items: int = p.total_items()
	var rr: float = ex.radiation
	await frames(30)
	check(is_equal_approx(ex.radiation, rr), "radiation paused inside hatch")
	p.global_position = Vector2(500, ex.surface_y(500) - 2)
	await frames(3)
	# death via F1 equivalent
	var died := false
	ex.radiation = 100.0
	await frames(5)
	check(ex.ended and p.dead, "death triggered at 100%")
	await create_timer(2.5).timeout
	check(not gs._fake_pack.is_empty(), "player_died called, pack: " + str(gs._fake_pack))
	# stub reloads the scene: the new one must spawn the Last Stand Pack
	await frames(10)
	var ex2: Node = current_scene
	check(ex2 != ex and ex2 != null, "scene reloaded")
	var pack: Area2D = null
	for n in ex2.get_children():
		if n is Area2D and n.get("items") != null: pack = n
	check(pack != null, "pack spawned")
	if pack:
		var p2 = ex2.player
		p2.global_position = pack.global_position
		await frames(3)
		p2.get_node("InteractArea").get_overlapping_areas()  # sanity
		pack.interact(p2)
		check(p2.total_items() == 12, "pack returned items within limit: %d" % p2.total_items())
		check(pack.items.is_empty() or p2.capacity_left() == 0, "pack consumed or full")
	# terrain steps never exceed 1 tile
	var maxstep := 0
	for i in range(1, ex2.COLS): maxstep = maxi(maxstep, absi(ex2.surface_rows[i] - ex2.surface_rows[i-1]))
	check(maxstep <= 1, "max terrain step %d" % maxstep)
	quit(1 if fails > 0 else 0)
