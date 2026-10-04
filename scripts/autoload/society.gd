extends Node
## KI-Variante (Webadresse mit /ki/): Die Siedler steuern sich selbst.
##
## - Jeder Siedler denkt selbst: Er wählt seine Arbeit nach dem, was auf seiner Insel
##   gerade fehlt, nach seinen Begabungen und nach der Absprache seines Hauses
##   (`_think`). Was er denkt, steht in `thoughts` (Infofenster).
## - Die Bewohner eines Hauses sind die kleinste Gruppe. Die Häuser sprechen sich ab,
##   wer sich um welchen Bereich kümmert (Nahrung, Rohstoffe, Bauen, Wissen, Schutz).
##   Mitglieder einer kranken Person pflegen sie (heilt schneller).
## - Jede Insel hat einen Rat aus je einem Sprecher pro Haus. Er stimmt regelmäßig über
##   die Strategie ab (`_council`). Die Strategie gewichtet Berufe, Bauten und Forschung.
## - Der Spieler ist der Herrscher. Die Inseln schicken ihm Anliegen (Forderungen und
##   Angebote, `requests`). Er stimmt zu, lehnt ab, diskutiert mit Argumenten
##   (`argue`) oder bestimmt (`command`). Was daraus folgt, setzt die KI selbst um.
##   Unbeantwortete Anliegen entscheidet der Rat nach `request_days` selbst.
## Alle Zahlen in data/society.json. Ohne KI-Variante tut dieses Modul nichts.

signal changed  # Rat, Anliegen oder Strategie haben sich geändert (für die Oberfläche)

const DOMAINS := {
	"nahrung": ["sammler", "fischer", "bauer", "koch"],
	"rohstoffe": ["holzfaeller", "steinmetz"],
	"bau": ["baumeister", "handwerker"],
	"wissen": ["forscher"],
	"schutz": ["jaeger"],
}
const DOMAIN_NAMES := {"nahrung": "Nahrung", "rohstoffe": "Holz und Stein", "bau": "Bauen und Werkstätten",
	"wissen": "Forschung", "schutz": "Schutz"}
const FOOD_JOBS := ["sammler", "fischer", "bauer"]
## Berufe, die die KI vergibt (Seeleute bleiben, wie sie sind)
const AI_JOBS := ["sammler", "fischer", "bauer", "koch", "holzfaeller", "steinmetz", "baumeister",
	"handwerker", "forscher", "jaeger", "frei"]
const PROD_ORDER := ["saegegrube", "muehle", "baeckerei", "raeucherei", "lehmgrube", "ziegelei", "steinbruch",
	"koehlerei", "mine", "schmelze", "schmiede", "huehnerhof", "glashuette", "papiermuehle", "stahlwerk",
	"fabrik", "konservenfabrik", "kraftwerk", "gewaechshaus", "elektronikwerk", "solarpark", "fusionsreaktor"]
const HOUSE_ORDER := ["wohnblock", "mietshaus", "steinhaus", "holzhaus", "huette"]

var enabled := false
## Je Insel (ID als int): {strategy, since, next_council, next_think, next_build, trust, votes,
## log, festival_until, leisure_until, overtime_until, resent_until, speakers, cool, attacks}
var isl: Dictionary = {}
var requests: Array = []  # offene Anliegen an den Herrscher
var next_req: int = 1
var orders: Dictionary = {}  # Siedler-ID -> Tag, bis zu dem der Befehl des Herrschers gilt
var last_change: Dictionary = {}  # Siedler-ID -> Tag des letzten Berufswechsels (nicht gespeichert)
var thoughts: Dictionary = {}  # Siedler-ID -> was er gerade denkt (nicht gespeichert)
var households: Dictionary = {}  # Insel-ID -> Liste der Häuser (zur Anzeige, nicht gespeichert)
var debate: Dictionary = {}  # laufende Diskussion (nicht gespeichert)
var welcomed := false  # Begrüßung der KI-Variante gezeigt
var _caps: Dictionary = {}  # wie viele Nahrungsarbeiter die Natur gerade trägt (aus desired_jobs)
var _rng := RandomNumberGenerator.new()
var _cfg: Dictionary = {}


func _ready() -> void:
	_rng.randomize()


func cfg(key: String, default = 0.0):
	if _cfg.is_empty():
		_cfg = Data.society
	return _cfg.get(key, default)


func strategies() -> Dictionary:
	return cfg("strategies", {})


func strat_name(k: String) -> String:
	return strategies().get(k, {}).get("name", k)


func strategy_allowed(k: String) -> bool:
	var req: String = strategies().get(k, {}).get("requires", "")
	return req == "" or Game.is_researched(req)


# ================================================================== Zustand je Insel
func state(w) -> Dictionary:
	var id := int(w.island_id) if typeof(w) == TYPE_OBJECT else int(w)
	if not isl.has(id):
		isl[id] = {"strategy": "nahrung", "since": Game.time_days, "next_council": Game.time_days + float(cfg("first_council_day", 0.4)),
			"next_think": 0.0, "next_build": Game.time_days + 0.3, "trust": float(cfg("trust_start", 55)), "votes": [],
			"log": [], "dlog": [], "festival_until": 0.0, "leisure_until": 0.0, "overtime_until": 0.0, "resent_until": 0.0,
			"speakers": {}, "cool": {}, "attacks": 0.0, "heard": []}
	return isl[id]


func trust(w) -> float:
	return float(state(w).trust)


func _add_trust(w, key: String) -> void:
	var st := state(w)
	st.trust = clampf(float(st.trust) + float(cfg("trust", {}).get(key, 0)), 0.0, 100.0)


## Entscheidungsprotokoll zum Beobachten der KI (Berufswechsel, Stimmen, Bauten, Anliegen).
func decide(w, text: String) -> void:
	var st := state(w)
	st.dlog.append([Game.time_days, text])
	if st.dlog.size() > 40:
		st.dlog = st.dlog.slice(st.dlog.size() - 40)
	changed.emit()


func log_line(w, text: String) -> void:
	decide(w, text)
	var st := state(w)
	st.log.append([Game.day(), text])
	if st.log.size() > 12:
		st.log = st.log.slice(st.log.size() - 12)


func reset() -> void:
	isl = {}
	requests = []
	next_req = 1
	orders = {}
	last_change = {}
	thoughts = {}
	households = {}
	debate = {}
	welcomed = false


func serialize() -> Dictionary:
	var out := {}
	for id in isl:
		out[str(id)] = isl[id]
	var ord := {}
	for sid in orders:
		ord[str(sid)] = orders[sid]
	return {"isl": out, "requests": requests, "next_req": next_req, "orders": ord, "welcomed": welcomed}


func load_from(d: Dictionary) -> void:
	reset()
	var src: Dictionary = d.get("isl", {})
	for k in src:
		var st: Dictionary = src[k]
		var sp := {}
		for h in st.get("speakers", {}):
			sp[int(h)] = int(st.speakers[h])
		st.speakers = sp
		isl[int(k)] = st
		state(int(k))  # fehlende Felder ergänzen
		for key in ["heard", "cool", "log", "votes", "dlog"]:
			if not st.has(key):
				st[key] = {} if key == "cool" else []
	for r in d.get("requests", []):
		r.isl = int(r.isl)
		requests.append(r)
	next_req = int(d.get("next_req", 1))
	welcomed = bool(d.get("welcomed", false))
	var od: Dictionary = d.get("orders", {})
	for k in od:
		orders[int(k)] = float(od[k])


# ================================================================== Takt
func _process(_delta: float) -> void:
	if not enabled or Game.world == null or Game.is_over or Game.speed <= 0:
		return
	var t := Game.time_days
	if not welcomed:
		welcomed = true
		Game.notify("KI-Version: Deine Siedler entscheiden selbst, was sie arbeiten. Jedes Haus schickt einen Sprecher in den Inselrat.", "ki")
		Game.notify("Du bist der Herrscher. Unter „Rat“ findest du die Anliegen der Inseln: zustimmen, diskutieren oder bestimmen.", "glocke")
	for w in Sea.all_worlds():
		if w.settlers.is_empty():
			continue
		var st := state(w)
		if t >= float(st.next_think):
			st.next_think = t + float(cfg("think_days", 0.25))
			_think(w)
			_care(w, float(cfg("think_days", 0.25)))
			st.attacks = maxf(0.0, float(st.attacks) - 0.5 * float(cfg("think_days", 0.25)))
		if t >= float(st.next_council) and not Game.is_night():
			st.next_council = t + float(cfg("council_days", 2.0))
			_council(w)
		if t >= float(st.next_build):
			st.next_build = t + float(cfg("build_check_days", 0.5))
			_plan_buildings(w)
			_check_research(w)
			_check_help(w)
	_expire_requests()


