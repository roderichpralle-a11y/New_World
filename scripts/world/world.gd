class_name World
extends Node2D
## Die Insel: Gelaende (Dual-Grid-Tilemaps), Wegfindung und alle Entitaeten.

signal placement_changed(active: bool, type: String, valid: bool)

const T := 16
const WATER := 0
const SAND := 1
const GRASS := 2
const OCEAN_MARGIN := 26

var size: int = 64
var island_id: int = 0
var biome: String = "heimat"
var terrain: PackedByteArray
var astar := AStarGrid2D.new()
var nodes: Array = []
var node_at: Dictionary = {}
var buildings: Array = []
var building_at: Dictionary = {}
var settlers: Array = []
var graves: Array = []  # [Sprite2D, bis_tag]
var animals: Array = []  # wilde Tiere (Animal)
var decor: Array = []  # Boote am Strand: [Sprite2D, bis_tag]
var _ship_nodes: Dictionary = {}  # Schiff-ID -> Sprite2D (Schiffe, die hier liegen)
var _ship_anim: float = 0.0
var center: Vector2i
var stock: Dictionary = {}  # Lager dieser Insel (Ware -> Menge), siehe Game.amount
var store_limits: Dictionary = {}  # Hoechstmengen je Ware auf dieser Insel (fehlt = frei)
var had_stock: bool = false  # Spielstand hatte ein eigenes Inselllager (ab Version 3)

var ground: Node2D  # Felder unter allem
var entities: Node2D  # y-sortiert
var fx: Node2D
var day_tint: CanvasModulate
## Jahreszeit-Shader (Schnee, Herbstlaub): Boden, Laubbäume und Büsche, Nadelbäume
var _mat_ground: ShaderMaterial
var _mat_leaf: ShaderMaterial
var _mat_needle: ShaderMaterial

var _layers: Array = []
var _unreachable: Dictionary = {}
var _storage_warn_time: float = -10.0
var _placing: String = ""
var _ghost_cell: Vector2i
var _move_b = null  # Gebaeude, das gerade verschoben wird (sonst null)
var _ghost: Node2D
var _ghost_sprite: Sprite2D
var _clouds: Array = []
var _rng := RandomNumberGenerator.new()
var _den_t: float = 0.0
var _den_breed: Dictionary = {}  # "x,y" -> Tag des letzten Wurfs (-1 = in diesem Fruehling bereit)
var _grazed: Dictionary = {}  # Zelle -> Tag, bis wann Tiere dort nichts mehr finden
var _species_seen: Dictionary = {}  # Tierarten, die es auf der Insel gab
var _school_frame: int = -1
var _school_of: Dictionary = {}  # Kind-ID -> Schule


func _ready() -> void:
	_rng.randomize()


# ================================================================== Aufbau
func build_new(seed_value: int) -> void:
	size = int(Data.bal("map_size", 64))
	stock = {}
	for id in Data.bal("start_stock", {}):
		stock[id] = int(Data.bal("start_stock")[id])
	var island := IslandGen.generate(seed_value, size)
	_build_terrain(island)
	for n in island.nodes:
		spawn_node(n.type, n.cell, int(n.get("variant", -1)))
	# Startsiedlung
	var fire := place_building("lagerfeuer", center, true)
	var hut_cell := center + Vector2i(-5, -4)
	_clear_area(hut_cell, Vector2i(3, 3))
	var hut := place_building("huette", hut_cell, true)
	var lena := spawn_settler({"name": "Lena", "sex": "f", "age": 20.0, "max_age": 46.0,
		"skills": {"nahrung": 4, "bauen": 3, "holz": 1, "stein": 1}, "job": "sammler",
		"traits": {"iq": 7.0, "konst": 7.0, "fleiss": 6.0, "gemuet": 7.5},
		"talents": {"nahrung": 1.4, "bauen": 1.2, "wissen": 1.3, "holz": 0.8, "stein": 0.7, "handwerk": 1.0, "jagd": 0.8},
		"look": {"skin": "#f2c9a0", "hair": "#a8642e", "style": 1, "shirt": "#d65f4f", "pants": "#5a4a7a"},
		"x": center.x + 1, "y": center.y + 1})
	var jonas := spawn_settler({"name": "Jonas", "sex": "m", "age": 21.0, "max_age": 44.0,
		"skills": {"holz": 4, "stein": 3, "nahrung": 1, "bauen": 2}, "job": "holzfaeller",
		"traits": {"iq": 5.0, "konst": 8.0, "fleiss": 8.0, "gemuet": 5.0},
		"talents": {"holz": 1.5, "stein": 1.3, "handwerk": 1.4, "jagd": 1.2, "nahrung": 0.8, "bauen": 1.0, "wissen": 0.7},
		"look": {"skin": "#e0ac7e", "hair": "#3a2a22", "style": 0, "shirt": "#4f8fd6", "pants": "#4a5a3a"},
		"x": center.x - 1, "y": center.y + 1})
	lena.home_id = hut.id
	jonas.home_id = hut.id
	Game.on_population_changed()


## Neue Siedlung auf einer entdeckten Insel: Gelaende, Rohstoffe, Tierbauten und ein Lagerfeuer.
func build_colony(m: Dictionary) -> void:
	island_id = int(m.id)
	biome = m.biome
	size = int(m.size)
	var island := IslandGen.generate(int(m.seed), size, _gen_opts(m))
	_build_terrain(island)
	for n in island.nodes:
		spawn_node(n.type, n.cell, int(n.get("variant", -1)))
	place_building("lagerfeuer", center, true)
	# Jeder Bau startet mit seinen Tieren
	for n in nodes.duplicate():
		var a: String = n.def.get("spawns", "")
		if a != "":
			for i in int(n.def.get("den_cap", 1)):
				_spawn_at_den(n)


func _gen_opts(m: Dictionary) -> Dictionary:
	var b: Dictionary = Data.islands.get(m.get("biome", "heimat"), {}).duplicate()
	b["_dens"] = m.get("dens", [])
	return {"biome": b}


func build_from_save(w: Dictionary, m: Dictionary) -> void:
	island_id = int(m.id)
	biome = m.get("biome", "heimat")
	size = int(m.get("size", Data.bal("map_size", 64)))
	var island := IslandGen.generate(int(m.seed), size, _gen_opts(m) if biome != "heimat" else {})
	_build_terrain(island)
	stock = {}
	had_stock = w.has("stock")
	for id in w.get("stock", {}):
		if Data.resources.has(id):
			stock[id] = int(w.stock[id])
	store_limits = {}
	for id in w.get("store_limits", {}):
		if Data.resources.has(id):
			store_limits[id] = int(w.store_limits[id])
	for n in w.nodes:
		var node := spawn_node(n[0], Vector2i(int(n[1]), int(n[2])), int(n[5]))
		node.amount = int(n[3])
		node.regrow_at = float(n[4])
		node.refresh()
	for b in w.buildings:
		if not Data.buildings.has(b.type):
			continue
		var bld := place_building(b.type, Vector2i(int(b.x), int(b.y)), bool(b.complete), int(b.id))
		bld.progress = float(b.progress)
		bld.delivered = b.delivered
		bld.farm_state = b.get("farm_state", "fallow")
		bld.farm_time = float(b.get("farm_time", 0.0))
		bld.paused = bool(b.get("paused", false))
		if Data.ships.has(b.get("ship", "")):
			bld.ship_choice = b.ship
		bld.refresh()
	for s in w.settlers:
		spawn_settler(s)
	for g in w.get("graves", []):
		_add_grave(cell_to_pos(Vector2i(int(g[0]), int(g[1]))), float(g[2]))
	for a in w.get("animals", []):
		spawn_animal(a[0], Vector2i(int(a[1]), int(a[2])), Vector2i(int(a[4]), int(a[5])), float(a[3]),
			float(a[6]) if a.size() > 6 else -1.0, float(a[7]) if a.size() > 7 else 1.0)
	if w.has("den_breed"):
		_den_breed = w.den_breed
	else:
		# Aelterer Spielstand: frueher kamen Tiere aus dem Nichts nach, jetzt vermehren sie
		# sich. Ausgeraeumte Baue kehren zurueck, und jeder Bau wird einmalig aufgefuellt.
		for n in island.nodes:
			var c: Vector2i = n.cell
			if Data.nodes[n.type].has("spawns") and not node_at.has(c) and not building_at.has(c):
				spawn_node(n.type, c, int(n.get("variant", -1)))
		for n in nodes.duplicate():
			if n.def.has("spawns"):
				var have := animals.filter(func(an): return an.home == n.cell).size()
				for i in max(0, int(n.def.get("den_cap", 1)) - have):
					_spawn_at_den(n)
	Game.on_population_changed()


