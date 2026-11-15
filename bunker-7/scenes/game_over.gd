extends Control
# Out of bounces: "How far you got". Art: game_over (480x270), text in a dark see-through box.

func _ready() -> void:
	var has_art := UIKit.tex("characters_clean/game_over") != null
	UIKit.backdrop(self, "characters_clean/game_over", Color(0.10, 0.04, 0.04))
	var box: VBoxContainer
	if has_art:
		box = UIKit.panel_box(self, Rect2(40, 6, 400, 0), UIKit.shade_style(7), 3)
	else:
		box = UIKit.center_column(self, 6)
	box.add_child(UIKit.outlined("OUT OF BOUNCES", 22, UIKit.BAD))
	box.add_child(UIKit.outlined("How far you got", 11, UIKit.DIM))
	box.add_child(UIKit.outlined("Reached day %d of %d" % [mini(GameState.day, GameState.MAX_DAY), GameState.MAX_DAY], 10))
	box.add_child(_wrapped("Built: " + GameState.built_names_text(), 10))
	box.add_child(_wrapped("Scars: " + GameState.scar_names_text(), 10))
	var b := UIKit.set_click_sfx(UIKit.button("Main Menu", Vector2(140, 24)), "ui_back")
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(GameState.go_to.bind("res://scenes/main_menu.tscn"))
	box.add_child(b)

func _wrapped(text: String, font_size: int) -> Label:
	var l := UIKit.outlined(text, font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	return l
