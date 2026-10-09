class_name SettlerMind
extends RefCounted
## Charakter eines Siedlers: Eigenschaften (Klugheit, Gesundheit, Fleiss, Gemuet),
## Begabungen je Faehigkeit, Vitamine, Speiseplan, Krankheiten, Laune, Erholung
## und daraus die Arbeitskraft. Alle Zahlen stehen in data/people.json.

const TRAITS := ["iq", "konst", "fleiss", "gemuet"]

var s  # der Siedler
var traits: Dictionary = {}   # 1..10
var talents: Dictionary = {}  # Faehigkeit -> Begabung (0.5..1.8, 1 = normal)
var vit: float = 70.0
var meals: Array = []         # zuletzt gegessene Sorten
var mood: float = 60.0
var rest: float = 100.0       # Erholung 0..100
var sick: String = ""         # Krankheit (Schluessel in illnesses) oder ""
var sick_left: float = 0.0    # verbleibende Krankheitstage
var vit_low_days: float = 0.0
var grief: Array = []         # [Name, bis Tag]
var joy_until: float = 0.0
var reasons: Array = []       # [Text, Wert] fuer die Anzeige
var _rng := RandomNumberGenerator.new()
var _check_t: float = 0.0


func _init(p_settler, data: Dictionary) -> void:
	s = p_settler
	_rng.randomize()
	var m: Dictionary = data.get("mind", {})
	if m.is_empty():
		# Alter Spielstand oder neuer Siedler ohne Vorgaben: Eigenschaften auswuerfeln,
		# fuer alte Spielstaende reproduzierbar aus der Siedler-ID
		var r := RandomNumberGenerator.new()
		r.seed = hash(int(data.get("id", 0)) * 7919 + 17)
		m = SettlerMind.roll(r, data.get("traits", {}), data.get("talents", {}))
	traits = m.get("traits", {})
	for t in TRAITS:
		traits[t] = clampf(float(traits.get(t, 5.5)), 1.0, 10.0)
	talents = m.get("talents", {})
	for sk in Data.skills:
		talents[sk] = clampf(float(talents.get(sk, 1.0)), float(Data.ppl("talent_min")), float(Data.ppl("talent_max")))
	vit = float(m.get("vit", Data.ppl("vit_start", 70.0)))
	meals = m.get("meals", [])
	mood = float(m.get("mood", 60.0))
	rest = float(m.get("rest", 100.0))
	sick = String(m.get("sick", ""))
	if sick != "" and not Data.ppl("illnesses", {}).has(sick):
		sick = ""
	sick_left = float(m.get("sick_left", 0.0))
	vit_low_days = float(m.get("vit_low", 0.0))
	grief = m.get("grief", [])
	joy_until = float(m.get("joy", 0.0))


func serialize() -> Dictionary:
	var t := {}
	for k in traits:
		t[k] = snappedf(traits[k], 0.1)
	var tal := {}
	for k in talents:
		tal[k] = snappedf(talents[k], 0.01)
	return {"traits": t, "talents": tal, "vit": snappedf(vit, 0.1), "meals": meals, "mood": snappedf(mood, 0.1),
		"rest": snappedf(rest, 0.1), "sick": sick, "sick_left": snappedf(sick_left, 0.01),
		"vit_low": snappedf(vit_low_days, 0.01), "grief": grief, "joy": joy_until}


# ================================================================== Eigenschaften
## Zufaellige Eigenschaften; fehlende Werte in fixed/fixed_tal werden gewuerfelt.
static func roll(r: RandomNumberGenerator, fixed: Dictionary = {}, fixed_tal: Dictionary = {}) -> Dictionary:
	var t := {}
	for k in TRAITS:
		# Dreiecksverteilung: die meisten sind mittelmaessig, wenige sehr gut oder schlecht
		t[k] = float(fixed[k]) if fixed.has(k) else clampf(roundf((r.randf_range(1, 10) + r.randf_range(1, 10)) * 5.0) / 10.0, 1.0, 10.0)
	var tal := {}
	for sk in Data.skills:
		tal[sk] = float(fixed_tal[sk]) if fixed_tal.has(sk) else _rand_talent(r)
	if fixed_tal.is_empty():
		# Jeder hat mindestens eine echte Begabung
		var best: String = Data.skills.keys()[r.randi() % Data.skills.size()]
		tal[best] = maxf(tal[best], r.randf_range(1.35, float(Data.ppl("talent_max"))))
	return {"traits": t, "talents": tal}


