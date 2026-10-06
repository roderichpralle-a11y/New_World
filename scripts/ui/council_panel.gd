class_name CouncilPanel
extends PanelContainer
## KI-Variante: Fenster „Rat“. Der Spieler ist der Herrscher über alle Inseln. Er sieht je
## Insel Schwerpunkt, Vertrauen, Aufträge, Anliegen, was der Rat gelernt hat und eine Chronik.
## Er beantwortet Anliegen (zustimmen, ablehnen, diskutieren), macht feste Vorgaben und setzt
## Prioritäten. Logik in KiMind (ki_mind.gd) und Society (society.gd).

const DIM := Color("#6e5a50")
const RULER := Color("#2a5a9a")

var hud
var _island: int = 0
var _view: String = "rat"  # rat, waehlen, debatte, ki, vorgaben, prio, lernen
var _tabs: HBoxContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _tick: float = 0.0
var _sig: String = ""
var _scrolled_at: int = -100000  # wann der Spieler zuletzt gescrollt hat (ms)
var _filled_view: String = ""
var _restoring := false


func setup(p_hud) -> void:
	hud = p_hud
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	var t := UiTheme.label(tr("Rat der Inseln"), 20, UiTheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := UiTheme.button("", "abriss", 32)
	x.tooltip_text = tr("Schließen")
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
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v):
		if not _restoring:
			_scrolled_at = Time.get_ticks_msec())
	Society.changed.connect(func():
		if visible:
			refresh())
	KiMind.changed.connect(func():
		if visible and _view == "rat":
			_tick = minf(_tick, 0.2))
	get_viewport().size_changed.connect(_fit)


func open() -> void:
	_island = Game.world.island_id if Game.world else 0
	# Gibt es auf der aktuellen Insel nichts zu entscheiden, aber woanders? Dorthin.
	if Society.requests_of(_island).is_empty() and not Society.requests.is_empty():
		_island = int(Society.requests[0].isl)
	_view = "rat"
	_filled_view = ""
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
		# Beim Beobachten nicht neu aufbauen, solange der Spieler scrollt oder die lange
		# Anfrage liest: Das Neuaufbauen vieler Zeilen ließ die Liste springen.
		if _view == "ki" and (Time.get_ticks_msec() - _scrolled_at < 2500):
			return
		if _view == "ki":
			_tick = 2.0
		var sig := _signature()
		if sig != _sig:
			refresh()


func _signature() -> String:
	var w = _world()
	if w == null:
		return ""
	var st: Dictionary = Society.state(w)
	var m: Dictionary = KiMind.mem(w)
	var extra := "%d|%d|%s" % [int(m.councils), m.binding.size(), m.focus]
	if _view == "ki":
		# Beobachten: jede Sekunde neu, solange das Spiel läuft
		extra += "%d|%d" % [st.dlog.size(), int(Game.time_days * 48.0)]
	return "%s|%d|%d|%s|%d|%d|%s" % [st.strategy, int(st.trust), Society.requests.size(), _view, st.log.size(), Sea.settled_islands().size(), extra]


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
	var keep := _scroll.scroll_vertical
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var w = _world()
	if w == null:
		return
	match _view:
		"ki":
			_fill_watch(w)
		"waehlen":
			_fill_choose(w)
		"debatte":
			_fill_debate(w)
		"vorgaben":
			_fill_binding(w)
		"prio":
			_fill_prio(w)
		"lernen":
			_fill_learn(w)
		_:
			_fill_overview(w)
	# Beim Neuaufbau derselben Ansicht an der Stelle bleiben, an der der Spieler liest
	if _view == _filled_view and _view in ["ki", "rat", "vorgaben", "prio", "waehlen", "lernen"] and keep > 0:
		_restore_scroll(keep)
	_filled_view = _view


