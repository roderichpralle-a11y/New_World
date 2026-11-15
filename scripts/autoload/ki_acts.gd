class_name KiActs
extends RefCounted
## Handlungen der lernenden KI für das ganze Spiel (josh 2026-11-15).
##
## Die KI (scripts/autoload/ki_brain.gd) lernt, WAS sie WANN tut: jede Handlung hier hat eine Zeile Gewichte, ihr
## Wert ist Gewichte mal Eingänge (Zustand der Insel + 4 Eingänge der Handlung selbst). Die beste erlaubte Handlung
## über 0 wird ausgeführt. WO gebaut wird und WELCHES Gebäude eine Handlung trifft (z. B. welches Haus abgerissen
## wird), sucht dieses Skript mit einfachen Hilfen: das ist nicht gelernt.
##
## Gruppen und Freischalt-Liste (UNLOCK): im Spiel gibt jedes Gebäude der KI eine Gruppe von Entscheidungen frei.
## Im Training (KiBrain.train_all) ist alles frei und die KI steuert das ganze Spiel allein.
## Gebäude mit dem Schalter „Nur Spieler“ (Building.player_only) und Siedler mit „Steuerung: Spieler“ fasst die
## KI nie an.

## Gruppe -> was freischaltet. "office": nötige Ausbaustufe der Verwaltung; "types": eines dieser Gebäude steht fertig.
const UNLOCK := {
	"berufe": {"office": 1, "name": "Berufe vergeben, Verwalter einsetzen"},
	"wohnen": {"office": 2, "name": "Häuser bauen und ausbauen (Wohnraum für Kinder)"},
	"natur": {"office": 2, "name": "Felder, Obstgärten, Gewächshäuser, Bäume nachpflanzen"},
	"wege": {"office": 2, "name": "Straßen bauen"},
	"forschung": {"types": ["bibliothek"], "name": "Forschung wählen und starten"},
	"lager": {"office": 3, "name": "Lager bauen und ausbauen, Höchstmenge, Reserve, Nicht essen, Nicht verarbeiten"},
	"werkstatt": {"office": 4, "name": "Werkstätten und alle übrigen Gebäude bauen und ausbauen, anhalten und starten"},
	"umbau": {"office": 5, "name": "Gebäude versetzen und abreißen"},
	"arbeitszeit": {"office": 5, "name": "Überstunden und Schichtarbeit anordnen"},
	"jagd": {"types": ["jagdhuette"], "name": "Gehege bauen und jagen lassen"},
	"see": {"types": ["hafen", "grosser_hafen"], "name": "Schiffe bauen, Seeleute zuteilen, Inseln erkunden und besiedeln, Häfen bauen"},
	"routen": {"types": ["grosser_hafen"], "name": "Schiffe beladen und Routen einrichten"},
	"funk": {"types": ["rundfunk"], "name": "Funkstationen bauen und Nebeninseln steuern"},
	"droiden": {"office": 6, "name": "Droidenfabriken bauen, Droiden einsetzen"},
	"zukunft": {"office": 7, "name": "Zukunftsstadt bauen"},
}

const OT_JOBS := ["holzfaeller", "bauer", "koch", "handwerker", "steinmetz", "forscher"]
const FIXED := ["haus", "ausbau", "lager", "feld", "obstgarten", "strasse", "werft", "schiff", "erkunden", "besiedeln",
	"ausbau_lager", "ausbau_wissen", "ausbau_amt", "ausbau_werft", "schmuck", "setzling", "gehege", "verwalter",
	"abriss_werkstatt", "abriss_haus", "abriss_feld", "versetzen", "pause", "weiter",
	"seemann", "fracht_hin", "fracht_her", "route", "route_weg",
	"limit", "limit_frei", "reserve", "reserve_weg", "nicht_essen", "nicht_essen_weg"]
const SEA_TYPES := ["anlegesteg", "hafen", "grosser_hafen", "holzkai", "steinkai", "proviantkai", "leuchtturm"]

static var _names: Array = []
static var _bau: Array = []


## Gebäude, die die KI einzeln als Handlung "bau:<typ>" kennt: alles Baubare außer Häusern, Lagern, Feldern,
## Wegen, Zäunen und Schmuck (die haben eigene Handlungen).
static func bau_types() -> Array:
	if _bau.is_empty():
		for t in Data.buildings:
			var d: Dictionary = Data.buildings[t]
			if not d.get("buildable", false) or d.has("tile") or d.has("decor") or d.has("base"):
				continue
			if int(d.get("housing", 0)) > 0 or int(d.get("storage", 0)) > 0:
				continue
			if t in ["feld", "obstgarten", "werft", "lagerfeuer", "jagdhuette"]:
				continue
			_bau.append(t)
		_bau.sort()
	return _bau


## Alle Handlungen (Namen = Schlüssel der Gewichte).
static func names() -> Array:
	if _names.is_empty():
		_names = FIXED.duplicate()
		for t in bau_types():
			_names.append("bau:" + t)
		for j in OT_JOBS:
			_names.append("ot:" + j)
			_names.append("schicht:" + j)
	return _names