func _clear_area(top_left: Vector2i, sz: Vector2i) -> void:
	for y in sz.y:
		for x in sz.x:
			var c := top_left + Vector2i(x, y)
			if node_at.has(c):
				remove_node(node_at[c])
			if is_inside(c) and terrain[c.y * size + c.x] == WATER:
				terrain[c.y * size + c.x] = SAND


func _build_terrain(island: Dictionary) -> void:
	terrain = island.terrain
	center = island.center
	# Layer: Wasser, Sand, Gras, Boden(Felder), Entitaeten, Effekte
	var ts := _make_tileset()
	for i in 3:
		var l := TileMapLayer.new()
		l.tile_set = ts
		add_child(l)
		_layers.append(l)
	# Jede Inselart hat ihren eigenen Grünton
	_layers[2].modulate = Color(Data.islands.get(biome, {}).get("tint", "#ffffff"))
	_make_season_materials()
	_layers[2].material = _mat_ground
	ground = Node2D.new()
	add_child(ground)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	fx = Node2D.new()
	fx.z_index = 10
	add_child(fx)
	_paint_terrain()
	_setup_astar()
	day_tint = CanvasModulate.new()
	add_child(day_tint)
	_make_clouds()
	_ghost = Node2D.new()
	_ghost.z_index = 20
	_ghost.visible = false
	_ghost.draw.connect(_draw_ghost)
	add_child(_ghost)
	_ghost_sprite = Sprite2D.new()
	_ghost_sprite.centered = false
	_ghost_sprite.modulate = Color(1, 1, 1, 0.65)
	_ghost.add_child(_ghost_sprite)


func _make_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(T, T)
	var src := TileSetAtlasSource.new()
	src.texture = Data.tex_terrain
	src.texture_region_size = Vector2i(T, T)
	# Wasser animiert (4 Frames ab 0,0)
	src.create_tile(Vector2i(0, 0))
	src.set_tile_animation_columns(Vector2i(0, 0), 4)
	src.set_tile_animation_frames_count(Vector2i(0, 0), 4)
	for f in 4:
		src.set_tile_animation_frame_duration(Vector2i(0, 0), f, 0.45)
	for m in 16:
		src.create_tile(Vector2i(m, 1))
		src.create_tile(Vector2i(m, 2))
	for v in 8:
		src.create_tile(Vector2i(v, 3))
	ts.add_source(src, 0)
	return ts


func _vertex(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= size or y >= size:
		return WATER
	return terrain[y * size + x]


func _paint_terrain() -> void:
	var water: TileMapLayer = _layers[0]
	var sand: TileMapLayer = _layers[1]
	var grass: TileMapLayer = _layers[2]
	for y in range(-OCEAN_MARGIN, size + OCEAN_MARGIN):
		for x in range(-OCEAN_MARGIN, size + OCEAN_MARGIN):
			water.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	for y in range(-1, size):
		for x in range(-1, size):
			var c := [_vertex(x, y), _vertex(x + 1, y), _vertex(x, y + 1), _vertex(x + 1, y + 1)]
			var ms := 0
			var mg := 0
			for i in 4:
				if c[i] >= SAND:
					ms |= 1 << i
				if c[i] >= GRASS:
					mg |= 1 << i
			var h := (hash(Vector2i(x, y)) & 0xffff) % 100
			if ms == 15:
				var v := Vector2i(15, 1) if h < 82 else Vector2i(h % 4, 3)
				sand.set_cell(Vector2i(x, y), 0, v)
			elif ms > 0:
				sand.set_cell(Vector2i(x, y), 0, Vector2i(ms, 1))
			if mg == 15:
				var v := Vector2i(15, 2) if h < 45 else Vector2i(4 + h % 4, 3)
				grass.set_cell(Vector2i(x, y), 0, v)
			elif mg > 0:
				grass.set_cell(Vector2i(x, y), 0, Vector2i(mg, 2))
	# Dual-Grid: Kachel (x,y) liegt zwischen den Eckpunkten (x..x+1, y..y+1)
	for l in _layers:
		l.position = Vector2.ZERO


func _setup_astar() -> void:
	astar.region = Rect2i(0, 0, size, size)
	astar.cell_size = Vector2(T, T)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in size:
		for x in size:
			if terrain[y * size + x] == WATER:
				astar.set_point_solid(Vector2i(x, y), true)


func _make_clouds() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.16))
	g.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	for i in 5:
		var s := Sprite2D.new()
		s.texture = gt
		s.scale = Vector2(_rng.randf_range(4.0, 7.0), _rng.randf_range(2.5, 3.5))
		s.position = Vector2(_rng.randf_range(-200, size * T + 200), _rng.randf_range(0, size * T))
		s.z_index = 9
		add_child(s)
		_clouds.append(s)


# ================================================================== Koordinaten
func cell_to_pos(c: Vector2i) -> Vector2:
	return Vector2(c.x * T, c.y * T)


func pos_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / T), roundi(p.y / T))


func is_inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size


func terrain_at(c: Vector2i) -> int:
	return _vertex(c.x, c.y)


func is_water(c: Vector2i) -> bool:
	return terrain_at(c) == WATER


func is_walkable(c: Vector2i) -> bool:
	return is_inside(c) and not astar.is_point_solid(c)


func world_size_px() -> Vector2:
	return Vector2(size * T, size * T)


