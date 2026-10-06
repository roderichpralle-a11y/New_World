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
var _food_short := false  # schmaler Bildschirm: Tage kurz als "3T"
var _pop_label: Label
var _day_label: Label
var _day_icon: TextureRect
var _season_icon: TextureRect
var _season_label: Label
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
var _notify_panel: PanelContainer
var _slots_panel: PanelContainer
var _slots_box: VBoxContainer
var _slots_scroll: ScrollContainer
var _import_cb  # JavaScriptObject: Rueckruf fuer die Dateiauswahl im Browser (muss leben bleiben)
var _import_slot_n := 0
var _update_btn: Button
var _update_ready := false
var _notify_grid: GridContainer
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
var _council_panel: CouncilPanel
var _council_btn: Button
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
	_build_notify_panel()
	_build_slots_panel()
	_build_info_panel()
	_sea_panel = SeaPanel.new()
	root.add_child(_sea_panel)
	_sea_panel.setup(self)
	_council_panel = CouncilPanel.new()
	root.add_child(_council_panel)
	_council_panel.setup(self)
	Society.changed.connect(_update_council_button)
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
	_watch_updates.call_deferred()


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
	p.tooltip_text = tr("Tippen: alle Vorräte anzeigen")
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
	pc[0].tooltip_text = tr("Bewohner / Wohnplätze")
	pc[0].mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(pc[0])
	var dc := HBoxContainer.new()
	dc.add_theme_constant_override("separation", 3)
	_day_icon = UiTheme.icon_rect(Data.icon("sonne"), 18)
	dc.add_child(_day_icon)
	_day_label = UiTheme.label(tr("Tag 1"), 16)
	dc.add_child(_day_label)
	h.add_child(dc)
	# Jahreszeit: Tippen zeigt, was sie bewirkt
	var sc := HBoxContainer.new()
	sc.add_theme_constant_override("separation", 3)
	sc.mouse_filter = Control.MOUSE_FILTER_STOP
	sc.tooltip_text = tr("Jahreszeit (Tag in der Jahreszeit). Tippen: was sie bewirkt")
	sc.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			sc.accept_event()
			Sound.play("klick")
			Game.notify(tr("Jahr %d, %s Tag %d von %d. %s") % [Seasons.year(), Seasons.season_name(),
				Seasons.day_in_season(), int(Seasons.season_days()), Seasons.effects_text()], ""))
	_season_icon = UiTheme.icon_rect(Seasons.icon(), 18)
	_season_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	sc.add_child(_season_icon)
	_season_label = UiTheme.label("", 16)
	_season_label.mouse_filter = Control.MOUSE_FILTER_PASS
	sc.add_child(_season_label)
	h.add_child(sc)
	_island_label = UiTheme.label("", 14, Color("#7a4a28"), true)
	_island_label.visible = false
	h.add_child(_island_label)
	_food_label.get_parent().set_meta("is_food", true)

	var sp := PanelContainer.new()
	sp.name = tr("SpeedPanel")
	root.add_child(sp)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 4)
	sp.add_child(sh)
	for i in 3:
		var icon_name: String = ["pause", "play", "schnell"][i]
		var b := UiTheme.button("", icon_name, 34)
		b.toggle_mode = true
		b.tooltip_text = [tr("Pause"), tr("Normal"), tr("Schnell (3x)")][i]
		var spd: int = [0, 1, 3][i]
		b.pressed.connect(func(): Game.set_speed(spd))
		sh.add_child(b)
		_speed_btns.append([b, spd])
	_on_speed(Game.speed)


func _refresh_top() -> void:
	for id in _res_labels:
		var room := Game.space_for(id)
		_res_labels[id].text = "%d" % Game.amount(id)
		_res_labels[id].add_theme_color_override("font_color", UiTheme.BAD if room <= 0 else UiTheme.TEXT)
		_res_labels[id].get_parent().tooltip_text = tr("%s: %d, Platz für %d weitere") % [Data.resource_name(id), Game.amount(id), room]
	var food := Game.total_food()
	var days := Game.food_days()
	if days < 0.0:
		_food_label.text = "%d" % food
	else:
		var dn := int(floor(min(days, 999.0)))
		if _food_short:
			_food_label.text = "%d (%s)" % [food, tr("%dT") % dn]
		else:
			_food_label.text = "%d (%s)" % [food, tr("1 Tag") if dn == 1 else tr("%d Tage") % dn]
	var parts := []
	for id in Data.food_ids():
		parts.append(tr("%s: %d  (sättigt %d, Vitamine %d)") % [Data.resource_name(id), Game.amount(id), int(Data.food_satiety(id)), int(Data.food_vitamins(id))])
	var days_tip := (tr("\nReicht für etwa %.1f Tage: Menge mal Sättigung aller Nahrung, geteilt durch die Siedler und ihren Tagesbedarf.") % days) if days >= 0.0 else ""
	_food_label.get_parent().tooltip_text = tr("Nahrung\n") + "\n".join(parts) + days_tip + tr("\nStauraum: %d von %d belegt") % [Game.used_volume(), Game.storage_volume()]
	var pop := Game.population()
	_food_label.add_theme_color_override("font_color", UiTheme.BAD if (days >= 0.0 and days < 1.0) or (days < 0.0 and food < pop * 3) else UiTheme.TEXT)
	var here: int = world.settlers.size() if world and is_instance_valid(world) else 0
	_pop_label.text = "%d/%d" % [here, Game.housing_capacity()]
	var tip := tr("Bewohner / Wohnplätze auf dieser Insel")
	if Sea.worlds.size() > 1 or Sea.people_at_sea() > 0:
		tip += tr("\nAuf allen Inseln und See: %d") % (pop + Sea.people_at_sea())
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
	p.name = tr("BottomPanel")
	root.add_child(p)
	_bottom = HBoxContainer.new()
	_bottom.add_theme_constant_override("separation", 8)
	p.add_child(_bottom)
	var bb := UiTheme.button(tr("Bauen"), "hammer", 44)
	bb.pressed.connect(func(): _toggle(_build_panel))
	_bottom.add_child(bb)
	_build_btn = bb
	_research_btn = UiTheme.button(tr("Forschung"), "wissen", 44)
	_research_btn.pressed.connect(func():
		_fill_research_list()
		_toggle(_research_panel))
	_bottom.add_child(_research_btn)
	var sb := UiTheme.button(tr("Siedler"), "person", 44)
	sb.pressed.connect(func():
		_toggle(_settler_panel)
		_refresh_settler_list())
	_bottom.add_child(sb)
	_sea_btn = UiTheme.button(tr("Inseln"), "boot", 44)
	_sea_btn.pressed.connect(_open_sea)
	_bottom.add_child(_sea_btn)
	_council_btn = UiTheme.button(tr("Rat"), "glocke", 44)
	_council_btn.tooltip_text = tr("Rat der Inseln: Anliegen, Abstimmungen, Diskussion")
	_council_btn.pressed.connect(_open_council)
	_council_btn.visible = Society.enabled
	_bottom.add_child(_council_btn)
	var mb := UiTheme.button(tr("Menü"), "menu", 44)
	mb.pressed.connect(func(): _toggle(_menu_panel))
	_bottom.add_child(mb)


func _open_sea() -> void:
	_sea_panel.open()
	if not _sea_panel.visible:
		_toggle(_sea_panel)
	_layout()


func _open_council() -> void:
	_council_panel.open()
	if not _council_panel.visible:
		_toggle(_council_panel)
	_layout()


func _update_council_button() -> void:
	if _council_btn == null:
		return
	var n := Society.requests.size()
	_council_btn.text = tr("Rat (%d)") % n if n > 0 else tr("Rat")
	_council_btn.visible = Society.enabled


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
	return [_build_panel, _research_panel, _stock_panel, _settler_panel, _menu_panel, _help_panel, _notify_panel, _slots_panel, _sea_panel, _council_panel]


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
	x.tooltip_text = tr("Schließen")
	x.pressed.connect(func(): p.visible = false)
	head.add_child(x)
	v.add_child(head)
	return [p, v]


# ================================================================== Bau-Menue
const BUILD_CATS := [["wohnen", "Wohnen", "haus"], ["nahrung", "Nahrung", "nahrung"],
	["handwerk", "Handwerk", "hammer"], ["lager", "Lager", "kiste"], ["wissen", "Wissen", "wissen"],
	["see", "Seefahrt und Schutz", "boot"]]


func _build_build_panel() -> void:
	var r := _popup_panel(tr("Bauen"))
	_build_panel = r[0]
	var v: VBoxContainer = r[1]
	_build_title = v.get_child(0).get_child(0)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	v.add_child(tabs)
	for c in BUILD_CATS:
		var b := UiTheme.button("", c[2], 40)
		b.toggle_mode = true
		b.tooltip_text = tr(c[1])
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
			_build_title.text = tr("Bauen: ") + tr(c[1])
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
			desc = tr("Benötigt Forschung: %s") % Data.techs.get(def.requires, {}).get("name", "?")
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
	var r := _popup_panel(tr("Forschung"))
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
	var who := tr("Keine Forscher! Gib einem Siedler den Beruf Forscher.") if n == 0 else tr("Forscher: %d") % n
	who = tr("Zeitalter: %s. %s") % [Data.age_name(Game.current_age()), who]
	if cur == "":
		_research_label.text = tr("Wähle eine Forschung aus. %s") % who
		_research_bar.value = 0
	else:
		var pts := Game.tech_points(cur)
		_research_label.text = tr("Forschung: %s  (%d / %d)\n%s") % [Data.techs[cur].name, int(Game.tech_progress(cur)), int(pts), who]
		_research_bar.value = Game.tech_progress(cur) / pts * 100.0
	_research_label.add_theme_color_override("font_color", UiTheme.BAD if n == 0 else UiTheme.TEXT)
	var label := tr("Forschung")
	if cur != "":
		label = "%d%%" % int(Game.tech_progress(cur) / Game.tech_points(cur) * 100.0)
	_research_btn.text = label


const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI"]


