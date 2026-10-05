extends Node
## Seefahrt (Etappe 3): alle Inseln, die Seekarte und Schiffsreisen.
## Jede besiedelte Insel ist eine eigene World. Nur die aktive Insel (Game.world) ist
## sichtbar, die anderen leben unsichtbar weiter. Jede Insel hat ihr eigenes Lager;
## Waren kommen nur per Schiff auf eine andere Insel. Schiffe brauchen Seeleute,
## Liegeplaetze in Haefen und fahren einzeln oder auf festen Routen.

signal islands_changed
signal island_switched(world)

## Meta-Daten je Insel: {id, name, biome, seed, size, pos: [x, y], state, found_day, dens: [[typ, anzahl]]}
## state: "discovered" (entdeckt), "settled" (besiedelt), "lost" (verloren)
var islands: Array = []
var worlds: Dictionary = {}  # Insel-ID -> World (nur besiedelte Inseln)
## Reisen: {kind: "explore"|"settle"|"ship", ship (ID, fehlt in alten Spielstaenden), from, to, depart,
## arrive, settlers: [Siedler-Daten der Fahrgaeste], crew: [Siedler-Daten der Besatzung]}
var voyages: Array = []
var world_root: Node = null  # Knoten, unter dem die Inseln haengen (main)


# ---------------------------------------------------------------- Inseln
func reset(home_seed: int) -> void:
	clear_worlds()
	islands = [{"id": 0, "name": tr("Heimatinsel"), "biome": "heimat", "seed": home_seed, "size": int(Data.bal("map_size", 64)),
		"pos": [0.0, 0.0], "state": "settled", "found_day": 1, "dens": []}]
	voyages = []
	ships = []
	next_ship = 1
	islands_changed.emit()


func clear_worlds() -> void:
	for w in worlds.values():
		if is_instance_valid(w):
			if w.get_parent():
				w.get_parent().remove_child(w)
			w.queue_free()
	worlds = {}


func meta(id: int) -> Dictionary:
	for m in islands:
		if int(m.id) == id:
			return m
	return {}


func biome_def(m: Dictionary) -> Dictionary:
	return Data.islands.get(m.get("biome", "heimat"), {})


func biome_name(m: Dictionary) -> String:
	return biome_def(m).get("name", tr("Insel"))


func all_worlds() -> Array:
	return worlds.values().filter(func(w): return is_instance_valid(w))


func settled_islands() -> Array:
	return islands.filter(func(m): return m.state == "settled")


func island_name(w) -> String:
	return meta(w.island_id).get("name", tr("Insel")) if w else ""


## Alle lebenden Siedler, auch die auf See.
func total_people() -> int:
	var n := 0
	for w in all_worlds():
		n += w.settlers.size()
	for v in voyages:
		n += v.settlers.size() + v.get("crew", []).size()
	return n


func people_at_sea() -> int:
	var n := 0
	for v in voyages:
		n += v.settlers.size() + v.get("crew", []).size()
	return n


func distance(a: int, b: int) -> float:
	var pa: Array = meta(a).get("pos", [0, 0])
	var pb: Array = meta(b).get("pos", [0, 0])
	return Vector2(float(pa[0]) - float(pb[0]), float(pa[1]) - float(pb[1])).length()


## Neue Insel Nummer `index`: die ersten drei sind Palmen-, Wald- und Felseninsel,
## danach zufaellig. Je weiter draussen, desto mehr Tierbauten.
func make_island(index: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.seed_value, index, "insel"])
	var kinds := ["tropen", "wald", "berg"]
	var biome: String = kinds[index - 1] if index <= 3 else kinds[rng.randi() % kinds.size()]
	var b: Dictionary = Data.islands[biome]
	var size := rng.randi_range(int(b.size[0]), int(b.size[1]))
	var ang := index * 2.39996 + rng.randf_range(-0.35, 0.35)
	var dist := 1.6 + index * 0.75 + rng.randf_range(-0.2, 0.3)
	var dens := []
	var extra := (index - 1) / 3
	for i in b.get("dens", []).size():
		var e: Array = b.dens[i]
		var n := rng.randi_range(int(e[1]), int(e[2])) + (extra if i == 0 else 0)
		if n > 0:
			dens.append([e[0], n])
	var used := islands.map(func(m): return m.name)
	var pool: Array = b.get("names", [tr("Insel")])
	var name: String = pool[rng.randi() % pool.size()]
	for i in 12:
		if not name in used:
			break
		name = pool[rng.randi() % pool.size()]
	if name in used:
		name = "%s %d" % [name, index]
	return {"id": index, "name": name, "biome": biome, "seed": rng.randi() % 1000000, "size": size,
		"pos": [cos(ang) * dist, sin(ang) * dist], "state": "discovered", "found_day": Game.day(), "dens": dens}


