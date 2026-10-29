class_name PlanReport
extends RefCounted
## Aufbau-Gutachten des Planungsautomaten (josh 2026-10-29, nur Version 2): einmal im Jahr im Sommer
## (Planner._process) rechnet er je Insel aus, wie der Aufbau besser liefe. Nur Vorschläge, er baut nichts,
## und es gibt keinen Knopf, der sie als Bauauftrag übernimmt. Der letzte Bericht steht im Fenster Verwalter,
## Reiter Gutachten, mit einer Karte. Teile je Insel:
##   roads  Felder, über die viel getragen wird und auf denen noch keine Straße liegt (Wege von den
##          Arbeitsplätzen zum nächsten Lager, gewichtet nach Arbeitsplätzen)
##   moves  Gebäude weit weg vom Lager und eine freie Stelle nah am Lager, mit der Wegersparnis
##   tips   allgemeine Hinweise (Essen, Wärme, Betten, stillstehende Werkstätten, Lager, Freie)
##   plan   Versorgungsplan (Befugnis „Versorgungsplan“ und Rundfunkanstalt): je Ware Bedarf für Essen,
##          Wärme, die nächsten Forschungen und die nächsten Gebäude, und wie viele Gebäude dafür nötig sind
## Dazu für alle Inseln: welche entdeckte Insel als Nächstes besiedelt werden sollte (settle).

const FAR := 12          # so viele Felder vom Lager gilt ein Arbeitsplatz als weit weg
const NEAR := 6          # die neue Stelle liegt höchstens so weit vom Lager
const MAX_ROADS := 40
const MAX_MOVES := 3
const CYCLES := 96.0     # Arbeitsgänge je Platz und Tag etwa = CYCLES / Arbeitszeit (Tag 240 s, Wege, Pausen, Schlaf)
const PLAN_DAYS := 10.0  # Forschung und Bauten sollen in so vielen Tagen bezahlbar sein


static func make() -> Dictionary:
	var rep := {"year": Seasons.year(), "day": Game.time_days, "islands": {}, "settle": settle_tip()}
	for w in Sea.all_worlds():
		if w.settlers.is_empty() or not Powers.covers(w):
			continue
		rep.islands[str(int(w.island_id))] = island(w)
	return rep


static func island(w) -> Dictionary:
	var roads := _roads(w)
	var out := {"name": Sea.island_name(w), "roads": roads, "moves": _moves(w), "tips": _tips(w), "plan": []}
	if Powers.on("versorgung") and Steward.has_radio(w):
		out.plan = supply_plan(w)
	return out


# ---------------------------------------------------------------- Straßen
static func _workplaces(w) -> Array:
	var out := []
	for b in w.buildings:
		if b.complete and not b.is_ground() and not b.is_decor() and (b.def.has("production") or b.def.has("research") or b.def.has("farm") or int(b.def.get("housing", 0)) > 0):
			out.append(b)
	return out


static func _roads(w) -> Array:
	if not Data.buildings.has("strasse") or not Game.is_unlocked("strasse"):
		return []
	var heat := {}
	for b in _workplaces(w):
		var st = w.nearest_storage(b.entrance_cell())
		if st == null or st == b:
			continue
		var weight := float(maxi(1, b.slots() if b.def.has("production") or b.def.has("research") else int(b.def.get("housing", 1)) / 2))
		var path: PackedVector2Array = w.find_path(b.entrance_cell(), st.entrance_cell())
		for p in path:
			var c := Vector2i(int(p.x), int(p.y))
			if w.road_at(c) or w.building_at.has(c):
				continue
			heat[c] = float(heat.get(c, 0.0)) + weight
	var cells: Array = heat.keys()
	cells.sort_custom(func(a, b): return heat[a] > heat[b])
	var out := []
	for c in cells:
		if out.size() >= MAX_ROADS or float(heat[c]) < 2.0:
			break
		out.append([c.x, c.y])
	return out


