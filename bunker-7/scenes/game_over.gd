extends Control
# Out of bounces: "How far you got".

func _ready() -> void:
	UIKit.background(self, Color(0.10, 0.04, 0.04))
	var box := UIKit.center_column(self, 6)
	box.add_child(UIKit.label("OUT OF BOUNCES", 22, UIKit.BAD))
	box.add_child(UIKit.label("How far you got", 11, UIKit.DIM))
	box.add_child(UIKit.label("Reached day %d of %d" % [mini(GameState.day, GameState.MAX_DAY), GameState.MAX_DAY], 10))
	box.add_child(_wrapped("Built: " + GameState.built_names_text(), 10))
	box.add_child(_wrapped("Scars: " + GameState.scar_names_text(), 10))
	var b := UIKit.button("Main Menu", Vector2(140, 24))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(GameState.go_to.bind("res://scenes/main_menu.tscn"))
	box.add_child(b)

func _wrapped(text: String, size: int) -> Label:
	var l := UIKit.label(text, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(400, 0)
	return l
