class_name Art
extends RefCounted
# Small helpers for optional art: every texture may be missing, callers keep
# their placeholder when these return null / empty arrays.

static var _sheet_cache := {}   # path -> Array[Texture2D] (split sheets)

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

# Frame files prefix_0.png, prefix_1.png, ... (stops at the first missing one).
# e.g. frames("res://art/characters_clean/zombie_walk") -> [tex0, tex1, ...]
static func frames(prefix: String, max_frames := 12) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for i in max_frames:
		var t := texture("%s_%d.png" % [prefix, i])
		if t == null:
			break
		out.append(t)
	return out

# RGBA8 image of a texture (or null). Used to cut sheets and resize atlases.
static func image(path: String) -> Image:
	var tex := texture(path)
	if tex == null:
		return null
	var img := tex.get_image()   # GPU readback; may fail on some web browsers
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img

# Splits a sheet of separate objects on transparent background into one texture
# per object, left to right (objects are separated by fully transparent columns).
# Each piece is cropped to its opaque box. Empty array if the file is missing.
static func split_sheet(path: String) -> Array[Texture2D]:
	if _sheet_cache.has(path):
		return _sheet_cache[path]
	var out: Array[Texture2D] = []
	var img := image(path)
	if img != null:
		var w := img.get_width()
		var h := img.get_height()
		var start := -1
		for x in w + 1:
			var used := false
			if x < w:
				for y in h:
					if img.get_pixel(x, y).a > 0.1:
						used = true
						break
			if used and start < 0:
				start = x
			elif not used and start >= 0:
				var piece := img.get_region(Rect2i(start, 0, x - start, h))
				var box := piece.get_used_rect()
				if box.size.x > 0 and box.size.y > 0:
					out.append(ImageTexture.create_from_image(piece.get_region(box)))
				start = -1
	_sheet_cache[path] = out
	return out
