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

const JOBS := ["holzfaeller", "steinmetz", "sammler", "fischer", "bauer", "koch", "handwerker", "jaeger", "forscher", "foerster", "frei"]
const OLD_JOBS := 9      # so viele Berufe kennen die Gewichte bis 3.0.19; Förster und „frei“ nur mit neuen Gewichten
const FEATURES := 96
## Ganzes Spiel (josh 2026-11-15): jede Handlung aus KiActs.names() hat eine Zeile mit FEATURES + ACT_X Gewichten
## (die letzten ACT_X Eingänge beschreiben die Handlung selbst, z. B. wie viele Gebäude dieser Art schon stehen).
const ACT_X := 4
const TECH_F := 12       # Eingänge der Forschungswahl (KiActs.tech_features)
## Bau-Handlungen (josh 2026-11-11, Stufe 1 des Plans): je eine Zeile Gewichte. Gelernt wird, WAS und WANN gebaut
## wird; WO, sucht das Spiel (Planner.spot, Straßen auf den meistbegangenen Feldern). „Nichts“ hat den Wert 0.
const BUILD_ACTS := ["haus", "ausbau", "lager", "feld", "obstgarten", "strasse", "werft", "schiff", "erkunden", "besiedeln"]
const LEARN_BUILD_DAYS := 0.5
var max_sites := 2  # höchstens so viele eigene Baustellen zugleich
const RESEARCH_WHOLE_PTS := 500.0 # eine ganze Forschung, anteilig nach Fortschritt, gleich in jedem Zeitalter (josh 2026-11-08)
const RESEARCH_DONE_PTS := 0.0   # kein Extra mehr für fertige Forschung (steckt in den 500)
const NEEDED_PTS := 3.0          # verarbeitete Ware, die der nächsten Forschung noch fehlt
const TICK_DAYS := 0.25
const HOLD_DAYS := 0.5
const BRAIN_PATH := "res://data/ki_brain.json"
const PROCESSED_PTS := 2.0
const DEATH_PTS := -100.0
const WOOD_CAP := 1000
# Wertung 2 (josh 2026-11-15, „Übernimm die Vorschläge für die Bewertung“)
const RESERVE_PTS := 10.0        # je Tag für eine volle Winterreserve (Extras.heat_reserve), statt 1 je 100 Holz
const FOOD_DAYS_CAP := 10.0      # Nahrungstage zählen höchstens bis 10, roher Weizen (raw_food) zählt nicht
const DISTRESS_PTS := -1.0       # je Siedler-Tag mit Hunger (unter 25) oder Kälte (Insel ohne Brennstoff)
const HUNGRY_BELOW := 25.0
const AGE_PTS := 1000.0          # je neu erreichtem Zeitalter (bestandene Prüfung)
const ISLAND_PTS := 20.0         # je bewohnter Nebeninsel und Tag
const SUPPLY_PTS := 1.0          # je Erz oder Kohle, das ein Schiff auf einer Insel ablädt
const WORK_PTS := 20.0           # je Tag mal Anteil der Erwachsenen, die gerade in ihrem Beruf arbeiten
const SAMPLE_DAYS := 0.25
# Ziel des ganzen Spiels (josh 2026-11-15: „bis alles erforscht und die Zukunftsstadt gebaut ist“, „Droiden, bis alle
# Menschen frei sind“). Diese zwei Werte hat Claude gesetzt, josh kann sie ändern.
const GOAL_PTS := 20000.0        # einmal, wenn die Zukunftsstadt fertig steht
const DROID_PTS := 2.0           # je Tag und arbeitendem Droiden

var on := false             # Schalter im Fenster Verwalter (Spielstand)
## Im Browser nur mit ?ki in der Adresse (josh 2026-11-07: /v21test2/ ohne „Berufe vergeben“, die KI unter
## /v21test2/?ki); außerhalb des Browsers (Tests, Training) immer.
var available := true
var v3 := false        # Version 3 (josh 2026-11-08): die KI-Fassung unter /v3/, KI immer verfügbar und anfangs an
var _kept_on := false  # Schalter aus dem Spielstand, solange die KI hier nicht verfügbar ist (bleibt beim Speichern erhalten)
var weights: Array = []     # JOBS.size() Zeilen mit FEATURES Zahlen
var job_rows := OLD_JOBS    # so viele Berufe-Zeilen standen in der Datei (die übrigen Berufe vergibt die KI nicht)
var aweights: Dictionary = {}   # Handlung -> Zeile mit FEATURES + ACT_X Zahlen (leer = die KI baut nichts selbst)
var tweights: Array = []    # TECH_F Zahlen für die Wahl der Forschung (leer = feste Reihenfolge der Liste)
## Training: alles freigeschaltet, die KI steuert das ganze Spiel allein (--kifull=1). Im Spiel gilt die
## Freischalt-Liste KiActs.UNLOCK: jedes Gebäude gibt der KI eine Gruppe von Entscheidungen frei.
var train_all := false
var unlock_list := false    # Freischalt-Liste anwenden (Version 3 mit neuen Gewichten)
var trace_log: Array = []   # [Tag, Insel, Text] der letzten Entscheidungen (Training: Verlauf in der Oberfläche)
var goal_done := false      # Zukunftsstadt steht (Training: Spiel zu Ende)
## Wie oft war ein Eingang nicht 0 (Training, josh 2026-11-15): Gewichte von Eingängen, die nie vorkamen, lernen nichts
var feat_seen := PackedInt32Array()
var act_seen := PackedInt32Array()
var built_log: Dictionary = {}  # Handlung -> Anzahl (Training, Anzeige)
var _bnext: Dictionary = {}     # Insel-ID -> Spieltag der nächsten Bau-Entscheidung
var _last_build: Dictionary = {}  # Insel-ID -> Spieltag des letzten eigenen Baus
var brain_score := 0        # aus der Datei: Punkte im Prüflauf (12 Tage ab Tag 163)
var brain_base := 0         # ... und untrainiert
var brain_vs := 0           # aus der Datei: Prozent mehr Punkte als der Verwalter (4 Spielstände, 24 Tage)
var _next := 0.0

