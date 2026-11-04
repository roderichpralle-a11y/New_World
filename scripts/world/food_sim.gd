class_name FoodSim
extends RefCounted
## Prüflauf zur Essens- und Handwerk-Matrix (josh 2026-10-31, /mnt/project-files/konzept/essen_matrix/):
## Stufe 5 (Mittelalter), 21 Erwachsene mit festen Berufen, 5 Essen (Brot, Fleisch, Milch, Eier, Äpfel), 10 Forscher.
## Kein Verwalter, kein Bot: die Siedler arbeiten nur in ihrem Beruf. Ein Spieljahr ab Frühlingsanfang, Bericht je Tag.
## Aufruf: godot --headless --fixed-fps 60 -- --autotest=4000 --scale=10 --seed=11 --foodsim=1

static var JOBS := {"forscher": 10, "handwerker": 5, "steinmetz": 3, "holzfaeller": 4, "bauer": 4, "koch": 1}  # Plan 2 (plan_insel.py, mit Tragen)
static var BUILD := [["lager", 2], ["grosslager", 2], ["holzhaus", 7], ["schreibstube4", 1], ["bibliothek", 2], ["muehle", 1], ["baeckerei", 1],
	["schweinestall", 1], ["kuhstall", 1], ["huehnerhof", 2], ["obstgarten", 2], ["feld", 6], ["saegegrube", 1],
	["tafelmacherei", 1], ["lehmgrube", 1], ["ziegelei", 1], ["koehlerei", 1], ["mine", 1], ["schmelze", 1], ["schmiede", 1]]
static var TOTAL := 27
# Gleichgewicht mit 3 Forschern (josh 2026-11-01, plan_insel.py FORSCHER=3): ganze Leute je Beruf
const JOBS3 := {"forscher": 3, "handwerker": 2, "steinmetz": 1, "holzfaeller": 1, "bauer": 2, "koch": 1}
const BUILD3 := [["lager", 2], ["grosslager", 1], ["holzhaus", 3], ["bibliothek", 1], ["muehle", 1], ["baeckerei", 1],
	["schweinestall", 1], ["kuhstall", 1], ["huehnerhof", 1], ["obstgarten", 2], ["feld", 3], ["saegegrube", 1],
	["tafelmacherei", 1], ["lehmgrube", 1], ["ziegelei", 1], ["koehlerei", 1], ["mine", 1], ["schmelze", 1], ["schmiede", 1]]
const STOCK := {"holz": 60, "bretter": 30, "stein": 30, "ziegel": 20, "tontafel": 30, "werkzeug": 20, "eisen": 10, "kohle": 10,
	"weizen": 60, "brot": 20, "aepfel": 20, "eier": 20, "milch": 10, "fleisch": 10}
const FOODS := ["brot", "fleisch", "milch", "eier", "aepfel", "weizen", "beeren", "fisch", "pilze"]
const GOODS := ["holz", "bretter", "stein", "lehm", "ziegel", "tontafel", "kohle", "erz", "eisen", "werkzeug"]

static var start_day := 0.0
static var start_points := 0.0
static var done_at_start := 0
static var log_lines: Array = []
static var _busy := {}   # Beruf -> [Arbeitszeit, Zeit insgesamt] (Proben)
static var _died := 0
static var _acts := {}  # Beruf -> {Tätigkeit: Proben}


static var admin := false


