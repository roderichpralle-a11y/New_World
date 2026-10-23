class_name StewardTest
extends RefCounted
## Selbsttest der Verwalter-Steuerung (Steward). Kein Autoload; Steward.autotest_setup ruft ihn.
##   --stewardtest=1 mit --fixture=<sea.json> (mindestens zwei besiedelte Inseln): Angebot erscheint,
##   Essen knapp -> Nahrungsberuf, Brennholz, Lager bis zur Höchstmenge, Spieler-Beruf bleibt, Speichern.
##   Druckt „Verwalter OK/FEHLER“. --stewardtest=shot: nur das Angebots-Fenster zeigen.


static func _okf(c: bool) -> String:
	return "OK" if c else "FEHLER"


static func _wait(main, secs: float) -> void:
	await main.get_tree().create_timer(secs, true, false, true).timeout


static func _food_ids_zero(w) -> void:
	for f in Data.food_ids():
		w.stock[f] = 0


static func run(main, mode: String) -> void:
	await _wait(main, 0.5)
	if mode == "shot":
		Steward.offered = false
		return
	if mode == "netshot":  # Angebot Inselverbund
		main.hud._offers.clear()
		if main.hud._hint_dialog != null and is_instance_valid(main.hud._hint_dialog):
			main.hud._hint_dialog.queue_free()
			main.hud._hint_dialog = null
		Steward.on = true
		Steward.offered_routes = true
		Game.research.done.erase("elektrizitaet")
		if not Game.is_researched("papier"):
			Game.research.done.append("papier")
		Steward.offered_net = true
		main.hud._show_offer("net")
		return
	var hud = main.hud
	print("Verwalter ", _okf(Steward.offered and (not hud._offers.is_empty() or hud._hint_dialog != null)), " Angebot bei %d Inseln" % Sea.settled_islands().size())
	if hud._hint_dialog != null and is_instance_valid(hud._hint_dialog):
		hud._hint_dialog.queue_free()
		hud._hint_dialog = null
	hud._offers.clear()
	Game.set_speed(1)
	Steward.set_on(true)
	var w = Sea.worlds.get(1)
	Data.balance["base_storage"] = 4000
	# Alle frei, Essen leer
	var adults: Array = w.settlers.filter(func(s): return s.is_adult())
	for s in adults:
		s.set_job("frei")
	_food_ids_zero(w)
	var keep = adults[0]
	keep.set_job("forscher")
	Steward.player_set(keep)
	var need := Steward.needed(w)
	print("Verwalter ", _okf(need.get("job", "") in Steward.FOOD_JOBS), " Essen leer -> %s (%s)" % [need.get("job", ""), need.get("why", "")])
	Steward.tick(w)
	var food_n: int = adults.filter(func(s): return s.job in Steward.FOOD_JOBS).size()
	print("Verwalter ", _okf(food_n >= 1 and keep.job == "forscher"), " %d Siedler holen Essen, Spieler-Beruf bleibt (%s)" % [food_n, keep.job])
	# Brennholz: Essen reichlich, Holz leer, Herbst
	for f in Data.food_ids():
		w.stock[f] = 0
	w.stock["fisch"] = 2000
	w.stock["holz"] = 0
	w.stock["kohle"] = 0
	var t0 := Game.time_days
	Game.time_days = Seasons.season_days() * 2.2  # Herbst
	need = Steward.needed(w)
	print("Verwalter ", _okf(need.get("job", "") == "holzfaeller"), " Herbst ohne Holz -> %s (%s, %.1f Tage Brennstoff)" % [need.get("job", ""), need.get("why", ""), Steward.fuel_days(w)])
	# Lager: Holz reichlich, Höchstmenge Stein 300
	w.stock["holz"] = 1000
	w.stock["stein"] = 0
	w.store_limits["stein"] = 300
	for s in adults:
		if s != keep:
			s.set_job("frei")
	need = Steward.needed(w)
	print("Verwalter ", _okf(need.get("job", "") == "steinmetz" or need.get("why", "") != ""), " Höchstmenge Stein 300 -> %s (%s)" % [need.get("job", ""), need.get("why", "")])
	Game.time_days = t0
	# >60 Siedler: nicht steuerbar
	print("Verwalter ", _okf(Steward.blocked_on(w) == "" and w.settlers.size() <= Steward.MAX_POP), " Insel mit %d Siedlern wird gesteuert" % w.settlers.size())
	# Speichern
	var d := {}
	Steward._on_save(d)
	var copy = JSON.parse_string(JSON.stringify(d))
	Steward._on_load(copy, 99)
	print("Verwalter ", _okf(Steward.on and Steward.offered and Steward.locked(keep)), " Speichern: an %s, Sperre %s" % [Steward.on, Steward.locked(keep)])
	# Läuft im Spiel: Essen leer, nach einer Weile arbeiten Leute für Essen
	_food_ids_zero(w)
	for s in adults:
		if s != keep:
			s.set_job("frei")
	await _wait(main, 3.0)
	food_n = adults.filter(func(s): return is_instance_valid(s) and s.job in Steward.FOOD_JOBS).size()
	print("Verwalter ", _okf(food_n >= 1), " im Spiel: %d holen Essen" % food_n)


