extends Node
# GameState: the whole game's data. Registered as the "GameState" autoload.
# Coder 1's expedition reads/calls the functions in the "CONTRACT" section.
# Don't rename those without telling Coder 1.

signal changed   # UI listens to this and redraws

const ITEM_KINDS := ["wood", "concrete", "scrap", "circuits"]   # building materials
# V3 survival stock (scenes/survival.gd): water = clean water, food = ready meals (cooked food and
# canned food), plus raw supplies to filter / cook, bandages and the radio part for the beacon.
const SUPPLY_KINDS := ["water", "food", "dirty_water", "raw_meat", "mushroom", "bandage", "radio_part"]
const STOCK_KINDS := ["wood", "concrete", "scrap", "circuits", "water", "food", "dirty_water", "raw_meat", "mushroom", "bandage", "radio_part"]
# What the expedition can carry home / leave in the pack (canned food is banked as food).
const LOOT_KINDS := ["wood", "concrete", "scrap", "circuits", "water", "food",
	"dirty_water", "raw_meat", "mushroom", "canned_food", "bandage", "radio_part"]
const STOCK_ALIAS := {"canned_food": "food"}
# Taken outside from the locker (counts toward the carry limit, comes back when banked).
const PACKABLE := ["water", "food", "bandage"]
const MAX_DAY := 7
const MAX_HEALTH := 10

enum Difficulty { EASY, NORMAL, HARD }

# Numbers from GAME_PLAN.md section 4. V3: drain = hunger/thirst speed outside (Survival.DRAIN x this).
const SETTINGS := {
	Difficulty.EASY:   {"name": "Easy",   "bounces": 5, "water": 8, "food": 8, "water_need": 1, "food_need": 1, "rad": 0.7, "loot": 1.3,  "event": 0.20, "drain": 0.75},
	Difficulty.NORMAL: {"name": "Normal", "bounces": 3, "water": 5, "food": 5, "water_need": 1, "food_need": 1, "rad": 1.0, "loot": 1.0,  "event": 0.35, "drain": 1.0},
	Difficulty.HARD:   {"name": "Hard",   "bounces": 2, "water": 3, "food": 3, "water_need": 2, "food_need": 1, "rad": 1.5, "loot": 0.75, "event": 0.55, "drain": 1.3},
}

# Rooms and buildings (GAME_PLAN.md section 3.4). Costs use the item keys.
const ROOMS := {
	"bedroom": {"name": "Bedroom",      "cost": {}},
	"utility": {"name": "Utility Room", "cost": {"wood": 6, "concrete": 6}},
	"garden":  {"name": "Garden Room",  "cost": {"wood": 8, "concrete": 4}},
	"storage": {"name": "Storage Room", "cost": {"concrete": 6, "scrap": 4}},
	"radio":   {"name": "Radio Room",   "cost": {"concrete": 8, "scrap": 6, "circuits": 1}},
}
const ROOM_ORDER := ["bedroom", "utility", "garden", "storage", "radio"]

const BUILDINGS := {
	"door":     {"name": "Reinforced Door",   "room": "bedroom", "cost": {"wood": 4, "scrap": 2}, "desc": "Raiders and hordes can't break in"},
	# V3: the old purifier (+2 water a night) is now the Water Filter station (id kept for saves/tests).
	"purifier": {"name": "Water Filter",      "room": "utility", "cost": {"scrap": 4, "concrete": 2, "circuits": 1}, "desc": "Turns dirty water into clean water (E at it; also up to 4 overnight)"},
	"stove":    {"name": "Stove",             "room": "utility", "cost": {"scrap": 3, "concrete": 2}, "desc": "Cooks raw meat and mushrooms into meals, boils water; burns wood"},
	"filter":   {"name": "Air Filter",        "room": "utility", "cost": {"scrap": 5}, "desc": "Radiation builds 25% slower outside"},
	"garden":   {"name": "Hydroponic Garden", "room": "garden",  "cost": {"wood": 5, "scrap": 3}, "desc": "+1 food every night"},
	"radio":    {"name": "Radio Beacon",      "room": "radio",   "cost": {"scrap": 10, "radio_part": 1}, "desc": "Calls the convoy: needed to be rescued"},
}

