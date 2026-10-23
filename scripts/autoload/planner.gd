extends Node
## Planungsautomat (josh 2026-10-21, Testversion /neu/): Ab der Industrialisierung steht vor der Verwaltung ein
## Automat (Gebäude `planautomat`, "planner": true, nur eins, höchstens OFFICE_DIST Felder von der Verwaltung).
## Mit ihm legt der Verwalter selbst fest, was wo gebaut wird, welche Waren entstehen, welche Schiffe Waren und
## Siedler fahren, und er teilt Berufe zu. Er läuft, solange der Automat steht, der Verwalter die Berufe steuert
## (Steward.on), der Schalter `on` an ist und die KI noch nicht herrscht (AiRule.ki()).
## Alle TICK_DAYS entscheidet er je Insel genau einen Schritt, in fester Rangfolge (die erste Lücke gewinnt):
##   a. Bedürfnisse: Essen (Tage, Vitamine), Brennstoff in der kalten Zeit, Bedürfnisse der Häuser;
##   b. Wintervorrat: ab Sommer haltbares Essen und Brennholz/Kohle für den ganzen Winter;
##   c. Wohnen: fehlen Arbeitskräfte und Betten, baut er das beste Haus; wächst die Insel zu langsam, holt er
##      freie Siedler per Schiff von einer anderen Insel;
##   d. Lager, wenn es fast voll ist;
##   e. Warenketten: was offene Baustellen, die Forschung und die Hauptaufgabe der Insel brauchen; fehlende
##      Werkstätten bauen, stillstehende besetzen, Rohstoffe von anderen Inseln holen;
## dazu einmal je Runde f. Forschung: forscht nichts, wählt er die günstigste Forschung auf dem Weg zur KI.
## Umsetzen müssen es die Siedler: je Insel höchstens eine Baustelle zur Zeit, gebaut wird erst, wenn das
## Material auf der Insel liegt oder schon unterwegs ist (sonst bestellt er es per Schiff oder lässt es
## herstellen), und für jede Baustelle sorgt er für einen Baumeister. Jede Entscheidung meldet er einmal
## („Automat: …“, Art „verwaltung“); der letzte Plan je Insel steht im Fenster Verwalter, Reiter Inseln.

signal changed

const TICK_DAYS := 0.5
const MIN_AGE := 4  # Industrialisierung
const OFFICE_DIST := 3  # so viele Felder Abstand zur Verwaltung höchstens
const FOOD_DAYS := 3.0  # darunter ist Essen knapp
const FOOD_SHIP_DAYS := 2.0  # darunter kommt Essen per Schiff
const DONOR_FOOD_DAYS := 6.0  # so viel Essen behält eine Insel, die abgibt
const VIT_LOW := 45.0  # mittlere Vitamine der Siedler, darunter fehlen Vitamine
const FUEL_DAYS := 2.0  # Brennstoff in der kalten Zeit
const WINTER_FOOD := 1.3  # haltbares Essen für so viele Winter (Jahreszeiten)
const STORE_FULL := 0.85
const STALL_DAYS := 3.0  # so lange ohne Zuwachs, dann kommen Siedler per Schiff
const KEEP_SEND := 20  # so viel behält eine Insel von einer Ware, die sie für den Bau abgibt
const SAY_DAYS := 2.0  # gleiche Meldung höchstens so oft
const WINTER_GUESS := {"": 1.3, "mild": 0.6, "normal": 1.0, "hart": 1.4, "bitter": 1.8, "streng": 1.6}
## Häuser und Werkstätten, die Essen machen, in der Reihenfolge, in der der Automat sie baut
const FARMS := ["gewaechshaus", "obstgarten", "feld"]
const VITAMIN_FARMS := ["gewaechshaus", "obstgarten"]

var on := true  # Schalter des Spielers
var offered := false
var plans: Dictionary = {}  # Insel-ID (String) -> {need, step, day} letzte Entscheidung
var orders: Dictionary = {}  # Insel-ID (String) -> {type, why, day} Bauvorhaben, das auf Material wartet
var wanted_tech := ""  # Forschung, für die Material fehlt
var research_note := ""  # zuletzt gestartete Forschung (Anzeige)
var built := 0  # Baustellen des Automaten (Statistik)
var started := 0  # gestartete Forschungen
var sent := 0  # Schiffe mit Siedlern
var _grow: Dictionary = {}  # Insel-ID (String) -> [Tag, Siedler] des letzten Zuwachses
var _said: Dictionary = {}  # Insel-ID (String) -> [Text, Tag] der letzten Meldung
var _next := 0.0


func _ready() -> void:
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)


# ---------------------------------------------------------------- Gebäude und Freigabe
## Der fertige Planungsautomat (oder null).
func machine():
	for w in Sea.all_worlds():
		for b in w.buildings:
			if is_instance_valid(b) and b.complete and b.def.get("planner", false):
				return b
	return null


## Liegt ein Gebäude der Größe sz an Zelle c höchstens OFFICE_DIST Felder neben der fertigen Verwaltung?
func near_office(w, c: Vector2i, sz) -> bool:
	var o = Admin.office()
	if o == null or o.world != w:
		return false
	var osz := Vector2i(int(o.def.size[0]), int(o.def.size[1]))
	var gx: int = maxi(0, maxi(o.cell.x - (c.x + int(sz[0])), c.x - (o.cell.x + osz.x)))
	var gy: int = maxi(0, maxi(o.cell.y - (c.y + int(sz[1])), c.y - (o.cell.y + osz.y)))
	return maxi(gx, gy) <= OFFICE_DIST


