extends SceneTree
var failures = 0
var checks = 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func click(button: Control) -> void:
	var point = button.get_global_rect().get_center()
	var motion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(event, true)
		await process_frame
	await process_frame

func run() -> void:
	root.size = Vector2i(1600, 900)
	root.notify_mouse_entered()
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await click(app.buttons.library)
	check(app.popup.visible and app.menu.section == "library", "Pointer opens library")
	await click(app.menu.close_button)
	check(not app.popup.visible, "Pointer closes drawer")
	check(app.buttons.library.get_theme_stylebox("normal").bg_color.a == 0, "Closed drawer clears nav highlight")
	await click(app.buttons.sheet)
	check(app.popup.visible and app.menu.section == "sheet", "Pointer opens sheet")
	await click(app.buttons.sheet)
	check(not app.popup.visible, "Second click toggles sheet off")
	var previous = app.sustain_enabled
	await click(app.buttons.sustain)
	check(app.sustain_enabled != previous, "Sustain toggles once per click")
	await click(app.buttons.auto)
	check(app.auto_enabled, "Auto starts by pointer")
	await click(app.buttons.auto)
	check(not app.auto_enabled, "Auto pauses by pointer")
	app.sheet_text_edit.text = ""
	app._compile_sheet()
	app._refresh()
	check(app.buttons.auto.disabled, "Empty sheet disables Auto")
	for mode in app.menu.light_mode_buttons:
		app.menu.set_active_light_mode("off")
		var emissions = [0]
		var listener = func(_c, _r, _m): emissions[0] += 1
		app.menu.appearance_changed.connect(listener)
		app.menu.set_active_light_mode(mode)
		app.menu.appearance_changed.disconnect(listener)
		check(app.menu.current_light_mode == mode and app.visualizer.light_mode == mode, "Off to requested light mode: " + mode)
	# Conversion section interaction & responsiveness tests
	app.menu.show_section("conversion")
	check(app.popup.visible and app.menu.section == "conversion", "Conversion section opens in drawer")
	check(app.buttons.sheet.get_theme_stylebox("normal").bg_color.a > 0, "Sheet tab remains highlighted during conversion")
	check(app.menu.converter.visible, "Converter panel is visible")
	
	# Test file dialog trigger from conversion
	app.menu.converter.choose_requested.emit()
	check(app._midi_dialog_target == "conversion" and app.midi_dialog.visible, "Conversion choose_requested opens midi dialog with conversion target")
	app.midi_dialog.hide()
	
	# Test apply signal does not double connect on close/reopen
	var apply_emissions = [0]
	var apply_listener = func(_s, _t): apply_emissions[0] += 1
	app.menu.converter.apply_requested.connect(apply_listener)
	app.menu.converter.apply_requested.emit("test", "test")
	check(apply_emissions[0] == 1, "apply_requested emits exactly once")
	app.menu.converter.apply_requested.disconnect(apply_listener)
	
	# Toggle close and reopen conversion
	await click(app.menu.close_button)
	check(not app.popup.visible, "Close button closes conversion drawer")
	app.menu.show_section("conversion")
	check(app.popup.visible and app.menu.section == "conversion", "Reopening conversion restores view")

	for dims in [Vector2(320, 480), Vector2(500, 420), Vector2(743, 419), Vector2(1600, 900)]:
		app.size = dims
		app._layout()
		await process_frame
		var ids = app.buttons.keys()
		for i in range(ids.size()):
			var a = app.buttons[ids[i]].get_rect()
			check(a.position.x >= 0 and a.end.x <= dims.x, "Button in viewport %s %s" % [ids[i], dims])
			for j in range(i + 1, ids.size()):
				check(not a.intersects(app.buttons[ids[j]].get_rect()), "Buttons do not overlap %s/%s at %s" % [ids[i], ids[j], dims])
		check(app.popup.get_rect().end.y <= dims.y * .8, "Drawer stays above piano")
	app.audio.stop_all()
	await create_timer(.2).timeout
	app.queue_free()
	await process_frame
	print("UI CHECKS: %d; FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
