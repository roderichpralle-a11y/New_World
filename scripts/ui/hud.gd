class_name Hud
extends CanvasLayer
## Gesamte Bedienoberflaeche: Vorratsleiste, Bau-Menue, Siedlerliste,
## Infofenster, Meldungen, Titel- und Endbildschirm. Touch und Maus.

signal new_game_requested
signal continue_requested

var world: World
var camera: GameCamera

var root: Control
var _res_labels: Dictionary = {}
var _food_label: Label
var _pop_label: Label
var _day_label: Label
var _day_icon: TextureRect
var _speed_btns: Array = []
var _bottom: HBoxContainer
var _build_panel: PanelContainer
var _settler_panel: PanelContainer
var _settler_list: VBoxContainer
var _menu_panel: PanelContainer
var _help_panel: PanelContainer
var _info_panel: PanelContainer
var _info_box: VBoxContainer
var _place_bar: PanelContainer
var _place_ok: Button
var _place_label: Label
var _toasts: VBoxContainer
var _overlay: Control
var _info_timer: float = 0.0
var _info_obj = null
var _demolish_armed: bool = false
var _follow: bool = false
var _info_sig: String = ""
var _updaters: Array = []


func setup(p_world: World, p_camera: GameCamera) -> void:
	world = p_world
	camera = p_camera
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make()
	add_child(root)
	_build_topbar()
	_build_bottom()
	_build_build_panel()
	_build_settler_panel()
	_build_menu_panel()
	_build_help_panel()
	_build_info_panel()
	_build_place_bar()
	_toasts = VBoxContainer.new()
	_toasts.position = Vector2(8, 56)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 3)
	root.add_child(_toasts)
	Game.stock_changed.connect(_refresh_top)
	Game.population_changed.connect(_refresh_top)
	Game.population_changed.connect(_refresh_settler_list)
	Game.notified.connect(toast)
	Game.selection_changed.connect(_on_selection)
	Game.speed_changed.connect(_on_speed)
	Game.game_over.connect(_show_game_over)
	world.placement_changed.connect(_on_placement)
	get_viewport().size_changed.connect(_layout)
	_refresh_top()
	_layout()


# ================================================================== Oberleiste
func _chip(icon_name: String) -> Array:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.add_child(UiTheme.icon_rect(Data.icon(icon_name), 18))
	var l := UiTheme.label("0", 16)
	h.add_child(l)
	return [h, l]


func _build_topbar() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(6, 6)
	root.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	for id in ["holz", "stein"]:
		var c := _chip(Data.resources[id].icon)
		c[0].tooltip_text = Data.resources[id].name
		c[0].mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(c[0])
		_res_labels[id] = c[1]
	var fc := _chip("nahrung")
	_food_label = fc[1]
	fc[0].mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(fc[0])
	var pc := _chip("person")
	_pop_label = pc[1]
	pc[0].tooltip_text = "Bewohner / Wohnplätze"
	pc[0].mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(pc[0])
	var dc := HBoxContainer.new()
	dc.add_theme_constant_override("separation", 3)
	_day_icon = UiTheme.icon_rect(Data.icon("sonne"), 18)
	dc.add_child(_day_icon)
	_day_label = UiTheme.label("Tag 1", 16)
	dc.add_child(_day_label)
	h.add_child(dc)
	_food_label.get_parent().set_meta("is_food", true)

	var sp := PanelContainer.new()
	sp.name = "SpeedPanel"
	root.add_child(sp)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 4)
	sp.add_child(sh)
	for i in 3:
		var icon_name: String = ["pause", "play", "schnell"][i]
		var b := UiTheme.button("", icon_name, 34)
		b.toggle_mode = true
		b.tooltip_text = ["Pause", "Normal", "Schnell (3x)"][i]
		var spd: int = [0, 1, 3][i]
		b.pressed.connect(func(): Game.set_speed(spd))
		sh.add_child(b)
		_speed_btns.append([b, spd])
	_on_speed(Game.speed)


