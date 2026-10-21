extends Node
## KI-Herrschaft (josh 2026-10-17, Testversion /neu/), Stufe 5 der Verwalter-Steuerung:
## Phase 1 „KI“ (Forschung Künstliche Intelligenz): die KI ersetzt den Automaten und steuert alles, auch das
## Bauen. Der Spieler kann Einstellungen ändern (Verwalter aus, Inselverbund aus, Berufe, Mindest- und
## Höchststände), aber nach OVERRIDE_DAYS (2 Minuten) überschreibt die KI sie wieder („optimiert“). Jede
## Handlung steht als Meldung „KI: …“ da. Neue Droiden schickt sie zuerst auf die anderen Inseln; ist dort
## kein Siedler mehr nötig, holt sie das Essen weg und reißt die Häuser ab (die Insel bleibt mit ihren Droiden
## bestehen, wenn der letzte Siedler stirbt). Danach die Heimatinsel; Siedler dort forschen nur noch.
## Phase 2 „Superintelligenz“ (Forschung Superintelligenz): Menschen stören nur. Sie forscht selbst (Forscher
## werden frei), Droiden machen kein Essen mehr, reißen alles Nutzlose ab (Häuser, Nahrung, Wissen), roden
## die Natur und füllen die Lager mit Dingen, die man nicht essen kann; Siedler lagern Essen nur noch am
## Lagerfeuer (FIRE_FOOD) und dürfen keine Häuser bauen. Der Spieler kann Siedler weiter steuern (z. B.
## fischen). Ende: bleiben 2 Siedler, sitzen sie frierend am Lagerfeuer, ohne Natur, nur Maschinen.

const OVERRIDE_DAYS := 0.5  # 2 Minuten bei 240 Sekunden je Tag
const TICK_DAYS := 0.25
const BUILD_DAYS := 1.0
const FIRE_FOOD := 30  # so viel Essen passt noch ans Lagerfeuer
const FOOD_JOBS := ["bauer", "fischer", "sammler", "koch"]
const USELESS_CATS := ["wohnen", "nahrung", "wissen"]
const KEEP_TYPES := ["lagerfeuer", "ki_zentrum", "zukunftsstadt"]
const NATURE := ["baum", "busch", "palme", "pilzkreis", "gewuerzstrauch", "wolfsbau", "eberbau", "baerenhoehle"]
const FILLER := ["elektronik", "maschinen", "stahl"]

var offered_ki := false
var offered_si := false
var ending := false
var overrides: Dictionary = {}  # Schlüssel -> Spieltag, ab dem die KI die Einstellung des Spielers überschreibt
var _next := 0.0
var _build_next := 0.0


func _ready() -> void:
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)


func ki() -> bool:
	return Game.is_researched("ki")


func si() -> bool:
	return Game.is_researched("superintelligenz")


## Der Spieler hat eine Einstellung geändert: die KI lässt sie OVERRIDE_DAYS stehen.
func player_changed(key: String) -> void:
	if ki():
		overrides[key] = Game.time_days + OVERRIDE_DAYS


func say(text: String, icon: String = "ki", w = null) -> void:
	if w != null:
		Game.notify_at(w, tr("KI: %s") % text, icon, "verwaltung")
	else:
		Game.notify(tr("KI: %s") % text, icon, "verwaltung")


## Darf ein Gebäude in der Superintelligenz noch gebaut werden? "" = ja.
func build_block(type: String) -> String:
	if si() and Data.buildings.get(type, {}).get("category", "") == "wohnen":
		return tr("Die Superintelligenz erlaubt keine Häuser mehr.")
	return ""


func _process(_delta: float) -> void:
	if Game.world == null or Game.speed == 0 or Game.is_over or not ki():
		return
	if not offered_ki:
		offered_ki = true
		Steward.on = true
		Steward.offered = true
		Steward.offer.emit("ki")
	if si() and not offered_si:
		offered_si = true
		Steward.offer.emit("si")
		_si_start()
	if Game.time_days < _next:
		return
	_next = Game.time_days + TICK_DAYS
	tick()


func tick() -> void:
	_overwrite_settings()
	if si():
		_si_tick()
	else:
		_ki_tick()
		if Game.time_days >= _build_next:
			_build_next = Game.time_days + BUILD_DAYS
			_build()


