class_name Settler
extends Node2D
## Ein Siedler mit Beduerfnissen, Faehigkeiten und einer einfachen Aufgaben-KI.
## Die KI plant kurze Aktionsfolgen (gehen, arbeiten, warten); Plaene werden nicht
## gespeichert, nach dem Laden plant jeder Siedler einfach neu.

const SKIN := ["#f2c9a0", "#e0ac7e", "#c68a5e", "#9a6440", "#6e4630"]
const HAIR := ["#3a2a22", "#6b4226", "#a8642e", "#d9a650", "#f0d890", "#2b2b38", "#b84a2e", "#8c8c94"]
const SHIRT := ["#4f8fd6", "#d65f4f", "#58b06a", "#e0b040", "#9a68c8", "#e08a40", "#40b0b0", "#f0f0e8"]
const PANTS := ["#5a4a7a", "#4a5a3a", "#6a4a3a", "#3a4a6a", "#7a6a5a"]
const DIR_DOWN := 0
const DIR_UP := 1
const DIR_SIDE := 2

var id: int
var display_name: String
var sex: String = "m"
var age: float = 18.0
var max_age: float = 40.0
var hunger: float = 90.0
var health: float = 100.0
var skills: Dictionary = {}
var skill_xp: Dictionary = {}
var job: String = "frei"
var home_id: int = 0
var look: Dictionary = {}
var carry_res: String = ""
var carry_n: int = 0
var birth_cooldown_until: float = 0.0
var parents: Array = []
var world

var cell: Vector2i
var activity: String = "Schaut sich um"
var sleeping: bool = false

var _plan: Array = []
var _path: PackedVector2Array = PackedVector2Array()
var _path_i: int = 0
var _work_t: float = 0.0
var _anim_t: float = 0.0
var _dir: int = DIR_DOWN
var _flip: bool = false
var _moving: bool = false
var _working: bool = false
var _think_cooldown: float = 0.0
var _reserved = null  # ResNode oder Building, das reserviert ist
var _incoming: Array = []  # [Building, res, n] fuer Materiallieferungen
var _rng := RandomNumberGenerator.new()

var _body: Node2D
var _layers: Dictionary = {}
var _tool: Sprite2D
var _carry_icon: Sprite2D
var _bubble: Sprite2D
var _zzz: Label
var _shadow: Sprite2D

static var _sheets: Dictionary = {}


static func sheet(name: String) -> Texture2D:
	if not _sheets.has(name):
		_sheets[name] = load("res://assets/sprites/settler_%s.png" % name)
	return _sheets[name]


func setup(p_world, data: Dictionary) -> void:
	world = p_world
	_rng.randomize()
	id = int(data.get("id", Game.new_id()))
	display_name = data.get("name", "Siedler")
	sex = data.get("sex", "m")
	age = float(data.get("age", 18.0))
	max_age = float(data.get("max_age", _rng.randf_range(Data.bal("old_age_min"), Data.bal("old_age_max"))))
	hunger = float(data.get("hunger", 90.0))
	health = float(data.get("health", 100.0))
	skills = data.get("skills", {})
	for sk in Data.skills:
		skills[sk] = float(skills.get(sk, 1.0))
	skill_xp = data.get("skill_xp", {})
	job = data.get("job", "frei")
	home_id = int(data.get("home", 0))
	look = data.get("look", random_look(_rng))
	carry_res = data.get("carry_res", "")
	carry_n = int(data.get("carry_n", 0))
	birth_cooldown_until = float(data.get("birth_cd", 0.0))
	parents = data.get("parents", [])
	cell = Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))
	position = world.cell_to_pos(cell)
	_build_visual()
	_update_scale()


static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"skin": SKIN[rng.randi() % SKIN.size()],
		"hair": HAIR[rng.randi() % HAIR.size()],
		"style": rng.randi() % 3,
		"shirt": SHIRT[rng.randi() % SHIRT.size()],
		"pants": PANTS[rng.randi() % PANTS.size()],
	}