func _refresh_top() -> void:
	var cap := Game.storage_capacity()
	for id in _res_labels:
		_res_labels[id].text = "%d" % Game.amount(id)
		_res_labels[id].add_theme_color_override("font_color", UiTheme.BAD if Game.amount(id) >= cap else UiTheme.TEXT)
		_res_labels[id].get_parent().tooltip_text = "%s: %d / %d (Lagerplatz)" % [Data.resource_name(id), Game.amount(id), cap]
	var food := Game.total_food()
	_food_label.text = "%d" % food
	var parts := []
	for id in Data.food_ids():
		parts.append("%s: %d" % [Data.resource_name(id), Game.amount(id)])
	_food_label.get_parent().tooltip_text = "Nahrung\n" + "\n".join(parts) + "\nLagerplatz je Sorte: %d" % cap
	var pop := Game.population()
	_food_label.add_theme_color_override("font_color", UiTheme.BAD if food < pop * 3 else UiTheme.TEXT)
	_pop_label.text = "%d/%d" % [pop, Game.housing_capacity()]


func _on_speed(s: int) -> void:
	for e in _speed_btns:
		e[0].set_pressed_no_signal(e[1] == s)


# ================================================================== Unterleiste
func _build_bottom() -> void:
	var p := PanelContainer.new()
	p.name = "BottomPanel"
	root.add_child(p)
	_bottom = HBoxContainer.new()
	_bottom.add_theme_constant_override("separation", 8)
	p.add_child(_bottom)
	var bb := UiTheme.button("Bauen", "hammer", 44)
	bb.pressed.connect(func(): _toggle(_build_panel))
	_bottom.add_child(bb)
	var sb := UiTheme.button("Siedler", "person", 44)
	sb.pressed.connect(func():
		_refresh_settler_list()
		_toggle(_settler_panel))
	_bottom.add_child(sb)
	var mb := UiTheme.button("Menü", "menu", 44)
	mb.pressed.connect(func(): _toggle(_menu_panel))
	_bottom.add_child(mb)


func _toggle(panel: Control) -> void:
	var show := not panel.visible
	for pnl in [_build_panel, _settler_panel, _menu_panel, _help_panel]:
		pnl.visible = false
	panel.visible = show
	if show and panel != _help_panel:
		_info_panel.visible = false
		Game.select(null)


func _popup_panel(title: String) -> Array:
	var p := PanelContainer.new()
	p.visible = false
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var head := HBoxContainer.new()
	var t := UiTheme.label(title, 20, UiTheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := UiTheme.button("", "abriss", 32)
	x.tooltip_text = "Schließen"
	x.pressed.connect(func(): p.visible = false)
	head.add_child(x)
	v.add_child(head)
	return [p, v]


# ================================================================== Bau-Menue
func _build_build_panel() -> void:
	var r := _popup_panel("Bauen")
	_build_panel = r[0]
	var v: VBoxContainer = r[1]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(355, 230)
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for type in Data.buildings:
		var def: Dictionary = Data.buildings[type]
		if not def.get("buildable", false):
			continue
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(335, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 8
		h.offset_right = -8
		b.add_child(h)
		var tex: Texture2D = Data.object_tex("field3" if def.get("ground", false) else def.sprite)
		h.add_child(UiTheme.icon_rect(tex, 48))
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 0)
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(tv)
		tv.add_child(UiTheme.label(def.name, 16, UiTheme.TEXT, true))
		var d := UiTheme.label(def.desc, 12)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 190
		tv.add_child(d)
		var cost := HBoxContainer.new()
		cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for res in def.cost:
			cost.add_child(UiTheme.icon_rect(Data.icon(Data.resources[res].icon), 16))
			cost.add_child(UiTheme.label(str(int(def.cost[res])), 14))
		h.add_child(cost)
		b.pressed.connect(func():
			_build_panel.visible = false
			Game.select(null)
			world.start_placement(type, camera.position))
		list.add_child(b)


func _build_place_bar() -> void:
	_place_bar = PanelContainer.new()
	_place_bar.visible = false
	root.add_child(_place_bar)
	var h := HBoxContainer.new()
	_place_bar.add_child(h)
	_place_label = UiTheme.label("Tippe auf die Karte, um den Bauplatz zu wählen.", 14)
	_place_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place_label.custom_minimum_size.x = 220
	_place_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_place_label)
	_place_ok = UiTheme.button("Hier bauen", "hammer", 44)
	_place_ok.pressed.connect(func(): world.confirm_placement())
	h.add_child(_place_ok)
	var c := UiTheme.button("Abbrechen", "abriss", 44)
	c.pressed.connect(func(): world.cancel_placement())
	h.add_child(c)