func _restore_scroll(v: int) -> void:
	_restoring = true
	_scroll.scroll_vertical = v
	await get_tree().process_frame
	_scroll.scroll_vertical = v
	await get_tree().process_frame
	_restoring = false


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
	var m: Dictionary = KiMind.mem(w)
	var st: Dictionary = Society.state(w)
	var sd: Dictionary = Society.strategies().get(m.focus, {})
	var h := _row()
	h.add_child(UiTheme.icon_rect(Data.icon(sd.get("icon", "ki")), 20))
	h.add_child(UiTheme.label(tr("Schwerpunkt: %s") % Society.strat_name(m.focus), 16, UiTheme.TEXT, true))
	if str(m.plan) != "":
		_text(tr("Der Rat sagt: %s") % m.plan, 14, Color("#2a7a3a"))
	_text(tr("Nächste Ratssitzung: Tag %d %s. Ziel: %s.") % [int(floor(float(m.next_council))) + 1, _clock(float(m.next_council)),
		tr("wachsen und forschen") if _island == 0 else tr("wachsen")], 13, DIM)
	if m.has("note"):
		_text(str(m.note), 13, UiTheme.BAD)
	var th := _row()
	th.add_child(UiTheme.label(tr("Vertrauen in dich: %d") % int(st.trust), 14, UiTheme.TEXT, true))
	var bar := UiTheme.bar(UiTheme.GOOD if float(st.trust) >= 50.0 else UiTheme.BAD, 10)
	bar.value = float(st.trust)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(bar)
	var r1 := _row()
	_btn(r1, tr("KI beobachten"), "ki", tr("Was der Rat zuletzt entschieden hat, was jeder Siedler denkt, das Gedächtnis des Rats und alle Entscheidungen."), func():
		_view = "ki"
		refresh())
	_btn(r1, tr("Gelernt und Statistik"), "buch", tr("Alles, was der Rat gelernt hat, und wie die Arbeiter beschäftigt waren."), func():
		_view = "lernen"
		refresh())
	var r2 := _row()
	_btn(r2, tr("Feste Vorgaben (%d)") % m.binding.size(), "hammer", tr("Befehle, die der Rat befolgen muss. Kostet Vertrauen."), func():
		_view = "vorgaben"
		refresh())
	_btn(r2, tr("Prioritäten"), "wissen", tr("Was dir wichtig ist. Der Rat verteilt die Arbeit danach."), func():
		_view = "prio"
		refresh())
	if KiMind.net != null:
		var r3 := _row()
		_btn(r3, tr("Trainiertes Netz: an") if KiMind.use_net else tr("Trainiertes Netz: aus"), "ki",
			tr("An: Ein durch Reinforcement Learning trainiertes Netz verschiebt die Entscheidungen des Rats. Aus: Der Rat entscheidet nur nach festen Regeln."), func():
			KiMind.set_use_net(not KiMind.use_net)
			refresh())
		_text(tr("Das trainierte Netz hat in vielen schnellen Probespielen gelernt, wann der Rat besser anders entscheidet als nach seinen Regeln."), 12, DIM)

	# Aufträge
	var slots: Dictionary = m.get("slots", {})
	if not slots.is_empty():
		_section(tr("Aufträge an die Bewohner"))
		_text(KiMind.slots_text(slots) + ".", 13)

	# Anliegen
	var reqs := Society.requests_of(_island)
	if not reqs.is_empty():
		_section(tr("Anliegen an dich (%d)") % reqs.size())
		for r in reqs:
			_request_card(w, r)

	# Was der Rat gelernt hat: Zusammenfassung, ganz unter "Gelernt und Statistik"
	_section(tr("Was der Rat gelernt hat"))
	if not m.knowledge.is_empty():
		for k in m.knowledge.slice(0, 3):
			_text("• " + KiMind.lesson_text(k), 13)
	elif not m.lessons.is_empty():
		var ls: Array = m.lessons.duplicate()
		ls.reverse()
		for l in ls.slice(0, 3):
			_text("• " + KiMind.lesson_text(l), 13)
	else:
		_text(tr("Noch keine Lehren."), 13, DIM)

	_section(tr("Chronik"))
	var lines: Array = st.log.duplicate()
	lines.reverse()
	if lines.is_empty():
		_text(tr("Noch nichts geschehen."), 13, DIM)
	for l in lines.slice(0, 8):
		_text(tr("Tag %d: %s") % [int(l[0]), l[1]], 13, DIM)


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
	var who: String = (tr("%s sagt: ") % r.who) if r.who != "" else ""
	var tx := UiTheme.label(who + r.text, 13)
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tx.custom_minimum_size.x = 200
	v.add_child(tx)
	var left: float = float(r.until) - Game.time_days
	var auto := tr("Ohne Antwort entscheidet der Rat selbst.") if r.kind in ["strategie", "bau", "forschung", "ueberstunden"] \
		else tr("Ohne Antwort sinkt das Vertrauen ein wenig.")
	var hint := UiTheme.label(tr("%s Noch etwa %d Stunden.") % [auto, int(ceil(left * 24.0))], 12, DIM)
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
		_btn(h, tr("Zustimmen"), "", tr("Der Rat bekommt seine Strategie. Das Vertrauen steigt."), func(): say.call(Society.answer(rid, "ja")))
		_btn(h, tr("Ablehnen"), "", tr("Die alte Strategie bleibt. Das Vertrauen sinkt."), func(): say.call(Society.answer(rid, "nein")))
		_btn(h, tr("Besprechen"), "glocke", tr("Schlage etwas anderes vor und überzeuge den Rat mit Argumenten."), func():
			Society.debate = {"rid": rid}
			_view = "waehlen"
			refresh())
	else:
		_btn(h, tr("Zustimmen") if not r.kind in ["ueberstunden"] else tr("Annehmen"), "", "", func(): say.call(Society.answer(rid, "ja")))
		_btn(h, tr("Ablehnen"), "", tr("Das Vertrauen sinkt."), func(): say.call(Society.answer(rid, "nein")))


