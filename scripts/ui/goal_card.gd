class_name GoalCard
extends PanelContainer
## Einfuehrung und Ziele (Etappe 4). Zeigt oben links den naechsten Schritt bzw. das
## naechste Ziel, prueft es regelmaessig und verteilt Belohnungen. Waehrend der
## Einfuehrung zeigt ein huepfender Pfeil auf den passenden Knopf oder Teil eines Fensters,
## und die Karte steht als Sprechblase daneben (josh 2026-10-19). Erklaer-Schritte haben
## den Knopf Weiter (check action/next), "gift" schenkt Waren, sobald der Schritt beginnt.
## Daten: data/goals.json, Zustand: Game.goals {tut, ms}.

var hud  # Hud
var _head: Label
var _text: Label
var _hint: Label
var _bar: ProgressBar
var _skip: Button
var _next: Button  # Weiter bei Erklaer-Schritten der Einfuehrung
var bubble: bool = false  # Karte steht als Sprechblase neben dem Ziel des Zeigers (hud._layout laesst sie dann in Ruhe)
var _home_idx: int = -1
var _pointer: TextureRect
var _tick: float = 0.0
var _cur_id: String = ""
var _actions: Array = []  # Aktionen seit Beginn des aktuellen Schritts
var _bob: float = 0.0
var _ms_box: Control  # Ziel bzw. Pruefung (oben); das X blendet nur diesen Teil aus
var _quest_row: Control  # Auftrag darunter (QuestView, Teil D)