## --stewardtest=routes mit --fixture=<sea.json> (vier Inseln): Mindeststand Stein auf der letzten Insel
## -> der Verwalter schickt ein freies Schiff mit Stein; Höchststand Holz auf Insel 1 -> Überschuss weg.
static func routes(main) -> void:
	await _wait(main, 0.5)
	var hud = main.hud
	if hud._hint_dialog != null and is_instance_valid(hud._hint_dialog):
		hud._hint_dialog.queue_free()
		hud._hint_dialog = null
	hud._offers.clear()
	Game.set_speed(1)
	Steward.on = true
	Data.balance["base_storage"] = 4000
	var ids: Array = Sea.settled_islands().map(func(m): return int(m.id))
	var to_id: int = ids[-1]
	var wt = Sea.worlds.get(to_id)
	var s0 := Game.amount("stein", wt)
	Steward.set_limits(to_id, "stein", s0 + 30, s0 + 60)
	Steward.route_tick()
	var trip := {}
	for sh in Sea.ships:
		if Sea.is_trip(sh) and int(sh.route[-1].island) == to_id:
			trip = sh
	print("Verwalter ", _okf(not trip.is_empty() and Steward.incoming(to_id, "stein") >= 5), " Mindeststand Stein auf %s -> %s" % [Sea.island_name(wt), Sea.plan_text(trip) if not trip.is_empty() else "kein Schiff"])
	for i in 4:
		Steward.route_tick()
	var n_trips := Sea.ships.filter(func(sh): return Sea.is_trip(sh) and int(sh.route[-1].island) == to_id).size()
	var coming: int = s0 + Steward.incoming(to_id, "stein")
	print("Verwalter ", _okf(coming >= s0 + 30 and coming <= s0 + 60 + 40), " schickt nur bis zum Höchststand: %d Fahrten, %d + %d unterwegs" % [n_trips, s0, Steward.incoming(to_id, "stein")])
	var t0 := Game.time_days
	while Game.time_days - t0 < 4.0 and not trip.is_empty() and Sea.is_trip(trip):
		await _wait(main, 0.2)
	print("Verwalter ", _okf(Game.amount("stein", wt) > s0), " Stein auf %s: %d -> %d" % [Sea.island_name(wt), s0, Game.amount("stein", wt)])
	# Höchststand: Holz auf Insel 1
	var w1 = Sea.worlds.get(ids[1])
	var h1 := Game.amount("holz", w1)
	Steward.set_limits(ids[1], "holz", 0, maxi(0, h1 - 30))
	Steward.route_tick()
	var out := Steward.outgoing(ids[1], "holz")
	print("Verwalter ", _okf(out >= 5), " Höchststand Holz auf %s (%d, max %d) -> %d werden abgeholt" % [Sea.island_name(w1), h1, h1 - 30, out])
	var d := {}
	Steward._on_save(d)
	var copy = JSON.parse_string(JSON.stringify(d))
	Steward._on_load(copy, 99)
	print("Verwalter ", _okf(Steward.limits(to_id, "stein")[0] == s0 + 30), " Speichern der Grenzen")
	# Schiffswahl (josh 2026-10-18): Kogge nur mit Hafen auf beiden Inseln, dann vor dem Ruderboot
	var home: int = ids[0]
	var hw = Sea.worlds.get(home)
	var kg: Dictionary = Sea._new_ship("kogge", home)
	for i in 3:
		hw.spawn_settler({"name": "Matrose %d" % i, "job": "seemann", "x": hw.center.x, "y": hw.center.y, "age": 25.0})
	Sea.fill_crew(kg)
	var pick := Steward._free_ship(home, to_id)
	print("Verwalter ", _okf(pick.get("type", "") == "boot"), " ohne Hafen auf %s fährt das Ruderboot (%s)" % [Sea.island_name(wt), pick.get("type", "-")])
	for w in [hw, wt]:
		if Sea.harbor_level(w) < 2:
			w.place_building("hafen", w.center + Vector2i(6, 6), true)
	pick = Steward._free_ship(home, to_id)
	print("Verwalter ", _okf(pick.get("type", "") == "kogge"), " mit Hafen auf beiden Inseln fährt die Kogge (%s)" % pick.get("type", "-"))


