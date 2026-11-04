class_name AgeTest
extends RefCounted
## Zeitalter-Test nach dem Useraktionsplan (josh 2026-10-31, /mnt/project-files/konzept/useraktionsplan/):
## baut das Startszenario eines Zeitalters (Siedler, Gebäude, Forschung, Vorräte, Starttag) und lässt den
## Plan-Bot (scripts/world/plan_bot.gd) spielen, bis die Prüfung bestanden ist oder das Limit erreicht ist.
## Aufruf: godot --headless --fixed-fps 60 -- --autotest=<sek> --scale=15 --seed=11 --agetest=<0..6> [--workday=0]
## --workday=0 schaltet den festen Arbeitstag (Schritt 1) zum Vergleich ab.

## Je Zeitalter: Starttag (erster Frühlingstag eines Jahres), Siedler [Heimat, Erwachsene], Kolonien [Siedler je Kolonie],
## Gebäude der Heimat [Typ, Zahl], Gebäude je Kolonie, Vorräte, Verwaltungsstufe, Schiffe, Limit (Spieltag).
const SCEN := {
	0: {"day": 1, "pop": [2, 2], "colonies": [], "build": [["lagerfeuer", 1], ["huette", 1]], "stock": {"holz": 16, "stein": 8, "beeren": 16},
		"admin": 0, "ships": [], "limit": 48, "skip_techs": []},
	1: {"day": 25, "pop": [10, 8], "colonies": [],
		"build": [["lager", 1], ["holzhaus", 1], ["huette", 3], ["schreibstube", 1], ["saegegrube", 1], ["raeucherei", 1],
			["lehmgrube", 1], ["tafelmacherei", 1], ["feld", 3], ["obstgarten", 2]],
		"stock": {"holz": 60, "stein": 30, "bretter": 20, "ziegel": 10, "tontafel": 15, "lehm": 10, "beeren": 30, "fisch": 20, "aepfel": 20},
		"admin": 0, "ships": [], "limit": 110, "skip_techs": ["vorratshaltung"]},
	2: {"day": 61, "pop": [16, 12], "colonies": [],
		"build": [["lager", 1], ["grosslager", 1], ["steinhaus", 1], ["holzhaus", 2], ["huette", 2], ["schreibstube", 1], ["bibliothek", 1],
			["saegegrube", 1], ["raeucherei", 1], ["lehmgrube", 1], ["tafelmacherei", 1], ["muehle", 1], ["baeckerei", 1], ["ziegelei", 1],
			["koehlerei", 1], ["steinbruch", 1], ["mine", 1], ["schmelze", 1], ["schmiede", 1], ["schule", 1], ["feld", 4], ["obstgarten", 2]],
		"stock": {"werkzeug": 20, "eisen": 6, "brot": 20, "kohle": 15, "ziegel": 30, "bretter": 30, "holz": 80, "stein": 50, "tontafel": 20,
			"beeren": 30, "fisch": 30, "weizen": 20},
		"admin": 1, "ships": [], "limit": 190, "skip_techs": []},
	3: {"day": 121, "pop": [18, 14], "colonies": [6],
		"build": [["lager", 1], ["grosslager", 1], ["steinhaus", 3], ["holzhaus", 2], ["schreibstube4", 1], ["bibliothek", 1], ["schule", 1],
			["werft2", 1], ["hafen", 1], ["wachturm", 1], ["waffenschmiede", 1], ["schmiede", 2], ["saegegrube", 1], ["raeucherei", 1],
			["lehmgrube", 1], ["tafelmacherei", 1], ["muehle", 1], ["baeckerei", 2], ["ziegelei", 1], ["koehlerei", 2], ["steinbruch", 1],
			["mine", 1], ["schmelze", 2], ["feld", 5], ["obstgarten", 3]],
		"colony_build": [["huette", 3], ["lager", 1], ["hafen", 1], ["feld", 2]],
		"stock": {"werkzeug": 25, "eisen": 10, "ziegel": 40, "kohle": 25, "bretter": 40, "tontafel": 20, "holz": 100, "stein": 60, "brot": 30,
			"beeren": 30, "fisch": 30, "weizen": 30},
		"admin": 2, "ships": ["boot", "kogge"], "limit": 260, "skip_techs": []},
	4: {"day": 169, "pop": [21, 16], "colonies": [6, 4],
		"build": [["lager", 1], ["grosslager", 2], ["steinhaus", 4], ["holzhaus", 2], ["schreibstube4", 1], ["bibliothek", 1], ["schule", 1],
			["universitaet", 1], ["rundfunk", 1], ["glashuette", 1], ["papiermuehle", 2], ["druckerei", 1],
			["werft2", 1], ["hafen", 1], ["wachturm", 1], ["waffenschmiede", 1], ["schmiede", 2], ["saegegrube", 1], ["raeucherei", 1],
			["lehmgrube", 2], ["muehle", 1], ["baeckerei", 2], ["ziegelei", 1], ["koehlerei", 2], ["steinbruch", 1],
			["mine", 1], ["schmelze", 2], ["feld", 5], ["obstgarten", 3]],
		"colony_build": [["huette", 3], ["lager", 1], ["hafen", 1], ["feld", 2], ["rundfunk", 1]],
		"stock": {"eisen": 30, "kohle": 35, "glas": 20, "papier": 25, "werkzeug": 25, "ziegel": 50, "bretter": 40, "holz": 100, "stein": 60,
			"brot": 30, "beeren": 30, "fisch": 30, "weizen": 30},
		"admin": 4, "ships": ["boot", "kogge"], "limit": 320, "skip_techs": []},
	5: {"day": 229, "pop": [27, 20], "colonies": [7, 5],
		"build": [["lager", 1], ["grosslager", 2], ["mietshaus", 2], ["steinhaus", 3], ["schreibstube4", 1], ["bibliothek", 1], ["schule", 1],
			["universitaet", 1], ["rundfunk", 1], ["glashuette", 1], ["papiermuehle", 2], ["druckerei", 1], ["stahlwerk", 1], ["fabrik", 1],
			["konservenfabrik", 1], ["werft2", 1], ["hafen", 1], ["wachturm", 1], ["schmiede", 2], ["saegegrube", 1], ["raeucherei", 1],
			["lehmgrube", 2], ["muehle", 1], ["baeckerei", 2], ["ziegelei", 1], ["koehlerei", 3], ["steinbruch", 1],
			["mine", 2], ["schmelze", 2], ["feld", 6], ["obstgarten", 3]],
		"colony_build": [["huette", 2], ["holzhaus", 1], ["lager", 1], ["hafen", 1], ["feld", 2], ["rundfunk", 1]],
		"stock": {"stahl": 32, "maschinen": 10, "konserven": 20, "kohle": 40, "glas": 25, "papier": 25, "eisen": 20, "werkzeug": 25,
			"ziegel": 50, "bretter": 40, "holz": 100, "stein": 60, "brot": 40, "beeren": 30, "fisch": 30, "weizen": 30},
		"admin": 5, "ships": ["boot", "kogge"], "limit": 380, "skip_techs": []},
	6: {"day": 289, "pop": [34, 26], "colonies": [8, 6],
		"build": [["lager", 1], ["grosslager", 2], ["wohnblock", 1], ["mietshaus", 3], ["steinhaus", 2], ["schreibstube4", 1], ["bibliothek", 1],
			["schule", 1], ["universitaet", 1], ["rundfunk", 1], ["glashuette", 1], ["papiermuehle", 2], ["druckerei", 1], ["stahlwerk", 1],
			["fabrik", 1], ["konservenfabrik", 1], ["kraftwerk", 2], ["gewaechshaus", 1], ["werft2", 1], ["hafen", 1], ["wachturm", 1],
			["schmiede", 2], ["saegegrube", 1], ["raeucherei", 1], ["lehmgrube", 2], ["muehle", 1], ["baeckerei", 2], ["ziegelei", 1],
			["koehlerei", 3], ["steinbruch", 1], ["mine", 2], ["schmelze", 2], ["feld", 6], ["obstgarten", 3]],
		"colony_build": [["huette", 2], ["holzhaus", 1], ["lager", 1], ["hafen", 1], ["feld", 2], ["rundfunk", 1]],
		"stock": {"glas": 30, "strom": 60, "stahl": 30, "maschinen": 12, "konserven": 20, "kohle": 40, "papier": 25, "eisen": 20,
			"werkzeug": 25, "ziegel": 50, "bretter": 40, "holz": 100, "stein": 60, "brot": 40, "beeren": 30, "fisch": 30, "weizen": 30},
		"admin": 5, "ships": ["boot", "kogge"], "limit": 440, "skip_techs": []},
}

