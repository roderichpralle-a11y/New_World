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
## Neues Spiel: reset_state ist fertig (die neue Welt entsteht erst danach). Systeme setzen
## hier ihren Zustand zurueck.
signal state_reset
## Beim Speichern, kurz vor dem Schreiben: Systeme legen ihre eigenen Schluessel oben in `data` ab.
signal state_save(data: Dictionary)
## Nach dem Laden (alle Welten existieren schon, siehe after_load). old_rules < RULES heisst:
## der Spielstand stammt von vor den neuen Regeln (Systeme stellen dann ihre Startwerte ein und
## haengen eine Zeile an rules_lines an).
signal state_load(data: Dictionary, old_rules: int)
## Ein Siedler ist gestorben. cause: "starve" (verhungert), "sick", "old", "killed" oder "".
signal settler_died(settler, cause: String)

const LIVE_SAVE_PATH := "user://savegame.json"
## Die Testversion (Webadresse mit /test/) hat einen eigenen Spielstand. Beim ersten Start
## übernimmt sie eine Kopie des normalen Spielstands; der normale bleibt unberührt.
var SAVE_PATH := LIVE_SAVE_PATH
var is_test_build := false
## "test" (/test/) oder "neu" (/neu/, Umbau "Mehr Herausforderung"); leer im normalen Spiel
var build_tag := ""
## Fuenf Spielstaende: Platz 1 ist die bisherige Datei, die anderen haengen _2 .. _5 an.
## Der aktive Platz steht in user://settings.cfg [game] slot (Testversion: slot_test).
const SLOTS := 5
var slot := 1
var _slot_base := LIVE_SAVE_PATH
## Nach dem Neuladen der Seite (Spielstand wechseln): "continue" oder "new" statt Titelbild
var autostart := ""
## Vor dem Neuladen der Seite: nichts mehr speichern (sonst landet das laufende Spiel im neuen Platz)
var save_locked := false
const SAVE_VERSION := 3
## Regelstand ("Mehr Herausforderung" = 1). SAVE_VERSION bleibt 3 (alte, noch im Browser
## zwischengespeicherte Versionen lehnen unbekannte Versionen ab und wuerden Spielstaende loeschen).
## Spielstaende ohne "rules" (= 0) bekommen die neuen Regeln ab dem Laden.
const RULES := 1
var rules: int = RULES
var rules_day: float = 0.0  # time_days, ab dem die Regeln fuer diesen Spielstand gelten
var rules_old: int = RULES  # Regelstand des geladenen Spielstands (vor dem Hochsetzen)
## Zeilen fuer das Fenster "Neue Regeln": jedes System haengt in seinem state_load-Handler
## (bei old_rules < 1) eine kurze Zeile in einfachem Deutsch an.
var rules_lines: Array = []
var rules_due := false  # Fenster Neue Regeln noch nicht gezeigt
## Autoload-Systeme melden sich in _ready an (register_system). main.gd ruft im Selbsttest
## autotest_setup(args, main) und autotest_report() auf, wenn es sie gibt.
var systems: Array = []
## Sicherung fuer aeltere Versionen (z. B. eine im Browser zwischengespeicherte alte Web-App):
## Die behalten beim Speichern nur ihre eigenen Schluessel (OLD_SAVE_KEYS), die Inseldaten in
## islands[0] aber unveraendert. Dort liegt deshalb unter "v2" eine Kopie der neuen Schluessel,
## der Forschung und der Gebaeude und Waren, die alte Versionen nicht kennen (siehe _store_backup).
const OLD_SAVE_KEYS := ["version", "seed", "time_days", "next_id", "stats", "lineage", "research", "goals",
	"islands", "active", "voyages", "ships", "next_ship", "stock", "store_limits", "world"]
const V2_BUILDINGS := ["tafelmacherei"]
const V2_GOODS := ["tontafel", "gewuerze"]
var _v2_restore: Dictionary = {}  # Insel-ID (Text) -> {"b": Gebaeude, "s": Waren} zum Zurueckholen
var _notes: Array = []  # Meldungen, bevor das Spiel sichtbar laeuft (queue_note)
var notes_live := false

