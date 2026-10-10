extends RefCounted
## Spiel-Bot v2 (Testhilfe --bot=1): spielt die Heimatinsel wie ein aufmerksamer Spieler, nur über die
## öffentliche Spiellogik (Baustellen anlegen, Berufe vergeben, Forschung wählen, Werkstätten anhalten,
## Aufträge annehmen, Einführung überspringen). Keine geschenkten Waren, keine erzwungenen Prüfungen.
## Ein Messwerkzeug für die Spielbalance: druckt je Jahr eine Zeile "BOT Jahr ..." und am Ende "ERGEBNIS: ...".
## main.gd ruft setup() vor der Schleife, tick() jede Testsekunde, report() alle 20 s und finish() am Ende.

const STONE_AGE := ["schrift", "steinwerkzeuge", "gartenbau", "holzbearbeitung", "zimmerei", "flechtkoerbe",
	"raeuchern", "toepferei", "vorratshaltung", "steinbruch", "muehlenbau", "brunnenbau"]
const ANTIQUITY := ["backkunst", "maurerei", "bewaesserung", "koehlerei", "unterricht", "heilkunde", "gelehrsamkeit",
	"tierhaltung", "handkarren", "bergbau", "eisenverhuettung", "schmiedekunst", "deichbau"]
const FOOD_JOBS := ["fischer", "sammler", "bauer"]
## Holzfaktor des Winters, so wie die Siedler ihn kennen (Seasons.winter_forecast); unbekannt = vorsichtig
const WINTER_GUESS := {"": 1.4, "mild": 0.6, "normal": 1.0, "hart": 1.4, "bitter": 1.8, "streng": 1.6}

var main
var args: Dictionary = {}
var w  # Heimatinsel (World)

var _n_food := 1  # Nahrungssammler (Regler nach Nahrung-Tagen)
var _food_next := 0.0  # time_days der nächsten Anpassung
var _year := 1
var _starved_by_year := {}  # Jahr -> Hungertote
var _deaths_by_cause := {}
var _placed := {}  # Gebäudetyp -> Zahl der vom Bot angelegten Baustellen
var _job_changes := 0
var _quest_log := []
var _research_log := []
var _last_research := ""
var _tut_done := false
var _want := {}  # zuletzt berechnete Berufe (für den Bericht)
var _targets := {}  # Zielmengen (für den Bericht)
var _events_seen := {}
var _cond_met := {}  # "Prüfung:Bedingung" -> Tag, an dem sie zuerst erfüllt war (Messwert)
var _exam_seen := 0
var _winter_min := 99.0  # kleinste Nahrung-Tage im laufenden Winter
var _was_winter := false
var _proven_pop := 0  # so viele Siedler hat der letzte Winter sicher ernährt
var _limits_next := 0.0
var _next_build := ""  # erstes Gebäude der Wunschliste, für das noch Material fehlt


func setup(m, a: Dictionary) -> void:
	main = m
	args = a
	w = Sea.worlds.get(0, Game.world)
	_year = Seasons.year()
	Game.settler_died.connect(_on_died)
	var nodes := {}
	for nd in w.nodes:
		nodes[nd.type] = int(nodes.get(nd.type, 0)) + 1
	print("BOT v2: spielt die Heimatinsel (Seed %d), Ereignisse %s, Winter %s, Rohstoffquellen %s" % [Game.seed_value,
		"aus" if not Events.enabled else "an", Seasons.force_w if Seasons.force_w != "" else "wechselnd", nodes])


func _on_died(s, cause: String) -> void:
	_deaths_by_cause[cause] = int(_deaths_by_cause.get(cause, 0)) + 1
	if cause == "starve":
		var y: int = Seasons.year()
		_starved_by_year[y] = int(_starved_by_year.get(y, 0)) + 1
		print("BOT: %s ist verhungert (Tag %d, Jahr %d, Nahrung %d, Nahrung-Tage %.1f)" % [s.display_name, Game.day(), y,
			Game.total_food(w), Game.food_days(w)])


# ================================================================== Takt
func tick(_elapsed: float) -> void:
	if Game.is_over:
		return
	w = Sea.worlds.get(0, Game.world)
	if w == null or not is_instance_valid(w) or w.settlers.is_empty():
		return
	_skip_tutorial()
	_year_line()
	_winter_watch()
	_exam_watch()
	_research()
	_quests()
	_build()
	_jobs()  # hält auch Werkstätten an oder lässt sie laufen
	_store_limits()
	_watch_events()


## Hoechstmengen im Lagerfenster (wie ein Spieler): Freie fällen sonst Holz, bis kein Platz mehr für Nahrung ist.
func _store_limits() -> void:
	if Game.time_days < _limits_next:
		return
	_limits_next = Game.time_days + 0.5
	var qs: Dictionary = _quest_stock()
	var want_holz: int = maxi(maxi(80, int(_wood_target() * 1.5)), int(qs.get("holz", 0)) + 10)
	var want_stein: int = maxi(maxi(80, (40 + _planned_need("stein")) * 2), int(qs.get("stein", 0)) + 10)
	var vol: int = Game.storage_volume(w)
	for pair in [["holz", want_holz], ["stein", want_stein]]:
		# Eine Hoechstmenge reserviert ihren Platz: erst bei großem Lager, und höchstens ein Drittel davon
		var n: int = -1 if vol < 800 else mini(int(pair[1]), vol / (3 * maxi(1, Data.good_size(pair[0]))))
		if Game.limit_of(pair[0], w) != n:
			Game.set_limit(pair[0], n, w)