static func _rand_talent(r: RandomNumberGenerator) -> float:
	return clampf(0.8 + r.randf() * r.randf() * 0.9 - r.randf() * 0.25, float(Data.ppl("talent_min")), float(Data.ppl("talent_max")))


## Kind: Eigenschaften und Begabungen teils von den Eltern geerbt.
static func inherit(r: RandomNumberGenerator, ma: SettlerMind, pa: SettlerMind) -> Dictionary:
	var base := roll(r)
	var w := float(Data.ppl("trait_inherit", 0.6))
	var noise := float(Data.ppl("trait_noise", 2.0))
	for k in TRAITS:
		var avg: float = (ma.traits[k] + pa.traits[k]) / 2.0
		base.traits[k] = clampf(roundf((lerpf(base.traits[k], avg, w) + r.randf_range(-noise, noise) * 0.5) * 10.0) / 10.0, 1.0, 10.0)
	var tn := float(Data.ppl("talent_noise", 0.3))
	for sk in Data.skills:
		var avg2: float = (ma.talents[sk] + pa.talents[sk]) / 2.0
		base.talents[sk] = clampf(lerpf(base.talents[sk], avg2, w) + r.randf_range(-tn, tn),
			float(Data.ppl("talent_min")), float(Data.ppl("talent_max")))
	return base


func trait_value(k: String) -> float:
	return float(traits.get(k, 5.5))


## Kurzbeschreibung, z. B. "klug, kränklich, Frohnatur".
func character_text() -> String:
	var parts := []
	var defs: Dictionary = Data.ppl("traits", {})
	for k in TRAITS:
		var v := trait_value(k)
		if v >= 7.5:
			parts.append(defs[k].high)
		elif v <= 3.5:
			parts.append(defs[k].low)
	return ", ".join(parts) if not parts.is_empty() else tr("durchschnittlich")


## Faehigkeiten mit Begabung ab 1.3, beste zuerst.
func best_talents() -> Array:
	var ks := talents.keys().filter(func(k): return talents[k] >= 1.3)
	ks.sort_custom(func(a, b): return talents[a] > talents[b])
	return ks


## Lerntempo fuer eine Faehigkeit: Begabung mal Klugheit.
func learn_factor(sk: String) -> float:
	return float(talents.get(sk, 1.0)) * (0.6 + 0.08 * trait_value("iq"))


## Forschungstempo: Kluge forschen schneller.
func research_factor() -> float:
	return 0.7 + 0.06 * trait_value("iq")


## 0 = robust, 1 = sehr kraenklich.
func frailty() -> float:
	return (10.0 - trait_value("konst")) / 9.0


# ================================================================== Entwicklung der Siedlung
## Lebensstil der Siedlung 0..1: steigt mit dem Fortschritt (Zahl der Forschungen).
static func comfort() -> float:
	var a := float(Data.ppl("comfort_techs_start", 2))
	var b := float(Data.ppl("comfort_techs_full", 22))
	return clampf((float(Game.research.get("done", []).size()) - a) / maxf(1.0, b - a), 0.0, 1.0)


## [Name, Beschreibung] der aktuellen Lebensstil-Stufe.
static func comfort_stage() -> Array:
	var c := comfort()
	var cur: Array = ["", ""]
	for st in Data.ppl("comfort_stages", []):
		if c >= float(st[0]):
			cur = [st[1], st[2]]
	return cur


## Anteil des Tages, den der Siedler gern frei haette.
func leisure_share() -> float:
	var f := 1.25 - 0.05 * trait_value("fleiss")  # Fleissige brauchen weniger Pausen
	return clampf(comfort() * float(Data.ppl("leisure_share_max", 0.3)) * f, 0.0, 0.45)


# ================================================================== Essen
func vitamins_of(food: String) -> float:
	return Data.food_vitamins(food)  # einzige Quelle: resources.json


