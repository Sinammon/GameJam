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
- **World:** 300 columns = 4800 px (10 screens), hatch at x=2400 (middle). Zones are mirrored:
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
  screen edge when you are more than 1.5 screens (720 px) from the hatch, and always from 60%.
- **HUD:** `scenes/hud.tscn` (CanvasLayer, drawn in code). Icons only, tiny numbers.
- **Inventory:** `scenes/inventory.gd` (hotbar of 5 tools, Tab backpack grid). The carry limit is still
  `GSBridge.carry_limit()`; the grid shows `carry_limit` unlocked slots, and the backpack tier only
  changes the total grid size (12/16/20/24). One slot = one item (matches the v1 carry rule: the
  limit counts items, not stacks); the grid groups them into stacks per material for display.
- **Input:** `pause` (Esc) replaces the debug quit; the pause menu (other agent) listens to it.
  `hotbar_1..5`, `inventory` (Tab), `attack` (left mouse) added.
