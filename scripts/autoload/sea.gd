extends Node
## Seefahrt (Etappe 3): alle Inseln, die Seekarte und Schiffsreisen.
## Jede besiedelte Insel ist eine eigene World. Nur die aktive Insel (Game.world) ist
## sichtbar, die anderen leben unsichtbar weiter. Jede Insel hat ihr eigenes Lager;
## Waren kommen nur per Schiff auf eine andere Insel.

signal islands_changed
signal island_switched(world)

## Meta-Daten je Insel: {id, name, biome, seed, size, pos: [x, y], state, found_day, dens: [[typ, anzahl]]}
## state: "discovered" (entdeckt), "settled" (besiedelt), "lost" (verloren)
var islands: Array = []
var worlds: Dictionary = {}  # Insel-ID -> World (nur besiedelte Inseln)
## Reisen: {kind: "explore"|"settle", from, to, depart, arrive, settlers: [Siedler-Daten]}
var voyages: Array = []
var world_root: Node = null  # Knoten, unter dem die Inseln haengen (main)


# ---------------------------------------------------------------- Inseln
func reset(home_seed: int) -> void:
	clear_worlds()
	islands = [{"id": 0, "name": "Heimatinsel", "biome": "heimat", "seed": home_seed, "size": int(Data.bal("map_size", 64)),
		"pos": [0.0, 0.0], "state": "settled", "found_day": 1, "dens": []}]
	voyages = []
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
	return biome_def(m).get("name", "Insel")


func all_worlds() -> Array:
	return worlds.values().filter(func(w): return is_instance_valid(w))


func settled_islands() -> Array:
	return islands.filter(func(m): return m.state == "settled")


func island_name(w) -> String:
	return meta(w.island_id).get("name", "Insel") if w else ""


## Alle lebenden Siedler, auch die auf See.
func total_people() -> int:
	var n := 0
	for w in all_worlds():
		n += w.settlers.size()
	for v in voyages:
		n += v.settlers.size()
	return n


func people_at_sea() -> int:
	var n := 0
	for v in voyages:
		n += v.settlers.size()
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
	var pool: Array = b.get("names", ["Insel"])
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
	Game.notify("%s ist verloren! Dort lebt niemand mehr." % m.name, "abriss")
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


# ---------------------------------------------------------------- Reisen
func ship_capacity() -> int:
	return int(Data.bal("ship_base_capacity", 4)) + int(Game.eff_add("ship_capacity"))


func voyage_days(from_id: int, to_id: int) -> float:
	var d := distance(from_id, to_id)
	return (float(Data.bal("voyage_days_base")) + float(Data.bal("voyage_days_per_dist")) * d) / Game.eff("ship_speed")


func exploring() -> bool:
	return voyages.any(func(v): return v.kind == "explore")


func can_explore(from_world = null) -> String:
	if exploring():
		return "Ein Boot ist schon auf Erkundungsfahrt."
	if Game.amount("boot", from_world) < 1:
		return "Es gibt kein Boot. Baue eines in der Werft."
	return ""


func start_explore(from_world) -> String:
	var err := can_explore(from_world)
	if err != "":
		return err
	Game.take_stock("boot", 1, from_world)
	var next := islands.size()
	var probe := make_island(next)
	var d := Vector2(float(probe.pos[0]), float(probe.pos[1])).length()
	var days := (float(Data.bal("explore_days_base")) + float(Data.bal("explore_days_per_dist")) * d) / Game.eff("explore")
	voyages.append({"kind": "explore", "from": from_world.island_id, "to": next, "depart": Game.time_days,
		"arrive": Game.time_days + days, "settlers": []})
	from_world.sail_away()
	Game.notify("Ein Boot sticht in See und sucht nach neuen Inseln.", "boot")
	Sound.play("glocke")
	islands_changed.emit()
	return ""


func can_send(from_world, to_id: int, people: Array) -> String:
	var m := meta(to_id)
	if m.is_empty() or m.state == "lost":
		return "Diese Insel ist verloren."
	if from_world.island_id == to_id:
		return "Die Siedler sind schon dort."
	if Game.amount("boot", from_world) < 1:
		return "Auf dieser Insel liegt kein Boot. Baue eines in der Werft."
	if people.is_empty():
		return "Wähle Siedler für die Fahrt aus."
	if people.size() > ship_capacity():
		return "Ins Boot passen nur %d Siedler." % ship_capacity()
	if people.size() >= from_world.settlers.size():
		return "Mindestens ein Siedler muss auf der Insel bleiben."
	return ""


