extends Node
## Verwalter-Steuerung der Berufe (josh 2026-10-17, neu gedacht 2026-10-29, nur Version 2): Es gibt nur einen
## Verwalter, den Siedler in der Verwaltung. Seit josh 2026-11-07 hat er nur noch die Befugnisse Nachbesetzen
## (Admin) und Auslastung (hier). Er arbeitet je Insel: auf der Insel der Verwaltung und auf Inseln am Funknetz
## (Rundfunkanstalt auf beiden Inseln, Powers.covers). Auslastung je Insel alle TICK_DAYS:
##   - weniger als FEW_ADULTS Erwachsene: einmal Meldung, alle (außer Verwalter und Seeleute) werden der Reihe nach
##     Holzfäller, Fischer, Sammler; danach teilt er nicht mehr ein, bis wieder genug Erwachsene da sind.
##   - immer mindestens ein Baumeister und ein Fischer (der Verwalter wird vom Spiel immer nachbesetzt).
##   - seit josh 2026-11-14 Verteilung nach Bedarf (balance, raw_wants, targets weiter unten) statt nur nach
##     Auslastung: Soll je Beruf aus dem, was es zu tun gibt; Essen und Brennholz zuerst; unter LOAD_LOW %
##     Auslastung einer weniger. idle_tick (Freie der Reihe nach probieren) wird nicht mehr aufgerufen.
##   - nach einem Wechsel in einem Beruf wartet er LOAD_DAYS, bis die Auslastung neu gemessen ist.

signal offer(kind: String)  # Hud zeigt ein Fenster (nur noch für die Geschichte der KI)
signal changed

const TICK_DAYS := 0.25
const MOVE_DAYS := 0.25
const PROTECT := ["verwalter", "seemann"]  # nie umbesetzt oder freigestellt
const KEEP_DAYS := 2.0
const PLAN_DAYS := 3.0  # Essen und Wärme für so viele Tage sichern
const FREE_DAYS := 1.0  # so lange darf ein Siedler frei bleiben, dann teilt ihn der Verwalter ein
const KIND_JOB := {"kueche": "koch", "handwerk": "handwerker", "stein": "steinmetz", "stall": "bauer"}
## Rohstoffe und wer sie holt (Werkstattwaren findet _producer über die Gebäude)
const RAW_JOB := {"holz": "holzfaeller", "stein": "steinmetz", "beeren": "sammler", "pilze": "sammler",
	"kokos": "sammler", "fisch": "fischer", "weizen": "bauer", "aepfel": "bauer", "fleisch": "jaeger", "felle": "jaeger"}
const FOOD_JOBS := ["bauer", "fischer", "sammler", "jaeger"]
## Berufe, die der Verwalter nie umbesetzt
const KEEP := ["verwalter", "seemann", "baumeister", "forscher"]
const FIELDS_PER_FARMER := 4
const WOOD_RATE := 10.0  # Holz je Holzfäller und Tag, bis gemessen ist
const MAX_POP := 60  # nur noch für alte Anzeigen (Rechenautomat)

var on := false        # alte Spielstände (früher Schalter); gesteuert wird über die Befugnisse
var offered := false
var offered_routes := false
var _next := 0.0
var _moved: Dictionary = {}       # Insel-ID -> Tag des letzten Wechsels
var _free_since: Dictionary = {}  # Siedler-ID -> Tag, seit dem er frei ist
var _day_stats: Dictionary = {}   # Insel-ID -> {day, start: {holz, kohle, food}, made: {...}, prev: {used_fuel, used_food, made_food, made_holz, food_w, wood_w}}
var research_info := ""
var _old_blocks: Dictionary = {}
var _few: Dictionary = {}   # Insel-ID -> true: weniger als FEW_ADULTS, schon gemeldet und eingeteilt
var _job_moved: Dictionary = {}  # "Insel-ID:Beruf" -> Tag des letzten Wechsels in oder aus diesem Beruf
## Auslastung (josh 2026-11-07)
const LOAD_LOW := 80.0
const LOAD_HIGH := 90.0
const LOAD_DAYS := 1.0
const FEW_ADULTS := 7
const ALWAYS := ["baumeister", "fischer"]  # dazu der Verwalter (Admin besetzt ihn immer nach)
const FEW_ORDER := ["holzfaeller", "fischer", "sammler"]
## Freie bekommen einen Beruf, der Reihe nach (josh 2026-11-07); nach LOAD_DAYS prüft er, ob es klappt (Anteil im
## Beruf mindestens LOAD_LOW), sonst wird der Siedler wieder frei und probiert den nächsten.
const IDLE_ORDER := ["bauer", "sammler", "fischer", "koch", "handwerker", "steinmetz", "holzfaeller", "foerster", "jaeger", "forscher"]  # Steinmetz nach Handwerker, Förster und Jäger dazu (josh 2026-11-07 18:43/18:49)
const IDLE_PER_ROUND := 3
const IDLE_RETRY_DAYS := 2.0  # alle Berufe probiert: so lange frei, dann wieder von vorn
var blocks: Dictionary = {}  # Insel-ID -> {Ware oder Beruf: Text}: Engpässe, die Leute nicht beheben (Lieferkette, Natur)


func _ready() -> void:
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)


# ---------------------------------------------------------------- Abfragen
## Gibt es schon eine Verwaltung (für Anzeigen)?
func unlocked() -> bool:
	return Admin.office() != null


## Arbeitet der Verwalter (Verwaltung mit Verwalter, oder die KI)?
func active() -> bool:
	return Admin.level() >= 1 or AiRule.ki()


## Steuert der Verwalter diese Insel? "" = ja, sonst der Grund.
func blocked_on(w) -> String:
	if w == null or not is_instance_valid(w):
		return "?"
	if Powers.covers(w):
		return ""
	if Admin.level() < 1:
		return tr("Keine Verwaltung mit Verwalter.")
	return tr("Nur mit einer Rundfunkanstalt auf dieser Insel und auf der Insel der Verwaltung.")


## Früherer Schalter: jetzt nur noch für die KI-Geschichte.
func set_on(v: bool) -> void:
	on = v
	changed.emit()


func locked(s) -> bool:
	return not JobDesk.may(s, "verwalter")


# ---------------------------------------------------------------- Ablauf
func _process(_delta: float) -> void:
	if Game.world == null or Game.speed == 0:
		return
	if Game.time_days < _next:
		return
	_next = Game.time_days + TICK_DAYS
	for w in Sea.all_worlds():
		_note_day(w)
	if not active():
		return
	for w in Sea.all_worlds():
		if blocked_on(w) == "":
			tick(w)
	if net_active() and Game.time_days >= _net_next:
		_net_next = Game.time_days + ROUTE_TICK
		net_tick()


func tick(w) -> void:
	if AiRule.si() or (AiRule.ki() and not Sea.is_main(w) and AiRule.automated(w)):
		return  # Superintelligenz: Menschen sind ihr egal; automatisierte Inseln brauchen keine Siedler mehr
	_track_free(w)
	var iid := int(w.island_id)
	if Game.time_days - float(_moved.get(iid, -99.0)) < MOVE_DAYS:
		return
	_moved[iid] = Game.time_days
	if KiBrain.controls(w):
		return  # Berufe vergibt die lernende KI (josh 2026-11-07)
	load_tick(w)


# ---------------------------------------------------------------- Auslastung (josh 2026-11-07)
## Eine Runde Auslastung auf der Insel w (siehe Kopf der Datei).
func load_tick(w) -> void:
	if not Powers.on("auslastung"):
		return
	var iid := int(w.island_id)
	var adults := _adults(w)
	if adults.size() < FEW_ADULTS:
		if not _few.get(iid, false):
			_few[iid] = true
			_few_staff(w, adults)
		return
	_few.erase(iid)
	var budget := 1 + adults.size() / 10
	# 1. immer ein Baumeister und ein Fischer
	for job in ALWAYS:
		if budget <= 0:
			return
		if not Data.job_unlocked(job) or _count(w, job) >= 1:
			continue
		var pick = _free_for(w, job)
		if pick == null:
			pick = _from_lowest(w, job)
		if pick != null and _move(w, pick, job, tr("es muss immer einen %s geben") % Data.jobs[job].name):
			budget -= 1
	# 2. Verteilung nach Bedarf (josh 2026-11-14), siehe balance
	balance(w, budget)


# ---------------------------------------------------------------- Verteilung nach Bedarf (josh 2026-11-14)
## josh: „Teile die Berufsgruppen so zu den Aufgaben ein, dass eine gewisse Ausgewogenheit entsteht.“
## Für jeden Beruf wird gezählt, wie viele Leute er gerade sinnvoll beschäftigen kann (raw_wants): Baustellen,
## Brennholz bis zum Winterende plus gemessener Holzverbrauch, Felder (weniger, wenn genug Getreide liegt) und
## Ställe, Werkstätten und Küchen, die arbeiten können (Zutaten da, Lager nicht voll), reife Fundstellen,
## Forschungsplätze. Reichen die Erwachsenen nicht, bekommt jeder Beruf seinen Anteil (targets). Ein Beruf, der
## gemessen unter LOAD_LOW % ausgelastet ist, braucht einen weniger. balance() versetzt je Runde wenige Leute:
## Freie in den Beruf mit der größten Lücke, sonst vom Beruf mit dem größten Überhang dorthin.
const WANT_JOBS := ["baumeister", "holzfaeller", "bauer", "sammler", "fischer", "koch", "handwerker", "steinmetz",
	"foerster", "jaeger", "forscher"]
