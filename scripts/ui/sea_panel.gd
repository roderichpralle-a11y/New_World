class_name SeaPanel
extends PanelContainer
## Seekarte: alle entdeckten Inseln, Schiffsreisen, Erkunden und Siedler aussenden.

var hud  # Hud (fuer Meldungen und Kamera)
var _selected: int = 0
var _sending: bool = false
var _send_sel: Array = []
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
	var t := UiTheme.label("Seekarte", 20, UiTheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := UiTheme.button("", "abriss", 32)
	x.tooltip_text = "Schließen"
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
	_map.tooltip_text = "Mausrad oder zwei Finger: zoomen. Ziehen: Karte verschieben."
	v.add_child(_map)
	_zoom_btns = HBoxContainer.new()
	_zoom_btns.add_theme_constant_override("separation", 4)
	var zin := UiTheme.button("+", "", 30)
	zin.tooltip_text = "Hineinzoomen"
	zin.custom_minimum_size.x = 30
	zin.pressed.connect(func(): _zoom_at(_map.size / 2.0, 1.5))
	var zout := UiTheme.button("-", "", 30)
	zout.tooltip_text = "Herauszoomen"
	zout.custom_minimum_size.x = 30
	zout.pressed.connect(func(): _zoom_at(_map.size / 2.0, 1.0 / 1.5))
	var zall := UiTheme.button("Alle", "", 30)
	zall.tooltip_text = "Alle Inseln zeigen"
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
		if visible and not _sending:
			_update_head())


func open() -> void:
	_selected = Game.world.island_id if Game.world else 0
	_sending = false
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	_update_head()
	_fill_details()
	_map.queue_redraw()


func _update_head() -> void:
	var at_sea := Sea.people_at_sea()
	var t := "Boote: %d   Bewohnte Inseln: %d" % [Game.amount("boot"), Sea.settled_islands().size()]
	if at_sea > 0:
		t += "   Auf See: %d Siedler" % at_sea
	if Sea.exploring():
		t += "   Ein Boot erkundet."
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
		_map.draw_texture_rect(Data.icon("boot"), Rect2(bp - Vector2(10, 14), Vector2(20, 20)), false)
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
		_sending = false
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


func _fill_details() -> void:
	_clear()
	if _sending:
		_fill_send()
		return
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
			state = "Besiedelt: %d Siedler" % (w.settlers.size() if w else 0)
			if here:
				state += " (hier bist du)"
		"discovered":
			state = "Unbewohnt. Schicke Siedler hierher, um sie zu besiedeln."
		"lost":
			state = "Verloren. Niemand kann hier mehr leben."
	_details.add_child(_wrap(state, 13, UiTheme.BAD if m.state == "lost" else UiTheme.TEXT))
	# Gefahren und Besonderheiten
	var dangers := Sea.dangers(m)
	var h := HBoxContainer.new()
	h.add_child(UiTheme.label("Gefahr:", 13))
	if dangers.is_empty():
		h.add_child(UiTheme.label("keine", 13, UiTheme.GOOD))
	for a in dangers:
		h.add_child(UiTheme.icon_rect(Data.icon(a), 16))
		h.add_child(UiTheme.label(Data.animals[a].name, 13, UiTheme.BAD))
	if w and m.state == "settled":
		h.add_child(UiTheme.label("(%d Tiere)" % w.animals.size(), 12))
	_details.add_child(h)
	var special: Array = Sea.biome_def(m).get("special", [])
	if not special.is_empty():
		var hs := HBoxContainer.new()
		hs.add_child(UiTheme.label("Reich an:", 13))
		for r in special:
			hs.add_child(UiTheme.icon_rect(Data.res_icon(r), 16))
			hs.add_child(UiTheme.label(Data.resource_name(r), 13))
		_details.add_child(hs)
	if not here and Game.world and m.state != "lost":
		var hours := Sea.voyage_days(Game.world.island_id, int(m.id)) * 24.0
		_details.add_child(UiTheme.label("Fahrzeit von hier: %d Stunden" % int(ceil(hours)), 13))
	# Aktionen
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	if m.state == "settled" and not here and w:
		var go := UiTheme.button("Ansehen", "play", 38)
		go.pressed.connect(func():
			visible = false
			Sea.switch_to(int(m.id)))
		acts.add_child(go)
	if m.state != "lost" and not here:
		var send := UiTheme.button("Siedler schicken", "boot", 38)
		send.pressed.connect(func():
			_sending = true
			_send_sel = []
			refresh())
		acts.add_child(send)
	var ex := UiTheme.button("Neue Insel suchen", "kompass", 38)
	ex.tooltip_text = "Ein Boot fährt hinaus und kommt mit einer neuen Insel auf der Karte zurück."
	ex.pressed.connect(func():
		var err := Sea.start_explore(Game.world)
		if err != "":
			hud.toast(err, "boot")
		refresh())
	acts.add_child(ex)
	_details.add_child(acts)
	var why := Sea.can_explore()
	if why != "" and not Sea.exploring():
		_details.add_child(_wrap("Neue Inseln suchen: %s" % why, 12, Color("#8a5a3a")))
	if Data.buildings.has("werft") and not Game.is_unlocked("werft"):
		_details.add_child(_wrap("Boote baut die Werft. Dafür braucht es die Forschung Schiffsbau.", 12, Color("#8a5a3a")))