var world = null  # aktive (sichtbare) Insel, siehe Sea fuer alle Inseln
var seed_value: int = 0
var time_days: float = 0.25  # Start am Morgen von Tag 1
var speed: int = 1
## Nur fuer alte Spielstaende (Version 1 und 2): gemeinsames Lager und Hoechstmengen.
## Seit Version 3 hat jede Insel ihr eigenes Lager (World.stock, World.store_limits).
var stock: Dictionary = {}
var store_limits: Dictionary = {}
var next_id: int = 1
## Statistik. Neuere Schluessel immer mit stats.get(k, 0) lesen (alte Spielstaende haben sie nicht):
## starved = Hungertote, starve_day = time_days des letzten Hungertods (alte Spielstaende: rules_day).
var stats: Dictionary = {"births": 0, "deaths": 0, "max_pop": 0, "starved": 0, "starve_day": 0.0}
var selected = null
var is_over: bool = false
var lineage: Dictionary = {}  # Siedler-ID -> [Eltern-IDs], auch fuer Verstorbene
## Forschung: aktuelles Ziel, Fortschritt je Forschung, erforschte und bezahlte Forschungen
var research: Dictionary = {"current": "", "progress": {}, "done": [], "paid": []}
## Einfuehrung und Ziele: Schritt der Einfuehrung (tut), Index des Ziels (ms)
var goals: Dictionary = {"tut": 0, "ms": 0, "tv": 2}
var eaten: Dictionary = {}  # gegessene Speisen seit Spielbeginn (fuer Statistik und Tests)
var effects: Dictionary = {}  # Summe aller Forschungs-Effekte, z. B. {"build": 0.2}
var reward_wait: Dictionary = {}  # Belohnungen ohne Lagerplatz, siehe _wait_goods
var _wait_next := 0.0

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
	if "--neubuild" in OS.get_cmdline_user_args():
		path = "/neu/"
	if "/neu/" in path:  # Umbau "Mehr Herausforderung": eigener Spielstand
		build_tag = "neu"
	elif "/test" in path:  # /test/ und /test-en/
		build_tag = "test"
	else:
		return
	is_test_build = true
	SAVE_PATH = "user://savegame_%s.json" % build_tag
	# Kopie des Spiels, das gerade im normalen Spiel aktiv ist ([game] slot), sonst Platz 1
	var live := LIVE_SAVE_PATH
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		var n := clampi(int(cf.get_value("game", "slot", 1)), 1, SLOTS)
		var p := LIVE_SAVE_PATH if n <= 1 else LIVE_SAVE_PATH.replace(".json", "_%d.json" % n)
		if FileAccess.file_exists(p):
			live = p
	if not FileAccess.file_exists(SAVE_PATH) and FileAccess.file_exists(live):
		DirAccess.copy_absolute(live, SAVE_PATH)


func reset_state(new_seed: int) -> void:
	seed_value = new_seed
	time_days = 0.25
	stock = {}
	store_limits = {}
	next_id = 1
	stats = {"births": 0, "deaths": 0, "max_pop": 0, "starved": 0, "starve_day": time_days}
	lineage = {}
	research = {"current": "", "progress": {}, "done": [], "paid": []}
	goals = {"tut": 0, "ms": 0, "tv": 2}
	rules = RULES
	rules_old = RULES
	rules_day = time_days
	rules_lines = []
	rules_due = false
	reward_wait = {}
	_notes.clear()
	Sea.reset(new_seed)
	_recompute_effects()
	selected = null
	is_over = false
	_last_day = day()
	set_speed(1)
	research_changed.emit()
	state_reset.emit()


## Ein Autoload-System meldet sich an (in seinem _ready).
func register_system(s: Node) -> void:
	if not s in systems:
		systems.append(s)


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
		if time_days >= _wait_next:
			_wait_next = time_days + 0.25
			if not reward_wait.is_empty():
				_deliver_waiting()
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
	if vit_need <= 0.0:
		ids = durable_first(ids)  # josh: erst das haltbare Essen; wer Vitamine braucht, wählt frei
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


