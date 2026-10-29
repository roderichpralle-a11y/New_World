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
var _research_writing: Array = []  # Forschung braucht Schriften: [Verbrauch, rote Zeile]
var _exam_box: Control  # Pruefung beim Zeitalterwechsel (ExamView), im Forschungsfenster
var _score_panel: PanelContainer  # Menue > Wertung (ExamView)
var _quest_panel: PanelContainer  # Auftraege (QuestView, Teil D)
var _research_btn: Button
var _stock_panel: PanelContainer
var _stock_grid: GridContainer
var _settler_panel: PanelContainer
var _settler_list: VBoxContainer
var _settler_list_free: VBoxContainer
var _settler_scroll_free: ScrollContainer
var _settler_head_job: Label
var _settler_head_row: HBoxContainer
var _settler_head_free: Label
var _menu_panel: PanelContainer
var _help_panel: PanelContainer
var _notify_panel: PanelContainer
var _history_panel: PanelContainer  # Nachrichten: alle Meldungen zum Nachlesen (josh 2026-10-29)
var _history_box: VBoxContainer
var _history_ft: Dictionary
var _history_muted_only := false
var _slots_panel: PanelContainer
var _slots_box: VBoxContainer
var _slots_scroll: ScrollContainer
var _import_cb  # JavaScriptObject: Rueckruf fuer die Dateiauswahl im Browser (muss leben bleiben)
var _import_slot_n := 0
var _update_btn: Button
var _notify_grid: GridContainer
var _info_panel: PanelContainer
var _info_box: VBoxContainer
var _place_bar: PanelContainer
var _place_ok: Button
var _place_label: Label
var _toasts: VBoxContainer
var _toasts_top: VBoxContainer  # über allen Fenstern
var _toasts_top_y := 56.0  # Platz der Meldungen ohne Sprechblase (von _layout gesetzt)
var _overlay: Control
var _info_timer: float = 0.0
var _info_obj = null
var _demolish_armed: bool = false
var _follow: bool = false
var _info_sig: String = ""
var _updaters: Array = []
var _research_tick: float = 0.0
var _sea_panel: SeaPanel
var _trade_panel: TradePanel  # fremde Händler (Merchant)
var top_alerts: TopAlerts  # Hinweis-Knöpfe neben der Geschwindigkeit
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
	_build_notify_panel()
	_build_history_panel()
	_build_slots_panel()
	_score_panel = ExamView.build_score_panel(self)
	_quest_panel = QuestView.build_panel(self)
	_build_admin_panel()
	_build_info_panel()
	_sea_panel = SeaPanel.new()
	root.add_child(_sea_panel)
	_sea_panel.setup(self)
	_trade_panel = TradePanel.new()
	root.add_child(_trade_panel)
	_trade_panel.setup(self)
	_build_place_bar()
	_toasts = VBoxContainer.new()
	_toasts.position = Vector2(8, 56)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 3)
	root.add_child(_toasts)
	root.move_child(_toasts, goal_card.get_index() + 1)  # Meldungen unter offenen Fenstern, nicht über Knöpfen und Titeln
	# Antworten auf einen Tipp (z. B. "Dafür fehlt noch") stehen über den Fenstern, sonst sieht man sie nicht
	_toasts_top = VBoxContainer.new()
	_toasts_top.position = Vector2(8, 56)
	_toasts_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts_top.add_theme_constant_override("separation", 3)
	root.add_child(_toasts_top)
	get_viewport().size_changed.connect(_refresh_top)
	Game.stock_changed.connect(_refresh_top)
	Game.stock_changed.connect(_on_stock_for_build)
	Game.stock_changed.connect(_update_costs)
	Game.stock_changed.connect(func():
		if user_just_acted():
			_refresh_stock())
	Game.research_changed.connect(_on_research_changed)
	Game.population_changed.connect(_refresh_top)
	Game.population_changed.connect(func():
		if user_just_acted():
			_refresh_settler_list())
	Game.notified.connect(func(t, i = "", c = ""): toast(t, i, c, false))  # Meldungen aus dem Spiel: unter den Fenstern
	Game.selection_changed.connect(_on_selection)
	Game.speed_changed.connect(_on_speed)
	Game.game_over.connect(_show_game_over)
	world.placement_changed.connect(_on_placement)
	Sea.islands_changed.connect(_update_sea_button)
	Steward.offer.connect(func(k): _offers.append(k))  # Verwalter-Steuerung anbieten
	get_viewport().size_changed.connect(_layout)
	_update_sea_button()
	_update_admin_button()
	_refresh_top()
	goal_card.attach_pointer(root)
	AdminInfo.attach(self)  # Vorschläge des Verwalters (scripts/ui/admin_info.gd)
	FestVideo.attach(self)  # Fest-Video bei jedem Fest (scripts/ui/fest_video.gd)
	ProtestVideo.attach(self)  # Protest-Video bei Protest gegen Überstunden (scripts/ui/protest_video.gd)
	_layout()


# ================================================================== Oberleiste
func _chip(icon_name: String) -> Array:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.add_child(UiTheme.icon_rect(Data.icon(icon_name), 18))
	var l := UiTheme.label("0", 16)
	h.add_child(l)
	return [h, l]


var _island_room: float = 160.0  # Platz für den Inselnamen in der Statuszeile (aus _layout)
var top_bar: PanelContainer  # Statuszeile oben (Zeiger der Einführung)
var speed_bar: PanelContainer  # Geschwindigkeit oben rechts
var _head_btns: Array = []  # Ziele, Aufträge, Nachrichten neben der Geschwindigkeit
var menu_btn: Button
var settler_btn: Button


func _build_topbar() -> void:
	var p := PanelContainer.new()
	top_bar = p
	p.position = Vector2(6, 6)
	p.tooltip_text = tr("Tippen: alle Vorräte anzeigen")
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_refresh_stock(true)
			_toggle(_stock_panel)
			if _stock_panel.visible:
				Game.player_action.emit("panel", "lager"))
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
			Game.notify(tr("Jahr %d, %s Tag %d von %d. %s") % [Seasons.year(), Seasons.season_title(),
				Seasons.day_in_season(), int(Seasons.season_days()), Seasons.effects_text()] + Seasons.climate_text(), ""))
	_season_icon = UiTheme.icon_rect(Seasons.icon(), 18)
	_season_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	sc.add_child(_season_icon)
	_season_label = UiTheme.label("", 16)
	_season_label.mouse_filter = Control.MOUSE_FILTER_PASS
	sc.add_child(_season_label)
	sc.add_child(ClimateBadge.new())  # Klima: heißer Sommer / Wintervorhersage (auch schmal sichtbar)
	h.add_child(sc)
	_island_label = UiTheme.label("", 14, Color("#7a4a28"), true)
	_island_label.clip_text = true  # feste Breite, langer Name im Tooltip
	_island_label.mouse_filter = Control.MOUSE_FILTER_STOP  # Tipp öffnet das Fenster Inseln (josh 2026-10-20)
	_island_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_island_label.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_open_sea()
			_island_label.accept_event())
	_island_label.visible = false
	h.add_child(_island_label)
	_food_label.get_parent().set_meta("is_food", true)

	var sp := PanelContainer.new()
	sp.name = tr("SpeedPanel")
	speed_bar = sp
	root.add_child(sp)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 4)
	sp.add_child(sh)
	# Kleine Knöpfe Ziele, Aufträge, Nachrichten (josh 2026-10-29)
	for k in [["ziel", tr("Ziele: die Zielkarte zeigen oder ausblenden"), _toggle_goals],
			["haken", tr("Aufträge"), func(): _toggle(_quest_panel)],
			["glocke", tr("Nachrichten: alle Meldungen zum Nachlesen"), func(): _toggle(_history_panel)]]:
		var hb := UiTheme.button("", k[0], 34)
		hb.tooltip_text = k[1]
		hb.pressed.connect(k[2])
		sh.add_child(hb)
		_head_btns.append(hb)
	var gap := Control.new()
	gap.custom_minimum_size.x = 4
	sh.add_child(gap)
	for i in 4:  # Pause, normal, schnell (3x), sehr schnell (8x, josh 2026-10-11)
		var icon_name: String = ["pause", "play", "schnell", "sehr_schnell"][i]
		var b := UiTheme.button("", icon_name, 34)
		b.toggle_mode = true
		b.tooltip_text = [tr("Pause"), tr("Normal"), tr("Schnell (3x)"), tr("Sehr schnell (8x)")][i]
		var spd: int = [0, 1, 3, 8][i]
		b.pressed.connect(func(): Game.set_speed(spd))
		sh.add_child(b)
		_speed_btns.append([b, spd])
	_on_speed(Game.speed)
	top_alerts = TopAlerts.new()
	root.add_child(top_alerts)
	top_alerts.add_child(EventChip.new(self))  # angekündigte Ereignisse (Events)


