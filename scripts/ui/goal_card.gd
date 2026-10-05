class_name GoalCard
extends PanelContainer
## Einfuehrung und Ziele (Etappe 4). Zeigt oben links den naechsten Schritt bzw. das
## naechste Ziel, prueft es regelmaessig und verteilt Belohnungen. Waehrend der
## Einfuehrung zeigt ein huepfender Pfeil auf den passenden Knopf.
## Daten: data/goals.json, Zustand: Game.goals {tut, ms}.

var hud  # Hud
var _head: Label
var _text: Label
var _hint: Label
var _bar: ProgressBar
var _skip: Button
var _pointer: TextureRect
var _tick: float = 0.0
var _cur_id: String = ""
var _actions: Array = []  # Aktionen seit Beginn des aktuellen Schritts
var _bob: float = 0.0


func setup(p_hud) -> void:
	hud = p_hud
	mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	add_child(h)
	var ic := UiTheme.icon_rect(Data.icon("ziel"), 22)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var hr := HBoxContainer.new()
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(hr)
	_head = UiTheme.label("", 12, Color("#8a5a3a"), true)
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(_head)
	_skip = UiTheme.button("Überspringen", "", 22)
	_skip.add_theme_font_size_override("font_size", 11)
	_skip.tooltip_text = "Einführung überspringen"
	_skip.pressed.connect(_skip_tutorial)
	hr.add_child(_skip)
	var close := UiTheme.button("", "abriss", 22)
	close.tooltip_text = "Ziel ausblenden, bis das nächste kommt"
	close.pressed.connect(_dismiss)
	hr.add_child(close)
	_text = UiTheme.label("", 14, UiTheme.TEXT, true)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 170
	v.add_child(_text)
	_bar = UiTheme.bar(UiTheme.GOOD, 6)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_bar)
	_hint = UiTheme.label("", 12)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 170
	_hint.visible = false
	v.add_child(_hint)
	tooltip_text = "Tippen: Erklärung ein- und ausblenden"
	gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_hint.visible = not _hint.visible and _hint.text != ""
			Sound.play("auf" if _hint.visible else "zu")
			_relayout())
	Game.player_action.connect(func(kind, what): _actions.append([kind, what]))
	_pointer = TextureRect.new()
	_pointer.texture = Data.icon("zeiger")
	_pointer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pointer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pointer.size = Vector2(30, 30)
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.visible = false


## Der Zeiger muss ueber allem liegen: nach dem Aufbau der Oberflaeche einhaengen.
func attach_pointer(parent: Control) -> void:
	parent.add_child(_pointer)


func _relayout() -> void:
	reset_size()
	if hud:
		hud._layout()


func in_tutorial() -> bool:
	return int(Game.goals.get("tut", 0)) < Data.goals.get("tutorial", []).size()


# ---------------------------------------------------------------- Ziele
func current() -> Dictionary:
	var tut: Array = Data.goals.get("tutorial", [])
	var t := int(Game.goals.get("tut", 0))
	if t < tut.size():
		return tut[t]
	return milestone(int(Game.goals.get("ms", 0)))


## Feste Ziele aus goals.json, danach endlos neue (Bevoelkerung, Inseln, Geburten).
func milestone(i: int) -> Dictionary:
	var list: Array = Data.goals.get("milestones", [])
	if i < list.size():
		return list[i]
	var k := i - list.size()
	var lvl := k / 3 + 1
	match k % 3:
		0:
			var n := 40 + 15 * lvl
			return {"id": "e%d" % k, "text": "Wachse auf %d Siedler." % n, "check": {"type": "pop", "n": n},
				"reward": {"brot": 10 + 5 * lvl, "werkzeug": 2 + lvl}}
		1:
			var n := 2 + 2 * lvl
			return {"id": "e%d" % k, "text": "Entdecke %d Inseln." % n, "hint": "Hinter dem Horizont warten immer neue Inseln.",
				"check": {"type": "islands_found", "n": n}, "reward": {"boot": 1, "eisen": 4 + 2 * lvl}}
		_:
			var n := 30 + 30 * lvl
			return {"id": "e%d" % k, "text": "Feiere %d Geburten." % n, "check": {"type": "births", "n": n},
				"reward": {"fleisch": 10 + 5 * lvl, "ziegel": 10 + 5 * lvl}}