# ================================================================== Lage einer Insel
## Zahlen, aus denen Siedler und Rat ihre Entscheidungen ableiten.
func situation(w) -> Dictionary:
	var pop: int = max(1, w.settlers.size())
	var adults: Array = w.settlers.filter(func(s): return s.is_adult())
	var kids: int = w.settlers.size() - adults.size()
	var food := Game.total_food(w)
	var season := Seasons.season()
	var dleft := Seasons.season_days() - float(Seasons.day_in_season()) + 1.0
	# Heizholz bis zum Frühling (je Siedler: Herbst 0,3, Winter 1 pro Tag)
	var heat := 0.0
	match season:
		Seasons.SUMMER:
			heat = pop * 3.9
		Seasons.AUTUMN:
			heat = pop * (0.3 * dleft + 3.0)
		Seasons.WINTER:
			heat = pop * dleft
	var sites: Array = w.construction_sites()
	var need_wood := 0
	var need_stone := 0
	for b in sites:
		var rc: Dictionary = b.remaining_cost()
		need_wood += int(rc.get("holz", 0))
		need_stone += int(rc.get("stein", 0))
	var predators := 0
	for a in w.animals:
		if is_instance_valid(a) and a.is_adult() and a.type in ["wolf", "baer"]:
			predators += 1
	var farms: int = w.buildings.filter(func(b): return b.complete and b.def.has("farm")).size()
	var vit_low: int = w.settlers.filter(func(s): return s.mind.vit < float(Data.ppl("vit_low", 30.0))).size()
	# Wie viel Essen sollte im Lager sein? Ein Erwachsener isst etwa 3 am Tag. Vor und im Winter
	# wächst kaum etwas nach, dann braucht es einen Vorrat bis zum Frühling.
	var eaters: float = adults.size() + kids * 0.5
	var reserve := 6.0
	match season:
		Seasons.SUMMER:
			reserve += 6.0
		Seasons.AUTUMN:
			reserve += 9.0
		Seasons.WINTER:
			reserve += 3.0 * dleft
	return {
		"pop": pop, "adults": adults.size(), "kids": kids, "food": food,
		"food_head": float(food) / pop, "season": season, "heat": heat,
		"food_target": maxf(10.0, eaters * reserve), "food_ratio": float(food) / maxf(10.0, eaters * reserve),
		"wood": Game.amount("holz", w), "stone": Game.amount("stein", w),
		"wood_target": 25.0 + heat + need_wood, "stone_target": 15.0 + need_stone,
		"sites": sites.size(), "housing": Game.housing_capacity(w), "predators": predators,
		"farms": farms, "vit_low": vit_low, "attacks": float(state(w).attacks),
		"storage_full": float(Game.used_volume(w)) / maxf(1.0, float(Game.storage_volume(w))),
	}


## Wie dringend ist jede Strategie aus Sicht der Lage (gleich für alle Ratsmitglieder)?
func situation_scores(w, sit: Dictionary = {}) -> Dictionary:
	if sit.is_empty():
		sit = situation(w)
	var wood_def := clampf(1.0 - float(sit.wood) / maxf(1.0, float(sit.wood_target)), 0.0, 1.0)
	var sc := {}
	sc["nahrung"] = clampf(1.0 - float(sit.food_ratio), 0.0, 1.0) * 1.3 + (0.2 if int(sit.vit_low) > 0 else 0.0)
	match int(sit.season):
		Seasons.SPRING:
			sc["winter"] = 0.0
		Seasons.SUMMER:
			sc["winter"] = 0.25 + wood_def * 0.8 + clampf(1.0 - float(sit.food_ratio), 0.0, 1.0) * 0.4
		Seasons.AUTUMN:
			sc["winter"] = 0.45 + wood_def + clampf(1.0 - float(sit.food_ratio), 0.0, 1.0) * 0.4
		_:
			sc["winter"] = wood_def * 1.1
	var crowded: bool = int(sit.pop) >= int(sit.housing) - 1
	sc["wachstum"] = (0.8 if crowded else 0.3) * (1.0 if float(sit.food_head) > 6.0 else 0.4)
	var unbuilt := 0
	for t in PROD_ORDER:
		if Game.is_unlocked(t) and not w.buildings.any(func(b): return b.type == t):
			unbuilt += 1
	sc["bauen"] = 0.3 + minf(0.5, unbuilt * 0.12) + (0.2 if int(sit.sites) > 0 else 0.0)
	var avail := Data.sorted_tech_ids().any(func(t): return Game.tech_state(t) in ["available", "current"])
	sc["wissen"] = (0.45 if avail else 0.0) + (0.3 if float(sit.food_head) > 12.0 else 0.0)
	sc["sicherheit"] = minf(1.2, int(sit.predators) * 0.12 + float(sit.attacks) * 0.3) if int(sit.predators) > 0 else 0.0
	sc["seefahrt"] = (0.3 + (0.3 if Sea.settled_islands().size() < 2 else 0.0)) if strategy_allowed("seefahrt") else -9.0
	return sc


# ================================================================== Denken der Siedler
## Wie viele Arbeiter jeder Beruf auf der Insel bräuchte (vor der Strategie).
func desired_jobs(w, sit: Dictionary) -> Dictionary:
	var want := {}
	var eaters: float = float(sit.adults) + float(sit.kids) * 0.5
	var f := clampf(1.6 - 0.7 * float(sit.food_ratio), 0.6, 1.6)
	var food_n := eaters / float(cfg("gatherer_feeds", 1.5)) * f
	# Wo gibt es Nahrung? Felder, Fischgründe, Sträucher (im Winter kahl)
	var fish := 0
	var bush := 0
	var bare: Array = Seasons.cfg.get("winter_bare", [])
	for n in w.nodes:
		if n.amount <= 0:
			continue  # abgeerntet, wächst erst nach
		if n.type == "fischgrund":
			fish += 1
		elif n.type in ["busch", "palme", "pilzkreis"] and not (Seasons.is_winter() and n.type in bare):
			bush += 1
	var farm_n := ceili(int(sit.farms) / 2.0)
	var bauer := minf(food_n, farm_n)
	var rest := food_n - bauer
	var fischer := minf(rest * 0.5 if bush > 0 else rest, maxf(1.0, fish / 2.0) if fish > 0 else 0.0)
	var sammler := minf(rest - fischer, maxf(0.0, bush / 2.0))
	_caps = {"bauer": float(int(sit.farms)), "fischer": float(fish), "sammler": float(bush)}
	if Data.job_unlocked("bauer") or farm_n > 0:
		want["bauer"] = bauer
	want["fischer"] = fischer
	want["sammler"] = sammler
	# Holz und Stein
	var wr := float(sit.wood) / maxf(1.0, float(sit.wood_target))
	want["holzfaeller"] = clampf(1.3 - wr, 0.0, 1.3) * (1.0 + float(sit.pop) / 6.0)
	var sr := float(sit.stone) / maxf(1.0, float(sit.stone_target))
	want["steinmetz"] = clampf(1.0 - sr, 0.0, 1.0) * (1.0 + float(sit.pop) / 10.0)
	if int(sit.sites) > 0:
		want["baumeister"] = minf(float(sit.sites), 1.0 + float(sit.pop) / 8.0)
	# Werkstätten, die arbeiten könnten
	for b in w.buildings:
		if not b.complete or b.prod_def().is_empty() or b.prod_blocker() != "":
			continue
		var j: String = {"kueche": "koch", "handwerk": "handwerker", "stein": "steinmetz"}.get(b.prod_def().get("job", ""), "")
		if j != "":
			want[j] = float(want.get(j, 0.0)) + minf(1.0, float(b.slots()))
	# Forschung
	if Game.research.current != "":
		var places := 0
		for b in w.buildings:
			if b.complete and b.def.has("research"):
				places += b.slots()
		want["forscher"] = minf(float(places), maxf(1.0, float(sit.adults) / 6.0))
	if Data.job_unlocked("jaeger") and int(sit.predators) > 0:
		want["jaeger"] = 1.0 + (1.0 if float(sit.attacks) > 1.0 else 0.0)
	return want