## Merkt sich, wie viele Siedler der letzte Winter satt gemacht hat: so weit wächst die Siedlung sicher.
func _winter_watch() -> void:
	var winter: bool = Seasons.season() == Seasons.WINTER
	if winter:
		_winter_min = minf(_winter_min, Game.food_days(w))
	elif _was_winter:
		var pop: int = w.settlers.size()
		_proven_pop = pop if _winter_min >= 0.8 else -int(pop * 0.85)  # negativ: knapper Winter, nicht weiter wachsen
		print("BOT: Winter vorbei, knappste Nahrung %.1f Tage, %d Siedler ernaehrt -> Wachstum bis %d" % [_winter_min, pop, _growth_cap()])
		_winter_min = 99.0
	_was_winter = winter


## Höchstzahl Siedler, für die der Bot Wohnplätze baut: was der letzte Winter ernährt hat, plus ein Viertel.
func _growth_cap() -> int:
	if _proven_pop < 0:
		return maxi(20, -_proven_pop)
	return maxi(20, int(ceil(_proven_pop * 1.25)))


## Wie ein Spieler, der das Spiel kennt: der Knopf "Überspringen" auf der Zielkarte.
func _skip_tutorial() -> void:
	if _tut_done:
		return
	_tut_done = true
	if Quests.in_tutorial():
		main.hud.goal_card._skip.pressed.emit()
		print("BOT: Einführung übersprungen (Tag %.2f)" % Game.time_days)


# ================================================================== Lagebild
func _adults() -> Array:
	return w.settlers.filter(func(s): return s.is_adult())


func _count(type: String, only_complete: bool = false) -> int:
	var n := 0
	for b in w.buildings:
		if (b.type == type or str(b.def.get("base", "")) == type) and (b.complete or not only_complete):
			n += 1
	return n


func _has(type: String) -> bool:
	return _count(type, true) > 0


func _sites() -> Array:
	return w.construction_sites()


## Holz, das für das Heizen bis zum Frühling bereitliegen sollte (Vorhersage, nicht der echte Wintertyp).
## Kohle im Lager wird zuerst verheizt und zählt mit (Extras.coal_ratio Holz je Kohle).
func heat_reserve() -> float:
	return maxf(0.0, _heat_need() - Game.amount("kohle", w) * Extras.coal_ratio())


func _heat_need() -> float:
	var pop: float = w.settlers.size()
	var f: float = WINTER_GUESS.get(Seasons.winter_forecast(), 1.4)
	var sd: float = Seasons.season_days()
	var left: float = (1.0 - Seasons.season_progress()) * sd
	match Seasons.season():
		Seasons.SPRING:
			return 0.0
		Seasons.SUMMER:
			return pop * (sd * f + sd * 0.3) * Seasons.season_progress()
		Seasons.AUTUMN:
			return pop * (sd * f + left * 0.3)
		_:
			return pop * left * f


## Zielwert Nahrung-Tage je Jahreszeit (Winter: nichts wächst; Herbst: Vorrat für den Winter anlegen).
func food_target() -> float:
	var p: float = Seasons.season_progress()
	var sd: float = Seasons.season_days()
	match Seasons.season():
		Seasons.SPRING:
			return 2.5
		Seasons.SUMMER:
			return 3.0 + 2.5 * p
		Seasons.AUTUMN:
			return (1.0 - p) * sd * 0.4 + sd * 1.15 + 1.0
		_:
			return (1.0 - p) * sd + 0.5
	return 3.0


## Material, das Baustellen noch brauchen.
func _site_need(res: String) -> int:
	var n := 0
	for b in _sites():
		n += int(b.def.cost.get(res, 0)) - int(b.delivered.get(res, 0))
	return maxi(0, n)


## Was die Baustellen, die gewünschte nächste Forschung und das nächste Gebäude der Wunschliste an
## Material brauchen.
func _planned_need(res: String) -> int:
	var n := _site_need(res)
	var t: String = _wanted_tech()
	if t != "" and not t in Game.research.paid:
		n += int(Data.techs[t].get("cost", {}).get(res, 0))
	if _next_build != "":
		n += int(Data.buildings[_next_build].get("cost", {}).get(res, 0))
	# Prüfung Steinzeit: Bretter und Holz für das Holzhaus schon vor der Zimmerei bereitlegen
	if Exams.passed == 0 and _next_build != "holzhaus" and _count("holzhaus") == 0 and Game.is_researched("holzbearbeitung"):
		n += int(Data.buildings["holzhaus"].get("cost", {}).get(res, 0))
	return n


## Die Forschung, die der Bot als nächste will (laufende oder erste wählbare der Rangliste).
func _wanted_tech() -> String:
	if Game.research.current != "":
		return Game.research.current
	for t in _priority():
		if Game.tech_state(t) == "available":
			return t
	return ""


# ================================================================== Forschung
func _priority() -> Array:
	var list := []
	var q: Dictionary = Quests.active
	if not q.is_empty() and str(q.get("check", {}).get("type", "")) == "tech":
		list.append(str(q.check.what))
	list.append_array(STONE_AGE)
	list.append_array(ANTIQUITY)
	for t in Data.sorted_tech_ids():
		if not t in list:
			list.append(t)
	return list


## Erste wählbare Forschung der Rangliste (bezahlt oder bezahlbar), sonst "".
func _next_tech() -> String:
	if Game.research.current != "":
		return Game.research.current
	var first_open := ""
	for t in _priority():
		if Game.tech_state(t) != "available":
			continue
		if first_open == "":
			first_open = t
		if t in Game.research.paid or Game.can_afford(Data.techs[t].get("cost", {}), w):
			return t
	return first_open


