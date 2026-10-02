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
var _build_list: VBoxContainer
var _build_title: Label
var _build_cat: String = "wohnen"
var _build_tabs: Array = []
var _research_panel: PanelContainer
var _research_list: VBoxContainer
var _research_scroll: ScrollContainer
var _research_head: VBoxContainer
var _research_bar: ProgressBar
var _research_label: Label
var _research_btn: Button
var _stock_panel: PanelContainer
var _stock_grid: GridContainer
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
var _research_tick: float = 0.0
var _sea_panel: SeaPanel
var _sea_btn: Button
var _island_label: Label
var _build_btn: Button
var goal_card: GoalCard


func setup(p_world: World, p_camera: GameCamera) -> void:
	world = p_world
	camera = p_camera
	camera.wheel_blocked = func(): return _panels().any(func(pn): return pn != null and pn.visible)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make()
	add_child(root)
	_build_topbar()
	_build_bottom()
	goal_card = GoalCard.new()
	root.add_child(goal_card)
	goal_card.setup(self)
	_build_build_panel()
	_build_research_panel()
	_build_stock_panel()
	_build_settler_panel()
	_build_menu_panel()
	_build_help_panel()
	_build_info_panel()
	_sea_panel = SeaPanel.new()
	root.add_child(_sea_panel)
	_sea_panel.setup(self)
	_build_place_bar()
	_toasts = VBoxContainer.new()
	_toasts.position = Vector2(8, 56)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 3)
	root.add_child(_toasts)
	get_viewport().size_changed.connect(_refresh_top)
	Game.stock_changed.connect(_refresh_top)
	Game.stock_changed.connect(_refresh_stock)
	Game.research_changed.connect(_on_research_changed)
	Game.population_changed.connect(_refresh_top)
	Game.population_changed.connect(_refresh_settler_list)
	Game.notified.connect(toast)
	Game.selection_changed.connect(_on_selection)
	Game.speed_changed.connect(_on_speed)
	Game.game_over.connect(_show_game_over)
	world.placement_changed.connect(_on_placement)
	Sea.islands_changed.connect(_update_sea_button)
	get_viewport().size_changed.connect(_layout)
	_update_sea_button()
	_refresh_top()
	goal_card.attach_pointer(root)
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
	p.tooltip_text = "Tippen: alle Vorräte anzeigen"
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_refresh_stock(true)
			_toggle(_stock_panel))
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
	_island_label = UiTheme.label("", 14, Color("#7a4a28"), true)
	_island_label.visible = false
	h.add_child(_island_label)
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
		_res_labels[id].get_parent().tooltip_text = "%s: %d / %d (Lagerplatz aller Lager zusammen)" % [Data.resource_name(id), Game.amount(id), cap]
	var food := Game.total_food()
	_food_label.text = "%d" % food
	var parts := []
	for id in Data.food_ids():
		parts.append("%s: %d" % [Data.resource_name(id), Game.amount(id)])
	_food_label.get_parent().tooltip_text = "Nahrung\n" + "\n".join(parts) + "\nLagerplatz je Sorte: %d" % cap
	var pop := Game.population()
	_food_label.add_theme_color_override("font_color", UiTheme.BAD if food < pop * 3 else UiTheme.TEXT)
	var here: int = world.settlers.size() if world and is_instance_valid(world) else 0
	_pop_label.text = "%d/%d" % [here, Game.housing_capacity()]
	var tip := "Bewohner / Wohnplätze auf dieser Insel"
	if Sea.worlds.size() > 1 or Sea.people_at_sea() > 0:
		tip += "\nAuf allen Inseln und See: %d" % (pop + Sea.people_at_sea())
	_pop_label.get_parent().tooltip_text = tip
	if _island_label:
		var vs := get_viewport().get_visible_rect().size
		# Auf schmalen Bildschirmen passt der Inselname nicht mehr in die Leiste
		_island_label.visible = Sea.worlds.size() > 1 and vs.x >= 520
		_island_label.text = Sea.island_name(world) if world and is_instance_valid(world) else ""


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
	_build_btn = bb
	_research_btn = UiTheme.button("Forschung", "wissen", 44)
	_research_btn.pressed.connect(func():
		_fill_research_list()
		_toggle(_research_panel))
	_bottom.add_child(_research_btn)
	var sb := UiTheme.button("Siedler", "person", 44)
	sb.pressed.connect(func():
		_toggle(_settler_panel)
		_refresh_settler_list())
	_bottom.add_child(sb)
	_sea_btn = UiTheme.button("Inseln", "boot", 44)
	_sea_btn.pressed.connect(_open_sea)
	_bottom.add_child(_sea_btn)
	var mb := UiTheme.button("Menü", "menu", 44)
	mb.pressed.connect(func(): _toggle(_menu_panel))
	_bottom.add_child(mb)


func _open_sea() -> void:
	_sea_panel.open()
	if not _sea_panel.visible:
		_toggle(_sea_panel)
	_layout()


func _update_sea_button() -> void:
	if _sea_btn == null:
		return
	var show := Game.is_researched("schiffsbau") or Sea.islands.size() > 1
	if _sea_btn.visible != show:
		_sea_btn.visible = show
		_layout()
	_refresh_top()


## Nach dem Wechsel auf eine andere Insel.
func on_island_switched() -> void:
	for pnl in _panels():
		if pnl != _sea_panel:
			pnl.visible = false
	_info_panel.visible = false
	_refresh_top()
	_refresh_settler_list()
	_update_sea_button()
	if _sea_panel.visible:
		_sea_panel.refresh()


func _toggle(panel: Control) -> void:
	var show := not panel.visible
	for pnl in _panels():
		pnl.visible = false
	panel.visible = show
	if show and panel != _help_panel:
		_info_panel.visible = false
		Game.select(null)


func _panels() -> Array:
	return [_build_panel, _research_panel, _stock_panel, _settler_panel, _menu_panel, _help_panel, _sea_panel]


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
const BUILD_CATS := [["wohnen", "Wohnen", "haus"], ["nahrung", "Nahrung", "nahrung"],
	["handwerk", "Handwerk", "hammer"], ["lager", "Lager", "kiste"], ["wissen", "Wissen", "wissen"],
	["see", "Seefahrt und Schutz", "boot"]]


