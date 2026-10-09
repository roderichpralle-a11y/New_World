class_name IslandTraits
## Inselstärken und Gewürze (Regeln ab Version 2, "Herausforderung").
##
## Inselstärken: buildings.json `biome_bonus` {Inselart: Faktor}. Eine Werkstatt auf einer passenden
## Insel arbeitet so viel schneller (Arbeitszeit / Faktor, siehe Settler._plan_production). Felseninsel:
## Mine x2, Steinbruch und Stahlwerk x1,5; Waldinsel: Sägegrube, Köhlerei, Papiermühle x1,5;
## Palmeninsel: Räucherei, Konservenfabrik, Solarpark x1,5; die Heimatinsel hat keine (Allrounder).
##
## Gewürze: der Gewürzstrauch wächst nur auf Palmeninseln (islands.json "extra", eigener Durchgang im
## Generator, IslandGen._place_extra). Ältere Spielstände bekommen die Sträucher beim Laden auf freien
## Feldern (patch_spice). Sammler pflücken Gewürze zuerst, solange die Insel genug Essen hat
## (spice_first).
##
## Die Anzeige-Helfer (build_row, info_rows, strength_row) hängen je eine Zeile an; hud.gd und
## sea_panel.gd rufen sie mit je einer Zeile auf.

const DIM := Color("#8a5a3a")


# ---------------------------------------------------------------- Inselstärken
## Tempo-Faktor eines Gebäudetyps auf einer Inselart (1 = kein Bonus).
static func factor(type: String, biome: String) -> float:
	var bb = Data.buildings.get(type, {}).get("biome_bonus", {})
	if bb is Dictionary:
		return maxf(0.1, float(bb.get(biome, 1.0)))
	return 1.0


## Stärken einer Inselart: [[Gebäudetyp, Faktor], ...] in der Reihenfolge von buildings.json.
static func strengths(biome: String) -> Array:
	var out := []
	for t in Data.buildings:
		var f := factor(t, biome)
		if f > 1.0:
			out.append([t, f])
	return out


## Inselarten, auf denen ein Gebäude schneller arbeitet: [[Inselart, Faktor], ...].
static func good_biomes(type: String) -> Array:
	var out := []
	var bb = Data.buildings.get(type, {}).get("biome_bonus", {})
	if bb is Dictionary:
		for b in bb:
			if float(bb[b]) > 1.0:
				out.append([str(b), float(bb[b])])
	return out


static func biome_name(biome: String) -> String:
	return str(Data.islands.get(biome, {}).get("name", biome))


## Kurzer Text für die Bauliste und das Infofenster ("" = keine Stärke).
## "x1,5" (deutsch mit Komma) bzw. "x1.5".
static func times(f: float) -> String:
	var t := "x%.1f" % f
	return t.replace(".", ",") if Loc.language == "de" else t


static func bonus_text(type: String, biome: String) -> String:
	var f := factor(type, biome)
	if f > 1.0:
		return Loc.t("Inselstärke: hier %s so schnell") % times(f)
	var parts := []
	for e in good_biomes(type):
		parts.append("%s %s" % [biome_name(e[0]), times(float(e[1]))])
	if parts.is_empty():
		return ""
	return Loc.t("Schneller auf: %s") % ", ".join(parts)


## Bauliste: eine Zeile unter der Beschreibung (grün, wenn die Insel passt), Knopf wird höher.
static func build_row(btn: Control, box: Control, type: String, w) -> void:
	var biome: String = w.biome if w and is_instance_valid(w) else "heimat"
	var text := bonus_text(type, biome)
	if text == "":
		return
	var l := UiTheme.label(text, 12, UiTheme.GOOD if factor(type, biome) > 1.0 else DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 170
	box.add_child(l)
	btn.custom_minimum_size.y += 16.0 if text.length() <= 34 else 30.0


## Infofenster einer Werkstatt: Inselstärke dieser Insel bzw. wo das Gebäude schneller wäre.
static func info_rows(hud, b) -> void:
	var biome: String = b.world.biome if b.world else "heimat"
	var text := bonus_text(b.type, biome)
	if text == "":
		return
	var l := UiTheme.label(text, 13, UiTheme.GOOD if b.biome_factor() > 1.0 else DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud._info_box.add_child(l)


## Seekarte (Inselansicht): "Stärken:" mit den Gebäuden, die auf dieser Inselart schneller arbeiten.
static func strength_row(box: Control, m: Dictionary) -> void:
	var list := strengths(str(m.get("biome", "heimat")))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 2)
	flow.add_child(UiTheme.label(Loc.t("Stärken:"), 13))
	if list.is_empty():
		flow.add_child(UiTheme.label(Loc.t("keine besonderen, dafür von allem etwas"), 13, DIM))
	for e in list:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 2)
		h.add_child(UiTheme.icon_rect(Data.building_tex(e[0]), 18))
		h.add_child(UiTheme.label("%s %s" % [Data.buildings[e[0]].name, times(float(e[1]))], 13, UiTheme.GOOD))
		flow.add_child(h)
	box.add_child(flow)


# ---------------------------------------------------------------- Gewürze
## Älterer Spielstand: hat eine Insel, auf der der Generator Gewürzsträucher setzt (Palmeninsel), noch
## keinen, kommen sie einmalig auf ihre Plätze, soweit frei (kein Rohstoff, kein Gebäude und keines
## direkt daneben, damit kein Eingang zugestellt wird). Sträucher wachsen nach und verschwinden nie;
## sobald einer steht, passiert beim nächsten Laden nichts mehr. Liefert die Zahl neuer Sträucher.
static func patch_spice(w, island: Dictionary) -> int:
	var want: Array = island.get("nodes", []).filter(func(n): return n.type == "gewuerzstrauch")
	if want.is_empty() or w.nodes.any(func(n): return n.type == "gewuerzstrauch"):
		return 0
	var placed := 0
	for e in want:
		var c: Vector2i = e.cell
		if not w.is_inside(c) or w.is_water(c) or w.node_at.has(c):
			continue
		var free := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if w.building_at.has(c + Vector2i(dx, dy)):
					free = false
		if not free:
			continue
		w.spawn_node("gewuerzstrauch", c, int(e.get("variant", -1)))
		placed += 1
	if placed > 0:
		Game.queue_note(Loc.t("Auf %s wachsen jetzt %d Gewürzsträucher. Sammler pflücken die Gewürze.") % [Sea.island_name(w), placed], "gewuerze", "lager")
	return placed


## Sammler: Gewürze nur, solange die Insel Essen für 10 Mahlzeiten je Siedler hat, dann aber zuerst;
## sonst sammeln sie nur Essen.
static func gather_order(targets: Array, w) -> Array:
	if not "gewuerzstrauch" in targets or w == null:
		return targets
	var out := targets.filter(func(t): return t != "gewuerzstrauch")
	if Game.total_food(w) >= w.settlers.size() * 10:
		out.push_front("gewuerzstrauch")
	return out
