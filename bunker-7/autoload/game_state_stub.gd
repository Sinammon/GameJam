extends Node
# STUB of Coder 2's GameState (fake values) so the expedition can be tested alone.
# When Coder 2's real autoload/game_state.gd arrives: repoint the GameState autoload
# (Project Settings > Globals) to it and delete this stub.

# --- READ (same names as the contract) ---
func get_radiation_multiplier() -> float:
	return 1.0

func get_loot_multiplier() -> float:
	return 1.0

func get_carry_limit() -> int:
	return 12

func get_move_speed_bonus() -> float:
	return 0.0   # e.g. 0.1 = +10% speed

func get_dig_speed_bonus() -> float:
	return 0.0

func has_air_filter() -> bool:
	return false

func has_reinforced_door() -> bool:
	return false

# Leftover backpack from the previous death: {} or {"items": {...}, "position": Vector2}
var _fake_pack := {}

func get_last_stand_pack() -> Dictionary:
	return _fake_pack

# --- CALL ---
func bank_loot(items: Dictionary) -> void:
	print("[stub] bank_loot ", items)
	_fake_pack = {}
	get_tree().reload_current_scene.call_deferred()   # stub only

func player_died(items: Dictionary, position: Vector2) -> void:
	print("[stub] player_died ", items, " at ", position)
	_fake_pack = {"items": items.duplicate(), "position": position}   # stub only
	get_tree().reload_current_scene.call_deferred()   # stub only
