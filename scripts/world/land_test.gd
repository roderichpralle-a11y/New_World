class_name LandTest
extends RefCounted
## Selbsttest --landtest=1 (aus main.gd): Straße (Maske, Tempo, Baumeister baut), Deich im Wasser,
## Neuland hinter Deichen, Spielstand, Deichbruch mit Überflutung und Rückkehr der Gebäude,
## Wiederaufbau für 70 %, Förster (pflanzen, roden). Druckt "Land OK/FEHLER".
## --landshot=road|dike: Straßen, Deiche, Neuland, Förster mit Pflanzstelle für ein Bildschirmfoto.

static var fails := 0


static func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("Land ", "OK " if c else "FEHLER ", what)


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


## Küstenstück: Wasserzellen a und a+(1,0), nördlich davon gerades Ufer (4 Landzellen), westlich,
## östlich und südlich freies Wasser für vier Deiche.
static func find_bay(w):
	for y in range(2, w.size - 3):
		for x in range(2, w.size - 3):
			var a := Vector2i(x, y)
			var ok := true
			for c in [a, a + Vector2i(1, 0), a + Vector2i(-1, 0), a + Vector2i(2, 0), a + Vector2i(0, 1), a + Vector2i(1, 1)]:
				if not w.is_water(c) or w.node_at.has(c) or w.building_at.has(c):
					ok = false
			for c in [a + Vector2i(-1, -1), a + Vector2i(0, -1), a + Vector2i(1, -1), a + Vector2i(2, -1)]:
				if w.is_water(c) or w.building_at.has(c) or not w.is_walkable(c):
					ok = false
			if ok:
				return a
	return null


## Die vier Deiche um die Bucht (der letzte schließt sie).
static func bay_dikes(a: Vector2i) -> Array:
	return [a + Vector2i(-1, 0), a + Vector2i(2, 0), a + Vector2i(0, 1), a + Vector2i(1, 1)]


