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
var terrain: PackedByteArray
var astar := AStarGrid2D.new()
var nodes: Array = []
var node_at: Dictionary = {}
var buildings: Array = []
var building_at: Dictionary = {}
var settlers: Array = []
var graves: Array = []  # [Sprite2D, bis_tag]
var center: Vector2i

var ground: Node2D  # Felder unter allem
var entities: Node2D  # y-sortiert
var fx: Node2D
var day_tint: CanvasModulate

var _layers: Array = []
var _unreachable: Dictionary = {}
var _storage_warn_time: float = -10.0
var _placing: String = ""
var _ghost_cell: Vector2i
var _ghost: Node2D
var _ghost_sprite: Sprite2D
var _clouds: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


# ================================================================== Aufbau
func build_new(seed_value: int) -> void:
	size = int(Data.bal("map_size", 64))
	var island := IslandGen.generate(seed_value, size)
	_build_terrain(island)
	for n in island.nodes:
		spawn_node(n.type, n.cell)
	# Startsiedlung
	var fire := place_building("lagerfeuer", center, true)
	var hut_cell := center + Vector2i(-5, -4)
	_clear_area(hut_cell, Vector2i(3, 3))
	var hut := place_building("huette", hut_cell, true)
	var lena := spawn_settler({"name": "Lena", "sex": "f", "age": 20.0, "max_age": 46.0,
		"skills": {"nahrung": 4, "bauen": 3, "holz": 1, "stein": 1}, "job": "sammler",
		"look": {"skin": "#f2c9a0", "hair": "#a8642e", "style": 1, "shirt": "#d65f4f", "pants": "#5a4a7a"},
		"x": center.x + 1, "y": center.y + 1})
	var jonas := spawn_settler({"name": "Jonas", "sex": "m", "age": 21.0, "max_age": 44.0,
		"skills": {"holz": 4, "stein": 3, "nahrung": 1, "bauen": 2}, "job": "holzfaeller",
		"look": {"skin": "#e0ac7e", "hair": "#3a2a22", "style": 0, "shirt": "#4f8fd6", "pants": "#4a5a3a"},
		"x": center.x - 1, "y": center.y + 1})
	lena.home_id = hut.id
	jonas.home_id = hut.id
	Game.on_population_changed()


func build_from_save(d: Dictionary) -> void:
	size = int(Data.bal("map_size", 64))
	var island := IslandGen.generate(Game.seed_value, size)
	var w: Dictionary = d.world
	_build_terrain(island)
	for n in w.nodes:
		var node := spawn_node(n[0], Vector2i(int(n[1]), int(n[2])), int(n[5]))
		node.amount = int(n[3])
		node.regrow_at = float(n[4])
		node.refresh()
	for b in w.buildings:
		var bld := place_building(b.type, Vector2i(int(b.x), int(b.y)), bool(b.complete), int(b.id))
		bld.progress = float(b.progress)
		bld.delivered = b.delivered
		bld.farm_state = b.get("farm_state", "fallow")
		bld.farm_time = float(b.get("farm_time", 0.0))
		bld.refresh()
	for s in w.settlers:
		spawn_settler(s)
	for g in w.get("graves", []):
		_add_grave(cell_to_pos(Vector2i(int(g[0]), int(g[1]))), float(g[2]))
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
				var v := Vector2i(15, 2) if h < 70 else Vector2i(4 + h % 4, 3)
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


func can_place(type: String, c: Vector2i) -> bool:
	var def: Dictionary = Data.buildings[type]
	for y in int(def.size[1]):
		for x in int(def.size[0]):
			var cc := c + Vector2i(x, y)
			if not is_inside(cc) or terrain_at(cc) == WATER:
				return false
			if node_at.has(cc) or building_at.has(cc):
				return false
	# Eingang muss frei sein
	if not def.get("ground", false):
		var e := c + Vector2i(int(def.size[0]) / 2, int(def.size[1]))
		if not is_walkable(e) or building_at.has(e):
			return false
	return true


