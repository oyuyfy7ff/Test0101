extends Node
## Entry point: owns the GameWorld, runs the fixed-step simulation loop,
## and wires the map view and HUD together.

const MAX_STEPS_PER_FRAME := 8

var world: GameWorld
var map_view: MapView
var hud: Hud
var speed := 1
var last_speed := 1
var acc := 0.0


func _ready() -> void:
	randomize()
	map_view = MapView.new()
	add_child(map_view)
	hud = Hud.new()
	add_child(hud)
	hud.speed_requested.connect(set_speed)
	hud.save_requested.connect(save_game)
	hud.load_requested.connect(load_game)
	hud.new_game_requested.connect(new_game)
	new_game()


func new_game() -> void:
	var w := GameWorld.new()
	WorldGen.generate(w, {"seed": randi(), "countries": 6, "width": 96, "height": 64})
	_set_world(w)
	hud.on_notify("You lead %s. Build an economy, raise an army, take enemy capitals." % w.cname(w.player_id))


func _set_world(w: GameWorld) -> void:
	if world != null:
		world.dispose()
	world = w
	acc = 0.0
	world.notified.connect(hud.on_notify)
	world.bus.rejected.connect(_on_rejected)
	world.ended.connect(hud.show_end)
	map_view.set_world(world)
	hud.set_world(world, map_view)
	set_speed(1)


func _on_rejected(cmd: Dictionary, reason: String) -> void:
	if int(cmd.get("by", -1)) == world.player_id:
		hud.on_notify("Cannot do that: " + reason, world.player_id)


func set_speed(s: int) -> void:
	if s > 0:
		last_speed = s
	speed = s
	hud.set_speed(s)


func save_game() -> void:
	if SaveGame.save(world):
		hud.on_notify("Game saved")
	else:
		hud.on_notify("Save failed")


func load_game() -> void:
	if not SaveGame.exists():
		hud.on_notify("No saved game")
		return
	var w := SaveGame.load_world()
	if w == null:
		hud.on_notify("Save file is incompatible")
		return
	_set_world(w)
	if w.result != "":
		hud.show_end(w.result)
	hud.on_notify("Game loaded (day %d)" % w.day())


func _process(delta: float) -> void:
	if world == null:
		return
	if speed > 0 and world.result == "":
		acc += delta * speed
		var steps := 0
		while acc >= GameWorld.TICK and steps < MAX_STEPS_PER_FRAME:
			world.step()
			acc -= GameWorld.TICK
			steps += 1
		if steps == MAX_STEPS_PER_FRAME:
			acc = 0.0
		map_view.alpha = clampf(acc / GameWorld.TICK, 0.0, 1.0)
	else:
		map_view.alpha = 1.0


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			set_speed(0 if speed > 0 else last_speed)
		KEY_1:
			set_speed(1)
		KEY_2:
			set_speed(2)
		KEY_3:
			set_speed(4)
		KEY_F5:
			save_game()
		KEY_F9:
			load_game()
