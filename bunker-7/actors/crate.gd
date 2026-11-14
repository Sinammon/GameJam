extends Area2D
# A lootable crate. Press E near it. Contents are rolled once in setup().

const KINDS := ["wood", "concrete", "scrap"]
# When the backpack can't fit everything, the rarest items go in first.
const TAKE_ORDER := ["circuits", "scrap", "concrete", "wood"]

var contents := {}   # kind -> amount left inside

const TEX_CLOSED := "res://art/world_clean/obj_crate_closed.png"
const TEX_OPEN := "res://art/world_clean/obj_crate_open.png"
var art: Sprite2D = null   # null = placeholder ColorRect "Sprite"

func _ready() -> void:
	art = Art.sprite(self, TEX_CLOSED)
	if art:
		$Sprite.visible = false

# Looks opened (art, or a darker placeholder box).
func show_open() -> void:
	if art and ResourceLoader.exists(TEX_OPEN):
		art.texture = load(TEX_OPEN)
		art.offset = Vector2(-floorf(art.texture.get_width() / 2.0), -art.texture.get_height())
	else:
		$Sprite.color = Color(0.3, 0.25, 0.2)

# far: 0.0 (next to the hatch) .. 1.0 (far right edge). loot_mult comes from GameState.
func setup(far: float, loot_mult: float) -> void:
	var count := maxi(1, roundi(randi_range(2, 4) * loot_mult))
	for i in count:
		var kind: String = KINDS[randi() % KINDS.size()]
		contents[kind] = contents.get(kind, 0) + 1
	# Rare circuit, only in the far right of the map.
	if far > 0.7 and randf() < 0.35:
		contents["circuits"] = 1

func is_empty() -> bool:
	return contents.is_empty()

func can_interact(_player: Node) -> bool:
	return not is_empty()

# Called by the player when E is pressed in reach.
func interact(player: Node) -> void:
	if is_empty():
		player.say("Empty crate")
		return
	if player.capacity_left() <= 0:
		player.say("Backpack full!")
		return
	var got := take_into(contents, player)
	if is_empty():
		show_open()
		player.say(", ".join(got))
	else:
		player.say(", ".join(got) + " (full, loot left in crate)")

# Moves as much of src into the player's backpack as fits (rarest first) and
# removes what was taken from src. Returns lines like "+2 wood". Shared with the pack.
static func take_into(src: Dictionary, player: Node) -> Array:
	var got := []
	for kind in TAKE_ORDER:
		if not src.has(kind):
			continue
		var added: int = player.add_item(kind, src[kind])
		src[kind] -= added
		if src[kind] <= 0:
			src.erase(kind)
		if added > 0:
			got.append("+%d %s" % [added, kind])
	return got
