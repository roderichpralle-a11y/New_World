extends Node
## Globaler Spielzustand: Zeit, Vorraete, Bevoelkerung, Speichern/Laden.
## Die Welt (World) haelt die Entitaeten; Game kennt sie ueber `world`.

signal stock_changed
signal population_changed
signal notified(text: String, icon: String)
signal day_started(day: int)
signal selection_changed(obj)
signal speed_changed(speed: int)
signal game_over

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

var world = null  # World
var seed_value: int = 0
var time_days: float = 0.25  # Start am Morgen von Tag 1
var speed: int = 1
var stock: Dictionary = {}
var next_id: int = 1
var stats: Dictionary = {"births": 0, "deaths": 0, "max_pop": 0}
var selected = null
var is_over: bool = false
var lineage: Dictionary = {}  # Siedler-ID -> [Eltern-IDs], auch fuer Verstorbene

var _birth_timer: float = 0.0
var _autosave_timer: float = 0.0
var _last_day: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS


func reset_state(new_seed: int) -> void:
	seed_value = new_seed
	time_days = 0.25
	stock = {}
	for id in Data.resources:
		stock[id] = 0
	for id in Data.bal("start_stock", {}):
		stock[id] = int(Data.bal("start_stock")[id])
	next_id = 1
	stats = {"births": 0, "deaths": 0, "max_pop": 0}
	lineage = {}
	selected = null
	is_over = false
	_last_day = day()
	set_speed(1)


func new_id() -> int:
	next_id += 1
	return next_id - 1


# ---------------------------------------------------------------- Zeit
func day() -> int:
	return int(floor(time_days)) + 1


func time_of_day() -> float:
	return fposmod(time_days, 1.0)


func is_night() -> bool:
	var t := time_of_day()
	return t >= Data.bal("night_start") or t < Data.bal("night_end")


