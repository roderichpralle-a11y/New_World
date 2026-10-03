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
	Sea.world_root = self
	Sea.island_switched.connect(_on_island_switched)
	var save := Game.load_save()
	if not save.is_empty():
		Game.apply_save_header(save)
		Sea.build_from_save(save)
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
	hud.show_title(not save.is_empty())
	_maybe_autotest()


# ---------------------------------------------------------------- Selbsttest
## Verschiebt Lagerfeuer und Huette ueber die Platzierung und prueft Raster und Bewohner.
## --movetest=<Sekunden>: Wartezeit vorher (z. B. bis zur Nacht, wenn Siedler in der Huette schlafen).
func _autotest_move(wait: float) -> void:
	await get_tree().create_timer(max(3.0, wait), true, false, true).timeout
	print("Vor dem Verschieben (", Game.clock_text(), "): ", world.settlers.map(func(s): return "%s schläft=%s sichtbar=%s %s" % [s.display_name, s.sleeping, s.visible, s.cell]))
	for b in world.buildings.duplicate():
		var old: Vector2i = b.cell
		var target = null
		for r in range(3, 14):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var c: Vector2i = old + Vector2i(dx, dy)
					if target == null and abs(dx) + abs(dy) >= r and world.can_place(b.type, c, b) and _roomy(b.type, c):
						target = c
		if target == null:
			print("Verschieben: kein Platz fuer ", b.type)
			continue
		world.start_move(b)
		print("Verschieben ", b.type, ": Geist ok am alten Platz = ", world.can_place(b.type, old, b))
		world.move_placement(world.cell_to_pos(target) + (Vector2(b.size) - Vector2.ONE) * 8.0)
		var ok: bool = world.confirm_placement()
		var grid_ok := true
		for cc in b.cells():
			if world.building_at.get(cc) != b or world.astar.is_point_solid(cc) != (not b.is_ground()):
				grid_ok = false
		var old_free := true
		var bc: Array = b.cells()
		for y in b.size.y:
			for x in b.size.x:
				var oc: Vector2i = old + Vector2i(x, y)
				if not bc.has(oc) and world.building_at.has(oc):
					old_free = false
		print("Verschieben ", b.type, " ", old, " -> ", b.cell, " ok=", ok, " raster=", grid_ok, " alt_frei=", old_free,
			" bewohner=", b.residents().size(), " platzierung_aus=", not world.is_placing(), " tuer=", b.entrance_cell())
	print("Nach dem Verschieben: ", world.settlers.map(func(s): return "%s schläft=%s %s" % [s.display_name, s.sleeping, s.cell]))
	Game.save_game()

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
	if args.has("season"):
		# Testhilfe: Start in einer Jahreszeit (0 Frühling .. 3 Winter)
		Seasons.jump_to_season(int(args.season))
	if args.has("build"):
		_autotest_build()
	if args.has("prodtest"):
		_autotest_prod()
	if args.has("research"):
		world.settlers[0].set_job("forscher")
	if args.has("crowd"):
		# Testhilfe: viele Siedler fuer die Siedlerliste
		var names := ["Anna", "Ben", "Clara", "Dirk", "Emma", "Finn", "Greta", "Hugo", "Ida", "Karl", "Mia", "Ole", "Paula", "Rudi", "Sina", "Tom"]
		for i in int(args.crowd):
			var c: Vector2i = world.settlers[0].cell
			var s = world.spawn_settler({"name": names[i % names.size()], "sex": "f" if i % 2 else "m",
				"age": 3.0 + (i * 7) % 40, "max_age": 50.0, "skills": {}, "x": c.x, "y": c.y})
			s.hunger = float((i * 37) % 100)
			if s.is_adult():
				s.set_job(["holzfaeller", "sammler", "frei", "steinmetz", "bauer"][i % 5] if Data.jobs.has("steinmetz") else "frei")
	if args.has("comfort"):
		# Testhilfe: so viele Forschungen als erledigt markieren (Lebensstil steigt)
		for t in Data.sorted_tech_ids().slice(0, int(args.comfort)):
			Game.research.done.append(t)
		Game._recompute_effects()
		print("Lebensstil: ", SettlerMind.comfort_stage()[0], " ", SettlerMind.comfort())
	if args.has("sick"):
		# Testhilfe: einige Siedler krank machen
		var ills := ["fieber", "erkaeltung", "ruhr"]
		for i in min(int(args.sick), world.settlers.size()):
			world.settlers[i].mind._fall_ill(ills[i % ills.size()])
	if args.has("chartest"):
		_autotest_chars()
	if args.has("seatest"):
		_autotest_sea()
	if args.has("schooltest"):
		_autotest_school()
	if args.has("movetest"):
		await _autotest_move(float(args.movetest))
	if args.has("upgrade"):
		for b in world.buildings.duplicate():
			if b.type == "huette":
				print("Ausbau: ", world.upgrade_building(b) != null)
	var elapsed := 0.0
	var next_report := 0.0
	while elapsed < secs:
		await get_tree().create_timer(1.0, true, false, true).timeout
		elapsed += 1.0
		if args.has("upgrade"):
			# Testhilfe: Schreibstube Stufe fuer Stufe ausbauen, Material nachfuellen
			for b in world.buildings.duplicate():
				if b.def.get("base", b.type) == "schreibstube" and b.complete and b.def.has("upgrade"):
					var nb = world.upgrade_building(b)
					print("Schreibstube ausgebaut: ", b.type, " -> ", nb.type if nb else "nein")
			for id in ["holz", "bretter", "stein", "ziegel", "eisen", "werkzeug"]:
				world.stock[id] = max(Game.amount(id), 40)
		if args.has("seatest"):
			_autotest_sea_tick(elapsed)
		if args.has("tuttest"):
			_autotest_tutorial()
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
			if Sea.islands.size() > 1:
				var isl := []
				for m in Sea.islands:
					var w = Sea.worlds.get(int(m.id))
					isl.append("%s[%s]:%s pop=%d tiere=%d holz=%d essen=%d" % [m.name, m.biome, m.state, w.settlers.size() if w else 0, w.animals.size() if w else 0,
						Game.amount("holz", w) if w else 0, Game.total_food(w) if w else 0])
				if args.has("wildlife"):
					_report_wildlife()
				print("   Inseln: ", ", ".join(isl), " | See: ", Sea.voyages.size(), " Boote: ", Game.amount("boot"), " Fleisch: ", Game.amount("fleisch"), " Felle: ", Game.amount("felle"))
			var jobs := world.settlers.map(func(s): return "%s:%s:%s:%d" % [s.display_name, s.job, s.activity, int(s.hunger)])
			print("   %s, Jahr %d: Holz %d, frierend %d Inseln" % [Seasons.short_text(), Seasons.year(), Game.amount("holz"), Seasons.cold.size()])
			print("t=%d Tag %d %s pop=%d/%d holz=%d stein=%d food=%d | %s" % [elapsed, Game.day(), Game.clock_text(),
				Game.population(), Game.housing_capacity(), Game.amount("holz"), Game.amount("stein"), Game.total_food(), jobs])
		if Game.is_over:
			break
	if args.has("storetest"):
		_autotest_store()
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
				"sea":
					hud._open_sea()
					if args.has("seaview"):
						var sp2 = hud._sea_panel
						var first: Dictionary = Sea.ships[0] if not Sea.ships.is_empty() else {}
						for sh in Sea.ships:
							if not sh.route.is_empty():
								first = sh
						match args.seaview:
							"ships":
								sp2._go("ships")
							"ship":
								sp2._open_ship(int(first.id))
							"stop":
								sp2._ship_id = int(first.id)
								sp2._stop_i = 0
								sp2._go("stop")
							"send":
								sp2._selected = int(Sea.islands[-1].id)
								sp2._go("send")
					if args.has("seazoom"):
						# Testhilfe: Mausrad ueber der Karte, dann ein Stueck ziehen
						var sp = hud._sea_panel
						await get_tree().process_frame
						for i in int(args.seazoom):
							var w := InputEventMouseButton.new()
							w.button_index = MOUSE_BUTTON_WHEEL_UP
							w.pressed = true
							w.position = sp._map.size * Vector2(0.3, 0.5)
							sp._on_map_input(w)
						var drag := InputEventMouseMotion.new()
						sp._pressed = true
						drag.position = Vector2(100, 100)
						drag.relative = Vector2(30, 0)
						sp._on_map_input(drag)
						sp._on_map_input(drag)
						sp._pressed = false
						print("Seekarte Zoom: ", sp._zoom, " Verschiebung: ", sp._pan)
				"settlers":
					hud._toggle(hud._settler_panel)
					hud._refresh_settler_list()
					if args.has("sfilter"):
						# Testhilfe: Filter und Sortierung der Siedlerliste
						hud._settler_head["hunger"].pressed.emit()
						hud._settler_head["hunger"].pressed.emit()
						hud._settler_f_hungry.button_pressed = true
						hud._settler_f_group.select(1)
						hud._settler_f_group.item_selected.emit(1)
						print("Siedlerliste: ", hud._settler_count.text)
				"build":
					hud._build_cat = args.get("cat", "nahrung")
					hud._fill_build_list()
					hud._toggle(hud._build_panel)
		if args.has("shipcam") and not world._ship_nodes.is_empty():
			var spn = world._ship_nodes.values()[0]
			print("Schiffe im Bild: ", world._ship_nodes.size(), " Hafen ", world.harbor_cell(), " Schiff ", world.pos_to_cell(spn.position))
			camera.focus(spn.position)
		if args.has("selectb"):
			for b in world.buildings:
				if b.type == args.selectb:
					Game.select(b)
					camera.focus(b.position)
		if args.has("moveb"):
			# Bildschirmfoto mitten im Verschieben: Geist zwei Felder rechts
			for b in world.buildings:
				if b.type == args.moveb:
					world.start_move(b)
					world.move_placement(b.position + Vector2(40, -8))
					camera.focus(b.position)
					break
		if args.has("island"):
			Sea.switch_to(int(args.island))
			await get_tree().process_frame
		if args.has("look"):
			Game.select(null)
			camera.focus(world.cell_to_pos(world.center))
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args.shot)
		print("Screenshot: ", args.shot)
	Game.save_game()
	get_tree().quit()


