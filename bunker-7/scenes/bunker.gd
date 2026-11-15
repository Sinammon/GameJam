extends Node2D
# The walkable bunker: a side-view cutaway you walk through (A/D, E to use things, Esc pause).
#
#   sky + surface (hatch, ladder top)                 y 0 .. SURFACE_Y
#   packed dirt with the ladder shaft down the middle  .. ROOM_Y
#   [garden][storage][BEDROOM][utility][radio]        ROOM_Y .. ROOM_Y + ROOM_H (feet on FLOOR_Y)
#
# The shaft comes down into the bedroom where its picture has the ladder painted (SHAFT_IN_ROOM).
# Rooms sit side by side; the seam between two rooms is a door that belongs to the room farther
# from the bedroom. A locked room is dark behind a boarded door (obj_door_locked) and blocks the
# way, so on each side rooms open in order (left: storage then garden, right: utility then radio).
#
# Stations (walk up, a world-space "E label" prompt shows, press E):
#   ladder (foot of the shaft): climb up -> GameState.go_outside() -> expedition
#   cot: sleep popup (GameState.sleep / wait_inside)     calendar: day popup
#   locker: stock popup                                    upgrade bench: backpack tiers
#   workbench (one per unlocked room with buildings): build / repair popup
#   locked door: unlock popup
#   V3: Water Filter (dirty -> clean water) and Stove (cook / boil) once built in the Utility Room;
#   the locker also eats / drinks / bandages and packs supplies for the trip; the ladder asks
#   where to go once the Old Mine / Bomb Crater are open (GameState.go_outside(location)).
# All rules live in GameState; this scene only calls can_* / build / unlock_room / repair_room /
# upgrade_backpack / sleep / go_outside and redraws on GameState.changed.
# Arrival (GameState.bunker_arrival): "hatch" = climb down the shaft from the surface (after
# bank_loot), "cot" = wake up at the cot (new day, Day 1). Every texture is optional (placeholders).

const WalkerScript := preload("res://scenes/bunker_walker.gd")
const PopupScript := preload("res://scenes/bunker_popup.gd")
const PAUSE_MENU := "res://scenes/pause_menu.tscn"
const LIGHTING := "res://scenes/lighting.gd"
const ART := "res://art/world_clean/%s.png"

# --- Layout (px) ----------------------------------------------------------------------
const ROOM_W := 234
const ROOM_H := 78
const ROOM_ORDER := ["garden", "storage", "bedroom", "utility", "radio"]   # left -> right
const HOME := "bedroom"
const MARGIN := 40                 # dirt left and right of the rooms
const SURFACE_Y := 72              # ground line outside
const ROOM_Y := 160                # top of the room pictures
const FLOOR_Y := ROOM_Y + 66       # where feet and buildings stand
const WALL := 14                   # walker stops this far inside a room's outer wall
const SHAFT_IN_ROOM := 39          # ladder x inside the bedroom picture
const SHAFT_HALF := 14             # inner half width of the shaft
const VIEW := Vector2(480, 270)
const WORLD_W := MARGIN * 2 + ROOM_W * 5
const REACH := 15.0                # px from a station's x that counts as "at it"
const DOOR_STAND := 18             # door station: this far inside the reachable room from the seam

# Station x inside its room (centre), per room. Buildings stand at BUILD_X.
const STATION_X := {
	"bedroom": {"calendar": 66, "cot": 98, "locker": 128, "workbench": 156, "upgrade": 199},
	"utility": {"workbench": 46},
	"garden": {"workbench": 50},
	"radio": {"workbench": 52},
}
const BUILD_X := {"purifier": 96, "stove": 142, "filter": 192, "garden": 132, "radio": 120}
# Art tried in order for a building (V3 station art from bunker_stations2 first, has-file fallback).
const BUILD_ART := {"purifier": ["obj_water_filter", "bld_purifier"], "stove": ["obj_stove", "bld_stove"]}
# ... and the picture in front of those while it works: the filter with water in it, the stove's fire.
const BUILD_ART_ON := {"purifier": "obj_water_filter_on", "stove": "obj_stove_lit"}
const SHELF_X := {"utility": 168}   # a pantry shelf (obj_shelf, scenery) between the stove and the air filter
const LAMP_X := {"bedroom": 88, "utility": 117, "garden": 117, "storage": 76, "radio": 78}   # painted lamps
const ROOM_COLORS := {
	"bedroom": Color(0.30, 0.24, 0.20), "utility": Color(0.22, 0.27, 0.30), "garden": Color(0.20, 0.30, 0.20),
	"storage": Color(0.29, 0.27, 0.20), "radio": Color(0.26, 0.21, 0.30),
}
const BUILDING_COLORS := {
	"cot": Color(0.55, 0.40, 0.30), "door": Color(0.50, 0.50, 0.55), "purifier": Color(0.30, 0.55, 0.80),
	"filter": Color(0.60, 0.65, 0.65), "garden": Color(0.35, 0.70, 0.35), "radio": Color(0.85, 0.55, 0.25),
	"stove": Color(0.30, 0.28, 0.27),
}
const STATION_LABEL := {
	"ladder": "Climb up", "cot": "Sleep", "calendar": "Calendar", "locker": "Stock",
	"upgrade": "Backpack", "workbench": "Build", "door": "Unlock",
	"purifier": "Filter water", "stove": "Cook",
}

# --- Look ------------------------------------------------------------------------------
const AMBIENT := Color(0.42, 0.40, 0.46)          # dark bunker; lamps make the warm pools
const LAMP_COLOR := Color(1.0, 0.78, 0.45)
const LOCKED_TINT := Color(0.45, 0.42, 0.42)
const BANNER_TIME := 4.5
const FADE_TIME := 0.45

