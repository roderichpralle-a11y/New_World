class_name AdminTest
extends RefCounted
## Selbsttest --admintest=1 (Admin.autotest_setup): Verwaltung nur einmal, nur ein Verwalter,
## Meldung bei fehlendem Personal, Vertretung in einer Werkstatt, Überstunden mit Protest nach einem
## Jahr, Schichtarbeit (alle arbeiten nachts, Nacht läuft normal schnell, Lampe, Laune) und Spielstand. Druckt "Verwaltung OK/FEHLER".

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
	_ok(Admin.set_overtime("handwerker", true) == "" and Admin.overtime("handwerker", w), "Überstunden angeordnet")
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
	# Schichtarbeit: alle des Berufs arbeiten nachts, Laune eine Stufe schlechter (bremst die Arbeit aber nicht)
	Admin.set_shift("handwerker", true)
	var nw := [Admin.night_worker(h1), Admin.night_worker(h2)]
	_ok(nw[0] and nw[1], "Schicht: alle Handwerker arbeiten nachts %s" % [nw])
	_ok(Admin.work_mult(h1) > 1.0, "Schicht: schnellere Arbeit %.2f" % Admin.work_mult(h1))
	var m0: float = h1.mind.mood
	h1.mind.mood = 30.0  # Schicht: 30 Laune wiegt bei der Arbeit wie 50 ohne Schicht
	var wf_shift: float = h1.mind.mood_work_factor()
	Admin.set_shift("handwerker", false)
	h1.mind.mood = 50.0
	var wf_plain: float = h1.mind.mood_work_factor()
	h1.mind.mood = m0
	Admin.set_shift("handwerker", true)
	_ok(is_equal_approx(wf_shift, wf_plain), "Schicht-Laune bremst die Arbeit nicht %.2f %.2f" % [wf_shift, wf_plain])
	rs = Admin.mood_reasons(h1)
	_ok(rs.size() == 1 and float(rs[0][1]) <= -20.0, "Schichtarbeit: Laune eine Stufe schlechter %s" % [rs])
	var at_night: bool = await _wait(main, func(): return Game.is_night(), 60.0)
	await main.get_tree().create_timer(2.0, true, false, true).timeout
	var night := []
	for s in [h1, h2]:
		night.append("%s Nachtschicht=%s schläft=%s %s" % [s.display_name, Admin.night_worker(s), s.sleeping, s.activity])
	print("Verwaltung: Nacht ", night)
	_ok(at_night and not h1.sleeping and not h2.sleeping, "Schicht: die Handwerker arbeiten nachts")
	Admin._night_check_at = 0
	_ok(Admin.night_work_now(), "Schicht: die Nacht läuft nicht schneller")
	var lit: bool = await _wait(main, func():
		for b in w.buildings:
			if b.type == "saegegrube" and b._light != null and b._light.energy > 0.1:
				return true
		return false, 30.0)
	_ok(lit, "Schicht: die Sägegrube hat nachts eine Arbeitslampe")
	# Nur die Insel der Verwaltung (josh 2026-10-16): auf einer zweiten Insel gilt nichts davon
	var m2: Dictionary = Sea.make_island(Sea.islands.size())
	Sea.islands.append(m2)
	var w2 = Sea.create_world_node(int(m2.id))
	w2.build_colony(m2)
	m2.state = "settled"
	var o2 = w2.spawn_settler({"name": "H3", "sex": "m", "age": 30.0, "max_age": 70.0, "x": w2.center.x, "y": w2.center.y,
		"mind": {"traits": {}, "talents": {}}})
	o2.set_job("handwerker")
	_ok(Admin.shift("handwerker", w) and not Admin.shift("handwerker", w2) and not Admin.night_worker(o2) and Admin.work_mult(o2) == 1.0,
		"Schicht gilt nur auf der Insel der Verwaltung")
	_ok(not Admin.needs_standin(w2, "handwerk") and w2.find_standin(w2.center, o2.id, "frei") == null, "keine Vertretung auf der anderen Insel")
	Game.add_stock("holz", 60, w2)
	main._place_on(w2, "saegegrube")
	_ok(Admin.shortages().all(func(e): return int(e[1]) <= 1), "Meldungen zählen nur die Insel der Verwaltung %s" % [Admin.shortages()])
	# Forschung nur auf der Hauptinsel
	_ok(Sea.is_main(w) and not Sea.is_main(w2), "Heimatinsel ist die Hauptinsel")
	var r2 = w2.spawn_settler({"name": "F2", "sex": "f", "age": 30.0, "max_age": 70.0, "x": w2.center.x, "y": w2.center.y,
		"mind": {"traits": {}, "talents": {}}})
	r2.set_job("forscher")
	var keep_cur: String = Game.research.current
	if Game.research.current == "":
		for t in Data.sorted_tech_ids():
			if Game.tech_state(t) == "available":
				Game.research.current = t
				break
	var ai2: String = AiJobs._most_needed(w2, w2.settlers.filter(func(x): return x.is_adult()))
	_ok(not r2._plan_research() and ai2 != "forscher", "Forscher auf der anderen Insel forscht nicht (KI wählt %s)" % ai2)
	Game.research.current = keep_cur
	# Verwalter auf der anderen Insel: die Verwaltung arbeitet nicht
	var v3 = w2.spawn_settler({"name": "V3", "sex": "m", "age": 30.0, "max_age": 70.0, "x": w2.center.x, "y": w2.center.y,
		"mind": {"traits": {}, "talents": {}}})
	v3.set_job("verwalter")
	_ok(not Admin.active() and Admin.manager() == v3, "Verwalter auf einer anderen Insel: Verwaltung ruht")
	v2.set_job("verwalter")
	_ok(Admin.active(), "Verwalter zurück auf der Insel der Verwaltung")
	w2.remove_settler(o2)
	w2.remove_settler(r2)
	w2.remove_settler(v3)
	# Neuzuweisung freier Berufe ab dem Mittelalter (josh 2026-10-16)
	var keep_passed: int = Exams.passed
	var keep_jobs := {}
	for s in w.settlers:
		if s.is_adult() and s.job == "frei":
			keep_jobs[s] = "frei"
			s.job = "sammler"
	var mkx := func(n: String, job: String, age: float):
		var x = w.spawn_settler({"name": n, "sex": "m", "age": age, "max_age": 70.0, "x": w.center.x, "y": w.center.y,
			"mind": {"traits": {}, "talents": {}}})
		if job != "":
			x.set_job(job)
		return x
	Admin.auto_reassign = true
	Exams.passed = 1
	var f1 = mkx.call("A1", "", 30.0)
	f1.set_job("frei")
	w.kill_settler(mkx.call("D1", "fischer", 30.0), "Test")
	_ok(not Admin.auto_unlocked() and f1.job == "frei" and Admin.pending_jobs.is_empty(), "vor dem Mittelalter keine Neuzuweisung")
	Exams.passed = 2
	w.kill_settler(mkx.call("D2", "fischer", 30.0), "Test")
	_ok(f1.job == "fischer", "ab dem Mittelalter übernimmt ein freier Siedler den Beruf (%s)" % f1.job)
	w.kill_settler(mkx.call("D3", "holzfaeller", 30.0), "Test")
	_ok(Admin.pending_jobs == ["holzfaeller"], "kein freier Siedler: Beruf wartet auf ein Kind %s" % [Admin.pending_jobs])
	var dp := {}
	Admin._on_save(dp)
	dp = JSON.parse_string(JSON.stringify(dp))
	Admin._on_load(dp, 9)
	_ok(Admin.pending_jobs == ["holzfaeller"] and Admin.auto_reassign, "offener Beruf bleibt im Spielstand")
	var kid = mkx.call("K1", "", float(Data.bal("adult_age")) - 0.001)
	kid._needs(0.01)
	_ok(kid.is_adult() and kid.job == "holzfaeller" and Admin.pending_jobs.is_empty(), "das nächste erwachsene Kind lernt den Beruf (%s)" % kid.job)
	var kid2 = mkx.call("K2", "", float(Data.bal("adult_age")) - 0.001)
	kid2._needs(0.01)
	_ok(kid2.job == "frei", "danach werden Kinder wieder frei")
	for x in [f1, kid, kid2]:
		w.remove_settler(x)
	for s in keep_jobs:
		if is_instance_valid(s):
			s.job = keep_jobs[s]
	Admin.auto_reassign = false
	Exams.passed = keep_passed
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


