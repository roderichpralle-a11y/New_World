extends Node
## Verwalter-Steuerung der Berufe (josh 2026-10-17, neu gedacht 2026-10-29, nur Version 2): Es gibt nur einen
## Verwalter, den Siedler in der Verwaltung. Was er darf, hängt an der Ausbaustufe der Verwaltung und an den
## Befugnissen (Powers, je Aus/Fragen/Selbst). Er arbeitet auf der Insel der Verwaltung und mit „Andere Inseln
## mitverwalten“ auf allen Inseln mit Rundfunkanstalt (Powers.covers). Reihenfolge je Insel:
##   1. Essen und Wärme sichern (Stufe 2): Bedarf der nächsten 3 Tage (Siedler, Häuser, Gebäude, gemessen am
##      Verbrauch des Vortags) gegen Vorrat plus Ertrag der jetzigen Arbeiter; fehlt etwas, so viele Leute wie
##      nötig, notfalls auch vom Spieler eingeteilte (mit Meldung). Klappt das nicht: Überstunden im Notfall.
##   2. Grundbesetzung (Stufe 1, nur Freie): Baumeister für Baustellen, Bauern nach Feldern und Ställen,
##      Holzfäller für die Wärme, Werkstätten mit Zutaten und Bedarf; ist ein Siedler einen Tag frei: Hauptaufgabe,
##      Mindestvorräte oder Werkstatt mit Arbeit.
##   3. Mindestvorräte (Stufe 2): Ware unter dem Mindeststand -> Freie und überzählige, die er selbst eingeteilt hat.
## Vom Spieler eingeteilte Siedler bleiben, bis der Spieler sie selbst freigibt (JobDesk). Höchstens ein Wechsel
## je Insel alle MOVE_DAYS, wer wechselt, bleibt KEEP_DAYS.

signal offer(kind: String)  # Hud zeigt ein Fenster (nur noch für die Geschichte der KI)
signal changed

const TICK_DAYS := 0.25
const MOVE_DAYS := 0.25
const RELEASE_IDLE := 40.0  # nur wer so viel Prozent der Zeit nichts zu tun hat, wird frei (josh: weder arbeiten noch forschen)
const RELEASE_DAYS := 0.5  # so lange muss ein Beruf über dem Stellenplan liegen, bis Leute frei werden
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
const NO_TRIM := ["frei", "verwalter", "seemann", "forscher"]
const MAX_POP := 60  # nur noch für alte Anzeigen (Rechenautomat)

var on := false        # alte Spielstände (früher Schalter); gesteuert wird über die Befugnisse
var offered := false
var offered_routes := false
var _next := 0.0
var _moved: Dictionary = {}       # Insel-ID -> Tag des letzten Wechsels
var _free_since: Dictionary = {}  # Siedler-ID -> Tag, seit dem er frei ist
var _emerg: Dictionary = {}       # Beruf -> letzter Tag mit ungesichertem Essen/Wärme (Notfall-Überstunden)
var _day_stats: Dictionary = {}   # Insel-ID -> {day, start: {holz, kohle, food}, made: {...}, prev: {used_fuel, used_food, made_food, made_holz, food_w, wood_w}}
var research_info := ""
var _old_blocks: Dictionary = {}
var _plan: Dictionary = {}  # Insel-ID -> letzter Stellenplan (StaffPlan.targets)
var _over: Dictionary = {}  # Insel-ID -> {Beruf: seit wann über dem Stellenplan}
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
	return tr("Nur mit der Befugnis „Andere Inseln mitverwalten“ und einer Rundfunkanstalt.")


## Früherer Schalter: jetzt nur noch für die KI-Geschichte.
func set_on(v: bool) -> void:
	on = v
	changed.emit()


## Der Spieler hat einem Siedler selbst einen Beruf gegeben: der bleibt, bis der Spieler ihn freigibt.
func player_set(s) -> void:
	if s != null:
		JobDesk.hold(s, "spieler")
		AiRule.player_changed("job:%d" % int(s.id))


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
	_end_emergency()
	if Powers.on("waren") and Game.time_days >= _route_next:
		_route_next = Game.time_days + ROUTE_TICK
		route_tick()
	if net_active() and Game.time_days >= _net_next:
		_net_next = Game.time_days + ROUTE_TICK
		net_tick()


