class_name SeaPanel
extends PanelContainer
## Seekarte: alle entdeckten Inseln, Schiffe, Routen, Erkunden und Siedler aussenden.

var hud  # Hud (fuer Meldungen und Kamera)
var _selected: int = 0
var _goods_hscroll := 0  # seitliche Stelle der Warentabelle
var _view: String = "goods"  # goods (Inseln), ships, trip, ship (Route), stop, island (Karte), send
var _send_sel: Array = []
var _send_goods: Dictionary = {}
var _send_ship: int = -1
var _ship_id: int = -1
var _stop_i: int = -1
var _tab_goods: Button
var _tab_islands: Button
var _tab_ships: Button
var _title: Label
var _goods_mode: String = "main"  # main, all, missing
var _mm_island: int = -1  # Mindest- und Höchststand bearbeiten (Steward, ab der 3. Insel): Insel und Ware
var _mm_good: String = ""
var _trip_from: int = -1
var _trip_to: int = -1
var _trip_goods: Dictionary = {}
var _head: Label
var _map: Control
var _details: VBoxContainer
var _scroll: ScrollContainer
var _tex_cache: Dictionary = {}
var _probe_cache: Dictionary = {}
var _anim: float = 0.0
# Zoom und Verschieben der Karte
const ZOOM_MIN := 1.0
const ZOOM_MAX := 8.0
var _zoom: float = 1.0
var _pan := Vector2.ZERO  # Verschiebung in Kartenkoordinaten
var _press_pos := Vector2.ZERO
var _pressed: bool = false
var _dragging: bool = false
var _touches: Dictionary = {}  # Fingerindex -> Position (Zwei-Finger-Zoom)
var _pinch_dist: float = 0.0
var _zoom_btns: HBoxContainer


func setup(p_hud) -> void:
	hud = p_hud
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	_title = UiTheme.label(tr("Inseln"), 20, UiTheme.TEXT, true)
	head.add_child(_title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	# Reiter (josh 2026-10-17): Inseln (Waren je Insel), Schiffe (Fahrten und Routen), Karte
	_tab_goods = UiTheme.button(tr("Inseln"), "kiste", 32)
	_tab_goods.toggle_mode = true
	_tab_goods.pressed.connect(func(): _go("goods"))
	head.add_child(_tab_goods)
	_tab_ships = UiTheme.button(tr("Schiffe"), "anker", 32)
	_tab_ships.toggle_mode = true
	_tab_ships.pressed.connect(func(): _go("ships"))
	head.add_child(_tab_ships)
	_tab_islands = UiTheme.button(tr("Karte"), "kompass", 32)
	_tab_islands.toggle_mode = true
	_tab_islands.pressed.connect(func(): _go("island"))
	head.add_child(_tab_islands)
	head.add_child(hud.help_button("inseln", tr("Inseln")))
	var x := UiTheme.button("", "abriss", 32)
	x.tooltip_text = tr("Schließen")
	x.pressed.connect(func(): visible = false)
	head.add_child(x)
	v.add_child(head)
	_head = UiTheme.label("", 13)
	_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_head.custom_minimum_size.x = 340
	v.add_child(_head)
	_map = Control.new()
	_map.custom_minimum_size = Vector2(350, 175)
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_map_input)
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.clip_contents = true
	_map.tooltip_text = tr("Mausrad oder zwei Finger: zoomen. Ziehen: Karte verschieben.")
	v.add_child(_map)
	_zoom_btns = HBoxContainer.new()
	_zoom_btns.add_theme_constant_override("separation", 4)
	var zin := UiTheme.button("+", "", 30)
	zin.tooltip_text = tr("Hineinzoomen")
	zin.custom_minimum_size.x = 30
	zin.pressed.connect(func(): _zoom_at(_map.size / 2.0, 1.5))
	var zout := UiTheme.button("-", "", 30)
	zout.tooltip_text = tr("Herauszoomen")
	zout.custom_minimum_size.x = 30
	zout.pressed.connect(func(): _zoom_at(_map.size / 2.0, 1.0 / 1.5))
	var zall := UiTheme.button(tr("Alle"), "", 30)
	zall.tooltip_text = tr("Alle Inseln zeigen")
	zall.pressed.connect(func():
		_zoom = 1.0
		_pan = Vector2.ZERO
		_map.queue_redraw())
	for zb in [zout, zin, zall]:
		zb.add_theme_font_size_override("font_size", 14)
		zb.focus_mode = Control.FOCUS_NONE
		_zoom_btns.add_child(zb)
	_zoom_btns.position = Vector2(5, 5)
	_map.add_child(_zoom_btns)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(350, 135)
	v.add_child(_scroll)
	_details = VBoxContainer.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_details)
	Sea.islands_changed.connect(_on_islands_changed)
	Game.stock_changed.connect(func():
		if visible and hud.user_just_acted():
			_update_head())
	get_viewport().size_changed.connect(_fit)


func open() -> void:
	_selected = Game.world.island_id if Game.world else 0
	_view = "goods"
	_fit()
	refresh()


## Liste unter der Karte so hoch wie der Platz auf dem Bildschirm erlaubt.
func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var on_map := _view in ["island", "send"]
	_map.visible = on_map
	_head.visible = on_map
	_title.visible = vs.x >= 560.0  # auf dem Handy passen nur die Reiter
	_scroll.custom_minimum_size.y = clamp(vs.y - 365.0, 130.0, 460.0) if on_map else clamp(vs.y - 130.0, 200.0, 600.0)
	_scroll.custom_minimum_size.x = 350.0 if on_map else clamp(vs.x - 40.0, 330.0, 720.0)
	_map.custom_minimum_size.x = clamp(vs.x - 40.0, 300.0, 420.0)


func refresh() -> void:
	if not is_inside_tree():
		return
	_update_head()
	_fill_details()
	_map.queue_redraw()


## Das Fenster bleibt stehen, während es offen ist (josh 2026-10-18 Warentabelle, 2026-10-19 alle Fenster):
## neue Zahlen erst beim Öffnen, beim Reiterwechsel oder nach einem Tipp im Fenster.
func _on_islands_changed() -> void:
	if visible and not hud.user_just_acted():
		_map.queue_redraw()  # offene Fenster stehen still (josh 2026-10-19); nur die Karte bewegt sich
		return
	refresh()


func _update_head() -> void:
	var at_sea := Sea.people_at_sea()
	var t := tr("Schiffe: %d   Bewohnte Inseln: %d") % [Sea.ships.size(), Sea.settled_islands().size()]
	if at_sea > 0:
		t += tr("   Auf See: %d Siedler") % at_sea
	if Sea.exploring():
		t += tr("   Ein Schiff erkundet.")
	_head.text = t


func _process(delta: float) -> void:
	if visible:
		_anim += delta
		_map.queue_redraw()


# ---------------------------------------------------------------- Karte
func _bounds() -> Rect2:
	var r := Rect2(0, 0, 0, 0)
	var first := true
	for m in Sea.islands:
		var p := Vector2(float(m.pos[0]), float(m.pos[1]))
		if first:
			r = Rect2(p, Vector2.ZERO)
			first = false
		else:
			r = r.expand(p)
	for v in Sea.voyages:
		if v.kind == "explore":
			r = r.expand(_probe_pos(int(v.to)))
	return r.grow(0.8)


func _probe_pos(index: int) -> Vector2:
	if not _probe_cache.has(index):
		var m := Sea.make_island(index)
		_probe_cache[index] = Vector2(float(m.pos[0]), float(m.pos[1]))
	return _probe_cache[index]


func _base_scale(b: Rect2) -> float:
	var sz := _map.size - Vector2(40, 40)
	var s: float = min(sz.x / max(b.size.x, 0.01), sz.y / max(b.size.y, 0.01))
	return min(s, 70.0)


func _to_screen(p: Vector2, b: Rect2) -> Vector2:
	var center := b.get_center() + _pan
	return _map.size / 2.0 + (p - center) * _base_scale(b) * _zoom


func _to_map(sp: Vector2, b: Rect2) -> Vector2:
	var center := b.get_center() + _pan
	return center + (sp - _map.size / 2.0) / (_base_scale(b) * _zoom)


## Groesse einer Insel auf der Karte; waechst beim Hineinzoomen mit.
func _island_px(m: Dictionary) -> float:
	return (18.0 + float(m.size) * 0.3) * min(_zoom, 5.0)