static var age := 0
static var limit_day := 48
static var start_text := ""


## Baut das Startszenario für Zeitalter n auf der Heimatinsel (neues Spiel ist schon geladen).
static func build(main, n: int) -> void:
	age = clampi(n, 0, 6)
	var sc: Dictionary = SCEN[age]
	limit_day = int(sc.limit)
	var w = main.world
	Game.set_speed(0)
	seed(Game.seed_value)
	if age == 0:
		_report_start(w)
		return
	# Forschung: alles aus den früheren Zeitaltern (ohne die ausgelassenen)
	for t in Data.techs:
		if t.begins_with("_"):
			continue
		if Data.age_of_tier(int(Data.techs[t].tier)) < age and not t in sc.skip_techs and not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()
	Exams.passed = age
	while Exams.days.size() < age:
		Exams.days.append(-1.0)
	Game.time_days = float(int(sc.day) - 1) + 0.25
	# Gebäude der Heimat
	if int(sc.admin) >= 1:
		main._place_on(w, "verwaltung")
		StewardLab._finish_all(w)
		for lvl in range(2, int(sc.admin) + 1):
			var o = Admin.office()
			var to := "verwaltung%d" % lvl
			if o == null:
				break
			if w.upgrade_spot(o, to).x < 0:
				StewardLab._move_free(w, o, to)
			var nb = w.upgrade_building(Admin.office())
			if nb != null:
				StewardLab._finish(nb)
	_place_list(w, sc.build)
	_fill_settlers(w, int(sc.pop[0]), int(sc.pop[1]))
	for k in sc.stock:
		w.stock[k] = int(sc.stock[k])
	# Kolonien
	for i in sc.colonies.size():
		var m: Dictionary = Sea.make_island(Sea.islands.size())
		Sea.islands.append(m)
		var cw = Sea.create_world_node(int(m.id))
		cw.build_colony(m)
		m.state = "settled"
		_place_list(cw, sc.get("colony_build", []))
		_fill_settlers(cw, int(sc.colonies[i]), maxi(2, int(sc.colonies[i]) - 2))
		for k in {"holz": 40, "stein": 20, "bretter": 10, "beeren": 30, "fisch": 20}:
			cw.stock[k] = {"holz": 40, "stein": 20, "bretter": 10, "beeren": 30, "fisch": 20}[k]
	for t in sc.ships:
		Sea._new_ship(t, 0)
	if int(sc.admin) >= 1:
		var best = null
		for s in w.settlers:
			if s.is_adult() and (best == null or s.skill_factor("wissen") > best.skill_factor("wissen")):
				best = s
		if best != null:
			best.set_job("verwalter")
	w.assign_homes()
	for cw in Sea.worlds.values():
		if cw != w:
			cw.assign_homes()
	_report_start(w)


