class_name Art
extends RefCounted
# Small helpers for optional art: every texture may be missing, callers keep
# their placeholder when these return null.

# Adds a Sprite2D child with its bottom-centre at (0,0) + `lift`. null if the texture is missing.
static func sprite(parent: Node, path: String, lift := 0.0) -> Sprite2D:
	var tex := texture(path)
	if tex == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-floorf(tex.get_width() / 2.0), -tex.get_height() + lift)
	parent.add_child(s)
	return s

static func texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
