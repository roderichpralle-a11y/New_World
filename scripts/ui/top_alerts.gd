class_name TopAlerts
extends HBoxContainer
## Kleine Hinweis-Knöpfe oben rechts (Händler, später auch Ereignisse). Systeme hängen ihren Knopf
## mit hud.top_alerts.add_child(...) an und rufen hud._layout(), wenn er erscheint oder verschwindet.
## Die Oberleiste selbst ist auf dem Handy schon voll.
##
## Platz (hud._layout -> place): auf schmalen Bildschirmen rechtsbündig unter der Geschwindigkeit
## (links daneben liegt die Zielkarte, die nicht schmaler werden kann), auf breiten links neben der
## Geschwindigkeit, wenn die Oberleiste dort Platz lässt, sonst auch unter der Geschwindigkeit.


func _init() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func shown() -> bool:
	return get_children().any(func(c): return c is Control and c.visible)


## Größe der sichtbaren Knöpfe. Selbst gerechnet: solange der Behälter versteckt ist, liefert
## get_combined_minimum_size() noch 0.
func content_size() -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for c in get_children():
		if c is Control and c.visible:
			var m: Vector2 = c.get_combined_minimum_size()
			s = Vector2(s.x + m.x, maxf(s.y, m.y))
			n += 1
	s.x += get_theme_constant("separation") * maxi(n - 1, 0)
	return s


func place(sp: Control, topbar: Control, narrow: bool) -> void:
	visible = shown()
	if not visible:
		return
	var sz := content_size()
	size = sz
	var x := sp.position.x - sz.x - 6.0
	if not narrow and (topbar == null or topbar.position.x + topbar.size.x + 6.0 <= x):
		position = Vector2(x, sp.position.y + (sp.size.y - sz.y) / 2.0)
	else:
		position = Vector2(sp.position.x + sp.size.x - sz.x, sp.position.y + sp.size.y + 4.0)
