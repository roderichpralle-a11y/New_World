extends Node
## Lernende KI für die Berufswahl (josh 2026-11-07, nur Testversion /v21test2/).
## Ein kleines Netz (lineare Strategie, 8 Berufe x FEATURES Eingänge) liest den Zustand der Insel (Jahreszeit,
## Vorräte, Hunger, Laune, Siedler, Natur, jetzige Berufe) und gibt je Beruf einen Anteil an den Erwachsenen.
## Gelernt mit Augmented Random Search (ARS, Mania u. a. 2018) in tools/ki_train/train.py: das Spiel läuft ohne
## Grafik ab joshs Spielstand Tag 163, jede Strategie spielt 3 oder 12 Spieltage, die Punkte (siehe score_day)
## entscheiden, in welche Richtung die Gewichte wandern. Im Spiel kostet eine Entscheidung nur 8 x 39 Multiplikationen
## alle Viertel-Tage, also nichts, auch auf dem iPhone.
## Die KI vergibt nur Produktionsberufe (JOBS). Verwalter, Seeleute und Forscher fasst sie nie an; Baumeister nach
## einer festen Regel (Baustellen). Vom Spieler eingeteilte Siedler bleiben, Freie nimmt sie immer.

const JOBS := ["holzfaeller", "steinmetz", "sammler", "fischer", "bauer", "koch", "handwerker", "jaeger", "forscher"]
const FEATURES := 50
const RESEARCH_PTS := 1.0        # je Forschungspunkt (josh 2026-11-07, Vorschlag)
const RESEARCH_DONE_PTS := 100.0 # je fertiger Forschung
const NEEDED_PTS := 3.0          # verarbeitete Ware, die der nächsten Forschung noch fehlt
const TICK_DAYS := 0.25
const HOLD_DAYS := 0.5
const BRAIN_PATH := "res://data/ki_brain.json"
const PROCESSED_PTS := 2.0
const DEATH_PTS := -20.0
const WOOD_CAP := 1000

var on := false             # Schalter im Fenster Verwalter (Spielstand)
## Im Browser nur mit ?ki in der Adresse (josh 2026-11-07: /v21test2/ ohne „Berufe vergeben“, die KI unter
## /v21test2/?ki); außerhalb des Browsers (Tests, Training) immer.
var available := true
var _kept_on := false  # Schalter aus dem Spielstand, solange die KI hier nicht verfügbar ist (bleibt beim Speichern erhalten)
var weights: Array = []     # JOBS.size() Zeilen mit FEATURES Zahlen
var brain_score := 0        # aus der Datei: Punkte im Prüflauf (12 Tage ab Tag 163)
var brain_base := 0         # ... und untrainiert
var _next := 0.0

# Punkte (Training und Anzeige)
var processed_today := 0.0
var deaths_today := 0
var research_today := 0.0
var finished_today := 0
var target := ""            # Forschung, auf die die KI hinarbeitet (läuft schon oder als Nächstes)
var score_log: Array = []   # je Tag {day, food, wood, proc, sat, mood, dead, total}
var score_total := 0.0
var _score_day := -1
var _score_t0 := 0.0


func _ready() -> void:
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)
	Game.settler_died.connect(func(_s, _c): deaths_today += 1)
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("window.location.search", true))
		available = RegEx.create_from_string("[?&]ki(=|&|$)").search(q) != null
	_load_weights(BRAIN_PATH)


func _load_weights(path: String) -> bool:
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		return false
	var d = JSON.parse_string(txt)
	if not d is Dictionary or not d.get("w") is Array:
		return false
	var w: Array = d.w
	if w.is_empty() or w.size() > JOBS.size():
		return false
	# ältere Gewichte (weniger Berufe oder Eingänge) mit Nullen auffüllen
	var out: Array = []
	for i in JOBS.size():
		var row: Array = (w[i] as Array).duplicate() if i < w.size() else []
		while row.size() < FEATURES:
			row.append(0.0)
		out.append(row)
	weights = out
	brain_score = int(d.get("score", 0))
	brain_base = int(d.get("base", 0))
	return true


func set_weights_file(path: String) -> bool:
	return _load_weights(path)


## Steuert die KI auf dieser Insel die Berufe?
func controls(w) -> bool:
	return on and available and not weights.is_empty() and w != null and is_instance_valid(w) \
		and (Sea.is_main(w) or Powers.covers(w))  # Nebeninseln nur mit Rundfunkanstalt hier und dort (josh 2026-11-07)


