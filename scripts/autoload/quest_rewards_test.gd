class_name QuestRewardsTest
extends RefCounted
## Selbsttest --questadapt=1 (Quests.autotest_setup ruft ihn): Belohnungen passend zur Lage.
## Jede Lage wird direkt hergestellt (Lager, Jahreszeit, Forschung, Häuser) und 20-mal gewürfelt;
## gedruckt werden die gewählten Waren mit Grund und Menge. Ergebnis je Prüfung
## „Belohnung angepasst OK/FEHLER“. --questadapt=shot stellt nur ein Holzhaus ohne Bretter hin (fürs
## Bildschirmfoto mit --questshot=offers --panel=quests).


static func _okf(c: bool) -> String:
	return "OK" if c else "FEHLER"


static func _roll(w: int, times: int = 20) -> Dictionary:
	var tally := {}
	for i in times:
		QuestRewards.begin()
		var r := QuestRewards.goods(w, Quests.context())
		var k := "%s/%s" % [str(r.what), str(r.get("why", "-"))]
		if not tally.has(k):
			tally[k] = [0, int(r.n)]
		tally[k][0] += 1
	return tally


static func _has_why(tally: Dictionary, what: String, why: String) -> bool:
	return tally.has("%s/%s" % [what, why])


static func _top(tally: Dictionary) -> String:
	var best := ""
	for k in tally:
		if best == "" or int(tally[k][0]) > int(tally[best][0]):
			best = k
	return best


static func _set_food(w, days: float) -> void:
	for id in Data.food_ids():
		w.stock[id] = 0
	var p := maxi(1, Game.population())
	w.stock["beeren"] = ceili(days * p * float(Data.bal("hunger_per_day", 75.0)) * Game.eff("hunger") / Data.food_satiety("beeren"))


## Genau so viel, dass QuestRewards.plenty gilt (und ein bisschen mehr).
static func _rich(w, id: String) -> void:
	var units := Game.storage_volume(w) / maxi(1, Data.good_size(id))
	var p := Game.population()
	w.stock[id] = ceili(maxf(0.25 * units, 40.0 + 4.0 * p)) + 5


