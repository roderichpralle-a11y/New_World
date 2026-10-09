extends Node
## Angekündigte Ereignisse (Regeln ab Version 2, "Herausforderung"): Dürre, Ratten, Brand, Seuche,
## Sturmflut und ab dem Mittelalter Piraten. Alle Zahlen und Texte stehen in data/events.json.
##
## Ablauf je besiedelter Insel: frühestens ab Spieltag `start_day` (13 = Jahr 2), nicht während der
## Einführung, mit mindestens `min_settlers` Siedlern. Eine neue oder gerade geladene Insel hat
## `grace_days` Schonzeit, nach dem Ende eines Ereignisses kommt das nächste `interval` Tage später.
## Zwischen zwei Ankündigungen (alle Inseln zusammen) liegen mindestens `global_gap` Tage. Je Insel
## höchstens ein Ereignis, nie zweimal hintereinander dieselbe Art. Angekündigt wird `lead` Tage vorher
## (Meldung mit Gegenmittel, ob es schon da ist), eintreten tut es tagsüber. Die Art wird nach den
## Gewichten der Jahreszeit beim Eintritt gewählt (heißer Sommer: Dürre und Brand doppelt, Seuche nicht
## in einem harten Winter oder Eiswinter). Stärke power = clamp(0,5 + 0,1*(Jahr-2) + Siedler/30, 0,5, 2,5).
## Drei Meldungen je Ereignis (Ankündigung, Eintritt, Ende); bei sofortigen Ereignissen (Ratten, Brand,
## Sturmflut) stehen Eintritt und Ergebnis in einer Meldung. Übersteht die Insel Dürre, Seuche oder
## Piraten ohne Tote, kommt ein Einwanderer (ohne freien Wohnplatz: Waren je Zeitalter).
##
## Für andere Systeme: busy(w) (Piraten angekündigt oder da, für den Händler), growth_factor(type, w)
## (Dürre, über Seasons.growth), sickness_factor(w) und epidemic_illness(w) (Seuche, SettlerMind),
## event_of(w), chip() und describe() für die Anzeige. Signal changed.
##
## Spielstand: oben "events" = {islands: {"<id>": {next, last, ev}}, last, seq} (Game.state_save /
## state_load). Piraten werden nicht als Tiere gespeichert: ev.left Piraten landen nach dem Laden neu.

signal changed  # angekündigt, eingetreten oder vorbei

const SPRING := 0
const SUMMER := 1
const WINTER := 3

var cfg: Dictionary = {}
var enabled := true  # Testhilfe --noevents=1
## Insel-ID (Text) -> {next: time_days der frühesten nächsten Ankündigung, last: letzte Art, ev: null
## oder {type, at, strike, end, power, deaths, struck, ill, count, left, kills, landing, loot}}
var islands: Dictionary = {}
var last_announce: float = -99.0  # time_days der letzten Ankündigung (alle Inseln)
var seq: int = 0  # Nummer des nächsten Ereignisses (Zufall)
var last_reward := ""  # Art der letzten Belohnung ("settler"/"goods", für Tests)

var _next_tick := 0.0
var _drought: Dictionary = {}  # World -> Wachstumsfaktor während einer Dürre
var _sick: Dictionary = {}  # World -> Krankheitsfaktor während einer Seuche
var _ill: Dictionary = {}  # World -> Krankheit der Seuche
var _raiders: Dictionary = {}  # Insel-ID -> [Raider]
var _ships: Dictionary = {}  # Insel-ID -> Sprite2D (Piratenschiff)
var _fires: Array = []  # [World, Building, Restzeit in Sekunden] (nur Bild)
var _fx_t := 0.0


func _ready() -> void:
	cfg = Data._load("events")
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)
	Game.settler_died.connect(_on_died)


func _c(key: String, default):
	return cfg.get(key, default)


func type_def(t: String) -> Dictionary:
	return cfg.get("types", {}).get(t, {})


func type_name(t: String) -> String:
	return str(type_def(t).get("name", t))


func raider_def() -> Dictionary:
	return cfg.get("raider", {})


## Spielzeit (time_days), ab der Ereignisse angekündigt werden (start_day ist ein Spieltag ab 1).
func start_time() -> float:
	return float(_c("start_day", 13)) - 1.0


func in_tutorial() -> bool:
	return int(Game.goals.get("tut", 0)) < Data.goals.get("tutorial", []).size()


func _world(id: int):
	var w = Sea.worlds.get(id)
	if w == null or not is_instance_valid(w) or Sea.meta(id).get("state", "") != "settled":
		return null
	return w


# ---------------------------------------------------------------- Abfragen
## Ereignis der Insel (angekündigt oder laufend) oder {}.
func event_of(w) -> Dictionary:
	if w == null or not is_instance_valid(w):
		return {}
	var st = islands.get(str(w.island_id))
	if st is Dictionary and st.get("ev") is Dictionary:
		return st.ev
	return {}


## Sind auf dieser Insel Piraten angekündigt oder da? (Der Händler meidet die Insel dann.)
func busy(w) -> bool:
	return str(event_of(w).get("type", "")) == "piraten"


## Faktor auf das Wachstum einer Rohstoffquelle oder eines Felds (Seasons.growth nimmt das Kleinere
## aus Klima und diesem Wert). Dürre: 0,4 (mit Bewässerung 0,7), sonst 1.
func growth_factor(type: String, w) -> float:
	if _drought.is_empty() or w == null:
		return 1.0
	var f = _drought.get(w)
	if f == null or not type in type_def("duerre").get("growth_types", []):
		return 1.0
	return float(f)


## Faktor auf das Krankheitsrisiko (SettlerMind._maybe_get_sick). Seuche: 1 + (m - 1) / Heilkunst.
func sickness_factor(w) -> float:
	if _sick.is_empty() or w == null:
		return 1.0
	return float(_sick.get(w, 1.0))


## Krankheit der laufenden Seuche auf dieser Insel ("" = keine).
func epidemic_illness(w) -> String:
	if _ill.is_empty() or w == null:
		return ""
	return str(_ill.get(w, ""))