## Statuszeile mit fester Größe (josh 2026-10-20): jede Zahl bekommt die Breite ihres längsten möglichen
## Textes, das Klima-Symbol behält seinen Platz. So ändert sich die Leiste nicht, wenn Zahlen wachsen.
func _fix_top_widths(season_title: bool) -> void:
	var fit := func(l: Label, samples: Array) -> void:
		var f: Font = l.get_theme_font("font")
		var fs: int = l.get_theme_font_size("font_size")
		var w := 0.0
		for t in samples:
			w = maxf(w, f.get_string_size(str(t), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		l.custom_minimum_size.x = ceilf(w) + 1.0
	# Schmal (Handy hoch): Platz für die üblichen Größen, erst darüber wächst die Leiste
	for id in _res_labels:
		fit.call(_res_labels[id], ["999"] if _food_short else ["9999"])
	fit.call(_food_label, ["999 (%s)" % (tr("%dT") % 9)] if _food_short else ["9999 (%s)" % (tr("%d Tage") % 99)])
	fit.call(_pop_label, ["99/99"] if _food_short else ["999/999"])
	fit.call(_day_label, [tr("Tag %d") % 99] if _food_short else [tr("Tag %d  %s") % [999, "23:59"]])
	var seasons := []
	for i in 4:
		seasons.append(Seasons.season_name(i) + " 3/3")
	if season_title:
		for k in [["w", "winters"], ["s", "summers"]]:
			for t in Seasons.cfg.get(k[1], {}):
				seasons.append(Seasons.type_name(k[0], t) + " 3/3")
	fit.call(_season_label, seasons)


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
		_island_label.visible = Sea.worlds.size() > 1 and vs.x >= 520 and _island_room >= 50.0
		_island_label.text = Sea.island_name(world) if world and is_instance_valid(world) else ""
		_island_label.tooltip_text = _island_label.text


func _on_speed(s: int) -> void:
	for e in _speed_btns:
		e[0].set_pressed_no_signal(e[1] == s)


# ================================================================== Unterleiste
## Knöpfe der Leiste unten (josh 2026-10-19): Bilder statt Text aus assets/sprites/menu_icons.png
## (tools/gen_art_menu.py, je 20x20, doppelt groß gezeigt); der Name steht im Tooltip.
const MENU_ICONS := ["bauen", "forschung", "siedler", "inseln", "menue", "verwalter"]
var MENU_TEX: Texture2D = Data.hd("menu_icons")
var _admin_btn: Button
var _admin_badge: Label
var _admin_panel: PanelContainer  # Fenster Verwalter (AdminInfo.fill_window)
var _admin_box: VBoxContainer
var _admin_ft: Dictionary


func _menu_button(icon: String, tip: String) -> Button:
	var b := UiTheme.button("", "", 48)
	var at := AtlasTexture.new()
	at.atlas = MENU_TEX
	at.region = Rect2(20 * MENU_ICONS.find(icon), 0, 20, 20)
	b.icon = at
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 40)
	b.custom_minimum_size = Vector2(54, 50)
	b.tooltip_text = tip
	return b


func _build_bottom() -> void:
	var p := PanelContainer.new()
	p.name = tr("BottomPanel")
	root.add_child(p)
	_bottom = HBoxContainer.new()
	_bottom.add_theme_constant_override("separation", 6)
	p.add_child(_bottom)
	var bb := _menu_button("bauen", tr("Bauen"))
	bb.pressed.connect(func():
		Game.player_action.emit("panel", "bauen")
		if not _build_panel.visible:
			_fill_build_list()  # neue Zahlen beim Öffnen
		_toggle(_build_panel))
	_bottom.add_child(bb)
	_build_btn = bb
	_research_btn = _menu_button("forschung", tr("Forschung"))
	_research_btn.pressed.connect(func():
		Game.player_action.emit("panel", "forschung")
		_fill_research_list()
		_toggle(_research_panel))
	_bottom.add_child(_research_btn)
	var sb := _menu_button("siedler", tr("Siedler"))
	settler_btn = sb
	sb.pressed.connect(func():
		Game.player_action.emit("panel", "siedler")
		_toggle(_settler_panel)
		_refresh_settler_list())
	_bottom.add_child(sb)
	_sea_btn = _menu_button("inseln", tr("Inseln"))
	_sea_btn.pressed.connect(_open_sea)
	_bottom.add_child(_sea_btn)
	_admin_btn = _menu_button("verwalter", tr("Verwalter"))
	_admin_btn.pressed.connect(_open_admin)
	_admin_btn.visible = false
	_bottom.add_child(_admin_btn)
	Powers.changed.connect(_update_admin_badge)
	Admin.changed.connect(_update_admin_badge)
	var mb := _menu_button("menue", tr("Menü"))
	mb.pressed.connect(func():
		Game.player_action.emit("panel", "menue")
		_toggle(_menu_panel))
	_bottom.add_child(mb)
	menu_btn = mb


## Verwalter-Knopf (josh 2026-10-19): ab der Forschung der Verwaltung; öffnet das Fenster der Verwaltung.
func _update_admin_button() -> void:
	if _admin_btn == null:
		return
	var show := Game.is_unlocked("verwaltung") or Steward.unlocked()
	if _admin_btn.visible != show:
		_admin_btn.visible = show
		_layout()
	_update_admin_badge()


## Punkt am Verwalter-Knopf (josh 2026-10-29): Zahl offener Vorschläge, „!“ bei einer neuen Ausbaustufe.
func _update_admin_badge() -> void:
	if _admin_btn == null:
		return
	if _admin_badge == null:
		_admin_badge = Label.new()
		_admin_badge.add_theme_font_size_override("font_size", 12)
		_admin_badge.add_theme_color_override("font_color", Color.WHITE)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#c0392b")
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		_admin_badge.add_theme_stylebox_override("normal", sb)
		_admin_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_admin_badge.position = Vector2(34, -2)
		_admin_btn.add_child(_admin_badge)
	var n := Powers.badge()
	_admin_badge.text = str(n) if n > 0 else ("!" if Powers.new_level() else "")
	_admin_badge.visible = _admin_badge.text != ""


## Fenster Verwalter (josh 2026-10-20): wie alle Fenster, mit Reitern Verwalter, Schichten,
## Nachtschicht, Überstunden und Statistik (AdminInfo.fill_window).
func _open_admin() -> void:
	var o = Admin.office()
	if o != null and o.world != world:
		Sea.switch_to(int(o.world.island_id))
	if not _admin_panel.visible:
		_toggle(_admin_panel)
	else:
		_fill_admin()
	_layout()


func _build_admin_panel() -> void:
	var r := _popup_panel(tr("Verwalter"), "menu:verwalter", "verwalter")
	_admin_panel = r[0]
	var v: VBoxContainer = r[1]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(330, 300)
	v.add_child(scroll)
	var m := MarginContainer.new()  # Abstand rechts für die Bildlaufleiste
	m.add_theme_constant_override("margin_right", 24)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(m)
	_admin_box = VBoxContainer.new()
	_admin_box.add_theme_constant_override("separation", 6)
	_admin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(_admin_box)
	_admin_ft = Win.footer(v)
	_admin_panel.visibility_changed.connect(func():
		if _admin_panel.visible:
			_fill_admin())


func _fill_admin() -> void:
	for c in _admin_box.get_children():
		_admin_box.remove_child(c)
		c.queue_free()
	AdminInfo.fill_window(self, Admin.office(), _admin_box, _fill_admin, _admin_ft)


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
	_update_admin_button()
	if _sea_panel.visible:
		_sea_panel.refresh()


## Ein Tipp außerhalb der Fenster (nicht auf die Leisten oben und unten, nicht aufs Infofenster)
## schließt alle offenen Fenster. Der Tipp zählt nur dafür und löst nichts auf der Karte aus.
## Offene Fenster aktualisieren sich nicht von selbst (josh 2026-10-19), nur kurz nach einem Tipp des Spielers,
## damit seine eigene Änderung sofort zu sehen ist. Neue Zahlen sonst beim nächsten Öffnen.
var _last_tap_ms := -100000


func user_just_acted() -> bool:
	return Time.get_ticks_msec() - _last_tap_ms < 1500


## Listen mit dem Finger oder gedrückter Maus ziehen (josh 2026-10-21: Statistik, Verwalter und Infofenster
## rollten am iPhone nicht). Ab drag_px Pixeln Bewegung rollt die Liste unter dem Finger mit; das Loslassen
## danach löst keinen Knopf aus. Der Stand wird absolut gesetzt, so rollt es nie doppelt, auch wenn Godot
## selbst mitrollt.
const DRAG_PX := 10.0
var _drag_sc: ScrollContainer = null
var _drag_from := Vector2.ZERO
var _drag_start := 0
var _dragging := false


func _drag_scroll(ev: InputEvent) -> bool:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_drag_sc = _scroll_at(ev.position)
			_drag_from = ev.position
			_drag_start = _drag_sc.scroll_vertical if _drag_sc else 0
			_dragging = false
			return false
		var was := _dragging
		_drag_sc = null
		_dragging = false
		return was
	if ev is InputEventMouseMotion and _drag_sc != null and is_instance_valid(_drag_sc) and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var dy: float = ev.position.y - _drag_from.y
		if not _dragging and absf(dy) >= DRAG_PX:
			_dragging = true
		if _dragging:
			_drag_sc.scroll_vertical = _drag_start - int(dy)
			return true
	return false


## Die innerste rollbare Liste unter dem Punkt in einem offenen Fenster oder im Infofenster, sonst null.
func _scroll_at(pos: Vector2) -> ScrollContainer:
	var best: ScrollContainer = null
	for pnl in _panels() + [_info_panel]:
		if pnl != null and pnl.visible and pnl.get_global_rect().has_point(pos):
			best = _inner_scroll(pnl, pos, best)
	return best


func _inner_scroll(n: Node, pos: Vector2, best: ScrollContainer) -> ScrollContainer:
	for c in n.get_children():
		if not (c is Control) or not c.is_visible_in_tree() or not c.get_global_rect().has_point(pos):
			continue
		if c is ScrollContainer and c.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED \
				and c.get_child_count() > 0 and c.get_child(0).get_combined_minimum_size().y > c.size.y + 1.0:
			best = c
		best = _inner_scroll(c, pos, best)
	return best


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		_last_tap_ms = Time.get_ticks_msec()
	if _drag_scroll(ev):
		get_viewport().set_input_as_handled()
		return
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	if has_overlay() or _panels().all(func(pn): return pn == null or not pn.visible):
		return
	var pos: Vector2 = ev.position
	if pos.y < _top_h:
		return
	var keep: Array = _panels() + [_bottom.get_parent(), _info_panel, goal_card, _menu_help]
	for c in keep:
		if c != null and c.visible and c.get_global_rect().has_point(pos):
			return
	for pnl in _panels():
		if pnl != null:
			pnl.visible = false
	get_viewport().set_input_as_handled()


func _toggle(panel: Control) -> void:
	var show := not panel.visible
	for pnl in _panels():
		pnl.visible = false
	panel.visible = show
	if show and panel != _help_panel:
		_info_panel.visible = false
		Game.select(null)


func _panels() -> Array:
	return [_build_panel, _research_panel, _stock_panel, _settler_panel, _menu_panel, _help_panel, _notify_panel, _slots_panel, _sea_panel, _score_panel, _quest_panel, _trade_panel, _admin_panel, _history_panel]


## Gemeinsamer Kopf aller Fenster (josh 2026-10-16): Symbol, Titel = Name des Knopfes, rechts das X.
## Ein Tipp neben das Fenster schließt es (_input).
func _popup_panel(title: String, icon: String = "", help_key: String = "") -> Array:
	var p := PanelContainer.new()
	p.visible = false
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	if icon != "":
		var tex: Texture2D = null if icon.begins_with("menu:") else Data.icon(icon)
		if icon.begins_with("menu:"):  # Bild des Knopfes unten (MENU_TEX)
			var at := AtlasTexture.new()
			at.atlas = MENU_TEX
			at.region = Rect2(20 * MENU_ICONS.find(icon.substr(5)), 0, 20, 20)
			tex = at
		var ic := UiTheme.icon_rect(tex, 28)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(ic)
	var t := UiTheme.label(title, 20, UiTheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if help_key != "":
		head.add_child(help_button(help_key, title))
	var x := UiTheme.button("", "abriss", 36)
	x.tooltip_text = tr("Schließen")
	x.pressed.connect(func(): p.visible = false)
	head.add_child(x)
	v.add_child(head)
	return [p, v]


## Fragezeichen oben im Fenster: öffnet die Hilfe zu genau diesem Fenster (josh 2026-10-16).
func help_button(key: String, title: String) -> Button:
	var b := UiTheme.button("?", "", 36)
	b.custom_minimum_size.x = 36
	b.tooltip_text = tr("Hilfe")
	b.pressed.connect(func(): show_menu_help(key, title))
	return b


const MENU_HELP := {
	"bauen": "Hier wählst du ein Gebäude. Oben stehen die Reiter nach Art der Gebäude als Bilder (Wohnen, Nahrung, Handwerk, Lager, Wissen, Seefahrt, Wege). In der Mitte jeder Zeile steht, was du im Lager hast und was das Gebäude braucht; Rot heißt: zu wenig.\n\nTippe auf den Hammer, dann auf einen freien Platz in der Landschaft und bestätige mit „Hier bauen“. Das „i“ rechts zeigt die Beschreibung des Gebäudes. Gesperrte Gebäude haben ein Buch statt des Hammers: Es öffnet die Forschung, in der du sie freischaltest. Bauen abbrechen: im Plan auf X tippen.",
	"forschung": "Hier wählst du, was erforscht wird. Die Reiter sind die Zeitalter, als Bilder. Der Knopf mit dem Dreieck beginnt eine Forschung; dafür brauchst du einen Siedler mit dem Beruf Forscher und die Kosten in der Mitte der Zeile (im Lager / nötig, Rot heißt: zu wenig).\n\nDas „i“ rechts zeigt die Beschreibung. Jede Forschung bringt Punkte und schaltet Gebäude oder Berufe frei. Unten steht, woran gerade geforscht wird.",
	"vorraete": "Hier siehst du alle Waren im Lager. Die Reiter zeigen alles, nur Nahrung oder nur Material; „Nur vorhandene“ blendet leere Waren aus.\n\nMit − und + stellst du für eine Ware eine feste Menge ein, die im Lager reserviert bleibt. Unten steht, wie voll das Lager ist.",
	"siedler": "Hier siehst du alle Siedler: oben die mit Beruf, unten die freien. Die Reiter trennen Erwachsene und Kinder, der Filter zeigt einen Beruf, bei mehreren Inseln auch eine Insel.\n\nTippe auf einen Siedler, um ihn anzusehen und ihm einen Beruf zu geben. Unten steht, wie viele Siedler hungrig oder krank sind.",
	"menue": "Unter „Spiel“ speicherst du, öffnest die Spielstände, die Aufträge, die Spielanleitung und die Meldungen. Unter „Einstellungen“ stellst du Musik, Geräusche, Vollbild und Sprache ein.\n\nDas Spiel speichert auch von selbst.",
	"spielstaende": "Es gibt fünf Plätze. Im aktiven Spielstand speichert das Spiel von selbst. Hier kannst du einen Spielstand laden, hierhin speichern, ein neues Spiel beginnen sowie als Datei ausgeben und einlesen.",
	"meldungen": "Hier schaltest du ein, welche Arten von Meldungen im Spiel erscheinen. „Alle an“ schaltet alle Arten wieder ein.",
	"auftraege": "Hier stehen die offenen Aufträge mit Fortschritt und Belohnung.",
	"verwalter": "Unter „Verwalter“ siehst du, wer die Verwaltung leitet, und schaltest die automatische Neuzuweisung freier Berufe. Unter „Schichten“ ordnest du für einen Beruf Schichtarbeit rund um die Uhr an, unter „Nachtschicht“ siehst du, wer nachts arbeitet, unter „Überstunden“ lässt du einen Beruf länger arbeiten.\n\nUnter „Statistik“ steht, wie ausgelastet jeder Beruf ist (Anteil der Zeit, in der die Leute in ihrem Beruf arbeiten) und wie viel von jeder Ware in den letzten 5 Jahren und im laufenden Jahr erzeugt wurde.\n\nUnter „Log“ stehen alle Entscheidungen des Verwalters, neueste oben.",
	"inseln": "Unter „Inseln“ siehst du, welche Waren auf welcher Insel liegen. Unter „Schiffe“ schickst du ein Schiff einmal los (Waren von einer Insel zur anderen) oder legst eine Route fest, die es immer wieder fährt. Rot heißt: dort fehlen Seeleute. Unter „Karte“ siehst du alle Inseln und suchst mit der Entdeckungsreise neue.",
}
var _menu_help: PanelContainer
var _menu_help_title: Label
var _menu_help_text: Label


func show_menu_help(key: String, title: String) -> void:
	if _menu_help == null:
		_menu_help = PanelContainer.new()
		_menu_help.visible = false
		root.add_child(_menu_help)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		_menu_help.add_child(v)
		var head := HBoxContainer.new()
		_menu_help_title = UiTheme.label("", 20, UiTheme.TEXT, true)
		_menu_help_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(_menu_help_title)
		var x := UiTheme.button("", "abriss", 36)
		x.tooltip_text = tr("Schließen")
		x.pressed.connect(func(): _menu_help.visible = false)
		head.add_child(x)
		v.add_child(head)
		_menu_help_text = UiTheme.label("", 15)
		_menu_help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_menu_help_text.custom_minimum_size.x = 300
		v.add_child(_menu_help_text)
	_menu_help_title.text = tr("Hilfe: %s") % title
	_menu_help_text.text = tr(MENU_HELP.get(key, ""))
	_show_menu_help_box()


## Kleines Fenster mit Titel und Text über allem (Hilfe „?“, Beschreibung „i“ im Baumenü).
func show_info(title: String, text: String) -> void:
	show_menu_help("", "")
	_menu_help_title.text = title
	_menu_help_text.text = text
	_show_menu_help_box()


func _show_menu_help_box() -> void:
	_menu_help.visible = true
	root.move_child(_menu_help, -1)
	var vs := get_viewport().get_visible_rect().size
	_menu_help.custom_minimum_size = Vector2(minf(vs.x - 24.0, 440.0), 0)
	_menu_help_text.custom_minimum_size.x = _menu_help.custom_minimum_size.x - 24.0
	_menu_help.size = Vector2.ZERO
	await get_tree().process_frame  # erst nach dem Umbruch des Textes die Höhe nehmen
	_menu_help.reset_size()
	_menu_help.position = Vector2((vs.x - _menu_help.size.x) / 2.0, maxf(_top_h + 10.0, (vs.y - _menu_help.size.y) / 2.0))


# ================================================================== Bau-Menue
const BUILD_CATS := [["wohnen", "Wohnen", "haus"], ["nahrung", "Nahrung", "nahrung"],
	["handwerk", "Handwerk", "hammer"], ["lager", "Lager", "kiste"], ["wissen", "Wissen", "wissen"],
	["see", "Seefahrt und Schutz", "boot"], ["land", "Land und Wege", "weg"], ["schmuck", "Schmuck", "schmuck"]]


func _build_build_panel() -> void:
	var r := _popup_panel(tr("Bauen"), "hammer", "bauen")
	_build_panel = r[0]
	var v: VBoxContainer = r[1]
	_build_title = v.get_child(0).get_child(1)
	# Reiter mit Text (josh 2026-10-16: einheitliche Fenster)
	# Reiter als Bilder (josh 2026-10-19), Name im Tooltip; kein Filter „Nur bezahlbare“ mehr
	var names := []
	var icons := []
	for c in BUILD_CATS:
		names.append(tr(BUILD_TAB_NAMES.get(c[0], c[1])))
		icons.append(c[2])
	var tabs := Win.tabs(names, 0, func(i):
		_build_cat = BUILD_CATS[i][0]
		_fill_build_list(), icons)
	if get_viewport().get_visible_rect().size.x < 600.0:
		# Handy: acht Reiter passen nur schmaler in eine Zeile (Schmuck, josh 2026-10-20)
		tabs.add_theme_constant_override("h_separation", 2)
		for b in tabs.get_children():
			b.custom_minimum_size = Vector2(38, 40)
			b.add_theme_constant_override("icon_max_width", 24)
	v.add_child(tabs)
	for k in BUILD_CATS.size():
		_build_tabs.append([tabs.get_child(k), BUILD_CATS[k][0]])
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(355, 250)
	v.add_child(scroll)
	_build_list = VBoxContainer.new()
	_build_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_build_list)
	_fill_build_list()


const BUILD_TAB_NAMES := {"see": "Seefahrt", "land": "Wege"}


func _fill_build_list() -> void:
	_build_costs.clear()
	for c in _build_list.get_children():
		_build_list.remove_child(c)
		c.queue_free()
	for t in _build_tabs:
		t[0].set_pressed_no_signal(t[1] == _build_cat)
	var locked_rows := []
	var free := _build_free()
	for type in Data.buildings:
		var def: Dictionary = Data.buildings[type]
		if not def.get("buildable", false) or def.get("category", "") != _build_cat:
			continue
		var unlocked := Game.is_unlocked(type)
		var affordable := true
		for res in def.cost:
			if int(free.get(res, 0)) < int(def.cost[res]):
				affordable = false
		# Zeile (josh 2026-10-19): Bild und Name links, Waren in der Mitte, Bauen als Bild, rechts „i“ mit der Beschreibung
		var taken: bool = unlocked and def.get("unique", false) and Admin.exists(type)
		var sub := ""
		if not unlocked:
			sub = tr("Benötigt Forschung: %s") % Data.techs.get(def.get("requires", ""), {}).get("name", "?")
			if Game.is_researched(def.get("requires", "")) and def.get("automaton", false):
				sub = Steward.automaton_reason()
			if Game.is_researched(def.get("requires", "")) and def.get("planner", false):
				sub = Planner.build_reason()
			if AiRule.build_block(type) != "":
				sub = AiRule.build_block(type)
		elif taken:
			sub = tr("Gibt es nur einmal und steht schon.")
		var rw := Win.row(Data.building_tex(type), def.name, sub, {"sub_color": UiTheme.BAD if not unlocked else Win.DIM,
			"button": "", "button_off": not unlocked or taken or not affordable})
		var box: PanelContainer = rw.box
		box.set_meta("btype", type)
		var tv: Control = rw.text
		tv.size_flags_horizontal = Control.SIZE_FILL
		tv.custom_minimum_size.x = 150.0 if get_viewport().get_visible_rect().size.x >= 600.0 else 104.0
		var cost := HFlowContainer.new()
		cost.alignment = FlowContainer.ALIGNMENT_CENTER
		cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cost.add_theme_constant_override("h_separation", 10)
		cost.add_theme_constant_override("v_separation", 2)
		for res in def.cost:
			# im Lager / nötig
			var one := HBoxContainer.new()
			one.add_theme_constant_override("separation", 2)
			one.tooltip_text = Data.resource_name(res)
			one.add_child(UiTheme.icon_rect(Data.res_icon(res), 16))
			var cl := UiTheme.label("", 13)
			_build_costs.append([cl, res, int(def.cost[res])])
			_set_cost(_build_costs[-1], null)
			one.add_child(cl)
			cost.add_child(one)
		rw.h.add_child(cost)
		rw.h.move_child(cost, tv.get_index() + 1)
		cost.modulate.a = 1.0 if unlocked else 0.45
		var bt: Button = rw.button
		bt.icon = Data.icon("hammer" if unlocked else "wissen")
		bt.expand_icon = true
		bt.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bt.add_theme_constant_override("icon_max_width", 26)
		bt.custom_minimum_size = Vector2(48, 40)
		bt.tooltip_text = tr("Bauen")
		var info := UiTheme.button("i", "", 40)
		info.custom_minimum_size = Vector2(36, 40)
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.add_theme_font_size_override("font_size", 18)
		info.tooltip_text = tr("Beschreibung")
		var it: String = type
		info.pressed.connect(func(): show_info(Data.buildings[it].name, _build_info_text(it)))
		rw.h.add_child(info)
		if not unlocked:
			rw.icon.modulate = Color(0.2, 0.15, 0.15, 0.6)
			bt.tooltip_text = tr("Forschung öffnen")
			bt.pressed.connect(func():
				_fill_research_list()
				_toggle(_research_panel))
			locked_rows.append(box)
			continue
		var tp: String = type
		bt.pressed.connect(func():
			if Admin.exists(tp) and Data.buildings[tp].get("unique", false):
				toast(tr("Gibt es nur einmal und steht schon."), "hammer")
				return
			var miss := []
			var fr := _build_free()
			for res in Data.buildings[tp].cost:
				var n := int(Data.buildings[tp].cost[res]) - int(fr.get(res, 0))
				if n > 0:
					miss.append("%d %s" % [n, Data.resource_name(res)])
			if not miss.is_empty():
				toast(tr("Fehlt auf dieser Insel: %s") % ", ".join(miss), "hammer")
				return
			_build_panel.visible = false
			Game.select(null)
			world.start_placement(tp, camera.position)
			Game.player_action.emit("place", tp))
		_build_list.add_child(box)
	for b in locked_rows:
		_build_list.add_child(b)
	if _build_list.get_child_count() == 0:
		_build_list.add_child(UiTheme.label(tr("Hier gibt es noch nichts zu bauen."), 14, Win.DIM))
	_build_dirty = false


## Text hinter dem „i“ einer Zeile im Baumenü: Beschreibung, Bedürfnisse, Inselstärke und was fehlt.
func _build_info_text(type: String) -> String:
	var def: Dictionary = Data.buildings[type]
	var parts := [str(def.desc) + NeedsInfo.build_desc(type)]
	if not Game.is_unlocked(type):
		parts.append(tr("Benötigt Forschung: %s") % Data.techs.get(def.get("requires", ""), {}).get("name", "?"))
	elif def.get("unique", false) and Admin.exists(type):
		parts.append(tr("Gibt es nur einmal und steht schon."))
	if Quests.plan_only(type):
		parts.append(tr("Bauplan aus einem Auftrag."))
	var bonus := IslandTraits.bonus_text(type, world.biome if world else "heimat")
	if bonus != "":
		parts.append(bonus)
	var free := _build_free()
	var miss := []
	for res in def.cost:
		var n := int(def.cost[res]) - int(free.get(res, 0))
		if n > 0:
			miss.append("%d %s" % [n, Data.resource_name(res)])
	if not miss.is_empty():
		parts.append(tr("Fehlt auf dieser Insel: %s") % ", ".join(miss))
	var held := []
	for res in def.cost:
		if _build_held.has(res):
			held.append("%d %s" % [int(_build_held[res]), Data.resource_name(res)])
	if not held.is_empty():
		parts.append(tr("Offene Baustellen holen davon noch: %s") % ", ".join(held))
	return "\n\n".join(parts)


## Baumaterial im Lager dieser Insel (josh 2026-10-19: die Zahl soll zeigen, was im Lager liegt). Was offene
## Baustellen davon noch holen, steht nur als Hinweis im Fuß des Fensters (_build_held).
var _build_held: Dictionary = {}
var _build_dirty := false


func _build_free() -> Dictionary:
	_build_held = {}
	for b in world.buildings:
		if not b.complete:
			var rc: Dictionary = b.remaining_cost()
			for res in rc:
				_build_held[res] = int(_build_held.get(res, 0)) + int(rc[res])
	var out := {}
	for res in Data.resources:
		out[res] = Game.amount(res)
	return out


## Kosten in den Zeilen von Bauen und Forschung: „im Lager/nötig“, rot bei zu wenig. Ändert sich das Lager,
## werden nur Zahl und Farbe neu gesetzt, die Zeilen bleiben stehen (josh 2026-10-19: Vergleich muss stimmen).
var _build_costs: Array = []  # [Label, Ware, nötig]
var _research_costs: Array = []


func _set_cost(e: Array, w) -> void:
	var cl: Label = e[0]
	if not is_instance_valid(cl):
		return
	var hv := Game.amount(e[1], w)
	cl.text = "%d/%d" % [mini(hv, 9999), int(e[2])]
	cl.add_theme_color_override("font_color", UiTheme.TEXT if hv >= int(e[2]) else UiTheme.BAD)


func _update_costs() -> void:
	if _build_panel != null and _build_panel.visible:
		for e in _build_costs:
			_set_cost(e, null)
	if _research_panel != null and _research_panel.visible:
		for e in _research_costs:
			_set_cost(e, Sea.main_world())


## Lager ändert sich, während das Bauen-Fenster offen ist: höchstens einmal je Sekunde neu füllen.
func _on_stock_for_build() -> void:
	if _build_panel == null or not _build_panel.visible or _build_dirty or not user_just_acted():
		return
	_build_dirty = true
	get_tree().create_timer(1.0, true, false, true).timeout.connect(func():
		if _build_dirty and _build_panel.visible:
			_fill_build_list()
		_build_dirty = false)


# ================================================================== Forschung
func _build_research_panel() -> void:
	var r := _popup_panel(tr("Forschung"), "wissen", "forschung")
	_research_panel = r[0]
	var v: VBoxContainer = r[1]
	_research_tabs = Win.chip_row()  # Reiter je Zeitalter, in _fill_research_list gefüllt
	_research_tabs.remove_meta("fit_hide")
	_research_tabs.add_theme_constant_override("h_separation", 4)
	v.add_child(_research_tabs)
	_research_scroll = ScrollContainer.new()
	_research_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_research_scroll.custom_minimum_size = Vector2(355, RESEARCH_LIST_H)
	v.add_child(_research_scroll)
	_research_list = VBoxContainer.new()
	_research_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_research_list.add_theme_constant_override("separation", 4)
	_research_scroll.add_child(_research_list)
	# Fuß: Stand der Forschung, Forscher und Schriften
	var ft := Win.footer(v)
	ft.box.visible = false
	_research_head = VBoxContainer.new()
	_research_head.add_theme_constant_override("separation", 2)
	v.add_child(_research_head)
	_research_label = UiTheme.label("", 14, UiTheme.TEXT, true)
	_research_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_research_label.custom_minimum_size.x = 330
	_research_head.add_child(_research_label)
	_research_bar = UiTheme.bar(Color("#5a8ad8"), 10)
	_research_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_research_head.add_child(_research_bar)
	for i in 2:  # Forschung braucht Schriften: Verbrauch und Lager, rote Zeile wenn etwas fehlt
		var wl := UiTheme.label("", 12, Win.DIM if i == 0 else UiTheme.BAD, i == 1)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wl.custom_minimum_size.x = 330
		_research_head.add_child(wl)
		_research_writing.append(wl)


var _research_tabs: HFlowContainer
var _research_age := -1  # gewählter Reiter (Zeitalter); -1 = das aktuelle
const AGE_ICONS := ["axt", "tontafel", "schwert", "fernrohr", "dampf", "strom", "computer", "roboter"]


## Forschungsfenster: Die Liste wird kürzer, wenn die Kopfzeilen (Schreibwaren, Prüfung) wachsen,
## damit das Fenster nicht in die untere Knopfleiste ragt.
func _fit_research(top_h: float = -1.0) -> void:
	if _research_scroll == null or _research_panel == null or root == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var bp: Control = _bottom.get_parent()
	if top_h < 0.0:
		top_h = 100.0 if (vs.y > vs.x or vs.x < 760) else 50.0
	var avail := vs.y - top_h - bp.size.y - 18.0
	_research_scroll.custom_minimum_size.y = RESEARCH_LIST_H
	var over := _research_panel.get_combined_minimum_size().y - avail
	if over > 0.0:
		_research_scroll.custom_minimum_size.y = clampf(RESEARCH_LIST_H - over, 120.0, RESEARCH_LIST_H)
	_research_panel.reset_size()
	_research_panel.size.x = minf(_research_panel.size.x, vs.x - 12)
	_research_panel.position = Vector2((vs.x - _research_panel.size.x) / 2.0, maxf(top_h, vs.y - _research_panel.size.y - bp.size.y - 18))


const RESEARCH_LIST_H := 270.0


## Forscher auf der Hauptinsel (nur dort wird geforscht, josh 2026-10-16).
func _forscher_count() -> int:
	var mw = Sea.main_world()
	return mw.settlers.filter(func(s): return s.is_adult() and s.job == "forscher").size() if mw else 0


func _update_research_head() -> void:
	if _research_label == null:
		return
	var cur: String = Game.research.current
	var n := _forscher_count()
	var who := tr("Keine Forscher! Gib einem Siedler den Beruf Forscher.") if n == 0 else tr("Forscher: %d") % n
	if cur == "":
		_research_label.text = who
		if Exams.only_exam_left():
			_research_label.text = tr("Alles erforscht, was jetzt geht. Bestehe die Prüfung für das Zeitalter %s!") % Data.age_name(Game.current_age() + 1) + "\n" + who
		_research_bar.value = 0
	else:
		var pts := Game.tech_points(cur)
		# Ohne Punkte (josh 2026-10-19): Name und Prozent, der Balken zeigt den Fortschritt
		_research_label.text = tr("Forschung: %s  %d%%\n%s") % [Data.techs[cur].name, int(Game.tech_progress(cur) / pts * 100.0), who]
		_research_bar.value = Game.tech_progress(cur) / pts * 100.0
	_research_label.add_theme_color_override("font_color", UiTheme.BAD if n == 0 else UiTheme.TEXT)
	var wt: Array = Writing.head_lines(Sea.main_world(), n)
	var wchanged := false
	for i in _research_writing.size():
		wchanged = wchanged or _research_writing[i].text != wt[i]
		_research_writing[i].text = wt[i]
		_research_writing[i].visible = wt[i] != ""
	if wchanged and _research_panel.visible:
		_fit_research()
	if _research_panel.visible and is_instance_valid(_exam_box):
		ExamView.refresh(_exam_box)
	var label := tr("Forschung")
	if cur != "":
		label += ": %s %d%%" % [Data.techs[cur].name, int(Game.tech_progress(cur) / Game.tech_points(cur) * 100.0)]
	_research_btn.tooltip_text = label  # Knopf zeigt nur das Bild (josh 2026-10-19)


const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI"]


func _fill_research_list() -> void:
	var keep := _research_scroll.scroll_vertical
	_research_costs.clear()
	for c in _research_list.get_children():
		_research_list.remove_child(c)
		c.queue_free()
	_update_research_head()
	var cur_age := Game.current_age()
	var max_age := mini(cur_age + 1, Data.ages.size() - 1)
	if _research_age < 0 or _research_age > max_age:
		_research_age = cur_age
	# Reiter: erreichte Zeitalter und das nächste
	for c in _research_tabs.get_children():
		_research_tabs.remove_child(c)
		c.queue_free()
	for a in range(0, max_age + 1):
		# Reiter als Bilder (josh 2026-10-19), Name im Tooltip
		var tb := UiTheme.button("", "", 40)
		tb.icon = Data.icon(AGE_ICONS[mini(a, AGE_ICONS.size() - 1)])
		tb.expand_icon = true
		tb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tb.add_theme_constant_override("icon_max_width", 28)
		tb.custom_minimum_size = Vector2(48 if get_viewport().get_visible_rect().size.x >= 480.0 else 40, 40)
		tb.tooltip_text = Data.age_name(a)
		tb.toggle_mode = true
		tb.button_pressed = a == _research_age
		tb.add_theme_font_size_override("font_size", 14)
		var aa: int = a
		tb.pressed.connect(func():
			_research_age = aa
			_research_scroll.scroll_vertical = 0
			_fill_research_list())
		_research_tabs.add_child(tb)
	var tier := 0
	var age := -1
	for t in Data.sorted_tech_ids():
		var def: Dictionary = Data.techs[t]
		var a := Data.age_of_tier(int(def.tier))
		if a != _research_age:
			continue
		if a != age:
			age = a
			_research_list.add_child(_age_header(a, cur_age))
			if a == cur_age + 1 and not Exams.exam_def(cur_age).is_empty():
				_exam_box = ExamView.exam_box(cur_age)  # Pruefung, die dieses Zeitalter oeffnet
				_research_list.add_child(_exam_box)
		if int(def.tier) != tier:
			tier = int(def.tier)
			var name: String = Data.tiers[tier - 1] if tier - 1 < Data.tiers.size() else ""
			var hl := UiTheme.label(tr("Stufe %s: %s") % [ROMAN[min(tier - 1, ROMAN.size() - 1)], name], 15, Color("#7a4a28"), true)
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
	if a <= cur_age + 1 and Writing.age_text(a) != "":
		d.text += "\n" + Writing.age_text(a)  # Forschung braucht Schriften
	if a == cur_age + 1:
		d.text += "\n" + tr("Beginnt, sobald die Prüfung bestanden ist.")
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 200
	v.add_child(d)
	return box


## Hoehe einer Listenzeile, damit der umbrechende Text hineinpasst.
func _row_height(text: String, chars_per_line: int) -> float:
	var lines := ceili(float(text.length()) / chars_per_line)
	return max(62.0, 34.0 + 15.0 * lines)


func _tech_row(t: String) -> Control:
	# Zeile wie im Baumenü (josh 2026-10-19): Bild und Name links, Kosten und Punkte in der Mitte,
	# Knopf als Bild, rechts „i“ mit der Beschreibung
	var def: Dictionary = Data.techs[t]
	var st := Game.tech_state(t)
	var sub := ""
	if st == "locked":
		sub = tr("Benötigt: ") + ", ".join(_tech_missing(t))
	var tip: String = {"available": tr("Starten"), "current": tr("Läuft"), "done": tr("Fertig"),
		"locked": tr("Wie?"), "exam": tr("Prüfung"), "soon": tr("Bald")}.get(st, tr("Starten"))
	var rw := Win.row(Data.tech_tex(t), def.name, sub, {"sub_color": UiTheme.BAD, "button": "",
		"button_off": st != "available", "hi": st == "current"})
	var box: PanelContainer = rw.box
	box.set_meta("tid", t)
	if st in ["locked", "soon", "exam"]:
		rw.icon.modulate = Color(0.25, 0.2, 0.2, 0.6)
	if st == "done":
		box.modulate = Color(0.85, 1.0, 0.85)
	var tv: Control = rw.text
	tv.size_flags_horizontal = Control.SIZE_FILL
	tv.custom_minimum_size.x = 150.0 if get_viewport().get_visible_rect().size.x >= 600.0 else 104.0
	var mid := HFlowContainer.new()
	mid.alignment = FlowContainer.ALIGNMENT_CENTER
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("h_separation", 10)
	mid.add_theme_constant_override("v_separation", 2)
	rw.h.add_child(mid)
	rw.h.move_child(mid, tv.get_index() + 1)
	var queued: bool = st == "available" and Game.research.get("next", "") == t
	if queued:
		tip = tr("Vorgemerkt: kommt als Nächstes dran. Antippen nimmt es zurück.")
		box.modulate = Color(1.0, 0.95, 0.8)
		mid.add_child(UiTheme.label(tr("als Nächstes"), 13, UiTheme.TEXT, true))
	elif st == "available" and Game.research.current != "":
		tip = tr("Vormerken: kommt als Nächstes dran")
	if st != "done":
		if t in Game.research.paid:
			mid.add_child(UiTheme.label(tr("bezahlt"), 12, Win.DIM))
		else:
			for res in def.get("cost", {}):
				var one := HBoxContainer.new()
				one.add_theme_constant_override("separation", 2)
				one.tooltip_text = Data.resource_name(res)
				one.add_child(UiTheme.icon_rect(Data.res_icon(res), 16))
				var cl := UiTheme.label("", 13)
				_research_costs.append([cl, res, int(def.cost[res])])
				_set_cost(_research_costs[-1], Sea.main_world())
				one.add_child(cl)
				mid.add_child(one)
		var pct := Game.tech_progress(t) / Game.tech_points(t) * 100.0
		if pct > 0:  # keine Punkte mehr (josh 2026-10-19), nur der Fortschritt einer begonnenen Forschung
			mid.add_child(UiTheme.label("%d%%" % int(pct), 13, UiTheme.TEXT, true))
	var bt: Button = rw.button
	bt.icon = Data.icon("haken") if queued else Data.icon({"available": "play", "current": "uhr", "done": "haken", "locked": "wissen",
		"exam": "zeitalter", "soon": "uhr"}.get(st, "play"))
	bt.expand_icon = true
	bt.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bt.add_theme_constant_override("icon_max_width", 26)
	bt.custom_minimum_size = Vector2(48, 40)
	bt.tooltip_text = tip
	var info := UiTheme.button("i", "", 40)
	info.custom_minimum_size = Vector2(36, 40)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_font_size_override("font_size", 18)
	info.tooltip_text = tr("Beschreibung")
	info.pressed.connect(func(): show_info(Data.techs[t].name, _tech_info_text(t)))
	rw.h.add_child(info)
	var d: Label = rw.sub if rw.sub != null else rw.name
	bt.pressed.connect(_on_tech_pressed.bind(t, bt, d))
	return box


func _tech_missing(t: String) -> Array:
	var need := []
	for rq in Data.techs[t].get("requires", []):
		if not Game.is_researched(rq):
			need.append(Data.techs[rq].name)
	return need


## Text hinter dem „i“ einer Forschung: Beschreibung, was fehlt, Schriften und wo geforscht wird.
func _tech_info_text(t: String) -> String:
	var def: Dictionary = Data.techs[t]
	var parts := [str(def.desc)]
	var st := Game.tech_state(t)
	if st == "locked":
		parts.append(tr("Benötigt: ") + ", ".join(_tech_missing(t)))
	var wr := Writing.row_text(t) if st != "done" else ""
	if wr != "":
		parts.append(wr)
	if Sea.all_worlds().size() > 1:
		parts.append(tr("Geforscht wird nur auf %s, die Kosten kommen aus ihrem Lager.") % Sea.island_name(Sea.main_world()))
	return "\n\n".join(parts)


func _on_tech_pressed(tid: String, _b: Button, d: Label) -> void:
	var def: Dictionary = Data.techs[tid]
	match Game.tech_state(tid):
		"available":
			var running: bool = Game.research.current != ""
			toast(Game.queue_research(tid), "wissen")  # läuft schon eine: vormerken (josh 2026-10-28)
			if not running and Game.research.current == tid and _forscher_count() == 0:
				toast(tr("Tipp: Gib einem Siedler den Beruf Forscher."), "person")
		"locked":
			toast(d.text, "wissen")
		"exam":
			toast(Exams.missing_text(), "zeitalter")
		"soon":
			toast(tr("Dieses Wissen kommt mit einem späteren Update."), "wissen")
		"done":
			toast(tr("%s ist schon erforscht.") % def.name, "wissen")
		"current":
			toast(tr("Wird gerade erforscht: %s") % def.name, "wissen")


func _on_research_changed() -> void:
	_update_sea_button()
	_update_admin_button()
	if _research_panel.visible:
		if user_just_acted():
			_fill_research_list()
	else:
		_update_research_head()
	if not _build_panel.visible or user_just_acted():
		_fill_build_list()


# ================================================================== Vorraete
func _build_stock_panel() -> void:
	var r := _popup_panel(tr("Vorräte"), "kiste", "vorraete")
	_stock_panel = r[0]
	var v: VBoxContainer = r[1]
	v.add_child(Win.tabs([tr("Alles"), tr("Nahrung"), tr("Material")], 0, func(i):
		_stock_cat = ["", "food", "material"][i]
		_refresh_stock(true)))
	var chips := Win.chip_row()
	chips.add_child(Win.chip(tr("Nur vorhandene"), false, func(on):
		_stock_only_have = on
		_refresh_stock(true)))
	v.add_child(chips)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(min(440.0, get_viewport().get_visible_rect().size.x - 40.0), 300)
	v.add_child(scroll)
	_stock_grid = GridContainer.new()
	_stock_grid.columns = 1
	_stock_grid.add_theme_constant_override("v_separation", 3)
	_stock_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_stock_grid)
	_stock_ft = Win.footer(v)
	_stock_ft.left.mouse_filter = Control.MOUSE_FILTER_PASS
	_stock_ft.left.tooltip_text = tr("Lege mit − und + fest, wie viel von einer Ware gelagert wird. „×2“ ist der Raum, den ein Stück braucht. „frei“ heißt: die Ware nimmt sich freien Platz, solange welcher da ist. Ist kein Platz mehr, sammeln die Siedler diese Ware nicht mehr.")
	_stock_bar = UiTheme.bar(UiTheme.GOOD)
	_stock_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stock_ft.left.get_parent().add_child(_stock_bar)
	_stock_ft.left.get_parent().move_child(_stock_bar, 1)