## Charakter-Test: taeglicher Bericht ueber Laune, Krankheit, Vitamine und Arbeitskraft.
func _autotest_chars() -> void:
	Game.day_started.connect(func(d):
		var all := []
		for w in Sea.all_worlds():
			all.append_array(w.settlers)
		var sick := all.filter(func(x): return x.mind.sick != "")
		var mood := 0.0
		var wp := 0.0
		var vit := 0.0
		for x in all:
			mood += x.mind.mood
			wp += x.mind.work_power()
			vit += x.mind.vit
		var n := maxf(1.0, all.size())
		print("   Tag %d: %d Siedler, %d krank, Laune %.0f, Vitamine %.0f, Arbeitskraft %.0f%%, Lebensstil %s, Tote %d" % [d, all.size(), sick.size(),
			mood / n, vit / n, wp / n * 100.0, SettlerMind.comfort_stage()[0], Game.stats.deaths])
		for x in all.slice(0, 4):
			print("      %s (%s): Laune %d %s, Erholung %d, Gründe %s" % [x.display_name, x.mind.character_text(), int(x.mind.mood),
				x.mind.mood_text(), int(x.mind.rest), x.mind.reasons.map(func(r): return "%s %+d" % [r[0], int(r[1])])]))


## Testhilfe: Tierbestand je Insel und Art (erwachsen/jung, satt, Futter am Bau).
func _report_wildlife() -> void:
	for m in Sea.islands:
		var w = Sea.worlds.get(int(m.id))
		if w == null or w.animals.is_empty():
			continue
		var out := []
		for t in Data.animals:
			var all: Array = w.animals.filter(func(a): return a.type == t)
			if all.is_empty():
				continue
			var food := 0.0
			for a in all:
				food += a.food
			out.append("%s %d+%d jung satt=%d%%" % [t, w.adult_count(t), all.size() - w.adult_count(t), int(food / all.size() * 100.0)])
		var dens := []
		for n in w.nodes:
			if n.def.has("spawns"):
				dens.append("%s:%d/%d" % [n.type, w.animals.filter(func(a): return a.home == n.cell).size(), w.den_capacity(n)])
		print("   Tiere %s: %s | Baue %s" % [m.name, ", ".join(out), " ".join(dens)])


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


