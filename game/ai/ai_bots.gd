class_name AiBots
extends RefCounted
## AI countries. They read the world and only act by submitting the same
## commands the player's UI submits.

const THINK_EVERY := 20       # ticks (2 s at 1x)
const GRACE_DAYS := 25        # no AI-declared wars before this day
const BUILD_PLAN := [
	["building:FARM", 2], ["building:CIV_FACTORY", 2], ["building:MINE", 1],
	["building:OIL_WELL", 1], ["building:ARMS_FACTORY", 1], ["building:AIR_DEFENSE", 1],
	["building:CIV_FACTORY", 4], ["building:MINE", 2], ["building:DRONE_BASE", 1],
	["building:FARM", 4], ["building:AIR_DEFENSE", 3], ["building:BARRACKS", 2],
	["building:MISSILE_SILO", 1], ["building:CIV_FACTORY", 7], ["building:FARM", 6],
]

var w: GameWorld


func _init(world: GameWorld) -> void:
	w = world


func update() -> void:
	for c in w.countries:
		if not c["alive"] or not c["ai"]:
			continue
		if (w.tick + int(c["id"]) * 3) % THINK_EVERY != 0:
			continue
		_think(c)
	_answer_proposals()


func _think(c: Dictionary) -> void:
	var info := _scan(c["id"])
	_economy(c, info)
	_market(c)
	_military(c, info)
	_strikes(c)
	_diplomacy(c, info)


## One pass over the map: owned tiles, neighbours and enemy front tiles.
func _scan(id: int) -> Dictionary:
	var owned := []
	var neighbours := {}
	var front := []
	for y in w.height:
		for x in w.width:
			var t := Vector2i(x, y)
			if w.owner_at(t) != id:
				continue
			owned.append(t)
			for d in GameWorld.DIRS4:
				var nt: Vector2i = t + d
				var o := w.owner_at(nt)
				if o < 0 and w.is_land(nt):
					front.append(nt)   # unclaimed land is free to take
				elif o >= 0 and o != id:
					neighbours[o] = true
					if w.at_war(id, o):
						front.append(nt)
	return {"owned": owned, "neighbours": neighbours.keys(), "front": front}


# ---------------------------------------------------------------- economy

func _economy(c: Dictionary, info: Dictionary) -> void:
	var counts := {}
	for b in w.buildings.values():
		if b["owner"] == c["id"]:
			counts[b["type"]] = int(counts.get(b["type"], 0)) + 1
	var plan := BUILD_PLAN.duplicate()
	if float(c["delta"].get("food", 0.0)) < 0.0:
		plan.push_front(["building:FARM", int(counts.get("building:FARM", 0)) + 1])
	for step in plan:
		var btype: String = step[0]
		if int(counts.get(btype, 0)) >= int(step[1]):
			continue
		var def: Dictionary = ContentDB.find(btype)
		var tile := _pick_tile(c, def, info["owned"])
		if tile.x < 0:
			continue   # no suitable terrain, try the next goal
		if w.economy.can_afford(c, def.get("cost", {})):
			w.submit(c["id"], "mil.build", {"type": btype, "x": tile.x, "y": tile.y})
		return   # save up for this goal


func _pick_tile(c: Dictionary, def: Dictionary, owned: Array) -> Vector2i:
	if owned.is_empty():
		return Vector2i(-1, -1)
	var allowed: Array = def.get("terrain", [])
	var cap: Vector2i = c["capital"]
	var best := Vector2i(-1, -1)
	var best_d := INF
	for _i in 40:
		var t: Vector2i = owned[w.rng.randi() % owned.size()]
		if w.building_at.has(t) or t == cap:
			continue
		if not allowed.is_empty() and not GameWorld.TERRAIN_NAMES[w.terrain_at(t)] in allowed:
			continue
		var d := Vector2(t).distance_to(Vector2(cap))
		if d < best_d:
			best_d = d
			best = t
	return best


func _market(c: Dictionary) -> void:
	var money: float = c["money"]
	for res in ["food", "metal", "fuel"]:
		var amount: float = c["res"].get(res, 0.0)
		if amount < 25.0 and money > 1500.0:
			w.submit(c["id"], "econ.buy", {"res": res, "amount": 20})
		elif amount > 400.0:
			w.submit(c["id"], "econ.sell", {"res": res, "amount": 50})


# ---------------------------------------------------------------- military

