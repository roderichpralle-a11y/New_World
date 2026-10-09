extends Node
## Bedürfnisstufen der Bewohner (Regeln ab Version 2, "Herausforderung").
##
## Häuser haben eine Stufe (buildings.json `level`: Hütte 1, Holzhaus 2, Steinhaus 3, Mietshaus 4,
## Wohnblock 5). Die Bedürfnisse je Stufe stehen in data/levels.json. Je Insel und Stufengruppe k
## (Verbraucher = Bewohner von Häusern ab Stufe k, Erwachsene 1, Kinder `child_weight`) prüft das
## System alle `tick_days` die Bedürfnisse, verbraucht Waren (Möbel = Bretter usw.) und glättet die
## Erfüllung (`tau_days`). Zufriedenheit der Stufe k = Mittel aller Bedürfnisse der Stufen 2..k;
## ok(k) mit Hysterese (an ab `on`, aus unter `off`). Ein Haus der Stufe L zählt als die höchste Stufe
## k <= L mit ok(k), sonst als Stufe 1 (Stufe 1 = Nahrung und Wärme, nur Anzeige).
##
## Fachkräfte-Pool: Werkstätten und Forschungsplätze haben `worker_level` (Standard 1). Plätze ab
## Stufe 2 darf ein Siedler nur nehmen, wenn für alle k = 2..L gilt: belegt(k) < Fachkräfte(k).
## Fachkräfte(k) = Erwachsene in Häusern, die als Stufe >= k zählen; belegt(k) = Siedler, die gerade in
## Werkstätten/Forschung mit worker_level >= k arbeiten. Abfrage über World.pool_allows(b, sid).
## Schalter balance.json "worker_levels" (false = keine Sperre, nur für Tests).
##
## Spielstand: oben "needs" = {"<insel-id>": {sat, ok, acc, grace}} (Game.state_save/state_load).
## Alter Spielstand ohne "needs": alles zufrieden und einen Tag Schonfrist.

var cfg: Dictionary = {}
var levels: Array = []  # levels.json "levels", Eintrag k-1 = Stufe k
## Insel-ID -> {sat: {Bedürfnis: 0..1 geglättet}, ok: {"2".."5": bool}, acc: {Ware: angefangene Menge},
## grace: time_days, bis dahin fällt keine Stufe ab}. Nur zur Laufzeit (Schlüssel mit "_", nicht
## gespeichert): _inst (Erfüllung gerade), _cons (Verbraucher je Stufe), _houses (fertige Häuser ab
## Stufe k), _miss (fehlende Bedürfnisse je Stufe als Text).
var state: Dictionary = {}
var turned_away: int = 0  # abgewiesene Fachkräfte seit Spielbeginn (Selbsttest, Bericht)

var _last := -1.0
var _cap_frame := -1
var _cap_memo: Dictionary = {}  # Insel-ID -> Fachkräfte je Stufe (einmal je Frame berechnet)
var _turned_at: Dictionary = {}  # "insel:stufe" -> time_days der letzten Meldung


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cfg = Data._load("levels")
	levels = cfg.get("levels", [])
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)


# ---------------------------------------------------------------- Abfragen
func max_level() -> int:
	return levels.size()


## Name einer Stufe ("Dorfbewohner"), übersetzt.
func level_name(k: int) -> String:
	if k < 1 or k > levels.size():
		return ""
	return str(levels[k - 1].get("name", ""))


## Name eines Hauses dieser Stufe (für Hinweise, z. B. "Holzhaus").
func level_house(k: int) -> String:
	for t in Data.buildings:
		var d: Dictionary = Data.buildings[t]
		if d.has("housing") and int(d.get("level", 1)) == k:
			return str(d.name)
	return ""


## Bedürfnisse einer Stufe (Liste aus levels.json).
func level_needs(k: int) -> Array:
	if k < 1 or k > levels.size():
		return []
	return levels[k - 1].get("needs", [])


func _state_of(w):
	if w == null or not is_instance_valid(w):
		return null
	return state.get(int(w.island_id))


