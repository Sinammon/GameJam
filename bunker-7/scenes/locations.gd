class_name Locations
extends RefCounted
# The places you can go from the bunker ladder (V3). Pure data: scenes/expedition.gd reads one
# config and builds the level from it; GameState checks the unlock day; the field guide lists them.
# Add a location by adding an entry here (and its art, all optional: missing files fall back to
# tinted surface art and drawn placeholders, so real art can drop in later by file name).
#
# Keys:
#   name, desc            shown at the ladder (destination popup) and in the field guide
#   unlock_day            first day it can be picked
#   cols, hatch_col       world width in 16 px columns; the exit sits at hatch_col (the middle)
#   base_row, hills       flat ground row and [column offset from the exit, half width, height] hills
#   ceiling               0 = open sky, else the tunnel height in tiles (unbreakable rock above, a mine)
#   rad                   radiation multiplier on top of GameState's (difficulty, Thick Skin, storms, filter)
#   ambient, min_light    dusk colour at the exit, and the darkest the ambient may get (lighting)
#   dark_dist             how much darker it gets towards the edges (0..1)
#   zone_tint             3 tints: near / middle / far third
#   sky                   clear colour behind everything (when there is no backdrop art)
#   bg_tint               modulate for the reused surface parallax art ("" art = no parallax)
#   ground_tint           modulate for the ground tiles (reused tiles_outside.png until real art exists)
#   trees                 dead trees (wood) on the near and middle thirds
#   crate_xs | crates     fixed crate x positions (px), or a crate count spread from near to far
#   loot                  crate contents: weights for wood/concrete/scrap, count [min, max], and the
#                         chance per crate of circuits (far crates only), water, canned_food, bandage, radio_part
#   guaranteed            {kind: n} put into the farthest crate (the radio part in the crater)
#   ores                  {} = surface ores (mining.gd defaults), else {"chance": x, "rocks": p, "areas": [{kind: weight} x3]}
#                         rocks = chance a floor block is an exposed ore rock you can mine at once
#   zombies               {"per_area": [near, mid, far] per side, "variant": "normal" | "cave" | "crater"}
#   critters              rats per side (hit them for raw meat)
#   sources               [[kind, count per side, area_from, area_to], ...]: puddle, barrel, water_pool, mushroom
#   decor                 [[name, every_n_cols], ...] props (art/world_clean/<name>.png or a drawn placeholder)
#   exit                  "hatch" | "rope" | "ladder": what the way home looks like
#   art                   optional art names: backdrop (one wide picture), exit

const ORDER := ["surface", "mine", "crater"]

