extends CanvasLayer
# Expedition HUD, icons only (tiny numbers, no words):
#   top-left: hearts; V3: thirst and hunger meters (water drop / food icon, bar, carried count)
#   under the radiation bar: location name and today's goal (tiny)
#   top-centre: geiger counter (ui_geiger.png, 5 frames = radiation level 0..4) + radiation bar
#   top-right: backpack icon (icon_backpack_<tier>.png, tier from GSBridge) + used/limit
#   bottom-left: 5-slot hotbar; Tab opens the backpack grid above it
#   screen edge: "go home" arrow pointing at the hatch
#   radiation vignette pulse at 60% / 85% / 100%, red flash on damage
# Every picture is optional: a missing file is drawn as a simple coloured shape.
# Drawing happens in the Draw control's draw signal; it is redrawn every frame.

const RadiationScript := preload("res://scenes/radiation.gd")

const ART := "res://art/world_clean/%s.png"
# Tool icons: try these files in order, else a drawn placeholder.
const TOOL_ICONS := {
	"axe": ["icon_tool_axe", "icon_axe"],
	"pickaxe": ["icon_tool_pickaxe", "icon_pickaxe"],
	"flashlight": ["icon_tool_flashlight", "icon_flashlight"],
	"canteen": ["icon_tool_canteen", "icon_canteen", "icon_water"],
	"medkit": ["icon_tool_medkit", "icon_medkit"],
}
const ITEM_COLORS := {
	"wood": Color(0.6, 0.4, 0.2), "concrete": Color(0.65, 0.65, 0.62), "scrap": Color(0.55, 0.5, 0.45),
	"circuits": Color(0.3, 0.75, 0.4), "water": Color(0.35, 0.6, 0.95), "food": Color(0.85, 0.55, 0.3),
	"raw_meat": Color(0.85, 0.3, 0.3), "mushroom": Color(0.9, 0.85, 0.7), "dirty_water": Color(0.4, 0.5, 0.35),
	"canned_food": Color(0.75, 0.75, 0.8), "bandage": Color(0.95, 0.95, 0.9), "radio_part": Color(0.95, 0.6, 0.2),
}
const METER_COLORS := {"water": Color(0.35, 0.6, 0.95), "food": Color(0.9, 0.6, 0.3)}
const DEATH_TEXT := {
	"radiation": "Radiation sickness took you.",
	"zombie": "A zombie got you.",
	"hunger": "You starved out there.",
	"thirst": "Thirst took you.",
	"sickness": "Sickness took you.",
}
const HOME_ARROW_DIST := 720.0     # 1.5 screens from the hatch
const CELL := 20
const STEP := 22
const GRID_COLS := 6
const YELLOW := Color(0.95, 0.76, 0.31)

@onready var draw_node: Control = $Draw
@onready var vignette: TextureRect = $Vignette
@onready var hurt_flash: ColorRect = $HurtFlash
@onready var msg_label: Label = $MessageLabel
@onready var hint_label: Label = $HintLabel
@onready var fade: ColorRect = $Fade
@onready var death_box: Control = $DeathBox

var player: Node = null
var inventory: Node = null
var radiation: RefCounted = null
var hatch_x := 0.0
var backpack_tier := 1              # GSBridge.backpack_tier(), read once in setup
var home_arrow_visible := false     # read by tests
var survival: RefCounted = null     # V3: scenes/survival.gd (set by the expedition)
var goal_text := ""                 # V3: today's goal line (GSBridge.goal_text)
var location_name := ""

var _tex := {}                      # path -> Texture2D or null (cached)
var _font: Font
var _time := 0.0
var _msg_tween: Tween
var _flash_tween: Tween

func _ready() -> void:
	_font = ThemeDB.fallback_font
	draw_node.draw.connect(_draw_hud)
	vignette.texture = _vignette_texture()
	msg_label.text = ""
	hint_label.text = ""

func setup(p: Node, inv: Node, rad: RefCounted, hx: float) -> void:
	player = p
	inventory = inv
	radiation = rad
	hatch_x = hx
	backpack_tier = GSBridge.backpack_tier()
	p.hurt.connect(func(_a: int, _s: String) -> void: flash_hurt())

func _process(delta: float) -> void:
	_time += delta
	_update_vignette()
	draw_node.queue_redraw()

# --- messages ----------------------------------------------------------------

func show_message(text: String) -> void:
	msg_label.text = text
	msg_label.modulate.a = 1.0
	if _msg_tween:
		_msg_tween.kill()
	_msg_tween = create_tween()
	_msg_tween.tween_property(msg_label, "modulate:a", 0.0, 0.6).set_delay(2.0)

