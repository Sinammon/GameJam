extends Area2D
# A supply spot outside (V3): press E to take what it gives, a few times.
#   puddle / barrel / water_pool -> dirty water      mushroom -> mushroom
# Placed by the expedition from the location's "sources" list (scenes/locations.gd).
# Art: art/world_clean/obj_<kind>.png (obj_water_pool, obj_mushroom, obj_puddle, obj_barrel)
# if present, else a drawn placeholder. Same interact contract as crates (can_interact / interact).

const KINDS := {
	# kind: [item, uses, per use, label]
	"puddle":     ["dirty_water", 2, 1, "Puddle"],
	"barrel":     ["dirty_water", 3, 1, "Rain barrel"],
	"water_pool": ["dirty_water", 3, 1, "Dripping pool"],
	"mushroom":   ["mushroom", 1, 1, "Mushrooms"],
}
const COLORS := {
	"puddle": Color(0.32, 0.42, 0.36, 0.9), "barrel": Color(0.42, 0.3, 0.22),
	"water_pool": Color(0.25, 0.4, 0.42, 0.9), "mushroom": Color(0.85, 0.75, 0.6),
}

var kind := "puddle"
var item := "dirty_water"
var uses := 2
var per_use := 1
var _art: Node2D = null

func setup(source_kind: String) -> void:
	kind = source_kind if KINDS.has(source_kind) else "puddle"
	item = KINDS[kind][0]
	uses = KINDS[kind][1]
	per_use = KINDS[kind][2]

func _ready() -> void:
	add_to_group("sources")
	collision_layer = 4
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(18, 14)
	shape.shape = rect
	shape.position = Vector2(0, -7)
	add_child(shape)
	_art = Art.sprite(self, "res://art/world_clean/obj_%s.png" % kind, 1.0)
	if _art != null and kind == "mushroom":
		_art.add_to_group("light_glow")   # the cave mushrooms glow (Lighting keeps them bright in the dark)
	if _art == null:
		_art = _placeholder()
		add_child(_art)

func _placeholder() -> Node2D:
	var n := Node2D.new()
	n.name = "Placeholder"
	var c: Color = COLORS[kind]
	match kind:
		"puddle", "water_pool":
			_box(n, Rect2(-9, -2, 18, 3), c)
			_box(n, Rect2(-6, -3, 9, 1), c.lightened(0.35))
			if kind == "water_pool":   # drips from above
				_box(n, Rect2(-1, -14, 1, 3), c.lightened(0.4))
				_box(n, Rect2(3, -9, 1, 2), c.lightened(0.4))
		"barrel":
			_box(n, Rect2(-6, -14, 12, 14), c)
			_box(n, Rect2(-6, -11, 12, 1), Color(0.25, 0.25, 0.27))
			_box(n, Rect2(-6, -4, 12, 1), Color(0.25, 0.25, 0.27))
			_box(n, Rect2(-5, -14, 10, 2), Color(0.3, 0.42, 0.36))
		"mushroom":
			for i in 3:
				var x := -6 + i * 5
				var h := 4 + (i % 2) * 3
				_box(n, Rect2(x + 1, -h, 2, h), Color(0.9, 0.88, 0.8))
				_box(n, Rect2(x - 1, -h - 3, 6, 3), c if i != 1 else Color(0.75, 0.45, 0.3))
	return n

static func _box(parent: Node, r: Rect2, c: Color) -> void:
	var b := ColorRect.new()
	b.position = r.position
	b.size = r.size
	b.color = c
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)

func label() -> String:
	return str(KINDS[kind][3])

func can_interact(_player: Node) -> bool:
	return uses > 0

func interact(player: Node) -> void:
	if uses <= 0:
		player.say("%s: nothing left" % label())
		return
	var got: int = player.add_item(item, per_use)
	if got <= 0:
		player.say("Backpack full!")
		return
	uses -= 1
	player.say("+%d %s%s" % [got, item.replace("_", " "), "" if uses > 0 else " (used up)"])
	if uses <= 0 and _art:
		_art.modulate = Color(0.5, 0.5, 0.5, 0.6)
		if kind == "mushroom":
			_art.visible = false
