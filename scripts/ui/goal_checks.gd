class_name GoalChecks
extends RefCounted
## Gemeinsame Pruefung von Bedingungen: Ziele (GoalCard), Pruefungen beim Zeitalterwechsel (Exams)
## und spaeter Auftraege. Eine Bedingung ist ein Dictionary {type, n, what, ...} wie in goals.json.
## progress(c) liefert [aktueller Wert, Zielwert], label(c) einen kurzen Anzeigetext ohne Zahlen
## (die Zahlen zeigt der Aufrufer als "wert/ziel"), icon(c) ein passendes Symbol.
## Nur Spielzustand (Game, Sea, Exams): selected_settler und action bleiben in GoalCard.
## Unbekannte Gebaeude oder Waren zaehlen 0 (kein Fehler), der Text zeigt dann die ID lesbar.
##
## Typen: building (what, n, any = auch Baustellen; zaehlt auch Ausbaustufen mit gleichem `base`),
## houses (what, n: dieses Haus oder ein besseres, ueber `upgrade` oder `level`), housing, pop,
## techs (all), tier, tech (what), age_techs (age, n: erforschte Forschungen dieses Zeitalters),
## research_active, speed, variety (all = alle Inseln zusammen), islands_found, islands_settled,
## kills, births, stock (what, alle Inseln), food (Nahrung auf allen Inseln), job (what, n),
## no_starve_days (Tage seit dem letzten Hungertod), exams (bestandene Pruefungen),
## exam (age: erfuellte Bedingungen der Pruefung).
## Fuer Auftraege (Quests): base (Startwert, der Wert zaehlt erst ab dann: Wert minus base),
## stock_at (what, island: Lager einer Insel), variety mit max (beste einzelne Insel),
## starved (Hungertote, stats.starved).


## [aktueller Wert, Zielwert]
static func progress(c: Dictionary) -> Array:
	if c.has("base"):  # Auftraege: zaehlt erst ab dem Annehmen (Wert minus Startwert)
		var raw := c.duplicate()
		raw.erase("base")
		var p := progress(raw)
		return [int(p[0]) - int(c.base), p[1]]
	var n := int(c.get("n", 1))
	var what := str(c.get("what", ""))
	match str(c.get("type", "")):
		"building":
			var cnt := 0
			for w in Sea.all_worlds():
				for b in w.buildings:
					if (b.type == what or b.def.get("base", "") == what) and (b.complete or c.get("any", false)):
						cnt += 1
			return [cnt, n]
		"houses":
			var cnt := 0
			for w in Sea.all_worlds():
				for b in w.buildings:
					if b.complete and house_counts(b.type, what):
						cnt += 1
			return [cnt, n]
		"housing":
			var cap := 0
			for w in Sea.all_worlds():
				cap += Game.housing_capacity(w)
			return [cap, n]
		"pop":
			return [Game.population() + Sea.people_at_sea(), n]
		"techs":
			if c.get("all", false):
				n = Data.techs.size()
			return [Game.research.done.size(), min(n, Data.techs.size())]
		"tier":
			var best := 0
			for t in Game.research.done:
				best = max(best, int(Data.techs[t].tier))
			return [best, n]
		"tech":
			return [1 if what != "" and Data.techs.has(what) and what in Game.research.done else 0, 1]
		"age_techs":
			var age := int(c.get("age", 0))
			var cnt := 0
			for t in Game.research.done:
				if Data.techs.has(t) and Data.age_of_tier(int(Data.techs[t].tier)) == age:
					cnt += 1
			return [cnt, n]
		"research_active":
			return [1 if Game.research.current != "" or not Game.research.done.is_empty() else 0, 1]
		"speed":
			return [1 if Game.speed >= n else 0, 1]
		"variety":
			if c.get("max", false):  # beste einzelne Insel
				var best := 0
				for w in Sea.all_worlds():
					best = maxi(best, Game.food_variety(w))
				return [best, n]
			if c.get("all", false):
				var kinds := 0
				for id in Data.food_ids():
					if Game.amount_all(id) > 0:
						kinds += 1
				return [kinds, n]
			return [Game.food_variety(), n]
		"islands_found":
			return [Sea.islands.size() - 1, n]
		"islands_settled":
			return [Sea.settled_islands().size(), n]
		"kills":
			return [int(Game.stats.get("kills", 0)), n]
		"births":
			return [int(Game.stats.get("births", 0)), n]
		"stock":
			return [Game.amount_all(what) if Data.resources.has(what) else 0, n]
		"stock_at":
			var sw = Sea.worlds.get(int(c.get("island", -1)))
			return [Game.amount(what, sw) if sw != null and is_instance_valid(sw) and Data.resources.has(what) else 0, n]
		"starved":
			return [int(Game.stats.get("starved", 0)), n]
		"food":
			var f := 0
			for w in Sea.all_worlds():
				f += Game.total_food(w)
			return [f, n]
		"job":
			var cnt := 0
			for w in Sea.all_worlds():
				for s in w.settlers:
					if s.job == what:
						cnt += 1
			return [cnt, n]
		"no_starve_days":
			return [no_starve_days(), n]
		"exams":
			return [int(Exams.passed), n]
		"exam":
			var st: Array = Exams.status(int(c.get("age", Exams.passed)))
			return [st.filter(func(x): return x[3]).size(), st.size()]
	return [0, 1]


