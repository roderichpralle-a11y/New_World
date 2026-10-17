class_name RouteTest
extends RefCounted
## Selbsttest für „Einmal hin und zurück“ (Sea.set_route_once). Kein Autoload; Sea.autotest_setup ruft ihn.
##   --oncetest=1 mit --fixture=<sea.json> (mindestens zwei besiedelte Inseln): ein freies Schiff auf
##   Insel 0 fährt einmal 0 -> 1 -> 0 (Holz hin, eine Ware von Insel 1 zurück), ist danach frei (Route
##   angehalten, Halte bleiben, Ladung leer), Speichern/Laden mitten auf der Fahrt (JSON), eine alte
##   Route ohne "once" fährt weiter. Druckt „Einmal-Route OK/FEHLER“. --oncetest=shot: nur die Route des
##   Schiffs, das --panel=sea --seaview=ship zeigt, auf „Einmal hin und zurück“ stellen.


static func _okf(c: bool) -> String:
	return "OK" if c else "FEHLER"


static func _wait(main, secs: float) -> void:
	await main.get_tree().create_timer(secs, true, false, true).timeout


## Bildschirmfoto: die Schiffsansicht der Seekarte immer ganz nach unten rollen (Fahrtart sichtbar).
static func _keep_scrolled(main) -> void:
	for i in 80:
		await _wait(main, 0.25)
		var sp = main.hud._sea_panel
		if sp != null and sp._scroll != null:
			sp._scroll.scroll_vertical = 100000


