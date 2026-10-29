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


static var _tab := 0  # Reiter im Fenster Verwalter (josh 2026-10-29): Befugnisse, Vorschläge, Vorräte, Inseln, Arbeitszeit, Statistik, Log
static var _task_island := -1  # Reiter Inseln: für diese Insel ist die Auswahl der Spezialisierung offen
static var _min_island := -1  # Reiter Vorräte: Insel, deren Mindestvorräte gezeigt werden
const TAB_POWERS := 0
const TAB_PROPOSALS := 1
const TAB_STOCK := 2
const TAB_ISLANDS := 3
const TAB_HOURS := 4
const TAB_STATS := 5
const TAB_LOG := 6
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


## Fenster Verwalter (josh 2026-10-29): Reiter Befugnisse, Vorschläge, Vorräte, Inseln, Arbeitszeit, Statistik, Log.
## box: Inhalt, rebuild: baut ihn neu auf, ft: Win.footer.
static func fill_window(hud, b, box: Container, rebuild: Callable, ft: Dictionary) -> void:
	_box = box
	_rebuild = rebuild
	var np := Powers.proposals.size()
	var names := [Loc.t("Befugnisse"), Loc.t("Vorschläge (%d)") % np if np > 0 else Loc.t("Vorschläge"), Loc.t("Vorräte"), Loc.t("Inseln"),
		Loc.t("Arbeitszeit"), Loc.t("Statistik"), Loc.t("Log")]
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
		TAB_PROPOSALS: _proposals_tab(hud)
		TAB_STOCK: _stock_tab(hud, b)
		TAB_ISLANDS: _islands_tab(hud)
		TAB_HOURS:
			_box.add_child(UiTheme.label(Loc.t("Überstunden"), 15, UiTheme.TEXT, true))
			_orders_tab(hud, b, "ot")
			_box.add_child(UiTheme.label(Loc.t("Schichtarbeit (auch nachts)"), 15, UiTheme.TEXT, true))
			_orders_tab(hud, b, "sh")
		TAB_LOG: _log_tab()
		_: _stats_tab(hud, b)


## Reiter Befugnisse: Verwalter, Ausbaustufe, Tagesbilanz, Essen und Wärme, dann alle Befugnisse mit
## den Schaltern Aus / Fragen / Selbst (gesperrte grau mit dem, was fehlt).
static func _powers_tab(_hud, b) -> void:
	Powers.seen_level = maxi(Powers.seen_level, Admin.level())
	var m = Admin.local_manager()
	var away = Admin.manager()
	var head_text := Loc.t("Verwalter: %s") % m.display_name if m else Loc.t("Kein Verwalter! Gib einem Siedler den Beruf Verwalter.")
	if m == null and away != null:
		head_text = Loc.t("Der Verwalter %s lebt auf einer anderen Insel (%s). Er arbeitet nur, wenn er auf der Insel der Verwaltung lebt.") % [away.display_name, Sea.island_name(away.world)]
	var head := UiTheme.label(head_text, 14, UiTheme.TEXT if m else UiTheme.BAD, true)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(head)
	var lv := Admin.office_level()
	var stage := "%s (%s)" % [Loc.t("Stufe %d von 7") % lv, b.def.name]
	if not b.complete:
		stage += " · " + Loc.t("Ausbau zu %s läuft") % b.def.name
	elif b.def.has("upgrade"):
		var nd: Dictionary = Data.buildings[b.def.upgrade]
		stage += "\n" + (Loc.t("Nächster Ausbau: %s, im Infofenster der Verwaltung.") % nd.name if Game.is_unlocked(b.def.upgrade)
			else Loc.t("Nächster Ausbau: %s nach der Forschung %s.") % [nd.name, Data.techs.get(nd.requires, {}).get("name", "?")])
	_note(stage, UiTheme.TEXT)
	var today := Powers.tally(true)
	var year := Powers.tally(false)
	var fmt := func(t: Dictionary) -> String:
		return Loc.t("%d Berufe · %d Fahrten · %d Anordnungen · %d Forschungen") % [int(t.get("job", 0)), int(t.get("trip", 0)), int(t.get("order", 0)), int(t.get("research", 0))]
	_box.add_child(Win.row(Data.icon("sonne"), Loc.t("Für dich erledigt"), Loc.t("Heute: %s") % fmt.call(today) + "\n" + Loc.t("Dieses Jahr: %s") % fmt.call(year), {"icon_px": 28}).box)
	if Powers.unlocked("essen_waerme"):
		var si := Steward.secure_info(b.world)
		var f: Array = si.food
		var h: Array = si.fuel
		var txt := Loc.t("Essen: braucht %d in 3 Tagen, Vorrat %d, Leute %d von %d nötig") % [int(f[0]), int(f[1]), int(f[3]), int(f[2])]
		txt += "\n" + Loc.t("Brennstoff: braucht %d in 3 Tagen, Vorrat %d, Holzfäller %d von %d nötig") % [int(h[0]), int(h[1]), int(h[3]), int(h[2])]
		var bad: bool = int(f[3]) < int(f[2]) or int(h[3]) < int(h[2])
		_box.add_child(Win.row(Data.icon("weizen"), Loc.t("Essen und Wärme"), txt, {"icon_px": 28, "sub_color": UiTheme.BAD if bad else DIM}).box)
	var last := 0
	for p in Powers.LIST:
		var lvl := int(p.level)
		if lvl != last:
			last = lvl
			var od: Dictionary = {}
			for k in Data.buildings:
				if int(Data.buildings[k].get("office_level", 0)) == lvl and Data.buildings[k].get("office", false):
					od = Data.buildings[k]
			_box.add_child(UiTheme.label(Loc.t("Stufe %d: %s") % [lvl, od.get("name", "")], 14, UiTheme.TEXT if lv >= lvl else DIM, true))
		_power_row(p)


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
		for mi in [Powers.AUS, Powers.FRAGEN, Powers.SELBST]:
			var label: String = [Loc.t("Aus"), Loc.t("Fragen"), Loc.t("Selbst")][mi]
			var mm: int = mi
			chips.add_child(Win.chip(label, Powers.mode_of(id) == mi, func(_on):
				Powers.set_mode(id, mm)
				_rebuild.call()))
		r.text.add_child(chips)
	_box.add_child(r.box)


