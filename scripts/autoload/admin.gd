extends Node
## Verwaltung und Verwalter (josh 2026-10-11). Alles steht in data/admin.json.
##
## - Gebäude "verwaltung" (Gelehrsamkeit, "unique": nur eine im ganzen Spiel) und Beruf "verwalter"
##   (nur einer: wer ihn bekommt, nimmt ihn dem bisherigen Verwalter ab, der wird "Frei").
##   Die Verwaltung arbeitet (active()), solange sie fertig steht und es einen erwachsenen Verwalter gibt.
## - Vertretung: In jeder Werkstatt (Gebäude mit "production") lässt sie sich im Infofenster einschalten
##   (Building.adm). Steht eine solche Werkstatt leer und sind weniger Fachkräfte ihres Berufs gerade
##   da (wach, ohne Pause, nicht krank im Bett, nicht schon in einer Werkstatt ihres Berufs) als
##   solche Werkstätten leer stehen, springt ein Siedler ein, der in seinem eigenen Beruf gerade nichts
##   zu tun hat (World.find_standin, Settler._plan_standin). Er arbeitet einen Arbeitsgang und plant dann neu.
## - Personal: alle check_every Tage zählt der Verwalter je Werkstattberuf (Koch, Handwerker,
##   Steinmetz, Bauer in den Ställen) die Werkstätten, die arbeiten könnten, und die Erwachsenen mit dem Beruf. Gibt es mehr
##   Werkstätten als Leute, meldet er sich (höchstens alle report_every Tage je Beruf) und schlägt
##   Überstunden oder Schichtarbeit vor (Signal proposal, Fenster in AdminInfo).
## - Anordnungen je Beruf:
##   (orders[job] = {ot: bool, since: Tag, sh: bool})
##   (josh 2026-10-12: Schicht doppelter, Überstunden anderthalbfacher Tagesertrag; admin_test --adminmeasure misst es)
##   Überstunden: keine Freizeitpausen mehr (Settler._think), overtime_hours früher anfangen und später
##   aufhören (sleep_time), Arbeitstempo overtime_speed (work_mult). Dauern sie overtime_years Jahre am Stück,
##   hören die Arbeiter unter Protest auf: Überstunden aus, protest_days lang protest_mood Laune und
##   so lange keine neuen Überstunden für diesen Beruf.
##   Schichtarbeit: alle Leute des Berufs arbeiten auch nachts (night_worker, sleep_time), Arbeitstempo
##   shift_speed, und alle mit dem Beruf haben shift_mood Laune (eine Laune-Stufe sind 20 Punkte), die ihre
##   Arbeitskraft aber nicht senkt (SettlerMind.mood_work_factor). Solange jemand nachts arbeitet, läuft die
##   Nacht nicht schneller (night_work_now); Werkstätten mit Arbeitern haben nachts Licht (Building).
## Spielstand: oben "admin" = {orders, protest, reported} (Game.state_save/state_load); Building.adm
## steht im Gebäude ("adm"). Alte Spielstände: keine Anordnungen.

signal changed
signal proposal(job: String, text: String)
## Die Leute eines Berufs hören unter Protest mit den Überstunden auf (text: übersetzter Grund, ProtestVideo).
signal protest_started(job: String, text: String)

const OFFICE := "verwaltung"
const JOB := "verwalter"
## Werkstattart (production.job) -> Beruf
const KIND_JOB := {"kueche": "koch", "handwerk": "handwerker", "stein": "steinmetz", "stall": "bauer"}