var walker: Node2D
var camera: Camera2D
var lighting: Node = null
var pause_menu: Node = null
var popup: CanvasLayer = null
var popup_kind := ""               # "", "cot", "workbench:<room>", "door:<room>", ...
var stations: Array = []           # [{kind, x, room}]
var near: Dictionary = {}          # the station in reach ({} = none)
var busy := false                  # climbing / fading / sleeping: no input
var tutorial: Node = null

var _rooms: Node2D                 # rebuilt on GameState.changed
var _prompt_layer: CanvasLayer
var _prompt: Node2D
var _prompt_label: Label
var _hud_layer: CanvasLayer
var _hud_row: Control = null
var _goal_label: Label
var _banner: PanelContainer
var _banner_label: Label
var _banner_left := 0.0
var _fade: ColorRect
var _slept := false
var _light_script: Script = null

func _ready() -> void:
	busy = true   # until _arrive() has placed the survivor (no prompts / hints before that)
	_load_lighting()
	_build_static()
	_add_door_lamps()
	_rooms = Node2D.new()
	_rooms.name = "Rooms"
	add_child(_rooms)
	walker = WalkerScript.new()
	walker.name = "Walker"
	add_child(walker)
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.limit_left = 0
	camera.limit_right = WORLD_W
	camera.limit_top = 0
	camera.limit_bottom = int(VIEW.y)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	_build_overlays()
	_rebuild()
	if GameState.has_signal("changed"):
		GameState.changed.connect(_rebuild)
	if ResourceLoader.exists(PAUSE_MENU):
		pause_menu = load(PAUSE_MENU).instantiate()
		add_child(pause_menu)
	_setup_lighting()
	_arrive()

# ---------------------------------------------------------------- layout helpers
static func room_x(id: String) -> float:
	return MARGIN + ROOM_ORDER.find(id) * ROOM_W

static func shaft_x() -> float:
	return room_x(HOME) + SHAFT_IN_ROOM

func station_x(kind: String, room := HOME) -> float:
	for s in stations:
		if s.kind == kind and s.room == room:
			return s.x
	return -1.0

# Rooms you can walk into: the bedroom, then outwards while the next room is unlocked.
func reach_range() -> Vector2i:
	var home := ROOM_ORDER.find(HOME)
	var lo := home
	while lo > 0 and GameState.is_room_unlocked(ROOM_ORDER[lo - 1]):
		lo -= 1
	var hi := home
	while hi < ROOM_ORDER.size() - 1 and GameState.is_room_unlocked(ROOM_ORDER[hi + 1]):
		hi += 1
	return Vector2i(lo, hi)

# ---------------------------------------------------------------- static world
func _tex(file: String) -> Texture2D:
	return Art.texture(ART % file)

func _rect(parent: Node, r: Rect2, c: Color, z := 0) -> ColorRect:
	var n := ColorRect.new()
	n.position = r.position
	n.size = r.size
	n.color = c
	n.z_index = z
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(n)
	return n

# A texture repeated over a rect (or a flat colour when it is missing).
func _tiled(parent: Node, file: String, r: Rect2, fallback: Color, tint := Color.WHITE) -> CanvasItem:
	var t := _tex(file)
	if t == null:
		return _rect(parent, r, fallback)
	var s := Sprite2D.new()
	s.texture = t
	s.centered = false
	s.position = r.position
	s.region_enabled = true
	s.region_rect = Rect2(Vector2.ZERO, r.size)
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.modulate = tint
	parent.add_child(s)
	return s

# Sprite with its bottom-centre at `foot` (null when the art is missing).
func _put(parent: Node, file: String, foot: Vector2, flip := false) -> Sprite2D:
	var t := _tex(file)
	if t == null:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.centered = false
	s.position = foot.floor()
	s.offset = Vector2(-floorf(t.get_width() / 2.0), -t.get_height())
	s.flip_h = flip
	parent.add_child(s)
	return s

func _build_static() -> void:
	var w := Node2D.new()
	w.name = "World"
	add_child(w)
	# sky: the outside's sky + far city, cut off at the ground line
	_rect(w, Rect2(0, 0, WORLD_W, SURFACE_Y), Color(0.55, 0.32, 0.22))
	for file in ["bg_sky", "bg_far"]:
		var t := _tex(file)
		if t == null:
			continue
		var s := Sprite2D.new()
		s.texture = t
		s.centered = false
		s.region_enabled = true
		s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		# the picture's bottom (its horizon) sits a little under the ground line
		var top := float(t.get_height()) - SURFACE_Y - 28.0
		s.region_rect = Rect2(0, top, WORLD_W, SURFACE_Y)
		s.light_mask = 2
		w.add_child(s)
	# ground: grass strip, then packed dirt down to the bottom of the screen
	_tiled(w, "tiles_outside_dirt_grass", Rect2(0, SURFACE_Y, WORLD_W, 16), Color(0.32, 0.26, 0.16))
	_tiled(w, "tiles_bunker_dirt_packed", Rect2(0, SURFACE_Y + 16, WORLD_W, VIEW.y - SURFACE_Y - 16),
			Color(0.20, 0.15, 0.11), Color(0.62, 0.56, 0.54))
	# the shaft: dark inside, steel walls, ladder rungs
	var sx := shaft_x()
	var top_y := float(SURFACE_Y)
	var bottom_y := float(ROOM_Y) + 6.0
	_rect(w, Rect2(sx - SHAFT_HALF, top_y, SHAFT_HALF * 2, bottom_y - top_y), Color(0.07, 0.06, 0.06))
	_tiled(w, "tile_shaft_wall", Rect2(sx - SHAFT_HALF - 16, top_y, 16, bottom_y - top_y), Color(0.35, 0.36, 0.38))
	_tiled(w, "tile_shaft_wall", Rect2(sx + SHAFT_HALF, top_y, 16, bottom_y - top_y), Color(0.35, 0.36, 0.38))
	var lt := _tex("obj_ladder")
	if lt:
		var ladder := Sprite2D.new()
		ladder.texture = lt
		ladder.centered = false
		ladder.region_enabled = true
		ladder.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		ladder.region_rect = Rect2(0, 0, lt.get_width(), bottom_y - top_y + 4)
		ladder.position = Vector2(sx - floorf(lt.get_width() / 2.0), top_y - 4)
		w.add_child(ladder)
	else:
		for y in range(int(top_y), int(bottom_y), 6):
			_rect(w, Rect2(sx - 5, y, 10, 2), Color(0.55, 0.35, 0.2))
	_put(w, "obj_ladder_top", Vector2(sx, top_y + 2))
	var hatch := _put(w, "obj_hatch_open", Vector2(sx + 1, top_y + 4))
	if hatch == null:
		_rect(w, Rect2(sx - 16, top_y - 6, 32, 6), Color(0.35, 0.36, 0.38))