## Anteil, mit dem eine neue Krankheit während einer Seuche die Seuchen-Krankheit ist.
func forced_share() -> float:
	return float(type_def("seuche").get("forced_share", 0.7))


## Alle Ereignisse: [[World, ev], ...], die aktive Insel zuerst, laufende vor angekündigten.
func all_events() -> Array:
	var out := []
	for k in islands:
		var ev = islands[k].get("ev")
		var w = _world(int(k))
		if ev is Dictionary and w != null:
			out.append([w, ev])
	out.sort_custom(func(a, b):
		var ka := (0 if a[0] == Game.world else 2) + (0 if a[1].get("struck", false) else 1)
		var kb := (0 if b[0] == Game.world else 2) + (0 if b[1].get("struck", false) else 1)
		return ka < kb)
	return out


## Für den Knopf oben: {} oder {type, icon, name, struck, hours, w, ev}.
func chip() -> Dictionary:
	var all := all_events()
	if all.is_empty():
		return {}
	var w = all[0][0]
	var ev: Dictionary = all[0][1]
	var t := str(ev.type)
	var struck := bool(ev.get("struck", false))
	var until := float(ev.end) if struck else float(ev.strike)
	return {"type": t, "icon": str(type_def(t).get("icon", "ereignis")), "name": type_name(t), "struck": struck,
		"hours": maxi(0, int(ceil((until - Game.time_days) * 24.0))), "w": w, "ev": ev, "more": all.size() - 1}


func _hours(until: float) -> int:
	return maxi(1, int(ceil((until - Game.time_days) * 24.0)))


## Text zum Antippen des Knopfs: alle Ereignisse mit Insel, Zeit und Gegenmittel.
func describe_all() -> String:
	var parts := []
	for e in all_events():
		parts.append(describe(e[0], e[1]))
	return " ".join(parts)


func describe(w, ev: Dictionary) -> String:
	var t := str(ev.type)
	var isl := Sea.island_name(w)
	if not bool(ev.get("struck", false)):
		return tr("%s auf %s in %d Stunden: %s %s") % [type_name(t), isl, _hours(float(ev.strike)), _what(t, ev), _counter(w, t)]
	match t:
		"duerre":
			return tr("Dürre auf %s, noch %d Stunden: Felder, Obstgärten, Beeren und Pilze wachsen nur mit %d %% der Kraft.") % [isl, _hours(float(ev.end)), roundi(_drought_factor() * 100.0)]
		"seuche":
			return tr("Seuche auf %s, noch %d Stunden: Siedler werden %s-mal so oft krank, meist an %s.") % [isl, _hours(float(ev.end)), _num(_sick_factor(ev)), _ill_name(str(ev.get("ill", "")))]
		"piraten":
			return tr("Piraten auf %s: %d an Land, %d vertrieben. Spätestens in %d Stunden segeln sie ab.") % [isl, int(ev.get("left", 0)), int(ev.get("kills", 0)), _hours(float(ev.end))]
	return "%s: %s" % [type_name(t), isl]


func _num(f: float) -> String:
	var s := "%.1f" % f
	return s.replace(".", ",") if Loc.language == "de" else s


func _ill_name(k: String) -> String:
	return str(Data.ppl("illnesses").get(k, {}).get("name", k))


## Ankündigungstext ohne Zeit: was passiert und der Rat dazu.
func _what(t: String, ev: Dictionary) -> String:
	var d := type_def(t)
	var s := "%s %s" % [d.get("text", ""), d.get("hint", "")]
	if t == "seuche":
		s += " " + tr("Meist trifft es: %s.") % _ill_name(str(ev.get("ill", "")))
	return s


## Gegenmittel und ob es schon da ist ("Hilft: Bewässerung (erforscht).").
func _counter(w, t: String) -> String:
	var c: Dictionary = type_def(t).get("counter", {})
	if c.has("tech") and Data.techs.has(str(c.tech)):
		var tn := str(Data.techs[str(c.tech)].name)
		if Game.is_researched(str(c.tech)):
			return tr("Hilft: %s (erforscht).") % tn
		return tr("Hilft: %s (noch nicht erforscht).") % tn
	if c.has("building") and Data.buildings.has(str(c.building)):
		var bt := str(c.building)
		var bn := str(Data.buildings[bt].name)
		if w != null and w.buildings.any(func(b): return b.complete and b.type == bt):
			return tr("Hilft: %s (steht schon).") % bn
		if Game.is_unlocked(bt):
			return tr("Hilft: %s (noch nicht gebaut).") % bn
		var req := str(Data.buildings[bt].get("requires", ""))
		if Data.techs.has(req):
			return tr("Hilft: %s (braucht die Forschung %s).") % [bn, Data.techs[req].name]
	return ""


# ---------------------------------------------------------------- Ablauf
func _process(delta: float) -> void:
	if not _fires.is_empty():
		_burn(delta)
	if not enabled or Game.world == null or Game.is_over or Game.speed <= 0:
		return
	if Game.time_days < _next_tick:
		return
	_next_tick = Game.time_days + float(_c("tick_days", 0.05))
	tick()


func tick() -> void:
	var t := Game.time_days
	for k in islands.keys():
		if _world(int(k)) == null:
			_forget(int(k))
	var due := []
	for w in Sea.all_worlds():
		if w.settlers.is_empty() or Sea.meta(int(w.island_id)).get("state", "") != "settled":
			continue
		var key := str(w.island_id)
		if not islands.has(key):
			islands[key] = {"next": maxf(t + float(_c("grace_days", 8.0)), start_time()), "last": "", "ev": null}
		var st: Dictionary = islands[key]
		if st.get("ev") is Dictionary:
			_advance(w, st, st.ev, t)
		elif t >= float(st.next):
			due.append([float(st.next), int(w.island_id), w, st])
	if not due.is_empty() and t >= start_time() and not in_tutorial() and t - last_announce >= float(_c("global_gap", 3.0)):
		due.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		for d in due:
			if _try_announce(d[2], d[3], t):
				break
	_refresh_caches()


