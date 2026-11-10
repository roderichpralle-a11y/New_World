class_name MerchantTest
extends RefCounted
## Selbsttests für "Inselstärken, Gewürze und fremde Händler" (kein Autoload; Merchant.autotest_setup
## ruft sie auf). Ausgaben nur mit print, Ergebnis je Prüfung "OK" oder "FEHLER".
##   --biometest=1   Tabelle der Inselstärken, Arbeitszeit je Inselart, Planung des Siedlers,
##                   Steinbruch je ein Tag Heimat/Fels/Heimat (nur Info, schwankt)
##   --spicetest=1   Generator (8 Sträucher, Rest unverändert), Kolonie auf einer Palmeninsel,
##                   alter Spielstand (Sträucher kommen wieder, nur einmal), Sammler-Reihenfolge, Ernte
##   --tradetest2=1  Händler sofort auf der aktiven Insel: Lose, Kauf, Verkauf, Gründe, Speichern/Laden,
##                   Seehandel, alter Spielstand, dann Abfahrt, Ankündigung und nächster Besuch
##   --basictrade=1  einfache Waren (Holz, Stein, ...): je Besuch 2 Verkaufs- und 2 Ankaufslose zusätzlich,
##                   seltene Lose bleiben, Zeitalter, Losgrößen, 40 Besuche Statistik, Kauf und Verkauf


static func _okf(c: bool) -> String:
	return "OK" if c else "FEHLER"


static func _wait(main, secs: float) -> void:
	await main.get_tree().create_timer(secs, true, false, true).timeout


# ---------------------------------------------------------------- Inselstärken
static func biome_test(main) -> void:
	var expect := {"mine": {"berg": 2.0}, "steinbruch": {"berg": 1.5}, "stahlwerk": {"berg": 1.5},
		"saegegrube": {"wald": 1.5}, "koehlerei": {"wald": 1.5}, "papiermuehle": {"wald": 1.5},
		"raeucherei": {"tropen": 1.5}, "konservenfabrik": {"tropen": 1.5}, "solarpark": {"tropen": 1.5}}
	var biomes := ["heimat", "tropen", "wald", "berg"]
	var table_ok := true
	for t in Data.buildings:
		for bio in biomes:
			var want := float(expect.get(t, {}).get(bio, 1.0))
			if absf(IslandTraits.factor(t, bio) - want) > 0.001:
				table_ok = false
				print("   Inselstärke falsch: ", t, " ", bio, " ", IslandTraits.factor(t, bio))
	print("Inselstärken ", _okf(table_ok), " Tabelle (nur Boni, Heimat ohne)")
	for bio in biomes:
		print("   Stärken ", bio, ": ", IslandTraits.strengths(bio))
	var w = Game.world
	Data.balance["base_storage"] = 4000
	if not w.buildings.any(func(x): return x.type == "steinbruch"):
		print("   Steinbruch hingestellt: ", main._place_on(w, "steinbruch"))
	var b = null
	for x in w.buildings:
		if x.type == "steinbruch":
			b = x
	var s = w.settlers[1] if w.settlers.size() > 1 else w.settlers[0]
	s.set_job("steinmetz")
	var keep: String = w.biome
	var times := {}
	for bio in ["heimat", "berg", "wald"]:
		w.biome = bio
		var p: Dictionary = b.prod_def()
		var t: float = float(p.time) / (s.work_factor(str(p.get("skill", "stein")), "production") * b.biome_factor())
		times[bio] = t
		print("   Steinbruch auf %s: ein Arbeitsgang %.2f s (Faktor %.1f)" % [bio, t, b.biome_factor()])
	var t_ok: bool = absf(times.heimat / times.berg - 1.5) < 0.01 and absf(times.heimat - times.wald) < 0.001
	print("Inselstärken ", _okf(t_ok), " Arbeitszeit Felseninsel = Heimat / 1,5, Waldinsel unverändert")
	# Echter Planungsweg: Settler._plan_production legt den Arbeitsgang mit dem Faktor an
	var planned := {}
	for bio in ["heimat", "berg"]:
		w.biome = bio
		s._plan.clear()
		s._release()
		var found: bool = s._plan_production("stein")
		var t_work := 0.0
		for e in s._plan:
			if e.get("a", "") == "work" and e.has("tool"):
				t_work = float(e.t)
		planned[bio] = t_work
		s._plan.clear()
		s._release()
		print("   Siedler plant auf %s: gefunden %s, Arbeitsgang %.2f s" % [bio, found, t_work])
	var plan_ok: bool = float(planned.berg) > 0.0 and absf(float(planned.heimat) / float(planned.berg) - 1.5) < 0.01
	print("Inselstärken ", _okf(plan_ok), " Siedler plant den Arbeitsgang auf der Felseninsel x1,5 so schnell")
	# Echter Lauf (nur zur Info, schwankt stark): je ein Tag Heimat, Felseninsel, Heimat; Stein im Lager
	var counts := []
	for bio in ["heimat", "berg", "heimat"]:
		w.biome = bio
		var t0 := Game.time_days
		var s0 := Game.amount("stein", w)
		while Game.time_days < t0 + 1.0:
			await _wait(main, 0.5)
		var got := Game.amount("stein", w) - s0
		counts.append(got)
		print("   Steinbruch ein Tag auf %s: %d Stein" % [bio, got])
	w.biome = keep
	var base := (float(counts[0]) + float(counts[2])) / 2.0
	print("Inselstärken Info: Felseninsel brachte x%.2f so viel Stein ins Lager (nur der Arbeitsgang ist x1,5 so schnell; Wege, Pausen und die anderen Siedler schwanken)" % (float(counts[1]) / maxf(1.0, base)))