func on_building_completed(b: Building) -> void:
	Game.notify("%s ist fertig!" % b.def.name, "hammer")
	spawn_effect("dust", b.position)
	spawn_effect("dust", b.position + Vector2(-12, -6))
	spawn_effect("dust", b.position + Vector2(12, -6))
	if b.housing() > 0:
		assign_homes()
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
	for res in refund:
		Game.add_stock(res, refund[res])
	assign_homes()
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
		var d := Vector2(b.cell - from).length_squared()
		if d < best_d:
			best_d = d
			best = b
	return best


func construction_sites() -> Array:
	return buildings.filter(func(b): return not b.complete)


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
	for b in buildings:
		if b.housing() > 0:
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
	# Talente: Mischung der Eltern plus ein zufaelliges Talent
	var skills := {}
	for sk in Data.skills:
		var avg: float = (mother.skill_level(sk) + father.skill_level(sk)) / 2.0
		skills[sk] = clamp(roundi(1.0 + (avg - 1.0) * 0.35 + rng.randf_range(-0.5, 1.0)), 1, 4)
	var talent: String = Data.skills.keys()[rng.randi() % Data.skills.size()]
	skills[talent] = min(int(skills[talent]) + 2, 5)
	var look := Settler.random_look(rng)
	look.skin = (mother if rng.randf() < 0.5 else father).look.skin
	look.hair = (mother if rng.randf() < 0.5 else father).look.hair
	var home = building_by_id(mother.home_id)
	var c: Vector2i = mother.cell
	if home and home.complete and is_walkable(home.entrance_cell()):
		c = home.entrance_cell()
	var child := spawn_settler({"name": name, "sex": sex, "age": 0.0, "skills": skills, "job": "frei",
		"look": look, "x": c.x, "y": c.y, "parents": [mother.id, father.id], "hunger": 80.0})
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
	# Ankunft an einem Strandfeld nahe dem Lager
	var fire = nearest_storage(center)
	var origin: Vector2i = fire.cell if fire else center
	var cands := []
	for y in size:
		for x in size:
			var c := Vector2i(x, y)
			if terrain_at(c) == SAND and is_walkable(c):
				cands.append([Vector2(c - origin).length_squared() + rng.randf() * 80.0, c])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var best = null
	for i in min(12, cands.size()):
		if not find_path(cands[i][1], origin).is_empty() or not find_path(cands[i][1], origin + Vector2i(0, 1)).is_empty():
			best = cands[i][1]
			break
	if best == null:
		return null
	var skills := {}
	for sk in Data.skills:
		skills[sk] = rng.randi_range(1, 3)
	var talent: String = Data.skills.keys()[rng.randi() % Data.skills.size()]
	skills[talent] = rng.randi_range(4, 5)
	var s := spawn_settler({"name": unique_name(sex, rng), "sex": sex, "age": rng.randf_range(4.0, 12.0),
		"skills": skills, "job": "frei", "x": best.x, "y": best.y, "hunger": 40.0})
	assign_homes()
	spawn_effect("chips_fischgrund", s.position)
	Game.on_population_changed()
	return s


func kill_settler(s: Settler, reason: String) -> void:
	if not settlers.has(s):
		return
	s.abort_plan()
	settlers.erase(s)
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
func spawn_effect(kind: String, p: Vector2) -> void:
	var colors := {
		"chips_baum": [Color("#c49a5c"), Color("#7a4e32")],
		"chips_fels": [Color("#b8bac6"), Color("#6a6c80")],
		"chips_busch": [Color("#e8586e"), Color("#5aa852")],
		"chips_fischgrund": [Color("#c8ecfa"), Color("#6eb8e8")],
		"leaves": [Color("#62ac52"), Color("#8acb62")],
		"dust": [Color("#e8d8b0"), Color("#c8b890")],
		"hearts": [Color("#f06080"), Color("#ffb0c0")],
	}
	if not colors.has(kind):
		return
	var cols: Array = colors[kind]
	var n := 10 if kind in ["leaves", "dust", "hearts"] else 4
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
		Game.notify("Das Lager ist voll (%s). Baue ein Lagerhaus!" % Data.resource_name(res), "haus")


