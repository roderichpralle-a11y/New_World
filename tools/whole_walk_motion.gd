extends SceneTree
## Whole runtime sprites, both directions, without touching game saves.
## Live: Godot --path . --script res://tools/whole_walk_motion.gd
## Capture: append -- --capture=/absolute/output/directory
## Captures 24 viewport PNGs over one deterministic cycle. For playback,
## each PNG lasts 1/40.8 s (six images per pose, 6.8 poses per second).

const WALK_SPEED := 34.0
const CYCLE_DISTANCE := 20.0
const CAPTURE_COUNT := 24
const CANVAS_SIZE := Vector2i(1280, 900)

var _sprites: Array[Sprite2D] = []
var _phase_label: Label
var _distance := 0.0
var _capturing := false
var _ready_to_animate := false


func _initialize() -> void:
	call_deferred("_show_motion")


func _process(delta: float) -> bool:
	if _ready_to_animate and not _capturing:
		_distance = fposmod(_distance + WALK_SPEED * delta, CYCLE_DISTANCE)
		_set_distance(_distance)
	return false


func _show_motion() -> void:
	root.size = CANVAS_SIZE
	root.content_scale_size = CANVAS_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var scene := Node2D.new()
	root.add_child(scene)
	var background := ColorRect.new()
	background.color = Color("#607344")
	background.size = Vector2(CANVAS_SIZE)
	scene.add_child(background)
	_add_label(scene, "Vollständige Gehfiguren · 6,8 Bilder/s · dunkles Bein hinten, helles Bein vorn", Vector2(28, 18), 25)
	_phase_label = _add_label(scene, "", Vector2(28, 56), 20)
	var names := ["Jonas →", "Jonas ←", "Lena →", "Lena ←"]
	for row in 2:
		var zoom := 4.0 if row == 0 else 8.0
		var ground_y := 365.0 if row == 0 else 825.0
		_add_label(scene, "Spielgröße × %d" % int(zoom), Vector2(28, 105 if row == 0 else 470), 21)
		var line := Line2D.new()
		line.width = 2.0
		line.default_color = Color("#c6d1aa")
		line.add_point(Vector2(20, ground_y))
		line.add_point(Vector2(1260, ground_y))
		scene.add_child(line)
		for col in 4:
			var person := Sprite2D.new()
			person.texture = HomeArt.WALK_JONAS if col < 2 else HomeArt.WALK_LENA
			person.hframes = HomeArt.WALK_FRAMES
			person.centered = false
			person.offset = Vector2(-80, -136)
			person.scale = HomeArt.SCALE * zoom
			person.flip_h = col % 2 == 1
			person.position = Vector2(160 + col * 320, ground_y)
			scene.add_child(person)
			_sprites.append(person)
			_add_label(scene, names[col], Vector2(105 + col * 320, ground_y + 16), 20)
	_ready_to_animate = true
	_set_distance(0.0)
	var capture_dir := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_dir = argument.trim_prefix("--capture=")
	if not capture_dir.is_empty():
		await _capture_cycle(capture_dir)


func _add_label(parent: Node, text: String, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#f6f2db"))
	parent.add_child(label)
	return label


func _set_distance(distance: float) -> void:
	var phase := int(distance / CYCLE_DISTANCE * HomeArt.WALK_FRAMES) % HomeArt.WALK_FRAMES
	for person in _sprites:
		person.frame = phase
	_phase_label.text = "Phase %d / %d" % [phase + 1, HomeArt.WALK_FRAMES]


func _capture_cycle(directory: String) -> void:
	_capturing = true
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		push_error("Cannot create motion capture directory: %s (%d)" % [directory, error])
		quit(1)
		return
	for index in CAPTURE_COUNT:
		_set_distance(CYCLE_DISTANCE * float(index) / CAPTURE_COUNT)
		await process_frame
		await RenderingServer.frame_post_draw
		var path := directory.path_join("walk-%02d.png" % index)
		var save_error := root.get_texture().get_image().save_png(path)
		if save_error != OK:
			push_error("Cannot save motion capture: %s (%d)" % [path, save_error])
			quit(1)
			return
	print("WHOLE WALK MOTION: 24 viewport PNGs in %s; playback 40.8 fps" % directory)
	quit()
