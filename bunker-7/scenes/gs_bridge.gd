class_name GSBridge
extends RefCounted
# Safe access to Coder 2's GameState autoload for the expedition.
# Every call checks has_method first, so a missing or renamed function in
# game_state.gd logs one warning and uses a default instead of crashing.
# Values are also type-checked (int/float mix-ups, bad pack data).

# water/food were added later (scavenging for Hard); V3 adds the survival supplies and the radio part.
const ITEM_KINDS := ["wood", "concrete", "scrap", "circuits", "water", "food",
	"dirty_water", "raw_meat", "mushroom", "canned_food", "bandage", "radio_part"]

static var _warned := {}

static func _gs() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("GameState")

static func _warn_once(method: String) -> void:
	if _warned.has(method):
		return
	_warned[method] = true
	push_warning("GameState.%s() is missing; the expedition uses a default / skips the call." % method)

static func has(method: String) -> bool:
	var gs := _gs()
	return gs != null and gs.has_method(method)

static func _call(method: String, args: Array = []) -> Variant:
	if not has(method):
		_warn_once(method)
		return null
	return _gs().callv(method, args)

static func _num(method: String, default: float) -> float:
	var v: Variant = _call(method)
	if v is float or v is int:
		return float(v)
	return default

static func _flag(method: String) -> bool:
	var v: Variant = _call(method)
	return v is bool and v

# --- READ ---
static func radiation_multiplier() -> float:
	return maxf(0.0, _num("get_radiation_multiplier", 1.0))

static func loot_multiplier() -> float:
	return maxf(0.0, _num("get_loot_multiplier", 1.0))

static func carry_limit() -> int:
	return maxi(1, int(_num("get_carry_limit", 12)))

static func move_speed_bonus() -> float:
	return clampf(_num("get_move_speed_bonus", 0.0), -0.9, 5.0)

static func dig_speed_bonus() -> float:
	return _num("get_dig_speed_bonus", 0.0)

static func has_air_filter() -> bool:
	return _flag("has_air_filter")

static func has_reinforced_door() -> bool:
	return _flag("has_reinforced_door")

# V2, optional (C2 may add these later; quiet defaults until then).
# Backpack tier 1..4 (12/16/20/24 slots).
static func backpack_tier() -> int:
	if not has("get_backpack_tier"):
		return 1
	return clampi(int(_num("get_backpack_tier", 1)), 1, 4)

# Player hit points in half-hearts (10 = 5 hearts).
static func max_health() -> int:
	for m in ["get_max_health", "max_health"]:
		if has(m):
			return clampi(int(_num(m, 10)), 2, 40)
	return 10

# Current day (1..), for zombie numbers. get_day() if it exists, else the `day`
# variable, else 1. Quiet (no warning) when missing.
static func day() -> int:
	var gs := _gs()
	if gs == null:
		return 1
	var v: Variant = gs.call("get_day") if gs.has_method("get_day") else gs.get("day")
	if v is int or v is float:
		return clampi(int(v), 1, 99)
	return 1

# --- V3, optional (quiet defaults when GameState doesn't have them) ---
static func _opt(method: String, default: Variant) -> Variant:
	if not has(method):
		return default
	var v: Variant = _gs().call(method)
	return v if typeof(v) == typeof(default) else default

# Where this trip goes (Locations id).
static func location() -> String:
	var v: Variant = _opt("get_location", "surface")
	return v if Locations.has(v) else "surface"

# {"water": 0..100, "food": 0..100} thirst/hunger meters at the start of the trip.
static func meters() -> Dictionary:
	var m: Dictionary = _opt("get_meters", {})
	return {"water": float(m.get("water", Survival.START)), "food": float(m.get("food", Survival.START))}

static func meter_drain() -> Dictionary:
	var m: Dictionary = _opt("get_meter_drain", {})
	return {"water": float(m.get("water", 1.0)), "food": float(m.get("food", 1.0))}

# Supplies packed in the locker for this trip (they start in the backpack).
static func trip_supplies() -> Dictionary:
	return clean_items(_opt("get_trip_supplies", {}))

static func zombie_multiplier() -> float:
	return clampf(float(_opt("get_zombie_multiplier", 1.0)), 0.0, 4.0)

static func goal_text() -> String:
	return str(_opt("get_goal_text", ""))

# Reported right before bank_loot / player_died (not an ending call).
static func set_meters(water: float, food: float) -> void:
	if has("set_meters"):
		_gs().call("set_meters", water, food)

# Always returns {} or {"items": {ITEM_KINDS: int}, "position": Vector2, "location": id?}.
# A pack with nothing in it, or with garbage data, counts as no pack.
static func last_stand_pack() -> Dictionary:
	var v: Variant = _call("get_last_stand_pack")
	if not (v is Dictionary) or not v.has("items") or not (v["items"] is Dictionary):
		return {}
	var items := clean_items(v["items"])
	var total := 0
	for k in items:
		total += items[k]
	if total <= 0:
		return {}
	var pos: Variant = v.get("position", null)
	if pos is Vector2i:
		pos = Vector2(pos)
	var out := {"items": items}
	if v.get("location") is String:
		out["location"] = v["location"]
	if pos is Vector2:
		out["position"] = pos   # else the caller picks a default spot
	return out

# Only the contract keys (ITEM_KINDS), as non-negative ints.
static func clean_items(src: Dictionary) -> Dictionary:
	var out := {}
	for k in ITEM_KINDS:
		var n: Variant = src.get(k, 0)
		out[k] = maxi(0, int(n)) if (n is int or n is float) else 0
	return out

# --- CALL ---
static func bank_loot(items: Dictionary) -> void:
	_call("bank_loot", [clean_items(items)])

static func player_died(items: Dictionary, position: Vector2) -> void:
	_call("player_died", [clean_items(items), position])   # contract unchanged (reason stays local)