## "" = der Planungsautomat darf (hier) gebaut werden, sonst was fehlt (Bauen-Fenster).
func build_reason() -> String:
	var miss := []
	if Game.current_age() < MIN_AGE:
		miss.append(tr("die Industrialisierung"))
	var o = Admin.office()
	if o == null:
		miss.append(tr("eine fertige Verwaltung"))
	if not miss.is_empty():
		return tr("Benötigt noch: %s") % ", ".join(PackedStringArray(miss))
	if Game.world != null and o.world != Game.world:
		return tr("Steht nur direkt vor der Verwaltung (auf %s).") % Sea.island_name(o.world)
	return ""


## "" = der Automat kann planen, sonst warum nicht (Fenster Verwalter).
func reason() -> String:
	if AiRule.ki():
		return tr("Die KI hat übernommen.")
	if Game.current_age() < MIN_AGE:
		return tr("Ab der Industrialisierung (Forschung Dampfmaschine).")
	if machine() == null:
		return tr("Baue den Planungsautomaten direkt vor die Verwaltung (Bauen, Reiter Wissen).")
	if not Steward.on:
		return tr("Dafür muss der Verwalter die Berufe steuern.")
	return ""


func active() -> bool:
	return on and reason() == ""


func set_on(v: bool) -> void:
	on = v
	offered = true
	if v and not Steward.on:
		Steward.set_on(true)
	Game.notify(tr("Der Planungsautomat plant jetzt Bauten, Waren und Routen.") if v else tr("Der Planungsautomat plant nicht mehr."), "wissen", "verwaltung")
	changed.emit()


func plan_of(w) -> Dictionary:
	return plans.get(str(int(w.island_id)), {}) if w != null else {}


# ---------------------------------------------------------------- Ablauf
func _process(_delta: float) -> void:
	if Game.world == null or Game.speed == 0 or Game.is_over:
		return
	if not offered and Game.current_age() >= MIN_AGE and not AiRule.ki() and machine() != null:
		offered = true
		Steward.offer.emit("planner")
	if Game.time_days < _next:
		return
	_next = Game.time_days + TICK_DAYS
	if active():
		tick()


func tick() -> void:
	for w in Sea.all_worlds():
		if not w.settlers.is_empty():
			decide(w)
	research_step()
	changed.emit()


## Ein Schritt für Insel w: die oberste Lücke in der Rangfolge. Gibt den Plan zurück {need, step, prio}.
func decide(w) -> Dictionary:
	var p := {}
	for f in [_need_food, _need_vitamins, _need_heat, _need_house, _winter_food, _winter_fuel, _housing, _storage, _chains]:
		p = f.call(w)
		if not p.is_empty():
			break
	if p.is_empty():
		p = {"need": tr("Alles versorgt"), "step": tr("nichts zu tun"), "prio": "ok"}
	_note_growth(w)
	_record(w, p)
	return p


func _record(w, p: Dictionary) -> void:
	var key := str(int(w.island_id))
	plans[key] = {"need": str(p.get("need", "")), "step": str(p.get("step", "")), "prio": str(p.get("prio", "")), "day": Game.time_days}
	if not p.get("say", false):
		return
	var text: String = tr("Automat: %s (%s)") % [p.step, p.need]
	var last: Array = _said.get(key, ["", -99.0])
	if text == str(last[0]) and Game.time_days - float(last[1]) < SAY_DAYS:
		return
	_said[key] = [text, Game.time_days]
	Game.notify_at(w, text, str(p.get("icon", "wissen")), "verwaltung")


func _plan(need: String, step: String, prio: String, say: bool = false, icon: String = "wissen") -> Dictionary:
	return {"need": need, "step": step, "prio": prio, "say": say, "icon": icon}


# ---------------------------------------------------------------- a. Bedürfnisse
func _need_food(w) -> Dictionary:
	var fd := Game.food_days(w)
	if fd < 0.0 or fd >= FOOD_DAYS:
		return {}
	var need: String = tr("Essen nur für %.1f Tage") % fd
	# 1. Essen per Schiff von einer Insel, die genug hat
	if fd < FOOD_SHIP_DAYS and Steward._incoming_food_days(w) < 1.0:
		var src = _food_donor(w)
		if src != null and Steward._send_goods(int(src.island_id), int(w.island_id), Steward._food_load(src), tr("Essen ist knapp")):
			return _plan(need, tr("Essen kommt per Schiff von %s") % Sea.island_name(src), "a", true, "anker")
	# 2. Leute in Nahrungsberufe
	var job := Steward._food_job(w)
	var s = _staff(w, job, tr("zu wenig Essen"), fd < 1.5)
	if s != null:
		return _plan(need, tr("%s arbeitet jetzt als %s") % [s.display_name, Data.jobs[job].name], "a", true, "person")
	# 3. Höfe und Felder
	var type := _farm_type(w, FARMS)
	if type != "":
		return _build(w, type, need, "a")
	return _plan(need, tr("alle Nahrungsberufe sind besetzt"), "a")