## Plätze je Beruf nach Strategie, passend zur Zahl der verfügbaren Siedler.
func job_slots(w, sit: Dictionary, avail: int) -> Dictionary:
	var want := desired_jobs(w, sit)
	var sw: Dictionary = strategies().get(state(w).strategy, {}).get("jobs", {})
	var famine := float(sit.food_head) < 3.0
	var total := 0.0
	for j in want:
		want[j] = float(want[j]) * float(sw.get(j, 1.0))
		total += float(want[j])
	var slots := {}
	var scale := 1.0 if total <= avail else float(avail) / total
	for j in want:
		var v := float(want[j]) * scale
		if famine and j in FOOD_JOBS:
			v = float(want[j])  # Hungersnot: Nahrung zuerst, ganz
		slots[j] = int(round(v)) if v >= 0.5 or j in FOOD_JOBS else 0
	# Übrige Hände: solange Essen nicht reichlich da ist, zuerst dorthin, wo die Natur noch trägt
	var used := 0
	for j in slots:
		used += int(slots[j])
	var spare := avail - used
	if float(sit.food_ratio) < 1.5:
		for j in ["bauer", "fischer", "sammler"]:
			while spare > 0 and float(slots.get(j, 0)) < float(_caps.get(j, 0.0)) * (1.0 if j == "bauer" else 0.7):
				slots[j] = int(slots.get(j, 0)) + 1
				spare -= 1
	# Ohne Holz geht nichts: mindestens ein Holzfäller, wenn es fast keins mehr gibt
	if float(sit.wood) < 15.0 and avail >= 2 and int(slots.get("holzfaeller", 0)) == 0:
		slots["holzfaeller"] = 1
	# Mindestens ein Nahrungsarbeiter, solange Nahrung nicht reichlich ist
	var food_slots := 0
	for j in FOOD_JOBS:
		food_slots += int(slots.get(j, 0))
	if food_slots == 0 and float(sit.food_head) < 20.0 and avail > 0:
		slots["fischer" if float(want.get("fischer", 0.0)) >= float(want.get("sammler", 0.0)) else "sammler"] = 1
	return slots


## Wie gern macht ein Siedler einen Beruf? (Begabung, Können, Gewohnheit, Absprache des Hauses)
func preference(s, job: String, domain: String) -> float:
	if job == "frei":
		return 0.3
	var sk: String = Data.jobs.get(job, {}).get("skill", "")
	var p := 0.0
	if sk != "":
		p += float(s.mind.talents.get(sk, 1.0)) + s.skill_level(sk) * 0.06
	if s.job == job:
		p += 0.35
	if domain != "" and job in DOMAINS.get(domain, []):
		p += 0.25
	if s.best_job() == job:
		p += 0.15
	return p


func _think(w) -> void:
	var sit := situation(w)
	_make_households(w, sit)
	var t := Game.time_days
	var free: Array = []
	for s in w.settlers:
		if not s.is_adult():
			thoughts[s.id] = "Spielt und lernt." if w.school_of(s) == null else "Lernt in der Schule."
			continue
		if float(orders.get(s.id, 0.0)) > t:
			thoughts[s.id] = "Der Herrscher hat mich zum %s bestimmt. Das mache ich." % s.job_name()
			continue
		if s.job == "seemann":
			thoughts[s.id] = "Ich gehöre zur Besatzung unserer Schiffe."
			continue
		if s.mind.needs_bed():
			thoughts[s.id] = "Ich bin krank und muss liegen."
			continue
		free.append(s)
	if free.is_empty():
		return
	var slots := job_slots(w, sit, free.size())
	var dom_of := {}
	for h in households.get(int(w.island_id), []):
		for sid in h.members:
			dom_of[sid] = h.domain
	# Wer macht gerade was? Zu viele in einem Beruf = jemand kann wechseln.
	var have := {}
	for s in free:
		have[s.job] = int(have.get(s.job, 0)) + 1
	var changes := 0
	var max_changes := int(cfg("max_changes_per_think", 3))
	var cd := float(cfg("change_cooldown_days", 1.0))
	# Absprache: offene Plätze, das dringendste (größte Lücke) zuerst
	var open := []
	for j in slots:
		var gap := int(slots[j]) - int(have.get(j, 0))
		if gap > 0 and Data.job_unlocked(j):
			open.append([gap + (1 if j in FOOD_JOBS and float(sit.food_head) < 5.0 else 0), j])
	open.sort_custom(func(x, y): return x[0] > y[0])
	for o in open:
		var j: String = o[1]
		for _n in int(o[0]):
			if changes >= max_changes:
				break
			# Wer wechselt? Freie oder jemand aus einem Beruf mit zu vielen Leuten, wer es am liebsten tut
			var best = null
			var best_v := -INF
			for s in free:
				if s.job == j or t - float(last_change.get(s.id, -99.0)) < cd:
					continue
				var surplus: bool = s.job == "frei" or not slots.has(s.job) or int(have.get(s.job, 0)) > int(slots.get(s.job, 0))
				if not surplus:
					continue
				var v := preference(s, j, dom_of.get(s.id, "")) - preference(s, s.job, dom_of.get(s.id, "")) * 0.3
				if v > best_v:
					best_v = v
					best = s
			if best == null:
				break
			var old: String = best.job_name()
			have[best.job] = int(have.get(best.job, 0)) - 1
			have[j] = int(have.get(j, 0)) + 1
			best.set_job(j)
			last_change[best.id] = t
			changes += 1
			Game.notify_at(w, "%s denkt um: %s statt %s. %s" % [best.display_name, best.job_name(), old, _why_job(w, j, sit)], "ki")
			decide(w, "%s wird %s (vorher %s). Gebraucht: %d, da waren %d. %s" % [best.display_name, best.job_name(), old,
				int(slots[j]), int(have[j]) - 1, _why_job(w, j, sit)])
	# Wer in einem überbesetzten Beruf bleibt und nichts anderes findet, hilft frei aus
	for s in free:
		if changes >= max_changes:
			break
		if s.job != "frei" and slots.has(s.job) and int(have.get(s.job, 0)) > int(slots.get(s.job, 0)) + 1 \
				and t - float(last_change.get(s.id, -99.0)) >= cd:
			have[s.job] = int(have.get(s.job, 0)) - 1
			decide(w, "%s hört als %s auf (zu viele dort) und hilft jetzt frei aus." % [s.display_name, s.job_name()])
			s.set_job("frei")
			last_change[s.id] = t
			changes += 1
	for s in free:
		thoughts[s.id] = _thought(s, w, sit, dom_of.get(s.id, ""))


func _why_job(w, j: String, sit: Dictionary) -> String:
	match j:
		"sammler", "fischer", "bauer":
			if float(sit.food_head) < 5.0:
				return "Das Essen wird knapp (%d je Kopf)." % int(sit.food_head)
			if int(sit.season) in [Seasons.SUMMER, Seasons.AUTUMN] and float(sit.food_ratio) < 1.0:
				return "Wir brauchen Vorrat für den Winter (%d von %d)." % [int(sit.food), int(sit.food_target)]
			return "Wir brauchen jeden Tag Essen."
		"koch":
			return "Die Küche macht haltbares, sättigendes Essen."
		"holzfaeller":
			if int(sit.season) in [Seasons.SUMMER, Seasons.AUTUMN]:
				return "Wir brauchen Brennholz für den Winter."
			return "Holz wird für Bauten gebraucht."
		"steinmetz":
			return "Stein wird gebraucht."
		"baumeister":
			return ("%d Baustellen warten." % int(sit.sites)) if int(sit.sites) > 0 else "Gerade ist keine Baustelle offen."
		"handwerker":
			return "Die Werkstätten brauchen Hände."
		"forscher":
			return "Wir wollen %s erforschen." % Data.techs.get(Game.research.current, {}).get("name", "Neues")
		"jaeger":
			return "Wilde Tiere bedrohen uns."
	return "Ich helfe, wo es gerade fehlt."