# Punkte (Training und Anzeige)
var processed_today := 0.0
var deaths_today := 0
var research_today := 0.0       # Anteil ganzer Forschungen heute x 500
var research_raw := 0.0         # rohe Forschungspunkte heute (nur zur Anzeige)
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
	if OS.has_feature("itch"):
		available = false  # itch.io-Fassung 2.1.0 ohne KI (josh 2026-11-07)
	elif OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("window.location.search", true))
		var path := str(JavaScriptBridge.eval("window.location.pathname", true))
		v3 = "/v3/" in path
		available = v3 or RegEx.create_from_string("[?&]ki(=|&|$)").search(q) != null
	if "--v3build" in OS.get_cmdline_user_args():
		v3 = true
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
	job_rows = clampi(w.size(), 1, JOBS.size())
	aweights = {}
	# alte Dateien: Zeilen "b" in der Reihenfolge BUILD_ACTS; neue: "a" {Handlung: Zeile}
	if d.get("b") is Array:
		for i in mini(BUILD_ACTS.size(), (d.b as Array).size()):
			aweights[BUILD_ACTS[i]] = _pad_act(d.b[i])
	if d.get("a") is Dictionary:
		for k in d.a:
			if d.a[k] is Array:
				aweights[str(k)] = _pad_act(d.a[k])
	tweights = []
	if d.get("t") is Array and not (d.t as Array).is_empty():
		tweights = (d.t as Array).duplicate()
		while tweights.size() < TECH_F:
			tweights.append(0.0)
	unlock_list = bool(d.get("full", false))
	_load_net(d.get("netz"))
	brain_score = int(d.get("score", 0))
	brain_base = int(d.get("base", 0))
	brain_vs = int(d.get("vs_verwalter", 0))
	return true


# ---------------------------------------------------------------- kleines neuronales Netz (josh 2026-11-16)
## Zusatz zu den linearen Gewichten: FEATURES Eingänge -> h1 -> h2 (ReLU) -> eine Korrektur je Handlung und Beruf.
## Die Korrektur wird zum linearen Wert addiert. Steht die letzte Schicht auf 0, spielt die KI genau wie ohne Netz;
## so bleibt das bisher Gelernte erhalten. Datei: "netz" = {h1, h2, aus: [Namen], w1, b1, w2, b2, w3, b3}
## (Berufe heißen in "aus" "job:<beruf>"). Gelernt wird mit tools/ki_voll (Einstellung netz).
var net_on := false
var _nh1 := 0
var _nh2 := 0
var _nout: Array = []
var _nw1 := PackedFloat32Array()
var _nb1 := PackedFloat32Array()
var _nw2 := PackedFloat32Array()
var _nb2 := PackedFloat32Array()
var _nw3 := PackedFloat32Array()
var _nb3 := PackedFloat32Array()
var _ncache: Dictionary = {}  # Insel -> [Tag, {Name: Korrektur}]


func _load_net(d) -> void:
	net_on = false
	_ncache = {}
	if not d is Dictionary or not d.get("aus") is Array:
		return
	var h1 := int(d.get("h1", 0))
	var h2 := int(d.get("h2", 0))
	var n: int = (d.aus as Array).size()
	var a1 := PackedFloat32Array(d.get("w1", []))
	var a2 := PackedFloat32Array(d.get("w2", []))
	var a3 := PackedFloat32Array(d.get("w3", []))
	if h1 <= 0 or h2 <= 0 or a1.size() != h1 * FEATURES or a2.size() != h2 * h1 or a3.size() != n * h2:
		push_warning("KI: Netz passt nicht zum Spiel, es wird nicht benutzt")
		return
	_nh1 = h1
	_nh2 = h2
	_nout = (d.aus as Array).map(func(x): return str(x))
	_nw1 = a1
	_nw2 = a2
	_nw3 = a3
	_nb1 = _pad_f(d.get("b1", []), h1)
	_nb2 = _pad_f(d.get("b2", []), h2)
	_nb3 = _pad_f(d.get("b3", []), n)
	net_on = true


func _pad_f(a, n: int) -> PackedFloat32Array:
	var p := PackedFloat32Array(a if a is Array else [])
	p.resize(n)
	return p


