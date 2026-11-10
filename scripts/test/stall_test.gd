class_name StallTest
extends RefCounted
## Selbsttest --stalltest=1 (josh 2026-10-12): Schweinestall und Kuhstall ab Bergbau, ein Bauer füttert und
## melkt (Werkstattart "stall"), aus Getreide werden Fleisch und Milch; seit 2026-10-21 versorgt er auch den
## Hühnerhof (Eier). Druckt "Stall OK/FEHLER".

static var fails := 0


static func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("Stall %s %s" % ["OK" if c else "FEHLER", what])


static func run(main) -> void:
	fails = 0
	var w = main.world
	_ok(not Game.is_unlocked("schweinestall") and not Game.is_unlocked("kuhstall"), "ohne Bergbau keine Ställe")
	for t in ["steinwerkzeuge", "steinbruch", "toepferei", "koehlerei", "zimmerei", "bergbau", "gartenbau", "tierhaltung"]:
		if not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()
	_ok(Game.is_unlocked("schweinestall") and Game.is_unlocked("kuhstall"), "mit Bergbau: Schweinestall und Kuhstall")
	_ok(str(Data.buildings.huehnerhof.production.job) == "stall", "den Hühnerhof versorgt der Bauer (josh 2026-10-21)")
	_ok(main._place_on(w, "schweinestall") and main._place_on(w, "kuhstall") and main._place_on(w, "huehnerhof"), "Ställe und Hühnerhof gebaut")
	var farmer = null
	for s in w.settlers:
		if s.is_adult():
			s.set_job("bauer" if farmer == null else "sammler")
			if farmer == null:
				farmer = s
	Game.add_stock("weizen", 20, w)
	Game.add_stock("beeren", 30, w)
	for b in w.buildings:
		if b.type in ["schweinestall", "kuhstall"]:
			print("Stall: %s fertig=%s Hindernis '%s', Lager frei %d" % [b.type, b.complete, b.prod_blocker(), Game.space_for("milch", w)])
	var f0 := Game.amount("fleisch", w)
	var m0 := Game.amount("milch", w)
	var seen := {}
	var made := {}
	var t0 := Game.time_days
	while Game.time_days < t0 + 1.5 and (int(made.get("fleisch", 0)) <= 0 or int(made.get("milch", 0)) <= 0 or int(made.get("eier", 0)) <= 0):
		await main.get_tree().create_timer(0.25, true, false, true).timeout
		if Game.amount("weizen", w) < 6:
			Game.add_stock("weizen", 10, w)
		for id in ["fleisch", "milch", "eier"]:  # abräumen, damit das kleine Lager nicht vollläuft
			if Game.amount(id, w) > 0:
				made[id] = int(made.get(id, 0)) + Game.take_stock(id, Game.amount(id, w), w)
		seen[farmer.activity] = true
	_ok(int(made.get("fleisch", 0)) > 0 and int(made.get("milch", 0)) > 0 and int(made.get("eier", 0)) > 0, "der Bauer macht aus Getreide %s in %.2f Tagen" % [made, Game.time_days - t0])
	print("Stall: Tätigkeiten des Bauern ", seen.keys())
	var milk: Dictionary = Data.resources.get("milch", {})
	var meat: Dictionary = Data.resources.get("fleisch", {})
	_ok(int(milk.get("nutrition", 0)) > int(Data.resources.eier.nutrition) and int(meat.get("nutrition", 0)) > int(Data.resources.raeucherfisch.nutrition),
		"Milch (%d) und Fleisch (%d) machen besser satt als Eier und Räucherfisch" % [int(milk.get("nutrition", 0)), int(meat.get("nutrition", 0))])
	_ok("milch" in Seasons.cfg.get("perishable", []), "Milch verdirbt wie Eier")
	print("Stall %s (%d Fehler)" % ["OK" if fails == 0 else "FEHLER", fails])
