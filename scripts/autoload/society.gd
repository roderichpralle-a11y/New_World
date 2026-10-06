extends Node
## KI-Variante (Webadresse mit /ki/): Die Siedler steuern sich selbst.
##
## - Jeder Siedler bekommt vom Inselrat einen Auftrag und befolgt ihn (KiMind, ki_mind.gd).
##   Was er denkt, steht in `thoughts` (Infofenster).
## - Die Bewohner eines Hauses sind die kleinste Gruppe. Die Häuser sprechen sich ab,
##   wer sich um welchen Bereich kümmert (Nahrung, Rohstoffe, Bauen, Wissen, Schutz).
##   Mitglieder einer kranken Person pflegen sie (heilt schneller).
## - Jede Insel hat einen Rat aus je einem Sprecher pro Haus. Er tagt in KiMind (Schwerpunkt,
##   Arbeit, Bauen, Forschung, Handel). Die Strategie gewichtet Berufe, Bauten und Forschung;
##   die Sprecher reden in Diskussionen mit dem Herrscher mit (`opinion`).
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
	KiMind.reset()


func serialize() -> Dictionary:
	var out := {}
	for id in isl:
		out[str(id)] = isl[id]
	var ord := {}
	for sid in orders:
		ord[str(sid)] = orders[sid]
	return {"isl": out, "requests": requests, "next_req": next_req, "orders": ord, "welcomed": welcomed, "mind": KiMind.serialize()}


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
	KiMind.load_from(d.get("mind", {}))


# ================================================================== Takt
func _process(_delta: float) -> void:
	if not enabled or Game.world == null or Game.is_over or Game.speed <= 0:
		return
	var t := Game.time_days
	if not welcomed:
		welcomed = true
		Game.notify(tr("KI-Version: Der Inselrat verteilt die Arbeit, baut und forscht. Jedes Haus schickt einen Sprecher in den Rat."), "ki", "rat")
		Game.notify(tr("Du bist der Herrscher. Unter „Rat“ findest du die Anliegen der Inseln: zustimmen, diskutieren oder bestimmen."), "glocke", "rat")
	for w in Sea.all_worlds():
		if w.settlers.is_empty():
			continue
		var st := state(w)
		# Rat und Aufträge der Siedler kommen aus KiMind, hier bleibt die Pflege der Häuser
		if t >= float(st.next_think):
			st.next_think = t + float(cfg("think_days", 0.25))
			_make_households(w, situation(w))
			_care(w, float(cfg("think_days", 0.25)))
			st.attacks = maxf(0.0, float(st.attacks) - 0.5 * float(cfg("think_days", 0.25)))
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
		var name: String = (tr("%s von %s") % [home.def.name, sp.display_name]) if home else tr("Am Lagerfeuer")
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
				thoughts[o.id] = tr("Ich pflege %s (%s). %s") % [s.display_name, s.mind.illness_name(), thoughts.get(o.id, "")]
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
				why = tr("Wir haben Hunger.") if hunger < 45.0 else tr("Die Vorräte sind zu knapp.")
			"winter":
				v += (6.0 - m.trait_value("konst")) / 12.0
				why = tr("Der Winter kommt, wir brauchen Holz und Vorräte.") if int(Seasons.season()) != Seasons.WINTER else tr("Wir frieren, wir brauchen Holz.")
			"wachstum":
				v += (0.4 if crowded else 0.0) + (0.15 if s.age < 20.0 else 0.0)
				why = tr("Unser Haus ist zu eng.") if crowded else tr("Wir wollen eine größere Familie.")
			"bauen":
				v += (m.trait_value("fleiss") - 5.0) / 12.0 + (0.15 if float(m.talents.get("bauen", 1.0)) >= 1.3 or float(m.talents.get("handwerk", 1.0)) >= 1.3 else 0.0)
				why = tr("Mit Werkstätten geht alles leichter.")
			"wissen":
				v += (m.trait_value("iq") - 5.0) / 8.0
				why = tr("Wissen bringt uns weiter.")
			"sicherheit":
				if float(sc.get("sicherheit", 0.0)) > 0.0:
					v += (5.0 - m.trait_value("gemuet")) / 12.0
				why = tr("Die wilden Tiere machen mir Angst.")
			"seefahrt":
				v += (m.trait_value("gemuet") - 5.0) / 12.0
				why = tr("Hinter dem Meer warten neue Inseln.")
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


func tally_text(votes: Array) -> String:
	var c := _tally(votes)
	var parts := []
	for k in c:
		parts.append("%s %d" % [strat_name(k), int(c[k])])
	return ", ".join(parts)


