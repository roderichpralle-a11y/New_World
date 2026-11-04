class_name StewardLab
extends RefCounted
## Versuchsinsel für den Verwalter (josh 2026-10-30): --vlab=1 baut eine Insel mit etwa 100 Siedlern, allen
## Forschungen bis Stufe 8, Werkstätten, Feldern, Häusern und einer Verwaltung (Stufe 4, alle Befugnisse auf
## Selbst). Die Berufe sind wie nach langer Verwalter-Arbeit bunt verteilt. Danach läuft das Spiel, und jeden
## Spieltag steht eine Zeile „LAB …“ im Log: Bedarf, was der Verwalter tat, Ergebnis.
## Aufruf: godot --headless --fixed-fps 60 -- --autotest=<sek> --scale=10 --seed=11 --vlab=1 [--labdays=12]
## --vlab=start: Berufe zufällig (Standard), --vlab=free: alle frei, --vlab=bad: alle in Rohstoffberufen.

const BUILD := [
	["grosslager", 3], ["schreibstube", 1], ["bibliothek", 1], ["universitaet", 1], ["schule", 1], ["rundfunk", 1],
	["muehle", 2], ["baeckerei", 3], ["raeucherei", 2], ["huehnerhof", 2], ["schweinestall", 1], ["kuhstall", 1],
	["saegegrube", 2], ["lehmgrube", 2], ["ziegelei", 1], ["steinbruch", 1], ["koehlerei", 2], ["mine", 1],
	["schmelze", 1], ["schmiede", 1], ["tafelmacherei", 1], ["glashuette", 1], ["papiermuehle", 1], ["druckerei", 1],
]
## --vlab=voll: so gebaut, wie es der Verwalter in den Engpässen empfiehlt (mehr Küchen, Kohle, Eisen, Bretter)
const MORE := [["muehle", 3], ["baeckerei", 2], ["koehlerei", 2], ["schmelze", 1], ["mine", 1], ["saegegrube", 2], ["raeucherei", 1]]
const HOUSES := [["steinhaus", 12], ["holzhaus", 7]]  # 72 + 28 = 100 Plätze
const FIELDS := 40
const ORCHARDS := 4
const START_JOBS := ["holzfaeller", "holzfaeller", "sammler", "fischer", "fischer", "bauer", "bauer", "steinmetz",
	"handwerker", "handwerker", "koch", "forscher", "forscher", "jaeger", "frei"]

static var _last_day := -1
static var _deaths := 0
static var _births := 0
static var _start_pop := 0
static var _first := {}
static var _log_n := 0
static var _made := {}


static func run(main, mode: String) -> void:
	var w = main.world
	Game.set_speed(0)
	seed(11)
	for t in Data.techs:
		if t.begins_with("_"):
			continue
		if int(Data.techs[t].get("tier", 99)) <= 8 and not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()
	# Prüfungen bis zum Zeitalter der Stufe 9 bestanden (sonst ist keine Forschung wählbar)
	Exams.passed = maxi(Exams.passed, Data.age_of_tier(9))
	while Exams.days.size() < Exams.passed:
		Exams.days.append(-1.0)
	# Verwaltung, Ausbau bis Stufe 4 (Inselamt)
	main._place_on(w, "verwaltung")
	_finish_all(w)
	for lvl in [2, 3, 4]:
		var o = Admin.office()
		var to := "verwaltung%d" % lvl
		if w.upgrade_spot(o, to).x < 0:
			_move_free(w, o, to)
		var nb = w.upgrade_building(Admin.office())
		if nb != null:
			_finish(nb)
	var placed := {}
	for e in HOUSES + BUILD + (MORE if mode.begins_with("voll") else []) + [["obstgarten", ORCHARDS], ["feld", FIELDS]]:
		for i in int(e[1]):
			if _place(w, e[0]):
				placed[e[0]] = int(placed.get(e[0], 0)) + 1
	_finish_all(w)
	print("LAB gebaut: ", placed)
	# Siedler: auf 100 auffüllen (etwa ein Viertel Kinder)
	var c: Vector2i = w.center
	var i := 0
	while w.settlers.size() < 100:
		var kid := i % 4 == 3
		var s = w.spawn_settler({"name": "S%d" % i, "sex": "f" if i % 2 else "m", "age": (1.0 + float(i % 3) * 0.6) if kid else (4.0 + float((i * 7) % 20)),
			"max_age": 40.0 + float(i % 10), "x": c.x + (i % 7) - 3, "y": c.y + (i % 5) - 2, "skills": {}, "mind": {"traits": {}, "talents": {}}})
		s.hunger = 80.0
		i += 1
	var adults: Array = w.settlers.filter(func(s): return s.is_adult())
	var mgr_set := false
	for k in adults.size():
		var s = adults[k]
		if not mgr_set:
			s.set_job("verwalter")
			mgr_set = true
			continue
		var j: String = "frei" if mode == "free" else (["holzfaeller", "sammler", "steinmetz", "fischer"][k % 4] if mode == "bad" else START_JOBS[k % START_JOBS.size()])
		if Data.jobs.has(j):
			JobDesk.assign(s, j, "verwalter")
	w.assign_homes()
	# Vorräte wie auf einer laufenden Insel
	var st := {"beeren": 120, "fisch": 150, "brot": 120, "raeucherfisch": 80, "weizen": 80, "mehl": 20, "eier": 40,
		"holz": 300, "stein": 150, "bretter": 80, "ziegel": 60, "lehm": 30, "kohle": 30, "erz": 20, "eisen": 10,
		"werkzeug": 20, "tontafel": 20, "papier": 10, "glas": 6}
	for k in st:
		w.stock[k] = int(st[k])
	# Alle Befugnisse auf Selbst
	for e in Powers.LIST:
		Powers.set_mode(str(e.id), Powers.SELBST)
	Steward._moved = {}
	_last_day = -1
	_log_n = Admin.log_entries.size()
	_deaths = int(Game.stats.get("deaths", 0))
	_births = 0
	_start_pop = w.settlers.size()
	print("LAB Versorgungsplan: ", PlanReport.supply_plan(w))
	var trees: int = w.nodes.filter(func(n): return n.type == "baum").size()
	print("LAB Natur: Bäume %d, Büsche %d, Fischgründe %d, Tiere %d" % [trees, w.nodes.filter(func(n): return n.type == "busch").size(), w.nodes.filter(func(n): return n.type == "fischgrund").size(), w.animals.size()])
	print("LAB Start: %d Siedler (%d Erwachsene), Verwaltung Stufe %d, Forschung %s" % [w.settlers.size(), adults.size(), Admin.level(), Game.research.current])
	_report(w, true)
	main.get_tree().process_frame.connect(func(): _tick(w))
	Game.set_speed(1)
	Engine.time_scale = float(main._args.get("scale", "10"))


