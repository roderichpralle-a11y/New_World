extends "res://scripts/test/bot.gd"
## Plan-Bot (josh 2026-10-31): spielt nach dem Useraktionsplan (/mnt/project-files/konzept/useraktionsplan/useraktionsplan.md)
## durch alle Zeitalter. Baut auf dem Spiel-Bot v2 auf (Steinzeit und Antike von Hand) und ergänzt:
## Pflicht- und Wahllisten der Forschung je Zeitalter, Bauliste je Zeitalter, Prüfungsgebäude, Verwaltung mit
## Befugnissen und Antworten auf Vorschläge, Mindestvorräte, Werkstätten nach Zielmengen, Schiffe und Kolonien.
## Eine Instanz je Insel: die Heimat (island_id 0) forscht und baut alles, Kolonien nur das Nötigste.

const PLAN := {
	0: {"must": ["schrift", "steinwerkzeuge", "gartenbau", "holzbearbeitung", "zimmerei", "flechtkoerbe", "raeuchern", "toepferei"],
		"opt": ["vorratshaltung", "steinbruch", "muehlenbau"],
		"build": []},
	1: {"must": ["backkunst", "koehlerei", "maurerei", "gelehrsamkeit", "bergbau", "eisenverhuettung", "schmiedekunst", "handkarren"],
		"opt": ["unterricht", "heilkunde", "bewaesserung", "tierhaltung", "wegebau", "deichbau"],
		"build": [["muehle", 1], ["baeckerei", 1], ["ziegelei", 1], ["steinhaus", 1], ["grosslager", 1], ["verwaltung", 1], ["bibliothek", 1],
			["koehlerei", 1], ["steinbruch", 1], ["mine", 1], ["schmelze", 1], ["schmiede", 1], ["schule", 1]]},
	2: {"must": ["eisenwerkzeuge", "baumeisterkunst", "waffenkunde", "schiffsbau", "navigation", "eisenpflug", "jagdkunst", "befestigung"],
		"opt": ["pelzkleidung", "seehandel"],
		"build": [["schmiede", 2], ["schmelze", 2], ["koehlerei", 2], ["werft", 1], ["anlegesteg", 1], ["wachturm", 1], ["waffenschmiede", 1]]},
	3: {"must": ["glasmacherei", "papier", "uhrwerk", "astronomie", "buchdruck", "hochschule"],
		"opt": ["anatomie", "fruchtwechsel"],
		"build": [["glashuette", 1], ["lehmgrube", 2], ["papiermuehle", 2], ["druckerei", 1], ["universitaet", 1], ["rundfunk", 1]]},
	4: {"must": ["dampfmaschine", "stahl", "konservendose", "mietshaus", "fabrik", "eisenbahn"],
		"opt": ["kunstduenger"],
		"build": [["stahlwerk", 1], ["konservenfabrik", 1], ["mietshaus", 1], ["fabrik", 1], ["koehlerei", 3], ["mine", 2]]},
	5: {"must": ["elektrizitaet", "kuehltechnik", "telegraf", "verbrennungsmotor", "wohnblock", "gewaechshaus"],
		"opt": ["impfung", "motorschiffe"],
		"build": [["kraftwerk", 1], ["gewaechshaus", 1], ["wohnblock", 1], ["mietshaus", 3]]},
	6: {"must": ["computer", "internet", "automatisierung", "solarenergie"],
		"opt": ["logistik"],
		"build": [["elektronikwerk", 2], ["labor", 1], ["solarpark", 1]]},
}
## Mindestvorräte (Abschnitt 5): Ware -> [ab Zeitalter, Menge]
const MIN_STOCK := {"bretter": [0, 20], "lehm": [0, 10], "tontafel": [1, 30], "ziegel": [1, 30], "kohle": [1, 20], "brot": [1, 25],
	"werkzeug": [1, 13], "eisen": [2, 20], "papier": [3, 25], "glas": [3, 25], "stahl": [4, 25], "maschinen": [4, 8], "konserven": [4, 25],
	"strom": [5, 40], "elektronik": [6, 38]}
## Werkstätten, die der Bot v2 schon selbst regelt (Nahrungskette und Rohstoffe der ersten Zeitalter)
const OWN := ["saegegrube", "lehmgrube", "tafelmacherei", "ziegelei", "raeucherei", "muehle", "baeckerei", "koehlerei", "mine",
	"schmelze", "schmiede", "huehnerhof", "steinbruch"]
