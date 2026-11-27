class_name SaveGame
extends RefCounted
## Whole-state snapshot via store_var (keeps Vector2/Color/packed arrays intact).

const DEFAULT_PATH := "user://savegame.dat"


static func save(w: GameWorld, path := DEFAULT_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(w.to_dict())
	return true


static func exists(path := DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)


static func load_world(path := DEFAULT_PATH) -> GameWorld:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d = f.get_var()
	if not d is Dictionary or int(d.get("version", 0)) != GameWorld.SAVE_VERSION:
		return null
	return GameWorld.from_dict(d)
