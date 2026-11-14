# Run once (already done, outputs are committed):
#   Godot --headless --path bunker-7 --script res://tools/make_tiles.gd
# Generates art/world/tiles_placeholder.png (2 tiles, 16x16) and art/world/tileset_placeholder.tres.
# Tile 0 (atlas 0,0) = solid ground, WITH collision. Tile 1 (atlas 1,0) = dirt, NO collision.
# This placeholder set is only the FALLBACK now: scenes/expedition.gd build_tileset() makes the
# real TileSet at runtime from art/world_clean/tiles_outside.png (alt 0 = collision, alt 1 = none).
extends SceneTree

func _init() -> void:
	# --- the PNG: 32x16, two tiles ---
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var n := ((x * 7 + y * 13) % 5) * 4  # cheap noise so it is not flat
			var ground := Color8(110 + n, 95 + n, 80 + n)
			if y < 3:
				ground = Color8(70 + n, 120 + n, 60 + n)  # grassy top strip
			var dirt := Color8(80 + n, 55 + n, 40 + n)
			img.set_pixel(x, y, ground)
			img.set_pixel(16 + x, y, dirt)
	img.save_png("res://art/world/tiles_placeholder.png")

	# --- the TileSet ---
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)  # world = physics layer 1
	var src := TileSetAtlasSource.new()
	src.texture = load("res://art/world/tiles_placeholder.png")
	src.texture_region_size = Vector2i(16, 16)
	src.create_tile(Vector2i(0, 0))
	src.create_tile(Vector2i(1, 0))
	ts.add_source(src, 0)
	var td: TileData = src.get_tile_data(Vector2i(0, 0), 0)
	td.add_collision_polygon(0)
	td.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]))
	var err := ResourceSaver.save(ts, "res://art/world/tileset_placeholder.tres")
	print("tileset saved, err=", err)
	quit()
