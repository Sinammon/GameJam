# Coder 1: expedition (outside) part

## Open and run
1. Godot 4.7: Project Manager > Import > pick `bunker-7/project.godot`.
2. Press F5. The main scene is `res://scenes/main_menu.tscn`; a new game opens the walkable bunker (`scenes/bunker.tscn`).
3. Headless check (exit 0 = all PASS):
   `Godot --headless --fixed-fps 60 --path bunker-7 --script res://tools/test_expedition.gd`
   It swaps GameState for a recorder (`tools/fake_game_state.gd`) and drives the player with real key events:
   walking, jumping, crates, carry limit, the pack, banking once, dying once, round trips to the farthest crate on
   both sides, health drain above 100%, damage and death reason, hotbar/backpack keys, Esc pause, radiation both ways.
   (Zombies are switched off there: `ex.zombies_enabled = false`.)
4. Phase 2 test (trees, carry limit, mining, dig rules, climbing out of holes, zombies, spawner, a random soak):
   `Godot --headless --fixed-fps 60 --path bunker-7 --script res://tools/test_phase2.gd`
5. Lighting test (qualities create/remove nodes, light cap, live switch via the pause menu signal and the settings poll,
   F2, a mined block stops occluding, glow pool, ambient, zombie eyes):
   `Godot --headless --fixed-fps 60 --path bunker-7 --script res://tools/test_lighting.gd` (uses its own settings file)
6. Lighting screenshots: `SHOT_QUALITY=full python3 ~/.claude/skills/godot/scripts/debug/run_scenario.py bunker-7 bunker-7/tools/shots/shot_light_hole.json --godot-bin "$GODOT"`
   (also `shot_light_hatch.json`, `shot_light_depot.json`; quality full/simple/off).
7. Screenshots (rendered window): `python3 ~/.claude/skills/godot/scripts/debug/run_scenario.py bunker-7 bunker-7/tools/shots/shot_tree.json --godot-bin "$GODOT"`
   (also `shot_tree_fall.json`, `shot_hole.json`, `shot_chop.json`, `shot_zombie.json`, `shot_ore.json`); PNGs land in the Godot user folder (`user://shot_*.png`).
8. Art V3 captures: `shot_zombie_death.json`, `shot_hud.json`, `shot_hatch.json`, `shot_tutorial.json` (same command). Each also saves
   its own numbered captures at exact moments (`user://shot_<mode>_<n>.png`: death frames, geiger levels 0-4 + backpack grid,
   hatch closed/open/climbing, all 7 tutorial slides).
9. Walkable bunker test (real GameState; new game + tutorial, every station, build once, unlock once, backpack tiers 1-4,
   sleep -> overnight -> bunker, ladder -> expedition, hatch -> bunker with the stock banked once, death -> scar pick -> bunker,
   Esc closing popups without the pause menu):
   `Godot --headless --fixed-fps 60 --path bunker-7 --script res://tools/test_bunker.gd`
10. Bunker screenshots: `shot_bunker_overview.json`, `shot_bunker_ladder.json` (climbing down the shaft), `shot_bunker_popup.json`
   (utility workbench), `shot_bunker_upgrade.json` (upgrade bench), `shot_bunker_door.json` (locked door), same command as 7.

11. V3 survival test (filter, stove, meters, every location, crater death, book, playthroughs):
   `Godot --headless --fixed-fps 60 --path bunker-7 --script res://tools/test_survival.gd`
12. V3 screenshots: `SHOT_MODE=mine python3 ~/.claude/skills/godot/scripts/debug/run_scenario.py bunker-7 bunker-7/tools/shots/shot_v3.json --godot-bin "$GODOT"`
   (modes morning, bunker, stations, utility, hud, mine, crater, book; picture in `user://shot_v3.png`).

## Controls
- V3: Q eats, R drinks (best item carried; dirty water and raw food are risky). Canteen slot drinks, medkit slot
  uses a bandage. Pause menu > Crafts / Book lists every item, station, recipe and place.
