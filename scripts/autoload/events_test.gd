class_name EventsTest
extends RefCounted
## Selbsttests für "Angekündigte Ereignisse" (kein Autoload; Events.autotest_setup ruft sie auf).
## Ausgaben nur mit print, Ergebnis je Prüfung "OK" oder "FEHLER".
##   --eventtest=<duerre|ratten|brand|seuche|sturmflut|piraten|all>  Ereignis sofort (Vorwarnung 0,05 Tag),
##                   prüft Wirkung, Gegenmittel, Belohnung, Speichern/Laden und (all) den alten Spielstand
##   --eventsched=1  Zeitplan: 6 Jahre im Schnelldurchlauf auf einer vollen Insel (Abstände, Jahreszeiten)
##   --eventshot=<art>[:now]  nur ankündigen bzw. eintreten lassen (Bildschirmfoto), dazu --eventtap=1
##                   (Knopf kurz vor dem Foto antippen) und --selectraider=1 (Piraten-Infofenster)

const TYPES := ["duerre", "ratten", "brand", "seuche", "sturmflut", "piraten"]


static func _okf(c: bool) -> String:
	return "OK" if c else "FEHLER"


static func _wait(main, secs: float) -> void:
	await main.get_tree().create_timer(secs, true, false, true).timeout


## Wartet Bild für Bild, bis cond() gilt oder max_days Spieltage vergangen sind.
static func _until(main, cond: Callable, max_days: float) -> bool:
	var t0 := Game.time_days
	while not cond.call():
		if Game.time_days > t0 + max_days or Game.is_over:
			return false
		await main.get_tree().process_frame
	return true


static func _gone(w) -> bool:
	return Events.event_of(w).is_empty()


static func _struck(w) -> bool:
	return bool(Events.event_of(w).get("struck", false))


## Gemeinsame Vorbereitung: Forschungen bis Stufe tier, viel Platz, 12 Siedler, Einführung fertig.
static func _prepare(main, tier: int) -> void:
	var w = Game.world
	for t in Data.techs:
		if int(Data.techs[t].tier) <= tier and not Data.techs[t].get("soon", false) and not t in Game.research.done \
				and not t in ["bewaesserung", "heilkunde", "deichbau"]:
			Game.research.done.append(t)
	Game._recompute_effects()
	Game.research_changed.emit()
	Data.balance["base_storage"] = 4000
	Game.goals.tut = Data.goals.get("tutorial", []).size()
	while w.settlers.size() < 12:
		if w.spawn_newcomer("f" if w.settlers.size() % 2 else "m") == null:
			break
	for id in ["holz", "bretter", "stein", "ziegel", "lehm", "eisen", "werkzeug"]:
		w.stock[id] = maxi(Game.amount(id, w), 120)
	for id in ["brot", "raeucherfisch", "beeren"]:
		w.stock[id] = maxi(Game.amount(id, w), 60)
	Game.stock_changed.emit()


static func _set_tech(t: String, on: bool) -> void:
	if on and not t in Game.research.done:
		Game.research.done.append(t)
	elif not on:
		Game.research.done.erase(t)
	Game._recompute_effects()
	Events._refresh_caches()


