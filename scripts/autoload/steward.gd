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
	Game.notify(tr("Der Verwalter steuert jetzt die Berufe auf allen Inseln.") if v else tr("Der Verwalter steuert die Berufe nicht mehr."), "person", "verwaltung")
	changed.emit()


## Der Spieler hat einem Siedler selbst einen Beruf gegeben: der Verwalter überstimmt das eine Weile nicht.
func player_set(s) -> void:
	if s != null:
		locks[int(s.id)] = Game.time_days + LOCK_DAYS


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
	_next = 0.0
	_route_next = 0.0
	_net_next = 0.0
	changed.emit()


func _on_save(d: Dictionary) -> void:
	d["steward"] = {"on": on, "offered": offered, "offered_routes": offered_routes, "offered_net": offered_net, "offered_automat": offered_automat, "net_on": net_on, "locks": locks.duplicate(), "minmax": minmax.duplicate(true)}


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
	Game.notify(tr("Inselverbund an: die Heimatinsel verarbeitet, die anderen Inseln liefern.") if v else tr("Inselverbund aus: jede Insel versorgt sich selbst."), "anker", "verwaltung")
	changed.emit()


func automat_mode() -> bool:
	return Game.is_researched("elektrizitaet")


## Wer steuert gerade? Für Meldungen.
func who() -> String:
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
	# 1. Essen zur Heimatinsel
	if fd >= 0.0 and fd + _incoming_food_days(hw) < HOME_FOOD_DAYS:
		var src := _supplier(hw, "food")
		if src != -1 and _send_goods(src, home_id, _food_load(Sea.worlds.get(src)), tr("Essen für die Heimatinsel")):
			return
	# 2. Brennholz zur Heimatinsel
	if fuel_days(hw) < HOME_FUEL_DAYS and incoming(home_id, "holz") == 0:
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
