class_name Economy
extends RefCounted
## Money + resources, construction, recruitment queues, daily production/upkeep, market.

const CAPITAL_INCOME := 40.0
const SELL_RATIO := 0.7
const PRICE_IMPACT := 0.002
const MAX_QUEUE := 10

var w: GameWorld


func _init(world: GameWorld) -> void:
	w = world


func register_commands(bus: CommandBus) -> void:
	bus.register("mil.build", _v_build, _a_build)
	bus.register("mil.demolish", _v_demolish, _a_demolish)
	bus.register("army.recruit", _v_recruit, _a_recruit)
	bus.register("econ.buy", _v_trade, _a_buy)
	bus.register("econ.sell", _v_sell, _a_sell)


# ---------------------------------------------------------------- helpers

static func cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		parts.append(("$%d" % int(cost[k])) if k == "money" else ("%d %s" % [int(cost[k]), k]))
	return ", ".join(parts)


func have(c: Dictionary, key: String) -> float:
	return float(c["money"]) if key == "money" else float(c["res"].get(key, 0.0))


func can_afford(c: Dictionary, cost: Dictionary) -> bool:
	for k in cost:
		if have(c, k) < float(cost[k]):
			return false
	return true


func pay(c: Dictionary, cost: Dictionary, mult := 1.0) -> void:
	for k in cost:
		_add(c, k, -float(cost[k]) * mult)


func _add(c: Dictionary, key: String, amount: float) -> void:
	if key == "money":
		c["money"] = float(c["money"]) + amount
	else:
		c["res"][key] = float(c["res"].get(key, 0.0)) + amount


func has_building(c: int, btype: String) -> bool:
	for b in w.buildings.values():
		if b["owner"] == c and b["type"] == btype and b["done"]:
			return true
	return false


func price(res: String) -> float:
	return float(w.market.get(res, 10.0))


# ---------------------------------------------------------------- commands

func _v_build(cmd: Dictionary) -> String:
	var a: Dictionary = cmd["args"]
	var def: Dictionary = ContentDB.find(str(a.get("type", "")))
	if def.get("category") != "building":
		return "Unknown building"
	var t := Vector2i(int(a.get("x", -1)), int(a.get("y", -1)))
	if not w.is_land(t):
		return "Must build on land"
	if w.owner_at(t) != cmd["by"]:
		return "Must build inside your own territory"
	if w.building_at.has(t):
		return "Tile already has a building"
	var allowed: Array = def.get("terrain", [])
	if not allowed.is_empty() and not GameWorld.TERRAIN_NAMES[w.terrain_at(t)] in allowed:
		return "%s needs terrain: %s" % [def["name"], ", ".join(allowed)]
	if not can_afford(w.countries[cmd["by"]], def.get("cost", {})):
		return "Not enough resources for " + def["name"]
	return ""


func _a_build(cmd: Dictionary) -> void:
	var a: Dictionary = cmd["args"]
	var def: Dictionary = ContentDB.find(a["type"])
	var t := Vector2i(int(a["x"]), int(a["y"]))
	pay(w.countries[cmd["by"]], def.get("cost", {}))
	var id := w.new_id()
	w.buildings[id] = {"id": id, "type": a["type"], "owner": cmd["by"], "tile": t,
		"progress": 0.0, "done": false, "hp": float(def.get("hp", 100)), "cd": 0}
	w.building_at[t] = id


func _v_demolish(cmd: Dictionary) -> String:
	var b = w.buildings.get(int(cmd["args"].get("id", -1)))
	if b == null or b["owner"] != cmd["by"]:
		return "Not your building"
	return ""


func _a_demolish(cmd: Dictionary) -> void:
	w.destroy_building(int(cmd["args"]["id"]))


func _v_recruit(cmd: Dictionary) -> String:
	var def: Dictionary = ContentDB.find(str(cmd["args"].get("type", "")))
	if def.get("category") != "unit":
		return "Unknown unit"
	var c: Dictionary = w.countries[cmd["by"]]
	var req: String = def.get("requires", "")
	if req != "" and not has_building(cmd["by"], req):
		return "%s requires a %s" % [def["name"], ContentDB.find(req).get("name", req)]
	if c["queue"].size() >= MAX_QUEUE:
		return "Recruitment queue is full"
	if not can_afford(c, def.get("cost", {})):
		return "Not enough resources for " + def["name"]
	return ""


func _a_recruit(cmd: Dictionary) -> void:
	var def: Dictionary = ContentDB.find(cmd["args"]["type"])
	var c: Dictionary = w.countries[cmd["by"]]
	pay(c, def.get("cost", {}))
	c["queue"].append({"type": def["id"], "left": int(float(def.get("build_time", 5)) / GameWorld.TICK)})


