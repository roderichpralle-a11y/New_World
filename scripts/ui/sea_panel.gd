class_name SeaPanel
extends PanelContainer
## Seekarte: alle entdeckten Inseln, Schiffe, Routen, Erkunden und Siedler aussenden.

var hud  # Hud (fuer Meldungen und Kamera)
var _selected: int = 0
var _view: String = "island"  # island, send, ships, ship, stop
var _send_sel: Array = []
var _send_goods: Dictionary = {}
var _send_ship: int = -1
var _ship_id: int = -1
var _stop_i: int = -1
var _tab_islands: Button
var _tab_ships: Button
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
	var t := UiTheme.label(tr("Seekarte"), 20, UiTheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_tab_islands = UiTheme.button(tr("Inseln"), "kompass", 32)
	_tab_islands.toggle_mode = true
	_tab_islands.pressed.connect(func(): _go("island"))
	head.add_child(_tab_islands)
	_tab_ships = UiTheme.button(tr("Schiffe"), "anker", 32)
	_tab_ships.toggle_mode = true
	_tab_ships.pressed.connect(func(): _go("ships"))
	head.add_child(_tab_ships)
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
	Sea.islands_changed.connect(refresh)
	Game.stock_changed.connect(func():
		if visible:
			_update_head())
	get_viewport().size_changed.connect(_fit)


func open() -> void:
	_selected = Game.world.island_id if Game.world else 0
	_view = "island"
	_fit()
	refresh()


## Liste unter der Karte so hoch wie der Platz auf dem Bildschirm erlaubt.
func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	_scroll.custom_minimum_size.y = clamp(vs.y - 365.0, 130.0, 460.0)
	_map.custom_minimum_size.x = clamp(vs.x - 40.0, 300.0, 420.0)


func refresh() -> void:
	if not is_inside_tree():
		return
	_update_head()
	_fill_details()
	_map.queue_redraw()


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
	refresh()
	_scroll.scroll_vertical = 0


func _fill_details() -> void:
	_clear()
	_tab_islands.set_pressed_no_signal(_view in ["island", "send"])
	_tab_ships.set_pressed_no_signal(_view in ["ships", "ship", "stop"])
	match _view:
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
	var ex := UiTheme.button(tr("Neue Insel suchen"), "kompass", 38)
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


func _fill_ships() -> void:
	_details.add_child(UiTheme.label(tr("Deine Schiffe"), 16, UiTheme.TEXT, true))
	if Sea.ships.is_empty():
		_details.add_child(_wrap(tr("Noch keine Schiffe. Die Werft baut sie, wenn ein Handwerker dort arbeitet und ein Liegeplatz frei ist.")))
	for sh in Sea.ships:
		var b := UiTheme.button("%s (%s): %s" % [sh.name, Sea.ship_def(sh).name, Sea.ship_status(sh)], Sea.ship_def(sh).get("icon", "boot"), 36)
		b.add_theme_font_size_override("font_size", 13)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size.x = 330
		var sid := int(sh.id)
		b.pressed.connect(func(): _open_ship(sid))
		_details.add_child(b)
	_details.add_child(_hint(tr("Jedes Schiff braucht einen Liegeplatz auf seiner Heimatinsel: die Werft hat einen für ein Ruderboot, der Anlegesteg zwei, der Hafen zwei für mittlere Schiffe, der Große Hafen drei für alle Schiffe. Mittlere Schiffe laufen nur Inseln mit Hafen an, Galeonen nur Große Häfen.")))


func _fill_ship() -> void:
	var sh := Sea.ship_by_id(_ship_id)
	if sh.is_empty():
		_go("ships")
		return
	var sd := Sea.ship_def(sh)
	var top := HBoxContainer.new()
	top.add_child(UiTheme.icon_rect(Data.icon(sd.get("icon", "boot")), 24))
	top.add_child(UiTheme.label(Sea.ship_label(sh), 16, UiTheme.TEXT, true))
	_details.add_child(top)
	_details.add_child(_wrap(Sea.ship_status(sh), 13, UiTheme.BAD if sh.note != "" else UiTheme.TEXT))
	_details.add_child(_wrap(tr("Laderaum %d, %d Fahrgäste, Tempo x%.1f. Heimathafen: %s.") % [int(sd.cargo), Sea.passenger_capacity(sh),
		float(sd.speed), Sea.meta(int(sh.home)).get("name", "?")], 12))
	_crew_line(sh)
	_details.add_child(_wrap(tr("Ladung (%d / %d): %s") % [Sea.cargo_volume(sh), int(sd.cargo), Sea.goods_text(sh.cargo)], 13))
	# Route
	_details.add_child(UiTheme.label(tr("Route"), 15, UiTheme.TEXT, true))
	if sh.route.is_empty():
		_details.add_child(_hint(tr("Eine Route fährt von Insel zu Insel, immer wieder oder einmal hin und zurück. An jedem Halt lädt das Schiff, was du dort einstellst, und lädt alles andere ab.")))
	for i in sh.route.size():
		var st: Dictionary = sh.route[i]
		var row := HBoxContainer.new()
		var cur: bool = int(sh.leg) == i and not sh.paused
		var l := UiTheme.label(tr("%d. %s: lädt %s") % [i + 1, Sea.meta(int(st.island)).get("name", "?"), Sea.goods_text(st.get("load", {}))], 13,
			UiTheme.GOOD if cur else UiTheme.TEXT, cur)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 200
		row.add_child(l)
		var ed := UiTheme.button(tr("Ändern"), "", 30)
		ed.add_theme_font_size_override("font_size", 12)
		var ii: int = i
		ed.pressed.connect(func():
			_stop_i = ii
			_go("stop"))
		row.add_child(ed)
		var rm := UiTheme.button("", "abriss", 30)
		rm.tooltip_text = tr("Halt entfernen")
		rm.pressed.connect(func():
			sh.route.remove_at(ii)
			sh.leg = 0
			Sea.set_route_once(sh, Sea.is_once(sh))
			refresh())
		row.add_child(rm)
		_details.add_child(row)
	if sh.route.size() >= 2:
		_route_mode_row(sh)
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	if sh.route.size() < 6:
		var add := UiTheme.button(tr("Halt hinzufügen"), "anker", 36)
		add.pressed.connect(func():
			var last := int(sh.route[-1].island) if not sh.route.is_empty() else (int(sh.at) if sh.state != "sea" else int(sh.home))
			var next_i := last
			for m in Sea.settled_islands():
				if int(m.id) != last:
					next_i = int(m.id)
					break
			if sh.route.is_empty():
				sh.route.append({"island": last, "load": {}})
				if next_i != last:
					sh.route.append({"island": next_i, "load": {}})
			else:
				sh.route.append({"island": next_i, "load": {}})
			sh.paused = true
			Sea.set_route_once(sh, Sea.is_once(sh))
			_stop_i = sh.route.size() - 1
			_go("stop"))
		acts.add_child(add)
	if sh.route.size() >= 2:
		var run := UiTheme.button(tr("Route anhalten") if not sh.paused else tr("Route starten"), "pause" if not sh.paused else "play", 36)
		run.pressed.connect(func():
			sh.paused = not sh.paused
			sh.note = ""
			refresh())
		acts.add_child(run)
	if sh.state != "sea" and sh.at != Game.world.island_id and Sea.worlds.has(int(sh.at)):
		var look := UiTheme.button(tr("Ansehen"), "play", 36)
		look.pressed.connect(func():
			visible = false
			Sea.switch_to(int(sh.at)))
		acts.add_child(look)
	_details.add_child(acts)
	if sh.state != "sea" and not sh.cargo.is_empty() and (sh.route.is_empty() or sh.paused):
		var ul := UiTheme.button(tr("Hier abladen"), "kiste", 36)
		ul.pressed.connect(func():
			var got := Sea.unload_goods(sh)
			hud.toast(tr("Abgeladen: %s") % Sea.goods_text(got) if not got.is_empty() else tr("Im Lager ist kein Platz."), "kiste")
			refresh())
		_details.add_child(ul)
	_details.add_child(_back_btn("ships"))


## Fahrtart der Route: „Immer wieder“ oder „Einmal hin und zurück“ (Sea.set_route_once), dazu der Stand.
func _route_mode_row(sh: Dictionary) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	row.add_child(UiTheme.label(tr("Fahrt:"), 13, UiTheme.TEXT, true))
	for once in [false, true]:
		var b := UiTheme.button(tr("Einmal hin und zurück") if once else tr("Immer wieder"), "", 32)
		b.add_theme_font_size_override("font_size", 13)
		b.toggle_mode = true
		b.button_pressed = Sea.is_once(sh) == once
		b.tooltip_text = tr("Das Schiff fährt alle Halte einmal ab, kommt zum ersten Halt zurück, lädt dort alles ab und ist dann wieder frei.") if once \
			else tr("Das Schiff fährt die Halte immer wieder ab, bis du die Route anhältst.")
		var on: bool = once
		b.pressed.connect(func():
			if Sea.is_once(sh) != on:
				Sea.set_route_once(sh, on)
			refresh())
		row.add_child(b)
	_details.add_child(row)
	if Sea.is_once(sh):
		var left := Sea.once_stops_left(sh)
		var t := (tr("Noch %d Halte, dann ist das Schiff wieder frei.") % left if left > 1 else tr("Noch ein Halt, dann ist das Schiff wieder frei.")) if left > 0 and not sh.paused \
			else tr("Startet am Halt, den das Schiff als Nächstes anläuft, und kommt dorthin zurück.")
		_details.add_child(_hint(t))


func _fill_stop() -> void:
	var sh := Sea.ship_by_id(_ship_id)
	if sh.is_empty() or _stop_i < 0 or _stop_i >= sh.route.size():
		_go("ship")
		return
	var st: Dictionary = sh.route[_stop_i]
	var sd := Sea.ship_def(sh)
	_details.add_child(UiTheme.label(tr("Halt %d der %s") % [_stop_i + 1, sh.name], 16, UiTheme.TEXT, true))
	var pick := HFlowContainer.new()
	pick.add_theme_constant_override("h_separation", 4)
	pick.add_theme_constant_override("v_separation", 4)
	for m in Sea.settled_islands():
		var b := UiTheme.button(m.name, "", 32)
		b.add_theme_font_size_override("font_size", 13)
		b.toggle_mode = true
		b.button_pressed = int(m.id) == int(st.island)
		var mid := int(m.id)
		if not Sea.can_visit(sh.type, mid):
			b.disabled = true
			b.tooltip_text = tr("Hafen zu klein für die %s (%s)") % [sh.name, sd.name]
		b.pressed.connect(func():
			st.island = mid
			refresh())
		pick.add_child(b)
	_details.add_child(pick)
	var w = Sea.worlds.get(int(st.island))
	var load: Dictionary = st.load
	var room_l := UiTheme.label("", 14, UiTheme.TEXT, true)
	var upd := func():
		var used := 0
		for id in load:
			used += int(load[id]) * Data.good_size(id)
		room_l.text = tr("Hier laden: %d / %d Laderaum") % [used, int(sd.cargo)]
	upd.call()
	_details.add_child(room_l)
	_details.add_child(_hint(tr("Alles, was hier nicht geladen wird, lädt das Schiff an diesem Halt ab. Lädt mehr, wenn mehr im Lager liegt.")))
	for id in Data.sorted_resource_ids():
		if Data.resources[id].get("category", "") == "ship":
			continue
		var rid: String = id
		var get_n := func(): return int(load.get(rid, 0))
		var set_n := func(n: int):
			var used := 0
			for k in load:
				if k != rid:
					used += int(load[k]) * Data.good_size(k)
			n = clamp(n, 0, (int(sd.cargo) - used) / max(1, Data.good_size(rid)))
			if n <= 0:
				load.erase(rid)
			else:
				load[rid] = n
			upd.call()
		_details.add_child(_goods_row(id, tr("Lager %d") % Game.amount(id, w) if w else "", get_n, set_n, 10))
	var done := UiTheme.button(tr("Fertig"), "play", 40)
	done.pressed.connect(func(): _go("ship"))
	_details.add_child(done)
