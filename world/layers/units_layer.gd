class_name UnitsLayer
extends MapLayer


func _init() -> void:
	dynamic = true


func _draw() -> void:
	if view == null or view.world == null:
		return
	var w := view.world
	for id in view.selected:
		var u = w.units.get(id)
		if u == null or u["path"].is_empty():
			continue
		var pts := PackedVector2Array([view.lerp_pos(u)])
		for t in u["path"]:
			pts.append(GameWorld.center_of(t) * T)
		draw_polyline(pts, Color(1, 1, 1, 0.35), 1.0)
	for u in w.units.values():
		var def: Dictionary = ContentDB.find(u["type"])
		var p := view.lerp_pos(u)
		var col: Color = w.countries[u["owner"]]["color"]
		var sel: bool = u["id"] in view.selected
		draw_circle(p, 6.5, Color.WHITE if sel else Color(0, 0, 0, 0.85))
		draw_circle(p, 5.0, col)
		text_centered(p, str(def.get("icon", "?")), 8, Color.WHITE, Color(0, 0, 0, 0))
		var max_hp := float(def.get("hp", 50))
		var hp := float(u["hp"])
		if hp < max_hp:
			draw_rect(Rect2(p + Vector2(-6, -9), Vector2(12, 2)), Color(0.2, 0, 0))
			draw_rect(Rect2(p + Vector2(-6, -9), Vector2(12.0 * hp / max_hp, 2)), Color("#5f5"))