func _fill_research_list() -> void:
	var keep := _research_scroll.scroll_vertical
	for c in _research_list.get_children():
		_research_list.remove_child(c)
		c.queue_free()
	_update_research_head()
	var tier := 0
	var age := -1
	var cur_age := Game.current_age()
	for t in Data.sorted_tech_ids():
		var def: Dictionary = Data.techs[t]
		var a := Data.age_of_tier(int(def.tier))
		if a != age:
			age = a
			_research_list.add_child(_age_header(a, cur_age))
		if a > cur_age + 1:
			continue  # spaetere Zeitalter bleiben ein Geheimnis
		if int(def.tier) != tier:
			tier = int(def.tier)
			var name: String = Data.tiers[tier - 1] if tier - 1 < Data.tiers.size() else ""
			var hl := UiTheme.label(tr("Stufe %s: %s") % [ROMAN[min(tier - 1, ROMAN.size() - 1)], name], 16, Color("#7a4a28"), true)
			_research_list.add_child(hl)
		_research_list.add_child(_tech_row(t))
	await get_tree().process_frame
	_research_scroll.scroll_vertical = keep


## Ueberschrift eines Zeitalters im Entwicklungsbaum; spaetere Zeitalter nur angedeutet.
func _age_header(a: int, cur_age: int) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(UiTheme.icon_rect(Data.icon("zeitalter"), 28))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(v)
	var state := tr("jetzt") if a == cur_age else (tr("erreicht") if a < cur_age else (tr("als Nächstes") if a == cur_age + 1 else tr("noch unbekannt")))
	var col := Color("#2f6a3a") if a == cur_age else (Color("#7a4a28") if a <= cur_age + 1 else Color("#8a7a6a"))
	var tl := UiTheme.label(tr("Zeitalter %d: %s (%s)") % [a + 1, Data.age_name(a), state], 16, col, true)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size.x = 200
	v.add_child(tl)
	var d := UiTheme.label(Data.ages[a].get("desc", "") if a <= cur_age + 1 else tr("Erreiche erst das Zeitalter %s.") % Data.age_name(a - 1), 12, col)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 200
	v.add_child(d)
	return box


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
			right.add_child(UiTheme.label(tr("Erforscht"), 13, UiTheme.GOOD, true))
			b.modulate = Color(0.85, 1.0, 0.85)
		"soon":
			right.add_child(UiTheme.label(tr("Bald"), 13, Color("#8a5a3a"), true))
		"locked":
			var need := []
			for rq in def.get("requires", []):
				if not Game.is_researched(rq):
					need.append(Data.techs[rq].name)
			var l := UiTheme.label(tr("Gesperrt"), 13, Color("#8a5a3a"), true)
			right.add_child(l)
			d.text = tr("Benötigt: ") + ", ".join(need)
		_:
			var cost := GridContainer.new()
			cost.columns = 2
			cost.add_theme_constant_override("h_separation", 2)
			cost.add_theme_constant_override("v_separation", 0)
			cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if t in Game.research.paid:
				right.add_child(UiTheme.label(tr("bezahlt"), 12, col))
			else:
				for res in def.get("cost", {}):
					cost.add_child(UiTheme.icon_rect(Data.res_icon(res), 14))
					var enough := Game.amount(res) >= int(def.cost[res])
					cost.add_child(UiTheme.label(str(int(def.cost[res])), 13, col if enough else UiTheme.BAD))
				right.add_child(cost)
			var pct := Game.tech_progress(t) / Game.tech_points(t) * 100.0
			right.add_child(UiTheme.label(tr("%d Pkt.") % int(Game.tech_points(t)) if pct <= 0 else "%d%%" % int(pct), 12, col))
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
				toast(tr("Forschung gestartet: %s") % def.name, "wissen")
				if _forscher_count() == 0:
					toast(tr("Tipp: Gib einem Siedler den Beruf Forscher."), "person")
		"locked":
			toast(d.text, "wissen")
		"soon":
			toast(tr("Dieses Wissen kommt mit einem späteren Update."), "wissen")
		"done":
			toast(tr("%s ist schon erforscht.") % def.name, "wissen")


func _on_research_changed() -> void:
	_update_sea_button()
	if _research_panel.visible:
		_fill_research_list()
	else:
		_update_research_head()
	_fill_build_list()


# ================================================================== Vorraete
func _build_stock_panel() -> void:
	var r := _popup_panel(tr("Lager"))
	_stock_panel = r[0]
	var v: VBoxContainer = r[1]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(min(440.0, get_viewport().get_visible_rect().size.x - 40.0), 300)
	v.add_child(scroll)
	_stock_grid = GridContainer.new()
	_stock_grid.columns = 1
	_stock_grid.add_theme_constant_override("v_separation", 2)
	_stock_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_stock_grid)


func _refresh_stock(force: bool = false) -> void:
	if _stock_grid == null or (not force and not _stock_panel.visible):
		return
	for c in _stock_grid.get_children():
		_stock_grid.remove_child(c)
		c.queue_free()
	var vol := Game.storage_volume()
	var used := Game.used_volume()
	var head := UiTheme.label(tr("Stauraum: %d von %d belegt, %d für feste Mengen reserviert") % [used, vol, Game.reserved_volume()], 13)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stock_grid.add_child(head)
	var bar := UiTheme.bar(UiTheme.BAD if used >= vol else UiTheme.GOOD)
	bar.value = 100.0 * used / max(1, vol)
	_stock_grid.add_child(bar)
	var hint := UiTheme.label(tr("Lege mit − und + fest, wie viel von einer Ware gelagert wird. „×2“ ist der Raum, den ein Stück braucht. „frei“ heißt: die Ware nimmt sich freien Platz, solange welcher da ist. Ist kein Platz mehr, sammeln die Siedler diese Ware nicht mehr."), 12, UiTheme.TEXT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate.a = 0.8
	_stock_grid.add_child(hint)
	for id in Data.sorted_resource_ids():
		if Data.resources[id].get("category", "") == "ship":
			continue  # Schiffe liegen im Hafen, nicht im Lager
		_stock_grid.add_child(_stock_row(id))
	var food := UiTheme.label(tr("Nahrungssorten: %d") % Game.food_variety(), 13)
	food.tooltip_text = tr("Ab %d Sorten im Lager kommen öfter Kinder zur Welt.") % int(Data.bal("variety_min", 3))
	food.mouse_filter = Control.MOUSE_FILTER_PASS
	_stock_grid.add_child(food)


func _stock_row(id: String) -> Control:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(UiTheme.icon_rect(Data.res_icon(id), 18))
	var size := Data.good_size(id)
	var n := UiTheme.label(Data.resource_name(id), 14)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.tooltip_text = tr("Größe: %d Raum je Stück") % size if size > 0 else tr("Braucht keinen Lagerraum.")
	n.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(n)
	var a := Game.amount(id)
	var full := size > 0 and Game.space_for(id) <= 0
	var al := UiTheme.label("%d" % a, 14, UiTheme.BAD if full else UiTheme.TEXT, true)
	al.custom_minimum_size.x = 36
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(al)
	h.modulate.a = 1.0 if a > 0 or Game.limit_of(id) >= 0 else 0.6
	if size <= 0:
		var x := UiTheme.label(tr("ohne Lagerraum"), 12)
		x.custom_minimum_size.x = 150
		h.add_child(x)
		return h
	var sl := UiTheme.label("×%d" % size, 12)
	sl.tooltip_text = tr("Größe: %d Raum je Stück") % size
	sl.mouse_filter = Control.MOUSE_FILTER_PASS
	sl.custom_minimum_size.x = 24
	h.add_child(sl)
	var lim := Game.limit_of(id)
	var minus := UiTheme.button("−", "", 30)
	minus.tooltip_text = tr("Weniger lagern")
	minus.pressed.connect(func():
		var cur := Game.limit_of(id)
		if cur < 0:
			Game.set_limit(id, ceili(Game.amount(id) / 10.0) * 10)
		else:
			Game.set_limit(id, max(0, cur - 10))
		_refresh_stock(true))
	h.add_child(minus)
	var ll := UiTheme.label("frei" if lim < 0 else "%d" % lim, 14)
	ll.custom_minimum_size.x = 38
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ll.tooltip_text = tr("Höchstens so viel wird gelagert.") if lim >= 0 else tr("Keine feste Menge: nimmt freien Platz.")
	ll.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(ll)
	var plus := UiTheme.button("+", "", 30)
	plus.tooltip_text = tr("Mehr lagern")
	plus.disabled = lim >= 0 and lim >= Game.max_limit(id)
	plus.pressed.connect(func():
		var cur := Game.limit_of(id)
		var base: int = ceili(Game.amount(id) / 10.0) * 10 if cur < 0 else cur
		var got := Game.set_limit(id, base + 10)
		if got < base + 10:
			toast(tr("Der Stauraum ist ausgeschöpft."), "kiste")
		_refresh_stock(true))
	h.add_child(plus)
	var ex := Game.excess(id)
	if ex > 0:
		var d := UiTheme.button(tr("%d weg") % ex, "", 30)
		d.tooltip_text = tr("Überschuss wegwerfen. Er ist dann verloren.")
		d.add_theme_color_override("font_color", UiTheme.BAD)
		d.pressed.connect(func():
			var k := Game.discard_excess(id)
			toast(tr("%d %s weggeworfen.") % [k, Data.resource_name(id)], "abriss")
			_refresh_stock(true))
		h.add_child(d)
	elif lim >= 0:
		var f := UiTheme.button("frei", "", 30)
		f.tooltip_text = tr("Feste Menge aufheben")
		f.pressed.connect(func():
			Game.set_limit(id, -1)
			_refresh_stock(true))
		h.add_child(f)
	else:
		var sp := Control.new()
		sp.custom_minimum_size.x = 30
		h.add_child(sp)
	return h


func _build_place_bar() -> void:
	_place_bar = PanelContainer.new()
	_place_bar.visible = false
	root.add_child(_place_bar)
	var h := HBoxContainer.new()
	_place_bar.add_child(h)
	_place_label = UiTheme.label(tr("Klicke auf einen freien Platz."), 14)
	_place_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place_label.custom_minimum_size.x = 220
	_place_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_place_label)
	_place_ok = UiTheme.button(tr("Hier bauen"), "hammer", 44)
	_place_ok.pressed.connect(func(): world.confirm_placement())
	h.add_child(_place_ok)
	var c := UiTheme.button(tr("Abbrechen"), "abriss", 44)
	c.pressed.connect(func(): world.cancel_placement())
	h.add_child(c)


