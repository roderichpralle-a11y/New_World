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
	if not Admin.active():
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


## Berufe, für die die Verwaltung Anordnungen zeigt: die Werkstattberufe und jeder Beruf mit Leuten.
static func _jobs() -> Array:
	var out: Array = Admin.KIND_JOB.values()
	for w in Sea.all_worlds():
		for s in w.settlers:
			if s.is_adult() and not s.job in out and not s.job in ["frei", Admin.JOB]:
				out.append(s.job)
	return out.filter(func(j): return Data.jobs.has(j) and (Data.job_unlocked(j) or Admin.ordered(j, "ot") or Admin.ordered(j, "sh")))


static func _count(job: String) -> int:
	var n := 0
	for w in Sea.all_worlds():
		n += w.settlers.filter(func(s): return s.job == job and s.is_adult()).size()
	return n


## Infofenster der Verwaltung: Verwalter, fehlendes Personal und Anordnungen je Beruf.
static func office_rows(hud, b) -> void:
	if not b.complete:
		return
	var m = Admin.manager()
	var head := UiTheme.label(Loc.t("Verwalter: %s") % m.display_name if m else Loc.t("Kein Verwalter! Gib einem Siedler den Beruf Verwalter."),
		14, UiTheme.TEXT if m else UiTheme.BAD, true)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud._info_box.add_child(head)
	var short := {}
	for e in Admin.shortages():
		short[e[0]] = e
	hud._info_box.add_child(UiTheme.label(Loc.t("Anordnungen"), 15, UiTheme.TEXT, true))
	var hint := UiTheme.label(Loc.t("Überstunden: keine Pausen, höchstens ein Jahr am Stück. Schichtarbeit: jede Nacht arbeitet die Hälfte durch, Laune eine Stufe schlechter."), 12, DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud._info_box.add_child(hint)
	for job in _jobs():
		var t := "%s (%d)" % [Data.jobs[job].name, _count(job)]
		var col := UiTheme.TEXT
		if short.has(job):
			t += "  " + Loc.t("fehlen: %d") % (int(short[job][1]) - int(short[job][2]))
			col = UiTheme.BAD
		hud._info_box.add_child(UiTheme.label(t, 14, col, true))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		hud._info_box.add_child(row)
		var ot: bool = Admin.ordered(job, "ot")
		var ob := UiTheme.button(Loc.t("Überstunden: an") if ot else Loc.t("Überstunden: aus"), "", 32)
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.add_theme_font_size_override("font_size", 13)
		if Admin.protesting(job):
			ob.disabled = true
			ob.tooltip_text = Loc.t("Protest gegen zu lange Überstunden")
		var jid: String = job
		ob.pressed.connect(func():
			var err := Admin.set_overtime(jid, not Admin.ordered(jid, "ot"))
			if err != "":
				hud.toast(err, "wissen")
			hud._rebuild_info())
		row.add_child(ob)
		var sh: bool = Admin.ordered(job, "sh")
		var sb := UiTheme.button(Loc.t("Schicht: an") if sh else Loc.t("Schicht: aus"), "", 32)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.add_theme_font_size_override("font_size", 13)
		sb.pressed.connect(func():
			Admin.set_shift(jid, not Admin.ordered(jid, "sh"))
			hud._rebuild_info())
		row.add_child(sb)
		var note := ""
		if ot:
			var left := Seasons.year_days() * float(Admin.cfg.get("overtime_years", 1.0)) - (Game.time_days - float(Admin.orders[job].since))
			note = Loc.t("Überstunden noch höchstens %d Tage.") % maxi(0, ceili(left))
		if Admin.protesting(job):
			note = Loc.t("Protest gegen zu lange Überstunden: noch %d Tage.") % maxi(1, ceili(float(Admin.protest[job]) - Game.time_days))
		if note != "":
			hud._info_box.add_child(UiTheme.label(note, 12, DIM))


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
	var d := UiTheme.label(Loc.t("Überstunden: keine Pausen, höchstens ein Jahr am Stück. Schichtarbeit: jede Nacht arbeitet die Hälfte durch, Laune eine Stufe schlechter."), 12, DIM)
	d.custom_minimum_size.x = 300
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var close := func():
		if is_instance_valid(bg):
			bg.queue_free()
		_dialog = null
		hud._rebuild_info()
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
