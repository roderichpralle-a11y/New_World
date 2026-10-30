class_name StaffPlan
extends RefCounted
## Stellenplan des Verwalters (josh 2026-10-30, Versuch mit 100 Siedlern, StewardLab): Wie viele Leute braucht
## jeder Beruf gerade? Aus Bedarf (Essen und Wärme für 3 Tage, Zielvorräte, Forschung, Häuser) und Kapazität
## (Werkstattplätze, Felder, Fischgründe, Sträucher, Bäume, Tiere). Der Verwalter füllt Lücken (Steward.tick) und
## stellt Leute ohne Bedarf auf frei, damit der Spieler sie einsetzen kann.
##
## targets(w) -> {Beruf: {n, why, power, hard}}; hard = Essen und Wärme (darf Spieler-Eingeteilte nehmen).

const CYCLES := 96.0          # Arbeitsgänge je Platz und Tag etwa = CYCLES / Arbeitszeit (wie PlanReport)
const STOCK_DAYS := 4.0       # Zwischenwaren: so viele Tage Verbrauch der Werkstätten auf Vorrat
const BASE_KEEP := 30         # jede Ware: so viel darf mindestens im Lager liegen, bevor die Werkstatt ruht
const FOOD_DAYS := 6.0        # Zubereitetes Essen (Brot, Räucherfisch …): Vorrat für so viele Tage
const FISH_PER_GROUND := 1.0  # Fischer je Fischgrund
const BUSH_PER_GATHERER := 4  # Sträucher (die gerade wachsen) je Sammler
const TREES_PER_CUTTER := 6   # reife Bäume je Holzfäller
const ANIMALS_PER_HUNTER := 4


## Zielvorrat je Ware: was Werkstätten, Häuser, Forschung, Baustellen und Mindestvorräte in den nächsten Tagen
## brauchen. Liegt mehr da, ruht die Werkstatt dieser Ware (ihre Leute werden frei).
static func stock_targets(w) -> Dictionary:
	var want := {}
	var put := func(g: String, n: float):
		if n > float(want.get(g, 0.0)):
			want[g] = n
	var adults := float(Steward._adults(w).size())
	var iid := int(w.island_id)
	# Mindestvorräte des Spielers
	if Powers.on("mindestvorrat"):
		for g in Steward.minmax.get(str(iid), {}):
			put.call(str(g), float(Steward.minmax[str(iid)][g][0]))
	# Häuser: Waren je Tag mal Verbraucher, für STOCK_DAYS Tage
	var st: Dictionary = HouseNeeds.state.get(iid, {})
	var cons: Array = st.get("_cons", [])
	for k in range(2, cons.size()):
		if float(cons[k]) <= 0.0:
			continue
		for nd in HouseNeeds.level_needs(k):
			if str(nd.get("kind", "")) == "good":
				put.call(str(nd.good), float(nd.get("rate", 0.0)) * float(cons[k]) * STOCK_DAYS + 5.0)
			elif str(nd.get("kind", "")) == "stock":
				for g in nd.get("goods", []):
					put.call(str(g), float(nd.get("per", 0.5)) * float(cons[k]))
	# Forschung: Schriften für den Rest, Kosten der nächsten Forschung
	if Sea.is_main(w):
		var cur: String = Game.research.current
		if cur != "":
			var left := Writing.left_for(cur)
			for g in left:
				put.call(str(g), minf(float(left[g]), 20.0) + 5.0)
		else:
			for t in Planner.tech_order().slice(0, 2):
				var cost: Dictionary = Data.techs[t].get("cost", {})
				for g in cost:
					put.call(str(g), float(cost[g]))
	# Baustellen: was noch fehlt
	for b in w.buildings:
		if b.complete:
			continue
		for g in b.def.get("cost", {}):
			put.call(str(g), float(int(b.def.cost[g]) - int(b.delivered.get(g, 0))))
	# Zubereitetes Essen: für FOOD_DAYS Tage (je Sorte ein Anteil)
	var per_day := Steward.food_per_day(w)
	for g in ["brot", "raeucherfisch", "eier", "milch", "fleisch", "konserven", "mehl"]:
		if Data.resources.has(g):
			put.call(g, per_day * (FOOD_DAYS + winter_days()) / 4.0 / maxf(1.0, Data.food_satiety(g)) if Data.food_ids().has(g) else per_day / 84.0 * 3.0)
	# Werkstätten brauchen ihre Zutaten: dreimal von hinten nach vorne durchreichen
	for _pass in 3:
		for b in w.buildings:
			if not _active(w, b, want):
				continue
			var p: Dictionary = b.prod_def()
			var cyc := CYCLES / maxf(1.0, float(p.get("time", 10.0))) * float(b.slots())
			for g in p.get("inputs", {}):
				put.call(str(g), float(p.inputs[g]) * cyc * STOCK_DAYS * 0.5)
	for g in want:
		want[g] = maxf(float(want[g]), float(BASE_KEEP))
	return want


