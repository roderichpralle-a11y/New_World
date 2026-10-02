class_name IslandGen
extends RefCounted
## Erzeugt eine Insel aus einem Seed. Ergebnis ist rein datenbasiert, damit
## spaetere Etappen weitere Inseln (andere Biome, andere Ressourcen) erzeugen koennen.
##
## opts.biome ist ein Eintrag aus data/islands.json (Heimatinsel, Palmen-, Wald-, Felseninsel).
## Ohne opts entsteht die Heimatinsel genau wie in Etappe 1 (alte Spielstaende bleiben gleich).
##
## Rueckgabe: {
##   "size": int,
##   "terrain": PackedByteArray (size*size, 0 Wasser, 1 Sand, 2 Gras),
##   "nodes": [{"type": String, "cell": Vector2i, "variant": int}],
##   "center": Vector2i  (Startpunkt fuer das Lagerfeuer)
## }

const WATER := 0
const SAND := 1
const GRASS := 2


static func generate(seed_value: int, size: int, opts: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.07
	noise.fractal_octaves = 3
	var biome: Dictionary = opts.get("biome", Data.islands.get("heimat", {}))
	var radius: float = opts.get("radius", size * 0.40)
	var center := Vector2(size / 2.0, size / 2.0)
	var stretch := Vector2(rng.randf_range(0.85, 1.15), rng.randf_range(0.85, 1.15))

	var height := PackedFloat32Array()
	height.resize(size * size)
	for y in size:
		for x in size:
			var d := ((Vector2(x, y) - center) / stretch).length() / radius
			var h := 1.0 - d * d + noise.get_noise_2d(x, y) * 0.55
			# Rand der Karte immer Wasser
			var edge: int = min(min(x, y), min(size - 1 - x, size - 1 - y))
			if edge < 3:
				h = -1.0
			height[y * size + x] = h

	var terrain := PackedByteArray()
	terrain.resize(size * size)
	for i in size * size:
		terrain[i] = SAND if height[i] > 0.12 else WATER

	# Startlichtung garantiert Land
	var c := Vector2i(int(center.x), int(center.y))
	for y in range(c.y - 6, c.y + 7):
		for x in range(c.x - 6, c.x + 7):
			if Vector2(x - c.x, y - c.y).length() <= 6.5:
				terrain[y * size + x] = SAND
				height[y * size + x] = max(height[y * size + x], 0.6)

	# Nur die zusammenhaengende Hauptinsel behalten
	_keep_main_island(terrain, size, c)
	# Kleine Wasserloecher im Land fuellen
	_fill_lakes(terrain, size)

	# Gras: hoeher gelegen und rundum Land (damit immer ein Sandrand bleibt)
	for y in range(1, size - 1):
		for x in range(1, size - 1):
			var i := y * size + x
			if terrain[i] != SAND or height[i] < float(biome.get("grass_level", 0.32)):
				continue
			var all_land := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if terrain[(y + dy) * size + x + dx] == WATER:
						all_land = false
			if all_land:
				terrain[i] = GRASS
	for y in range(c.y - 4, c.y + 5):
		for x in range(c.x - 4, c.x + 5):
			terrain[y * size + x] = GRASS

	var nodes := _place_nodes(terrain, size, c, rng, seed_value, biome)
	return {"size": size, "terrain": terrain, "nodes": nodes, "center": c}


static func _keep_main_island(terrain: PackedByteArray, size: int, start: Vector2i) -> void:
	var seen := PackedByteArray()
	seen.resize(size * size)
	var stack: Array[Vector2i] = [start]
	seen[start.y * size + start.x] = 1
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.x < 0 or q.y < 0 or q.x >= size or q.y >= size:
				continue
			var qi := q.y * size + q.x
			if seen[qi] == 0 and terrain[qi] != WATER:
				seen[qi] = 1
				stack.append(q)
	for i in size * size:
		if seen[i] == 0:
			terrain[i] = WATER


static func _fill_lakes(terrain: PackedByteArray, size: int) -> void:
	# Wasser, das nicht mit dem Kartenrand verbunden ist, wird zu Sand
	var seen := PackedByteArray()
	seen.resize(size * size)
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	seen[0] = 1
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.x < 0 or q.y < 0 or q.x >= size or q.y >= size:
				continue
			var qi := q.y * size + q.x
			if seen[qi] == 0 and terrain[qi] == WATER:
				seen[qi] = 1
				stack.append(q)
	for i in size * size:
		if terrain[i] == WATER and seen[i] == 0:
			terrain[i] = SAND


static func _place_nodes(terrain: PackedByteArray, size: int, c: Vector2i, rng: RandomNumberGenerator, seed_value: int, biome: Dictionary) -> Array:
	var forest := FastNoiseLite.new()
	forest.seed = seed_value + 17
	forest.frequency = 0.09
	var used := {}
	var nodes := []
	var tree_variant := int(biome.get("tree_variant", -1))
	var add := func(type: String, cell: Vector2i):
		if used.has(cell):
			return
		used[cell] = true
		var v := -1
		# Waldinseln haben viele Nadelbaeume, Palmeninseln helle Laubbaeume
		if type == "baum" and tree_variant >= 0 and (hash(cell) & 0xff) < 150:
			v = tree_variant
		nodes.append({"type": type, "cell": cell, "variant": v})

	var is_t := func(x: int, y: int, t: int) -> bool:
		if x < 0 or y < 0 or x >= size or y >= size:
			return false
		return terrain[y * size + x] == t

	var dense: String = biome.get("dense", "baum")
	var dense_thr: float = biome.get("dense_threshold", 0.22)
	var dense_p: float = biome.get("dense_chance", 0.5)
	var grass_list: Array = biome.get("grass", [])
	var sand_list: Array = biome.get("sand", [])
	var fish_p: float = biome.get("fish", 0.07)
	for y in size:
		for x in size:
			var cell := Vector2i(x, y)
			var dist := Vector2(cell - c).length()
			var t := terrain[y * size + x]
			if dist < 8.0:
				continue
			if t == GRASS:
				var f := forest.get_noise_2d(x, y)
				if f > dense_thr and rng.randf() < dense_p:
					add.call(dense, cell)
				else:
					for e in grass_list:
						if rng.randf() < float(e[1]):
							add.call(e[0], cell)
							break
			elif t == SAND:
				for e in sand_list:
					if rng.randf() < float(e[1]):
						add.call(e[0], cell)
						break
			else:
				# Fischgrund: Wasser direkt am Ufer
				var shore := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if is_t.call(x + d.x, y + d.y, SAND) or is_t.call(x + d.x, y + d.y, GRASS):
						shore = true
				if shore and rng.randf() < fish_p:
					var near := false
					for n in nodes:
						if n.type == "fischgrund" and Vector2(n.cell - cell).length() < 5:
							near = true
							break
					if not near:
						add.call("fischgrund", cell)

	# Garantierte Startressourcen nah am Lagerfeuer
	var ring := func(type: String, count: int, rmin: float, rmax: float, need_grass: bool):
		var placed := 0
		var tries := 0
		while placed < count and tries < 400:
			tries += 1
			var a := rng.randf() * TAU
			var r := rng.randf_range(rmin, rmax)
			var cell := c + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
			if cell.x < 1 or cell.y < 1 or cell.x >= size - 1 or cell.y >= size - 1:
				continue
			var tt := terrain[cell.y * size + cell.x]
			if tt == WATER or (need_grass and tt != GRASS) or used.has(cell):
				continue
			add.call(type, cell)
			placed += 1
	for e in biome.get("ring", []):
		ring.call(e[0], int(e[1]), float(e[2]), float(e[3]), bool(e[4]))

	# Tierbauten weit weg vom Landeplatz (opts.dens: [[typ, anzahl]])
	for e in biome.get("_dens", []):
		var placed := 0
		var tries := 0
		while placed < int(e[1]) and tries < 600:
			tries += 1
			var cell := Vector2i(rng.randi_range(2, size - 3), rng.randi_range(2, size - 3))
			var tt := terrain[cell.y * size + cell.x]
			if tt == WATER or used.has(cell) or Vector2(cell - c).length() < 13.0:
				continue
			if Data.nodes[e[0]].get("terrain", "land") == "grass" and tt != GRASS and tries < 400:
				continue
			# Rund um den Bau muss Platz sein
			var free := true
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = cell + d
				if used.has(q) or terrain[q.y * size + q.x] == WATER:
					free = false
			if not free:
				continue
			add.call(e[0], cell)
			placed += 1
	return nodes
