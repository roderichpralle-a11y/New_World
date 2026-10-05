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
var _view: String = "rat"  # rat, waehlen, debatte, ki, chat, vorgaben, prio
var _draft: String = ""  # angefangene Nachricht an den Rat
var _show_prompt: String = ""  # rat/siedler: letzte Anfrage an das Modell anzeigen
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
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v):
		if not _restoring:
			_scrolled_at = Time.get_ticks_msec())
	Society.changed.connect(func():
		if visible:
			refresh())
	KiMind.changed.connect(func():
		if visible and _view in ["chat", "rat"]:
			_tick = minf(_tick, 0.2))
	Llm.status_changed.connect(func():
		if visible:
			refresh())
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
		if _view == "ki" and (Time.get_ticks_msec() - _scrolled_at < 2500 or _show_prompt != ""):
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
	var extra := ""
	if KiMind.active() or Llm.state == "laden":
		var m: Dictionary = KiMind.mem(w)
		extra = "%s|%d|%d|%s|%d|%s|%s|%s" % [Llm.state, m.chat.size(), int(m.councils), str(m.waiting), m.binding.size(), KiMind.activity, Llm.status_text() if Llm.state == "laden" else "", str(KiMind.braking)]
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
		"chat":
			_fill_chat(w)
		"vorgaben":
			_fill_binding(w)
		"prio":
			_fill_prio(w)
		_:
			_fill_overview(w)
	# Beim Neuaufbau derselben Ansicht an der Stelle bleiben, an der der Spieler liest
	if _view == _filled_view and _view in ["ki", "rat", "vorgaben", "prio", "waehlen"] and keep > 0:
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
	_ki_status()
	if KiMind.active():
		_fill_overview_llm(w)
		return
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
	var wr := _row()
	_btn(wr, "KI beobachten", "ki", "Zeigt, was gebraucht wird, was jeder Siedler denkt und jede Entscheidung der KI.", func():
		_view = "ki"
		refresh())

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


# ================================================================== KI beobachten
## Was die KI gerade sieht und warum sie so entscheidet: Bedarf je Beruf, nächster Bau,
## Gedanken jedes Siedlers und das Protokoll aller Entscheidungen.
func _fill_watch(w) -> void:
	var back := _row()
	_btn(back, "Zurück zum Rat", "", "", func():
		_view = "rat"
		refresh())
	if KiMind.active():
		_fill_watch_llm(w)
		return
	var sit: Dictionary = Society.situation(w)
	var st: Dictionary = Society.state(w)
	_section("Was die KI sieht")
	_text("Strategie: %s. Essen: %d (Ziel %d, mit Wintervorrat). Holz: %d (Ziel %d, mit Heizholz bis zum Frühling). Stein: %d. Wohnplätze: %d Siedler auf %d Plätzen. Baustellen: %d. Raubtiere: %d." % [
		Society.strat_name(st.strategy), int(sit.food), int(sit.food_target), int(sit.wood), int(sit.wood_target),
		int(sit.stone), int(sit.pop), int(sit.housing), int(sit.sites), int(sit.predators)], 13)

	# Bedarf je Beruf: gewünschte Plätze und wer sie gerade hat
	var free := 0
	var have := {}
	for s in w.settlers:
		if s.is_adult() and s.job != "seemann" and not s.mind.needs_bed():
			free += 1
			have[s.job] = int(have.get(s.job, 0)) + 1
	var slots: Dictionary = Society.job_slots(w, sit, free)
	_section("Bedarf je Beruf (gebraucht / besetzt)")
	var jobs: Array = slots.keys()
	for j in have:
		if not j in jobs:
			jobs.append(j)
	jobs.sort_custom(func(a, b): return int(slots.get(a, 0)) - int(have.get(a, 0)) > int(slots.get(b, 0)) - int(have.get(b, 0)))
	for j in jobs:
		var want := int(slots.get(j, 0))
		var got := int(have.get(j, 0))
		if want == 0 and got == 0:
			continue
		var name: String = Data.jobs.get(j, {}).get("name", j)
		var mark := "fehlt %d" % (want - got) if want > got else ("zu viele" if got > want and j != "frei" else "passt")
		_text("%s: %d / %d (%s). %s" % [name, want, got, mark, Society._why_job(w, j, sit) if j != "frei" else "Freie helfen, wo es fehlt."],
			13, UiTheme.BAD if want > got else UiTheme.TEXT)

	# Nächster Bau
	_section("Nächster Bau")
	var pick: Dictionary = Society._choose_building(w, sit)
	if pick.is_empty():
		_text("Im Moment plant der Rat keinen Bau.", 13, DIM)
	else:
		_text("%s: %s" % [Data.buildings[pick.type].name + (" (Ausbau)" if pick.has("upgrade") else ""), pick.why], 13)
	if Game.research.current == "":
		var t: String = Society.choose_research(st.strategy, w)
		if t != "":
			_text("Nächste Forschung: %s." % Data.techs[t].name, 13)

	# Gedanken
	_section("Was die Siedler denken")
	for s in w.settlers:
		if not s.is_adult():
			continue
		var hh: Dictionary = Society.household_of(s)
		var l := _text("%s (%s, %s): %s" % [s.display_name, s.job_name(), hh.get("name", "?"),
			Society.thoughts.get(s.id, "Überlegt noch.")], 13)
		_jump_on_tap(l, s)

	# Protokoll
	_section("Entscheidungen (neueste oben)")
	var lines: Array = st.dlog.duplicate()
	lines.reverse()
	if lines.is_empty():
		_text("Noch keine Entscheidung.", 13, DIM)
	for l in lines.slice(0, 25):
		_text("Tag %d %s  %s" % [int(floor(float(l[0]))) + 1, _clock(float(l[0])), l[1]], 12, DIM)