func _build_visual() -> void:
	_shadow = Sprite2D.new()
	_shadow.texture = Data.object_tex("shadow")
	_shadow.position = Vector2(0, 1)
	add_child(_shadow)
	_body = Node2D.new()
	add_child(_body)
	var style := int(look.get("style", 0))
	var order := [["pants", "pants"], ["shirt", "shirt"], ["skin", "skin"],
		["hair_%d" % style, "hair"], ["fixed_bun" if style == 2 else "fixed", ""]]
	for o in order:
		var s := Sprite2D.new()
		s.texture = sheet(o[0])
		s.hframes = 4
		s.vframes = 3
		s.centered = false
		s.offset = Vector2(-8, -22)
		if o[1] != "":
			s.modulate = Color(look.get(o[1], "#ffffff"))
		_body.add_child(s)
		_layers[o[0]] = s
	_tool = Sprite2D.new()
	_tool.visible = false
	_tool.position = Vector2(5, -8)
	_tool.offset = Vector2(4, -4)
	_body.add_child(_tool)
	_carry_icon = Sprite2D.new()
	_carry_icon.position = Vector2(0, -27)
	_carry_icon.scale = Vector2(0.75, 0.75)
	_carry_icon.visible = false
	_body.add_child(_carry_icon)
	_bubble = Sprite2D.new()
	_bubble.position = Vector2(8, -28)
	_bubble.visible = false
	_bubble.texture = Data.icon("nahrung")
	_body.add_child(_bubble)
	_zzz = Label.new()
	_zzz.text = "z Z"
	_zzz.position = Vector2(-2, -34)
	_zzz.add_theme_font_size_override("font_size", 10)
	_zzz.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_zzz.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.2))
	_zzz.add_theme_constant_override("outline_size", 3)
	_zzz.visible = false
	add_child(_zzz)


func _update_scale() -> void:
	var s := 1.0 if is_adult() else lerpf(0.6, 0.85, clamp(age / float(Data.bal("adult_age")), 0.0, 1.0))
	_body.scale = Vector2(s, s)
	_shadow.scale = Vector2(s, s)


func is_adult() -> bool:
	return age >= float(Data.bal("adult_age"))


func skill_level(sk: String) -> float:
	return float(skills.get(sk, 1.0))


func skill_factor(sk: String) -> float:
	if sk == "":
		return 1.0
	return 0.6 + 0.08 * skill_level(sk)


func gain_xp(sk: String, amount: float = 1.0) -> void:
	if sk == "":
		return
	skill_xp[sk] = float(skill_xp.get(sk, 0.0)) + amount
	var need := float(Data.bal("skill_xp_per_level")) * skill_level(sk)
	if skill_xp[sk] >= need and skill_level(sk) < float(Data.bal("skill_max")):
		skill_xp[sk] = 0.0
		skills[sk] = skill_level(sk) + 1.0
		Game.notify("%s ist besser geworden: %s Stufe %d." % [display_name, Data.skills[sk].name, int(skills[sk])], "sonne")
		world.float_text(position + Vector2(0, -30), "Stufe %d!" % int(skills[sk]), "")


func best_job() -> String:
	var best := "frei"
	var best_v := 1.5
	var map := {"holz": "holzfaeller", "stein": "steinmetz", "nahrung": "sammler", "bauen": "baumeister",
		"handwerk": "handwerker", "wissen": "forscher"}
	for sk in map:
		if skill_level(sk) > best_v:
			best_v = skill_level(sk)
			best = map[sk]
	return best


func set_job(j: String) -> void:
	if j == job:
		return
	job = j
	abort_plan()


func job_name() -> String:
	return Data.jobs.get(job, {}).get("name", job)