static func group(act: String) -> String:
	if act.begins_with("ot:") or act.begins_with("schicht:"):
		return "arbeitszeit"
	if act.begins_with("bau:"):
		var t := act.substr(4)
		if t in SEA_TYPES:
			return "see"
		if t == "rundfunk":
			return "funk"
		if t == "droidenfabrik":
			return "droiden"
		if t == "zukunftsstadt":
			return "zukunft"
		if t == "gewaechshaus":
			return "natur"
		return "werkstatt"
	match act:
		"haus", "ausbau":
			return "wohnen"
		"feld", "obstgarten", "setzling":
			return "natur"
		"strasse":
			return "wege"
		"lager", "ausbau_lager", "limit", "limit_frei", "reserve", "reserve_weg", "nicht_essen", "nicht_essen_weg":
			return "lager"
		"abriss_werkstatt", "abriss_haus", "abriss_feld", "versetzen":
			return "umbau"
		"gehege":
			return "jagd"
		"werft", "ausbau_werft", "schiff", "erkunden", "besiedeln", "seemann":
			return "see"
		"fracht_hin", "fracht_her", "route", "route_weg":
			return "routen"
		"verwalter":
			return "berufe"
	return "werkstatt"


## Freischalt-Liste: ist die Gruppe durch ein Gebäude freigegeben?
static func unlocked(g: String) -> bool:
	var u: Dictionary = UNLOCK.get(g, {})
	if u.has("office"):
		return Admin.level() >= int(u.office)
	for w in Sea.all_worlds():
		for b in w.buildings:
			if b.complete and (b.type in u.get("types", []) or str(b.def.get("base", "")) in u.get("types", [])):
				return true
	return false


## Text der Freischalt-Liste für Anzeige und Hilfe: [[Gebäude, Entscheidungen], ...]
static func unlock_rows() -> Array:
	var out := []
	for g in UNLOCK:
		var u: Dictionary = UNLOCK[g]
		var by := ""
		if u.has("office"):
			for t in Data.buildings:
				if Data.buildings[t].get("office", false) and int(Data.buildings[t].get("office_level", 1)) == int(u.office):
					by = str(Data.buildings[t].name)
		else:
			by = " oder ".join(PackedStringArray((u.types as Array).map(func(t): return str(Data.buildings[t].name))))
		out.append([by, str(u.name), unlocked(g)])
	return out


# ---------------------------------------------------------------- Eingänge
## Eingänge 66..95 der Insel (ki_brain.features ruft das am Ende).
static func more_features(w, x: PackedFloat32Array, n: int, adults: int, beds: int) -> void:
	x[66] = Game.current_age() / 8.0
	x[67] = Game.max_tier() / 16.0
	var st: Array = Exams.status(Exams.passed) if not Exams.exam_def(Exams.passed).is_empty() else []
	var met := 0
	for e in st:
		if e[3]:
			met += 1
		else:
			var typ := str(e[0].get("type", ""))
			var gap := clampf(float(int(e[2]) - int(e[1])) / maxf(1.0, float(e[2])), 0.0, 1.0)
			if typ == "pop":
				x[69] = gap
			elif typ == "islands":
				x[70] = gap
			elif typ == "houses":
				x[71] = gap
	x[68] = 1.0 - float(met) / maxf(1.0, float(st.size())) if not st.is_empty() else 0.0
	x[72] = minf(w.droids.size() / 20.0, 3.0)
	x[73] = minf(Game.amount("strom", w) / 100.0, 3.0)
	x[74] = 1.0 if Steward.has_radio(w) else 0.0
	x[75] = Admin.level() / 7.0
	x[76] = 1.0 if Sea.is_main(w) else 0.0
	var wild := 0
	for a in w.animals:
		if is_instance_valid(a) and not a.dead:
			wild += 1
	x[77] = minf(wild / 10.0, 3.0)
	x[78] = minf(w.lodges().size() / 3.0, 3.0)
	x[79] = minf(Sea.free_sailors(w) / 3.0, 3.0)
	var routed := 0
	for sh in Sea.ships:
		if not sh.route.is_empty() and not Sea.is_trip(sh):
			routed += 1
	x[80] = minf(routed / 3.0, 3.0)
	x[81] = minf(Game.amount("elektronik", w) / 50.0, 3.0)
	x[82] = minf(Game.amount("gold", w) / 20.0, 3.0)
	x[83] = minf((Game.amount("glas", w) + Game.amount("papier", w)) / 100.0, 3.0)
	x[84] = minf((Game.amount("stahl", w) + Game.amount("maschinen", w)) / 100.0, 3.0)
	var prod := 0
	var blocked := 0
	for b in w.buildings:
		if is_instance_valid(b) and b.complete and b.def.has("production"):
			prod += 1
			if b.paused or b.prod_blocker() != "":
				blocked += 1
	x[85] = minf(prod / 20.0, 3.0)
	x[86] = float(blocked) / maxf(1.0, float(prod))
	var free := 0
	for s in w.settlers:
		if is_instance_valid(s) and s.is_adult() and s.job == "frei":
			free += 1
	x[87] = float(free) / maxf(1.0, float(adults))
	x[88] = clampf(SettlerMind.comfort(), 0.0, 2.0)
	var orders := 0
	for j in OT_JOBS:
		if Admin.ordered(j, "ot") or Admin.ordered(j, "sh"):
			orders += 1
	x[89] = orders / 6.0
	x[90] = clampf(float(beds - n) / 10.0, 0.0, 3.0)
	x[91] = float(n - adults) / maxf(1.0, float(n))
	var low := 10.0
	for o in Sea.all_worlds():
		if o != w and not o.settlers.is_empty():
			low = minf(low, KiBrain.food_days(o))
	x[92] = low / 10.0
	var avail := 0
	for t in Data.techs:
		if not str(t).begins_with("_") and Game.tech_state(t) == "available":
			avail += 1
	x[93] = minf(avail / 10.0, 3.0)
	x[94] = minf(Game.time_days / 500.0, 3.0)
	var at_limit := 0
	for id in w.stock:
		var lim: int = Game.limit_of(id, w)
		if lim >= 0 and Game.amount(id, w) >= lim:
			at_limit += 1
	x[95] = minf(at_limit / 10.0, 3.0)


