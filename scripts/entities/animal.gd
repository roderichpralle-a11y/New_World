class_name Animal
extends Node2D
## Wildes Tier (Wolf, Wildschwein, Baer). Werte aus data/animals.json.
## Streift um seinen Bau, greift Siedler in der Naehe an und wehrt sich, wenn es
## angegriffen wird. Siedler in Haeusern sieht es nicht.

var type: String
var def: Dictionary
var world
var hp: float = 10.0
var home: Vector2i  # Zelle des Baus
var cell: Vector2i
var target = null  # Settler
var dead: bool = false

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
var _rng := RandomNumberGenerator.new()

var _sprite: Sprite2D
var _shadow: Sprite2D


func setup(p_world, p_type: String, p_cell: Vector2i, p_home: Vector2i, p_hp: float = -1.0) -> void:
	world = p_world
	type = p_type
	def = Data.animals[type]
	cell = p_cell
	home = p_home
	hp = p_hp if p_hp > 0.0 else float(def.hp)
	position = world.cell_to_pos(cell)
	_rng.randomize()
	_shadow = Sprite2D.new()
	_shadow.texture = Data.object_tex("shadow")
	_shadow.position = Vector2(0, 1)
	_shadow.scale = Vector2(1.3, 1.0) if type != "baer" else Vector2(1.7, 1.2)
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.offset = Vector2(-12, -21)
	add_child(_sprite)
	_wait = _rng.randf_range(0.0, 2.0)


func max_hp() -> float:
	return float(def.hp)


## Greift von sich aus an (Wolf, Baer) oder nur, wenn man ihm zu nahe kommt.
func is_hostile() -> bool:
	return target != null or _provoked > 0.0 or float(def.aggro) >= 3.0


func _aggro_px() -> float:
	var r := float(def.night_aggro if Game.is_night() else def.aggro)
	if _provoked > 0.0:
		r = max(r, 8.0)
	return r * 16.0


func _process(delta: float) -> void:
	if dead or Game.is_over:
		return
	_attack_cd -= delta
	_provoked -= delta
	_calm -= delta
	_hurt -= delta
	_attack_anim -= delta
	_think -= delta
	if _think <= 0.0:
		_think = 0.35 + _rng.randf() * 0.2
		_choose_target()
	_moving = false
	if target != null:
		_chase(delta)
	else:
		_wander(delta)
	_animate(delta)


func _valid_target(s) -> bool:
	return s != null and is_instance_valid(s) and s.visible and world.settlers.has(s) and not world.near_fire(s.position)


func _choose_target() -> void:
	var leash := float(def.get("leash", 10)) + (6.0 if _provoked > 0.0 else 0.0)
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
		_path = world.find_path(cell, target.cell)
		_path_i = 1
		if _path.is_empty():
			# Ziel unerreichbar (z. B. auf der anderen Seite des Wassers)
			target = null
			return
	_step(delta, float(def.speed) * 1.1)


func _wander(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		return
	if _path_i >= _path.size():
		var r := 4 if Game.is_night() == (type == "wolf") else 3
		for i in 6:
			var c := home + Vector2i(_rng.randi_range(-r, r), _rng.randi_range(-r, r))
			if world.is_walkable(c):
				_path = world.find_path(cell, c)
				_path_i = 1
				break
		if _path_i >= _path.size():
			_wait = 1.5
			return
	_step(delta, float(def.speed) * 0.45)
	if _path_i >= _path.size():
		_wait = _rng.randf_range(1.5, 4.5)


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
	_provoked = 14.0
	if by is Settler and is_instance_valid(by):
		target = by
	world.float_text(position + Vector2(-2, -22), "-%d" % int(round(n)), "")
	if hp <= 0.0:
		dead = true
		world.on_animal_killed(self, by)


func _animate(delta: float) -> void:
	_anim += delta
	var frame := 0
	if _attack_anim > 0.0:
		frame = 4
	elif _moving:
		frame = int(_anim * (10.0 if target else 6.0)) % 4
	_sprite.texture = Data.animal_tex(type, frame)
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
	return [type, cell.x, cell.y, snappedf(hp, 0.1), home.x, home.y]
