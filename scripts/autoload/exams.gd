extends Node
## Pruefungen beim Zeitalterwechsel und Wertung (Regeln ab Version 2, Teil J).
## Ein neues Zeitalter beginnt erst nach einer Pruefung: Forschungen eines Zeitalters a sind nur
## moeglich, wenn a <= passed (sonst Zustand "exam", Game.tech_state). Game.current_age() = passed.
## Pruefung i steht in techs.json `_ages[i].exam` = {checks: [...], fest_days, reward} und oeffnet das
## Zeitalter i+1. Bedingungen sind Ziel-Pruefungen (GoalChecks), Waren werden nur gezaehlt (alle Inseln),
## nie verbraucht. Sind alle erfuellt, ist die Pruefung bestanden (alle 0,25 Tage geprueft, nur wenn das
## Spiel laeuft): Fest (Laune +fest_mood fuer fest_days), Einwanderer und Waren (Game.grant_reward auf die
## besiedelte Insel mit den meisten freien Wohnplaetzen), Meldung "Ein neues Zeitalter beginnt".
## Wertung (Punkte) und Rekorde (user://settings.cfg [records], Testversionen [records_test], [records_neu]).
## Spielstand: Schluessel "exams" = {passed, days, fest_until, year, y_starved, beaten}.

const CHECK_DAYS := 0.25
const SETTINGS := "user://settings.cfg"

var passed := 0  # bestandene Pruefungen = aktuelles Zeitalter
var days: Array = []  # days[i]: time_days, als Pruefung i bestanden wurde (Zeitalter i+1 begann), -1 = uebernommen
var fest_until := 0.0  # Fest des neuen Zeitalters bis (time_days)
var year := 1  # Jahr, fuer das y_starved gilt (Jahre ohne Hungertod)
var y_starved := 0  # stats.starved zu Beginn dieses Jahres
var beaten: Array = []  # Rekorde, die dieses Spiel gebrochen hat (Schluessel)
var last_result: Dictionary = {}  # Spielende: {score, beaten}

var _next := 0.0
var _fest_next := 0.0
var _block_cache := [-100000, false]
var _goal_cache := [-100000, {}]
var _strict := false  # Selbsttest: --strictexam (der Forschungs-Bot ueberspringt keine Pruefung)
var _test := {}  # Selbsttest --examtest


func _ready() -> void:
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)
	Game.day_started.connect(_on_day)
	Game.game_over.connect(final_result)
	Game.research_changed.connect(_on_research_changed)


func _on_research_changed() -> void:
	_block_cache[0] = -100000
	_goal_cache[0] = -100000
	_next = minf(_next, Game.time_days)  # gleich pruefen (z. B. genug Forschungen des Zeitalters)


func _process(_delta: float) -> void:
	if Game.world == null or Game.is_over or Game.speed <= 0:
		return
	if Game.time_days >= _next:
		_next = Game.time_days + CHECK_DAYS
		check()
	if Game.time_days < fest_until and Game.time_days >= _fest_next:
		_fest_next = Game.time_days + 0.1
		_fest_text(2)


# ---------------------------------------------------------------- Zustand
func _on_reset() -> void:
	passed = 0
	days = []
	fest_until = 0.0
	year = Seasons.year()
	y_starved = 0
	beaten = []
	last_result = {}
	_next = 0.0
	_fest_next = 0.0
	_on_research_changed()


func _on_save(data: Dictionary) -> void:
	data["exams"] = {"passed": passed, "days": days.duplicate(), "fest_until": fest_until, "year": year,
		"y_starved": y_starved, "beaten": beaten.duplicate()}


## Alter Spielstand (ohne "exams"): bestanden gilt alles bis zum spaetesten Zeitalter, aus dem etwas
## erforscht, bezahlt oder gerade in Arbeit ist (nichts Bezahltes wird gesperrt). Tage = -1 (keine Rekorde).
func _on_load(data: Dictionary, old_rules: int) -> void:
	var e = data.get("exams", null)
	last_result = {}
	_next = 0.0
	_fest_next = 0.0
	if e is Dictionary:
		passed = int(e.get("passed", 0))
		days = Array(e.get("days", [])).map(func(x): return float(x))
		fest_until = float(e.get("fest_until", 0.0))
		year = int(e.get("year", Seasons.year()))
		y_starved = int(e.get("y_starved", Game.stats.get("starved", 0)))
		beaten = Array(e.get("beaten", [])).map(func(x): return str(x))
	else:
		passed = 0
		days = []
		fest_until = 0.0
		year = Seasons.year()
		y_starved = int(Game.stats.get("starved", 0))
		beaten = []
	passed = clampi(maxi(passed, researched_age(true)), 0, maxi(0, Data.ages.size() - 1))
	if days.size() > passed:
		days.resize(passed)
	while days.size() < passed:
		days.append(-1.0)
	_on_research_changed()
	if old_rules < 1:
		Game.rules_lines.append(tr("Ein neues Zeitalter beginnt erst nach einer Prüfung. Jede bestandene Prüfung bringt ein Fest, Einwanderer und Waren. Neu: Menü > Wertung mit Rekorden."))