func _build_build_panel() -> void:
	var r := _popup_panel("Bauen")
	_build_panel = r[0]
	var v: VBoxContainer = r[1]
	_build_title = v.get_child(0).get_child(0)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	v.add_child(tabs)
	for c in BUILD_CATS:
		var b := UiTheme.button("", c[2], 40)
		b.toggle_mode = true
		b.tooltip_text = c[1]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cat: String = c[0]
		b.pressed.connect(func():
			_build_cat = cat
			_fill_build_list())
		tabs.add_child(b)
		_build_tabs.append([b, cat])
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(355, 250)
	v.add_child(scroll)
	_build_list = VBoxContainer.new()
	_build_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_build_list)
	_fill_build_list()


func _fill_build_list() -> void:
	for c in _build_list.get_children():
		_build_list.remove_child(c)
		c.queue_free()
	for t in _build_tabs:
		t[0].set_pressed_no_signal(t[1] == _build_cat)
	for c in BUILD_CATS:
		if c[0] == _build_cat:
			_build_title.text = "Bauen: " + c[1]
	var locked_rows := []
	for type in Data.buildings:
		var def: Dictionary = Data.buildings[type]
		if not def.get("buildable", false) or def.get("category", "") != _build_cat:
			continue
		var unlocked := Game.is_unlocked(type)
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
		var ic := UiTheme.icon_rect(Data.building_tex(type), 48)
		h.add_child(ic)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 0)
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(tv)
		tv.add_child(UiTheme.label(def.name, 16, UiTheme.TEXT, true))
		var desc: String = def.desc
		if not unlocked:
			desc = "Benötigt Forschung: %s" % Data.techs.get(def.requires, {}).get("name", "?")
		b.custom_minimum_size.y = _row_height(desc, 30)
		var d := UiTheme.label(desc, 12, UiTheme.TEXT if unlocked else Color("#8a5a3a"))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 170
		tv.add_child(d)
		var cost := GridContainer.new()
		cost.columns = 2
		cost.add_theme_constant_override("h_separation", 2)
		cost.add_theme_constant_override("v_separation", 0)
		cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for res in def.cost:
			cost.add_child(UiTheme.icon_rect(Data.res_icon(res), 16))
			var enough := Game.amount(res) >= int(def.cost[res])
			cost.add_child(UiTheme.label(str(int(def.cost[res])), 14, UiTheme.TEXT if enough else UiTheme.BAD))
		h.add_child(cost)
		if not unlocked:
			b.disabled = true
			ic.modulate = Color(0.2, 0.15, 0.15, 0.6)
			locked_rows.append(b)
			continue
		var bt: String = type
		b.set_meta("btype", type)
		b.pressed.connect(func():
			_build_panel.visible = false
			Game.select(null)
			world.start_placement(bt, camera.position))
		_build_list.add_child(b)
	for b in locked_rows:
		_build_list.add_child(b)


# ================================================================== Forschung
func _build_research_panel() -> void:
	var r := _popup_panel("Forschung")
	_research_panel = r[0]
	var v: VBoxContainer = r[1]
	_research_head = VBoxContainer.new()
	v.add_child(_research_head)
	_research_label = UiTheme.label("", 14)
	_research_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_research_label.custom_minimum_size.x = 330
	_research_head.add_child(_research_label)
	_research_bar = UiTheme.bar(Color("#5a8ad8"), 10)
	_research_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_research_head.add_child(_research_bar)
	_research_scroll = ScrollContainer.new()
	_research_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_research_scroll.custom_minimum_size = Vector2(355, 270)
	v.add_child(_research_scroll)
	_research_list = VBoxContainer.new()
	_research_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_research_scroll.add_child(_research_list)


func _forscher_count() -> int:
	return world.settlers.filter(func(s): return s.is_adult() and s.job == "forscher").size()


func _update_research_head() -> void:
	if _research_label == null:
		return
	var cur: String = Game.research.current
	var n := _forscher_count()
	var who := "Keine Forscher! Gib einem Siedler den Beruf Forscher." if n == 0 else "Forscher: %d" % n
	if cur == "":
		_research_label.text = "Wähle eine Forschung aus. %s" % who
		_research_bar.value = 0
	else:
		var pts := Game.tech_points(cur)
		_research_label.text = "Forschung: %s  (%d / %d)\n%s" % [Data.techs[cur].name, int(Game.tech_progress(cur)), int(pts), who]
		_research_bar.value = Game.tech_progress(cur) / pts * 100.0
	_research_label.add_theme_color_override("font_color", UiTheme.BAD if n == 0 else UiTheme.TEXT)
	var label := "Forschung"
	if cur != "":
		label = "%d%%" % int(Game.tech_progress(cur) / Game.tech_points(cur) * 100.0)
	_research_btn.text = label


const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII"]


func _fill_research_list() -> void:
	var keep := _research_scroll.scroll_vertical
	for c in _research_list.get_children():
		_research_list.remove_child(c)
		c.queue_free()
	_update_research_head()
	var tier := 0
	for t in Data.sorted_tech_ids():
		var def: Dictionary = Data.techs[t]
		if int(def.tier) != tier:
			tier = int(def.tier)
			var name: String = Data.tiers[tier - 1] if tier - 1 < Data.tiers.size() else ""
			var hl := UiTheme.label("Stufe %s: %s" % [ROMAN[min(tier - 1, ROMAN.size() - 1)], name], 16, Color("#7a4a28"), true)
			_research_list.add_child(hl)
		_research_list.add_child(_tech_row(t))
	await get_tree().process_frame
	_research_scroll.scroll_vertical = keep


## Hoehe einer Listenzeile, damit der umbrechende Text hineinpasst.
func _row_height(text: String, chars_per_line: int) -> float:
	var lines := ceili(float(text.length()) / chars_per_line)
	return max(62.0, 34.0 + 15.0 * lines)