func _thought(s, w, sit: Dictionary, domain: String) -> String:
	var text := "Ich bin %s. %s" % [s.job_name(), _why_job(w, s.job, sit)]
	var sk: String = Data.jobs.get(s.job, {}).get("skill", "")
	if sk != "" and float(s.mind.talents.get(sk, 1.0)) >= 1.3:
		text += " Das liegt mir."
	elif sk != "" and float(s.mind.talents.get(sk, 1.0)) < 0.8:
		text += " Eigentlich liegt mir das nicht, aber es muss sein."
	if domain != "" and s.job in DOMAINS.get(domain, []):
		text += " Unser Haus kümmert sich um %s." % DOMAIN_NAMES[domain]
	var fav: String = s.best_job()
	if fav != s.job and fav != "frei" and Data.jobs.has(fav):
		text += " Am liebsten wäre ich %s." % Data.jobs[fav].name
	return text


# ================================================================== Häuser
## Bewohner eines Hauses bilden die kleinste Gruppe. Ohne Haus: „Am Lagerfeuer“.
## Die Häuser teilen sich die Bereiche nach Bedarf und Begabung ihrer Mitglieder auf.
func _make_households(w, sit: Dictionary) -> void:
	var st := state(w)
	var groups := {}
	for s in w.settlers:
		var hid: int = int(s.home_id)
		if not groups.has(hid):
			groups[hid] = []
		groups[hid].append(s)
	var list := []
	for hid in groups:
		var mem: Array = groups[hid]
		var adults: Array = mem.filter(func(s): return s.is_adult())
		if adults.is_empty():
			continue
		var sp = null
		var old_sp := int(st.speakers.get(hid, 0))
		for s in adults:
			if s.id == old_sp:
				sp = s
		if sp == null:
			adults.sort_custom(func(a, b): return a.mind.trait_value("iq") + a.mind.trait_value("gemuet") + a.age * 0.1 \
				> b.mind.trait_value("iq") + b.mind.trait_value("gemuet") + b.age * 0.1)
			sp = adults[0]
			st.speakers[hid] = sp.id
		var home = w.building_by_id(hid) if hid != 0 else null
		var name: String = ("%s von %s" % [home.def.name, sp.display_name]) if home else "Am Lagerfeuer"
		list.append({"home": hid, "name": name, "speaker": sp, "members": mem.map(func(s): return s.id),
			"adults": adults.size(), "size": mem.size(), "domain": "", "cap": home.housing() if home else 0})
	# Absprache: Bedarf je Bereich, größte Häuser wählen zuerst nach Begabung
	var want := desired_jobs(w, sit)
	var demand := {}
	for d in DOMAINS:
		demand[d] = 0.0
		for j in DOMAINS[d]:
			demand[d] += float(want.get(j, 0.0))
	list.sort_custom(func(a, b): return a.adults > b.adults)
	for h in list:
		var best := ""
		var best_v := -INF
		for d in DOMAINS:
			if float(demand[d]) <= 0.0:
				continue
			var fit := 0.0
			for sid in h.members:
				var s = _settler(w, sid)
				if s and s.is_adult():
					for j in DOMAINS[d]:
						var sk: String = Data.jobs.get(j, {}).get("skill", "")
						fit = maxf(fit, float(s.mind.talents.get(sk, 1.0)) if sk != "" else 1.0)
			var v := float(demand[d]) * fit
			if v > best_v:
				best_v = v
				best = d
		if best == "":
			best = "nahrung"
		h.domain = best
		demand[best] = float(demand[best]) - float(h.adults)
	households[int(w.island_id)] = list


func _settler(w, sid: int):
	for s in w.settlers:
		if s.id == sid:
			return s
	return null


func household_of(s) -> Dictionary:
	for h in households.get(int(s.world.island_id), []):
		if s.id in h.members:
			return h
	return {}


## Gegenseitige Hilfe: Liegt jemand krank im Bett, pflegen ihn die anderen im Haus.
func _care(w, days: float) -> void:
	for s in w.settlers:
		if not s.mind.needs_bed():
			continue
		var h := household_of(s)
		for sid in h.get("members", []):
			var o = _settler(w, sid)
			if o and o != s and o.is_adult() and not o.mind.needs_bed():
				s.mind.sick_left -= days * float(cfg("care_heal_bonus", 0.4))
				thoughts[o.id] = "Ich pflege %s (%s). %s" % [s.display_name, s.mind.illness_name(), thoughts.get(o.id, "")]
				break


# ================================================================== Inselrat
## Ein Sprecher je Haus stimmt über die Strategie ab.
func representatives(w) -> Array:
	return households.get(int(w.island_id), []).map(func(h): return h.speaker).filter(func(s): return is_instance_valid(s))


## Wie sieht ein Ratsmitglied die Strategien? Gibt {Strategie: [Wert, Grund]} zurück.
func opinion(s, w, sc: Dictionary) -> Dictionary:
	var st := state(w)
	var h := household_of(s)
	var m = s.mind
	var hunger := 0.0
	var n := 0
	for sid in h.get("members", [s.id]):
		var o = _settler(w, sid)
		if o:
			hunger += o.hunger
			n += 1
	hunger = hunger / maxf(1.0, n)
	var crowded: bool = int(h.get("home", 0)) == 0 or int(h.get("size", 0)) >= int(h.get("cap", 99))
	var r := RandomNumberGenerator.new()
	r.seed = hash(s.id * 31 + Game.day())
	var op := {}
	for k in strategies():
		if not strategy_allowed(k):
			continue
		var v := float(sc.get(k, 0.0))
		var why := ""
		match k:
			"nahrung":
				v += (60.0 - hunger) / 100.0 + (0.15 if float(m.talents.get("nahrung", 1.0)) >= 1.3 else 0.0)
				why = "Wir haben Hunger." if hunger < 45.0 else "Die Vorräte sind zu knapp."
			"winter":
				v += (6.0 - m.trait_value("konst")) / 12.0
				why = "Der Winter kommt, wir brauchen Holz und Vorräte." if int(Seasons.season()) != Seasons.WINTER else "Wir frieren, wir brauchen Holz."
			"wachstum":
				v += (0.4 if crowded else 0.0) + (0.15 if s.age < 20.0 else 0.0)
				why = "Unser Haus ist zu eng." if crowded else "Wir wollen eine größere Familie."
			"bauen":
				v += (m.trait_value("fleiss") - 5.0) / 12.0 + (0.15 if float(m.talents.get("bauen", 1.0)) >= 1.3 or float(m.talents.get("handwerk", 1.0)) >= 1.3 else 0.0)
				why = "Mit Werkstätten geht alles leichter."
			"wissen":
				v += (m.trait_value("iq") - 5.0) / 8.0
				why = "Wissen bringt uns weiter."
			"sicherheit":
				if float(sc.get("sicherheit", 0.0)) > 0.0:
					v += (5.0 - m.trait_value("gemuet")) / 12.0
				why = "Die wilden Tiere machen mir Angst."
			"seefahrt":
				v += (m.trait_value("gemuet") - 5.0) / 12.0
				why = "Hinter dem Meer warten neue Inseln."
		if k == st.strategy:
			v += 0.1
		v += r.randf_range(-0.08, 0.08)
		op[k] = [v, why]
	return op


func _tally(votes: Array) -> Dictionary:
	var c := {}
	for v in votes:
		c[v.strat] = int(c.get(v.strat, 0)) + 1
	return c


func _winner(votes: Array, prefer: String, sc: Dictionary) -> String:
	var c := _tally(votes)
	var top := 0
	for k in c:
		top = max(top, int(c[k]))
	var tied: Array = c.keys().filter(func(k): return int(c[k]) == top)
	if prefer in tied:
		return prefer  # Gleichstand: es bleibt, wie es ist
	tied.sort_custom(func(a, b): return float(sc.get(a, 0.0)) > float(sc.get(b, 0.0)))
	return tied[0] if not tied.is_empty() else prefer


