extends Node
## Forschung braucht Schriften (Regeln ab Version 2, Teil E).
## Forscher verbrauchen ab der Antike Schreibwaren aus dem Lager ihrer eigenen Insel: je 100
## gutgeschriebene Forschungspunkte die Mengen aus techs.json `_ages[i].writing` (Antike 10 Tontafeln,
## Mittelalter 4 Tontafeln, Renaissance 2,5 Papier ...). Eine Ware zaehlt nur, wenn schon ein Gebaeude
## freigeschaltet ist, das sie herstellt; laesst sich keine Ware des Zeitalters herstellen, gilt die
## Liste des Zeitalters davor (wiederholt). Fehlt eine Ware im Lager, gibt es nur
## balance.writing_missing_factor (0,2) der Punkte. Passive Forschung und Punkte aus Belohnungen
## (Game.add_research direkt) bleiben frei. Gespeichert wird nichts (angefangene Einheiten liegen in
## World.writing_debt und gehen beim Laden verloren, hoechstens eine Einheit je Ware).

var _cache: Dictionary = {}  # Forschung -> {Ware: Einheiten je 100 Punkte}, geleert in Game._recompute_effects
var _producers: Dictionary = {}  # Ware -> baubare Gebaeudetypen, die sie herstellen
## Zaehler fuer Selbsttest und Bericht (seit Programmstart, nicht gespeichert)
var used: Dictionary = {}  # Ware -> verbrauchte Einheiten
var cycles := 0  # Arbeitsgaenge von Forschern, die Schreibwaren brauchten
var slow_cycles := 0  # davon langsam, weil etwas fehlte

var _test_w = null  # Selbsttest --writingtest: Insel
var _test_last := 0.0  # Fortschritt am letzten Tagesbeginn
var _test_tech := ""


func _ready() -> void:
	Game.register_system(self)
	Game.state_load.connect(_on_state_load)


func _on_state_load(_data: Dictionary, old_rules: int) -> void:
	clear_cache()
	if old_rules < 1:
		Game.rules_lines.append(tr("Forschung ab der Antike verbraucht Tontafeln (Tafelmacherei), später Papier, Strom und Elektronik. Forschungen kosten mehr."))


## Freischaltungen haben sich geaendert (Game._recompute_effects: Forschung fertig, Laden, neues Spiel).
func clear_cache() -> void:
	_cache.clear()


## Baubare Gebaeudetypen, die diese Ware herstellen.
func producers_of(good: String) -> Array:
	if not _producers.has(good):
		var out := []
		for type in Data.buildings:
			var def: Dictionary = Data.buildings[type]
			if def.get("buildable", true) and def.get("production", {}).get("outputs", {}).has(good):
				out.append(type)
		_producers[good] = out
	return _producers[good]


## Die Ware laesst sich herstellen: mindestens ein Gebaeude dafuer ist freigeschaltet.
func producible(good: String) -> bool:
	for type in producers_of(good):
		if Game.is_unlocked(type):
			return true
	return false


## Schreibwaren beim Erforschen von t: {Ware: Einheiten je 100 Punkte}, leer = frei.
func goods_for(t: String) -> Dictionary:
	if t == "" or not Data.techs.has(t):
		return {}
	if _cache.has(t):
		return _cache[t]
	var out := {}
	var a := Data.age_of_tier(int(Data.techs[t].get("tier", 1)))
	while a >= 0 and out.is_empty():
		var raw: Dictionary = Data.ages[a].get("writing", {}) if a < Data.ages.size() else {}
		if raw.is_empty():
			break
		for id in raw:
			if Data.resources.has(id) and producible(id):
				out[id] = float(raw[id])
		a -= 1  # nichts davon herstellbar: Waren des Zeitalters davor
	_cache[t] = out
	return out


## Wie viele Einheiten die Forschung t bis zum Ende noch braucht: {Ware: Menge}.
func left_for(t: String) -> Dictionary:
	var out := {}
	var rates := goods_for(t)
	var rest := maxf(0.0, Game.tech_points(t) - Game.tech_progress(t))
	for id in rates:
		out[id] = maxi(0, ceili(rest * float(rates[id]) / 100.0 - 0.001))
	return out


