extends SceneTree
## Actual full-frame textures at one shared scale, for checking the whole person.

func _initialize() -> void:
	call_deferred("_preview")


func _preview() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var scene := Node2D.new()
	root.add_child(scene)
	var bg := ColorRect.new()
	bg.color = Color("#607344")
	bg.size = Vector2(1280,720)
	scene.add_child(bg)
	for row in 2:
		for col in HomeArt.WALK_FRAMES:
			var p := Vector2(160+col*320,295+row*340)
			var s := Sprite2D.new()
			s.texture = HomeArt.WALK_JONAS if row==0 else HomeArt.WALK_LENA
			s.hframes = HomeArt.WALK_FRAMES
			s.frame = col
			s.centered = false
			s.offset = Vector2(-80,-136)
			s.scale = Vector2.ONE*1.75
			s.position = p
			scene.add_child(s)
			var label := Label.new()
			label.text = str(col+1)
			label.position = p+Vector2(-5,12)
			scene.add_child(label)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/fein-whole-walk.png")
	print("WHOLE WALK PREVIEW /private/tmp/fein-whole-walk.png")
	quit()
