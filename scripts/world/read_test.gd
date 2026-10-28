class_name ReadTest
extends RefCounted
## Selbsttest --readtest=1 (aus main.gd, josh 2026-10-20): Druckerei macht aus Papier Bücher und Zeitungen,
## Steinhaus-Bewohner brauchen Lesestoff erst ab der Forschung Papier, Siedler lesen in der Freizeit
## (Buch oder Zeitung in der Hand), machen dann längere Pausen, Kinder lernen schneller. "Lesen OK/FEHLER".
## --readtest=shot: zwei Siedler lesen am Feuer und im Grünen (Bildschirmfoto).

static var fails := 0


static func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("Lesen ", "OK " if c else "FEHLER ", what)


static func _wait(main, cond: Callable, max_s: float) -> bool:
	var t := 0.0
	while not cond.call() and t < max_s:
		await main.get_tree().create_timer(0.25, true, false, true).timeout
		t += 0.25
	return cond.call()


static func _research(ts: Array) -> void:
	for t in ts:
		if not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()


## Siedler s liest jetzt (Buch oder Zeitung) an Zelle c.
static func _read_now(s, tool: String, text: String) -> void:
	s.abort_plan()
	s._plan.append({"a": "wait", "t": 600.0, "rest": true, "act": text, "read": tool})
	s.activity = text


static func shot(main) -> void:
	var w = main.world
	_research(["papier"])
	Game.add_stock("zeitungen", 20, w)
	Game.add_stock("buecher", 10, w)
	var fire = w.fire_building()
	var i := 0
	for s in w.settlers:
		if not s.is_adult():
			continue
		var c: Vector2i = fire.cell + (Vector2i(1, 1) if i == 0 else Vector2i(-1, 1))
		s.cell = c
		s.position = w.cell_to_pos(c)
		_read_now(s, "book" if i == 0 else "newspaper", "Liest")
		s._face(Vector2(-1, 0) if i == 0 else Vector2(1, 0))
		i += 1
	main.camera.focus(fire.position)


static func run(main) -> void:
	fails = 0
	var w = main.world
	var lesen := func(): return HouseNeeds.level_needs(3).any(func(nd): return nd.id == "lesen")
	_ok(not lesen.call(), "vor der Forschung Papier braucht niemand Lesestoff")
	# genug Forschung, damit es Freizeit gibt (SettlerMind.comfort)
	var many := ["papier"]
	for t in Data.techs:
		if many.size() < 14 and int(Data.techs[t].get("tier", 99)) <= 5:
			many.append(t)
	_research(many)
	_ok(lesen.call(), "mit Papier brauchen Steinhäuser Lesestoff (Stufe 3)")
	_ok(Data.buildings.has("druckerei") and Data.buildings.druckerei.requires == "papier", "Druckerei mit der Forschung Papier")
	var s = w.settlers[0]
	var share0: float = s.mind.leisure_share()
	Game.add_stock("zeitungen", 20, w)
	var share1: float = s.mind.leisure_share()
	_ok(share1 > share0 or share0 >= 0.45, "mit Lesestoff etwas längere Pausen (%.3f -> %.3f)" % [share0, share1])
	# Freizeit: liest
	var reads := 0
	for i in 40:
		s.abort_plan()
		s._plan_leisure()
		for st in s._plan:
			if st.get("read", "") != "":
				reads += 1
	_ok(reads >= 10, "in der Freizeit liest er oft (%d von 40)" % reads)
	_read_now(s, "newspaper", "Liest")
	await main.get_tree().create_timer(0.3).timeout
	if s._sied_kind != "":
		# Siedler-Bögen (2.0): die Zeitung ist gezeichnet, die Figur zeigt die Zeilen "Zeitung lesen"
		var row: int = s._layers["fig"].frame / 8
		_ok(s._sied_kind == "frei" and row / 3 == int(Settler.SIED_FREI["zeitung"]), "Zeitung in der Hand (Bogen-Zeile %d)" % row)
	else:
		_ok(s._tool.visible and s._tool.texture == Data.tool_tex("newspaper"), "Zeitung in der Hand")
	# Kinder lernen schneller
	var xp0 := 0.0
	var xp1 := 0.0
	var k = s
	var prev_age: float = k.age
	k.age = 2.0
	var before: Dictionary = k.skill_xp.duplicate()
	for sk in k.skill_xp:
		k.skill_xp[sk] = 0.0
	before = k.skill_xp.duplicate()
	var start_xp: Dictionary = k.skill_xp.duplicate()
	var start_sk: Dictionary = k.skills.duplicate()
	Game.take_stock("zeitungen", Game.amount("zeitungen", w), w)
	Game.take_stock("buecher", Game.amount("buecher", w), w)
	k._learn_as_child(0.01, true)
	for sk in k.skill_xp:
		xp0 += float(k.skill_xp[sk]) - float(before.get(sk, 0.0))
	k.skill_xp = start_xp.duplicate()
	k.skills = start_sk.duplicate()
	before = k.skill_xp.duplicate()
	Game.add_stock("buecher", 5, w)
	k._learn_as_child(0.01, true)
	for sk in k.skill_xp:
		xp1 += float(k.skill_xp[sk]) - float(before.get(sk, 0.0))
	k.age = prev_age
	_ok(xp1 > xp0 * 1.2, "Kinder lernen mit Büchern schneller (%.1f -> %.1f)" % [xp0, xp1])
	# Bedarf verbraucht Zeitungen, sonst Bücher
	var nd: Dictionary = HouseNeeds.level_needs(3).filter(func(n): return n.id == "lesen")[0]
	var st := {"acc": {}}
	Game.take_stock("buecher", Game.amount("buecher", w), w)
	Game.add_stock("buecher", 5, w)
	var v: float = HouseNeeds._eval(w, st, nd, 10.0, 2.0)
	_ok(v >= 0.99 and Game.amount("buecher", w) < 5, "ohne Zeitungen werden Bücher gelesen (%.2f, Bücher %d)" % [v, Game.amount("buecher", w)])
	print("Lesen fertig: %d Fehler" % fails)
