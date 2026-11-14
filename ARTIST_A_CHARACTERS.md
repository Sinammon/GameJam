# ARTIST A — Characters, Creatures & Key Art

You make everything that **moves or has a face**: the survivor, enemies, the dog, portraits, title and ending screens.
Artist B makes the world (tiles, backgrounds, rooms, props, icons). **Your survivor image is the scale reference for Artist B, so send it to them the moment it's approved.**

Check the jam rules about AI art before you start. Some jams ban it or require disclosure.

---

## How this works (read once)

1. Open a **new ChatGPT chat** just for you. Paste the **SETUP** message below and wait for "Ready".
2. Paste prompts **in the order below**. Do **A1 first**. Keep generating (use "regenerate" or say what to change) until you love the survivor. Then **attach that approved image to every later prompt**.
3. Save every approved image with the file name in the prompt. Put them in the shared folder `art/characters/`.
4. If the style drifts, paste the SETUP again and attach an approved image: *"Match the attached image's style and palette exactly."*
5. Only draw the character **facing right**. The game can flip it for facing left.
6. ChatGPT won't make perfectly aligned frames. That's OK: the coders can use fewer frames and add small bounces in code. If a sheet comes out messy, regenerate once or twice, then ask for fewer frames.

**Priority:** `MUST` = the game doesn't work without it. `SHOULD` = do it if time. `COULD` = bonus.

---

## SETUP (paste first, in a NEW chat)

```
I'm making a 2D pixel-art game for a game jam. It's a side-view survival game set in a bunker and ruined city after a nuclear war, with a look similar to Terraria. I will send you many asset requests in this chat. For ALL of them, follow these rules exactly and keep every image consistent with the previous ones.

STYLE RULES: 2D side-view pixel art. Chunky, readable pixels with a 1-pixel dark outline. Flat shading with 2-3 tones per material. No gradients, no anti-aliasing, no blur, no drop shadows, no text, no labels, no watermarks. Strict hard-edged pixel art with visible square pixels, as if drawn at the target pixel size I give you and then enlarged. Mood: post-nuclear-war, dusty, lonely, but readable and slightly cute. Not gory.

COLOR PALETTE (use only these families): outline near-black blue #14121F, rust orange #C2602B, dark rust #7A3A1E, olive green #6B7A3A, dark olive #3E4A2A, concrete gray #8A8D8F, dark concrete #4B4E55, dirty beige #C9B38C, deep brown #4A3222, warm lamp yellow #F2C14E, danger red #B8322A. Toxic yellow-green #B6E21F is ONLY for radiation, glowing eyes and warning lights.

BACKGROUND RULE: characters and objects are always on a pure flat solid magenta #FF00FF background, with no shadow, no ground, no gradient. Each character is centered with space around it.

When I attach an image, match its design, colors, proportions and outline exactly.

Reply only "Ready".
```

---

## A1 — The Survivor (MUST, DO THIS FIRST)

Attach: nothing. Save as `survivor_concept.png`. **Send to Artist B when approved.**

```
Follow the STYLE RULES from my first message. Create a full-body character design, side view, facing right, standing in a neutral pose. A lone survivor in a worn orange-yellow hazmat jacket, patched dark jeans, heavy brown boots, a gray gas mask pushed up on the forehead, a small backpack with a rolled-up blanket, a flashlight clipped to the chest strap. Slightly large head, short body, messy dark hair, a friendly readable face. The body is exactly twice as tall as it is wide, designed to read clearly at 16x32 pixels. Square image, pure flat magenta #FF00FF background, character centered, nothing else in the image.
```

---

## A2 — Survivor animation sheets (attach `survivor_concept.png` to EVERY one)

Each prompt: attach the approved survivor image first. Save as the file name given.

### A2.1 Idle (MUST) → `survivor_idle.png`
```
Follow the STYLE RULES from my first message. Using the attached character exactly (same design, colors, proportions, outline), create a sprite sheet: ONE horizontal row of 4 frames of an idle breathing cycle (subtle chest and head movement, the rest still). Every frame is the same size and evenly spaced with equal gaps, the feet on the same baseline, the character the same scale in every frame, facing right. Wide landscape image, pure flat magenta #FF00FF background.
```

### A2.2 Walk (MUST) → `survivor_walk.png`
```
Follow the STYLE RULES from my first message. Using the attached character exactly, create a sprite sheet: ONE horizontal row of 4 frames of a walk cycle (contact pose, passing pose, contact pose on the other leg, passing pose). Every frame is the same size and evenly spaced with equal gaps, the feet on the same baseline, the character the same scale in every frame, facing right, backpack bouncing slightly. Wide landscape image, pure flat magenta #FF00FF background.
```