## Korrekturen des Netzes für diese Insel (je Viertelstunde Spielzeit einmal gerechnet).
func net_corr(w, x: PackedFloat32Array) -> Dictionary:
	if not net_on:
		return {}
	var iid := int(w.island_id)
	var c: Array = _ncache.get(iid, [])
	if c.size() == 2 and absf(Game.time_days - float(c[0])) < 0.01:
		return c[1]
	var h := PackedFloat32Array()
	h.resize(_nh1)
	for j in _nh1:
		var s := _nb1[j]
		var o := j * FEATURES
		for k in FEATURES:
			s += _nw1[o + k] * x[k]
		h[j] = maxf(0.0, s)
	var g := PackedFloat32Array()
	g.resize(_nh2)
	for j in _nh2:
		var s := _nb2[j]
		var o := j * _nh1
		for k in _nh1:
			s += _nw2[o + k] * h[k]
		g[j] = maxf(0.0, s)
	var out := {}
	for j in _nout.size():
		var s := _nb3[j]
		var o := j * _nh2
		for k in _nh2:
			s += _nw3[o + k] * g[k]
		out[_nout[j]] = s
	_ncache[iid] = [Game.time_days, out]
	return out


## Zeile einer Handlung auf FEATURES + ACT_X bringen (alte Zeilen haben nur die Eingänge der Insel).
func _pad_act(r) -> Array:
	var row: Array = (r as Array).duplicate()
	if row.size() <= FEATURES:
		while row.size() < FEATURES:
			row.append(0.0)
		for _i in ACT_X:
			row.append(0.0)
	while row.size() < FEATURES + ACT_X:
		row.append(0.0)
	return row


## Darf die KI Entscheidungen dieser Gruppe treffen? Im Training alles; im Spiel nach der Freischalt-Liste.
func allowed(group: String) -> bool:
	if train_all or not unlock_list:
		return true
	return KiActs.unlocked(group)


func note(w, text: String) -> void:
	trace_log.append([snappedf(Game.time_days, 0.01), Sea.island_name(w) if w != null else "", text])
	if trace_log.size() > 4000:
		trace_log = trace_log.slice(1000)


func set_weights_file(path: String) -> bool:
	return _load_weights(path)


## Steuert die KI auf dieser Insel die Berufe?
func controls(w) -> bool:
	return on and available and not weights.is_empty() and w != null and is_instance_valid(w) \
		and (Sea.is_main(w) or Powers.covers(w)) and allowed("berufe")  # Nebeninseln nur mit Rundfunkanstalt hier und dort (josh 2026-11-07)


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
	# Neuer Spielstart (josh 2026-11-15): im echten Spiel (goals.live, nie im Training) entscheidet zuerst der Spieler
	if Game.goals.get("live", false) and Quests.in_tutorial():
		return
	_next = Game.time_days + TICK_DAYS
	for w in Sea.all_worlds():
		if not w.settlers.is_empty() and controls(w):  # verlassene Inseln ("empty") bleiben in Sea.worlds
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
		if not aweights.has("bau:schmiede"):
			build_tick(w)  # alte Gewichte: fehlende Werkstatt für die Forschung nach fester Regel
	learn_build_tick(w)
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
		# woher: Freie (über dem Soll an Freien), dann Berufe über dem Soll
		var cands: Array = []
		if int(count.get("frei", 0)) > int(want.get("frei", 0)):
			cands = pool.filter(func(s): return s.job == "frei")
		if cands.is_empty():
			cands = pool.filter(func(s): return s.job != gap_job and int(count.get(s.job, 0)) > int(want.get(s.job, 0)))
		if cands.is_empty():
			break
		var pick = cands[0] if gap_job == "frei" else Steward._pick(w, cands, gap_job)
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
	elif not tweights.is_empty() and allowed("forschung"):
		target = KiActs.pick_tech()  # gelernte Wahl (josh 2026-11-15)
	else:
		target = ""
		for t in Data.sorted_tech_ids():
			if Game.tech_state(t) == "available":
				target = t
				break
	if target != "" and Game.start_research(target) == "":
		Game.notify(Loc.t("KI: Forschung gestartet: %s") % Data.techs[target].name, "wissen")
		note(Sea.main_world(), "Forschung gestartet: %s" % Data.techs[target].name)


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


## Was fehlt, um weiterzukommen (Training ganzes Spiel, josh 2026-11-15): Kosten ALLER wählbaren Forschungen,
## die Waren der Zeitalter-Prüfung und die Vorstufen dazu (Lehm für Ziegel, Mehl für Brot). Fund im Training:
## die KI sah nur die eine Ziel-Forschung und baute nie Lehmgrube oder Bäckerei. Im normalen Spiel (alte
## Gewichte) bleibt es bei research_missing().
var _needs_at := -1.0
var _needs: Dictionary = {}


