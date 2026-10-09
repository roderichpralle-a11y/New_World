class_name TradePanel
extends PanelContainer
## Handelsfenster der fremden Händler (Merchant): wer da ist, wie lange noch, Gold dieser Insel und die
## festen Lose ("Er verkauft" mit "Kaufen", "Er kauft" mit "Verkaufen"). Gehandelt wird immer mit dem
## Lager der Insel, an der der Händler liegt. Offen über den Händler-Knopf oben rechts (hud.top_alerts),
## das Infofenster eines Hafens (harbor_rows) und die Seekarte (sea_rows). Zeilen sind höchstens
## ~320 px breit und Knöpfe 36 px hoch, damit es auch auf einem 360 px breiten Handy passt.

const DIM := Color("#8a5a3a")
const BADGE := Color("#e0a830")
const BADGE_SOON := Color("#c9b88e")
const HELP := """[b]Inselstärken, Gewürze und Händler[/b]
Jede Inselart hat Stärken: Auf Felseninseln arbeiten Mine, Steinbruch und Stahlwerk schneller, auf Waldinseln Sägegrube, Köhlerei und Papiermühle, auf Palmeninseln Räucherei, Konservenfabrik und Solarpark. Die Bauliste und die Seekarte zeigen, wo ein Gebäude schneller ist. Gewürze wachsen nur auf Palmeninseln; Sammler pflücken sie, wenn genug Essen da ist. Städter in Mietshäusern brauchen sie.
Hat eine Insel einen Hafen (auch die Werft zählt), kommen fremde Händler. Sie werden einen Tag vorher angekündigt und bleiben einen Tag. Tippe oben rechts auf das Händler-Symbol: Sie verkaufen Werkzeug, Eisen, Gewürze und mehr, dazu einfache Waren wie Holz, Stein und Bretter, gegen Gold und kaufen deine Waren, auch einfache. Gehandelt wird mit dem Lager der Insel, an der der Händler liegt."""

var hud
var _title: Label
var _info: Label
var _gold_row: HBoxContainer
var _gold: Label
var _hint: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _badge: Button
var _badge_sb: StyleBoxFlat
var _badge_sig := "?"
var _next_ms := 0


func setup(p_hud) -> void:
	hud = p_hud
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UiTheme.icon_rect(Data.icon("haendler"), 24))
	_title = UiTheme.label(tr("Fremder Händler"), 19, UiTheme.TEXT, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	head.add_child(_title)
	var x := UiTheme.button("", "abriss", 36)
	x.tooltip_text = tr("Schließen")
	x.pressed.connect(func(): visible = false)
	head.add_child(x)
	v.add_child(head)
	_info = UiTheme.label("", 13)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_info)
	_gold_row = HBoxContainer.new()
	_gold_row.add_theme_constant_override("separation", 4)
	_gold_row.add_child(UiTheme.icon_rect(Data.res_icon("gold"), 18))
	_gold = UiTheme.label("", 15, UiTheme.TEXT, true)
	_gold_row.add_child(_gold)
	v.add_child(_gold_row)
	_hint = UiTheme.label("", 12, DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_hint)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_fit()
	# Händler-Knopf oben rechts (neben der Geschwindigkeit)
	_badge = Button.new()
	_badge.icon = Data.icon("haendler")
	_badge.expand_icon = false
	_badge.custom_minimum_size = Vector2(34, 34)
	_badge.focus_mode = Control.FOCUS_NONE
	_badge.visible = false
	_badge_sb = StyleBoxFlat.new()
	_badge_sb.set_corner_radius_all(5)
	_badge_sb.set_border_width_all(2)
	for st in ["normal", "hover", "pressed"]:
		_badge.add_theme_stylebox_override(st, _badge_sb)
	_badge.pressed.connect(func():
		Sound.play("klick")
		open())
	hud.top_alerts.add_child(_badge)
	Merchant.changed.connect(_on_changed)
	Game.stock_changed.connect(func():
		if visible:
			refresh())
	get_viewport().size_changed.connect(func():
		if _fit():
			hud._layout())


func open() -> void:
	refresh()
	if not visible:
		hud._toggle(self)
	_fit()
	hud._layout()


