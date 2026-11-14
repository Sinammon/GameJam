# BUNKER 7 — "Bounce Back" (working title)

Theme: **Bounce Back**. Nuclear war, 2D side-view pixel art (Terraria look), survive 7 days in a bunker.

---

## 1. The pitch (read this out loud to the team)

The bombs fell. You are the last person in a small bunker. A radio crackles: *"Convoy arrives at dawn on Day 7. Keep the beacon alive."*

Each day you climb out of the hatch into the irradiated ruins, scavenge water, food and scrap, and race back before the radiation gets you. At night you eat, drink, build, and survive a random event. Survive 7 days and build the radio beacon to get rescued.

**Where "bounce back" comes in (this is the part judges will remember):**

1. **Death is not game over, it's a respawn.** Like Minecraft: you wake up on your cot the next morning. You lose the rest of the day, and your backpack drops at the place you died as a **Last Stand Pack** that you can go and fetch.
2. **Every death makes you stronger.** Each bounce gives you a **Scar**, a permanent perk of your choice (less radiation, faster, more loot). Failure is fuel.
3. **Lives are called "Bounces".** Easy 5, Normal 3, Hard 2. When you run out, it's over.
4. **The bunker bounces back too.** Night events (raid, collapse, storm) damage buildings, and you rebuild them stronger.

One-sentence version: *"A survival game where dying is part of the strategy."*

---

## 2. Tech stack (the decision)

**Use Godot 4 with GDScript.** Not Unity.

