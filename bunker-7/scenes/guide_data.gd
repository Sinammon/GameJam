class_name GuideData
extends RefCounted
# Data for the Crafts / Book screen (scenes/book.gd). Nothing is typed twice: every entry is built
# from the game's own tables, so the book can't go out of date:
#   items      GameState.ITEMS (+ "made at" from FILTER_* / RECIPES, "used for" from BUILDINGS / ROOMS /
#              BACKPACK_COSTS / RECIPES)
#   stations   GameState.BUILDINGS and ROOMS (cost, what it does)
#   recipes    the Water Filter (FILTER_IN/OUT) and GameState.RECIPES (the Stove)
#   backpack   GameState.BACKPACK_SLOTS / BACKPACK_COSTS
#   places     Locations.LOCATIONS
#   tools      Inventory.TOOLS (+ the one-line TOOL_INFO below; tools are not items)
# Each entry: {"name", "where", "use", "recipe"} (empty strings are skipped by the screen).

const SECTIONS := ["Items", "Stations", "Recipes", "Places", "Tools"]
const TOOL_INFO := {
	"axe": "Chops dead trees for wood; weak against zombies.",
	"pickaxe": "Mines ore rocks and blocks (scrap, concrete, circuits); hits zombies hard.",
	"flashlight": "A beam where you face. You need it in the Old Mine.",
	"canteen": "Left click drinks the cleanest water you carry (same as R).",
	"medkit": "Left click uses a bandage: +3 half-hearts.",
}

static func gs() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("GameState") if tree else null

static func sections() -> Dictionary:
	var out := {}
	for s in SECTIONS:
		out[s] = entries(s)
	return out

static func entries(section: String) -> Array:
	var g := gs()
	if g == null:
		return []
	match section:
		"Items":
			return _items(g)
		"Stations":
			return _stations(g)
		"Recipes":
			return _recipes(g)
		"Places":
			return _places()
		"Tools":
			return _tools()
	return []

static func _items(g: Node) -> Array:
	var out: Array = []
	for kind in g.ITEMS:
		var info: Dictionary = g.ITEMS[kind]
		var made: PackedStringArray = []
		if g.FILTER_OUT.has(kind):
			made.append("Water Filter: %s" % g.cost_text(g.FILTER_IN))
		for id in g.RECIPES:
			if g.RECIPES[id]["out"].has(kind):
				made.append("Stove: %s" % g.cost_text(g.RECIPES[id]["in"]))
		var used: PackedStringArray = []
		for id in g.BUILDINGS:
			if g.BUILDINGS[id].cost.has(kind):
				used.append(g.BUILDINGS[id].name)
		for id in g.ROOMS:
			if g.ROOMS[id].cost.has(kind):
				used.append(g.ROOMS[id].name)
		for id in g.RECIPES:
			if g.RECIPES[id]["in"].has(kind):
				used.append(g.RECIPES[id].name)
		for t in g.BACKPACK_COSTS:
			if g.BACKPACK_COSTS[t].has(kind):
				used.append("Backpack %d" % t)
		var use: String = info.use
		if not used.is_empty():
			use += " Needed for: %s." % ", ".join(used)
		out.append({"id": kind, "name": info.name, "where": info.where, "use": use,
			"recipe": " / ".join(made)})
	return out

static func _stations(g: Node) -> Array:
	var out: Array = []
	out.append({"id": "cot", "name": "Cot", "where": "Bedroom", "use": "Sleep: ends the day. The night costs water and a meal.", "recipe": ""})
	out.append({"id": "locker", "name": "Locker", "where": "Bedroom", "use": "Your stock. Eat, drink, bandage, pack supplies for the trip.", "recipe": ""})
	for id in g.ROOM_ORDER:
		var r: Dictionary = g.ROOMS[id]
		if r.cost.is_empty():
			continue
		var builds: PackedStringArray = []
		for b in g.buildings_in(id):
			builds.append(g.BUILDINGS[b].name)
		var use := "Unlock at its door." + (" Lets you build: %s." % ", ".join(builds) if not builds.is_empty() else "")
		if id == "storage":
			use += " +%d carry space." % g.STORAGE_BONUS
		out.append({"id": "room_" + id, "name": r.name, "where": "Room", "use": use, "recipe": g.cost_text(r.cost)})
	for id in g.BUILDINGS:
		var b: Dictionary = g.BUILDINGS[id]
		out.append({"id": id, "name": b.name, "where": "%s workbench" % g.ROOMS[b.room].name, "use": b.desc,
			"recipe": g.cost_text(b.cost)})
	var tiers: PackedStringArray = []
	for t in g.BACKPACK_COSTS:
		tiers.append("tier %d (%d slots): %s" % [t, g.BACKPACK_SLOTS[t - 1], g.cost_text(g.BACKPACK_COSTS[t])])
	out.append({"id": "backpack", "name": "Backpack upgrades", "where": "Upgrade bench, Bedroom",
		"use": "Carry more. Tier 1 carries %d." % g.BACKPACK_SLOTS[0], "recipe": "; ".join(tiers)})
	return out

static func _recipes(g: Node) -> Array:
	var out: Array = []
	out.append({"id": "filter", "name": "Filter water", "where": "Water Filter",
		"use": "Up to %d a night on its own." % g.FILTER_NIGHT_MAX,
		"recipe": "%s -> %s" % [g.cost_text(g.FILTER_IN), g.cost_text(g.FILTER_OUT)]})
	for id in g.RECIPES:
		var r: Dictionary = g.RECIPES[id]
		out.append({"id": id, "name": r.name, "where": "Stove", "use": "",
			"recipe": "%s -> %s" % [g.cost_text(r["in"]), g.cost_text(r["out"])]})
	return out

static func _places() -> Array:
	var out: Array = []
	for id in Locations.ORDER:
		var c: Dictionary = Locations.get_config(id)
		out.append({"id": id, "name": c.name, "where": "Ladder, from day %d" % int(c.unlock_day),
			"use": c.desc, "recipe": "Radiation x%s" % str(c.rad)})
	return out

static func _tools() -> Array:
	var out: Array = []
	var inv: Script = load("res://scenes/inventory.gd")
	var tools: Array = inv.get_script_constant_map().get("TOOLS", [])
	for i in tools.size():
		var t: String = tools[i]
		out.append({"id": t, "name": t.capitalize(), "where": "Hotbar %d" % (i + 1), "use": str(TOOL_INFO.get(t, "")), "recipe": ""})
	out.append({"id": "keys", "name": "Keys", "where": "Outside", "use": "Q eats, R drinks, E uses, Tab backpack, 1-5 tools.", "recipe": ""})
	return out

# Every id listed anywhere in the book (tests check that each item / building is in it).
static func all_ids() -> Array:
	var ids: Array = []
	for s in SECTIONS:
		for e in entries(s):
			ids.append(e.id)
	return ids