## --stewardtest=net mit --fixture=<sea.json>: Inselverbund ab Papier (Essen zur Heimatinsel, Rohstoff-Berufe
## dort überzählig, Forscher, Überschuss abholen), Rechenautomat-Bedingung und Automat ab Elektrizität.
static func _radio(main, w) -> void:
	main._place_on(w, "rundfunk")  # fertig gebaut


static func net(main) -> void:
	await _wait(main, 0.5)
	var hud = main.hud
	if hud._hint_dialog != null and is_instance_valid(hud._hint_dialog):
		hud._hint_dialog.queue_free()
		hud._hint_dialog = null
	hud._offers.clear()
	Game.set_speed(1)
	Steward.on = true
	Steward.offered = true
	Steward.offered_routes = true
	Data.balance["base_storage"] = 4000
	Game.research.done.erase("papier")
	Game.research.done.erase("elektrizitaet")
	print("Verwalter ", _okf(not Steward.net_active()), " ohne Papier kein Inselverbund")
	Game.research.done.append("papier")
	Game.refresh_effects()
	print("Verwalter ", _okf(not Steward.net_active()), " mit Papier, aber ohne Rundfunkanstalt: kein Inselverbund (josh 2026-10-21)")
	var hw = Sea.main_world()
	var home_id := int(hw.island_id)
	var ids: Array = Sea.settled_islands().map(func(m): return int(m.id)).filter(func(i): return i != home_id)
	var ow = Sea.worlds.get(ids[0])
	_radio(main, ow)
	print("Verwalter ", _okf(not Steward.net_active()), " Rundfunkanstalt nur auf der anderen Insel: Verbund ruht (Heimatinsel fehlt)")
	_radio(main, hw)
	print("Verwalter ", _okf(Steward.net_active() and Steward.net_member(hw) and Steward.net_member(ow)), " mit Rundfunkanstalt auf beiden Inseln: Inselverbund an")
	# Essen: Heimatinsel knapp (2 Tage), andere Insel reichlich
	for w in [hw, ow]:
		_food_ids_zero(w)
	ow.stock["fisch"] = 3000
	hw.stock["fisch"] = 100
	var fd := Game.food_days(hw)
	hw.stock["fisch"] = int(100.0 * 2.0 / maxf(0.01, fd))
	var need := Steward.needed(hw)
	print("Verwalter ", _okf(need.get("job", "") not in Steward.FOOD_JOBS), " Heimatinsel mit %.1f Tagen Essen holt nicht selbst (%s)" % [Game.food_days(hw), need.get("job", "-")])
	Steward.net_tick()
	print("Verwalter ", _okf(Steward.incoming(home_id, "fisch") > 0), " Schiff bringt %d Fisch zur Heimatinsel" % Steward.incoming(home_id, "fisch"))
	# Rohstoff-Berufe auf der Heimatinsel sind überzählig, auf der anderen nicht
	print("Verwalter ", _okf(Steward._surplus(hw, "holzfaeller") and not Steward._surplus(ow, "fischer")), " Heimatinsel: Holzfäller überzählig")
	# Andere Insel hält 6 Tage Essen vor
	_food_ids_zero(ow)
	ow.stock["fisch"] = 50
	need = Steward.needed(ow)
	print("Verwalter ", _okf(need.get("job", "") in Steward.FOOD_JOBS), " andere Insel holt Essen für die Heimatinsel (%s, %s)" % [need.get("job", ""), need.get("why", "")])
	# Forscher: freie Forschungsplätze auf der Heimatinsel
	hw.stock["fisch"] = 5000
	if Game.research.current == "":
		for t in Data.techs:
			if not Game.is_researched(t):
				Game.research.current = t
				break
	for s in hw.settlers:
		if s.is_adult() and s.job == "forscher":
			s.set_job("frei")
	hw.stock["holz"] = 2000
	need = Steward.needed(hw)
	var slots := 0
	for b in hw.buildings:
		if b.complete and b.def.has("research") and b.free_slots() > 0 and hw.pool_allows(b):
			slots += 1
	print("Verwalter ", _okf(slots == 0 or need.get("job", "") == "forscher" or need.get("job", "") == "baumeister"), " freie Forschungsplätze (%d) -> %s" % [slots, need.get("job", "")])
	# Überschuss abholen: viel Stein auf der anderen Insel
	ow.stock["stein"] = 600
	hw.stock["fisch"] = 0  # Platz im Lager der Heimatinsel, Essen und Brennstoff reichen trotzdem
	hw.stock["brot"] = 500
	hw.stock["holz"] = 0
	hw.stock["kohle"] = 400
	for i in 3:
		Steward.net_tick()
	var out := 0
	for i in ids:
		out += Steward.outgoing(i, "stein")
	var free := Sea.ships.filter(func(sh): return sh.state == "dock" and sh.route.is_empty()).size()
	print("Heimatinsel %.1f Tage Essen, %.1f Tage Brennstoff" % [Game.food_days(hw), Steward.fuel_days(hw)])
	print("Verwalter ", _okf(free == 0 or out >= 20 or Steward.incoming(home_id, "stein") >= 20), " Überschuss Stein wird abgeholt (%d, %d freie Schiffe)" % [maxi(out, Steward.incoming(home_id, "stein")), free])
	# Rechenautomat
	print("Verwalter ", _okf(not Game.is_unlocked("rechenautomat") and Steward.automaton_reason() != ""), " Rechenautomat noch nicht: %s" % Steward.automaton_reason())
	# Automat ab Elektrizität
	print("Verwalter ", _okf(not Steward.automat_mode()), " vor Elektrizität: %s" % Steward.who())
	Game.research.done.append("elektrizitaet")
	print("Verwalter ", _okf(Steward.automat_mode()), " ab Elektrizität: %s" % Steward.who())
	await _wait(main, 0.5)
	print("Verwalter ", _okf(Steward.offered_automat and Steward.offered_net), " Angebote Inselverbund und Automat gezeigt")
	# Speichern
	Steward.set_net(false)
	var d := {}
	Steward._on_save(d)
	var copy = JSON.parse_string(JSON.stringify(d))
	Steward._on_load(copy, 99)
	print("Verwalter ", _okf(not Steward.net_on and Steward.offered_net), " Speichern: Inselverbund aus")


