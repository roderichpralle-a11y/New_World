extends Node2D
## Einstieg: baut Welt, Kamera und Oberflaeche auf und verbindet sie.

var world: World
var camera: GameCamera
var hud: Hud
## Testhilfen (scripts/test/harness.gd): nur bei einem Start mit Argumenten, fehlt im Web-Export
const HARNESS := "res://scripts/test/harness.gd"
var test = null


func _ready() -> void:
	# Testversion (josh 2026-11-05, Abstürze auf dem iPhone): Handy und Tablet im Browser höchstens 30 Bilder pro
	# Sekunde; dazu zeichnet die Seite dort mit doppelter statt dreifacher Auflösung (export_presets head_include).
	if OS.has_feature("web") and DisplayServer.is_touchscreen_available():
		Engine.max_fps = 30
	get_window().size_changed.connect(_update_ui_scale)
	Game.ui_size_changed.connect(_update_ui_scale)
	_update_ui_scale()
	camera = GameCamera.new()
	add_child(camera)
	camera.make_current()
	Sea.world_root = self
	Sea.island_switched.connect(_on_island_switched)
	if not OS.get_cmdline_user_args().is_empty() and ResourceLoader.exists(HARNESS):
		test = load(HARNESS).new()
		test.main = self
		add_child(test)
		test._copy_fixture()
	var save := Game.load_save()
	if not save.is_empty():
		Game.apply_save_header(save)
		Sea.build_from_save(save)
		Game.after_load(save)  # Systeme lesen ihre Schluessel, alte Spielstaende bekommen die neuen Regeln
		world = Game.world
	if world == null:
		_new_world()
	hud = Hud.new()
	add_child(hud)
	hud.setup(world, camera)
	hud.new_game_requested.connect(_on_new_game)
	hud.continue_requested.connect(_on_continue)
	camera.tapped.connect(_on_tap)
	camera.hovered.connect(_on_hover)
	camera.right_tapped.connect(func():
		if world.is_placing():
			world.cancel_placement())
	_focus_start()
	Game.set_speed(0)
	if Game.probelauf and test != null:
		test._start_probe(save.is_empty())
	elif Game.autostart == "continue" and not save.is_empty():
		_on_continue()
	elif Game.autostart != "":
		_on_new_game()
	else:
		hud.show_title(not save.is_empty())
	if test != null:
		test._maybe_autotest()


## Testaufrufe: alles nach "--" als {name: wert}; "--x" ohne Wert heisst "1".
static func _user_args() -> Dictionary:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return args


## Kleine Bildschirme (Handy) bekommen eine groessere Oberflaeche:
## die kurze Bildschirmseite entspricht 400 bis 540 virtuellen Pixeln, geteilt durch die Anzeigegröße
## aus dem Menü (Game.ui_size: 75 % zeigt mehr, 125 % alles größer), höchstens so viele wie echte Pixel.
const UI_MIN_LONG := 860.0


func _update_ui_scale() -> void:
	var win := get_window()
	var px := Vector2(win.size)
	if px.x < 2 or px.y < 2:
		return
	var dpr := DisplayServer.screen_get_scale()
	if dpr <= 0.0:
		dpr = 1.0
	var css := px / dpr
	var short_css: float = min(css.x, css.y)
	var virt_short: float = minf(clamp(short_css, 400.0, 540.0) / Game.ui_size, minf(px.x, px.y))
	# Fenster und Leisten brauchen mindestens UI_MIN_LONG virtuelle Pixel auf der langen Seite (125 % auf einem
	# Bildschirm im Format 16:10 wäre sonst zu schmal)
	virt_short = maxf(virt_short, UI_MIN_LONG * minf(px.x, px.y) / maxf(px.x, px.y))
	var s: float = min(px.x, px.y) / virt_short
	var target := Vector2i(roundi(px.x / s), roundi(px.y / s))
	if win.content_scale_size != target:
		win.content_scale_size = target


func _new_world() -> void:
	var seed_value := randi() % 1000000
	if _user_args().has("seed"):
		seed_value = int(_user_args().seed)  # Testhilfe --seed=N: immer dieselbe Insel
	Game.reset_state(seed_value)
	world = Sea.create_world_node(0)
	world.visible = true
	Game.world = world
	world.build_new(seed_value)
	camera.bounds = Rect2(Vector2(-10, -10) * 16, (world.world_size_px() / 16 + Vector2(20, 20)) * 16)


## Eine andere Insel wird angezeigt.
func _on_island_switched(w) -> void:
	if world and is_instance_valid(world) and world.is_placing():
		world.cancel_placement()
	if world and is_instance_valid(world) and world.placement_changed.is_connected(hud._on_placement):
		world.placement_changed.disconnect(hud._on_placement)
	world = w
	if hud:
		hud.world = w
		w.placement_changed.connect(hud._on_placement)
		hud.on_island_switched()
	_focus_start()


func _focus_start() -> void:
	camera.bounds = Rect2(Vector2(-10, -10) * 16, (world.world_size_px() / 16 + Vector2(20, 20)) * 16)
	var target := world.cell_to_pos(world.center)
	if not world.settlers.is_empty():
		target = world.settlers[0].position
	camera.focus(target)


func _on_new_game() -> void:
	Sound.in_title = false
	Game.delete_save()
	_new_world()
	hud.world = world
	world.placement_changed.connect(hud._on_placement)
	hud.on_island_switched()
	_focus_start()
	Game.set_speed(1)
	# Neues Spiel: Zielkarte mit Aufträgen und Meldungen zu Aufträgen an (josh 2026-10-22)
	hud.notify_on("goal_card")
	hud.notify_on("ziel")
	Game.save_game()
	Game.flush_notes()
	Game.notify(tr("Willkommen auf deiner Insel! Lena und Jonas brauchen ein Zuhause für Nachwuchs."), "sonne")


func _on_continue() -> void:
	Sound.in_title = false
	Game.set_speed(1)
	Game.notify(tr("Willkommen zurück! Tag %d.") % Game.day(), "sonne")
	# Kein Fenster "Neue Regeln" mehr (josh 2026-10-29): neue Regeln gelten still ab dem Laden
	Game.rules_seen()
	Game.flush_notes()


func _on_tap(p: Vector2, touch: bool = false) -> void:
	if hud.has_overlay():
		return
	if world.is_placing():
		world.move_placement(p)
		# Mit der Maus baut ein Klick sofort, am Handy erst der Knopf "Hier bauen"
		if not touch:
			world.confirm_placement()
		return
	# Finger sind dicker als Mauszeiger: groesserer Fangradius auf Touchgeraeten
	var radius := 12.0
	if DisplayServer.is_touchscreen_available():
		radius = max(12.0, 34.0 / camera.zoom.x)
	Game.select(world.pick_at(p, radius))


func _on_hover(p: Vector2) -> void:
	if world.is_placing():
		world.move_placement(p)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and event is InputEventKey and event.keycode == KEY_ESCAPE and world and world.is_placing():
		world.cancel_placement()
