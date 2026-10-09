class_name Raider
extends Animal
## Pirat (Ereignis "Piraten", Autoload Events). Landet am Strand (`landing`), zieht zum Eingang des
## nächsten Lagers, plündert dort `plunder_secs` Sekunden und geht dann zurück zum Schiff. Die Beute
## (Events.plan_loot) wird erst beim Ablegen aus dem Lager genommen: wer vorher vertrieben wird, nimmt
## nichts mit. Greift Siedler in `aggro` Feldern an, verfolgt sie höchstens `chase` Felder weit.
## Werte in data/events.json "raider" (nicht in animals.json, damit die Tierlisten ihn nicht sehen).
## Kein Hunger, keine Winterruhe, kein Bau; wird nicht gespeichert (Events lässt nach dem Laden neu landen),
## zählt nicht als Jagdbeute (kein Fleisch, keine Felle, nicht in stats.kills).

enum {LAND, PLUNDER, LEAVE}

var phase: int = LAND
var landing: Vector2i
var loot: Dictionary = {}  # geplante Beute (Ware -> Menge)
var loot_cap: int = 10
var gone := false  # an Bord, verschwunden oder vertrieben
var _plunder_t := 0.0
var _goal := Vector2i(-1, -1)
var _wait_path := 0.0


func setup_raider(p_world, p_cell: Vector2i, p_landing: Vector2i, p_cap: int, p_def: Dictionary) -> void:
	world = p_world
	type = "pirat"
	def = p_def
	cell = p_cell
	home = p_landing
	landing = p_landing
	loot_cap = p_cap
	age = 99.0
	food = 1.0
	hp = max_hp()
	position = world.cell_to_pos(cell)
	_rng.randomize()
	_shadow = Sprite2D.new()
	_shadow.texture = Data.object_tex("shadow")
	_shadow.position = Vector2(0, 1)
	_shadow.scale = Vector2(1.1, 1.0)
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.offset = Vector2(-12, -21)
	add_child(_sprite)
	_wait = _rng.randf_range(0.0, 0.8)
	_animate(0.0)


func is_hostile() -> bool:
	return visible and not dead and not gone


## Zurück zum Schiff (Events: ein halber Tag nach der Landung, oder kein Lager erreichbar).
func go_home() -> void:
	if phase != LEAVE:
		phase = LEAVE
		_goal = Vector2i(-1, -1)
		_path = PackedVector2Array()


func state_text() -> String:
	if target != null and is_instance_valid(target):
		return tr("Greift %s an!") % target.display_name
	match phase:
		LAND:
			return tr("Zieht zum Lager.")
		PLUNDER:
			return tr("Plündert das Lager!")
	if loot.is_empty():
		return tr("Zieht ohne Beute zum Schiff.")
	return tr("Trägt Beute zum Schiff: %s") % loot_text()


func loot_text() -> String:
	var parts := []
	for id in loot:
		parts.append("%d %s" % [int(loot[id]), Data.resource_name(str(id))])
	return ", ".join(parts)


func _process(delta: float) -> void:
	if dead or gone or Game.is_over:
		return
	_attack_cd -= delta
	_provoked -= delta
	_hurt -= delta
	_attack_anim -= delta
	_think -= delta
	_wait_path -= delta
	if _think <= 0.0:
		_think = 0.35 + _rng.randf() * 0.2
		_choose_target()
	_moving = false
	if _wait > 0.0:
		_wait -= delta
	elif target != null:
		_chase(delta)
		if target == null:
			_goal = Vector2i(-1, -1)  # nach der Verfolgung neuen Weg suchen
	else:
		_task(delta)
	_animate(delta)


func _task(delta: float) -> void:
	match phase:
		LAND:
			var st = world.nearest_storage(cell)
			if st == null:
				go_home()
				return
			if _walk_to(st.entrance_cell(), delta):
				phase = PLUNDER
				_plunder_t = float(def.get("plunder_secs", 4.0))
		PLUNDER:
			_plunder_t -= delta
			if fmod(_plunder_t, 1.0) > 0.7:
				_attack_anim = 0.1
			if _plunder_t <= 0.0:
				loot = Events.plan_loot(self)
				phase = LEAVE
				_goal = Vector2i(-1, -1)
				if not loot.is_empty():
					world.float_text(position + Vector2(-10, -26), tr("Beute!"), str(loot.keys()[0]))
		LEAVE:
			if _walk_to(landing, delta):
				Events.on_raider_boarded(self)


## Läuft zur Zelle goal; true, sobald er dort ist. Ohne Weg wartet er und sucht später neu (das Zeitlimit
## der Piraten holt ihn notfalls).
func _walk_to(goal: Vector2i, delta: float) -> bool:
	if _path_i >= _path.size() and Vector2(goal - cell).length() <= 1.0:
		return true
	if _goal != goal or _path_i >= _path.size():
		if _wait_path > 0.0:
			return false
		_goal = goal
		_path = world.find_path(cell, goal)
		_path_i = 1
		if _path.is_empty():
			_wait_path = 2.0
			if phase == LAND:
				go_home()
			return false
	_step(delta, float(def.speed))
	return false


func _valid_target(s) -> bool:
	return s != null and is_instance_valid(s) and s.visible and world.settlers.has(s)


## Greift Siedler in `aggro` Feldern an (Tag und Nacht gleich), verfolgt sie höchstens `chase` Felder.
func _choose_target() -> void:
	if _valid_target(target) and (target.position - position).length() < float(def.get("chase", 9)) * 16.0:
		return
	target = null
	var best = null
	var best_d := float(def.get("aggro", 3)) * 16.0
	for s in world.settlers:
		if not s.visible:
			continue
		var d: float = (s.position - position).length()
		if d < best_d:
			best_d = d
			best = s
	target = best
	if target:
		_path = PackedVector2Array()


func take_damage(n: float, by) -> void:
	if dead or gone:
		return
	hp -= n
	_hurt = 0.18
	Sound.play_at("treffer", world, position)
	world.float_text(position + Vector2(-2, -22), "-%d" % int(round(n)), "")
	_provoked = 14.0
	if by is Settler and is_instance_valid(by) and by.visible:
		target = by
	if hp <= 0.0:
		dead = true
		Events.on_raider_killed(self, by)


func serialize() -> Array:
	return []  # wird nicht gespeichert (World.serialize lässt Piraten aus)


## Infofenster (hud._info_animal): Kraft, was er tut, Beute und wie man sich wehrt.
func fill_info(h) -> void:
	h._info_head(str(def.get("name", "")))
	var hb: ProgressBar = h._bar_row(tr("Kraft"), hp / max_hp() * 100.0, UiTheme.BAD)
	var st := UiTheme.label("", 14, Color("#6a4a30"))
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h._info_box.add_child(st)
	var upd := func():
		if not is_instance_valid(self) or gone:
			return
		hb.value = hp / max_hp() * 100.0
		st.text = state_text()
	upd.call()
	h._updaters.append(upd)
	var l := UiTheme.label(tr("Gefährlich! Schlag: %d Schaden. Jäger und Wachtürme vertreiben Piraten. Ihre Beute nehmen sie erst beim Ablegen aus dem Lager; wer vorher vertrieben wird, bekommt nichts.") % int(def.get("damage", 7)), 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h._info_box.add_child(l)