static func _tick(w) -> void:
	if not is_instance_valid(w):
		return
	var d := Game.day()
	if d != _last_day and Game.clock_text() >= "12:00":
		_last_day = d
		_report(w, false)


## Eine Zeile je Tag: Bedarf (Essen/Wärme 3 Tage), Vorräte, Berufe mit Leerlauf, Freie, Verwalter heute, Engpässe.
static func _report(w, first: bool) -> void:
	var adults: Array = w.settlers.filter(func(s): return s.is_adult())
	var kids: int = w.settlers.size() - adults.size()
	var si := Steward.secure_info(w)
	var jobs := {}
	var idle := {}
	for s in adults:
		jobs[s.job] = int(jobs.get(s.job, 0)) + 1
		var sh: Array = s.busy_shares()
		if not sh.is_empty():
			idle[s.job] = float(idle.get(s.job, 0.0)) + float(sh[2])
	var jt := []
	var keys := jobs.keys()
	keys.sort()
	for j in keys:
		var n: int = jobs[j]
		jt.append("%s %d%s" % [j, n, (" (%d%% leer)" % roundi(float(idle.get(j, 0.0)) / n)) if idle.has(j) else ""])
	var goods := []
	for g in ["holz", "stein", "bretter", "ziegel", "lehm", "kohle", "eisen", "werkzeug", "tontafel", "papier", "glas", "buecher", "zeitungen"]:
		goods.append("%s %d" % [g, Game.amount(g, w)])
	var food := {}
	for f in Data.food_ids():
		if Game.amount(f, w) > 0:
			food[f] = Game.amount(f, w)
	var hungry: int = w.settlers.filter(func(s): return s.hunger < 20.0).size()
	var sick: int = w.settlers.filter(func(s): return s.mind.sick != "").size()
	var mood := 0.0
	for s in w.settlers:
		mood += float(s.mind.mood)
	mood /= maxf(1.0, w.settlers.size())
	var hs := []
	for k in range(2, 4):
		hs.append("H%d %s" % [k, "ok" if HouseNeeds.level_ok(w, k) else "NEIN"])
	var dead: int = int(Game.stats.get("deaths", 0)) - _deaths
	var miss := HouseNeeds.missing_text(w, 3)
	print("LAB Tag %d %s | %s | Siedler %d (E %d, K %d) geboren %d tot %d, hungrig %d, krank %d, Laune %d | %s" % [Game.day(), Seasons.season_name(Seasons.season()),
		Game.clock_text(), w.settlers.size(), adults.size(), kids, w.settlers.size() - _start_pop + dead, dead, hungry, sick, roundi(mood), " ".join(hs)])
	print("LAB   Essen: braucht %d/3T, Vorrat %d (%s), Leute %d/%d | Brennstoff: braucht %d/3T, Vorrat %d, Holzf. %d/%d" % [
		int(si.food[0]), int(si.food[1]), Game.food_days(w), int(si.food[3]), int(si.food[2]), int(si.fuel[0]), int(si.fuel[1]), int(si.fuel[3]), int(si.fuel[2])])
	print("LAB   Nahrung: ", food, " | Häuser fehlt: ", miss)
	print("LAB   Waren: ", ", ".join(goods))
	var made := {}
	for y in Admin.produced:
		var pi: Dictionary = Admin.produced[y].get(str(w.island_id), {})
		for r in pi:
			made[r] = int(made.get(r, 0)) + int(pi[r])
	var md := []
	for r in made:
		if int(made[r]) - int(_made.get(r, 0)) > 0:
			md.append("%s %d" % [r, int(made[r]) - int(_made.get(r, 0))])
	_made = made
	print("LAB   erzeugt seit letztem Bericht: ", ", ".join(md))
	print("LAB   Berufe: ", ", ".join(jt))
	var tg := StaffPlan.targets(w)
	print("LAB   Soll: ", ", ".join(tg.keys().map(func(j): return "%s %d" % [j, int(tg[j].n)])))
	var ws := []
	for b in w.buildings:
		if b.complete and b.def.has("production") and not b.def.has("farm") and not b.def.get("ships", false):
			ws.append("%s%s%s" % [b.type, "" if StaffPlan._active(w, b, StaffPlan.stock_targets(w)) else "-", "" if StaffPlan._has_inputs(w, b) else "!"])
	print("LAB   Werkstätten (- ruht, ! keine Zutaten): ", " ".join(ws))
	var to := Planner.tech_order()
	print("LAB   Forschung: next=%s, nächste wählbar=%s (Kosten %s) | " % [str(Game.research.get("next", "")), to[0] if not to.is_empty() else "-", Data.techs[to[0]].get("cost", {}) if not to.is_empty() else {}], "%s %d%%" % [Game.research.current, roundi(100.0 * Game.tech_progress(Game.research.current) / maxf(1.0, Game.tech_points(Game.research.current))) if Game.research.current != "" else 0])
	if not first:
		var tot := Powers.tally(false)
		var diff := {}
		for k in tot:
			if int(tot[k]) != int(_first.get(k, 0)):
				diff[k] = int(tot[k]) - int(_first.get(k, 0))
		_first = tot
		print("LAB   Verwalter seit gestern: ", diff)
		for e in Admin.log_entries.slice(mini(_log_n, Admin.log_entries.size())):
			print("LAB     - ", str(e[2]))
		_log_n = Admin.log_entries.size()
		var bl: Dictionary = Steward.blocks.get(int(w.island_id), {})
		if not bl.is_empty():
			print("LAB   Engpässe: ", " | ".join(bl.values()))
		var needs := Steward.needs(w)
		print("LAB   offener Bedarf: ", needs.map(func(n): return "%s (%s)" % [n.job, n.why]))


