extends Node
## KI-Variante: der Inselrat, nach Regeln (seit 2026-10-06 ohne Sprachmodelle, josh).
##
## Jede Insel hat einen Rat, der alle `council_days` tagt (Hauptinsel zuerst):
## 1. Schwerpunkt: die Strategie mit der besten Lagebewertung (Society.situation_scores),
##    außer der Herrscher hat einen festen Schwerpunkt vorgegeben.
## 2. Arbeit: Wie viele Siedler je Beruf bis zur nächsten Sitzung wirklich etwas zu tun haben
##    (`job_capacity`), gewichtet nach Bedarf (Society.desired_jobs) und den Prioritäten des
##    Herrschers. Daraus bekommt jeder Siedler einen Auftrag (`_make_orders`), den er befolgt;
##    wer keinen Platz bekommt, wird Helfer.
## 3. Bauen: Notregel Lager (ab `storage_rule` voll sofort), sonst der dringendste bezahlbare
##    Vorschlag aus `build_options`.
## 4. Forschung (nur Hauptinsel) und 5. Handel mit anderen Inseln per Schiff.
## Lernen: Jede Sitzung wird mit den Zahlen der Insel gespeichert und bei der nächsten
## gemessen (Erfahrung je Jahreszeit und Schwerpunkt). Dazu kommt die Arbeitsstatistik der
## Siedler (eigene Arbeit, anderes, untätig, geliefert): Leerlauf senkt die Plätze eines
## Berufs (`fit`). Auffällige Messungen werden Lehren, die das ganze Spiel über im Archiv
## bleiben und zu höchstens `knowledge_max` Regeln zusammengefasst werden.
## Der Herrscher kann feste Vorgaben machen (`bind`) und Prioritäten verschieben (`set_prio`).

signal changed

const JOB_ORDER := ["sammler", "fischer", "bauer", "koch", "holzfaeller", "steinmetz", "baumeister", "handwerker", "forscher", "jaeger"]
const PRIO_FACTOR := [0.4, 1.0, 1.5, 2.2]
const PRIO_WORDS := ["unwichtig", "normal", "wichtig", "sehr wichtig"]
const TRADE_GOODS := ["holz", "stein", "bretter", "lehm", "ziegel", "werkzeug", "eisen", "erz", "kohle", "felle", "gold", "glas", "papier"]

var trades: Array = []  # laufende Handelsrouten zwischen Inseln
var next_trade := 1
var _next_orders: Dictionary = {}  # Insel-ID -> wann die Siedler ihre Aufträge wieder prüfen (nicht gespeichert)


func _ready() -> void:
	# Aufräumen nach der Zeit mit Sprachmodellen: deren Downloads (etwa 1,2 GB im Browser-Speicher
	# "transformers-cache") und Absturzmerker werden nicht mehr gebraucht.
	if OS.has_feature("web") and Game.is_ki_build:
		JavaScriptBridge.eval("""(async function () {
			try { await caches.delete('transformers-cache'); } catch (e) { }
			try { localStorage.removeItem('kiLlmPending'); localStorage.removeItem('kiLlmTooBig'); } catch (e) { }
			try { indexedDB.deleteDatabase('kiLlm'); } catch (e) { }
		})();""", true)


func cfg(key: String, default = null):
	return Data.ki_rat.get(key, default)


func active() -> bool:
	return Society.enabled


# ================================================================== Zustand
## Gedächtnis und Vorgaben eines Inselrats (liegt im Society-Zustand unter "llm", der Name
## stammt aus der Zeit mit Sprachmodellen und bleibt, damit alte Spielstände laden).
func mem(w) -> Dictionary:
	var st: Dictionary = Society.state(w)
	if not st.has("llm"):
		st["llm"] = {}
	var m: Dictionary = st.llm
	var defaults := {"next_council": Game.time_days + float(cfg("first_council_day", 0.15)), "focus": st.get("strategy", "nahrung"),
		"plan": "", "shares": {}, "orders": {}, "last": {}, "binding": [], "prios": {},
		"records": [], "lessons": [], "exp": {}, "councils": 0,
		"archive": [], "knowledge": [], "lesson_new": 0, "stats": [], "stat_total": {}, "fit": {}, "stat_from": Game.time_days}
	for k in defaults:
		if not m.has(k):
			m[k] = defaults[k]
	if not m.has("archive_v1"):
		# Seit 2026-10-05 bleiben alle Lehren das ganze Spiel über im Archiv
		m["archive_v1"] = true
		if m.archive.is_empty():
			for l in m.lessons:
				m.archive.append([l[0], l[1], l[2], l[3] if l.size() > 3 else "", -1])
			m.lesson_new = m.lessons.size()
	if not m.has("rule_v1"):
		# Seit 2026-10-06 ohne Sprachmodelle: Gespräch und Wünsche an das Modell fallen weg
		m["rule_v1"] = true
		for k in ["chat", "wishes", "waiting", "clean_v2", "en_v1"]:
			m.erase(k)
		# Vom Sprachmodell geschriebene Regeln und Lehren fallen weg (bleiben im Archiv)
		m.knowledge = []
		m.lessons = m.lessons.filter(func(l): return str(l[2]) != "Rat")
	return m


func reset() -> void:
	trades = []
	next_trade = 1
	_next_orders = {}


func serialize() -> Dictionary:
	return {"trades": trades, "next_trade": next_trade}


func load_from(d: Dictionary) -> void:
	reset()
	trades = d.get("trades", [])
	next_trade = int(d.get("next_trade", 1))


func prio(w, key: String) -> int:
	return int(mem(w).prios.get(key, 1))


