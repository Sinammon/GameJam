class_name Locations
extends RefCounted
# The places you can go from the bunker ladder (V3). Pure data: the expedition builder
# (scenes/expedition.gd) reads one config and builds the level from it, GameState checks the
# unlock day. Add a location by adding an entry here (and its art, all optional).
#
# Keys (all required unless marked optional):
#   name, desc            shown at the ladder (destination popup) and in the field guide
#   unlock_day            first day it can be picked
#   cols                  world width in 16 px columns; the exit is at hatch_col (the middle)
#   base_row, hills       flat ground row and [column offset from the exit, half width, height] hills
#   ceiling               0 = open sky, else the tunnel height in tiles (rock above it, a mine)
#   rad                   radiation multiplier on top of GameState's (difficulty, Thick Skin, storms, air filter)
#   ambient, min_light    dusk colour at the exit, and the darkest the ambient may get (Lighting.min_brightness)
#   dark_dist             how much darker it gets towards the edges (0..1)
#   zone_tint             3 tints: near / middle / far third
#   trees                 dead trees (wood) on the near and middle thirds
#   crate_xs | crates     fixed crate x positions (px), or a crate count spread from near to far
#   loot                  crate contents: weights for wood/concrete/scrap, count [min, max], and chances
#                         per crate for circuits (far third only on the surface), canned_food, bandage, radio_part
#   guaranteed            optional: {kind: n} put into the farthest crate on one side (the radio part)
#   ores                  {} = surface ores (mining.gd defaults), else {"chance": x, "rocks": p, "areas": [{kind: weight} x3]}
#   zombies               {"per_area": [near, mid, far] per side, "variant": "normal" | "cave" | "crater"}
#   critters              {"rat": n, "bat": n}
#   sources               [[kind, count, area_from, area_to], ...]: puddle, barrel, bucket, water_pool, mushroom
#   decor                 [[art, every_n_cols or count, ...]] non-interactive props (see location_dressing.gd)
#   exit                  "hatch" | "rope" | "ladder": what the way home looks like
#   art                   tile/backdrop/exit/crate names (art/world_clean/<name>.png), every one optional

const ORDER := ["surface", "mine", "crater"]