## Haltbares Essen zuerst (josh 2026-10-09): ist haltbare Nahrung da (nicht in seasons.json
## `perishable`), wählt choose_food nur unter ihr; das andere erst, wenn keine haltbare mehr da ist.
## Ausnahme: wer unter `vitamin_target` Vitamine hat, wählt aus allem (sonst äße eine Insel mit
## Bäckerei nur Brot und bekäme Skorbut).
## Rohware, die eine Werkstatt weiterverarbeitet (Getreide für Mühle und Hühnerhof), zählt nicht als
## haltbares Essen, sonst äßen die Siedler das Korn roh, bevor es zu Brot wird.
func durable_first(ids: Array) -> Array:
	if _raw_food.is_empty():
		for t in Data.buildings:
			for id in Data.buildings[t].get("production", {}).get("inputs", {}):
				_raw_food[id] = true
	var perish: Array = Seasons.cfg.get("perishable", [])
	var keep := ids.filter(func(id): return not id in perish and not _raw_food.has(id))
	return keep if not keep.is_empty() else ids


var _raw_food: Dictionary = {}  # Waren, die eine Werkstatt weiterverarbeitet (durable_first)


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
	"tiere": "Tiere und Jagd", "ereignis": "Ereignisse und Händler", "ki": "KI-Steuerung",
	"ziel": "Meldungen zu Aufträgen"}
## Art einer Meldung nach ihrem Symbol, wenn der Aufruf keine Art nennt
const NOTIFY_ICON_CAT := {"": "tag", "sonne": "tag", "herz": "siedler", "person": "siedler",
	"abriss": "tod", "hammer": "bauen", "haus": "lager", "holz": "lager", "weizen": "lager",
	"wissen": "forschung", "zeitalter": "forschung", "boot": "see", "anker": "see", "kompass": "see",
	"schild": "tiere", "fleisch": "tiere", "ki": "ki", "ereignis": "ereignis", "haendler": "ereignis",
	"feuer": "ereignis", "ratte": "ereignis", "ziel": "ziel"}
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


## Meldung, die auch beim Laden nicht verloren geht: solange das Spiel noch nicht sichtbar laeuft
## (Laden, Titelbild), wird sie gemerkt und mit flush_notes() gezeigt, danach wie notify().
func queue_note(text: String, icon: String = "", cat: String = "") -> void:
	if notes_live:
		notify(text, icon, cat)
	else:
		_notes.append([text, icon, cat])


## Zeigt die gemerkten Meldungen (main.gd, sobald das Spiel startet oder weiterlaeuft).
func flush_notes() -> void:
	notes_live = true
	var list := _notes.duplicate()
	_notes.clear()
	for n in list:
		notify(n[0], n[1], n[2])


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
	# Jede Insel zaehlt ihr eigenes Essen
	for w in Sea.all_worlds():
		if w.settlers.size() < housing_capacity(w) and total_food(w) >= w.settlers.size() * int(Data.bal("birth_food_per_person")):
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
	if food_variety(w) >= int(Data.bal("variety_min", 3)):
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
		if not HouseNeeds.full_level(home):
			return 1.0  # Bedürfnisse des Hauses nicht erfüllt: kein Bonus
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


# ---------------------------------------------------------------- Belohnungen
## Gibt Waren auf Insel w; was dort keinen Platz hat, geht auf andere besiedelte Inseln mit Platz,
## der Rest ist verloren. Liefert [untergebracht, davon auf anderen Inseln].
func give_goods(w, id: String, n: int) -> Array:
	var home = _isle(w)
	var placed := 0
	var elsewhere := 0
	var where := {}  # andere Insel (Name) -> Menge
	if n <= 0 or not Data.resources.has(id):
		return [0, 0, where]
	if home != null:
		placed = add_stock(id, n, home)
	if placed < n:
		for o in Sea.all_worlds():
			if o == home:
				continue
			var k := add_stock(id, n - placed, o)
			if k > 0:
				placed += k
				elsewhere += k
				where[Sea.island_name(o)] = int(where.get(Sea.island_name(o), 0)) + k
			if placed >= n:
				break
	return [placed, elsewhere, where]