var cfg: Dictionary = {}
var orders: Dictionary = {}    # Beruf -> {"ot": Überstunden, "since": seit Tag, "sh": Schichtarbeit}
var protest: Dictionary = {}   # Beruf -> Protest bis Tag
var reported: Dictionary = {}  # Beruf -> letzte Meldung (Tag)
var auto_reassign := false     # Stirbt jemand mit Beruf, bekommt ein freier Siedler diesen Beruf (josh 2026-10-16)
var pending_jobs: Array = []   # Berufe Verstorbener ohne freien Nachfolger: das nächste erwachsene Kind lernt sie
const AUTO_AGE := 2            # Neuzuweisung erst ab dem Mittelalter (Zeitalter-Index, josh 2026-10-16)
## Ab Forschungsstufe 8 ordnet der Verwalter Überstunden und Schichtarbeit (mit Nachtschicht) selbst an
## (josh 2026-10-21) und beendet sie wieder, wenn niemand mehr fehlt oder Protest droht.
const SELF_ORDER_TIER := 8
var self_orders := true        # Spieler-Schalter im Reiter Verwalter
var auto_orders: Dictionary = {}  # Beruf -> true: diese Anordnung hat der Verwalter selbst getroffen
var _short_at: Dictionary = {}    # Beruf -> letzter Tag, an dem Leute fehlten
var _ot_rest: Dictionary = {}     # Beruf -> bis zu diesem Tag ordnet er keine Überstunden mehr an (Erholung)
var _hold: Dictionary = {}        # Beruf -> bis zu diesem Tag ordnet er nichts an (Spieler hat abgeschaltet)
var _next_tick := 0.0
var _night_check_at := 0
var _night_cached := false


func _ready() -> void:
	cfg = Data._load("admin")
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)
	Game.settler_died.connect(_on_settler_died)


func _c(key: String, default) -> float:
	return float(cfg.get(key, default))


# ---------------------------------------------------------------- Abfragen
## Die fertige Verwaltung (auf irgendeiner Insel) oder null.
func office():
	for w in Sea.all_worlds():
		for b in w.buildings:
			if b.def.get("office", false) and (b.complete or int(b.def.get("office_level", 1)) > 1):
				return b  # eine Ausbau-Baustelle arbeitet mit der Stufe davor weiter
	return null


## Ausbaustufe der Verwaltung (josh 2026-10-29): 0 ohne fertige Verwaltung oder ohne Verwalter auf ihrer
## Insel, sonst 1 (Schreibstube) bis 7 (KI-Leitstelle). Während eines Ausbaus gilt die Stufe davor.
func level() -> int:
	var o = office()
	if o == null or local_manager() == null:
		return 0
	var lv := int(o.def.get("office_level", 1))
	return lv if o.complete else lv - 1


## Ausbaustufe des Gebäudes allein (auch ohne Verwalter), für Anzeigen.
func office_level() -> int:
	var o = office()
	if o == null:
		return 0
	var lv := int(o.def.get("office_level", 1))
	return lv if o.complete else lv - 1


## Der Verwalter (erwachsen) oder null.
func manager():
	for w in Sea.all_worlds():
		for s in w.settlers:
			if s.job == JOB and s.is_adult():
				return s
	return null


## Insel der Verwaltung (josh 2026-10-16): Die Entscheidungen des Verwalters (Vertretung, Überstunden,
## Schichtarbeit, Meldungen über fehlende Leute) gelten nur dort. null ohne fertige Verwaltung.
func admin_world():
	var o = office()
	return o.world if o != null else null


## Der Verwalter (erwachsen) auf der Insel der Verwaltung, oder null.
func local_manager():
	var w = admin_world()
	if w == null:
		return null
	for s in w.settlers:
		if s.job == JOB and s.is_adult():
			return s
	return null


## Die Verwaltung arbeitet: fertig gebaut und ein Verwalter auf derselben Insel.
func active() -> bool:
	return local_manager() != null


## Arbeitet die Verwaltung für diese Insel?
func active_on(w) -> bool:
	return w != null and active() and Powers.covers(w)


## Gibt es dieses Gebäude schon (fertig oder als Baustelle), ohne ignore (beim Verschieben)?
func exists(type: String, ignore = null) -> bool:
	var base: String = Data.buildings.get(type, {}).get("base", type)
	for w in Sea.all_worlds():
		for b in w.buildings:
			if (b.type == type or b.def.get("base", b.type) == base) and b != ignore:
				return true
	return false


func _order(job: String) -> Dictionary:
	return orders.get(job, {"ot": false, "since": 0.0, "sh": false})


## Gelten Überstunden / Schichtarbeit für diesen Beruf auf Insel w? (nur auf der Insel der Verwaltung)
func overtime(job: String, w) -> bool:
	return bool(_order(job).ot) and active_on(w)