# ================================================================== Simulation
func _process(delta: float) -> void:
	if Game.is_over:
		return
	var days := delta / float(Data.bal("day_length"))
	_needs(days)
	if not is_instance_valid(self) or is_queued_for_deletion():
		return
	if _plan.is_empty():
		_think_cooldown -= delta
		if _think_cooldown <= 0.0:
			_think()
	else:
		_run_action(delta)
	_animate(delta)


func _needs(days: float) -> void:
	var f := 1.0 if is_adult() else float(Data.bal("child_hunger_factor"))
	if sleeping:
		f *= 0.6
	hunger = max(0.0, hunger - float(Data.bal("hunger_per_day")) * days * f)
	if hunger <= 0.0:
		health -= float(Data.bal("starve_damage_per_day")) * days
	elif hunger > 30.0:
		health = min(100.0, health + float(Data.bal("heal_per_day")) * Game.eff("heal") * days)
	var was_adult := is_adult()
	age += days
	if not was_adult and is_adult():
		job = "frei"
		Game.notify("%s ist erwachsen und kann jetzt arbeiten." % display_name, "person")
		abort_plan()
	_update_scale()
	if health <= 0.0:
		world.kill_settler(self, "verhungert")
	elif age >= max_age + Game.eff_add("life"):
		world.kill_settler(self, "im hohen Alter von %d Jahren gestorben" % int(age))


# ------------------------------------------------------------------ Planung
func _think() -> void:
	_think_cooldown = 0.6 + _rng.randf() * 0.6
	_release()
	if sleeping and (Game.is_night()):
		return
	if sleeping:
		_wake_up()
	# 1. Getragenes abliefern
	if carry_n > 0:
		if _plan_deliver():
			return
	# 2. Essen
	if hunger < float(Data.bal("eat_below")) and Game.total_food() > 0:
		if _plan_eat():
			return
	# 3. Schlafen
	if Game.is_night():
		_plan_sleep()
		return
	# 4. Kinder spielen
	if not is_adult():
		_plan_wander(5, "Spielt")
		return
	# 5. Arbeit
	if _plan_work():
		return
	_plan_wander(4, "Hat nichts zu tun")


func abort_plan() -> void:
	_plan.clear()
	_path = PackedVector2Array()
	_working = false
	_moving = false
	_release()
	_think_cooldown = 0.0


func _release() -> void:
	if _reserved and is_instance_valid(_reserved):
		if _reserved.reserved_by == id:
			_reserved.reserved_by = 0
		if _reserved is Building:
			_reserved.occupants.erase(id)
	_reserved = null
	for inc in _incoming:
		var b = inc[0]
		if is_instance_valid(b):
			b.incoming[inc[1]] = max(0, int(b.incoming.get(inc[1], 0)) - int(inc[2]))
	_incoming.clear()


func _reserve(obj) -> void:
	_reserved = obj
	obj.reserved_by = id


## Platz in einer Werkstatt oder Forschungsstaette belegen (mehrere Plaetze moeglich).
func _occupy(b) -> void:
	_reserved = b
	if not id in b.occupants:
		b.occupants.append(id)


func carry_capacity() -> int:
	return int(Data.bal("carry_capacity")) + int(Game.eff_add("carry"))


## Arbeitstempo fuer eine Faehigkeit inklusive Forschungsboni.
func work_factor(sk: String, bonus: String = "") -> float:
	var f := skill_factor(sk) * Game.eff("work")
	if bonus != "":
		f *= Game.eff(bonus)
	return f


## Gehe zu einer Zelle neben dem Ziel. Gibt false zurueck, wenn unerreichbar.
func _push_move_to(target_cells: Array, adjacent: bool = true) -> bool:
	var dest = world.find_approach(cell, target_cells, adjacent)
	if dest == null:
		return false
	_plan.append({"a": "move", "cell": dest})
	return true


func _plan_deliver() -> bool:
	var st = world.nearest_storage(cell)
	if st == null:
		return false
	if not _push_move_to(st.cells()):
		return false
	_plan.append({"a": "work", "t": 0.4, "act": "Liefert ab", "done": _do_deliver})
	activity = "Bringt %s zum Lager" % Data.resource_name(carry_res)
	return true