# ================================================================== Takt
func _process(_delta: float) -> void:
	if not Society.enabled or Game.world == null or Game.is_over or Game.speed <= 0:
		return
	_expire_trades()
	var worlds: Array = Sea.all_worlds().duplicate()
	worlds.sort_custom(func(a, b): return int(a.island_id) < int(b.island_id))
	for w in worlds:
		if not is_instance_valid(w) or w.settlers.is_empty():
			continue
		var m := mem(w)
		if Game.time_days >= float(m.next_council) and not Game.is_night():
			m.next_council = Game.time_days + float(cfg("council_days", 1.0))
			_council(w)
		var id := int(w.island_id)
		if Game.time_days >= float(_next_orders.get(id, 0.0)):
			_next_orders[id] = Game.time_days + float(cfg("settler_days", 0.25))
			for s in w.settlers:
				if is_instance_valid(s) and s.world == w:
					_follow_order(s, w)


# ================================================================== Texte
func _jname(j: String) -> String:
	return Data.jobs.get(j, {}).get("name", j)


func _binding_text(b: Dictionary) -> String:
	match str(b.kind):
		"fokus":
			return tr("Schwerpunkt %s") % Society.strat_name(b.value)
		"bau":
			return tr("%s bauen") % Data.buildings.get(b.value, {}).get("name", b.value)
		"forschung":
			return tr("%s erforschen") % Data.techs.get(b.value, {}).get("name", b.value)
		"beruf":
			return tr("mindestens %d %s") % [int(b.get("n", 1)), _jname(b.value)]
	return str(b.value)


## Plätze je Beruf als Text, die meisten zuerst ("3 Sammler, 2 Holzfäller").
func slots_text(slots: Dictionary) -> String:
	var keys: Array = slots.keys().filter(func(j): return int(slots[j]) > 0)
	keys.sort_custom(func(a, b): return int(slots[a]) > int(slots[b]))
	return ", ".join(keys.map(func(j): return "%d %s" % [int(slots[j]), _jname(j)])) if not keys.is_empty() else tr("keine Aufträge")


# ================================================================== Rat
func _council(w) -> void:
	var m := mem(w)
	var sit: Dictionary = Society.situation(w)
	var sit0 := sit  # Lage zu Beginn der Sitzung (für die Messung danach)
	Society._make_households(w, sit)
	_collect_stats(w)
	_evaluate(w, sit)
	_prune_binding(w)
	var last := {"day": Game.time_days}

	# 1. Schwerpunkt: die Strategie, für die die Lage am meisten spricht
	var forced := _binding_value(w, "fokus")
	var keys: Array = Society.strategies().keys().filter(func(k): return Society.strategy_allowed(k))
	var sc: Dictionary = Society.situation_scores(w, sit)
	keys.sort_custom(func(a, b): return float(sc.get(a, 0.0)) > float(sc.get(b, 0.0)))
	if forced != "":
		m.focus = forced
		last.focus = {"choice": Society.strat_name(forced), "id": forced, "why": tr("Vorgabe des Herrschers")}
	elif not keys.is_empty():
		if keys[0] != m.focus:
			Society.log_line(w, tr("Der Rat wählt den Schwerpunkt „%s“ (vorher „%s“).") % [Society.strat_name(keys[0]), Society.strat_name(m.focus)])
		m.focus = keys[0]
		last.focus = {"choice": Society.strat_name(keys[0]), "id": keys[0]}
	Society.state(w).strategy = m.focus

	# 2. Arbeit: nach Bedarf und Schwerpunkt gewichtet, aber je Beruf nur so viele, wie bis zur
	# nächsten Sitzung Arbeit da ist. Daraus bekommt jeder Siedler einen Auftrag.
	m["cap"] = job_capacity(w)
	m["cap_day"] = Game.time_days
	var want: Dictionary = Society.desired_jobs(w, sit)
	var sw: Dictionary = Society.strategies().get(m.focus, {}).get("jobs", {})
	var shares := {}
	for j in _job_options(w, sit):
		shares[j] = (0.1 + float(want.get(j, 0.0))) * float(sw.get(j, 1.0))
	m.shares = shares
	_make_orders(w, sit)
	last.jobs = {"slots": slots_text(m.get("slots", {}))}
	Society.decide(w, tr("Rat: Arbeit verteilt: %s.") % last.jobs.slots)

	# 3. Bauen
	sit = Society.situation(w)
	var bforced := _binding_value(w, "bau")
	if bforced != "":
		_build(w, {"type": bforced, "why": tr("Vorgabe des Herrschers.")}, tr("auf Befehl des Herrschers"))
		_drop_binding(w, "bau")
		last.build = {"choice": Data.buildings[bforced].name, "id": bforced, "why": tr("Vorgabe des Herrschers")}
	elif w.fire_building() != null and _storage_rule(w, sit):
		var sid := str(m.get("store_built", "lager"))
		last.build = {"choice": Data.buildings[sid].name, "id": sid, "why": tr("Lager fast voll")}
	elif w.fire_building() != null and w.construction_sites().size() < 2:
		var cands := build_options(w, sit)
		if not cands.is_empty():
			var c: Dictionary = cands[0]
			last.build = {"choice": _build_name(w, c), "id": c.type, "why": str(c.get("why", ""))}
			_build(w, c, tr("der Rat hat es beschlossen"))
			Society.decide(w, tr("Rat: Bauen %s. %s") % [last.build.choice, last.build.why])

	# 4. Forschung (nur Hauptinsel)
	if int(w.island_id) == 0 and Game.research.current == "":
		var tforced := _binding_value(w, "forschung")
		if tforced != "" and Game.tech_state(tforced) == "available":
			_research(w, tforced, tr("auf Befehl des Herrschers"))
			_drop_binding(w, "forschung")
			last.research = {"choice": Data.techs[tforced].name, "id": tforced, "why": tr("Vorgabe des Herrschers")}
		else:
			var techs := research_options(w)
			if not techs.is_empty():
				last.research = {"choice": Data.techs[techs[0]].name, "id": techs[0]}
				_research(w, techs[0], tr("der Rat hat es beschlossen"))

	# 5. Handel mit anderen Inseln
	var trade := _trade(w, Society.situation(w))
	if trade != "":
		last.trade = trade

	# 6. Ansage an die Bewohner
	m.plan = _decision_summary(last)
	Society.log_line(w, tr("Der Rat sagt: %s") % m.plan)
	Game.notify_at(w, tr("Der Inselrat von %s: %s") % [Sea.island_name(w), m.plan], "glocke", "rat")
	last.plan = m.plan
	m.last = last
	m.councils = int(m.councils) + 1
	_remember(w, sit0, last)
	Society._council_requests(w, Society.situation(w))
	if int(m.lesson_new) >= int(cfg("summarize_every", 4)):
		_summarize(w)
	Society.changed.emit()
	changed.emit()