## Zoomt so, dass der Kartenpunkt unter sp an seinem Platz bleibt.
func _zoom_at(sp: Vector2, factor: float) -> void:
	var b := _bounds()
	var before := _to_map(sp, b)
	_zoom = clamp(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var after := _to_map(sp, b)
	_pan += before - after
	_clamp_pan(b)
	_map.queue_redraw()


func _clamp_pan(b: Rect2) -> void:
	if _zoom <= ZOOM_MIN + 0.001:
		_pan = Vector2.ZERO
		return
	var half := b.size / 2.0
	_pan.x = clamp(_pan.x, -half.x, half.x)
	_pan.y = clamp(_pan.y, -half.y, half.y)


func _island_tex(m: Dictionary) -> Texture2D:
	var id := int(m.id)
	if _tex_cache.has(id):
		return _tex_cache[id]
	var opts := {}
	if m.biome != "heimat":
		var bd: Dictionary = Data.islands[m.biome].duplicate()
		bd["_dens"] = []
		opts = {"biome": bd}
	var gen := IslandGen.generate(int(m.seed), int(m.size), opts)
	var size := int(m.size)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var tint := Color(Data.islands.get(m.biome, {}).get("tint", "#ffffff"))
	var grass := Color("#64ac4a") * tint
	for y in size:
		for x in size:
			var t: int = gen.terrain[y * size + x]
			if t == 1:
				img.set_pixel(x, y, Color("#ecd49a"))
			elif t == 2:
				img.set_pixel(x, y, grass)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[id] = tex
	return tex


func _draw_map() -> void:
	var sz := _map.size
	_map.draw_rect(Rect2(Vector2.ZERO, sz), Color("#3a78bc"))
	# Wellen
	for i in 26:
		var p := Vector2(fposmod(i * 67.0 + _anim * 4.0, sz.x), fposmod(i * 41.0, sz.y))
		_map.draw_line(p, p + Vector2(5, 0), Color(1, 1, 1, 0.25), 1.0)
	_map.draw_rect(Rect2(Vector2.ZERO, sz), Color("#2a1c20"), false, 2.0)
	var b := _bounds()
	var font: Font = Data.font_regular
	# Reisen
	for v in Sea.voyages:
		var pa := _to_screen(_meta_pos(int(v.from)), b)
		var pb := _to_screen(_probe_pos(int(v.to)) if v.kind == "explore" else _meta_pos(int(v.to)), b)
		_dashed(pa, pb, Color(1, 1, 1, 0.7))
		var f: float = clamp((Game.time_days - float(v.depart)) / max(0.001, float(v.arrive) - float(v.depart)), 0.0, 1.0)
		if v.kind == "explore":
			f = 1.0 - abs(1.0 - f * 2.0)
		var bp := pa.lerp(pb, f)
		var vs := Sea.ship_by_id(int(v.get("ship", -1)))
		var ic: String = Sea.ship_def(vs).get("icon", "boot") if not vs.is_empty() else "boot"
		_map.draw_texture_rect(Data.icon(ic), Rect2(bp - Vector2(10, 14), Vector2(20, 20)), false)
	for m in Sea.islands:
		var p := _to_screen(_meta_pos(int(m.id)), b)
		var s := _island_px(m)
		if not Rect2(Vector2.ZERO, sz).grow(s).has_point(p):
			continue  # beim Zoomen ausserhalb des Bildes
		var tex := _island_tex(m)
		var col := Color.WHITE if m.state != "lost" else Color(0.45, 0.4, 0.4)
		if int(m.id) == _selected:
			_map.draw_circle(p, s * 0.62, Color(1, 0.9, 0.4, 0.45))
		_map.draw_texture_rect(tex, Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), false, col)
		if m.state == "lost":
			_map.draw_line(p - Vector2(7, 7), p + Vector2(7, 7), Color("#d0484a"), 2.0)
			_map.draw_line(p + Vector2(-7, 7), p + Vector2(7, -7), Color("#d0484a"), 2.0)
		if Game.world and int(m.id) == Game.world.island_id:
			_map.draw_texture_rect(Data.icon("person"), Rect2(p - Vector2(8, 10), Vector2(16, 16)), false)
		elif m.state == "settled":
			_map.draw_texture_rect(Data.icon("haus"), Rect2(p - Vector2(7, 9), Vector2(14, 14)), false)
		# Schiffe, die dort liegen
		var docked := Sea.ships_at(int(m.id))
		for i in min(docked.size(), 4):
			var ic2: String = Sea.ship_def(docked[i]).get("icon", "boot")
			_map.draw_texture_rect(Data.icon(ic2), Rect2(p + Vector2(s * 0.35 + i * 9, -s * 0.35), Vector2(14, 14)), false)
		var name: String = m.name
		var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var tp := p + Vector2(-w / 2.0, s / 2.0 + 9)
		if _zoom <= ZOOM_MIN + 0.001:
			tp.x = clamp(tp.x, 3.0, sz.x - w - 3.0)
			tp.y = min(tp.y, sz.y - 4.0)
		_map.draw_string_outline(font, tp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color("#2a1c20"))
		_map.draw_string(font, tp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#fff6e0"))


func _dashed(a: Vector2, b: Vector2, c: Color) -> void:
	var n := int((b - a).length() / 6.0)
	for i in range(0, n, 2):
		_map.draw_line(a.lerp(b, float(i) / max(1, n)), a.lerp(b, float(i + 1) / max(1, n)), c, 1.0)


func _meta_pos(id: int) -> Vector2:
	var m := Sea.meta(id)
	if m.is_empty():
		return Vector2.ZERO
	return Vector2(float(m.pos[0]), float(m.pos[1]))


func _on_map_input(ev: InputEvent) -> void:
	# Zwei Finger: zoomen
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
		else:
			_touches.erase(ev.index)
		_pinch_dist = 0.0
		if _touches.size() >= 2:
			_pressed = false
			_dragging = false
		return
	if ev is InputEventScreenDrag:
		_touches[ev.index] = ev.position
		if _touches.size() >= 2:
			var pts: Array = _touches.values()
			var d: float = (pts[0] - pts[1]).length()
			if _pinch_dist > 0.0 and d > 1.0:
				_zoom_at((pts[0] + pts[1]) / 2.0, d / _pinch_dist)
			_pinch_dist = d
			accept_event()
		return
	if ev is InputEventMagnifyGesture:
		_zoom_at(ev.position, ev.factor)
		accept_event()
		return
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			_zoom_at(ev.position, 1.2)
			accept_event()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			_zoom_at(ev.position, 1.0 / 1.2)
			accept_event()
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_pressed = true
				_dragging = false
				_press_pos = ev.position
			else:
				var was_click := _pressed and not _dragging
				_pressed = false
				_dragging = false
				if was_click and _touches.size() < 2:
					_select_at(ev.position)
		return
	if ev is InputEventMouseMotion and _pressed and _touches.size() < 2:
		if not _dragging and (ev.position - _press_pos).length() > 6.0:
			_dragging = true
		if _dragging and _zoom > ZOOM_MIN + 0.001:
			var b := _bounds()
			_pan -= ev.relative / (_base_scale(b) * _zoom)
			_clamp_pan(b)
			_map.queue_redraw()


func _select_at(pos: Vector2) -> void:
	var b := _bounds()
	var best := -1
	var best_d := 40.0
	for m in Sea.islands:
		best_d = max(best_d, _island_px(m) * 0.6)
	for m in Sea.islands:
		var d: float = (_to_screen(_meta_pos(int(m.id)), b) - pos).length()
		if d < best_d:
			best_d = d
			best = int(m.id)
	if best >= 0:
		_selected = best
		if _view != "island":
			_view = "island"
		refresh()


# ---------------------------------------------------------------- Details
func _clear() -> void:
	for c in _details.get_children():
		_details.remove_child(c)
		c.queue_free()


func _wrap(text: String, size: int = 13, col: Color = UiTheme.TEXT) -> Label:
	var l := UiTheme.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 320
	return l


func _hint(text: String) -> Label:
	return _wrap(text, 12, Color("#8a5a3a"))


func _go(view: String) -> void:
	_view = view
	_fit()
	refresh()
	_scroll.scroll_vertical = 0


func _fill_details() -> void:
	_clear()
	_tab_goods.set_pressed_no_signal(_view == "goods")
	_tab_islands.set_pressed_no_signal(_view in ["island", "send"])
	_tab_ships.set_pressed_no_signal(_view in ["ships", "trip", "ship", "stop"])
	match _view:
		"goods":
			_fill_goods()
		"trip":
			_fill_trip()
		"send":
			_fill_send()
		"ships":
			_fill_ships()
		"ship":
			_fill_ship()
		"stop":
			_fill_stop()
		_:
			_fill_island()


func _fill_island() -> void:
	var m := Sea.meta(_selected)
	if m.is_empty():
		_selected = 0
		m = Sea.meta(0)
	var w = Sea.worlds.get(int(m.id))
	var here: bool = Game.world != null and int(m.id) == Game.world.island_id
	_details.add_child(UiTheme.label("%s (%s)" % [m.name, Sea.biome_name(m)], 16, UiTheme.TEXT, true))
	_details.add_child(_wrap(Sea.biome_def(m).get("desc", "")))
	var state := ""
	match m.state:
		"settled":
			state = tr("Besiedelt: %d Siedler") % (w.settlers.size() if w else 0)
			if here:
				state += tr(" (hier bist du)")
		"discovered":
			state = tr("Unbewohnt. Schicke Siedler hierher, um sie zu besiedeln. Ohne Hafen können nur Ruderboote landen.")
		"lost":
			state = tr("Verloren. Niemand kann hier mehr leben.")
	_details.add_child(_wrap(state, 13, UiTheme.BAD if m.state == "lost" else UiTheme.TEXT))
	# Gefahren und Besonderheiten
	var dangers := Sea.dangers(m)
	var h := HBoxContainer.new()
	h.add_child(UiTheme.label(tr("Gefahr:"), 13))
	if dangers.is_empty():
		h.add_child(UiTheme.label(tr("keine"), 13, UiTheme.GOOD))
	for a in dangers:
		h.add_child(UiTheme.icon_rect(Data.icon(a), 16))
		h.add_child(UiTheme.label(Data.animals[a].name, 13, UiTheme.BAD))
	if w and m.state == "settled":
		h.add_child(UiTheme.label(tr("(%d Tiere)") % w.animals.size(), 12))
	_details.add_child(h)
	var special: Array = Sea.biome_def(m).get("special", [])
	if not special.is_empty():
		var hs := HBoxContainer.new()
		hs.add_child(UiTheme.label(tr("Reich an:"), 13))
		for r in special:
			hs.add_child(UiTheme.icon_rect(Data.res_icon(r), 16))
			hs.add_child(UiTheme.label(Data.resource_name(r), 13))
		_details.add_child(hs)
	IslandTraits.strength_row(_details, m)  # Inselstärken: Gebäude, die hier schneller arbeiten
	TradePanel.sea_rows(self, m)  # fremder Händler hier oder angekündigt
	if w and m.state == "settled":
		_details.add_child(_wrap(tr("Hafen: %s. %s.") % [Sea.harbor_level_name(Sea.harbor_level(w)), Sea.berth_text(w)], 12))
		var docked := Sea.ships_at(int(m.id))
		if not docked.is_empty():
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 4)
			for sh in docked:
				var sb := UiTheme.button(sh.name, Sea.ship_def(sh).get("icon", "boot"), 32)
				sb.add_theme_font_size_override("font_size", 13)
				var sid := int(sh.id)
				sb.pressed.connect(func(): _open_ship(sid))
				flow.add_child(sb)
			_details.add_child(flow)
	if not here and Game.world and m.state != "lost":
		var hours := Sea.voyage_days(Game.world.island_id, int(m.id)) * 24.0
		_details.add_child(UiTheme.label(tr("Fahrzeit von hier (Ruderboot): %d Stunden") % int(ceil(hours)), 13))
	# Aktionen
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	if m.state == "settled" and not here and w:
		var go := UiTheme.button(tr("Ansehen"), "play", 38)
		go.pressed.connect(func():
			visible = false
			Sea.switch_to(int(m.id)))
		acts.add_child(go)
	if m.state != "lost" and not here:
		var send := UiTheme.button(tr("Schiff hierher schicken"), "boot", 38)
		send.tooltip_text = tr("Bringt Siedler und Waren von der Insel, auf der du gerade bist.")
		send.pressed.connect(func():
			_send_sel = []
			_send_goods = {}
			_send_ship = -1
			_go("send"))
		acts.add_child(send)
	var ex := UiTheme.button(tr("Entdeckungsreise"), "kompass", 38)
	ex.tooltip_text = tr("Das schnellste freie Schiff fährt hinaus und kommt mit einer neuen Insel auf der Karte zurück.")
	ex.pressed.connect(func():
		var err := Sea.start_explore(Game.world)
		if err != "":
			hud.toast(err, "boot")
		refresh())
	acts.add_child(ex)
	_details.add_child(acts)
	var why := Sea.can_explore()
	if why != "" and not Sea.exploring():
		_details.add_child(_hint(tr("Neue Inseln suchen: %s") % why))
	if Data.buildings.has("werft") and not Game.is_unlocked("werft"):
		_details.add_child(_hint(tr("Schiffe baut die Werft. Dafür braucht es die Forschung Schiffsbau.")))