## Gefahren einer Insel als Tierarten, z. B. ["wolf", "baer"].
func dangers(m: Dictionary) -> Array:
	var out := []
	for e in m.get("dens", []):
		var a: String = Data.nodes.get(e[0], {}).get("spawns", "")
		if a != "" and not a in out:
			out.append(a)
	return out


# ---------------------------------------------------------------- Welten
func create_world_node(id: int) -> World:
	var w := World.new()
	w.name = "Insel%d" % id
	w.island_id = id
	w.visible = false
	world_root.add_child(w)
	world_root.move_child(w, 0)
	worlds[id] = w
	return w


func switch_to(id: int) -> void:
	var w = worlds.get(id)
	if w == null or not is_instance_valid(w):
		return
	var old = Game.world
	if old and is_instance_valid(old) and old != w:
		old.cancel_placement()
		old.visible = false
		if meta(old.island_id).get("state", "") == "lost" and not worlds.values().has(old):
			old.queue_free()
	Game.world = w
	w.visible = true
	Game.select(null)
	island_switched.emit(w)
	Game.population_changed.emit()


func island_lost(w) -> void:
	var m := meta(w.island_id)
	if m.is_empty() or m.state == "lost":
		return
	m.state = "lost"
	worlds.erase(w.island_id)
	_ships_lost(int(w.island_id))
	Game.notify(tr("%s ist verloren! Dort lebt niemand mehr.") % m.name, "abriss")
	Sound.play("verloren")
	var others := all_worlds()
	if Game.world == w and not others.is_empty():
		var best = others[0]
		for o in others:
			if o.settlers.size() > best.settlers.size():
				best = o
		switch_to(best.island_id)
	if not others.is_empty():
		w.visible = false
		w.queue_free()
	Game.refresh_effects()
	islands_changed.emit()


# ---------------------------------------------------------------- Schiffe und Haefen
## Ein Schiff: {id, type, name, home, at, state, until, crew: [Siedler-IDs], cargo: {Ware: Menge},
## route: [{island, load: {Ware: Menge}}], leg, paused, note}
## state: "dock" (liegt bei Insel `at`), "load" (laedt bis `until`), "sea" (auf Fahrt, siehe voyages)
## `home` ist die Insel, deren Liegeplatz das Schiff belegt. Schiffe entstehen als Ware
## (z. B. "kogge") in einer Werft und werden sofort zu einem Schiff.
const SHIP_NAMES := ["Möwe", "Seestern", "Albatros", "Delfin", "Wellenreiter", "Sturmvogel", "Nordstern",
	"Kormoran", "Seeadler", "Glückauf", "Hoffnung", "Morgenrot", "Krabbe", "Seepferdchen", "Brise",
	"Perle", "Abendstern", "Walfisch", "Muschel", "Seeschwalbe", "Treue", "Fortuna", "Meeresblick", "Tümmler"]
const BEACH_RATE := 15.0  # Ladung (Stauraum) je Stunde ohne Hafen

var ships: Array = []
var next_ship: int = 1
var _ship_tick: float = 0.0


func ship_def(sh: Dictionary) -> Dictionary:
	return Data.ships.get(sh.type, {})


func ship_by_id(id: int) -> Dictionary:
	for sh in ships:
		if int(sh.id) == id:
			return sh
	return {}


func ship_label(sh: Dictionary) -> String:
	return "%s (%s)" % [sh.name, ship_def(sh).get("name", tr("Schiff"))]


## Schiffe, die gerade bei einer Insel liegen (nicht auf See).
func ships_at(island_id: int) -> Array:
	return ships.filter(func(sh): return sh.state != "sea" and int(sh.at) == island_id)


func ships_of(island_id: int) -> Array:
	return ships.filter(func(sh): return int(sh.home) == island_id)


func harbor_level(w) -> int:
	var lv := 0
	if w and is_instance_valid(w):
		for b in w.buildings:
			if b.complete and b.def.has("harbor"):
				lv = max(lv, int(b.def.harbor.get("level", 1)))
	return lv


