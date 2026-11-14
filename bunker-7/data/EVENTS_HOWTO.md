# How to add a night event

Night events live in `data/events.json`. You don't need to touch any code.

1. Open `data/events.json` in any text editor.
2. Copy one whole event block (from `{` to the matching `},`) and paste it inside the `"events": [ ... ]` list.
   Put a comma between events, but not after the last one.
3. Change the text:
   - `"id"`: a short unique name, like `"dog"`.
   - `"title"`: shown big on the card.
   - `"description"`: one or two short sentences.
   - `"options"`: exactly two choices. Each has:
     - `"label"`: the button text (keep it short).
     - `"text"`: the result line shown after the player picks it.
     - `"effects"`: what happens (see below). `{}` means nothing.
     - `"cost"` (optional): what the player must pay to pick it, like `{"scrap": 3}`.
       If they can't pay, the button is greyed out. **The other option must have no cost**, so nobody gets stuck.
     - `"unless": "door"` (optional): the effects are skipped if the Reinforced Door works.
       Then `"unless_text"` is shown instead of `"text"`.
4. Save, run the game. If the file is broken, the game logs a warning and simply has no events (it won't crash).
   Paste the file into https://jsonlint.com to find the typo.

## Effects you can use
| Key | Example | Meaning |
|---|---|---|
| `wood`, `concrete`, `scrap`, `circuits`, `water`, `food` | `"food": -2` | add or remove (never goes below 0) |
| `health` | `"health": 3` | heal or hurt (stays between 1 and 10) |
| `skip_expedition` | `true` | storm: the player can't go outside tomorrow |
| `rad_mult` | `2.0` | radiation builds this many times faster tomorrow |
| `bonus_crate` | `true` | an extra crate tomorrow |
| `damage_room` | `true` | a random room with a building gets damaged (repair costs 3 scrap) |
| `repair_room` | `true` | repairs one damaged room for free |

Example:
```json
{
	"id": "dog",
	"title": "A dog scratches at the hatch",
	"description": "It looks hungry.",
	"options": [
		{"label": "Feed it", "text": "It licks your hand and runs off.", "cost": {"food": 1}, "effects": {"health": 1}},
		{"label": "Ignore it", "text": "It whines, then leaves.", "effects": {}}
	]
}
```
How often events happen depends on difficulty (Easy 20%, Normal 35%, Hard 55% each night). Every event has the same chance to be picked.