func tick(w) -> void:
	if AiRule.si() or (AiRule.ki() and not Sea.is_main(w) and AiRule.automated(w)):
		return  # Superintelligenz: Menschen sind ihr egal; automatisierte Inseln brauchen keine Siedler mehr
	_track_free(w)
	if Sea.is_main(w):
		_check_research(w)
	var iid := int(w.island_id)
	if Game.time_days - float(_moved.get(iid, -99.0)) < MOVE_DAYS:
		return
	_moved[iid] = Game.time_days
	# Mehrere Wechsel je Runde, je mehr Siedler, desto mehr (100 Siedler: 11)
	var budget := 1 + _adults(w).size() / 10
	for need in needs(w):
		for k in int(need.get("miss", 1)):
			if budget <= 0:
				return
			var pick = _take_worker(w, need)
			if pick == null:
				if need.get("secure", false):
					_emergency(w, need)
				break
			var force: bool = not JobDesk.may(pick, "verwalter")
			var text := tr("%s arbeitet jetzt als %s (%s, vorher %s).") % [pick.display_name, Data.jobs[need.job].name, need.why, pick.job_name()]
			if force:
				text += " " + tr("Den Beruf hattest du vergeben, aber Essen und Wärme gehen vor.")
			var act := {"kind": "job", "island": iid, "sid": int(pick.id), "job": need.job, "force": force}
			if not Powers.decide(need.power, "job:%d:%s" % [iid, need.job], Sea.island_name(w) + ": " + text if Sea.worlds.size() > 1 else text, act, force):
				break  # Fragen: ein Vorschlag je Beruf genügt
			budget -= 1
	_release(w, budget)


## Leute ohne Bedarf auf frei (josh 2026-10-30): Liegt ein Beruf seit einem halben Tag über dem Stellenplan,
## werden die Überzähligen frei, damit der Spieler sie einsetzen kann; zuerst die, die am meisten nichts tun.
## Vom Spieler Eingeteilte nur, wenn sie mehr als die Hälfte der Zeit nichts zu tun haben.
func _release(w, budget: int) -> void:
	if not Powers.on("grundbesetzung"):
		return
	var iid := int(w.island_id)
	var tg: Dictionary = _plan.get(iid, {})
	var over: Dictionary = _over.get(iid, {})
	var now := {}
	for job in _job_counts(w):
		if job in PROTECT or job == "frei":
			continue
		var n := _count(w, job) - int(tg.get(job, {}).get("n", 0))
		if n <= 0:
			continue
		now[job] = float(over.get(job, Game.time_days))
		if Game.time_days - float(now[job]) < RELEASE_DAYS:
			continue
		var cands: Array = _adults(w).filter(func(s): return s.job == job and _idle(s) >= RELEASE_IDLE)
		cands.sort_custom(func(x, y): return _idle(x) > _idle(y))
		for s in cands.slice(0, mini(n, budget)):
			var force: bool = not JobDesk.may(s, "verwalter")
			var text := tr("%s ist jetzt frei: im Beruf %s gibt es gerade nichts zu tun (%d %% Leerlauf). Du kannst ihn einsetzen.") % [s.display_name, Data.jobs[job].name, roundi(_idle(s))]
			if Powers.decide("grundbesetzung", "free:%d:%s" % [iid, job], text, {"kind": "job", "island": iid, "sid": int(s.id), "job": "frei", "force": force}):
				budget -= 1
		if budget <= 0:
			break
	_over[iid] = now


func _idle(s) -> float:
	var sh: Array = s.busy_shares()
	return float(sh[2]) if not sh.is_empty() else 0.0


func _job_counts(w) -> Dictionary:
	var out := {}
	for s in _adults(w):
		out[s.job] = int(out.get(s.job, 0)) + 1
	return out


