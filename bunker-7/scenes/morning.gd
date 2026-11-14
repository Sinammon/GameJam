extends Control
# Morning screen: shows the state of the run and the "Go Outside" button.

var _stats: Label
var _materials: Label
var _title: Label
var _bounces: Label

func _ready() -> void:
	UIKit.background(self)
	var box := UIKit.center_column(self, 8)
	_title = UIKit.label("", 22, UIKit.ACCENT)
	box.add_child(_title)
	_bounces = UIKit.label("", 11, UIKit.BAD)
	box.add_child(_bounces)
	_stats = UIKit.label("", 11)
	box.add_child(_stats)
	_materials = UIKit.label("", 11, UIKit.DIM)
	box.add_child(_materials)

	var go := UIKit.button("Go Outside", Vector2(160, 28), 12)
	go.pressed.connect(_go_outside)
	box.add_child(go)

	if OS.is_debug_build():
		box.add_child(UIKit.label("cheats: F2/7 +10 materials   F3/8 skip day   F4/9 +bounce", 7, UIKit.DIM))

	GameState.changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	_title.text = "DAY %d / %d" % [GameState.day, GameState.MAX_DAY]
	_bounces.text = "Bounces left: %d" % GameState.bounces
	_stats.text = "Health %d/%d     Water %d     Food %d" % [GameState.health, GameState.MAX_HEALTH, GameState.water, GameState.food]
	_materials.text = "Wood %d   Concrete %d   Scrap %d   Circuits %d" % [GameState.wood, GameState.concrete, GameState.scrap, GameState.circuits]

func _go_outside() -> void:
	get_tree().change_scene_to_file("res://scenes/expedition.tscn")