# ================================================================== Diskussion
func _fill_choose(w) -> void:
	_section(tr("Was schlägst du dem Rat von %s vor?") % Sea.island_name(w))
	_text(tr("Wähle eine Strategie. Danach versuchst du, die Sprecher der Häuser zu überzeugen."), 13, DIM)
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
		var note := tr("jetzt") if k == cur else ("dringend" if float(sc.get(k, 0.0)) > 0.8 else "")
		h.add_child(UiTheme.label(note, 12, DIM))
	var back := _row()
	_btn(back, tr("Zurück"), "", "", func():
		Society.debate = {}
		_view = "rat"
		refresh())


func _fill_debate(w) -> void:
	var d: Dictionary = Society.debate
	if d.is_empty() or not d.has("strat"):
		_view = "rat"
		_fill_overview(w)
		return
	_section(tr("Diskussion: %s") % Society.strat_name(d.strat))
	var n: int = d.reps.size()
	_text(tr("Dafür: %d von %d Sprechern. Für eine Mehrheit braucht es %d.") % [Society.debate_yes(), n, n / 2 + 1], 14, UiTheme.TEXT, true)
	for l in d.lines:
		var you: bool = l[0] == tr("Du")
		_text("%s: %s" % [tr("Du") if you else tr(l[0]), l[1]], 13, RULER if you else (Color("#2a7a3a") if l[0] == "Rat" else UiTheme.TEXT))
	if d.won:
		_text(tr("Der Rat folgt dir. Die Siedler setzen die neue Strategie selbst um."), 14, UiTheme.GOOD, true)
	else:
		var args := Society.arguments()
		if not args.is_empty():
			_section(tr("Dein Argument"))
			for a in args:
				var h := _row()
				var b := _btn(h, a[1], "", _arg_tip(a[0]), func(): Society.argue(a[0]))
				b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			_text(tr("Dir gehen die Argumente aus. Du kannst nachgeben oder bestimmen."), 13, DIM)
		var h2 := _row()
		_btn(h2, tr("Bestimmen"), "", tr("Du setzt die Strategie durch. Das Vertrauen sinkt stark, die Laune leidet zwei Tage."), func():
			Society.command(w, d.strat)
			_view = "rat"
			refresh())
		if int(d.get("rid", 0)) > 0 and not Society.request_by_id(int(d.rid)).is_empty():
			_btn(h2, tr("Nachgeben"), "", tr("Der Rat bekommt seine eigene Strategie."), func():
				Society.give_in()
				_view = "rat"
				refresh())
	var back := _row()
	_btn(back, tr("Zurück zum Rat"), "", "", func():
		Society.debate = {}
		_view = "rat"
		refresh())
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _arg_tip(a: String) -> String:
	match a:
		"lage":
			return tr("Überzeugt vor allem kluge Sprecher, und nur, wenn die Lage wirklich dafür spricht.")
		"gemeinwohl":
			return tr("Wirkt bei gutmütigen Sprechern.")
		"fest":
			return tr("Wirkt bei allen. Wenn der Rat zustimmt, feiert die Insel ein Fest (kostet Essen).")
		"freizeit":
			return tr("Wirkt besonders bei wenig fleißigen Sprechern. Bei Zustimmung wird zwei Tage gemütlicher gearbeitet.")
	return ""


