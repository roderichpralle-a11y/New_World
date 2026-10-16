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
			if b.type == OFFICE and b.complete:
				return b
	return null


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
	return w != null and active() and w == admin_world()


## Gibt es dieses Gebäude schon (fertig oder als Baustelle), ohne ignore (beim Verschieben)?
func exists(type: String, ignore = null) -> bool:
	for w in Sea.all_worlds():
		for b in w.buildings:
			if b.type == type and b != ignore:
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
func set_overtime(job: String, on: bool) -> String:
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


func set_shift(job: String, on: bool) -> void:
	var o := _order(job).duplicate()
	o.sh = on
	orders[job] = o
	changed.emit()


## Automatische Neuzuweisung: Stirbt ein Siedler mit Beruf, übernimmt ein freier Erwachsener auf
## derselben Insel den Beruf (einer mit passendem Talent zuerst). Nur auf der Insel der Verwaltung.
func _on_settler_died(s, _cause: String) -> void:
	if not auto_reassign or s == null or not s.is_adult() or s.job in ["frei", JOB]:
		return
	if not active_on(s.world) or not Data.jobs.has(s.job):
		return
	var pick = null
	for o in s.world.settlers:
		if o == s or not o.is_adult() or o.job != "frei":
			continue
		if pick == null or (TalentInfo.job_match(o.mind, s.job) and not TalentInfo.job_match(pick.mind, s.job)):
			pick = o
	if pick == null:
		return
	pick.set_job(s.job)
	Game.notify_at(s.world, tr("%s übernimmt den Beruf %s von %s.") % [pick.display_name, _name(s.job), s.display_name], "wissen", "verwaltung")
	changed.emit()


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
	if not active():
		return
	var m = local_manager()
	for e in shortages():
		var job: String = e[0]
		if Game.time_days - float(reported.get(job, -99.0)) < _c("report_every", 2.0):
			continue
		reported[job] = Game.time_days
		var text := tr("Verwalter %s: Im Beruf %s fehlen Leute (Werkstätten: %d, Leute: %d).") % [
			m.display_name, _name(job), int(e[1]), int(e[2])]
		if ordered(job, "ot") and ordered(job, "sh"):
			Game.notify(text + " " + tr("Teile mehr Siedler für diesen Beruf ein."), "wissen", "verwaltung")
			continue
		Game.notify(text + " " + tr("Vorschlag: Überstunden oder Schichtarbeit."), "wissen", "verwaltung")
		proposal.emit(job, text)


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	orders = {}
	protest = {}
	reported = {}
	auto_reassign = false
	_next_tick = 0.0
	changed.emit()


func _on_save(d: Dictionary) -> void:
	d["admin"] = {"orders": orders.duplicate(true), "protest": protest.duplicate(), "reported": reported.duplicate(), "auto": auto_reassign}


func _on_load(data: Dictionary, old_rules: int) -> void:
	_on_reset()
	if old_rules < 2:
		Game.rules_lines.append(tr("Schichtarbeit in der Verwaltung bringt doppelt so viel, Überstunden anderthalbmal so viel. Nachts brennt in den Werkstätten Licht, und die Nacht vergeht dann nicht schneller."))
	var e = data.get("admin", null)
	if not (e is Dictionary):
		return
	auto_reassign = bool(e.get("auto", false))
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
	if args.has("adminshot"):  # Bildschirmfoto: office | night | workshop | proposal (mit --shot)
		AdminTest.shot(main, str(args.adminshot))


## Hilfetext (Menü > Hilfe), wie Extras.help_text.
func help_text() -> String:
	return "\n\n" + tr("[b]Verwaltung[/b]\nMit Gelehrsamkeit baust du eine Verwaltung (nur eine) und machst einen Siedler zum Verwalter (nur einer). Er arbeitet nur, wenn er auf der Insel der Verwaltung lebt, und alles gilt nur für diese Insel. Dann lässt sich in jeder Werkstatt die Vertretung einschalten: Fehlt die Fachkraft gerade (Pause, Schlaf, Essen), springt ein Siedler ein, der sonst nichts zu tun hat. Fehlen für einen Beruf Leute, meldet sich der Verwalter und schlägt Überstunden oder Schichtarbeit vor (in der Verwaltung an- und abzuschalten). Überstunden: die Arbeiter fangen 2 Stunden früher an, hören 2 Stunden später auf und machen keine Pausen; das bringt etwa anderthalbmal so viel. Nach einem Jahr am Stück hören sie unter Protest auf und ihre Laune sinkt. Schichtarbeit: die Werkstätten laufen rund um die Uhr (nachts brennt dort Licht), das bringt etwa doppelt so viel; Schichtarbeiter sind eine Laune-Stufe schlechter gelaunt. Solange nachts gearbeitet wird, vergeht die Nacht nicht schneller.")