## Seefahrt-Test: alles erforscht, Werft und Boote da, drei Inseln entdecken und besiedeln.
func _autotest_sea() -> void:
	var weak := OS.get_cmdline_user_args().has("--weak=1")
	for t in Data.techs:
		if weak and t in ["waffenkunde", "jagdkunst", "befestigung", "pelzkleidung", "goldenes_zeitalter"]:
			continue
		if not t in Game.research.done:
			Game.research.done.append(t)
	Game._recompute_effects()
	Game.research_changed.emit()
	Data.balance["base_storage"] = 4000  # Testlauf: genug Stauraum fuer die Testvorraete
	for id in Data.resources:
		if not Data.ships.has(id):
			world.stock[id] = 50
	world.stock["boot"] = 6
	for i in 14:
		world.spawn_newcomer("f" if i % 2 else "m")
	for s in world.settlers:
		s.age = max(s.age, 20.0)
	var c := world.center
	for type in (["werft", "grosslager"] if weak else ["werft", "wachturm", "grosslager", "leuchtturm"]):
		var done := false
		for rad in range(3, 30):
			for dy in range(-rad, rad + 1):
				for dx in range(-rad, rad + 1):
					var cc := c + Vector2i(dx, dy)
					if not done and world.can_place(type, cc) and _roomy(type, cc):
						world.place_building(type, cc, true)
						done = true
		print("platziert ", type, " ", done)
	Game.refresh_effects()
	Sea._ship_tick_all()
	for sh in Sea.ships:
		Sea.hire_sailor(sh)
	print("Schiffe: ", Sea.ships.map(func(sh): return "%s %s Besatzung %d" % [sh.type, sh.name, sh.crew.size()]))
	print("Erkunden: ", Sea.start_explore(world))


