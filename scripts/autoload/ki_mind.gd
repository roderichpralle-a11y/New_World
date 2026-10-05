extends Node
## KI-Variante mit Sprachmodellen: Inselräte (Llama-3.2-1B) und Siedler (SmolLM-135M).
##
## Ablauf einer Runde (`_run_round`), Insel für Insel, Hauptinsel zuerst:
## 1. Ist der Rat dran (alle `council_days`), bekommt Llama die Lage der Insel: Siedler mit
##    Fähigkeiten und letzten Entscheidungen, Gebäude mit Lage, Vorräte und Bedarf, alle
##    Inseln mit Lage, Rohstoffen und Bedarf, alle Schiffe mit Fahrt, die Jahreszeiten und
##    ihre Regeln, die Wünsche, Vorgaben und Prioritäten des Herrschers und das Gedächtnis
##    des Rats. Daraus entscheidet der Rat nacheinander: Schwerpunkt, welche Arbeit wie
##    wichtig ist (daraus bekommt jeder Siedler einen Auftrag), was gebaut wird, was erforscht
##    wird (nur die Hauptinsel) und ob er mit einer anderen Insel handelt. Zum Schluss sagt
##    er den Bewohnern in einem Satz, was sie tun sollen.
## 2. Danach fragt SmolLM für jeden erwachsenen Siedler: Fähigkeiten, Bedürfnisse, Auftrag
##    des Rats, was er zuletzt getan hat. Der Siedler entscheidet selbst und kann vom
##    Auftrag abweichen.
## Lernen: Jede Ratssitzung wird mit den Zahlen der Insel gespeichert. Bei der nächsten
## Sitzung misst der Rat, was seit der Entscheidung geschehen ist (Essen, Holz, Stein,
## Siedler, Laune, Forschung je Tag) und führt eine Erfahrungstabelle je Jahreszeit und
## Schwerpunkt. Aus auffälligen Messungen schreibt er Lehren, und alle paar Sitzungen
## lässt er Llama aus seinen Entscheidungen und deren Folgen selbst eine Lehre ziehen.
## Lehren, Erfahrung und letzte Entscheidungen stehen in jeder neuen Anfrage.
## Der Herrscher kann jederzeit mit einem Rat schreiben (`chat`), feste Vorgaben machen
## (`bind`) und Prioritäten verschieben (`set_prio`).
## Sind die Sprachmodelle nicht da, entscheidet die Regel-KI in Society wie bisher.

signal changed

const JOB_ORDER := ["sammler", "fischer", "bauer", "koch", "holzfaeller", "steinmetz", "baumeister", "handwerker", "forscher", "jaeger"]
const PRIO_FACTOR := [0.4, 1.0, 1.5, 2.2]
const PRIO_WORDS := ["unwichtig", "normal", "wichtig", "sehr wichtig"]
const TRADE_GOODS := ["holz", "stein", "bretter", "lehm", "ziegel", "werkzeug", "eisen", "erz", "kohle", "felle", "gold", "glas", "papier"]

var running := false
var epoch := 0
var activity := ""  # was gerade gerechnet wird (Anzeige)
var smem: Dictionary = {}  # Siedler-ID (Text) -> letzte Entscheidungen [[Tag, Beruf, eigene Wahl]]
var sdec: Dictionary = {}  # Siedler-ID (Text) -> letzte Entscheidung mit Wahrscheinlichkeiten
var trades: Array = []  # laufende Handelsrouten zwischen Inseln
var next_trade := 1
var last_prompt: Dictionary = {}  # rat/siedler -> letzte Anfrage (zum Ansehen)
var traces: Array = []  # Debug: alle Anfragen an die Modelle mit Ergebnis (nur im Speicher, für den Bericht)
var trace_count := 0
var _round_start := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func cfg(key: String, default = null):
	return Data.ki_llm.get(key, default)


func active() -> bool:
	return Llm.active()


# ================================================================== Zustand
## Gedächtnis und Vorgaben eines Inselrats (liegt im Society-Zustand, wird mitgespeichert).
func mem(w) -> Dictionary:
	var st: Dictionary = Society.state(w)
	if not st.has("llm"):
		st["llm"] = {}
	var m: Dictionary = st.llm
	var defaults := {"next_council": Game.time_days + float(cfg("first_council_day", 0.15)), "focus": st.get("strategy", "nahrung"),
		"plan": "", "shares": {}, "orders": {}, "last": {}, "binding": [], "prios": {}, "wishes": [], "chat": [],
		"records": [], "lessons": [], "exp": {}, "councils": 0, "waiting": false}
	for k in defaults:
		if not m.has(k):
			m[k] = defaults[k]
	if not m.has("clean_v2"):
		# Ältere Spielstände: abgeschnittene Lehren und Ansage auf ganze Sätze kürzen
		m["clean_v2"] = true
		for l in m.lessons:
			l[1] = _clean(str(l[1]))
		m.plan = _clean(str(m.plan)) if str(m.plan) != "" else ""
	return m


func reset() -> void:
	epoch += 1
	running = false
	activity = ""
	smem = {}
	sdec = {}
	trades = []
	next_trade = 1
	last_prompt = {}
	traces = []
	trace_count = 0


func serialize() -> Dictionary:
	return {"smem": smem, "trades": trades, "next_trade": next_trade}


func load_from(d: Dictionary) -> void:
	reset()
	smem = d.get("smem", {})
	trades = d.get("trades", [])
	next_trade = int(d.get("next_trade", 1))


func prio(w, key: String) -> int:
	return int(mem(w).prios.get(key, 1))


# ================================================================== Takt
func _process(_delta: float) -> void:
	if not Society.enabled:
		return
	Llm.maybe_start()
	if running and Time.get_ticks_msec() / 1000.0 - _round_start > 900.0:
		running = false  # Sicherheitsnetz: hängende Runde aufgeben
	if not active() or running or Game.world == null or Game.is_over:
		return
	_expire_trades()
	_run_round()


func _paused() -> bool:
	return Game.speed <= 0 or Game.is_over


## Wartet, solange das Spiel pausiert. Gibt false zurück, wenn die Runde abbrechen soll.
func _alive(ep: int) -> bool:
	while _paused() and ep == epoch:
		await get_tree().process_frame
	return ep == epoch and active()


func _run_round() -> void:
	running = true
	_round_start = Time.get_ticks_msec() / 1000.0
	var ep := epoch
	var worlds: Array = Sea.all_worlds().duplicate()
	worlds.sort_custom(func(a, b): return int(a.island_id) < int(b.island_id))
	var did := false
	for w in worlds:
		if not await _alive(ep):
			return
		if not is_instance_valid(w) or w.settlers.is_empty():
			continue
		var m := mem(w)
		if Game.time_days >= float(m.next_council) and not Game.is_night():
			m.next_council = Game.time_days + float(cfg("council_days", 1.0))
			await _council(w, ep)
			did = true
			if ep != epoch:
				return
		for s in w.settlers.duplicate():
			if not await _alive(ep):
				return
			if not is_instance_valid(s) or not is_instance_valid(w) or s.world != w:
				continue
			if not _settler_due(s):
				continue
			await _settler_turn(s, w)
			did = true
			if ep != epoch:
				return
	activity = ""
	running = false
	if not did:
		# Nichts zu tun: kurz warten, bevor die nächste Runde startet
		running = true
		await get_tree().create_timer(0.5).timeout
		if ep == epoch:
			running = false


# ================================================================== Gemeinsame Texte
func _season_rules() -> String:
	var out := []
	for s in 4:
		out.append("%s: %s" % [Seasons.season_name(s), Seasons.effects_text(s)])
	return "Ein Jahr hat 4 Jahreszeiten mit je %d Tagen. %s Ein Erwachsener isst etwa 3 Essen am Tag. Heizholz je Siedler und Tag: Herbst 0,3, Winter 1. Felder werden nur im Frühling und Sommer bestellt, der Winter vernichtet die Saat." % [
		int(Seasons.season_days()), " ".join(out)]


func _when() -> String:
	return "Tag %d, %s (Tag %d von %d), Jahr %d" % [Game.day(), Seasons.season_name(), Seasons.day_in_season(), int(Seasons.season_days()), Seasons.year() + 1]


func _jname(j: String) -> String:
	return Data.jobs.get(j, {}).get("name", j)


func _skill_text(s) -> String:
	var parts := []
	var tal: Dictionary = s.mind.talents
	var ks: Array = tal.keys()
	ks.sort_custom(func(a, b): return float(tal[a]) + s.skill_level(a) * 0.1 > float(tal[b]) + s.skill_level(b) * 0.1)
	for sk in ks.slice(0, 3):
		var word := "sehr gut" if float(tal[sk]) >= 1.4 else ("gut" if float(tal[sk]) >= 1.15 else ("mittel" if float(tal[sk]) >= 0.85 else "schwach"))
		parts.append("%s %s (Stufe %d)" % [Data.skills.get(sk, {}).get("name", sk), word, int(s.skill_level(sk))])
	return ", ".join(parts)


func _food_text(w) -> String:
	var parts := []
	for id in Data.resources:
		if Data.resources[id].get("category", "") == "food" and Game.amount(id, w) > 0:
			parts.append("%d %s" % [Game.amount(id, w), Data.resources[id].name])
	return ", ".join(parts) if not parts.is_empty() else "nichts"


func _stock_text(w) -> String:
	var parts := []
	for id in Data.resources:
		if Data.resources[id].get("category", "") == "material" and Game.amount(id, w) > 0:
			parts.append("%d %s" % [Game.amount(id, w), Data.resources[id].name])
	return ", ".join(parts) if not parts.is_empty() else "nichts"


func _needs(w, sit: Dictionary) -> Array:
	var n := []
	if float(sit.food) < float(sit.food_target):
		n.append("Essen (%d von %d)" % [int(sit.food), int(sit.food_target)])
	if float(sit.wood) < float(sit.wood_target):
		n.append("Holz (%d von %d)" % [int(sit.wood), int(sit.wood_target)])
	if float(sit.stone) < float(sit.stone_target):
		n.append("Stein (%d von %d)" % [int(sit.stone), int(sit.stone_target)])
	if int(sit.pop) >= int(sit.housing):
		n.append("Wohnplatz (%d Siedler, %d Plätze)" % [int(sit.pop), int(sit.housing)])
	if int(sit.vit_low) > 0:
		n.append("Vitamine (%d mit Mangel)" % int(sit.vit_low))
	if int(sit.predators) > 0:
		n.append("Schutz vor %d Raubtieren" % int(sit.predators))
	return n


func _resources_text(w) -> String:
	var c := {}
	for n in w.nodes:
		if n.amount > 0:
			c[n.type] = int(c.get(n.type, 0)) + 1
	var parts := []
	for t in c:
		parts.append("%d %s" % [int(c[t]), Data.nodes.get(t, {}).get("name", t)])
	return ", ".join(parts)