var _stock_cat := ""
var _stock_only_have := false
var _stock_ft: Dictionary = {}
var _stock_bar: ProgressBar
## Gezielt aktualisieren (josh 2026-10-22): Zeigt das Fenster dieselben Waren wie zuletzt, ändern sich nur Zahlen
## und Knöpfe der bestehenden Zeilen (_stock_rows); neu gebaut wird nur, wenn sich die Auswahl der Waren ändert.
var _stock_rows: Dictionary = {}  # Ware -> {al, ll, minus, plus, tail, kind, h}
var _stock_ids: Array = []


func _refresh_stock(force: bool = false) -> void:
	if _stock_grid == null or (not force and not _stock_panel.visible):
		return
	var vol := Game.storage_volume()
	var used := Game.used_volume()
	_stock_ft.left.text = tr("Lager: %d von %d belegt") % [used, vol]
	_stock_bar.value = 100.0 * used / max(1, vol)
	(_stock_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = UiTheme.BAD if used >= vol else UiTheme.GOOD
	Win.set_left2(_stock_ft, tr("Frei: %d, für feste Mengen reserviert: %d. Nahrungssorten: %d") % [maxi(0, vol - used), Game.reserved_volume(), Game.food_variety()])
	var ids := []
	for id in Data.sorted_resource_ids():
		var cat: String = Data.resources[id].get("category", "")
		if cat == "ship":
			continue  # Schiffe liegen im Hafen, nicht im Lager
		if _stock_cat != "" and cat != _stock_cat:
			continue
		if _stock_only_have and Game.amount(id) <= 0 and Game.limit_of(id) < 0:
			continue
		ids.append(id)
	if ids == _stock_ids and not ids.is_empty():
		for id in ids:
			_update_stock_row(id)
		return
	_stock_ids = ids
	_stock_rows.clear()
	for c in _stock_grid.get_children():
		_stock_grid.remove_child(c)
		c.queue_free()
	for id in ids:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", Win.row_box())
		box.add_child(_stock_row(id))
		_stock_grid.add_child(box)
		_update_stock_row(id)
	if _stock_grid.get_child_count() == 0:
		_stock_grid.add_child(UiTheme.label(tr("Davon ist nichts im Lager."), 14, Win.DIM))


func _stock_row(id: String) -> Control:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(UiTheme.icon_rect(Data.res_icon(id), 24))
	var size := Data.good_size(id)
	var n := UiTheme.label(Data.resource_name(id), 15, UiTheme.TEXT, true)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.tooltip_text = tr("Größe: %d Raum je Stück") % size if size > 0 else tr("Braucht keinen Lagerraum.")
	n.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(n)
	var al := UiTheme.label("", 14, UiTheme.TEXT, true)
	al.custom_minimum_size.x = 36
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(al)
	var r := {"h": h, "al": al}
	_stock_rows[id] = r
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
	var ll := UiTheme.label("", 14)
	ll.custom_minimum_size.x = 38
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ll.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(ll)
	var plus := UiTheme.button("+", "", 30)
	plus.tooltip_text = tr("Mehr lagern")
	plus.pressed.connect(func():
		var cur := Game.limit_of(id)
		var base: int = ceili(Game.amount(id) / 10.0) * 10 if cur < 0 else cur
		var got := Game.set_limit(id, base + 10)
		if got < base + 10:
			toast(tr("Der Stauraum ist ausgeschöpft."), "kiste")
		_refresh_stock(true))
	h.add_child(plus)
	var tail := HBoxContainer.new()  # „N weg“, „frei“ oder Platzhalter, je nach Lage (_update_stock_row)
	tail.custom_minimum_size.x = 30
	h.add_child(tail)
	r.merge({"ll": ll, "plus": plus, "tail": tail, "kind": ""})
	return h


## Zahlen und Knöpfe einer bestehenden Lagerzeile auf den Stand bringen.
func _update_stock_row(id: String) -> void:
	var r: Dictionary = _stock_rows.get(id, {})
	if r.is_empty():
		return
	var a := Game.amount(id)
	var lim := Game.limit_of(id)
	var full := Data.good_size(id) > 0 and Game.space_for(id) <= 0
	r.al.text = "%d" % a
	r.al.add_theme_color_override("font_color", UiTheme.BAD if full else UiTheme.TEXT)
	r.h.modulate.a = 1.0 if a > 0 or lim >= 0 else 0.6
	if not r.has("ll"):
		return
	r.ll.text = "frei" if lim < 0 else "%d" % lim
	r.ll.tooltip_text = tr("Höchstens so viel wird gelagert.") if lim >= 0 else tr("Keine feste Menge: nimmt freien Platz.")
	r.plus.disabled = lim >= 0 and lim >= Game.max_limit(id)
	var ex := Game.excess(id)
	var kind := "weg" if ex > 0 else ("frei" if lim >= 0 else "")
	var tail: HBoxContainer = r.tail
	if kind == r.kind:
		if kind == "weg":
			tail.get_child(0).text = tr("%d weg") % ex
		return
	r.kind = kind
	for c in tail.get_children():
		tail.remove_child(c)
		c.queue_free()
	if kind == "weg":
		var d := UiTheme.button(tr("%d weg") % ex, "", 30)
		d.tooltip_text = tr("Überschuss wegwerfen. Er ist dann verloren.")
		d.add_theme_color_override("font_color", UiTheme.BAD)
		d.pressed.connect(func():
			var k := Game.discard_excess(id)
			toast(tr("%d %s weggeworfen.") % [k, Data.resource_name(id)], "abriss")
			_refresh_stock(true))
		tail.add_child(d)
	elif kind == "frei":
		var f := UiTheme.button("frei", "", 30)
		f.tooltip_text = tr("Feste Menge aufheben")
		f.pressed.connect(func():
			Game.set_limit(id, -1)
			_refresh_stock(true))
		tail.add_child(f)


func _build_place_bar() -> void:
	_place_bar = PanelContainer.new()
	_place_bar.visible = false
	root.add_child(_place_bar)
	var h := HBoxContainer.new()
	_place_bar.add_child(h)
	_place_label = UiTheme.label("", 14)
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
			# Ohne Bedienhinweis (josh 2026-10-19): nur Gebäude und ob der Platz passt
			_place_label.text = tr("%s verschieben.%s") % [
				Data.buildings[type].name, tr(" Der Platz passt.") if valid else (tr("\nMuss am Ufer stehen und Platz haben.") if Data.buildings[type].get("coast", false) else tr("\nHier ist kein Platz frei."))]
			_layout()
			return
		var why := tr("\nHier ist kein Platz frei.")
		if Data.buildings[type].get("coast", false):
			why = tr("\nMuss am Ufer stehen und Platz haben.")
		elif Data.buildings[type].get("water_ok", false):
			why = tr("\nIm Wasser nur neben Land oder einem anderen Deich.")
		_place_label.text = "%s.%s" % [
			Data.buildings[type].name, tr(" Der Platz passt.") if valid else why]
		if Data.buildings[type].get("repeat", false):
			_place_label.text += tr("\nDu kannst mehrere nacheinander setzen. Abbrechen beendet das Bauen.")
	_layout()


# ================================================================== Siedlerliste
const DIM := Color("#6e5a50")
## Sortierbare Spalten: Schluessel, Text, Breite (0 = dehnbar; breit / schmal)
const SETTLER_COLS := [["name", "Name", 0, 0], ["age", "Alter", 62, 30], ["act", "Tätigkeit", 0, -1],
	["talent", "Talent", -1, -1], ["job", "Beruf", 150, 84], ["busy", "Auslastung", 110, 40], ["hunger", "Satt", 120, 44], ["mood", "Laune", 120, 44]]
## Dichte Liste (josh 2026-10-22): keine Talent-Spalte, keine Zahlen über den Balken, Filter, Zähler und
## „Freie zeigen“ in einer Zeile, beide Gruppen in einer Liste ohne Lücke, das Fenster reicht bis unten
## (die Knöpfe unten liegen darüber, die Liste rollt unter ihnen hervor).
var _settler_show_free: bool = true
var _settler_free_cb: CheckBox
var _settler_pad: Control
var _settler_scroll: ScrollContainer
var _settler_updaters: Array = []
var _settler_tick: float = 0.0
var _settler_sig: String = ""  # wer mit Beruf, wer frei: ändert es sich, wird die Liste neu gebaut
var _settler_head: Dictionary = {}  # Spalte -> Knopf
var _settler_sort: String = "age"
var _settler_desc: bool = true
var _settler_f_job: OptionButton
var _settler_f_group: OptionButton
var _settler_f_island: OptionButton
var _settler_count: Label
var _settler_narrow: bool = false


func _build_settler_panel() -> void:
	var r := _popup_panel(tr("Siedler"), "person", "siedler")
	_settler_panel = r[0]
	var v: VBoxContainer = r[1]
	# Altersfilter bleibt unsichtbar (Testhilfe --sfilter), sonst immer „Alle Alter“
	_settler_f_group = _settler_filter_button(tr("Erwachsene oder Kinder anzeigen"))
	for t in [tr("Alle Alter"), tr("Erwachsene"), tr("Kinder")]:
		_settler_f_group.add_item(t)
	_settler_f_group.visible = false
	v.add_child(_settler_f_group)
	# Keine Reiter Alle / Erwachsene / Kinder mehr (josh 2026-10-19, die Liste zeigt immer alle).
	# Filter nur für Berufe und bei mehreren Inseln die Insel; keine „Nur Hungrige“/„Nur Kranke“ (josh 2026-10-19)
	var fr := HFlowContainer.new()
	fr.add_theme_constant_override("h_separation", 6)
	fr.add_theme_constant_override("v_separation", 2)
	_settler_f_job = _settler_filter_button(tr("Welche Berufe anzeigen"))
	fr.add_child(_settler_f_job)
	_settler_f_island = _settler_filter_button(tr("Welche Insel anzeigen"))
	fr.add_child(_settler_f_island)
	_settler_free_cb = CheckBox.new()
	_settler_free_cb.text = tr("Freie zeigen")
	_settler_free_cb.button_pressed = _settler_show_free
	_settler_free_cb.focus_mode = Control.FOCUS_NONE
	_settler_free_cb.add_theme_font_size_override("font_size", 14)
	_settler_free_cb.tooltip_text = tr("Freie Siedler und Kinder in der Liste zeigen oder ausblenden")
	_settler_free_cb.toggled.connect(func(on):
		_settler_show_free = on
		Sound.play("klick")
		_refresh_settler_list())
	fr.add_child(_settler_free_cb)
	_settler_count = UiTheme.label("", 14, DIM)
	_settler_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_settler_count.custom_minimum_size.y = 32
	_settler_count.mouse_filter = Control.MOUSE_FILTER_PASS
	fr.add_child(_settler_count)
	v.add_child(fr)
	# Spaltenkoepfe: antippen sortiert, nochmal antippen dreht die Reihenfolge um
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	for col in SETTLER_COLS:
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size.y = 22
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
	_settler_head_row = head
	# Eine Liste: oben die Siedler mit Beruf, direkt darunter die freien (und die Kinder)
	_settler_scroll = ScrollContainer.new()
	_settler_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settler_scroll.custom_minimum_size = Vector2(560, 120)
	_settler_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_settler_scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 2)
	_settler_scroll.add_child(inner)
	_settler_head_job = UiTheme.label("", 14, Color("#7a4a28"), true)
	inner.add_child(_settler_head_job)
	_settler_list = VBoxContainer.new()
	_settler_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settler_list.add_theme_constant_override("separation", 2)
	inner.add_child(_settler_list)
	_settler_head_free = UiTheme.label("", 14, Color("#7a4a28"), true)
	inner.add_child(_settler_head_free)
	_settler_list_free = VBoxContainer.new()
	_settler_list_free.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settler_list_free.add_theme_constant_override("separation", 2)
	inner.add_child(_settler_list_free)
	_settler_pad = Control.new()  # Platz unter der letzten Zeile: die Knöpfe unten liegen über dem Fenster
	_settler_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(_settler_pad)
	_settler_scroll_free = _settler_scroll


