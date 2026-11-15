class_name DroidTest
extends RefCounted
## Selbsttest der Droiden. --droidtest=1 mit --fixture=<sea.json>: Droide bauen (übernimmt den häufigsten
## Beruf, der Siedler wird frei), Strom verbrauchen, ohne Strom Stillstand, arbeiten, Speichern und Laden.
## Druckt „Droiden OK/FEHLER“. --droidtest=shot: drei Droiden bei der Arbeit, einer ausgewählt.


static func _okf(c: bool) -> String:
	return "OK" if c else "FEHLER"


static func _wait(main, secs: float) -> void:
	await main.get_tree().create_timer(secs, true, false, true).timeout


static func run(main, mode: String) -> void:
	await _wait(main, 0.5)
	var hud = main.hud
	if hud._hint_dialog != null and is_instance_valid(hud._hint_dialog):
		hud._hint_dialog.queue_free()
		hud._hint_dialog = null
	hud._offers.clear()
	Game.set_speed(1)
	Steward.offered = true
	Steward.offered_routes = true
	Steward.offered_net = true
	Steward.offered_automat = true
	for t in ["elektrizitaet", "computer"]:
		if not Game.is_researched(t):
			Game.research.done.append(t)
	var w = Game.world
	Data.balance["base_storage"] = 4000
	w.stock["strom"] = 200
	if mode == "shot":
		for j in ["holzfaeller", "steinmetz", "holzfaeller"]:
			var d0 = Droids.build(w, null)
			d0.set_job(j)
		await _wait(main, 3.0)
		Game.select(w.droids[0])
		main.camera.zoom = main.camera.zoom * 2.0
		main.hud._follow = true
		return
	print("Droiden ", _okf(Droids.unlocked() and Game.is_unlocked("droidenfabrik")), " Droidenfabrik ab Computer und Elektrizität")
	var by := {}
	for s in w.settlers:
		if s.is_adult() and Droids.replaceable(s.job):
			by[s.job] = int(by.get(s.job, 0)) + 1
	var pop: int = w.settlers.size()
	var d = Droids.build(w, null)
	var most := 0
	for j in by:
		most = maxi(most, by[j])
	print("Droiden ", _okf(w.droids.size() == 1 and w.settlers.size() == pop and (by.is_empty() or int(by.get(d.job, 0)) == most)), " Droide %s übernimmt %s (häufigster Beruf, %d Siedler bleiben)" % [d.display_name, d.job, w.settlers.size()])
	print("Droiden ", _okf(Game.population() >= pop and not w.settlers.has(d)), " zählt nicht zur Bevölkerung")
	print("Droiden ", _okf(Droids.is_droid_id(w, d.id) and HouseNeeds.pool_block(w, w.buildings[0], d.id) == 0), " braucht keine Hausstufe")
	# Strom
	d.set_job("holzfaeller")
	var s0 := Game.amount("strom", w)
	Game.time_days += 0.0
	for i in 12:
		Droids.tick(w, 0.1)
	print("Droiden ", _okf(Game.amount("strom", w) == s0 - 1 and Droids.powered(w)), " braucht 1 Strom am Tag (%d -> %d)" % [s0, Game.amount("strom", w)])
	w.stock["strom"] = 0
	for i in 12:
		Droids.tick(w, 0.1)
	await _wait(main, 0.5)
	print("Droiden ", _okf(not Droids.powered(w) and not d.powered), " ohne Strom: %s" % d.activity)
	w.stock["strom"] = 100
	Droids.tick(w, 0.1)
	await _wait(main, 3.0)
	print("Droiden ", _okf(d.powered and d.activity != Loc.t("Kein Strom: steht still")), " mit Strom: %s (Strom %s, Plan %s)" % [d.activity, Droids.powered(w), str(d._plan)])
	var h0 := Game.amount("holz", w)
	var t0 := Game.time_days
	var waited := 0
	while Game.time_days - t0 < 1.0 and Game.amount("holz", w) <= h0 and d.carry_n == 0 and waited < 100:
		waited += 1
		await _wait(main, 0.3)
	print("Droiden ", _okf(Game.amount("holz", w) > h0 or d.carry_n > 0), " fällt Holz (%d -> %d, trägt %d)" % [h0, Game.amount("holz", w), d.carry_n])
	# Speichern
	var data: Dictionary = w.serialize()
	var copy = JSON.parse_string(JSON.stringify(data))
	print("Droiden ", _okf(Array(copy.get("droids", [])).size() == 1 and str(copy.droids[0].job) == "holzfaeller"), " Speichern: %s" % str(copy.get("droids", [])))
	var dd := {}
	Droids._on_save(dd)
	Droids._on_load(JSON.parse_string(JSON.stringify(dd)), 99)
	print("Droiden ", _okf(Droids.built >= 1), " Zähler gespeichert (%d)" % Droids.built)
	w.remove_droid(d)
	print("Droiden ", _okf(w.droids.is_empty()), " Droide abgebaut")