func set_strategy(w, k: String, how: String) -> void:
	var st := state(w)
	st.strategy = k
	st.since = Game.time_days
	# Wer für diese Strategie gestimmt hat, fühlt sich gehört
	st.heard = st.votes.filter(func(v): return v.strat == k).map(func(v): return int(v.sid))
	log_line(w, tr("Neue Strategie: „%s“. %s") % [strat_name(k), how])
	Game.notify_at(w, tr("Neue Strategie: %s. %s") % [strat_name(k), how], "glocke", "rat")
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
	decide(w, tr("Anliegen an dich: %s") % title)
	Game.notify_at(w, tr("Anliegen an den Herrscher: %s") % title, "glocke", "rat")
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
		return tr("Dieses Anliegen gibt es nicht mehr.")
	var w = _world_of(int(r.isl))
	if w == null:
		_close(r)
		return ""
	var msg := ""
	if ans == "ja":
		msg = _carry_out(w, r, tr("der Herrscher hat zugestimmt"))
		if msg == "":
			_add_trust(w, "agree")
			log_line(w, tr("Herrscher stimmt zu: %s.") % r.title)
	else:
		_add_trust(w, "reject")
		log_line(w, tr("Herrscher lehnt ab: %s.") % r.title)
		Game.notify_at(w, tr("Der Herrscher lehnt ab: %s.") % r.title, "glocke", "rat")
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
			_carry_out(w, r, tr("ohne Antwort hat der Rat selbst entschieden"))
			if r.kind != "strategie":
				log_line(w, tr("Ohne Antwort entschieden: %s.") % r.title)
		else:
			_add_trust(w, "ignored")
			log_line(w, tr("Keine Antwort auf: %s.") % r.title)
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
					return tr("Das Haus kann gerade nicht ausgebaut werden.")
				Game.notify_at(w, tr("Der Rat lässt %s ausbauen (%s).") % [b.def.name, how], "hammer", "rat_bau")
			else:
				var c := find_spot(w, d.type)
				if c.x < 0:
					return tr("Es gibt keinen freien Platz für %s.") % Data.buildings[d.type].name
				w.place_building(d.type, c, false)
				Game.notify_at(w, tr("Der Rat lässt bauen: %s (%s).") % [Data.buildings[d.type].name, how], "hammer", "rat_bau")
		"forschung":
			if Game.research.current != "":
				return ""
			var err := Game.start_research(d.tech)
			if err != "":
				Game.notify_at(w, tr("Forschung %s: %s") % [Data.techs[d.tech].name, err], "wissen", "rat_bau")
				return err if how.begins_with(tr("der Herrscher")) else ""
			Game.notify_at(w, tr("Die Siedler forschen jetzt an %s (%s).") % [Data.techs[d.tech].name, how], "wissen", "rat_bau")
		"fest":
			_festival(w)
		"freizeit":
			state(w).leisure_until = Game.time_days + float(cfg("leisure_days", 2.0))
			Game.notify_at(w, tr("Mehr Freizeit auf %s: die Siedler arbeiten zwei Tage gemütlicher.") % Sea.island_name(w), "sonne", "rat")
		"ueberstunden":
			state(w).overtime_until = Game.time_days + float(cfg("overtime_days", 2.0))
			Game.notify_at(w, tr("Die Siedler auf %s machen Überstunden.") % Sea.island_name(w), "hammer", "rat_bau")
		"hilfe":
			var from = _world_of(int(d.from))
			var sh := Sea.ship_by_id(int(d.ship))
			if from == null or sh.is_empty():
				return tr("Das Schiff ist nicht mehr da.")
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
	Game.notify_at(w, tr("Fest auf %s! Die Siedler feiern, essen gut und arbeiten heute weniger.") % Sea.island_name(w), "musik", "rat")
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
		add_request(w, "fest", tr("Ein Fest feiern"),
			tr("Die Stimmung ist schlecht. Die Siedler wünschen sich ein Fest. Kosten: etwa %d Essen, einen halben Arbeitstag.") % (int(cfg("festival_food_per_head", 2)) * w.settlers.size()))
	elif int(Seasons.season()) == Seasons.AUTUMN and Seasons.day_in_season() == 1 and float(sit.food_head) > 10.0:
		add_request(w, "fest", tr("Erntefest"),
			tr("Die Ernte ist eingebracht. Die Siedler möchten ein Erntefest feiern (etwa %d Essen).") % (int(cfg("festival_food_per_head", 2)) * w.settlers.size()))
	if tired >= max(2, int(sit.adults) / 3) and Game.time_days > float(st.leisure_until):
		add_request(w, "freizeit", tr("Weniger Arbeit"),
			tr("%d Siedler sind überarbeitet. Sie fordern zwei Tage mit mehr Freizeit (es wird langsamer gearbeitet).") % tired)
	var wood_short: bool = int(sit.season) in [Seasons.SUMMER, Seasons.AUTUMN] and float(sit.wood) < float(sit.wood_target) * 0.6
	if (wood_short or float(sit.food_head) < 4.0) and Game.time_days > float(st.overtime_until):
		add_request(w, "ueberstunden", tr("Angebot: Überstunden"),
			tr("Die Siedler bieten an, zwei Tage lang mehr zu arbeiten, damit %s reicht. Das drückt die Laune.") % (tr("das Holz") if wood_short else tr("das Essen")))