## Liste so hoch, wie der Bildschirm erlaubt (Platz zwischen Oberleiste und unterer Leiste wie in
## hud._layout, abzüglich Kopf, Text und Gold); schmal genug für 360 px. true, wenn sich etwas ändert.
func _fit() -> bool:
	var vs := get_viewport().get_visible_rect().size
	var old := _scroll.custom_minimum_size
	var w := clampf(vs.x - 44.0, 300.0, 370.0)
	_info.custom_minimum_size.x = w - 10.0
	_hint.custom_minimum_size.x = w - 10.0
	_scroll.custom_minimum_size = Vector2(w, 0)
	var top := 100.0 if (vs.y > vs.x or vs.x < 760.0) else 50.0
	var bar: Control = hud._bottom.get_parent() if hud != null and hud._bottom != null else null
	var room := vs.y - top - (bar.size.y if bar != null else 60.0) - 24.0 - get_combined_minimum_size().y
	if Merchant.world() == null:
		room = 110.0  # nur der kurze Hilfetext
	else:
		room = minf(room, _list.get_combined_minimum_size().y + 4.0)  # nicht höher als die Zeilen
	_scroll.custom_minimum_size.y = clampf(room, 110.0, 420.0)
	return _scroll.custom_minimum_size != old


func _on_changed() -> void:
	_refresh_badge()
	if visible:
		refresh()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _next_ms:
		return
	_next_ms = now + 500
	_refresh_badge()
	if visible:
		_update_head()


func _refresh_badge() -> void:
	if _badge == null:
		return
	var here := Merchant.present()
	var soon := not here and Merchant.planned_world() != null
	var sig := "%s|%s" % [here, soon]
	_badge.tooltip_text = Merchant.status_text() + (tr("\nTippen: handeln") if here else "")
	if sig == _badge_sig:
		return
	_badge_sig = sig
	_badge.visible = here or soon
	var col := BADGE if here else BADGE_SOON
	_badge_sb.bg_color = col
	_badge_sb.border_color = col.darkened(0.45)
	_badge.modulate = Color.WHITE if here else Color(1, 1, 1, 0.8)
	hud._layout()


func _update_head() -> void:
	var w = Merchant.world()
	if w == null:
		_title.text = tr("Fremder Händler")
		_info.text = Merchant.status_text()
		_gold_row.visible = false
		return
	_title.text = Merchant.merchant_name()
	_info.text = tr("Liegt in %s, fährt in %d Std. weiter. Gehandelt wird mit dem Lager dieser Insel.") % [Sea.island_name(w), Merchant.hours_left()]
	_gold_row.visible = true
	_gold.text = tr("Gold hier: %d") % Game.amount("gold", w)


func refresh() -> void:
	if not is_inside_tree():
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_update_head()
	var w = Merchant.world()
	if w == null:
		_hint.text = ""
		_hint.visible = false
		_list.add_child(_wrap(tr("Händler werden einen Tag vorher angekündigt, bleiben einen Tag und handeln gegen das Gold im Lager der Insel, an der sie liegen. Gold gibt es in Goldadern auf Felseninseln, oder du verkaufst dem Händler Waren."), 13))
		if visible and _fit():
			hud._layout()
		return
	var other: Array = Merchant.gold_elsewhere(w)
	if not other.is_empty():
		var parts := other.map(func(e): return "%s %d" % [e[0], int(e[1])])
		_hint.text = tr("Gold auf anderen Inseln: %s. Ein Schiff kann es herbringen.") % ", ".join(parts)
	elif Game.amount("gold", w) <= 0:
		_hint.text = tr("Kein Gold hier? Verkaufe dem Händler Waren, dann kannst du bei ihm kaufen.")
	else:
		_hint.text = ""
	_hint.visible = _hint.text != ""
	_list.add_child(UiTheme.label(tr("Er verkauft"), 15, UiTheme.TEXT, true))
	for i in Merchant.state.sells.size():
		_list.add_child(_row(Merchant.state.sells[i], i, false))
	_list.add_child(UiTheme.label(tr("Er kauft"), 15, UiTheme.TEXT, true))
	for i in Merchant.state.buys.size():
		_list.add_child(_row(Merchant.state.buys[i], i, true))
	if visible and _fit():
		hud._layout()


func _wrap(text: String, size: int = 13, col: Color = UiTheme.TEXT) -> Label:
	var l := UiTheme.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = _scroll.custom_minimum_size.x - 12.0
	return l


