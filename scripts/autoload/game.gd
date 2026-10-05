extends Node
## Globaler Spielzustand: Zeit, Vorraete, Bevoelkerung, Speichern/Laden.
## Die Welt (World) haelt die Entitaeten; Game kennt sie ueber `world`.

signal stock_changed
signal population_changed
signal notified(text: String, icon: String, cat: String)
signal day_started(day: int)
signal selection_changed(obj)
signal speed_changed(speed: int)
signal game_over
signal research_changed
## Spieler hat etwas getan (fuer die Einfuehrung), z. B. ("job", "holzfaeller")
signal player_action(kind: String, what: String)

const LIVE_SAVE_PATH := "user://savegame.json"
## Die Testversion (Webadresse mit /test/) hat einen eigenen Spielstand. Beim ersten Start
## übernimmt sie eine Kopie des normalen Spielstands; der normale bleibt unberührt.
var SAVE_PATH := LIVE_SAVE_PATH
var is_test_build := false
## Fuenf Spielstaende: Platz 1 ist die bisherige Datei, die anderen haengen _2 .. _5 an.
## Der aktive Platz steht in user://settings.cfg [game] slot (Testversion: slot_test).
const SLOTS := 5
var slot := 1
var _slot_base := LIVE_SAVE_PATH
## Nach dem Neuladen der Seite (Spielstand wechseln): "continue" oder "new" statt Titelbild
var autostart := ""
const SAVE_VERSION := 3

var world = null  # aktive (sichtbare) Insel, siehe Sea fuer alle Inseln
var seed_value: int = 0
var time_days: float = 0.25  # Start am Morgen von Tag 1
var speed: int = 1
## Nur fuer alte Spielstaende (Version 1 und 2): gemeinsames Lager und Hoechstmengen.
## Seit Version 3 hat jede Insel ihr eigenes Lager (World.stock, World.store_limits).
var stock: Dictionary = {}
var store_limits: Dictionary = {}
var next_id: int = 1
var stats: Dictionary = {"births": 0, "deaths": 0, "max_pop": 0}
var selected = null
var is_over: bool = false
var lineage: Dictionary = {}  # Siedler-ID -> [Eltern-IDs], auch fuer Verstorbene
## Forschung: aktuelles Ziel, Fortschritt je Forschung, erforschte und bezahlte Forschungen
var research: Dictionary = {"current": "", "progress": {}, "done": [], "paid": []}
## Einfuehrung und Ziele: Schritt der Einfuehrung (tut), Index des Ziels (ms)
var goals: Dictionary = {"tut": 0, "ms": 0}
var eaten: Dictionary = {}  # gegessene Speisen seit Spielbeginn (fuer Statistik und Tests)
var effects: Dictionary = {}  # Summe aller Forschungs-Effekte, z. B. {"build": 0.2}

var _birth_timer: float = 0.0
var _autosave_timer: float = 0.0
var _last_day: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_detect_test_build()
	_load_slot()
	_load_notify_settings()


func _detect_test_build() -> void:
	var path := ""
	if OS.has_feature("web"):
		path = str(JavaScriptBridge.eval("window.location.pathname", true))
	if "--testbuild" in OS.get_cmdline_user_args():
		path = "/test/"
	if not "/test" in path:  # /test/ und /test-en/
		return
	is_test_build = true
	SAVE_PATH = "user://savegame_test.json"
	if not FileAccess.file_exists(SAVE_PATH) and FileAccess.file_exists(LIVE_SAVE_PATH):
		DirAccess.copy_absolute(LIVE_SAVE_PATH, SAVE_PATH)


func reset_state(new_seed: int) -> void:
	seed_value = new_seed
	time_days = 0.25
	stock = {}
	store_limits = {}
	next_id = 1
	stats = {"births": 0, "deaths": 0, "max_pop": 0}
	lineage = {}
	research = {"current": "", "progress": {}, "done": [], "paid": []}
	goals = {"tut": 0, "ms": 0}
	Sea.reset(new_seed)
	_recompute_effects()
	selected = null
	is_over = false
	_last_day = day()
	set_speed(1)
	research_changed.emit()


