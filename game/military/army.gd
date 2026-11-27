class_name Army
extends RefCounted
## Land units: movement along A* paths, automatic combat, territory capture.

const SPREAD_EVERY := 10     # ticks between capturing neighbouring tiles
const STARVE_DAMAGE := 0.05  # hp per tick while the owner is out of food
const FORMATION := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1), Vector2i(2, 0), Vector2i(0, 2),
	Vector2i(-2, 0), Vector2i(0, -2)]

var w: GameWorld
var grid := {}   # Vector2i -> Array of unit ids, rebuilt every tick


func _init(world: GameWorld) -> void:
	w = world


func register_commands(bus: CommandBus) -> void:
	bus.register("mil.order_move", _v_move, _a_move)
	bus.register("army.order_hold", _v_ids, _a_hold)
	bus.register("army.disband", _v_ids, _a_disband)


func spawn_unit(owner: int, utype: String, tile: Vector2i) -> int:
	var def: Dictionary = ContentDB.find(utype)
	if def.is_empty():
		return -1
	var id := w.new_id()
	var pos := GameWorld.center_of(tile) + Vector2(w.rng.randf_range(-0.3, 0.3), w.rng.randf_range(-0.3, 0.3))
	w.units[id] = {"id": id, "type": utype, "owner": owner, "pos": pos, "ppos": pos,
		"path": [], "attack_move": true, "hp": float(def.get("hp", 50)), "cd": 0}
	return id


func units_of(c: int) -> Array:
	var out := []
	for u in w.units.values():
		if u["owner"] == c:
			out.append(u)
	return out


# ---------------------------------------------------------------- commands

func _owned_ids(cmd: Dictionary) -> Array:
	var out := []
	for id in cmd["args"].get("ids", []):
		var u = w.units.get(int(id))
		if u != null and u["owner"] == cmd["by"]:
			out.append(int(id))
	return out


func _v_ids(cmd: Dictionary) -> String:
	return "" if not _owned_ids(cmd).is_empty() else "No units selected"


func _v_move(cmd: Dictionary) -> String:
	if _owned_ids(cmd).is_empty():
		return "No units selected"
	var t := Vector2i(int(cmd["args"].get("x", -1)), int(cmd["args"].get("y", -1)))
	if not w.is_land(t):
		return "Units cannot move onto water"
	return ""


func _a_move(cmd: Dictionary) -> void:
	var target := Vector2i(int(cmd["args"]["x"]), int(cmd["args"]["y"]))
	var attack: bool = cmd["args"].get("attack", true)
	var slot := 0
	for id in _owned_ids(cmd):
		var u: Dictionary = w.units[id]
		var dest := target
		while slot < FORMATION.size():
			var cand: Vector2i = target + FORMATION[slot]
			slot += 1
			if w.is_land(cand):
				dest = cand
				break
		var from := GameWorld.tile_of(u["pos"])
		var path: Array = w.astar.get_id_path(from, dest)
		if not path.is_empty():
			path.pop_front()
		u["path"] = path
		u["attack_move"] = attack


func _a_hold(cmd: Dictionary) -> void:
	for id in _owned_ids(cmd):
		w.units[id]["path"] = []


func _a_disband(cmd: Dictionary) -> void:
	for id in _owned_ids(cmd):
		w.units.erase(id)


# ---------------------------------------------------------------- simulation

func update() -> void:
	_rebuild_grid()
	var dead := []
	for u in w.units.values():
		if not w.units.has(u["id"]):
			continue   # removed this tick (e.g. its country was eliminated)
		if u["hp"] <= 0:
			dead.append(u["id"])
			continue
		u["ppos"] = u["pos"]
		var def: Dictionary = ContentDB.find(u["type"])
		var rng_range := float(def.get("range", 1.0))
		if u["cd"] > 0:
			u["cd"] -= 1
		var enemy := _find_enemy(u, rng_range)
		if not enemy.is_empty():
			if u["cd"] <= 0:
				_hit(u, def, enemy)
		elif u["cd"] <= 0:
			_hit_building(u, def, rng_range)
		if enemy.is_empty() or not u["attack_move"]:
			_move(u, def)
		_capture(u)
		if w.countries[u["owner"]]["starving"]:
			u["hp"] -= STARVE_DAMAGE
	for u in w.units.values():
		if u["hp"] <= 0 and not u["id"] in dead:
			dead.append(u["id"])
	for id in dead:
		w.units.erase(id)