### A2.3 Jump (MUST) → `survivor_jump.png`
```
Follow the STYLE RULES from my first message. Using the attached character exactly, create a sprite sheet: ONE horizontal row of 4 frames of a jump: crouch to push off, rising with arms up, peak of the jump, falling with legs reaching down. Every frame the same size, evenly spaced, the character the same scale, facing right. Wide landscape image, pure flat magenta #FF00FF background.
```

### A2.4 Collapse = death (MUST) → `survivor_collapse.png`
```
Follow the STYLE RULES from my first message. Using the attached character exactly, create a sprite sheet: ONE horizontal row of 4 frames of the character dying from radiation: sways dizzily, drops to the knees, falls forward, lies on the ground. Every frame the same size, evenly spaced, the character the same scale, facing right, no gore. Wide landscape image, pure flat magenta #FF00FF background.
```

### A2.5 Wake-up = BOUNCE BACK (MUST, make this one special) → `survivor_wakeup.png`
```
Follow the STYLE RULES from my first message. Using the attached character exactly but WITHOUT the backpack and gas mask (he is in a plain t-shirt and jeans, just woke up), create a sprite sheet: ONE horizontal row of 5 frames: lying on a small cot with eyes closed, eyes open, sitting up, standing up, stretching with a determined look. Hopeful feeling, the first sign of a comeback. Every frame the same size, evenly spaced, the character the same scale, facing right. Wide landscape image, pure flat magenta #FF00FF background.
```

### A2.6 Mining swing (SHOULD) → `survivor_mine.png`
```
Follow the STYLE RULES from my first message. Using the attached character exactly, holding a small rusty pickaxe, create a sprite sheet: ONE horizontal row of 4 frames of a mining swing: raise the pickaxe overhead, swing down, hit, recover. Every frame the same size, evenly spaced, the character the same scale, facing right. Wide landscape image, pure flat magenta #FF00FF background.
```

### A2.7 Hurt (SHOULD) → `survivor_hurt.png`
```
Follow the STYLE RULES from my first message. Using the attached character exactly, create a sprite sheet: ONE horizontal row of 2 frames of getting hit: flinching backward with a pained face, then recovering to standing. Same size, same scale, facing right. Wide landscape image, pure flat magenta #FF00FF background.
```

---

## A3 — Creature designs (MUST: rat and raider; SHOULD: drone; COULD: dog)

Save as `rat_concept.png`, `raider_concept.png`, `drone_concept.png`, `dog_concept.png`. Attach `survivor_concept.png` to each to keep the same style and scale.

### Rat → `rat_concept.png`
```
Follow the STYLE RULES from my first message. Match the style and outline of the attached survivor. Side view facing right, full body. An irradiated mutant rat, the size of a cat, patchy gray fur, a bald pink tail, glowing toxic yellow-green #B6E21F eyes, a few green radioactive drips. Cartoonish, not gory. Designed to read at 16x16 pixels. Square image, pure flat magenta #FF00FF background.
```

### Raider → `raider_concept.png`
```
Follow the STYLE RULES from my first message. Match the style, outline and body proportions of the attached survivor (same 16x32 pixel scale). Side view facing right, full body. A wasteland raider: a ragged dark red scarf covering the face, a patched leather vest, welding goggles, holding a baseball bat wrapped with nails and tape. Skinny, hunched, menacing but not gory. Square image, pure flat magenta #FF00FF background.
```

### Drone → `drone_concept.png`
```
Follow the STYLE RULES from my first message. Match the style and outline of the attached survivor. Side view facing right. A rusty old security drone: round dented body, one cracked red lens eye, two small propellers on top, hanging wires, a faded military star sticker. Designed to read at 24x16 pixels. Square image, pure flat magenta #FF00FF background.
```

### Dog → `dog_concept.png`
```
Follow the STYLE RULES from my first message. Match the style and outline of the attached survivor. Side view facing right, full body. A small scruffy stray dog wearing a torn red bandana, big sad eyes, wagging tail, ribs slightly visible but very cute. Designed to read at 16x16 pixels. Square image, pure flat magenta #FF00FF background.
```

---

## A4 — Creature animation sheets (attach the matching concept image to each)