# ---------------------------------------------------------------- Gewürze
static func spice_test(main) -> void:
	var bd: Dictionary = Data.islands["tropen"].duplicate()
	bd["_dens"] = [["eberbau", 1]]
	var bd0 := bd.duplicate()
	bd0.erase("extra")
	var g1 := IslandGen.generate(4242, 48, {"biome": bd})
	var g0 := IslandGen.generate(4242, 48, {"biome": bd0})
	var sp: Array = g1.nodes.filter(func(n): return n.type == "gewuerzstrauch")
	var rest: Array = g1.nodes.filter(func(n): return n.type != "gewuerzstrauch")
	var same: bool = rest.size() == g0.nodes.size()
	for i in mini(rest.size(), g0.nodes.size()):
		if rest[i].type != g0.nodes[i].type or rest[i].cell != g0.nodes[i].cell:
			same = false
	var grass := sp.filter(func(n): return g1.terrain[n.cell.y * 48 + n.cell.x] == 2).size()
	print("Gewürze ", _okf(sp.size() == 8), " Generator: %d Sträucher (%d auf Gras) | " % [sp.size(), grass], _okf(same), " alle anderen Rohstoffe und Baue gleich")
	var counts := []
	for k in range(1, 21):
		counts.append(IslandGen.generate(k * 7919, 44 + k % 9, {"biome": bd}).nodes.filter(func(n): return n.type == "gewuerzstrauch").size())
	var others := 0
	for bio in ["heimat", "wald", "berg"]:
		var o: Dictionary = Data.islands[bio].duplicate()
		o["_dens"] = []
		others += IslandGen.generate(4242, 48, {"biome": o}).nodes.filter(func(n): return n.type == "gewuerzstrauch").size()
	print("Gewürze ", _okf(counts.min() >= 7 and others == 0), " je Palmeninsel (20 Seeds): ", counts, " | andere Inselarten: ", others)
	# Kolonie auf einer Palmeninsel
	var m: Dictionary = Sea.make_island(Sea.islands.size())
	m.biome = "tropen"
	m.dens = [["eberbau", 1]]
	Sea.islands.append(m)
	var w = Sea.create_world_node(int(m.id))
	w.build_colony(m)
	m.state = "settled"
	Sea.islands_changed.emit()
	var bushes: int = w.nodes.filter(func(n): return n.type == "gewuerzstrauch").size()
	print("Gewürze ", _okf(bushes == 8), " Kolonie %s: %d Sträucher" % [m.name, bushes])
	var came: Array = Game.spawn_immigrants(w, 4, {"convert": false})
	for i in mini(2, came.size()):
		came[i].set_job("sammler")
	w.stock = {}
	var targets: Array = Data.jobs.sammler.targets
	var hungry := IslandTraits.gather_order(targets, w)
	Game.add_stock("kokos", 60, w)
	var fed := IslandTraits.gather_order(targets, w)
	print("Gewürze ", _okf(not "gewuerzstrauch" in hungry and fed[0] == "gewuerzstrauch"), " Sammler ohne Essen: ", hungry, " | mit 60 Kokos für 4 Siedler: ", fed)
	# Alter Spielstand: Sträucher fehlen und kommen beim Laden wieder (nur einmal)
	for n in w.nodes.duplicate():
		if n.type == "gewuerzstrauch":
			w.remove_node(n)
	var gen := IslandGen.generate(int(m.seed), int(m.size), w._gen_opts(m))
	var again1 := IslandTraits.patch_spice(w, gen)
	var again2 := IslandTraits.patch_spice(w, gen)
	print("Gewürze ", _okf(again1 >= 6 and again2 == 0), " alter Spielstand: %d nachgesetzt, beim zweiten Laden %d" % [again1, again2])
	var t0 := Game.time_days
	while Game.time_days < t0 + 2.0:
		await _wait(main, 1.0)
	var acts: Array = w.settlers.map(func(x): return "%s:%s:%s" % [x.display_name, x.job, x.activity])
	print("Gewürze ", _okf(Game.amount("gewuerze", w) > 0), " nach 2 Tagen auf %s: %d Gewürze, Essen %d | %s" % [m.name, Game.amount("gewuerze", w), Game.total_food(w), acts])


