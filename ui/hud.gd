class_name Hud
extends CanvasLayer
## In-game UI built in code: top resource bar, tabbed side panel
## (Build / Army / Strike / Diplomacy / Market), notifications, tile info.
## Every button submits a command; the HUD never edits world state itself.

signal speed_requested(speed: int)
signal save_requested
signal load_requested
signal new_game_requested

var world: GameWorld
var view: MapView

var root := Control.new()
var flag := ColorRect.new()
var name_label := Label.new()
var res_label := Label.new()
var speed_label := Label.new()
var mode_label := Label.new()
var info_label := Label.new()
var notif_box := VBoxContainer.new()
var army_label := Label.new()
var strike_label := Label.new()
var dip_box := VBoxContainer.new()
var price_labels := {}
var end_panel := PanelContainer.new()
var end_label := Label.new()
var refresh_t := 0.0
var dip_sig := ""


func _ready() -> void:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top_bar()
	_build_side_panel()
	notif_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	notif_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	notif_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	notif_box.alignment = BoxContainer.ALIGNMENT_END
	notif_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notif_box)
	info_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	info_label.add_theme_constant_override("outline_size", 4)
	root.add_child(info_label)
	_build_end_panel()


# ---------------------------------------------------------------- layout

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.12, 0.9)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	return sb


func _button(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	flag.custom_minimum_size = Vector2(22, 16)
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(flag)
	row.add_child(name_label)
	res_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(res_label)
	row.add_child(speed_label)
	for s in [0, 1, 2, 4]:
		row.add_child(_button("||" if s == 0 else "%dx" % s, speed_requested.emit.bind(s), "Space = pause"))
	row.add_child(_button("Save", save_requested.emit, "F5"))
	row.add_child(_button("Load", load_requested.emit, "F9"))
	row.add_child(_button("New", new_game_requested.emit))


func _scroll_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func _build_side_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.position = Vector2(8, 52)
	panel.custom_minimum_size = Vector2(300, 470)
	root.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_label.add_theme_color_override("font_color", Color("#ffd84a"))
	col.add_child(mode_label)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tabs)

	var build := _scroll_tab(tabs, "Build")
	for def in ContentDB.list("building"):
		var tip := _def_tooltip(def)
		build.add_child(_button("%s  (%s)" % [def["name"], Economy.cost_text(def.get("cost", {}))], _on_build.bind(def["id"]), tip))
	var hint := Label.new()
	hint.text = "Click a tile in your territory. Shift+click to place several."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.6)
	build.add_child(hint)

	var army := _scroll_tab(tabs, "Army")
	army_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	army.add_child(army_label)
	for def in ContentDB.list("unit"):
		army.add_child(_button("Recruit %s  (%s)" % [def["name"], Economy.cost_text(def.get("cost", {}))], _on_recruit.bind(def["id"]), _def_tooltip(def)))
	army.add_child(HSeparator.new())
	army.add_child(_button("Select all units", func(): view.select_all()))
	army.add_child(_button("Hold position", _on_selected_cmd.bind("army.order_hold")))
	army.add_child(_button("Disband selected", _on_selected_cmd.bind("army.disband")))
	var help := Label.new()
	help.text = "Drag to box-select. Right-click to move / attack. Units fight automatically and capture enemy tiles. Taking a capital defeats that country."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.6)
	army.add_child(help)

	var strike := _scroll_tab(tabs, "Strike")
	strike_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	strike.add_child(strike_label)
	for def in ContentDB.list("strike"):
		strike.add_child(_button("Launch %s  (%s)" % [def["name"], Economy.cost_text(def.get("cost", {}))], _on_launch.bind(def["id"]), _def_tooltip(def)))

	var dip := _scroll_tab(tabs, "Diplomacy")
	dip.add_child(dip_box)
	dip_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var market := _scroll_tab(tabs, "Market")
	for def in ContentDB.list("res"):
		var key: String = def["id"].split(":")[1]
		var row := HBoxContainer.new()
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		price_labels[key] = l
		row.add_child(_button("Buy 10", _on_trade.bind("econ.buy", key)))
		row.add_child(_button("Sell 10", _on_trade.bind("econ.sell", key)))
		market.add_child(row)


