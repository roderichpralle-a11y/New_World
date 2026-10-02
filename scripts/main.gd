extends Node2D
## Einstieg: baut Welt, Kamera und Oberflaeche auf und verbindet sie.

var world: World
var camera: GameCamera
var hud: Hud


func _ready() -> void:
	camera = GameCamera.new()
	add_child(camera)
	camera.make_current()
	var save := Game.load_save()
	if not save.is_empty():
		_create_world()
		Game.apply_save_header(save)
		world.build_from_save(save)
	else:
		_new_world()
	hud = Hud.new()
	add_child(hud)
	hud.setup(world, camera)
	hud.new_game_requested.connect(_on_new_game)
	hud.continue_requested.connect(_on_continue)
	camera.tapped.connect(_on_tap)
	camera.hovered.connect(_on_hover)
	_focus_start()
	Game.set_speed(0)
	hud.show_title(not save.is_empty())
	_maybe_autotest()


# ---------------------------------------------------------------- Selbsttest
## Aufruf: godot -- --autotest=600 --scale=8 --shot=/pfad/bild.png
## Startet ein neues Spiel, simuliert und schreibt Zustandsberichte.
func _maybe_autotest() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if not args.has("autotest"):
		return
	hud._overlay_clear()
	if not args.has("keep"):
		_on_new_game()
	var secs := float(args.autotest)
	var scale := float(args.get("scale", "8"))
	Game.set_speed(1)
	Engine.time_scale = scale
	Game.notified.connect(func(t, _i): print("[Tag %d %s] %s" % [Game.day(), Game.clock_text(), t]))
	if args.has("build"):
		_autotest_build()
	var elapsed := 0.0
	var next_report := 0.0
	while elapsed < secs:
		await get_tree().create_timer(1.0, true, false, true).timeout
		elapsed += 1.0
		if elapsed >= next_report:
			next_report += 20.0
			var jobs := world.settlers.map(func(s): return "%s:%s:%s:%d" % [s.display_name, s.job, s.activity, int(s.hunger)])
			print("t=%d Tag %d %s pop=%d/%d holz=%d stein=%d food=%d | %s" % [elapsed, Game.day(), Game.clock_text(),
				Game.population(), Game.housing_capacity(), Game.amount("holz"), Game.amount("stein"), Game.total_food(), jobs])
		if Game.is_over:
			break
	if args.has("shot"):
		Engine.time_scale = 1.0
		if args.has("night"):
			pass
		if args.has("select"):
			Game.select(world.settlers[0])
			camera.focus(world.settlers[0].position)
		if args.has("buildmenu"):
			hud._toggle(hud._build_panel)
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args.shot)
		print("Screenshot: ", args.shot)
	get_tree().quit()


func _autotest_build() -> void:
	var c := world.center
	for off in [Vector2i(3, -4), Vector2i(-2, 4), Vector2i(4, 3)]:
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var cc: Vector2i = c + off + Vector2i(dx, dy)
				if world.can_place("huette", cc):
					world.place_building("huette", cc, false)
					break
			if false:
				break
	for dy in range(-6, 7):
		var cc := c + Vector2i(-6, dy)
		if world.can_place("feld", cc):
			world.place_building("feld", cc, false)
			break


func _create_world() -> void:
	if world:
		world.queue_free()
		remove_child(world)
	world = World.new()
	world.name = "World"
	add_child(world)
	move_child(world, 0)
	Game.world = world


func _new_world() -> void:
	var seed_value := randi() % 1000000
	_create_world()
	Game.reset_state(seed_value)
	world.build_new(seed_value)
	camera.bounds = Rect2(Vector2(-10, -10) * 16, (world.world_size_px() / 16 + Vector2(20, 20)) * 16)


func _focus_start() -> void:
	camera.bounds = Rect2(Vector2(-10, -10) * 16, (world.world_size_px() / 16 + Vector2(20, 20)) * 16)
	var target := world.cell_to_pos(world.center)
	if not world.settlers.is_empty():
		target = world.settlers[0].position
	camera.focus(target)


func _on_new_game() -> void:
	Game.delete_save()
	_new_world()
	hud.world = world
	world.placement_changed.connect(hud._on_placement)
	_focus_start()
	Game.set_speed(1)
	Game.save_game()
	Game.notify("Willkommen auf deiner Insel! Lena und Jonas brauchen ein Zuhause für Nachwuchs.", "sonne")
	Game.notify("Tippe auf einen Siedler, um seinen Beruf zu wählen. Über Bauen entstehen neue Hütten.", "hammer")


func _on_continue() -> void:
	Game.set_speed(1)
	Game.notify("Willkommen zurück! Tag %d." % Game.day(), "sonne")


func _on_tap(p: Vector2) -> void:
	if hud.has_overlay():
		return
	if world.is_placing():
		world.move_placement(p)
		return
	Game.select(world.pick_at(p))


func _on_hover(p: Vector2) -> void:
	if world.is_placing() and not DisplayServer.is_touchscreen_available():
		world.move_placement(p)