## Waren der Forschung t, von denen auf Insel w keine ganze Einheit mehr da ist.
func missing_at(w, t: String) -> Array:
	var out := []
	for id in goods_for(t):
		if Game.amount(id, w) < 1:
			out.append(id)
	return out


## "24 Tontafeln, 238 Strom"
func goods_text(d: Dictionary) -> String:
	var parts := []
	for id in d:
		parts.append("%d %s" % [int(d[id]), Data.resource_name(id)])
	return ", ".join(parts)


func names_text(ids: Array) -> String:
	return ", ".join(ids.map(func(id): return Data.resource_name(id)))


## Ein Forscher auf Insel w hat pts Punkte erarbeitet (mit Forschungsbonus). Nimmt je Ware
## pts * Rate / 100 aus dem Lager der Insel (Bruchteile sammeln sich in w.writing_debt) und liefert 1.0.
## Fehlt eine Ware ganz: nichts wird verbraucht, Meldung hoechstens einmal am Tag je Insel, Faktor 0,2.
func consume(w, rates: Dictionary, pts: float) -> float:
	if rates.is_empty() or pts <= 0.0 or w == null:
		return 1.0
	cycles += 1
	var missing := []
	for id in rates:
		if Game.amount(id, w) < 1:
			missing.append(id)
	if not missing.is_empty():
		slow_cycles += 1
		_warn(w, missing)
		return float(Data.bal("writing_missing_factor", 0.2))
	for id in rates:
		var d := float(w.writing_debt.get(id, 0.0)) + pts * float(rates[id]) / 100.0
		var n := int(floor(d))
		if n > 0:
			n = Game.take_stock(id, n, w)
			used[id] = int(used.get(id, 0)) + n
			Game.stats["writing_used"] = int(Game.stats.get("writing_used", 0)) + n
		w.writing_debt[id] = d - n
	return 1.0


## Namen der Gebaeude, die fuer die fehlenden Waren gebaut werden sollten (keins davon steht auf w),
## und solche, die zwar stehen, aber gerade nichts liefern.
func _producer_hint(w, missing: Array) -> Array:
	var build := []
	var check := []
	for id in missing:
		var unlocked: Array = producers_of(id).filter(func(type): return Game.is_unlocked(type))
		if unlocked.is_empty():
			continue
		var here = null
		for b in w.buildings:
			if b.type in unlocked:
				here = b
				break
		var name: String = Data.buildings[unlocked[0] if here == null else here.type].name
		if here == null:
			if not name in build:
				build.append(name)
		elif not name in check:
			check.append(name)
	return [build, check]


func _warn(w, missing: Array) -> void:
	if Game.time_days - float(w.writing_warn_time) < 1.0:
		return
	w.writing_warn_time = Game.time_days
	var hint := _producer_hint(w, missing)
	var text := ""
	if not hint[0].is_empty():
		text = tr("Den Forschern fehlen %s, sie forschen nur noch langsam. Baue: %s.") % [names_text(missing), ", ".join(hint[0])]
	else:
		text = tr("Den Forschern fehlen %s, sie forschen nur noch langsam. Prüfe: %s (braucht einen Arbeiter und Rohstoffe).") % [names_text(missing), ", ".join(hint[1])]
	Game.notify_at(w, text, "wissen", "forschung")


## Taetigkeit eines Forschers nach einem Arbeitsgang (f = Faktor aus consume).
func research_activity(f: float, w) -> String:
	var t: String = Game.research.current
	if t == "" or not Data.techs.has(t):
		return tr("Forscht")
	if f < 1.0:
		return tr("Forscht langsam, es fehlen %s") % names_text(missing_at(w, t))
	return tr("Forscht: %s") % Data.techs[t].name


## Forschungsfenster, Kopf: [Verbrauch und Lager, rote Zeile wenn etwas fehlt] fuer Insel w.
func head_lines(w, researchers: int) -> Array:
	var t: String = Game.research.current
	var left := left_for(t)
	if left.is_empty():
		return ["", ""]
	var parts := []
	for id in left:
		parts.append(tr("%d %s (Lager: %d)") % [int(left[id]), Data.resource_name(id), Game.amount(id, w)])
	var use := tr("Noch nötig: %s") % ", ".join(parts)
	var miss := missing_at(w, t)
	var warn := ""
	if not miss.is_empty() and researchers > 0:
		warn = tr("Es fehlen %s: Forschung nur %d %%.") % [names_text(miss), roundi(float(Data.bal("writing_missing_factor", 0.2)) * 100.0)]
		var hint := _producer_hint(w, miss)
		if not hint[0].is_empty():
			warn += " " + tr("Baue: %s.") % ", ".join(hint[0])
	return [use, warn]


