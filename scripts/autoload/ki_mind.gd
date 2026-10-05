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
const PRIO_WORDS_EN := ["unimportant", "normal", "important", "very important"]
const PRIO_EN := {"nahrung": "food", "rohstoffe": "wood and stone", "bauen": "building", "forschung": "research",
	"wachstum": "growth", "schutz": "protection", "handel": "trade"}
const TRADE_GOODS := ["holz", "stein", "bretter", "lehm", "ziegel", "werkzeug", "eisen", "erz", "kohle", "felle", "gold", "glas", "papier"]

var running := false
var epoch := 0
var activity := ""  # was gerade gerechnet wird (Anzeige)
var smem: Dictionary = {}  # Siedler-ID (Text) -> letzte Entscheidungen [[Tag, Beruf, eigene Wahl]]
var sdec: Dictionary = {}  # Siedler-ID (Text) -> letzte Entscheidung mit Wahrscheinlichkeiten
var trades: Array = []  # laufende Handelsrouten zwischen Inseln
var next_trade := 1
var last_prompt: Dictionary = {}  # rat/siedler -> letzte Anfrage (zum Ansehen)
var _trade_en := ""  # Handel der laufenden Sitzung auf Englisch (für das Modell)
var traces: Array = []  # Debug: alle Anfragen an die Modelle mit Ergebnis (nur im Speicher, für den Bericht)
var trace_count := 0
var _round_start := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_en()
	var cf := ConfigFile.new()
	if cf.load("user://ki_mind.cfg") == OK:
		brake = bool(cf.get_value("ki", "brake", true))
	if "--kibrake=0" in OS.get_cmdline_user_args():
		brake = false


## Zeitbremse: Bei schneller Geschwindigkeit läuft das Spiel nur normal schnell, solange der
## Rat tagt oder Siedler auf ihre Entscheidung warten. Sonst wären die Angaben, mit denen die
## Modelle entscheiden, schon viele Spielstunden alt, bevor die Antwort kommt.
var brake := true
var braking := false
var _brake_check := 0.0


func set_brake(on: bool) -> void:
	brake = on
	var cf := ConfigFile.new()
	cf.set_value("ki", "brake", on)
	cf.save("user://ki_mind.cfg")
	changed.emit()


func _overdue() -> int:
	var n := 0
	var lim := float(cfg("settler_days", 0.25)) * 2.0
	for w in Sea.all_worlds():
		if not is_instance_valid(w):
			continue
		for s in w.settlers:
			if not is_instance_valid(s) or not s.is_adult() or s.job == "seemann" or s.mind.needs_bed() \
					or float(Society.orders.get(s.id, 0.0)) > Game.time_days:
				continue
			var d: Dictionary = sdec.get(str(s.id), {})
			if not d.is_empty() and Game.time_days - float(d.get("day", 0.0)) > lim:
				n += 1
	return n


func _update_brake(delta: float) -> void:
	_brake_check -= delta
	if _brake_check > 0.0:
		return
	_brake_check = 0.5
	var want := brake and active() and Game.speed > 1 and not Game.is_over and (council_busy or _overdue() > 0)
	if want != braking:
		braking = want
		changed.emit()
	if Game.speed > 1:
		Engine.time_scale = 1.0 if braking else float(Game.speed)


## Englisch für die Sprachmodelle: Alle Anfragen und Antworten der Modelle sind Englisch,
## egal in welcher Sprache die Oberfläche läuft (josh 2026-10-05). Namen aus data/ki_en.json.
var EN: Dictionary = {}


func _load_en() -> void:
	var f := FileAccess.open("res://data/ki_en.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			EN = d


func _en_entry(sec: String, id: String) -> Variant:
	return EN.get(sec, {}).get(id, null)


func en_name(sec: String, id: String) -> String:
	var e = _en_entry(sec, id)
	if e is Dictionary:
		return str(e.get("name", id))
	if e != null:
		return str(e)
	return id.replace("_", " ")


func en_desc(sec: String, id: String) -> String:
	var e = _en_entry(sec, id)
	return str(e.get("desc", "")) if e is Dictionary else ""


func en_res(id: String) -> String:
	return "food" if id == "food" else en_name("resources", id)


func en_job(j: String) -> String:
	return en_name("jobs", j) if _en_entry("jobs", j) != null else JOB_EN.get(j, [j])[0]


func en_season(s: int = -1) -> String:
	if s < 0:
		s = Seasons.season()
	return SEASON_EN[clampi(s, 0, 3)]


func en_goods(goods: Dictionary) -> String:
	var parts := []
	for id in goods:
		if int(goods[id]) > 0:
			parts.append("%d %s" % [int(goods[id]), en_res(id)])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func en_strat(k: String) -> String:
	return en_name("strategies", k)


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
		"records": [], "lessons": [], "exp": {}, "councils": 0, "waiting": false,
		"archive": [], "knowledge": [], "lesson_new": 0, "stats": [], "stat_total": {}, "fit": {}, "stat_from": Game.time_days}
	for k in defaults:
		if not m.has(k):
			m[k] = defaults[k]
	if not m.has("clean_v2"):
		# Ältere Spielstände: abgeschnittene Lehren und Ansage auf ganze Sätze kürzen
		m["clean_v2"] = true
		for l in m.lessons:
			l[1] = _clean(str(l[1]))
		m.plan = _clean(str(m.plan)) if str(m.plan) != "" else ""
	if not m.has("en_v1"):
		# Seit 2026-10-05 denkt die KI auf Englisch: gemessene Lehren werden auf Englisch neu
		# geschrieben, darum fallen die alten deutschen weg (die nächste Messung ersetzt sie).
		m["en_v1"] = true
		m.lessons = m.lessons.filter(func(l): return str(l[2]) != "Messung")
	if not m.has("archive_v1"):
		# Seit 2026-10-05 bleiben alle Lehren das ganze Spiel über im Archiv
		m["archive_v1"] = true
		if m.archive.is_empty():
			for l in m.lessons:
				m.archive.append([l[0], l[1], l[2], l[3] if l.size() > 3 else "", -1])
			m.lesson_new = m.lessons.size()
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
	_update_brake(_delta / maxf(0.01, Engine.time_scale))
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
	var g0 := Game.time_days
	for w in worlds:
		if not await _alive(ep):
			return
		if not is_instance_valid(w) or w.settlers.is_empty():
			continue
		var m := mem(w)
		if Game.time_days >= float(m.next_council) and not Game.is_night():
			m.next_council = Game.time_days + float(cfg("council_days", 1.0))
			var c0 := Game.time_days
			council_busy = true
			await _council(w, ep)
			council_busy = false
			_note_lag("rat", (Game.time_days - c0) * 24.0)
			did = true
			if ep != epoch:
				return
		# Wer am dringendsten eine Entscheidung braucht, kommt zuerst dran: Bei vielen Siedlern
		# dauert eine Runde lange, und wer zuletzt käme, hätte sonst den ältesten Stand.
		var queue: Array = w.settlers.duplicate()
		queue.sort_custom(func(a, b): return _urgency(a) > _urgency(b))
		for s in queue:
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
	council_busy = false
	if did:
		_note_lag("runde", (Game.time_days - g0) * 24.0)
	if not did:
		# Nichts zu tun: kurz warten, bevor die nächste Runde startet
		running = true
		await get_tree().create_timer(0.5).timeout
		if ep == epoch:
			running = false


# ================================================================== Gemeinsame Texte
const SEASON_EFFECTS_EN := [
	"trees grow fastest, fields are sown, animals have young",
	"long days, berries ripen, grain grows best, fresh food spoils faster",
	"mushroom time, everything else grows slower, no more sowing, storms slow ships, houses need some wood",
	"nothing grows, short days, snow slows building and walking, every settler needs wood for heating and more food, stores do not spoil"]


func _season_rules() -> String:
	var out := []
	for s in 4:
		out.append("%s: %s." % [en_season(s).capitalize(), SEASON_EFFECTS_EN[s]])
	return "A year has 4 seasons of %d days each. %s An adult eats about 3 food per day. Heating wood per settler and day: autumn 0.3, winter 1. Fields are only sown in spring and summer; winter destroys the crops." % [
		int(Seasons.season_days()), " ".join(out)]


func _when() -> String:
	return "Day %d, %s (day %d of %d), year %d" % [Game.day(), en_season(), Seasons.day_in_season(), int(Seasons.season_days()), Seasons.year() + 1]


func _jname(j: String) -> String:
	return Data.jobs.get(j, {}).get("name", j)


func _skill_text(s) -> String:
	var parts := []
	var tal: Dictionary = s.mind.talents
	var ks: Array = tal.keys()
	ks.sort_custom(func(a, b): return float(tal[a]) + s.skill_level(a) * 0.1 > float(tal[b]) + s.skill_level(b) * 0.1)
	for sk in ks.slice(0, 3):
		parts.append("%s %s (level %d)" % [en_name("skills", sk), _talent_word(float(tal[sk])), int(s.skill_level(sk))])
	return ", ".join(parts)