const GRAIN_PER_HEAD := 25    # so viel Getreide je Siedler gilt als genug: dann nur noch ein Drittel der Bauern
const FOOD_SAFE_DAYS := 8.0   # so viele Tage Essen im Lager: Sammler und Fischer nur noch als Grundbesetzung
var _want_avg: Dictionary = {}  # "Insel-ID:Beruf" -> geglätteter Bedarf
const FIRST := ["bauer", "koch", "fischer", "sammler", "holzfaeller"]  # Essen und Brennholz gehen vor


## Plätze in Werkstätten dieser Art, die gerade arbeiten können (besetzt oder ohne Hindernis).
func _workable(w, kind: String) -> int:
	var n := 0
	for b in w.buildings:
		if not b.complete or b.paused or not b.def.has("production") or b.prod_def().get("job", "") != kind:
			continue
		if not b.occupants.is_empty() or b.prod_blocker() == "":
			n += maxi(1, b.slots())
	return n


## Bedarf je Beruf ohne Rücksicht darauf, wie viele Erwachsene es gibt.
func raw_wants(w) -> Dictionary:
	var want := {}
	var prev: Dictionary = _day_stats.get(int(w.island_id), {}).get("prev", {})
	var sites: int = w.buildings.filter(func(b): return not b.complete and str(b.def.get("builder", "")) != "foerster").size()
	want["baumeister"] = 1 + sites / 4
	# Holz: Brennstoff bis zum Winterende, gemessener Verbrauch, Werkstätten, die auf Holz warten
	var hw := 0
	if int(_ripe(w, ["baum"])[0]) >= RIPE_MIN:
		var gap := maxf(0.0, Extras.heat_reserve(w, true) - Extras.fuel(w))
		var s := Seasons.season()
		var days_left := maxf(1.0, (1.0 - Seasons.season_progress()) * Seasons.season_days() + float(maxi(0, 2 - s)) * Seasons.season_days())
		var waiting := 0
		for b in w.buildings:
			if b.complete and not b.paused and b.def.has("production"):
				var need := int(b.prod_def().get("inputs", {}).get("holz", 0))
				if need > 0 and Game.usable("holz", w) < need:
					waiting += 1
		hw = maxi(1, ceili((float(prev.get("used_fuel", 0.0)) + gap / days_left) / wood_rate(w)) + ceili(waiting / 3.0))
		if Game.space_for("holz", w) <= 0:
			hw = 1
	want["holzfaeller"] = hw
	# Essen
	var food_days := _food_sat(w) / maxf(1.0, food_per_day(w))
	var grain_ok: bool = Game.amount("weizen", w) >= GRAIN_PER_HEAD * w.settlers.size() or Game.space_for("weizen", w) <= 0
	var fields := 0.0
	for b in w.buildings:
		if b.complete and b.def.has("farm") and Seasons.growth(str(b.type), w) > 0.0:
			var y := str(b.def.farm.get("yield", ""))
			if Game.space_for(y, w) > 0:
				fields += (1.0 / 3.0) if (y == "weizen" and grain_ok) else 1.0
	want["bauer"] = ceili(fields / FIELDS_PER_FARMER) + _workable(w, "stall")
	var wild := 0
	for t in RAW_NODES["sammler"]:
		if Seasons.growth(str(t), w) > 0.0:
			wild += int(_ripe(w, [t])[0])
	var fish := int(_ripe(w, ["fischgrund"])[0])
	want["sammler"] = mini(ceili(wild / 9.0), 1 if food_days >= FOOD_SAFE_DAYS else 99)
	want["fischer"] = maxi(1, mini(ceili(fish / 9.0), 1 if food_days >= FOOD_SAFE_DAYS else 99))
	want["koch"] = _workable(w, "kueche")
	want["handwerker"] = _workable(w, "handwerk")
	var rocks := int(_ripe(w, RAW_NODES["steinmetz"])[0])
	want["steinmetz"] = _workable(w, "stein") + (1 if rocks >= RIPE_MIN and Game.space_for("stein", w) > 0 else 0)
	# Förster nur, wenn der Spieler ihm Arbeit gegeben hat (Pflanzplätze, Rodungen)
	var forest: int = w.buildings.filter(func(b): return not b.complete and str(b.def.get("builder", "")) == "foerster").size() \
		+ w.nodes.filter(func(n): return is_instance_valid(n) and n.clear_mark).size()
	want["foerster"] = ceili(forest / 8.0)
	want["jaeger"] = maxi(1, w.animals.size() / 3) if _raw_block(w, "jaeger") == "" else 0
	var slots := 0
	if Sea.is_main(w) and Game.research.current != "":
		for b in w.buildings:
			if b.complete and b.def.has("research"):
				slots += int(b.def.research.get("slots", 1))
	want["forscher"] = slots
	# Not: Essen für weniger als PLAN_DAYS Tage oder Brennstoff unter der Winterreserve zählt anderthalbfach
	if food_days < PLAN_DAYS:
		for j in ["bauer", "sammler", "fischer", "koch"]:
			want[j] = ceili(int(want[j]) * 1.5)
	if Extras.fuel(w) < Extras.heat_reserve(w) or Seasons.cold.has(w):
		want["holzfaeller"] = ceili(int(want["holzfaeller"]) * 1.5) + (1 if hw > 0 else 0)
	for j in want.keys():
		if not Data.jobs.has(j) or not Data.job_unlocked(j):
			want.erase(j)
	return want


## Soll je Beruf: der geglättete Bedarf, bei zu wenigen Erwachsenen anteilig gekürzt (jeder nötige Beruf behält
## mindestens einen). n = Erwachsene, die der Verwalter einteilen darf.
func targets(w, n: int) -> Dictionary:
	var raw := raw_wants(w)
	var load := Admin.job_load(w)
	var want := {}
	var sum := 0.0
	for j in raw:
		var key := "%d:%s" % [int(w.island_id), j]
		var v := float(raw[j])
		# wenig ausgelastet: einer weniger als jetzt genügt
		if load.has(j) and int(load[j][1]) >= 0 and int(load[j][1]) < LOAD_LOW and _settled(w, j):
			v = minf(v, maxf(float(1 if j in ALWAYS else 0), float(_count(w, j)) - 1.0))
		var avg := lerpf(float(_want_avg.get(key, v)), v, 0.4)
		_want_avg[key] = avg
		want[j] = avg
		sum += avg
	var out := {}
	if sum <= float(n) or sum <= 0.0:
		for j in want:
			out[j] = roundi(float(want[j]))
		return out
	# Zu wenige Erwachsene: erst Essen und Brennholz (FIRST), dann der Rest anteilig. Jeder nötige Beruf behält
	# einen Platz, solange Leute da sind; gekürzt wird von hinten (TRIM_ORDER).
	var left := n
	for group in [want.keys().filter(func(j): return j in FIRST), want.keys().filter(func(j): return not j in FIRST)]:
		var gsum := 0.0
		for j in group:
			gsum += float(want[j])
		if gsum <= 0.0 or left <= 0:
			for j in group:
				out[j] = 0
			continue
		var k := minf(1.0, float(left) / gsum)
		var used := 0
		var rest := []
		for j in group:
			var share := float(want[j]) * k
			out[j] = floori(share)
			used += floori(share)
			rest.append([share - floorf(share), j])
		rest.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
		for e in rest:
			if used >= mini(left, roundi(gsum)):
				break
			out[e[1]] = int(out[e[1]]) + 1
			used += 1
		left -= used
	return out


## Für Anzeige und Tests: Soll und Ist je Beruf.
func balance_info(w) -> Dictionary:
	var movable := _adults(w).filter(func(s): return not s.job in PROTECT and not JobDesk.player_controlled(s))
	var t := targets(w, movable.size())
	var out := {}
	for j in t:
		out[j] = [int(t[j]), _count(w, j)]
	return out


