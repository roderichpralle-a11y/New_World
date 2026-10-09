class_name ExamView
extends RefCounted
## Oberflaeche der Pruefungen und der Wertung (Teil J, Logik in Exams): der Kasten unter der
## Ueberschrift des naechsten Zeitalters im Forschungsfenster und das Fenster "Wertung" (Menue).

const BOX_BG := Color("#f3e3c0")
const BOX_LINE := Color("#b07a3a")
const HEAD := Color("#7a4a28")


## Kasten der Pruefung i (oeffnet das Zeitalter i+1): je Bedingung Symbol, Text und "wert/ziel",
## darunter die Belohnung. refresh(box) aktualisiert Werte und Farben.
static func exam_box(i: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_meta("exam_box", i)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BOX_BG
	sb.border_color = BOX_LINE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(UiTheme.icon_rect(Data.icon("zeitalter"), 20))
	var t := UiTheme.label(Loc.t("Prüfung für das Zeitalter %s") % Data.age_name(i + 1), 15, HEAD, true)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 220
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	v.add_child(head)
	var info := UiTheme.label(Loc.t("Sind alle Bedingungen erfüllt, ist die Prüfung bestanden. Waren werden nur gezählt (alle Inseln), nicht verbraucht."), 12)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 260
	v.add_child(info)
	var rows := []
	for x in Exams.status(i):
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var ic := UiTheme.icon_rect(GoalChecks.icon(x[0]), 16)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var l := UiTheme.label(GoalChecks.label(x[0]), 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 180
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var val := UiTheme.label("", 13, UiTheme.TEXT, true)
		val.custom_minimum_size.x = 64
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(val)
		v.add_child(h)
		rows.append([ic, l, val, GoalChecks.icon(x[0])])
	var rw := UiTheme.label(Loc.t("Belohnung: %s.") % Exams.reward_text(i), 12, Color("#2f6a3a"))
	rw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rw.custom_minimum_size.x = 260
	v.add_child(rw)
	p.set_meta("rows", rows)
	refresh(p)
	return p


## Werte und Farben: erfuellt = Haken und gruen, sonst das Symbol blass und der Wert rot.
static func refresh(box: Control) -> void:
	if box == null or not is_instance_valid(box) or not box.has_meta("rows"):
		return
	var st := Exams.status(int(box.get_meta("exam_box", 0)))
	var rows: Array = box.get_meta("rows")
	for k in mini(rows.size(), st.size()):
		var r: Array = rows[k]
		var x: Array = st[k]
		var met: bool = x[3]
		r[0].texture = Data.icon("haken") if met else r[3]
		r[0].modulate = Color.WHITE if met else Color(1, 1, 1, 0.45)
		r[1].add_theme_color_override("font_color", UiTheme.TEXT if met else Color("#5a4038"))
		r[2].text = "%d/%d" % [int(x[1]), int(x[2])]
		r[2].add_theme_color_override("font_color", Color("#2f6a3a") if met else UiTheme.BAD)


# ---------------------------------------------------------------- Wertung
## Fenster "Wertung" (Menue): Punkte je Kategorie, Summe und die Rekorde dieses Geraets.
static func build_score_panel(hud) -> PanelContainer:
	var r: Array = hud._popup_panel(Loc.t("Wertung"))
	var p: PanelContainer = r[0]
	var v: VBoxContainer = r[1]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(330, 290)
	v.add_child(scroll)
	var m := MarginContainer.new()  # Abstand rechts fuer die Bildlaufleiste
	m.add_theme_constant_override("margin_right", 14)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(box)
	p.visibility_changed.connect(func():
		if p.visible:
			fill_score(box))
	return p


static func fill_score(box: VBoxContainer) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 3)
	box.add_child(g)
	var cells := [[Loc.t("Kategorie"), true, false], [Loc.t("Wert"), true, true], [Loc.t("Punkte"), true, true]]
	for row in Exams.score_parts():
		cells.append_array([[str(row[0]), false, false], [str(row[1]), false, true], [str(row[2]), false, true]])
	cells.append_array([[Loc.t("Summe"), true, false], ["", true, true], [str(Exams.score()), true, true]])
	for i in cells.size():
		var c: Array = cells[i]
		var l := UiTheme.label(c[0], 14 if i >= cells.size() - 3 else 13, HEAD if c[1] else UiTheme.TEXT, c[1])
		if i % 3 == 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.custom_minimum_size.x = 170
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			l.custom_minimum_size.x = 52
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		g.add_child(l)
	box.add_child(HSeparator.new())
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 6)
	rh.add_child(UiTheme.icon_rect(Data.icon("ziel"), 18))
	rh.add_child(UiTheme.label(Loc.t("Rekorde"), 16, HEAD, true))
	box.add_child(rh)
	var note := UiTheme.label(Loc.t("Gelten für alle Spielstände auf diesem Gerät. Grün: in diesem Spiel erreicht."), 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 260
	box.add_child(note)
	var rec := Exams.records()
	var keys := ["score", "max_pop", "best_streak", "days"]
	for i in range(1, Data.ages.size()):
		keys.append("age_%d" % i)
	var rg := GridContainer.new()
	rg.columns = 2
	rg.add_theme_constant_override("h_separation", 10)
	rg.add_theme_constant_override("v_separation", 3)
	box.add_child(rg)
	var any := false
	for k in keys:
		if not rec.has(k):
			continue
		any = true
		var mine: bool = k in Exams.beaten
		var col: Color = Color("#2f6a3a") if mine else UiTheme.TEXT
		var nl := UiTheme.label(Exams.record_name(k), 13, col, mine)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.custom_minimum_size.x = 190
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rg.add_child(nl)
		var vl := UiTheme.label(Exams.record_value_text(k, int(rec[k])), 13, col, mine)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.custom_minimum_size.x = 80
		rg.add_child(vl)
	if not any:
		box.add_child(UiTheme.label(Loc.t("Noch keine Rekorde."), 13))
