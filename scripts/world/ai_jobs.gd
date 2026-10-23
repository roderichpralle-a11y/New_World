class_name AiJobs
## KI-Steuerung (Zeitalter Zukunft): Steht ein KI-Zentrum, verteilt die KI freie
## Siedler auf die Berufe, die auf ihrer Insel gerade am meisten fehlen. Bei
## Hungersnot holt sie zusätzlich einen Arbeiter aus einem anderen Beruf zur Nahrung.
## Einmal je Viertel-Tag und Insel, höchstens ein Wechsel pro Runde. Steuert auf der Insel der Verwalter die
## Berufe, hält sich das KI-Zentrum heraus (Vergabestelle JobDesk, niedrigster Rang „zentrum“).

const FOOD_JOBS := ["bauer", "fischer", "sammler"]


static func tick(w) -> void:
	if Game.eff_add("ai_jobs") <= 0.0 or w == null or not JobDesk.center_allowed(w):
		return
	var adults: Array = w.settlers.filter(func(s): return s.is_adult() and JobDesk.may(s, "zentrum"))
	if adults.is_empty():
		return
	var want := _most_needed(w, adults)
	if want == "":
		return
	var free: Array = adults.filter(func(s): return s.job == "frei")
	var pick = null
	if not free.is_empty():
		pick = _best_for(free, want)
	elif want in FOOD_JOBS and Game.total_food(w) < adults.size() * 2:
		# Hungersnot: einen Arbeiter aus der Werkstatt oder Forschung abziehen
		var others: Array = adults.filter(func(s): return not s.job in FOOD_JOBS and s.job != "baumeister" and s.job != "seemann" and s.job != Admin.JOB)
		if not others.is_empty():
			pick = _best_for(others, want)
	if pick == null:
		return
	if not JobDesk.assign(pick, want, "zentrum"):
		return
	Game.notify_at(w, Loc.t("KI: %s arbeitet jetzt als %s.") % [pick.display_name, Data.jobs[want].name], "ki")


## Welcher Beruf fehlt auf der Insel am meisten?
static func _most_needed(w, adults: Array) -> String:
	var count := {}
	for s in adults:
		count[s.job] = int(count.get(s.job, 0)) + 1
	var pop: int = w.settlers.size()
	# 1. Nahrung: unter 6 je Siedler wird es knapp
	if Game.total_food(w) < pop * 6:
		var has_fields: bool = w.buildings.any(func(b): return b.complete and b.def.has("farm"))
		if has_fields and int(count.get("bauer", 0)) < 1 + w.buildings.filter(func(b): return b.def.has("farm")).size() / 4:
			return "bauer"
		return "fischer" if int(count.get("fischer", 0)) <= int(count.get("sammler", 0)) else "sammler"
	# 2. Baustellen ohne Baumeister
	if not w.construction_sites().is_empty() and int(count.get("baumeister", 0)) < 1 + w.construction_sites().size() / 3:
		return "baumeister"
	# 3. Werkstätten, die arbeiten könnten, aber niemand ist da
	for kind in ["kueche", "handwerk", "stein", "stall"]:
		for b in w.buildings:
			if b.complete and b.prod_def().get("job", "") == kind and b.free_slots() > 0 and b.prod_blocker() == "":
				if b.occupants.is_empty() and w.pool_allows(b):  # nur, wenn eine Fachkraft dieser Stufe frei ist
					return {"kueche": "koch", "handwerk": "handwerker", "stein": "steinmetz", "stall": "bauer"}[kind]
	# 4. Rohstoffe für Bauten
	if Game.amount("holz", w) < 30:
		return "holzfaeller"
	if Game.amount("stein", w) < 20:
		return "steinmetz"
	# 5. Freie Forschungsplätze
	if Game.research.current != "" and Sea.is_main(w):  # Forschung nur auf der Hauptinsel
		for b in w.buildings:
			if b.complete and b.def.has("research") and b.free_slots() > 0 and w.pool_allows(b):
				return "forscher"
	return ""


## Wer kann den Beruf am besten (höchste passende Fähigkeit)?
static func _best_for(cands: Array, job: String):
	var sk: String = Data.jobs.get(job, {}).get("skill", "")
	var best = null
	var best_v := -INF
	for s in cands:
		var v: float = s.skill_factor(sk) if sk != "" else 0.0  # Stufe und Talent
		if v > best_v:
			best_v = v
			best = s
	return best
