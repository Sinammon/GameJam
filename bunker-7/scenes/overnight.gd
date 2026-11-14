extends Control
# Overnight summary: what changed during the night (GameState.last_night_summary). Continue -> morning.

func _ready() -> void:
	UIKit.backdrop(self, "characters_clean/game_over", UIKit.BG, 0.3)   # the bunker at night
	var box := UIKit.center_panel(self, UIKit.panel_style(12), 6)
	box.add_child(UIKit.label("THE NIGHT PASSES", 18, UIKit.ACCENT))
	box.add_child(UIKit.label("Morning of day %d" % GameState.day, 9, UIKit.DIM))
	for line in GameState.last_night_summary:
		var l := UIKit.label(line, 10)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(340, 0)
		box.add_child(l)
	var go := UIKit.button("Continue", Vector2(140, 24))
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(GameState.go_to.bind("res://scenes/morning.tscn"))
	box.add_child(go)
