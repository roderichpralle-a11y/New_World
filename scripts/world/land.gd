class_name Land
extends RefCounted
## Straßen, Deiche, Neuland und der Förster (josh 2026-10-11). Gebäude in data/buildings.json mit "tile":
## "road" (Straße), "dike" (Deich, "water_ok": auch im Wasser) und "plant_mark" (Setzling, baut der Förster).
##
## - Straße: Bodenkachel, 20 Stein, baut der Baumeister. Auf fertigen Straßen laufen Siedler
##   balance.road_speed (1,5) mal so schnell (Settler._walk).
## - Deich: Bodenkachel aus Stein, Holz und Lehm, baut der Baumeister. Darf auf Land oder im Wasser stehen,
##   im Wasser nur neben Land oder einem anderen Deich (dike_allowed). Ein fertiger Deich im Wasser ist
##   begehbar. Nach jedem fertigen Deich prüft update_polders: Wasser, das nicht mehr mit dem offenen Meer
##   (Kartenrand) verbunden ist (4er-Nachbarschaft, fertige Deiche sperren), an einen Deich und an Land
##   grenzt, wird Land (Sand, innen Gras). Das Neuland steht in World.land_mod und im Spielstand
##   ("land": {cells: [[x, y, t]], sunk: [...]}); beim Laden wird es vor dem Gelände eingetragen.
## - Sturmflut (Events._flood -> storm): mit power steigt die Wahrscheinlichkeit, dass ein äußerer Deich
##   (grenzt an offenes Wasser) bricht. Er wird zur Baustelle (70 % des Preises), und flood setzt alles
##   Neuland unter Wasser, das jetzt wieder mit dem Meer verbunden ist: Bäume verschwinden, Gebäude gehen
##   unter (World.sunk) und kommen als Baustelle für 70 % zurück, sobald dort wieder Land ist.
##   Siedler und Tiere auf überflutetem Boden retten sich aufs nächste Land. Reißt der Spieler einen Deich
##   ab, läuft das Wasser genauso hinein.
## - Förster (Beruf "foerster"): pflanzt an Pflanzstellen (Gebäude "setzling", nur er baut sie) einen jungen
##   Baum und rodet Bäume und Sträucher, die im Infofenster zum Roden markiert sind (ResNode.clear_mark).
##   Gerodete Bäume bringen ihr Holz, Sträucher nichts.

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const CLEARABLE := ["baum", "busch", "palme", "gewuerzstrauch", "pilzkreis"]


# ---------------------------------------------------------------- Spielstand
static func serialize(w) -> Dictionary:
	var cells := []
	for idx in w.land_mod:
		cells.append([int(idx) % w.size, int(idx) / w.size, int(w.land_mod[idx])])
	return {"cells": cells, "sunk": w.sunk.duplicate(true)}


## Vor _build_terrain: Neuland aus dem Spielstand in das frisch erzeugte Gelände eintragen.
static func apply_saved(w, island: Dictionary, save: Dictionary) -> void:
	w.land_mod = {}
	w.sunk = []
	var d = save.get("land", null)
	if not (d is Dictionary):
		return
	for e in d.get("cells", []):
		var x := int(e[0])
		var y := int(e[1])
		if x < 0 or y < 0 or x >= w.size or y >= w.size:
			continue
		var idx: int = y * w.size + x
		island.terrain[idx] = int(e[2])
		w.land_mod[idx] = int(e[2])
	for e in d.get("sunk", []):
		if e is Dictionary and Data.buildings.has(str(e.get("type", ""))):
			w.sunk.append({"type": str(e.type), "x": int(e.x), "y": int(e.y)})


# ---------------------------------------------------------------- Bau
## Deich: auf Land immer, im Wasser nur neben Land oder einem Deich (fertig oder Baustelle).
static func dike_allowed(w, c: Vector2i) -> bool:
	if not w.is_water(c):
		return true
	for d in DIRS:
		var n: Vector2i = c + d
		if w.is_inside(n) and not w.is_water(n):
			return true
		var o = w.building_at.get(n)
		if o != null and o.def.get("tile", "") == "dike":
			return true
	return false