## --stewardtest=task mit --fixture=<sea.json>: Hauptaufgabe „Holz und Bretter“ auf einer anderen Insel ->
## der Verwalter setzt Holzfäller ein (auch aus anderen Berufen), sie sind nicht überzählig, Speichern.
## --stewardtest=taskshot: Inseln-Fenster mit offener Auswahl.
static func task(main, mode: String) -> void:
	await _wait(main, 0.5)
	var hud = main.hud
	if hud._hint_dialog != null and is_instance_valid(hud._hint_dialog):
		hud._hint_dialog.queue_free()
		hud._hint_dialog = null
	hud._offers.clear()
	Game.set_speed(1)
	Steward.on = true
	Steward.offered = true
	Steward.offered_routes = true
	var hw = Sea.main_world()
	var ow = Sea.all_worlds().filter(func(w): return w != hw and w.settlers.size() >= 3)[0]
	var oid := int(ow.island_id)
	if mode == "taskshot":
		Steward.set_tasks(oid, ["holz", "gold", "pilze"])
		Steward.set_tasks(int(hw.island_id), ["getreide"])
		hud._toggle(hud._sea_panel)
		await _wait(main, 0.3)
		hud._sea_panel._task_island = oid
		hud._sea_panel.refresh()
		await _wait(main, 0.3)
		hud._sea_panel._scroll.scroll_vertical = 230
		return
	Data.balance["base_storage"] = 6000
	for s in ow.settlers:
		if s.is_adult():
			s.set_job("fischer")
	ow.stock["fisch"] = 3000
	ow.stock["holz"] = 2000
	Steward.set_tasks(oid, ["holz"])
	var target := Steward.task_target(ow, "holzfaeller")
	for i in 20:
		Steward.tick(ow)
	var n := Steward._count(ow, "holzfaeller")
	print("Verwalter ", _okf(n >= target and target >= 1), " Hauptaufgabe Holz auf %s: %d Holzfäller (Ziel %d)" % [Sea.island_name(ow), n, target])
	print("Verwalter ", _okf(not Steward._surplus(ow, "holzfaeller")), " Holzfäller sind nicht überzählig, obwohl viel Holz da ist")
	var d := {}
	Steward._on_save(d)
	Steward._on_load(JSON.parse_string(JSON.stringify(d)), 99)
	print("Verwalter ", _okf(Steward.tasks_of(ow) == ["holz"]), " Speichern der Hauptaufgabe")
	# Mehrere Aufgaben: Holz und Pilze -> Holzfäller und Sammler, Sammler gehen zuerst an Pilzkreise
	Steward.toggle_task(oid, "pilze")
	var jobs := Steward.task_jobs(ow)
	print("Verwalter ", _okf(Steward.tasks_of(ow) == ["holz", "pilze"] and "holzfaeller" in jobs and "sammler" in jobs), " zwei Hauptaufgaben: %s" % ", ".join(PackedStringArray(jobs)))
	var order := IslandTraits.gather_order(Data.jobs.sammler.targets, ow)
	print("Verwalter ", _okf(order[0] == "pilzkreis"), " Sammler gehen zuerst an: %s" % order[0])
	Steward.toggle_task(oid, "gold")
	var st := IslandTraits.gather_order(Data.jobs.steinmetz.targets, ow)
	print("Verwalter ", _okf(st[0] == "goldader" and "steinmetz" in Steward.task_jobs(ow)), " Gold: Steinmetze zuerst an %s" % st[0])
	var d2 := {"steward": {"tasks": {str(oid): "holz"}}}
	Steward._on_load(d2, 99)
	print("Verwalter ", _okf(Steward.tasks_of(ow) == ["holz"]), " alter Spielstand mit einer Aufgabe lädt")
	Steward.toggle_task(oid, "")
	print("Verwalter ", _okf(Steward.tasks_of(ow).is_empty() and Steward.task_need(ow).is_empty()), " Hauptaufgabe aus")


