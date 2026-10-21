class_name AdminInfo
extends RefCounted
## Anzeige der Verwaltung (Admin): Schalter "Vertretung" in Werkstätten, Anordnungen im Infofenster
## der Verwaltung und das Fenster, in dem der Verwalter Überstunden oder Schichtarbeit vorschlägt.
## hud.gd ruft attach(hud) einmal und die *_rows-Helfer im Infofenster auf.

const DIM := Color("#6e5a50")

static var _dialog: Control


## Fenster beim Vorschlag des Verwalters (Signal Admin.proposal).
static func attach(hud) -> void:
	Admin.proposal.connect(func(job, text): show_proposal(hud, job, text))


## Werkstatt: Schalter Vertretung (nur, wenn die Verwaltung arbeitet).
static func workshop_rows(hud, b) -> void:
	if not Admin.active_on(b.world):  # nur auf der Insel der Verwaltung (josh 2026-10-16)
		return
	var on: bool = b.adm
	var bt := UiTheme.button(Loc.t("Vertretung: an") if on else Loc.t("Vertretung: aus"), "wissen", 34)
	bt.tooltip_text = Loc.t("Fehlt die Fachkraft gerade (Pause, Schlaf, Essen), springt ein Siedler ein, der sonst nichts zu tun hat.")
	bt.pressed.connect(func():
		b.adm = not b.adm
		hud._rebuild_info())
	hud._info_box.add_child(bt)
	var l := UiTheme.label(Loc.t("Verwaltung: Fehlt die Fachkraft, springt ein anderer Siedler ein.") if on
		else Loc.t("Verwaltung: Vertretung einschalten, damit die Werkstatt auch ohne ihre Fachkraft läuft."), 12, DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud._info_box.add_child(l)


## Berufe, für die die Verwaltung Anordnungen zeigt: die Werkstattberufe und jeder Beruf mit Leuten
## auf der Insel der Verwaltung.
static func _jobs(w) -> Array:
	var out: Array = Admin.KIND_JOB.values()
	for s in w.settlers:
		if s.is_adult() and not s.job in out and not s.job in ["frei", Admin.JOB]:
			out.append(s.job)
	return out.filter(func(j): return Data.jobs.has(j) and (Data.job_unlocked(j) or Admin.ordered(j, "ot") or Admin.ordered(j, "sh")))


static func _count(job: String, w) -> int:
	return w.settlers.filter(func(s): return s.job == job and s.is_adult()).size()


static var _tab := 0  # Reiter im Fenster Verwalter: 0 Verwalter, 1 Schichten, 2 Nachtschicht, 3 Überstunden, 4 Statistik, 5 Inseln
static var _task_island := -1  # Reiter Inseln: für diese Insel ist die Auswahl der Spezialisierung offen
const TAB_ISLANDS := 5
static var _box: Container  # hierhin bauen die Reiter ihre Zeilen (Fenster Verwalter oder Infofenster)
static var _rebuild: Callable  # baut das Fenster neu auf


## Infofenster der Verwaltung mit den Reitern Verwalter, Schichten, Nachtschicht und Überstunden
## (josh 2026-10-16).
static func office_rows(hud, b) -> void:
	_box = hud._info_box
	_rebuild = hud._rebuild_info
	if b.complete:
		var bt := UiTheme.button(Loc.t("Fenster Verwalter öffnen"), "person", 40)
		bt.pressed.connect(hud._open_admin)
		_box.add_child(bt)


## Fenster Verwalter (josh 2026-10-20, einheitlich wie alle Fenster): Reiter Verwalter, Schichten,
## Nachtschicht, Überstunden und Statistik. box: Inhalt, rebuild: baut ihn neu auf, ft: Win.footer.
static func fill_window(hud, b, box: Container, rebuild: Callable, ft: Dictionary) -> void:
	_box = box
	_rebuild = rebuild
	var names := [Loc.t("Verwalter"), Loc.t("Schichten"), Loc.t("Nachtschicht"), Loc.t("Überstunden"), Loc.t("Statistik"), Loc.t("Inseln")]
	box.add_child(Win.tabs(names, _tab, func(i):
		_tab = i
		rebuild.call()))
	var m = Admin.local_manager()
	ft.left.text = Loc.t("Verwalter: %s") % m.display_name if m else Loc.t("Kein Verwalter")
	Win.set_left2(ft, Sea.island_name(b.world) if b != null and Sea.settled_islands().size() > 1 else "")
	if b == null and _tab < 4 and _tab != TAB_ISLANDS:
		var l := UiTheme.label(Loc.t("Baue zuerst die Verwaltung (Bauen, Reiter Wissen). Dann findest du hier den Verwalter, Schichten und Überstunden."), 14, UiTheme.BAD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
		return
	match _tab:
		0: _manager_tab(hud, b)
		1: _orders_tab(hud, b, "sh")
		2: _night_tab(hud, b)
		3: _orders_tab(hud, b, "ot")
		TAB_ISLANDS: _islands_tab(hud)
		_: _stats_tab(hud, b)


## Reiter Inseln (josh 2026-10-21: die Verwaltung der Inseln gehört zum Verwalter): Verwalter steuert die
## Berufe (Steward), Inselverbund mit Rundfunkanstalten, Spezialisierung (Hauptaufgabe) je Insel.
static func _islands_tab(_hud) -> void:
	if not Steward.unlocked():
		_note(Loc.t("Ab der zweiten Insel kann der Verwalter die Berufe auf allen Inseln steuern. Dann stellst du es hier ein."))
		return
	var auto := Steward.automat_mode()
	var r := Win.row(Data.icon("person"), Loc.t("Automat steuert die Inseln") if auto else Loc.t("Verwalter steuert die Berufe"),
		Loc.t("Er verteilt die Berufe nach dem Bedarf: Essen, Brennholz, Lager bis zur Höchstmenge, Werkstätten und Baustellen."),
		{"button": Loc.t("an") if Steward.on else Loc.t("aus"), "button_off": not Steward.on, "hi": Steward.on, "icon_px": 28,
		"on_press": func():
			Steward.set_on(not Steward.on)
			_rebuild.call()})
	_box.add_child(r.box)
	if Steward.on:
		for m in Sea.settled_islands():
			var why := Steward.blocked_on(Sea.worlds.get(int(m.id)))
			if why != "":
				_note(Loc.t("%s: %s.") % [m.name, why], UiTheme.BAD)
	_planner_rows()
	if Steward.net_unlocked():
		var miss: Array = Steward.islands_without_radio()
		var sub := Loc.t("Die Heimatinsel verarbeitet, die anderen Inseln liefern Essen und Rohstoffe.")
		var col := DIM
		if Steward.net_on and not Steward.has_radio(Sea.main_world()):
			sub = Loc.t("Ruht: Die Heimatinsel braucht eine Rundfunkanstalt.")
			col = UiTheme.BAD
		elif Steward.net_on and Steward._ids().size() < 2:
			sub = Loc.t("Ruht: Noch keine andere Insel hat eine Rundfunkanstalt.")
			col = UiTheme.BAD
		if Steward.net_on and not miss.is_empty():
			sub += "\n" + Loc.t("Ohne Rundfunkanstalt, machen nicht mit: %s") % ", ".join(PackedStringArray(miss))
		var nr := Win.row(Data.icon("papier"), Loc.t("Inselverbund"), sub, {"sub_color": col, "icon_px": 28,
			"button": Loc.t("an") if Steward.net_on else Loc.t("aus"), "button_off": not Steward.net_on, "hi": Steward.net_on,
			"on_press": func():
				Steward.set_net(not Steward.net_on)
				_rebuild.call()})
		_box.add_child(nr.box)
	_box.add_child(UiTheme.label(Loc.t("Spezialisierung der Inseln"), 15, UiTheme.TEXT, true))
	if not Steward.on:
		_note(Loc.t("Der Verwalter richtet sich danach, sobald er die Berufe steuert."))
	for m in Sea.settled_islands():
		var iid := int(m.id)
		var w = Sea.worlds.get(iid)
		if w == null:
			continue
		var keys := Steward.tasks_of(w)
		var sub := Steward.task_names(w) if not keys.is_empty() else Loc.t("Keine (nur nach Bedarf)")
		if not keys.is_empty():
			var parts := []
			for j in Steward.task_jobs(w):
				parts.append("%s %d/%d" % [Data.jobs[j].name, Steward._count(w, j), Steward.task_target(w, j)])
			sub += "\n" + (Loc.t("Berufe: %s") % ", ".join(PackedStringArray(parts)) if not parts.is_empty() else Loc.t("Hier fehlt noch die passende Werkstatt oder Forschung."))
		if Steward.net_unlocked():
			sub += "\n" + (Loc.t("Rundfunkanstalt: ja") if Steward.has_radio(w) else Loc.t("Rundfunkanstalt: fehlt"))
		var tr_ := Win.row(Data.icon(Steward.TASKS[keys[0]].icon if not keys.is_empty() else "anker"), str(m.name), sub, {"icon_px": 28,
			"button": Loc.t("Fertig") if _task_island == iid else Loc.t("Wählen"), "hi": _task_island == iid,
			"on_press": func():
				_task_island = -1 if _task_island == iid else iid
				_rebuild.call()})
		_box.add_child(tr_.box)
		if _task_island == iid:
			_note(Loc.t("Mehrere wählbar. Nochmal tippen wählt ab."))
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 4)
			grid.add_theme_constant_override("v_separation", 4)
			for k in [""] + Steward.TASKS.keys():
				if k == "forschung" and not Sea.is_main(w):
					continue
				var tb := UiTheme.button(Loc.t(Steward.TASKS[k].name) if k != "" else Loc.t("Keine"), Steward.TASKS[k].icon if k != "" else "abriss", 36)
				tb.add_theme_font_size_override("font_size", 13)
				tb.toggle_mode = true
				tb.button_pressed = k in keys if k != "" else keys.is_empty()
				tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var kk: String = k
				tb.pressed.connect(func():
					Steward.toggle_task(iid, kk)
					_rebuild.call())
				grid.add_child(tb)
			_box.add_child(grid)


## Planungsautomat (Planner, josh 2026-10-21): Schalter und der letzte Plan je Insel (oberste Lücke, nächster Schritt).
static func _planner_rows() -> void:
	var why := Planner.reason()
	var sub := Loc.t("Erst Essen, Wärme und Wintervorrat, dann Häuser, Lager, Werkstätten und Forschung bis zur KI. Bauen und das Material bringen müssen die Siedler.")
	if why != "":
		sub = why
	var r := Win.row(Data.building_tex("planautomat"), Loc.t("Automat plant Bauten, Waren und Routen"), sub,
		{"sub_color": UiTheme.BAD if why != "" else DIM, "icon_px": 28,
		"button": Loc.t("an") if Planner.on else Loc.t("aus"), "button_off": not Planner.on or why != "", "hi": Planner.on and why == "",
		"on_press": func():
			Planner.set_on(not Planner.on)
			_rebuild.call()})
	_box.add_child(r.box)
	if not Planner.active():
		return
	_box.add_child(UiTheme.label(Loc.t("Plan"), 15, UiTheme.TEXT, true))
	for m in Sea.settled_islands():
		var w = Sea.worlds.get(int(m.id))
		if w == null:
			continue
		var p := Planner.plan_of(w)
		var text := Loc.t("Noch nicht geplant.") if p.is_empty() else "%s\n%s" % [p.need, Loc.t("Nächster Schritt: %s") % p.step]
		var col: Color = UiTheme.BAD if str(p.get("prio", "")) == "a" else DIM
		_box.add_child(Win.row(Data.icon("anker"), str(m.name), text, {"sub_color": col, "icon_px": 24}).box)
	if Planner.research_note != "" or Planner.wanted_tech != "":
		var rt := Loc.t("Forscht: %s") % Planner.research_note if Game.research.current != "" else Loc.t("Wartet auf Material für %s") % Data.techs.get(Planner.wanted_tech, {}).get("name", "?")
		_box.add_child(Win.row(Data.icon("wissen"), Loc.t("Forschung"), rt, {"icon_px": 24}).box)


static func _note(t: String, col: Color = DIM) -> void:
	var l := UiTheme.label(t, 12, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(l)


## Nachtschicht: welche Berufe nachts arbeiten (Schichtarbeit), wie viele Leute und was es kostet.
static func _night_tab(hud, b) -> void:
	var any := false
	for job in _jobs(b.world):
		if not Admin.ordered(job, "sh"):
			continue
		any = true
		var n := 0
		for s in b.world.settlers:
			if s.job == job and Admin.night_worker(s):
				n += 1
		var sub := Loc.t("%d arbeiten auch nachts, Laune eine Stufe schlechter.") % n
		if not Admin.active_on(b.world):
			sub = Loc.t("Ruht, solange kein Verwalter hier arbeitet.")
		var jid: String = job
		var r := Win.row(null, Data.jobs[job].name, sub, {"button": Loc.t("Beenden"), "on_press": func():
			Admin.set_shift(jid, false)
			_rebuild.call()})
		_box.add_child(r.box)
	var l := UiTheme.label(Loc.t("In der Nacht brennt in diesen Werkstätten Licht, und die Nacht vergeht nicht schneller.") if any
		else Loc.t("Niemand arbeitet nachts. Unter „Schichten“ lässt sich für einen Beruf Schichtarbeit rund um die Uhr anordnen."), 12, DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(l)


static func _manager_tab(hud, b) -> void:
	var m = Admin.local_manager()
	var away = Admin.manager()
	var head_text := Loc.t("Verwalter: %s") % m.display_name if m else Loc.t("Kein Verwalter! Gib einem Siedler den Beruf Verwalter.")
	if m == null and away != null:
		head_text = Loc.t("Der Verwalter %s lebt auf einer anderen Insel (%s). Er arbeitet nur hier, auf der Insel der Verwaltung.") % [away.display_name, Sea.island_name(away.world)]
	var head := UiTheme.label(head_text, 14, UiTheme.TEXT if m else UiTheme.BAD, true)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(head)
	var cb := CheckBox.new()
	cb.text = Loc.t("Automatische Neuzuweisung freier Berufe")
	cb.focus_mode = Control.FOCUS_NONE
	cb.custom_minimum_size.y = 40
	cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # langer Text bricht um, statt das Infofenster aus dem Bild zu schieben
	cb.add_theme_font_size_override("font_size", 14)
	cb.tooltip_text = Loc.t("Stirbt ein Siedler mit Beruf, auch der Verwalter, bekommt automatisch ein freier Siedler diesen Beruf. Gibt es keinen, lernt ihn das nächste Kind, das erwachsen wird.")
	cb.button_pressed = Admin.auto_reassign
	cb.toggled.connect(func(on):
		Admin.auto_reassign = on
		Admin.changed.emit())
	if not Admin.auto_unlocked():
		cb.disabled = true
		cb.text += " " + Loc.t("(ab dem Mittelalter)")
	_box.add_child(cb)
	var so := CheckBox.new()  # josh 2026-10-21: ab Stufe 8 ordnet er selbst an
	so.text = Loc.t("Überstunden und Schichtarbeit selbst anordnen")
	so.focus_mode = Control.FOCUS_NONE
	so.custom_minimum_size.y = 40
	so.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	so.add_theme_font_size_override("font_size", 14)
	so.tooltip_text = Loc.t("Fehlen in einem Beruf Leute, ordnet der Verwalter erst Überstunden an, dann Schichtarbeit mit Nachtschicht. Fehlt niemand mehr, beendet er sie; Überstunden beendet er, bevor protestiert wird. Schaltest du selbst etwas ab, lässt er den Beruf ein Jahr in Ruhe.")
	so.button_pressed = Admin.self_orders
	so.toggled.connect(func(on):
		Admin.self_orders = on
		Admin.changed.emit())
	if not Admin.self_orders_unlocked():
		so.disabled = true
		so.text += " " + Loc.t("(ab Stufe %d)") % Admin.SELF_ORDER_TIER
	_box.add_child(so)
	if Admin.auto_on() and not Admin.pending_jobs.is_empty():
		var wait := UiTheme.label(Loc.t("Wartet auf das nächste erwachsene Kind: %s") % ", ".join(Admin.pending_jobs.map(func(j): return Admin._name(j))), 13, UiTheme.TEXT, true)
		wait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(wait)


## Eine Zeile je Beruf mit einem Schalter: kind "sh" Schichtarbeit, "ot" Überstunden.
static func _orders_tab(hud, b, kind: String) -> void:
	var short := {}
	for e in Admin.shortages():
		short[e[0]] = e
	for job in _jobs(b.world):
		var sub := Loc.t("Siedler: %d") % _count(job, b.world)
		var col := DIM
		if short.has(job):
			sub += " · " + Loc.t("fehlen: %d") % (int(short[job][1]) - int(short[job][2]))
			col = UiTheme.BAD
		if kind == "ot":
			if Admin.ordered(job, "ot"):
				var left := Seasons.year_days() * float(Admin.cfg.get("overtime_years", 1.0)) - (Game.time_days - float(Admin.orders[job].since))
				sub += "\n" + Loc.t("Überstunden noch höchstens %d Tage.") % maxi(0, ceili(left))
			if Admin.protesting(job):
				sub += "\n" + Loc.t("Protest gegen zu lange Überstunden: noch %d Tage.") % maxi(1, ceili(float(Admin.protest[job]) - Game.time_days))
				col = UiTheme.BAD
		var on: bool = Admin.ordered(job, kind)
		if on and Admin.auto_orders.has(job):
			sub += "\n" + Loc.t("Vom Verwalter angeordnet.")
		var jid: String = job
		var press := func():
			if kind == "ot":
				var err := Admin.set_overtime(jid, not Admin.ordered(jid, "ot"))
				if err != "":
					hud.toast(err, "wissen")
			else:
				Admin.set_shift(jid, not Admin.ordered(jid, "sh"))
			_rebuild.call()
		var r := Win.row(Data.icon("person"), Data.jobs[job].name, sub,
			{"sub_color": col, "button": Loc.t("an") if on else Loc.t("aus"), "button_off": not on, "on_press": press, "icon_px": 28, "hi": on})
		if on and Admin.auto_orders.has(job):
			UiTheme.mark_admin(r.button)
		if kind == "ot" and Admin.protesting(job):
			r.button.disabled = true
			r.button.tooltip_text = Loc.t("Protest gegen zu lange Überstunden")
		_box.add_child(r.box)


## Statistik (josh 2026-10-20): Auslastung je Beruf (alle Inseln) und was im letzten und im laufenden
## Jahr erzeugt wurde.
static func _stats_tab(_hud, b) -> void:
	var w = b.world if b != null else Game.world
	if Sea.settled_islands().size() > 1:
		var il := UiTheme.label(Loc.t("Zahlen für die Insel %s.") % Sea.island_name(w), 13, DIM)
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(il)
	_box.add_child(UiTheme.label(Loc.t("Auslastung der Berufe"), 15, UiTheme.TEXT, true))
	var load := Admin.job_load(w)
	var jobs := load.keys()
	jobs.sort_custom(func(x, c): return int(load[x][1]) > int(load[c][1]))
	if jobs.is_empty():
		_box.add_child(UiTheme.label(Loc.t("Noch hat niemand einen Beruf."), 13, DIM))
	for job in jobs:
		if not Data.jobs.has(job):
			continue
		var l: Array = load[job]
		var p: int = l[1]
		var sub := Loc.t("Siedler: %d") % int(l[0])
		if p >= 0:
			sub += " · " + Loc.t("hilft aus %d %%, nichts zu tun %d %%") % [int(l[2]), int(l[3])]
		else:
			sub += " · " + Loc.t("wird noch gemessen")
		var r := Win.row(Data.icon("person"), Data.jobs[job].name, sub, {"icon_px": 28,
			"value": ("%d %%" % p) if p >= 0 else "–",
			"value_color": DIM if p < 0 else (UiTheme.GOOD if p >= 70 else (UiTheme.ACCENT if p >= 40 else UiTheme.BAD))})
		_box.add_child(r.box)
	var hint := UiTheme.label(Loc.t("Die große Zahl ist der Anteil der Arbeitszeit im eigenen Beruf. Essen, Schlafen und Freizeit zählen nicht mit."), 12, DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(hint)
	var y := Seasons.year()
	var last := Admin.produced_in(y - 1, w)
	var now := Admin.produced_in(y, w)
	_box.add_child(UiTheme.label(Loc.t("Erzeugte Waren"), 15, UiTheme.TEXT, true))
	var goods := []
	for id in Data.sorted_resource_ids():
		if int(last.get(id, 0)) > 0 or int(now.get(id, 0)) > 0:
			goods.append(id)
	if goods.is_empty():
		var e := UiTheme.label(Loc.t("Noch nichts gezählt. Gezählt wird, was gesammelt, geerntet, gejagt und in Werkstätten hergestellt wird."), 13, DIM)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(e)
		return
	# Kopfzeile mit zwei Spalten: Vorjahr und laufendes Jahr
	var head := Win.row(null, "", "", {})
	head.box.self_modulate = Color(1, 1, 1, 0)
	_cols(head.h, Loc.t("Jahr %d") % (y - 1) if y > 1 else "", Loc.t("Jahr %d bisher") % y, DIM)
	_box.add_child(head.box)
	for id in goods:
		var r := Win.row(Data.res_icon(id), Data.resource_name(id), "", {"icon_px": 24})
		_cols(r.h, str(int(last.get(id, 0))) if y > 1 else "", str(int(now.get(id, 0))), UiTheme.TEXT)
		_box.add_child(r.box)
	var note := UiTheme.label(Loc.t("Gezählt wird seit dem Update vom 20. Oktober, was auf dieser Insel gesammelt, geerntet, gejagt und in Werkstätten hergestellt wird, nicht was Schiffe bringen oder Händler verkaufen. Ein Jahr hat vier Jahreszeiten."), 12, DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(note)


## Zwei rechtsbündige Zahlenspalten fester Breite am Ende einer Zeile.
static func _cols(h: Container, a: String, c: String, col: Color) -> void:
	for t in [a, c]:
		var l := UiTheme.label(t, 14 if col == UiTheme.TEXT else 12, col, col == UiTheme.TEXT)
		l.custom_minimum_size.x = 84
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(l)


## Der Verwalter schlägt Überstunden oder Schichtarbeit vor (Fenster mit drei Knöpfen).
static func show_proposal(hud, job: String, text: String) -> void:
	if _dialog and is_instance_valid(_dialog):
		_dialog.queue_free()
	if Game.speed > 1:
		Game.set_speed(1)  # zum Entscheiden auf normale Zeit
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.15, 0.35)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.root.add_child(bg)
	_dialog = bg
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var t := UiTheme.label(Loc.t("Verwaltung"), 22, UiTheme.TEXT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var l := UiTheme.label(text + "\n" + Loc.t("Was ordnest du an?"), 15)
	l.custom_minimum_size.x = 300
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var d := UiTheme.label(Loc.t("Überstunden: 2 Stunden früher anfangen und länger arbeiten, keine Pausen, etwa anderthalbmal so viel Ertrag, höchstens ein Jahr am Stück. Schichtarbeit: Arbeit rund um die Uhr, etwa doppelt so viel Ertrag, Laune eine Stufe schlechter."), 12, DIM)
	d.custom_minimum_size.x = 300
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var close := func():
		if is_instance_valid(bg):
			bg.queue_free()
		_dialog = null
		_rebuild.call()
	var ob := UiTheme.button(Loc.t("Überstunden"), "", 40)
	ob.disabled = Admin.ordered(job, "ot") or Admin.protesting(job)
	ob.pressed.connect(func():
		var err := Admin.set_overtime(job, true)
		hud.toast(err if err != "" else Loc.t("Überstunden angeordnet: %s") % Data.jobs[job].name, "wissen")
		close.call())
	v.add_child(ob)
	var sb := UiTheme.button(Loc.t("Schichtarbeit"), "", 40)
	sb.disabled = Admin.ordered(job, "sh")
	sb.pressed.connect(func():
		Admin.set_shift(job, true)
		hud.toast(Loc.t("Schichtarbeit angeordnet: %s") % Data.jobs[job].name, "wissen")
		close.call())
	v.add_child(sb)
	var later := UiTheme.button(Loc.t("Nichts anordnen"), "abriss", 40)
	later.pressed.connect(func():
		Admin.reported[job] = Game.time_days + 4.0  # dann erst in 6 statt 2 Tagen wieder fragen
		close.call())
	v.add_child(later)
