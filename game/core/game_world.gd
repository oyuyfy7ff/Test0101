class_name GameWorld
extends RefCounted
## The whole simulation state plus the fixed-step loop.
## Saved state = plain Dictionaries/Arrays (see to_dict). Runtime caches
## (pathfinding grid, building lookup, fx) are rebuilt after load.

signal territory_changed
signal notified(text: String, country: int)
signal ended(result: String)

const TICK := 0.1            # seconds of game time per simulation step
const DAY_TICKS := 20        # 1 in-game day = 2 seconds at 1x speed
const SAVE_VERSION := 1

const T_WATER := 0
const T_PLAINS := 1
const T_FOREST := 2
const T_HILLS := 3
const T_MOUNTAIN := 4
const T_DESERT := 5
const TERRAIN_NAMES := ["water", "plains", "forest", "hills", "mountain", "desert"]
const MOVE_MULT := [0.0, 1.0, 0.7, 0.6, 0.4, 0.85]
const DEFENSE_MULT := [1.0, 1.0, 1.2, 1.3, 1.6, 0.9]
const PATH_WEIGHT := [1.0, 1.0, 1.4, 1.7, 2.5, 1.2]
const DIRS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# ---- saved state ----
var settings := {}
var width := 0
var height := 0
var terrain := PackedByteArray()
var tile_owner := PackedInt32Array()
var countries: Array = []      # Array of Dictionary
var buildings := {}            # id -> Dictionary
var units := {}                # id -> Dictionary
var strikes := {}              # id -> Dictionary (drones/missiles in flight)
var proposals := {}            # id -> Dictionary (diplomatic offers)
var relations := {}            # "a:b" -> "war" | "ally"
var war_since := {}            # "a:b" -> tick
var market := {}               # res name -> current price
var next_id := 1
var tick := 0
var player_id := 0
var result := ""
var rng := RandomNumberGenerator.new()

# ---- runtime only ----
var fx: Array = []
var astar := AStarGrid2D.new()
var building_at := {}          # Vector2i -> building id
var territory_dirty := false
var bus := CommandBus.new()
var economy: Economy
var army: Army
var strike_sys: Strikes
var diplomacy: Diplomacy
var ai: AiBots


func _init() -> void:
	economy = Economy.new(self)
	army = Army.new(self)
	strike_sys = Strikes.new(self)
	diplomacy = Diplomacy.new(self)
	ai = AiBots.new(self)
	economy.register_commands(bus)
	army.register_commands(bus)
	strike_sys.register_commands(bus)
	diplomacy.register_commands(bus)


## Breaks reference cycles (systems hold the world) so the old world is freed.
func dispose() -> void:
	bus.clear()
	economy = null
	army = null
	strike_sys = null
	diplomacy = null
	ai = null


# ---------------------------------------------------------------- loop

func step() -> void:
	if result != "":
		return
	bus.process(self)
	ai.update()
	economy.update()
	army.update()
	strike_sys.update()
	diplomacy.update()
	_update_fx()
	tick += 1
	_check_end()
	if territory_dirty:
		territory_dirty = false
		territory_changed.emit()


func submit(by: int, cmd: String, args := {}) -> void:
	bus.submit({"cmd": cmd, "by": by, "args": args})


func day() -> int:
	return tick / DAY_TICKS


# ---------------------------------------------------------------- map helpers

func idx(t: Vector2i) -> int:
	return t.y * width + t.x


func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < width and t.y < height


func terrain_at(t: Vector2i) -> int:
	return terrain[idx(t)] if in_bounds(t) else T_WATER


func is_land(t: Vector2i) -> bool:
	return in_bounds(t) and terrain[idx(t)] != T_WATER


func owner_at(t: Vector2i) -> int:
	return tile_owner[idx(t)] if in_bounds(t) else -1


static func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(p.floor())


static func center_of(t: Vector2i) -> Vector2:
	return Vector2(t) + Vector2(0.5, 0.5)


func new_id() -> int:
	next_id += 1
	return next_id - 1


func notify(text: String, country := -1) -> void:
	notified.emit(text, country)


func cname(c: int) -> String:
	return countries[c]["name"] if c >= 0 and c < countries.size() else "Nobody"


# ---------------------------------------------------------------- relations

static func pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