func _def_tooltip(def: Dictionary) -> String:
	var lines := [def.get("name", "")]
	for k in ["hp", "attack", "range", "speed", "build_time", "damage", "radius"]:
		if def.has(k):
			lines.append("%s: %s" % [k, def[k]])
	for k in ["produces", "upkeep"]:
		if def.has(k):
			lines.append("%s/day: %s" % [k, Economy.cost_text(def[k])])
	if def.has("terrain"):
		lines.append("terrain: " + ", ".join(def["terrain"]))
	if def.has("requires"):
		lines.append("requires: " + ContentDB.find(def["requires"]).get("name", def["requires"]))
	if def.has("launcher"):
		lines.append("launched from: " + ContentDB.find(def["launcher"]).get("name", def["launcher"]))
	return "\n".join(lines)


func _build_end_panel() -> void:
	end_panel.add_theme_stylebox_override("panel", _panel_style())
	end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	end_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	end_panel.visible = false
	root.add_child(end_panel)
	var box := VBoxContainer.new()
	end_panel.add_child(box)
	end_label.add_theme_font_size_override("font_size", 32)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(end_label)
	box.add_child(_button("New game", new_game_requested.emit))


# ---------------------------------------------------------------- world binding

func set_world(w: GameWorld, v: MapView) -> void:
	world = w
	view = v
	if not v.tile_hovered.is_connected(_on_hover):
		v.tile_hovered.connect(_on_hover)
		v.mode_changed.connect(_on_mode)
	end_panel.visible = false
	dip_sig = ""
	for c in notif_box.get_children():
		c.queue_free()
	var me: Dictionary = w.countries[w.player_id]
	flag.color = me["color"]
	name_label.text = me["name"]
	_on_mode("select", "")
	_refresh()


func set_speed(s: int) -> void:
	speed_label.text = "PAUSED" if s == 0 else "Speed %dx" % s


func on_notify(text: String, country := -1) -> void:
	if world != null and country != -1 and country != world.player_id:
		return
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	notif_box.add_child(l)
	while notif_box.get_child_count() > 7:
		var old := notif_box.get_child(0)
		notif_box.remove_child(old)
		old.queue_free()
	get_tree().create_timer(7.0).timeout.connect(_expire_label.bind(l))


func _expire_label(l) -> void:
	if is_instance_valid(l):
		l.queue_free()


func show_end(result: String) -> void:
	end_label.text = "VICTORY" if result == "victory" else "DEFEAT"
	end_panel.visible = true


func _process(delta: float) -> void:
	refresh_t += delta
	if refresh_t >= 0.2:
		refresh_t = 0.0
		_refresh()


func _refresh() -> void:
	if world == null:
		return
	var me: Dictionary = world.countries[world.player_id]
	var d: Dictionary = me["delta"]
	var parts := ["$ %d (%+d/day)" % [int(me["money"]), int(d.get("money", 0))]]
	for k in ["food", "metal", "fuel"]:
		parts.append("%s %d (%+.1f)" % [k.capitalize(), int(me["res"].get(k, 0)), float(d.get(k, 0))])
	parts.append("Day %d" % world.day())
	if me["starving"]:
		parts.append("STARVING")
	res_label.text = "   ".join(parts)

	var q := []
	for item in me["queue"]:
		q.append(ContentDB.find(item["type"]).get("name", "?"))
	army_label.text = "Units: %d   Selected: %d\nQueue: %s" % [world.army.units_of(world.player_id).size(), view.selected.size(), ", ".join(q) if not q.is_empty() else "empty"]

	var s := []
	for def in ContentDB.list("strike"):
		s.append("%s ready: %d" % [def["name"], world.strike_sys.ready_launchers(world.player_id, def)])
	s.append("Strikes need a war target and a launcher building in range.")
	strike_label.text = "\n".join(s)

	for key in price_labels:
		price_labels[key].text = "%s  $%.1f  (have %d)" % [key.capitalize(), world.economy.price(key), int(me["res"].get(key, 0))]

	var sig := str(world.relations) + str(world.proposals.keys())
	for c in world.countries:
		sig += str(c["alive"])
	if sig != dip_sig:
		dip_sig = sig
		_rebuild_diplomacy()
	else:
		_update_strengths()