func _food_text(w) -> String:
	var parts := []
	for id in Data.resources:
		if Data.resources[id].get("category", "") == "food" and Game.amount(id, w) > 0:
			parts.append("%d %s" % [Game.amount(id, w), en_res(id)])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _stock_text(w) -> String:
	var parts := []
	for id in Data.resources:
		if Data.resources[id].get("category", "") == "material" and Game.amount(id, w) > 0:
			parts.append("%d %s" % [Game.amount(id, w), en_res(id)])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _needs(w, sit: Dictionary) -> Array:
	var n := []
	if float(sit.food) < float(sit.food_target):
		n.append("food (%d of %d)" % [int(sit.food), int(sit.food_target)])
	if float(sit.wood) < float(sit.wood_target):
		n.append("wood (%d of %d)" % [int(sit.wood), int(sit.wood_target)])
	if float(sit.stone) < float(sit.stone_target):
		n.append("stone (%d of %d)" % [int(sit.stone), int(sit.stone_target)])
	if int(sit.pop) >= int(sit.housing):
		n.append("housing (%d settlers, %d places)" % [int(sit.pop), int(sit.housing)])
	if int(sit.vit_low) > 0:
		n.append("vitamins (%d lacking)" % int(sit.vit_low))
	if int(sit.predators) > 0:
		n.append("protection from %d predators" % int(sit.predators))
	return n


func _resources_text(w) -> String:
	var c := {}
	for n in w.nodes:
		if n.amount > 0:
			c[n.type] = int(c.get(n.type, 0)) + 1
	var parts := []
	for t in c:
		parts.append("%d %s" % [int(c[t]), en_name("nodes", t)])
	return ", ".join(parts) if not parts.is_empty() else "none"


func _buildings_text(w) -> String:
	var groups := {}
	var sites := []
	for b in w.buildings:
		if not b.complete:
			sites.append("%s at (%d,%d)" % [en_name("buildings", b.type), b.cell.x, b.cell.y])
			continue
		if not groups.has(b.type):
			groups[b.type] = []
		groups[b.type].append("(%d,%d)" % [b.cell.x, b.cell.y])
	var parts := []
	for t in groups:
		var cells: Array = groups[t]
		parts.append("%s %dx at %s" % [en_name("buildings", t), cells.size(), " ".join(cells.slice(0, 4)) + (" ..." if cells.size() > 4 else "")])
	var out := "; ".join(parts) if not parts.is_empty() else "none"
	if not sites.is_empty():
		out += ". Construction sites: " + "; ".join(sites)
	return out


func _islands_text(w) -> String:
	var lines := []
	for m in Sea.islands:
		var id := int(m.id)
		var pos: Array = m.get("pos", [0, 0])
		var where := "(%.1f, %.1f)" % [float(pos[0]), float(pos[1])]
		var kind: String = en_name("islands", str(m.get("biome", "heimat")))
		var state: String = m.get("state", "")
		if state == "settled" and Sea.worlds.has(id):
			var o = Sea.worlds[id]
			var osit: Dictionary = Society.situation(o)
			var need := _needs(o, osit)
			lines.append("- %s%s, %s at %s: %d settlers. Resources: %s. Stores: %s; food %d. Needs: %s." % [m.name,
				" (your island)" if id == int(w.island_id) else "", kind, where, o.settlers.size(), _resources_text(o),
				_stock_text(o), int(osit.food), ", ".join(need) if not need.is_empty() else "nothing urgent"])
		elif state == "discovered":
			lines.append("- %s, %s at %s: discovered, uninhabited." % [m.name, kind, where])
		elif state == "lost":
			lines.append("- %s at %s: lost." % [m.name, where])
	return "\n".join(lines)


func _ship_status_en(sh: Dictionary) -> String:
	if sh.state == "sea":
		for v in Sea.voyages:
			if int(v.get("ship", -1)) == int(sh.id):
				if v.kind == "explore":
					return "exploring the sea"
				return "sailing to %s, %d hours left" % [Sea.meta(int(v.to)).get("name", "?"), int(ceil(maxf(0.0, float(v.arrive) - Game.time_days) * 24.0))]
		return "at sea"
	var where: String = Sea.meta(int(sh.at)).get("name", "?")
	if sh.state == "load":
		return "loading in %s" % where
	return "in %s" % where


func _ships_text() -> String:
	var lines := []
	for sh in Sea.ships:
		var route := ""
		if not sh.route.is_empty():
			var stops := []
			for stp in sh.route:
				stops.append("%s (loads %s)" % [Sea.meta(int(stp.island)).get("name", "?"), en_goods(stp.get("load", {}))])
			route = " Route: " + " -> ".join(stops)
		lines.append("- %s (%s), home %s: %s.%s" % [sh.name, en_name("ships", str(sh.type)),
			Sea.meta(int(sh.home)).get("name", "?"), _ship_status_en(sh), route])
	return "\n".join(lines) if not lines.is_empty() else "No ships."


func _settlers_text(w) -> String:
	var lines := []
	var adults: Array = w.settlers.filter(func(s): return s.is_adult())
	for s in adults.slice(0, 16):
		var last := ""
		var sm: Array = smem.get(str(s.id), [])
		if not sm.is_empty():
			var e: Array = sm[sm.size() - 1]
			last = "; last: %s%s" % [en_job(e[1]), " (own choice)" if e[2] else ""]
		var state := ""
		if s.mind.needs_bed():
			state = ", sick"
		elif s.hunger < 35.0:
			state = ", hungry"
		lines.append("- %s, %d years, %s; skills: %s%s%s" % [s.display_name, int(s.age), en_job(s.job), _skill_text(s), state, last])
	if adults.size() > 16:
		var rest := {}
		for s in adults.slice(16):
			rest[s.job] = int(rest.get(s.job, 0)) + 1
		var parts := []
		for j in rest:
			parts.append("%d %s" % [int(rest[j]), en_job(j)])
		lines.append("- and %d more: %s" % [adults.size() - 16, ", ".join(parts)])
	return "\n".join(lines)


## Die ganze Lage einer Insel für den Rat (was josh aufgezählt hat).
func island_report(w) -> String:
	var sit: Dictionary = Society.situation(w)
	var need := _needs(w, sit)
	return "%s.\nIsland %s. Settlers: %d (%d adults, %d children), housing %d.\nAdults:\n%s\nBuildings: %s.\nStores: food %d (%s). Materials: %s. Storage %d %% full.\nThe island needs: %s.\nResources on the island: %s.\nIslands:\n%s\nShips:\n%s" % [
		_when(), Sea.island_name(w), int(sit.pop), int(sit.adults), int(sit.kids), int(sit.housing),
		_settlers_text(w), _buildings_text(w), int(sit.food), _food_text(w), _stock_text(w), int(float(sit.storage_full) * 100.0),
		", ".join(need) if not need.is_empty() else "nothing urgent", _resources_text(w), _islands_text(w), _ships_text()]


## Systemtext des Rats: Rolle, Ziel, Spielregeln, Herrscher, Gedächtnis.
func council_system(w) -> String:
	var m := mem(w)
	var main: bool = int(w.island_id) == 0
	var goal := "Your goal: the island should grow and research should advance. You also decide what is researched next." if main \
		else "Your goal: the island should grow. The main island decides research."
	var t := "You are the island council of %s in a settlement building game. You tell the settlers what to do and decide what gets built. The settlers make the final choice themselves. %s Always answer in English.\nGame rules: %s" % [
		Sea.island_name(w), goal, _season_rules()]
	var pr := []
	for k in cfg("priorities", {}):
		var v := prio(w, k)
		if v != 1:
			pr.append("%s %s" % [PRIO_EN.get(k, k), PRIO_WORDS_EN[v]])
	if not pr.is_empty():
		t += "\nThe ruler's priorities: %s." % ", ".join(pr)
	var wishes := []
	for x in m.wishes:
		if Game.time_days - float(x[0]) < 3.0:
			wishes.append("\"%s\"" % x[1])
	if not wishes.is_empty():
		t += "\nThe ruler told you: %s" % " ".join(wishes)
	var binds := []
	for b in m.binding:
		binds.append(_binding_text_en(b))
	if not binds.is_empty():
		t += "\nBinding orders from the ruler (must be followed): %s." % "; ".join(binds)
	var mem_t := memory_text(w)
	if mem_t != "":
		t += "\n" + mem_t
	return t


## Was der Rat gelernt hat: Lehren, gemessene Erfahrung, letzte Entscheidungen und Folgen.
func memory_text(w) -> String:
	var m := mem(w)
	var parts := []
	if not m.knowledge.is_empty():
		parts.append("What you have learned in this whole game (summary of all your lessons):\n" + "\n".join(m.knowledge.map(func(k): return "- " + str(k))))
	if not m.lessons.is_empty():
		var ls := []
		var nl: int = int(cfg("lessons_in_prompt", 3)) if not m.knowledge.is_empty() else m.lessons.size()
		for l in m.lessons.slice(maxi(0, m.lessons.size() - nl)):
			ls.append("- " + str(l[1]))
		parts.append("Your newest lessons:\n" + "\n".join(ls))
	var st := stats_lines(w, true)
	if not st.is_empty():
		parts.append("How your workers spent the daytime since the last meeting:\n" + "\n".join(st))
	var ex := experience_lines(w, 5, true)
	if not ex.is_empty():
		parts.append("Measured experience (change per day after your decision):\n" + "\n".join(ex))
	var rec := []
	for r in m.records.slice(maxi(0, m.records.size() - 4)):
		rec.append("- " + record_text(r, true))
	if not rec.is_empty():
		parts.append("Your last decisions and what happened after:\n" + "\n".join(rec))
	return "\n".join(parts)