func shift(job: String, w) -> bool:
	return bool(_order(job).sh) and active_on(w)


## Angeordnet (auch wenn die Verwaltung gerade nicht arbeitet)?
func ordered(job: String, what: String) -> bool:
	return bool(_order(job).ot) if what == "ot" else bool(_order(job).sh)


func protesting(job: String) -> bool:
	return Game.time_days < float(protest.get(job, 0.0))


## Arbeitet der Siedler heute Nacht durch (Schichtarbeit: die Werkstätten laufen rund um die Uhr)?
func night_worker(s) -> bool:
	return s.is_adult() and shift(s.job, s.world)


## Schlafenszeit eines Siedlers (Settler._sleep_time): nachts, außer bei Schichtarbeit; bei Überstunden
## fängt er overtime_hours früher an und hört so viel später auf.
func sleep_time(s) -> bool:
	if not Game.is_night():
		return false
	if not s.is_adult():
		return true
	if shift(s.job, s.world):
		return false
	if overtime(s.job, s.world):
		var x := _c("overtime_hours", 2.0) / 24.0
		var t := Game.time_of_day()
		return t >= Seasons.night_start() + x or t < Seasons.night_end() - x
	return true


## Arbeitet gerade nachts jemand (Schicht, oder Überstunden in den Randstunden)? Dann läuft die Nacht
## nicht schneller (Game._process, night_speedup), sonst brächte Nachtarbeit fast nichts und man sähe sie kaum.
## Wird höchstens alle 0,5 Sekunden neu gezählt.
func night_work_now() -> bool:
	var now := Time.get_ticks_msec()
	if now < _night_check_at:
		return _night_cached
	_night_check_at = now + 500
	_night_cached = false
	if not active():
		return false
	for s in admin_world().settlers:
		if s.is_adult() and (shift(s.job, s.world) or overtime(s.job, s.world)) and not sleep_time(s):
			_night_cached = true
			return true
	return false


## Arbeitstempo-Faktor aus den Anordnungen (Settler.work_factor): so abgestimmt, dass ein Beruf mit
## Schichtarbeit am Tag shift_output (2) mal so viel schafft wie ohne, mit Überstunden overtime_output (1,5)
## mal so viel. Die längere Arbeitszeit bringt schon einen Teil, der Faktor den Rest (admin_test misst es).
func work_mult(s) -> float:
	if not s.is_adult():
		return 1.0
	if shift(s.job, s.world):
		return _c("shift_speed", 1.0)
	if overtime(s.job, s.world):
		return _c("overtime_speed", 1.0)
	return 1.0


## Laune-Abzug durch Schichtarbeit (negativ, 0 ohne).
func shift_mood(s) -> float:
	return _c("shift_mood", -20.0) if s.is_adult() and shift(s.job, s.world) else 0.0


## Laune-Gründe aus der Verwaltung (SettlerMind._update_mood).
func mood_reasons(s) -> Array:
	var r := []
	if not s.is_adult():
		return r
	if shift(s.job, s.world):
		r.append([tr("Schichtarbeit"), _c("shift_mood", -20.0)])
	if protesting(s.job) and active_on(s.world):
		r.append([tr("Protestiert gegen zu lange Überstunden"), _c("protest_mood", -15.0)])
	return r


## Werkstätten einer Art, die gerade arbeiten könnten (fertig, nicht angehalten, nichts fehlt).
func _workable(w, kind: String) -> Array:
	return w.buildings.filter(func(b): return b.complete and b.prod_def().get("job", "") == kind and b.prod_blocker() == "")


## Soll ein Siedler aus einem anderen Beruf in einer leeren Werkstatt dieser Art einspringen?
## Ja, wenn mehr Werkstätten mit Vertretung leer stehen, als Fachkräfte gerade da sind.
func needs_standin(w, kind: String) -> bool:
	if not active_on(w):
		return false
	var job: String = KIND_JOB.get(kind, "")
	var busy := {}
	var idle := 0
	for b in _workable(w, kind):
		for id in b.occupants:
			busy[id] = true
		if b.adm and b.occupants.is_empty():
			idle += 1
	if idle == 0:
		return false
	var avail := 0
	for s in w.settlers:
		if s.job == job and s.is_adult() and not s.sleeping and not s.on_break() and not s.mind.needs_bed() \
				and not busy.has(s.id):
			avail += 1
	return idle > avail


