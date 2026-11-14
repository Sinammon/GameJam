extends Node
# GameState: the whole game's data. Registered as the "GameState" autoload.
# Coder 1's expedition reads/calls the functions in the "CONTRACT" section.
# Don't rename those without telling Coder 1.

signal changed   # UI listens to this and redraws

const ITEM_KINDS := ["wood", "concrete", "scrap", "circuits"]
const MAX_DAY := 7
const MAX_HEALTH := 10

enum Difficulty { EASY, NORMAL, HARD }

# Numbers from GAME_PLAN.md section 4.
const SETTINGS := {
	Difficulty.EASY:   {"name": "Easy",   "bounces": 5, "water": 8, "food": 8, "water_need": 1, "food_need": 1, "rad": 0.7, "loot": 1.3,  "event": 0.20},
	Difficulty.NORMAL: {"name": "Normal", "bounces": 3, "water": 5, "food": 5, "water_need": 1, "food_need": 1, "rad": 1.0, "loot": 1.0,  "event": 0.35},
	Difficulty.HARD:   {"name": "Hard",   "bounces": 2, "water": 3, "food": 3, "water_need": 2, "food_need": 1, "rad": 1.5, "loot": 0.75, "event": 0.55},
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
	"door":     {"name": "Reinforced Door",   "room": "bedroom", "cost": {"wood": 4, "scrap": 2}, "desc": "Raiders can't break in"},
	"purifier": {"name": "Water Purifier",    "room": "utility", "cost": {"scrap": 6}, "desc": "+2 water every night"},
	"filter":   {"name": "Air Filter",        "room": "utility", "cost": {"scrap": 5}, "desc": "Radiation builds 25% slower outside"},
	"garden":   {"name": "Hydroponic Garden", "room": "garden",  "cost": {"wood": 5, "scrap": 3}, "desc": "+1 food every night"},
	"radio":    {"name": "Radio Beacon",      "room": "radio",   "cost": {"scrap": 10}, "desc": "Calls the convoy: needed to be rescued"},
}