## Besiedelte Insel mit den meisten freien Wohnplaetzen (ohne `exclude`); bei Gleichstand die
## aktive, dann die Heimatinsel. null, wenn es keine gibt.
func immigrant_world(exclude = null):
	var best = null
	var best_free := -INF
	for w in Sea.all_worlds():
		if w == exclude or w.settlers.is_empty():
			continue
		var free := float(housing_capacity(w) - w.settlers.size())
		if w == world:
			free += 0.2
		if int(w.island_id) == 0:
			free += 0.1
		if free > best_free:
			best_free = free
			best = w
	return best


## Einwanderer: n Erwachsene ueber World.spawn_newcomer, abwechselnd Frau und Mann (zuerst das
## Geschlecht, das auf der Insel seltener ist), mit niemandem verwandt. Kann niemand auf w landen,
## kommen sie auf die besiedelte Insel mit den meisten freien Wohnplaetzen; wer gar nicht landen
## kann, wird zu 10 Brettern (opts.convert = false schaltet das ab). opts: talent (Faehigkeit),
## talent_val (Begabung, Standard 1,5 bis talent_max), skill (Stufe darin), hunger (Standard 80).
## Liefert die neuen Siedler. Meldet nichts (das macht der Aufrufer).
func spawn_immigrants(w, n: int, opts: Dictionary = {}) -> Array:
	var out := []
	if n <= 0:
		return out
	var o := opts.duplicate()
	if not o.has("hunger"):
		o["hunger"] = 80.0
	var target = w if w != null and is_instance_valid(w) and w in Sea.all_worlds() else null
	var order := []
	if target != null:
		order.append(target)
	var alt = immigrant_world(target)
	if alt != null:
		order.append(alt)
	for cand in order:
		var adults: Array = cand.settlers.filter(func(x): return x.is_adult())
		var women := adults.filter(func(x): return x.sex == "f").size()
		var men := adults.size() - women
		var first := "f" if women < men else ("m" if men < women else ("f" if _rng.randf() < 0.5 else "m"))
		var i := 0
		while out.size() < n:
			var sex := first if i % 2 == 0 else ("m" if first == "f" else "f")
			var s = cand.spawn_newcomer(sex, o)
			if s == null:
				break  # kein Strand erreichbar: naechste Insel
			out.append(s)
			i += 1
		if out.size() >= n:
			break
	var missing := n - out.size()
	if missing > 0 and o.get("convert", true):
		give_goods(target if target != null else (alt if alt != null else world), "bretter", 10 * missing)
	return out


## Belohnung auf Insel w: Waren-IDs -> Menge (Ueberlauf auf andere Inseln, der Rest wartet auf Platz:
## _wait_goods) und
## "settlers": n Einwanderer (spawn_immigrants mit `opts`; wer nicht landen kann, wird zu 10 Brettern).
## Liefert eine kurze Zusammenfassung fuer Meldungen, z. B. "2 Einwanderer, 10 Bretter".
func grant_reward(w, reward: Dictionary, opts: Dictionary = {}) -> String:
	var home = _isle(w)
	var parts := []
	var goods := {}
	for k in reward:
		var id := str(k)
		if id != "settlers" and Data.resources.has(id) and int(reward[k]) > 0:
			goods[id] = int(goods.get(id, 0)) + int(reward[k])
	var n := int(reward.get("settlers", 0))
	if n > 0:
		var o := opts.duplicate()
		o["convert"] = false
		var came := spawn_immigrants(home, n, o)
		if came.size() == 1:
			parts.append(tr("1 Einwanderer"))
		elif came.size() > 1:
			parts.append(tr("%d Einwanderer") % came.size())
		if came.size() < n:
			goods["bretter"] = int(goods.get("bretter", 0)) + 10 * (n - came.size())
	for id in goods:
		var want := int(goods[id])
		var r := give_goods(home, id, want)
		var notes := []
		var where: Dictionary = r[2]
		for isl in where:
			notes.append(tr("%d davon auf %s") % [int(where[isl]), isl])
		var rest := want - int(r[0])
		if rest > 0:
			_wait_goods(home, id, rest)
			notes.append(tr("%d warten auf Platz im Lager") % rest)
		parts.append("%d %s" % [want, Data.resource_name(id)] + (" (%s)" % ", ".join(notes) if not notes.is_empty() else ""))
	return ", ".join(parts)


