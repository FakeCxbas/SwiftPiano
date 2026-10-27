extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
var checks = 0
var failures = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: %s" % message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var app = MainScene.instantiate()
	root.add_child(app)
	await create_timer(0.2).timeout
	
	# 1. Verify Audio Engine Instruments Registry
	check(app.audio.INSTRUMENTS.size() == 11, "11 instruments registered in audio engine")
	var expected_ids = [
		"grand_piano", "steinway_grand", "bright_piano", "honkytonk_piano",
		"electric_grand", "electric_piano", "fm_piano",
		"church_organ", "synth_strings", "celesta", "harpsichord"
	]
	for id in expected_ids:
		check(app.audio.INSTRUMENTS.has(id), "Instrument '%s' exists in registry" % id)
	
	# 2. Verify initial instrument state
	check(app.audio.current_instrument == "grand_piano", "Default instrument is grand_piano")
	check(app.audio.bank.size() == 30, "Initial grand piano bank has 30 samples")
	check(app.menu.instrument_buttons.size() == 11, "UI has 11 instrument selection buttons")
	check(app.menu.current_instrument == "grand_piano", "UI current instrument is grand_piano")
	check("Piano de Cola" in app.menu.song_title.text, "Initial song title displays Piano de Cola")
	
	# 3. Verify Reverb Bus & Presets
	check(app.audio.reverb_effect != null, "Acoustic reverb effect is instantiated")
	check(app.menu.reverb_buttons.size() == 4, "UI has 4 reverb preset buttons")
	for r_id in ["dry", "studio", "hall", "cathedral"]:
		var r_btn = app.menu.reverb_buttons[r_id]
		r_btn.pressed.emit()
		await create_timer(0.02).timeout
		check(app.audio.current_reverb_preset == r_id, "Reverb preset switched to '%s'" % r_id)
	app.menu.reverb_buttons["hall"].pressed.emit()
	
	# 4. Test switching across all 11 instruments
	for id in expected_ids:
		var btn = app.menu.instrument_buttons[id]
		btn.pressed.emit()
		await create_timer(0.05).timeout
		
		check(app.audio.current_instrument == id, "Audio engine switched to '%s'" % id)
		check(app.audio.bank.size() == 30, "'%s' bank contains 30 samples" % id)
		check(app.menu.current_instrument == id, "UI active instrument is '%s'" % id)
		var expected_name = app.audio.INSTRUMENTS[id].name
		check(expected_name in app.menu.song_title.text, "Top bar reflects '%s'" % expected_name)
		
		# Test note playback
		app.audio.note_on(500, 60, 80)
		check(app.audio.voices.has(500), "Voice started on instrument '%s'" % id)
		app.audio.note_off(500)
		app.audio.stop_all()
	
	# 5. Verify return to grand_piano
	app.menu.instrument_buttons["grand_piano"].pressed.emit()
	await create_timer(0.05).timeout
	check(app.audio.current_instrument == "grand_piano", "Successfully returned to grand_piano")
	check(app.audio.bank.size() == 30, "Grand piano bank still has 30 samples")
	
	print("INSTRUMENT TEST RESULTS: CHECKS: %d; FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
