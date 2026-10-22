class_name ProtestVideo
extends ColorRect
## Protest-Video (josh 2026-10-11): Siedler marschieren mit Protestschildern (durchgestrichene Uhr, "!")
## und erhobenen Fäusten vor der Verwaltung auf und ab, rufen in Sprechblasen, dunkle Wolken ziehen auf,
## die Uhr am Dach rast. Banner "Protest!" und darunter der Grund. Alles prozedural im 16x16-Pixelstil wie
## FestVideo: kleine Pixelbühne (W x H Bildpunkte, ganzzahlig vergrößert), Siedler aus den Spiel-Sprites,
## Gebäude aus buildings.png. Jedes Bild ist eine reine Funktion der Zeit t; die Szene wiederholt sich
## nahtlos alle PERIOD Sekunden. Anders als FestVideo schließt es sich nie selbst und nicht durch Tippen:
## es läuft, bis man "Schließen" drückt (oder Esc). Das Spiel läuft darunter weiter.
## Start: Admin.protest_started (Protest gegen Überstunden). In Selbsttests (--autotest) nur mit
## --protestvideo=1 (Test) oder --panel=protest [--protestframe=<Sekunden>] (Bildschirmfoto).

const PERIOD := 4.0  # Länge einer Schleife in Sekunden (nahtlos)
const H := 96  # Bühnenhöhe in Pixeln; die Breite W passt sich dem Bildschirm an (100..180)
const MARCHERS := 6
## Was jeder Marschierer hochhält: 0 Schild mit durchgestrichener Uhr, 1 Schild "!", 2 Faust
const HOLDS := [0, 2, 1, 1, 0, 2]
const GROUND := 72.0  # Unterkante der Gebäude, Anfang des Platzes
const ROWS := [84.0, 93.0]  # Fußlinie hintere / vordere Reihe
const RED := Color("#c8302a")
const INK := Color("#3a2a22")
const CARD := Color("#f2e6c8")
const STICK := Color("#7a4a28")

static var current: ProtestVideo = null
static var shown := 0  # Selbsttest: wie oft das Video aufging
static var last := [0.0, 0]  # Selbsttest: Laufzeit und Bilder des zuletzt geschlossenen Videos

var reason := ""
var t := 0.0
var frozen := -1.0  # >= 0: Standbild zu dieser Zeit (Bildschirmfoto)
var frames := 0
var _k := 3
var _w := 160
var _stage: Control
var _panel: PanelContainer
var _title: Label
var _reason: Label
var _close_btn: Button
var _looks: Array = []
var _last_us := 0
var _vs := Vector2.ZERO


# ---------------------------------------------------------------- Einbindung
## Hud.setup: bei jedem Protest gegen Überstunden das Video zeigen; Testhilfen --protestvideo, --panel=protest.
static func attach(hud) -> void:
	var args := _args()
	Admin.protest_started.connect(func(_job: String, text: String):
		if is_instance_valid(hud) and allowed():
			play(hud, text))
	if args.get("panel", "") == "protest":
		hud.get_tree().create_timer(1.0).timeout.connect(func():
			var v := play(hud, Loc.t("Die Leute im Beruf %s protestieren gegen zu lange Überstunden.") % Admin._name("handwerker"))
			v.frozen = float(args.get("protestframe", "1.3"))
			v.t = v.frozen
			print("Protest-Video Standbild bei %.1f s" % v.frozen))
	if args.has("protestvideo"):
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
	return _allow_test and (a.has("protestvideo") or a.get("panel", "") == "protest")


static func play(hud, text: String) -> ProtestVideo:
	if current and is_instance_valid(current):
		current.queue_free()
	var v := ProtestVideo.new()
	v.reason = text
	hud.root.add_child(v)
	current = v
	shown += 1
	Sound.play("warnung")
	return v


# ---------------------------------------------------------------- Aufbau
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.03, 0.04, 0.1, 0.55)
	mouse_filter = Control.MOUSE_FILTER_STOP  # Tippen daneben schließt nicht und erreicht das Spiel nicht
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	c.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.clip_contents = true
	_stage.draw.connect(_draw_stage)
	v.add_child(_stage)
	_title = UiTheme.label(tr("Protest!"), 16, Color("#c8302a"), true)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_outline_color", Color("#fff6e0"))
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_title)
	_reason = UiTheme.label(reason, 16)
	_reason.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_reason)
	var row := CenterContainer.new()
	v.add_child(row)
	_close_btn = UiTheme.button(tr("Schließen"))
	_close_btn.custom_minimum_size.x = 140
	_close_btn.pressed.connect(func():
		Sound.play("zu")
		close())
	row.add_child(_close_btn)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1848  # immer dieselben Leute
	for i in MARCHERS:
		_looks.append(Settler.random_look(rng))
	_last_us = Time.get_ticks_usec()
	_fit()


