class_name EventChip
extends Button
## Knopf oben rechts (hud.top_alerts) für angekündigte Ereignisse (Events.chip()): das Symbol der Art,
## auf breiten Bildschirmen dazu Name und Stunden ("Dürre in 30 Std."). Gelb = angekündigt, rot = läuft.
## Auf dem Handy nur das Symbol (die Oberleiste ist voll; TopAlerts legt den Knopf unter die
## Geschwindigkeit). Antippen zeigt alle Ereignisse mit Insel, Zeit und Gegenmittel (Events.describe_all).

const SOON := Color("#f3d27a")
const NOW := Color("#d0484a")

var hud
var _sb: StyleBoxFlat
var _sig := "?"
var _next_ms := 0


func _init(p_hud = null) -> void:
	hud = p_hud
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(34, 34)
	expand_icon = false
	visible = false
	_sb = StyleBoxFlat.new()
	_sb.set_corner_radius_all(5)
	_sb.set_border_width_all(2)
	_sb.content_margin_left = 6
	_sb.content_margin_right = 6
	_sb.content_margin_top = 4
	_sb.content_margin_bottom = 4
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		add_theme_stylebox_override(st, _sb)
	add_theme_font_size_override("font_size", 14)
	pressed.connect(func():
		Sound.play("klick")
		var t := tap_text()
		if t != "" and hud != null:
			hud.toast(t, Events.chip().get("icon", "ereignis")))


## Was das Antippen zeigt (alle Ereignisse).
func tap_text() -> String:
	return Events.describe_all()


func _process(_delta: float) -> void:
	# Echtzeit-Takt (auch bei Pause und im Zeitraffer der Tests)
	var now := Time.get_ticks_msec()
	if now < _next_ms:
		return
	_next_ms = now + 250
	refresh()


func refresh() -> void:
	var c: Dictionary = Events.chip() if Game.world != null else {}
	var vs := get_viewport().get_visible_rect().size
	var narrow := vs.y > vs.x or vs.x < 760.0
	var label := ""
	if not c.is_empty() and not narrow:
		if not c.struck:
			label = tr("%s in %d Std.") % [c.name, c.hours]
		elif c.type in ["duerre", "seuche"]:
			label = tr("%s noch %d Std.") % [c.name, c.hours]
		else:
			label = tr("%s!") % c.name
		if int(c.more) > 0:
			label += " +%d" % int(c.more)
	if not c.is_empty():
		tooltip_text = tap_text()
	var sig := "%s|%s|%s|%s" % [c.get("type", ""), c.get("struck", false), label, c.get("icon", "")]
	if sig == _sig:
		return
	_sig = sig
	var was := visible
	visible = not c.is_empty()
	if visible:
		icon = Data.icon(str(c.icon))
		text = label
		var col: Color = NOW if c.struck else SOON
		_sb.bg_color = col
		_sb.border_color = col.darkened(0.45)
		var fc: Color = UiTheme.TEXT_LIGHT if c.struck else UiTheme.TEXT
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			add_theme_color_override(k, fc)
	else:
		tooltip_text = ""
	if hud != null and (visible or was):
		hud._layout.call_deferred()