func _decision_summary(last: Dictionary) -> String:
	var parts := []
	if last.has("focus"):
		parts.append(tr("Schwerpunkt %s") % last.focus.choice)
	if last.has("jobs"):
		parts.append(tr("Arbeit: %s") % last.jobs.slots)
	if last.has("build"):
		parts.append(tr("Bauen: %s") % last.build.choice)
	if last.has("research"):
		parts.append(tr("Forschen: %s") % last.research.choice)
	if last.has("trade"):
		parts.append(tr("Handel: %s") % last.trade)
	return ". ".join(parts) + "."


# ------------------------------------------------------------------ Arbeit
## Berufe, die auf der Insel gerade überhaupt etwas zu tun haben.
func _job_options(w, sit: Dictionary) -> Array:
	var cap: Dictionary = mem(w).get("cap", {})
	var out := []
	for j in JOB_ORDER:
		if not Data.job_unlocked(j) and not cap.has(j):
			continue
		if int(cap.get(j, {}).get("n", 0)) <= 0:
			continue
		out.append(j)
	return out


## Wie viele Siedler haben in jedem Beruf bis zur nächsten Ratssitzung wirklich etwas zu tun?
## Gezählt wird die Arbeit, die es in dieser Zeit gibt (reife und säbare Felder, Früchte und
## Fische samt Nachwuchs, Platz im Lager, Bauarbeit, Werkstätten mit Rohstoffen), geteilt durch
## das, was ein Siedler in der Zeit schafft. Die gemessene Auslastung (Statistik) korrigiert das.
## Ergebnis: Beruf -> {"n": Plätze, "why": Begründung für die Anzeige, "secs": Arbeit in Sekunden}
func job_capacity(w) -> Dictionary:
	var m := mem(w)
	var h := clampf(float(m.next_council) - Game.time_days, 0.3, 2.0)
	var day_secs := float(Data.bal("day_length")) * maxf(0.3, Seasons.night_start() - Seasons.night_end())
	var pace := float(Data.bal("work_pace", 1.0)) * Seasons.work_mult(w) * Society.work_mult(w)
	# Sekunden echter Arbeit, die ein Siedler bis zur nächsten Sitzung leistet (Wege, Essen, Pausen abgezogen)
	var secs := maxf(10.0, day_secs * h * float(cfg("work_share", 0.5)))
	var out := {}
	var need := func(j: String, work_s: float, why: String):
		var n := 0 if work_s <= 0.0 else int(ceil(work_s / secs - 0.15))
		if work_s > 0.0:
			n = maxi(1, n)
		out[j] = {"n": n, "why": why, "secs": work_s}
	# Felder: nur säen und ernten ist Arbeit
	var tasks := 0
	var tsecs := 0.0
	var fields := 0
	for b in w.buildings:
		if not b.complete or not b.def.has("farm"):
			continue
		fields += 1
		var fd: Dictionary = b.farm_def()
		var room := Game.space_for(str(fd.yield), w) > 0
		var sow_s := float(fd.sow_time) / pace + 6.0
		var harv_s := float(fd.harvest_time) * 2.0 / pace + 6.0
		if b.farm_state == "fallow":
			if Seasons.can_sow(b.type):
				tasks += 1
				tsecs += sow_s
				if b.grow_days() < h * 0.8 and room:
					tasks += 1
					tsecs += harv_s
		elif b.farm_state == "ripe" or float(b.farm_time) + b.grow_days() <= Game.time_days + h:
			if room:
				tasks += 1
				tsecs += harv_s
	if Data.job_unlocked("bauer") or fields > 0:
		need.call("bauer", tsecs, tr("%d von %d Feldern brauchen Saat oder Ernte") % [tasks, fields])
	# Sammeln, Fischen, Holz, Stein: was nachwächst und ins Lager passt
	var gather := {"sammler": ["busch", "palme", "pilzkreis"], "fischer": ["fischgrund"], "holzfaeller": ["baum"],
		"steinmetz": ["fels", "erzader", "goldader"]}
	var bare: Array = Seasons.cfg.get("winter_bare", [])
	for j in gather:
		var units := {}
		var wsecs := {}
		for n in w.nodes:
			if not n.type in gather[j] or (Seasons.is_winter() and n.type in bare):
				continue
			var res: String = str(n.def.get("yield", ""))
			var u := 0
			if n.amount > 0:
				u = n.amount
			elif n.regrow_at >= 0.0 and float(n.regrow_at) <= Game.time_days + h:
				u = int(n.def.capacity)
			if u <= 0:
				continue
			units[res] = int(units.get(res, 0)) + u
			wsecs[res] = float(n.def.work_time) / pace + 1.0
		var total := 0.0
		var got := 0
		var full := []
		for res in units:
			var room := Game.space_for(res, w)
			if room < int(units[res]):
				full.append(res)
			var u2 := mini(int(units[res]), room)
			got += u2
			total += u2 * float(wsecs[res])
		var why := tr("%d Einheiten zu holen") % got
		if not full.is_empty():
			why += tr(", Lager fast voll für %s") % ", ".join(full.map(func(r): return Data.resource_name(r)))
		if j in ["holzfaeller", "steinmetz"] or not units.is_empty() or Data.job_unlocked(j):
			need.call(j, total, why)
	# Werkstätten: nur, solange Rohstoffe da sind und Platz für das Erzeugnis
	var wjob := {"kueche": "koch", "handwerk": "handwerker", "stein": "steinmetz"}
	for b in w.buildings:
		var p: Dictionary = b.prod_def() if b.complete else {}
		var j: String = wjob.get(str(p.get("job", "")), "")
		if j == "" or b.prod_blocker() != "":
			continue
		var cycles := 99
		for res in p.get("inputs", {}):
			cycles = mini(cycles, int(Game.amount(res, w) / maxi(1, int(p.inputs[res]))))
		var t := float(p.get("time", 10.0)) / pace + 3.0
		var per := maxf(1.0, floor(secs / t))
		var wn := mini(b.slots(), int(ceil(float(cycles) / per)))
		if wn <= 0:
			continue
		var e: Dictionary = out.get(j, {"n": 0, "why": "", "secs": 0.0})
		e.n = int(e.n) + wn
		e.secs = float(e.secs) + wn * secs
		e.why = (str(e.why) + "; " if str(e.why) != "" else "") + tr("%s braucht %d") % [b.def.name, wn]
		out[j] = e
	# Bauen: Restarbeit und noch fehlendes Material aller Baustellen
	var bsecs := 0.0
	var sites: Array = w.construction_sites()
	for b in sites:
		bsecs += maxf(0.0, float(b.def.work) - float(b.progress)) * 1.5 / maxf(0.1, pace * Seasons.build_mult())
		for res in b.def.cost:
			bsecs += maxf(0.0, int(b.def.cost[res]) - int(b.delivered.get(res, 0))) * 2.0
	if not sites.is_empty():
		need.call("baumeister", bsecs, tr("%d Baustellen") % sites.size())
		out.baumeister.n = mini(int(out.baumeister.n), sites.size() * 3)
	# Forschen: so viele, wie Plätze da sind (auch wenn der Rat gleich erst ein Ziel wählt)
	var places := 0
	for b in w.buildings:
		if b.complete and b.def.has("research"):
			places += b.slots()
	if places > 0 and (Game.research.current != "" or (int(w.island_id) == 0 and not research_options(w).is_empty())):
		out["forscher"] = {"n": places, "why": tr("%d Forschungsplätze") % places, "secs": places * secs}
	# Jagen: nur, was gejagt werden darf (die letzten Tiere jeder Art bleiben)
	if Data.job_unlocked("jaeger"):
		var prey := 0
		var keep := int(Data.bal("hunt_min_keep", 2))
		var types := {}
		for a in w.animals:
			if is_instance_valid(a) and not a.dead:
				types[a.type] = true
		for t in types:
			prey += maxi(0, w.adult_count(t) - keep)
		var n := mini(2, prey)
		out["jaeger"] = {"n": n, "why": tr("%d Tiere dürfen gejagt werden") % prey, "secs": n * secs}
	# Gemessene Auslastung: Wer zuletzt viel Leerlauf hatte, bekommt weniger Plätze
	var fit: Dictionary = m.get("fit", {})
	for j in out:
		var f := float(fit.get(j, 1.0))
		if f < 0.95 and int(out[j].n) > 1:
			out[j].n = maxi(1, int(round(float(out[j].n) * f)))
			out[j].why = str(out[j].why) + tr(" (auf %d %% gesenkt nach gemessenem Leerlauf)") % int(f * 100.0)
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
	if not m.has("cap") or Game.time_days - float(m.get("cap_day", -9.0)) > 0.2:
		m["cap"] = job_capacity(w)
		m["cap_day"] = Game.time_days
	var cap: Dictionary = m.cap
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
		# Größte Reste: n Plätze nach Anteil, aber nie mehr, als es bis zur nächsten Sitzung
		# Arbeit gibt (job_capacity). Wer übrig bleibt, wird Helfer (frei).
		var rem := []
		var used := 0
		for j in weights:
			var exact := float(weights[j]) / total * n
			var lim := int(cap.get(j, {}).get("n", 0))
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
			while food_now < need and int(cap.get(j, {}).get("n", 0)) > int(slots.get(j, 0)):
				slots[j] = int(slots.get(j, 0)) + 1
				food_now += 1
		if food_now > 0:
			m["note"] = tr("Notregel: Das Essen reicht kaum, mindestens %d sollen Nahrung holen.") % need
	else:
		m.erase("note")
		# Solange Essen nicht reichlich da ist, holt immer mindestens einer Nahrung
		var food_now := 0
		for j in ["sammler", "fischer", "bauer"]:
			food_now += int(slots.get(j, 0))
		if food_now == 0 and float(sit.food_head) < 20.0:
			for j in ["fischer", "sammler", "bauer"]:
				if int(cap.get(j, {}).get("n", 0)) > 0:
					slots[j] = 1
					break
			var used := 0
			for j in slots:
				used += int(slots[j])
			if used > n:
				var big := ""
				for j in slots:
					if not j in ["sammler", "fischer", "bauer"] and (big == "" or int(slots[j]) > int(slots[big])):
						big = j
				if big != "" and int(slots[big]) > 0:
					slots[big] = int(slots[big]) - 1
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
	return ", ".join(parts) if not parts.is_empty() else tr("nichts")