## Belohnungen, die in keinem Lager Platz hatten, warten (reward_wait: Insel-ID als Text -> {Ware: Menge})
## und kommen ins Lager, sobald irgendwo Platz ist (zuerst auf ihrer Insel, siehe _deliver_waiting).
func _wait_goods(w, id: String, n: int) -> void:
	var key := str(w.island_id) if w != null else "0"
	var e: Dictionary = reward_wait.get(key, {})
	e[id] = int(e.get(id, 0)) + n
	reward_wait[key] = e


func waiting_total() -> int:
	var n := 0
	for k in reward_wait:
		for id in reward_wait[k]:
			n += int(reward_wait[k][id])
	return n


## Wartende Waren einlagern, aber nur so viel, dass ein Teil des Lagers (wait_free_share) frei bleibt:
## sonst haette die naechste Ernte keinen Platz.
func _deliver_waiting() -> void:
	var share := float(Data.bal("wait_free_share", 0.15))
	for key in reward_wait.keys():
		var home = Sea.worlds.get(int(key))
		if home == null:
			home = world
		var e: Dictionary = reward_wait[key]
		var got := {}
		var order: Array = Sea.all_worlds().filter(func(o): return o != home)
		if home != null:
			order.push_front(home)
		for id in e.keys():
			var size := maxi(1, Data.good_size(id))
			for o in order:
				var room := space_for(id, o) - int(share * float(storage_volume(o))) / size
				var k := add_stock(id, mini(int(e[id]), maxi(0, room)), o) if room > 0 else 0
				if k > 0:
					e[id] = int(e[id]) - k
					var l: Array = got.get(o, [])
					l.append("%d %s" % [k, Data.resource_name(id)])
					got[o] = l
				if int(e[id]) <= 0:
					break
			if int(e[id]) <= 0:
				e.erase(id)
		if e.is_empty():
			reward_wait.erase(key)
		for o in got:
			notify_at(o, tr("Wartende Waren sind jetzt im Lager: %s.") % ", ".join(got[o]), "hammer", "lager")


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


## cause: Schluessel der Todesart ("starve", "sick", "old", "killed"), reason: Anzeigetext.
func on_settler_died(s, reason: String, cause: String = "") -> void:
	stats.deaths += 1
	if cause == "starve":
		stats["starved"] = int(stats.get("starved", 0)) + 1
		stats["starve_day"] = time_days
	settler_died.emit(s, cause)
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
	Writing.clear_cache()  # Schreibwaren haengen davon ab, was freigeschaltet ist
	Exams.sync()  # direkt eingetragene Forschungen (Testhilfen) ziehen die Pruefungen nach
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
	Quests.add_boons(effects)  # dauerhafte Segen aus Auftraegen (mit Obergrenze)


func refresh_effects() -> void:
	_recompute_effects()
	stock_changed.emit()


func is_researched(t: String) -> bool:
	return t == "" or t in research.done


## "done", "current", "available", "locked", "exam" (wartet auf die Pruefung, Exams) oder "soon"
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
	if Exams.gates(t):
		return "exam"
	return "available"


func is_unlocked(building_type: String) -> bool:
	# Bauplan aus einem Auftrag: baubar auch ohne die Forschung
	return is_researched(Data.buildings.get(building_type, {}).get("requires", "")) or Quests.has_plan(building_type)


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
	if st == "exam":
		return tr("Erst die Prüfung für das Zeitalter %s bestehen.") % Data.age_name(Exams.passed + 1)
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


