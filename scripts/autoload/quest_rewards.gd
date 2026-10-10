class_name QuestRewards
extends RefCounted
## Auftragsbelohnungen passend zur Lage (josh: „Die Mengen der Belohnungen von Quests sollten an die
## Situation in Form von Menge und Art angepasst werden“). Kein Autoload; Quests ruft die Funktionen auf.
##
## Art: Waren, die der Kolonie gerade fehlen oder bald fehlen (Bedarf, `needs`):
##   hunger  Essen reicht für weniger als 2 Tage: die haltbarste Speise des Zeitalters
##   winter  Sommer und Herbst: Essen bis Winterende (haltbar zuerst: Räucherfisch, Brot, Konserven)
##   heizen  Sommer bis Winter: Heizholz bis Winterende (nach Wintervorhersage)
##   schrift laufende Forschung: fehlende Schreibwaren (Tontafeln, Papier)
##   haeuser Bedürfnisse der Hausstufen, die es gibt (Bretter, Werkzeug, Brot, Glas, Papier, Gewürze ...)
##   pruefung nächste Prüfung: Lagerwaren und Baukosten der verlangten Häuser und Gebäude
##   forschung Kosten der nächsten wählbaren Forschungen
##   bauen   Baustoffe (Holz, Bretter, Stein, Ziegel) für freigeschaltete Gebäude
## Nie Waren, von denen genug da ist (Lager zur Hälfte damit voll) oder die die Kolonie noch nicht
## brauchen kann (`usable`). Gibt es keinen Bedarf: die alte Liste goods_by_age, aber nur Brauchbares;
## ist von allem genug da, gibt es Forschungspunkte statt Waren.
## Menge: Budget goods_budget x Gewicht x (1 + Zeitalter) Gold x Siedler-Faktor clamp(P / pop_ref,
## pop_min, pop_max) / Preis; bei bekanntem Fehlbedarf 1,5-mal so viel wie fehlt (short_cover), mindestens
## short_min des Budgets; höchstens free_share des freien Lagerplatzes aller Inseln für die Ware (und wie bisher
## goods_space der Lagerkapazität), mindestens 3. Werte in goals.json quests.adapt.

## Gründe (Spielstand reward.why), Text in der Anzeige: why_text
const WHY := ["hunger", "winter", "heizen", "schrift", "haeuser", "pruefung", "forschung", "bauen"]

static var _used: Array = []  # Waren, die eine Angebotsrunde schon vergeben hat


static func cfg() -> Dictionary:
	var c = Quests.cfg().get("adapt", {})
	return c if c is Dictionary else {}


static func _c(key: String, default):
	return cfg().get(key, default)


## Neue Angebotsrunde: jede Ware nur einmal.
static func begin() -> void:
	_used = []


static func why_text(why: String) -> String:
	match why:
		"hunger":
			return Loc.t("Essen ist knapp")
		"winter":
			return Loc.t("Vorrat für den Winter")
		"heizen":
			return Loc.t("Heizholz für den Winter")
		"schrift":
			return Loc.t("für die laufende Forschung")
		"haeuser":
			return Loc.t("für die Bewohner")
		"pruefung":
			return Loc.t("für die nächste Prüfung")
		"forschung":
			return Loc.t("für eine Forschung")
		"bauen":
			return Loc.t("zum Bauen")
	return ""


static func _price(id: String) -> float:
	return float(Data.resources.get(id, {}).get("price", 0.0))


static func _rewardable(id: String) -> bool:
	return Data.resources.has(id) and _price(id) > 0.0 and Data.good_size(id) > 0 and Data.resources[id].get("category", "") != "ship"


## Waren, die es im erreichten Zeitalter gibt (goods_by_age bis jetzt, dazu Nahrung und Bedürfnisse).
static func _age_goods(a: int) -> Dictionary:
	var out := {}
	var ages: Array = Quests.cfg().get("goods_by_age", [])
	for i in mini(a + 1, ages.size()):
		for id in ages[i]:
			out[str(id)] = true
	return out


