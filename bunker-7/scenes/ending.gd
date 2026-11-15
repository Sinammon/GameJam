extends Control
# Day 7 survived. Rescue if the Radio Beacon is built and its room isn't damaged, else neutral.
# Art: ending_rescue / ending_alone (480x270); text sits in a dark see-through box.

func _ready() -> void:
	var rescued: bool = GameState.is_rescued()
	var art := "characters_clean/ending_rescue" if rescued else "characters_clean/ending_alone"
	var has_art := UIKit.tex(art) != null
	UIKit.backdrop(self, art, Color(0.05, 0.10, 0.07) if rescued else UIKit.BG)
	var box: VBoxContainer
	if has_art:   # top band over the sky, the scene below stays visible
		box = UIKit.panel_box(self, Rect2(40, 6, 400, 0), UIKit.shade_style(7), 3)
	else:
		box = UIKit.center_column(self, 6)
	if rescued:
		box.add_child(UIKit.outlined("THE CONVOY ARRIVES", 20, UIKit.GOOD))
		box.add_child(_wrapped("Engines at dawn. They followed your beacon. You're going home.", 10))
	else:
		box.add_child(UIKit.outlined("DAY 7 IS OVER", 20, UIKit.ACCENT))
		box.add_child(_wrapped("No beacon, no convoy. You're alive. Alone.", 10))
	box.add_child(UIKit.outlined("Days survived: %d     Bounces used: %d of %d" % [GameState.MAX_DAY, GameState.bounces_used(), int(GameState.settings.bounces)], 9, UIKit.DIM))
	box.add_child(_wrapped("Scars: " + GameState.scar_names_text(), 9))
	var b := UIKit.button("Main Menu", Vector2(140, 24))
	b.pressed.connect(GameState.go_to.bind("res://scenes/main_menu.tscn"))
	if has_art:   # bottom-right corner, off the characters
		b.position = Vector2(480 - 150, 270 - 32)
		add_child(b)
	else:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(b)

func _wrapped(text: String, font_size: int) -> Label:
	var l := UIKit.outlined(text, font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	return l