func _binding_text(b: Dictionary) -> String:
	match str(b.kind):
		"fokus":
			return tr("Schwerpunkt %s") % Society.strat_name(b.value)
		"bau":
			return tr("%s bauen") % Data.buildings.get(b.value, {}).get("name", b.value)
		"forschung":
			return tr("%s erforschen") % Data.techs.get(b.value, {}).get("name", b.value)
		"beruf":
			return "mindestens %d %s" % [int(b.get("n", 1)), _jname(b.value)]
	return str(b.value)


func _binding_text_en(b: Dictionary) -> String:
	match str(b.kind):
		"fokus":
			return "focus %s" % en_strat(b.value)
		"bau":
			return "build %s" % en_name("buildings", b.value)
		"forschung":
			return "research %s" % en_name("techs", b.value)
		"beruf":
			return "at least %d %s" % [int(b.get("n", 1)), en_job(b.value)]
	return str(b.value)


func _ask_text(question: String, options: Array) -> String:
	var lines := [question]
	for i in options.size():
		lines.append("%d) %s" % [i + 1, options[i]])
	lines.append("Answer with the number only.")
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
	activity = tr("Rat von %s denkt nach: %s") % [Sea.island_name(w), topic]
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
	trace({"who": tr("Rat"), "isl": Sea.island_name(w), "role": "rat", "topic": topic, "prompt": last_prompt["rat"], "options": options,
		"probs": probs, "mass": float(r.get("mass", 0.0)), "top": str(r.get("top", "")), "ms": float(r.get("ms", 0.0)),
		"clarity": clar, "choice": options[i] if i < options.size() else "?", "rule": rule})
	return {"ok": true, "i": i, "probs": probs, "mass": float(r.get("mass", 0.0)), "top": str(r.get("top", "")), "ms": float(r.get("ms", 0.0)),
		"clarity": clar, "rule": rule}


# ================================================================== Rat
func _council(w, ep: int) -> void:
	var m := mem(w)
	var sit: Dictionary = Society.situation(w)
	var sit0 := sit  # Lage zu Beginn der Sitzung (für die Messung danach)
	Society._make_households(w, sit)
	_collect_stats(w)
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
		last.focus = {"choice": Society.strat_name(forced), "id": forced, "why": tr("Vorgabe des Herrschers")}
	else:
		var opts := keys.map(func(k): return "%s: %s" % [en_strat(k), en_desc("strategies", k)])
		var hint := keys.map(func(k): return maxf(0.05, float(sc.get(k, 0.0))))
		var r := await _council_choose(w, ep, system, report, tr("Schwerpunkt"), "Which focus is most important for your island now?", opts, hint)
		if not r.ok:
			return
		var labels := keys.map(func(k): return Society.strat_name(k))
		if keys[r.i] != m.focus:
			Society.log_line(w, tr("Der Rat (Llama) wählt den Schwerpunkt „%s“ (vorher „%s“).") % [labels[r.i], Society.strat_name(m.focus)])
		m.focus = keys[r.i]
		last.focus = {"choice": labels[r.i], "id": keys[r.i], "probs": _probs_text(labels, r.probs), "mass": r.mass}
		Society.decide(w, tr("Rat: Schwerpunkt %s. Modell: %s.") % [labels[r.i], last.focus.probs])
	Society.state(w).strategy = m.focus

	# Frische Lage vor jeder Frage: Eine Sitzung dauert echte Zeit, in der das Spiel weiterläuft
	# (bei schneller Geschwindigkeit viele Spielstunden). Jede Frage wird ohnehin ganz neu
	# eingelesen, die frische Lage kostet also nichts extra.
	sit = Society.situation(w)
	system = council_system(w)
	report = island_report(w)
	# 2. Welche Arbeit ist wie wichtig? Daraus bekommt jeder Siedler einen Auftrag,
	# aber nur so viele je Beruf, wie bis zur nächsten Sitzung Arbeit da ist.
	m["cap"] = job_capacity(w)
	m["cap_day"] = Game.time_days
	var jobs := _job_options(w, sit)
	if not jobs.is_empty():
		var want: Dictionary = Society.desired_jobs(w, sit)
		jobs.sort_custom(func(a, b): return float(want.get(a, 0.0)) > float(want.get(b, 0.0)))
		jobs = jobs.slice(0, 9)
		var cap: Dictionary = m.cap
		var opts := jobs.map(func(j): return "%s: %s Work until the next meeting for at most %d (%s)." % [en_job(j), en_desc("jobs", j), int(cap[j].n), cap[j].en])
		var hint := jobs.map(func(j): return 0.1 + float(want.get(j, 0.0)))
		var r := await _council_choose(w, ep, system, report, tr("Arbeit"), "Which work do your settlers need most urgently now?", opts, hint)
		if not r.ok:
			return
		var shares := {}
		for i in jobs.size():
			shares[jobs[i]] = float(r.probs[i]) if i < r.probs.size() else 0.0
		m.shares = shares
		var labels := jobs.map(func(j): return _jname(j))
		last.jobs = {"probs": _probs_text(labels, r.probs, 5), "mass": r.mass, "en": _probs_text(jobs.map(func(j): return en_job(j)), r.probs, 5)}
		_make_orders(w, sit)
		Society.decide(w, tr("Rat: Arbeit verteilt nach %s.") % last.jobs.probs)
	else:
		m.shares = {}
		_make_orders(w, sit)

	# 3. Bauen
	if not await _alive(ep):
		return
	# Frische Lage vor jeder Frage: Eine Sitzung dauert echte Zeit, in der das Spiel weiterläuft
	# (bei schneller Geschwindigkeit viele Spielstunden). Jede Frage wird ohnehin ganz neu
	# eingelesen, die frische Lage kostet also nichts extra.
	sit = Society.situation(w)
	system = council_system(w)
	report = island_report(w)
	var bforced := _binding_value(w, "bau")
	if bforced != "":
		_build(w, {"type": bforced, "why": tr("Vorgabe des Herrschers.")}, tr("auf Befehl des Herrschers"))
		_drop_binding(w, "bau")
		last.build = {"choice": Data.buildings[bforced].name, "id": bforced, "en": en_name("buildings", bforced), "why": tr("Vorgabe des Herrschers")}
	elif w.fire_building() != null and _storage_rule(w, sit):
		last.build = {"choice": Data.buildings[str(m.get("store_built", "lager"))].name, "id": str(m.get("store_built", "lager")),
			"en": en_name("buildings", str(m.get("store_built", "lager"))), "why": tr("Lager fast voll")}
	elif w.fire_building() != null and w.construction_sites().size() < 2:
		var cands := build_options(w, sit)
		if not cands.is_empty():
			cands = cands.slice(0, int(cfg("max_options", 8)))
			var opts := cands.map(func(c): return "%s: %s Cost %s." % [_build_name_en(w, c), c.get("why_en", "Useful for the island now."), _cost_text_en(c.type)])
			opts.append("Build nothing, save materials.")
			var hint := []
			for i in cands.size():
				hint.append(1.0 / (1.0 + i))
			hint.append(0.3)
			var r := await _council_choose(w, ep, system, report, tr("Bauen"), "What should be built next?", opts, hint)
			if not r.ok:
				return
			var labels := cands.map(func(c): return _build_name(w, c))
			labels.append(tr("nichts"))
			last.build = {"choice": labels[r.i], "probs": _probs_text(labels, r.probs), "mass": r.mass,
				"id": cands[r.i].type if r.i < cands.size() else "", "en": _build_name_en(w, cands[r.i]) if r.i < cands.size() else "nothing"}
			if r.i < cands.size() and w.construction_sites().size() >= 2:
				Society.decide(w, tr("Rat: Bau %s verschoben, inzwischen sind schon zwei Baustellen offen.") % labels[r.i])
			elif r.i < cands.size():
				_build(w, cands[r.i], tr("der Rat hat es beschlossen"))
			Society.decide(w, tr("Rat: Bauen %s. Modell: %s.") % [labels[r.i], last.build.probs])

	# 4. Forschung (nur Hauptinsel)
	if not await _alive(ep):
		return
	# Frische Lage vor jeder Frage: Eine Sitzung dauert echte Zeit, in der das Spiel weiterläuft
	# (bei schneller Geschwindigkeit viele Spielstunden). Jede Frage wird ohnehin ganz neu
	# eingelesen, die frische Lage kostet also nichts extra.
	sit = Society.situation(w)
	system = council_system(w)
	report = island_report(w)
	if int(w.island_id) == 0 and Game.research.current == "":
		var tforced := _binding_value(w, "forschung")
		if tforced != "" and Game.tech_state(tforced) == "available":
			_research(w, tforced, tr("auf Befehl des Herrschers"))
			_drop_binding(w, "forschung")
			last.research = {"choice": Data.techs[tforced].name, "id": tforced, "en": en_name("techs", tforced), "why": tr("Vorgabe des Herrschers")}
		else:
			var techs := research_options(w)
			if not techs.is_empty():
				var opts := techs.map(func(t): return "%s: %s" % [en_name("techs", t), en_desc("techs", t)])
				var hint := []
				for i in techs.size():
					hint.append(1.0 / (1.0 + i))
				var r := await _council_choose(w, ep, system, report, tr("Forschung"), "What should your researchers research next?", opts, hint)
				if not r.ok:
					return
				if Game.research.current != "":
					# Während der Rat nachdachte, wurde schon etwas anderes begonnen
					Society.decide(w, tr("Rat: Forschung %s verworfen, inzwischen wird %s erforscht.") % [Data.techs[techs[r.i]].name, Data.techs[Game.research.current].name])
				else:
					var labels := techs.map(func(t): return Data.techs[t].name)
					last.research = {"choice": labels[r.i], "probs": _probs_text(labels, r.probs), "mass": r.mass, "id": techs[r.i], "en": en_name("techs", techs[r.i])}
					_research(w, techs[r.i], tr("der Rat hat es beschlossen"))
					Society.decide(w, tr("Rat: Forschung %s. Modell: %s.") % [labels[r.i], last.research.probs])

	# 5. Handel mit anderen Inseln
	if not await _alive(ep):
		return
	# Frische Lage vor jeder Frage: Eine Sitzung dauert echte Zeit, in der das Spiel weiterläuft
	# (bei schneller Geschwindigkeit viele Spielstunden). Jede Frage wird ohnehin ganz neu
	# eingelesen, die frische Lage kostet also nichts extra.
	sit = Society.situation(w)
	system = council_system(w)
	report = island_report(w)
	_trade_en = ""
	var tr := await _trade(w, ep, system, report, sit)
	if ep != epoch:
		return
	if tr != "":
		last.trade = tr
		if _trade_en != "":
			last.trade_en = _trade_en

	# 6. Was sagt der Rat den Bewohnern?
	# Frische Lage vor jeder Frage: Eine Sitzung dauert echte Zeit, in der das Spiel weiterläuft
	# (bei schneller Geschwindigkeit viele Spielstunden). Jede Frage wird ohnehin ganz neu
	# eingelesen, die frische Lage kostet also nichts extra.
	sit = Society.situation(w)
	system = council_system(w)
	report = island_report(w)
	activity = tr("Rat von %s spricht zu den Bewohnern") % where
	var summary := _decision_summary(last)
	var msgs := [{"role": "system", "content": system},
		{"role": "user", "content": report + "\n\nYou decided: %s\nTell your settlers in one or two short sentences in English what they should do now and why. %s" % [_decision_summary_en(last), length_rule("reason_tokens")]}]
	last_prompt["rat"] = system + "\n\n" + msgs[1].content
	var gj = Llm.generate("rat", msgs, int(cfg("reason_tokens", 60)), 0.0, "We focus on %s. %s" % [en_strat(m.focus), _decision_summary_en(last)])
	var g: Dictionary = await gj.wait()
	if ep != epoch:
		return
	trace({"who": tr("Rat"), "isl": where, "role": "rat", "topic": tr("Ansage an die Bewohner"), "prompt": last_prompt["rat"], "text": str(g.get("text", g.get("error", ""))), "ms": float(g.get("ms", 0.0))})
	if g.get("ok", false):
		m.plan = _clean(str(g.get("text", "")))
		if m.plan != "":
			Society.log_line(w, tr("Der Rat sagt: „%s“") % m.plan)
			Game.notify_at(w, tr("Der Inselrat von %s: „%s“") % [where, m.plan], "glocke")
	last.plan = m.plan
	m.last = last
	m.councils = int(m.councils) + 1
	_remember(w, sit0, last)
	Society._council_requests(w, sit)
	# Alle paar Sitzungen zieht der Rat selbst eine Lehre
	if int(m.councils) % int(cfg("reflect_every", 3)) == 0 and m.records.size() >= 2:
		await _reflect(w, ep, system)
	if ep == epoch and int(m.lesson_new) >= int(cfg("summarize_every", 4)):
		await _summarize(w, ep)
	Society.changed.emit()
	changed.emit()