## Game._recompute_effects: Testhilfen und alte Spielstaende, die Forschungen direkt als erledigt
## eintragen, ziehen die bestandenen Pruefungen nach (im normalen Spiel nie noetig).
func sync() -> void:
	var a := researched_age(false)
	if a > passed:
		passed = mini(a, maxi(0, Data.ages.size() - 1))
		while days.size() < passed:
			days.append(-1.0)
		_block_cache[0] = -100000


## Spaetestes Zeitalter mit erforschter (with_paid: auch bezahlter oder laufender) Forschung.
func researched_age(with_paid: bool = false) -> int:
	var ids: Array = Game.research.get("done", []).duplicate()
	if with_paid:
		ids.append_array(Game.research.get("paid", []))
		ids.append(str(Game.research.get("current", "")))
	var a := 0
	for t in ids:
		if Data.techs.has(t):
			a = maxi(a, Data.age_of_tier(int(Data.techs[t].tier)))
	return a


func current_age() -> int:
	return clampi(passed, 0, maxi(0, Data.ages.size() - 1))


## Forschung t wartet auf eine Pruefung (ihr Zeitalter ist noch nicht erreicht).
func gates(t: String) -> bool:
	return Data.techs.has(t) and Data.age_of_tier(int(Data.techs[t].get("tier", 1))) > passed


# ---------------------------------------------------------------- Pruefungen
func exam_def(i: int) -> Dictionary:
	if i < 0 or i >= Data.ages.size() - 1:
		return {}
	var e = Data.ages[i].get("exam", {})
	return e if e is Dictionary else {}


## Bedingungen der Pruefung i: [[check, aktueller Wert, Zielwert, erfuellt], ...]
func status(i: int) -> Array:
	var out := []
	for c in exam_def(i).get("checks", []):
		if c is Dictionary:
			var p := GoalChecks.progress(c)
			out.append([c, int(p[0]), int(p[1]), int(p[0]) >= int(p[1])])
	return out


func all_met(i: int) -> bool:
	var st := status(i)
	return not st.is_empty() and st.all(func(x): return x[3])


## Prueft die aktuelle Pruefung und besteht sie, wenn alles erfuellt ist.
func check() -> bool:
	if exam_def(passed).is_empty() or not all_met(passed):
		return false
	pass_exam()
	return true


## Eine Forschung wartet auf die Pruefung (Zustand "exam").
func gated() -> bool:
	for t in Data.techs:
		if Game.tech_state(t) == "exam":
			return true
	return false


## Nur noch die Pruefung bringt die Forschung weiter: keine Forschung laeuft oder ist waehlbar.
func only_exam_left() -> bool:
	if exam_def(passed).is_empty():
		return false
	var any_exam := false
	for t in Data.techs:
		var st := Game.tech_state(t)
		if st == "available" or st == "current":
			return false
		any_exam = any_exam or st == "exam"
	return any_exam


## Die Pruefung haelt das Weiterforschen auf (Zielkarte zeigt sie dann vor den Zielen): eine Forschung
## wartet auf sie, und entweder reichen die Forschungen des Zeitalters schon oder es gibt nichts anderes
## mehr zu erforschen. Zwischengespeichert (die Zielkarte fragt jedes Bild).
func blocking() -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_block_cache[0]) < 400:
		return bool(_block_cache[1])
	var v := false
	if not exam_def(passed).is_empty() and gated():
		v = only_exam_left()
		if not v:
			for x in status(passed):
				if str(x[0].get("type", "")) == "age_techs" and x[3]:
					v = true
	_block_cache = [now, v]
	return v