# ---------------------------------------------------------------- rooms (rebuilt on change)
func _rebuild() -> void:
	for c in _rooms.get_children():
		_rooms.remove_child(c)
		c.queue_free()
	stations.clear()
	var rr := reach_range()
	for i in ROOM_ORDER.size():
		_add_room(ROOM_ORDER[i], i >= rr.x and i <= rr.y)
	# doors on the seams (owner = the room farther from the bedroom)
	var home := ROOM_ORDER.find(HOME)
	for i in range(1, ROOM_ORDER.size()):
		var behind: String = ROOM_ORDER[i - 1] if i - 1 < home else ROOM_ORDER[i]
		_add_door(behind, MARGIN + i * ROOM_W, i - 1 < home, rr)
	stations.append({"kind": "ladder", "x": shaft_x(), "room": HOME})
	stations.sort_custom(func(a, b): return a.x < b.x)
	walker.min_x = MARGIN + rr.x * ROOM_W + WALL
	walker.max_x = MARGIN + (rr.y + 1) * ROOM_W - WALL
	walker.position.x = clampf(walker.position.x, walker.min_x, walker.max_x)
	_refresh_hud()
	near = {}
	_update_near()

func _add_room(id: String, reachable: bool) -> void:
	var x := room_x(id)
	var unlocked: bool = GameState.is_room_unlocked(id)
	var room := Node2D.new()
	room.name = "Room_" + id
	room.position = Vector2(x, ROOM_Y)
	_rooms.add_child(room)
	var pic := _put(room, "room_" + id if unlocked else "room_locked", Vector2(ROOM_W / 2.0, ROOM_H))
	if pic == null:
		_rect(room, Rect2(0, 0, ROOM_W, ROOM_H), ROOM_COLORS[id] if unlocked else Color(0.11, 0.09, 0.07))
		_rect(room, Rect2(0, 66, ROOM_W, 12), Color(0.18, 0.17, 0.16))
	if not unlocked or not reachable:
		room.modulate = LOCKED_TINT
		var name_l := UIKit.outlined(GameState.ROOMS[id].name, 8, UIKit.DIM)
		name_l.position = Vector2(0, 50)
		name_l.size = Vector2(ROOM_W, 12)
		room.add_child(name_l)
		return
	var damaged: bool = GameState.is_room_damaged(id)
	if damaged:
		var cracks := _put(room, "room_damaged_overlay", Vector2(ROOM_W / 2.0, ROOM_H))
		if cracks == null:
			_rect(room, Rect2(0, 0, ROOM_W, ROOM_H), Color(0.5, 0.1, 0.05, 0.25))
	# lamp light (the room pictures have the lamp painted)
	var lamp_x: float = LAMP_X.get(id, 117)
	_lamp(room, Vector2(lamp_x, 22), 0.85, 120.0, 0.25 if damaged else 0.08)
	# buildings
	if id == HOME:
		_building(room, "cot", STATION_X[HOME].cot, true, false)
	for b in GameState.buildings_in(id):
		if b == "door":
			continue   # the Reinforced Door is drawn on the seam / hatch (see _add_door, _reinforced_door)
		_building(room, b, BUILD_X.get(b, 117), GameState.is_built(b), damaged)
		if b in ["purifier", "stove"] and GameState.is_built(b):   # V3 stations: E at them
			stations.append({"kind": b, "x": x + BUILD_X[b], "room": id})
	if id == HOME:   # Reinforced Door: a steel door by the hatch on the surface (it guards the way in)
		var holder := Node2D.new()
		holder.name = "ReinforcedDoor"
		holder.position = Vector2(shaft_x() + 34, SURFACE_Y + 3 - 66) - room.position
		room.add_child(holder)
		_building(holder, "door", 0, GameState.is_built("door"), damaged)
	if SHELF_X.has(id):
		_put(room, "obj_shelf", Vector2(SHELF_X[id], 66))
	# stations
	for kind in STATION_X.get(id, {}):
		var sx: float = x + STATION_X[id][kind]
		stations.append({"kind": kind, "x": sx, "room": id})
		match kind:
			"workbench":
				_station_art(room, "obj_workbench", STATION_X[id][kind], Vector2(38, 32), Color(0.45, 0.32, 0.2))
			"locker":
				_station_art(room, "obj_locker", STATION_X[id][kind], Vector2(12, 32), Color(0.4, 0.42, 0.45))
			"upgrade":
				_station_art(room, "obj_upgrade_bench", STATION_X[id][kind], Vector2(40, 32), Color(0.35, 0.4, 0.3))
			"calendar":
				var day_l := UIKit.outlined(str(GameState.day), 8, UIKit.BAD)
				day_l.position = Vector2(STATION_X[id][kind] - 10, 46)
				day_l.size = Vector2(20, 10)
				room.add_child(day_l)
				if pic == null:
					_rect(room, Rect2(STATION_X[id][kind] - 8, 28, 16, 18), Color(0.85, 0.82, 0.75))
	if id == "storage":
		var l := UIKit.outlined("Storage: +%d carry" % GameState.STORAGE_BONUS, 7, UIKit.GOOD)
		l.position = Vector2(0, 50)
		l.size = Vector2(ROOM_W, 10)
		room.add_child(l)

