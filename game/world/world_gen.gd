class_name WorldGen
extends RefCounted
## Procedural map: noise heightmap -> terrain, spread-out capitals,
## territory grown from capitals with a terrain-weighted flood fill.

const NAMES := ["Valdoria", "Kestrel Union", "Ostmark", "Durnholm", "Seraphine", "Altavia",
	"Brannock", "Corvenia", "Mirelund", "Tessaly", "Halvren", "Pyrrhos"]
const COLORS := ["#3a7bd5", "#d64545", "#3fa34d", "#e0a526", "#8e5bd6", "#2bb3b1",
	"#d16ba5", "#8a9a3a", "#c76b2e", "#5d6fd1", "#9c4a4a", "#4a9c86"]
const LAND_RATIO := 0.6


static func generate(w: GameWorld, settings: Dictionary) -> void:
	w.settings = settings
	var map_seed: int = settings.get("seed", 1)
	var n_countries: int = clampi(settings.get("countries", 6), 2, NAMES.size())
	w.width = settings.get("width", 96)
	w.height = settings.get("height", 64)
	w.rng.seed = map_seed
	_terrain(w, map_seed)
	var capitals := _capitals(w, n_countries)
	_countries(w, capitals)
	_territory(w, capitals)
	for res in ContentDB.list("res"):
		w.market[res["id"].split(":")[1]] = float(res["base_price"])
	w.rebuild_runtime()
	_starting_forces(w)


static func _terrain(w: GameWorld, map_seed: int) -> void:
	var height_noise := FastNoiseLite.new()
	height_noise.seed = map_seed
	height_noise.frequency = 0.035
	height_noise.fractal_octaves = 4
	var moist := FastNoiseLite.new()
	moist.seed = map_seed + 7
	moist.frequency = 0.06
	var n := w.width * w.height
	var elev := PackedFloat32Array()
	elev.resize(n)
	for y in w.height:
		for x in w.width:
			var dx := (float(x) / w.width - 0.5) * 2.0
			var dy := (float(y) / w.height - 0.5) * 2.0
			var d := Vector2(dx, dy).length()
			elev[y * w.width + x] = height_noise.get_noise_2d(x, y) + 0.3 - 0.55 * d * d
	# Percentile thresholds make land ratio stable for any seed.
	var sorted := elev.duplicate()
	sorted.sort()
	var sea: float = sorted[int(n * (1.0 - LAND_RATIO))]
	var hills: float = sorted[int(n * 0.86)]
	var mountain: float = sorted[int(n * 0.95)]
	w.terrain.resize(n)
	w.tile_owner.resize(n)
	w.tile_owner.fill(-1)
	for y in w.height:
		for x in w.width:
			var i := y * w.width + x
			var e := elev[i]
			var t := GameWorld.T_PLAINS
			if e < sea or x == 0 or y == 0 or x == w.width - 1 or y == w.height - 1:
				t = GameWorld.T_WATER
			elif e >= mountain:
				t = GameWorld.T_MOUNTAIN
			elif e >= hills:
				t = GameWorld.T_HILLS
			else:
				var m := moist.get_noise_2d(x, y)
				if m > 0.22:
					t = GameWorld.T_FOREST
				elif m < -0.3:
					t = GameWorld.T_DESERT
			w.terrain[i] = t


static func _capitals(w: GameWorld, count: int) -> Array:
	var land := []
	for y in w.height:
		for x in w.width:
			var t := Vector2i(x, y)
			var ter := w.terrain_at(t)
			if ter == GameWorld.T_PLAINS or ter == GameWorld.T_FOREST:
				land.append(t)
	var caps := [land[w.rng.randi() % land.size()]]
	while caps.size() < count:
		var best := Vector2i(-1, -1)
		var best_d := -1.0
		for _i in 300:
			var c: Vector2i = land[w.rng.randi() % land.size()]
			var md := INF
			for p in caps:
				md = minf(md, Vector2(c).distance_to(Vector2(p)))
			if md > best_d:
				best_d = md
				best = c
		caps.append(best)
	return caps


static func _countries(w: GameWorld, capitals: Array) -> void:
	var names := NAMES.duplicate()
	# Deterministic shuffle with the world RNG.
	for i in range(names.size() - 1, 0, -1):
		var j := w.rng.randi() % (i + 1)
		var tmp = names[i]
		names[i] = names[j]
		names[j] = tmp
	for i in capitals.size():
		w.countries.append({
			"id": i,
			"name": names[i],
			"color": Color(COLORS[i % COLORS.size()]),
			"capital": capitals[i],
			"alive": true,
			"ai": i != w.player_id,
			"money": 2500.0,
			"res": {"food": 120.0, "metal": 80.0, "fuel": 60.0},
			"delta": {},
			"queue": [],
			"starving": false,
			"aggr": w.rng.randf_range(0.4, 1.3),
		})


## Multi-source Dijkstra (bucket queue) over land; cost depends on terrain.
static func _territory(w: GameWorld, capitals: Array) -> void:
	const COST := [0, 2, 3, 5, 8, 3]
	var n := w.width * w.height
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(1 << 30)
	var buckets := {0: []}
	for c in capitals.size():
		var i := w.idx(capitals[c])
		dist[i] = 0
		w.tile_owner[i] = c
		buckets[0].append(i)
	var cur := 0
	var max_cost := 0
	while cur <= max_cost:
		if buckets.has(cur):
			for i in buckets[cur]:
				if dist[i] != cur:
					continue
				var t := Vector2i(i % w.width, i / w.width)
				for d in GameWorld.DIRS4:
					var nt: Vector2i = t + d
					if not w.is_land(nt):
						continue
					var ni := w.idx(nt)
					var nd: int = cur + COST[w.terrain[ni]] + (w.rng.randi() % 2)
					if nd < dist[ni]:
						dist[ni] = nd
						w.tile_owner[ni] = w.tile_owner[i]
						if not buckets.has(nd):
							buckets[nd] = []
						buckets[nd].append(ni)
						max_cost = maxi(max_cost, nd)
			buckets.erase(cur)
		cur += 1


static func _starting_forces(w: GameWorld) -> void:
	for c in w.countries:
		var cap: Vector2i = c["capital"]
		for btype in ["building:FARM", "building:BARRACKS", "building:FARM"]:
			var t := find_free_tile(w, c["id"], cap, ContentDB.find(btype).get("terrain", []))
			if t.x >= 0:
				var id := w.new_id()
				w.buildings[id] = {"id": id, "type": btype, "owner": c["id"], "tile": t,
					"progress": 1.0, "done": true, "hp": ContentDB.num(btype, "hp", 100), "cd": 0}
				w.building_at[t] = id
		for k in 5:
			w.army.spawn_unit(c["id"], "unit:INFANTRY", cap)
		w.army.spawn_unit(c["id"], "unit:TANK", cap)


## Spiral search for an owned, empty land tile matching allowed terrain names.
static func find_free_tile(w: GameWorld, c: int, center: Vector2i, allowed: Array, max_r := 12) -> Vector2i:
	for r in range(1, max_r + 1):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if absi(x) != r and absi(y) != r:
					continue
				var t := center + Vector2i(x, y)
				if not w.is_land(t) or w.owner_at(t) != c or w.building_at.has(t):
					continue
				if not allowed.is_empty() and not GameWorld.TERRAIN_NAMES[w.terrain_at(t)] in allowed:
					continue
				return t
	return Vector2i(-1, -1)