## Eine Zeile: Symbol, "6 Werkzeug" / "noch 2x", Goldpreis, Knopf (gesperrt mit Grund).
func _row(lot: Dictionary, i: int, selling: bool) -> Control:
	var id := str(lot.id)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.add_child(UiTheme.icon_rect(Data.res_icon(id), 20))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	var nm := UiTheme.label("%d %s" % [int(lot.n), Data.resource_name(id)], 14, UiTheme.TEXT, true)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	tv.add_child(nm)
	var why: String = Merchant.sell_block(i) if selling else Merchant.buy_block(i)
	var left := int(lot.left)
	var sub_text := tr("noch %dx") % left if left > 0 else ""
	if why != "":
		sub_text = why if sub_text == "" or left <= 0 else "%s · %s" % [sub_text, why]
	var sub := UiTheme.label(sub_text, 11, UiTheme.BAD if why != "" else DIM)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.clip_text = true
	tv.add_child(sub)
	h.add_child(tv)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 2)
	pr.add_child(UiTheme.icon_rect(Data.res_icon("gold"), 16))
	var gl := UiTheme.label(("+%d" if selling else "%d") % int(lot.gold), 15, UiTheme.GOOD if selling else UiTheme.TEXT, true)
	gl.custom_minimum_size.x = 26
	pr.add_child(gl)
	pr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pr)
	var btn := UiTheme.button(tr("Verkaufen") if selling else tr("Kaufen"), "", 36)
	btn.custom_minimum_size.x = 92
	btn.add_theme_font_size_override("font_size", 14)
	btn.disabled = why != ""
	btn.tooltip_text = why if why != "" else (tr("%d %s für %d Gold verkaufen") if selling else tr("%d %s für %d Gold kaufen")) % [int(lot.n), Data.resource_name(id), int(lot.gold)]
	btn.pressed.connect(func():
		var err: String = Merchant.sell(i) if selling else Merchant.buy(i)
		if err != "":
			hud.toast(err, "haendler")
		refresh())
	h.add_child(btn)
	return h


# ---------------------------------------------------------------- Einstiege
## Infofenster eines Hafens (auch Werft): Händler da / angekündigt, Knopf zum Handeln.
static func harbor_rows(hud, b) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	hud._info_box.add_child(box)
	var memo := {"sig": ""}
	var upd := func():
		if not is_instance_valid(box) or not is_instance_valid(b):
			return
		var id := int(b.world.island_id)
		var mode := "here" if Merchant.at(id) else ("soon" if Merchant.planned_world() == b.world else "none")
		var text := ""
		match mode:
			"here":
				text = Loc.t("Fremder Händler im Hafen: %s, noch %d Std.") % [Merchant.merchant_name(), Merchant.hours_left()]
			"soon":
				text = Loc.t("Ein fremder Händler legt in %d Std. hier an.") % Merchant.hours_until()
			_:
				text = Merchant.status_text()
		if memo.sig != mode:
			memo.sig = mode
			for c in box.get_children():
				box.remove_child(c)
				c.queue_free()
			var l := UiTheme.label(text, 13, UiTheme.GOOD if mode == "here" else (UiTheme.ACCENT if mode == "soon" else DIM))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(l)
			if mode == "here":
				var tb := UiTheme.button(Loc.t("Mit dem Händler handeln"), "haendler", 36)
				tb.pressed.connect(func(): hud._trade_panel.open())
				box.add_child(tb)
		elif box.get_child_count() > 0:
			(box.get_child(0) as Label).text = text
	upd.call()
	hud._updaters.append(upd)


## Seekarte, Inselansicht: Händler hier (mit Knopf "Handeln") oder angekündigt.
static func sea_rows(sp, m: Dictionary) -> void:
	var id := int(m.get("id", -1))
	if Merchant.at(id):
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var l := UiTheme.label(Loc.t("Händler hier: %s, noch %d Std.") % [Merchant.merchant_name(), Merchant.hours_left()], 13, UiTheme.GOOD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var tb := UiTheme.button(Loc.t("Handeln"), "haendler", 36)
		tb.pressed.connect(func():
			sp.visible = false
			sp.hud._trade_panel.open())
		h.add_child(tb)
		sp._details.add_child(h)
	elif Merchant.planned_world() != null and int(Merchant.state.plan) == id:
		sp._details.add_child(sp._wrap(Loc.t("Ein fremder Händler wird hier in %d Std. erwartet.") % Merchant.hours_until(), 13, UiTheme.ACCENT))


## Abschnitt für die Spielanleitung (hud._build_help_panel).
static func help_text() -> String:
	return "\n\n" + Loc.t(HELP)