## Reiter Vorschläge: was der Verwalter auf „Fragen“ tun würde, mit Ja und Nein.
static func _proposals_tab(_hud) -> void:
	if Powers.proposals.is_empty():
		_note(Loc.t("Keine Vorschläge. Steht eine Befugnis auf „Fragen“, schlägt der Verwalter hier vor, was er tun würde."))
		return
	var all := UiTheme.button(Loc.t("Alle annehmen"), "play", 36)
	all.pressed.connect(func():
		Powers.answer_all()
		_rebuild.call())
	_box.add_child(all)
	for i in Powers.proposals.size():
		var p: Dictionary = Powers.proposals[i]
		var info := Powers.info(str(p.power))
		var r := Win.row(Data.icon(info.get("icon", "person")), Loc.t(info.get("name", "")), str(p.text), {"icon_px": 28, "sub_color": UiTheme.TEXT})
		var bh := HBoxContainer.new()
		var idx: int = i
		var yes := UiTheme.button(Loc.t("Ja"), "", 34)
		yes.pressed.connect(func():
			Powers.answer(idx, true)
			_rebuild.call())
		var no := UiTheme.button(Loc.t("Nein"), "", 34)
		no.pressed.connect(func():
			Powers.answer(idx, false)
			_rebuild.call())
		bh.add_child(yes)
		bh.add_child(no)
		r.h.add_child(bh)
		_box.add_child(r.box)


