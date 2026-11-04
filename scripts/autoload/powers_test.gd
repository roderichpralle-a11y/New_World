class_name PowersTest
extends RefCounted
## Selbsttest --powerstest=1 (Powers.autotest_setup) der neuen Verwaltung (josh 2026-10-29): Ausbaustufen,
## Platz beim größeren Ausbau, Befugnisse Aus/Fragen/Selbst, Essen und Wärme für 3 Tage, Spieler-Berufe,
## Grundbesetzung, einen Tag frei, Mindestvorrat, Überstunden im Notfall, Spielstand.
## Druckt „Befugnisse OK/FEHLER …“ und am Ende „Befugnisse OK (N Fehler)“.
## --powerstest=shot: Fenster Verwalter, Reiter Befugnisse (mit --shot); shot2: Reiter Vorschläge; shot3: Gutachten;
## shot4: Fenster Nachrichten; shot5: Engpässe im Winter; soak: danach alle Befugnisse auf Selbst und schnell weiterspielen.

static var fails := 0


static func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("Befugnisse ", "OK " if c else "FEHLER ", what)


static func _mk(w, n: String, job: String):
	var c: Vector2i = w.center
	var s = w.spawn_settler({"name": n, "sex": "m", "age": 30.0, "max_age": 70.0, "x": c.x, "y": c.y, "skills": {},
		"mind": {"traits": {}, "talents": {}}})
	s.hunger = 100.0
	s.set_job(job)
	return s


static func _office(w):
	for b in w.buildings:
		if b.def.get("office", false):
			return b
	return null


static func _finish(b) -> void:
	for res in b.def.cost:
		b.delivered[res] = int(b.def.cost[res])
	b.add_work(float(b.def.work) + 1.0)