func needs() -> Dictionary:
	if not (train_all or unlock_list):
		return research_missing()
	if absf(Game.time_days - _needs_at) < 0.25:
		return _needs
	_needs_at = Game.time_days
	var out := {}
	var mw = Sea.main_world()
	for t in Data.techs:
		if t == "superintelligenz" or t in Game.research.paid or Game.tech_state(t) != "available":
			continue
		var cost: Dictionary = Data.techs[t].get("cost", {})
		for id in cost:
			var miss := int(cost[id]) - Game.amount(id, mw)
			if miss > 0:
				out[id] = maxi(int(out.get(id, 0)), miss)
	if not Exams.exam_def(Exams.passed).is_empty():
		for e in Exams.status(Exams.passed):
			if not e[3] and str(e[0].get("type", "")) == "stock":
				var id := str(e[0].get("what", ""))
				out[id] = maxi(int(out.get(id, 0)), int(e[2]) - int(e[1]))
	for _i in 3:  # Vorstufen: was die Hersteller der fehlenden Waren selbst brauchen und nicht im Lager liegt
		for bt in Data.buildings:
			var pr: Dictionary = Data.buildings[bt].get("production", {})
			var hit := false
			for o in pr.get("outputs", {}):
				if out.has(o):
					hit = true
			if hit:
				for inp in pr.get("inputs", {}):
					if not out.has(inp) and Game.amount(inp, mw) < 10:
						out[inp] = 10 - Game.amount(inp, mw)
	_needs = out
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
	var nc := net_corr(w, x)
	var logits := []
	var best := -INF
	for i in JOBS.size():
		var row: Array = weights[i]
		var z := float(nc.get("job:" + JOBS[i], 0.0))
		for k in FEATURES:
			z += float(row[k]) * x[k]
		if i >= job_rows or int(caps[JOBS[i]]) <= 0:
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
	var c := {"holzfaeller": 99, "sammler": 99, "fischer": 99, "steinmetz": 0, "bauer": 0, "koch": 0, "handwerker": 0, "jaeger": 0, "forscher": 0,
		"foerster": 0, "frei": 99}
	var plant := 0
	for b in w.buildings:
		if not b.complete and str(b.def.get("builder", "")) == "foerster":
			plant += 1
	c["foerster"] = ceili(plant / 8.0)
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
	var miss := needs()
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
	# 50..63 Bauen (josh 2026-11-11)
	var beds := 0
	var houses := 0
	var fields := 0
	var roads := 0
	var up := 0
	var yard = null
	for b in w.buildings:
		if not is_instance_valid(b):
			continue
		var hs := int(b.def.get("housing", 0))
		if hs > 0:
			houses += 1
			if b.complete:
				beds += hs
				if _upgrade_ok(w, b):
					up += 1
		if b.def.has("farm"):
			fields += 1
		if str(b.def.get("tile", "")) == "road":
			roads += 1
		if b.def.get("ships", false) and b.complete:
			yard = b
	x[50] = clampf(float(beds - n) / maxf(4.0, float(n)), -1.0, 2.0)
	x[51] = minf(houses / 20.0, 3.0)
	x[52] = minf(w.construction_sites().size() / 3.0, 3.0)
	x[53] = minf(fields / 20.0, 3.0)
	x[54] = minf(float(fields) / (4.0 * float(_count_job(w, "bauer")) + 4.0), 3.0)
	x[55] = minf(float(Game.storage_volume(w)) / 2000.0, 3.0)
	x[56] = minf(roads / 50.0, 3.0)
	x[57] = 1.0 if yard != null else 0.0
	x[58] = minf(Sea.ships_of(int(w.island_id)).size() / 3.0, 3.0)
	x[59] = minf(Sea.idle_ships(int(w.island_id)).size() / 3.0, 3.0)
	x[60] = minf(_unsettled().size() / 3.0, 3.0)
	x[61] = minf(Sea.settled_islands().size() / 4.0, 3.0)
	x[62] = minf(up / 5.0, 3.0)
	x[63] = minf((Game.time_days - float(_last_build.get(int(w.island_id), -99.0))) / 5.0, 1.0)
	# Brennholz für den Winter (josh 2026-11-14): Vorrat gegen den ganzen Winterbedarf, und was über der Reserve liegt
	var need_full: float = Extras.heat_reserve(w, true)
	x[64] = minf(Extras.fuel(w) / maxf(1.0, need_full), 3.0)
	x[65] = minf(maxf(0.0, Extras.fuel(w) - Extras.heat_reserve(w)) / 500.0, 3.0)
	KiActs.more_features(w, x, n, adults.size(), beds)  # 66..95: Zeitalter, Prüfung, Droiden, Funk, Tiere, See, Waren
	if score_on:
		if feat_seen.size() != FEATURES:
			feat_seen.resize(FEATURES)
			feat_seen.fill(0)
		for k in FEATURES:
			if absf(x[k]) > 0.000001:
				feat_seen[k] += 1
	return x


func _count_job(w, job: String) -> int:
	var c := 0
	for s in w.settlers:
		if is_instance_valid(s) and s.job == job:
			c += 1
	return c


## Entdeckte, nicht besiedelte Inseln.
func _unsettled() -> Array:
	return Sea.islands.filter(func(m): return str(m.get("state", "")) in ["discovered", "empty"])