func setup(p_hud) -> void:
	hud = p_hud
	mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var col := VBoxContainer.new()  # oben Ziel oder Pruefung, darunter der Auftrag
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	col.add_child(h)
	_ms_box = h
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
	_skip = UiTheme.button(tr("Überspringen"), "", 22)
	_skip.add_theme_font_size_override("font_size", 11)
	_skip.tooltip_text = tr("Einführung überspringen")
	_skip.pressed.connect(_skip_tutorial)
	hr.add_child(_skip)
	var close := UiTheme.button("", "abriss", 22)
	close.tooltip_text = tr("Ziel ausblenden, bis das nächste kommt")
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
	_next = UiTheme.button(tr("Weiter"), "play", 34)
	_next.size_flags_horizontal = Control.SIZE_SHRINK_END
	_next.add_theme_font_size_override("font_size", 14)
	_next.visible = false
	_next.pressed.connect(func():
		Sound.play("klick")
		Game.player_action.emit("next", _cur_id)
		_tick = 0.0)  # gleich weiter, nicht erst nach der naechsten Pruefung
	v.add_child(_next)
	tooltip_text = tr("Tippen: Erklärung ein- und ausblenden")
	gui_input.connect(func(ev):
		if in_tutorial():
			return  # in der Einfuehrung bleibt die Erklaerung offen
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
	_quest_row = QuestView.goal_row(self)
	col.add_child(_quest_row)


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
	if Exams.blocking():  # Pruefung haelt das Weiterforschen auf: sie kommt vor den Zielen
		return Exams.goal()
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
			return {"id": "e%d" % k, "text": tr("Wachse auf %d Siedler.") % n, "check": {"type": "pop", "n": n},
				"reward": {"brot": 10 + 5 * lvl, "werkzeug": 2 + lvl}}
		1:
			var n := 2 + 2 * lvl
			return {"id": "e%d" % k, "text": tr("Entdecke %d Inseln.") % n, "hint": tr("Hinter dem Horizont warten immer neue Inseln."),
				"check": {"type": "islands_found", "n": n}, "reward": {"boot": 1, "eisen": 4 + 2 * lvl}}
		_:
			var n := 30 + 30 * lvl
			return {"id": "e%d" % k, "text": tr("Feiere %d Geburten.") % n, "check": {"type": "births", "n": n},
				"reward": {"fleisch": 10 + 5 * lvl, "ziegel": 10 + 5 * lvl}}


## [aktueller Wert, Zielwert]. Alles ausser Auswahl und Aktionen prueft GoalChecks (gemeinsam mit
## den Pruefungen und Auftraegen).
func progress(g: Dictionary) -> Array:
	var c: Dictionary = g.get("check", {})
	var what: String = c.get("what", "")
	match c.get("type", ""):
		"selected_settler":
			return [1 if Game.selected is Settler else 0, 1]
		"action":
			for a in _actions:
				if a[0] == c.get("kind") and (what == "" or a[1] == what):
					return [1, 1]
			return [0, 1]
	return GoalChecks.progress(c)


## Pseudo-Ziel der Pruefung beim Zeitalterwechsel (Exams.goal): bringt nie das naechste Ziel.
static func is_exam(g: Dictionary) -> bool:
	return str(g.get("id", "")).begins_with("exam_")


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
			hud.toast(tr("Einführung geschafft! Jetzt warten Ziele mit Belohnungen auf dich."), "ziel")
			Extras.tutorial_reward(Game.world)  # 2 Siedler, Hütte, Lagerhaus und zwei Forschungen
		var got := Extras.tutorial_step_reward(Game.world, g.get("reward", {}))
		if got != "":
			hud.toast(tr("Geschafft! Belohnung: %s.") % got, "ziel")
	else:
		var parts := []
		for res in g.get("reward", {}):
			var got := Game.add_stock(res, int(g.reward[res]))
			if got > 0:
				parts.append("%d %s" % [got, Data.resource_name(res)])
		var text: String = tr("Ziel erreicht: %s") % g.text
		if not parts.is_empty():
			text += tr(" Belohnung: ") + ", ".join(parts) + "."
		hud.toast(text, "ziel")
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	modulate = Color(1.4, 1.4, 0.8)
	tw.tween_property(self, "modulate", Color.WHITE, 0.8)


## Wegklicken: dieses Ziel bleibt verborgen, das naechste erscheint wieder (ein Auftrag bleibt sichtbar).
func _dismiss() -> void:
	Game.goals["hide"] = _cur_id
	Sound.play("zu")
	hud.toast(tr("Ziel ausgeblendet. Das nächste Ziel erscheint wieder. Ganz abschalten: Menü > Meldungen."), "ziel", "tag")


## Die Einführung erscheint immer, auch wenn die Zielkarte unter Menü > Meldungen aus ist (die Einstellung
## gilt im Browser für alle Versionen, josh sah 2026-10-21 bei einem neuen Spiel sonst keine Einführung).
func shown() -> bool:
	if in_tutorial():
		return _ms_shown()
	return Game.goal_card_on and (_ms_shown() or QuestView.row_wanted(self))


func _ms_shown() -> bool:
	return str(Game.goals.get("hide", "")) != current().id


## Geschenk eines Schritts der Einfuehrung (z. B. 12 Holz fuer die Flechtkoerbe): einmal, auf die Hauptinsel.
func _give_gift(g: Dictionary) -> void:
	var gift: Dictionary = g.get("gift", {})
	if gift.is_empty() or str(Game.goals.get("gift", "")) == str(g.id):
		return
	Game.goals["gift"] = g.id
	var parts := []
	for res in gift:
		var got := Game.add_stock(res, int(gift[res]), Sea.main_world())
		if got > 0:
			parts.append("%d %s" % [got, Data.resource_name(res)])
	if not parts.is_empty():
		hud.toast(tr("Geschenkt: %s") % ", ".join(parts), "ziel")


func _skip_tutorial() -> void:
	Game.goals.tut = Data.goals.get("tutorial", []).size()
	_actions.clear()
	_cur_id = ""
	hud.toast(tr("Einführung übersprungen. Die Spielanleitung findest du im Menü."), "ziel")


# ---------------------------------------------------------------- Anzeige
func _process(delta: float) -> void:
	var real: float = delta / max(Engine.time_scale, 0.001) if Engine.time_scale > 0.0 else 1.0 / 60.0
	_bob += real
	var active: bool = Game.world != null and is_instance_valid(Game.world) and not Game.is_over and not hud.has_overlay()
	if not active:
		_set_visible(false)
		_set_bubble(false)
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
		_set_bubble(false)
	if visible != on:
		visible = on
		if hud:
			hud._layout.call_deferred()


func _check() -> void:
	if Game.goals.get("catchup", false):
		Game.goals.erase("catchup")
		for i in 200:
			var g := current()
			if is_exam(g) or not _is_done(g):
				break
			_advance(g, true)
	var g := current()
	if _is_done(g) and not is_exam(g):  # Pruefungen besteht Game (Exams), nie die Zielkarte
		_advance(g, false)
		g = current()
	var t := in_tutorial()
	if g.id != _cur_id:
		_cur_id = g.id
		var tut_n: int = Data.goals.get("tutorial", []).size()
		_head.text = (tr("Einführung %d/%d") % [int(Game.goals.tut) + 1, tut_n]) if t else (tr("Prüfung") if is_exam(g) else tr("Ziel"))
		_text.text = g.text
		_hint.text = g.get("hint", "")
		if t:  # was der Schritt bringt; der letzte zeigt die Belohnung für die ganze Einführung
			var last := int(Game.goals.tut) == tut_n - 1
			var rw: Dictionary = g.get("reward", Extras.TUT_FINAL if last else {})
			if not rw.is_empty():
				_hint.text += "\n" + tr("Belohnung: %s.") % Extras.tutorial_reward_text(rw)
		# In der Einfuehrung ist die Erklaerung immer offen
		_hint.visible = t and _hint.text != ""
		_skip.visible = t
		var c: Dictionary = g.get("check", {})
		_next.visible = t and c.get("type", "") == "action" and c.get("kind", "") == "next"
		if t:
			_give_gift(g)
		_relayout()
	elif is_exam(g) and _hint.text != str(g.get("hint", "")):
		_hint.text = g.get("hint", "")  # Pruefung: was noch fehlt, aendert sich laufend
		if _hint.visible:
			_relayout()
	var p := progress(g)
	_bar.visible = int(p[1]) > 1
	_bar.value = 100.0 * float(p[0]) / max(1.0, float(p[1]))
	_bar.tooltip_text = "%d / %d" % [int(p[0]), int(p[1])]
	# Ziel (ausblendbar) und Auftrag (QuestView): bei geaenderter Hoehe neu anordnen
	var ms := _ms_shown()
	var moved: bool = QuestView.update_row(_quest_row, self, ms) or _ms_box.visible != ms
	_ms_box.visible = ms
	if moved:
		_relayout()


func _update_pointer() -> void:
	var target = null
	if in_tutorial():
		target = _pointer_target(current())
	if target == null:
		_pointer.visible = false
		if in_tutorial() and _panel_open():
			# Erklaerung ohne Ziel bei offenem Fenster: Karte oben links, aber ueber dem Fenster
			_set_bubble(true)
			_fit_width(minf(330.0, get_viewport().get_visible_rect().size.x - 12.0))
			position = Vector2(6, hud._top_h + 4.0)
		else:
			_set_bubble(false)
		return
	var bob := sin(_bob * 6.0) * 4.0
	_pointer.visible = true
	var r: Rect2
	if target is Vector2:
		r = Rect2(target - Vector2(10, 12), Vector2(20, 24))
	elif target is Rect2:
		r = target
	else:
		_scroll_into_view(target)
		r = target.get_global_rect()
	var vs := get_viewport().get_visible_rect().size
	# Ziel in der oberen Haelfte: Pfeil darunter zeigt nach oben, die Sprechblase steht darunter; sonst umgekehrt
	var below := r.get_center().y < vs.y * 0.5
	_pointer.flip_v = below
	var px := clampf(r.get_center().x - 15, 2, vs.x - 32)
	# Pfeilspitze ragt etwas ins Ziel, damit klar ist, worauf er zeigt
	_pointer.position = Vector2(px, r.end.y - 8 + bob) if below else Vector2(px, r.position.y - 22 + bob)
	if in_tutorial():
		_set_bubble(true)
		var w := minf(330.0, vs.x - 12.0)
		_fit_width(w)
		var y := r.end.y + 24.0 if below else r.position.y - 24.0 - size.y
		position = Vector2(clampf(r.get_center().x - w * 0.5, 6, vs.x - w - 6), clampf(y, 4, maxf(4.0, vs.y - size.y - 4)))
	_pointer.get_parent().move_child(_pointer, -1)


var _scrolled_for: String = ""


## Ziel in einer Liste: einmal je Schritt hinrollen, danach darf der Spieler selbst rollen.
func _scroll_into_view(c: Control) -> void:
	if _scrolled_for == _cur_id:
		return
	var p := c.get_parent()
	while p != null and not p is ScrollContainer:
		p = p.get_parent()
	if p == null:
		return
	_scrolled_for = _cur_id
	(p as ScrollContainer).ensure_control_visible(c)


func _fit_width(w: float) -> void:
	if size.x != w:
		custom_minimum_size.x = w
		size = Vector2(w, 0)


## Sprechblase: ueber allen Fenstern neben dem Ziel; sonst wieder an ihrem Platz oben links unter den Fenstern.
func _set_bubble(on: bool) -> void:
	if bubble == on:
		return
	bubble = on
	var par := get_parent()
	if on:
		_home_idx = get_index()
		par.move_child(self, -1)
	elif _home_idx >= 0:
		par.move_child(self, mini(_home_idx, par.get_child_count() - 1))
	if hud:
		hud._layout.call_deferred()


## Aktionsknopf einer Listenzeile (Win.row: der letzte Knopf rechts), sonst die Zeile selbst.
func _row_button(row: Control) -> Control:
	var h = row.get_child(0) if row.get_child_count() > 0 else null
	if h != null and h.get_child_count() > 0 and h.get_child(-1) is Button:
		return h.get_child(-1)
	return row


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
						return _row_button(row)
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
						return _row_button(row)
				return null
			if _panel_open() or Game.selected != null:
				return null
			return hud._research_btn
		"speed":
			if _panel_open():
				return null
			return hud._speed_btns[2][0]
		"top":
			return _closed_or(hud.top_bar)
		"speeds":
			return _closed_or(hud.speed_bar)
		"bottom":
			return _closed_or(hud._bottom.get_parent())
		"build_btn":
			return _closed_or(hud._build_btn)
		"research_btn":
			return _closed_or(hud._research_btn)
		"settler_btn":
			return _closed_or(hud.settler_btn)
		"menu_btn":
			return _closed_or(hud.menu_btn)
		"hut_row":
			if not hud._build_panel.visible:
				return null
			for row in hud._build_list.get_children():
				if row.get_meta("btype", "") == "huette":
					return row
			return null
		"settler_head":
			if not hud._settler_panel.visible:
				return null
			if hud._settler_head_row.visible:
				return hud._settler_head_row
			return hud._settler_list.get_child(0) if hud._settler_list.get_child_count() > 0 else null
		"job":
			# Berufswahl der ersten Erwachsenenzeile im Menü Siedler, sonst der Knopf Siedler
			if hud._settler_panel.visible:
				var obs: Array = hud._settler_list.find_children("*", "OptionButton", true, false)
				if obs.is_empty():
					return null
				# Forscher: am besten der Baumeister, der nach der Hütte frei ist
				if g.check.get("what", "") == "forscher":
					for ob in obs:
						if ob.selected >= 0 and ob.get_item_text(ob.selected) == Data.jobs.baumeister.name:
							return ob
				return obs[0]
			return _closed_or(hud.settler_btn)
		"age_tabs":
			return _children_rect(hud._research_tabs) if hud._research_panel.visible else null
		"tech_row", "tech_btn":
			if not hud._research_panel.visible:
				return _closed_or(hud._research_btn)
			for row in hud._research_list.get_children():
				if row.get_meta("tid", "") == "flechtkoerbe":
					return row if pt == "tech_row" else _row_button(row)
			return null
		"menu_tabs":
			return _children_rect(hud._menu_tabs) if hud._menu_panel.visible else null
		"child":
			if _panel_open():
				return null
			for s in w.settlers:
				if not s.is_adult():
					return s.get_global_transform_with_canvas().origin - Vector2(0, 16 * hud.camera.zoom.y)
			return null
	return null


## Reiterzeile: nur die Flaeche der Reiter selbst (die Zeile ist so breit wie das Fenster).
func _children_rect(box: Control):
	var r := Rect2()
	for c in box.get_children():
		if c is Control and c.visible:
			r = c.get_global_rect() if r.size == Vector2.ZERO else r.merge(c.get_global_rect())
	return r if r.size != Vector2.ZERO else null


## Knopf oder Leiste, solange kein Fenster offen ist (sonst verdeckt der Pfeil das Fenster).
func _closed_or(c: Control):
	return null if _panel_open() or not is_instance_valid(c) or not c.is_visible_in_tree() else c


func _panel_open() -> bool:
	for p in hud._panels():
		if p.visible:
			return true
	return false
