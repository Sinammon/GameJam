class_name DayPlan
extends RefCounted
# The week's structure (V3): one goal a day (shown in the morning banner, the bunker's top
# bar and the expedition HUD) and simple escalating threats. Pure data; GameState checks the
# goals (check_goal) and applies the threats (storms in the morning, hordes at night).
#
# goal     short text           check   what completes it (see GameState.goal_met):
#            {"banked": {kind: n}}    brought home today (all trips of the day, one per day)
#            {"built": id}            the building exists (and works)
#            {"cooked": n}            stove recipes cooked today
#            {"survive": true}        never "done" during the day: surviving the night is the goal
# reward   stock added once when the goal is met
# storm    radiation multiplier outside today (0 = none)
# zombies  zombie slot multiplier outside today
# night    forced night event id (data/events.json) after sleeping on this day ("" = random as before)
# note     extra morning line

const DAYS := {
	1: {"goal": "Bring home 8 scrap.", "check": {"banked": {"scrap": 8}}, "reward": {"water": 2},
		"storm": 0.0, "zombies": 1.0, "night": "",
		"note": "Find dirty water outside (puddles, barrels, buckets). Drink it only if you must."},
	2: {"goal": "Bring home 2 circuits (the Old Mine is rich in them).", "check": {"banked": {"circuits": 2}},
		"reward": {"food": 2}, "storm": 0.0, "zombies": 1.0, "night": "",
		"note": "The Old Mine is open: choose it at the ladder. Take the flashlight."},
	3: {"goal": "Fix up the Water Filter (Utility Room).", "check": {"built": "purifier"}, "reward": {"bandage": 1},
		"storm": 1.5, "zombies": 1.0, "night": "",
		"note": "First storm: radiation builds 50% faster outside today."},
	4: {"goal": "Cook a meal on the Stove (Utility Room).", "check": {"cooked": 1}, "reward": {"water": 2},
		"storm": 0.0, "zombies": 1.5, "night": "",
		"note": "The Bomb Crater is open. The dead are restless today: more zombies outside."},
	5: {"goal": "Bring home a Radio Part from the Bomb Crater.", "check": {"banked": {"radio_part": 1}},
		"reward": {"food": 2}, "storm": 0.0, "zombies": 1.3, "night": "horde",
		"note": "Something big is moving out there. Expect visitors at the hatch tonight."},
	6: {"goal": "Build the Radio Beacon (Radio Room).", "check": {"built": "radio"}, "reward": {"water": 2},
		"storm": 1.8, "zombies": 1.3, "night": "",
		"note": "Heavy storm: radiation builds 80% faster outside today."},
	7: {"goal": "Hold out one more night. Keep the beacon working.", "check": {"survive": true}, "reward": {},
		"storm": 0.0, "zombies": 1.5, "night": "",
		"note": "Last day. The horde will come for the hatch tonight: a Reinforced Door helps."},
}
# The last night's horde (night 7) is resolved during the night without a card (GameState._final_horde).
const FINAL_HORDE_DAY := 7
const FINAL_HORDE_LOSS := {"food": 2}
const FINAL_HORDE_HEALTH := 2

static func get_day(d: int) -> Dictionary:
	return DAYS.get(d, {})

static func goal_text(d: int) -> String:
	return str(get_day(d).get("goal", ""))