## Zufriedenheit der Stufe k auf Insel w (Mittel der Bedürfnisse der Stufen 2..k, 0..1).
func level_sat(w, k: int) -> float:
	var st = _state_of(w)
	if st == null or k < 2:
		return 1.0
	var total := 0.0
	var n := 0
	for j in range(2, mini(k, levels.size()) + 1):
		for nd in level_needs(j):
			total += float(st.sat.get(nd.id, 1.0))
			n += 1
	return total / maxf(1.0, float(n))


## Ist Stufe k auf Insel w insgesamt erfüllt (mit Hysterese)?
func level_ok(w, k: int) -> bool:
	var st = _state_of(w)
	if st == null or k < 2:
		return true
	return bool(st.ok.get(str(k), true))


## Erfüllung eines Bedürfnisses (geglättet ab Stufe 2, Stufe 1 der Wert gerade), 0..1.
func need_sat(w, id: String) -> float:
	var st = _state_of(w)
	if st == null:
		return 1.0
	if st.sat.has(id):
		return float(st.sat[id])
	return float(st.get("_inst", {}).get(id, 1.0))


## Effektive Stufe eines Hauses: die höchste Stufe k <= Hausstufe mit ok(k), sonst 1. 0 = kein Haus.
func effective_level(b) -> int:
	var lv: int = b.house_level()
	if lv <= 1:
		return lv
	var st = _state_of(b.world)
	if st == null:
		return lv
	for k in range(mini(lv, levels.size()), 1, -1):
		if bool(st.ok.get(str(k), true)):
			return k
	return 1


## Haus voll zufrieden (zählt mit seiner eigenen Stufe)? Hütten und Nicht-Häuser: immer.
func full_level(b) -> bool:
	return b.house_level() < 2 or effective_level(b) >= b.house_level()


## Zufriedenheit eines Hauses (0..1) für die Anzeige.
func house_sat(b) -> float:
	return level_sat(b.world, b.house_level())


## Siedler in Häusern, die als Stufe >= k zählen (für Aufträge, Prüfungen, Wertung).
func count_level(w, k: int) -> int:
	var eff := {}
	for b in w.buildings:
		if b.complete and b.house_level() > 0:
			eff[b.id] = effective_level(b)
	var n := 0
	for s in w.settlers:
		if int(eff.get(s.home_id, 0)) >= k:
			n += 1
	return n


## Was einer Stufe fehlt (Namen der Bedürfnisse der Stufen 2..k unter `on`, das Schlechteste zuerst).
func missing_text(w, k: int) -> String:
	var st = _state_of(w)
	if st == null:
		return ""
	if st.has("_miss") and st._miss.has(k):
		return st._miss[k]
	return _missing(st, k)


func _missing(st: Dictionary, k: int) -> String:
	var list := []
	for j in range(2, mini(k, levels.size()) + 1):
		for nd in level_needs(j):
			var v := float(st.sat.get(nd.id, 1.0))
			if v < float(cfg.get("on", 0.7)):
				list.append([v, str(nd.get("name", nd.id))])
	list.sort_custom(func(a, b): return a[0] < b[0])
	return ", ".join(list.slice(0, 3).map(func(x): return x[1]))


## Laune-Grund für Bewohner eines Hauses ab Stufe 2 ([Text, Wert] oder []). Liest nur gemerkte Werte.
func mood_reason(home, c: float) -> Array:
	var lv: int = home.house_level()
	if lv < 2 or not home.complete:
		return []
	if effective_level(home) >= lv:
		return [tr("Bedürfnisse erfüllt (%s)") % level_name(lv), float(cfg.get("mood_ok_per_level", 2.0)) * lv * (0.5 + c)]
	var miss := missing_text(home.world, lv)
	return [tr("Bedürfnisse fehlen: %s") % (miss if miss != "" else level_name(lv)),
		-(float(cfg.get("mood_bad", 3.0)) + float(cfg.get("mood_bad_per_level", 2.0)) * lv)]