func clock_text() -> String:
	var minutes := int(time_of_day() * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func set_speed(s: int) -> void:
	speed = clamp(s, 0, 3)
	Engine.time_scale = float(speed)
	speed_changed.emit(speed)


func _process(delta: float) -> void:
	if world == null or is_over:
		return
	# delta ist bereits mit Engine.time_scale skaliert
	if speed > 0:
		time_days += delta / float(Data.bal("day_length"))
		if day() != _last_day:
			_last_day = day()
			day_started.emit(_last_day)
			notify("Tag %d beginnt." % _last_day, "sonne")
		_birth_timer += delta / float(Data.bal("day_length"))
		if _birth_timer >= float(Data.bal("birth_check_interval")):
			_birth_timer = 0.0
			_try_birth()
	# Autosave in Echtzeit
	var now := Time.get_ticks_msec() / 1000.0
	if now - _autosave_timer >= float(Data.bal("autosave_seconds")):
		_autosave_timer = now
		save_game()


# ---------------------------------------------------------------- Vorraete
func storage_capacity() -> int:
	var cap := int(Data.bal("base_storage"))
	if world:
		for b in world.buildings:
			if b.complete:
				cap += int(b.def.get("storage", 0))
	return cap


func housing_capacity() -> int:
	var cap := 0
	if world:
		for b in world.buildings:
			if b.complete:
				cap += int(b.def.get("housing", 0))
	return cap


func population() -> int:
	return world.settlers.size() if world else 0


func total_food() -> int:
	var n := 0
	for id in Data.food_ids():
		n += int(stock.get(id, 0))
	return n


func amount(id: String) -> int:
	return int(stock.get(id, 0))


## Fuegt Vorrat hinzu; gibt die tatsaechlich eingelagerte Menge zurueck.
func add_stock(id: String, n: int) -> int:
	var cap := storage_capacity()
	var cur := amount(id)
	var add: int = clamp(n, 0, max(0, cap - cur))
	stock[id] = cur + add
	stock_changed.emit()
	return add


func space_for(id: String) -> int:
	return max(0, storage_capacity() - amount(id))


func take_stock(id: String, n: int) -> int:
	var take: int = min(n, amount(id))
	stock[id] = amount(id) - take
	stock_changed.emit()
	return take


func can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if amount(id) < int(cost[id]):
			return false
	return true


## Nimmt eine Mahlzeit: liefert Naehrwert (0 wenn nichts da).
func eat_one() -> float:
	# Abwechslung: nimm die Sorte, von der am meisten da ist
	var best := ""
	for id in Data.food_ids():
		if amount(id) > 0 and (best == "" or amount(id) > amount(best)):
			best = id
	if best == "":
		return 0.0
	take_stock(best, 1)
	return float(Data.resources[best].get("nutrition", 20))


func notify(text: String, icon: String = "") -> void:
	notified.emit(text, icon)


func select(obj) -> void:
	selected = obj
	selection_changed.emit(obj)


# ---------------------------------------------------------------- Nachwuchs
func _try_birth() -> void:
	if world == null:
		return
	var pop := population()
	if pop >= housing_capacity():
		return
	if total_food() < pop * int(Data.bal("birth_food_per_person")):
		return
	var couples := []
	var possible := false
	var adults: Array = world.settlers.filter(func(s): return s.is_adult())
	var max_age := float(Data.bal("fertile_max_age", 34.0))
	for m in adults:
		if m.sex != "f" or m.age > max_age:
			continue
		for f in adults:
			if f.sex == "m" and f.age <= max_age + 8.0 and not related(m.id, f.id):
				possible = true
				if time_days >= m.birth_cooldown_until and m.hunger >= 45.0 and f.hunger >= 45.0:
					couples.append([m, f])
	if not possible:
		_try_newcomer(adults)
		return
	if couples.is_empty():
		return
	if _rng.randf() > float(Data.bal("birth_chance")):
		return
	var pair: Array = couples[_rng.randi() % couples.size()]
	var mother = pair[0]
	var father = pair[1]
	mother.birth_cooldown_until = time_days + float(Data.bal("birth_cooldown"))
	var child = world.spawn_child(mother, father)
	stats.births += 1
	notify("%s ist geboren! Eltern: %s und %s." % [child.display_name, mother.display_name, father.display_name], "herz")


## Ohne passendes Paar wird gelegentlich ein Schiffbrüchiger angespült.
func _try_newcomer(adults: Array) -> void:
	if _rng.randf() > float(Data.bal("newcomer_chance", 0.06)):
		return
	var women := adults.filter(func(s): return s.sex == "f").size()
	var men := adults.size() - women
	var sex := "m" if men < women else ("f" if women < men else ("f" if _rng.randf() < 0.5 else "m"))
	var s = world.spawn_newcomer(sex)
	if s:
		notify("%s ist an den Strand gespült worden und schließt sich euch an!" % s.display_name, "person")


## Eltern, Geschwister, Großeltern und Kinder bekommen keinen Nachwuchs miteinander.
func related(a: int, b: int) -> bool:
	var pa: Array = lineage.get(a, [])
	var pb: Array = lineage.get(b, [])
	if a in pb or b in pa:
		return true
	for p in pa:
		if p in pb:
			return true
		var gp: Array = lineage.get(p, [])
		if b in gp:
			return true
	for p in pb:
		if a in lineage.get(p, []):
			return true
	return false


func register_lineage(sid: int, parents: Array) -> void:
	lineage[sid] = parents.map(func(x): return int(x))


func on_settler_died(s, reason: String) -> void:
	stats.deaths += 1
	var text := "%s ist %s." % [s.display_name, reason]
	notify(text, "abriss")
	if selected == s:
		select(null)
	population_changed.emit()
	if population() == 0:
		is_over = true
		set_speed(0)
		delete_save()
		game_over.emit()


func on_population_changed() -> void:
	stats.max_pop = max(stats.max_pop, population())
	population_changed.emit()


# ---------------------------------------------------------------- Speichern
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	if world == null or is_over:
		return
	var data := {
		"version": SAVE_VERSION,
		"seed": seed_value,
		"time_days": time_days,
		"stock": stock,
		"next_id": next_id,
		"stats": stats,
		"lineage": lineage,
		"world": world.serialize(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func load_save() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary) or int(d.get("version", 0)) != SAVE_VERSION:
		return {}
	return d


func apply_save_header(d: Dictionary) -> void:
	seed_value = int(d.seed)
	time_days = float(d.time_days)
	stock = {}
	for id in Data.resources:
		stock[id] = int(d.stock.get(id, 0))
	next_id = int(d.next_id)
	stats = d.get("stats", stats)
	lineage = {}
	var lin: Dictionary = d.get("lineage", {})
	for k in lin:
		register_lineage(int(k), lin[k])
	is_over = false
	selected = null
	_last_day = day()
	set_speed(1)


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()