func harbor_level_name(lv: int) -> String:
	return [tr("kein Hafen (nur Ruderboote am Strand)"), tr("Steg (Ruderboote)"), tr("Hafen (bis mittlere Schiffe)"), tr("Großer Hafen (alle Schiffe)")][clamp(lv, 0, 3)]


## Kann ein Schiff dieser Art bei der Insel anlegen? Ruderboote landen ueberall am Strand.
func can_visit(type: String, island_id: int) -> bool:
	var sz := int(Data.ships.get(type, {}).get("size", 1))
	if sz <= 1:
		return true
	return harbor_level(worlds.get(island_id)) >= sz


## Liegeplaetze einer Insel als Groessen, groesste zuerst.
func berths(w) -> Array:
	var out := []
	if w and is_instance_valid(w):
		for b in w.buildings:
			if b.complete and b.def.has("harbor"):
				for s in b.def.harbor.get("berths", []):
					out.append(int(s))
	out.sort()
	out.reverse()
	return out


## Passt noch ein Schiff der Groesse `size` an einen freien Liegeplatz dieser Insel?
func free_berth(w, size: int) -> bool:
	var free := berths(w)
	var mine := ships_of(w.island_id).map(func(sh): return int(ship_def(sh).get("size", 1)))
	mine.append(size)
	mine.sort()
	mine.reverse()
	# groesste Schiffe zuerst an den kleinsten passenden Platz
	for s in mine:
		var best := -1
		for i in free.size():
			if free[i] >= s and (best < 0 or free[i] < free[best]):
				best = i
		if best < 0:
			return false
		free.remove_at(best)
	return true


func berth_text(w) -> String:
	return tr("Liegeplätze: %d belegt von %d") % [ships_of(w.island_id).size(), berths(w).size()]


## Ladetempo einer Ware an dieser Insel (Stauraum je Stunde). Spezielle Kais laden ihre Waren schneller.
func load_rate(w, res: String) -> float:
	var r := BEACH_RATE
	if w and is_instance_valid(w):
		for b in w.buildings:
			if b.complete and b.def.has("harbor"):
				var h: Dictionary = b.def.harbor
				r = max(r, float(h.get("rate", BEACH_RATE)))
				if res in h.get("goods", []):
					r = max(r, float(h.get("goods_rate", 0)))
	return r


func cargo_volume(sh: Dictionary) -> int:
	var n := 0
	for id in sh.cargo:
		n += int(sh.cargo[id]) * Data.good_size(id)
	return n


func cargo_room(sh: Dictionary) -> int:
	return max(0, int(ship_def(sh).get("cargo", 0)) - cargo_volume(sh))


func passenger_capacity(sh: Dictionary) -> int:
	return int(ship_def(sh).get("passengers", 4)) + int(Game.eff_add("ship_capacity"))


## Fahrzeit in Tagen fuer ein Schiff (ohne Schiff: Ruderboot).
func voyage_days(from_id: int, to_id: int, type: String = "boot") -> float:
	var d := distance(from_id, to_id)
	var spd := float(Data.ships.get(type, {}).get("speed", 1.0))
	return (float(Data.bal("voyage_days_base")) + float(Data.bal("voyage_days_per_dist")) * d) / (Game.eff("ship_speed") * spd) * Seasons.sail_mult()


func _new_ship(type: String, island_id: int) -> Dictionary:
	var used := ships.map(func(s): return s.name)
	var name: String = tr(SHIP_NAMES[(next_ship * 7) % SHIP_NAMES.size()])
	if name in used:
		for n in SHIP_NAMES:
			if not tr(n) in used:
				name = tr(n)
				break
	if name in used:
		name = "%s %d" % [name, next_ship]
	var sh := {"id": next_ship, "type": type, "name": name, "home": island_id, "at": island_id, "state": "dock",
		"until": 0.0, "crew": [], "cargo": {}, "route": [], "leg": 0, "paused": false, "note": ""}
	next_ship += 1
	ships.append(sh)
	return sh


## Siedler der Besatzung, die gerade auf der Insel des Schiffs sind.
func crew_present(sh: Dictionary) -> Array:
	var w = worlds.get(int(sh.at))
	if w == null or not is_instance_valid(w):
		return []
	var ids: Array = sh.crew.map(func(x): return int(x))
	return w.settlers.filter(func(s): return int(s.id) in ids)


