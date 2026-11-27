class_name GroundLayer
extends MapLayer
## Static terrain: one pixel per tile, scaled up, plus simple relief marks.

const COLORS := [Color("#1d3b5c"), Color("#7fa35a"), Color("#4f7a3d"), Color("#a39062"), Color("#8b8680"), Color("#d2bf7f")]
const SHALLOW := Color("#2b5a80")

var tex: ImageTexture


func on_world() -> void:
	var w := view.world
	var img := Image.create(w.width, w.height, false, Image.FORMAT_RGBA8)
	for y in w.height:
		for x in w.width:
			var t := Vector2i(x, y)
			var ter := w.terrain_at(t)
			var col: Color = COLORS[ter]
			if ter == GameWorld.T_WATER:
				for d in GameWorld.DIRS4:
					if w.is_land(t + d):
						col = SHALLOW
						break
			# deterministic per-tile shading
			var h := float((x * 73856093) ^ (y * 19349663)) / 4294967296.0
			col = col.darkened(fposmod(h, 1.0) * 0.08)
			img.set_pixel(x, y, col)
	tex = ImageTexture.create_from_image(img)
	queue_redraw()


func _draw() -> void:
	if view == null or view.world == null or tex == null:
		return
	var w := view.world
	draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(w.width, w.height) * T), false)
	for y in w.height:
		for x in w.width:
			var ter := w.terrain_at(Vector2i(x, y))
			var c := Vector2(x + 0.5, y + 0.5) * T
			match ter:
				GameWorld.T_MOUNTAIN:
					draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 4), c + Vector2(0, -5), c + Vector2(5, 4)]), Color("#6c6863"))
					draw_colored_polygon(PackedVector2Array([c + Vector2(-1.5, -2), c + Vector2(0, -5), c + Vector2(1.5, -2)]), Color("#e8e8e8"))
				GameWorld.T_HILLS:
					draw_arc(c + Vector2(0, 3), 4.0, PI, TAU, 6, Color("#857552"), 1.5)
				GameWorld.T_FOREST:
					draw_circle(c + Vector2(-2.5, 1), 2.6, Color("#3b6330"))
					draw_circle(c + Vector2(2.5, -1), 2.6, Color("#3b6330"))
