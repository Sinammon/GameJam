extends Control
# Bounce back: you wake up on your cot and pick one Scar (a permanent perk) out of up to 3.

func _ready() -> void:
	UIKit.background(self)
	var box := UIKit.center_column(self, 8)
	box.add_child(UIKit.label("YOU WAKE UP ON YOUR COT", 16, UIKit.ACCENT))
	box.add_child(UIKit.label("Lost 1 bounce. Bounces left: %d" % GameState.bounces, 10, UIKit.BAD))
	box.add_child(UIKit.label("Every fall leaves a scar. Choose one:", 9, UIKit.DIM))
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
		var card := UIKit.button("%s\n\n%s" % [s.name, s.desc], Vector2(130, 70), 9)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.pressed.connect(_pick.bind(id))
		row.add_child(card)

func _pick(id: String) -> void:
	for c in find_children("*", "Button", true, false):
		(c as Button).disabled = true   # no double clicks
	GameState.pick_scar(id)