func _food_donor(w):
	var best = null
	for o in Sea.all_worlds():
		if o != w and Game.food_days(o) > DONOR_FOOD_DAYS and (best == null or Game.food_days(o) > Game.food_days(best)):
			best = o
	return best


## Ein Hof oder Feld aus list, wenn die Insel noch zu wenige hat (1 je 5 Siedler und einer mehr).
func _farm_type(w, list: Array) -> String:
	var n: int = w.buildings.filter(func(b): return b.def.has("farm")).size()
	if n >= 1 + w.settlers.size() / 5:
		return ""
	for t in list:
		if Data.buildings.has(t) and Game.is_unlocked(t):
			return t
	return ""


func _need_vitamins(w) -> Dictionary:
	var adults: Array = w.settlers.filter(func(s): return s.mind != null)
	if adults.is_empty():
		return {}
	var vit := 0.0
	for s in adults:
		vit += float(s.mind.vit)
	vit /= adults.size()
	if vit >= VIT_LOW:
		return {}
	var need: String = tr("zu wenig Vitamine (%d)") % int(vit)
	# Obst und Beeren: Sammler, dann Obstgarten oder Gewächshaus
	var have_fruit := false
	for b in w.buildings:
		if b.def.has("farm") and str(b.def.farm.get("yield", "")) == "aepfel":
			have_fruit = true
	if not have_fruit:
		for t in VITAMIN_FARMS:
			if Data.buildings.has(t) and Game.is_unlocked(t):
				return _build(w, t, need, "a")
	if w.nodes.any(func(n): return n.type == "busch") and Steward._count(w, "sammler") < 1 + w.settlers.size() / 8:
		var s = _staff(w, "sammler", tr("Vitamine"))
		if s != null:
			return _plan(need, tr("%s sammelt jetzt Beeren") % s.display_name, "a", true, "person")
	if have_fruit and Steward._count(w, "bauer") < 1:
		var s2 = _staff(w, "bauer", tr("Vitamine"))
		if s2 != null:
			return _plan(need, tr("%s pflegt jetzt den Obstgarten") % s2.display_name, "a", true, "person")
	return {}  # nichts zu tun: Vitamine kommen mit der Zeit


## Brennstoff: in Herbst und Winter mindestens FUEL_DAYS Tage.
func _need_heat(w) -> Dictionary:
	var s := Seasons.season()
	if s != Seasons.AUTUMN and s != Seasons.WINTER:
		return {}
	var fd := Steward.fuel_days(w)
	if fd >= FUEL_DAYS:
		return {}
	var need: String = tr("Brennstoff nur für %.1f Tage") % fd
	var step := _supply(w, "holz", int(ceil(w.settlers.size() * Seasons.heat_per_settler() * FUEL_DAYS * 2.0)), tr("Brennholz"), false)
	if not step.is_empty():
		step.need = need
		step.prio = "a"
		return step
	return _plan(need, tr("alle Holzfäller sind besetzt"), "a")


## Bedürfnisse der Häuser (Stufe 2 und höher), die nicht erfüllt sind und Waren oder ein Gebäude brauchen.
func _need_house(w) -> Dictionary:
	var top := 1
	for b in w.buildings:
		if b.complete and b.housing() > 0:
			top = maxi(top, int(b.def.get("level", 1)))
	for k in range(2, mini(top, HouseNeeds.max_level()) + 1):
		if HouseNeeds.level_ok(w, k):
			continue
		for nd in HouseNeeds.level_needs(k):
			if HouseNeeds.need_sat(w, str(nd.id)) >= 0.7:
				continue
			var need: String = tr("Häuser: %s fehlt") % HouseNeeds.need_label(nd)
			var kind := str(nd.get("kind", ""))
			var goods := []
			if kind == "good":
				goods = [str(nd.good)] + Array(nd.get("alt", [])).map(func(x): return str(x))
			elif kind == "stock":
				goods = Array(nd.get("goods", [])).map(func(x): return str(x))
			elif kind == "building":
				var flag := str(nd.get("flag", ""))
				for t in Data.buildings:
					if Data.buildings[t].has(flag) and Data.buildings[t].get("buildable", false) and Game.is_unlocked(t):
						return _build(w, t, need, "a")
			elif kind == "variety":
				var ft := _farm_type(w, ["obstgarten", "feld", "gewaechshaus"])
				if ft != "":
					return _build(w, ft, need, "a")
			for g in goods:
				var st := _supply(w, g, 20, need, true)
				if not st.is_empty():
					st.need = need
					st.prio = "a"
					return st
	return {}


# ---------------------------------------------------------------- b. Winter
## Haltbares Essen (verdirbt nicht) in Tagen für alle Siedler.
func durable_days(w) -> float:
	if w.settlers.is_empty():
		return 0.0
	var per: Array = Seasons.cfg.get("perishable", [])
	var sat := 0.0
	for id in Data.food_ids():
		if not id in per:
			sat += Game.amount(id, w) * Data.food_satiety(id)
	var need := float(Data.bal("hunger_per_day")) * Game.eff("hunger") * float(Seasons.cfg.get("hunger", [1, 1, 1, 1.15])[Seasons.WINTER])
	return sat / (w.settlers.size() * maxf(need, 0.01))


func _winter_due() -> bool:
	var s := Seasons.season()
	return s == Seasons.SUMMER or s == Seasons.AUTUMN