const LOCATIONS := {
	"surface": {
		"name": "Surface Ruins", "unlock_day": 1,
		"desc": "The ruined town around the hatch. Wood from dead trees, crates with materials, puddles and rusty barrels of dirty water. Radiation rises the farther you go.",
		"cols": 300, "hatch_col": 150, "base_row": 14,
		"hills": [[25, 9, 2], [60, 12, 3], [92, 8, 2], [120, 14, 3], [142, 6, 1],
			[-30, 8, 2], [-62, 12, 3], [-95, 9, 2], [-118, 13, 3], [-140, 6, 1]],
		"ceiling": 0,
		"rad": 1.0,
		"ambient": Color(0.86, 0.8, 0.9), "min_light": 0.35, "dark_dist": 0.42,
		"zone_tint": [Color(1.0, 0.92, 0.82), Color(0.96, 0.96, 1.0), Color(0.82, 1.0, 0.8)],
		"trees": true,
		"crate_xs": [2640, 2140, 2910, 1860, 3240, 1520, 3560, 1180, 3900, 820, 4230, 520, 4520, 250, 58, 4758],
		"loot": {"weights": {"wood": 1.0, "concrete": 1.0, "scrap": 1.0}, "count": [2, 4],
			"circuits": 0.35, "canned_food": 0.15, "bandage": 0.1, "radio_part": 0.0},
		"ores": {},
		"zombies": {"per_area": [2, 4, 6], "variant": "normal"},
		"critters": {"rat": 4, "bat": 0},
		"sources": [["bucket", 3, 0, 0], ["puddle", 6, 0, 1], ["barrel", 4, 1, 2], ["mushroom", 2, 0, 1]],
		"decor": [],
		"exit": "hatch",
		"art": {},
	},
	"mine": {
		"name": "Old Mine", "unlock_day": 2,
		"desc": "A dark, tight tunnel under the hills. Low radiation, but you need your light. Rich in scrap, concrete and circuits in the rock (pickaxe), mushrooms and dripping pools of dirty water. Bats and cave zombies.",
		"cols": 200, "hatch_col": 100, "base_row": 14,
		"hills": [[22, 6, 1], [44, 8, 2], [70, 6, 1], [88, 5, 2], [-20, 5, 1], [-46, 9, 2], [-72, 6, 2], [-90, 5, 1]],
		"ceiling": 7,
		"rad": 0.3,
		"ambient": Color(0.3, 0.28, 0.33), "min_light": 0.13, "dark_dist": 0.35,
		"zone_tint": [Color(1.0, 0.9, 0.8), Color(0.9, 0.92, 1.0), Color(0.85, 1.0, 0.85)],
		"trees": false,
		"crates": 6,
		"loot": {"weights": {"wood": 0.6, "concrete": 1.3, "scrap": 1.4}, "count": [2, 3],
			"circuits": 0.3, "canned_food": 0.12, "bandage": 0.08, "radio_part": 0.0},
		"ores": {"chance": 2.4, "rocks": 0.14, "areas": [
			{"scrap_ore": 4.0, "concrete": 4.0, "bones": 1.0, "pipe": 1.0},
			{"scrap_ore": 4.0, "concrete": 3.0, "circuits": 2.0, "pipe": 1.0},
			{"scrap_ore": 3.0, "concrete": 3.0, "circuits": 3.0, "toxic": 1.0}]},
		"zombies": {"per_area": [1, 2, 3], "variant": "cave"},
		"critters": {"rat": 3, "bat": 6},
		"sources": [["water_pool", 6, 0, 2], ["mushroom", 10, 0, 2]],
		"decor": [["obj_mine_support", 14], ["obj_mine_cart", 3], ["obj_mine_lamp", 22]],
		"exit": "rope",
		"art": {"backdrop": "bg_mine", "surface": "tile_mine_floor", "under": "tile_mine_wall",
			"ceiling": "tile_mine_ceiling", "exit": "obj_mine_exit", "crate": ""},
		"ground_tint": Color(0.62, 0.58, 0.6),
	},
	"crater": {
		"name": "Bomb Crater", "unlock_day": 4,
		"desc": "Where the bomb hit. Glowing green ground and very high radiation: go with the Air Filter built, and keep trips short. The best loot: circuits, supply crates and the Radio Part the beacon needs. Tougher zombies with glowing eyes.",
		"cols": 140, "hatch_col": 70, "base_row": 15,
		"hills": [[30, 10, 2], [58, 12, 5], [-30, 9, 2], [-58, 12, 5], [12, 3, 1], [-14, 3, 1]],
		"ceiling": 0,
		"rad": 2.4,
		"ambient": Color(0.72, 0.86, 0.62), "min_light": 0.3, "dark_dist": 0.3,
		"zone_tint": [Color(0.95, 1.0, 0.85), Color(0.85, 1.0, 0.75), Color(0.75, 1.0, 0.6)],
		"trees": false,
		"crates": 8,
		"loot": {"weights": {"wood": 0.3, "concrete": 0.8, "scrap": 1.6}, "count": [2, 4],
			"circuits": 0.6, "canned_food": 0.2, "bandage": 0.15, "radio_part": 0.12},
		"guaranteed": {"radio_part": 1},
		"ores": {"chance": 1.6, "rocks": 0.08, "areas": [
			{"scrap_ore": 3.0, "toxic": 3.0, "concrete": 1.0},
			{"scrap_ore": 3.0, "toxic": 2.0, "circuits": 2.0},
			{"scrap_ore": 2.0, "toxic": 2.0, "circuits": 3.0}]},
		"zombies": {"per_area": [1, 2, 3], "variant": "crater"},
		"critters": {"rat": 0, "bat": 0},
		"sources": [["puddle", 3, 0, 1]],
		"decor": [["obj_girder", 4], ["obj_car_wreck", 3], ["obj_ash_pile", 6], ["obj_crater_crystal", 5], ["obj_bomb_shell", 1]],
		"exit": "ladder",
		"art": {"backdrop": "bg_crater", "surface": "tile_crater_ground", "under": "tile_crater_under",
			"exit": "obj_crater_exit", "crate": "obj_supply_crate"},
		"ground_tint": Color(0.8, 1.0, 0.72),
	},
}

static func has(id: String) -> bool:
	return LOCATIONS.has(id)

# The config of `id`, or the surface for an unknown id.
static func get_config(id: String) -> Dictionary:
	return LOCATIONS.get(id, LOCATIONS["surface"])

static func unlock_day(id: String) -> int:
	return int(get_config(id).get("unlock_day", 1))

static func display_name(id: String) -> String:
	return str(get_config(id).get("name", id))
