class_name NeedsInfo
## Anzeige der Bedürfnisstufen (HouseNeeds) im Infofenster und in der Bauliste. hud.gd ruft diese
## statischen Helfer mit je einer Zeile auf; sie hängen Zeilen an hud._info_box und halten sie über
## hud._updaters aktuell (alle 0,5 s).

const DIM := Color("#6e5a50")


static func _status_color(v: float) -> Color:
	if v >= 0.7:
		return UiTheme.GOOD
	if v >= 0.4:
		return UiTheme.ACCENT
	return UiTheme.BAD


static func _need_icon(nd: Dictionary) -> Texture2D:
	if nd.has("icon"):
		return Data.icon(str(nd.icon))
	return Data.res_icon(str(nd.get("good", "")))


## Verbraucher eines Hauses: Erwachsene 1, Kinder child_weight.
static func _consumers(b) -> float:
	var n := 0.0
	for s in b.residents():
		n += 1.0 if s.is_adult() else float(HouseNeeds.cfg.get("child_weight", 0.5))
	return n


## Zahl mit einer Nachkommastelle, im Deutschen mit Komma ("2,4").
static func _num(v: float) -> String:
	var t := "%.1f" % v
	return t.replace(".", ",") if Loc.language == "de" else t


## Kurzer Wert einer Bedarfszeile für dieses Haus (je Tag, Vorrat, Sorten ...).
static func _need_value(w, nd: Dictionary, cons: float) -> String:
	match str(nd.get("kind", "")):
		"good":
			return Loc.t("%s/Tag") % _num(float(nd.get("rate", 0.0)) * cons)
		"stock":
			var have := 0
			for g in nd.get("goods", []):
				have += Game.amount(str(g), w)
			return Loc.t("Vorrat %d (braucht %d)") % [have, ceili(float(nd.get("per", 0.5)) * cons)]
		"variety":
			return Loc.t("%d Sorten (braucht %d)") % [Game.food_variety(w), int(nd.get("sorts", 3))]
		"building":
			return Loc.t("vorhanden") if HouseNeeds.need_sat(w, str(nd.id)) >= 0.5 else Loc.t("fehlt")
		"food":
			var fd := Game.food_days(w)
			return Loc.t("%s Tage") % _num(maxf(fd, 0.0))
		"warm":
			return Loc.t("warm") if Seasons.is_warm(w) else Loc.t("friert")
	return ""


## Haus: Stufe, effektive Stufe, Zufriedenheit und je Bedürfnis eine kurze Zeile.
static func house_rows(hud, b) -> void:
	var lv: int = b.house_level()
	if lv <= 0 or not b.complete:
		return
	var box: VBoxContainer = hud._info_box
	var w = b.world
	box.add_child(UiTheme.label(Loc.t("Hausstufe %d: %s") % [lv, HouseNeeds.level_name(lv)], 15, UiTheme.TEXT, true))
	var drop := UiTheme.label("", 12, UiTheme.BAD)
	drop.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(drop)
	var bar: ProgressBar = null
	if lv >= 2:
		bar = hud._bar_row(Loc.t("Zufriedenheit"), 0.0, UiTheme.GOOD)
	var rows := []
	for k in range(1, lv + 1):
		var head := Loc.t("Hausstufe %d: %s") % [k, HouseNeeds.level_name(k)]
		if k == 1 and lv >= 2:
			head += Loc.t(" (zählt nicht für die Zufriedenheit)")
		box.add_child(UiTheme.label(head, 12, DIM, true))
		for nd in HouseNeeds.level_needs(k):
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 4)
			h.add_child(UiTheme.icon_rect(_need_icon(nd), 16))
			var nl := UiTheme.label(HouseNeeds.need_label(nd), 13)
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			nl.clip_text = true
			h.add_child(nl)
			var vl := UiTheme.label("", 13, UiTheme.TEXT, true)
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.add_child(vl)
			box.add_child(h)
			rows.append([nd, vl])
	var upd := func():
		if not is_instance_valid(b):
			return
		var eff := HouseNeeds.effective_level(b)
		drop.visible = eff < lv
		var miss := HouseNeeds.missing_text(w, eff + 1)
		drop.text = Loc.t("Zählt nur als Hausstufe %d (%s), es fehlt: %s. Eine Hausstufe zählt erst, wenn auch alle Stufen darunter erfüllt sind. Bis dahin keine Fachkräfte ab Hausstufe %d und kein Kinder-Bonus.") % [eff, HouseNeeds.level_name(eff), miss if miss != "" else HouseNeeds.level_name(eff + 1), eff + 1]
		if bar:
			var v := HouseNeeds.house_sat(b)
			bar.value = v * 100.0
			var sb = bar.get_theme_stylebox("fill")
			if sb is StyleBoxFlat:
				sb.bg_color = UiTheme.GOOD if eff >= lv else UiTheme.BAD
		var cons := _consumers(b)
		for r in rows:
			var nd: Dictionary = r[0]
			var vl: Label = r[1]
			vl.text = _need_value(w, nd, cons)
			vl.add_theme_color_override("font_color", _status_color(HouseNeeds.need_sat(w, str(nd.id))))
	upd.call()
	hud._updaters.append(upd)