# ================================================================== Wegfindung
func find_path(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	if not is_inside(from) or not is_inside(to):
		return PackedVector2Array()
	var from_solid := astar.is_point_solid(from)
	if from_solid:
		astar.set_point_solid(from, false)
	var path := astar.get_point_path(from, to)
	if from_solid:
		astar.set_point_solid(from, true)
	return path


## Bester begehbarer Platz neben (oder auf) den Zielzellen, der erreichbar ist.
func find_approach(from: Vector2i, target_cells: Array, adjacent: bool):
	var cand := []
	var tset := {}
	for t in target_cells:
		tset[t] = true
	if adjacent:
		for t in target_cells:
			for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				var c: Vector2i = t + d
				if not tset.has(c) and is_walkable(c) and not c in cand:
					cand.append(c)
	else:
		for t in target_cells:
			if is_walkable(t):
				cand.append(t)
	if cand.is_empty():
		return null
	cand.sort_custom(func(a, b): return Vector2(a - from).length_squared() < Vector2(b - from).length_squared())
	for i in min(4, cand.size()):
		if cand[i] == from:
			return from
		if not find_path(from, cand[i]).is_empty():
			return cand[i]
	return null


func mark_unreachable(obj) -> void:
	_unreachable[obj] = Game.time_days + 0.5


func _set_solid(c: Vector2i, solid: bool) -> void:
	if not is_inside(c):
		return
	if is_water(c):
		solid = true
	astar.set_point_solid(c, solid)


# ================================================================== Rohstoffe
func spawn_node(type: String, c: Vector2i, variant: int = -1) -> ResNode:
	var n := ResNode.new()
	n.setup(self, type, c, variant)
	entities.add_child(n)
	nodes.append(n)
	node_at[c] = n
	if n.is_solid():
		_set_solid(c, true)
	return n


func remove_node(n: ResNode) -> void:
	nodes.erase(n)
	node_at.erase(n.cell)
	_set_solid(n.cell, building_at.has(n.cell))
	n.queue_free()


func find_node_for(type: String, from: Vector2i, sid: int):
	var best = null
	var best_d := INF
	for n in nodes:
		if n.type != type or not n.is_available():
			continue
		if n.reserved_by != 0 and n.reserved_by != sid:
			continue
		if _unreachable.has(n) and _unreachable[n] > Game.time_days:
			continue
		var d := Vector2(n.cell - from).length_squared()
		if d < best_d:
			best_d = d
			best = n
	return best


# ================================================================== Gebaeude
func place_building(type: String, c: Vector2i, complete: bool, bid: int = 0) -> Building:
	var b := Building.new()
	b.id = bid if bid > 0 else Game.new_id()
	b.setup(self, type, c, complete)
	if b.is_ground():
		ground.add_child(b)
	else:
		entities.add_child(b)
	buildings.append(b)
	for cc in b.cells():
		building_at[cc] = b
		if not b.is_ground():
			_set_solid(cc, true)
	if complete and b.housing() > 0:
		assign_homes()
	return b


## ignore: Gebaeude, dessen eigene Felder als frei gelten (beim Verschieben).
func can_place(type: String, c: Vector2i, ignore = null) -> bool:
	var def: Dictionary = Data.buildings[type]
	for y in int(def.size[1]):
		for x in int(def.size[0]):
			var cc := c + Vector2i(x, y)
			if not is_inside(cc) or terrain_at(cc) == WATER:
				return false
			if node_at.has(cc) or (building_at.has(cc) and building_at[cc] != ignore):
				return false
	# Eingang muss frei sein
	if not def.get("ground", false):
		var e := c + Vector2i(int(def.size[0]) / 2, int(def.size[1]))
		var own: bool = ignore != null and building_at.get(e) == ignore
		if building_at.has(e) and not own:
			return false
		if not own and not is_walkable(e):
			return false
		if own and (not is_inside(e) or is_water(e) or (node_at.has(e) and node_at[e].is_solid())):
			return false
	# Werft und Leuchtturm muessen am Wasser stehen
	if def.get("coast", false):
		var near := false
		for y in range(-2, int(def.size[1]) + 3):
			for x in range(-2, int(def.size[0]) + 2):
				if is_water(c + Vector2i(x, y)):
					near = true
		if not near:
			return false
	return true


func on_building_completed(b: Building) -> void:
	Game.notify_at(self, tr("%s ist fertig!") % b.def.name, "hammer")
	Sound.play_on("fertig", self)
	spawn_effect("dust", b.position)
	spawn_effect("dust", b.position + Vector2(-12, -6))
	spawn_effect("dust", b.position + Vector2(12, -6))
	if b.housing() > 0:
		assign_homes()
	if b.def.has("effects"):
		Game.refresh_effects()
	if b.def.has("harbor"):
		sync_ships()
	Game.stock_changed.emit()
	Game.population_changed.emit()


func demolish(b: Building) -> void:
	if b.type == "lagerfeuer":
		return
	# Rueckerstattung: gelieferte Materialien bei Baustellen voll, sonst die Haelfte
	var refund := {}
	for res in b.def.cost:
		var n := int(b.delivered.get(res, 0))
		refund[res] = n if not b.complete else n / 2
	for s in settlers:
		if s.home_id == b.id:
			s.home_id = 0
			if s.sleeping:
				s._wake_up()
		if s._reserved == b or s._incoming.any(func(i): return i[0] == b):
			s.abort_plan()
	buildings.erase(b)
	for cc in b.cells():
		building_at.erase(cc)
		_set_solid(cc, node_at.has(cc) and node_at[cc].is_solid())
	if Game.selected == b:
		Game.select(null)
	spawn_effect("dust", b.position)
	b.queue_free()
	if b.def.has("harbor"):
		sync_ships.call_deferred()
	for res in refund:
		Game.add_stock(res, refund[res], self)
	assign_homes()
	if b.def.has("effects"):
		Game.refresh_effects()
	Game.population_changed.emit()


func building_by_id(bid: int):
	if bid == 0:
		return null
	for b in buildings:
		if b.id == bid:
			return b
	return null


func nearest_storage(from: Vector2i):
	var best = null
	var best_d := INF
	for b in buildings:
		if not b.is_storage():
			continue
		var d: float = b.dist_sq(from)
		if d < best_d:
			best_d = d
			best = b
	return best


## Lager zum Abliefern: unter allen Lagern, die kaum weiter weg sind als das
## naechste, das mit den wenigsten Ablieferungen im Verhaeltnis zu seinem Platz.
## So bekommt auch das Lagerfeuer weiter Waren, wenn ein Lagerhaus daneben steht.
func delivery_storage(from: Vector2i):
	var near = nearest_storage(from)
	if near == null:
		return null
	var reach := sqrt(near.dist_sq(from)) + float(Data.bal("delivery_spread", 6))
	var best = near
	var best_score := INF
	for b in buildings:
		if not b.is_storage() or b.dist_sq(from) > reach * reach:
			continue
		var score: float = float(b.deliveries) / maxf(1.0, float(b.def.storage))
		if score < best_score:
			best_score = score
			best = b
	best.deliveries += 1
	return best


func construction_sites() -> Array:
	return buildings.filter(func(b): return not b.complete)


## Werkstatt einer Art ("kueche", "handwerk", "stein"), die gerade arbeiten kann.
## Bevorzugt wird die, deren Ware am knappsten ist.
func find_workshop(kind: String, from: Vector2i, sid: int):
	var best = null
	var best_score := INF
	for b in buildings:
		if not b.complete or b.prod_def().get("job", "") != kind:
			continue
		if b.free_slots() <= 0 and not sid in b.occupants:
			continue
		if _unreachable.has(b) and _unreachable[b] > Game.time_days:
			continue
		if b.prod_blocker() != "":
			continue
		var scarce := INF
		for res in b.prod_def().get("outputs", {}):
			scarce = min(scarce, float(Game.amount(res, self)))
		var score := scarce * 4.0 + Vector2(b.cell - from).length()
		if score < best_score:
			best_score = score
			best = b
	return best


## Bester Forschungsplatz mit freiem Platz (Bibliothek vor Schreibstube vor Lagerfeuer).
func find_research_place(from: Vector2i, sid: int):
	var best = null
	var best_score := -INF
	for b in buildings:
		if not b.complete or not b.def.has("research"):
			continue
		if b.free_slots() <= 0 and not sid in b.occupants:
			continue
		if _unreachable.has(b) and _unreachable[b] > Game.time_days:
			continue
		var score := float(b.research_def().get("factor", 1.0)) * 100.0 - Vector2(b.cell - from).length()
		if score > best_score:
			best_score = score
			best = b
	return best


## Ausbau (z. B. Huette -> Holzhaus): das Gebaeude wird zur Baustelle des neuen Typs.
func upgrade_building(b: Building) -> Building:
	var to: String = b.def.get("upgrade", "")
	if to == "" or not Game.is_unlocked(to) or not b.complete:
		return null
	var c := b.cell
	var bid := b.id
	for s in settlers:
		if s._reserved == b or s._incoming.any(func(i): return i[0] == b):
			s.abort_plan()
		if s.home_id == bid and s.sleeping:
			s._wake_up()
	buildings.erase(b)
	for cc in b.cells():
		building_at.erase(cc)
		_set_solid(cc, false)
	var was_selected: bool = Game.selected == b
	b.queue_free()
	var nb := place_building(to, c, false, bid)
	spawn_effect("dust", nb.position)
	assign_homes()
	if was_selected:
		Game.select(nb)
	Game.population_changed.emit()
	return nb


## Verschieben: das Gebaeude zieht samt Lager, Bewohnern und Baufortschritt an einen neuen Platz.
func move_building(b: Building, c: Vector2i) -> bool:
	if c == b.cell:
		return true
	if not can_place(b.type, c, b):
		return false
	var old_cells := b.cells()
	var near := {}  # Felder, zu denen Siedler wegen dieses Gebaeudes unterwegs sein koennten
	for cc in old_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				near[cc + Vector2i(dx, dy)] = true
	for cc in old_cells:
		building_at.erase(cc)
		_set_solid(cc, node_at.has(cc) and node_at[cc].is_solid())
	b.cell = c
	b.position = b.foot_pos()
	for cc in b.cells():
		building_at[cc] = b
		if not b.is_ground():
			_set_solid(cc, true)
	_unreachable.erase(b)
	var door := cell_to_pos(b.entrance_cell())
	for s in settlers:
		var inside: bool = s._hiding == b or (s.sleeping and not s.visible and s.home_id == b.id)
		if inside:
			# Wer drinnen schlaeft oder sich versteckt, zieht mit um
			s.cell = b.entrance_cell()
			s.position = door
			continue
		if s._plan.is_empty():
			continue
		var busy: bool = s._plan[0].a == "work"  # laufende Arbeit (z. B. in der Werkstatt) zu Ende bringen
		var refs: bool = s._reserved == b or s._incoming.any(func(i): return i[0] == b)
		var heading := false
		for a in s._plan:
			if a.a == "move" and near.has(a.cell):
				heading = true
		if (refs or heading) and not busy:
			s.abort_plan()
	# Siedler, die auf dem neuen Platz stehen, treten zur Seite
	if not b.is_ground():
		for s in settlers:
			if b.cells().has(s.cell):
				s.cell = b.entrance_cell()
				s.position = door
	spawn_effect("dust", b.position)
	if b.housing() > 0:
		assign_homes()
	Game.stock_changed.emit()
	return true


func find_field_task(from: Vector2i, sid: int):
	var best = null
	var best_d := INF
	for b in buildings:
		if b.farm_task() == "" or (b.reserved_by != 0 and b.reserved_by != sid):
			continue
		var d := Vector2(b.cell - from).length_squared()
		if d < best_d:
			best_d = d
			best = b
	return best


func assign_homes() -> void:
	var free := {}
	# Bessere Haeuser zuerst belegen: dort kommen mehr Kinder zur Welt
	var homes := buildings.filter(func(b): return b.housing() > 0)
	homes.sort_custom(func(a, b): return float(a.def.get("birth_bonus", 1.0)) > float(b.def.get("birth_bonus", 1.0)))
	for b in homes:
		free[b] = b.housing()
	for s in settlers:
		var h = building_by_id(s.home_id)
		if h and free.has(h) and free[h] > 0:
			free[h] -= 1
		else:
			s.home_id = 0
	for s in settlers:
		if s.home_id != 0:
			continue
		for b in free:
			if free[b] > 0:
				free[b] -= 1
				s.home_id = b.id
				break
	# Umzug in ein besseres Haus, wenn dort Platz ist (Erwachsene zuerst)
	var movers := settlers.filter(func(s): return not s.sleeping and s.home_id != 0)
	movers.sort_custom(func(a, b): return a.is_adult() and not b.is_adult())
	for s in movers:
		var cur = building_by_id(s.home_id)
		var cur_bonus := float(cur.def.get("birth_bonus", 1.0))
		for h in free:
			if free[h] > 0 and float(h.def.get("birth_bonus", 1.0)) > cur_bonus:
				free[h] -= 1
				free[cur] += 1
				s.home_id = h.id
				break


## Schule, die dieses Kind besucht (oder null). Jede fertige Schule nimmt `school.slots`
## Kinder auf, die aeltesten zuerst.
func school_of(child):
	var f := Engine.get_process_frames()
	if f != _school_frame:
		_school_frame = f
		_school_of.clear()
		var kids := settlers.filter(func(s): return not s.is_adult())
		kids.sort_custom(func(a, b): return a.age > b.age)
		var i := 0
		for b in buildings:
			if not b.complete or not b.def.has("school"):
				continue
			for n in int(b.def.school.get("slots", 8)):
				if i >= kids.size():
					break
				_school_of[kids[i].id] = b
				i += 1
	var sc = _school_of.get(child.id)
	return sc if sc != null and is_instance_valid(sc) else null


# ================================================================== Siedler
func spawn_settler(data: Dictionary) -> Settler:
	var s := Settler.new()
	s.setup(self, data)
	if not Game.lineage.has(s.id):
		Game.register_lineage(s.id, s.parents)
	entities.add_child(s)
	settlers.append(s)
	return s


func spawn_child(mother, father) -> Settler:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var sex := "f" if rng.randf() < 0.5 else "m"
	var name := unique_name(sex, rng)
	# Charakter und Begabungen teils von den Eltern; Faehigkeiten wachsen mit Spiel und Schule
	var mind := SettlerMind.inherit(rng, mother.mind, father.mind)
	var skills := {}
	for sk in Data.skills:
		skills[sk] = clampi(roundi(1.0 + (float(mind.talents[sk]) - 1.0) * 1.5 + rng.randf_range(-0.3, 0.6)), 1, 3)
	var look := Settler.random_look(rng)
	look.skin = (mother if rng.randf() < 0.5 else father).look.skin
	look.hair = (mother if rng.randf() < 0.5 else father).look.hair
	var home = building_by_id(mother.home_id)
	var c: Vector2i = mother.cell
	if home and home.complete and is_walkable(home.entrance_cell()):
		c = home.entrance_cell()
	var child := spawn_settler({"name": name, "sex": sex, "age": 0.0, "skills": skills, "job": "frei",
		"look": look, "mind": mind, "x": c.x, "y": c.y, "parents": [mother.id, father.id], "hunger": 80.0})
	assign_homes()
	spawn_effect("hearts", child.position + Vector2(0, -16))
	Game.on_population_changed()
	return child


func unique_name(sex: String, rng: RandomNumberGenerator) -> String:
	var pool: Array = Data.names.get(sex, ["Kim"])
	var used := settlers.map(func(s): return s.display_name)
	var name: String = pool[rng.randi() % pool.size()]
	for i in 12:
		if not name in used:
			return name
		name = pool[rng.randi() % pool.size()]
	return name + " " + ["II", "III", "IV", "V"][rng.randi() % 4]


func spawn_newcomer(sex: String) -> Settler:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var best = beach_near(rng)
	if best == null:
		return null
	var mind := SettlerMind.roll(rng)
	var skills := {}
	for sk in Data.skills:
		skills[sk] = clampi(roundi(1.0 + (float(mind.talents[sk]) - 0.8) * 3.0 + rng.randf_range(0.0, 1.0)), 1, 5)
	var s := spawn_settler({"name": unique_name(sex, rng), "sex": sex, "age": rng.randf_range(4.0, 12.0),
		"skills": skills, "mind": mind, "job": "frei", "x": best.x, "y": best.y, "hunger": 40.0})
	assign_homes()
	spawn_effect("chips_fischgrund", s.position)
	Game.on_population_changed()
	return s


## Strandfeld nahe dem Lager, von dem aus das Lager erreichbar ist.
func beach_near(rng: RandomNumberGenerator = null):
	if rng == null:
		rng = _rng
	var fire = nearest_storage(center)
	var origin: Vector2i = fire.cell if fire else center
	var cands := []
	for y in size:
		for x in size:
			var c := Vector2i(x, y)
			if terrain_at(c) == SAND and is_walkable(c):
				cands.append([Vector2(c - origin).length_squared() + rng.randf() * 80.0, c])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for i in min(12, cands.size()):
		if not find_path(cands[i][1], origin).is_empty() or not find_path(cands[i][1], origin + Vector2i(0, 1)).is_empty():
			return cands[i][1]
	return null


## Landeplatz fuer ankommende Boote.
func landing_cell() -> Vector2i:
	var b = beach_near()
	return b if b != null else center + Vector2i(0, 2)


## Siedler verlaesst die Insel (Schiffsreise).
func remove_settler(s: Settler) -> void:
	if not settlers.has(s):
		return
	s.abort_plan()
	settlers.erase(s)
	if Game.selected == s:
		Game.select(null)
	s.queue_free()
	assign_homes()


func kill_settler(s: Settler, reason: String) -> void:
	if not settlers.has(s):
		return
	s.abort_plan()
	settlers.erase(s)
	# Die Familie trauert, die anderen auf der Insel ein wenig
	for o in settlers:
		o.mind.on_relative_died(s.display_name, SettlerMind.is_close(o.id, s.id))
	_add_grave(s.position, Game.time_days + 3.0)
	s.queue_free()
	assign_homes()
	Game.on_settler_died(s, reason)


func _add_grave(p: Vector2, until: float) -> void:
	var g := Sprite2D.new()
	g.texture = Data.object_tex("grave")
	g.centered = false
	g.offset = Vector2(-8, -12)
	g.position = p
	entities.add_child(g)
	graves.append([g, until])


# ================================================================== Effekte
## Geraeusch beim Abbauen je Rohstoffquelle
const CHIP_SOUNDS := {"baum": "axt", "palme": "axt", "fels": "stein", "erzader": "stein", "goldader": "stein",
	"busch": "pfluecken", "pilzkreis": "pfluecken", "fischgrund": "platsch"}


func spawn_effect(kind: String, p: Vector2) -> void:
	var colors := {
		"chips_baum": [Color("#c49a5c"), Color("#7a4e32")],
		"chips_fels": [Color("#b8bac6"), Color("#6a6c80")],
		"chips_busch": [Color("#e8586e"), Color("#5aa852")],
		"chips_fischgrund": [Color("#c8ecfa"), Color("#6eb8e8")],
		"chips_palme": [Color("#8a5a36"), Color("#52a03e")],
		"chips_pilzkreis": [Color("#e05040"), Color("#f0e8d6")],
		"chips_erzader": [Color("#c06a3a"), Color("#8a8c9e")],
		"chips_goldader": [Color("#f5d250"), Color("#8a8c9e")],
		"chips_beute": [Color("#c84a40"), Color("#88583c")],
		"chips_wolfsbau": [Color("#7e5438"), Color("#4a3428")],
		"chips_eberbau": [Color("#6e5a40"), Color("#4a3428")],
		"chips_baerenhoehle": [Color("#8a8c9e"), Color("#4a3428")],
		"blood": [Color("#c03030"), Color("#ff6a5a")],
		"leaves": [Color("#62ac52"), Color("#8acb62")],
		"dust": [Color("#e8d8b0"), Color("#c8b890")],
		"hearts": [Color("#f06080"), Color("#ffb0c0")],
	}
	if not colors.has(kind):
		return
	if kind.begins_with("chips_"):
		Sound.play_at(CHIP_SOUNDS.get(kind.trim_prefix("chips_"), "treffer"), self, p)
	var cols: Array = colors[kind]
	var n := 10 if kind in ["leaves", "dust", "hearts"] else (6 if kind == "blood" else 4)
	for i in n:
		var r := ColorRect.new()
		var sz := 2.0 if kind != "hearts" else 3.0
		r.size = Vector2(sz, sz)
		r.color = cols[i % cols.size()]
		r.position = p + Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-4, 2))
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx.add_child(r)
		var tw := r.create_tween()
		var dx := _rng.randf_range(-14, 14)
		var up := _rng.randf_range(8, 18) if kind != "leaves" else _rng.randf_range(-6, 10)
		tw.set_parallel(true)
		tw.tween_property(r, "position", r.position + Vector2(dx, -up), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(r, "modulate:a", 0.0, 0.6).set_delay(0.2)
		tw.chain().tween_callback(r.queue_free)


func spawn_smoke(p: Vector2) -> void:
	var r := ColorRect.new()
	var sz := _rng.randf_range(2.0, 4.0)
	r.size = Vector2(sz, sz)
	r.color = Color(0.82, 0.8, 0.78, 0.75) if _rng.randf() < 0.6 else Color(0.62, 0.6, 0.62, 0.7)
	r.position = p + Vector2(_rng.randf_range(-1.5, 1.5), 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(r)
	var tw := r.create_tween()
	tw.set_parallel(true)
	tw.tween_property(r, "position", r.position + Vector2(_rng.randf_range(2, 9), -_rng.randf_range(14, 22)), 1.6)
	tw.tween_property(r, "size", Vector2(sz + 2, sz + 2), 1.6)
	tw.tween_property(r, "modulate:a", 0.0, 1.0).set_delay(0.6)
	tw.chain().tween_callback(r.queue_free)


func float_text(p: Vector2, text: String, icon_res: String) -> void:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	if icon_res != "":
		var ic := TextureRect.new()
		var icon_name: String = Data.resources.get(icon_res, {}).get("icon", icon_res)
		ic.texture = Data.icon(icon_name)
		ic.custom_minimum_size = Vector2(10, 10)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(ic)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", Color(1, 1, 0.9))
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.12))
	l.add_theme_constant_override("outline_size", 3)
	box.add_child(l)
	box.position = p + Vector2(-10, -6)
	fx.add_child(box)
	var tw := box.create_tween()
	tw.tween_property(box, "position", box.position + Vector2(0, -14), 1.2).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(box, "modulate:a", 0.0, 0.5).set_delay(0.7)
	tw.tween_callback(box.queue_free)


