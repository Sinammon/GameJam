extends Node2D
# Mining: per-cell health for the ground TileMapLayer, crack overlay, drops and
# the digging rules. The expedition builds the terrain through place() and
# kind_for(); the swing controller asks pick_target() and calls hit().
#
# Digging rules (kept simple so the player can never get stuck):
# - Top-down only: you can only dig the top block of a column (the ground stays a
#   height map, no caves or overhangs).
# - A column can be dug at most MAX_DIG_DEPTH (4) blocks below its natural surface.
# - The bedrock row (BEDROCK_ROW) never breaks.
# - Protected columns (the hatch and spawn, crates, trees, the Last Stand Pack) can't be dug.
# - Escape rule: a block is only dug if afterwards every column can still be
#   left by steps of at most MAX_CLIMB (2) blocks up, ending on an undug column.
#   The player jumps ~2.7 blocks, so 2-block steps are always climbable.
#
# Tile pictures: source 0 = tiles_outside.png (surface + dirt), source 1 =
# tiles_ore.png (4x2: scrap ore, concrete, circuit vein, bedrock / planks, pipe,
# bones, toxic crystal). A missing sheet is drawn here as a placeholder image.
# Cracks: tiles_crack.png (4 stages left to right) or drawn lines.

signal block_broken(cell: Vector2i, kind: String)

const TILE := 16
const BEDROCK_ROW := 20          # last row; never breaks
const MAX_DIG_DEPTH := 4         # blocks below the natural surface, per column
const MAX_CLIMB := 2             # largest step (blocks) the escape rule allows
const REACH := 34.0              # px from the player's chest to a block centre
const PICK_DAMAGE := 1.0         # per pickaxe hit, x (1 + dig_speed_bonus)

const OUTSIDE_TEX := "res://art/world_clean/tiles_outside.png"
const ORE_TEX := "res://art/world_clean/tiles_ore.png"   # optional art # lint:ignore res_path
const CRACK_TEX := "res://art/world_clean/tiles_crack.png"   # optional art # lint:ignore res_path

# kind -> [source, atlas coords] (dirt/surface use the expedition's art_tile()).
const ORE_ATLAS := {
	"scrap_ore": Vector2i(0, 0), "concrete": Vector2i(1, 0), "circuits": Vector2i(2, 0), "bedrock": Vector2i(3, 0),
	"planks": Vector2i(0, 1), "pipe": Vector2i(1, 1), "bones": Vector2i(2, 1), "toxic": Vector2i(3, 1),
}
# kind -> hits of hp (pickaxe hits at bonus 0)
const HP := {
	"surface": 3.0, "dirt": 3.0, "planks": 3.0, "bones": 3.0, "scrap_ore": 4.0, "pipe": 4.0,
	"concrete": 5.0, "toxic": 5.0, "circuits": 6.0,
}
# kind -> [item, chance]; the item count is 1 x loot multiplier (at least 1).
const DROPS := {
	"surface": ["scrap", 0.08], "dirt": ["scrap", 0.08], "scrap_ore": ["scrap", 1.0], "pipe": ["scrap", 1.0],
	"concrete": ["concrete", 1.0], "circuits": ["circuits", 1.0], "planks": ["wood", 1.0], "bones": ["scrap", 0.25],
}
const CHIP_KIND := {"concrete": "concrete", "circuits": "stone", "toxic": "toxic", "scrap_ore": "scrap", "pipe": "scrap", "planks": "wood"}

const PickupScript := preload("res://actors/pickup.gd")
const Chips := preload("res://actors/chips.gd")