static func build(main, with_admin := false, plan := "") -> void:
	admin = with_admin
	if plan == "3":
		JOBS = JOBS3
		BUILD = BUILD3
		TOTAL = 10
	var w = main.world
	Game.set_speed(0)
	seed(Game.seed_value)
	for t in Data.techs:
		if t.begins_with("_"):
			continue
		if Data.age_of_tier(int(Data.techs[t].tier)) < 2 and not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()
	Exams.passed = 2
	while Exams.days.size() < 2:
		Exams.days.append(-1.0)
	Game.time_days = 12.0 * 5.0 + 0.25  # Frühlingsanfang Jahr 6
	# Mit einem freien Rand um jedes Gebäude (main._place_on), sonst sperren dichte Reihen die Wege zu
	# Bäumen, Werkstätten und Forschung (erster Lauf: viele Ziele unerreichbar)
	for e in BUILD:
		for k in int(e[1]):
			if not main._place_on(w, str(e[0])):
				print("FOODSIM kein Platz für ", e[0])
	StewardLab._finish_all(w)
	var i := 0
	AgeTest._fill_settlers(w, TOTAL, TOTAL)
	for s in w.settlers:
		s.birth_cooldown_until = 99999.0  # gleich viele Esser
		s.max_age = 200.0
		s.mind.mood = 75.0
		for sk in ["holz", "stein", "nahrung", "bauen", "handwerk", "wissen", "jagd"]:
			s.skills[sk] = 3.0  # Fähigkeit Stufe 3 wie in der Rechnung
	var order: Array = []
	for j in JOBS:
		for k in JOBS[j]:
			order.append(j)
	for s in w.settlers:
		if i < order.size():
			s.set_job(order[i])
		i += 1
	for k in STOCK:
		w.stock[k] = int(STOCK[k])
	w.assign_homes()
	if admin:
		# Mit Verwalter (josh 2026-11-01): Verwaltung Stufe 3, alle Befugnisse selbst, nur die Lager-Obergrenzen als
		# Vorschlag, den der "Spieler" (dieser Lauf) annimmt
		if not "baumeisterkunst" in Game.research.done:
			Game.research.done.append("baumeisterkunst")  # Stellenplan
			Game.refresh_effects()
		main._place_on(w, "verwaltung")
		StewardLab._finish_all(w)
		for lvl in range(2, 4):
			var o = Admin.office()
			if o == null:
				break
			if w.upgrade_spot(o, "verwaltung%d" % lvl).x < 0:
				StewardLab._move_free(w, o, "verwaltung%d" % lvl)
			var nb = w.upgrade_building(Admin.office())
			if nb != null:
				StewardLab._finish(nb)
		AgeTest._fill_settlers(w, TOTAL + 1, TOTAL + 1)
		var v = w.settlers[w.settlers.size() - 1]
		v.set_job("verwalter")
		for sk in ["holz", "stein", "nahrung", "bauen", "handwerk", "wissen", "jagd"]:
			v.skills[sk] = 3.0
		v.birth_cooldown_until = 99999.0
		v.max_age = 200.0
		for e in Powers.LIST:
			Powers.mode[e.id] = Powers.SELBST
		Powers.mode["obergrenzen"] = Powers.FRAGEN
		w.assign_homes()
		print("FOODSIM Verwaltung Stufe %d, Befugnisse %s" % [Admin.level(), Powers.LIST.filter(func(e): return Powers.on(e.id)).map(func(e): return e.id)])
	start_day = Game.time_days
	done_at_start = Game.research.done.size()
	_next_research()
	start_points = _points()
	print("FOODSIM START Tag %d %s | Siedler %d | Berufe %s | Gebäude %d | Forschungen %d | Arbeitstag %s" % [Game.day(), Seasons.short_text(),
		w.settlers.size(), _jobs(w), w.buildings.size(), done_at_start, "an" if not WorkDay.off else "aus"])


static func _jobs(w) -> Dictionary:
	var d := {}
	for s in w.settlers:
		d[s.job] = int(d.get(s.job, 0)) + 1
	return d


static func _points() -> float:
	var p := 0.0
	for t in Game.research.done:
		p += Game.tech_points(t)
	p += Game.tech_progress(Game.research.current) if Game.research.current != "" else 0.0
	return p


## Nächste Forschung des Mittelalters, die bezahlbar ist (Gold und Felle gibt es auf dieser Insel nicht).
static func _next_research() -> void:
	if Game.research.current != "":
		return
	var cands: Array = []
	for t in Data.techs:
		if t.begins_with("_") or Game.tech_state(t) != "available":
			continue
		cands.append(t)
	cands.sort_custom(func(a, b): return int(Data.techs[a].tier) < int(Data.techs[b].tier))
	for t in cands:
		if Game.start_research(t) == "":
			return


static func tick(main) -> void:
	var w = main.world
	if admin:
		# Der Spieler nimmt den Vorschlag für Obergrenzen an, sobald er kommt
		for i in range(Powers.proposals.size() - 1, -1, -1):
			if str(Powers.proposals[i].power) == "obergrenzen":
				print("FOODSIM Vorschlag angenommen: ", Powers.proposals[i].text)
				Powers.answer(i, true)
		_next_research()  # der Spieler startet die nächste Forschung (Stufe 2 hat „Forschung weiterführen“ noch nicht)
		return
	_next_research()
	for s in w.settlers:
		if not s.is_adult():
			continue
		var e: Array = _busy.get(s.job, [0, 0])
		e[1] += 1
		var a := str(s.activity)
		if a != "" and not a.begins_with("Wartet") and not a.begins_with("Schläft") and not a.begins_with("Freizeit") \
				and not a.begins_with("Isst") and not a.begins_with("Sucht") and a != "Ruht":
			e[0] += 1
		_busy[s.job] = e
		var h: Dictionary = _acts.get(s.job, {})
		var key := a.split(" (")[0].split(":")[0]
		h[key] = int(h.get(key, 0)) + 1
		_acts[s.job] = h


