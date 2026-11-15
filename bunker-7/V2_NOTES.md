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