func _build_name(w, c: Dictionary) -> String:
	if c.has("upgrade"):
		var b = w.building_by_id(int(c.upgrade))
		return tr("%s zu %s ausbauen") % [b.def.name if b else "?", Data.buildings[c.type].name]
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
	# Lager zuerst, wenn es eng wird: Ist es voll, hören Sammler, Holzfäller und Steinmetze auf
	var store := storage_option(w, sit)
	if not store.is_empty() and float(sit.storage_full) >= float(cfg("storage_urgent", 0.8)):
		add.call(store)
	var first: Dictionary = Society._choose_building(w, sit)
	if not first.is_empty():
		add.call(first)
	if int(sit.season) in [Seasons.SPRING, Seasons.SUMMER]:
		add.call({"type": "feld", "why": tr("Mehr Felder bringen mehr Essen (Ernte im Sommer und Herbst).")})
		if Game.is_unlocked("obstgarten"):
			add.call({"type": "obstgarten", "why": tr("Obst bringt Vitamine.")})
	for t in Society.HOUSE_ORDER:
		if Game.is_unlocked(t) and Data.buildings[t].get("buildable", true):
			add.call({"type": t, "why": tr("Mehr Wohnplatz (%d Siedler, %d Plätze).") % [int(sit.pop), int(sit.housing)]})
			break
	for b in w.buildings:
		var to: String = b.def.get("upgrade", "")
		if b.complete and b.housing() > 0 and to != "" and Game.is_unlocked(to):
			add.call({"type": to, "upgrade": b.id, "why": tr("Mehr Platz für Familien.")})
			break
	for t in Society.PROD_ORDER:
		if Game.is_unlocked(t) and Society._count(w, [t]) == 0:
			add.call({"type": t, "why": tr("%s fehlt noch auf der Insel.") % Data.buildings[t].name})
	for t in ["schreibstube", "bibliothek", "universitaet", "labor", "schule"]:
		if Game.is_unlocked(t) and Society._count(w, [t]) == 0:
			add.call({"type": t, "why": tr("Ein Ort zum Forschen und Lernen.")})
	if not store.is_empty():
		add.call(store)
	if Game.is_unlocked("wachturm") and int(sit.predators) > 0:
		add.call({"type": "wachturm", "why": tr("%d Raubtiere auf der Insel.") % int(sit.predators)})
	for t in ["werft", "anlegesteg", "hafen"]:
		if Game.is_unlocked(t) and Society._count(w, [t]) == 0:
			add.call({"type": t, "why": tr("Für Schiffe und Handel.")})
			break
	return out