var _sea_step := 0
var _route_set := false


func _autotest_sea_tick(elapsed: float) -> void:
	for sh in Sea.ships:
		if sh.state == "dock" and Sea.crew_missing(sh) > 0 and Sea.worlds.get(int(sh.at)) and Sea.worlds[int(sh.at)].settlers.size() > 3:
			Sea.hire_sailor(sh)
	if Sea.can_explore() == "" and Sea.islands.size() < 4:
		print("Erkunden: ", Sea.start_explore(Game.world))
	# Handel: Hafen auf beiden Inseln, eine Kogge faehrt Holz hinueber
	if OS.get_cmdline_user_args().has("--tradetest") and not _route_set and Sea.settled_islands().size() >= 2:
		var col_w = Sea.worlds.get(int(Sea.settled_islands()[1].id))
		var home_w = Sea.worlds.get(0)
		print("Hafen Heimat: ", _place_on(home_w, "hafen"), " Holzkai: ", _place_on(home_w, "holzkai"), " Hafen Kolonie: ", _place_on(col_w, "hafen"))
		Game.refresh_effects()
		print("Liegeplaetze Heimat: ", Sea.berths(home_w), " frei fuer Kogge: ", Sea.free_berth(home_w, 2), " Stufe ", Sea.harbor_level(home_w))
		for i in 6:
			home_w.spawn_newcomer("m")
		home_w.stock["kogge"] = 1
		Sea._ship_tick_all()
		var kg: Dictionary = Sea.ships[-1]
		Sea.hire_sailor(kg)
		Sea.hire_sailor(kg)
		kg.route = [{"island": 0, "load": {"holz": 80, "bretter": 10}}, {"island": int(col_w.island_id), "load": {"fisch": 20}}]
		_route_set = true
		print("Kogge: ", Sea.ship_label(kg), " Besatzung ", kg.crew.size(), " Blocker '", Sea.ship_blocker(kg), "'")
		print("Galeone darf Kolonie anlaufen: ", Sea.can_visit("galeone", int(col_w.island_id)), ", Kogge: ", Sea.can_visit("kogge", int(col_w.island_id)))
	# Route: Holz und Beeren von der Heimat zur ersten Kolonie
	if not _route_set and Sea.settled_islands().size() >= 2:
		var col := int(Sea.settled_islands()[1].id)
		for sh in Sea.idle_ships(0):
			if Sea.can_visit(sh.type, col):
				sh.route = [{"island": 0, "load": {"holz": 20, "beeren": 10}}, {"island": col, "load": {}}]
				sh.leg = 0
				_route_set = true
				print("Route fuer ", Sea.ship_label(sh), " nach ", Sea.meta(col).name)
				break
	if int(elapsed) % 20 == 0:
		for sh in Sea.ships:
			print("   Schiff ", sh.name, " [", sh.type, "] ", Sea.ship_status(sh), " Ladung ", Sea.goods_text(sh.cargo), " Besatzung ", sh.crew.size())
	# Jede entdeckte Insel bekommt vier Siedler, davon zwei Jaeger
	for m in Sea.islands:
		if m.state == "discovered" and not Sea.voyages.any(func(v): return int(v.to) == int(m.id)):
			var home = Sea.worlds.get(0)
			if home == null:
				return
			var adults: Array = home.settlers.filter(func(s): return s.is_adult())
			if adults.size() < 6:
				return
			var group := adults.slice(0, 4)
			for i in 2:
				group[i].set_job("jaeger" if Data.job_unlocked("jaeger") else "baumeister")
			print("Sende nach ", m.name, ": ", Sea.send_settlers(home, int(m.id), group))