func _decision_summary_en(last: Dictionary) -> String:
	var parts := []
	if last.has("focus"):
		parts.append("focus %s" % en_strat(m_focus_id(last)))
	if last.has("jobs") and last.jobs.has("en"):
		parts.append("work: %s" % last.jobs.en)
	if last.has("build") and last.build.has("en"):
		parts.append("build: %s" % last.build.en)
	if last.has("research") and last.research.has("en"):
		parts.append("research: %s" % last.research.en)
	if last.has("trade_en"):
		parts.append("trade: %s" % last.trade_en)
	return ". ".join(parts) + "."


func m_focus_id(last: Dictionary) -> String:
	return str(last.get("focus", {}).get("id", ""))


func _decision_summary(last: Dictionary) -> String:
	var parts := []
	if last.has("focus"):
		parts.append(tr("Schwerpunkt %s") % last.focus.choice)
	if last.has("jobs"):
		parts.append(tr("Arbeit: %s") % last.jobs.probs)
	if last.has("build"):
		parts.append(tr("Bauen: %s") % last.build.choice)
	if last.has("research"):
		parts.append(tr("Forschen: %s") % last.research.choice)
	if last.has("trade"):
		parts.append(tr("Handel: %s") % last.trade)
	return ". ".join(parts) + "."


## Längengrenze für freie Antworten, steht in der Anfrage: Das Modell soll selbst kurz bleiben,
## statt an der Grenze abgeschnitten zu werden. Die Grenze zählt Wortstücke (Token); ein deutsches
## Wort sind etwa zwei, darum steht in der Anfrage die Hälfte als Wörter.
func length_rule(key: String) -> String:
	var words := int(int(cfg(key, 140)) * 0.6)
	return "Your whole answer must be at most %d words, otherwise it gets cut off. End with a complete sentence." % words


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
## Ergebnis: Beruf -> {"n": Plätze, "en": Begründung fürs Modell, "de": für die Anzeige}
func job_capacity(w) -> Dictionary:
	var m := mem(w)
	var h := clampf(float(m.next_council) - Game.time_days, 0.3, 2.0)
	var day_secs := float(Data.bal("day_length")) * maxf(0.3, Seasons.night_start() - Seasons.night_end())
	var pace := float(Data.bal("work_pace", 1.0)) * Seasons.work_mult(w) * Society.work_mult(w)
	# Sekunden echter Arbeit, die ein Siedler bis zur nächsten Sitzung leistet (Wege, Essen, Pausen abgezogen)
	var secs := maxf(10.0, day_secs * h * float(cfg("work_share", 0.5)))
	var out := {}
	var need := func(j: String, work_s: float, en: String, de: String):
		var n := 0 if work_s <= 0.0 else int(ceil(work_s / secs - 0.15))
		if work_s > 0.0:
			n = maxi(1, n)
		out[j] = {"n": n, "en": en, "de": de, "secs": work_s}
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
		need.call("bauer", tsecs, "%d of %d fields need sowing or harvest" % [tasks, fields],
			tr("%d von %d Feldern brauchen Saat oder Ernte") % [tasks, fields])
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
		var en := "%d units to gather" % got
		var de := tr("%d Einheiten zu holen") % got
		if not full.is_empty():
			en += ", storage nearly full for %s" % ", ".join(full.map(func(r): return en_res(r)))
			de += tr(", Lager fast voll für %s") % ", ".join(full.map(func(r): return Data.resource_name(r)))
		if j in ["holzfaeller", "steinmetz"] or not units.is_empty() or Data.job_unlocked(j):
			need.call(j, total, en, de)
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
		var e: Dictionary = out.get(j, {"n": 0, "en": "", "de": "", "secs": 0.0})
		e.n = int(e.n) + wn
		e.secs = float(e.secs) + wn * secs
		e.en = (str(e.en) + "; " if str(e.en) != "" else "") + "%s can use %d" % [en_name("buildings", b.type), wn]
		e.de = (str(e.de) + "; " if str(e.de) != "" else "") + tr("%s braucht %d") % [b.def.name, wn]
		out[j] = e
	# Bauen: Restarbeit und noch fehlendes Material aller Baustellen
	var bsecs := 0.0
	var sites: Array = w.construction_sites()
	for b in sites:
		bsecs += maxf(0.0, float(b.def.work) - float(b.progress)) * 1.5 / maxf(0.1, pace * Seasons.build_mult())
		for res in b.def.cost:
			bsecs += maxf(0.0, int(b.def.cost[res]) - int(b.delivered.get(res, 0))) * 2.0
	if not sites.is_empty():
		need.call("baumeister", bsecs, "%d construction sites" % sites.size(), tr("%d Baustellen") % sites.size())
		out.baumeister.n = mini(int(out.baumeister.n), sites.size() * 3)
	# Forschen: so viele, wie Plätze da sind (auch wenn der Rat gleich erst ein Ziel wählt)
	var places := 0
	for b in w.buildings:
		if b.complete and b.def.has("research"):
			places += b.slots()
	if places > 0 and (Game.research.current != "" or (int(w.island_id) == 0 and not research_options(w).is_empty())):
		out["forscher"] = {"n": places, "en": "%d research places" % places, "de": tr("%d Forschungsplätze") % places, "secs": places * secs}
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
		out["jaeger"] = {"n": n, "en": "%d animals may be hunted" % prey, "de": tr("%d Tiere dürfen gejagt werden") % prey, "secs": n * secs}
	# Gemessene Auslastung: Wer zuletzt viel Leerlauf hatte, bekommt weniger Plätze
	var fit: Dictionary = m.get("fit", {})
	for j in out:
		var f := float(fit.get(j, 1.0))
		if f < 0.95 and int(out[j].n) > 1:
			out[j].n = maxi(1, int(round(float(out[j].n) * f)))
			out[j].en = str(out[j].en) + " (reduced to %d%% after measured idle time)" % int(f * 100.0)
			out[j].de = str(out[j].de) + tr(" (auf %d %% gesenkt nach gemessenem Leerlauf)") % int(f * 100.0)
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