func _do_deliver() -> void:
	if carry_n <= 0:
		return
	var added := Game.add_stock(carry_res, carry_n)
	if added > 0:
		world.float_text(position + Vector2(0, -26), "+%d" % added, carry_res)
	if added < carry_n:
		world.warn_storage_full(carry_res)
	carry_n = 0
	carry_res = ""


func _plan_eat() -> bool:
	var st = world.nearest_storage(cell)
	if st == null:
		return false
	if not _push_move_to(st.cells()):
		return false
	_plan.append({"a": "work", "t": 1.6, "act": "Isst", "done": _do_eat})
	activity = "Geht essen"
	return true


func _do_eat() -> void:
	var eaten := 0
	while hunger < float(Data.bal("eat_until")):
		var n := Game.eat_one()
		if n <= 0.0:
			break
		hunger = min(100.0, hunger + n)
		eaten += 1
	if eaten > 0:
		world.float_text(position + Vector2(0, -26), "Mahlzeit", "nahrung")


func _plan_sleep() -> void:
	var home = world.building_by_id(home_id)
	if home and home.complete:
		if _push_move_to([home.entrance_cell()], false):
			_plan.append({"a": "work", "t": 0.2, "act": "Geht schlafen", "done": _do_sleep_inside})
			activity = "Geht nach Hause"
			return
	var fire = world.nearest_storage(cell)
	if fire and _push_move_to(fire.cells()):
		_plan.append({"a": "work", "t": 0.2, "act": "Legt sich hin", "done": _do_sleep_outside})
		activity = "Sucht einen Schlafplatz"
		return
	_do_sleep_outside()


func _do_sleep_inside() -> void:
	sleeping = true
	visible = false
	activity = "Schläft in der Hütte"


func _do_sleep_outside() -> void:
	sleeping = true
	_body.rotation = -PI / 2
	_body.position = Vector2(-6, -4)
	_zzz.visible = true
	activity = "Schläft unter freiem Himmel"


func _wake_up() -> void:
	sleeping = false
	visible = true
	_body.rotation = 0
	_body.position = Vector2.ZERO
	_zzz.visible = false


func _plan_wander(radius: int, text: String) -> void:
	var anchor: Vector2i = cell
	var st = world.nearest_storage(cell)
	if st:
		anchor = st.cell
	for i in 6:
		var c := anchor + Vector2i(_rng.randi_range(-radius, radius), _rng.randi_range(-radius, radius))
		if world.is_walkable(c):
			_plan.append({"a": "move", "cell": c})
			_plan.append({"a": "wait", "t": _rng.randf_range(1.0, 3.0)})
			activity = text
			return
	_plan.append({"a": "wait", "t": 1.5})


# ------------------------------------------------------------------ Arbeit
func _plan_work() -> bool:
	match job:
		"frei":
			return _plan_free()
		"baumeister":
			return _plan_construction() or _plan_free_gather()
		"bauer":
			return _plan_farm() or _plan_gather(["busch"])
		"forscher":
			return _plan_research() or _plan_free_gather()
		_:
			var targets: Array = Data.jobs.get(job, {}).get("targets", [])
			# Ist das eigene Lager voll, hilft der Siedler woanders aus
			return _plan_gather(targets) or _plan_construction() or _plan_free_gather()


func _plan_free() -> bool:
	if _plan_construction():
		return true
	return _plan_free_gather()


func _plan_free_gather() -> bool:
	var pop: int = max(1, Game.population())
	if Game.total_food() < pop * 10:
		if _plan_farm() or _plan_gather(["busch", "fischgrund"]):
			return true
	# Was am knappsten ist (Holz wird doppelt gewichtet, weil es ueberall gebraucht wird)
	var wood := Game.amount("holz") / 2.0
	var stone := float(Game.amount("stein"))
	var order := ["baum", "fels"] if wood <= stone else ["fels", "baum"]
	for t in order:
		if _plan_gather([t]):
			return true
	return _plan_gather(["busch", "fischgrund"])


