extends Node
## Auftraege mit Wahl (Regeln ab Version 2, Teil D). Nach der Einfuehrung bietet das Auftragsbrett
## drei Auftraege an (verschiedene Vorlagen, verschiedene Belohnungen); der Spieler nimmt einen an.
## Nur einer laeuft zur Zeit, jeder hat eine Frist. Scheitern, Aufgeben und "Andere Auftraege" kosten
## nichts. Belohnungen: Waren (nach Goldwert `price`), Forschungspunkte (frei, ohne Schreibwaren),
## Einwanderer mit Begabung, dauerhafte Segen (Wirkungen mit Obergrenze, in Game._recompute_effects)
## oder ein Bauplan (Gebaeude ohne die Forschung, Game.is_unlocked).
## Daten: goals.json "quests" (Vorlagen, Zahlen). Bedingungen: GoalChecks (wie Ziele und Pruefungen).
## Spielstand: Schluessel "quests" = {offers, active, next, offers_until, reroll_at, plans, boons,
## rp_bank, rp_marks, seq, stats, last}. Texte werden nie gespeichert (text_of baut sie beim Anzeigen).

signal changed

## Angebote [Auftrag, ...] und der laufende Auftrag. Ein Auftrag ist
## {tpl, w, days, until, check: {type, what, n, base, island, max}, survive, reward: {kind, ...}}.
var offers: Array = []
var active: Dictionary = {}
var next := -1.0  # neue Angebote ab (time_days); -1 = Brett noch nicht offen (Einfuehrung)
var offers_until := 0.0  # Angebote gelten bis
var reroll_at := 0.0  # Knopf Andere Auftraege wieder moeglich ab
var plans: Array = []  # Bauplaene: Gebaeudetypen, die ohne Forschung baubar sind
var boons: Dictionary = {}  # Segen: Wirkung -> Zuschlag (mit Obergrenze)
var rp_bank := 0.0  # Forschungspunkte aus Belohnungen, die auf die naechste Forschung warten
var rp_marks: Array = []  # [[time_days, Forschungspunkte gesamt], ...] je Tagesbeginn (Forschung je Tag)
var seq := 0  # Zaehler fuer den Zufall der Angebote (gleicher Spielstand, gleiche Angebote)
var qstats: Dictionary = {}  # offered, accepted, done, failed, abandoned, rerolls
var last: Dictionary = {}  # letztes Ergebnis {tpl, ok, day, text}

var _next_check := 0.0
var _rng := RandomNumberGenerator.new()
var _obt: Dictionary = {}  # Zwischenspeicher obtainable() waehrend einer Angebotsrunde
var _force_reward := ""  # Selbsttest --questreward
var _fast := false  # Selbsttest --questfast: Frist 0,3 Tage
var _test := {}


func _ready() -> void:
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)
	Game.day_started.connect(func(_d): _mark_research())
	Game.research_changed.connect(_on_research_changed)


func cfg() -> Dictionary:
	var c = Data.goals.get("quests", {})
	return c if c is Dictionary else {}


func templates() -> Dictionary:
	var t = cfg().get("templates", {})
	return t if t is Dictionary else {}


func _f(key: String, default: float) -> float:
	return float(cfg().get(key, default))


func in_tutorial() -> bool:
	return int(Game.goals.get("tut", 0)) < Data.goals.get("tutorial", []).size()


## Etwas fuer die Zielkarte: ein laufender Auftrag oder Angebote.
func has_content() -> bool:
	return not active.is_empty() or not offers.is_empty()


func _process(_delta: float) -> void:
	if Game.world == null or Game.is_over or Game.speed <= 0:
		return
	if Game.time_days < _next_check:
		return
	_next_check = Game.time_days + _f("check_days", 0.05)
	tick()


# ---------------------------------------------------------------- Ablauf
func tick() -> void:
	var now := Game.time_days
	if next < 0.0:
		if not in_tutorial():  # Brett oeffnet nach der Einfuehrung
			next = now + _f("start_delay", 0.25)
		return
	if not active.is_empty():
		_check_active(now)
		return
	if not offers.is_empty():
		var before := offers.size()
		offers = offers.filter(func(q): return not is_met(q))  # schon erfuellt: faellt weg
		if now >= offers_until:
			offers.clear()
			next = now + _f("cooldown", 0.5)
			changed.emit()
			return
		if offers.size() != before:
			if offers.is_empty():
				next = now
			changed.emit()
		if not offers.is_empty():
			return
	if now >= next:
		if make_offers():
			Game.notify(tr("Neue Aufträge: Wähle einen von drei aus (oben links)."), "ziel", "ziel")
		else:
			next = now + 0.25


func _check_active(now: float) -> void:
	if active.get("survive", false):
		if int(progress(active)[0]) > 0:
			_fail()
		elif now >= float(active.until):
			_complete()
		return
	if is_met(active):
		_complete()
	elif now >= float(active.until):
		_fail()


## [Wert, Ziel] eines Auftrags (Zaehler ab dem Annehmen).
func progress(q: Dictionary) -> Array:
	return GoalChecks.progress(q.get("check", {}))


func is_met(q: Dictionary) -> bool:
	if q.get("survive", false):
		return false
	var p := progress(q)
	return int(p[0]) >= int(p[1])


## Angebot i annehmen. Liefert "" oder den Grund.
func accept(i: int) -> String:
	if not active.is_empty():
		return tr("Es läuft schon ein Auftrag.")
	if i < 0 or i >= offers.size():
		return tr("Dieses Angebot gibt es nicht mehr.")
	var q: Dictionary = offers[i].duplicate(true)
	var c: Dictionary = q.check
	if c.has("base"):  # Zaehler (Tiere, Geburten, Inseln, Hungertote) zaehlen ab jetzt
		var raw := c.duplicate()
		raw.erase("base")
		c["base"] = int(GoalChecks.progress(raw)[0])
	if is_met(q):
		offers.remove_at(i)
		if offers.is_empty():
			next = Game.time_days
		changed.emit()
		return tr("Dieser Auftrag ist schon erfüllt.")
	if float(q.get("until", -1.0)) <= Game.time_days:
		q["until"] = Game.time_days + (0.3 if _fast else float(q.get("days", 4.0)))
	elif _fast:
		q["until"] = Game.time_days + 0.3
	q["accepted"] = Game.time_days
	active = q
	offers = []
	_count("accepted")
	Sound.play("klick")
	changed.emit()
	return ""


## Laufenden Auftrag aufgeben (kostet nichts; neue Angebote nach der Pause).
func abandon() -> void:
	if active.is_empty():
		return
	active = {}
	next = Game.time_days + _f("cooldown", 0.5)
	_count("abandoned")
	changed.emit()


## "Andere Auftraege": sofort neue Angebote, danach erst wieder nach reroll_days.
func can_reroll() -> bool:
	return active.is_empty() and next >= 0.0 and Game.time_days >= reroll_at


func reroll() -> String:
	if not active.is_empty():
		return tr("Es läuft schon ein Auftrag.")
	if not can_reroll():
		return tr("Andere Aufträge gibt es erst wieder in %s.") % duration_text(reroll_at - Game.time_days, false)
	reroll_at = Game.time_days + _f("reroll_days", 1.0)
	_count("rerolls")
	if not make_offers():
		offers = []
		next = Game.time_days + 0.25
		changed.emit()
	return ""