func _tech_row(t: String) -> Button:
	var def: Dictionary = Data.techs[t]
	var st := Game.tech_state(t)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(335, 62)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.toggle_mode = true
	b.button_pressed = st == "current"
	b.set_meta("tid", t)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -8
	b.add_child(h)
	var ic := UiTheme.icon_rect(Data.tech_tex(t), 40)
	if st in ["locked", "soon"]:
		ic.modulate = Color(0.25, 0.2, 0.2, 0.6)
	h.add_child(ic)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(tv)
	var col := UiTheme.TEXT_LIGHT if st == "current" else UiTheme.TEXT
	tv.add_child(UiTheme.label(def.name, 15, col, true))
	b.custom_minimum_size.y = _row_height(def.desc, 33)
	var d := UiTheme.label(def.desc, 12, col)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 180
	tv.add_child(d)
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size.x = 70
	h.add_child(right)
	match st:
		"done":
			right.add_child(UiTheme.label("Erforscht", 13, UiTheme.GOOD, true))
			b.modulate = Color(0.85, 1.0, 0.85)
		"soon":
			right.add_child(UiTheme.label("Bald", 13, Color("#8a5a3a"), true))
		"locked":
			var need := []
			for rq in def.get("requires", []):
				if not Game.is_researched(rq):
					need.append(Data.techs[rq].name)
			var l := UiTheme.label("Gesperrt", 13, Color("#8a5a3a"), true)
			right.add_child(l)
			d.text = "Benötigt: " + ", ".join(need)
		_:
			var cost := GridContainer.new()
			cost.columns = 2
			cost.add_theme_constant_override("h_separation", 2)
			cost.add_theme_constant_override("v_separation", 0)
			cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if t in Game.research.paid:
				right.add_child(UiTheme.label("bezahlt", 12, col))
			else:
				for res in def.get("cost", {}):
					cost.add_child(UiTheme.icon_rect(Data.res_icon(res), 14))
					var enough := Game.amount(res) >= int(def.cost[res])
					cost.add_child(UiTheme.label(str(int(def.cost[res])), 13, col if enough else UiTheme.BAD))
				right.add_child(cost)
			var pct := Game.tech_progress(t) / Game.tech_points(t) * 100.0
			right.add_child(UiTheme.label("%d Pkt." % int(Game.tech_points(t)) if pct <= 0 else "%d%%" % int(pct), 12, col))
	b.pressed.connect(_on_tech_pressed.bind(t, b, d))
	return b


func _on_tech_pressed(tid: String, b: Button, d: Label) -> void:
	var def: Dictionary = Data.techs[tid]
	b.set_pressed_no_signal(Game.tech_state(tid) == "current")
	match Game.tech_state(tid):
		"available":
			var err := Game.start_research(tid)
			if err != "":
				toast(err, "wissen")
			else:
				toast("Forschung gestartet: %s" % def.name, "wissen")
				if _forscher_count() == 0:
					toast("Tipp: Gib einem Siedler den Beruf Forscher.", "person")
		"locked":
			toast(d.text, "wissen")
		"soon":
			toast("Dieses Wissen kommt mit einem späteren Update.", "wissen")
		"done":
			toast("%s ist schon erforscht." % def.name, "wissen")


func _on_research_changed() -> void:
	_update_sea_button()
	if _research_panel.visible:
		_fill_research_list()
	else:
		_update_research_head()
	_fill_build_list()


# ================================================================== Vorraete
func _build_stock_panel() -> void:
	var r := _popup_panel("Vorräte")
	_stock_panel = r[0]
	var v: VBoxContainer = r[1]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(340, 250)
	v.add_child(scroll)
	_stock_grid = GridContainer.new()
	_stock_grid.columns = 2
	_stock_grid.add_theme_constant_override("h_separation", 16)
	_stock_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_stock_grid)


func _refresh_stock(force: bool = false) -> void:
	if _stock_grid == null or (not force and not _stock_panel.visible):
		return
	for c in _stock_grid.get_children():
		_stock_grid.remove_child(c)
		c.queue_free()
	var cap := Game.storage_capacity()
	for id in Data.sorted_resource_ids():
		var h := HBoxContainer.new()
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(UiTheme.icon_rect(Data.res_icon(id), 18))
		var n := UiTheme.label(Data.resource_name(id), 14)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var a := Game.amount(id)
		h.add_child(UiTheme.label("%d" % a, 14, UiTheme.BAD if a >= cap else UiTheme.TEXT, true))
		h.modulate.a = 1.0 if a > 0 else 0.55
		_stock_grid.add_child(h)
	var info := UiTheme.label("Platz je Ware: %s" % Game.storage_breakdown(), 13)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stock_grid.add_child(info)
	var food := UiTheme.label("Nahrungssorten: %d" % Game.food_variety(), 13)
	food.tooltip_text = "Ab %d Sorten im Lager kommen öfter Kinder zur Welt." % int(Data.bal("variety_min", 3))
	food.mouse_filter = Control.MOUSE_FILTER_PASS
	_stock_grid.add_child(food)


func _build_place_bar() -> void:
	_place_bar = PanelContainer.new()
	_place_bar.visible = false
	root.add_child(_place_bar)
	var h := HBoxContainer.new()
	_place_bar.add_child(h)
	_place_label = UiTheme.label("Klicke auf einen freien Platz.", 14)
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
		var moving: bool = world.moving_building() != null
		_place_ok.text = "Hier hinstellen" if moving else "Hier bauen"
		if moving:
			_place_label.text = "%s verschieben: Klicke auf den neuen Platz. Am Handy tippen, dann Hier hinstellen.%s" % [
				Data.buildings[type].name, " Der Platz passt." if valid else ("\nMuss am Ufer stehen und Platz haben." if Data.buildings[type].get("coast", false) else "\nHier ist kein Platz frei.")]
			_layout()
			return
		_place_label.text = "%s: Klicke auf einen freien Platz. Am Handy tippen, dann Hier bauen.%s" % [
			Data.buildings[type].name, " Der Platz passt." if valid else ("\nMuss am Ufer stehen und Platz haben." if Data.buildings[type].get("coast", false) else "\nHier ist kein Platz frei.")]
	_layout()


# ================================================================== Siedlerliste
const DIM := Color("#6e5a50")
## Sortierbare Spalten: Schluessel, Text, Breite (0 = dehnbar; breit / schmal)
const SETTLER_COLS := [["name", "Name", 0, 0], ["age", "Alter", 62, 56], ["act", "Tätigkeit", 0, -1],
	["job", "Beruf", 150, 104], ["hunger", "Satt", 130, 64]]
var _settler_scroll: ScrollContainer
var _settler_updaters: Array = []
var _settler_tick: float = 0.0
var _settler_head: Dictionary = {}  # Spalte -> Knopf
var _settler_sort: String = "age"
var _settler_desc: bool = true
var _settler_f_job: OptionButton
var _settler_f_group: OptionButton
var _settler_f_hungry: CheckBox
var _settler_f_island: OptionButton
var _settler_count: Label
var _settler_narrow: bool = false