var ground: TileMapLayer
var cols := 0
var surface_rows: Array[int] = []   # natural surface (never changes)
var floor_rows: Array[int] = []     # current top solid row per column
var kinds := {}                     # Vector2i -> kind
var damage := {}                    # Vector2i -> damage taken so far
var protected_cols := {}            # col -> true
var dig_damage := PICK_DAMAGE
var loot_mult := 1.0
var player: Node = null
var _crack_tex: Texture2D = null
var _outside_tex: Texture2D = null  # for the dark back wall behind dug-out blocks
var _back: Node2D                   # draws the back wall (behind the ground, in front of the sky)
var dug := {}                       # Vector2i -> true for every dug-out block
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	z_index = 1
	_back = Node2D.new()
	_back.name = "BackWall"
	_back.z_as_relative = false
	_back.z_index = -2
	add_child(_back)
	_back.draw.connect(_draw_back)
	_crack_tex = _atlas(CRACK_TEX, Vector2i(4, 1))

func setup(layer: TileMapLayer, surface: Array[int], p: Node, mult: float, dig_bonus: float) -> void:
	ground = layer
	cols = surface.size()
	surface_rows = surface.duplicate()
	floor_rows = surface.duplicate()
	player = p
	loot_mult = mult
	dig_damage = PICK_DAMAGE * (1.0 + maxf(dig_bonus, -0.5))

# --- tileset -----------------------------------------------------------------

# Builds the ground TileSet (every tile has a full collision square). Returns true
# if tiles_outside.png art was used (false = drawn placeholder colours).
func build_tileset() -> bool:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	var art := Art.texture(OUTSIDE_TEX) != null
	_outside_tex = _atlas(OUTSIDE_TEX, Vector2i(4, 2))
	if _outside_tex == null:
		_outside_tex = ImageTexture.create_from_image(_placeholder_outside())
	var ore := _atlas(ORE_TEX, Vector2i(4, 2))
	if ore == null:
		var dirt := _outside_tex.get_image()   # may be null where GPU readback is missing
		if dirt == null or dirt.is_empty():
			dirt = _placeholder_outside()
		dirt.convert(Image.FORMAT_RGBA8)
		ore = ImageTexture.create_from_image(_placeholder_ore(dirt.get_region(Rect2i(0, 0, TILE, TILE))))
	_add_source(ts, _outside_tex)
	_add_source(ts, ore)
	ground.tile_set = ts
	return art

# A sheet of cells x 16 px tiles. Used as is when it has exactly that size (no
# GPU readback needed, safe on the web), else read back and scaled to fit.
# null if the file is missing or can't be read.
func _atlas(path: String, cells: Vector2i) -> Texture2D:
	var tex := Art.texture(path)
	if tex == null:
		return null
	var want := cells * TILE
	if Vector2i(tex.get_size()) == want:
		return tex
	var img := Art.image(path)
	if img == null:
		return null
	img.resize(want.x, want.y, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)

func _add_source(ts: TileSet, tex: Texture2D) -> void:
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src)
	var square := PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)])
	for y in 2:
		for x in 4:
			var c := Vector2i(x, y)
			src.create_tile(c)
			var td := src.get_tile_data(c, 0)
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, square)

# 4x2 colours in the tiles_outside layout: dirt, grass, -, asphalt / -, gravel, scrap, toxic.
func _placeholder_outside() -> Image:
	var img := Image.create(TILE * 4, TILE * 2, false, Image.FORMAT_RGBA8)
	var cols_ := [Color(0.42, 0.3, 0.2), Color(0.35, 0.42, 0.22), Color(0.4, 0.38, 0.35), Color(0.25, 0.25, 0.27),
		Color(0.42, 0.3, 0.2), Color(0.45, 0.43, 0.4), Color(0.45, 0.35, 0.28), Color(0.35, 0.45, 0.2)]
	for i in 8:
		var r := Rect2i((i % 4) * TILE, floori(i / 4.0) * TILE, TILE, TILE)
		img.fill_rect(r, cols_[i])
		img.fill_rect(Rect2i(r.position, Vector2i(TILE, 2)), (cols_[i] as Color).lightened(0.15))
	return img