func _plan_gather(types: Array) -> bool:
	for t in types:
		if t == "farm":
			if _plan_farm():
				return true
			continue
		if t == "construction":
			if _plan_construction():
				return true
			continue
		if t.begins_with("prod:"):
			if _plan_production(t.trim_prefix("prod:")):
				return true
			continue
		var res: String = Data.nodes.get(t, {}).get("yield", "")
		if res != "" and Game.space_for(res) <= 0:
			continue
		var node = world.find_node_for(t, cell, id)
		if node == null:
			continue
		var adjacent: bool = node.is_solid() or world.is_water(node.cell)
		if not _push_move_to([node.cell], adjacent):
			world.mark_unreachable(node)
			continue
		_reserve(node)
		var def: Dictionary = node.def
		var job_def: Dictionary = Data.jobs.get(job, {})
		var tool_name: String = job_def.get("tool", "")
		if tool_name == "" or not t in job_def.get("targets", []):
			tool_name = _tool_for_node(t)
		_plan.append({"a": "work", "t": float(def.work_time) / work_factor(def.skill, "gather_" + res), "act": _verb(t),
			"tool": tool_name, "face": node.position, "done": _do_harvest.bind(node)})
		activity = "%s (%s)" % [_verb(t), def.name]
		return true
	return false


func _tool_for_node(t: String) -> String:
	return {"baum": "axe", "fels": "pick", "busch": "basket", "fischgrund": "rod"}.get(t, "")


func _verb(t: String) -> String:
	return {"baum": "Fällt einen Baum", "fels": "Schlägt Steine", "busch": "Pflückt Beeren",
		"fischgrund": "Angelt"}.get(t, "Arbeitet")


func _do_harvest(node) -> void:
	if not is_instance_valid(node) or not node.is_available():
		return
	var res: String = node.def.yield
	var got: int = node.harvest_one()
	if got <= 0:
		return
	if carry_res != res and carry_n > 0:
		_do_deliver()
	carry_res = res
	carry_n += got
	gain_xp(node.def.skill)
	world.spawn_effect("chips_" + node.type, node.position + Vector2(0, -6))
	# Weiterarbeiten, solange Platz und Zeit ist
	var cap := carry_capacity()
	if carry_n < cap and is_instance_valid(node) and node.is_available() and not Game.is_night() \
			and hunger >= float(Data.bal("eat_below")) * 0.6:
		_plan.push_front({"a": "work", "t": float(node.def.work_time) / work_factor(node.def.skill, "gather_" + res),
			"act": _verb(node.type), "tool": _cur_tool, "face": node.position,
			"done": _do_harvest.bind(node)})
	else:
		_plan_deliver_after()


func _plan_deliver_after() -> void:
	_release()
	var st = world.nearest_storage(cell)
	if st and _push_move_to(st.cells()):
		_plan.append({"a": "work", "t": 0.4, "act": "Liefert ab", "done": _do_deliver})
		activity = "Bringt %s zum Lager" % Data.resource_name(carry_res)


func _plan_farm() -> bool:
	var field = world.find_field_task(cell, id)
	if field == null:
		return false
	var task: String = field.farm_task()
	var fd: Dictionary = field.farm_def()
	if task == "harvest" and Game.space_for(fd.yield) <= 0:
		return false
	var target: Vector2i = field.cells()[_rng.randi() % field.cells().size()]
	if not _push_move_to([target], false):
		return false
	_reserve(field)
	if task == "sow":
		_plan.append({"a": "work", "t": float(fd.sow_time) / work_factor("nahrung"), "act": "Sät",
			"tool": "sickle", "done": _do_sow.bind(field)})
		activity = fd.get("sow_verb", "Sät")
	else:
		_plan.append({"a": "work", "t": float(fd.harvest_time) * 2.0 / work_factor("nahrung"), "act": "Erntet",
			"tool": "sickle", "done": _do_field_harvest.bind(field)})
		activity = fd.get("harvest_verb", "Erntet")
	return true


