class_name PowersTest
extends RefCounted
## Selbsttest --powerstest=1 (Powers.autotest_setup) der Verwaltung, seit josh 2026-11-07 mit nur noch den
## Befugnissen Nachbesetzen und Auslastung: Ausbaustufen und Platz beim Ausbau, Liste der Befugnisse, Aus/Selbst,
## Auslastung (unter 80 % frei, über 90 % einer dazu, immer Baumeister und Fischer, unter 7 Erwachsenen Meldung und
## Holzfäller/Fischer/Sammler, dann Pause), Verwalter wird nachbesetzt, Spielstand, Fenster mit drei Reitern, ein
## Lied, Einführung überspringen mit Belohnung, die letzten zwei Siedler sterben nicht.
## Druckt „Befugnisse OK/FEHLER …“ und am Ende „Befugnisse OK (N Fehler)“.
## --powerstest=shot: Fenster Verwalter, Reiter Befugnisse (mit --shot); soak: danach schnell weiterspielen.

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


## Auslastung eines Siedlers festlegen: Anteil im Beruf in Prozent (Rest: nichts zu tun).
static func _busy(s, pct: float) -> void:
	s.busy = {"job": pct / 100.0, "other": 0.0, "idle": 1.0 - pct / 100.0}


static func _jobs(w) -> Dictionary:
	var out := {}
	for s in w.settlers:
		if s.is_adult():
			out[s.job] = int(out.get(s.job, 0)) + 1
	return out


## Eine Runde Auslastung (ohne das Einteilen der Freien, das prüft der Test eigens), ohne Wartezeiten.
static func _round(w) -> void:
	Steward._moved = {}
	Steward._job_moved = {}
	Steward.load_tick(w)