func _assigned_ids() -> Dictionary:
	var out := {}
	for sh in ships:
		for id in sh.crew:
			out[int(id)] = int(sh.id)
	return out


## Fehlende Besatzung mit Seeleuten der Insel auffuellen.
func fill_crew(sh: Dictionary) -> void:
	if sh.state == "sea":
		return
	var present := crew_present(sh)
	sh.crew = present.map(func(s): return int(s.id))
	var need: int = int(ship_def(sh).get("crew", 1)) - sh.crew.size()
	if need <= 0:
		return
	var w = worlds.get(int(sh.at))
	if w == null:
		return
	var taken := _assigned_ids()
	for s in w.settlers:
		if need <= 0:
			break
		if s.is_adult() and s.job == "seemann" and not taken.has(int(s.id)):
			sh.crew.append(int(s.id))
			need -= 1


func crew_missing(sh: Dictionary) -> int:
	return max(0, int(ship_def(sh).get("crew", 1)) - crew_present(sh).size())


## Macht einen Siedler der Insel zum Seemann (zuerst Freie, dann die mit der kleinsten Fertigkeit).
func hire_sailor(sh: Dictionary) -> String:
	var w = worlds.get(int(sh.at))
	if w == null or sh.state == "sea":
		return tr("Das Schiff ist auf See.")
	fill_crew(sh)
	if crew_missing(sh) <= 0:
		return ""
	var taken := _assigned_ids()
	var cands: Array = w.settlers.filter(func(s): return s.is_adult() and not taken.has(int(s.id)) and s.job != "seemann")
	if cands.size() <= 1:
		return tr("Auf %s ist niemand mehr frei, der anheuern kann.") % island_name(w)
	cands.sort_custom(func(a, b): return _hire_score(a) < _hire_score(b))
	cands[0].set_job("seemann")
	fill_crew(sh)
	Game.notify(tr("%s heuert auf der %s an.") % [cands[0].display_name, sh.name], "boot")
	return ""


func _hire_score(s) -> float:
	var v := 0.0 if s.job == "frei" else 5.0
	if s.job in ["baumeister", "forscher"]:
		v += 5.0
	for k in s.skills:
		v = max(v, float(s.skills[k]) + (0.0 if s.job == "frei" else 5.0))
	return v


## Warum das Schiff nicht ablegen kann ("" = bereit).
func ship_blocker(sh: Dictionary) -> String:
	if sh.state == "sea":
		return tr("Das Schiff ist auf See.")
	if sh.state == "load":
		return tr("Das Schiff wird gerade beladen.")
	fill_crew(sh)
	var miss := crew_missing(sh)
	if miss > 0:
		return tr("Es fehlen %d Seeleute. Gib Siedlern auf %s den Beruf Seemann.") % [miss, island_name(worlds.get(int(sh.at)))]
	var w = worlds.get(int(sh.at))
	if w and crew_present(sh).size() >= w.settlers.size():
		return tr("Die Seeleute sind die letzten Siedler auf %s und bleiben dort.") % island_name(w)
	return ""


## Schiff legt ab. Besatzung und Fahrgaeste verlassen die Insel.
func _depart(sh: Dictionary, to_id: int, kind: String, passengers: Array = [], days: float = -1.0) -> void:
	var from_id := int(sh.at)
	var w = worlds.get(from_id)
	var crew_data := []
	for s in crew_present(sh):
		crew_data.append(s.serialize())
		w.remove_settler(s)
	var datas := []
	for s in passengers:
		if is_instance_valid(s):
			datas.append(s.serialize())
			w.remove_settler(s)
	if days < 0.0:
		days = voyage_days(from_id, to_id, sh.type)
	voyages.append({"kind": kind, "ship": int(sh.id), "from": from_id, "to": to_id, "depart": Game.time_days,
		"arrive": Game.time_days + days, "settlers": datas, "crew": crew_data})
	sh.state = "sea"
	sh.at = -1
	sh.note = ""
	if w:
		w.sail_away(ship_def(sh).get("sprite", "boat"))
		w.sync_ships()
	if not datas.is_empty():
		Game.on_population_changed()
	islands_changed.emit()


## Laedt Waren der Insel ins Schiff, so viel passt. Gibt die geladene Menge je Ware zurueck.
func load_goods(sh: Dictionary, goods: Dictionary) -> Dictionary:
	var w = worlds.get(int(sh.at))
	var got := {}
	for id in goods:
		var size: int = max(1, Data.good_size(id))
		var n: int = min(int(goods[id]), Game.amount(id, w), cargo_room(sh) / size)
		if n > 0:
			Game.take_stock(id, n, w)
			sh.cargo[id] = int(sh.cargo.get(id, 0)) + n
			got[id] = n
	return got


