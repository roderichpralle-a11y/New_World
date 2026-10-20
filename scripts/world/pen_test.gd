class_name PenTest
extends RefCounted
## Selbsttest --pentest=1 (aus main.gd, josh 2026-10-20): Zaun um eine Wildschweinsuhle, Jagdhütte als
## Teil des Zauns. Prüft: geschlossenes Gehege, Tiere kommen nicht hinaus (Siedler schon), Jäger lauert in
## der Hütte und erlegt ein erwachsenes Tier, die anderen fliehen und bleiben fern, bis er das Fleisch
## geholt hat, 2 bleiben übrig, Junge kommen im Gehege zur Welt, Spielstand. Druckt "Gehege OK/FEHLER".
## --pentest=shot: nur das Gehege bauen (Bildschirmfoto).

static var fails := 0


static func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("Gehege ", "OK " if c else "FEHLER ", what)


static func _wait(main, cond: Callable, max_s: float) -> bool:
	var t := 0.0
	while not cond.call() and t < max_s:
		await main.get_tree().create_timer(0.25, true, false, true).timeout
		t += 0.25
	return cond.call()


## Freies Landstück 11x11 um c (kein Wasser, keine Gebäude).
static func _find_spot(w):
	for r in range(6, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c: Vector2i = w.center + Vector2i(dx, dy)
				var ok := true
				for y in range(-5, 6):
					for x in range(-5, 7):
						var cc := c + Vector2i(x, y)
						if not w.is_inside(cc) or w.is_water(cc) or w.building_at.has(cc):
							ok = false
							break
					if not ok:
						break
				if ok:
					return c
	return null


## Baut das Gehege: Zaunring (Halbbreite 4) um c, Jagdhütte rechts als Teil des Rings, Suhle in der
## Mitte, Beerensträucher und 4 erwachsene Wildschweine darin. Gibt [Suhle, Hütte] zurück.
static func build(w) -> Array:
	var c = _find_spot(w)
	if c == null:
		return []
	for y in range(-5, 6):
		for x in range(-5, 7):
			var n = w.node_at.get(c + Vector2i(x, y))
			if n != null:
				w.remove_node(n)
	var lodge = w.place_building("jagdhuette", c + Vector2i(4, -1), true)
	for i in range(-4, 5):
		for cc in [c + Vector2i(i, -4), c + Vector2i(i, 4), c + Vector2i(-4, i), c + Vector2i(4, i)]:
			if not w.building_at.has(cc):
				w.place_building("zaun", cc, true)
	var den = w.spawn_node("eberbau", c)
	for p in [Vector2i(-2, -2), Vector2i(2, 2), Vector2i(-2, 2)]:
		w.spawn_node("busch", c + p)
	for a in w.animals.duplicate():
		if a.type == "eber":
			w.animals.erase(a)
			a.queue_free()
	for i in 4:
		w.spawn_animal("eber", c + Vector2i(-1 + i % 3, 1), c, -1.0, -1.0, 1.0)
	return [den, lodge]


static func shot(main) -> void:
	_research(["tierhaltung", "waffenkunde"])
	var r := build(main.world)
	if not r.is_empty():
		main.camera.focus(r[0].position)


static func _research(ts: Array) -> void:
	for t in ts:
		if not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()


static func run(main) -> void:
	fails = 0
	var w = main.world
	_research(["tierhaltung", "waffenkunde", "eisenwerkzeuge"])
	var r := build(w)
	if r.is_empty():
		_ok(false, "kein Platz für das Gehege")
		return
	var den = r[0]
	var lodge = r[1]
	var c: Vector2i = den.cell
	var pen: int = w.pen_of(c + Vector2i(0, 1))
	_ok(pen > 0 and w.lodge_pen(lodge) == pen, "Zaun und Hütte schließen ein Gehege (%d, Hütte %d)" % [pen, w.lodge_pen(lodge)])
	_ok(w.pen_of(c + Vector2i(8, 0)) != pen, "draußen ist kein Gehege")
	_ok(w.find_animal_path(c + Vector2i(1, 1), c + Vector2i(8, 1)).is_empty(), "Tiere finden keinen Weg hinaus")
	_ok(not w.find_path(c + Vector2i(1, 1), c + Vector2i(8, 1)).is_empty(), "Siedler steigen über den Zaun")
	_ok(w.tile_mask(w.building_at[c + Vector2i(0, -4)]) == 10, "Zaunbild verbindet die Nachbarn (Maske %d)" % w.tile_mask(w.building_at[c + Vector2i(0, -4)]))
	# Jäger
	var hunter = w.settlers[0]
	hunter.set_job("jaeger")
	hunter.health = 100.0
	hunter.hunger = 100.0
	Engine.time_scale = 6.0
	var boars := func(): return w.animals.filter(func(a): return a.type == "eber" and not a.dead)
	var n0: int = boars.call().size()
	var kills0 := int(Game.stats.get("kills", 0))
	var hid := await _wait(main, func(): return hunter._hiding == lodge, 60.0)
	_ok(hid, "Jäger geht in die Jagdhütte (%s)" % hunter.activity)
	var shot := await _wait(main, func(): return int(Game.stats.get("kills", 0)) > kills0, 40.0)
	_ok(shot and boars.call().size() == n0 - 1, "Jäger erlegt ein Tier aus der Hütte (%d -> %d)" % [n0, boars.call().size()])
	var meat = w.pen_meat(pen)
	var shy: bool = boars.call().all(func(a): return a._shy != null and a.is_scared())
	_ok(meat != null and shy, "Fleisch liegt im Gehege, die anderen Tiere bleiben fern (%s)" % [boars.call().map(func(a): return a._shy != null)])
	var fetched := await _wait(main, func(): return w.pen_meat(pen) == null, 60.0)
	_ok(fetched, "Jäger holt das Fleisch (%s)" % hunter.activity)
	await _wait(main, func(): return boars.call().all(func(a): return a._shy == null), 5.0)
	_ok(boars.call().all(func(a): return a._shy == null), "danach laufen die Tiere wieder normal herum")
	# Weiter jagen bis zum Rest
	await _wait(main, func(): return boars.call().size() <= 2 and w.pen_meat(pen) == null, 150.0)
	await _wait(main, func(): return false, 15.0)
	_ok(boars.call().size() == 2, "von der Art bleiben 2 übrig (%d)" % boars.call().size())
	_ok(boars.call().all(func(a): return w.pen_of(a.cell) == pen), "kein Tier ist aus dem Gehege gekommen")
	# Nachwuchs im Gehege
	var kid = w._spawn_at_den(den, 0.0)
	_ok(kid != null and w.pen_of(kid.cell) == pen, "Junge kommen im Gehege zur Welt")
	# Wilde Tiere draußen bedrohen niemanden durch den Zaun
	var outside := c + Vector2i(6, 3)
	var s2 = w.settlers[1] if w.settlers.size() > 1 else hunter
	_ok(w.pen_of(outside) != pen, "Siedler draußen: kein Gehege")
	# Spielstand
	var data = JSON.parse_string(JSON.stringify(w.serialize()))
	_ok(data != null and str(data).find("zaun") >= 0 and str(data).find("jagdhuette") >= 0, "Zaun und Jagdhütte im Spielstand")
	Engine.time_scale = 1.0
	print("Gehege fertig: %d Fehler" % fails)
