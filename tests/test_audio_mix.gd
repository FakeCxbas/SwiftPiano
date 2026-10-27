extends SceneTree
## Capture the actual processed mixer output, without playing through speakers.
## godot --headless --audio-driver Dummy --path . --script tests/test_audio_mix.gd
const EngineScript = preload("res://scripts/audio_engine.gd")
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var piano = EngineScript.new()
	root.add_child(piano)
	var bus = AudioServer.get_bus_index("Master")
	var reference = "--reference" in OS.get_cmdline_user_args()
	if "--clarity-baseline" in OS.get_cmdline_user_args():
		AudioServer.get_bus_effect(AudioServer.get_bus_index("PianoReverb"), 1).pre_gain_db = 3.8
	if reference:
		var compressor = AudioServer.get_bus_effect(AudioServer.get_bus_index("GrandPiano"), 0)
		compressor.threshold = -10.0
		compressor.ratio = 2.0
		compressor.gain = 0.0
	print("PROFILE: ", "previous" if reference else "presence")
	var capture = AudioEffectCapture.new()
	capture.buffer_length = 4.0
	var capture_index = AudioServer.get_bus_effect_count(bus)
	AudioServer.add_bus_effect(bus, capture)
	var cases = [
		{"name": "single", "notes": [60], "volume": 200, "velocity": 88, "preset": "studio"},
		{"name": "clear_chord", "notes": [48, 55, 60, 64, 67], "volume": 200, "velocity": 88, "preset": "studio"},
		{"name": "chord", "notes": [36, 48, 55, 60, 64, 67, 72, 76], "volume": 100, "velocity": 59},
		{"name": "sustain_200", "notes": [36, 48, 55, 60, 64, 67, 72, 76], "volume": 200, "velocity": 59},
		{"name": "stress_64", "notes": range(36, 100), "volume": 200, "velocity": 127},
	]
	for preset in ["dry", "studio", "cathedral"]:
		cases.append({"name": preset, "notes": range(36, 100), "volume": 200, "velocity": 127, "preset": preset})
	for instrument in piano.INSTRUMENTS:
		cases.append({"name": instrument, "notes": [36, 48, 55, 60, 64, 67, 72, 76], "volume": 200, "velocity": 88, "instrument": instrument, "preset": "cathedral"})
	for scenario in cases:
		piano.stop_all()
		piano.set_instrument(scenario.get("instrument", "grand_piano"))
		piano.set_reverb_preset(scenario.get("preset", "hall"))
		await create_timer(0.4).timeout
		capture.clear_buffer()
		piano.set_volume(scenario.volume)
		piano.set_sustain(true)
		var token = 0
		var repeats = 4 if scenario.name == "sustain_200" else 1
		for repeat in range(repeats):
			for note in scenario.notes:
				piano.note_on(token, note, scenario.velocity)
				piano.note_off(token)
				token += 1
			await create_timer(0.12).timeout
		await create_timer(1.0).timeout
		var frames = capture.get_buffer(capture.get_frames_available())
		var peak = 0.0
		var energy = 0.0
		var clipped = 0
		for frame in frames:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
			energy += frame.length_squared()
			if absf(frame.x) >= 1.0 or absf(frame.y) >= 1.0:
				clipped += 1
		var rms = sqrt(energy / maxf(1, frames.size() * 2))
		if not reference and scenario.name == "single" and linear_to_db(rms) < -28.0:
			failures += 1
			push_error("Single-note level did not reach the presence target")
		print("%s: frames=%d peak=%.2f dBFS RMS=%.2f dBFS clipped=%d" % [scenario.name, frames.size(), linear_to_db(peak), linear_to_db(rms), clipped])
		if frames.is_empty() or peak < 0.001 or peak > db_to_linear(-0.3) + 0.001 or clipped > 0 or capture.get_discarded_frames() > 0:
			failures += 1
			push_error("Mixer validation failed: " + scenario.name)
	piano.stop_all()
	await create_timer(0.2).timeout
	AudioServer.remove_bus_effect(bus, capture_index)
	piano.queue_free()
	await process_frame
	print("AUDIO MIX FAILURES: ", failures)
	quit(0 if failures == 0 else 1)