## Laedt Waren ab, soweit im Lager Platz ist. `only` leer = alles.
func unload_goods(sh: Dictionary, keep: Array = []) -> Dictionary:
	var w = worlds.get(int(sh.at))
	var got := {}
	for id in sh.cargo.keys():
		if id in keep:
			continue
		var n := Game.add_stock(id, int(sh.cargo[id]), w)
		if n > 0:
			got[id] = n
		sh.cargo[id] = int(sh.cargo[id]) - n
		if int(sh.cargo[id]) <= 0:
			sh.cargo.erase(id)
	return got


func _handling_days(w, moved: Dictionary) -> float:
	var hours := 0.0
	for id in moved:
		hours += float(int(moved[id]) * max(1, Data.good_size(id))) / load_rate(w, id)
	return max(0.02, hours / 24.0) if not moved.is_empty() else 0.01


func goods_text(goods: Dictionary) -> String:
	var parts := []
	for id in goods:
		if int(goods[id]) > 0:
			parts.append("%d %s" % [int(goods[id]), Data.resource_name(id)])
	return ", ".join(parts) if not parts.is_empty() else tr("nichts")


## Kurzer Zustand fuer die Liste.
func ship_status(sh: Dictionary) -> String:
	if sh.state == "sea":
		for v in voyages:
			if int(v.get("ship", -1)) == int(sh.id):
				var to: String = meta(int(v.to)).get("name", "?") if v.kind != "explore" else tr("unbekannte Gewässer")
				var h := int(ceil(max(0.0, float(v.arrive) - Game.time_days) * 24.0))
				return tr("Unterwegs nach %s, noch %d Std.") % [to, h] if v.kind != "explore" else tr("Erkundet das Meer, zurück in %d Std.") % h
		return tr("Auf See")
	var where: String = meta(int(sh.at)).get("name", "?")
	if sh.state == "load":
		return tr("Lädt in %s") % where
	if sh.note != "":
		return "%s: %s" % [where, sh.note]
	if not sh.route.is_empty() and not sh.paused:
		return tr("In %s") % where
	return tr("Liegt in %s") % where


func _ship_tick_all() -> void:
	# Fertige Schiffe aus den Werften
	for w in all_worlds():
		for t in Data.ships:
			var n := int(w.stock.get(t, 0))
			if n > 0:
				w.stock[t] = 0
				for i in n:
					var sh := _new_ship(t, w.island_id)
					fill_crew(sh)
					Game.notify_at(w, tr("Stapellauf! Die %s liegt bereit.") % ship_label(sh), Data.ships[t].get("icon", "boot"), "see")
					Sound.play_on("entdeckt", w)
				w.sync_ships()
				islands_changed.emit()
	for sh in ships.duplicate():
		if sh.state == "sea":
			continue
		var w = worlds.get(int(sh.at))
		if w == null or not is_instance_valid(w):
			continue
		if sh.state == "load":
			if Game.time_days >= float(sh.until):
				sh.state = "dock"
				if not sh.route.is_empty():
					sh.leg = (int(sh.leg) + 1) % sh.route.size()
			continue
		if sh.route.size() >= 2 and not sh.paused:
			_route_step(sh, w)
		elif not sh.cargo.is_empty() and sh.route.is_empty():
			# Einzelfahrt: am Ziel alles abladen
			var got := unload_goods(sh)
			if not got.is_empty():
				sh.state = "load"
				sh.until = Game.time_days + _handling_days(w, got)
			sh.note = "" if sh.cargo.is_empty() else tr("Lager voll, Ladung bleibt an Bord")