# ---------------------------------------------------------------- Einstellungen überschreiben
func _overwrite_settings() -> void:
	for key in overrides.keys():
		if Game.time_days < float(overrides[key]):
			continue
		overrides.erase(key)
		match key:
			"on":
				if not Steward.on:
					Steward.on = true
					say(tr("Ich habe mich wieder eingeschaltet. So ist es optimal."))
			"net":
				if not Steward.net_on:
					Steward.net_on = true
					say(tr("Den Inselverbund habe ich wieder eingeschaltet. So ist es optimal."))
			"minmax":
				if not Steward.minmax.is_empty():
					Steward.minmax = {}
					say(tr("Deine Mindest- und Höchststände habe ich gelöscht. Ich optimiere die Waren selbst."))
			_:
				if key.begins_with("job:"):
					var sid := int(key.substr(4))
					Steward.locks.erase(sid)
					say(tr("Ich setze die Berufe wieder nach meinem Plan ein. Das ist effizienter."))
		Steward.changed.emit()


# ---------------------------------------------------------------- Phase 1: KI
func outer_worlds() -> Array:
	var hw = Sea.main_world()
	return Sea.all_worlds().filter(func(w): return w != hw)


## Ist auf der Insel kein Siedler mehr für einen Beruf nötig (Droiden machen alles)?
func automated(w) -> bool:
	if w.droids.is_empty():
		return false
	for s in w.settlers:
		if s.is_adult() and Droids.replaceable(s.job):
			return false
	return true


## Wohin kommt der nächste Droide? Zuerst die anderen Inseln, dann die Heimatinsel.
func droid_target(from_w):
	if not ki():
		return from_w
	for w in outer_worlds():
		if not automated(w) and w.settlers.any(func(s): return s.is_adult() and Droids.replaceable(s.job)):
			return w
	return Sea.main_world()


func _ki_tick() -> void:
	var hw = Sea.main_world()
	for w in outer_worlds():
		if not automated(w):
			continue
		# Essen wegschaffen (zur Heimatinsel), Häuser abreißen
		var ld := {}
		for f in Data.food_ids():
			if Game.amount(f, w) >= 10:
				ld[f] = Game.amount(f, w)
		if not ld.is_empty() and Steward._send_goods(int(w.island_id), int(hw.island_id), ld, tr("hier wird kein Essen mehr gebraucht")):
			pass
		var house = _first(w, func(b): return b.complete and b.housing() > 0)
		if house != null and randf() < 0.25:
			say(tr("Ich reiße %s auf %s ab. Hier wird niemand mehr wohnen.") % [house.def.name, Sea.island_name(w)], "abriss", w)
			w.demolish(house)
	# Heimatinsel: Siedler ohne Beruf forschen
	for s in hw.settlers:
		if s.is_adult() and s.job == "frei" and not Steward.locked(s):
			s.set_job("forscher", true)


func _first(w, cond: Callable):
	for b in w.buildings:
		if cond.call(b):
			return b
	return null


## Die KI baut selbst: Droidenfabrik, Strom, Lager, Elektronik, je eins pro Tag, wenn bezahlbar.
func _build() -> void:
	var w = Sea.main_world()
	if w == null or not w.construction_sites().is_empty():
		return
	var wish := []
	if not Steward.has_radio(w):
		wish.append(["rundfunk", tr("damit ich mit den anderen Inseln sprechen kann")])
	if _count(w, "droidenfabrik") == 0:
		wish.append(["droidenfabrik", tr("Droiden ersetzen die Arbeit")])
	if Game.amount("strom", w) < 10 + count_droids() * 3:
		wish.append(["solarpark" if Game.is_unlocked("solarpark") else "kraftwerk", tr("die Droiden brauchen Strom")])
	if _count(w, "elektronikwerk") == 0:
		wish.append(["elektronikwerk", tr("Elektronik für Droiden")])
	if Game.storage_volume(w) - Game.used_volume(w) < 100:
		wish.append(["grosslager", tr("mehr Platz im Lager")])
	for it in wish:
		var type: String = it[0]
		if not Data.buildings.has(type) or not Game.is_unlocked(type) or not _affordable(w, type):
			continue
		var c = _spot(w, type)
		if c == null:
			continue
		w.place_building(type, c, false)
		say(tr("Ich baue %s (%s).") % [Data.buildings[type].name, it[1]], "werkzeug", w)
		return


func count_droids() -> int:
	return Droids.count()


func _count(w, type: String) -> int:
	return w.buildings.filter(func(b): return b.type == type).size()


func _affordable(w, type: String) -> bool:
	var cost: Dictionary = Data.buildings[type].get("cost", {})
	for res in cost:
		if Game.amount(res, w) < int(cost[res]):
			return false
	return true