# Every item: name, where to find it, what it is for (the Crafts / Book screen reads this through
# scenes/guide_data.gd; recipes and costs come from RECIPES / BUILDINGS / ROOMS / BACKPACK_COSTS).
const ITEMS := {
	"wood":        {"name": "Wood",        "where": "Dead trees (axe) on the surface, crates, buried planks.", "use": "Building, rooms, backpacks; fuel for the Stove."},
	"concrete":    {"name": "Concrete",    "where": "Crates, concrete blocks (pickaxe), rich in the Old Mine.", "use": "Rooms and stations."},
	"scrap":       {"name": "Scrap",       "where": "Crates, scrap ore and pipes (pickaxe), zombies.", "use": "Almost every building and upgrade."},
	"circuits":    {"name": "Circuits",    "where": "Far crates, deep circuit veins (Old Mine, Bomb Crater).", "use": "Water Filter, Radio Room, big backpacks."},
	"water":       {"name": "Clean water", "where": "Water Filter or Stove (from dirty water), rare bottles in crates.", "use": "R drinks outside (+50 thirst). One a night."},
	"food":        {"name": "Meal",        "where": "Stove (cook meat or mushrooms), Hydroponic Garden.", "use": "Q eats outside (+50 hunger). One a night."},
	"canned_food": {"name": "Canned food", "where": "Rare in crates.", "use": "Safe food (+50 hunger). Stored as a meal."},
	"dirty_water": {"name": "Dirty water", "where": "Puddles, barrels, mine pools (E).", "use": "Filter or boil it. Drinking it raw: radiation and maybe sickness."},
	"raw_meat":    {"name": "Raw meat",    "where": "Rats (hit them), sometimes zombies.", "use": "Cook it on the Stove. Raw: risky. Half rots every night."},
	"mushroom":    {"name": "Mushroom",    "where": "Old Mine floor (E).", "use": "Stew on the Stove (2 make a meal). Raw: a little food, a little risk."},
	"bandage":     {"name": "Bandage",     "where": "Crates, day goal rewards.", "use": "Medkit slot (5) outside or the locker: heals 3 half-hearts."},
	"radio_part":  {"name": "Radio part",  "where": "The farthest crate in the Bomb Crater.", "use": "Needed to build the Radio Beacon (rescue)."},
}

# Water Filter (station "purifier"): 1 dirty water -> 1 clean water, any time; overnight it
# filters up to FILTER_NIGHT_MAX on its own.
const FILTER_IN := {"dirty_water": 1}
const FILTER_OUT := {"water": 1}
const FILTER_NIGHT_MAX := 4
# Stove recipes (station "stove"): wood is the fuel.
const RECIPES := {
	"cook_meat":     {"name": "Cooked meat",   "in": {"raw_meat": 1, "wood": 1}, "out": {"food": 1}},
	"mushroom_stew": {"name": "Mushroom stew", "in": {"mushroom": 2, "wood": 1}, "out": {"food": 1}},
	"boil_water":    {"name": "Boiled water",  "in": {"dirty_water": 2, "wood": 1}, "out": {"water": 1}},
}
const RAW_MEAT_SPOILS := 0.5   # this share of uncooked raw meat (rounded up) rots every night
const DEATH_MIN_METER := 35.0  # after dying outside you wake up at least this fed and watered

# Backpack tiers 1..4 (upgrade bench in the bunker's bedroom). Carry-limit rule (one place:
# carry_limit_for_tier):  carry = BACKPACK_SLOTS[tier - 1]           (12 / 16 / 20 / 24)
#                               + STORAGE_BONUS if the Storage Room is unlocked   (+4)
#                               + STEADY_BONUS with the Steady Hands scar          (+2)
# So the tiers are the base slots and the room/scar bonuses stack on top (max 24 + 4 + 2 = 30).
# BACKPACK_COSTS[t] = what it costs to go from tier t - 1 to tier t (all backpack costs live here).
const BACKPACK_SLOTS := [12, 16, 20, 24]
const BACKPACK_COSTS := {
	2: {"scrap": 6, "wood": 4},
	3: {"scrap": 10, "concrete": 6, "circuits": 2},
	4: {"scrap": 14, "concrete": 8, "circuits": 4},
}
const STORAGE_BONUS := 4
const STEADY_BONUS := 2
# Seconds between bank_loot and the scene change: the expedition plays the ladder climb + fade meanwhile.
const HATCH_TRANSITION := 0.9

const SCARS := {
	"thick_skin": {"name": "Thick Skin",      "desc": "-20% radiation"},
	"scavenger":  {"name": "Scavenger's Eye", "desc": "+1 loot per crate"},
	"light_feet": {"name": "Light Feet",      "desc": "+10% speed"},
	"iron_gut":   {"name": "Iron Gut",        "desc": "thirst 25% slower, 1 less water a night"},
	"steady":     {"name": "Steady Hands",    "desc": "carry 2 more items"},   # no digging in the game
}

# --- Game state ---
var difficulty: int = Difficulty.NORMAL
var settings: Dictionary = SETTINGS[Difficulty.NORMAL]
var day := 1
var bounces := 3
var health := MAX_HEALTH
var water := 5
var food := 5
var wood := 0
var concrete := 0
var scrap := 0
var circuits := 0
var dirty_water := 0
var raw_meat := 0
var mushroom := 0
var bandage := 0
var radio_part := 0
var water_meter := Survival.START          # 0..100 thirst meter (100 = not thirsty)
var food_meter := Survival.START           # 0..100 hunger meter
var packed: Dictionary = {}                # locker -> backpack for the next trip {kind: n}
var trip_supplies: Dictionary = {}         # what this trip started with (read by the expedition)
var current_location := "surface"          # where today's trip goes (Locations)
var today: Dictionary = {}                 # goal progress today: {"banked": {kind: n}, "cooked": n}
var goal_done := false                     # today's DayPlan goal is met (reward given)
var goal_message := ""                     # one line for the bunker banner when a goal was just met
var unlocked_rooms: Array[String] = ["bedroom"]
var built: Dictionary = {}               # {"purifier": true}
var scars: Array[String] = []
var last_stand_pack: Dictionary = {}     # {} or {"items": {...}, "position": Vector2}
var damaged_rooms: Array[String] = []    # a damaged room's buildings don't work until repaired
var backpack_tier := 1                   # 1..4, see BACKPACK_SLOTS
var went_outside := false                # true once today's expedition started (one per day)
var bunker_arrival := "cot"              # where the walkable bunker puts you: "cot" (new day) or "hatch" (back from outside)
var show_tutorial := false               # true right after start_game: the bunker opens the slideshow (first time only)
var last_banked: Dictionary = {}         # what the last bank_loot added (the bunker shows it on arrival)