const SCARS := {
	"thick_skin": {"name": "Thick Skin",      "desc": "-20% radiation"},
	"scavenger":  {"name": "Scavenger's Eye", "desc": "+1 loot per crate"},
	"light_feet": {"name": "Light Feet",      "desc": "+10% speed"},
	"iron_gut":   {"name": "Iron Gut",        "desc": "need 1 less water a day"},
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
var unlocked_rooms: Array[String] = ["bedroom"]
var built: Dictionary = {}               # {"purifier": true}
var scars: Array[String] = []
var last_stand_pack: Dictionary = {}     # {} or {"items": {...}, "position": Vector2}
var damaged_rooms: Array[String] = []    # a damaged room's buildings don't work until repaired

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
	unlocked_rooms = ["bedroom"]
	built = {}
	scars = []
	last_stand_pack = {}
	damaged_rooms = []
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
	go_to("res://scenes/morning.tscn")

# Change scene safely: if a scene doesn't exist yet (still being built), use the fallback.
func go_to(path: String, fallback: String = "res://scenes/morning.tscn") -> void:
	var target := path if ResourceLoader.exists(path) else fallback
	get_tree().change_scene_to_file.call_deferred(target)

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
	return (16 if is_room_unlocked("storage") else 12) + (2 if has_scar("steady") else 0)

func get_move_speed_bonus() -> float:
	return 0.1 if has_scar("light_feet") else 0.0

func get_dig_speed_bonus() -> float:
	return 0.0   # no digging in the game (Steady Hands gives carry space instead)

func has_air_filter() -> bool:
	return is_working("filter")

func has_reinforced_door() -> bool:
	return is_working("door")

# {} or {"items": {wood, concrete, scrap, circuits}, "position": Vector2}
func get_last_stand_pack() -> Dictionary:
	return last_stand_pack.duplicate(true)

# ---------------------------------------------------------------- CONTRACT: call
# The expedition calls this when the player returns alive to the hatch.
func bank_loot(items: Dictionary) -> void:
	for kind in ITEM_KINDS:
		add_item(kind, int(items.get(kind, 0)))
	last_stand_pack = {}   # the old pack is only for one expedition
	_clear_day_flags()     # storm / bonus crate were for this expedition only
	changed.emit()
	go_to("res://scenes/bunker.tscn")

# The expedition calls this when radiation reaches 100%.
func player_died(items: Dictionary, position: Vector2) -> void:
	var clean := {}
	for kind in ITEM_KINDS:
		clean[kind] = int(items.get(kind, 0))
	last_stand_pack = {"items": clean, "position": position}
	_pending_notes = ["You died outside. You wake up on your cot.", "Lost 1 bounce. Your pack lies where you fell."]
	_lose_bounce(true)

# ---------------------------------------------------------------- night
# Flow: bunker Sleep (or morning "Wait inside", or after a scar pick) -> sleep()
#   -> upkeep (purifier, garden, eat, drink) -> maybe collapse (lose a bounce, scar pick)
#   -> day + 1 -> ending (after day 7) / night event / overnight summary -> morning.
const STAT_KEYS := ["water", "food", "health", "wood", "concrete", "scrap", "circuits"]

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

func _night_upkeep() -> void:
	if is_working("purifier"):
		water += 2
	if is_working("garden"):
		food += 1
	var water_need := int(settings.water_need)
	if has_scar("iron_gut"):
		water_need = maxi(0, water_need - 1)
	var missing := 0
	if water < water_need:
		missing += 1
	water = maxi(0, water - water_need)
	if food < int(settings.food_need):
		missing += 1
	food = maxi(0, food - int(settings.food_need))
	if missing > 0:
		health -= 2 * missing
		_night_notes.append("Not enough to eat or drink.")

func _end_night() -> void:
	day += 1
	changed.emit()
	if day > MAX_DAY:
		go_to("res://scenes/ending.tscn", "res://scenes/main_menu.tscn")
		return
	current_event = {}
	if rng.randf() < float(settings.event):
		current_event = pick_event()
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
			changes.append("%+d %s" % [d, k])
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

func pick_event() -> Dictionary:
	var events := load_events()
	if events.is_empty():
		return {}
	return events[rng.randi_range(0, events.size() - 1)]

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
			"wood", "concrete", "scrap", "circuits", "water", "food":
				add_item(k, int(v))
			"health":
				health = clampi(health + int(v), 1, MAX_HEALTH)
			"skip_expedition":
				skip_expedition = bool(v)
			"rad_mult":
				tomorrow_rad_mult = maxf(0.1, float(v))
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
		and can_afford(BUILDINGS[id].cost)

func build(id: String) -> bool:
	if not can_build(id) or not pay(BUILDINGS[id].cost):
		return false
	built[id] = true
	changed.emit()
	return true

func can_repair(id: String) -> bool:
	return is_room_damaged(id) and can_afford(REPAIR_COST)

func repair_room(id: String) -> bool:
	if not can_repair(id) or not pay(REPAIR_COST):
		return false
	damaged_rooms.erase(id)
	changed.emit()
	return true

func buildings_in(room: String) -> Array[String]:
	var out: Array[String] = []
	for id in BUILDINGS:
		if BUILDINGS[id].room == room:
			out.append(id)
	return out

func get_item(kind: String) -> int:
	return int(get(kind))

func add_item(kind: String, amount: int) -> void:
	if kind in ITEM_KINDS or kind == "water" or kind == "food":
		set(kind, maxi(0, get_item(kind) + amount))

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
	for kind in ITEM_KINDS:
		if cost.has(kind):
			parts.append("%d %s" % [int(cost[kind]), kind])
	return ", ".join(parts)

# ---------------------------------------------------------------- test cheats
# Debug builds only (running from the editor). F2/7 materials, F3/8 skip day, F4/9 bounce.
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
			changed.emit()
		KEY_F3, KEY_8:
			day = mini(day + 1, MAX_DAY)
			changed.emit()
		KEY_F4, KEY_9:
			bounces += 1
			changed.emit()
