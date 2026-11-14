# CODER PROMPTS (OLD reference version)

> **Don't use this file.** Each coder's complete, ordered prompts are now in `CODER_1_START.md` and `CODER_2_START.md`. This file is kept only as a reference.

# CODER PROMPTS (for the two people using Claude)

Paste these into Claude (Claude Code, opened in the shared project folder). Each coder uses their own Claude session.

- **Coder 1 = the LEAD, the more experienced person.** Does more work: the whole outside game (player, tile world, camera, pickups, radiation, enemies, digging), PLUS creating the project and GitHub repo, the Mac/Windows/web exports, polish (lighting, screen shake, particles), wiring in sounds, and the final bug-fix pass. Also reviews Coder 2's changes to `game_state.gd`.
- **Coder 2 = Inside + data, the lighter load** (GameState, menus, bunker rooms and building, night events, scars, endings, finding sounds, the art helper script). Simple scenes made of labels and buttons, good for someone newer to Godot.

**Who should be Coder 1?** The person who has coded most, or is most comfortable with git, the terminal and debugging. The outside game is the hardest part: physics, camera, tiles, enemies. If you're all beginners, pick whoever is least scared of red error messages.

Both start with the **SHARED PREAMBLE**, then their own **MASTER PROMPT**, then paste the **phase prompts one at a time** as each phase works.

---

## Step 0 — Before anyone pastes anything (humans do this, 20 minutes)

1. Everyone installs **Godot 4.3 or newer, the standard version (NOT the ".NET" one)** from godotengine.org.
2. **Coder 1 (the lead)** creates the project: Godot → New Project. Choose the **Compatibility** renderer (needed for web export). Name it `bunker7`, save it inside the game jam folder.
3. Coder 1 puts it on GitHub (private repo) and invites the other three. Everyone else clones it and opens it in Godot.
4. Add the Godot settings for pixel art. Project Settings:
   - Rendering → Textures → Default Texture Filter = **Nearest**
   - Display → Window → Viewport Width **480**, Height **270**; Stretch Mode = **canvas_items**, Scale Mode = **integer**
5. Make the folders: `art/characters`, `art/world`, `scenes`, `actors`, `autoload`, `data`, `audio`.
6. Add a `.gitignore` for Godot (ask Claude: "create a standard Godot .gitignore").

Claude can write scripts and even scene files, but **it can't see the Godot editor**. So: ask it for click-by-click steps, do them in Godot, run the game, and **paste any red error text back to Claude**.

---

## SHARED PREAMBLE (paste first, both coders)

```
We are four people at a hackathon building a 2D pixel-art survival game called "Bunker 7" in Godot 4 (Compatibility renderer, GDScript only, no C#). The theme is "Bounce Back". It runs on Mac, Windows and as a web build. Read GAME_PLAN.md in this folder first: it has the game design, loop, difficulty table, rooms and materials. Treat it as the spec.

About me and how to help:
- I am NEW to Godot and game development. Explain things in plain language and keep answers short.
- When something needs doing in the Godot editor (making a scene, adding a node, setting a property), give me numbered click-by-click steps. Don't assume I know where things are.
- Write simple, readable GDScript with short comments. No fancy architecture. Prefer the simplest thing that works.
- Work ONE small step at a time. After each step, tell me exactly how to run it and what I should see. Wait for me to confirm before moving on.
- Until real art arrives, use placeholder art (colored rectangles, ColorRect nodes, or simple shapes) so the game is playable immediately.
- If I paste an error, find the cause and fix it. Don't guess, ask me for the missing information if you need it.
- This is a jam: cut scope rather than add features. Never add anything not in GAME_PLAN.md without asking.
- Only edit the files YOU own (listed in your master prompt). If you need something from the other coder's files, tell me what to ask them for.

Art file names are listed in ARTIST_A_CHARACTERS.md and ARTIST_B_WORLD.md. Art is saved in art/characters/ and art/world/. Sprites arrive as PNGs on a magenta (#FF00FF) background and need processing first, see the helper-script prompt in CODER_PROMPTS.md.

Reply with a 5-line summary of the game as you understand it, then wait for my next message.
```

---

## THE SHARED CONTRACT (both coders read this; it's how your code connects)

This is the only place the two halves touch. **Coder 2 owns `autoload/game_state.gd`. Coder 1 only calls it.** If either of you wants to change this list, tell the other first.

**What GameState keeps track of (Coder 2 builds, Coder 1 reads):**
- day (1 to 7), bounces left, health, water, food, wood, concrete, scrap, circuits
- which rooms are unlocked, which buildings are built, which scars the player has
- difficulty settings