func _research() -> void:
	if Game.research.current != "":
		return
	# Was der gewünschten Forschung fehlt, wird nicht für eine spätere ausgegeben (z. B. Bretter für die Zimmerei)
	var wanted: String = _wanted_tech()
	var lacking := {}
	if wanted != "" and not wanted in Game.research.paid:
		var wc: Dictionary = Data.techs[wanted].get("cost", {})
		for res in wc:
			if Game.amount(res, w) < int(wc[res]):
				lacking[res] = true
	for t in _priority():
		if Game.tech_state(t) != "available":
			continue
		var cost: Dictionary = Data.techs[t].get("cost", {})
		if not t in Game.research.paid:
			if not Game.can_afford(cost, w):
				continue
			if t != wanted and cost.keys().any(func(r): return lacking.has(r) and r != "holz"):
				continue
			# Erst die Baustellen und das Brennholz für den Winter, dann die Forschung
			var short := false
			for res in cost:
				var keep: float = heat_reserve() * 0.8 if res == "holz" else 0.0
				if Game.amount(res, w) - int(cost[res]) < keep:
					short = true
			if short:
				continue
		if Game.start_research(t) == "":
			_research_log.append([t, Game.day()])
			print("BOT: Forschung gestartet: %s (Tag %d, %d erforscht)" % [t, Game.day(), Game.research.done.size()])
			return


# ================================================================== Aufträge
func _quests() -> void:
	if not Quests.active.is_empty() or Quests.offers.is_empty():
		return
	var best := -1
	var best_v := 1.4
	for i in Quests.offers.size():
		var v: float = _quest_value(Quests.offers[i])
		if v > best_v:
			best_v = v
			best = i
	if best < 0:
		return
	var q: Dictionary = Quests.offers[best]
	var txt: String = Quests.text_of(q)
	if Quests.accept(best) == "":
		_quest_log.append(txt)
		print("BOT: Auftrag angenommen (Tag %d): %s | Belohnung %s | Wert %.1f" % [Game.day(), txt, Quests.reward_text(q.reward), best_v])


## Wie gut passt ein Angebot zum Spiel des Bots (0 = nicht machbar)?
func _quest_value(q: Dictionary) -> float:
	var c: Dictionary = q.get("check", {})
	var typ := str(c.get("type", ""))
	var what := str(c.get("what", ""))
	var p: Array = GoalChecks.progress(c)
	var left: float = maxf(0.0, float(p[1]) - float(p[0]))
	var v := 0.0
	match typ:
		"building":
			var d: Dictionary = Data.buildings.get(what, {})
			v = 3.0 if Game.can_afford(d.get("cost", {}), w) else 1.5
			if d.has("ships") or d.has("harbor") or d.get("coast", false):
				v = 0.0
		"stock":
			if what == "holz":
				v = 3.0 if left <= 30 + 10 * _adults().size() else 1.0
			elif what == "stein":
				v = 2.5
			elif Data.food_ids().has(what):
				v = 2.5 if left <= 8.0 * w.settlers.size() else 1.0
			elif what in ["bretter", "lehm", "tontafel", "ziegel", "mehl", "kohle"]:
				v = 2.0 if _has(_producer(what)) else 0.5
			else:
				v = 0.5
		"tech":
			v = 3.0
		"housing":
			v = 2.0
		"variety":
			v = 2.0
		"starved":
			v = 3.0 if Game.food_days(w) >= food_target() * 0.8 else 1.0
		"pop", "births":
			v = 1.5 if Game.housing_capacity(w) > w.settlers.size() else 0.8
		_:
			v = 0.0  # Jagd, Inseln entdecken, Liefern: kann der Bot (noch) nicht
	return v + 0.3 * float(q.get("w", 1)) if v > 0.0 else 0.0


func _producer(res: String) -> String:
	for type in Data.buildings:
		if Data.buildings[type].get("production", {}).get("outputs", {}).has(res):
			return type
	return ""


## Ware, die der laufende Auftrag sammeln will, und wie viel insgesamt (sonst {}).
func _quest_stock() -> Dictionary:
	var q: Dictionary = Quests.active
	if q.is_empty():
		return {}
	var c: Dictionary = q.get("check", {})
	if str(c.get("type", "")) != "stock":
		return {}
	return {str(c.what): int(c.n)}