func _on_placement(active: bool, type: String, valid: bool) -> void:
	_place_bar.visible = active
	_bottom.get_parent().visible = not active
	if active:
		_place_ok.disabled = not valid
		_place_label.text = "%s: Tippe auf die Karte, um den Bauplatz zu wählen.%s" % [
			Data.buildings[type].name, " Der Platz passt." if valid else "\nHier ist kein Platz frei."]
	_layout()


# ================================================================== Siedlerliste
func _build_settler_panel() -> void:
	var r := _popup_panel("Siedler")
	_settler_panel = r[0]
	var v: VBoxContainer = r[1]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(350, 280)
	v.add_child(scroll)
	_settler_list = VBoxContainer.new()
	_settler_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_settler_list)


func _refresh_settler_list() -> void:
	if _settler_list == null or not _settler_panel.visible:
		return
	for c in _settler_list.get_children():
		c.queue_free()
	var list := world.settlers.duplicate()
	list.sort_custom(func(a, b): return a.age > b.age)
	for s in list:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(330, 44)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 10
		h.offset_right = -10
		b.add_child(h)
		var name := UiTheme.label("%s (%d)" % [s.display_name, int(s.age)], 15, UiTheme.TEXT, true)
		name.custom_minimum_size.x = 120
		h.add_child(name)
		var job := UiTheme.label(s.job_name() if s.is_adult() else "Kind", 14)
		job.custom_minimum_size.x = 90
		h.add_child(job)
		var hb := UiTheme.bar(Color("#e0a040"), 8)
		hb.value = s.hunger
		hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(hb)
		var sref = s
		b.pressed.connect(func():
			_settler_panel.visible = false
			Game.select(sref)
			camera.focus(sref.position))
		_settler_list.add_child(b)


# ================================================================== Menue / Hilfe
func _build_menu_panel() -> void:
	var r := _popup_panel("Menü")
	_menu_panel = r[0]
	var v: VBoxContainer = r[1]
	var save := UiTheme.button("Spiel speichern", "haus", 44)
	save.pressed.connect(func():
		Game.save_game()
		toast("Spiel gespeichert.", "haus")
		_menu_panel.visible = false)
	v.add_child(save)
	var help := UiTheme.button("Spielanleitung", "sonne", 44)
	help.pressed.connect(func(): _toggle(_help_panel))
	v.add_child(help)
	var ng := UiTheme.button("Neues Spiel", "abriss", 44)
	var armed := [false]
	ng.pressed.connect(func():
		if not armed[0]:
			armed[0] = true
			ng.text = "Wirklich? Alles geht verloren!"
			return
		new_game_requested.emit())
	_menu_panel.visibility_changed.connect(func():
		armed[0] = false
		ng.text = "Neues Spiel")
	v.add_child(ng)
	var info := UiTheme.label("Das Spiel speichert automatisch.", 12)
	v.add_child(info)


const HELP_TEXT := """[b]Ziel[/b]
Führe deine kleine Siedlung durch die Generationen. Sorge für Nahrung, baue Hütten und lass deine Insel wachsen.

[b]Bedienung[/b]
Ziehen bewegt die Karte, Mausrad oder zwei Finger zoomen. Tippe auf Siedler, Gebäude oder Rohstoffe für Infos.

[b]Siedler[/b]
Jeder Siedler hat eigene Fähigkeiten. Gib ihnen im Infofenster einen Beruf, der zu ihren Stärken passt. Mit Übung werden sie besser. Freie Siedler helfen dort, wo es nötig ist.

[b]Nahrung[/b]
Siedler essen am Lagerfeuer. Ohne Nahrung werden sie schwach und verhungern. Beeren wachsen nach, Fische auch, und Getreidefelder bringen viel Ertrag.

[b]Nachwuchs[/b]
Kinder kommen nur zur Welt, wenn es freie Wohnplätze in Hütten gibt und genug Nahrung im Lager ist. Kinder werden nach 3 Tagen erwachsen. Niemand lebt ewig, also sorge rechtzeitig für Nachwuchs.

[b]Bauen[/b]
Wähle ein Gebäude und einen Bauplatz. Baumeister und freie Siedler bringen das Material und bauen es auf.

[b]Achtung[/b]
Stirbt der letzte Siedler, ist die Insel verloren."""


func _build_help_panel() -> void:
	var r := _popup_panel("Spielanleitung")
	_help_panel = r[0]
	var v: VBoxContainer = r[1]
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = HELP_TEXT
	rt.custom_minimum_size = Vector2(360, 300)
	rt.scroll_active = true
	v.add_child(rt)


