class_name Strikes
extends RefCounted
## Drones and missiles in flight, launchers, and air-defence interception.

var w: GameWorld


func _init(world: GameWorld) -> void:
	w = world


func register_commands(bus: CommandBus) -> void:
	bus.register("mil.launch", _v_launch, _a_launch)


## Nearest ready launcher of country `c` that can reach `target` (tile coords).
func find_launcher(c: int, def: Dictionary, target: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	var r := float(def.get("range", 10))
	for b in w.buildings.values():
		if b["owner"] != c or b["type"] != def.get("launcher") or not b["done"] or b["cd"] > 0:
			continue
		var d := GameWorld.center_of(b["tile"]).distance_to(target)
		if d <= r and d < best_d:
			best_d = d
			best = b
	return best


func ready_launchers(c: int, def: Dictionary) -> int:
	var n := 0
	for b in w.buildings.values():
		if b["owner"] == c and b["type"] == def.get("launcher") and b["done"] and b["cd"] <= 0:
			n += 1
	return n


func _v_launch(cmd: Dictionary) -> String:
	var def: Dictionary = ContentDB.find(str(cmd["args"].get("type", "")))
	if def.get("category") != "strike":
		return "Unknown strike type"
	var t := Vector2i(int(cmd["args"].get("x", -1)), int(cmd["args"].get("y", -1)))
	if not w.in_bounds(t):
		return "Target outside the map"
	if not w.at_war(cmd["by"], w.owner_at(t)):
		return "Strikes can only target countries you are at war with"
	if find_launcher(cmd["by"], def, GameWorld.center_of(t)).is_empty():
		return "No ready %s within range" % ContentDB.find(def["launcher"]).get("name", "launcher")
	if not w.economy.can_afford(w.countries[cmd["by"]], def.get("cost", {})):
		return "Not enough resources for " + def["name"]
	return ""


func _a_launch(cmd: Dictionary) -> void:
	var def: Dictionary = ContentDB.find(cmd["args"]["type"])
	var target := GameWorld.center_of(Vector2i(int(cmd["args"]["x"]), int(cmd["args"]["y"])))
	var launcher := find_launcher(cmd["by"], def, target)
	w.economy.pay(w.countries[cmd["by"]], def.get("cost", {}))
	launcher["cd"] = int(float(def.get("reload", 5)) / GameWorld.TICK)
	var id := w.new_id()
	var start := GameWorld.center_of(launcher["tile"])
	w.strikes[id] = {"id": id, "type": def["id"], "owner": cmd["by"], "pos": start, "ppos": start,
		"from": start, "target": target}
	var victim := w.owner_at(GameWorld.tile_of(target))
	if victim == w.player_id:
		w.notify("Incoming %s from %s!" % [def["name"].to_lower(), w.cname(cmd["by"])], w.player_id)


func update() -> void:
	for b in w.buildings.values():
		if b["cd"] > 0:
			b["cd"] -= 1
	for s in w.strikes.values():
		s["ppos"] = s["pos"]
		var def: Dictionary = ContentDB.find(s["type"])
		var to: Vector2 = s["target"] - s["pos"]
		var step: float = float(def.get("speed", 3)) * GameWorld.TICK
		if to.length() <= step:
			s["pos"] = s["target"]
			_explode(s, def)
			w.strikes.erase(s["id"])
		else:
			s["pos"] = s["pos"] + to.normalized() * step
	_air_defense()


func _air_defense() -> void:
	if w.strikes.is_empty():
		return
	for b in w.buildings.values():
		var def: Dictionary = ContentDB.find(b["type"])
		if not def.has("ad") or not b["done"] or b["cd"] > 0:
			continue
		var ad: Dictionary = def["ad"]
		var here := GameWorld.center_of(b["tile"])
		var best := {}
		var best_d := INF
		for s in w.strikes.values():
			if not w.at_war(b["owner"], s["owner"]):
				continue
			var d: float = here.distance_to(s["pos"])
			if d <= float(ad["range"]) and d < best_d:
				best_d = d
				best = s
		if best.is_empty():
			continue
		b["cd"] = int(float(ad["reload"]) / GameWorld.TICK)
		w.add_fx("intercept", here, best["pos"], 0.0, 4)
		var chance: float = float(ad["chance"]) * ContentDB.num(best["type"], "evasion", 1.0)
		if w.rng.randf() < chance:
			w.add_fx("pop", best["pos"], Vector2.ZERO, 0.5, 6)
			w.strikes.erase(best["id"])
			if best["owner"] == w.player_id:
				w.notify("Your %s was shot down" % ContentDB.find(best["type"]).get("name", "strike").to_lower(), w.player_id)


func _explode(s: Dictionary, def: Dictionary) -> void:
	var r := float(def.get("radius", 1.0))
	var dmg := float(def.get("damage", 30))
	var p: Vector2 = s["pos"]
	w.add_fx("blast", p, Vector2.ZERO, r, 12)
	for u in w.units.values():
		if not w.at_war(s["owner"], u["owner"]):
			continue
		var d: float = p.distance_to(u["pos"])
		if d <= r:
			u["hp"] -= dmg * (1.0 - d / (r * 1.5))
	for b in w.buildings.values():
		if not w.at_war(s["owner"], b["owner"]):
			continue
		if p.distance_to(GameWorld.center_of(b["tile"])) <= r:
			b["hp"] -= dmg
			if b["hp"] <= 0:
				if b["owner"] == w.player_id or s["owner"] == w.player_id:
					w.notify("%s destroyed by a %s" % [ContentDB.find(b["type"]).get("name", "Building"), def["name"].to_lower()], w.player_id)
				w.destroy_building(b["id"])
