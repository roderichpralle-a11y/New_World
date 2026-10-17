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
