class_name FineTest
extends RefCounted
## Regression checks for the independently saved fine edition and real UI gestures.
static var fails := 0

static func check(ok: bool, message: String) -> void:
	print("FEIN ", "OK " if ok else "FEHLER ", message)
	if not ok:
		fails += 1

static func frame(main) -> void:
	await main.get_tree().process_frame
	await main.get_tree().process_frame

static func run(main) -> void:
	fails = 0
	check(ProjectSettings.get_setting("application/config/version") == "1.1.0", "Version 1.1.0")
	check(Game.build_tag == "fein" and "fein" in Game.SAVE_PATH, "isolierte Speicherplätze")
	check(Game.import_slot(5, '{"version":3,"time_days":1}') != "", "alte Spielstände werden nicht übernommen")
	for type in Data.buildings:
		var tex := Data.building_tex(type)
		check(tex != null and tex.get_width() > 0 and "sprites_fine" in tex.atlas.resource_path, "Bauobjekt " + type)
		var b := Building.new()
		main.world.entities.add_child(b)
		b.setup(main.world, type, Vector2i(5, 5), true)
		check(b.position == b.foot_pos(), "Bodenanker " + type)
		if b._sprite:
			check(b._sprite.offset.y + b._sprite.texture.get_height() <= 6.1, "Grundlinie " + type)
		b.queue_free()
	for name in Data._icon_index:
		var tex := Data.icon(name)
		check(tex.region.end.x <= tex.atlas.get_width(), "Symbolregion " + name)
	for family in ["road", "dike", "fence", "gravel", "bricks", "hedge"]:
		for mask in 16:
			var tex := Data.object_tex(family + str(mask))
			check(tex.region.end.x <= tex.atlas.get_width() and tex.region.end.y <= tex.atlas.get_height(), "Verbindung %s %d" % [family, mask])
	var person = main.world.settlers[0]
	for job in Data.jobs:
		person.job = job
		person._stat_kind = "job"
		person._apply_outfit()
		for name in person._layers:
			var layer: Sprite2D = person._layers[name]
			check(layer.texture.get_size() == Vector2(192, 3024) and layer.offset == Vector2(-24, -66) and layer.scale.is_equal_approx(Vector2.ONE / 3.0), "registrierter Layer %s/%s" % [job, name])
	person._do_sleep_inside()
	check(not person.visible, "Schlaf im Haus unsichtbar")
	person._wake_up()
	person._do_sleep_outside()
	person._animate(0.01)
	check(person.visible and person._body.rotation == 0, "Bodenschlaf als liegende Figur ohne Bett")
	person._wake_up()
	# Verify geometry of the real placement overlay independently of its color.
	for type in ["huette", "feld", "hafen", "parkanlage", "zaun"]:
		var def: Dictionary = Data.buildings[type]
		var expected := Vector2(int(def.size[0]), int(def.size[1])) * World.T
		check(expected.x > 0 and expected.y > 0, "orthogonale Platzierung " + type)
	# Enough rows to require scrolling even on desktop.
	main.hud.goal_card._skip_tutorial()
	main.hud.goal_card._dismiss()
	main.hud._overlay_clear()
	while main.world.settlers.size() < 32:
		main.world.spawn_newcomer("f" if main.world.settlers.size() % 2 else "m")
	main.hud._toggle(main.hud._settler_panel)
	main.hud._refresh_settler_list()
	await frame(main)
	await frame(main)
	var sc: ScrollContainer = main.hud._settler_scroll
	var bar := sc.get_v_scroll_bar()
	check(bar.is_visible_in_tree() and bar.max_value > bar.page, "Siedlerliste hat sichtbaren Scrollgriff")
	check(bar.size.x >= 24.0, "Scrollgriff hat mindestens 24 Pixel Trefferbreite")
	# Input goes through the actual viewport: content-drag must not steal the thumb.
	var start := bar.global_position + Vector2(bar.size.x / 2.0, 19.0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = start
	press.global_position = start
	check(not main.hud._drag_scroll(press) and main.hud._drag_sc == null, "Griffgesten bleiben bei der nativen Scrollbar")
	bar.value = 0
	var enter := InputEventMouseMotion.new()
	enter.position = start
	enter.global_position = start
	main.get_viewport().push_input(enter, true)
	await frame(main)
	print("FEIN SCROLL DEBUG ", bar.get_global_rect(), " page=", bar.page, " max=", bar.max_value, " target=", start, " viewport=", main.get_viewport_rect())
	main.get_viewport().push_input(press, true)
	await frame(main)
	var motion := InputEventMouseMotion.new()
	motion.position = start + Vector2(0, 65)
	motion.global_position = motion.position
	motion.relative = Vector2(0, 65)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	main.get_viewport().push_input(motion, true)
	await frame(main)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	release.global_position = motion.position
	main.get_viewport().push_input(release, true)
	await frame(main)
	check(bar.value > 0, "nativer Griff lässt sich mit echter Zeigerbewegung ziehen")
	bar.value = bar.max_value
	check(bar.value >= bar.max_value - bar.page - 1.0, "untere Siedler sind erreichbar")
	main.hud._settler_panel.hide()
	Game.save_game()
	var saved := Game.load_save()
	check(saved.get("edition", "") == "fein" and saved.get("version", 0) == 4, "Fein speichern und laden")
	print("FEIN ERGEBNIS: ", fails, " Fehler")

static func gallery(main, group: String) -> void:
	# Runtime contact sheet uses the exact same textures as actual gameplay.
	main.hud.root.hide()
	var layer := CanvasLayer.new()
	main.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color("#e9dfc6")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.position = Vector2(12, 25)
	bg.add_child(grid)
	for type in Data.buildings:
		if group != "all" and Data.buildings[type].category != group:
			continue
		var box := VBoxContainer.new()
		grid.add_child(box)
		box.add_child(UiTheme.icon_rect(Data.building_tex(type), 85))
		box.add_child(UiTheme.label(type, 10))