## Zeile in der Liste der Forschungen: "Beim Forschen: 24 Tontafeln" ("" = frei).
func row_text(t: String) -> String:
	var left := left_for(t)
	return tr("Beim Forschen: %s") % goods_text(left) if not left.is_empty() else ""


## Infofenster eines Forschungsgebaeudes auf Insel w: [Text, fehlt etwas].
func info_line(w) -> Array:
	var t: String = Game.research.current
	var g := goods_for(t)
	if g.is_empty():
		if Game.current_age() < 1:
			return [tr("Ab der Antike brauchen Forscher Tontafeln."), false]
		return ["", false]
	var parts := []
	for id in g:
		parts.append(tr("%s (Lager: %d)") % [Data.resource_name(id), Game.amount(id, w)])
	return [tr("Verbraucht beim Forschen: %s") % ", ".join(parts), not missing_at(w, t).is_empty()]


## Ueberschrift eines Zeitalters: welche Schreibwaren Forscher dort brauchen ("" = keine).
func age_text(a: int) -> String:
	if a < 0 or a >= Data.ages.size():
		return ""
	var raw: Dictionary = Data.ages[a].get("writing", {})
	if raw.is_empty():
		return ""
	return tr("Forscher brauchen: %s") % names_text(raw.keys())


# ---------------------------------------------------------------- Selbsttest
## --writingtest=1: Stufe 1-4 erforscht ausser Schmiedekunst, Schreibstube, Lehmgrube und Tafelmacherei,
## zwei Forscher, ein Handwerker, ein Steinmetz, keine Tontafeln: erst 20 %, dann volle Fahrt.
## --writingtest=2: dasselbe ohne Tafelmacherei (bleibt langsam).
## --build=1 --research=1: baut ab der Toepferei Lehmgrube und Tafelmacherei und teilt Arbeiter ein.
func autotest_setup(args: Dictionary, main) -> void:
	if args.has("writingtest"):
		_writing_test(int(args.writingtest), main)
	elif args.has("research") and args.has("build"):
		_bot_loop(main)
	if args.has("researchscroll"):
		_scroll_research(main, str(args.researchscroll))


func autotest_report() -> String:
	var t: String = Game.research.current
	if goods_for(t).is_empty() and cycles == 0:
		return ""
	var w = Game.world
	print("   Schriften: Forschung %s braucht %s je 100 Pkt (noch %s), verbraucht %s (gesamt %d), langsam %d von %d Arbeitsgaengen, Lager tontafel=%d papier=%d strom=%d elektronik=%d" % [t, goods_for(t), left_for(t), used, int(Game.stats.get("writing_used", 0)), slow_cycles, cycles, Game.amount("tontafel", w), Game.amount("papier", w), Game.amount("strom", w), Game.amount("elektronik", w)])
	return ""


func _writing_test(mode: int, main) -> void:
	var w = main.world
	_test_w = w
	_test_tech = "schmiedekunst"
	_check_fallback()
	for t in Data.techs:
		if int(Data.techs[t].tier) <= 4 and t != _test_tech and not t in Game.research.done:
			Game.research.done.append(t)
	Game._recompute_effects()
	Game.research_changed.emit()
	var types := ["schreibstube", "lehmgrube", "steinhaus"]
	if mode == 1:
		types.append("tafelmacherei")
	for type in types:
		print("Schrifttest: platziert ", type, " ", main._place_on(w, type))
	Game.refresh_effects()
	Data.balance["base_storage"] = 4000  # Testlauf: genug Stauraum, damit keine Tafel verloren geht
	w.stock["tontafel"] = 0
	w.stock["lehm"] = 0
	for id in ["eisen", "kohle"]:
		w.stock[id] = 8
	for id in ["beeren", "fisch"]:
		w.stock[id] = maxi(Game.amount(id, w), 60)
	var roles := ["forscher", "forscher", "handwerker", "steinmetz"]
	for i in roles.size():
		var s = w.spawn_newcomer("f" if i % 2 == 0 else "m", {"hunger": 90.0})
		if s:
			s.set_job(roles[i])
	_self_check(w)
	print("Schrifttest modus=", mode, ": Start ", _test_tech, " -> '", Game.start_research(_test_tech), "' braucht ", goods_for(_test_tech), " je 100 Pkt, insgesamt ", left_for(_test_tech), " bei ", int(Game.tech_points(_test_tech)), " Pkt, Faktor ohne Tafeln ", Data.bal("writing_missing_factor", 0.2))
	_test_last = 0.0
	Game.day_started.connect(_test_day)