## [aktueller Wert, Zielwert]
func progress(g: Dictionary) -> Array:
	var c: Dictionary = g.get("check", {})
	var n := int(c.get("n", 1))
	var what: String = c.get("what", "")
	match c.get("type", ""):
		"selected_settler":
			return [1 if Game.selected is Settler else 0, 1]
		"action":
			for a in _actions:
				if a[0] == c.get("kind") and (what == "" or a[1] == what):
					return [1, 1]
			return [0, 1]
		"building":
			var cnt := 0
			for w in Sea.all_worlds():
				for b in w.buildings:
					if (b.type == what or b.def.get("base", "") == what) and (b.complete or c.get("any", false)):
						cnt += 1
			return [cnt, n]
		"housing":
			var cap := 0
			for w in Sea.all_worlds():
				cap += Game.housing_capacity(w)
			return [cap, n]
		"pop":
			return [Game.population() + Sea.people_at_sea(), n]
		"techs":
			return [Game.research.done.size(), min(n, Data.techs.size())]
		"tier":
			var best := 0
			for t in Game.research.done:
				best = max(best, int(Data.techs[t].tier))
			return [best, n]
		"research_active":
			return [1 if Game.research.current != "" or not Game.research.done.is_empty() else 0, 1]
		"speed":
			return [1 if Game.speed >= n else 0, 1]
		"variety":
			return [Game.food_variety(), n]
		"islands_found":
			return [Sea.islands.size() - 1, n]
		"islands_settled":
			return [Sea.settled_islands().size(), n]
		"kills":
			return [int(Game.stats.get("kills", 0)), n]
		"births":
			return [int(Game.stats.get("births", 0)), n]
		"stock":
			return [Game.amount_all(what), n]
	return [0, 1]


func _is_done(g: Dictionary) -> bool:
	var p := progress(g)
	return int(p[0]) >= int(p[1])


func _advance(g: Dictionary, silent: bool) -> void:
	var was_tut := in_tutorial()
	if was_tut:
		Game.goals.tut = int(Game.goals.get("tut", 0)) + 1
	else:
		Game.goals.ms = int(Game.goals.get("ms", 0)) + 1
	_actions.clear()
	if silent:
		return
	Sound.play("ziel")
	if was_tut:
		if not in_tutorial():
			hud.toast("Einführung geschafft! Jetzt warten Ziele mit Belohnungen auf dich.", "ziel")
	else:
		var parts := []
		for res in g.get("reward", {}):
			var got := Game.add_stock(res, int(g.reward[res]))
			if got > 0:
				parts.append("%d %s" % [got, Data.resource_name(res)])
		var text: String = "Ziel erreicht: %s" % g.text
		if not parts.is_empty():
			text += " Belohnung: " + ", ".join(parts) + "."
		hud.toast(text, "ziel")
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	modulate = Color(1.4, 1.4, 0.8)
	tw.tween_property(self, "modulate", Color.WHITE, 0.8)


## Wegklicken: dieses Ziel bleibt verborgen, das naechste erscheint wieder.
func _dismiss() -> void:
	Game.goals["hide"] = _cur_id
	Sound.play("zu")
	hud.toast("Ziel ausgeblendet. Das nächste Ziel erscheint wieder. Ganz abschalten: Menü > Meldungen.", "ziel", "tag")


func shown() -> bool:
	return Game.goal_card_on and str(Game.goals.get("hide", "")) != current().id


func _skip_tutorial() -> void:
	Game.goals.tut = Data.goals.get("tutorial", []).size()
	_actions.clear()
	_cur_id = ""
	hud.toast("Einführung übersprungen. Die Spielanleitung findest du im Menü.", "ziel")


