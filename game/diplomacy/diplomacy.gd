class_name Diplomacy
extends RefCounted
## War, peace and alliances. Offers are stored as proposals and answered with
## another command, so the AI and the player use exactly the same flow.

const PROPOSAL_DAYS := 15

var w: GameWorld


func _init(world: GameWorld) -> void:
	w = world


func register_commands(bus: CommandBus) -> void:
	bus.register("diplo.declare_war", _v_war, _a_war)
	bus.register("diplo.propose_peace", _v_peace, _a_propose.bind("peace"))
	bus.register("diplo.propose_alliance", _v_alliance, _a_propose.bind("alliance"))
	bus.register("diplo.answer", _v_answer, _a_answer)
	bus.register("diplo.break_alliance", _v_break, _a_break)


func _target(cmd: Dictionary) -> int:
	return int(cmd["args"].get("target", -1))


func _valid_target(cmd: Dictionary) -> String:
	var t := _target(cmd)
	if t < 0 or t >= w.countries.size() or not w.countries[t]["alive"] or t == cmd["by"]:
		return "Invalid country"
	return ""


func has_pending(from: int, to: int, kind: String) -> bool:
	for p in w.proposals.values():
		if p["from"] == from and p["to"] == to and p["kind"] == kind:
			return true
	return false


func _v_war(cmd: Dictionary) -> String:
	var err := _valid_target(cmd)
	if err != "":
		return err
	if w.at_war(cmd["by"], _target(cmd)):
		return "Already at war"
	if w.allied(cmd["by"], _target(cmd)):
		return "Break the alliance first"
	return ""


func _a_war(cmd: Dictionary) -> void:
	var a: int = cmd["by"]
	var b := _target(cmd)
	w.set_relation(a, b, "war")
	w.notify("%s declared war on %s!" % [w.cname(a), w.cname(b)])
	# Defensive alliances: the victim's allies join in.
	for o in w.countries:
		var id: int = o["id"]
		if o["alive"] and id != a and w.allied(id, b) and not w.allied(id, a) and not w.at_war(id, a):
			w.set_relation(id, a, "war")
			w.notify("%s joins the war to defend %s" % [w.cname(id), w.cname(b)])


func _v_peace(cmd: Dictionary) -> String:
	var err := _valid_target(cmd)
	if err != "":
		return err
	if not w.at_war(cmd["by"], _target(cmd)):
		return "Not at war"
	if has_pending(cmd["by"], _target(cmd), "peace"):
		return "Offer already sent"
	return ""


func _v_alliance(cmd: Dictionary) -> String:
	var err := _valid_target(cmd)
	if err != "":
		return err
	if w.at_war(cmd["by"], _target(cmd)) or w.allied(cmd["by"], _target(cmd)):
		return "Alliance not possible"
	if has_pending(cmd["by"], _target(cmd), "alliance"):
		return "Offer already sent"
	return ""


func _a_propose(cmd: Dictionary, kind: String) -> void:
	var id := w.new_id()
	var to := _target(cmd)
	w.proposals[id] = {"id": id, "kind": kind, "from": cmd["by"], "to": to,
		"expires": w.tick + PROPOSAL_DAYS * GameWorld.DAY_TICKS}
	if to == w.player_id:
		w.notify("%s offers %s" % [w.cname(cmd["by"]), "peace" if kind == "peace" else "an alliance"], w.player_id)


func _v_answer(cmd: Dictionary) -> String:
	var p = w.proposals.get(int(cmd["args"].get("proposal", -1)))
	if p == null or p["to"] != cmd["by"]:
		return "Offer no longer available"
	return ""


func _a_answer(cmd: Dictionary) -> void:
	var p: Dictionary = w.proposals[int(cmd["args"]["proposal"])]
	w.proposals.erase(p["id"])
	var ok: bool = cmd["args"].get("accept", false)
	var a: int = p["from"]
	var b: int = p["to"]
	if not ok:
		if a == w.player_id:
			w.notify("%s rejected your %s offer" % [w.cname(b), p["kind"]], w.player_id)
		return
	if p["kind"] == "peace" and w.at_war(a, b):
		w.set_relation(a, b, "")
		w.notify("Peace signed between %s and %s" % [w.cname(a), w.cname(b)])
	elif p["kind"] == "alliance" and not w.at_war(a, b):
		w.set_relation(a, b, "ally")
		w.notify("%s and %s formed an alliance" % [w.cname(a), w.cname(b)])


func _v_break(cmd: Dictionary) -> String:
	var err := _valid_target(cmd)
	if err != "":
		return err
	return "" if w.allied(cmd["by"], _target(cmd)) else "Not allied"


func _a_break(cmd: Dictionary) -> void:
	w.set_relation(cmd["by"], _target(cmd), "")
	w.notify("%s left its alliance with %s" % [w.cname(cmd["by"]), w.cname(_target(cmd))])


func update() -> void:
	for p in w.proposals.values():
		if w.tick >= p["expires"]:
			w.proposals.erase(p["id"])