func warn_storage_full(res: String) -> void:
	if Game.time_days - _storage_warn_time > 1.0:
		_storage_warn_time = Game.time_days
		Game.notify(tr("Kein Platz mehr für %s. Baue ein Lager oder stelle im Lager mehr Platz dafür ein.") % Data.resource_name(res), "haus")


# ================================================================== Tag und Nacht
func night_factor() -> float:
	var t := Game.time_of_day()
	# 0 am Tag, 1 in der Nacht, weiche Uebergaenge in Daemmerung
	var ns := Seasons.night_start()
	var ne := Seasons.night_end()
	if t >= ns - 0.06 and t < ns:
		return (t - (ns - 0.06)) / 0.06
	if t >= ns or t < ne:
		return 1.0
	if t >= ne and t < ne + 0.06:
		return 1.0 - (t - ne) / 0.06
	return 0.0


func _process(delta: float) -> void:
	if day_tint == null:
		return
	var nf := night_factor()
	var t := Game.time_of_day()
	var day_col := Color(1, 1, 1)
	var dusk := Color(1.0, 0.82, 0.7)
	var night := Color(0.26, 0.3, 0.52)
	var c := day_col
	if nf > 0.0:
		var is_evening := t > 0.5
		c = day_col.lerp(dusk if is_evening else Color(0.9, 0.85, 1.0), clamp(nf * 2.0, 0.0, 1.0)).lerp(night, clamp(nf * 2.0 - 1.0, 0.0, 1.0))
	day_tint.color = c
	_update_season_look()
	if not _ship_nodes.is_empty():
		_animate_ships(delta)
	for cl in _clouds:
		cl.position.x += delta * 6.0
		if cl.position.x > size * T + 300:
			cl.position.x = -300
			cl.position.y = _rng.randf_range(0, size * T)
	for i in range(graves.size() - 1, -1, -1):
		var g = graves[i]
		if Game.time_days > g[1]:
			g[0].queue_free()
			graves.remove_at(i)
	for i in range(decor.size() - 1, -1, -1):
		var d = decor[i]
		d[0].frame = int(Time.get_ticks_msec() / 600) % 2
		if Game.time_days > d[1]:
			d[0].queue_free()
			decor.remove_at(i)
	_process_dens(delta)