static func _count_type(w, t: String) -> int:
	var c := 0
	for b in w.buildings:
		if is_instance_valid(b) and (b.type == t or str(b.def.get("base", "")) == t):
			c += 1
	return c


## Die 4 Eingänge der Handlung selbst: [so viele stehen schon / 3, keins da, wird gerade gebraucht, Besetzung].
static func extras(w, act: String) -> Array:
	var ex := [0.0, 0.0, 0.0, 0.0]
	if not act.begins_with("bau:"):
		return ex
	var t := act.substr(4)
	var cnt := 0
	var slots := 0
	var occ := 0
	for b in w.buildings:
		if is_instance_valid(b) and (b.type == t or str(b.def.get("base", "")) == t):
			cnt += 1
			if b.complete and (b.def.has("production") or b.def.has("research")):
				slots += b.slots()
				occ += b.occupants.size()
	ex[0] = minf(cnt / 3.0, 3.0)
	ex[1] = 1.0 if cnt == 0 else 0.0
	# gebraucht: stellt eine Ware her, die der Ziel-Forschung fehlt, oder die Prüfung verlangt dieses Gebäude
	var d: Dictionary = Data.buildings[t]
	var miss := KiBrain.research_missing()
	for id in d.get("production", {}).get("outputs", {}):
		if miss.has(id):
			ex[2] = 1.0
	if not Exams.exam_def(Exams.passed).is_empty():
		for e in Exams.status(Exams.passed):
			if not e[3] and str(e[0].get("what", "")) == t:
				ex[2] = 1.0
	ex[3] = float(occ) / float(slots) if slots > 0 else 0.0
	return ex


# ---------------------------------------------------------------- Forschung
static var _zpath: Dictionary = {}
static var _deps: Dictionary = {}


static func _tech_tables() -> void:
	if not _zpath.is_empty():
		return
	var todo := ["zukunftsstadt"]
	while not todo.is_empty():
		var t: String = todo.pop_back()
		if _zpath.has(t) or not Data.techs.has(t):
			continue
		_zpath[t] = true
		for r in Data.techs[t].get("requires", []):
			todo.append(str(r))
	for t in Data.techs:
		if str(t).begins_with("_"):
			continue
		for r in Data.techs[t].get("requires", []):
			_deps[str(r)] = int(_deps.get(str(r), 0)) + 1


## TECH_F Eingänge einer wählbaren Forschung.
static func tech_features(t: String) -> Array:
	_tech_tables()
	var d: Dictionary = Data.techs[t]
	var mw = Sea.main_world()
	var cost: Dictionary = d.get("cost", {})
	var need := 0.0
	var miss := 0.0
	for id in cost:
		need += float(cost[id])
		miss += maxf(0.0, float(cost[id]) - float(Game.amount(id, mw)))
	var f := []
	f.resize(KiBrain.TECH_F)
	f.fill(0.0)
	f[0] = 1.0
	f[1] = float(d.get("tier", 1)) / 16.0
	f[2] = minf(Game.tech_points(t) / 10000.0, 3.0)
	f[3] = 1.0 if miss <= 0.0 else 0.0
	f[4] = miss / maxf(1.0, need)
	f[5] = 1.0 if _zpath.has(t) else 0.0
	var unl := 0
	var home := 0
	var sea := 0
	for bt in Data.buildings:
		if str(Data.buildings[bt].get("requires", "")) == t:
			unl += 1
			if int(Data.buildings[bt].get("housing", 0)) > 0 or int(Data.buildings[bt].get("storage", 0)) > 0:
				home = 1
			if Data.buildings[bt].has("harbor") or Data.buildings[bt].get("ships", false):
				sea = 1
	for st in Data.ships:
		if str(Data.ships[st].get("requires", "")) == t:
			sea = 1
	f[6] = minf(unl / 3.0, 1.0)
	f[7] = float(home)
	f[8] = minf((d.get("effects", {}) as Dictionary).size() / 3.0, 1.0)
	# zählt für die Prüfung: Forschung des laufenden Zeitalters
	var age: Dictionary = Data.ages[mini(Exams.passed, Data.ages.size() - 1)]
	f[9] = 1.0 if int(d.get("tier", 1)) in age.get("tiers", []) else 0.0
	f[10] = float(sea)
	f[11] = minf(int(_deps.get(t, 0)) / 5.0, 1.0)
	return f


