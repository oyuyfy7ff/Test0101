extends Node
## Autoload "ContentDB": loads every JSON definition under res://content.
## IDs use the form "category:NAME" (building:FARM, unit:TANK, strike:DRONE, res:food).
## content/overrides/overrides.json patches definitions after loading (balance / mods).

const ROOT := "res://content"
const FOLDERS := ["resources", "buildings", "units", "strikes"]

var defs := {}
var by_cat := {}


func _init() -> void:
	reload()


func reload() -> void:
	defs.clear()
	by_cat.clear()
	for sub in FOLDERS:
		_load_dir(ROOT + "/" + sub)
	_apply_overrides(ROOT + "/overrides/overrides.json")
	for id in defs:
		var def: Dictionary = defs[id]
		var cat: String = def["category"]
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(def)
	for cat in by_cat:
		by_cat[cat].sort_custom(func(a, b): return float(a.get("order", 99)) < float(b.get("order", 99)))


func find(id: String) -> Dictionary:
	return defs.get(id, {})


func list(category: String) -> Array:
	return by_cat.get(category, [])


func num(id: String, key: String, default := 0.0) -> float:
	return float(find(id).get(key, default))


func _load_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("ContentDB: missing folder " + path)
		return
	for f in dir.get_files():
		if f.ends_with(".json"):
			_load_file(path + "/" + f)
	for sub in dir.get_directories():
		_load_dir(path + "/" + sub)


func _load_file(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		_add(data, path)
	elif data is Array:
		for d in data:
			if d is Dictionary:
				_add(d, path)
	else:
		push_error("ContentDB: cannot parse " + path)


func _add(def: Dictionary, path: String) -> void:
	var id: String = def.get("id", "")
	if not id.contains(":"):
		push_error("ContentDB: entry without 'category:NAME' id in " + path)
		return
	def["category"] = id.split(":")[0]
	defs[id] = def


func _apply_overrides(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return
	for id in data:
		if not defs.has(id) or not data[id] is Dictionary:
			continue
		var def: Dictionary = defs[id]
		var patch: Dictionary = data[id]
		for k in patch:
			if patch[k] is Dictionary and def.get(k) is Dictionary:
				def[k].merge(patch[k], true)
			else:
				def[k] = patch[k]