## Brauchbar: Nahrung, oder Baukosten/Rohstoff eines freigeschalteten Gebäudes, Kosten einer
## Forschung, die bald dran ist, Bedürfnis einer Hausstufe, die es gibt, oder Schreibware.
static func usable(id: String) -> bool:
	if not _rewardable(id):
		return false
	if Data.resources[id].get("category", "") == "food":
		return true
	for type in Data.buildings:
		var d: Dictionary = Data.buildings[type]
		if not Game.is_unlocked(type):
			continue
		if d.get("buildable", true) and d.get("cost", {}).has(id):
			return true
		if d.get("production", {}).get("inputs", {}).has(id):
			return true
	for t in Data.techs:
		var st := Game.tech_state(t)
		if (st == "available" or st == "exam" or st == "locked") and not t in Game.research.paid and Data.techs[t].get("cost", {}).has(id):
			if st != "locked" or _reqs_near(t):
				return true
	var lv := _house_levels()
	for k in lv:
		for nd in HouseNeeds.level_needs(int(k)):
			if str(nd.get("good", "")) == id or id in nd.get("goods", []):
				return true
	var cur := str(Game.research.current)
	if cur != "" and Writing.goods_for(cur).has(id):
		return true
	return false


## Forschung, deren Voraussetzungen höchstens eine Forschung entfernt sind.
static func _reqs_near(t: String) -> bool:
	for r in Data.techs[t].get("requires", []):
		if not r in Game.research.done and Game.tech_state(r) != "available" and Game.tech_state(r) != "current":
			return false
	return true


## Hausstufen, die es (fertig) gibt: {Stufe: Bewohner in Häusern ab dieser Stufe}.
static func _house_levels() -> Dictionary:
	var out := {}
	for w in Sea.all_worlds():
		var lvl := {}
		for b in w.buildings:
			if b.complete and b.house_level() > 0:
				lvl[b.id] = b.house_level()
		for s in w.settlers:
			var hl := int(lvl.get(s.home_id, 0))
			for k in range(2, hl + 1):
				out[k] = int(out.get(k, 0)) + 1
	return out


## Ist von der Ware genug da? Ein Viertel des Lagers aller Inseln (plenty_share) ist damit voll, und es
## sind mindestens plenty_base + plenty_per_settler je Siedler (40 + 4 je Siedler).
static func plenty(id: String) -> bool:
	var units := 0
	for w in Sea.all_worlds():
		units += Game.storage_volume(w) / maxi(1, Data.good_size(id))
	var p := Game.population() + Sea.people_at_sea()
	return Game.amount_all(id) >= maxf(float(_c("plenty_share", 0.25)) * units, float(_c("plenty_base", 40)) + float(_c("plenty_per_settler", 4)) * p)


## Freier Platz für die Ware auf allen Inseln (Einheiten).
static func free_units(id: String) -> int:
	var n := 0
	for w in Sea.all_worlds():
		n += Game.space_for(id, w)
	return n


static func _food_days_all() -> float:
	var p := maxi(1, Game.population())
	var sat := 0.0
	for id in Data.food_ids():
		sat += Game.amount_all(id) * Data.food_satiety(id)
	return sat / (p * maxf(1.0, float(Data.bal("hunger_per_day", 75.0)) * Game.eff("hunger")))


## Speise für Vorräte: haltbar (verdirbt nicht) und sättigend, die es im Zeitalter gibt.
static func durable_food(a: int) -> String:
	var list: Array = _c("winter_food", [["raeucherfisch", 0], ["brot", 1], ["konserven", 4], ["kokos", 0], ["fisch", 0]])
	var perish: Array = Seasons.cfg.get("perishable", [])
	var fresh := ""
	for e in list:
		var id := str(e[0])
		if int(e[1]) > a or not _rewardable(id) or plenty(id):
			continue
		if not id in perish:
			return id
		if fresh == "":
			fresh = id
	return fresh


static func _days_to_winter() -> float:
	var start := float(Seasons.year() - 1) * Seasons.year_days() + 3.0 * Seasons.season_days()
	return start - Game.time_days