# ---------------------------------------------------------------- Verschieben
static func _moves(w) -> Array:
	var out := []
	var cand := []
	for b in w.buildings:
		if not b.complete or b.is_ground() or b.is_decor() or not b.def.has("production") or b.def.get("unique", false):
			continue
		if b.def.has("harbor") or b.def.get("coast", false) or b.def.get("water_ok", false):
			continue
		var st = w.nearest_storage(b.entrance_cell())
		if st == null or st == b:
			continue
		var d: int = w.find_path(b.entrance_cell(), st.entrance_cell()).size()
		if d > FAR:
			cand.append([b, st, d])
	cand.sort_custom(func(a, c): return a[2] > c[2])
	for e in cand:
		if out.size() >= MAX_MOVES:
			break
		var b = e[0]
		var st = e[1]
		var spot := _near_spot(w, b, st)
		if spot.x < 0:
			continue
		var nd: int = w.find_path(spot + Vector2i(int(b.def.size[0]) / 2, int(b.def.size[1])), st.entrance_cell()).size()
		if nd <= 0 or nd >= int(e[2]) - 4:
			continue
		out.append({"type": b.type, "name": b.def.name, "from": [b.cell.x, b.cell.y], "to": [spot.x, spot.y],
			"size": [int(b.def.size[0]), int(b.def.size[1])], "was": int(e[2]), "now": nd})
	return out


static func _near_spot(w, b, st) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 999
	var sc: Vector2i = st.entrance_cell()
	for dy in range(-NEAR, NEAR + 1):
		for dx in range(-NEAR, NEAR + 1):
			var c := sc + Vector2i(dx, dy)
			if not w.can_place(b.type, c, b):
				continue
			var d := absi(dx) + absi(dy)
			if d < best_d:
				best_d = d
				best = c
	return best


# ---------------------------------------------------------------- Tipps
static func _tips(w) -> Array:
	var out := []
	var si := Steward.secure_info(w)
	var f: Array = si.food
	var h: Array = si.fuel
	if int(f[2]) > int(f[3]):
		out.append(Loc.t("Essen reicht nicht für 3 Tage: %d Leute in Nahrungsberufen nötig, %d da. Mehr Felder, Fischer oder Sammler.") % [int(f[2]), int(f[3])])
	if int(h[2]) > int(h[3]):
		out.append(Loc.t("Brennstoff reicht nicht für 3 Tage: %d Holzfäller nötig, %d da.") % [int(h[2]), int(h[3])])
	var beds: int = Game.housing_capacity(w) - w.settlers.size()
	if beds <= 0:
		out.append(Loc.t("Alle Betten sind belegt: ohne neue Häuser kommen keine Kinder."))
	var idle := []
	for b in w.buildings:
		if b.complete and b.def.has("production") and b.occupants.is_empty() and b.prod_blocker() != "":
			idle.append(b.def.name)
	if not idle.is_empty():
		out.append(Loc.t("Diesen Werkstätten fehlen Zutaten: %s.") % ", ".join(PackedStringArray(idle.slice(0, 4))))
	var free: int = w.settlers.filter(func(s): return s.is_adult() and s.job == "frei").size()
	if free >= 3:
		out.append(Loc.t("%d Erwachsene sind frei. Gib ihnen einen Beruf oder eine Hauptaufgabe der Insel.") % free)
	var full := []
	for id in w.stock:
		if int(w.stock[id]) > 0 and Game.space_for(str(id), w) <= 0:
			full.append(Data.resource_name(str(id)))
	if full.size() >= 3:
		out.append(Loc.t("Das Lager ist voll mit %s. Ein größeres Lager oder Lagergrenzen helfen.") % ", ".join(PackedStringArray(full.slice(0, 4))))
	if Game.is_unlocked("strasse") and w.buildings.filter(func(b): return b.def.get("tile", "") == "road").size() < 5 and w.buildings.size() > 12:
		out.append(Loc.t("Kaum Straßen: Auf Straßen laufen Siedler 1,5-mal so schnell. Die Karte zeigt, wo sie am meisten bringen."))
	if out.is_empty():
		out.append(Loc.t("Die Insel ist gut versorgt."))
	return out


