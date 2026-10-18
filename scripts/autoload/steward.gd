extends Node
## Verwalter-Steuerung (josh 2026-10-17, Testversion): Ist die zweite Insel besiedelt, bietet ein Fenster an,
## dass der Verwalter die Berufe auf allen Inseln (auch der Heimatinsel) nach dem Bedarf steuert:
## 1. immer genug zu essen, 2. Wärme (Brennholz für Herbst und Winter), 3. Lager bis zur eingestellten
## Höchstmenge füllen (World.store_limits), dazu Werkstätten besetzen und Baustellen. Inseln mit mehr als
## MAX_POP Siedlern kann er nicht steuern. Ändert der Spieler einen Beruf von Hand, lässt der Verwalter
## diesen Siedler LOCK_DAYS Tage in Ruhe (player_set). Keine Verwaltung nötig; an- und abschaltbar im
## Fenster Inseln.

signal offer(kind: String)  # Hud zeigt das Angebots-Fenster
signal changed

const MAX_POP := 60
const LOCK_DAYS := 2.0
const TICK_DAYS := 0.25
const MOVES_PER_TICK := 2
const KIND_JOB := {"kueche": "koch", "handwerk": "handwerker", "stein": "steinmetz", "stall": "bauer"}
## Rohstoffe und wer sie holt (Werkstattwaren findet _producer über die Gebäude)
const RAW_JOB := {"holz": "holzfaeller", "stein": "steinmetz", "beeren": "sammler", "pilze": "sammler",
	"kokos": "sammler", "fisch": "fischer", "weizen": "bauer", "aepfel": "bauer", "fleisch": "jaeger", "felle": "jaeger"}
const FOOD_JOBS := ["bauer", "fischer", "sammler", "jaeger"]
## Berufe, die der Verwalter nie umbesetzt
const KEEP := ["verwalter", "seemann", "baumeister", "forscher"]

var on := false        # Verwalter steuert die Berufe
var offered := false   # Angebot schon gezeigt
var offered_routes := false  # Hinweis „Verwalter fährt Waren“ (3. Insel) schon gezeigt
var locks: Dictionary = {}  # Siedler-ID -> Spieltag, bis zu dem der Verwalter ihn in Ruhe lässt
var _next := 0.0


func _ready() -> void:
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)


# ---------------------------------------------------------------- Abfragen
func unlocked() -> bool:
	return Sea.settled_islands().size() >= 2


func active() -> bool:
	return on and unlocked()


## Steuert der Verwalter diese Insel? "" = ja, sonst der Grund.
func blocked_on(w) -> String:
	if w == null or not is_instance_valid(w):
		return "?"
	if w.settlers.size() > MAX_POP and not automat_mode() and not has_automaton(w):
		return tr("mehr als %d Siedler, das schafft der Verwalter nicht. Ein Rechenautomat hilft.") % MAX_POP
	return ""


func set_on(v: bool) -> void:
	on = v
	offered = true
	AiRule.player_changed("on")
	Game.notify(tr("Der Verwalter steuert jetzt die Berufe auf allen Inseln.") if v else tr("Der Verwalter steuert die Berufe nicht mehr."), "person", "verwaltung")
	changed.emit()


## Der Spieler hat einem Siedler selbst einen Beruf gegeben: der Verwalter überstimmt das eine Weile nicht.
func player_set(s) -> void:
	if s != null:
		locks[int(s.id)] = Game.time_days + (AiRule.OVERRIDE_DAYS if AiRule.ki() else LOCK_DAYS)
		AiRule.player_changed("job:%d" % int(s.id))


func locked(s) -> bool:
	return float(locks.get(int(s.id), -1.0)) > Game.time_days


# ---------------------------------------------------------------- Ablauf
func _process(_delta: float) -> void:
	if Game.world == null or Game.speed == 0:
		return
	if not offered and unlocked():
		offered = true
		offer.emit("jobs")
	if not offered_routes and routes_unlocked():
		offered_routes = true
		offer.emit("routes")
	if not offered_net and net_unlocked():
		offered_net = true
		offer.emit("net")
	if not offered_automat and automat_mode():
		offered_automat = true
		offer.emit("automat")
	if Game.time_days < _next:
		return
	_next = Game.time_days + TICK_DAYS
	if not active():
		return
	for w in Sea.all_worlds():
		if blocked_on(w) == "":
			tick(w)
	if routes_unlocked() and Game.time_days >= _route_next:
		_route_next = Game.time_days + ROUTE_TICK
		route_tick()
	if net_active() and Game.time_days >= _net_next:
		_net_next = Game.time_days + ROUTE_TICK
		net_tick()


