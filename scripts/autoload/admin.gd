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
##   Steinmetz) die Werkstätten, die arbeiten könnten, und die Erwachsenen mit dem Beruf. Gibt es mehr
##   Werkstätten als Leute, meldet er sich (höchstens alle report_every Tage je Beruf) und schlägt
##   Überstunden oder Schichtarbeit vor (Signal proposal, Fenster in AdminInfo).
## - Anordnungen je Beruf:
##   (orders[job] = {ot: bool, since: Tag, sh: bool})
##   Überstunden: keine Freizeitpausen mehr (Settler._think). Dauern sie overtime_years Jahre am Stück,
##   hören die Arbeiter unter Protest auf: Überstunden aus, protest_days lang protest_mood Laune und
##   so lange keine neuen Überstunden für diesen Beruf.
##   Schichtarbeit: jede Nacht arbeitet die Hälfte der Leute des Berufs durch (wechselt jede Nacht,
##   night_worker), und alle mit dem Beruf haben shift_mood Laune (eine Laune-Stufe sind 20 Punkte).
## Spielstand: oben "admin" = {orders, protest, reported} (Game.state_save/state_load); Building.adm
## steht im Gebäude ("adm"). Alte Spielstände: keine Anordnungen.

signal changed
signal proposal(job: String, text: String)
## Die Leute eines Berufs hören unter Protest mit den Überstunden auf (text: übersetzter Grund, ProtestVideo).
signal protest_started(job: String, text: String)

const OFFICE := "verwaltung"
const JOB := "verwalter"
## Werkstattart (production.job) -> Beruf
const KIND_JOB := {"kueche": "koch", "handwerk": "handwerker", "stein": "steinmetz"}

var cfg: Dictionary = {}
var orders: Dictionary = {}    # Beruf -> {"ot": Überstunden, "since": seit Tag, "sh": Schichtarbeit}
var protest: Dictionary = {}   # Beruf -> Protest bis Tag
var reported: Dictionary = {}  # Beruf -> letzte Meldung (Tag)
var _next_tick := 0.0


func _ready() -> void:
	cfg = Data._load("admin")
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)


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


func active() -> bool:
	return office() != null and manager() != null


## Gibt es dieses Gebäude schon (fertig oder als Baustelle), ohne ignore (beim Verschieben)?
func exists(type: String, ignore = null) -> bool:
	for w in Sea.all_worlds():
		for b in w.buildings:
			if b.type == type and b != ignore:
				return true
	return false


func _order(job: String) -> Dictionary:
	return orders.get(job, {"ot": false, "since": 0.0, "sh": false})


func overtime(job: String) -> bool:
	return bool(_order(job).ot) and active()


func shift(job: String) -> bool:
	return bool(_order(job).sh) and active()


## Angeordnet (auch wenn die Verwaltung gerade nicht arbeitet)?
func ordered(job: String, what: String) -> bool:
	return bool(_order(job).ot) if what == "ot" else bool(_order(job).sh)


func protesting(job: String) -> bool:
	return Game.time_days < float(protest.get(job, 0.0))


## Arbeitet der Siedler heute Nacht durch (Schichtarbeit, jede Nacht die andere Hälfte)?
func night_worker(s) -> bool:
	if not s.is_adult() or not shift(s.job):
		return false
	var night := int(floor(Game.time_days - Seasons.night_start()))
	return (int(s.id) + night) % 2 == 0


## Laune-Gründe aus der Verwaltung (SettlerMind._update_mood).
func mood_reasons(s) -> Array:
	var r := []
	if not s.is_adult():
		return r
	if shift(s.job):
		r.append([tr("Schichtarbeit"), _c("shift_mood", -20.0)])
	if protesting(s.job):
		r.append([tr("Protestiert gegen zu lange Überstunden"), _c("protest_mood", -15.0)])
	return r


## Werkstätten einer Art, die gerade arbeiten könnten (fertig, nicht angehalten, nichts fehlt).
func _workable(w, kind: String) -> Array:
	return w.buildings.filter(func(b): return b.complete and b.prod_def().get("job", "") == kind and b.prod_blocker() == "")


## Soll ein Siedler aus einem anderen Beruf in einer leeren Werkstatt dieser Art einspringen?
## Ja, wenn mehr Werkstätten mit Vertretung leer stehen, als Fachkräfte gerade da sind.
func needs_standin(w, kind: String) -> bool:
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


## Fehlendes Personal je Werkstattberuf über alle Inseln: [[Beruf, Werkstätten, Leute], ...].
func shortages() -> Array:
	var out := []
	for kind in KIND_JOB:
		var job: String = KIND_JOB[kind]
		var n_b := 0
		var n_p := 0
		for w in Sea.all_worlds():
			n_b += _workable(w, kind).size()
			n_p += w.settlers.filter(func(s): return s.job == job and s.is_adult()).size()
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
	var m = manager()
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
	_next_tick = 0.0
	changed.emit()


func _on_save(d: Dictionary) -> void:
	d["admin"] = {"orders": orders.duplicate(true), "protest": protest.duplicate(), "reported": reported.duplicate()}


func _on_load(data: Dictionary, _old_rules: int) -> void:
	_on_reset()
	var e = data.get("admin", null)
	if not (e is Dictionary):
		return
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
	if args.has("adminshot"):  # Bildschirmfoto: office | workshop | proposal (mit --shot)
		AdminTest.shot(main, str(args.adminshot))


## Hilfetext (Menü > Hilfe), wie Extras.help_text.
func help_text() -> String:
	return "\n\n" + tr("[b]Verwaltung[/b]\nMit Gelehrsamkeit baust du eine Verwaltung (nur eine) und machst einen Siedler zum Verwalter (nur einer). Dann lässt sich in jeder Werkstatt die Vertretung einschalten: Fehlt die Fachkraft gerade (Pause, Schlaf, Essen), springt ein Siedler ein, der sonst nichts zu tun hat. Fehlen für einen Beruf Leute, meldet sich der Verwalter und schlägt Überstunden oder Schichtarbeit vor (in der Verwaltung an- und abzuschalten). Überstunden: keine Pausen mehr; nach einem Jahr am Stück hören die Arbeiter unter Protest auf und ihre Laune sinkt. Schichtarbeit: jede Nacht arbeitet die Hälfte durch; Schichtarbeiter sind eine Laune-Stufe schlechter gelaunt.")
