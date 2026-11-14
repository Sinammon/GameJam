# CODER 1 — THE LEAD (the more experienced person)

Everything you need is in this one file: what to download, and **every prompt to paste into Claude Code, in order.** Paste one prompt, test it in Godot, then paste the next.

You do the most work: the whole **outside** game, plus the GitHub repo, exports, polish, sound and the final bug fixes. Coder 2 is waiting on Part A, so do it fast.

---

# PART A — Setup (you, 15 minutes)

### A1. Download 2 things
1. **Godot** (the game engine): https://godotengine.org/download → **Godot Engine** for your Mac or Windows. Get the **standard** one, NOT ".NET". Needs version **4.3 or newer**. It's one file you open, no install.
2. **Claude desktop app**: https://claude.ai/download → install → sign in → open the **Code** tab.

### A2. Create the Godot project
1. Open Godot → **New Project**.
2. Name: `bunker7`. Folder: the `game jam` folder. **Renderer: Compatibility** (needed for the web build). Click **Create**.
3. Open the settings: in the **menu bar at the very top of your screen** (Mac: next to the Apple menu, it says Godot / Scene / Project / Debug / Editor / Help; Windows: top-left of the Godot window) click **Project → Project Settings…**. A window opens. Use the **search box at the top of that window** to find each setting by typing its name:
   - type `texture filter` → **Default Texture Filter = Nearest** (found under Rendering → Textures → Canvas Textures; keeps pixel art sharp)
   - type `viewport width` → **Viewport Width = 480**, and **Viewport Height = 270** (Display → Window → Size)
   - type `stretch` → **Mode = canvas_items**, **Scale Mode = integer** (Display → Window → Stretch)
   - If a setting doesn't show up, switch on **Advanced Settings** (toggle at the top right of the Project Settings window).
   - Close the window (settings save automatically).
4. Close Godot's project window for now.

### A3. Put it on GitHub for the team
Open the `game jam` folder in the Claude **Code** tab and paste **PROMPT 0**:

**PROMPT 0 — GitHub**
```
Set this folder up as a git repository for a Godot project. Create the folders art/characters, art/world, scenes, actors, autoload, data and audio (with a small placeholder file in each so git keeps them). Add a standard Godot .gitignore, make a first commit, and walk me through putting it on GitHub as a private repo so my 3 teammates can clone it. Ask me to do the parts that need my GitHub login.
```

When it's on GitHub, **send the link to Coder 2 and both artists.**

---

# PART B — Your prompts, in order

**How it works:** paste a prompt → Claude does it → follow its steps in Godot → run the game → if there's a red error in Godot, **copy it and paste it to Claude** (Claude can't see Godot) → when it works, paste the next prompt.

When something works, tell Claude: `Commit and push my changes.` Every morning: `Pull the latest changes.`

---