## Wer ist seit wann frei? (für „einen Tag frei, dann teilt der Verwalter ein“)
func _track_free(w) -> void:
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
	return maxf(est, float(prev.get("used_food", 0.0)) * 0.9)


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
## Alle Lücken in der Reihenfolge der Befugnisse: [{job, why, power, src, secure}]. src: "free" nur Freie,
## "spare" auch Überzählige, die der Verwalter eingeteilt hat, "hard" notfalls jeden (Essen und Wärme).
func needs(w) -> Array:
	var out := []
	if _adults(w).is_empty():
		return out
	var iid := int(w.island_id)
	_old_blocks[iid] = blocks.get(iid, {})
	blocks[iid] = {}
	# Stellenplan (josh 2026-10-30): Soll je Beruf aus Bedarf und Kapazität, siehe StaffPlan
	var tg := StaffPlan.targets(w)
	_plan[iid] = tg
	var rank := {"essen_waerme": 0, "grundbesetzung": 1, "mindestvorrat": 2, "forschung": 3}
	for j in tg:
		if j in PROTECT:
			continue
		var miss := int(tg[j].n) - _count(w, j)
		if miss <= 0 or not Powers.on(str(tg[j].power)):
			continue
		out.append({"job": j, "why": str(tg[j].why), "power": str(tg[j].power), "src": "hard" if tg[j].hard else "spare",
			"secure": bool(tg[j].hard), "miss": miss, "rank": int(rank.get(str(tg[j].power), 9))})
	out.sort_custom(func(x, y): return x.rank < y.rank or (x.rank == y.rank and int(x.miss) > int(y.miss)))
	# Engpässe der Lieferkette als Hinweis (Glas -> Lehm -> Lehmgrube …)
	if Powers.on("mindestvorrat"):
		_min_job(w)
		_house_job(w)
	if Powers.on("forschung") and Sea.is_main(w):
		_writing_job(w)
		_research_block(w)
	return out


## Forschung steht, weil die Kosten fehlen: als Engpass zeigen (die Waren stehen im Zielvorrat, StaffPlan).
func _research_block(w) -> void:
	if Game.research.current != "" or str(Game.research.get("next", "")) != "":
		return
	var order := Planner.tech_order()
	if order.is_empty():
		return
	var t: String = order[0]
	var miss := []
	var why := ""
	var cost: Dictionary = Data.techs[t].get("cost", {})
	for g in cost:
		if Game.amount(g, w) < int(cost[g]):
			miss.append("%d %s" % [int(cost[g]) - Game.amount(g, w), Data.resource_name(g)])
			var r := trace(w, str(g))
			if why == "" and r.has("block"):
				why = " " + str(r.block)  # z. B. „Schmelzofen arbeitet schon voll …“: hier hilft nur ein weiteres Gebäude
	if not miss.is_empty():
		_note_block(w, "forschung", tr("Forschung %s wartet, es fehlen: %s.") % [Data.techs[t].name, ", ".join(miss)] + why)


## Verderb (josh 2026-10-30): Liegt viel Frisches, das gerade verdirbt, und hat eine Küche (Räucherei, Bäckerei …)
## alles dafür, soll dort jemand arbeiten.
func _spoil_job(w) -> String:
	for b in w.buildings:
		if not (b.complete and b.def.has("production") and b.prod_def().get("job", "") == "kueche"):
			continue
		var p: Dictionary = b.prod_def()
		var fresh := false
		for res in p.get("inputs", {}):
			if Seasons.spoil_rate(str(res)) > 0.0 and Game.amount(res, w) >= int(p.inputs[res]) * 3:
				fresh = true
		if fresh and b.prod_blocker() == "" and b.free_slots() > 0 and w.pool_allows(b) and _count(w, "koch") < _workplaces(w, "kueche"):
			return "koch"
	return ""


## Gefahr (josh 2026-10-30): erwachsene Wölfe, Eber oder Bären bis 8 Felder an Arbeitsplätzen oder Häusern -> ein Jäger.
const DANGER_DIST := 8
func _danger_job(w) -> String:
	if not Data.job_unlocked("jaeger") or _count(w, "jaeger") >= 1 + _adults(w).size() / 8:
		return ""
	for a in w.animals:
		if not is_instance_valid(a) or a.dead or not a.is_adult() or float(a.def.get("damage", 0)) <= 0.0:
			continue
		if a.def.get("hibernate", false) and Seasons.is_winter():
			continue
		for b in w.buildings:
			if b.complete and (b.def.has("production") or b.house_level() > 0) and Vector2(a.cell - b.cell).length() <= DANGER_DIST:
				return "jaeger"
	return ""