## Antippen einer Zeile springt zum Siedler. Nur ein echter Klick oder Tipp (linke Taste,
## losgelassen ohne zu ziehen): Mausrad und Wischen zum Scrollen gehen an die Liste weiter.
## Früher reagierte die Zeile auf jedes Drücken, auch auf das Mausrad, und schloss beim
## Scrollen das Fenster.
func _jump_on_tap(l: Control, s) -> void:
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.tooltip_text = "Antippen: zum Siedler springen"
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


# ================================================================== Sprachmodelle
## Welche KI gerade entscheidet, und der Schalter dafür (gilt je Gerät).
func _ki_status() -> void:
	if not Society.enabled:
		return
	var color := UiTheme.GOOD if Llm.state == "bereit" else (UiTheme.BAD if Llm.state == "fehler" else DIM)
	_text(Llm.status_text(), 13, color, Llm.state == "bereit")
	if KiMind.activity != "" and KiMind.active():
		_text("Gerade: %s …" % KiMind.activity, 12, DIM)
	var h := _row()
	if Llm.choice != "llm" or Llm.state in ["fehler", "aus"]:
		_btn(h, "Sprachmodelle laden", "ki", "Llama-3.2-1B (Rat) und SmolLM-135M (Siedler) im Browser laden, einmalig etwa %d MB." % int(Llm.cfg("download_mb", 1250)), func():
			if Llm.state == "fehler":
				Llm.stop()
			Llm.set_choice("llm")
			refresh())
	if Llm.state == "bereit" and not Llm.big_council():
		_btn(h, "Llama trotzdem versuchen", "", "Lädt Llama-3.2-1B für den Rat (über 1 GB). Kann auf diesem Gerät abstürzen; dann nimmt das Spiel beim nächsten Start wieder das kleinere Modell.", func():
			Llm.retry_big()
			refresh())
	if Llm.choice == "llm":
		_btn(h, "Regel-KI nutzen", "", "Sprachmodelle ausschalten, die eingebaute Regel-KI entscheidet.", func():
			Llm.set_choice("regel")
			refresh())
	if KiMind.active():
		var lg: Dictionary = KiMind.lag
		_text("Antworten kommen im Schnitt %.1f Spielstunden nach der Frage an (Rat: Sitzung %.1f Spielstunden, alle Siedler einmal: %.1f)." % [
			float(lg.siedler), float(lg.rat), float(lg.runde)], 12, DIM)
		if KiMind.braking:
			_text("Die Zeit läuft gerade nur normal schnell, bis die KI aufgeholt hat.", 12, RULER)
		var b := CheckButton.new()
		b.text = "Zeit wartet auf die KI"
		b.tooltip_text = "Bei schneller Geschwindigkeit läuft die Zeit nur normal schnell, solange der Rat tagt oder Siedler auf ihre Entscheidung warten. So entscheidet die KI mit aktuellen Angaben."
		b.button_pressed = KiMind.brake
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_color_override("font_color", UiTheme.TEXT)
		b.add_theme_color_override("font_pressed_color", UiTheme.TEXT)
		b.toggled.connect(func(on): KiMind.set_brake(on))
		_body.add_child(b)