# ================================================================== Infofenster
func _build_info_panel() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.visible = false
	root.add_child(_info_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(290, 0)
	_info_panel.add_child(scroll)
	_info_box = VBoxContainer.new()
	_info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_info_box)


func _on_selection(obj) -> void:
	_info_obj = obj
	_demolish_armed = false
	_follow = false
	if obj == null:
		_info_panel.visible = false
		return
	for pnl in [_build_panel, _settler_panel, _menu_panel, _help_panel]:
		pnl.visible = false
	_info_panel.visible = true
	_rebuild_info()
	_layout()


func _clear_info() -> void:
	for c in _info_box.get_children():
		_info_box.remove_child(c)
		c.queue_free()


func _info_head(title: String) -> void:
	var head := HBoxContainer.new()
	var t := UiTheme.label(title, 19, UiTheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := UiTheme.button("", "abriss", 30)
	x.pressed.connect(func(): Game.select(null))
	head.add_child(x)
	_info_box.add_child(head)


func _bar_row(text: String, value: float, color: Color) -> ProgressBar:
	var h := HBoxContainer.new()
	var l := UiTheme.label(text, 14)
	l.custom_minimum_size.x = 96
	h.add_child(l)
	var b := UiTheme.bar(color, 10)
	b.value = value
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	_info_box.add_child(h)
	return b


func _info_signature() -> String:
	var o = _info_obj
	if o == null or not is_instance_valid(o):
		return ""
	if o is Settler:
		return "s%d|%s|%s|%d|%s|%s" % [o.id, o.job, o.is_adult(), o.home_id, str(o.skills), _follow]
	if o is Building:
		return "b%d|%s|%s|%s|%d|%d" % [o.id, o.complete, o.farm_state, str(o.delivered), int(o.build_fraction() * 50), int((Game.time_days - o.farm_time) * 20)]
	if o is ResNode:
		return "n%s|%d|%d" % [o.cell, o.amount, int((o.regrow_at - Game.time_days) * 24)]
	return ""


func _rebuild_info() -> void:
	_info_sig = _info_signature()
	_updaters.clear()
	_clear_info()
	var o = _info_obj
	if o == null or not is_instance_valid(o):
		_info_panel.visible = false
		return
	if o is Settler:
		_info_settler(o)
	elif o is Building:
		_info_building(o)
	elif o is ResNode:
		_info_node(o)


func _info_settler(s: Settler) -> void:
	_info_head(s.display_name)
	var sex := "Frau" if s.sex == "f" else "Mann"
	if not s.is_adult():
		sex = "Mädchen" if s.sex == "f" else "Junge"
	_info_box.add_child(UiTheme.label("%s, %d Jahre" % [sex, int(s.age)], 14))
	var act := UiTheme.label(s.activity, 14, Color("#6a4a30"))
	act.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(act)
	var hb := _bar_row("Sättigung", s.hunger, Color("#e0a040"))
	var gb := _bar_row("Gesundheit", s.health, UiTheme.GOOD)
	_updaters.append(func():
		act.text = s.activity
		hb.value = s.hunger
		gb.value = s.health)
	var home = world.building_by_id(s.home_id)
	_info_box.add_child(UiTheme.label("Zuhause: %s" % ("Hütte" if home else "keins (schläft draußen)"), 13))
	_info_box.add_child(UiTheme.label("Fähigkeiten", 15, UiTheme.TEXT, true))
	for sk in Data.skills:
		var lvl := int(s.skill_level(sk))
		_bar_row("%s %d" % [Data.skills[sk].name, lvl], lvl * 10.0, Color("#5a8ad8"))
	if not s.is_adult():
		_info_box.add_child(UiTheme.label("Kinder arbeiten noch nicht.", 13))
	else:
		_info_box.add_child(UiTheme.label("Beruf", 15, UiTheme.TEXT, true))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		for j in Data.jobs:
			var b := UiTheme.button(Data.jobs[j].name, "", 34)
			b.toggle_mode = true
			b.button_pressed = s.job == j
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 14)
			var jd: Dictionary = Data.jobs[j]
			var tip: String = jd.desc
			if jd.skill != "":
				tip += "\nFähigkeit: %s (Stufe %d)" % [Data.skills[jd.skill].name, int(s.skill_level(jd.skill))]
			b.tooltip_text = tip
			var jid: String = j
			b.pressed.connect(func():
				s.set_job(jid)
				_rebuild_info())
			grid.add_child(b)
		_info_box.add_child(grid)
	var f := UiTheme.button("Folgen", "person", 34)
	f.toggle_mode = true
	f.button_pressed = _follow
	f.toggled.connect(func(on):
		_follow = on
		_info_sig = _info_signature())
	_info_box.add_child(f)


