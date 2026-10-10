class_name StartFish
## Fischgründe der Startinsel (josh 2026-10-09: „Erhöhe die Startinsel auf 5 Fischgründe“).
##
## islands.json `min_fish` (Heimatinsel 5): hat die Insel nach dem normalen Verteilen weniger
## Fischgründe, legt ein eigener Durchgang mit eigenem Zufall (hash [Seed, "fish"]) weitere auf freies
## Wasser direkt am Ufer, möglichst nah am Lagerfeuer und mindestens 4 Felder (zur Not 3) von anderen
## Fischgründen entfernt. Alles andere auf der Karte bleibt dadurch genau gleich. Die zusätzlichen
## tragen "start_fish": true. Ältere Spielstände bekommen die fehlenden beim Laden (patch), bis die
## Insel `min_fish` Fischgründe hat; danach fehlt keiner mehr, also passiert es nur einmal.

const WATER := 0


static func min_fish(biome: Dictionary) -> int:
	return int(biome.get("min_fish", 0))


## Generator: nach _place_nodes und _place_extra (IslandGen.generate).
static func place(terrain: PackedByteArray, size: int, c: Vector2i, seed_value: int, biome: Dictionary, nodes: Array) -> void:
	var want := min_fish(biome)
	if want <= 0:
		return
	var fish := []
	var used := {}
	for n in nodes:
		used[n.cell] = true
		if n.type == "fischgrund":
			fish.append(n.cell)
	if fish.size() >= want:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "fish"])
	var cand := []
	for y in range(1, size - 1):
		for x in range(1, size - 1):
			var cell := Vector2i(x, y)
			if terrain[y * size + x] != WATER or used.has(cell):
				continue
			var shore := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if terrain[(y + d.y) * size + x + d.x] != WATER:
					shore = true
			if shore:
				# nah am Lagerfeuer zuerst (Abstand in Schritten von 5 Feldern), innerhalb gleich weit zufällig
				cand.append([int(Vector2(cell - c).length() / 5.0) * 1000 + rng.randi_range(0, 999), cell])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	for gap in [4.0, 3.0]:
		for e in cand:
			if fish.size() >= want:
				return
			var cell: Vector2i = e[1]
			if used.has(cell):
				continue
			var near := false
			for f in fish:
				if Vector2(f - cell).length() < gap:
					near = true
					break
			if near:
				continue
			used[cell] = true
			fish.append(cell)
			nodes.append({"type": "fischgrund", "cell": cell, "variant": -1, "start_fish": true})


## Älterer Spielstand: fehlende Fischgründe der Startinsel nachlegen (World.build_from_save).
static func patch(w, island: Dictionary) -> int:
	var want := min_fish(Data.islands.get(str(w.biome), {}))
	if want <= 0:
		return 0
	var have: int = w.nodes.filter(func(n): return n.type == "fischgrund").size()
	var added := 0
	for n in island.nodes:
		if have >= want:
			break
		if not n.get("start_fish", false):
			continue
		var cell: Vector2i = n.cell
		if w.node_at.has(cell) or w.building_at.has(cell) or not w.is_water(cell):
			continue
		w.spawn_node("fischgrund", cell)
		have += 1
		added += 1
	if added > 0:
		Game.queue_note(Loc.t("Vor der Küste der Heimatinsel gibt es jetzt %d neue Fischgründe (zusammen %d).") % [added, have], "fisch", "lager")
	return added


## Testhilfe --fishtest=1: Verteilung über viele Seeds, der Rest der Karte bleibt gleich.
static func self_test(w) -> void:
	var bd: Dictionary = Data.islands.get("heimat", {})
	var b0 := bd.duplicate()
	b0["min_fish"] = 0
	var size := int(Data.bal("map_size", 64))
	var before := []
	var after := []
	var same := true
	var near := []
	for k in 100:
		var sd := 1000 + k * 7919
		var g0 := IslandGen.generate(sd, size, {"biome": b0})
		var g1 := IslandGen.generate(sd, size)
		before.append(g0.nodes.filter(func(n): return n.type == "fischgrund").size())
		var f1: Array = g1.nodes.filter(func(n): return n.type == "fischgrund")
		after.append(f1.size())
		# alles außer den neuen Fischgründen gleich und in gleicher Reihenfolge
		var rest: Array = g1.nodes.filter(func(n): return not n.get("start_fish", false))
		if rest.size() != g0.nodes.size():
			same = false
		else:
			for i in rest.size():
				if rest[i].type != g0.nodes[i].type or rest[i].cell != g0.nodes[i].cell:
					same = false
					break
		for n in f1:
			if n.get("start_fish", false):
				near.append(Vector2(n.cell - g1.center).length())
	var avg := func(a: Array) -> float: return float(a.reduce(func(x, y): return x + y, 0)) / maxf(1.0, a.size())
	print("Fisch-Test %s: 100 Seeds, Fischgruende vorher min %d / Schnitt %.1f / max %d, nachher min %d / Schnitt %.1f / max %d" % [
		"OK" if after.min() >= min_fish(bd) else "FEHLER", before.min(), avg.call(before), before.max(), after.min(), avg.call(after), after.max()])
	print("Fisch-Test %s: uebrige Karte unveraendert" % ("OK" if same else "FEHLER"))
	print("Fisch-Test: neue Fischgruende %d, Abstand zum Lagerfeuer Schnitt %.1f, max %.1f" % [near.size(), avg.call(near), near.max() if not near.is_empty() else 0.0])
	var few := []  # Spiel-Seeds (--seed=N), deren Startinsel von Natur aus zu wenige hat
	for sd in range(1, 400):
		var n0: int = IslandGen.generate(sd, size, {"biome": b0}).nodes.filter(func(n): return n.type == "fischgrund").size()
		if n0 < min_fish(bd):
			few.append("%d:%d" % [sd, n0])
	print("Fisch-Test: Seeds 1-399 mit weniger als %d Fischgruenden von Natur aus: %s" % [min_fish(bd), few])
	if w != null:
		print("Fisch-Test: diese Insel hat %d Fischgruende" % w.nodes.filter(func(n): return n.type == "fischgrund").size())