# One-day flags set by night events (used from Stage 4).
var skip_expedition := false
var tomorrow_rad_mult := 1.0
var bonus_crate := false

func _ready() -> void:
	settings = SETTINGS[difficulty]

# ---------------------------------------------------------------- new game
func start_game(d: int) -> void:
	difficulty = d
	settings = SETTINGS[d]
	day = 1
	bounces = int(settings.bounces)
	health = MAX_HEALTH
	water = int(settings.water)
	food = int(settings.food)
	wood = 0
	concrete = 0
	scrap = 0
	circuits = 0
	dirty_water = 0
	raw_meat = 0
	mushroom = 0
	bandage = 0
	radio_part = 0
	water_meter = Survival.START
	food_meter = Survival.START
	packed = {}
	trip_supplies = {}
	current_location = "surface"
	today = {}
	goal_done = false
	goal_message = ""
	unlocked_rooms = ["bedroom"]
	built = {}
	scars = []
	last_stand_pack = {}
	damaged_rooms = []
	backpack_tier = 1
	went_outside = false
	bunker_arrival = "cot"
	show_tutorial = true
	last_banked = {}
	current_event = {}
	last_night_summary = []
	_pending_notes = []
	_sleep_after_scar = false
	_awaiting_scar = false
	_night_before = {}
	_night_notes = []
	skip_expedition = false
	tomorrow_rad_mult = 1.0
	bonus_crate = false
	changed.emit()
	go_to(BUNKER)

const BUNKER := "res://scenes/bunker.tscn"
const EXPEDITION := "res://scenes/expedition.tscn"

# Change scene safely: if a scene doesn't exist yet (still being built), use the fallback.
# delay > 0: change after that many seconds (lets the old scene finish an animation).
func go_to(path: String, fallback: String = "res://scenes/morning.tscn", delay: float = 0.0) -> void:
	var target := path if ResourceLoader.exists(path) else fallback
	if delay <= 0.0:
		get_tree().change_scene_to_file.call_deferred(target)
		return
	await get_tree().create_timer(delay).timeout
	get_tree().change_scene_to_file(target)

# A new day starts in the walkable bunker, at the cot (overnight summary "Continue").
func start_day() -> void:
	bunker_arrival = "cot"
	go_to(BUNKER)

# "" if the player may climb up and go outside now, else the reason to show.
# location: also checks that this destination is open today ("" = any).
func go_outside_block(location := "") -> String:
	if skip_expedition:
		return "Radiation storm outside. Stay in: sleep at the cot."
	if went_outside:
		return "It's getting dark. Sleep at the cot first."
	if location != "":
		return location_lock_text(location)
	return ""

# Bunker ladder (or the morning screen): start today's expedition to `location`. One per day.
# Packed supplies leave the locker now (trip_supplies; the expedition starts carrying them).
func go_outside(location := "surface") -> bool:
	if not Locations.has(location) or go_outside_block(location) != "":
		return false
	went_outside = true
	current_location = location
	trip_supplies = packed.duplicate()
	packed = {}
	changed.emit()
	go_to(EXPEDITION)
	return true

# ---------------------------------------------------------------- V3: locations
func is_location_unlocked(id: String) -> bool:
	return Locations.has(id) and day >= Locations.unlock_day(id)

# "" when open today, else why not ("Opens on day 4.").
func location_lock_text(id: String) -> String:
	if not Locations.has(id):
		return "Unknown place."
	if not is_location_unlocked(id):
		return "Opens on day %d." % Locations.unlock_day(id)
	return ""

func get_location() -> String:
	return current_location

# Ids in ladder order: [[id, unlocked], ...]
func destinations() -> Array:
	var out := []
	for id in Locations.ORDER:
		out.append([id, is_location_unlocked(id)])
	return out

# ---------------------------------------------------------------- CONTRACT: read
func get_radiation_multiplier() -> float:
	var m: float = float(settings.rad) * tomorrow_rad_mult
	if has_scar("thick_skin"):
		m *= 0.8
	if has_air_filter():   # the expedition has no overnight radiation, so the filter slows it outside
		m *= 0.75
	return m

func get_loot_multiplier() -> float:
	var m: float = float(settings.loot)
	if has_scar("scavenger"):
		m *= 1.33   # crates give 2-4 items, so +1 per crate is about +33%
	if bonus_crate:   # stranger's supplies: the expedition has no extra crate, so crates are fuller
		m *= 1.5
	return m

func get_carry_limit() -> int:
	return carry_limit_for_tier(get_backpack_tier())