## Hausbedürfnisse (josh 2026-10-30): Waren der bewohnten Hausstufen (Möbel = Bretter, Lesestoff, Glas …), die
## gerade fehlen, über die Lieferkette nachliefern.
func _house_job(w) -> Dictionary:
	var st: Dictionary = HouseNeeds.state.get(int(w.island_id), {})
	var cons: Array = st.get("_cons", [])
	for k in range(2, cons.size()):
		if float(cons[k]) <= 0.0:
			continue
		for nd in HouseNeeds.level_needs(k):
			var kind := str(nd.get("kind", ""))
			if not kind in ["good", "stock"] or HouseNeeds.need_sat(w, str(nd.id)) >= 0.9:
				continue
			var goods: Array = [str(nd.good)] + nd.get("alt", []) if kind == "good" else nd.get("goods", [])
			var block := {}
			for g in goods:
				var r := trace(w, str(g), 0, {})
				if r.has("job"):
					return {"job": r.job, "why": tr("Häuser brauchen %s (%s)") % [HouseNeeds.need_label(nd), r.why]}
				if r.has("block") and block.is_empty():
					block = r
			if not block.is_empty():
				_note_block(w, "haus:" + str(nd.id), tr("Häuser: %s fehlt. %s") % [HouseNeeds.need_label(nd), block.block])
	return {}


## Schriften (josh 2026-10-30): ohne Tontafeln, Papier … forschen die Forscher nur mit 20 %. Reicht der Vorrat
## nicht für den Rest der laufenden Forschung (höchstens 10), über die Lieferkette nachliefern.
func _writing_job(w) -> Dictionary:
	var cur: String = Game.research.current
	if cur == "":
		return {}
	var left := Writing.left_for(cur)
	for id in left:
		if Game.amount(id, w) >= mini(int(left[id]), 10):
			continue
		var r := trace(w, str(id), 0, {})
		if r.has("job"):
			return {"job": r.job, "why": tr("Schriften für die Forschung (%s)") % r.why}
		if r.has("block"):
			_note_block(w, "schrift:" + str(id), tr("Forschung: %s fehlt. %s") % [Data.resource_name(str(id)), r.block])
	return {}


## Die dringendste Lücke ({} = keine), für Anzeigen und Tests.
func needed(w) -> Dictionary:
	var l := needs(w)
	return l[0] if not l.is_empty() else {}


## Erster Werkstattberuf, dessen Werkstatt Zutaten hat, deren Ware gebraucht wird und in der Platz ist.
func _workshop_job(w) -> String:
	for b in w.buildings:
		if not (b.complete and b.def.has("production") and b.free_slots() > 0 and b.prod_blocker() == "" and w.pool_allows(b)):
			continue
		var j: String = KIND_JOB.get(b.prod_def().get("job", ""), "")
		if j == "" or j == "bauer" or _count(w, j) >= _workplaces(w, b.prod_def().get("job", "")):
			continue
		for id in b.prod_def().get("outputs", {}):
			if _wanted(w, str(id)):
				return j
	return ""


## Wird die Ware gebraucht? Unter dem Mindestvorrat, unter der Lagergrenze oder noch Platz im Lager.
func _wanted(w, id: String) -> bool:
	if not Data.resources.has(id):
		return false
	var mn := int(limits(int(w.island_id), id)[0])
	if mn > 0 and Game.amount(id, w) < mn:
		return true
	var lim := int(w.store_limits.get(id, 0))
	if lim > 0:
		return Game.amount(id, w) < lim * 9 / 10
	return Game.space_for(id, w) > 0


## Ware unter dem Mindestvorrat: {job, why} des Berufs, der sie herstellt.
func _min_job(w) -> Dictionary:
	var mm: Dictionary = minmax.get(str(int(w.island_id)), {})
	for id in mm:
		var mn := int(mm[id][0])
		if mn <= 0 or Game.amount(id, w) + incoming(int(w.island_id), id) >= mn:
			continue
		# Lieferkette rückwärts: erst die Vorprodukte, dann die Werkstatt, Rohstoffe nur, wenn die Natur etwas hergibt
		var r := trace(w, str(id), 0, {})
		if r.has("job") and _count(w, r.job) < 1 + w.settlers.size() / 4:
			var chain: String = r.why
			if chain == Data.resource_name(str(id)):
				return {"job": r.job, "why": tr("%s unter dem Mindestvorrat") % chain}
			return {"job": r.job, "why": tr("%s unter dem Mindestvorrat, es fehlt: %s") % [Data.resource_name(str(id)), chain]}
		if r.has("block"):
			_note_block(w, "min:" + str(id), str(r.block))
	return {}