# ---------------------------------------------------------------- Fachkräfte-Pool
## Fachkräfte je Stufe (Index 0..max): Erwachsene in Häusern, die als Stufe >= k zählen.
func caps(w) -> Array:
	var f := Engine.get_process_frames()
	if f != _cap_frame:
		_cap_frame = f
		_cap_memo.clear()
	var id := int(w.island_id)
	if _cap_memo.has(id):
		return _cap_memo[id]
	var cap := []
	cap.resize(levels.size() + 2)
	cap.fill(0)
	var eff := {}
	for b in w.buildings:
		if b.complete and b.house_level() >= 2:
			eff[b.id] = effective_level(b)
	for s in w.settlers:
		if s.is_adult() and eff.has(s.home_id):
			for k in range(2, int(eff[s.home_id]) + 1):
				cap[k] += 1
	_cap_memo[id] = cap
	return cap


## Siedler, die gerade an Plätzen mit worker_level >= k arbeiten (ohne sid).
func used(w, k: int, sid: int = 0) -> int:
	var n := 0
	for b in w.buildings:
		if b.complete and not b.occupants.is_empty() and b.worker_level() >= k:
			n += b.occupants.size()
			if sid != 0 and sid in b.occupants:
				n -= 1
	return n


## [belegt, Fachkräfte] der Stufe k auf Insel w.
func pool(w, k: int) -> Array:
	return [used(w, k), int(caps(w)[clampi(k, 0, levels.size())])]


## Die Stufe, an der ein Platz gerade scheitert (0 = frei). Für Anzeige und pool_allows.
func pool_block(w, b, sid: int = 0) -> int:
	if w == null or not bool(Data.bal("worker_levels", true)):
		return 0
	var lv: int = mini(b.worker_level(), levels.size())
	if lv <= 1:
		return 0
	var cap := caps(w)
	for k in range(2, lv + 1):
		if used(w, k, sid) >= int(cap[k]):
			return k
	return 0


## Darf Siedler sid (0 = irgendwer) an diesem Platz arbeiten? Siehe Kopf der Datei.
func pool_allows(w, b, sid: int = 0) -> bool:
	var k := pool_block(w, b, sid)
	if k == 0:
		return true
	if sid != 0:
		turned_away += 1
		var key := "%d:%d" % [int(w.island_id), k]
		if Game.time_days - float(_turned_at.get(key, -99.0)) >= float(cfg.get("turned_note_days", 3.0)):
			_turned_at[key] = Game.time_days
			Game.notify_at(w, tr("%s: keine freie Fachkraft der Stufe %d (%s). Mehr zufriedene Häuser dieser Stufe helfen.") % [b.def.name, k, level_name(k)], "haus", "siedler")
	return false


# ---------------------------------------------------------------- Ablauf
func _process(_delta: float) -> void:
	if Game.world == null or Game.is_over or Game.speed <= 0:
		return
	var t := Game.time_days
	if _last < 0.0 or t < _last:
		_last = t
		return
	if t - _last < float(cfg.get("tick_days", 0.1)):
		return
	var dt := clampf(t - _last, 0.0, 0.5)
	_last = t
	for w in Sea.all_worlds():
		tick(w, dt)