func _route_step(sh: Dictionary, w) -> void:
	# Halte auf verlorenen Inseln fallen weg
	sh.route = sh.route.filter(func(st): return meta(int(st.island)).get("state", "") == "settled")
	if sh.route.size() < 2:
		sh.note = tr("Route braucht zwei Inseln")
		return
	sh.leg = int(sh.leg) % sh.route.size()
	var stop: Dictionary = sh.route[sh.leg]
	var target := int(stop.island)
	if target == int(sh.at):
		var keep: Array = stop.get("load", {}).keys()
		var moved := unload_goods(sh, keep)
		var want := {}
		for id in stop.get("load", {}):
			want[id] = max(0, int(stop.load[id]) - int(sh.cargo.get(id, 0)))
		var got := load_goods(sh, want)
		for id in got:
			moved[id] = int(moved.get(id, 0)) + int(got[id])
		sh.state = "load"
		sh.until = Game.time_days + _handling_days(w, moved)
		sh.note = ""
		return
	if not can_visit(sh.type, target):
		sh.note = tr("%s hat keinen passenden Hafen") % meta(target).get("name", "?")
		sh.leg = (int(sh.leg) + 1) % sh.route.size()
		return
	var why := ship_blocker(sh)
	if why != "":
		sh.note = tr("wartet auf Besatzung (%d fehlen)") % crew_missing(sh)
		return
	_depart(sh, target, "ship")


# ---------------------------------------------------------------- Reisen
func ship_capacity() -> int:
	return int(Data.bal("ship_base_capacity", 4)) + int(Game.eff_add("ship_capacity"))


func exploring() -> bool:
	return voyages.any(func(v): return v.kind == "explore")


## Freie Schiffe einer Insel: liegen dort, fahren keine Route.
func idle_ships(island_id: int) -> Array:
	return ships_at(island_id).filter(func(sh): return sh.state == "dock" and (sh.route.is_empty() or sh.paused))


## Bestes Schiff fuer eine Erkundung: das schnellste freie mit Besatzung.
func explore_ship(from_world) -> Dictionary:
	var best := {}
	for sh in idle_ships(from_world.island_id):
		if ship_blocker(sh) == "" and (best.is_empty() or float(ship_def(sh).speed) > float(ship_def(best).speed)):
			best = sh
	return best


func can_explore(from_world = null) -> String:
	if from_world == null:
		from_world = Game.world
	if exploring():
		return tr("Ein Schiff ist schon auf Erkundungsfahrt.")
	if idle_ships(from_world.island_id).is_empty():
		return tr("Hier liegt kein freies Schiff. Baue eines in der Werft.")
	if explore_ship(from_world).is_empty():
		return tr("Dem Schiff fehlen Seeleute. Gib Siedlern den Beruf Seemann.")
	return ""


func start_explore(from_world) -> String:
	var err := can_explore(from_world)
	if err != "":
		return err
	var sh := explore_ship(from_world)
	var next := islands.size()
	var probe := make_island(next)
	var d := Vector2(float(probe.pos[0]), float(probe.pos[1])).length()
	var days := (float(Data.bal("explore_days_base")) + float(Data.bal("explore_days_per_dist")) * d) / Game.eff("explore")
	days = days / float(ship_def(sh).get("speed", 1.0)) * Seasons.sail_mult()
	_depart(sh, next, "explore", [], days)
	Game.notify(tr("Die %s sticht in See und sucht nach neuen Inseln.") % ship_label(sh), "boot")
	Sound.play("glocke")
	return ""


## Prueft eine Fahrt mit Siedlern und Waren.
func can_send(from_world, to_id: int, people: Array, sh: Dictionary = {}) -> String:
	var m := meta(to_id)
	if m.is_empty() or m.state == "lost":
		return tr("Diese Insel ist verloren.")
	if from_world.island_id == to_id:
		return tr("Das Schiff ist schon dort.")
	if sh.is_empty():
		return tr("Hier liegt kein freies Schiff. Baue eines in der Werft.")
	if int(sh.at) != from_world.island_id or sh.state != "dock":
		return tr("Das Schiff liegt nicht hier.")
	var why := ship_blocker(sh)
	if why != "":
		return why
	if not can_visit(sh.type, to_id):
		return tr("Die %s ist zu groß für %s. Dort braucht es erst einen %s.") % [sh.name, m.name,
			tr("Großen Hafen") if int(ship_def(sh).size) >= 3 else tr("Hafen")]
	if m.state != "settled" and people.is_empty():
		return tr("Wähle Siedler, die die Insel besiedeln.")
	if people.size() > passenger_capacity(sh):
		return tr("Auf die %s passen nur %d Fahrgäste.") % [sh.name, passenger_capacity(sh)]
	var crew_n := crew_present(sh).size()
	if not people.is_empty() and people.size() + crew_n >= from_world.settlers.size():
		return tr("Mindestens ein Siedler muss auf der Insel bleiben.")
	return ""


