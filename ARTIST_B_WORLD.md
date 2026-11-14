# ARTIST B — World, Bunker Rooms, Props & UI

You make everything the characters **live in and use**: ground tiles, sky and city backgrounds, bunker rooms, buildings, pickups, icons and menus.
Artist A makes the characters. **Wait for their approved `survivor_concept.png` before the scale step (B0).** Until then do B1 and B2, which don't need it.

Check the jam rules about AI art before you start. Some jams ban it or require disclosure.

---

## How this works (read once)

1. Open a **new ChatGPT chat** just for you. Paste the **SETUP** message and wait for "Ready".
2. Paste prompts in the order below. Save every approved image with the file name given into the shared folder `art/world/`.
3. **Tiles and backgrounds are the hardest things for AI.** AI can't make a perfect tile grid or a perfect seamless loop. That's OK, the coders can fix it:
   - Tiles: the coders cut your sheet into pieces. If it looks wrong, use free tiles from **kenney.nl** for the ground instead and spend your time on rooms, props and icons.
   - Backgrounds: if the left and right edges don't match, tell ChatGPT *"make the left 10% and right 10% of the image identical so it loops"*, or the coders mirror the image to hide the seam.
4. If the style drifts, paste the SETUP again and attach an approved image: *"Match the attached image's style and palette exactly."*
5. Ask for **one sheet per request, never more than 9 items**. More than that and quality drops.

**Priority:** `MUST` = the game doesn't work without it. `SHOULD` = if time. `COULD` = bonus.

---

## SETUP (paste first, in a NEW chat)

```
I'm making a 2D pixel-art game for a game jam. It's a side-view survival game set in a bunker and ruined city after a nuclear war, with a look similar to Terraria. I will send you many asset requests in this chat. For ALL of them, follow these rules exactly and keep every image consistent with the previous ones.

STYLE RULES: 2D side-view pixel art. Chunky, readable pixels with a 1-pixel dark outline. Flat shading with 2-3 tones per material. No gradients, no anti-aliasing, no blur, no drop shadows, no text, no labels, no watermarks. Strict hard-edged pixel art with visible square pixels, as if drawn at the target pixel size I give you and then enlarged. Mood: post-nuclear-war, dusty, lonely, but readable and slightly cute. Not gory.

COLOR PALETTE (use only these families): outline near-black blue #14121F, rust orange #C2602B, dark rust #7A3A1E, olive green #6B7A3A, dark olive #3E4A2A, concrete gray #8A8D8F, dark concrete #4B4E55, dirty beige #C9B38C, deep brown #4A3222, warm lamp yellow #F2C14E, danger red #B8322A. Toxic yellow-green #B6E21F is ONLY for radiation, glowing eyes and warning lights.

WORLD LOOK: OUTSIDE is a dead city after nuclear war at permanent dusk: heavy dusty orange-brown sky, a pale sick sun behind haze, ruined concrete buildings with broken windows, rusted cars, dead bare trees, cracked asphalt, rubble. Gray-brown dirt with dead dry grass. INSIDE the bunker is cramped and underground, shown from the side like an ant-farm cutaway: concrete walls, riveted steel doors, exposed pipes, a warm flickering yellow lamp, stacked crates. Warm yellow light inside versus cold orange outside, so the bunker always feels like the safe place.

BACKGROUND RULE: objects and items are always on a pure flat solid magenta #FF00FF background, with no shadow, no ground, no gradient. Full scenes and backgrounds are filled pictures with no magenta unless I say so.

When I attach an image, match its design, colors, proportions and outline exactly.

Reply only "Ready".
```

---

## B0 — Scale lock (MUST, after Artist A sends the survivor)

Attach `survivor_concept.png` from Artist A. Ask for no image.

```
This is our main character, the survivor. Use him as the scale reference for everything I ask from now on. The survivor is 2 tiles tall and 1 tile wide, where one tile is a 16x16 pixel block. So: a normal doorway is 3 tiles tall, a cot is about 2 tiles wide and 1 tile tall, a crate is 1 tile, a hatch is 2 tiles wide, machines like a water purifier are 2 tiles wide and 2 tiles tall. Keep every object's size consistent with that. Reply only "Understood".
```

---

## B1 — Ground tiles (MUST)

Tiles are drawn on a **4x2 grid** (8 tiles per sheet), flat front view like Terraria (not top-down). Each tile must be seamless with itself. If you need a different look, just regenerate.