## Bildschirmfoto-Hilfe --researchscroll=<forschung>: sobald das Forschungsfenster offen ist, bis zu dieser
## Forschung rollen (z. B. --panel=research --researchscroll=schmiedekunst).
func _scroll_research(main, tid: String) -> void:
	while is_instance_valid(main) and not main.hud._research_panel.visible:
		await get_tree().process_frame
	for i in 3:
		await get_tree().process_frame
	for row in main.hud._research_list.get_children():
		if row.get_meta("tid", "") == tid:
			main.hud._research_scroll.scroll_vertical = maxi(0, int(row.position.y) - 60)


## Prueft World.use_writing direkt: ohne Tafeln 0,2, mit Tafeln 1,0 und Verbrauch (Rest als Bruchteil).
func _self_check(w) -> void:
	var rates := {"tontafel": 10.0}
	var f0: float = w.use_writing(rates, 15.0)
	w.stock["tontafel"] = 5
	var f1: float = w.use_writing(rates, 15.0)
	print("Schrifttest use_writing: ohne Tafeln f=%.2f, mit 5 Tafeln f=%.2f, danach Lager %d, Rest %.2f (erwartet 0.20 / 1.00 / 4 / 0.50) %s" % [f0, f1, Game.amount("tontafel", w), float(w.writing_debt.get("tontafel", 0.0)),
		"OK" if is_equal_approx(f0, 0.2) and is_equal_approx(f1, 1.0) and Game.amount("tontafel", w) == 4 else "FEHLER"])
	w.stock["tontafel"] = 0
	w.writing_debt.clear()
	w.writing_warn_time = -10.0
	used.clear()
	cycles = 0
	slow_cycles = 0
	Game.stats["writing_used"] = 0


## Rueckfall-Regel: mit verschiedenen erforschten Staenden die Schreibwaren einiger Forschungen pruefen.
func _check_fallback() -> void:
	var saved: Array = Game.research.done.duplicate()
	var upto := func(tier: int, extra: Array, without: Array) -> Array:
		var out := []
		for t in Data.techs:
			if (int(Data.techs[t].tier) <= tier or t in extra) and not t in without:
				out.append(t)
		return out
	# [hoechste erforschte Stufe, zusaetzlich erforscht, nicht erforscht, Forschung, erwartet]
	var cases := [
		[2, [], ["toepferei", "brunnenbau"], "heilkunde", {}],
		[2, [], [], "heilkunde", {"tontafel": 30}],
		[4, [], [], "baumeisterkunst", {"tontafel": 40}],
		[6, [], [], "papier", {"tontafel": 156}],
		[6, ["papier"], [], "glasmacherei", {"papier": 105}],
		[10, [], [], "elektrizitaet", {"papier": 119}],
		[10, ["elektrizitaet"], [], "telegraf", {"papier": 119, "strom": 238}],
		[12, [], [], "computer", {"strom": 350}],
		[12, ["computer"], [], "solarenergie", {"strom": 350, "elektronik": 27}],
		[14, [], [], "ki", {"strom": 413, "elektronik": 28}],
		[15, [], [], "zukunftsstadt", {"strom": 600, "elektronik": 40}],
	]
	var bad := 0
	for c in cases:
		Game.research.done = upto.call(c[0], c[1], c[2])
		Game._recompute_effects()
		var got := left_for(c[3])
		var ok: bool = got == c[4]
		bad += 0 if ok else 1
		print("Rueckfall-Pruefung [Stufe 1-%d, dazu %s, ohne %s] %s: je 100 Pkt %s insgesamt %s erwartet %s %s" % [c[0], c[1], c[2], c[3], goods_for(c[3]), got, c[4], "OK" if ok else "FEHLER"])
	print("Rueckfall-Pruefung: ", "alle OK" if bad == 0 else "%d FEHLER" % bad)
	Game.research.done = saved
	Game._recompute_effects()