## Eine Runde: höchstens budget Wechsel hin zum Soll.
func balance(w, budget: int) -> void:
	var movable := _adults(w).filter(func(s): return not s.job in PROTECT and not JobDesk.player_controlled(s))
	var t := targets(w, movable.size())
	var mine := func(s): return JobDesk.may(s, "verwalter") or JobDesk.holder(s) == "verwalter"
	while budget > 0:
		var short := ""
		var short_n := 0
		var over := ""
		var over_n := 0
		for j in t:
			var d := _count(w, j) - int(t[j])
			if d < short_n:
				short = j
				short_n = d
			if d > over_n and movable.any(func(s): return s.job == j and mine.call(s)):
				over = j
				over_n = d
		if short == "":
			# Nirgends fehlt jemand: aus einem Beruf mit deutlich zu vielen Leuten wird einer frei (Freie helfen
			# beim Bauen und Tragen), statt Waren zu häufen, die niemand braucht
			if over != "" and over_n >= 2:
				var extra := movable.filter(func(s): return s.job == over and mine.call(s) \
					and Game.time_days - float(s.get_meta("adm_moved", -99.0)) >= KEEP_DAYS)
				extra.sort_custom(func(x, y): return _idle(x) > _idle(y))
				if not extra.is_empty() and _move(w, extra[0], "frei", tr("Bedarf: %d %s genügen, %d da") % [int(t[over]), Data.jobs[over].name, _count(w, over)]):
					budget -= 1
					continue
			return
		var free := movable.filter(func(s): return s.job == "frei" and mine.call(s))
		var pick = _pick(w, free, short) if not free.is_empty() else null
		var why := tr("Bedarf: %d %s nötig, %d da") % [int(t[short]), Data.jobs[short].name, _count(w, short)]
		if pick == null:
			if over == "":
				return
			var cands := movable.filter(func(s): return s.job == over and mine.call(s) \
				and Game.time_days - float(s.get_meta("adm_moved", -99.0)) >= KEEP_DAYS)
			if cands.is_empty():
				return
			pick = _pick(w, cands, short)
			why += tr(", %s hat %d zu viel") % [Data.jobs[over].name, over_n]
		if pick == null or not _move(w, pick, short, why):
			return
		budget -= 1


## Freie einteilen und Versuche prüfen (josh 2026-11-07): Wer frei ist (auch vom Spieler freigestellt), bekommt
## den nächsten Beruf aus IDLE_ORDER, in dem es gerade Arbeit gibt. Nach LOAD_DAYS: arbeitet er weniger als
## LOAD_LOW % im Beruf, wird er frei und probiert den nächsten. Nach dem letzten wartet er IDLE_RETRY_DAYS.
func idle_tick(w) -> void:
	# Versuche prüfen
	for s in _adults(w):
		if not s.has_meta("try_job"):
			continue
		if s.job != str(s.get_meta("try_job")):  # inzwischen anders eingeteilt
			s.remove_meta("try_job")
			continue
		if Game.time_days - float(s.get_meta("try_at", 0.0)) < LOAD_DAYS:
			continue
		var sh: Array = s.busy_shares()
		s.remove_meta("try_job")
		if sh.is_empty() or float(sh[0]) >= LOAD_LOW:
			s.set_meta("try_idx", 0)  # klappt: beim nächsten Mal wieder von vorn
			continue
		var job: String = s.job
		_move(w, s, "frei", tr("als %s nur %d %% beschäftigt, probiert den nächsten Beruf") % [Data.jobs[job].name, roundi(float(sh[0]))])
		s.set_meta("try_idx", IDLE_ORDER.find(job) + 1)
	# Freie einteilen
	var n := 0
	for s in _adults(w):
		if n >= IDLE_PER_ROUND:
			break
		if s.job != "frei" or not (JobDesk.may(s, "verwalter") or JobDesk.holder(s) == "verwalter"):
			continue
		if Game.time_days < float(s.get_meta("try_wait", -1.0)):
			continue
		var i := int(s.get_meta("try_idx", 0))
		var job := ""
		while i < IDLE_ORDER.size():
			if _idle_job_ok(w, str(IDLE_ORDER[i])):
				job = str(IDLE_ORDER[i])
				break
			i += 1
		if job == "":
			s.set_meta("try_idx", 0)
			s.set_meta("try_wait", Game.time_days + IDLE_RETRY_DAYS)
			continue
		if _move(w, s, job, tr("war frei, Versuch %d von %d") % [i + 1, IDLE_ORDER.size()]):
			s.set_meta("try_job", job)
			s.set_meta("try_at", Game.time_days)
			s.set_meta("try_idx", i + 1)
			n += 1


## Gibt es in dem Beruf gerade Arbeit und Platz? (Forschung, Werkstattplätze, Natur, Felder)
func _idle_job_ok(w, job: String) -> bool:
	if not Data.jobs.has(job) or not Data.job_unlocked(job):
		return false
	match job:
		"koch":
			return _count(w, job) < _workplaces(w, "kueche")
		"handwerker":
			return _count(w, job) < _workplaces(w, "handwerk")
		"forscher":
			if not Sea.is_main(w) or Game.research.current == "":
				return false
			var slots := 0
			for b in w.buildings:
				if b.complete and b.def.has("research"):
					slots += int(b.def.research.get("slots", 1))
			return _count(w, job) < slots
		"foerster":  # einer je zwei Holzfäller, mindestens einer
			return _count(w, job) < maxi(1, ceili(_count(w, "holzfaeller") / 2.0))
		"jaeger":  # Tiere da, einer je drei Tiere, mindestens einer
			return _raw_block(w, job) == "" and _count(w, job) < maxi(1, w.animals.size() / 3)
		"bauer":
			if _raw_block(w, job) != "":
				return false
			var fields: int = w.buildings.filter(func(b): return b.complete and b.def.has("farm")).size()
			return _count(w, job) < ceili(float(fields) / FIELDS_PER_FARMER) + _workplaces(w, "stall")
	return _raw_block(w, job) == ""


## Weniger als FEW_ADULTS Erwachsene: Meldung und einmal Holzfäller, Fischer, Sammler der Reihe nach.
func _few_staff(w, adults: Array) -> void:
	var order: Array = FEW_ORDER.filter(func(j): return Data.jobs.has(j) and Data.job_unlocked(j))
	var txt := tr("Auf %s leben nur %d Erwachsene, zu wenige, um die Berufe zu steuern. Der Verwalter teilt Holzfäller, Fischer und Sammler ein und hört dann auf, bis es wieder %d sind.") % [Sea.island_name(w), adults.size(), FEW_ADULTS]
	Game.notify(who() + ": " + txt, "person", "verwaltung")
	Admin.add_log(who() + ": " + txt)
	if order.is_empty():
		return
	var list := adults.filter(func(s): return not s.job in PROTECT)
	list.sort_custom(func(x, y): return int(x.id) < int(y.id))
	var i := 0
	for s in list:
		var job: String = order[i % order.size()]
		i += 1
		if s.job != job:
			JobDesk.assign(s, job, "verwalter", KEEP_DAYS, true)
			Powers.count("job")


## Ein Freier für den Beruf (der Geübteste, der nah wohnt), oder null.
func _free_for(w, job: String):
	# Wen er selbst freigestellt hat, darf er gleich wieder einteilen (nur Spieler, Automat und KI halten fest)
	var free := _adults(w).filter(func(s): return s.job == "frei" and (JobDesk.may(s, "verwalter") or JobDesk.holder(s) == "verwalter"))
	if free.is_empty():
		return null
	return _pick(w, free, job)


## Niemand frei: einen aus dem am wenigsten ausgelasteten Beruf holen (nicht Verwalter, Seeleute, nicht den letzten
## Baumeister oder Fischer).
func _from_lowest(w, job: String):
	var load := Admin.job_load(w)
	var best := ""
	for j in load:
		if j == job or j in PROTECT or j == "frei" or int(load[j][1]) < 0:
			continue
		if j in ALWAYS and _count(w, j) <= 1:
			continue
		if best == "" or int(load[j][1]) < int(load[best][1]):
			best = j
	if best == "":
		return null
	var cands := _adults(w).filter(func(s): return s.job == best)
	return _pick(w, cands, job) if not cands.is_empty() else null


## Wechsel ausführen (über die Befugnis Auslastung: Log und Tagesbilanz).
func _move(w, s, job: String, why: String) -> bool:
	var iid := int(w.island_id)
	var old: String = s.job
	var text := tr("%s arbeitet jetzt als %s (%s, vorher %s).") % [s.display_name, Data.jobs[job].name, why, s.job_name()] if job != "frei" \
		else tr("%s ist jetzt frei (%s).") % [s.display_name, why]
	if Sea.worlds.size() > 1:
		text = Sea.island_name(w) + ": " + text
	var act := {"kind": "job", "island": iid, "sid": int(s.id), "job": job, "force": true}
	if not Powers.decide("auslastung", "job:%d:%s" % [iid, job], text, act):
		return false
	s.set_meta("adm_moved", Game.time_days)
	if job == "frei" and old in IDLE_ORDER:  # beim Einteilen der Freien mit dem nächsten Beruf weitermachen
		s.set_meta("try_idx", IDLE_ORDER.find(old) + 1)
	_job_moved["%d:%s" % [iid, old]] = Game.time_days
	_job_moved["%d:%s" % [iid, job]] = Game.time_days
	return true


## Ist die Auslastung des Berufs seit dem letzten Wechsel neu gemessen?
func _settled(w, job: String) -> bool:
	return Game.time_days - float(_job_moved.get("%d:%s" % [int(w.island_id), job], -99.0)) >= LOAD_DAYS


func _idle(s) -> float:
	var sh: Array = s.busy_shares()
	return float(sh[2]) if not sh.is_empty() else 0.0