### B1.1 Outside tiles → `tiles_outside.png`
```
Follow the STYLE RULES from my first message. A tileset sheet: a 4x2 grid of 8 separate square tiles, each tile the same size with a thin magenta gap between them, flat side view like Terraria, each tile designed at 16x16 pixels and seamless with itself. Tiles, left to right, top row then bottom row: 1 gray-brown dirt, 2 dirt with dead dry grass on top, 3 stone, 4 cracked asphalt on top of dirt, 5 concrete rubble, 6 gravel, 7 dirt with scrap metal buried inside, 8 dirt with a glowing toxic green #B6E21F radioactive vein. Wide landscape image, pure flat magenta #FF00FF between and around the tiles.
```

### B1.2 Bunker and building tiles → `tiles_bunker.png`
```
Follow the STYLE RULES from my first message. A tileset sheet: a 4x2 grid of 8 separate square tiles, each tile the same size with a thin magenta gap between them, flat side view like Terraria, each designed at 16x16 pixels and seamless with itself. Tiles, left to right, top row then bottom row: 1 bunker concrete wall, 2 bunker concrete floor, 3 riveted steel plate, 4 concrete wall with a pipe running across, 5 wooden planks, 6 damaged brick wall, 7 dark empty cave background (very dark, simple), 8 solid packed dirt (darker than outside dirt, for locked rooms). Wide landscape image, pure flat magenta #FF00FF between and around the tiles.
```

---

## B2 — Outside backgrounds (MUST: sky + far + near suburb)

These move at different speeds behind the player, which creates depth. Ask for a **wide landscape image**. These are filled pictures (the sky is not magenta). For layers that sit on top of other layers, the empty top part should be **flat magenta** so it can be cut out.

### B2.1 Sky → `bg_sky.png` (MUST)
```
Follow the STYLE RULES from my first message. A wide landscape background, no ground. A dusty orange-brown sky at dusk, a pale sick sun behind thick haze, faint ash clouds drifting, subtle darker orange at the top and lighter near the horizon (made of flat pixel color bands, not smooth gradients). The left and right edges must match perfectly so the image can loop horizontally.
```

### B2.2 Far city skyline → `bg_far.png` (MUST)
```
Follow the STYLE RULES from my first message. A wide landscape layer. A flat, hazy silhouette of a ruined city skyline: broken skyscrapers, cooling towers, thin smoke columns. Muted brown-orange with low contrast, it sits at the bottom of the image. Everything above the skyline is pure flat magenta #FF00FF so it can be cut out. The left and right edges must match so the image can loop horizontally.
```

### B2.3 Near ruins, suburb (MUST) → `bg_near_suburb.png`
```
Follow the STYLE RULES from my first message. A wide landscape layer. The near ruins of a suburb: dead bare trees, broken fences, collapsed brick walls, a wrecked rusty car, a leaning street sign, more detail and more contrast than the far skyline, sitting at the bottom of the image. Everything above is pure flat magenta #FF00FF. The left and right edges must match so the image can loop horizontally.
```

### B2.4 Near ruins, supermarket and gas station (SHOULD) → `bg_near_market.png`
```
Follow the STYLE RULES from my first message. A wide landscape layer. The near ruins of a supermarket and a gas station: a broken shop sign, empty shopping carts, collapsed pumps, a crashed truck, shattered glass fronts. More detail than the far skyline, sitting at the bottom of the image. Everything above is pure flat magenta #FF00FF. The left and right edges must match so the image can loop horizontally.
```

### B2.5 Near ruins, military depot (SHOULD) → `bg_near_depot.png`
```
Follow the STYLE RULES from my first message. A wide landscape layer. The near ruins of a military depot: barbed wire fences, a tall radio tower with a red blinking light, a rusted tank, sandbag walls, a faded radiation warning sign. A faint toxic green #B6E21F glow near the ground. Sitting at the bottom of the image. Everything above is pure flat magenta #FF00FF. The left and right edges must match so the image can loop horizontally.
```

---

## B3 — The bunker rooms (MUST)

The bunker is a side-view cutaway with **5 rooms**. The player starts with only the Bedroom. The others are locked until they pay materials, so each needs an empty interior **and** a shared locked look. Each room interior should be a **wide landscape image with the floor area left empty** (the buildings are added as separate pictures).

### B3.1 Overview, for the team's reference → `bunker_overview.png` (SHOULD)
```
Follow the STYLE RULES from my first message. A full-scene side-view cutaway of a small underground bunker, like an ant-farm cross-section, as a wide landscape image. FIVE rooms side by side separated by concrete walls with riveted steel doors, with a ladder going up on the far left to a round hatch in the ceiling that leads outside. Only the first room (the bedroom, with a cot, a small shelf and a hand-drawn calendar) is lit and finished. The other four rooms are LOCKED: filled with dark packed dirt and rock with faint outlines of rooms inside. Warm flickering yellow lamp light in the bedroom, cold dark rock around. Keep the floors of all rooms empty and flat.
```