func _do_sow(field) -> void:
	if is_instance_valid(field) and field.farm_task() == "sow":
		field.sow()
		gain_xp("nahrung")


func _do_field_harvest(field) -> void:
	if is_instance_valid(field) and field.farm_task() == "harvest":
		var n: int = field.harvest()
		carry_res = field.farm_def().yield
		carry_n = n
		gain_xp("nahrung", 2.0)
		_plan_deliver_after()


func _plan_construction() -> bool:
	var sites: Array = world.construction_sites()
	sites.sort_custom(func(a, b): return Vector2(a.cell - cell).length() < Vector2(b.cell - cell).length())
	# Zuerst bauen, wo alles Material da ist
	for site in sites:
		if site.materials_complete():
			if _push_move_to(site.cells(), not site.is_ground()):
				_plan.append({"a": "work", "t": 1.5, "act": "Baut", "tool": "hammer",
					"face": site.position, "done": _do_build.bind(site)})
				activity = "Baut: %s" % site.def.name
				return true
	# Dann Material liefern
	for site in sites:
		var need: Dictionary = site.remaining_cost()
		for res in need:
			var n: int = min(min(int(need[res]), Game.amount(res)), carry_capacity() + 2)
			if n <= 0:
				continue
			var st = world.nearest_storage(cell)
			if st == null:
				return false
			if not _push_move_to(st.cells()):
				continue
			var mark := _plan.size()
			_plan.append({"a": "work", "t": 0.5, "act": "Holt Material", "done": _do_pickup.bind(site, res, n)})
			if not _push_move_to(site.cells(), not site.is_ground()):
				_plan.resize(mark - 1)
				continue
			_plan.append({"a": "work", "t": 0.5, "act": "Liefert Material", "tool": "hammer", "done": _do_site_deliver.bind(site)})
			site.incoming[res] = int(site.incoming.get(res, 0)) + n
			_incoming.append([site, res, n])
			activity = "Bringt %s zur Baustelle" % Data.resource_name(res)
			return true
	return false


func _do_pickup(site, res: String, n: int) -> void:
	if carry_n > 0:
		_do_deliver()
	var got := Game.take_stock(res, n)
	# Reservierung anpassen
	for inc in _incoming:
		if inc[0] == site and inc[1] == res:
			if is_instance_valid(site):
				site.incoming[res] = max(0, int(site.incoming.get(res, 0)) - (n - got))
			inc[2] = got
	carry_res = res
	carry_n = got
	if got <= 0 or not is_instance_valid(site) or site.complete:
		abort_plan()


func _do_site_deliver(site) -> void:
	if not is_instance_valid(site) or carry_n <= 0:
		return
	site.deliver(carry_res, carry_n)
	for inc in _incoming:
		if inc[0] == site:
			inc[2] = 0
	_incoming.clear()
	carry_n = 0
	carry_res = ""


func _do_build(site) -> void:
	if not is_instance_valid(site) or site.complete:
		return
	site.add_work(1.5 * work_factor("bauen", "build"))
	gain_xp("bauen", 0.5)
	world.spawn_effect("dust", site.position + Vector2(_rng.randf_range(-12, 12), -4))
	if not site.complete and not Game.is_night() and hunger >= float(Data.bal("eat_below")) * 0.6:
		_plan.push_front({"a": "work", "t": 1.5, "act": "Baut", "tool": "hammer",
			"face": site.position, "done": _do_build.bind(site)})