## Fehlendes Personal je Werkstattberuf auf der Insel der Verwaltung: [[Beruf, Werkstätten, Leute], ...].
func shortages() -> Array:
	var out := []
	var w = admin_world()
	if w == null:
		return out
	for kind in KIND_JOB:
		var job: String = KIND_JOB[kind]
		var n_b: int = _workable(w, kind).size()
		var n_p: int = w.settlers.filter(func(s): return s.job == job and s.is_adult()).size()
		if n_b > n_p:
			out.append([job, n_b, n_p])
	return out


# ---------------------------------------------------------------- Ändern
## Nur ein Verwalter: s wird Verwalter, ein bisheriger wird "Frei" (aus Settler.set_job).
func claim_manager(s) -> void:
	for w in Sea.all_worlds():
		for o in w.settlers:
			if o != s and o.job == JOB:
				o.job = "frei"
				o.busy = {}
				o.abort_plan()
				Game.notify_at(w, tr("%s ist jetzt Verwalter, %s ist wieder frei.") % [s.display_name, o.display_name], "wissen", "verwaltung")
	changed.emit()


## Überstunden an- oder abschalten. Gibt einen Fehlertext zurück ("" = erledigt).
func set_overtime(job: String, on: bool, by_admin := false) -> String:
	_mark_auto(job, by_admin, on)
	var o := _order(job).duplicate()
	if on:
		if protesting(job):
			return tr("Im Beruf %s wird noch gegen die letzten Überstunden protestiert.") % _name(job)
		if not bool(o.ot):
			o.ot = true
			o.since = Game.time_days
	else:
		o.ot = false
	orders[job] = o
	changed.emit()
	return ""


func set_shift(job: String, on: bool, by_admin := false) -> void:
	_mark_auto(job, by_admin, on)
	var o := _order(job).duplicate()
	o.sh = on
	orders[job] = o
	changed.emit()


## Wer zuletzt eine Anordnung trifft, dem gehört sie: der Spieler übernimmt sie, der Verwalter markiert sie.
## Schaltet der Spieler etwas ab, lässt der Verwalter den Beruf ein Jahr in Ruhe (_hold).
func _mark_auto(job: String, by_admin: bool, on: bool) -> void:
	if by_admin:
		auto_orders[job] = true
	else:
		auto_orders.erase(job)
		if not on:
			_hold[job] = Game.time_days + Seasons.year_days()


func self_orders_unlocked() -> bool:
	return Game.max_tier() >= SELF_ORDER_TIER


func self_orders_on() -> bool:
	return self_orders and self_orders_unlocked()


## Neuzuweisung freigeschaltet (ab dem Mittelalter)?
func auto_unlocked() -> bool:
	return Game.current_age() >= AUTO_AGE


func auto_on() -> bool:
	return Powers.on("nachbesetzen")


## Automatische Neuzuweisung (ab dem Mittelalter): Stirbt ein Siedler mit Beruf, übernimmt ein freier
## Erwachsener auf derselben Insel den Beruf (einer mit passendem Talent zuerst). Gibt es keinen,
## lernt das nächste Kind, das erwachsen wird, den Beruf. Nur auf der Insel der Verwaltung.
## Stirbt der Verwalter selbst, bekommt ein Freier auf der Insel der Verwaltung den Posten (josh 2026-10-17).
func _on_settler_died(s, _cause: String) -> void:
	if not auto_on() or s == null or not s.is_adult() or s.job == "frei":
		return
	if not _covers(s.world, s.job) or not Data.jobs.has(s.job):
		return
	if s.job == JOB and local_manager() != null:
		return  # es gibt schon einen neuen Verwalter
	var pick = null
	for o in s.world.settlers:
		if o == s or not o.is_adult() or o.job != "frei" or not JobDesk.may(o, "verwalter"):
			continue
		if pick == null or (TalentInfo.job_match(o.mind, s.job) and not TalentInfo.job_match(pick.mind, s.job)):
			pick = o
	if pick == null:
		if Powers.mode_of("nachbesetzen") != Powers.SELBST:
			return
		pending_jobs.append(s.job)
		Game.notify_at(s.world, tr("Für den Beruf %s von %s gibt es keinen freien Siedler. Das nächste Kind, das erwachsen wird, lernt ihn.") % [_name(s.job), s.display_name], "wissen", "verwaltung")
		changed.emit()
		return
	Powers.decide("nachbesetzen", "nach:%d" % int(pick.id), tr("%s übernimmt den Beruf %s von %s.") % [pick.display_name, _name(s.job), s.display_name],
		{"kind": "job", "island": int(s.world.island_id), "sid": int(pick.id), "job": s.job})
	changed.emit()


