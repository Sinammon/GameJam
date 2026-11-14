extends Control
# Day 7 survived. Rescue if the Radio Beacon is built and its room isn't damaged, else neutral.

func _ready() -> void:
	var rescued: bool = GameState.is_rescued()
	UIKit.background(self, Color(0.05, 0.10, 0.07) if rescued else UIKit.BG)
	var box := UIKit.center_column(self, 6)
	if rescued:
		box.add_child(UIKit.label("THE CONVOY ARRIVES", 20, UIKit.GOOD))
		box.add_child(_wrapped("Engines at dawn. They followed your beacon. You're going home.", 10))
	else:
		box.add_child(UIKit.label("DAY 7 IS OVER", 20, UIKit.ACCENT))
		box.add_child(_wrapped("No beacon, no convoy. You're alive. Alone.", 10))
	box.add_child(UIKit.label("Days survived: %d" % GameState.MAX_DAY, 10, UIKit.DIM))
	box.add_child(UIKit.label("Bounces used: %d of %d" % [GameState.bounces_used(), int(GameState.settings.bounces)], 10, UIKit.DIM))
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
