class_name PlannerTest
extends RefCounted
## Selbsttest des Planungsautomaten (Planner). Kein Autoload; Planner.autotest_setup ruft ihn.
##   --plannertest=1 mit --fixture=<sea.json> (vier Inseln): nichts vor der Industrialisierung und ohne das
##   Gebäude, Bauplatz vor der Verwaltung, Essen zuerst (Schiff, Beruf, Hof), kein Bau ohne Material (bestellt
##   stattdessen), eine Baustelle zur Zeit mit Baumeister, Haus bei fehlenden Arbeitskräften, Siedler per Schiff,
##   Forschung auf dem Weg zur KI, KI übernimmt, Spielstand. Druckt „Planer OK/FEHLER …“ und am Ende
##   „Planer OK (N Fehler)“.
##   --plannermeasure=<Tage>[,off] mit --fixture=<sea.json>: dieselbe Lage, Automat an (oder aus), misst
##   Siedler, Essen-Tage, Gebäude und Forschungen. --plannershot=1: Fenster Verwalter, Reiter Inseln.

static var fails := 0


static func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("Planer ", "OK " if c else "FEHLER ", what)


static func _wait(main, secs: float) -> void:
	await main.get_tree().create_timer(secs, true, false, true).timeout


static func _close_dialogs(main) -> void:
	var hud = main.hud
	hud._offers.clear()
	if hud._hint_dialog != null and is_instance_valid(hud._hint_dialog):
		hud._hint_dialog.queue_free()
		hud._hint_dialog = null


## Lage wie in der Industrialisierung: Forschung bis Stufe 9, Zeitalter 4, Verwalter steuert, Verwaltung auf der
## Heimatinsel. machine: auch den Planungsautomaten davor stellen.
static func prepare(main, machine: bool) -> void:
	_close_dialogs(main)
	Game.set_speed(1)
	Game.research.done = Game.research.done.filter(func(t): return int(Data.techs.get(t, {}).get("tier", 1)) <= 9)
	Game.research.current = ""
	Game.research.paid = []
	Exams.passed = 4
	Game.refresh_effects()
	Steward.on = true
	Steward.offered = true
	Steward.offered_routes = true
	Steward.offered_net = true
	Steward.offered_automat = true
	Planner.offered = true
	var hw = Sea.main_world()
	for w in Sea.all_worlds():  # Baustellen aus der Zeit davor (die KI des Testspielstands) weg
		for b in w.construction_sites():
			w.demolish(b)
	if Admin.office() == null:
		main._place_on(hw, "verwaltung")
	if machine and Planner.machine() == null:
		place_machine(hw, true)
	Game.refresh_effects()


## Stellt den Planungsautomaten neben die Verwaltung. Gibt die Zelle zurück (oder null).
static func place_machine(w, complete: bool):
	var o = Admin.office()
	for dy in range(-4, 6):
		for dx in range(-5, 6):
			var c: Vector2i = o.cell + Vector2i(dx, dy)
			if w.can_place("planautomat", c):
				w.place_building("planautomat", c, complete)
				return c
	return null


static func _food_zero(w) -> void:
	for f in Data.food_ids():
		w.stock[f] = 0


static func _set_food_days(w, days: float) -> void:
	_food_zero(w)
	w.stock["fisch"] = 100
	var fd := Game.food_days(w)
	w.stock["fisch"] = int(100.0 * days / maxf(0.01, fd))


static func _sites(w) -> Array:
	return w.construction_sites()


