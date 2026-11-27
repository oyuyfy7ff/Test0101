class_name CommandBus
extends RefCounted
## Every player/AI action is a command: {"cmd": "domain.action", "by": country_id, "args": {...}}.
## Commands are queued and applied at the start of the next simulation tick, in order.
## The UI and the AI never change world state directly, which keeps the simulation
## deterministic and makes replays / lockstep multiplayer possible later.

signal rejected(cmd: Dictionary, reason: String)
signal applied(cmd: Dictionary)

var handlers := {}
var queue: Array = []
var history: Array = []
var keep_history := true


func register(name: String, validate: Callable, apply: Callable) -> void:
	handlers[name] = {"validate": validate, "apply": apply}


func submit(cmd: Dictionary) -> void:
	queue.append(cmd)


func process(world: GameWorld) -> void:
	var batch := queue
	queue = []
	for cmd in batch:
		var h = handlers.get(cmd.get("cmd", ""))
		if h == null:
			rejected.emit(cmd, "Unknown command " + str(cmd.get("cmd")))
			continue
		var by: int = int(cmd.get("by", -1))
		if by < 0 or by >= world.countries.size() or not world.countries[by]["alive"]:
			rejected.emit(cmd, "Invalid issuer")
			continue
		if not cmd.has("args"):
			cmd["args"] = {}
		var err: String = h["validate"].call(cmd)
		if err != "":
			rejected.emit(cmd, err)
			continue
		h["apply"].call(cmd)
		cmd["tick"] = world.tick
		if keep_history:
			history.append(cmd)
		applied.emit(cmd)


func clear() -> void:
	handlers.clear()
	queue.clear()