## Beste wählbare Forschung nach den gelernten Gewichten ("" = keine). Die Superintelligenz (böses Ende, für die
## Zukunftsstadt nicht nötig) wählt die KI nie.
static func pick_tech() -> String:
	# Nur Forschungen, die jetzt bezahlbar sind (josh 2026-11-15, Fund in Runde 32: die KI blieb 130 Tage an
	# "Bewässerung" hängen, weil 2 Ziegel nie im Lager lagen). Ist keine bezahlbar, zählt die beste insgesamt.
	var mw = Sea.main_world()
	var best := ""
	var best_v := -INF
	var any_pay := false
	for t in Data.sorted_tech_ids():
		if t != "superintelligenz" and Game.tech_state(t) == "available" and (t in Game.research.paid or Game.can_afford(Data.techs[t].get("cost", {}), mw)):
			any_pay = true
			break
	for t in Data.sorted_tech_ids():
		if t == "superintelligenz" or Game.tech_state(t) != "available":
			continue
		if any_pay and not (t in Game.research.paid or Game.can_afford(Data.techs[t].get("cost", {}), mw)):
			continue
		var f := tech_features(t)
		var v := 0.0
		for k in KiBrain.TECH_F:
			v += float(KiBrain.tweights[k]) * float(f[k])
		if v > best_v:
			best_v = v
			best = t
	return best


# ---------------------------------------------------------------- Hilfen
static func _free(b) -> bool:
	return is_instance_valid(b) and not b.player_only


static func _spot(w, type: String):
	var c = Planner.spot(w, type)
	if c != null:
		return c
	# Küste, Erz, enge Inseln: nächster erlaubter Platz zum Hafen bzw. zur Siedlung
	var d: Dictionary = Data.buildings[type]
	var from: Vector2i = w.harbor_cell() if d.get("coast", false) else Planner.settlement_center(w)
	var best = null
	var best_d := INF
	for y in range(0, int(w.size)):
		for x in range(0, int(w.size)):
			var cc := Vector2i(x, y)
			var dd := float((cc - from).length_squared())
			if dd < best_d and w.can_place(type, cc):
				best_d = dd
				best = cc
	return best


static func _place(w, type: String):
	var c = _spot(w, type)
	if c == null:
		return null
	var b = w.place_building(type, c, false)
	if b != null:
		b.set_meta("ki_site", true)
	return b


static func _affordable(w, type: String) -> bool:
	return Data.buildings.has(type) and Game.is_unlocked(type) and Planner.missing_cost(w, type).is_empty()


static func _sites_full(w) -> bool:
	return KiBrain._ki_sites(w) >= KiBrain.max_sites


static func _upgradable(w, pred: Callable) -> Array:
	return w.buildings.filter(func(b): return _free(b) and b.complete and str(b.def.get("upgrade", "")) != "" and pred.call(b) \
		and Game.is_unlocked(str(b.def.upgrade)) and HouseNeeds.full_level(b) and Planner.missing_cost(w, str(b.def.upgrade)).is_empty() \
		and w.upgrade_spot(b, str(b.def.upgrade)).x >= 0)


static func _up_pred(act: String) -> Callable:
	match act:
		"ausbau_lager":
			return func(b): return int(b.def.get("storage", 0)) > 0 and b.type != "lagerfeuer"
		"ausbau_wissen":
			return func(b): return b.def.has("research")
		"ausbau_amt":
			return func(b): return b.def.get("office", false)
		"ausbau_werft":
			return func(b): return b.def.get("ships", false)
	return func(_b): return false


static func _outputs_full(w, b) -> bool:
	for id in b.prod_def().get("outputs", {}):
		if not Data.resources.has(id):
			continue
		var lim: int = Game.limit_of(id, w)
		if Game.space_for(id, w) <= 0 or (lim >= 0 and Game.amount(id, w) >= lim):
			return true
	return false


static func _idle_shop(w):
	var best = null
	var best_n := 0
	for b in w.buildings:
		if not _free(b) or not b.complete or not b.def.has("production") or b.def.get("ships", false):
			continue
		if not b.occupants.is_empty() or not (b.paused or b.prod_blocker() != ""):
			continue
		var n := _count_type(w, b.type)
		if n > best_n:
			best_n = n
			best = b
	return best