# The filter shows water while there is dirty water to filter; the stove burns while it works.
func _station_on(b_id: String) -> bool:
	if b_id == "purifier":
		return GameState.is_working("purifier") and GameState.dirty_water > 0
	return GameState.is_working(b_id)

func _station_art(room: Node2D, file: String, cx: float, size: Vector2, fallback: Color) -> void:
	if _put(room, file, Vector2(cx, 66)) == null:
		_rect(room, Rect2(cx - size.x / 2.0, 66 - size.y, size.x, size.y), fallback)

# A building on the floor: the bld_ art (or a labelled block); not built yet = a faint ghost.
func _building(room: Node2D, b_id: String, cx: float, built: bool, damaged: bool) -> void:
	var node: CanvasItem = null
	var files: Array = BUILD_ART.get(b_id, ["bld_" + b_id]).duplicate()
	if built and not damaged and BUILD_ART_ON.has(b_id) and _station_on(b_id):
		files.push_front(BUILD_ART_ON[b_id])
	for file in files:
		node = _put(room, file, Vector2(cx, 66))
		if node != null:
			break
	if node == null and b_id == "stove":   # placeholder iron stove with a fire window and a pipe
		var r := _rect(room, Rect2(cx - 12, 44, 24, 22), BUILDING_COLORS.stove)
		_rect(r, Rect2(4, 10, 16, 7), Color(1.0, 0.55, 0.2) if built and not damaged else Color(0.15, 0.12, 0.1))
		_rect(r, Rect2(-1, 0, 26, 3), Color(0.4, 0.38, 0.36))
		_rect(r, Rect2(16, -14, 4, 14), Color(0.25, 0.24, 0.23))
		node = r
	if node == null:
		var r := _rect(room, Rect2(cx - 13, 44, 26, 22), BUILDING_COLORS.get(b_id, Color.GRAY))
		var l := UIKit.label(b_id.capitalize(), 7, Color(0.05, 0.05, 0.05))
		l.size = r.size
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.add_child(l)
		node = r
	node.name = "Bld_" + b_id
	if not built:
		node.modulate = Color(1, 1, 1, 0.22)
	elif damaged:
		node.modulate = Color(0.55, 0.45, 0.45)

# A door on a seam. behind = the room behind it; left_side = that room is left of the seam.
func _add_door(behind: String, seam: float, left_side: bool, rr: Vector2i) -> void:
	var d := Node2D.new()
	d.name = "Door_" + behind
	d.position = Vector2(seam, FLOOR_Y)
	_rooms.add_child(d)
	var unlocked: bool = GameState.is_room_unlocked(behind)
	var art := _put(d, "obj_door_open" if unlocked else "obj_door_locked", Vector2.ZERO)
	if art == null:
		_rect(d, Rect2(-15, -44, 30, 44), Color(0.25, 0.22, 0.2) if unlocked else Color(0.45, 0.3, 0.15))
	if unlocked:
		return
	# the station is on the reachable side, only when the room next to the door is reachable
	var i := ROOM_ORDER.find(behind)
	var near_i := i + 1 if left_side else i - 1
	if near_i < rr.x or near_i > rr.y:
		return
	stations.append({"kind": "door", "x": seam + (DOOR_STAND if left_side else -DOOR_STAND), "room": behind})

