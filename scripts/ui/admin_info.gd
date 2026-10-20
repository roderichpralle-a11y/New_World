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


static var _tab := 0  # Reiter im Fenster Verwalter: 0 Verwalter, 1 Schichten, 2 Nachtschicht, 3 Überstunden, 4 Statistik
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
	var names := [Loc.t("Verwalter"), Loc.t("Schichten"), Loc.t("Nachtschicht"), Loc.t("Überstunden"), Loc.t("Statistik")]
	box.add_child(Win.tabs(names, _tab, func(i):
		_tab = i
		rebuild.call()))
	var m = Admin.local_manager()
	ft.left.text = Loc.t("Verwalter: %s") % m.display_name if m else Loc.t("Kein Verwalter")
	Win.set_left2(ft, Sea.island_name(b.world) if b != null and Sea.settled_islands().size() > 1 else "")
	if b == null and _tab < 4:
		var l := UiTheme.label(Loc.t("Baue zuerst die Verwaltung (Bauen, Reiter Wissen). Dann findest du hier den Verwalter, Schichten und Überstunden."), 14, UiTheme.BAD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
		return
	match _tab:
		0: _manager_tab(hud, b)
		1: _orders_tab(hud, b, "sh")
		2: _night_tab(hud, b)
		3: _orders_tab(hud, b, "ot")
		_: _stats_tab(hud, b)


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
		if kind == "ot" and Admin.protesting(job):
			r.button.disabled = true
			r.button.tooltip_text = Loc.t("Protest gegen zu lange Überstunden")
		_box.add_child(r.box)


## Statistik (josh 2026-10-20): Auslastung je Beruf (alle Inseln) und was im letzten und im laufenden
## Jahr erzeugt wurde.
static func _stats_tab(_hud, _b) -> void:
	_box.add_child(UiTheme.label(Loc.t("Auslastung der Berufe"), 15, UiTheme.TEXT, true))
	var load := Admin.job_load()
	var jobs := load.keys()
	jobs.sort_custom(func(a, c): return int(load[a][1]) > int(load[c][1]))
	if jobs.is_empty():
		_box.add_child(UiTheme.label(Loc.t("Noch hat niemand einen Beruf."), 13, DIM))
	for job in jobs:
		if not Data.jobs.has(job):
			continue
		var p: int = load[job][1]
		var r := Win.row(Data.icon("person"), Data.jobs[job].name,
			Loc.t("Siedler: %d") % int(load[job][0]), {"icon_px": 28,
			"value": ("%d %%" % p) if p >= 0 else "–",
			"value_color": UiTheme.GOOD if p >= 70 else (UiTheme.ACCENT if p >= 40 else UiTheme.BAD)})
		r.box.tooltip_text = Loc.t("Anteil der Zeit, in der die Leute in ihrem Beruf arbeiten (statt auszuhelfen oder nichts zu tun).")
		_box.add_child(r.box)
	var y := Seasons.year()
	var last := Admin.produced_in(y - 1)
	var now := Admin.produced_in(y)
	var hd := UiTheme.label(Loc.t("Erzeugte Waren: Jahr %d · bisher Jahr %d") % [y - 1, y] if y > 1 else Loc.t("Erzeugte Waren im Jahr %d (bisher)") % y, 15, UiTheme.TEXT, true)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(hd)
	var goods := []
	for id in Data.sorted_resource_ids():
		if int(last.get(id, 0)) > 0 or int(now.get(id, 0)) > 0:
			goods.append(id)
	if goods.is_empty():
		_box.add_child(UiTheme.label(Loc.t("Noch nichts gezählt. Gezählt wird, was gesammelt, geerntet, gejagt und in Werkstätten hergestellt wird."), 13, DIM))
	for id in goods:
		var v := "%d" % int(last.get(id, 0)) if y > 1 else ""
		v += ("  ·  " if v != "" else "") + "%d" % int(now.get(id, 0))
		_box.add_child(Win.row(Data.res_icon(id), Data.resource_name(id), "", {"icon_px": 24, "value": v}).box)


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
