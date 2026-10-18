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
	print("Verwalter ", _okf(Steward.net_active()), " mit Papier: Inselverbund an")
	var hw = Sea.main_world()
	var home_id := int(hw.island_id)
	var ids: Array = Sea.settled_islands().map(func(m): return int(m.id)).filter(func(i): return i != home_id)
	var ow = Sea.worlds.get(ids[0])
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