- Bunker: A/D walk, E uses the station you stand at (a key box with a label shows above it), Enter / click presses the
  focused popup button, Esc or E closes a popup (never the pause menu at the same time), Esc otherwise pauses.
  E at the foot of the ladder climbs up to the expedition (once a day).
- Move: A/D or Left/Right. Jump: W, Up or Space. Interact: E.
- Hotbar: 1-5 or mouse wheel (axe, pickaxe, flashlight, canteen, medkit). Left click uses the tool. Tab: backpack grid. Esc: pause menu.
- Axe: chop dead trees (logs = wood), hit zombies lightly. Pickaxe: dig the block under the mouse / in front / under you, hit zombies harder. Swings aim at the mouse side (or where you face), one every 0.4 s.
- E near a crate opens it. E inside the hatch (middle of the map) banks your loot.
- E in the hatch with an empty backpack asks first ("Press E again to go inside"); a second E within 2 s goes home empty-handed. This stops an accidental E at spawn ending the day.
- Debug builds only (editor F5 / debug export): F1 fills radiation to 100% (to test the health drain). F2 cycles the lights quality (full, simple, off; not saved).
- Lights: Esc > Settings > Lights (Full, Simple, Off), applied at once. Hotbar 3 (flashlight) shines a beam where you face. See `V2_NOTES.md` Phase 3.

## How it plays
- Day loop: wake at the cot in the bunker (day banner) -> walk to the ladder, E -> expedition -> E in the hatch banks and
  climbs down -> bunker (stock banner) -> build / unlock / upgrade the backpack -> cot, Sleep -> overnight summary
  (maybe a night event first) -> next day at the cot. Death outside -> scar pick -> night -> cot. See `V2_NOTES.md` Phase 4.
- Backpack: carry = 12/16/20/24 by tier (upgrade bench in the bedroom; costs `GameState.BACKPACK_COSTS`) + 4 with the
  Storage Room + 2 with Steady Hands.
- World: 4800 px (10 screens), hatch in the middle (x=2408). Zones mirrored: depot | market | suburb | HATCH | suburb | market | depot. See `V2_NOTES.md`.
- Radiation fills while you are outside the hatch: 0.8%/s next to it up to 2.8%/s at either edge, times `get_radiation_multiplier()`. Walking straight to a farthest crate (2350 px away, either side) and back takes about 49 s and costs about 87% on Normal; on Hard (x1.5) you arrive home losing hearts. Warnings (message + green vignette pulse) at 60% and 85%; a go-home arrow shows when you are more than 1.5 screens away (or off-screen at 60%+). Radiation stops counting once you bank or start dying.
- Health: 10 half-hearts (or `get_max_health()`). At 100% radiation you lose 1 half-heart at once and then every 2 s (not in the hatch). At 0 the player collapses (0.9 s), the HUD says why, the screen fades to black (1 s + 0.8 s), then `player_died(items, position)` is called once, with what was carried at the moment of death.
- Crates give 2-4 random wood/concrete/scrap (times loot multiplier). Circuits only in crates in the last 30% of the map (35% chance each, 3 such crates). Crates also hold supplies: 0-1 water and 0-1 food each (0-2 food in the suburb third, 0-2 water in the market third), times loot multiplier. Water and food count toward the carry limit. A full backpack leaves the leftover loot in the crate.
- Carry limit comes from `get_carry_limit()` (counts items). HUD shows carried/limit by the backpack icon; Tab shows the grid (stacks per material, locked slots padlocked).
- Last Stand Pack: if `get_last_stand_pack()` has items, a yellow backpack sits on the ground at that x. E takes what fits, rarest first (circuits, scrap, water, food, concrete, wood). The rest stays in the pack for this expedition only; when the expedition ends GameState drops the pack. Dying again makes what you carry the new pack.
- Trees: suburb and market only. 3/5/7 axe hits for 1/2/3 logs (x loot multiplier); a stump stays. Logs fall to the ground and are picked up by walking over them if the backpack has room.
- Mining: top block of a column only, at most 4 deep, bedrock never breaks, never under the hatch/crates/trees/pack, and never so steep that you couldn't climb out (steps of at most 2 blocks). Ores 1-3 blocks down: planks (wood), scrap ore / pipes (scrap), concrete, circuit veins (deep and far out only). Dirt sometimes gives scrap.
- Zombies: none within 14 tiles of the hatch at spawn and they never enter the 6-tile safe zone around it. 2/4/6 per side in suburb/market/depot (more each day), at most 8 near you, spawned off-screen. Chase at 60 px/s (you run 100), 0.4 s windup then 1 half-heart. Pickaxe kills in 2 hits, axe in 4. 30% drop food or scrap. Death by zombie shows "A zombie got you."
- When several things are in reach, E uses the nearest one that still has something in it; the hatch always comes last, so loot lying in the hatch is picked up before banking.
- After `bank_loot` the player is frozen until GameState changes the scene. The scene never changes scenes itself.