## Beruf für jemanden, der einen Tag frei war: Hauptaufgabe, dann Mindestvorräte, dann Werkstatt mit Arbeit.
func _long_free_job(w) -> String:
	for j in task_jobs(w):
		if _count(w, j) < task_target(w, j):
			return j
	var mj := _min_job(w)
	if not mj.is_empty():
		return str(mj.job)
	return _workshop_job(w)


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
	var tg: Dictionary = _plan.get(int(w.island_id), {})
	var over := func(j: String) -> bool:
		if tg.is_empty():
			return _surplus(w, j) and not j in FOOD_JOBS and j != "holzfaeller"
		return _count(w, j) > int(tg.get(j, {}).get("n", 0))
	var spare := adults.filter(func(s): return JobDesk.may(s, "verwalter") and over.call(s.job))
	if not spare.is_empty():
		return _pick(w, spare, job)
	if src != "hard":
		return null
	var safe := func(s): return not s.job in FOOD_JOBS and s.job != "holzfaeller" and s.job != "frei"
	var mine := adults.filter(func(s): return safe.call(s) and JobDesk.may(s, "verwalter"))
	if not mine.is_empty():
		return _pick(w, mine, job)
	var theirs := adults.filter(func(s): return safe.call(s))
	if not theirs.is_empty():
		return _pick(w, theirs, job)
	return null


# ---------------------------------------------------------------- Überstunden im Notfall
## Essen oder Wärme lassen sich nicht sichern, weil niemand mehr frei ist: Überstunden, reicht das nicht,
## Schichtarbeit für die Leute dieses Berufs (Admin-Anordnungen gelten für den Beruf).
func _emergency(w, need: Dictionary) -> void:
	var job: String = need.job
	if job in FOOD_JOBS:  # Essen: der Nahrungsberuf mit den meisten Leuten, in dem es etwas zu holen gibt
		for j in FOOD_JOBS:
			if _count(w, j) > _count(w, job) and _raw_block(w, j) == "":
				job = j
	if _count(w, job) < 1 or _raw_block(w, job) != "":
		return  # Überstunden helfen nicht, wenn nichts wächst
	_emerg[job] = Game.time_days
	if not Admin.ordered(job, "ot") and not Admin.protesting(job):
		Powers.decide("notfall", "ot:" + job, tr("Essen oder Wärme reichen nicht und niemand ist frei: Überstunden für die %s.") % Data.jobs[job].name,
			{"kind": "order", "job": job, "what": "ot", "on": true}, true)
	elif not Admin.ordered(job, "sh") and float(_emerg.get(job + ":since", Game.time_days)) < Game.time_days - 1.0:
		Powers.decide("notfall", "sh:" + job, tr("Überstunden reichen nicht: Schichtarbeit für die %s.") % Data.jobs[job].name,
			{"kind": "order", "job": job, "what": "sh", "on": true}, true)
	if not _emerg.has(job + ":since"):
		_emerg[job + ":since"] = Game.time_days


## Ist die Not seit 2 Tagen vorbei, beendet er seine Notfall-Anordnungen.
func _end_emergency() -> void:
	for job in _emerg.keys():
		if str(job).ends_with(":since"):
			continue
		if Game.time_days - float(_emerg[job]) < 2.0:
			continue
		_emerg.erase(job)
		_emerg.erase(job + ":since")
		if not Admin.auto_orders.has(job):
			continue
		if Admin.ordered(job, "ot") or Admin.ordered(job, "sh"):
			Powers.decide("notfall", "end:" + job, tr("Essen und Wärme sind wieder gesichert: Überstunden und Schichten der %s beendet.") % Data.jobs[job].name,
				{"kind": "order", "job": job, "what": "ot", "on": false}, true)
			Admin.set_shift(job, false, true)


# ---------------------------------------------------------------- Forschung (Befugnis „Forschung weiterführen“)
func _check_research(w) -> void:
	if not Powers.on("forschung") or Game.research.current != "":
		return
	if str(Game.research.get("next", "")) != "":
		return  # vorgemerkt: das Spiel macht selbst weiter
	for t in Planner.tech_order():
		if Planner._affordable(t):
			Powers.decide("forschung", "research", tr("Neue Forschung: %s.") % Data.techs[t].name, {"kind": "research", "tech": t})
			return


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