func _on_placement(active: bool, type: String, valid: bool) -> void:
	_place_bar.visible = active
	_bottom.get_parent().visible = not active
	if active:
		_place_ok.disabled = not valid
		var moving: bool = world.moving_building() != null
		_place_ok.text = tr("Hier hinstellen") if moving else tr("Hier bauen")
		if moving:
			_place_label.text = tr("%s verschieben: Klicke auf den neuen Platz. Am Handy tippen, dann Hier hinstellen.%s") % [
				Data.buildings[type].name, tr(" Der Platz passt.") if valid else (tr("\nMuss am Ufer stehen und Platz haben.") if Data.buildings[type].get("coast", false) else tr("\nHier ist kein Platz frei."))]
			_layout()
			return
		_place_label.text = tr("%s: Klicke auf einen freien Platz. Am Handy tippen, dann Hier bauen.%s") % [
			Data.buildings[type].name, tr(" Der Platz passt.") if valid else (tr("\nMuss am Ufer stehen und Platz haben.") if Data.buildings[type].get("coast", false) else tr("\nHier ist kein Platz frei."))]
	_layout()


# ================================================================== Siedlerliste
const DIM := Color("#6e5a50")
## Sortierbare Spalten: Schluessel, Text, Breite (0 = dehnbar; breit / schmal)
const SETTLER_COLS := [["name", "Name", 0, 0], ["age", "Alter", 62, 30], ["act", "Tätigkeit", 0, -1],
	["job", "Beruf", 150, 84], ["busy", "Auslastung", 110, 40], ["hunger", "Satt", 120, 44], ["mood", "Laune", 120, 44]]
var _settler_scroll: ScrollContainer
var _settler_updaters: Array = []
var _settler_tick: float = 0.0
var _settler_head: Dictionary = {}  # Spalte -> Knopf
var _settler_sort: String = "age"
var _settler_desc: bool = true
var _settler_f_job: OptionButton
var _settler_f_group: OptionButton
var _settler_f_hungry: CheckBox
var _settler_f_sick: CheckBox
var _settler_f_island: OptionButton
var _settler_count: Label
var _settler_narrow: bool = false


