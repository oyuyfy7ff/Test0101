class_name MapView
extends Node2D
## Camera, input and the stack of map layers. Each layer draws one system.

signal tile_hovered(t: Vector2i)
signal mode_changed(mode: String, mode_type: String)
signal selection_changed(count: int)

const TILE := 16.0
const ZOOM_MIN := 0.35
const ZOOM_MAX := 4.0
const PAN_SPEED := 700.0

var world: GameWorld
var camera := Camera2D.new()
var layers: Array = []
var selected: Array = []
var mode := "select"          # select | build | launch
var mode_type := ""
var alpha := 1.0              # interpolation between the last two sim ticks
var hover := Vector2i(-1, -1)
var drag_start = null         # Vector2 while box-selecting
var drag_now := Vector2.ZERO
var panning := false
var order_marker := {}        # {pos, time}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(camera)
	camera.make_current()
	for script in [GroundLayer, TerritoryLayer, BuildingsLayer, UnitsLayer, FxLayer, OverlayLayer]:
		var layer: MapLayer = script.new()
		layer.view = self
		add_child(layer)
		layers.append(layer)


func set_world(w: GameWorld) -> void:
	world = w
	selected.clear()
	set_mode("select")
	w.territory_changed.connect(_on_territory_changed)
	for l in layers:
		l.on_world()
	var cap: Vector2i = w.countries[w.player_id]["capital"]
	camera.position = GameWorld.center_of(cap) * TILE
	camera.zoom = Vector2(1.6, 1.6)


func _on_territory_changed() -> void:
	for l in layers:
		l.on_territory()


func set_mode(m: String, t := "") -> void:
	mode = m
	mode_type = t
	mode_changed.emit(m, t)


func to_tile(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func lerp_pos(e: Dictionary) -> Vector2:
	return (e["ppos"] as Vector2).lerp(e["pos"], alpha) * TILE


func _process(delta: float) -> void:
	if world == null:
		return
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1
	camera.position += dir * PAN_SPEED * delta / camera.zoom.x
	camera.position = camera.position.clamp(Vector2.ZERO, Vector2(world.width, world.height) * TILE)
	var alive := []
	for id in selected:
		if world.units.has(id):
			alive.append(id)
	if alive.size() != selected.size():
		selected = alive
		selection_changed.emit(selected.size())
	for l in layers:
		if l.dynamic:
			l.queue_redraw()


func _zoom(factor: float) -> void:
	# Keep the point under the cursor fixed while zooming.
	var focus := get_global_mouse_position()
	var old := camera.zoom.x
	var z := clampf(old * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	camera.position = focus + (camera.position - focus) * (old / z)


func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		var wp := get_global_mouse_position()
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(1.0 / 1.15)
			MOUSE_BUTTON_MIDDLE:
				panning = mb.pressed
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_left_press(wp, mb.shift_pressed)
				else:
					_left_release(wp, mb.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_right_click(wp)
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if panning:
			camera.position -= mm.relative / camera.zoom.x
		drag_now = get_global_mouse_position()
		var t := to_tile(drag_now)
		if t != hover:
			hover = t
			tile_hovered.emit(t)
		return
	var mg := event as InputEventMagnifyGesture
	if mg != null:
		_zoom(mg.factor)
		return
	var pg := event as InputEventPanGesture
	if pg != null:
		camera.position += pg.delta * 20.0 / camera.zoom.x
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		if mode != "select":
			set_mode("select")
		else:
			selected.clear()
			selection_changed.emit(0)


func _left_press(wp: Vector2, shift: bool) -> void:
	var t := to_tile(wp)
	if mode == "build":
		world.submit(world.player_id, "mil.build", {"type": mode_type, "x": t.x, "y": t.y})
		if not shift:
			set_mode("select")
		return
	if mode == "launch":
		world.submit(world.player_id, "mil.launch", {"type": mode_type, "x": t.x, "y": t.y})
		return
	drag_start = wp
	drag_now = wp


func _left_release(wp: Vector2, shift: bool) -> void:
	if drag_start == null:
		return
	var rect := Rect2(drag_start, wp - drag_start).abs()
	drag_start = null
	if not shift:
		selected.clear()
	if rect.size.length() < 6.0:
		var best = null
		var best_d := TILE * 0.8
		for u in world.units.values():
			if u["owner"] != world.player_id:
				continue
			var d := wp.distance_to(lerp_pos(u))
			if d < best_d:
				best_d = d
				best = u["id"]
		if best != null and not best in selected:
			selected.append(best)
	else:
		for u in world.units.values():
			if u["owner"] == world.player_id and rect.has_point(lerp_pos(u)) and not u["id"] in selected:
				selected.append(u["id"])
	selection_changed.emit(selected.size())


func _right_click(wp: Vector2) -> void:
	if mode != "select":
		set_mode("select")
		return
	if selected.is_empty():
		return
	var t := to_tile(wp)
	world.submit(world.player_id, "mil.order_move", {"ids": selected.duplicate(), "x": t.x, "y": t.y, "attack": true})
	order_marker = {"pos": GameWorld.center_of(t) * TILE, "time": Time.get_ticks_msec()}


func select_all() -> void:
	selected.clear()
	for u in world.units.values():
		if u["owner"] == world.player_id:
			selected.append(u["id"])
	selection_changed.emit(selected.size())
