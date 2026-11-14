# CODER 2 — THE INSIDE (the lighter load)

Everything you need is in this one file: what to download, and **every prompt to paste into Claude Code, in order.** Paste one prompt, test it in Godot, then paste the next.

You build the **inside**: menus, the bunker rooms, building, night events, bouncing back and the endings. These are mostly simple screens of text and buttons, a good place to learn Godot. Coder 1 (the lead) creates the project first, so do Part A now and wait for the GitHub link.

---

# PART A — Setup (you, 15 minutes)

### A1. Download 2 things (do this right away)
1. **Godot** (the game engine): https://godotengine.org/download → **Godot Engine** for your Mac or Windows. Get the **standard** one, NOT ".NET". Needs version **4.3 or newer**. It's one file you open, no install.
2. **Claude desktop app**: https://claude.ai/download → install → sign in → open the **Code** tab.

### A2. Get the project (after Coder 1 sends the GitHub link)
In the Claude **Code** tab, open any folder and paste **PROMPT 0**:

**PROMPT 0 — Clone the project**
```
Clone this GitHub repo to my computer and tell me the folder it's in: <PASTE THE LINK FROM CODER 1 HERE>. I'm a beginner, give me exact steps and ask me to do the parts that need my GitHub login.
```

Then:
1. In Claude Code, **open the cloned `game jam` folder.**
2. Open Godot → **Import** → pick the `project.godot` file in that folder → open it.

---

# PART B — Your prompts, in order

**How it works:** paste a prompt → Claude does it → follow its steps in Godot → run the game → if there's a red error in Godot, **copy it and paste it to Claude** (Claude can't see Godot) → when it works, paste the next prompt.

When something works, tell Claude: `Commit and push my changes.` Every morning: `Pull the latest changes.`

---

### PROMPT 1 — Start (paste this first)
```
We are four people at a hackathon building a 2D pixel-art survival game called "Bunker 7" in Godot 4 (Compatibility renderer, GDScript only, no C#). The theme is "Bounce Back". It must run on Mac, Windows and as a web build. Read GAME_PLAN.md in this folder first: it has the game design, loop, difficulty table, rooms and materials. Treat it as the spec.

I am Coder 2. I'm NEW to Godot and game development. How to help me:
- Explain things in plain language and keep answers short. When something needs doing in the Godot editor (making a scene, adding a node, setting a property), give me numbered click-by-click steps. Don't assume I know where anything is.
- Write simple, readable GDScript with short comments. No fancy architecture.
- Work ONE small step at a time. After each step, tell me exactly how to run it and what I should see. Wait for me before moving on.
- Until real art arrives, use placeholder art (Label, Button, ColorRect nodes) so the game is playable immediately.
- If I paste an error, find the cause and fix it. If you need more information, ask me.
- This is a hackathon: cut scope instead of adding features. Never add anything not in GAME_PLAN.md without asking.
- Only edit the files I own. If I need something from Coder 1's files, tell me what to ask them.

WHAT I OWN: autoload/game_state.gd, scenes/main_menu.tscn, scenes/morning.tscn, scenes/bunker.tscn (the evening screen with the rooms), scenes/night_event.tscn, scenes/scar_pick.tscn, scenes/ending.tscn, scenes/game_over.tscn, and data/events.json. I do NOT own the expedition scene or the player: Coder 1 does (they are the team lead).

THE SHARED CONTRACT with Coder 1 (the only place our code connects; don't rename anything in it without telling them, they review changes to game_state.gd):
- I own autoload/game_state.gd (an autoload called GameState). It keeps: day (1 to 7), bounces left, health, water, food, wood, concrete, scrap, circuits, unlocked rooms, built buildings, scars, and the difficulty settings (use the Easy / Normal / Hard table in GAME_PLAN.md).
- Coder 1 READS these from GameState through simple functions, so I must provide them: radiation speed multiplier (from difficulty and scars), loot multiplier (difficulty and scars), carry limit (starts at 12, higher once the storage room is built), movement speed bonus (scars), dig speed bonus (scars), whether an air filter or reinforced door exists, and the Last Stand Pack left from a previous death (what items and where), if any.
- Coder 1 CALLS these on GameState: bank_loot (when the player returns alive to the hatch, telling it how many of each item were carried home) and player_died (telling it what the player was carrying and where he died).
- Scene hand-offs: my morning screen "Go Outside" button loads res://scenes/expedition.tscn (I make the button, Coder 1 makes the scene; if it doesn't exist yet, make an empty placeholder scene so the button works). The expedition scene ends ONLY by calling bank_loot or player_died on GameState, and GameState then changes the scene (to the bunker evening screen, or to the scar-pick screen). Coder 1 never changes scenes himself.
- TEST CHEATS I build early, because testing without them wastes hours: keyboard shortcuts to add 10 of every material, skip to the next day, set radiation to full, and add one bounce.
- Folders: autoload, scenes, actors, data, audio, art/characters, art/world.

Reply with a 5-line summary of the game as you understand it, then wait for my next message.
```

---

### PROMPT 2 — GameState, main menu, morning screen
```
Make GameState an autoload singleton (tell me how to register it in Project Settings → Autoload). It stores the day, bounces, health, water, food, wood, concrete, scrap, circuits, unlocked rooms, built buildings and scars. Use the Easy / Normal / Hard numbers from GAME_PLAN.md section 4. Include the functions in the SHARED CONTRACT (radiation multiplier, loot multiplier, carry limit, bank_loot, player_died, and so on), with placeholder bodies where needed. Build a main menu with three difficulty buttons that starts a game, and a morning screen that shows the day, bounces, and the materials, with a "Go Outside" button that loads res://scenes/expedition.tscn (if it doesn't exist yet, make an empty placeholder scene so the button works). Add the TEST CHEATS (press keys to add 10 of each material, skip a day, set radiation full, add a bounce). Use plain Label and Button nodes, no art. When it works, tell me what to tell Coder 1.
```

