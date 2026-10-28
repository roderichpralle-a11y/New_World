class_name DecorTest
extends RefCounted
## Selbsttest --decortest=1 (aus main.gd, josh 2026-10-20): Schmuck (Bau-Reiter „Schmuck“). Prüft:
## mindestens 18 Stücke, nach und nach durch Forschungen in mehreren Zeitaltern freigeschaltet, Laune
## „Wohnt in schöner Umgebung“ mit Obergrenze und nach Abriss weg, Kies- und Ziegelweg schneller als Gras
## (auch in der Wegsuche), Hecke hält Tiere ab, Park und Bank als Freizeitorte (sitzen, langsam gehen),
## Bilder (Brunnen und Fahne bewegt), Spielstand. Druckt „Schmuck OK/FEHLER“.
## --decorshot=1: kleines Dorf mit allem Schmuck (Bildschirmfoto); --decorshot=bench: Nahaufnahme Bank und Park.

static var fails := 0


static func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("Schmuck ", "OK " if c else "FEHLER ", what)


## Echtzeit warten; hält ein Fenster (z. B. nach vielen Forschungen) das Spiel an, läuft es mit Tempo 4 weiter.
static func _sleep(main, secs: float) -> void:
	var t := 0.0
	while t < secs:
		if Engine.time_scale < 0.5:
			Game.set_speed(4)
		await main.get_tree().create_timer(0.05, true, false, true).timeout
		t += 0.05


static func _research(ts: Array) -> void:
	for t in ts:
		if not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()


## Alle Forschungen bis Stufe 14 (ohne KI und Superintelligenz, die das Spiel umkrempeln).
static func most_techs() -> Array:
	return Data.techs.keys().filter(func(t): return int(Data.techs[t].tier) <= 14)


static func decor_types() -> Array:
	return Data.buildings.keys().filter(func(t): return Data.buildings[t].get("category", "") == "schmuck")