## Wer ist seit wann frei? (für „einen Tag frei, dann teilt der Verwalter ein“)
func _track_free(w) -> void:
	if _free_since.size() > 400:  # Einträge Verstorbener entfernen
		var alive: Dictionary = Game.living_ids()
		for k in _free_since.keys():
			if not alive.has(int(k)):
				_free_since.erase(k)
	for s in _adults(w):
		if s.job == "frei":
			if not _free_since.has(int(s.id)):
				_free_since[int(s.id)] = Game.time_days
		else:
			_free_since.erase(int(s.id))


func free_days(s) -> float:
	if not _free_since.has(int(s.id)):
		return 0.0
	return Game.time_days - float(_free_since[int(s.id)])


# ---------------------------------------------------------------- Bedarf messen (josh 2026-10-29)
## Je Insel und Tag: Bestand am Tagesanfang und erzeugte Mengen; daraus der Verbrauch des Vortags
## (Bestand vorher + erzeugt - Bestand nachher). Er enthält Heizen, Werkstätten und Baustellen.
func _note_day(w) -> void:
	var iid := int(w.island_id)
	var day := int(floor(Game.time_days))
	var st: Dictionary = _day_stats.get(iid, {})
	var fuel := float(Game.amount("holz", w)) + 2.0 * float(Game.amount("kohle", w))
	var food := _food_sat(w)
	if st.is_empty():
		_day_stats[iid] = {"day": day, "fuel": fuel, "food": food, "made": {}, "prev": {}}
		return
	if int(st.day) == day:
		return
	var made: Dictionary = st.made
	var mf := float(made.get("food", 0.0))
	var mh := float(made.get("fuel", 0.0))
	var days := maxf(1.0, float(day - int(st.day)))
	st.prev = {"used_fuel": maxf(0.0, float(st.fuel) + mh - fuel) / days, "used_food": maxf(0.0, float(st.food) + mf - food) / days,
		"made_food": mf / days, "made_fuel": mh / days,
		"food_w": _busy_workers(w, FOOD_JOBS), "wood_w": _busy_workers(w, ["holzfaeller"])}
	st.day = day
	st.fuel = fuel
	st.food = food
	st.made = {}


## Settler meldet erzeugte Waren (über Admin.note_produced).
func note_made(res: String, n: int, w) -> void:
	if w == null or not is_instance_valid(w):
		return
	var st: Dictionary = _day_stats.get(int(w.island_id), {})
	if st.is_empty():
		return
	if Data.food_ids().has(res):
		st.made["food"] = float(st.made.get("food", 0.0)) + n * Data.food_satiety(res)
	elif res == "holz":
		st.made["fuel"] = float(st.made.get("fuel", 0.0)) + n
	elif res == "kohle":
		st.made["fuel"] = float(st.made.get("fuel", 0.0)) + 2.0 * n


## Arbeiter in diesen Berufen, gewichtet mit dem Anteil, in dem sie wirklich arbeiten (Leerlauf zählt nicht).
## So steigt der gemessene Ertrag je Arbeiter nicht künstlich, wenn viele nichts zu tun haben.
func _busy_workers(w, jobs: Array) -> float:
	var n := 0.0
	for s in _adults(w):
		if s.job in jobs:
			n += 1.0 - _idle(s) / 100.0
	return n


func _food_sat(w) -> float:
	var sat := 0.0
	for id in Data.food_ids():
		# Frisches verdirbt (im Sommer schnell): zählt für die nächsten Tage nur zum Teil (josh 2026-10-30)
		var keep := clampf(1.0 - Seasons.spoil_rate(id) * PLAN_DAYS * 0.5, 0.2, 1.0)
		sat += float(Game.amount(id, w)) * Data.food_satiety(id) * keep
	return sat


func _count_food_workers(w) -> int:
	var n := 0
	for j in FOOD_JOBS:
		n += _count(w, j)
	return n


## Sättigung, die ein Erwachsener am Tag braucht.
func _need_per_head(w) -> float:
	return float(Data.bal("hunger_per_day")) * Game.eff("hunger") * Seasons.hunger_mult(w)


## Essen am Tag (Sättigung) für alle Siedler, mindestens der gemessene Verbrauch des Vortags.
func food_per_day(w) -> float:
	var est := _need_per_head(w) * float(w.settlers.size())
	var prev: Dictionary = _day_stats.get(int(w.island_id), {}).get("prev", {})
	# Gemessen zählt auch Getreide, das Mühle und Ställe verarbeiten, als "gegessen": höchstens 30 % über dem
	# Bedarf der Siedler (josh 2026-11-01: der Verwalter sah Hunger bei 9 Tagen Vorrat und zog Forscher ab)
	return maxf(est, minf(float(prev.get("used_food", 0.0)) * 0.9, est * 1.3))


## Brennstoff am Tag (Holz, Kohle doppelt): Heizen der Siedler in der kältesten Jahreszeit der nächsten
## PLAN_DAYS Tage, mindestens der gemessene Verbrauch des Vortags (Häuser, Werkstätten, Baustellen).
func fuel_per_day(w) -> float:
	var heat := 0.0
	for d in [0.0, PLAN_DAYS]:
		heat = maxf(heat, Seasons.heat_per_settler(Seasons.season(Game.time_days + d)))
	# Nur Heizen: was Werkstätten an Holz brauchen, rechnet der Stellenplan (StaffPlan) dazu
	return heat * float(w.settlers.size())


## Ertrag je Arbeiter und Tag (gemessen am Vortag, sonst Schätzung).
func food_rate(w) -> float:
	var base := 1.5 * _need_per_head(w)  # ein Sammler ernährt etwa anderthalb Erwachsene
	var prev: Dictionary = _day_stats.get(int(w.island_id), {}).get("prev", {})
	if float(prev.get("food_w", 0)) > 0.5 and float(prev.get("made_food", 0.0)) > 0.0:
		return maxf(base * 0.4, float(prev.made_food) / float(prev.food_w))
	return base


func wood_rate(w) -> float:
	var prev: Dictionary = _day_stats.get(int(w.island_id), {}).get("prev", {})
	if float(prev.get("wood_w", 0)) > 0.5 and float(prev.get("made_fuel", 0.0)) > 0.0:
		return maxf(WOOD_RATE * 0.4, float(prev.made_fuel) / float(prev.wood_w))
	return WOOD_RATE


## Wie viele Arbeiter braucht es, damit Vorrat plus Ertrag den Bedarf der nächsten PLAN_DAYS Tage decken?
## Liegt mehr als doppelt so viel im Lager, braucht es im Moment keine.
static func workers_for(per_day: float, stock: float, rate: float) -> int:
	if per_day <= 0.0:
		return 0
	var need := per_day * PLAN_DAYS
	if stock >= 2.0 * need:
		return 0
	var refill := ceili(maxf(0.0, need - stock) / (PLAN_DAYS * maxf(rate, 0.01)))
	var keep := ceili(per_day / maxf(rate, 0.01))
	return maxi(refill, keep)


## Für die Anzeige: [Bedarf 3 Tage, Vorrat, Arbeiter nötig, Arbeiter da] je "food" und "fuel".
func secure_info(w) -> Dictionary:
	var fpd := food_per_day(w)
	var fs := _food_sat(w)
	var hpd := fuel_per_day(w) if _cold_season() or Seasons.season(Game.time_days + PLAN_DAYS) != Seasons.season() else 0.0
	var hs := float(Game.amount("holz", w)) + 2.0 * float(Game.amount("kohle", w))
	return {"food": [fpd * PLAN_DAYS, fs, workers_for(fpd, fs, food_rate(w)), _count_food_workers(w)],
		"fuel": [hpd * PLAN_DAYS, hs, workers_for(hpd, hs, wood_rate(w)), _count(w, "holzfaeller")]}


# ---------------------------------------------------------------- Was braucht die Insel?
## Gefahr (josh 2026-10-30): erwachsene Wölfe, Eber oder Bären bis 8 Felder an Arbeitsplätzen oder Häusern -> ein Jäger.
## Wer passt am besten (josh 2026-10-30)? Talent und Stufe im neuen Beruf zählen, Erfahrung im alten Beruf
## geht ungern verloren, und wer nah an den Arbeitsplätzen des Berufs wohnt, hat kurze Wege.
func _pick(w, cands: Array, job: String):
	var sk: String = Data.jobs.get(job, {}).get("skill", "")
	var spots := _job_spots(w, job)
	var best = null
	var best_v := -INF
	for s in cands:
		var v: float = s.skill_factor(sk) if sk != "" else 1.0
		var old_sk: String = Data.jobs.get(s.job, {}).get("skill", "")
		if s.job != "frei" and old_sk != "" and old_sk != sk:
			v -= 0.5 * maxf(0.0, s.skill_factor(old_sk) - 1.0)  # Erfahrung im alten Beruf
		if not spots.is_empty():
			var from: Vector2i = s.cell
			var home = w.building_by_id(s.home_id)
			if home != null:
				from = home.cell
			var d := INF
			for c in spots:
				d = minf(d, Vector2(c - from).length())
			v -= minf(d, 40.0) / 80.0  # bis zu 0,5 Abzug für weite Wege
		if v > best_v:
			best_v = v
			best = s
	return best