const COLONY_TYPES := ["huette", "holzhaus", "lager", "feld", "obstgarten", "raeucherei", "saegegrube", "rundfunk"]

var island_id := 0
var colonies := {}  # Insel-ID -> Plan-Bot der Kolonie
var _powers_set := -1
var _ship_note := ""
var _goal := {}  # Ware -> Zielmenge (Bericht)
var _last_exam := -1
var _mins_next := 0.0
var _round_next := 0.0  # Entscheidungsrunde alle 0,25 Spieltage (Abschnitt 1)
var _build_left := 0


func setup_island(m, id: int) -> void:
	main = m
	island_id = id
	w = Sea.worlds.get(id)


func _home() -> bool:
	return island_id == 0


func tick(_elapsed: float) -> void:
	if Game.is_over:
		return
	w = Sea.worlds.get(island_id, Game.world if _home() else null)
	if w == null or not is_instance_valid(w) or w.settlers.is_empty():
		return
	if not _home():
		if Game.time_days >= _round_next:
			_round_next = Game.time_days + 0.25
			_build()
		_jobs()
		_store_limits()
		return
	_skip_tutorial()
	_year_line()
	_winter_watch()
	_exam_watch()
	_powers()
	_answer()
	_research()
	_quests()
	if Game.time_days >= _round_next:
		_round_next = Game.time_days + 0.25
		_build_left = 2 if w.settlers.size() >= 20 else 1
	if _build_left > 0:
		var n_sites: int = _sites().size()
		_admin_upgrade()
		_build()
		if _sites().size() > n_sites:
			_build_left -= 1
	_jobs()
	_store_limits()
	_min_stocks()
	_ships()
	_watch_events()
	for m in Sea.settled_islands():
		var id := int(m.id)
		if id != 0 and not colonies.has(id):
			var b = load("res://scripts/test/plan_bot.gd").new()
			b.setup_island(main, id)
			colonies[id] = b
			print("BOT: Kolonie %s wird mitgespielt" % m.name)
	for id in colonies:
		colonies[id].tick(0.0)


# ================================================================== Forschung
func _priority() -> Array:
	var list := []
	var q: Dictionary = Quests.active
	if not q.is_empty() and str(q.get("check", {}).get("type", "")) == "tech":
		list.append(str(q.check.what))
	var age: int = Game.current_age()
	for a in range(0, mini(age, 6) + 1):
		list.append_array(PLAN[a].must)
	list.append_array(PLAN[mini(age, 6)].opt)
	for a in range(0, mini(age, 6)):
		list.append_array(PLAN[a].opt)
	for t in Data.sorted_tech_ids():
		if not t in list:
			list.append(t)
	return list


# ================================================================== Verwaltung
## Befugnisse wie im Plan (Abschnitt 4): fast alles Selbst, Überstunden und Forschung auf Fragen.
func _powers() -> void:
	var lvl: int = Admin.level()
	if lvl == _powers_set:
		return
	_powers_set = lvl
	for e in Powers.LIST:
		var id := str(e.id)
		if not Powers.unlocked(id) or id == "ki":
			continue
		if Powers.mode_of(id) != Powers.SELBST:
			Powers.set_mode(id, Powers.SELBST)
			print("BOT: Befugnis %s -> Selbst" % id)
	# Verwalter einsetzen (der mit dem meisten Wissen)
	if Admin.office() != null and Admin.manager() == null:
		var best = null
		for s in _adults():
			if s.job != "forscher" and (best == null or s.skill_factor("wissen") > best.skill_factor("wissen")):
				best = s
		if best != null:
			_set_job(best, "verwalter")


## Vorschläge gibt es seit josh 2026-11-07 nicht mehr.
func _answer() -> void:
	pass


## Ausbau der Verwaltung, sobald Forschung und Material da sind.
func _admin_upgrade() -> void:
	var o = Admin.office()
	if o == null or not o.complete or not o.def.has("upgrade") or str(o.def.upgrade) == "":
		return
	var to := str(o.def.upgrade)
	if not Game.is_unlocked(to) or not _affordable(to, true) or not _sites().is_empty() and _sites().size() >= 2:
		return
	if w.upgrade_spot(o, to).x < 0:
		return
	var nb = w.upgrade_building(o)
	if nb != null:
		_show(tr("Baut aus: %s") % Data.buildings[to].name)
		print("BOT: Verwaltung wird ausgebaut zu %s (Tag %d)" % [to, Game.day()])


