class_name AdminTest
extends RefCounted
## Selbsttest --admintest=1 (Admin.autotest_setup): Verwaltung nur einmal, nur ein Verwalter,
## Meldung bei fehlendem Personal, Vertretung in einer Werkstatt, Überstunden mit Protest nach einem
## Jahr, Schichtarbeit (Hälfte arbeitet nachts, Laune) und Spielstand. Druckt "Verwaltung OK/FEHLER".

static var fails := 0


static func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("Verwaltung ", "OK " if c else "FEHLER ", what)


static func _wait(main, cond: Callable, max_s: float) -> bool:
	var t := 0.0
	while not cond.call() and t < max_s:
		await main.get_tree().create_timer(0.25, true, false, true).timeout
		t += 0.25
	return cond.call()


static func run(main) -> void:
	fails = 0
	var w = main.world
	for t in ["gelehrsamkeit", "holzbearbeitung", "steinwerkzeuge"]:
		if not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()
	_ok(not Admin.active(), "ohne Verwaltung nicht aktiv")
	_ok(main._place_on(w, "verwaltung"), "Verwaltung gebaut")
	_ok(not w.can_place("verwaltung", w.center + Vector2i(8, 8)) and not main._place_on(w, "verwaltung"), "zweite Verwaltung geht nicht")
	_ok(not Admin.active(), "ohne Verwalter nicht aktiv")
	var c: Vector2i = w.settlers[0].cell
	var mk := func(n: String, job: String):
		var s = w.spawn_settler({"name": n, "sex": "m", "age": 30.0, "max_age": 70.0, "x": c.x, "y": c.y, "skills": {},
			"mind": {"traits": {}, "talents": {}}})
		s.hunger = 100.0
		s.set_job(job)
		return s
	var v1 = mk.call("V1", "verwalter")
	var v2 = mk.call("V2", "frei")
	v2.set_job("verwalter")
	_ok(Admin.active() and Admin.manager() == v2 and v1.job == "frei", "nur ein Verwalter (V1 jetzt %s)" % v1.job)
	# Werkstatt ohne Handwerker: Meldung mit Vorschlag
	_ok(main._place_on(w, "saegegrube"), "Sägegrube gebaut")
	var saw = null
	for b in w.buildings:
		if b.type == "saegegrube":
			saw = b
	Game.add_stock("holz", 60, w)
	for s in w.settlers:
		if s.job == "handwerker":
			s.set_job("frei")
	var props := []
	var cb := func(job, text): props.append([job, text])
	Admin.proposal.connect(cb)
	Admin.reported.clear()
	Admin._tick()
	Admin.proposal.disconnect(cb)
	if AdminInfo._dialog and is_instance_valid(AdminInfo._dialog):
		AdminInfo._dialog.queue_free()
	print("Verwaltung: fehlt ", Admin.shortages(), " Vorschlag ", props)
	_ok(props.size() == 1 and props[0][0] == "handwerker", "Verwalter meldet fehlende Handwerker")
	# Vertretung: ein freier Siedler arbeitet in der Sägegrube
	Game.add_stock("beeren", 80, w)  # genug Essen: Freie sammeln sonst zuerst Nahrung
	saw.adm = true
	var b0 := Game.amount("bretter", w)
	var got: bool = await _wait(main, func(): return not saw.occupants.is_empty() or Game.amount("bretter", w) > b0, 30.0)
	var who := []
	for s in w.settlers:
		if s.id in saw.occupants:
			who.append("%s (%s): %s" % [s.display_name, s.job, s.activity])
	print("Verwaltung: Vertretung ", who, " Bretter ", b0, " -> ", Game.amount("bretter", w))
	_ok(got, "Vertretung in der Sägegrube")
	saw.adm = false
	# Mit eigener Fachkraft keine Vertretung nötig
	var h1 = mk.call("H1", "handwerker")
	var h2 = mk.call("H2", "handwerker")
	saw.adm = true
	h1.sleeping = false
	h2.sleeping = false
	_ok(not Admin.needs_standin(w, "handwerk"), "Fachkraft da: keine Vertretung")
	# Überstunden und Protest nach einem Jahr
	_ok(Admin.set_overtime("handwerker", true) == "" and Admin.overtime("handwerker"), "Überstunden angeordnet")
	h1.mind.rest = 10.0
	var wants: bool = h1.mind.wants_break()
	h1._think()
	_ok(not h1.on_break(), "Überstunden: keine Pause (wollte Pause: %s)" % wants)
	Admin.orders["handwerker"]["since"] = Game.time_days - Seasons.year_days() - 0.1
	Admin._tick()
	_ok(not Admin.ordered("handwerker", "ot") and Admin.protesting("handwerker"), "nach einem Jahr Protest, Überstunden aus")
	_ok(Admin.set_overtime("handwerker", true) != "", "während des Protests keine neuen Überstunden")
	var rs: Array = Admin.mood_reasons(h1)
	_ok(rs.size() == 1 and float(rs[0][1]) < 0.0, "Protest senkt die Laune %s" % [rs])
	Admin.protest.clear()
	# Schichtarbeit: Hälfte arbeitet nachts, Laune eine Stufe schlechter
	Admin.set_shift("handwerker", true)
	var nw := [Admin.night_worker(h1), Admin.night_worker(h2)]
	var parity_ok: bool = (int(h1.id) + int(h2.id)) % 2 == 0 or nw[0] != nw[1]
	_ok(parity_ok, "Schicht: je Nacht arbeitet eine Hälfte %s" % [nw])
	rs = Admin.mood_reasons(h1)
	_ok(rs.size() == 1 and float(rs[0][1]) <= -20.0, "Schichtarbeit: Laune eine Stufe schlechter %s" % [rs])
	var at_night: bool = await _wait(main, func(): return Game.is_night(), 60.0)
	await main.get_tree().create_timer(2.0, true, false, true).timeout
	var night := []
	for s in [h1, h2]:
		night.append("%s Nachtschicht=%s schläft=%s %s" % [s.display_name, Admin.night_worker(s), s.sleeping, s.activity])
	print("Verwaltung: Nacht ", night)
	var worker = h1 if Admin.night_worker(h1) else (h2 if Admin.night_worker(h2) else null)
	_ok(at_night and worker != null and not worker.sleeping, "Schicht: ein Handwerker arbeitet nachts")
	# Spielstand
	var d := {}
	Admin._on_save(d)
	d = JSON.parse_string(JSON.stringify(d))
	var keep: Dictionary = Admin.orders.duplicate(true)
	Admin._on_load(d, 9)
	_ok(Admin.ordered("handwerker", "sh") and Admin.orders.keys() == keep.keys(), "Anordnungen bleiben gespeichert")
	_ok(bool(saw.serialize().adm), "Vertretung steht im Gebäude")
	var old := Admin.orders.duplicate(true)
	Admin._on_load({}, 0)
	_ok(Admin.orders.is_empty(), "alter Spielstand: keine Anordnungen")
	Admin.orders = old
	Admin.set_shift("handwerker", false)
	print("Verwaltung %s (%d Fehler)" % ["OK" if fails == 0 else "FEHLER", fails])


## Bildschirmfoto-Hilfe --adminshot=office|workshop|proposal: Verwaltung, Verwalter und Sägegrube
## mit Vertretung; danach Infofenster bzw. das Vorschlagsfenster.
static func shot(main, kind: String) -> void:
	var w = main.world
	for t in ["gelehrsamkeit", "holzbearbeitung", "steinwerkzeuge"]:
		if not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()
	main._place_on(w, "verwaltung")
	main._place_on(w, "saegegrube")
	w.settlers[1].set_job("verwalter")
	Game.add_stock("holz", 30, w)
	if kind != "proposal":
		Admin.set_overtime("koch", true)
		Admin.set_shift("handwerker", true)
	for b in w.buildings:
		if b.type == "saegegrube":
			b.adm = true
			if kind == "workshop":
				Game.select(b)
		if b.type == "verwaltung" and kind == "office":
			Game.select(b)
	if kind == "proposal":
		Admin.reported.clear()
		Admin._tick()