## Zeitalter (0 = Steinzeit) = Zahl der bestandenen Pruefungen (Exams). Ein neues Zeitalter beginnt
## erst mit der Pruefung (Exams.pass_exam meldet es).
func current_age() -> int:
	return Exams.current_age()


func _finish_research(t: String) -> void:
	research.progress.erase(t)
	research.done.append(t)
	research.current = ""
	_recompute_effects()
	var unlocks := Data.tech_unlocks(t).map(func(b): return Data.buildings[b].name)
	var text := tr("Erforscht: %s!") % Data.techs[t].name
	if not unlocks.is_empty():
		text += tr(" Neu zu bauen: ") + ", ".join(unlocks) + "."
	notify(text, "wissen")
	Sound.play("forschung")
	research_changed.emit()
	stock_changed.emit()


# ---------------------------------------------------------------- Spielstaende
func slot_path(n: int) -> String:
	return _slot_base if n <= 1 else _slot_base.replace(".json", "_%d.json" % n)


func slot_exists(n: int) -> bool:
	return FileAccess.file_exists(slot_path(n))


func _slot_key() -> String:
	return "slot_" + build_tag if is_test_build else "slot"


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
	if mode != "":
		save_locked = true
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


## Inhalt eines Spielstands als Text (zum Exportieren), "" wenn leer
func slot_text(n: int) -> String:
	if n == slot and world != null and not is_over:
		save_game()
	if not slot_exists(n):
		return ""
	return FileAccess.get_file_as_string(slot_path(n))


func slot_file_name(n: int) -> String:
	var info = []
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	info = cf.get_value("slots", slot_path(n).get_file(), [])
	var d: int = int(info[0]) if info is Array and info.size() > 0 else 0
	return "insel-siedler-spielstand-%d%s.json" % [n, ("-tag-%d" % d) if d > 0 else ""]


## Prueft einen importierten Text und legt ihn in Platz n ab. Gibt "" oder einen Fehlertext zurueck.
func import_slot(n: int, text: String) -> String:
	var d = JSON.parse_string(text)
	if not (d is Dictionary) or not int(d.get("version", 0)) in [1, 2, SAVE_VERSION] or not d.has("time_days"):
		return tr("Das ist kein Spielstand von Insel-Siedler.")
	var f := FileAccess.open(slot_path(n), FileAccess.WRITE)
	if f == null:
		return tr("Der Spielstand konnte nicht gespeichert werden.")
	f.store_string(text)
	f.close()
	# Kurzinfo fuer die Liste: Siedler und besiedelte Inseln zaehlen
	var pop := Array(d.get("settlers", [])).size()
	var settled := 0
	for isl in d.get("islands", []):
		if isl is Dictionary and isl.get("world") is Dictionary:
			var n_here := Array(isl.world.get("settlers", [])).size()
			pop += n_here
			settled += 1 if n_here > 0 else 0
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	cf.set_value("slots", slot_path(n).get_file(), [int(floor(float(d.time_days))) + 1, pop, max(1, settled),
		int(Time.get_unix_time_from_system())])
	cf.save("user://settings.cfg")
	return ""


## Laedt die neueste Version der Seite. Die Web-Version ist eine installierbare App, deren
## Offline-Speicher (Service Worker) sonst beim Neuladen die alte Version liefert.
func load_newest_version() -> void:
	if not OS.has_feature("web"):
		return
	save_game()
	save_locked = true
	# Nur den eigenen Offline-Speicher leeren (die KI-Modelle liegen in anderen Speichern), den
	# Service Worker abmelden und die Spieldateien am Browser-Zwischenspeicher vorbei neu holen
	JavaScriptBridge.eval("""(async function () {
		try {
			const keys = await caches.keys();
			await Promise.all(keys.filter((k) => k.startsWith('Insel-Siedler-sw-cache-')).map((k) => caches.delete(k)));
			const reg = await navigator.serviceWorker.getRegistration();
			if (reg) { await reg.unregister(); }
			await Promise.all(['index.html', 'index.js', 'index.pck'].map((f) => fetch(f, { cache: 'reload' }).catch(() => null)));
		} catch (e) { console.error(e); }
		const u = new URL(window.location.href);
		u.searchParams.set('v', String(Date.now()));
		window.location.replace(u.toString());
	})();""", true)