**What Coder 1 needs from GameState (via simple functions):**
- radiation speed multiplier (from difficulty and scars)
- loot multiplier (from difficulty and scars)
- carry limit (starts at 12, goes up when the storage room is built)
- movement speed bonus (from scars)
- dig speed bonus (from scars)
- whether an air filter or reinforced door exists (for inside effects)
- the Last Stand Pack left from a previous death (what items, where), if any

**What Coder 1 tells GameState (calls these functions):**
- `bank_loot` when the player returns to the hatch alive: tells it how many of each item were carried home
- `player_died` when radiation or health hits 100%/0: tells it what the player was carrying and where he died

**Scene hand-offs:**
- Morning screen's "Go Outside" button loads `res://scenes/expedition.tscn` (Coder 2 builds the button, Coder 1 builds the scene)
- Expedition scene ends by calling `bank_loot` or `player_died` on GameState, which then changes the scene (to the bunker evening screen or to the scar-pick screen). Coder 1 does NOT change scenes himself.

**Test cheats (Coder 2 builds early, everyone benefits):** keyboard shortcuts to add 10 of every material, skip to the next day, set radiation to full, and add one bounce. Testing without cheats wastes hours.

---

## CODER 1 — OUTSIDE

### Master prompt (paste after the preamble)
```
I'm Coder 1. I own everything OUTSIDE: actors/player.tscn and its script, scenes/expedition.tscn, the tile world, the camera, parallax backgrounds, pickups and crates, radiation, enemies (rats first, then raiders and drones), digging, and the Last Stand Pack. I do NOT own autoload/game_state.gd, menus, or the bunker: Coder 2 does. Use the "SHARED CONTRACT" in CODER_PROMPTS.md to talk to GameState. If GameState doesn't exist yet, create a tiny stand-in file named autoload/game_state_stub.gd with fake values and tell me, so I can work now and swap it out later.

I am also the team lead and the more experienced coder. On top of the outside, I also handle: the GitHub repo, the Mac/Windows/web exports, polish (lighting, screen shake, particles), wiring in sound, reviewing Coder 2's changes to autoload/game_state.gd, and the final bug-fix pass. Keep explanations short but still tell me exact editor steps.

Work in phases and wait for my message before starting each one. Phase 1 first.
```

### Phase 1 — Walk and jump on a tile world (do this first, in the first 1-2 hours)
```
Phase 1. Build a minimal test: a character (colored rectangle for now) that walks left and right and jumps on a floor made of tiles using TileMapLayer, with a Camera2D that follows the player. Use a placeholder TileSet with 2 tile types (solid ground, dirt). Add collision only on ground tiles. Make the world about 6 screens wide, flat with a few small hills. Give me the click-by-click steps for the scenes and nodes and the script. Tell me how to run it and what I should see. Also add a simple pause/ESC-to-quit so I can test easily.
```

### Phase 2 — Radiation, the hatch and pickups
```
Phase 2. Add: (1) a hatch placed at the far left of the world, (2) a radiation bar on screen that fills over time while the player is outside (read the speed multiplier from GameState, fake it with a stand-in if needed), (3) crates the player can open by walking up and pressing E, each giving a random amount of wood, concrete or scrap (read the loot multiplier), (4) a carry limit shown on screen (like 7/12), the player can't pick up more than the limit, (5) walking back to the hatch and pressing E banks the loot by calling GameState.bank_loot with what was carried. Placeholder art only. Tell me how to run it and what to expect.
```

### Phase 3 — Dying and the Last Stand Pack (the theme, do not skip)
```
Phase 3. Add dying: when radiation reaches 100% the player collapses (placeholder for now, play a "collapse" animation slot later), then GameState.player_died is called with what the player was carrying and the death position. Then on the NEXT expedition, if GameState says a Last Stand Pack exists, spawn it at that spot in the world as a glowing backpack the player can pick up by pressing E, and remove it once picked up or after that expedition. Test by making radiation fill quickly (a debug key), dying, and starting a new expedition.
```

### Phase 4 — Real art and parallax
```
Phase 4. The art files are now in art/characters/ and art/world/. First tell me the exact steps to import them correctly for pixel art (Nearest filter, no mipmaps). Then replace the placeholder player with the real survivor: an AnimatedSprite2D using survivor_idle, survivor_walk, survivor_jump and survivor_collapse sheets cut into frames. Replace the placeholder tiles with the real tileset (tiles_outside.png). Add parallax layers using bg_sky, bg_far, and bg_near_suburb, scrolling at different speeds behind the player. If a file hasn't arrived yet, tell me which and leave the placeholder in place.
```

