extends Control
# Bounce back: you wake up on your cot and pick one Scar (a permanent perk) out of up to 3.
# Art: the survivor getting up (survivor_wakeup frames played backwards) and scar_<id> icons.

const SCAR_ICONS := {"thick_skin": "scar_thick_skin", "scavenger": "scar_scavenger",
		"light_feet": "scar_light_feet", "iron_gut": "scar_iron_gut", "steady": "scar_steady"}

var _wake: TextureRect
var _wake_frames: Array[Texture2D] = []
var _wake_i := 0

func _ready() -> void:
	UIKit.backdrop(self, "characters_clean/game_over", UIKit.BG, 0.3)
	var box := UIKit.center_column(self, 6)
	_add_wakeup(box)
	box.add_child(UIKit.outlined("YOU WAKE UP ON YOUR COT", 16, UIKit.ACCENT))
	box.add_child(UIKit.outlined("Lost 1 bounce. Bounces left: %d" % GameState.bounces, 10, UIKit.BAD))
	box.add_child(UIKit.outlined("Every fall leaves a scar. Choose one:", 9, UIKit.TEXT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var choices: Array[String] = GameState.scar_choices(3)
	if choices.is_empty():
		GameState.continue_after_scar.call_deferred()
		return
	for id in choices:
		var s: Dictionary = GameState.SCARS[id]
		var card := UIKit.set_click_sfx(UIKit.button("%s\n%s" % [s.name, s.desc], Vector2(130, 76), 9), "ui_confirm")
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var icon := UIKit.tex("world_clean/" + str(SCAR_ICONS.get(id, "")))
		if icon != null:
			card.icon = icon
			card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		else:
			card.text = "%s\n\n%s" % [s.name, s.desc]
		card.pressed.connect(_pick.bind(id))
		row.add_child(card)

# Lying on the floor -> standing up, at 2x, then it stays standing.
func _add_wakeup(box: VBoxContainer) -> void:
	for i in [3, 2, 1, 0]:
		var t := UIKit.tex("characters_clean/survivor_wakeup_%d" % i)
		if t != null:
			_wake_frames.append(t)
	if _wake_frames.is_empty():
		return
	_wake = UIKit.picture("characters_clean/survivor_wakeup_3", 2)
	_wake.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_wake)
	var timer := Timer.new()
	timer.wait_time = 0.45
	timer.timeout.connect(_next_wake_frame.bind(timer))
	add_child(timer)
	timer.start()

func _next_wake_frame(timer: Timer) -> void:
	_wake_i += 1
	if _wake_i >= _wake_frames.size():
		timer.stop()
		return
	_wake.texture = _wake_frames[_wake_i]

func _pick(id: String) -> void:
	for c in find_children("*", "Button", true, false):
		(c as Button).disabled = true   # no double clicks
	GameState.pick_scar(id)