## Eine Runde für Insel w: Verbraucher zählen, Bedürfnisse prüfen und verbrauchen, glätten, ok(k).
func tick(w, dt: float) -> void:
	var id := int(w.island_id)
	if not state.has(id):
		state[id] = {"sat": {}, "ok": {}, "acc": {}, "grace": 0.0, "fresh": true}
	var st: Dictionary = state[id]
	var n := levels.size()
	var cons := []
	cons.resize(n + 2)
	cons.fill(0.0)
	var houses := []
	houses.resize(n + 2)
	houses.fill(0)
	var lvl_of := {}
	for b in w.buildings:
		var lv: int = b.house_level()
		if lv > 0 and b.complete:
			lvl_of[b.id] = lv
			for k in range(1, mini(lv, n) + 1):
				houses[k] += 1
	var cw := float(cfg.get("child_weight", 0.5))
	for s in w.settlers:
		var lv: int = int(lvl_of.get(s.home_id, 0))
		if lv > 0:
			var wgt := 1.0 if s.is_adult() else cw
			for k in range(1, mini(lv, n) + 1):
				cons[k] += wgt
	var fresh := bool(st.get("fresh", false))
	var a := 1.0 - exp(-dt / maxf(0.01, float(cfg.get("tau_days", 0.5))))
	var inst := {}
	for k in range(1, n + 1):
		for nd in level_needs(k):
			var v := _eval(w, st, nd, float(cons[k]), dt)
			inst[nd.id] = v
			if k >= 2:
				st.sat[nd.id] = v if fresh or not st.sat.has(nd.id) else lerpf(float(st.sat[nd.id]), v, a)
	st["_inst"] = inst
	st["_cons"] = cons
	st["_houses"] = houses
	var on := float(cfg.get("on", 0.7))
	var off := float(cfg.get("off", 0.55))
	var grace := Game.time_days < float(st.get("grace", 0.0))
	var miss := {}
	for k in range(2, n + 1):
		var c := level_sat(w, k)
		var key := str(k)
		var was: bool = (c >= on) if fresh or not st.ok.has(key) else bool(st.ok[key])
		var now := was
		if was and c < off and not grace:
			now = false
		elif not was and c >= on:
			now = true
		st.ok[key] = now
		miss[k] = _missing(st, k)
		if now != was and int(houses[k]) > 0:
			if now:
				Game.notify_at(w, tr("Häuser der Stufe %d (%s) sind zufrieden. Ihre Bewohner arbeiten wieder als Fachkräfte.") % [k, level_name(k)], "haus", "siedler")
			else:
				Game.notify_at(w, tr("Häuser der Stufe %d (%s) sind unzufrieden, es fehlt: %s. Fachkräfte dieser Stufe fallen aus.") % [k, level_name(k), miss[k]], "haus", "siedler")
	st["_miss"] = miss
	st.erase("fresh")


## Erfüllung eines Bedürfnisses gerade (0..1). Waren werden dabei verbraucht (angefangene Mengen in acc).
func _eval(w, st: Dictionary, nd: Dictionary, cons: float, dt: float) -> float:
	match str(nd.get("kind", "")):
		"food":
			var fd := Game.food_days(w)
			return 1.0 if fd < 0.0 else clampf(fd, 0.0, 1.0)
		"warm":
			return 1.0 if Seasons.is_warm(w) else 0.0
		"variety":
			return minf(1.0, float(Game.food_variety(w)) / maxf(1.0, float(nd.get("sorts", 3))))
		"good":
			var g := str(nd.get("good", ""))
			var acc := float(st.acc.get(g, 0.0)) + float(nd.get("rate", 0.0)) * cons * dt
			var want := int(acc)
			if want <= 0:
				st.acc[g] = acc
				return 1.0 if Game.amount(g, w) > 0 else 0.0
			var got := Game.take_stock(g, want, w)
			st.acc[g] = acc - want  # was fehlt, bleibt nicht als Schuld stehen
			return float(got) / float(want)
		"stock":
			var have := 0
			for g in nd.get("goods", []):
				have += Game.amount(str(g), w)
			var need := float(nd.get("per", 0.5)) * cons
			if need <= 0.0:
				return 1.0 if have > 0 else 0.0
			return minf(1.0, float(have) / need)
		"building":
			var flag := str(nd.get("flag", ""))
			for b in w.buildings:
				if b.complete and b.def.has(flag):
					return 1.0
			return 0.0
	return 1.0


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	state = {}
	_last = -1.0
	_turned_at = {}
	turned_away = 0


func _on_save(d: Dictionary) -> void:
	var out := {}
	for id in state:
		var st: Dictionary = state[id]
		var sat := {}
		for k in st.sat:
			sat[k] = snappedf(float(st.sat[k]), 0.001)
		var acc := {}
		for k in st.acc:
			acc[k] = snappedf(float(st.acc[k]), 0.001)
		out[str(id)] = {"sat": sat, "ok": st.ok.duplicate(), "acc": acc, "grace": float(st.get("grace", 0.0))}
	d["needs"] = out