## Ein Kind ist erwachsen geworden: es lernt den ältesten offenen Beruf eines Verstorbenen.
func on_grown_up(s) -> bool:
	if pending_jobs.is_empty() or not auto_on() or not _covers(s.world, pending_jobs[0]):
		return false
	var job: String = pending_jobs.pop_front()
	if not Data.jobs.has(job) or (job == JOB and local_manager() != null) or not JobDesk.assign(s, job, "verwalter"):
		return false
	Game.notify_at(s.world, tr("%s ist erwachsen und lernt den Beruf %s.") % [s.display_name, _name(job)], "wissen", "verwaltung")
	changed.emit()
	return true


## Gilt die Neuzuweisung für diesen Beruf auf dieser Insel? Den Verwalterposten besetzt sie auch ohne
## Verwalter, solange die Verwaltung auf der Insel steht.
func _covers(w, job: String) -> bool:
	if job == JOB:
		return w != null and w == admin_world()
	return active_on(w)


func _name(job: String) -> String:
	return Data.jobs.get(job, {}).get("name", job)


# ---------------------------------------------------------------- Ablauf
func _process(_delta: float) -> void:
	if Game.is_over or Game.world == null or Game.time_days < _next_tick:
		return
	_next_tick = Game.time_days + _c("check_every", 0.25)
	_tick()


func _tick() -> void:
	# Überstunden länger als ein Jahr am Stück: Protest
	var year := Seasons.year_days() * _c("overtime_years", 1.0)
	for job in orders.keys():
		var o := _order(job)
		if bool(o.ot) and Game.time_days - float(o.since) >= year:
			orders[job].ot = false
			protest[job] = Game.time_days + _c("protest_days", 6.0)
			Game.notify(tr("Die Leute im Beruf %s hören unter Protest mit den Überstunden auf. Ihre Laune sinkt.") % _name(job), "wissen", "verwaltung")
			protest_started.emit(job, tr("Die Leute im Beruf %s protestieren gegen zu lange Überstunden.") % _name(job))
			changed.emit()
	# Seit 2026-10-29 keine Meldungen über fehlende Werkstatt-Leute mehr: Überstunden und Schichten ordnet
	# der Verwalter nur noch im Notfall an (Steward._emergency, Befugnis „Überstunden im Notfall“).


## Eigene Anordnungen des Verwalters pflegen: Überstunden vor dem Protest (nach 80 % der erlaubten Zeit) in
## Schichtarbeit umwandeln; fehlt im Beruf zwei Meldezeiten lang niemand mehr, alles beenden.
func _self_order_tick(m) -> void:
	var year := Seasons.year_days() * _c("overtime_years", 1.0)
	for job in auto_orders.keys():
		var o := _order(job)
		var who := tr("Verwalter %s") % m.display_name
		if Game.time_days - float(_short_at.get(job, -99.0)) > 2.0 * _c("report_every", 2.0):
			set_overtime(job, false, true)
			set_shift(job, false, true)
			auto_orders.erase(job)
			Game.notify(who + ": " + tr("Im Beruf %s fehlt niemand mehr. Er beendet Überstunden und Schichtarbeit.") % _name(job), "wissen", "verwaltung")
		elif bool(o.ot) and Game.time_days - float(o.since) >= year * 0.8:
			set_overtime(job, false, true)
			_ot_rest[job] = Game.time_days + year
			if not bool(o.sh):
				set_shift(job, true, true)
			Game.notify(who + ": " + tr("Damit im Beruf %s niemand protestiert, beendet er die Überstunden und ordnet Schichtarbeit an.") % _name(job), "wissen", "verwaltung")