func winter_food_goal() -> float:
	return Seasons.season_days() * WINTER_FOOD * float(WINTER_GUESS.get(Seasons.winter_forecast(), 1.3))


func _winter_food(w) -> Dictionary:
	if not _winter_due():
		return {}
	var dd := durable_days(w)
	var goal := winter_food_goal()
	if dd >= goal:
		return {}
	var need: String = tr("Wintervorrat: haltbares Essen für %.1f von %.1f Tagen") % [dd, goal]
	# Was haltbar macht: Räucherei (Fisch), Mühle und Bäckerei (Getreide), Konservenfabrik (Fisch und Eisen)
	var chain := []
	if Game.amount("fisch", w) >= 12 or Steward._count(w, "fischer") > 0:
		chain.append_array(["konservenfabrik", "raeucherei"])
	if Game.amount("weizen", w) >= 12 or w.buildings.any(func(b): return b.type == "feld"):
		chain.append_array(["muehle", "baeckerei"])
	if chain.is_empty():
		chain = ["raeucherei"]
	for t in chain:
		if not Game.is_unlocked(t):
			continue
		var have: Array = w.buildings.filter(func(b): return b.type == t)
		if have.is_empty():
			if t == "konservenfabrik" and Game.amount("eisen", w) < 5:
				continue
			return _build(w, t, need, "b")
		for b in have:
			if b.complete and b.paused:
				b.paused = false
				return _plan(need, tr("%s arbeitet wieder") % b.def.name, "b", true, "hammer")
			if b.complete and b.occupants.is_empty() and b.prod_blocker() == "":
				var job: String = Steward.KIND_JOB.get(b.prod_def().get("job", ""), "")
				var s = _staff(w, job, need)
				if s != null:
					return _plan(need, tr("%s arbeitet jetzt als %s") % [s.display_name, Data.jobs[job].name], "b", true, "person")
	# Rohstoff für die Küchen: Fisch
	if Steward._count(w, "fischer") < 1 + w.settlers.size() / 4:
		var s2 = _staff(w, "fischer", need)
		if s2 != null:
			return _plan(need, tr("%s arbeitet jetzt als %s") % [s2.display_name, Data.jobs["fischer"].name], "b", true, "person")
	return {}


## Brennstoff für den ganzen Winter (Vorhersage der Alten).
func winter_fuel_goal(w) -> float:
	var f: float = WINTER_GUESS.get(Seasons.winter_forecast(), 1.3)
	var sd := Seasons.season_days()
	var pop: float = w.settlers.size()
	var autumn_left := sd if Seasons.season() == Seasons.SUMMER else (1.0 - Seasons.season_progress()) * sd
	return pop * (Seasons.heat_per_settler(Seasons.WINTER) * sd * f + Seasons.heat_per_settler(Seasons.AUTUMN) * autumn_left)


func _winter_fuel(w) -> Dictionary:
	if not _winter_due():
		return {}
	var have: float = Game.amount("holz", w) + Extras.coal_ratio() * Game.amount("kohle", w)
	var goal := winter_fuel_goal(w)
	if have >= goal:
		return {}
	var need: String = tr("Wintervorrat: Brennstoff %d von %d") % [int(have), int(goal)]
	# Lagergrenze für Holz zu klein? Dann anheben.
	var lim := Game.limit_of("holz", w)
	if lim >= 0 and lim < goal:
		Game.set_limit("holz", int(goal) + 20, w)
		return _plan(need, tr("Höchstmenge Holz auf %d angehoben") % Game.limit_of("holz", w), "b", true, "holz")
	var st := _supply(w, "holz", int(goal - have), need, false)
	if not st.is_empty():
		st.need = need
		st.prio = "b"
		return st
	return {}


# ---------------------------------------------------------------- c. Wohnen
## Braucht die Insel mehr Arbeitskräfte? Grund oder "".
func workers_wanted(w) -> String:
	if w.settlers.any(func(s): return s.is_adult() and s.job == "frei"):
		return ""
	for b in w.buildings:
		if b.complete and b.def.has("production") and b.occupants.is_empty() and b.prod_blocker() == "" and not b.def.get("ships", false):
			var j: String = Steward.KIND_JOB.get(b.prod_def().get("job", ""), "")
			if j != "" and Steward._count(w, j) < Steward._workplaces(w, b.prod_def().get("job", "")):
				return tr("%s steht still") % b.def.name
	if Admin.active_on(w) and not Admin.shortages().is_empty():
		return tr("in Werkstätten fehlen Leute")
	if not Steward.task_need(w).is_empty():
		return tr("Hauptaufgabe: %s") % Steward.task_names(w)
	if not w.construction_sites().is_empty() and Steward._count(w, "baumeister") < 1:
		return tr("Baustellen ohne Baumeister")
	return ""


func free_beds(w) -> int:
	return Game.housing_capacity(w) - w.settlers.size()


func _note_growth(w) -> void:
	var key := str(int(w.island_id))
	var g: Array = _grow.get(key, [Game.time_days, w.settlers.size()])
	if w.settlers.size() > int(g[1]) or not _grow.has(key):
		g = [Game.time_days, w.settlers.size()]
	elif w.settlers.size() < int(g[1]):
		g[1] = w.settlers.size()
	_grow[key] = g


func stalled_days(w) -> float:
	var g: Array = _grow.get(str(int(w.island_id)), [Game.time_days, 0])
	return Game.time_days - float(g[0])