# ================================================================== Bauen
func _wishlist() -> Array:
	var out := []
	if not _home():
		for e in super._wishlist():
			if e[0] in COLONY_TYPES:
				out.append(e)
		if _count("lager") == 0:
			out.append(["lager", "Stauraum"])
		if Steward.net_unlocked() and _count("rundfunk") == 0 and Game.is_unlocked("rundfunk"):
			out.append(["rundfunk", "Funk"])
		return out
	var age: int = mini(Game.current_age(), 6)
	# Rang 1 Lager bleibt aus dem Bot v2; Rang 2 Prüfungsgebäude
	for x in Exams.status(Exams.passed):
		var c: Dictionary = x[0]
		if str(c.get("type", "")) in ["houses", "building"] and not x[3]:
			out.append([str(c.what), "Pruefung"])
	if Game.is_unlocked("verwaltung") and _count("verwaltung") == 0 and Admin.office() == null:
		out.append(["verwaltung", "Verwaltung"])
	out.append_array(super._wishlist())
	for a in range(0, age + 1):
		for e in PLAN[a].build:
			if _count(str(e[0])) < int(e[1]):
				out.append([str(e[0]), "Plan"])
	# Hausbedürfnisse: Werkstatt für fehlende Waren der Häuser
	for g in _goals():
		var mk: String = Steward._maker_type(g)
		if mk != "" and _count(mk) == 0 and Game.amount(g, w) < int(_goal.get(g, 0)):
			out.append([mk, "Engpass %s" % g])
	# Schiffe: Werft, wenn noch Inseln fehlen
	if _islands_needed() > Sea.settled_islands().size() and Game.is_unlocked("werft") and _count("werft") == 0:
		out.insert(0, ["werft", "Pruefung Inseln"])
	return out


func _affordable(type: String, relaxed: bool = false) -> bool:
	if not Data.buildings.has(type):
		return false
	return super._affordable(type, relaxed)


# ================================================================== Werkstätten
## Zielmengen (Abschnitt 5 und 7): Mindestvorräte, Prüfungswaren + 25 %, nächste Forschung, Baustellen, Hausbedürfnisse.
func _goals() -> Dictionary:
	var g := {}
	var age: int = Game.current_age()
	for k in MIN_STOCK:
		if age >= int(MIN_STOCK[k][0]):
			g[k] = int(MIN_STOCK[k][1])
	if age >= 2:
		g["werkzeug"] = 25
		g["kohle"] = 40
		g["bretter"] = 40
	g["holz"] = int(heat_reserve()) + (40 if Seasons.season() == Seasons.SPRING else 30)
	g["stein"] = 60 if _has("steinbruch") else 40
	for x in Exams.status(Exams.passed):
		var c: Dictionary = x[0]
		if str(c.get("type", "")) == "stock":
			g[str(c.what)] = maxi(int(g.get(str(c.what), 0)), int(ceil(int(c.n) * 1.25)))
	var t: String = _wanted_tech()
	if t != "" and not t in Game.research.paid:
		var tc: Dictionary = Data.techs[t].get("cost", {})
		for k in tc:
			g[k] = int(g.get(k, 0)) + int(tc[k])
	if t != "":
		for k in Writing.goods_for(t):
			g[k] = maxi(int(g.get(k, 0)), 30)
	for b in _sites():
		for k in b.def.cost:
			g[k] = int(g.get(k, 0)) + maxi(0, int(b.def.cost[k]) - int(b.delivered.get(k, 0)))
	for k in range(1, HouseNeeds.max_level() + 1):
		if HouseNeeds.count_level(w, k) == 0:
			continue
		for nd in HouseNeeds.level_needs(k):
			if str(nd.get("kind", "")) == "good":
				g[str(nd.good)] = maxi(int(g.get(str(nd.good), 0)), 15)
	# Vorprodukte der Werkstätten, deren Ware fehlt (zwei Stufen tief)
	for i in 2:
		for k in g.keys():
			if Game.amount(k, w) >= int(g[k]):
				continue
			var mk: String = Steward._maker_type(k)
			if mk == "":
				continue
			var ins: Dictionary = Data.buildings[mk].production.get("inputs", {})
			for inp in ins:
				g[inp] = maxi(int(g.get(inp, 0)), int(ins[inp]) * 6)
	_goal = g
	return g