# ---------------------------------------------------------------- Händler
static func trade_test(main, mode: String) -> void:
	var M = Merchant
	var w = Game.world
	Data.balance["base_storage"] = 4000
	if Sea.harbor_level(w) < 1:
		print("Handel: Werft hingestellt ", main._place_on(w, "werft"))
		Game.refresh_effects()
	for id in ["holz", "stein", "bretter", "fisch", "kokos", "brot", "werkzeug", "felle", "ziegel", "kohle", "raeucherfisch"]:
		w.stock[id] = maxi(Game.amount(id, w), 60)
	w.stock["gold"] = 40
	M.enabled = true
	M.arrive(w)
	print("Handel: %s in %s bis Tag %.2f" % [M.merchant_name(), Sea.island_name(w), float(M.state.until) + 1.0])
	print("   verkauft: ", M._lots_text(M.state.sells))
	print("   kauft:    ", M._lots_text(M.state.buys))
	if mode == "shot":  # nur Händler hinlegen (Bildschirmfotos), keine Prüfungen
		return
	# 1 Lose im Rahmen
	var lots_ok: bool = M.state.sells.size() == 6 and M.state.buys.size() == 5  # 4 + 2 und 3 + 2 einfache
	for l in M.state.sells:
		var v := int(l.n) * float(Data.resources[l.id].price)
		lots_ok = lots_ok and int(l.gold) >= ceili(v - 0.001) and int(l.gold) <= ceili(v * 1.25 + 0.001) and int(l.left) >= 1 and int(l.left) <= 3
	for l in M.state.buys:
		var v := int(l.n) * float(Data.resources[l.id].price)
		lots_ok = lots_ok and int(l.gold) >= maxi(1, floori(v * 0.5 - 0.001)) and int(l.gold) <= maxi(1, floori(v * 0.65 + 0.001))
	print("Handel ", _okf(lots_ok), " 4+2 Verkaufs- und 3+2 Ankaufslose (seltene + einfache), Preise x1,0-1,25 bzw. x0,5-0,65, je 1-3-mal")
	# 2 gleiche Lose für gleichen Seed und Besuch
	var keep: Dictionary = M.state.duplicate(true)
	M.make_lots(w)
	var same: bool = str(M.state.sells) == str(keep.sells) and str(M.state.buys) == str(keep.buys)
	M.state = keep
	print("Handel ", _okf(same), " gleiche Lose bei gleichem Seed und Besuch")
	# 3 Kauf (billigstes Los)
	var bi := 0
	for i in M.state.sells.size():
		if int(M.state.sells[i].gold) < int(M.state.sells[bi].gold):
			bi = i
	var lot: Dictionary = M.state.sells[bi]
	var g0 := Game.amount("gold", w)
	var a0 := Game.amount(str(lot.id), w)
	var l0 := int(lot.left)
	var err: String = M.buy(bi)
	var g1 := Game.amount("gold", w)
	var a1 := Game.amount(str(lot.id), w)
	var buy_ok: bool = err == "" and g1 == g0 - int(lot.gold) and a1 == a0 + int(lot.n) and int(lot.left) == l0 - 1
	print("Handel ", _okf(buy_ok), " Kauf: %d %s für %d Gold | Gold %d -> %d, %s %d -> %d, noch %dx" % [int(lot.n), str(lot.id), int(lot.gold), g0, g1, str(lot.id), a0, a1, int(lot.left)])
	# 4 Verkauf (erstes Los)
	var bl: Dictionary = M.state.buys[0]
	if Game.amount(str(bl.id), w) < int(bl.n):
		Game.add_stock(str(bl.id), int(bl.n), w)
	g0 = Game.amount("gold", w)
	a0 = Game.amount(str(bl.id), w)
	err = M.sell(0)
	g1 = Game.amount("gold", w)
	a1 = Game.amount(str(bl.id), w)
	var sell_ok: bool = err == "" and g1 == g0 + int(bl.gold) and a1 == a0 - int(bl.n)
	print("Handel ", _okf(sell_ok), " Verkauf: %d %s für %d Gold | Gold %d -> %d, %s %d -> %d" % [int(bl.n), str(bl.id), int(bl.gold), g0, g1, str(bl.id), a0, a1])
	# 5 Gründe
	var gk := Game.amount("gold", w)
	w.stock["gold"] = 0
	var why1: String = M.buy_block(bi) if int(lot.left) > 0 else M.buy_block((bi + 1) % M.state.sells.size())
	w.stock["gold"] = gk
	var b2: Dictionary = M.state.buys[1]
	var ak := Game.amount(str(b2.id), w)
	w.stock[str(b2.id)] = 0
	var why2: String = M.sell_block(1)
	w.stock[str(b2.id)] = ak
	var lk := int(M.state.sells[0].left)
	M.state.sells[0].left = 0
	var why3: String = M.buy_block(0)
	M.state.sells[0].left = lk
	var why_ok: bool = why1 == Loc.t("zu wenig Gold") and why2 == Loc.t("nur %d im Lager") % 0 and why3 == Loc.t("ausverkauft")
	print("Handel ", _okf(why_ok), " Gründe: '%s' | '%s' | '%s'" % [why1, why2, why3])
	# 6 Schiff im Hafen
	print("Handel ", _okf(w._ship_nodes.has(-1)), " Schiff des Händlers liegt vor dem Hafen (Schiffe im Bild: %d)" % w._ship_nodes.size())
	# 7 Speichern und Laden
	var d := {}
	M._on_save(d)
	var back = JSON.parse_string(JSON.stringify(d))
	var before: Dictionary = M.state.duplicate(true)
	M._on_load(back, 1)
	var load_ok: bool = str(M.state.sells) == str(before.sells) and str(M.state.buys) == str(before.buys) \
		and int(M.state.island) == int(before.island) and int(M.state.seq) == int(before.seq) \
		and absf(float(M.state.until) - float(before.until)) < 0.001 and M.present()
	print("Handel ", _okf(load_ok), " Speichern und Laden: Lose, Insel, Abfahrt gleich")
	# 8 Seehandel: ein Los mehr, Abstand x0,7
	var eff_keep: Dictionary = Game.effects.duplicate()
	var keep2: Dictionary = M.state.duplicate(true)
	var iv_n: float = M.next_interval(7)
	Game.effects["trade"] = 1.0
	M.make_lots(w)
	var n_sells: int = M.state.sells.size()
	var iv_t: float = M.next_interval(7)
	Game.effects = eff_keep
	M.state = keep2
	print("Handel ", _okf(n_sells == 7 and absf(iv_t / iv_n - 0.7) < 0.001), " Seehandel: %d Verkaufslose, Abstand %.2f statt %.2f Tage" % [n_sells, iv_t, iv_n])
	# 9 alter Spielstand: erster Besuch rules_day + 2, Regelzeile
	var keep3: Dictionary = M.state.duplicate(true)
	var lines_keep: Array = Game.rules_lines.duplicate()
	M._on_load({}, 0)
	var old_ok: bool = absf(float(M.state.next) - (Game.rules_day + 2.0)) < 0.001 and int(M.state.island) == -1 \
		and Game.rules_lines.size() == lines_keep.size() + 1 \
		and Game.rules_lines[-1] == Loc.t("Jede Inselart hat Stärken. Palmeninseln haben Gewürze. Händler kommen an Häfen und handeln gegen Gold.")
	print("Handel ", _okf(old_ok), " alter Spielstand: erster Besuch Tag %.2f (Regeln ab Tag %.2f), Regelzeile '%s'" % [float(M.state.next) + 1.0, Game.rules_day + 1.0, Game.rules_lines[-1] if not Game.rules_lines.is_empty() else ""])
	Game.rules_lines = lines_keep
	M.state = keep3
	w.sync_ships()
	print("Handel: Ereignisse (Events.busy) ", "vorhanden" if main.get_node_or_null("/root/Events") != null else "noch nicht eingebaut, Sperre wird übersprungen")
	# 10 Ablauf: Abfahrt, nächster Besuch in 4-6 Tagen, Ankündigung einen Tag vorher, Ankunft
	var t_arr := Game.time_days
	while M.present():
		await _wait(main, 0.25)
	var t_leave := Game.time_days
	var gap: float = float(M.state.next) - t_leave
	var leave_ok: bool = absf(t_leave - t_arr - 1.0) < 0.05 and gap >= 3.99 and gap <= 6.01 and not w._ship_nodes.has(-1)
	print("Handel ", _okf(leave_ok), " Abfahrt nach %.2f Tagen, nächster Besuch in %.2f Tagen, Schiff weg" % [t_leave - t_arr, gap])
	while M.planned_world() == null and not M.present():
		await _wait(main, 0.25)
	var lead: float = float(M.state.next) - Game.time_days
	print("Handel ", _okf(lead > 0.9 and lead <= 1.01), " angekündigt %.2f Tage vorher für %s" % [lead, Sea.island_name(M.planned_world())])
	while not M.present():
		await _wait(main, 0.25)
	print("Handel ", _okf(int(M.state.seq) == 1 and M.state.sells.size() == 6), " Besuch 2 in %s: verkauft %s | kauft %s" % [Sea.island_name(M.world()), M._lots_text(M.state.sells), M._lots_text(M.state.buys)])


