class_name BuildingsLayer
extends MapLayer


func _init() -> void:
	dynamic = true


func _draw() -> void:
	if view == null or view.world == null:
		return
	var w := view.world
	for b in w.buildings.values():
		var def: Dictionary = ContentDB.find(b["type"])
		var p := GameWorld.center_of(b["tile"]) * T
		var col: Color = w.countries[b["owner"]]["color"] if b["owner"] >= 0 else Color.GRAY
		var a := 1.0 if b["done"] else 0.55
		var r := Rect2(p - Vector2(6, 6), Vector2(12, 12))
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.8 * a))
		draw_rect(r, Color(col.darkened(0.25), a))
		text_centered(p, str(def.get("icon", "?")), 9, Color(1, 1, 1, a), Color(0, 0, 0, 0))
		if not b["done"]:
			draw_rect(Rect2(p + Vector2(-6, 7), Vector2(12.0 * float(b["progress"]), 2)), Color("#7cf"))
		var max_hp := float(def.get("hp", 100))
		if float(b["hp"]) < max_hp:
			draw_rect(Rect2(p + Vector2(-6, -9), Vector2(12, 2)), Color(0.2, 0, 0))
			draw_rect(Rect2(p + Vector2(-6, -9), Vector2(12.0 * float(b["hp"]) / max_hp, 2)), Color("#e44"))
		if def.has("ad") and b["owner"] == w.player_id:
			draw_arc(p, float(def["ad"]["range"]) * T, 0, TAU, 48, Color(0.5, 0.9, 1.0, 0.18), 1.0)