func set_hint(text: String) -> void:
	hint_label.text = text

# One-time in-world hint (remembered in the settings file through SettingsStore,
# if that class exists; without it the hint shows once per expedition).
# Returns true if it was shown.
var _hints_local := {}
func hint_once(id: String, text: String) -> bool:
	var first := not _hints_local.has(id)
	_hints_local[id] = true
	var store: Variant = _settings_store()
	if store != null:
		first = store.hint_once(id)
	if first:
		show_message(text)
	return first

static func _settings_store() -> Variant:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == "SettingsStore":
			return load(c["path"])
	return null

# Icon + one line over the fade, saying why you died.
func show_death(reason: String) -> void:
	hint_label.text = ""
	msg_label.text = ""
	var icon := _t("icon_radiation" if reason == "radiation" else "icon_health")
	($DeathBox/Icon as TextureRect).texture = icon
	($DeathBox/Label as Label).text = DEATH_TEXT.get(reason, "You collapsed.")
	death_box.visible = true
	death_box.modulate.a = 0.0
	create_tween().tween_property(death_box, "modulate:a", 1.0, 0.4)

func flash_hurt() -> void:
	if _flash_tween:
		_flash_tween.kill()
	hurt_flash.color.a = 0.35
	_flash_tween = create_tween()
	_flash_tween.tween_property(hurt_flash, "color:a", 0.0, 0.3)

# --- vignette ------------------------------------------------------------------