# ================================================================== Bauen
## Wunschliste in Rangfolge: [Typ, Grund]. Nur Freigeschaltetes, das noch fehlt.
func _wishlist() -> Array:
	var out := []
	var pop: int = w.settlers.size()
	var adults: int = _adults().size()
	var cap: int = Game.housing_capacity(w)
	var site_housing := 0
	for b in _sites():
		site_housing += int(b.def.get("housing", 0))
	var fd: float = Game.food_days(w)
	var winter: bool = Seasons.season() == Seasons.WINTER
	# Reicht die Nahrung für mehr Leute? (wenige Sammler genügen und es liegt Vorrat)
	var food_ok: bool = pop < 6 or (fd >= 1.5 and _n_food <= maxi(2, adults / 2) and pop < _growth_cap())
	# Volles Lager: Ernte und Fang gehen verloren, also zuerst Stauraum
	# (nicht im ersten Jahr: da füllen Beeren das kleine Grundlager, und Hütten sind wichtiger)
	if _count("lager") > 0 and Game.used_volume(w) > Game.storage_volume(w) * 0.85 and _sites().filter(func(b): return b.def.has("storage")).is_empty():
		if Game.is_unlocked("grosslager"):
			out.append(["grosslager", "Lager voll"])
		out.append(["lager", "Lager voll"])
	var q: Dictionary = Quests.active
	if not q.is_empty() and str(q.get("check", {}).get("type", "")) == "building":
		var qt := str(q.check.what)
		if _count(qt) < int(q.check.n):
			out.append([qt, "Auftrag"])
	# Feuer angekündigt: ein Brunnen löscht in der Nähe
	var ev: Dictionary = Events.event_of(w)
	if str(ev.get("type", "")) == "brand" and not ev.get("struck", false) and _count("brunnen") == 0:
		out.append(["brunnen", "Brand angekündigt"])
	# Prüfung Steinzeit offen: das Holzhaus vor allem anderen (Bretter nicht für Mühle und Co. ausgeben)
	if Exams.passed == 0 and Game.is_unlocked("holzhaus") and _count("holzhaus") == 0:
		out.append(["holzhaus", "Pruefung"])
	# Nahrung zuerst: Obstgärten und Felder (nicht im Winter, da wächst nichts), Räucherei, Bäckerei
	var orchards: int = _count("obstgarten")
	var fields: int = _count("feld")
	if not winter:
		if Game.is_unlocked("obstgarten") and orchards < 1 + pop / 4:
			out.append(["obstgarten", "Nahrung"])
		if fields < 1 + pop / 4 and Game.amount("weizen", w) < 60:
			out.append(["feld", "Nahrung"])
	# Getreide wird erst als Brot richtig satt (3 Getreide = 30 Nährwert, 2 Brot = 168): Mühle und Bäckerei, bei Getreideberg eine zweite
	var grain_pile: bool = Game.amount("weizen", w) > 80 + 40 * _count("muehle")
	if Game.is_unlocked("baeckerei") and (_count("baeckerei") == 0 or (grain_pile and _count("baeckerei") < _count("muehle"))):
		out.append(["baeckerei", "Brot"])
	if Game.is_unlocked("muehle") and Exams.passed >= 1 and (Game.is_researched("backkunst") or Game.tech_state("backkunst") != "locked") \
			and (_count("muehle") == 0 or (grain_pile and _count("baeckerei") >= _count("muehle") and _count("muehle") < 3)):
		out.append(["muehle", "Mehl"])
	if Game.is_unlocked("raeucherei") and _count("raeucherei") == 0:
		out.append(["raeucherei", "Nahrung"])
	if Game.is_unlocked("schreibstube") and _count("schreibstube") == 0:
		out.append(["schreibstube", "Forschung"])
	# Wohnen: Plätze Luft für Nachwuchs (am Anfang drei), aber nur, wenn die Nahrung reicht
	if food_ok and cap + site_housing < pop + (3 if pop < 10 else 2):
		if Game.is_unlocked("holzhaus") and Game.amount("bretter", w) >= 12:
			out.append(["holzhaus", "Wohnplatz"])
		elif _count("huette") < 6:
			out.append(["huette", "Wohnplatz"])
	# Prüfung Steinzeit: ein Holzhaus
	if Game.is_unlocked("holzhaus") and _count("holzhaus") == 0:
		out.append(["holzhaus", "Pruefung"])
	if Game.is_unlocked("saegegrube") and _count("saegegrube") == 0:
		out.append(["saegegrube", "Bretter"])
	if Game.is_unlocked("tafelmacherei"):
		if _count("lehmgrube") == 0:
			out.append(["lehmgrube", "Lehm"])
		if _count("tafelmacherei") == 0:
			out.append(["tafelmacherei", "Tontafeln"])
	if _count("lager") == 0 and (pop >= 5 or Game.used_volume(w) > Game.storage_volume(w) * 0.6):
		out.append(["lager", "Stauraum"])
	elif Game.used_volume(w) > Game.storage_volume(w) * 0.7 and _sites().filter(func(b): return b.def.has("storage")).is_empty():
		if Game.is_unlocked("grosslager"):
			out.append(["grosslager", "Stauraum"])
		out.append(["lager", "Stauraum"])  # wenn Ziegel für das große fehlen
	if Game.is_unlocked("ziegelei") and _count("ziegelei") == 0 and (Exams.passed >= 1 or Game.research.done.size() >= 7):
		out.append(["ziegelei", "Ziegel"])
	if Game.is_unlocked("brunnen") and _count("brunnen") == 0 and pop >= 8:
		out.append(["brunnen", "Brandschutz"])
	if Game.is_unlocked("steinhaus") and _count("steinhaus") == 0:
		out.append(["steinhaus", "Pruefung Antike"])
	if Game.is_unlocked("steinbruch") and _count("steinbruch") == 0 and pop >= 8:
		out.append(["steinbruch", "Stein"])
	if Game.is_unlocked("schule") and _count("schule") == 0 and pop >= 10:
		out.append(["schule", "Kinder"])
	if Game.is_unlocked("koehlerei") and _count("koehlerei") == 0 and Game.is_unlocked("mine"):
		out.append(["koehlerei", "Kohle"])
	if Game.is_unlocked("mine") and _count("mine") == 0:
		out.append(["mine", "Erz"])
	if Game.is_unlocked("schmelze") and _count("schmelze") == 0:
		out.append(["schmelze", "Eisen"])
	if Game.is_unlocked("schmiede") and _count("schmiede") == 0:
		out.append(["schmiede", "Werkzeug"])
	if Game.is_unlocked("huehnerhof") and _count("huehnerhof") == 0 and fields >= 3:
		out.append(["huehnerhof", "Eier"])
	if Game.is_unlocked("bibliothek") and _count("bibliothek") == 0:
		out.append(["bibliothek", "Forschung"])
	return out