# ---------------------------------------------------------------- Bauen lernen (josh 2026-11-11)
## Alle LEARN_BUILD_DAYS je Insel: jede erlaubte Bau-Handlung bekommt einen Wert (Gewichte x Eingänge), die beste
## wird ausgeführt, wenn ihr Wert über 0 liegt (0 = nichts tun). Erlaubt heißt: freigeschaltet, Material auf der
## Insel, ein Platz, höchstens MAX_KI_SITES eigene Baustellen zugleich.
func learn_build_tick(w) -> void:
	if aweights.is_empty():
		return
	var iid := int(w.island_id)
	if Game.time_days < float(_bnext.get(iid, 0.0)):
		return
	_bnext[iid] = Game.time_days + LEARN_BUILD_DAYS
	max_sites = 2 + _adults(w).size() / 15
	var x := features(w)
	KiActs.settings_tick(w, x)  # Überstunden und Schichten: an, solange der Wert über 0 liegt
	# alle Handlungen bewerten, die besten zuerst versuchen (höchstens 2 je Runde)
	var vals := []
	for act in aweights:
		if act.begins_with("ot:") or act.begins_with("schicht:") or not allowed(KiActs.group(act)):
			continue
		var v := act_value(w, act, x)
		if v > 0.0:
			vals.append([v, act])
	vals.sort_custom(func(a, b): return a[0] > b[0])
	if OS.has_environment("KI_DEBUG"):
		print("KIDBG Tag %.1f: %d über 0; %s" % [Game.time_days, vals.size(), vals.slice(0, 8).map(func(e): return "%s %.2f %s" % [e[1], e[0], can_act(w, e[1])])])
	var done := 0
	for e in vals:
		if done >= 2:
			break
		var act: String = e[1]
		if not can_act(w, act):
			continue
		var res := act_build(w, act)
		if res != "":
			built_log[act] = int(built_log.get(act, 0)) + 1
			KiActs.note_done(w, act)
			_last_build[iid] = Game.time_days
			note(w, res)
			done += 1


## Wert einer Handlung: Gewichte mal (Eingänge der Insel + ACT_X Eingänge der Handlung).
func act_value(w, act: String, x: PackedFloat32Array) -> float:
	var row: Array = aweights[act]
	var v := float(net_corr(w, x).get(act, 0.0))
	for k in FEATURES:
		v += float(row[k]) * x[k]
	var ex := KiActs.extras(w, act)
	if score_on:
		if act_seen.size() != ACT_X:
			act_seen.resize(ACT_X)
			act_seen.fill(0)
	for k in ACT_X:
		v += float(row[FEATURES + k]) * float(ex[k])
		if score_on and absf(float(ex[k])) > 0.000001:
			act_seen[k] += 1
	return v


## Felder ohne Straße, über die am meisten getragen wird: Wege von Arbeitsplätzen und Häusern zum nächsten Lager,
## gewichtet nach Plätzen (wie das Gutachten, aber mit Zellen statt Bildpunkten). Meistbegangene zuerst.
func road_cells(w) -> Array:
	var heat := {}
	for b in w.buildings:
		if not is_instance_valid(b) or not b.complete or b.is_ground() or b.is_decor():
			continue
		if not (b.def.has("production") or b.def.has("research") or b.def.has("farm") or int(b.def.get("housing", 0)) > 0):
			continue
		var st = w.nearest_storage(b.entrance_cell())
		if st == null or st == b:
			continue
		var weight := float(maxi(1, b.slots() if b.def.has("production") or b.def.has("research") else int(b.def.get("housing", 1)) / 2))
		if not w.is_inside(b.entrance_cell()) or not w.is_inside(st.entrance_cell()):
			continue
		for c in w.astar.get_id_path(b.entrance_cell(), st.entrance_cell(), true):
			if w.road_at(c) or w.building_at.has(c):
				continue
			heat[c] = float(heat.get(c, 0.0)) + weight
	var cells: Array = heat.keys().filter(func(c): return float(heat[c]) >= 2.0)
	cells.sort_custom(func(a, b): return heat[a] > heat[b])
	return cells


func _ki_sites(w) -> int:
	return w.buildings.filter(func(b): return is_instance_valid(b) and not b.complete and b.has_meta("ki_site")).size()


func _affordable(w, type: String) -> bool:
	if not Data.buildings.has(type) or not Game.is_unlocked(type):
		return false
	return Planner.missing_cost(w, type).is_empty()


func _best_of(w, types: Array, key: String) -> String:
	var best := ""
	var best_n := -1
	for t in types:
		if _affordable(w, t) and int(Data.buildings[t].get(key, 0)) > best_n:
			best_n = int(Data.buildings[t].get(key, 0))
			best = t
	return best


func _house_types() -> Array:
	return Data.buildings.keys().filter(func(t): return Data.buildings[t].get("buildable", false) and int(Data.buildings[t].get("housing", 0)) > 0)


func _store_types() -> Array:
	return Data.buildings.keys().filter(func(t): return Data.buildings[t].get("buildable", false) and int(Data.buildings[t].get("storage", 0)) > 0 and t != "lagerfeuer")


func _upgrade_ok(w, b) -> bool:
	var to: String = b.def.get("upgrade", "")
	return to != "" and b.complete and not b.player_only and Game.is_unlocked(to) and HouseNeeds.full_level(b) and Planner.missing_cost(w, to).is_empty()


func _yard(w):
	for b in w.buildings:
		if is_instance_valid(b) and b.complete and b.def.get("ships", false):
			return b
	return null


func _free_adults(w) -> Array:
	return w.settlers.filter(func(s): return is_instance_valid(s) and s.is_adult() and s.job == "frei" and not JobDesk.player_controlled(s))


