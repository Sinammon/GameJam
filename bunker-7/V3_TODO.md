# V3 status and TODO (handoff to Coder 2)

Nothing in this list was hand-played. The V3 work was stopped part-way, so the pieces below are at different stages.

## Done and merged into main
- **Font:** Pixelify Sans is the project font (see FONT_NOTES.md). New UI text should wrap sizes in `UIKit.fs(size)` or use `UIKit.label/outlined/button`. Only checked at 1x (480x270). Not checked: 2x+ window, web export (is the TTF inside the pck?), the bunker room-name labels look tight at 10 px.
- **Audio files:** 47 synthesized .wav files in `audio/` (5.6 MB) plus the generator `tools/synth_audio.py`. Nobody has listened to them. Names:
  music_menu, music_bunker, music_expedition, music_danger, music_gameover, music_ending, amb_wind, geiger_1..3, heartbeat, rad_warning, footstep_1..2, jump, land, swing, axe_chop, tree_fall, pickaxe_hit, rock_break, pickup, drop, zombie_growl_1..2, zombie_hit, zombie_death, player_hurt, player_death, hatch_open, hatch_close, ladder_climb, door_open, build_ok, build_fail, eat, drink, sleep, flashlight_toggle, popup_open, popup_close, slot_select, day_start, ui_click, ui_hover, ui_back, ui_confirm.

## Audio: NOT wired in yet (todo)
- Create `autoload/audio.gd` (register in project.godot): Music/SFX buses, `play_sfx(name, volume_db, pitch_var)` with a small AudioStreamPlayer pool (never crash on a missing name), `play_music(name, fade)` with crossfade, `stop_music`.
- Music/SFX volume sliders in the pause menu options, saved in settings (scenes/settings_store.gd).
- Hook sounds in: player (step/jump/land), tree/rock/chips (chop, fall, pick, break), zombie (growl/hit/death), pickup, hatch, bunker (ladder, door, build ok/fail, sleep), inventory (slot select, eat, drink), HUD/radiation (geiger rate by radiation level, warning beep, heartbeat at low health), UI (click/hover/back/confirm), scene music switches (menu, bunker, expedition, danger, game over, ending).
- Web: first sound only after a user click; check the Web export still works. Listen to every file and fix loops/volume.
- Add `tools/test_audio.gd` (files exist, unknown name does not crash, buses exist).

## Gameplay: WORK IN PROGRESS on branch `v3-gameplay` (NOT in main)
It is an unfinished data layer; nothing is wired into the scenes yet, and it was never run in the game.
- `autoload/game_state.gd`: +360 lines (new stock kinds dirty_water, raw_meat, mushroom, bandage, radio_part; RECIPES; filter_water(), cook(), consume_stock(); water/food meters; locker packing; current_location; go_outside(location); is_location_unlocked(); daily goal fields; final horde).
- `scenes/survival.gd`: thirst/hunger meter constants and tick (Q eats, R drinks).
- `scenes/locations.gd`: LOCATIONS dict (surface, mine, crater).
- `scenes/day_plan.gd`: per-day goals, final horde day 7.
- Known test status: test_expedition, test_phase2, test_ui, test_lighting pass; **test_bunker has 1 failure** ("Build is enabled", because the building recipes changed). Fix the test or the recipe.

### Gameplay TODO (design)
1. Survival loop: dirty water and raw meat outside; Water Filter station and Stove in the bunker (filter dirty -> clean water, cook meat/mushrooms -> food); canned food rare and safe; hunger/thirst meters in the HUD that drain outside; at 0 health drains; drinking dirty water risks sickness/radiation; eat/drink hotkeys or inventory use. Keep Easy/Normal/Hard meaningful; Normal must be survivable with care.
2. Two locations, picked when you climb the ladder (lock text if locked): **Old Mine** (unlock day 2: dark, scrap/circuits/concrete/mushrooms, rocks to mine, bats or cave zombies, dirty-water pools, rope exit) and **Bomb Crater** (unlock day 4: very high radiation, best loot incl. the radio part for the beacon, tougher glowing zombies, risk and reward). Parametrise `scenes/expedition.gd` from the LOCATIONS data instead of copying it. The expedition must keep calling only GameState.bank_loot / player_died through GSBridge.
3. Days: daily goal in morning screen and top bar; storm day 3, horde at the hatch day 5; 3 to 5 new food/water random events (poisoned can, rain shower, trader rat...). Keep the 7 day beacon/convoy win.
4. Tests: dirty -> clean water, cooking, hunger/thirst drain and damage, unlock days, enter/leave each location and bank loot, death in the crater, carry limit.

## Crafts book / field guide (not started)
- Pause menu (Esc) gets a **Crafts / Book** button opening a screen that lists every item and craft/building: name, where to find it (surface, mine, crater, containers, zombies), what it is used for, recipe/cost. Build it from data (one dict in GameState or a new `scenes/guide_data.gd`, which does not exist yet) so it cannot go out of date. Needs the final item list from the gameplay work.

## Art still needed (designer; prompts are in the local-only ASSET_PROMPTS_V4.md, not in git)
- Mine: `bg_mine`, `mine_set` (tile_mine_floor, tile_mine_wall, tile_mine_ceiling, obj_mine_support, obj_mine_cart, obj_mine_lamp, obj_mine_exit, obj_mushroom, obj_water_pool), `bat_fly` (4 frames), `rat_run` (4 frames).
- Crater: `bg_crater`, `crater_set` (tile_crater_ground, tile_crater_under, obj_bomb_shell, obj_car_wreck, obj_crater_crystal, obj_supply_crate, obj_girder, obj_crater_exit, obj_ash_pile).
- Survival icons `icon_survival`: icon_dirty_water, icon_clean_water, icon_raw_meat, icon_cooked_meat, icon_mushroom, icon_canned_food, icon_bandage, icon_tin_can, icon_bucket.
- Stations `bunker_stations2`: obj_water_filter, obj_water_filter_on, obj_stove, obj_stove_lit, obj_shelf.
- Older redo list: survivor chop and flashlight matching the real survivor (5b, 5c), zombie attack/hurt style, hatch art match.
- Process new art with `art_tools/clean_art.py` (magenta to transparent), then wire in with a has-file fallback.

## Release
- The last web export (walkable bunker, before font and audio) is already uploaded to itch.io. The Web export templates are installed only on the lead's Mac (see EXPORT.md to install them elsewhere). Re-export after the above lands and re-test the web build (lights, zombies, audio, font).
- Hand-playtest everything and tune balance (zombies, radiation, ore, meters).