func _complete() -> void:
	var q := active
	active = {}
	next = Game.time_days + _f("cooldown", 0.5)
	Game.stats["quests"] = int(Game.stats.get("quests", 0)) + 1
	_count("done")
	var got := give_reward(q)
	last = {"tpl": q.tpl, "ok": true, "day": Game.day(), "text": got}
	var msg := tr("Auftrag erfüllt: %s") % text_of(q)
	if got != "":
		msg += " " + tr("Belohnung: %s.") % got
	Game.notify(msg, "ziel", "ziel")
	Sound.play("ziel")
	changed.emit()


func _fail() -> void:
	var q := active
	active = {}
	next = Game.time_days + _f("cooldown", 0.5)
	Game.stats["quests_failed"] = int(Game.stats.get("quests_failed", 0)) + 1
	_count("failed")
	last = {"tpl": q.tpl, "ok": false, "day": Game.day(), "text": ""}
	var why := tr("Ein Siedler ist verhungert.") if q.get("survive", false) else tr("Die Zeit ist um.")
	Game.notify(tr("Auftrag nicht geschafft: %s %s Neue Aufträge kommen bald.") % [text_of(q), why], "ziel", "ziel")
	changed.emit()


func _count(k: String) -> void:
	qstats[k] = int(qstats.get(k, 0)) + 1


# ---------------------------------------------------------------- Angebote
## Neue Angebote (verschiedene Vorlagen und Belohnungen). false, wenn keine Vorlage passt.
func make_offers() -> bool:
	seq += 1
	_rng.seed = hash([Game.seed_value, seq, "auftrag"])
	_obt.clear()
	var ctx := context()
	var ids: Array = []
	for id in templates():
		if templates()[id].get("pick", true):
			ids.append(id)
	_shuffle(ids)
	var list := []
	var count := int(cfg().get("offer_count", 3))
	for id in ids:
		if list.size() >= count:
			break
		var q := make_quest(id, ctx)
		if q.is_empty() or is_met(q):
			continue
		list.append(q)
	if list.is_empty():
		return false
	_assign_rewards(list, ctx)
	offers = list
	offers_until = Game.time_days + _f("offer_days", 1.0)
	_count("offered")
	changed.emit()
	return true


## Groessen fuer die Vorlagen: A = Zeitalter, P = Siedler (auch auf See), R = Forschungspunkte je Tag.
func context() -> Dictionary:
	return {"A": Game.current_age(), "P": Game.population() + Sea.people_at_sea(), "R": research_rate()}


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _pick(a: Array):
	return a[_rng.randi_range(0, a.size() - 1)] if not a.is_empty() else null


