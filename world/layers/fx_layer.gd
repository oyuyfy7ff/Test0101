class_name FxLayer
extends MapLayer
## Drones/missiles in flight, explosions, tracers and interceptions.


func _init() -> void:
	dynamic = true


func _draw() -> void:
	if view == null or view.world == null:
		return
	var w := view.world
	for s in w.strikes.values():
		var p := view.lerp_pos(s)
		var dir: Vector2 = (s["target"] - s["pos"]).normalized()
		var col: Color = w.countries[s["owner"]]["color"]
		if s["type"] == "strike:MISSILE":
			draw_line(p - dir * 14.0, p, Color(1, 0.8, 0.4, 0.5), 2.0)
			draw_line(p - dir * 5.0, p + dir * 3.0, Color.WHITE, 3.0)
		else:
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([p + dir * 5.0, p + side * 4.0, p - dir * 3.0, p - side * 4.0]), col.lightened(0.3))
			draw_line(p + side * 4.0, p - side * 4.0, Color.BLACK, 1.0)
	for f in w.fx:
		var k: float = 1.0 - float(f["ttl"]) / float(f["max"])
		var p: Vector2 = f["pos"] * T
		match f["kind"]:
			"blast":
				var r: float = float(f["radius"]) * T * (0.4 + 0.6 * k)
				draw_circle(p, r, Color(1.0, 0.55, 0.1, 0.55 * (1.0 - k)))
				draw_arc(p, r, 0, TAU, 24, Color(1, 0.9, 0.6, 0.8 * (1.0 - k)), 1.5)
			"tracer":
				draw_line(p, f["to"] * T, Color(1, 1, 0.7, 0.6 * (1.0 - k)), 1.0)
			"intercept":
				draw_line(p, f["to"] * T, Color(0.6, 0.9, 1.0, 0.9 * (1.0 - k)), 1.5)
			"pop":
				draw_circle(p, 3.0 + 6.0 * k, Color(0.8, 0.95, 1.0, 0.7 * (1.0 - k)))