func _buildings_text(w) -> String:
	var groups := {}
	var sites := []
	for b in w.buildings:
		if not b.complete:
			sites.append("%s bei (%d,%d)" % [b.def.name, b.cell.x, b.cell.y])
			continue
		if not groups.has(b.type):
			groups[b.type] = []
		groups[b.type].append("(%d,%d)" % [b.cell.x, b.cell.y])
	var parts := []
	for t in groups:
		var cells: Array = groups[t]
		parts.append("%s %dx bei %s" % [Data.buildings[t].name, cells.size(), " ".join(cells.slice(0, 4)) + (" …" if cells.size() > 4 else "")])
	var out := "; ".join(parts)
	if not sites.is_empty():
		out += ". Baustellen: " + "; ".join(sites)
	return out


func _islands_text(w) -> String:
	var lines := []
	for m in Sea.islands:
		var id := int(m.id)
		var pos: Array = m.get("pos", [0, 0])
		var where := "(%.1f, %.1f)" % [float(pos[0]), float(pos[1])]
		var kind: String = Sea.biome_name(m)
		var state: String = m.get("state", "")
		if state == "settled" and Sea.worlds.has(id):
			var o = Sea.worlds[id]
			var osit: Dictionary = Society.situation(o)
			var need := _needs(o, osit)
			lines.append("- %s%s, %s bei %s: %d Siedler. Rohstoffe: %s. Vorräte: %s; Essen %d. Braucht: %s." % [m.name,
				" (eure Insel)" if id == int(w.island_id) else "", kind, where, o.settlers.size(), _resources_text(o),
				_stock_text(o), int(osit.food), ", ".join(need) if not need.is_empty() else "nichts Dringendes"])
		elif state == "discovered":
			lines.append("- %s, %s bei %s: entdeckt, unbewohnt." % [m.name, kind, where])
		elif state == "lost":
			lines.append("- %s bei %s: verloren." % [m.name, where])
	return "\n".join(lines)


func _ships_text() -> String:
	var lines := []
	for sh in Sea.ships:
		var route := ""
		if not sh.route.is_empty():
			var stops := []
			for stp in sh.route:
				stops.append("%s (lädt %s)" % [Sea.meta(int(stp.island)).get("name", "?"), Sea.goods_text(stp.get("load", {})) if not stp.get("load", {}).is_empty() else "nichts"])
			route = " Route: " + " -> ".join(stops)
		lines.append("- %s (%s), Heimat %s: %s.%s" % [sh.name, Sea.ship_def(sh).get("name", sh.type),
			Sea.meta(int(sh.home)).get("name", "?"), Sea.ship_status(sh), route])
	return "\n".join(lines) if not lines.is_empty() else "Keine Schiffe."


func _settlers_text(w) -> String:
	var lines := []
	var adults: Array = w.settlers.filter(func(s): return s.is_adult())
	for s in adults.slice(0, 16):
		var last := ""
		var sm: Array = smem.get(str(s.id), [])
		if not sm.is_empty():
			var e: Array = sm[sm.size() - 1]
			last = "; zuletzt: %s%s" % [_jname(e[1]), " (eigene Wahl)" if e[2] else ""]
		var state := ""
		if s.mind.needs_bed():
			state = ", krank"
		elif s.hunger < 35.0:
			state = ", hungrig"
		lines.append("- %s, %d Jahre, %s; kann: %s%s%s" % [s.display_name, int(s.age), _jname(s.job), _skill_text(s), state, last])
	if adults.size() > 16:
		var rest := {}
		for s in adults.slice(16):
			rest[s.job] = int(rest.get(s.job, 0)) + 1
		var parts := []
		for j in rest:
			parts.append("%d %s" % [int(rest[j]), _jname(j)])
		lines.append("- und %d weitere: %s" % [adults.size() - 16, ", ".join(parts)])
	return "\n".join(lines)


## Die ganze Lage einer Insel für den Rat (was josh aufgezählt hat).
func island_report(w) -> String:
	var sit: Dictionary = Society.situation(w)
	var need := _needs(w, sit)
	return "%s.\nInsel %s. Siedler: %d (%d Erwachsene, %d Kinder), Wohnplätze %d.\nErwachsene:\n%s\nGebäude: %s.\nVorräte: Essen %d (%s). Material: %s. Lager %d %% voll.\nDie Insel braucht: %s.\nRohstoffe auf der Insel: %s.\nInseln:\n%s\nSchiffe:\n%s" % [
		_when(), Sea.island_name(w), int(sit.pop), int(sit.adults), int(sit.kids), int(sit.housing),
		_settlers_text(w), _buildings_text(w), int(sit.food), _food_text(w), _stock_text(w), int(float(sit.storage_full) * 100.0),
		", ".join(need) if not need.is_empty() else "nichts Dringendes", _resources_text(w), _islands_text(w), _ships_text()]


## Systemtext des Rats: Rolle, Ziel, Spielregeln, Herrscher, Gedächtnis.
func council_system(w) -> String:
	var m := mem(w)
	var main: bool = int(w.island_id) == 0
	var goal := "Euer Ziel: Die Insel soll wachsen und die Forschung soll vorankommen. Ihr entscheidet auch, was als Nächstes erforscht wird." if main \
		else "Euer Ziel: Die Insel soll wachsen. Forschung entscheidet die Hauptinsel."
	var t := "Ihr seid der Inselrat von %s in einem Aufbauspiel. Ihr sagt den Bewohnern, was sie tun sollen, und entscheidet, was gebaut wird. Die Bewohner entscheiden am Ende selbst. %s\nSpielregeln: %s" % [
		Sea.island_name(w), goal, _season_rules()]
	var pr := []
	for k in cfg("priorities", {}):
		var v := prio(w, k)
		if v != 1:
			pr.append("%s %s" % [cfg("priorities", {})[k], PRIO_WORDS[v]])
	if not pr.is_empty():
		t += "\nPrioritäten des Herrschers: %s." % ", ".join(pr)
	var wishes := []
	for x in m.wishes:
		if Game.time_days - float(x[0]) < 3.0:
			wishes.append("„%s“" % x[1])
	if not wishes.is_empty():
		t += "\nDer Herrscher hat euch gesagt: %s" % " ".join(wishes)
	var binds := []
	for b in m.binding:
		binds.append(_binding_text(b))
	if not binds.is_empty():
		t += "\nFeste Vorgaben des Herrschers (müssen befolgt werden): %s." % "; ".join(binds)
	var mem_t := memory_text(w)
	if mem_t != "":
		t += "\n" + mem_t
	return t


## Was der Rat gelernt hat: Lehren, gemessene Erfahrung, letzte Entscheidungen und Folgen.
func memory_text(w) -> String:
	var m := mem(w)
	var parts := []
	if not m.lessons.is_empty():
		var ls := []
		for l in m.lessons:
			ls.append("- " + str(l[1]))
		parts.append("Eure Lehren aus früheren Entscheidungen:\n" + "\n".join(ls))
	var ex := experience_lines(w, 5)
	if not ex.is_empty():
		parts.append("Gemessene Erfahrung (Veränderung je Tag nach eurer Entscheidung):\n" + "\n".join(ex))
	var rec := []
	for r in m.records.slice(maxi(0, m.records.size() - 4)):
		rec.append("- " + record_text(r))
	if not rec.is_empty():
		parts.append("Eure letzten Entscheidungen und was danach geschah:\n" + "\n".join(rec))
	return "\n".join(parts)


func _binding_text(b: Dictionary) -> String:
	match str(b.kind):
		"fokus":
			return "Schwerpunkt %s" % Society.strat_name(b.value)
		"bau":
			return "%s bauen" % Data.buildings.get(b.value, {}).get("name", b.value)
		"forschung":
			return "%s erforschen" % Data.techs.get(b.value, {}).get("name", b.value)
		"beruf":
			return "mindestens %d %s" % [int(b.get("n", 1)), _jname(b.value)]
	return str(b.value)


func _ask_text(question: String, options: Array) -> String:
	var lines := [question]
	for i in options.size():
		lines.append("%d) %s" % [i + 1, options[i]])
	lines.append("Antworte nur mit der Nummer.")
	return "\n".join(lines)


## Wählt nach den Wahrscheinlichkeiten des Modells (Temperatur < 1 macht es entschiedener).
func pick(probs: Array, temp: float) -> int:
	if probs.is_empty():
		return 0
	var w := []
	var sum := 0.0
	for p in probs:
		var v := pow(maxf(float(p), 1e-9), 1.0 / maxf(0.05, temp))
		w.append(v)
		sum += v
	var r := _rng.randf() * sum
	for i in w.size():
		r -= float(w[i])
		if r <= 0.0:
			return i
	return w.size() - 1


func _probs_text(labels: Array, probs: Array, top: int = 3) -> String:
	var idx := range(mini(labels.size(), probs.size()))
	idx.sort_custom(func(a, b): return float(probs[a]) > float(probs[b]))
	var parts := []
	for i in idx.slice(0, top):
		parts.append("%s %d %%" % [labels[i], int(round(float(probs[i]) * 100.0))])
	return ", ".join(parts)


## Eine Auswahlfrage an den Rat. Gibt {i, probs, ok} zurück.
func _council_choose(w, ep: int, system: String, report: String, topic: String, question: String, options: Array, hint: Array) -> Dictionary:
	activity = "Rat von %s denkt nach: %s" % [Sea.island_name(w), topic]
	changed.emit()
	var msgs := [{"role": "system", "content": system}, {"role": "user", "content": report + "\n\n" + _ask_text(question, options)}]
	last_prompt["rat"] = system + "\n\n" + msgs[1].content
	var job = Llm.choose("rat", msgs, options.size(), hint)
	var r: Dictionary = await job.wait()
	if ep != epoch or not r.get("ok", false):
		return {"ok": false, "error": r.get("error", "")}
	var probs: Array = r.get("probs", [])
	var clar := clarity(probs)
	var i: int
	var rule := "Modell"
	if clar < float(cfg("undecided_clarity", 1.35)):
		# Keine klare Meinung: nicht würfeln, die stärkste Nummer nehmen
		i = _argmax(probs)
		rule = "unentschlossen, stärkste Nummer"
	else:
		i = pick(probs, float(cfg("council_temperature", 0.35)))
	trace({"who": "Rat", "isl": Sea.island_name(w), "role": "rat", "topic": topic, "prompt": last_prompt["rat"], "options": options,
		"probs": probs, "mass": float(r.get("mass", 0.0)), "top": str(r.get("top", "")), "ms": float(r.get("ms", 0.0)),
		"clarity": clar, "choice": options[i] if i < options.size() else "?", "rule": rule})
	return {"ok": true, "i": i, "probs": probs, "mass": float(r.get("mass", 0.0)), "top": str(r.get("top", "")), "ms": float(r.get("ms", 0.0)),
		"clarity": clar, "rule": rule}


