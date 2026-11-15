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
		"note": "Puddles and barrels outside hold dirty water (E). Drink it only if you must: filter or boil it first."},
	2: {"goal": "Bring home 2 circuits.", "check": {"banked": {"circuits": 2}},
		"reward": {"food": 2}, "storm": 0.0, "zombies": 1.0, "night": "",
		"note": "The Old Mine is open: pick it at the ladder. Take the flashlight (hotbar 3)."},
	3: {"goal": "Build the Water Filter (Utility Room).", "check": {"built": "purifier"}, "reward": {"bandage": 1},
		"storm": 1.5, "zombies": 1.0, "night": "",
		"note": "Storm day: radiation builds 50% faster outside today."},
	4: {"goal": "Cook a meal on the Stove (Utility Room).", "check": {"cooked": 1}, "reward": {"water": 2},
		"storm": 0.0, "zombies": 1.3, "night": "",
		"note": "The Bomb Crater is open. The Radio Part for the beacon lies there."},
	5: {"goal": "Bring home the Radio Part from the Bomb Crater.", "check": {"banked": {"radio_part": 1}},
		"reward": {"food": 2}, "storm": 0.0, "zombies": 1.3, "night": "horde",
		"note": "A horde is gathering. Tonight it comes for the hatch: a Reinforced Door holds it."},
	6: {"goal": "Build the Radio Beacon (Radio Room).", "check": {"built": "radio"}, "reward": {"water": 2},
		"storm": 0.0, "zombies": 1.3, "night": "",
		"note": "The convoy listens for beacons. Build it before the last night."},
	7: {"goal": "Hold out one more night. Keep the beacon working.", "check": {"survive": true}, "reward": {},
		"storm": 0.0, "zombies": 1.5, "night": "",
		"note": "Last day. Sleep at the cot tonight and wait for the convoy."},
}

static func get_day(d: int) -> Dictionary:
	return DAYS.get(d, {})

static func goal_text(d: int) -> String:
	return str(get_day(d).get("goal", ""))

static func note_text(d: int) -> String:
	return str(get_day(d).get("note", ""))