## Zellen, an denen der Beruf arbeitet (Werkstätten, Felder, Ställe, Rohstoffe der Natur).
func _job_spots(w, job: String) -> Array:
	var out := []
	for b in w.buildings:
		if not b.complete:
			continue
		if job == "bauer" and b.def.has("farm"):
			out.append(b.cell)
		elif b.def.has("production") and KIND_JOB.get(b.prod_def().get("job", ""), "") == job:
			out.append(b.cell)
		elif job == "forscher" and b.def.has("research"):
			out.append(b.cell)
	if out.is_empty() and RAW_NODES.has(job):
		for n in w.nodes:
			if is_instance_valid(n) and str(n.type) in RAW_NODES[job] and int(n.amount) > 0:
				out.append(n.cell)
				if out.size() >= 60:
					break
	return out


## Holt einen Siedler für den Beruf. Freie zuerst (bei "long" nur die schon einen Tag Freien), bei "spare"
## auch Leute aus Berufen über dem Stellenplan, bei "hard" (Essen, Wärme) notfalls jeden anderen außer
## Nahrung und Holz, Spieler-Eingeteilte zuletzt (dann mit Meldung). Nie Verwalter und Seeleute.
func _take_worker(w, need: Dictionary):
	var job: String = need.job
	var src: String = need.get("src", "free")
	var adults := _adults(w).filter(func(s): return s.job != job and not s.job in PROTECT)
	var free := adults.filter(func(s): return s.job == "frei" and JobDesk.may(s, "verwalter") and (src != "long" or free_days(s) >= FREE_DAYS))
	if not free.is_empty():
		return _pick(w, free, job)
	if src == "free" or src == "long":
		return null
	var over := func(j: String) -> bool:
		return _surplus(w, j) and not j in FOOD_JOBS and j != "holzfaeller"
	# Wer gerade erst umgesetzt wurde, bleibt eine Weile (josh 2026-11-01: Köche wurden ständig hin und her geschoben)
	var settled := func(s) -> bool: return Game.time_days - float(s.get_meta("adm_moved", -99.0)) >= KEEP_DAYS
	var spare := adults.filter(func(s): return JobDesk.may(s, "verwalter") and over.call(s.job) and settled.call(s))
	if not spare.is_empty():
		return _pick(w, spare, job)
	if src != "hard":
		return null
	# Köche machen auch Essen (Mühle, Bäckerei, Räucherei): nicht für Rohnahrung abziehen (josh 2026-11-01)
	var safe := func(s): return not s.job in FOOD_JOBS and s.job != "koch" and s.job != "holzfaeller" and s.job != "frei"
	var mine := adults.filter(func(s): return safe.call(s) and JobDesk.may(s, "verwalter"))
	if not mine.is_empty():
		return _pick(w, mine, job)
	var theirs := adults.filter(func(s): return safe.call(s))
	if not theirs.is_empty():
		return _pick(w, theirs, job)
	return null


# ---------------------------------------------------------------- Überstunden im Notfall
# ---------------------------------------------------------------- Forschung (Befugnis „Forschung weiterführen“)
# ---------------------------------------------------------------- Auslastung (josh 2026-10-22, nur Anzeige)
## Auslastung eines Berufs auf der Insel: [Mittel in %, kleinster Wert, gemessene Leute, alle Leute].
func job_busy(w, job: String) -> Array:
	var sum := 0.0
	var lo := 999
	var n := 0
	var all := 0
	for s in _adults(w):
		if s.job != job:
			continue
		all += 1
		var b: int = s.busy_percent()
		if b < 0:
			continue
		sum += b
		lo = mini(lo, b)
		n += 1
	return [sum / n if n > 0 else -1.0, lo if n > 0 else -1, n, all]


## Einen Forscher frei machen (der am wenigsten zu tun hat). Für die KI.
func release_researcher(w) -> void:
	var cand := _adults(w).filter(func(s): return s.job == "forscher" and JobDesk.may(s, "verwalter"))
	if cand.is_empty():
		return
	cand.sort_custom(func(a, c): return a.busy_percent() < c.busy_percent())
	JobDesk.assign(cand[0], "frei", "verwalter")
	Admin.add_log(who() + ": " + tr("%s forscht nicht mehr und ist jetzt frei.") % cand[0].display_name)


func _adults(w) -> Array:
	return w.settlers.filter(func(s): return s.is_adult())


func _count(w, job: String) -> int:
	return _adults(w).filter(func(s): return s.job == job).size() + w.droids.filter(func(d): return d.job == job).size()


func _cold_season() -> bool:
	var s := Seasons.season()
	return s == 1 or s == 2 or s == 3  # ab Sommer vorsorgen, Herbst und Winter heizen


## Brennstoff in Tagen (Kohle zählt doppelt).
func fuel_days(w) -> float:
	var per: float = Seasons.heat_per_settler() * maxf(1.0, float(w.settlers.size()))
	if per <= 0.0:
		return 999.0
	return (Game.amount("holz", w) + 2.0 * Game.amount("kohle", w)) / per


func _workplaces(w, kind: String) -> int:
	var n := 0
	for b in w.buildings:
		if b.complete and b.def.has("production") and b.prod_def().get("job", "") == kind:
			n += b.slots()
	return n


## Nur Berufe, in denen gerade etwas zu holen ist (kein Sammler im Winter, kein Bauer ohne Ernte); "" = keiner.
func _food_job(w) -> String:
	var order := []
	var fields: Array = w.buildings.filter(func(b): return b.complete and b.def.has("farm"))
	if not fields.is_empty() and _count(w, "bauer") < ceili(float(fields.size()) / FIELDS_PER_FARMER):
		order.append("bauer")
	if w.animals.size() > 6 and _count(w, "jaeger") < 1:
		order.append("jaeger")
	order += ["fischer", "sammler"] if _count(w, "fischer") <= _count(w, "sammler") else ["sammler", "fischer"]
	order += ["jaeger", "bauer"]
	for j in order:
		if Data.job_unlocked(j) and _raw_block(w, j) == "":
			return j
	return ""


## Wer stellt die Ware her? Rohstoffe aus RAW_JOB, sonst der Beruf einer Werkstatt, die sie herstellt.
func _producer(w, id: String) -> String:
	if RAW_JOB.has(id):
		return RAW_JOB[id]
	for b in w.buildings:
		if b.complete and b.def.has("production") and b.prod_def().get("outputs", {}).has(id):
			return KIND_JOB.get(b.prod_def().get("job", ""), "")
	return ""


# ---------------------------------------------------------------- Lieferketten (josh 2026-10-30)
## Quellen in der Natur je Beruf (Knoten aus nodes.json), für _raw_block.
const RAW_NODES := {"holzfaeller": ["baum"], "sammler": ["busch", "palme", "pilzkreis"],
	"fischer": ["fischgrund"], "steinmetz": ["fels", "erzader", "goldader"], "jaeger": ["beute", "wolfsbau", "eberbau", "baerenhoehle"]}
const RIPE_MIN := 3  # so viel muss in der Natur reif sein, damit ein weiterer Arbeiter etwas holen kann


## Was gerade reif in der Natur liegt (Summe der Mengen) und wie stark es in dieser Jahreszeit nachwächst.
func _ripe(w, types: Array) -> Array:
	var n := 0
	for o in w.nodes:
		if is_instance_valid(o) and str(o.type) in types and int(o.amount) > 0:
			n += int(o.amount)
	var g := 0.0
	for t in types:
		g = maxf(g, Seasons.growth(str(t), w))
	return [n, g]


## Kann ein (weiterer) Siedler in diesem Rohstoffberuf gerade etwas holen? "" = ja, sonst der Grund.
## Holzfäller ohne Bäume, Sammler im Winter, Bauern ohne Felder oder im Winter, Fischer an leeren Gründen.
func _raw_block(w, job: String) -> String:
	match job:
		"bauer":
			var fields: int = w.buildings.filter(func(b): return b.complete and b.def.has("farm")).size()
			var stalls := _workplaces(w, "stall")
			if fields == 0 and stalls == 0:
				return tr("Es gibt keine Felder und keine Ställe.")
			if stalls == 0 and Seasons.growth("feld", w) <= 0.0 and Seasons.growth("obstgarten", w) <= 0.0:
				return tr("Im Winter wächst auf den Feldern nichts.")
			return ""
		"jaeger":
			if w.animals.is_empty() and _ripe(w, ["beute"])[0] <= 0:
				return tr("Es gibt keine Tiere zum Jagen.")
			return ""
		"steinmetz":
			if _workplaces(w, "stein") > 0:
				return ""
	if not RAW_NODES.has(job):
		return ""
	var types: Array = RAW_NODES[job]
	if job == "sammler":  # nur, was in dieser Jahreszeit wächst (im Winter nichts, außer Palmen)
		types = types.filter(func(t): return Seasons.growth(str(t), w) > 0.0)
		if types.is_empty():
			return tr("Im Winter wächst nichts zum Sammeln.")
	var r := _ripe(w, types)
	if int(r[0]) >= RIPE_MIN * (_count(w, job) + 1) or (int(r[0]) >= RIPE_MIN and float(r[1]) > 0.0):
		return ""
	match job:
		"holzfaeller":
			return tr("Es gibt gerade keine Bäume zum Fällen. Ein Förster pflanzt neue, sie wachsen erst nach.") if int(r[0]) < RIPE_MIN else tr("Die wenigen Bäume reichen nicht für mehr Holzfäller.")
		"sammler":
			if float(r[1]) <= 0.0 or Seasons.is_winter():
				return tr("Im Winter wächst nichts zum Sammeln.")
			return tr("Alle Sträucher sind abgeerntet und wachsen erst nach.")
		"fischer":
			return tr("Die Fischgründe sind leer gefischt und erholen sich erst.")
		"steinmetz":
			return tr("Es gibt keine Felsen mehr. Baue einen Steinbruch.")
	return ""