func set_on(v: bool) -> void:
	on = v and available
	_next = 0.0


# ---------------------------------------------------------------- Ablauf
func _process(_delta: float) -> void:
	if Game.world == null or Game.speed == 0:
		return
	if score_on:
		_score_tick()
	if not on or weights.is_empty() or Game.time_days < _next:
		return
	_next = Game.time_days + TICK_DAYS
	for w in Sea.all_worlds():
		if controls(w):
			tick(w)


func _adults(w) -> Array:
	return w.settlers.filter(func(s): return is_instance_valid(s) and s.is_adult())


## Darf die KI diesen Siedler umsetzen?
func _movable(s) -> bool:
	if s.job in ["verwalter", "seemann"]:
		return false
	if JobDesk.player_controlled(s):
		return false  # Schalter „Spieler“ in der Siedlerliste (josh 2026-11-07)
	if s.job == "frei":
		return true  # Freie nimmt sie immer (josh hat sie für die KI freigestellt)
	return JobDesk.may(s, "ki")


func tick(w) -> void:
	if Sea.is_main(w):
		research_tick()
		build_tick(w)
	var adults := _adults(w)
	var pool: Array = adults.filter(func(s): return _movable(s))
	if pool.is_empty():
		return
	var want := targets(w, pool.size())
	var count := {}
	for s in pool:
		count[s.job] = int(count.get(s.job, 0)) + 1
	var budget := 2 + pool.size() / 6
	while budget > 0:
		# größte Lücke zuerst
		var gap_job := ""
		var gap := 0
		for j in want:
			var g := int(want[j]) - int(count.get(j, 0))
			if g > gap:
				gap = g
				gap_job = j
		if gap_job == "":
			break
		# woher: Freie, dann Berufe über dem Soll
		var cands: Array = pool.filter(func(s): return s.job == "frei")
		if cands.is_empty():
			cands = pool.filter(func(s): return s.job != gap_job and int(count.get(s.job, 0)) > int(want.get(s.job, 0)))
		if cands.is_empty():
			break
		var pick = Steward._pick(w, cands, gap_job)
		if pick == null:
			break
		count[pick.job] = int(count.get(pick.job, 0)) - 1
		count[gap_job] = int(count.get(gap_job, 0)) + 1
		JobDesk.assign(pick, gap_job, "ki", HOLD_DAYS, true)
		budget -= 1


## Forschung (josh 2026-11-07): hat der Spieler nichts gewählt, nimmt die KI die nächste noch nicht erforschte
## Forschung der Liste (Stufe, dann Punkte) und startet sie, sobald die Kosten im Lager liegen.
func research_tick() -> void:
	if Game.research.current != "":
		target = Game.research.current
		return
	var nx := str(Game.research.get("next", ""))
	if nx != "" and Game.tech_state(nx) == "available":
		target = nx
	else:
		target = ""
		for t in Data.sorted_tech_ids():
			if Game.tech_state(t) == "available":
				target = t
				break
	if target != "" and Game.start_research(target) == "":
		Game.notify(Loc.t("KI: Forschung gestartet: %s") % Data.techs[target].name, "wissen")


## Bauen für die Forschung (josh 2026-11-07, Karte „KI darf auch bauen“): fehlt der Ziel-Forschung eine Ware und
## steht auf der Insel keine Werkstatt dafür, legt die KI eine Baustelle an (nur erforschte Gebäude, höchstens
## eine eigene Baustelle zugleich). Fehlen der Werkstatt Zutaten ohne Werkstatt, geht sie eine Stufe zurück.
## Das ist eine feste Regel; was gelernt wird, ist die Einteilung der Leute (auch Steinmetze, Handwerker für das Material).
var _build_next := 0.0
const BUILD_DAYS := 0.5

func build_tick(w) -> void:
	if Game.time_days < _build_next:
		return
	_build_next = Game.time_days + BUILD_DAYS
	if w.buildings.any(func(b): return not b.complete and b.has_meta("ki_site")):
		return
	for id in research_missing():
		var t := _missing_maker(w, str(id), 0)
		if t == "":
			continue
		var c = _spot(w, t)
		if c == null:
			continue
		var b = w.place_building(t, c, false)
		b.set_meta("ki_site", true)
		Game.notify_at(w, Loc.t("KI baut: %s (für die Forschung %s)") % [Data.buildings[t].name, Data.techs[target].name], "hammer")
		return