## Wer darf mit auf eine neue Insel: zuerst Freie, dann alle, die die KI umsetzen darf (keine Baumeister).
func _colonists(w) -> Array:
	var free := _free_adults(w)
	var rest: Array = _adults(w).filter(func(s): return s.job != "frei" and s.job != "baumeister" and _movable(s))
	return free + rest


func can_act(w, act: String) -> bool:
	if (train_all or unlock_list) and not KiActs.wanted(w, act):
		return false
	if not act in BUILD_ACTS:
		return KiActs.can(w, act)
	var site_acts := ["haus", "ausbau", "lager", "feld", "obstgarten", "strasse", "werft"]
	if act in site_acts and _ki_sites(w) >= max_sites:
		return false
	match act:
		"haus":
			return _best_of(w, _house_types(), "housing") != ""
		"ausbau":
			return w.buildings.any(func(b): return is_instance_valid(b) and int(b.def.get("housing", 0)) > 0 and _upgrade_ok(w, b))
		"lager":
			return _best_of(w, _store_types(), "storage") != ""
		"feld":
			return _affordable(w, "feld")
		"obstgarten":
			return _affordable(w, "obstgarten")
		"strasse":
			return _affordable(w, "strasse") and Game.amount("stein", w) >= 15 and not road_cells(w).is_empty()
		"werft":
			return _yard(w) == null and _affordable(w, "werft")
		"schiff":
			var y = _yard(w)
			return y != null and y.ship_queue.is_empty() and y.ship_wip == "" and Sea.ships_of(int(w.island_id)).size() < 3 + Sea.settled_islands().size()
		"erkunden":
			return Sea.can_explore(w) == ""
		"besiedeln":
			return not _unsettled().is_empty() and not Sea.idle_ships(int(w.island_id)).is_empty() and _colonists(w).size() >= 3 and _adults(w).size() >= 8
	return false


func _place(w, type: String):
	var c = Planner.spot(w, type)
	if c == null:
		return null
	var b = w.place_building(type, c, false)
	if b != null:
		b.set_meta("ki_site", true)
		b.set_meta("ki_day", Game.time_days)
	return b


## Führt eine Bau-Handlung aus. Gibt einen kurzen Text zurück ("" = ging nicht).
func act_build(w, act: String) -> String:
	if not act in BUILD_ACTS:
		return KiActs.do(w, act)
	var txt := ""
	match act:
		"haus":
			var t := _best_of(w, _house_types(), "housing")
			if _place(w, t) != null:
				txt = Data.buildings[t].name
		"ausbau":
			var cands: Array = w.buildings.filter(func(b): return is_instance_valid(b) and int(b.def.get("housing", 0)) > 0 and _upgrade_ok(w, b))
			cands.sort_custom(func(a, b): return int(a.def.housing) < int(b.def.housing))
			if not cands.is_empty():
				var nb = w.upgrade_building(cands[0])
				if nb != null:
					nb.set_meta("ki_site", true)
					txt = nb.def.name
		"lager":
			var t := _best_of(w, _store_types(), "storage")
			if _place(w, t) != null:
				txt = Data.buildings[t].name
		"feld":
			var c = Planner.spot(w, "obstgarten" if Data.buildings.has("obstgarten") else "feld")
			if c != null:
				var n := 0
				for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					if _affordable(w, "feld") and w.can_place("feld", c + d):
						var b = w.place_building("feld", c + d, false)
						if b != null:
							b.set_meta("ki_site", n == 0)
							n += 1
				if n > 0:
					txt = tr("%d Getreidefelder") % n
		"obstgarten":
			if _place(w, "obstgarten") != null:
				txt = Data.buildings["obstgarten"].name
		"strasse":
			var cells := road_cells(w)
			var n := 0
			for cc in cells:
				if n >= 6 or not _affordable(w, "strasse"):
					break
				if w.can_place("strasse", cc):
					w.place_building("strasse", cc, false)
					n += 1
			if n > 0:
				txt = tr("%d Felder Straße") % n
		"werft":
			if _place(w, "werft") != null:
				txt = Data.buildings["werft"].name
		"schiff":
			var y = _yard(w)
			var best := "boot"
			for t in ["kogge", "schnellsegler", "galeone"]:
				if Data.ships.has(t) and Game.is_researched(str(Data.ships[t].get("requires", ""))) and int(Data.ships[t].get("yard", 1)) <= y.yard_level():
					best = t
					break
			y.ship_queue.append(best)
			y.ship_choice = best
			txt = Data.ships[best].name
		"erkunden":
			if Sea.start_explore(w) == "":
				txt = tr("Erkundung")
		"besiedeln":
			var target: Dictionary = _unsettled()[0]
			var best_d := INF
			for m in _unsettled():
				var dd := Sea.distance(int(w.island_id), int(m.id))
				if dd < best_d:
					best_d = dd
					target = m
			var people: Array = _colonists(w).slice(0, 3)
			# ohne Funk kann die KI drüben niemanden einteilen: die drei fahren als Sammler, Holzfäller und Fischer
			var cj := ["sammler", "holzfaeller", "fischer"]
			for i in people.size():
				JobDesk.assign(people[i], cj[i % 3], "ki", 3.0, true)
			var goods := {}
			var wood := mini(40, Game.amount("holz", w) / 3)
			if wood > 0:
				goods["holz"] = wood
			for id in Data.food_ids():
				var a := mini(30, Game.amount(id, w) / 3)
				if a > 0 and goods.size() < 4:
					goods[id] = a
			for sh in Sea.idle_ships(int(w.island_id)):
				Sea.fill_crew(sh)
				if Sea.crew_missing(sh) > 0:
					Sea.hire_sailor(sh, "ki")
				if Sea.send_ship(w, int(target.id), people, sh, goods) == "":
					txt = tr("Siedler nach %s") % str(target.get("name", "?"))
					break
	if txt != "":
		Game.notify_at(w, tr("KI baut: %s") % txt if not act in ["schiff", "erkunden", "besiedeln"] else tr("KI: %s") % txt, "hammer", "verwaltung")
	return txt