static func on_completed(w, b) -> void:
	match str(b.def.get("tile", "")):
		"dike":
			w._set_solid(b.cell, false)
			w.refresh_tiles_around(b.cell)
			w.spawn_effect("dust", b.position)
			Sound.play_at("hammer", w, b.position)
			update_polders(w)
		"plant_mark":
			plant_tree(w, b)
		_:
			w.refresh_tiles_around(b.cell)
			w.spawn_effect("dust", b.position)
	Game.stock_changed.emit()


## Setzling fertig: die Pflanzstelle verschwindet, ein junger Baum wächst (halbe Nachwachszeit).
static func plant_tree(w, b) -> void:
	var c: Vector2i = b.cell
	w.buildings.erase(b)
	w.building_at.erase(c)
	if Game.selected == b:
		Game.select(null)
	b.queue_free()
	var t = w.spawn_node("baum", c)
	t.amount = 0
	t.regrow_at = Game.time_days + float(t.def.regrow_days) * 0.5
	t.refresh()
	w.spawn_effect("leaves", t.position + Vector2(0, -6))
	# Wer auf der Zelle steht, geht einen Schritt zur Seite
	for s in w.settlers:
		if s.cell == c:
			_rescue(w, s)


# ---------------------------------------------------------------- Neuland
## Offenes Wasser: vom Kartenrand aus erreichbar, ohne durch fertige Deiche zu gehen.
## with_land: auch Neuland (land_mod) gilt als durchlässig (für die Überflutung nach einem Deichbruch).
static func _open(w, with_land: bool) -> PackedByteArray:
	var n: int = w.size
	var seen := PackedByteArray()
	seen.resize(n * n)
	var q: Array = []
	var flows := func(x: int, y: int) -> bool:
		var idx: int = y * n + x
		if w.dike_at(Vector2i(x, y)):
			return false
		return w.terrain[idx] == World.WATER or (with_land and w.land_mod.has(idx))
	for i in n:
		for c in [Vector2i(i, 0), Vector2i(i, n - 1), Vector2i(0, i), Vector2i(n - 1, i)]:
			var idx: int = c.y * n + c.x
			if seen[idx] == 0 and flows.call(c.x, c.y):
				seen[idx] = 1
				q.append(c)
	var h := 0
	while h < q.size():
		var c: Vector2i = q[h]
		h += 1
		for d in DIRS:
			var m: Vector2i = c + d
			if m.x < 0 or m.y < 0 or m.x >= n or m.y >= n:
				continue
			var idx: int = m.y * n + m.x
			if seen[idx] == 0 and flows.call(m.x, m.y):
				seen[idx] = 1
				q.append(m)
	return seen


## Abgeschlossenes Wasser hinter Deichen wird Land. Gibt die Zahl der neuen Landfelder zurück.
static func update_polders(w, quiet := false) -> int:
	var n: int = w.size
	var open := _open(w, false)
	var done := PackedByteArray()
	done.resize(n * n)
	var gained: Array = []
	for y in n:
		for x in n:
			var idx: int = y * n + x
			if done[idx] == 1 or open[idx] == 1 or w.terrain[idx] != World.WATER or w.dike_at(Vector2i(x, y)):
				continue
			# Wasserfläche einsammeln
			var comp: Array = [Vector2i(x, y)]
			done[idx] = 1
			var h := 0
			var by_dike := false
			var by_land := false
			while h < comp.size():
				var c: Vector2i = comp[h]
				h += 1
				for d in DIRS:
					var m: Vector2i = c + d
					if not w.is_inside(m):
						continue
					var mi: int = m.y * n + m.x
					if w.dike_at(m):
						by_dike = true
					elif w.terrain[mi] != World.WATER:
						by_land = true
					elif done[mi] == 0 and open[mi] == 0:
						done[mi] = 1
						comp.append(m)
			if by_dike and by_land:
				gained.append_array(comp)
	if gained.is_empty():
		return 0
	for c in gained:
		var nd = w.node_at.get(c)
		if nd != null:
			w.remove_node(nd)  # Fischgründe fallen trocken
		w.land_mod[c.y * n + c.x] = World.SAND
		w.terrain[c.y * n + c.x] = World.SAND
	# Innen Gras, am Rand Sand
	for c in gained:
		var inner := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var m: Vector2i = c + Vector2i(dx, dy)
				if not w.is_inside(m) or w.terrain[m.y * n + m.x] == World.WATER:
					inner = false
		if inner:
			w.land_mod[c.y * n + c.x] = World.GRASS
	for c in gained:
		w.set_terrain(c, int(w.land_mod[c.y * n + c.x]))
	for c in gained:
		w.refresh_tiles_around(c)
	var back := _restore_sunk(w)
	if not quiet:
		var t := Loc.t("Neuland! Hinter den Deichen sind %d Felder Land entstanden.") % gained.size()
		if back > 0:
			t += " " + Loc.t("Untergegangene Gebäude stehen wieder als Baustelle da (70 % des Preises).")
		Game.notify_at(w, t, "wasser")
		Sound.play_on("fertig", w)
	Game.population_changed.emit()
	return gained.size()