# ================================================================== KI baut


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
				cands.append({"type": to, "upgrade": b.id, "why": tr("Mehr Platz für Familien."), "cat": "wohnen"})
				break
		for t in HOUSE_ORDER:
			if Game.is_unlocked(t) and Data.buildings[t].get("buildable", true) and Game.can_afford(Data.buildings[t].cost, w):
				cands.append({"type": t, "why": tr("Die Häuser sind voll (%d Siedler, %d Plätze).") % [int(sit.pop), int(sit.housing)], "cat": "wohnen"})
				break
	# Lager: wenn es voll wird
	# (Nicht, wenn das Lager nur voller Holz und Stein im Überfluss ist)
	if float(sit.storage_full) > 0.85 and float(sit.wood) < float(sit.wood_target) * 3.0 and float(sit.stone) < float(sit.stone_target) * 5.0:
		var t := "grosslager" if Game.is_unlocked("grosslager") and Game.can_afford(Data.buildings.grosslager.cost, w) else "lager"
		if Game.can_afford(Data.buildings[t].cost, w):
			cands.append({"type": t, "why": tr("Das Lager ist fast voll."), "cat": "lager"})
	# Felder und Gärten
	if int(sit.season) in [Seasons.SPRING, Seasons.SUMMER] and int(sit.farms) < ceili(int(sit.pop) / 3.0) \
			and (strat in ["nahrung", "wachstum", "winter"] or float(sit.food_head) < 8.0):
		var t := "feld"
		if Game.is_unlocked("obstgarten") and _count(w, ["obstgarten"]) * 3 < int(sit.farms) and int(sit.vit_low) > 0:
			t = "obstgarten"
		if Game.can_afford(Data.buildings[t].cost, w):
			cands.append({"type": t, "why": tr("Mehr Felder bringen mehr Essen."), "cat": "nahrung"})
	# Werkstätten und Ketten: was freigeschaltet, aber noch nicht da ist
	for t in PROD_ORDER:
		if Game.is_unlocked(t) and _count(w, [t]) == 0 and Game.can_afford(Data.buildings[t].cost, w):
			if t == "baeckerei" and _count(w, ["muehle"]) == 0:
				continue
			if t == "muehle" and int(sit.farms) == 0:
				continue
			cands.append({"type": t, "why": tr("%s fehlt noch auf der Insel.") % Data.buildings[t].name, "cat": Data.buildings[t].category})
	# Wissen
	for t in ["schreibstube", "bibliothek", "universitaet", "labor"]:
		if Game.is_unlocked(t) and _count(w, [t]) == 0 and Game.can_afford(Data.buildings[t].cost, w):
			cands.append({"type": t, "why": tr("Ein Ort zum Forschen und Lernen."), "cat": "wissen"})
			break
	if Game.is_unlocked("schule") and int(sit.kids) >= 3 and _count(w, ["schule"]) == 0 and Game.can_afford(Data.buildings.schule.cost, w):
		cands.append({"type": "schule", "why": tr("%d Kinder sollen lernen.") % int(sit.kids), "cat": "wohnen"})
	# Schutz
	if Game.is_unlocked("wachturm") and int(sit.predators) > 0 and _count(w, ["wachturm"]) < 1 + int(sit.predators) / 4 \
			and Game.can_afford(Data.buildings.wachturm.cost, w):
		cands.append({"type": "wachturm", "why": tr("Wilde Tiere greifen an."), "cat": "schutz"})
	# Seefahrt
	if strat == "seefahrt":
		for t in ["werft", "anlegesteg", "hafen"]:
			if Game.is_unlocked(t) and _count(w, [t]) == 0 and Game.can_afford(Data.buildings[t].cost, w):
				cands.append({"type": t, "why": tr("Für Schiffe und Handel."), "cat": "see"})
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
			debate.lines.append([r.name, tr("Ich bin sowieso für „%s“.") % strat_name(strat)])
		else:
			debate.lines.append([r.name, tr("Ich bin für „%s“. %s") % [strat_name(r.own), r.why]])
	_check_majority()
	changed.emit()