static func _free_land(w, near: Vector2i, avoid: Array = []):
	for r in range(1, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c: Vector2i = near + Vector2i(dx, dy)
				if c in avoid or not w.is_inside(c) or w.is_water(c) or w.node_at.has(c) or w.building_at.has(c):
					continue
				if w.is_walkable(c) and w.is_walkable(c + Vector2i(1, 0)) and not w.building_at.has(c + Vector2i(1, 0)) \
						and not w.node_at.has(c + Vector2i(1, 0)):
					return c
	return null


static func run(main) -> void:
	fails = 0
	var w = main.world
	_research(["steinwerkzeuge", "steinbruch", "wegebau", "toepferei", "zimmerei", "maurerei", "bewaesserung", "deichbau"])
	Game.add_stock("stein", 50, w)  # Lagerfeuer fasst nur 200 Raum
	Game.add_stock("holz", 20, w)
	Game.add_stock("lehm", 20, w)
	Game.add_stock("beeren", 40, w)
	await _fastest_way(main, w)
	# ---- Straße
	var rc = _free_land(w, w.center + Vector2i(4, 4))
	var r1 = w.place_building("strasse", rc, true)
	var r2 = w.place_building("strasse", rc + Vector2i(1, 0), true)
	_ok(w.road_at(rc) and w.tile_mask(r1) == 2 and w.tile_mask(r2) == 8, "Straßen verbinden sich (Masken %d, %d)" % [w.tile_mask(r1), w.tile_mask(r2)])
	var s = w.settlers[0]
	s.abort_plan()
	var speed := func(c: Vector2i) -> float:
		s.cell = c
		s.position = w.cell_to_pos(c)
		s._path = PackedVector2Array([s.position, s.position + Vector2(400, 0)])
		s._path_i = 1
		var p0: Vector2 = s.position
		s._walk(0.05)
		var d: float = s.position.distance_to(p0)
		s.position = p0
		return d
	var far = _free_land(w, w.center + Vector2i(-6, 6), [rc, rc + Vector2i(1, 0)])
	var on_road: float = speed.call(rc)
	var off_road: float = speed.call(far)
	_ok(absf(on_road / maxf(0.001, off_road) - 1.5) < 0.05, "auf der Straße 1,5-mal so schnell (%.2f / %.2f)" % [on_road, off_road])
	s.cell = w.center
	s.position = w.cell_to_pos(w.center)
	# Baumeister baut eine Straße
	var rc3 = _free_land(w, w.center + Vector2i(-3, 5), [rc, rc + Vector2i(1, 0)])
	_ok(w.can_place("strasse", rc3), "Straße lässt sich setzen")
	var site = w.place_building("strasse", rc3, false)
	for o in w.settlers:
		if o.is_adult():
			o.set_job("baumeister")
			break
	var built: bool = await _wait(main, func(): return site.complete, 40.0)
	_ok(built and w.road_at(rc3), "Baumeister baut die Straße (Stein %d)" % Game.amount("stein", w))
	# ---- Deich und Neuland
	var a = find_bay(w)
	_ok(a != null, "Bucht gefunden %s" % [a])
	if a == null:
		print("Land FEHLER (%d Fehler)" % (fails))
		return
	_ok(w.can_place("deich", a + Vector2i(-1, 0)), "Deich im Wasser am Ufer geht")
	var deep = null
	for y in w.size:
		for x in w.size:
			var c := Vector2i(x, y)
			if deep == null and w.is_water(c) and not w.node_at.has(c) and [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)].all(
					func(d): return w.is_water(c + d) and not w.building_at.has(c + d)):
				deep = c
	_ok(deep != null and not w.can_place("deich", deep), "Deich mitten im Wasser geht nicht")
	_ok(not w.can_place("strasse", a), "Straße nicht im Wasser")
	var cells: Array = bay_dikes(a)
	var dikes := []
	for i in 3:
		dikes.append(w.place_building("deich", cells[i], true))
	Land.update_polders(w, true)
	_ok(w.is_water(a) and w.land_mod.is_empty(), "noch offen: kein Neuland")
	_ok(not w.is_walkable(cells[3]), "Lücke im Deich ist Wasser")
	# Der letzte Deich wird vom Baumeister gebaut (im Wasser, vom fertigen Deich aus)
	var last = w.place_building("deich", cells[3], false)
	dikes.append(last)
	var done: bool = await _wait(main, func(): return last.complete, 60.0)
	_ok(done, "Baumeister baut den Deich im Wasser")
	_ok(not w.is_water(a) and not w.is_water(a + Vector2i(1, 0)) and w.land_mod.size() == 2, "Neuland: 2 Felder (%s)" % [w.land_mod])
	_ok(w.is_walkable(cells[0]), "fertiger Deich ist begehbar")
	# Spielstand
	var d: Dictionary = JSON.parse_string(JSON.stringify(w.serialize()))
	var island := {"terrain": w.terrain.duplicate()}
	for idx in w.land_mod:
		island.terrain[idx] = World.WATER
	var keep: Dictionary = w.land_mod.duplicate()
	Land.apply_saved(w, island, d)
	_ok(w.land_mod.size() == keep.size() and island.terrain[a.y * w.size + a.x] != World.WATER, "Neuland bleibt im Spielstand")
	var old := {"terrain": PackedByteArray([0, 0])}
	var lm: Dictionary = w.land_mod.duplicate()
	Land.apply_saved(w, old, {})
	_ok(w.land_mod.is_empty(), "alter Spielstand: kein Neuland")
	w.land_mod = lm
	# Gebäude auf Neuland, dann Deichbruch
	var on_new = w.place_building("strasse", a, true)
	var tree = w.spawn_node("baum", a + Vector2i(1, 0))
	Events.damage_building(w, dikes[1])
	w._set_solid(dikes[1].cell, true)
	var r: Dictionary = Land.flood(w, [dikes[1]])
	_ok(int(r.cells) == 2 and w.is_water(a) and not is_instance_valid(tree) or tree.is_queued_for_deletion(), "Deichbruch: Neuland überflutet (%s)" % [r])
	_ok(not w.buildings.has(on_new) and w.sunk.size() == 1, "Gebäude auf Neuland untergegangen, gemerkt %s" % [w.sunk])
	var cost: int = int(dikes[1].def.cost.stein)
	_ok(int(dikes[1].delivered.get("stein", 0)) == cost - ceili(cost * 0.7), "Deich neu bauen kostet 70 %% (geliefert %s)" % [dikes[1].delivered])
	# Deich wieder aufbauen: Land kommt zurück, die Straße als Baustelle (70 %)
	dikes[1].delivered = dikes[1].def.cost.duplicate()
	dikes[1].add_work(float(dikes[1].def.work) + 1.0)
	var back = w.building_at.get(a)
	_ok(not w.is_water(a) and back != null and not back.complete and int(back.delivered.get("stein", 0)) == 20 - 14,
		"Deich steht wieder: Neuland und Straße als Baustelle %s" % [back.delivered if back else "-"])
	# Sturmflut bricht einen äußeren Deich (Wahrscheinlichkeit erzwungen)
	var sd: Dictionary = Events.type_def("sturmflut")
	var b0 = sd.get("breach_base", 0.3)
	sd["breach_base"] = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var outer: int = Land.outer_dikes(w).size()
	var txt := Land.storm(w, rng, 1.0)
	sd["breach_base"] = b0
	print("Land: Sturmflut ", txt)
	_ok(outer >= 3 and txt != "" and w.buildings.any(func(b): return b.type == "deich" and not b.complete), "Sturmflut bricht einen äußeren Deich (%d äußere)" % outer)
	# ---- Wiederaufbau für 70 % nach Ereignis
	_ok(main._place_on(w, "huette"), "Hütte gebaut")
	var hut = null
	for b in w.buildings:
		if b.type == "huette" and b.complete:
			hut = b
	Events.damage_building(w, hut)
	_ok(not hut.complete and int(hut.delivered.holz) == 16 - ceili(16 * 0.7), "Hütte nach Ereignis: Neuaufbau 70 %% (geliefert %s)" % [hut.delivered])
	# ---- Förster
	var f = null
	for o in w.settlers:
		if o.is_adult() and o.job != "baumeister":
			f = o
	if f == null:
		f = w.settlers[0]
	f.set_job("foerster")
	f.hunger = 100.0
	var pc = _free_land(w, f.cell + Vector2i(2, 2))
	_ok(w.can_place("setzling", pc), "Pflanzstelle lässt sich setzen")
	var ps = w.place_building("setzling", pc, false)
	var mark = null
	for nd in w.nodes:
		if nd.type == "baum" and nd.amount > 0 and Vector2(nd.cell - f.cell).length() < 20:
			mark = nd
			break
	mark.clear_mark = true
	mark.refresh()
	var mcell: Vector2i = mark.cell
	var planted: bool = await _wait(main, func(): return w.node_at.has(pc) and w.node_at[pc].type == "baum", 40.0)
	_ok(planted and not w.buildings.has(ps), "Förster pflanzt einen Baum (%s)" % f.activity)
	var cleared: bool = await _wait(main, func(): return not w.node_at.has(mcell), 40.0)
	_ok(cleared, "Förster rodet den markierten Baum")
	var nd2 = w.nodes.filter(func(n): return n.type == "busch")
	if not nd2.is_empty():
		nd2[0].clear_mark = true
		var ser: Array = nd2[0].serialize()
		_ok(ser.size() == 7 and int(ser[6]) == 1, "Markierung steht im Spielstand")
		nd2[0].clear_mark = false
		nd2[0].refresh()
	print("Land %s (%d Fehler)" % ["OK" if fails == 0 else "FEHLER", fails])


