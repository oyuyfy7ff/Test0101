class_name TerritoryLayer
extends MapLayer
## Country colour fill, borders (red where two countries are at war),
## capitals and country names.

const FILL_ALPHA := 0.42

var tex: ImageTexture
var borders := PackedVector2Array()
var fronts := PackedVector2Array()
var labels := []   # [{pos, text, size}]


func on_world() -> void:
	on_territory()


func on_territory() -> void:
	var w := view.world
	var img := Image.create(w.width, w.height, false, Image.FORMAT_RGBA8)
	borders = PackedVector2Array()
	fronts = PackedVector2Array()
	var sums := {}
	for y in w.height:
		for x in w.width:
			var t := Vector2i(x, y)
			var o := w.owner_at(t)
			if o >= 0:
				var col: Color = w.countries[o]["color"]
				col.a = FILL_ALPHA
				img.set_pixel(x, y, col)
				if not sums.has(o):
					sums[o] = [Vector2.ZERO, 0]
				sums[o][0] += Vector2(x + 0.5, y + 0.5)
				sums[o][1] += 1
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			# right and bottom edges
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nt: Vector2i = t + d
				if not w.in_bounds(nt):
					continue
				var no := w.owner_at(nt)
				if no == o or (o < 0 and no < 0):
					continue
				var a := Vector2(nt) * T
				var b := a + (Vector2(0, T) if d.x == 1 else Vector2(T, 0))
				if w.at_war(o, no):
					fronts.append(a)
					fronts.append(b)
				elif w.is_land(t) and w.is_land(nt):
					borders.append(a)
					borders.append(b)
	tex = ImageTexture.create_from_image(img)
	labels.clear()
	for o in sums:
		var count: int = sums[o][1]
		if count < 4 or not w.countries[o]["alive"]:
			continue
		labels.append({"pos": sums[o][0] / count * T, "text": w.countries[o]["name"].to_upper(),
			"size": clampi(int(sqrt(count) * 1.6), 10, 40)})
	queue_redraw()


func _draw() -> void:
	if view == null or view.world == null or tex == null:
		return
	var w := view.world
	draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(w.width, w.height) * T), false)
	if borders.size() > 0:
		draw_multiline(borders, Color(0.05, 0.05, 0.08, 0.85), 1.5)
	if fronts.size() > 0:
		draw_multiline(fronts, Color(0.95, 0.15, 0.1, 0.95), 2.5)
	for c in w.countries:
		if c["alive"]:
			var p := GameWorld.center_of(c["capital"]) * T
			draw_circle(p, 6.0, Color(0, 0, 0, 0.7))
			draw_circle(p, 4.5, Color("#ffd84a"))
	for l in labels:
		text_centered(l["pos"], l["text"], l["size"], Color(1, 1, 1, 0.75))
