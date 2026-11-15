extends Node
# Places zombies by zone and keeps them cheap:
# - spawn slots per zone and side: few in the suburb, more at the market, most at
#   the depot, times a day factor (GSBridge.day()); none closer than
#   SPAWN_MIN_DIST to the hatch (the safe zone is SAFE_RADIUS = 6 tiles).
# - a slot only turns into a zombie when it is off-screen but near the player
#   (SPAWN_NEAR..SPAWN_FAR px away), with at most CAP alive near the player.
# - zombies far off-screen (DESPAWN_DIST) are removed and their slot waits again;
#   a killed zombie's slot comes back after RESPAWN_TIME.

signal first_seen   # a zombie came on screen for the first time this expedition

const ZOMBIE_SCENE := "res://actors/zombie.tscn"

# Tuning (see V2_NOTES.md)
const PER_AREA := [2, 4, 6]       # slots per side: suburb, market, depot (day 1)
const DAY_GROWTH := 0.2           # +20% slots per day after the first
const MAX_DAY_FACTOR := 2.0
const SAFE_RADIUS := 96.0         # 6 tiles around the hatch: zombies never walk in
const SPAWN_MIN_DIST := 224.0     # 14 tiles: no slot closer to the hatch than this
const SPAWN_NEAR := 260.0         # off-screen (half a screen is 240 px)
const SPAWN_FAR := 560.0
const DESPAWN_DIST := 820.0
const CAP := 8                    # alive within SPAWN_FAR of the player
const RESPAWN_TIME := 40.0
const CHECK_EVERY := 0.5

var ex: Node2D = null             # the expedition
var slots: Array = []             # each: {"x": float, "zombie": Node or null, "wait": float}
var enabled := true
var _check_left := 0.0
var _seen := false
var _scene: PackedScene
var variant := "normal"           # V3: zombie look/strength for the location (actors/zombie.gd VARIANTS)

func setup(expedition: Node2D) -> void:
	ex = expedition
	_scene = load(ZOMBIE_SCENE)
	var day_factor := minf(1.0 + DAY_GROWTH * (GSBridge.day() - 1), MAX_DAY_FACTOR) * GSBridge.zombie_multiplier()
	# V3: per-location numbers and look (scenes/locations.gd "zombies"); the surface keeps PER_AREA
	var zcfg: Dictionary = ex.loc.get("zombies", {}) if "loc" in ex else {}
	var per_area: Array = zcfg.get("per_area", PER_AREA)
	variant = str(zcfg.get("variant", "normal"))
	var area_px: float = float(ex.AREA_COLS) * 16.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for side in [-1.0, 1.0]:
		for area in 3:
			var n := roundi(float(per_area[area]) * day_factor)
			# area columns: AREA_COLS per area (50 on the surface), measured from the hatch
			var from: float = maxf(area * area_px, SPAWN_MIN_DIST)
			var to: float = (area + 1) * area_px - 16.0
			if from >= to:
				continue
			for i in n:
				var x: float = ex.HATCH_X + side * rng.randf_range(from, to)
				slots.append({"x": clampf(x, 24.0, ex.WORLD_W - 24.0), "zombie": null, "wait": 0.0})

func alive() -> Array:
	return get_tree().get_nodes_in_group("zombies").filter(func(z: Node) -> bool: return not z.is_dead())

func alive_near(px: float) -> int:
	return alive().filter(func(z: Node) -> bool: return absf(z.global_position.x - px) < SPAWN_FAR).size()

func _process(delta: float) -> void:
	if ex == null or ex.ended:
		return
	_check_first_seen()
	_check_left -= delta
	for s in slots:
		s["wait"] = maxf(0.0, s["wait"] - delta)
	if _check_left > 0.0 or not enabled:
		return
	_check_left = CHECK_EVERY
	var px: float = ex.player.global_position.x
	for z in alive():   # despawn far ones (their slot waits for the player again)
		if absf(z.global_position.x - px) > DESPAWN_DIST:
			for s in slots:
				if s["zombie"] == z:
					s["zombie"] = null
			z.remove_from_group("zombies")
			z.queue_free()
	var near := alive_near(px)
	for s in slots:
		if near >= CAP:
			break
		if s["zombie"] != null and is_instance_valid(s["zombie"]):
			continue
		var d := absf(float(s["x"]) - px)
		if s["wait"] > 0.0 or d < SPAWN_NEAR or d > SPAWN_FAR:
			continue
		spawn_at(s["x"], s)
		near += 1

# Spawns one zombie standing on the ground at x (also used by tests).
func spawn_at(x: float, slot: Variant = null) -> Node:
	if absf(x - ex.HATCH_X) < SAFE_RADIUS:
		return null   # never inside the safe zone
	var z: CharacterBody2D = _scene.instantiate()
	z.position = Vector2(x, ex.floor_y(x) - 1.0)
	z.setup(ex.player, ex.HATCH_X, SAFE_RADIUS, ex.floor_y, GSBridge.loot_multiplier())
	z.variant = variant
	ex.add_child(z)
	if slot is Dictionary:
		slot["zombie"] = z
		z.died.connect(func(_z: Node) -> void:
			slot["zombie"] = null
			slot["wait"] = RESPAWN_TIME)
	return z

func _check_first_seen() -> void:
	if _seen:
		return
	var px: float = ex.player.global_position.x
	for z in alive():
		if absf(z.global_position.x - px) < 230.0:
			_seen = true
			first_seen.emit()
			return