## Argumente, die der Herrscher vorbringen kann.
func arguments() -> Array:
	if debate.is_empty():
		return []
	var w = _world_of(int(debate.isl))
	var out := []
	for a in [["lage", tr("Auf die Lage zeigen")], ["gemeinwohl", tr("An das Gemeinwohl appellieren")],
			["fest", tr("Ein Fest versprechen")], ["freizeit", tr("Mehr Freizeit versprechen")]]:
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
			return tr("Wir haben nur %d Essen je Kopf.") % int(sit.food_head)
		"winter":
			return tr("Wir haben %d Holz, bis zum Frühling brauchen wir etwa %d.") % [int(sit.wood), int(sit.wood_target)]
		"wachstum":
			return tr("%d Siedler wohnen auf %d Plätzen.") % [int(sit.pop), int(sit.housing)]
		"bauen":
			return tr("Mit Werkstätten wird jede Arbeit leichter.")
		"wissen":
			return tr("Jede Forschung macht uns stärker.")
		"sicherheit":
			return tr("Auf der Insel leben %d Raubtiere.") % int(sit.predators)
		"seefahrt":
			return tr("Auf anderen Inseln gibt es neue Rohstoffe.")
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
	var said := {"lage": tr("Seht euch die Lage an: %s") % fact(w, debate.strat),
		"gemeinwohl": tr("Denkt an alle Inseln und an eure Kinder. Wir schaffen das nur gemeinsam."),
		"fest": tr("Wenn ihr zustimmt, feiern wir ein Fest."),
		"freizeit": tr("Wenn ihr zustimmt, bekommt ihr zwei Tage mehr Freizeit.")}
	debate.lines.append([tr("Du"), said[arg]])
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
			debate.lines.append([r.name, [tr("Gut, das überzeugt mich."), tr("Du hast recht, ich stimme zu."), tr("Na gut, versuchen wir es.")][_rng.randi() % 3]])
		else:
			debate.lines.append([r.name, tr("Das überzeugt mich nicht. %s") % r.why])
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
	debate.lines.append(["Rat", tr("Der Rat stimmt „%s“ zu (%d von %d).") % [strat_name(debate.strat), debate_yes(), n]])
	if w:
		_add_trust(w, "persuaded")
		for p in debate.get("promises", []):
			if p == "fest":
				_festival(w)
			else:
				state(w).leisure_until = Game.time_days + float(cfg("leisure_days", 2.0))
			_add_trust(w, "promise_kept")
		set_strategy(w, debate.strat, tr("Der Herrscher hat den Rat überzeugt."))
		_close_debate_request()


func _close_debate_request() -> void:
	var r := request_by_id(int(debate.get("rid", 0)))
	if not r.is_empty():
		_close(r)


## Der Herrscher bestimmt, ohne den Rat zu überzeugen.
func command(w, strat: String) -> void:
	_add_trust(w, "command")
	state(w).resent_until = Game.time_days + float(cfg("resent_days", 2.0))
	set_strategy(w, strat, tr("Der Herrscher hat es bestimmt."))
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
		r.append([tr("Vertraut dem Herrscher") if tv > 0 else tr("Misstraut dem Herrscher"), tv])
	if t < float(st.festival_until):
		r.append([tr("Feiert ein Fest"), float(md.get("festival", 14))])
	if t < float(st.leisure_until):
		r.append([tr("Hat mehr Freizeit"), float(md.get("leisure", 6))])
	if t < float(st.overtime_until) and s.is_adult():
		r.append([tr("Macht Überstunden"), float(md.get("overtime", -8))])
	if t < float(st.resent_until):
		r.append([tr("Der Herrscher hat über den Rat hinweg bestimmt"), float(md.get("resent", -8))])
	if int(s.id) in st.get("heard", []):
		r.append([tr("Der Rat ist seiner Meinung gefolgt"), float(md.get("heard", 3))])
	return r


func on_attack(w) -> void:
	if enabled and w:
		state(w).attacks = float(state(w).attacks) + 1.0


## Der Herrscher gibt einem Siedler einen Beruf vor (gilt einen Tag lang).
func order_job(s) -> void:
	if enabled:
		orders[s.id] = Game.time_days + 1.0
		thoughts[s.id] = tr("Der Herrscher hat mich zum %s bestimmt. Das mache ich.") % s.job_name()