## Pseudo-Ziel fuer die Zielkarte (GoalCard): id "exam_<i>", Fortschritt = erfuellte Bedingungen.
func goal() -> Dictionary:
	var now := Time.get_ticks_msec()
	if now - int(_goal_cache[0]) < 400 and str(_goal_cache[1].get("id", "")) == "exam_%d" % passed:
		return _goal_cache[1]
	var g := {"id": "exam_%d" % passed, "text": tr("Bestehe die Prüfung für das Zeitalter %s.") % Data.age_name(passed + 1),
		"hint": missing_text(false) + " " + tr("Belohnung: %s.") % reward_text(passed), "check": {"type": "exam", "age": passed}}
	_goal_cache = [now, g]
	return g


## "Es fehlt noch: Siedler 4/6, Holzhaus oder besser 0/1." (with_head: mit "Erst die Pruefung ...")
func missing_text(with_head: bool = true) -> String:
	var miss := []
	for x in status(passed):
		if not x[3]:
			miss.append("%s %d/%d" % [GoalChecks.label(x[0]), x[1], x[2]])
	var t := tr("Es fehlt noch: %s.") % ", ".join(miss) if not miss.is_empty() else tr("Alles erfüllt, die Prüfung ist gleich bestanden.")
	if with_head:
		t = tr("Erst die Prüfung für das Zeitalter %s bestehen.") % Data.age_name(passed + 1) + " " + t
	return t


## "2 Einwanderer, 10 Bretter, 10 Ziegel und ein Fest"
func reward_text(i: int) -> String:
	var r: Dictionary = exam_def(i).get("reward", {})
	var parts := []
	var n := int(r.get("settlers", 0))
	if n == 1:
		parts.append(tr("1 Einwanderer"))
	elif n > 1:
		parts.append(tr("%d Einwanderer") % n)
	for id in r:
		if str(id) != "settlers" and Data.resources.has(str(id)):
			parts.append("%d %s" % [int(r[id]), Data.resource_name(str(id))])
	return tr("%s und ein Fest") % ", ".join(parts) if not parts.is_empty() else tr("ein Fest")


## Pruefung bestanden: naechstes Zeitalter, Fest, Einwanderer und Waren, Meldung.
func pass_exam() -> void:
	var i := passed
	var def := exam_def(i)
	if def.is_empty():
		return
	passed = i + 1
	while days.size() < i:
		days.append(-1.0)
	if days.size() > i:
		days.resize(i)
	days.append(Game.time_days)
	fest_until = Game.time_days + float(def.get("fest_days", 1.0))
	_fest_next = Game.time_days + 0.1
	_on_research_changed()
	var w = Game.immigrant_world()
	if w == null:
		w = Game.world
	var got := Game.grant_reward(w, def.get("reward", {}))
	var a := current_age()
	Game.notify(tr("Prüfung bestanden! Ein neues Zeitalter beginnt: %s! %s") % [Data.age_name(a), Data.ages[a].get("desc", "")], "zeitalter")
	if got != "":
		Game.notify_at(w, tr("Zum Fest kommen Geschenke: %s.") % got, "zeitalter")
	Sound.play("stufe")
	_fest_text(99)
	Game.research_changed.emit()
	Game.stock_changed.emit()
	_daily_stats()
	update_records()


## "Fest!" ueber Siedlern der sichtbaren Insel (hoechstens n).
func _fest_text(n: int) -> void:
	var w = Game.world
	if w == null or not is_instance_valid(w) or w.settlers.is_empty():
		return
	var list: Array = w.settlers.duplicate()
	list.shuffle()
	for s in list.slice(0, n):
		w.float_text(s.position + Vector2(0, -30), tr("Fest!"), "")


## Laune: "Feiert das neue Zeitalter" waehrend des Fests (SettlerMind._update_mood).
func fest_active() -> bool:
	return Game.time_days < fest_until


# ---------------------------------------------------------------- Wertung
## Tage seit dem letzten Hungertod (oder seit Spielbeginn bzw. seit die neuen Regeln gelten).
func streak() -> float:
	return maxf(0.0, Game.time_days - float(Game.stats.get("starve_day", Game.rules_day)))


func _on_day(_d: int) -> void:
	_daily_stats()
	update_records()