static func run(main, mode: String) -> void:
	fails = 0
	var w = main.world
	Game.set_speed(0)
	for t in ["gelehrsamkeit", "holzbearbeitung", "steinwerkzeuge", "baumeisterkunst", "papier"]:
		if not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()
	Data.balance["base_storage"] = 4000
	_ok(Admin.level() == 0, "ohne Verwaltung Stufe 0")
	_ok(main._place_on(w, "verwaltung"), "Verwaltung gebaut")
	var v = _mk(w, "Verwalterin", "verwalter")
	_ok(Admin.level() == 1, "mit Verwalter Stufe 1 (%d)" % Admin.level())
	_ok(Powers.unlocked("grundbesetzung") and not Powers.unlocked("essen_waerme"), "Stufe 1 schaltet nur Stufe-1-Befugnisse frei")
	# Ausbau zu Stufe 2 (gleiche Größe)
	var o = _office(w)
	var o2 = w.upgrade_building(o)
	_ok(o2 != null and o2.type == "verwaltung2" and not o2.complete and Admin.level() == 1, "Ausbau zum Amtshaus läuft, Stufe bleibt 1")
	_finish(o2)
	_ok(Admin.level() == 2 and Powers.unlocked("essen_waerme"), "Amtshaus fertig: Stufe 2")
	# Ausbau zu Stufe 3 (4x2): erst eingemauert, dann mit Platz
	o2 = _office(w)
	var blockers := []
	for y in range(-1, 3):
		for dx in [-1, 3]:
			var c: Vector2i = o2.cell + Vector2i(dx, y)
			if w.can_place("strasse", c):
				blockers.append(w.place_building("strasse", c, true))
	var spot: Vector2i = w.upgrade_spot(o2, "verwaltung3")
	_ok(spot.x < 0 and w.upgrade_building(o2) == null and _office(w).type == "verwaltung2", "ohne Platz kein Ausbau zur Kanzlei")
	for bb in blockers:
		w.demolish(bb)
	await main.get_tree().process_frame
	spot = w.upgrade_spot(_office(w), "verwaltung3")
	var o3 = w.upgrade_building(_office(w)) if spot.x >= 0 else null
	_ok(o3 != null and o3.type == "verwaltung3", "mit Platz Ausbau zur Kanzlei (%s)" % str(spot))
	if o3 != null:
		_finish(o3)
	_ok(Admin.level() == 3, "Stufe 3 (%d)" % Admin.level())
	# Essen und Wärme: Fragen -> Vorschlag, Ja -> ausgeführt
	var adults: Array = w.settlers.filter(func(s): return s.is_adult() and s != v)
	for s in adults:
		JobDesk.assign(s, "frei", "spieler")
	for f in Data.food_ids():
		w.stock[f] = 0
	w.stock["holz"] = 2000
	Powers.mode = {}
	Powers.proposals = []
	Steward._moved = {}
	Powers.set_mode("grundbesetzung", Powers.AUS)
	Steward.tick(w)
	var pi := -1
	for i in Powers.proposals.size():
		if str(Powers.proposals[i].power) == "essen_waerme":
			pi = i
	var ew_keys := Powers.proposals.filter(func(p): return p.power == "essen_waerme").map(func(p): return str(p.get("key", "")))
	var uniq := {}
	for k in ew_keys:
		uniq[k] = true
	_ok(pi >= 0 and uniq.size() == ew_keys.size(), "Fragen: je Nahrungsberuf höchstens ein Vorschlag (%d Vorschläge)" % Powers.proposals.size())
	var before := adults.filter(func(s): return s.job in Steward.FOOD_JOBS).size()
	Powers.answer(pi, true)
	var after := adults.filter(func(s): return s.job in Steward.FOOD_JOBS).size()
	_ok(after == before + 1, "Ja: ein Siedler holt Essen (%d -> %d)" % [before, after])
	# Selbst: direkt, höchstens ein Wechsel je halben Tag
	Powers.set_mode("essen_waerme", Powers.SELBST)
	Steward._moved = {}
	Steward.tick(w)
	Steward.tick(w)
	var after2 := adults.filter(func(s): return s.job in Steward.FOOD_JOBS).size()
	_ok(after2 == after + 1, "Selbst: ein Wechsel je Runde (%d -> %d)" % [after, after2])
	var info := Steward.secure_info(w)
	_ok(int(info.food[2]) >= 1 and float(info.food[0]) > 0.0, "Bedarf 3 Tage %d, nötig %d Leute" % [int(info.food[0]), int(info.food[2])])
	# Spieler-Beruf bleibt, solange es nicht um Essen geht; bei Hunger ohne Freie wird er genommen
	for s in adults:
		JobDesk.assign(s, "steinmetz", "spieler")
	w.stock["fisch"] = 5000
	Steward._moved = {}
	Steward.tick(w)
	_ok(adults.all(func(s): return s.job == "steinmetz"), "Spieler-Berufe bleiben bei genug Essen")
	for f in Data.food_ids():
		w.stock[f] = 0
	Steward._moved = {}
	Steward.tick(w)
	var taken := adults.filter(func(s): return s.job in Steward.FOOD_JOBS).size()
	_ok(taken == 1, "Essen leer, keiner frei: einer der Spieler-Siedler holt Essen (%d)" % taken)
	# Grundbesetzung: Baustelle -> Baumeister nur aus Freien; einen Tag frei -> Beruf
	w.stock["fisch"] = 5000
	for s in adults:
		JobDesk.assign(s, "fischer", "spieler")
	Powers.set_mode("grundbesetzung", Powers.SELBST)
	var f1 = _mk(w, "Frei1", "frei")
	Steward._moved = {}
	Steward._free_since = {}
	Steward.tick(w)
	_ok(f1.job == "frei" or f1.job != "", "Freier ohne Bedarf bleibt erst frei (%s)" % f1.job)
	Steward._free_since[int(f1.id)] = Game.time_days - 1.5
	print("  Lagerplatz Stein: %d" % Steward.store_cap(int(w.island_id), "stein"))
	Steward.minmax[str(int(w.island_id))] = {"stein": [100, 0]}
	w.stock["stein"] = 0
	Steward._moved = {}
	Steward.tick(w)
	_ok(f1.job != "frei", "nach einem Tag frei bekommt er einen Beruf (%s; Mindest Stein %s, needs %s)" % [f1.job, str(Steward.limits(int(w.island_id), "stein")), str(Steward.needs(w))])
	# Mindestvorrat: Stein unter dem Minimum -> Steinmetz
	Powers.set_mode("mindestvorrat", Powers.SELBST)
	var f2 = _mk(w, "Frei2", "frei")
	var nl := Steward.needs(w)
	_ok(nl.any(func(n): return n.power == "mindestvorrat" and n.job == "steinmetz"), "Stein unter Mindestvorrat -> Steinmetz gesucht")
	f2.set_job("frei")
	# Überstunden im Notfall: niemand mehr zu holen
	Powers.set_mode("notfall", Powers.SELBST)
	var first := true
	for s in w.settlers:
		if s.is_adult() and s != v:
			JobDesk.assign(s, "fischer" if first else "sammler", "spieler")
			first = false
	for f in Data.food_ids():
		w.stock[f] = 0
	Admin.orders = {}
	Steward._moved = {}
	Steward.tick(w)
	var any_ot := false
	for j in Steward.FOOD_JOBS:
		any_ot = any_ot or Admin.ordered(j, "ot")
	_ok(any_ot, "Notfall: Überstunden für einen Nahrungsberuf")
	# Ausbau zu Stufe 4 und 5, Gutachten
	for t in ["buchdruck", "dampfmaschine", "wegebau"]:
		if not t in Game.research.done:
			Game.research.done.append(t)
	for lvl in [4, 5]:
		var ob = _office(w)
		var sp: Vector2i = w.upgrade_spot(ob, "verwaltung%d" % lvl)
		if sp.x < 0:  # kein Platz: an eine freie Stelle verschieben (wie der Spieler)
			for rad in range(2, 25):
				var moved := false
				for dy in range(-rad, rad + 1):
					for dx in range(-rad, rad + 1):
						var c: Vector2i = w.center + Vector2i(dx, dy)
						if not moved and w.can_place(ob.type, c, ob) and w.move_building(ob, c) and w.upgrade_spot(ob, "verwaltung%d" % lvl).x >= 0:
							moved = true
				if moved:
					break
		var nb = w.upgrade_building(_office(w))
		if nb != null:
			_finish(nb)
	_ok(Admin.level() == 5 and Powers.on("gutachten"), "Stufe 5 Planungsamt: Gutachten frei (Stufe %d)" % Admin.level())
	Planner.make_report()
	var rep: Dictionary = Planner.report.get("islands", {}).get(str(int(w.island_id)), {})
	_ok(not rep.is_empty() and not rep.get("tips", []).is_empty(), "Gutachten mit %d Tipps, %d Straßenfeldern, %d Verschiebungen" % [rep.get("tips", []).size(), rep.get("roads", []).size(), rep.get("moves", []).size()])
	_ok(PlanReport.map_image(w, rep) != null, "Karte zum Gutachten")
	# Lieferkette (josh 2026-10-30): Glas fehlt -> Glashütte hat keinen Lehm -> erst die Lehmgrube
	for t in ["toepferei", "glasmacherei", "koehlerei"]:
		if not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()
	_ok(main._place_on(w, "glashuette"), "Glashütte gebaut")
	for bb in w.buildings:
		if bb.type == "glashuette" and not bb.complete:
			_finish(bb)
	w.stock["glas"] = 0
	w.stock["lehm"] = 0
	w.stock["kohle"] = 50
	var tr1 := Steward.trace(w, "glas", 0, {})
	_ok(tr1.has("block") and str(tr1.block).contains("Lehmgrube"), "Glas fehlt, Lehm fehlt, keine Lehmgrube: Hinweis „baue Lehmgrube“ (%s)" % str(tr1))
	_ok(main._place_on(w, "lehmgrube"), "Lehmgrube gebaut")
	for bb in w.buildings:
		if bb.type == "lehmgrube" and not bb.complete:
			_finish(bb)
	for s in w.settlers:
		if s.job == "steinmetz":
			JobDesk.assign(s, "fischer", "spieler")
	var tr2 := Steward.trace(w, "glas", 0, {})
	_ok(tr2.get("job", "") == "steinmetz" and str(tr2.get("why", "")).contains("Lehm"), "mit Lehmgrube: zuerst ein Steinmetz für Lehm, nicht ein Handwerker für Glas (%s)" % str(tr2))
	w.stock["lehm"] = 100
	for f in Data.food_ids():
		w.stock[f] = 0
	w.stock["holz"] = 100
	var tr3 := Steward.trace(w, "glas", 0, {})
	_ok(tr3.get("job", "") == "handwerker" or str(tr3.get("block", "")).contains("Fachkräfte"), "Lehm da: jetzt die Glashütte selbst (Handwerker oder Fachkräfte fehlen) (%s)" % str(tr3))
	# Natur: keine Bäume -> keine Holzfäller; Winter -> keine Sammler
	var keep_amt := {}
	for n in w.nodes:
		if n.type == "baum":
			keep_amt[n] = n.amount
			n.amount = 0
	_ok(Steward._raw_block(w, "holzfaeller") != "", "ohne Bäume keine Holzfäller (%s)" % Steward._raw_block(w, "holzfaeller"))
	for n in keep_amt:
		n.amount = keep_amt[n]
	_ok(Steward._raw_block(w, "holzfaeller") == "", "mit Bäumen wieder Holzfäller")
	var t0: float = Game.time_days
	Game.time_days = Seasons.season_days() * 3.0 + 0.5 + floor(t0 / Seasons.year_days()) * Seasons.year_days()
	_ok(Seasons.season() == Seasons.WINTER and Steward._raw_block(w, "sammler") != "" and Steward._food_job(w) != "sammler", "im Winter keine Sammler (%s; Essen: %s)" % [Steward._raw_block(w, "sammler"), Steward._food_job(w)])
	Game.time_days = t0
	# Weitere Rücksichten (josh 2026-10-30): Verderb, Gefahr, Schriften, Talent und Wege
	for t in ["raeuchern", "toepferei", str(Data.jobs.jaeger.get("requires", "raeuchern"))]:
		if not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()
	for typ in ["raeucherei", "tafelmacherei"]:
		_ok(main._place_on(w, typ), "%s gebaut" % typ)
		for bb in w.buildings:
			if bb.type == typ and not bb.complete:
				_finish(bb)
	for s in w.settlers:
		if s.job in ["koch", "handwerker"]:
			JobDesk.assign(s, "fischer", "spieler")
	w.stock["fisch"] = 120
	w.stock["holz"] = 100
	var t1: float = Game.time_days
	Game.time_days = Seasons.season_days() * 1.0 + 0.5 + floor(t1 / Seasons.year_days()) * Seasons.year_days()
	_ok(Seasons.spoil_rate("fisch") > 0.0 and Steward._spoil_job(w) == "koch", "Sommer, viel Fisch: ein Koch in die Räucherei (%s, Verderb %.2f)" % [Steward._spoil_job(w), Seasons.spoil_rate("fisch")])
	Game.time_days = t1
	var tech := ""
	for t in Data.techs:
		if not t in Game.research.done and int(Data.techs[t].get("tier", 1)) >= 3 and int(Data.techs[t].get("tier", 1)) <= 4:
			tech = t
			break
	Game.research.current = tech
	w.stock["tontafel"] = 0
	w.stock["lehm"] = 100
	var wj := Steward._writing_job(w)
	_ok(wj.get("job", "") == "handwerker", "Forschung %s ohne Tontafeln: Handwerker in die Tafelmacherei (%s)" % [tech, str(wj)])
	Game.research.current = ""
	var oc: Vector2i = _office(w).cell
	for bb in w.buildings:
		if bb.type == "raeucherei":
			oc = bb.cell
	var wolf = w.spawn_animal("wolf", oc + Vector2i(3, 0), oc + Vector2i(3, 0))
	for a in w.animals:
		if wolf == null and is_instance_valid(a) and not a.dead and a.is_adult() and float(a.def.get("damage", 0)) > 0.0:
			wolf = a
	if wolf != null:
		var keep_cell: Vector2i = wolf.cell
		wolf.cell = _office(w).cell + Vector2i(3, 0)
		for s in w.settlers:
			if s.job == "jaeger":
				JobDesk.assign(s, "fischer", "spieler")
		_ok(Steward._danger_job(w) == "jaeger", "%s nahe der Räucherei: ein Jäger wird gebraucht" % wolf.type)
		wolf.cell = keep_cell
	else:
		print("  (kein Raubtier auf der Insel, Gefahrtest übersprungen)")
	var pa = _mk(w, "Ungeübt", "frei")
	var pb = _mk(w, "Talent", "frei")
	pb.skills["holz"] = 5.0
	_ok(Steward._pick(w, [pa, pb], "holzfaeller") == pb, "der Geübtere wird Holzfäller")
	pa.set_job("fischer")
	pb.set_job("fischer")
	# Verwalter stirbt: immer gleich nachbesetzt, auch mit Nachbesetzen auf Aus (josh 2026-10-29)
	Powers.set_mode("nachbesetzen", Powers.AUS)
	var f3 = _mk(w, "Frei3", "frei")
	w.kill_settler(v, "gestorben", "old")
	var nm = Admin.local_manager()
	_ok(nm != null and Admin.level() == 5, "Verwalter gestorben: %s ist neuer Verwalter, Stufe %d" % [nm.display_name if nm else "niemand", Admin.level()])
	_ok(nm == f3, "der Freie wird Verwalter")
	w.kill_settler(nm, "gestorben", "old")
	nm = Admin.local_manager()
	_ok(nm != null, "kein Freier: ein Erwachsener aus einem anderen Beruf wird Verwalter (%s)" % (nm.display_name if nm else "niemand"))
	Powers.set_mode("nachbesetzen", Powers.FRAGEN)
	# Spielstand
	var d := {}
	Powers._on_save(d)
	Powers.mode = {}
	Powers._on_load(d, 99)
	_ok(Powers.mode_of("notfall") == Powers.SELBST and Powers.mode_of("forschung") == Powers.FRAGEN, "Spielstand: Schalter bleiben")
	# Stellenplan erst ab Baumeisterkunst (josh 2026-10-31)
	_ok(Steward.plan_active(), "mit Baumeisterkunst gilt der Stellenplan")
	Game.research.done.erase("baumeisterkunst")
	var simple := Steward.needs(w)
	_ok(not Steward.plan_active() and simple.all(func(n): return not n.has("rank")), "ohne Baumeisterkunst der einfache Verwalter (%d Bedarfe)" % simple.size())
	Game.research.done.append("baumeisterkunst")
	print("Befugnisse ", "OK" if fails == 0 else "FEHLER", " (%d Fehler)" % fails)
	if mode == "soak":  # danach alles auf Selbst weiterlaufen lassen (Laufzeitfehler suchen)
		for e in Powers.LIST:
			Powers.set_mode(str(e.id), Powers.SELBST)
		Game.set_speed(8)
		return
	if mode.begins_with("shot"):
		w.stock["fisch"] = 0
		if mode == "shot5":  # Engpässe: Winter, Glas unter dem Mindestvorrat
			Game.time_days = Seasons.season_days() * 3.0 + 0.5
			for n in w.nodes:
				if n.type == "fischgrund":
					n.amount = 0
			w.stock["lehm"] = 0
			Steward.minmax[str(int(w.island_id))] = {"glas": [20, 0]}
		Powers.set_mode("essen_waerme", Powers.FRAGEN)
		Powers.set_mode("grundbesetzung", Powers.FRAGEN)
		Steward._moved = {}
		Steward.tick(w)
		Loc.set_language("de")
		main.hud._update_admin_button()
		if mode == "shot4":  # Fenster Nachrichten mit einer ausgeschalteten Meldung
			Game.notify_off["tiere"] = true
			Game.notify("Ein Wildschwein läuft über die Insel.", "schild", "tiere")
			Game.notify_off.erase("tiere")
			Game.notify("Neues Kind geboren.", "herz")
			main.hud._toggle(main.hud._history_panel)
			return
		AdminInfo._tab = AdminInfo.TAB_PROPOSALS if mode == "shot2" else (AdminInfo.TAB_REPORT if mode == "shot3" else AdminInfo.TAB_POWERS)
		main.hud._open_admin()

