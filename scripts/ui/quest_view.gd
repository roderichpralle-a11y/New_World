class_name QuestView
extends RefCounted
## Oberflaeche der Auftraege (Teil D, Logik in Quests): das Fenster "Auftraege" (drei Angebote oder der
## laufende Auftrag, Segen und Bauplaene) und die Zeile "Auftrag" auf der Zielkarte (GoalCard).

const BOX_BG := Color("#f3e3c0")
const BOX_LINE := Color("#b07a3a")
const HEAD := Color("#7a4a28")
const GREEN := Color("#2f6a3a")


static func _box_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BOX_BG
	sb.border_color = BOX_LINE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func _wrap(text: String, size: int, min_w: float, color: Color = UiTheme.TEXT, bold: bool = false) -> Label:
	var l := UiTheme.label(text, size, color, bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = min_w
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


# ---------------------------------------------------------------- Fenster
## Fenster "Auftraege" (hud._quest_panel). Wird bei Quests.changed neu gebaut, Zeiten und Fortschritt
## alle 0,5 s aufgefrischt.
static func build_panel(hud) -> PanelContainer:
	var r: Array = hud._popup_panel(Loc.t("Aufträge"))
	var p: PanelContainer = r[0]
	var v: VBoxContainer = r[1]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(330, 330)
	v.add_child(scroll)
	var m := MarginContainer.new()  # Abstand rechts fuer die Bildlaufleiste
	m.add_theme_constant_override("margin_right", 14)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(box)
	p.set_meta("box", box)
	p.visibility_changed.connect(func():
		if p.visible:
			fill(box, hud))
	Quests.changed.connect(func():
		if is_instance_valid(p) and p.visible:
			fill(box, hud))
	var t := Timer.new()
	t.wait_time = 0.5
	t.ignore_time_scale = true
	t.autostart = true
	t.timeout.connect(func():
		if p.visible:
			refresh(box))
	p.add_child(t)
	return p


static func refresh(box: Control) -> void:
	for u in box.get_meta("upd", []):
		u.call()


static func fill(box: VBoxContainer, hud) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var upd := []
	if not Quests.active.is_empty():
		box.add_child(UiTheme.label(Loc.t("Laufender Auftrag"), 16, HEAD, true))
		box.add_child(_quest_box(Quests.active, -1, hud, upd))
	elif not Quests.offers.is_empty():
		var info := _wrap("", 13, 260)
		upd.append(func(): info.text = Loc.t("Wähle einen Auftrag. Die Angebote gelten noch %s.") % Quests.duration_text(Quests.offers_until - Game.time_days, false))
		box.add_child(info)
		for i in Quests.offers.size():
			box.add_child(_quest_box(Quests.offers[i], i, hud, upd))
		var rr := UiTheme.button("", "schnell", 40)
		rr.add_theme_font_size_override("font_size", 14)
		rr.tooltip_text = Loc.t("Drei neue Angebote. Danach gibt es erst nach einem Tag wieder andere.")
		rr.pressed.connect(func():
			var err := Quests.reroll()
			if err != "":
				hud.toast(err, "ziel"))
		upd.append(func():
			rr.disabled = not Quests.can_reroll()
			rr.text = Loc.t("Andere Aufträge") if not rr.disabled else Loc.t("Andere Aufträge (in %s)") % Quests.duration_text(Quests.reroll_at - Game.time_days, false))
		box.add_child(rr)
	else:
		var wait := _wrap("", 13, 260)
		upd.append(func():
			if Quests.next < 0.0:
				wait.text = Loc.t("Aufträge gibt es nach der Einführung.")
			else:
				wait.text = Loc.t("Neue Aufträge kommen in %s.") % Quests.duration_text(Quests.next - Game.time_days, false))
		box.add_child(wait)
	if not Quests.last.is_empty():
		var ok: bool = Quests.last.get("ok", false)
		box.add_child(_wrap(Loc.t("Zuletzt: geschafft (Tag %d).") % int(Quests.last.get("day", 0)) if ok
			else Loc.t("Zuletzt: nicht geschafft (Tag %d).") % int(Quests.last.get("day", 0)), 12, 260, GREEN if ok else UiTheme.BAD))
	box.add_child(HSeparator.new())
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 6)
	bh.add_child(UiTheme.icon_rect(Data.icon("sonne"), 18))
	bh.add_child(UiTheme.label(Loc.t("Segen und Baupläne"), 15, HEAD, true))
	box.add_child(bh)
	var any := false
	for k in Quests.boons:
		any = true
		box.add_child(_wrap(Loc.t("Segen: %s") % Quests.boon_text(str(k), float(Quests.boons[k])), 13, 260))
	for t in Quests.plans:
		any = true
		box.add_child(_wrap(Loc.t("Bauplan: %s") % GoalChecks.building_name(str(t)), 13, 260))
	if not any:
		box.add_child(_wrap(Loc.t("Noch keine. Segen wirken für immer (mit Obergrenze), ein Bauplan erlaubt ein Gebäude ohne die Forschung."), 12, 260))
	var st := Quests.qstats
	box.add_child(_wrap(Loc.t("Erledigt: %d, nicht geschafft: %d, aufgegeben: %d") % [int(st.get("done", 0)), int(st.get("failed", 0)), int(st.get("abandoned", 0))], 12, 260, Color("#6e5a50")))
	box.set_meta("upd", upd)
	refresh(box)