func _workshops() -> Dictionary:
	# Mit Verwalter: nur anhalten, was über dem Doppelten des Ziels liegt (Abschnitt 3, Grenzen). Fehlt ein
	# Vorprodukt, bleibt die Werkstatt an, damit der Verwalter sie besetzt und der Nachschub nachgezogen wird.
	var steward_mode: bool = _home() and Admin.level() >= 1 and Admin.manager() != null
	var jobs: Dictionary = {} if steward_mode else super._workshops()
	var g := _goals()
	for b in w.buildings:
		if not b.complete or not b.def.has("production") or b.def.get("ships", false):
			continue
		if b.type in OWN and not steward_mode:
			continue
		if steward_mode:
			var over := true
			for o in b.prod_def().get("outputs", {}):
				if Game.amount(o, w) < int(g.get(o, 0)) * 2 or (b.type in ["muehle", "baeckerei", "raeucherei", "huehnerhof"] and Game.food_days(w) < 4.0):
					over = false
			b.paused = over
			continue
		var outs: Dictionary = b.prod_def().get("outputs", {})
		var ins: Dictionary = b.prod_def().get("inputs", {})
		var want := false
		for o in outs:
			var goal := int(g.get(o, 0))
			if goal > 0 and Game.amount(o, w) < (goal * 2 if not b.paused else goal):
				want = true
		var can := true
		for k in ins:
			if Game.amount(k, w) < int(ins[k]):
				can = false
		var on := want and can
		b.paused = not on
		if on and w.pool_allows(b):
			var job: String = {"kueche": "koch", "handwerk": "handwerker", "stein": "steinmetz", "stall": "bauer"}.get(str(b.prod_def().get("job", "")), "")
			if job != "":
				jobs[job] = int(jobs.get(job, 0)) + 1
	return jobs


## Mindestvorräte im Reiter Vorräte, ab Amtshaus (Befugnis Mindestvorräte).
func _min_stocks() -> void:
	if not Powers.unlocked("mindestvorrat") or Game.time_days < _mins_next:
		return
	_mins_next = Game.time_days + 1.0
	var g := _goals()
	for k in g:
		if not MIN_STOCK.has(k) and not k in ["holz", "stein"] and Exams.status(Exams.passed).all(func(x): return str(x[0].get("what", "")) != k):
			continue
		var cur: Array = Steward.limits(0, k)
		if int(cur[0]) != int(g[k]):
			Steward.set_limits(0, k, int(g[k]), int(cur[1]))


# ================================================================== Berufe
func _jobs() -> void:
	# Mit Verwaltung teilt der Verwalter die Berufe ein; der Bot nur Forscher (Abschnitt 2, Punkt 6)
	if _home() and Admin.level() >= 1 and Admin.manager() != null:
		_researchers()
		_emergency()
		return
	if not _home() and Powers.covers(w):
		return
	super._jobs()


## Notfallregeln (Abschnitt 8) mit Verwalter: Kälte und Winterholz. Der Bot greift wie ein Spieler ein.
var _emerg_next := 0.0
var _cold := false


func _emergency() -> void:
	if Game.time_days < _emerg_next:
		return
	_emerg_next = Game.time_days + 0.25
	var adults := _adults()
	var pop: int = w.settlers.size()
	var heat_day: float = Seasons.heat_per_settler() * pop
	var fuel: float = Extras.fuel(w)
	var cold: bool = heat_day > 0.0 and fuel < heat_day * 1.5
	var burners := ["papiermuehle", "saegegrube", "ziegelei", "raeucherei", "glashuette"]
	if cold != _cold:
		_cold = cold
		print("BOT: Kälte-Notfall %s (Brennstoff %d, Heizbedarf %.1f am Tag, Tag %d)" % ["an" if cold else "aus", int(fuel), heat_day, Game.day()])
		if cold:
			_show(tr("Kälte: Holzfäller und Werkstätten, die Holz verbrennen, angehalten"))
	if cold:
		for b in w.buildings:
			if b.complete and b.type in burners:
				b.paused = true
			if b.complete and b.type == "baeckerei" and Game.food_days(w) >= 1.0:
				b.paused = true
	# Holzfäller-Soll: Kälte 2 zusätzlich, sonst so viele, dass die Heizreserve bis zum Frühling + 30 erreicht wird
	var have: Array = adults.filter(func(s): return s.job == "holzfaeller")
	var target: float = heat_reserve() + 30.0 + float(_site_need("holz"))
	var want: int = have.size()
	if cold:
		want = have.size() + 2
	elif Game.amount("holz", w) < target:
		want = maxi(have.size(), 1 + ceili((target - Game.amount("holz", w)) / 20.0))
	want = mini(want, maxi(2, adults.size() / 4))
	if want <= have.size():
		return
	var cand: Array = adults.filter(func(s): return s.job in ["frei", "sammler", "steinmetz", "handwerker", "koch", "bauer"])
	cand.sort_custom(func(a, b): return (0 if a.job == "frei" else 1) < (0 if b.job == "frei" else 1))
	for i in mini(want - have.size(), cand.size()):
		_set_job(cand[i], "holzfaeller")