func send_settlers(from_world, to_id: int, people: Array) -> String:
	var err := can_send(from_world, to_id, people)
	if err != "":
		return err
	Game.take_stock("boot", 1, from_world)
	var datas := []
	for s in people:
		datas.append(s.serialize())
		from_world.remove_settler(s)
	voyages.append({"kind": "settle", "from": from_world.island_id, "to": to_id, "depart": Game.time_days,
		"arrive": Game.time_days + voyage_days(from_world.island_id, to_id), "settlers": datas})
	from_world.sail_away()
	Game.notify("%d Siedler stechen in See nach %s." % [datas.size(), meta(to_id).name], "boot")
	Sound.play("glocke")
	Game.on_population_changed()
	islands_changed.emit()
	return ""


func _process(_delta: float) -> void:
	if Game.is_over or voyages.is_empty():
		return
	for v in voyages.duplicate():
		if Game.time_days >= float(v.arrive):
			voyages.erase(v)
			_arrive(v)


func _arrive(v: Dictionary) -> void:
	if v.kind == "explore":
		var m := make_island(int(v.to))
		islands.append(m)
		var home = worlds.get(int(v.from))
		if home and is_instance_valid(home):
			Game.add_stock("boot", 1, home)
		var danger := dangers(m).map(func(a): return Data.animals[a].name)
		var text := "Entdeckt: %s, eine %s!" % [m.name, biome_name(m)]
		text += " Gefahr: %s." % ", ".join(danger) if not danger.is_empty() else " Keine wilden Tiere gesichtet."
		Game.notify(text, "kompass")
		Sound.play("entdeckt")
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
	for d in v.settlers:
		d["x"] = c.x
		d["y"] = c.y
		d["home"] = 0
		w.spawn_settler(d)
	w.assign_homes()
	w.add_boat_decor(c)
	if founded:
		Game.notify("Land in Sicht! %d Siedler gründen eine Siedlung auf %s." % [v.settlers.size(), m.name], "boot")
		Sound.play("entdeckt")
	else:
		Game.notify("%d Siedler sind auf %s angekommen." % [v.settlers.size(), m.name], "boot")
	if Game.world == null or not is_instance_valid(Game.world) or Game.world.settlers.is_empty():
		switch_to(dest)
	Game.on_population_changed()
	islands_changed.emit()


# ---------------------------------------------------------------- Speichern
func serialize() -> Dictionary:
	var list := []
	for m in islands:
		var e: Dictionary = m.duplicate(true)
		var w = worlds.get(int(m.id))
		if w and is_instance_valid(w):
			e["world"] = w.serialize()
		list.append(e)
	return {"islands": list, "active": Game.world.island_id if Game.world else 0, "voyages": voyages}


## Baut alle Inseln aus einem Spielstand. Alte Spielstaende (Version 1) haben nur `world`.
func build_from_save(d: Dictionary) -> void:
	clear_worlds()
	islands = []
	voyages = []
	var list: Array = d.get("islands", [])
	if list.is_empty():
		list = [{"id": 0, "name": "Heimatinsel", "biome": "heimat", "seed": int(d.seed),
			"size": int(Data.bal("map_size", 64)), "pos": [0.0, 0.0], "state": "settled", "found_day": 1,
			"dens": [], "world": d.world}]
	for e in list:
		var m: Dictionary = e.duplicate()
		m.erase("world")
		m.id = int(m.id)
		m.seed = int(m.seed)
		m.size = int(m.size)
		islands.append(m)
		if m.state == "settled" and e.has("world"):
			var w := create_world_node(m.id)
			w.build_from_save(e.world, m)
	for v in d.get("voyages", []):
		voyages.append(v)
	# Bis Version 2 gab es ein gemeinsames Lager: das bekommt die Heimatinsel
	if not Game.stock.is_empty() and not worlds.is_empty():
		var heir = worlds.get(0, worlds.values()[0])
		if not heir.had_stock:
			for id in Game.stock:
				heir.stock[id] = int(heir.stock.get(id, 0)) + int(Game.stock[id])
	Game.stock = {}
	var active := int(d.get("active", 0))
	if not worlds.has(active) and not worlds.is_empty():
		active = int(worlds.keys()[0])
	Game.world = worlds.get(active)
	if Game.world:
		Game.world.visible = true
	Game.refresh_effects()
	islands_changed.emit()