func _test_day(d: int) -> void:
	var w = _test_w
	if w == null or not is_instance_valid(w):
		return
	var t := _test_tech
	var done: bool = t in Game.research.done
	var prog: float = Game.tech_points(t) if done else Game.tech_progress(t)
	var made := Game.amount("tontafel", w) + int(used.get("tontafel", 0))
	var fin := "fertig" if done else "offen"
	print("Schrifttest Tag %d: %s %d/%d (+%d Pkt am Tag, %s), Tontafeln: Lager %d, hergestellt %d, verbraucht %d, Lehm %d, langsame Arbeitsgaenge %d von %d" % [d, t, int(prog), int(Game.tech_points(t)), int(prog - _test_last), fin, Game.amount("tontafel", w), made, int(used.get("tontafel", 0)), Game.amount("lehm", w), slow_cycles, cycles])
	_test_last = prog


## Forschungs-Bot (--build=1 --research=1): sobald eine bezahlte Forschung Tontafeln braucht, erst die
## Tafelmacherei, dann die Lehmgrube bauen (je eine Baustelle) und je einen freien Erwachsenen als
## Steinmetz und Handwerker einteilen (nur bei genug Essen und mindestens vier Erwachsenen; wird das Essen
## knapp, sind beide wieder frei). Beide Werkstaetten halten an, wenn genug auf Vorrat liegt
## (Tontafeln 40, Lehm 24, reicht auch fuer die Koehlerei), und laufen wieder unter 20 bzw. 8.
var _bot_said := {}


func _bot_loop(main) -> void:
	while is_instance_valid(main) and not Game.is_over:
		await get_tree().create_timer(3.0, true, false, true).timeout
		if is_instance_valid(main):
			_bot_tick(main)


func _bot_tick(main) -> void:
	var w = main.world
	if w == null or not is_instance_valid(w) or not Game.is_unlocked("tafelmacherei"):
		return
	var started: bool = w.buildings.any(func(b): return b.type == "tafelmacherei")
	if not started and not goods_for(Game.research.current).has("tontafel"):
		return
	for type in ["tafelmacherei", "lehmgrube"]:
		var have: Array = w.buildings.filter(func(b): return b.type == type)
		if have.is_empty():
			var placed := _bot_place(main, w, type)
			if placed or not _bot_said.has(type):
				print("Schriften-Bot: Baustelle ", type, " ", placed, " (Forschung ", Game.research.current, ")")
				_bot_said[type] = true
			return
		if not have[0].complete:
			return
	for b in w.buildings:
		var stock_n := Game.amount("tontafel" if b.type == "tafelmacherei" else "lehm", w)
		if b.type == "tafelmacherei":
			b.paused = stock_n > 20 if b.paused else stock_n >= 40
		elif b.type == "lehmgrube":
			b.paused = stock_n > 8 if b.paused else stock_n >= 24
	# Nur einteilen, wenn genug Essen da ist; bei Hunger sammeln alle wieder Nahrung
	var adults: Array = w.settlers.filter(func(s): return s.is_adult())
	var fd := Game.food_days(w)
	if fd >= 0.0 and fd < 0.5:
		for s in adults:
			if s.job in ["steinmetz", "handwerker"]:
				s.set_job("frei")
				print("Schriften-Bot: ", s.display_name, " wieder frei (Essen knapp)")
		return
	if fd < 1.5 or adults.size() < 4:
		return
	for pair in [["lehmgrube", "steinmetz"], ["tafelmacherei", "handwerker"]]:
		if w.settlers.any(func(s): return s.job == pair[1]):
			continue
		for s in w.settlers:
			if s.is_adult() and s.job == "frei":
				s.set_job(pair[1])
				print("Schriften-Bot: ", s.display_name, " wird ", pair[1])
				break


func _bot_place(main, w, type: String) -> bool:
	for rad in range(4, 16):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var cc: Vector2i = w.center + Vector2i(dx, dy)
				if w.can_place(type, cc) and main._roomy(type, cc):
					w.place_building(type, cc, false)
					return true
	return false