## Taeglich: Jahre ohne Hungertod, laengste Zeit ohne Hungertod, Zukunftsstadt gebaut.
func _daily_stats() -> void:
	var st: Dictionary = Game.stats
	var y := Seasons.year()
	if y > year:
		if int(st.get("starved", 0)) <= y_starved:
			st["good_years"] = int(st.get("good_years", 0)) + 1
		year = y
		y_starved = int(st.get("starved", 0))
	elif y < year:
		year = y
	st["best_streak"] = maxf(float(st.get("best_streak", 0.0)), streak())
	if int(st.get("future_city", 0)) == 0:
		for w in Sea.all_worlds():
			for b in w.buildings:
				if b.type == "zukunftsstadt" and b.complete:
					st["future_city"] = 1


## [[Kategorie, Wert, Punkte], ...]; die Punkte nehmen nie ab.
func score_parts() -> Array:
	var st: Dictionary = Game.stats
	var settled := 0
	for m in Sea.islands:
		if str(m.get("state", "")) != "discovered":
			settled += 1
	var rows := [[tr("Höchste Bevölkerung"), int(st.get("max_pop", 0)), 10],
		[tr("Besiedelte Inseln"), settled, 50],
		[tr("Entdeckte Inseln"), maxi(0, Sea.islands.size() - 1), 10],
		[tr("Forschungen"), Game.research.done.size(), 15],
		[tr("Bestandene Prüfungen"), passed, 250],
		[tr("Erreichte Ziele"), int(Game.goals.get("ms", 0)), 25],
		[tr("Jahre ohne Hungertod"), int(st.get("good_years", 0)), 60]]
	if int(st.get("quests", 0)) > 0:  # Auftraege (Teil D) zaehlen stats.quests
		rows.append([tr("Erledigte Aufträge"), int(st.get("quests", 0)), 40])
	if int(st.get("future_city", 0)) > 0:
		rows.append([tr("Zukunftsstadt gebaut"), 1, 500])
	return rows.map(func(r): return [r[0], r[1], int(r[1]) * int(r[2])])


func score() -> int:
	var n := 0
	for r in score_parts():
		n += int(r[2])
	return n


func record_section() -> String:
	return "records_" + Game.build_tag if Game.is_test_build else "records"


## Gespeicherte Rekorde: Schluessel -> Wert.
func records() -> Dictionary:
	var out := {}
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK and cf.has_section(record_section()):
		for k in cf.get_section_keys(record_section()):
			out[k] = int(cf.get_value(record_section(), k, 0))
	return out


## Werte dieses Spiels fuer die Rekorde (age_i = Spieltag, an dem das Zeitalter i erreicht wurde).
func record_values() -> Dictionary:
	var v := {"score": score(), "max_pop": int(Game.stats.get("max_pop", 0)),
		"best_streak": int(floor(float(Game.stats.get("best_streak", 0.0)))), "days": Game.day()}
	for i in days.size():
		if float(days[i]) >= 0.0:
			v["age_%d" % (i + 1)] = int(floor(float(days[i]))) + 1
	return v


## Traegt neue Rekorde ein (age_i: je kleiner, desto besser) und liefert die neu gebrochenen.
func update_records() -> Array:
	if Game.world == null:
		return []
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	var sec := record_section()
	var vals := record_values()
	var new := []
	for k in vals:
		var v := int(vals[k])
		var low: bool = str(k).begins_with("age_")
		if cf.has_section_key(sec, k):
			var old := int(cf.get_value(sec, k, 0))
			if (low and v >= old) or (not low and v <= old):
				continue
		elif v <= 0:
			continue
		cf.set_value(sec, k, v)
		new.append(k)
	if not new.is_empty():
		cf.save(SETTINGS)
	for k in new:
		if not k in beaten:
			beaten.append(k)
	return new


func record_name(k: String) -> String:
	match k:
		"score":
			return tr("Punkte")
		"max_pop":
			return tr("Höchste Bevölkerung")
		"best_streak":
			return tr("Tage ohne Hungertod")
		"days":
			return tr("Längstes Spiel")
	if k.begins_with("age_"):
		return tr("Zeitalter %s erreicht") % Data.age_name(int(k.trim_prefix("age_")))
	return k


## "Tag 23" fuer Zeitalter, "40 Tage" fuer Spieldauer, sonst die Zahl.
func record_value_text(k: String, v: int) -> String:
	if k.begins_with("age_"):
		return tr("Tag %d") % v
	if k in ["days", "best_streak"]:
		return tr("%d Tage") % v
	return str(v)


