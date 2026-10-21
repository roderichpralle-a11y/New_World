class_name AiRuleTest
extends RefCounted
## Selbsttest der KI-Herrschaft (AiRule). --aitest=1 mit --fixture=<sea.json>: KI übernimmt, überschreibt
## Spieler-Einstellungen nach 2 Minuten, Droiden zuerst auf die anderen Inseln, automatisierte Insel bleibt
## ohne Siedler bestehen, KI baut, Superintelligenz (kein Essen, Abriss, Natur weg, keine Häuser), Ende am
## Lagerfeuer, Speichern. Druckt „KI OK/FEHLER“. --aitest=shot: Ende am Lagerfeuer zeigen.


static func _okf(c: bool) -> String:
	return "OK" if c else "FEHLER"


static func _wait(main, secs: float) -> void:
	await main.get_tree().create_timer(secs, true, false, true).timeout


static func _close(hud) -> void:
	if hud._hint_dialog != null and is_instance_valid(hud._hint_dialog):
		hud._hint_dialog.queue_free()
		hud._hint_dialog = null
	hud._offers.clear()


static func run(main, mode: String) -> void:
	await _wait(main, 0.5)
	var hud = main.hud
	_close(hud)
	Game.set_speed(1)
	Steward.on = true
	for k in ["offered", "offered_routes", "offered_net", "offered_automat"]:
		Steward.set(k, true)
	Data.balance["base_storage"] = 6000
	for t in ["papier", "elektrizitaet", "computer", "robotik", "ki"]:
		if not Game.is_researched(t):
			Game.research.done.append(t)
	var hw = Sea.main_world()
	var outer: Array = AiRule.outer_worlds()
	if mode == "shot":
		await _shot(main, hw)
		return
	await _wait(main, 0.5)
	print("KI ", _okf(AiRule.offered_ki and Steward.who() == Loc.t("KI") or Steward.who() == "KI" or Steward.who() == "AI"), " KI übernimmt (%s)" % Steward.who())
	_close(hud)
	# Spieler schaltet aus: nach 2 Minuten wieder an
	Steward.set_on(false)
	Steward.set_limits(int(outer[0].island_id), "holz", 10, 50)
	AiRule.player_changed("minmax")
	AiRule.tick()
	print("KI ", _okf(not Steward.on), " Spieler darf ausschalten")
	Game.time_days += AiRule.OVERRIDE_DAYS + 0.01
	AiRule.tick()
	print("KI ", _okf(Steward.on and Steward.minmax.is_empty()), " nach 2 Minuten überschrieben (an %s, Grenzen %d)" % [Steward.on, Steward.minmax.size()])
	# Droiden zuerst auf die andere Insel
	var ow = outer[0]
	var adults_ow: Array = ow.settlers.filter(func(s): return s.is_adult() and Droids.replaceable(s.job))
	if adults_ow.is_empty() and not ow.settlers.is_empty():
		ow.settlers[0].set_job("holzfaeller")
		adults_ow = [ow.settlers[0]]
	var n0: int = ow.droids.size()
	Droids.build(hw, null)
	print("KI ", _okf(ow.droids.size() == n0 + 1), " erster Droide fährt nach %s" % Sea.island_name(ow))
	var guard := 0
	while not AiRule.automated(ow) and guard < 40:
		guard += 1
		Droids.build(hw, null)
	print("KI ", _okf(AiRule.automated(ow)), " %s automatisiert (%d Droiden)" % [Sea.island_name(ow), ow.droids.size()])
	var houses := func(w): return w.buildings.filter(func(b): return b.housing() > 0).size()
	var h0: int = houses.call(ow)
	for i in 40:
		AiRule._ki_tick()
	print("KI ", _okf(houses.call(ow) < h0 or h0 == 0), " Häuser abgerissen (%d -> %d)" % [h0, houses.call(ow)])
	for s in ow.settlers.duplicate():
		ow.kill_settler(s, "Test")
	print("KI ", _okf(Sea.meta(int(ow.island_id)).get("state", "") == "settled" and not Game.is_over), " Insel ohne Siedler bleibt mit Droiden bestehen")
	# Heimatinsel: Freie forschen
	var free_s = null
	for s in hw.settlers:
		if s.is_adult():
			free_s = s
			break
	free_s.set_job("frei")
	Steward.locks.erase(int(free_s.id))
	AiRule._ki_tick()
	print("KI ", _okf(free_s.job == "forscher"), " Freie auf der Heimatinsel forschen (%s)" % free_s.job)
	# Bauen
	for id in ["stahl", "ziegel", "elektronik", "maschinen", "glas"]:
		hw.stock[id] = 200
	for b in hw.construction_sites():
		hw.demolish(b)
	AiRule._build()
	print("KI ", _okf(not hw.construction_sites().is_empty()), " KI baut selbst: %s" % str(hw.construction_sites().map(func(b): return b.type)))
	# Superintelligenz
	Game.research.done.append("superintelligenz")
	await _wait(main, 0.5)
	_close(hud)
	print("KI ", _okf(AiRule.offered_si and not Game.is_unlocked("huette")), " Superintelligenz: keine Häuser mehr")
	hw.stock["fisch"] = 300
	var b0: int = hw.buildings.size()
	var nat0: int = hw.nodes.filter(func(n): return n.type in AiRule.NATURE).size()
	for i in 3:
		AiRule._si_tick()
	var food := 0
	for f in Data.food_ids():
		food += Game.amount(f, hw)
	print("KI ", _okf(food <= AiRule.FIRE_FOOD), " Essen nur noch am Lagerfeuer (%d)" % food)
	var useless: int = hw.buildings.filter(func(b): return Data.buildings[b.type].get("category", "") in AiRule.USELESS_CATS and not b.type in AiRule.KEEP_TYPES).size()
	print("KI ", _okf(hw.buildings.size() < b0 or useless == 0), " Nutzloses abgerissen (%d -> %d Gebäude, %d nutzlose übrig)" % [b0, hw.buildings.size(), useless])
	print("KI ", _okf(hw.nodes.filter(func(n): return n.type in AiRule.NATURE).size() < nat0 or nat0 == 0), " Natur gerodet (%d -> %d)" % [nat0, hw.nodes.filter(func(n): return n.type in AiRule.NATURE).size()])
	print("KI ", _okf(not ow.droids.any(func(d): return d.job in AiRule.FOOD_JOBS)), " Droiden machen kein Essen mehr")
	# Ende: bis auf 2 Siedler
	_keep_two(hw)
	AiRule._si_tick()
	await _wait(main, 3.0)
	_close(hud)
	var acts: Array = hw.settlers.map(func(s): return s.activity)
	print("KI ", _okf(AiRule.ending and hw.nodes.filter(func(n): return n.type in AiRule.NATURE).is_empty()), " Ende: keine Natur mehr, %s" % str(acts))
	var d := {}
	AiRule._on_save(d)
	AiRule._on_load(JSON.parse_string(JSON.stringify(d)), 99)
	print("KI ", _okf(AiRule.ending and AiRule.offered_si), " Speichern")