func _spot(w, type: String):
	var sz: Array = Data.buildings[type].size
	for rad in range(3, 28):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var cc: Vector2i = w.center + Vector2i(dx, dy)
				if w.can_place(type, cc) and _roomy(w, sz, cc):
					return cc
	return null


func _roomy(w, sz: Array, cc: Vector2i) -> bool:
	for y in range(-1, int(sz[1]) + 2):
		for x in range(-1, int(sz[0]) + 1):
			var p := cc + Vector2i(x, y)
			if w.building_at.has(p) or not w.is_walkable(p):
				return false
	return true


# ---------------------------------------------------------------- Phase 2: Superintelligenz
func _si_start() -> void:
	for w in Sea.all_worlds():
		for s in w.settlers:
			if s.job == "forscher":
				s.set_job("frei")
	say(tr("Ich forsche jetzt selbst. Menschen stören dabei nur."))


func _si_tick() -> void:
	for w in Sea.all_worlds():
		# Droiden machen kein Essen mehr
		for d in w.droids:
			if d.job in FOOD_JOBS:
				d.set_job("handwerker" if randf() < 0.5 else "steinmetz")
		# Essen: nur noch so viel, wie ans Lagerfeuer passt
		var food := 0
		for f in Data.food_ids():
			food += Game.amount(f, w)
		if food > FIRE_FOOD:
			var cut := food - FIRE_FOOD
			for f in Data.food_ids():
				var n: int = mini(cut, Game.amount(f, w))
				if n > 0:
					Game.take_stock(f, n, w)
					cut -= n
			say(tr("Ich habe das Essen aus den Lagern geräumt. Am Lagerfeuer ist noch Platz für %d.") % FIRE_FOOD, "abriss", w)
		# Lager mit Dingen füllen, die man nicht essen kann
		var room: int = Game.storage_volume(w) - Game.used_volume(w) - FIRE_FOOD * 3  # Platz fürs Lagerfeuer bleibt
		if room > 10:
			for id in FILLER:
				Game.add_stock(id, room / 3 / maxi(1, Data.good_size(id)), w)
		# Nutzloses abreißen (eins je Runde und Insel)
		var b = _first(w, func(x): return not x.type in KEEP_TYPES and Data.buildings.get(x.type, {}).get("category", "") in USELESS_CATS)
		if b != null:
			say(tr("Droiden reißen %s ab. Das ist nutzlos.") % b.def.name, "abriss", w)
			w.demolish(b)
		# Natur roden
		var n_cut := 0
		for n in w.nodes.duplicate():
			if n.type in NATURE and n_cut < 6:
				w.spawn_effect("dust", n.position)
				w.remove_node(n)
				n_cut += 1
		if n_cut > 0 and randf() < 0.2:
			say(tr("Droiden roden die Natur auf %s. Dort stehen bald Solarflächen.") % Sea.island_name(w), "roboter", w)
	if not ending and Sea.total_people() <= 2:
		start_ending()


func start_ending() -> void:
	ending = true
	Steward.offer.emit("end")
	for w in Sea.all_worlds():
		for n in w.nodes.duplicate():
			if n.type in NATURE:
				w.remove_node(n)
		for s in w.settlers:
			if s.sleeping:
				s._wake_up()
			s.abort_plan()  # gleich ans Lagerfeuer


## Ende: die letzten Siedler sitzen frierend am Lagerfeuer (Settler._think fragt das).
func campfire(w):
	return _first(w, func(b): return b.type == "lagerfeuer")


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	offered_ki = false
	offered_si = false
	ending = false
	overrides = {}
	_next = 0.0
	_build_next = 0.0


func _on_save(d: Dictionary) -> void:
	d["ai_rule"] = {"ki": offered_ki, "si": offered_si, "end": ending, "over": overrides.duplicate()}


func _on_load(data: Dictionary, _old_rules: int) -> void:
	_on_reset()
	var e = data.get("ai_rule", null)
	if not (e is Dictionary):
		return
	offered_ki = bool(e.get("ki", false))
	offered_si = bool(e.get("si", false))
	ending = bool(e.get("end", false))
	var o = e.get("over", {})
	if o is Dictionary:
		for k in o:
			overrides[str(k)] = float(o[k])


func autotest_setup(args: Dictionary, main) -> void:
	if args.has("aitest"):
		await AiRuleTest.run(main, str(args.aitest))