const LOCATIONS := {
	"surface": {
		"name": "Surface Ruins", "unlock_day": 1,
		"desc": "The ruined town around the hatch. Dead trees for wood, crates, puddles and barrels of dirty water, rats. Radiation rises the farther you go.",
		"cols": 300, "hatch_col": 150, "base_row": 14,
		"hills": [[25, 9, 2], [60, 12, 3], [92, 8, 2], [120, 14, 3], [142, 6, 1],
			[-30, 8, 2], [-62, 12, 3], [-95, 9, 2], [-118, 13, 3], [-140, 6, 1]],
		"ceiling": 0, "rad": 1.0,
		"ambient": Color(0.86, 0.8, 0.9), "min_light": 0.35, "dark_dist": 0.42,
		"zone_tint": [Color(1.0, 0.92, 0.82), Color(0.96, 0.96, 1.0), Color(0.82, 1.0, 0.8)],
		"sky": Color(0.35, 0.4, 0.38), "bg_tint": Color(1, 1, 1), "ground_tint": Color(1, 1, 1),
		"trees": true,
		"crate_xs": [2640, 2140, 2910, 1860, 3240, 1520, 3560, 1180, 3900, 820, 4230, 520, 4520, 250, 58, 4758],
		"loot": {"weights": {"wood": 1.0, "concrete": 1.0, "scrap": 1.0}, "count": [2, 4],
			"circuits": 0.35, "water": 0.25, "canned_food": 0.2, "bandage": 0.1, "radio_part": 0.0},
		"ores": {},
		"zombies": {"per_area": [2, 4, 6], "variant": "normal"},
		"critters": 3,
		"sources": [["puddle", 3, 0, 1], ["barrel", 2, 1, 2]],
		"decor": [],
		"exit": "hatch",
		"art": {},
	},
	"mine": {
		"name": "Old Mine", "unlock_day": 2,
		"desc": "A dark tunnel under the hills. Low radiation, but bring the flashlight. Ore rocks (pickaxe) for scrap, concrete and circuits, mushrooms, dripping pools of dirty water, cave zombies. Climb the rope to go home.",
		"cols": 200, "hatch_col": 100, "base_row": 14,
		"hills": [[22, 6, 1], [44, 8, 2], [70, 6, 1], [88, 5, 2], [-20, 5, 1], [-46, 9, 2], [-72, 6, 2], [-90, 5, 1]],
		"ceiling": 7, "rad": 0.35,
		"ambient": Color(0.34, 0.31, 0.36), "min_light": 0.16, "dark_dist": 0.35,
		"zone_tint": [Color(1.0, 0.9, 0.8), Color(0.9, 0.92, 1.0), Color(0.85, 1.0, 0.85)],
		"sky": Color(0.07, 0.06, 0.07), "bg_tint": Color(0.22, 0.2, 0.24), "ground_tint": Color(0.62, 0.56, 0.6),
		"trees": false,
		"crates": 6,
		"loot": {"weights": {"wood": 0.8, "concrete": 1.3, "scrap": 1.4}, "count": [2, 3],
			"circuits": 0.35, "water": 0.1, "canned_food": 0.12, "bandage": 0.08, "radio_part": 0.0},
		"ores": {"chance": 2.4, "rocks": 0.16, "areas": [
			{"scrap_ore": 4.0, "concrete": 4.0, "bones": 1.0, "pipe": 1.0},
			{"scrap_ore": 4.0, "concrete": 3.0, "circuits": 2.0, "pipe": 1.0},
			{"scrap_ore": 3.0, "concrete": 3.0, "circuits": 3.0, "toxic": 1.0}]},
		"zombies": {"per_area": [1, 2, 3], "variant": "cave"},
		"critters": 3,
		"sources": [["water_pool", 3, 0, 2], ["mushroom", 5, 0, 2]],
		"decor": [["obj_mine_support", 12], ["obj_mine_lamp", 20], ["obj_mine_cart", 45]],
		"exit": "rope",
		"art": {"backdrop": "bg_mine", "exit": "obj_mine_exit"},
	},
	"crater": {
		"name": "Bomb Crater", "unlock_day": 4,
		"desc": "Where the bomb hit. Glowing ground and very high radiation: build the Air Filter first and keep trips short. The best loot: circuits, supply crates and the Radio Part the beacon needs. Tougher glowing zombies.",
		"cols": 140, "hatch_col": 70, "base_row": 15,
		"hills": [[30, 10, 2], [56, 10, 4], [-30, 9, 2], [-56, 10, 4], [12, 3, 1], [-14, 3, 1]],
		"ceiling": 0, "rad": 2.0,
		"ambient": Color(0.74, 0.88, 0.62), "min_light": 0.3, "dark_dist": 0.3,
		"zone_tint": [Color(0.95, 1.0, 0.85), Color(0.85, 1.0, 0.75), Color(0.75, 1.0, 0.6)],
		"sky": Color(0.3, 0.38, 0.22), "bg_tint": Color(0.62, 0.85, 0.5), "ground_tint": Color(0.78, 0.95, 0.62),
		"trees": false,
		"crates": 8,
		"loot": {"weights": {"wood": 0.3, "concrete": 0.8, "scrap": 1.6}, "count": [3, 4],
			"circuits": 0.6, "water": 0.15, "canned_food": 0.25, "bandage": 0.15, "radio_part": 0.12},
		"guaranteed": {"radio_part": 1},
		"ores": {"chance": 1.6, "rocks": 0.08, "areas": [
			{"scrap_ore": 3.0, "toxic": 3.0, "concrete": 1.0},
			{"scrap_ore": 3.0, "toxic": 2.0, "circuits": 2.0},
			{"scrap_ore": 2.0, "toxic": 2.0, "circuits": 3.0}]},
		"zombies": {"per_area": [1, 2, 3], "variant": "crater"},
		"critters": 0,
		"sources": [["puddle", 2, 0, 1]],
		"decor": [["obj_girder", 18], ["obj_car_wreck", 31], ["obj_crater_crystal", 13]],
		"exit": "ladder",
		"art": {"backdrop": "bg_crater", "exit": "obj_crater_exit"},
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
