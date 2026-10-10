class_name FestVideo
extends ColorRect
## Kleines Fest-Video (gut 5 Sekunden): Siedler tanzen um ein Lagerfeuer, Wimpelkette und Laternen,
## Feuerwerk und Konfetti, Banner "Fest!" mit dem Anlass. Alles prozedural im 16x16-Pixelstil:
## eine kleine Pixelbühne (W x H Bildpunkte, ganzzahlig vergrößert), Siedler aus den Spiel-Sprites.
## Jedes Bild ist eine reine Funktion der Zeit t (Bildschirmfotos mit --festframe sind reproduzierbar).
## Start: Exams.fest_started (bestandene Prüfung). Das Spiel läuft weiter; Tippen/Klicken oder
## Esc/Leertaste überspringt, nach DURATION schließt es sich selbst. In Selbsttests (--autotest) nur
## mit --festvideo=1 (Test) oder --panel=fest [--festframe=<Sekunden>] (Bildschirmfoto).

const DURATION := 5.5
const H := 96  # Bühnenhöhe in Pixeln; die Breite W passt sich dem Bildschirm an (100..180)
const DANCERS := 6
## Feuerwerk: [Zeit, x-Anteil der Breite, Höhe, Farbe]
const BURSTS := [[0.8, 0.24, 24.0, "#ffd84a"], [1.4, 0.76, 20.0, "#ff6a8a"], [2.0, 0.5, 30.0, "#7ae0ff"],
	[2.6, 0.14, 22.0, "#a8ff6a"], [3.1, 0.86, 26.0, "#ffd84a"], [3.6, 0.38, 18.0, "#d08aff"],
	[4.1, 0.66, 28.0, "#ff9a3a"], [4.5, 0.3, 24.0, "#7ae0ff"]]
const CONFETTI := ["#e8483a", "#ffd84a", "#4f8fd6", "#58b06a", "#e08ae0", "#fff6e0"]
const FLAGS := ["#d0484a", "#ffd84a", "#4f8fd6", "#58b06a", "#e08a40"]

static var current: FestVideo = null
static var shown := 0  # Selbsttest: wie oft das Video aufging
static var last := [0.0, 0]  # Selbsttest: Laufzeit und Bilder des zuletzt geschlossenen Videos

var reason := ""
var t := 0.0
var frozen := -1.0  # >= 0: Standbild zu dieser Zeit (Bildschirmfoto), schließt nicht selbst
var frames := 0
var _k := 3
var _w := 160
var _stage: Control
var _panel: PanelContainer
var _title: Label
var _reason: Label
var _hint: Label
var _looks: Array = []
var _last_us := 0
var _vs := Vector2.ZERO


# ---------------------------------------------------------------- Einbindung
## Hud.setup: bei jedem Fest das Video zeigen; Testhilfen --festvideo und --panel=fest.
static func attach(hud) -> void:
	var args := _args()
	Exams.fest_started.connect(func(text: String):
		if is_instance_valid(hud) and allowed():
			play(hud, text))
	if args.get("panel", "") == "fest":
		hud.get_tree().create_timer(1.0).timeout.connect(func():
			var v := play(hud, Loc.t("Ein neues Zeitalter: %s") % Data.age_name(1))
			v.frozen = float(args.get("festframe", "2.4"))
			v.t = v.frozen
			print("Fest-Video Standbild bei %.1f s" % v.frozen))
	if args.has("festvideo"):
		_selftest(hud)


static func _args() -> Dictionary:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return a


static var _allow_test := true  # Selbsttest: Sperre in Selbsttests nachprüfen


## Im Spiel immer; in Selbsttests nur, wenn ein Testschalter es verlangt.
static func allowed() -> bool:
	var a := _args()
	if not a.has("autotest"):
		return true
	return _allow_test and (a.has("festvideo") or a.get("panel", "") == "fest")


static func play(hud, text: String) -> FestVideo:
	if current and is_instance_valid(current):
		current.queue_free()
	var v := FestVideo.new()
	v.reason = text
	hud.root.add_child(v)
	current = v
	shown += 1
	Sound.play("stufe")
	return v