## Fertiges Gebäude in höchstens maxr Feldern um c (mit Rand frei); liefert es oder null.
static func _place_near(w, type: String, c: Vector2i, maxr: int, minr: int = 1):
	for r in range(minr, maxr + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cc := c + Vector2i(dx, dy)
				if w.can_place(type, cc) and _roomy(w, type, cc):
					return w.place_building(type, cc, true)
	return null


static func _roomy(w, type: String, cc: Vector2i) -> bool:
	var sz: Array = Data.buildings[type].size
	for y in range(-1, int(sz[1]) + 2):
		for x in range(-1, int(sz[0]) + 1):
			var p := cc + Vector2i(x, y)
			if w.building_at.has(p) or not w.is_walkable(p):
				return false
	return true


## Fertiges Gebäude nahe am Wasser (höchstens 2 Felder, wie die Sturmflut prüft).
static func _place_coast(w, type: String):
	var st = w.nearest_storage(w.center)
	var origin: Vector2i = st.cell if st != null else w.center
	var cands := []
	for y in w.size:
		for x in w.size:
			var c := Vector2i(x, y)
			if w.can_place(type, c) and _roomy(w, type, c):
				cands.append([Vector2(c - origin).length(), c])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var sz := Vector2i(int(Data.buildings[type].size[0]), int(Data.buildings[type].size[1]))
	for e in cands:
		if Events.near_water(w, e[1], sz, 2):
			return w.place_building(type, e[1], true)
	return null


static func run(main, which: String) -> void:
	var list: Array = TYPES if which == "all" else [which]
	Events.enabled = true
	await _wait(main, 0.5)
	_prepare(main, 6 if "piraten" in list else 4)
	_weights_check()
	for t in list:
		match t:
			"duerre":
				await _test_duerre(main)
			"ratten":
				await _test_ratten(main)
			"brand":
				await _test_brand(main)
			"seuche":
				await _test_seuche(main)
			"sturmflut":
				await _test_flood(main)
			"piraten":
				await _test_pirates(main)
			_:
				print("Ereignis-Test: unbekannte Art ", t)
	if which == "all":
		_old_save_check()
	print("Ereignis-Statistik: überstanden %d von %d, Piraten vertrieben %d, Jagdbeute (kills) %d" % [int(Game.stats.get("events_survived", 0)),
		int(Game.stats.get("events", 0)), int(Game.stats.get("pirates", 0)), int(Game.stats.get("kills", 0))])


## Gewichte: Jahreszeit beim Eintritt, heißer Sommer, keine Seuche im harten Winter.
static func _weights_check() -> void:
	var y := Seasons.year()
	var key := str(y)
	var keep = Seasons.climate.get(key, {"w": "normal", "s": "normal"}).duplicate()
	var t0 := floorf(Game.time_days / Seasons.year_days()) * Seasons.year_days()
	var at := [t0 + 0.4, t0 + 3.4, t0 + 6.4, t0 + 9.4]
	Seasons.climate[key] = {"w": "normal", "s": "normal"}
	var rows := []
	for t in TYPES:
		rows.append("%s %s" % [t, at.map(func(x): return Events.weight(t, x))])
	var d_norm := Events.weight("duerre", at[1])
	var b_norm := Events.weight("brand", at[1])
	Seasons.climate[key] = {"w": "hart", "s": "heiss"}
	var d_hot := Events.weight("duerre", at[1])
	var b_hot := Events.weight("brand", at[1])
	var s_hard := Events.weight("seuche", at[3])
	Seasons.climate[key] = keep
	print("Ereignis-Gewichte (Frühling, Sommer, Herbst, Winter): ", ", ".join(rows))
	var ok := d_hot == d_norm * 2.0 and b_hot == b_norm * 2.0 and s_hard == 0.0 and Events.weight("duerre", at[0]) == 0.0 \
		and Events.weight("piraten", at[3]) == 0.0 and Events.weight("sturmflut", at[1]) == 0.0
	print("Ereignis-Test Gewichte ", _okf(ok), " heißer Sommer Dürre %.1f -> %.1f, Brand %.1f -> %.1f, Seuche im harten Winter %.1f" % [d_norm, d_hot, b_norm, b_hot, s_hard])


static func _force_wait(main, w, typ: String) -> Dictionary:
	var ev: Dictionary = Events.force(w, typ, 0.05)
	print("   angekündigt: ", typ, " Eintritt Tag %.2f, Stärke %.2f, busy=%s" % [float(ev.strike) + 1.0, float(ev.power), Events.busy(w)])
	await _until(main, func(): return bool(ev.get("struck", false)), 0.6)
	return ev


# ---------------------------------------------------------------- Dürre
static func _test_duerre(main) -> void:
	print("--- Ereignis-Test Dürre")
	var w = Game.world
	Seasons.jump_to_season(Seasons.SUMMER)
	var fields := []
	for i in 2:
		var f = _place_near(w, "feld", w.center + Vector2i(-7, 2 + i * 3), 12)
		if f != null:
			fields.append(f)
	print("   Felder: ", fields.size(), " geeignet=", Events.eligible(w, "duerre"))
	var base := float(Seasons.cfg.growth.feld[Seasons.SUMMER])
	var cf := float(Seasons._s_tab.get("growth", {}).get("feld", 1.0))  # Klima (heißer Sommer 0,8)
	var g0 := Seasons.growth("feld", w)
	var tree0 := Seasons.growth("baum", w)
	var ev := await _force_wait(main, w, "duerre")
	var g1 := Seasons.growth("feld", w)
	var b1 := Seasons.growth("busch", w)
	var ok := absf(g1 - base * minf(cf, 0.4)) < 0.001 and absf(Seasons.growth("baum", w) - tree0) < 0.001 and absf(Seasons.growth("feld", null) - g0) < 0.001
	print("Ereignis-Test Dürre ", _okf(ok), " Feld im Sommer %.3f -> %.3f (erwartet %.3f), Beeren %.3f, Bäume unverändert %.3f, andere Insel %.3f; Ende Tag %.2f (Sommerende)" % [g0, g1, base * 0.4,
		b1, Seasons.growth("baum", w), Seasons.growth("feld", null), float(ev.end) + 1.0])
	# Heißer Sommer: min statt mal (0,8 und 0,4 -> 0,4)
	var key := str(Seasons.year())
	var keep = Seasons.climate.get(key, {}).duplicate()
	Seasons.force_s = "heiss"
	Seasons._cy = -1
	Seasons._ensure_year()
	var g_hot := Seasons.growth("feld", w)
	Seasons.force_s = ""
	Seasons.climate[key] = keep
	Seasons._cy = -1
	Seasons._ensure_year()
	print("Ereignis-Test Dürre ", _okf(absf(g_hot - base * 0.4) < 0.001), " im heißen Sommer %.3f (Kleineres aus Hitze 0,8 und Dürre 0,4, nicht das Produkt %.3f)" % [g_hot, base * 0.32])
	_set_tech("bewaesserung", true)
	var g2 := Seasons.growth("feld", w)
	_set_tech("bewaesserung", false)
	print("Ereignis-Test Dürre ", _okf(absf(g2 - base * minf(cf, 0.7)) < 0.001), " mit Bewässerung %.3f (x0,7, Klima %.2f)" % [g2, cf])
	# Ein wachsendes Feld reift wirklich langsamer: farm_time rückt um dt*(1-Faktor) nach
	var f = fields[0] if not fields.is_empty() else null
	if f != null:
		f.farm_state = "growing"
		f.farm_time = Game.time_days
		var ft0: float = f.farm_time
		var t0 := Game.time_days
		await _until(main, func(): return Game.time_days >= t0 + 0.2, 0.3)
		var share: float = (f.farm_time - ft0) / maxf(0.0001, Game.time_days - t0)
		print("Ereignis-Test Dürre ", _okf(absf(share - (1.0 - g1)) < 0.05), " Feld reift langsamer: verschoben um %.2f je Tag (erwartet %.2f)" % [share, 1.0 - g1])
	# Ende ohne Tote: ein Einwanderer, wenn Wohnplatz frei ist
	for i in 8:
		if Game.housing_capacity(w) > w.settlers.size():
			break
		_place_near(w, "huette", w.center + Vector2i(5, -5), 16)
	var n0: int = w.settlers.size()
	var surv0 := int(Game.stats.get("events_survived", 0))
	Events.last_reward = ""
	ev.end = Game.time_days + 0.05
	await _until(main, func(): return _gone(w), 0.5)
	var free := Game.housing_capacity(w) - n0
	print("Ereignis-Test Dürre ", _okf(_gone(w) and free > 0 and Events.last_reward == "settler" and w.settlers.size() >= n0 + 1 and int(Game.stats.get("events_survived", 0)) == surv0 + 1), " vorbei, Wohnplätze frei %d, Belohnung %s, Siedler %d -> %d (dazu evtl. Geburten), überstanden %d, Wachstum wieder %.3f" % [free, Events.last_reward, n0, w.settlers.size(), int(Game.stats.get("events_survived", 0)), Seasons.growth("feld", w)])


# ---------------------------------------------------------------- Ratten
static func _test_ratten(main) -> void:
	print("--- Ereignis-Test Ratten")
	var w = Game.world
	for round_i in 2:
		for id in ["weizen", "beeren", "fisch", "brot"]:
			w.stock[id] = 100
		w.stock["konserven"] = 30
		print("   geeignet=", Events.eligible(w, "ratten"), " Rattenwaren ", Events._rat_goods(w))
		var ev := await _force_wait(main, w, "ratten")
		await _until(main, func(): return _gone(w), 0.2)
		var sh: Array = Events.type_def("ratten").share
		var share := clampf(float(sh[0]) + float(sh[1]) * float(ev.power), float(sh[2]), float(sh[3])) * (0.5 if round_i == 1 else 1.0)
		var by: Dictionary = ev.get("lost_by", {})
		var ok: bool = absf(float(ev.get("share", 0.0)) - share) < 0.001 and Game.amount("konserven", w) == 30 and _gone(w) and by.size() >= 4
		for id in by:
			if int(by[id][1]) != roundi(int(by[id][0]) * share):
				ok = false
		print("Ereignis-Test Ratten ", _okf(ok), " %s: Anteil %.3f (erwartet %.3f), gefressen [vorher, weg] %s, Konserven 30 -> %d" % ["mit Großem Lager" if round_i == 1 else "ohne Großes Lager", float(ev.get("share", 0.0)), share, by, Game.amount("konserven", w)])
		if round_i == 0:
			print("   Großes Lager: ", _place_near(w, "grosslager", w.center, 16, 4) != null)


# ---------------------------------------------------------------- Brand
static func _test_brand(main) -> void:
	print("--- Ereignis-Test Brand")
	var w = Game.world
	for t in ["huette", "huette", "saegegrube", "raeucherei"]:
		_place_near(w, t, w.center + Vector2i(8, 6), 14)
	var cands: Array = Events._damage_candidates(w)
	print("   Kandidaten: ", cands.map(func(b): return b.type), " geeignet=", Events.eligible(w, "brand"), " (Lager, Häfen, Lagerfeuer und Felder nie dabei: ", not cands.any(func(b): return b.is_storage() or b.type == "lagerfeuer" or b.is_ground()), ")")
	var before := {}
	for b in w.buildings:
		before[b.id] = b.complete
	var homes_before := {}
	for s in w.settlers:
		homes_before[s.id] = s.home_id
	var ev := await _force_wait(main, w, "brand")
	await _until(main, func(): return _gone(w), 0.2)
	var hit: Array = w.buildings.filter(func(b): return before.get(b.id, false) and not b.complete)
	var basic: Array = Events._c("basic_goods", [])
	var mat_ok := true
	for b in hit:
		for res in b.def.cost:
			var want: int = ceili(int(b.def.cost[res]) * 0.7) if res in basic else int(b.def.cost[res])
			if int(b.delivered.get(res, 0)) != want:
				mat_ok = false
		if b.progress != 0.0 or not b.occupants.is_empty() or w.settlers.any(func(s): return s.home_id == b.id):
			mat_ok = false
	print("Ereignis-Test Brand ", _okf(hit.size() == int(ev.get("burnt", -1)) and hit.size() == Events._hits(float(ev.power)) and mat_ok), " abgebrannt %s (%d, erwartet %d bei Stärke %.2f), Baustoffe: einfache 70 %%, andere ganz, Bauarbeit neu, Bewohner ausgezogen" % [
		hit.map(func(b): return "%s %s" % [b.type, b.delivered]), hit.size(), Events._hits(float(ev.power)), float(ev.power)])
	# Baumeister bauen es mit der normalen Baustellen-Logik wieder auf
	w.settlers[1].set_job("baumeister")
	w.settlers[2].set_job("baumeister")
	var t0 := Game.time_days
	var rebuilt := await _until(main, func(): return hit.all(func(b): return is_instance_valid(b) and b.complete), 2.0)
	print("Ereignis-Test Brand ", _okf(rebuilt), " wieder aufgebaut nach %.2f Tagen (gleiche Gebäude-ID, Bewohner ziehen wieder ein: %d)" % [Game.time_days - t0,
		w.settlers.filter(func(s): return hit.any(func(b): return s.home_id == b.id)).size()])
	# Brunnen: neben jedem Kandidaten einer, dann wird gelöscht
	for b in Events._damage_candidates(w):
		if not w.buildings.any(func(x): return x.type == "brunnen" and b.dist_sq(x.cell) <= 64):
			_place_near(w, "brunnen", b.entrance_cell(), 7)
	var before2: int = w.buildings.filter(func(b): return b.complete).size()
	var ev2 := await _force_wait(main, w, "brand")
	await _until(main, func(): return _gone(w), 0.2)
	print("Ereignis-Test Brand ", _okf(int(ev2.get("saved", 0)) >= 1 and int(ev2.get("burnt", 0)) == 0 and w.buildings.filter(func(b): return b.complete).size() == before2), " mit Brunnen: gelöscht %d, abgebrannt %d" % [int(ev2.get("saved", 0)), int(ev2.get("burnt", 0))])
	for s in w.settlers:
		if s.job == "baumeister":
			s.set_job("frei")


# ---------------------------------------------------------------- Seuche
static func _test_seuche(main) -> void:
	print("--- Ereignis-Test Seuche")
	var w = Game.world
	for s in w.settlers:
		if s.mind.sick != "":
			s.mind._recover()
	var ev := await _force_wait(main, w, "seuche")
	var m: Array = Events.type_def("seuche").mult
	var mm := clampf(float(m[0]) + float(m[1]) * float(ev.power), float(m[2]), float(m[3]))
	var want := 1.0 + (mm - 1.0) / Game.eff("heal")
	var f := Events.sickness_factor(w)
	var zero: Array = w.settlers.filter(func(s): return s.mind.sick == str(ev.ill))
	print("Ereignis-Test Seuche ", _okf(absf(f - want) < 0.001 and Events.epidemic_illness(w) == str(ev.ill) and not zero.is_empty() and Events.sickness_factor(null) == 1.0), " Krankheit x%.2f (erwartet %.2f), Seuchen-Krankheit %s, krank zu Beginn %s" % [f, want, ev.ill, zero.map(func(s): return s.display_name)])
	_set_tech("heilkunde", true)
	var f2 := Events.sickness_factor(w)
	var want2 := 1.0 + (mm - 1.0) / Game.eff("heal")
	_set_tech("heilkunde", false)
	print("Ereignis-Test Seuche ", _okf(f2 < f and absf(f2 - want2) < 0.001), " mit Heilkunde x%.2f statt x%.2f (erwartet %.2f)" % [f2, f, want2])
	# Die ganze Seuche beobachten: wer erkrankt woran?
	var seen := {}
	var t0 := Game.time_days
	while Game.time_days < float(ev.end) - 0.05 and not Game.is_over:
		for s in w.settlers:
			if s.mind.sick != "" and not seen.has(s.id):
				seen[s.id] = s.mind.sick
		await main.get_tree().process_frame
	var kinds := {}
	for k in seen:
		kinds[seen[k]] = int(kinds.get(seen[k], 0)) + 1
	print("   während der Seuche (%.1f Tage) erkrankt: %d von %d Siedlern %s, Tote bisher %d" % [Game.time_days - t0, seen.size(), w.settlers.size(), kinds, int(ev.get("deaths", 0))])
	var n0: int = w.settlers.size()
	var goods0 := Game.amount("bretter", w) + Game.amount("ziegel", w) + Game.amount("werkzeug", w) + Game.amount("eisen", w)
	var free := Game.housing_capacity(w) - n0
	ev.end = Game.time_days + 0.02
	await _until(main, func(): return _gone(w), 0.3)
	var goods1 := Game.amount("bretter", w) + Game.amount("ziegel", w) + Game.amount("werkzeug", w) + Game.amount("eisen", w)
	var deaths := int(ev.get("deaths", 0))
	var rewarded: bool = w.settlers.size() > n0 or goods1 > goods0
	print("Ereignis-Test Seuche ", _okf(_gone(w) and Events.sickness_factor(w) == 1.0 and (deaths > 0 or rewarded)), " vorbei: Tote %d, Wohnplätze frei %d, Belohnung %s (Siedler %d -> %d, Waren %d -> %d)" % [deaths, free, "Einwanderer" if w.settlers.size() > n0 else ("Waren" if goods1 > goods0 else "keine"), n0, w.settlers.size(), goods0, goods1])


# ---------------------------------------------------------------- Sturmflut
static func _test_flood(main) -> void:
	print("--- Ereignis-Test Sturmflut")
	var w = Game.world
	var field = _place_coast(w, "feld")
	var hut = _place_coast(w, "huette")
	var werft = null
	for b in w.buildings:
		if b.type == "werft":
			werft = b
	if werft == null:
		werft = _place_near(w, "werft", w.center, 30, 3)
	if field != null:
		field.farm_state = "growing"
		field.farm_time = Game.time_days
	var coast: Array = Events._flood_buildings(w)
	print("   Feld am Wasser %s, Hütte am Wasser %s, Werft %s, Gebäude am Ufer: %s" % [field != null, hut != null, werft != null, coast.map(func(b): return b.type)])
	var ev := await _force_wait(main, w, "sturmflut")
	await _until(main, func(): return _gone(w), 0.2)
	var hit: Array = coast.filter(func(b): return not b.complete)
	print("Ereignis-Test Sturmflut ", _okf(field != null and field.farm_state == "fallow" and hit.size() == mini(coast.size(), Events._hits(float(ev.power))) and (werft == null or werft.complete) and int(ev.get("fields", 0)) >= 1), " Feld %s, beschädigt %s (erwartet %d), Werft heil %s" % [field.farm_state if field else "-", hit.map(func(b): return b.type),
		mini(coast.size(), Events._hits(float(ev.power))), werft.complete if werft else "-"])
	for b in hit:
		b.complete = true
		b.progress = float(b.def.work)
		b.refresh()
	w.assign_homes()
	if field != null:
		field.farm_state = "growing"
	_set_tech("deichbau", true)
	var ev2 := await _force_wait(main, w, "sturmflut")
	await _until(main, func(): return _gone(w), 0.2)
	print("Ereignis-Test Sturmflut ", _okf((field == null or field.farm_state == "growing") and coast.all(func(b): return b.complete) and int(ev2.get("burnt", -1)) == 0), " mit Deichbau: kein Schaden (Feld %s)" % (field.farm_state if field else "-"))
	_set_tech("deichbau", false)


# ---------------------------------------------------------------- Piraten
static func _test_pirates(main) -> void:
	print("--- Ereignis-Test Piraten")
	var w = Game.world
	var lager = null
	for b in w.buildings:
		if b.type == "lager" and b.complete:
			lager = b
	if lager == null:
		lager = _place_near(w, "lager", w.center, 12, 3)
	var werft = null
	for b in w.buildings:
		if b.def.has("harbor") and b.complete:
			werft = b
	if werft == null:
		werft = _place_near(w, "werft", w.center, 30, 3)
	print("   Zeitalter %d, Hafenstufe %d, Lager %s, geeignet=%s, Händler darf vorher: %s" % [Game.current_age(), Sea.harbor_level(w), lager != null,
		Events.eligible(w, "piraten"), Merchant.eligible(w)])
	for id in ["gold", "werkzeug", "eisen", "brot"]:
		w.stock[id] = 40
	var kills0 := int(Game.stats.get("kills", 0))
	var felle0 := Game.amount("felle", w)
	var beute0: int = w.nodes.filter(func(n): return n.type == "beute").size()
	# 1. Ohne Abwehr: alle Jäger weg, kein Wachturm -> Beute erst beim Ablegen
	for s in w.settlers:
		if s.job == "jaeger":
			s.set_job("frei")
	var stock0 := {}
	for id in ["gold", "werkzeug", "eisen", "brot"]:
		stock0[id] = Game.amount(id, w)
	var ev := await _force_wait(main, w, "piraten")
	var rs: Array = Events._raiders_of(w)
	var r_ok: bool = rs.size() == int(ev.get("count", -1)) and rs.all(func(r): return r in w.animals and r.is_hostile() and w.is_huntable(r) and not w.is_protected(r))
	print("Ereignis-Test Piraten ", _okf(r_ok and rs.size() >= 2 and Events.busy(w) and not Merchant.eligible(w)), " gelandet %d (erwartet %d), feindlich, jagdbar, Händler meidet die Insel" % [rs.size(), int(ev.get("count", -1))])
	# Speichern mitten im Überfall: Piraten nicht als Tiere, Ereignis mit left
	Game.save_game()
	var data = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	var pirat_saved := false
	var animals_saved := 0
	for m in data.get("islands", []):
		if m.get("world") is Dictionary:
			for a in m.world.get("animals", []):
				animals_saved += 1
				if a is Array and (a.is_empty() or str(a[0]) == "pirat"):
					pirat_saved = true
	var sev = data.get("events", {}).get("islands", {}).get(str(w.island_id), {}).get("ev", {})
	print("Ereignis-Test Piraten ", _okf(not pirat_saved and sev is Dictionary and int(sev.get("left", 0)) == rs.size() and bool(sev.get("struck", false))), " Spielstand: keine Piraten unter %d Tieren, Ereignis gespeichert (left=%s)" % [animals_saved, sev.get("left", "-") if sev is Dictionary else "-"])
	# Laden mitten im Überfall: die Piraten landen neu
	Events._on_load(data, 1)
	var rs2: Array = Events._raiders_of(w)
	ev = Events.event_of(w)
	print("Ereignis-Test Piraten ", _okf(rs2.size() == rs.size() and not rs2.any(func(r): return r in rs) and rs2.all(func(r): return r in w.animals)), " nach dem Laden neu gelandet: %d" % rs2.size())
	var planned_taken := false
	var t0 := Game.time_days
	var log_t := 0.0
	while not _gone(w) and Game.time_days < t0 + 1.0 and not Game.is_over:
		for r in Events._raiders_of(w):
			if not r.loot.is_empty() and not planned_taken:
				planned_taken = true
				var same := true
				for id in stock0:
					if Game.amount(id, w) != int(stock0[id]):
						same = false
				print("   Pirat %s hat Beute geplant: %s, Lager noch unverändert: %s" % [r.get_instance_id(), r.loot_text(), same])
		if Game.time_days >= log_t:
			log_t = Game.time_days + 0.1
			print("   Tag %.2f: %s" % [Game.time_days + 1.0, Events._raiders_of(w).map(func(r): return "%s %d hp=%d" % [["Landung", "Plündern", "Rückweg"][r.phase], r.cell.distance_to(r.landing), int(r.hp)])])
		await main.get_tree().process_frame
	var lost := {}
	for id in stock0:
		lost[id] = int(stock0[id]) - Game.amount(id, w)
	var loot: Dictionary = ev.get("loot", {})
	var match_ok := true
	for id in loot:
		if int(lost.get(id, 0)) < int(loot[id]):
			match_ok = false
	print("Ereignis-Test Piraten ", _okf(_gone(w) and not loot.is_empty() and match_ok and planned_taken), " ohne Abwehr: Beute %s, Lager weniger %s, nach %.2f Tagen fort" % [loot, lost, Game.time_days - t0])
	# 2. Mit Abwehr: Wachturm am Lager und zwei Jäger
	var tower = _place_near(w, "wachturm", lager.entrance_cell() if lager else w.center, 10, 2)
	var hunters := 0
	for s in w.settlers:
		if hunters < 3 and s.is_adult() and s.mind.sick == "":
			s.set_job("jaeger")
			s.health = 100.0
			hunters += 1
	for id in ["gold", "werkzeug", "eisen", "brot"]:
		w.stock[id] = 40
	var gold0 := Game.amount("gold", w)
	var pir0 := int(Game.stats.get("pirates", 0))
	var ev2 := await _force_wait(main, w, "piraten")
	var t1 := Game.time_days
	await _until(main, func(): return _gone(w), 1.0)
	var kills := int(ev2.get("kills", 0))
	var loot2: Dictionary = ev2.get("loot", {})
	print("Ereignis-Test Piraten ", _okf(_gone(w) and kills >= 1 and int(Game.stats.get("pirates", 0)) == pir0 + kills), " mit Wachturm %s und %d Jägern: vertrieben %d von %d, Beute %s, Gold %d -> %d, Tote %d, nach %.2f Tagen fort" % [tower != null, hunters, kills,
		int(ev2.get("count", 0)), loot2, gold0, Game.amount("gold", w), int(ev2.get("deaths", 0)), Game.time_days - t1])
	var beute1: int = w.nodes.filter(func(n): return n.type == "beute").size()
	print("Ereignis-Test Piraten ", _okf(int(Game.stats.get("kills", 0)) == kills0 and Game.amount("felle", w) == felle0 and beute1 == beute0 and Merchant.eligible(w) and not Events.busy(w)), " keine Jagdbeute: kills %d -> %d, Felle %d -> %d, Fleischstellen %d -> %d; Händler darf wieder" % [kills0, int(Game.stats.get("kills", 0)), felle0, Game.amount("felle", w), beute0, beute1])


# ---------------------------------------------------------------- Alter Spielstand
static func _old_save_check() -> void:
	var w = Game.world
	var lines_before: int = Game.rules_lines.size()
	Events._on_load({}, 0)
	var line_ok: bool = Game.rules_lines.size() == lines_before + 1
	print("   Regelzeile: ", Game.rules_lines[-1] if line_ok else "-")
	Game.rules_lines.resize(lines_before)
	Events.tick()
	var st: Dictionary = Events.islands.get(str(w.island_id), {})
	var t := Game.time_days
	var ok: bool = line_ok and not st.is_empty() and absf(float(st.next) - maxf(t + 8.0, Events.start_time())) < 0.06 and st.ev == null
	print("Ereignis-Test alter Spielstand ", _okf(ok), " Regelzeile, Schonzeit bis Tag %.2f (jetzt Tag %.2f)" % [float(st.get("next", -1.0)) + 1.0, t + 1.0])


# ---------------------------------------------------------------- Zeitplan
## Sechs Jahre im Schnelldurchlauf (Zeit in Schritten von 0,05 Tagen, ohne Bilder dazwischen):
## Start ab Jahr 2, Abstände, Jahreszeiten, keine Art zweimal hintereinander.
static func schedule(main) -> void:
	var w = Game.world
	await _wait(main, 0.5)
	_prepare(main, 6)
	Game.goals.tut = 0
	Events.enabled = true
	for t in ["feld", "feld", "huette", "huette", "saegegrube", "raeucherei"]:
		_place_near(w, t, w.center + Vector2i(-6, 4), 16)
	_place_coast(w, "feld")
	_place_near(w, "werft", w.center, 30, 3)
	var log := []
	var t0 := Game.time_days
	var tut_blocked := true
	var prev_year := Seasons.year()
	while Game.time_days < t0 + 6.0 * Seasons.year_days():
		if Game.time_days > t0 + 20.0 and Game.goals.tut == 0:
			# Bis Tag 20 läuft noch die Einführung: in dieser Zeit darf nichts kommen
			tut_blocked = not log.any(func(e): return e[0] < Game.time_days)
			Game.goals.tut = Data.goals.get("tutorial", []).size()
		Game.time_days += 0.05
		if Seasons.year() != prev_year:
			prev_year = Seasons.year()
			Seasons._ensure_year()
		var had := Events.event_of(w).duplicate()
		Events.tick()
		var now := Events.event_of(w)
		if not now.is_empty() and (had.is_empty() or float(had.get("at", -1.0)) != float(now.at)):
			print("   Auswahl Tag %.1f (Eintritt %s, Jahreszeit %d, Winter %s, Sommer %s): %s" % [Game.time_days + 1.0, "%.1f" % (float(now.strike) + 1.0), Seasons.season(float(now.strike)), Seasons.winter_type(Seasons.year(float(now.strike))), Seasons.summer_type(Seasons.year(float(now.strike))), TYPES.map(func(t): return "%s %.1f%s" % [t, Events.weight(t, float(now.strike)), "" if Events.eligible(w, t) else " (nicht möglich)"])])
			log.append([Game.time_days, str(now.type), float(now.strike), Seasons.season(float(now.strike)), Seasons.summer_type(Seasons.year(float(now.strike))),
				Seasons.winter_type(Seasons.year(float(now.strike)))])
		# Insel am Leben halten: Gebäude heil, Waren und Siedler da
		for b in w.buildings:
			if not b.complete:
				b.complete = true
				b.progress = float(b.def.work)
				b.refresh()
		for id in ["weizen", "beeren", "fisch", "brot", "gold", "werkzeug"]:
			w.stock[id] = 80
		if w.settlers.size() < 12:
			w.spawn_newcomer("f")
	var counts := {}
	var seasons := {}
	var min_gap := 99.0
	var twice := false
	var bad_season := []
	for i in log.size():
		var e: Array = log[i]
		counts[e[1]] = int(counts.get(e[1], 0)) + 1
		var sk := "%s@%d" % [e[1], int(e[3])]
		seasons[sk] = int(seasons.get(sk, 0)) + 1
		if i > 0:
			min_gap = minf(min_gap, float(e[0]) - float(log[i - 1][0]))
			if e[1] == log[i - 1][1]:
				twice = true
		if Events.weight(str(e[1]), float(e[2])) <= 0.0 and not (e[1] == "seuche" and int(e[3]) == 3):
			bad_season.append(e)
		if e[1] == "seuche" and int(e[3]) == 3 and str(e[5]) in ["hart", "bitter"]:
			bad_season.append(e)
	var first := float(log[0][0]) if not log.is_empty() else -1.0
	print("Ereignis-Zeitplan: %d Ereignisse in 6 Jahren, je Art %s" % [log.size(), counts])
	print("   Art@Jahreszeit beim Eintritt (0 Frühling .. 3 Winter): ", seasons)
	print("   Ablauf: ", log.map(func(e): return "Tag %.1f %s (Eintritt %.1f)" % [float(e[0]) + 1.0, e[1], float(e[2]) + 1.0]))
	var ok := not log.is_empty() and first >= 20.0 and tut_blocked and min_gap >= 3.0 - 0.001 and not twice and bad_season.is_empty() and log.size() <= 30
	print("Ereignis-Test Zeitplan ", _okf(ok), " erstes Tag %.1f (Einführung bis Tag 21), kleinster Abstand %.2f Tage (mind. 3), keine Art zweimal hintereinander: %s, Jahreszeit passt: %s" % [
		first + 1.0, min_gap, not twice, bad_season.is_empty()])
	Events.enabled = false


# ---------------------------------------------------------------- Bildschirmfotos
## --eventshot=<art>: ankündigen (Vorwarnung 1,5 Tage); <art>:now: eintreten lassen. Dazu --eventtap=1 und
## --selectraider=1 (über die Testargumente von main).
static func shot(main, spec: String) -> void:
	var parts := spec.split(":")
	var typ := parts[0]
	var now := parts.size() > 1 and parts[1] == "now"
	var w = Game.world
	await _wait(main, 0.3)
	_prepare(main, 6 if typ == "piraten" else 4)
	if typ == "piraten":
		if Sea.harbor_level(w) < 1:
			_place_near(w, "werft", w.center, 30, 3)
		_place_near(w, "lager", w.center, 12, 3)
		for id in ["gold", "werkzeug"]:
			w.stock[id] = 30
	if typ == "duerre":
		_place_near(w, "feld", w.center + Vector2i(-6, 3), 12)
	var ev := Events.force(w, typ, 0.02 if now else 1.5)
	if now:
		await _until(main, func(): return bool(ev.get("struck", false)), 0.3)
	print("Ereignis-Bild: %s %s, Knopf: %s" % [typ, "läuft" if ev.get("struck", false) else "angekündigt", Events.chip().get("name", "-")])
	var args: Dictionary = main._user_args()
	var chip: EventChip = null
	for c in main.hud.top_alerts.get_children():
		if c is EventChip:
			chip = c
	if chip != null:
		chip.refresh()
		print("Ereignis-Bild Antippen: ", chip.tap_text())
	if args.has("selectraider") and typ == "piraten":
		await _wait(main, float(args.get("raiderwait", "1.0")))
		var rs := Events._raiders_of(w)
		if not rs.is_empty():
			Game.select(rs[0])
			main.camera.focus(rs[0].position)
	if args.has("eventtap") and chip != null:
		var secs := float(args.get("autotest", "20"))
		main.get_tree().create_timer(maxf(0.3, secs - 1.5), true, false, true).timeout.connect(func():
			chip.pressed.emit()
			var r: Rect2 = chip.get_global_rect()
			var vs: Vector2 = chip.get_viewport().get_visible_rect().size
			print("Ereignis-Knopf: sichtbar=%s bei x=%d..%d y=%d..%d, Bild %dx%d, im Bild=%s, Text '%s'" % [chip.is_visible_in_tree(), r.position.x, r.end.x,
				r.position.y, r.end.y, vs.x, vs.y, r.end.x <= vs.x and r.position.x >= 0, chip.text]))
