class_name CouncilPanel
extends PanelContainer
## KI-Variante: Fenster „Rat“. Der Spieler ist der Herrscher über alle Inseln. Er sieht je
## Insel Strategie, Vertrauen, Anliegen (Forderungen und Angebote), die Abstimmung im Rat,
## die Häuser und ihre Absprachen und eine Chronik. Er stimmt zu, lehnt ab, diskutiert
## mit Argumenten oder bestimmt. Logik in Society (scripts/autoload/society.gd).

const DIM := Color("#6e5a50")
const RULER := Color("#2a5a9a")

var hud
var _island: int = 0
var _view: String = "rat"  # rat, waehlen, debatte
var _tabs: HBoxContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _tick: float = 0.0
var _sig: String = ""


func setup(p_hud) -> void:
	hud = p_hud
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	var t := UiTheme.label("Rat der Inseln", 20, UiTheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := UiTheme.button("", "abriss", 32)
	x.tooltip_text = "Schließen"
	x.pressed.connect(func(): visible = false)
	head.add_child(x)
	v.add_child(head)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	v.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(380, 300)
	v.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 5)
	_scroll.add_child(_body)
	Society.changed.connect(func():
		if visible:
			refresh())
	get_viewport().size_changed.connect(_fit)


func open() -> void:
	_island = Game.world.island_id if Game.world else 0
	# Gibt es auf der aktuellen Insel nichts zu entscheiden, aber woanders? Dorthin.
	if Society.requests_of(_island).is_empty() and not Society.requests.is_empty():
		_island = int(Society.requests[0].isl)
	_view = "rat"
	_fit()
	refresh()


func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	_scroll.custom_minimum_size = Vector2(clamp(vs.x - 40.0, 300.0, 520.0), clamp(vs.y - 200.0, 220.0, 560.0))
	_body.custom_minimum_size.x = _scroll.custom_minimum_size.x - 14.0


func _process(delta: float) -> void:
	if not visible:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		var sig := _signature()
		if sig != _sig:
			refresh()


func _signature() -> String:
	var w = _world()
	if w == null:
		return ""
	var st: Dictionary = Society.state(w)
	return "%s|%d|%d|%s|%d|%d" % [st.strategy, int(st.trust), Society.requests.size(), _view, st.log.size(), Sea.settled_islands().size()]


func _world():
	var w = Sea.worlds.get(_island)
	if w == null or not is_instance_valid(w):
		w = Game.world
		_island = w.island_id if w else 0
	return w


func refresh() -> void:
	if not is_inside_tree():
		return
	_sig = _signature()
	_fill_tabs()
	for c in _body.get_children():
		c.queue_free()
	var w = _world()
	if w == null:
		return
	match _view:
		"waehlen":
			_fill_choose(w)
		"debatte":
			_fill_debate(w)
		_:
			_fill_overview(w)


func _fill_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	var isles := Sea.settled_islands()
	_tabs.visible = isles.size() > 1
	for m in isles:
		var id := int(m.id)
		var n := Society.requests_of(id).size()
		var b := UiTheme.button("%s%s" % [m.name, " (%d)" % n if n > 0 else ""], "", 30)
		b.toggle_mode = true
		b.button_pressed = id == _island
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			_island = id
			_view = "rat"
			refresh())
		_tabs.add_child(b)