# ================================================================== KI beobachten
## Was der Rat zuletzt entschieden hat, was jeder Siedler denkt, das Gedächtnis des Rats
## und das Protokoll aller Entscheidungen.
func _fill_watch(w) -> void:
	_back_row()
	var m: Dictionary = KiMind.mem(w)
	var last: Dictionary = m.get("last", {})
	_section(tr("Letzte Ratssitzung"))
	if last.is_empty():
		_text(tr("Der Rat hat noch nicht getagt."), 13, DIM)
	else:
		_text(tr("Entschieden mit: trainiertem Netz und Regeln") if last.get("net", false) else tr("Entschieden mit: nur Regeln"), 13, DIM)
	for k in [["focus", tr("Schwerpunkt")], ["build", tr("Bauen")], ["research", tr("Forschung")]]:
		if last.has(k[0]):
			var d: Dictionary = last[k[0]]
			var t: String = "%s: %s" % [k[1], d.get("choice", "")]
			if str(d.get("why", "")) != "":
				t += " (%s)" % d.why
			_text(t, 13)
	if last.has("jobs") and last.jobs.has("slots"):
		_text(tr("Arbeit: %s") % last.jobs.slots, 13)
	if last.has("trade"):
		_text(tr("Handel: %s") % last.trade, 13)
	for t in KiMind.trades:
		if int(t.to) == _island or int(t.from) == _island:
			_text(tr("Handelsroute bis Tag %d: %s bringt %s, bekommt %s.") % [int(float(t.until)) + 1, Sea.meta(int(t.from)).get("name", "?"),
				Sea.goods_text(t.get("get", {})), Sea.goods_text(t.give) if not t.give.is_empty() else tr("nichts")], 13)

	_section(tr("Was die Siedler denken"))
	for s in w.settlers:
		if not s.is_adult():
			continue
		var l := _text("%s (%s): %s" % [s.display_name, s.job_name(), Society.thoughts.get(s.id, tr("Überlegt noch."))], 13)
		_jump_on_tap(l, s)

	_section(tr("Gedächtnis des Rats"))
	var gl := _row()
	_btn(gl, tr("Gelernt und Statistik"), "buch", tr("Zusammenfassung, alle Lehren des Spiels und die Arbeitsstatistik."), func():
		_view = "lernen"
		refresh())
	if m.lessons.is_empty():
		_text(tr("Noch keine Lehren."), 13, DIM)
	for l in m.lessons:
		_text(tr("Lehre (Tag %d): %s") % [int(float(l[0])) + 1, KiMind.lesson_text(l)], 13)
	var ex := KiMind.experience_lines(w, 8)
	if not ex.is_empty():
		_text(tr("Gemessene Erfahrung (je Tag nach der Entscheidung):"), 13, UiTheme.TEXT, true)
		for e in ex:
			_text(e, 12)
	var recs: Array = m.records.duplicate()
	recs.reverse()
	if not recs.is_empty():
		_text(tr("Entscheidungen und Folgen:"), 13, UiTheme.TEXT, true)
	for r in recs.slice(0, 6):
		_text(KiMind.record_text(r), 12, DIM)

	_section(tr("Entscheidungen (neueste oben)"))
	var lines: Array = Society.state(w).dlog.duplicate()
	lines.reverse()
	if lines.is_empty():
		_text(tr("Noch keine Entscheidung."), 13, DIM)
	for l in lines.slice(0, 25):
		_text(tr("Tag %d %s  %s") % [int(floor(float(l[0]))) + 1, _clock(float(l[0])), l[1]], 12, DIM)


