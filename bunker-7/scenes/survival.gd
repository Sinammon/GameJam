class_name Survival
extends RefCounted
# Hunger and thirst (V3). Two "fullness" meters, 0..100 (100 = not hungry / not thirsty).
# Outside they drain every second (DRAIN x the GameState multiplier: difficulty, Iron Gut).
# At 0 a meter drains health: 1 half-heart every STARVE_EVERY seconds ("hunger" / "thirst").
# The values live in GameState (water_meter / food_meter) between trips: the expedition
# reads them at the start (GSBridge.meters()) and reports them back before banking or dying.
# Also the one place for what eating / drinking each item does (CONSUMABLES), used outside
# (expedition.consume) and in the bunker (GameState.consume_stock).

signal starving_tick(meter: String)   # take STARVE_DAMAGE now; meter "water" or "food"
signal low(meter: String)             # crossed LOW_AT going down (once per crossing)

# Tuning (see V2_NOTES.md, V3 section)
const MAX := 100.0
const LOW_AT := 25.0
const START := 80.0                    # meters on a new game
const DRAIN := {"water": 0.3, "food": 0.2}   # per second outside on Normal (x multiplier): ~5.5 / ~8 min from full
const STARVE_EVERY := 4.0              # s per half-heart while a meter is empty
const STARVE_DAMAGE := 1
const NIGHT_BURN := 25.0               # what a night costs each meter, before the evening meal
const REASON := {"water": "thirst", "food": "hunger"}

# What one of each does. meter: which meter fills, gain: how much. rad: radiation % added
# (outside only). sick: chance of SICK_DAMAGE half-hearts ("sickness"). heal: half-hearts healed.
const CONSUMABLES := {
	"water":       {"meter": "water", "gain": 50.0},
	"dirty_water": {"meter": "water", "gain": 25.0, "rad": 6.0, "sick": 0.3},
	"food":        {"meter": "food", "gain": 50.0},
	"canned_food": {"meter": "food", "gain": 50.0},
	"raw_meat":    {"meter": "food", "gain": 20.0, "sick": 0.4},
	"mushroom":    {"meter": "food", "gain": 12.0, "sick": 0.15},
	"bandage":     {"heal": 3},
}
const SICK_DAMAGE := 1
# Q eats / R drinks the best thing carried, in this order (safest first).
const EAT_ORDER := ["food", "canned_food", "mushroom", "raw_meat"]
const DRINK_ORDER := ["water", "dirty_water"]
const EAT_KEY := KEY_Q
const DRINK_KEY := KEY_R

var water := MAX
var food := MAX
var _starve_left := {"water": 0.0, "food": 0.0}
var _low_warned := {"water": false, "food": false}

# Input actions "eat" (Q) and "drink" (R), added at runtime when the project doesn't define them.
static func ensure_actions() -> void:
	for pair in [["eat", EAT_KEY], ["drink", DRINK_KEY]]:
		if InputMap.has_action(pair[0]):
			continue
		InputMap.add_action(pair[0])
		var e := InputEventKey.new()
		e.physical_keycode = pair[1]
		InputMap.action_add_event(pair[0], e)

func setup(water_value: float, food_value: float) -> void:
	water = clampf(water_value, 0.0, MAX)
	food = clampf(food_value, 0.0, MAX)
	for m in ["water", "food"]:
		_low_warned[m] = get_meter(m) < LOW_AT

func get_meter(meter: String) -> float:
	return water if meter == "water" else food

func set_meter(meter: String, v: float) -> void:
	v = clampf(v, 0.0, MAX)
	if meter == "water":
		water = v
	else:
		food = v
	if v >= LOW_AT + 5.0:
		_low_warned[meter] = false

func add(meter: String, amount: float) -> void:
	set_meter(meter, get_meter(meter) + amount)

# mult: {"water": x, "food": y} drain multipliers (GSBridge.meter_drain()).
func tick(delta: float, mult: Dictionary) -> void:
	for m in ["water", "food"]:
		var v := maxf(0.0, get_meter(m) - float(DRAIN[m]) * float(mult.get(m, 1.0)) * delta)
		if m == "water":
			water = v
		else:
			food = v
		if v < LOW_AT and not _low_warned[m]:
			_low_warned[m] = true
			low.emit(m)
		if v <= 0.0:
			_starve_left[m] -= delta
			if _starve_left[m] <= 0.0:
				_starve_left[m] += STARVE_EVERY
				starving_tick.emit(m)
		else:
			_starve_left[m] = 0.0

# Best carried item for "eat" / "drink" ("" = nothing carried). items: the player's items.
static func best(order: Array, items: Dictionary) -> String:
	for k in order:
		if int(items.get(k, 0)) > 0:
			return k
	return ""

static func is_consumable(kind: String) -> bool:
	return CONSUMABLES.has(kind)