## Freies Landstück (2*rx+1) x (2*ry+1) um einen Punkt nahe der Mitte: kein Wasser, keine Gebäude.
## Bäume und Steine darauf werden entfernt.
static func clear_spot(w, rx: int, ry: int):
	for r in range(4, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c: Vector2i = w.center + Vector2i(dx, dy)
				var ok := true
				for y in range(-ry - 1, ry + 2):
					for x in range(-rx - 1, rx + 2):
						var cc := c + Vector2i(x, y)
						if not w.is_inside(cc) or w.is_water(cc) or w.building_at.has(cc):
							ok = false
							break
					if not ok:
						break
				if ok:
					for y in range(-ry - 1, ry + 2):
						for x in range(-rx - 1, rx + 2):
							var n = w.node_at.get(c + Vector2i(x, y))
							if n != null:
								w.remove_node(n)
					return c
	return null


## Kleines Dorf mit jedem Schmuckstück um o (Platz 23 x 15 Felder).
const VILLAGE := [
	["kiesweg_row", 0, 0], ["ziegelweg_col", 0, 0],
	["blumenbeet_rot", -10, -1], ["blumenbeet_gelb", -9, -1], ["blumenbeet_blau", -8, -1], ["holzbank", -6, -1],
	["laterne", -4, -1], ["menhir", -2, -1], ["fahnenmast", 1, -1], ["steinstatue", 3, -1], ["blumenkuebel", 4, -1],
	["rosenbogen", 6, -1], ["sonnenuhr", 7, -1], ["obelisk", 9, -1], ["bronzestatue", 10, -1],
	["springbrunnen", -4, -4], ["reiterdenkmal", -9, -4], ["pavillon", 5, -4], ["strassenlaterne", 1, 1],
	["teich", -9, 2], ["parkanlage", 3, 2], ["holzbank", 7, 2], ["hologramm", -2, 1],
	["blumenkuebel", 2, -5], ["blumenkuebel", 8, -5], ["blumenbeet_rot", -6, 2], ["blumenbeet_gelb", -5, 2],
]


static func build_village(w, o: Vector2i) -> void:
	for e in VILLAGE:
		var c: Vector2i = o + Vector2i(e[1], e[2])
		match e[0]:
			"kiesweg_row":
				for x in range(-11, 12):
					if x != 0:
						w.place_building("kiesweg", o + Vector2i(x, 0), true)
			"ziegelweg_col":
				for y in range(-7, 8):
					w.place_building("ziegelweg", o + Vector2i(0, y), true)
			_:
				if w.can_place(e[0], c):
					w.place_building(e[0], c, true)
				else:
					print("Schmuck: kein Platz für ", e[0], " bei ", c)
	# Hecke als Rahmen unten links
	for x in range(-11, -1):
		if w.can_place("hecke", o + Vector2i(x, 6)):
			w.place_building("hecke", o + Vector2i(x, 6), true)
	for y in range(4, 6):
		if w.can_place("hecke", o + Vector2i(-11, y)):
			w.place_building("hecke", o + Vector2i(-11, y), true)
	w.decor_dirty()


static func shot(main, what: String) -> void:
	var w = main.world
	# Bis Stufe 10 (ohne Elektrizität, deren Fenster das Bild verdecken würde); gebaut wird ohnehin direkt
	_research(Data.techs.keys().filter(func(t): return int(Data.techs[t].tier) <= 10))
	var o = clear_spot(w, 11, 7)
	if o == null:
		print("Schmuck FEHLER kein Platz für das Dorf")
		return
	build_village(w, o)
	# Siedler: zwei auf der Bank, einer im Park, einer im Pavillon
	var adults: Array = w.settlers.filter(func(s): return s.is_adult())
	var spots := [["bench", o + Vector2i(-6, -1)], ["park", o + Vector2i(3, 2)], ["bench", o + Vector2i(-6, -1)], ["pavilion", o + Vector2i(5, -4)]]
	for i in mini(adults.size(), spots.size()):
		var s = adults[i]
		var b = w.building_at.get(spots[i][1])
		if b == null:
			continue
		s.abort_plan()
		s.cell = b.entrance_cell() if spots[i][0] != "park" else b.cell + Vector2i(1, 2)
		s.position = w.cell_to_pos(s.cell)
		s._think_cooldown = 999.0
		if spots[i][0] == "park":
			s._plan.append({"a": "wait", "t": 999.0, "rest": true, "act": Loc.t("Spaziert durch den Park")})
		else:
			var seat: Vector2 = b.position + (Vector2(-4 + 8 * (i / 2), 1) if spots[i][0] == "bench" else Vector2(-3, -9))
			s._plan.append({"a": "wait", "t": 999.0, "rest": true, "act": "", "sit": seat, "sit_b": b.id})
	main.camera.focus(w.cell_to_pos(o + (Vector2i(-3, 0) if what == "bench" else Vector2i.ZERO)))
	if what == "bench":
		main.camera.zoom = Vector2(4, 4)


static func run(main) -> void:
	fails = 0
	var prev_scale := Engine.time_scale
	var w = main.world
	var types := decor_types()
	_ok(types.size() >= 18, "%d Schmuckstücke im Bau-Reiter „Schmuck“" % types.size())
	var need := ["springbrunnen", "steinstatue", "bronzestatue", "reiterdenkmal", "blumenbeet_rot", "blumenbeet_gelb",
		"blumenbeet_blau", "blumenkuebel", "hecke", "rosenbogen", "kiesweg", "ziegelweg", "parkanlage", "fahnenmast", "holzbank"]
	_ok(need.all(func(t): return Data.buildings.has(t) and Data.buildings[t].category == "schmuck"), "Brunnen, Statuen, Blumen, Wege, Park, Fahnenmast, Bank")
	_ok(Hud.BUILD_CATS.any(func(c): return c[0] == "schmuck"), "Reiter „Schmuck“ im Bau-Menü")
	# Nach und nach freigeschaltet
	var ages := {}
	var all_tech := true
	for t in types:
		var req := str(Data.buildings[t].get("requires", ""))
		if not Data.techs.has(req):
			all_tech = false
			continue
		ages[Data.age_of_tier(int(Data.techs[req].tier))] = true
	_ok(all_tech, "jedes Stück braucht eine Forschung")
	_ok(ages.size() >= 5, "freigeschaltet über %d Zeitalter" % ages.size())
	var locked := types.filter(func(t): return not Game.is_unlocked(t))
	_ok(locked.size() >= types.size() - 4, "am Anfang fast alles gesperrt (%d von %d)" % [locked.size(), types.size()])
	_ok(not Game.is_unlocked("springbrunnen"), "Springbrunnen gesperrt ohne Maurerei")
	_research(["maurerei"])
	_ok(Game.is_unlocked("springbrunnen") and Game.is_unlocked("ziegelweg"), "Maurerei schaltet Springbrunnen und Ziegelweg frei")
	_ok(not Game.is_unlocked("hologramm"), "Hologramm-Statue erst mit Computer")
	_research(most_techs())
	_ok(types.all(func(t): return Game.is_unlocked(t)), "alles erforscht: alles baubar")
	# Platz für die Tests
	var o = clear_spot(w, 8, 6)
	if o == null:
		_ok(false, "kein Platz")
		return
	# Haus mit Bewohner
	var house = w.place_building("huette", o + Vector2i(-8, -6), true)
	w.assign_homes()
	var s = w.settlers[0]
	s.home_id = house.id
	var has_line := func():
		s.mind._update_mood(0.0)
		return s.mind.reasons.any(func(r): return str(r[0]) == Loc.t("Wohnt in schöner Umgebung"))
	_ok(w.decor_mood(house) == 0.0 and not has_line.call(), "ohne Schmuck keine schöne Umgebung")
	var bed = w.place_building("blumenbeet_rot", o + Vector2i(-5, -6), true)
	var m1: float = w.decor_mood(house)
	_ok(m1 > 0.0 and has_line.call(), "Blumenbeet nebenan: „Wohnt in schöner Umgebung“ (+%.1f)" % m1)
	var far = w.place_building("springbrunnen", o + Vector2i(6, 4), true)
	_ok(is_equal_approx(w.decor_mood(house), m1), "Brunnen weit weg zählt nicht")
	w.demolish(far)
	var site = w.place_building("springbrunnen", o + Vector2i(-5, -3), false)
	_ok(is_equal_approx(w.decor_mood(house), m1), "Baustelle zählt noch nicht")
	site.progress = 99999.0
	site.complete = true
	site.refresh()
	w.on_building_completed(site)
	var m2: float = w.decor_mood(house)
	_ok(m2 > m1, "fertiger Brunnen in der Nähe: mehr Laune (%.1f -> %.1f)" % [m1, m2])
	var extra := []
	for i in 6:
		for c in [o + Vector2i(-3 + i, -6), o + Vector2i(-3 + i, -1)]:
			if w.can_place("reiterdenkmal", c):
				extra.append(w.place_building("reiterdenkmal", c, true))
	var m3: float = w.decor_mood(house)
	_ok(m3 <= float(Data.bal("decor_mood_max", 8.0)) + 0.001 and m3 > m2, "viel Schmuck: höchstens +%d (%.1f)" % [int(Data.bal("decor_mood_max", 8.0)), m3])
	for b in extra + [site, bed]:
		w.demolish(b)
	_ok(w.decor_mood(house) == 0.0 and not has_line.call(), "nach dem Abriss wieder weg")
	# Wege
	var gc: Vector2i = o + Vector2i(-2, 3)
	var g = w.place_building("kiesweg", gc, true)
	var bc: Vector2i = o + Vector2i(-2, 5)
	var br = w.place_building("ziegelweg", bc, true)
	var road_w := float(Data.bal("road_speed", 1.5))
	_ok(is_equal_approx(w.path_speed(gc), 1.2) and is_equal_approx(w.path_speed(bc), 1.3), "Kiesweg 1,2-mal, Ziegelweg 1,3-mal so schnell")
	_ok(is_equal_approx(w.path_speed(o + Vector2i(-2, 4)), 1.0), "Gras normal")
	_ok(is_equal_approx(w.astar.get_point_weight_scale(gc), road_w / 1.2) and is_equal_approx(w.astar.get_point_weight_scale(bc), road_w / 1.3),
		"Wegsuche rechnet mit dem Tempo (%.2f, %.2f)" % [w.astar.get_point_weight_scale(gc), w.astar.get_point_weight_scale(bc)])
	var g2 = w.place_building("kiesweg", gc + Vector2i(1, 0), true)
	_ok(w.tile_mask(g) == 2 and w.tile_mask(g2) == 8, "Kieswege verbinden sich")
	w.demolish(g)
	_ok(is_equal_approx(w.astar.get_point_weight_scale(gc), road_w), "abgerissen: wieder Gras")
	# Laufen: Siedler läuft 6 Felder auf Kies schneller als auf Gras (Fenster der Forschung halten das Spiel an)
	var t_grass := _walk_time(main, w, s, o + Vector2i(-8, 3), 6)
	for x in 7:
		if not w.building_at.has(o + Vector2i(-8 + x, 3)):
			w.place_building("kiesweg", o + Vector2i(-8 + x, 3), true)
	var t_gravel := _walk_time(main, w, s, o + Vector2i(-8, 3), 6)
	_ok(t_gravel < t_grass * 0.92, "auf Kies schneller (%.2f s statt %.2f s)" % [t_gravel, t_grass])
	# Hecke hält Tiere ab
	var hc: Vector2i = o + Vector2i(5, -6)
	w.place_building("hecke", hc, true)
	_ok(w.fence_at(hc) and not w.animal_walkable(hc) and w.is_walkable(hc), "Hecke: Tiere kommen nicht durch, Siedler schon")
	# Freizeit: Park und Bank
	var park = w.place_building("parkanlage", o + Vector2i(2, 1), true)
	var bench = w.place_building("holzbank", o + Vector2i(7, 0), true)
	_ok(park.prop_cells().all(func(c): return not w.is_walkable(c)) and w.is_walkable(park.cell + Vector2i(1, 1)), "Park begehbar, die Bäume nicht")
	var sits := 0
	var strolls := 0
	s.cell = o + Vector2i(4, 5)
	s.position = w.cell_to_pos(s.cell)
	for i in 60:
		s.abort_plan()
		if not s._plan_leisure():
			continue
		for st in s._plan:
			if st.has("sit") and st.get("sit_b", -1) == bench.id:
				sits += 1
				break
		for st in s._plan:
			if st.a == "move" and float(st.get("speed", 1.0)) < 1.0 and park.cells().has(st.cell):
				strolls += 1
				break
	_ok(sits >= 5, "in der Freizeit auf der Bank sitzen (%d von 60)" % sits)
	_ok(strolls >= 5, "langsam durch den Park gehen (%d von 60)" % strolls)
	# Sitzen: auf der Bank, nach vorn
	s.abort_plan()
	s._think_cooldown = 5.0
	var seat: Vector2 = bench.position + Vector2(-4, 1)
	s.cell = bench.entrance_cell()
	s.position = w.cell_to_pos(s.cell)
	s._plan.append({"a": "wait", "t": 3.0, "rest": true, "act": Loc.t("Sitzt auf der Bank"), "sit": seat, "sit_b": bench.id})
	Game.set_speed(4)
	await _sleep(main, 0.3)
	# Siedler-Bögen (2.0): eigenes Bild im Sitzen statt der 2 Pixel tiefer gesetzten Figur
	var on_bench: bool = s._body.position.y > 0.0 if s._sied_kind == "" else s._layers["fig"].frame / 24 == int(Settler.SIED_FREI["sitzen"])
	_ok(s.position.distance_to(seat) < 0.5 and on_bench, "sitzt auf der Bank (%s, %s, Körper %.0f, %s)" % [s.position, seat, s._body.position.y, s._plan.map(func(a): return a.a)])
	await _sleep(main, 1.2)
	_ok(s.position.distance_to(w.cell_to_pos(s.cell)) < 4.0, "steht danach wieder auf (Tempo %.1f)" % Engine.time_scale)
	s._think_cooldown = 0.0
	# Bilder
	_ok(Data.object_frames("fountain") == 4 and Data.object_frames("flagpole") == 4, "Brunnen und Fahne bewegt (4 Bilder)")
	var fl = w.place_building("fahnenmast", o + Vector2i(7, -4), true)
	var tex0: Texture2D = fl._sprite.texture
	await _sleep(main, 0.35)
	_ok(fl._sprite.texture != tex0, "die Fahne weht")
	for t in types:
		var d: Dictionary = Data.buildings[t]
		if not d.has("tile") and not Data.BUILDING_CELLS.has(str(d.sprite)):
			_ok(false, "Bild fehlt: " + t)
	# Schmuck versperrt keine Tür
	_ok(not w.can_place("menhir", house.entrance_cell()), "Schmuck nicht vor eine Tür")
	# Spielstand
	var data = JSON.parse_string(JSON.stringify(w.serialize()))
	_ok(data != null and str(data).find("parkanlage") >= 0 and str(data).find("holzbank") >= 0 and str(data).find("kiesweg") >= 0, "Schmuck im Spielstand")
	Game.set_speed(1)
	Engine.time_scale = prev_scale
	print("Schmuck fertig: %d Fehler" % fails)


## Spielzeit, die der Siedler für n Felder nach rechts ab c braucht (Settler._walk mit festen Schritten).
static func _walk_time(main, w, s, c: Vector2i, n: int) -> float:
	s.abort_plan()
	s.set_process(false)
	s.cell = c
	s.position = w.cell_to_pos(c)
	s.hunger = 100.0
	s._path = w.find_path(c, c + Vector2i(n, 0))
	s._path_i = 1
	var t := 0.0
	while s._path_i < s._path.size() and t < 60.0:
		s._walk(0.02)
		t += 0.02
	s.set_process(true)
	return t