## Notregel: Ist das Lager fast voll und kein neues im Bau, baut der Rat sofort eins, wenn das
## Material reicht (sonst steht ein Lager ganz oben unter den Bauvorschlägen).
func _storage_rule(w, sit: Dictionary) -> bool:
	if float(sit.storage_full) < float(cfg("storage_rule", 0.9)):
		return false
	var c := storage_option(w, sit)
	if c.is_empty() or not Game.can_afford(Data.buildings[c.type].get("cost", {}), w):
		return false
	var n: int = w.construction_sites().size()
	_build(w, c, tr("Notregel: Lager fast voll"))
	if w.construction_sites().size() <= n:
		return false
	mem(w)["store_built"] = c.type
	Society.decide(w, tr("Rat: Notregel, das Lager ist zu %d %% voll, also wird %s gebaut.") % [int(float(sit.storage_full) * 100.0), Data.buildings[c.type].name])
	return true


## Ein weiteres Lager, wenn das vorhandene zu mehr als storage_watch voll ist (das größte erforschte).
func storage_option(w, sit: Dictionary) -> Dictionary:
	var full := float(sit.storage_full)
	if full < float(cfg("storage_watch", 0.65)):
		return {}
	for b in w.construction_sites():
		if int(b.def.get("storage", 0)) > 0:
			return {}  # wird schon gebaut
	for t in ["grosslager", "lager"]:
		if Game.is_unlocked(t) and Data.buildings[t].get("buildable", true):
			var add := int(Data.buildings[t].storage)
			return {"type": t, "storage": true,
				"why": tr("Das Lager ist zu %d %% voll (%d von %d). %s bringt %d Platz.") % [int(full * 100.0), Game.used_volume(w), Game.storage_volume(w), Data.buildings[t].name, add]}
	return {}


func _build(w, c: Dictionary, how: String) -> void:
	var def: Dictionary = Data.buildings[c.type]
	if c.has("upgrade"):
		var b = w.building_by_id(int(c.upgrade))
		if b and b.complete and w.upgrade_building(b) != null:
			Society.log_line(w, tr("Der Rat lässt %s ausbauen (%s).") % [b.def.name, how])
			Game.notify_at(w, tr("Der Rat lässt %s ausbauen (%s).") % [b.def.name, how], "hammer", "rat_bau")
		return
	var spot: Vector2i = Society.find_spot(w, c.type)
	if spot.x < 0:
		Society.decide(w, tr("Kein Platz für %s.") % def.name)
		return
	w.place_building(c.type, spot, false)
	Society.log_line(w, tr("Der Rat lässt bauen: %s bei (%d,%d) (%s).") % [def.name, spot.x, spot.y, how])
	Game.notify_at(w, tr("Der Rat lässt bauen: %s. %s") % [def.name, c.get("why", "")], "hammer", "rat_bau")


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
		Society.decide(w, tr("Forschung %s geht nicht: %s") % [Data.techs[t].name, err])
		return
	Society.log_line(w, tr("Die Forscher beginnen mit %s (%s).") % [Data.techs[t].name, how])
	Game.notify_at(w, tr("Der Rat lässt erforschen: %s.") % Data.techs[t].name, "wissen", "rat_bau")


# ================================================================== Handel
## Fehlt der Insel etwas, das eine andere übrig hat, bittet der Rat dort darum (die dringendste
## Ware zuerst). Die andere Insel verlangt dafür eine Ware, die ihr selbst fehlt, oder hilft
## umsonst. Ein Schiff einer der beiden Inseln fährt dann eine Route hin und her, bis die
## Abmachung ausläuft.
func _trade(w, sit: Dictionary) -> String:
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
	var off: Array = offers[0]
	var o = off[2]
	var good: String = off[0]
	var amount := int(off[1])
	Society.decide(w, tr("Handel: Der Rat bittet %s um %d %s.") % [Sea.island_name(o), amount, Data.resource_name(good)])
	# Die andere Insel nennt ihren Preis: was ihr selbst fehlt und wir übrig haben
	var pay := _trade_spare(w)
	pay.erase(good)
	var price := {}
	for id in _trade_needs(o, Society.situation(o)):
		if pay.has(id):
			price[id] = mini(int(pay[id]), maxi(4, amount))
			break
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
		Society.log_line(w, tr("Handel mit %s vereinbart, aber kein freies Schiff.") % Sea.island_name(o))
		return tr("vereinbart, aber kein freies Schiff")
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
	var text := tr("%s bringt %s%s mit der %s (Heimat %s)") % [Sea.island_name(o), Sea.goods_text(g),
		(tr(" gegen ") + Sea.goods_text(p)) if not p.is_empty() else tr(" als Hilfe"), ship.name, Sea.meta(int(ship.home)).get("name", "?")]
	Society.log_line(w, tr("Handelsroute beschlossen: %s.") % text)
	Society.log_line(o, tr("Handelsroute beschlossen: %s.") % text)
	Game.notify(tr("Handel: %s.") % text, "boot", "handel")
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
			Society.log_line(w, tr("Die Handelsroute mit %s ist ausgelaufen.") % Sea.meta(int(t.from)).get("name", "?"))