## Prueft Stauraum, Hoechstmengen und Wegwerfen.
func _autotest_store() -> void:
	var ok := func(cond: bool, what: String):
		print("   Lager ", "OK  " if cond else "FEHLER ", what)
	for id in Data.resources:
		world.stock[id] = 0
	world.store_limits = {}
	var vol := Game.storage_volume()
	print("   Lager Stauraum ", vol)
	ok.call(Game.space_for("holz") == vol / 2, "Holz frei: %d" % Game.space_for("holz"))
	ok.call(Game.space_for("bretter") == vol / 3, "Bretter frei: %d" % Game.space_for("bretter"))
	ok.call(Game.set_limit("holz", 40) == 40, "Holz auf 40")
	ok.call(Game.space_for("beeren") == vol - 80, "Beeren nach Reservierung: %d" % Game.space_for("beeren"))
	ok.call(Game.add_stock("holz", 100) == 40, "Holz nur bis 40 eingelagert")
	ok.call(Game.set_limit("stein", 100000) == (vol - 80) / 2, "Stein hoechstens Restraum: %d" % Game.limit_of("stein"))
	ok.call(Game.space_for("beeren") == 0, "Beeren ohne Platz")
	ok.call(Game.add_stock("beeren", 5) == 0, "Beeren abgewiesen")
	Game.set_limit("holz", 10)
	ok.call(Game.excess("holz") == 30, "Ueberschuss 30")
	ok.call(Game.discard_excess("holz") == 30 and Game.amount("holz") == 10, "weggeworfen, 10 bleiben")
	ok.call(Game.space_for("boot") > 1000, "Boote ohne Lagerraum")
	Game.set_limit("stein", -1)
	ok.call(Game.space_for("beeren") == vol - 20, "Stein frei, Beeren wieder Platz: %d" % Game.space_for("beeren"))
	world.store_limits = {}