func _build() -> void:
	var adults: int = _adults().size()
	var open: int = _sites().size()
	var max_open: int = 1 if adults < 4 else (2 if adults < 8 else 3)
	if open >= max_open:
		return
	var seen := {}
	_next_build = ""
	for item in _wishlist():
		var type: String = item[0]
		if seen.has(type) or not Data.buildings.has(type) or not Game.is_unlocked(type):
			continue
		seen[type] = true
		if not Data.buildings[type].get("buildable", false):
			continue
		if not _affordable(type, str(item[1]).begins_with("Pruefung")):
			if _next_build == "":
				_next_build = type
			continue
		var c = _spot(type)
		if c == null:
			continue
		w.place_building(type, c, false)
		Game.player_action.emit("place", type)
		_placed[type] = int(_placed.get(type, 0)) + 1
		print("BOT: Baustelle %s bei %s (%s), Tag %d" % [type, c, item[1], Game.day()])
		return  # eine Baustelle je Takt


## Material da (Holz und Stein: die Hälfte reicht, der Rest kommt nach), ohne das Brennholz anzugreifen.
## relaxed: für eine Prüfung reicht die Hälfte jeder Ware (der Rest wird gerade hergestellt).
func _affordable(type: String, relaxed: bool = false) -> bool:
	var cost: Dictionary = Data.buildings[type].get("cost", {})
	var tech: String = _wanted_tech()
	var tech_cost: Dictionary = Data.techs[tech].get("cost", {}) if tech != "" and Game.research.current == "" and not tech in Game.research.paid else {}
	if Data.buildings[type].has("housing") and Game.housing_capacity(w) < w.settlers.size() + 2:
		tech_cost = {}  # Wohnplatz für Nachwuchs geht dann vor
	for res in cost:
		var need := int(cost[res]) + _site_need(res) + int(tech_cost.get(res, 0))  # die Forschung geht vor
		var have: int = Game.amount(res, w)
		if res == "holz":
			have -= int(heat_reserve())
		if relaxed or res in ["holz", "stein"]:
			if have < need / 2:
				return false
		elif have < need:
			return false
	return true


## Freier Platz nahe der Mitte mit einem Feld Abstand ringsum (Wege bleiben frei).
func _spot(type: String):
	var sz: Array = Data.buildings[type].size
	var ground: bool = Data.buildings[type].get("ground", false)
	var start := 3 if not ground else 5
	for rad in range(start, 26):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var cc: Vector2i = w.center + Vector2i(dx, dy)
				if not w.can_place(type, cc):
					continue
				if _roomy(sz, cc):
					return cc
	return null


func _roomy(sz: Array, cc: Vector2i) -> bool:
	for y in range(-1, int(sz[1]) + 2):
		for x in range(-1, int(sz[0]) + 1):
			var p := cc + Vector2i(x, y)
			if w.building_at.has(p) or not w.is_walkable(p):
				return false
	return true


# ================================================================== Werkstätten
## Welche Werkstätten laufen sollen (der Rest wird angehalten). Liefert die Berufe dafür.
func _workshops() -> Dictionary:
	var jobs := {}
	var holz_spare: float = Game.amount("holz", w) - heat_reserve() - _site_need("holz")
	var qs: Dictionary = _quest_stock()
	var age: int = Game.current_age()
	var t_bretter := 12 + _planned_need("bretter") + (12 if Game.is_unlocked("holzhaus") else 0) + int(qs.get("bretter", 0))
	var t_ziegel := _planned_need("ziegel") + (16 if Game.is_unlocked("steinhaus") else 8) + int(qs.get("ziegel", 0))
	var t_tafel := (40 if age >= 1 else 16) + int(qs.get("tontafel", 0))
	var t_lehm := 8 + _planned_need("lehm") + int(qs.get("lehm", 0))
	var t_mehl := (12 if not Game.is_researched("backkunst") else 6) + _planned_need("mehl")
	_targets = {"holz": int(_wood_target()), "bretter": t_bretter, "ziegel": t_ziegel, "tontafel": t_tafel, "lehm": t_lehm, "nahrung_tage": snappedf(food_target(), 0.1)}
	for b in w.buildings:
		if not b.complete or not b.def.has("production"):
			continue
		var on := false
		match b.type:
			"saegegrube":
				on = Game.amount("bretter", w) < t_bretter and holz_spare >= 6
			"lehmgrube":
				var users: bool = _has("tafelmacherei") or _has("ziegelei") or _has("koehlerei") or t_lehm > 8
				on = users and Game.amount("lehm", w) < t_lehm + (8 if _has("tafelmacherei") else 0)
			"tafelmacherei":
				on = Game.amount("tontafel", w) < t_tafel and Game.amount("lehm", w) >= 2
			"ziegelei":
				on = Game.amount("ziegel", w) < t_ziegel and Game.amount("lehm", w) >= 2 and holz_spare >= 4
			"raeucherei":
				on = Game.amount("fisch", w) >= 4 and holz_spare >= 4
			"muehle":
				on = Game.amount("weizen", w) >= 3 and Game.amount("mehl", w) < (40 if _has("baeckerei") else t_mehl)
			"baeckerei":
				on = Game.amount("mehl", w) >= 2 and holz_spare >= 2
			"koehlerei":
				on = Game.amount("kohle", w) < 16 and holz_spare >= 10
			"mine":
				on = Game.amount("erz", w) < 16
			"schmelze":
				on = Game.amount("eisen", w) < 16 and Game.amount("erz", w) >= 2 and Game.amount("kohle", w) >= 2
			"schmiede":
				on = Game.amount("werkzeug", w) < 24 and Game.amount("eisen", w) >= 1
			"huehnerhof":
				on = Game.amount("weizen", w) >= (8 if not _has("baeckerei") else 30)
			"steinbruch":
				on = Game.amount("stein", w) < 40 + _planned_need("stein")
			_:
				on = false
		b.paused = not on
		if on and w.pool_allows(b):
			var job: String = {"kueche": "koch", "handwerk": "handwerker", "stein": "steinmetz"}.get(str(b.prod_def().get("job", "")), "")
			if job != "":
				jobs[job] = int(jobs.get(job, 0)) + 1
	return jobs


