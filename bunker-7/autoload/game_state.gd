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
	"door":     {"name": "Reinforced Door",   "room": "bedroom", "cost": {"wood": 4, "scrap": 2}},
	"purifier": {"name": "Water Purifier",    "room": "utility", "cost": {"scrap": 6}},
	"filter":   {"name": "Air Filter",        "room": "utility", "cost": {"scrap": 5}},
	"garden":   {"name": "Hydroponic Garden", "room": "garden",  "cost": {"wood": 5, "scrap": 3}},
	"radio":    {"name": "Radio Beacon",      "room": "radio",   "cost": {"scrap": 10}},
}

const SCARS := {
	"thick_skin": {"name": "Thick Skin",      "desc": "-20% radiation"},
	"scavenger":  {"name": "Scavenger's Eye", "desc": "+1 loot per crate"},
	"light_feet": {"name": "Light Feet",      "desc": "+10% speed"},
	"iron_gut":   {"name": "Iron Gut",        "desc": "need 1 less water a day"},
	"steady":     {"name": "Steady Hands",    "desc": "dig 30% faster"},
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
	return m

func get_loot_multiplier() -> float:
	var m: float = float(settings.loot)
	if has_scar("scavenger"):
		m *= 1.33   # crates give 2-4 items, so +1 per crate is about +33%
	return m

func get_carry_limit() -> int:
	return 16 if is_room_unlocked("storage") else 12

func get_move_speed_bonus() -> float:
	return 0.1 if has_scar("light_feet") else 0.0

func get_dig_speed_bonus() -> float:
	return 0.3 if has_scar("steady") else 0.0

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
	changed.emit()
	go_to("res://scenes/bunker.tscn")

# The expedition calls this when radiation reaches 100%.
func player_died(items: Dictionary, position: Vector2) -> void:
	var clean := {}
	for kind in ITEM_KINDS:
		clean[kind] = int(items.get(kind, 0))
	last_stand_pack = {"items": clean, "position": position}
	bounces -= 1
	changed.emit()
	if bounces <= 0:
		go_to("res://scenes/game_over.tscn", "res://scenes/main_menu.tscn")
	else:
		go_to("res://scenes/scar_pick.tscn")

# ---------------------------------------------------------------- night
func sleep() -> void:
	day += 1
	changed.emit()
	go_to("res://scenes/morning.tscn")

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
	if kind in ITEM_KINDS:
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