## Nahrung im Lager in Tagen für alle Siedler.
func food_days(w) -> float:
	var sat := 0.0
	for id in Data.food_ids():
		sat += _amt(id, w) * Data.food_satiety(id)
	var need := Steward._need_per_head(w) * maxf(1.0, float(w.settlers.size()))
	return sat / maxf(1.0, need)


# ---------------------------------------------------------------- Punkte (josh 2026-11-07)
## Je Spieltag über alle bewohnten Inseln (Wertung 2, josh 2026-11-15): Nahrungstage ohne rohen Weizen (bis 10),
## 10 für eine volle Winterreserve an Brennstoff, 2 je verarbeitetem Gut, solange es gebraucht wird (3, wenn es der
## Forschung fehlt), 500 je ganze Forschung und 1000 je neuem Zeitalter, 1 je satten und je zufriedenen Siedler,
## -1 je Siedler-Tag mit Hunger oder Kälte, -100 je Toter, 20 je bewohnter Nebeninsel, 1 je Erz/Kohle per Schiff,
## 20 mal Anteil der Erwachsenen, die im eigenen Beruf arbeiten.
var score_on := false

## Verarbeitete Ware zählt nur, solange sie gebraucht wird: unter der Höchstmenge der Insel und mit Platz im Lager.
func note_processed(res: String, n: int, w = null) -> void:
	if w != null and is_instance_valid(w):
		var lim: int = Game.limit_of(res, w)
		if (lim >= 0 and Game.amount(res, w) > lim) or Game.space_for(res, w) <= 0:
			return
	processed_today += float(n) * (NEEDED_PTS if needs().has(res) else PROCESSED_PTS)


## Nachschub per Schiff (Sea.unload_goods/unload_some): Erz und Kohle.
func note_supply(res: String, n: int) -> void:
	if score_on and res in ["erz", "kohle"]:
		supply_today += float(n) * SUPPLY_PTS


func note_research(points: float, total: float = 0.0) -> void:
	research_raw += points
	if total > 0.0:
		research_today += RESEARCH_WHOLE_PTS * points / total


func note_research_done() -> void:
	finished_today += 1


func score_start() -> void:
	score_on = true
	_needs_at = -1.0
	waste_today = 0
	_firsts = {}
	for o in Sea.all_worlds():
		for id in o.stock:
			if float(o.stock[id]) > 0.0:
				_firsts[id] = true
	score_log = []
	score_total = 0.0
	processed_today = 0.0
	deaths_today = 0
	research_today = 0.0
	research_raw = 0.0
	finished_today = 0
	supply_today = 0.0
	distress_today = 0.0
	work_today = 0.0
	droid_today = 0.0
	goal_today = 0.0
	goal_done = false
	trace_log = []
	feat_seen = PackedInt32Array()
	act_seen = PackedInt32Array()
	_age0 = Game.current_age()
	_sample_t = Game.time_days
	_score_t0 = Game.time_days
	_score_day = 0


var supply_today := 0.0
var droid_today := 0.0
var goal_today := 0.0
var distress_today := 0.0
## Verschwendung (josh 2026-11-15): jeder Abriss durch die KI kostet Punkte. Fund im Training: 241 Hühnerhöfe
## gebaut und 220 wieder abgerissen.
const WASTE_PTS := -20.0
var waste_today := 0
## Zwischenpunkte (josh 2026-11-18, Karte "Zwischenpunkte und Abrissschutz"): 300 Punkte, wenn eine gebrauchte
## Ware (needs(): Forschungskosten, Prüfungswaren und ihre Vorstufen) zum ersten Mal in einem Lager liegt. Einmal je
## Ware und Spiel; Waren, die schon beim Start da waren, zählen nicht. Fund im Training: die KI baute nie eine
## Köhlerei und nie Getreidefelder, weil Punkte erst nach der ganzen Kette (Kohle -> Erz -> Eisen -> Werkzeug) kamen.
const FIRST_PTS := 300.0
var _firsts: Dictionary = {}
var work_today := 0.0
var _age0 := 0
var _sample_t := 0.0


