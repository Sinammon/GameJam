extends Area2D
# A lootable crate. Press E near it. Contents are rolled once in setup().

const KINDS := ["wood", "concrete", "scrap"]

var contents := {}   # kind -> amount left inside

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

# Called by the player when E is pressed in reach.
func interact(player: Node) -> void:
	if is_empty():
		player.message.emit("Empty crate")
		return
	if player.capacity_left() <= 0:
		player.message.emit("Backpack full!")
		return
	var got := []
	for kind in contents.keys():
		var added: int = player.add_item(kind, contents[kind])
		contents[kind] -= added
		if contents[kind] <= 0:
			contents.erase(kind)
		if added > 0:
			got.append("+%d %s" % [added, kind])
	if is_empty():
		$Sprite.color = Color(0.3, 0.25, 0.2)   # looks opened
		player.message.emit(", ".join(got))
	else:
		player.message.emit(", ".join(got) + " (full, loot left in crate)")