# The carry-limit rule (see BACKPACK_SLOTS): tier slots + storage room bonus + Steady Hands bonus.
func carry_limit_for_tier(tier: int) -> int:
	return int(BACKPACK_SLOTS[clampi(tier, 1, BACKPACK_SLOTS.size()) - 1]) \
		+ (STORAGE_BONUS if is_room_unlocked("storage") else 0) + (STEADY_BONUS if has_scar("steady") else 0)

func get_backpack_tier() -> int:
	return clampi(backpack_tier, 1, BACKPACK_SLOTS.size())

func get_day() -> int:
	return day

func max_health() -> int:
	return MAX_HEALTH

func get_move_speed_bonus() -> float:
	return 0.1 if has_scar("light_feet") else 0.0

# V3 survival contract (read by the expedition through GSBridge; all optional there).
# {"water": 0..100, "food": 0..100} at the start of a trip.
func get_meters() -> Dictionary:
	return {"water": water_meter, "food": food_meter}

# Drain multipliers outside: difficulty, Iron Gut (thirst x0.75).
func get_meter_drain() -> Dictionary:
	var d := float(settings.get("drain", 1.0))
	return {"water": d * (0.75 if has_scar("iron_gut") else 1.0), "food": d}

# The expedition reports the meters right before bank_loot / player_died.
func set_meters(water_value: float, food_value: float) -> void:
	water_meter = clampf(water_value, 0.0, Survival.MAX)
	food_meter = clampf(food_value, 0.0, Survival.MAX)

# What this trip started carrying (packed in the locker).
func get_trip_supplies() -> Dictionary:
	return trip_supplies.duplicate()

# Zombie slot multiplier today (DayPlan threat).
func get_zombie_multiplier() -> float:
	return float(DayPlan.get_day(day).get("zombies", 1.0))

# Today's goal line for HUDs ("" = none), with a tick when done.
func get_goal_text() -> String:
	var g := DayPlan.goal_text(day)
	if g == "":
		return ""
	return ("Done: " if goal_done else "Goal: ") + g

func get_dig_speed_bonus() -> float:
	return 0.0   # no digging in the game (Steady Hands gives carry space instead)

func has_air_filter() -> bool:
	return is_working("filter")

func has_reinforced_door() -> bool:
	return is_working("door")

# {} or {"items": {wood, concrete, scrap, circuits, water, food}, "position": Vector2}
func get_last_stand_pack() -> Dictionary:
	return last_stand_pack.duplicate(true)

# ---------------------------------------------------------------- CONTRACT: call
# The expedition calls this when the player returns alive to the hatch.
func bank_loot(items: Dictionary) -> void:
	last_banked = {}
	var got: Dictionary = today.get("banked", {})
	for kind in LOOT_KINDS:
		var n := maxi(0, int(items.get(kind, 0)))
		add_item(kind, n)
		if n > 0:
			last_banked[kind] = n
			got[kind] = int(got.get(kind, 0)) + n
	today["banked"] = got
	last_stand_pack = {}   # the old pack is only for one expedition
	trip_supplies = {}
	_clear_day_flags()     # storm / bonus crate were for this expedition only
	went_outside = true
	bunker_arrival = "hatch"
	check_goal()
	changed.emit()
	go_to(BUNKER, "res://scenes/morning.tscn", HATCH_TRANSITION)   # the expedition plays the ladder climb meanwhile

# The expedition calls this when health reaches 0 (radiation, zombies, hunger, thirst...).
# The pack remembers where (location) it was dropped: it only lies there on the next trip.
func player_died(items: Dictionary, position: Vector2) -> void:
	var clean := {}
	for kind in LOOT_KINDS:
		clean[kind] = int(items.get(kind, 0))
	last_stand_pack = {"items": clean, "position": position, "location": current_location}
	trip_supplies = {}
	water_meter = maxf(water_meter, DEATH_MIN_METER)
	food_meter = maxf(food_meter, DEATH_MIN_METER)
	_pending_notes = ["You died outside (%s). You wake up on your cot." % Locations.display_name(current_location),
		"Lost 1 bounce. Your pack lies where you fell."]
	_lose_bounce(true)

# ---------------------------------------------------------------- night
# Flow: bunker cot (sleep, or wait_inside when you didn't go out), or after a scar pick -> sleep()
#   -> upkeep (purifier, garden, eat, drink) -> maybe collapse (lose a bounce, scar pick)
#   -> day + 1 -> ending (after day 7) / night event / overnight summary -> start_day() -> bunker at the cot.
# A day: wake at the cot -> ladder up (go_outside) -> expedition -> hatch (bank_loot) -> bunker -> cot.
const STAT_KEYS := ["water", "food", "health", "wood", "concrete", "scrap", "circuits", "dirty_water", "raw_meat", "mushroom", "bandage", "radio_part"]

var rng := RandomNumberGenerator.new()
var current_event: Dictionary = {}             # the event card being shown tonight
var last_night_summary: Array[String] = []     # lines for the overnight screen
var _night_before: Dictionary = {}             # stats when the night started (for the diff)
var _night_notes: Array[String] = []           # story lines for the overnight screen
var _pending_notes: Array[String] = []         # notes from before sleep() (death on the surface)
var _sleep_after_scar := false                 # true: died outside, the night still has to run
var _awaiting_scar := false                    # true between losing a bounce and picking the scar

