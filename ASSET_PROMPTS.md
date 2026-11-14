# Asset Prompts for ChatGPT (BUNKER 7)

## 0. How to work with ChatGPT so assets match

1. **Check the jam rules about AI art first.** Some jams ban it or require you to disclose it.
2. Make **one ChatGPT chat per asset type** (characters, tiles, backgrounds, UI). Keep each chat open so it remembers the style.
3. **Paste the STYLE BLOCK at the top of every prompt.** This is what keeps everything looking like one game.
4. **Generate the player first.** Once you like it, attach that image to every later character prompt and say *"match this character exactly"*.
5. Ask for a **solid magenta background (#FF00FF)** on characters and objects. It's easy to remove later and leaves less of a white halo than a white background. (Check the edges after removal and clean stray pixels.)
6. Ask for **one asset per request**, or a sheet with at most ~9 items. More than that and quality drops.
7. **Be honest about pixels:** ChatGPT does not make pixel-perfect pixel art. The trick is to pick one scale, then shrink every image to that scale with **nearest-neighbor** resizing (Piskel / Aseprite / any editor, never "smooth") so it looks clean. Don't mix assets at different pixel sizes.
8. Walk cycles from AI often have frames that don't line up. Don't fight it: a **2-frame walk + a tiny bounce in code** looks great. Spend the saved time elsewhere.
9. Keep a shared folder with approved assets only. Name them clearly: `player_idle.png`, `tile_dirt.png`.

### Target sizes (pick these and never change)
| Thing | Size |
|---|---|
| Tile | 16×16 px |
| Player | 16×32 px (1 tile wide, 2 tall) |
| Rat | 16×16 px |
| Raider | 16×32 px |
| Drone | 24×16 px |
| Icons | 16×16 px |
| Screen | 480×270 px, scaled up ×4 to 1920×1080 |

Generate big (e.g. 1024×1024), then downscale. In Godot set Project Settings → Rendering → Textures → Default Texture Filter = **Nearest**.

---

## 1. STYLE BLOCK (paste this at the start of EVERY prompt)

```
STYLE: 2D side-view pixel art game asset in the style of Terraria. Chunky, readable pixels, 1-pixel dark outline, flat shading with 2-3 tones per material, no gradients, no anti-aliasing, no blur, no text, no watermark, no drop shadow. Limited palette of about 24 colors: rust orange, faded olive green, concrete gray, dirty beige, deep brown, near-black blue shadows, with toxic yellow-green (#B6E21F) reserved only for radiation, glowing eyes and warning lights. Mood: post-nuclear-war, dusty, lonely, but readable and slightly cute, not gory.
```

---

## 2. WORLD LOOK (the art bible, for everyone on the team)

**Surface (outside):** A dead city after nuclear war. Sky is a heavy dusty orange-brown at permanent dusk, with a pale sick sun behind haze. Ruined concrete buildings with broken windows, rusted cars, dead bare trees, cracked asphalt, rubble. Ground is gray-brown dirt with dead dry grass. Radiation shown as faint toxic green haze and glowing green puddles. Far = flatter and hazier, near = more detail.

**Bunker (inside):** A cramped underground cutaway, we see the rooms from the side like an ant farm. Concrete walls, riveted steel doors, exposed pipes, a flickering yellow lamp, stacked crates, a hand-written calendar, handmade shelves. Warm yellow light inside vs cold orange outside, so the bunker always feels like "safe". Each building you build visibly appears in a room.

**Characters:** Ordinary people in improvised gear. Everything patched, nothing military-clean. Silhouettes must be readable at 16×32.

---

## 3. CHARACTERS

### 3.1 Player: the Survivor (DO THIS FIRST)
```
[STYLE BLOCK]
Full-body character concept, side view facing right, standing neutral pose. A lone survivor in a worn orange-yellow hazmat jacket, patched dark jeans, heavy brown boots, a gray gas mask pushed up on the forehead, a small backpack with a rolled-up blanket, a flashlight clipped on the chest strap. Slightly large head, short body, friendly readable face, messy dark hair. Proportions 1:2 (width:height), designed to read clearly at 16x32 pixels. Solid magenta (#FF00FF) background, character centered, nothing else in the image.
```

### 3.2 Player animation sheets (attach the approved 3.1 image to each)
```
[STYLE BLOCK]
Using the attached character exactly (same design, colors, proportions, outline), create a sprite sheet: ONE horizontal row of 4 frames, <ANIMATION>. Every frame the same size, evenly spaced, the feet on the same baseline, the character the same scale in every frame, facing right. Solid magenta (#FF00FF) background.
```
Replace `<ANIMATION>` with each of these, one request per animation:
- `idle breathing cycle (subtle chest and head movement)`
- `walk cycle (2 contact poses and 2 passing poses)`  *(or ask for 2 frames only)*
- `jump: crouch, rising, peak, falling`
- `mining swing with a small pickaxe: raise, swing, hit, recover`
- `hurt flinch, 2 frames then standing`
- `collapse: stumbles, falls to knees, lies on the ground` **(death)**
- `wake-up (the BOUNCE BACK!): lying on a cot, eyes open, sitting up, standing, stretching` **(make this one nice, it's the theme)**

### 3.3 Enemies and others
```
[STYLE BLOCK]
Side view facing right, full body. An irradiated mutant rat, the size of a cat, patchy gray fur, bald pink tail, glowing toxic yellow-green eyes, a few green radioactive drips. Cartoonish, not gory. Designed to read at 16x16 pixels. Solid magenta (#FF00FF) background.
```
```
[STYLE BLOCK]
Side view facing right, full body. A wasteland raider, human, wrapped in a ragged dark red scarf covering the face, patched leather vest, welding goggles, holding a baseball bat wrapped with nails and tape. Skinny, hunched, menacing but not gory. Designed to read at 16x32 pixels. Solid magenta (#FF00FF) background.
```
```
[STYLE BLOCK]
Side view facing right. A rusty old security drone, round dented body, one cracked red lens eye, two small propellers, hanging wires, a faded military star sticker. Designed to read at 24x16 pixels. Solid magenta (#FF00FF) background.
```
```
[STYLE BLOCK]
Side view facing right, full body. A small scruffy stray dog with a torn red bandana, big sad eyes, wagging tail, ribs slightly visible but cute. Designed to read at 16x16 pixels. Solid magenta (#FF00FF) background.
```
(The dog is a stretch goal, a companion that follows you home. Everyone loves it.)

### 3.4 Radio operator portrait (optional, for the intro and events)
```
[STYLE BLOCK]
Bust portrait, front view, a tired middle-aged woman with a headset and static-filled old radio in front of her, dim green radio glow lighting her face. 64x64 pixel look. Solid magenta (#FF00FF) background.
```

---

## 4. TILES (the Terraria-like ground)

AI cannot produce a perfect tile grid. Two workable options:

**Option A (fast, recommended): use free CC0 tiles from [Kenney.nl](https://kenney.nl/assets) for the ground** and spend AI time on characters, backgrounds, and props.

**Option B: generate tiles with AI:**
```
[STYLE BLOCK]
A tileset sheet: a 4x4 grid of 16 seamless square tiles, each tile the same size with a thin gap between them, top-down NOT used, flat front view like Terraria. Tiles: 1 gray-brown dirt, 2 dirt with dead dry grass on top, 3 stone, 4 cracked asphalt top, 5 concrete rubble, 6 rusted metal plate, 7 bunker concrete wall, 8 bunker concrete floor, 9 riveted steel hatch, 10 bunker wall with pipe, 11 dirt with scrap metal buried inside, 12 dirt with green glowing radioactive vein, 13 brick wall damaged, 14 dark empty cave background tile, 15 wooden plank, 16 gravel. Each tile must tile seamlessly with itself. Solid magenta (#FF00FF) between and around tiles.
```
Then in Godot: Create a `TileSet`, add the image as an atlas, set the tile size to match, and paint collision only on **solid ground** tiles (not on background tiles).

---

## 5. BACKGROUNDS

### 5.1 Surface parallax (3 layers, each a wide image that repeats horizontally)
```
[STYLE BLOCK]
A wide horizontally-seamless background layer, side view, 1920x540 pixels. Layer 1 (far sky): dusty orange-brown sky, a pale sick sun behind thick haze, faint drifting ash clouds, no ground. The left and right edges must match perfectly so it can repeat.
```
```
[STYLE BLOCK]
A wide horizontally-seamless background layer, 1920x540, transparent/magenta sky. Layer 2 (far ruins): a flat hazy silhouette of a ruined city skyline, broken skyscrapers, cooling towers, smoke columns, muted brown-orange with low contrast, sits at the bottom of the image. Edges must match to repeat. Solid magenta (#FF00FF) behind the buildings.
```
```
[STYLE BLOCK]
A wide horizontally-seamless background layer, 1920x540, solid magenta behind. Layer 3 (near ruins): dead bare trees, wrecked rusty cars, broken fences, a leaning street sign, collapsed brick walls, slightly more detail and contrast than the far layer, sits at the bottom. Edges must match to repeat.
```

### 5.2 Bunker interior (the cutaway)
```
[STYLE BLOCK]
Side-view cutaway of a small underground bunker, like an ant-farm cross-section, 1920x1080. Three connected rooms side by side separated by concrete walls with riveted steel doors: left room is a bedroom with a cot, small shelf and hand-drawn calendar; middle room is an empty utility room with exposed pipes and a bare floor space for machines; right room is storage with stacked crates. A ladder up on the far right goes to a hatch in the ceiling. Warm flickering yellow lamp light, cold dark concrete, dirt and rock visible around the cutaway. Leave floor space empty so buildings can be added later.
```

### 5.3 Title screen key art
```
[STYLE BLOCK]
Title screen key art, 1920x1080. The survivor standing alone at the bunker hatch on a ruined hill at dusk, looking at a distant glowing city on the horizon, a faint green aurora in the orange sky, a stray dog sitting beside them. Empty space at the top for a game title. Cinematic, hopeful in a sad way.
```

---

## 6. BUNKER BUILDINGS & PROPS (one sheet per 6-9 objects)
```
[STYLE BLOCK]
A sheet of 6 separate bunker furniture and machine sprites, side view, evenly spaced, same pixel scale, on a solid magenta (#FF00FF) background: 1 water purifier (barrel with filter tubes and a dripping tap), 2 hydroponic garden (metal shelf with grow lamps and green lettuce), 3 air filter (wall machine with a fan and green status light), 4 reinforced door (thick steel door with extra bars and bolts), 5 radio beacon (old radio with a tall antenna, a blinking red light), 6 cot with a blanket and a pillow.
```
```
[STYLE BLOCK]
A sheet of 6 separate world props on a solid magenta (#FF00FF) background: 1 closed scavenge crate (wooden, military-green), 2 opened empty crate, 3 bunker hatch (round steel door set in the ground with a ladder), 4 glowing green radiation puddle, 5 warning sign with a radiation symbol on a pole, 6 the Last Stand Pack (a dropped, slightly open backpack with a faint white glow, so players can find it).
```

---

## 7. ICONS AND UI (16×16 look, one sheet)
```
[STYLE BLOCK]
A sheet of 9 separate HUD icons in a 3x3 grid, each centered and the same size, on a solid magenta (#FF00FF) background: 1 water bottle, 2 canned food, 3 scrap metal gear, 4 circuit board, 5 medkit, 6 heart (health), 7 radiation trefoil symbol, 8 bouncing-ball-spring arrow (BOUNCE = life) shown as a small red heart with a spring under it, 9 calendar page.
```
```
[STYLE BLOCK]
Game UI frame elements on a solid magenta background: a wide rectangular panel with a rusty riveted steel border and dark inner fill, a smaller button in normal state and a pressed state, a horizontal bar frame for the radiation meter, and a card frame for a night event (paper with a taped corner and a coffee stain).
```

---

## 8. QUICK FIXES IF CHATGPT MISBEHAVES
- **Style drifts:** re-paste the STYLE BLOCK and attach the approved image: *"Same style and palette as the attached image."*
- **Smooth, not pixelated:** add *"Strict hard-edged pixel art, visible square pixels, nearest-neighbor look, no smoothing."*
- **Background not clean:** *"Pure flat #FF00FF background, no shadows, no gradient, no ground."*
- **Frames misaligned:** make fewer frames (2), or generate one pose per request and assemble in Piskel.
- **Wrong proportions:** *"The character is exactly twice as tall as wide."*
- **Still bad after 3 tries:** swap in a Kenney asset. Don't burn the hackathon on one sprite.