# ================================================================== Rat
func _council(w, ep: int) -> void:
	var m := mem(w)
	var sit: Dictionary = Society.situation(w)
	Society._make_households(w, sit)
	_evaluate(w, sit)
	_prune_binding(w)
	var system := council_system(w)
	var report := island_report(w)
	var last := {"day": Game.time_days}
	var where := Sea.island_name(w)

	# 1. Schwerpunkt
	var forced := _binding_value(w, "fokus")
	var keys: Array = Society.strategies().keys().filter(func(k): return Society.strategy_allowed(k))
	var sc: Dictionary = Society.situation_scores(w, sit)
	keys.sort_custom(func(a, b): return float(sc.get(a, 0.0)) > float(sc.get(b, 0.0)))
	if forced != "":
		m.focus = forced
		last.focus = {"choice": Society.strat_name(forced), "why": "Vorgabe des Herrschers"}
	else:
		var opts := keys.map(func(k): return "%s: %s" % [Society.strat_name(k), Society.strategies()[k].get("desc", "")])
		var hint := keys.map(func(k): return maxf(0.05, float(sc.get(k, 0.0))))
		var r := await _council_choose(w, ep, system, report, "Schwerpunkt", "Welcher Schwerpunkt ist für eure Insel jetzt am wichtigsten?", opts, hint)
		if not r.ok:
			return
		var labels := keys.map(func(k): return Society.strat_name(k))
		if keys[r.i] != m.focus:
			Society.log_line(w, "Der Rat (Llama) wählt den Schwerpunkt „%s“ (vorher „%s“)." % [labels[r.i], Society.strat_name(m.focus)])
		m.focus = keys[r.i]
		last.focus = {"choice": labels[r.i], "probs": _probs_text(labels, r.probs), "mass": r.mass}
		Society.decide(w, "Rat: Schwerpunkt %s. Modell: %s." % [labels[r.i], last.focus.probs])
	Society.state(w).strategy = m.focus

	# 2. Welche Arbeit ist wie wichtig? Daraus bekommt jeder Siedler einen Auftrag.
	var jobs := _job_options(w, sit)
	if not jobs.is_empty():
		var want: Dictionary = Society.desired_jobs(w, sit)
		jobs.sort_custom(func(a, b): return float(want.get(a, 0.0)) > float(want.get(b, 0.0)))
		jobs = jobs.slice(0, 9)
		var opts := jobs.map(func(j): return "%s: %s" % [_jname(j), Data.jobs[j].get("desc", "")])
		var hint := jobs.map(func(j): return 0.1 + float(want.get(j, 0.0)))
		var r := await _council_choose(w, ep, system, report, "Arbeit", "Welche Arbeit brauchen eure Bewohner jetzt am dringendsten?", opts, hint)
		if not r.ok:
			return
		var shares := {}
		for i in jobs.size():
			shares[jobs[i]] = float(r.probs[i]) if i < r.probs.size() else 0.0
		m.shares = shares
		var labels := jobs.map(func(j): return _jname(j))
		last.jobs = {"probs": _probs_text(labels, r.probs, 5), "mass": r.mass}
		_make_orders(w, sit)
		Society.decide(w, "Rat: Arbeit verteilt nach %s." % last.jobs.probs)

	# 3. Bauen
	if not await _alive(ep):
		return
	var bforced := _binding_value(w, "bau")
	if bforced != "":
		_build(w, {"type": bforced, "why": "Vorgabe des Herrschers."}, "auf Befehl des Herrschers")
		_drop_binding(w, "bau")
		last.build = {"choice": Data.buildings[bforced].name, "why": "Vorgabe des Herrschers"}
	elif w.fire_building() != null and w.construction_sites().size() < 2:
		var cands := build_options(w, sit)
		if not cands.is_empty():
			cands = cands.slice(0, int(cfg("max_options", 8)))
			var opts := cands.map(func(c): return "%s: %s Kosten %s." % [_build_name(w, c), c.why, _cost_text(c.type)])
			opts.append("Nichts bauen, Material sparen.")
			var hint := []
			for i in cands.size():
				hint.append(1.0 / (1.0 + i))
			hint.append(0.3)
			var r := await _council_choose(w, ep, system, report, "Bauen", "Was soll als Nächstes gebaut werden?", opts, hint)
			if not r.ok:
				return
			var labels := cands.map(func(c): return _build_name(w, c))
			labels.append("nichts")
			last.build = {"choice": labels[r.i], "probs": _probs_text(labels, r.probs), "mass": r.mass}
			if r.i < cands.size():
				_build(w, cands[r.i], "der Rat hat es beschlossen")
			Society.decide(w, "Rat: Bauen %s. Modell: %s." % [labels[r.i], last.build.probs])

	# 4. Forschung (nur Hauptinsel)
	if not await _alive(ep):
		return
	if int(w.island_id) == 0 and Game.research.current == "":
		var tforced := _binding_value(w, "forschung")
		if tforced != "" and Game.tech_state(tforced) == "available":
			_research(w, tforced, "auf Befehl des Herrschers")
			_drop_binding(w, "forschung")
			last.research = {"choice": Data.techs[tforced].name, "why": "Vorgabe des Herrschers"}
		else:
			var techs := research_options(w)
			if not techs.is_empty():
				var opts := techs.map(func(t): return "%s: %s" % [Data.techs[t].name, Data.techs[t].get("desc", "")])
				var hint := []
				for i in techs.size():
					hint.append(1.0 / (1.0 + i))
				var r := await _council_choose(w, ep, system, report, "Forschung", "Was sollen eure Forscher als Nächstes erforschen?", opts, hint)
				if not r.ok:
					return
				var labels := techs.map(func(t): return Data.techs[t].name)
				last.research = {"choice": labels[r.i], "probs": _probs_text(labels, r.probs), "mass": r.mass}
				_research(w, techs[r.i], "der Rat hat es beschlossen")
				Society.decide(w, "Rat: Forschung %s. Modell: %s." % [labels[r.i], last.research.probs])

	# 5. Handel mit anderen Inseln
	if not await _alive(ep):
		return
	var tr := await _trade(w, ep, system, report, sit)
	if ep != epoch:
		return
	if tr != "":
		last.trade = tr

	# 6. Was sagt der Rat den Bewohnern?
	activity = "Rat von %s spricht zu den Bewohnern" % where
	var summary := _decision_summary(last)
	var msgs := [{"role": "system", "content": system},
		{"role": "user", "content": report + "\n\nIhr habt beschlossen: %s\nSagt euren Bewohnern in ein oder zwei kurzen Sätzen auf Deutsch, was sie jetzt tun sollen und warum. %s" % [summary, length_rule("reason_tokens")]}]
	last_prompt["rat"] = system + "\n\n" + msgs[1].content
	var gj = Llm.generate("rat", msgs, int(cfg("reason_tokens", 60)), 0.0, "Wir setzen auf %s. %s" % [Society.strat_name(m.focus), summary])
	var g: Dictionary = await gj.wait()
	if ep != epoch:
		return
	trace({"who": "Rat", "isl": where, "role": "rat", "topic": "Ansage an die Bewohner", "prompt": last_prompt["rat"], "text": str(g.get("text", g.get("error", ""))), "ms": float(g.get("ms", 0.0))})
	if g.get("ok", false):
		m.plan = _clean(str(g.get("text", "")))
		if m.plan != "":
			Society.log_line(w, "Der Rat sagt: „%s“" % m.plan)
			Game.notify_at(w, "Der Inselrat von %s: „%s“" % [where, m.plan], "glocke")
	last.plan = m.plan
	m.last = last
	m.councils = int(m.councils) + 1
	_remember(w, sit, last)
	Society._council_requests(w, sit)
	# Alle paar Sitzungen zieht der Rat selbst eine Lehre
	if int(m.councils) % int(cfg("reflect_every", 3)) == 0 and m.records.size() >= 2:
		await _reflect(w, ep, system)
	Society.changed.emit()
	changed.emit()


func _decision_summary(last: Dictionary) -> String:
	var parts := []
	if last.has("focus"):
		parts.append("Schwerpunkt %s" % last.focus.choice)
	if last.has("jobs"):
		parts.append("Arbeit: %s" % last.jobs.probs)
	if last.has("build"):
		parts.append("Bauen: %s" % last.build.choice)
	if last.has("research"):
		parts.append("Forschen: %s" % last.research.choice)
	if last.has("trade"):
		parts.append("Handel: %s" % last.trade)
	return ". ".join(parts) + "."


## Längengrenze für freie Antworten, steht in der Anfrage: Das Modell soll selbst kurz bleiben,
## statt an der Grenze abgeschnitten zu werden. Die Grenze zählt Wortstücke (Token); ein deutsches
## Wort sind etwa zwei, darum steht in der Anfrage die Hälfte als Wörter.
func length_rule(key: String) -> String:
	var words := int(int(cfg(key, 140)) / 2)
	return "Eure ganze Antwort darf höchstens %d Wörter lang sein, sonst wird sie abgeschnitten. Hört mit einem ganzen Satz auf." % words


## Antwort eines Modells aufräumen. Hört das Modell mitten im Satz auf (Wortgrenze erreicht),
## bleibt nur bis zum letzten ganzen Satz stehen; sonst wäre der Text abgeschnitten, auch in den
## Lehren, die der Rat in jeder Anfrage wieder liest.
func _clean(t: String) -> String:
	t = t.strip_edges().replace("\n", " ")
	while "  " in t:
		t = t.replace("  ", " ")
	if t.length() > 400:
		t = t.substr(0, 400)
	var ends := [".", "!", "?"]
	var tail := t.rstrip(" „“\"')»«")
	if tail != "" and not tail.right(1) in ends:
		var dot := -1
		for e in ends:
			dot = maxi(dot, t.rfind(e + " "))
		if dot >= 10:
			t = t.substr(0, dot + 1)
		else:
			t = t.rstrip(" ,;:-") + " …"
	return t


# ------------------------------------------------------------------ Arbeit
## Berufe, die auf der Insel gerade überhaupt etwas zu tun haben.
func _job_options(w, sit: Dictionary) -> Array:
	var want: Dictionary = Society.desired_jobs(w, sit)
	var caps: Dictionary = Society._caps
	var out := []
	for j in JOB_ORDER:
		if not Data.job_unlocked(j):
			continue
		match j:
			"sammler", "fischer", "bauer":
				if float(caps.get(j, 0.0)) <= 0.0:
					continue
			"koch", "handwerker":
				if float(want.get(j, 0.0)) <= 0.0:
					continue
			"forscher":
				if not w.buildings.any(func(b): return b.complete and b.def.has("research")):
					continue
			"jaeger":
				if int(sit.predators) == 0 and not w.animals.any(func(a): return is_instance_valid(a)):
					continue
		out.append(j)
	return out