## Warum kein Nahrungsberuf hilft (Text für den Engpass).
func _food_block(w) -> String:
	var why := []
	for j in ["sammler", "fischer", "bauer"]:
		if Data.job_unlocked(j):
			var b := _raw_block(w, j)
			if b != "" and not b in why:
				why.append(b)
	return tr("Essen wird knapp, aber mehr Leute bringen gerade nichts: %s Lege Vorräte an (Räuchern, Backen) oder hol Essen per Schiff.") % " ".join(why)


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
const RAW_NODES := {"holzfaeller": ["baum"], "sammler": ["busch", "palme", "pilzkreis", "gewuerzstrauch"],
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
	if job == "sammler":  # nur, was in dieser Jahreszeit wächst (im Winter nichts, außer Palmen und Gewürzen)
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


## Warum fehlt die Ware? Folgt der Lieferkette rückwärts (Glas -> Glashütte -> Lehm -> Lehmgrube) und gibt
## den Beruf ganz vorne zurück, der wirklich etwas ändert: {job, why} oder {block: Text} oder {}.
## Erst die Vorprodukte, dann die Werkstatt selbst; Rohstoffe nur, wenn die Natur etwas hergibt.
func trace(w, id: String, depth := 0, seen: Dictionary = {}) -> Dictionary:
	if depth > 6 or seen.has(id):
		return {}
	seen[id] = true
	var name := Data.resource_name(id)
	var first_block := {}
	var any_maker := false
	for b in w.buildings:
		if not (b.complete and b.def.has("production") and not b.def.get("ships", false) and b.prod_def().get("outputs", {}).has(id)):
			continue
		any_maker = true
		if b.paused:
			if first_block.is_empty():
				first_block = {"block": tr("%s steht still (angehalten), darum fehlt %s.") % [b.def.name, name]}
			continue
		var p: Dictionary = b.prod_def()
		# Vorprodukte zuerst: fehlt eines, liegt dort die Ursache
		for res in p.get("inputs", {}):
			if Game.amount(res, w) >= int(p.inputs[res]) * 2:
				continue
			var r := trace(w, str(res), depth + 1, seen)
			if r.has("job"):
				if depth == 0 or not str(r.why).contains("→"):
					r.why = "%s → %s" % [name, r.why] if r.why != "" else name
				return r
			if r.has("block") and first_block.is_empty():
				first_block = r
		var blk: String = b.prod_blocker()
		if blk != "":
			if first_block.is_empty() and not blk.begins_with(tr("Es fehlt")):
				first_block = {"block": "%s: %s." % [b.def.name, blk]}
			continue
		var kind: String = p.get("job", "")
		var j: String = KIND_JOB.get(kind, "")
		if j == "" or not Data.job_unlocked(j):
			continue
		if not w.pool_allows(b):
			if first_block.is_empty():
				first_block = {"block": tr("%s braucht Fachkräfte ab Hausstufe %d (%s), darum fehlt %s.") % [b.def.name, b.worker_level(), HouseNeeds.level_name(b.worker_level()), name]}
			continue
		if b.free_slots() > 0 and _count(w, j) < _workplaces(w, kind):
			return {"job": j, "why": name}
		if first_block.is_empty():
			first_block = {"block": tr("%s arbeitet schon voll. Für mehr %s baue eine weitere.") % [b.def.name, name]}
	if RAW_JOB.has(id):
		var j: String = RAW_JOB[id]
		if not Data.job_unlocked(j):
			return first_block
		var rb := _raw_block(w, j)
		if rb == "":
			return {"job": j, "why": name}
		return {"block": tr("%s fehlt: %s") % [name, rb]}
	if not any_maker:
		var bt := _maker_type(id)
		if bt == "":
			return first_block
		if Game.is_unlocked(bt):
			return {"block": tr("%s stellt niemand her: baue %s.") % [name, Data.buildings[bt].name]}
		return {"block": tr("%s stellt niemand her: %s ist noch nicht erforscht.") % [name, Data.buildings[bt].name]}
	return first_block


## Gebäudeart, die die Ware herstellt (für den Hinweis „baue …“).
func _maker_type(id: String) -> String:
	for t in Data.buildings:
		var d: Dictionary = Data.buildings[t]
		if d.get("buildable", true) and d.has("production") and d.production.get("outputs", {}).has(id):
			return t
	return ""


## Engpass merken (für das Fenster Verwalter und das Log; Meldung höchstens einmal am Tag über Game.notify).
func _note_block(w, key: String, text: String) -> void:
	var id := int(w.island_id)
	if not blocks.has(id):
		blocks[id] = {}
	if _old_blocks.get(id, {}).get(key, "") != text and blocks[id].get(key, "") != text:
		Admin.add_log(who() + ": " + text)
	blocks[id][key] = text


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
	_next = 0.0
	_moved = {}
	_free_since = {}
	_emerg = {}
	_day_stats = {}
	research_info = ""
	_route_next = 0.0
	_net_next = 0.0
	changed.emit()


func _on_save(d: Dictionary) -> void:
	d["steward"] = {"on": on, "offered": offered, "offered_routes": offered_routes, "offered_net": offered_net, "offered_automat": offered_automat, "net_on": net_on, "minmax": minmax.duplicate(true), "tasks": tasks.duplicate(true)}


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
	var tk = e.get("tasks", {})
	if tk is Dictionary:
		for k in tk:
			var v = tk[k]
			var keys: Array = (v if v is Array else [v]).map(func(x): return str(x)).filter(func(x): return TASKS.has(x))
			if not keys.is_empty():
				tasks[str(k)] = keys  # früher nur eine Aufgabe als Text
	changed.emit()


func autotest_setup(args: Dictionary, main) -> void:
	if args.has("stewardtest"):
		if str(args.stewardtest) == "routes":
			await StewardTest.routes(main)
		elif str(args.stewardtest) == "net":
			await StewardTest.net(main)
		elif str(args.stewardtest) == "busy":
			await StewardTest.busy(main)
		elif str(args.stewardtest).begins_with("task"):
			await StewardTest.task(main, str(args.stewardtest))
		else:
			await StewardTest.run(main, str(args.stewardtest))


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
	if Powers.mode_of("waren") == Powers.FRAGEN and Powers.proposed(key):
		return false
	var text := tr("Schiff bringt %s von %s nach %s (%s).") % [", ".join(PackedStringArray(parts)),
		Sea.meta(from_id).get("name", "?"), Sea.meta(to_id).get("name", "?"), why]
	Powers.decide("waren", key, text, {"kind": "trip", "from": from_id, "to": to_id, "goods": goods, "why": why})
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


func route_tick() -> void:
	var settled: Array = Sea.settled_islands().map(func(m): return int(m.id))
	for key in minmax.keys():
		var to_id := int(key)
		if not to_id in settled:
			continue
		var w = Sea.worlds.get(to_id)
		for id in minmax[key].keys():
			var lim := limits(to_id, id)
			var have: int = Game.amount(id, w) + incoming(to_id, id)
			# Unter dem Mindeststand: holen (bis zum Höchststand, sonst doppelter Mindeststand)
			if lim[0] > 0 and have < lim[0]:
				var want: int = mini((lim[1] if lim[1] > 0 else lim[0] * 2) - have, _room_below_max(to_id, id))
				var srcs := settled.filter(func(i): return i != to_id and _spare(i, id) > 0)
				srcs.sort_custom(func(a, b): return _over_max(a, id) > _over_max(b, id) or (_over_max(a, id) == _over_max(b, id) and _spare(a, id) > _spare(b, id)))
				for src in srcs:
					if _send(src, to_id, id, mini(want, _spare(src, id)), tr("unter dem Mindeststand")):
						return  # eine Fahrt je Runde
			# Über dem Höchststand: Überschuss wegbringen
			if lim[1] > 0 and Game.amount(id, w) - outgoing(to_id, id) > lim[1]:
				var extra: int = Game.amount(id, w) - outgoing(to_id, id) - lim[1]
				var dsts := settled.filter(func(i): return i != to_id and _room_below_max(i, id) > 0)
				dsts.sort_custom(func(a, b): return Sea.is_main(Sea.worlds.get(a)) and not Sea.is_main(Sea.worlds.get(b)))
				for dst in dsts:
					if _send(to_id, dst, id, mini(extra, _room_below_max(dst, id)), tr("über dem Höchststand")):
						return


func _over_max(island_id: int, id: String) -> int:
	var lim := limits(island_id, id)
	if lim[1] <= 0:
		return 0
	return maxi(0, Game.amount(id, Sea.worlds.get(island_id)) - lim[1])


## Wie viel eine Insel noch aufnehmen soll: bis zu ihrem Höchststand, ohne Höchststand so viel ins Lager passt.
func _room_below_max(island_id: int, id: String) -> int:
	var w = Sea.worlds.get(island_id)
	if w == null:
		return 0
	var lim := limits(island_id, id)
	var room: int = Game.space_for(id, w) - incoming(island_id, id)
	if lim[1] > 0:
		room = mini(room, lim[1] - Game.amount(id, w) - incoming(island_id, id))
	return room



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


## Inseln ohne Rundfunkanstalt (Namen), für den Hinweis unter Inseln.
func islands_without_radio() -> Array:
	var out := []
	for m in Sea.settled_islands():
		var w = Sea.worlds.get(int(m.id))
		if w != null and not has_radio(w):
			out.append(Sea.island_name(w))
	return out


func set_net(v: bool) -> void:
	net_on = v
	AiRule.player_changed("net")
	Game.notify(tr("Inselverbund an: die Heimatinsel verarbeitet, die anderen Inseln liefern.") if v else tr("Inselverbund aus: jede Insel versorgt sich selbst."), "anker", "verwaltung")
	changed.emit()


## Früher: ab Elektrizität ersetzte ein Automat den Verwalter. Seit 2026-10-29 gibt es nur den Verwalter.
func automat_mode() -> bool:
	return false


## Wer steuert gerade? Für Meldungen.
func who() -> String:
	if AiRule.ki():
		return tr("KI")
	return tr("Verwalter")


func has_automaton(w) -> bool:
	for b in w.buildings:
		if b.complete and b.def.get("automaton", false):
			return true
	return false


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


## Rohstoffe, die der Heimatinsel für ihre Werkstätten fehlen (unter 20 im Lager).
func _home_wants(hw) -> Array:
	var out := []
	if hw == null:
		return out
	for b in hw.buildings:
		if b.complete and b.def.has("production"):
			for id in b.prod_def().get("inputs", {}):
				if RAW_JOB.has(id) and not id in out and Game.amount(id, hw) < 20:
					out.append(id)
	return out


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
	"gewuerze": {"name": "Gewürze", "icon": "gewuerze", "goods": ["gewuerze"], "jobs": ["sammler"], "nodes": ["gewuerzstrauch"]},
	"jagd": {"name": "Fleisch und Felle", "icon": "fleisch", "goods": ["fleisch", "felle"], "jobs": ["jaeger"], "nodes": []},
	"metall": {"name": "Erz und Metall", "icon": "eisen", "goods": ["erz", "kohle", "eisen", "werkzeug", "stahl"], "jobs": ["steinmetz", "handwerker"], "nodes": ["erzader"]},
	"gold": {"name": "Gold", "icon": "gold", "goods": ["gold"], "jobs": ["steinmetz"], "nodes": ["goldader"]},
	"forschung": {"name": "Forschung", "icon": "wissen", "goods": [], "jobs": ["forscher"], "nodes": []},
}
var tasks: Dictionary = {}  # Insel-ID (String) -> Array mit Schlüsseln aus TASKS