## Vergrößerung k und Bühnenbreite W nach dem Bildschirm (wie FestVideo; unten Platz für Grund und Knopf).
func _fit() -> void:
	_vs = get_viewport().get_visible_rect().size
	_k = clampi(int(minf((_vs.x - 36.0) / 120.0, (_vs.y - 150.0) / float(H))), 1, 5)
	_w = clampi(int((_vs.x - 36.0) / _k), 100, 180)
	_stage.custom_minimum_size = Vector2(_w * _k, H * _k)
	_title.add_theme_font_size_override("font_size", 7 * _k + 2)
	_title.add_theme_constant_override("outline_size", maxi(2, _k))
	_reason.add_theme_font_size_override("font_size", maxi(15, 2 * _k + 9))
	_reason.custom_minimum_size.x = _w * _k
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
	t = frozen if frozen >= 0.0 else t + dt
	frames += 1
	modulate.a = clampf(t / 0.25, 0.0, 1.0) if frozen < 0.0 else 1.0
	_place_labels()
	_stage.queue_redraw()


func close() -> void:
	last = [t, frames]
	if current == self:
		current = null
	queue_free()


## Tippen oder Klicken neben den Knopf schließt nicht (das Video läuft, bis man "Schließen" drückt).
func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton or ev is InputEventScreenTouch:
		accept_event()


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


## Banner fällt in der ersten halben Sekunde herein (mit kleinem Nachfedern), danach hängt es.
func _banner_y() -> float:
	var u := clampf(t / 0.5, 0.0, 1.0)
	var e := 1.0 + 2.7 * pow(u - 1.0, 3) + 1.7 * pow(u - 1.0, 2)  # ease-out-back
	return lerpf(-22.0, 3.0, e)


func _place_labels() -> void:
	var by := _banner_y()
	_title.reset_size()
	_title.position = Vector2((_w * _k - _title.size.x) / 2.0, (by + 8.0) * _k - _title.size.y / 2.0)


# ---------------------------------------------------------------- Zeichnen
func _px(x: float, y: float, w: float, h: float, c: Color) -> void:
	_stage.draw_rect(Rect2(Vector2(floorf(x), floorf(y)) * _k, Vector2(w, h) * _k), c)