### Phase 5 — Enemies
```
Phase 5. Add the rat enemy: it patrols left and right on the ground and chases the player when close. If it touches the player, it drains health a little and the player is knocked back briefly (then immune for a second). The player cannot attack, he can only run or jump over it. Use rat_run.png for animation if it exists. Then add the raider the same way but slower and with more damage. Keep numbers easy to change at the top of each script.
```

### Phase 6 — Digging and zones (only if the loop already works end to end)
```
Phase 6. Add digging: the player holds a mouse button on a dirt tile within one tile of him, it takes about 1 second (apply the dig speed bonus from GameState), then the tile is removed. Some dirt tiles hide a crate or a scrap pickup. Then divide the world into three zones going right: suburb (low radiation, wood), supermarket (medium, scrap and food), depot (high, circuits, medkits). Make radiation fill faster in further zones and use bg_near_market / bg_near_depot art when it's available.
```

### Phase 1b (LEAD) — Prove the exports work (same day, don't skip)
Use the "Phase 1b — Prove the exports work" prompt in the Coder 2 section below. It's the lead's job. Redo it at the midpoint and in the last hour.

### Phase 7 (LEAD) — Polish that makes it look professional
```
Phase 7. Add polish, one thing at a time, each easy to turn off: (1) a dark overlay outside with a soft light around the player and a warm glow around lamps in the bunker, using Godot's 2D lights, (2) a small screen shake when the player is hurt and a stronger one on death, (3) a fade to black and back for scene changes, including the "wake up" fade when bouncing back, (4) a few green particles floating in the air near radiation puddles and in far zones, (5) a subtle bounce (squash and stretch) when the player lands. Keep the performance light so it runs on a web build.
```

### Phase 8 (LEAD) — Sound
```
Phase 8. Sound files are now in audio/ (Coder 2 gathers them). Add: footsteps, jump, pickup, crate open, hurt, collapse, wake-up chime, button click, a calm bunker music loop and a tense outside music loop. Make one small AudioManager autoload with simple "play this sound" calls, and a mute key. Tell me how to import the files and which ones are missing.
```

### Phase 9 (LEAD) — Final integration and bug-fix pass
```
Phase 9. Help me do a full playthrough bug-fix pass: tell me a checklist of the 15 most likely problems in this game (scene changes losing data, unlocking a room twice, carry limit bugs, dying twice in a row, bouncing back with 0 bounces, the Last Stand Pack not spawning, day 7 ending conditions, the web build's sound, window size on different screens), help me test each one, fix any I find, and then do a clean export for Mac, Windows and web.
```

---

## CODER 2 — INSIDE AND DATA

### Master prompt (paste after the preamble)
```
I'm Coder 2. I own autoload/game_state.gd, scenes/main_menu.tscn, scenes/morning.tscn, scenes/bunker.tscn (the evening screen with the rooms), scenes/night_event.tscn, scenes/scar_pick.tscn, scenes/ending.tscn, scenes/game_over.tscn, and data/events.json. I do NOT own the expedition scene or the player: Coder 1 does. Use the "SHARED CONTRACT" in CODER_PROMPTS.md: GameState is the one script both halves rely on, so keep its function names as listed there and tell me before changing any.

Work in phases and wait for my message before starting each one. Phase 1 first.
```

### Phase 1 — Project skeleton, GameState, main menu, morning screen
```
Phase 1. Make GameState an autoload singleton (tell me how to register it in Project Settings → Autoload). It stores the day, bounces, health, water, food, wood, concrete, scrap, circuits, unlocked rooms, built buildings and scars. Use the Easy / Normal / Hard numbers from GAME_PLAN.md section 4. Include simple functions listed in the SHARED CONTRACT in CODER_PROMPTS.md (radiation multiplier, loot multiplier, carry limit, bank_loot, player_died and so on), with placeholder bodies where needed. Build a main menu with three difficulty buttons that starts a game, and a morning screen that shows the day, bounces, and the materials, with a "Go Outside" button that loads res://scenes/expedition.tscn (if it doesn't exist yet, make an empty placeholder scene so the button works). Add the TEST CHEATS from the contract (press keys to add materials, skip a day, add a bounce). Use plain Label and Button nodes, no art.
```

### Phase 1b — Prove the exports work (same day, don't skip) — THE LEAD (Coder 1) PASTES THIS ONE, NOT CODER 2
```
Phase 1b. Walk me through exporting the current project for: macOS, Windows, and Web. Explain installing export templates in Godot and the exact export preset settings. For Web, tell me how to run it locally to test (a simple local server command) and what to check (sound, window size). Tell me what breaks if the web build doesn't load.
```