# ================================================================== Siedler


## Jeder erwachsene Siedler macht, was der Rat ihm aufträgt; ohne Auftrag bleibt er bei seiner
## Arbeit. Ausnahmen: ein Befehl des Herrschers und Krankheit.
func _follow_order(s, w) -> void:
	if not s.is_adult():
		Society.thoughts[s.id] = tr("Spielt und lernt.") if w.school_of(s) == null else tr("Lernt in der Schule.")
		return
	if s.job == "seemann":
		Society.thoughts[s.id] = tr("Ich gehöre zur Besatzung unserer Schiffe.")
		return
	if float(Society.orders.get(s.id, 0.0)) > Game.time_days:
		Society.thoughts[s.id] = tr("Der Herrscher hat mich zum %s bestimmt. Das mache ich.") % s.job_name()
		return
	if s.mind.needs_bed():
		Society.thoughts[s.id] = tr("Ich bin krank und muss liegen.")
		return
	var order := council_order(s)
	var choice: String = order if order != "" else s.job
	var old: String = s.job
	if choice != old:
		s.set_job(choice)
		Society.last_change[s.id] = Game.time_days
		Society.decide(w, tr("%s wird %s (vorher %s), wie der Rat sagt.") % [s.display_name, _jname(choice), _jname(old)])
		changed.emit()
	Society.thoughts[s.id] = (tr("Ich bin %s. Das ist mein Auftrag vom Rat.") % _jname(choice)) if order != "" else (tr("Ich bin %s. Der Rat hat mir nichts anderes aufgetragen.") % _jname(choice))


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
	var t := tr("Tag %d (%s): Schwerpunkt %s") % [int(float(r.d)) + 1, Seasons.season_name(int(r.s)), Society.strat_name(str(r.focus))]
	if str(r.get("build", "")) not in ["", tr("nichts")]:
		t += tr(", gebaut %s") % r.build
	if str(r.get("research", "")) != "":
		t += tr(", erforscht %s") % r.research
	if str(r.get("trade", "")) != "":
		t += tr(", Handel: %s") % r.trade
	if r.has("out"):
		var o: Dictionary = r.out
		t += tr(" -> danach je Tag: Essen %+.1f, Holz %+.1f, Stein %+.1f, Siedler %+.1f, Laune %+.1f") % [float(o.food), float(o.wood), float(o.stone), float(o.pop), float(o.mood)]
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
		out.append(tr("- %s, Schwerpunkt %s: Essen %+.1f, Holz %+.1f, Stein %+.1f, Siedler %+.1f, Laune %+.1f (%d mal)") % [
			Seasons.season_name(int(p[0])), Society.strat_name(p[1]), float(e[1]) / c, float(e[2]) / c, float(e[3]) / c,
			float(e[4]) / c, float(e[5]) / c, int(c)])
	return out


## Aus einer auffälligen Messung eine Lehre über die Spielmechanik machen.
func _measure_lesson(w, r: Dictionary, o: Dictionary) -> void:
	var food_workers := 0
	for j in ["sammler", "fischer", "bauer", "koch"]:
		food_workers += int(r.jobs.get(j, 0))
	var s := int(r.s)
	var d := {}
	var kind := ""
	if float(o.food) < -2.0 and food_workers > 0:
		kind = "essen"
		d = {"t": kind, "s": s, "v": [-float(o.food), food_workers]}
	elif float(o.food) < -1.0 and food_workers == 0:
		kind = "ohne"
		d = {"t": kind, "s": s, "v": [float(o.food)]}
	elif float(o.wood) < -3.0 and s in [Seasons.AUTUMN, Seasons.WINTER]:
		kind = "holz"
		d = {"t": kind, "s": s, "v": [float(o.wood)]}
	elif float(o.pop) > 0.4:
		kind = "wachsen|" + str(r.focus)
		d = {"t": "wachsen", "s": s, "v": [float(o.pop)], "f": str(r.focus)}
	elif float(o.mood) < -5.0:
		kind = "laune"
		d = {"t": kind, "s": s, "v": [float(o.mood)]}
	if not d.is_empty():
		# Dieselbe Beobachtung in derselben Jahreszeit ersetzt die alte (neueste Zahlen)
		add_lesson(w, d, "Messung", "%s|%d" % [kind, s])


