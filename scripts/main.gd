extends Node2D
## Einstieg: baut Welt, Kamera und Oberflaeche auf und verbindet sie.

var world: World
var camera: GameCamera
var hud: Hud


func _ready() -> void:
	get_window().size_changed.connect(_update_ui_scale)
	_update_ui_scale()
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
	if args.has("prodtest"):
		_autotest_prod()
	if args.has("research"):
		world.settlers[0].set_job("forscher")
	if args.has("upgrade"):
		for b in world.buildings.duplicate():
			if b.type == "huette":
				print("Ausbau: ", world.upgrade_building(b) != null)
	var elapsed := 0.0
	var next_report := 0.0
	while elapsed < secs:
		await get_tree().create_timer(1.0, true, false, true).timeout
		elapsed += 1.0
		if args.has("research") and not Game.has_research_goal():
			for t in Data.sorted_tech_ids():
				if Game.tech_state(t) == "available" and Game.start_research(t) == "":
					print("Forschung gestartet: ", t)
					break
		if elapsed >= next_report:
			next_report += 20.0
			if args.has("prodtest") or args.has("research"):
				var st := []
				for id in Data.sorted_resource_ids():
					st.append("%s=%d" % [id, Game.amount(id)])
				print("   ", " ".join(st), " | Forschung ", Game.research.current, " ", int(Game.tech_progress(Game.research.current)), " erforscht ", Game.research.done.size())
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
		if args.has("panel"):
			match args.panel:
				"research":
					hud._fill_research_list()
					hud._toggle(hud._research_panel)
				"stock":
					hud._refresh_stock(true)
					hud._toggle(hud._stock_panel)
				"build":
					hud._build_cat = args.get("cat", "nahrung")
					hud._fill_build_list()
					hud._toggle(hud._build_panel)
		if args.has("selectb"):
			for b in world.buildings:
				if b.type == args.selectb:
					Game.select(b)
					camera.focus(b.position)
		if args.has("look"):
			Game.select(null)
			camera.focus(world.cell_to_pos(world.center))
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args.shot)
		print("Screenshot: ", args.shot)
	Game.save_game()
	get_tree().quit()


func _autotest_build() -> void:
	var c := world.center
	for off in [Vector2i(3, -4), Vector2i(-2, 4), Vector2i(4, 3)]:
		var done := false
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var cc: Vector2i = c + off + Vector2i(dx, dy)
				if not done and world.can_place("huette", cc):
					world.place_building("huette", cc, false)
					done = true
	for dy in range(-6, 7):
		var cc := c + Vector2i(-6, dy)
		if world.can_place("feld", cc):
			world.place_building("feld", cc, false)
			break
	world.settlers[1].set_job("baumeister")


func _roomy(type: String, cc: Vector2i) -> bool:
	var sz: Array = Data.buildings[type].size
	for y in range(-1, int(sz[1]) + 2):
		for x in range(-1, int(sz[0]) + 1):
			var p := cc + Vector2i(x, y)
			if world.building_at.has(p) or not world.is_walkable(p):
				return false
	return true


func _autotest_prod() -> void:
	for t in Data.techs:
		if not Data.techs[t].get("soon", false):
			Game.research.done.append(t)
	Game._recompute_effects()
	Game.research_changed.emit()
	var c := world.center
	var r := 4
	for type in Data.buildings:
		var def: Dictionary = Data.buildings[type]
		if not (def.has("production") or def.has("research")) or type == "lagerfeuer":
			continue
		var done := false
		for rad in range(r, 20):
			for dy in range(-rad, rad + 1):
				for dx in range(-rad, rad + 1):
					var cc := c + Vector2i(dx, dy)
					if not done and world.can_place(type, cc) and _roomy(type, cc):
						world.place_building(type, cc, true)
						done = true
		print("platziert ", type, " ", done)
	world.place_building("grosslager", c + Vector2i(-8, 6), true) if world.can_place("grosslager", c + Vector2i(-8, 6)) else null
	for id in Data.resources:
		Game.stock[id] = 40
	for i in 8:
		world.spawn_newcomer("f" if i % 2 else "m")
	var jobs := ["koch", "koch", "handwerker", "handwerker", "steinmetz", "forscher", "forscher", "holzfaeller", "bauer", "fischer"]
	for i in world.settlers.size():
		world.settlers[i].age = 20.0
		world.settlers[i].set_job(jobs[i % jobs.size()])
	Game.research.done.erase("eisenwerkzeuge")
	Game.start_research("eisenwerkzeuge")


## Kleine Bildschirme (Handy) bekommen eine groessere Oberflaeche:
## die kurze Bildschirmseite entspricht 400 bis 540 virtuellen Pixeln.
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
	var virt_short: float = clamp(short_css, 400.0, 540.0)
	var s: float = min(px.x, px.y) / virt_short
	var target := Vector2i(roundi(px.x / s), roundi(px.y / s))
	if win.content_scale_size != target:
		win.content_scale_size = target


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