func _wood_target() -> float:
	var qs: Dictionary = _quest_stock()
	return maxf(15.0 + heat_reserve() + _planned_need("holz"), float(qs.get("holz", 0)))


# ================================================================== Berufe
func _jobs() -> void:
	var adults := _adults()
	var n := adults.size()
	if n == 0:
		return
	var fd: float = Game.food_days(w)
	# Was die Insel an Nahrung hergibt: Fischgründe und Sträucher mit Vorrat, Felder mit Arbeit
	var fish_nodes := 0
	var bush_nodes := 0
	for nd in w.nodes:
		if nd.amount <= 0:
			continue
		if nd.type == "fischgrund":
			fish_nodes += 1
		elif nd.type in ["busch", "palme", "pilzkreis"]:
			bush_nodes += 1
	var farm_tasks := 0
	for b in w.buildings:
		if b.complete and b.def.has("farm") and (b.farm_task() != "" or b.farm_state == "growing"):
			farm_tasks += 1
	var bauer_cap := 0 if Seasons.season() == Seasons.WINTER or farm_tasks == 0 else maxi(1, ceili(farm_tasks / 3.0))
	var fish_cap := fish_nodes + 1 if fish_nodes > 0 else 0
	var bush_cap := ceili(bush_nodes / 4.0) + (1 if bush_nodes > 0 else 0)
	_food_control(fd, n, bauer_cap + fish_cap + bush_cap)
	var want := {}
	var room := {"left": n}  # Lambdas sehen lokale Zahlen nur als Kopie, darum ein Dictionary
	var add := func(job: String, k: int) -> void:
		var take: int = mini(k, int(room.left))
		if take > 0:
			want[job] = int(want.get(job, 0)) + take
			room.left = int(room.left) - take
	var researching: bool = Game.research.current != ""
	var research_ok: bool = fd > 0.8 or Seasons.season() == Seasons.WINTER
	if n <= 3:
		# Kleine Siedlung: ein Sammler, dann zuerst Wohnplatz (Freie fällen Holz und bauen), sonst ein Forscher
		if fd < 3.0 and n >= 2:
			add.call("fischer" if fish_cap > 0 else "sammler", 1)
		var housing_due: bool = not _sites().filter(func(b): return b.def.has("housing")).is_empty() \
			or Game.housing_capacity(w) < w.settlers.size() + 2
		if researching and research_ok and not housing_due:
			add.call("forscher", 1)
		_want = want
		_apply_jobs(adults, want)
		return
	var stockpile: bool = Seasons.season() >= Seasons.AUTUMN or fd < 1.0  # Wintervorrat oder Hunger: Nahrung vor allem
	# Nahrung aufteilen: Bauern für die Felder, dann Fischer und Sammler (nur so viele, wie Quellen da sind)
	var food: int = _n_food
	var bauer: int = mini(food, bauer_cap)
	var fischer: int = mini(food - bauer, fish_cap)
	var sammler: int = mini(food - bauer - fischer, bush_cap)
	var food_first: int = food if stockpile else mini(food, maxi(1, ceili(n * (0.4 if fd < 2.0 else 0.3))))
	var placed := {"bauer": 0, "fischer": 0, "sammler": 0}
	var add_food := func(k: int) -> void:
		for job in ["bauer", "fischer", "sammler"]:
			var cap: int = {"bauer": bauer, "fischer": fischer, "sammler": sammler}[job] - int(placed[job])
			var t: int = mini(cap, k)
			if t > 0:
				add.call(job, t)
				placed[job] = int(placed[job]) + t
				k -= t
	# 1. Baumeister, wenn es Baustellen gibt (fehlt Material, holt er es selbst)
	var sites: int = _sites().size()
	if sites > 0 and n >= 2:
		add.call("baumeister", 1 if sites < 3 or n < 8 else 2)
	# 2. ein Forscher, sobald die Nahrung nicht knapp ist
	if researching and research_ok:
		add.call("forscher", 1)
	var crit := {}  # schon vergebene Werkstatt-Berufe (zählen bei den Werkstätten mit)
	# 2a. Prüfung Steinzeit: Forschung ist der Engpass, ein zweiter Forscher vor dem Vorratsammeln
	var early_research: bool = Exams.passed == 0 and researching and n >= 5 and fd >= 1.2 and _research_slots() >= 2
	if early_research:
		add.call("forscher", 1)
	# 2b. Prüfung Steinzeit: Bretter für Zimmerei und das erste Holzhaus
	if Exams.passed == 0 and _has("saegegrube") and not _has("holzhaus") and Game.amount("bretter", w) < 12 + _planned_need("bretter"):
		add.call("handwerker", 1)
		crit["handwerker"] = 1
	# 2c. Ab der Antike: Tontafeln für die Forscher (Lehmgrube und Tafelmacherei besetzen)
	if researching and Writing.goods_for(Game.research.current).has("tontafel") and Game.amount("tontafel", w) < 30:
		if _has("tafelmacherei") and Game.amount("lehm", w) >= 2:
			add.call("handwerker", 1)
			crit["handwerker"] = int(crit.get("handwerker", 0)) + 1
		if _has("lehmgrube") and Game.amount("lehm", w) < 16:
			add.call("steinmetz", 1)
			crit["steinmetz"] = 1
	# 3. Brennholz wird knapp (Herbst und Winter): ein Holzfäller vor allem anderen
	var heat_day: float = Seasons.heat_per_settler() * w.settlers.size()
	if heat_day > 0.0 and Extras.fuel(w) < heat_day * 1.5:  # Holz und Kohle
		add.call("holzfaeller", 1)
	# 4. Nahrung, die gebraucht wird
	add_food.call(food_first)
	# 5. Holz und Stein (Brennholz vor dem Winter, Baustellen, nächste Forschung)
	var wood_def: float = _wood_target() - Game.amount("holz", w)
	if wood_def > 0.0:
		add.call("holzfaeller", 1 + (1 if wood_def > 30.0 and n >= 5 else 0) + (1 if wood_def > 60.0 and n >= 8 else 0))
	var stone_def: int = _planned_need("stein") + (10 if n >= 5 else 0) - Game.amount("stein", w)
	if stone_def > 0:
		add.call("steinmetz", 1 + (1 if stone_def > 30 and n >= 8 else 0))
	# 6. Werkstätten, die laufen sollen
	var ws := _workshops()
	for job in ["handwerker", "steinmetz", "koch"]:
		add.call(job, int(ws.get(job, 0)) - int(crit.get(job, 0)))
	# 7. weitere Forscher, wenn Forschungsplätze frei sind
	if researching and n >= 5 and fd > 1.5 and _research_slots() >= 2 and not early_research:
		add.call("forscher", 1)
	if researching and n >= 10 and fd > 2.0 and _research_slots() >= 3:
		add.call("forscher", 1)
	# 8. Vorrat anlegen mit dem Rest
	add_food.call(food - food_first)
	_want = want
	_apply_jobs(adults, want)