### B3.2 Bedroom (start room) → `room_bedroom.png` (MUST)
```
Follow the STYLE RULES from my first message. A single bunker room interior, side view, wide landscape image, no magenta. A cramped concrete bedroom: a hand-drawn calendar with crossed-out days on the wall, a small wooden shelf with a few tin cans, a lamp hanging from the ceiling giving warm yellow light, a ladder on the left going up to the ceiling hatch. The floor is a flat concrete strip along the bottom. The center of the room is EMPTY floor space so a cot and furniture can be added later.
```

### B3.3 Utility room → `room_utility.png` (MUST)
```
Follow the STYLE RULES from my first message. A single bunker room interior, side view, wide landscape image, no magenta. A concrete utility room with exposed pipes running along the walls and ceiling, a few valves, a hanging lamp with warm yellow light, wall-mounted fuse boxes. The floor is a flat concrete strip along the bottom. The floor space in the center is EMPTY so machines can be added later.
```

### B3.4 Garden room → `room_garden.png` (SHOULD)
```
Follow the STYLE RULES from my first message. A single bunker room interior, side view, wide landscape image, no magenta. A concrete room with a high ceiling, a few empty mounting hooks for grow lamps, a drain in the floor, a stack of empty plastic trays against a wall, warm yellow lamp light. The floor is a flat concrete strip along the bottom. The floor space in the center is EMPTY so a hydroponic garden can be added later.
```

### B3.5 Storage room → `room_storage.png` (SHOULD)
```
Follow the STYLE RULES from my first message. A single bunker room interior, side view, wide landscape image, no magenta. A concrete storage room with empty steel shelves along the walls, a couple of stacked empty wooden crates in the corner, a hanging lamp with warm yellow light. The floor is a flat concrete strip along the bottom. The center of the floor is EMPTY.
```

### B3.6 Radio room → `room_radio.png` (SHOULD)
```
Follow the STYLE RULES from my first message. A single bunker room interior, side view, wide landscape image, no magenta. A concrete radio room with a big wall map of the region with pins, a dusty empty desk, cables running along the ceiling to a hole where an antenna cable leads upward, a lamp with warm yellow light. The floor is a flat concrete strip along the bottom. The center of the floor is EMPTY so a radio can be added later.
```

### B3.7 Locked room look → `room_locked.png` (MUST)
```
Follow the STYLE RULES from my first message. A single bunker room shown LOCKED, side view, wide landscape image, no magenta. The same room size as a bunker room but completely filled with dark packed dirt and rock, with faint lighter outlines suggesting a room carved inside, a few roots, and a small rusty padlock symbol in the middle. Dark, mysterious, unfinished.
```

### B3.8 Damaged room look (for night events) → `room_damaged_overlay.png` (COULD)
```
Follow the STYLE RULES from my first message. An overlay picture to show a bunker room has been damaged, wide landscape image, on a pure flat magenta #FF00FF background: cracks running across the wall, a few chunks of fallen concrete and dust on the floor, a hanging broken lamp, a small leak dripping. Only the damage details, nothing else, so it can be placed on top of a room.
```

---

## B4 — Bunker buildings (MUST for the first sheet)

### B4.1 Machines and furniture → `buildings_sheet.png`
```
Follow the STYLE RULES from my first message. A sheet of 6 separate bunker sprites in a 3x2 grid, side view, the same pixel scale and the same lighting, evenly spaced, on a pure flat magenta #FF00FF background. Sizes relative to a 2-tile-tall person: 1 water purifier (2x2 tiles: a barrel with filter tubes and a dripping tap), 2 hydroponic garden (2x2 tiles: a metal shelf with grow lamps and green lettuce), 3 air filter (1x2 tiles: a wall machine with a fan and a green status light), 4 reinforced door (1x3 tiles: a thick steel door with extra bars and bolts), 5 radio beacon (2x2 tiles: an old radio with a tall antenna and a blinking red light), 6 cot (2x1 tiles: a metal cot with a gray blanket and a pillow).
```

---

## B5 — Things in the outside world (MUST)

### B5.1 World objects → `world_objects.png`
```
Follow the STYLE RULES from my first message. A sheet of 6 separate sprites in a 3x2 grid, side view, same pixel scale, evenly spaced, on a pure flat magenta #FF00FF background: 1 closed scavenge crate (wooden, military green, 1x1 tile), 2 the same crate opened and empty, 3 the bunker hatch (a round steel door set into the ground with a short ladder going down, 2 tiles wide), 4 a glowing toxic green #B6E21F radioactive puddle (2 tiles wide, flat), 5 a radiation warning sign on a pole, 6 the Last Stand Pack (a dropped, slightly open backpack with a faint white glow around it so players can spot it).
```

