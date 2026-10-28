class_name Animal
extends Node2D
## Wildes Tier (Wolf, Wildschwein, Baer). Werte aus data/animals.json.
## Streift um seinen Bau, greift Siedler in der Naehe an und wehrt sich, wenn es
## angegriffen wird. Siedler in Haeusern sieht es nicht.
## Tiere werden hungrig und suchen Futter (Beeren, Pilze, Wild im Wald, Aas). Hungrige
## Tiere streifen weiter und greifen eher an, verhungernde verlieren Kraft. Jungtiere
## (`age` < `adult_days`) sind klein, harmlos und werden nicht gejagt. Gehoert ein Tier zu
## den letzten `hunt_min_keep` seiner Art auf der Insel, stirbt es nicht durch Siedler,
## sondern flieht verwundet in seinen Bau (`_scared`).

var type: String
var def: Dictionary
var world
var hp: float = 10.0
var home: Vector2i  # Zelle des Baus
var cell: Vector2i
var target = null  # Settler
var dead: bool = false
var age: float = 99.0  # Tage
var food: float = 1.0  # 1 = satt, 0 = hungert
var homeless_t: float = -1.0  # Tage ohne Bau (-1 = hat einen Bau)
var _homeless_limit: float = 2.0

var _provoked: float = 0.0
var _calm: float = 0.0  # Wildschweine beruhigen sich nach einem Angriff
var _path := PackedVector2Array()
var _path_i: int = 0
var _repath: float = 0.0
var _think: float = 0.0
var _attack_cd: float = 0.0
var _attack_anim: float = 0.0
var _wait: float = 0.0
var _anim: float = 0.0
var _hurt: float = 0.0
var _moving: bool = false
var _flee_t: float = 0.0  # rennt nach einem Schuss davon (Sekunden)
var _scared: float = 0.0  # flieht verwundet in den Bau (Sekunden)
var _eat_node = null
var _shy = null  # Fleisch eines erlegten Tiers im Gehege: so lange bleibt das Tier fern (startle)
var _eat_t: float = 0.0
var _food_cd: float = 0.0
var _rng := RandomNumberGenerator.new()

var _sprite: Sprite2D
var _shadow: Sprite2D


func setup(p_world, p_type: String, p_cell: Vector2i, p_home: Vector2i, p_hp: float = -1.0,
		p_age: float = -1.0, p_food: float = 1.0) -> void:
	z_index = 1  # Figuren immer vor Gebäuden und Bäumen (josh 2026-10-28), y-Sortierung nur unter Figuren
	world = p_world
	type = p_type
	def = Data.animals[type]
	cell = p_cell
	home = p_home
	age = p_age if p_age >= 0.0 else float(def.get("adult_days", 2.0)) * 3.0
	food = clamp(p_food, 0.0, 1.0)
	hp = p_hp if p_hp > 0.0 else max_hp()
	position = world.cell_to_pos(cell)
	_rng.randomize()
	_shadow = Sprite2D.new()
	_shadow.texture = Data.object_tex("shadow")
	_shadow.position = Vector2(0, 1)
	_shadow.scale = Vector2(1.3, 1.0) if type != "baer" else Vector2(1.7, 1.2)
	if not is_adult():
		_shadow.scale *= 0.7
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.offset = Vector2(-12, -21)
	add_child(_sprite)
	_wait = _rng.randf_range(0.0, 2.0)


func max_hp() -> float:
	return float(def.hp) * (1.0 if is_adult() else 0.5)


func is_adult() -> bool:
	return age >= float(def.get("adult_days", 2.0))


func is_hungry() -> bool:
	return food < 0.25


func is_scared() -> bool:
	return _scared > 0.0 or not visible


## Baeren halten im Winter Winterruhe in ihrer Hoehle.
func _hibernates() -> bool:
	return def.get("hibernate", false) and Seasons.is_winter() and homeless_t < 0.0


## Der Bau wurde zerstoert und es gibt keinen anderen: das Tier geht nach einigen Tagen ein.
func lose_home() -> void:
	if homeless_t < 0.0:
		homeless_t = 0.0
	var lim: Array = Data.bal("animal_homeless_days", [1.0, 3.0])
	_homeless_limit = _rng.randf_range(float(lim[0]), float(lim[1]))
	if not visible:
		visible = true  # aus der Winterruhe geweckt