func _research_slots() -> int:
	var n := 0
	for b in w.buildings:
		if b.complete and b.def.has("research") and w.pool_allows(b):
			n += b.slots()
	return n


## Regler: mehr Sammler, wenn die Nahrung unter dem Ziel liegt, weniger, wenn reichlich da ist.
func _food_control(fd: float, n: int, cap: int) -> void:
	if Game.time_days < _food_next:
		return
	_food_next = Game.time_days + 0.2
	var t: float = food_target()
	if fd < 0.0:
		return
	if fd < t:
		_n_food += 1
	elif fd > t + 2.0 or (Game.space_for("fisch", w) < 20 and fd > t):
		_n_food -= 1
	_n_food = clampi(_n_food, 1 if fd < t + 4.0 else 0, maxi(1, mini(n - 1, cap)))


## Berufe angleichen: Überzählige werden frei, Fehlende kommen aus den Freien (beste Fähigkeit).
func _apply_jobs(adults: Array, want: Dictionary) -> void:
	var have := {}
	for s in adults:
		have[s.job] = int(have.get(s.job, 0)) + 1
	for job in have:
		if job == "frei" or job == "seemann" or job == "jaeger":
			continue
		var extra: int = int(have[job]) - int(want.get(job, 0))
		if extra <= 0:
			continue
		var holders: Array = adults.filter(func(s): return s.job == job)
		holders.sort_custom(func(a, b): return _skill_for(a, job) < _skill_for(b, job))
		for i in extra:
			_set_job(holders[i], "frei")
	for job in want:
		var missing: int = int(want[job]) - adults.filter(func(s): return s.job == job).size()
		for i in missing:
			var free: Array = adults.filter(func(s): return s.job == "frei")
			if free.is_empty():
				return
			free.sort_custom(func(a, b): return _skill_for(a, job) > _skill_for(b, job))
			_set_job(free[0], job)


func _skill_for(s, job: String) -> float:
	var sk: String = Data.jobs.get(job, {}).get("skill", "")
	return s.skill_factor(sk) if sk != "" else 0.0  # Stufe und Talent


func _set_job(s, job: String) -> void:
	if s.job == job:
		return
	s.set_job(job)
	Game.player_action.emit("job", job)
	_job_changes += 1


# ================================================================== Ereignisse
func _watch_events() -> void:
	for e in Events.all_events():
		var ev: Dictionary = e[1]
		var key: String = "%s:%.2f" % [ev.get("type", ""), float(ev.get("strike", 0.0))]
		if not _events_seen.has(key):
			_events_seen[key] = true
			print("BOT: Ereignis angekündigt: %s, Eintritt Tag %.2f" % [ev.get("type", ""), float(ev.get("strike", 0.0)) + 1.0])


# ================================================================== Berichte
## Merkt, wann jede Bedingung der laufenden Prüfung zuerst erfüllt war, und meldet bestandene Prüfungen.
func _exam_watch() -> void:
	for x in Exams.status(Exams.passed):
		var key := "%d:%s" % [Exams.passed, GoalChecks.label(x[0])]
		if x[3] and not _cond_met.has(key):
			_cond_met[key] = snappedf(Game.time_days + 1.0, 0.1)
	while _exam_seen < Exams.passed:
		var conds := []
		for k in _cond_met:
			if str(k).begins_with("%d:" % _exam_seen):
				conds.append("%s Tag %.1f" % [str(k).substr(2), float(_cond_met[k])])
		print("BOT: Pruefung %d bestanden (Tag %.1f). Bedingungen zuerst erfuellt: %s" % [_exam_seen, Game.time_days + 1.0, ", ".join(conds)])
		_exam_seen += 1