func seed_rng(value: int) -> void:
	rng.seed = value

func sleep() -> void:
	_night_before = _snapshot()
	_night_notes = _pending_notes.duplicate()
	_pending_notes = []
	_clear_day_flags()   # yesterday's storm / bonus crate are over
	_night_upkeep()
	if health <= 0:
		_night_notes.append("You collapsed from hunger and thirst. Lost 1 bounce.")
		_lose_bounce(false)
		return
	_end_night()

# Morning button when a storm keeps you in: no expedition, no loot, straight to the night.
func wait_inside() -> void:
	_pending_notes.append("You stayed inside all day.")
	sleep()

func night_water_need() -> int:
	return maxi(0, int(settings.water_need) - (1 if has_scar("iron_gut") else 0))

func night_food_need() -> int:
	return int(settings.food_need)

# V3 night: packed supplies go back, garden grows, the Water Filter works off dirty water,
# raw meat rots, the night burns NIGHT_BURN of each meter, then you drink water_need and eat
# food_need from the stock (each refills the meter like drinking/eating it). A meter at 0 after
# that costs 2 health (as the old "missing" rule).
func _night_upkeep() -> void:
	unpack_all()
	if is_working("garden"):
		food += 1
	if is_working("purifier") and dirty_water > 0:
		var n := filter_water(FILTER_NIGHT_MAX)
		if n > 0:
			_night_notes.append("The Water Filter cleaned %d dirty water." % n)
	if raw_meat > 0:
		var rot := ceili(raw_meat * RAW_MEAT_SPOILS)
		raw_meat -= rot
		_night_notes.append("%d raw meat rotted (cook it on the Stove)." % rot)
	water_meter = maxf(0.0, water_meter - Survival.NIGHT_BURN)
	food_meter = maxf(0.0, food_meter - Survival.NIGHT_BURN)
	for i in night_water_need():
		if water > 0:
			water -= 1
			water_meter = minf(Survival.MAX, water_meter + float(Survival.CONSUMABLES.water.gain))
	for i in night_food_need():
		if food > 0:
			food -= 1
			food_meter = minf(Survival.MAX, food_meter + float(Survival.CONSUMABLES.food.gain))
	var missing := 0
	if water_meter <= 0.0:
		missing += 1
	if food_meter <= 0.0:
		missing += 1
	if missing > 0:
		health -= 2 * missing
		_night_notes.append("Not enough to eat or drink.")

func _end_night() -> void:
	day += 1
	went_outside = false
	bunker_arrival = "cot"
	last_banked = {}
	today = {}
	goal_done = false
	goal_message = ""
	changed.emit()
	if day > MAX_DAY:
		go_to("res://scenes/ending.tscn", "res://scenes/main_menu.tscn")
		return
	current_event = {}
	var forced := str(DayPlan.get_day(day - 1).get("night", ""))
	if forced != "":
		current_event = event_by_id(forced)
	elif rng.randf() < float(settings.event):
		current_event = pick_event()
	_apply_day_threats()
	check_goal()   # a goal already met (e.g. the filter built early) counts at once
	if current_event.is_empty():
		show_overnight()
	else:
		go_to("res://scenes/night_event.tscn", "res://scenes/morning.tscn")

func show_overnight() -> void:
	last_night_summary = _night_notes.duplicate()
	var now := _snapshot()
	var changes: PackedStringArray = []
	for k in STAT_KEYS:
		var d: int = int(now[k]) - int(_night_before.get(k, now[k]))
		if d != 0:
			changes.append("%+d %s" % [d, item_name(k)])
	if changes.is_empty():
		last_night_summary.append("Nothing changed.")
	else:
		last_night_summary.append(", ".join(changes))
	changed.emit()
	go_to("res://scenes/overnight.tscn")

func _snapshot() -> Dictionary:
	var out := {}
	for k in STAT_KEYS:
		out[k] = int(get(k))
	return out

func _clear_day_flags() -> void:
	skip_expedition = false
	tomorrow_rad_mult = 1.0
	bonus_crate = false

# ---------------------------------------------------------------- night events
# Events are data: data/events.json (how-to: data/EVENTS_HOWTO.md).
const EVENTS_PATH := "res://data/events.json"

# Returns the list of valid events. A missing or broken file gives [] and a warning (no events).
func load_events() -> Array:
	if not FileAccess.file_exists(EVENTS_PATH):
		push_warning("No %s: night events are off." % EVENTS_PATH)
		return []
	var json := JSON.new()
	var data: Variant = null
	if json.parse(FileAccess.get_file_as_string(EVENTS_PATH)) == OK:
		data = json.data
	if not (data is Dictionary and data.get("events") is Array):
		push_warning("%s is not valid JSON with an \"events\" list: night events are off." % EVENTS_PATH)
		return []
	var out: Array = []
	for e in data.events:
		if e is Dictionary and e.get("title") is String and e.get("options") is Array and e.options.size() >= 1 \
				and e.options.all(func(o): return o is Dictionary and o.get("label") is String):
			out.append(e)
		else:
			push_warning("Skipping a broken event in %s: %s" % [EVENTS_PATH, str(e).left(60)])
	return out