# ================================================================== Tag und Nacht
func night_factor() -> float:
	var t := Game.time_of_day()
	# 0 am Tag, 1 in der Nacht, weiche Uebergaenge in Daemmerung
	var ns := float(Data.bal("night_start"))
	var ne := float(Data.bal("night_end"))
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
	var night := Color(0.38, 0.42, 0.68)
	var c := day_col
	if nf > 0.0:
		var is_evening := t > 0.5
		c = day_col.lerp(dusk if is_evening else Color(0.9, 0.85, 1.0), clamp(nf * 2.0, 0.0, 1.0)).lerp(night, clamp(nf * 2.0 - 1.0, 0.0, 1.0))
	day_tint.color = c
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


# ================================================================== Bauen (Platzieren)
func start_placement(type: String, at_pos: Vector2) -> void:
	_placing = type
	var def: Dictionary = Data.buildings[type]
	var sz := Vector2i(int(def.size[0]), int(def.size[1]))
	_ghost_cell = pos_to_cell(at_pos) - sz / 2
	var tex: AtlasTexture
	if def.get("ground", false):
		tex = Data.object_tex("field0")
		_ghost_sprite.visible = false
	else:
		tex = Data.object_tex(def.sprite)
		_ghost_sprite.visible = true
		_ghost_sprite.texture = tex
	_ghost.visible = true
	_update_ghost()


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
	_ghost.queue_redraw()
	placement_changed.emit(true, _placing, can_place(_placing, _ghost_cell))


func _draw_ghost() -> void:
	if _placing == "":
		return
	var def: Dictionary = Data.buildings[_placing]
	var sz := Vector2i(int(def.size[0]), int(def.size[1]))
	var ok := can_place(_placing, _ghost_cell)
	var col := Color(0.4, 1.0, 0.5, 0.35) if ok else Color(1.0, 0.3, 0.3, 0.4)
	var origin := Vector2(-sz.x * 8, -sz.y * 16)
	for y in sz.y:
		for x in sz.x:
			_ghost.draw_rect(Rect2(origin + Vector2(x * T, y * T) + Vector2(1, 1), Vector2(T - 2, T - 2)), col)
	_ghost.draw_rect(Rect2(origin, Vector2(sz) * T), Color(1, 1, 1, 0.8), false, 1.0)
	if not def.get("ground", false):
		_ghost.draw_rect(Rect2(Vector2(-4, 4), Vector2(8, 8)), Color(1, 1, 0.6, 0.6), false, 1.0)


func confirm_placement() -> bool:
	if _placing == "" or not can_place(_placing, _ghost_cell):
		return false
	var b := place_building(_placing, _ghost_cell, false)
	spawn_effect("dust", b.position)
	if not Game.can_afford(b.def.cost):
		Game.notify("Baustelle angelegt. Es fehlt noch Material.", "hammer")
	var has_builder := settlers.any(func(s): return s.is_adult() and (s.job == "baumeister" or s.job == "frei"))
	if not has_builder:
		Game.notify("Tipp: Mache einen Siedler zum Baumeister, damit gebaut wird.", "hammer")
	cancel_placement()
	return true


func cancel_placement() -> void:
	_placing = ""
	_ghost.visible = false
	placement_changed.emit(false, "", false)


func is_placing() -> bool:
	return _placing != ""


# ================================================================== Auswahl
func pick_at(p: Vector2):
	var best = null
	var best_d := 12.0
	for s in settlers:
		if not s.visible:
			continue
		var d: float = (s.position + Vector2(0, -9) - p).length()
		if d < best_d:
			best_d = d
			best = s
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
		"nodes": nodes.map(func(n): return n.serialize()),
		"buildings": buildings.map(func(b): return b.serialize()),
		"settlers": settlers.map(func(s): return s.serialize()),
		"graves": graves.map(func(g): return [pos_to_cell(g[0].position).x, pos_to_cell(g[0].position).y, g[1]]),
	}