## Untergegangene Gebäude kommen als Baustelle zurück, wo wieder Platz ist.
static func _restore_sunk(w) -> int:
	var back := 0
	for e in w.sunk.duplicate():
		var c := Vector2i(int(e.x), int(e.y))
		if not w.can_place(e.type, c):
			continue
		var b = w.place_building(e.type, c, false)
		b.delivered = Events.rebuild_delivered(b.def.cost)
		b.refresh()
		w.sunk.erase(e)
		back += 1
	return back


## Äußere Deiche: fertig und an offenes Wasser grenzend (nur sie kann eine Sturmflut brechen).
static func outer_dikes(w) -> Array:
	var out := []
	var open: PackedByteArray
	var have := false
	for b in w.buildings:
		if not (b.complete and b.def.get("tile", "") == "dike"):
			continue
		if not have:
			open = _open(w, false)
			have = true
		for d in DIRS:
			var m: Vector2i = b.cell + d
			if w.is_inside(m) and open[m.y * w.size + m.x] == 1:
				out.append(b)
				break
	return out


## Wasser läuft in Neuland, das wieder mit dem Meer verbunden ist (nach Deichbruch oder Abriss).
## Gibt {cells: Zahl, lost: [Gebäudenamen]} zurück.
static func flood(w, _breached: Array) -> Dictionary:
	var res := {"cells": 0, "lost": []}
	if w.land_mod.is_empty():
		_rescue_all(w)
		return res
	var n: int = w.size
	var open := _open(w, true)
	var wet: Array = []
	for idx in w.land_mod.keys():
		if open[int(idx)] == 1:
			wet.append(Vector2i(int(idx) % n, int(idx) / n))
	if wet.is_empty():
		_rescue_all(w)
		return res
	var wet_set := {}
	for c in wet:
		wet_set[c] = true
	# Gebäude auf überflutetem Boden gehen unter (Deiche bleiben, sie dürfen im Wasser stehen)
	for b in w.buildings.duplicate():
		if b.def.get("water_ok", false) or b.type == "lagerfeuer":
			continue
		var hit := false
		for cc in b.cells():
			if wet_set.has(cc):
				hit = true
		if hit:
			res.lost.append(str(b.def.name))
			_sink(w, b)
	for c in wet:
		var nd = w.node_at.get(c)
		if nd != null:
			w.remove_node(nd)
		w.land_mod.erase(c.y * n + c.x)
		w.set_terrain(c, World.WATER)
		w.spawn_effect("chips_fischgrund", w.cell_to_pos(c))
	for c in wet:
		w.refresh_tiles_around(c)
	res.cells = wet.size()
	_rescue_all(w)
	w.assign_homes()
	Game.refresh_effects()
	Game.population_changed.emit()
	Game.stock_changed.emit()
	return res