# ---------------------------------------------------------------- Anzeige
func _process(delta: float) -> void:
	var real: float = delta / max(Engine.time_scale, 0.001) if Engine.time_scale > 0.0 else 1.0 / 60.0
	_bob += real
	var active: bool = Game.world != null and is_instance_valid(Game.world) and not Game.is_over and not hud.has_overlay()
	if not active:
		_set_visible(false)
		return
	_tick -= real
	if _tick <= 0.0:
		_tick = 0.4
		_check()
	_set_visible(shown())
	if visible:
		_update_pointer()


func _set_visible(on: bool) -> void:
	if not on:
		_pointer.visible = false
	if visible != on:
		visible = on
		if hud:
			hud._layout.call_deferred()


func _check() -> void:
	if Game.goals.get("catchup", false):
		Game.goals.erase("catchup")
		for i in 200:
			var g := current()
			if not _is_done(g):
				break
			_advance(g, true)
	var g := current()
	if _is_done(g):
		_advance(g, false)
		g = current()
	var t := in_tutorial()
	if g.id != _cur_id:
		_cur_id = g.id
		var tut_n: int = Data.goals.get("tutorial", []).size()
		_head.text = ("Einführung %d/%d" % [int(Game.goals.tut) + 1, tut_n]) if t else "Ziel"
		_text.text = g.text
		_hint.text = g.get("hint", "")
		# In der Einfuehrung ist die Erklaerung immer offen
		_hint.visible = t and _hint.text != ""
		_skip.visible = t
		_relayout()
	var p := progress(g)
	_bar.visible = int(p[1]) > 1
	_bar.value = 100.0 * float(p[0]) / max(1.0, float(p[1]))
	_bar.tooltip_text = "%d / %d" % [int(p[0]), int(p[1])]


func _update_pointer() -> void:
	var target = null
	if in_tutorial():
		target = _pointer_target(current())
	if target == null:
		_pointer.visible = false
		return
	var bob := sin(_bob * 6.0) * 4.0
	_pointer.visible = true
	_pointer.flip_v = false
	if target is Vector2:
		_pointer.position = target - Vector2(15, 34 - bob)
	else:
		var r: Rect2 = target.get_global_rect()
		if r.position.y < 40:
			_pointer.flip_v = true
			_pointer.position = Vector2(r.get_center().x - 15, r.end.y + 4 + bob)
		else:
			_pointer.position = Vector2(r.get_center().x - 15, r.position.y - 32 + bob)
	_pointer.get_parent().move_child(_pointer, -1)


## Wohin der Zeiger zeigt: ein Control, eine Bildschirmposition oder nichts.
func _pointer_target(g: Dictionary):
	var w = Game.world
	var pt: String = g.get("point", "")
	match pt:
		"settler", "info":
			if Game.selected is Settler or _panel_open() or w.settlers.is_empty():
				return null
			var s = w.settlers[0]
			var cam: Camera2D = hud.camera
			return s.get_global_transform_with_canvas().origin - Vector2(0, 22 * cam.zoom.y)
		"build":
			var what: String = g.check.get("what", "")
			if w.is_placing():
				return hud._place_ok if not hud._place_ok.disabled else null
			if hud._build_panel.visible:
				for row in hud._build_list.get_children():
					if row.get_meta("btype", "") == what:
						return row.get_child(0).get_child(0)
				var cat: String = Data.buildings.get(what, {}).get("category", "")
				for tab in hud._build_tabs:
					if tab[1] == cat:
						return tab[0]
				return null
			if _panel_open() or Game.selected != null:
				return null
			return hud._build_btn
		"research":
			if hud._research_panel.visible:
				for row in hud._research_list.get_children():
					if row.get_meta("tid", "") == "steinwerkzeuge" and Game.tech_state("steinwerkzeuge") == "available":
						return row.get_child(0).get_child(0)
				return null
			if _panel_open() or Game.selected != null:
				return null
			return hud._research_btn
		"speed":
			if _panel_open():
				return null
			return hud._speed_btns[2][0]
	return null


func _panel_open() -> bool:
	for p in hud._panels():
		if p.visible:
			return true
	return false