func _v_trade(cmd: Dictionary) -> String:
	var res: String = str(cmd["args"].get("res", ""))
	var amount := float(cmd["args"].get("amount", 0))
	if not w.market.has(res) or amount <= 0:
		return "Invalid trade"
	if float(w.countries[cmd["by"]]["money"]) < price(res) * amount:
		return "Not enough money"
	return ""


func _v_sell(cmd: Dictionary) -> String:
	var res: String = str(cmd["args"].get("res", ""))
	var amount := float(cmd["args"].get("amount", 0))
	if not w.market.has(res) or amount <= 0:
		return "Invalid trade"
	if have(w.countries[cmd["by"]], res) < amount:
		return "Not enough " + res
	return ""


func _a_buy(cmd: Dictionary) -> void:
	var res: String = cmd["args"]["res"]
	var amount := float(cmd["args"]["amount"])
	var c: Dictionary = w.countries[cmd["by"]]
	_add(c, "money", -price(res) * amount)
	_add(c, res, amount)
	w.market[res] = price(res) * (1.0 + PRICE_IMPACT * amount)


func _a_sell(cmd: Dictionary) -> void:
	var res: String = cmd["args"]["res"]
	var amount := float(cmd["args"]["amount"])
	var c: Dictionary = w.countries[cmd["by"]]
	_add(c, res, -amount)
	_add(c, "money", price(res) * amount * SELL_RATIO)
	w.market[res] = maxf(1.0, price(res) * (1.0 - PRICE_IMPACT * amount))


# ---------------------------------------------------------------- simulation

func update() -> void:
	for b in w.buildings.values():
		if not b["done"]:
			b["progress"] = float(b["progress"]) + GameWorld.TICK / maxf(0.1, ContentDB.num(b["type"], "build_time", 5))
			if b["progress"] >= 1.0:
				b["progress"] = 1.0
				b["done"] = true
				if b["owner"] == w.player_id:
					w.notify("%s completed" % ContentDB.find(b["type"]).get("name", "Building"), w.player_id)
	for c in w.countries:
		if not c["alive"] or c["queue"].is_empty():
			continue
		var q: Dictionary = c["queue"][0]
		q["left"] = int(q["left"]) - 1
		if q["left"] <= 0:
			c["queue"].pop_front()
			w.army.spawn_unit(c["id"], q["type"], _spawn_tile(c, q["type"]))
	if w.tick > 0 and w.tick % GameWorld.DAY_TICKS == 0:
		_daily()


func _spawn_tile(c: Dictionary, utype: String) -> Vector2i:
	var req: String = ContentDB.find(utype).get("requires", "")
	var options := []
	for b in w.buildings.values():
		if b["owner"] == c["id"] and b["type"] == req and b["done"]:
			options.append(b["tile"])
	if options.is_empty():
		return c["capital"]
	return options[w.rng.randi() % options.size()]


func _daily() -> void:
	var delta := {}
	for c in w.countries:
		if c["alive"]:
			delta[c["id"]] = {"money": CAPITAL_INCOME}
	for b in w.buildings.values():
		if not b["done"] or not delta.has(b["owner"]):
			continue
		var def: Dictionary = ContentDB.find(b["type"])
		_accumulate(delta[b["owner"]], def.get("produces", {}), 1.0)
		_accumulate(delta[b["owner"]], def.get("upkeep", {}), -1.0)
	for u in w.units.values():
		if delta.has(u["owner"]):
			_accumulate(delta[u["owner"]], ContentDB.find(u["type"]).get("upkeep", {}), -1.0)
	for id in delta:
		var c: Dictionary = w.countries[id]
		for k in delta[id]:
			_add(c, k, delta[id][k])
		var food: float = c["res"].get("food", 0.0)
		c["starving"] = food < 0.0
		if food < 0.0:
			c["res"]["food"] = 0.0
			if id == w.player_id and w.day() % 5 == 0:
				w.notify("Food shortage! Your troops are losing strength. Build farms or buy food.", id)
		c["delta"] = delta[id]
	# Prices drift back toward base.
	for res in ContentDB.list("res"):
		var key: String = res["id"].split(":")[1]
		w.market[key] = lerpf(price(key), float(res["base_price"]), 0.05)


func _accumulate(into: Dictionary, src: Dictionary, mult: float) -> void:
	for k in src:
		into[k] = float(into.get(k, 0.0)) + float(src[k]) * mult
