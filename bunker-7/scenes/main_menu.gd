extends Control
# Main menu: title art, radio message, three difficulty buttons.

const RADIO_MESSAGE := "\"...convoy arrives at dawn on Day 7.\nKeep the beacon alive...\""

func _ready() -> void:
	var has_art := UIKit.tex("characters_clean/title_art") != null
	UIKit.backdrop(self, "characters_clean/title_art")
	var box: VBoxContainer
	if has_art:
		# The survivor stands on the left of the picture, so the menu sits on the right.
		box = UIKit.panel_box(self, Rect2(262, 14, 206, 242), UIKit.shade_style(8), 5)
	else:
		box = UIKit.center_column(self, 6)
	box.add_child(UIKit.outlined("BUNKER 7", 28, UIKit.ACCENT))
	box.add_child(UIKit.outlined("Bounce Back", 11, UIKit.DIM))
	box.add_child(UIKit.outlined(RADIO_MESSAGE, 9, UIKit.GOOD))
	box.add_child(Control.new())   # small gap
	box.add_child(UIKit.outlined("Choose difficulty", 10))
	_add_difficulty(box, GameState.Difficulty.EASY, "5 bounces, gentle")
	_add_difficulty(box, GameState.Difficulty.NORMAL, "3 bounces")
	_add_difficulty(box, GameState.Difficulty.HARD, "2 bounces, scarce")

func _add_difficulty(box: VBoxContainer, d: int, note: String) -> void:
	var s: Dictionary = GameState.SETTINGS[d]
	var b := UIKit.button("%s  -  %s" % [s.name, note], Vector2(190, 24))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(GameState.start_game.bind(d))
	box.add_child(b)