func _fill_overview_llm(w) -> void:
	var m: Dictionary = KiMind.mem(w)
	var st: Dictionary = Society.state(w)
	var sd: Dictionary = Society.strategies().get(m.focus, {})
	var h := _row()
	h.add_child(UiTheme.icon_rect(Data.icon(sd.get("icon", "ki")), 20))
	h.add_child(UiTheme.label("Schwerpunkt: %s" % Society.strat_name(m.focus), 16, UiTheme.TEXT, true))
	if str(m.plan) != "":
		_text("Der Rat sagt: „%s“" % m.plan, 14, Color("#2a7a3a"))
	_text("Nächste Ratssitzung: Tag %d %s. Ziel: %s." % [int(floor(float(m.next_council))) + 1, _clock(float(m.next_council)),
		"wachsen und forschen" if _island == 0 else "wachsen"], 13, DIM)
	if m.has("note"):
		_text(str(m.note), 13, UiTheme.BAD)
	var th := _row()
	th.add_child(UiTheme.label("Vertrauen in dich: %d" % int(st.trust), 14, UiTheme.TEXT, true))
	var bar := UiTheme.bar(UiTheme.GOOD if float(st.trust) >= 50.0 else UiTheme.BAD, 10)
	bar.value = float(st.trust)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(bar)
	var r1 := _row()
	_btn(r1, "Mit dem Rat sprechen", "glocke", "Schreibe dem Rat, was er tun soll. Er antwortet und berücksichtigt es.", func():
		_view = "chat"
		refresh())
	_btn(r1, "KI beobachten", "ki", "Was die Modelle sehen, wie wahrscheinlich jede Wahl war, das Gedächtnis des Rats und die letzte Anfrage.", func():
		_view = "ki"
		refresh())
	var r2 := _row()
	_btn(r2, "Feste Vorgaben (%d)" % m.binding.size(), "hammer", "Befehle, die der Rat befolgen muss. Kostet Vertrauen.", func():
		_view = "vorgaben"
		refresh())
	_btn(r2, "Prioritäten", "wissen", "Was dir wichtig ist. Der Rat sieht es und verteilt die Arbeit danach.", func():
		_view = "prio"
		refresh())

	# Aufträge
	var slots: Dictionary = m.get("slots", {})
	if not slots.is_empty():
		_section("Aufträge an die Bewohner")
		var parts := []
		for j in slots:
			if int(slots[j]) > 0:
				parts.append("%d %s" % [int(slots[j]), Data.jobs.get(j, {}).get("name", j)])
		_text(", ".join(parts) + ".", 13)
		var own := []
		for s in w.settlers:
			var d: Dictionary = KiMind.sdec.get(str(s.id), {})
			if d.get("own", false):
				own.append("%s ist %s statt %s" % [s.display_name, Data.jobs.get(d.job, {}).get("name", d.job), Data.jobs.get(d.order, {}).get("name", d.order)])
		if not own.is_empty():
			_text("Eigene Entscheidung: %s." % "; ".join(own), 13, RULER)

	# Anliegen
	var reqs := Society.requests_of(_island)
	if not reqs.is_empty():
		_section("Anliegen an dich (%d)" % reqs.size())
		for r in reqs:
			_request_card(w, r)

	# Letzte Lehren
	if not m.lessons.is_empty():
		_section("Was der Rat gelernt hat")
		var ls: Array = m.lessons.duplicate()
		ls.reverse()
		for l in ls.slice(0, 3):
			_text("%s (%s)" % [l[1], l[2]], 13)

	_section("Chronik")
	var lines: Array = st.log.duplicate()
	lines.reverse()
	if lines.is_empty():
		_text("Noch nichts geschehen.", 13, DIM)
	for l in lines.slice(0, 8):
		_text("Tag %d: %s" % [int(l[0]), l[1]], 13, DIM)


