class_name Building
extends Node2D
## Gebaeude oder Baustelle. Werte kommen aus data/buildings.json.

var id: int
var type: String
var def: Dictionary
var cell: Vector2i  # obere linke Zelle der Grundflaeche
var size: Vector2i
var complete: bool = false
var progress: float = 0.0
var delivered: Dictionary = {}
var incoming: Dictionary = {}  # von Baumeistern unterwegs
var farm_state: String = "fallow"  # fallow, growing, ripe
var farm_time: float = 0.0  # Spielzeit der Aussaat
var reserved_by: int = 0
var occupants: Array = []  # Siedler-IDs, die hier arbeiten (Produktion, Forschung)
var paused: bool = false
var active_until: float = 0.0  # Echtzeit, bis zu der die Werkstatt als "in Betrieb" gilt
var world

var _sprite: Sprite2D
var _tiles: Array = []
var _light: PointLight2D
var _anim_t: float = 0.0
var _bar: Node2D

static var _light_tex: Texture2D


func setup(p_world, p_type: String, p_cell: Vector2i, p_complete: bool) -> void:
	world = p_world
	type = p_type
	def = Data.buildings[type]
	cell = p_cell
	size = Vector2i(int(def.size[0]), int(def.size[1]))
	complete = p_complete
	position = foot_pos()
	if is_ground():
		for y in size.y:
			for x in size.x:
				var s := Sprite2D.new()
				s.centered = false
				s.position = Vector2(x * 16 - size.x * 8, y * 16 - size.y * 16)
				add_child(s)
				_tiles.append(s)
	else:
		var sh := Sprite2D.new()
		sh.texture = Data.object_tex("shadow_big")
		sh.scale = Vector2(size.x * 16 / 32.0 * 1.1, 1.6)
		sh.position = Vector2(0, -2)
		add_child(sh)
		_sprite = Sprite2D.new()
		_sprite.centered = false
		add_child(_sprite)
	if def.get("light", false):
		_light = PointLight2D.new()
		_light.texture = _get_light_tex()
		_light.color = Color(1.0, 0.75, 0.45)
		_light.texture_scale = 1.6 if type == "lagerfeuer" else 1.0
		_light.position = Vector2(0, -6) if type == "lagerfeuer" else Vector2(0, -14)
		_light.energy = 0.0
		add_child(_light)
	_bar = Node2D.new()
	_bar.draw.connect(_draw_bar)
	_bar.position = Vector2(0, -size.y * 16 - 22) if not is_ground() else Vector2(0, -size.y * 16 - 4)
	add_child(_bar)
	refresh()


static func _get_light_tex() -> Texture2D:
	if _light_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 128
		_light_tex = gt
	return _light_tex


func is_ground() -> bool:
	return def.get("ground", false)


func foot_pos() -> Vector2:
	# Unterkante Mitte der Grundflaeche
	return Vector2(cell.x * 16 - 8 + size.x * 8, cell.y * 16 - 8 + size.y * 16)


func cells() -> Array:
	var out := []
	for y in size.y:
		for x in size.x:
			out.append(cell + Vector2i(x, y))
	return out


func entrance_cell() -> Vector2i:
	return cell + Vector2i(size.x / 2, size.y)


func is_storage() -> bool:
	return complete and def.get("storage", 0) > 0


func housing() -> int:
	return int(def.get("housing", 0)) if complete else 0


func residents() -> Array:
	return world.settlers.filter(func(s): return s.home_id == id)


# ---------------------------------------------------------------- Bau
func remaining_cost() -> Dictionary:
	var out := {}
	for res in def.cost:
		var need := int(def.cost[res]) - int(delivered.get(res, 0)) - int(incoming.get(res, 0))
		if need > 0:
			out[res] = need
	return out


func materials_complete() -> bool:
	for res in def.cost:
		if int(delivered.get(res, 0)) < int(def.cost[res]):
			return false
	return true


func deliver(res: String, n: int) -> void:
	delivered[res] = int(delivered.get(res, 0)) + n
	incoming[res] = max(0, int(incoming.get(res, 0)) - n)
	refresh()


func add_work(amount: float) -> void:
	if complete:
		return
	progress += amount
	if progress >= float(def.work):
		complete = true
		progress = float(def.work)
		world.on_building_completed(self)
	refresh()


func build_fraction() -> float:
	var w := float(def.work)
	var mat_total := 0
	var mat_have := 0
	for res in def.cost:
		mat_total += int(def.cost[res])
		mat_have += int(delivered.get(res, 0))
	var m := 1.0 if mat_total == 0 else float(mat_have) / mat_total
	var p := 1.0 if w <= 0 else progress / w
	return m * 0.4 + p * 0.6


# ---------------------------------------------------------------- Feld
func farm_def() -> Dictionary:
	return def.get("farm", {})


func farm_stage() -> int:
	if farm_state == "fallow":
		return 0
	if farm_state == "ripe":
		return 3
	var t := (Game.time_days - farm_time) / grow_days()
	return 1 if t < 0.5 else 2


func grow_days() -> float:
	return float(farm_def().get("grow_days", 1.0)) / Game.eff("farm_speed")


func sow() -> void:
	farm_state = "growing"
	farm_time = Game.time_days
	refresh()


func harvest() -> int:
	farm_state = "fallow"
	refresh()
	return int(round(float(farm_def().amount) * Game.eff("farm_yield")))


func farm_task() -> String:
	if not complete or not def.has("farm"):
		return ""
	if farm_state == "fallow":
		return "sow"
	if farm_state == "ripe":
		return "harvest"
	return ""


# ---------------------------------------------------------------- Werkstatt / Forschung
func prod_def() -> Dictionary:
	return def.get("production", {})