# ---------------------------------------------------------------- Nächste Insel
static func settle_tip() -> String:
	var have := {}
	for m in Sea.settled_islands():
		have[str(m.get("biome", ""))] = true
	var best := {}
	var best_s := -99
	for m in Sea.islands:
		if str(m.get("state", "")) != "discovered":
			continue
		var bd: Dictionary = Data.islands.get(str(m.get("biome", "")), {})
		var s := 0 if have.has(str(m.biome)) else 3
		s += bd.get("special", []).size()
		s -= Sea.dangers(m).size()
		if s > best_s:
			best_s = s
			best = m
	if best.is_empty():
		return Loc.t("Keine entdeckte Insel zum Besiedeln. Schicke ein Schiff auf Entdeckungsreise.") if Sea.settled_islands().size() > 0 else ""
	var bd: Dictionary = Data.islands.get(str(best.biome), {})
	var goods := ", ".join(PackedStringArray(bd.get("special", []).map(func(r): return Data.resource_name(str(r)))))
	var danger: Array = Sea.dangers(best).map(func(a): return Data.animals.get(str(a), {}).get("name", str(a)))
	var t := Loc.t("Besiedle als Nächstes %s (%s): bringt %s.") % [str(best.name), Loc.t(str(bd.get("name", ""))), goods]
	if not danger.is_empty():
		t += " " + Loc.t("Gefahr: %s.") % ", ".join(PackedStringArray(danger))
	return t


# ---------------------------------------------------------------- Versorgungsplan
## Je Ware: [{id, need (Menge), why, building (Typ), have (Gebäude), want (Gebäude)}]. Bedarf: Essen und
## Brennstoff für PLAN_DAYS Tage, Kosten der nächsten 3 Forschungen und der nächsten noch nicht gebauten Gebäude.
static func supply_plan(w) -> Array:
	var need := {}
	var why := {}
	var add := func(id: String, n: float, reason: String):
		if n <= 0.0:
			return
		need[id] = float(need.get(id, 0.0)) + n
		if not why.has(id):
			why[id] = []
		if not reason in why[id]:
			why[id].append(reason)
	var techs: Array = Planner.tech_order().slice(0, 3)
	for t in techs:
		for res in Data.techs[t].get("cost", {}):
			add.call(str(res), float(Data.techs[t].cost[res]), Data.techs[t].name)
	var next := _next_buildings(w)
	for t in next:
		for res in Data.buildings[t].get("cost", {}):
			add.call(str(res), float(Data.buildings[t].cost[res]), Data.buildings[t].name)
	var out := []
	# Essen und Wärme: Nahrungsberufe und Holzfäller statt Gebäude
	var si := Steward.secure_info(w)
	out.append({"id": "nahrung", "text": Loc.t("Essen: %d Leute in Nahrungsberufen nötig, %d da") % [int(si.food[2]), int(si.food[3])], "ok": int(si.food[3]) >= int(si.food[2])})
	out.append({"id": "holz", "text": Loc.t("Brennstoff: %d Holzfäller nötig, %d da") % [int(si.fuel[2]), int(si.fuel[3])], "ok": int(si.fuel[3]) >= int(si.fuel[2])})
	var beds: int = Game.housing_capacity(w)
	var want_beds := ceili(w.settlers.size() * 1.15) + 2
	out.append({"id": "haus", "text": Loc.t("Betten: %d nötig, %d da") % [want_beds, beds], "ok": beds >= want_beds})
	for id in need:
		var short := float(need[id]) - float(Game.amount(id, w))
		var b := _maker(w, id)
		var have: int = w.buildings.filter(func(x): return x.complete and x.type == b).size() if b != "" else 0
		var want := have
		if short > 0.0 and b != "":
			var pd: Dictionary = Data.buildings[b].get("production", {})
			var per := float(pd.get("outputs", {}).get(id, 1)) * CYCLES / maxf(1.0, float(pd.get("time", 10.0))) * maxf(1.0, float(Data.buildings[b].get("slots", 1)))
			want = maxi(have, ceili(short / (per * PLAN_DAYS)))
		var reasons: Array = why[id]
		var text := Loc.t("%s: %d nötig für %s, im Lager %d") % [Data.resource_name(id), int(need[id]), ", ".join(PackedStringArray(reasons.slice(0, 3))), Game.amount(id, w)]
		if b != "":
			text += " · " + Loc.t("%s: %d nötig, %d da") % [Data.buildings[b].name, want, have]
		elif short > 0.0 and Steward.RAW_JOB.has(id):
			text += " · " + Loc.t("Beruf %s") % Data.jobs[Steward.RAW_JOB[id]].name
		out.append({"id": id, "text": text, "ok": short <= 0.0 or want <= have})
	# Zu viel: Werkstätten, deren Waren keiner braucht und deren Lager voll ist
	for b in w.buildings:
		if not b.complete or not b.def.has("production"):
			continue
		var outs: Dictionary = b.prod_def().get("outputs", {})
		if outs.is_empty() or outs.keys().any(func(o): return need.has(str(o)) or Game.space_for(str(o), w) > 0):
			continue
		out.append({"id": b.type, "text": Loc.t("%s: Lager voll, wird gerade nicht gebraucht") % b.def.name, "ok": true, "extra": true})
	return out