## Gebäude verschwindet im Wasser und wird für den Wiederaufbau gemerkt (World.sunk).
static func _sink(w, b) -> void:
	for s in w.settlers:
		if s.home_id == b.id:
			s.home_id = 0
			if s.sleeping:
				s._wake_up()
		if s._reserved == b or s._incoming.any(func(i): return i[0] == b) or s._hiding == b:
			s.abort_plan()
		if b.occupants.has(s.id):
			s.abort_plan()
	w.buildings.erase(b)
	for cc in b.cells():
		w.building_at.erase(cc)
		w._set_solid(cc, w.node_at.has(cc) and w.node_at[cc].is_solid())
	if Game.selected == b:
		Game.select(null)
	w.sunk.append({"type": b.type, "x": b.cell.x, "y": b.cell.y})
	if b.def.has("harbor"):
		w.sync_ships.call_deferred()
	b.queue_free()


## Siedler und Tiere, die im Wasser oder auf einem Hindernis stehen, gehen aufs nächste begehbare Land.
static func _rescue_all(w) -> void:
	for s in w.settlers:
		if s.visible and not w.is_walkable(s.cell):
			_rescue(w, s)
	for a in w.animals:
		if is_instance_valid(a) and not w.is_walkable(a.cell) and w.is_water(a.cell):
			var c = _nearest_land(w, a.cell)
			if c != null:
				a.cell = c
				a.position = w.cell_to_pos(c)
				a._path = PackedVector2Array()


static func _rescue(w, s) -> void:
	var c = _nearest_land(w, s.cell)
	if c == null:
		return
	s.abort_plan()
	s.cell = c
	s.position = w.cell_to_pos(c)


static func _nearest_land(w, from: Vector2i):
	for r in range(1, 20):
		var best = null
		var bd := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if max(abs(dx), abs(dy)) != r:
					continue
				var c: Vector2i = from + Vector2i(dx, dy)
				if w.is_walkable(c) and not w.is_water(c):
					var d := Vector2(dx, dy).length_squared()
					if d < bd:
						bd = d
						best = c
		if best != null:
			return best
	return null


## Sturmflut: vielleicht bricht ein äußerer Deich (bei großer Stärke auch zwei). Text für die Meldung
## oder "" (kein Deich gebrochen).
static func storm(w, rng: RandomNumberGenerator, power: float) -> String:
	var outer := outer_dikes(w)
	if outer.is_empty():
		return ""
	var d: Dictionary = Events.type_def("sturmflut")
	var p: float = clampf(float(d.get("breach_base", 0.3)) + float(d.get("breach_power", 0.2)) * power, 0.0, 0.95)
	var n := 0
	if rng.randf() < p:
		n = 1
		if power >= 2.0 and outer.size() > 1 and rng.randf() < 0.5:
			n = 2
	if n == 0:
		return ""
	var broken := []
	for i in n:
		var b = outer[rng.randi() % outer.size()]
		outer.erase(b)
		Events.damage_building(w, b)
		w._set_solid(b.cell, w.is_water(b.cell))
		w.refresh_tiles_around(b.cell)
		w.spawn_effect("chips_fischgrund", b.position)
		broken.append(b)
	var r := flood(w, broken)
	var t := Loc.t("Ein Deich ist gebrochen!") if n == 1 else Loc.t("Zwei Deiche sind gebrochen!")
	if int(r.cells) > 0:
		t += " " + Loc.t("Das Wasser hat %d Felder Neuland überflutet.") % int(r.cells)
	if not r.lost.is_empty():
		t += " " + Loc.t("Zerstört: %s. Steht der Deich wieder, kommen sie als Baustelle für 70 %% des Preises zurück.") % ", ".join(r.lost)
	t += " " + Loc.t("Baut den Deich wieder auf.")
	return t