# ================================================================== Jahreszeiten (Aussehen)
func _make_season_materials() -> void:
	var sh: Shader = preload("res://assets/shaders/season.gdshader")
	_mat_ground = ShaderMaterial.new()
	_mat_ground.shader = sh
	_mat_leaf = ShaderMaterial.new()
	_mat_leaf.shader = sh
	_mat_needle = ShaderMaterial.new()
	_mat_needle.shader = sh


## Material für eine Rohstoffquelle: Laub färbt sich, auf allen Bäumen liegt Schnee.
func season_material(type: String, sprite: String) -> Material:
	if _mat_leaf == null:
		return null
	if type == "busch" or (type == "baum" and sprite != "tree2"):
		return _mat_leaf
	if type == "baum":
		return _mat_needle
	return null


func _update_season_look() -> void:
	if _mat_ground == null:
		return
	# Auf Palmeninseln fällt kein Schnee
	var snow := Seasons.snow_amount() * float(Seasons.cfg.get("snow_biomes", {}).get(biome, 1.0))
	var autumn := Seasons.autumn_amount()
	_mat_ground.set_shader_parameter("snow", snow * 0.85)
	_mat_leaf.set_shader_parameter("snow", snow * 0.7)
	_mat_leaf.set_shader_parameter("autumn", autumn)
	_mat_needle.set_shader_parameter("snow", snow * 0.5)