## Kasten eines Auftrags: Symbol und Text, Fortschritt bzw. Frist, Belohnung und Knopf
## (i >= 0: Angebot mit "Annehmen", sonst der laufende Auftrag mit "Aufgeben").
static func _quest_box(q: Dictionary, i: int, hud, upd: Array) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box_style())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var ic := UiTheme.icon_rect(GoalChecks.icon(q.get("check", {})), 24)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	h.add_child(_wrap(Quests.text_of(q), 15, 220, UiTheme.TEXT, true))
	v.add_child(h)
	if i < 0:
		var pr := HBoxContainer.new()
		pr.add_theme_constant_override("separation", 6)
		var bar := UiTheme.bar(UiTheme.GOOD, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pr.add_child(bar)
		var val := UiTheme.label("", 13, UiTheme.TEXT, true)
		pr.add_child(val)
		v.add_child(pr)
		var tl := _wrap("", 13, 220)
		v.add_child(tl)
		upd.append(func():
			if Quests.active.is_empty():
				return
			bar.value = 100.0 * Quests.progress_ratio(Quests.active)
			val.text = Quests.progress_text(Quests.active)
			tl.text = Loc.t("Zeit: noch %s") % Quests.duration_text(float(Quests.active.get("until", 0.0)) - Game.time_days, false))
	else:
		var fixed := float(q.get("until", -1.0)) > 0.0
		var tl := _wrap("", 12, 220, Color("#5a4038"))
		upd.append(func():
			if fixed:
				tl.text = Loc.t("Frist: noch %s") % Quests.duration_text(float(q.until) - Game.time_days, false)
			else:
				tl.text = Loc.t("Frist: %s ab dem Annehmen") % Quests.duration_text(float(q.get("days", 4.0)), false))
		v.add_child(tl)
	var rw := HBoxContainer.new()  # Belohnung und Knopf in einer Zeile
	rw.add_theme_constant_override("separation", 6)
	var ri := UiTheme.icon_rect(Quests.reward_icon(q.get("reward", {})), 20)
	ri.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rw.add_child(ri)
	var rl := _wrap(Loc.t("Belohnung: %s") % Quests.reward_text(q.get("reward", {})), 13, 120, GREEN, true)
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rw.add_child(rl)
	v.add_child(rw)
	var b: Button
	if i >= 0:
		b = UiTheme.button(Loc.t("Annehmen"), "haken", 40)
		var idx := i
		b.pressed.connect(func():
			var err := Quests.accept(idx)
			if err != "":
				hud.toast(err, "ziel"))
	else:
		b = UiTheme.button(Loc.t("Aufgeben"), "abriss", 40)
		b.tooltip_text = Loc.t("Kostet nichts. Neue Angebote kommen nach einer kurzen Pause.")
		var armed := [false]
		b.pressed.connect(func():
			if not armed[0]:
				armed[0] = true
				b.text = Loc.t("Wirklich aufgeben?")
				return
			Quests.abandon())
	b.add_theme_font_size_override("font_size", 14)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rw.add_child(b)
	return p


# ---------------------------------------------------------------- Zielkarte
## Zeile "Auftrag" unter dem Ziel auf der Zielkarte. Tippen oeffnet das Fenster "Auftraege".
static func goal_row(card) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = Loc.t("Tippen: Aufträge öffnen")
	row.visible = false
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sep)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(head)
	var ic := UiTheme.icon_rect(Data.icon("ziel"), 16)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var title := UiTheme.label("", 12, Color("#8a5a3a"), true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	var btn := UiTheme.button("", "", 22)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(func(): card.hud._toggle(card.hud._quest_panel))
	head.add_child(btn)
	var text := UiTheme.label("", 12, UiTheme.TEXT, false)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 150
	row.add_child(text)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 5)
	br.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(br)
	var bar := UiTheme.bar(UiTheme.GOOD, 6)
	bar.custom_minimum_size.x = 40
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(bar)
	var val := UiTheme.label("", 11, UiTheme.TEXT, true)
	br.add_child(val)
	var tl := UiTheme.label("", 11, Color("#5a4038"))
	br.add_child(tl)
	row.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			card.hud._toggle(card.hud._quest_panel))
	row.set_meta("w", {"sep": sep, "ic": ic, "title": title, "btn": btn, "text": text, "br": br, "bar": bar, "val": val, "tl": tl})
	return row


## Gibt es etwas fuer die Zeile (laufender Auftrag oder Angebote)? Das Brett oeffnet erst nach
## der Einfuehrung, bei alten Spielstaenden gleich nach dem Laden (dann auch neben der Einfuehrung).
static func row_wanted(card) -> bool:
	return Quests.has_content() and (not card.in_tutorial() or Quests.next >= 0.0)


## Zeile auffrischen; true, wenn sich die Hoehe aendern kann (Zielkarte neu anordnen).
static func update_row(row: Control, card, with_sep: bool) -> bool:
	var want := row_wanted(card)
	var was := row.visible
	row.visible = want
	if not want:
		return was
	var w: Dictionary = row.get_meta("w")
	var old_text: String = w.text.text
	w.sep.visible = with_sep
	if not Quests.active.is_empty():
		var q: Dictionary = Quests.active
		w.title.text = Loc.t("Auftrag")
		w.ic.texture = GoalChecks.icon(q.get("check", {}))
		w.btn.text = Loc.t("Details")
		w.text.text = Quests.text_of(q)
		w.br.visible = true
		w.bar.value = 100.0 * Quests.progress_ratio(q)
		w.val.text = "" if q.get("survive", false) else Quests.progress_text(q)
		w.val.visible = w.val.text != ""
		w.tl.text = Quests.duration_text(float(q.get("until", 0.0)) - Game.time_days)
	else:
		w.title.text = Loc.t("Aufträge")
		w.ic.texture = Data.icon("ziel")
		w.btn.text = Loc.t("Wählen (%d)") % Quests.offers.size()
		w.text.text = Loc.t("Neue Angebote: Wähle einen Auftrag aus.")
		w.br.visible = false
	return not was or old_text != w.text.text
