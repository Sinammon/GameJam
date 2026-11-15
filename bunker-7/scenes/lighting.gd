class_name Lighting
extends Node2D
# 2D lights for any scene (expedition outside, the walkable bunker later):
# ambient tint (CanvasModulate), the player's headlamp + flashlight cone, world
# lights (LightSource: lamps, glows, pulses) with a cap, a pool of glow lights
# for many small spots (toxic tiles), and cheap shadows from height-map
# occluders. Quality comes from SettingsStore "lights_quality":
#   full   : ambient + lights + shadows on the headlamp/cone, cap CAP["full"]
#   simple : ambient + lights, no shadows, no occluders, cap CAP["simple"]
#   off    : no CanvasModulate, no lights, no occluders (the plain look)
#
# Use from another scene:
#   var lights := Lighting.setup_scene(self, Color(0.7, 0.62, 0.55))
#   lights.follow_player($Player)                       # headlamp
#   Lighting.add_lamp(self, Vector2(100, 200), Color(1, 0.75, 0.4), 1.0, 90.0, 0.12)
#   lights.watch(pause_menu)                            # settings_changed -> live
#   Lighting.add_occluder(self, PackedVector2Array([...]))   # walls (full only)
#
# Cost (Compatibility renderer): each enabled light adds a per-pixel pass over the
# canvas items inside its rect; shadows add a tiny 1D shadow-map render per
# shadow-casting light (only the headlamp and the cone) plus a lookup per pixel.
# The cap keeps at most CAP world lights + 2 player lights on. CanvasModulate is
# free. Nothing here allocates per frame (refresh every REFRESH s, flicker = sines).
# CanvasLayers (HUD, vignette, pause menu, tutorial) are never affected.

const LightSourceScript := preload("res://scenes/light_source.gd")

# --- Tuning -------------------------------------------------------------------
const QUALITIES := ["full", "simple", "off"]
const CAP := {"full": 6, "simple": 3, "off": 0}   # world LightSources on at once (player lights extra)
const MIN_BRIGHTNESS := 0.35       # ambient never darker than this (luminance)
const AMBIENT_SMOOTH := 2.0        # 1/s, how fast the ambient follows its target
const HEADLAMP_RADIUS := 110.0
const HEADLAMP_COLOR := Color(1.0, 0.93, 0.8)
const HEADLAMP_ENERGY := Vector2(0.25, 0.85)   # energy at bright .. darkest ambient
const CONE_LENGTH := 180.0
const CONE_HALF_ANGLE := 0.42      # rad
const CONE_COLOR := Color(1.0, 0.97, 0.88)
const CONE_ENERGY := 1.1
const CONE_TILT := 0.12            # rad, a little downwards
const CONE_SHADOWS := true         # the cone is part of the headlamp: casts shadows in "full"
const CHEST := Vector2(0, -14)     # light origin on the player
const REFRESH := 0.2               # s between cap / glow-pool / eye updates
const SETTINGS_POLL := 0.5         # s between SettingsStore checks (fallback to the signal)
const VIEW_MARGIN := 48.0          # px outside the view a light may still be on
const OCCLUDER_INSET := 5.0        # px of lit "skin" on exposed ground faces
const TEX_SIZE := 128

const MASK_WORLD := 1              # light_mask of normal items
const MASK_BACKGROUND := 2         # parallax: lit by world lamps, not by the headlamp
const GROUP := "lighting"
const GROUP_SOURCES := "light_sources"
const GROUP_OCCLUDERS := "light_occluders"
const GROUP_GLOW := "light_glow"   # items whose self_modulate is boosted to stay bright in the dark (zombie eyes)

static var _radial: Texture2D = null
static var _cone: Texture2D = null
static var _store: Variant = null
static var _store_looked := false

var quality := "full"
var ambient_target := Color.WHITE
var ambient := Color.WHITE
var canvas_mod: CanvasModulate = null
var player: Node2D = null
var flashlight_on := Callable()    # () -> bool; null = no flashlight
var headlamp: PointLight2D = null
var cone: PointLight2D = null
var sources: Array = []            # registered LightSources
var glow_pool: Array = []          # LightSources reused for glow spots
var glow_spots := PackedVector2Array()
var glow_range := 320.0
var _glow_taken := PackedByteArray()
var _ground_tops: Array = []       # row per column (a live reference, e.g. mining.floor_rows)
var _ground_bottom := 0.0
var _ground_tile := 16
var _ground_chunk := 20
var _ground_occ: Array = []        # LightOccluder2D per chunk
var _t := 0.0
var _refresh_left := 0.0
var _poll_left := 0.0
var _stored := ""                  # last value seen in SettingsStore
var _override := false             # F2 debug override until the setting changes