func _info_building(b: Building) -> void:
	_info_head(b.def.name if b.complete else "Baustelle: " + b.def.name)
	var d := UiTheme.label(b.def.desc, 13)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(d)
	if not b.complete:
		for res in b.def.cost:
			var h := HBoxContainer.new()
			h.add_child(UiTheme.icon_rect(Data.icon(Data.resources[res].icon), 16))
			h.add_child(UiTheme.label("%s: %d / %d" % [Data.resource_name(res), int(b.delivered.get(res, 0)), int(b.def.cost[res])], 14))
			_info_box.add_child(h)
		_bar_row("Fortschritt", b.build_fraction() * 100.0, UiTheme.ACCENT)
		var builders := world.settlers.filter(func(s): return s.is_adult() and (s.job == "baumeister" or s.job == "frei"))
		if builders.is_empty():
			var w := UiTheme.label("Niemand baut! Mache einen Siedler zum Baumeister.", 13, UiTheme.BAD)
			w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_info_box.add_child(w)
	else:
		if b.housing() > 0:
			var names := b.residents().map(func(s): return s.display_name)
			_info_box.add_child(UiTheme.label("Bewohner: %d / %d" % [names.size(), b.housing()], 14))
			if not names.is_empty():
				var l := UiTheme.label(", ".join(names), 13)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_info_box.add_child(l)
		if b.def.get("storage", 0) > 0:
			_info_box.add_child(UiTheme.label("Lagerplatz: +%d je Sorte" % int(b.def.storage), 14))
		if b.is_ground() and b.def.has("farm"):
			var st := {"fallow": "Wartet auf Aussaat", "growing": "Getreide wächst", "ripe": "Erntereif!"}
			_info_box.add_child(UiTheme.label(st.get(b.farm_state, ""), 14))
			if b.farm_state == "growing":
				var frac: float = (Game.time_days - b.farm_time) / float(b.farm_def().grow_days)
				_bar_row("Wachstum", frac * 100.0, UiTheme.GOOD)
			if not world.settlers.any(func(s): return s.job == "bauer"):
				var w := UiTheme.label("Ohne Bauern wird das Feld nur selten bestellt.", 13, UiTheme.BAD)
				w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_info_box.add_child(w)
	if b.type != "lagerfeuer":
		var dm := UiTheme.button("Abreißen" if not _demolish_armed else "Wirklich abreißen?", "abriss", 36)
		dm.pressed.connect(func():
			if not _demolish_armed:
				_demolish_armed = true
				_rebuild_info()
				return
			world.demolish(b))
		_info_box.add_child(dm)


func _info_node(n: ResNode) -> void:
	_info_head(n.def.name)
	var res: String = n.def.yield
	var h := HBoxContainer.new()
	h.add_child(UiTheme.icon_rect(Data.icon(Data.resources[res].icon), 16))
	h.add_child(UiTheme.label("%s: %d / %d" % [Data.resource_name(res), n.amount, int(n.def.capacity)], 14))
	_info_box.add_child(h)
	if n.amount <= 0 and n.regrow_at >= 0.0:
		var left: float = (n.regrow_at - Game.time_days) * 24.0
		_info_box.add_child(UiTheme.label("Wächst nach: noch %d Std." % max(1, int(ceil(left))), 14))
	elif n.def.get("on_empty", "") == "remove":
		_info_box.add_child(UiTheme.label("Wächst nicht nach.", 13))
	var who := {"baum": "Holzfäller", "fels": "Steinmetz", "busch": "Sammler", "fischgrund": "Fischer"}
	_info_box.add_child(UiTheme.label("Wird bearbeitet von: %s" % who.get(n.type, "?"), 13))