func _housing(w) -> Dictionary:
	var why := workers_wanted(w)
	var beds := free_beds(w)
	if why == "":
		# Wachstum: Betten voll und reichlich Essen -> ein Haus mehr, damit Kinder kommen
		if beds <= 0 and Game.food_days(w) > 6.0:
			var t0 := best_house(w)
			if t0 != "":
				return _build(w, t0, tr("alle Betten belegt, kein Platz für Kinder"), "c")
		return {}
	var need: String = tr("Arbeitskräfte fehlen (%s)") % why
	if beds <= 1:
		var t := best_house(w)
		if t != "":
			return _build(w, t, need, "c")
	if stalled_days(w) >= STALL_DAYS:
		var st := _bring_settlers(w, need)
		if not st.is_empty():
			return st
	return _plan(need, tr("wartet auf Nachwuchs (%d freie Betten)") % maxi(0, beds), "c")


## Das beste baubare Haus: die meisten Betten, nur wenn sein Material auf den Inseln zusammen da ist
## (sonst das nächstkleinere).
func best_house(w) -> String:
	var best := ""
	var best_n := 0
	for t in Data.buildings:
		var d: Dictionary = Data.buildings[t]
		if not d.get("buildable", false) or int(d.get("housing", 0)) <= 0 or not Game.is_unlocked(t):
			continue
		var ok := true
		for res in d.get("cost", {}):
			if Game.amount_all(res) < int(d.cost[res]):
				ok = false
		if ok and int(d.housing) > best_n:
			best_n = int(d.housing)
			best = t
	return best


## Freie Siedler per Schiff von einer Insel mit Überschuss (mindestens 2 Freie, genug Essen).
func _bring_settlers(w, need: String) -> Dictionary:
	var donors := []  # [Insel, freie Erwachsene], die mit den meisten Freien zuerst
	for o in Sea.all_worlds():
		if o == w or Game.food_days(o) < FOOD_DAYS or Sea.idle_ships(int(o.island_id)).is_empty():
			continue
		var free: Array = o.settlers.filter(func(s): return s.is_adult() and s.job == "frei" and JobDesk.may(s, "automat"))
		if free.size() >= 2:
			donors.append([o, free])
	donors.sort_custom(func(a, b): return a[1].size() > b[1].size())
	for d in donors:
		var people: Array = d[1].slice(0, mini(3, d[1].size() - 1))
		if Sea.send_settlers(d[0], int(w.island_id), people) != "":
			continue
		sent += 1
		_grow[str(int(w.island_id))] = [Game.time_days, w.settlers.size()]
		return _plan(need, tr("%d Siedler kommen per Schiff von %s") % [people.size(), Sea.island_name(d[0])], "c", true, "boot")
	return {}


# ---------------------------------------------------------------- d. Lager
func _storage(w) -> Dictionary:
	var vol := Game.storage_volume(w)
	if vol <= 0 or float(Game.used_volume(w)) / vol < STORE_FULL:
		return {}
	var need: String = tr("Lager zu %d %% voll") % int(100.0 * Game.used_volume(w) / vol)
	for t in ["grosslager", "lager"]:
		if Game.is_unlocked(t):
			return _build(w, t, need, "d")
	return {}


# ---------------------------------------------------------------- e. Warenketten
## Was die Insel braucht: {Ware: Menge} aus offenen Baustellen, Forschung (Heimatinsel) und Hauptaufgabe.
func demand(w) -> Dictionary:
	var out := {}
	for b in w.construction_sites():
		for res in b.def.get("cost", {}):
			out[res] = int(out.get(res, 0)) + maxi(0, int(b.def.cost[res]) - int(b.delivered.get(res, 0)))
	if Sea.is_main(w):
		var t: String = Game.research.current if Game.research.current != "" else wanted_tech
		if t != "" and not t in Game.research.paid and Data.techs.has(t):
			var c: Dictionary = Data.techs[t].get("cost", {})
			for res in c:
				out[res] = int(out.get(res, 0)) + int(c[res])
		if Game.research.current != "":
			for res in Writing.goods_for(Game.research.current):
				out[res] = int(out.get(res, 0)) + 20
	for key in Steward.tasks_of(w):
		for g in Steward.TASKS[key].goods:
			out[g] = maxi(int(out.get(g, 0)), 30)
	return out


func _chains(w) -> Dictionary:
	var want := demand(w)
	var ids: Array = want.keys().filter(func(id): return Game.amount(id, w) + Steward.incoming(int(w.island_id), id) < int(want[id]))
	ids.sort_custom(func(a, b): return int(want[a]) - Game.amount(a, w) > int(want[b]) - Game.amount(b, w))
	for id in ids:
		var miss: int = int(want[id]) - Game.amount(id, w) - Steward.incoming(int(w.island_id), id)
		var need: String = tr("%s fehlt: %d") % [Data.resource_name(id), miss]
		var st := _supply(w, id, miss, need, true)
		if not st.is_empty():
			st.need = need
			st.prio = "e"
			return st
	# Forscher: freie Forschungsplätze auf der Heimatinsel
	if Sea.is_main(w) and Game.research.current != "":
		for b in w.buildings:
			if b.complete and b.def.has("research") and b.free_slots() > 0 and w.pool_allows(b):
				var s = _staff(w, "forscher", tr("freie Forschungsplätze"))
				if s != null:
					return _plan(tr("Forschung: %s") % Data.techs[Game.research.current].name, tr("%s forscht jetzt") % s.display_name, "e", true, "wissen")
				break
	return {}