## Gebäudeart, die die Ware herstellt (für den Hinweis „baue …“).
func _maker_type(id: String) -> String:
	for t in Data.buildings:
		var d: Dictionary = Data.buildings[t]
		if d.get("buildable", true) and d.has("production") and d.production.get("outputs", {}).has(id):
			return t
	return ""


## Ein Beruf ist überzählig, wenn alle seine Waren den Mindestvorrat bzw. das Lagerziel erreicht haben oder
## das Lager dafür voll ist.
func _surplus(w, job: String) -> bool:
	if job in task_jobs(w):
		return false  # Hauptaufgabe der Insel: diese Berufe bleiben
	if net_active() and Sea.is_main(w) and job in RAW_JOB.values():
		return true  # Heimatinsel im Inselverbund: nur noch Endverarbeitung
	var goods := []
	for id in RAW_JOB:
		if RAW_JOB[id] == job:
			goods.append(id)
	if goods.is_empty():
		return false
	for id in goods:
		var mn := int(limits(int(w.island_id), id)[0])
		if mn > 0 and Game.amount(id, w) < mn:
			return false
		var mx := int(w.store_limits.get(id, 0))
		if mx > 0 and Game.amount(id, w) < mx:
			return false
		if mx <= 0 and mn <= 0 and Game.space_for(id, w) > 0:
			return false
	return true


# ---------------------------------------------------------------- Rangliste der Werkstätten (josh 2026-11-14)
## josh: „Für die Handwerker kannst du eine Rangliste einführen.“ Je Insel eine Reihenfolge der Werkstattarten
## des Handwerkers (Fenster Verwalter, Reiter Rangliste). Handwerker besetzen zuerst die Werkstatt, die am
## weitesten oben steht und arbeiten kann (World.find_workshop). Ohne eigene Rangliste wie bisher: zuerst dorthin,
## wo am wenigsten von der Ware im Lager liegt.
var craft_rank: Dictionary = {}  # Insel-ID (String) -> Array Gebäudearten (Grundart), oben = zuerst


## Grundart einer Werkstatt (ausgebaute Werft zählt als Werft).
static func craft_type(b) -> String:
	return str(b.def.get("base", b.type))


## Hat die Insel eine eigene Rangliste?
func has_rank(w) -> bool:
	return w != null and not Array(craft_rank.get(str(int(w.island_id)), [])).is_empty()


## Werkstattarten des Handwerkers auf dieser Insel in ihrer Reihenfolge: erst die Rangliste, dann neue Arten.
func rank_list(w) -> Array:
	var have := []
	for t in Data.buildings:  # Reihenfolge der Bauliste
		for b in w.buildings:
			if b.def.get("production", {}).get("job", "") == "handwerk" and craft_type(b) == t and not t in have:
				have.append(t)
	var out: Array = Array(craft_rank.get(str(int(w.island_id)), [])).filter(func(t): return t in have)
	for t in have:
		if not t in out:
			out.append(t)
	return out


## Platz in der Rangliste (0 = zuerst); ohne Rangliste 0.
func rank_index(w, b) -> int:
	if not has_rank(w):
		return 0
	var i := rank_list(w).find(craft_type(b))
	return i if i >= 0 else 99


## Eine Art um einen Platz nach oben (dir -1) oder unten (dir 1) schieben.
func rank_move(w, type: String, dir: int) -> void:
	var list := rank_list(w)
	var i := list.find(type)
	var j := i + dir
	if i < 0 or j < 0 or j >= list.size():
		return
	list[i] = list[j]
	list[j] = type
	craft_rank[str(int(w.island_id))] = list
	World.global_rev += 1


## Zurück zur Automatik (knappste Ware zuerst).
func rank_clear(w) -> void:
	craft_rank.erase(str(int(w.island_id)))
	World.global_rev += 1


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	on = false
	blocks = {}
	_old_blocks = {}
	offered = false
	offered_routes = false
	offered_net = false
	offered_automat = false
	net_on = true
	minmax = {}
	tasks = {}
	craft_rank = {}
	_want_avg = {}
	_next = 0.0
	_moved = {}
	_few = {}
	_job_moved = {}
	_free_since = {}
	_day_stats = {}
	research_info = ""
	_route_next = 0.0
	_net_next = 0.0
	changed.emit()


func _on_save(d: Dictionary) -> void:
	d["steward"] = {"on": on, "offered": offered, "offered_routes": offered_routes, "offered_net": offered_net, "offered_automat": offered_automat, "net_on": net_on, "minmax": minmax.duplicate(true), "tasks": tasks.duplicate(true), "craft_rank": craft_rank.duplicate(true)}


func _on_load(data: Dictionary, _old_rules: int) -> void:
	_on_reset()
	var e = data.get("steward", null)
	if not (e is Dictionary):
		return
	on = bool(e.get("on", false))
	offered = bool(e.get("offered", false))
	offered_routes = bool(e.get("offered_routes", false))
	offered_net = bool(e.get("offered_net", false))
	offered_automat = bool(e.get("offered_automat", false))
	net_on = bool(e.get("net_on", true))
	var mm = e.get("minmax", {})
	if mm is Dictionary:
		for k in mm:
			if mm[k] is Dictionary:
				for id in mm[k]:
					var v = mm[k][id]
					if Data.resources.has(str(id)) and v is Array and v.size() == 2:
						if not minmax.has(str(k)):
							minmax[str(k)] = {}
						minmax[str(k)][str(id)] = [int(v[0]), int(v[1])]
	var cr = e.get("craft_rank", {})
	if cr is Dictionary:
		for k in cr:
			if cr[k] is Array:
				craft_rank[str(k)] = Array(cr[k]).map(func(x): return str(x)).filter(func(x): return Data.buildings.has(x))
	var tk = e.get("tasks", {})
	if tk is Dictionary:
		for k in tk:
			var v = tk[k]
			var keys: Array = (v if v is Array else [v]).map(func(x): return str(x)).filter(func(x): return TASKS.has(x))
			if not keys.is_empty():
				tasks[str(k)] = keys  # früher nur eine Aufgabe als Text
	changed.emit()


func autotest_setup(_args: Dictionary, _main) -> void:
	pass  # Test der Auslastung: --powerstest=1 (PowersTest)


# ---------------------------------------------------------------- Stufe 2: Warenausgleich zwischen Inseln
## Ab der dritten besiedelten Insel: der Spieler stellt je Insel und Ware einen Mindest- und Höchststand ein
## (minmax). Liegt eine Insel unter dem Mindeststand, schickt der Verwalter ein freies Schiff (keine Route,
## keine Fahrt) mit der Ware von einer Insel, die mehr hat als ihren eigenen Mindeststand (zuerst über
## ihrem Höchststand). Liegt eine Insel über dem Höchststand, bringt er den Überschuss zu einer Insel, die
## unter ihrem Höchststand liegt (zuerst die Heimatinsel). Das Schiff fährt als Einmal-Fahrt
## (Sea.start_trip) und ist danach wieder frei; sh.steward markiert es.
const ROUTE_TICK := 0.5
var minmax: Dictionary = {}  # Insel-ID (String) -> {Ware: [min, max]}; 0 = keine Grenze
var _route_next := 0.0


func routes_unlocked() -> bool:
	return Powers.unlocked("waren")


func limits(island_id: int, id: String) -> Array:
	var e: Dictionary = minmax.get(str(island_id), {})
	var v = e.get(id, [0, 0])
	return [int(v[0]), int(v[1])]


func set_limits(island_id: int, id: String, mn: int, mx: int) -> void:
	mn = maxi(0, mn)
	mx = maxi(0, mx)
	# Höchstens so viel, wie das Lager der Insel für diese Ware fasst (Lagergrenze dort, josh 2026-10-20)
	var cap := store_cap(island_id, id)
	if cap >= 0:
		mn = mini(mn, cap)
		mx = mini(mx, cap)
	if mx > 0 and mn > mx:
		mn = mx
	var key := str(island_id)
	if not minmax.has(key):
		minmax[key] = {}
	if mn == 0 and mx == 0:
		minmax[key].erase(id)
	else:
		minmax[key][id] = [mn, mx]
	changed.emit()