## Bedarfsliste: [{id, why, short (Einheiten, -1 unbekannt), weight}], das Dringendste zuerst.
static func needs(ctx: Dictionary) -> Array:
	var a := int(ctx.A)
	var p := maxi(1, int(ctx.P))
	var out := []
	var hunger := float(Data.bal("hunger_per_day", 75.0)) * Game.eff("hunger")
	var fd := _food_days_all()
	var season := Seasons.season()
	var food := durable_food(a)
	# Essen
	if food != "" and fd < float(_c("hunger_days", 2.0)):
		out.append({"id": food, "why": "hunger", "short": _units_for_days(food, 3.0 - fd, p, hunger), "weight": 6.0})
	elif food != "" and (season == 1 or season == 2):
		var to_end := maxf(0.0, _days_to_winter()) + Seasons.season_days()
		var target := minf(to_end, Seasons.season_days() * float(_c("winter_food_days", 1.3)))
		if fd < target:
			out.append({"id": food, "why": "winter", "short": _units_for_days(food, target - fd, p, hunger * 1.15), "weight": 5.0 if season == 2 else 3.5})
	# Heizholz
	if season >= 1 and _rewardable("holz"):
		var need := float(Seasons.winter_wood_need()) * Quests.winter_mult()
		if season == 3:
			need *= clampf(1.0 - Seasons.season_progress(), 0.0, 1.0)
		elif season == 2:
			need += p * Seasons.heat_per_settler(2) * Seasons.season_days() * clampf(1.0 - Seasons.season_progress(), 0.0, 1.0)
		var short := ceili(need) - Game.amount_all("holz")
		if short > 0 and not plenty("holz"):
			out.append({"id": "holz", "why": "heizen", "short": short, "weight": 5.0 if season >= 2 else 3.0})
	# Schreibwaren der laufenden Forschung
	var cur := str(Game.research.current)
	if cur != "":
		var left := Writing.left_for(cur)
		for id in left:
			var short := int(left[id]) - Game.amount_all(id)
			if short > 0 and _rewardable(id):
				out.append({"id": id, "why": "schrift", "short": short, "weight": 3.0})
	# Bedürfnisse der Hausstufen
	var lv := _house_levels()
	for k in lv:
		var who := int(lv[k])
		for nd in HouseNeeds.level_needs(int(k)):
			match str(nd.get("kind", "")):
				"good":
					var id := str(nd.get("good", ""))
					var short := ceili(float(nd.get("rate", 0.0)) * who * float(_c("need_days", 4.0))) - Game.amount_all(id)
					if short > 0 and _rewardable(id):
						out.append({"id": id, "why": "haeuser", "short": short, "weight": 3.0})
				"stock":
					var have := 0
					var pick := ""
					for g in nd.get("goods", []):
						have += Game.amount_all(str(g))
						if pick == "" and _rewardable(str(g)) and _age_goods(a).has(str(g)):
							pick = str(g)
					var short := ceili(float(nd.get("per", 0.5)) * who * 2.0) - have
					if short > 0 and pick != "":
						out.append({"id": pick, "why": "haeuser", "short": short, "weight": 3.0})
	# Nächste Prüfung
	for x in Exams.status(Exams.passed):
		if bool(x[3]):
			continue
		var c: Dictionary = x[0]
		match str(c.get("type", "")):
			"stock":
				if _rewardable(str(c.what)):
					out.append({"id": str(c.what), "why": "pruefung", "short": int(x[2]) - int(x[1]), "weight": 3.0})
			"houses", "building":
				var type := str(c.get("what", ""))
				var req := str(Data.buildings.get(type, {}).get("requires", ""))
				if Data.buildings.has(type) and (Game.is_unlocked(type) or Game.tech_state(req) in ["available", "current"]):
					var cost: Dictionary = Data.buildings[type].get("cost", {})
					for id in cost:
						var short := int(cost[id]) - Game.amount_all(str(id))
						if short > 0 and _rewardable(str(id)):
							out.append({"id": str(id), "why": "pruefung", "short": short, "weight": 3.0})
	# Kosten der nächsten Forschungen (die drei günstigsten wählbaren)
	var techs := []
	for t in Data.techs:
		if Game.tech_state(t) == "available" and not t in Game.research.paid:
			techs.append(t)
	techs.sort_custom(func(x, y): return Game.tech_points(x) < Game.tech_points(y))
	for t in techs.slice(0, 3):
		var cost: Dictionary = Data.techs[t].get("cost", {})
		for id in cost:
			var short := int(cost[id]) - Game.amount_all(str(id))
			if short > 0 and _rewardable(str(id)):
				out.append({"id": str(id), "why": "forschung", "short": short, "weight": 2.0})
	# Baustoffe
	var target := int(_c("build_base", 30)) + int(_c("build_per_settler", 3)) * p
	for id in _c("build_goods", ["holz", "bretter", "stein", "ziegel"]):
		if _rewardable(str(id)) and usable(str(id)):
			var short := target - Game.amount_all(str(id))
			if short > 0:
				out.append({"id": str(id), "why": "bauen", "short": short, "weight": 1.0})
	# Gleiche Ware nur einmal (der wichtigste Grund), nichts, wovon genug da ist
	var seen := {}
	var list := []
	out.sort_custom(func(x, y): return float(x.weight) > float(y.weight))
	for e in out:
		if seen.has(e.id) or plenty(str(e.id)):
			continue
		seen[e.id] = true
		list.append(e)
	return list