## Antippen einer Zeile springt zum Siedler. Nur ein echter Klick oder Tipp (linke Taste,
## losgelassen ohne zu ziehen): Mausrad und Wischen zum Scrollen gehen an die Liste weiter.
## Früher reagierte die Zeile auf jedes Drücken, auch auf das Mausrad, und schloss beim
## Scrollen das Fenster.
func _jump_on_tap(l: Control, s) -> void:
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.tooltip_text = tr("Antippen: zum Siedler springen")
	var sref = s
	var down := [Vector2.ZERO, -1]
	l.gui_input.connect(func(e):
		if not (e is InputEventMouseButton) or e.button_index != MOUSE_BUTTON_LEFT:
			return
		var now := Time.get_ticks_msec()
		if e.pressed:
			down[0] = e.global_position
			down[1] = _scroll.scroll_vertical
			return
		if int(down[1]) < 0 or e.global_position.distance_to(down[0]) > 12.0 or absi(_scroll.scroll_vertical - int(down[1])) > 6 \
				or now - _scrolled_at < 300:
			down[1] = -1
			return
		down[1] = -1
		if is_instance_valid(sref) and sref.world == Game.world:
			visible = false
			Game.select(sref)
			if hud:
				hud.camera.focus(sref.position))


func _clock(t: float) -> String:
	var h := fposmod(t, 1.0) * 24.0
	return "%02d:%02d" % [int(h), int(fposmod(h, 1.0) * 60.0)]


func _back_row() -> void:
	var back := _row()
	_btn(back, tr("Zurück zum Rat"), "", "", func():
		_view = "rat"
		refresh())