func _rng_for(w) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.seed_value, int(w.island_id), seq, "ereignis"])
	return rng


## Stärke eines Ereignisses (Jahr und Siedler der Insel).
func power_for(w, at: float) -> float:
	var p: Array = _c("power", [0.5, 0.1, 30.0, 0.5, 2.5])
	return clampf(float(p[0]) + float(p[1]) * (Seasons.year(at) - 2) + w.settlers.size() / float(p[2]), float(p[3]), float(p[4]))


## Eintrittszeit: lead Tage nach t, tagsüber (strike_tod), nie früher als die kürzeste Vorwarnzeit.
func _strike_time(t: float, rng: RandomNumberGenerator) -> float:
	var lead: Array = _c("lead", [1.0, 2.0])
	var tod: Array = _c("strike_tod", [0.3, 0.55])
	var raw := t + rng.randf_range(float(lead[0]), float(lead[1]))
	var s := floorf(raw) + rng.randf_range(float(tod[0]), float(tod[1]))
	if s < t + float(lead[0]):
		s += 1.0
	return s


## Kann diese Art auf der Insel gerade eintreten?
func eligible(w, t: String) -> bool:
	var d := type_def(t)
	if d.is_empty() or w.settlers.size() < int(d.get("min_settlers", _c("min_settlers", 6))):
		return false
	match t:
		"duerre":
			var needs: Array = d.get("needs", [])
			return w.buildings.any(func(b): return b.complete and b.type in needs)
		"ratten":
			return _rat_goods(w) >= int(d.get("min_goods", 30))
		"brand":
			return _damage_candidates(w).size() >= int(d.get("min_targets", 3))
		"sturmflut":
			return not _flood_fields(w).is_empty() or not _flood_buildings(w).is_empty()
		"piraten":
			return Game.current_age() >= int(d.get("min_age", 2)) and Sea.harbor_level(w) >= int(d.get("min_harbor", 1)) \
				and w.nearest_storage(w.center) != null
	return true


## Gewicht einer Art für die Jahreszeit beim Eintritt (0 = kommt nicht).
func weight(t: String, at: float) -> float:
	var d := type_def(t)
	var s := Seasons.season(at)
	var y := Seasons.year(at)
	var ws: Array = d.get("weights", [0, 0, 0, 0])
	var wt := float(ws[s]) if s < ws.size() else 0.0
	if s == SUMMER and Seasons.summer_type(y) == "heiss":
		wt *= float(d.get("hot_mult", 1.0))
	if d.get("no_hard_winter", false) and s == WINTER and Seasons.winter_type(y) in ["hart", "bitter"]:
		wt = 0.0
	return wt


func _try_announce(w, st: Dictionary, t: float) -> bool:
	if not enabled:
		return false
	var rng := _rng_for(w)
	var strike := _strike_time(t, rng)
	var cands := []
	var total := 0.0
	for k in cfg.get("types", {}):
		var typ := str(k)
		if typ == str(st.get("last", "")):
			continue
		var wt := weight(typ, strike)
		if wt <= 0.0 or not eligible(w, typ):
			continue
		cands.append([typ, wt])
		total += wt
	if cands.is_empty():
		st.next = t + float(_c("retry_days", 1.0))
		return false
	var r := rng.randf() * total
	var pick: String = cands[-1][0]
	for c in cands:
		r -= float(c[1])
		if r <= 0.0:
			pick = c[0]
			break
	announce(w, pick, strike, rng)
	return true