## Spielende (Game.game_over): Wertung und Rekorde ein letztes Mal.
func final_result() -> Dictionary:
	if last_result.is_empty():
		_daily_stats()
		update_records()
		last_result = {"score": score(), "beaten": beaten.duplicate()}
	return last_result


## Zeilen fuer das Spielende: "Wertung: 1234 Punkte" und "Neuer Rekord: ...".
func result_text() -> String:
	var r := final_result()
	var t := tr("Wertung: %d Punkte") % int(r.score)
	if not Array(r.beaten).is_empty():
		t += "\n" + tr("Neuer Rekord: %s") % ", ".join(Array(r.beaten).map(func(k): return record_name(str(k))))
	return t


# ---------------------------------------------------------------- Selbsttest
## --examtest=N: Daten und Gating pruefen, N Pruefungen sofort bestehen, dann die Bedingungen der
## Pruefung N bis auf eine erfuellen (bleibt offen) und die letzte nach 40 s nachreichen (besteht von selbst).
## --research=1: der Forschungs-Bot besteht eine Pruefung, wenn sonst nichts mehr geht (nicht mit --strictexam).
## --examscroll=1: Forschungsfenster bis zum Pruefungskasten rollen (Bildschirmfoto).
## --examhint=1: Erklaerung der Zielkarte aufklappen; --gameovershot=1: kurz vor dem Bildschirmfoto das
## Spielende-Fenster mit Wertung zeigen (nur Bild, das Spiel laeuft weiter); --scorescroll=1: Wertung
## bis zu den Rekorden rollen.
func autotest_setup(args: Dictionary, main) -> void:
	_strict = args.has("strictexam")
	if args.has("examtest"):
		await _exam_test(int(args.examtest), main)
	if args.has("research") and not _strict:
		_bot_loop(main)
	if args.has("examscroll"):
		_scroll_exam(main)
	if args.has("examhint"):
		_show_hint(main)
	if args.has("gameovershot"):
		_game_over_shot(main, float(args.get("autotest", "20")) - 2.0)
	if args.has("scorescroll"):
		_scroll_score(main)


## --panel=score --scorescroll=1: Fenster Wertung bis zu den Rekorden rollen (Bildschirmfoto).
func _scroll_score(main) -> void:
	while is_instance_valid(main) and not main.hud._score_panel.visible:
		await get_tree().process_frame
	for i in 3:
		await get_tree().process_frame
	var stack: Array = [main.hud._score_panel]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is ScrollContainer:
			n.scroll_vertical = 10000
		stack.append_array(n.get_children())


func _show_hint(main) -> void:
	for i in 300:
		await get_tree().process_frame
		var gc = main.hud.goal_card
		if gc.visible and gc._hint.text != "" and not gc._hint.visible:
			gc._hint.visible = true
			gc._relayout()
			return


func _game_over_shot(main, secs: float) -> void:
	await get_tree().create_timer(maxf(1.0, secs), true, false, true).timeout
	if is_instance_valid(main):
		print("Spielende (Bild): ", result_text().replace("\n", " | "))
		main.hud._show_game_over()


func autotest_report() -> String:
	var st := status(passed)
	var parts := st.map(func(x): return "%s %d/%d %s" % [x[0].get("type", ""), x[1], x[2], "ok" if x[3] else "fehlt"])
	var gc := []
	if not _test.is_empty() and is_instance_valid(_test.main):
		var g: Dictionary = _test.main.hud.goal_card.current()
		gc = [g.get("id", ""), _test.main.hud.goal_card.progress(g)]
	print("   Pruefungen: bestanden %d (Zeitalter %s), Pruefung %d: %s | blockiert=%s nur_pruefung=%s | Fest bis %.2f | Wertung %d (%s) | Rekorde %s neu %s | Zielkarte %s" % [passed,
		Data.age_name(current_age()), passed, ", ".join(parts) if not parts.is_empty() else "-", blocking(), only_exam_left(), fest_until,
		score(), score_parts().map(func(r): return "%s=%d" % [r[0], r[2]]), records(), beaten, gc])
	if not _test.is_empty() and fest_active() and Game.world:
		for s in Game.world.settlers.slice(0, 2):
			print("   Fest-Laune %s: %d %s" % [s.display_name, int(s.mind.mood), s.mind.reasons.filter(func(r): return float(r[1]) >= 15.0).map(func(r): return "%s %+d" % [r[0], int(r[1])])])
	return ""


