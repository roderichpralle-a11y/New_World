class_name TallTest
extends RefCounted
## Selbsttest --talltest=1 (josh 2026-11-10): Hochregallager. Stauraum 5000, Grundfläche 3x2, keine Dachfelder
## (hinter ihm darf gebaut und gegangen werden), oberer Bildteil auf Ebene der Figuren. --talltest=shot stellt zusätzlich ein Haus, eine Straße und Siedler dahinter und davor auf (Bildschirmfoto mit --shot).

static var fails := 0


static func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("Hochregal ", "OK " if c else "FEHLER ", what)


static func _spot(w, type: String, around: Vector2i, need_back: int) -> Vector2i:
	var sz: Array = Data.buildings[type].size
	for rad in range(2, 30):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var cc: Vector2i = around + Vector2i(dx, dy)
				var ok := true
				for y in range(-need_back, int(sz[1]) + 2):
					for x in range(-1, int(sz[0]) + 1):
						var p: Vector2i = cc + Vector2i(x, y)
						if w.building_at.has(p) or w.roof_at.has(p) or not w.is_inside(p) or w.is_water(p):
							ok = false
				if ok and w.can_place(type, cc):
					return cc
	return Vector2i(-1, -1)


static func run(main, shot: bool) -> void:
	fails = 0
	var w = main.world
	var d: Dictionary = Data.buildings.hochregallager
	_ok(int(d.storage) == 5000 and int(d.size[0]) == 3 and int(d.size[1]) == 2, "Stauraum 5000, Grundfläche 3x2")
	_ok(str(d.get("requires", "")) == "stahl", "freigeschaltet mit der Forschung Stahl")
	_ok(Building.roof_offsets("hochregallager").is_empty(), "keine Dachfelder: hinter dem Lager darf man gehen und bauen")
	var c := _spot(w, "hochregallager", w.center, 5)
	_ok(c.x >= 0, "Platz für das Hochregallager gefunden")
	if c.x < 0:
		return
	var vol0: int = Game.storage_volume(w)
	var b: Building = w.place_building("hochregallager", c, true)
	_ok(Game.storage_volume(w) - vol0 == Game.building_volume(d), "Stauraum der Insel wächst um %d" % Game.building_volume(d))
	_ok(b._top != null and b._top.z_index == 1 and b._sprite.z_index == 0, "oberer Bildteil auf Ebene der Figuren, unterer darunter")
	if b._top:
		var hi: AtlasTexture = b._top.texture
		var lo: AtlasTexture = b._sprite.texture
		_ok(is_equal_approx(lo.region.size.y, 36.0) and hi.region.size.y > 20.0, "Bild geteilt: unten %d, oben %d Pixel" % [lo.region.size.y, hi.region.size.y])
		# beide Teile schließen ohne Lücke aneinander an
		_ok(is_equal_approx(b._top.offset.y + hi.region.size.y, b._sprite.offset.y), "Teile schließen aneinander an")
	# Gebäude direkt hinter dem Lager (unter dem hohen Bild) ist erlaubt
	var behind := c + Vector2i(0, -3)
	for y in range(-3, -1):  # Bäume und Steine dort weg, damit nur das Dach-Thema geprüft wird
		for x in range(-1, 4):
			if w.node_at.has(c + Vector2i(x, y)):
				w.remove_node(w.node_at[c + Vector2i(x, y)]) if w.has_method("remove_node") else null
	_ok(w.can_place("huette", behind), "Hütte direkt dahinter darf gebaut werden (Bild ragt darüber)")
	var road_ok := true
	for x in range(-1, 4):
		var rc := c + Vector2i(x, -1)
		if w.can_place("strasse", rc):
			w.place_building("strasse", rc, true)
		else:
			road_ok = false
	_ok(road_ok, "Straße direkt hinter dem Lager")
	_ok(w.is_walkable(c + Vector2i(1, -1)), "Feld hinter dem Lager ist begehbar")
	if shot:
		w.place_building("huette", behind, true)
		var pos: Vector2 = b.position
		var people := [Vector2(-8, -40), Vector2(16, -44), Vector2(-30, -56), Vector2(8, 14), Vector2(-22, 18)]
		for i in people.size():
			var s = w.spawn_settler({"name": "H%d" % i, "sex": "m" if i % 2 == 0 else "f", "age": 30.0, "max_age": 70.0,
				"x": c.x, "y": c.y + 3})
			s.position = pos + people[i]
			s.set_process(false)
			s.set_physics_process(false)
		main.camera.position = pos + Vector2(0, -30)
		main.camera.zoom = Vector2(3.2, 3.2)
	print("Hochregal fertig, Fehler: ", fails)