| | Godot 4 (GDScript) | Unity (C#) | Phaser (JavaScript) |
|---|---|---|---|
| Install | ~100 MB single file, no account | Hub + account + multi-GB editor | Needs Node + code editor |
| Made for 2D | Yes, real 2D engine | 3D engine with 2D mode | Yes, but code only, no editor |
| Tilemap (Terraria-style ground) | Built in (TileMapLayer) | Built in, more setup | Plugins |
| Learning curve for a beginner | Gentlest | Steeper | Easy if you know JS |
| Team merge conflicts | Text-based scenes, OK | Messier | Fine |
| Share the finished game | Export to web or Mac/Win | Same, bigger | Web only |

Why: most game jam sources point to Godot as the default pick for a beginner 2D jam game, and its share of jam entries has grown sharply. GDScript reads like Python. Nobody on the team needs to know anything beforehand.

Caveats:
- **Use GDScript, not C#.** One guide says Godot C# projects can't export to the web. I couldn't verify this, so check the current Godot export docs if you want a browser build.
- Use **Godot 4.3 or newer**. It replaced the old `TileMap` node with `TileMapLayer`. A lot of tutorials online still show the old node. Translate them, the ideas are the same.
- Do the web export test **early** (in the first few hours), not at the end.

Other tools:
- **Images:** ChatGPT image generation (prompts in `ASSET_PROMPTS.md`)
- **Cutting out backgrounds / fixing pixels:** [Piskel](https://www.piskelapp.com) (free, in browser), Aseprite (paid), or any background remover
- **Sound effects:** [jsfxr](https://sfxr.me) (generate retro sounds in the browser), freesound.org (check license)
- **Music:** free CC0 packs on itch.io / opengameart.org
- **Fallback art:** [Kenney.nl](https://kenney.nl/assets) has CC0 (free, no attribution) pixel packs. If an AI asset fails, drop in a Kenney one and move on.
- **Fonts:** Google Fonts "Pixelify Sans" or "Press Start 2P"
- **Code sharing:** GitHub, **one person owns each scene file** to avoid merge conflicts

**Check the jam rules about AI-generated assets.** Some jams ban them or require disclosure. Read it before spending hours on prompts.

---

## 3. The game loop

```
        ┌──────────────── 7 DAYS ────────────────┐
MORNING  →  EXPEDITION (surface)  →  EVENING (bunker)  →  NIGHT EVENT  →  next day
plan        scavenge, dodge,         eat/drink auto,       2-choice card,
            return to hatch          build, craft          maybe damage
```

### 3.1 Start screen
Pick difficulty (see table), then a short intro text with the radio message.

### 3.2 Morning
Show: Day X/7, water, food, scrap, Bounces left, and the building list. Button: **Go Outside**. (Just a HUD screen, 30 minutes of work.)

### 3.3 Expedition (the Terraria-like part, the main gameplay)
- Side-view platformer. Walk, jump, and **dig** (mine dirt blocks to find buried crates and pipes).
- **Radiation is the timer.** A bar fills while you're outside, faster in far zones and storms. At 100% you collapse and die. This replaces a countdown, and creates the tension: *"One more crate or head home?"*
- You must walk back to the **hatch** to bank your loot. Far loot means a longer walk back, so greed is punished.
- Zones to the right of the hatch, further means riskier and better:

| Zone | Distance | Radiation | Loot | Danger |
|---|---|---|---|---|
| Ruined suburb | near | low | scrap, some food | rats |
| Supermarket & gas station | mid | medium | food, water, fuel | rats, raiders |
| Military depot / radio tower | far | high | rare parts (circuit), medkits | raiders, drones |

- Enemies: irradiated rat, raider, drone (see prompts). You can run from all of them. Keep combat tiny: one melee swing, or none at all (enemies just drain health).

### 3.4 Evening (bunker, cross-section view)
- Bunker is a side-view cutaway with 2-3 rooms (Terraria base look). Each building you build appears as a sprite in a room.
- **Automatic consumption:** you eat 1 food and drink 1 water. If you're missing one, you lose health and get a "Weak" debuff next day.
- **The bunker grows.** You start with one room (the bedroom with the cot and the hatch ladder). The other four rooms are locked, shown as packed dirt. You pay **materials** to unlock a room, then pay to place buildings in it.
- **Three materials, found in different places outside:** wood (suburb: fences, broken houses), concrete (rubble, and digging), scrap (supermarket, depot). The rare **circuit** comes only from the far depot. You can carry about 12 items per trip, so you pick what to haul back.
- Rooms persist when you die. Night events can damage a room, and you pay a little to repair it.

| Room | Unlock cost | Lets you build |
|---|---|---|
| Bedroom | free (start) | Cot, Reinforced Door |
| Utility room | 6 wood + 6 concrete | Water Purifier, Air Filter |
| Garden room | 8 wood + 4 concrete | Hydroponic Garden |
| Storage room | 6 concrete + 4 scrap | +carry space (12 → 16 items) |
| Radio room | 8 concrete + 6 scrap + 1 circuit | Radio Beacon (required to win) |

| Building | Cost | Effect |
|---|---|---|
| Water Purifier | 6 scrap | +2 water every night |
| Hydroponic Garden | 5 wood + 3 scrap | +1 food every night |
| Air Filter | 5 scrap | radiation fully resets overnight (otherwise only half) |
| Reinforced Door | 4 wood + 2 scrap | raid events do no damage |
| **Radio Beacon** | 10 scrap | **required to win** |

Everything adds up to about 23 wood, 24 concrete and 36 scrap. In a week you can realistically haul back about 60-70 materials, so you **can't build everything** and must choose. These are starting values: playtest, then tune until it feels tight but fair. The code skeleton in section 5 predates the room system, so extend its `BUILDINGS` list and add a `rooms` unlock list.

### 3.5 Night event
Draw one event card (chance depends on difficulty). Player picks one of two options. Events are data, add a new one in a minute.

| Event | Option A | Option B |
|---|---|---|
| Raiders knock | Open door: lose 2 food, gain 1 medkit | Ignore: lose 3 scrap if no Reinforced Door |
| Radiation storm | Hide: skip tomorrow's expedition | Go out anyway: radiation ×2 tomorrow |
| Pipe burst | Repair: spend 3 scrap | Ignore: lose 2 water |
| Stranger's radio message | Follow it: tomorrow a bonus crate on the map | Ignore |
| Rats in the pantry | Fight: lose 1 health | Lose 2 food |
| Quiet night | Heal 2 health | Heal 2 health |

### 3.6 Dying (the theme)
1. Death on the surface: fade out, "You wake up on your cot." Day advances. A **Last Stand Pack** (everything you were carrying) stays at the death spot for the next expedition only.
2. Bounces −1. Choose a **Scar** (3 random options): *Thick Skin* (−20% radiation), *Scavenger's Eye* (+1 loot per crate), *Light Feet* (+10% speed), *Iron Gut* (need 1 less water per day), *Steady Hands* (dig 30% faster).
3. If Bounces hit 0: game over screen with "How far you got" (days, builds).

### 3.7 Win / endings
- Day 7 reached **with Radio Beacon built:** convoy arrives, good ending.
- Day 7 reached **without it:** you survive, but nobody comes. Neutral ending: "You're alive. Alone."
- Out of Bounces: game over.

---

## 4. Difficulty (all numbers are starting values, playtest and tweak)

| | Easy | Normal | Hard |
|---|---|---|---|
| Days | 7 | 7 | 7 |
| Bounces (lives) | 5 | 3 | 2 |
| Starting water / food | 8 / 8 | 5 / 5 | 3 / 3 |
| Water & food per night | 1 / 1 | 1 / 1 | 2 / 1 |
| Radiation speed | ×0.7 | ×1.0 | ×1.5 |
| Loot amount | ×1.3 | ×1.0 | ×0.75 |
| Night event chance | 20% | 35% | 55% |

---

## 5. Project structure in Godot

```
res://
  autoload/game_state.gd      <- the whole game's data, one script
  data/events.json            <- night events
  scenes/
    main_menu.tscn            <- difficulty buttons
    morning.tscn              <- HUD planning screen
    expedition.tscn           <- platformer level (TileMapLayer + Player + enemies + crates + hatch)
    bunker.tscn               <- cutaway rooms + build menu
    night_event.tscn          <- event card with 2 buttons
    game_over.tscn / ending.tscn
  actors/player.tscn, rat.tscn, raider.tscn, drone.tscn, crate.tscn
  art/  audio/  ui/
```

**GameState** (an Autoload, a script every scene can reach as `GameState`). This is the single most important script. Starter code:

```gdscript
extends Node

signal changed          # UI listens to this and redraws

enum Difficulty { EASY, NORMAL, HARD }
const SETTINGS = {
	Difficulty.EASY:   {"bounces": 5, "water": 8, "food": 8, "water_need": 1, "food_need": 1, "rad": 0.7,  "loot": 1.3,  "event": 0.20},
	Difficulty.NORMAL: {"bounces": 3, "water": 5, "food": 5, "water_need": 1, "food_need": 1, "rad": 1.0,  "loot": 1.0,  "event": 0.35},
	Difficulty.HARD:   {"bounces": 2, "water": 3, "food": 3, "water_need": 2, "food_need": 1, "rad": 1.5,  "loot": 0.75, "event": 0.55},
}
const BUILDINGS = {
	"purifier": {"name": "Water Purifier", "scrap": 10},
	"garden":   {"name": "Hydroponic Garden", "scrap": 12},
	"filter":   {"name": "Air Filter", "scrap": 8},
	"door":     {"name": "Reinforced Door", "scrap": 6},
	"radio":    {"name": "Radio Beacon", "scrap": 20, "needs_circuit": true},
}

var day := 1
var bounces := 3
var water := 5
var food := 5
var scrap := 0
var circuits := 0
var health := 10
var scars: Array[String] = []
var built: Dictionary = {}          # {"purifier": true}
var settings: Dictionary = {}

func start_game(d: Difficulty) -> void:
	settings = SETTINGS[d]
	day = 1
	bounces = settings.bounces
	water = settings.water
	food = settings.food
	scrap = 0; circuits = 0; health = 10
	scars.clear(); built.clear()
	changed.emit()
	get_tree().change_scene_to_file("res://scenes/morning.tscn")

func can_build(id: String) -> bool:
	var b = BUILDINGS[id]
	return not built.has(id) and scrap >= b.scrap and (not b.get("needs_circuit", false) or circuits > 0)

func build(id: String) -> void:
	if not can_build(id): return
	scrap -= BUILDINGS[id].scrap
	if BUILDINGS[id].get("needs_circuit", false): circuits -= 1
	built[id] = true
	changed.emit()

func end_day() -> void:                   # call when the evening is over
	if built.has("purifier"): water += 2
	if built.has("garden"): food += 1
	_consume(water, "water")
	day += 1
	if day > 7: finish_game()
	changed.emit()

func bounce() -> void:                    # call from the player's death
	bounces -= 1
	if bounces <= 0: get_tree().change_scene_to_file("res://scenes/game_over.tscn")
	else: get_tree().change_scene_to_file("res://scenes/scar_pick.tscn")

func finish_game() -> void:
	get_tree().change_scene_to_file("res://scenes/ending.tscn")   # check built.has("radio") there

func _consume(_have: int, _what: String) -> void:
	# TODO: subtract water_need / food_need; if short, health -= 2
	pass
```

(This is a skeleton to start from, it has not been run. `_consume` is left for you.)

Player movement: Godot's `CharacterBody2D` template (right-click a node, "Attach Script", template "Basic Movement") gives you walking and jumping in 5 minutes.
Digging: on click, find the tile under the cursor with `local_to_map()`, and call `erase_cell()` on the `TileMapLayer`.

---

## 6. Scope: what to build first

Keep the full loop running end-to-end first, ugly, and then make it pretty.

**MUST (playable game) — do these in this order**
1. Godot installed on every laptop, repo created, empty project pushed.
2. GameState + main menu with 3 difficulty buttons + morning screen.
3. Expedition scene: one flat level, walking + jumping, 3 crates, hatch, radiation bar.
4. Death → wake up → Scar pick → next day.
5. Bunker scene with the build menu, auto-eating at night.
6. Day 7 ending (win/neutral).
7. Placeholder art (colored squares) is fine until all this works.

**SHOULD**
8. Real art swapped in, parallax background.
9. Night events (JSON).
10. Sound effects, music.
11. Enemies (rats first).

**COULD (only if everything above is done)**
12. Digging with buried crates.
13. Zones 2 and 3.
14. Dog companion, more Scars, more events.
15. Screen shake, particles, nicer UI.

**Cut list if time runs out:** enemies → digging → zones → events. Never cut: dying and bouncing back, because it's the theme.

---

## 7. Team split (adjust to however many people you are)

Four people: two with Claude (code) and two with ChatGPT (art).

| Person | Tool | Owns | First task |
|---|---|---|---|
| Coder 1 (**lead, the most experienced**) | Claude | The whole outside: `expedition.tscn`, player, tile world, camera, parallax, pickups, radiation, enemies, digging. Plus: creates the GitHub repo, exports (Mac/Windows/web), polish (lighting, shake, particles), wiring sound, reviews `game_state.gd`, final bug-fix pass | Create the project and repo, then walk + jump on a tile floor with a following camera |
| Coder 2 (lighter load) | Claude | `game_state.gd`, menus, morning, bunker rooms and building, night events, scars, endings, finds sound effects, runs the art helper script | GameState + difficulty + morning screen |
| Artist A | ChatGPT | `ARTIST_A_CHARACTERS.md` (survivor, creatures, key art) | Survivor first, **send it to Artist B** |
| Artist B | ChatGPT | `ARTIST_B_WORLD.md` (tiles, backgrounds, rooms, props, icons, UI) | Tiles + sky while waiting for the survivor |

Artists also share the load of sounds, event text and playtesting. Each Coder puts the art into their own scenes (Coder 1 outside, Coder 2 the bunker), starting with the survivor, tiles and bunker rooms. The lead (Coder 1) does the final integration. Everyone playtests. `ASSET_PROMPTS.md` is the older combined version, use the two artist files instead.

Rules: commit small and often. Don't both edit the same scene. Export the game for web or desktop at the **midpoint** and again in the last hour, so a broken export never surprises you.

---

## 8. Learning links
- Godot docs: https://docs.godotengine.org (search "Your first 2D game", "Using TileMaps")
- Beginner 2D platformer series (written with the older TileMap node, adapt to TileMapLayer): https://dev.to/christinec_dev/learn-godot-4-by-making-a-2d-platformer-part-4-level-creation-1-4obb
- Godot's TileMapLayer demo with video: https://www.godotengine.org/asset-library/asset/3259
- Engine comparison used for this recommendation: https://app.cinevva.com/guides/best-2d-game-engines-2026
- Design references: *This War of Mine* (scavenge by day, survive by night, scarcity and choices), *Fallout Shelter* (food/water/power balance), *Terraria* (look, digging), Minecraft (respawn at bed).

Note: the research sources are mostly vendor blogs and community posts, so treat engine comparisons as guidance, not benchmarks.