## So viel kann das Lager der Insel von der Ware höchstens halten: die Lagergrenze, sonst der ganze
## freie Platz für sie (Game.max_limit). -1 = Insel nicht geladen.
func store_cap(island_id: int, id: String) -> int:
	var w = Sea.worlds.get(island_id)
	if w == null or not is_instance_valid(w):
		return -1
	var lim := Game.limit_of(id, w)
	return lim if lim >= 0 else Game.max_limit(id, w)


## Was schon unterwegs ist (Fahrten des Verwalters) zur Insel to mit der Ware id.
func incoming(to_id: int, id: String) -> int:
	var n := 0
	for sh in Sea.ships:
		if Sea.is_trip(sh) and sh.route.size() >= 2 and int(sh.route[-1].island) == to_id:
			n += int(sh.route[0].get("load", {}).get(id, 0)) + int(sh.cargo.get(id, 0))
	return n


## Was schon abgeholt wird von der Insel from mit der Ware id (Fahrt noch nicht geladen).
func outgoing(from_id: int, id: String) -> int:
	var n := 0
	for sh in Sea.ships:
		if Sea.is_trip(sh) and sh.route.size() >= 2 and int(sh.route[0].island) == from_id and int(sh.leg) == 0 and sh.state != "load":
			n += int(sh.route[0].get("load", {}).get(id, 0))
	return n


## Das beste freie Schiff für eine Fahrt: das nächste; liegen mehrere etwa gleich nah (bis einen halben Tag),
## das mit dem größten Laderaum (josh 2026-10-18: sonst fuhr meist das Ruderboot, die Kogge blieb liegen).
## Größere Schiffe brauchen auf beiden Inseln einen Hafen (Sea.can_visit); fehlt er, sagt der Verwalter es einmal.
func _free_ship(from_id: int, to_id: int) -> Dictionary:
	var best := {}
	var best_d := INF
	var no_harbor := {}
	for sh in Sea.ships:
		if sh.state != "dock" or not sh.route.is_empty() or Sea.is_trip(sh) or not sh.cargo.is_empty():
			continue
		if not Sea.can_visit(sh.type, from_id) or not Sea.can_visit(sh.type, to_id):
			no_harbor = sh
			continue
		Sea.fill_crew(sh)
		if Sea.ship_blocker(sh) != "":
			continue
		var d := 0.0 if int(sh.at) == from_id else Sea.voyage_days(int(sh.at), from_id, sh.type)
		if best.is_empty() or d < best_d - 0.5 or (d <= best_d + 0.5 and Sea.cargo_room(sh) > Sea.cargo_room(best)):
			best_d = minf(d, best_d)
			best = sh
	if not no_harbor.is_empty() and (best.is_empty() or Sea.cargo_room(best) < Sea.cargo_room(no_harbor)):
		var where := from_id if not Sea.can_visit(no_harbor.type, from_id) else to_id
		if Game.time_days - float(_harbor_hint.get(where, -9.0)) > 3.0:
			_harbor_hint[where] = Game.time_days
			Game.notify(who() + ": " + tr("Die %s kann nicht nach %s fahren, dort fehlt ein Hafen. Bis dahin fahren kleinere Schiffe.") % [no_harbor.name, Sea.meta(where).get("name", "?")], "anker", "verwaltung")
	return best


var _harbor_hint: Dictionary = {}  # Insel-ID -> Tag der letzten Meldung „fehlt ein Hafen“


## Verfügbar zum Abgeben: über dem eigenen Mindeststand (und nicht schon abgeholt).
func _spare(island_id: int, id: String) -> int:
	var w = Sea.worlds.get(island_id)
	if w == null:
		return 0
	var lim := limits(island_id, id)
	return Game.amount(id, w) - outgoing(island_id, id) - lim[0]


func _send(from_id: int, to_id: int, id: String, n: int, why: String) -> bool:
	return _send_goods(from_id, to_id, {id: n}, why)


## Eine Fahrt als Entscheidung der Befugnis „Waren ausgleichen“ (josh 2026-10-29): Selbst fährt sie gleich,
## Fragen legt sie als Vorschlag ab. true = erledigt oder vorgeschlagen (eine Fahrt je Runde).
func _send_goods(from_id: int, to_id: int, goods: Dictionary, why: String) -> bool:
	if _free_ship(from_id, to_id).is_empty():
		return false
	var parts := []
	for id in goods:
		if int(goods[id]) >= 5:
			parts.append("%d %s" % [int(goods[id]), Data.resource_name(id)])
	if parts.is_empty():
		return false
	var key := "trip:%d:%d:%s" % [from_id, to_id, ",".join(PackedStringArray(goods.keys()))]
	var text := tr("Schiff bringt %s von %s nach %s (%s).") % [", ".join(PackedStringArray(parts)),
		Sea.meta(from_id).get("name", "?"), Sea.meta(to_id).get("name", "?"), why]
	# Befugnis „Waren ausgleichen“ gibt es seit josh 2026-11-07 nicht mehr; Automat und KI fahren direkt
	if not ship_now(from_id, to_id, goods, why):
		return false
	Admin.add_log(who() + ": " + text)
	return true


## Schickt ein freies Schiff mit mehreren Waren (in der Reihenfolge von goods, bis der Laderaum voll ist).
func ship_now(from_id: int, to_id: int, goods: Dictionary, _why: String) -> bool:
	var sh := _free_ship(from_id, to_id)
	if sh.is_empty():
		return false
	var room := Sea.cargo_room(sh)
	var ld := {}
	var parts := []
	for id in goods:
		var n: int = mini(int(goods[id]), room / maxi(1, Data.good_size(id)))
		if n < 5:
			continue
		ld[id] = n
		room -= n * Data.good_size(id)
		parts.append("%d %s" % [n, Data.resource_name(id)])
	if ld.is_empty():
		return false
	if Sea.start_trip(sh, from_id, to_id, ld) != "":
		return false
	sh["steward"] = true
	return true


# ---------------------------------------------------------------- Stufe 3: Inselverbund, Rechenautomat, Automat
## Ab Papier reden die Verwalter der Inseln miteinander (net_on, abschaltbar), aber nur über eine Rundfunkanstalt
## (Gebäude mit "radio", josh 2026-10-21): mitmachen nur Inseln mit fertiger Rundfunkanstalt, und ohne eine auf
## der Heimatinsel ruht der Verbund ganz (net_member, has_radio). Die Heimatinsel macht nur noch
## Endverarbeitung und Forschung, Rohstoff-Berufe sind dort überzählig. Essen und Brennholz kommen per Schiff
## von den anderen Inseln (die dafür NET_FOOD_DAYS Tage Vorrat halten), Überschüsse an Rohstoffen werden zur
## Heimatinsel abgeholt. Rechenautomat (Gebäude, ab 2 Inseln, einer Insel mit über 60 Siedlern und der
## Renaissance): auf seiner Insel gilt die Grenze von 60 Siedlern nicht. Ab Elektrizität ersetzt ein Automat den
## Verwalter: keine Grenze mehr, Meldungen beginnen mit „Automat“.
const NET_FOOD_DAYS := 6.0
const HOME_FOOD_DAYS := 5.0
const HOME_FUEL_DAYS := 6.0
const KEEP_RAW := 60  # so viel behält eine Insel von jedem Rohstoff, der Rest geht zur Heimatinsel
var net_on := true
var offered_net := false
var offered_automat := false
var _net_next := 0.0


func net_unlocked() -> bool:
	return unlocked() and Game.is_researched("papier")


func net_active() -> bool:
	return active() and Powers.on("waren") and net_on and net_unlocked() and has_radio(Sea.main_world()) and _ids().size() >= 2


func has_radio(w) -> bool:
	if w == null:
		return false
	for b in w.buildings:
		if is_instance_valid(b) and b.complete and b.def.get("radio", false):
			return true
	return false


## Gehört die Insel zum Inselverbund? (Verbund an und eine Rundfunkanstalt auf der Insel)
func net_member(w) -> bool:
	return net_active() and has_radio(w)


## Wer steuert gerade? Für Meldungen.
func who() -> String:
	if AiRule.ki():
		return tr("KI")
	return tr("Verwalter")


## "" = der Rechenautomat darf gebaut werden, sonst was noch fehlt (josh: ab der 2. Insel, mehr als 60 Siedlern und der Renaissance).
func automaton_reason() -> String:
	var miss := []
	if Sea.settled_islands().size() < 2:
		miss.append(tr("eine zweite Insel"))
	var big := false
	for w in Sea.all_worlds():
		if w.settlers.size() > MAX_POP:
			big = true
	if not big:
		miss.append(tr("eine Insel mit mehr als %d Siedlern") % MAX_POP)
	if Game.current_age() < 3:
		miss.append(tr("die Renaissance"))
	if miss.is_empty():
		return ""
	return tr("Benötigt noch: %s") % ", ".join(PackedStringArray(miss))


## Inseln im Inselverbund: bewohnt und mit Rundfunkanstalt.
func _ids() -> Array:
	return Sea.settled_islands().map(func(m): return int(m.id)).filter(func(i): return has_radio(Sea.worlds.get(i)))