# ---------------------------------------------------------------- Aufbau
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.03, 0.04, 0.1, 0.55)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(_panel)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	_panel.add_child(v)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.clip_contents = true
	_stage.draw.connect(_draw_stage)
	v.add_child(_stage)
	_title = _text_label(tr("Fest!"), Color("#fff6e0"))
	_reason = _text_label(reason, Color("#ffe9a8"))
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = UiTheme.label(tr("Tippen oder klicken zum Überspringen"), 12)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hint)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711  # immer dieselben Tänzer
	for i in DANCERS:
		_looks.append(Settler.random_look(rng))
	_last_us = Time.get_ticks_usec()
	_fit()


func _text_label(text: String, col: Color) -> Label:
	var l := UiTheme.label(text, 16, col, true)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color("#2a1418"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(l)
	return l


## Vergrößerung k und Bühnenbreite W nach dem Bildschirm (Handy 360 px: k 3, W 121; PC 960x540: k 4, W 180).
func _fit() -> void:
	_vs = get_viewport().get_visible_rect().size
	_k = clampi(int(minf((_vs.x - 36.0) / 120.0, (_vs.y - 110.0) / float(H))), 1, 5)
	_w = clampi(int((_vs.x - 36.0) / _k), 100, 180)
	_stage.custom_minimum_size = Vector2(_w * _k, H * _k)
	_title.add_theme_font_size_override("font_size", 7 * _k + 2)
	_title.add_theme_constant_override("outline_size", maxi(2, _k + 1))
	_reason.add_theme_font_size_override("font_size", 3 * _k + 6)
	_reason.add_theme_constant_override("outline_size", maxi(2, _k))
	_reason.custom_minimum_size.x = _w * _k - 8
	_hint.custom_minimum_size.x = _w * _k
	_panel.reset_size()


# ---------------------------------------------------------------- Ablauf
func _process(delta: float) -> void:
	# Echtzeit, unabhängig von der Spielgeschwindigkeit (auch bei Pause)
	var now := Time.get_ticks_usec()
	var dt := delta / Engine.time_scale if Engine.time_scale > 0.0 else minf(0.1, (now - _last_us) / 1e6)
	_last_us = now
	if get_viewport().get_visible_rect().size != _vs:
		_fit()
	if get_index() < get_parent().get_child_count() - 1:
		move_to_front()  # über Zeigerpfeil, Meldungen und Fenstern bleiben
	if frozen >= 0.0:
		t = frozen
	else:
		t += dt
		if t >= DURATION:
			close()
			return
	frames += 1
	modulate.a = clampf(minf(t / 0.25, (DURATION - t) / 0.4), 0.0, 1.0) if frozen < 0.0 else 1.0
	_place_labels()
	_stage.queue_redraw()


func close() -> void:
	last = [t, frames]
	if current == self:
		current = null
	queue_free()


func _gui_input(ev: InputEvent) -> void:
	var tap: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]) \
		or (ev is InputEventScreenTouch and ev.pressed)
	if tap:
		accept_event()
		close()


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
		get_viewport().set_input_as_handled()
		close()


## Banner fällt in der ersten halben Sekunde herein (mit kleinem Nachfedern).
func _banner_y() -> float:
	var u := clampf(t / 0.5, 0.0, 1.0)
	var e := 1.0 + 2.7 * pow(u - 1.0, 3) + 1.7 * pow(u - 1.0, 2)  # ease-out-back
	return lerpf(-24.0, 4.0, e)


func _place_labels() -> void:
	var by := _banner_y()
	_title.reset_size()
	_title.position = Vector2((_w * _k - _title.size.x) / 2.0, (by + 8.0) * _k - _title.size.y / 2.0)
	_reason.reset_size()
	_reason.position = Vector2(4, (by + 18.0) * _k)
	_reason.modulate.a = clampf((t - 0.35) / 0.3, 0.0, 1.0)


# ---------------------------------------------------------------- Zeichnen
func _px(x: float, y: float, w: float, h: float, c: Color) -> void:
	_stage.draw_rect(Rect2(Vector2(floorf(x), floorf(y)) * _k, Vector2(w, h) * _k), c)