func _military(c: Dictionary, info: Dictionary) -> void:
	var id: int = c["id"]
	var mine := w.army.units_of(id)
	var factories := 0
	for b in w.buildings.values():
		if b["owner"] == id and b["type"] == "building:CIV_FACTORY" and b["done"]:
			factories += 1
	var cap := 8 + factories * 4
	if mine.size() + c["queue"].size() < cap and c["queue"].size() < 3:
		var utype := "unit:INFANTRY"
		if w.economy.has_building(id, "building:ARMS_FACTORY"):
			var r := w.rng.randf()
			utype = "unit:TANK" if r < 0.35 else ("unit:ARTILLERY" if r < 0.6 else "unit:INFANTRY")
		if w.economy.can_afford(c, ContentDB.find(utype).get("cost", {})):
			w.submit(id, "army.recruit", {"type": utype})
	var enemies := w.enemies_of(id)
	var front: Array = info["front"]
	if front.is_empty() and not enemies.is_empty():
		front = [w.countries[enemies[0]]["capital"]]
	if front.is_empty():
		return
	for u in mine:
		if not u["path"].is_empty():
			continue
		if int(u["id"]) % 4 == 0 and not enemies.is_empty():
			continue   # keep a home guard
		var goal := _nearest(u["pos"], front)
		if not enemies.is_empty() and w.rng.randf() < 0.1:
			goal = w.countries[enemies[w.rng.randi() % enemies.size()]]["capital"]
		w.submit(id, "mil.order_move", {"ids": [u["id"]], "x": goal.x, "y": goal.y, "attack": true})


func _nearest(p: Vector2, tiles: Array) -> Vector2i:
	var best: Vector2i = tiles[0]
	var best_d := INF
	var n := mini(tiles.size(), 60)
	for i in n:
		var t: Vector2i = tiles[w.rng.randi() % tiles.size()] if tiles.size() > 60 else tiles[i]
		var d := p.distance_squared_to(GameWorld.center_of(t))
		if d < best_d:
			best_d = d
			best = t
	return best


func _strikes(c: Dictionary) -> void:
	var id: int = c["id"]
	if w.enemies_of(id).is_empty():
		return
	for def in ContentDB.list("strike"):
		if w.strike_sys.ready_launchers(id, def) == 0:
			continue
		var cost: Dictionary = def.get("cost", {})
		if float(c["money"]) < float(cost.get("money", 0)) * 3.0 or not w.economy.can_afford(c, cost):
			continue
		var targets := []
		for b in w.buildings.values():
			if w.at_war(id, b["owner"]):
				targets.append(GameWorld.center_of(b["tile"]))
		for u in w.units.values():
			if w.at_war(id, u["owner"]):
				targets.append(u["pos"])
		for _i in 12:
			if targets.is_empty():
				break
			var p: Vector2 = targets[w.rng.randi() % targets.size()]
			if not w.strike_sys.find_launcher(id, def, p).is_empty():
				var t := GameWorld.tile_of(p)
				w.submit(id, "mil.launch", {"type": def["id"], "x": t.x, "y": t.y})
				break


# ---------------------------------------------------------------- diplomacy

func _diplomacy(c: Dictionary, info: Dictionary) -> void:
	var id: int = c["id"]
	var mine := w.strength(id)
	var enemies := w.enemies_of(id)
	if enemies.is_empty():
		if w.day() < GRACE_DAYS:
			return
		var weakest := -1
		var weakest_s := INF
		for n in info["neighbours"]:
			if w.allied(id, n) or not w.countries[n]["alive"]:
				continue
			var s := w.strength(n)
			if s < weakest_s:
				weakest_s = s
				weakest = n
		if weakest >= 0 and mine > weakest_s * 1.4 + 5.0 and w.rng.randf() < 0.05 * float(c["aggr"]):
			w.submit(id, "diplo.declare_war", {"target": weakest})
		return
	for e in enemies:
		if mine < w.strength(e) * 0.5 and w.rng.randf() < 0.1 and not w.diplomacy.has_pending(id, e, "peace"):
			w.submit(id, "diplo.propose_peace", {"target": e})
	# Look for a partner against a shared enemy.
	if w.rng.randf() < 0.05:
		for o in w.countries:
			var oid: int = o["id"]
			if oid == id or not o["alive"] or w.allied(id, oid) or w.at_war(id, oid):
				continue
			for e in enemies:
				if w.at_war(oid, e) and not w.diplomacy.has_pending(id, oid, "alliance"):
					w.submit(id, "diplo.propose_alliance", {"target": oid})
					return


func _answer_proposals() -> void:
	for p in w.proposals.values():
		var to: int = p["to"]
		if not w.countries[to]["ai"] or p.get("seen", false):
			continue
		p["seen"] = true
		var from: int = p["from"]
		var accept := false
		if p["kind"] == "peace":
			var since: int = w.war_since.get(GameWorld.pair_key(from, to), w.tick)
			var long_war := (w.tick - since) > 60 * GameWorld.DAY_TICKS
			accept = w.strength(to) < w.strength(from) * 1.2 or (long_war and w.rng.randf() < 0.5)
		else:
			var shared_enemy := false
			for e in w.enemies_of(to):
				if w.at_war(from, e):
					shared_enemy = true
			accept = shared_enemy or w.rng.randf() < 0.25
		w.submit(to, "diplo.answer", {"proposal": p["id"], "accept": accept})