# A random event. Skips "forced_only" ones (scripted by DayPlan) and ones whose "requires"
# stock you don't have (e.g. spoiled meat needs raw meat in the locker).
func pick_event() -> Dictionary:
	var events := load_events().filter(func(e: Dictionary) -> bool:
		return not bool(e.get("forced_only", false)) and (not (e.get("requires") is Dictionary) or can_afford(e.requires)))
	if events.is_empty():
		return {}
	return events[rng.randi_range(0, events.size() - 1)]

# The event with this id ({} if missing).
func event_by_id(id: String) -> Dictionary:
	for e in load_events():
		if str(e.get("id", "")) == id:
			return e
	return {}

func can_choose_option(option: Dictionary) -> bool:
	var cost: Variant = option.get("cost", {})
	return not (cost is Dictionary) or can_afford(cost)

# Applies option `index` of current_event and returns the result line to show.
func choose_event_option(index: int) -> String:
	var options: Array = current_event.get("options", [])
	if index < 0 or index >= options.size() or not can_choose_option(options[index]):
		return ""
	var o: Dictionary = options[index]
	if o.get("cost") is Dictionary:
		pay(o.cost)
	var text: String = str(o.get("text", ""))
	if str(o.get("unless", "")) == "door" and has_reinforced_door():
		text = str(o.get("unless_text", "Your Reinforced Door holds."))
	elif o.get("effects") is Dictionary:
		var extra := apply_effects(o.effects)
		if extra != "":
			text += " " + extra
	_night_notes.append("%s: %s" % [current_event.get("title", "Event"), text])
	current_event = {}
	changed.emit()
	return text

# Applies an effects dictionary. Returns an extra story line (e.g. which room got damaged).
func apply_effects(effects: Dictionary) -> String:
	var extra := ""
	for k in effects:
		var v: Variant = effects[k]
		match k:
			"wood", "concrete", "scrap", "circuits", "water", "food", "dirty_water", "raw_meat", "mushroom", "bandage", "radio_part", "canned_food":
				add_item(k, int(v))
			"water_meter":
				water_meter = clampf(water_meter + float(v), 0.0, Survival.MAX)
			"food_meter":
				food_meter = clampf(food_meter + float(v), 0.0, Survival.MAX)
			"health":
				health = clampi(health + int(v), 1, MAX_HEALTH)
			"skip_expedition":
				skip_expedition = bool(v)
			"rad_mult":
				tomorrow_rad_mult = maxf(tomorrow_rad_mult, maxf(0.1, float(v)))
			"bonus_crate":
				bonus_crate = bool(v)
			"damage_room":
				if bool(v):
					var room := damage_random_room()
					if room != "":
						extra = "The %s is damaged!" % ROOMS[room].name
			"repair_room":
				if bool(v) and not damaged_rooms.is_empty():
					extra = "The %s is repaired." % ROOMS[damaged_rooms[0]].name
					damaged_rooms.remove_at(0)
			_:
				push_warning("Unknown event effect '%s' (ignored)." % k)
	return extra

# Damages a random unlocked, undamaged room that has a building. Returns its id or "".
func damage_random_room() -> String:
	var targets: Array[String] = []
	for id in unlocked_rooms:
		if is_room_damaged(id):
			continue
		for b in buildings_in(id):
			if is_built(b):
				targets.append(id)
				break
	if targets.is_empty():
		return ""
	var room := targets[rng.randi_range(0, targets.size() - 1)]
	damaged_rooms.append(room)
	return room

# ---------------------------------------------------------------- bouncing back
# then_sleep: true when you died outside (the night still has to happen after the scar pick),
# false when you collapsed during the night (the night is already done).
func _lose_bounce(then_sleep: bool) -> void:
	bounces -= 1
	var old_health := health
	health = clampi(maxi(health, 6), 0, MAX_HEALTH)
	# The health reset is not a night "gain": move the summary baseline so it isn't shown as +health.
	if _night_before.has("health"):
		_night_before["health"] = int(_night_before["health"]) + (health - old_health)
	_clear_day_flags()
	changed.emit()
	if bounces <= 0:
		go_to("res://scenes/game_over.tscn", "res://scenes/main_menu.tscn")
		return
	_sleep_after_scar = then_sleep
	_awaiting_scar = true
	if scar_choices().is_empty():
		continue_after_scar()
	else:
		go_to("res://scenes/scar_pick.tscn")

# Up to `count` random scars the player doesn't have yet.
func scar_choices(count: int = 3) -> Array[String]:
	var free: Array[String] = []
	for id in SCARS:
		if not has_scar(id):
			free.append(id)
	for i in range(free.size() - 1, 0, -1):   # shuffle with our own rng (seedable in tests)
		var j := rng.randi_range(0, i)
		var t := free[i]
		free[i] = free[j]
		free[j] = t
	return free.slice(0, count)

func pick_scar(id: String) -> void:
	if not _awaiting_scar:
		return
	if SCARS.has(id) and not has_scar(id):
		scars.append(id)
	continue_after_scar()