func _cost_text_en(t: String) -> String:
	return en_goods(Data.buildings[t].get("cost", {}))


func _build_name_en(w, c: Dictionary) -> String:
	if c.has("upgrade"):
		var b = w.building_by_id(int(c.upgrade))
		return "upgrade %s to %s" % [en_name("buildings", b.type) if b else "?", en_name("buildings", c.type)]
	return en_name("buildings", c.type)


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
		add.call({"type": "feld", "why": tr("Mehr Felder bringen mehr Essen (Ernte im Sommer und Herbst)."), "why_en": "More fields bring more food (harvest in summer and autumn)."})
		if Game.is_unlocked("obstgarten"):
			add.call({"type": "obstgarten", "why": tr("Obst bringt Vitamine."), "why_en": "Fruit brings vitamins."})
	for t in Society.HOUSE_ORDER:
		if Game.is_unlocked(t) and Data.buildings[t].get("buildable", true):
			add.call({"type": t, "why": tr("Mehr Wohnplatz (%d Siedler, %d Plätze).") % [int(sit.pop), int(sit.housing)], "why_en": "More housing (%d settlers, %d places)." % [int(sit.pop), int(sit.housing)]})
			break
	for b in w.buildings:
		var to: String = b.def.get("upgrade", "")
		if b.complete and b.housing() > 0 and to != "" and Game.is_unlocked(to):
			add.call({"type": to, "upgrade": b.id, "why": tr("Mehr Platz für Familien."), "why_en": "More room for families."})
			break
	for t in Society.PROD_ORDER:
		if Game.is_unlocked(t) and Society._count(w, [t]) == 0:
			add.call({"type": t, "why": tr("%s fehlt noch auf der Insel.") % Data.buildings[t].name, "why_en": "The island has no %s yet." % en_name("buildings", t)})
	for t in ["schreibstube", "bibliothek", "universitaet", "labor", "schule"]:
		if Game.is_unlocked(t) and Society._count(w, [t]) == 0:
			add.call({"type": t, "why": tr("Ein Ort zum Forschen und Lernen."), "why_en": "A place for research and learning."})
	if not store.is_empty():
		add.call(store)
	if Game.is_unlocked("wachturm") and int(sit.predators) > 0:
		add.call({"type": "wachturm", "why": tr("%d Raubtiere auf der Insel.") % int(sit.predators), "why_en": "%d predators on the island." % int(sit.predators)})
	for t in ["werft", "anlegesteg", "hafen"]:
		if Game.is_unlocked(t) and Society._count(w, [t]) == 0:
			add.call({"type": t, "why": tr("Für Schiffe und Handel."), "why_en": "For ships and trade."})
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
				"why": tr("Das Lager ist zu %d %% voll (%d von %d). %s bringt %d Platz.") % [int(full * 100.0), Game.used_volume(w), Game.storage_volume(w), Data.buildings[t].name, add],
				"why_en": "Storage is %d %% full (%d of %d). When it is full, gatherers, woodcutters and stonecutters must stop. %s adds %d space." % [int(full * 100.0), Game.used_volume(w), Game.storage_volume(w), en_name("buildings", t), add]}
	return {}


func _build(w, c: Dictionary, how: String) -> void:
	var def: Dictionary = Data.buildings[c.type]
	if c.has("upgrade"):
		var b = w.building_by_id(int(c.upgrade))
		if b and b.complete and w.upgrade_building(b) != null:
			Society.log_line(w, tr("Der Rat lässt %s ausbauen (%s).") % [b.def.name, how])
			Game.notify_at(w, tr("Der Rat lässt %s ausbauen (%s).") % [b.def.name, how], "hammer")
		return
	var spot: Vector2i = Society.find_spot(w, c.type)
	if spot.x < 0:
		Society.decide(w, tr("Kein Platz für %s.") % def.name)
		return
	w.place_building(c.type, spot, false)
	Society.log_line(w, tr("Der Rat lässt bauen: %s bei (%d,%d) (%s).") % [def.name, spot.x, spot.y, how])
	Game.notify_at(w, tr("Der Rat lässt bauen: %s. %s") % [def.name, c.get("why", "")], "hammer")


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
	Game.notify_at(w, tr("Der Rat lässt erforschen: %s.") % Data.techs[t].name, "wissen")


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
	var opts := offers.map(func(x): return "Ask %s for %d %s" % [Sea.island_name(x[2]), int(x[1]), en_res(x[0])])
	opts.append("No trade.")
	var hint := []
	for i in offers.size():
		hint.append(0.6 / (1.0 + i))
	hint.append(0.4)
	var r := await _council_choose(w, ep, system, report, tr("Handel"), "Do you want to ask another island for goods? It will want something in return.", opts, hint)
	if not r.ok or r.i >= offers.size():
		return ""
	var off: Array = offers[r.i]
	var o = off[2]
	var good: String = off[0]
	var amount := int(off[1])
	Society.decide(w, tr("Handel: Der Rat bittet %s um %d %s.") % [Sea.island_name(o), amount, Data.resource_name(good)])
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
	var popts := pay_opts.map(func(x): return "Ask for %d %s" % [int(x[1]), en_res(x[0])])
	popts.append("Ask for nothing, we are glad to help.")
	popts.append("Refuse, we need it ourselves.")
	var phint := []
	for i in pay_opts.size():
		phint.append(0.8 / (1.0 + i))
	phint.append(0.2)
	phint.append(0.25)
	var osys := council_system(o)
	var orep := island_report(o)
	var pr := await _council_choose(o, ep, osys, orep, tr("Handel mit %s") % Sea.island_name(w),
		"The council of %s asks you for %d %s by ship. What do you want in return?" % [Sea.island_name(w), amount, en_res(good)], popts, phint)
	if not pr.ok or not is_instance_valid(o):
		return ""
	if pr.i == popts.size() - 1:
		Society.log_line(o, tr("Der Rat lehnt die Bitte von %s um %s ab.") % [Sea.island_name(w), Data.resource_name(good)])
		Society.log_line(w, tr("%s lehnt ab: keine %s für uns.") % [Sea.island_name(o), Data.resource_name(good)])
		_trade_en = "%s refused" % Sea.island_name(o)
		return tr("%s lehnt ab") % Sea.island_name(o)
	var price := {}
	if pr.i < pay_opts.size():
		price[pay_opts[pr.i][0]] = int(pay_opts[pr.i][1])
		# Der bittende Rat stimmt über den Preis ab
		var ar := await _council_choose(w, ep, system, report, tr("Preis"),
			"%s wants %s for %d %s. Do you accept?" % [Sea.island_name(o), en_goods(price), amount, en_res(good)],
			["Yes, accept.", "No, too expensive."], [0.6, 0.4])
		if not ar.ok:
			return ""
		if ar.i != 0:
			Society.log_line(w, tr("Der Rat lehnt den Preis von %s ab (%s).") % [Sea.island_name(o), Sea.goods_text(price)])
			_trade_en = "price of %s refused" % Sea.island_name(o)
			return tr("Preis von %s abgelehnt") % Sea.island_name(o)
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
		_trade_en = "agreed, but no free ship"
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
	_trade_en = "%s brings %s%s with the %s (home %s)" % [Sea.island_name(o), en_goods(g),
		(" for " + en_goods(p)) if not p.is_empty() else " as help", ship.name, Sea.meta(int(ship.home)).get("name", "?")]
	Society.log_line(w, tr("Handelsroute beschlossen: %s.") % text)
	Society.log_line(o, tr("Handelsroute beschlossen: %s.") % text)
	Game.notify(tr("Handel: %s.") % text, "boot")
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
func _settler_due(s) -> bool:
	if not s.is_adult() or s.job == "seemann":
		return false
	if float(Society.orders.get(s.id, 0.0)) > Game.time_days:
		Society.thoughts[s.id] = tr("Der Herrscher hat mich zum %s bestimmt. Das mache ich.") % s.job_name()
		return false
	if s.mind.needs_bed():
		Society.thoughts[s.id] = tr("Ich bin krank und muss liegen.")
		return false
	var d: Dictionary = sdec.get(str(s.id), {})
	return d.is_empty() or Game.time_days - float(d.get("day", -99.0)) >= float(cfg("settler_days", 0.25))


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