## Nur für die Übersetzung (tools/i18n.py findet tr-Texte): die Namen aus TASKS.
func _task_names() -> Array:
	return [tr("Holz und Bretter"), tr("Stein und Ziegel"), tr("Getreide und Brot"), tr("Fisch"), tr("Beeren"), tr("Pilze"),
		tr("Kokosnüsse"), tr("Gewürze"), tr("Fleisch und Felle"), tr("Erz und Metall"), tr("Gold"), tr("Forschung")]


## Die Hauptaufgaben einer Insel, in der Reihenfolge von TASKS.
func tasks_of(w) -> Array:
	if w == null:
		return []
	var have: Array = tasks.get(str(int(w.island_id)), [])
	return TASKS.keys().filter(func(k): return k in have)


func task_names(w) -> String:
	return ", ".join(PackedStringArray(tasks_of(w).map(func(k): return tr(TASKS[k].name))))


## Eine Aufgabe an- oder abwählen; key "" löscht alle.
func toggle_task(island_id: int, key: String) -> void:
	var have: Array = tasks.get(str(island_id), []).duplicate()
	if key == "" or not TASKS.has(key):
		have.clear()
	elif key in have:
		have.erase(key)
	else:
		have.append(key)
	set_tasks(island_id, have)


func set_tasks(island_id: int, keys: Array) -> void:
	var have := keys.filter(func(k): return TASKS.has(k))
	if have.is_empty():
		tasks.erase(str(island_id))
	else:
		tasks[str(island_id)] = have
		var w = Sea.worlds.get(island_id)
		Game.notify(tr("Hauptaufgabe für %s: %s. Der Verwalter setzt die passenden Berufe ein.") % [Sea.meta(island_id).get("name", "?"), task_names(w) if w != null else ""], "person", "verwaltung")
	AiRule.player_changed("task")
	changed.emit()


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