static func _empty_house(w):
	var beds := 0
	for b in w.buildings:
		if b.complete:
			beds += int(b.def.get("housing", 0))
	var best = null
	for b in w.buildings:
		if _free(b) and b.complete and int(b.def.get("housing", 0)) > 0 and b.residents().is_empty():
			if beds - int(b.def.housing) >= w.settlers.size() + 2 and (best == null or int(b.def.housing) < int(best.def.housing)):
				best = b
	return best


static func _spare_field(w):
	var fields: Array = w.buildings.filter(func(b): return _free(b) and b.complete and b.type == "feld")
	if fields.size() <= 4 * KiBrain._count_job(w, "bauer") + 4:
		return null
	var best = null
	var best_d := -1.0
	for b in fields:
		var st = w.nearest_storage(b.cell)
		var d: float = b.dist_sq(st.entrance_cell()) if st != null else 0.0
		if d > best_d:
			best_d = d
			best = b
	return best


## Gebäude, das weit vom Lager steht und näher an die Siedlung könnte: [Gebäude, neue Zelle] oder [].
static func _move_pick(w) -> Array:
	var best = null
	var best_d := 144.0  # weiter als 12 Felder
	for b in w.buildings:
		if not _free(b) or not b.complete or b.is_ground() or b.is_decor() or b.is_storage():
			continue
		if not (b.def.has("production") or int(b.def.get("housing", 0)) > 0) or b.def.get("coast", false) or b.def.has("deposit"):
			continue
		var st = w.nearest_storage(b.entrance_cell())
		if st == null:
			continue
		var d: float = b.dist_sq(st.entrance_cell())
		if d > best_d:
			best_d = d
			best = b
	if best == null:
		return []
	var c = Planner.spot(w, best.type)
	if c == null:
		return []
	var st2 = w.nearest_storage(c)
	if st2 == null or float((c - st2.entrance_cell()).length_squared()) > best_d * 0.5:
		return []
	return [best, c]


static func _tree_cells(w, want: int) -> Array:
	var out := []
	var seen := {}
	for nd in w.nodes:
		if out.size() >= want:
			break
		if not is_instance_valid(nd) or str(nd.type) != "baum":
			continue
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(2, 0), Vector2i(0, 2)]:
			var c: Vector2i = nd.cell + d
			if seen.has(c):
				continue
			seen[c] = true
			if w.can_place("setzling", c) and not w.road_at(c):
				out.append(c)
				break
	return out


## Platz für ein Gehege um ein wildes, friedliches Tier: {ring: [Zellen], lodge: Zelle} oder {}.
static func _pen_plan(w) -> Dictionary:
	for a in w.animals:
		if not is_instance_valid(a) or a.dead or a.is_predator() or w.pen_of(a.cell) > 0:
			continue
		# das Tier muss innen stehen; die Mitte des Geheges darf bis zu 2 Felder daneben liegen
		for oy in [0, -1, 1, -2, 2]:
			for ox in [0, -1, 1, -2, 2]:
				var p := _pen_at(w, a.cell + Vector2i(ox, oy))
				if not p.is_empty():
					return p
	return {}


## Gehege 7 x 7 um mid: der Rand wird Zaun (oder ist schon dicht), innen steht kein Gebäude.
static func _pen_at(w, mid: Vector2i) -> Dictionary:
	var ring := []
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var c := mid + Vector2i(dx, dy)
			if not w.is_inside(c) or w.building_at.has(c):
				return {}
			if maxi(absi(dx), absi(dy)) == 3:
				if w.can_place("zaun", c):
					ring.append(c)
				elif w.animal_walkable(c):
					return {}  # offene Stelle, die sich nicht schließen lässt
	if ring.size() < 8:
		return {}
	for lc in [mid + Vector2i(-1, -5), mid + Vector2i(-1, 4), mid + Vector2i(4, -1), mid + Vector2i(-6, -1)]:
		if w.can_place("jagdhuette", lc):
			return {"ring": ring, "lodge": lc}
	return {}


static func _other_settled(w) -> Array:
	return Sea.all_worlds().filter(func(o): return o != w and not o.settlers.is_empty() and Sea.meta(int(o.island_id)).get("state", "") == "settled")


static func _surplus_out(w) -> Dictionary:
	var goods := {}
	var heads := maxf(1.0, float(w.settlers.size()))
	if KiBrain.food_days(w) > 6.0:
		for id in Data.food_ids():
			var a: int = Game.amount(id, w) / 3
			if a >= 5:
				goods[id] = mini(a, int(heads) * 6)
	var wood: int = int(Extras.above_reserve("holz", w)) / 3
	if wood >= 5:
		goods["holz"] = wood
	for id in ["bretter", "ziegel", "werkzeug", "stein"]:
		var a: int = Game.amount(id, w) / 4
		if a >= 5:
			goods[id] = a
	return goods