func _build_settler_panel() -> void:
	var r := _popup_panel(tr("Siedler"))
	_settler_panel = r[0]
	var v: VBoxContainer = r[1]
	# Filter
	var fr := HFlowContainer.new()
	fr.add_theme_constant_override("h_separation", 8)
	fr.add_theme_constant_override("v_separation", 4)
	_settler_f_job = _settler_filter_button(tr("Welche Berufe anzeigen"))
	fr.add_child(_settler_f_job)
	_settler_f_group = _settler_filter_button(tr("Erwachsene oder Kinder anzeigen"))
	for t in [tr("Alle Alter"), tr("Erwachsene"), tr("Kinder")]:
		_settler_f_group.add_item(t)
	fr.add_child(_settler_f_group)
	_settler_f_island = _settler_filter_button(tr("Welche Insel anzeigen"))
	fr.add_child(_settler_f_island)
	_settler_f_hungry = CheckBox.new()
	_settler_f_hungry.text = tr("Nur Hungrige")
	_settler_f_hungry.focus_mode = Control.FOCUS_NONE
	_settler_f_hungry.custom_minimum_size.y = 40
	_settler_f_hungry.add_theme_font_size_override("font_size", 15)
	_settler_f_hungry.toggled.connect(func(_on): _refresh_settler_list())
	fr.add_child(_settler_f_hungry)
	_settler_f_sick = CheckBox.new()
	_settler_f_sick.text = tr("Nur Kranke")
	_settler_f_sick.focus_mode = Control.FOCUS_NONE
	_settler_f_sick.custom_minimum_size.y = 40
	_settler_f_sick.add_theme_font_size_override("font_size", 15)
	_settler_f_sick.toggled.connect(func(_on): _refresh_settler_list())
	fr.add_child(_settler_f_sick)
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
			b.tooltip_text = tr("Nach %s sortieren") % tr(col[1])
			b.pressed.connect(func():
				if _settler_sort == key:
					_settler_desc = not _settler_desc
				else:
					_settler_sort = key
					_settler_desc = key in ["age", "hunger", "mood"]
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
		b.add_theme_font_size_override("font_size", 12 if _settler_narrow else 14)
		b.add_theme_constant_override("h_separation", 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if cw == 0 else Control.SIZE_FILL
		if col[0] == "act":
			b.size_flags_stretch_ratio = 1.4


## Flachere Knoepfe fuer lange Listen
var _compact_boxes: Dictionary = {}


func _compact(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		if not _compact_boxes.has(st):
			var sb = _settler_panel.get_theme_stylebox(st, tr("Button"))
			if sb == null:
				continue
			sb = sb.duplicate()
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			_compact_boxes[st] = sb
		b.add_theme_stylebox_override(st, _compact_boxes[st])


func _settler_job_label(s) -> String:
	return Data.jobs[s.job].name if s.is_adult() else tr("Kind")


## Filterauswahl aktuell halten (Berufe, Inseln), gewaehlte Eintraege bleiben stehen.
func _update_settler_filters() -> void:
	var keep_job = _settler_f_job.get_item_metadata(_settler_f_job.selected) if _settler_f_job.item_count > 0 else ""
	_settler_f_job.clear()
	_settler_f_job.add_item(tr("Alle Berufe"))
	_settler_f_job.set_item_metadata(0, "")
	for j in Data.jobs:
		if Data.job_unlocked(j):
			_settler_f_job.add_item(Data.jobs[j].name)
			_settler_f_job.set_item_metadata(_settler_f_job.item_count - 1, j)
			if j == keep_job:
				_settler_f_job.select(_settler_f_job.item_count - 1)
	var keep_isl = _settler_f_island.get_item_metadata(_settler_f_island.selected) if _settler_f_island.item_count > 0 else -1
	_settler_f_island.clear()
	_settler_f_island.add_item(tr("Diese Insel"))
	_settler_f_island.set_item_metadata(0, -1)
	_settler_f_island.add_item(tr("Alle Inseln"))
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
		if _settler_f_sick.button_pressed and s.mind.sick == "":
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
			"busy":
				va = a.busy_percent() if a.is_adult() else -2
				vb = b.busy_percent() if b.is_adult() else -2
			"hunger":
				va = a.hunger
				vb = b.hunger
			"mood":
				va = a.mind.mood
				vb = b.mind.mood
			_:
				va = a.age
				vb = b.age
		if va == vb:
			return a.display_name < b.display_name
		return va > vb if desc else va < vb)
	# Spaltenkoepfe mit Pfeil fuer die Sortierung
	for col in SETTLER_COLS:
		var b: Button = _settler_head[col[0]]
		b.text = tr(col[1]) + ((" ▼" if _settler_desc else " ▲") if col[0] == _settler_sort else "")
	var stage := SettlerMind.comfort_stage()
	var sick_n := pool.filter(func(x): return x.mind.sick != "").size()
	_settler_count.text = tr("%d von %d Siedlern%s. Lebensstil: %s. Spaltenkopf antippen sortiert. Auslastung: Anteil der eigenen Arbeit am Tag, hoch heißt, mehr Leute für diese Arbeit lohnen sich. Satt zeigt, wie voll der Magen ist; rot heißt Hunger oder krank.") % [
		list.size(), pool.size(), (tr(", %d krank") % sick_n) if sick_n > 0 else "", stage[0]]
	if list.is_empty():
		_settler_list.add_child(UiTheme.label(tr("Niemand passt zu dieser Auswahl.") if not pool.is_empty() else tr("Auf dieser Insel lebt niemand."), 14))
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
		nb.tooltip_text = tr("Auf der Karte zeigen")
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
			ob.tooltip_text = tr("Beruf wählen")
			ob.item_selected.connect(func(i):
				sref.set_job(ids[i])
				Game.player_action.emit("job", ids[i]))
			h.add_child(ob)
		else:
			var kl := UiTheme.label(tr("Kind"), 14, DIM)
			kl.custom_minimum_size.x = jw
			h.add_child(kl)
		# Auslastung: Anteil der eigenen Arbeit an der Tageszeit
		var bz := VBoxContainer.new()
		bz.custom_minimum_size.x = SETTLER_COLS[4][3] if narrow else SETTLER_COLS[4][2]
		bz.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bz.add_theme_constant_override("separation", 1)
		bz.mouse_filter = Control.MOUSE_FILTER_PASS
		var bl := UiTheme.label("", 12)
		bl.mouse_filter = Control.MOUSE_FILTER_PASS
		bz.add_child(bl)
		var bbar := UiTheme.bar(Color("#5a9a4a"), 8)
		bbar.custom_minimum_size.x = 0
		bz.add_child(bbar)
		h.add_child(bz)
		# Saettigung: Balken mit Prozentzahl
		var sat := VBoxContainer.new()
		sat.custom_minimum_size.x = SETTLER_COLS[5][3] if narrow else SETTLER_COLS[5][2]
		sat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sat.add_theme_constant_override("separation", 1)
		var pl := UiTheme.label("", 12)
		sat.add_child(pl)
		var hb := UiTheme.bar(Color("#e0a040"), 8)
		hb.custom_minimum_size.x = 0
		sat.add_child(hb)
		h.add_child(sat)
		# Laune, rot bei Krankheit
		var md := VBoxContainer.new()
		md.custom_minimum_size.x = SETTLER_COLS[6][3] if narrow else SETTLER_COLS[6][2]
		md.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		md.add_theme_constant_override("separation", 1)
		var ml := UiTheme.label("", 12)
		ml.clip_text = true
		md.add_child(ml)
		var mbar := UiTheme.bar(Color("#e070a0"), 8)
		mbar.custom_minimum_size.x = 0
		md.add_child(mbar)
		h.add_child(md)
		var mfill: StyleBoxFlat = mbar.get_theme_stylebox("fill")
		var fill: StyleBoxFlat = hb.get_theme_stylebox("fill")
		var upd := func():
			if not is_instance_valid(sref) or not is_instance_valid(nb):
				return
			al.text = str(int(sref.age))
			if act:
				act.text = sref.activity
			var bp: int = sref.busy_percent() if sref.is_adult() else -1
			bbar.visible = bp >= 0
			bbar.value = max(bp, 0)
			bl.text = "%d%%" % bp if bp >= 0 else "–"
			if bp >= 0:
				var bd: Dictionary = sref.busy
				var tot: float = max(0.0001, float(bd.get("job", 0.0)) + float(bd.get("other", 0.0)) + float(bd.get("idle", 0.0)))
				bz.tooltip_text = tr("Eigene Arbeit %d %%, etwas anderes %d %%, nichts zu tun %d %% der Tageszeit (ohne Essen, Pausen und Krankheit).") % [
					bp, int(round(float(bd.get("other", 0.0)) / tot * 100.0)), int(round(float(bd.get("idle", 0.0)) / tot * 100.0))]
			else:
				bz.tooltip_text = tr("Noch nicht gemessen.") if sref.is_adult() else ""
			hb.value = sref.hunger
			var hungry: bool = sref.hunger < 30.0
			fill.bg_color = Color("#d04a3a") if hungry else Color("#e0a040")
			pl.text = "%d%%" % int(round(sref.hunger)) + (tr(" Hunger!") if hungry and not narrow else "")
			var m: SettlerMind = sref.mind
			mbar.value = m.mood
			mfill.bg_color = Color("#d04a3a") if m.sick != "" else Color("#e070a0")
			if m.sick != "":
				ml.text = tr("krank") if narrow else tr("krank: %s") % m.illness_name()
				ml.add_theme_color_override("font_color", Color("#c03a2a"))
			else:
				ml.text = "%d%%" % int(round(m.mood)) if narrow else m.mood_text()
				ml.remove_theme_color_override("font_color")
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
	var r := _popup_panel(tr("Menü"))
	_menu_panel = r[0]
	var v: VBoxContainer = r[1]
	var save := UiTheme.button(tr("Spiel speichern"), "haus", 44)
	save.pressed.connect(func():
		Game.save_game()
		toast(tr("Spiel gespeichert."), "haus")
		_menu_panel.visible = false)
	v.add_child(save)
	var sl := UiTheme.button(tr("Spielstände"), "kiste", 44)
	sl.pressed.connect(func(): _open_slots())
	v.add_child(sl)
	if OS.has_feature("web"):
		_update_btn = UiTheme.button(tr("Neueste Version laden"), "schnell", 44)
		_update_btn.tooltip_text = tr("Speichert und lädt die neueste Version des Spiels.")
		_update_btn.pressed.connect(func():
			toast(tr("Lade die neueste Version ..."), "haus")
			Game.load_newest_version())
		v.add_child(_update_btn)
	var help := UiTheme.button(tr("Spielanleitung"), "sonne", 44)
	help.pressed.connect(func(): _toggle(_help_panel))
	v.add_child(help)
	var nt := UiTheme.button(tr("Meldungen"), "glocke", 44)
	nt.pressed.connect(func(): _toggle(_notify_panel))
	v.add_child(nt)
	var ng := UiTheme.button(tr("Neues Spiel"), "abriss", 44)
	var armed := [false]
	ng.pressed.connect(func():
		if not armed[0]:
			armed[0] = true
			ng.text = tr("Wirklich? Alles geht verloren!")
			return
		new_game_requested.emit())
	_menu_panel.visibility_changed.connect(func():
		armed[0] = false
		ng.text = tr("Neues Spiel"))
	v.add_child(ng)
	v.add_child(_volume_row(tr("Musik"), "musik", Sound.music_volume, func(x): Sound.set_volumes(x, Sound.sfx_volume)))
	v.add_child(_volume_row(tr("Geräusche"), "glocke", Sound.sfx_volume, func(x):
		Sound.set_volumes(Sound.music_volume, x)
		Sound.play("klick")))
	if OS.has_feature("web") or OS.has_feature("mobile") or OS.has_feature("pc"):
		var fs := UiTheme.button(tr("Vollbild"), "vollbild", 44)
		fs.pressed.connect(func():
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			_menu_panel.visible = false)
		v.add_child(fs)
	v.add_child(_language_row())
	var info := UiTheme.label(tr("Das Spiel speichert automatisch."), 12)
	v.add_child(info)
	v.add_child(_version_label())


## Sprachwahl (Menue und Titelbild). Nach dem Wechsel startet das Spiel neu,
## der Spielstand wird vorher gespeichert.
func _language_row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := UiTheme.label("Sprache / Language", 15)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var ob := OptionButton.new()
	ob.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(140, 40)
	ob.add_theme_font_size_override("font_size", 15)
	ob.get_popup().add_theme_font_size_override("font_size", 16)
	var codes := Loc.LANGUAGES.keys()
	for c in codes:
		ob.add_item(Loc.LANGUAGES[c])
		if c == Loc.language:
			ob.select(ob.item_count - 1)
	ob.item_selected.connect(func(i):
		if codes[i] == Loc.language:
			return
		Loc.set_language(codes[i])
		if Game.world != null and not Game.is_over and not Sound.in_title:
			Game.save_game()
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.location.reload()")
		else:
			OS.set_restart_on_exit(true)
			get_tree().quit())
	h.add_child(ob)
	return h


## Fuenf Spielstaende: laden, hierhin speichern, neu beginnen, loeschen
func _build_slots_panel() -> void:
	var r := _popup_panel(tr("Spielstände"))
	_slots_panel = r[0]
	_slots_scroll = ScrollContainer.new()
	_slots_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	r[1].add_child(_slots_scroll)
	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 6)
	_slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_scroll.add_child(_slots_box)


func _open_slots() -> void:
	_toggle(_slots_panel)
	if _slots_panel.visible:
		_fill_slots()
		root.move_child(_slots_panel, -1)
		_layout.call_deferred()


func _fill_slots() -> void:
	for c in _slots_box.get_children():
		c.queue_free()
	var in_title := has_overlay()
	var vs := get_viewport().get_visible_rect().size
	_slots_box.custom_minimum_size.x = min(640.0, vs.x - 40.0)
	_slots_scroll.custom_minimum_size = Vector2(_slots_box.custom_minimum_size.x, clampf(vs.y - 230.0, 200.0, 620.0))
	_slots_panel.size = Vector2.ZERO
	var hint := UiTheme.label(tr("Das Spiel speichert automatisch in den aktiven Spielstand."), 13, DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_slots_box.add_child(hint)
	for n in range(1, Game.SLOTS + 1):
		var row := PanelContainer.new()
		# Breit: Text links, Knoepfe rechts; schmal: Knoepfe darunter
		var f: BoxContainer = HBoxContainer.new() if get_viewport().get_visible_rect().size.x >= 600.0 else VBoxContainer.new()
		f.add_theme_constant_override("separation", 8 if f is HBoxContainer else 4)
		row.add_child(f)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f.add_child(v)
		var active: bool = n == Game.slot
		var used := Game.slot_exists(n)
		var head := UiTheme.label(tr("Spielstand %d") % n + (tr(" (aktiv)") if active else ""), 15, Color("#7a4a28") if active else UiTheme.TEXT, true)
		v.add_child(head)
		var info := Game.slot_info(n)
		var il := UiTheme.label(info if info != "" else (tr("Gespeichertes Spiel") if used else tr("Leer")), 12, DIM)
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(il)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		f.add_child(h)
		var slot_n: int = n
		if active and not in_title:
			var sv := _slot_button(tr("Speichern"))
			sv.pressed.connect(func():
				Game.save_game()
				toast(tr("Spiel gespeichert."), "haus")
				_fill_slots())
			h.add_child(sv)
		if used and not (active and not in_title):
			var ld := _slot_button(tr("Laden") if not active else tr("Weiterspielen"))
			ld.pressed.connect(func():
				if active:
					_slots_panel.visible = false
					_overlay_clear()
					continue_requested.emit()
					return
				if not in_title:
					Game.save_game()
				Game.switch_slot(slot_n, "continue"))
			h.add_child(ld)
		if not active and not in_title:
			h.add_child(_slot_confirm_button(tr("Hier speichern"), used, func():
				Game.save_to_slot(slot_n)
				toast(tr("Gespeichert in Spielstand %d. Du spielst jetzt dort weiter.") % slot_n, "haus")
				_fill_slots()))
		h.add_child(_slot_confirm_button(tr("Neues Spiel"), used, func():
			if not in_title and not active:
				Game.save_game()
			if active:
				_slots_panel.visible = false
				_overlay_clear()
				new_game_requested.emit()
			else:
				Game.switch_slot(slot_n, "new")))
		if used and not active:
			h.add_child(_slot_confirm_button(tr("Löschen"), true, func():
				Game.delete_slot(slot_n)
				_fill_slots()))
		# Datei auf die Festplatte und zurueck
		var h2 := HBoxContainer.new()
		h2.add_theme_constant_override("separation", 6)
		if used:
			var ex := _slot_button(tr("Exportieren"))
			ex.tooltip_text = tr("Spielstand als Datei auf dem Gerät speichern")
			ex.pressed.connect(func(): _export_slot(slot_n))
			h2.add_child(ex)
		var im := _slot_confirm_button(tr("Importieren"), used, func(): _import_slot(slot_n))
		if OS.has_feature("web"):
			# Browser oeffnen die Dateiauswahl nur direkt beim Tippen: beim Druecken vorbereiten,
			# beim Loslassen (noch im Ereignis des Browsers) oeffnen
			im.button_down.connect(func():
				if not used or im.text == tr("Sicher?"):
					_arm_import(slot_n))
		im.tooltip_text = tr("Spielstand aus einer Datei in diesen Platz laden")
		h2.add_child(im)
		v.add_child(h2)
		_slots_box.add_child(row)


func _export_slot(n: int) -> void:
	var text := Game.slot_text(n)
	if text == "":
		return
	var fname := Game.slot_file_name(n)
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), fname, "application/json")
		toast(tr("Spielstand %d exportiert: %s") % [n, fname], "haus")
		return
	var fd := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	fd.current_file = fname
	fd.file_selected.connect(func(path):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(text)
			f.close()
			toast(tr("Spielstand %d exportiert: %s") % [n, path.get_file()], "haus"))
	fd.popup_centered_ratio(0.8)


func _import_slot(n: int) -> void:
	_import_slot_n = n
	if OS.has_feature("web"):
		# Falls das Loslassen schneller war als die Vorbereitung: jetzt oeffnen
		JavaScriptBridge.eval("if (window.inselPickPending) { window.inselPickPending(); }", true)
		return
	var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	fd.file_selected.connect(func(path): _imported(FileAccess.get_file_as_string(path)))
	fd.popup_centered_ratio(0.8)


