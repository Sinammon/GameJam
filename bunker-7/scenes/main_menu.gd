extends Control
# Main menu: title, radio message, three difficulty buttons.

const RADIO_MESSAGE := "\"...convoy arrives at dawn on Day 7.\nKeep the beacon alive...\""

func _ready() -> void:
	UIKit.background(self)
	var box := UIKit.center_column(self, 6)
	box.add_child(UIKit.label("BUNKER 7", 28, UIKit.ACCENT))
	box.add_child(UIKit.label("Bounce Back", 11, UIKit.DIM))
	box.add_child(UIKit.label(RADIO_MESSAGE, 9, UIKit.GOOD))
	box.add_child(Control.new())   # small gap
	box.add_child(UIKit.label("Choose difficulty", 10))
	_add_difficulty(box, GameState.Difficulty.EASY, "5 bounces, gentle")
	_add_difficulty(box, GameState.Difficulty.NORMAL, "3 bounces")
	_add_difficulty(box, GameState.Difficulty.HARD, "2 bounces, scarce")

func _add_difficulty(box: VBoxContainer, d: int, note: String) -> void:
	var s: Dictionary = GameState.SETTINGS[d]
	var b := UIKit.button("%s  -  %s" % [s.name, note], Vector2(190, 24))
	b.pressed.connect(GameState.start_game.bind(d))
	box.add_child(b)