func _back_row() -> void:
	var back := _row()
	_btn(back, "Zurück zum Rat", "", "", func():
		_view = "rat"
		refresh())


# ------------------------------------------------------------------ Chat
func _fill_chat(w) -> void:
	_back_row()
	var m: Dictionary = KiMind.mem(w)
	_section("Gespräch mit dem Rat von %s" % Sea.island_name(w))
	_text("Schreib dem Rat, was er tun soll. Er antwortet und nimmt deinen Wunsch drei Tage lang in seine Entscheidungen mit. Er muss nicht gehorchen; dafür gibt es feste Vorgaben.", 12, DIM)
	if m.chat.is_empty():
		_text("Noch kein Gespräch.", 13, DIM)
	for c in m.chat.slice(maxi(0, m.chat.size() - 14)):
		var you: bool = c[0] == "Du"
		_text("%s: %s" % ["Du" if you else "Rat", c[1]], 14, RULER if you else Color("#2a7a3a"))
	if m.waiting:
		_text("Der Rat berät …", 13, DIM)
	var h := _row()
	var le := LineEdit.new()
	le.placeholder_text = "Deine Nachricht an den Rat"
	le.text = _draft
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.custom_minimum_size.y = 34
	le.add_theme_font_size_override("font_size", 15)
	le.text_changed.connect(func(t): _draft = t)
	h.add_child(le)
	var send := func():
		var t := le.text.strip_edges()
		if t == "" or m.waiting:
			return
		_draft = ""
		KiMind.chat(w, t)
		refresh()
	le.text_submitted.connect(func(_t): send.call())
	_btn(h, "Senden", "", "", send)
	if not KiMind.active():
		_text("Ohne Sprachmodelle antwortet der Rat nicht, dein Wunsch wird aber notiert.", 12, DIM)
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
	if is_instance_valid(le) and not OS.has_feature("mobile") and not Llm.probe.get("mobile", false):
		le.grab_focus()
		le.caret_column = le.text.length()


