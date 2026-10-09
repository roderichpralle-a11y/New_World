class_name IntegrationTest
extends RefCounted
## Selbsttest --integtest=1: prüft, ob die Teile der Erweiterung "Mehr Herausforderung" zusammenspielen
## (Klima und Aufträge, Prüfungen und Hausstufen, Piraten und Zeitalter, Händler und Ereignisse,
## Fachkräfte-Pool und Schreibwaren beim Forschen, Wertung und Aufträge).
## Dürre und Klima prüft --eventtest=duerre. Ausgaben nur mit print, je Prüfung "Zusammenspiel OK" oder "Zusammenspiel FEHLER".

static var fails := 0


## Der Name endet auf "print(": tools/i18n.py wrap lässt die Aufrufe (Testausgaben) in Ruhe.
static func _okprint(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("Zusammenspiel ", "OK " if c else "FEHLER ", what)


static func _wait(main, secs: float) -> void:
	await main.get_tree().create_timer(secs, true, false, true).timeout


## Wartet, bis cond() gilt oder max_days Spieltage vergangen sind.
static func _until(main, cond: Callable, max_days: float) -> bool:
	var t0 := Game.time_days
	while not cond.call():
		if Game.time_days > t0 + max_days or Game.is_over:
			return false
		await main.get_tree().process_frame
	return true


static func run(main) -> void:
	fails = 0
	var w = main.world
	await _wait(main, 0.5)
	Game.goals["tut"] = Data.goals.get("tutorial", []).size()
	Data.balance["base_storage"] = 4000
	while w.settlers.size() < 10:
		if w.spawn_newcomer("f" if w.settlers.size() % 2 else "m") == null:
			break
	for id in ["holz", "bretter", "stein", "ziegel", "lehm", "eisen", "werkzeug", "kohle"]:
		w.stock[id] = maxi(Game.amount(id, w), 150)
	for id in ["beeren", "fisch", "brot"]:
		w.stock[id] = maxi(Game.amount(id, w), 80)
	Game.stock_changed.emit()
	_climate_quests()  # jetzt (Frühling: Winter noch unbekannt)
	_exam_houses()
	_score_quests()
	_pirates_age(main, w)
	_merchant_events(main, w)
	await _pool_writing(main, w)
	Seasons.jump_to_season(Seasons.AUTUMN)  # ab Herbst ist der Winter genau bekannt
	_climate_quests()
	print("Zusammenspiel Ergebnis: %d Fehler" % fails)


## H -> D: die Winterholz-Menge der Aufträge folgt der Wintervorhersage, nicht dem geheimen Wintertyp.
static func _climate_quests() -> void:
	var key := str(Seasons.year())
	var keep = Seasons.climate.get(key)
	var p := 10
	var res := {}
	for t in ["mild", "normal", "hart", "bitter"]:
		Seasons.climate[key] = {"w": t, "s": "normal"}
		res[t] = [Seasons.winter_forecast(), Quests.winter_type(), Quests.winter_wood(p, Quests.winter_mult())]
	if keep == null:
		Seasons.climate.erase(key)
	else:
		Seasons.climate[key] = keep
	var known := Seasons.winter_known()
	var ok := true
	for t in res:
		var f: String = res[t][0]
		var want := "normal" if f == "" else ("hart" if f == "streng" else f)
		ok = ok and res[t][1] == want
	if known == "exact":
		ok = ok and int(res.bitter[2]) > int(res.normal[2]) and int(res.mild[2]) < int(res.normal[2])
	print("Zusammenspiel: Jahreszeit %s, Winter bekannt '%s', Aufträge sehen %s" % [Seasons.season_name(), known, res])
	_okprint(ok, "Winterholz-Auftrag nutzt Seasons.winter_forecast (Klima)")


## B -> J: Prüfungen 4 und 5 verlangen Mietshaus und Wohnblock; Namen und Ausbaukette aus B.
static func _exam_houses() -> void:
	var labels := []
	var ok := true
	for i in [4, 5]:
		for c in Exams.exam_def(i).get("checks", []):
			if str(c.get("type", "")) == "houses":
				var l := GoalChecks.label(c)
				labels.append(l)
				ok = ok and Data.buildings.has(str(c.what)) and l.find(str(Data.buildings[c.what].name)) >= 0
	ok = ok and GoalChecks.house_counts("wohnblock", "mietshaus") and GoalChecks.house_counts("mietshaus", "steinhaus") \
		and not GoalChecks.house_counts("steinhaus", "mietshaus") and labels.size() == 2
	print("Zusammenspiel: Prüfungs-Häuser %s, Wohnblock zählt als Mietshaus %s" % [labels, GoalChecks.house_counts("wohnblock", "mietshaus")])
	_okprint(ok, "Prüfungen nennen Mietshaus und Wohnblock (Hausstufen)")


## D -> J: erledigte Aufträge geben je 40 Punkte in der Wertung.
static func _score_quests() -> void:
	var keep := int(Game.stats.get("quests", 0))
	var s0 := Exams.score()
	Game.stats["quests"] = keep + 2
	var s1 := Exams.score()
	var row := ""
	for r in Exams.score_parts():
		if int(r[1]) == keep + 2 and int(r[2]) == (keep + 2) * 40:
			row = str(r[0])
	Game.stats["quests"] = keep
	print("Zusammenspiel: Wertung %d -> %d mit 2 Aufträgen, Zeile '%s'" % [s0, s1, row])
	_okprint(s1 - s0 == 80 and row != "", "Wertung zählt Aufträge (40 Punkte je Auftrag)")


## J -> C: Piraten erst ab dem Mittelalter (Game.current_age = bestandene Prüfungen).
static func _pirates_age(main, w) -> void:
	main._place_on(w, "werft")
	var keep := Exams.passed
	Exams.passed = 1
	var at1 := Events.eligible(w, "piraten")
	Exams.passed = 2
	var at2 := Events.eligible(w, "piraten")
	Exams.passed = keep
	print("Zusammenspiel: Piraten möglich bei Zeitalter 1: %s, 2: %s (Hafenstufe %d, Siedler %d)" % [at1, at2, Sea.harbor_level(w), w.settlers.size()])
	_okprint(not at1 and at2, "Piraten folgen Game.current_age (Prüfungen)")


## C -> G: der Händler meidet Inseln mit angekündigten Piraten (Events.busy).
static func _merchant_events(_main, w) -> void:
	var before := Merchant.eligible(w)
	var keep := Exams.passed
	Exams.passed = maxi(keep, 2)
	var ev := Events.force(w, "piraten", 5.0)
	var during := Merchant.eligible(w)
	var busy := Events.busy(w)
	var key := str(w.island_id)
	Events._end(w, Events.islands[key], ev, "")
	var after := Merchant.eligible(w)
	Exams.passed = keep
	print("Zusammenspiel: Händler-Insel möglich vorher %s, während Piraten %s (busy %s), danach %s" % [before, during, busy, after])
	_okprint(before and busy and not during and after, "Händler meidet Inseln mit Piraten (Events.busy)")


## B + E: Bibliothek (Fachkräfte Stufe 2) bleibt ohne zufriedenes Holzhaus leer; Forschung verbraucht
## Tontafeln aus dem Lager der Insel, egal an welchem Platz.
static func _pool_writing(main, w) -> void:
	for t in Data.techs:
		if int(Data.techs[t].tier) <= 4 and not Data.techs[t].get("soon", false) and not t in Game.research.done and t != "deichbau":
			Game.research.done.append(t)
	Game._recompute_effects()
	Game.research_changed.emit()
	for id in ["ziegel", "stein"]:
		w.stock[id] = maxi(Game.amount(id, w), 200)
	var err := Game.start_research("deichbau")
	var rates := Writing.goods_for("deichbau")
	main._place_on(w, "bibliothek")
	var lib = null
	for b in w.buildings:
		if b.type == "bibliothek":
			lib = b
	var n := 0
	for s in w.settlers:
		if s.is_adult() and n < 3:
			s.set_job("forscher")
			n += 1
	w.stock["tontafel"] = 0
	var p0 := float(Game.research.progress.get("deichbau", 0.0))
	var stalled := await _until(main, func(): return Writing.slow_cycles > 0, 1.0)
	var lib_empty: bool = lib != null and lib.occupants.is_empty()
	var cap: Array = HouseNeeds.pool(w, 2)
	print("Zusammenspiel: Forschung %s (Fehler '%s'), Schreibwaren %s, Bibliothek leer %s, Fachkräfte Stufe 2 %s, gebremst %s" % [Game.research.current, err, rates, lib_empty, cap, stalled])
	_okprint(err == "" and rates.has("tontafel") and lib_empty and int(cap[1]) == 0 and stalled, "ohne Holzhaus keine Fachkraft für die Bibliothek, ohne Tontafeln gebremst")
	# Holzhaus mit erfüllten Bedürfnissen (Bretter, drei Nahrungsarten): jetzt darf die Bibliothek arbeiten
	main._place_on(w, "holzhaus")
	main._place_on(w, "holzhaus")
	w.assign_homes()
	w.stock["tontafel"] = 60
	Game.stock_changed.emit()
	var used0 := int(Game.stats.get("writing_used", 0))
	var staffed := await _until(main, func(): return lib != null and not lib.occupants.is_empty(), 2.0)
	await _until(main, func(): return int(Game.stats.get("writing_used", 0)) > used0 + 3, 1.5)
	cap = HouseNeeds.pool(w, 2)
	var used := int(Game.stats.get("writing_used", 0)) - used0
	print("Zusammenspiel: Bibliothek besetzt %s (%d Forscher), Fachkräfte Stufe 2 %s, Tontafeln verbraucht %d, Lager %d, Fortschritt %.0f -> %.0f" % [staffed, lib.occupants.size() if lib else 0, cap, used, Game.amount("tontafel", w), p0, float(Game.research.progress.get("deichbau", 0.0))])
	_okprint(staffed and int(cap[1]) > 0 and used > 0 and Game.amount("tontafel", w) < 60, "mit Holzhaus forscht die Bibliothek und verbraucht Tontafeln")