static func _units_for_days(food: String, days: float, p: int, hunger: float) -> int:
	return ceili(maxf(0.0, days) * p * hunger / maxf(1.0, Data.food_satiety(food)))


## Budget in Einheiten: goods_budget x w x (1 + A) Gold x Siedler-Faktor / Preis.
static func budget_units(id: String, w: int, ctx: Dictionary) -> float:
	var pf := clampf(float(ctx.P) / float(_c("pop_ref", 8.0)), float(_c("pop_min", 0.5)), float(_c("pop_max", 2.0)))
	return Quests._f("goods_budget", 25.0) * w * (1 + int(ctx.A)) * pf / maxf(0.01, _price(id))


## Menge für Ware id: Fehlbedarf x short_cover (mindestens short_min des Budgets), höchstens Budget und
## Lagerplatz.
static func amount(id: String, w: int, ctx: Dictionary, short: int, room: bool = true) -> int:
	var b := budget_units(id, w, ctx)
	var n := b if short < 0 else clampf(float(short) * float(_c("short_cover", 1.5)), b * float(_c("short_min", 0.3)), b)
	var units := 0
	for ww in Sea.all_worlds():
		units += Game.storage_volume(ww) / maxi(1, Data.good_size(id))
	n = minf(n, Quests._f("goods_space", 0.4) * units)
	if room:  # sonst wartet, was keinen Platz hat (Game.grant_reward)
		n = minf(n, float(_c("free_share", 0.6)) * free_units(id))
	var k := int(n)
	if k > 20:
		k -= k % 5
	return k


## Warenbelohnung für Gewicht w: die dringendste fehlende Ware (Zufall unter den fast so dringenden),
## sonst Brauchbares aus goods_by_age. {kind: goods, what, n, why}; {} wenn von allem genug da ist.
static func goods(w: int, ctx: Dictionary, avoid: String = "") -> Dictionary:
	var skip: Array = _used + [avoid]  # schon vergeben, und nie die Ware, die der Auftrag selbst verlangt
	var cands := []
	var list := needs(ctx).filter(func(e): return not str(e.id) in skip)
	for e in list:
		var n := amount(str(e.id), w, ctx, int(e.short))
		if n < 3:
			continue
		var value := minf(1.5, maxf(0.5, float(e.short) * _price(str(e.id)) / maxf(1.0, Quests._f("goods_budget", 25.0) * w)))
		cands.append({"id": e.id, "why": e.why, "n": n, "score": float(e.weight) * value})
	if not cands.is_empty():
		var best := 0.0
		for c in cands:
			best = maxf(best, float(c.score))
		var top := cands.filter(func(c): return float(c.score) >= best * float(_c("pick_share", 0.6)))
		var c: Dictionary = Quests._pick(top)
		_used.append(str(c.id))
		return {"kind": "goods", "what": str(c.id), "n": int(c.n), "why": str(c.why)}
	if not list.is_empty():  # Lager überall voll: das Dringendste trotzdem, es wartet auf Platz
		var e: Dictionary = list[0]
		var n := maxi(3, amount(str(e.id), w, ctx, int(e.short), false))
		_used.append(str(e.id))
		return {"kind": "goods", "what": str(e.id), "n": n, "why": str(e.why)}
	# Kein Bedarf: Waren des Zeitalters, aber nur Brauchbares, nicht im Überfluss
	var pool := []
	for id in _age_goods(int(ctx.A)):
		if usable(str(id)) and not plenty(str(id)) and not str(id) in skip and amount(str(id), w, ctx, -1) >= 3:
			pool.append(str(id))
	pool.sort()
	var room := true
	if pool.is_empty():  # kein Platz: Brauchbares, das auf Platz warten darf
		room = false
		for id in _age_goods(int(ctx.A)):
			if usable(str(id)) and not plenty(str(id)) and not str(id) in skip:
				pool.append(str(id))
		pool.sort()
	if pool.is_empty():
		return {}  # von allem genug da (oder schon vergeben): Quests gibt dann Forschungspunkte
	var id := str(Quests._pick(pool))
	_used.append(id)
	return {"kind": "goods", "what": id, "n": maxi(3, amount(id, w, ctx, -1, room))}


## Einwanderer nur, wenn sie ein Dach und genug Essen finden: freie Wohnplätze >= n, Essen für 2 Tage.
static func settlers_ok(n: int) -> bool:
	var free := 0
	for w in Sea.all_worlds():
		if not w.settlers.is_empty():
			free += maxi(0, Game.housing_capacity(w) - w.settlers.size())
	return free >= n and _food_days_all() >= float(_c("hunger_days", 2.0))