## Bereitet die Dateiauswahl des Browsers vor: sie oeffnet beim naechsten Loslassen des Fingers
## oder der Maustaste, denn nur dort erlaubt der Browser sie. Der Text kommt per Rueckruf zurueck.
func _arm_import(n: int) -> void:
	_import_slot_n = n
	_import_cb = JavaScriptBridge.create_callback(func(args): _imported(str(args[0]) if args.size() > 0 else ""))
	JavaScriptBridge.get_interface("window").inselImport = _import_cb
	JavaScriptBridge.eval("""(function () {
		const open = function () {
			window.removeEventListener('pointerup', open, true);
			window.removeEventListener('touchend', open, true);
			window.inselPickPending = null;
			const i = document.createElement('input');
			i.type = 'file';
			i.accept = '.json,application/json,text/plain';
			i.style.position = 'fixed';
			i.style.left = '-1000px';
			document.body.appendChild(i);
			i.onchange = function () {
				const f = i.files && i.files[0];
				i.remove();
				if (!f) { return; }
				const r = new FileReader();
				r.onload = function () { window.inselImport(String(r.result)); };
				r.readAsText(f);
			};
			i.click();
		};
		window.inselPickPending = open;
		window.addEventListener('pointerup', open, true);
		window.addEventListener('touchend', open, true);
	})();""", true)


func _imported(text: String) -> void:
	var n := _import_slot_n
	var err := Game.import_slot(n, text)
	if err != "":
		toast(err, "abriss")
		return
	if n == Game.slot:
		# Der aktive Platz wurde ersetzt: neu laden, ohne das laufende Spiel darueber zu speichern
		Game.switch_slot(n, "continue")
		return
	toast(tr("Spielstand %d importiert. Mit Laden spielst du ihn.") % n, "haus")
	if _slots_panel.visible:
		_fill_slots()


func _file_dialog(mode: int) -> FileDialog:
	var fd := FileDialog.new()
	fd.file_mode = mode
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.json"])
	fd.use_native_dialog = true
	root.add_child(fd)
	fd.close_requested.connect(fd.queue_free)
	fd.file_selected.connect(func(_p): fd.queue_free.call_deferred())
	return fd


## Neue Version: Die Web-App liefert aus ihrem Offline-Speicher oft noch die alte Version. Darum
## fragt das Spiel beim Start und alle 10 Minuten version.txt vom Server ab (schreibt der Web-Build).
## Ist sie neuer: auf dem Titelbild sofort laden, im Spiel melden.
var _version_cb  # JavaScriptObject, muss leben bleiben
var _version_timer := 0.0


func _watch_updates() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.pwa_update_available.connect(_on_update_available)
	if JavaScriptBridge.pwa_needs_update():
		_on_update_available()
	_version_cb = JavaScriptBridge.create_callback(func(args): _on_server_version(str(args[0]) if args.size() > 0 else ""))
	JavaScriptBridge.get_interface("window").inselVersion = _version_cb
	_ask_server_version()


func _ask_server_version() -> void:
	_version_timer = 600.0
	JavaScriptBridge.eval("fetch('version.txt', { cache: 'no-store' }).then((r) => r.ok ? r.text() : '').then((t) => window.inselVersion(t.trim())).catch(() => {});", true)


func _on_server_version(v: String) -> void:
	var mine := str(ProjectSettings.get_setting("application/config/version", ""))
	# Nur eine Versionsnummer wie 1.0.43 zaehlt (keine Fehlerseite)
	if v == mine or v.length() > 20 or not v.replace(".", "").is_valid_int():
		return
	_on_update_available()


func _on_update_available() -> void:
	if _update_ready:
		return
	_update_ready = true
	if has_overlay() and Sound.in_title:
		Game.load_newest_version()
		return
	if _update_btn:
		_update_btn.text = tr("Neue Version laden!")
	toast(tr("Eine neue Version des Spiels ist da. Menü > Neue Version laden."), "sonne")


func _slot_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 36
	b.add_theme_font_size_override("font_size", 14)
	return b


## Knopf, der bei belegtem Platz erst nachfragt (zweimal tippen)
func _slot_confirm_button(text: String, ask: bool, action: Callable) -> Button:
	var b := _slot_button(text)
	var armed := [not ask]
	b.pressed.connect(func():
		if not armed[0]:
			armed[0] = true
			b.text = tr("Sicher?")
			return
		action.call())
	return b