static func once_test(main, mode: String = "1") -> void:
	if mode == "shot":  # Bildschirmfoto: das Schiff, das --seaview=ship zeigt, fährt einmal
		var last := {}
		for s in Sea.ships:
			if not s.route.is_empty():
				last = s
		if not last.is_empty():
			Sea.set_route_once(last, true)
			last["once_from"] = int(last.leg)
			last["once_left"] = 9  # läuft schon, damit die Zeile „Noch … Halte“ zu sehen ist
		_keep_scrolled(main)  # läuft nebenher (ohne await)
		return
	var w0 = Sea.worlds.get(0)
	var w1 = Sea.worlds.get(1)
	if w0 == null or w1 == null:
		print("Einmal-Route FEHLER: braucht zwei besiedelte Inseln (--fixture=sea.json)")
		return
	Data.balance["base_storage"] = 4000
	# Ein freies Schiff auf Insel 0 mit Besatzung
	var sh := {}
	for s in Sea.idle_ships(0):
		if s.route.is_empty():
			sh = s
			break
	if sh.is_empty():
		print("Einmal-Route FEHLER: kein freies Schiff auf Insel 0")
		return
	Sea.fill_crew(sh)
	if Sea.crew_missing(sh) > 0:
		Sea.hire_sailor(sh)
	# Rückfracht: Stein (wird nicht gegessen und nicht verheizt)
	var back := "stein"
	Game.add_stock(back, 20, w1)
	Game.add_stock("holz", 40, w0)
	# Alte Route ohne "once" (eine andere Fahrt im Spielstand) zum Vergleich
	var old := {}
	for s in Sea.ships:
		if s != sh and s.route.size() >= 2 and not s.paused and not s.has("once"):
			old = s
	var old_legs := []
	sh.route = [{"island": 0, "load": {"holz": 10}}, {"island": 1, "load": {back: 5}}]
	sh.leg = 0
	sh.paused = false
	Sea.set_route_once(sh, true)
	var h0 := Game.amount("holz", w1)
	var b0 := Game.amount(back, w0)
	print("Einmal-Route: %s, 0 -> 1 -> 0, Holz hin, %s zurück | Insel 1 Holz %d, Insel 0 %s %d | alte Route: %s" % [
		Sea.ship_label(sh), back, h0, back, b0, Sea.ship_label(old) if not old.is_empty() else Loc.t("keine")])
	var seen := []  # Inseln, an denen geladen wurde, in Reihenfolge
	var left_seen := []
	var saved := false
	var t0 := Game.time_days
	var last_state := ""
	var legs_cargo := []  # Ladung beim Ablegen
	while Game.time_days - t0 < 8.0:
		await _wait(main, 0.1)
		if sh.state == "load" and last_state != "load":
			seen.append(int(sh.at))
			left_seen.append(int(sh.get("once_left", -1)))
		if sh.state == "sea" and last_state != "sea":
			legs_cargo.append(sh.cargo.duplicate())
		last_state = str(sh.state)
		if not old.is_empty() and (old_legs.is_empty() or old_legs[-1] != int(old.leg)):
			old_legs.append(int(old.leg))
		# Mitten auf der Fahrt: Spielstand als JSON hin und zurück (Zahlen werden float)
		if not saved and sh.state == "sea" and seen.size() == 1:
			saved = true
			var data = JSON.parse_string(JSON.stringify(Sea.serialize()))
			var copy := {}
			for e in data.ships:
				if int(e.id) == int(sh.id):
					copy = e
			var save_ok: bool = bool(copy.get("once", false)) and int(copy.get("once_left", -1)) == 2 and copy.get("route", []).size() == 2
			for k in ["once", "once_left", "once_from"]:
				sh[k] = copy.get(k)  # weiter mit den Werten aus dem JSON (float)
			print("Einmal-Route ", _okf(save_ok), " Speichern mitten auf der Fahrt: once %s, noch %s Halte" % [copy.get("once"), copy.get("once_left")])
		if sh.paused and sh.state == "dock" and seen.size() >= 3:
			break
	var days := Game.time_days - t0
	var h1 := Game.amount("holz", w1)
	var b1 := Game.amount(back, w0)
	print("Einmal-Route: Halte %s (noch %s), %.2f Tage" % [seen, left_seen, days])
	print("Einmal-Route ", _okf(seen == [0, 1, 0]), " fährt 0 -> 1 -> 0 und hält dann")
	var cargo_ok: bool = legs_cargo.size() >= 2 and int(legs_cargo[0].get("holz", 0)) == 10 and int(legs_cargo[0].get(back, 0)) == 0 \
		and int(legs_cargo[1].get(back, 0)) == 5 and int(legs_cargo[1].get("holz", 0)) == 0 and b1 >= b0 + 5
	print("Einmal-Route ", _okf(cargo_ok), " Ladung hin %s, zurück %s, am Ende abgeladen: Insel 0 %s %d -> %d (Insel 1 Holz %d -> %d)" % [
		legs_cargo[0] if legs_cargo.size() > 0 else {}, legs_cargo[1] if legs_cargo.size() > 1 else {}, back, b0, b1, h0, h1])
	var free: bool = sh.paused and sh.state == "dock" and int(sh.at) == 0 and sh.cargo.is_empty() and Sea.idle_ships(0).has(sh)
	print("Einmal-Route ", _okf(free), " danach frei auf Insel 0 (angehalten %s, Ladung %s, frei %s)" % [sh.paused, Sea.goods_text(sh.cargo), Sea.idle_ships(0).has(sh)])
	print("Einmal-Route ", _okf(sh.route.size() == 2 and int(sh.leg) == 0 and int(sh.once_left) == -1 and Sea.is_once(sh)), " Halte bleiben für „Route starten“ (Halt %d, Einmal %s)" % [int(sh.leg) + 1, Sea.is_once(sh)])
	if not old.is_empty():
		print("Einmal-Route ", _okf(not old.paused and not Sea.is_once(old) and old_legs.size() >= 3), " alte Route fährt weiter: Halte %s" % [old_legs])
	# Noch einmal starten: zählt neu
	sh.paused = false
	await _wait(main, 0.6)
	print("Einmal-Route ", _okf(int(sh.get("once_left", -1)) == 2 or sh.state == "sea"), " neu gestartet: %s, noch %d Halte" % [Sea.ship_status(sh), Sea.once_stops_left(sh)])
	# Umstellen auf Immer wieder: zählt nicht mehr
	Sea.set_route_once(sh, false)
	print("Einmal-Route ", _okf(not Sea.is_once(sh) and Sea.once_stops_left(sh) == 0), " umgestellt auf Immer wieder")