# ------------------------------------------------------------------ Arbeitsstatistik
## Liest die Zeiten der Siedler seit der letzten Sitzung (settler.stat), legt sie je Beruf ab,
## misst die Auslastung (fit, für job_capacity) und macht aus auffälligem Leerlauf eine Lehre.
func _collect_stats(w) -> void:
	var m := mem(w)
	var d0 := float(m.get("stat_from", Game.time_days))
	m.stat_from = Game.time_days
	var jobs := {}
	var people := []
	var orders: Dictionary = m.orders
	for s in w.settlers:
		if not s.is_adult() or s.stat.is_empty():
			s.stat = {}
			continue
		var st: Dictionary = s.stat
		s.stat = {}
		var e: Dictionary = jobs.get(s.job, {"n": 0, "job": 0.0, "other": 0.0, "idle": 0.0, "needs": 0.0, "acts": 0, "goods": {}, "off": 0})
		e.n = int(e.n) + 1
		for k in ["job", "other", "idle", "needs"]:
			e[k] = float(e[k]) + float(st.get(k, 0.0))
		e.acts = int(e.acts) + int(st.get("acts_job", 0))
		var gsum := 0
		for g in st.get("goods", {}):
			e.goods[g] = int(e.goods.get(g, 0)) + int(st.goods[g])
			gsum += int(st.goods[g])
		var order := str(orders.get(str(s.id), ""))
		if order != "" and order != s.job:
			e.off = int(e.off) + 1
		jobs[s.job] = e
		people.append([s.display_name, s.job, snappedf(float(st.get("job", 0.0)), 0.001), snappedf(float(st.get("other", 0.0)), 0.001),
			snappedf(float(st.get("idle", 0.0)), 0.001), gsum, order])
	if jobs.is_empty() or Game.time_days - d0 < 0.05:
		return
	var caps := {}
	for j in m.get("cap", {}):
		caps[j] = int(m.cap[j].n)
	var per := {"d0": snappedf(d0, 0.01), "d1": snappedf(Game.time_days, 0.01), "s": int(Seasons.season()), "jobs": jobs,
		"people": people, "cap": caps}
	m.stats.append(per)
	var mx := int(cfg("stats_max", 12))
	if m.stats.size() > mx:
		m.stats = m.stats.slice(m.stats.size() - mx)
	# Summe über das ganze Spiel
	for j in jobs:
		var t: Dictionary = m.stat_total.get(j, {"job": 0.0, "other": 0.0, "idle": 0.0, "needs": 0.0, "acts": 0, "goods": {}, "n": 0})
		for k in ["job", "other", "idle", "needs"]:
			t[k] = float(t[k]) + float(jobs[j][k])
		t.acts = int(t.acts) + int(jobs[j].acts)
		t.n = int(t.n) + int(jobs[j].n)
		for g in jobs[j].goods:
			t.goods[g] = int(t.goods.get(g, 0)) + int(jobs[j].goods[g])
		m.stat_total[j] = t
	# Auslastung lernen: eigene Arbeit unter 70 % der Tageszeit heißt, es waren zu viele
	var target := float(cfg("busy_target", 0.7))
	for j in jobs:
		if j in ["frei", "seemann"]:
			continue
		var e: Dictionary = jobs[j]
		var day := float(e.job) + float(e.other) + float(e.idle)
		if day <= 0.0:
			continue
		var share := float(e.job) / day
		var f := float(m.fit.get(j, 1.0))
		if share >= target:
			f = minf(1.0, f + 0.25)
		elif int(e.n) >= 2:
			f = clampf(f * 0.5 + clampf(share / target, 0.3, 1.0) * 0.5, 0.3, 1.0)
		m.fit[j] = snappedf(f, 0.01)
	_stat_lessons(w, per)


## Anteile eines Berufs an der Tageszeit: [eigene Arbeit, anderes, untätig] in Prozent.
func _shares(e: Dictionary) -> Array:
	var day := maxf(0.0001, float(e.job) + float(e.other) + float(e.idle))
	return [int(round(float(e.job) / day * 100.0)), int(round(float(e.other) / day * 100.0)), int(round(float(e.idle) / day * 100.0))]


## Statistik als Text, die Berufe mit den meisten Siedlern zuerst.
func stats_lines(w, idx: int = -1) -> Array:
	var m := mem(w)
	if m.stats.is_empty():
		return []
	var per: Dictionary = m.stats[idx]
	var jobs: Dictionary = per.jobs
	var keys: Array = jobs.keys()
	keys.sort_custom(func(a, b): return int(jobs[a].n) > int(jobs[b].n))
	var out := []
	for j in keys:
		var e: Dictionary = jobs[j]
		var sh := _shares(e)
		var goods: Dictionary = e.goods
		var g := Sea.goods_text(goods) if not goods.is_empty() else tr("nichts")
		out.append(tr("%s ×%d: eigene Arbeit %d %%, anderes %d %%, untätig %d %%; geliefert: %s") % [_jname(j), int(e.n), sh[0], sh[1], sh[2], g])
	return out


func _stat_lessons(w, per: Dictionary) -> void:
	var jobs: Dictionary = per.jobs
	var worst := ""
	var worst_share := 101
	var all_day := 0.0
	var all_idle := 0.0
	for j in jobs:
		var e: Dictionary = jobs[j]
		all_day += float(e.job) + float(e.other) + float(e.idle)
		all_idle += float(e.idle)
		if j in ["frei", "seemann"] or int(e.n) < 2:
			continue
		var sh := _shares(e)
		if sh[0] < 50 and sh[0] < worst_share:
			worst = j
			worst_share = sh[0]
	if worst != "":
		var e2: Dictionary = jobs[worst]
		var cap: Dictionary = mem(w).get("cap", {})
		var why := str(cap[worst].get("why", "")) if cap.has(worst) else ""
		add_lesson(w, {"t": "leer", "s": int(per.s), "v": [int(e2.n)] + _shares(e2), "j": worst, "why": why}, "Messung", "leer|%s|%d" % [worst, int(per.s)])
	elif all_day > 0.0 and all_idle / all_day > 0.3:
		add_lesson(w, {"t": "untaetig", "s": int(per.s), "v": [int(all_idle / all_day * 100.0)]}, "Messung", "untaetig|%d" % int(per.s))