---

### PROMPT 3 — The bunker: rooms and building
```
Build scenes/bunker.tscn: a side-view cutaway with the five rooms from GAME_PLAN.md side by side (bedroom, utility, garden, storage, radio). Use colored rectangles. Only the bedroom is open at the start. Locked rooms look like dark rectangles with a "Locked" label and an "Unlock" button that shows the cost (wood, concrete, scrap) and is disabled if the player can't afford it. After a room is unlocked, show a build menu listing the buildings that can go in it with their costs. Use the exact costs in GAME_PLAN.md section 3.4. Built buildings appear as colored rectangles in the room. At the bottom: a "Sleep" button that ends the evening. Everything reads from and writes to GameState. Unlocking a room twice or building something twice must be impossible.
```

---

### PROMPT 4 — Night and the next morning
```
Implement what happens when the player presses Sleep: GameState applies the night. The water purifier adds water, the garden adds food, the player eats and drinks (use the difficulty numbers; if he's short, he loses health), the air filter resets radiation (otherwise only half), then the day goes up by one. If it's past day 7, go to the ending scene. Otherwise roll for a night event using the difficulty chance and go to scenes/night_event.tscn, then to the morning screen. Show a short summary screen of what changed overnight (for example "+2 water, -1 food, -1 health").
```

---

### PROMPT 5 — Night events (from a data file)
```
Create data/events.json with the six events in GAME_PLAN.md (raiders knock, radiation storm, pipe burst, stranger's radio message, rats in the pantry, quiet night). Each has a title, a description, and two options with their effects (add or remove materials, food, water or health; skip tomorrow's expedition; multiply tomorrow's radiation; pay a repair cost to a damaged room). Build scenes/night_event.tscn: a card showing the title, the description and two buttons, then it applies the chosen effect to GameState. Make adding a new event as simple as adding an entry to the JSON file, and explain exactly how.
```

---

### PROMPT 6 — Bounce back: scars, endings, game over (THIS IS THE THEME)
```
Build the bounce-back flow. When GameState.player_died is called: lose one bounce and the rest of that day, then show scenes/scar_pick.tscn with 3 random scars, out of the five in GAME_PLAN.md (Thick Skin, Scavenger's Eye, Light Feet, Iron Gut, Steady Hands) that the player doesn't already have. After picking one, the game goes to the night processing for that day (the player "wakes up on his cot" the next morning). If bounces reach 0, go to game_over. Also build the ending scene (rescue ending if the radio is built on day 7, neutral ending otherwise), and make sure the Game Over and Ending screens return to the main menu. Test everything with the cheat keys.
```

---

### PROMPT 7 — Art helper script (paste when the artists' PNGs start arriving)
(The artists' images come on a pink/magenta background. This makes them transparent for the whole team. Needs Python: Mac has `python3`; on Windows install Python first.)
```
Create a small Python script, and tell me how to install what it needs (I'm a beginner), that processes the art from ChatGPT. The input folders are art/characters and art/world. For every PNG it should: (1) turn the magenta background (#FF00FF, with some tolerance for near-magenta and edge fringes) into transparent pixels and remove magenta halos on the edges, (2) trim away empty transparent space around the picture (but not for backgrounds, tiles or full scenes, so skip files starting with bg_, tiles_, room_, title_, ending_, game_over and bunker_), (3) for sprite-sheet files (names containing _idle, _walk, _jump, _collapse, _wakeup, _mine, _hurt, _run, _attack, _hover), split them into separate frames by detecting the gaps between the figures, and save each frame as its own PNG with the same canvas size and the same bottom baseline, (4) never smooth or blur anything. Save the results in new folders art/characters_clean/ and art/world_clean/ and never change the original files. Give me simple command-line instructions and show me the commands to run for everything at once.
```

---

### PROMPT 8 — Real art in the bunker (when the room and building art arrives)
```
Art files are now in art/world_clean/. First tell me the exact steps to import them correctly for pixel art (Nearest filter, no mipmaps). Then replace the colored rectangles in the bunker scene with the real room pictures (room_bedroom, room_utility, room_garden, room_storage, room_radio, room_locked), the buildings from buildings_sheet, and the icons from icons_resources and icons_status. Replace the plain labels and buttons with the ui_panels art and put icons next to the numbers. Use scar icons in the scar-pick screen and event pictures in the event card if they exist. If a file hasn't arrived yet, tell me which one and leave the placeholder. Then, after I playtest, I'll tell you what felt off and you suggest 5 specific balance changes.
```

---

# Your side jobs (no prompt needed)
- **Sounds:** make effects at https://sfxr.me (footsteps, jump, pickup, crate open, hurt, collapse, button click, wake-up chime) and download them as .wav. Find a calm bunker loop and a tense outside loop on itch.io or opengameart.org (check the license). Save everything in `audio/` and tell Coder 1.
- **Playtest** your part with the cheat keys. Write down what felt boring or confusing, and give it to Prompt 8.
- **Keep the artists unblocked:** if their pictures have pink edges after the script, tell the artist and ask Claude to improve the edge cleanup.

# Rules
- Only edit your own files (menus, bunker, night events, game_state). Coder 1 owns the outside.
- Don't rename functions in game_state without telling Coder 1, who reviews it.
- Export tests are Coder 1's job, not yours.