# ---------------------------------------------------------------- Förster
## Arbeit des Försters: erst pflanzen, dann roden. false = nichts zu tun.
static func plan_forester(s) -> bool:
	var w = s.world
	# 1. Pflanzstellen
	var sites: Array = w.construction_sites("foerster")
	sites.sort_custom(func(a, b): return a.dist_sq(s.cell) < b.dist_sq(s.cell))
	for site in sites:
		if site.reserved_by != 0 and site.reserved_by != s.id:
			continue
		if w._unreachable.has(site) and w._unreachable[site] > Game.time_days:
			continue
		if not s._push_move_to(site.cells(), true):
			w.mark_unreachable(site)
			continue
		s._reserve(site)
		s._plan.append({"a": "work", "t": 2.5 / s.work_factor("holz"), "act": Loc.t("Pflanzt einen Baum"), "tool": "shovel",
			"face": site.position, "done": _do_plant.bind(s, site)})
		s.activity = Loc.t("Pflanzt einen Baum")
		return true
	# 2. Zum Roden markierte Bäume und Sträucher
	var best = null
	var bd := INF
	for nd in w.nodes:
		if not nd.clear_mark or (nd.reserved_by != 0 and nd.reserved_by != s.id):
			continue
		if w._unreachable.has(nd) and w._unreachable[nd] > Game.time_days:
			continue
		var dd := Vector2(nd.cell - s.cell).length_squared()
		if dd < bd:
			bd = dd
			best = nd
	if best == null:
		return false
	if not s._push_move_to([best.cell], best.is_solid()):
		w.mark_unreachable(best)
		return false
	s._reserve(best)
	var tool := "axe" if best.type in ["baum", "palme"] else "shovel"
	s._plan.append({"a": "work", "t": float(best.def.work_time) * 1.5 / s.work_factor("holz"), "act": Loc.t("Rodet"),
		"tool": tool, "face": best.position, "done": _do_clear.bind(s, best)})
	s.activity = Loc.t("Rodet: %s") % best.def.name
	return true


static func _do_plant(s, site) -> void:
	if not is_instance_valid(site) or site.complete:
		return
	s.gain_xp("holz", 0.5)
	site.add_work(float(site.def.work) + 1.0)  # fertig: plant_tree


static func _do_clear(s, nd) -> void:
	if not is_instance_valid(nd) or not nd.clear_mark:
		return
	var w = s.world
	var wood := 0
	if nd.type == "baum" and nd.amount > 0:
		wood = int(nd.amount)
	w.spawn_effect("leaves" if nd.type in ["baum", "palme"] else "dust", nd.position + Vector2(0, -8))
	Sound.play_at("axt", w, nd.position)
	w.remove_node(nd)
	s.gain_xp("holz", 1.0)
	if wood > 0 and Game.space_for("holz", w) > 0:
		if s.carry_n > 0 and s.carry_res != "holz":
			s._do_deliver()
		s.carry_res = "holz"
		s.carry_n = mini(s.carry_n + wood, s.carry_capacity())
		s._plan_deliver_after()


## Infofenster eines Baums oder Strauchs: Knopf "Roden lassen" (nur mit freigeschaltetem Förster).
static func node_rows(hud, nd) -> void:
	if not nd.type in CLEARABLE or not Data.job_unlocked("foerster"):
		return
	var on: bool = nd.clear_mark
	var bt := UiTheme.button(Loc.t("Nicht roden") if on else Loc.t("Roden lassen (Förster)"), "abriss" if on else "axt", 34)
	bt.pressed.connect(func():
		nd.clear_mark = not nd.clear_mark
		nd.refresh()
		hud._rebuild_info())
	hud._info_box.add_child(bt)
	var has := false
	for s in nd.world.settlers:
		if s.job == "foerster" and s.is_adult():
			has = true
	var t := Loc.t("Ein Förster rodet ihn bald.") if on else Loc.t("Der Förster entfernt Bäume und Sträucher, damit Platz für Gebäude, Felder und Straßen wird.")
	if on and not has:
		t = Loc.t("Es gibt noch keinen Förster. Gib einem Siedler den Beruf Förster.")
	var l := UiTheme.label(t, 12, UiTheme.BAD if on and not has else Color("#6e5a50"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud._info_box.add_child(l)