## Spielstand geladen: Zustand je Insel lesen. Fehlt er (alter Spielstand), gilt alles als erfüllt,
## und einen Tag lang fällt keine Stufe ab (Schonfrist).
func _on_load(data: Dictionary, old_rules: int) -> void:
	state = {}
	_last = Game.time_days
	_turned_at = {}
	var saved = data.get("needs", null)
	var ids := {}
	for k in range(1, levels.size() + 1):
		for nd in level_needs(k):
			ids[str(nd.id)] = k
	for w in Sea.all_worlds():
		var e = saved.get(str(int(w.island_id))) if saved is Dictionary else null
		var st := {"sat": {}, "ok": {}, "acc": {}, "grace": 0.0}
		if e is Dictionary:
			var sat = e.get("sat", {})
			if sat is Dictionary:
				for k in sat:
					if int(ids.get(str(k), 0)) >= 2:
						st.sat[str(k)] = clampf(float(sat[k]), 0.0, 1.0)
			var ok = e.get("ok", {})
			for k in range(2, levels.size() + 1):
				st.ok[str(k)] = bool(ok.get(str(k), true)) if ok is Dictionary else true
			var acc = e.get("acc", {})
			if acc is Dictionary:
				for g in acc:
					if Data.resources.has(str(g)):
						st.acc[str(g)] = maxf(0.0, float(acc[g]))
			st.grace = float(e.get("grace", 0.0))
		else:
			for k in range(2, levels.size() + 1):
				st.ok[str(k)] = true
				for nd in level_needs(k):
					st.sat[str(nd.id)] = 1.0
			st.grace = Game.time_days + float(cfg.get("grace_days", 1.0))
		state[int(w.island_id)] = st
	if old_rules < 1:
		Game.rules_lines.append(tr("Häuser haben Bedürfnisse. Nur zufriedene Häuser stellen Fachkräfte für höhere Werkstätten (z. B. Schmiede ab Holzhaus-Stufe)."))


# ---------------------------------------------------------------- Selbsttest
## Testhilfen (Game.systems): --needstest=1 spielt alle Stufen durch (siehe _needs_test),
## --workerlevels=0 schaltet die Fachkräfte-Sperre ab.
func autotest_setup(args: Dictionary, main) -> void:
	if args.has("workerlevels"):
		Data.balance["worker_levels"] = str(args.workerlevels) != "0"
		print("Bedürfnisse: Fachkräfte-Sperre ", "an" if Data.balance.worker_levels else "aus")
	if args.has("needstest"):
		_needs_test(main, str(args.needstest))  # läuft nebenher weiter (await), der Test beginnt sofort
	if args.has("needsscroll"):
		# Bildschirmfoto-Hilfe: Infofenster nach der Auswahl (--selectb) ein Stück herunterrollen
		Game.selection_changed.connect(func(o):
			if o is Building:
				_scroll_info(main, int(args.needsscroll)))


func _scroll_info(main, px: int) -> void:
	for i in 3:
		await get_tree().process_frame
	var sc = main.hud._info_box.get_parent()
	if sc is ScrollContainer:
		sc.scroll_vertical = px


func autotest_report() -> String:
	for w in Sea.all_worlds():
		var st = _state_of(w)
		var hs: Array = st.get("_houses", []) if st != null else []
		if hs.size() < 3 or int(hs[2]) == 0:
			continue  # nur Inseln mit Häusern ab Stufe 2
		_print_status(w)
	return ""


## Bericht (alle 20 s): Häuser ab Stufe k, Zufriedenheit je Stufe (+ = erfüllt), Haus>zählt-als, Fachkräfte belegt/da.
func _print_status(w) -> void:
	var st = _state_of(w)
	var n := levels.size()
	var hs := []
	var effs := {}
	for b in w.buildings:
		if b.complete and b.house_level() > 0:
			var key := "%d>%d" % [b.house_level(), effective_level(b)]
			effs[key] = int(effs.get(key, 0)) + 1
	for k in range(1, n + 1):
		hs.append(int(st._houses[k]) if st.has("_houses") else 0)
	var sats := []
	var pools := []
	for k in range(2, n + 1):
		sats.append("%d:%.2f%s" % [k, level_sat(w, k), "+" if level_ok(w, k) else "-"])
		var p := pool(w, k)
		pools.append("%d:%d/%d" % [k, p[0], p[1]])
	print("   Bedürfnisse %s: Häuser ab Stufe %s | Zufriedenheit %s | Haus>zählt %s | Fachkräfte %s | abgewiesen %d" % [Sea.island_name(w), hs, " ".join(sats), effs, " ".join(pools), turned_away])