### Rat run (MUST) → `rat_run.png`
```
Follow the STYLE RULES from my first message. Using the attached rat exactly, create a sprite sheet: ONE horizontal row of 4 frames of a scurrying run cycle, facing right. Every frame the same size, evenly spaced, same scale, feet on the same baseline. Wide landscape image, pure flat magenta #FF00FF background.
```

### Raider walk (MUST) → `raider_walk.png`
```
Follow the STYLE RULES from my first message. Using the attached raider exactly, create a sprite sheet: ONE horizontal row of 4 frames of a slow menacing walk cycle holding the bat, facing right. Every frame the same size, evenly spaced, same scale, feet on the same baseline. Wide landscape image, pure flat magenta #FF00FF background.
```

### Raider attack (SHOULD) → `raider_attack.png`
```
Follow the STYLE RULES from my first message. Using the attached raider exactly, create a sprite sheet: ONE horizontal row of 3 frames of a bat swing: wind up, swing, follow through, facing right. Every frame the same size, evenly spaced, same scale. Wide landscape image, pure flat magenta #FF00FF background.
```

### Drone hover (SHOULD) → `drone_hover.png`
```
Follow the STYLE RULES from my first message. Using the attached drone exactly, create a sprite sheet: ONE horizontal row of 3 frames of hovering: propellers blurred in different positions, body bobbing slightly up and down, the red eye flickering, facing right. Every frame the same size, evenly spaced. Wide landscape image, pure flat magenta #FF00FF background.
```

### Dog run (COULD) → `dog_run.png`
```
Follow the STYLE RULES from my first message. Using the attached dog exactly, create a sprite sheet: ONE horizontal row of 4 frames of a happy trotting run cycle with a wagging tail, facing right. Every frame the same size, evenly spaced, same scale, paws on the same baseline. Wide landscape image, pure flat magenta #FF00FF background.
```

---

## A5 — Portraits (COULD)

### Radio operator → `portrait_radio.png`
```
Follow the STYLE RULES from my first message. A bust portrait, front view, of a tired middle-aged woman wearing a headset, an old radio with a glowing dial in front of her, dim green radio light on her face, a hopeful but exhausted expression. Pixel art that reads at 64x64 pixels. Square image, pure flat magenta #FF00FF background.
```

### Survivor expressions → `portrait_survivor.png`
```
Follow the STYLE RULES from my first message. Using the attached survivor: ONE horizontal row of 3 bust portraits, front view: neutral, hurt and in pain, determined with a small smile. Each reads at 48x48 pixels, same size, evenly spaced. Wide landscape image, pure flat magenta #FF00FF background.
```

---

## A6 — Key art and ending screens (SHOULD for title, COULD for the rest)

For these, **no magenta background**: they are full pictures. Ask for a wide landscape image. Attach `survivor_concept.png` (and `dog_concept.png` if the dog is in the shot).

### Title screen (SHOULD) → `title_art.png`
```
Follow the STYLE RULES from my first message, but this is a FULL scene (no magenta background). A wide landscape title screen picture. The survivor from the attached image stands alone at a round steel hatch on a ruined hill at dusk, seen from behind or the side, looking at a distant glowing city on the horizon. A pale sick sun in a dusty orange-brown sky, a faint green glow on the horizon. Leave the upper third empty and calm for the game title. Cinematic, lonely, hopeful in a sad way.
```

### Good ending (COULD) → `ending_rescue.png`
```
Follow the STYLE RULES from my first message, but this is a FULL scene (no magenta background). A wide landscape picture at dawn: the survivor and a small scruffy dog stand on top of the bunker hatch waving at a convoy of old trucks with headlights, driving toward them across the wasteland. The sky breaks into warm yellow and orange. Hopeful and emotional.
```

### Neutral ending (COULD) → `ending_alone.png`
```
Follow the STYLE RULES from my first message, but this is a FULL scene (no magenta background). A wide landscape picture at dawn: the survivor sits alone on the bunker hatch looking at an empty road toward the horizon. A small radio with a dead antenna beside them. Quiet, lonely, but still alive.
```

### Game over (COULD) → `game_over.png`
```
Follow the STYLE RULES from my first message, but this is a FULL scene (no magenta background). A wide landscape picture: a dark empty bunker room with a single cot, the lamp out, a faint green glow from the open hatch above. No character visible, a blanket dropped on the floor. Sad and quiet, not gory.
```

---

## Handoff checklist
- [ ] `survivor_concept.png` approved and **sent to Artist B**
- [ ] Survivor idle, walk, jump, collapse, wake-up ready for the coders
- [ ] Rat and raider ready
- [ ] Everything saved in `art/characters/` with exact file names