### PROMPT 1 — Start (paste this first)
```
We are four people at a hackathon building a 2D pixel-art survival game called "Bunker 7" in Godot 4 (Compatibility renderer, GDScript only, no C#). The theme is "Bounce Back". It must run on Mac, Windows and as a web build. Read GAME_PLAN.md in this folder first: it has the game design, loop, difficulty table, rooms and materials. Treat it as the spec.

I am Coder 1, the team lead and the more experienced coder. I'm fairly comfortable with code but new to Godot. How to help me:
- Keep explanations short. When something needs doing in the Godot editor (making a scene, adding a node, setting a property), give me numbered click-by-click steps.
- Write simple, readable GDScript with short comments. No fancy architecture.
- Work ONE small step at a time. After each step, tell me exactly how to run it and what I should see. Wait for me before moving on.
- Until real art arrives, use placeholder art (colored rectangles, ColorRect nodes) so the game is playable immediately.
- If I paste an error, find the cause and fix it. If you need more information, ask me.
- This is a hackathon: cut scope instead of adding features. Never add anything not in GAME_PLAN.md without asking.
- Only edit the files I own. If I need something from Coder 2's files, tell me what to ask them.

WHAT I OWN: everything OUTSIDE: actors/player.tscn and its script, scenes/expedition.tscn, the tile world, camera, parallax backgrounds, pickups and crates, radiation, enemies (rats first, then raiders and drones), digging, and the Last Stand Pack. As lead I also handle: the GitHub repo, the Mac/Windows/web exports, polish (lighting, screen shake, particles), wiring in sound, reviewing Coder 2's changes to autoload/game_state.gd, and the final bug-fix pass. I do NOT own autoload/game_state.gd, the menus or the bunker: Coder 2 does.

THE SHARED CONTRACT with Coder 2 (the only place our code connects; don't rename anything in it without telling them):
- Coder 2 owns autoload/game_state.gd (an autoload called GameState). It keeps: day (1 to 7), bounces left, health, water, food, wood, concrete, scrap, circuits, unlocked rooms, built buildings, scars, and the difficulty settings.
- I READ these from GameState through simple functions: radiation speed multiplier, loot multiplier, carry limit (starts at 12, higher once the storage room is built), movement speed bonus, dig speed bonus, whether an air filter or reinforced door exists, and the Last Stand Pack left from a previous death (what items and where).
- I CALL these on GameState: bank_loot (when the player returns alive to the hatch, telling it how many of each item were carried home) and player_died (telling it what the player was carrying and where he died).
- Scene hand-offs: Coder 2's morning screen "Go Outside" button loads res://scenes/expedition.tscn (they make the button, I make the scene). My expedition scene ends ONLY by calling bank_loot or player_died. GameState then changes the scene. I never change scenes myself.
- If GameState doesn't exist yet, create a tiny stand-in file named autoload/game_state_stub.gd with fake values and tell me, so I can work now and swap it out later.
- Coder 2 will add test cheat keys (add 10 of each material, skip a day, fill radiation, add a bounce).
- Folders: autoload, scenes, actors, data, audio, art/characters, art/world.

Art arrives later as PNGs; characters and objects start on a magenta (#FF00FF) background and Coder 2 turns them into clean transparent versions in art/characters_clean/ and art/world_clean/. File names are listed in ARTIST_A_CHARACTERS.md and ARTIST_B_WORLD.md.

Reply with a 5-line summary of the game as you understand it, then wait for my next message.
```

---

### PROMPT 2 — Walk and jump on a tile world (first 1-2 hours)
```
Build a minimal test: a character (colored rectangle for now) that walks left and right and jumps on a floor made of tiles using TileMapLayer, with a Camera2D that follows the player. Use a placeholder TileSet with 2 tile types (solid ground, dirt). Add collision only on ground tiles. Make the world about 6 screens wide, flat with a few small hills. Give me the click-by-click steps for the scenes, nodes and the script. Tell me how to run it and what I should see. Also add ESC-to-quit so I can test easily.
```

---

### PROMPT 3 — Prove the exports work (same day, don't skip)
```
Walk me through exporting the current project for macOS, Windows and Web. Explain how to install the export templates in Godot and the exact export preset settings. For Web, use the single-threaded option (turn off "use threads") so it works on itch.io without special headers, and tell me how to test it locally (a simple local server command) and what to check (sound, window size, loading). Tell me what usually breaks if the web build doesn't load.
```

---

### PROMPT 4 — Radiation, the hatch and pickups
```
Add: (1) a hatch placed at the far left of the world, (2) a radiation bar on screen that fills over time while the player is outside (read the speed multiplier from GameState, fake it with the stand-in if needed), (3) crates the player can open by walking up and pressing E, each giving a random amount of wood, concrete or scrap (read the loot multiplier), (4) a carry limit shown on screen (like 7/12): the player can't pick up more than the limit, (5) walking back to the hatch and pressing E banks the loot by calling GameState.bank_loot with what was carried. Placeholder art only. Tell me how to run it and what to expect.
```

---

### PROMPT 5 — Dying and the Last Stand Pack (THIS IS THE THEME, don't skip)
```
Add dying: when radiation reaches 100% the player collapses (leave a slot for a "collapse" animation later), then GameState.player_died is called with what the player was carrying and the death position. Then on the NEXT expedition, if GameState says a Last Stand Pack exists, spawn it at that spot in the world as a glowing backpack the player can pick up by pressing E, and remove it once picked up or after that expedition ends. Add a debug key that makes radiation fill quickly so I can test dying, then starting a new expedition.
```