# ---------------------------------------------------------------- Statistik (josh 2026-10-20)
## Erzeugte Waren je Jahr (alle Inseln): {"<Jahr>": {Ware: Menge}}. Gezählt wird beim Sammeln, Ernten,
## Jagen und in den Werkstätten (Settler), nicht beim Umladen, Handel oder Belohnungen.
var produced: Dictionary = {}


func note_produced(res: String, n: int, w = null) -> void:
	if n <= 0 or res == "":
		return
	var key := str(Seasons.year())
	if not produced.has(key):
		produced[key] = {}
		for k in produced.keys():  # die letzten 5 Jahre und das laufende aufheben (josh 2026-10-28)
			if int(k) < Seasons.year() - 5:
				produced.erase(k)
	var isl := _isl(w)
	if not produced[key].has(isl):
		produced[key][isl] = {}
	produced[key][isl][res] = int(produced[key][isl].get(res, 0)) + n
	Steward.note_made(res, n, w)


static func _isl(w) -> String:
	if w == null or not is_instance_valid(w):
		w = Sea.main_world()
	return str(w.island_id) if w else "0"


## Erzeugte Menge je Ware im Jahr y (Seasons.year()) auf der Insel w (null: Hauptinsel).
# ---------------------------------------------------------------- Log (josh 2026-10-28)
## Entscheidungen von Verwalter, Automat, KI und Droiden: jede Meldung der Art „verwaltung“ (Game.notify),
## auch wenn der Spieler diese Meldungen ausgeschaltet hat. [Spielzeit in Tagen, Insel, Text], neueste zuletzt.
const LOG_MAX := 300
var log_entries: Array = []


func add_log(text: String) -> void:
	log_entries.append([Game.time_days, "", text])
	if log_entries.size() > LOG_MAX:
		log_entries = log_entries.slice(log_entries.size() - LOG_MAX)


func produced_in(y: int, w = null) -> Dictionary:
	return produced.get(str(y), {}).get(_isl(w), {})


## Auslastung je Beruf auf der Insel w (null: alle Inseln): {job: [Leute, im Beruf %, hilft aus %, nichts zu tun %]},
## Anteile -1 solange zu wenig gemessen ist (Settler.busy_shares).
func job_load(w = null) -> Dictionary:
	var out := {}
	for wo in ([w] if w != null else Sea.all_worlds()):
		for s in wo.settlers:
			if not s.is_adult() or s.job == "frei":
				continue
			if not out.has(s.job):
				out[s.job] = [0, 0.0, 0.0, 0.0, 0]
			out[s.job][0] += 1
			var sh: Array = s.busy_shares()
			if not sh.is_empty():
				for i in 3:
					out[s.job][i + 1] += float(sh[i])
				out[s.job][4] += 1
	var res := {}
	for j in out:
		var n := int(out[j][4])
		res[j] = [int(out[j][0])]
		for i in 3:
			res[j].append(roundi(out[j][i + 1] / n) if n > 0 else -1)
	return res


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	produced = {}
	log_entries = []
	orders = {}
	protest = {}
	reported = {}
	auto_reassign = false
	pending_jobs = []
	self_orders = true
	auto_orders = {}
	_short_at = {}
	_ot_rest = {}
	_hold = {}
	_next_tick = 0.0
	changed.emit()


func _on_save(d: Dictionary) -> void:
	d["admin"] = {"orders": orders.duplicate(true), "protest": protest.duplicate(), "reported": reported.duplicate(), "auto": auto_reassign, "pending": pending_jobs.duplicate(), "produced": produced.duplicate(true), "self_orders": self_orders, "auto_orders": auto_orders.keys(), "log": log_entries.duplicate(true)}