## Sorgt für n Stück der Ware id auf Insel w: per Schiff von einer anderen Insel, eine stillstehende Werkstatt
## besetzen, einen Rohstoff-Beruf besetzen oder (build) eine Werkstatt bauen. {} = nichts zu tun.
func _supply(w, id: String, n: int, why: String, build: bool) -> Dictionary:
	var to_id := int(w.island_id)
	# 1. Eine andere Insel hat genug übrig
	var src := _source(w, id, maxi(5, n))
	if src != -1:
		var amt: int = mini(maxi(5, n), _spare(Sea.worlds.get(src), id))
		if Steward._send(src, to_id, id, amt, why):
			return _plan(why, tr("%s kommt per Schiff von %s") % [Data.resource_name(id), Sea.meta(src).get("name", "?")], "e", true, "anker")
	# 2. Werkstatt auf der Insel
	var has_shop := false
	for b in w.buildings:
		if not b.def.has("production") or not b.prod_def().get("outputs", {}).has(id) or b.def.get("ships", false):
			continue
		if not b.complete:
			has_shop = true
			continue
		has_shop = true
		if b.paused:
			b.paused = false
			return _plan(why, tr("%s arbeitet wieder") % b.def.name, "e", true, "hammer")
		var block: String = b.prod_blocker()
		if block == "" and b.occupants.is_empty():
			var job: String = Steward.KIND_JOB.get(b.prod_def().get("job", ""), "")
			var s = _staff(w, job, why)
			if s != null:
				return _plan(why, tr("%s arbeitet jetzt als %s (%s)") % [s.display_name, Data.jobs[job].name, b.def.name], "e", true, "person")
		elif block != "" and build:
			# Zutat fehlt: eine Stufe tiefer (ohne weiter zu bauen)
			for res in b.prod_def().get("inputs", {}):
				if Game.amount(res, w) < int(b.prod_def().inputs[res]):
					var st := _supply(w, res, int(b.prod_def().inputs[res]) * 5, why, false)
					if not st.is_empty():
						return st
	if has_shop:
		return {}
	# 3. Rohstoff: Beruf besetzen
	var raw := str(Steward.RAW_JOB.get(id, ""))
	if raw != "":
		if Data.job_unlocked(raw) and Steward._count(w, raw) < 2 + w.settlers.size() / 6:
			var s2 = _staff(w, raw, why)
			if s2 != null:
				return _plan(why, tr("%s arbeitet jetzt als %s") % [s2.display_name, Data.jobs[raw].name], "e", true, "person")
		return {}
	# 4. Werkstatt bauen
	if build:
		for t in Writing.producers_of(id):
			if Game.is_unlocked(t) and not Data.buildings[t].get("ships", false):
				return _build(w, t, why, "e")
	return {}


## So viel kann eine Insel von der Ware abgeben (behält KEEP_SEND und was ihre Baustellen brauchen).
func _spare(o, id: String) -> int:
	if o == null:
		return 0
	var keep := KEEP_SEND + int(demand(o).get(id, 0))
	return Game.amount(id, o) - Steward.outgoing(int(o.island_id), id) - keep


## Insel, die n Stück der Ware abgeben kann (die mit dem meisten Übrigen), sonst -1.
func _source(w, id: String, n: int) -> int:
	var best := -1
	var best_v := 0
	for o in Sea.all_worlds():
		if o == w:
			continue
		var v := _spare(o, id)
		if v >= mini(n, 5) and v > best_v:
			best_v = v
			best = int(o.island_id)
	return best


# ---------------------------------------------------------------- Bauen
## Was für einen Bau von type auf Insel w noch fehlt: {Ware: Menge} (Lager und was schon unterwegs ist
## zählen, was andere Baustellen noch brauchen nicht).
func missing_cost(w, type: String) -> Dictionary:
	var other := {}
	for b in w.construction_sites():
		for res in b.def.get("cost", {}):
			other[res] = int(other.get(res, 0)) + maxi(0, int(b.def.cost[res]) - int(b.delivered.get(res, 0)))
	var out := {}
	var cost: Dictionary = Data.buildings[type].get("cost", {})
	for res in cost:
		var have: int = Game.amount(res, w) + Steward.incoming(int(w.island_id), res) - int(other.get(res, 0))
		if have < int(cost[res]):
			out[res] = int(cost[res]) - have
	return out