func _build_settler_panel() -> void:
	var r := _popup_panel("Siedler")
	_settler_panel = r[0]
	var v: VBoxContainer = r[1]
	# Filter
	var fr := HFlowContainer.new()
	fr.add_theme_constant_override("h_separation", 8)
	fr.add_theme_constant_override("v_separation", 4)
	_settler_f_job = _settler_filter_button("Welche Berufe anzeigen")
	fr.add_child(_settler_f_job)
	_settler_f_group = _settler_filter_button("Erwachsene oder Kinder anzeigen")
	for t in ["Alle Alter", "Erwachsene", "Kinder"]:
		_settler_f_group.add_item(t)
	fr.add_child(_settler_f_group)
	_settler_f_island = _settler_filter_button("Welche Insel anzeigen")
	fr.add_child(_settler_f_island)
	_settler_f_hungry = CheckBox.new()
	_settler_f_hungry.text = "Nur Hungrige"
	_settler_f_hungry.focus_mode = Control.FOCUS_NONE
	_settler_f_hungry.custom_minimum_size.y = 40
	_settler_f_hungry.add_theme_font_size_override("font_size", 15)
	_settler_f_hungry.toggled.connect(func(_on): _refresh_settler_list())
	fr.add_child(_settler_f_hungry)
	v.add_child(fr)
	_settler_count = UiTheme.label("", 13, DIM)
	_settler_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settler_count.custom_minimum_size.x = 280
	v.add_child(_settler_count)
	# Spaltenkoepfe: antippen sortiert, nochmal antippen dreht die Reihenfolge um
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	for col in SETTLER_COLS:
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size.y = 32
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", DIM)
		b.add_theme_color_override("font_hover_color", UiTheme.TEXT)
		var key: String = col[0]
		if key == "act":
			b.disabled = true
			b.add_theme_color_override("font_disabled_color", DIM)
		else:
			b.tooltip_text = "Nach %s sortieren" % col[1]
			b.pressed.connect(func():
				if _settler_sort == key:
					_settler_desc = not _settler_desc
				else:
					_settler_sort = key
					_settler_desc = key in ["age", "hunger"]
				_refresh_settler_list())
		head.add_child(b)
		_settler_head[key] = b
	v.add_child(head)
	_settler_scroll = ScrollContainer.new()
	_settler_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settler_scroll.custom_minimum_size = Vector2(560, 420)
	v.add_child(_settler_scroll)
	_settler_list = VBoxContainer.new()
	_settler_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settler_list.add_theme_constant_override("separation", 3)
	_settler_scroll.add_child(_settler_list)


func _settler_filter_button(tip: String) -> OptionButton:
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(120, 40)
	ob.add_theme_font_size_override("font_size", 15)
	ob.get_popup().add_theme_font_size_override("font_size", 16)
	ob.tooltip_text = tip
	ob.item_selected.connect(func(_i): _refresh_settler_list())
	return ob


