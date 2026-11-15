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

## Gameplay: DONE (branch `v3-finish`, ported from the old `v3-gameplay` data layer)
Tests: `tools/test_survival.gd` (new) plus all older suites pass. Balance was checked with API
playthroughs only (Normal careful run reaches the rescue, Hard careful survives the week, Hard careless
loses), not by hand. Hand-playtest and tune the numbers below.
1. **Survival loop** (done): stock kinds dirty_water, raw_meat, mushroom, bandage, radio_part (+ canned
   food outside, banked as a meal). Puddles / barrels / mine pools give dirty water (E), mushrooms in the
   mine, rats (`actors/critter.gd`, hit them) and zombies drop raw meat. Utility Room: **Water Filter**
   (old purifier id, 1 dirty -> 1 clean, up to 4 overnight) and **Stove** (cook meat, mushroom stew,
   boil water; wood is fuel). Thirst/hunger meters (`scenes/survival.gd`) drain outside, HUD bars under the
   hearts, Q eats, R drinks (also the canteen slot; medkit slot uses a bandage). Empty meter = 1 half-heart
   every 4 s; dirty water +6% radiation and 30% sickness. The night burns 25 of each meter and refills it
   from the water/meals it eats (no separate charge). Crates hand out clean water / canned food rarely.
   Locker: drink / eat / bandage, pack water, meals, bandages for the trip. Difficulty: drain x0.75 / 1 / 1.3.
2. **Locations** (done): `scenes/locations.gd` table drives `scenes/expedition.gd` (layout, crates, ores,
   zombies, sources, decor, exit). Ladder popup lists them with lock text. Old Mine (day 2: rock ceiling,
   dark, ore rocks, pools, mushrooms, cave zombies, rope exit), Bomb Crater (day 4: radiation x2, rich
   crates, the Radio Part in the farthest crate, glowing zombies 1.75x hp, 2 damage, ladder exit).
   The last stand pack remembers its location.
3. **Days** (done): `scenes/day_plan.gd` goals with rewards (morning screen, bunker banner and top bar,
   expedition HUD), storm day 3 (radiation x1.5), horde night after day 5 (forced event card: the
   Reinforced Door holds, else -2 meals -2 health and a damaged room, or pay 3 meals). New events: poisoned
   can, rain shower, trader rat, spoiled meat, mushroom patch (`requires` / `forced_only` keys, see
   data/EVENTS_HOWTO.md). The Radio Beacon needs the radio part (debug F2/7 gives one). 7-day win unchanged.
4. **Crafts / Book** (done): pause menu > Crafts / Book (`scenes/book.gd`), data from
   `scenes/guide_data.gd`, derived from GameState.ITEMS / BUILDINGS / ROOMS / RECIPES / BACKPACK_COSTS,
   Locations and Inventory.TOOLS. Tabs: Items, Stations, Recipes, Places, Tools. Esc closes it.

### Still open
- Hand playtest and balance (meter drain, crater radiation, mine darkness with lights quality "off").
- Real art for the mine/crater/stations/survival icons (list below): placeholders are drawn now and every
  file is picked up by name when it exists (`obj_water_filter`, `obj_stove`, `obj_mushroom`,
  `obj_water_pool`, `obj_barrel`, `obj_mine_*`, `obj_girder`, `obj_car_wreck`, `obj_crater_crystal`,
  `obj_mine_exit`, `obj_crater_exit`, `bg_mine`, `bg_crater`, `icon_<item>`, `rat_run_N`).
  Not wired yet: `tile_mine_*` / `tile_crater_*` tiles (the ground reuses tiles_outside.png tinted per
  location), `bat_fly`, `obj_shelf`, `obj_stove_lit`, `obj_water_filter_on`, `obj_bomb_shell`, `obj_supply_crate`, `obj_ash_pile`.
- Audio wiring (next agent, unchanged list above). New hook points: eat/drink (`expedition.use_item`),
  filter/cook (bunker `_do`), rat hit (`actors/critter.gd take_hit`), source use (`actors/source.gd interact`).
- Event pictures for the new events (`event_<id>.png`, 88x64).

## Art still needed (designer; prompts are in the local-only ASSET_PROMPTS_V4.md, not in git)
- Done (V4 "gameNewPlaces" batch, cleaned by `art_tools/clean_art.py`, see art/ART_INDEX.md): `bg_mine`, `bg_crater`,
  mine tiles + props (`tiles_mine` atlas, support, cart, lamp, rope-ladder exit, mushroom, water pool + drip),
  crater tiles + props (`tiles_crater` atlas, bomb shell, car wreck, crystal, supply crate, girder, ladder exit, ash pile),
  `bat_fly` (scenery bats in the mine), `rat_run` (redone), the 9 survival icons, filter / stove (on and lit) and the shelf.
  Not used yet: `icon_tin_can`, `icon_bucket` (no such items in the game).
- Older redo list: survivor chop and flashlight matching the real survivor (5b, 5c), zombie attack/hurt style, hatch art match.
- Process new art with `art_tools/clean_art.py` (magenta to transparent; "parts" sheets cut objects from listed regions), then
  wire in with a has-file fallback.

## Release
- The last web export (walkable bunker, before font and audio) is already uploaded to itch.io. The Web export templates are installed only on the lead's Mac (see EXPORT.md to install them elsewhere). Re-export after the above lands and re-test the web build (lights, zombies, audio, font).
- Hand-playtest everything and tune balance (zombies, radiation, ore, meters).