### Phase 2 — Evening in the bunker: rooms and building
```
Phase 2. Build scenes/bunker.tscn: a side-view cutaway with the five rooms from GAME_PLAN.md side by side. Use colored rectangles. Only the bedroom is open at the start. Locked rooms look like dark rectangles with a "Locked" label and an "Unlock" button that shows the cost (wood, concrete, scrap) and is disabled if the player can't afford it. After unlocking a room, show a build menu listing the buildings that can go in it with their costs. Use the exact costs in GAME_PLAN.md section 3.4. Built buildings appear as colored rectangles in the room. At the bottom: a "Sleep" button that ends the evening. Everything reads from and writes to GameState.
```

### Phase 3 — Night and the next morning
```
Phase 3. Implement what happens when the player presses Sleep: GameState applies the night: the water purifier adds water, the garden adds food, the player eats and drinks (use the difficulty numbers, if they're short, lose health), the air filter resets radiation (otherwise half), then the day goes up. If it's past day 7, go to the ending scene. Otherwise roll for a night event using the difficulty chance and go to scenes/night_event.tscn, then to the morning. Show a short summary screen of what changed overnight.
```

### Phase 4 — Night events (data-driven)
```
Phase 4. Create data/events.json with the six events in GAME_PLAN.md (raiders knock, radiation storm, pipe burst, stranger's radio message, rats in the pantry, quiet night), each with a title, a description, and two options with their effects (add or remove materials, food, water, health, skip tomorrow's expedition, multiply radiation, repair cost for a damaged room). Build scenes/night_event.tscn: a card showing the title, description and two buttons, then it applies the chosen effect to GameState. Make adding a new event as simple as adding an entry to the JSON file, and explain how.
```

### Phase 5 — Bounce back: scars, endings, game over
```
Phase 5. Build the bounce-back flow: when GameState.player_died is called, lose one bounce and the rest of that day, then show scenes/scar_pick.tscn with 3 random scars from the five in GAME_PLAN.md (Thick Skin, Scavenger's Eye, Light Feet, Iron Gut, Steady Hands) that the player doesn't already have. After picking, the game goes to the night processing for that day. If bounces reach 0 go to game_over. Also build the ending scene (rescue ending if the radio is built on day 7, neutral ending otherwise) and make sure Game Over and Ending screens can return to the main menu. Test with the cheats.
```

### Phase 6 — Polish, balance, art in
```
Phase 6. Art files are now in art/world/. Replace the colored rectangles in the bunker scene with the real room pictures (room_bedroom, room_utility, room_garden, room_storage, room_radio, room_locked), the buildings from buildings_sheet.png, and the icons from icons_resources.png and icons_status.png (tell me how to import for pixel art). Replace the plain labels and buttons with the ui_panels art, and use the icons next to the numbers. Then suggest 5 specific balance changes after I tell you what my playtest felt like. If a file hasn't arrived yet, leave the placeholder.
```

### Phase 7 — Sounds (Coder 2 finds them, the lead wires them in)
Not a Claude prompt. Make sound effects in the browser at https://sfxr.me (footsteps, jump, pickup, crate open, hurt, collapse, button click, wake-up chime) and download them as .wav files. For music, look for free CC0 loops on itch.io or opengameart.org (check the license). Save everything in `audio/` and tell the lead, who pastes Phase 8.

---

## EXTRA — Helper script for art (whoever has free time; Coder 2 first)

Paste into Claude (it needs Python: Mac has `python3`; on Windows install Python first).

```
Create a small Python script (and tell me how to install what it needs, I'm a beginner) that processes the art from ChatGPT. Given a folder of PNGs, it should: (1) turn the magenta background (#FF00FF, with some tolerance for near-magenta and edge fringes) into transparent pixels and remove magenta halos on the edges, (2) optionally crop each image to the non-transparent area, (3) for a sprite sheet, split it into N equal frames and save each frame as its own PNG with the same height and a consistent bottom baseline, (4) optionally resize with NEAREST-neighbor to an exact target size (for example 16x32), never smoothing. Give it simple command-line options and show me example commands for: a single character sheet, and a folder of tile sheets. Keep the original files untouched, save results into a new folder.
```

---

## Daily routine for the whole team
1. **Pull** from GitHub before you start; **commit and push** every time something works.
2. Never edit a file owned by someone else. Message them instead.
3. Every 2 hours: both coders run the game end to end once (menu → outside → back → bunker → sleep) to make sure nothing is broken.
4. Export the web build at the midpoint and again an hour before the deadline.