## --stewardtest=busy mit --fixture=<sea.json>: Vergabestelle (Vorrang, Halte-Zeit), Auslastung (unter 80 % wird
## einer frei, dann ein Tag Ruhe; alle voll ausgelastet -> mehr Leute), Forscher unter 20 % -> Frage an den
## Spieler, mit Automat startet die nächste Forschung, neue Insel: Jäger-, dann Holzfäller-Hinweis.
## Druckt „Vergabe OK/FEHLER“ und am Ende „Vergabe OK (N Fehler)“.
static func busy(main) -> void:
	await _wait(main, 0.5)
	var fails := [0]
	var ok := func(c: bool, what: String):
		if not c:
			fails[0] += 1
		print("Vergabe ", _okf(c), " ", what)
	Game.set_speed(0)
	var w = Sea.main_world()
	for o in Sea.all_worlds():  # die Insel mit den meisten Siedlern
		if o.settlers.size() > w.settlers.size():
			w = o
	var ad: Array = w.settlers.filter(func(s): return s.is_adult())
	ok.call(ad.size() >= 5, "Insel mit %d Erwachsenen" % ad.size())
	# Vergabestelle
	var a = ad[0]
	JobDesk.release(int(a.id))
	JobDesk.assign(a, "holzfaeller", "spieler")
	ok.call(a.job == "holzfaeller" and not a.by_admin, "Spieler setzt Holzfäller")
	ok.call(not JobDesk.may(a, "verwalter") and not JobDesk.may(a, "automat") and not JobDesk.may(a, "ki"), "Spieler-Beruf hält gegen Verwalter, Automat und KI")
	ok.call(not JobDesk.assign(a, "fischer", "verwalter") and a.job == "holzfaeller", "Verwalter darf nicht umsetzen")
	JobDesk.release(int(a.id))
	JobDesk.assign(a, "fischer", "verwalter")
	ok.call(a.job == "fischer" and a.by_admin and not JobDesk.may(a, "verwalter") and not JobDesk.may(a, "zentrum"), "Verwalter hält gegen sich selbst und das KI-Zentrum")
	ok.call(JobDesk.may(a, "automat"), "Automat (Rang darüber) darf")
	Game.time_days += 0.6
	ok.call(JobDesk.may(a, "verwalter"), "nach der Halte-Zeit darf der Verwalter wieder")
	Steward.on = true
	ok.call(not JobDesk.center_allowed(w), "KI-Zentrum hält sich heraus, wenn der Verwalter steuert")
	# Auslastung: drei Holzfäller mit 30 %
	var cut := ad.slice(0, 3)
	for s in ad:
		JobDesk.release(int(s.id))
		s.set_job("sammler")
		s.busy = {"job": 1.0}
	for s in cut:
		s.set_job("holzfaeller")
		s.busy = {"job": 0.3, "idle": 0.7}
	ok.call(int(round(float(Steward.job_busy(w, "holzfaeller")[0]))) == 30, "Auslastung Holzfäller %s" % [Steward.job_busy(w, "holzfaeller")])
	Steward._trim_next.clear()
	Steward._trim(w)
	var n_h: int = w.settlers.filter(func(s): return s.job == "holzfaeller").size()
	ok.call(n_h == 2 and Steward._cooling(w, "holzfaeller"), "unter 80 %%: einer frei, Holzfäller jetzt %d" % n_h)
	Steward._trim(w)
	ok.call(w.settlers.filter(func(s): return s.job == "holzfaeller").size() == 2, "einen Tag Ruhe, dann wieder prüfen")
	# alle voll ausgelastet
	for s in ad:
		if s.job == "sammler":
			s.busy = {"job": 1.0}
	ok.call(Steward._busy_job(w) == "sammler", "alle Sammler voll ausgelastet -> mehr Sammler (%s)" % Steward._busy_job(w))
	# Forscher unter 20 %
	var r = ad[ad.size() - 1]
	JobDesk.release(int(r.id))
	r.set_job("forscher")
	r.busy = {"job": 0.1, "idle": 0.9}
	Game.research.current = ""
	Planner.on = false
	var ki_done: Array = Game.research.done.filter(func(t): return t in ["ki", "superintelligenz"])
	for t in ki_done:
		Game.research.done.erase(t)
	main.hud._offers.clear()
	Steward._research_asked = -99.0
	Steward._check_research(w)
	ok.call(main.hud._offers.has("forscher") and Steward.research_info != "", "Forscher 10 %%: Spieler wird gefragt (%s)" % Steward.research_info)
	main.hud._offers.clear()
	Steward._check_research(w)
	ok.call(not main.hud._offers.has("forscher"), "nicht gleich noch einmal fragen")
	Game.research.done.append_array(ki_done)
	if AiRule.ki() and Sea.is_main(w):
		Steward._check_research(w)
		ok.call(Game.research.current != "" or Planner.wanted_tech != "", "unter der KI: nächste Forschung von selbst (%s%s)" % [Game.research.current, Planner.wanted_tech])
	main.hud._show_offer("forscher")
	ok.call(main.hud._hint_dialog != null, "Fenster mit der Frage")
	if main.hud._hint_dialog != null:
		main.hud._hint_dialog.queue_free()
		main.hud._hint_dialog = null
	# Neue Insel
	var ow = null
	for o in Sea.all_worlds():
		if not Sea.is_main(o) and not o.settlers.is_empty():
			ow = o
	if ow != null:
		Hints.isl.clear()
		var keys: Array = Hints.island_guide()
		var id := str(int(ow.island_id))
		ok.call(keys.has(("isl_wood:" if Hints.tame(ow) else "isl_hunt:") + id), "neue Insel: erster Hinweis %s" % [keys])
		if keys.has("isl_hunt:" + id):
			for an in ow.animals.duplicate():
				if ow.adult_count(an.type) > 2:
					an.dead = true
			keys = Hints.island_guide()
			ok.call(keys.has("isl_wood:" + id), "Tiere bei 2 je Art: Holzfäller-Hinweis %s" % [keys])
		ok.call(Hints.island_guide().is_empty(), "kein Hinweis doppelt")
		ok.call(Hints.title("isl_wood:" + id).contains(Sea.island_name(ow)), "Überschrift mit Inselname: %s" % Hints.title("isl_wood:" + id))
	print("Vergabe ", _okf(fails[0] == 0), " (%d Fehler)" % fails[0])