## Warum eine Siedler-Antwort nicht mehr passt (leer = passt noch). Dann wird sie nicht
## umgesetzt; der Siedler kommt in der nächsten Runde mit frischen Angaben wieder dran.
func _settler_stale(s, w, choice: String, order: String) -> String:
	if float(Society.orders.get(s.id, 0.0)) > Game.time_days:
		return tr("der Herrscher hat inzwischen bestimmt")
	if s.mind.needs_bed():
		return tr("inzwischen krank")
	if council_order(s) != order:
		return tr("der Rat hat inzwischen einen neuen Auftrag gegeben")
	if choice != s.job and choice != "frei" and not choice in _job_options(w, Society.situation(w)):
		return tr("%s hat inzwischen nichts mehr zu tun") % _jname(choice)
	return ""


## Wie dringend braucht ein Siedler eine neue Entscheidung? Noch nie entschieden, neuer
## Auftrag vom Rat, hungrig oder ohne Arbeit zuerst, sonst wessen Entscheidung am ältesten ist.
func _urgency(s) -> float:
	if not is_instance_valid(s):
		return -1.0
	var d: Dictionary = sdec.get(str(s.id), {})
	if d.is_empty():
		return 100.0
	var u := Game.time_days - float(d.get("day", 0.0))
	if council_order(s) != str(d.get("order", "")):
		u += 10.0
	if s.hunger < 35.0:
		u += 5.0
	if s.job == "frei":
		u += 3.0
	return u


## Wie alt sind die Antworten der Modelle, wenn sie ankommen (in Spielstunden)?
var lag := {"siedler": 0.0, "rat": 0.0, "runde": 0.0}
var council_busy := false


func _note_lag(key: String, hours: float) -> void:
	lag[key] = hours if float(lag.get(key, 0.0)) <= 0.0 else lerpf(float(lag[key]), hours, 0.3)


## Freier Wille der Siedler (josh 2026-10-05: vorerst aus). Aus: Jeder Siedler macht, was der Rat
## ihm aufträgt; ohne Auftrag bleibt er bei seiner Arbeit. Das Siedlermodell wird dann nicht
## gefragt (spart Rechenzeit). Die ganze Entscheidungslogik bleibt und ist mit
## "settler_free_will": true in data/ki_llm.json oder `--freewill=1` sofort wieder an.
func free_will() -> bool:
	return bool(cfg("settler_free_will", false)) or "--freewill=1" in OS.get_cmdline_user_args()


func _settler_obey(s, w, order: String) -> void:
	var choice: String = order if order != "" else s.job
	sdec[str(s.id)] = {"day": Game.time_days, "age_h": 0.0, "job": choice, "order": order, "own": false, "probs": "",
		"mass": 0.0, "top": "", "clarity": 0.0, "rule": "Auftrag des Rats (freier Wille aus)" if order != "" else "kein Auftrag, bleibt dabei (freier Wille aus)"}
	var hist: Array = smem.get(str(s.id), [])
	hist.append([snappedf(Game.time_days, 0.01), choice, false])
	if hist.size() > 3:
		hist = hist.slice(hist.size() - 3)
	smem[str(s.id)] = hist
	var old: String = s.job
	if choice != old:
		s.set_job(choice)
		Society.last_change[s.id] = Game.time_days
		Society.decide(w, tr("%s wird %s (vorher %s), wie der Rat sagt.") % [s.display_name, _jname(choice), _jname(old)])
	Society.thoughts[s.id] = (tr("Ich bin %s. Das ist mein Auftrag vom Rat.") % _jname(choice)) if order != "" else (tr("Ich bin %s. Der Rat hat mir nichts anderes aufgetragen.") % _jname(choice))
	changed.emit()


func _settler_turn(s, w) -> void:
	var ep := epoch
	var order := council_order(s)
	if not free_will():
		_settler_obey(s, w, order)
		return
	var opts := settler_options(s, w)
	activity = tr("%s überlegt, was er als Nächstes tut") % s.display_name if s.sex == "m" else tr("%s überlegt, was sie als Nächstes tut") % s.display_name
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
	var t0 := Game.time_days
	var r: Dictionary = await j1.wait()
	var r2: Dictionary = await j2.wait()
	if ep != epoch or not is_instance_valid(s) or s.world != w:
		return
	if not r.get("ok", false):
		return
	var age_h := (Game.time_days - t0) * 24.0
	_note_lag("siedler", age_h)
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
		rule = "unentschlossen, %s" % (tr("folgt dem Auftrag") if order != "" and opts[i] == order else tr("bleibt dabei"))
	else:
		i = pick(probs, float(cfg("settler_temperature", 0.35)))
		rule = "Modell"
	var choice: String = opts[i]
	# Ist die Antwort noch gültig? Während das Modell rechnete, lief das Spiel weiter.
	var stale := _settler_stale(s, w, choice, order)
	if stale != "":
		trace({"who": s.display_name, "isl": Sea.island_name(w), "role": "siedler", "topic": tr("Arbeit (verworfen)"),
			"text": tr("Antwort (%s) nach %.1f Spielstunden verworfen: %s") % [_jname(choice), age_h, stale]})
		return
	var own := order != "" and choice != order
	var names := opts.map(func(j): return _jname(j))
	var ptext := _probs_text(names, probs)
	sdec[str(s.id)] = {"day": Game.time_days, "age_h": age_h, "job": choice, "order": order, "own": own, "probs": ptext,
		"mass": float(r.get("mass", 0.0)), "top": str(r.get("top", "")), "clarity": clar, "rule": rule}
	trace({"who": s.display_name, "isl": Sea.island_name(w), "role": "siedler", "topic": tr("Arbeit"), "prompt": last_prompt["siedler"],
		"prompt2": msgs2[1].content, "options": names, "probs": probs, "probs_a": p1, "probs_b": p2r, "mass": [r.get("mass", 0.0), r2.get("mass", 0.0)],
		"top": [r.get("top", ""), r2.get("top", "")], "ms": float(r.get("ms", 0.0)) + float(r2.get("ms", 0.0)), "clarity": clar,
		"choice": names[i], "order": _jname(order) if order != "" else "", "rule": rule, "own": own, "age_h": age_h})
	var hist: Array = smem.get(str(s.id), [])
	hist.append([snappedf(Game.time_days, 0.01), choice, own])
	if hist.size() > 3:
		hist = hist.slice(hist.size() - 3)
	smem[str(s.id)] = hist
	var old: String = s.job
	if choice != old:
		s.set_job(choice)
		Society.last_change[s.id] = Game.time_days
		Society.decide(w, tr("%s wird %s (vorher %s)%s. Modell: %s.") % [s.display_name, _jname(choice), _jname(old),
			tr(", gegen den Auftrag (%s)") % _jname(order) if own else tr(", wie der Rat sagt"), ptext])
	var t := tr("Ich bin %s.") % _jname(choice)
	if own:
		t += tr(" Der Rat wollte mich als %s, aber ich habe selbst anders entschieden.") % _jname(order)
	elif order != "":
		t += tr(" Das ist mein Auftrag vom Rat.")
	if rule != "Modell":
		t += tr(" (Ich war unentschlossen.)")
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
		"trade": str(last.get("trade", "")), "jobs": jobs, "m": _metrics(w, sit),
		"build_en": str(last.get("build", {}).get("en", "")), "research_en": str(last.get("research", {}).get("en", "")),
		"trade_en": str(last.get("trade_en", ""))}
	m.records.append(rec)
	var mx := int(cfg("memory_records", 30))
	if m.records.size() > mx:
		m.records = m.records.slice(m.records.size() - mx)