## Werkstatt oder Forschungsplatz ab Stufe 2: Arbeiterstufe und Fachkräfte der Insel.
static func worker_rows(hud, b) -> void:
	var lv: int = b.worker_level()
	if lv < 2:
		return
	var box: VBoxContainer = hud._info_box
	var w = b.world
	box.add_child(UiTheme.label(Loc.t("Arbeiter ab Hausstufe %d (%s)") % [lv, HouseNeeds.level_name(lv)], 13, UiTheme.TEXT, true))
	var pl := UiTheme.label("", 13)
	box.add_child(pl)
	var hint := UiTheme.label("", 12, UiTheme.BAD)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var upd := func():
		if not is_instance_valid(b):
			return
		var k := HouseNeeds.pool_block(w, b)
		# eigene Stufe zeigen; eine niedrigere nur, wenn dort alle Fachkräfte schon arbeiten
		var kk := lv
		if k > 0 and int(HouseNeeds.pool(w, lv)[1]) > 0:
			kk = k
		var p := HouseNeeds.pool(w, kk)
		var stuck: bool = k > 0 and b.free_slots() > 0
		pl.text = Loc.t("Fachkräfte Hausstufe %d: %d / %d") % [kk, int(p[0]), int(p[1])]
		pl.add_theme_color_override("font_color", UiTheme.BAD if stuck else UiTheme.TEXT)
		hint.visible = stuck
		if int(p[1]) == 0:
			hint.text = Loc.t("Es braucht zufriedene Häuser ab Hausstufe %d (%s, z. B. %s).") % [kk, HouseNeeds.level_name(kk), HouseNeeds.level_house(kk)]
		else:
			hint.text = Loc.t("Alle Fachkräfte dieser Hausstufe arbeiten schon. Mehr zufriedene Häuser ab Hausstufe %d helfen.") % kk
	upd.call()
	hud._updaters.append(upd)


## Ausbau eines Hauses ab Stufe 2: erst, wenn seine Bedürfnisse erfüllt sind (Knopf gesperrt).
static func upgrade_gate(hud, b, ub: Button) -> void:
	if b.house_level() < 2:
		return
	var l := UiTheme.label("", 12, UiTheme.BAD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud._info_box.add_child(l)
	var upd := func():
		if not is_instance_valid(b):
			return
		var full := HouseNeeds.full_level(b)
		ub.disabled = not full
		l.visible = not full
		l.text = Loc.t("Erst müssen die Bedürfnisse des Hauses erfüllt sein (%d %%).") % roundi(HouseNeeds.house_sat(b) * 100.0)
	upd.call()
	hud._updaters.append(upd)


## " · Bürger" hinter dem Zuhause eines Siedlers (die Stufe, als die das Haus gerade zählt).
static func home_suffix(home) -> String:
	if home == null or home.house_level() <= 0:
		return ""
	return " · " + HouseNeeds.level_name(maxi(1, HouseNeeds.effective_level(home)))


## Zusatz für die Bauliste: Hausstufe und neue Bedürfnisse bzw. Arbeiterstufe.
static func build_desc(type: String) -> String:
	var d: Dictionary = Data.buildings.get(type, {})
	if d.has("housing"):
		var lv := int(d.get("level", 1))
		var names := HouseNeeds.level_needs(lv).map(func(nd): return HouseNeeds.need_label(nd))
		if lv <= 1:
			return " " + Loc.t("Hausstufe %d (%s), braucht: %s.") % [lv, HouseNeeds.level_name(lv), ", ".join(names)]
		return " " + Loc.t("Hausstufe %d (%s), braucht zusätzlich: %s.") % [lv, HouseNeeds.level_name(lv), ", ".join(names)]
	var wl := int(d.get("worker_level", 1))
	if wl >= 2:
		return " " + Loc.t("Arbeiter ab Hausstufe %d (%s).") % [wl, HouseNeeds.level_name(wl)]
	return ""