## Aus den Anteilen des Rats Plätze je Beruf und daraus einen Auftrag für jeden Siedler.
func _make_orders(w, sit: Dictionary) -> void:
	var m := mem(w)
	var free := []
	for s in w.settlers:
		if s.is_adult() and s.job != "seemann" and not s.mind.needs_bed() and float(Society.orders.get(s.id, 0.0)) <= Game.time_days:
			free.append(s)
	var n := free.size()
	if n == 0:
		return
	var caps: Dictionary = Society._caps
	var pj: Dictionary = cfg("priority_jobs", {})
	var weights := {}
	var total := 0.0
	for j in m.shares:
		var f := 1.0
		for k in pj:
			if j in pj[k]:
				f = PRIO_FACTOR[prio(w, k)]
		weights[j] = float(m.shares[j]) * f
		total += float(weights[j])
	var slots := {}
	if total > 0.0:
		# Größte Reste: n Plätze nach Anteil, Natur begrenzt Sammler, Fischer, Bauern
		var rem := []
		var used := 0
		for j in weights:
			var exact := float(weights[j]) / total * n
			var lim := 99
			if j in ["sammler", "fischer", "bauer"]:
				lim = int(ceil(float(caps.get(j, 0.0)) * (1.0 if j == "bauer" else 0.7)))
			var k := mini(int(floor(exact)), lim)
			slots[j] = k
			used += k
			rem.append([exact - k, j, lim])
		rem.sort_custom(func(a, b): return a[0] > b[0])
		var guard := 0
		while used < n and guard < 50:
			guard += 1
			var placed := false
			for r in rem:
				if used >= n:
					break
				if int(slots[r[1]]) < int(r[2]):
					slots[r[1]] = int(slots[r[1]]) + 1
					used += 1
					placed = true
			if not placed:
				break
	# Feste Vorgaben: mindestens so viele
	for b in m.binding:
		if b.kind == "beruf":
			slots[b.value] = maxi(int(slots.get(b.value, 0)), int(b.get("n", 1)))
	# Not: Ohne Essen verhungern alle. Mindestens die Hälfte des Bedarfs an Nahrungsarbeit.
	if float(sit.food_ratio) < 0.4:
		var food_now := 0
		for j in ["sammler", "fischer", "bauer"]:
			food_now += int(slots.get(j, 0))
		var need := mini(n, int(ceil((float(sit.adults) + float(sit.kids) * 0.5) / float(Society.cfg("gatherer_feeds", 1.5)) * 0.5)))
		for j in ["fischer", "sammler", "bauer"]:
			while food_now < need and float(caps.get(j, 0.0)) > float(slots.get(j, 0)):
				slots[j] = int(slots.get(j, 0)) + 1
				food_now += 1
		if food_now > 0:
			m["note"] = "Notregel: Das Essen reicht kaum, mindestens %d sollen Nahrung holen." % need
	else:
		m.erase("note")
	# Siedler auf Plätze verteilen: wer es am besten kann, bleibt oder kommt dorthin
	var pairs := []
	for s in free:
		for j in slots:
			if int(slots[j]) <= 0:
				continue
			var sk: String = Data.jobs.get(j, {}).get("skill", "")
			var v: float = (float(s.mind.talents.get(sk, 1.0)) + s.skill_level(sk) * 0.06) if sk != "" else 1.0
			if s.job == j:
				v += 0.5
			pairs.append([v, s, j])
	pairs.sort_custom(func(a, b): return a[0] > b[0])
	var orders := {}
	var left := slots.duplicate()
	for p in pairs:
		var s = p[1]
		if orders.has(str(s.id)) or int(left.get(p[2], 0)) <= 0:
			continue
		orders[str(s.id)] = p[2]
		left[p[2]] = int(left[p[2]]) - 1
	for s in free:
		if not orders.has(str(s.id)):
			orders[str(s.id)] = "frei"
	m.orders = orders
	m["slots"] = slots


func council_order(s) -> String:
	if s.world == null:
		return ""
	return str(mem(s.world).orders.get(str(s.id), ""))


# ------------------------------------------------------------------ Bauen
func _cost_text(t: String) -> String:
	var parts := []
	var c: Dictionary = Data.buildings[t].get("cost", {})
	for id in c:
		parts.append("%d %s" % [int(c[id]), Data.resource_name(id)])
	return ", ".join(parts) if not parts.is_empty() else "nichts"


func _build_name(w, c: Dictionary) -> String:
	if c.has("upgrade"):
		var b = w.building_by_id(int(c.upgrade))
		return "%s zu %s ausbauen" % [b.def.name if b else "?", Data.buildings[c.type].name]
	return Data.buildings[c.type].name


## Alle Bauten, die gerade sinnvoll und bezahlbar sind, die dringendsten zuerst.
func build_options(w, sit: Dictionary) -> Array:
	var out := []
	var seen := {}
	var add := func(c: Dictionary):
		var key: String = c.type + str(c.get("upgrade", ""))
		if not seen.has(key) and Data.buildings.has(c.type) and Game.can_afford(Data.buildings[c.type].get("cost", {}), w):
			seen[key] = true
			out.append(c)
	var first: Dictionary = Society._choose_building(w, sit)
	if not first.is_empty():
		add.call(first)
	if int(sit.season) in [Seasons.SPRING, Seasons.SUMMER]:
		add.call({"type": "feld", "why": "Mehr Felder bringen mehr Essen (Ernte im Sommer und Herbst)."})
		if Game.is_unlocked("obstgarten"):
			add.call({"type": "obstgarten", "why": "Obst bringt Vitamine."})
	for t in Society.HOUSE_ORDER:
		if Game.is_unlocked(t) and Data.buildings[t].get("buildable", true):
			add.call({"type": t, "why": "Mehr Wohnplatz (%d Siedler, %d Plätze)." % [int(sit.pop), int(sit.housing)]})
			break
	for b in w.buildings:
		var to: String = b.def.get("upgrade", "")
		if b.complete and b.housing() > 0 and to != "" and Game.is_unlocked(to):
			add.call({"type": to, "upgrade": b.id, "why": "Mehr Platz für Familien."})
			break
	for t in Society.PROD_ORDER:
		if Game.is_unlocked(t) and Society._count(w, [t]) == 0:
			add.call({"type": t, "why": "%s fehlt noch auf der Insel." % Data.buildings[t].name})
	for t in ["schreibstube", "bibliothek", "universitaet", "labor", "schule"]:
		if Game.is_unlocked(t) and Society._count(w, [t]) == 0:
			add.call({"type": t, "why": "Ein Ort zum Forschen und Lernen."})
	if float(sit.storage_full) > 0.7:
		add.call({"type": "lager", "why": "Das Lager ist zu %d %% voll." % int(float(sit.storage_full) * 100.0)})
	if Game.is_unlocked("wachturm") and int(sit.predators) > 0:
		add.call({"type": "wachturm", "why": "%d Raubtiere auf der Insel." % int(sit.predators)})
	for t in ["werft", "anlegesteg", "hafen"]:
		if Game.is_unlocked(t) and Society._count(w, [t]) == 0:
			add.call({"type": t, "why": "Für Schiffe und Handel."})
			break
	return out


func _build(w, c: Dictionary, how: String) -> void:
	var def: Dictionary = Data.buildings[c.type]
	if c.has("upgrade"):
		var b = w.building_by_id(int(c.upgrade))
		if b and b.complete and w.upgrade_building(b) != null:
			Society.log_line(w, "Der Rat lässt %s ausbauen (%s)." % [b.def.name, how])
			Game.notify_at(w, "Der Rat lässt %s ausbauen (%s)." % [b.def.name, how], "hammer")
		return
	var spot: Vector2i = Society.find_spot(w, c.type)
	if spot.x < 0:
		Society.decide(w, "Kein Platz für %s." % def.name)
		return
	w.place_building(c.type, spot, false)
	Society.log_line(w, "Der Rat lässt bauen: %s bei (%d,%d) (%s)." % [def.name, spot.x, spot.y, how])
	Game.notify_at(w, "Der Rat lässt bauen: %s. %s" % [def.name, c.get("why", "")], "hammer")


# ------------------------------------------------------------------ Forschung
func research_options(w) -> Array:
	var focus: String = mem(w).focus
	var scored := []
	for t in Data.sorted_tech_ids():
		if Game.tech_state(t) != "available":
			continue
		var v := 0.0 if Society.choose_research(focus, w) != t else 10.0
		v -= float(Data.techs[t].get("tier", 1))
		if Game.can_afford(Data.techs[t].get("cost", {}), w):
			v += 2.0
		scored.append([v, t])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	return scored.slice(0, int(cfg("max_options", 8))).map(func(x): return x[1])


func _research(w, t: String, how: String) -> void:
	var err := Game.start_research(t)
	if err != "":
		Society.decide(w, "Forschung %s geht nicht: %s" % [Data.techs[t].name, err])
		return
	Society.log_line(w, "Die Forscher beginnen mit %s (%s)." % [Data.techs[t].name, how])
	Game.notify_at(w, "Der Rat lässt erforschen: %s." % Data.techs[t].name, "wissen")