func tally_text(votes: Array) -> String:
	var c := _tally(votes)
	var parts := []
	for k in c:
		parts.append("%s %d" % [strat_name(k), int(c[k])])
	return ", ".join(parts)


func _council(w) -> void:
	var sit := situation(w)
	_make_households(w, sit)
	var reps := representatives(w)
	if reps.is_empty():
		return
	var st := state(w)
	var sc := situation_scores(w, sit)
	var votes := []
	for s in reps:
		var op := opinion(s, w, sc)
		var best := ""
		var bv := -INF
		for k in op:
			if float(op[k][0]) > bv:
				bv = float(op[k][0])
				best = k
		votes.append({"sid": s.id, "name": s.display_name, "house": household_of(s).get("name", ""), "strat": best, "why": op[best][1]})
	st.votes = votes
	for v in votes:
		decide(w, "Rat: %s stimmt für „%s“. „%s“" % [v.name, strat_name(v.strat), v.why])
	var win := _winner(votes, st.strategy, sc)
	var where := Sea.island_name(w)
	if win == st.strategy:
		log_line(w, "Der Rat bleibt bei „%s“ (%s)." % [strat_name(win), tally_text(votes)])
		Game.notify_at(w, "Der Inselrat hat getagt und bleibt bei „%s“." % strat_name(win), "glocke")
	else:
		add_request(w, "strategie", "Neue Strategie: %s" % strat_name(win),
			"Der Rat von %s möchte die Strategie ändern: „%s“ statt „%s“. Abstimmung: %s." % [where, strat_name(win), strat_name(st.strategy), tally_text(votes)],
			{"strat": win}, ["ja", "besprechen", "bestimmen"])
	_council_requests(w, sit)
	changed.emit()


func set_strategy(w, k: String, how: String) -> void:
	var st := state(w)
	st.strategy = k
	st.since = Game.time_days
	# Wer für diese Strategie gestimmt hat, fühlt sich gehört
	st.heard = st.votes.filter(func(v): return v.strat == k).map(func(v): return int(v.sid))
	log_line(w, "Neue Strategie: „%s“. %s" % [strat_name(k), how])
	Game.notify_at(w, "Neue Strategie: %s. %s" % [strat_name(k), how], "glocke")
	st.next_think = 0.0
	changed.emit()


# ================================================================== Anliegen an den Herrscher
func add_request(w, kind: String, title: String, text: String, data: Dictionary = {}, opts: Array = ["ja", "nein"]) -> void:
	var id := int(w.island_id)
	for r in requests:
		if int(r.isl) == id and r.kind == kind:
			return  # nur ein Anliegen je Art
	var st := state(w)
	if Game.time_days < float(st.cool.get(kind, 0.0)):
		return
	var who := ""
	var reps := representatives(w)
	if not reps.is_empty():
		who = reps[_rng.randi() % reps.size()].display_name
	requests.append({"id": next_req, "isl": id, "kind": kind, "title": title, "text": text, "who": who,
		"made": Game.time_days, "until": Game.time_days + float(cfg("request_days", 1.0)), "data": data, "opts": opts})
	next_req += 1
	decide(w, "Anliegen an dich: %s" % title)
	Game.notify_at(w, "Anliegen an den Herrscher: %s" % title, "glocke")
	changed.emit()


func requests_of(id: int) -> Array:
	return requests.filter(func(r): return int(r.isl) == id)


func request_by_id(rid: int) -> Dictionary:
	for r in requests:
		if int(r.id) == rid:
			return r
	return {}


func _world_of(id: int):
	return Sea.worlds.get(id)


func _close(r: Dictionary) -> void:
	requests.erase(r)
	var w = _world_of(int(r.isl))
	if w:
		state(w).cool[r.kind] = Game.time_days + float(cfg("council_days", 2.0)) * 0.75
	changed.emit()


## Der Herrscher antwortet auf ein Anliegen. answer: "ja" oder "nein".
func answer(rid: int, ans: String) -> String:
	var r := request_by_id(rid)
	if r.is_empty():
		return "Dieses Anliegen gibt es nicht mehr."
	var w = _world_of(int(r.isl))
	if w == null:
		_close(r)
		return ""
	var msg := ""
	if ans == "ja":
		msg = _carry_out(w, r, "der Herrscher hat zugestimmt")
		if msg == "":
			_add_trust(w, "agree")
			log_line(w, "Herrscher stimmt zu: %s." % r.title)
	else:
		_add_trust(w, "reject")
		log_line(w, "Herrscher lehnt ab: %s." % r.title)
		Game.notify_at(w, "Der Herrscher lehnt ab: %s." % r.title, "glocke")
	if msg == "":
		_close(r)
	return msg


func _expire_requests() -> void:
	for r in requests.duplicate():
		if Game.time_days < float(r.until):
			continue
		var w = _world_of(int(r.isl))
		if w == null:
			_close(r)
			continue
		# Ohne Antwort entscheidet der Rat selbst
		if r.kind in ["strategie", "bau", "forschung", "ueberstunden"]:
			_carry_out(w, r, "ohne Antwort hat der Rat selbst entschieden")
			if r.kind != "strategie":
				log_line(w, "Ohne Antwort entschieden: %s." % r.title)
		else:
			_add_trust(w, "ignored")
			log_line(w, "Keine Antwort auf: %s." % r.title)
		_close(r)


## Führt ein Anliegen aus. Gibt "" zurück oder warum es (gerade) nicht geht.
func _carry_out(w, r: Dictionary, how: String) -> String:
	var d: Dictionary = r.data
	match r.kind:
		"strategie":
			set_strategy(w, d.strat, how.substr(0, 1).to_upper() + how.substr(1) + ".")
		"bau":
			if d.has("upgrade"):
				var b = w.building_by_id(int(d.upgrade))
				if b == null or not b.complete or w.upgrade_building(b) == null:
					return "Das Haus kann gerade nicht ausgebaut werden."
				Game.notify_at(w, "Der Rat lässt %s ausbauen (%s)." % [b.def.name, how], "hammer")
			else:
				var c := find_spot(w, d.type)
				if c.x < 0:
					return "Es gibt keinen freien Platz für %s." % Data.buildings[d.type].name
				w.place_building(d.type, c, false)
				Game.notify_at(w, "Der Rat lässt bauen: %s (%s)." % [Data.buildings[d.type].name, how], "hammer")
		"forschung":
			if Game.research.current != "":
				return ""
			var err := Game.start_research(d.tech)
			if err != "":
				Game.notify_at(w, "Forschung %s: %s" % [Data.techs[d.tech].name, err], "wissen")
				return err if how.begins_with("der Herrscher") else ""
			Game.notify_at(w, "Die Siedler forschen jetzt an %s (%s)." % [Data.techs[d.tech].name, how], "wissen")
		"fest":
			_festival(w)
		"freizeit":
			state(w).leisure_until = Game.time_days + float(cfg("leisure_days", 2.0))
			Game.notify_at(w, "Mehr Freizeit auf %s: die Siedler arbeiten zwei Tage gemütlicher." % Sea.island_name(w), "sonne")
		"ueberstunden":
			state(w).overtime_until = Game.time_days + float(cfg("overtime_days", 2.0))
			Game.notify_at(w, "Die Siedler auf %s machen Überstunden." % Sea.island_name(w), "hammer")
		"hilfe":
			var from = _world_of(int(d.from))
			var sh := Sea.ship_by_id(int(d.ship))
			if from == null or sh.is_empty():
				return "Das Schiff ist nicht mehr da."
			Sea.fill_crew(sh)
			if Sea.crew_missing(sh) > 0:
				Sea.hire_sailor(sh)
			var goods := {}
			for id in d.goods:
				var n: int = min(int(d.goods[id]), Game.amount(id, from))
				if n > 0:
					goods[id] = n
			var err := Sea.send_ship(from, int(r.isl), [], sh, goods)
			if err != "":
				return err
			_add_trust(w, "help")
	return ""