## Wird nach jeder Mahlzeit gerufen (Sorte, optional Vitamine aus dem Ernaehrungsmodell).
func on_meal(food: String, vitamins = null) -> void:
	vit = minf(100.0, vit + (float(vitamins) if vitamins != null else vitamins_of(food)))
	meals.append(food)
	while meals.size() > int(Data.ppl("diet_memory", 8)):
		meals.pop_front()
	if sick == "skorbut" and vit >= float(Data.ppl("illnesses").skorbut.get("until_vit", 45)):
		_recover()


func diet_variety() -> int:
	var seen := {}
	for m in meals:
		seen[m] = true
	return seen.size()


# ================================================================== Simulation
## Laeuft jede Frame mit der vergangenen Zeit in Tagen.
func tick(days: float) -> void:
	var child: bool = not s.is_adult()
	vit = maxf(0.0, vit - float(Data.ppl("vit_per_day", 40.0)) * days * (0.6 if child else 1.0))
	if vit < float(Data.ppl("vit_scurvy", 12.0)):
		vit_low_days += days
	else:
		vit_low_days = maxf(0.0, vit_low_days - days * 2.0)
	# Krankheit
	if sick != "":
		var ill: Dictionary = Data.ppl("illnesses")[sick]
		s.health -= float(ill.damage) * days * lerpf(0.7, 1.3, frailty())
		var speed := Game.eff("heal") * lerpf(1.3, 0.75, frailty())
		if s.sleeping:
			speed *= float(Data.ppl("rest_heal_bonus", 1.5))
		if s.hunger < 30.0:
			speed *= 0.6
		sick_left -= days * speed
		if sick_left <= 0.0 and sick != "skorbut":
			_recover()
	# Erholung: Arbeit zehrt, Schlaf und Pausen erholen
	if s.sleeping:
		rest = minf(100.0, rest + 60.0 * days)
	elif not child and not s.on_break():
		var share := leisure_share()
		if share > 0.0:
			rest = maxf(0.0, rest - 600.0 * share / (1.0 - share) * days)
	elif child:
		rest = 100.0
	# Seltener: Ansteckung pruefen und Laune nachfuehren
	_check_t -= days
	if _check_t <= 0.0:
		_check_t += 0.02
		_maybe_get_sick(0.02)
		_update_mood(0.02)


## Erholung waehrend einer Pause (Rate je Tag).
func relax(days: float) -> void:
	rest = minf(100.0, rest + 600.0 * days)


## Pause machen? In einer Hungersnot arbeiten alle durch.
func wants_break() -> bool:
	if not s.is_adult() or leisure_share() <= 0.0 or rest >= 35.0:
		return false
	return Game.total_food(s.world) >= s.world.settlers.size() * 3


func break_length() -> float:
	return _rng.randf_range(float(Data.ppl("leisure_break_min", 8.0)), float(Data.ppl("leisure_break_max", 16.0)))


func _maybe_get_sick(days: float) -> void:
	if sick != "":
		return
	if vit_low_days > 1.5:
		_fall_ill("skorbut")
		return
	var risk := float(Data.ppl("sick_base_per_day", 0.07)) * lerpf(0.4, 1.8, frailty())
	if not s.is_adult():
		risk *= float(Data.ppl("sick_child", 1.3))
	elif s.age > s.max_age * 0.8:
		risk *= float(Data.ppl("sick_old", 1.8))
	if s.hunger < 30.0:
		risk *= float(Data.ppl("sick_hungry", 1.8))
	if vit < float(Data.ppl("vit_low", 30.0)):
		risk *= float(Data.ppl("sick_vit_low", 2.0))
	if s.home_id == 0:
		risk *= float(Data.ppl("sick_outside", 1.4))
	risk *= Seasons.season_mod("sickness")
	# Kein Heizholz in Herbst und Winter: frierende Siedler werden schneller krank
	if not Seasons.is_warm(s.world):
		risk *= float(Data.ppl("sick_cold", 1.8))
	risk /= sqrt(Game.eff("heal"))
	# Ansteckung: Kranke im selben Haus oder ganz in der Naehe
	var near := 0
	for o in s.world.settlers:
		if o != s and o.mind.sick != "" and Data.ppl("illnesses")[o.mind.sick].get("contagious", false):
			if (o.home_id != 0 and o.home_id == s.home_id) or o.cell.distance_to(s.cell) < 3.0:
				near += 1
	risk *= 1.0 + float(Data.ppl("sick_contagion", 0.6)) * near
	if _rng.randf() < risk * days:
		_fall_ill(_pick_illness())


