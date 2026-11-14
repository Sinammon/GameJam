class_name GSBridge
extends RefCounted
# Safe access to Coder 2's GameState autoload for the expedition.
# Every call checks has_method first, so a missing or renamed function in
# game_state.gd logs one warning and uses a default instead of crashing.
# Values are also type-checked (int/float mix-ups, bad pack data).

const ITEM_KINDS := ["wood", "concrete", "scrap", "circuits"]

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

# Always returns {} or {"items": {wood,concrete,scrap,circuits: int}, "position": Vector2}.
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
	if not (pos is Vector2):
		return {"items": items}   # caller picks a default spot
	return {"items": items, "position": pos}

# Only the four contract keys, as non-negative ints.
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
	_call("player_died", [clean_items(items), position])