func _festival(w) -> void:
	var st := state(w)
	var need: int = int(cfg("festival_food_per_head", 2)) * w.settlers.size()
	# Das Fest isst von dem, was am meisten da ist
	var foods := Data.resources.keys().filter(func(id): return Data.resources[id].get("category", "") == "food")
	foods.sort_custom(func(a, b): return Game.amount(a, w) > Game.amount(b, w))
	for id in foods:
		if need <= 0:
			break
		need -= Game.take_stock(id, min(need, Game.amount(id, w)), w)
	st.festival_until = Game.time_days + float(cfg("festival_days", 1.0))
	Game.notify_at(w, "Fest auf %s! Die Siedler feiern, essen gut und arbeiten heute weniger." % Sea.island_name(w), "musik")
	Sound.play_on("glocke", w)


## Forderungen und Angebote, die der Rat nach seiner Sitzung stellt.
func _council_requests(w, sit: Dictionary) -> void:
	var mood := 0.0
	var tired := 0
	for s in w.settlers:
		mood += s.mind.mood
		if s.is_adult() and s.mind.rest < 25.0:
			tired += 1
	mood /= maxf(1.0, w.settlers.size())
	var st := state(w)
	if mood < 45.0 and float(sit.food_head) > 6.0 and Game.time_days > float(st.festival_until) + 3.0:
		add_request(w, "fest", "Ein Fest feiern",
			"Die Stimmung ist schlecht. Die Siedler wünschen sich ein Fest. Kosten: etwa %d Essen, einen halben Arbeitstag." % (int(cfg("festival_food_per_head", 2)) * w.settlers.size()))
	elif int(Seasons.season()) == Seasons.AUTUMN and Seasons.day_in_season() == 1 and float(sit.food_head) > 10.0:
		add_request(w, "fest", "Erntefest",
			"Die Ernte ist eingebracht. Die Siedler möchten ein Erntefest feiern (etwa %d Essen)." % (int(cfg("festival_food_per_head", 2)) * w.settlers.size()))
	if tired >= max(2, int(sit.adults) / 3) and Game.time_days > float(st.leisure_until):
		add_request(w, "freizeit", "Weniger Arbeit",
			"%d Siedler sind überarbeitet. Sie fordern zwei Tage mit mehr Freizeit (es wird langsamer gearbeitet)." % tired)
	var wood_short: bool = int(sit.season) in [Seasons.SUMMER, Seasons.AUTUMN] and float(sit.wood) < float(sit.wood_target) * 0.6
	if (wood_short or float(sit.food_head) < 4.0) and Game.time_days > float(st.overtime_until):
		add_request(w, "ueberstunden", "Angebot: Überstunden",
			"Die Siedler bieten an, zwei Tage lang mehr zu arbeiten, damit %s reicht. Das drückt die Laune." % ("das Holz" if wood_short else "das Essen"))


# ================================================================== KI baut
## Was soll auf der Insel als nächstes gebaut werden? Kleine Bauten setzt der Rat selbst,
## große legt er dem Herrscher vor.
func _plan_buildings(w) -> void:
	if w.fire_building() == null:
		return
	var sit := situation(w)
	# Essen geht vor: fehlen Felder, legt der Rat sofort eines an (kostet wenig)
	if int(sit.season) in [Seasons.SPRING, Seasons.SUMMER] \
			and _count(w, ["feld", "obstgarten"]) < ceili(int(sit.pop) / 2.5) and Game.can_afford(Data.buildings.feld.cost, w):
		var t := "feld"
		if Game.is_unlocked("obstgarten") and _count(w, ["obstgarten"]) * 3 < _count(w, ["feld"]) and int(sit.vit_low) > 0:
			t = "obstgarten"
		var fc := find_spot(w, t)
		if fc.x >= 0:
			w.place_building(t, fc, false)
			log_line(w, "Der Rat legt an: %s." % Data.buildings[t].name)
			Game.notify_at(w, "Der Rat legt an: %s. Mehr Felder bringen mehr Essen." % Data.buildings[t].name, "weizen")
			return
	if w.construction_sites().size() >= 2:
		return
	var pick := _choose_building(w, sit)
	if pick.is_empty():
		return
	var cost := 0
	var def: Dictionary = Data.buildings[pick.type]
	for id in def.get("cost", {}):
		cost += int(def.cost[id])
	var title: String = ("%s ausbauen" % Data.buildings[w.building_by_id(int(pick.upgrade)).type].name) if pick.has("upgrade") \
		else "%s bauen" % def.name
	if cost <= int(cfg("small_build_cost", 30)) and not pick.has("upgrade"):
		var c := find_spot(w, pick.type)
		if c.x >= 0:
			w.place_building(pick.type, c, false)
			log_line(w, "Der Rat lässt bauen: %s. %s" % [def.name, pick.why])
			Game.notify_at(w, "Der Rat lässt bauen: %s. %s" % [def.name, pick.why], "hammer")
		return
	var costs := []
	for id in def.get("cost", {}):
		costs.append("%d %s" % [int(def.cost[id]), Data.resource_name(id)])
	add_request(w, "bau", title, "%s Kosten: %s." % [pick.why, ", ".join(costs)], pick)


func _count(w, types: Array) -> int:
	return w.buildings.filter(func(b): return b.type in types or b.def.get("base", "") in types).size()


func _choose_building(w, sit: Dictionary) -> Dictionary:
	var strat: String = state(w).strategy
	var cats: Array = strategies().get(strat, {}).get("build", [])
	var cands := []
	# Wohnen: wenn es eng wird
	if int(sit.pop) + 1 >= int(sit.housing) and (float(sit.food_head) > 4.0 or strat == "wachstum"):
		for b in w.buildings:
			var to: String = b.def.get("upgrade", "")
			if b.complete and b.housing() > 0 and to != "" and Game.is_unlocked(to) and Game.can_afford(Data.buildings[to].cost, w):
				cands.append({"type": to, "upgrade": b.id, "why": "Mehr Platz für Familien.", "cat": "wohnen"})
				break
		for t in HOUSE_ORDER:
			if Game.is_unlocked(t) and Data.buildings[t].get("buildable", true) and Game.can_afford(Data.buildings[t].cost, w):
				cands.append({"type": t, "why": "Die Häuser sind voll (%d Siedler, %d Plätze)." % [int(sit.pop), int(sit.housing)], "cat": "wohnen"})
				break
	# Lager: wenn es voll wird
	# (Nicht, wenn das Lager nur voller Holz und Stein im Überfluss ist)
	if float(sit.storage_full) > 0.85 and float(sit.wood) < float(sit.wood_target) * 3.0 and float(sit.stone) < float(sit.stone_target) * 5.0:
		var t := "grosslager" if Game.is_unlocked("grosslager") and Game.can_afford(Data.buildings.grosslager.cost, w) else "lager"
		if Game.can_afford(Data.buildings[t].cost, w):
			cands.append({"type": t, "why": "Das Lager ist fast voll.", "cat": "lager"})
	# Felder und Gärten
	if int(sit.season) in [Seasons.SPRING, Seasons.SUMMER] and int(sit.farms) < ceili(int(sit.pop) / 3.0) \
			and (strat in ["nahrung", "wachstum", "winter"] or float(sit.food_head) < 8.0):
		var t := "feld"
		if Game.is_unlocked("obstgarten") and _count(w, ["obstgarten"]) * 3 < int(sit.farms) and int(sit.vit_low) > 0:
			t = "obstgarten"
		if Game.can_afford(Data.buildings[t].cost, w):
			cands.append({"type": t, "why": "Mehr Felder bringen mehr Essen.", "cat": "nahrung"})
	# Werkstätten und Ketten: was freigeschaltet, aber noch nicht da ist
	for t in PROD_ORDER:
		if Game.is_unlocked(t) and _count(w, [t]) == 0 and Game.can_afford(Data.buildings[t].cost, w):
			if t == "baeckerei" and _count(w, ["muehle"]) == 0:
				continue
			if t == "muehle" and int(sit.farms) == 0:
				continue
			cands.append({"type": t, "why": "%s fehlt noch auf der Insel." % Data.buildings[t].name, "cat": Data.buildings[t].category})
	# Wissen
	for t in ["schreibstube", "bibliothek", "universitaet", "labor"]:
		if Game.is_unlocked(t) and _count(w, [t]) == 0 and Game.can_afford(Data.buildings[t].cost, w):
			cands.append({"type": t, "why": "Ein Ort zum Forschen und Lernen.", "cat": "wissen"})
			break
	if Game.is_unlocked("schule") and int(sit.kids) >= 3 and _count(w, ["schule"]) == 0 and Game.can_afford(Data.buildings.schule.cost, w):
		cands.append({"type": "schule", "why": "%d Kinder sollen lernen." % int(sit.kids), "cat": "wohnen"})
	# Schutz
	if Game.is_unlocked("wachturm") and int(sit.predators) > 0 and _count(w, ["wachturm"]) < 1 + int(sit.predators) / 4 \
			and Game.can_afford(Data.buildings.wachturm.cost, w):
		cands.append({"type": "wachturm", "why": "Wilde Tiere greifen an.", "cat": "schutz"})
	# Seefahrt
	if strat == "seefahrt":
		for t in ["werft", "anlegesteg", "hafen"]:
			if Game.is_unlocked(t) and _count(w, [t]) == 0 and Game.can_afford(Data.buildings[t].cost, w):
				cands.append({"type": t, "why": "Für Schiffe und Handel.", "cat": "see"})
				break
	if cands.is_empty():
		return {}
	# Wohnen und Lager bei Not zuerst, sonst was zur Strategie passt
	for c in cands:
		if c.cat in ["wohnen", "lager"] and (c.type in HOUSE_ORDER or c.has("upgrade") or c.cat == "lager"):
			if not c.has("upgrade") or strat == "wachstum" or float(sit.food_head) > 8.0:
				return c
	for c in cands:
		if c.cat in cats:
			return c
	# Andere Bauten nur, wenn genug Essen da ist
	if float(sit.food_head) > 8.0:
		return cands[0]
	return {}