## Alle 0,25 Tage: Siedler mit Hunger oder Kälte, Anteil der Erwachsenen im eigenen Beruf.
func _sample() -> void:
	var adults := 0
	var working := 0
	for o in Sea.all_worlds():
		var cold: bool = Seasons.cold.has(o)
		for s in o.settlers:
			if not is_instance_valid(s):
				continue
			if cold or s.hunger < HUNGRY_BELOW:
				distress_today += DISTRESS_PTS * SAMPLE_DAYS
			if s.is_adult():
				adults += 1
				if not s.sleeping and s._stat_kind == "job":
					working += 1
		# Droiden zählen wie arbeitende Erwachsene: übernehmen sie die Arbeit, kosten freie Menschen keine Punkte
		if Droids.powered(o):
			for d in o.droids:
				if is_instance_valid(d) and d.job != "frei":
					working += 1
					droid_today += DROID_PTS * SAMPLE_DAYS
		if not goal_done and o.buildings.any(func(b): return b.type == "zukunftsstadt" and b.complete):
			goal_done = true
			goal_today += GOAL_PTS
			note(o, "Die Zukunftsstadt steht. Ziel erreicht.")
	if adults > 0:
		work_today += WORK_PTS * SAMPLE_DAYS * minf(1.0, float(working) / float(adults))


func food_days_score(w) -> float:
	var sat := 0.0
	for id in Data.food_ids():
		if not bool(Data.resources.get(id, {}).get("raw_food", false)):
			sat += _amt(id, w) * Data.food_satiety(id)
	var need := Steward._need_per_head(w) * maxf(1.0, float(w.settlers.size()))
	return minf(sat / maxf(1.0, need), FOOD_DAYS_CAP)


func _score_tick() -> void:
	while Game.time_days - _sample_t >= SAMPLE_DAYS:
		_sample_t += SAMPLE_DAYS
		_sample()
	var d := int(floor(Game.time_days - _score_t0))
	if d == _score_day:
		return
	_score_day = d
	score_day()


func score_day() -> Dictionary:
	var w = Game.world
	var r := {"day": int(floor(Game.time_days))}
	# alle besiedelten Inseln zählen (josh: Punkte je Siedler); Nahrungstage nach Köpfen gewichtet
	var ws: Array = Sea.all_worlds().filter(func(o): return not o.settlers.is_empty())
	if ws.is_empty():
		ws = [w]
	var fd := 0.0
	var heads := 0
	var warm := 0.0
	for o in ws:
		var n := float(o.settlers.size())
		fd += food_days_score(o) * n
		heads += o.settlers.size()
		var need: float = Extras.heat_reserve(o, true)
		warm += (1.0 if need <= 0.0 else minf(1.0, Extras.fuel(o) / need)) * n
	r["food"] = fd / maxf(1.0, float(heads))
	r["wood"] = RESERVE_PTS * warm / maxf(1.0, float(heads))
	r["proc"] = processed_today
	var age := Game.current_age()
	r["res"] = research_today + RESEARCH_DONE_PTS * finished_today + AGE_PTS * maxf(0.0, float(age - _age0))
	_age0 = maxi(_age0, age)
	r["isl"] = ISLAND_PTS * float(maxi(0, ws.size() - 1)) + supply_today
	r["need"] = distress_today
	r["work"] = work_today
	r["rpts"] = research_raw
	r["goal"] = goal_today + droid_today
	r["age"] = age
	r["techs"] = Game.research.done.size()
	r["droids"] = Droids.count()
	var sat := 0
	var mood := 0
	for s in ws.reduce(func(acc, o): return acc + o.settlers, []):
		if is_instance_valid(s):
			if s.hunger > 50.0:
				sat += 1
			if s.mind.mood > 50.0:
				mood += 1
	r["sat"] = sat
	r["mood"] = mood
	r["dead"] = DEATH_PTS * deaths_today
	r["waste"] = WASTE_PTS * waste_today
	waste_today = 0
	var first := 0.0
	if train_all or unlock_list:
		for id in needs():
			if _firsts.has(id):
				continue
			for o in ws:
				if Game.amount(id, o) > 0:
					_firsts[id] = true
					first += FIRST_PTS
					note(o, "erste Ware: " + str(Data.resources.get(id, {}).get("name", id)))
					break
	r["first"] = first
	r["pop"] = heads
	r["islands"] = ws.size()
	r["total"] = float(r.food) + float(r.wood) + float(r.proc) + float(r.res) + sat + mood + float(r.dead) \
		+ float(r.isl) + float(r.need) + float(r.work) + float(r.goal) + float(r.waste) + float(r.first)
	score_total += float(r.total)
	score_log.append(r)
	processed_today = 0.0
	deaths_today = 0
	research_today = 0.0
	research_raw = 0.0
	finished_today = 0
	supply_today = 0.0
	distress_today = 0.0
	work_today = 0.0
	droid_today = 0.0
	goal_today = 0.0
	return r


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	on = v3 and available
	_kept_on = false
	_next = 0.0


func _on_save(d: Dictionary) -> void:
	d["ki_brain"] = {"on": on or (_kept_on and not available), "v3": v3 or bool(_v3_seen)}


var _v3_seen := false


func _on_load(data: Dictionary, _old_rules: int) -> void:
	_on_reset()
	var k = data.get("ki_brain", null)
	_v3_seen = k is Dictionary and bool(k.get("v3", false))
	if k is Dictionary:
		_kept_on = bool(k.get("on", false))
		on = _kept_on and available
	if v3 and not _v3_seen:
		on = available  # Spielstand zum ersten Mal in Version 3: die KI übernimmt (josh 2026-11-08)
