# V2 notes (Coder 1)

## Phase 0: reproduced before changing anything
Probe: `tools/probe_phase0.gd` (real GameState, Normal), run headless on the v1 code (commit adcdef1).

- **"World only goes one way": confirmed.** Hatch and spawn at x=48, world 0..2880. Holding A for 2 s
  from spawn reaches x=6 and stops at the left wall. Everything (crates, hills, three areas) lies to the right.
- **"You can't die outside": confirmed as "you can, but nobody does".** Radiation 0.8 %/s next to the
  hatch, 2.4 %/s at the far right. Standing still just outside the hatch takes 120 s to reach 100%;
  the full round trip to the farthest crate costs 88%. Death is instant at 100% (collapse + fade),
  with no warning, no health, no message saying why. The only HUD element is a plain grey "RAD" bar.

## Phase 1 + world layout: decisions
- **World:** 300 columns = 4800 px (10 screens), hatch at x=2408 (column 150, the middle). Zones are mirrored:
  `depot | market | suburb | HATCH | suburb | market | depot`. Suburb is next to the hatch on both
  sides (safe, food), then market (water), depot at the edges (circuits). The hills and crates
  are mirrored too (crates are not exactly symmetric so the two sides feel different).
- **Radiation:** rate = lerp(0.8, 2.4, |x - hatch| / 2400) %/s on both sides, x GameState multiplier.
  Farthest crates are 2350 px from the hatch (same distance as v1's farthest crate), so the measured
  round trip on Normal stays at about 88%.
- **Over 100%:** radiation stays at 100% and drains 1 half-heart every 2 s. 10 half-hearts = 20 s of
  grace. Health 0 = the v1 death sequence; `player_died(items, position)` is unchanged.
  The death reason ("radiation") is kept on the player and shown as an icon + one line during the fade.
- **Warnings:** 60% (green pulse, "Radiation rising. Head home.") and 85% (stronger pulse, "Radiation
  high! Go home now!"), 100% ("Radiation sickness! Losing health!"). A "go home" arrow shows at the
  screen edge when you are more than 1.5 screens (720 px) from the hatch, and from 60% whenever the hatch is off-screen.
- **HUD:** `scenes/hud.tscn` (CanvasLayer, drawn in code). Icons only, tiny numbers.
- **Inventory:** `scenes/inventory.gd` (hotbar of 5 tools, Tab backpack grid). The carry limit is still
  `GSBridge.carry_limit()` and still counts items (v1 rule), so nothing changes for banking or balance.
  The grid shows `carry_limit` unlocked slots (the rest of the tier size, 12/16/20/24, padlocked) and
  draws carried materials as one stack per kind with its count; `used/limit` sits next to the grid.
  Left click emits `Inventory.tool_used(tool_id)`: the hook for trees, mining and combat.
- **Pause:** the expedition adds `scenes/pause_menu.tscn` (if present) and disables it once the
  death fade or banking starts.
- **Input:** `pause` (Esc) replaces the debug quit; the pause menu (other agent) listens to it.
  `hotbar_1..5`, `inventory` (Tab), `attack` (left mouse) added.

## Systems and hooks (for the next agent: trees, mining, zombies)
- `player.take_damage(amount_half_hearts, source, from_pos = null) -> bool`: i-frames 0.6 s (radiation
  ignores them), knockback away from `from_pos`, red flash, hurt anim. Health 0 -> `player.out_of_health(reason)`
  -> expedition `_die(reason)` -> collapse, HUD shows icon + line, fade, `player_died(items, position)`.
  Add a line for a new reason in `hud.gd` `DEATH_TEXT`.
- `ex.inventory.tool_used(tool_id)` and `ex.inventory.selected_tool()`; `ex.distance_frac(x)` (0 at the
  hatch, 1 at either edge) and `ex.area_of(col)` (0 suburb, 1 market, 2 depot) for placing things by zone.
- Radiation: `scenes/radiation.gd` (rate, thresholds, drain, colours). HUD: `scenes/hud.gd`.
- Optional art the HUD picks up when it exists (`art/world_clean/`): `ui_geiger.png` (5-frame strip),
  `ui_markers.png` (first square frame = arrow pointing right), `icon_backpack.png`,
  `icon_tool_{axe,pickaxe,flashlight,canteen,medkit}.png`; optional sound `audio/sfx_rad_warning.{wav,ogg,mp3}`.
- Measured (headless test): round trip hatch -> farthest crate -> hatch, either side: 24.6 s each way,
  87% radiation on Normal; on Hard (x1.5) it goes over 100% and you start losing hearts.

## Phase 2: trees, mining, zombies (decisions and tuning)
All tuning constants sit at the top of their script, under a "Tuning" comment.
- **Tool swings** (`scenes/tool_swing.gd`, connected to `Inventory.tool_used`): one swing per `COOLDOWN` 0.4 s,
  reach `REACH` 26 px (~1.5 tiles) in front. Aim = towards the mouse once the mouse has moved, else the facing
  direction. Order: zombies in the swing box first, then (pickaxe) the block in reach, else a tree; (axe) a tree.
  Damage: zombies axe 1 / pickaxe 2 (`ZOMBIE_DAMAGE`), trees axe 1 / pickaxe 0.34 (`TREE_DAMAGE`). Plays
  `survivor_chop` (axe) / `survivor_mine` (pickaxe) if the frames exist, else a small white arc.
  The player got `facing` and `face(dir)`; `use_tool(tool)` now only plays the swing animation.
- **Trees** (`actors/tree.gd/.tscn`): placed by the expedition (`spawn_trees`) in the suburb and market only,
  from `TREE_MIN_COL` 12 columns off the hatch, every 5-11 columns, never within 2 columns of a crate or the pack.
  Seeded by day. Sizes (`SIZES`): small 3 hp / 1 log, medium 5 / 2, large 7 / 3 (market: more large ones). Logs x
  loot multiplier (at least 1). Logs are `actors/pickup.gd` items: they fall to the ground, drift to the player
  within 36 px and go into the backpack only if there is room (a full pack leaves them lying, "Backpack full!").
  The ground under a tree can't be dug.
- **Mining** (`scenes/mining.gd`): every block collides now (any block may become exposed); the old "deep fill
  without collision" trick is gone. Rows: surface .. row 19 dirt/ores, row 20 bedrock (`BEDROCK_ROW`).
  Block hp (`HP`): dirt/surface/planks/bones 3, scrap ore/pipe 4, concrete/toxic 5, circuits 6. Pickaxe damage =
  1 x (1 + `dig_speed_bonus`), so Steady Hands +50% digs dirt in 2 hits. Crack overlay in 4 stages.
  Drops (`DROPS`, x loot multiplier): dirt 8% scrap, scrap ore/pipe scrap, concrete concrete, circuit vein circuits,
  planks wood, bones 25% scrap, toxic nothing (decor). Ores (`kind_for`): only 1-3 blocks under the surface (the
  diggable depth), chance grows with depth and distance; suburb mostly planks, market concrete/pipes, depot scrap/
  concrete/toxic; circuits only 2+ deep and more than 60% of the way out.
  **Digging rule (so nobody gets stuck):** top-down only (you dig the top block of a column; the ground stays a
  height map), at most `MAX_DIG_DEPTH` 4 below the natural surface, bedrock never breaks, protected columns
  (hatch +-3 = spawn, crates +-1, pack +-1, trees) can't be dug, and a block is refused if afterwards some column
  could no longer be left by steps of at most `MAX_CLIMB` 2 blocks up to an undug column (`escapable()`, a flood
  fill over 300 columns). The player jumps ~2.7 blocks, so a 1-wide shaft can go 2 deep; deeper needs a staircase.
  Refusals show a short message ("Too deep to dig here.", "Too steep: you couldn't climb back out.").
  Target: column under the mouse (when aiming with the mouse), else the column in front, else under the feet,
  each only within 34 px of the chest. Dug blocks get a dark back wall so holes read as holes.
  The camera now follows the player down into holes (limit_bottom 270 on the surface, up to 336).
- **Zombies** (`actors/zombie.gd/.tscn`): CharacterBody2D on collision layer 8, mask 1 (world only: passes
  through the player and other zombies; hits are distance checks). HP 4. Wander 18 px/s, chase 60 px/s (player
  100), sight 96 px (6 tiles), lose sight at 200 px. Attack within 18 px: 0.4 s windup (leans in), hits 1
  half-heart via `player.take_damage(1, "zombie", pos)` if still within 24 px, 1 s cooldown. Hurt: knockback 90
  px/s for 0.3 s. Dead: fall/fade 0.8 s, 30% drop of food or scrap. Hops 1-block steps (`STEP_JUMP`), can't climb
  2 (they can fall into your holes). The hatch safe zone (96 px = 6 tiles) acts like a wall for them.
- **Spawner** (`scenes/zombie_spawner.gd`): slots per side 2 suburb / 4 market / 6 depot, x(1 + 0.2 per day after
  the first, max x2), via the new optional `GSBridge.day()` (`get_day()` or the `day` variable, default 1).
  No slot within 224 px (14 tiles) of the hatch. A slot spawns only 260-560 px from the player (off-screen),
  at most `CAP` 8 alive within 560 px; zombies more than 820 px away are removed (the slot waits again);
  a killed zombie's slot comes back after 40 s. Checks run every 0.5 s (cheap on the web).
- **HUD:** first zombie on screen -> one-time hint via `SettingsStore.hint_once("first_zombie")` (looked up by
  class name, guarded; `hud.hint_once(id, text)`). Death by zombie uses reason "zombie" (DEATH_TEXT). Any non-
  radiation hit shakes the camera (`expedition.shake`); landing a hit on a zombie shakes it lightly.
- **Art hooks** (all optional, placeholders until then): `obj_trees.png` (6 objects on transparent background,
  split by empty columns: tall, medium, short tree, stump, log, bush), `tiles_ore.png` and `tiles_crack.png`
  (used as is at exactly 64x32 / 64x16, other sizes are read back and scaled), `fx_chips.png` (8 pieces split by
  empty columns), `characters_clean/zombie_{walk,attack,death,hurt}_N.png`, `survivor_chop_N.png`.
  Note: splitting/scaling needs a GPU readback (`Texture2D.get_image()`); if that fails on a browser, the
  placeholder is used instead of crashing. Exact-size atlases avoid the readback entirely.
- Tests switch zombies off with `expedition.zombies_enabled = false` before adding the scene (the timed walks in
  `test_expedition.gd` would otherwise be interrupted); `tools/test_phase2.gd` covers the new systems.

## Phase 3: lights and shadows
Module: `scenes/lighting.gd` (class `Lighting`) + `scenes/light_source.gd` (class `LightSource`, a PointLight2D).
The expedition loads it with `load()` in `_setup_lighting()`, so the game still runs if the file is missing.
- **Quality** (`SettingsStore` `lights_quality`): `full` = ambient + lights + shadows on the headlamp/cone,
  cap 6 world lights; `simple` = ambient + lights, no occluders, cap 3; `off` = no CanvasModulate, no lights,
  no occluders (exactly the old look). Applied live: the pause menu's `settings_changed(key, value)` signal
  (`lighting.watch(pause_menu)`) plus a 0.5 s poll of SettingsStore (SettingsStore itself has no signal; the poll
  also catches changes from other screens). Lighting runs with PROCESS_MODE_ALWAYS so it applies while paused.
  Debug builds: **F2** cycles full -> simple -> off (not saved; the next real settings change wins).
- **Ambient** (expedition `dusk_ambient()`, constants at the top of expedition.gd): `DUSK` x zone tint
  (`ZONE_TINT`: suburb warm, market neutral, depot green, blended) x (1 - `DARK_DIST` x distance - `DARK_RAD` x
  radiation). Lighting smooths it (`AMBIENT_SMOOTH`) and never lets it drop below `MIN_BRIGHTNESS` 0.35 luminance.
- **Player**: headlamp (radius 110, warm white) at the chest; its energy rises as the ambient darkens
  (`HEADLAMP_ENERGY` 0.25..1.0). Flashlight (hotbar slot 3 selected): a 180 px cone texture generated once,
  rotated to the facing side, tilted 0.12 rad down. Both are children of the player and exist only when quality != off.
  The headlamp does not light the parallax background (background items use light_mask 2, the headlamp only mask 1).
- **World lights** (LightSource, cap + only near the camera, refresh every 0.2 s, no allocation per frame):
  hatch lamp (warm, flicker, priority so it always survives the cap = the safe-zone marker), Last Stand Pack (yellow
  pulse), toxic glow pool (3 green lights placed on the nearest exposed toxic tiles within 320 px: surface toxic
  tiles in the depot and toxic crystals once a side or top is dug open). Flicker = 3 sines, pulse = 1 sine.
- **Shadows**: generated occluder polygons from the ground height map (`mining.floor_rows`), 20 columns per
  LightOccluder2D (15 total), with a 5 px lit skin on top and on exposed side faces (so the ground surface and hole
  walls still catch the headlamp). `mining.block_broken` -> `lighting.refresh_ground_col(col)` rebuilds that chunk
  (and its neighbour at a chunk edge). Shadow filter NONE. Only the headlamp and cone cast shadows, only in full.
- **Zombie eyes** (placeholder eye rects) are in group `light_glow`; Lighting sets their `self_modulate` to
  1/ambient brightness (max x3) so they stay bright in the dark. No light per zombie.
- **Not darkened**: HUD, vignette, fade, pause menu, tutorial are CanvasLayers (checked in the test).
- **Cost**: CanvasModulate is free. Each enabled light is an extra per-pixel pass over the items inside its rect;
  the shadow-casting lights also render a 1D shadow map from 15 small polygons. Worst case on screen: 6 world
  lights + headlamp + cone in full, 3 + 2 in simple. Not measured on a real GPU or in a browser yet: if the web
  build is slow, "simple" drops the shadows, "off" drops everything.
- Screenshots: `tools/shots/shot_light_{hatch,depot,hole}.json` with `SHOT_QUALITY=full|simple|off` (see COMMANDS).

## Art V2 batch (new artist PNGs)
Cleaned by `art_tools/clean_art.py` from `../art_raw_v2/{chars,world}` (raws untracked); list in `art/ART_INDEX.md`.
- **Zombie**: `zombie_walk_0..3` (17x32), `zombie_attack_0..2` (29x30), `zombie_hurt_0..1` (24x32), all facing right,
  flipped by `facing`. No death frames: `_die()` holds the last hurt frame, tints it `DEATH_TINT`, sinks 3 px and fades
  (same 0.8 s). Glowing eyes: an `Eyes` AnimatedSprite2D child (group `light_glow`) made once from the bright
  yellow-green pixels of every frame (needs a texture readback; skipped where it fails).
- **Player**: `survivor_chop` (axe swing), `survivor_mine` (pickaxe), `survivor_flashlight_idle` when standing with the
  flashlight selected (`player.held_tool`, set by the expedition from `Inventory.selection_changed`), `survivor_climb`
  loaded as anim `climb` (not played yet: for the walkable bunker).
- **Trees** (`actors/tree.gd`): small = `obj_tree_dead` (50x80), medium = `obj_tree_oak` or `obj_tree_oak_orange`
  (orange on every third column), large = `obj_tree_pine` (82x128); `obj_stump` after falling; wood pickups from trees
  are drawn with `obj_logs`. Hp/logs/hit boxes unchanged. `obj_tree_sapling`, `obj_bush`, `obj_branch` unused so far.
  The old `obj_trees.png` sheet is no longer used.
- **Ore atlas** `tiles_ore.png` (64x32, mining.gd order): scrap ore = silver ore (tiles_ore3), concrete = grey stone
  chunks (tiles_ore2), circuits = gold ore (tiles_ore3), bedrock = plain stone (tiles_ore3) darkened blue-grey,
  planks / pipe / bones = dirt-with-rocks / dirt-with-pebbles (tiles_ore) with the stones recoloured wood / rust / bone
  and the dirt darkened toward `tiles_outside_dirt`, toxic = toxic green veins (tiles_ore2). Mapping: `ORE_ATLAS` in
  clean_art.py. `tiles_crack.png` 64x16 (4 stages). Surface and dirt still come from `tiles_outside.png`.
- Screenshots: `tools/shots/shot_zombie.json` (flashlight idle, a zombie attacking, one walking), `shot_ore.json`
  (every ore tile in a pit wall + cracks), `shot_chop.json` (mid axe swing on a pine), plus the old ones.