static func run(main, _mode: String) -> void:
	fails = 0
	await _wait(main, 0.5)
	Data.balance["base_storage"] = 4000
	prepare(main, false)
	var hw = Sea.main_world()
	var ids: Array = Sea.settled_islands().map(func(m): return int(m.id))
	# Frühling (keine Wintervorsorge in diesen Prüfungen)
	Game.time_days = ceilf(Game.time_days / Seasons.year_days()) * Seasons.year_days() + 0.3
	# 1. Freigabe
	Exams.passed = 3
	_ok(not Game.is_unlocked("planautomat") and Planner.build_reason().contains(Loc.t("die Industrialisierung")), "vor der Industrialisierung nicht baubar: %s" % Planner.build_reason())
	_ok(not Planner.active(), "vor der Industrialisierung plant niemand: %s" % Planner.reason())
	Exams.passed = 4
	_ok(Game.is_unlocked("planautomat"), "ab der Industrialisierung baubar")
	_ok(not Planner.active() and Planner.machine() == null, "ohne Gebäude plant niemand: %s" % Planner.reason())
	var far := false
	for b in hw.buildings:
		if b.type == "verwaltung":
			far = hw.can_place("planautomat", b.cell + Vector2i(12, 0)) or hw.can_place("planautomat", b.cell + Vector2i(-12, 6))
	_ok(not far, "weit weg von der Verwaltung nicht baubar")
	var c = place_machine(hw, true)
	_ok(c != null and Planner.machine() != null, "direkt vor der Verwaltung gebaut bei %s" % str(c))
	var c2 = place_machine(hw, true)
	_ok(c2 == null, "nur einer im Spiel")
	_ok(Planner.active(), "mit Gebäude, Industrialisierung und Verwalter: Automat plant")
	var bot_off := Steward.on
	Steward.on = false
	_ok(not Planner.active(), "ohne Verwalter-Steuerung plant er nicht")
	Steward.on = bot_off
	Game.set_speed(0)  # die Prüfungen rufen decide selbst auf
	# 2. Essen zuerst: andere Insel ohne Essen -> Schiff mit Essen oder Nahrungsberuf
	var w1 = Sea.worlds.get(ids[1])
	var adults1: Array = w1.settlers.filter(func(s): return s.is_adult())
	for s in adults1:
		s.set_job("frei")
	_food_zero(w1)
	var p := Planner.decide(w1)
	var food_jobs: int = adults1.filter(func(s): return s.job in Steward.FOOD_JOBS).size()
	_ok(p.prio == "a" and (Steward._incoming_food_days(w1) > 0.0 or food_jobs > 0), "kein Essen auf %s: %s (%s)" % [Sea.island_name(w1), p.step, p.need])
	p = Planner.decide(w1)
	food_jobs = adults1.filter(func(s): return s.job in Steward.FOOD_JOBS).size()
	_ok(p.prio == "a" and food_jobs > 0, "dann Siedler in Nahrungsberufe: %s (%d)" % [p.step, food_jobs])
	# Essen knapp (2,5 Tage), alle haben einen Beruf, der Verwalter lässt sie: ein Hof wird gebaut
	_set_food_days(w1, 2.5)
	for s in adults1:
		if s.job == "frei":
			s.set_job("holzfaeller")
		JobDesk.hold(s, "spieler", 5.0)
	var n_sites: int = _sites(w1).size()
	p = Planner.decide(w1)
	var farm := _sites(w1).filter(func(b): return b.def.has("farm"))
	_ok(p.prio == "a" and not farm.is_empty(), "Essen 2,5 Tage, niemand frei: %s (%s)" % [p.step, farm.map(func(b): return b.type)])
	_ok(_sites(w1).size() == n_sites + 1, "genau eine neue Baustelle")
	# Baumeister: der Automat sorgt für einen
	# (alle waren gesperrt; jetzt darf der Automat wieder umsetzen)
	for s in adults1:
		JobDesk.release(int(s.id))
	var bm = Planner._ensure_builder(w1)
	_ok(Steward._count(w1, "baumeister") >= 1, "Baumeister für die Baustelle: %s (%d)" % [bm.display_name if bm != null else "-", Steward._count(w1, "baumeister")])
	_ok(Planner._ensure_builder(w1) == null, "nur ein Baumeister, solange einer da ist")
	# Eine Baustelle zur Zeit
	p = Planner._build(w1, "lager", "Test", "d")
	_ok(_sites(w1).size() == n_sites + 1, "zweiter Bau wartet, bis die Baustelle fertig ist: %s" % p.step)
	# 3. Kein Bau ohne Material: auf Insel 2 fehlt Holz -> bestellt, baut nicht
	var w2 = Sea.worlds.get(ids[2])
	w2.stock["fisch"] = 2000
	for site in _sites(w2):
		w2.demolish(site)
	var h2 := Game.amount("holz", w2)
	w2.stock["holz"] = 0
	p = Planner._build(w2, "obstgarten", "Test", "e")
	_ok(_sites(w2).is_empty(), "ohne Holz keine Baustelle auf %s: %s" % [Sea.island_name(w2), p.step])
	_ok(Steward.incoming(ids[2], "holz") > 0, "Holz bestellt: %d unterwegs" % Steward.incoming(ids[2], "holz"))
	_ok(Planner.orders.has(str(ids[2])), "Bauvorhaben gemerkt: %s" % str(Planner.orders.get(str(ids[2]), {})))
	p = Planner._build(w2, "obstgarten", "Test", "e")
	_ok(_sites(w2).size() == 1, "Material unterwegs: jetzt wird gebaut (%s)" % p.step)
	for site in _sites(w2):
		w2.demolish(site)
	# Nirgends Holz: keine Baustelle, kein Schiff, Holzfäller statt dessen
	var keep_h := {}
	for w in Sea.all_worlds():
		keep_h[w] = Game.amount("holz", w)
		w.stock["holz"] = 0
	var inc0 := Steward.incoming(ids[2], "holz")
	p = Planner._build(w2, "lager", "Test", "e")
	_ok(_sites(w2).is_empty() and Steward.incoming(ids[2], "holz") == inc0, "Holz nirgends da: nicht gebaut, %s" % p.step)
	for w in keep_h:
		w.stock["holz"] = keep_h[w]
	w2.stock["holz"] = h2
	# 4. Haus, wenn Arbeitskräfte fehlen: Werkstatt ohne Handwerker, niemand frei, keine Betten
	var w3 = Sea.worlds.get(ids[3])
	w3.stock["fisch"] = 2000
	w3.stock["holz"] = 600
	for site in _sites(w3):
		w3.demolish(site)
	main._place_on(w3, "saegegrube")
	for s in w3.settlers:
		if s.is_adult():
			s.set_job("fischer")
			JobDesk.hold(s, "spieler", 5.0)
	_ok(Planner.workers_wanted(w3) != "", "Arbeitskräfte fehlen auf %s: %s" % [Sea.island_name(w3), Planner.workers_wanted(w3)])
	p = Planner.decide(w3)
	var house := _sites(w3).filter(func(b): return int(b.def.get("housing", 0)) > 0)
	var ordered := false
	for res in Data.buildings[Planner.best_house(w3)].cost:
		if Steward.incoming(ids[3], res) > 0:
			ordered = true
	_ok(p.prio == "c" and (not house.is_empty() or ordered), "keine Betten: %s (%s)" % [p.step, p.need])
	# 5. Wächst die Insel nicht, kommen freie Siedler per Schiff
	for site in _sites(w3):
		w3.demolish(site)
	for i in 3:
		main._place_on(w3, "huette")
	var w1free: Array = w1.settlers.filter(func(s): return s.is_adult())
	w1.stock["fisch"] = 3000
	for s in w1free:
		JobDesk.release(int(s.id))
		s.set_job("frei")
	Planner._grow[str(ids[3])] = [Game.time_days - 5.0, w3.settlers.size()]
	Sea._new_ship("boot", ids[1])  # die Boote dort fahren schon Waren
	var sent0 := Planner.sent
	var pop1: int = w1.settlers.size()
	p = Planner.decide(w3)
	_ok(Planner.sent == sent0 + 1 and w1.settlers.size() < pop1, "Nachwuchs dauert: %s (%s)" % [p.step, p.need])
	# 6. Forschung: nichts läuft -> nächste Forschung auf dem Weg zur KI
	Game.research.current = ""
	Planner.plans.erase(str(int(hw.island_id)))
	for id in ["stahl", "werkzeug", "maschinen", "eisen", "kohle", "holz", "ziegel"]:
		hw.stock[id] = 200
	var t := Planner.research_step()
	_ok(t != "" and Game.research.current == t and Planner.ki_path().has(t), "Forschung gewählt: %s (auf dem Weg zur KI: %s)" % [t, Planner.ki_path().has(t)])
	var order := Planner.tech_order()
	_ok(order.is_empty() or Planner.ki_path().has(order[0]), "Rangfolge beginnt auf dem Weg zur KI: %s" % str(order.slice(0, 3)))
	# 7. Bedürfnisse vor Ausbau: Essen knapp -> kein Haus, kein Lager
	_set_food_days(w3, 2.5)
	p = Planner.decide(w3)
	_ok(p.prio == "a", "Essen knapp geht vor dem Haus: %s" % p.need)
	# 8. Winter: im Herbst ohne haltbares Essen -> Wintervorrat
	w3.stock["fisch"] = 2000
	var t0 := Game.time_days
	Game.time_days = floorf(t0 / Seasons.year_days()) * Seasons.year_days() + Seasons.season_days() * 2.1
	for f in Data.food_ids():
		if not f in Seasons.cfg.get("perishable", []):
			w3.stock[f] = 0
	p = Planner.decide(w3)
	_ok(p.prio == "b", "Herbst ohne haltbares Essen: %s (%s)" % [p.step, p.need])
	Game.time_days = t0
	# 9. KI übernimmt: der Automat steht still
	Game.research.done.append("ki")
	_ok(not Planner.active() and Planner.reason() != "", "mit KI plant der Automat nicht mehr: %s" % Planner.reason())
	Game.research.done.erase("ki")
	# 10. Spielstand
	Planner.on = false
	var d := {}
	Planner._on_save(d)
	var copy = JSON.parse_string(JSON.stringify(d))
	Planner._on_load(copy, 99)
	_ok(not Planner.on and Planner.plans.has(str(ids[3])) and Planner.built > 0, "Spielstand: aus, Pläne %d, Bauten %d" % [Planner.plans.size(), Planner.built])
	Planner._on_load({}, 99)
	_ok(Planner.on and not Planner.offered, "alter Spielstand ohne Planer: an, Angebot kommt")
	# 11. Im Spiel: alle Inseln bekommen einen Plan
	Planner.on = true
	Planner.offered = true
	Planner.plans = {}
	Game.set_speed(1)
	await _wait(main, 4.0)
	_ok(Planner.plans.size() == Sea.all_worlds().size(), "im Spiel: Plan für %d von %d Inseln" % [Planner.plans.size(), Sea.all_worlds().size()])
	for k in Planner.plans:
		print("   Plan %s: %s -> %s" % [Sea.meta(int(k)).get("name", "?"), Planner.plans[k].need, Planner.plans[k].step])
	print("Planer %s (%d Fehler)" % ["OK" if fails == 0 else "FEHLER", fails])