## Freier Landstreifen (29 x 5) weit weg von allen Lagern; Bäume und Büsche darin werden entfernt.
static func _strip(w):
	for y0 in range(2, w.size - 7):
		for x0 in range(14, w.size - 18):
			var ok := true
			for y in range(y0, y0 + 5):
				for x in range(x0 - 12, x0 + 17):
					var c := Vector2i(x, y)
					if w.is_water(c) or w.building_at.has(c):
						ok = false
						break
				if not ok:
					break
			if not ok:
				continue
			for b in w.buildings:
				if b.is_storage() and Vector2(b.cell - Vector2i(x0, y0 + 3)).length() < 15.0:
					ok = false
			if ok:
				return Vector2i(x0, y0)
	return null


## Schnellster Weg (josh 2026-10-12): Straßen zählen bei der Wegsuche und bei der Wahl des Lagers.
static func _fastest_way(main, w) -> void:
	var p0 = _strip(w)
	if p0 == null:
		print("Land: kein freier Streifen für den Wegtest, übersprungen (Insel %d)" % w.size)
		return
	for y in range(p0.y, p0.y + 5):
		for x in range(p0.x - 12, p0.x + 17):
			var n = w.node_at.get(Vector2i(x, y))
			if n != null:
				w.remove_node(n)
	var o: Vector2i = p0 + Vector2i(0, 3)
	var x: Vector2i = p0 + Vector2i(12, 3)
	var grass := func(path: PackedVector2Array) -> int:
		var n := 0
		for pt in path:
			if not w.road_at(Vector2i((pt / World.T).floor())):
				n += 1
		return n
	_ok(grass.call(w.find_path(o, x)) == 13, "ohne Straße geradeaus (%d Felder)" % w.find_path(o, x).size())
	var l1 = w.place_building("lager", p0 + Vector2i(-13, 2), true)   # 11 Felder links, nur Gras
	var l2 = w.place_building("lager", p0 + Vector2i(13, 2), true)    # 13 Felder rechts, an der Straße
	_ok(w.nearest_storage(o) == l1, "ohne Straße: das Lager links ist am nächsten")
	var roads := []
	for i in range(0, 13):
		roads.append(w.place_building("strasse", p0 + Vector2i(i, 2), true))
	var path: PackedVector2Array = w.find_path(o, x)
	_ok(grass.call(path) <= 3, "mit Straße: der Weg nimmt die Straße (%d von %d Feldern Gras)" % [grass.call(path), path.size()])
	var t_road: float = w.travel_time(o, l2)
	var t_grass: float = w.travel_time(o, l1)
	_ok(w.nearest_storage(o) == l2 and t_road < t_grass, "mit Straße: das weitere Lager ist schneller (%.1f statt %.1f)" % [t_road, t_grass])
	_ok(w.delivery_storage(o) == l2, "Abliefern immer im schnellsten Lager")
	for b in roads + [l1, l2]:
		w.demolish(b)
	_ok(w.astar.get_point_weight_scale(p0 + Vector2i(5, 2)) > 1.0, "abgerissene Straße kostet wieder wie Gras")