func _researchers() -> void:
	var adults := _adults()
	var fd: float = Game.food_days(w)
	var want := 0
	if Game.research.current != "":
		if fd >= 0.8:
			want = 1
		if w.settlers.size() >= 5 and fd >= 1.5:
			want = maxi(2, adults.size() / 5)
		if fd < 1.0:
			want = 1
		want = mini(want, _research_slots())
	var have: Array = adults.filter(func(s): return s.job == "forscher")
	if have.size() > want:
		for i in have.size() - want:
			_set_job(have[i], "frei")
	elif have.size() < want:
		var cand: Array = adults.filter(func(s): return s.job in ["frei", "sammler", "holzfaeller"] and not Steward.locked(s) or s.job == "frei")
		cand.sort_custom(func(a, b): return a.skill_factor("wissen") > b.skill_factor("wissen"))
		for i in mini(want - have.size(), cand.size()):
			_set_job(cand[i], "forscher")


func _apply_jobs(adults: Array, want: Dictionary) -> void:
	if not _home():
		want.erase("forscher")  # geforscht wird nur auf der Hauptinsel
	super._apply_jobs(adults, want)


func _set_job(s, job: String) -> void:
	if s.job == job:
		return
	if Admin.level() >= 1 and Sea.is_main(s.world):
		if job != "frei":
			_show(tr("%s wird %s") % [s.display_name, Data.jobs[job].name if Data.jobs.has(job) else job])
		JobDesk.assign(s, job, "spieler")
		Game.player_action.emit("job", job)
		_job_changes += 1
		return
	super._set_job(s, job)


# ================================================================== Schiffe und Inseln (Abschnitt 6)
func _islands_needed() -> int:
	for x in Exams.status(Exams.passed):
		if str(x[0].get("type", "")) == "islands_settled":
			return int(x[0].n)
	return 1


