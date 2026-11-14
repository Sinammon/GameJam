# Coder 1: expedition (outside) part

## Open and run
1. Godot 4.7: Project Manager > Import > pick `bunker-7/project.godot`.
2. Press F5. The main scene is `res://scenes/expedition.tscn` (set in project.godot).
3. Headless check (exit 0 = all PASS):
   `Godot --headless --fixed-fps 60 --path bunker-7 --script res://tools/test_expedition.gd`
   It swaps GameState for a recorder (`tools/fake_game_state.gd`) and drives the player with real key events:
   walking, jumping, crates, carry limit, the pack, banking once, dying once, and a full round trip to the farthest crate.

## Controls
- Move: A/D or Left/Right. Jump: W, Up or Space. Interact: E.
- E near a crate opens it. E inside the hatch (left end) banks your loot.
- E in the hatch with an empty backpack asks first ("Press E again to go inside"); a second E within 2 s goes home empty-handed. This stops an accidental E at spawn ending the day.
- Debug builds only (editor F5 / debug export): ESC quits, F1 fills radiation to 100%. Both do nothing in a release export.

## How it plays
- Radiation fills while you are outside the hatch: 0.8%/s next to it up to 2.4%/s at the far right, times `get_radiation_multiplier()`. Walking straight to the farthest crate (x=2750) and back takes about 56 s and costs about 88% on Normal; on Hard (x1.5) that trip kills you, so far crates are a gamble. Radiation stops counting once you bank or start dying.
- At 100% the player collapses (0.9 s), the screen fades to black (1 s), then `player_died(items, position)` is called once, with what was carried at the moment of death.
- Crates give 2-4 random wood/concrete/scrap (times loot multiplier). Circuits only in crates in the last 30% of the map (35% chance each, 3 such crates). A full backpack leaves the leftover loot in the crate.
- Carry limit comes from `get_carry_limit()`. HUD shows carried/limit.
- Last Stand Pack: if `get_last_stand_pack()` has items, a yellow backpack sits on the ground at that x. E takes what fits, rarest first (circuits, scrap, concrete, wood). The rest stays in the pack for this expedition only; when the expedition ends GameState drops the pack. Dying again makes what you carry the new pack.
- When several things are in reach, E uses the nearest one that still has something in it; the hatch always comes last, so loot lying in the hatch is picked up before banking.
- After `bank_loot` the player is frozen until GameState changes the scene. The scene never changes scenes itself.

## Art
Survivor (`actors/player.gd`, SpriteFrames built in code from `art/characters_clean/survivor_*`: idle, walk, jump by velocity, a short pickaxe swing when looting, collapse on death), crates, hatch, Last Stand Pack (`actors/art.gd` helper), parallax background (sky 0.1, far city 0.4 mirrored, one near panel per area at 0.8: suburb, market, depot) and the ground TileSet (built at runtime from `tiles_outside.png`). Every texture is optional: if one is missing the old placeholder shape is used.

## Contract usage
All GameState access goes through `scenes/gs_bridge.gd` (`GSBridge`). Every call is guarded with `has_method`, so a missing function logs one warning and uses the default (radiation x1, loot x1, carry 12, speed +0, no pack) instead of crashing. Return values are type-checked and items dicts are cleaned to the four keys as ints.
Read: get_radiation_multiplier, get_loot_multiplier, get_carry_limit, get_move_speed_bonus, get_last_stand_pack (read once when the expedition starts). Not used yet: get_dig_speed_bonus (no digging yet), has_air_filter, has_reinforced_door (bunker-side effects).
Call: bank_loot(items), player_died(items, position). Each is called at most once per expedition, never both.

## For Coder 2
`autoload/game_state.gd` should provide (names exact, return types as shown):
- `get_radiation_multiplier() -> float` (difficulty rad x Thick Skin x storm, 1.0 normal)
- `get_loot_multiplier() -> float`
- `get_carry_limit() -> int` (12, 16 with the storage room)
- `get_move_speed_bonus() -> float` (0.1 = +10%, Light Feet)
- `get_dig_speed_bonus() -> float`
- `has_air_filter() -> bool`, `has_reinforced_door() -> bool`
- `get_last_stand_pack() -> Dictionary`: `{}` or `{"items": {"wood":int,"concrete":int,"scrap":int,"circuits":int}, "position": Vector2}`.
- `bank_loot(items: Dictionary) -> void`: add the four counts to your stock, clear the pack, change scene (e.g. to the bunker).
- `player_died(items: Dictionary, position: Vector2) -> void`: store `{"items": items, "position": position}` as the new pack (replacing any old one), bounces -1, change scene (scar pick / game over).
- The pack is "next expedition only": clear it in `bank_loot`, and replace it in `player_died`. The expedition never reports pack pickup; picked-up items are simply part of what it banks or dies with.

Swap out the stub: edit the `GameState=` line in project.godot to
`GameState="*res://autoload/game_state.gd"` (or Project > Project Settings > Globals > Autoload), then delete `autoload/game_state_stub.gd`. The stub reloads the expedition after bank/death and remembers a fake pack; the real one must change scenes instead.