func _rebuild_diplomacy() -> void:
	for c in dip_box.get_children():
		c.queue_free()
	var me := world.player_id
	for p in world.proposals.values():
		if p["to"] != me:
			continue
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s offers %s" % [world.cname(p["from"]), p["kind"]]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_button("Accept", _on_answer.bind(p["id"], true)))
		row.add_child(_button("Decline", _on_answer.bind(p["id"], false)))
		dip_box.add_child(row)
	for c in world.countries:
		var id: int = c["id"]
		if id == me or not c["alive"]:
			continue
		var box := VBoxContainer.new()
		var head := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = c["color"]
		sw.custom_minimum_size = Vector2(14, 14)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(sw)
		var l := Label.new()
		l.name = "Info"
		l.set_meta("country", id)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(l)
		box.add_child(head)
		var btns := HBoxContainer.new()
		if world.at_war(me, id):
			btns.add_child(_button("Offer peace", _on_dip.bind("diplo.propose_peace", id)))
		elif world.allied(me, id):
			btns.add_child(_button("Break alliance", _on_dip.bind("diplo.break_alliance", id)))
		else:
			btns.add_child(_button("Declare war", _on_dip.bind("diplo.declare_war", id)))
			btns.add_child(_button("Offer alliance", _on_dip.bind("diplo.propose_alliance", id)))
		box.add_child(btns)
		box.add_child(HSeparator.new())
		dip_box.add_child(box)
	_update_strengths.call_deferred()


func _update_strengths() -> void:
	var me := world.player_id
	var mine := world.strength(me)
	for box in dip_box.get_children():
		if box.is_queued_for_deletion() or box.get_child_count() == 0:
			continue
		var l := box.get_child(0).get_node_or_null("Info") as Label
		if l == null:
			continue
		var id: int = l.get_meta("country")
		var status := "WAR" if world.at_war(me, id) else ("Ally" if world.allied(me, id) else "Peace")
		l.text = "%s  [%s]  army %d vs yours %d" % [world.cname(id), status, int(world.strength(id)), int(mine)]


# ---------------------------------------------------------------- handlers

func _on_build(id: String) -> void:
	view.set_mode("build", id)


func _on_launch(id: String) -> void:
	view.set_mode("launch", id)


func _on_recruit(id: String) -> void:
	world.submit(world.player_id, "army.recruit", {"type": id})


func _on_selected_cmd(cmd: String) -> void:
	world.submit(world.player_id, cmd, {"ids": view.selected.duplicate()})


func _on_trade(cmd: String, res: String) -> void:
	world.submit(world.player_id, cmd, {"res": res, "amount": 10})


func _on_dip(cmd: String, target: int) -> void:
	world.submit(world.player_id, cmd, {"target": target})


func _on_answer(proposal: int, accept: bool) -> void:
	world.submit(world.player_id, "diplo.answer", {"proposal": proposal, "accept": accept})


func _on_mode(mode: String, mtype: String) -> void:
	match mode:
		"build":
			mode_label.text = "Placing %s: left-click a tile, right-click / Esc to cancel" % ContentDB.find(mtype).get("name", mtype)
		"launch":
			mode_label.text = "Target %s: left-click enemy territory, right-click / Esc to cancel" % ContentDB.find(mtype).get("name", mtype)
		_:
			mode_label.text = ""
	mode_label.visible = mode_label.text != ""


func _on_hover(t: Vector2i) -> void:
	if world == null or not world.in_bounds(t):
		info_label.text = ""
		return
	var text: String = "(%d, %d)  %s" % [t.x, t.y, GameWorld.TERRAIN_NAMES[world.terrain_at(t)]]
	var o := world.owner_at(t)
	if o >= 0:
		text += "  |  " + world.cname(o)
	if world.building_at.has(t):
		var b: Dictionary = world.buildings[world.building_at[t]]
		text += "  |  " + ContentDB.find(b["type"]).get("name", "?")
		if not b["done"]:
			text += " (%d%%)" % int(float(b["progress"]) * 100)
	info_label.text = text