static func _place_list(w, list: Array) -> void:
	for e in list:
		var type: String = e[0]
		if not Data.buildings.has(type):
			continue
		var have := 0
		for b in w.buildings:
			if b.type == type:
				have += 1
		for i in range(have, int(e[1])):
			if not StewardLab._place(w, type):
				print("AGETEST: kein Platz für ", type)
	StewardLab._finish_all(w)


static func _fill_settlers(w, total: int, adults: int) -> void:
	var c: Vector2i = w.center
	var i: int = w.settlers.size()
	var have_adults: int = w.settlers.filter(func(s): return s.is_adult()).size()
	while w.settlers.size() < total:
		var kid := have_adults >= adults
		var s = w.spawn_settler({"name": "S%d_%d" % [int(w.island_id), i], "sex": "f" if i % 2 else "m",
			"age": (1.0 + float(i % 3) * 0.6) if kid else (4.0 + float((i * 7) % 14)), "max_age": 40.0 + float(i % 10),
			"x": c.x + (i % 7) - 3, "y": c.y + (i % 5) - 2, "skills": {}, "mind": {"traits": {}, "talents": {}}})
		s.hunger = 80.0
		s.birth_cooldown_until = Game.time_days + float(i % 5) * 0.4  # nicht alle Paare am ersten Tag
		if not kid:
			have_adults += 1
		i += 1


## Startdaten (josh: Siedlerzahl, Ressourcen, Gebäude, vergangene Zeit).
static func _report_start(w) -> void:
	var pops := []
	for m in Sea.islands:
		var ww = Sea.worlds.get(int(m.id))
		if ww != null:
			pops.append("%s %d (%d Erw.)" % [m.name, ww.settlers.size(), ww.settlers.filter(func(s): return s.is_adult()).size()])
	var bl := {}
	for b in w.buildings:
		bl[b.type] = int(bl.get(b.type, 0)) + 1
	var st := []
	for k in w.stock:
		if int(w.stock[k]) > 0:
			st.append("%s %d" % [k, int(w.stock[k])])
	start_text = "START Zeitalter %d %s | Tag %d (Jahr %d, %s) | Siedler %s | Forschungen %d | Verwaltung Stufe %d | Gebäude %s | Vorräte %s | Schiffe %s | Arbeitstag %s" % [
		age, Data.age_name(age), Game.day(), Seasons.year(), Seasons.short_text(), ", ".join(pops), Game.research.done.size(), Admin.office_level(),
		bl, ", ".join(st), Sea.ships.map(func(sh): return sh.type), "aus" if WorkDay.off else "an"]
	print(start_text)