static func is_met(c: Dictionary) -> bool:
	var p := progress(c)
	return int(p[0]) >= int(p[1])


## Ganze Tage seit dem letzten Hungertod (oder seit die neuen Regeln gelten bzw. seit Spielbeginn).
static func no_starve_days() -> int:
	return maxi(0, int(floor(Game.time_days - float(Game.stats.get("starve_day", Game.rules_day)))))


## Gebaeudetyp `type` zaehlt als Haus `what` oder besser: gleich, eine Ausbaustufe davon (`upgrade`,
## wiederholt) oder ein Wohnhaus mit mindestens derselben Stufe (`level`, falls vorhanden).
static func house_counts(type: String, what: String) -> bool:
	if type == what:
		return true
	if not Data.buildings.has(what) or not Data.buildings.has(type):
		return false
	var x := what
	for i in 10:
		x = str(Data.buildings.get(x, {}).get("upgrade", ""))
		if x == "":
			break
		if x == type:
			return true
	var d: Dictionary = Data.buildings[type]
	var wd: Dictionary = Data.buildings[what]
	if d.has("level") and wd.has("level") and int(d.get("housing", 0)) > 0:
		return int(d.level) >= int(wd.level)
	return false


## Name eines Gebaeudes; unbekannte IDs lesbar ("mietshaus" -> "Mietshaus").
static func building_name(id: String) -> String:
	if Data.buildings.has(id):
		return str(Data.buildings[id].get("name", id))
	return id.capitalize()


## Kurzer Anzeigetext ohne Zahlen, z. B. "Holzhaus oder besser", "Brot im Lager".
static func label(c: Dictionary) -> String:
	var what := str(c.get("what", ""))
	match str(c.get("type", "")):
		"building":
			return building_name(what)
		"houses":
			return Loc.t("%s oder besser") % building_name(what)
		"housing":
			return Loc.t("Wohnplätze")
		"pop":
			return Loc.t("Siedler")
		"techs":
			return Loc.t("Forschungen")
		"tier":
			return Loc.t("Forschungsstufe")
		"tech":
			return Loc.t("Forschung: %s") % (str(Data.techs[what].name) if Data.techs.has(what) else what.capitalize())
		"age_techs":
			return Loc.t("Forschungen: %s") % Data.age_name(int(c.get("age", 0)))
		"research_active":
			return Loc.t("Eine Forschung läuft")
		"speed":
			return Loc.t("Schnelles Tempo")
		"variety":
			return Loc.t("Sorten Nahrung im Lager")
		"islands_found":
			return Loc.t("Entdeckte Inseln")
		"islands_settled":
			return Loc.t("Besiedelte Inseln")
		"kills":
			return Loc.t("Erlegte Tiere")
		"births":
			return Loc.t("Geburten")
		"stock":
			return Loc.t("%s im Lager") % (Data.resource_name(what) if Data.resources.has(what) else what.capitalize())
		"stock_at":
			var m: Dictionary = Sea.meta(int(c.get("island", -1)))
			return Loc.t("%s im Lager auf %s") % [Data.resource_name(what) if Data.resources.has(what) else what.capitalize(),
				str(m.get("name", "?"))]
		"starved":
			return Loc.t("Hungertote")
		"food":
			return Loc.t("Nahrung im Lager")
		"job":
			return Loc.t("Siedler als %s") % str(Data.jobs.get(what, {}).get("name", what.capitalize()))
		"no_starve_days":
			return Loc.t("Tage ohne Hungertod")
		"exams":
			return Loc.t("Bestandene Prüfungen")
		"exam":
			return Loc.t("Prüfung für das Zeitalter %s") % Data.age_name(int(c.get("age", Exams.passed)) + 1)
	return str(c.get("type", ""))


## "Holzhaus oder besser 0/1"
static func status_text(c: Dictionary) -> String:
	var p := progress(c)
	return "%s %d/%d" % [label(c), int(p[0]), int(p[1])]


## Symbol einer Bedingung.
static func icon(c: Dictionary) -> Texture2D:
	var what := str(c.get("what", ""))
	match str(c.get("type", "")):
		"building", "houses":
			if Data.buildings.has(what):
				return Data.building_tex(what)
			return Data.icon("haus")
		"housing":
			return Data.icon("haus")
		"pop", "births", "job":
			return Data.icon("person")
		"techs", "tier", "tech", "age_techs", "research_active":
			return Data.icon("wissen")
		"variety", "food", "no_starve_days":
			return Data.icon("nahrung")
		"islands_found", "islands_settled":
			return Data.icon("kompass")
		"kills":
			return Data.icon("schild")
		"stock", "stock_at":
			if Data.resources.has(what):
				return Data.res_icon(what)
			return Data.icon("kiste")
		"starved":
			return Data.icon("nahrung")
		"exams", "exam":
			return Data.icon("zeitalter")
	return Data.icon("ziel")