# Draws the 8 ore tiles on the dirt tile so they match the ground.
func _placeholder_ore(dirt: Image) -> Image:
	var img := Image.create(TILE * 4, TILE * 2, false, Image.FORMAT_RGBA8)
	var stone := Color(0.2, 0.2, 0.23)
	for kind in ORE_ATLAS:
		var o: Vector2i = ORE_ATLAS[kind] * TILE
		if kind in ["circuits", "bedrock", "toxic"]:
			img.fill_rect(Rect2i(o, Vector2i(TILE, TILE)), Color(0.22, 0.24, 0.3) if kind == "bedrock" else stone)
		else:
			img.blit_rect(dirt, Rect2i(0, 0, TILE, TILE), o)
		match kind:
			"scrap_ore":
				for p in [Vector2i(2, 3), Vector2i(9, 2), Vector2i(5, 9), Vector2i(11, 11)]:
					img.fill_rect(Rect2i(o + p, Vector2i(4, 2)), Color(0.6, 0.38, 0.22))
					img.fill_rect(Rect2i(o + p + Vector2i(0, 2), Vector2i(3, 1)), Color(0.55, 0.55, 0.58))
			"concrete":
				for p in [Vector2i(1, 2), Vector2i(8, 5), Vector2i(3, 10)]:
					img.fill_rect(Rect2i(o + p, Vector2i(5, 4)), Color(0.72, 0.72, 0.7))
			"circuits":
				img.fill_rect(Rect2i(o + Vector2i(3, 4), Vector2i(9, 6)), Color(0.15, 0.55, 0.25))
				for p in [Vector2i(4, 5), Vector2i(7, 7), Vector2i(10, 5)]:
					img.fill_rect(Rect2i(o + p, Vector2i(1, 1)), Color(0.95, 0.8, 0.3))
			"bedrock":
				for p in [Vector2i(3, 3), Vector2i(10, 6), Vector2i(6, 12)]:
					img.fill_rect(Rect2i(o + p, Vector2i(2, 1)), Color(0.32, 0.34, 0.42))
			"planks":
				img.fill_rect(Rect2i(o + Vector2i(1, 4), Vector2i(13, 3)), Color(0.55, 0.38, 0.2))
				img.fill_rect(Rect2i(o + Vector2i(3, 10), Vector2i(12, 3)), Color(0.5, 0.34, 0.18))
			"pipe":
				img.fill_rect(Rect2i(o + Vector2i(0, 6), Vector2i(16, 4)), Color(0.55, 0.32, 0.2))
				img.fill_rect(Rect2i(o + Vector2i(0, 6), Vector2i(16, 1)), Color(0.7, 0.45, 0.3))
			"bones":
				img.fill_rect(Rect2i(o + Vector2i(3, 6), Vector2i(9, 2)), Color(0.85, 0.82, 0.72))
				img.fill_rect(Rect2i(o + Vector2i(2, 5), Vector2i(2, 4)), Color(0.85, 0.82, 0.72))
				img.fill_rect(Rect2i(o + Vector2i(11, 5), Vector2i(2, 4)), Color(0.85, 0.82, 0.72))
			"toxic":
				img.fill_rect(Rect2i(o + Vector2i(6, 3), Vector2i(4, 10)), Color(0.71, 0.89, 0.12))
				img.fill_rect(Rect2i(o + Vector2i(4, 6), Vector2i(8, 4)), Color(0.6, 0.8, 0.1))
	return img

# --- terrain generation --------------------------------------------------------

# What a block below the surface holds. depth: blocks below the natural surface
# (1..), far: 0 at the hatch .. 1 at the edges. Deeper and farther = richer.
# Ores only within dig depth; circuits only deep (2+) and far (> 60% out).
func kind_for(depth: int, far: float, area: int) -> String:
	if depth <= 0:
		return "surface"
	if depth >= MAX_DIG_DEPTH:
		return "dirt"
	var chance := 0.06 + 0.05 * depth + 0.12 * far
	if rng.randf() > chance:
		return "dirt"
	var roll := rng.randf()
	if far > 0.6 and depth >= 2 and roll < 0.25:
		return "circuits"
	roll = rng.randf()
	match area:
		0:   # suburb: buried planks, some scrap, bones
			return "planks" if roll < 0.45 else ("scrap_ore" if roll < 0.75 else ("bones" if roll < 0.9 else "pipe"))
		1:   # market: concrete and pipes
			return "concrete" if roll < 0.45 else ("pipe" if roll < 0.7 else ("scrap_ore" if roll < 0.9 else "planks"))
		_:   # depot: scrap, concrete, toxic crystals
			return "scrap_ore" if roll < 0.4 else ("concrete" if roll < 0.65 else ("toxic" if roll < 0.85 else "pipe"))