## Spielt die Einfuehrung durch, wie es ein Spieler tun wuerde.
func _autotest_tutorial() -> void:
	var g: Dictionary = hud.goal_card.current()
	print("   Ziel: ", g.id, " ", hud.goal_card.progress(g), " tut=", Game.goals.tut, " ms=", Game.goals.ms)
	match g.id:
		"t_select":
			Game.select(world.settlers[0])
		"t_job":
			world.settlers[0].set_job("holzfaeller")
			Game.player_action.emit("job", "holzfaeller")
		"t_hut", "t_field":
			var type := "huette" if g.id == "t_hut" else "feld"
			for rad in range(3, 12):
				for dy in range(-rad, rad + 1):
					for dx in range(-rad, rad + 1):
						var cc := world.center + Vector2i(dx, dy)
						if not world.is_placing() and hud.goal_card.current().id == g.id and world.can_place(type, cc) and _roomy(type, cc):
							world.start_placement(type, world.cell_to_pos(cc))
							world.move_placement(world.cell_to_pos(cc))
							print("   platziert: ", world.confirm_placement())
							return
		"t_research":
			Game.start_research("steinwerkzeuge")
		"t_speed":
			Game.set_speed(3)
			Engine.time_scale = 10.0


## Testhilfe: Gebaeude fertig auf einer beliebigen Insel hinstellen.
func _place_on(w, type: String) -> bool:
	var sz: Array = Data.buildings[type].size
	for rad in range(3, 30):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var cc: Vector2i = w.center + Vector2i(dx, dy)
				if not w.can_place(type, cc):
					continue
				var ok := true
				for y in range(-1, int(sz[1]) + 2):
					for x in range(-1, int(sz[0]) + 1):
						var p: Vector2i = cc + Vector2i(x, y)
						if w.building_at.has(p) or not w.is_walkable(p):
							ok = false
				if ok:
					w.place_building(type, cc, true)
					return true
	return false


func _roomy(type: String, cc: Vector2i) -> bool:
	var sz: Array = Data.buildings[type].size
	for y in range(-1, int(sz[1]) + 2):
		for x in range(-1, int(sz[0]) + 1):
			var p := cc + Vector2i(x, y)
			if world.building_at.has(p) or not world.is_walkable(p):
				return false
	return true


## Steinhaus und Schule fertig hinstellen, viel Essen: Geburten und Schulkinder beobachten.
func _autotest_school() -> void:
	for t in Data.techs:
		Game.research.done.append(t)
	Game._recompute_effects()
	var c := world.center
	for type in ["steinhaus", "schule", "grosslager"]:
		var done := false
		for rad in range(4, 20):
			for dy in range(-rad, rad + 1):
				for dx in range(-rad, rad + 1):
					var cc := c + Vector2i(dx, dy)
					if not done and world.can_place(type, cc) and _roomy(type, cc):
						world.place_building(type, cc, true)
						done = true
		print("platziert ", type, " ", done)
	Data.balance["base_storage"] = 4000  # Testlauf: genug Stauraum fuer die Testvorraete
	for id in ["beeren", "fisch", "brot", "aepfel", "holz"]:
		world.stock[id] = 150
	world.assign_homes()
	for s in world.settlers:
		var h = world.building_by_id(s.home_id)
		print("   %s wohnt in %s" % [s.display_name, h.type if h else "-"])
	Game.day_started.connect(func(d):
		var kids := world.settlers.filter(func(s): return not s.is_adult())
		print("   Tag %d: Geburten %d, Kinder %s" % [d, Game.stats.births,
			kids.map(func(k): return "%s %.2f %s" % [k.display_name, k.age, "Schule" if world.school_of(k) else "-"])]))


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
	Data.balance["base_storage"] = 4000  # Testlauf: genug Stauraum fuer die Testvorraete
	for id in Data.resources:
		world.stock[id] = 40
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


func _new_world() -> void:
	var seed_value := randi() % 1000000
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
	Game.save_game()
	Game.notify("Willkommen auf deiner Insel! Lena und Jonas brauchen ein Zuhause für Nachwuchs.", "sonne")


func _on_continue() -> void:
	Sound.in_title = false
	Game.set_speed(1)
	Game.notify("Willkommen zurück! Tag %d." % Game.day(), "sonne")


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