# ================================================================== Bauen (Platzieren)
func start_placement(type: String, at_pos: Vector2) -> void:
	_placing = type
	var def: Dictionary = Data.buildings[type]
	var sz := Vector2i(int(def.size[0]), int(def.size[1]))
	_ghost_cell = pos_to_cell(at_pos) - sz / 2
	var tex: AtlasTexture
	if def.get("ground", false):
		_ghost_sprite.visible = false
	else:
		tex = Data.object_tex(def.sprite)
		_ghost_sprite.visible = true
		_ghost_sprite.texture = tex
	_ghost.visible = true
	_update_ghost()


## Verschieben: wie Bauen, nur mit einem fertigen Gebaeude.
func start_move(b: Building) -> void:
	start_placement(b.type, b.position)
	_move_b = b
	_ghost_cell = b.cell
	b.modulate.a = 0.35
	if Game.selected == b:
		Game.select(null)
	_update_ghost()


func moving_building():
	return _move_b


func move_placement(at_pos: Vector2) -> void:
	if _placing == "":
		return
	var def: Dictionary = Data.buildings[_placing]
	var sz := Vector2i(int(def.size[0]), int(def.size[1]))
	_ghost_cell = pos_to_cell(at_pos - (Vector2(sz) - Vector2.ONE) * 8.0)
	_update_ghost()


func _update_ghost() -> void:
	var def: Dictionary = Data.buildings[_placing]
	var sz := Vector2i(int(def.size[0]), int(def.size[1]))
	_ghost.position = Vector2(_ghost_cell.x * T - 8 + sz.x * 8, _ghost_cell.y * T - 8 + sz.y * 16)
	if _ghost_sprite.visible:
		var r: Vector2 = _ghost_sprite.texture.region.size
		_ghost_sprite.offset = Vector2(-r.x / 2.0, -r.y + 4)
	var ok := can_place(_placing, _ghost_cell, _move_b)
	_ghost_sprite.modulate = Color(1, 1, 1, 0.7) if ok else Color(1, 0.45, 0.4, 0.7)
	_ghost.queue_redraw()
	placement_changed.emit(true, _placing, ok)


func _draw_ghost() -> void:
	if _placing == "":
		return
	var def: Dictionary = Data.buildings[_placing]
	var sz := Vector2i(int(def.size[0]), int(def.size[1]))
	var ok := can_place(_placing, _ghost_cell, _move_b)
	var col := Color(0.4, 1.0, 0.5, 0.45) if ok else Color(1.0, 0.25, 0.25, 0.55)
	var origin := Vector2(-sz.x * 8, -sz.y * 16)
	for y in sz.y:
		for x in sz.x:
			_ghost.draw_rect(Rect2(origin + Vector2(x * T, y * T) + Vector2(1, 1), Vector2(T - 2, T - 2)), col)
	_ghost.draw_rect(Rect2(origin, Vector2(sz) * T), Color(1, 1, 1, 0.8), false, 1.0)
	if not def.get("ground", false):
		_ghost.draw_rect(Rect2(Vector2(-4, 4), Vector2(8, 8)), Color(1, 1, 0.6, 0.6), false, 1.0)


func confirm_placement() -> bool:
	if _placing == "" or not can_place(_placing, _ghost_cell, _move_b):
		Sound.play("fehler")
		return false
	if _move_b != null:
		var mb: Building = _move_b
		cancel_placement()
		move_building(mb, _ghost_cell)
		Sound.play("platzieren")
		Game.player_action.emit("move", mb.type)
		Game.select(mb)
		return true
	var b := place_building(_placing, _ghost_cell, false)
	Sound.play("platzieren")
	Game.player_action.emit("place", b.type)
	spawn_effect("dust", b.position)
	if not Game.can_afford(b.def.cost, self):
		Game.notify(tr("Baustelle angelegt. Es fehlt noch Material."), "hammer")
	var has_builder := settlers.any(func(s): return s.is_adult() and (s.job == "baumeister" or s.job == "frei"))
	if not has_builder:
		Game.notify(tr("Tipp: Mache einen Siedler zum Baumeister, damit gebaut wird."), "hammer")
	cancel_placement()
	return true


func cancel_placement() -> void:
	if _move_b != null and is_instance_valid(_move_b):
		_move_b.modulate.a = 1.0
	_move_b = null
	_placing = ""
	_ghost.visible = false
	placement_changed.emit(false, "", false)


func is_placing() -> bool:
	return _placing != ""


# ================================================================== Auswahl
func pick_at(p: Vector2, radius: float = 12.0):
	var best = null
	var best_d := radius
	for s in settlers:
		if not s.visible:
			continue
		var d: float = (s.position + Vector2(0, -9) - p).length()
		if d < best_d:
			best_d = d
			best = s
	if best:
		return best
	for a in animals:
		if not a.visible:
			continue
		var d: float = (a.position + Vector2(0, -7) - p).length()
		if d < best_d:
			best_d = d
			best = a
	if best:
		return best
	var c := pos_to_cell(p)
	if building_at.has(c):
		return building_at[c]
	# Gebaeude-Sprite ragt nach oben ueber die Grundflaeche
	for b in buildings:
		if b.is_ground():
			continue
		var r := Rect2(b.position + Vector2(-b.size.x * 8, -b.size.y * 16 - 16), Vector2(b.size.x * 16, b.size.y * 16 + 16))
		if r.has_point(p):
			return b
	if node_at.has(c):
		return node_at[c]
	return null


# ================================================================== Speichern
func serialize() -> Dictionary:
	return {
		"stock": stock,
		"store_limits": store_limits,
		"nodes": nodes.map(func(n): return n.serialize()),
		"buildings": buildings.map(func(b): return b.serialize()),
		"settlers": settlers.map(func(s): return s.serialize()),
		"graves": graves.map(func(g): return [pos_to_cell(g[0].position).x, pos_to_cell(g[0].position).y, g[1]]),
		"animals": animals.map(func(a): return a.serialize()),
		"den_breed": _den_breed,
	}


# ================================================================== Seefahrt
## Ein Boot liegt ein paar Tage am Landeplatz.
func add_boat_decor(c: Vector2i) -> void:
	var w = _water_near(c, 4)
	if w == null:
		return
	var sp := Sprite2D.new()
	sp.texture = Data.tex_objects2
	sp.region_enabled = true
	sp.region_rect = Rect2(0, 64, 64, 32)
	sp.hframes = 2
	sp.position = cell_to_pos(w) + Vector2(0, -6)
	entities.add_child(sp)
	decor.append([sp, Game.time_days + 2.0])