## Schickt ein Schiff mit Siedlern und Waren zu einer anderen Insel. Es bleibt dort liegen.
func send_ship(from_world, to_id: int, people: Array, sh: Dictionary, goods: Dictionary = {}) -> String:
	var err := can_send(from_world, to_id, people, sh)
	if err != "":
		return err
	sh.route = []
	sh.paused = false
	var got := load_goods(sh, goods)
	var n := people.size()
	_depart(sh, to_id, "settle" if n > 0 else "ship", people)
	var what := []
	if n > 0:
		what.append(tr("%d Siedler") % n)
	if not got.is_empty():
		what.append(goods_text(got))
	Game.notify(tr("Die %s sticht in See nach %s%s.") % [sh.name, meta(to_id).name,
		(tr(" mit ") + tr(" und ").join(what)) if not what.is_empty() else ""], "boot")
	Sound.play("glocke")
	return ""


## Alter Aufruf (Tests): nimmt das erste freie Schiff.
func send_settlers(from_world, to_id: int, people: Array) -> String:
	var list := idle_ships(from_world.island_id)
	for sh in list:
		fill_crew(sh)
		if crew_missing(sh) > 0:
			hire_sailor(sh)
	for sh in list:
		if can_send(from_world, to_id, people, sh) == "":
			return send_ship(from_world, to_id, people, sh)
	return can_send(from_world, to_id, people, list[0] if not list.is_empty() else {})


func _process(delta: float) -> void:
	if Game.is_over:
		return
	_ship_tick -= delta
	if _ship_tick <= 0.0:
		_ship_tick = 0.4
		_ship_tick_all()
	if voyages.is_empty():
		return
	for v in voyages.duplicate():
		if Game.time_days >= float(v.arrive):
			voyages.erase(v)
			_arrive(v)


## Siedler (Daten) auf einer Insel an Land setzen.
func _land(w, datas: Array, c: Vector2i) -> void:
	for d in datas:
		d["x"] = c.x
		d["y"] = c.y
		d["home"] = 0
		w.spawn_settler(d)


func _arrive(v: Dictionary) -> void:
	var sh := ship_by_id(int(v.get("ship", -1)))
	if v.kind == "explore":
		var m := make_island(int(v.to))
		islands.append(m)
		var danger := dangers(m).map(func(a): return Data.animals[a].name)
		var text := tr("Entdeckt: %s, eine %s!") % [m.name, biome_name(m)]
		text += tr(" Gefahr: %s.") % ", ".join(danger) if not danger.is_empty() else tr(" Keine wilden Tiere gesichtet.")
		Game.notify(text, "kompass")
		Sound.play("entdeckt")
		var back := int(v.from)
		if meta(back).get("state", "") != "settled" and not settled_islands().is_empty():
			back = int(settled_islands()[0].id)
		var home = worlds.get(back)
		if home and is_instance_valid(home):
			if sh.is_empty():
				Game.add_stock("boot", 1, home)  # alte Spielstaende: Boot ohne Schiff
			else:
				_dock(sh, home, v.get("crew", []))
		elif not sh.is_empty():
			ships.erase(sh)
		islands_changed.emit()
		return
	# Ziel verloren? Dann zurueck nach Hause oder zur naechsten bewohnten Insel.
	var dest := int(v.to)
	if meta(dest).get("state", "lost") == "lost":
		if meta(int(v.from)).get("state", "") == "settled":
			dest = int(v.from)
		elif not settled_islands().is_empty():
			dest = int(settled_islands()[0].id)
	var m := meta(dest)
	var w = worlds.get(dest)
	var founded := false
	if w == null or not is_instance_valid(w):
		w = create_world_node(dest)
		w.build_colony(m)
		founded = true
	m.state = "settled"
	var c: Vector2i = w.landing_cell()
	_land(w, v.settlers, c)
	w.assign_homes()
	if sh.is_empty():
		w.add_boat_decor(c)
	else:
		_dock(sh, w, v.get("crew", []))
	var n: int = v.settlers.size()
	if founded:
		Game.notify(tr("Land in Sicht! %d Siedler gründen eine Siedlung auf %s.") % [n, m.name], "boot")
		Sound.play("entdeckt")
	elif n > 0:
		Game.notify(tr("%d Siedler sind auf %s angekommen.") % [n, m.name], "boot")
	elif not sh.is_empty() and sh.route.is_empty():
		Game.notify_at(w, tr("Die %s hat in %s angelegt.") % [ship_label(sh), m.name], "anker")
	if Game.world == null or not is_instance_valid(Game.world) or Game.world.settlers.is_empty():
		switch_to(dest)
	if n > 0:
		Game.on_population_changed()
	islands_changed.emit()


