extends SceneTree
## Measure only the artificial reverb tail, after forcibly stopping source voices.
const Piano = preload("res://scripts/audio_engine.gd")
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func tail_rms(piano: Node, capture: AudioEffectCapture, preset: String) -> float:
	piano.stop_all()
	piano.set_reverb_preset(preset)
	await create_timer(2.0).timeout
	capture.clear_buffer()
	for midi in [48, 55, 60, 64, 67, 72]:
		piano.note_on(midi, midi, 88)
	await create_timer(0.45).timeout
	piano.stop_all()
	# Allow the audio thread and limiter lookahead to drain the direct signal.
	await create_timer(0.15).timeout
	capture.clear_buffer()
	await create_timer(0.65).timeout
	var frames = capture.get_buffer(capture.get_frames_available())
	if frames.is_empty() or capture.get_discarded_frames() > 0:
		failures += 1
	var energy = 0.0
	for frame in frames:
		energy += frame.length_squared()
	return sqrt(energy / maxf(1.0, frames.size() * 2.0))

func run() -> void:
	var piano = Piano.new()
	root.add_child(piano)
	piano.set_volume(200)
	if piano.current_reverb_preset != "studio" or piano.reverb_effect.dry != 1.0:
		failures += 1
	var bus = AudioServer.get_bus_index("Master")
	var index = AudioServer.get_bus_effect_count(bus)
	var capture = AudioEffectCapture.new()
	capture.buffer_length = 4.0
	AudioServer.add_bus_effect(bus, capture)
	for instrument in ["grand_piano", "steinway_grand", "electric_piano"]:
		piano.set_instrument(instrument)
		var original = await tail_rms(piano, capture, "hall")
		var clear = await tail_rms(piano, capture, "studio")
		print("%s reverb tail: original %.2f dBFS, clear %.2f dBFS" % [instrument, linear_to_db(original), linear_to_db(clear)])
		if original <= 0 or clear >= original * 0.7:
			failures += 1
			push_error("Reverb tail did not decrease sufficiently: " + instrument)
	AudioServer.remove_bus_effect(bus, index)
	piano.queue_free()
	await process_frame
	print("CLARITY FAILURES: ", failures)
	quit(0 if failures == 0 else 1)