## Werkstatt soll arbeiten: fertig, nicht angehalten, keine Werft, eine Ware unter dem Zielvorrat und Platz im Lager.
static func _active(w, b, want: Dictionary) -> bool:
	if not (b.complete and b.def.has("production")) or b.paused or b.def.get("ships", false) or b.def.has("farm"):
		return false
	for g in b.prod_def().get("outputs", {}):
		if Game.amount(g, w) < float(want.get(g, BASE_KEEP)) and Game.space_for(g, w) > 0:
			return true
	return false


## Hat die Werkstatt Zutaten für einen Arbeitsgang?
static func _has_inputs(w, b) -> bool:
	var p: Dictionary = b.prod_def()
	for g in p.get("inputs", {}):
		if Game.amount(g, w) < int(p.inputs[g]):
			return false
	return true


## Tage, für die vor dem Winter zusätzlich Essen ins Lager soll: im Sommer und Herbst der ganze Winter, im Winter
## der Rest davon. Im Frühling nichts.
static func winter_days() -> float:
	var sd := Seasons.season_days()
	match Seasons.season():
		1, 2:
			return sd
		3:
			return sd - fposmod(Game.time_days, sd)
	return 0.0


## Wie viele Leute in einem Rohstoffberuf wirklich Arbeit finden: haben die jetzigen viel Leerlauf, nur so viele,
## wie gerade arbeiten, plus einer. So stellt der Verwalter niemanden ein, den er gleich wieder freistellt.
static func _useful(w, job: String, cap: int) -> int:
	var have := Steward._count(w, job)
	if have < 2 or cap <= 0:
		return cap
	var busy := Steward._busy_workers(w, [job])
	if busy / float(have) >= 1.0 - Steward.RELEASE_IDLE / 100.0:
		return cap
	return mini(cap, ceili(busy * 1.25) + 1)


## Fehlende Zutaten werden auf der Insel gerade hergestellt (Werkstatt, Feld oder Rohstoffberuf)? Dann bleibt die
## Werkstatt besetzt: Zwischenwaren wie Mehl oder Kohle liegen selten auf Vorrat, weil sie sofort weiterverarbeitet werden.
static func _fed(w, b) -> bool:
	var p: Dictionary = b.prod_def()
	for g in p.get("inputs", {}):
		if Game.amount(g, w) >= int(p.inputs[g]):
			continue
		var made := Steward.RAW_JOB.has(str(g)) and Steward._count(w, Steward.RAW_JOB[str(g)]) > 0
		for o in w.buildings:
			if made:
				break
			if o == b or not o.complete or o.paused:
				continue
			if o.def.has("farm"):
				made = str(g) == str(o.def.farm.get("yield", ""))
			elif o.def.has("production") and o.prod_def().get("outputs", {}).has(g):
				made = _has_inputs(w, o)
		if not made:
			return false
	return true


## Liegt eine Ware unter dem Mindestvorrat des Spielers, gilt dessen Befugnis „Mindestvorräte halten“.
static func _min_power(w, goods: Array, other: String) -> String:
	if not Powers.on("mindestvorrat"):
		return other
	var mm: Dictionary = Steward.minmax.get(str(int(w.island_id)), {})
	for g in goods:
		if mm.has(str(g)) and Game.amount(str(g), w) < int(mm[str(g)][0]):
			return "mindestvorrat"
	return other