# ================================================================== Handel
## Fragt den Rat, ob er eine andere Insel um eine Ware bittet; die andere Insel nennt ihren
## Preis, der Rat nimmt an oder nicht. Ein Schiff einer der beiden Inseln fährt dann eine
## Route hin und her, bis die Abmachung ausläuft.
func _trade(w, ep: int, system: String, report: String, sit: Dictionary) -> String:
	var others: Array = Sea.all_worlds().filter(func(o): return o != w and is_instance_valid(o) and not o.settlers.is_empty())
	if others.is_empty():
		return ""
	if trades.any(func(t): return int(t.to) == int(w.island_id) or int(t.from) == int(w.island_id)):
		return ""
	var offers := []  # [Ware, Menge, Insel]
	var need := _trade_needs(w, sit)
	for o in others:
		if Sea.ships_of(int(o.island_id)).is_empty() and Sea.ships_of(int(w.island_id)).is_empty():
			continue
		var spare := _trade_spare(o)
		for id in need:
			if spare.has(id):
				offers.append([id, mini(int(need[id]), int(spare[id])), o])
	if offers.is_empty():
		return ""
	offers = offers.slice(0, 6)
	var opts := offers.map(func(x): return "%d %s von %s holen lassen" % [int(x[1]), Data.resource_name(x[0]), Sea.island_name(x[2])])
	opts.append("Keinen Handel.")
	var hint := []
	for i in offers.size():
		hint.append(0.6 / (1.0 + i))
	hint.append(0.4)
	var r := await _council_choose(w, ep, system, report, "Handel", "Wollt ihr eine andere Insel um eine Ware bitten? Sie wird dafür etwas verlangen.", opts, hint)
	if not r.ok or r.i >= offers.size():
		return ""
	var off: Array = offers[r.i]
	var o = off[2]
	var good: String = off[0]
	var amount := int(off[1])
	Society.decide(w, "Handel: Der Rat bittet %s um %d %s." % [Sea.island_name(o), amount, Data.resource_name(good)])
	# Die andere Insel nennt ihren Preis
	if not await _alive(ep) or not is_instance_valid(o):
		return ""
	var pay := _trade_spare(w)
	pay.erase(good)
	var pay_opts := []
	for id in _trade_needs(o, Society.situation(o)):
		if pay.has(id):
			pay_opts.append([id, mini(int(pay[id]), maxi(4, amount))])
	pay_opts = pay_opts.slice(0, 5)
	var popts := pay_opts.map(func(x): return "%d %s verlangen" % [int(x[1]), Data.resource_name(x[0])])
	popts.append("Nichts verlangen, wir helfen gern.")
	popts.append("Ablehnen, wir brauchen es selbst.")
	var phint := []
	for i in pay_opts.size():
		phint.append(0.8 / (1.0 + i))
	phint.append(0.2)
	phint.append(0.25)
	var osys := council_system(o)
	var orep := island_report(o)
	var pr := await _council_choose(o, ep, osys, orep, "Handel mit %s" % Sea.island_name(w),
		"Der Rat von %s bittet euch um %d %s per Schiff. Was verlangt ihr dafür?" % [Sea.island_name(w), amount, Data.resource_name(good)], popts, phint)
	if not pr.ok or not is_instance_valid(o):
		return ""
	if pr.i == popts.size() - 1:
		Society.log_line(o, "Der Rat lehnt die Bitte von %s um %s ab." % [Sea.island_name(w), Data.resource_name(good)])
		Society.log_line(w, "%s lehnt ab: keine %s für uns." % [Sea.island_name(o), Data.resource_name(good)])
		return "%s lehnt ab" % Sea.island_name(o)
	var price := {}
	if pr.i < pay_opts.size():
		price[pay_opts[pr.i][0]] = int(pay_opts[pr.i][1])
		# Der bittende Rat stimmt über den Preis ab
		var ar := await _council_choose(w, ep, system, report, "Preis",
			"%s verlangt %s für %d %s. Nehmt ihr an?" % [Sea.island_name(o), Sea.goods_text(price), amount, Data.resource_name(good)],
			["Ja, annehmen.", "Nein, zu teuer."], [0.6, 0.4])
		if not ar.ok:
			return ""
		if ar.i != 0:
			Society.log_line(w, "Der Rat lehnt den Preis von %s ab (%s)." % [Sea.island_name(o), Sea.goods_text(price)])
			return "Preis von %s abgelehnt" % Sea.island_name(o)
	return _open_trade(w, o, {good: amount}, price)


## Was einer Insel fehlt (Ware -> Menge).
func _trade_needs(w, sit: Dictionary) -> Dictionary:
	var n := {}
	if float(sit.food_ratio) < 0.8:
		n["food"] = int(float(sit.food_target) - float(sit.food))
	if float(sit.wood) < float(sit.wood_target):
		n["holz"] = int(float(sit.wood_target) - float(sit.wood))
	if float(sit.stone) < float(sit.stone_target):
		n["stein"] = int(float(sit.stone_target) - float(sit.stone))
	# Was fehlt für Bauten, die freigeschaltet, aber nicht bezahlbar sind?
	for t in Society.PROD_ORDER:
		if Game.is_unlocked(t) and Society._count(w, [t]) == 0:
			var c: Dictionary = Data.buildings[t].get("cost", {})
			for id in c:
				if Game.amount(id, w) < int(c[id]) and id != "holz" and id != "stein":
					n[id] = int(c[id]) - Game.amount(id, w)
			break
	# "food" in die Speise umwandeln, die die andere Seite hat, passiert in _trade_spare
	var out := {}
	for id in n:
		if int(n[id]) > 0:
			out[id] = clampi(int(n[id]), 5, 60)
	return out


## Was eine Insel abgeben kann (Ware -> Menge). Essen zählt als "food".
func _trade_spare(w) -> Dictionary:
	var sit: Dictionary = Society.situation(w)
	var s := {}
	if float(sit.food) > float(sit.food_target) * 1.4 + 10.0:
		s["food"] = int((float(sit.food) - float(sit.food_target) * 1.2) / 2.0)
	if float(sit.wood) > float(sit.wood_target) * 1.4 + 10.0:
		s["holz"] = int((float(sit.wood) - float(sit.wood_target)) / 2.0)
	if float(sit.stone) > float(sit.stone_target) * 1.4 + 10.0:
		s["stein"] = int((float(sit.stone) - float(sit.stone_target)) / 2.0)
	for id in TRADE_GOODS:
		if id in ["holz", "stein"]:
			continue
		var a := Game.amount(id, w)
		if a >= 8:
			s[id] = a / 2
	for id in s.keys():
		if int(s[id]) < 4:
			s.erase(id)
	return s


func _food_good(w) -> String:
	var best := ""
	for id in Data.resources:
		if Data.resources[id].get("category", "") == "food" and (best == "" or Game.amount(id, w) > Game.amount(best, w)):
			best = id
	return best


func _open_trade(w, o, get: Dictionary, give: Dictionary) -> String:
	# Welches Schiff? Erst eines der gebenden Insel, sonst ein eigenes.
	var ship := {}
	for id in [int(o.island_id), int(w.island_id)]:
		for sh in Sea.ships_of(id):
			if sh.route.is_empty() and sh.state == "dock" and Sea.can_visit(sh.type, int(o.island_id)) and Sea.can_visit(sh.type, int(w.island_id)):
				ship = sh
				break
		if not ship.is_empty():
			break
	if ship.is_empty():
		Society.log_line(w, "Handel mit %s vereinbart, aber kein freies Schiff." % Sea.island_name(o))
		return "vereinbart, aber kein freies Schiff"
	# "food" in echte Speisen umwandeln
	var g := {}
	for id in get:
		g[_food_good(o) if id == "food" else id] = int(get[id])
	var p := {}
	for id in give:
		p[_food_good(w) if id == "food" else id] = int(give[id])
	Sea.fill_crew(ship)
	if Sea.crew_missing(ship) > 0:
		Sea.hire_sailor(ship)
	ship.route = [{"island": int(o.island_id), "load": g}, {"island": int(w.island_id), "load": p}]
	ship.leg = 0 if int(ship.at) == int(o.island_id) else 0
	ship.paused = false
	var t := {"id": next_trade, "to": int(w.island_id), "from": int(o.island_id), "get": g, "give": p, "ship": int(ship.id),
		"day": Game.time_days, "until": Game.time_days + float(cfg("trade_days", 4.0))}
	next_trade += 1
	trades.append(t)
	var text := "%s bringt %s%s mit der %s (Heimat %s)" % [Sea.island_name(o), Sea.goods_text(g),
		(" gegen " + Sea.goods_text(p)) if not p.is_empty() else " als Hilfe", ship.name, Sea.meta(int(ship.home)).get("name", "?")]
	Society.log_line(w, "Handelsroute beschlossen: %s." % text)
	Society.log_line(o, "Handelsroute beschlossen: %s." % text)
	Game.notify("Handel: %s." % text, "boot")
	return text


func _expire_trades() -> void:
	for t in trades.duplicate():
		if Game.time_days < float(t.until):
			continue
		trades.erase(t)
		var sh: Dictionary = Sea.ship_by_id(int(t.ship))
		if not sh.is_empty():
			sh.route = []
		var w = Sea.worlds.get(int(t.to))
		if w:
			Society.log_line(w, "Die Handelsroute mit %s ist ausgelaufen." % Sea.meta(int(t.from)).get("name", "?"))


# ================================================================== Siedler
func _settler_due(s) -> bool:
	if not s.is_adult() or s.job == "seemann":
		return false
	if float(Society.orders.get(s.id, 0.0)) > Game.time_days:
		Society.thoughts[s.id] = "Der Herrscher hat mich zum %s bestimmt. Das mache ich." % s.job_name()
		return false
	if s.mind.needs_bed():
		Society.thoughts[s.id] = "Ich bin krank und muss liegen."
		return false
	var d: Dictionary = sdec.get(str(s.id), {})
	return d.is_empty() or Game.time_days - float(d.get("day", -99.0)) >= float(cfg("settler_days", 0.25))


func _needs_text(s, w) -> String:
	var parts := []
	parts.append("Hunger %s" % ("groß" if s.hunger < 35.0 else ("etwas" if s.hunger < 65.0 else "keiner")))
	parts.append("Laune %d von 100" % int(s.mind.mood))
	if s.mind.rest < 30.0:
		parts.append("müde")
	if s.mind.vit < float(Data.ppl("vit_low", 30.0)):
		parts.append("braucht Vitamine (Obst, Beeren)")
	if s.mind.sick != "":
		parts.append("krank: %s" % s.mind.illness_name())
	if Seasons.is_winter() and not Seasons.is_warm(w):
		parts.append("friert")
	return ", ".join(parts)


## Die Möglichkeiten eines Siedlers: Auftrag des Rats zuerst, dann was er gerade tut,
## was ihm liegt und was die Insel braucht.
func settler_options(s, w) -> Array:
	var out := []
	var order := council_order(s)
	if order != "":
		out.append(order)
	if not s.job in out and s.job != "seemann":
		out.append(s.job)
	var sit: Dictionary = Society.situation(w)
	var avail := _job_options(w, sit)
	var fav: String = s.best_job()
	if fav in avail and not fav in out:
		out.append(fav)
	var m := mem(w)
	var sh: Array = m.shares.keys()
	sh.sort_custom(func(a, b): return float(m.shares[a]) > float(m.shares[b]))
	for j in sh:
		if out.size() >= 6:
			break
		if j in avail and not j in out:
			out.append(j)
	if s.hunger < 50.0 and not "sammler" in out and "sammler" in avail:
		out.append("sammler")
	if not "frei" in out:
		out.append("frei")
	return out.slice(0, 7)


## Englische Namen für das Siedlermodell: SmolLM-135M hat fast nur Englisch gelernt. Auf
## Deutsch verstand es die Frage kaum und gab allen Nummern fast dieselbe Wahrscheinlichkeit,
## die Entscheidung war dann gewürfelt.
const JOB_EN := {"frei": ["Helper", "helps wherever needed"], "holzfaeller": ["Woodcutter", "fells trees and brings wood"],
	"steinmetz": ["Stonemason", "breaks stone and ore"], "sammler": ["Gatherer", "picks berries and mushrooms (food)"],
	"fischer": ["Fisher", "catches fish (food)"], "bauer": ["Farmer", "works fields and orchards (food)"],
	"koch": ["Cook", "works in mill and bakery (food)"], "handwerker": ["Craftsman", "works in sawpit, brickworks and smithy"],
	"baumeister": ["Builder", "builds new houses and workshops"], "forscher": ["Researcher", "finds new knowledge"],
	"jaeger": ["Hunter", "hunts wild animals for meat and furs"], "seemann": ["Sailor", "sails on the ships"]}
const SKILL_EN := {"holz": "woodwork", "stein": "stonework", "nahrung": "food", "bauen": "building", "handwerk": "crafts",
	"wissen": "knowledge", "jagd": "hunting"}