func tick(w) -> void:
	if AiRule.si() or (AiRule.ki() and not Sea.is_main(w) and AiRule.automated(w)):
		return  # Superintelligenz: Menschen sind ihr egal; automatisierte Inseln brauchen keine Siedler mehr
	for i in MOVES_PER_TICK:
		var need := needed(w)
		if need.is_empty():
			return
		var pick = _take_worker(w, need)
		if pick == null:
			return
		var old: String = pick.job_name()
		pick.set_job(need.job)
		locks[int(pick.id)] = Game.time_days + 0.5  # nicht gleich wieder umsetzen
		Game.notify_at(w, who() + ": " + tr("%s arbeitet jetzt als %s (%s, vorher %s).") % [pick.display_name, Data.jobs[need.job].name, need.why, old], "person", "verwaltung")


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


## Was braucht die Insel am dringendsten? {job, why, hard} oder {} (hard = darf Arbeiter aus anderen Berufen holen)
func needed(w) -> Dictionary:
	var adults := _adults(w)
	if adults.is_empty():
		return {}
	var pop: int = w.settlers.size()
	var net := net_active()
	var home: bool = net and Sea.is_main(w)
	# 1. Essen: unter 3 Tagen Vorrat (hart unter 1 Tag). Im Inselverbund kommt das Essen der
	# Heimatinsel von den anderen Inseln (nur in echter Not selbst holen); die anderen Inseln halten 6 Tage.
	var fd := Game.food_days(w)
	var food_goal := 3.0
	if home and _supplier(w, "food") != -1:
		food_goal = 1.0
	elif net and not Sea.is_main(w):
		food_goal = NET_FOOD_DAYS
	if fd >= 0.0 and fd < food_goal:
		return {"job": _food_job(w), "why": tr("zu wenig Essen") if fd < 3.0 else tr("Essen für die Heimatinsel"), "hard": fd < 1.5}
	# 2. Wärme: Brennholz für mindestens 4 Tage, solange es kalt ist oder wird
	var fuel_goal := 4.0
	if home and _supplier(w, "holz") != -1:
		fuel_goal = 1.0
	if _cold_season() and fuel_days(w) < fuel_goal and Data.job_unlocked("holzfaeller"):
		return {"job": "holzfaeller", "why": tr("Brennholz für den Winter"), "hard": Seasons.season() >= 2 and fuel_days(w) < 1.5}
	# 3. Baustellen ohne Baumeister
	var sites: Array = w.construction_sites()
	if not sites.is_empty() and _count(w, "baumeister") < 1 + sites.size() / 3:
		return {"job": "baumeister", "why": tr("Baustellen"), "hard": false}
	# 3b. Hauptaufgabe der Insel (vom Spieler gewählt): die passenden Berufe besetzen
	var tn := task_need(w)
	if not tn.is_empty():
		return tn
	# 4. Werkstätten, die arbeiten könnten, aber niemand ist da
	for b in w.buildings:
		if b.complete and b.def.has("production") and b.free_slots() > 0 and b.occupants.is_empty() and b.prod_blocker() == "":
			var j: String = KIND_JOB.get(b.prod_def().get("job", ""), "")
			if j != "" and w.pool_allows(b) and _count(w, j) < _workplaces(w, b.prod_def().get("job", "")):
				return {"job": j, "why": tr("%s steht still") % b.def.name, "hard": false}
	# 4b. Im Inselverbund: genug Forscher auf der Heimatinsel (alle freien Forschungsplätze besetzt)
	if home and Game.research.current != "":
		for b in w.buildings:
			if b.complete and b.def.has("research") and b.free_slots() > 0 and w.pool_allows(b):
				return {"job": "forscher", "why": tr("freie Forschungsplätze"), "hard": false}
	# 4c. Im Inselverbund: die anderen Inseln liefern die Rohstoffe, die der Heimatinsel fehlen
	if net and not Sea.is_main(w):
		var hw = Sea.main_world()
		for id in _home_wants(hw):
			var j := str(RAW_JOB.get(id, ""))
			if j != "" and Data.job_unlocked(j) and _count(w, j) < 1 + pop / 6:
				return {"job": j, "why": tr("%s für die Heimatinsel") % Data.resource_name(id), "hard": false}
	# 5. Lager bis zur eingestellten Höchstmenge füllen
	var lim: Dictionary = w.store_limits
	for id in lim:
		var mx := int(lim[id])
		if mx <= 0 or Game.amount(id, w) >= mx * 9 / 10:
			continue
		if home and RAW_JOB.has(id):
			continue  # Rohstoffe holen die anderen Inseln
		var j := _producer(w, str(id))
		if j != "" and Data.job_unlocked(j) and _count(w, j) < 1 + pop / 8:
			return {"job": j, "why": tr("Lager mit %s auffüllen") % Data.resource_name(str(id)), "hard": false}
	return {}