## Fasst alle Lehren zu wenigen Regeln zusammen, die das ganze Spiel über bleiben: je Art von
## Beobachtung die neueste Lehre, die am häufigsten gemachten zuerst.
func _summarize(w) -> void:
	var m := mem(w)
	var latest := {}
	var count := {}
	for l in m.archive:
		if str(l[2]) == "Rat":
			continue  # früher vom Sprachmodell geschrieben, keine Messung
		var k := str(l[3]) if l.size() > 3 and str(l[3]) != "" else str(l[1])
		latest[k] = l
		count[k] = int(count.get(k, 0)) + 1
	var keys: Array = latest.keys()
	keys.sort_custom(func(a, b): return int(count[a]) > int(count[b]))
	m.knowledge = keys.slice(0, int(cfg("knowledge_max", 8))).map(func(k): return latest[k])
	m["knowledge_day"] = snappedf(Game.time_days, 0.01)
	m.lesson_new = 0
	Society.decide(w, tr("Rat: Lehren zusammengefasst (%d Regeln aus %d Lehren).") % [m.knowledge.size(), m.archive.size()])
	changed.emit()





## Eine Lehre aus einer Messung. d: Art ("t"), Jahreszeit ("s"), Zahlen ("v") und mehr; der
## Text entsteht erst beim Anzeigen (lesson_text), damit er in jeder Sprache stimmt.
func add_lesson(w, d: Dictionary, source: String, key: String = "") -> void:
	var m := mem(w)
	var text := _lesson_words(d)
	if text == "":
		return
	for l in m.lessons.duplicate():
		if str(l[1]) == text:
			return
		if key != "" and l.size() > 3 and str(l[3]) == key:
			m.lessons.erase(l)
	m.lessons.append([snappedf(Game.time_days, 0.01), text, source, key, d])
	# Archiv: jede Lehre bleibt das ganze Spiel über (zum Nachlesen und für die Zusammenfassung)
	m.archive.append([snappedf(Game.time_days, 0.01), text, source, key, int(Seasons.season()), d])
	var amx := int(cfg("archive_max", 400))
	if m.archive.size() > amx:
		m.archive = m.archive.slice(m.archive.size() - amx)
	m.lesson_new = int(m.lesson_new) + 1
	var mx := int(cfg("lessons_max", 10))
	while m.lessons.size() > mx:
		# Die älteste Lehre derselben Herkunft fällt weg, sonst die älteste überhaupt
		var drop := 0
		for i in m.lessons.size():
			if str(m.lessons[i][2]) == source:
				drop = i
				break
		m.lessons.remove_at(drop)
	Society.decide(w, tr("Lehre: %s") % text)


## Text einer Lehre (aus dem Archiv, den neuesten Lehren oder den Regeln). Alte Spielstände
## haben nur fertigen Text (damals Englisch fürs Sprachmodell).
func lesson_text(l) -> String:
	if l is Array:
		if not l.is_empty() and l[l.size() - 1] is Dictionary:
			return _lesson_words(l[l.size() - 1])
		return str(l[1]) if l.size() > 1 else ""
	return str(l)


func _lesson_words(d: Dictionary) -> String:
	var season := Seasons.season_name(int(d.get("s", 0)))
	var v: Array = d.get("v", [])
	match str(d.get("t", "")):
		"essen":
			return tr("%s: Das Essen sank um %.1f je Tag, obwohl %d Siedler Essen holten. %s") % [season, float(v[0]), int(v[1]),
				tr("Vor dem Winter Vorräte anlegen.") if int(d.s) in [Seasons.AUTUMN, Seasons.WINTER] else tr("Mehr Felder oder Fischer nötig.")]
		"ohne":
			return tr("%s: Ohne Siedler, die Essen holen, sinkt das Essen schnell (%.1f je Tag).") % [season, float(v[0])]
		"holz":
			return tr("%s: Es wird viel Holz verbrannt (%.1f je Tag). Im Sommer Holz sammeln.") % [season, float(v[0])]
		"wachsen":
			return tr("%s: Mit Schwerpunkt %s wuchs die Insel (%+.1f Siedler je Tag).") % [season, Society.strat_name(str(d.get("f", ""))), float(v[0])]
		"laune":
			return tr("%s: Die Laune sank stark (%.1f je Tag). Feste und Freizeit helfen.") % [season, float(v[0])]
		"leer":
			var why := str(d.get("why", ""))
			return tr("%s: %d × %s hatten nur %d %% der Tageszeit eigene Arbeit, %d %% anderes, %d %% untätig%s. Dann reichen weniger.") % [
				season, int(v[0]), _jname(str(d.get("j", ""))), int(v[1]), int(v[2]), int(v[3]), (" (%s)" % why) if why != "" else ""]
		"untaetig":
			return tr("%s: Die Siedler waren %d %% der Tageszeit untätig. Werkstätten oder Häuser bauen, damit alle Arbeit haben.") % [season, int(v[0])]
	return ""


# ================================================================== Herrscher
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
				msg = tr("Dafür fehlt Material. Der Rat baut es, sobald es reicht.")
			elif spot.x < 0:
				msg = tr("Kein Platz für %s.") % Data.buildings[value].name
			else:
				_build(w, {"type": value, "why": tr("Befehl des Herrschers.")}, tr("auf Befehl des Herrschers"))
				_drop_binding(w, "bau")
		"forschung":
			if Game.research.current == "" or Game.research.current != value:
				var err := Game.start_research(value)
				if err == "":
					_drop_binding(w, "forschung")
					Society.log_line(w, tr("Auf Befehl des Herrschers wird %s erforscht.") % Data.techs[value].name)
				else:
					msg = err
		"beruf":
			pass
	Society.log_line(w, tr("Feste Vorgabe des Herrschers: %s.") % _binding_text(b))
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
		Society.log_line(w, tr("Vorgabe aufgehoben: %s.") % _binding_text(m.binding[i]))
		m.binding.remove_at(i)
		changed.emit()
		Society.changed.emit()


func set_prio(w, key: String, v: int) -> void:
	var m := mem(w)
	m.prios[key] = clampi(v, 0, 3)
	Society.decide(w, tr("Herrscher: Priorität %s jetzt %s.") % [tr(cfg("priorities", {}).get(key, key)), tr(PRIO_WORDS[clampi(v, 0, 3)])])
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