# --- static helpers ---------------------------------------------------------------

# Adds a Lighting node to root with this ambient tint and returns it.
static func setup_scene(root: Node, ambient_color: Color) -> Lighting:
	var l: Lighting = load("res://scenes/lighting.gd").new()
	l.name = "Lighting"
	l.ambient_target = ambient_color
	l.ambient = ambient_color
	root.add_child(l)
	return l

# A world lamp (child of parent at pos). flicker 0 = steady, ~0.12 = slow wobble.
static func add_lamp(parent: Node, pos: Vector2, color: Color, energy: float, radius: float, flicker := 0.0) -> LightSource:
	var s: LightSource = LightSourceScript.new()
	s.configure(color, energy, radius, flicker)
	s.position = pos
	parent.add_child(s)
	return s

# A shadow-casting polygon (only visible in "full").
static func add_occluder(parent: Node, polygon: PackedVector2Array) -> LightOccluder2D:
	var o := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.polygon = polygon
	poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
	o.occluder = poly
	o.add_to_group(GROUP_OCCLUDERS)
	parent.add_child(o)
	var l := find(o)
	o.visible = l.quality == "full" if l else stored_quality() == "full"
	return o

static func find(node: Node) -> Lighting:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as Lighting

# "full" / "simple" / "off" from SettingsStore ("full" if that class is missing).
static func stored_quality() -> String:
	if not _store_looked:
		_store_looked = true
		for c in ProjectSettings.get_global_class_list():
			if c["class"] == "SettingsStore":
				_store = load(c["path"])
	if _store == null:
		return "full"
	var q: Variant = _store.get_value("lights_quality")
	return q if typeof(q) == TYPE_STRING and q in QUALITIES else "full"

# Soft round light (white centre -> transparent), shared by every light.
static func radial_texture() -> Texture2D:
	if _radial == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(0, 0, 0, 0))
		g.add_point(0.45, Color(0.55, 0.55, 0.55, 0.75))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = TEX_SIZE
		t.height = TEX_SIZE
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_radial = t
	return _radial

# Cone pointing right from the texture centre (left half empty), made once.
static func cone_texture() -> Texture2D:
	if _cone == null:
		var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
		var c := TEX_SIZE / 2.0
		for y in TEX_SIZE:
			for x in TEX_SIZE:
				var d := Vector2(x + 0.5 - c, y + 0.5 - c)
				var r := d.length() / c
				if d.x <= 0.0 or r >= 1.0:
					continue
				var a := absf(atan2(d.y, d.x)) / CONE_HALF_ANGLE
				if a >= 1.0:
					continue
				var v := (1.0 - r) * (1.0 - r * 0.3) * (1.0 - a * a) * minf(1.0, r * 6.0)
				img.set_pixel(x, y, Color(v, v, v, v))
		_cone = ImageTexture.create_from_image(img)
	return _cone

# --- lifecycle -----------------------------------------------------------------------

func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS   # settings change while paused (pause menu)
	_stored = stored_quality()
	for s in get_tree().get_nodes_in_group(GROUP_SOURCES):
		register(s)
	set_quality(_stored)

func register(s: Node) -> void:
	if not s in sources:
		sources.append(s)
		s.manager = self
		s.enabled = false
		_refresh_left = 0.0

func unregister(s: Node) -> void:
	sources.erase(s)

# Listens to a node's settings_changed(key, value) signal (the pause menu).
func watch(node: Object) -> void:
	if node and node.has_signal("settings_changed") and not node.is_connected("settings_changed", _on_settings_changed):
		node.connect("settings_changed", _on_settings_changed)

func _on_settings_changed(key: String, value: Variant) -> void:
	if key == "lights_quality" and typeof(value) == TYPE_STRING and value in QUALITIES:
		_stored = value
		_override = false
		set_quality(value)

func set_ambient(c: Color) -> void:
	ambient_target = c

# Applies a quality now: creates or removes the CanvasModulate, player lights, occluders.
func set_quality(q: String) -> void:
	if not q in QUALITIES:
		q = "full"
	quality = q
	if q == "off":
		if canvas_mod:
			canvas_mod.queue_free()
			canvas_mod = null
		_free_player_lights()
	else:
		if canvas_mod == null:
			canvas_mod = CanvasModulate.new()
			canvas_mod.name = "Ambient"
			add_child(canvas_mod)
		canvas_mod.color = _clamped(ambient)
		_make_player_lights()
		if headlamp:
			headlamp.shadow_enabled = q == "full"
			cone.shadow_enabled = q == "full" and CONE_SHADOWS
	for o in get_tree().get_nodes_in_group(GROUP_OCCLUDERS):
		(o as CanvasItem).visible = q == "full"
	if q == "full" and _ground_occ.is_empty() and not _ground_tops.is_empty():
		_build_ground()
	elif q != "full" and not _ground_occ.is_empty():
		for o in _ground_occ:
			o.queue_free()
		_ground_occ.clear()
	_refresh_left = 0.0
	_refresh()