func _quest(id: String, check: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var t: Dictionary = templates().get(id, {})
	var q := {"tpl": id, "w": int(t.get("w", 1)), "days": float(t.get("days", 4)), "until": -1.0, "check": check,
		"survive": false, "reward": {}}
	q.merge(extra, true)
	return q


static func _round5(x: float) -> int:
	return int(round(x / 5.0)) * 5


## Ziel-Zuwachs auf hoechstens stock_space des freien Platzes (alle Inseln oder Insel w) begrenzen.
func _cap_space(id: String, delta: int, w = null) -> int:
	var space := 0
	if w != null:
		space = Game.space_for(id, w)
	else:
		for ww in Sea.all_worlds():
			space += Game.space_for(id, ww)
	var cap := int(_f("stock_space", 0.7) * float(space))
	if cap < delta:
		delta = cap - cap % 5 if cap > 10 else cap
	return delta


## Eine Vorlage fuer die jetzige Lage ausfuellen ({} = passt gerade nicht).
func make_quest(id: String, ctx: Dictionary) -> Dictionary:
	var a := int(ctx.A)
	var p := int(ctx.P)
	var now := Game.time_days
	match id:
		"vorrat_essen":
			var food := ""
			for f in ["brot", "raeucherfisch", "konserven", "eier"]:
				if Data.resources.has(f) and obtainable(f):
					food = f
					break
			if food == "":
				for f in Data.food_ids():  # nach Saettigung sortiert
					if obtainable(f):
						food = f
						break
			if food == "":
				return {}
			var delta := _cap_space(food, _round5(maxf(15.0, 1.5 * p)))
			if delta < 8:
				return {}
			return _quest(id, {"type": "stock", "what": food, "n": Game.amount_all(food) + delta})
		"vorrat_ware":
			var list := []
			for r in Data.resources:
				var d: Dictionary = Data.resources[r]
				if d.get("category", "") == "material" and float(d.get("price", 0.0)) > 0.0 and Data.good_size(r) > 0 and obtainable(r):
					list.append(r)
			if list.is_empty():
				return {}
			var r: String = _pick(list)
			var delta := _cap_space(r, _round5(clampf(4.0 * p / float(Data.resources[r].price), 8.0, 100.0)))
			if delta < 8:
				return {}
			return _quest(id, {"type": "stock", "what": r, "n": Game.amount_all(r) + delta})
		"winterholz":
			if Seasons.season() > 1:
				return {}
			var start := float(Seasons.year() - 1) * Seasons.year_days() + 3.0 * Seasons.season_days()
			if start - now < 3.0:
				return {}
			var delta := _cap_space("holz", winter_wood(p, winter_mult()))
			if delta < 8:
				return {}
			return _quest(id, {"type": "stock", "what": "holz", "n": Game.amount_all("holz") + delta}, {"until": start})
		"bauen":
			var cands := []
			for type in Data.buildings:
				var d: Dictionary = Data.buildings[type]
				if not d.get("buildable", false) or not Game.is_unlocked(type) or d.has("effects"):
					continue
				if _building_count(type, true) > 0 or not _goods_ok(d.get("cost", {})):
					continue
				cands.append(type)
			if cands.is_empty():
				return make_quest("bauen_mehr", ctx)
			var type: String = _pick(cands)
			var sum := 0
			for r in Data.buildings[type].get("cost", {}):
				sum += int(Data.buildings[type].cost[r])
			var big := sum > 60
			return _quest(id, {"type": "building", "what": type, "n": 1}, {"w": 2 if big else 1, "days": 6.0 if big else 4.0})
		"bauen_mehr":
			var best := ""
			for type in Data.buildings:
				var d: Dictionary = Data.buildings[type]
				if d.get("buildable", false) and Game.is_unlocked(type) and int(d.get("housing", 0)) > 0 and _goods_ok(d.get("cost", {})):
					if best == "" or int(d.housing) > int(Data.buildings[best].housing):
						best = type
			if best == "":
				return {}
			return _quest(id, {"type": "building", "what": best, "n": _building_count(best, false) + 1})
		"wohnen":
			var cap := int(GoalChecks.progress({"type": "housing", "n": 1})[0])
			return _quest(id, {"type": "housing", "n": cap + maxi(4, roundi(0.25 * p))})
		"wachsen":
			return _quest(id, {"type": "pop", "n": p + maxi(2, ceili(0.15 * p))})
		"forschen":
			var limit := 0.7 * float(ctx.R) * 6.0
			var cands := []
			for t in Data.techs:
				var st := Game.tech_state(t)
				if st != "available" and st != "current":
					continue
				if not (t in Game.research.paid or Game.can_afford(Data.techs[t].get("cost", {}))):
					continue
				if Game.tech_points(t) - Game.tech_progress(t) <= limit:
					cands.append(t)
			if cands.is_empty():
				return {}
			return _quest(id, {"type": "tech", "what": _pick(cands), "n": 1})
		"jagd":
			if not Data.job_unlocked("jaeger"):
				return {}
			var n := mini(3 + a, huntable())
			if n < 2:
				return {}
			return _quest(id, {"type": "kills", "n": n, "base": int(Game.stats.get("kills", 0))})
		"winter":
			if Seasons.season() != 2 or Seasons.day_in_season() > 2:
				return {}
			var wt := winter_type()
			return _quest(id, {"type": "starved", "n": 0, "base": int(Game.stats.get("starved", 0))},
				{"until": float(Seasons.year()) * Seasons.year_days(), "survive": true, "w": 3 if wt in ["hart", "bitter"] else 2})
		"liefern":
			var worlds := Sea.all_worlds().filter(func(w): return not w.settlers.is_empty())
			if worlds.size() < 2 or Sea.ships.is_empty():
				return {}
			var pairs := []
			for src in worlds:
				for dst in worlds:
					if dst == src:
						continue
					for r in Data.resources:
						if float(Data.resources[r].get("price", 0.0)) > 0.0 and Data.good_size(r) > 0 and Game.amount(r, src) >= 10:
							pairs.append([src, dst, r])
			if pairs.is_empty():
				return {}
			var pr: Array = _pick(pairs)
			var r: String = pr[2]
			var want := minf(Game.amount(r, pr[0]) * 0.6, 3.0 * p / float(Data.resources[r].price))
			var delta := _cap_space(r, _round5(clampf(want, 8.0, 60.0)), pr[1])
			if delta < 8:
				return {}
			return _quest(id, {"type": "stock_at", "what": r, "island": int(pr[1].island_id), "n": Game.amount(r, pr[1]) + delta})
		"geburten":
			return _quest(id, {"type": "births", "n": 2 + p / 8, "base": int(Game.stats.get("births", 0))})
		"entdecken":
			if Sea.ships.is_empty():
				return {}
			return _quest(id, {"type": "islands_found", "n": 1, "base": maxi(0, Sea.islands.size() - 1)})
		"abwechslung":
			var best := int(GoalChecks.progress({"type": "variety", "max": true, "n": 1})[0])
			var kinds := 0
			for f in Data.food_ids():
				if obtainable(f):
					kinds += 1
			if kinds <= best:
				return {}
			return _quest(id, {"type": "variety", "max": true, "n": best + 1})
	return {}


## Gebaeude dieses Typs (auch Ausbaustufen mit gleichem `base`), mit Baustellen oder nur fertige.
func _building_count(type: String, any: bool) -> int:
	return int(GoalChecks.progress({"type": "building", "what": type, "n": 1, "any": any})[0])


## Jede Ware laesst sich beschaffen oder liegt schon in genug Menge im Lager.
func _goods_ok(goods: Dictionary) -> bool:
	for r in goods:
		if not obtainable(str(r)) and Game.amount_all(str(r)) < int(goods[r]):
			return false
	return true


## Eine Ware laesst sich beschaffen: ein fertiges Gebaeude stellt sie her (oder erntet sie), eine
## Rohstoffquelle auf einer besiedelten Insel liefert sie und ein freigeschalteter Beruf baut sie ab,
## oder Jaeger koennen Tiere jagen (Fleisch, Felle).
func obtainable(id: String) -> bool:
	if _obt.has(id):
		return _obt[id]
	var ok := false
	var targets := {}
	for j in Data.jobs:
		if Data.job_unlocked(j):
			for t in Data.jobs[j].get("targets", []):
				targets[str(t)] = true
	for w in Sea.all_worlds():
		if ok:
			break
		for b in w.buildings:
			if b.complete and (b.def.get("production", {}).get("outputs", {}).has(id) or str(b.def.get("farm", {}).get("yield", "")) == id):
				ok = true
				break
		if not ok:
			for n in w.nodes:
				if targets.has(n.type) and str(n.def.get("yield", "")) == id:
					ok = true
					break
		if not ok and id in ["fleisch", "felle"] and targets.has("hunt") and not w.animals.is_empty():
			ok = true
	_obt[id] = ok
	return ok


## Erwachsene Tiere, die Jaeger erlegen duerfen (je Art bleiben hunt_min_keep).
func huntable() -> int:
	var keep := int(Data.bal("hunt_min_keep", 2))
	var n := 0
	for w in Sea.all_worlds():
		var per := {}
		for an in w.animals:
			if is_instance_valid(an) and an.is_adult():
				per[an.type] = int(per.get(an.type, 0)) + 1
		for t in per:
			n += maxi(0, int(per[t]) - keep)
	return n


## Art des kommenden Winters, so wie die Siedler sie kennen (Seasons.winter_forecast: im Frühling
## noch unbekannt = "normal", im Sommer grob, ab Herbst genau; "streng" zählt wie "hart"). So verrät
## die Menge Winterholz nichts, was die Vorhersage noch nicht gesagt hat.
func winter_type() -> String:
	var f := Seasons.winter_forecast()
	if f == "":
		return "normal"
	return "hart" if f == "streng" else f


func winter_mult() -> float:
	return float(cfg().get("winter_mult", {}).get(winter_type(), 1.0))


## Zusaetzliches Holz fuer den Winter: 3 je Siedler mal Faktor der Winterart, auf 5 gerundet.
func winter_wood(p: int, mult: float) -> int:
	return maxi(10, int(ceil(float(p) * 3.0 * mult / 5.0)) * 5)


# ---------------------------------------------------------------- Belohnungen
## Jedes Angebot bekommt eine Belohnung: das leichteste Waren, die anderen moeglichst andere Arten;
## hoechstens ein Segen. Einwanderer, Segen und Bauplan erst ab Gewicht 2.
func _assign_rewards(list: Array, ctx: Dictionary) -> void:
	var order := range(list.size())
	order.sort_custom(func(x, y): return int(list[x].w) < int(list[y].w) or (int(list[x].w) == int(list[y].w) and x < y))
	var used := []
	var boon_ok := not boon_choices().is_empty()
	var plan_ok := not plan_choices().is_empty()
	for k in order.size():
		var q: Dictionary = list[order[k]]
		var kinds := ["goods", "research"]
		if int(q.w) >= 2:
			kinds.append("settlers")
			if boon_ok and not "boon" in used:
				kinds.append("boon")
			if plan_ok:
				kinds.append("plan")
		var kind := "goods"
		if _force_reward != "":
			kind = _force_reward
		elif k > 0:
			var fresh := kinds.filter(func(x): return not x in used)
			kind = str(_pick(fresh if not fresh.is_empty() else kinds.filter(func(x): return x != "boon")))
		used.append(kind)
		q["reward"] = make_reward(kind, q, ctx)


func make_reward(kind: String, q: Dictionary, ctx: Dictionary) -> Dictionary:
	var w := int(q.get("w", 1))
	match kind:
		"research":
			var pts := maxf(_f("research_min_per_w", 20) * w, w * float(ctx.R) * _f("research_days_per_w", 1.0))
			return {"kind": "research", "n": int(round(pts / 10.0)) * 10}
		"settlers":
			var tal: Array = Array(cfg().get("talents", ["wissen"])).filter(func(x): return Data.skills.has(str(x)))
			if Data.job_unlocked("jaeger") and Data.skills.has("jagd"):
				tal.append("jagd")
			return {"kind": "settlers", "n": 2 if w >= 3 else 1, "talent": str(_pick(tal)) if not tal.is_empty() else ""}
		"boon":
			var ch := boon_choices()
			if not ch.is_empty():
				var b: Dictionary = _pick(ch)
				return {"kind": "boon", "key": str(b.key), "v": float(b.v)}
		"plan":
			var pl := plan_choices()
			if not pl.is_empty():
				return {"kind": "plan", "what": str(_pick(pl))}
	return goods_reward(w, int(ctx.A))


## Waren im Wert goods_budget * w * (1 + Zeitalter) Gold (Menge = Budget / price), hoechstens goods_space
## der Lagerkapazitaet aller Inseln fuer diese Ware (sonst ginge das meiste verloren), mindestens 3.
func goods_reward(w: int, a: int) -> Dictionary:
	var ages: Array = cfg().get("goods_by_age", [["holz"]])
	var pool: Array = Array(ages[clampi(a, 0, ages.size() - 1)]).filter(func(x): return Data.resources.has(str(x)) and float(Data.resources[str(x)].get("price", 0.0)) > 0.0)
	if pool.is_empty():
		pool = ["holz"]
	var id := str(_pick(pool))
	var want := maxi(3, roundi(_f("goods_budget", 25.0) * w * (1 + a) / float(Data.resources[id].get("price", 0.1))))
	var units := 0
	for ww in Sea.all_worlds():
		units += Game.storage_volume(ww) / maxi(1, Data.good_size(id))
	var n := clampi(int(_f("goods_space", 0.4) * float(units)), 3, want)
	if n > 20:
		n -= n % 5
	return {"kind": "goods", "what": id, "n": n}


func boon_def(key: String) -> Dictionary:
	for b in cfg().get("boons", []):
		if b is Dictionary and str(b.get("key", "")) == key:
			return b
	return {}


## Segen, die noch nicht an ihrer Obergrenze sind.
func boon_choices() -> Array:
	var out := []
	for b in cfg().get("boons", []):
		if b is Dictionary and absf(float(boons.get(str(b.key), 0.0)) + float(b.v)) <= absf(float(b.cap)) + 0.0001:
			out.append(b)
	return out


## Gebaeude fuer einen Bauplan: baubar, noch nicht freigeschaltet, Forschung waehlbar (Voraussetzungen
## erforscht, Zeitalter erreicht), kein Hafen/Schiff/Denkmal, Waren fuer Bau und Betrieb beschaffbar.
func plan_choices() -> Array:
	var out := []
	for type in Data.buildings:
		var d: Dictionary = Data.buildings[type]
		if not d.get("buildable", false) or Game.is_unlocked(type) or type in plans:
			continue
		if d.get("category", "") == "see" or d.has("harbor") or d.has("effects"):
			continue
		var req := str(d.get("requires", ""))
		if not Data.techs.has(req) or not Game.tech_state(req) in ["available", "current"]:
			continue
		if Data.age_of_tier(int(Data.techs[req].get("tier", 1))) > Game.current_age():
			continue
		var prod: Dictionary = d.get("production", {})
		var ship := false
		for o in prod.get("outputs", {}):
			if Data.resources.get(str(o), {}).get("category", "") == "ship":
				ship = true
		if ship:
			continue
		var ok := true
		for r in prod.get("inputs", {}):
			if not obtainable(str(r)) and Game.amount_all(str(r)) <= 0:
				ok = false
		if ok and _goods_ok(d.get("cost", {})):
			out.append(type)
	return out


func has_plan(type: String) -> bool:
	return type in plans


## Nur durch einen Bauplan baubar (ohne die Forschung).
func plan_only(type: String) -> bool:
	return type in plans and not Game.is_researched(str(Data.buildings.get(type, {}).get("requires", "")))


## Game._recompute_effects: Segen in die Wirkungen einrechnen.
func add_boons(effects: Dictionary) -> void:
	for k in boons:
		effects[k] = float(effects.get(k, 0.0)) + float(boons[k])


## Belohnung auszahlen; liefert eine kurze Zusammenfassung.
func give_reward(q: Dictionary) -> String:
	var r: Dictionary = q.get("reward", {})
	var w := int(q.get("w", 1))
	match str(r.get("kind", "")):
		"goods":
			var txt := Game.grant_reward(Game.world, {str(r.what): int(r.n)})
			return reward_text(r) + txt if txt.begins_with(" ") else txt  # alles ohne Platz: Ware trotzdem nennen
		"research":
			return _give_research(float(r.n))
		"settlers":
			var target = Game.world
			if target == null or Game.housing_capacity(target) <= target.settlers.size():
				target = Game.immigrant_world()
			var tal := str(r.get("talent", ""))
			var opts := {"hunger": 80.0}
			if Data.skills.has(tal):
				opts["talent"] = tal
				opts["talent_val"] = _rng.randf_range(1.5, float(Data.ppl("talent_max", 1.8)))
			var got := Game.grant_reward(target, {"settlers": int(r.n)}, opts)
			if Data.skills.has(tal):
				got += " " + tr("(begabt für %s)") % str(Data.skills[tal].name)
			return got
		"boon":
			var key := str(r.key)
			var b := boon_def(key)
			var cur := float(boons.get(key, 0.0))
			if not b.is_empty() and absf(cur) < absf(float(b.cap)) - 0.0001:
				var v := float(r.v)
				boons[key] = clampf(cur + v, minf(0.0, float(b.cap)), maxf(0.0, float(b.cap)))
				Game.refresh_effects()
				return tr("Segen: %s") % boon_text(key, v)
		"plan":
			var type := str(r.what)
			if Data.buildings.has(type) and not Game.is_unlocked(type):
				plans.append(type)
				Game.refresh_effects()
				Game.research_changed.emit()
				return tr("Bauplan: %s (jetzt im Baumenü)") % GoalChecks.building_name(type)
	# Segen schon voll oder Gebaeude schon freigeschaltet: Waren statt dessen
	var g := goods_reward(w, Game.current_age())
	return Game.grant_reward(Game.world, {str(g.what): int(g.n)})


## Forschungspunkte: auf die laufende Forschung (frei, ohne Schreibwaren), Rest fuer die naechste.
func _give_research(pts: float) -> String:
	var left := _apply_research(pts)
	rp_bank += left
	if left > 0.5:
		return tr("%d Forschungspunkte (%d davon für die nächste Forschung)") % [int(pts), int(left)]
	return tr("%d Forschungspunkte") % int(pts)


## Punkte auf die laufende Forschung, hoechstens bis sie fertig ist; liefert den Rest.
func _apply_research(pts: float) -> float:
	var t: String = Game.research.current
	if t == "" or pts <= 0.0:
		return pts
	var use := minf(pts, maxf(0.0, Game.tech_points(t) - Game.tech_progress(t)))
	Game.add_research(use, false)
	return pts - use


func _on_research_changed() -> void:
	if rp_bank > 0.5 and Game.research.current != "":
		_pay_bank.call_deferred()


func _pay_bank() -> void:
	if rp_bank <= 0.5 or Game.research.current == "":
		return
	var t: String = Game.research.current
	var had := rp_bank
	rp_bank = 0.0
	rp_bank = _apply_research(had)
	Game.notify(tr("Gesparte Forschungspunkte aus einem Auftrag: %d für %s.") % [int(had - rp_bank), str(Data.techs.get(t, {}).get("name", t))], "wissen")
	changed.emit()


# ---------------------------------------------------------------- Forschung je Tag
## Alle Forschungspunkte bisher (erforschte Forschungen plus Fortschritt).
func research_total() -> float:
	var n := 0.0
	for t in Game.research.done:
		n += Game.tech_points(t)
	for t in Game.research.progress:
		n += float(Game.research.progress[t])
	return n


func _mark_research() -> void:
	rp_marks.append([Game.time_days, research_total()])
	while rp_marks.size() > 1 and Game.time_days - float(rp_marks[1][0]) >= 1.0:
		rp_marks.pop_front()


## Forschungspunkte je Tag, gemessen ueber den letzten Tag (mindestens research_min_rate).
func research_rate() -> float:
	var mn := _f("research_min_rate", 4.0)
	if rp_marks.is_empty():
		return mn
	var dt := Game.time_days - float(rp_marks[0][0])
	if dt < 0.5:
		return mn
	return maxf(mn, (research_total() - float(rp_marks[0][1])) / dt)


# ---------------------------------------------------------------- Texte
## Text eines Auftrags aus der Vorlage (beim Anzeigen gebaut, damit die Sprache stimmt).
func text_of(q: Dictionary) -> String:
	var tpl := str(q.get("tpl", ""))
	var text := str(templates().get(tpl, {}).get("text", tpl))
	var c: Dictionary = q.get("check", {})
	var what := str(c.get("what", ""))
	var n := int(c.get("n", 0))
	var args := []
	match tpl:
		"vorrat_essen", "vorrat_ware":
			args = [n, Data.resource_name(what)]
		"winterholz", "wohnen", "wachsen", "abwechslung", "jagd", "geburten":
			args = [n]
		"bauen", "bauen_mehr":
			args = [GoalChecks.building_name(what)]
		"forschen":
			args = [str(Data.techs.get(what, {}).get("name", what.capitalize()))]
		"liefern":
			args = [str(Sea.meta(int(c.get("island", -1))).get("name", "?")), n, Data.resource_name(what)]
	var holes := RegEx.create_from_string("%[sd]").search_all(text).size()
	if holes != args.size():
		return text
	return text % args if holes > 0 else text


func reward_text(r: Dictionary) -> String:
	match str(r.get("kind", "")):
		"goods":
			return "%d %s" % [int(r.n), Data.resource_name(str(r.what))]
		"research":
			return tr("%d Forschungspunkte") % int(r.n)
		"settlers":
			var tal := str(r.get("talent", ""))
			var who := tr("1 Einwanderer") if int(r.n) == 1 else tr("%d Einwanderer") % int(r.n)
			if Data.skills.has(tal):
				who += " " + tr("(begabt für %s)") % str(Data.skills[tal].name)
			return who
		"boon":
			return tr("Segen: %s") % boon_text(str(r.key), float(r.v))
		"plan":
			return tr("Bauplan: %s") % GoalChecks.building_name(str(r.what))
	return ""


func reward_icon(r: Dictionary) -> Texture2D:
	match str(r.get("kind", "")):
		"goods":
			return Data.res_icon(str(r.what)) if Data.resources.has(str(r.what)) else Data.icon("kiste")
		"research":
			return Data.icon("wissen")
		"settlers":
			return Data.icon("person")
		"boon":
			return Data.icon("sonne")
		"plan":
			return Data.building_tex(str(r.what)) if Data.buildings.has(str(r.what)) else Data.icon("hammer")
	return Data.icon("ziel")


## "Holzfällen +15 %", "Tragen +1", "Hunger -5 %"
func boon_text(key: String, v: float) -> String:
	var b := boon_def(key)
	var name := str(b.get("name", key))
	if b.get("add", false):
		return "%s %+d" % [name, roundi(v)]
	return "%s %+d %%" % [name, roundi(v * 100.0)]


## Kurz "2 T. 5 Std." / "5 Std." (Zielkarte), lang "4 Tage" / "1 Tag 6 Std." (Fenster).
func duration_text(days: float, short: bool = true) -> String:
	days = maxf(0.0, days)
	var d := int(floor(days + 0.0001))
	var h := int(floor((days - d) * 24.0 + 0.001))
	if d <= 0:
		return tr("%d Std.") % maxi(h, 1) if days > 0.0 else tr("0 Std.")
	if short:
		return tr("%d T. %d Std.") % [d, h] if h > 0 else tr("%d T.") % d
	var t := tr("1 Tag") if d == 1 else tr("%d Tage") % d
	if h > 0:
		t += " " + tr("%d Std.") % h
	return t


## Fortschritt als Text: "34/40", beim Winter-Auftrag "kein Hungertod" bzw. "Hungertod".
func progress_text(q: Dictionary) -> String:
	var p := progress(q)
	if q.get("survive", false):
		return tr("kein Hungertod") if int(p[0]) <= 0 else tr("Hungertod")
	return "%d/%d" % [maxi(0, int(p[0])), int(p[1])]


func progress_ratio(q: Dictionary) -> float:
	if q.get("survive", false):  # Winter: Anteil der Zeit, die schon geschafft ist
		var t0 := float(q.get("accepted", Game.time_days))
		return clampf((Game.time_days - t0) / maxf(0.01, float(q.get("until", t0)) - t0), 0.0, 1.0)
	var p := progress(q)
	return clampf(float(p[0]) / maxf(1.0, float(p[1])), 0.0, 1.0)


# ---------------------------------------------------------------- Spielstand
func _clear() -> void:
	offers = []
	active = {}
	next = -1.0
	offers_until = 0.0
	reroll_at = 0.0
	plans = []
	boons = {}
	rp_bank = 0.0
	rp_marks = []
	seq = 0
	qstats = {}
	last = {}
	_next_check = 0.0
	_obt.clear()


func _on_reset() -> void:
	_clear()
	Game._recompute_effects()  # Segen und Bauplaene des alten Spiels entfernen
	_mark_research()
	changed.emit()


func serialize() -> Dictionary:
	return {"offers": offers.duplicate(true), "active": active.duplicate(true), "next": next, "offers_until": offers_until,
		"reroll_at": reroll_at, "plans": plans.duplicate(), "boons": boons.duplicate(), "rp_bank": rp_bank,
		"rp_marks": rp_marks.duplicate(true), "seq": seq, "stats": qstats.duplicate(), "last": last.duplicate()}


func _on_save(data: Dictionary) -> void:
	data["quests"] = serialize()


## Nach dem Laden (alle Welten da). Ohne "quests" (alter Spielstand): das Brett oeffnet gleich,
## auch mitten in der Einfuehrung. Segen und Bauplaene wirken erst nach refresh_effects.
func _on_load(data: Dictionary, old_rules: int) -> void:
	_clear()
	var d = data.get("quests", null)
	if d is Dictionary:
		apply_state(d)
	elif old_rules < 1 or not in_tutorial():
		next = Game.time_days
	if rp_marks.is_empty():
		_mark_research()
	Game.refresh_effects()
	if old_rules < 1:
		Game.rules_lines.append(tr("Neue Aufträge mit Wahl: du suchst dir einen von drei aus. Belohnungen sind Einwanderer, dauerhafte Segen, Baupläne oder seltene Waren."))
	changed.emit()


## Gespeicherten Zustand uebernehmen: Zahlen umwandeln (JSON liefert float), unbekannte Waren,
## Gebaeude, Forschungen, Segen und Vorlagen fallen weg.
func apply_state(d: Dictionary) -> void:
	offers = []
	for q in d.get("offers", []):
		var s := sanitize_quest(q)
		if not s.is_empty():
			offers.append(s)
	active = sanitize_quest(d.get("active", {}))
	next = float(d.get("next", -1.0))
	offers_until = float(d.get("offers_until", 0.0))
	reroll_at = float(d.get("reroll_at", 0.0))
	plans = []
	for t in d.get("plans", []):
		if Data.buildings.has(str(t)) and Data.buildings[str(t)].get("buildable", false) and not str(t) in plans:
			plans.append(str(t))
	boons = {}
	var bd = d.get("boons", {})
	if bd is Dictionary:
		for k in bd:
			var b := boon_def(str(k))
			if not b.is_empty():
				boons[str(k)] = clampf(float(bd[k]), minf(0.0, float(b.cap)), maxf(0.0, float(b.cap)))
	rp_bank = maxf(0.0, float(d.get("rp_bank", 0.0)))
	rp_marks = []
	for m in d.get("rp_marks", []):
		if m is Array and m.size() >= 2:
			rp_marks.append([float(m[0]), float(m[1])])
	seq = int(d.get("seq", 0))
	qstats = {}
	var st = d.get("stats", {})
	if st is Dictionary:
		for k in st:
			qstats[str(k)] = int(st[k])
	var l = d.get("last", {})
	last = l if l is Dictionary else {}


func sanitize_quest(q) -> Dictionary:
	if not q is Dictionary or q.is_empty():
		return {}
	var tpl := str(q.get("tpl", ""))
	var c = q.get("check", {})
	if not templates().has(tpl) or not c is Dictionary:
		return {}
	var type := str(c.get("type", ""))
	var what := str(c.get("what", ""))
	var check := {"type": type, "n": int(c.get("n", 1))}
	match type:
		"stock":
			if not Data.resources.has(what):
				return {}
		"stock_at":
			if not Data.resources.has(what) or not Sea.worlds.has(int(c.get("island", -1))):
				return {}
			check["island"] = int(c.island)
		"building":
			if not Data.buildings.has(what):
				return {}
		"tech":
			if not Data.techs.has(what):
				return {}
		"housing", "pop", "kills", "births", "islands_found", "variety", "starved":
			pass
		_:
			return {}
	if what != "":
		check["what"] = what
	if c.has("base"):
		check["base"] = int(c.base)
	if c.get("max", false):
		check["max"] = true
	if c.get("any", false):
		check["any"] = true
	var reward := sanitize_reward(q.get("reward", {}))
	if reward.is_empty():
		return {}
	var out := {"tpl": tpl, "w": clampi(int(q.get("w", 1)), 1, 3), "days": float(q.get("days", 4.0)),
		"until": float(q.get("until", -1.0)), "check": check, "survive": bool(q.get("survive", false)), "reward": reward}
	if q.has("accepted"):
		out["accepted"] = float(q.accepted)
	return out


func sanitize_reward(r) -> Dictionary:
	if not r is Dictionary:
		return {}
	match str(r.get("kind", "")):
		"goods":
			if Data.resources.has(str(r.get("what", ""))):
				return {"kind": "goods", "what": str(r.what), "n": maxi(1, int(r.get("n", 1)))}
		"research":
			return {"kind": "research", "n": maxi(1, int(r.get("n", 1)))}
		"settlers":
			var tal := str(r.get("talent", ""))
			return {"kind": "settlers", "n": clampi(int(r.get("n", 1)), 1, 3), "talent": tal if Data.skills.has(tal) else ""}
		"boon":
			if not boon_def(str(r.get("key", ""))).is_empty():
				return {"kind": "boon", "key": str(r.key), "v": float(r.get("v", 0.0))}
		"plan":
			if Data.buildings.has(str(r.get("what", ""))):
				return {"kind": "plan", "what": str(r.what)}
	return {}


# ---------------------------------------------------------------- Selbsttest
## --questtest=N: Generator (40 Runden, Regeln), jede Belohnungsart direkt, Segen-Obergrenze, Bauplan,
## Speichern/Laden mit unbekannten IDs, alter Spielstand; danach im laufenden Spiel: Angebot N annehmen
## und erfuellen, einen Auftrag scheitern lassen, einen aufgeben, "Andere Auftraege", Winter-Auftrag
## (geschafft und gescheitert), Ablauf der Angebote. --questreward=goods|research|settlers|boon|plan
## erzwingt die Belohnung, --questfast=1 setzt jede Frist auf 0,3 Tage.
## --questauto=1: Einfuehrung ueberspringen und jedes Angebot von selbst annehmen (Angebot 1), damit
## Auftraege im normalen Spiel (z. B. mit --build=1 --research=1) erscheinen und erfuellt werden.
## Bildschirmfotos: --questshot=offers|active|card (mit --panel=quests fuer das Fenster).
func autotest_setup(args: Dictionary, main) -> void:
	_force_reward = str(args.get("questreward", "")) if args.has("questreward") else ""
	_fast = args.has("questfast")
	if args.has("questtest"):
		await _quest_test(int(args.questtest), main)
	if args.has("questshot"):
		await _quest_shot(str(args.questshot), main)
	if args.has("questauto"):
		Game.goals["tut"] = Data.goals.get("tutorial", []).size()
		_auto_loop(main)


func _auto_loop(main) -> void:
	while is_instance_valid(main) and not Game.is_over:
		await get_tree().create_timer(1.0, true, false, true).timeout
		if active.is_empty() and not offers.is_empty():
			print("Auftrag angenommen (Tag %.2f): %s | Belohnung %s | Angebote %s" % [Game.time_days, text_of(offers[0]), reward_text(offers[0].reward),
				offers.map(func(q): return text_of(q))])
			accept(0)


func autotest_report() -> String:
	var off := offers.map(func(q): return "%s [%s, w%d]" % [text_of(q), reward_text(q.reward), int(q.w)])
	var act := []
	if not active.is_empty():
		act = [text_of(active), progress_text(active), duration_text(float(active.until) - Game.time_days), reward_text(active.reward)]
	print("   Auftraege: naechste %.2f, Angebote %s | laufend: %s | Segen %s Bauplaene %s Bank %d | R %.0f/Tag | %s | stats quests=%d failed=%d" % [
		next, off if not off.is_empty() else "-", act if not act.is_empty() else "-", boons, plans, int(rp_bank), research_rate(), qstats,
		int(Game.stats.get("quests", 0)), int(Game.stats.get("quests_failed", 0))])
	return ""


func _wait(cond: Callable, max_s: float) -> bool:
	var t := 0.0
	while not cond.call() and t < max_s:
		await get_tree().create_timer(0.25, true, false, true).timeout
		t += 0.25
	return cond.call()


func _quest_shot(kind: String, main) -> void:
	Game.goals["tut"] = Data.goals.get("tutorial", []).size()
	var w = main.world
	for id in ["holz", "stein", "beeren", "fisch"]:
		w.stock[id] = maxi(Game.amount(id, w), 60)
	next = Game.time_days
	tick()
	if kind == "active" or kind == "card":
		accept(0)
		var c: Dictionary = active.get("check", {})
		if c.get("type", "") == "stock":  # etwas Fortschritt fuer den Balken
			w.stock[str(c.what)] = maxi(0, int(c.n) - 12)
	if kind == "segen" or kind == "active":
		_give_test(make_reward("boon", {"w": 2}, context()))
		_give_test({"kind": "boon", "key": "gather_holz", "v": 0.15})
		var pl := plan_choices()
		if not pl.is_empty():
			_give_test({"kind": "plan", "what": pl[0]})
	print("Auftragsbild %s: Angebote %d, laufend %s" % [kind, offers.size(), text_of(active) if not active.is_empty() else "-"])


func _give_test(r: Dictionary) -> String:
	return give_reward({"w": 2, "reward": r})


func _quest_test(n: int, main) -> void:
	var w = main.world
	_test = {"main": main}
	Data.balance["base_storage"] = 4000  # Testlauf: genug Stauraum
	Game.goals["tut"] = Data.goals.get("tutorial", []).size()  # Einfuehrung ueberspringen
	for id in ["holz", "stein", "beeren", "fisch"]:
		w.stock[id] = maxi(Game.amount(id, w), 80)
	print("Auftragstest: %d Vorlagen %s" % [templates().size(), templates().keys()])
	print("   Lage: Zeitalter %d, Siedler %d, Forschung %.0f/Tag, Jahreszeit %s" % [Game.current_age(), Game.population(), research_rate(), Seasons.season_name()])
	var wm: Dictionary = cfg().get("winter_mult", {})
	print("   Winter: Art %s (Vorhersage '%s', tatsächlich %s), Faktor %.2f, Winterholz bei 10 Siedlern %s" % [winter_type(),
		Seasons.winter_forecast(), Seasons.winter_type(), winter_mult(), wm.keys().map(func(k): return "%s %d" % [k, winter_wood(10, float(wm[k]))])])
	# 1) Generator: 40 Runden, Regeln pruefen
	var keep_seq := seq
	var tpl_n := {}
	var kind_n := {}
	var bad := 0
	for round_i in 40:
		if not make_offers():
			bad += 1
			continue
		var ids := offers.map(func(q): return q.tpl)
		var kinds := offers.map(func(q): return q.reward.kind)
		for t in ids:
			tpl_n[t] = int(tpl_n.get(t, 0)) + 1
		for k in kinds:
			kind_n[k] = int(kind_n.get(k, 0)) + 1
		var uniq := {}
		for t in ids:
			uniq[t] = true
		var small_big := offers.filter(func(q): return int(q.w) < 2 and str(q.reward.kind) in ["settlers", "boon", "plan"])
		var reward_bad: bool = _force_reward == "" and (not "goods" in kinds or kinds.count("boon") > 1 or not small_big.is_empty())  # --questreward erzwingt die Art
		if uniq.size() != ids.size() or reward_bad or offers.size() != int(cfg().get("offer_count", 3)):
			bad += 1
			print("   Regel verletzt: ", ids, kinds)
		if round_i < 3:
			for q in offers:
				print("   Beispiel Runde %d: %s | Frist %s | Belohnung %s (w%d)" % [round_i + 1, text_of(q),
					duration_text(float(q.days), false) if float(q.until) < 0.0 else "fest", reward_text(q.reward), int(q.w)])
	print("   Generator 40 Runden: Vorlagen %s, Belohnungen %s, Regeln verletzt: %d %s" % [tpl_n, kind_n, bad, "OK" if bad == 0 else "FEHLER"])
	seq = keep_seq
	offers = []
	# 2) Jede Belohnungsart direkt
	var ctx := context()
	var g := make_reward("goods", {"w": 1}, ctx)
	var before := Game.amount_all(str(g.what))
	print("   Belohnung Waren: %s -> %s, Lager %s %d -> %d" % [reward_text(g), _give_test(g), g.what, before, Game.amount_all(str(g.what))])
	var keep_stock: Dictionary = w.stock.duplicate()
	Game.give_goods(w, str(g.what), 1000000)  # Lager voll: Ware wird trotzdem genannt
	print("   Belohnung Waren bei vollem Lager: %s" % _give_test(g))
	w.stock = keep_stock
	var big := goods_reward(3, 7)
	print("   Waren Zeitalter 7, w3: %s (Budget %d Gold)" % [reward_text(big), int(_f("goods_budget", 25) * 3 * 8)])
	Game.research.current = ""
	var rr := make_reward("research", {"w": 2}, ctx)
	print("   Belohnung Forschung ohne laufende Forschung: %s -> %s, Bank %d" % [reward_text(rr), _give_test(rr), int(rp_bank)])
	var tech := ""
	for t in Data.sorted_tech_ids():
		if Game.tech_state(t) == "available" and Game.can_afford(Data.techs[t].get("cost", {})):
			tech = t
			break
	if tech != "":
		var used0 := int(Game.stats.get("writing_used", 0))
		Game.start_research(tech)
		await get_tree().process_frame
		await get_tree().process_frame
		print("   Forschung %s gestartet: Bank jetzt %d, Fortschritt %d/%d (oder fertig: %s), Schreibwaren verbraucht %d (frei)" % [tech, int(rp_bank),
			int(Game.tech_progress(tech)), int(Game.tech_points(tech)), tech in Game.research.done, int(Game.stats.get("writing_used", 0)) - used0])
	var pop0 := Game.population()
	var sr := make_reward("settlers", {"w": 3}, ctx)
	var got := _give_test(sr)
	var newest = w.settlers.back()
	print("   Belohnung Einwanderer: %s -> %s, Siedler %d -> %d, %s: Begabung %s %.2f, Stufe %d, Hunger %d" % [reward_text(sr), got, pop0, Game.population(),
		newest.display_name, sr.talent, float(newest.mind.talents.get(sr.talent, 0.0)), int(newest.skills.get(sr.talent, 0)), int(newest.hunger)])
	var e0 := Game.eff("gather_holz")
	var out := []
	for i in 4:
		out.append(_give_test({"kind": "boon", "key": "gather_holz", "v": 0.15}))
	print("   Belohnung Segen 4x Holzfaellen: %s, eff(gather_holz) %.2f -> %.2f (Obergrenze 0.45), noch waehlbar: %s" % [out, e0, Game.eff("gather_holz"),
		boon_choices().any(func(b): return b.key == "gather_holz")])
	var h0 := Game.eff("hunger")
	for i in 4:
		_give_test({"kind": "boon", "key": "hunger", "v": -0.05})
	print("   Segen Hunger 4x: eff(hunger) %.2f -> %.2f (Obergrenze -0.15)" % [h0, Game.eff("hunger")])
	var pl := plan_choices()
	print("   Bauplan-Kandidaten: %s" % [pl])
	if not pl.is_empty():
		var bt: String = pl[0]
		var u0 := Game.is_unlocked(bt)
		print("   Belohnung Bauplan: %s, freigeschaltet %s -> %s, nur Bauplan=%s, Forschung %s=%s" % [_give_test({"kind": "plan", "what": bt}), u0,
			Game.is_unlocked(bt), plan_only(bt), Data.buildings[bt].requires, Game.tech_state(Data.buildings[bt].requires)])
		print("   Bauplan-Kandidaten danach: %s (ohne %s)" % [plan_choices(), bt])
	# 3) Speichern und Laden, unbekannte IDs, alter Spielstand
	var d := {}
	_on_save(d)
	var json := JSON.stringify(d.quests)
	apply_state(JSON.parse_string(json))
	print("   Spielstand quests: %d Zeichen, nach JSON-Rundreise gleich: %s" % [json.length(), "OK" if JSON.stringify(serialize()) == json else "FEHLER"])
	var keep := serialize()
	apply_state({"offers": [{"tpl": "gibtsnicht", "check": {"type": "pop", "n": 3}, "reward": {"kind": "goods", "what": "holz", "n": 5}},
		{"tpl": "bauen", "check": {"type": "building", "what": "gibtsnicht", "n": 1}, "reward": {"kind": "goods", "what": "holz", "n": 5}},
		{"tpl": "wachsen", "check": {"type": "pop", "n": 9.0}, "w": 2.0, "reward": {"kind": "settlers", "n": 1.0, "talent": "gibtsnicht"}}],
		"plans": ["gibtsnicht", "schreibstube"], "boons": {"gibtsnicht": 1.0, "gather_holz": 5.0}, "seq": 7.0})
	print("   Unbekannte IDs: Angebote %s, Bauplaene %s, Segen %s, seq %d" % [offers.map(func(q): return [q.tpl, q.check, q.reward]), plans, boons, seq])
	apply_state(keep)
	var lines0 := Game.rules_lines.size()
	_on_load({}, 0)
	print("   Alter Spielstand ohne quests: naechste Angebote %.2f (jetzt %.2f), Regelzeile: %s" % [next, Game.time_days,
		Game.rules_lines.slice(lines0) if Game.rules_lines.size() > lines0 else "FEHLT"])
	apply_state(keep)
	Game.refresh_effects()
	offers = []
	active = {}
	next = Game.time_days
	_quest_flow(n, main)


## Teil 2 im laufenden Spiel (nicht abgewartet; der Test laeuft weiter).
func _quest_flow(n: int, main) -> void:
	var w = main.world
	await _wait(func(): return not offers.is_empty(), 20.0)
	print("Auftragstest: Angebote erschienen: %s" % [offers.map(func(q): return "%s -> %s" % [text_of(q), reward_text(q.reward)])])
	var i := clampi(n - 1, 0, offers.size() - 1)
	if _force_reward != "":
		offers[i].reward = make_reward(_force_reward, offers[i], context())
	print("   Annehmen %d: '%s' -> %s" % [i + 1, accept(i), text_of(active)])
	var q0 := active.duplicate(true)
	_fulfil(q0, w, main)
	await _wait(func(): return active.is_empty(), 15.0)
	print("Auftragstest: Auftrag 1 %s, stats.quests=%d, Wertung Auftraege: %s" % ["erfuellt" if int(qstats.get("done", 0)) >= 1 else "NICHT erfuellt",
		int(Game.stats.get("quests", 0)), Exams.score_parts().filter(func(r): return r[0] == tr("Erledigte Aufträge"))])
	# Scheitern: Frist sehr kurz, nichts tun
	await _wait(func(): return not offers.is_empty(), 30.0)
	print("   Neue Angebote nach der Pause: %d (Tag %.2f)" % [offers.size(), Game.time_days])
	accept(0)
	active.until = Game.time_days + 0.08
	print("   Annehmen und liegen lassen: '%s', Frist 0,08 Tage" % text_of(active))
	await _wait(func(): return active.is_empty(), 10.0)
	print("Auftragstest: Auftrag 2 %s, stats.quests_failed=%d" % ["gescheitert" if int(qstats.get("failed", 0)) >= 1 else "NICHT gescheitert",
		int(Game.stats.get("quests_failed", 0))])
	# Aufgeben
	await _wait(func(): return not offers.is_empty(), 30.0)
	accept(0)
	var txt := text_of(active)
	abandon()
	print("Auftragstest: aufgegeben '%s': laufend leer=%s, aufgegeben=%d, naechste in %.2f Tagen" % [txt, active.is_empty(), int(qstats.get("abandoned", 0)), next - Game.time_days])
	# Andere Auftraege
	await _wait(func(): return not offers.is_empty(), 30.0)
	var a0 := offers.map(func(q): return text_of(q))
	var e1 := reroll()
	var a1 := offers.map(func(q): return text_of(q))
	print("Auftragstest: Andere Auftraege '%s': vorher %s, nachher %s, gleich wieder: '%s'" % [e1, a0, a1, reroll()])
	# Winter-Auftrag: geschafft (kein Hungertod bis zur Frist), dann gescheitert (Hungertod)
	offers = []
	var wq := _quest("winter", {"type": "starved", "n": 0, "base": int(Game.stats.get("starved", 0))}, {"survive": true, "w": 2})
	wq.reward = make_reward("research", wq, context())
	offers = [wq]
	wq.until = Game.time_days + 0.12
	accept(0)
	await _wait(func(): return active.is_empty(), 10.0)
	print("Auftragstest: Winter ohne Hungertod: %s (erledigt %d)" % [last.get("ok", false), int(qstats.get("done", 0))])
	wq = wq.duplicate(true)
	wq.until = Game.time_days + 0.5
	offers = [wq]
	accept(0)
	Game.stats["starved"] = int(Game.stats.get("starved", 0)) + 1  # Testhilfe: ein Hungertod
	await _wait(func(): return active.is_empty(), 10.0)
	print("Auftragstest: Winter mit Hungertod: geschafft=%s nach %.2f Tagen (gescheitert %d)" % [last.get("ok", true), 0.5 - (float(wq.until) - Game.time_days), int(qstats.get("failed", 0))])
	Game.stats["starved"] = int(Game.stats.get("starved", 0)) - 1
	# Ablauf der Angebote
	next = Game.time_days
	await _wait(func(): return not offers.is_empty(), 10.0)
	offers_until = Game.time_days + 0.05
	await _wait(func(): return offers.is_empty(), 10.0)
	print("Auftragstest: Angebote abgelaufen: leer=%s, neue in %.2f Tagen" % [offers.is_empty(), next - Game.time_days])
	print("Auftragstest fertig: %s, stats quests=%d failed=%d, Segen %s, Bauplaene %s, Wertung %d" % [qstats, int(Game.stats.get("quests", 0)),
		int(Game.stats.get("quests_failed", 0)), boons, plans, Exams.score()])


## Testhilfe: die Bedingung eines Auftrags herstellen.
func _fulfil(q: Dictionary, w, main) -> void:
	var c: Dictionary = q.get("check", {})
	var n := int(c.get("n", 1))
	var what := str(c.get("what", ""))
	match str(c.get("type", "")):
		"stock":
			w.stock[what] = Game.amount(what, w) + maxi(0, n - Game.amount_all(what))
		"stock_at":
			var dw = Sea.worlds.get(int(c.island))
			dw.stock[what] = maxi(Game.amount(what, dw), n)
		"building":
			for i in maxi(1, n - _building_count(what, false)):
				print("   platziert ", what, " ", main._place_on(w, what))
			Game.refresh_effects()
		"housing":
			while int(GoalChecks.progress(c)[0]) < n:
				if not main._place_on(w, "huette"):
					break
		"pop":
			while Game.population() + Sea.people_at_sea() < n:
				if w.spawn_newcomer("f" if Game.population() % 2 == 0 else "m", {"hunger": 90.0}) == null:
					break
		"tech":
			if not what in Game.research.done:
				Game.research.done.append(what)
			if Game.research.current == what:
				Game.research.current = ""
			Game._recompute_effects()
			Game.research_changed.emit()
		"kills", "births":
			Game.stats[c.type] = int(Game.stats.get(c.type, 0)) + n
		"variety":
			for id in ["beeren", "fisch", "weizen", "aepfel", "pilze", "kokos", "eier"].slice(0, n):
				w.stock[id] = maxi(Game.amount(id, w), 10)
		_:
			print("   kann im Test nicht hergestellt werden: ", c)
	Game.stock_changed.emit()