## Welche Werkstatt fehlt, damit `id` entstehen kann? "" = keine nötig oder keine möglich.
func _missing_maker(w, id: String, depth: int) -> String:
	if depth > 2:
		return ""
	var t: String = Steward._maker_type(id)
	if t == "" or not Game.is_unlocked(t):
		return ""
	var have = null
	for b in w.buildings:
		if b.type == t or str(b.def.get("base", "")) == t:
			have = b
			break
	if have == null:
		return t
	if not have.complete:
		return ""
	var ins: Dictionary = Data.buildings[t].production.get("inputs", {})
	for r in ins:
		if Game.amount(r, w) < int(ins[r]) * 2:
			var sub := _missing_maker(w, str(r), depth + 1)
			if sub != "":
				return sub
	return ""


func _spot(w, type: String):
	var sz: Array = Data.buildings[type].size
	var center: Vector2i = w.center
	for rad in range(3, 30):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var cc: Vector2i = center + Vector2i(dx, dy)
				if not w.can_place(type, cc):
					continue
				var ok := true
				for y in range(-1, int(sz[1]) + 2):
					for x in range(-1, int(sz[0]) + 1):
						var p := cc + Vector2i(x, y)
						if w.building_at.has(p) or not w.is_walkable(p):
							ok = false
				if ok:
					return cc
	return null


## Was der Ziel-Forschung im Lager noch fehlt {Ware: Menge} (leer, wenn sie läuft oder bezahlt ist).
func research_missing() -> Dictionary:
	var out := {}
	if target == "" or target in Game.research.paid:
		return out
	var cost: Dictionary = Data.techs.get(target, {}).get("cost", {})
	var mw = Sea.main_world()
	for id in cost:
		var miss := int(cost[id]) - Game.amount(id, mw)
		if miss > 0:
			out[id] = miss
	return out


## Soll je Beruf für `n` umsetzbare Erwachsene (Baumeister nach Regel, Rest nach dem Netz).
func targets(w, n: int) -> Dictionary:
	var out := {}
	var sites: int = w.construction_sites().size() + w.repair_sites().size()
	var bm := 0
	if sites > 0:
		bm = mini(1 + sites / 2, maxi(1, n / 3))
	out["baumeister"] = bm
	var rest := n - bm
	var caps := capacities(w)
	var x := features(w)
	var logits := []
	var best := -INF
	for i in JOBS.size():
		var row: Array = weights[i]
		var z := 0.0
		for k in FEATURES:
			z += float(row[k]) * x[k]
		if int(caps[JOBS[i]]) <= 0:
			z = -INF
		logits.append(z)
		best = maxf(best, z)
	if best == -INF:
		return out
	var p := []
	var sum := 0.0
	for z in logits:
		var e: float = 0.0 if z == -INF else exp(clampf(z - best, -30.0, 0.0))
		p.append(e)
		sum += e
	# Anteile auf Plätze verteilen (Obergrenzen je Beruf, Überschuss an die anderen)
	var share := {}
	for i in JOBS.size():
		share[JOBS[i]] = p[i] / sum
	var alloc := {}
	var left := float(rest)
	var open: Array = JOBS.filter(func(j): return float(share[j]) > 0.0)
	for _round in 8:
		if left <= 0.001 or open.is_empty():
			break
		var tot := 0.0
		for j in open:
			tot += float(share[j])
		var next_open := []
		var used := 0.0
		for j in open:
			var add := left * float(share[j]) / tot
			var cur := float(alloc.get(j, 0.0))
			var cap := float(caps[j])
			if cur + add >= cap:
				add = cap - cur
			else:
				next_open.append(j)
			alloc[j] = cur + add
			used += add
		left -= used
		open = next_open
	# ganze Leute: abrunden, Rest nach größtem Bruchteil
	var whole := 0
	var fr := []
	for j in alloc:
		var v := float(alloc[j])
		out[j] = int(floor(v))
		whole += int(out[j])
		fr.append([v - floor(v), j])
	fr.sort_custom(func(a, b): return a[0] > b[0])
	var rem := rest - whole
	for e in fr:
		if rem <= 0:
			break
		if int(out[e[1]]) < int(caps[e[1]]):
			out[e[1]] = int(out[e[1]]) + 1
			rem -= 1
	return out


