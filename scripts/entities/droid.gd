class_name Droid
extends Settler
## Droide (josh 2026-10-17, Testversion): ein Arbeiter aus der Droidenfabrik. Isst nicht, schläft nicht,
## altert nicht, macht keine Pause und bekommt keine Kinder. Arbeitet, solange auf seiner Insel Strom da ist
## (Droids zieht den Strom ab); ohne Strom bleibt er stehen. Steht nicht in World.settlers, sondern in
## World.droids, zählt also nicht zur Bevölkerung, zum Essen oder zu den Häusern. Nimmt keinen Schaden.

const SPEED := 1.25  # arbeitet etwas schneller als ein Siedler

var powered := true


func setup(p_world, data: Dictionary) -> void:
	super.setup(p_world, data)
	age = 30.0
	max_age = 9999.0
	hunger = 100.0
	health = 100.0
	for sk in Data.skills:
		skills[sk] = 3.0


func _build_visual() -> void:
	super._build_visual()
	for k in _layers:
		_layers[k].queue_free()
	_layers.clear()
	var s := Sprite2D.new()
	s.texture = Settler.sheet("droid")
	s.hframes = 4
	s.vframes = 3
	s.centered = false
	s.offset = Vector2(-8, -22)
	_body.add_child(s)
	_body.move_child(s, 0)
	_layers["droid"] = s


func is_adult() -> bool:
	return true


func skill_factor(_sk: String) -> float:
	return SPEED


func gain_xp(_sk: String, _amount: float = 1.0, _quiet: bool = false) -> void:
	pass


func _needs(_days: float) -> void:
	hunger = 100.0
	health = 100.0
	powered = Droids.powered(world)


func _sleep_time() -> bool:
	return false


func _check_danger(_delta: float) -> void:
	pass


func take_damage(_n: float, _by) -> void:
	pass


func _think() -> void:
	_think_cooldown = 0.6 + _rng.randf() * 0.6
	_release()
	_stat_kind = "needs"
	if not powered:
		_stat_kind = "idle"
		activity = tr("Kein Strom: steht still")
		_plan.append({"a": "wait", "t": 2.0})
		return
	if carry_n > 0:
		_stat_kind = "job"
		if _plan_deliver():
			return
	if _plan_work():
		return
	_stat_kind = "idle"
	_plan_wander(3, tr("Wartet auf Arbeit"))


func _animate(delta: float) -> void:
	super._animate(delta)
	if not powered:
		_body.modulate = Color(0.55, 0.55, 0.6)
	_bubble.visible = false


func serialize() -> Dictionary:
	return {"id": id, "name": display_name, "job": job, "x": cell.x, "y": cell.y,
		"carry_res": carry_res, "carry_n": carry_n, "droid": true}