const SEASON_EN := ["spring", "summer", "autumn", "winter"]
const FOOD_JOBS := ["sammler", "fischer", "bauer", "koch"]


func _en(j: String) -> String:
	return JOB_EN.get(j, [_jname(j)])[0]


func _talent_word(v: float) -> String:
	return "very good" if v >= 1.4 else ("good" if v >= 1.15 else ("average" if v >= 0.85 else "poor"))


## Was für und gegen eine Arbeit spricht, in kurzen englischen Stichworten: So kann auch das
## kleine Modell die Möglichkeiten auseinanderhalten.
func _option_facts(j: String, s, w, sit: Dictionary, order: String) -> Array:
	var f := []
	if j == order:
		f.append("the council orders this")
	if j == s.job:
		f.append("your current work")
	var sk: String = Data.jobs.get(j, {}).get("skill", "")
	if sk != "":
		f.append("you are %s at it" % _talent_word(float(s.mind.talents.get(sk, 1.0))))
	var food_low := float(sit.food) < float(sit.food_target)
	if j in FOOD_JOBS:
		if food_low:
			f.append("the island needs food")
		if s.hunger < 50.0 and j in ["sammler", "fischer"]:
			f.append("you are hungry")
	if j == "holzfaeller" and (float(sit.wood) < float(sit.wood_target) or Seasons.season() >= 2):
		f.append("the island needs wood" + (" for heating" if Seasons.season() >= 2 else ""))
	if j == "steinmetz" and float(sit.stone) < float(sit.stone_target):
		f.append("the island needs stone")
	if j == "baumeister" and int(sit.sites) > 0:
		f.append("%d buildings wait to be built" % int(sit.sites))
	if j == "jaeger" and int(sit.predators) > 0:
		f.append("%d dangerous animals" % int(sit.predators))
	if j == "frei" and (s.mind.rest < 30.0 or s.mind.sick != ""):
		f.append("you can rest")
	return f


func settler_prompt(s, w, opts: Array, order: String) -> Array:
	var sit: Dictionary = Society.situation(w)
	var sea := Seasons.season()
	var sname: String = SEASON_EN[clampi(sea, 0, 3)]
	var left := int(Seasons.season_days()) - Seasons.day_in_season() + 1
	var when := "It is %s, %d day%s left in this season." % [sname, left, "" if left == 1 else "s"]
	if sea == 2:
		when += " Winter comes next: nothing grows in winter and everyone needs wood for heating."
	elif sea == 3:
		when += " Nothing grows now. Food and wood are used up fast."
	var me := []
	me.append("%d years old" % int(s.age))
	me.append("hunger: %s" % ("strong" if s.hunger < 35.0 else ("some" if s.hunger < 65.0 else "none")))
	me.append("mood %d of 100" % int(s.mind.mood))
	if s.mind.rest < 30.0:
		me.append("tired")
	if s.mind.sick != "":
		me.append("sick")
	var skills := []
	var tal: Dictionary = s.mind.talents
	var ks: Array = tal.keys()
	ks.sort_custom(func(a, b): return float(tal[a]) > float(tal[b]))
	for sk in ks.slice(0, 3):
		skills.append("%s %s" % [SKILL_EN.get(sk, sk), _talent_word(float(tal[sk]))])
	var last := []
	for e in smem.get(str(s.id), []):
		last.append("%s (day %d)" % [_en(e[1]), int(float(e[0])) + 1])
	var lines := []
	for i in opts.size():
		var j: String = opts[i]
		var facts := _option_facts(j, s, w, sit, order)
		if not facts.is_empty():
			facts[0] = str(facts[0]).left(1).to_upper() + str(facts[0]).substr(1)
		lines.append("%d) %s: %s.%s" % [i + 1, _en(j), JOB_EN.get(j, ["", ""])[1], (" " + ", ".join(facts) + ".") if not facts.is_empty() else ""])
	var sys := "You are %s, a settler on the island %s. You choose your next work yourself. The island council gives you an order, but you may choose something else if it is better for you or the island." % [
		s.display_name, Sea.island_name(w)]
	var user := "%s\nYou: %s.\nYour skills: %s.\nThe island: %d settlers, food %d (goal %d), wood %d (goal %d), stone %d.\nThe council's order for you: %s.\nYour last work: %s.\n\nWhat work do you do next?\n%s\nAnswer with the number only." % [
		when, ", ".join(me), ", ".join(skills), int(sit.pop), int(sit.food), int(sit.food_target), int(sit.wood), int(sit.wood_target),
		int(sit.stone), _en(order) if order != "" else "none", ", ".join(last) if not last.is_empty() else "nothing yet", "\n".join(lines)]
	return [{"role": "system", "content": sys}, {"role": "user", "content": user}]


## Wie entschieden ist eine Verteilung? 1 = alle gleich, n = ganz sicher.
func clarity(probs: Array) -> float:
	var top := 0.0
	for p in probs:
		top = maxf(top, float(p))
	return top * probs.size()


func _argmax(probs: Array) -> int:
	var b := 0
	for i in probs.size():
		if float(probs[i]) > float(probs[b]):
			b = i
	return b


func _settler_turn(s, w) -> void:
	var ep := epoch
	var opts := settler_options(s, w)
	var order := council_order(s)
	activity = "%s überlegt, was er als Nächstes tut" % s.display_name if s.sex == "m" else "%s überlegt, was sie als Nächstes tut" % s.display_name
	var msgs := settler_prompt(s, w, opts, order)
	last_prompt["siedler"] = msgs[0].content + "\n\n" + msgs[1].content
	var hint := []
	for j in opts:
		var v := 0.15
		if j == order:
			v += 1.0
		if j == s.job:
			v += 0.4
		if j == s.best_job():
			v += 0.3
		hint.append(v)
	# Zweimal fragen, das zweite Mal in umgekehrter Reihenfolge: Kleine Modelle schreiben gern
	# einfach die 1. Gemittelt bleibt nur, was das Modell wirklich über die Arbeiten denkt.
	var rev := opts.duplicate()
	rev.reverse()
	var rhint := hint.duplicate()
	rhint.reverse()
	var msgs2 := settler_prompt(s, w, rev, order)
	var j1 = Llm.choose("siedler", msgs, opts.size(), hint, "My choice:")
	var j2 = Llm.choose("siedler", msgs2, rev.size(), rhint, "My choice:")
	var r: Dictionary = await j1.wait()
	var r2: Dictionary = await j2.wait()
	if ep != epoch or not is_instance_valid(s) or s.world != w:
		return
	if not r.get("ok", false):
		return
	var p1: Array = r.get("probs", [])
	var p2r: Array = r2.get("probs", []) if r2.get("ok", false) else []
	var probs := []
	for i in opts.size():
		var a := float(p1[i]) if i < p1.size() else 0.0
		var b := float(p2r[opts.size() - 1 - i]) if p2r.size() == opts.size() else a
		probs.append((a + b) * 0.5)
	var clar := clarity(probs)
	var i: int
	var rule: String
	if clar < float(cfg("undecided_clarity", 1.35)):
		# Das Modell hat keine klare Meinung: nicht würfeln, sondern beim Auftrag oder der Arbeit bleiben
		i = opts.find(order) if order != "" else opts.find(s.job)
		if i < 0:
			i = _argmax(probs)
		rule = "unentschlossen, %s" % ("folgt dem Auftrag" if order != "" and opts[i] == order else "bleibt dabei")
	else:
		i = pick(probs, float(cfg("settler_temperature", 0.35)))
		rule = "Modell"
	var choice: String = opts[i]
	var own := order != "" and choice != order
	var names := opts.map(func(j): return _jname(j))
	var ptext := _probs_text(names, probs)
	sdec[str(s.id)] = {"day": Game.time_days, "job": choice, "order": order, "own": own, "probs": ptext,
		"mass": float(r.get("mass", 0.0)), "top": str(r.get("top", "")), "clarity": clar, "rule": rule}
	trace({"who": s.display_name, "isl": Sea.island_name(w), "role": "siedler", "topic": "Arbeit", "prompt": last_prompt["siedler"],
		"prompt2": msgs2[1].content, "options": names, "probs": probs, "probs_a": p1, "probs_b": p2r, "mass": [r.get("mass", 0.0), r2.get("mass", 0.0)],
		"top": [r.get("top", ""), r2.get("top", "")], "ms": float(r.get("ms", 0.0)) + float(r2.get("ms", 0.0)), "clarity": clar,
		"choice": names[i], "order": _jname(order) if order != "" else "", "rule": rule, "own": own})
	var hist: Array = smem.get(str(s.id), [])
	hist.append([snappedf(Game.time_days, 0.01), choice, own])
	if hist.size() > 3:
		hist = hist.slice(hist.size() - 3)
	smem[str(s.id)] = hist
	var old: String = s.job
	if choice != old:
		s.set_job(choice)
		Society.last_change[s.id] = Game.time_days
		Society.decide(w, "%s wird %s (vorher %s)%s. Modell: %s." % [s.display_name, _jname(choice), _jname(old),
			", gegen den Auftrag (%s)" % _jname(order) if own else ", wie der Rat sagt", ptext])
	var t := "Ich bin %s." % _jname(choice)
	if own:
		t += " Der Rat wollte mich als %s, aber ich habe selbst anders entschieden." % _jname(order)
	elif order != "":
		t += " Das ist mein Auftrag vom Rat."
	if rule != "Modell":
		t += " (Ich war unentschlossen.)"
	Society.thoughts[s.id] = t
	changed.emit()


# ================================================================== Lernen
func _metrics(w, sit: Dictionary) -> Dictionary:
	var mood := 0.0
	var sick := 0
	for s in w.settlers:
		mood += s.mind.mood
		if s.mind.sick != "":
			sick += 1
	return {"food": int(sit.food), "wood": int(sit.wood), "stone": int(sit.stone), "pop": int(sit.pop),
		"mood": int(mood / maxf(1.0, w.settlers.size())), "sick": sick, "techs": Game.research.done.size(),
		"houses": int(sit.housing)}


func _remember(w, sit: Dictionary, last: Dictionary) -> void:
	var m := mem(w)
	var jobs := {}
	for s in w.settlers:
		if s.is_adult():
			jobs[s.job] = int(jobs.get(s.job, 0)) + 1
	var rec := {"d": snappedf(Game.time_days, 0.01), "s": int(sit.season), "focus": m.focus,
		"build": str(last.get("build", {}).get("choice", "")), "research": str(last.get("research", {}).get("choice", "")),
		"trade": str(last.get("trade", "")), "jobs": jobs, "m": _metrics(w, sit)}
	m.records.append(rec)
	var mx := int(cfg("memory_records", 30))
	if m.records.size() > mx:
		m.records = m.records.slice(m.records.size() - mx)