## Freier Platz für ein Gebäude nahe dem Lagerfeuer, mit einem Feld Abstand zu anderen Gebäuden.
func find_spot(w, type: String) -> Vector2i:
	var fire = w.fire_building()
	var c0: Vector2i = fire.cell if fire else w.center
	var def: Dictionary = Data.buildings[type]
	var sz := Vector2i(int(def.size[0]), int(def.size[1]))
	var r := RandomNumberGenerator.new()
	r.seed = hash(int(w.island_id) * 101 + w.buildings.size())
	for rad in range(3, 26):
		var ring := []
		for y in range(-rad, rad + 1):
			for x in range(-rad, rad + 1):
				if max(abs(x), abs(y)) == rad:
					ring.append(c0 + Vector2i(x, y))
		for i in ring.size():
			var j := r.randi_range(i, ring.size() - 1)
			var tmp = ring[i]
			ring[i] = ring[j]
			ring[j] = tmp
		for c in ring:
			if w.can_place(type, c) and _has_margin(w, c, sz):
				return c
	return Vector2i(-1, -1)


func _has_margin(w, c: Vector2i, sz: Vector2i) -> bool:
	for y in range(-1, sz.y + 2):
		for x in range(-1, sz.x + 1):
			var cc := c + Vector2i(x, y)
			if w.building_at.has(cc):
				return false
	return true


# ================================================================== KI forscht
func _check_research(w) -> void:
	if Game.research.current != "":
		return
	# Forschung ist gemeinsam: die Insel mit den meisten Siedlern schlägt vor
	for o in Sea.all_worlds():
		if o.settlers.size() > w.settlers.size():
			return
	var t := choose_research(state(w).strategy, w)
	if t == "":
		return
	add_request(w, "forschung", "Forschung: %s" % Data.techs[t].name,
		"Die Gelehrten möchten %s erforschen. %s" % [Data.techs[t].name, Data.techs[t].get("desc", "")], {"tech": t})


func choose_research(strat: String, w) -> String:
	var keys: Array = {
		"nahrung": ["farm", "gather_beeren", "gather_fisch", "hunger", "spoil"],
		"winter": ["storage", "spoil", "gather_holz", "warm"],
		"wachstum": ["birth", "life", "heal", "build"],
		"bauen": ["build", "work", "production", "gather_holz", "gather_stein", "carry"],
		"wissen": ["research"],
		"sicherheit": ["weapons", "hunt", "tower"],
		"seefahrt": ["ship", "explore"],
	}.get(strat, [])
	var best := ""
	var best_v := -INF
	for t in Data.sorted_tech_ids():
		if Game.tech_state(t) != "available":
			continue
		var def: Dictionary = Data.techs[t]
		var v := -float(def.get("tier", 1)) * 2.0 - float(def.get("points", 100)) / 400.0
		for k in def.get("effects", {}):
			for key in keys:
				if k.begins_with(key):
					v += 3.0
		# Schaltet ein Gebäude frei, das zur Strategie passt?
		for b in Data.buildings:
			if Data.buildings[b].get("requires", "") == t and Data.buildings[b].get("category", "") in strategies().get(strat, {}).get("build", []):
				v += 2.5
		if Game.can_afford(def.get("cost", {}), w):
			v += 1.5
		# Mehr Siedler brauchen Felder, Mühle und Bäckerei: Nahrungsbauten sind immer wichtig
		if w.settlers.size() >= 5:
			for b in Data.buildings:
				if Data.buildings[b].get("requires", "") == t and Data.buildings[b].get("category", "") == "nahrung":
					v += 3.0
		if v > best_v:
			best_v = v
			best = t
	return best


# ================================================================== Hilfe zwischen Inseln
func _check_help(w) -> void:
	var sit := situation(w)
	var need := {}
	if float(sit.food_head) < 3.0:
		need["food"] = int(sit.pop) * 6
	if int(sit.season) in [Seasons.AUTUMN, Seasons.WINTER] and float(sit.wood) < float(sit.heat) * 0.4:
		need["holz"] = int(float(sit.heat) * 0.6)
	if need.is_empty():
		return
	for o in Sea.all_worlds():
		if o == w or o.settlers.is_empty():
			continue
		var osit := situation(o)
		var goods := {}
		if need.has("food") and float(osit.food_head) > 15.0:
			var foods := Data.resources.keys().filter(func(id): return Data.resources[id].get("category", "") == "food")
			foods.sort_custom(func(a, b): return Game.amount(a, o) > Game.amount(b, o))
			goods[foods[0]] = min(int(need.food), Game.amount(foods[0], o) / 3)
		if need.has("holz") and float(osit.wood) > float(osit.wood_target) + 20.0:
			goods["holz"] = min(int(need.holz), int(float(osit.wood) - float(osit.wood_target)))
		if goods.is_empty():
			continue
		for sh in Sea.idle_ships(int(o.island_id)):
			if Sea.can_visit(sh.type, int(w.island_id)):
				add_request(w, "hilfe", "Hilfe von %s" % Sea.island_name(o),
					"%s ist in Not. Die Siedler bitten: %s soll mit der %s %s schicken." % [Sea.island_name(w), Sea.island_name(o), sh.name, Sea.goods_text(goods)],
					{"from": int(o.island_id), "ship": int(sh.id), "goods": goods})
				return


# ================================================================== Diskussion
## Der Herrscher schlägt dem Rat einer Insel eine Strategie vor und diskutiert.
func start_debate(w, strat: String, rid: int = 0) -> void:
	var sit := situation(w)
	_make_households(w, sit)
	var sc := situation_scores(w, sit)
	var reps := []
	for s in representatives(w):
		var op := opinion(s, w, sc)
		var own := ""
		var bv := -INF
		for k in op:
			if float(op[k][0]) > bv:
				bv = float(op[k][0])
				own = k
		# Jeder hängt ein wenig an seiner eigenen Meinung
		var resist := maxf(0.0, bv - float(op.get(strat, [0.0])[0])) + (float(cfg("stubborn", 0.2)) if own != strat else 0.0)
		reps.append({"sid": s.id, "name": s.display_name, "house": household_of(s).get("name", ""), "own": own,
			"why": op[own][1], "resist": resist, "power": 0.0, "yes": own == strat})
	debate = {"isl": int(w.island_id), "strat": strat, "rid": rid, "reps": reps, "used": [], "lines": [], "done": false, "won": false}
	for r in reps:
		if r.yes:
			debate.lines.append([r.name, "Ich bin sowieso für „%s“." % strat_name(strat)])
		else:
			debate.lines.append([r.name, "Ich bin für „%s“. %s" % [strat_name(r.own), r.why]])
	_check_majority()
	changed.emit()


