# Coder 1: expedition (outside) part

## Open and run
1. Godot 4.7: Project Manager > Import > pick `bunker-7/project.godot`.
2. Press F5. The main scene is `res://scenes/expedition.tscn` (set in project.godot).
3. Headless check: `Godot --headless --path bunker-7 --script res://tools/test_expedition.gd` (exit 0 = all PASS).

## Controls
- Move: A/D or Left/Right. Jump: W, Up or Space. Interact: E.
- E near a crate opens it. E inside the hatch (left end) banks your loot.
- ESC quits (test only). F1 fills radiation to 100% (debug, expedition only).

## How it plays
- Radiation fills while you are outside the hatch: 1.5%/s next to it up to 4.5%/s at the far right, times `get_radiation_multiplier()`. At 100% the player collapses, the screen fades, `player_died` is called.
- Crates give 2-4 random wood/concrete/scrap (times loot multiplier). Circuits only in crates in the last 30% of the map (35% chance). A full backpack leaves the leftover loot in the crate.
- Carry limit comes from `get_carry_limit()`. HUD shows carried/limit.
- If `get_last_stand_pack()` is non-empty, a yellow backpack appears at that x on the ground. E gives back what fits (the rest stays for this expedition only).
- The scene never changes scenes. It only calls `GameState.bank_loot(items)` or `GameState.player_died(items, position)`.

## Contract usage
Read: get_radiation_multiplier, get_loot_multiplier, get_carry_limit, get_move_speed_bonus (applied to player speed), get_last_stand_pack. Not used yet by the expedition: get_dig_speed_bonus, has_air_filter, has_reinforced_door (no digging yet; filter and door are bunker-side effects).
Call: bank_loot, player_died. Items dict keys: wood, concrete, scrap, circuits.

## For Coder 2
`autoload/game_state.gd` must provide exactly these functions (return types matter):
- `get_radiation_multiplier() -> float` (1.0 normal)
- `get_loot_multiplier() -> float`
- `get_carry_limit() -> int` (default 12)
- `get_move_speed_bonus() -> float` (0.1 = +10%)
- `get_dig_speed_bonus() -> float`
- `has_air_filter() -> bool`
- `has_reinforced_door() -> bool`
- `get_last_stand_pack() -> Dictionary`: `{}` or `{"items": {"wood":int,"concrete":int,"scrap":int,"circuits":int}, "position": Vector2}`. Return `{}` after the pack's expedition is over (the expedition does not report pickup, it only reads).
- `bank_loot(items: Dictionary) -> void` and `player_died(items: Dictionary, position: Vector2) -> void`. These must change the scene themselves.

Swap out the stub: Project > Project Settings > Globals > Autoload, set `GameState` path to `res://autoload/game_state.gd` (or edit the `GameState=` line in project.godot), then delete `autoload/game_state_stub.gd`. The stub reloads the expedition after bank/death and remembers a fake pack; the real one must not.