func _text(t: String, size: int = 14, color: Color = UiTheme.TEXT, bold: bool = false) -> Label:
	var l := UiTheme.label(t, size, color, bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(l)
	return l


func _section(t: String) -> void:
	var l := _text(t, 16, UiTheme.TEXT, true)
	l.add_theme_color_override("font_color", Color("#7a4a28"))


func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	_body.add_child(h)
	return h


func _btn(parent: Control, text: String, icon: String, tip: String, cb: Callable) -> Button:
	var b := UiTheme.button(text, icon, 34)
	b.add_theme_font_size_override("font_size", 14)
	b.tooltip_text = tip
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# ================================================================== Übersicht
func _fill_overview(w) -> void:
	var st: Dictionary = Society.state(w)
	var sd: Dictionary = Society.strategies().get(st.strategy, {})
	var h := _row()
	h.add_child(UiTheme.icon_rect(Data.icon(sd.get("icon", "ki")), 20))
	var sl := UiTheme.label("Strategie: %s" % Society.strat_name(st.strategy), 16, UiTheme.TEXT, true)
	h.add_child(sl)
	_text("%s Gilt seit Tag %d. Nächste Ratssitzung: Tag %d." % [sd.get("desc", ""), int(floor(float(st.since))) + 1,
		int(floor(float(st.next_council))) + 1], 13, DIM)
	var th := _row()
	th.add_child(UiTheme.label("Vertrauen in dich: %d" % int(st.trust), 14, UiTheme.TEXT, true))
	var bar := UiTheme.bar(UiTheme.GOOD if float(st.trust) >= 50.0 else UiTheme.BAD, 10)
	bar.value = float(st.trust)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(bar)
	var mods := []
	var t := Game.time_days
	if t < float(st.festival_until):
		mods.append("Fest")
	if t < float(st.leisure_until):
		mods.append("mehr Freizeit")
	if t < float(st.overtime_until):
		mods.append("Überstunden")
	if not mods.is_empty():
		_text("Gerade: %s." % ", ".join(mods), 13, RULER)

	# Anliegen
	var reqs := Society.requests_of(_island)
	_section("Anliegen an dich (%d)" % reqs.size())
	if reqs.is_empty():
		_text("Im Moment hat der Rat keine Anliegen. Ohne deine Antwort entscheidet er nach einem Tag selbst.", 13, DIM)
	for r in reqs:
		_request_card(w, r)
	var own := _row()
	_btn(own, "Eigener Vorschlag", "glocke", "Schlage dem Rat eine Strategie vor und überzeuge ihn.", func():
		Society.debate = {}
		_view = "waehlen"
		refresh())

	# Rat
	var reps: Array = Society.representatives(w)
	_section("Inselrat (%d Sprecher)" % reps.size())
	if st.votes.is_empty():
		_text("Der Rat hat noch nicht getagt.", 13, DIM)
	else:
		_text("Letzte Abstimmung: %s" % Society.tally_text(st.votes), 13, DIM)
		for v in st.votes:
			_text("%s (%s): %s. „%s“" % [v.name, v.house, Society.strat_name(v.strat), v.why], 13)

	# Häuser
	var hs: Array = Society.households.get(_island, [])
	_section("Häuser und Absprachen")
	for hh in hs:
		var sp = hh.speaker
		_text("%s: %d Bewohner, Sprecher %s. Kümmert sich um %s." % [hh.name, hh.size,
			sp.display_name if is_instance_valid(sp) else "?", Society.DOMAIN_NAMES.get(hh.domain, hh.domain)], 13)

	# Chronik
	_section("Chronik")
	var lines: Array = st.log.duplicate()
	lines.reverse()
	if lines.is_empty():
		_text("Noch nichts geschehen.", 13, DIM)
	for l in lines.slice(0, 8):
		_text("Tag %d: %s" % [int(l[0]), l[1]], 13, DIM)


func _request_card(w, r: Dictionary) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#f6e7c8")
	sb.border_color = Color("#c89a5a")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	_body.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var tl := UiTheme.label(r.title, 15, UiTheme.TEXT, true)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tl)
	var who: String = ("%s sagt: " % r.who) if r.who != "" else ""
	var tx := UiTheme.label(who + r.text, 13)
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tx.custom_minimum_size.x = 200
	v.add_child(tx)
	var left: float = float(r.until) - Game.time_days
	var auto := "Ohne Antwort entscheidet der Rat selbst." if r.kind in ["strategie", "bau", "forschung", "ueberstunden"] \
		else "Ohne Antwort sinkt das Vertrauen ein wenig."
	var hint := UiTheme.label("%s Noch etwa %d Stunden." % [auto, int(ceil(left * 24.0))], 12, DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	v.add_child(h)
	var rid := int(r.id)
	var say := func(msg: String):
		if msg != "" and hud:
			hud.toast(msg, "glocke")
		refresh()
	if r.kind == "strategie":
		_btn(h, "Zustimmen", "", "Der Rat bekommt seine Strategie. Das Vertrauen steigt.", func(): say.call(Society.answer(rid, "ja")))
		_btn(h, "Ablehnen", "", "Die alte Strategie bleibt. Das Vertrauen sinkt.", func(): say.call(Society.answer(rid, "nein")))
		_btn(h, "Besprechen", "glocke", "Schlage etwas anderes vor und überzeuge den Rat mit Argumenten.", func():
			Society.debate = {"rid": rid}
			_view = "waehlen"
			refresh())
	else:
		_btn(h, "Zustimmen" if not r.kind in ["ueberstunden"] else "Annehmen", "", "", func(): say.call(Society.answer(rid, "ja")))
		_btn(h, "Ablehnen", "", "Das Vertrauen sinkt.", func(): say.call(Society.answer(rid, "nein")))


# ================================================================== Diskussion
func _fill_choose(w) -> void:
	_section("Was schlägst du dem Rat von %s vor?" % Sea.island_name(w))
	_text("Wähle eine Strategie. Danach versuchst du, die Sprecher der Häuser zu überzeugen.", 13, DIM)
	var rid := int(Society.debate.get("rid", 0))
	var cur: String = Society.state(w).strategy
	var sc := Society.situation_scores(w)
	for k in Society.strategies():
		if not Society.strategy_allowed(k):
			continue
		var sd: Dictionary = Society.strategies()[k]
		var h := _row()
		var b := _btn(h, sd.name, sd.get("icon", ""), sd.get("desc", ""), func():
			Society.start_debate(w, k, rid)
			_view = "debatte"
			refresh())
		b.custom_minimum_size.x = 210
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var note := "jetzt" if k == cur else ("dringend" if float(sc.get(k, 0.0)) > 0.8 else "")
		h.add_child(UiTheme.label(note, 12, DIM))
	var back := _row()
	_btn(back, "Zurück", "", "", func():
		Society.debate = {}
		_view = "rat"
		refresh())


func _fill_debate(w) -> void:
	var d: Dictionary = Society.debate
	if d.is_empty() or not d.has("strat"):
		_view = "rat"
		_fill_overview(w)
		return
	_section("Diskussion: %s" % Society.strat_name(d.strat))
	var n: int = d.reps.size()
	_text("Dafür: %d von %d Sprechern. Für eine Mehrheit braucht es %d." % [Society.debate_yes(), n, n / 2 + 1], 14, UiTheme.TEXT, true)
	for l in d.lines:
		var you: bool = l[0] == "Du"
		_text("%s: %s" % ["Du" if you else l[0], l[1]], 13, RULER if you else (Color("#2a7a3a") if l[0] == "Rat" else UiTheme.TEXT))
	if d.won:
		_text("Der Rat folgt dir. Die Siedler setzen die neue Strategie selbst um.", 14, UiTheme.GOOD, true)
	else:
		var args := Society.arguments()
		if not args.is_empty():
			_section("Dein Argument")
			for a in args:
				var h := _row()
				var b := _btn(h, a[1], "", _arg_tip(a[0]), func(): Society.argue(a[0]))
				b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			_text("Dir gehen die Argumente aus. Du kannst nachgeben oder bestimmen.", 13, DIM)
		var h2 := _row()
		_btn(h2, "Bestimmen", "", "Du setzt die Strategie durch. Das Vertrauen sinkt stark, die Laune leidet zwei Tage.", func():
			Society.command(w, d.strat)
			_view = "rat"
			refresh())
		if int(d.get("rid", 0)) > 0 and not Society.request_by_id(int(d.rid)).is_empty():
			_btn(h2, "Nachgeben", "", "Der Rat bekommt seine eigene Strategie.", func():
				Society.give_in()
				_view = "rat"
				refresh())
	var back := _row()
	_btn(back, "Zurück zum Rat", "", "", func():
		Society.debate = {}
		_view = "rat"
		refresh())
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _arg_tip(a: String) -> String:
	match a:
		"lage":
			return "Überzeugt vor allem kluge Sprecher, und nur, wenn die Lage wirklich dafür spricht."
		"gemeinwohl":
			return "Wirkt bei gutmütigen Sprechern."
		"fest":
			return "Wirkt bei allen. Wenn der Rat zustimmt, feiert die Insel ein Fest (kostet Essen)."
		"freizeit":
			return "Wirkt besonders bei wenig fleißigen Sprechern. Bei Zustimmung wird zwei Tage gemütlicher gearbeitet."
	return ""