## Baut type auf Insel w, wenn die Siedler es umsetzen können: keine andere Baustelle, Material da oder
## unterwegs (sonst bestellen oder herstellen lassen), ein Platz, ein Baumeister.
func _build(w, type: String, need: String, prio: String) -> Dictionary:
	var key := str(int(w.island_id))
	var name: String = Data.buildings[type].name
	var sites: Array = w.construction_sites()
	if not sites.is_empty():
		# Eine Baustelle zur Zeit: erst die laufende fertig bauen (Material und Baumeister)
		var b = sites[0]
		var st := _feed_site(w, b, need)
		if not st.is_empty():
			st.prio = prio
			return st
		return _plan(need, tr("%s ist dran, erst die Baustelle %s fertig bauen") % [name, b.def.name], prio)
	var miss := missing_cost(w, type)
	if not miss.is_empty():
		orders[key] = {"type": type, "why": need, "day": Game.time_days}
		var got := _order(w, miss, tr("Material für %s") % name)
		if got != "":
			return _plan(need, tr("bestellt für %s: %s") % [name, got], prio, true, "anker")
		for res in miss:
			var st2 := _supply(w, res, int(miss[res]), need, false)
			if not st2.is_empty():
				st2.step = tr("für %s: %s") % [name, st2.step]
				st2.prio = prio
				return st2
		return _plan(need, tr("%s fehlt noch: %s") % [name, _goods_text(miss)], prio)
	var c = spot(w, type)
	if c == null:
		return _plan(need, tr("kein Platz für %s") % name, prio)
	w.place_building(type, c, false)
	orders.erase(key)
	built += 1
	_ensure_builder(w)
	return _plan(need, tr("baut %s") % name, prio, true, "hammer")


## Laufende Baustelle: fehlendes Material bestellen, Baumeister sicherstellen.
func _feed_site(w, b, need: String) -> Dictionary:
	var miss := {}
	for res in b.def.get("cost", {}):
		var left: int = int(b.def.cost[res]) - int(b.delivered.get(res, 0))
		var have: int = Game.amount(res, w) + Steward.incoming(int(w.island_id), res)
		if left > have:
			miss[res] = left - have
	if not miss.is_empty():
		var got := _order(w, miss, tr("Material für %s") % b.def.name)
		if got != "":
			return _plan(need, tr("bestellt für die Baustelle %s: %s") % [b.def.name, got], "", true, "anker")
	var s = _ensure_builder(w)
	if s != null:
		return _plan(need, tr("%s baut jetzt an %s") % [s.display_name, b.def.name], "", true, "person")
	return {}


## Waren per Schiff von anderen Inseln bestellen. Gibt den Text des Bestellten zurück ("" = nichts).
func _order(w, miss: Dictionary, why: String) -> String:
	var parts := []
	for res in miss:
		var n: int = int(miss[res]) - Steward.incoming(int(w.island_id), res)
		if n <= 0:
			continue
		var src := _source(w, res, maxi(5, n))
		if src == -1:
			continue
		var amt: int = mini(maxi(5, n), _spare(Sea.worlds.get(src), res))
		if Steward._send(src, int(w.island_id), res, amt, why):
			parts.append(tr("%d %s von %s") % [amt, Data.resource_name(res), Sea.meta(src).get("name", "?")])
	return ", ".join(PackedStringArray(parts))


func _goods_text(d: Dictionary) -> String:
	var parts := []
	for res in d:
		parts.append("%d %s" % [int(d[res]), Data.resource_name(res)])
	return ", ".join(PackedStringArray(parts))


## Mindestens ein Baumeister, solange gebaut wird. Gibt den neuen Baumeister zurück (oder null).
func _ensure_builder(w):
	if w.construction_sites().is_empty() or Steward._count(w, "baumeister") >= 1:
		return null
	var s = _staff(w, "baumeister", tr("Baustelle"), true)
	if s == null:
		# Sonst niemand da (kleine Insel, alle forschen): ein Forscher baut, damit die Baustelle nicht ewig steht
		var cand: Array = w.settlers.filter(func(x): return x.is_adult() and x.job == "forscher" and JobDesk.may(x, "automat"))
		if not cand.is_empty():
			s = cand[0]
			JobDesk.assign(s, "baumeister", "automat")
	return s


## Gibt einem Siedler den Beruf (zuerst Freie, dann Überzählige, mit hard auch andere; Steward._take_worker).
func _staff(w, job: String, why: String, hard: bool = false):
	if job == "" or not Data.jobs.has(job) or not Data.job_unlocked(job):
		return null
	var s = Steward._take_worker(w, {"job": job, "why": why, "hard": hard}, "automat")
	if s == null or not JobDesk.assign(s, job, "automat"):  # der Verwalter (Rang darunter) setzt ihn nicht gleich wieder um
		return null
	return s


## Bauplatz nahe der Siedlung: freie Fläche mit einem Feld Abstand ringsum, nah an Straßen, nicht vor dem Hafen.
func spot(w, type: String):
	var sz: Array = Data.buildings[type].size
	var mid := settlement_center(w)
	var harbor: Vector2i = w.harbor_cell()
	var best = null
	var best_v := INF
	var found_rad := -1
	for rad in range(2, 28):
		if found_rad >= 0 and rad > found_rad + 2:
			break
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var cc: Vector2i = mid + Vector2i(dx, dy)
				if not w.can_place(type, cc) or not AiRule._roomy(w, sz, cc):
					continue
				var hd: int = maxi(absi(cc.x + int(sz[0]) / 2 - harbor.x), absi(cc.y + int(sz[1]) / 2 - harbor.y))
				if hd <= 3:
					continue  # vor dem Hafen bleibt frei
				var v := float(rad)
				if _road_near(w, cc, sz):
					v -= 2.0
				if found_rad < 0:
					found_rad = rad
				if v < best_v:
					best_v = v
					best = cc
	return best


## Mitte der Siedlung: Mittel der Gebäude (ohne Felder), sonst die Inselmitte.
func settlement_center(w) -> Vector2i:
	var sum := Vector2i.ZERO
	var n := 0
	for b in w.buildings:
		if not b.is_ground() and not b.def.has("tile"):
			sum += b.cell
			n += 1
	return w.center if n == 0 else sum / n