## Art
Survivor (`actors/player.gd`, SpriteFrames built in code from `art/characters_clean/survivor_*`: idle, walk, jump by velocity, a short pickaxe swing when looting, collapse on death), crates, hatch, Last Stand Pack (`actors/art.gd` helper), parallax background (sky 0.1, far city 0.4 mirrored, one near panel per area at 0.8: suburb, market, depot) and the ground TileSet (built at runtime from `tiles_outside.png`). Every texture is optional: if one is missing the old placeholder shape is used.

## Contract usage
All GameState access goes through `scenes/gs_bridge.gd` (`GSBridge`). Every call is guarded with `has_method`, so a missing function logs one warning and uses the default (radiation x1, loot x1, carry 12, speed +0, no pack) instead of crashing. Return values are type-checked and items dicts are cleaned to the six keys (wood, concrete, scrap, circuits, water, food) as ints.
Read: get_radiation_multiplier, get_loot_multiplier, get_carry_limit, get_move_speed_bonus, get_last_stand_pack (read once when the expedition starts). Optional V2 reads (quiet defaults if missing): get_backpack_tier (1), get_max_health / max_health (10). get_dig_speed_bonus (pickaxe damage x (1 + bonus)). Optional: day via get_day() or the `day` variable (zombie numbers, default 1). Not used yet: has_air_filter, has_reinforced_door (bunker-side effects).
Call: bank_loot(items), player_died(items, position). Each is called at most once per expedition, never both.

## For Coder 2
`autoload/game_state.gd` should provide (names exact, return types as shown):
- `get_radiation_multiplier() -> float` (difficulty rad x Thick Skin x storm, 1.0 normal)
- `get_loot_multiplier() -> float`
- `get_carry_limit() -> int` (backpack tier 12/16/20/24, +4 storage room, +2 Steady Hands)
- `get_move_speed_bonus() -> float` (0.1 = +10%, Light Feet)
- `get_dig_speed_bonus() -> float`
- `has_air_filter() -> bool`, `has_reinforced_door() -> bool`
- `get_last_stand_pack() -> Dictionary`: `{}` or `{"items": {"wood":int,"concrete":int,"scrap":int,"circuits":int,"water":int,"food":int}, "position": Vector2}`.
- `bank_loot(items: Dictionary) -> void`: add the six counts to your stock (GameState.LOOT_KINDS), clear the pack, change scene (e.g. to the bunker).
- `player_died(items: Dictionary, position: Vector2) -> void`: store `{"items": items, "position": position}` as the new pack (replacing any old one), bounces -1, change scene (scar pick / game over).
- The pack is "next expedition only": clear it in `bank_loot`, and replace it in `player_died`. The expedition never reports pack pickup; picked-up items are simply part of what it banks or dies with.

Swap out the stub: edit the `GameState=` line in project.godot to
`GameState="*res://autoload/game_state.gd"` (or Project > Project Settings > Globals > Autoload), then delete `autoload/game_state_stub.gd`. The stub reloads the expedition after bank/death and remembers a fake pack; the real one must change scenes instead.