static func _shot(main, hw) -> void:
	Game.research.done.append("superintelligenz")
	AiRule.offered_ki = true
	AiRule.offered_si = true
	for b in hw.buildings.duplicate():
		if Data.buildings.get(b.type, {}).get("category", "") in AiRule.USELESS_CATS and not b.type in AiRule.KEEP_TYPES:
			hw.demolish(b)
	_keep_two(hw)
	var cf = AiRule.campfire(hw)
	for id in ["kraftwerk", "droidenfabrik", "elektronikwerk", "solarpark"]:
		if Data.buildings.has(id):
			var c = AiRule._spot(hw, id)
			if c != null:
				hw.place_building(id, c, true)
	for i in 4:
		var dd = hw.spawn_droid({"name": "D-%02d" % (i + 1), "x": cf.entrance_cell().x + i - 2, "y": cf.entrance_cell().y + 3})
		dd.set_job("steinmetz")
	hw.stock["strom"] = 300
	AiRule.start_ending()
	main.camera.focus(cf.position)
	await main.get_tree().create_timer(2.5, true, false, true).timeout
	main.camera.focus(cf.position)


## Alle Siedler auf den anderen Inseln und bis auf 2 auf der Heimatinsel sterben lassen.
static func _keep_two(hw) -> void:
	for w in AiRule.outer_worlds():
		for s in w.settlers.duplicate():
			w.kill_settler(s, "Test")
	for s in hw.settlers.duplicate():
		if hw.settlers.size() > 2:
			hw.kill_settler(s, "Test")