## Pixel-Ellipse aus waagrechten Streifen (Wolken).
func _blob(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	if rx < 1.0 or ry < 1.0:
		return
	for yy in range(-int(ry), int(ry) + 1):
		var hw := floorf(rx * sqrt(maxf(0.0, 1.0 - pow(yy / ry, 2))))
		_px(cx - hw, cy + yy, hw * 2.0 + 1.0, 1, c)


## Pseudozufall aus einer Zahl (gleiche Zahl, gleicher Wert 0..1).
static func _h(n: float) -> float:
	return fposmod(sin(n * 12.9898 + 78.233) * 43758.5453, 1.0)


## Zeit in der Schleife (0..PERIOD): alles außer dem Hereinfallen des Banners hängt nur davon ab.
func _lt() -> float:
	return fposmod(t, PERIOD)


func _draw_stage() -> void:
	var w := float(_w)
	_draw_sky(w)
	_draw_clouds(w)
	_draw_buildings(w)
	_draw_ground(w)
	var lt := _lt()
	var ms := []
	for i in MARCHERS:
		ms.append(_marcher(i, w, lt))
	for row in [0, 1]:  # hintere Reihe zuerst
		for m in ms:
			if m.row == row:
				_draw_marcher(m, lt)
	for m in ms:
		if m.shout >= 0.0:
			_draw_bubble(m, w)
	_draw_banner(w)


func _draw_sky(w: float) -> void:
	var bands := ["#5d6478", "#666d80", "#707688", "#7a8090", "#858a98", "#9095a0", "#9ba0a8", "#a5aaae"]
	for i in bands.size():
		_px(0, i * 8.0, w, 8.0, Color(bands[i]))


## Dunkle Wolken, die sich langsam hin und her schieben (nahtlos in der Schleife).
func _draw_clouds(w: float) -> void:
	var lt := _lt()
	var n := 3 + int(w / 50.0)
	for i in n:
		var cx := floorf((float(i) + 0.3 + _h(i + 30.0) * 0.4) * w / n + sin(TAU * lt / PERIOD + i * 1.7) * 2.0)
		var cy := 8.0 + floorf(_h(i + 50.0) * 14.0)
		var s := 0.8 + _h(i + 70.0) * 0.5
		var dark := Color("#4a4f60")
		var mid := Color("#5a5f72")
		var hi := Color("#6e7488")
		_blob(cx, cy + 3, 13.0 * s, 4.0, dark)
		_blob(cx - 6.0 * s, cy + 1, 7.0 * s, 4.0, mid)
		_blob(cx + 5.0 * s, cy, 8.0 * s, 5.0, mid)
		_blob(cx - 1.0, cy - 3, 6.0 * s, 4.0, mid)
		_px(cx - 3.0 * s, cy - 6, 5.0 * s, 1, hi)
		_px(cx + 2.0 * s, cy - 4, 6.0 * s, 1, hi)
		_px(cx - 11.0 * s, cy + 6, 22.0 * s, 1, Color("#3e4252"))


## Verwaltung in der Mitte (mit rasender Uhr), Schmiede links und Sägegrube rechts aus buildings.png.
func _draw_buildings(w: float) -> void:
	_px(0, GROUND - 10.0, w, 10.0, Color("#5f8f46"))  # Wiese hinter den Häusern
	for i in int(w / 3.0):
		_px(floorf(_h(i + 140.0) * w), GROUND - 9.0 + floorf(_h(i + 160.0) * 8.0), 1, 1, Color("#4e7a3a"))
	var ox := floorf(w / 2.0) - 32.0
	var top := GROUND - 62.0
	for b in [["smithy", ox - 58.0, top + 2.0], ["sawpit", ox + 60.0, top + 2.0], ["office", ox, top]]:
		_stage.draw_texture_rect(Data.object_tex(b[0]), Rect2(Vector2(b[1], b[2]) * _k, Vector2(64, 64) * _k), false)
	# Uhr am Dach: das Zifferblatt neu malen, die Zeiger rasen (Überstunden!)
	var face := Color("#f6f0dc")
	for r in [[15, 30, 4], [16, 29, 6], [17, 29, 6], [18, 28, 8], [19, 29, 6], [20, 29, 6], [21, 30, 4]]:
		_px(ox + r[1], top + r[0], r[2], 1, face)
	var lt := _lt()
	for hand in [[3, 2.0, Color("#28201e")], [2, 0.5, Color("#c8302a")]]:
		var a := TAU * lt / PERIOD * float(hand[1]) - PI / 2.0
		for d in range(1, int(hand[0]) + 1):
			_px(ox + 32.0 + roundf(cos(a) * d), top + 18.0 + roundf(sin(a) * d), 1, 1, hand[2])
	_px(ox + 32, top + 18, 1, 1, Color("#28201e"))


## Gepflasterter Platz vor den Häusern.
func _draw_ground(w: float) -> void:
	_px(0, GROUND, w, H - GROUND, Color("#a0937e"))
	_px(0, GROUND, w, 1, Color("#7c705e"))
	_px(0, GROUND + 1, w, 1, Color("#b8ac94"))
	var y := GROUND + 4.0
	var r := 0
	while y < H:
		_px(0, y, w, 1, Color("#8e826e"))
		var x := -3.0 * (r % 2)
		while x < w:
			_px(x, y - 3.0, 1, 3, Color("#8e826e"))
			_px(x + 1.0, y - 3.0, 4, 1, Color("#aea18a"))
			x += 6.0
		y += 4.0
		r += 1
	for i in 6:  # ein paar Grasbüschel in den Fugen
		var gx := floorf(_h(i + 900.0) * w)
		var gy := GROUND + 6.0 + floorf(_h(i + 910.0) * (H - GROUND - 8.0))
		_px(gx, gy, 1, 1, Color("#6a9a4a"))
		_px(gx + 1, gy - 1, 1, 2, Color("#6a9a4a"))


## Lage eines Marschierers zur Schleifenzeit lt: Reihe 0 geht erst nach rechts, Reihe 1 erst nach links,
## an den Enden bleiben sie kurz stehen (Blick nach vorn) und recken die Schilder.
func _marcher(i: int, w: float, lt: float) -> Dictionary:
	var row := i % 2
	var margin := 14.0
	var base := margin + (float(i) + 0.5) * (w - 2.0 * margin) / MARCHERS
	var amp := clampf((w - 2.0 * margin) / MARCHERS * 0.75, 8.0, 13.0)
	var s := fposmod(lt / PERIOD + 0.5 * row + 0.04 * (i / 2), 1.0)
	var walk := 0.42
	var x := 0.0
	var dir := 2
	var f := 1.0
	var vx := 0.0
	if s < walk:
		x = -amp + 2.0 * amp * s / walk
		vx = 1.0
	elif s < 0.5:
		x = amp
		dir = 0
	elif s < 0.5 + walk:
		x = amp - 2.0 * amp * (s - 0.5) / walk
		vx = -1.0
		f = -1.0
	else:
		x = -amp
		dir = 0
		f = -1.0
	if row == 1:
		x = -x  # vordere Reihe läuft gegengleich
		vx = -vx
		f = -f
	var shout_u := fposmod(lt / PERIOD * 2.0 + i * 0.29, 1.0)
	return {"i": i, "row": row, "x": floorf(base + x), "y": ROWS[row], "dir": dir, "f": f,
		"walking": vx != 0.0, "shout": shout_u / 0.3 if shout_u < 0.3 else -1.0}


func _draw_marcher(m: Dictionary, lt: float) -> void:
	var i: int = m.i
	var x: float = m.x
	var y: float = m.y
	var f: float = m.f
	var look: Dictionary = _looks[i]
	_px(x - 4, y, 8, 1, Color(0, 0, 0, 0.25))
	var style := int(look.get("style", 0))
	var step := int(lt * 8.0) + i  # 8 Schritte je Sekunde, 32 je Schleife: nahtlos
	var frame: int = m.dir * 4 + (step % 4 if m.walking else 0)
	var src := Rect2((frame % 4) * 48, (frame / 4) * 72, 48, 72)
	var dst := Rect2(Vector2(x - 8.0, y - 22.0) * _k, Vector2(16, 24) * _k)
	if m.dir == 2 and f < 0.0:
		dst.size.x = -dst.size.x  # gespiegelt: Godot zeichnet ab position mit |Breite|
	for o in [["pants", "pants"], ["shirt", "shirt"], ["skin", "skin"], ["hair_%d" % style, "hair"],
			["fixed_bun" if style == 2 else "fixed", ""]]:
		var col := Color(look.get(o[1], "#ffffff")) if o[1] != "" else Color.WHITE
		_stage.draw_texture_rect_region(Settler.sheet(o[0]), dst, src, col)
	var skin := Color(look.get("skin", "#f2c9a0"))
	var hx := x + 5.0 if f > 0.0 else x - 6.0  # Hand vorn (im Stehen die rechte/linke Seite)
	var hold: int = HOLDS[i]
	var shouting: bool = m.shout >= 0.0
	if hold == 2:
		# Faust recken: im Takt hoch und runter, beim Rufen schneller
		var pump := floorf(absf(sin(TAU * lt / PERIOD * (8.0 if shouting else 4.0) + i)) * 3.0)
		var fy := y - 26.0 + pump  # Oberkante der Faust
		var ax := hx - (1.0 if f < 0.0 else 0.0)  # Arm 2 Pixel breit, mit dunklem Rand wie die Sprites
		var fx := ax if f > 0.0 else ax - 1.0  # Faust 3 Pixel, nach außen
		_px(ax - 1.0, fy + 3.0, 4, y - 12.0 - (fy + 3.0), INK)
		_px(fx - 1.0, fy - 1.0, 5, 5, INK)
		_px(ax, fy + 7.0, 2, y - 13.0 - (fy + 7.0), Color(look.get("shirt", "#c84a3a")))  # Ärmel
		_px(ax, fy + 3.0, 2, 4, skin)  # Unterarm
		_px(fx, fy, 3, 3, skin)
		_px(fx, fy, 3, 1, skin.lightened(0.25))
		_px(fx + (2.0 if f > 0.0 else 0.0), fy + 1.0, 1, 1, skin.darkened(0.25))  # Daumen
		return
	# Schild am Stock: wippt beim Gehen, im Stehen wird es hochgereckt
	var bob := float(step % 2) if m.walking else floorf(absf(sin(TAU * lt / PERIOD * 4.0 + i)) * 3.0)
	var top := y - 39.0 - bob
	_px(hx, top + 10.0, 1, y - 9.0 - (top + 10.0), STICK)
	_px(hx + (1.0 if f > 0.0 else -1.0), top + 11.0, 1, y - 11.0 - (top + 11.0), Color("#4a2c18"))
	_px(hx - 1.0, y - 11.0, 3, 3, INK)  # Hand am Stock
	_px(hx, y - 10.0, 1, 1, skin)
	_draw_sign(hx - 6.0, top, hold)


## Pappschild 13x11 mit Holzrand: 0 durchgestrichene Uhr, 1 Ausrufezeichen.
func _draw_sign(x: float, y: float, kind: int) -> void:
	_px(x, y, 13, 11, Color("#5a3820"))
	_px(x + 1, y + 1, 11, 9, CARD)
	_px(x + 1, y + 9, 11, 1, Color("#d8c8a0"))
	var cx := x + 6.0
	var cy := y + 5.0
	if kind == 1:
		_px(cx - 1, cy - 3, 2, 4, RED)
		_px(cx - 1, cy + 2, 2, 2, RED)
		return
	# Uhr: Ring, weißes Blatt, Zeiger, roter Strich quer darüber
	for r in [[-3, -1, 3], [-2, -2, 5], [-1, -3, 7], [0, -3, 7], [1, -3, 7], [2, -2, 5], [3, -1, 3]]:
		_px(cx + r[1], cy + r[0], r[2], 1, INK)
	for r in [[-2, -1, 3], [-1, -2, 5], [0, -2, 5], [1, -2, 5], [2, -1, 3]]:
		_px(cx + r[1], cy + r[0], r[2], 1, Color.WHITE)
	_px(cx, cy - 2, 1, 3, INK)
	_px(cx + 1, cy, 1, 1, INK)
	for d in range(-4, 5):
		_px(cx + d, cy + d, 1, 1, RED)
		_px(cx + d + 1, cy + d, 1, 1, RED)


## Sprechblase mit "!!" vor dem Kopf; springt kurz auf (u 0..1 über die Rufzeit).
func _draw_bubble(m: Dictionary, w: float) -> void:
	var u: float = m.shout
	var f: float = m.f
	if m.x + 17.0 > w:
		f = -1.0  # am Rand: Blase auf die andere Seite
	elif m.x - 17.0 < 0.0:
		f = 1.0
	var bx: float = m.x + (7.0 if f > 0.0 else -18.0)
	var by: float = m.y - 29.0 - (1.0 if u < 0.12 else 0.0)
	if u < 0.06:  # klein beim Aufploppen
		_px(bx + 3, by + 2, 5, 4, INK)
		_px(bx + 4, by + 3, 3, 2, Color.WHITE)
		return
	_px(bx + 1, by, 9, 8, INK)
	_px(bx, by + 1, 11, 6, INK)
	_px(bx + 1, by + 1, 9, 6, Color.WHITE)
	var tx := bx + (1.0 if f > 0.0 else 8.0)
	_px(tx, by + 7, 2, 2, INK)
	_px(tx + (0.0 if f > 0.0 else 1.0), by + 7, 1, 1, Color.WHITE)
	for c in [bx + 3.0, bx + 6.0]:
		_px(c, by + 2, 2, 2, RED)
		_px(c, by + 4, 2, 1, RED)
		_px(c, by + 6, 2, 1, RED)


## Stoffbanner an zwei Seilen, Text "Protest!" liegt als Label darüber.
func _draw_banner(w: float) -> void:
	var by := floorf(_banner_y())
	var bw := minf(w - 26.0, 86.0)
	var bx := floorf((w - bw) / 2.0)
	var cloth := Color("#f2e6c8")
	var shade := Color("#d8c8a0")
	for rx in [bx + 3.0, bx + bw - 4.0]:
		_px(rx, 0, 1, by + 1.0, Color("#5a3820"))
	_px(bx, by, bw, 16, cloth)
	_px(bx, by, bw, 1, Color("#c8b48a"))
	_px(bx, by + 15, bw, 1, shade)
	_px(bx, by + 16, bw, 1, Color(0, 0, 0, 0.25))
	# Falten im Stoff, leicht wehend
	var lt := _lt()
	for j in int(bw / 12.0):
		var fx := bx + 6.0 + j * 12.0 + roundf(sin(TAU * lt / PERIOD + j) * 1.0)
		_px(fx, by + 1, 1, 14, Color(shade, 0.5))
	for rx in [bx + 2.0, bx + bw - 5.0]:  # Ösen
		_px(rx, by + 1, 3, 2, Color("#8a5a32"))


# ---------------------------------------------------------------- Selbsttest
## --protestvideo=1: Protest über Admin erzwingen (Video geht auf, mit Grund), es läuft nach 10 s
## Spielzeit und 10 s Echtzeit noch (schließt sich nicht selbst, nicht durch Tippen, nicht durch Leertaste),
## schließt über den Knopf "Schließen" und über Esc; ohne Testschalter kein Video.
static func _selftest(hud) -> void:
	var tree: SceneTree = hud.get_tree()
	await tree.create_timer(3.0).timeout
	var ok := true
	var job := "handwerker"
	var n0 := shown
	Admin.protest.erase(job)
	Admin.orders[job] = {"ot": true, "since": Game.time_days - Seasons.year_days() * Admin._c("overtime_years", 1.0) - 0.1, "sh": false}
	Admin._tick()
	var v := current
	var opened := v != null and is_instance_valid(v) and shown == n0 + 1
	print("PROTESTVIDEO: Protest erzwungen -> Protest=%s Video offen=%s Grund='%s'" % [
		Admin.protesting(job), opened, v.reason if opened else ""])
	ok = ok and opened and Admin.protesting(job) and v.reason.contains(Admin._name(job))
	if not opened:
		print("Protest-Video FEHLER")
		return
	await tree.process_frame
	await tree.process_frame
	var vs := v.get_viewport().get_visible_rect().size
	var r := v._panel.get_global_rect()
	var inside := Rect2(Vector2.ZERO, vs).encloses(r)
	print("PROTESTVIDEO: Buehne %dx%d Pixel x%d, Fenster %s im Bild %s, Knopf '%s'" % [v._w, H, v._k, r, inside, v._close_btn.text])
	ok = ok and inside and v._close_btn.is_visible_in_tree()
	# Tippen und Leertaste schließen nicht
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	v._gui_input(tap)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	v._gui_input(touch)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	v._input(space)
	await tree.process_frame
	var still := is_instance_valid(v) and not v.is_queued_for_deletion() and current == v
	print("PROTESTVIDEO: Tippen/Fingertipp/Leertaste schliessen nicht: %s" % still)
	ok = ok and still
	# 10 s Spielzeit, dann 10 s Echtzeit: läuft weiter
	var day0 := Game.time_days
	var f0 := v.frames
	await tree.create_timer(10.0).timeout
	await tree.create_timer(10.0, true, false, true).timeout
	still = is_instance_valid(v) and not v.is_queued_for_deletion() and current == v
	print("PROTESTVIDEO: nach 10 s Spielzeit und 10 s Echtzeit noch offen: %s (Video %.2f s = %.1f Schleifen, %d Bilder, Spiel lief weiter: Tag +%.3f)" % [
		still, v.t, v.t / PERIOD, v.frames - f0, Game.time_days - day0])
	ok = ok and still and v.t >= 10.0 and v.frames - f0 > 500 and Game.time_days > day0
	# Schließen-Knopf
	v._close_btn.pressed.emit()
	var gone := v.is_queued_for_deletion() and current == null
	print("PROTESTVIDEO: Knopf Schliessen schliesst nach %.2f s: %s" % [last[0], gone])
	ok = ok and gone
	await tree.process_frame
	# Esc
	v = play(hud, "-")
	for i in 20:
		await tree.process_frame
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	v._input(esc)
	gone = v.is_queued_for_deletion() and current == null
	print("PROTESTVIDEO: Esc schliesst: %s" % gone)
	ok = ok and gone
	await tree.process_frame
	# Sperre: im Selbsttest ohne Schalter kein Video
	_allow_test = false
	var n1 := shown
	Admin.protest_started.emit(job, "-")
	print("PROTESTVIDEO: ohne Testschalter kein Video: %s" % (shown == n1 and current == null))
	ok = ok and shown == n1 and current == null
	_allow_test = true
	Admin.protest.erase(job)
	Admin.orders.erase(job)
	print("Protest-Video OK" if ok else "Protest-Video FEHLER")