## Gemeinsame Zeile fuer eine Ware: Symbol, Name, Info, [-] Menge [+].
func _goods_row(id: String, info: String, get_n: Callable, set_n: Callable, step: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.add_child(UiTheme.icon_rect(Data.res_icon(id), 18))
	var nm := UiTheme.label(Data.resource_name(id), 13)
	nm.custom_minimum_size.x = 92
	nm.clip_text = true
	h.add_child(nm)
	var inf := UiTheme.label(info, 11)
	inf.custom_minimum_size.x = 84
	inf.modulate.a = 0.75
	h.add_child(inf)
	var minus := UiTheme.button("−", "", 30)
	minus.custom_minimum_size.x = 30
	minus.focus_mode = Control.FOCUS_NONE
	var val := UiTheme.label(str(int(get_n.call())), 14, UiTheme.TEXT, true)
	val.custom_minimum_size.x = 36
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plus := UiTheme.button("+", "", 30)
	plus.custom_minimum_size.x = 30
	plus.focus_mode = Control.FOCUS_NONE
	minus.pressed.connect(func():
		set_n.call(max(0, int(get_n.call()) - step))
		val.text = str(int(get_n.call())))
	plus.pressed.connect(func():
		set_n.call(int(get_n.call()) + step)
		val.text = str(int(get_n.call())))
	h.add_child(minus)
	h.add_child(val)
	h.add_child(plus)
	return h


func _fill_send() -> void:
	var m := Sea.meta(_selected)
	var from = Game.world
	_details.add_child(UiTheme.label(tr("Schiff nach %s schicken") % m.name, 16, UiTheme.TEXT, true))
	var list := Sea.idle_ships(from.island_id)
	if list.is_empty():
		_details.add_child(_wrap(tr("Auf %s liegt kein freies Schiff. Baue eines in der Werft oder hole ein Schiff von seiner Route.") % Sea.island_name(from), 13, UiTheme.BAD))
		_details.add_child(_back_btn("island"))
		return
	if Sea.ship_by_id(_send_ship).is_empty() or not list.has(Sea.ship_by_id(_send_ship)):
		_send_ship = int(list[0].id)
		for sh in list:
			if Sea.can_visit(sh.type, _selected) and Sea.ship_blocker(sh) == "":
				_send_ship = int(sh.id)
				break
	var sh := Sea.ship_by_id(_send_ship)
	var pick := HFlowContainer.new()
	pick.add_theme_constant_override("h_separation", 4)
	pick.add_theme_constant_override("v_separation", 4)
	for s2 in list:
		var b := UiTheme.button(s2.name, Sea.ship_def(s2).get("icon", "boot"), 32)
		b.add_theme_font_size_override("font_size", 13)
		b.toggle_mode = true
		b.button_pressed = int(s2.id) == _send_ship
		var sid := int(s2.id)
		b.pressed.connect(func():
			_send_ship = sid
			refresh())
		pick.add_child(b)
	_details.add_child(pick)
	var sd := Sea.ship_def(sh)
	_details.add_child(_wrap(tr("%s: %d Fahrgäste, Laderaum %d, Fahrzeit %d Std.") % [sd.name, Sea.passenger_capacity(sh), int(sd.cargo),
		int(ceil(Sea.voyage_days(from.island_id, _selected, sh.type) * 24.0))], 12))
	if not Sea.can_visit(sh.type, _selected):
		_details.add_child(_wrap(tr("Die %s (%s) ist zu groß für %s: dort fehlt ein passender Hafen.") % [sh.name, sd.name, m.name], 12, UiTheme.BAD))
	_crew_line(sh)
	if m.state == "discovered":
		_details.add_child(_hint(tr("Tipp: Schicke eine Frau und einen Mann mit, damit es dort Kinder gibt. Ein Baumeister baut die ersten Hütten. Nimm Essen und Holz mit, dort ist das Lager leer.")))
	if not Sea.dangers(m).is_empty():
		_details.add_child(_wrap(tr("Achtung, wilde Tiere! Jäger mit Speeren schützen die Siedler."), 12, UiTheme.BAD))
	# Fahrgaeste
	var cap := Sea.passenger_capacity(sh)
	var crew_ids: Array = sh.crew.map(func(x): return int(x))
	var count := UiTheme.label(tr("Fahrgäste: %d / %d") % [_send_sel.size(), cap], 14, UiTheme.TEXT, true)
	_details.add_child(count)
	var people: Array = from.settlers.filter(func(s): return not int(s.id) in crew_ids)
	people.sort_custom(func(a, b): return a.age > b.age)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for s in people:
		var who := (tr("Frau") if s.sex == "f" else tr("Mann")) if s.is_adult() else tr("Kind")
		var b := UiTheme.button("%s, %s" % [s.display_name, s.job_name() if s.is_adult() else who], "", 34)
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = tr("%s, %d Jahre") % [who, int(s.age)]
		b.toggle_mode = true
		b.button_pressed = _send_sel.has(s)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 160
		var sref = s
		b.toggled.connect(func(on):
			if on and not _send_sel.has(sref):
				if _send_sel.size() >= cap:
					b.set_pressed_no_signal(false)
					hud.toast(tr("Auf die %s passen nur %d Fahrgäste.") % [sh.name, cap], "boot")
					return
				_send_sel.append(sref)
			elif not on:
				_send_sel.erase(sref)
			count.text = tr("Fahrgäste: %d / %d") % [_send_sel.size(), cap])
		grid.add_child(b)
	_details.add_child(grid)
	# Ladung
	var room_l := UiTheme.label("", 14, UiTheme.TEXT, true)
	var upd_room := func():
		var used := 0
		for id in _send_goods:
			used += int(_send_goods[id]) * Data.good_size(id)
		room_l.text = tr("Ladung: %d / %d Laderaum") % [used, int(sd.cargo)]
	upd_room.call()
	_details.add_child(room_l)
	var any := false
	for id in Data.sorted_resource_ids():
		if Data.resources[id].get("category", "") == "ship" or Game.amount(id, from) <= 0:
			continue
		any = true
		var rid: String = id
		var get_n := func(): return int(_send_goods.get(rid, 0))
		var set_n := func(n: int):
			var used := 0
			for k in _send_goods:
				if k != rid:
					used += int(_send_goods[k]) * Data.good_size(k)
			var size: int = max(1, Data.good_size(rid))
			n = clamp(n, 0, min(Game.amount(rid, from), (int(sd.cargo) - used) / size))
			if n <= 0:
				_send_goods.erase(rid)
			else:
				_send_goods[rid] = n
			upd_room.call()
		_details.add_child(_goods_row(id, tr("Lager %d") % Game.amount(id, from), get_n, set_n, 5))
	if not any:
		_details.add_child(_hint(tr("Im Lager ist nichts zum Mitnehmen.")))
	var acts := HBoxContainer.new()
	var go := UiTheme.button(tr("Ablegen"), "boot", 40)
	go.pressed.connect(func():
		var alive := _send_sel.filter(func(x): return is_instance_valid(x))
		var err := Sea.send_ship(from, _selected, alive, Sea.ship_by_id(_send_ship), _send_goods)
		if err != "":
			hud.toast(err, "boot")
			return
		_send_sel = []
		_send_goods = {}
		_go("island"))
	acts.add_child(go)
	acts.add_child(_back_btn("island"))
	_details.add_child(acts)


func _back_btn(to: String) -> Button:
	var back := UiTheme.button(tr("Zurück"), "abriss", 40)
	back.pressed.connect(func(): _go(to))
	return back


## Besatzung eines Schiffs mit Knopf zum Anheuern.
func _crew_line(sh: Dictionary) -> void:
	if sh.state == "sea":
		_details.add_child(UiTheme.label(tr("Besatzung: %d Seeleute an Bord") % sh.crew.size(), 13))
		return
	Sea.fill_crew(sh)
	var need := int(Sea.ship_def(sh).get("crew", 1))
	var have := need - Sea.crew_missing(sh)
	var h := HBoxContainer.new()
	h.add_child(UiTheme.label(tr("Besatzung: %d / %d Seeleute") % [have, need], 13, UiTheme.GOOD if have >= need else UiTheme.BAD))
	if have < need:
		var hb := UiTheme.button(tr("Seemann anheuern"), "person", 32)
		hb.add_theme_font_size_override("font_size", 13)
		hb.tooltip_text = tr("Gibt einem Siedler dieser Insel den Beruf Seemann (zuerst Freie).")
		hb.pressed.connect(func():
			var err := Sea.hire_sailor(sh)
			if err != "":
				hud.toast(err, "person")
			refresh())
		h.add_child(hb)
	_details.add_child(h)


func open_ships() -> void:
	open()
	_go("ships")


func _open_ship(id: int) -> void:
	_ship_id = id
	_go("ship")


# ---------------------------------------------------------------- Inseln: Waren je Insel
const MAIN_GOODS := ["holz", "stein", "bretter", "essen", "werkzeug", "eisen"]
const CELL_BG := Color("#ead7ae")
const CELL_LINE := Color("#b89466")
const RED_BG := Color("#f2c9bd")


## Kasten mit Rahmen (Tabellenzelle, Schiffszeile, Halt der Route).
func _box(bg: Color = CELL_BG, line: Color = CELL_LINE, width: int = 2, pad: int = 6) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = line
	sb.set_border_width_all(width)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Menge einer Spalte: "essen" zählt alle Lebensmittel zusammen.
func _goods_amount(id: String, w) -> int:
	if id == "essen":
		var n := 0
		for f in Data.food_ids():
			n += Game.amount(f, w)
		return n
	return Game.amount(id, w)


func _goods_short(id: String, w, n: int) -> bool:
	if id == "essen":
		return Game.food_days(w) >= 0.0 and Game.food_days(w) < 1.0
	return n < 10


func _goods_columns(islands: Array) -> Array:
	if _goods_mode == "main":
		# Essen einzeln, damit man jedes Nahrungsmittel für Routen und Grenzen antippen kann (josh 2026-10-18)
		var main := []
		for id in MAIN_GOODS:
			if id != "essen":
				main.append(id)
				continue
			for f in Data.sorted_resource_ids():
				if f in Data.food_ids() and islands.any(func(m): return Game.amount(f, Sea.worlds.get(int(m.id))) > 0):
					main.append(f)
		return main
	var cols := []
	for id in Data.sorted_resource_ids():
		if Data.resources[id].get("category", "") == "ship":
			continue
		var have := 0
		var missing := false
		for m in islands:
			var n := Game.amount(id, Sea.worlds.get(int(m.id)))
			have += n
			missing = missing or n < 10
		if have <= 0:
			continue
		if _goods_mode == "missing" and not missing:
			continue
		cols.append(id)
	return cols


func _fill_goods() -> void:
	_steward_row()
	_details.add_child(_wrap(tr("Was liegt auf welcher Insel? Tippe auf eine Insel, um sie auf der Karte zu sehen."), 13))
	var islands := Sea.settled_islands()
	var cols := _goods_columns(islands)
	var grid := GridContainer.new()
	grid.columns = cols.size() + 2
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	grid.add_child(UiTheme.label(tr("Insel"), 13, UiTheme.TEXT, true))
	for id in cols:
		var hc := HBoxContainer.new()
		hc.alignment = BoxContainer.ALIGNMENT_CENTER
		hc.tooltip_text = tr("Essen") if id == "essen" else Data.resource_name(id)
		hc.add_child(UiTheme.icon_rect(Data.icon("beeren") if id == "essen" else Data.res_icon(id), 16))
		if _goods_mode == "main":
			hc.add_child(UiTheme.label(tr("Essen") if id == "essen" else Data.resource_name(id), 12, UiTheme.TEXT, true))
		grid.add_child(hc)
	grid.add_child(UiTheme.label(tr("Seeleute"), 12, UiTheme.TEXT, true))
	for m in islands:
		var w = Sea.worlds.get(int(m.id))
		var nb := UiTheme.button("", "", 40)
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.text = "%s\n%s" % [m.name, tr("%d Siedler") % (w.settlers.size() if w else 0)]
		nb.add_theme_font_size_override("font_size", 12)
		nb.custom_minimum_size = Vector2(118, 40)
		var mid := int(m.id)
		nb.pressed.connect(func():
			_selected = mid
			_go("island"))
		grid.add_child(nb)
		for id in cols:
			var n := _goods_amount(id, w)
			var cell := _box()
			cell.custom_minimum_size = Vector2(56 if _goods_mode == "main" else 44, 40)
			var txt := str(n)
			var lim: Array = Steward.limits(int(m.id), id) if id != "essen" else [0, 0]
			if lim[0] > 0 or lim[1] > 0:
				txt += "\n%s–%s" % [str(lim[0]) if lim[0] > 0 else "", str(lim[1]) if lim[1] > 0 else ""]
			var l := UiTheme.label(txt, 13 if txt.find("\n") < 0 else 11, UiTheme.BAD if _goods_short(id, w, n) else UiTheme.TEXT, true)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cell.add_child(l)
			if Steward.routes_unlocked() and id != "essen":
				var cid := int(m.id)
				var gid: String = id
				cell.mouse_filter = Control.MOUSE_FILTER_STOP
				cell.tooltip_text = tr("Tippen: Mindest- und Höchststand für den Verwalter einstellen")
				cell.gui_input.connect(func(ev):
					if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
						_mm_island = cid
						_mm_good = gid
						refresh())
				if cid == _mm_island and gid == _mm_good:
					var sb: StyleBoxFlat = cell.get_theme_stylebox("panel").duplicate()
					sb.border_color = UiTheme.ACCENT
					sb.set_border_width_all(3)
					cell.add_theme_stylebox_override("panel", sb)
			grid.add_child(cell)
		var free := Sea.free_sailors(w)
		var sc := _box()
		sc.custom_minimum_size = Vector2(64, 40)
		var sl := UiTheme.label(tr("%d frei") % free, 13, UiTheme.GOOD if free > 0 else UiTheme.BAD, true)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sc.add_child(sl)
		grid.add_child(sc)
	# Nur die Tabelle rollt seitlich (viele Spalten auf dem Handy)
	var hs := ScrollContainer.new()
	hs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hs.add_child(grid)
	_details.add_child(hs)
	# Beim Neuaufbau (z. B. nach dem Tipp auf eine Zahl) seitlich an derselben Stelle bleiben
	_keep_hscroll(hs, _goods_hscroll)
	_minmax_editor()
	if cols.is_empty():
		_details.add_child(_hint(tr("Gerade fehlt auf keiner Insel etwas.")))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	chips.add_child(UiTheme.label(tr("Zeigen:"), 13))
	for mode in [["main", tr("Wichtige Waren")], ["all", tr("Alle Waren")], ["missing", tr("Nur was fehlt")]]:
		var b := UiTheme.button(mode[1], "", 32)
		b.add_theme_font_size_override("font_size", 13)
		b.toggle_mode = true
		b.button_pressed = _goods_mode == mode[0]
		var md: String = mode[0]
		b.pressed.connect(func():
			_goods_mode = md
			refresh())
		chips.add_child(b)
	_details.add_child(chips)
	_details.add_child(_hint(tr("Rot: knapp (weniger als 10, beim Essen weniger als ein Tag). Grün: Seeleute, die gerade frei sind und ein Schiff fahren können.")))
	var ex := UiTheme.button(tr("Entdeckungsreise"), "kompass", 36)
	ex.tooltip_text = tr("Das schnellste freie Schiff fährt hinaus und kommt mit einer neuen Insel auf der Karte zurück.")
	ex.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ex.pressed.connect(func():
		var err := Sea.start_explore(Game.world)
		if err != "":
			hud.toast(err, "boot")
		refresh())
	_details.add_child(ex)


## Mindest- und Höchststand einer Ware auf einer Insel (Steward.set_limits): der Verwalter fährt Waren nach.
func _minmax_editor() -> void:
	if not Steward.routes_unlocked():
		return
	if _mm_island < 0 or _mm_good == "" or Sea.worlds.get(_mm_island) == null:
		_details.add_child(_hint(tr("Tippe auf eine Zahl, um für die Ware auf dieser Insel einen Mindest- und Höchststand einzustellen. Der Verwalter fährt dann mit freien Schiffen Waren hin und her.")))
		return
	var w = Sea.worlds.get(_mm_island)
	var box := _box(Color("#f3e6c8"), UiTheme.ACCENT, 2, 8)
	var v := VBoxContainer.new()
	box.add_child(v)
	var head := HBoxContainer.new()
	var t := UiTheme.label(tr("%s auf %s (jetzt %d)") % [Data.resource_name(_mm_good), Sea.island_name(w), Game.amount(_mm_good, w)], 14, UiTheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var done := _small_btn(tr("Fertig"))
	done.pressed.connect(func():
		_mm_island = -1
		refresh())
	head.add_child(done)
	v.add_child(head)
	var iid := _mm_island
	var gid := _mm_good
	for which in [0, 1]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var nm := UiTheme.label(tr("Mindestens") if which == 0 else tr("Höchstens"), 13)
		nm.custom_minimum_size.x = 96
		row.add_child(nm)
		var wi: int = which
		var val := UiTheme.label("", 14, UiTheme.TEXT, true)
		val.custom_minimum_size.x = 64
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var show := func():
			var x: int = Steward.limits(iid, gid)[wi]
			val.text = str(x) if x > 0 else tr("–")
		for step in [-50, -10, 10, 50]:
			if step == 10:
				row.add_child(val)
			var b := _small_btn(("%+d" % step))
			b.custom_minimum_size.x = 44
			var st: int = step
			b.pressed.connect(func():
				var lim: Array = Steward.limits(iid, gid)
				lim[wi] = maxi(0, int(lim[wi]) + st)
				if wi == 1 and lim[1] > 0 and lim[0] > lim[1]:
					lim[0] = lim[1]
				if wi == 0 and lim[1] > 0 and lim[0] > lim[1]:
					lim[1] = lim[0]
				Steward.set_limits(iid, gid, lim[0], lim[1])
				AiRule.player_changed("minmax")
				show.call())
			row.add_child(b)
		show.call()
		v.add_child(row)
	var why := tr("Liegt weniger als der Mindeststand da, holt der Verwalter die Ware von einer anderen Insel. Liegt mehr als der Höchststand da, bringt er den Überschuss weg (zuerst zur Heimatinsel). Dafür nimmt er freie Schiffe ohne Route.")
	if not Steward.on:
		why += " " + tr("Dafür muss der Verwalter eingeschaltet sein.")
	var hl := _hint(why)
	v.add_child(hl)
	_details.add_child(box)


## Verwalter-Steuerung (Steward): Schalter und Inseln, die er nicht schafft.
func _steward_row() -> void:
	if not Steward.unlocked():
		return
	var box := _box(Color("#e3eecf") if Steward.on else CELL_BG, CELL_LINE, 2, 6)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(UiTheme.icon_rect(Data.icon("person"), 20))
	var l := UiTheme.label((tr("Automat steuert die Inseln: an") if Steward.on else tr("Automat steuert die Inseln: aus")) if Steward.automat_mode() else (tr("Verwalter steuert die Berufe: an") if Steward.on else tr("Verwalter steuert die Berufe: aus")), 14, UiTheme.TEXT, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 150
	h.add_child(l)
	var b := _small_btn(tr("Ausschalten") if Steward.on else tr("Einschalten"), "pause" if Steward.on else "play")
	b.tooltip_text = tr("Er verteilt die Berufe nach dem Bedarf: Essen, Brennholz, Lager bis zur Höchstmenge, Werkstätten und Baustellen.")
	b.pressed.connect(func():
		Steward.set_on(not Steward.on)
		refresh())
	h.add_child(b)
	box.add_child(h)
	_details.add_child(box)
	if Steward.on and Steward.net_unlocked():
		var nb := _box(Color("#e3eecf") if Steward.net_on else CELL_BG, CELL_LINE, 2, 6)
		var nh := HBoxContainer.new()
		nh.add_theme_constant_override("separation", 8)
		nh.add_child(UiTheme.icon_rect(Data.icon("papier"), 20))
		var nl := UiTheme.label(tr("Inselverbund: an (Heimatinsel verarbeitet, die anderen liefern)") if Steward.net_on else tr("Inselverbund: aus (jede Insel versorgt sich selbst)"), 14, UiTheme.TEXT, true)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size.x = 150
		nh.add_child(nl)
		var nbt := _small_btn(tr("Ausschalten") if Steward.net_on else tr("Einschalten"), "pause" if Steward.net_on else "play")
		nbt.pressed.connect(func():
			Steward.set_net(not Steward.net_on)
			refresh())
		nh.add_child(nbt)
		nb.add_child(nh)
		_details.add_child(nb)
	if Steward.on:
		for m in Sea.settled_islands():
			var why := Steward.blocked_on(Sea.worlds.get(int(m.id)))
			if why != "":
				_details.add_child(_hint(tr("%s: %s.") % [m.name, why]))


# ---------------------------------------------------------------- Schiffe
func _keep_hscroll(hs: ScrollContainer, x: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame  # erst nach dem Layout ist die Breite bekannt
	if not is_instance_valid(hs):
		return
	hs.scroll_horizontal = x
	hs.get_h_scroll_bar().value_changed.connect(func(v): _goods_hscroll = int(v))


func _small_btn(text: String, icon: String = "") -> Button:
	var b := UiTheme.button(text, icon, 34)
	b.add_theme_font_size_override("font_size", 13)
	return b


## Rot: das Schiff liegt an einer Insel und dort fehlen Seeleute für die Besatzung.
func _ship_red(sh: Dictionary) -> bool:
	if sh.state == "sea":
		return false
	Sea.fill_crew(sh)
	return Sea.crew_missing(sh) > 0


func _fill_ships() -> void:
	if Sea.ships.is_empty():
		_details.add_child(_wrap(tr("Noch keine Schiffe. Die Werft baut sie, wenn ein Handwerker dort arbeitet und ein Liegeplatz frei ist.")))
	for sh in Sea.ships:
		_details.add_child(_ship_row(sh))
	if not Sea.ships.is_empty():
		_details.add_child(_hint(tr("Rot: Auf der Insel, wo das Schiff liegt, gibt es keine freien Seeleute für dieses Schiff.")))
	_details.add_child(_hint(tr("Jedes Schiff braucht einen Liegeplatz auf seiner Heimatinsel: die Werft hat einen für ein Ruderboot, der Anlegesteg zwei, der Hafen zwei für mittlere Schiffe, der Große Hafen drei für alle Schiffe. Mittlere Schiffe laufen nur Inseln mit Hafen an, Galeonen nur Große Häfen.")))


func _ship_row(sh: Dictionary) -> PanelContainer:
	var red := _ship_red(sh)
	var sd := Sea.ship_def(sh)
	var box := _box(RED_BG if red else CELL_BG, UiTheme.BAD if red else CELL_LINE, 3 if red else 2, 8)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(UiTheme.icon_rect(Data.icon(sd.get("icon", "boot")), 28))
	var txt := VBoxContainer.new()
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := Color("#6b1e14") if red else UiTheme.TEXT
	txt.add_child(UiTheme.label(tr("%s · %s · Laderaum %d") % [sh.name, sd.name, int(sd.cargo)], 14, col, true))
	var sub := ""
	if sh.state == "sea":
		sub = Sea.ship_status(sh)
	else:
		var need := int(sd.get("crew", 1))
		var have := need - Sea.crew_missing(sh)
		var crew := tr("Besatzung da") if have >= need else (tr("keine Seeleute da (braucht %d)") % need if have <= 0 else tr("%d von %d Seeleuten da") % [have, need])
		var plan := Sea.plan_text(sh)
		sub = tr("Liegt in %s · %s · %s") % [Sea.meta(int(sh.at)).get("name", "?"), plan if plan != "" else tr("frei"), crew]
		if sh.note != "":
			sub += " · " + str(sh.note)
	if sh.state == "sea" and Sea.plan_text(sh) != "":
		sub += "\n" + Sea.plan_text(sh)
	var sl := UiTheme.label(sub, 12, col)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.custom_minimum_size.x = 220
	txt.add_child(sl)
	top.add_child(txt)
	v.add_child(top)
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 4)
	var sid := int(sh.id)
	if red:
		var hb := _small_btn(tr("Seemann anheuern"), "person")
		hb.tooltip_text = tr("Gibt einem Siedler dieser Insel den Beruf Seemann (zuerst Freie).")
		hb.pressed.connect(func():
			var err := Sea.hire_sailor(sh)
			if err != "":
				hud.toast(err, "person")
			refresh())
		acts.add_child(hb)
	if Sea.is_trip(sh):
		var look := _small_btn(tr("Ansehen"))
		look.pressed.connect(func(): _open_ship(sid))
		acts.add_child(look)
	elif sh.route.size() >= 2:
		var ed := _small_btn(tr("Route ändern"), "anker")
		ed.pressed.connect(func(): _open_ship(sid))
		acts.add_child(ed)
		var run := _small_btn(tr("Anhalten") if not sh.paused else tr("Starten"), "pause" if not sh.paused else "play")
		run.pressed.connect(func():
			_toggle_route(sh)
			refresh())
		acts.add_child(run)
	else:
		var once := _small_btn(tr("Einmal schicken"), "boot")
		once.tooltip_text = tr("Fährt zu einer Insel, lädt dort Waren und bringt sie zu einer anderen Insel. Danach ist das Schiff wieder frei.")
		once.pressed.connect(func(): _open_trip(sid))
		acts.add_child(once)
		var rt := _small_btn(tr("Route"), "anker")
		rt.tooltip_text = tr("Fährt immer wieder von Insel zu Insel und bringt jedes Mal dieselben Waren.")
		rt.pressed.connect(func(): _open_ship(sid))
		acts.add_child(rt)
	v.add_child(acts)
	return box


func _toggle_route(sh: Dictionary) -> void:
	sh.paused = not sh.paused
	sh.note = ""
	if not sh.paused and Sea.is_once(sh):
		Sea.set_route_once(sh, false)  # alte „Einmal hin und zurück“-Routen fahren ab jetzt immer wieder


# ---------------------------------------------------------------- Einmal schicken
func _open_trip(id: int) -> void:
	_ship_id = id
	var sh := Sea.ship_by_id(id)
	var settled := Sea.settled_islands()
	_trip_goods = {}
	_trip_from = int(sh.at) if sh.state != "sea" and Sea.meta(int(sh.at)).get("state", "") == "settled" else int(sh.home)
	_trip_to = -1
	for m in settled:
		if int(m.id) != _trip_from and Sea.can_visit(sh.type, int(m.id)):
			_trip_to = int(m.id)
			break
	_go("trip")


## Knöpfe zur Wahl einer Insel; disabled, wo das Schiff nicht anlegen kann.
func _island_pick(sh: Dictionary, current: int, on_pick: Callable, skip: int = -1) -> HFlowContainer:
	var pick := HFlowContainer.new()
	pick.add_theme_constant_override("h_separation", 4)
	pick.add_theme_constant_override("v_separation", 4)
	for m in Sea.settled_islands():
		var mid := int(m.id)
		var b := _small_btn(m.name)
		b.toggle_mode = true
		b.button_pressed = mid == current
		if not Sea.can_visit(sh.type, mid):
			b.disabled = true
			b.tooltip_text = tr("Hafen zu klein für die %s (%s)") % [sh.name, Sea.ship_def(sh).name]
		elif mid == skip:
			b.disabled = true
		b.pressed.connect(func(): on_pick.call(mid))
		pick.add_child(b)
	return pick


func _step_head(n: String, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var badge := _box(Color("#8a5a2e"), Color("#4a3020"), 2, 2)
	badge.custom_minimum_size = Vector2(28, 28)
	var bl := UiTheme.label(n, 14, UiTheme.TEXT_LIGHT, true)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(bl)
	h.add_child(badge)
	h.add_child(UiTheme.label(text, 15, UiTheme.TEXT, true))
	return h


func _fill_trip() -> void:
	var sh := Sea.ship_by_id(_ship_id)
	if sh.is_empty():
		_go("ships")
		return
	var sd := Sea.ship_def(sh)
	var head := HBoxContainer.new()
	var t := UiTheme.label(tr("%s einmal schicken") % sh.name, 16, UiTheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_back_btn("ships"))
	_details.add_child(head)
	if Sea.settled_islands().size() < 2:
		_details.add_child(_wrap(tr("Dafür braucht es zwei besiedelte Inseln. Besiedle zuerst eine zweite Insel (Karte > Schiff hierher schicken)."), 13, UiTheme.BAD))
		return
	# 1. Ladeinsel
	_details.add_child(_step_head("1", tr("Fahre nach")))
	_details.add_child(_island_pick(sh, _trip_from, func(mid):
		_trip_from = mid
		if _trip_to == mid:
			_trip_to = -1
		_trip_goods = {}
		refresh()))
	if sh.state != "sea" and int(sh.at) == _trip_from:
		_details.add_child(_hint(tr("Die %s liegt schon dort und lädt gleich.") % sh.name))
	# 2. Waren
	_details.add_child(_step_head("2", tr("Lade ein")))
	var w = Sea.worlds.get(_trip_from)
	var summary := _wrap("", 14)
	var info := _hint("")
	var upd := func():
		var used := 0
		for id in _trip_goods:
			used += int(_trip_goods[id]) * Data.good_size(id)
		var to_name: String = Sea.meta(_trip_to).get("name", "?") if _trip_to >= 0 else "?"
		var from_name: String = Sea.meta(_trip_from).get("name", "?")
		var what := Sea.goods_text(_trip_goods) if not _trip_goods.is_empty() else tr("nichts")
		summary.text = tr("Die %s fährt nach %s, lädt %s und bringt es nach %s. Dort lädt sie alles ab und ist wieder frei.") % [sh.name, from_name, what, to_name]
		var days := 0.0
		if _trip_to >= 0:
			days = Sea.voyage_days(_trip_from, _trip_to, sh.type)
			if sh.state != "sea" and int(sh.at) != _trip_from:
				days += Sea.voyage_days(int(sh.at), _trip_from, sh.type)
		info.text = tr("Laderaum %d / %d · Fahrzeit etwa %d Stunden") % [used, int(sd.cargo), int(ceil(days * 24.0))]
	var any := false
	for id in Data.sorted_resource_ids():
		if Data.resources[id].get("category", "") == "ship" or Game.amount(id, w) <= 0:
			continue
		any = true
		var rid: String = id
		var get_n := func(): return int(_trip_goods.get(rid, 0))
		var set_n := func(n: int):
			var used := 0
			for k in _trip_goods:
				if k != rid:
					used += int(_trip_goods[k]) * Data.good_size(k)
			n = clamp(n, 0, min(Game.amount(rid, w), (int(sd.cargo) - used) / max(1, Data.good_size(rid))))
			if n <= 0:
				_trip_goods.erase(rid)
			else:
				_trip_goods[rid] = n
			upd.call()
		_details.add_child(_goods_row(id, tr("dort %d") % Game.amount(id, w), get_n, set_n, 10))
	if not any:
		_details.add_child(_hint(tr("Auf %s liegt nichts im Lager.") % Sea.meta(_trip_from).get("name", "?")))
	# 3. Zielinsel
	_details.add_child(_step_head("3", tr("Bringe es nach")))
	_details.add_child(_island_pick(sh, _trip_to, func(mid):
		_trip_to = mid
		refresh(), _trip_from))
	var sum_box := _box()
	var sv := VBoxContainer.new()
	sv.add_child(summary)
	sv.add_child(info)
	sum_box.add_child(sv)
	_details.add_child(sum_box)
	upd.call()
	_crew_line(sh)
	var go := UiTheme.button(tr("Ablegen"), "boot", 40)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func():
		var err := Sea.start_trip(sh, _trip_from, _trip_to, _trip_goods)
		if err != "":
			hud.toast(err, "boot")
			return
		hud.toast(Sea.plan_text(sh), "boot")
		_go("ships"))
	_details.add_child(go)


# ---------------------------------------------------------------- Route
func _new_stop(island: int, drop_all: bool = true) -> Dictionary:
	return {"island": island, "load": {}, "drop_all": drop_all, "drop": {}}


## Was ein Halt tut, in einer Zeile: „lädt alles ab · lädt ein: Stein 150“.
func _stop_text(st: Dictionary) -> String:
	var parts := []
	if Sea.stop_drop_all(st):
		parts.append(tr("lädt alles ab"))
	elif not st.get("drop", {}).is_empty():
		parts.append(tr("lädt ab: %s") % Sea.goods_text(st.drop))
	if not st.get("load", {}).is_empty():
		parts.append(tr("lädt ein: %s") % Sea.goods_text(st.load))
	return " · ".join(PackedStringArray(parts)) if not parts.is_empty() else tr("legt nur an")


func _fill_ship() -> void:
	var sh := Sea.ship_by_id(_ship_id)
	if sh.is_empty():
		_go("ships")
		return
	var sd := Sea.ship_def(sh)
	var head := HBoxContainer.new()
	head.add_child(UiTheme.icon_rect(Data.icon(sd.get("icon", "boot")), 24))
	var t := UiTheme.label(tr("Fahrt der %s") % sh.name if Sea.is_trip(sh) else tr("Route der %s") % sh.name, 16, UiTheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_back_btn("ships"))
	_details.add_child(head)
	_details.add_child(_wrap(Sea.ship_status(sh), 13, UiTheme.BAD if sh.note != "" else UiTheme.TEXT))
	_crew_line(sh)
	_details.add_child(_wrap(tr("Ladung (%d / %d): %s") % [Sea.cargo_volume(sh), int(sd.cargo), Sea.goods_text(sh.cargo)], 12))
	if Sea.is_trip(sh):
		_details.add_child(_wrap(Sea.plan_text(sh), 14))
		var stop := _small_btn(tr("Fahrt abbrechen"), "abriss")
		stop.tooltip_text = tr("Das Schiff fährt noch zum nächsten Halt und lädt dort alles ab.")
		stop.pressed.connect(func():
			Sea.cancel_trip(sh)
			refresh())
		_details.add_child(stop)
		return
	if Sea.settled_islands().size() < 2 and sh.route.size() < 2:
		_details.add_child(_wrap(tr("Für eine Route braucht es zwei besiedelte Inseln."), 13, UiTheme.BAD))
		return
	if sh.route.size() < 2:  # neue Route: von hier zur nächsten Insel, angehalten bis „Route starten“
		var a := int(sh.at) if sh.state != "sea" and Sea.meta(int(sh.at)).get("state", "") == "settled" else int(sh.home)
		var b := a
		for m in Sea.settled_islands():
			if int(m.id) != a and Sea.can_visit(sh.type, int(m.id)):
				b = int(m.id)
				break
		sh.route = [_new_stop(a), _new_stop(b)]
		sh.leg = 0
		sh.paused = true
		Sea.set_route_once(sh, false)
	_details.add_child(_hint(tr("Das Schiff fährt die Halte der Reihe nach ab und dann wieder von vorn, bis du die Route anhältst.")))
	var n: int = sh.route.size()
	for i in n:
		var st: Dictionary = sh.route[i]
		var mid := i > 0 and i < n - 1
		var box := _box(Color("#f3e6c8") if mid else CELL_BG, CELL_LINE, 2, 8)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var letter := "A" if i == 0 else ("B" if i == n - 1 else "+")
		var badge := _box(Color("#3f6e2c") if i == 0 else (Color("#a35a2a") if i == n - 1 else Color("#d9b27a")), Color("#4a3020"), 2, 2)
		badge.custom_minimum_size = Vector2(28, 28)
		var bl := UiTheme.label(letter, 14, UiTheme.TEXT if mid else UiTheme.TEXT_LIGHT, true)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_child(bl)
		row.add_child(badge)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm: String = Sea.meta(int(st.island)).get("name", "?")
		var cur: bool = int(sh.leg) == i and not sh.paused
		tv.add_child(UiTheme.label((tr("Zwischenhalt: %s") % nm if mid else nm) + (tr("  (fährt hierhin)") if cur else ""), 14,
			UiTheme.GOOD if cur else UiTheme.TEXT, true))
		var dl := UiTheme.label(_stop_text(st), 12)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size.x = 160
		tv.add_child(dl)
		row.add_child(tv)
		var ed := _small_btn(tr("Ändern"))
		var ii: int = i
		ed.pressed.connect(func():
			_stop_i = ii
			_go("stop"))
		row.add_child(ed)
		if mid:
			var rm := UiTheme.button("", "abriss", 34)
			rm.tooltip_text = tr("Zwischenhalt entfernen")
			rm.pressed.connect(func():
				sh.route.remove_at(ii)
				sh.leg = int(sh.leg) % sh.route.size()
				refresh())
			row.add_child(rm)
		box.add_child(row)
		_details.add_child(box)
		if i < n - 1:
			_details.add_child(UiTheme.label("   ↓", 16, Color("#6b4a2b")))
	_details.add_child(UiTheme.label(tr("   ↺ zurück zu A, dann von vorn"), 13, Color("#6b4a2b")))
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	if n < 6:
		var add := _small_btn(tr("+ Zwischenhalt"))
		add.tooltip_text = tr("Ein Halt zwischen A und B, um dort etwas dazuzuladen oder auszutauschen.")
		add.pressed.connect(func():
			var prev := int(sh.route[-2].island)
			var last := int(sh.route[-1].island)
			var pick := prev
			for m in Sea.settled_islands():
				if int(m.id) != prev and int(m.id) != last and Sea.can_visit(sh.type, int(m.id)):
					pick = int(m.id)
					break
			sh.route.insert(sh.route.size() - 1, _new_stop(pick, false))
			_stop_i = sh.route.size() - 2
			_go("stop"))
		acts.add_child(add)
	var run := UiTheme.button(tr("Route anhalten") if not sh.paused else tr("Route starten"), "pause" if not sh.paused else "play", 36)
	run.pressed.connect(func():
		_toggle_route(sh)
		refresh())
	acts.add_child(run)
	var clear := _small_btn(tr("Route auflösen"), "abriss")
	clear.tooltip_text = tr("Löscht die Route. Das Schiff ist danach frei.")
	clear.pressed.connect(func():
		sh.route = []
		sh.leg = 0
		sh.paused = false
		sh.note = ""
		Sea.set_route_once(sh, false)
		_go("ships"))
	acts.add_child(clear)
	if sh.state != "sea" and Game.world and int(sh.at) != Game.world.island_id and Sea.worlds.has(int(sh.at)):
		var look := _small_btn(tr("Ansehen"), "play")
		look.pressed.connect(func():
			visible = false
			Sea.switch_to(int(sh.at)))
		acts.add_child(look)
	if sh.state != "sea" and not sh.cargo.is_empty() and sh.paused:
		var ul := _small_btn(tr("Hier abladen"), "kiste")
		ul.pressed.connect(func():
			var got := Sea.unload_goods(sh)
			hud.toast(tr("Abgeladen: %s") % Sea.goods_text(got) if not got.is_empty() else tr("Im Lager ist kein Platz."), "kiste")
			refresh())
		acts.add_child(ul)
	_details.add_child(acts)
	_details.add_child(_hint(tr("Liegt nicht genug im Lager, nimmt das Schiff, was da ist, und fährt weiter.")))


# ---------------------------------------------------------------- Halt bearbeiten
func _fill_stop() -> void:
	var sh := Sea.ship_by_id(_ship_id)
	if sh.is_empty() or _stop_i < 0 or _stop_i >= sh.route.size():
		_go("ship")
		return
	var st: Dictionary = sh.route[_stop_i]
	var sd := Sea.ship_def(sh)
	var n: int = sh.route.size()
	var letter := "A" if _stop_i == 0 else ("B" if _stop_i == n - 1 else tr("Zwischenhalt"))
	var head := HBoxContainer.new()
	var t := UiTheme.label(tr("Halt %s der %s") % [letter, sh.name], 16, UiTheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var done := UiTheme.button(tr("Fertig"), "play", 36)
	done.pressed.connect(func(): _go("ship"))
	head.add_child(done)
	_details.add_child(head)
	_details.add_child(UiTheme.label(tr("Insel"), 14, UiTheme.TEXT, true))
	_details.add_child(_island_pick(sh, int(st.island), func(mid):
		st.island = mid
		refresh()))
	var w = Sea.worlds.get(int(st.island))
	# Abladen
	_details.add_child(UiTheme.label(tr("Hier abladen"), 14, UiTheme.TEXT, true))
	var all_on := Sea.stop_drop_all(st)
	var modes := HFlowContainer.new()
	modes.add_theme_constant_override("h_separation", 6)
	for opt in [[true, tr("Alles abladen")], [false, tr("Nur bestimmte Waren")]]:
		var b := _small_btn(opt[1])
		b.toggle_mode = true
		b.button_pressed = all_on == opt[0]
		var on: bool = opt[0]
		b.pressed.connect(func():
			st["drop_all"] = on
			if not st.has("drop"):
				st["drop"] = {}
			refresh())
		modes.add_child(b)
	_details.add_child(modes)
	if all_on:
		_details.add_child(_hint(tr("Das Schiff lädt hier alles ab, was es nicht hier einlädt.")))
	else:
		if not st.has("drop"):
			st["drop"] = {}
		var drop: Dictionary = st.drop
		var ids := []
		for s2 in sh.route:
			for id in s2.get("load", {}):
				if not id in ids:
					ids.append(id)
		for id in sh.cargo:
			if not id in ids:
				ids.append(id)
		for id in drop:
			if not id in ids:
				ids.append(id)
		if ids.is_empty():
			_details.add_child(_hint(tr("Stelle zuerst an einem anderen Halt ein, was das Schiff einlädt.")))
		for id in ids:
			var rid: String = id
			var get_n := func(): return int(drop.get(rid, 0))
			var set_n := func(v: int):
				v = clamp(v, 0, int(sd.cargo))
				if v <= 0:
					drop.erase(rid)
				else:
					drop[rid] = v
			_details.add_child(_goods_row(id, tr("Lager %d") % Game.amount(id, w) if w else "", get_n, set_n, 10))
	# Einladen
	var load: Dictionary = st.load
	var room_l := UiTheme.label("", 14, UiTheme.TEXT, true)
	var upd := func():
		var used := 0
		for id in load:
			used += int(load[id]) * Data.good_size(id)
		room_l.text = tr("Hier einladen: %d / %d Laderaum") % [used, int(sd.cargo)]
	upd.call()
	_details.add_child(room_l)
	_details.add_child(_hint(tr("Das Schiff füllt bis zu dieser Menge auf. Liegt weniger im Lager, nimmt es, was da ist.") if all_on
		else tr("Das Schiff lädt diese Menge zusätzlich ein. Liegt weniger im Lager, nimmt es, was da ist.")))
	var shown := 0
	for id in Data.sorted_resource_ids():
		if Data.resources[id].get("category", "") == "ship":
			continue
		if not load.has(id) and Game.amount(id, w) <= 0:
			continue
		shown += 1
		var rid: String = id
		var get_n := func(): return int(load.get(rid, 0))
		var set_n := func(v: int):
			var used := 0
			for k in load:
				if k != rid:
					used += int(load[k]) * Data.good_size(k)
			v = clamp(v, 0, (int(sd.cargo) - used) / max(1, Data.good_size(rid)))
			if v <= 0:
				load.erase(rid)
			else:
				load[rid] = v
			upd.call()
		_details.add_child(_goods_row(id, tr("Lager %d") % Game.amount(id, w) if w else "", get_n, set_n, 10))
	if shown == 0:
		_details.add_child(_hint(tr("Auf %s liegt gerade nichts im Lager.") % Sea.meta(int(st.island)).get("name", "?")))
	var done2 := UiTheme.button(tr("Fertig"), "play", 40)
	done2.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	done2.pressed.connect(func(): _go("ship"))
	_details.add_child(done2)
