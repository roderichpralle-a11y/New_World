class_name Win
extends RefCounted
## Bausteine für das einheitliche Fenster (josh 2026-10-16, Entwurfsbilder in /mnt/project-files/konzept/):
## Reiter mit Text, Filter-Chips, gleich aufgebaute Zeile (Symbol, Name, graue Kurzinfo, Wert, Knopf
## rechts) und Fuß (Zusammenfassung links, Hauptaktion rechts). Der Kopf kommt aus Hud._popup_panel.

const DIM := Color("#6e5a50")
const ROW_BG := Color("#ecd8ac")
const ROW_BORDER := Color("#b07a3a")
const CHIP_ON := Color("#d8902f")

static var _row_box: StyleBoxFlat
static var _row_box_hi: StyleBoxFlat
static var _chip_boxes: Dictionary = {}


## Reiter mit Text in einer umbrechenden Reihe. on_pick bekommt den Index. Gibt die Reihe zurück;
## die Knöpfe stehen in ihr der Reihe nach (select() setzt den gedrückten).
static func tabs(names: Array, selected: int, on_pick: Callable) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 4)
	f.add_theme_constant_override("v_separation", 4)
	for i in names.size():
		var b := UiTheme.button(str(names[i]), "", 36)
		b.toggle_mode = true
		b.button_pressed = i == selected
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func():
			select(f, i)
			on_pick.call(i))
		f.add_child(b)
	return f


static func select(f: Container, i: int) -> void:
	for k in f.get_child_count():
		var b = f.get_child(k)
		if b is Button:
			b.set_pressed_no_signal(k == i)


## Filter-Chip: kleiner, abgerundeter Schalter. on_toggle bekommt an/aus.
static func chip(text: String, on: bool, on_toggle: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(40, 34)
	b.add_theme_font_size_override("font_size", 13)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, _chip_box(st in ["pressed", "hover_pressed"]))
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", UiTheme.TEXT)
	b.add_theme_color_override("font_pressed_color", UiTheme.TEXT_LIGHT)
	b.add_theme_color_override("font_hover_pressed_color", UiTheme.TEXT_LIGHT)
	b.toggled.connect(func(x): on_toggle.call(x))
	return b


static func _chip_box(on: bool) -> StyleBoxFlat:
	if not _chip_boxes.has(on):
		var sb := StyleBoxFlat.new()
		sb.bg_color = CHIP_ON if on else Color("#f6e8c8")
		sb.border_color = CHIP_ON if on else DIM
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		_chip_boxes[on] = sb
	return _chip_boxes[on]


## Reihe für Chips (und kleine Auswahlknöpfe), bricht auf schmalen Bildschirmen um.
static func chip_row() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.set_meta("fit_hide", true)  # Handy quer: Hud blendet Chips aus, wenn die Liste schon am kleinsten ist
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 4)
	return f


static func row_box(hi: bool = false) -> StyleBoxFlat:
	if _row_box == null:
		_row_box = StyleBoxFlat.new()
		_row_box.bg_color = ROW_BG
		_row_box.border_color = ROW_BORDER
		_row_box.set_border_width_all(1)
		_row_box.set_corner_radius_all(4)
		_row_box.content_margin_left = 6
		_row_box.content_margin_right = 6
		_row_box.content_margin_top = 4
		_row_box.content_margin_bottom = 4
		_row_box_hi = _row_box.duplicate()
		_row_box_hi.bg_color = Color("#f2c27a")
		_row_box_hi.border_color = Color("#8a5a2a")
		_row_box_hi.set_border_width_all(2)
	return _row_box_hi if hi else _row_box


## Eine Listenzeile: Symbol, Name (fett), graue Kurzinfo, Wert und Knopf rechts.
## Gibt {"box", "h", "icon", "name", "sub", "text", "value", "button"} zurück; fehlende Teile sind null.
## opts: sub_color, value, value_color, button, button_off (grau, aber antippbar), on_press, icon_px, hi.
static func row(tex: Texture2D, name: String, sub: String = "", opts: Dictionary = {}) -> Dictionary:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", row_box(bool(opts.get("hi", false))))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	box.add_child(h)
	var ic: TextureRect = null
	if tex != null:
		ic = UiTheme.icon_rect(tex, float(opts.get("icon_px", 40)))
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(tv)
	var nl := UiTheme.label(name, 15, UiTheme.TEXT, true)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size.x = 110
	tv.add_child(nl)
	var sl: Label = null
	if sub != "":
		sl = UiTheme.label(sub, 12, opts.get("sub_color", DIM))
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size.x = 110
		tv.add_child(sl)
	var vl: Label = null
	if opts.has("value"):
		vl = UiTheme.label(str(opts.value), 14, opts.get("value_color", UiTheme.TEXT), true)
		vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(vl)
	var bt: Button = null
	if opts.has("button"):
		bt = UiTheme.button(str(opts.button), "", 40)
		bt.custom_minimum_size.x = 64
		bt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bt.add_theme_font_size_override("font_size", 14)
		if opts.get("button_off", false):
			bt.modulate = Color(1, 1, 1, 0.55)
		if opts.has("on_press"):
			bt.pressed.connect(opts.on_press)
		h.add_child(bt)
	return {"box": box, "h": h, "icon": ic, "name": nl, "sub": sl, "text": tv, "value": vl, "button": bt}


## Fuß eines Fensters: Linie, links Zusammenfassung (zwei Zeilen), rechts Platz für die Hauptaktion.
## Gibt {"box", "left", "left2", "right"} zurück; right ist ein HBox für Knöpfe.
static func footer(parent: Container) -> Dictionary:
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = ROW_BORDER
	line.thickness = 2
	sep.add_theme_stylebox_override("separator", line)
	sep.set_meta("fit_hide", true)
	parent.add_child(sep)
	var h := HBoxContainer.new()
	h.set_meta("fit_hide", true)
	h.add_theme_constant_override("separation", 8)
	parent.add_child(h)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 0)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(lv)
	var l1 := UiTheme.label("", 14, UiTheme.TEXT, true)
	l1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l1.custom_minimum_size.x = 150
	lv.add_child(l1)
	var l2 := UiTheme.label("", 12, DIM)
	l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l2.custom_minimum_size.x = 150
	l2.visible = false
	lv.add_child(l2)
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	h.add_child(right)
	return {"box": h, "sep": sep, "left": l1, "left2": l2, "right": right}


## Zweite Fußzeile setzen und nur zeigen, wenn sie Text hat.
static func set_left2(ft: Dictionary, text: String) -> void:
	ft.left2.text = text
	ft.left2.visible = text != ""