static func run(main, mode: String) -> void:
	fails = 0
	var w = main.world
	Game.set_speed(0)
	for t in ["gelehrsamkeit", "holzbearbeitung", "steinwerkzeuge", "baumeisterkunst", "papier"]:
		if not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()
	Data.balance["base_storage"] = 4000
	# Befugnisse
	var ids: Array = Powers.LIST.map(func(e): return str(e.id))
	_ok(ids == ["nachbesetzen", "auslastung"], "nur Nachbesetzen und Auslastung (%s)" % str(ids))
	_ok(Powers.info("auslastung").get("name", "") == "Auslastung", "Grundbesetzung heißt jetzt Auslastung")
	_ok(Admin.level() == 0, "ohne Verwaltung Stufe 0")
	_ok(main._place_on(w, "verwaltung"), "Verwaltung gebaut")
	var v = _mk(w, "Verwalterin", "verwalter")
	_ok(Admin.level() == 1 and Powers.unlocked("auslastung") and Powers.on("auslastung"), "mit Verwalter Stufe 1, Auslastung an (Standard Selbst)")
	# Ausbau zu Stufe 2 und 3 (Platz)
	var o2 = w.upgrade_building(_office(w))
	_ok(o2 != null and o2.type == "verwaltung2" and not o2.complete and Admin.level() == 1, "Ausbau zum Amtshaus läuft, Stufe bleibt 1")
	_finish(o2)
	_ok(Admin.level() == 2, "Amtshaus fertig: Stufe 2")
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
	w.stock["holz"] = 2000
	for f in Data.food_ids():
		w.stock[f] = 500
	# --- Weniger als 7 Erwachsene: Meldung, Holzfäller, Fischer, Sammler, dann Pause
	for s in w.settlers.duplicate():
		if s != v and s.is_adult():
			w.settlers.erase(s)
			s.queue_free()
	var few := []
	for i in 4:
		few.append(_mk(w, "Wenig%d" % i, "steinmetz"))
	_round(w)
	var got: Array = few.map(func(s): return s.job)
	_ok(got == ["holzfaeller", "fischer", "sammler", "holzfaeller"], "unter 7 Erwachsenen: Holzfäller, Fischer, Sammler der Reihe nach (%s)" % str(got))
	_ok(v.job == "verwalter", "der Verwalter bleibt Verwalter")
	_ok(Admin.log_entries.slice(maxi(0, Admin.log_entries.size() - 10)).any(func(e): return str(e[2]).contains("zu wenige") or str(e[2]).contains("too few")), "Meldung: zu wenige Siedler zum Steuern")
	few[0].set_job("steinmetz")
	_round(w)
	_ok(few[0].job == "steinmetz", "danach teilt er nicht mehr ein")
	# --- 7 und mehr: Auslastung
	for s in few:
		JobDesk.assign(s, "frei", "spieler")
	var sam := [_mk(w, "Sam1", "sammler"), _mk(w, "Sam2", "sammler"), _mk(w, "Sam3", "sammler")]
	var hol := [_mk(w, "Hol1", "holzfaeller"), _mk(w, "Hol2", "holzfaeller")]
	for s in sam:
		_busy(s, 50.0)
	for s in hol:
		_busy(s, 96.0)
	_ok(w.settlers.filter(func(s): return s.is_adult()).size() >= 7, "jetzt %d Erwachsene" % w.settlers.filter(func(s): return s.is_adult()).size())
	_round(w)
	var j1 := _jobs(w)
	_ok(int(j1.get("baumeister", 0)) == 1, "immer ein Baumeister (%s)" % str(j1))
	_ok(int(j1.get("fischer", 0)) == 1, "immer ein Fischer (%s)" % str(j1))
	_round(w)
	var j2 := _jobs(w)
	_ok(int(j2.get("sammler", 0)) == 2, "Sammler zu 50 %% ausgelastet: einer wird frei (%d Sammler)" % int(j2.get("sammler", 0)))
	_ok(int(j2.get("holzfaeller", 0)) == 3, "Holzfäller zu 96 %% ausgelastet: ein Freier kommt dazu (%d)" % int(j2.get("holzfaeller", 0)))
	# Zwischen 80 und 90 % bleibt alles
	for s in w.settlers:
		if s.is_adult() and s.job in ["sammler", "holzfaeller"]:
			_busy(s, 85.0)
	var j3a := _jobs(w)
	_round(w)
	var j3 := _jobs(w)
	_ok(int(j3.get("sammler", 0)) == int(j3a.get("sammler", 0)) and int(j3.get("holzfaeller", 0)) == int(j3a.get("holzfaeller", 0)), "zwischen 80 und 90 %% bleibt alles")
	# Der letzte Baumeister und der letzte Fischer werden nicht frei, auch wenn sie wenig zu tun haben
	for s in w.settlers:
		if s.is_adult() and s.job in ["baumeister", "fischer"]:
			_busy(s, 10.0)
	_round(w)
	var j4 := _jobs(w)
	_ok(int(j4.get("baumeister", 0)) == 1 and int(j4.get("fischer", 0)) == 1, "letzter Baumeister und Fischer bleiben (%s)" % str(j4))
	# Nach einem Wechsel wartet er, bis neu gemessen ist
	for s in w.settlers:
		if s.is_adult() and s.job == "sammler":
			_busy(s, 40.0)
	Steward._moved = {}
	Steward._job_moved = {}
	Steward.load_tick(w)
	var n1 := int(_jobs(w).get("sammler", 0))
	for s in w.settlers:
		if s.is_adult() and s.job == "sammler":
			_busy(s, 40.0)
	Steward._moved = {}
	Steward.load_tick(w)
	_ok(int(_jobs(w).get("sammler", 0)) == n1, "gleich danach kein zweiter Wechsel im selben Beruf")
	# Freie bekommen einen Beruf der Reihe nach, mit Prüfung nach einem Tag (josh 2026-11-07)
	var idl = _mk(w, "Idle1", "frei")
	JobDesk.assign(idl, "frei", "spieler")
	for k in 8:  # je Runde höchstens IDLE_PER_ROUND Freie
		if idl.job != "frei":
			break
		Steward.idle_tick(w)
	var first: String = idl.job
	_ok(first in Steward.IDLE_ORDER, "Freier (vom Spieler freigestellt) bekommt einen Beruf aus der Reihe (%s)" % first)
	_busy(idl, 20.0)
	idl.set_meta("try_at", Game.time_days - 2.0)
	Steward.idle_tick(w)
	var second: String = idl.job
	_ok(second != first and (second == "frei" or Steward.IDLE_ORDER.find(second) > Steward.IDLE_ORDER.find(first)), "klappt es nicht (20 %%), probiert er den nächsten Beruf (%s -> %s)" % [first, second])
	if second == "frei":
		Steward.idle_tick(w)
		second = idl.job
	_ok(second == "frei" or Steward.IDLE_ORDER.find(second) > Steward.IDLE_ORDER.find(first), "nächster Versuch weiter hinten in der Reihe (%s)" % second)
	_busy(idl, 95.0)
	idl.set_meta("try_at", Game.time_days - 2.0)
	var kept: String = idl.job
	Steward.idle_tick(w)
	_ok(idl.job == kept, "klappt es (95 %%), bleibt er (%s)" % idl.job)
	# Aus: nichts passiert
	Powers.set_mode("auslastung", Powers.AUS)
	var j5a := _jobs(w)
	_round(w)
	_ok(_jobs(w) == j5a, "Auslastung aus: keine Wechsel")
	Powers.set_mode("auslastung", Powers.SELBST)
	_ok(Powers.mode_of("auslastung") == Powers.SELBST, "wieder Selbst")
	# Andere Insel ohne Funknetz: nicht verwaltet
	_ok(Powers.covers(w), "Insel der Verwaltung wird verwaltet")
	# Verwalter stirbt: immer gleich nachbesetzt
	var f3 = _mk(w, "Frei3", "frei")
	w.kill_settler(v, "gestorben", "old")
	var nm = Admin.local_manager()
	_ok(nm != null, "Verwalter gestorben: %s ist neuer Verwalter" % (nm.display_name if nm else "niemand"))
	_ok(nm != null and nm.job == "verwalter", "ein Siedler wird Verwalter (%s)" % (nm.display_name if nm else "-"))
	f3.set_job("frei")
	# Spielstand
	Powers.set_mode("nachbesetzen", Powers.AUS)
	var d := {}
	Powers._on_save(d)
	Powers._on_load(d, 0)
	_ok(Powers.mode_of("nachbesetzen") == Powers.AUS and Powers.mode_of("auslastung") == Powers.SELBST, "Spielstand: Schalter bleiben")
	var old := {"powers": {"mode": {"grundbesetzung": Powers.AUS}}}
	Powers._on_load(old, 0)
	_ok(Powers.mode_of("auslastung") == Powers.SELBST, "alter Spielstand mit Grundbesetzung aus: Auslastung startet auf Selbst")
	# Nebeninsel ohne Rundfunkanstalt: Verwalter (und KI) steuern dort nichts (josh 2026-11-07 20:59)
	var m2: Dictionary = Sea.make_island(Sea.islands.size())
	Sea.islands.append(m2)
	var w2 = Sea.create_world_node(int(m2.id))
	w2.build_colony(m2)
	m2.state = "settled"
	var side := []
	for k in 9:
		var ns = w2.spawn_settler({"name": "N%d" % k, "sex": "m", "age": 30.0, "max_age": 70.0, "x": w2.center.x, "y": w2.center.y,
			"mind": {"traits": {}, "talents": {}}})
		ns.set_job("frei")
		side.append(ns)
	_ok(not Powers.covers(w2) and Steward.blocked_on(w2) != "", "Nebeninsel ohne Rundfunkanstalt: nicht verwaltet")
	KiBrain.on = true
	_ok(not KiBrain.controls(w2), "Nebeninsel ohne Rundfunkanstalt: die KI steuert dort auch nicht")
	KiBrain.on = false
	for k in 6:
		Steward._moved = {}
		Steward._next = 0.0
		Steward._process(0.0)
	_ok(side.all(func(o): return o.job == "frei"), "Nebeninsel ohne Rundfunkanstalt: der Verwalter teilt dort niemanden ein")
	# Siedler kommen per Schiff an (josh 2026-11-08): Beruf bleibt, aber nicht mehr „vom Verwalter zugewiesen“
	var mover = _mk(w, "Fahrgast", "frei")
	JobDesk.assign(mover, "holzfaeller", "verwalter", -1.0, true)
	var lab0: String = mover.job_label()
	var md: Dictionary = mover.serialize()
	w.remove_settler(mover)
	Sea._land(w2, [md], w2.center)
	var landed = null
	for o in w2.settlers:
		if o.display_name == "Fahrgast":
			landed = o
	_ok(str(md.get("job_by", "")) == "verwalter" and landed != null and landed.job == "holzfaeller" and not landed.by_admin and not landed.job_label().contains("("),
		"angekommen auf Insel ohne Verwalter: Beruf bleibt, ohne Verwalter (%s -> %s)" % [lab0, landed.job_label() if landed else "-"])
	for k in 6:
		Steward._moved = {}
		Steward._next = 0.0
		Steward._process(0.0)
	_ok(landed != null and landed.job == "holzfaeller", "der Verwalter ändert seinen Beruf dort nicht")
	if landed != null:
		side.append(landed)
	for o in side:
		w2.kill_settler(o, "test", "old")
	# Ausgeblendete Meldung: kein Ton (josh 2026-11-08)
	var was_off: bool = Game.notify_off.get("ereignis", false)
	Game.notify_off["ereignis"] = true
	Game.notify("Testmeldung stumm", "haendler", "ereignis")
	var sound_skipped: bool = int(Game._last_note[0]) == Engine.get_process_frames() and bool(Game._last_note[1])
	Game.notify_off["ereignis"] = false
	Game.notify("Testmeldung laut", "haendler", "ereignis")
	_ok(sound_skipped and not bool(Game._last_note[1]), "ausgeblendete Meldung ohne Ton, eingeschaltete mit Ton")
	Game.notify_off["ereignis"] = was_off
	# Lager ausbauen wie Wohnhäuser (josh 2026-11-08)
	if not "maurerei" in Game.research.done:
		Game.research.done.append("maurerei")
	var lg = null
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			if lg == null and w.can_place("grosslager", w.center + Vector2i(dx, dy)) and w.can_place("lager", w.center + Vector2i(dx, dy)):
				lg = w.place_building("lager", w.center + Vector2i(dx, dy), true)
	_ok(lg != null and lg.def.get("upgrade", "") == "grosslager", "Lagerhaus lässt sich zum Großen Lager ausbauen")
	if lg != null:
		var vol0 := Game.storage_volume(w)
		var gl = w.upgrade_building(lg)
		_ok(gl != null and gl.type == "grosslager" and not gl.complete, "Ausbau läuft: Baustelle Großes Lager")
		_ok(Game.storage_volume(w) == vol0, "während des Ausbaus bleibt der Stauraum (%d -> %d)" % [vol0, Game.storage_volume(w)])
		if gl != null:
			_finish(gl)
			_ok(gl.complete and Game.storage_volume(w) == vol0 - Game.building_volume(Data.buildings.lager) + Game.building_volume(Data.buildings.grosslager),
				"fertig: Stauraum %d" % Game.storage_volume(w))
	# Abriss einer Baustelle: alles eingeplante Material zurück (josh 2026-11-08)
	var site = null
	for dy in range(-14, 15):
		for dx in range(-14, 15):
			if site == null and w.can_place("lager", w.center + Vector2i(dx, dy)):
				site = w.place_building("lager", w.center + Vector2i(dx, dy), false)
	_ok(site != null and not site.complete, "Baustelle Lagerhaus steht")
	if site != null:
		var cres: Array = site.def.cost.keys()
		var r0: String = str(cres[0])
		Game.add_stock_over(r0, 10, w)
		var before := {}
		for r in cres:
			before[r] = Game.amount(r, w)
		site.deliver(r0, 2)  # schon geliefert
		var carrier = _mk(w, "Träger", "baumeister")
		carrier.carry_res = r0
		carrier.carry_n = 3  # unterwegs zur Baustelle
		carrier._incoming.append([site, r0, 3])
		site.incoming[r0] = 3
		var spent := {r0: 5}
		Game._stock_of(w)[r0] = Game.amount(r0, w) - 5  # die 5 kamen aus dem Lager
		w.demolish(site)
		var back_ok := true
		for r in cres:
			if Game.amount(r, w) != int(before[r]):
				back_ok = false
				print("Abriss Baustelle: ", r, " ", before[r], " -> ", Game.amount(r, w))
		_ok(back_ok and carrier.carry_n == 0, "Abriss einer Baustelle: geliefertes und getragenes Material kommt voll zurück (%s)" % str(spent))
		w.kill_settler(carrier, "test", "old")
	# Schalter „nur Spieler“ (josh 2026-11-07 18:43)
	_ok(Steward.IDLE_ORDER.find("steinmetz") == Steward.IDLE_ORDER.find("handwerker") + 1, "Steinmetz steht direkt nach Handwerker in der Reihe")
	var pc = _mk(w, "Spielerfigur", "holzfaeller")
	JobDesk.set_player_controlled(pc, true)
	_ok(not JobDesk.assign(pc, "frei", "verwalter", -1.0, true), "nur Spieler: Verwalter darf ihn nicht umsetzen, auch nicht mit force")
	_ok(not JobDesk.assign(pc, "bauer", "ki", 0.5, true) and pc.job == "holzfaeller", "nur Spieler: KI darf ihn nicht umsetzen")
	JobDesk.set_player_controlled(pc, false)
	_ok(JobDesk.assign(pc, "sammler", "verwalter") and pc.job == "sammler", "Schalter zurück: Verwalter darf ihn wieder einteilen")
	JobDesk.assign(pc, "holzfaeller", "spieler")
	_ok(JobDesk.player_controlled(pc), "vom Spieler eingeteilt: nur Spieler")
	for o in w.settlers:
		if o.is_adult() and o.job == "frei":
			o.set_job("sammler")
	var heir = _mk(w, "Erbe", "frei")
	w.kill_settler(pc, "gestorben", "old")
	_ok(heir.job == "holzfaeller", "nur Spieler, gestorben (Nachbesetzen aus): ein Freier übernimmt den Beruf (%s)" % heir.job)
	_ok(JobDesk.player_controlled(heir), "der Nachfolger wird ebenfalls nur vom Spieler gesteuert")
	Powers._on_load(d, 0)
	# Fenster Verwalter: drei Reiter
	_ok(AdminInfo.TAB_POWERS == 0 and AdminInfo.TAB_HOURS == 1 and AdminInfo.TAB_LOG == 2, "Fenster Verwalter: Befugnisse, Arbeitszeit, Log")
	# Ton: ein Lied
	_ok(Sound.MUSIC == ["lied"] and ResourceLoader.exists("res://assets/audio/music/lied.ogg"), "nur noch ein Lied")
	if mode.begins_with("shot"):
		Loc.set_language("de")
		AdminInfo._tab = AdminInfo.TAB_POWERS
		main.hud._open_admin()
		print("Befugnisse ", "OK" if fails == 0 else "FEHLER", " (%d Fehler)" % fails)
		return
	# Einführung überspringen: gilt als gelernt, mit Belohnung
	var hw = Sea.main_world()
	var gc = main.hud.goal_card
	var n_tut: int = Data.goals.get("tutorial", []).size()
	Game.goals.tut = 3
	var pop0: int = hw.settlers.size()
	var huts0: int = hw.buildings.filter(func(b): return b.type == "huette").size()
	gc._skip_tutorial()
	await main.get_tree().create_timer(1.0, true, false, true).timeout
	_ok(int(Game.goals.tut) == n_tut, "Einführung übersprungen: am Ende (%d/%d)" % [int(Game.goals.tut), n_tut])
	_ok(hw.settlers.size() >= pop0 + 2, "Belohnung: Siedler dazu (%d -> %d)" % [pop0, hw.settlers.size()])
	_ok(hw.buildings.filter(func(b): return b.type == "huette").size() > huts0, "Belohnung: Hütte")
	_ok(Game.is_researched("steinwerkzeuge") and Game.is_researched("flechtkoerbe"), "Belohnung: Forschungen der Einführung")
	if mode == "soak":
		print("Befugnisse ", "OK" if fails == 0 else "FEHLER", " (%d Fehler)" % fails)
		Game.set_speed(8)
		return
	# Die letzten zwei Siedler sterben nicht (josh 2026-11-07, wieder eingebaut)
	for s in hw.settlers.duplicate():
		if hw.settlers.size() <= 3:
			break
		hw.settlers.erase(s)
		s.queue_free()
	for wo in Sea.all_worlds():
		if wo != hw:
			for s in wo.settlers.duplicate():
				wo.settlers.erase(s)
				s.queue_free()
	var third = hw.settlers[2]
	hw.kill_settler(third, "test", "starve")
	_ok(Sea.total_people() == 2 and not hw.settlers.has(third), "Letzte zwei: ein dritter stirbt (%d leben)" % Sea.total_people())
	var a = hw.settlers[0]
	a.health = 0.0
	a.hunger = 0.0
	hw.kill_settler(a, "verhungert", "starve")
	_ok(hw.settlers.has(a) and a.health >= 40.0 and a.hunger >= 40.0, "Letzte zwei: verhungert nicht")
	a.age = a.max_age + 1.0
	hw.kill_settler(a, "alt", "old")
	_ok(hw.settlers.has(a) and a.age < a.max_age + Game.eff_add("life"), "Letzte zwei: stirbt nicht an Alter")
	a.take_damage(500.0, null)
	_ok(hw.settlers.has(a) and not Game.is_over, "Letzte zwei: überlebt Angriff")
	var b2 = hw.settlers[1]
	hw.settlers.erase(b2)
	b2.queue_free()
	Game.ensure_min_people()
	_ok(Sea.total_people() == 2, "Spielstand mit einem Siedler: wieder zwei (%d)" % Sea.total_people())
	print("Befugnisse ", "OK" if fails == 0 else "FEHLER", " (%d Fehler)" % fails)