## Bildschirmfoto-Hilfe --adminshot=office|night|workshop|proposal (night: Reiter Nachtschicht): Verwaltung, Verwalter und Sägegrube
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
		if b.type == "verwaltung" and kind in ["office", "night"]:
			AdminInfo._tab = 2 if kind == "night" else 0
			for j in Data.jobs:
				Admin.reported[j] = 1e9  # kein Vorschlagsfenster über dem Infofenster
			Game.select(b)
	if kind == "proposal":
		Admin.reported.clear()
		Admin._tick()


## Messung --adminmeasure=normal|ot|shift[,tage]: zwei Handwerker, zwei Sägegruben, Holz und Essen
## werden nachgefüllt, Bretter abgeräumt. Druckt "Verwaltung Messung <art>: <Bretter> Bretter in <Tage> Tagen".
static func measure(main, arg: String) -> void:
	var parts := arg.split(",")
	var mode := parts[0]
	var days := float(parts[1]) if parts.size() > 1 else 3.0
	var w = main.world
	for t in ["gelehrsamkeit", "holzbearbeitung", "steinwerkzeuge", "maurerei", "toepferei", "zimmerei", "schrift"]:
		if not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()
	main._place_on(w, "verwaltung")
	main._place_on(w, "lager")
	main._place_on(w, "saegegrube")
	main._place_on(w, "saegegrube")
	for s in w.settlers:
		s.set_job("sammler")
	var c: Vector2i = w.settlers[0].cell
	var mk := func(n: String, job: String):
		var s = w.spawn_settler({"name": n, "sex": "m", "age": 30.0, "max_age": 70.0, "x": c.x, "y": c.y,
			"skills": {"handwerk": 3}, "mind": {"traits": {"iq": 5.0, "konst": 7.0, "fleiss": 5.0, "gemuet": 6.0}, "talents": {}}})
		s.hunger = 100.0
		s.set_job(job)
		return s
	mk.call("V", "verwalter")
	mk.call("H1", "handwerker")
	mk.call("H2", "handwerker")
	if mode == "ot":
		Admin.set_overtime("handwerker", true)
	elif mode == "shift":
		Admin.set_shift("handwerker", true)
	Admin.reported["handwerker"] = 999.0
	var t0 := Game.time_days + 0.5
	var made := 0
	var night := 0
	var bins := [0, 0, 0, 0, 0, 0, 0, 0]
	while Game.time_days < t0 + days:
		await main.get_tree().create_timer(0.25, true, false, true).timeout
		if Game.amount("holz", w) < 40:
			Game.add_stock("holz", 40, w)
		if Game.amount("beeren", w) < 40:
			Game.add_stock("beeren", 40, w)
		var n := Game.amount("bretter", w)
		if n > 0:
			Game.take_stock("bretter", n, w)
			if Game.time_days >= t0:
				made += n
				bins[int(Game.time_of_day() * 8.0) % 8] += n
				if Game.is_night():
					night += n
		Admin.orders.get("handwerker", {})["since"] = Game.time_days  # kein Protest während der Messung
		if OS.get_cmdline_user_args().has("--measuredebug") and int(Game.time_days * 8.0) != int((Game.time_days - 0.02) * 8.0):
			for s in w.settlers:
				if s.job == "handwerker":
					print("  %s %s %s Laune %.0f Kraft %.2f schläft=%s rest=%.0f: %s" % [Game.clock_text(), s.display_name, "Nacht" if Game.is_night() else "Tag",
						s.mind.mood, s.mind.work_power(), s.sleeping, s.mind.rest, s.activity])
	print("Verwaltung Messung %s: %d Bretter in %.1f Tagen (nachts %d) je 3 Stunden %s" % [mode, made, days, night, str(bins)])