## --needstest=1: alle Hausstufen, Werkstätten der Stufen 2-5, Speichern/Laden, alter Spielstand und vier
## Abschnitte: 1 alles da, 2 Waren ab Stufe 2 fehlen, 3 auch zubereitetes Essen fehlt, 4 alles wieder da.
## --needstest=shot: nur aufbauen, alles da; --needstest=drop: aufbauen, Waren ab Stufe 2 fehlen (Bildschirmfotos).
func _needs_test(main, mode: String) -> void:
	var w = Game.world
	for t in Data.techs:
		if not t in Game.research.done and not Data.techs[t].get("soon", false):
			Game.research.done.append(t)
	Game.research.done.erase("zukunftsstadt")
	Game.research.paid.append("zukunftsstadt")
	Game.research.current = "zukunftsstadt"
	Game._recompute_effects()
	Game.research_changed.emit()
	Data.balance["base_storage"] = 4000
	var places := {}
	for type in ["grosslager", "holzhaus", "steinhaus", "mietshaus", "wohnblock", "schule", "schmelze", "glashuette", "fabrik",
			"fusionsreaktor", "bibliothek", "universitaet"]:
		print("Bedürfnis-Test: platziert ", type, " ", main._place_on(w, type))
	for b in w.buildings:
		places[b.type] = b
	Game.refresh_effects()
	for i in 34:
		w.spawn_newcomer("f" if i % 2 else "m")
	for s in w.settlers:
		s.age = maxf(s.age, 20.0)
		s.hunger = 90.0
	var jobs := ["handwerker", "handwerker", "handwerker", "handwerker", "handwerker", "handwerker", "forscher", "forscher",
		"forscher", "forscher", "forscher", "holzfaeller", "fischer", "sammler"]
	for i in w.settlers.size():
		w.settlers[i].set_job(jobs[i] if i < jobs.size() else "frei")
	var goods_l2 := ["bretter", "werkzeug", "glas", "papier", "gewuerze", "strom", "elektronik"]
	var prepared := ["brot", "raeucherfisch", "eier", "konserven"]
	var stock_up := func(skip: Array):
		for id in ["beeren", "fisch", "aepfel", "weizen", "holz", "stein", "lehm", "kohle", "erz", "eisen", "stahl"] + goods_l2 + prepared:
			w.stock[id] = 0 if id in skip else 80
	stock_up.call([])
	w.assign_homes()
	var homes := {}
	for s in w.settlers:
		var h = w.building_by_id(s.home_id)
		var k: String = h.type if h else "-"
		homes[k] = int(homes.get(k, 0)) + 1
	print("Bedürfnis-Test: %d Siedler, wohnen in %s" % [w.settlers.size(), homes])
	if mode == "shot" or mode == "drop":
		while not Game.is_over and is_instance_valid(w):
			stock_up.call(goods_l2 if mode == "drop" else [])
			await get_tree().create_timer(0.25, true, false, true).timeout
		return
	# Speichern und Laden (über JSON wie im Spiel), dann alter Spielstand ohne "needs"
	for i in 3:
		tick(w, 0.1)
	var d := {}
	_on_save(d)
	var back = JSON.parse_string(JSON.stringify(d))
	var before := _plain(state)
	_on_load(back, 1)
	var same := JSON.stringify(_plain(state)) == JSON.stringify(before)  # stringify sortiert die Schlüssel
	print("Bedürfnis-Test Speichern/Laden: ", d["needs"].get("0", {}).keys(), " gleich=", same)
	if not same:
		print("   vorher  ", before, "\n   nachher ", _plain(state))
	var n_lines := Game.rules_lines.size()
	_on_load({}, 0)
	var st0: Dictionary = state.get(0, {})
	var grace := float(st0.get("grace", 0.0))
	print("Bedürfnis-Test alter Spielstand: ok=", st0.get("ok"), " sat(moebel)=", st0.get("sat", {}).get("moebel"), " Schonfrist bis Tag %.2f (jetzt %.2f)" % [grace, Game.time_days])
	print("Bedürfnis-Test Regelzeile: ", Game.rules_lines.slice(n_lines))
	Game.rules_lines.resize(n_lines)
	_on_load(back, 1)
	# Hysterese von Hand: 0.6 bleibt an, 0.5 geht aus, 0.65 geht nicht an, 0.7 geht an
	var hy := []
	for pair in [[true, 0.6], [true, 0.5], [false, 0.65], [false, 0.7]]:
		var was: bool = pair[0]
		var c: float = pair[1]
		hy.append("%s@%.2f->%s" % [was, c, (false if was and c < float(cfg.off) else (true if not was and c >= float(cfg.on) else was))])
	print("Bedürfnis-Test Hysterese: ", " ".join(hy))
	var watch := ["schmelze", "glashuette", "fabrik", "fusionsreaktor", "bibliothek", "universitaet"]
	var phases := [[], goods_l2, goods_l2 + prepared, []]
	var results := []
	for pi in phases.size():
		match pi:
			0: print("Bedürfnis-Test Abschnitt 1: alles da")
			1: print("Bedürfnis-Test Abschnitt 2: ohne Waren ab Stufe 2 (Bretter, Werkzeug, Glas, Papier, Gewürze, Strom, Elektronik)")
			2: print("Bedürfnis-Test Abschnitt 3: auch ohne zubereitetes Essen")
			3: print("Bedürfnis-Test Abschnitt 4: alles wieder da")
		var skip: Array = phases[pi]
		var t0 := Game.time_days
		var maxw := {}
		var max_used := {}
		while Game.time_days < t0 + 1.6 and not Game.is_over:
			stock_up.call(skip)
			for s in w.settlers:
				s.hunger = maxf(s.hunger, 60.0)
			if Game.time_days >= t0 + 0.9:  # gemessen wird erst, wenn die Glättung durch ist
				for t in watch:
					if places.has(t) and is_instance_valid(places[t]):
						maxw[t] = maxi(int(maxw.get(t, 0)), places[t].occupants.size())
				for k in range(2, levels.size() + 1):
					max_used[k] = maxi(int(max_used.get(k, 0)), used(w, k))
			await get_tree().create_timer(0.25, true, false, true).timeout
		var effs := {}
		for t in ["huette", "holzhaus", "steinhaus", "mietshaus", "wohnblock"]:
			if places.has(t) and is_instance_valid(places[t]):
				effs[t] = "%d>%d" % [places[t].house_level(), effective_level(places[t])]
		var oks := {}
		for k in range(2, levels.size() + 1):
			oks[k] = "%.2f%s" % [level_sat(w, k), "+" if level_ok(w, k) else "-"]
		var caps_now := caps(w)
		var wb = places.get("wohnblock")
		var mother = null
		for s in w.settlers:
			if wb and s.home_id == wb.id and s.sex == "f":
				mother = s
		var bonus: float = Game.home_birth_bonus(w, mother) if mother else -1.0
		var mood: Array = mood_reason(wb, 0.5) if wb else []
		var gate: bool = places.has("holzhaus") and not full_level(places["holzhaus"])
		print("   Ergebnis Tag %.1f: Stufen %s | Haus>zählt %s | Fachkräfte %s, belegt höchstens %s | Arbeiter höchstens %s | Kinder-Bonus Wohnblock %.2f | Laune %s | Holzhaus-Ausbau gesperrt=%s | abgewiesen %d" % [Game.time_days, oks, effs, caps_now.slice(2), max_used, maxw, bonus, mood, gate, turned_away])
		results.append({"ok": oks.duplicate(), "effs": effs, "maxw": maxw, "bonus": bonus, "gate": gate, "mood": mood})
	# Erwartungen
	var r1: Dictionary = results[0]
	var r2: Dictionary = results[1]
	var r3: Dictionary = results[2]
	var r4: Dictionary = results[3]
	var none3 := true
	for t in watch:
		if int(r3.maxw.get(t, 0)) > 0:
			none3 = false
	var sh = places.get("steinhaus")
	var site = w.upgrade_building(sh) if sh and is_instance_valid(sh) else null
	print("Bedürfnis-Test ", _okf(_oks_are(r1, [true, true, true, true])), "1: alle Stufen erfüllt")
	print("Bedürfnis-Test ", _okf(r1.effs.get("wohnblock") == "5>5" and r1.effs.get("holzhaus") == "2>2"), "1: Häuser zählen mit ihrer Stufe")
	print("Bedürfnis-Test ", _okf(int(r1.maxw.get("fabrik", 0)) > 0 and int(r1.maxw.get("fusionsreaktor", 0)) > 0), "1: Werkstätten Stufe 4 und 5 arbeiten")
	print("Bedürfnis-Test ", _okf(float(r1.bonus) > 1.5), "1: Kinder-Bonus im Wohnblock")
	print("Bedürfnis-Test ", _okf(_oks_are(r2, [false, true, false, false])), "2: Stufe 2, 4, 5 aus, Stufe 3 bleibt an (Hysterese 0.6)")
	print("Bedürfnis-Test ", _okf(r2.effs.get("holzhaus") == "2>1" and r2.effs.get("wohnblock") == "5>3"), "2: Holzhaus zählt als 1, Wohnblock als 3")
	print("Bedürfnis-Test ", _okf(int(r2.maxw.get("fabrik", 0)) == 0 and int(r2.maxw.get("fusionsreaktor", 0)) == 0), "2: Stufe 4 und 5 ohne Arbeiter")
	print("Bedürfnis-Test ", _okf(int(r2.maxw.get("glashuette", 0)) > 0 or int(r2.maxw.get("universitaet", 0)) > 0), "2: Stufe 3 arbeitet weiter")
	print("Bedürfnis-Test ", _okf(r2.gate and float(r2.bonus) == 1.0 and not r2.mood.is_empty() and float(r2.mood[1]) < 0.0), "2: Ausbau gesperrt, kein Kinder-Bonus, Laune sinkt")
	print("Bedürfnis-Test ", _okf(_oks_are(r3, [false, false, false, false])), "3: alle Stufen aus")
	print("Bedürfnis-Test ", _okf(none3), "3: keine Fachkraft an Plätzen ab Stufe 2")
	print("Bedürfnis-Test ", _okf(_oks_are(r4, [true, true, true, true]) and int(r4.maxw.get("fusionsreaktor", 0)) > 0), "4: alles erholt, Stufe 5 arbeitet wieder")
	print("Bedürfnis-Test ", _okf(site != null and site.type == "mietshaus" and not site.complete), "4: Steinhaus lässt sich zum Mietshaus ausbauen")


func _okf(cond: bool) -> String:
	return "OK     " if cond else "FEHLER "


## Stimmen die ok-Flags eines Abschnitts (Stufen 2..5) mit want überein?
func _oks_are(r: Dictionary, want: Array) -> bool:
	for k in range(2, levels.size() + 1):
		if str(r.ok[k]).ends_with("+") != bool(want[k - 2]):
			return false
	return true


## Zustand ohne Laufzeit-Schlüssel, Zahlen gerundet wie im Spielstand (zum Vergleichen).
func _plain(s: Dictionary) -> Dictionary:
	var out := {}
	for id in s:
		var e := {}
		for k in s[id]:
			if str(k).begins_with("_"):
				continue
			var v = s[id][k]
			if v is Dictionary:
				var vv := {}
				for kk in v:
					vv[str(kk)] = snappedf(float(v[kk]), 0.001) if (v[kk] is float or v[kk] is int) else v[kk]
				v = vv
			e[str(k)] = v
		out[str(id)] = e
	return out