func _exam_test(n: int, main) -> void:
	var w = main.world
	_test = {"main": main}
	Data.balance["base_storage"] = 4000  # Testlauf: genug Stauraum fuer die Testvorraete
	Game.goals["tut"] = Data.goals.get("tutorial", []).size()  # ohne Einfuehrung: die Zielkarte zeigt die Pruefung
	print("Pruefungstest: %d Zeitalter, Pruefungen in techs.json:" % Data.ages.size())
	for i in Data.ages.size():
		var d := exam_def(i)
		print("   Pruefung %d (%s -> %s): %s | Belohnung %s" % [i, Data.age_name(i), Data.age_name(i + 1),
			status(i).map(func(x): return "%s %d/%d" % [GoalChecks.label(x[0]), x[1], x[2]]) if not d.is_empty() else "-", reward_text(i) if not d.is_empty() else "-"])
	for c in [{"type": "houses", "what": "gibtsnicht", "n": 1}, {"type": "building", "what": "gibtsnicht", "n": 1}, {"type": "stock", "what": "gibtsnicht", "n": 5}]:
		print("   Unbekannte ID: %s -> '%s' %s" % [c, GoalChecks.label(c), GoalChecks.progress(c)])
	print("   Haus-Pruefung: huette zaehlt als holzhaus=%s, steinhaus zaehlt als holzhaus=%s, holzhaus zaehlt als steinhaus=%s" % [
		GoalChecks.house_counts("huette", "holzhaus"), GoalChecks.house_counts("steinhaus", "holzhaus"), GoalChecks.house_counts("holzhaus", "steinhaus")])
	# Gating: alle Steinzeit-Forschungen erledigt, Antike wartet auf die Pruefung
	_mark_age_done(0, 99)
	var stock_before := {"holz": Game.amount("holz", w), "stein": Game.amount("stein", w)}
	w.stock["holz"] = 200
	w.stock["stein"] = 200
	print("   Gating vor Pruefung 0: heilkunde=%s start='%s' aktuell=%s, Zeitalter %s, nur_pruefung=%s" % [Game.tech_state("heilkunde"),
		Game.start_research("heilkunde"), Game.research.current, Data.age_name(Game.current_age()), only_exam_left()])
	for i in n:
		var pop0 := Game.population()
		var tafeln0 := Game.amount_all("tontafel")
		pass_exam()
		print("   Pruefung %d sofort bestanden: Zeitalter %s, Siedler %d -> %d, Tontafeln %d -> %d, Fest bis %.2f, Tage %s" % [i, Data.age_name(current_age()),
			pop0, Game.population(), tafeln0, Game.amount_all("tontafel"), fest_until, days])
		if i == 0:
			print("   Gating nach Pruefung 0: heilkunde=%s" % Game.tech_state("heilkunde"))
		_mark_age_done(i + 1, 99)
	w.stock["holz"] = stock_before.holz
	w.stock["stein"] = stock_before.stein
	# Speichern und Laden der Pruefungen (JSON-Rundreise)
	var d := {}
	_on_save(d)
	var back = JSON.parse_string(JSON.stringify(d))
	var keep := [passed, days.duplicate(), fest_until]
	_on_load(back, 1)
	print("   Spielstand exams=%s -> nach dem Laden passed=%d days=%s fest=%.2f %s" % [d.exams, passed, days, fest_until,
		"OK" if passed == keep[0] and days == keep[1] and is_equal_approx(fest_until, keep[2]) else "FEHLER"])
	if exam_def(n).is_empty():
		return
	# Pruefung n: alles bis auf eine Bedingung (das erste Gebaeude, sonst die letzte) erfuellen
	var checks: Array = exam_def(n).get("checks", [])
	var hold := checks.size() - 1
	for k in checks.size():
		if str(checks[k].get("type", "")) in ["houses", "building"]:
			hold = k
			break
	for k in checks.size():
		if k != hold:
			_fulfil(checks[k], w, main)
	print("   Pruefung %d vorbereitet (eine Bedingung fehlt noch): %s" % [n, status(n).map(func(x): return "%s %d/%d" % [GoalChecks.label(x[0]), x[1], x[2]])])
	_late_fulfil(checks[hold], w, main, n)


## Pruefungstest: die ersten k Forschungen (Stufe, dann Punkte) des Zeitalters a als erforscht eintragen.
func _mark_age_done(a: int, k: int) -> void:
	var cnt := 0
	for t in Data.sorted_tech_ids():
		if Data.age_of_tier(int(Data.techs[t].tier)) == a and cnt < k:
			cnt += 1
			if not t in Game.research.done:
				Game.research.done.append(t)
	Game._recompute_effects()
	Game.research_changed.emit()