## Bildschirmfoto: Straßen, Deiche mit Neuland, Förster mit Pflanzstelle und markiertem Baum.
static func shot(main, kind: String) -> void:
	var w = main.world
	_research(["steinwerkzeuge", "steinbruch", "wegebau", "deichbau"])
	var a = find_bay(w)
	if a != null:
		for c in bay_dikes(a):
			w.place_building("deich", c, true)
		if w.can_place("deich", a + Vector2i(2, 1)):
			w.place_building("deich", a + Vector2i(2, 1), true)
		if w.can_place("deich", a + Vector2i(2, 2)):
			w.place_building("deich", a + Vector2i(2, 2), false)
		Land.update_polders(w, true)
		if kind == "dike":
			main.camera.focus(w.cell_to_pos(a))
	var rc = w.center + Vector2i(0, 3)
	for i in 7:
		var c: Vector2i = rc + Vector2i(i - 3, 0)
		if w.can_place("strasse", c):
			w.place_building("strasse", c, i < 6)
	for i in 3:
		var c: Vector2i = rc + Vector2i(3, -1 - i)
		if w.can_place("strasse", c):
			w.place_building("strasse", c, true)
	var pc = _free_land(w, w.center + Vector2i(-4, 5))
	if pc != null:
		w.place_building("setzling", pc, false)
	for nd in w.nodes:
		if nd.type == "baum" and Vector2(nd.cell - w.center).length() < 12:
			nd.clear_mark = true
			nd.refresh()
			break
	w.settlers[0].set_job("foerster")
	if a == null or kind != "dike":
		main.camera.focus(w.cell_to_pos(rc))
	main.camera.zoom = Vector2(2.5, 2.5)