func continue_after_scar() -> void:
	if not _awaiting_scar:   # a second click / call must not run the night twice
		return
	_awaiting_scar = false
	if _sleep_after_scar:
		_sleep_after_scar = false
		sleep()
	else:
		_end_night()

# ---------------------------------------------------------------- endings
func is_rescued() -> bool:
	return is_built("radio") and not is_room_damaged("radio")

func bounces_used() -> int:
	return int(settings.bounces) - bounces

func built_names_text() -> String:
	var names: PackedStringArray = ["Cot"]
	for id in BUILDINGS:
		if is_built(id):
			names.append(BUILDINGS[id].name)
	return ", ".join(names)

func scar_names_text() -> String:
	var names: PackedStringArray = []
	for id in scars:
		names.append(SCARS[id].name)
	return "none" if names.is_empty() else ", ".join(names)

# ---------------------------------------------------------------- helpers
func has_scar(id: String) -> bool:
	return scars.has(id)

func is_room_unlocked(id: String) -> bool:
	return unlocked_rooms.has(id)

func is_built(id: String) -> bool:
	return built.has(id)

# Built AND its room is not damaged.
func is_working(id: String) -> bool:
	return is_built(id) and not is_room_damaged(BUILDINGS[id].room)

func is_room_damaged(id: String) -> bool:
	return damaged_rooms.has(id)

# ---------------------------------------------------------------- rooms & building
const REPAIR_COST := {"scrap": 3}

func can_unlock(id: String) -> bool:
	return ROOMS.has(id) and not is_room_unlocked(id) and can_afford(ROOMS[id].cost)

func unlock_room(id: String) -> bool:
	if not can_unlock(id) or not pay(ROOMS[id].cost):
		return false
	unlocked_rooms.append(id)
	changed.emit()
	return true

func can_build(id: String) -> bool:
	return BUILDINGS.has(id) and not is_built(id) and is_room_unlocked(BUILDINGS[id].room) \
		and not is_room_damaged(BUILDINGS[id].room) and can_afford(BUILDINGS[id].cost)

func build(id: String) -> bool:
	if not can_build(id) or not pay(BUILDINGS[id].cost):
		return false
	built[id] = true
	check_goal()
	changed.emit()
	return true

func can_repair(id: String) -> bool:
	return is_room_damaged(id) and can_afford(REPAIR_COST)

func repair_room(id: String) -> bool:
	if not can_repair(id) or not pay(REPAIR_COST):
		return false
	damaged_rooms.erase(id)
	check_goal()
	changed.emit()
	return true

# ---------------------------------------------------------------- backpack
# Cost to reach `tier` (2..4) from the tier below; {} for tier 1 or out of range.
func backpack_upgrade_cost(tier: int) -> Dictionary:
	return (BACKPACK_COSTS.get(tier, {}) as Dictionary).duplicate()

func can_upgrade_backpack() -> bool:
	var next := get_backpack_tier() + 1
	return BACKPACK_COSTS.has(next) and can_afford(BACKPACK_COSTS[next])

# Checks the cost of the next tier, spends it and raises the tier. false at tier 4 or when short.
func upgrade_backpack() -> bool:
	if not can_upgrade_backpack() or not pay(BACKPACK_COSTS[get_backpack_tier() + 1]):
		return false
	backpack_tier = get_backpack_tier() + 1
	changed.emit()
	return true

func buildings_in(room: String) -> Array[String]:
	var out: Array[String] = []
	for id in BUILDINGS:
		if BUILDINGS[id].room == room:
			out.append(id)
	return out

func get_item(kind: String) -> int:
	kind = STOCK_ALIAS.get(kind, kind)
	if not kind in STOCK_KINDS:
		return 0
	return int(get(kind))

func add_item(kind: String, amount: int) -> void:
	kind = STOCK_ALIAS.get(kind, kind)
	if kind in STOCK_KINDS:
		set(kind, maxi(0, get_item(kind) + amount))

# Takes what there is of each (never below 0): losses from events / the horde.
func pay_partial(cost: Dictionary) -> void:
	for kind in cost:
		add_item(kind, -int(cost[kind]))
	changed.emit()

func can_afford(cost: Dictionary) -> bool:
	for kind in cost:
		if get_item(kind) < int(cost[kind]):
			return false
	return true

func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for kind in cost:
		add_item(kind, -int(cost[kind]))
	changed.emit()
	return true

# "6 wood, 6 concrete" for buttons
func cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts: PackedStringArray = []
	for kind in STOCK_KINDS:
		if cost.has(kind):
			parts.append("%d %s" % [int(cost[kind]), item_name(kind)])
	return ", ".join(parts)

# "dirty water", "radio part" (stock ids with spaces).
func item_name(kind: String) -> String:
	return kind.replace("_", " ")

# ---------------------------------------------------------------- V3: water filter, stove, eating in the bunker
func can_filter() -> bool:
	return is_working("purifier") and dirty_water > 0

# Filters up to n dirty water into clean water (1:1). Returns how many.
func filter_water(n := 1) -> int:
	if not is_working("purifier"):
		return 0
	var k := mini(n, dirty_water)
	if k <= 0:
		return 0
	dirty_water -= k
	water += k
	today["filtered"] = int(today.get("filtered", 0)) + k
	check_goal()
	changed.emit()
	return k