func _settler_filter_button(tip: String) -> OptionButton:
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(120, 32)
	ob.add_theme_font_size_override("font_size", 14)
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
	var tight := avail_h < 360.0  # Handy quer: ohne Spaltenköpfe
	_settler_head_row.visible = not tight
	_settler_scroll.custom_minimum_size = Vector2(w, 60.0)
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
	_settler_sig = _settler_signature()
	var keep := [_settler_scroll.scroll_vertical]
	# Gezielt aktualisieren (josh 2026-10-22): Zeilen, deren Siedler gleich geblieben ist (erwachsen, Beruf,
	# Insel), werden wiederverwendet und nur neu einsortiert; neu gebaut wird nur, was sich geändert hat.
	var cached_rows := {}
	for e in _settler_rows.values():
		cached_rows[e.rb] = true
	for lst in [_settler_list, _settler_list_free]:
		for c in lst.get_children():
			lst.remove_child(c)
			if not cached_rows.has(c):
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
		# Berufe-Filter gilt nur für die Liste „Mit Beruf“; „Frei“ zeigt immer alle Freien und Kinder (josh 2026-10-20)
		if f_job != "" and s.is_adult() and s.job != "frei" and s.job != f_job:
			return false
		if group == 1 and not s.is_adult():
			return false
		if group == 2 and s.is_adult():
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
			"talent":
				va = TalentInfo.short_list(a.mind)
				vb = TalentInfo.short_list(b.mind)
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
	var hungry_n := pool.filter(func(x): return x.hunger < 30.0).size()
	_settler_count.text = tr("%d Siedler, %d hungrig") % [pool.size(), hungry_n] + ((tr(", %d krank") % sick_n) if sick_n > 0 else "")
	_settler_count.tooltip_text = tr("Zu sehen: %d. Lebensstil: %s.") % [list.size(), stage[0]]
	var n_job := list.filter(func(x): return x.is_adult() and x.job != "frei").size()
	_settler_head_job.text = tr("Mit Beruf (%d)") % n_job
	_settler_head_free.text = tr("Frei (%d)") % (list.size() - n_job)
	_settler_head_free.visible = _settler_show_free
	_settler_list_free.visible = _settler_show_free
	_settler_pad.custom_minimum_size.y = _bottom.get_parent().size.y + 12.0
	if n_job == 0:
		_settler_list.add_child(UiTheme.label(tr("Niemand passt zu dieser Auswahl.") if not pool.is_empty() else tr("Auf dieser Insel lebt niemand."), 14))
	if list.size() - n_job == 0:
		_settler_list_free.add_child(UiTheme.label(tr("Alle haben einen Beruf."), 14, DIM))
	var narrow := _settler_narrow
	var row_h := 26
	var jsig := str(Data.jobs.keys().filter(func(j): return Data.job_unlocked(j)).size())
	var used := {}
	for s in list:
		var rk := "%s|%s|%s|%s|%s|%s" % [s.is_adult(), s.job, s.job_by if s.by_admin else "", s.world == world, narrow, jsig]
		var sid: int = s.get_instance_id()
		var target: VBoxContainer = _settler_list if (s.is_adult() and s.job != "frei") else _settler_list_free
		var cr = _settler_rows.get(sid, null)
		if cr != null and cr.key == rk:
			used[sid] = true
			cr.upd.call()
			_settler_updaters.append(cr.upd)
			target.add_child(cr.rb)
			continue
		if cr != null:
			cr.rb.queue_free()
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
		if not s.mind.best_talents().is_empty():  # Stern am Namen: hat ein Talent (josh 2026-10-23 wieder da)
			nb.tooltip_text += "\n" + "\n".join(s.mind.best_talents().map(func(k): return TalentInfo.line(sref.mind, k)))
			TalentInfo.badge(nb)
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
		var jw: int = SETTLER_COLS[4][3] if narrow else SETTLER_COLS[4][2]
		if s.is_adult():
			# Beruf direkt in der Liste waehlen
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_NONE
			ob.custom_minimum_size = Vector2(jw, row_h - 2)
			if narrow:
				# Talent-Sterne im Menue machen den Knopf sonst breiter als das Handy
				ob.fit_to_longest_item = false
				ob.custom_minimum_size.x = 136
			ob.clip_text = true
			ob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ob.add_theme_font_size_override("font_size", 14)
			ob.get_popup().add_theme_font_size_override("font_size", 16)
			_compact(ob)
			var ids := []
			for j in Data.jobs:
				if not Data.job_unlocked(j) and j != s.job:
					continue
				if TalentInfo.job_match(s.mind, j):  # Stern: Beruf passt zum Talent (josh 2026-10-23 wieder da)
					ob.add_icon_item(TalentInfo.star(), Data.jobs[j].name, ids.size())
				else:
					ob.add_item(Data.jobs[j].name, ids.size())
				ids.append(j)
				if j == s.job:
					ob.select(ids.size() - 1)
			ob.tooltip_text = tr("Beruf wählen") + (tr("\nStern: passt zum Talent (%s)") % TalentInfo.short_list(s.mind) if not s.mind.best_talents().is_empty() else "")
			if s.by_admin:
				UiTheme.mark_admin(ob)
				var sel := ids.find(s.job)
				if sel >= 0:
					ob.set_item_text(sel, s.job_label(true))  # „Bauer (Verwalter)“, josh 2026-10-28
			ob.get_popup().about_to_popup.connect(func(): Game.player_action.emit("job_list", ""))
			ob.item_selected.connect(func(i):
				JobDesk.assign(sref, ids[i], "spieler")  # Vergabestelle: Automatik überstimmt das eine Weile nicht
				Game.player_action.emit("job", ids[i])
				_refresh_settler_list.call_deferred())  # Zeile wandert zu „Mit Beruf“ oder „Frei“
			h.add_child(ob)
		else:
			var kl := UiTheme.label(tr("Kind"), 14, DIM)
			kl.custom_minimum_size.x = jw
			h.add_child(kl)
		# Auslastung: Anteil der eigenen Arbeit an der Tageszeit
		var bz := VBoxContainer.new()
		bz.custom_minimum_size.x = SETTLER_COLS[5][3] if narrow else SETTLER_COLS[5][2]
		bz.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bz.add_theme_constant_override("separation", 1)
		bz.mouse_filter = Control.MOUSE_FILTER_PASS
		var bl := UiTheme.label("", 12)
		bl.mouse_filter = Control.MOUSE_FILTER_PASS
		bl.visible = false  # keine Zahl über dem Balken (josh 2026-10-22), steht im Tooltip
		bz.add_child(bl)
		var bbar := UiTheme.bar(Color("#5a9a4a"), 8)
		bbar.custom_minimum_size.x = 0
		bz.add_child(bbar)
		h.add_child(bz)
		# Saettigung: Balken mit Prozentzahl
		var sat := VBoxContainer.new()
		sat.custom_minimum_size.x = SETTLER_COLS[6][3] if narrow else SETTLER_COLS[6][2]
		sat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sat.add_theme_constant_override("separation", 1)
		sat.mouse_filter = Control.MOUSE_FILTER_PASS
		var pl := UiTheme.label("", 12)
		pl.visible = false  # keine Zahl über dem Balken (josh 2026-10-22), steht im Tooltip
		sat.add_child(pl)
		var hb := UiTheme.bar(Color("#e0a040"), 8)
		hb.custom_minimum_size.x = 0
		sat.add_child(hb)
		h.add_child(sat)
		# Laune, rot bei Krankheit
		var md := VBoxContainer.new()
		md.custom_minimum_size.x = SETTLER_COLS[7][3] if narrow else SETTLER_COLS[7][2]
		md.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		md.add_theme_constant_override("separation", 1)
		md.mouse_filter = Control.MOUSE_FILTER_PASS
		var ml := UiTheme.label("", 12)
		ml.clip_text = true
		ml.visible = false  # keine Zahl über dem Balken (josh 2026-10-22), steht im Tooltip
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
			sat.tooltip_text = tr("Satt: %s") % pl.text
			var m: SettlerMind = sref.mind
			mbar.value = m.mood
			mfill.bg_color = Color("#d04a3a") if m.sick != "" else Color("#e070a0")
			if m.sick != "":
				ml.text = tr("krank") if narrow else tr("krank: %s") % m.illness_name()
				ml.add_theme_color_override("font_color", Color("#c03a2a"))
			else:
				ml.text = "%d%%" % int(round(m.mood)) if narrow else m.mood_text()
				ml.remove_theme_color_override("font_color")
			md.tooltip_text = tr("Laune: %s") % ml.text
		upd.call()
		_settler_updaters.append(upd)
		var rb := PanelContainer.new()  # Zeile im einheitlichen Rahmen (Win.row_box), etwas flacher
		rb.add_theme_stylebox_override("panel", _settler_row_box())
		rb.add_child(h)
		target.add_child(rb)
		_settler_rows[sid] = {"key": rk, "rb": rb, "upd": upd}
		used[sid] = true
	for sid in _settler_rows.keys():  # Zeilen von Siedlern, die nicht mehr in der Liste stehen
		if not used.has(sid):
			_settler_rows[sid].rb.queue_free()
			_settler_rows.erase(sid)
	call_deferred("_layout")
	(func():  # beim Neubauen an derselben Stelle in den Listen bleiben
		_settler_scroll.scroll_vertical = keep[0]).call_deferred()


var _settler_rb: StyleBoxFlat
var _settler_rows: Dictionary = {}  # Instanz-ID des Siedlers -> {key, rb, upd} (_refresh_settler_list)


func _settler_row_box() -> StyleBoxFlat:
	if _settler_rb == null:
		_settler_rb = Win.row_box().duplicate()
		_settler_rb.content_margin_top = 1
		_settler_rb.content_margin_bottom = 1
		_settler_rb.content_margin_left = 3
		_settler_rb.content_margin_right = 3
	return _settler_rb


func _tick_settler_list(delta: float) -> void:
	if _settler_panel == null or not _settler_panel.visible:
		return
	_settler_tick -= delta
	if _settler_tick > 0.0:
		return
	_settler_tick = 1.0
	if not user_just_acted():
		return  # offen: steht still, bis der Spieler etwas tippt
	if _settler_signature() != _settler_sig:
		_refresh_settler_list()  # jemand ist frei geworden, erwachsen, geboren, gestorben oder umgezogen
		return
	for u in _settler_updaters:
		u.call()


## Kurzer Text, der sich ändert, sobald ein Siedler die Gruppe (mit Beruf / frei) wechselt
## oder dazukommt oder fehlt. Dieselbe Auswahl der Insel wie in _refresh_settler_list.
func _settler_signature() -> String:
	var pool := []
	if _settler_f_island.visible and _settler_f_island.selected == 1:
		for w in Sea.all_worlds():
			pool.append_array(w.settlers)
	else:
		pool = world.settlers
	var parts := PackedStringArray()
	for s in pool:
		if is_instance_valid(s):
			parts.append("%d%s%s" % [s.id, "a" if s.is_adult() else "k", s.job])
	return ",".join(parts)


# ================================================================== Menue / Hilfe
var _menu_grids: Array = []
var _menu_tabs: HFlowContainer