func _year_line() -> void:
	var y: int = Seasons.year()
	if y == _year:
		return
	print(_status_line("BOT Jahr %d zu Ende" % _year))
	_year = y


func _status_line(head: String) -> String:
	var exam: String = ", ".join(Exams.status(Exams.passed).map(func(x): return "%s %d/%d" % [x[0].get("type", ""), x[1], x[2]]))
	return "%s (Tag %d): Siedler %d/%d Wohnplätze, Erwachsene %d, Nahrung %d (%.1f Tage), Holz %d, Stein %d, Bretter %d, Tontafeln %d | Forschungen %d, Zeitalter %s, Pruefung %d: %s | Hungertote %d, Tote %d | Auftraege %d/%d | Ereignisse %d/%d | Wertung %d | Winter %s" % [
		head, Game.day(), w.settlers.size(), Game.housing_capacity(w), _adults().size(), Game.total_food(w), Game.food_days(w),
		Game.amount("holz", w), Game.amount("stein", w), Game.amount("bretter", w), Game.amount("tontafel", w),
		Game.research.done.size(), Data.age_name(Game.current_age()), Exams.passed, exam, int(Game.stats.get("starved", 0)),
		int(Game.stats.get("deaths", 0)), int(Game.stats.get("quests", 0)), int(Game.stats.get("quests_failed", 0)),
		int(Game.stats.get("events_survived", 0)), int(Game.stats.get("events", 0)), Exams.score(), Seasons.winter_type(_year)]


func report() -> void:
	if w == null or not is_instance_valid(w):
		return
	print("   " + _status_line("BOT"))
	print("   BOT Berufe soll %s | Nahrungssammler %d | Ziele %s | Holzreserve %d | Baustellen %s | Forschung %s %d/%d" % [_want, _n_food, _targets,
		int(heat_reserve()), _sites().map(func(b): return b.type), Game.research.current, int(Game.tech_progress(Game.research.current)),
		int(Game.tech_points(Game.research.current))])
	var chain := []
	for g in ["weizen", "mehl", "brot", "eier", "aepfel", "fisch", "raeucherfisch", "beeren"]:
		chain.append("%s=%d" % [g, Game.amount(g, w)])
	var shops := []
	for b in w.buildings:
		if is_instance_valid(b) and b.complete and b.type in ["muehle", "baeckerei", "huehnerhof", "raeucherei"]:
			shops.append("%s%s/%d" % [b.type, "(aus)" if b.paused else "", b.occupants.size()])
	var st: Dictionary = w.stock if "stock" in w else {}
	var big: Array = st.keys().filter(func(k): return int(st[k]) * Data.good_size(k) >= 40)
	big.sort_custom(func(a, b): return int(st[a]) * Data.good_size(a) > int(st[b]) * Data.good_size(b))
	print("   BOT Nahrungskette %s | Lagerplatz %d/%d %s | %s" % [" ".join(chain), Game.used_volume(w), Game.storage_volume(w),
		big.slice(0, 6).map(func(k): return "%s=%d" % [k, int(st[k]) * Data.good_size(k)]), shops])


## Die eine Ergebniszeile (grep "ERGEBNIS").
func finish() -> void:
	var by_age := {}
	for t in Game.research.done:
		var a: int = Data.age_of_tier(int(Data.techs[t].tier))
		by_age[a] = int(by_age.get(a, 0)) + 1
	var exams := []
	for i in Exams.passed:
		var d: float = float(Exams.days[i]) if i < Exams.days.size() else -1.0
		exams.append("%s Tag %d (Jahr %d)" % [Data.age_name(i), int(floor(d)) + 1, Seasons.year(d)] if d >= 0.0 else "%s uebernommen" % Data.age_name(i))
	var early: int = int(_starved_by_year.get(1, 0)) + int(_starved_by_year.get(2, 0))
	var tafeln: int = int(Writing.used.get("tontafel", 0))
	print("ERGEBNIS: Tag %d Jahr %d | Siedler %d (hoechstens %d) | Pruefungen %d [%s] | Forschungen %d (Steinzeit %d, Antike %d, spaeter %d) | Hungertote %d (Jahr 1-2: %d, je Jahr %s) | Tote %d %s | Tontafeln verbraucht %d (Schreibwaren gesamt %d) | Auftraege erledigt %d, gescheitert %d | Ereignisse ueberstanden %d von %d | Wertung %d | Spielende %s" % [
		Game.day(), Seasons.year(), Game.population(), int(Game.stats.get("max_pop", 0)), Exams.passed, ", ".join(exams),
		Game.research.done.size(), int(by_age.get(0, 0)), int(by_age.get(1, 0)), Game.research.done.size() - int(by_age.get(0, 0)) - int(by_age.get(1, 0)),
		int(Game.stats.get("starved", 0)), early, _starved_by_year, int(Game.stats.get("deaths", 0)), _deaths_by_cause, tafeln,
		int(Game.stats.get("writing_used", 0)), int(Game.stats.get("quests", 0)), int(Game.stats.get("quests_failed", 0)),
		int(Game.stats.get("events_survived", 0)), int(Game.stats.get("events", 0)), Exams.score(), Game.is_over])
