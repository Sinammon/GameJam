extends Node
# Test double for GameState: records every contract call, never changes scenes.
# Used by tools/test_expedition.gd, test_phase2.gd and test_lighting.gd (the expedition side only).

var rad_mult := 1.0
var carry := 12
var pack := {}
var tier := 1
var max_hp := 10
var day := 1                   # read by GSBridge.day() (zombie numbers)
var dig_bonus := 0.0
var loot_mult := 1.0
var bank_calls: Array = []     # each entry: items dict
var died_calls: Array = []     # each entry: [items, position]

func get_radiation_multiplier() -> float: return rad_mult
func get_loot_multiplier() -> float: return loot_mult
func get_carry_limit() -> int: return carry
func get_move_speed_bonus() -> float: return 0.0
func get_dig_speed_bonus() -> float: return dig_bonus
func has_air_filter() -> bool: return false
func has_reinforced_door() -> bool: return false
func get_backpack_tier() -> int: return tier
func get_max_health() -> int: return max_hp
func max_health() -> int: return max_hp
func get_day() -> int: return day
func get_last_stand_pack() -> Dictionary: return pack
func bank_loot(items: Dictionary) -> void: bank_calls.append(items.duplicate())
func player_died(items: Dictionary, position: Vector2) -> void: died_calls.append([items.duplicate(), position])