## Kündigt ein Ereignis an (auch Testhilfe force()). Gespeichert ab jetzt: Neuladen umgeht es nicht.
func announce(w, typ: String, strike: float, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = _rng_for(w)
	var key := str(w.island_id)
	if not islands.has(key):
		islands[key] = {"next": Game.time_days, "last": "", "ev": null}
	var ev := {"type": typ, "at": Game.time_days, "strike": strike, "end": strike, "power": snappedf(power_for(w, strike), 0.01),
		"deaths": 0, "struck": false}
	if typ == "seuche":
		var ills: Array = type_def(typ).get("ills", ["fieber"])
		ev["ill"] = str(ills[rng.randi() % ills.size()])
	islands[key].ev = ev
	last_announce = Game.time_days
	seq += 1
	Game.notify_at(w, tr("%s in %d Stunden! %s %s") % [type_name(typ), _hours(strike), _what(typ, ev), _counter(w, typ)],
		str(type_def(typ).get("icon", "ereignis")), "ereignis")
	Sound.play("warnung")
	changed.emit()
	return ev


## Testhilfe: Ereignis dieser Art jetzt ankündigen, Eintritt nach lead Tagen (ohne Bedingungen).
func force(w, typ: String, lead: float) -> Dictionary:
	var key := str(w.island_id)
	if islands.has(key) and islands[key].get("ev") is Dictionary:
		_end(w, islands[key], islands[key].ev, "")
	return announce(w, typ, Game.time_days + lead)


func _advance(w, st: Dictionary, ev: Dictionary, t: float) -> void:
	if not bool(ev.get("struck", false)):
		if t >= float(ev.strike):
			_strike(w, st, ev)
		return
	match str(ev.type):
		"piraten":
			_pirates_tick(w, st, ev, t)
		_:
			if t >= float(ev.end):
				_finish(w, st, ev)


func _strike(w, st: Dictionary, ev: Dictionary) -> void:
	ev.struck = true
	ev.power = snappedf(power_for(w, Game.time_days), 0.01)
	var typ := str(ev.type)
	var icon := str(type_def(typ).get("icon", "ereignis"))
	var desc := str(type_def(typ).get("desc", ""))
	Sound.play_on("glocke", w)
	match typ:
		"duerre":
			var sd := Seasons.season_days()
			var t := Game.time_days
			ev.end = maxf(floorf(t / sd) * sd + sd, t + float(type_def(typ).get("min_days", 1.5)))
			Game.notify_at(w, desc, icon, "ereignis")
		"seuche":
			ev.end = Game.time_days + float(type_def(typ).get("days", 2.0))
			Game.notify_at(w, "%s %s" % [desc, tr("Meist trifft es: %s.") % _ill_name(str(ev.get("ill", "")))], icon, "ereignis")
			_refresh_caches()
			var healthy: Array = w.settlers.filter(func(s): return s.is_adult() and s.mind.sick == "")
			if not healthy.is_empty():
				healthy[_rng_for(w).randi() % healthy.size()].mind._fall_ill(str(ev.get("ill", "fieber")))
		"ratten":
			Game.notify_at(w, "%s %s" % [desc, _rats(w, ev)], icon, "ereignis")
			_finish(w, st, ev, false)
		"brand":
			Game.notify_at(w, "%s %s" % [desc, _fire(w, ev)], icon, "ereignis")
			_finish(w, st, ev, false)
		"sturmflut":
			Game.notify_at(w, "%s %s" % [desc, _flood(w, ev)], icon, "ereignis")
			_finish(w, st, ev, false)
		"piraten":
			_pirates_land(w, st, ev)
	changed.emit()


## Ende: Ergebnis melden, Belohnung (keine Toten), nächstes Ereignis planen.
func _finish(w, st: Dictionary, ev: Dictionary, say: bool = true) -> void:
	var typ := str(ev.type)
	var parts := []
	if say:
		match typ:
			"duerre":
				parts.append(tr("Die Dürre ist vorbei, es regnet wieder."))
			"seuche":
				parts.append(tr("Die Seuche ist vorbei."))
			"piraten":
				parts.append(_pirates_result(w, ev))
	var deaths := int(ev.get("deaths", 0))
	if deaths == 0:
		Game.stats["events_survived"] = int(Game.stats.get("events_survived", 0)) + 1
		if type_def(typ).get("reward", false):
			parts.append(_reward(w))
	elif say:
		parts.append(tr("%d Siedler sind dabei gestorben.") % deaths if deaths > 1 else tr("Ein Siedler ist dabei gestorben."))
	if not parts.is_empty():
		Game.notify_at(w, " ".join(parts), str(type_def(typ).get("icon", "ereignis")), "ereignis")
	_end(w, st, ev, typ)


func _end(w, st: Dictionary, _ev: Dictionary, typ: String) -> void:
	Game.stats["events"] = int(Game.stats.get("events", 0)) + (1 if typ != "" else 0)
	var rng := _rng_for(w)
	var iv: Array = _c("interval", [10.0, 14.0])
	st.ev = null
	if typ != "":
		st.last = typ
	# Abstand plus/minus bis zu season_jitter Jahreszeiten: so wandern Ereignisse durch das Jahr und
	# hängen nicht an einer Jahreszeit fest (im Mittel bleibt es beim Abstand aus interval)
	var gap := rng.randf_range(float(iv[0]), float(iv[1]))
	var jit := int(_c("season_jitter", 0))
	if jit > 0:
		gap += float(rng.randi_range(-jit, jit)) * Seasons.season_days()
	st.next = Game.time_days + maxf(float(_c("min_gap", 5.0)), gap)
	_clear_pirates(w)
	_refresh_caches()
	changed.emit()


## Belohnung für eine Insel ohne Tote: ein Einwanderer, ohne freien Wohnplatz Waren je Zeitalter.
func _reward(w) -> String:
	last_reward = "goods"
	if Game.housing_capacity(w) > w.settlers.size():
		var came: Array = Game.spawn_immigrants(w, 1, {"convert": false})
		if not came.is_empty():
			last_reward = "settler"
			Sound.play_on("geburt", w)
			return tr("%s hat von eurer Standhaftigkeit gehört und zieht zu euch.") % came[0].display_name
	var goods := {}
	for e in _c("reward_goods", []):
		if Game.current_age() >= int(e[0]):
			goods = e[1]
	var txt := Game.grant_reward(w, goods)
	return tr("Ohne freien Wohnplatz schicken Nachbarn zum Dank für eure Standhaftigkeit Waren: %s.") % txt


func _forget(id: int) -> void:
	islands.erase(str(id))
	_raiders.erase(id)
	var sp = _ships.get(id)
	if sp != null and is_instance_valid(sp):
		sp.queue_free()
	_ships.erase(id)


func _on_died(s, cause: String) -> void:
	if cause == "old" or s == null or not is_instance_valid(s):
		return
	var w = s.world
	var ev := event_of(w)
	if not ev.is_empty() and bool(ev.get("struck", false)):  # Tote vor dem Eintritt zaehlen nicht
		ev.deaths = int(ev.get("deaths", 0)) + 1


func _drought_factor() -> float:
	var d := type_def("duerre")
	return float(d.get("factor_irrigated", 0.7) if Game.is_researched("bewaesserung") else d.get("factor", 0.4))


func _sick_factor(ev: Dictionary) -> float:
	var m: Array = type_def("seuche").get("mult", [2.0, 0.6, 2.5, 4.0])
	var mm := clampf(float(m[0]) + float(m[1]) * float(ev.get("power", 1.0)), float(m[2]), float(m[3]))
	return 1.0 + (mm - 1.0) / maxf(1.0, Game.eff("heal"))


## Merkt sich, welche Inseln gerade eine Dürre oder Seuche haben (schnelle Abfragen je Bild).
func _refresh_caches() -> void:
	_drought = {}
	_sick = {}
	_ill = {}
	var t := Game.time_days
	for k in islands:
		var ev = islands[k].get("ev")
		if not ev is Dictionary or not bool(ev.get("struck", false)) or t >= float(ev.end):
			continue
		var w = _world(int(k))
		if w == null:
			continue
		match str(ev.type):
			"duerre":
				_drought[w] = _drought_factor()
			"seuche":
				_sick[w] = _sick_factor(ev)
				_ill[w] = str(ev.get("ill", ""))


# ---------------------------------------------------------------- Ratten
func _rat_goods(w) -> int:
	var n := 0
	for id in type_def("ratten").get("goods", []):
		n += Game.amount(str(id), w)
	return n


func _rats(w, ev: Dictionary) -> String:
	var d := type_def("ratten")
	var sh: Array = d.get("share", [0.15, 0.08, 0.15, 0.35])
	var share := clampf(float(sh[0]) + float(sh[1]) * float(ev.power), float(sh[2]), float(sh[3]))
	var store := str(d.get("store", "grosslager"))
	var guarded: bool = w.buildings.any(func(b): return b.complete and b.type == store)
	if guarded:
		share *= float(d.get("store_mult", 0.5))
	var lost := []
	var total := 0
	var by := {}
	for id in d.get("goods", []):
		var have := Game.amount(str(id), w)
		var n := roundi(have * share)
		if n > 0:
			n = Game.take_stock(str(id), n, w)
			total += n
			by[str(id)] = [have, n]
			lost.append("%d %s" % [n, Data.resource_name(str(id))])
	ev["lost"] = total
	ev["lost_by"] = by  # Ware -> [vorher, gefressen] (nur für Tests, nicht gespeichert)
	ev["share"] = share
	var st = w.nearest_storage(w.center)
	if st != null and total > 0:
		w.float_text(st.position + Vector2(0, -30), "-%d" % total, "ratte")
	if lost.is_empty():
		return tr("Sie haben kaum etwas gefunden.")
	var txt := tr("Sie haben gefressen: %s.") % ", ".join(lost)
	if guarded:
		txt += " " + tr("Das Große Lager hat die Hälfte gerettet.")
	return txt


# ---------------------------------------------------------------- Brand und Sturmflut
## Gebäude, die Feuer oder Flut beschädigen können: fertig, kein Feld, kein Lager, kein Hafen, nicht am
## Ufer gebaut (coast), ohne besondere Wirkung, kein Lagerfeuer oder Brunnen.
func _damage_candidates(w) -> Array:
	var no: Array = _c("no_damage", [])
	return w.buildings.filter(func(b): return b.complete and not b.is_ground() and not b.type in no \
		and int(b.def.get("storage", 0)) <= 0 and not b.def.has("harbor") and not b.def.get("coast", false) \
		and not b.def.has("effects"))


## Liegt das Gebäude höchstens r Felder vom Wasser?
func _coastal(w, b, r: int) -> bool:
	return near_water(w, b.cell, b.size, r)


## Liegt die Fläche (obere linke Zelle c, Größe sz) höchstens r Felder vom Wasser?
func near_water(w, c: Vector2i, sz: Vector2i, r: int) -> bool:
	for y in range(-r, sz.y + r):
		for x in range(-r, sz.x + r):
			if w.is_water(c + Vector2i(x, y)):
				return true
	return false


func _flood_fields(w) -> Array:
	var r := int(type_def("sturmflut").get("coast_radius", 2))
	return w.buildings.filter(func(b): return b.complete and b.is_ground() and b.def.has("farm") and _coastal(w, b, r))


func _flood_buildings(w) -> Array:
	var r := int(type_def("sturmflut").get("coast_radius", 2))
	return _damage_candidates(w).filter(func(b): return _coastal(w, b, r))


func _hits(power: float) -> int:
	return 1 + int(floor(power / 1.25))


func _fire(w, ev: Dictionary) -> String:
	var d := type_def("brand")
	var cands := _damage_candidates(w)
	if cands.is_empty():
		return tr("Zum Glück hat das Feuer nichts erfasst.")
	var rng := _rng_for(w)
	var first = cands[rng.randi() % cands.size()]
	cands.sort_custom(func(a, b): return a.dist_sq(first.cell) < b.dist_sq(first.cell))
	var r := float(d.get("well_radius", 8))
	var well := str(d.get("well", "brunnen"))
	var wells: Array = w.buildings.filter(func(b): return b.complete and b.type == well)
	var burnt := []
	var saved := []
	for b in cands.slice(0, _hits(float(ev.power))):
		var near: bool = wells.any(func(x): return b.dist_sq(x.cell) <= r * r)
		_fires.append([w, b, 2.5 if near else 7.0])
		if near:
			saved.append(str(b.def.name))
		else:
			damage_building(w, b, float(d.get("keep", 0.7)))
			burnt.append(str(b.def.name))
	ev["burnt"] = burnt.size()
	ev["saved"] = saved.size()
	var parts := []
	if not burnt.is_empty():
		parts.append(tr("Abgebrannt: %s. Baumeister bauen es wieder auf, ein Teil des Baumaterials ist noch da.") % ", ".join(burnt))
	if not saved.is_empty():
		parts.append(tr("Am Brunnen schnell gelöscht: %s.") % ", ".join(saved))
	return " ".join(parts)


func _flood(w, ev: Dictionary) -> String:
	if Game.eff_add("flood") > 0.0:
		ev["fields"] = 0
		ev["burnt"] = 0
		return tr("Die Deiche halten! Die Sturmflut richtet keinen Schaden an.")
	var d := type_def("sturmflut")
	var fields := 0
	for b in _flood_fields(w):
		w.spawn_effect("chips_fischgrund", b.position + Vector2(0, -8))
		if b.farm_state != "fallow":
			b.farm_state = "fallow"
			b.refresh()
			fields += 1
	var hit := []
	var cands := _flood_buildings(w)
	var rng := _rng_for(w)
	for i in range(cands.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var x = cands[i]
		cands[i] = cands[j]
		cands[j] = x
	for b in cands.slice(0, _hits(float(ev.power))):
		w.spawn_effect("chips_fischgrund", b.position + Vector2(0, -12))
		damage_building(w, b, float(d.get("keep", 0.8)))
		hit.append(str(b.def.name))
	ev["fields"] = fields
	ev["burnt"] = hit.size()
	var parts := []
	if fields > 0:
		parts.append(tr("%d Felder am Wasser haben ihre Ernte verloren.") % fields if fields > 1 else tr("Ein Feld am Wasser hat seine Ernte verloren."))
	if not hit.is_empty():
		parts.append(tr("Beschädigt: %s. Baumeister bauen es wieder auf.") % ", ".join(hit))
	if parts.is_empty():
		parts.append(tr("Das Wasser ist zurückgegangen, ohne viel Schaden anzurichten."))
	return " ".join(parts)


## Beschädigt ein Gebäude an Ort und Stelle: es wird wieder zur Baustelle (gleiche ID). Fortgeschrittene
## Baustoffe bleiben ganz, von den einfachen (basic_goods) der Anteil keep; die Bauarbeit beginnt neu.
## Bewohner und Arbeiter verlassen es, Baumeister bauen es mit der normalen Baustellen-Logik wieder auf.
func damage_building(w, b, keep: float) -> void:
	for s in w.settlers:
		if s._reserved == b or s._incoming.any(func(i): return i[0] == b) or s._hiding == b:
			s.abort_plan()
		if s.home_id == b.id and s.sleeping:
			s._wake_up()
	var basic: Array = _c("basic_goods", [])
	var dl := {}
	for res in b.def.cost:
		var n := int(b.def.cost[res])
		dl[res] = ceili(n * keep) if res in basic else n
	b.complete = false
	b.progress = 0.0
	b.delivered = dl
	b.incoming = {}
	b.occupants.clear()
	b.reserved_by = 0
	if b.def.has("farm"):
		b.farm_state = "fallow"
	b.refresh()
	w.assign_homes()
	if b.def.has("effects"):
		Game.refresh_effects()
	Game.population_changed.emit()
	Game.stock_changed.emit()


## Flammen und Rauch über brennenden Gebäuden (nur Bild, nur auf der sichtbaren Insel).
func _burn(delta: float) -> void:
	_fx_t -= delta
	var spawn := _fx_t <= 0.0
	if spawn:
		_fx_t = 0.12
	for f in _fires.duplicate():
		f[2] = float(f[2]) - delta
		var w = f[0]
		var b = f[1]
		if float(f[2]) <= 0.0 or not is_instance_valid(w) or not is_instance_valid(b):
			_fires.erase(f)
			continue
		if spawn and w == Game.world:
			var p: Vector2 = b.position + Vector2(randf_range(-b.size.x * 6.0, b.size.x * 6.0), -randf_range(4.0, b.size.y * 12.0))
			_flame(w, p)
			if randf() < 0.5:
				w.spawn_smoke(p + Vector2(0, -6))


func _flame(w, p: Vector2) -> void:
	var cols := [Color("#ff9a3a"), Color("#ffd25a"), Color("#e04a20")]
	for i in 3:
		var r := ColorRect.new()
		var sz := randf_range(2.0, 4.0)
		r.size = Vector2(sz, sz)
		r.color = cols[i % cols.size()]
		r.position = p + Vector2(randf_range(-3, 3), 0)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		w.fx.add_child(r)
		var tw := r.create_tween()
		tw.set_parallel(true)
		tw.tween_property(r, "position", r.position + Vector2(randf_range(-3, 3), -randf_range(8, 16)), 0.6)
		tw.tween_property(r, "modulate:a", 0.0, 0.45).set_delay(0.15)
		tw.chain().tween_callback(r.queue_free)


# ---------------------------------------------------------------- Piraten
func _raiders_of(w) -> Array:
	var list: Array = _raiders.get(int(w.island_id), [])
	return list.filter(func(r): return is_instance_valid(r) and not r.dead and not r.gone)


## Landeplatz der Piraten: Strand mit Wasser davor, etwa 12 Felder vom Lager, Weg zum Lager frei.
func _landing_cell(w, rng: RandomNumberGenerator):
	var st = w.nearest_storage(w.center)
	var origin: Vector2i = st.entrance_cell() if st != null else w.center
	var cands := []
	for y in w.size:
		for x in w.size:
			var c := Vector2i(x, y)
			if w.terrain_at(c) == World.SAND and w.is_walkable(c) and not w.building_at.has(c):
				var d := Vector2(c - origin).length()
				cands.append([absf(d - 12.0) + rng.randf() * 4.0, c])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(16, cands.size()):
		var c: Vector2i = cands[i][1]
		if w._water_near(c, 5) != null and not w.find_path(c, origin).is_empty():
			return c
	return w.beach_near(rng)


func _pirates_land(w, st: Dictionary, ev: Dictionary) -> void:
	var d := type_def("piraten")
	var rng := _rng_for(w)
	var c: Array = d.get("count", [2, 10, 7])
	var age := Game.current_age()
	var n := clampi(int(c[0]) + w.settlers.size() / maxi(1, int(c[1])) + (age - 2), int(c[0]), int(c[2]))
	ev.end = Game.time_days + float(d.get("timeout", 0.8))
	ev.count = n
	ev.kills = 0
	ev.loot = {}
	var land = _landing_cell(w, rng)
	if land == null:
		ev.left = 0
		Game.notify_at(w, tr("Die Piraten fanden keinen Landeplatz und sind weitergesegelt."), "schwert", "ereignis")
		_finish(w, st, ev, false)
		return
	ev.landing = [land.x, land.y]
	_spawn_raiders(w, ev, n)
	Game.notify_at(w, "%s %s" % [type_def("piraten").get("desc", ""), tr("%d Piraten ziehen zum Lager. Siedler fliehen in die Häuser, Jäger und Wachtürme wehren sie ab.") % n],
		"schwert", "ereignis")


func _spawn_raiders(w, ev: Dictionary, n: int) -> void:
	var land := Vector2i(int(ev.landing[0]), int(ev.landing[1]))
	var rd := raider_def().duplicate(true)
	var age := Game.current_age()
	rd["hp"] = float(rd.get("hp", 45)) * (1.0 + float(rd.get("hp_age", 0.15)) * maxi(0, age - 2))
	var cap := int(float(rd.get("loot_base", 6)) + float(rd.get("loot_power", 4)) * float(ev.get("power", 1.0)))
	var list: Array = _raiders_of(w)
	var spots := [land]
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var q := land + Vector2i(dx, dy)
			if q != land and w.is_walkable(q) and not w.building_at.has(q):
				spots.append(q)
	for i in n:
		var r := Raider.new()
		r.setup_raider(w, spots[i % spots.size()], land, cap, rd)
		w.entities.add_child(r)
		w.animals.append(r)
		list.append(r)
	_raiders[int(w.island_id)] = list
	ev.left = list.size()
	_ship_in(w, land)


func _pirates_tick(w, st: Dictionary, ev: Dictionary, t: float) -> void:
	var d := type_def("piraten")
	var list := _raiders_of(w)
	var strike := float(ev.strike)
	if t >= strike + float(d.get("home_after", 0.5)):
		for r in list:
			r.go_home()
	if t >= float(ev.end):
		for r in list:
			_raider_gone(w, r, true)  # Zeit um: wer noch an Land ist, verschwindet mit seiner Beute
		list = []
	ev.left = list.size()
	if ev.left <= 0:
		_finish(w, st, ev)


## Beute für einen Piraten, der fertig geplündert hat: aus der Liste (Gold zuerst), was die anderen
## Piraten dieser Insel nicht schon tragen. Genommen wird erst beim Ablegen.
func plan_loot(r) -> Dictionary:
	var w = r.world
	var taken := {}
	for o in _raiders_of(w):
		if o != r:
			for id in o.loot:
				taken[id] = int(taken.get(id, 0)) + int(o.loot[id])
	var out := {}
	var left := int(r.loot_cap)
	for id in raider_def().get("loot", []):
		if left <= 0:
			break
		var have := Game.amount(str(id), w) - int(taken.get(str(id), 0))
		var n := mini(have, left)
		if n > 0:
			out[str(id)] = n
			left -= n
	return out


## Ein Pirat ist mit seiner Beute an Bord gegangen.
func on_raider_boarded(r) -> void:
	_raider_gone(r.world, r, true)
	var w = r.world
	var ev := event_of(w)
	if not ev.is_empty():
		ev.left = _raiders_of(w).size()


## Ein Pirat wurde vertrieben (Jäger, Wachturm, Notwehr). Kein Fleisch, keine Felle, zählt nicht als Jagd.
func on_raider_killed(r, by) -> void:
	var w = r.world
	Game.stats["pirates"] = int(Game.stats.get("pirates", 0)) + 1
	var ev := event_of(w)
	if not ev.is_empty():
		ev.kills = int(ev.get("kills", 0)) + 1
	w.spawn_effect("blood", r.position + Vector2(0, -6))
	w.float_text(r.position + Vector2(-8, -24), tr("Vertrieben!"), "")
	if by is Settler and is_instance_valid(by):
		by.gain_xp("jagd", 2.0)
	_raider_gone(w, r, false)
	if not ev.is_empty():
		ev.left = _raiders_of(w).size()


func _raider_gone(w, r, with_loot: bool) -> void:
	if not is_instance_valid(r) or r.gone:
		return
	r.gone = true
	var ev := event_of(w)
	if with_loot and not r.dead:
		for id in r.loot:
			var n := Game.take_stock(str(id), mini(int(r.loot[id]), Game.amount(str(id), w)), w)
			if n > 0 and not ev.is_empty():
				var lt: Dictionary = ev.get("loot", {})
				lt[str(id)] = int(lt.get(str(id), 0)) + n
				ev["loot"] = lt
	w.animals.erase(r)
	if Game.selected == r:
		Game.select(null)
	r.queue_free()
	var list: Array = _raiders.get(int(w.island_id), [])
	list.erase(r)


func _pirates_result(w, ev: Dictionary) -> String:
	var kills := int(ev.get("kills", 0))
	var count := maxi(1, int(ev.get("count", 1)))
	var loot: Dictionary = ev.get("loot", {})
	var parts := []
	if loot.is_empty():
		parts.append(tr("Die Piraten sind ohne Beute abgezogen."))
	else:
		var l := []
		for id in loot:
			l.append("%d %s" % [int(loot[id]), Data.resource_name(str(id))])
		parts.append(tr("Die Piraten sind abgezogen und haben mitgenommen: %s.") % ", ".join(l))
	if kills > 0:
		parts.append(tr("%d von %d Piraten wurden vertrieben.") % [kills, count])
	if kills * 2 >= count and kills > 0:
		var g := Game.give_goods(w, "gold", kills * int(type_def("piraten").get("gold_per_kill", 1)))
		if int(g[0]) > 0:
			parts.append(tr("Sie ließen %d Gold zurück.") % int(g[0]))
	return " ".join(parts)


func _ship_in(w, land: Vector2i) -> void:
	var id := int(w.island_id)
	if _ships.has(id) and is_instance_valid(_ships[id]):
		return
	var spot = w._water_near(land, 5)
	if spot == null:
		return
	var sp: Sprite2D = w._ship_node("ship_kogge")
	sp.modulate = Color("#8a6a6a")
	var to: Vector2 = w.cell_to_pos(spot)
	var dir: Vector2 = (to - w.cell_to_pos(w.center)).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	sp.position = to + dir * 160.0
	w.entities.add_child(sp)
	var tw := sp.create_tween()
	tw.tween_property(sp, "position", to, 4.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_ships[id] = sp


## Alle Piraten der Insel weg (Ende oder Insel verloren); das Schiff segelt davon.
func _clear_pirates(w) -> void:
	var id := int(w.island_id)
	for r in _raiders.get(id, []):
		if is_instance_valid(r) and not r.gone:
			_raider_gone(w, r, false)
	_raiders.erase(id)
	var sp = _ships.get(id)
	_ships.erase(id)
	if sp != null and is_instance_valid(sp):
		var dir: Vector2 = (sp.position - w.cell_to_pos(w.center)).normalized()
		var tw: Tween = sp.create_tween()
		tw.tween_property(sp, "position", sp.position + dir * 200.0, 6.0)
		tw.parallel().tween_property(sp, "modulate:a", 0.0, 2.5).set_delay(3.5)
		tw.tween_callback(sp.queue_free)


# ---------------------------------------------------------------- Spielstand
func _clear_runtime() -> void:
	for id in _raiders:
		for r in _raiders[id]:
			if is_instance_valid(r):
				if is_instance_valid(r.world):
					r.world.animals.erase(r)
				r.gone = true
				r.queue_free()
	for id in _ships:
		if is_instance_valid(_ships[id]):
			_ships[id].queue_free()
	_raiders = {}
	_ships = {}
	_fires = []
	_drought = {}
	_sick = {}
	_ill = {}
	_next_tick = 0.0


func _on_reset() -> void:
	_clear_runtime()
	islands = {}
	last_announce = -99.0
	seq = 0
	changed.emit()


func _on_save(d: Dictionary) -> void:
	d["events"] = {"islands": islands.duplicate(true), "last": last_announce, "seq": seq}


func _ev_from(e, t: float):
	if not e is Dictionary or type_def(str(e.get("type", ""))).is_empty():
		return null
	var ev := {"type": str(e.type), "at": float(e.get("at", t)), "strike": float(e.get("strike", t)),
		"end": float(e.get("end", e.get("strike", t))), "power": clampf(float(e.get("power", 1.0)), 0.1, 5.0),
		"deaths": maxi(0, int(e.get("deaths", 0))), "struck": bool(e.get("struck", false))}
	for k in ["ill"]:
		if e.has(k):
			ev[k] = str(e[k])
	for k in ["count", "left", "kills", "lost", "burnt", "saved", "fields"]:
		if e.has(k):
			ev[k] = maxi(0, int(e[k]))
	if e.get("landing") is Array and e.landing.size() == 2:
		ev["landing"] = [int(e.landing[0]), int(e.landing[1])]
	var lt := {}
	if e.get("loot") is Dictionary:
		for id in e.loot:
			if Data.resources.has(str(id)):
				lt[str(id)] = maxi(0, int(e.loot[id]))
	ev["loot"] = lt
	return ev


## Spielstand geladen. Ohne "events" (alter Spielstand) bekommt jede Insel beim ersten Takt
## grace_days Schonzeit (wie eine neue Insel). Laufende Piraten landen neu (ev.left).
func _on_load(data: Dictionary, old_rules: int) -> void:
	_clear_runtime()
	islands = {}
	last_announce = -99.0
	seq = 0
	var t := Game.time_days
	var e = data.get("events", null)
	if e is Dictionary:
		last_announce = float(e.get("last", -99.0))
		seq = maxi(0, int(e.get("seq", 0)))
		var isl = e.get("islands", {})
		if isl is Dictionary:
			for k in isl:
				var s = isl[k]
				if not s is Dictionary or _world(int(k)) == null:
					continue
				var last := str(s.get("last", ""))
				islands[str(int(k))] = {"next": float(s.get("next", t + float(_c("grace_days", 8.0)))),
					"last": last if not type_def(last).is_empty() else "", "ev": _ev_from(s.get("ev"), t)}
	if old_rules < 1:
		Game.rules_lines.append(tr("Ab dem zweiten Jahr kündigen sich Ereignisse an: Dürre, Ratten, Brand, Seuche, Sturmflut und ab dem Mittelalter Piraten. Wer sie gut übersteht, bekommt Einwanderer."))
	# Laufender Piratenüberfall: die Piraten, die noch an Land waren, landen neu
	for k in islands:
		var ev = islands[k].ev
		var w = _world(int(k))
		if ev is Dictionary and str(ev.type) == "piraten" and bool(ev.struck) and w != null:
			if int(ev.get("left", 0)) > 0 and t < float(ev.end) and ev.has("landing"):
				_spawn_raiders(w, ev, int(ev.left))
			else:
				ev.left = 0
	_refresh_caches()
	changed.emit()


# ---------------------------------------------------------------- Selbsttest
## Testhilfen (Game.systems): --noevents=1 (keine Ereignisse), --eventtest=<duerre|ratten|brand|
## seuche|sturmflut|piraten|all> (Ereignis sofort, Vorwarnung 0,05 Tag, prüft die Wirkung), --eventshot=<art>
## (nur ankündigen bzw. eintreten lassen, für Bildschirmfotos), --eventsched=1 (Zeitplan über Jahre).
func autotest_setup(args: Dictionary, main) -> void:
	if str(args.get("noevents", "0")) != "0":
		enabled = false
		print("Ereignisse: aus")
	if args.has("skiptut"):
		Game.goals.tut = Data.goals.get("tutorial", []).size()  # Einführung überspringen (sonst keine Ereignisse)
		print("Einführung übersprungen")
	if args.has("eventtest"):
		await EventsTest.run(main, str(args.eventtest))
	if args.has("eventshot"):
		await EventsTest.shot(main, str(args.eventshot))
	if args.has("eventsched"):
		await EventsTest.schedule(main)


func autotest_report() -> String:
	if not enabled:
		print("   Ereignisse: aus")
		return ""
	print("   Ereignisse: überstanden %d von %d, Piraten vertrieben %d" % [int(Game.stats.get("events_survived", 0)), int(Game.stats.get("events", 0)), int(Game.stats.get("pirates", 0))])
	for k in islands:
		var st: Dictionary = islands[k]
		var w = _world(int(k))
		var name := Sea.island_name(w) if w != null else str(k)
		var ev = st.get("ev")
		var pir := "%d/%d, %d" % [int(ev.get("left", 0)), int(ev.get("count", 0)), int(ev.get("kills", 0))] if ev is Dictionary and ev.type == "piraten" else "-"
		if ev is Dictionary:
			print("     %s: %s eingetreten=%s Eintritt Tag %.2f Ende %.2f Stärke %.2f Tote %d Piraten (übrig/gelandet, vertrieben) %s" % [name, ev.type, ev.struck, float(ev.strike) + 1.0, float(ev.end) + 1.0, float(ev.power), int(ev.deaths), pir])
		else:
			print("     %s: nächstes ab Tag %.2f (zuletzt %s)" % [name, float(st.next) + 1.0, st.get("last", "-")])
	return ""