func _workplaces(w, kind: String) -> int:
	var n := 0
	for b in w.buildings:
		if b.complete and b.def.has("production") and b.prod_def().get("job", "") == kind:
			n += b.slots()
	return n


func _food_job(w) -> String:
	var fields: Array = w.buildings.filter(func(b): return b.complete and b.def.has("farm"))
	if not fields.is_empty() and _count(w, "bauer") < 1 + fields.size() / 4:
		return "bauer"
	if Data.job_unlocked("jaeger") and w.animals.size() > 6 and _count(w, "jaeger") < 1:
		return "jaeger"
	return "fischer" if _count(w, "fischer") <= _count(w, "sammler") else "sammler"


## Wer stellt die Ware her? Rohstoffe aus RAW_JOB, sonst der Beruf einer Werkstatt, die sie herstellt.
func _producer(w, id: String) -> String:
	if RAW_JOB.has(id):
		return RAW_JOB[id]
	for b in w.buildings:
		if b.complete and b.def.has("production") and b.prod_def().get("outputs", {}).has(id):
			return KIND_JOB.get(b.prod_def().get("job", ""), "")
	return ""


## Ein Beruf ist überzählig, wenn alle seine Waren das Lagerziel erreicht haben oder das Lager dafür voll ist.
func _surplus(w, job: String) -> bool:
	if job in task_jobs(w):
		return false  # Hauptaufgabe der Insel: diese Berufe bleiben
	if net_active() and Sea.is_main(w) and job in RAW_JOB.values() and Sea.settled_islands().size() >= 2:
		return true  # Heimatinsel im Inselverbund: nur noch Endverarbeitung
	var goods := []
	for id in RAW_JOB:
		if RAW_JOB[id] == job:
			goods.append(id)
	if goods.is_empty():
		return false
	for id in goods:
		var mx := int(w.store_limits.get(id, 0))
		if mx > 0 and Game.amount(id, w) < mx:
			return false
		if mx <= 0 and Game.space_for(id, w) > 0:
			return false
	return true


## Holt einen Siedler für den Beruf: zuerst Freie, dann Überzählige; bei harter Not auch andere.
func _take_worker(w, need: Dictionary):
	var job: String = need.job
	var adults := _adults(w).filter(func(s): return s.job != job and not locked(s) and not s.job in KEEP)
	var free := adults.filter(func(s): return s.job == "frei")
	if not free.is_empty():
		return AiJobs._best_for(free, job)
	var spare := adults.filter(func(s): return _surplus(w, s.job))
	if not spare.is_empty():
		return AiJobs._best_for(spare, job)
	if need.get("task", false):
		# Hauptaufgabe: aus Berufen außerhalb der Aufgabe holen; Essen holen nur, wenn genug zu essen da ist
		var tj := task_jobs(w)
		var fed: bool = Game.food_days(w) >= 4.0
		var cand := adults.filter(func(s): return not s.job in tj and (fed or not s.job in FOOD_JOBS))
		if not cand.is_empty():
			return AiJobs._best_for(cand, job)
	if need.get("hard", false):
		var others := adults.filter(func(s): return not s.job in FOOD_JOBS)  # Essen holen bleibt immer besetzt
		if not others.is_empty():
			return AiJobs._best_for(others, job)
	return null


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	on = false
	offered = false
	offered_routes = false
	offered_net = false
	offered_automat = false
	net_on = true
	locks = {}
	minmax = {}
	tasks = {}
	_next = 0.0
	_route_next = 0.0
	_net_next = 0.0
	changed.emit()