## Soll je Beruf.
static func targets(w) -> Dictionary:
	var out := {}
	var add := func(job: String, n: int, why: String, power: String, hard := false):
		if n <= 0 or not Data.jobs.has(job) or not Data.job_unlocked(job):
			return
		if not out.has(job):
			out[job] = {"n": 0, "why": why, "power": power, "hard": hard}
		out[job].n += n
		if hard:
			out[job].hard = true
			out[job].power = power
			out[job].why = why
	var adults: Array = Steward._adults(w)
	var want := stock_targets(w)
	var info := Steward.secure_info(w)
	var g_on := Powers.on("grundbesetzung")
	var ew_on := Powers.on("essen_waerme")
	# Werkstätten: aktiv und Zutaten da -> alle Plätze; fehlen Zutaten, erst die Kette davor (trace)
	var used_slots := {}
	for b in w.buildings:
		if not _active(w, b, want) or not w.pool_allows(b):
			continue
		var kind: String = b.prod_def().get("job", "")
		var job: String = Steward.KIND_JOB.get(kind, "")
		if job == "":
			continue
		if _has_inputs(w, b) or _fed(w, b):
			var food := false
			for g in b.prod_def().get("outputs", {}):
				food = food or Data.food_ids().has(str(g))
			add.call(job, b.slots(), Loc.t("%s arbeitet") % b.def.name, "essen_waerme" if food and ew_on else _min_power(w, b.prod_def().get("outputs", {}).keys(), "grundbesetzung"),
				food and ew_on and float(info.food[1]) < Steward.food_per_day(w) * (Steward.PLAN_DAYS + winter_days()))
			used_slots[kind] = int(used_slots.get(kind, 0)) + b.slots()
	# Essen: Rohnahrung so viele Leute, dass Vorrat plus Ertrag 3 Tage reichen; verteilt nach Kapazität
	var fields: int = w.buildings.filter(func(b): return b.complete and b.def.has("farm")).size()
	var farm_cap := ceili(float(fields) / Steward.FIELDS_PER_FARMER) if Steward._raw_block(w, "bauer") == "" else 0
	var fish_cap := 0
	var bush_cap := 0
	var hunt_cap := 0
	if Steward._raw_block(w, "fischer") == "":
		fish_cap = ceili(float(w.nodes.filter(func(n): return n.type == "fischgrund").size()) * FISH_PER_GROUND)
	if Steward._raw_block(w, "sammler") == "":
		var grow := 0
		for n in w.nodes:
			if str(n.type) in Steward.RAW_NODES.sammler and Seasons.growth(str(n.type), w) > 0.0:
				grow += 1
		bush_cap = ceili(float(grow) / BUSH_PER_GATHERER)
	if Steward._raw_block(w, "jaeger") == "":
		hunt_cap = w.animals.filter(func(a): return is_instance_valid(a) and not a.dead and a.is_adult()).size() / ANIMALS_PER_HUNTER
	# Rohnahrung (josh 2026-10-30, Lauf mit 100 Siedlern): nicht aus einer geschätzten Rate (die schwankt stark), sondern
	# nach dem Zielvorrat. Liegt weniger als Bedarf für 3 Tage plus Wintervorrat im Lager, arbeiten alle Plätze,
	# an denen gerade etwas wächst; liegt deutlich mehr da, nur so viele, wie der Verbrauch braucht.
	var fpd := Steward.food_per_day(w)
	var food_want := fpd * (Steward.PLAN_DAYS + winter_days())
	var food_have := float(info.food[1])
	var share := 1.0
	if food_have >= food_want * 1.3:
		share = clampf(fpd / maxf(1.0, Steward.food_rate(w)) / maxf(1.0, float(farm_cap + fish_cap + bush_cap + hunt_cap)), 0.25, 1.0)
	var hard_food := ew_on and food_have < food_want
	var raw_n := 0
	for e in [["bauer", farm_cap], ["fischer", fish_cap], ["sammler", bush_cap], ["jaeger", hunt_cap]]:
		var cap := _useful(w, e[0], int(e[1]))
		var n := ceili(float(cap) * share) if cap > 0 else 0
		if e[0] == "bauer":
			n = int(e[1])  # Felder brauchen ihre Bauern zur Ernte, auch wenn sie dazwischen warten
		if n <= 0 or not (g_on or ew_on):
			continue
		raw_n += n
		var why := Loc.t("%d Felder") % fields if e[0] == "bauer" else Loc.t("Essen für %d Tage") % roundi(Steward.PLAN_DAYS + winter_days())
		add.call(e[0], n, why, "essen_waerme" if ew_on else "grundbesetzung", hard_food)
	# Rohes liegt im Lager, aber die Küchen schaffen es nicht (josh 2026-10-30: im Lauf mit 100 Siedlern stauten sich
	# über 1000 Weizen, während das Essen knapp wurde): dann helfen keine Bauern, sondern mehr Mühlen und Bäckereien.
	for e in [["weizen", "muehle", "baeckerei"], ["fisch", "raeucherei", ""]]:
		var kitchens: Array = w.buildings.filter(func(b): return b.complete and b.type == e[1])
		if kitchens.is_empty() or Game.amount(e[0], w) < 150 or food_have >= food_want:
			continue
		var names := [Data.buildings[e[1]].name] + ([Data.buildings[e[2]].name] if e[2] != "" else [])
		Steward._note_block(w, "kueche_" + e[0], Loc.t("%d %s liegen im Lager, aber in %s ist jeder Platz besetzt. Mehr Leute helfen nicht, baue mehr davon.") % [
			Game.amount(e[0], w), Data.resources[e[0]].name, Loc.t(" und ").join(names)])
	if ew_on and food_have < fpd * Steward.PLAN_DAYS and raw_n < int(info.food[2]):
		Steward._note_block(w, "essen", Loc.t("Essen reicht nicht: %d Leute in Nahrungsberufen wären nötig, aber Felder, Fischgründe und Sträucher geben nur Arbeit für %d. Baue Felder (je 4 ein Bauer), Räuchereien und Bäckereien.") % [int(info.food[2]), raw_n])
	# Holz: Wärme, Werkstätten, Baustellen; höchstens so viele, wie reife Bäume tragen
	var wood_day: float = float(info.fuel[0]) / Steward.PLAN_DAYS
	for b in w.buildings:
		if _active(w, b, want) and b.prod_def().get("inputs", {}).has("holz"):
			wood_day += float(b.prod_def().inputs.holz) * CYCLES / maxf(1.0, float(b.prod_def().get("time", 10.0))) * float(b.slots())
	var wood_want := maxf(float(want.get("holz", BASE_KEEP)), wood_day * STOCK_DAYS)
	var wood_have := float(Game.amount("holz", w))
	var cut := 0
	if wood_have < wood_want or float(info.fuel[3]) < float(info.fuel[2]):
		var rate := maxf(Steward.WOOD_RATE, Steward.wood_rate(w))
		cut = ceili(maxf(wood_day, (wood_want - wood_have) / 2.0) / rate)
		var ripe: int = w.nodes.filter(func(n): return n.type == "baum" and int(n.amount) > 0).size()
		cut = maxi(cut, int(info.fuel[2]))
		cut = mini(cut, maxi(1, ripe / TREES_PER_CUTTER) if Steward._raw_block(w, "holzfaeller") == "" else 0)
	add.call("holzfaeller", cut, Loc.t("Holz für Wärme und Werkstätten"), "essen_waerme" if int(info.fuel[2]) > 0 and ew_on else "grundbesetzung", int(info.fuel[2]) > 0 and ew_on)
	# Stein aus Felsen, wenn kein Steinbruch arbeitet
	if float(Game.amount("stein", w)) < float(want.get("stein", BASE_KEEP)) and int(used_slots.get("stein", 0)) == 0 and Steward._raw_block(w, "steinmetz") == "":
		add.call("steinmetz", 2, Loc.t("Stein"), _min_power(w, ["stein"], "grundbesetzung"))
	# Forschung: alle Plätze, solange geforscht wird
	if Sea.is_main(w) and Game.research.current != "":
		var slots := 0
		for b in w.buildings:
			if b.complete and b.def.has("research"):
				slots += b.slots()
		add.call("forscher", slots, Loc.t("Forschung %s") % Data.techs[Game.research.current].name, "grundbesetzung")
	# Baustellen
	var sites: Array = w.construction_sites()
	add.call("baumeister", (1 + sites.size() / 2) if not sites.is_empty() else 1, Loc.t("Baustellen"), "grundbesetzung")
	# Gefahr
	if Steward._danger_job(w) != "":
		add.call("jaeger", 1, Loc.t("Raubtiere nahe den Arbeitsplätzen"), "grundbesetzung")
	out["verwalter"] = {"n": 1, "why": "", "power": "", "hard": false}
	return out