## Wie viele Leute in jedem Beruf überhaupt Arbeit finden können.
func capacities(w) -> Dictionary:
	var c := {"holzfaeller": 99, "sammler": 99, "fischer": 99, "steinmetz": 0, "bauer": 0, "koch": 0, "handwerker": 0, "jaeger": 0, "forscher": 0}
	var researching: bool = Game.research.current != "" and Sea.is_main(w)
	var fields := 0
	for b in w.buildings:
		if not b.complete:
			continue
		if b.def.has("farm"):
			fields += 1
		elif b.def.has("research"):
			if researching:
				c["forscher"] = int(c.forscher) + b.slots()
		elif b.def.has("production") and not b.paused and not b.def.get("ships", false):
			var j: String = Steward.KIND_JOB.get(b.prod_def().get("job", ""), "")
			if c.has(j):
				c[j] = int(c[j]) + b.slots()
	c["bauer"] = int(c.bauer) + int(ceil(fields / float(Steward.FIELDS_PER_FARMER)))
	var rocks := 0
	var fish := 0
	for nd in w.nodes:
		if not is_instance_valid(nd):
			continue
		if str(nd.type) == "fischgrund":
			fish += 1  # Fischgründe wachsen nach: alle zählen
		elif int(nd.amount) > 0 and str(nd.def.get("yield", "")) in ["stein", "erz"]:
			rocks += 1
	c["steinmetz"] = int(c.steinmetz) + mini(rocks, 3)
	c["fischer"] = maxi(0, fish * 2)
	var wild := 0
	for a in w.animals:
		if is_instance_valid(a) and not a.dead:
			wild += 1
	c["jaeger"] = mini(3, (wild + 3) / 4)
	return c


func _amt(id: String, w) -> float:
	return float(Game.amount(id, w))


## Eingänge des Netzes, alle etwa zwischen 0 und 1.
func features(w) -> PackedFloat32Array:
	var x := PackedFloat32Array()
	x.resize(FEATURES)
	x[0] = 1.0
	var se := Seasons.season()
	x[1 + se] = 1.0
	x[5] = fposmod(Game.time_days, Seasons.season_days()) / Seasons.season_days()
	x[6] = minf(food_days(w) / 10.0, 3.0)
	x[7] = minf(_amt("beeren", w) / 100.0, 3.0)
	x[8] = minf(_amt("fisch", w) / 100.0, 3.0)
	x[9] = minf(_amt("weizen", w) / 200.0, 3.0)
	x[10] = minf(_amt("aepfel", w) / 100.0, 3.0)
	x[11] = minf(_amt("mehl", w) / 100.0, 3.0)
	x[12] = minf((_amt("brot", w) + _amt("raeucherfisch", w) + _amt("eier", w) + _amt("milch", w) + _amt("fleisch", w)) / 100.0, 3.0)
	var i := 13
	for id in ["holz", "kohle", "bretter", "stein", "lehm", "erz", "ziegel", "tontafel"]:
		var div := 1000.0 if id == "holz" else (100.0 if id == "lehm" else 200.0)
		x[i] = minf(_amt(id, w) / div, 3.0)
		i += 1
	# 21..24 Sättigung und Laune
	var n := 0
	var sat := 0.0
	var hungry := 0
	var mood := 0.0
	var sad := 0
	for s in w.settlers:
		if not is_instance_valid(s):
			continue
		n += 1
		sat += float(s.hunger)
		mood += float(s.mind.mood)
		if s.hunger < 50.0:
			hungry += 1
		if s.mind.mood < 50.0:
			sad += 1
	if n > 0:
		x[21] = sat / n / 100.0
		x[22] = float(hungry) / n
		x[23] = mood / n / 100.0
		x[24] = float(sad) / n
	var adults := _adults(w)
	x[25] = adults.size() / 20.0
	x[26] = (n - adults.size()) / 20.0
	var fuel := _amt("holz", w) + 2.0 * _amt("kohle", w)
	x[27] = minf(fuel / (Steward.fuel_per_day(w) + 5.0) / 10.0, 3.0)
	x[28] = float(Game.used_volume(w)) / maxf(1.0, float(Game.storage_volume(w)))
	var trees := 0
	var bushes := 0
	for nd in w.nodes:
		if not is_instance_valid(nd) or int(nd.amount) <= 0:
			continue
		if str(nd.type) == "baum":
			trees += 1
		elif str(nd.type) in ["busch", "palme", "pilzkreis"]:
			bushes += 1
	x[29] = minf(trees / 60.0, 3.0)
	x[30] = minf(bushes / 40.0, 3.0)
	if not adults.is_empty():
		for s in adults:
			var k := JOBS.find(s.job)
			if k >= 0 and k < 8:
				x[31 + k] += 1.0 / adults.size()
			elif s.job == "forscher":
				x[49] += 1.0 / adults.size()
	# 39..48 Forschung
	var cur := str(Game.research.current)
	x[39] = 1.0 if cur != "" else 0.0
	if cur != "":
		x[40] = clampf(Game.tech_progress(cur) / maxf(1.0, Game.tech_points(cur)), 0.0, 1.0)
	var miss := research_missing()
	x[41] = minf(float(miss.get("eisen", 0)) / 20.0, 3.0)
	x[42] = minf(float(miss.get("werkzeug", 0)) / 20.0, 3.0)
	x[43] = minf(float(miss.get("kohle", 0)) / 20.0, 3.0)
	x[44] = minf(float(miss.get("bretter", 0)) / 40.0, 3.0)
	x[45] = minf(float(miss.get("ziegel", 0)) / 40.0, 3.0)
	var other := 0.0
	for id in miss:
		if not id in ["eisen", "werkzeug", "kohle", "bretter", "ziegel"]:
			other += float(miss[id])
	x[46] = minf(other / 40.0, 3.0)
	x[47] = minf(_amt("eisen", w) / 50.0, 3.0)
	x[48] = minf(_amt("werkzeug", w) / 50.0, 3.0)
	return x