func _pick_illness() -> String:
	var ills: Dictionary = Data.ppl("illnesses")
	# Gewichte einmal bestimmen; das Klima verschiebt sie (heißer Sommer: mehr Ruhr, "ill_<id>")
	var wts := {}
	var total := 0.0
	for k in ills:
		wts[k] = float(ills[k].get("weight", 0)) * Seasons.climate_factor("ill_" + k)
		total += wts[k]
	var x := _rng.randf() * total
	for k in ills:
		x -= wts[k]
		if x <= 0.0 and wts[k] > 0.0:
			return k
	return "erkaeltung"


func _fall_ill(k: String) -> void:
	var ill: Dictionary = Data.ppl("illnesses")[k]
	sick = k
	sick_left = float(ill.days) * _rng.randf_range(0.8, 1.2)
	s.abort_plan()
	# Leichte Krankheiten nur in Liste und Infofenster, schwere als Meldung
	if ill.get("bed", false) or ill.has("deadly"):
		var hint := tr(" Es fehlen Vitamine: Beeren, Äpfel oder Kokosnüsse helfen.") if k == "skorbut" else ""
		Game.notify_at(s.world, tr("%s ist krank: %s.%s") % [s.display_name, ill.name, hint], "herz", "gesundheit")


func _recover() -> void:
	if sick == "":
		return
	var ill: Dictionary = Data.ppl("illnesses")[sick]
	var name: String = ill.name
	sick = ""
	sick_left = 0.0
	if (ill.get("bed", false) or ill.has("deadly")) and s.world and s.world.settlers.has(s):
		Game.notify_at(s.world, tr("%s ist wieder gesund (%s überstanden).") % [s.display_name, name], "herz", "gesundheit")


func illness_name() -> String:
	return Data.ppl("illnesses")[sick].name if sick != "" else ""


## Todesursache, falls die Gesundheit durch eine Krankheit auf 0 faellt.
func death_reason() -> String:
	if sick != "":
		return String(Data.ppl("illnesses")[sick].get("deadly", tr("an einer Krankheit gestorben")))
	return ""


func needs_bed() -> bool:
	return sick != "" and bool(Data.ppl("illnesses")[sick].get("bed", false))


# ================================================================== Laune
## Familie oder Partner (gemeinsames Kind)?
static func is_close(a: int, b: int) -> bool:
	if Game.related(a, b):
		return true
	for kid in Game.lineage:
		var ps: Array = Game.lineage[kid]
		if a in ps and b in ps:
			return true
	return false


func on_relative_died(name: String, close: bool) -> void:
	grief.append([name, Game.time_days + float(Data.ppl("grief_days", 2.5)) * (1.0 if close else 0.4), close])


func on_child_born() -> void:
	joy_until = Game.time_days + float(Data.ppl("joy_days", 1.5))