func _ships() -> void:
	var need := _islands_needed()
	var settled: int = Sea.settled_islands().size() + Sea.voyages.filter(func(v): return v.kind == "settle").size()
	if settled >= need:
		return
	var yard = null
	for b in w.buildings:
		if b.complete and str(b.def.get("base", b.type)) == "werft":
			yard = b
	if yard == null:
		return
	var known: Array = Sea.islands.filter(func(m): return m.state == "discovered")
	var mine: Array = Sea.ships.filter(func(sh): return int(sh.get("home", 0)) == 0)
	var has_boat: bool = mine.any(func(sh): return not Sea.is_expedition(sh)) or "boot" in yard.ship_queue or yard.ship_wip == "boot"
	var has_exp: bool = mine.any(func(sh): return Sea.is_expedition(sh)) or "expedition" in yard.ship_queue or yard.ship_wip == "expedition"
	# 1. Ruderboot und Erkundung, bis 2 unbesiedelte Inseln bekannt sind
	if known.size() < 2:
		if not has_boat:
			yard.ship_queue.append("boot")
			yard.paused = false
			_show(tr("Werft: Ruderboot in Auftrag"))
			print("BOT: Werft baut ein Ruderboot (Tag %d)" % Game.day())
		for sh in Sea.idle_ships(0):
			if Sea.is_expedition(sh):
				continue
			if Sea.crew_missing(sh) > 0:
				Sea.hire_sailor(sh)
		if Sea.can_explore(w) == "":
			Sea.start_explore(w)
			_show(tr("Schiff sucht eine neue Insel"))
			print("BOT: Erkundung gestartet (Tag %d)" % Game.day())
	# 2. Expeditionsschiff
	if not known.is_empty() and not has_exp:
		yard.ship_queue.append("expedition")
		yard.paused = false
		_show(tr("Werft: Expeditionsschiff in Auftrag"))
		print("BOT: Werft baut ein Expeditionsschiff (Tag %d)" % Game.day())
	if not yard.ship_queue.is_empty() or yard.ship_wip != "":
		yard.paused = false
	# 3. Losschicken, wenn alles stimmt
	var exp := {}
	for sh in Sea.idle_ships(0):
		if Sea.is_expedition(sh):
			exp = sh
	if exp.is_empty() or known.is_empty():
		return
	var why := ""
	if Seasons.season() >= Seasons.AUTUMN:
		why = "Herbst/Winter"
	elif _adults().size() < 12 + 6 and Game.current_age() >= 2 and _adults().size() < 14:
		why = "zu wenige Erwachsene (%d)" % _adults().size()
	elif not Events.all_events().is_empty():
		why = "Ereignis angekündigt"
	var people := _crew_for_colony()
	if people.size() < 6 and why == "":
		why = "keine 6 Mitfahrer"
	var goods := {}
	var need_food: float = Sea.expedition_food_need(people) * 2.0
	var got := 0.0
	for f in ["brot", "raeucherfisch", "fisch", "beeren", "aepfel", "weizen", "konserven"]:
		if got >= need_food:
			break
		var per: float = Data.food_satiety(f)
		if per <= 0.0:
			continue
		var n: int = mini(Game.amount(f, w) - 5, int(ceil((need_food - got) / per)))
		if n > 0:
			goods[f] = n
			got += n * per
	if Game.current_age() >= 2 and Game.amount("waffen", w) >= 2:
		goods["waffen"] = 2
	if why == "" and got < Sea.expedition_food_need(people):
		why = "zu wenig Essen"
	if why != "":
		if why != _ship_note:
			_ship_note = why
			print("BOT: Expedition wartet: %s (Tag %d)" % [why, Game.day()])
		return
	var target := _pick_island(known)
	var err: String = Sea.send_ship(w, int(target.id), people, exp, goods)
	if err == "":
		_show(tr("Expedition nach %s") % target.name)
		print("BOT: Expedition mit %d Siedlern nach %s (%s), Ladung %s (Tag %d)" % [people.size(), target.name, target.biome, goods, Game.day()])
	else:
		print("BOT: Expedition nicht möglich: %s" % err)


func _pick_island(known: Array) -> Dictionary:
	var age: int = Game.current_age()
	var want_biome := "berg" if age == 3 else ("tropen" if age >= 4 else "")
	var best: Dictionary = known[0]
	for m in known:
		if want_biome != "" and str(m.biome) == want_biome and str(best.biome) != want_biome:
			best = m
		elif (want_biome == "" or str(m.biome) == str(best.biome)) and Sea.distance(0, int(m.id)) < Sea.distance(0, int(best.id)):
			best = m
	return best


## 3 Paare, nicht Verwalter, Forscher oder Seeleute; je einer gut in Holz, Bauen und Nahrung (soweit vorhanden).
func _crew_for_colony() -> Array:
	var cand: Array = _adults().filter(func(s): return not s.job in ["verwalter", "forscher", "seemann"])
	var f: Array = cand.filter(func(s): return s.sex == "f")
	var m: Array = cand.filter(func(s): return s.sex != "f")
	var out := []
	for i in 3:
		if i < f.size():
			out.append(f[i])
		if i < m.size():
			out.append(m[i])
	return out


# ================================================================== Bericht
func report() -> void:
	super.report()
	if not _home():
		return
	var gl := []
	for k in _goal:
		if Game.amount(k, w) < int(_goal[k]):
			gl.append("%s %d/%d" % [k, Game.amount(k, w), int(_goal[k])])
	print("   BOT Ziele offen: %s | Verwaltung Stufe %d | Inseln %d/%d | Schiffe %s | %s" % [", ".join(gl), Admin.level(),
		Sea.settled_islands().size(), _islands_needed(), Sea.ships.map(func(sh): return "%s@%d:%s" % [sh.type, int(sh.at), sh.state]), _ship_note])
	for id in colonies:
		var cw = Sea.worlds.get(id)
		if cw != null and is_instance_valid(cw):
			print("   BOT Kolonie %s: Siedler %d, Nahrung %.1f Tage, Holz %d, Gebäude %d" % [Sea.island_name(cw), cw.settlers.size(),
				Game.food_days(cw), Game.amount("holz", cw), cw.buildings.size()])
