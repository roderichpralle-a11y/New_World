class_name ClimateBadge
extends PanelContainer
## Klima-Symbol in der Oberleiste neben der Jahreszeit (Seasons.badge()): Sonne auf Rot für einen
## heißen Sommer, Schneeflocke für den vorhergesagten oder laufenden Winter (grün mild, blau hart bzw.
## streng, dunkelblau Eiswinter). Nur ein Symbol, damit es auch auf dem Handy in die Leiste passt
## (dort ist es der einzige Hinweis). Antippen läuft zur Jahreszeit durch, die dann den Klimatext zeigt.

const COLORS := {"mild": Color("#4f9a5a"), "hart": Color("#3d6cc4"), "streng": Color("#3d6cc4"),
	"bitter": Color("#26287a"), "heiss": Color("#cf5326")}

var _icon: TextureRect
var _sb: StyleBoxFlat
var _sig := "?"
var _next_ms := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sb = StyleBoxFlat.new()
	_sb.set_corner_radius_all(4)
	_sb.set_border_width_all(1)
	_sb.content_margin_left = 2
	_sb.content_margin_right = 2
	_sb.content_margin_top = 2
	_sb.content_margin_bottom = 2
	add_theme_stylebox_override("panel", _sb)
	_icon = UiTheme.icon_rect(Data.icon("schnee"), 14)
	_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_icon)
	visible = false


func _process(_delta: float) -> void:
	# Echtzeit-Takt (auch bei Pause und im Zeitraffer der Tests)
	var now := Time.get_ticks_msec()
	if now < _next_ms:
		return
	_next_ms = now + 250
	refresh()


func refresh() -> void:
	var b: Dictionary = Seasons.badge() if Game.world != null else {}
	if not b.is_empty():
		tooltip_text = Seasons.season_title() + "." + Seasons.climate_text()
	var sig := "%s|%s" % [b.get("kind", ""), b.get("type", "")]
	if sig == _sig:
		return
	_sig = sig
	visible = not b.is_empty()
	if b.is_empty():
		tooltip_text = ""
		return
	var col: Color = COLORS.get(str(b.type), Color("#3d6cc4"))
	_sb.bg_color = col
	_sb.border_color = col.darkened(0.45)
	_icon.texture = Data.icon("sonne" if b.kind == "s" else "schnee")