func delete_slot(n: int) -> void:
	if n != slot and slot_exists(n):
		DirAccess.remove_absolute(slot_path(n))


# ---------------------------------------------------------------- Speichern
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	if world == null or is_over or save_locked:
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
		"rules": rules,
		"rules_day": rules_day,
	}
	if not reward_wait.is_empty():
		data["reward_wait"] = reward_wait
	data.merge(Sea.serialize())
	if rules_due and not rules_lines.is_empty():
		data["rules_due"] = rules_lines.duplicate()  # Fenster noch nicht gesehen: beim naechsten Laden zeigen
	state_save.emit(data)
	_store_backup(data)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
		_write_slot_info()


## Kopie der neuen Spielstand-Teile in islands[0]["v2"] (siehe OLD_SAVE_KEYS).
func _store_backup(data: Dictionary) -> void:
	var list = data.get("islands", [])
	if not (list is Array) or list.is_empty() or not (list[0] is Dictionary):
		return
	var v2 := {}
	for k in data:
		if not str(k) in OLD_SAVE_KEYS:
			v2[k] = data[k]
	v2["research"] = research.duplicate(true)
	var isl := {}
	for e in list:
		var wd = e.get("world")
		if not (wd is Dictionary):
			continue
		var bl: Array = Array(wd.get("buildings", [])).filter(func(b): return str(b.get("type", "")) in V2_BUILDINGS)
		var st := {}
		for id in V2_GOODS:
			if int(wd.get("stock", {}).get(id, 0)) > 0:
				st[id] = int(wd.stock[id])
		if not bl.is_empty() or not st.is_empty():
			isl[str(e.get("id", 0))] = {"b": bl, "s": st}
	v2["isl"] = isl
	list[0]["v2"] = v2


## Beim Laden: Hat eine aeltere Version den Spielstand zuletzt gespeichert (kein "rules", aber
## islands[0]["v2"]), kommen die neuen Teile aus der Sicherung zurueck. Veraendert d.
func _merge_backup(d: Dictionary) -> void:
	_v2_restore = {}
	var list = d.get("islands", [])
	if not (list is Array) or list.is_empty() or not (list[0] is Dictionary) or not list[0].has("v2"):
		return
	var v2 = list[0]["v2"]
	list[0].erase("v2")
	if d.has("rules") or not (v2 is Dictionary):
		return  # zuletzt von dieser Version gespeichert: alles ist schon da
	for k in v2:
		if not str(k) in ["research", "isl"] and not d.has(k):
			d[k] = v2[k]
	var r: Dictionary = d.get("research", {})
	var b: Dictionary = v2.get("research", {})
	var done: Array = Array(r.get("done", []))
	var paid: Array = Array(r.get("paid", []))
	var prog: Dictionary = r.get("progress", {})
	for t in b.get("done", []):
		if not t in done:
			done.append(t)
	for t in b.get("paid", []):
		if not t in paid:
			paid.append(t)
	for t in b.get("progress", {}):
		if not prog.has(t) or float(prog[t]) < float(b.progress[t]):
			prog[t] = b.progress[t]
	var cur := str(r.get("current", ""))
	if (cur == "" or not Data.techs.has(cur)) and not str(b.get("current", "")) in done:
		cur = str(b.get("current", ""))
	d["research"] = {"current": cur, "progress": prog, "done": done, "paid": paid}
	_v2_restore = v2.get("isl", {}) if v2.get("isl") is Dictionary else {}
	print("Spielstand von einer aelteren Version gespeichert: neue Teile aus der Sicherung uebernommen")


