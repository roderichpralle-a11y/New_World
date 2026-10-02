class_name UiTheme
extends RefCounted
## Baut das Pixel-Theme (Holzrahmen, Pixelschrift) im Code.

const TEXT := Color("#3b2a2c")
const TEXT_LIGHT := Color("#fff6e0")
const ACCENT := Color("#d8902f")
const GOOD := Color("#5aa852")
const BAD := Color("#d0484a")


static func _box(region: Rect2, margin: int = 6, content: int = 8) -> StyleBoxTexture:
	var at := AtlasTexture.new()
	at.atlas = Data.tex_ui
	at.region = region
	var sb := StyleBoxTexture.new()
	sb.texture = at
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = content
	sb.content_margin_right = content
	sb.content_margin_top = content - 2
	sb.content_margin_bottom = content - 2
	return sb


static func make() -> Theme:
	var t := Theme.new()
	t.default_font = Data.font_regular
	t.default_font_size = 16
	var panel := _box(Rect2(0, 0, 24, 24), 6, 10)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var bn := _box(Rect2(24, 0, 24, 24), 6, 8)
	var bh := _box(Rect2(48, 0, 24, 24), 6, 8)
	var bp := _box(Rect2(72, 0, 24, 24), 6, 8)
	var bd := _box(Rect2(24, 0, 24, 24), 6, 8)
	bd.modulate_color = Color(1, 1, 1, 0.5)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, bn)
		t.set_stylebox("hover", cls, bh)
		t.set_stylebox("pressed", cls, bp)
		t.set_stylebox("hover_pressed", cls, bp)
		t.set_stylebox("disabled", cls, bd)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, TEXT)
		t.set_color("font_pressed_color", cls, TEXT_LIGHT)
		t.set_color("font_hover_pressed_color", cls, TEXT_LIGHT)
		t.set_color("font_disabled_color", cls, Color(TEXT, 0.5))
		t.set_color("icon_normal_color", cls, Color.WHITE)
		t.set_constant("h_separation", cls, 6)
	# Aufklappliste (Beruf in der Siedlerliste) im selben Holzrahmen
	t.set_stylebox("panel", "PopupMenu", _box(Rect2(0, 0, 24, 24), 6, 8))
	t.set_stylebox("hover", "PopupMenu", bh)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", TEXT)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "RichTextLabel", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", Data.font_regular)
	t.set_font("bold_font", "RichTextLabel", Data.font_bold)
	t.set_font_size("normal_font_size", "RichTextLabel", 15)
	t.set_font_size("bold_font_size", "RichTextLabel", 15)
	# Fortschrittsbalken
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#5a4038")
	bg.border_color = Color("#2a1c20")
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOOD
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_constant("separation", "VBoxContainer", 4)
	t.set_constant("separation", "HBoxContainer", 6)
	# Scrollleiste
	var sbg := StyleBoxFlat.new()
	sbg.bg_color = Color(0.35, 0.25, 0.2, 0.3)
	sbg.content_margin_left = 5
	sbg.content_margin_right = 5
	var sg := StyleBoxFlat.new()
	sg.bg_color = Color("#a8743e")
	sg.set_corner_radius_all(2)
	sg.content_margin_left = 5
	sg.content_margin_right = 5
	t.set_stylebox("scroll", "VScrollBar", sbg)
	t.set_stylebox("grabber", "VScrollBar", sg)
	t.set_stylebox("grabber_highlight", "VScrollBar", sg)
	t.set_stylebox("grabber_pressed", "VScrollBar", sg)
	# Tooltip
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color("#fff6e0")
	tip.border_color = Color("#3b2a2c")
	tip.set_border_width_all(2)
	tip.set_content_margin_all(6)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t


static func bar(color: Color, height: float = 8.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(60, height)
	b.max_value = 100
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func icon_rect(tex: Texture2D, px: float = 16.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func label(text: String, size: int = 16, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", Data.font_bold)
	return l


static func button(text: String, icon_name: String = "", min_h: float = 40.0) -> Button:
	var b := Button.new()
	b.text = text
	if icon_name != "":
		b.icon = Data.icon(icon_name)
		b.expand_icon = false
	b.custom_minimum_size = Vector2(min_h, min_h)
	b.focus_mode = Control.FOCUS_NONE
	return b
