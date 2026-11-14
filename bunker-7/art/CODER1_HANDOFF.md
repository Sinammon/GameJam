# Art handoff for Coder 1 (expedition, actors)

Clean, game-size pixel art from Coder 2. Nothing in `actors/`, `scenes/expedition.*` or `tools/` was touched.
Full file list with sizes: `art/ART_INDEX.md`. Regenerate from the raw PNGs with `python3 art_tools/clean_art.py --chars <dir> --world <dir>`.
Import: project default filter is Nearest; the .import files are lossless, no mipmaps. Nothing to change.

## Characters (`res://art/characters_clean/`)
Every frame of one animation has the same canvas, feet on the bottom edge, figure centred, facing right
(use `flip_h` for left). Origin tip: `AnimatedSprite2D.centered = false`, `offset = Vector2(-w/2, -h)` so (0,0) is the feet,
like the current `Body` ColorRect.

| animation | files | frame size | frames | suggested fps / loop |
|---|---|---|---|---|
| survivor idle | survivor_idle_0..3 | 14x32 | 4 | 4, loop |
| survivor walk | survivor_walk_0..3 | 17x32 | 4 | 8, loop |
| survivor jump | survivor_jump_0..3 | 19x33 | 4 | crouch, rise, peak, fall: pick by velocity.y, no loop |
| survivor mine | survivor_mine_0..3 | 28x36 | 4 | 8, loop while digging |
| survivor hurt | survivor_hurt_0..1 | 20x32 | 2 | 8, play once |
| survivor collapse (death) | survivor_collapse_0..3 | 30x32 | 4 | 4, play once, hold last |
| survivor wake-up | survivor_wakeup_0..3 | 31x32 | 4 | frames are stand -> lying; play 3..0 to get up (used on the scar screen) |
| rat run | rat_run_0..3 | 27x13 | 4 | 10, loop |
| raider walk | raider_walk_0..3 | 20x33 | 4 | 6, loop |
| raider attack | raider_attack_0..2 | 34x33 | 3 | 8, once |
| drone hover | drone_hover_0..2 | 27x24 | 3 | 8, loop |
| dog run | dog_run_0..3 | 22x18 | 4 | 10, loop |

`*_strip.png` = the same frames in one row (frame width = strip width / frames) if you prefer one AtlasTexture per animation.
Concept art (bigger, not for gameplay): survivor/raider_concept (64 tall), rat/drone/dog_concept.

Note: the survivor art is 32 px tall (2 tiles, as in the art brief); the player's collision box is 12x24. Either make the
shape ~12x30 or keep it and let the head stick out. Don't scale the sprite by 0.75 (non-integer scaling smears pixels).

SpriteFrames sketch:
```gdscript
var sf := SpriteFrames.new()
for anim in {"idle": 4, "walk": 4, "mine": 4, "hurt": 2, "collapse": 4, "jump": 4}.keys():
    sf.add_animation(anim)
    for i in {"idle": 4, "walk": 4, "mine": 4, "hurt": 2, "collapse": 4, "jump": 4}[anim]:
        sf.add_frame(anim, load("res://art/characters_clean/survivor_%s_%d.png" % [anim, i]))
$AnimatedSprite2D.sprite_frames = sf
```
(or build it once in the editor and save `survivor_frames.tres`).

## Outside backgrounds (`res://art/world_clean/`), all 810x270, transparent above the skyline
Parallax order, back to front (Parallax2D or ParallaxBackground):
1. `bg_sky.png` (opaque) – scroll ~0.0-0.05
2. `bg_far.png` – far city skyline, scroll ~0.2
3. one near layer per area, scroll ~0.5: `bg_near_suburb.png` (houses, car, sign), `bg_near_market.png` (supermarket + gas station), `bg_near_depot.png` (military depot, tank, radio tower)
4. ground tiles (TileMapLayer) in front.
Repeat horizontally (`repeat_size = Vector2(810, 0)`); the edges were not made seamless by the artist, so a seam may show.

## Tiles (16x16)
`tiles_outside.png` 64x32 atlas, 4x2: dirt, dirt_grass, stone, asphalt / rubble, gravel, dirt_scrap, dirt_toxic.
`tiles_bunker.png` 64x32 atlas, 4x2: concrete_wall, concrete_floor, steel_plate, pipe_wall / wood_planks, brick_damaged, cave_dark, dirt_packed.
Single tiles also exist as `tiles_outside_<name>.png` / `tiles_bunker_<name>.png`. dirt_grass and rubble have transparent pixels at the top.

## World objects and pickups
`obj_crate_closed` 16x12, `obj_crate_open` 16x16 (bottom-align them), `obj_hatch` 32x28, `obj_puddle` 31x12,
`obj_sign` 14x23, `obj_last_stand_pack` 19x20.
Pickups ~16x12: `pickup_wood`, `pickup_concrete`, `pickup_scrap`, `pickup_water`, `pickup_food`, `pickup_circuits`, `pickup_medkit`, `pickup_sparkle` (rare-find marker).
HUD icons (16x16): `icon_wood/concrete/scrap/water/food/circuits/health/radiation/bounce/day/medkit/locked`.
UI: `ui_bar_frame.png` 195x26 (radiation bar frame, hazard cap on the right), `ui_slot.png` 37x36 (item slot); `UIKit.button()` already uses the button art.