# Remembers the kind and sets the tile. dirt/surface use art_coords from tiles_outside.
func place(cell: Vector2i, kind: String, art_coords: Vector2i) -> void:
	kinds[cell] = kind
	if ORE_ATLAS.has(kind):
		ground.set_cell(cell, 1, ORE_ATLAS[kind])
	else:
		ground.set_cell(cell, 0, art_coords)

func protect_col(col: int, radius := 0) -> void:
	for c in range(col - radius, col + radius + 1):
		if c >= 0 and c < cols:
			protected_cols[c] = true

func protect_x(x: float, radius := 0) -> void:
	protect_col(int(x / TILE), radius)

# --- queries -----------------------------------------------------------------------

func floor_y(x: float) -> float:
	var col := clampi(int(x / TILE), 0, cols - 1)
	return float(floor_rows[col] * TILE)

func dug_depth(col: int) -> int:
	return floor_rows[col] - surface_rows[col]

func kind_at(cell: Vector2i) -> String:
	return kinds.get(cell, "")

# Damage stage 0..3 for the crack overlay (-1 = undamaged).
func crack_stage(cell: Vector2i) -> int:
	if not damage.has(cell):
		return -1
	var max_hp: float = HP.get(kind_at(cell), 3.0)
	return clampi(floori(damage[cell] / max_hp * 4.0), 0, 3)

# "" if the block can be dug now, else why not.
func why_not(cell: Vector2i) -> String:
	var kind := kind_at(cell)
	if kind == "":
		return "empty"
	if kind == "bedrock" or cell.y >= BEDROCK_ROW:
		return "bedrock"
	if cell.x < 0 or cell.x >= cols or cell.y != floor_rows[cell.x]:
		return "buried"
	if protected_cols.has(cell.x):
		return "protected"
	if cell.y - surface_rows[cell.x] >= MAX_DIG_DEPTH:
		return "too deep"
	var floors := floor_rows.duplicate()
	floors[cell.x] += 1
	if not escapable(floors):
		return "unsafe"
	return ""

func can_mine(cell: Vector2i) -> bool:
	return why_not(cell) == ""

# True if from every column you can walk/jump (steps up of <= MAX_CLIMB) to an
# undug column. Falling down is always possible, so it is a reverse flood fill.
func escapable(floors: Array) -> bool:
	var ok := []
	ok.resize(cols)
	ok.fill(false)
	var todo: Array[int] = []
	for c in cols:
		if floors[c] <= surface_rows[c]:
			ok[c] = true
			todo.append(c)
	while not todo.is_empty():
		var b: int = todo.pop_back()
		for a in [b - 1, b + 1]:
			# from a you can step onto b if b's top is at most MAX_CLIMB rows above a's
			if a >= 0 and a < cols and not ok[a] and floors[b] >= floors[a] - MAX_CLIMB:
				ok[a] = true
				todo.append(a)
	return not ok.has(false)

func in_reach(from: Vector2, cell: Vector2i) -> bool:
	return from.distance_to(Vector2(cell) * TILE + Vector2(8, 8)) <= REACH