func record_text(r: Dictionary) -> String:
	var t := "Tag %d (%s): Schwerpunkt %s" % [int(float(r.d)) + 1, Seasons.season_name(int(r.s)), Society.strat_name(str(r.focus))]
	if str(r.get("build", "")) not in ["", "nichts"]:
		t += ", gebaut %s" % r.build
	if str(r.get("research", "")) != "":
		t += ", erforscht %s" % r.research
	if str(r.get("trade", "")) != "":
		t += ", Handel: %s" % r.trade
	if r.has("out"):
		var o: Dictionary = r.out
		t += " -> danach je Tag: Essen %+.1f, Holz %+.1f, Stein %+.1f, Siedler %+.1f, Laune %+.1f" % [float(o.food), float(o.wood), float(o.stone), float(o.pop), float(o.mood)]
	return t


## Misst, was seit der letzten Entscheidung geschehen ist, und lernt daraus.
func _evaluate(w, sit: Dictionary) -> void:
	var m := mem(w)
	if m.records.is_empty():
		return
	var r: Dictionary = m.records[m.records.size() - 1]
	if r.has("out"):
		return
	var dt := Game.time_days - float(r.d)
	if dt < 0.5:
		return
	var now := _metrics(w, sit)
	var b: Dictionary = r.m
	var o := {}
	for k in ["food", "wood", "stone", "pop", "mood", "sick", "techs"]:
		o[k] = snappedf((float(now[k]) - float(b.get(k, 0))) / dt, 0.1)
	r["out"] = o
	# Erfahrung je Jahreszeit und Schwerpunkt
	var key := "%d|%s" % [int(r.s), str(r.focus)]
	var e: Array = m.exp.get(key, [0, 0.0, 0.0, 0.0, 0.0, 0.0])
	e[0] = int(e[0]) + 1
	e[1] = float(e[1]) + float(o.food)
	e[2] = float(e[2]) + float(o.wood)
	e[3] = float(e[3]) + float(o.stone)
	e[4] = float(e[4]) + float(o.pop)
	e[5] = float(e[5]) + float(o.mood)
	m.exp[key] = e
	_measure_lesson(w, r, o)


## Erfahrung als Text, die passende Jahreszeit zuerst.
func experience_lines(w, n: int) -> Array:
	var m := mem(w)
	var keys: Array = m.exp.keys()
	var cur := int(Seasons.season())
	keys.sort_custom(func(a, b):
		var sa := 1 if int(str(a).split("|")[0]) == cur else 0
		var sb := 1 if int(str(b).split("|")[0]) == cur else 0
		if sa != sb:
			return sa > sb
		return int(m.exp[a][0]) > int(m.exp[b][0]))
	var out := []
	for k in keys.slice(0, n):
		var e: Array = m.exp[k]
		var c := float(e[0])
		var p := str(k).split("|")
		out.append("- %s, Schwerpunkt %s: Essen %+.1f, Holz %+.1f, Stein %+.1f, Siedler %+.1f, Laune %+.1f (%d mal)" % [
			Seasons.season_name(int(p[0])), Society.strat_name(p[1]), float(e[1]) / c, float(e[2]) / c, float(e[3]) / c,
			float(e[4]) / c, float(e[5]) / c, int(c)])
	return out


## Aus einer auffälligen Messung eine Lehre über die Spielmechanik machen.
func _measure_lesson(w, r: Dictionary, o: Dictionary) -> void:
	var food_workers := 0
	for j in ["sammler", "fischer", "bauer", "koch"]:
		food_workers += int(r.jobs.get(j, 0))
	var season := Seasons.season_name(int(r.s))
	var text := ""
	var kind := ""
	if float(o.food) < -2.0 and food_workers > 0:
		kind = "essen"
		text = "Im %s sank das Essen um %.1f je Tag, obwohl %d Leute Nahrung holten. %s" % [season, -float(o.food), food_workers,
			"Vor dem Winter Vorrat anlegen." if int(r.s) in [Seasons.AUTUMN, Seasons.WINTER] else "Mehr Felder oder Fischer nötig."]
	elif float(o.food) < -1.0 and food_workers == 0:
		kind = "ohne"
		text = "Ohne Nahrungsarbeiter sinkt das Essen schnell (%.1f je Tag im %s)." % [float(o.food), season]
	elif float(o.wood) < -3.0 and int(r.s) in [Seasons.AUTUMN, Seasons.WINTER]:
		kind = "holz"
		text = "Im %s verbrennen wir viel Holz (%.1f je Tag). Im Sommer Holz sammeln." % [season, float(o.wood)]
	elif float(o.pop) > 0.4:
		kind = "wachsen|" + str(r.focus)
		text = "Mit Schwerpunkt %s im %s wuchs die Insel (+%.1f Siedler je Tag)." % [Society.strat_name(str(r.focus)), season, float(o.pop)]
	elif float(o.mood) < -5.0:
		kind = "laune"
		text = "Im %s fiel die Laune stark (%.1f je Tag). Feste und Freizeit helfen." % [season, float(o.mood)]
	if text != "":
		# Dieselbe Beobachtung in derselben Jahreszeit ersetzt die alte (neueste Zahlen)
		add_lesson(w, text, "Messung", "%s|%d" % [kind, int(r.s)])


func add_lesson(w, text: String, source: String, key: String = "") -> void:
	var m := mem(w)
	text = _clean(text)
	if text == "":
		return
	for l in m.lessons.duplicate():
		if str(l[1]) == text:
			return
		if key != "" and l.size() > 3 and str(l[3]) == key:
			m.lessons.erase(l)
	m.lessons.append([snappedf(Game.time_days, 0.01), text, source, key])
	var mx := int(cfg("lessons_max", 10))
	while m.lessons.size() > mx:
		# Die älteste Lehre derselben Herkunft fällt weg, sonst die älteste überhaupt
		var drop := 0
		for i in m.lessons.size():
			if str(m.lessons[i][2]) == source:
				drop = i
				break
		m.lessons.remove_at(drop)
	Society.decide(w, "Lehre (%s): %s" % [source, text])


## Llama schaut auf seine letzten Entscheidungen und deren Folgen und zieht selbst eine Lehre.
func _reflect(w, ep: int, system: String) -> void:
	var m := mem(w)
	var lines := []
	for r in m.records.slice(maxi(0, m.records.size() - 6)):
		lines.append("- " + record_text(r))
	activity = "Rat von %s denkt über seine Entscheidungen nach" % Sea.island_name(w)
	var msgs := [{"role": "system", "content": system},
		{"role": "user", "content": "Eure letzten Entscheidungen und was danach geschah:\n%s\n\nWas habt ihr daraus über die Spielmechanik gelernt? Schreibt eine kurze, konkrete Lehre in einem Satz auf Deutsch, die euch künftig hilft. %s" % ["\n".join(lines), length_rule("reason_tokens")]}]
	last_prompt["rat"] = system + "\n\n" + msgs[1].content
	var hint := "Im %s brauchen wir mehr Nahrungsarbeiter, wenn das Essen sinkt." % Seasons.season_name()
	var j = Llm.generate("rat", msgs, int(cfg("reason_tokens", 60)), 0.0, hint)
	var g: Dictionary = await j.wait()
	trace({"who": "Rat", "isl": Sea.island_name(w), "role": "rat", "topic": "Lehre ziehen", "prompt": last_prompt["rat"], "text": str(g.get("text", g.get("error", ""))), "ms": float(g.get("ms", 0.0))})
	if ep != epoch or not g.get("ok", false):
		return
	add_lesson(w, str(g.get("text", "")), "Rat")


# ================================================================== Herrscher
## Der Herrscher schreibt dem Rat. Der Rat antwortet, der Wunsch fließt in seine nächsten Entscheidungen.
func chat(w, text: String) -> void:
	text = text.strip_edges()
	if text == "":
		return
	var m := mem(w)
	m.chat.append(["Du", text, snappedf(Game.time_days, 0.01)])
	m.wishes.append([snappedf(Game.time_days, 0.01), text])
	if m.wishes.size() > 3:
		m.wishes = m.wishes.slice(m.wishes.size() - 3)
	m.waiting = true
	changed.emit()
	if not active():
		m.chat.append(["Rat", "(Die Sprachmodelle sind nicht geladen. Dein Wunsch ist notiert und gilt für die nächsten Ratssitzungen.)", snappedf(Game.time_days, 0.01)])
		m.waiting = false
		changed.emit()
		return
	var ep := epoch
	var hist := []
	for c in m.chat.slice(maxi(0, m.chat.size() - 7), m.chat.size() - 1):
		hist.append("%s: %s" % ["Herrscher" if c[0] == "Du" else "Rat", c[1]])
	var msgs := [{"role": "system", "content": council_system(w)},
		{"role": "user", "content": "%s\n\n%sDer Herrscher sagt zu euch: „%s“\nAntwortet dem Herrscher kurz auf Deutsch (höchstens drei Sätze). Sagt, ob und wie ihr seinem Wunsch folgt. %s" % [
			island_report(w), ("Bisheriges Gespräch:\n%s\n\n" % "\n".join(hist)) if not hist.is_empty() else "", text, length_rule("chat_tokens")]}]
	last_prompt["rat"] = msgs[0].content + "\n\n" + msgs[1].content
	var j = Llm.generate("rat", msgs, int(cfg("chat_tokens", 90)), 0.3, "Wir haben deinen Wunsch gehört und berücksichtigen ihn bei der nächsten Sitzung.")
	var g: Dictionary = await j.wait()
	trace({"who": "Rat", "isl": Sea.island_name(w), "role": "rat", "topic": "Gespräch mit dem Herrscher", "prompt": last_prompt["rat"], "text": str(g.get("text", g.get("error", ""))), "ms": float(g.get("ms", 0.0))})
	if ep != epoch:
		return
	m.waiting = false
	var ans := _clean(str(g.get("text", ""))) if g.get("ok", false) else "(Keine Antwort: %s)" % g.get("error", "")
	m.chat.append(["Rat", ans, snappedf(Game.time_days, 0.01)])
	if m.chat.size() > 30:
		m.chat = m.chat.slice(m.chat.size() - 30)
	Society.decide(w, "Gespräch: Herrscher „%s“, Rat „%s“" % [text, ans])
	# Der Rat soll bald neu entscheiden, damit der Wunsch wirkt
	m.next_council = minf(float(m.next_council), Game.time_days + 0.1)
	changed.emit()
	Society.changed.emit()