# ------------------------------------------------------------------ Werkstaetten
func _plan_production(kind: String) -> bool:
	var b = world.find_workshop(kind, cell, id)
	if b == null:
		return false
	if not _push_move_to([b.entrance_cell()], false) and not _push_move_to(b.cells()):
		world.mark_unreachable(b)
		return false
	_occupy(b)
	var p: Dictionary = b.prod_def()
	var tool_name: String = p.get("tool", Data.jobs.get(job, {}).get("tool", "hammer"))
	_plan.append({"a": "work", "t": 0.3, "act": "Holt Rohstoffe", "done": _do_take_inputs.bind(b)})
	_plan.append({"a": "work", "t": float(p.time) / work_factor(p.get("skill", "handwerk")), "act": p.get("verb", "Arbeitet"),
		"tool": tool_name, "face": b.position, "done": _do_produce.bind(b)})
	activity = "%s (%s)" % [p.get("verb", "Arbeitet"), b.def.name]
	return true


func _do_take_inputs(b) -> void:
	if not is_instance_valid(b) or not b.take_inputs():
		abort_plan()
		return
	if carry_n > 0:
		_do_deliver()
	b.mark_active(float(b.prod_def().time) / work_factor(b.prod_def().get("skill", "handwerk")) + 0.5)


func _do_produce(b) -> void:
	if not is_instance_valid(b):
		return
	var p: Dictionary = b.prod_def()
	gain_xp(p.get("skill", "handwerk"))
	var outs: Dictionary = p.get("outputs", {})
	var first := true
	for res in outs:
		var n := int(outs[res])
		if first:
			carry_res = res
			carry_n = n
			first = false
		else:
			# Nebenprodukte gehen direkt ins Lager
			Game.add_stock(res, n)
	world.spawn_effect("dust", b.position + Vector2(_rng.randf_range(-8, 8), -4))
	_plan_deliver_after()


# ------------------------------------------------------------------ Forschung
func _plan_research() -> bool:
	if not Game.has_research_goal():
		return false
	var b = world.find_research_place(cell, id)
	if b == null:
		return false
	if not _push_move_to(b.cells()):
		world.mark_unreachable(b)
		return false
	_occupy(b)
	_push_research_step(b)
	activity = "Forscht: %s" % Data.techs[Game.research.current].name
	return true


func _push_research_step(b) -> void:
	_plan.append({"a": "work", "t": float(Data.bal("research_work_time", 2.5)), "act": "Forscht",
		"tool": "book", "face": b.position, "done": _do_research.bind(b)})


func _do_research(b) -> void:
	if not is_instance_valid(b) or not b.complete:
		return
	var pts := float(Data.bal("research_per_work", 1.0)) * float(b.research_def().get("factor", 1.0)) * skill_factor("wissen")
	Game.add_research(pts)
	gain_xp("wissen", 0.5)
	b.mark_active(3.0)
	if _rng.randf() < 0.2:
		world.float_text(position + Vector2(0, -28), "Idee!", "")
	if Game.has_research_goal() and not Game.is_night() and hunger >= float(Data.bal("eat_below")) * 0.6:
		_plan.push_front({"a": "work", "t": float(Data.bal("research_work_time", 2.5)), "act": "Forscht",
			"tool": "book", "face": b.position, "done": _do_research.bind(b)})


# ------------------------------------------------------------------ Ausfuehrung
var _cur_tool: String = ""


func _run_action(delta: float) -> void:
	var a: Dictionary = _plan[0]
	match a.a:
		"move":
			if not a.get("started", false):
				a.started = true
				_path = world.find_path(cell, a.cell)
				_path_i = 1
				if _path.is_empty():
					_plan.clear()
					_release()
					_think_cooldown = 1.0
					return
			_moving = true
			_working = false
			if _path_i >= _path.size():
				_moving = false
				cell = a.cell
				_plan.pop_front()
				return
			var target: Vector2 = _path[_path_i]
			var spd := float(Data.bal("walk_speed")) * Game.eff("walk") * (1.0 if is_adult() else 0.85)
			if hunger <= 0.0:
				spd *= 0.6
			var to := target - position
			var step := spd * delta
			if to.length() <= step:
				position = target
				cell = world.pos_to_cell(target)
				_path_i += 1
			else:
				position += to.normalized() * step
			_face(to)
		"work":
			_moving = false
			if not a.get("started", false):
				a.started = true
				_work_t = 0.0
				_cur_tool = a.get("tool", "")
				if a.has("face"):
					_face(a.face - position)
			_working = _cur_tool != ""
			_work_t += delta
			if _work_t >= float(a.t):
				_working = false
				_plan.pop_front()
				var cb: Callable = a.get("done", Callable())
				if cb.is_valid():
					cb.call()
		"wait":
			_moving = false
			_working = false
			a.t = float(a.t) - delta
			if a.t <= 0.0:
				_plan.pop_front()