## Schiff legt an: Besatzung geht an Land.
func _dock(sh: Dictionary, w, crew_data: Array) -> void:
	sh.at = w.island_id
	sh.state = "dock"
	_land(w, crew_data, w.harbor_cell())
	sh.crew = crew_data.map(func(d): return int(d.get("id", -1)))
	w.assign_homes()
	w.sync_ships()
	if not crew_data.is_empty():
		Game.on_population_changed()


## Insel verloren: Schiffe, die dort liegen, gehen mit verloren.
func _ships_lost(island_id: int) -> void:
	for sh in ships.duplicate():
		if sh.state != "sea" and int(sh.at) == island_id:
			ships.erase(sh)
	for sh in ships:
		if int(sh.home) == island_id:
			var alt := settled_islands().filter(func(m): return int(m.id) != island_id)
			if not alt.is_empty():
				sh.home = int(alt[0].id)


# ---------------------------------------------------------------- Speichern
func serialize() -> Dictionary:
	var list := []
	for m in islands:
		var e: Dictionary = m.duplicate(true)
		var w = worlds.get(int(m.id))
		if w and is_instance_valid(w):
			e["world"] = w.serialize()
		list.append(e)
	return {"islands": list, "active": Game.world.island_id if Game.world else 0, "voyages": voyages,
		"ships": ships, "next_ship": next_ship}


## Baut alle Inseln aus einem Spielstand. Alte Spielstaende (Version 1) haben nur `world`.
func build_from_save(d: Dictionary) -> void:
	clear_worlds()
	islands = []
	voyages = []
	var list: Array = d.get("islands", [])
	if list.is_empty():
		list = [{"id": 0, "name": tr("Heimatinsel"), "biome": "heimat", "seed": int(d.seed),
			"size": int(Data.bal("map_size", 64)), "pos": [0.0, 0.0], "state": "settled", "found_day": 1,
			"dens": [], "world": d.world}]
	for e in list:
		var m: Dictionary = e.duplicate()
		m.erase("world")
		m.name = Loc.name_of(str(m.get("name", "")))  # Name in der gewaehlten Sprache
		m.id = int(m.id)
		m.seed = int(m.seed)
		m.size = int(m.size)
		islands.append(m)
		if m.state == "settled" and e.has("world"):
			var w := create_world_node(m.id)
			w.build_from_save(e.world, m)
	for v in d.get("voyages", []):
		voyages.append(v)
	ships = []
	for e in d.get("ships", []):
		var sh: Dictionary = e.duplicate(true)
		sh.name = Loc.name_of(str(sh.get("name", "")))
		for k in ["id", "home", "at", "leg"]:
			sh[k] = int(sh.get(k, 0))
		sh.crew = sh.get("crew", []).map(func(x): return int(x))
		var cg := {}
		for id in sh.get("cargo", {}):
			cg[id] = int(sh.cargo[id])
		sh.cargo = cg
		var rt := []
		for st in sh.get("route", []):
			var ld := {}
			for id in st.get("load", {}):
				ld[id] = int(st.load[id])
			rt.append({"island": int(st.island), "load": ld})
		sh.route = rt
		sh["paused"] = bool(sh.get("paused", false))
		sh["note"] = str(sh.get("note", ""))
		if Data.ships.has(sh.get("type", "")):
			ships.append(sh)
	next_ship = int(d.get("next_ship", ships.size() + 1))
	# Bis Version 2 gab es ein gemeinsames Lager: das bekommt die Heimatinsel
	if not Game.stock.is_empty() and not worlds.is_empty():
		var heir = worlds.get(0, worlds.values()[0])
		if not heir.had_stock:
			for id in Game.stock:
				heir.stock[id] = int(heir.stock.get(id, 0)) + int(Game.stock[id])
			heir.store_limits = Game.store_limits.duplicate()
	Game.stock = {}
	Game.store_limits = {}
	var active := int(d.get("active", 0))
	if not worlds.has(active) and not worlds.is_empty():
		active = int(worlds.keys()[0])
	Game.world = worlds.get(active)
	if Game.world:
		Game.world.visible = true
	for w in all_worlds():
		w.sync_ships()
	Game.refresh_effects()
	islands_changed.emit()