## Ein Jaeger zerstoert den Bau: das Tier greift ihn an.
func defend_den(s) -> void:
	_provoked = 14.0
	_calm = 0.0
	target = s
	_path = PackedVector2Array()


## Greift von sich aus an (Wolf, Baer) oder nur, wenn man ihm zu nahe kommt.
## Jungtiere und fliehende Tiere sind harmlos.
func is_hostile() -> bool:
	if not is_adult() or _scared > 0.0 or not visible:
		return false
	return target != null or _provoked > 0.0 or float(def.aggro) >= 3.0


func _aggro_px() -> float:
	var r := float(def.night_aggro if Game.is_night() else def.aggro)
	if is_hungry():
		r *= 1.5
	if _provoked > 0.0:
		r = max(r, 8.0)
	return r * 16.0


## Satt, hungrig oder am Verhungern, fuer das Infofenster.
func state_text() -> String:
	if homeless_t >= 0.0:
		return tr("Hat keinen Bau mehr und irrt umher.")
	if _hibernates():
		return tr("Hält Winterruhe in der Höhle.") if not visible else tr("Zieht sich für den Winter in die Höhle zurück.")
	if _scared > 0.0:
		return tr("Verwundet, flieht in den Bau.")
	if target and is_instance_valid(target):
		return tr("Greift %s an!") % target.display_name
	if _eat_node != null and is_instance_valid(_eat_node) and _eat_t > 0.0:
		return tr("Frisst.")
	if food <= 0.0:
		return tr("Verhungert langsam!")
	if is_hungry():
		return tr("Hungrig, sucht weit nach Futter.")
	if food < 0.6:
		return tr("Sucht Futter.")
	return tr("Satt, streift umher.")


func _process(delta: float) -> void:
	if dead or Game.is_over:
		return
	_attack_cd -= delta
	_provoked -= delta
	_calm -= delta
	_hurt -= delta
	_attack_anim -= delta
	_scared -= delta
	_think -= delta
	if _shy != null:
		# Erst wenn der Jäger das Fleisch geholt hat, läuft das Tier wieder normal herum
		if is_instance_valid(_shy) and _shy.amount > 0:
			_scared = maxf(_scared, 0.5)
		else:
			_shy = null
	if _hibernates():
		_hibernate(delta)
		_animate(delta)
		return
	if not visible:
		# Aufgewacht: nach dem Winter hungrig
		visible = true
		food = min(food, 0.3)
	if not _needs(delta / float(Data.bal("day_length"))):
		return
	if _think <= 0.0:
		_think = 0.35 + _rng.randf() * 0.2
		_choose_target()
	_moving = false
	if target != null:
		_chase(delta)
	elif food < 0.6 and _scared <= 0.0:
		_forage(delta)
	else:
		_wander(delta)
	_animate(delta)


func _hibernate(delta: float) -> void:
	target = null
	_eat_node = null
	_moving = false
	if not visible:
		age += delta / float(Data.bal("day_length"))
		return
	if Vector2(cell - home).length() <= 1.5:
		visible = false
		hp = max_hp()
		if Game.selected == self:
			Game.select(null)
		return
	if _path_i >= _path.size():
		_path = _path_to(home + Vector2i(0, 1))
		_path_i = 1
		if _path.size() <= 1:
			visible = false
			return
	_step(delta, float(def.speed) * 0.5)


## Altern, Hunger, Heilen. Liefert false, wenn das Tier verhungert ist.
func _needs(days: float) -> bool:
	var was_adult := is_adult()
	age += days
	if homeless_t < 0.0 and world.is_homeless(self):
		lose_home()
	if homeless_t >= 0.0:
		homeless_t += days
		if homeless_t >= _homeless_limit:
			dead = true
			world.on_animal_perished(self)
			return false
	if is_adult() and not was_adult:
		_sprite.scale = Vector2.ONE
		_shadow.scale *= 1.0 / 0.7
	var hunger := float(Data.bal("animal_hunger_per_day", 0.5))
	if Seasons.is_winter():
		hunger *= float(Data.bal("animal_winter_hunger", 0.6))
	food = max(0.0, food - hunger * days)
	if food <= 0.0:
		hp -= float(Data.bal("animal_starve_per_day", 0.45)) * float(def.hp) * days
		# Die letzten zwei einer Art magern ab, verhungern aber nicht
		if hp <= max_hp() * 0.1 and world.is_protected(self) and is_adult():
			hp = max_hp() * 0.1
		elif hp <= 0.0:
			dead = true
			world.on_animal_starved(self)
			return false
	elif food > 0.3 and hp < max_hp():
		hp = min(max_hp(), hp + float(Data.bal("animal_heal_per_day", 0.6)) * max_hp() * days)
	return true