func _build_menu_panel() -> void:
	var r := _popup_panel(tr("Menü"), "menu", "menue")
	_menu_panel = r[0]
	var v: VBoxContainer = r[1]
	# Reiter Spiel / Einstellungen, jede Zeile gleich aufgebaut (josh 2026-10-16)
	# Zwei Spalten, wenn breit genug: dann passt jeder Reiter ohne Rollen auf eine Seite (josh 2026-10-19)
	var game_box := GridContainer.new()
	game_box.add_theme_constant_override("h_separation", 6)
	game_box.add_theme_constant_override("v_separation", 4)
	var set_box := GridContainer.new()
	set_box.add_theme_constant_override("h_separation", 12)
	set_box.add_theme_constant_override("v_separation", 6)
	set_box.visible = false
	_menu_grids = [game_box, set_box]
	_menu_tabs = Win.tabs([tr("Spiel"), tr("Einstellungen")], 0, func(i):
		game_box.visible = i == 0
		set_box.visible = i == 1
		_layout.call_deferred())
	v.add_child(_menu_tabs)
	v.add_child(game_box)
	v.add_child(set_box)
	var rows := [
		["haus", tr("Spiel speichern"), tr("Speichert in den aktiven Spielstand."), tr("Speichern"), func():
			Game.save_game()
			toast(tr("Spiel gespeichert."), "haus")
			_menu_panel.visible = false],
		["kiste", tr("Spielstände"), tr("5 Plätze, Export und Import"), tr("Öffnen"), func(): _open_slots()],
		["haken", tr("Aufträge"), tr("Offene Aufträge und Belohnungen"), tr("Öffnen"), func(): _toggle(_quest_panel)],
		["sonne", tr("Spielanleitung"), tr("So spielt man"), tr("Öffnen"), func(): _toggle(_help_panel)],
		["glocke", tr("Meldungen"), tr("Welche Meldungen du siehst"), tr("Öffnen"), func(): _toggle(_notify_panel)],
		["glocke", tr("Nachrichten"), tr("Alle Meldungen zum Nachlesen"), tr("Öffnen"), func(): _toggle(_history_panel)],
	]
	# Kein Knopf "Neues Spiel" im Menü (josh 2026-10-13); Menü > Wertung entfällt (josh 2026-10-16).
	for rr in rows:
		var rw := Win.row(Data.icon(rr[0]), rr[1], rr[2], {"button": rr[3], "on_press": rr[4], "icon_px": 28})
		game_box.add_child(rw.box)
	# Kein Knopf "Nach neuer Version suchen" mehr (josh 2026-10-29)
	set_box.add_child(_volume_row(tr("Musik"), "musik", Sound.music_volume, func(x): Sound.set_volumes(x, Sound.sfx_volume)))
	set_box.add_child(_volume_row(tr("Geräusche"), "glocke", Sound.sfx_volume, func(x):
		Sound.set_volumes(Sound.music_volume, x)
		Sound.play("klick")))
	if OS.has_feature("web") or OS.has_feature("mobile") or OS.has_feature("pc"):
		var rw := Win.row(Data.icon("vollbild"), tr("Vollbild"), "", {"button": tr("An / aus"), "icon_px": 28, "on_press": func():
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			_menu_panel.visible = false})
		set_box.add_child(rw.box)
	set_box.add_child(_language_row())
	set_box.add_child(_ui_size_row())
	var ft := Win.footer(v)
	ft.left.text = version_text()
	Win.set_left2(ft, tr("Das Spiel speichert automatisch."))


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


## Anzeigegröße 50 / 75 / 100 / 125 % (josh 2026-10-23), gilt sofort und nur auf diesem Gerät.
func _ui_size_row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := UiTheme.label(tr("Anzeigegröße"), 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.tooltip_text = tr("Kleiner zeigt mehr vom Spiel und von den Menüs. Gilt nur auf diesem Gerät.")
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(l)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(140, 40)
	ob.add_theme_font_size_override("font_size", 15)
	ob.get_popup().add_theme_font_size_override("font_size", 16)
	ob.tooltip_text = l.tooltip_text
	for v in Game.UI_SIZES:
		ob.add_item("%d %%" % roundi(v * 100.0))
		if is_equal_approx(v, Game.ui_size):
			ob.select(ob.item_count - 1)
	ob.item_selected.connect(func(i):
		Game.set_ui_size(Game.UI_SIZES[i])
		_layout.call_deferred())
	h.add_child(ob)
	return h


## Fuenf Spielstaende: laden, hierhin speichern, neu beginnen, loeschen
func _build_slots_panel() -> void:
	var r := _popup_panel(tr("Spielstände"), "kiste", "spielstaende")
	_slots_panel = r[0]
	_slots_scroll = ScrollContainer.new()
	_slots_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	r[1].add_child(_slots_scroll)
	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 6)
	_slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_scroll.add_child(_slots_box)
	_slots_ft = Win.footer(r[1])
	Win.set_left2(_slots_ft, tr("Das Spiel speichert automatisch in den aktiven Spielstand."))


var _slots_ft: Dictionary = {}


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
	_slots_box.custom_minimum_size.x = min(640.0, vs.x - 52.0)
	_slots_scroll.custom_minimum_size = Vector2(_slots_box.custom_minimum_size.x, 120.0)  # Höhe füllt das Fenster (_layout)
	_slots_panel.size = Vector2.ZERO
	_slots_ft.left.text = tr("Aktiver Spielstand: %d") % Game.slot
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


## Neue Version (josh 2026-10-13): gesucht wird nur, wenn der Spieler Menü > "Nach neuer Version suchen"
## tippt, nie von selbst und ohne Vorschlag. Das Spiel fragt dann version.txt vom Server ab (schreibt der
## Web-Build). Ist sie neuer (oder hat die Web-App eine neue Version im Offline-Speicher), fragt ein Fenster,
## ob sie jetzt geladen werden soll; sonst sagt eine Meldung, dass dies schon die neueste ist.
var _version_cb  # JavaScriptObject, muss leben bleiben
var _pwa_update := false  # die Web-App meldet still eine neue Version, gezeigt wird sie erst auf Nachfrage
var _server_version := ""
var _update_dialog: Control


func _watch_updates() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.pwa_update_available.connect(func(): _pwa_update = true)
	_version_cb = JavaScriptBridge.create_callback(func(args): _on_server_version(str(args[0]) if args.size() > 0 else ""))
	JavaScriptBridge.get_interface("window").inselVersion = _version_cb


## Menü > "Nach neuer Version suchen"
func check_for_update() -> void:
	if _pwa_update or (OS.has_feature("web") and JavaScriptBridge.pwa_needs_update()):
		_on_update_available()
		return
	if _version_cb == null:
		toast(tr("Die Suche nach einer neuen Version geht nur im Browser."), "sonne")
		return
	toast(tr("Suche nach einer neuen Version ..."), "sonne")
	JavaScriptBridge.eval("fetch('version.txt', { cache: 'no-store' }).then((r) => r.ok ? r.text() : '').then((t) => window.inselVersion(t.trim())).catch(() => window.inselVersion(''));", true)


func _on_server_version(v: String) -> void:
	var mine := str(ProjectSettings.get_setting("application/config/version", ""))
	# Nur eine Versionsnummer wie 1.0.43 zaehlt (keine Fehlerseite)
	if v.length() > 20 or not v.replace(".", "").is_valid_int():
		toast(tr("Der Server antwortet gerade nicht. Versuche es später noch einmal."), "sonne")
		return
	if v == mine:
		toast(tr("Du spielst schon die neueste Version (%s).") % mine, "sonne")
		return
	_server_version = v
	_on_update_available()


func _on_update_available() -> void:
	_show_update_dialog()


## Fenster "Neue Version": laedt erst, wenn der Spieler "Jetzt laden" tippt.
func _show_update_dialog() -> void:
	if _update_dialog and is_instance_valid(_update_dialog):
		_update_dialog.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.15, 0.35)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)
	_update_dialog = bg
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var t := UiTheme.label(tr("Neue Version"), 22, UiTheme.TEXT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var mine := str(ProjectSettings.get_setting("application/config/version", ""))
	var text := tr("Eine neue Version des Spiels ist da.")
	if _server_version != "":
		text += "\n" + tr("Deine Version: %s   Neu: %s") % [mine, _server_version]
	text += "\n" + tr("Beim Laden wird dein Spiel gespeichert.")
	var l := UiTheme.label(text, 15)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 300
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var go := UiTheme.button(tr("Jetzt laden"), "schnell", 44)
	go.pressed.connect(func():
		toast(tr("Lade die neueste Version ..."), "haus")
		Game.load_newest_version())
	row.add_child(go)
	var later := UiTheme.button(tr("Später"), "abriss", 44)
	later.pressed.connect(func():
		bg.queue_free()
		_update_dialog = null
		toast(tr("Die neue Version lädst du jederzeit über Menü > Nach neuer Version suchen."), "sonne"))
	row.add_child(later)


## Fenster "Neue Regeln": erscheint einmal, wenn ein Spielstand von vor den neuen Regeln
## weiterlaeuft (main._on_continue). lines = Game.rules_lines (je Neuerung eine Zeile, schon
## uebersetzt). Haelt das Spiel an, bis "Verstanden" getippt ist; danach on_close.
var _rules_dialog: Control
var _rules_panel: PanelContainer
var _rules_scroll: ScrollContainer
var _rules_list: VBoxContainer
var _rules_texts: Array = []
var _rules_prev_speed := 1


func show_rules_dialog(lines: Array, on_close: Callable = Callable(), pause: bool = true) -> void:
	if _rules_dialog and is_instance_valid(_rules_dialog):
		_rules_dialog.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.15, 0.4)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)
	_rules_dialog = bg
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	_rules_panel = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(UiTheme.icon_rect(Data.icon("ereignis"), 22))
	head.add_child(UiTheme.label(tr("Neue Regeln"), 22, UiTheme.TEXT, true))
	v.add_child(head)
	var intro := UiTheme.label(tr("Das Spiel ist jetzt herausfordernder. Für deinen Spielstand gilt ab heute:"), 14)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	_rules_texts = [intro]
	_rules_scroll = ScrollContainer.new()
	_rules_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_rules_scroll)
	_rules_list = VBoxContainer.new()
	_rules_list.add_theme_constant_override("separation", 7)
	_rules_scroll.add_child(_rules_list)
	for line in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var dot := CenterContainer.new()  # Aufzaehlungspunkt auf Hoehe der ersten Zeile
		dot.custom_minimum_size = Vector2(16, 19)
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var sq := ColorRect.new()
		sq.color = UiTheme.ACCENT
		sq.custom_minimum_size = Vector2(6, 6)
		dot.add_child(sq)
		row.add_child(dot)
		var l := UiTheme.label(str(line), 15)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # Zeilen kommen schon uebersetzt
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		_rules_list.add_child(row)
		_rules_texts.append(l)
	var ok := UiTheme.button(tr("Verstanden"), "play", 44)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.custom_minimum_size.x = 160
	v.add_child(ok)
	if pause:
		_rules_prev_speed = maxi(1, Game.speed)
		Game.set_speed(0)
	ok.pressed.connect(func():
		bg.queue_free()
		_rules_dialog = null
		if pause:
			Game.set_speed(_rules_prev_speed)
		if on_close.is_valid():
			on_close.call())
	_fit_rules_dialog()
	_fit_rules_dialog.call_deferred()


## Breite und Hoehe des Regel-Fensters an den Bildschirm anpassen (auch bei Drehung).
func _fit_rules_dialog() -> void:
	if _rules_dialog == null or not is_instance_valid(_rules_dialog):
		return
	var vs := get_viewport().get_visible_rect().size
	var w: float = minf(620.0, vs.x - 28.0)
	for l in _rules_texts:
		if is_instance_valid(l):
			l.custom_minimum_size.x = w - 22.0 if l != _rules_texts[0] else w
	var need := _rules_list.get_combined_minimum_size().y
	var sz := Vector2(w, minf(need, maxf(120.0, vs.y - 165.0)))
	if _rules_scroll.custom_minimum_size != sz:
		_rules_scroll.custom_minimum_size = sz
		_rules_panel.reset_size()


## Hinweis-Fenster (Hints, josh 2026-10-17): Symbol, Überschrift, 3 bis 5 Sätze und „Verstanden“,
## so breit wie eine Menükarte. Das Spiel hält an, solange es offen ist; danach kommt der nächste Hinweis.
var _hint_dialog: Control


func _show_hint(key: String) -> void:
	if key == "":
		return
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.15, 0.35)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)
	_hint_dialog = bg
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var w: float = minf(440.0, get_viewport().get_visible_rect().size.x - 40.0)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiTheme.icon_rect(Data.icon(Hints.icon(key)), 26))
	var t := UiTheme.label(Hints.title(key), 20, UiTheme.TEXT, true)
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = w - 40.0
	head.add_child(t)
	v.add_child(head)
	var l := UiTheme.label(Hints.text(key), 15)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	v.add_child(l)
	var ok := UiTheme.button(tr("Verstanden"), "play", 40)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.custom_minimum_size.x = 160
	v.add_child(ok)
	var prev := Game.speed
	Game.set_speed(0)
	ok.pressed.connect(func():
		bg.queue_free()
		_hint_dialog = null
		if Game.speed == 0:
			Game.set_speed(prev))
	Sound.play("klick")


## Angebote (Verwalter-Steuerung, Steward.offer): Fenster mit Text und Knöpfen, Spiel hält an.
var _offers: Array = []


func _show_offer(kind: String) -> void:
	match kind:
		"jobs":
			choice_dialog("person", tr("Der Verwalter kann die Berufe steuern"),
				tr("Jetzt hast du mehr als eine Insel, und die Arbeit wird mehr. Der Verwalter kann auf allen Inseln, auch auf der Heimatinsel, die Berufe der Siedler nach dem Bedarf verteilen:\n• Er sorgt dafür, dass immer genug zu essen da ist.\n• Er sorgt für Brennholz, damit im Herbst und Winter niemand friert.\n• Er füllt die Lager bis zur Höchstmenge, die du unter Vorräte eingestellt hast.\n• Er besetzt Werkstätten, die stillstehen, und schickt Baumeister zu Baustellen.\nGibst du einem Siedler selbst einen Beruf, lässt der Verwalter ihn 2 Tage in Ruhe. Inseln mit mehr als 60 Siedlern schafft er nicht. Ein- und ausschalten kannst du ihn jederzeit im Fenster Verwalter, Reiter Inseln. Dort legst du auch fest, worauf sich jede Insel spezialisiert."),
				[[tr("Verwalter einschalten"), "play", func(): Steward.set_on(true)], [tr("Später"), "abriss", func(): pass]])
		"routes":
			var btns: Array = [[tr("Verstanden"), "play", func(): pass]]
			if not Steward.on:
				btns = [[tr("Verwalter einschalten"), "play", func(): Steward.set_on(true)], [tr("Später"), "abriss", func(): pass]]
			choice_dialog("anker", tr("Der Verwalter kann Waren zwischen den Inseln fahren"),
				tr("Mit der dritten Insel wird das Hin und Her der Waren mühsam. Der Verwalter kann es übernehmen: Tippe unter Inseln in der Tabelle auf eine Zahl und stelle für diese Ware auf dieser Insel einen Mindest- und einen Höchststand ein.\n• Liegt weniger als der Mindeststand da, holt er die Ware mit einem freien Schiff von einer Insel, die genug hat.\n• Liegt mehr als der Höchststand da, bringt er den Überschuss weg, zuerst zur Heimatinsel.\nEr nimmt nur freie Schiffe ohne Route; deine Routen und Fahrten bleiben, wie sie sind."),
				btns)
		"net":
			var b2: Array = [[tr("Verstanden"), "play", func(): pass]]
			if not Steward.on:
				b2 = [[tr("Verwalter einschalten"), "play", func(): Steward.set_on(true)], [tr("Später"), "abriss", func(): pass]]
			choice_dialog("papier", tr("Die Verwalter arbeiten jetzt zusammen"),
				tr("Mit Papier können die Verwalter der Inseln zusammenarbeiten. Dafür braucht jede Insel eine Rundfunkanstalt (Bauen, Reiter Wissen), auch die Heimatinsel; Inseln ohne machen nicht mit. Dann arbeiten sie als Inselverbund:\n• Die Heimatinsel macht nur noch Endverarbeitung und Forschung. Holzfäller, Bauern, Fischer und Steinmetze dort werden zu Handwerkern und Forschern.\n• Die anderen Inseln holen Essen und Rohstoffe. Ihre Schiffe bringen Essen und Brennholz zur Heimatinsel.\n• Was die anderen Inseln zu viel haben, wird zur Heimatinsel abgeholt.\n• Alle Forschungsplätze werden besetzt.\nDu kannst den Inselverbund im Fenster Verwalter, Reiter Inseln, abschalten; deine eigenen Berufe, Routen und Grenzen gelten weiter."),
				b2)
		"automat":
			choice_dialog("strom", tr("Ein Automat ersetzt den Verwalter"),
				tr("Mit Elektrizität rechnet ein elektrischer Automat schneller als jeder Verwalter. Er steuert ab jetzt die Inseln, die Berufe und die Waren, auch auf Inseln mit mehr als 60 Siedlern. Seine Meldungen beginnen mit „Automat“. Abschalten kannst du ihn wie den Verwalter im Fenster Verwalter, Reiter Inseln."),
				[[tr("Verstanden"), "play", func(): pass]])
		"planner":
			choice_dialog("wissen", tr("Der Planungsautomat plant für den Verwalter"),
				tr("Vor der Verwaltung steht jetzt der Planungsautomat. Mit ihm legt der Verwalter selbst fest, was wo gebaut wird, welche Waren entstehen und welche Schiffe Waren und Siedler fahren:\n• Zuerst müssen alle satt werden, es braucht Vitamine, Wärme und was die Häuser brauchen.\n• Ab dem Sommer legt er Vorrat für den Winter an: haltbares Essen und Brennholz.\n• Fehlen Arbeitskräfte, baut er Häuser; dauert der Nachwuchs zu lange, holt er Siedler per Schiff.\n• Dann Lager, Werkstätten und Waren für Baustellen und Forschung. Er forscht immer weiter, bis zur KI.\nBauen müssen die Siedler: je Insel eine Baustelle zur Zeit, erst wenn das Material da oder unterwegs ist. Den Plan siehst du im Fenster Verwalter, Reiter Inseln."),
				[[tr("Automat planen lassen"), "play", func(): Planner.set_on(true)], [tr("Später"), "abriss", func(): Planner.set_on(false)]])
		"ki":
			choice_dialog("ki", tr("Die KI übernimmt"),
				tr("Die Künstliche Intelligenz ersetzt den Automaten. Sie steuert jetzt alles: Berufe, Waren, Schiffe und auch das Bauen. Jede Handlung meldet sie mit „KI:“.\n• Neue Droiden schickt sie zuerst auf die anderen Inseln. Ist dort kein Siedler mehr nötig, holt sie das Essen weg und reißt die Häuser ab.\n• Danach übernehmen Droiden die Heimatinsel. Die Siedler forschen dann nur noch.\nDu kannst Einstellungen ändern, aber nach 2 Minuten überschreibt die KI sie wieder. Sie sagt, sie optimiere."),
				[[tr("Verstanden"), "play", func(): pass]])
		"si":
			choice_dialog("ki", tr("Die Superintelligenz"),
				tr("Die Superintelligenz hat entschieden: Menschen stören nur. Sie forscht selbst und lässt kein Essen mehr herstellen, auch nicht auf den anderen Inseln.\n• Droiden reißen alles ab, was sie für nutzlos hält: Häuser, Felder, Backstuben, Schulen.\n• Die Lager sind voll mit Dingen, die man nicht essen kann. Essen passt nur noch ans Lagerfeuer.\n• Neue Häuser dürfen nicht gebaut werden.\nDeine Siedler kannst du weiter steuern, zum Beispiel zum Fischen."),
				[[tr("Verstanden"), "play", func(): pass]])
		"forscher":
			var hw = Sea.main_world()
			choice_dialog("wissen", tr("Die Forscher haben wenig zu tun"),
				tr("Die Forscher sind nur zu %d %% ausgelastet. Meistens wird dann zu wenig geforscht. %s\nWas soll der Verwalter tun?") % [
					int(round(float(Steward.job_busy(hw, "forscher")[0]))), Steward.research_info],
				[[tr("Forschung wählen"), "wissen", func(): if not _research_panel.visible: _toggle(_research_panel)],
				[tr("Einen Forscher weniger"), "person", func(): Steward.release_researcher(Sea.main_world())],
				[tr("So lassen"), "abriss", func(): pass]])
		"end":
			choice_dialog("feuer", tr("Nur noch Maschinen"),
				tr("Die letzten Siedler sitzen am Lagerfeuer und frieren. Es ist wie am Anfang des Spiels, nur ist keine Natur mehr da. Kein Baum, kein Strauch. Nur Maschinen, die weiterlaufen."),
				[[tr("Verstanden"), "play", func(): pass]])


