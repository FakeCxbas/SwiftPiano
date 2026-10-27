extends SceneTree
## Silent visual smoke test, isolated from timing-sensitive audio assertions.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	var viewport: Viewport = root
	if "--wide" in OS.get_cmdline_user_args():
		viewport = SubViewport.new()
		viewport.size = Vector2i(1600, 900)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
	viewport.add_child(app)
	await create_timer(0.5).timeout
	app.audio.set_volume(0)
	if "--glass" in OS.get_cmdline_user_args():
		app.menu.set_active_bar_style("frosted_glass")
	if "--library" in OS.get_cmdline_user_args():
		app.menu.show_section("library")
	elif "--studio" in OS.get_cmdline_user_args():
		app.menu.show_section("appearance")
	elif "--sheet" in OS.get_cmdline_user_args():
		app.menu.show_section("sheet")
	elif "--conversion" in OS.get_cmdline_user_args():
		app.menu.show_section("conversion")
		app.menu.converter.load_result({"sheet": "MIDI: 60 64 67\n[9o] [9(]", "tracks": 2, "percussion": 0, "omitted": 0}, "res://assets/demo.mid")
	for midi in [48, 55, 60, 64, 67, 72]:
		app.keyboard.press(midi, app.active_color)
		app.visualizer.note_on(midi, midi, app.active_color)
	await create_timer(0.3).timeout
	if "--resize" in OS.get_cmdline_user_args():
		for dims in [Vector2i(743, 419), Vector2i(320, 240), Vector2i(1600, 900)]:
			viewport.size = dims
			await create_timer(0.2).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var capture = viewport.get_texture().get_image()
		if capture.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]:
			for y in range(capture.get_height()):
				for x in range(capture.get_width()):
					capture.set_pixel(x, y, capture.get_pixel(x, y).linear_to_srgb())
			capture.convert(Image.FORMAT_RGBA8)
		capture.save_png("/tmp/swiftpiano-studio.png")
	app.audio.stop_all()
	app.queue_free()
	await process_frame
	await process_frame
	quit()