## Futter suchen: naechste Futterquelle in der Naehe des Baus, hingehen, fressen.
func _forage(delta: float) -> void:
	if _eat_node == null or not is_instance_valid(_eat_node) or not world.animal_can_eat(_eat_node, type):
		_eat_node = null
		_eat_t = 0.0
		_food_cd -= delta
		if _food_cd > 0.0:
			_wander(delta)
			return
		_food_cd = 3.0 + _rng.randf()
		var n = world.find_animal_food(self)
		var spot = world.find_approach(cell, [n.cell], true, true) if n != null else null
		if spot == null:
			_wander(delta)
			return
		_eat_node = n
		_path = _path_to(spot)
		_path_i = 1
		_wait = 0.0
		return
	if _path_i < _path.size():
		_step(delta, float(def.speed) * 0.6)
		return
	if Vector2(_eat_node.cell - cell).length() > 1.5:
		_eat_node = null
		return
	_flip_to(_eat_node.position.x - position.x)
	_eat_t += delta
	if _eat_t >= 2.0:
		world.animal_eats(self, _eat_node)
		food = 1.0
		_eat_node = null
		_eat_t = 0.0
		_wait = _rng.randf_range(1.0, 3.0)


func _valid_target(s) -> bool:
	return s != null and is_instance_valid(s) and s.visible and world.settlers.has(s) and not world.near_fire(s.position)


func _choose_target() -> void:
	if not is_adult() or _scared > 0.0:
		target = null
		return
	var leash := float(def.get("leash", 10)) + (6.0 if _provoked > 0.0 else 0.0) + (5.0 if is_hungry() else 0.0)
	if _valid_target(target):
		var d: float = (target.position - position).length()
		if d < _aggro_px() * 1.8 and Vector2(target.cell - home).length() <= leash + 4.0:
			return
	target = null
	if _calm > 0.0 and _provoked <= 0.0:
		return
	var best = null
	var best_d := _aggro_px()
	for s in world.settlers:
		if not s.visible or world.near_fire(s.position):
			continue
		if Vector2(s.cell - home).length() > leash:
			continue
		var d: float = (s.position - position).length()
		if d < best_d:
			best_d = d
			best = s
	target = best
	if target:
		_path = PackedVector2Array()
		Sound.play_at(String(def.get("sound", "knurren")), world, position, 0.08)


func _chase(delta: float) -> void:
	if not _valid_target(target):
		target = null
		return
	var to: Vector2 = target.position - position
	_flip_to(to.x)
	if to.length() <= 13.0:
		if _attack_cd <= 0.0:
			_attack_cd = float(def.attack_time)
			_attack_anim = 0.3
			target.take_damage(float(def.damage), self)
			# Wer nur verteidigt (Wildschwein), laesst nach einem Biss ab
			if float(def.aggro) < 3.0 and _provoked < 13.0:
				_calm = 8.0
				_provoked = 0.0
				target = null
		return
	_repath -= delta
	if _repath <= 0.0 or _path_i >= _path.size():
		_repath = 0.5
		_path = _path_to(target.cell)
		_path_i = 1
		if _path.is_empty():
			# Ziel unerreichbar (z. B. auf der anderen Seite des Wassers)
			target = null
			return
	_step(delta, float(def.speed) * 1.1)


func _wander(delta: float) -> void:
	_flee_t -= delta
	if _flee_t > 0.0 and _path_i < _path.size():
		_step(delta, float(def.speed) * 1.2)
		return
	if _wait > 0.0:
		_wait -= delta
		return
	if _shy != null and _path_i >= _path.size():
		_wait = 1.0  # bleibt am anderen Ende des Geheges, bis das Fleisch fort ist
		return
	if _path_i >= _path.size():
		var r := 4 if Game.is_night() == (type == "wolf") else 3
		if _scared > 0.0:
			r = 1
		elif not is_adult():
			r = 2
		for i in 6:
			var c := home + Vector2i(_rng.randi_range(-r, r), _rng.randi_range(-r, r))
			if world.animal_walkable(c):
				_path = _path_to(c)
				_path_i = 1
				break
		if _path_i >= _path.size():
			_wait = 1.5
			return
	_step(delta, float(def.speed) * 0.45)
	if _path_i >= _path.size():
		_wait = _rng.randf_range(1.5, 4.5)