func cycle_quality() -> void:
	_override = true
	set_quality(QUALITIES[(QUALITIES.find(quality) + 1) % QUALITIES.size()])

# --- player lights -------------------------------------------------------------------

# Headlamp on this player; flashlight_fn () -> bool shows the cone when true.
func follow_player(p: Node2D, flashlight_fn := Callable()) -> void:
	player = p
	flashlight_on = flashlight_fn
	if quality != "off":
		_make_player_lights()
		set_quality(quality)

func _make_player_lights() -> void:
	if player == null or not is_instance_valid(player) or headlamp != null:
		return
	headlamp = PointLight2D.new()
	headlamp.name = "Headlamp"
	headlamp.texture = radial_texture()
	headlamp.texture_scale = HEADLAMP_RADIUS * 2.0 / TEX_SIZE
	headlamp.color = HEADLAMP_COLOR
	headlamp.position = CHEST
	_setup_player_light(headlamp)
	cone = PointLight2D.new()
	cone.name = "Flashlight"
	cone.texture = cone_texture()
	cone.texture_scale = CONE_LENGTH * 2.0 / TEX_SIZE
	cone.color = CONE_COLOR
	cone.energy = CONE_ENERGY
	cone.position = CHEST
	cone.enabled = false
	_setup_player_light(cone)

func _setup_player_light(l: PointLight2D) -> void:
	l.range_item_cull_mask = MASK_WORLD
	l.shadow_filter = Light2D.SHADOW_FILTER_NONE
	l.shadow_item_cull_mask = 1
	player.add_child(l)

func _free_player_lights() -> void:
	for l in [headlamp, cone]:
		if l and is_instance_valid(l):
			l.queue_free()
	headlamp = null
	cone = null

# --- glow pool (many spots, few lights) ------------------------------------------------

# count lights that sit on the spots nearest to the player (within glow_range).
func setup_glow(count: int, color: Color, energy: float, radius: float, flicker := 0.15) -> void:
	for i in count:
		var s: LightSource = add_lamp(self, Vector2.ZERO, color, energy, radius, flicker)
		s.name = "Glow%d" % i
		s.wanted = false
		s.range_item_cull_mask = MASK_WORLD
		glow_pool.append(s)

func set_glow_spots(points: PackedVector2Array) -> void:
	glow_spots = points
	_glow_taken.resize(points.size())
	_refresh_left = 0.0

# --- height-map occluders (ground) --------------------------------------------------------

# Shadows from a ground that is a height map: tops[col] = top solid row.
# One LightOccluder2D per chunk of columns; refresh_ground_col() after digging.
func add_heightmap_occluders(tops: Array, bottom_y: float, tile := 16, chunk_cols := 20) -> void:
	_ground_tops = tops
	_ground_bottom = bottom_y
	_ground_tile = tile
	_ground_chunk = chunk_cols
	if quality == "full":
		_build_ground()

func refresh_ground_col(col: int) -> void:
	if _ground_occ.is_empty():
		return
	var ch := floori(col / float(_ground_chunk))
	var first := ch - 1 if col % _ground_chunk == 0 else ch   # a chunk's edge step depends on its neighbour column
	var last := ch + 1 if col % _ground_chunk == _ground_chunk - 1 else ch
	for c in range(first, last + 1):
		if c >= 0 and c < _ground_occ.size():
			(_ground_occ[c] as LightOccluder2D).occluder.polygon = ground_polygon(c)

func _build_ground() -> void:
	var n := ceili(_ground_tops.size() / float(_ground_chunk))
	for c in n:
		var o := LightOccluder2D.new()
		o.name = "GroundOccluder%d" % c
		var poly := OccluderPolygon2D.new()
		poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
		o.occluder = poly
		add_child(o)
		_ground_occ.append(o)
		poly.polygon = ground_polygon(c)

func _top(col: int) -> float:
	col = clampi(col, 0, _ground_tops.size() - 1)
	return float(_ground_tops[col]) * _ground_tile + OCCLUDER_INSET