## Pixel-Ellipse (Schein von Feuer, Laternen, Feuerwerk) aus waagrechten Streifen.
func _blob(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	if rx < 1.0 or ry < 1.0:
		return
	for yy in range(-int(ry), int(ry) + 1):
		var hw := floorf(rx * sqrt(maxf(0.0, 1.0 - pow(yy / ry, 2))))
		_px(cx - hw, cy + yy, hw * 2.0 + 1.0, 1, c)


## Pseudozufall aus einer Zahl (gleiche Zahl, gleicher Wert 0..1).
static func _h(n: float) -> float:
	return fposmod(sin(n * 12.9898 + 78.233) * 43758.5453, 1.0)


func _draw_stage() -> void:
	var w := float(_w)
	_draw_sky(w)
	_draw_fireworks(w)  # weit weg: hinter Meer, Wimpeln und Tänzern
	_draw_ground(w)
	_draw_garland(w)
	var cx := floorf(w / 2.0)
	var gy := 74.0
	# Feuerschein auf dem Boden
	var fl := 0.85 + 0.15 * sin(t * 17.0) * sin(t * 7.3)
	for r in [[26.0, 0.10], [17.0, 0.12], [10.0, 0.16]]:
		_blob(cx, gy - 2.0, floorf(r[0] * fl), floorf(r[0] * fl * 0.45), Color(1.0, 0.6, 0.2, r[1]))
	# Tänzer im Kreis: hintere vor dem Feuer zeichnen, vordere danach
	var dancers := []
	var rx := minf(w * 0.3, 44.0)
	for i in DANCERS:
		var a := float(i) * TAU / DANCERS + t * 0.9
		dancers.append([gy - 2.0 + sin(a) * 11.0, i, a])
	dancers.sort_custom(func(p, q): return p[0] < q[0])
	for d in dancers:
		if d[0] < gy - 2.0:
			_draw_dancer(d[1], d[2], cx, gy, rx)
	_draw_fire(cx, gy)
	for d in dancers:
		if d[0] >= gy - 2.0:
			_draw_dancer(d[1], d[2], cx, gy, rx)
	_draw_confetti(w)
	_draw_banner(w)


func _draw_sky(w: float) -> void:
	var bands := ["#141a36", "#1a2142", "#202a4e", "#28305a", "#323866", "#3e3e70"]
	for i in bands.size():
		_px(0, i * 9.0, w, 9.0, Color(bands[i]))
	for i in 22:
		var sx := floorf(_h(i) * w)
		var sy := floorf(_h(i + 40.0) * 46.0)
		var tw := sin(t * (2.0 + _h(i + 80.0) * 3.0) + i)
		if tw > -0.4:
			_px(sx, sy, 1, 1, Color(1, 1, 0.9, 0.5 + 0.5 * tw))
		if i % 7 == 0 and tw > 0.6:
			_px(sx - 1, sy, 3, 1, Color(1, 1, 0.9, 0.5))
			_px(sx, sy - 1, 1, 3, Color(1, 1, 0.9, 0.5))
	# Mond
	var mx := w - 20.0
	_px(mx + 1, 7, 4, 6, Color("#f4ecc8"))
	_px(mx, 8, 6, 4, Color("#f4ecc8"))
	_px(mx + 3, 7, 3, 5, Color("#323866"))


func _draw_ground(w: float) -> void:
	_px(0, 50, w, 7, Color("#2c4f86"))
	for i in 10:
		var wx := fposmod(_h(i + 7.0) * w + t * 6.0, w)
		_px(wx, 52 + (i % 3) * 2, 3, 1, Color("#5a84c0"))
	_px(0, 57, w, 3, Color("#d8c08a"))
	_px(0, 60, w, H - 60.0, Color("#4f8a3a"))
	for i in 40:
		_px(floorf(_h(i + 200.0) * w), 61.0 + floorf(_h(i + 300.0) * 34.0), 2, 1, Color("#3f7430"))
		_px(floorf(_h(i + 400.0) * w), 61.0 + floorf(_h(i + 500.0) * 34.0), 1, 1, Color("#6aa84a"))
	for i in 9:  # Blumen im Vordergrund
		var fx := floorf(4.0 + _h(i + 1200.0) * (w - 8.0))
		var fy := 86.0 + floorf(_h(i + 1300.0) * 7.0)
		var fc := Color(CONFETTI[i % CONFETTI.size()])
		_px(fx, fy, 1, 2, Color("#2f5a24"))
		_px(fx - 1, fy - 1, 3, 1, fc)
		_px(fx, fy - 2, 1, 3, fc)
		_px(fx, fy - 1, 1, 1, Color("#ffd84a"))


## Wimpelkette zwischen zwei Pfählen, mit drei Laternen.
func _draw_garland(w: float) -> void:
	var x0 := 8.0
	var x1 := w - 9.0
	for px_ in [x0, x1]:
		_px(px_ - 1, 26, 2, 42, Color("#6b4226"))
		_px(px_ - 1, 26, 1, 42, Color("#8a5a32"))
	var mid := (x0 + x1) / 2.0
	var half := (x1 - x0) / 2.0
	var sway := sin(t * 2.2) * 1.2
	var rope := func(x: float) -> float:
		var u := (x - mid) / half
		return 28.0 + (7.0 + sway) * (1.0 - u * u)
	for x in range(int(x0), int(x1) + 1):
		_px(x, rope.call(float(x)), 1, 1, Color("#3a2a22"))
	var n := 0
	var x := x0 + 4.0
	while x < x1 - 3.0:
		var y: float = rope.call(x) + 1.0
		var col := Color(FLAGS[n % FLAGS.size()])
		_px(x - 2, y, 5, 1, col)
		_px(x - 1, y + 1, 3, 2, col)
		_px(x, y + 3, 1, 1, col)
		n += 1
		x += 7.0
	for f in [0.22, 0.5, 0.78]:
		var lx := floorf(x0 + (x1 - x0) * f)
		var ly: float = rope.call(lx) + 2.0
		var glow := 0.2 + 0.05 * sin(t * 5.0 + f * 9.0)
		_blob(lx + 1.0, ly + 4.0, 7.0, 6.0, Color(0.8, 0.4, 0.15, glow * 1.5))
		_blob(lx + 1.0, ly + 4.0, 4.0, 4.0, Color(1.0, 0.72, 0.3, glow * 2.0))
		_px(lx + 1, ly, 1, 1, Color("#3a2a22"))
		_px(lx, ly + 1, 3, 1, Color("#8a3a1a"))
		_px(lx - 1, ly + 2, 5, 4, Color("#e8702a"))
		_px(lx, ly + 3, 3, 2, Color("#ffd84a"))
		_px(lx, ly + 6, 3, 1, Color("#8a3a1a"))


func _draw_fire(cx: float, gy: float) -> void:
	# Holzscheite
	_px(cx - 7, gy - 2, 14, 2, Color("#5a3820"))
	_px(cx - 6, gy - 3, 5, 1, Color("#7a4a28"))
	_px(cx + 1, gy - 3, 5, 1, Color("#7a4a28"))
	_px(cx - 8, gy, 16, 1, Color("#3a2414"))
	# Flamme: Zeilen von unten nach oben, Breite flackert je Bild
	var f := int(t * 10.0)
	var rows := [10, 10, 9, 8, 8, 6, 5, 4, 3, 2, 1]
	for r in rows.size():
		var wr := float(rows[r]) + floorf(_h(f * 13.0 + r) * 3.0) - 1.0
		if wr <= 0.0:
			continue
		var y := gy - 4.0 - r
		var off := floorf((_h(f * 7.0 + r * 3.0) - 0.5) * 2.0) if r > 3 else 0.0
		var x := cx - floorf(wr / 2.0) + off
		_px(x, y, wr, 1, Color("#d8402a"))
		if wr > 2.0:
			_px(x + 1, y, wr - 2.0, 1, Color("#f08a2a"))
		if wr > 5.0 and r < 7:
			_px(x + 2, y, wr - 4.0, 1, Color("#ffd84a"))
		if wr > 7.0 and r < 4:
			_px(x + 3, y, wr - 6.0, 1, Color("#fff6c0"))
	# Funken steigen auf
	for i in 7:
		var per := 1.1 + _h(i + 600.0) * 0.6
		var u := fposmod(t + _h(i + 700.0) * per, per) / per
		var sx := cx + sin(u * 6.0 + i) * 4.0 + (_h(i + 800.0) - 0.5) * 6.0
		_px(sx, gy - 10.0 - u * 30.0, 1, 1, Color(1.0, 0.85 - u * 0.4, 0.3, 1.0 - u))


## Siedler i tanzt auf der Ellipse um das Feuer (Spiel-Sprites, Lauf-Bilder, kleine Sprünge).
func _draw_dancer(i: int, a: float, cx: float, gy: float, rx: float) -> void:
	var x := cx + cos(a) * rx
	var y := gy - 2.0 + sin(a) * 11.0
	var vx := -sin(a) * rx
	var vy := cos(a) * 11.0
	var dir := 2
	var flip := false
	if absf(vx) > absf(vy) * 2.5:
		flip = vx < 0.0
	else:
		dir = 0 if vy > 0.0 else 1
	var hop := floorf(absf(sin(t * 7.0 + i * 1.3)) * 3.0)
	_px(x - 3, y, 6, 1, Color(0, 0, 0, 0.3))
	var look: Dictionary = _looks[i]
	var style := int(look.get("style", 0))
	var frame := dir * 4 + (int(t * 9.0) + i) % 4
	var src := Rect2((frame % 4) * 16, (frame / 4) * 24, 16, 24)
	var dst := Rect2(Vector2(floorf(x) - 8.0, floorf(y) - 22.0 - hop) * _k, Vector2(16, 24) * _k)
	if flip:
		dst = Rect2(dst.position + Vector2(dst.size.x, 0), Vector2(-dst.size.x, dst.size.y))
	for o in [["pants", "pants"], ["shirt", "shirt"], ["skin", "skin"], ["hair_%d" % style, "hair"],
			["fixed_bun" if style == 2 else "fixed", ""]]:
		var col := Color(look.get(o[1], "#ffffff")) if o[1] != "" else Color.WHITE
		_stage.draw_texture_rect_region(Settler.sheet(o[0]), dst, src, col)
	# Arme hoch: zwei Hände über dem Kopf im Takt
	if int(t * 4.0 + i) % 2 == 0:
		var skin := Color(look.get("skin", "#f2c9a0"))
		_px(x - 5, y - 19 - hop, 1, 2, skin)
		_px(x + 4, y - 19 - hop, 1, 2, skin)


func _draw_fireworks(w: float) -> void:
	for bi in BURSTS.size():
		var b: Array = BURSTS[bi]
		var t0: float = b[0]
		var bx := floorf(w * float(b[1]))
		var by: float = b[2]
		var col := Color(b[3])
		var dt := t - t0
		if dt < -0.55 or dt > 1.3:
			continue
		if dt < 0.0:  # Rakete steigt
			var u := (dt + 0.55) / 0.55
			var ry := lerpf(50.0, by, 1.0 - pow(1.0 - u, 2))
			_px(bx, ry, 1, 2, Color("#fff6e0"))
			_px(bx, ry + 2, 1, 2, Color(1.0, 0.7, 0.3, 0.6))
			continue
		if dt < 0.12:
			var rr := floorf(4.0 + dt * 40.0)
			_blob(bx, by, rr, rr, Color(col, 0.3))
		var n := 18
		var fade := clampf((1.3 - dt) / 0.6, 0.0, 1.0)  # erst hell, dann verglühen
		for j in n:
			var ang := TAU * j / n + bi
			var sp := 18.0 + _h(bi * 31.0 + j) * 7.0
			var px_ := bx + cos(ang) * sp * dt
			var py := by + sin(ang) * sp * dt + 9.0 * dt * dt
			var c := col.lerp(Color.WHITE, 0.4) if j % 3 == 0 else col
			if dt > 0.7 and int(t * 20.0 + j) % 3 == 0:
				continue  # Glitzern beim Verglühen
			_px(px_, py, 1, 1, Color(c, fade))
			for k2 in [1, 2]:  # Schweif
				var dt2 := maxf(0.0, dt - 0.07 * k2)
				_px(bx + cos(ang) * sp * dt2, by + sin(ang) * sp * dt2 + 9.0 * dt2 * dt2, 1, 1, Color(col, fade * (0.6 - 0.25 * k2)))


func _draw_confetti(w: float) -> void:
	for i in 44:
		var start := 1.0 + _h(i + 900.0) * 2.6
		var dt := t - start
		if dt < 0.0:
			continue
		var y := -3.0 + dt * (14.0 + _h(i + 1000.0) * 10.0)
		if y > H:
			continue
		var x := _h(i + 1100.0) * w + sin(t * 3.0 + i) * 3.0
		var flat := sin(t * 8.0 + i * 0.7) > 0.0
		_px(x, y, 2 if flat else 1, 1 if flat else 2, Color(CONFETTI[i % CONFETTI.size()]))


## Rotes Band mit Goldrand und eingeschnittenen Enden; Text "Fest!" liegt als Label darüber.
func _draw_banner(w: float) -> void:
	var by := floorf(_banner_y())
	var bw := minf(w - 28.0, 84.0)
	var bx := floorf((w - bw) / 2.0)
	var dark := Color("#8a2420")
	var red := Color("#c8382e")
	var gold := Color("#ffd84a")
	# Enden hinter dem Band, mit V-Schnitt nach außen
	for side in [-1, 1]:
		for r in 12:
			var d := maxf(0.0, 3.0 - absf(r - 5.5))  # Tiefe der Kerbe
			if side < 0:
				_px(bx - 9.0 + d, by + 4 + r, 10.0 - d, 1, dark)
			else:
				_px(bx + bw - 1.0, by + 4 + r, 10.0 - d, 1, dark)
	_px(bx, by, bw, 16, red)
	_px(bx, by, bw, 1, gold)
	_px(bx, by + 15, bw, 1, gold)
	_px(bx, by + 2, bw, 1, Color("#e05a40"))
	_px(bx, by + 13, bw, 1, dark)
	for side in [bx + 2.0, bx + bw - 4.0]:
		_px(side, by + 6, 2, 2, gold)
		_px(side, by + 9, 2, 1, gold)


# ---------------------------------------------------------------- Selbsttest
## --festvideo=1: echte Prüfung bestehen (Video geht auf, Sound), Ablauf bis zum Selbstschließen,
## Überspringen per Klick, per Fingertipp und per Taste, Sperre in Selbsttests ohne Schalter.
static func _selftest(hud) -> void:
	var tree: SceneTree = hud.get_tree()
	await tree.create_timer(3.0).timeout
	var ok := true
	var n0 := shown
	Sound._last_play.erase("stufe")
	Exams.pass_exam()
	var v := current
	var opened := v != null and is_instance_valid(v) and shown == n0 + 1
	print("FESTVIDEO: Pruefung bestanden -> Video offen=%s Grund='%s' Sound stufe=%s Taenzer=%d Feuerwerk=%d" % [
		opened, v.reason if opened else "", Sound._last_play.has("stufe"), DANCERS, BURSTS.size()])
	ok = ok and opened and Sound._last_play.has("stufe") and v.reason.contains(Data.age_name(Exams.current_age()))
	if not opened:
		print("FESTVIDEO FEHLER")
		return
	await tree.process_frame
	await tree.process_frame
	var vs := v.get_viewport().get_visible_rect().size
	var r := v._panel.get_global_rect()
	print("FESTVIDEO: Buehne %dx%d Pixel x%d = %dx%d, Fenster %s im Bild %s, oberstes Element %s" % [v._w, H, v._k,
		v._stage.size.x, v._stage.size.y, r, Rect2(Vector2.ZERO, vs).encloses(r), v.get_index() == hud.root.get_child_count() - 1])
	ok = ok and Rect2(Vector2.ZERO, vs).encloses(r)
	print("FESTVIDEO: Viewport %s, letztes Element in root: %s" % [vs, hud.root.get_child(-1)])
	var day0 := Game.time_days
	while is_instance_valid(v) and not v.is_queued_for_deletion():
		await tree.process_frame
	print("FESTVIDEO: schliesst selbst nach %.2f s Echtzeit, %d Bilder; Spiel lief weiter: %s (Tag +%.3f)" % [last[0], last[1], Game.time_days > day0, Game.time_days - day0])
	ok = ok and last[0] >= DURATION and last[1] > 100 and Game.time_days > day0
	# Überspringen: Maus, Finger, Taste
	for kind in ["click", "touch", "key"]:
		v = play(hud, "-")
		for i in 30:
			await tree.process_frame
		var ev: InputEvent
		if kind == "click":
			ev = InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			v._gui_input(ev)
		elif kind == "touch":
			ev = InputEventScreenTouch.new()
			ev.pressed = true
			v._gui_input(ev)
		else:
			ev = InputEventKey.new()
			ev.keycode = KEY_ESCAPE
			ev.pressed = true
			v._input(ev)
		var gone := v.is_queued_for_deletion() and current == null
		print("FESTVIDEO: %s ueberspringt nach %.2f s: %s" % [kind, last[0], gone])
		ok = ok and gone
	await tree.process_frame
	# Sperre: im Selbsttest ohne Schalter kein Video
	_allow_test = false
	var n1 := shown
	Exams.fest_started.emit("-")
	print("FESTVIDEO: ohne Testschalter kein Video: %s" % (shown == n1 and current == null))
	ok = ok and shown == n1 and current == null
	_allow_test = true
	print("FESTVIDEO OK" if ok else "FESTVIDEO FEHLER")