# ------------------------------------------------------------------ Feste Vorgaben
func _fill_binding(w) -> void:
	_back_row()
	var m: Dictionary = KiMind.mem(w)
	_section(tr("Feste Vorgaben für %s") % Sea.island_name(w))
	_text(tr("Der Rat muss sie befolgen. Jede Vorgabe kostet Vertrauen und drückt kurz die Laune. Schwerpunkt und Arbeiter gelten drei Tage, Bauen und Forschen bis erledigt."), 12, DIM)
	if m.binding.is_empty():
		_text(tr("Keine Vorgaben."), 13, DIM)
	for i in m.binding.size():
		var b: Dictionary = m.binding[i]
		var h := _row()
		var l := UiTheme.label(KiMind._binding_text(b) + (tr(" (bis Tag %d)") % (int(float(b.until)) + 1) if b.kind in ["fokus", "beruf"] else ""), 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var idx: int = i
		_btn(h, tr("Aufheben"), "", "", func(): KiMind.unbind(w, idx))
	var say := func(msg: String):
		if msg != "" and hud:
			hud.toast(msg, "glocke")
		refresh()
	_section(tr("Schwerpunkt bestimmen"))
	var fr := HFlowContainer.new()
	_body.add_child(fr)
	for k in Society.strategies():
		if Society.strategy_allowed(k):
			var key: String = k
			_btn(fr, Society.strat_name(k), Society.strategies()[k].get("icon", ""), Society.strategies()[k].get("desc", ""), func(): say.call(KiMind.bind(w, "fokus", key)))
	_section(tr("Arbeiter bestimmen (mindestens einer mehr)"))
	var jr := HFlowContainer.new()
	_body.add_child(jr)
	var slots: Dictionary = m.get("slots", {})
	for j in KiMind.JOB_ORDER:
		if not Data.job_unlocked(j):
			continue
		var jj: String = j
		var n := int(slots.get(j, 0)) + 1
		_btn(jr, "%d %s" % [n, Data.jobs[j].name], "", "", func(): say.call(KiMind.bind(w, "beruf", jj, n)))
	_section(tr("Bauen lassen"))
	var br := HFlowContainer.new()
	_body.add_child(br)
	var shown := 0
	for t in Data.buildings:
		var def: Dictionary = Data.buildings[t]
		if not def.get("buildable", true) or not Game.is_unlocked(t) or def.has("base") or shown >= 24:
			continue
		var tt: String = t
		var b := _btn(br, def.name, def.get("icon", ""), tr("Kosten: %s") % KiMind._cost_text(t), func(): say.call(KiMind.bind(w, "bau", tt)))
		b.disabled = not Game.can_afford(def.get("cost", {}), w)
		shown += 1
	_section(tr("Forschen lassen"))
	var rr := HFlowContainer.new()
	_body.add_child(rr)
	for t in Data.sorted_tech_ids():
		if Game.tech_state(t) == "available":
			var tt: String = t
			_btn(rr, Data.techs[t].name, "", Data.techs[t].get("desc", ""), func(): say.call(KiMind.bind(w, "forschung", tt)))


# ------------------------------------------------------------------ Prioritäten
func _fill_prio(w) -> void:
	_back_row()
	_section(tr("Prioritäten für %s") % Sea.island_name(w))
	_text(tr("Der Rat verteilt die Arbeit nach deinen Prioritäten: Berufe in wichtigen Bereichen bekommen mehr Plätze, soweit es Arbeit für sie gibt."), 12, DIM)
	var pr: Dictionary = KiMind.cfg("priorities", {})
	for k in pr:
		var h := _row()
		var l := UiTheme.label(tr(pr[k]), 14, UiTheme.TEXT, true)
		l.custom_minimum_size.x = 120
		h.add_child(l)
		var cur := KiMind.prio(w, k)
		for v in 4:
			var key: String = k
			var val: int = v
			var b := _btn(h, tr(KiMind.PRIO_WORDS[v]), "", "", func():
				KiMind.set_prio(w, key, val)
				refresh())
			b.toggle_mode = true
			b.button_pressed = v == cur
			b.add_theme_font_size_override("font_size", 12)


# ------------------------------------------------------------------ Gelernt und Statistik
func _fill_learn(w) -> void:
	var m: Dictionary = KiMind.mem(w)
	_back_row()
	_section(tr("Was der Rat gelernt hat"))
	if m.knowledge.is_empty():
		_text(tr("Noch keine Zusammenfassung. Der Rat fasst seine Lehren nach je %d neuen zusammen (bisher %d).") % [int(KiMind.cfg("summarize_every", 4)), m.archive.size()], 13, DIM)
	else:
		_text(tr("Zusammenfassung aller %d Lehren, zuletzt an Tag %d: je Art von Beobachtung die neueste, die häufigsten zuerst.") % [m.archive.size(), int(float(m.get("knowledge_day", 0.0))) + 1], 12, DIM)
		for k in m.knowledge:
			_text("• " + KiMind.lesson_text(k), 14)

	_section(tr("Arbeit bis zur nächsten Sitzung"))
	var sit: Dictionary = Society.situation(w)
	_text(tr("Lager: %d von %d belegt (%d %%).") % [Game.used_volume(w), Game.storage_volume(w), int(float(sit.storage_full) * 100.0)], 13,
		UiTheme.BAD if float(sit.storage_full) >= float(KiMind.cfg("storage_urgent", 0.8)) else UiTheme.TEXT)
	var cap: Dictionary = m.get("cap", {})
	var slots: Dictionary = m.get("slots", {})
	if cap.is_empty():
		_text(tr("Der Rat hat noch nicht getagt."), 13, DIM)
	for j in cap:
		var c: Dictionary = cap[j]
		_text(tr("%s: Arbeit für höchstens %d, eingeteilt %d (%s)") % [Data.jobs.get(j, {}).get("name", j), int(c.n), int(slots.get(j, 0)), str(c.get("why", c.get("de", "")))], 13,
			DIM if int(c.n) == 0 else UiTheme.TEXT)

	_section(tr("Arbeitsstatistik"))
	if m.stats.is_empty():
		_text(tr("Die erste Statistik gibt es nach der nächsten Ratssitzung."), 13, DIM)
	else:
		var per: Dictionary = m.stats[-1]
		_text(tr("Tag %d bis Tag %d, Anteil der hellen Tageszeit je Beruf. Eigene Arbeit = was der Beruf tun soll, anderes = hilft woanders aus, untätig = nichts zu tun.") % [
			int(float(per.d0)) + 1, int(float(per.d1)) + 1], 12, DIM)
		for l in KiMind.stats_lines(w):
			_text(l, 13)
		_text(tr("Je Siedler:"), 13, UiTheme.TEXT, true)
		for p in per.get("people", []):
			var day := maxf(0.0001, float(p[2]) + float(p[3]) + float(p[4]))
			var t := tr("%s (%s): eigene Arbeit %d %%, anderes %d %%, untätig %d %%, %d Waren geliefert") % [p[0], Data.jobs.get(p[1], {}).get("name", p[1]),
				int(round(float(p[2]) / day * 100.0)), int(round(float(p[3]) / day * 100.0)), int(round(float(p[4]) / day * 100.0)), int(p[5])]
			if str(p[6]) != "" and str(p[6]) != str(p[1]):
				t += tr(" (Auftrag: %s)") % Data.jobs.get(str(p[6]), {}).get("name", p[6])
			_text(t, 12, UiTheme.BAD if float(p[4]) / day > 0.4 else UiTheme.TEXT)
	if not m.stat_total.is_empty():
		_text(tr("Über das ganze Spiel:"), 13, UiTheme.TEXT, true)
		for j in m.stat_total:
			var e: Dictionary = m.stat_total[j]
			var sh: Array = KiMind._shares(e)
			_text(tr("%s: eigene Arbeit %d %%, anderes %d %%, untätig %d %%; geliefert: %s") % [Data.jobs.get(j, {}).get("name", j), sh[0], sh[1], sh[2],
				Sea.goods_text(e.goods) if not e.goods.is_empty() else tr("nichts")], 12, DIM)
		var fit: Dictionary = m.get("fit", {})
		var fl := []
		for j in fit:
			if float(fit[j]) < 0.95:
				fl.append("%s %d %%" % [Data.jobs.get(j, {}).get("name", j), int(float(fit[j]) * 100.0)])
		if not fl.is_empty():
			_text(tr("Gelernt aus dem Leerlauf, weniger Plätze für: %s.") % ", ".join(fl), 12, RULER)

	_section(tr("Alle Lehren (%d)") % m.archive.size())
	if m.archive.is_empty():
		_text(tr("Noch keine Lehren."), 13, DIM)
	var arc: Array = m.archive.duplicate()
	arc.reverse()
	for l in arc:
		var season: String = (", " + Seasons.season_name(int(l[4]))) if l.size() > 4 and int(l[4]) >= 0 else ""
		_text(tr("Tag %d%s: %s") % [int(float(l[0])) + 1, season, KiMind.lesson_text(l)], 12)