# Outline of chunk ch: the ground below its columns, with an OCCLUDER_INSET px
# lit skin left on top and on exposed side faces.
func ground_polygon(ch: int) -> PackedVector2Array:
	var c0 := ch * _ground_chunk
	var c1 := mini(c0 + _ground_chunk, _ground_tops.size())
	var t := float(_ground_tile)
	var pts := PackedVector2Array()
	var x0 := c0 * t
	var y0 := _top(c0)
	var yl := _top(c0 - 1) if c0 > 0 else y0
	pts.append(Vector2(x0, _ground_bottom))
	if yl > y0:   # left neighbour lower: our left face is exposed
		pts.append(Vector2(x0, yl))
		pts.append(Vector2(x0 + OCCLUDER_INSET, yl))
		pts.append(Vector2(x0 + OCCLUDER_INSET, y0))
	else:
		pts.append(Vector2(x0, y0))
	for col in range(c0, c1):
		var y := _top(col)
		var x := (col + 1) * t
		var last := col == c1 - 1
		var yn := _top(col + 1) if col + 1 < _ground_tops.size() else y
		if yn > y:   # step down to the right: skin on our right face
			pts.append(Vector2(x - OCCLUDER_INSET, y))
			pts.append(Vector2(x - OCCLUDER_INSET, yn))
			if last:
				pts.append(Vector2(x, yn))
		elif yn < y and not last:   # step up: skin on the next column's left face
			pts.append(Vector2(x + OCCLUDER_INSET, y))
			pts.append(Vector2(x + OCCLUDER_INSET, yn))
		elif last:
			pts.append(Vector2(x, y))
	pts.append(Vector2(c1 * t, _ground_bottom))
	return pts

# --- per frame -----------------------------------------------------------------------------

func _clamped(c: Color) -> Color:
	var lum := c.get_luminance()
	if lum < MIN_BRIGHTNESS:
		var k := MIN_BRIGHTNESS / maxf(lum, 0.01)
		c = Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0))
	return c

func _process(delta: float) -> void:
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = SETTINGS_POLL
		var q := stored_quality()
		if q != _stored:
			_stored = q
			_override = false
			set_quality(q)
	if get_tree().paused:
		return
	_t += delta
	ambient = ambient.lerp(ambient_target, clampf(delta * AMBIENT_SMOOTH, 0.0, 1.0))
	if quality == "off":
		return
	var amb := _clamped(ambient)
	if canvas_mod:
		canvas_mod.color = amb
	if headlamp and is_instance_valid(headlamp):
		headlamp.energy = lerpf(HEADLAMP_ENERGY.y, HEADLAMP_ENERGY.x, clampf((amb.get_luminance() - MIN_BRIGHTNESS) / (1.0 - MIN_BRIGHTNESS), 0.0, 1.0))
		var on := flashlight_on.is_valid() and bool(flashlight_on.call())
		cone.enabled = on
		if on:
			var f: float = player.get("facing") if "facing" in player else 1.0
			cone.rotation = CONE_TILT if f >= 0.0 else PI - CONE_TILT
	for s in sources:
		if s.enabled:
			s.animate(_t)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH
		_refresh()

# Which world lights are on: wanted, near the view, best CAP by distance - priority.
func _refresh() -> void:
	var cap: int = CAP.get(quality, 0)
	var center := _view_center()
	var reach := 300.0 + VIEW_MARGIN
	_assign_glow(center)
	for s in sources:
		s._chosen = false
		s._score = INF
		if cap > 0 and s.wanted and s.is_visible_in_tree():
			var d: float = s.global_position.distance_to(center)
			if d - s.radius < reach:
				s._score = d - s.priority
	for k in cap:
		var best: Node = null
		for s in sources:
			if not s._chosen and s._score < INF and (best == null or s._score < best._score):
				best = s
		if best == null:
			break
		best._chosen = true
	for s in sources:
		s.enabled = s._chosen
		if not s._chosen:
			s.energy = s.base_energy
	var boost := 1.0
	if quality != "off":
		boost = clampf(1.0 / maxf(_clamped(ambient).get_luminance(), 0.01), 1.0, 3.0)
	get_tree().set_group(GROUP_GLOW, "self_modulate", Color(boost, boost, boost))

func _assign_glow(center: Vector2) -> void:
	if glow_pool.is_empty():
		return
	var from := player.global_position if player and is_instance_valid(player) else center
	_glow_taken.fill(0)
	for g in glow_pool:
		var best := -1
		var best_d := glow_range
		for i in glow_spots.size():
			if _glow_taken[i] == 0:
				var d := from.distance_to(glow_spots[i])
				if d < best_d:
					best_d = d
					best = i
		g.wanted = best >= 0
		if best >= 0:
			_glow_taken[best] = 1
			g.position = glow_spots[best]

func _view_center() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	return vp.get_canvas_transform().affine_inverse() * (vp.get_visible_rect().size * 0.5)

func enabled_sources() -> int:
	var n := 0
	for s in sources:
		if s.enabled:
			n += 1
	return n

# Debug builds only: F2 cycles full -> simple -> off (not saved).
func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		cycle_quality()
		get_viewport().set_input_as_handled()