func _update_mood(days: float) -> void:
	var c := comfort()
	var r := []
	var base := 55.0 + (trait_value("gemuet") - 5.5) * 3.0
	# Essen: Menge
	if s.hunger <= 0.0:
		r.append([tr("Hungert"), -30.0])
	elif s.hunger < 35.0:
		r.append([tr("Hat Hunger"), -12.0])
	elif s.hunger >= 70.0:
		r.append([tr("Ist satt"), 6.0])
	# Essen: Abwechslung (wird mit dem Wohlstand wichtiger)
	if meals.size() >= 3:
		var v := diet_variety()
		var val := clampf((v - 2) * 4.0, -8.0, 10.0) * (0.5 + c)
		if v <= 1:
			r.append([tr("Immer dasselbe Essen"), val])
		elif v >= 4:
			r.append([tr("Abwechslungsreiches Essen"), val])
	if vit < float(Data.ppl("vit_low", 30.0)):
		r.append([tr("Zu wenig Vitamine"), -10.0])
	# Gesundheit
	if sick != "":
		r.append([tr("Ist krank (%s)") % illness_name(), -20.0 if needs_bed() else -12.0])
	elif s.health < 50.0:
		r.append([tr("Fühlt sich schwach"), -8.0])
	# Wohnen
	var home = s.world.building_by_id(s.home_id) if s.home_id != 0 else null
	if home == null:
		r.append([tr("Hat kein Zuhause"), -(4.0 + 14.0 * c)])
	else:
		var hb := float(home.def.get("birth_bonus", 1.0)) - 1.0
		if hb > 0.0 and HouseNeeds.full_level(home):  # nur wie der Kinder-Bonus
			r.append([tr("Wohnt schön (%s)") % home.def.name, hb * 15.0 * (0.5 + c)])
		var need: Array = HouseNeeds.mood_reason(home, c)  # Bedürfnisstufen (nur gemerkte Werte)
		if not need.is_empty():
			r.append(need)
	# Freizeit
	if leisure_share() > 0.0:
		if rest < 25.0:
			r.append([tr("Ist überarbeitet"), -(8.0 + 10.0 * c)])
		elif rest > 70.0 and c > 0.1:
			r.append([tr("Ist erholt"), 4.0])
	# Trauer und Freude
	var keep := []
	for g in grief:
		if Game.time_days < float(g[1]):
			keep.append(g)
	grief = keep
	if not grief.is_empty():
		var g: Array = grief[-1]
		var full := float(Data.ppl("grief_mood", 30.0)) * (1.0 if g.size() < 3 or g[2] else 0.3)
		r.append([tr("Trauert um %s") % g[0], -full])
	if Game.time_days < joy_until:
		r.append([tr("Freut sich über das Baby"), float(Data.ppl("joy_mood", 12.0))])
	var sm := Seasons.season_mod("mood") - 1.0
	if absf(sm) > 0.01:
		r.append([(tr("Freut sich über: %s") if sm > 0.0 else tr("Leidet unter: %s")) % Seasons.season_title(), sm * 60.0])
	if not Seasons.is_warm(s.world):
		r.append([tr("Friert (kein Heizholz)"), -15.0])
	var target := base
	for x in r:
		target += float(x[1])
	target = clampf(target, 0.0, 100.0)
	mood = lerpf(mood, target, clampf(float(Data.ppl("mood_rate_per_day", 1.6)) * days, 0.0, 1.0))
	reasons = r


func mood_text() -> String:
	if mood >= 80.0:
		return tr("glücklich")
	if mood >= 60.0:
		return tr("zufrieden")
	if mood >= 40.0:
		return tr("geht so")
	if mood >= 20.0:
		return tr("unzufrieden")
	return tr("verzweifelt")


func birth_factor() -> float:
	return lerpf(float(Data.ppl("mood_birth_min", 0.4)), float(Data.ppl("mood_birth_max", 1.3)), mood / 100.0)


# ================================================================== Arbeitskraft
## Faktor auf jedes Arbeitstempo: Gesundheit, Hunger, Laune, Krankheit, Alter und Fleiss.
func work_power() -> float:
	var f := 0.55 + 0.45 * clampf(s.health / 60.0, 0.0, 1.0)
	if s.hunger <= 0.0:
		f *= float(Data.ppl("work_starving", 0.5))
	elif s.hunger < 30.0:
		f *= lerpf(float(Data.ppl("work_hungry", 0.75)), 1.0, s.hunger / 30.0)
	f *= lerpf(float(Data.ppl("mood_work_min", 0.75)), float(Data.ppl("mood_work_max", 1.12)), mood / 100.0)
	if sick != "":
		f *= maxf(0.3, float(Data.ppl("illnesses")[sick].get("work", 1.0)))
	if vit < float(Data.ppl("vit_low", 30.0)):
		f *= 0.92
	if s.age > s.max_age * 0.8:
		f *= float(Data.ppl("work_old", 0.8))
	f *= 0.9 + 0.022 * trait_value("fleiss")
	return f