## Nahrung im Lager in Tagen für alle Siedler.
func food_days(w) -> float:
	var sat := 0.0
	for id in Data.food_ids():
		sat += _amt(id, w) * Data.food_satiety(id)
	var need := Steward._need_per_head(w) * maxf(1.0, float(w.settlers.size()))
	return sat / maxf(1.0, need)


# ---------------------------------------------------------------- Punkte (josh 2026-11-07)
## Je Spieltag: 1 Punkt je Nahrungstag im Lager, 1 je 100 Holz (höchstens 1000 Holz), 2 je an diesem Tag
## verarbeitetem Gut (alles, was eine Werkstatt, ein Stall, Steinbruch oder Mine herstellt), 1 je Siedler über
## 50 satt, 1 je Siedler über 50 zufrieden, -20 je gestorbenem Siedler.
var score_on := false

func note_processed(res: String, n: int) -> void:
	processed_today += float(n) * (NEEDED_PTS if research_missing().has(res) else PROCESSED_PTS)


func note_research(points: float) -> void:
	research_today += points


func note_research_done() -> void:
	finished_today += 1


func score_start() -> void:
	score_on = true
	score_log = []
	score_total = 0.0
	processed_today = 0.0
	deaths_today = 0
	research_today = 0.0
	finished_today = 0
	_score_t0 = Game.time_days
	_score_day = 0


func _score_tick() -> void:
	var d := int(floor(Game.time_days - _score_t0))
	if d == _score_day:
		return
	_score_day = d
	score_day()


func score_day() -> Dictionary:
	var w = Game.world
	var r := {"day": int(floor(Game.time_days))}
	r["food"] = food_days(w)
	r["wood"] = minf(_amt("holz", w), WOOD_CAP) / 100.0
	r["proc"] = processed_today
	r["res"] = RESEARCH_PTS * research_today + RESEARCH_DONE_PTS * finished_today
	r["rpts"] = research_today
	var sat := 0
	var mood := 0
	for s in w.settlers:
		if is_instance_valid(s):
			if s.hunger > 50.0:
				sat += 1
			if s.mind.mood > 50.0:
				mood += 1
	r["sat"] = sat
	r["mood"] = mood
	r["dead"] = DEATH_PTS * deaths_today
	r["pop"] = w.settlers.size()
	r["total"] = float(r.food) + float(r.wood) + float(r.proc) + float(r.res) + sat + mood + float(r.dead)
	score_total += float(r.total)
	score_log.append(r)
	processed_today = 0.0
	deaths_today = 0
	research_today = 0.0
	finished_today = 0
	return r


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	on = false
	_kept_on = false
	_next = 0.0


func _on_save(d: Dictionary) -> void:
	d["ki_brain"] = {"on": on or (_kept_on and not available)}


func _on_load(data: Dictionary, _old_rules: int) -> void:
	_on_reset()
	var k = data.get("ki_brain", null)
	if k is Dictionary:
		_kept_on = bool(k.get("on", false))
		on = _kept_on and available