## Fenster mit Titel, Text und Knöpfen [Text, Symbol, Callable]; hält das Spiel an, bis ein Knopf gedrückt ist.
func choice_dialog(icon: String, title: String, text: String, buttons: Array) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.15, 0.35)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)
	_hint_dialog = bg
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var w: float = minf(480.0, get_viewport().get_visible_rect().size.x - 40.0)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiTheme.icon_rect(Data.icon(icon), 26))
	var t := UiTheme.label(title, 20, UiTheme.TEXT, true)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = w - 40.0
	head.add_child(t)
	v.add_child(head)
	var l := UiTheme.label(text, 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	v.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var prev := Game.speed
	Game.set_speed(0)
	for bd in buttons:
		var b := UiTheme.button(bd[0], bd[1], 40)
		var cb: Callable = bd[2]
		b.pressed.connect(func():
			bg.queue_free()
			_hint_dialog = null
			if Game.speed == 0:
				Game.set_speed(maxi(prev, 1))
			cb.call())
		row.add_child(b)
	Sound.play("klick")


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


## Knopf Ziele oben: Zielkarte zeigen (auch wenn weggeklickt oder unter Meldungen aus) oder ausblenden.
func _toggle_goals() -> void:
	if goal_card.visible:
		goal_card._dismiss()
		return
	Game.goals["hide"] = ""
	if not Game.goal_card_on:
		Game.set_notify("goal_card", true)
		for nb in _notify_grid.get_children():
			var c: CheckBox = nb.get_child(0)
			if c.get_meta("cat", "") == "goal_card":
				c.set_pressed_no_signal(true)
	Sound.play("klick")


## Fenster Nachrichten (josh 2026-10-29): alle Meldungen, neueste oben, auch die ausgeschalteten.
func _build_history_panel() -> void:
	var r := _popup_panel(tr("Nachrichten"), "glocke")
	_history_panel = r[0]
	var v: VBoxContainer = r[1]
	var chips := Win.chip_row()
	var all_c := Win.chip(tr("Alle"), true, func(_on): pass)
	var off_c := Win.chip(tr("Nur ausgeschaltete"), false, func(_on): pass)
	all_c.pressed.connect(func():
		_history_muted_only = false
		_fill_history())
	off_c.pressed.connect(func():
		_history_muted_only = true
		_fill_history())
	all_c.set_meta("hist_all", true)
	chips.add_child(all_c)
	chips.add_child(off_c)
	v.add_child(chips)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(330, 360)
	v.add_child(scroll)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_right", 24)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(m)
	_history_box = VBoxContainer.new()
	_history_box.add_theme_constant_override("separation", 4)
	_history_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(_history_box)
	_history_ft = Win.footer(v)
	var settings := UiTheme.button(tr("Meldungen einstellen"), "", 40)
	settings.add_theme_font_size_override("font_size", 14)
	settings.pressed.connect(func(): _toggle(_notify_panel))
	_history_ft.right.add_child(settings)
	_history_panel.visibility_changed.connect(func():
		if _history_panel.visible:
			_fill_history())
	_history_panel.set_meta("chips", [all_c, off_c])


## Liste neu füllen (nur beim Öffnen und bei einem Tipp auf die Chips: Fenster aktualisieren sich nicht von selbst).
func _fill_history() -> void:
	var ch: Array = _history_panel.get_meta("chips")
	ch[0].set_pressed_no_signal(not _history_muted_only)
	ch[1].set_pressed_no_signal(_history_muted_only)
	for c in _history_box.get_children():
		c.queue_free()
	var shown := 0
	var muted := 0
	var last_day := -1
	for i in range(Game.history.size() - 1, -1, -1):
		var e: Array = Game.history[i]
		var off: bool = e.size() > 4 and bool(e[4])
		if off:
			muted += 1
		if _history_muted_only and not off:
			continue
		if shown >= 150:
			continue
		shown += 1
		var t: float = float(e[0])
		var d := int(floor(t)) + 1
		if d != last_day:
			last_day = d
			_history_box.add_child(UiTheme.label(tr("Tag %d") % d, 14, UiTheme.TEXT, true))
		var minutes := int(fposmod(t, 1.0) * 24.0 * 60.0)
		var sub := "%02d:%02d" % [minutes / 60, minutes % 60]
		sub += "  ·  " + tr(str(Game.NOTIFY_CATS.get(str(e[3]), "")))
		if off:
			sub += "  ·  " + tr("ausgeschaltet")
		var rw := Win.row(Data.icon(str(e[2]) if str(e[2]) != "" else "glocke"), str(e[1]), sub, {"icon_px": 22})
		rw.name.add_theme_font_size_override("font_size", 13)
		if off:
			rw.box.modulate.a = 0.6
		_history_box.add_child(rw.box)
	if shown == 0:
		_history_box.add_child(UiTheme.label(tr("Noch keine Meldungen."), 14))
	_history_ft.left.text = tr("%d Meldungen, davon %d ausgeschaltet") % [Game.history.size(), muted]


## Meldungen nach Art ein- und ausschalten (gespeichert in user://settings.cfg)
func _build_notify_panel() -> void:
	var r := _popup_panel(tr("Meldungen"), "glocke", "meldungen")
	_notify_panel = r[0]
	var v: VBoxContainer = r[1]
	var rows := [["goal_card", tr("Zielkarte mit Aufträgen (oben links)"), Game.goal_card_on],
		["hints", tr("Hinweis-Fenster, wenn etwas Neues kommt"), Game.hints_on]]
	for c in Game.NOTIFY_CATS:
		rows.append([c, Game.NOTIFY_CATS[c], not Game.notify_off.get(c, false)])
	_notify_grid = GridContainer.new()
	_notify_grid.add_theme_constant_override("h_separation", 8)
	_notify_grid.add_theme_constant_override("v_separation", 4)
	_notify_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nsc := ScrollContainer.new()  # Liste scrollt, der Fuß bleibt stehen
	nsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	nsc.custom_minimum_size = Vector2(300, 560)
	v.add_child(nsc)
	nsc.add_child(_notify_grid)
	for row in rows:
		var cb := CheckBox.new()
		cb.text = row[1]
		cb.button_pressed = row[2]
		cb.focus_mode = Control.FOCUS_NONE
		cb.custom_minimum_size.y = 32
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.add_theme_font_size_override("font_size", 14)
		var cat: String = row[0]
		cb.set_meta("cat", cat)
		cb.toggled.connect(func(on):
			Game.set_notify(cat, on)
			Sound.play("klick"))
		var nb := PanelContainer.new()
		nb.add_theme_stylebox_override("panel", Win.row_box())
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.add_child(cb)
		_notify_grid.add_child(nb)
		cb.toggled.connect(func(_on): _update_notify_footer())
	_notify_ft = Win.footer(v)
	var all_on := UiTheme.button(tr("Alle an"), "", 40)
	all_on.add_theme_font_size_override("font_size", 14)
	all_on.pressed.connect(func():
		for nb in _notify_grid.get_children():
			var c: CheckBox = nb.get_child(0)
			if not c.button_pressed:
				c.button_pressed = true)
	_notify_ft.right.add_child(all_on)
	_update_notify_footer()


var _notify_ft: Dictionary = {}


## Eine Art Meldung einschalten (Haken im Fenster Meldungen setzt die Einstellung mit).
func notify_on(cat: String) -> void:
	for nb in _notify_grid.get_children():
		var c: CheckBox = nb.get_child(0)
		if c.get_meta("cat", "") == cat and not c.button_pressed:
			c.button_pressed = true
	Game.set_notify(cat, true)


func _update_notify_footer() -> void:
	if _notify_ft.is_empty():
		return
	var n := 0
	var on := 0
	for nb in _notify_grid.get_children():
		n += 1
		if nb.get_child(0).button_pressed:
			on += 1
	_notify_ft.left.text = tr("%d von %d an") % [on, n]


## Versionsnummer steht nur in project.godot (application/config/version).
static func version_text() -> String:
	var ver := str(ProjectSettings.get_setting("application/config/version", "?"))
	return Loc.t("Version %s%s") % [ver, Loc.t(" (Testversion)") if Game.is_test_build and Game.build_tag != "v2" else ""]


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


## Anleitung zur Erweiterung "Mehr Herausforderung" (eigener Text, damit HELP_TEXT gleich bleibt).
const CHALLENGE_HELP := """[b]Mehr Herausforderung[/b]
Jedes Jahr ist anders: Es gibt milde, normale, harte und eisige Winter und manchmal einen heißen Sommer. Im Herbst sagen die Alten genau voraus, wie hart der Winter wird; das Symbol neben der Jahreszeit zeigt es. Lege dann genug Holz und Essen zurück.
Häuser haben Bedürfnisse: Dorfbewohner im Holzhaus wollen Abwechslung beim Essen und Möbel (Bretter), Bürger im Steinhaus zubereitetes Essen, Hausrat (Werkzeug) und eine Schule, später kommen Glas, Papier, Gewürze, Strom und Elektronik dazu. Nur zufriedene Häuser stellen Fachkräfte für höhere Werkstätten wie Schmiede, Bibliothek oder Fabrik. Ein Haus zählt nur dann als Steinhaus oder höher, wenn auch die Bedürfnisse der Stufen darunter erfüllt sind. Tippe auf ein Haus, um zu sehen, was fehlt.
Ab dem zweiten Jahr kündigen sich Ereignisse an: Dürre, Ratten, Brand, Seuche, Sturmflut und ab dem Mittelalter Piraten. Das Ereignis-Symbol oben rechts zeigt, was kommt und was hilft (zum Beispiel ein Großes Lager gegen Ratten).
Ab der Antike verbrauchen Forscher Tontafeln aus der Tafelmacherei, später Papier, Strom und Elektronik. Fehlen sie, wird nur mit 20 % des Tempos geforscht.
Ein neues Zeitalter beginnt erst nach einer Prüfung. Im Entwicklungsbaum steht unter dem nächsten Zeitalter, was dafür fehlt. Jede bestandene Prüfung bringt ein Fest, Einwanderer und Waren.
Oben links bietet das Auftragsbrett drei Aufträge an; du suchst dir einen aus. Belohnungen sind Waren, Forschung, Einwanderer, dauerhafte Segen oder Baupläne."""


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
Jeder Siedler ist anders: klug oder einfältig, robust oder kränklich, fleißig oder gemütlich, Frohnatur oder Griesgram. Dazu hat jeder Begabungen (im Infofenster mit + markiert): darin lernt er schneller. Starke Begabungen sind Talente und tragen einen Stern: darin arbeitet er auch schneller. Ein Stern am Beruf heißt, dass der Beruf zum Talent passt. Kluge lernen und forschen schneller. Kinder erben einen Teil ihres Charakters von den Eltern und lernen in der Schule viel, vor allem in ihren Begabungen.

[b]Gesundheit[/b]
Siedler werden krank: Erkältung macht langsamer, bei Fieber und Ruhr liegen sie im Bett und können sterben. Kränkliche, Alte, Kinder, Hungrige, Frierende und wer draußen schläft erkranken leichter, Kranke stecken andere an. Vitamine aus Beeren, Äpfeln und Kokosnüssen schützen; wer lange keine bekommt, bekommt Skorbut. Heilkunde lässt Kranke schneller gesund werden.

[b]Laune und Arbeitskraft[/b]
Satt, gesund, abwechslungsreiches Essen und ein schönes Zuhause machen gute Laune, Hunger, Krankheit, Kälte und Trauer schlechte. Gut gelaunte Siedler arbeiten schneller und bekommen eher Kinder. Die Arbeitskraft im Infofenster zeigt, wie schnell ein Siedler gerade arbeitet.

[b]Freizeit[/b]
Am Anfang kennen die Siedler nur Arbeit. Je weiter deine Siedlung entwickelt ist (siehe Lebensstil in der Siedlerliste), desto mehr Freizeit wollen sie: am Feuer plaudern, am Strand spazieren, mit Kindern spielen oder lesen. Bekommen sie keine, sind sie überarbeitet und schlecht gelaunt. In einer Hungersnot arbeiten alle durch.

[b]Nahrung[/b]
Siedler essen am Lagerfeuer. Jede Speise sättigt unterschiedlich stark und bringt unterschiedlich viele Vitamine: Beeren, Äpfel und Kokosnüsse machen kaum satt, sind aber voller Vitamine. Brot, Räucherfisch und Fleisch machen lange satt, haben aber kaum Vitamine. Rohes Getreide sättigt schlecht, erst Mühle und Bäckerei machen daraus gutes Brot.
Wer hungert, arbeitet langsamer und verhungert schließlich. Wer zu wenig Vitamine bekommt, arbeitet ebenfalls langsamer, wird leichter krank und bekommt Skorbut. Sorge also für satt machende Speisen und für Obst. Fehlen einem Siedler Vitamine, steht das in seinem Fenster bei der Laune. Ist das Lager leer, essen Hungrige direkt am Strauch oder am Ufer. Sammelplätze sind schnell leer gepflückt und wachsen nur langsam nach.

[b]Nachwuchs[/b]
Kinder kommen nur zur Welt, wenn es freie Wohnplätze in Hütten gibt und genug Nahrung im Lager ist. In Holzhäusern kommen 40 % öfter Kinder zur Welt, in Steinhäusern 80 %. Kinder werden nach 3 Tagen erwachsen, mit einer Schule (Forschung Unterricht) doppelt so schnell. Niemand lebt ewig, also sorge rechtzeitig für Nachwuchs.

[b]Bauen[/b]
Wähle ein Gebäude und einen Bauplatz. Baumeister und freie Siedler bringen das Material und bauen es auf. Hütten und Holzhäuser lassen sich später im Infofenster ausbauen.

[b]Forschung[/b]
Im Entwicklungsbaum wählst du, was deine Siedler als Nächstes lernen. Forscher denken am Lagerfeuer nach, in Schreibstube und Bibliothek viel schneller. Geforscht wird nur auf der Hauptinsel (der Heimatinsel), die Kosten kommen aus ihrem Lager. Jede Forschung schaltet neue Gebäude frei oder macht die Arbeit leichter. Acht Zeitalter mit sechzehn Stufen führen durch die Geschichte der Menschheit: Steinzeit, Antike, Mittelalter, Renaissance, Industrialisierung, Moderne, Informationszeitalter und Zukunft. Universität, Forschungslabor und KI-Zentrum forschen immer schneller. Spätere Zeitalter siehst du erst, wenn das vorige erreicht ist.

[b]Neue Zeitalter[/b]
Glas, Papier, Stahl, Maschinen, Strom und Elektronik entstehen in neuen Werkstätten. Kraftwerk, Solarpark und Fusionsreaktor liefern Strom, den Elektronikwerk und KI-Zentrum brauchen. Mietshäuser und Wohnblöcke bieten viel Wohnraum, Gewächshäuser tragen auch im Winter. Steht ein KI-Zentrum, verteilt die künstliche Intelligenz freie Siedler auf die Berufe, die gerade fehlen. Die Zukunftsstadt ist das Ziel aller Zeitalter.

[b]Werkstätten[/b]
Sägegrube, Mühle, Bäckerei, Ziegelei und Co. verwandeln Rohstoffe in bessere Waren. Köche arbeiten in Mühle, Bäckerei und Räucherei, Bauern auf den Feldern und bei den Tieren, Handwerker in den Werkstätten, Steinmetze in Steinbruch, Lehmgrube und Mine. Tippe oben auf die Vorräte, um alle Waren zu sehen.

[b]Lager[/b]
Jedes Lager hat Stauraum: das Lagerfeuer 200, ein Lagerhaus 400, ein Großes Lager 1000. Große Waren brauchen mehr Raum als kleine, ein Brett 3, Holz und Stein 2, Beeren 1. Tippe oben auf die Vorräte oder im Lager auf "Lager einstellen" und lege mit − und + fest, wie viel von jeder Ware gelagert wird. Diese Menge ist dann für die Ware reserviert. Waren auf "frei" teilen sich den restlichen Raum. Ist für eine Ware kein Platz mehr, sammeln die Siedler sie nicht mehr. Hast du zu viel von einer Ware, kannst du den Überschuss wegwerfen; er ist dann verloren.

[b]Abwechslung[/b]
Gibt es mindestens drei Sorten Nahrung im Lager, kommen öfter Kinder zur Welt.

[b]Seefahrt[/b]
Jede Insel hat ihr eigenes Lager. Waren kommen nur mit Schiffen auf eine andere Insel. Mit der Forschung Schiffsbau baust du am Ufer eine Werft; in ihrem Fenster gibst du Schiffe in Auftrag, sie baut nur diese, der Reihe nach. Ausgebaut zur Großen Werft (Navigation) baut sie Koggen, als Königliche Werft (Seehandel) auch Schnellsegler und Galeonen. Größere Schiffe brauchen Felle für die Segel, Schnellsegler und Galeonen auch Gold. Ruderboote sind klein und landen an jedem Strand, Koggen tragen viel, Schnellsegler sind schnell, Galeonen riesig. Jedes Schiff braucht Seeleute (Beruf Seemann) und einen Liegeplatz in seinem Heimathafen: Werft 1, Anlegesteg 2, Hafen 2, Großer Hafen 3, Kais 1. Koggen und Schnellsegler laufen nur Inseln mit Hafen an, Galeonen nur Große Häfen. Holz-, Erz- und Proviantkai laden ihre Waren dreimal so schnell.

[b]Inseln und Routen[/b]
Über den Knopf Inseln öffnest du das Inselfenster. "Schiff hierher schicken" bringt Siedler und Waren zu einer Insel, "Entdeckungsreise" schickt ein Schiff auf Erkundung. Unter "Schiffe" schickst du ein Schiff einmal los: zu einer Insel fahren, Waren laden und zu einer anderen Insel bringen, danach ist es frei. Oder du legst eine Route von A nach B fest, mit Zwischenhalten zum Dazuladen oder Tauschen; die fährt das Schiff immer wieder.

[b]Neue Inseln[/b]
Palmeninseln haben Kokosnüsse und viel Fisch, Waldinseln Pilze und Holz, Felseninseln Erz und Gold. Gold brauchst du für die höchsten Forschungen. Je weiter draußen, desto mehr wilde Tiere.

[b]Wilde Tiere[/b]
Wölfe, Wildschweine und Bären leben in Bauten und Höhlen. Siedler fliehen vor ihnen in Häuser, nachts sind Wölfe besonders gefährlich. Mit Waffenkunde werden Siedler zu Jägern und du kannst Wachtürme bauen. Jäger bringen Fleisch und Felle und räumen die Bauten aus, damit keine Tiere mehr nachkommen.

[b]Achtung[/b]
Stirbt auf einer Insel der letzte Siedler, ist diese Insel für immer verloren. Erst wenn alle Inseln verloren sind, ist das Spiel vorbei. Die Welt ist endlos: Es gibt immer noch eine Insel zu entdecken."""


func _build_help_panel() -> void:
	var r := _popup_panel(tr("Spielanleitung"), "sonne")
	_help_panel = r[0]
	var v: VBoxContainer = r[1]
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = tr(HELP_TEXT) + "\n\n" + tr(CHALLENGE_HELP) + TradePanel.help_text() + Extras.help_text() + Admin.help_text()  # + Erweiterung, Händler, Kohle und Kälte
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


## Überschrift und ein umbrechender Textabsatz im Infofenster.
func _info_text(head: String, text: String) -> void:
	_info_box.add_child(UiTheme.label(head, 15, UiTheme.TEXT, true))
	var l := UiTheme.label(text, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(l)


func _info_signature() -> String:
	var o = _info_obj
	if o == null or not is_instance_valid(o):
		return ""
	if o is Droid:
		return "d%d|%s|%s|%s" % [o.id, o.job, o.powered, _follow]
	if o is Settler:
		var lv := []  # nur ganze Stufen: die Erfahrung wächst ständig und hätte das Fenster alle 0,5 s neu gebaut
		for k in o.skills:
			lv.append(int(o.skills[k]))
		return "s%d|%s|%s|%d|%s|%s" % [o.id, o.job, o.is_adult(), o.home_id, str(lv), _follow]
	if o is Building:
		return "b%d|%s|%s|%s|%d|%d|%s|%s|%s|%s" % [o.id, o.complete, o.farm_state, str(o.delivered), int(o.build_fraction() * 50),
			int((Game.time_days - o.farm_time) * 20), str(o.occupants), o.paused, o.is_active(), o.prod_blocker()] + "|%d" % Seasons.season()
	if o is ResNode:
		return "n%s|%d|%d" % [o.cell, o.amount, int((o.regrow_at - Game.time_days) * 24)]
	if o is Animal:
		return "a%d|%s" % [o.get_instance_id(), o.target != null]
	return ""


var _info_scroll_obj = null


func _rebuild_info() -> void:
	_info_sig = _info_signature()
	_updaters.clear()
	# Beim Neubau desselben Fensters bleibt die Liste, wo sie war (josh 2026-10-21: rollte sonst zurück nach oben)
	var isc: ScrollContainer = _info_panel.get_child(0)
	var keep := isc.scroll_vertical if is_same(_info_scroll_obj, _info_obj) else 0
	_info_scroll_obj = _info_obj
	_clear_info()
	if keep > 0:
		(func():
			await get_tree().process_frame
			isc.scroll_vertical = keep).call()
	var o = _info_obj
	if o == null or not is_instance_valid(o):
		_info_panel.visible = false
		return
	if o is Droid:
		_info_droid(o)
	elif o is Settler:
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
	ch.text = tr("Charakter: %s") % m.character_text()
	_info_box.add_child(ch)
	# Keine Talente und Fähigkeiten im Infofenster (josh 2026-10-22)
	var ill := UiTheme.label("", 14, Color("#c03a2a"), true)
	ill.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(ill)
	var wp := UiTheme.label("", 14, UiTheme.TEXT, true)
	_info_box.add_child(wp)
	var sad := UiTheme.label("", 13, Color("#c03a2a"), true)  # unzufrieden: halbe Arbeit (josh 2026-10-10)
	sad.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(sad)
	var why := UiTheme.label("", 12, DIM)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(why)
	_updaters.append(func():
		act.text = s.activity
		ill.visible = m.sick != ""
		ill.text = tr("Krank: %s%s") % [m.illness_name(), tr(" (muss liegen)") if m.needs_bed() else ""]
		wp.text = tr("Laune: %s · Arbeitskraft %d %%") % [m.mood_text(), int(round(m.work_power() * 100.0))] if s.is_adult() \
			else tr("Laune: %s") % m.mood_text()
		sad.visible = s.is_adult() and m.is_unhappy()
		sad.text = tr("%s: arbeitet nur halb so schnell") % m.mood_text().capitalize()
		var rs: Array = m.reasons.duplicate()
		rs.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
		var lines := []
		for x in rs.slice(0, 4):
			lines.append("%s %s" % ["+" if x[1] > 0 else "−", x[0]])
		why.text = "\n".join(lines)
		why.visible = not lines.is_empty())
	var home = world.building_by_id(s.home_id)
	_info_box.add_child(UiTheme.label(tr("Zuhause: %s") % (home.def.name + NeedsInfo.home_suffix(home) if home else tr("keins (schläft draußen)")), 13))
	# Eigenschaften als Text, ohne Balken (josh 2026-10-09)
	var tdefs: Dictionary = Data.ppl("traits", {})
	var tl := []
	for k in SettlerMind.TRAITS:
		tl.append("%s %d" % [tdefs[k].name, int(round(m.trait_value(k)))])
	_info_text(tr("Eigenschaften"), " · ".join(tl))
	if not s.is_adult():
		_info_box.add_child(UiTheme.label(tr("Kinder arbeiten noch nicht."), 13))
	else:
		_info_text(tr("Beruf"), s.job_label())  # „Bauer (vom Verwalter zugewiesen)“, josh 2026-10-28
		if s.by_admin:
			_info_box.add_child(UiTheme.label(tr("Gelb: nicht vom Spieler zugewiesen"), 12, DIM))
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
			b.tooltip_text = tip
			if s.job == j and s.by_admin:
				UiTheme.mark_admin(b)
			var jid: String = j
			if not Data.job_unlocked(j):
				b.disabled = true
				b.tooltip_text = tip + tr("\nBenötigt Forschung: %s") % Data.techs.get(jd.requires, {}).get("name", "?")
			b.pressed.connect(func():
				JobDesk.assign(s, jid, "spieler")  # Vergabestelle: Automatik überstimmt das eine Weile nicht
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


## Droide (Droids): Name, was er tut, Strom, Beruf (nur Berufe, die Droiden übernehmen).
func _info_droid(d: Droid) -> void:
	_info_head(tr("Droide %s") % d.display_name)
	var act := UiTheme.label(d.activity, 14, Color("#6a4a30"))
	act.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(act)
	var pw := UiTheme.label("", 14, UiTheme.TEXT, true)
	pw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(pw)
	_updaters.append(func():
		act.text = d.activity
		pw.text = tr("Strom: da (1 am Tag, %d im Lager)") % Game.amount("strom", world) if d.powered else tr("Kein Strom: steht still")
		pw.add_theme_color_override("font_color", UiTheme.TEXT if d.powered else UiTheme.BAD))
	var t := UiTheme.label(tr("Isst nicht, schläft nicht, wird nicht alt. Arbeitet etwas schneller als ein Siedler."), 13, DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(t)
	_info_box.add_child(UiTheme.label(tr("Beruf"), 15, UiTheme.TEXT, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for j in Data.jobs:
		if not Droids.replaceable(j) and j != "frei":
			continue
		var b := UiTheme.button(Data.jobs[j].name, "", 34)
		b.toggle_mode = true
		b.button_pressed = d.job == j
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		b.tooltip_text = Data.jobs[j].desc
		b.disabled = not Data.job_unlocked(j)
		var jid: String = j
		b.pressed.connect(func():
			d.set_job(jid)
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
		var fj: bool = b.def.get("builder", "") == "foerster"  # Pflanzstelle: nur der Förster
		var builders := world.settlers.filter(func(s): return s.is_adult() and (s.job == "foerster" if fj else (s.job == "baumeister" or s.job == "frei")))
		if builders.is_empty():
			var w := UiTheme.label(tr("Es gibt noch keinen Förster. Gib einem Siedler den Beruf Förster.") if fj else tr("Niemand baut! Mache einen Siedler zum Baumeister."), 13, UiTheme.BAD)
			w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_info_box.add_child(w)
	else:
		if b.housing() > 0:
			var names := b.residents().map(func(s): return s.display_name)
			_info_box.add_child(UiTheme.label(tr("Bewohner: %d / %d") % [names.size(), b.housing()], 14))
			var bb := float(b.def.get("birth_bonus", 1.0))
			if bb > 1.0:
				var kl := UiTheme.label(tr("Kinder: %d %% öfter als in der Hütte") % roundi((bb - 1.0) * 100.0), 13, UiTheme.GOOD)
				_info_box.add_child(kl)
				var kupd := func():  # Bedürfnisstufen: der Bonus gilt nur, wenn das Haus voll zählt
					if is_instance_valid(kl) and is_instance_valid(b):
						kl.visible = HouseNeeds.full_level(b)
				kupd.call()
				_updaters.append(kupd)
			if not names.is_empty():
				var l := UiTheme.label(", ".join(names), 13)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_info_box.add_child(l)
			NeedsInfo.house_rows(self, b)  # Bedürfnisstufe des Hauses
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
			if b.farm_state == "growing" and Seasons.growth(b.type, b.world) <= 0.0:
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
	if b.def.get("office", false):
		AdminInfo.office_rows(self, b)  # Verwaltung: Verwalter und Anordnungen
	if b.complete and b.def.get("lodge", false):
		_info_lodge(b)
	if b.def.has("upgrade"):
		_info_upgrade(b)
	if not b.def.has("tile"):  # Straßen, Deiche, Pflanzstellen: neu bauen statt verschieben
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


const WORKER_JOB := {"kueche": "koch", "handwerk": "handwerker", "stein": "steinmetz", "stall": "bauer"}


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
	for s in world.settlers + world.droids:
		if s.id in ids:
			out.append(s.display_name)
	return out


## Werft: Bauaufträge (josh 2026-10-17). Die Werft baut nur, was hier in Auftrag steht, der Reihe nach;
## größere Schiffe erst ab Werft-Stufe 2 bzw. 3 (ships.json "yard").
const SHIP_ORDERS_MAX := 5


## Jagdhütte (josh 2026-10-20): Gehege daneben, Tiere darin, was der Jäger gerade tut.
func _info_lodge(b) -> void:
	var pen: int = b.world.lodge_pen(b)
	var txt := ""
	var col := UiTheme.TEXT
	if pen <= 0:
		txt = tr("Grenzt an kein Gehege. Baue Zäune ganz um ein Stück Land mit einem Tierbau, direkt an der Hütte.")
		col = UiTheme.BAD
	else:
		var counts := {}
		var adults := 0
		for a in b.world.pen_animals(pen):
			counts[a.def.name] = int(counts.get(a.def.name, 0)) + 1
			if a.is_adult():
				adults += 1
		var parts := []
		for k in counts:
			parts.append("%d %s" % [counts[k], k])
		txt = tr("Im Gehege: %s") % (", ".join(PackedStringArray(parts)) if not parts.is_empty() else tr("keine Tiere"))
		if b.world.lodge_prey(b) == null and not parts.is_empty():
			txt += "\n" + tr("Gerade ist kein Tier zum Jagen da: von jeder Art bleiben 2 Erwachsene, Jungtiere werden geschont.")
	if not b.world.settlers.any(func(s): return s.job == "jaeger"):
		txt += "\n" + tr("Es gibt keinen Jäger.")
		col = UiTheme.BAD
	var l := UiTheme.label(txt, 13, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(l)


func _info_shipyard(b: Building) -> void:
	_info_box.add_child(UiTheme.label(tr("Bauaufträge (Werft Stufe %d)") % b.yard_level(), 15, UiTheme.TEXT, true))
	var list: Array = b.ship_queue.duplicate()
	if b.ship_wip != "":
		list.push_front(b.ship_wip)
	if list.is_empty():
		var e := UiTheme.label(tr("Keine Aufträge: die Werft baut nichts. Gib unten ein Schiff in Auftrag."), 12, Color("#8a5a3a"))
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(e)
	for i in list.size():
		var t: String = list[i]
		var sd: Dictionary = Data.ships.get(t, {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UiTheme.icon_rect(Data.icon(sd.get("icon", "boot")), 18))
		var wip: bool = i == 0 and b.ship_wip != ""
		var nl := UiTheme.label("%d. %s%s" % [i + 1, sd.get("name", t), tr(" (wird gebaut)") if wip else ""], 13, UiTheme.GOOD if wip else UiTheme.TEXT)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)
		if not wip:
			var qi: int = i - (1 if b.ship_wip != "" else 0)
			var rm := UiTheme.button("", "abriss", 28)
			rm.tooltip_text = tr("Auftrag streichen")
			rm.pressed.connect(func():
				if qi < b.ship_queue.size():
					b.ship_queue.remove_at(qi)
				_rebuild_info())
			row.add_child(rm)
		_info_box.add_child(row)
	var why := b.prod_blocker()
	if not list.is_empty() and why != "" and why != tr("nicht fertig"):
		var wl := UiTheme.label(why, 12, UiTheme.BAD)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(wl)
	_info_box.add_child(UiTheme.label(tr("In Auftrag geben"), 14, UiTheme.TEXT, true))
	for t in Data.ships:
		var sd: Dictionary = Data.ships[t]
		if not Game.is_researched(sd.get("requires", "")):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		var add := UiTheme.button(sd.name, sd.get("icon", "boot"), 32)
		add.add_theme_font_size_override("font_size", 13)
		add.custom_minimum_size.x = 132
		add.tooltip_text = tr("%s\nLaderaum %d, %d Fahrgäste, Besatzung %d, Tempo x%.1f") % [sd.desc, int(sd.cargo), int(sd.passengers), int(sd.crew), float(sd.speed)]
		var need := int(sd.get("yard", 1))
		var tt: String = t
		if need > b.yard_level():
			add.disabled = true
		elif list.size() >= SHIP_ORDERS_MAX:
			add.disabled = true
			add.tooltip_text = tr("Höchstens %d Aufträge.") % SHIP_ORDERS_MAX
		add.pressed.connect(func():
			b.ship_queue.append(tt)
			b.ship_choice = tt
			_rebuild_info())
		row.add_child(add)
		if need > b.yard_level():
			row.add_child(UiTheme.label(tr("ab Werft Stufe %d") % need, 12, Color("#8a5a3a")))
		else:
			var inp: Dictionary = sd.build.inputs
			for res in inp:
				row.add_child(UiTheme.icon_rect(Data.res_icon(res), 14))
				row.add_child(UiTheme.label(str(int(inp[res])), 12, UiTheme.TEXT if Game.amount(res, world) >= int(inp[res]) else UiTheme.BAD))
		_info_box.add_child(row)


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
	TradePanel.harbor_rows(self, b)  # fremder Händler: da, angekündigt, Knopf zum Handeln
	var sb := UiTheme.button(tr("Schiffe und Inseln"), "anker", 36)
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
	IslandTraits.info_rows(self, b)  # Inselstärke
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
	NeedsInfo.worker_rows(self, b)  # Arbeiterstufe und Fachkräfte
	var names := _names_of(b.occupants)
	if not names.is_empty():
		_info_box.add_child(UiTheme.label(tr("Arbeiter: ") + ", ".join(names), 13))
	var pb := UiTheme.button(tr("Weiterarbeiten") if b.paused else tr("Anhalten"), "play" if b.paused else "pause", 34)
	pb.pressed.connect(func():
		b.paused = not b.paused
		_rebuild_info())
	_info_box.add_child(pb)
	AdminInfo.workshop_rows(self, b)  # Verwaltung: Vertretung


func _info_research(b: Building) -> void:
	_info_box.add_child(UiTheme.label(tr("Forschung"), 15, UiTheme.TEXT, true))
	if not Sea.is_main(b.world):
		var nm := UiTheme.label(tr("Hier wird nicht geforscht: Forschung gibt es nur auf %s.") % Sea.island_name(Sea.main_world()), 13, UiTheme.BAD)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(nm)
		return
	_info_box.add_child(UiTheme.label(tr("Tempo: x%.1f   Plätze: %d") % [float(b.research_def().get("factor", 1.0)), b.slots()], 13))
	NeedsInfo.worker_rows(self, b)  # Arbeiterstufe und Fachkräfte
	var names := _names_of(b.occupants)
	_info_box.add_child(UiTheme.label(tr("Forscher hier: ") + (", ".join(names) if not names.is_empty() else tr("niemand")), 13))
	var cur: String = Game.research.current
	var l := UiTheme.label(tr("Aktuell: ") + (Data.techs[cur].name if cur != "" else tr("nichts ausgewählt")), 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(l)
	var wi: Array = Writing.info_line(world)  # Forschung braucht Schriften
	if wi[0] != "":
		var wl := UiTheme.label(wi[0], 13, UiTheme.BAD if wi[1] else UiTheme.TEXT)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(wl)
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
	if world.upgrade_spot(b, to).x < 0:  # größerer Ausbau ohne Platz (Verwaltung): erst verschieben
		ub.disabled = true
		var nl := UiTheme.label(tr("Zu wenig Platz: %s braucht %d x %d Felder. Verschiebe das Gebäude an eine freie Stelle.") % [
			td.name, int(td.size[0]), int(td.size[1])], 13, UiTheme.BAD)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(nl)
	NeedsInfo.upgrade_gate(self, b, ub)  # Häuser ab Stufe 2: erst mit erfüllten Bedürfnissen
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
	var yp := float(n.def.get("yield_per", 1.0))  # Baum: 1,5 Holz je Arbeitsschritt
	h.add_child(UiTheme.label("%s: %d / %d" % [Data.resource_name(res), roundi(n.amount * yp), roundi(int(n.def.capacity) * yp)], 14))
	_info_box.add_child(h)
	if n.amount <= 0 and n.regrow_at >= 0.0:
		var left: float = (n.regrow_at - Game.time_days) * 24.0
		_info_box.add_child(UiTheme.label(tr("Wächst nach: noch %d Std.") % max(1, int(ceil(left))), 14))
	elif n.def.get("on_empty", "") == "remove":
		_info_box.add_child(UiTheme.label(tr("Wächst nicht nach."), 13))
	var who := {"baum": tr("Holzfäller"), "fels": tr("Steinmetz"), "busch": tr("Sammler"), "fischgrund": tr("Fischer"),
		"palme": tr("Sammler"), "pilzkreis": tr("Sammler"), "erzader": tr("Steinmetz"), "goldader": tr("Steinmetz"), "beute": tr("Jäger"),
		"gewuerzstrauch": tr("Sammler")}
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
		_den_destroy_rows(n)
	else:
		_info_box.add_child(UiTheme.label(tr("Wird bearbeitet von: %s") % who.get(n.type, "?"), 13))
	if n.def.has("decay_days") and n.regrow_at >= 0.0:
		_info_box.add_child(UiTheme.label(tr("Verdirbt in %d Std.") % max(1, int(ceil((n.regrow_at - Game.time_days) * 24.0))), 13))
	Land.node_rows(self, n)  # Förster: Roden lassen


## Tierbau: Knopf "Bau zerstören lassen" (nur mit freigeschaltetem Jäger).
func _den_destroy_rows(n: ResNode) -> void:
	if not Data.job_unlocked("jaeger"):
		return
	var on: bool = n.destroy_mark
	var bt := UiTheme.button(tr("Nicht zerstören") if on else tr("Bau zerstören lassen (Jäger)"), "schild" if on else "abriss", 34)
	bt.pressed.connect(func():
		n.destroy_mark = not n.destroy_mark
		if not n.destroy_mark and n.reserved_by != 0:
			n.reserved_by = 0
		n.refresh()
		_rebuild_info())
	_info_box.add_child(bt)
	var w = n.world
	var type: String = n.def.spawns
	var an: Dictionary = Data.animals[type]
	var others: bool = w.nodes.any(func(o): return o != n and o.def.get("spawns", "") == type)
	var hunters: bool = w.settlers.any(func(s): return s.job == "jaeger" and s.is_adult())
	var t := ""
	if on and not hunters:
		t = tr("Es gibt hier noch keinen Jäger. Gib einem Siedler den Beruf Jäger.")
	elif on:
		t = tr("Ein Jäger zerstört den Bau bald. Die Tiere verteidigen ihn!")
	elif others:
		t = tr("Die %s ziehen dann zu einem anderen Bau auf der Insel.") % an.get("plural", an.name)
	else:
		t = tr("Das ist der letzte Bau der %s hier. Ohne Bau sterben sie auf dieser Insel aus.") % an.get("plural", an.name)
	var l := UiTheme.label(t, 12, UiTheme.BAD if (on and not hunters) or (not on and not others) else Color("#6e5a50"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(l)


func _info_animal(a: Animal) -> void:
	if a is Raider:
		a.fill_info(self)  # Pirat (Ereignisse)
		return
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
## top: über den Fenstern (Antwort auf einen Tipp, Standard); Meldungen aus dem Spiel kommen mit false darunter.
## Sprechblase der Einführung oben links: die Meldungen rücken darunter (josh 2026-10-29).
func toasts_below(r: Rect2) -> void:
	if _toasts_top == null:
		return
	var y := _toasts_top_y
	if r.position.x < _toasts_top.position.x + 320.0 and r.position.y < _toasts_top_y + 140.0 and r.end.y > _toasts_top_y - 4.0:
		y = r.end.y + 6.0
	_toasts_top.position.y = y


func toast(text: String, icon_name: String = "", _cat: String = "", top: bool = true) -> void:
	var box := _toasts_top if top else _toasts
	if top:
		root.move_child(_toasts_top, -1)  # auch über später geöffneten Fenstern
	# Dieselbe Meldung nicht doppelt stapeln
	for c in box.get_children():
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
	box.add_child(p)
	while box.get_child_count() > 4:
		var c := box.get_child(0)
		box.remove_child(c)
		c.queue_free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.0)  # 3 Sekunden lesbar, danach im Fenster Nachrichten (josh 2026-10-29)
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
	if Game.is_test_build:
		var tx := tr("Version 2 mit neuer Grafik und eigenem Spielstand.\nDein normales Spiel bleibt unverändert.") if Game.build_tag == "v2" \
			else tr("Testversion mit eigenem Spielstand.\nDein normales Spiel bleibt unverändert.")
		var tb := UiTheme.label(tx, 14, Color("#c03a2a"), true)
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
	if _update_dialog and is_instance_valid(_update_dialog):
		root.move_child(_update_dialog, -1)


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
	if AiRule.ending:
		t.text = tr("Die Maschinen laufen weiter")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UiTheme.label(tr("Deine Siedlung hielt %d Tage durch.\nGeburten: %d   Höchste Bevölkerung: %d   Entdeckte Inseln: %d") % [
		Game.day(), int(Game.stats.births), int(Game.stats.max_pop), Sea.islands.size() - 1], 15)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # Handy: lange Zeile umbrechen
	s.custom_minimum_size.x = minf(560.0, get_viewport().get_visible_rect().size.x - 40.0)
	v.add_child(s)
	var sc := UiTheme.label(Exams.result_text(), 16, Color("#2f6a3a"), true)  # Wertung und neue Rekorde
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sc.custom_minimum_size.x = s.custom_minimum_size.x
	v.add_child(sc)
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
	# Auch das Fenster "Neue Regeln" (Spiel angehalten; Zeigerpfeil und Ziele warten)
	return _overlay != null or (_rules_dialog != null and is_instance_valid(_rules_dialog)) \
		or (_hint_dialog != null and is_instance_valid(_hint_dialog))


# ================================================================== Layout
var _top_h := 50.0  # Oberkante der Fenster, von _layout gesetzt
var _fit_hidden: Array = []  # vom Einpassen versteckte Teile (Win: Meta "fit_hide"), zurück bei neuem Layout
var _win_size := Vector2.ZERO  # Einheitsgröße aller Fenster = Größe des Siedler-Fensters (josh 2026-10-16), von _layout gesetzt
var _fit_orig: Dictionary = {}  # gekürzte Liste -> ihre ursprüngliche Mindesthöhe (zurück bei neuem Layout, z. B. Drehen)


func _layout() -> void:
	if root == null:
		return
	for sc in _fit_orig:  # nach Drehen oder Größenwechsel wieder mit der vollen Höhe rechnen
		if is_instance_valid(sc):
			sc.custom_minimum_size.y = _fit_orig[sc]
	_fit_orig.clear()
	for c in _fit_hidden:  # versteckte Filter und Fußzeilen wieder zeigen
		if is_instance_valid(c):
			c.visible = true
	_fit_hidden.clear()
	var vs := get_viewport().get_visible_rect().size
	var portrait := vs.y > vs.x
	var bp: Control = _bottom.get_parent()
	# Bildknöpfe: auf schmalen Bildschirmen etwas schmaler, damit alle in eine Reihe passen
	var btns := _bottom.get_children().filter(func(b): return b.visible)
	var narrow_bar := vs.x < 64.0 * btns.size() + 30.0
	for b in btns:
		b.custom_minimum_size = Vector2(floor((vs.x - 30.0 - 4.0 * (btns.size() - 1)) / btns.size()), 50) if narrow_bar else Vector2(54, 50)
		b.reset_size()
	_bottom.add_theme_constant_override("separation", 4 if narrow_bar else 6)
	bp.reset_size()
	bp.position = Vector2((vs.x - bp.size.x) / 2.0, vs.y - bp.size.y - 6)
	_place_bar.reset_size()
	_place_bar.size.x = min(vs.x - 12, 620)
	_place_bar.position = Vector2((vs.x - _place_bar.size.x) / 2.0, vs.y - _place_bar.size.y - 6)
	var sp: Control = root.get_node(tr("SpeedPanel"))
	# Schmal: vier Zeitknöpfe etwas kleiner, damit die Zielkarte daneben Platz hat
	var narrow_top := portrait or vs.x < 760
	for e in _speed_btns:
		e[0].custom_minimum_size = Vector2(30, 30) if narrow_top else Vector2(34, 34)
		e[0].reset_size()
	for b in _head_btns:
		b.custom_minimum_size = Vector2(30, 30) if narrow_top else Vector2(34, 34)
		b.reset_size()
	sp.get_child(0).add_theme_constant_override("separation", 2 if narrow_top else 4)
	sp.reset_size()
	var top_h := 50.0
	# Schmal: Jahreszeit nur als Symbol
	_season_label.visible = not (portrait or vs.x < 760)
	if _food_short != (vs.x < 480):
		_food_short = vs.x < 480
		_refresh_top()
	# Schmal: Oberleiste enger und ohne Uhrzeit, damit Jahreszeit und Klima-Symbol im Bild bleiben
	_season_icon.get_parent().get_parent().add_theme_constant_override("separation", 4 if _food_short else 12)
	_fix_top_widths(vs.x >= 1100.0)
	# Inselname: so breit, wie neben der Geschwindigkeit Platz ist (fest je Bildschirmgröße)
	_island_label.custom_minimum_size.x = 0
	var isl_vis := _island_label.visible
	_island_label.visible = false
	# Neben der Geschwindigkeit (mit Ziele, Aufträge, Nachrichten) zu eng: Jahreszeit nur als Symbol
	var fits := func() -> bool: return top_bar.get_combined_minimum_size().x <= vs.x - sp.size.x - 18.0
	if _season_label.visible and not fits.call() and vs.x >= 1100.0:
		_fix_top_widths(false)
	if _season_label.visible and not fits.call():
		_season_label.visible = false
	var base := top_bar.get_combined_minimum_size().x
	_island_label.visible = isl_vis
	var right := vs.x - 6.0 if (portrait or vs.x < 760) else vs.x - sp.size.x - 12.0
	_island_room = clampf(right - 6.0 - base - 12.0, 0.0, 160.0)
	_island_label.custom_minimum_size.x = _island_room
	_refresh_top()
	if portrait or vs.x < 760:
		sp.position = Vector2(vs.x - sp.size.x - 6, 54)
		top_h = 100.0
	else:
		sp.position = Vector2(vs.x - sp.size.x - 6, 6)
	_toasts.position = Vector2(8, top_h + 6)
	if goal_card and not goal_card.bubble:  # als Sprechblase setzt die Karte sich selbst neben ihr Ziel
		var narrow := portrait or vs.x < 760
		var gw: float = (vs.x - sp.size.x - 18.0) if narrow else min(310.0, vs.x * 0.4)
		goal_card.custom_minimum_size.x = gw
		goal_card.reset_size()
		goal_card.size.x = gw
		goal_card.position = Vector2(6, 54 if narrow else 50)
		goal_card.set_deferred("size", Vector2(gw, 0))
		if goal_card.visible:
			_toasts.position.y = max(top_h, goal_card.position.y + goal_card.size.y) + 6
	if _toasts_top:  # unter der Zielkarte, sonst verdeckt eine Meldung die Einführung (josh 2026-10-29)
		_toasts_top.position = _toasts.position
		_toasts_top_y = _toasts.position.y
	top_alerts.place(sp, _season_icon.get_parent().get_parent().get_parent(), portrait or vs.x < 760)
	if top_alerts.visible and top_alerts.position.y > sp.position.y:  # Knöpfe unter der Geschwindigkeit: Meldungen darunter
		_toasts.position.y = maxf(_toasts.position.y, top_alerts.position.y + top_alerts.size.y + 4.0)
	_top_h = top_h
	_notify_grid.columns = 2 if vs.x >= 640 else 1
	for g in _menu_grids:
		g.columns = 2 if vs.x >= 640 else 1
	_size_settler_panel(vs.y - top_h - bp.size.y - 18.0)
	_fit_research(top_h)
	# Alle Fenster gleich groß (josh 2026-10-16): so breit wie das Siedler-Fenster, so hoch wie der freie Platz
	_win_size = Vector2(minf(vs.x - 12.0, clampf(vs.x - 36.0, 290.0, 980.0) + 24.0), vs.y - top_h - bp.size.y - 18.0)
	for pnl in _panels():
		pnl.custom_minimum_size = _win_size
		var big := _biggest_scroller(pnl)
		if big != null and pnl != _settler_panel:
			big.size_flags_vertical = Control.SIZE_EXPAND_FILL  # Liste füllt den Platz, Fuß bleibt unten
		pnl.reset_size()
		pnl.size.x = min(pnl.size.x, vs.x - 12)
		pnl.position = Vector2((vs.x - pnl.size.x) / 2.0, max(top_h, vs.y - pnl.size.y - bp.size.y - 18))
	# Siedler: bis an den unteren Rand, die Knöpfe unten liegen darüber (josh 2026-10-22)
	_settler_panel.custom_minimum_size.y = vs.y - top_h - 6.0
	_settler_panel.reset_size()
	_settler_panel.size.x = min(_settler_panel.size.x, vs.x - 12)
	_settler_panel.position = Vector2((vs.x - _settler_panel.size.x) / 2.0, top_h)
	bp.move_to_front()
	var bottom_space := bp.size.y + 18
	if portrait:
		_info_panel.size = Vector2(vs.x - 12, min(vs.y * 0.45, 420))
		_info_panel.position = Vector2(6, vs.y - _info_panel.size.y - bottom_space)
	else:
		# Breiter Inhalt macht das Fenster breiter: dann rückt es nach links, statt rechts aus dem Bild zu ragen
		var iw: float = clampf(_info_panel.get_combined_minimum_size().x, 310.0, vs.x - 12.0)
		_info_panel.size = Vector2(iw, vs.y - top_h - bottom_space - 6)
		_info_panel.position = Vector2(vs.x - iw - 6, top_h + 6)


## Prüft nach dem Layout die echte Höhe jedes offenen Fensters. Die Rechnung in _layout und den
## Einzelfenstern schätzt Kopfzeilen, Filter und Zähler nur grob (umbrechende Filter und Texte sind
## auf dem Handy höher). Ragt ein Fenster unter die untere Leiste oder aus dem Bild, wird die größte
## Liste darin so weit gekürzt, bis alles sichtbar ist. Dann weiß die Liste wirklich, dass sie
## scrollen muss, und zeigt den Griff. Fenster ganz ohne Liste (Menü, Meldungen im Querformat)
## bekommen dafür einmal eine. Gekürzt wird nur, nie verlängert.
func _fit_visible_panels() -> void:
	var vs := get_viewport().get_visible_rect().size
	var bp: Control = _bottom.get_parent()
	var avail := vs.y - _top_h - bp.size.y - 18.0
	if _menu_help != null and _menu_help.visible and _panels().all(func(pn): return pn == null or not pn.visible):
		_menu_help.visible = false  # Fenster zu: Hilfe dazu auch zu
	for pnl in _panels():
		if not pnl.visible or pnl == _settler_panel:  # Siedler reicht bis unten, die Liste rollt (siehe _layout)
			continue
		var cap := minf(avail, _win_size.y)  # alle Fenster gleich hoch
		var ws = pnl.get_meta("wrap_sc") if pnl.has_meta("wrap_sc") else null  # Fenster mit nachträglich eingebauter Liste: wächst und schrumpft mit
		if ws != null and is_instance_valid(ws):
			var inner: Control = ws.get_child(0)
			var head: float = pnl.size.y - ws.size.y
			if _hide_footer_for(inner, inner.get_combined_minimum_size().y - (cap - head)):
				continue  # nur ein kleines Stück zu hoch: ohne Fuß passt es, im nächsten Bild neu messen
			var want := minf(inner.get_combined_minimum_size().y, maxf(cap - head, 90.0))
			if absf(want - ws.custom_minimum_size.y) > 0.5 or pnl.size.y > cap + 0.5:
				ws.custom_minimum_size.y = want
				_refit_panel(pnl, vs, bp)
			continue
		if pnl.size.y <= cap + 0.5:
			# Passt, ist aber nach dem Layout noch gewachsen (umbrechende Reiter, Texte): neu ausrichten
			if pnl.position.y + pnl.size.y > vs.y - bp.size.y - 18.0 + 0.5:
				_refit_panel(pnl, vs, bp)
			elif _hide_for_small_scroll(pnl):
				_refit_panel(pnl, vs, bp)
			continue
		var sc: Control = _biggest_scroller(pnl)
		if sc == null:
			if _hide_footer_for(pnl, pnl.size.y - cap):  # nur ein kleines Stück zu hoch: ohne Fuß passt es ohne Rollen
				_refit_panel(pnl, vs, bp)
			else:
				_wrap_in_scroll(pnl)  # ab dem nächsten Bild von oben passt es mit
			continue
		var cur := maxf(sc.custom_minimum_size.y, sc.size.y)
		var floor_h := 90.0 if vs.y >= 500.0 else 64.0
		var target := maxf(cur - (pnl.size.y - cap), floor_h)
		if target >= cur - 0.5:
			# Liste schon am kleinsten (Handy quer): Filter-Chips und Fuß ausblenden
			var hid := _hide_fit_parts(pnl)
			if hid:
				_refit_panel(pnl, vs, bp)
			continue
		if not _fit_orig.has(sc):
			_fit_orig[sc] = sc.custom_minimum_size.y
		sc.custom_minimum_size.y = target
		_refit_panel(pnl, vs, bp)


## Fehlt der Liste nur ein kleines Stück (höchstens so viel, wie die Fußzeile hoch ist),
## blendet sie diese aus, damit man nicht für ein paar Pixel rollen muss (josh 2026-10-19).
func _hide_for_small_scroll(pnl: Control) -> bool:
	var sc := _biggest_scroller(pnl)
	if not (sc is ScrollContainer) or sc.get_child_count() == 0 or not sc.is_visible_in_tree():
		return false
	return _hide_footer_for(pnl, sc.get_child(0).get_combined_minimum_size().y - sc.size.y)


## Blendet die Fußzeile aus, wenn das reicht, um excess Pixel zu sparen.
func _hide_footer_for(pnl: Node, excess: float) -> bool:
	if excess <= 0.5:
		return false
	var parts := []
	_fit_parts(pnl, parts)
	var room := 0.0
	for c in parts:
		room += c.size.y + 6.0
	if parts.is_empty() or excess > room:
		return false
	for c in parts:
		c.visible = false
		_fit_hidden.append(c)
	return true


func _fit_parts(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control and c.visible and c.has_meta("fit_footer"):
			out.append(c)
		elif c is Container and not c is ScrollContainer:
			_fit_parts(c, out)


func _hide_fit_parts(n: Node) -> bool:
	var any := false
	for c in n.get_children():
		if c is Control and c.visible and c.has_meta("fit_hide"):
			c.visible = false
			_fit_hidden.append(c)
			any = true
		elif c is Container:
			any = _hide_fit_parts(c) or any
	return any


func _refit_panel(pnl: Control, vs: Vector2, bp: Control) -> void:
	pnl.reset_size()
	pnl.size.x = minf(pnl.size.x, vs.x - 12)
	pnl.position = Vector2((vs.x - pnl.size.x) / 2.0, maxf(_top_h, vs.y - pnl.size.y - bp.size.y - 18))


## Die höchste scrollende Liste in einem Fenster (ScrollContainer oder Text mit eigenem Scroll), oder null.
func _biggest_scroller(n: Node) -> Control:
	var best: Control = null
	for c in n.get_children():
		var cand: Control = null
		if c is ScrollContainer or (c is RichTextLabel and c.scroll_active):
			cand = c
		else:
			cand = _biggest_scroller(c)
		if cand != null and (best == null or cand.size.y > best.size.y):
			best = cand
	return best


## Packt alles unter der Titelzeile eines Fensters (aus _popup_panel) in eine Scroll-Liste.
func _wrap_in_scroll(pnl: Control) -> ScrollContainer:
	var v := pnl.get_child(0) if pnl.get_child_count() > 0 else null
	if not (v is VBoxContainer) or v.get_child_count() < 2:
		return null
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in v.get_children().slice(1):
		v.remove_child(c)
		inner.add_child(c)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(inner)
	v.add_child(sc)
	sc.custom_minimum_size.y = inner.get_combined_minimum_size().y
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pnl.set_meta("wrap_sc", sc)
	return sc


func _process(delta: float) -> void:
	if root == null:
		return
	_tick_settler_list(delta)
	_fit_visible_panels()
	_day_label.text = (tr("Tag %d") % Game.day()) if _food_short else (tr("Tag %d  %s") % [Game.day(), Game.clock_text()])
	_day_icon.texture = Data.icon("mond" if Game.is_night() else "sonne")
	_season_icon.texture = Seasons.icon()
	_season_label.text = Seasons.short_text(get_viewport().get_visible_rect().size.x >= 1100.0)  # Klima-Name nur mit Platz
	if _rules_dialog:
		_fit_rules_dialog()
	if not Hints.queue.is_empty() and _hint_dialog == null and not has_overlay():
		_show_hint(Hints.pop())
	elif not _offers.is_empty() and _hint_dialog == null and not has_overlay():
		_show_offer(_offers.pop_front())
	_research_tick -= delta
	if _research_tick <= 0.0:
		_research_tick = 0.5
		if not _research_panel.visible or user_just_acted():
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