## Fast der ganze Bildschirm, damit viele Siedler auf einmal zu sehen sind.
func _size_settler_panel(avail_h: float = -1.0) -> void:
	if _settler_scroll == null:
		return
	var vs := get_viewport().get_visible_rect().size
	if avail_h < 0.0:
		avail_h = vs.y - 160.0
	var w := clampf(vs.x - 36.0, 290.0, 980.0)
	_settler_narrow = w < 620.0
	# Platz fuer Titel, Filter, Zaehler und Spaltenkoepfe abziehen
	var extra := 150.0 + (46.0 if _settler_narrow else 0.0)
	_settler_scroll.custom_minimum_size = Vector2(w, clampf(avail_h - extra, 140.0, 2000.0))
	for col in SETTLER_COLS:
		var b: Button = _settler_head[col[0]]
		var cw: int = col[3] if _settler_narrow else col[2]
		b.visible = cw >= 0
		b.custom_minimum_size.x = max(cw, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if cw == 0 else Control.SIZE_FILL
		if col[0] == "act":
			b.size_flags_stretch_ratio = 1.4


## Flachere Knoepfe fuer lange Listen
var _compact_boxes: Dictionary = {}


func _compact(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		if not _compact_boxes.has(st):
			var sb = _settler_panel.get_theme_stylebox(st, "Button")
			if sb == null:
				continue
			sb = sb.duplicate()
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			_compact_boxes[st] = sb
		b.add_theme_stylebox_override(st, _compact_boxes[st])


func _settler_job_label(s) -> String:
	return Data.jobs[s.job].name if s.is_adult() else "Kind"


## Filterauswahl aktuell halten (Berufe, Inseln), gewaehlte Eintraege bleiben stehen.
func _update_settler_filters() -> void:
	var keep_job = _settler_f_job.get_item_metadata(_settler_f_job.selected) if _settler_f_job.item_count > 0 else ""
	_settler_f_job.clear()
	_settler_f_job.add_item("Alle Berufe")
	_settler_f_job.set_item_metadata(0, "")
	for j in Data.jobs:
		if Data.job_unlocked(j):
			_settler_f_job.add_item(Data.jobs[j].name)
			_settler_f_job.set_item_metadata(_settler_f_job.item_count - 1, j)
			if j == keep_job:
				_settler_f_job.select(_settler_f_job.item_count - 1)
	var keep_isl = _settler_f_island.get_item_metadata(_settler_f_island.selected) if _settler_f_island.item_count > 0 else -1
	_settler_f_island.clear()
	_settler_f_island.add_item("Diese Insel")
	_settler_f_island.set_item_metadata(0, -1)
	_settler_f_island.add_item("Alle Inseln")
	_settler_f_island.set_item_metadata(1, -2)
	if keep_isl == -2:
		_settler_f_island.select(1)
	_settler_f_island.visible = Sea.all_worlds().size() > 1
	if not _settler_f_island.visible:
		_settler_f_island.select(0)


func _refresh_settler_list() -> void:
	if _settler_list == null or not _settler_panel.visible:
		return
	_size_settler_panel()
	_update_settler_filters()
	_settler_updaters.clear()
	for c in _settler_list.get_children():
		_settler_list.remove_child(c)
		c.queue_free()
	var all_isl: bool = _settler_f_island.visible and _settler_f_island.selected == 1
	var pool := []
	if all_isl:
		for w in Sea.all_worlds():
			pool.append_array(w.settlers)
	else:
		pool = world.settlers.duplicate()
	var f_job: String = _settler_f_job.get_item_metadata(_settler_f_job.selected)
	var group := _settler_f_group.selected
	var list := pool.filter(func(s):
		if f_job != "" and (not s.is_adult() or s.job != f_job):
			return false
		if group == 1 and not s.is_adult():
			return false
		if group == 2 and s.is_adult():
			return false
		if _settler_f_hungry.button_pressed and s.hunger >= 30.0:
			return false
		return true)
	var key := _settler_sort
	var desc := _settler_desc
	list.sort_custom(func(a, b):
		var va
		var vb
		match key:
			"name":
				va = a.display_name.to_lower()
				vb = b.display_name.to_lower()
			"job":
				va = _settler_job_label(a)
				vb = _settler_job_label(b)
			"hunger":
				va = a.hunger
				vb = b.hunger
			_:
				va = a.age
				vb = b.age
		if va == vb:
			return a.display_name < b.display_name
		return va > vb if desc else va < vb)
	# Spaltenkoepfe mit Pfeil fuer die Sortierung
	for col in SETTLER_COLS:
		var b: Button = _settler_head[col[0]]
		b.text = col[1] + ((" ▼" if _settler_desc else " ▲") if col[0] == _settler_sort else "")
	_settler_count.text = "%d von %d Siedlern. Spaltenkopf antippen sortiert. Satt zeigt, wie voll der Magen ist; rot heißt Hunger." % [list.size(), pool.size()]
	if list.is_empty():
		_settler_list.add_child(UiTheme.label("Niemand passt zu dieser Auswahl." if not pool.is_empty() else "Auf dieser Insel lebt niemand.", 14))
	var narrow := _settler_narrow
	var row_h := 30
	for s in list:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var sref = s
		# Name antippen: Siedler zeigen (auch auf einer anderen Insel)
		var nb := Button.new()
		nb.focus_mode = Control.FOCUS_NONE
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.custom_minimum_size = Vector2(40, row_h)
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.clip_text = true
		nb.add_theme_font_size_override("font_size", 14)
		_compact(nb)
		var other: bool = s.world != world
		nb.text = s.display_name + ("  (%s)" % Sea.island_name(s.world) if other else "")
		nb.tooltip_text = "Auf der Karte zeigen"
		nb.pressed.connect(func():
			_settler_panel.visible = false
			if is_instance_valid(sref) and sref.world != world:
				Sea.switch_to(sref.world.island_id)
			Game.select(sref)
			camera.focus(sref.position + _view_offset()))
		h.add_child(nb)
		var al := UiTheme.label("", 15)
		al.custom_minimum_size.x = SETTLER_COLS[1][3] if narrow else SETTLER_COLS[1][2]
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(al)
		var act: Label = null
		if not narrow:
			act = UiTheme.label("", 13, DIM)
			act.clip_text = true
			act.custom_minimum_size.x = 40
			act.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			act.size_flags_stretch_ratio = 1.4
			h.add_child(act)
		var jw: int = SETTLER_COLS[3][3] if narrow else SETTLER_COLS[3][2]
		if s.is_adult():
			# Beruf direkt in der Liste waehlen
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_NONE
			ob.custom_minimum_size = Vector2(jw, row_h - 2)
			ob.clip_text = true
			ob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ob.add_theme_font_size_override("font_size", 14)
			ob.get_popup().add_theme_font_size_override("font_size", 16)
			_compact(ob)
			var ids := []
			for j in Data.jobs:
				if not Data.job_unlocked(j) and j != s.job:
					continue
				ob.add_item(Data.jobs[j].name, ids.size())
				ids.append(j)
				if j == s.job:
					ob.select(ids.size() - 1)
			ob.tooltip_text = "Beruf wählen"
			ob.item_selected.connect(func(i):
				sref.set_job(ids[i])
				Game.player_action.emit("job", ids[i]))
			h.add_child(ob)
		else:
			var kl := UiTheme.label("Kind", 14, DIM)
			kl.custom_minimum_size.x = jw
			h.add_child(kl)
		# Saettigung: Balken mit Prozentzahl
		var sat := VBoxContainer.new()
		sat.custom_minimum_size.x = SETTLER_COLS[4][3] if narrow else SETTLER_COLS[4][2]
		sat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sat.add_theme_constant_override("separation", 1)
		var pl := UiTheme.label("", 12)
		sat.add_child(pl)
		var hb := UiTheme.bar(Color("#e0a040"), 8)
		hb.custom_minimum_size.x = 0
		sat.add_child(hb)
		h.add_child(sat)
		var fill: StyleBoxFlat = hb.get_theme_stylebox("fill")
		var upd := func():
			if not is_instance_valid(sref) or not is_instance_valid(nb):
				return
			al.text = str(int(sref.age))
			if act:
				act.text = sref.activity
			hb.value = sref.hunger
			var hungry: bool = sref.hunger < 30.0
			fill.bg_color = Color("#d04a3a") if hungry else Color("#e0a040")
			pl.text = "%d%%" % int(round(sref.hunger)) + (" Hunger!" if hungry and not narrow else "")
		upd.call()
		_settler_updaters.append(upd)
		_settler_list.add_child(h)
	call_deferred("_layout")


func _tick_settler_list(delta: float) -> void:
	if _settler_panel == null or not _settler_panel.visible:
		return
	_settler_tick -= delta
	if _settler_tick > 0.0:
		return
	_settler_tick = 1.0
	for u in _settler_updaters:
		u.call()


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
	v.add_child(_volume_row("Musik", "musik", Sound.music_volume, func(x): Sound.set_volumes(x, Sound.sfx_volume)))
	v.add_child(_volume_row("Geräusche", "glocke", Sound.sfx_volume, func(x):
		Sound.set_volumes(Sound.music_volume, x)
		Sound.play("klick")))
	if OS.has_feature("web") or OS.has_feature("mobile") or OS.has_feature("pc"):
		var fs := UiTheme.button("Vollbild", "vollbild", 44)
		fs.pressed.connect(func():
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			_menu_panel.visible = false)
		v.add_child(fs)
	var info := UiTheme.label("Das Spiel speichert automatisch.", 12)
	v.add_child(info)


func _volume_row(text: String, icon_name: String, value: float, on_change: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(UiTheme.icon_rect(Data.icon(icon_name), 20))
	var l := UiTheme.label(text, 15)
	l.custom_minimum_size.x = 86
	h.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = value
	sl.custom_minimum_size = Vector2(170, 36)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(on_change)
	h.add_child(sl)
	return h


const HELP_TEXT := """[b]Ziel[/b]
Führe deine kleine Siedlung durch die Generationen. Sorge für Nahrung, baue Hütten und lass deine Insel wachsen.

[b]Bedienung[/b]
Ziehen bewegt die Karte, Mausrad oder zwei Finger zoomen und schieben. Am PC geht es auch mit WASD oder den Pfeiltasten. Tippe auf Siedler, Gebäude oder Rohstoffe für Infos.

[b]Ziele[/b]
Oben links steht immer das nächste Ziel. Tippe darauf für eine Erklärung. Jedes erreichte Ziel bringt eine Belohnung, und es kommen immer neue nach.

[b]Ton[/b]
Lautstärke von Musik und Geräuschen stellst du im Menü ein.

[b]Siedler[/b]
Jeder Siedler hat eigene Fähigkeiten. Gib ihnen im Infofenster einen Beruf, der zu ihren Stärken passt. Mit Übung werden sie besser. Freie Siedler helfen dort, wo es nötig ist.

[b]Nahrung[/b]
Siedler essen am Lagerfeuer. Ohne Nahrung werden sie schwach und verhungern. Beeren wachsen nach, Fische auch, und Getreidefelder bringen viel Ertrag.

[b]Nachwuchs[/b]
Kinder kommen nur zur Welt, wenn es freie Wohnplätze in Hütten gibt und genug Nahrung im Lager ist. In Holzhäusern kommen 40 % öfter Kinder zur Welt, in Steinhäusern 80 %. Kinder werden nach 3 Tagen erwachsen, mit einer Schule (Forschung Unterricht) doppelt so schnell. Niemand lebt ewig, also sorge rechtzeitig für Nachwuchs.

[b]Bauen[/b]
Wähle ein Gebäude und einen Bauplatz. Baumeister und freie Siedler bringen das Material und bauen es auf. Hütten und Holzhäuser lassen sich später im Infofenster ausbauen.

[b]Forschung[/b]
Im Entwicklungsbaum wählst du, was deine Siedler als Nächstes lernen. Forscher denken am Lagerfeuer nach, in Schreibstube und Bibliothek viel schneller. Jede Forschung schaltet neue Gebäude frei oder macht die Arbeit leichter. Sechs Stufen führen von Steinwerkzeugen über Eisen und Schiffsbau bis zum Goldenen Zeitalter.

[b]Werkstätten[/b]
Sägegrube, Mühle, Bäckerei, Ziegelei und Co. verwandeln Rohstoffe in bessere Waren. Köche arbeiten in Mühle, Bäckerei, Räucherei und Hühnerhof, Handwerker in den Werkstätten, Steinmetze in Steinbruch, Lehmgrube und Mine. Tippe oben auf die Vorräte, um alle Waren zu sehen.

[b]Abwechslung[/b]
Gibt es mindestens drei Sorten Nahrung im Lager, kommen öfter Kinder zur Welt.

[b]Seefahrt[/b]
Mit der Forschung Schiffsbau baust du am Ufer eine Werft. Handwerker zimmern dort Boote. Über den Knopf Inseln öffnest du die Seekarte: Ein Boot sucht neue Inseln, und mit "Siedler schicken" bringt ein Boot bis zu vier Siedler hinüber. Alle Inseln teilen sich die Vorräte.

[b]Neue Inseln[/b]
Palmeninseln haben Kokosnüsse und viel Fisch, Waldinseln Pilze und Holz, Felseninseln Erz und Gold. Gold brauchst du für die höchsten Forschungen. Je weiter draußen, desto mehr wilde Tiere.

[b]Wilde Tiere[/b]
Wölfe, Wildschweine und Bären leben in Bauten und Höhlen. Siedler fliehen vor ihnen in Häuser, nachts sind Wölfe besonders gefährlich. Mit Waffenkunde werden Siedler zu Jägern und du kannst Wachtürme bauen. Jäger bringen Fleisch und Felle und räumen die Bauten aus, damit keine Tiere mehr nachkommen.

[b]Achtung[/b]
Stirbt auf einer Insel der letzte Siedler, ist diese Insel für immer verloren. Erst wenn alle Inseln verloren sind, ist das Spiel vorbei. Die Welt ist endlos: Es gibt immer noch eine Insel zu entdecken."""


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
	for pnl in _panels():
		pnl.visible = false
	_info_panel.visible = true
	_rebuild_info()
	_layout()
	# Liegt das Gewaehlte unter dem Infofenster, rueckt die Kamera es ins Bild
	if obj is Node2D and is_instance_valid(obj):
		var sp: Vector2 = obj.get_global_transform_with_canvas().origin
		if _info_panel.get_global_rect().grow(24).has_point(sp):
			camera.focus(obj.position + _view_offset())


## Kameraversatz, damit ein Ziel im freien Bereich neben dem Infofenster liegt.
func _view_offset() -> Vector2:
	if not _info_panel.visible:
		return Vector2.ZERO
	var vs := get_viewport().get_visible_rect().size
	if vs.y > vs.x:
		return Vector2(0, (vs.y / 2.0 - _info_panel.position.y / 2.0) / camera.zoom.y)
	return Vector2((vs.x / 2.0 - _info_panel.position.x / 2.0) / camera.zoom.x, 0)


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
		return "b%d|%s|%s|%s|%d|%d|%s|%s|%s|%s" % [o.id, o.complete, o.farm_state, str(o.delivered), int(o.build_fraction() * 50),
			int((Game.time_days - o.farm_time) * 20), str(o.occupants), o.paused, o.is_active(), o.prod_blocker()]
	if o is ResNode:
		return "n%s|%d|%d" % [o.cell, o.amount, int((o.regrow_at - Game.time_days) * 24)]
	if o is Animal:
		return "a%d|%s" % [o.get_instance_id(), o.target != null]
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
	elif o is Animal:
		_info_animal(o)


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
	_info_box.add_child(UiTheme.label("Zuhause: %s" % (home.def.name if home else "keins (schläft draußen)"), 13))
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
			if not Data.job_unlocked(j):
				b.disabled = true
				b.tooltip_text = tip + "\nBenötigt Forschung: %s" % Data.techs.get(jd.requires, {}).get("name", "?")
			b.pressed.connect(func():
				s.set_job(jid)
				Game.player_action.emit("job", jid)
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
			var bb := float(b.def.get("birth_bonus", 1.0))
			if bb > 1.0:
				_info_box.add_child(UiTheme.label("Kinder: %d %% öfter als in der Hütte" % roundi((bb - 1.0) * 100.0), 13, UiTheme.GOOD))
			if not names.is_empty():
				var l := UiTheme.label(", ".join(names), 13)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_info_box.add_child(l)
		if b.def.has("school"):
			var sl := UiTheme.label("", 14)
			_info_box.add_child(sl)
			var upd := func():
				var n := world.settlers.filter(func(s): return not s.is_adult() and world.school_of(s) == b).size()
				sl.text = "Schulkinder: %d / %d" % [n, int(b.def.school.get("slots", 8))]
			upd.call()
			_updaters.append(upd)
		if b.def.get("storage", 0) > 0:
			_info_box.add_child(UiTheme.label("Dieses Lager: +%d je Sorte" % int(int(b.def.storage) * Game.eff("storage")), 14))
			var tot := UiTheme.label("Alle Lager zusammen: %s" % Game.storage_breakdown(), 13)
			tot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_info_box.add_child(tot)
		if b.is_ground() and b.def.has("farm"):
			var st := {"fallow": "Wartet auf den Bauern", "growing": "Wächst", "ripe": "Erntereif!"}
			_info_box.add_child(UiTheme.label(st.get(b.farm_state, ""), 14))
			if b.farm_state == "growing":
				var frac: float = (Game.time_days - b.farm_time) / b.grow_days()
				_bar_row("Wachstum", frac * 100.0, UiTheme.GOOD)
			if not world.settlers.any(func(s): return s.job == "bauer"):
				var w := UiTheme.label("Ohne Bauern wird das Feld nur selten bestellt.", 13, UiTheme.BAD)
				w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_info_box.add_child(w)
	if b.complete and b.def.has("production"):
		_info_production(b)
	if b.complete and b.def.has("research"):
		_info_research(b)
	if b.def.has("upgrade"):
		_info_upgrade(b)
	var mv := UiTheme.button("Verschieben", "hammer", 36)
	mv.tooltip_text = "Stellt das Gebäude an einen anderen Platz. Vorräte, Bewohner und Baufortschritt ziehen mit."
	mv.pressed.connect(func(): world.start_move(b))
	_info_box.add_child(mv)
	if b.type != "lagerfeuer":
		var dm := UiTheme.button("Abreißen" if not _demolish_armed else "Wirklich abreißen?", "abriss", 36)
		dm.pressed.connect(func():
			if not _demolish_armed:
				_demolish_armed = true
				_rebuild_info()
				return
			world.demolish(b))
		_info_box.add_child(dm)


const WORKER_JOB := {"kueche": "koch", "handwerk": "handwerker", "stein": "steinmetz"}


func _recipe_row(p: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	for res in p.get("inputs", {}):
		h.add_child(UiTheme.label(str(int(p.inputs[res])), 15, UiTheme.TEXT, true))
		h.add_child(UiTheme.icon_rect(Data.res_icon(res), 18))
	if not p.get("inputs", {}).is_empty():
		h.add_child(UiTheme.label(" → ", 15, UiTheme.TEXT, true))
	for res in p.get("outputs", {}):
		h.add_child(UiTheme.label(str(int(p.outputs[res])), 15, UiTheme.TEXT, true))
		h.add_child(UiTheme.icon_rect(Data.res_icon(res), 18))
	return h


func _names_of(ids: Array) -> Array:
	var out := []
	for s in world.settlers:
		if s.id in ids:
			out.append(s.display_name)
	return out


func _info_production(b: Building) -> void:
	var p := b.prod_def()
	_info_box.add_child(UiTheme.label("Herstellung", 15, UiTheme.TEXT, true))
	_info_box.add_child(_recipe_row(p))
	var job_id: String = WORKER_JOB.get(p.get("job", ""), "")
	var job_name: String = Data.jobs.get(job_id, {}).get("name", "?")
	var status := ""
	var col := UiTheme.TEXT
	var block := b.prod_blocker()
	if b.paused:
		status = "Angehalten."
		col = Color("#8a5a3a")
	elif b.is_active() or not b.occupants.is_empty():
		status = "In Betrieb."
		col = UiTheme.GOOD
	elif block != "":
		status = block + "."
		col = UiTheme.BAD
	elif not world.settlers.any(func(s): return s.is_adult() and s.job == job_id):
		status = "Niemand arbeitet hier. Gib einem Siedler den Beruf %s." % job_name
		col = UiTheme.BAD
	else:
		status = "Wartet auf Arbeiter (%s)." % job_name
	var st := UiTheme.label(status, 13, col)
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(st)
	var names := _names_of(b.occupants)
	if not names.is_empty():
		_info_box.add_child(UiTheme.label("Arbeiter: " + ", ".join(names), 13))
	var pb := UiTheme.button("Weiterarbeiten" if b.paused else "Anhalten", "play" if b.paused else "pause", 34)
	pb.pressed.connect(func():
		b.paused = not b.paused
		_rebuild_info())
	_info_box.add_child(pb)


func _info_research(b: Building) -> void:
	_info_box.add_child(UiTheme.label("Forschung", 15, UiTheme.TEXT, true))
	_info_box.add_child(UiTheme.label("Tempo: x%.1f   Plätze: %d" % [float(b.research_def().get("factor", 1.0)), b.slots()], 13))
	var names := _names_of(b.occupants)
	_info_box.add_child(UiTheme.label("Forscher hier: " + (", ".join(names) if not names.is_empty() else "niemand"), 13))
	var cur: String = Game.research.current
	var l := UiTheme.label("Aktuell: " + (Data.techs[cur].name if cur != "" else "nichts ausgewählt"), 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(l)
	var open := UiTheme.button("Forschung öffnen", "wissen", 34)
	open.pressed.connect(func():
		Game.select(null)
		_fill_research_list()
		_toggle(_research_panel))
	_info_box.add_child(open)


func _info_upgrade(b: Building) -> void:
	if not b.complete:
		return
	var to: String = b.def.upgrade
	var td: Dictionary = Data.buildings[to]
	if not Game.is_unlocked(to):
		var l := UiTheme.label("Ausbau: %s nach der Forschung %s." % [td.name, Data.techs[td.requires].name], 13, Color("#8a5a3a"))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(l)
		return
	var ub := UiTheme.button("Ausbauen: %s" % td.name, "hammer", 36)
	ub.tooltip_text = "Wird zur Baustelle. Bewohner und Forscher ziehen solange aus."
	ub.pressed.connect(func(): world.upgrade_building(b))
	_info_box.add_child(ub)
	var h := HBoxContainer.new()
	h.add_child(UiTheme.label("Kosten:", 13))
	for res in td.cost:
		h.add_child(UiTheme.icon_rect(Data.res_icon(res), 14))
		h.add_child(UiTheme.label(str(int(td.cost[res])), 13, UiTheme.TEXT if Game.amount(res) >= int(td.cost[res]) else UiTheme.BAD))
	_info_box.add_child(h)
	if td.has("housing"):
		_info_box.add_child(UiTheme.label("Platz für %d statt %d Siedler." % [int(td.get("housing", 0)), int(b.def.get("housing", 0))], 12))
	if td.has("research"):
		var rd: Dictionary = td.research
		var cur := b.research_def()
		var l := UiTheme.label("Forschungstempo x%.1f statt x%.1f, %d statt %d Forscher." % [float(rd.factor), float(cur.get("factor", 1.0)),
			int(rd.slots), int(cur.get("slots", 1))], 12, UiTheme.GOOD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(l)
	if float(td.get("birth_bonus", 1.0)) > float(b.def.get("birth_bonus", 1.0)):
		_info_box.add_child(UiTheme.label("Dort kommen mehr Kinder zur Welt.", 12, UiTheme.GOOD))


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
	var who := {"baum": "Holzfäller", "fels": "Steinmetz", "busch": "Sammler", "fischgrund": "Fischer",
		"palme": "Sammler", "pilzkreis": "Sammler", "erzader": "Steinmetz", "goldader": "Steinmetz", "beute": "Jäger"}
	if n.def.has("spawns"):
		var an: Dictionary = Data.animals[n.def.spawns]
		var l := UiTheme.label("Hier leben bis zu %d: %s. Jäger können den Bau ausräumen, dann kommen keine Tiere mehr nach." % [int(n.def.get("den_cap", 1)), an.name], 13, UiTheme.BAD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(l)
	else:
		_info_box.add_child(UiTheme.label("Wird bearbeitet von: %s" % who.get(n.type, "?"), 13))
	if n.def.has("decay_days") and n.regrow_at >= 0.0:
		_info_box.add_child(UiTheme.label("Verdirbt in %d Std." % max(1, int(ceil((n.regrow_at - Game.time_days) * 24.0))), 13))


func _info_animal(a: Animal) -> void:
	_info_head(a.def.name)
	var hb := _bar_row("Kraft", a.hp / a.max_hp() * 100.0, UiTheme.BAD)
	var st := UiTheme.label("", 14, Color("#6a4a30"))
	_info_box.add_child(st)
	var upd := func():
		if not is_instance_valid(a):
			return
		hb.value = a.hp / a.max_hp() * 100.0
		st.text = ("Greift %s an!" % a.target.display_name) if a.target and is_instance_valid(a.target) else "Streift umher."
	upd.call()
	_updaters.append(upd)
	var t := "Gefährlich! Biss: %d Schaden. Siedler fliehen in Häuser. Jäger (Forschung Waffenkunde) und Wachtürme wehren die Tiere ab. Erlegt gibt es Fleisch und Felle." % int(a.def.damage)
	if float(a.def.aggro) < 3.0:
		t = "Greift nur an, wenn man ihm zu nahe kommt. Biss: %d Schaden. Jäger und Wachtürme erlegen es für Fleisch und Felle." % int(a.def.damage)
	var l := UiTheme.label(t, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(l)


# ================================================================== Meldungen
func toast(text: String, icon_name: String = "") -> void:
	# Dieselbe Meldung nicht doppelt stapeln
	for c in _toasts.get_children():
		if c.get_meta("text", "") == text and not c.is_queued_for_deletion():
			return
	var p := PanelContainer.new()
	p.set_meta("text", text)
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
	Sound.in_title = true
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
	var t := UiTheme.label("Alle Inseln sind verloren" if Sea.islands.size() > 1 else "Die Insel ist verloren", 30, UiTheme.BAD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UiTheme.label("Deine Siedlung hielt %d Tage durch.\nGeburten: %d   Höchste Bevölkerung: %d   Entdeckte Inseln: %d" % [
		Game.day(), int(Game.stats.births), int(Game.stats.max_pop), Sea.islands.size() - 1], 15)
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
	# Schmaler Bildschirm: Symbol ueber dem Text, alle Knoepfe gleich breit
	var btns := _bottom.get_children().filter(func(b): return b.visible)
	var narrow_bar := vs.x < 140.0 * btns.size()
	for b in btns:
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP if narrow_bar else VERTICAL_ALIGNMENT_CENTER
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if narrow_bar else HORIZONTAL_ALIGNMENT_LEFT
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			if narrow_bar:
				var sb: StyleBox = root.theme.get_stylebox(st, "Button").duplicate()
				sb.content_margin_left = 2
				sb.content_margin_right = 2
				b.add_theme_stylebox_override(st, sb)
			else:
				b.remove_theme_stylebox_override(st)
		if narrow_bar:
			b.add_theme_font_size_override("font_size", 12)
			b.custom_minimum_size = Vector2(floor((vs.x - 30.0 - 6.0 * (btns.size() - 1)) / btns.size()), 50)
			b.clip_text = true
		else:
			b.remove_theme_font_size_override("font_size")
			b.custom_minimum_size = Vector2(44, 44)
			b.clip_text = false
		b.reset_size()
	_bottom.add_theme_constant_override("separation", 6 if narrow_bar else 8)
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
	if goal_card:
		var narrow := portrait or vs.x < 760
		var gw: float = (vs.x - sp.size.x - 18.0) if narrow else min(310.0, vs.x * 0.4)
		goal_card.custom_minimum_size.x = gw
		goal_card.reset_size()
		goal_card.size.x = gw
		goal_card.position = Vector2(6, 54 if narrow else 50)
		goal_card.set_deferred("size", Vector2(gw, 0))
		if goal_card.visible:
			_toasts.position.y = max(top_h, goal_card.position.y + goal_card.size.y) + 6
	_size_settler_panel(vs.y - top_h - bp.size.y - 18.0)
	for pnl in _panels():
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
	_tick_settler_list(delta)
	_day_label.text = "Tag %d  %s" % [Game.day(), Game.clock_text()]
	_day_icon.texture = Data.icon("mond" if Game.is_night() else "sonne")
	_research_tick -= delta
	if _research_tick <= 0.0:
		_research_tick = 0.5
		_update_research_head()
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
		camera.focus(_info_obj.position + _view_offset())