func _rebuild_grid() -> void:
	grid.clear()
	for u in w.units.values():
		var t := GameWorld.tile_of(u["pos"])
		if not grid.has(t):
			grid[t] = []
		grid[t].append(u["id"])


func _find_enemy(u: Dictionary, r: float) -> Dictionary:
	var t := GameWorld.tile_of(u["pos"])
	var reach := int(ceil(r))
	var best := {}
	var best_d := INF
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			for oid in grid.get(t + Vector2i(dx, dy), []):
				var o: Dictionary = w.units.get(oid, {})
				if o.is_empty() or o["hp"] <= 0 or not w.at_war(u["owner"], o["owner"]):
					continue
				var d: float = u["pos"].distance_to(o["pos"])
				if d <= r and d < best_d:
					best_d = d
					best = o
	return best


func _hit(u: Dictionary, def: Dictionary, target: Dictionary) -> void:
	var ter := w.terrain_at(GameWorld.tile_of(target["pos"]))
	var dmg: float = float(def.get("attack", 5)) * w.rng.randf_range(0.8, 1.2) / GameWorld.DEFENSE_MULT[ter]
	target["hp"] -= dmg
	u["cd"] = int(float(def.get("reload", 1.0)) / GameWorld.TICK)
	w.add_fx("tracer", u["pos"], target["pos"], 0.0, 3)
	if float(def.get("range", 1.0)) > 2.0:
		w.add_fx("blast", target["pos"], Vector2.ZERO, 0.6, 6)


func _hit_building(u: Dictionary, def: Dictionary, r: float) -> void:
	var t := GameWorld.tile_of(u["pos"])
	var reach := int(ceil(r))
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var bt := t + Vector2i(dx, dy)
			if not w.building_at.has(bt):
				continue
			var b: Dictionary = w.buildings[w.building_at[bt]]
			if not w.at_war(u["owner"], b["owner"]):
				continue
			if u["pos"].distance_to(GameWorld.center_of(bt)) > r:
				continue
			b["hp"] -= float(def.get("attack", 5)) * 0.5
			u["cd"] = int(float(def.get("reload", 1.0)) / GameWorld.TICK)
			w.add_fx("tracer", u["pos"], GameWorld.center_of(bt), 0.0, 3)
			if b["hp"] <= 0:
				if b["owner"] == w.player_id or u["owner"] == w.player_id:
					w.notify("%s destroyed" % ContentDB.find(b["type"]).get("name", "Building"), w.player_id)
				w.destroy_building(b["id"])
			return


func _move(u: Dictionary, def: Dictionary) -> void:
	var path: Array = u["path"]
	if path.is_empty():
		return
	var next: Vector2i = path[0]
	if not w.can_enter(u["owner"], next):
		path.clear()
		if u["owner"] == w.player_id:
			w.notify("Units stopped at %s's border: declare war or ally first." % w.cname(w.owner_at(next)), w.player_id)
		return
	var target := GameWorld.center_of(next)
	var cur := w.terrain_at(GameWorld.tile_of(u["pos"]))
	var step: float = float(def.get("speed", 1.0)) * GameWorld.MOVE_MULT[cur] * GameWorld.TICK
	var to: Vector2 = target - u["pos"]
	if to.length() <= step:
		u["pos"] = target
		path.pop_front()
	else:
		u["pos"] = u["pos"] + to.normalized() * step


func _enemy_present(t: Vector2i, c: int) -> bool:
	for oid in grid.get(t, []):
		var o: Dictionary = w.units.get(oid, {})
		if not o.is_empty() and o["hp"] > 0 and w.at_war(c, o["owner"]):
			return true
	return false


func _capturable(c: int, t: Vector2i) -> bool:
	if not w.is_land(t):
		return false
	var o := w.owner_at(t)
	if o == c:
		return false
	return (o == -1 or w.at_war(c, o)) and not _enemy_present(t, c)


func _capture(u: Dictionary) -> void:
	var c: int = u["owner"]
	var t := GameWorld.tile_of(u["pos"])
	if _capturable(c, t):
		w.set_tile_owner(t, c)
	if not w.countries[c]["alive"]:
		return
	if (w.tick + int(u["id"])) % SPREAD_EVERY == 0:
		for d in GameWorld.DIRS4:
			var nt: Vector2i = t + d
			if _capturable(c, nt):
				w.set_tile_owner(nt, c)