# ---------------------------------------------------------------- overlays (HUD, prompt, banner, fade)
func _build_overlays() -> void:
	# world-space prompt, on its own layer so the ambient light doesn't darken it
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.name = "PromptLayer"
	_prompt_layer.layer = 5
	_prompt_layer.follow_viewport_enabled = true
	add_child(_prompt_layer)
	_prompt = Node2D.new()
	_prompt.name = "Prompt"
	_prompt.visible = false
	_prompt_layer.add_child(_prompt)
	var key := PanelContainer.new()
	var ks := StyleBoxFlat.new()
	ks.bg_color = Color(0.9, 0.88, 0.8)
	ks.border_color = Color(0.15, 0.1, 0.05)
	ks.set_border_width_all(1)
	ks.set_corner_radius_all(2)
	ks.content_margin_left = 3
	ks.content_margin_right = 3
	ks.content_margin_top = 0
	ks.content_margin_bottom = 0
	key.add_theme_stylebox_override("panel", ks)
	key.add_child(UIKit.label("E", 8, Color(0.1, 0.07, 0.04)))
	key.position = Vector2(-5, -1)
	_prompt.add_child(key)
	_prompt_label = UIKit.outlined("", 8, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_label.position = Vector2(-50, 12)
	_prompt_label.size = Vector2(100, 10)
	_prompt.add_child(_prompt_label)

	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "Hud"
	_hud_layer.layer = 10
	add_child(_hud_layer)
	var strip := ColorRect.new()
	strip.color = Color(0.05, 0.05, 0.06, 0.78)
	strip.size = Vector2(VIEW.x, 29)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(strip)
	# V3: today's goal and the thirst / hunger meters, a second line of the top bar
	_goal_label = UIKit.outlined("", 7, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	_goal_label.position = Vector2(4, 15)
	_goal_label.size = Vector2(VIEW.x - 8, 13)
	_goal_label.clip_text = true
	_goal_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hud_layer.add_child(_goal_label)

	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", UIKit.shade_style(5))
	_banner.position = Vector2(40, 228)
	_banner.custom_minimum_size = Vector2(VIEW.x - 80, 0)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	_hud_layer.add_child(_banner)
	_banner_label = UIKit.outlined("", 8, UIKit.TEXT)
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_label.custom_minimum_size = Vector2(VIEW.x - 92, 0)
	_banner.add_child(_banner_label)

	var fade_layer := CanvasLayer.new()
	fade_layer.name = "FadeLayer"
	fade_layer.layer = 90
	add_child(fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.size = VIEW * 2.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade)

func _refresh_hud() -> void:
	if _hud_row != null:
		_hud_row.queue_free()
	var gs := GameState
	var tier: int = gs.get_backpack_tier()
	_hud_row = UIKit.icon_row([
		["icon_day", "Day", "%d/%d" % [gs.day, gs.MAX_DAY]],
		["icon_bounce", "Bounces", str(gs.bounces)],
		["icon_health", "Health", "%d/%d" % [gs.health, gs.MAX_HEALTH]],
		["icon_water", "Water", str(gs.water)],
		["icon_food", "Food", str(gs.food)],
		["icon_wood", "Wood", str(gs.wood)],
		["icon_concrete", "Concrete", str(gs.concrete)],
		["icon_scrap", "Scrap", str(gs.scrap)],
		["icon_circuits", "Circuits", str(gs.circuits)],
		["icon_backpack_%d" % tier, "Pack", str(gs.get_carry_limit())]], 8, 7)
	_hud_row.position = Vector2(0, 1)
	_hud_row.size = Vector2(VIEW.x, 15)
	_hud_layer.add_child(_hud_row)
	if _goal_label:
		_goal_label.text = "Thirst %d  Hunger %d   %s" % [int(gs.water_meter), int(gs.food_meter), _goal_line()]

# "Goal: Bring home 8 scrap. (scrap 3/8)" or "Done: ..." for the top bar and the day banner.
func _goal_line() -> String:
	var t: String = GameState.get_goal_text()
	var prog: String = GameState.goal_progress_text()
	if prog != "" and not GameState.goal_done:
		t += " (%s)" % prog
	return t

func banner(text: String, time := BANNER_TIME) -> void:
	_banner_label.text = text
	_banner.visible = text != ""
	_banner.size = Vector2.ZERO   # shrink to the text
	_banner_left = time

func _hint(id: String, text: String) -> void:
	if _hint_once(id):
		banner(text, 6.0)

# SettingsStore.hint_once, guarded (a missing class just never shows hints).
func _hint_once(id: String) -> bool:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == "SettingsStore":
			return bool(load(c["path"]).hint_once(id))
	return false

# ---------------------------------------------------------------- lighting
func _load_lighting() -> void:
	if ResourceLoader.exists(LIGHTING):
		var script: Script = load(LIGHTING)
		if script != null and script.can_instantiate():
			_light_script = script

func _setup_lighting() -> void:
	if _light_script == null:
		return
	lighting = _light_script.call("setup_scene", self, AMBIENT)
	if lighting and pause_menu:
		lighting.call("watch", pause_menu)

# A warm LightSource (via the loaded lighting script; nothing when it is missing or broken).
func _lamp(parent: Node, pos: Vector2, energy: float, radius: float, flicker: float) -> void:
	if _light_script == null:
		return
	var l: Node = _light_script.call("add_lamp", parent, pos, LAMP_COLOR, energy, radius, flicker)
	if l:
		l.name = "Lamp"

# A lamp hangs over every door (the bottom of obj_lamp_ceiling, just under the rooms' ceiling).
func _add_door_lamps() -> void:
	var t := _tex("obj_lamp_ceiling")
	for i in range(1, ROOM_ORDER.size()):
		var seam := MARGIN + i * ROOM_W
		var holder := Node2D.new()
		holder.name = "DoorLamp%d" % i
		holder.position = Vector2(seam, ROOM_Y + 6)
		holder.z_index = 1   # over the room pictures
		add_child(holder)
		if t:
			var s := Sprite2D.new()
			s.texture = t
			s.centered = false
			s.region_enabled = true
			s.region_rect = Rect2(0, t.get_height() - 16, t.get_width(), 16)
			s.position = Vector2(-floorf(t.get_width() / 2.0), 0)
			holder.add_child(s)
		else:
			_rect(holder, Rect2(-4, 0, 8, 6), Color(1.0, 0.8, 0.4))
		_lamp(holder, Vector2(0, 12), 0.6, 70.0, 0.15)

# ---------------------------------------------------------------- arrival, ladder, sleep
func _arrive() -> void:
	var arrival := str(GameState.get("bunker_arrival")) if "bunker_arrival" in GameState else "cot"
	if arrival == "hatch":
		walker.position = Vector2(shaft_x(), SURFACE_Y)
		camera.position = Vector2(walker.position.x, VIEW.y / 2.0)
		camera.reset_smoothing()
		busy = true
		walker.can_walk = false
		_fade.color.a = 1.0
		create_tween().tween_property(_fade, "color:a", 0.0, FADE_TIME)
		walker.climb_to(Vector2(shaft_x(), FLOOR_Y))
		await walker.climb_finished
		busy = false
		walker.can_walk = true
		var got := _banked_text()
		banner(got)
		if not got.is_empty():
			await get_tree().create_timer(2.5).timeout
		_hint("bunker_ladder", "The ladder goes back up to the surface: E at its foot. One trip outside per day; then sleep at the cot.")
	else:
		walker.position = Vector2(station_x("cot") + 12, FLOOR_Y)
		walker.facing = -1.0
		camera.position = Vector2(walker.position.x, VIEW.y / 2.0)
		camera.reset_smoothing()
		walker.wake_up()
		busy = false
		_fade.color.a = 1.0
		create_tween().tween_property(_fade, "color:a", 0.0, FADE_TIME)
		banner(_day_text(), 6.0)
		if bool(GameState.get("show_tutorial")):
			GameState.set("show_tutorial", false)
			if _tutorial_first_time():
				_open_tutorial()
		if tutorial == null:
			_hint("bunker_ladder", "Walk with A / D. The ladder leads outside: press E at its foot. Walk up to things and press E to use them.")

func _tutorial_first_time() -> bool:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == "Tutorial":
			return bool(load(c["path"]).is_first_time())
	return false

func _open_tutorial() -> void:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == "Tutorial":
			tutorial = load(c["path"]).open(self)
	if tutorial == null:
		return
	walker.can_walk = false
	tutorial.finished.connect(func():
		tutorial = null
		walker.can_walk = popup == null and not busy
		_hint("bunker_ladder", "Walk with A / D. The ladder leads outside: press E at its foot. Walk up to things and press E to use them."))

func _day_text() -> String:
	var gs := GameState
	var t := "Day %d of %d. %s" % [gs.day, gs.MAX_DAY, gs.get_goal_text()]
	var note: String = DayPlan.note_text(gs.day)
	if note != "":
		t += " " + note
	if gs.skip_expedition:
		t += " A radiation storm rages outside: stay in today."
	elif gs.tomorrow_rad_mult > 1.0 and not note.contains("Storm"):
		t += " Storm: radiation x%s outside today." % str(gs.tomorrow_rad_mult)
	if gs.bonus_crate:
		t += " Stranger's supplies: crates are fuller today."
	return t

func _banked_text() -> String:
	var got: Dictionary = GameState.get("last_banked") if "last_banked" in GameState else {}
	if got.is_empty():
		return "You climb down empty-handed."
	var parts: PackedStringArray = []
	for k in GameState.LOOT_KINDS:
		if got.has(k):
			parts.append("+%d %s" % [int(got[k]), GameState.item_name(k)])
	var t := "Stored in the locker: " + ", ".join(parts)
	if str(GameState.get("goal_message")) != "":
		t += " " + str(GameState.goal_message)
	return t

# E at the foot of the ladder: where to? (only the surface open: go straight up)
func use_ladder() -> void:
	var why: String = GameState.go_outside_block()
	if why != "":
		banner(why)
		return
	for id in Locations.ORDER:
		if id != "surface" and GameState.is_location_unlocked(id):
			_open_popup("ladder", HOME)
			return
	climb_up("surface")

# Climb up and start today's expedition to `location`.
func climb_up(location := "surface") -> void:
	var why: String = GameState.go_outside_block(location)
	if why != "":
		banner(why)
		return
	close_popup()
	busy = true
	walker.can_walk = false
	near = {}
	_prompt.visible = false
	if pause_menu:
		pause_menu.enabled = false
	walker.position.x = shaft_x()
	walker.climb_to(Vector2(shaft_x(), SURFACE_Y))
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await walker.climb_finished
	if _fade.color.a < 1.0:
		await tw.finished
	GameState.go_outside(location)

func sleep_now() -> void:
	if _slept:
		return
	_slept = true
	busy = true
	walker.can_walk = false
	close_popup()
	if pause_menu:
		pause_menu.enabled = false
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await tw.finished
	if GameState.went_outside or GameState.skip_expedition:
		GameState.sleep()
	else:
		GameState.wait_inside()

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	camera.position = Vector2(walker.position.x, VIEW.y / 2.0)
	if _banner_left > 0.0:
		_banner_left -= delta
		if _banner_left <= 0.0:
			_banner.visible = false
	_update_near()

func _update_near() -> void:
	var best: Dictionary = {}
	if not busy and popup == null and tutorial == null and walker and not walker.climbing:
		var best_d := REACH
		for s in stations:
			var d := absf(float(s.x) - walker.position.x)
			if d <= best_d:
				best_d = d
				best = s
	if best != near:
		near = best
		if not near.is_empty():
			_hint("bunker_stations", "Walk up to things and press E to use them.")
	_prompt.visible = not near.is_empty()
	if near.is_empty():
		return
	_prompt.position = Vector2(roundf(float(near.x)), FLOOR_Y - 58)
	_prompt_label.text = _station_label(near)

func _station_label(s: Dictionary) -> String:
	match s.kind:
		"door":
			return "Unlock " + str(GameState.ROOMS[s.room].name)
		"workbench":
			return "Repair / build" if GameState.is_room_damaged(s.room) else "Build"
		"ladder":
			return "Climb up" if GameState.go_outside_block() == "" else "Ladder"
	return STATION_LABEL.get(s.kind, s.kind)

func _unhandled_input(event: InputEvent) -> void:
	if busy or popup != null or tutorial != null or near.is_empty():
		return
	if event.is_action_pressed(&"interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		use_station(near)

# ---------------------------------------------------------------- stations
func use_station(s: Dictionary) -> void:
	match s.kind:
		"ladder":
			use_ladder()
		"purifier":
			_open_popup("purifier", s.room)
		"stove":
			_open_popup("stove", s.room)
		"cot":
			_open_popup("cot", s.room)
		"calendar":
			_open_popup("calendar", s.room)
		"locker":
			_open_popup("locker", s.room)
		"upgrade":
			_open_popup("upgrade", s.room)
		"workbench":
			_open_popup("workbench", s.room)
		"door":
			_open_popup("door", s.room)

func _open_popup(kind: String, room: String) -> void:
	close_popup()
	popup = PopupScript.new()
	popup_kind = kind + ":" + room
	add_child(popup)
	popup.closed.connect(_on_popup_closed)
	walker.can_walk = false
	if pause_menu:
		pause_menu.enabled = false
	_fill_popup()

func _fill_popup() -> void:
	if popup == null:
		return
	popup.clear()
	var parts := popup_kind.split(":")
	var kind := parts[0]
	var room := parts[1]
	var gs := GameState
	match kind:
		"cot":
			popup.title("Cot")
			popup.line("Sleep until tomorrow. The night makes you thirsty and hungry; you drink %d water and eat %d meal (you have %d and %d)."
					% [gs.night_water_need(), gs.night_food_need(), gs.water, gs.food])
			if gs.water < gs.night_water_need() or gs.food < gs.night_food_need():
				popup.line("Not enough in the locker: if a meter runs empty tonight you lose health.", UIKit.BAD)
			if not gs.went_outside and not gs.skip_expedition:
				popup.line("You haven't been outside today: sleeping now skips the day.", UIKit.BAD)
			popup.row("Day %d of %d" % [gs.day, gs.MAX_DAY], "", "Sleep", "sleep", true, sleep_now)
		"calendar":
			popup.title("Day %d of %d" % [gs.day, gs.MAX_DAY])
			popup.line("The convoy comes after Day %d, but only if the Radio Beacon is built and working." % gs.MAX_DAY)
			popup.line("Radio Beacon: " + ("built" if gs.is_built("radio") else "not built"),
					UIKit.GOOD if gs.is_rescued() else UIKit.DIM)
			popup.line("Bounces left: %d   Scars: %s" % [gs.bounces, gs.scar_names_text()], UIKit.DIM)
		"locker":
			popup.title("Locker")
			popup.add_node(UIKit.icon_row([
				[UIKit.item_icon("water"), "Water", str(gs.water)], [UIKit.item_icon("food"), "Meals", str(gs.food)],
				["icon_dirty_water", "Dirty", str(gs.dirty_water)], ["icon_raw_meat", "Meat", str(gs.raw_meat)],
				["icon_mushroom", "Mush.", str(gs.mushroom)]], 9, 8))
			popup.add_node(UIKit.icon_row([
				["icon_wood", "Wood", str(gs.wood)], ["icon_concrete", "Concrete", str(gs.concrete)],
				["icon_scrap", "Scrap", str(gs.scrap)], ["icon_circuits", "Circuits", str(gs.circuits)],
				["icon_bandage", "Bandage", str(gs.bandage)], ["icon_radio_part", "Radio part", str(gs.radio_part)]], 9, 6))
			popup.line("Thirst %d/100  Hunger %d/100  Health %d/%d" % [int(gs.water_meter), int(gs.food_meter), gs.health, gs.MAX_HEALTH], UIKit.TEXT)
			popup.button_row([["Drink", "drink", gs.can_consume_stock("water"), _do.bind("consume", "water")],
				["Eat", "eat", gs.can_consume_stock("food"), _do.bind("consume", "food")],
				["Bandage", "bandage", gs.can_consume_stock("bandage"), _do.bind("consume", "bandage")]])
			var packed := PackedStringArray()
			for k in gs.PACKABLE:
				packed.append("%s %d" % [gs.item_name(k), int(gs.packed.get(k, 0))])
			popup.line("Take on the trip: %s (uses carry space)." % ", ".join(packed), UIKit.DIM, 7)
			popup.button_row([["+Water", "pack_water", gs.can_pack("water"), _do.bind("pack", "water")],
				["+Meal", "pack_food", gs.can_pack("food"), _do.bind("pack", "food")],
				["+Bandage", "pack_bandage", gs.can_pack("bandage"), _do.bind("pack", "bandage")]])
		"upgrade":
			var tier: int = gs.get_backpack_tier()
			popup.title("Upgrade bench")
			popup.add_node(_backpack_row(tier, "Now: tier %d, carry %d items" % [tier, gs.get_carry_limit()]))
			if tier >= gs.BACKPACK_SLOTS.size():
				popup.line("Your backpack is the best there is.", UIKit.GOOD)
			else:
				var next := tier + 1
				popup.add_node(_backpack_row(next, "Tier %d: carry %d items" % [next, gs.carry_limit_for_tier(next)]))
				var cost: Dictionary = gs.backpack_upgrade_cost(next)
				popup.row("Upgrade to tier %d" % next, "Costs " + gs.cost_text(cost), "Upgrade", "upgrade",
						gs.can_upgrade_backpack(), _do.bind("upgrade", ""))
			popup.line("Storage Room +%d, Steady Hands +%d on top of the tier." % [gs.STORAGE_BONUS, gs.STEADY_BONUS], UIKit.DIM, 7)
		"workbench":
			popup.title("%s workbench" % gs.ROOMS[room].name)
			if gs.is_room_damaged(room):
				popup.line("This room is damaged: its machines don't work and nothing can be built here.", UIKit.BAD)
				popup.row("Repair the room", "Costs " + gs.cost_text(gs.REPAIR_COST), "Repair", "repair",
						gs.can_repair(room), _do.bind("repair", room))
			for b in gs.buildings_in(room):
				var info: Dictionary = gs.BUILDINGS[b]
				var built: bool = gs.is_built(b)
				popup.row(info.name, "%s. %s" % [info.get("desc", ""), "Built." if built else "Costs " + gs.cost_text(info.cost)],
						"Built" if built else "Build", "build_" + b, gs.can_build(b), _do.bind("build", b))
		"ladder":
			popup.title("Where to?")
			for id in Locations.ORDER:
				var lock: String = gs.location_lock_text(id)
				var cfg: Dictionary = Locations.get_config(id)
				popup.row(cfg.name, lock if lock != "" else "Radiation x%s. %s" % [str(cfg.rad), _short(cfg.desc)],
						"Go" if lock == "" else "Locked", "go_" + id, lock == "", climb_up.bind(id))
		"purifier":
			popup.title("Water Filter")
			popup.line("Dirty water in, clean water out (1 for 1). At night it filters up to %d on its own." % gs.FILTER_NIGHT_MAX, UIKit.DIM)
			popup.add_node(UIKit.icon_row([["icon_dirty_water", "Dirty water", str(gs.dirty_water)],
				[UIKit.item_icon("water"), "Clean water", str(gs.water)]], 9, 12))
			popup.button_row([["Filter 1", "filter_1", gs.can_filter(), _do.bind("filter", "1")],
				["Filter all", "filter_all", gs.can_filter(), _do.bind("filter", "99")]], 70)
		"stove":
			popup.title("Stove")
			popup.line("Wood is the fuel.", UIKit.DIM)
			popup.add_node(UIKit.icon_row([["icon_raw_meat", "Raw meat", str(gs.raw_meat)], ["icon_mushroom", "Mushrooms", str(gs.mushroom)],
				["icon_dirty_water", "Dirty water", str(gs.dirty_water)], ["icon_wood", "Wood", str(gs.wood)]], 9, 8))
			for id in gs.RECIPES:
				var r: Dictionary = gs.RECIPES[id]
				popup.row(r.name, "%s -> %s" % [gs.cost_text(r["in"]), gs.cost_text(r["out"])], "Cook", "cook_" + id,
						gs.can_cook(id), _do.bind("cook", id))
		"door":
			var info: Dictionary = gs.ROOMS[room]
			popup.title(info.name)
			if gs.is_room_unlocked(room):
				popup.line("Unlocked.", UIKit.GOOD)
			else:
				popup.line("Dig it out and shore it up to use it. " + _room_use(room), UIKit.TEXT)
				popup.row("Unlock", "Costs " + gs.cost_text(info.cost), "Unlock", "unlock",
						gs.can_unlock(room), _do.bind("unlock", room))
	popup.finish()

# First sentence of a description (popup notes stay short).
static func _short(text: String) -> String:
	var i := text.find(". ")
	return text if i < 0 else text.left(i + 1)

func _room_use(room: String) -> String:
	if room == "storage":
		return "Storage: +%d carry space." % GameState.STORAGE_BONUS
	var names: PackedStringArray = []
	for b in GameState.buildings_in(room):
		names.append(GameState.BUILDINGS[b].name)
	return "Lets you build: %s." % ", ".join(names)

func _backpack_row(tier: int, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var pic := UIKit.picture("world_clean/icon_backpack_%d" % tier)
	if pic != null:
		h.add_child(pic)
	var l := UIKit.label(text, 8, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h

# A popup button: run the GameState call, then refill the popup (or close it for an unlock).
func _do(what: String, id: String) -> void:
	var ok := false
	var goal_before: bool = GameState.goal_done
	match what:
		"upgrade":
			ok = GameState.upgrade_backpack()
			if ok:
				banner("Backpack tier %d: you can carry %d items." % [GameState.get_backpack_tier(), GameState.get_carry_limit()])
		"build":
			ok = GameState.build(id)
			if ok:
				banner("Built: %s." % GameState.BUILDINGS[id].name)
		"repair":
			ok = GameState.repair_room(id)
			if ok:
				banner("The %s is repaired." % GameState.ROOMS[id].name)
		"consume":
			ok = GameState.consume_stock(id)
		"pack":
			ok = GameState.pack_item(id)
		"filter":
			var n: int = GameState.filter_water(int(id))
			ok = n > 0
			if ok:
				banner("Filtered %d dirty water into clean water." % n)
		"cook":
			ok = GameState.cook(id)
			if ok:
				banner("Cooked: %s." % GameState.RECIPES[id].name)
		"unlock":
			ok = GameState.unlock_room(id)
			if ok:
				banner("The %s is open." % GameState.ROOMS[id].name)
				close_popup()
				return
	if ok and GameState.goal_done and not goal_before:
		banner(GameState.goal_message, 6.0)
	_fill_popup()

func close_popup() -> void:
	if popup != null and is_instance_valid(popup):
		popup.close()

func _on_popup_closed() -> void:
	popup = null
	popup_kind = ""
	walker.can_walk = not busy and tutorial == null
	_reenable_pause.call_deferred()   # deferred: not for the Esc that closed the popup

func _reenable_pause() -> void:
	if pause_menu and popup == null and not busy:
		pause_menu.enabled = true
