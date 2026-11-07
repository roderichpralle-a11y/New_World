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


static var _tab := 0  # Reiter im Fenster Verwalter (josh 2026-11-07): nur noch Befugnisse, Arbeitszeit, Log
const TAB_POWERS := 0
const TAB_HOURS := 1
const TAB_LOG := 2
static var _box: Container  # hierhin bauen die Reiter ihre Zeilen (Fenster Verwalter oder Infofenster)
static var _rebuild: Callable  # baut das Fenster neu auf


## Infofenster der Verwaltung: Knopf zum Fenster Verwalter und die Ausbaustufe.
static func office_rows(hud, b) -> void:
	_box = hud._info_box
	_rebuild = hud._rebuild_info
	var lv := int(b.def.get("office_level", 1))
	var l := UiTheme.label(Loc.t("Ausbaustufe %d von 7") % lv, 13, DIM)
	_box.add_child(l)
	if b.complete:
		var bt := UiTheme.button(Loc.t("Fenster Verwalter öffnen"), "person", 40)
		bt.pressed.connect(hud._open_admin)
		_box.add_child(bt)


## Fenster Verwalter (josh 2026-10-29, 2026-11-07 nur noch drei Reiter): Befugnisse, Arbeitszeit, Log.
## box: Inhalt, rebuild: baut ihn neu auf, ft: Win.footer.
static func fill_window(hud, b, box: Container, rebuild: Callable, ft: Dictionary) -> void:
	_box = box
	_rebuild = rebuild
	var names := [Loc.t("Befugnisse"), Loc.t("Arbeitszeit"), Loc.t("Log")]
	if _tab < 0 or _tab >= names.size():
		_tab = TAB_POWERS
	box.add_child(Win.tabs(names, _tab, func(i):
		_tab = i
		rebuild.call()))
	var m = Admin.local_manager()
	ft.left.text = Loc.t("Verwalter: %s") % m.display_name if m else Loc.t("Kein Verwalter")
	Win.set_left2(ft, Sea.island_name(b.world) if b != null and Sea.settled_islands().size() > 1 else "")
	if b == null and _tab != TAB_LOG:
		var l := UiTheme.label(Loc.t("Baue zuerst die Verwaltung (Bauen, Reiter Wissen) und gib einem Siedler den Beruf Verwalter. Mit jedem Ausbau der Verwaltung übernimmt er mehr Aufgaben."), 14, UiTheme.BAD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
		return
	match _tab:
		TAB_POWERS: _powers_tab(hud, b)
		TAB_HOURS:
			_box.add_child(UiTheme.label(Loc.t("Überstunden"), 15, UiTheme.TEXT, true))
			_orders_tab(hud, b, "ot")
			_box.add_child(UiTheme.label(Loc.t("Schichtarbeit (auch nachts)"), 15, UiTheme.TEXT, true))
			_orders_tab(hud, b, "sh")
		_: _log_tab()


## Reiter Befugnisse: Verwalter, Tagesbilanz, dann die Befugnisse (Nachbesetzen, Auslastung) mit den Schaltern
## Aus / Selbst (josh 2026-11-07: alle anderen Befugnisse und Stufen sind gestrichen).
static func _powers_tab(_hud, _b) -> void:
	Powers.seen_level = maxi(Powers.seen_level, Admin.level())
	var m = Admin.local_manager()
	var away = Admin.manager()
	var head_text := Loc.t("Verwalter: %s") % m.display_name if m else Loc.t("Kein Verwalter! Gib einem Siedler den Beruf Verwalter.")
	if m == null and away != null:
		head_text = Loc.t("Der Verwalter %s lebt auf einer anderen Insel (%s). Er arbeitet nur, wenn er auf der Insel der Verwaltung lebt.") % [away.display_name, Sea.island_name(away.world)]
	var head := UiTheme.label(head_text, 14, UiTheme.TEXT if m else UiTheme.BAD, true)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(head)
	var today := int(Powers.tally(true).get("job", 0))
	var year := int(Powers.tally(false).get("job", 0))
	_box.add_child(Win.row(Data.icon("sonne"), Loc.t("Für dich erledigt"), Loc.t("Berufe vergeben: heute %d, dieses Jahr %d") % [today, year], {"icon_px": 28}).box)
	# Nebeninsel ohne Rundfunkanstalt hier und auf der Insel der Verwaltung: hier gibt es keinen Verwalter und nichts
	# zu wählen (josh 2026-11-07)
	if Game.world != null and not Sea.is_main(Game.world) and not Powers.covers(Game.world):
		var note := UiTheme.label(Loc.t("Auf %s arbeitet der Verwalter nicht. Hier teilst nur du ein, bis auf dieser Insel und auf der Insel der Verwaltung eine Rundfunkanstalt steht.") % Sea.island_name(Game.world), 14, UiTheme.BAD, true)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(note)
		return
	if KiBrain.available:  # nur unter /v21test2/?ki (josh 2026-11-07)
		_ki_row()
	for p in Powers.LIST:
		_power_row(p)


## Umschalter Verwalter / lernende KI für die Berufe (josh 2026-11-07, Testversion).
static func _ki_row() -> void:
	var sub := Loc.t("Wer teilt die Berufe ein? Die lernende KI wurde ab deinem Spielstand Tag 163 trainiert: Punkte für Nahrungstage im Lager, Holz (bis 1000), verarbeitete Waren (mehr für Waren, die der Forschung fehlen), Forschungspunkte, fertige Forschungen, satte und zufriedene Siedler, Abzug für jeden Toten. Sie vergibt Holzfäller, Steinmetze, Sammler, Fischer, Bauern, Köche, Handwerker, Jäger und Forscher, Baumeister nach den Baustellen. Hast du keine Forschung gewählt, startet sie die nächste der Liste und baut die Werkstatt, die dafür fehlt. Verwalter, Seeleute und Siedler, die nur du einteilst, lässt sie, wie sie sind.")
	if KiBrain.weights.is_empty():
		sub = Loc.t("Noch keine trainierte KI in dieser Version.")
	elif KiBrain.brain_score > 0:
		sub += "\n" + Loc.t("Prüfung über ein Spieljahr (12 Tage) ab Tag 163: %d Punkte, untrainiert %d.") % [KiBrain.brain_score, KiBrain.brain_base]
	var r := Win.row(Data.icon("ki"), Loc.t("Berufe vergeben"), sub, {"icon_px": 28, "hi": KiBrain.on})
	if not KiBrain.weights.is_empty():
		var chips := Win.chip_row()
		chips.add_child(Win.chip(Loc.t("Verwalter"), not KiBrain.on, func(_on):
			KiBrain.set_on(false)
			_rebuild.call()))
		chips.add_child(Win.chip(Loc.t("Lernende KI"), KiBrain.on, func(_on):
			KiBrain.set_on(true)
			_rebuild.call()))
		r.text.add_child(chips)
	_box.add_child(r.box)


static func _power_row(p: Dictionary) -> void:
	var id: String = p.id
	var ok := Powers.unlocked(id)
	var sub: String = Loc.t(p.desc)
	if not ok:
		var od: Dictionary = {}
		for k in Data.buildings:
			if int(Data.buildings[k].get("office_level", 0)) == int(p.level) and Data.buildings[k].get("office", false):
				od = Data.buildings[k]
		sub = Loc.t("Fehlt: Ausbau der Verwaltung zu %s (Forschung %s).") % [od.get("name", "?"), Data.techs.get(od.get("requires", ""), {}).get("name", "?")] + "\n" + sub
	var r := Win.row(Data.icon(p.icon), Loc.t(p.name), sub, {"icon_px": 28, "hi": ok and Powers.mode_of(id) == Powers.SELBST})
	if not ok:
		r.box.modulate = Color(1, 1, 1, 0.6)
	else:
		var chips := Win.chip_row()
		for mi in [Powers.AUS, Powers.SELBST]:  # ohne Fragen (josh 2026-11-07: kein Reiter Vorschläge mehr)
			var label: String = Loc.t("Aus") if mi == Powers.AUS else Loc.t("Selbst")
			var mm: int = mi
			chips.add_child(Win.chip(label, Powers.mode_of(id) == mi, func(_on):
				Powers.set_mode(id, mm)
				_rebuild.call()))
		r.text.add_child(chips)
	_box.add_child(r.box)


static func _note(t: String, col: Color = DIM) -> void:
	var l := UiTheme.label(t, 12, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(l)


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


## Reiter Log (josh 2026-10-28): was Verwalter, Automat, KI und Droiden entschieden haben, neueste zuerst.
static func _log_tab() -> void:
	var entries: Array = Admin.log_entries
	if entries.is_empty():
		_note(Loc.t("Noch keine Entscheidungen. Hier steht später alles, was der Verwalter (und später Automat und KI) anordnet oder umstellt."))
		return
	var hint := UiTheme.label(Loc.t("Die letzten %d Entscheidungen, neueste oben.") % entries.size(), 12, DIM)
	_box.add_child(hint)
	for i in range(entries.size() - 1, -1, -1):
		var e: Array = entries[i]
		var t: float = e[0]
		var hour := int(fposmod(t, 1.0) * 24.0)
		var when := Loc.t("Jahr %d, %s Tag %d, %d Uhr") % [Seasons.year(t), Seasons.season_name(Seasons.season(t)), Seasons.day_in_season(t), hour]
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.add_child(UiTheme.label(when, 11, DIM))
		var l := UiTheme.label(str(e[2]), 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
		_box.add_child(v)


## Rechtsbündige Zahlenspalten fester Breite am Ende einer Zeile (bis zu 6 Jahre).
static func _cols(h: Container, texts: Array, col: Color) -> void:
	for t in texts:
		var l := UiTheme.label(str(t), 13 if col == UiTheme.TEXT else 12, col, col == UiTheme.TEXT)
		l.custom_minimum_size.x = 48
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
