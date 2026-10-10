class_name TalentTest
extends RefCounted
## Selbsttest --talenttest=1: Talente geben mehr Arbeitstempo und Lerntempo und sind im
## Infofenster, in der Siedlerliste und bei der Berufswahl mit Stern zu sehen.
## Ausgaben nur mit print, je Pruefung "Talente OK" oder "Talente FEHLER".

static var fails := 0


static func _okprint(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("Talente ", "OK " if c else "FEHLER ", what)


static func run(main) -> void:
	fails = 0
	var w = main.world
	var hud = main.hud
	var c: Vector2i = w.settlers[0].cell
	var tal := {"bauen": 1.8, "holz": 1.0, "stein": 0.6, "nahrung": 1.3}
	var s = w.spawn_settler({"name": "T1", "sex": "f", "age": 25.0, "max_age": 70.0, "x": c.x, "y": c.y,
		"skills": {"bauen": 3, "holz": 3, "stein": 3, "nahrung": 3},
		"mind": {"traits": {"iq": 5.5, "konst": 5.5, "fleiss": 5.5, "gemuet": 5.5}, "talents": tal}})
	var m: SettlerMind = s.mind
	# Werte aus data/people.json
	var wb := float(Data.ppl("talent_work_bonus"))
	var lb := float(Data.ppl("talent_learn_bonus"))
	print("Talente: talent_show=%.2f talent_work_bonus=%.2f talent_learn_bonus=%.2f" % [
		float(Data.ppl("talent_show")), wb, lb])
	# Arbeitstempo: gleiche Stufe, verschiedene Begabung
	var work_b: float = s.skill_factor("bauen") / s.skill_factor("holz")
	var work_s: float = s.skill_factor("stein") / s.skill_factor("holz")
	var work_n: float = s.skill_factor("nahrung") / s.skill_factor("holz")
	print("Talente: Arbeitstempo Bauen 1.8 x%.2f (vorher x1.00), Nahrung 1.3 x%.2f, Stein 0.6 x%.2f" % [work_b, work_n, work_s])
	_okprint(absf(work_b - 1.4) < 0.001, "Arbeitstempo Talent 1.8 = +40 %")
	_okprint(absf(work_n - 1.15) < 0.001, "Arbeitstempo Talent 1.3 = +15 %")
	_okprint(absf(work_s - 1.0) < 0.001, "Schwaeche bremst die Arbeit nicht")
	var wf_b: float = s.work_factor("bauen", "build") / s.work_factor("holz", "build")
	_okprint(absf(wf_b - 1.4) < 0.001, "work_factor nimmt das Talent mit (x%.2f)" % wf_b)
	# Lernen
	var learn_b: float = m.learn_factor("bauen") / m.learn_factor("holz")
	var learn_s: float = m.learn_factor("stein") / m.learn_factor("holz")
	print("Talente: Lernen Bauen 1.8 x%.2f (vorher x1.80), Stein 0.6 x%.2f (vorher x0.60)" % [learn_b, learn_s])
	_okprint(absf(learn_b - 2.6) < 0.001, "Lernen Talent 1.8 = x2.6")
	_okprint(absf(learn_s - 0.6) < 0.001, "Lernen Schwaeche unveraendert")
	var xp0 := float(s.skill_xp.get("bauen", 0.0))
	s.gain_xp("bauen", 1.0, true)
	var xp1 := float(s.skill_xp.get("bauen", 0.0))
	var hx0 := float(s.skill_xp.get("holz", 0.0))
	s.gain_xp("holz", 1.0, true)
	var hx1 := float(s.skill_xp.get("holz", 0.0))
	_okprint(absf((xp1 - xp0) / (hx1 - hx0) - 2.6) < 0.01, "gain_xp: Bauen %.2f, Holz %.2f Erfahrung je Arbeit" % [xp1 - xp0, hx1 - hx0])
	# Talente und Texte
	_okprint(m.best_talents() == ["bauen", "nahrung"], "Talente erkannt: %s" % str(m.best_talents()))
	print("Talente: Zeile '%s' | kurz '%s'" % [TalentInfo.line(m, "bauen"), TalentInfo.short_list(m)])
	_okprint(TalentInfo.work_pct(m, "bauen") == 40 and TalentInfo.learn_pct(m, "bauen") == 160, "Prozent im Text 40 / 160")
	var jm: bool = TalentInfo.job_match(m, "baumeister") and TalentInfo.job_match(m, "sammler") and not TalentInfo.job_match(m, "holzfaeller")
	_okprint(jm, "Beruf passt: Baumeister, Sammler ja, Holzfaeller nein")
	# Infofenster: Sternzeilen und Sternknoepfe
	Game.select(s)
	hud._rebuild_info()
	var lines := []
	var star_jobs := []
	for n in _all(hud._info_box):
		if n is HBoxContainer and n.get_child_count() >= 2 and n.get_child(0) is TextureRect \
				and n.get_child(0).texture == TalentInfo.star() and n.get_child(1) is Label:
			lines.append(n.get_child(1).text)
		if n is Button and n.icon == TalentInfo.star():
			star_jobs.append(n.text)
	print("Talente: Infofenster ", lines, " Sternberufe ", star_jobs)
	_okprint(lines.size() == 2 and "40" in str(lines[0]), "Infofenster zeigt 2 Talentzeilen")
	var sj: bool = star_jobs.size() >= 2 and Data.jobs.baumeister.name in star_jobs and not Data.jobs.holzfaeller.name in star_jobs
	_okprint(sj, "Berufsknoepfe mit Stern: %d" % star_jobs.size())
	# Siedlerliste: Stern am Namen und im Berufsmenue
	print("Talente: Fenster ", main.get_viewport().get_visible_rect().size)
	hud._toggle(hud._settler_panel)
	hud._refresh_settler_list()
	var name_tip := false
	var col := ""
	var menu_star := []
	for n in _all(hud._settler_list):
		if n is Button and not n is OptionButton and n.text.begins_with("T1"):
			name_tip = "40" in n.tooltip_text
			var row: Node = n.get_parent()
			for x in row.get_children():
				if x is Label and x.text == TalentInfo.column_text(m):
					col = x.text
		if n is OptionButton and n.tooltip_text.contains(TalentInfo.short_list(m)):
			for i in n.item_count:
				if n.get_item_icon(i) == TalentInfo.star():
					menu_star.append(n.get_item_text(i))
	print("Talente: Liste schmal=", hud._settler_narrow, " Spalte Talent '", col, "' Name-Tooltip mit Bonus=", name_tip, " Menue mit Stern ", menu_star)
	var col_ok: bool = (col == "") if hud._settler_narrow else (col == TalentInfo.column_text(m))
	_okprint(col_ok and name_tip, "Siedlerliste: Spalte Talent (nur breit) und Tooltip am Namen")
	_okprint(Data.jobs.baumeister.name in menu_star and not Data.jobs.holzfaeller.name in menu_star, "Siedlerliste: Stern im Berufsmenue")
	hud._toggle(hud._settler_panel)
	# Ohne Talent: kein Stern
	var plain = w.spawn_settler({"name": "T2", "sex": "m", "age": 25.0, "max_age": 70.0, "x": c.x, "y": c.y, "skills": {},
		"mind": {"traits": {}, "talents": {"bauen": 1.2, "holz": 1.0}}})
	_okprint(plain.mind.best_talents().is_empty() and TalentInfo.short_list(plain.mind) == "", "Begabung 1.2 ist kein Talent (Bonus %d %%)" % TalentInfo.work_pct(plain.mind, "bauen"))
	# Speichern und Laden behalten die Begabung
	var data: Dictionary = s.serialize()
	_okprint(absf(float(data.mind.talents.bauen) - 1.8) < 0.001, "Begabung wird gespeichert")
	w.remove_settler(s)
	w.remove_settler(plain)
	print("Talente %s (%d Fehler)" % ["OK" if fails == 0 else "FEHLER", fails])


static func _all(root: Node) -> Array:
	var out := []
	for c in root.get_children():
		out.append(c)
		out.append_array(_all(c))
	return out