static func adapt_test(main, mode: String = "1") -> void:
	var w = Game.world
	if mode == "shot":  # Bildschirmfoto (mit --questshot=offers --panel=quests): Holzhaus ohne Möbel
		print("Belohnung angepasst: Bild, Holzhaus ", main._place_on(w, "holzhaus"))
		w.assign_homes()
		w.stock["bretter"] = 0
		return
	Data.balance["base_storage"] = 6000
	Game.goals["tut"] = Data.goals.get("tutorial", []).size()
	var keep_stock: Dictionary = w.stock.duplicate()
	var keep_done: Array = Game.research.done.duplicate()
	var keep_cur := str(Game.research.current)
	var keep_passed: int = Exams.passed
	var p := Game.population()
	print("Belohnung angepasst: Siedler %d, Zeitalter %d, Lager %d, Speise für Vorräte: %s" % [p, Game.current_age(), Game.storage_volume(w), QuestRewards.durable_food(0)])
	for id in ["holz", "stein", "bretter"]:
		_rich(w, id)  # genug da
	# 1 Hunger im Frühling: haltbare Speise, Menge reicht für etwa 3 Tage
	Seasons.jump_to_season(0)
	_set_food(w, 0.5)
	var t1 := _roll(1)
	print("Belohnung angepasst ", _okf(_top(t1).ends_with("/hunger") and _top(t1).begins_with("raeucherfisch")), " Hunger im Frühling (Essen 0,5 Tage): %s" % [t1])
	# 2 Herbst, Essen für 2,5 Tage, Holz reichlich: Wintervorrat
	Seasons.jump_to_season(2)
	_set_food(w, 2.5)
	var t2 := _roll(1)
	print("Belohnung angepasst ", _okf(_top(t2).ends_with("/winter")), " Herbst, Essen 2,5 Tage, Holz genug: %s" % [t2])
	# 3 Herbst, Essen reichlich, kein Holz: Heizholz, Menge nach Bedarf
	_set_food(w, 12.0)
	w.stock["holz"] = 0
	var need := ceili(float(Seasons.winter_wood_need()) * Quests.winter_mult())
	var t3 := _roll(1)
	var t3w := _roll(3)
	print("Belohnung angepasst ", _okf(_top(t3).begins_with("holz/heizen") and _top(t3w).begins_with("holz/heizen")), " Herbst, kein Holz (Winter braucht %d): Gewicht 1 %s | Gewicht 3 %s" % [need, t3, t3w])
	_rich(w, "holz")
	# 4 Frühling ohne Bedarf an Essen und Holz: nie Waren, von denen genug da ist; alles brauchbar
	Seasons.jump_to_season(0)
	var t4 := _roll(1, 40)
	var bad := []
	for k in t4:
		var id: String = k.split("/")[0]
		if QuestRewards.plenty(id) or not QuestRewards.usable(id):
			bad.append(k)
	print("Belohnung angepasst ", _okf(bad.is_empty() and not t4.keys().any(func(k): return k.begins_with("holz/") or k.begins_with("gold/"))), " Frühling, Holz/Stein/Bretter reichlich, 40 Würfe: %s, unpassend: %s" % [t4, bad])
	# 5 Laufende Forschung im Altertum braucht Tontafeln
	Exams.passed = 1
	if not "toepferei" in Game.research.done:
		Game.research.done.append("toepferei")
	Writing.clear_cache()
	Game.research.current = "maurerei"
	w.stock["tontafel"] = 0
	var left := Writing.left_for("maurerei")
	var t5 := _roll(2)
	print("Belohnung angepasst ", _okf(t5.keys().any(func(k): return k.ends_with("/schrift"))), " Forschung Maurerei braucht %s: %s" % [left, t5])
	Game.research.current = keep_cur
	Exams.passed = keep_passed
	Game.research.done = keep_done.duplicate()
	Writing.clear_cache()
	# 6 Nächste Prüfung (Steinzeit verlangt ein Holzhaus): Bretter, sobald die Zimmerei wählbar ist
	w.stock["bretter"] = 0
	_rich(w, "holz")
	if not "zimmerei" in Game.research.done:
		Game.research.done.append("zimmerei")
	var t6 := _roll(1)
	print("Belohnung angepasst ", _okf(t6.keys().any(func(k): return k.begins_with("bretter/pruefung") or k.begins_with("bretter/"))), " Prüfung braucht ein Holzhaus (Bretter 0): %s" % [t6])
	# 7 Hausstufe 2 (Holzhaus mit Bewohnern) braucht Möbel = Bretter
	var placed: bool = main._place_on(w, "holzhaus")
	w.assign_homes()
	var lv := QuestRewards._house_levels()
	var t7 := _roll(1)
	print("Belohnung angepasst ", _okf(placed and t7.keys().any(func(k): return k.begins_with("bretter/"))), " Holzhaus gebaut %s, Bewohner je Stufe %s, Bretter 0: %s (Gründe: %s)" % [placed, lv, t7,
		QuestRewards.needs(Quests.context()).filter(func(e): return e.id == "bretter").map(func(e): return e.why)])
	_rich(w, "bretter")
	# 8 Menge: Siedler, Zeitalter und freier Platz
	var c4 := {"A": 0, "P": 4, "R": 0.0}
	var c16 := {"A": 0, "P": 16, "R": 0.0}
	var c16a2 := {"A": 2, "P": 16, "R": 0.0}
	var m4 := QuestRewards.amount("werkzeug", 1, c4, -1)
	var m16 := QuestRewards.amount("werkzeug", 1, c16, -1)
	var m16a := QuestRewards.amount("werkzeug", 1, c16a2, -1)
	var short := QuestRewards.amount("werkzeug", 2, c16a2, 10)
	w.stock["stein"] = 0
	var free0 := QuestRewards.free_units("stein")
	var roomy := QuestRewards.amount("stein", 2, c16a2, -1)
	var fill: int = free0 - 20
	w.stock["stein"] = fill
	var tight := QuestRewards.amount("stein", 2, c16a2, -1)
	print("Belohnung angepasst ", _okf(m4 < m16 and m16 < m16a and short < m16a and short >= 15 and tight <= 12 and roomy > tight),
		" Werkzeug: 4 Siedler %d, 16 Siedler %d, 16 Siedler Zeitalter 2 %d, davon fehlen nur 10 %d | Stein: Platz für %d -> %d, Platz für 20 -> %d" % [m4, m16, m16a, short, free0, roomy, tight])
	_rich(w, "stein")
	# 9 Einwanderer nur mit freien Wohnplätzen und Essen
	var cap := 0
	var pop := 0
	for ww in Sea.all_worlds():
		cap += Game.housing_capacity(ww)
		pop += ww.settlers.size()
	var ok_now := QuestRewards.settlers_ok(1)
	_set_food(w, 0.5)
	var ok_hungry := QuestRewards.settlers_ok(1)
	_set_food(w, 12.0)
	var ok_many := QuestRewards.settlers_ok(cap - pop + 1)
	print("Belohnung angepasst ", _okf(ok_now == (cap - pop >= 1) and not ok_hungry and not ok_many), " Einwanderer: Wohnplätze %d, Siedler %d -> geht %s, hungrig %s, mehr als frei %s" % [cap, pop, ok_now, ok_hungry, ok_many])
	# 10 Angebote: 30 Runden, Einwanderer nie ohne Dach, Waren je Runde verschieden
	var seq0: int = Quests.seq
	var settlers_bad := 0
	var dup := 0
	var shown := []
	for i in 30:
		if not Quests.make_offers():
			continue
		var gs := []
		for q in Quests.offers:
			if str(q.reward.kind) == "settlers" and not QuestRewards.settlers_ok(int(q.reward.n)):
				settlers_bad += 1
			if str(q.reward.kind) == "goods":
				if str(q.reward.what) in gs:
					dup += 1
				gs.append(str(q.reward.what))
				if shown.size() < 4:
					shown.append(Quests.reward_text(q.reward))
	Quests.seq = seq0
	Quests.offers = []
	print("Belohnung angepasst ", _okf(settlers_bad == 0 and dup == 0), " 30 Angebotsrunden: Einwanderer ohne Dach %d, doppelte Waren %d, Beispiele %s" % [settlers_bad, dup, shown])
	# 11 Anzeige und Spielstand: Grund bleibt, unbekannter Grund fällt weg
	var r := {"kind": "goods", "what": "raeucherfisch", "n": 30.0, "why": "winter"}
	var s1 := Quests.sanitize_reward(JSON.parse_string(JSON.stringify(r)))
	var s2 := Quests.sanitize_reward({"kind": "goods", "what": "holz", "n": 5, "why": "gibtsnicht"})
	var s3 := Quests.sanitize_reward({"kind": "goods", "what": "holz", "n": 5})
	print("Belohnung angepasst ", _okf(str(s1.get("why", "")) == "winter" and not s2.has("why") and not s3.has("why")), " Spielstand: %s | unbekannt %s | alt %s | Anzeige: %s" % [s1, s2, s3, Quests.reward_text(s1)])
	w.stock = keep_stock
	Game.research.done = keep_done
	Seasons.jump_to_season(0)
	Game.refresh_effects()