### B5.2 Pickups (the materials you carry back) → `pickups.png`
```
Follow the STYLE RULES from my first message. A sheet of 8 separate small item sprites in a 4x2 grid, each designed at 16x16 pixels, same pixel scale, evenly spaced, on a pure flat magenta #FF00FF background: 1 a bundle of wooden planks tied with rope, 2 a pile of concrete blocks, 3 a heap of scrap metal with gears, 4 two water bottles, 5 a box of canned food, 6 a circuit board inside a small metal case with a faint glowing edge (rare item), 7 a medkit with a red cross, 8 a small glowing white sparkle (used to mark a rare find).
```

---

## B6 — Icons (MUST)

Icons are 16x16 in-game. Ask for **bold, simple shapes** that read when small.

### B6.1 Resource icons → `icons_resources.png`
```
Follow the STYLE RULES from my first message. A sheet of 6 separate icons in a 3x2 grid, each designed at 16x16 pixels, bold simple shapes, centered in their cells, evenly spaced, on a pure flat magenta #FF00FF background: 1 wood plank, 2 concrete block, 3 scrap metal gear, 4 water bottle, 5 canned food, 6 circuit board.
```

### B6.2 Status icons → `icons_status.png`
```
Follow the STYLE RULES from my first message. A sheet of 6 separate icons in a 3x2 grid, each designed at 16x16 pixels, bold simple shapes, centered in their cells, evenly spaced, on a pure flat magenta #FF00FF background: 1 heart (health), 2 radiation trefoil symbol in toxic green #B6E21F, 3 a small red heart sitting on a spring (this is "Bounce", the player's lives), 4 calendar page, 5 medkit, 6 small rusty padlock (locked).
```

### B6.3 Scar (upgrade) icons → `icons_scars.png`
```
Follow the STYLE RULES from my first message. A sheet of 5 separate icons in a 5x1 row, each designed at 24x24 pixels, bold simple shapes, evenly spaced, on a pure flat magenta #FF00FF background: 1 "Thick Skin" (a skin-colored shield with a scar line), 2 "Scavenger's Eye" (an eye with a small magnifying glass), 3 "Light Feet" (a boot with small wings), 4 "Iron Gut" (a stomach in a metal can), 5 "Steady Hands" (an open hand holding a pickaxe).
```

---

## B7 — Interface (SHOULD)

### B7.1 Panels and buttons → `ui_panels.png`
```
Follow the STYLE RULES from my first message. A sheet of game menu elements, on a pure flat magenta #FF00FF background, evenly spaced: a wide rectangular panel with a rusty riveted steel border and a dark inner fill; a button in its normal state and the same button pressed (a slightly darker, lower version); a horizontal bar frame for a radiation meter (empty frame, with a hazard-stripe end cap); a small square slot frame for an inventory item. No text anywhere.
```

### B7.2 Night event card frame → `ui_event_card.png`
```
Follow the STYLE RULES from my first message. A single game card frame, portrait orientation, on a pure flat magenta #FF00FF background: a sheet of old paper with a taped corner, a coffee stain, a darker header strip at the top, a framed empty box in the upper half for a picture, and empty space below for text. No text anywhere.
```

---

## B8 — Night event illustrations (COULD)

Small scene thumbnails to put in the event cards. Full pictures (no magenta). One request per sheet.

### B8.1 Six event thumbnails → `events_sheet.png`
```
Follow the STYLE RULES from my first message, but these are FULL small scenes (no magenta background). A sheet of 6 separate wide thumbnails in a 3x2 grid, each in its own square frame with a thin dark border, evenly spaced: 1 raiders knocking at the bunker's steel door (two silhouettes with a flashlight), 2 a radiation storm sweeping over a ruined city with green lightning, 3 a burst pipe spraying water in a concrete room, 4 an old radio glowing in the dark with a mysterious waveform, 5 a couple of mutant rats in a pantry nibbling at cans, 6 a quiet night: the bunker lamp glowing and a kettle steaming on a small stove.
```

---

## Handoff checklist
- [ ] Waiting on / received `survivor_concept.png` from Artist A, B0 done
- [ ] Tiles, sky, far and near backgrounds ready
- [ ] Bedroom, utility room and locked room ready
- [ ] Buildings sheet, world objects, pickups, icons ready
- [ ] Everything saved in `art/world/` with exact file names