func research_def() -> Dictionary:
	return def.get("research", {})


func slots() -> int:
	if def.has("research"):
		return int(research_def().get("slots", 1))
	if def.has("production"):
		return int(prod_def().get("slots", 1))
	return 0


func free_slots() -> int:
	return slots() - occupants.size()


## Warum die Werkstatt gerade nicht arbeiten kann ("" = alles bereit).
func prod_blocker() -> String:
	var p := prod_def()
	if p.is_empty() or not complete:
		return "nicht fertig"
	if paused:
		return "angehalten"
	for res in p.get("inputs", {}):
		if Game.amount(res, world) < int(p.inputs[res]):
			return "Es fehlt %s" % Data.resource_name(res)
	var any_space := false
	for res in p.get("outputs", {}):
		if Game.space_for(res, world) > 0:
			any_space = true
	if not any_space:
		return "Das Lager ist voll"
	return ""


## Nimmt die Rohstoffe fuer einen Arbeitsgang aus dem Lager.
func take_inputs() -> bool:
	if prod_blocker() != "":
		return false
	var p := prod_def()
	for res in p.get("inputs", {}):
		Game.take_stock(res, int(p.inputs[res]), world)
	return true


func mark_active(seconds: float) -> void:
	active_until = Time.get_ticks_msec() / 1000.0 + seconds


func is_active() -> bool:
	return Time.get_ticks_msec() / 1000.0 < active_until


# ---------------------------------------------------------------- Darstellung
func refresh() -> void:
	if is_ground():
		var stage := farm_stage() if complete else 0
		var tiles: String = farm_def().get("tiles", "field")
		for t in _tiles:
			t.texture = Data.object_tex("%s%d" % [tiles, stage])
			t.modulate = Color(1, 1, 1, 1.0 if complete else 0.55)
	else:
		var name: String = def.sprite if complete else "construction"
		var tex := Data.object_tex(name, 0)
		_sprite.texture = tex
		var sz := tex.region.size
		_sprite.offset = Vector2(-sz.x / 2.0, -sz.y + 4 if sz.y > 16 else -sz.y + 6)
		_sprite.modulate = Color.WHITE
	_bar.queue_redraw()


func _draw_bar() -> void:
	if complete:
		return
	var w := 20.0
	_bar.draw_rect(Rect2(-w / 2 - 1, -1, w + 2, 4), Color(0.16, 0.1, 0.12, 0.85))
	_bar.draw_rect(Rect2(-w / 2, 0, w, 2), Color(0.45, 0.32, 0.25, 0.9))
	_bar.draw_rect(Rect2(-w / 2, 0, w * build_fraction(), 2), Color(0.98, 0.78, 0.3))


var _smoke_t: float = 0.0


func _process(delta: float) -> void:
	if complete and _sprite and is_active():
		var frames := Data.object_frames(def.sprite)
		if frames > 1:
			_anim_t += delta
			_sprite.texture = Data.object_tex(def.sprite, int(_anim_t * 5.0) % frames)
		if prod_def().has("smoke"):
			_smoke_t -= delta
			if _smoke_t <= 0.0:
				_smoke_t = 0.45
				var o: Array = prod_def().smoke
				world.spawn_smoke(position + Vector2(float(o[0]), float(o[1])))
	if type == "lagerfeuer":
		_anim_t += delta
		_sprite.texture = Data.object_tex("campfire", int(_anim_t * 8.0) % 4)
	elif complete and _sprite and not def.has("production") and Data.object_frames(def.sprite) > 1:
		# Leuchtturm: das Feuer kreist nachts
		_anim_t += delta
		var lit: bool = world.night_factor() > 0.3
		_sprite.texture = Data.object_tex(def.sprite, (int(_anim_t * 2.0) % 2) if lit else 0)
	if complete and def.has("defense") and not world.animals.is_empty():
		_defend(delta)
	if _light:
		var target: float = world.night_factor() if complete else 0.0
		var flicker := 1.0 + (sin(_anim_t * 13.0) * 0.06 + sin(_anim_t * 7.3) * 0.05 if type == "lagerfeuer" else 0.0)
		_anim_t += 0.0 if type == "lagerfeuer" else delta
		_light.energy = target * (0.75 if type == "lagerfeuer" else 0.45) * flicker
		_light.visible = _light.energy > 0.02
	if is_ground() and complete and farm_state == "growing":
		if Game.time_days - farm_time >= grow_days():
			farm_state = "ripe"
			refresh()
		elif farm_stage() != _last_stage:
			refresh()
		_last_stage = farm_stage()


var _last_stage := -1
var _shot_t: float = 0.0


## Wachturm: schiesst Pfeile auf das naechste Tier in Reichweite.
func _defend(delta: float) -> void:
	_shot_t -= delta
	if _shot_t > 0.0:
		return
	var d: Dictionary = def.defense
	var tower_bonus := Game.eff_add("tower")
	var rng := float(d.range) * 16.0 * (1.0 + tower_bonus * 0.5)
	var an = world.nearest_animal(position + Vector2(0, -8), rng)
	if an == null:
		_shot_t = 0.3
		return
	_shot_t = float(d.interval)
	var from := position + Vector2(0, -34)
	world.spawn_arrow(from, an.position + Vector2(0, -6))
	an.take_damage(float(d.damage) * Game.eff("tower"), self)


func serialize() -> Dictionary:
	return {
		"id": id, "type": type, "x": cell.x, "y": cell.y, "complete": complete,
		"progress": progress, "delivered": delivered,
		"farm_state": farm_state, "farm_time": farm_time, "paused": paused,
	}