func record_text(r: Dictionary, en: bool = false) -> String:
	if en:
		var e := "Day %d (%s): focus %s" % [int(float(r.d)) + 1, en_season(int(r.s)), en_strat(str(r.focus))]
		if str(r.get("build_en", "")) not in ["", "nothing"]:
			e += ", built %s" % r.build_en
		if str(r.get("research_en", "")) != "":
			e += ", researched %s" % r.research_en
		if str(r.get("trade_en", "")) != "":
			e += ", trade: %s" % r.trade_en
		if r.has("out"):
			var oo: Dictionary = r.out
			e += " -> after that per day: food %+.1f, wood %+.1f, stone %+.1f, settlers %+.1f, mood %+.1f" % [float(oo.food), float(oo.wood), float(oo.stone), float(oo.pop), float(oo.mood)]
		return e
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
func experience_lines(w, n: int, en: bool = false) -> Array:
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
		if en:
			out.append("- %s, focus %s: food %+.1f, wood %+.1f, stone %+.1f, settlers %+.1f, mood %+.1f (%d times)" % [
				en_season(int(p[0])), en_strat(p[1]), float(e[1]) / c, float(e[2]) / c, float(e[3]) / c,
				float(e[4]) / c, float(e[5]) / c, int(c)])
			continue
		out.append(tr("- %s, Schwerpunkt %s: Essen %+.1f, Holz %+.1f, Stein %+.1f, Siedler %+.1f, Laune %+.1f (%d mal)") % [
			Seasons.season_name(int(p[0])), Society.strat_name(p[1]), float(e[1]) / c, float(e[2]) / c, float(e[3]) / c,
			float(e[4]) / c, float(e[5]) / c, int(c)])
	return out


## Aus einer auffälligen Messung eine Lehre über die Spielmechanik machen.
func _measure_lesson(w, r: Dictionary, o: Dictionary) -> void:
	var food_workers := 0
	for j in ["sammler", "fischer", "bauer", "koch"]:
		food_workers += int(r.jobs.get(j, 0))
	var season := en_season(int(r.s))
	var text := ""
	var kind := ""
	if float(o.food) < -2.0 and food_workers > 0:
		kind = "essen"
		text = "In %s food fell by %.1f per day although %d people got food. %s" % [season, -float(o.food), food_workers,
			"Build up stores before winter." if int(r.s) in [Seasons.AUTUMN, Seasons.WINTER] else "More fields or fishers needed."]
	elif float(o.food) < -1.0 and food_workers == 0:
		kind = "ohne"
		text = "Without food workers food falls fast (%.1f per day in %s)." % [float(o.food), season]
	elif float(o.wood) < -3.0 and int(r.s) in [Seasons.AUTUMN, Seasons.WINTER]:
		kind = "holz"
		text = "In %s we burn a lot of wood (%.1f per day). Collect wood in summer." % [season, float(o.wood)]
	elif float(o.pop) > 0.4:
		kind = "wachsen|" + str(r.focus)
		text = "With focus %s in %s the island grew (+%.1f settlers per day)." % [en_strat(str(r.focus)), season, float(o.pop)]
	elif float(o.mood) < -5.0:
		kind = "laune"
		text = "In %s mood fell strongly (%.1f per day). Festivals and free time help." % [season, float(o.mood)]
	if text != "":
		# Dieselbe Beobachtung in derselben Jahreszeit ersetzt die alte (neueste Zahlen)
		add_lesson(w, text, "Messung", "%s|%d" % [kind, int(r.s)])


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


## Statistik als Text (en: fürs Modell), die Berufe mit den meisten Siedlern zuerst.
func stats_lines(w, en: bool = false, idx: int = -1) -> Array:
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
		if en:
			var g := en_goods(goods) if not goods.is_empty() else "nothing"
			out.append("- %s x%d: own work %d%%, other work %d%%, idle %d%%; delivered %s" % [en_job(j), int(e.n), sh[0], sh[1], sh[2], g])
		else:
			var g2 := Sea.goods_text(goods) if not goods.is_empty() else tr("nichts")
			out.append(tr("%s ×%d: eigene Arbeit %d %%, anderes %d %%, untätig %d %%; geliefert: %s") % [_jname(j), int(e.n), sh[0], sh[1], sh[2], g2])
	return out


func _stat_lessons(w, per: Dictionary) -> void:
	var season := en_season(int(per.s))
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
		var sh2 := _shares(e2)
		var why := ""
		var cap: Dictionary = mem(w).get("cap", {})
		if cap.has(worst):
			why = " (%s)" % str(cap[worst].en)
		add_lesson(w, "In %s, %d %s had their own work only %d%% of the daytime, %d%% other work, %d%% idle%s. Fewer %s are enough then." % [
			season, int(e2.n), en_job(worst), sh2[0], sh2[1], sh2[2], why, en_job(worst)], "Messung", "leer|%s|%d" % [worst, int(per.s)])
	elif all_day > 0.0 and all_idle / all_day > 0.3:
		add_lesson(w, "In %s, settlers were idle %d%% of the daytime. Build workshops or houses so everyone has work." % [
			season, int(all_idle / all_day * 100.0)], "Messung", "untaetig|%d" % int(per.s))


## Fasst alle Lehren zu wenigen Regeln zusammen, die das ganze Spiel über bleiben.
func _summarize(w, ep: int) -> void:
	var m := mem(w)
	var n := int(m.lesson_new)
	var fresh: Array = m.archive.slice(maxi(0, m.archive.size() - n))
	var fallback := _fallback_knowledge(w)
	var lines := []
	for l in fresh:
		lines.append("- " + str(l[1]))
	var before: String = "\n".join(m.knowledge.map(func(k): return "- " + str(k))) if not m.knowledge.is_empty() else "(nothing yet)"
	var mx := int(cfg("knowledge_max", 8))
	activity = tr("Rat von %s fasst zusammen, was er gelernt hat") % Sea.island_name(w)
	var system := "You are the island council of %s in a settlement building game. You keep a short list of rules you have learned about the game. Always answer in English." % Sea.island_name(w)
	var user := "Your rules so far:\n%s\n\nNew lessons:\n%s\n\nWrite your updated rules: at most %d rules, one per line, each starting with \"- \". Keep what is still true, merge rules that say the same, and drop what the new lessons show is wrong. Each rule is one short sentence with the concrete numbers or seasons that matter. %s" % [
		before, "\n".join(lines), mx, length_rule("summary_tokens")]
	var msgs := [{"role": "system", "content": system}, {"role": "user", "content": user}]
	last_prompt["rat"] = system + "\n\n" + user
	var j = Llm.generate("rat", msgs, int(cfg("summary_tokens", 220)), 0.0, "\n".join(fallback.map(func(k): return "- " + k)))
	var g: Dictionary = await j.wait()
	trace({"who": tr("Rat"), "isl": Sea.island_name(w), "role": "rat", "topic": tr("Lehren zusammenfassen"), "prompt": last_prompt["rat"], "text": str(g.get("text", g.get("error", ""))), "ms": float(g.get("ms", 0.0))})
	if ep != epoch:
		return
	var rules := []
	if g.get("ok", false):
		for line in str(g.get("text", "")).split("\n"):
			var t := line.strip_edges()
			var rx := RegEx.create_from_string("^(-|\\*|•|\\d+[.)])\\s*")
			t = rx.sub(t, "").strip_edges()
			if t.length() < 12:
				continue
			t = _clean(t)
			if t != "" and not t.ends_with("…") and not rules.has(t):
				rules.append(t)
	if rules.is_empty():
		rules = fallback
	m.knowledge = rules.slice(0, mx)
	m["knowledge_day"] = snappedf(Game.time_days, 0.01)
	m.lesson_new = 0
	Society.decide(w, tr("Rat: Lehren zusammengefasst (%d Regeln aus %d Lehren).") % [m.knowledge.size(), m.archive.size()])
	changed.emit()


## Ohne Modellantwort: je Art von Beobachtung die neueste Lehre, die häufigsten zuerst.
func _fallback_knowledge(w) -> Array:
	var m := mem(w)
	var latest := {}
	var count := {}
	for l in m.archive:
		var k := str(l[3]) if l.size() > 3 and str(l[3]) != "" else str(l[1])
		latest[k] = str(l[1])
		count[k] = int(count.get(k, 0)) + 1
	var keys: Array = latest.keys()
	keys.sort_custom(func(a, b): return int(count[a]) > int(count[b]))
	var out := []
	for k in m.knowledge:
		if out.size() < int(cfg("knowledge_max", 8)) / 2:
			out.append(str(k))
	for k in keys:
		if out.size() >= int(cfg("knowledge_max", 8)):
			break
		if not out.has(latest[k]):
			out.append(latest[k])
	return out


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
	# Archiv: jede Lehre bleibt das ganze Spiel über (zum Nachlesen und für die Zusammenfassung)
	m.archive.append([snappedf(Game.time_days, 0.01), text, source, key, int(Seasons.season())])
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
	Society.decide(w, tr("Lehre (%s): %s") % [source, text])