## Meldungen nach Art ein- und ausschalten (gespeichert in user://settings.cfg)
func _build_notify_panel() -> void:
	var r := _popup_panel(tr("Meldungen"))
	_notify_panel = r[0]
	var v: VBoxContainer = r[1]
	var l := UiTheme.label(tr("Welche Meldungen sollen eingeblendet werden?"), 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 260
	v.add_child(l)
	var rows := [["goal_card", tr("Nächstes Ziel (oben links)"), Game.goal_card_on]]
	for c in Game.NOTIFY_CATS:
		if c in Game.KI_NOTIFY_CATS and not Society.enabled:
			continue
		rows.append([c, Game.NOTIFY_CATS[c], not Game.notify_off.get(c, false)])
	_notify_grid = GridContainer.new()
	_notify_grid.add_theme_constant_override("h_separation", 8)
	_notify_grid.add_theme_constant_override("v_separation", 4)
	v.add_child(_notify_grid)
	for row in rows:
		var cb := CheckBox.new()
		cb.text = row[1]
		cb.button_pressed = row[2]
		cb.focus_mode = Control.FOCUS_NONE
		cb.custom_minimum_size.y = 32
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.add_theme_font_size_override("font_size", 14)
		var cat: String = row[0]
		cb.toggled.connect(func(on):
			Game.set_notify(cat, on)
			Sound.play("klick"))
		_notify_grid.add_child(cb)


## Versionsnummer steht nur in project.godot (application/config/version).
static func version_text() -> String:
	var ver := str(ProjectSettings.get_setting("application/config/version", "?"))
	return Loc.t("Version %s%s") % [ver, (" KI" if Game.is_ki_build else "") + (Loc.t(" (Testversion)") if Game.is_test_build else "")]


func _version_label() -> Label:
	var l := UiTheme.label(version_text(), 12, Color("#6e5a50"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


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


const HELP_KI := """[b]KI-Version: Du bist der Herrscher[/b]
Jede Insel hat einen [b]Inselrat[/b], der etwa einmal am Tag tagt. Er wählt den Schwerpunkt (Nahrung sichern, Vorrat für den Winter, Wachsen, Bauen, Wissen, Schutz oder Seefahrt), verteilt die Arbeit, lässt bauen, wählt die Forschung (Hauptinsel) und handelt per Schiff mit anderen Inseln.
Der Rat rechnet aus, wie viele Siedler in jedem Beruf bis zur nächsten Sitzung wirklich etwas zu tun haben: Bauern nur für Felder, die gesät oder geerntet werden, Sammler nach dem, was nachwächst und ins Lager passt, Werkstätten nur mit Rohstoffen. Wer keinen Platz bekommt, hilft frei aus. Jeder Siedler macht, was der Rat ihm aufträgt. Wird das Lager voll, baut der Rat ein neues.
Der Rat führt eine Statistik, wie die Arbeiter beschäftigt waren (eigene Arbeit, anderes, untätig, geliefert). Hatte ein Beruf zu wenig zu tun, bekommt er beim nächsten Mal weniger Plätze. Was der Rat misst, schreibt er sich als Lehren auf (Rat > „Gelernt und Statistik“).
Die Bewohner eines Hauses halten zusammen, pflegen Kranke und schicken einen Sprecher in den Rat.
Unter [b]Rat[/b] machst du feste Vorgaben (Schwerpunkt, Arbeiter, Bauen, Forschen) und verschiebst Prioritäten. Vorgaben kosten Vertrauen und drücken die Laune. Dort stehen auch die Anliegen der Inseln (Feste, mehr Freizeit, Überstunden). Ohne Antwort entscheidet der Rat nach einem Tag selbst.
Du kannst weiter selbst bauen, forschen und Schiffe schicken. Gibst du einem Siedler einen Beruf, gilt dein Befehl einen Tag lang.

"""
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

[b]Charakter[/b]
Jeder Siedler ist anders: klug oder einfältig, robust oder kränklich, fleißig oder gemütlich, Frohnatur oder Griesgram. Dazu hat jeder Begabungen (im Infofenster mit + markiert): darin lernt er schneller. Kluge lernen und forschen schneller. Kinder erben einen Teil ihres Charakters von den Eltern und lernen in der Schule viel, vor allem in ihren Begabungen.

[b]Gesundheit[/b]
Siedler werden krank: Erkältung macht langsamer, bei Fieber und Ruhr liegen sie im Bett und können sterben. Kränkliche, Alte, Kinder, Hungrige, Frierende und wer draußen schläft erkranken leichter, Kranke stecken andere an. Vitamine aus Beeren, Äpfeln und Kokosnüssen schützen; wer lange keine bekommt, bekommt Skorbut. Heilkunde lässt Kranke schneller gesund werden.

[b]Laune und Arbeitskraft[/b]
Satt, gesund, abwechslungsreiches Essen und ein schönes Zuhause machen gute Laune, Hunger, Krankheit, Kälte und Trauer schlechte. Gut gelaunte Siedler arbeiten schneller und bekommen eher Kinder. Die Arbeitskraft im Infofenster zeigt, wie schnell ein Siedler gerade arbeitet.

[b]Freizeit[/b]
Am Anfang kennen die Siedler nur Arbeit. Je weiter deine Siedlung entwickelt ist (siehe Lebensstil in der Siedlerliste), desto mehr Freizeit wollen sie: am Feuer plaudern, am Strand spazieren, mit Kindern spielen oder lesen. Bekommen sie keine, sind sie überarbeitet und schlecht gelaunt. In einer Hungersnot arbeiten alle durch.

[b]Nahrung[/b]
Siedler essen am Lagerfeuer. Jede Speise sättigt unterschiedlich stark und bringt unterschiedlich viele Vitamine: Beeren, Äpfel und Kokosnüsse machen kaum satt, sind aber voller Vitamine. Brot, Räucherfisch und Fleisch machen lange satt, haben aber kaum Vitamine. Rohes Getreide sättigt schlecht, erst Mühle und Bäckerei machen daraus gutes Brot.
Wer hungert, arbeitet langsamer und verhungert schließlich. Wer zu wenig Vitamine bekommt, arbeitet ebenfalls langsamer, wird leichter krank und bekommt Skorbut. Sorge also für satt machende Speisen und für Obst. Im Fenster eines Siedlers siehst du seine Vitamine. Ist das Lager leer, essen Hungrige direkt am Strauch oder am Ufer. Sammelplätze sind schnell leer gepflückt und wachsen nur langsam nach.

[b]Nachwuchs[/b]
Kinder kommen nur zur Welt, wenn es freie Wohnplätze in Hütten gibt und genug Nahrung im Lager ist. In Holzhäusern kommen 40 % öfter Kinder zur Welt, in Steinhäusern 80 %. Kinder werden nach 3 Tagen erwachsen, mit einer Schule (Forschung Unterricht) doppelt so schnell. Niemand lebt ewig, also sorge rechtzeitig für Nachwuchs.

[b]Bauen[/b]
Wähle ein Gebäude und einen Bauplatz. Baumeister und freie Siedler bringen das Material und bauen es auf. Hütten und Holzhäuser lassen sich später im Infofenster ausbauen.

[b]Forschung[/b]
Im Entwicklungsbaum wählst du, was deine Siedler als Nächstes lernen. Forscher denken am Lagerfeuer nach, in Schreibstube und Bibliothek viel schneller. Jede Forschung schaltet neue Gebäude frei oder macht die Arbeit leichter. Acht Zeitalter mit sechzehn Stufen führen durch die Geschichte der Menschheit: Steinzeit, Antike, Mittelalter, Renaissance, Industrialisierung, Moderne, Informationszeitalter und Zukunft. Universität, Forschungslabor und KI-Zentrum forschen immer schneller. Spätere Zeitalter siehst du erst, wenn das vorige erreicht ist.

[b]Neue Zeitalter[/b]
Glas, Papier, Stahl, Maschinen, Strom und Elektronik entstehen in neuen Werkstätten. Kraftwerk, Solarpark und Fusionsreaktor liefern Strom, den Elektronikwerk und KI-Zentrum brauchen. Mietshäuser und Wohnblöcke bieten viel Wohnraum, Gewächshäuser tragen auch im Winter. Steht ein KI-Zentrum, verteilt die künstliche Intelligenz freie Siedler auf die Berufe, die gerade fehlen. Die Zukunftsstadt ist das Ziel aller Zeitalter.

[b]Werkstätten[/b]
Sägegrube, Mühle, Bäckerei, Ziegelei und Co. verwandeln Rohstoffe in bessere Waren. Köche arbeiten in Mühle, Bäckerei, Räucherei und Hühnerhof, Handwerker in den Werkstätten, Steinmetze in Steinbruch, Lehmgrube und Mine. Tippe oben auf die Vorräte, um alle Waren zu sehen.

[b]Lager[/b]
Jedes Lager hat Stauraum: das Lagerfeuer 200, ein Lagerhaus 400, ein Großes Lager 1000. Große Waren brauchen mehr Raum als kleine, ein Brett 3, Holz und Stein 2, Beeren 1. Tippe oben auf die Vorräte oder im Lager auf "Lager einstellen" und lege mit − und + fest, wie viel von jeder Ware gelagert wird. Diese Menge ist dann für die Ware reserviert. Waren auf "frei" teilen sich den restlichen Raum. Ist für eine Ware kein Platz mehr, sammeln die Siedler sie nicht mehr. Hast du zu viel von einer Ware, kannst du den Überschuss wegwerfen; er ist dann verloren.

[b]Abwechslung[/b]
Gibt es mindestens drei Sorten Nahrung im Lager, kommen öfter Kinder zur Welt.

[b]Seefahrt[/b]
Jede Insel hat ihr eigenes Lager. Waren kommen nur mit Schiffen auf eine andere Insel. Mit der Forschung Schiffsbau baust du am Ufer eine Werft; im Fenster der Werft wählst du das nächste Schiff. Ruderboote sind klein und landen an jedem Strand, Koggen tragen viel, Schnellsegler sind schnell, Galeonen riesig. Jedes Schiff braucht Seeleute (Beruf Seemann) und einen Liegeplatz in seinem Heimathafen: Werft 1, Anlegesteg 2, Hafen 2, Großer Hafen 3, Kais 1. Koggen und Schnellsegler laufen nur Inseln mit Hafen an, Galeonen nur Große Häfen. Holz-, Erz- und Proviantkai laden ihre Waren dreimal so schnell.

[b]Seekarte und Routen[/b]
Über den Knopf Inseln öffnest du die Seekarte. "Schiff hierher schicken" bringt Siedler und Waren zu einer Insel, "Neue Insel suchen" schickt ein Schiff auf Erkundung. Unter "Schiffe" legst du Routen fest: An jedem Halt lädt das Schiff die eingestellten Waren und lädt alles andere ab, dann fährt es weiter, immer wieder.

[b]Neue Inseln[/b]
Palmeninseln haben Kokosnüsse und viel Fisch, Waldinseln Pilze und Holz, Felseninseln Erz und Gold. Gold brauchst du für die höchsten Forschungen. Je weiter draußen, desto mehr wilde Tiere.

[b]Wilde Tiere[/b]
Wölfe, Wildschweine und Bären leben in Bauten und Höhlen. Siedler fliehen vor ihnen in Häuser, nachts sind Wölfe besonders gefährlich. Mit Waffenkunde werden Siedler zu Jägern und du kannst Wachtürme bauen. Jäger bringen Fleisch und Felle und räumen die Bauten aus, damit keine Tiere mehr nachkommen.

[b]Achtung[/b]
Stirbt auf einer Insel der letzte Siedler, ist diese Insel für immer verloren. Erst wenn alle Inseln verloren sind, ist das Spiel vorbei. Die Welt ist endlos: Es gibt immer noch eine Insel zu entdecken."""


func _build_help_panel() -> void:
	var r := _popup_panel(tr("Spielanleitung"))
	_help_panel = r[0]
	var v: VBoxContainer = r[1]
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = (tr(HELP_KI) + tr(HELP_TEXT)) if Society.enabled else tr(HELP_TEXT)
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
			int((Game.time_days - o.farm_time) * 20), str(o.occupants), o.paused, o.is_active(), o.prod_blocker()] + "|%d" % Seasons.season()
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
	var sex := tr("Frau") if s.sex == "f" else tr("Mann")
	if not s.is_adult():
		sex = tr("Mädchen") if s.sex == "f" else tr("Junge")
	_info_box.add_child(UiTheme.label(tr("%s, %d Jahre") % [sex, int(s.age)], 14))
	var act := UiTheme.label(s.activity, 14, Color("#6a4a30"))
	act.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(act)
	var m: SettlerMind = s.mind
	var ch := UiTheme.label("", 13)
	ch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tal := m.best_talents().map(func(k): return Data.skills[k].name)
	ch.text = tr("Charakter: %s") % m.character_text() + (tr("\nBegabt für: %s") % ", ".join(tal) if not tal.is_empty() else "")
	_info_box.add_child(ch)
	var ill := UiTheme.label("", 14, Color("#c03a2a"), true)
	ill.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(ill)
	var hb := _bar_row(tr("Sättigung"), s.hunger, Color("#e0a040"))
	var gb := _bar_row(tr("Gesundheit"), s.health, UiTheme.GOOD)
	var vb := _bar_row(tr("Vitamine"), m.vit, Color("#7ac040"))
	var mb := _bar_row(tr("Laune"), m.mood, Color("#e070a0"))
	var rb: ProgressBar = null
	if s.is_adult() and m.leisure_share() > 0.0:
		rb = _bar_row(tr("Erholung"), m.rest, Color("#60b0d0"))
	var wp := UiTheme.label("", 14, UiTheme.TEXT, true)
	_info_box.add_child(wp)
	var why := UiTheme.label("", 12, DIM)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(why)
	_updaters.append(func():
		act.text = s.activity
		hb.value = s.hunger
		gb.value = s.health
		vb.value = m.vit
		mb.value = m.mood
		if rb:
			rb.value = m.rest
		ill.visible = m.sick != ""
		ill.text = tr("Krank: %s%s") % [m.illness_name(), tr(" (muss liegen)") if m.needs_bed() else ""]
		wp.text = tr("Laune: %s · Arbeitskraft %d %%") % [m.mood_text(), int(round(m.work_power() * 100.0))] if s.is_adult() \
			else tr("Laune: %s") % m.mood_text()
		var rs: Array = m.reasons.duplicate()
		rs.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
		var lines := []
		for x in rs.slice(0, 4):
			lines.append("%s %s" % ["+" if x[1] > 0 else "−", x[0]])
		why.text = "\n".join(lines)
		why.visible = not lines.is_empty())
	var home = world.building_by_id(s.home_id)
	_info_box.add_child(UiTheme.label(tr("Zuhause: %s") % (home.def.name if home else tr("keins (schläft draußen)")), 13))
	if Society.enabled:
		var th := UiTheme.label("", 13, Color("#2a5a9a"))
		th.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(th)
		var upd := func():
			var hh: Dictionary = Society.household_of(s)
			var sp: String = tr(" Sprecher im Inselrat.") if not hh.is_empty() and hh.speaker == s else ""
			th.text = tr("Denkt: %s%s") % [Society.thoughts.get(s.id, tr("Überlegt noch, was zu tun ist.")), sp]
		upd.call()
		_updaters.append(upd)
	_info_box.add_child(UiTheme.label(tr("Eigenschaften"), 15, UiTheme.TEXT, true))
	var tdefs: Dictionary = Data.ppl("traits", {})
	for k in SettlerMind.TRAITS:
		var v := m.trait_value(k)
		_bar_row("%s %d" % [tdefs[k].name, int(round(v))], v * 10.0, Color("#b08ad8"))
	_info_box.add_child(UiTheme.label(tr("Fähigkeiten (+ = begabt)"), 15, UiTheme.TEXT, true))
	for sk in Data.skills:
		var lvl := int(s.skill_level(sk))
		var t := float(m.talents.get(sk, 1.0))
		var stars := " ++" if t >= 1.6 else (" +" if t >= 1.3 else "")
		_bar_row("%s %d%s" % [Data.skills[sk].name, lvl, stars], lvl * 10.0, Color("#5a8ad8"))
	if not s.is_adult():
		_info_box.add_child(UiTheme.label(tr("Kinder arbeiten noch nicht."), 13))
	else:
		_info_box.add_child(UiTheme.label(tr("Beruf"), 15, UiTheme.TEXT, true))
		if Society.enabled:
			var nl := UiTheme.label(tr("Die Siedler wählen ihre Arbeit selbst. Bestimmst du einen Beruf, gilt dein Befehl einen Tag lang."), 12, DIM)
			nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_info_box.add_child(nl)
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
				tip += tr("\nFähigkeit: %s (Stufe %d)") % [Data.skills[jd.skill].name, int(s.skill_level(jd.skill))]
			b.tooltip_text = tip
			var jid: String = j
			if not Data.job_unlocked(j):
				b.disabled = true
				b.tooltip_text = tip + tr("\nBenötigt Forschung: %s") % Data.techs.get(jd.requires, {}).get("name", "?")
			b.pressed.connect(func():
				s.set_job(jid)
				Society.order_job(s)
				Game.player_action.emit("job", jid)
				_rebuild_info())
			grid.add_child(b)
		_info_box.add_child(grid)
	var f := UiTheme.button(tr("Folgen"), "person", 34)
	f.toggle_mode = true
	f.button_pressed = _follow
	f.toggled.connect(func(on):
		_follow = on
		_info_sig = _info_signature())
	_info_box.add_child(f)


func _info_building(b: Building) -> void:
	_info_head(b.def.name if b.complete else tr("Baustelle: ") + b.def.name)
	var d := UiTheme.label(b.def.desc, 13)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(d)
	if not b.complete:
		for res in b.def.cost:
			var h := HBoxContainer.new()
			h.add_child(UiTheme.icon_rect(Data.icon(Data.resources[res].icon), 16))
			h.add_child(UiTheme.label("%s: %d / %d" % [Data.resource_name(res), int(b.delivered.get(res, 0)), int(b.def.cost[res])], 14))
			_info_box.add_child(h)
		_bar_row(tr("Fortschritt"), b.build_fraction() * 100.0, UiTheme.ACCENT)
		var builders := world.settlers.filter(func(s): return s.is_adult() and (s.job == "baumeister" or s.job == "frei"))
		if builders.is_empty():
			var w := UiTheme.label(tr("Niemand baut! Mache einen Siedler zum Baumeister."), 13, UiTheme.BAD)
			w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_info_box.add_child(w)
	else:
		if b.housing() > 0:
			var names := b.residents().map(func(s): return s.display_name)
			_info_box.add_child(UiTheme.label(tr("Bewohner: %d / %d") % [names.size(), b.housing()], 14))
			var bb := float(b.def.get("birth_bonus", 1.0))
			if bb > 1.0:
				_info_box.add_child(UiTheme.label(tr("Kinder: %d %% öfter als in der Hütte") % roundi((bb - 1.0) * 100.0), 13, UiTheme.GOOD))
			if not names.is_empty():
				var l := UiTheme.label(", ".join(names), 13)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_info_box.add_child(l)
		if b.def.has("school"):
			var sl := UiTheme.label("", 14)
			_info_box.add_child(sl)
			var upd := func():
				var n := world.settlers.filter(func(s): return not s.is_adult() and world.school_of(s) == b).size()
				sl.text = tr("Schulkinder: %d / %d") % [n, int(b.def.school.get("slots", 8))]
			upd.call()
			_updaters.append(upd)
		if b.def.get("storage", 0) > 0:
			_info_box.add_child(UiTheme.label(tr("Stauraum dieses Lagers: %d") % Game.building_volume(b.def), 14))
			var tot := UiTheme.label(tr("Alle Lager dieser Insel: %d von %d belegt") % [Game.used_volume(), Game.storage_volume()], 13)
			tot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_info_box.add_child(tot)
			var sb := UiTheme.button(tr("Lager einstellen"), "kiste", 36)
			sb.pressed.connect(func():
				_refresh_stock(true)
				_toggle(_stock_panel))
			_info_box.add_child(sb)
		if b.def.has("farm"):
			var st := {"fallow": tr("Wartet auf den Bauern"), "growing": tr("Wächst"), "ripe": tr("Erntereif!")}
			if b.farm_state == "fallow" and not Seasons.can_sow(b.type):
				st.fallow = tr("Ruht bis zum Frühling (Aussaat nur im Frühling und Sommer)")
			var fl := UiTheme.label(st.get(b.farm_state, ""), 14)
			fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_info_box.add_child(fl)
			if b.farm_state == "growing" and Seasons.growth(b.type) <= 0.0:
				_info_box.add_child(UiTheme.label(tr("Im Winter wächst nichts."), 13, UiTheme.BAD))
			if b.farm_state == "growing":
				var frac: float = (Game.time_days - b.farm_time) / b.grow_days()
				_bar_row(tr("Wachstum"), frac * 100.0, UiTheme.GOOD)
			if not world.settlers.any(func(s): return s.job == "bauer"):
				var w := UiTheme.label(tr("Ohne Bauern wird das Feld nur selten bestellt."), 13, UiTheme.BAD)
				w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_info_box.add_child(w)
	if b.complete and b.def.get("ships", false):
		_info_shipyard(b)
	if b.complete and b.def.has("harbor"):
		_info_harbor(b)
	if b.complete and b.def.has("production"):
		_info_production(b)
	if b.complete and b.def.has("research"):
		_info_research(b)
	if b.def.has("upgrade"):
		_info_upgrade(b)
	var mv := UiTheme.button(tr("Verschieben"), "hammer", 36)
	mv.tooltip_text = tr("Stellt das Gebäude an einen anderen Platz. Vorräte, Bewohner und Baufortschritt ziehen mit.")
	mv.pressed.connect(func(): world.start_move(b))
	_info_box.add_child(mv)
	if b.type != "lagerfeuer":
		var dm := UiTheme.button(tr("Abreißen") if not _demolish_armed else tr("Wirklich abreißen?"), "abriss", 36)
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


## Werft: welches Schiff als naechstes gebaut wird.
func _info_shipyard(b: Building) -> void:
	_info_box.add_child(UiTheme.label(tr("Nächstes Schiff"), 15, UiTheme.TEXT, true))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	for t in Data.ships:
		var sd: Dictionary = Data.ships[t]
		if not Game.is_researched(sd.get("requires", "")):
			continue
		var bt := UiTheme.button(sd.name, sd.get("icon", "boot"), 34)
		bt.toggle_mode = true
		bt.button_pressed = b.ship_choice == t
		bt.tooltip_text = tr("%s\nLaderaum %d, %d Fahrgäste, Besatzung %d, Tempo x%.1f") % [sd.desc, int(sd.cargo), int(sd.passengers), int(sd.crew), float(sd.speed)]
		var tt: String = t
		bt.pressed.connect(func():
			b.ship_choice = tt
			_rebuild_info())
		flow.add_child(bt)
	_info_box.add_child(flow)
	var sd: Dictionary = Data.ships.get(b.ship_choice, {})
	var l := UiTheme.label(tr("%s: Laderaum %d, %d Fahrgäste, %d Seeleute, Tempo x%.1f. %s") % [sd.get("name", ""), int(sd.get("cargo", 0)),
		int(sd.get("passengers", 0)), int(sd.get("crew", 1)), float(sd.get("speed", 1.0)), sd.get("desc", "")], 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(l)


## Hafen, Steg, Kai: Liegeplaetze und Schiffe der Insel.
func _info_harbor(b: Building) -> void:
	var h: Dictionary = b.def.harbor
	var sizes := {1: tr("klein"), 2: tr("mittel"), 3: tr("groß")}
	var bl := []
	for x in h.get("berths", []):
		bl.append(sizes.get(int(x), "?"))
	_info_box.add_child(UiTheme.label(tr("Liegeplätze hier: %s") % ", ".join(bl), 13))
	_info_box.add_child(UiTheme.label(tr("Ladetempo: %d je Stunde") % int(h.get("rate", 0)), 13))
	if h.has("goods"):
		var gl := UiTheme.label(tr("Schnell (%d je Stunde): %s") % [int(h.goods_rate), ", ".join(h.goods.map(func(g): return Data.resource_name(g)))], 12, UiTheme.GOOD)
		gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(gl)
	_info_box.add_child(UiTheme.label(tr("Insel: %s, %s") % [Sea.harbor_level_name(Sea.harbor_level(world)), Sea.berth_text(world)], 12))
	var sb := UiTheme.button(tr("Schiffe und Seekarte"), "anker", 36)
	sb.pressed.connect(func():
		Game.select(null)
		_sea_panel.open_ships()
		if not _sea_panel.visible:
			_toggle(_sea_panel))
	_info_box.add_child(sb)


func _info_production(b: Building) -> void:
	var p := b.prod_def()
	_info_box.add_child(UiTheme.label(tr("Herstellung"), 15, UiTheme.TEXT, true))
	_info_box.add_child(_recipe_row(p))
	var job_id: String = WORKER_JOB.get(p.get("job", ""), "")
	var job_name: String = Data.jobs.get(job_id, {}).get("name", "?")
	var status := ""
	var col := UiTheme.TEXT
	var block := b.prod_blocker()
	if b.paused:
		status = tr("Angehalten.")
		col = Color("#8a5a3a")
	elif b.is_active() or not b.occupants.is_empty():
		status = tr("In Betrieb.")
		col = UiTheme.GOOD
	elif block != "":
		status = block + "."
		col = UiTheme.BAD
	elif not world.settlers.any(func(s): return s.is_adult() and s.job == job_id):
		status = tr("Niemand arbeitet hier. Gib einem Siedler den Beruf %s.") % job_name
		col = UiTheme.BAD
	else:
		status = tr("Wartet auf Arbeiter (%s).") % job_name
	var st := UiTheme.label(status, 13, col)
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(st)
	var names := _names_of(b.occupants)
	if not names.is_empty():
		_info_box.add_child(UiTheme.label(tr("Arbeiter: ") + ", ".join(names), 13))
	var pb := UiTheme.button(tr("Weiterarbeiten") if b.paused else tr("Anhalten"), "play" if b.paused else "pause", 34)
	pb.pressed.connect(func():
		b.paused = not b.paused
		_rebuild_info())
	_info_box.add_child(pb)


func _info_research(b: Building) -> void:
	_info_box.add_child(UiTheme.label(tr("Forschung"), 15, UiTheme.TEXT, true))
	_info_box.add_child(UiTheme.label(tr("Tempo: x%.1f   Plätze: %d") % [float(b.research_def().get("factor", 1.0)), b.slots()], 13))
	var names := _names_of(b.occupants)
	_info_box.add_child(UiTheme.label(tr("Forscher hier: ") + (", ".join(names) if not names.is_empty() else tr("niemand")), 13))
	var cur: String = Game.research.current
	var l := UiTheme.label(tr("Aktuell: ") + (Data.techs[cur].name if cur != "" else tr("nichts ausgewählt")), 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(l)
	var open := UiTheme.button(tr("Forschung öffnen"), "wissen", 34)
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
		var l := UiTheme.label(tr("Ausbau: %s nach der Forschung %s.") % [td.name, Data.techs[td.requires].name], 13, Color("#8a5a3a"))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(l)
		return
	var ub := UiTheme.button(tr("Ausbauen: %s") % td.name, "hammer", 36)
	ub.tooltip_text = tr("Wird zur Baustelle. Bewohner und Forscher ziehen solange aus.")
	ub.pressed.connect(func(): world.upgrade_building(b))
	_info_box.add_child(ub)
	var h := HBoxContainer.new()
	h.add_child(UiTheme.label(tr("Kosten:"), 13))
	for res in td.cost:
		h.add_child(UiTheme.icon_rect(Data.res_icon(res), 14))
		h.add_child(UiTheme.label(str(int(td.cost[res])), 13, UiTheme.TEXT if Game.amount(res) >= int(td.cost[res]) else UiTheme.BAD))
	_info_box.add_child(h)
	if td.has("housing"):
		_info_box.add_child(UiTheme.label(tr("Platz für %d statt %d Siedler.") % [int(td.get("housing", 0)), int(b.def.get("housing", 0))], 12))
	if td.has("research"):
		var rd: Dictionary = td.research
		var cur := b.research_def()
		var l := UiTheme.label(tr("Forschungstempo x%.1f statt x%.1f, %d statt %d Forscher.") % [float(rd.factor), float(cur.get("factor", 1.0)),
			int(rd.slots), int(cur.get("slots", 1))], 12, UiTheme.GOOD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(l)
	if float(td.get("birth_bonus", 1.0)) > float(b.def.get("birth_bonus", 1.0)):
		_info_box.add_child(UiTheme.label(tr("Dort kommen mehr Kinder zur Welt."), 12, UiTheme.GOOD))


func _info_node(n: ResNode) -> void:
	_info_head(n.def.name)
	var res: String = n.def.yield
	var h := HBoxContainer.new()
	h.add_child(UiTheme.icon_rect(Data.icon(Data.resources[res].icon), 16))
	h.add_child(UiTheme.label("%s: %d / %d" % [Data.resource_name(res), n.amount, int(n.def.capacity)], 14))
	_info_box.add_child(h)
	if n.amount <= 0 and n.regrow_at >= 0.0:
		var left: float = (n.regrow_at - Game.time_days) * 24.0
		_info_box.add_child(UiTheme.label(tr("Wächst nach: noch %d Std.") % max(1, int(ceil(left))), 14))
	elif n.def.get("on_empty", "") == "remove":
		_info_box.add_child(UiTheme.label(tr("Wächst nicht nach."), 13))
	var who := {"baum": tr("Holzfäller"), "fels": tr("Steinmetz"), "busch": tr("Sammler"), "fischgrund": tr("Fischer"),
		"palme": tr("Sammler"), "pilzkreis": tr("Sammler"), "erzader": tr("Steinmetz"), "goldader": tr("Steinmetz"), "beute": tr("Jäger")}
	if n.def.has("spawns"):
		var an: Dictionary = Data.animals[n.def.spawns]
		var w = n.world
		var here: Array = w.animals.filter(func(a): return a.home == n.cell)
		var young := here.filter(func(a): return not a.is_adult()).size()
		var t := tr("Hier leben %d %s") % [here.size(), an.get("plural", an.name)]
		if young > 0:
			t += tr(", davon %d Jungtiere") % young
		t += tr(". Futter (%s) reicht für %d.") % [an.get("food_name", tr("Futter")), w.den_capacity(n)]
		var l := UiTheme.label(t, 13, UiTheme.BAD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(l)
		var l2 := UiTheme.label(tr("Im Frühling bekommt ein sattes Paar Junge, wenn das Futter reicht. Jäger lassen von jeder Art mindestens %d erwachsene Tiere auf der Insel übrig.") % int(Data.bal("hunt_min_keep", 2)), 12)
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(l2)
	else:
		_info_box.add_child(UiTheme.label(tr("Wird bearbeitet von: %s") % who.get(n.type, "?"), 13))
	if n.def.has("decay_days") and n.regrow_at >= 0.0:
		_info_box.add_child(UiTheme.label(tr("Verdirbt in %d Std.") % max(1, int(ceil((n.regrow_at - Game.time_days) * 24.0))), 13))


func _info_animal(a: Animal) -> void:
	_info_head(a.def.name if a.is_adult() else tr("Junges: %s") % a.def.name)
	var hb := _bar_row(tr("Kraft"), a.hp / a.max_hp() * 100.0, UiTheme.BAD)
	var fb := _bar_row(tr("Satt"), a.food * 100.0, UiTheme.GOOD)
	var st := UiTheme.label("", 14, Color("#6a4a30"))
	_info_box.add_child(st)
	var upd := func():
		if not is_instance_valid(a):
			return
		hb.value = a.hp / a.max_hp() * 100.0
		fb.value = a.food * 100.0
		st.text = a.state_text()
	upd.call()
	_updaters.append(upd)
	var t := tr("Gefährlich! Biss: %d Schaden, hungrig noch angriffslustiger. Siedler fliehen in Häuser. Jäger (Forschung Waffenkunde) und Wachtürme wehren die Tiere ab. Erlegt gibt es Fleisch und Felle.") % int(a.def.damage)
	if float(a.def.aggro) < 3.0:
		t = tr("Greift nur an, wenn man ihm zu nahe kommt. Biss: %d Schaden. Jäger erlegen es für Fleisch und Felle.") % int(a.def.damage)
	if not a.is_adult():
		t = tr("Ein Jungtier. Harmlos und wird nicht gejagt. Nach %d Tagen ist es erwachsen.") % int(ceil(float(a.def.get("adult_days", 2.0))))
	t += tr(" Frisst: %s.") % a.def.get("food_name", tr("Futter"))
	var l := UiTheme.label(t, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(l)


# ================================================================== Meldungen
func toast(text: String, icon_name: String = "", _cat: String = "") -> void:
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
	var t := UiTheme.label(tr("Insel-Siedler"), 40, Color("#7a4a28"), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := UiTheme.label(tr("Zwei Siedler. Eine Insel. Viele Generationen."), 15)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	if Game.is_ki_build:
		var kb := UiTheme.label(tr("KI-Version mit eigenem Spielstand: Jede Insel hat einen Rat,\nder die Arbeit verteilt, baut und forscht. Du bist der Herrscher.\nDein normales Spiel bleibt unverändert."), 14, Color("#2a5a9a"), true)
		kb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(kb)
	if Game.is_test_build:
		var tb := UiTheme.label(tr("Testversion mit eigenem Spielstand.\nDein normales Spiel bleibt unverändert."), 14, Color("#c03a2a"), true)
		tb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tb)
	if has_save:
		var cont := UiTheme.button(tr("Weiterspielen"), "play", 50)
		cont.pressed.connect(func():
			_overlay_clear()
			continue_requested.emit())
		v.add_child(cont)
	var ng := UiTheme.button(tr("Neues Spiel") if has_save else tr("Spiel starten"), "sonne", 50)
	var armed := [not has_save]
	ng.pressed.connect(func():
		if not armed[0]:
			armed[0] = true
			ng.text = tr("Spielstand überschreiben?")
			return
		_overlay_clear()
		new_game_requested.emit())
	v.add_child(ng)
	var sb := UiTheme.button(tr("Spielstände (aktiv: %d)") % Game.slot, "kiste", 40)
	sb.pressed.connect(func(): _open_slots())
	v.add_child(sb)
	var hb := UiTheme.button(tr("Spielanleitung"), "menu", 40)
	hb.pressed.connect(func(): _toggle(_help_panel))
	v.add_child(hb)
	v.add_child(_language_row())
	v.add_child(_version_label())
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
	var t := UiTheme.label(tr("Alle Inseln sind verloren") if Sea.islands.size() > 1 else tr("Die Insel ist verloren"), 30, UiTheme.BAD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UiTheme.label(tr("Deine Siedlung hielt %d Tage durch.\nGeburten: %d   Höchste Bevölkerung: %d   Entdeckte Inseln: %d") % [
		Game.day(), int(Game.stats.births), int(Game.stats.max_pop), Sea.islands.size() - 1], 15)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var ng := UiTheme.button(tr("Neue Insel besiedeln"), "sonne", 50)
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
				var sb: StyleBox = root.theme.get_stylebox(st, tr("Button")).duplicate()
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
	var sp: Control = root.get_node(tr("SpeedPanel"))
	sp.reset_size()
	var top_h := 50.0
	# Schmal: Jahreszeit nur als Symbol
	_season_label.visible = not (portrait or vs.x < 760)
	if _food_short != (vs.x < 480):
		_food_short = vs.x < 480
		_refresh_top()
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
	_notify_grid.columns = 2 if vs.x >= 640 else 1
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
	if _version_cb != null and not _update_ready:
		_version_timer -= delta / max(Engine.time_scale, 0.001)
		if _version_timer <= 0.0:
			_ask_server_version()
	_day_label.text = tr("Tag %d  %s") % [Game.day(), Game.clock_text()]
	_day_icon.texture = Data.icon("mond" if Game.is_night() else "sonne")
	_season_icon.texture = Seasons.icon()
	_season_label.text = Seasons.short_text()
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