## --plannermeasure=<Tage>[,off]: gleiche Ausgangslage, Automat an oder aus. Druckt eine Zeile „Planer Messung …“.
static func measure(main, arg: String) -> void:
	await _wait(main, 0.5)
	var parts := arg.split(",")
	var days := float(parts[0]) if parts[0].is_valid_float() else 10.0
	var off := parts.size() > 1 and parts[1] == "off"
	prepare(main, true)
	Planner.on = not off
	var t0 := Game.time_days
	var pop0 := Sea.total_people()
	var techs0: int = Game.research.done.size()
	var b0 := _count_buildings()
	var samples := 0
	var food_sum := 0.0
	var food_min := 999.0
	var hungry := 0
	var died0: int = int(Game.stats.get("deaths", 0))
	while Game.time_days < t0 + days and not Game.is_over:
		await _wait(main, 1.0)
		_close_dialogs(main)
		for w in Sea.all_worlds():
			var fd := Game.food_days(w)
			if fd < 0.0:
				continue
			samples += 1
			food_sum += minf(fd, 30.0)
			food_min = minf(food_min, fd)
			if fd < 1.0:
				hungry += 1
	var b1 := _count_buildings()
	print("Planer Messung %s: %.1f Tage | Siedler %d -> %d | Gebäude %d -> %d (Baustellen %d) | Forschungen %d -> %d | Essen-Tage Mittel %.1f, kleinste %.1f, Proben unter 1 Tag %d von %d | Planer: Bauten %d, Forschungen %d, Siedlerschiffe %d | Tote %d" % [
		"aus" if off else "an", Game.time_days - t0, pop0, Sea.total_people(), b0[0], b1[0], b1[1], techs0, Game.research.done.size(),
		food_sum / maxf(1.0, samples), food_min, hungry, samples, Planner.built, Planner.started, Planner.sent, int(Game.stats.get("deaths", 0)) - died0])


static func _count_buildings() -> Array:
	var done := 0
	var sites := 0
	for w in Sea.all_worlds():
		for b in w.buildings:
			if b.def.has("tile") or b.is_decor():
				continue
			if b.complete:
				done += 1
			else:
				sites += 1
	return [done, sites]


## --plannershot=1 mit --fixture=<sea.json> und --shot: Fenster Verwalter, Reiter Inseln mit Automat und Plan.
static func shot(main) -> void:
	prepare(main, true)
	Planner.tick()
	AdminInfo._tab = AdminInfo.TAB_ISLANDS
	for j in Data.jobs:
		Admin.reported[j] = 1e9
	var close := func():
		main.hud._offers.clear()
		for c in main.hud.root.get_children():
			if c is ColorRect and c.mouse_filter == Control.MOUSE_FILTER_STOP:
				c.queue_free()
	for t in [0.5, 1.5, 3.0]:
		main.get_tree().create_timer(t).timeout.connect(close)
	main.hud._open_admin()
