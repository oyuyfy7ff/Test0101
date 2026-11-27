class_name OverlayLayer
extends MapLayer
## Cursor feedback: hovered tile, build/launch previews, selection box, order marker.


func _init() -> void:
	dynamic = true


func _draw() -> void:
	if view == null or view.world == null:
		return
	var w := view.world
	var t := view.hover
	if w.in_bounds(t):
		var r := Rect2(Vector2(t) * T, Vector2(T, T))
		match view.mode:
			"build":
				var ok := w.owner_at(t) == w.player_id and w.is_land(t) and not w.building_at.has(t)
				var allowed: Array = ContentDB.find(view.mode_type).get("terrain", [])
				if not allowed.is_empty() and not GameWorld.TERRAIN_NAMES[w.terrain_at(t)] in allowed:
					ok = false
				draw_rect(r, Color(0.3, 1, 0.4, 0.35) if ok else Color(1, 0.2, 0.2, 0.35))
			"launch":
				var def: Dictionary = ContentDB.find(view.mode_type)
				var c := GameWorld.center_of(t) * T
				draw_arc(c, float(def.get("radius", 1)) * T, 0, TAU, 32, Color(1, 0.3, 0.2, 0.9), 2.0)
				draw_line(c - Vector2(8, 0), c + Vector2(8, 0), Color(1, 0.3, 0.2), 1.0)
				draw_line(c - Vector2(0, 8), c + Vector2(0, 8), Color(1, 0.3, 0.2), 1.0)
				for b in w.buildings.values():
					if b["owner"] == w.player_id and b["type"] == def.get("launcher") and b["done"]:
						draw_arc(GameWorld.center_of(b["tile"]) * T, float(def.get("range", 10)) * T, 0, TAU, 64, Color(1, 0.6, 0.2, 0.3), 1.0)
			_:
				draw_rect(r, Color(1, 1, 1, 0.5), false, 1.0)
	if view.drag_start != null:
		var rect := Rect2(view.drag_start, view.drag_now - view.drag_start).abs()
		draw_rect(rect, Color(0.6, 0.9, 1.0, 0.12))
		draw_rect(rect, Color(0.6, 0.9, 1.0, 0.8), false, 1.0)
	if not view.order_marker.is_empty():
		var age := (Time.get_ticks_msec() - int(view.order_marker["time"])) / 600.0
		if age < 1.0:
			draw_arc(view.order_marker["pos"], 4.0 + 8.0 * age, 0, TAU, 20, Color(0.4, 1, 0.5, 1.0 - age), 2.0)