## Argumente, die der Herrscher vorbringen kann.
func arguments() -> Array:
	if debate.is_empty():
		return []
	var w = _world_of(int(debate.isl))
	var out := []
	for a in [["lage", "Auf die Lage zeigen"], ["gemeinwohl", "An das Gemeinwohl appellieren"],
			["fest", "Ein Fest versprechen"], ["freizeit", "Mehr Freizeit versprechen"]]:
		if a[0] in debate.used:
			continue
		var text: String = a[1]
		if a[0] == "lage":
			text += ": " + fact(w, debate.strat)
		out.append([a[0], text])
	return out


## Eine wahre Aussage über die Lage, die für die Strategie spricht.
func fact(w, strat: String) -> String:
	var sit := situation(w)
	match strat:
		"nahrung":
			return "Wir haben nur %d Essen je Kopf." % int(sit.food_head)
		"winter":
			return "Wir haben %d Holz, bis zum Frühling brauchen wir etwa %d." % [int(sit.wood), int(sit.wood_target)]
		"wachstum":
			return "%d Siedler wohnen auf %d Plätzen." % [int(sit.pop), int(sit.housing)]
		"bauen":
			return "Mit Werkstätten wird jede Arbeit leichter."
		"wissen":
			return "Jede Forschung macht uns stärker."
		"sicherheit":
			return "Auf der Insel leben %d Raubtiere." % int(sit.predators)
		"seefahrt":
			return "Auf anderen Inseln gibt es neue Rohstoffe."
	return ""


func argue(arg: String) -> void:
	if debate.is_empty() or debate.done or arg in debate.used:
		return
	var w = _world_of(int(debate.isl))
	if w == null:
		return
	debate.used.append(arg)
	var sc := situation_scores(w)
	var tr := lerpf(0.4, 1.4, trust(w) / 100.0)
	var any := false
	var said := {"lage": "Seht euch die Lage an: %s" % fact(w, debate.strat),
		"gemeinwohl": "Denkt an alle Inseln und an eure Kinder. Wir schaffen das nur gemeinsam.",
		"fest": "Wenn ihr zustimmt, feiern wir ein Fest.",
		"freizeit": "Wenn ihr zustimmt, bekommt ihr zwei Tage mehr Freizeit."}
	debate.lines.append(["Du", said[arg]])
	for r in debate.reps:
		if r.yes:
			continue
		var s = _settler(w, int(r.sid))
		if s == null:
			continue
		var p := 0.0
		match arg:
			"lage":
				p = maxf(0.0, float(sc.get(debate.strat, 0.0))) * (0.5 + s.mind.trait_value("iq") / 10.0)
			"gemeinwohl":
				p = 0.35 * s.mind.trait_value("gemuet") / 7.0
			"fest":
				p = 0.45
			"freizeit":
				p = 0.4 * (1.0 + (10.0 - s.mind.trait_value("fleiss")) / 20.0)
		r.power = float(r.power) + p * tr
		if float(r.power) >= float(r.resist):
			r.yes = true
			any = true
			debate.lines.append([r.name, ["Gut, das überzeugt mich.", "Du hast recht, ich stimme zu.", "Na gut, versuchen wir es."][_rng.randi() % 3]])
		else:
			debate.lines.append([r.name, "Das überzeugt mich nicht. %s" % r.why])
	if not any:
		_add_trust(w, "argument_failed")
	if arg in ["fest", "freizeit"]:
		if not debate.has("promises"):
			debate.promises = []
		debate.promises.append(arg)
	_check_majority()
	changed.emit()


func debate_yes() -> int:
	return debate.get("reps", []).filter(func(r): return r.yes).size()


func _check_majority() -> void:
	var n: int = debate.reps.size()
	if n == 0 or debate_yes() * 2 <= n:
		if arguments().is_empty():
			debate.done = true
		return
	debate.done = true
	debate.won = true
	var w = _world_of(int(debate.isl))
	debate.lines.append(["Rat", "Der Rat stimmt „%s“ zu (%d von %d)." % [strat_name(debate.strat), debate_yes(), n]])
	if w:
		_add_trust(w, "persuaded")
		for p in debate.get("promises", []):
			if p == "fest":
				_festival(w)
			else:
				state(w).leisure_until = Game.time_days + float(cfg("leisure_days", 2.0))
			_add_trust(w, "promise_kept")
		set_strategy(w, debate.strat, "Der Herrscher hat den Rat überzeugt.")
		_close_debate_request()


func _close_debate_request() -> void:
	var r := request_by_id(int(debate.get("rid", 0)))
	if not r.is_empty():
		_close(r)


## Der Herrscher bestimmt, ohne den Rat zu überzeugen.
func command(w, strat: String) -> void:
	_add_trust(w, "command")
	state(w).resent_until = Game.time_days + float(cfg("resent_days", 2.0))
	set_strategy(w, strat, "Der Herrscher hat es bestimmt.")
	if not debate.is_empty() and int(debate.isl) == int(w.island_id):
		debate.done = true
		_close_debate_request()
	for r in requests_of(int(w.island_id)):
		if r.kind == "strategie":
			_close(r)
			break


## Nach der Diskussion nachgeben: der Rat behält seine Mehrheit.
func give_in() -> void:
	if debate.is_empty():
		return
	var w = _world_of(int(debate.isl))
	var r := request_by_id(int(debate.get("rid", 0)))
	if w and not r.is_empty():
		answer(int(r.id), "ja")
	debate = {}
	changed.emit()


# ================================================================== Wirkungen
## Faktor auf das Arbeitstempo (Fest, Freizeit, Überstunden).
func work_mult(w) -> float:
	if not enabled or w == null:
		return 1.0
	var st := state(w)
	var t := Game.time_days
	var wk: Dictionary = cfg("work", {})
	if t < float(st.festival_until):
		return float(wk.get("festival", 0.6))
	var f := 1.0
	if t < float(st.leisure_until):
		f *= float(wk.get("leisure", 0.85))
	if t < float(st.overtime_until):
		f *= float(wk.get("overtime", 1.2))
	return f


## Gründe für die Laune aus Rat und Herrschaft.
func mood_reasons(s) -> Array:
	if not enabled or s.world == null:
		return []
	var st := state(s.world)
	var t := Game.time_days
	var md: Dictionary = cfg("mood", {})
	var r := []
	var tv := (float(st.trust) - 50.0) * float(md.get("trust_per_point", 0.2))
	if absf(tv) >= 2.0:
		r.append(["Vertraut dem Herrscher" if tv > 0 else "Misstraut dem Herrscher", tv])
	if t < float(st.festival_until):
		r.append(["Feiert ein Fest", float(md.get("festival", 14))])
	if t < float(st.leisure_until):
		r.append(["Hat mehr Freizeit", float(md.get("leisure", 6))])
	if t < float(st.overtime_until) and s.is_adult():
		r.append(["Macht Überstunden", float(md.get("overtime", -8))])
	if t < float(st.resent_until):
		r.append(["Der Herrscher hat über den Rat hinweg bestimmt", float(md.get("resent", -8))])
	if int(s.id) in st.get("heard", []):
		r.append(["Der Rat ist seiner Meinung gefolgt", float(md.get("heard", 3))])
	return r


func on_attack(w) -> void:
	if enabled and w:
		state(w).attacks = float(state(w).attacks) + 1.0


## Der Herrscher gibt einem Siedler einen Beruf vor (gilt einen Tag lang).
func order_job(s) -> void:
	if enabled:
		orders[s.id] = Game.time_days + 1.0
		thoughts[s.id] = "Der Herrscher hat mich zum %s bestimmt. Das mache ich." % s.job_name()
