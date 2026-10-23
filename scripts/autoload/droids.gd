extends Node
## Droiden (josh 2026-10-17, Testversion /neu/): ab Elektrizität und Halbleitern (Forschung Computer) baut die
## Droidenfabrik aus Elektronik, Stahl, Maschinen und Strom einen Droiden (Building._do_produce ruft build).
## Ein neuer Droide übernimmt Schritt für Schritt einen Beruf: den, den die meisten Siedler der Insel haben
## (ohne Forscher, Verwalter, Seeleute und Jäger); dieser Siedler wird frei (der Verwalter setzt ihn neu
## ein). Jeder Droide braucht POWER_PER_DAY Strom am Tag aus dem Lager seiner Insel; ist keiner da, stehen
## alle Droiden der Insel still. Droiden leben in World.droids (scripts/entities/droid.gd).

signal changed

const POWER_PER_DAY := 1.0
const TICK_DAYS := 0.1
## Berufe, die Droiden nie übernehmen
const HUMAN_JOBS := ["frei", "forscher", "verwalter", "seemann", "jaeger"]

var _power: Dictionary = {}  # Insel-ID -> bool (Strom reicht)
var _acc: Dictionary = {}    # Insel-ID -> angefangener Stromverbrauch
var _warned: Dictionary = {} # Insel-ID -> Tag der letzten Warnung
var _next := 0.0
var built := 0               # Droiden insgesamt gebaut (für Namen)


func _ready() -> void:
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)


func unlocked() -> bool:
	return Game.is_researched("computer") and Game.is_researched("elektrizitaet")


func powered(w) -> bool:
	return bool(_power.get(int(w.island_id), true))


func count(w = null) -> int:
	if w != null:
		return w.droids.size()
	var n := 0
	for o in Sea.all_worlds():
		n += o.droids.size()
	return n


func is_droid_id(w, sid: int) -> bool:
	if w == null or sid == 0:
		return false
	for d in w.droids:
		if d.id == sid:
			return true
	return false


func replaceable(job: String) -> bool:
	return Data.jobs.has(job) and not job in HUMAN_JOBS


func _process(_delta: float) -> void:
	if Game.world == null or Game.speed == 0 or Game.is_over:
		return
	if Game.time_days < _next:
		return
	var dt := TICK_DAYS if _next > 0.0 else 0.0
	_next = Game.time_days + TICK_DAYS
	for w in Sea.all_worlds():
		tick(w, dt)


## Strom für die Droiden der Insel abziehen.
func tick(w, dt: float) -> void:
	var key := int(w.island_id)
	if w.droids.is_empty():
		_power[key] = true
		return
	var need: float = float(_acc.get(key, 0.0)) + w.droids.size() * POWER_PER_DAY * dt
	var take := int(need)
	var have := Game.amount("strom", w)
	if take > 0 and have < take:
		Game.take_stock("strom", have, w)
		_acc[key] = 0.0
		if bool(_power.get(key, true)):
			_power[key] = false
			if Game.time_days - float(_warned.get(key, -9.0)) > 1.0:
				_warned[key] = Game.time_days
				Game.notify_at(w, tr("Kein Strom: %d Droiden stehen still. Baue Kraftwerke oder Solarparks.") % w.droids.size(), "strom", "verwaltung")
			changed.emit()
		return
	if take > 0:
		Game.take_stock("strom", take, w)
	_acc[key] = need - take
	if not bool(_power.get(key, true)) and have > 0:
		_power[key] = true
		changed.emit()


## Die Droidenfabrik b hat einen Droiden fertig: er erscheint vor ihr und übernimmt einen Beruf.
func build(w, b) -> Droid:
	built += 1
	var c: Vector2i = b.entrance_cell() if b != null else w.center
	var to = AiRule.droid_target(w)  # KI: zuerst die anderen Inseln automatisieren
	if to != w:
		var cf = AiRule.campfire(to)
		c = cf.entrance_cell() if cf != null else to.center
		AiRule.say(tr("Droide D-%02d fährt nach %s, um dort die Arbeit zu übernehmen.") % [built, Sea.island_name(to)], "roboter")
		w = to
	var d: Droid = w.spawn_droid({"name": "D-%02d" % built, "x": c.x, "y": c.y})
	var pick := pick_job(w)
	d.set_job(pick[0])
	var s = pick[1]
	if s != null:
		var old: String = s.job_name()
		JobDesk.assign(s, "frei", "automat", -1.0, true)  # pick_job hat ihn schon nach der Vergabestelle gewählt
		Game.notify_at(w, tr("Droide %s übernimmt die Arbeit von %s als %s. %s ist jetzt frei.") % [d.display_name, s.display_name, old, s.display_name], "roboter", "verwaltung")
	else:
		Game.notify_at(w, tr("Droide %s ist fertig und arbeitet als %s.") % [d.display_name, d.job_name()], "roboter", "verwaltung")
	changed.emit()
	return d


## [Beruf, Siedler, der ihn abgibt] – der Beruf, den die meisten Siedler der Insel haben.
func pick_job(w) -> Array:
	var by_job := {}
	for s in w.settlers:
		if s.is_adult() and replaceable(s.job) and JobDesk.may(s, "automat"):
			if not by_job.has(s.job):
				by_job[s.job] = []
			by_job[s.job].append(s)
	var best := ""
	for j in by_job:
		if best == "" or by_job[j].size() > by_job[best].size():
			best = j
	if best != "":
		return [best, by_job[best][0]]
	var need: Dictionary = Steward.needed(w)
	var j: String = need.get("job", "")
	return [j if replaceable(j) else "frei", null]


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	_power = {}
	_acc = {}
	_warned = {}
	_next = 0.0
	built = 0


func _on_save(d: Dictionary) -> void:
	d["droids"] = {"built": built}


func _on_load(data: Dictionary, _old_rules: int) -> void:
	_on_reset()
	var e = data.get("droids", null)
	if e is Dictionary:
		built = int(e.get("built", 0))


func autotest_setup(args: Dictionary, main) -> void:
	if args.has("droidtest"):
		await DroidTest.run(main, str(args.droidtest))
