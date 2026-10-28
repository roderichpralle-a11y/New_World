class_name CartTest
extends RefCounted
## Testhilfe --cartshot=1 (Extras.autotest_setup): Schubkarren der Siedler mit Handkarren.
## Prueft zuerst, dass die Karre nur beim Transportieren mit erforschtem Handkarren zu sehen ist
## ("Karren OK" / "Karren FEHLER"), dann laufen vier Siedler mit Waren hin und her (seitlich nach
## rechts und links, nach unten, nach oben) und die Kamera zoomt auf sie (Bildschirmfoto mit --shot).

const GOODS := ["holz", "stein", "beeren", "fisch"]
static var fails := 0
static var seen_dirs: Dictionary = {}


static func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("Karren ", "OK " if c else "FEHLER ", what)


static func _set_handkarren(on: bool) -> void:
	if on and not "handkarren" in Game.research.done:
		Game.research.done.append("handkarren")
	elif not on:
		Game.research.done.erase("handkarren")
	Game.refresh_effects()


## Freie Flaeche (13 x 9 Zellen begehbar) moeglichst nah an der Inselmitte.
static func _open_spot(w) -> Vector2i:
	var best: Vector2i = w.settlers[0].cell if not w.settlers.is_empty() else w.center
	for r in range(0, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c: Vector2i = w.center + Vector2i(dx, dy)
				var free := true
				for y in range(-4, 5):
					for x in range(-6, 7):
						if not w.is_walkable(c + Vector2i(x, y)):
							free = false
				if free:
					return c
	return best


static func run(main, args: Dictionary) -> void:
	fails = 0
	seen_dirs = {}
	var w = main.world
	var c := _open_spot(w)
	var names := ["Karla", "Rudi", "Berta", "Udo"]
	# Laufwege (Start, Ziel): unten nach rechts, oben nach links, nach unten, nach oben. Am Ziel
	# geht es wieder vom Start los, so zeigt jeder Siedler immer seine Richtung.
	var legs := [[Vector2i(-5, 3), Vector2i(0, 3)], [Vector2i(5, -3), Vector2i(0, -3)],
		[Vector2i(-2, -1), Vector2i(-2, 1)], [Vector2i(2, 1), Vector2i(2, -1)]]
	var carts: Array = []
	for i in 4:
		var start: Vector2i = c + legs[i][0]
		var s = w.spawn_settler({"name": names[i], "sex": "f" if i % 2 == 0 else "m", "age": 25.0,
			"max_age": 70.0, "skills": {}, "x": start.x, "y": start.y})
		s.hunger = 100.0
		s.mind.sick = ""
		s.carry_res = GOODS[i]
		s.carry_n = 3
		carts.append(s)
	# 1. Sichtbarkeit: ohne Handkarren keine Karre, mit Handkarren nur beim Laufen mit Last
	var s0 = carts[0]
	s0._dir = Settler.DIR_SIDE
	s0._moving = true
	_set_handkarren(false)
	s0._animate(0.0)
	_ok(not s0._cart.visible and s0._carry_icon.visible and s0._carry_icon.position.y < -20.0,
		"ohne Handkarren keine Karre, Ware ueber dem Kopf")
	_set_handkarren(true)
	s0._animate(0.0)
	if s0._sied_kind != "":
		# Siedler-Bögen (2.0): die Karre ist gezeichnet (Zeilen "Schubkarre schieben"), die Ware schwebt darüber
		var block: int = s0._layers["fig"].frame / 8 / 3
		var want: int = Settler.SIED_JOB["karre"] if s0._sied_kind == "job" else Settler.SIED_FREI["karre"]
		_ok(not s0._cart.visible and block == want, "mit Handkarren schiebt die Figur ihre Schubkarre (Block %d)" % block)
	else:
		_ok(s0._cart.visible and s0._cart_front.visible and s0._carry_icon.position.y > -20.0
			and s0._carry_icon.position.x > 5.0, "mit Handkarren Karre sichtbar, Ware in der Wanne")
	s0.carry_n = 0
	s0._animate(0.0)
	_ok(not s0._cart.visible, "ohne Last keine Karre")
	s0.carry_n = 3
	s0._moving = false
	s0._animate(0.0)
	_ok(not s0._cart.visible, "im Stehen keine Karre")
	s0._moving = true
	s0.age = float(Data.bal("adult_age")) * 0.5
	s0._animate(0.0)
	_ok(not s0._cart.visible, "Kinder schieben keine Karre")
	s0.age = 25.0
	s0._moving = false
	# 2. Hin und her laufen lassen; Rad-Bild und Richtung werden mitgeschrieben
	for i in 4:
		carts[i].abort_plan()
	var cam = main.camera
	# Bildmitte etwas links von den Siedlern: links oben steht die Zielkarte
	var center: Vector2 = w.cell_to_pos(c) + Vector2(-23, -6)
	if args.has("shot"):
		cam.zoom = Vector2(3.0, 3.0)
		cam.focus(center)
	var wheels := {}
	main.get_tree().process_frame.connect(func():
		for i in carts.size():
			var s = carts[i]
			if not is_instance_valid(s):
				continue
			s.hunger = 100.0
			s.mind.sick = ""
			s.carry_res = GOODS[i]
			s.carry_n = 3
			if s.sleeping:
				s._wake_up()
				s._plan.clear()
			if s._plan.is_empty():
				var a: Vector2i = c + legs[i][0]
				s.cell = a
				s.position = w.cell_to_pos(a)
				s._cart_last = s.position
				s._plan.append({"a": "move", "cell": c + legs[i][1]})
			var sied: bool = s._sied_kind != "" and s.pushes_cart()  # Siedler-Bögen: Karre im Bild, 8 Bilder
			if s._cart.visible or sied:
				seen_dirs[s._dir * 10 + (1 if s._flip and s._dir == Settler.DIR_SIDE else 0)] = true
				wheels[(s._layers["fig"].frame if sied else int(s._cart_roll)) % 4] = true
		if args.has("shot") and is_instance_valid(cam):
			cam.focus(center))
	# 6 Sekunden Spielzeit laufen lassen (nach Bildern, nicht nach Echtzeit: die ersten Bilder mit
	# Fenster koennen lange dauern)
	var t0: float = Game.time_days
	var frames := 0
	while frames < 30 or (Game.time_days - t0) * float(Data.bal("day_length")) < 6.0:
		await main.get_tree().process_frame
		frames += 1
		if frames > 5000:
			break
	_ok(seen_dirs.has(Settler.DIR_SIDE * 10) and seen_dirs.has(Settler.DIR_SIDE * 10 + 1)
		and seen_dirs.has(Settler.DIR_DOWN * 10) and seen_dirs.has(Settler.DIR_UP * 10),
		"Karre seitlich (rechts und links), nach unten und nach oben gesehen: %s" % [seen_dirs.keys()])
	_ok(wheels.size() == 4, "Rad dreht sich (Bilder %s)" % [wheels.keys()])
	print("Karren ", "OK" if fails == 0 else "FEHLER", ": %d Fehler" % fails)