# Block to dig: the column under the mouse (when aiming with the mouse), else
# the column in front, else the one under the feet. Returns [cell, reason]:
# reason "" = dig it; otherwise cell is the best candidate and why it can't be dug.
func pick_target(feet: Vector2, facing: float, aim: Variant) -> Array:
	var chest := feet + Vector2(0, -12)
	var col := int(feet.x / TILE)
	var cands: Array[int] = []
	if aim is Vector2:
		cands.append(int(aim.x / TILE))
	cands.append_array([col + (1 if facing >= 0.0 else -1), col])
	var first := []
	for c in cands:
		if c < 0 or c >= cols:
			continue
		var cell := Vector2i(c, floor_rows[c])
		if not in_reach(chest, cell):
			continue
		var why := why_not(cell)
		if why == "":
			return [cell, ""]
		if first.is_empty():
			first = [cell, why]
	return first if not first.is_empty() else [Vector2i(-1, -1), "reach"]

# --- digging -----------------------------------------------------------------------

# One pickaxe hit. Returns true if the block broke.
func hit(cell: Vector2i, amount := -1.0) -> bool:
	if not can_mine(cell):
		return false
	if amount < 0.0:
		amount = dig_damage
	var kind := kind_at(cell)
	damage[cell] = damage.get(cell, 0.0) + amount
	var at := Vector2(cell) * TILE + Vector2(8, 4)
	Chips.burst(get_parent(), at, CHIP_KIND.get(kind, "dirt"), 4)
	if damage[cell] + 0.001 < HP.get(kind, 3.0):
		queue_redraw()
		return false
	_break(cell, kind)
	return true

func _break(cell: Vector2i, kind: String) -> void:
	damage.erase(cell)
	kinds.erase(cell)
	ground.erase_cell(cell)
	floor_rows[cell.x] = cell.y + 1
	dug[cell] = true
	queue_redraw()
	_back.queue_redraw()
	Chips.burst(get_parent(), Vector2(cell) * TILE + Vector2(8, 8), CHIP_KIND.get(kind, "dirt"), 8)
	var drop: Array = DROPS.get(kind, [])
	if not drop.is_empty() and rng.randf() < drop[1]:
		for i in maxi(1, roundi(loot_mult)):
			spawn_pickup(drop[0], Vector2(cell) * TILE + Vector2(8, 8))
	block_broken.emit(cell, kind)

func spawn_pickup(item: String, at: Vector2) -> Node2D:
	var p: Node2D = PickupScript.new()
	p.position = at
	get_parent().add_child(p)
	p.setup(item, player, floor_y, Vector2(randf_range(-20, 20), -80))
	return p

# --- back wall and crack overlay ----------------------------------------------------

# A dark copy of the dirt behind every dug-out block, so holes read as holes
# (the background art would otherwise show its painted ground there).
func _draw_back() -> void:
	for cell in dug:
		var r := Rect2(Vector2(cell) * TILE, Vector2(TILE, TILE))
		if _outside_tex:
			_back.draw_texture_rect_region(_outside_tex, r, Rect2(0, 0, TILE, TILE), Color(0.32, 0.27, 0.27))
		else:
			_back.draw_rect(r, Color(0.14, 0.1, 0.08))

func _draw() -> void:
	for cell in damage:
		var stage := crack_stage(cell)
		var o := Vector2(cell) * TILE
		if _crack_tex:
			draw_texture_rect_region(_crack_tex, Rect2(o, Vector2(TILE, TILE)), Rect2(stage * TILE, 0, TILE, TILE))
			continue
		var dark := Color(0.08, 0.07, 0.12, 0.9)
		var light := Color(0.8, 0.8, 0.8, 0.6)
		var lines := [[Vector2(8, 3), Vector2(6, 8)], [Vector2(6, 8), Vector2(10, 12)],
			[Vector2(6, 8), Vector2(2, 10)], [Vector2(10, 12), Vector2(14, 14)],
			[Vector2(8, 3), Vector2(13, 5)], [Vector2(2, 10), Vector2(3, 15)], [Vector2(13, 5), Vector2(12, 9)]]
		for i in mini(lines.size(), 2 + stage * 2):
			draw_line(o + lines[i][0], o + lines[i][1], dark, 1.0)
			draw_line(o + lines[i][0] + Vector2(1, 0), o + lines[i][1] + Vector2(1, 0), light, 1.0)