## Reiter Vorräte: Mindestvorrat je Ware für eine Insel (Befugnis Mindestvorräte, auch Ziel für Fahrten).
static func _stock_tab(_hud, b) -> void:
	var worlds: Array = Sea.all_worlds().filter(func(w): return Powers.covers(w))
	if worlds.is_empty():
		worlds = [b.world]
	if _min_island < 0 or not worlds.any(func(w): return int(w.island_id) == _min_island):
		_min_island = int(b.world.island_id)
	if worlds.size() > 1:
		var chips := Win.chip_row()
		for w in worlds:
			var iid := int(w.island_id)
			chips.add_child(Win.chip(Sea.island_name(w), iid == _min_island, func(_on):
				_min_island = iid
				_rebuild.call()))
		_box.add_child(chips)
	var w = Sea.worlds.get(_min_island, b.world)
	_note(Loc.t("Mindestvorrat: Liegt weniger da, schickt der Verwalter Siedler in den passenden Beruf (Befugnis Mindestvorräte) oder holt die Ware per Schiff (Waren ausgleichen)."))
	if not Powers.unlocked("mindestvorrat"):
		_note(Loc.t("Der Verwalter richtet sich erst ab Stufe 2 (Amtshaus) danach."), UiTheme.BAD)
	var ids := []
	for id in Data.resources:
		var rd: Dictionary = Data.resources[id]
		if rd.get("hidden", false) or id in ["droide", "strom", "boot"]:
			continue
		if Game.amount(id, w) > 0 or Steward.limits(int(w.island_id), id)[0] > 0 or Steward._producer(w, id) != "":
			ids.append(id)
	for id in ids:
		var gid: String = id
		var iid := int(w.island_id)
		var mn: int = Steward.limits(iid, gid)[0]
		var have := Game.amount(gid, w)
		var r := Win.row(Data.res_icon(gid), Data.resource_name(gid), Loc.t("im Lager %d") % have,
			{"icon_px": 24, "value": str(mn) if mn > 0 else "–", "value_color": UiTheme.BAD if mn > 0 and have < mn else UiTheme.TEXT})
		for step in [-10, 10]:
			var st: int = step
			var bt := UiTheme.button("%+d" % st, "", 34)
			bt.custom_minimum_size.x = 48
			bt.pressed.connect(func():
				var lim: Array = Steward.limits(iid, gid)
				lim[0] = maxi(0, int(lim[0]) + st)
				if int(lim[1]) > 0 and lim[0] > lim[1]:
					lim[1] = lim[0]
				Steward.set_limits(iid, gid, lim[0], lim[1])
				AiRule.player_changed("minmax")
				_rebuild.call())
			r.h.add_child(bt)
		_box.add_child(r.box)


## Reiter Inseln (josh 2026-10-21: die Verwaltung der Inseln gehört zum Verwalter): Verwalter steuert die
## Berufe (Steward), Inselverbund mit Rundfunkanstalten, Spezialisierung (Hauptaufgabe) je Insel.
static func _islands_tab(_hud) -> void:
	for m in Sea.settled_islands():
		var w = Sea.worlds.get(int(m.id))
		if w == null:
			continue
		var why := Steward.blocked_on(w)
		_note(Loc.t("%s: vom Verwalter verwaltet.") % m.name if why == "" else Loc.t("%s: %s") % [m.name, why], DIM if why == "" else UiTheme.BAD)
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
	_note(Loc.t("Bleibt ein Siedler einen Tag frei, gibt ihm der Verwalter zuerst einen Beruf der Hauptaufgabe."))
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
	# Die letzten 5 Jahre und das laufende Jahr (josh 2026-10-28)
	var y := Seasons.year()
	var years := []
	for k in range(maxi(1, y - 5), y + 1):
		years.append(k)
	var per := {}
	for k in years:
		per[k] = Admin.produced_in(k, w)
	_box.add_child(UiTheme.label(Loc.t("Erzeugte Waren"), 15, UiTheme.TEXT, true))
	var goods := []
	for id in Data.sorted_resource_ids():
		if years.any(func(k): return int(per[k].get(id, 0)) > 0):
			goods.append(id)
	if goods.is_empty():
		var e := UiTheme.label(Loc.t("Noch nichts gezählt. Gezählt wird, was gesammelt, geerntet, gejagt und in Werkstätten hergestellt wird."), 13, DIM)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(e)
		return
	var head := Win.row(null, "", "", {})
	head.box.self_modulate = Color(1, 1, 1, 0)
	_cols(head.h, years.map(func(k): return (Loc.t("J. %d") % k) + ("*" if k == y else "")), DIM)
	_box.add_child(head.box)
	for id in goods:
		var r := Win.row(Data.res_icon(id), Data.resource_name(id), "", {"icon_px": 24})
		_cols(r.h, years.map(func(k): return str(int(per[k].get(id, 0)))), UiTheme.TEXT)
		_box.add_child(r.box)
	var star := UiTheme.label(Loc.t("J. = Jahr, * = laufendes Jahr bis jetzt."), 12, DIM)
	_box.add_child(star)
	var note := UiTheme.label(Loc.t("Gezählt wird seit dem Update vom 20. Oktober, was auf dieser Insel gesammelt, geerntet, gejagt und in Werkstätten hergestellt wird, nicht was Schiffe bringen oder Händler verkaufen. Ein Jahr hat vier Jahreszeiten."), 12, DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(note)


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