# ---------------------------------------------------------------- Einfache Waren
static func basic_test(main) -> void:
	var M = Merchant
	var w = Game.world
	Data.balance["base_storage"] = 4000
	if Sea.harbor_level(w) < 1:
		print("Einfache Waren: Werft hingestellt ", main._place_on(w, "werft"))
		Game.refresh_effects()
	w.stock["gold"] = 60
	for id in ["holz", "stein", "lehm", "weizen", "bretter", "ziegel"]:
		w.stock[id] = maxi(Game.amount(id, w), 80)
	M.enabled = true
	M.arrive(w)
	var basic: Dictionary = M.cfg.get("basic", {})
	var nb_s := int(M.cfg.get("basic_sell_lots", 2))
	var nb_b := int(M.cfg.get("basic_buy_lots", 2))
	print("Einfache Waren: Zeitalter %d, verkauft %s | kauft %s" % [Game.current_age(), M._lots_text(M.state.sells), M._lots_text(M.state.buys)])
	# 1 je Besuch: einfache Lose zusätzlich, seltene bleiben vollständig
	var bs: Array = M.state.sells.filter(func(l): return M.is_basic(str(l.id)))
	var bb: Array = M.state.buys.filter(func(l): return M.is_basic(str(l.id)))
	var rs: int = M.state.sells.size() - bs.size()
	var rb: int = M.state.buys.size() - bb.size()
	var ids_s: Array = M.state.sells.map(func(l): return str(l.id))
	var ids_b: Array = M.state.buys.map(func(l): return str(l.id))
	var both: Array = ids_s.filter(func(x): return x in ids_b)
	print("Einfache Waren ", _okf(bs.size() == nb_s and bb.size() == nb_b and rs == int(M.cfg.sell_lots) and rb == int(M.cfg.buy_lots) and both.is_empty()), " %d einfache + %d seltene Verkaufslose, %d einfache + %d andere Ankaufslose, doppelt: %s" % [bs.size(), rs, bb.size(), rb, both])
	# 2 Losgrößen: Fünferschritte, Wert im Rahmen basic_lot_gold
	var lg: Array = M.cfg.get("basic_lot_gold", [3, 6])
	var size_ok := true
	for l in bs + bb:
		var v := int(l.n) * float(Data.resources[str(l.id)].price)
		size_ok = size_ok and int(l.n) % 5 == 0 and v >= float(lg[0]) * 0.5 - 0.01 and v <= float(lg[1]) * 1.5 + 0.01
	print("Einfache Waren ", _okf(size_ok), " Losgrößen in Fünferschritten für etwa %d-%d Gold: %s" % [int(lg[0]), int(lg[1]), M._lots_text(bs + bb)])
	# 3 Statistik über 40 Besuche: jede einfache Ware kommt vor, seltene Lose immer 4, Kohle erst ab Antike
	var keep: Dictionary = M.state.duplicate(true)
	var seen := {}
	var rare_min := 99
	var kohle_early := 0
	for k in 40:
		M.state.seq = 100 + k
		M.make_lots(w)
		var r: int = M.state.sells.filter(func(l): return not M.is_basic(str(l.id))).size()
		rare_min = mini(rare_min, r)
		for l in M.state.sells + M.state.buys:
			if M.is_basic(str(l.id)):
				seen[str(l.id)] = int(seen.get(str(l.id), 0)) + 1
				if str(l.id) == "kohle" and Game.current_age() < int(basic.kohle):
					kohle_early += 1
	var all_seen := true
	for id in basic:
		if int(basic[id]) <= Game.current_age() and not seen.has(id):
			all_seen = false
	print("Einfache Waren ", _okf(all_seen and rare_min == int(M.cfg.sell_lots) and kohle_early == 0), " 40 Besuche: einfache Waren %s, seltene Verkaufslose je Besuch mindestens %d, Kohle vor ihrem Zeitalter %d" % [seen, rare_min, kohle_early])
	var eff_keep: Dictionary = Game.effects.duplicate()
	var age_keep: int = Exams.passed
	Exams.passed = 2
	M.state.seq = 7
	M.make_lots(w)
	var later: Array = (M.state.sells + M.state.buys).filter(func(l): return M.is_basic(str(l.id))).map(func(l): return str(l.id))
	Exams.passed = age_keep
	Game.effects = eff_keep
	M.state = keep
	print("Einfache Waren Info: im Mittelalter (Besuch 8): %s" % [later])
	# 4 Kauf und Verkauf eines einfachen Loses
	var si: int = M.state.sells.find(bs[0])
	var g0 := Game.amount("gold", w)
	var a0 := Game.amount(str(bs[0].id), w)
	var e1: String = M.buy(si)
	var buy_ok: bool = e1 == "" and Game.amount("gold", w) == g0 - int(bs[0].gold) and Game.amount(str(bs[0].id), w) == a0 + int(bs[0].n)
	print("Einfache Waren ", _okf(buy_ok), " Kauf: %d %s für %d Gold | Gold %d -> %d" % [int(bs[0].n), str(bs[0].id), int(bs[0].gold), g0, Game.amount("gold", w)])
	var bi: int = M.state.buys.find(bb[0])
	if Game.amount(str(bb[0].id), w) < int(bb[0].n):
		Game.add_stock(str(bb[0].id), int(bb[0].n), w)
	g0 = Game.amount("gold", w)
	a0 = Game.amount(str(bb[0].id), w)
	var e2: String = M.sell(bi)
	var sell_ok: bool = e2 == "" and Game.amount("gold", w) == g0 + int(bb[0].gold) and Game.amount(str(bb[0].id), w) == a0 - int(bb[0].n)
	print("Einfache Waren ", _okf(sell_ok), " Verkauf: %d %s für %d Gold | Gold %d -> %d" % [int(bb[0].n), str(bb[0].id), int(bb[0].gold), g0, Game.amount("gold", w)])
	# 5 Speichern und Laden behält die einfachen Lose
	var d := {}
	M._on_save(d)
	var before: String = str(M.state.sells) + str(M.state.buys)
	M._on_load(JSON.parse_string(JSON.stringify(d)), 1)
	print("Einfache Waren ", _okf(str(M.state.sells) + str(M.state.buys) == before), " Speichern und Laden: Lose gleich")