---

### PROMPT 6 — Real art and parallax (when the artists' files arrive)
```
The art files are now in art/characters_clean/ and art/world_clean/ (transparent PNGs made by Coder 2's script; if a file is still on a magenta background, tell me and we'll ask Coder 2). First tell me the exact steps to import them correctly for pixel art (Nearest filter, no mipmaps). Then replace the placeholder player with the real survivor: an AnimatedSprite2D using the survivor_idle, survivor_walk, survivor_jump and survivor_collapse sheets cut into frames. Replace the placeholder tiles with the real tileset (tiles_outside). Add parallax layers using bg_sky, bg_far and bg_near_suburb, scrolling at different speeds behind the player. If a file hasn't arrived yet, tell me which one and leave the placeholder in place.
```

---

### PROMPT 7 — Enemies
```
Add the rat enemy: it patrols left and right on the ground and chases the player when he gets close. If it touches the player, it drains health a little and the player is knocked back briefly (then immune for a second). The player cannot attack, he can only run or jump over it. Use rat_run for animation if it exists. Then add the raider the same way but slower and with more damage. Keep the numbers easy to change at the top of each script.
```

---

### PROMPT 8 — Digging and zones (only if the loop already works end to end)
```
Add digging: the player holds the mouse button on a dirt tile within one tile of him, it takes about 1 second (apply the dig speed bonus from GameState), then the tile is removed. Some dirt tiles hide a crate or a scrap pickup. Then divide the world into three zones going right: suburb (low radiation, wood), supermarket (medium, scrap and food), depot (high, circuits and medkits). Make radiation fill faster in the further zones and use bg_near_market and bg_near_depot art when available.
```

---

### PROMPT 9 — Polish that looks professional
```
Add polish, one thing at a time, each easy to turn off: (1) a dark overlay outside with a soft light around the player, and a warm glow around lamps in the bunker, using Godot's 2D lights, (2) a small screen shake when the player is hurt and a stronger one on death, (3) a fade to black and back for scene changes, including the "wake up" fade when bouncing back, (4) a few green particles floating in the air near radiation puddles and in far zones, (5) a subtle squash-and-stretch when the player lands. Keep it light so it runs on the web build.
```

---

### PROMPT 10 — Sound (after Coder 2 puts files in audio/)
```
Sound files are now in audio/. Add: footsteps, jump, pickup, crate open, hurt, collapse, wake-up chime, button click, a calm bunker music loop and a tense outside music loop. Make one small AudioManager autoload with simple "play this sound" calls, and a mute key (M). Tell me how to import the files and which ones are missing.
```

---

### PROMPT 11 — Final bug-fix pass and clean exports (last 2-3 hours)
```
Help me do a full playthrough bug-fix pass. Give me a checklist of the 15 most likely problems in this game (scene changes losing data, unlocking a room twice, carry limit bugs, dying twice in a row, bouncing back with 0 bounces left, the Last Stand Pack not spawning, day 7 ending conditions, web build sound, window size on different screens, and anything else you think likely). Help me test each one and fix any I find. Then do a clean export for Mac, Windows and Web and tell me how to upload the web build to itch.io.
```

---

# Your extra jobs (no prompt needed)
- **Review Coder 2's changes** to `autoload/game_state.gd` before they merge. It connects everything.
- **Every 2 hours:** run the whole game once (menu → outside → back → bunker → sleep) so nothing is secretly broken. Repeat the export test (PROMPT 3) at the midpoint and in the last hour.
- **Cut list if time runs out:** enemies → digging → zones → night events. Never cut dying and bouncing back.

# Rules
- Only edit your own files (player, expedition scene, enemies, tile world) plus polish and exports. Coder 2 owns menus, bunker and game_state.
- You never change scenes yourself when the player returns or dies: you call `bank_loot` or `player_died`.
- If game_state is missing a function you need, ask Coder 2. The stand-in covers you meanwhile.