## Wie ein Spieler, der eng baut: Gitter mit einer Zelle Abstand (Gebäude 3x2 auf 4x3, Felder dicht), Bäume
## unter der Grundfläche werden gefällt.
static func _place(w, type: String) -> bool:
	var sz: Array = Data.buildings[type].size
	var step := Vector2i(int(sz[0]) + 1, int(sz[1]) + 1) if int(sz[0]) > 1 else Vector2i(1, 1)
	for rad in range(2, 34):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var c: Vector2i = w.center + Vector2i(dx, dy)
				if step.x > 1 and (posmod(c.x, step.x) != 0 or posmod(c.y, step.y) != 0):
					continue
				var nodes := []
				var ok := true
				for y in int(sz[1]):
					for x in int(sz[0]):
						var cc := c + Vector2i(x, y)
						if w.node_at.has(cc):
							var n = w.node_at[cc]
							if n.type != "baum":
								ok = false
							nodes.append(n)
				if not ok:
					continue
				for n in nodes:
					w.remove_node(n)
				if w.can_place(type, c):
					w.place_building(type, c, true)
					return true
	return false


static func _finish(b) -> void:
	for res in b.def.cost:
		b.delivered[res] = int(b.def.cost[res])
	b.add_work(float(b.def.work) + 1.0)


static func _finish_all(w) -> void:
	for b in w.buildings:
		if not b.complete:
			_finish(b)


static func _move_free(w, ob, to: String) -> void:
	for rad in range(2, 30):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var c: Vector2i = w.center + Vector2i(dx, dy)
				if w.can_place(ob.type, c, ob) and w.move_building(ob, c) and w.upgrade_spot(ob, to).x >= 0:
					return