func _water_near(c: Vector2i, radius: int):
	var best = null
	var best_d := INF
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var q := c + Vector2i(x, y)
			if is_water(q) and is_water(q + Vector2i(1, 0)) and is_water(q + Vector2i(-1, 0)):
				var d := Vector2(x, y).length()
				if d < best_d:
					best_d = d
					best = q
	return best


## Bild eines Schiffs (Sprite aus objects2.png, schaukelt in zwei Bildern).
func _ship_node(sprite: String) -> Sprite2D:
	var r: Array = Data.OBJECT2_REGIONS.get(sprite, Data.OBJECT2_REGIONS.boat)
	var sp := Sprite2D.new()
	sp.texture = Data.tex_objects2
	sp.region_enabled = true
	sp.region_rect = Rect2(r[0], r[1], r[2] * r[4], r[3])
	sp.hframes = int(r[4])
	sp.offset = Vector2(0, -r[3] / 2.0 + 10)
	return sp


## Ein Schiff legt am Hafen (oder am Strand) ab und segelt aufs Meer hinaus.
func sail_away(sprite: String = "boat") -> void:
	var start = _water_near(harbor_cell(), 6)
	if start == null:
		start = _water_near(landing_cell(), 5)
	if start == null:
		return
	var sp := _ship_node(sprite)
	sp.position = cell_to_pos(start)
	fx.add_child(sp)
	var dir := (sp.position - cell_to_pos(center)).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	var tw := sp.create_tween()
	tw.tween_property(sp, "position", sp.position + dir * size * T * 0.7, 9.0)
	tw.parallel().tween_property(sp, "modulate:a", 0.0, 3.0).set_delay(6.0)
	tw.tween_callback(sp.queue_free)


## Eingang des groessten Hafens (oder der Werft), sonst der Landeplatz am Strand.
func harbor_cell() -> Vector2i:
	var best = null
	var lv := -1
	for b in buildings:
		if b.complete and b.def.has("harbor") and int(b.def.harbor.get("level", 1)) > lv:
			lv = int(b.def.harbor.get("level", 1))
			best = b
	return best.entrance_cell() if best else landing_cell()


## Zeigt die Schiffe, die gerade bei dieser Insel liegen, im Wasser vor den Haefen.
func sync_ships() -> void:
	var here: Array = Sea.ships_at(island_id)
	# Immer neu verteilen: Haefen koennen dazugekommen oder verschoben worden sein
	for id in _ship_nodes.keys():
		_ship_nodes[id].queue_free()
	_ship_nodes.clear()
	var taken := []
	here.sort_custom(func(a, b): return int(Sea.ship_def(a).get("size", 1)) > int(Sea.ship_def(b).get("size", 1)))
	for sh in here:
		var id := int(sh.id)
		var spot = _ship_spot(taken)
		if spot == null:
			continue
		taken.append(spot)
		var sp := _ship_node(String(Sea.ship_def(sh).get("sprite", "boat")))
		sp.position = cell_to_pos(spot)
		entities.add_child(sp)
		_ship_nodes[id] = sp


func _ship_spot(taken: Array):
	var hs := buildings.filter(func(b): return b.complete and b.def.has("harbor"))
	hs.sort_custom(func(a, b): return int(a.def.harbor.get("level", 1)) > int(b.def.harbor.get("level", 1)))
	var anchors := hs.map(func(b): return b.entrance_cell())
	anchors.append(landing_cell())
	for a in anchors:
		var best = null
		var best_d := INF
		for y in range(-7, 8):
			for x in range(-7, 8):
				var q: Vector2i = a + Vector2i(x, y)
				if not (is_water(q) and is_water(q + Vector2i(1, 0)) and is_water(q + Vector2i(-1, 0)) and is_water(q + Vector2i(0, -1))):
					continue
				if taken.any(func(t): return Vector2(t - q).length() < 3.0):
					continue
				var d := Vector2(x, y).length()
				if d < best_d:
					best_d = d
					best = q
		if best != null:
			return best
	return null


func _animate_ships(delta: float) -> void:
	_ship_anim += delta
	var f := int(_ship_anim * 1.6) % 2
	for sp in _ship_nodes.values():
		sp.frame = f


# ================================================================== Wilde Tiere
func spawn_animal(type: String, c: Vector2i, home: Vector2i, hp: float = -1.0, age: float = -1.0,
		food: float = 1.0) -> Animal:
	var a := Animal.new()
	a.setup(self, type, c, home, hp, age, food)
	entities.add_child(a)
	animals.append(a)
	_species_seen[type] = true
	return a


func _spawn_at_den(den: ResNode, age: float = -1.0):
	var dirs := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1)]
	dirs.shuffle()
	for d in dirs:
		var c: Vector2i = den.cell + d
		if is_walkable(c):
			return spawn_animal(den.def.spawns, c, den.cell, -1.0, age)
	return null


# ------------------------------------------------------------------ Bestand der Tiere
## Erwachsene Tiere einer Art auf dieser Insel.
func adult_count(type: String) -> int:
	var n := 0
	for a in animals:
		if a.type == type and a.is_adult() and not a.dead:
			n += 1
	return n


## Die letzten Tiere einer Art werden geschont (Jaeger, Wachturm, Notwehr), Jungtiere immer.
func is_protected(a) -> bool:
	return not a.is_adult() or adult_count(a.type) <= int(Data.bal("hunt_min_keep", 2))


## Darf ein Jaeger dieses Tier jagen? Nur Erwachsene, und nur solange genug uebrig bleiben.
func is_huntable(a) -> bool:
	return a.is_adult() and not a.is_scared() and not is_protected(a)


func animal_can_eat(n, type: String) -> bool:
	var def: Dictionary = Data.animals[type]
	if not def.food.has(n.type) and not (n.type in def.get("winter_food", []) and Seasons.is_winter()):
		return false
	return n.amount > 0 and float(_grazed.get(n.cell, -1.0)) <= Game.time_days


## Naechste Futterquelle fuer ein Tier, im Umkreis seines Baus (hungrig weiter).
func find_animal_food(a):
	var r := float(a.def.get("roam", Data.bal("animal_food_radius", 10))) + (6.0 if a.is_hungry() else 0.0)
	var best = null
	var best_d := INF
	for n in nodes:
		if not animal_can_eat(n, a.type) or Vector2(n.cell - a.home).length() > r:
			continue
		if near_fire(n.position):
			continue
		var d := Vector2(n.cell - a.cell).length_squared()
		if d < best_d:
			best_d = d
			best = n
	return best


func animal_eats(a, n) -> void:
	_grazed[n.cell] = Game.time_days + float(Data.bal("animal_graze_days", 1.0))
	if Data.animals[a.type].food.get(n.type, false) and n.type != "baum":
		n.harvest_one()


## Futterquellen um einen Bau (ohne Aas, das kommt und geht).
func den_food(den) -> int:
	var def: Dictionary = Data.animals[den.def.spawns]
	var r := float(def.get("roam", Data.bal("animal_food_radius", 10)))
	var n := 0
	for o in nodes:
		if o.type != "beute" and def.food.has(o.type) and o.amount > 0 and Vector2(o.cell - den.cell).length() <= r:
			n += 1
	return n


## So viele Tiere kann die Umgebung des Baus ernaehren.
func den_capacity(den) -> int:
	var def: Dictionary = Data.animals[den.def.spawns]
	return min(int(def.get("den_max", 6)), int(den_food(den) / float(def.get("food_per_animal", 3))))


## Jahreszeit: 1 = Fruehling, 0 = andere Jahreszeit, -1 = keine Jahreszeiten (dann alle
## `animal_breed_days` Tage).
func _spring() -> int:
	return 1 if Seasons.season() == Seasons.SPRING else 0