func _face(v: Vector2) -> void:
	if v.length() < 0.01:
		return
	if abs(v.x) > abs(v.y) * 0.9:
		_dir = DIR_SIDE
		_flip = v.x < 0
	elif v.y > 0:
		_dir = DIR_DOWN
	else:
		_dir = DIR_UP


func _animate(delta: float) -> void:
	_anim_t += delta
	var frame := 0
	if _moving:
		frame = int(_anim_t * 8.0) % 4
	for k in _layers:
		var s: Sprite2D = _layers[k]
		s.frame = _dir * 4 + frame
		s.flip_h = _flip and _dir == DIR_SIDE
		s.offset.x = -8 if not s.flip_h else -8
	# Werkzeug schwingen
	_tool.visible = _working and _cur_tool != "" and not sleeping
	if _tool.visible:
		_tool.texture = Data.tool_tex(_cur_tool)
		var swing := sin(_anim_t * 9.0)
		_tool.rotation = -0.9 + swing * 0.9 if _cur_tool != "rod" else -0.3 + swing * 0.08
		_tool.position = Vector2(-5 if (_flip and _dir == DIR_SIDE) else 5, -9)
		_tool.flip_h = _flip and _dir == DIR_SIDE
		_tool.z_index = -1 if _dir == DIR_UP else 0
		_body.position.y = -abs(swing) * 0.8 if not sleeping else _body.position.y
	elif not sleeping:
		_body.position.y = 0
	_carry_icon.visible = carry_n > 0 and not sleeping
	if _carry_icon.visible:
		_carry_icon.texture = Data.icon(Data.resources.get(carry_res, {}).get("icon", carry_res))
		_carry_icon.position.y = -27 + sin(_anim_t * 4.0) * 0.6
	_bubble.visible = hunger < 20.0 and not sleeping and int(_anim_t * 2.0) % 3 != 0
	_zzz.visible = sleeping and visible and _body.rotation != 0
	if _zzz.visible:
		_zzz.position.y = -30 + sin(_anim_t * 2.0) * 2.0
	queue_redraw()


func _draw() -> void:
	if Game.selected == self:
		var y := -32.0 + sin(_anim_t * 5.0) * 2.0
		if not is_adult():
			y += 8.0
		draw_colored_polygon(PackedVector2Array([Vector2(-4, y), Vector2(4, y), Vector2(0, y + 5)]), Color(1, 0.9, 0.3))
		draw_polyline(PackedVector2Array([Vector2(-4, y), Vector2(4, y), Vector2(0, y + 5), Vector2(-4, y)]), Color(0.2, 0.12, 0.1), 1.0)


# ------------------------------------------------------------------ Speichern
func serialize() -> Dictionary:
	return {
		"id": id, "name": display_name, "sex": sex, "age": snappedf(age, 0.001), "max_age": max_age,
		"hunger": snappedf(hunger, 0.01), "health": snappedf(health, 0.01), "skills": skills,
		"skill_xp": skill_xp, "job": job, "home": home_id, "look": look,
		"carry_res": carry_res, "carry_n": carry_n, "birth_cd": birth_cooldown_until,
		"parents": parents, "x": cell.x, "y": cell.y,
	}