static func _raw_surplus(o) -> Dictionary:
	var goods := {}
	for id in ["erz", "kohle", "gold", "stein", "lehm", "eisen"]:
		var a: int = Game.amount(id, o) - 40
		if a >= 10:
			goods[id] = a
	return goods


static func _has_route(a: int, b: int) -> bool:
	for sh in Sea.ships:
		if sh.route.size() >= 2 and not Sea.is_trip(sh):
			var ids: Array = sh.route.map(func(st): return int(st.island))
			if a in ids and b in ids:
				return true
	return false


static func _route_target(w):
	for o in _other_settled(w):
		if not _has_route(int(w.island_id), int(o.island_id)):
			return o
	return null


static func _route_ship(w, o) -> Dictionary:
	for sh in Sea.idle_ships(int(w.island_id)):
		if Sea.is_trip(sh) or not sh.route.is_empty() or Sea.is_expedition(sh):
			continue
		if Sea.can_visit(sh.type, int(w.island_id)) and Sea.can_visit(sh.type, int(o.island_id)):
			return sh
	return {}


static func _limit_pick(w) -> String:
	var best := ""
	var best_v := 99
	for id in w.stock:
		if not Data.resources.has(id) or Data.resources[id].get("category", "") == "food" or id in ["holz", "kohle", "strom"]:
			continue
		if Game.limit_of(id, w) >= 0:
			continue
		var v: int = Game.amount(id, w) * Data.good_size(id)
		if v > best_v:
			best_v = v
			best = id
	return best


static func _limit_full(w) -> String:
	for id in w.stock:
		var lim: int = Game.limit_of(id, w)
		if lim >= 0 and Game.amount(id, w) >= int(lim * 0.9):
			return id
	return ""


static func _keep_pick(w, food: bool) -> String:
	# Nahrung: Zutat einer Küche hier (z. B. Weizen für die Mühle); sonst: Baustoff mit dem größten Vorrat
	var best := ""
	var best_v := 19
	if food:
		for b in w.buildings:
			if not b.complete or not b.def.has("production"):
				continue
			for id in b.prod_def().get("inputs", {}):
				if Data.resources.get(id, {}).get("category", "") == "food" and Game.amount(id, w) - Game.food_keep_of(id, w) > best_v:
					best_v = Game.amount(id, w) - Game.food_keep_of(id, w)
					best = id
	else:
		for id in ["bretter", "ziegel", "stein", "eisen", "werkzeug", "glas", "stahl"]:
			if Game.amount(id, w) - Game.food_keep_of(id, w) > best_v:
				best_v = Game.amount(id, w) - Game.food_keep_of(id, w)
				best = id
	return best


static func _keep_set(w, food: bool) -> String:
	for id in w.stock:
		if Game.food_keep_of(id, w) > 0 and (Data.resources.get(id, {}).get("category", "") == "food") == food:
			return id
	return ""


# ---------------------------------------------------------------- Geht die Handlung gerade?
static func can(w, act: String) -> bool:
	if act in KiBrain.BUILD_ACTS:
		return KiBrain.can_act(w, act)
	if act.begins_with("bau:"):
		var t := act.substr(4)
		if _sites_full(w) or not _affordable(w, t):
			return false
		if Data.buildings[t].get("unique", false) and Admin.exists(t):
			return false
		if t == "zukunftsstadt" and _count_type(w, t) > 0:
			return false
		return true
	match act:
		"ausbau_lager", "ausbau_wissen", "ausbau_amt", "ausbau_werft":
			return not _sites_full(w) and not _upgradable(w, _up_pred(act)).is_empty()
		"schmuck":
			return not _sites_full(w) and _decor_pick(w) != ""
		"setzling":
			if not Game.is_unlocked("setzling"):
				return false
			var open: int = w.buildings.filter(func(b): return not b.complete and b.type == "setzling").size()
			return open < 12 and not _tree_cells(w, 1).is_empty()
		"gehege":
			if not Game.is_unlocked("zaun") or not Game.is_unlocked("jagdhuette") or _sites_full(w) or w.lodges().size() >= 2:
				return false
			if Game.amount("holz", w) < 90 or not Planner.missing_cost(w, "jagdhuette").is_empty():
				return false
			return not _pen_plan(w).is_empty()
		"verwalter":
			var aw = Admin.admin_world()
			return aw == w and Admin.local_manager() == null and KiBrain._adults(w).any(func(s): return KiBrain._movable(s))
		"abriss_werkstatt":
			return _idle_shop(w) != null
		"abriss_haus":
			return _empty_house(w) != null
		"abriss_feld":
			return _spare_field(w) != null
		"versetzen":
			return not _move_pick(w).is_empty()
		"pause":
			return w.buildings.any(func(b): return _free(b) and b.complete and b.def.has("production") and not b.paused \
				and not b.def.get("ships", false) and _outputs_full(w, b))
		"weiter":
			return w.buildings.any(func(b): return _free(b) and b.paused and b.has_meta("ki_paused") and not _outputs_full(w, b))
		"seemann":
			return Sea.ships_at(int(w.island_id)).any(func(sh): return sh.state == "dock" and Sea.crew_missing(sh) > 0) \
				and KiBrain._adults(w).size() >= 6
		"fracht_hin":
			return not _surplus_out(w).is_empty() and _other_settled(w).any(func(o): return not Steward._free_ship(int(w.island_id), int(o.island_id)).is_empty())
		"fracht_her":
			return _other_settled(w).any(func(o): return not _raw_surplus(o).is_empty() and not Steward._free_ship(int(o.island_id), int(w.island_id)).is_empty())
		"route":
			var o = _route_target(w)
			return o != null and not _route_ship(w, o).is_empty()
		"route_weg":
			return Sea.ships_at(int(w.island_id)).any(func(sh): return sh.state == "dock" and sh.route.size() >= 2 and not Sea.is_trip(sh))
		"limit":
			return _limit_pick(w) != ""
		"limit_frei":
			return _limit_full(w) != ""
		"reserve":
			return _keep_pick(w, false) != ""
		"reserve_weg":
			return _keep_set(w, false) != ""
		"nicht_essen":
			return _keep_pick(w, true) != ""
		"nicht_essen_weg":
			return _keep_set(w, true) != ""
	return false