## Tiere bekommen im Fruehling einmal Junge, wenn am Bau ein sattes Paar lebt und das
## Futter fuer mehr Tiere reicht.
func _process_dens(delta: float) -> void:
	_den_t += delta / float(Data.bal("day_length"))
	if _den_t < float(Data.bal("animal_tick_days", 0.1)):
		return
	_den_t = 0.0
	for c in _grazed.keys():
		if float(_grazed[c]) <= Game.time_days:
			_grazed.erase(c)
	var spring := _spring()
	for n in nodes:
		if not n.def.has("spawns"):
			continue
		var key := "%d,%d" % [n.cell.x, n.cell.y]
		if spring == 0:
			_den_breed[key] = -1.0
			continue
		var here := animals.filter(func(a): return a.home == n.cell and not a.dead)
		var adults := here.filter(func(a): return a.is_adult())
		# Ohne Paar zieht ein Tier herueber: von einem Bau mit mehr als zwei Erwachsenen,
		# oder ein einzelnes Tier zu einem anderen einzelnen (zum Bau mit mehr Futter)
		if adults.size() < 2:
			if adults.size() == 1 or here.is_empty():
				_find_mate(n, adults.size())
			continue
		var last := float(_den_breed.get(key, -99.0))
		if spring == 1 and last >= 0.0:
			continue  # in diesem Fruehling schon geworfen
		if spring == -1 and Game.time_days - last < float(Data.bal("animal_breed_days", 4.0)):
			continue
		if adults.filter(func(a): return a.food > 0.4).size() < 2:
			continue
		var cap := den_capacity(n)
		if here.size() >= cap:
			continue
		if _rng.randf() > float(Data.bal("animal_breed_chance", 0.75)):
			continue
		var def: Dictionary = Data.animals[n.def.spawns]
		var lit: Array = def.get("litter", [1, 2])
		var k: int = min(_rng.randi_range(int(lit[0]), int(lit[1])), cap + 1 - here.size(), int(def.get("den_max", 6)) - here.size())
		var born := 0
		for i in k:
			if _spawn_at_den(n, 0.0) != null:
				born += 1
		_den_breed[key] = Game.time_days
		if born > 0:
			Game.notify_at(self, tr("Nachwuchs bei den %s: %d %s.") % [def.get("plural_dat", def.name), born, tr("Jungtier") if born == 1 else tr("Jungtiere")], n.def.spawns)


func _find_mate(den, have: int) -> void:
	var type: String = den.def.spawns
	var cap := den_capacity(den)
	for a in animals:
		if a.type != type or a.home == den.cell or not a.is_adult() or a.is_scared():
			continue
		var at := animals.filter(func(b): return b.home == a.home and b.is_adult()).size()
		var other = node_at.get(a.home)
		var other_cap := den_capacity(other) if other != null and other.def.has("spawns") else -1
		if at > 2 or other_cap < 0 or (have == 1 and at == 1 and (other_cap < cap or (other_cap == cap and a.home < den.cell))):
			a.home = den.cell
			return


var _escape_note: Dictionary = {}  # Tierart -> Tag der letzten Meldung


## Ein Tier entkommt verwundet, weil es zu den letzten seiner Art gehoert.
func on_animal_escaped(a) -> void:
	if Game.time_days - float(_escape_note.get(a.type, -99.0)) < 2.0:
		return
	_escape_note[a.type] = Game.time_days
	if a.is_adult():
		Game.notify_at(self, tr("%s entkommt verwundet. Die letzten %d %s werden geschont.") % [a.def.name, int(Data.bal("hunt_min_keep", 2)), a.def.get("plural", a.def.name)], "schild")


func on_animal_starved(a) -> void:
	animals.erase(a)
	if Game.selected == a:
		Game.select(null)
	if is_visible_in_tree():
		Game.notify_at(self, tr("%s ist verhungert. Für so viele Tiere gibt es nicht genug Futter.") % a.def.name, "schild")
	_check_extinct(a.type)
	a.queue_free()


func _check_extinct(type: String) -> void:
	if animals.any(func(b): return b.type == type and not b.dead):
		return
	Game.notify_at(self, tr("Hier gibt es keine %s mehr.") % Data.animals[type].get("plural", Data.animals[type].name), "schild")


func on_animal_killed(a: Animal, by) -> void:
	animals.erase(a)
	Game.stats["kills"] = int(Game.stats.get("kills", 0)) + 1
	if Game.selected == a:
		Game.select(null)
	var meat := int(round(float(a.def.get("meat", 3)) * Game.eff("hunt")))
	var c := a.cell
	if not is_walkable(c) or node_at.has(c):
		for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
			if is_walkable(c + d) and not node_at.has(c + d):
				c = c + d
				break
	if not node_at.has(c) and not building_at.has(c):
		var n := spawn_node("beute", c)
		n.amount = meat
		n.regrow_at = Game.time_days + float(n.def.get("decay_days", 2.0))
		n.refresh()
	var f := Game.add_stock("felle", int(a.def.get("felle", 1)), self)
	if f > 0:
		float_text(a.position + Vector2(0, -20), "+%d" % f, "felle")
	spawn_effect("blood", a.position + Vector2(0, -6))
	var who := ""
	if by is Settler:
		who = tr(" von %s") % by.display_name
	elif by is Building:
		who = tr(" vom Wachturm")
	Game.notify_at(self, tr("%s wurde%s erlegt.") % [a.def.name, who], "fleisch")
	_check_extinct(a.type)
	a.queue_free()


## filter: "" alle, "hunt" nur jagdbare (Jaeger), "hostile" nur angreifende (Wachturm).
func nearest_animal(from: Vector2, max_px: float, filter: String = ""):
	var best = null
	var best_d := max_px
	for a in animals:
		if filter == "hunt" and not is_huntable(a):
			continue
		if filter == "hostile" and not a.is_hostile():
			continue
		var d: float = (a.position - from).length()
		if d < best_d:
			best_d = d
			best = a
	return best


## Tier, das diesem Siedler gerade gefaehrlich wird (greift ihn an oder ist ganz nah).
func threat_for(s) -> Animal:
	var r := float(Data.bal("flee_radius", 4.0)) * T
	var best = null
	var best_d := INF
	for a in animals:
		if not a.visible:
			continue
		var d: float = (a.position - s.position).length()
		if a.target == s and d < r * 2.0:
			return a
		if d < r and a.is_hostile() and d < best_d:
			best_d = d
			best = a
	return best


## Zuflucht vor Tieren: Haus mit Dach oder Wachturm in der Naehe.
func nearest_refuge(from: Vector2i):
	var best = null
	var best_d := float(Data.bal("refuge_radius", 14))
	for b in buildings:
		if not b.complete or b.is_ground():
			continue
		if b.housing() <= 0 and not b.def.has("defense") and not b.is_storage():
			continue
		if b.type == "lagerfeuer":
			continue
		var d := Vector2(b.entrance_cell() - from).length()
		if d < best_d:
			best_d = d
			best = b
	return best


## Das Lagerfeuer haelt wilde Tiere fern.
func near_fire(p: Vector2) -> bool:
	for b in buildings:
		if b.type == "lagerfeuer" and (b.position - p).length() < 3.5 * T:
			return true
	return false


func fire_building():
	for b in buildings:
		if b.type == "lagerfeuer":
			return b
	return null


func spawn_arrow(from: Vector2, to: Vector2) -> void:
	var sp := Sprite2D.new()
	sp.texture = Data.object_tex("arrow")
	Sound.play_at("pfeil", self, from)
	sp.position = from
	sp.rotation = (to - from).angle()
	fx.add_child(sp)
	var tw := sp.create_tween()
	tw.tween_property(sp, "position", to, clamp((to - from).length() / 260.0, 0.08, 0.4))
	tw.tween_callback(sp.queue_free)