## Feste Vorgabe des Herrschers: kind fokus|bau|forschung|beruf. Kostet Vertrauen.
func bind(w, kind: String, value: String, n: int = 1) -> String:
	var m := mem(w)
	m.binding = m.binding.filter(func(b): return not (b.kind == kind and (kind != "beruf" or b.value == value)))
	var b := {"kind": kind, "value": value, "n": n, "until": Game.time_days + 3.0}
	m.binding.append(b)
	Society._add_trust(w, "command")
	Society.state(w).resent_until = Game.time_days + float(Society.cfg("resent_days", 2.0)) * 0.5
	var msg := ""
	match kind:
		"fokus":
			m.focus = value
			Society.state(w).strategy = value
		"bau":
			var spot: Vector2i = Society.find_spot(w, value)
			if not Game.can_afford(Data.buildings[value].get("cost", {}), w):
				msg = "Dafür fehlt Material. Der Rat baut es, sobald es reicht."
			elif spot.x < 0:
				msg = "Kein Platz für %s." % Data.buildings[value].name
			else:
				_build(w, {"type": value, "why": "Befehl des Herrschers."}, "auf Befehl des Herrschers")
				_drop_binding(w, "bau")
		"forschung":
			if Game.research.current == "" or Game.research.current != value:
				var err := Game.start_research(value)
				if err == "":
					_drop_binding(w, "forschung")
					Society.log_line(w, "Auf Befehl des Herrschers wird %s erforscht." % Data.techs[value].name)
				else:
					msg = err
		"beruf":
			pass
	Society.log_line(w, "Feste Vorgabe des Herrschers: %s." % _binding_text(b))
	m.next_council = minf(float(m.next_council), Game.time_days + 0.05)
	if kind in ["fokus", "beruf"]:
		var sit: Dictionary = Society.situation(w)
		if m.shares.is_empty():
			for j in _job_options(w, sit):
				m.shares[j] = 1.0
		_make_orders(w, sit)
	changed.emit()
	Society.changed.emit()
	return msg


func unbind(w, i: int) -> void:
	var m := mem(w)
	if i >= 0 and i < m.binding.size():
		Society.log_line(w, "Vorgabe aufgehoben: %s." % _binding_text(m.binding[i]))
		m.binding.remove_at(i)
		changed.emit()
		Society.changed.emit()


func set_prio(w, key: String, v: int) -> void:
	var m := mem(w)
	m.prios[key] = clampi(v, 0, 3)
	Society.decide(w, "Herrscher: Priorität %s jetzt %s." % [cfg("priorities", {}).get(key, key), PRIO_WORDS[clampi(v, 0, 3)]])
	if not m.shares.is_empty():
		_make_orders(w, Society.situation(w))
	changed.emit()


func _binding_value(w, kind: String) -> String:
	for b in mem(w).binding:
		if b.kind == kind:
			return str(b.value)
	return ""


func _drop_binding(w, kind: String) -> void:
	var m := mem(w)
	m.binding = m.binding.filter(func(b): return b.kind != kind)


func _prune_binding(w) -> void:
	var m := mem(w)
	m.binding = m.binding.filter(func(b): return float(b.until) > Game.time_days or b.kind in ["bau", "forschung"])


# ================================================================== Debug-Bericht
## Vorübergehend zur Kontrolle: Jede Anfrage an ein Modell wird mit Möglichkeiten,
## Wahrscheinlichkeiten und Entscheidung festgehalten. Die vollen Anfragetexte bleiben nur
## für die letzten Einträge, damit der Speicher klein bleibt.
const TRACE_MAX := 3000
const TRACE_FULL := 150


func trace(e: Dictionary) -> void:
	trace_count += 1
	e["n"] = trace_count
	e["day"] = Game.time_days
	e["clock"] = Time.get_time_string_from_system()
	traces.append(e)
	if traces.size() > TRACE_MAX:
		traces = traces.slice(traces.size() - TRACE_MAX)
	var old := traces.size() - TRACE_FULL - 1
	if old >= 0:
		for k in ["prompt", "prompt2"]:
			if traces[old].has(k):
				traces[old][k] = "(gekürzt) " + str(traces[old][k]).right(600)


func _pct(v) -> String:
	return "%d %%" % int(round(float(v) * 100.0))


func _plist(opts: Array, probs: Array) -> String:
	var parts := []
	for i in opts.size():
		var name := str(opts[i]).split(":")[0]
		parts.append("%d) %s %s" % [i + 1, name, _pct(probs[i]) if i < probs.size() else "?"])
	return ", ".join(parts)


## Der ganze Bericht als Text.
func report_text() -> String:
	var L := []
	L.append("KI-BERICHT New World (KI-Version)")
	L.append("Erstellt: %s, Spieltag %d (%s), Jahr %d" % [Time.get_datetime_string_from_system(false, true), Game.day(), Seasons.season_name(), Seasons.year() + 1])
	L.append(Llm.status_text())
	L.append("Geladen: %s" % JSON.stringify(Llm.loaded))
	L.append("Gerät: %s, Prüfung: %s, übersprungen: %s" % [Llm.device, JSON.stringify(Llm.probe), JSON.stringify(Llm.skipped)])
	L.append("Anfragen: Rat %d (Schnitt %.1f s), Siedler %d (Schnitt %.2f s)" % [int(Llm.stats.rat[0]), Llm.avg_ms("rat") / 1000.0, int(Llm.stats.siedler[0]), Llm.avg_ms("siedler") / 1000.0])
	L.append("Festgehalten: %d Einträge seit dem Start (die letzten %d hier, volle Anfragetexte nur bei den letzten %d)." % [trace_count, traces.size(), TRACE_FULL])
	L.append("")
	L.append("Lesehilfe: Klarheit 1,0 heißt, alle Möglichkeiten waren dem Modell gleich lieb (Würfeln). Klarheit = höchste Wahrscheinlichkeit mal Anzahl der Möglichkeiten; unter %.2f gilt das Modell als unentschlossen. Nummernanteil = wie sehr das Modell überhaupt mit einer Nummer antworten wollte. Siedler werden zweimal gefragt (A: normale Reihenfolge, B: umgekehrt), gezählt wird der Mittelwert." % float(cfg("undecided_clarity", 1.35)))
	L.append("")
	# Zusammenfassung
	for role in ["siedler", "rat"]:
		var ch := traces.filter(func(e): return e.role == role and e.has("probs"))
		if ch.is_empty():
			continue
		var und := 0
		var clar := 0.0
		var mass := 0.0
		var first_a := 0
		var first_b := 0
		var own := 0
		var agree := 0
		for e in ch:
			if str(e.rule) != "Modell":
				und += 1
			clar += float(e.clarity)
			var ms = e.get("mass", 0.0)
			mass += float(ms[0]) if ms is Array else float(ms)
			if e.get("own", false):
				own += 1
			if e.has("probs_a") and not e.probs_a.is_empty():
				if _argmax(e.probs_a) == 0:
					first_a += 1
				if not e.probs_b.is_empty():
					if _argmax(e.probs_b) == 0:
						first_b += 1
					if _argmax(e.probs_a) == e.probs_a.size() - 1 - _argmax(e.probs_b):
						agree += 1
		var n := float(ch.size())
		L.append("== Zusammenfassung %s: %d Auswahlentscheidungen ==" % ["Siedler (SmolLM)" if role == "siedler" else "Rat", ch.size()])
		L.append("Unentschlossen: %d (%s), mittlere Klarheit %.2f, mittlerer Nummernanteil %s" % [und, _pct(und / n), clar / n, _pct(mass / n)])
		if role == "siedler":
			L.append("Nummer 1 am liebsten: in A %s, in B %s (stark über 1/Anzahl heißt: das Modell nimmt einfach die erste Nummer)" % [_pct(first_a / n), _pct(first_b / n)])
			L.append("A und B einig über die beste Arbeit: %s. Gegen den Auftrag entschieden: %d" % [_pct(agree / n), own])
		L.append("")
	# Gedächtnis der Räte
	for i in Sea.settled_islands():
		var w = Sea.worlds.get(i)
		if w == null or not is_instance_valid(w):
			continue
		var m := mem(w)
		L.append("== Insel %s ==" % Sea.island_name(w))
		L.append("Schwerpunkt: %s, Plan: %s" % [Society.strat_name(m.focus), m.plan])
		L.append("Anteile Arbeit: %s" % JSON.stringify(m.shares))
		L.append("Vorgaben: %s, Prioritäten: %s" % [JSON.stringify(m.binding), JSON.stringify(m.prios)])
		for l in m.lessons:
			L.append("Lehre (Tag %d, %s): %s" % [int(float(l[0])) + 1, l[2], l[1]])
		for e in experience_lines(w, 20):
			L.append("Erfahrung: %s" % e)
		for r in m.records:
			L.append("Entscheidung: %s" % record_text(r))
		for c in m.chat:
			L.append("Gespräch %s: %s" % [c[0], c[1]])
		L.append("")
	# Verlauf
	L.append("== Verlauf aller Anfragen (älteste zuerst) ==")
	for e in traces:
		L.append("")
		L.append("#%d  Tag %d %02d:%02d (Uhr %s)  %s, %s: %s" % [int(e.n), int(floor(float(e.day))) + 1, int(fmod(float(e.day), 1.0) * 24.0),
			int(fmod(float(e.day) * 24.0, 1.0) * 60.0), e.clock, e.isl, e.who, e.topic])
		if e.has("probs"):
			if e.has("order"):
				L.append("Auftrag des Rats: %s" % (e.order if str(e.order) != "" else "keiner"))
			L.append("Möglichkeiten und Wahrscheinlichkeit: %s" % _plist(e.options, e.probs))
			if e.has("probs_a"):
				L.append("  A (normale Reihenfolge): %s" % _plist(e.options, e.probs_a))
				var rb := []
				for k in e.probs_b.size():
					rb.append(e.probs_b[e.probs_b.size() - 1 - k])
				L.append("  B (umgekehrt gefragt, zurückgeordnet): %s" % (_plist(e.options, rb) if not rb.is_empty() else "keine Antwort"))
			L.append("Klarheit %.2f, Nummernanteil %s, liebstes Wort: %s, Rechenzeit %d ms" % [float(e.clarity), JSON.stringify(e.mass), JSON.stringify(e.top), int(float(e.ms))])
			L.append("Entscheidung: %s (%s)%s" % [str(e.choice).split(":")[0], e.rule, ", gegen den Auftrag" if e.get("own", false) else ""])
		if e.has("text"):
			L.append("Antwort: %s  (%d ms)" % [e.text, int(float(e.get("ms", 0.0)))])
		if e.has("prompt"):
			L.append("--- Anfrage ---")
			L.append(str(e.prompt))
			if e.has("prompt2"):
				L.append("--- Anfrage B (Frageteil) ---")
				L.append(str(e.prompt2))
			L.append("--- Ende ---")
	return "\n".join(L)


## Bericht als Datei: im Browser herunterladen, sonst in user:// ablegen. Gibt den Dateinamen zurück.
func download_report() -> String:
	var name := "ki-bericht-tag%d-%s.txt" % [Game.day(), Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")]
	var txt := report_text()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(txt.to_utf8_buffer(), name, "text/plain;charset=utf-8")
		return name
	var f := FileAccess.open("user://" + name, FileAccess.WRITE)
	if f:
		f.store_string(txt)
		f.close()
	return ProjectSettings.globalize_path("user://" + name)