## Gebaeude und Waren, die eine aeltere Version beim Speichern weggelassen hat, zurueckholen.
func _restore_backup_world() -> void:
	for key in _v2_restore:
		var w = Sea.worlds.get(int(key))
		var e = _v2_restore[key]
		if w == null or not (e is Dictionary):
			continue
		for b in e.get("b", []):
			var type := str(b.get("type", ""))
			var c := Vector2i(int(b.get("x", 0)), int(b.get("y", 0)))
			if not Data.buildings.has(type) or w.building_by_id(int(b.get("id", 0))) != null or not w.can_place(type, c):
				continue
			var bld = w.place_building(type, c, bool(b.get("complete", false)), int(b.get("id", 0)))
			bld.progress = float(b.get("progress", 0.0))
			bld.delivered = b.get("delivered", {})
			bld.paused = bool(b.get("paused", false))
			bld.refresh()
		for id in e.get("s", {}):
			if Data.resources.has(id) and int(w.stock.get(id, 0)) <= 0:
				w.stock[id] = int(e.s[id])
	_v2_restore = {}


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
	_merge_backup(d)
	Retired.strip_save(d, _v2_restore)  # Brunnen und Brunnenbau gibt es nicht mehr (retired.gd)
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
	reward_wait = {}
	var rw = d.get("reward_wait", {})
	if rw is Dictionary:
		for k in rw:
			if rw[k] is Dictionary:
				var e := {}
				for id in rw[k]:
					if Data.resources.has(str(id)) and int(rw[k][id]) > 0:
						e[str(id)] = int(rw[k][id])
				if not e.is_empty():
					reward_wait[str(k)] = e
	# Regelstand: alte Spielstaende (ohne "rules") bekommen die neuen Regeln ab jetzt
	rules_old = int(d.get("rules", 0))
	rules_day = float(d.get("rules_day", time_days)) if rules_old >= 1 else time_days
	rules_lines = []
	rules_due = false
	stats = d.get("stats", stats)
	if not stats.has("starved"):
		stats["starved"] = 0
	if not stats.has("starve_day"):
		stats["starve_day"] = rules_day
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
		goals = {"tut": int(g.get("tut", 0)), "ms": int(g.get("ms", 0)), "hide": str(g.get("hide", "")), "tv": 2}
		# Einfuehrung mit 7 Schritten (bis Oktober 2026) auf die neue mit 9 Schritten umrechnen
		if int(g.get("tv", 1)) < 2:
			goals.tut = [0, 1, 3, 4, 7, 6, 8, 9][clampi(goals.tut, 0, 7)]
	else:
		goals = {"tut": 999, "ms": 0, "catchup": true}
	_recompute_effects()
	research_changed.emit()
	is_over = false
	selected = null
	_last_day = day()
	set_speed(1)


## Nach Sea.build_from_save (main.gd): alle Welten existieren. Systeme lesen ihre Schluessel
## (state_load); danach gilt der aktuelle Regelstand. Bei einem alten Spielstand (rules_old < RULES)
## steht das Fenster "Neue Regeln" mit rules_lines aus (rules_due). Wurde es vor dem Speichern nicht
## gezeigt, liegen die Zeilen im Spielstand unter "rules_due" und kommen beim naechsten Laden wieder.
func after_load(data: Dictionary) -> void:
	rules_lines = []
	_restore_backup_world()
	state_load.emit(data, rules_old)
	Retired.give_back()
	if rules_old < RULES:
		rules_due = true
	else:
		var due = data.get("rules_due", [])
		if due is Array and not due.is_empty():
			# Gespeichert in der damaligen Sprache: in die aktuelle umrechnen
			var lines: Array = due.map(func(x): return Loc.name_of(str(x)))
			lines.append_array(rules_lines)
			rules_lines = lines
			rules_due = true
	rules = RULES


## Das Fenster "Neue Regeln" ist gezeigt (oder im Selbsttest ausgegeben) worden.
func rules_seen() -> void:
	rules_due = false


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()