func _on_load(data: Dictionary, old_rules: int) -> void:
	_on_reset()
	if old_rules < 2:
		Game.rules_lines.append(tr("Schichtarbeit in der Verwaltung bringt doppelt so viel, Überstunden anderthalbmal so viel. Nachts brennt in den Werkstätten Licht, und die Nacht vergeht dann nicht schneller."))
	var e = data.get("admin", null)
	if not (e is Dictionary):
		return
	auto_reassign = bool(e.get("auto", false))
	self_orders = bool(e.get("self_orders", true))
	var ao = e.get("auto_orders", [])
	if ao is Array:
		for j in ao:
			if Data.jobs.has(str(j)):
				auto_orders[str(j)] = true
	var lg = e.get("log", [])
	if lg is Array:
		for it in lg:
			if it is Array and it.size() >= 3:
				log_entries.append([float(it[0]), str(it[1]), str(it[2])])
	var pr = e.get("produced", {})
	if pr is Dictionary:
		for y in pr:
			if pr[y] is Dictionary:
				produced[str(y)] = {}
				for k in pr[y]:
					if pr[y][k] is Dictionary:  # je Insel (seit 1.0.85)
						produced[str(y)][str(k)] = {}
						for r in pr[y][k]:
							produced[str(y)][str(k)][str(r)] = int(pr[y][k][r])
					else:  # 1.0.84 zählte alle Inseln zusammen: der Hauptinsel zuschreiben
						var m := _isl(null)
						if not produced[str(y)].has(m):
							produced[str(y)][m] = {}
						produced[str(y)][m][str(k)] = int(pr[y][k])
	var pj = e.get("pending", [])
	if pj is Array:
		pending_jobs = pj.map(func(j): return str(j)).filter(func(j): return Data.jobs.has(j))
	var o = e.get("orders", {})
	if o is Dictionary:
		for job in o:
			if Data.jobs.has(str(job)) and o[job] is Dictionary:
				orders[str(job)] = {"ot": bool(o[job].get("ot", false)), "since": float(o[job].get("since", 0.0)),
					"sh": bool(o[job].get("sh", false))}
	for key in ["protest", "reported"]:
		var src = e.get(key, {})
		if src is Dictionary:
			var dst: Dictionary = protest if key == "protest" else reported
			for job in src:
				dst[str(job)] = float(src[job])
	changed.emit()


## Selbsttest --admintest=1 (scripts/autoload/admin_test.gd).
func autotest_setup(args: Dictionary, main) -> void:
	if args.has("admintest"):
		await AdminTest.run(main)
	if args.has("adminmeasure"):  # Ertrag: normal | ot | shift[,Tage]
		await AdminTest.measure(main, str(args.adminmeasure))
	if args.has("strolltest"):  # Spaziergang am Ufer (josh 2026-10-20)
		await AdminTest.stroll(main)
	if args.has("adminshot"):  # Bildschirmfoto: office | shifts | night | stats | workshop | proposal (mit --shot)
		AdminTest.shot(main, str(args.adminshot))


## Hilfetext (Menü > Hilfe), wie Extras.help_text.
func help_text() -> String:
	return "\n\n" + tr("[b]Verwaltung[/b]\nMit Gelehrsamkeit baust du eine Verwaltung (nur eine) und machst einen Siedler zum Verwalter (nur einer). Er arbeitet nur, wenn er auf der Insel der Verwaltung lebt, und alles gilt nur für diese Insel. Dann lässt sich in jeder Werkstatt die Vertretung einschalten: Fehlt die Fachkraft gerade (Pause, Schlaf, Essen), springt ein Siedler ein, der sonst nichts zu tun hat. Fehlen für einen Beruf Leute, meldet sich der Verwalter und schlägt Überstunden oder Schichtarbeit vor (in der Verwaltung an- und abzuschalten). Überstunden: die Arbeiter fangen 2 Stunden früher an, hören 2 Stunden später auf und machen keine Pausen; das bringt etwa anderthalbmal so viel. Nach einem Jahr am Stück hören sie unter Protest auf und ihre Laune sinkt. Schichtarbeit: die Werkstätten laufen rund um die Uhr (nachts brennt dort Licht), das bringt etwa doppelt so viel; Schichtarbeiter sind eine Laune-Stufe schlechter gelaunt. Solange nachts gearbeitet wird, vergeht die Nacht nicht schneller.")