## Weg für dieses Tier: Zäune versperren ihn (World.find_animal_path). Piraten (Raider) steigen darüber.
func _path_to(c: Vector2i) -> PackedVector2Array:
	return world.find_animal_path(cell, c)


func _step(delta: float, spd: float) -> void:
	if _path_i >= _path.size():
		return
	var t: Vector2 = _path[_path_i]
	var to := t - position
	var step := spd * delta
	_moving = true
	_flip_to(to.x)
	if to.length() <= step:
		position = t
		cell = world.pos_to_cell(t)
		_path_i += 1
	else:
		position += to.normalized() * step


func _flip_to(dx: float) -> void:
	if abs(dx) > 0.5:
		_sprite.flip_h = dx < 0


func take_damage(n: float, by) -> void:
	if dead:
		return
	hp -= n
	_hurt = 0.18
	Sound.play_at("treffer", world, position)
	world.float_text(position + Vector2(-2, -22), "-%d" % int(round(n)), "")
	if _scared > 0.0:
		hp = max(hp, 1.0)
		return
	_provoked = 14.0
	if by is Settler and is_instance_valid(by):
		target = by
	if hp <= 0.0:
		# Die letzten Tiere einer Art (und Jungtiere) entkommen verwundet
		if world.is_protected(self):
			hp = max_hp() * 0.2
			_flee_home()
			world.on_animal_escaped(self)
			return
		dead = true
		world.on_animal_killed(self, by)


## Schuss aus der Jagdhütte (josh 2026-10-20): weg von der Hütte, ans andere Ende des Geheges.
func startle(from: Vector2, meat) -> void:
	_shy = meat
	_scared = 3.0
	_provoked = 0.0
	target = null
	_eat_node = null
	_wait = 0.0
	var best := cell
	var best_d := (position - from).length()
	for i in 14:
		var c := cell + Vector2i(_rng.randi_range(-7, 7), _rng.randi_range(-7, 7))
		if not world.animal_walkable(c) or world.pen_of(c) != world.pen_of(cell):
			continue
		var d: float = (world.cell_to_pos(c) - from).length()
		if d > best_d:
			best_d = d
			best = c
	_path = _path_to(best)
	_path_i = 1
	_flee_t = 3.0


func _flee_home() -> void:
	_scared = float(Data.bal("day_length")) * 0.5
	_provoked = 0.0
	target = null
	_eat_node = null
	_wait = 0.0
	_path = _path_to(home + Vector2i(0, 1))
	_path_i = 1


func _animate(delta: float) -> void:
	_anim += delta
	var frame := 0
	if _attack_anim > 0.0:
		frame = 4
	elif _moving:
		frame = int(_anim * (10.0 if target else 6.0)) % 4
	_sprite.texture = Data.animal_tex(type, frame)
	if not is_adult():
		_sprite.scale = Vector2(0.65, 0.65)
		_sprite.offset = Vector2(-12, -21)
	_sprite.modulate = Color(1, 0.45, 0.45) if _hurt > 0.0 else Color.WHITE
	queue_redraw()


func _draw() -> void:
	if hp < max_hp():
		var w := 16.0
		draw_rect(Rect2(-w / 2 - 1, -26, w + 2, 4), Color(0.16, 0.1, 0.12, 0.85))
		draw_rect(Rect2(-w / 2, -25, w * clamp(hp / max_hp(), 0.0, 1.0), 2), Color(0.9, 0.3, 0.25))
	if Game.selected == self:
		var y := -32.0 + sin(_anim * 5.0) * 2.0
		draw_colored_polygon(PackedVector2Array([Vector2(-4, y), Vector2(4, y), Vector2(0, y + 5)]), Color(1, 0.4, 0.3))


func serialize() -> Array:
	var out := [type, cell.x, cell.y, snappedf(hp, 0.1), home.x, home.y, snappedf(age, 0.01), snappedf(food, 0.01)]
	if homeless_t >= 0.0:
		out.append(snappedf(homeless_t, 0.01))
	return out