# ================================================================== Meldungen
func toast(text: String, icon_name: String = "") -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	if icon_name != "":
		h.add_child(UiTheme.icon_rect(Data.icon(icon_name), 16))
	var l := UiTheme.label(text, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = min(300.0, root.size.x - 60.0)
	h.add_child(l)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 4:
		var c := _toasts.get_child(0)
		_toasts.remove_child(c)
		c.queue_free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(5.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


# ================================================================== Overlays
func show_title(has_save: bool) -> void:
	_overlay_clear()
	_overlay = ColorRect.new()
	_overlay.color = Color(0.05, 0.08, 0.15, 0.45)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_overlay)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var t := UiTheme.label("Insel-Siedler", 40, Color("#7a4a28"), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := UiTheme.label("Zwei Siedler. Eine Insel. Viele Generationen.", 15)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	if has_save:
		var cont := UiTheme.button("Weiterspielen", "play", 50)
		cont.pressed.connect(func():
			_overlay_clear()
			continue_requested.emit())
		v.add_child(cont)
	var ng := UiTheme.button("Neues Spiel" if has_save else "Spiel starten", "sonne", 50)
	var armed := [not has_save]
	ng.pressed.connect(func():
		if not armed[0]:
			armed[0] = true
			ng.text = "Spielstand überschreiben?"
			return
		_overlay_clear()
		new_game_requested.emit())
	v.add_child(ng)
	var hb := UiTheme.button("Spielanleitung", "menu", 40)
	hb.pressed.connect(func(): _toggle(_help_panel))
	v.add_child(hb)
	root.move_child(_help_panel, -1)


func _show_game_over() -> void:
	_overlay_clear()
	_overlay = ColorRect.new()
	_overlay.color = Color(0.05, 0.03, 0.06, 0.55)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_overlay)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var t := UiTheme.label("Die Insel ist verloren", 30, UiTheme.BAD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UiTheme.label("Deine Siedlung hielt %d Tage durch.\nGeburten: %d   Höchste Bevölkerung: %d" % [
		Game.day(), int(Game.stats.births), int(Game.stats.max_pop)], 15)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var ng := UiTheme.button("Neue Insel besiedeln", "sonne", 50)
	ng.pressed.connect(func():
		_overlay_clear()
		new_game_requested.emit())
	v.add_child(ng)


func _overlay_clear() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_help_panel.visible = false


func has_overlay() -> bool:
	return _overlay != null


# ================================================================== Layout
func _layout() -> void:
	if root == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var portrait := vs.y > vs.x
	var bp: Control = _bottom.get_parent()
	bp.reset_size()
	bp.position = Vector2((vs.x - bp.size.x) / 2.0, vs.y - bp.size.y - 6)
	_place_bar.reset_size()
	_place_bar.size.x = min(vs.x - 12, 620)
	_place_bar.position = Vector2((vs.x - _place_bar.size.x) / 2.0, vs.y - _place_bar.size.y - 6)
	var sp: Control = root.get_node("SpeedPanel")
	sp.reset_size()
	var top_h := 50.0
	if portrait or vs.x < 760:
		sp.position = Vector2(vs.x - sp.size.x - 6, 54)
		top_h = 100.0
	else:
		sp.position = Vector2(vs.x - sp.size.x - 6, 6)
	_toasts.position = Vector2(8, top_h + 6)
	for pnl in [_build_panel, _settler_panel, _menu_panel, _help_panel]:
		pnl.reset_size()
		pnl.size.x = min(pnl.size.x, vs.x - 12)
		pnl.position = Vector2((vs.x - pnl.size.x) / 2.0, max(top_h, vs.y - pnl.size.y - bp.size.y - 18))
	var bottom_space := bp.size.y + 18
	if portrait:
		_info_panel.size = Vector2(vs.x - 12, min(vs.y * 0.45, 420))
		_info_panel.position = Vector2(6, vs.y - _info_panel.size.y - bottom_space)
	else:
		_info_panel.size = Vector2(310, vs.y - top_h - bottom_space - 6)
		_info_panel.position = Vector2(vs.x - 316, top_h + 6)


func _process(delta: float) -> void:
	if root == null:
		return
	_day_label.text = "Tag %d  %s" % [Game.day(), Game.clock_text()]
	_day_icon.texture = Data.icon("mond" if Game.is_night() else "sonne")
	_info_timer -= delta / max(Engine.time_scale, 0.001) if Engine.time_scale > 0 else delta
	if _info_panel.visible and _info_timer <= 0.0:
		_info_timer = 0.5
		if _info_obj == null or not is_instance_valid(_info_obj):
			Game.select(null)
		elif not _demolish_armed:
			if _info_signature() != _info_sig:
				_rebuild_info()
			else:
				for u in _updaters:
					u.call()
	if _follow and _info_obj and is_instance_valid(_info_obj) and _info_obj is Settler:
		camera.focus(_info_obj.position)