func _on_save(d: Dictionary) -> void:
	d["steward"] = {"on": on, "offered": offered, "offered_routes": offered_routes, "offered_net": offered_net, "offered_automat": offered_automat, "net_on": net_on, "locks": locks.duplicate(), "minmax": minmax.duplicate(true), "tasks": tasks.duplicate(true)}


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
	var l = e.get("locks", {})
	if l is Dictionary:
		for k in l:
			locks[int(k)] = float(l[k])
	changed.emit()


func autotest_setup(args: Dictionary, main) -> void:
	if args.has("stewardtest"):
		if str(args.stewardtest) == "routes":
			await StewardTest.routes(main)
		elif str(args.stewardtest) == "net":
			await StewardTest.net(main)
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
	return Sea.settled_islands().size() >= 3


func limits(island_id: int, id: String) -> Array:
	var e: Dictionary = minmax.get(str(island_id), {})
	var v = e.get(id, [0, 0])
	return [int(v[0]), int(v[1])]


func set_limits(island_id: int, id: String, mn: int, mx: int) -> void:
	mn = maxi(0, mn)
	mx = maxi(0, mx)
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


func _free_ship(from_id: int, to_id: int) -> Dictionary:
	var best := {}
	var best_d := INF
	for sh in Sea.ships:
		if sh.state != "dock" or not sh.route.is_empty() or Sea.is_trip(sh) or not sh.cargo.is_empty():
			continue
		if not Sea.can_visit(sh.type, from_id) or not Sea.can_visit(sh.type, to_id):
			continue
		Sea.fill_crew(sh)
		if Sea.ship_blocker(sh) != "":
			continue
		var d := 0.0 if int(sh.at) == from_id else Sea.voyage_days(int(sh.at), from_id, sh.type)
		if d < best_d:
			best_d = d
			best = sh
	return best


## Verfügbar zum Abgeben: über dem eigenen Mindeststand (und nicht schon abgeholt).
func _spare(island_id: int, id: String) -> int:
	var w = Sea.worlds.get(island_id)
	if w == null:
		return 0
	var lim := limits(island_id, id)
	return Game.amount(id, w) - outgoing(island_id, id) - lim[0]


func _send(from_id: int, to_id: int, id: String, n: int, why: String) -> bool:
	return _send_goods(from_id, to_id, {id: n}, why)


## Schickt ein freies Schiff mit mehreren Waren (in der Reihenfolge von goods, bis der Laderaum voll ist).
func _send_goods(from_id: int, to_id: int, goods: Dictionary, why: String) -> bool:
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
	Game.notify(who() + ": " + tr("die %s bringt %s von %s nach %s (%s).") % [sh.name, ", ".join(PackedStringArray(parts)),
		Sea.meta(from_id).get("name", "?"), Sea.meta(to_id).get("name", "?"), why], "anker", "verwaltung")
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
				var want: int = (lim[1] if lim[1] > 0 else lim[0] * 2) - have
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
## Ab Papier reden die Verwalter der Inseln miteinander (net_on, abschaltbar): die Heimatinsel macht nur noch
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
	return active() and net_on and net_unlocked()


func set_net(v: bool) -> void:
	net_on = v
	AiRule.player_changed("net")
	Game.notify(tr("Inselverbund an: die Heimatinsel verarbeitet, die anderen Inseln liefern.") if v else tr("Inselverbund aus: jede Insel versorgt sich selbst."), "anker", "verwaltung")
	changed.emit()


func automat_mode() -> bool:
	return Game.is_researched("elektrizitaet")


## Wer steuert gerade? Für Meldungen.
func who() -> String:
	if AiRule.ki():
		return tr("KI")
	return tr("Automat") if automat_mode() else tr("Verwalter")


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


func _ids() -> Array:
	return Sea.settled_islands().map(func(m): return int(m.id))


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