func _road_near(w, cc: Vector2i, sz: Array) -> bool:
	for y in range(-2, int(sz[1]) + 3):
		for x in range(-2, int(sz[0]) + 2):
			var b = w.building_at.get(cc + Vector2i(x, y))
			if b != null and (str(b.def.get("tile", "")) == "road" or b.def.has("path_speed")):
				return true
	return false


# ---------------------------------------------------------------- f. Forschung
## Forschungen auf dem Weg zur KI (sie selbst und alle Voraussetzungen).
func ki_path() -> Dictionary:
	var out := {}
	var todo := ["ki"]
	while not todo.is_empty():
		var t: String = todo.pop_back()
		if out.has(t) or not Data.techs.has(t):
			continue
		out[t] = true
		for r in Data.techs[t].get("requires", []):
			todo.append(str(r))
	return out


## Wählbare Forschungen, sortiert: auf dem Weg zur KI zuerst, dann die günstigste (Punkte).
func tech_order() -> Array:
	var path := ki_path()
	var out := []
	for t in Data.techs:
		if t.begins_with("_") or Game.tech_state(t) != "available":
			continue
		out.append(t)
	out.sort_custom(func(a, b):
		var pa := 0 if path.has(a) else 1
		var pb := 0 if path.has(b) else 1
		if pa != pb:
			return pa < pb
		return Game.tech_points(a) < Game.tech_points(b))
	return out


func _affordable(t: String) -> bool:
	return t in Game.research.paid or Game.can_afford(Data.techs[t].get("cost", {}), Sea.main_world())


## Forscht nichts: die nächste Forschung starten. Gibt sie zurück ("" = keine).
func research_step() -> String:
	if Game.research.current != "":
		wanted_tech = ""
		return ""
	var hw = Sea.main_world()
	if hw == null:
		return ""
	var p := plan_of(hw)
	if str(p.get("prio", "")) in ["a"]:
		return ""  # erst die Bedürfnisse der Heimatinsel
	var list := tech_order()
	if list.is_empty():
		return ""
	var first: String = list[0]
	var lacking := {}
	if not _affordable(first):
		var c: Dictionary = Data.techs[first].get("cost", {})
		for res in c:
			if Game.amount(res, hw) < int(c[res]):
				lacking[res] = true
	for t in list:
		if not _affordable(t):
			continue
		if t != first and not t in Game.research.paid and Data.techs[t].get("cost", {}).keys().any(func(r): return lacking.has(r)):
			continue  # nimmt der gewünschten Forschung nichts weg
		if Game.start_research(t) == "":
			started += 1
			wanted_tech = "" if t == first else first
			research_note = (tr("%s (auf dem Weg zur KI)") if ki_path().has(t) else "%s") % Data.techs[t].name
			Game.notify_at(hw, tr("Automat: forscht jetzt %s") % research_note, "wissen", "verwaltung")
			return t
	wanted_tech = first
	return ""


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	on = true
	offered = false
	plans = {}
	orders = {}
	wanted_tech = ""
	research_note = ""
	built = 0
	started = 0
	sent = 0
	_grow = {}
	_said = {}
	_next = 0.0
	changed.emit()


func _on_save(d: Dictionary) -> void:
	d["planner"] = {"on": on, "offered": offered, "plans": plans.duplicate(true), "orders": orders.duplicate(true),
		"wanted": wanted_tech, "note": research_note, "built": built, "started": started, "sent": sent, "grow": _grow.duplicate(true)}


func _on_load(data: Dictionary, _old_rules: int) -> void:
	_on_reset()
	var e = data.get("planner", null)
	if not (e is Dictionary):
		return  # alter Spielstand: Automat an, Angebot noch nicht gezeigt
	on = bool(e.get("on", true))
	offered = bool(e.get("offered", false))
	wanted_tech = str(e.get("wanted", ""))
	research_note = str(e.get("note", ""))
	if not Data.techs.has(wanted_tech):
		wanted_tech = ""
	built = int(e.get("built", 0))
	started = int(e.get("started", 0))
	sent = int(e.get("sent", 0))
	for k in ["plans", "orders", "grow"]:
		var v = e.get(k, {})
		if not (v is Dictionary):
			continue
		for i in v:
			match k:
				"plans":
					if v[i] is Dictionary:
						plans[str(i)] = {"need": str(v[i].get("need", "")), "step": str(v[i].get("step", "")), "prio": str(v[i].get("prio", "")), "day": float(v[i].get("day", 0.0))}
				"orders":
					if v[i] is Dictionary and Data.buildings.has(str(v[i].get("type", ""))):
						orders[str(i)] = {"type": str(v[i].type), "why": str(v[i].get("why", "")), "day": float(v[i].get("day", 0.0))}
				"grow":
					if v[i] is Array and v[i].size() == 2:
						_grow[str(i)] = [float(v[i][0]), int(v[i][1])]
	changed.emit()


func autotest_setup(args: Dictionary, main) -> void:
	if args.has("plannertest"):
		await PlannerTest.run(main, str(args.plannertest))
	if args.has("plannermeasure"):
		await PlannerTest.measure(main, str(args.plannermeasure))
	if args.has("plannershot"):
		PlannerTest.shot(main)