static func _decor_pick(w) -> String:
	var best := ""
	var best_c := 1 << 30
	for t in Data.buildings:
		var d: Dictionary = Data.buildings[t]
		if not d.has("decor") or d.has("tile") or not d.get("buildable", false) or not _affordable(w, t):
			continue
		var c := 0
		for id in d.get("cost", {}):
			c += int(d.cost[id])
		c += _count_type(w, t) * 20  # Abwechslung: was schon oft steht, kommt später
		if c < best_c:
			best_c = c
			best = t
	return best


# ---------------------------------------------------------------- Ausführen
## Führt die Handlung aus. Gibt einen kurzen Text für Meldung und Verlauf zurück ("" = ging nicht).
static func do(w, act: String) -> String:
	if act in KiBrain.BUILD_ACTS:
		return KiBrain.act_build(w, act)
	var txt := ""
	if act.begins_with("bau:"):
		var t := act.substr(4)
		if _place(w, t) != null:
			txt = "baut %s" % Data.buildings[t].name
	else:
		match act:
			"ausbau_lager", "ausbau_wissen", "ausbau_amt", "ausbau_werft":
				var c: Array = _upgradable(w, _up_pred(act))
				if not c.is_empty():
					var old: String = c[0].def.name
					var nb = w.upgrade_building(c[0])
					if nb != null:
						nb.set_meta("ki_site", true)
						txt = "baut %s zu %s aus" % [old, nb.def.name]
			"schmuck":
				var t := _decor_pick(w)
				if t != "" and _place(w, t) != null:
					txt = "baut %s" % Data.buildings[t].name
			"setzling":
				var n := 0
				for c in _tree_cells(w, 6):
					if w.place_building("setzling", c, false) != null:
						n += 1
				if n > 0:
					txt = "lässt %d Bäume pflanzen" % n
			"gehege":
				var p := _pen_plan(w)
				if not p.is_empty():
					for c in p.ring:
						w.place_building("zaun", c, false)
					var lb = w.place_building("jagdhuette", p.lodge, false)
					if lb != null:
						lb.set_meta("ki_site", true)
					txt = "legt ein Gehege mit Jagdhütte an"
			"verwalter":
				var pool: Array = KiBrain._adults(w).filter(func(s): return KiBrain._movable(s))
				var free: Array = pool.filter(func(s): return s.job == "frei")
				var s = free[0] if not free.is_empty() else pool[0]
				if JobDesk.assign(s, "verwalter", "ki", -1.0, true):
					txt = "macht %s zum Verwalter" % s.display_name
			"abriss_werkstatt":
				var b = _idle_shop(w)
				txt = "reißt %s ab (steht still)" % b.def.name
				w.demolish(b)
			"abriss_haus":
				var b = _empty_house(w)
				txt = "reißt %s ab (leer)" % b.def.name
				w.demolish(b)
			"abriss_feld":
				var b = _spare_field(w)
				txt = "gibt ein Getreidefeld auf"
				w.demolish(b)
			"versetzen":
				var m := _move_pick(w)
				if not m.is_empty() and w.move_building(m[0], m[1]):
					txt = "versetzt %s näher an die Siedlung" % m[0].def.name
			"pause":
				for b in w.buildings:
					if _free(b) and b.complete and b.def.has("production") and not b.paused and not b.def.get("ships", false) and _outputs_full(w, b):
						b.paused = true
						b.set_meta("ki_paused", true)
						txt = "hält %s an (Lager voll)" % b.def.name
						break
			"weiter":
				for b in w.buildings:
					if _free(b) and b.paused and b.has_meta("ki_paused") and not _outputs_full(w, b):
						b.paused = false
						b.remove_meta("ki_paused")
						txt = "lässt %s weiterarbeiten" % b.def.name
						break
			"seemann":
				for sh in Sea.ships_at(int(w.island_id)):
					if sh.state == "dock" and Sea.crew_missing(sh) > 0:
						Sea.fill_crew(sh)
						if Sea.crew_missing(sh) > 0 and Sea.hire_sailor(sh, "ki") == "":
							txt = "heuert einen Seemann für die %s an" % sh.name
						break
			"fracht_hin":
				var best = null
				for o in _other_settled(w):
					if best == null or KiBrain.food_days(o) < KiBrain.food_days(best):
						best = o
				var goods := _surplus_out(w)
				if best != null and Steward.ship_now(int(w.island_id), int(best.island_id), goods, "ki"):
					txt = "schickt %s nach %s" % [Sea.goods_text(goods), Sea.island_name(best)]
			"fracht_her":
				for o in _other_settled(w):
					var goods := _raw_surplus(o)
					if not goods.is_empty() and Steward.ship_now(int(o.island_id), int(w.island_id), goods, "ki"):
						txt = "holt %s von %s" % [Sea.goods_text(goods), Sea.island_name(o)]
						break
			"route":
				var o = _route_target(w)
				var sh := _route_ship(w, o) if o != null else {}
				if not sh.is_empty():
					Sea.fill_crew(sh)
					if Sea.crew_missing(sh) > 0:
						Sea.hire_sailor(sh, "ki")
					var out := {"holz": 20}
					var foods: Array = Data.food_ids()
					foods.sort_custom(func(a, b): return Game.amount(a, w) > Game.amount(b, w))
					if not foods.is_empty():
						out[foods[0]] = 30
					sh.route = [{"island": int(w.island_id), "load": out, "drop_all": true, "drop": {}},
						{"island": int(o.island_id), "load": {"erz": 40, "kohle": 40, "stein": 20}, "drop_all": true, "drop": {}}]
					sh["trip"] = false
					sh.leg = 0
					sh.paused = false
					Sea.islands_changed.emit()
					txt = "richtet eine Route %s - %s ein (%s)" % [Sea.island_name(w), Sea.island_name(o), sh.name]
			"route_weg":
				for sh in Sea.ships_at(int(w.island_id)):
					if sh.state == "dock" and sh.route.size() >= 2 and not Sea.is_trip(sh):
						Sea.cancel_trip(sh)
						txt = "hebt die Route der %s auf" % sh.name
						break
			"limit":
				var id := _limit_pick(w)
				Game.set_limit(id, Game.amount(id, w), w)
				txt = "setzt die Höchstmenge für %s auf %d" % [Data.resource_name(id), Game.limit_of(id, w)]
			"limit_frei":
				var id := _limit_full(w)
				Game.set_limit(id, -1, w)
				txt = "hebt die Höchstmenge für %s auf" % Data.resource_name(id)
			"reserve", "nicht_essen":
				var id := _keep_pick(w, act == "nicht_essen")
				Game.set_food_keep(id, Game.food_keep_of(id, w) + 20, w)
				txt = "%s: %d %s" % ["Nicht essen" if act == "nicht_essen" else "Reserve (nicht verarbeiten)", Game.food_keep_of(id, w), Data.resource_name(id)]
			"reserve_weg", "nicht_essen_weg":
				var id := _keep_set(w, act == "nicht_essen_weg")
				Game.set_food_keep(id, Game.food_keep_of(id, w) - 20, w)
				txt = "%s gesenkt: %d %s" % ["Nicht essen" if act == "nicht_essen_weg" else "Reserve", Game.food_keep_of(id, w), Data.resource_name(id)]
	if txt != "":
		Game.notify_at(w, "KI %s." % txt, "hammer", "verwaltung")
	return txt


## Überstunden und Schichtarbeit: je Beruf an, solange der Wert seiner Zeile über 0 liegt (nur auf der Insel der
## Verwaltung, dort gelten Anordnungen).
static func settings_tick(w, x: PackedFloat32Array) -> void:
	if not KiBrain.allowed("arbeitszeit") or Admin.admin_world() != w or not Admin.active_on(w):
		return
	for j in OT_JOBS:
		for kind in ["ot", "schicht"]:
			var act: String = kind + ":" + j
			if not KiBrain.aweights.has(act):
				continue
			var want: bool = KiBrain.act_value(w, act, x) > 0.0
			var what := "ot" if kind == "ot" else "sh"
			if want == Admin.ordered(j, what):
				continue
			if kind == "ot":
				if Admin.set_overtime(j, want, true) != "":
					continue
			else:
				Admin.set_shift(j, want, true)
			KiBrain.built_log[act] = int(KiBrain.built_log.get(act, 0)) + 1
			KiBrain.note(w, "%s für %s %s" % ["Überstunden" if kind == "ot" else "Schichtarbeit", Data.jobs[j].name, "an" if want else "aus"])