## --oncetest=trip mit --fixture=<sea.json>: „Einmal schicken“ (Sea.start_trip) von Insel 0 aus: fährt nach 1,
## lädt Stein, bringt ihn nach 0, ist danach frei (Route leer); Speichern/Laden mitten auf der Fahrt. Dann eine
## Route 0 -> 1 mit Zwischenhalt-Austausch an 1 (lädt nur 5 Holz ab, lädt 5 Stein dazu). Druckt „Fahrt OK/FEHLER“.
static func trip_test(main) -> void:
	var w0 = Sea.worlds.get(0)
	var w1 = Sea.worlds.get(1)
	if w0 == null or w1 == null:
		print("Fahrt FEHLER: braucht zwei besiedelte Inseln (--fixture=sea.json)")
		return
	Data.balance["base_storage"] = 4000
	var sh := {}
	for s in Sea.idle_ships(0):
		if s.route.is_empty():
			sh = s
			break
	if sh.is_empty():
		print("Fahrt FEHLER: kein freies Schiff auf Insel 0")
		return
	Sea.fill_crew(sh)
	if Sea.crew_missing(sh) > 0:
		Sea.hire_sailor(sh)
	Game.add_stock("stein", 30, w1)
	print("Fahrt ", _okf(Sea.start_trip(sh, 0, 0, {"stein": 10}) != ""), " gleiche Insel abgelehnt")
	print("Fahrt ", _okf(Sea.start_trip(sh, 1, 0, {}) != ""), " ohne Ware abgelehnt")
	var b0 := Game.amount("stein", w0)
	var err := Sea.start_trip(sh, 1, 0, {"stein": 10})
	print("Fahrt ", _okf(err == "" and Sea.is_trip(sh)), " Einmal: %s %s" % [Sea.plan_text(sh), err])
	var t0 := Game.time_days
	var saved := false
	var loaded_at := []
	var last := ""
	while Game.time_days - t0 < 6.0:
		await _wait(main, 0.1)
		if sh.state == "load" and last != "load":
			loaded_at.append(int(sh.at))
		last = str(sh.state)
		if not saved and sh.state == "sea" and loaded_at.size() == 1:
			saved = true
			var data = JSON.parse_string(JSON.stringify(Sea.serialize()))
			var copy := {}
			for e in data.ships:
				if int(e.id) == int(sh.id):
					copy = e
			var ok: bool = bool(copy.get("trip", false)) and copy.get("route", []).size() == 2 and not bool(copy.route[0].get("drop_all", true))
			print("Fahrt ", _okf(ok), " Speichern mitten auf der Fahrt: trip %s, Halte %d" % [copy.get("trip"), copy.get("route", []).size()])
		if not Sea.is_trip(sh) and sh.state == "dock":
			break
	var b1 := Game.amount("stein", w0)
	print("Fahrt ", _okf(loaded_at == [1, 0] and b1 >= b0 + 10), " fährt 1 -> 0, Stein auf Insel 0 %d -> %d (Halte %s, %.2f Tage)" % [b0, b1, loaded_at, Game.time_days - t0])
	print("Fahrt ", _okf(sh.route.is_empty() and not Sea.is_trip(sh) and sh.cargo.is_empty() and Sea.idle_ships(0).has(sh)), " danach frei (Route %d Halte, Ladung %s)" % [sh.route.size(), Sea.goods_text(sh.cargo)])
	# Route mit Austausch: an 1 nur 5 Holz abladen, 5 Stein dazuladen
	Game.add_stock("holz", 60, w0)
	sh.route = [{"island": 0, "load": {"holz": 20}, "drop_all": true, "drop": {}},
		{"island": 1, "load": {"stein": 5}, "drop_all": false, "drop": {"holz": 5}}]
	sh.leg = 0
	sh.paused = false
	var after1 := {}
	last = ""
	t0 = Game.time_days
	while Game.time_days - t0 < 4.0:
		await _wait(main, 0.1)
		if sh.state == "sea" and last != "sea" and int(sh.leg) == 0 and after1.is_empty() and Game.time_days - t0 > 0.05:
			after1 = sh.cargo.duplicate()
			break
		last = str(sh.state)
	print("Fahrt ", _okf(int(after1.get("holz", 0)) == 15 and int(after1.get("stein", 0)) == 5), " Austausch an Insel 1: an Bord %s" % [after1])
	sh.route = []
	sh.paused = false