func new_id() -> int:
	next_id += 1
	return next_id - 1


# ---------------------------------------------------------------- Zeit
func day() -> int:
	return int(floor(time_days)) + 1


func time_of_day() -> float:
	return fposmod(time_days, 1.0)


func is_night() -> bool:
	# Die Nacht ist im Sommer kurz und im Winter lang (Seasons)
	var t := time_of_day()
	return t >= Seasons.night_start() or t < Seasons.night_end()


func clock_text() -> String:
	var minutes := int(time_of_day() * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func set_speed(s: int) -> void:
	speed = clamp(s, 0, 3)
	Engine.time_scale = float(speed)
	speed_changed.emit(speed)


var _ai_next := 0.0


func _process(delta: float) -> void:
	if world == null or is_over:
		return
	# delta ist bereits mit Engine.time_scale skaliert
	if speed > 0:
		# Naechte vergehen schneller, damit das Warten nicht langweilt
		var mult := float(Data.bal("night_speedup", 1.0)) if is_night() else 1.0
		time_days += delta * mult / float(Data.bal("day_length"))
		if day() != _last_day:
			_last_day = day()
			day_started.emit(_last_day)
			notify(tr("Tag %d beginnt.") % _last_day, "sonne")
		# KI-Steuerung (KI-Zentrum): freie Siedler auf fehlende Berufe verteilen
		if time_days >= _ai_next:
			_ai_next = time_days + 0.25
			if eff_add("ai_jobs") > 0.0:
				for w in Sea.all_worlds():
					AiJobs.tick(w)
		# Geschichten am Lagerfeuer: ein kleines bisschen Forschung kommt immer voran
		add_research(float(Data.bal("passive_research_per_day", 0.0)) * delta * mult / float(Data.bal("day_length")), false)
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
## Lager haben Stauraum (`storage` in buildings.json), jede Ware hat eine Groesse
## (`size` in resources.json). Belegt ist Menge mal Groesse. Der Spieler kann je
## Ware eine Hoechstmenge festlegen (`store_limits`); diese Menge ist dann fuer die
## Ware reserviert. Waren ohne Grenze ("frei") teilen sich den restlichen Raum.
## Jede Insel hat ihr eigenes Lager (World.stock) und eigene Hoechstmengen
## (World.store_limits). Waren kommen nur per Schiff auf eine andere Insel.
## Ohne Angabe einer Insel `w` gilt die aktive Insel (Game.world).

func _isle(w):
	return w if w != null and is_instance_valid(w) else world


func _stock_of(w = null) -> Dictionary:
	var i = _isle(w)
	return i.stock if i != null else {}


func _limits_of(w = null) -> Dictionary:
	var i = _isle(w)
	return i.store_limits if i != null else {}


## Stauraum der Lager einer Insel.
func storage_volume(w = null) -> int:
	var i = _isle(w)
	var cap := int(Data.bal("base_storage"))
	if i:
		for b in i.buildings:
			if b.complete:
				cap += int(b.def.get("storage", 0))
	return int(cap * eff("storage"))


## Stauraum, den ein einzelnes Lagergebaeude beitraegt (mit Forschung).
func building_volume(def: Dictionary) -> int:
	return int(int(def.get("storage", 0)) * eff("storage"))


## Belegter Stauraum.
func used_volume(w = null) -> int:
	var st := _stock_of(w)
	var n := 0
	for id in st:
		n += int(st[id]) * Data.good_size(id)
	return n


## Hoechstmenge einer Ware oder -1 fuer "frei".
func limit_of(id: String, w = null) -> int:
	return int(_limits_of(w).get(id, -1))


## Raum, der fuer Waren mit fester Hoechstmenge reserviert ist (ohne `skip`).
func reserved_volume(w = null, skip: String = "") -> int:
	var lim := _limits_of(w)
	var n := 0
	for id in lim:
		if id != skip:
			n += max(int(lim[id]), amount(id, w)) * Data.good_size(id)
	return n


## Belegter Raum der Waren ohne Grenze (ohne `skip`).
func _free_used(w = null, skip: String = "") -> int:
	var st := _stock_of(w)
	var lim := _limits_of(w)
	var n := 0
	for id in st:
		if id != skip and not lim.has(id):
			n += int(st[id]) * Data.good_size(id)
	return n


## Wie viele Einheiten dieser Ware noch ins Lager passen.
func space_for(id: String, w = null) -> int:
	var size := Data.good_size(id)
	if size <= 0:
		return 1 << 30
	var total_free: int = storage_volume(w) - used_volume(w)
	var lim := limit_of(id, w)
	if lim >= 0:
		return max(0, min(lim - amount(id, w), total_free / size))
	var free: int = storage_volume(w) - reserved_volume(w) - _free_used(w)
	return max(0, min(free, total_free) / size)


## Groesste Hoechstmenge, die fuer diese Ware eingestellt werden kann.
func max_limit(id: String, w = null) -> int:
	var size := Data.good_size(id)
	if size <= 0:
		return 1 << 30
	var room: int = storage_volume(w) - reserved_volume(w, id) - _free_used(w, id)
	return max(0, room / size)


## Setzt die Hoechstmenge (-1 = frei). Gibt die tatsaechlich gesetzte Menge zurueck.
func set_limit(id: String, n: int, w = null) -> int:
	var lim := _limits_of(w)
	if n < 0:
		lim.erase(id)
	else:
		n = min(n, max_limit(id, w))
		lim[id] = n
	stock_changed.emit()
	return n


## Was ueber der Hoechstmenge liegt (z. B. nach dem Herabsetzen).
func excess(id: String, w = null) -> int:
	var lim := limit_of(id, w)
	return max(0, amount(id, w) - lim) if lim >= 0 else 0


## Wirft den Ueberschuss einer Ware weg; er ist dann verloren.
func discard_excess(id: String, w = null) -> int:
	var n := excess(id, w)
	if n > 0:
		take_stock(id, n, w)
	return n


## Wohnplaetze einer Insel (ohne Angabe: die aktive Insel).
func housing_capacity(w = null) -> int:
	if w == null:
		w = world
	var cap := 0
	if w:
		for b in w.buildings:
			if b.complete:
				cap += int(b.def.get("housing", 0))
	return cap


## Alle Siedler auf allen Inseln (ohne die auf See).
func population() -> int:
	var n := 0
	for w in Sea.all_worlds():
		n += w.settlers.size()
	return n


func total_food(w = null) -> int:
	var st := _stock_of(w)
	var n := 0
	for id in Data.food_ids():
		n += int(st.get(id, 0))
	return n


## Fuer wie viele Tage die Nahrung einer Insel alle Siedler satt macht: Menge mal Saettigung
## aller Nahrungsgueter, geteilt durch Siedler und den Tagesbedarf eines Erwachsenen (mit
## Jahreszeit und Kaelte). -1 ohne Siedler.
func food_days(w = null) -> float:
	var ww = w if w != null else world
	if ww == null or not is_instance_valid(ww) or ww.settlers.is_empty():
		return -1.0
	var st := _stock_of(w)
	var sat := 0.0
	for id in Data.food_ids():
		sat += float(st.get(id, 0)) * Data.food_satiety(id)
	var need := float(Data.bal("hunger_per_day")) * eff("hunger") * Seasons.hunger_mult(ww)
	return sat / (ww.settlers.size() * max(need, 0.01))


func amount(id: String, w = null) -> int:
	return int(_stock_of(w).get(id, 0))


## Menge einer Ware auf allen Inseln zusammen (fuer Ziele und Uebersichten).
func amount_all(id: String) -> int:
	var n := 0
	for i in Sea.all_worlds():
		n += int(i.stock.get(id, 0))
	return n


## Fuegt Vorrat hinzu, soweit Platz ist; gibt die eingelagerte Menge zurueck.
func add_stock(id: String, n: int, w = null) -> int:
	if _isle(w) == null:
		return 0
	var add: int = clamp(n, 0, space_for(id, w))
	_stock_of(w)[id] = amount(id, w) + add
	stock_changed.emit()
	return add


func take_stock(id: String, n: int, w = null) -> int:
	var take: int = min(n, amount(id, w))
	_stock_of(w)[id] = amount(id, w) - take
	stock_changed.emit()
	return take


func can_afford(cost: Dictionary, w = null) -> bool:
	for id in cost:
		if amount(id, w) < int(cost[id]):
			return false
	return true


var last_eaten: String = ""  # Sorte der letzten Mahlzeit (fuer Vitamine und Speiseplan)


## Nimmt eine Mahlzeit: liefert Naehrwert (0 wenn nichts da).
func eat_one(w = null) -> float:
	var id := eat_food(false, w)
	return Data.food_satiety(id) if id != "" else 0.0


## Nimmt eine Speise aus dem Lager der Insel w und liefert ihre ID ("" wenn nichts da ist).
## Mit prefer_vitamins wird die vitaminreichste Speise gewaehlt, sonst die saettigendste.
## Bei Gleichstand nimmt der Siedler die Sorte, von der am meisten da ist.
func eat_food(prefer_vitamins: bool, w = null) -> String:
	var best := ""
	var best_v := -INF
	for id in Data.food_ids():
		var n := amount(id, w)
		if n <= 0:
			continue
		var v := Data.food_vitamins(id) if prefer_vitamins else Data.food_satiety(id)
		v += n * 0.001
		if v > best_v:
			best_v = v
			best = id
	if best != "":
		take_stock(best, 1, w)
		eaten[best] = int(eaten.get(best, 0)) + 1
		last_eaten = best
	return best


## Kluge Speisenwahl: Der Siedler s waehlt aus dem Lager der Insel w die Speise, die seinen
## Bedarf (Saettigung bis eat_until, Vitamine bis vitamin_target) am besten deckt, ohne
## Saettigung zu verschwenden. Dazu zaehlen: was bald verdirbt zuerst, Abwechslung gegenueber
## den letzten Mahlzeiten, Vorrat im Lager und ob die Speise noch als Zutat gebraucht wird.
## Gibt die Sorte zurueck und nimmt sie aus dem Lager ("" wenn nichts da ist).
func choose_food(s, w = null) -> String:
	var deficit := maxf(1.0, float(Data.bal("eat_until")) - s.hunger)
	var vit_need := maxf(0.0, float(Data.bal("vitamin_target", 70.0)) - s.mind.vit)
	var vit_urgent := 1.0 if s.mind.vit < float(Data.ppl("vit_low", 30.0)) else 0.0
	var total := 0
	var ids := []
	for id in Data.food_ids():
		var n := amount(id, w)
		if n > 0:
			ids.append(id)
			total += n
	if ids.is_empty():
		return ""
	var needed := _ingredient_goods(w)
	var meals: Array = s.mind.meals
	var best := ""
	var best_score := -INF
	for id in ids:
		var sat := Data.food_satiety(id)
		var vit := Data.food_vitamins(id)
		var score := minf(sat, deficit) / deficit  # Bedarf gedeckt
		score -= float(Data.bal("eat_waste_weight", 0.6)) * maxf(0.0, sat - deficit) / deficit  # verschwendet
		if vit_need > 0.0:
			score += (0.8 + 0.8 * vit_urgent) * minf(vit, vit_need) / vit_need
		var recent := 0
		for m in meals:
			if m == id:
				recent += 1
		score += 0.3 * (1.0 - float(recent) / maxf(1.0, float(meals.size())))  # Abwechslung
		score += minf(0.5, Seasons.spoil_rate(id) * 15.0)  # bald verdorben
		score += 0.25 * float(amount(id, w)) / float(total)  # Vorrat
		if needed.has(id):
			score -= 0.2  # wird in einer Werkstatt noch gebraucht
		score += float(amount(id, w)) * 0.0001  # bei Gleichstand das, wovon mehr da ist
		if score > best_score:
			best_score = score
			best = id
	take_stock(best, 1, w)
	eaten[best] = int(eaten.get(best, 0)) + 1
	last_eaten = best
	return best


## Waren, die eine fertige Werkstatt der Insel als Zutat braucht.
func _ingredient_goods(w) -> Dictionary:
	var out := {}
	var world_w = w if w != null else world
	if world_w == null:
		return out
	for b in world_w.buildings:
		if b.complete:
			for id in b.prod_def().get("inputs", {}):
				out[id] = true
	return out


## Anzahl der Nahrungssorten, die gerade im Lager sind.
func food_variety(w = null) -> int:
	var n := 0
	for id in Data.food_ids():
		if amount(id, w) > 0:
			n += 1
	return n


## Meldungsarten: jede laesst sich im Menue unter "Meldungen" abschalten.
const NOTIFY_CATS := {"tag": "Tag und Jahreszeit", "siedler": "Siedler und Nachwuchs",
	"gesundheit": "Krankheiten", "tod": "Todesfälle und verlorene Inseln", "bauen": "Bauen",
	"lager": "Lager, Vorräte und Winter", "forschung": "Forschung und Zeitalter", "see": "Seefahrt",
	"tiere": "Tiere und Jagd", "ki": "KI-Steuerung"}
## Art einer Meldung nach ihrem Symbol, wenn der Aufruf keine Art nennt
const NOTIFY_ICON_CAT := {"": "tag", "sonne": "tag", "herz": "siedler", "person": "siedler",
	"abriss": "tod", "hammer": "bauen", "haus": "lager", "holz": "lager", "weizen": "lager",
	"wissen": "forschung", "zeitalter": "forschung", "boot": "see", "anker": "see", "kompass": "see",
	"schild": "tiere", "fleisch": "tiere", "ki": "ki"}
var notify_off: Dictionary = {}  # Art -> true, wenn abgeschaltet (user://settings.cfg [notify])
var goal_card_on: bool = true


func notify(text: String, icon: String = "", cat: String = "") -> void:
	if cat == "":
		cat = NOTIFY_ICON_CAT.get(icon, "tag")
	if notify_off.get(cat, false):
		return
	notified.emit(text, icon, cat)


## Meldung von einer Insel: bei mehreren Inseln steht der Inselname davor.
func notify_at(w, text: String, icon: String = "", cat: String = "") -> void:
	if w and w != world and Sea.worlds.size() > 1:
		text = "%s: %s" % [Sea.island_name(w), text]
	notify(text, icon, cat)


func _load_notify_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") != OK:
		return
	for c in NOTIFY_CATS:
		notify_off[c] = not bool(cf.get_value("notify", c, true))
	goal_card_on = bool(cf.get_value("notify", "goal_card", true))


func set_notify(cat: String, on: bool) -> void:
	if cat == "goal_card":
		goal_card_on = on
	else:
		notify_off[cat] = not on
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	cf.set_value("notify", cat, on)
	cf.save("user://settings.cfg")


func select(obj) -> void:
	selected = obj
	selection_changed.emit(obj)


# ---------------------------------------------------------------- Nachwuchs
func _try_birth() -> void:
	if total_food() < population() * int(Data.bal("birth_food_per_person")):
		return
	for w in Sea.all_worlds():
		if w.settlers.size() < housing_capacity(w):
			_try_birth_on(w)


func _try_birth_on(w) -> void:
	var couples := []
	var possible := false
	var adults: Array = w.settlers.filter(func(s): return s.is_adult())
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
		_try_newcomer(w, adults)
		return
	if couples.is_empty():
		return
	var pair: Array = couples[_rng.randi() % couples.size()]
	var mother = pair[0]
	var father = pair[1]
	var chance := float(Data.bal("birth_chance"))
	# Abwechslungsreiche Kost macht Lust auf Familie
	if food_variety() >= int(Data.bal("variety_min", 3)):
		chance *= float(Data.bal("variety_birth_bonus", 1.0))
	chance *= eff("birth")
	# In besseren Haeusern kommen mehr Kinder zur Welt
	chance *= home_birth_bonus(w, mother)
	# Gut gelaunte Paare bekommen eher Kinder, kranke kaum
	chance *= sqrt(mother.mind.birth_factor() * father.mind.birth_factor())
	if mother.mind.sick != "":
		chance *= 0.2
	if _rng.randf() > chance:
		return
	mother.birth_cooldown_until = time_days + float(Data.bal("birth_cooldown"))
	var child = w.spawn_child(mother, father)
	mother.mind.on_child_born()
	father.mind.on_child_born()
	stats.births += 1
	Sound.play_on("geburt", w)
	notify_at(w, tr("%s ist geboren! Eltern: %s und %s.") % [child.display_name, mother.display_name, father.display_name], "herz")


## Geburtenfaktor des Hauses, in dem die Mutter wohnt (Hütte 1, Holzhaus 1.4, Steinhaus 1.8).
func home_birth_bonus(w, mother) -> float:
	var home = w.building_by_id(mother.home_id)
	if home and home.complete:
		return float(home.def.get("birth_bonus", 1.0))
	return 1.0


## Ohne passendes Paar wird gelegentlich ein Schiffbrüchiger angespült.
func _try_newcomer(w, adults: Array) -> void:
	if _rng.randf() > float(Data.bal("newcomer_chance", 0.06)):
		return
	var women := adults.filter(func(s): return s.sex == "f").size()
	var men := adults.size() - women
	var sex := "m" if men < women else ("f" if women < men else ("f" if _rng.randf() < 0.5 else "m"))
	var s = w.spawn_newcomer(sex)
	if s:
		notify_at(w, tr("%s ist an den Strand gespült worden und schließt sich euch an!") % s.display_name, "person")
		Sound.play_on("glocke", w)


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
	var text := tr("%s ist %s.") % [s.display_name, reason]
	notify_at(s.world, text, "abriss")
	Sound.play_on("tod", s.world)
	if selected == s:
		select(null)
	population_changed.emit()
	if s.world and s.world.settlers.is_empty():
		Sea.island_lost(s.world)
	if Sea.total_people() == 0:
		is_over = true
		set_speed(0)
		delete_save()
		game_over.emit()


func on_population_changed() -> void:
	stats.max_pop = max(stats.max_pop, population())
	population_changed.emit()


# ---------------------------------------------------------------- Forschung
## Effekt als Faktor (1 + Summe), z. B. eff("build") = 1.6
func eff(key: String) -> float:
	return 1.0 + float(effects.get(key, 0.0))


## Effekt als Zuschlag, z. B. eff_add("carry") = 5
func eff_add(key: String) -> float:
	return float(effects.get(key, 0.0))


func _recompute_effects() -> void:
	effects = {}
	for t in research.done:
		var e: Dictionary = Data.techs.get(t, {}).get("effects", {})
		for k in e:
			effects[k] = float(effects.get(k, 0.0)) + float(e[k])
	# Besondere Gebaeude (Leuchtturm, Denkmal) wirken einmal je Art auf alle Inseln
	var seen := {}
	for w in Sea.all_worlds():
		for b in w.buildings:
			if b.complete and b.def.has("effects") and not seen.has(b.type):
				seen[b.type] = true
				for k in b.def.effects:
					effects[k] = float(effects.get(k, 0.0)) + float(b.def.effects[k])


func refresh_effects() -> void:
	_recompute_effects()
	stock_changed.emit()


func is_researched(t: String) -> bool:
	return t == "" or t in research.done


## "done", "current", "available", "locked" oder "soon"
func tech_state(t: String) -> String:
	if t in research.done:
		return "done"
	var def: Dictionary = Data.techs.get(t, {})
	if def.get("soon", false):
		return "soon"
	if research.current == t:
		return "current"
	for r in def.get("requires", []):
		if not r in research.done:
			return "locked"
	return "available"


func is_unlocked(building_type: String) -> bool:
	return is_researched(Data.buildings.get(building_type, {}).get("requires", ""))


func tech_progress(t: String) -> float:
	return float(research.progress.get(t, 0.0))


func tech_points(t: String) -> float:
	return float(Data.techs.get(t, {}).get("points", 1)) * float(Data.bal("research_cost_factor", 1.0))


## Startet (oder wechselt zu) einer Forschung. Die Kosten werden beim ersten Start bezahlt.
## Liefert "" bei Erfolg, sonst den Grund.
func start_research(t: String) -> String:
	var st := tech_state(t)
	if st == "current":
		return ""
	if st != "available":
		return tr("Diese Forschung ist noch nicht möglich.")
	if not t in research.paid:
		var cost: Dictionary = Data.techs[t].get("cost", {})
		if not can_afford(cost):
			var miss := []
			for id in cost:
				if amount(id) < int(cost[id]):
					miss.append("%d %s" % [int(cost[id]) - amount(id), Data.resource_name(id)])
			var why := tr("Es fehlt noch: ") + ", ".join(miss)
			if amount("felle") < int(cost.get("felle", 0)):
				why += tr(". Felle bringen Jäger, wenn sie wilde Tiere erlegen.")
			return why
		for id in cost:
			take_stock(id, int(cost[id]))
		research.paid.append(t)
	research.current = t
	research_changed.emit()
	return ""


func has_research_goal() -> bool:
	return research.current != ""


## Forschungspunkte gutschreiben (von Forschern oder passiv).
func add_research(points: float, apply_bonus: bool = true) -> void:
	var t: String = research.current
	if t == "" or points <= 0.0:
		return
	if apply_bonus:
		points *= eff("research")
	research.progress[t] = tech_progress(t) + points
	if tech_progress(t) >= tech_points(t):
		_finish_research(t)


## Zeitalter: das spaeteste, aus dem schon etwas erforscht ist (0 = Steinzeit).
func current_age() -> int:
	var a := 0
	for t in research.done:
		if Data.techs.has(t):
			a = maxi(a, Data.age_of_tier(int(Data.techs[t].tier)))
	return a


func _finish_research(t: String) -> void:
	var age_before := current_age()
	research.progress.erase(t)
	research.done.append(t)
	research.current = ""
	_recompute_effects()
	var unlocks := Data.tech_unlocks(t).map(func(b): return Data.buildings[b].name)
	var text := tr("Erforscht: %s!") % Data.techs[t].name
	if not unlocks.is_empty():
		text += tr(" Neu zu bauen: ") + ", ".join(unlocks) + "."
	notify(text, "wissen")
	var age := current_age()
	if age > age_before:
		notify(tr("Ein neues Zeitalter beginnt: %s! %s") % [Data.age_name(age), Data.ages[age].get("desc", "")], "zeitalter")
	Sound.play("forschung")
	research_changed.emit()
	stock_changed.emit()


# ---------------------------------------------------------------- Spielstaende
func slot_path(n: int) -> String:
	return _slot_base if n <= 1 else _slot_base.replace(".json", "_%d.json" % n)


func slot_exists(n: int) -> bool:
	return FileAccess.file_exists(slot_path(n))


func _slot_key() -> String:
	return "slot_test" if is_test_build else "slot"


func _load_slot() -> void:
	_slot_base = SAVE_PATH
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		slot = clampi(int(cf.get_value("game", _slot_key(), 1)), 1, SLOTS)
		autostart = str(cf.get_value("game", "autostart", ""))
		if autostart != "":
			cf.erase_section_key("game", "autostart")
			cf.save("user://settings.cfg")
	SAVE_PATH = slot_path(slot)


## Kurzbeschreibung eines Spielstands, beim Speichern in settings.cfg [slots] abgelegt
func slot_info(n: int) -> String:
	if not slot_exists(n):
		return ""
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	var raw = cf.get_value("slots", slot_path(n).get_file(), [])
	if not (raw is Array) or raw.size() < 4:
		return ""
	var dt := Time.get_datetime_dict_from_unix_time(int(raw[3]) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	var isl: int = int(raw[2])
	return tr("Tag %d, %d Siedler, %s, gespeichert %02d.%02d. %02d:%02d") % [int(raw[0]), int(raw[1]),
		tr("1 Insel") if isl == 1 else tr("%d Inseln") % isl, dt.day, dt.month, dt.hour, dt.minute]


func _write_slot_info() -> void:
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	cf.set_value("slots", SAVE_PATH.get_file(), [day(), population(), Sea.worlds.size(), int(Time.get_unix_time_from_system())])
	cf.save("user://settings.cfg")


## Wechselt den Spielstand. mode: "continue" laedt ihn, "new" beginnt dort ein neues Spiel,
## "" merkt sich nur den Platz (nach "Hier speichern"). Laden und Neu laden die Seite neu.
func switch_slot(n: int, mode: String) -> void:
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	cf.set_value("game", _slot_key(), n)
	if mode != "":
		cf.set_value("game", "autostart", mode)
	cf.save("user://settings.cfg")
	slot = n
	SAVE_PATH = slot_path(n)
	if mode == "":
		return
	if mode == "new" and slot_exists(n):
		DirAccess.remove_absolute(slot_path(n))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.reload()")
	else:
		OS.set_restart_on_exit(true)
		get_tree().quit()


## Speichert das laufende Spiel in einen anderen Platz und spielt dort weiter.
func save_to_slot(n: int) -> void:
	switch_slot(n, "")
	save_game()


func delete_slot(n: int) -> void:
	if n != slot and slot_exists(n):
		DirAccess.remove_absolute(slot_path(n))


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
		"next_id": next_id,
		"stats": stats,
		"lineage": lineage,
		"research": research,
		"goals": goals,
	}
	data.merge(Sea.serialize())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
		_write_slot_info()


func load_save() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	# Version 1 (eine Insel) wird beim Laden in das neue Format uebernommen
	if not (d is Dictionary) or not int(d.get("version", 0)) in [1, 2, SAVE_VERSION]:
		return {}
	return d


func apply_save_header(d: Dictionary) -> void:
	seed_value = int(d.seed)
	time_days = float(d.time_days)
	# Bis Version 2 gab es ein gemeinsames Lager; Sea.build_from_save gibt es der Heimatinsel
	stock = {}
	var old_st: Dictionary = d.get("stock", {})
	for id in old_st:
		if Data.resources.has(id):
			stock[id] = int(old_st[id])
	store_limits = {}
	var sl: Dictionary = d.get("store_limits", {})
	for id in sl:
		if Data.resources.has(id):
			store_limits[id] = int(sl[id])
	next_id = int(d.next_id)
	stats = d.get("stats", stats)
	lineage = {}
	var lin: Dictionary = d.get("lineage", {})
	for k in lin:
		register_lineage(int(k), lin[k])
	var r: Dictionary = d.get("research", {})
	research = {
		"current": str(r.get("current", "")),
		"progress": r.get("progress", {}),
		"done": Array(r.get("done", [])).filter(func(x): return Data.techs.has(x)),
		"paid": Array(r.get("paid", [])),
	}
	if not Data.techs.has(research.current):
		research.current = ""
	# Aeltere Spielstaende kennen keine Ziele: Einfuehrung ueberspringen, erreichte Ziele nachholen
	var g = d.get("goals", null)
	if g is Dictionary:
		goals = {"tut": int(g.get("tut", 0)), "ms": int(g.get("ms", 0)), "hide": str(g.get("hide", ""))}
	else:
		goals = {"tut": 999, "ms": 0, "catchup": true}
	_recompute_effects()
	research_changed.emit()
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