## Llama schaut auf seine letzten Entscheidungen und deren Folgen und zieht selbst eine Lehre.
func _reflect(w, ep: int, system: String) -> void:
	var m := mem(w)
	var lines := []
	for r in m.records.slice(maxi(0, m.records.size() - 6)):
		lines.append("- " + record_text(r, true))
	activity = tr("Rat von %s denkt über seine Entscheidungen nach") % Sea.island_name(w)
	var msgs := [{"role": "system", "content": system},
		{"role": "user", "content": "Your last decisions and what happened after:\n%s\n\nWhat did you learn from this about the game mechanics? Write one short, concrete lesson in one sentence in English that will help you in the future. %s" % ["\n".join(lines), length_rule("reason_tokens")]}]
	last_prompt["rat"] = system + "\n\n" + msgs[1].content
	var hint := "In %s we need more food workers when food goes down." % en_season()
	var j = Llm.generate("rat", msgs, int(cfg("reason_tokens", 60)), 0.0, hint)
	var g: Dictionary = await j.wait()
	trace({"who": tr("Rat"), "isl": Sea.island_name(w), "role": "rat", "topic": tr("Lehre ziehen"), "prompt": last_prompt["rat"], "text": str(g.get("text", g.get("error", ""))), "ms": float(g.get("ms", 0.0))})
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
		m.chat.append(["Rat", tr("(Die Sprachmodelle sind nicht geladen. Dein Wunsch ist notiert und gilt für die nächsten Ratssitzungen.)"), snappedf(Game.time_days, 0.01)])
		m.waiting = false
		changed.emit()
		return
	var ep := epoch
	var hist := []
	for c in m.chat.slice(maxi(0, m.chat.size() - 7), m.chat.size() - 1):
		hist.append("%s: %s" % ["Ruler" if c[0] == "Du" else "Council", c[1]])
	var msgs := [{"role": "system", "content": council_system(w)},
		{"role": "user", "content": "%s\n\n%sThe ruler says to you: \"%s\"\nAnswer the ruler briefly in English (at most three sentences). Say whether and how you follow the wish. %s" % [
			island_report(w), ("Conversation so far:\n%s\n\n" % "\n".join(hist)) if not hist.is_empty() else "", text, length_rule("chat_tokens")]}]
	last_prompt["rat"] = msgs[0].content + "\n\n" + msgs[1].content
	var j = Llm.generate("rat", msgs, int(cfg("chat_tokens", 90)), 0.3, "We heard your wish and will consider it at the next session.")
	var g: Dictionary = await j.wait()
	trace({"who": tr("Rat"), "isl": Sea.island_name(w), "role": "rat", "topic": tr("Gespräch mit dem Herrscher"), "prompt": last_prompt["rat"], "text": str(g.get("text", g.get("error", ""))), "ms": float(g.get("ms", 0.0))})
	if ep != epoch:
		return
	m.waiting = false
	var ans := _clean(str(g.get("text", ""))) if g.get("ok", false) else tr("(Keine Antwort: %s)") % g.get("error", "")
	m.chat.append(["Rat", ans, snappedf(Game.time_days, 0.01)])
	if m.chat.size() > 30:
		m.chat = m.chat.slice(m.chat.size() - 30)
	Society.decide(w, tr("Gespräch: Herrscher „%s“, Rat „%s“") % [text, ans])
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
	Society.decide(w, tr("Herrscher: Priorität %s jetzt %s.") % [cfg("priorities", {}).get(key, key), PRIO_WORDS[clampi(v, 0, 3)]])
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
				traces[old][k] = tr("(gekürzt) ") + str(traces[old][k]).right(600)


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
	L.append(tr("KI-BERICHT New World (KI-Version)"))
	L.append(tr("Erstellt: %s, Spieltag %d (%s), Jahr %d") % [Time.get_datetime_string_from_system(false, true), Game.day(), Seasons.season_name(), Seasons.year() + 1])
	L.append(Llm.status_text())
	L.append(tr("Geladen: %s") % JSON.stringify(Llm.loaded))
	L.append(tr("Gerät: %s, Prüfung: %s, übersprungen: %s") % [Llm.device, JSON.stringify(Llm.probe), JSON.stringify(Llm.skipped)])
	L.append(tr("Anfragen: Rat %d (Schnitt %.1f s), Siedler %d (Schnitt %.2f s)") % [int(Llm.stats.rat[0]), Llm.avg_ms("rat") / 1000.0, int(Llm.stats.siedler[0]), Llm.avg_ms("siedler") / 1000.0])
	L.append(tr("Spielgeschwindigkeit %d, Zeit wartet auf die KI: %s%s") % [Game.speed, "an" if brake else "aus", tr(" (bremst gerade)") if braking else ""])
	L.append(tr("Alter der Antworten in Spielstunden: Siedler %.1f, Ratssitzung %.1f, alle Siedler einmal %.1f. Verworfene Siedler-Antworten (veraltet): %d") % [
		float(lag.siedler), float(lag.rat), float(lag.runde), traces.filter(func(e): return str(e.topic).ends_with("(verworfen)")).size()])
	L.append(tr("Festgehalten: %d Einträge seit dem Start (die letzten %d hier, volle Anfragetexte nur bei den letzten %d).") % [trace_count, traces.size(), TRACE_FULL])
	L.append("")
	L.append(tr("Lesehilfe: Klarheit 1,0 heißt, alle Möglichkeiten waren dem Modell gleich lieb (Würfeln). Klarheit = höchste Wahrscheinlichkeit mal Anzahl der Möglichkeiten; unter %.2f gilt das Modell als unentschlossen. Nummernanteil = wie sehr das Modell überhaupt mit einer Nummer antworten wollte. Siedler werden zweimal gefragt (A: normale Reihenfolge, B: umgekehrt), gezählt wird der Mittelwert.") % float(cfg("undecided_clarity", 1.35)))
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
		L.append(tr("== Zusammenfassung %s: %d Auswahlentscheidungen ==") % [tr("Siedler (SmolLM)") if role == "siedler" else tr("Rat"), ch.size()])
		L.append(tr("Unentschlossen: %d (%s), mittlere Klarheit %.2f, mittlerer Nummernanteil %s") % [und, _pct(und / n), clar / n, _pct(mass / n)])
		if role == "siedler":
			L.append(tr("Nummer 1 am liebsten: in A %s, in B %s (stark über 1/Anzahl heißt: das Modell nimmt einfach die erste Nummer)") % [_pct(first_a / n), _pct(first_b / n)])
			L.append(tr("A und B einig über die beste Arbeit: %s. Gegen den Auftrag entschieden: %d") % [_pct(agree / n), own])
		L.append("")
	# Gedächtnis der Räte
	for i in Sea.settled_islands():
		var w = Sea.worlds.get(i)
		if w == null or not is_instance_valid(w):
			continue
		var m := mem(w)
		L.append(tr("== Insel %s ==") % Sea.island_name(w))
		L.append(tr("Schwerpunkt: %s, Plan: %s") % [Society.strat_name(m.focus), m.plan])
		L.append(tr("Anteile Arbeit: %s") % JSON.stringify(m.shares))
		L.append(tr("Vorgaben: %s, Prioritäten: %s") % [JSON.stringify(m.binding), JSON.stringify(m.prios)])
		for l in m.lessons:
			L.append(tr("Lehre (Tag %d, %s): %s") % [int(float(l[0])) + 1, l[2], l[1]])
		for e in experience_lines(w, 20):
			L.append(tr("Erfahrung: %s") % e)
		for r in m.records:
			L.append(tr("Entscheidung: %s") % record_text(r))
		for c in m.chat:
			L.append(tr("Gespräch %s: %s") % [c[0], c[1]])
		L.append("")
	# Verlauf
	L.append(tr("== Verlauf aller Anfragen (älteste zuerst) =="))
	for e in traces:
		L.append("")
		L.append("#%d  Tag %d %02d:%02d (Uhr %s)  %s, %s: %s" % [int(e.n), int(floor(float(e.day))) + 1, int(fmod(float(e.day), 1.0) * 24.0),
			int(fmod(float(e.day) * 24.0, 1.0) * 60.0), e.clock, e.isl, e.who, e.topic])
		if e.has("probs"):
			if e.has("order"):
				L.append(tr("Auftrag des Rats: %s") % (e.order if str(e.order) != "" else "keiner"))
			L.append(tr("Möglichkeiten und Wahrscheinlichkeit: %s") % _plist(e.options, e.probs))
			if e.has("probs_a"):
				L.append(tr("  A (normale Reihenfolge): %s") % _plist(e.options, e.probs_a))
				var rb := []
				for k in e.probs_b.size():
					rb.append(e.probs_b[e.probs_b.size() - 1 - k])
				L.append(tr("  B (umgekehrt gefragt, zurückgeordnet): %s") % (_plist(e.options, rb) if not rb.is_empty() else tr("keine Antwort")))
			L.append(tr("Klarheit %.2f, Nummernanteil %s, liebstes Wort: %s, Rechenzeit %d ms%s") % [float(e.clarity), JSON.stringify(e.mass), JSON.stringify(e.top), int(float(e.ms)),
				tr(", Antwort kam %.1f Spielstunden nach der Frage") % float(e.age_h) if e.has("age_h") else ""])
			L.append(tr("Entscheidung: %s (%s)%s") % [str(e.choice).split(":")[0], tr(str(e.rule)), tr(", gegen den Auftrag") if e.get("own", false) else ""])
		if e.has("text"):
			L.append(tr("Antwort: %s  (%d ms)") % [e.text, int(float(e.get("ms", 0.0)))])
		if e.has("prompt"):
			L.append(tr("--- Anfrage ---"))
			L.append(str(e.prompt))
			if e.has("prompt2"):
				L.append(tr("--- Anfrage B (Frageteil) ---"))
				L.append(str(e.prompt2))
			L.append(tr("--- Ende ---"))
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