func _fill_send() -> void:
	var m := Sea.meta(_selected)
	_details.add_child(UiTheme.label("Siedler nach %s schicken" % m.name, 16, UiTheme.TEXT, true))
	var cap := Sea.ship_capacity()
	var count := UiTheme.label("Im Boot: %d / %d" % [_send_sel.size(), cap], 14, UiTheme.TEXT, true)
	_details.add_child(count)
	if m.state == "discovered":
		_details.add_child(_wrap("Tipp: Schicke eine Frau und einen Mann mit, damit es dort Kinder gibt. Ein Baumeister baut die ersten Hütten.", 12))
	if not Sea.dangers(m).is_empty():
		_details.add_child(_wrap("Achtung, wilde Tiere! Jäger mit Speeren schützen die Siedler.", 12, UiTheme.BAD))
	var list: Array = Game.world.settlers.duplicate()
	list.sort_custom(func(a, b): return a.age > b.age)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for s in list:
		var who := ("Frau" if s.sex == "f" else "Mann") if s.is_adult() else "Kind"
		var b := UiTheme.button("%s, %s" % [s.display_name, s.job_name() if s.is_adult() else who], "", 34)
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = "%s, %d Jahre" % [who, int(s.age)]
		b.toggle_mode = true
		b.button_pressed = _send_sel.has(s)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 160
		var sref = s
		b.toggled.connect(func(on):
			if on and not _send_sel.has(sref):
				if _send_sel.size() >= cap:
					b.set_pressed_no_signal(false)
					hud.toast("Ins Boot passen nur %d Siedler." % cap, "boot")
					return
				_send_sel.append(sref)
			elif not on:
				_send_sel.erase(sref)
			count.text = "Im Boot: %d / %d" % [_send_sel.size(), cap])
		grid.add_child(b)
	_details.add_child(grid)
	var acts := HBoxContainer.new()
	var go := UiTheme.button("Ablegen", "boot", 40)
	go.pressed.connect(func():
		var alive := _send_sel.filter(func(x): return is_instance_valid(x))
		var err := Sea.send_settlers(Game.world, _selected, alive)
		if err != "":
			hud.toast(err, "boot")
			return
		_sending = false
		_send_sel = []
		refresh())
	acts.add_child(go)
	var back := UiTheme.button("Zurück", "abriss", 40)
	back.pressed.connect(func():
		_sending = false
		refresh())
	acts.add_child(back)
	_details.add_child(acts)