func _late_fulfil(c: Dictionary, w, main, n: int) -> void:
	await get_tree().create_timer(40.0, true, false, true).timeout
	print("Pruefungstest: nach 40 s noch offen=%s, jetzt fehlt nur noch: %s" % [passed == n, missing_text(false)])
	_fulfil(c, w, main)
	print("Pruefungstest: letzte Bedingung erfuellt (%s), die Pruefung muss jetzt von selbst bestehen" % GoalChecks.status_text(c))
	var t0 := Game.time_days
	while passed == n and is_instance_valid(main) and Game.time_days - t0 < 1.0:
		await get_tree().create_timer(0.5, true, false, true).timeout
	print("Pruefungstest: Pruefung %d %s nach %.2f Tagen, Zeitalter %s, Zielkarte jetzt %s" % [n, "bestanden" if passed > n else "NICHT bestanden",
		Game.time_days - t0, Data.age_name(current_age()), main.hud.goal_card.current().get("id", "")])
	await get_tree().create_timer(4.0, true, false, true).timeout
	for s in w.settlers.slice(0, 3):
		print("   Fest-Laune %s: Laune %d, Gruende %s" % [s.display_name, int(s.mind.mood), s.mind.reasons.map(func(r): return "%s %+d" % [r[0], int(r[1])])])


## Pruefungstest: eine Bedingung herstellen (Forschungen, Siedler, Gebaeude, Waren, Tage ohne Hungertod).
func _fulfil(c: Dictionary, w, main) -> void:
	var n := int(c.get("n", 1))
	var what := str(c.get("what", ""))
	match str(c.get("type", "")):
		"age_techs":
			_mark_age_done(int(c.get("age", 0)), n)
		"pop":
			while Game.population() + Sea.people_at_sea() < n:
				if w.spawn_newcomer("f" if Game.population() % 2 == 0 else "m", {"hunger": 90.0}) == null:
					break
			w.stock["beeren"] = maxi(Game.amount("beeren", w), 200)
			w.stock["fisch"] = maxi(Game.amount("fisch", w), 200)
		"houses", "building":
			for i in n:
				if Data.buildings.has(what):
					print("   platziert ", what, " ", main._place_on(w, what))
			Game.refresh_effects()
		"stock":
			if Data.resources.has(what):
				w.stock[what] = maxi(Game.amount(what, w), n)
		"variety":
			for id in ["beeren", "fisch", "weizen", "aepfel"].slice(0, n):
				w.stock[id] = maxi(Game.amount(id, w), 20)
		"food":
			w.stock["fisch"] = Game.amount("fisch", w) + n
		"no_starve_days":
			Game.stats["starve_day"] = Game.time_days - float(n) - 0.5
		_:
			print("   kann im Test nicht hergestellt werden: ", c)
	Game.stock_changed.emit()


## Forschungs-Bot: geht nichts mehr ausser der Pruefung (keine waehlbare Forschung bezahlbar, aber eine
## Forschung des naechsten Zeitalters waere es), gilt die Pruefung als bestanden (wie frueher der Sprung).
func _bot_loop(main) -> void:
	while is_instance_valid(main) and not Game.is_over:
		await get_tree().create_timer(1.0, true, false, true).timeout
		if Game.research.current != "" or exam_def(passed).is_empty():
			continue
		var ready := false
		var gated_ok := false
		for t in Data.techs:
			var st := Game.tech_state(t)
			var ok: bool = t in Game.research.paid or Game.can_afford(Data.techs[t].get("cost", {}))
			if st == "available" and ok:
				ready = true
			elif st == "exam" and ok:
				gated_ok = true
		if not ready and gated_ok:
			print("Pruefung (Forschungs-Bot, ohne --strictexam) uebersprungen: %s" % missing_text(false))
			pass_exam()


func _scroll_exam(main) -> void:
	while is_instance_valid(main) and not main.hud._research_panel.visible:
		await get_tree().process_frame
	for i in 3:
		await get_tree().process_frame
	for row in main.hud._research_list.get_children():
		if row.has_meta("exam_box"):
			main.hud._research_scroll.scroll_vertical = maxi(0, int(row.position.y) - 100)