static func day_report(main) -> void:
	var w = main.world
	var fs := []
	var sat := 0.0
	for g in FOODS:
		var n := Game.amount(g, w)
		sat += float(n) * Data.food_satiety(g)
		if n > 0:
			fs.append("%s %d" % [g, n])
	var gs := []
	for g in GOODS:
		gs.append("%s %d" % [g, Game.amount(g, w)])
	var hungry: int = w.settlers.filter(func(s): return s.hunger < 30.0).size()
	var mood := 0.0
	for s in w.settlers:
		mood += float(s.mind.mood)
	mood /= maxf(1.0, w.settlers.size())
	var lims := []
	for g in w.store_limits:
		lims.append("%s %d" % [g, int(w.store_limits[g])])
	var line := "FOODSIM Tag %d %s | Siedler %d, hungrig %d, Laune %d | Essen-Vorrat %d Sättigung = %.1f Tage (%s) | Waren %s | Forschung +%d Punkte, %d fertig, jetzt %s" % [
		Game.day(), Seasons.short_text(), w.settlers.size(), hungry, roundi(mood), roundi(sat),
		sat / maxf(1.0, w.settlers.size() * float(Data.bal("hunger_per_day"))), ", ".join(fs), ", ".join(gs),
		roundi(_points() - start_points), Game.research.done.size() - done_at_start, Game.research.current]
	var bl := []
	for b in w.buildings:
		if b.complete and not b.prod_def().is_empty() and b.prod_blocker() != "":
			bl.append("%s: %s" % [b.type, b.prod_blocker()])
	line += " | Lager %d/%d | Werkstatt-Sperren %s | Berufe %s | Obergrenzen %s" % [Game.used_volume(w), Game.storage_volume(w), bl, _jobs(w), ", ".join(lims)]
	print(line)
	log_lines.append(line)


static func finish(main) -> void:
	var w = main.world
	var busy := []
	for j in _busy:
		busy.append("%s %d %%" % [j, roundi(100.0 * float(_busy[j][0]) / maxf(1.0, float(_busy[j][1])))])
	var used := []
	for g in Writing.used:
		used.append("%s %d" % [g, roundi(float(Writing.used[g]))])
	print("FOODSIM ENDE nach %.1f Tagen | Siedler %d | Forschungspunkte %d, Forschungen fertig %d | Schreibwaren verbraucht %s | beschäftigt (ganzer Tag): %s" % [
		Game.time_days - start_day, w.settlers.size(), roundi(_points() - start_points), Game.research.done.size() - done_at_start,
		", ".join(used), ", ".join(busy)])
	print("FOODSIM HERGESTELLT ", Admin.produced)
	var un := []
	for b in w._unreachable:
		if is_instance_valid(b) and float(w._unreachable[b]) > Game.time_days - 1.0:
			un.append(str(b.type) if "type" in b else "?")
	print("FOODSIM UNERREICHBAR ", un)
	var homeless: int = w.settlers.filter(func(s): return s.home_id < 0).size()
	print("FOODSIM OHNE HAUS ", homeless, " | Häuser ", w.buildings.filter(func(b): return b.def.has("housing")).map(func(b): return "%s %s/%d" % [b.type, str(b.complete), int(b.def.housing)]))
	for b in w.buildings:
		if not b.prod_def().is_empty():
			print("FOODSIM WERKSTATT %s Plätze %d frei %d Leute %s" % [b.type, b.slots(), b.free_slots(), b.occupants])
	for j in _acts:
		var tot := 0
		for k in _acts[j]:
			tot += int(_acts[j][k])
		var ks: Array = _acts[j].keys()
		ks.sort_custom(func(x, y): return int(_acts[j][x]) > int(_acts[j][y]))
		var parts := []
		for k in ks.slice(0, 8):
			parts.append("%s %d %%" % [k, roundi(100.0 * float(_acts[j][k]) / maxf(1.0, float(tot)))])
		print("FOODSIM TÄTIGKEIT %s: %s" % [j, ", ".join(parts)])