func can_cook(id: String) -> bool:
	return RECIPES.has(id) and is_working("stove") and can_afford(RECIPES[id]["in"])

func cook(id: String) -> bool:
	if not can_cook(id) or not pay(RECIPES[id]["in"]):
		return false
	var out: Dictionary = RECIPES[id]["out"]
	for k in out:
		add_item(k, int(out[k]))
	today["cooked"] = int(today.get("cooked", 0)) + 1
	check_goal()
	changed.emit()
	return true

# Eat / drink / use one of the stock in the bunker (water, food, bandage). Raw things are
# cooked first (stove); dirty water is filtered first. False if there is none or no need.
func can_consume_stock(kind: String) -> bool:
	if not kind in ["water", "food", "bandage"] or get_item(kind) <= 0:
		return false
	if kind == "bandage":
		return health < MAX_HEALTH
	return (water_meter if kind == "water" else food_meter) < Survival.MAX - 1.0

func consume_stock(kind: String) -> bool:
	if not can_consume_stock(kind):
		return false
	add_item(kind, -1)
	var c: Dictionary = Survival.CONSUMABLES[kind]
	if c.has("heal"):
		health = mini(MAX_HEALTH, health + int(c.heal))
	elif c.meter == "water":
		water_meter = minf(Survival.MAX, water_meter + float(c.gain))
	else:
		food_meter = minf(Survival.MAX, food_meter + float(c.gain))
	changed.emit()
	return true

# ---------------------------------------------------------------- V3: packing supplies for the trip
func packed_total() -> int:
	var n := 0
	for k in packed:
		n += int(packed[k])
	return n

func can_pack(kind: String) -> bool:
	return kind in PACKABLE and get_item(kind) > 0 and packed_total() < get_carry_limit() and not went_outside

func pack_item(kind: String) -> bool:
	if not can_pack(kind):
		return false
	add_item(kind, -1)
	packed[kind] = int(packed.get(kind, 0)) + 1
	changed.emit()
	return true

func unpack_all() -> void:
	if packed.is_empty():
		return
	for k in packed:
		add_item(k, int(packed[k]))
	packed = {}
	changed.emit()

# ---------------------------------------------------------------- V3: daily goals and threats (DayPlan)
func _apply_day_threats() -> void:
	var storm := float(DayPlan.get_day(day).get("storm", 0.0))
	if storm > 0.0:
		tomorrow_rad_mult = maxf(tomorrow_rad_mult, storm)

# True when a DayPlan goal check passes today.
func goal_met(check: Dictionary) -> bool:
	if check.is_empty() or check.has("survive"):
		return false
	if check.has("banked"):
		var got: Dictionary = today.get("banked", {})
		for k in check.banked:
			if int(got.get(k, 0)) < int(check.banked[k]):
				return false
	if check.has("built") and not is_working(str(check.built)):
		return false
	if check.has("cooked") and int(today.get("cooked", 0)) < int(check.cooked):
		return false
	return true

# Checks today's goal; the first time it passes the reward is added and goal_message is set.
func check_goal() -> bool:
	if goal_done:
		return true
	var plan := DayPlan.get_day(day)
	if plan.is_empty() or not goal_met(plan.get("check", {})):
		return false
	goal_done = true
	var reward: Dictionary = plan.get("reward", {})
	for k in reward:
		add_item(k, int(reward[k]))
	goal_message = "Goal done: %s" % plan.goal
	if not reward.is_empty():
		var parts: PackedStringArray = []
		for k in reward:
			parts.append("+%d %s" % [int(reward[k]), item_name(k)])
		goal_message += " Reward: %s." % ", ".join(parts)
	changed.emit()
	return true

# Progress for the goal ("scrap 3/8"), "" when there is nothing to count.
func goal_progress_text() -> String:
	var check: Dictionary = DayPlan.get_day(day).get("check", {})
	if check.has("banked"):
		var got: Dictionary = today.get("banked", {})
		var parts: PackedStringArray = []
		for k in check.banked:
			parts.append("%s %d/%d" % [item_name(k), mini(int(got.get(k, 0)), int(check.banked[k])), int(check.banked[k])])
		return ", ".join(parts)
	if check.has("cooked"):
		return "cooked %d/%d" % [mini(int(today.get("cooked", 0)), int(check.cooked)), int(check.cooked)]
	return ""

# ---------------------------------------------------------------- test cheats
# Debug builds only (running from the editor). F2/7 materials + raw supplies + the radio part,
# F3/8 skip day, F4/9 bounce.
func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F2, KEY_7:
			for kind in ITEM_KINDS:
				add_item(kind, 10)
			for kind in ["dirty_water", "raw_meat", "mushroom"]:
				add_item(kind, 3)
			radio_part = maxi(radio_part, 1)   # so the Radio Beacon can be tested
			changed.emit()
		KEY_F3, KEY_8:
			day = mini(day + 1, MAX_DAY)
			changed.emit()
		KEY_F4, KEY_9:
			bounces += 1
			changed.emit()