# ------------------------------------------------------------------ Feste Vorgaben
func _fill_binding(w) -> void:
	_back_row()
	var m: Dictionary = KiMind.mem(w)
	_section("Feste Vorgaben für %s" % Sea.island_name(w))
	_text("Der Rat muss sie befolgen. Jede Vorgabe kostet Vertrauen und drückt kurz die Laune. Schwerpunkt und Arbeiter gelten drei Tage, Bauen und Forschen bis erledigt.", 12, DIM)
	if m.binding.is_empty():
		_text("Keine Vorgaben.", 13, DIM)
	for i in m.binding.size():
		var b: Dictionary = m.binding[i]
		var h := _row()
		var l := UiTheme.label(KiMind._binding_text(b) + (" (bis Tag %d)" % (int(float(b.until)) + 1) if b.kind in ["fokus", "beruf"] else ""), 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var idx: int = i
		_btn(h, "Aufheben", "", "", func(): KiMind.unbind(w, idx))
	var say := func(msg: String):
		if msg != "" and hud:
			hud.toast(msg, "glocke")
		refresh()
	_section("Schwerpunkt bestimmen")
	var fr := HFlowContainer.new()
	_body.add_child(fr)
	for k in Society.strategies():
		if Society.strategy_allowed(k):
			var key: String = k
			_btn(fr, Society.strat_name(k), Society.strategies()[k].get("icon", ""), Society.strategies()[k].get("desc", ""), func(): say.call(KiMind.bind(w, "fokus", key)))
	_section("Arbeiter bestimmen (mindestens einer mehr)")
	var jr := HFlowContainer.new()
	_body.add_child(jr)
	var slots: Dictionary = m.get("slots", {})
	for j in KiMind.JOB_ORDER:
		if not Data.job_unlocked(j):
			continue
		var jj: String = j
		var n := int(slots.get(j, 0)) + 1
		_btn(jr, "%d %s" % [n, Data.jobs[j].name], "", "", func(): say.call(KiMind.bind(w, "beruf", jj, n)))
	_section("Bauen lassen")
	var br := HFlowContainer.new()
	_body.add_child(br)
	var shown := 0
	for t in Data.buildings:
		var def: Dictionary = Data.buildings[t]
		if not def.get("buildable", true) or not Game.is_unlocked(t) or def.has("base") or shown >= 24:
			continue
		var tt: String = t
		var b := _btn(br, def.name, def.get("icon", ""), "Kosten: %s" % KiMind._cost_text(t), func(): say.call(KiMind.bind(w, "bau", tt)))
		b.disabled = not Game.can_afford(def.get("cost", {}), w)
		shown += 1
	_section("Forschen lassen")
	var rr := HFlowContainer.new()
	_body.add_child(rr)
	for t in Data.sorted_tech_ids():
		if Game.tech_state(t) == "available":
			var tt: String = t
			_btn(rr, Data.techs[t].name, "", Data.techs[t].get("desc", ""), func(): say.call(KiMind.bind(w, "forschung", tt)))


# ------------------------------------------------------------------ Prioritäten
func _fill_prio(w) -> void:
	_back_row()
	_section("Prioritäten für %s" % Sea.island_name(w))
	_text("Der Rat sieht deine Prioritäten in jeder Anfrage, und die Arbeit wird danach gewichtet.", 12, DIM)
	var pr: Dictionary = KiMind.cfg("priorities", {})
	for k in pr:
		var h := _row()
		var l := UiTheme.label(pr[k], 14, UiTheme.TEXT, true)
		l.custom_minimum_size.x = 120
		h.add_child(l)
		var cur := KiMind.prio(w, k)
		for v in 4:
			var key: String = k
			var val: int = v
			var b := _btn(h, KiMind.PRIO_WORDS[v], "", "", func():
				KiMind.set_prio(w, key, val)
				refresh())
			b.toggle_mode = true
			b.button_pressed = v == cur
			b.add_theme_font_size_override("font_size", 12)


# ------------------------------------------------------------------ Beobachten
func _fill_watch_llm(w) -> void:
	var m: Dictionary = KiMind.mem(w)
	_section("Sprachmodelle")
	_text(Llm.status_text(), 13)
	_text("Anfragen bisher: Rat %d (im Schnitt %.1f s), Siedler %d (im Schnitt %.2f s)." % [int(Llm.stats.rat[0]), Llm.avg_ms("rat") / 1000.0,
		int(Llm.stats.siedler[0]), Llm.avg_ms("siedler") / 1000.0], 12, DIM)
	if KiMind.activity != "":
		_text("Gerade: %s …" % KiMind.activity, 13, RULER)
	var last: Dictionary = m.get("last", {})
	_section("Letzte Ratssitzung (Llama)")
	if last.is_empty():
		_text("Der Rat hat noch nicht getagt.", 13, DIM)
	for k in [["focus", "Schwerpunkt"], ["jobs", "Arbeit"], ["build", "Bauen"], ["research", "Forschung"]]:
		if last.has(k[0]):
			var d: Dictionary = last[k[0]]
			var t: String = ("%s: %s" % [k[1], d.get("choice", "")]) if d.has("choice") else str(k[1])
			if d.has("probs"):
				t += ". Modell: %s" % d.probs
			if d.has("why"):
				t += " (%s)" % d.why
			if d.has("mass"):
				t += ". Antwort als Nummer: %d %%" % int(float(d.mass) * 100.0)
			_text(t, 13)
	if last.has("trade"):
		_text("Handel: %s" % last.trade, 13)
	if str(m.plan) != "":
		_text("Plan: „%s“" % m.plan, 13, Color("#2a7a3a"))
	for t in KiMind.trades:
		if int(t.to) == _island or int(t.from) == _island:
			_text("Handelsroute bis Tag %d: %s bringt %s, bekommt %s." % [int(float(t.until)) + 1, Sea.meta(int(t.from)).get("name", "?"),
				Sea.goods_text(t.get("get", {})), Sea.goods_text(t.give) if not t.give.is_empty() else "nichts"], 13)

	_section("Siedler (SmolLM): Auftrag und eigene Entscheidung")
	for s in w.settlers:
		if not s.is_adult():
			continue
		var d: Dictionary = KiMind.sdec.get(str(s.id), {})
		var t := "%s: " % s.display_name
		if d.is_empty():
			t += Society.thoughts.get(s.id, "hat noch nicht entschieden.")
		else:
			var order: String = d.get("order", "")
			t += "Auftrag %s, entscheidet %s%s. Modell: %s. Klarheit %.1f%s" % [Data.jobs.get(order, {}).get("name", "keiner") if order != "" else "keiner",
				Data.jobs.get(d.job, {}).get("name", d.job), " (eigene Wahl)" if d.get("own", false) else "", d.get("probs", ""),
				float(d.get("clarity", 0.0)), ", unentschlossen" if str(d.get("rule", "Modell")) != "Modell" else ""]
		var l := _text(t, 13, RULER if d.get("own", false) else UiTheme.TEXT)
		_jump_on_tap(l, s)

	_section("Gedächtnis des Rats")
	if m.lessons.is_empty():
		_text("Noch keine Lehren.", 13, DIM)
	for l in m.lessons:
		_text("Lehre (Tag %d, %s): %s" % [int(float(l[0])) + 1, "selbst gezogen" if l[2] == "Rat" else "aus Messung", l[1]], 13)
	var ex := KiMind.experience_lines(w, 8)
	if not ex.is_empty():
		_text("Gemessene Erfahrung (je Tag nach der Entscheidung):", 13, UiTheme.TEXT, true)
		for e in ex:
			_text(e, 12)
	var recs: Array = m.records.duplicate()
	recs.reverse()
	if not recs.is_empty():
		_text("Entscheidungen und Folgen:", 13, UiTheme.TEXT, true)
	for r in recs.slice(0, 6):
		_text(KiMind.record_text(r), 12, DIM)

	_section("Bericht")
	var rr0 := _row()
	_btn(rr0, "KI-Bericht herunterladen", "buch", "Textdatei mit allen Anfragen, Wahrscheinlichkeiten und Entscheidungen seit dem Start.", func():
		var f := KiMind.download_report()
		if hud:
			hud.toast("KI-Bericht gespeichert: %s" % f, "buch"))
	_text("%d Anfragen festgehalten." % KiMind.trace_count, 12, DIM)

	_section("Letzte Anfrage an ein Modell")
	var pr := _row()
	for role in ["rat", "siedler"]:
		var rr: String = role
		var b := _btn(pr, "Rat (Llama)" if role == "rat" else "Siedler (SmolLM)", "", "Zeigt den Text, den das Modell zuletzt bekommen hat.", func():
			_show_prompt = "" if _show_prompt == rr else rr
			refresh())
		b.toggle_mode = true
		b.button_pressed = _show_prompt == role
	if _show_prompt != "":
		_text(str(KiMind.last_prompt.get(_show_prompt, "Noch keine Anfrage.")), 11, DIM)

	_section("Entscheidungen (neueste oben)")
	var lines: Array = Society.state(w).dlog.duplicate()
	lines.reverse()
	for l in lines.slice(0, 25):
		_text("Tag %d %s  %s" % [int(floor(float(l[0]))) + 1, _clock(float(l[0])), l[1]], 12, DIM)