func _vignette_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.3, 1.0, 0.25, 0.0))
	g.set_color(1, Color(0.3, 1.0, 0.25, 0.9))
	g.add_point(0.55, Color(0.3, 1.0, 0.25, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.05, 1.05)
	t.width = 96
	t.height = 54
	return t

func _update_vignette() -> void:
	if radiation == null:
		return
	var lvl: int = radiation.level()
	var base := 0.0
	var amp := 0.0
	var speed := 3.0
	match lvl:
		2:
			base = 0.15
			amp = 0.2
		3:
			base = 0.3
			amp = 0.3
			speed = 5.0
		4:
			base = 0.5
			amp = 0.35
			speed = 7.0
	vignette.modulate.a = base + amp * (0.5 + 0.5 * sin(_time * speed))

# --- drawing -------------------------------------------------------------------

func _t(file: String) -> Texture2D:
	var path := ART % file
	if not _tex.has(path):
		_tex[path] = Art.texture(path)
	return _tex[path]

func _num(pos: Vector2, text: String, color := Color(0.95, 0.95, 0.9), align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_node.draw_string(_font, pos + Vector2(1, 1), text, align, width, UIKit.fs(8), Color(0, 0, 0, 0.8))
	draw_node.draw_string(_font, pos, text, align, width, UIKit.fs(8), color)

func _draw_hud() -> void:
	if player == null:
		return
	_draw_hearts(Vector2(6, 5))
	_draw_supplies(Vector2(6, 22))
	_draw_radiation(Vector2(170, 4))
	_draw_backpack_icon(Vector2(458, 4))
	_draw_hotbar(Vector2(6, 270 - 6 - CELL))
	if inventory and inventory.backpack_open:
		_draw_backpack_grid()
	_draw_home_arrow()

func _draw_hearts(at: Vector2) -> void:
	var hp: int = player.health.hp
	var max_hp: int = player.health.max_hp
	var tex := _t("icon_health")
	var n := ceili(max_hp / 2.0)
	for i in n:
		var p := at + Vector2(i * 17, 0)
		var fill := clampi(hp - i * 2, 0, 2)   # 0 empty, 1 half, 2 full
		if tex:
			var sz := tex.get_size()
			draw_node.draw_texture(tex, p, Color(0.15, 0.12, 0.12, 0.8))
			if fill > 0:
				var w := sz.x if fill == 2 else floorf(sz.x / 2.0)
				draw_node.draw_texture_rect_region(tex, Rect2(p, Vector2(w, sz.y)), Rect2(Vector2.ZERO, Vector2(w, sz.y)))
		else:
			draw_node.draw_rect(Rect2(p, Vector2(14, 12)), Color(0.2, 0.1, 0.1, 0.8))
			if fill > 0:
				draw_node.draw_rect(Rect2(p, Vector2(14 if fill == 2 else 7, 12)), Color(0.9, 0.2, 0.25))

func _draw_icon(file: String, at: Vector2, fallback: Color, size := Vector2(10, 12)) -> float:
	var tex := _t(file)
	if tex:
		draw_node.draw_texture(tex, at)
		return tex.get_width()
	draw_node.draw_rect(Rect2(at + Vector2(0, 2), size), fallback)
	return size.x

# V3: two meter rows (thirst, hunger): icon, bar 0..100, the count carried that fills it.
# Low (< 25) bars blink; empty ones are red (health drains).
func _draw_supplies(at: Vector2) -> void:
	var y := at.y
	for k in ["water", "food"]:
		var icon := _t("icon_" + k)
		if icon:
			var s := minf(12.0 / maxf(icon.get_height(), 1.0), 1.0)
			draw_node.draw_texture_rect(icon, Rect2(Vector2(at.x, y), (icon.get_size() * s).floor()), false)
		else:
			draw_node.draw_rect(Rect2(Vector2(at.x, y + 2), Vector2(10, 10)), ITEM_COLORS[k])
		if survival != null:
			var v: float = survival.get_meter(k)
			var bar := Rect2(Vector2(at.x + 15, y + 4), Vector2(48, 5))
			draw_node.draw_rect(bar.grow(1), Color(0.05, 0.05, 0.05, 0.85))
			var col: Color = METER_COLORS[k]
			if v <= 0.0:
				col = Color(0.9, 0.2, 0.2, 0.6 + 0.4 * sin(_time * 8.0))
			elif v < 25.0:
				col.a = 0.55 + 0.45 * sin(_time * 6.0)
			draw_node.draw_rect(Rect2(bar.position, Vector2(bar.size.x * v / 100.0, bar.size.y)), col)
		var carried := 0
		for item in (["water", "dirty_water"] if k == "water" else ["food", "canned_food", "mushroom", "raw_meat"]):
			carried += int(player.items.get(item, 0))
		_num(Vector2(at.x + 67, y + 11), str(carried))
		y += 13
	_num(Vector2(at.x, y + 9), "Q eat  R drink", Color(1, 1, 1, 0.45))

func _draw_radiation(at: Vector2) -> void:
	if radiation == null:
		return
	var v: float = radiation.value
	var lvl: int = radiation.level()
	var col: Color = RadiationScript.color(v)
	# geiger counter: 5-frame strip (24x24 frames, drawn 1:1) if present, else the radiation icon tinted by level
	var strip := _t("ui_geiger")
	var bar_x := 20.0
	if strip:
		var fw := floorf(strip.get_width() / 5.0)
		var fh := float(strip.get_height())
		var s := minf(24.0 / fh, 1.0)
		var shake := Vector2(roundf(sin(_time * 40.0)), 0) if lvl >= 4 else Vector2.ZERO
		draw_node.draw_texture_rect_region(strip, Rect2(at + Vector2(0, -2) + shake, Vector2(fw, fh) * s), Rect2(fw * clampi(lvl, 0, 4), 0, fw, fh))
		bar_x = ceilf(fw * s) + 4.0
	else:
		var icon := _t("icon_radiation")
		var shake := Vector2(sin(_time * 40.0), 0) * (0.0 if lvl < 3 else 1.0)
		if icon:
			draw_node.draw_texture(icon, at + shake, Color(1, 1, 1).lerp(col, 0.5))
		else:
			draw_node.draw_circle(at + Vector2(8, 8) + shake, 7, col)
		for i in lvl:   # tick marks = state
			draw_node.draw_rect(Rect2(at + Vector2(i * 4, 17), Vector2(3, 2)), col)
	# bar
	var bar := Rect2(at + Vector2(bar_x, 4), Vector2(120, 8))
	draw_node.draw_rect(bar.grow(1), Color(0.05, 0.05, 0.05, 0.85))
	draw_node.draw_rect(Rect2(bar.position, Vector2(bar.size.x * v / 100.0, bar.size.y)), col)
	for mark in RadiationScript.WARN_AT:   # 60 / 85 notches
		if mark < 100.0:
			draw_node.draw_rect(Rect2(bar.position + Vector2(bar.size.x * mark / 100.0, -1), Vector2(1, bar.size.y + 2)), Color(1, 1, 1, 0.5))
	_num(at + Vector2(bar_x + 124, 12), "%d" % int(v), col)
	# V3: where you are and today's goal, tiny, under the bar
	var line := goal_text
	var cut := line.find(" (")
	if cut > 0:
		line = line.left(cut) + "."   # drop "(Utility Room)" hints in the tiny HUD line
	while line.length() > 4 and _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.fs(7)).x > 184.0:
		line = line.left(line.length() - 2) + "~"
		line = line.left(line.length() - 1)
	if line != "":
		draw_node.draw_string(_font, at + Vector2(bar_x - 22, 26), line, HORIZONTAL_ALIGNMENT_CENTER, 186, UIKit.fs(7), Color(0, 0, 0, 0.8))
		draw_node.draw_string(_font, at + Vector2(bar_x - 23, 25), line, HORIZONTAL_ALIGNMENT_CENTER, 186, UIKit.fs(7), Color(0.9, 0.88, 0.75))

func _draw_backpack_icon(at: Vector2) -> void:
	# tier icon (24x24, drawn 1:1, right-aligned at the screen edge), else the generic pack (16 px)
	var tex := _t("icon_backpack_%d" % backpack_tier)
	var box := 24.0
	if tex == null:
		box = 16.0
		tex = _t("icon_backpack")
		if tex == null:
			tex = _t("obj_last_stand_pack")
	var full: bool = player.capacity_left() <= 0
	var tint := Color(1, 0.6, 0.5) if full else Color(1, 1, 1)
	var right := at.x + 16.0
	if tex:
		var s := minf(box / maxf(tex.get_width(), tex.get_height()), 1.0)
		var sz := (tex.get_size() * s).floor()
		var pos := Vector2(right - sz.x, at.y + floorf((box - sz.y) / 2.0) - (2.0 if box > 16.0 else 0.0))
		draw_node.draw_texture_rect(tex, Rect2(pos, sz), false, tint)
		right = pos.x
	else:
		draw_node.draw_rect(Rect2(at + Vector2(2, 2), Vector2(12, 14)), Color(0.75, 0.6, 0.25) * tint)
		right = at.x
	_num(Vector2(right - 44, at.y + 12), "%d/%d" % [player.total_items(), player.carry_limit],
		Color(1, 0.5, 0.4) if full else Color(0.95, 0.95, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, 42)

func _slot(r: Rect2, selected := false, locked := false) -> void:
	var tex := _t("ui_slot")
	if tex:
		draw_node.draw_texture_rect(tex, r, false, Color(0.6, 0.6, 0.6) if locked else Color(1, 1, 1))
	else:
		draw_node.draw_rect(r, Color(0.12, 0.13, 0.15, 0.85))
		draw_node.draw_rect(r, Color(0.45, 0.47, 0.5), false, 1.0)
	if selected:
		draw_node.draw_rect(r.grow(1), YELLOW, false, 2.0)
	if locked:
		var lock := _t("icon_locked")
		if lock:
			draw_node.draw_texture(lock, r.position + (r.size - lock.get_size()) / 2.0, Color(1, 1, 1, 0.7))
		else:
			draw_node.draw_rect(Rect2(r.position + Vector2(6, 8), Vector2(8, 7)), Color(0.5, 0.5, 0.5))

func _draw_tool(tool_id: String, r: Rect2) -> void:
	for file in TOOL_ICONS[tool_id]:
		var tex := _t(file)
		if tex:
			var s := minf(16.0 / maxf(tex.get_width(), tex.get_height()), 1.0)
			var sz := (tex.get_size() * s).floor()
			draw_node.draw_texture_rect(tex, Rect2(r.position + ((r.size - sz) / 2.0).floor(), sz), false)
			return
	var c := r.position + r.size / 2.0
	match tool_id:   # simple drawn placeholders
		"axe":
			draw_node.draw_line(c + Vector2(-5, 6), c + Vector2(4, -5), Color(0.6, 0.4, 0.2), 2.0)
			draw_node.draw_rect(Rect2(c + Vector2(1, -7), Vector2(6, 5)), Color(0.75, 0.75, 0.78))
		"pickaxe":
			draw_node.draw_line(c + Vector2(-5, 6), c + Vector2(3, -4), Color(0.6, 0.4, 0.2), 2.0)
			draw_node.draw_line(c + Vector2(-3, -6), c + Vector2(7, 0), Color(0.75, 0.75, 0.78), 2.0)
		"flashlight":
			draw_node.draw_rect(Rect2(c + Vector2(-6, -2), Vector2(9, 4)), Color(0.3, 0.3, 0.35))
			draw_node.draw_rect(Rect2(c + Vector2(3, -3), Vector2(3, 6)), YELLOW)
		"canteen":
			draw_node.draw_circle(c + Vector2(0, 1), 5, Color(0.35, 0.5, 0.35))
		"medkit":
			draw_node.draw_rect(Rect2(c - Vector2(6, 5), Vector2(12, 10)), Color(0.9, 0.9, 0.88))
			draw_node.draw_rect(Rect2(c - Vector2(1, 4), Vector2(2, 8)), Color(0.85, 0.2, 0.2))
			draw_node.draw_rect(Rect2(c - Vector2(4, 1), Vector2(8, 2)), Color(0.85, 0.2, 0.2))

func _draw_hotbar(at: Vector2) -> void:
	if inventory == null:
		return
	for i in inventory.TOOLS.size():
		var r := Rect2(at + Vector2(i * STEP, 0), Vector2(CELL, CELL))
		_slot(r, i == inventory.selected)
		_draw_tool(inventory.TOOLS[i], r)
		_num(r.position + Vector2(2, 8), str(i + 1), Color(1, 1, 1, 0.6))

func _draw_backpack_grid() -> void:
	var total: int = inventory.slots_total()
	var unlocked: int = inventory.slots_unlocked()
	var rows := ceili(float(total) / GRID_COLS)
	var origin := Vector2(6, 270 - 6 - CELL - 8 - rows * STEP)
	var panel := Rect2(origin - Vector2(4, 4), Vector2(GRID_COLS * STEP + 6, rows * STEP + 6))
	draw_node.draw_rect(panel, Color(0.06, 0.07, 0.08, 0.85))
	draw_node.draw_rect(panel, Color(0.4, 0.42, 0.45), false, 1.0)
	var stacks: Array = inventory.stacks()
	for i in total:
		var r := Rect2(origin + Vector2((i % GRID_COLS) * STEP, floori(i / float(GRID_COLS)) * STEP), Vector2(CELL, CELL))
		_slot(r, false, i >= unlocked)
		if i < stacks.size():
			var kind: String = stacks[i][0]
			var tex := _t("icon_" + kind)
			if tex:
				draw_node.draw_texture(tex, r.position + ((r.size - tex.get_size()) / 2.0).floor())
			else:
				draw_node.draw_rect(Rect2(r.position + Vector2(5, 5), Vector2(10, 10)), ITEM_COLORS.get(kind, Color.WHITE))
			_num(r.position + Vector2(0, 19), str(int(stacks[i][1])), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT, CELL - 1)
	_num(panel.position + Vector2(panel.size.x + 4, 10), "%d/%d" % [inventory.used(), unlocked])

# Arrow at the screen edge towards the hatch when far away or at 60%+ radiation.
func _draw_home_arrow() -> void:
	var dx: float = hatch_x - player.global_position.x
	var rad_high: bool = radiation != null and radiation.value >= RadiationScript.WARN_AT[0]
	var screen_x: float = (draw_node.get_viewport().get_canvas_transform() * Vector2(hatch_x, 0)).x
	var on_screen := screen_x > 8.0 and screen_x < 472.0
	home_arrow_visible = not player.dead and (absf(dx) > HOME_ARROW_DIST or (rad_high and not on_screen))
	if not home_arrow_visible:
		return
	var dir := 1.0 if dx > 0.0 else -1.0
	var pos := Vector2(472.0 if dir > 0.0 else 8.0, 135.0)
	var a := 0.55 + 0.45 * sin(_time * (8.0 if rad_high else 4.0))
	var col := Color(1, 1, 1, a).lerp(Color(0.5, 1.0, 0.4, a), 0.6 if rad_high else 0.0)
	var marker := _t("ui_markers")
	if marker:   # first square frame of the markers sheet, drawn as "points right"
		var h := float(marker.get_height())
		var s := minf(16.0 / h, 1.0)
		draw_node.draw_set_transform(pos, 0.0, Vector2(dir * s, s))
		draw_node.draw_texture_rect_region(marker, Rect2(Vector2(-h, -h / 2.0), Vector2(h, h)), Rect2(0, 0, h, h), col)
		draw_node.draw_set_transform(Vector2.ZERO)
	else:
		var tip := pos
		var back := pos - Vector2(dir * 10.0, 0)
		draw_node.draw_colored_polygon(PackedVector2Array([tip, back + Vector2(0, -7), back + Vector2(0, 7)]), col)
		draw_node.draw_rect(Rect2(minf(back.x, back.x - dir * 5.0), back.y - 2.0, 5.0, 4.0), col)
	_num(Vector2(pos.x - (40.0 if dir > 0.0 else -14.0), pos.y + 18.0), "%d" % int(absf(dx) / 16.0), col)