func at_war(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a == b:
		return false
	return relations.get(pair_key(a, b), "") == "war"


func allied(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a == b:
		return false
	return relations.get(pair_key(a, b), "") == "ally"


func set_relation(a: int, b: int, value: String) -> void:
	var k := pair_key(a, b)
	if value == "":
		relations.erase(k)
		war_since.erase(k)
	else:
		relations[k] = value
		if value == "war":
			war_since[k] = tick
		else:
			war_since.erase(k)
	territory_dirty = true   # front-line colours change


func enemies_of(c: int) -> Array:
	var out := []
	for o in countries:
		if o["alive"] and at_war(c, o["id"]):
			out.append(o["id"])
	return out


## Units may enter own, allied, enemy (at war) and unclaimed land.
func can_enter(c: int, t: Vector2i) -> bool:
	if not is_land(t):
		return false
	var o := owner_at(t)
	return o == -1 or o == c or at_war(c, o) or allied(c, o)


func strength(c: int) -> float:
	var s := 0.0
	for u in units.values():
		if u["owner"] == c:
			s += float(u["hp"]) * ContentDB.num(u["type"], "attack") / 100.0
	return s


# ---------------------------------------------------------------- territory

func set_tile_owner(t: Vector2i, c: int) -> void:
	var i := idx(t)
	var old := tile_owner[i]
	if old == c:
		return
	tile_owner[i] = c
	territory_dirty = true
	if building_at.has(t):
		var b: Dictionary = buildings[building_at[t]]
		b["owner"] = c
		if old == player_id or c == player_id:
			notify("%s captured a %s from %s" % [cname(c), ContentDB.find(b["type"]).get("name", "building"), cname(old)], player_id)
	if old >= 0 and countries[old]["alive"] and countries[old]["capital"] == t:
		eliminate(old, c)


func eliminate(c: int, by: int) -> void:
	var country: Dictionary = countries[c]
	country["alive"] = false
	country["queue"] = []
	for i in tile_owner.size():
		if tile_owner[i] == c:
			tile_owner[i] = by
	for b in buildings.values():
		if b["owner"] == c:
			b["owner"] = by
	for u in units.values():
		if u["owner"] == c:
			units.erase(u["id"])
	for o in countries:
		if o["id"] != c:
			relations.erase(pair_key(c, o["id"]))
			war_since.erase(pair_key(c, o["id"]))
	for p in proposals.values():
		if p["from"] == c or p["to"] == c:
			proposals.erase(p["id"])
	territory_dirty = true
	notify("%s has fallen. Its capital was taken by %s." % [cname(c), cname(by)])


func destroy_building(id: int) -> void:
	var b = buildings.get(id)
	if b == null:
		return
	building_at.erase(b["tile"])
	buildings.erase(id)
	add_fx("blast", center_of(b["tile"]), Vector2.ZERO, 1.0, 10)


func add_fx(kind: String, pos: Vector2, to := Vector2.ZERO, radius := 1.0, ttl := 6) -> void:
	if fx.size() > 400:
		return
	fx.append({"kind": kind, "pos": pos, "to": to, "radius": radius, "ttl": ttl, "max": ttl})


func _update_fx() -> void:
	var keep := []
	for f in fx:
		f["ttl"] -= 1
		if f["ttl"] > 0:
			keep.append(f)
	fx = keep


func _check_end() -> void:
	if not countries[player_id]["alive"]:
		_end("defeat")
		return
	for c in countries:
		if c["alive"] and c["id"] != player_id and not allied(c["id"], player_id):
			return
	_end("victory")


func _end(r: String) -> void:
	result = r
	ended.emit(r)


# ---------------------------------------------------------------- runtime caches

func rebuild_runtime() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in height:
		for x in width:
			var t := Vector2i(x, y)
			var ter := terrain[idx(t)]
			if ter == T_WATER:
				astar.set_point_solid(t, true)
			else:
				astar.set_point_weight_scale(t, PATH_WEIGHT[ter])
	building_at.clear()
	for b in buildings.values():
		building_at[b["tile"]] = b["id"]
	territory_dirty = true


# ---------------------------------------------------------------- save / load

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"settings": settings.duplicate(true),
		"width": width, "height": height,
		"terrain": terrain, "tile_owner": tile_owner,
		"countries": countries.duplicate(true),
		"buildings": buildings.duplicate(true),
		"units": units.duplicate(true),
		"strikes": strikes.duplicate(true),
		"proposals": proposals.duplicate(true),
		"relations": relations.duplicate(),
		"war_since": war_since.duplicate(),
		"market": market.duplicate(),
		"next_id": next_id, "tick": tick, "player_id": player_id, "result": result,
		"rng_seed": rng.seed, "rng_state": rng.state,
		"history": bus.history.duplicate(true),
	}


static func from_dict(d: Dictionary) -> GameWorld:
	var w := GameWorld.new()
	w.settings = d["settings"]
	w.width = d["width"]
	w.height = d["height"]
	w.terrain = d["terrain"]
	w.tile_owner = d["tile_owner"]
	w.countries = d["countries"]
	w.buildings = d["buildings"]
	w.units = d["units"]
	w.strikes = d["strikes"]
	w.proposals = d["proposals"]
	w.relations = d["relations"]
	w.war_since = d["war_since"]
	w.market = d["market"]
	w.next_id = d["next_id"]
	w.tick = d["tick"]
	w.player_id = d["player_id"]
	w.result = d["result"]
	w.rng.seed = d["rng_seed"]
	w.rng.state = d["rng_state"]
	w.bus.history = d.get("history", [])
	w.rebuild_runtime()
	return w