## Die nächsten noch nicht gebauten, freigeschalteten Gebäude (ohne Schmuck und Wege), höchstens 3.
static func _next_buildings(w) -> Array:
	var out := []
	for t in Data.buildings:
		var d: Dictionary = Data.buildings[t]
		if not d.get("buildable", false) or not Game.is_unlocked(t) or d.has("decor") or d.has("tile") or d.get("ground", false):
			continue
		if w.buildings.any(func(b): return b.type == t or b.def.get("base", "") == t):
			continue
		out.append(t)
	out.sort_custom(func(a, b): return int(Data.techs.get(Data.buildings[a].get("requires", ""), {}).get("tier", 0)) > int(Data.techs.get(Data.buildings[b].get("requires", ""), {}).get("tier", 0)))
	return out.slice(0, 3)


## Welches Gebäude stellt die Ware her (das erste freigeschaltete)?
static func _maker(_w, id: String) -> String:
	for t in Data.buildings:
		var d: Dictionary = Data.buildings[t]
		if d.has("production") and d.production.get("outputs", {}).has(id) and Game.is_unlocked(t) and d.get("buildable", false):
			return t
	return ""


# ---------------------------------------------------------------- Karte
## Karte einer Insel (ein Pixel-Quadrat je Feld): Wasser, Sand, Gras, Gebäude, Straßen, vorgeschlagene
## Straßen (orange), alter Platz (rot umrandet) und neuer Platz (grün) der Gebäude zum Verschieben.
static func map_image(w, rep: Dictionary, px: int = 4) -> ImageTexture:
	var n: int = w.size
	var img := Image.create(n * px, n * px, false, Image.FORMAT_RGBA8)
	var col_water := Color("#4a7fb5")
	var col_sand := Color("#e6d49a")
	var col_grass := Color("#7fae5a")
	var col_bld := Color("#8a5a3a")
	var col_road := Color("#9a9a9a")
	for y in n:
		for x in n:
			var c := Vector2i(x, y)
			var t: int = w.terrain_at(c)
			var col := col_water if t == 0 else (col_sand if t == 1 else col_grass)
			if w.building_at.has(c):
				var b = w.building_at[c]
				col = col_road if b.def.get("tile", "") == "road" else (col_bld if not b.is_ground() else col.darkened(0.15))
			img.fill_rect(Rect2i(x * px, y * px, px, px), col)
	for r in rep.get("roads", []):
		img.fill_rect(Rect2i(int(r[0]) * px, int(r[1]) * px, px, px), Color("#ff9a1f"))
	for m in rep.get("moves", []):
		var sz: Array = m.size
		var fr := Rect2i(int(m.from[0]) * px, int(m.from[1]) * px, int(sz[0]) * px, int(sz[1]) * px)
		_frame(img, fr, Color("#d03030"))
		img.fill_rect(Rect2i(int(m.to[0]) * px, int(m.to[1]) * px, int(sz[0]) * px, int(sz[1]) * px), Color("#2fbf4a"))
	return ImageTexture.create_from_image(img)


static func _frame(img: Image, r: Rect2i, col: Color) -> void:
	img.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, 2), col)
	img.fill_rect(Rect2i(r.position.x, r.end.y - 2, r.size.x, 2), col)
	img.fill_rect(Rect2i(r.position.x, r.position.y, 2, r.size.y), col)
	img.fill_rect(Rect2i(r.end.x - 2, r.position.y, 2, r.size.y), col)