## Welche andere Insel kann der Heimatinsel liefern? what = "food" oder eine Ware. -1 = keine.
func _supplier(hw, what: String) -> int:
	var best := -1
	var best_v := 0.0
	for i in _ids():
		var w = Sea.worlds.get(i)
		if w == null or w == hw:
			continue
		var v: float
		if what == "food":
			v = Game.food_days(w) - 4.0
		elif what == "holz":
			v = float(Game.amount("holz", w) - KEEP_RAW)
		else:
			v = float(Game.amount(what, w) - KEEP_RAW)
		if v > best_v:
			best_v = v
			best = i
	return best


func _food_load(src) -> Dictionary:
	var ids: Array = Data.food_ids().filter(func(f): return Game.amount(f, src) > 0)
	ids.sort_custom(func(a, b): return Game.amount(a, src) * Data.food_satiety(a) > Game.amount(b, src) * Data.food_satiety(b))
	var keep := 1.0 - 4.0 / maxf(4.01, Game.food_days(src))  # Anteil, den die Insel abgeben kann (behält 4 Tage)
	var ld := {}
	for f in ids:
		ld[f] = int(Game.amount(f, src) * keep)
	return ld


func net_tick() -> void:
	var hw = Sea.main_world()
	if hw == null:
		return
	var home_id := int(hw.island_id)
	var fd := Game.food_days(hw)
	# 1. Essen zur Heimatinsel (nicht mehr unter der Superintelligenz)
	if AiRule.si():
		fd = 999.0
	if fd >= 0.0 and fd + _incoming_food_days(hw) < HOME_FOOD_DAYS:
		var src := _supplier(hw, "food")
		if src != -1 and _send_goods(src, home_id, _food_load(Sea.worlds.get(src)), tr("Essen für die Heimatinsel")):
			return
	# 2. Brennholz zur Heimatinsel
	if not AiRule.si() and fuel_days(hw) < HOME_FUEL_DAYS and incoming(home_id, "holz") == 0:
		var src := _supplier(hw, "holz")
		if src != -1 and _send(src, home_id, "holz", Game.amount("holz", Sea.worlds.get(src)) - KEEP_RAW, tr("Brennholz für die Heimatinsel")):
			return
	# 3. Überschüsse an Rohstoffen abholen (ohne vom Spieler eingestellte Grenzen)
	for i in _ids():
		if i == home_id:
			continue
		var w = Sea.worlds.get(i)
		var ld := {}
		for id in RAW_JOB:
			if Data.food_ids().has(id) or limits(i, id) != [0, 0]:
				continue
			var extra: int = Game.amount(id, w) - outgoing(i, id) - KEEP_RAW
			var room: int = Game.space_for(id, hw) - incoming(home_id, id)
			if extra >= 20 and room >= 20:
				ld[id] = mini(extra, room)
		var keys: Array = ld.keys()
		keys.sort_custom(func(a, b): return ld[a] > ld[b])  # größter Überschuss zuerst
		var sorted := {}
		for k in keys:
			sorted[k] = ld[k]
		if not sorted.is_empty() and _send_goods(i, home_id, sorted, tr("Überschuss zur Heimatinsel")):
			return


func _incoming_food_days(hw) -> float:
	var sat := 0.0
	for f in Data.food_ids():
		sat += incoming(int(hw.island_id), f) * Data.food_satiety(f)
	var need := float(Data.bal("hunger_per_day")) * Game.eff("hunger") * Seasons.hunger_mult(hw)
	return sat / (maxf(1.0, hw.settlers.size()) * maxf(need, 0.01))



# ---------------------------------------------------------------- Hauptaufgabe je Insel (josh 2026-10-18)
## Der Spieler wählt für eine Insel eine oder mehrere Hauptaufgaben; der Verwalter setzt dann TASK_SHARE der
## Erwachsenen (ohne Verwalter, Seeleute, Baumeister, Forscher) in die passenden Berufe, gleich verteilt. Werkstatt-
## Berufe (Handwerker, Koch) nur, wenn auf der Insel eine Werkstatt steht, die eine Ware der Aufgaben herstellt, und
## nur so viele, wie sie Plätze hat. Essen, Brennholz und Baustellen gehen weiter vor; diese Berufe sind nie
## überzählig. "nodes": Sammler und Steinmetze gehen zuerst an diese Fundstellen (IslandTraits.gather_order).
const TASK_SHARE := 0.6
const TASKS := {
	"holz": {"name": "Holz und Bretter", "icon": "holz", "goods": ["holz", "bretter"], "jobs": ["holzfaeller", "handwerker"], "nodes": []},
	"stein": {"name": "Stein und Ziegel", "icon": "stein", "goods": ["stein", "lehm", "ziegel"], "jobs": ["steinmetz", "handwerker"], "nodes": ["fels"]},
	"getreide": {"name": "Getreide und Brot", "icon": "weizen", "goods": ["weizen", "mehl", "brot"], "jobs": ["bauer", "koch"], "nodes": []},
	"fisch": {"name": "Fisch", "icon": "fisch", "goods": ["fisch", "raeucherfisch"], "jobs": ["fischer", "koch"], "nodes": []},
	"sammeln": {"name": "Beeren", "icon": "beeren", "goods": ["beeren"], "jobs": ["sammler"], "nodes": ["busch"]},
	"pilze": {"name": "Pilze", "icon": "pilze", "goods": ["pilze"], "jobs": ["sammler"], "nodes": ["pilzkreis"]},
	"kokos": {"name": "Kokosnüsse", "icon": "kokos", "goods": ["kokos"], "jobs": ["sammler"], "nodes": ["palme"]},
	"jagd": {"name": "Fleisch und Felle", "icon": "fleisch", "goods": ["fleisch", "felle"], "jobs": ["jaeger"], "nodes": []},
	"metall": {"name": "Erz und Metall", "icon": "eisen", "goods": ["erz", "kohle", "eisen", "werkzeug", "stahl"], "jobs": ["steinmetz", "handwerker"], "nodes": ["erzader"]},
	"gold": {"name": "Gold", "icon": "gold", "goods": ["gold"], "jobs": ["steinmetz"], "nodes": ["goldader"]},
	"forschung": {"name": "Forschung", "icon": "wissen", "goods": [], "jobs": ["forscher"], "nodes": []},
}
var tasks: Dictionary = {}  # Insel-ID (String) -> Array mit Schlüsseln aus TASKS


## Die Hauptaufgaben einer Insel, in der Reihenfolge von TASKS.
func tasks_of(w) -> Array:
	if w == null:
		return []
	var have: Array = tasks.get(str(int(w.island_id)), [])
	return TASKS.keys().filter(func(k): return k in have)


func task_names(w) -> String:
	return ", ".join(PackedStringArray(tasks_of(w).map(func(k): return tr(TASKS[k].name))))


## Berufe, die für die Hauptaufgaben auf dieser Insel gebraucht werden und dort arbeiten können.
func task_jobs(w) -> Array:
	var keys := tasks_of(w)
	var goods := _task_goods(keys)
	var out := []
	for key in keys:
		for j in TASKS[key].jobs:
			if j in out or not Data.job_unlocked(j):
				continue
			if j == "forscher" and not Sea.is_main(w):
				continue  # geforscht wird nur auf der Heimatinsel
			if j in ["handwerker", "koch"] and _task_places(w, goods, j) == 0:
				continue
			out.append(j)
	return out


## Fundstellen, an die Sammler und Steinmetze dieser Insel zuerst gehen.
func task_nodes(w) -> Array:
	var out := []
	for key in tasks_of(w):
		for n in TASKS[key].nodes:
			if not n in out:
				out.append(n)
	return out


func _task_goods(keys: Array) -> Array:
	var out := []
	for key in keys:
		out.append_array(TASKS[key].goods)
	return out


## Plätze in Werkstätten dieser Insel, die eine Ware der Aufgaben herstellen (für Handwerker und Köche).
func _task_places(w, goods: Array, job: String) -> int:
	var kind := "handwerk" if job == "handwerker" else "kueche"
	var n := 0
	for b in w.buildings:
		if b.complete and b.def.has("production") and b.prod_def().get("job", "") == kind:
			for id in b.prod_def().get("outputs", {}):
				if id in goods:
					n += b.slots()
					break
	return n


## Wie viele Siedler soll ein Beruf der Hauptaufgaben haben?
func task_target(w, job: String) -> int:
	var jobs := task_jobs(w)
	if not job in jobs:
		return 0
	var pool: int = _adults(w).filter(func(s): return not s.job in KEEP or s.job in jobs).size() + w.droids.size()
	var n: int = maxi(1, int(ceil(pool * TASK_SHARE / float(jobs.size()))))
	if job in ["handwerker", "koch"]:
		n = mini(n, _task_places(w, _task_goods(tasks_of(w)), job))
	return n


func task_need(w) -> Dictionary:
	if tasks_of(w).is_empty():
		return {}
	var best := ""
	var gap := 0
	for j in task_jobs(w):
		var g: int = task_target(w, j) - _count(w, j)
		if g > gap:
			gap = g
			best = j
	if best == "":
		return {}
	return {"job": best, "why": tr("Hauptaufgabe: %s") % task_names(w), "hard": false, "task": true}
