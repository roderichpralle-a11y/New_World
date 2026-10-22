class_name HomeArtTest
extends RefCounted
## Exercises the actual home renderers; screenshot fixture is opt-in test code.

static func run(main) -> void:
	FineTest.check(HomeArt.active(main.world), "Heimatinsel verwendet neue Grafiken")
	FineTest.check(not HomeArt.active({"biome": "tropen"}), "andere Inselvarianten bleiben getrennt")
	FineTest.check(main.world._mat_ground.get_shader_parameter("meadow") == HomeArt.MEADOW, "zusammenhängende Wiese ist eingebunden")
	for b in main.world.buildings:
		if b.type == "huette":
			FineTest.check(b._sprite.texture.atlas == HomeArt.OBJECTS.hut and b._sprite.scale == HomeArt.SCALE, "Hütte zeigt native Grafik statt altem Miniaturbild")
	for n in main.world.nodes:
		if n.type in ["baum", "busch"]:
			FineTest.check(n._sprite.texture.atlas == HomeArt.OBJECTS[n.sprite_name()], "neue Naturgrafik am Bodenanker " + n.type)
	for s in main.world.settlers.slice(0, 2):
		var old := {"working": s._working, "tool": s._cur_tool, "time": s._work_t, "dir": s._dir}
		FineTest.check(s._home_sprite != null, "vollständige neue Figur " + s.display_name)
		for direction in 3:
			for phase in 4:
				s._working = true
				s._cur_tool = "axe" if s.look.home_portrait == "jonas" else "basket"
				s._work_t = (phase + 0.01) / 3.2
				s._dir = direction
				s._animate_home()
				FineTest.check(s._home_sprite.frame == (3 + direction) * 4 + phase and not s._tool.visible, "registrierte Arbeitsphase %s/%d/%d" % [s.display_name, direction, phase])
				FineTest.check(s._layers.values().all(func(layer): return not layer.visible), "keine alten Figurenlagen " + s.display_name)
				if s._cur_tool == "axe":
					FineTest.check(s._work_prop.texture.region.position.x == phase * 160, "Holz und Axt in derselben Phase")
		s._working = old.working
		s._cur_tool = old.tool
		s._work_t = old.time
		s._dir = old.dir
		s._animate(0.0)


static func scene(main, phase: int) -> void:
	# A repeatable view of real Building/ResNode/Settler objects, for checking all
	# four working poses at the same camera scale. Not used by normal gameplay.
	var w: World = main.world
	var c: Vector2i = w.center
	for n in w.nodes.duplicate():
		if abs(n.cell.x - c.x) < 11 and abs(n.cell.y - c.y) < 9:
			w.remove_node(n)
	var tree = w.spawn_node("baum", c + Vector2i(5, -2), 0)
	w.spawn_node("baum", c + Vector2i(-7, 3), 1)
	w.spawn_node("baum", c + Vector2i(8, 4), 2)
	var bush = w.spawn_node("busch", c + Vector2i(-1, 4), 0)
	for s in w.settlers:
		s.abort_plan()
		s.set_process(false)
		s._moving = false
		s._working = true
		s._dir = Settler.DIR_SIDE
		s._flip = false
		s._work_t = (phase + 0.01) / 3.2
		if s.look.get("home_portrait", "") == "lena":
			s.position = bush.position + Vector2(-23, 6)
			s._cur_tool = "basket"
		else:
			s.position = tree.position + Vector2(-25, 7)
			s._cur_tool = "axe"
		s._animate(0.0)
	main.hud.root.hide()
	var zoom := clampf(main.get_viewport_rect().size.x / 330.0, 1.0, 2.0)
	main.camera.zoom = Vector2(zoom, zoom)
	main.camera.focus(w.cell_to_pos(c) + Vector2(0, -2))
