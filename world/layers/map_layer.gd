class_name MapLayer
extends Node2D
## Base class for one drawing layer of the map (stacked in MapView).

const T := 16.0   # keep equal to MapView.TILE

var view: MapView
var dynamic := false   # true = redrawn every frame


func on_world() -> void:
	queue_redraw()


func on_territory() -> void:
	pass


func font() -> Font:
	return ThemeDB.fallback_font


func text_centered(pos: Vector2, text: String, size: int, color: Color, outline := Color(0, 0, 0, 0.8)) -> void:
	var f := font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos + Vector2(-w * 0.5, size * 0.35)
	draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(2, size / 5), outline)
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
