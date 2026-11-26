extends SceneTree

const Concert = preload("res://scripts/concert_voicing.gd")
const AudioEngine = preload("res://scripts/audio_engine.gd")
const SheetParser = preload("res://scripts/sheet_parser.gd")
const MainScene = preload("res://scenes/main.tscn")

var checks: int = 0
var failures: int = 0
var engine: Node = null

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	_test_step_voicing()
	_test_live_voicing()
	await _test_audio_engine()
	_test_real_sheet_voicing()
	await _test_audio_separation_and_capture()
	await _test_main_integration()
	_test_role_buses()
	_test_tail_limits()
	_test_bass_damping()
	if engine != null:
		engine.stop_all()
		await create_timer(0.15).timeout
		engine.queue_free()
		await process_frame
	print("Concert voicing: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _test_real_sheet_voicing() -> void:
	var file: FileAccess = FileAccess.open("res://assets/library/beloved_idyll.txt", FileAccess.READ)
	check(file != null, "Beloved Idyll sheet opens for analysis")
	if file == null:
		return
	var steps: Array[Dictionary] = SheetParser.parse(file.get_as_text(), true)
	Concert.voice_steps(steps)
	check(steps.size() > 8, "Beloved Idyll parses into enough steps for regression analysis")
	if steps.size() <= 8:
		return
	var vels: Dictionary = steps[0]["voiced_velocities"]
	var roles: Dictionary = steps[0]["voice_roles"]
	check(steps[0]["notes"] == [60, 72], "Beloved Idyll step 0 is [ts]")
	check(roles.get(72, "") == "lead" and roles.get(60, "") == "bass", "[ts] assigns lead to 72 and bass to 60")
	check(int(vels.get(72, 0)) >= int(vels.get(60, 0)) + 18, "[ts] lead is at least 18 velocity above bass")
	vels = steps[1]["voiced_velocities"]
	roles = steps[1]["voice_roles"]
	check(steps[1]["notes"] == [63, 67], "Beloved Idyll step 1 is [Yo]")
	check(roles.get(63, "") == "inner" and roles.get(67, "") == "inner", "[Yo] notes are both inner voices")
	check(int(vels.get(63, 127)) <= 68 and int(vels.get(67, 127)) <= 68, "[Yo] velocities stay at or below 68")
	check(int(steps[8]["voiced_velocities"].get(63, 127)) < int(steps[7]["voiced_velocities"].get(63, 127)), "Consecutive [Yo] step 8 attenuates below step 7")
	vels = steps[2]["voiced_velocities"]
	roles = steps[2]["voice_roles"]
	check(steps[2]["notes"] == [63, 67, 75], "Beloved Idyll step 2 is [YoD]")
	check(roles.get(75, "") == "lead" and int(vels.get(75, 0)) >= 110, "[YoD] D is a lead at velocity 110 or above")
	check(roles.get(67, "") == "inner" and int(vels.get(67, 127)) <= 70, "[YoD] o is inner at velocity 70 or below")
	check(int(vels.get(75, 0)) - int(vels.get(67, 127)) >= 40, "[YoD] lead exceeds inner by at least 40")
	var climax_index: int = -1
	for i: int in range(steps.size() - 1):
		if steps[i].get("token", "") == "[^V]" and steps[i + 1].get("token", "") == "[qEy]":
			climax_index = i
			break
	check(climax_index >= 0, "Climax [^V] is immediately followed by [qEy]")
	if climax_index >= 0:
		vels = steps[climax_index]["voiced_velocities"]
		roles = steps[climax_index]["voice_roles"]
		check(steps[climax_index]["notes"] == [46, 92], "Climax [^V] resolves to MIDI 46 and 92")
		check(roles.get(92, "") == "lead" and int(vels.get(92, 0)) >= 118, "Climax V is lead at velocity 118 or above")
		check(roles.get(46, "") == "bass" and int(vels.get(46, 0)) >= 92, "Climax ^ is bass at velocity 92 or above")
		vels = steps[climax_index + 1]["voiced_velocities"]
		roles = steps[climax_index + 1]["voice_roles"]
		var all_inner: bool = true
		for note: Variant in steps[climax_index + 1]["notes"]:
			all_inner = all_inner and roles.get(int(note), "") == "inner" and int(vels.get(int(note), 127)) <= 68
		check(all_inner, "Every [qEy] note is inner at velocity 68 or below")

func _test_audio_separation_and_capture() -> void:
	var local_engine: Node = AudioEngine.new()
	root.add_child(local_engine)
	await process_frame
	local_engine.set_volume(100)
	local_engine.stop_all()
	local_engine.note_on(401, 75, 117, "lead")
	local_engine.note_on(402, 67, 65, "inner")
	var voices: Dictionary = local_engine.get("voices")
	var lead_player: AudioStreamPlayer = voices[401]["player"]
	var inner_player: AudioStreamPlayer = voices[402]["player"]
	check(linear_to_db(lead_player.volume_linear / inner_player.volume_linear) >= 8.0, "Lead player level exceeds inner by at least 8 dB")
	local_engine.stop_all()
	local_engine.set_sustain(true)
	local_engine.note_on(410, 75, 117, "lead")
	local_engine.note_on(411, 41, 94, "bass")
	local_engine.note_off(411)
	local_engine.note_on(412, 46, 94, "bass")
	voices = local_engine.get("voices")
	check(bool(voices[411]["stolen"]), "F2 released under sustain is stolen by harmonic A#2")
	check(not bool(voices[410]["stolen"]), "Held lead 75 survives bass harmonic half-pedal stealing")
	local_engine.stop_all()
	local_engine.set_sustain(false)
	var master_index: int = AudioServer.get_bus_index("Master")
	var capture: AudioEffectCapture = AudioEffectCapture.new()
	capture.buffer_length = 3.0
	var capture_index: int = AudioServer.get_bus_effect_count(master_index)
	AudioServer.add_bus_effect(master_index, capture)
	var disabled_effects: Array[Vector2i] = []
	for bus_name: String in ["PianoLead", "PianoWarm", "PianoBass", "PianoReverb", "Master"]:
		var bus_index: int = AudioServer.get_bus_index(bus_name)
		for effect_index: int in range(AudioServer.get_bus_effect_count(bus_index)):
			if bus_index == master_index and effect_index == capture_index:
				continue
			disabled_effects.append(Vector2i(bus_index, effect_index))
			AudioServer.set_bus_effect_enabled(bus_index, effect_index, false)
	local_engine.set_volume(100)
	var rms: Array[float] = []
	var clipped_counts: Array[int] = []
	for case_index: int in range(2):
		local_engine.stop_all()
		await create_timer(0.2).timeout
		capture.clear_buffer()
		if case_index == 0:
			local_engine.note_on(420, 75, 117, "lead")
		else:
			local_engine.note_on(421, 67, 65, "inner")
		await create_timer(0.8).timeout
		var frames: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
		var energy: float = 0.0
		var clipped: int = 0
		for frame: Vector2 in frames:
			energy += frame.length_squared()
			if absf(frame.x) >= 1.0 or absf(frame.y) >= 1.0:
				clipped += 1
		rms.append(sqrt(energy / maxf(1.0, float(frames.size() * 2))))
		clipped_counts.append(clipped)
		check(not frames.is_empty(), "Master capture receives audio for case %d" % case_index)
	check(rms.size() == 2 and linear_to_db(rms[0] / maxf(rms[1], 0.000001)) >= 8.0, "Captured lead RMS exceeds inner RMS by at least 8 dB")
	check(clipped_counts.size() == 2 and clipped_counts[0] == 0 and clipped_counts[1] == 0, "Lead and inner Master captures have zero clipped frames")
	local_engine.stop_all()
	await create_timer(0.15).timeout
	AudioServer.remove_bus_effect(master_index, capture_index)
	for bus_effect: Vector2i in disabled_effects:
		AudioServer.set_bus_effect_enabled(bus_effect.x, bus_effect.y, true)
	local_engine.queue_free()
	await process_frame

func _test_main_integration() -> void:
	root.size = Vector2i(1600, 900)
	var app: Node = MainScene.instantiate()
	root.add_child(app)
	await process_frame
	var menu: Node = app.get("menu")
	var toggle: CheckButton = menu.get("concert_voicing_toggle")
	var app_audio: Node = app.get("audio")
	check(bool(app.get("concert_voicing_enabled")) and bool(app_audio.get("concert_voicing_enabled")), "Concert voicing starts enabled in app and audio")
	check(toggle != null and toggle.text == "Peso de teclas y realce de melodía" and toggle.button_pressed, "Concert voicing menu toggle starts labeled and enabled")
	app.set("auto_enabled", false)
	app.set("user_transposition", 0)
	app.set("transposition", 0)
	var manual_keys: Array[int] = [KEY_8, KEY_T, KEY_U, KEY_O]
	for key_code: int in manual_keys:
		var down_ev: InputEventKey = InputEventKey.new()
		down_ev.keycode = key_code
		down_ev.physical_keycode = key_code
		down_ev.pressed = true
		app.call("_input", down_ev)
	var live_voices: Dictionary = app_audio.get("voices")
	var roles_by_midi: Dictionary = {}
	var buses_by_midi: Dictionary = {}
	for v_data: Variant in live_voices.values():
		var vd: Dictionary = v_data
		if not bool(vd.get("released", false)):
			var m_pitch: int = int(vd.get("midi", -1))
			roles_by_midi[m_pitch] = str(vd.get("role", ""))
			var v_player: AudioStreamPlayer = vd.get("player")
			buses_by_midi[m_pitch] = str(v_player.bus) if v_player != null else ""
	check(roles_by_midi.get(48, "") == "bass" and roles_by_midi.get(60, "") == "inner" and roles_by_midi.get(64, "") == "inner" and roles_by_midi.get(67, "") == "lead", "Manual QWERTY chord assigns bass, inner, and lead roles across separate key events")
	check(buses_by_midi.get(48, "") == "PianoBass" and buses_by_midi.get(60, "") == "PianoWarm" and buses_by_midi.get(64, "") == "PianoWarm" and buses_by_midi.get(67, "") == "PianoLead", "Manual QWERTY chord routes active voices to PianoBass, PianoWarm, and PianoLead")
	toggle.button_pressed = false
	var rerouted_plain: bool = true
	for v_data: Variant in live_voices.values():
		var vd: Dictionary = v_data
		if not bool(vd.get("released", false)):
			var v_player: AudioStreamPlayer = vd.get("player")
			if v_player == null or str(v_player.bus) != "GrandPiano" or not is_equal_approx(float(vd.get("weight", 0.0)), 1.0):
				rerouted_plain = false
	check(rerouted_plain, "Disabling UI voicing toggle immediately reroutes held manual voices to GrandPiano with unit weight")
	toggle.button_pressed = true
	for key_code: int in manual_keys:
		var up_ev: InputEventKey = InputEventKey.new()
		up_ev.keycode = key_code
		up_ev.physical_keycode = key_code
		up_ev.pressed = false
		app.call("_input", up_ev)
	app_audio.call("stop_all")
	await process_frame
	var legato_first: InputEventKey = InputEventKey.new()
	legato_first.keycode = KEY_O
	legato_first.physical_keycode = KEY_O
	legato_first.pressed = true
	app.call("_input", legato_first)
	var legato_t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - legato_t0 < 120:
		await create_timer(0.05).timeout
	var legato_second: InputEventKey = InputEventKey.new()
	legato_second.keycode = KEY_U
	legato_second.physical_keycode = KEY_U
	legato_second.pressed = true
	app.call("_input", legato_second)
	var seq_roles: Dictionary = {}
	for v_data: Variant in (app_audio.get("voices") as Dictionary).values():
		var vd: Dictionary = v_data
		if not bool(vd.get("released", false)):
			seq_roles[int(vd.get("midi", -1))] = str(vd.get("role", ""))
	check(seq_roles.get(67, "") == "lead" and seq_roles.get(64, "") == "lead", "Sequential legato notes outside the 90 ms chord window stay independent leads")
	for key_code: int in [KEY_O, KEY_U]:
		var rel_ev: InputEventKey = InputEventKey.new()
		rel_ev.keycode = key_code
		rel_ev.physical_keycode = key_code
		rel_ev.pressed = false
		app.call("_input", rel_ev)
	app_audio.call("stop_all")
	var library: Object = app.get("library")
	var songs: Array = library.get("songs")
	var song_index: int = -1
	for i: int in range(songs.size()):
		if str(songs[i].get("id", "")) == "beloved-idyll":
			song_index = i
			break
	check(song_index >= 0, "Beloved Idyll exists in app library")
	if song_index >= 0:
		app.call("_load_song", song_index)
		var app_steps: Array = app.get("steps")
		var app_voicing: Array = app.get("step_voicing")
		check(not app_steps.is_empty() and app_voicing.size() == app_steps.size() and app_voicing[0].has("voiced_velocities") and app_voicing[0].has("voice_roles") and not app_steps[0].has("voiced_velocities"), "Loading Beloved Idyll populates parallel step_voicing without mutating raw steps")
		var baseline_voicing: Array = (app.get("step_voicing") as Array).duplicate(true)
		app.call("set_transposition", -24)
		var transposed_voicing: Array = app.get("step_voicing")
		check(transposed_voicing != baseline_voicing, "Changing user transposition recomputes step_voicing metadata")
		app.call("set_transposition", 0)
		app.call("set_bot_enabled", true)
		check(bool(app.get("bot_enabled")), "Bot starts on loaded sheet step 0")
		await create_timer(0.35).timeout
		check(int(app.get("_bot_current_step")) >= 1, "Bot advances from step 0 to step 1")
		app.call("set_bot_enabled", false)
		check(not bool(app.get("bot_enabled")), "Bot stops cleanly after integration playback")
		app.call("_change_instrument", "church_organ")
		app.call("set_bot_enabled", true)
		var organ_uniform: bool = not (app_audio.get("voices") as Dictionary).is_empty()
		for v_data: Variant in (app_audio.get("voices") as Dictionary).values():
			var vd: Dictionary = v_data
			if int(vd.get("velocity", -1)) != 108 or not str(vd.get("role", "")).is_empty():
				organ_uniform = false
		check(organ_uniform, "Non-piano instrument keeps uniform unvoiced sheet velocities during Bot playback")
		app.call("set_bot_enabled", false)
		app_audio.call("stop_all")
		for key_code: int in manual_keys:
			var org_down: InputEventKey = InputEventKey.new()
			org_down.keycode = key_code
			org_down.physical_keycode = key_code
			org_down.pressed = true
			app.call("_input", org_down)
		var organ_live_uniform: bool = not (app_audio.get("voices") as Dictionary).is_empty()
		for v_data: Variant in (app_audio.get("voices") as Dictionary).values():
			var vd: Dictionary = v_data
			if int(vd.get("velocity", -1)) != 108 or not str(vd.get("role", "")).is_empty():
				organ_live_uniform = false
		check(organ_live_uniform, "Non-piano instrument keeps uniform unvoiced velocities on manual QWERTY chords")
		for key_code: int in manual_keys:
			var org_up: InputEventKey = InputEventKey.new()
			org_up.keycode = key_code
			org_up.physical_keycode = key_code
			org_up.pressed = false
			app.call("_input", org_up)
		app_audio.call("stop_all")
		app.call("_change_instrument", "grand_piano")
		app.set("step_index", 2)
		app.call("set_concert_voicing_enabled", true)
		app.call("set_bot_enabled", true)
		app.call("set_concert_voicing_enabled", false)
		var restored_sheet_unvoiced: bool = not (app_audio.get("voices") as Dictionary).is_empty()
		for v_data: Variant in (app_audio.get("voices") as Dictionary).values():
			var vd: Dictionary = v_data
			if not bool(vd.get("released", false)):
				if int(vd.get("velocity", -1)) != 108 or not str(vd.get("role", "")).is_empty():
					restored_sheet_unvoiced = false
		check(restored_sheet_unvoiced, "Disabling concert voicing mid-step on VP sheet restores full default velocity 108")
		app.call("set_bot_enabled", false)
		app_audio.call("stop_all")
		app.set("step_index", 2)
		app.call("set_concert_voicing_enabled", false)
		app.call("set_bot_enabled", true)
		app.call("set_concert_voicing_enabled", true)
		var sheet_roles_after_enable: Dictionary = {}
		for v_data: Variant in (app_audio.get("voices") as Dictionary).values():
			var vd: Dictionary = v_data
			if not bool(vd.get("released", false)):
				sheet_roles_after_enable[str(vd.get("role", ""))] = true
		check(sheet_roles_after_enable.has("inner") and sheet_roles_after_enable.has("lead"), "Enabling concert voicing mid-step restores precomputed inner and lead sheet roles")
		app.call("set_bot_enabled", false)
		app_audio.call("stop_all")
	toggle.button_pressed = false
	check(not bool(app.get("concert_voicing_enabled")) and not bool(app_audio.get("concert_voicing_enabled")), "UI toggle disables voicing in app and audio")
	var settings_path: String = "user://test_concert_voicing_settings.cfg"
	app.call("save_user_settings", settings_path)
	if not FileAccess.file_exists(settings_path):
		# Some sandboxed headless runners cannot write Godot's per-user data directory.
		# Keep exercising the same ConfigFile persistence path with a repo-local temporary file.
		settings_path = "res://test_concert_voicing_settings.cfg"
		app.call("save_user_settings", settings_path)
	check(FileAccess.file_exists(settings_path), "Temporary concert voicing settings file is written")
	app.call("set_concert_voicing_enabled", true)
	var loaded: bool = bool(app.call("load_user_settings", settings_path))
	menu = app.get("menu")
	toggle = menu.get("concert_voicing_toggle")
	app_audio = app.get("audio")
	check(loaded and not bool(app.get("concert_voicing_enabled")) and not bool(app_audio.get("concert_voicing_enabled")) and not toggle.button_pressed, "Settings reload restores persisted disabled concert voicing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	app_audio.call("stop_all")
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	await process_frame

func _test_step_voicing() -> void:
	var steps: Array[Dictionary] = [
		{"notes": [60, 64, 67], "transposition": 12, "velocities": {60: 91, 67: 119}},
		{"notes": [60, 64, 67], "transposition": null},
		{"notes": [60, 64, 67], "transposition": 12},
	]
	for i: int in range(7):
		steps.append({"notes": [84, 88, 91], "transposition": 0})
	Concert.voice_steps(steps)
	var first: Dictionary = steps[0]
	var first_velocities: Dictionary = first["voiced_velocities"]
	var first_roles: Dictionary = first["voice_roles"]
	check(first_velocities.has(60) and first_velocities.has(64) and first_velocities.has(67), "Step velocities use raw note keys under transposition")
	check(not first_velocities.has(72) and not first_roles.has(72), "Transposed pitches are not used as metadata keys")
	check(first_velocities[60] == 91 and first_velocities[67] == 119, "Explicit velocities override generated values by raw note")
	var comparison_steps: Array[Dictionary] = []
	for step: Dictionary in steps:
		var copy: Dictionary = step.duplicate(true)
		copy.erase("velocities")
		comparison_steps.append(copy)
	Concert.voice_steps(comparison_steps)
	check(first_roles == comparison_steps[0]["voice_roles"], "Explicit velocity changes preserve generated voice roles")
	check(steps[1]["voiced_velocities"].has(67) and steps[1]["voice_roles"].has(67), "Null transposition is treated as zero")
	var accompaniment: Array[Dictionary] = []
	for i: int in range(7):
		accompaniment.append({"notes": [84, 88, 91]})
	accompaniment.append({"notes": [60, 64, 67]})
	accompaniment.append({"notes": [60, 64, 67]})
	for i: int in range(7):
		accompaniment.append({"notes": [84, 88, 91]})
	Concert.voice_steps(accompaniment)
	var repeated_before: Dictionary = accompaniment[7]["voiced_velocities"]
	var repeated_after: Dictionary = accompaniment[8]["voiced_velocities"]
	check(int(repeated_after[67]) < int(repeated_before[67]), "Repeated accompaniment receives contextual attenuation")
	var phrase_mid: Array[Dictionary] = [{"notes": [64]}, {"notes": [64]}, {"notes": [64]}, {"notes": [64]}, {"notes": [58]}]
	var voiced_base: Array[Dictionary] = Concert.build_step_voicing(phrase_mid, 0)
	var voiced_down: Array[Dictionary] = Concert.build_step_voicing(phrase_mid, -12)
	check(voiced_base[4]["voice_roles"].get(58, "") == Concert.ROLE_LEAD and voiced_down[4]["voice_roles"].get(58, "") == Concert.ROLE_BASS, "Downward extra transposition reclassifies note crossing bass threshold")
	var overflow_chord: Array[Dictionary] = [{"notes": [60, 102], "transposition": 0}]
	var voiced_overflow: Array[Dictionary] = Concert.build_step_voicing(overflow_chord, 12)
	check(voiced_overflow[0]["voice_roles"].get(60, "") == Concert.ROLE_LEAD and not voiced_overflow[0]["voice_roles"].has(102), "Out-of-range transposed notes do not steal lead role from highest playable note")

func _test_live_voicing() -> void:
	var empty: Dictionary = Concert.voice_live_chord([])
	check((empty["velocities"] as Dictionary).is_empty() and (empty["roles"] as Dictionary).is_empty(), "Empty live chord returns empty maps")
	var singleton: Dictionary = Concert.voice_live_chord([48], 110)
	check(singleton["velocities"][48] == 110 and singleton["roles"][48] == Concert.ROLE_BASS, "Singleton live bass keeps base velocity and bass role")
	var live: Dictionary = Concert.voice_live_chord([67, 48, 64, 67], 108)
	var velocities: Dictionary = live["velocities"]
	var roles: Dictionary = live["roles"]
	check(velocities.size() == 3 and roles.size() == 3, "Live chord deduplicates repeated pitches")
	check(roles[48] == Concert.ROLE_BASS and roles[64] == Concert.ROLE_INNER and roles[67] == Concert.ROLE_LEAD, "Live chord assigns bass, inner, and lead roles")

func _test_audio_engine() -> void:
	engine = AudioEngine.new()
	root.add_child(engine)
	await process_frame
	engine.stop_all()
	engine.concert_voicing_enabled = true
	engine.note_on(101, 72, 108, "lead")
	var lead: Dictionary = engine.voices[101]
	var lead_bloom: float = 1.0 + 0.10 * clampf(float(72 - 60) / 30.0, 0.0, 1.0)
	var expected_lead_weight: float = lead_bloom * clampf(pow(108.0 / 108.0, 0.50), 0.65, 1.20)
	var expected_gain: float = pow(108.0 / 127.0, 1.15) * engine.SAMPLE_GAIN * 1.0
	check(is_equal_approx(float(lead["gain"]), expected_gain), "Voice gain stores exact velocity curve separately from role weight")
	check(is_equal_approx(float(lead["weight"]), expected_lead_weight), "Lead role weight is stored separately")
	check(is_equal_approx((lead["player"] as AudioStreamPlayer).volume_linear, expected_gain * expected_lead_weight * float(lead["norm"]) * engine.master_volume), "Player level multiplies gain, role weight, normalization, and master volume")
	engine.note_on(102, 48, 90, "bass")
	check((engine.voices[102]["player"] as AudioStreamPlayer).bus == "PianoBass", "Explicit bass routes to bass bus")
	engine.note_on(103, 64, 90, "inner")
	check((engine.voices[103]["player"] as AudioStreamPlayer).bus == "PianoWarm", "Explicit inner routes to warm bus")
	engine.concert_voicing_enabled = false
	check((engine.voices[102]["player"] as AudioStreamPlayer).bus == "GrandPiano" and is_equal_approx(float(engine.voices[102]["weight"]), 1.0) and str(engine.voices[102]["role"]).is_empty(), "Disabling concert voicing immediately reroutes and unweights already-held voices")
	engine.note_on(104, 60, 108, "lead")
	check(str(engine.voices[104]["role"]).is_empty() and (engine.voices[104]["player"] as AudioStreamPlayer).bus == "GrandPiano", "Disabled concert voicing uses plain piano route")
	engine.concert_voicing_enabled = true
	check((engine.voices[102]["player"] as AudioStreamPlayer).bus == "PianoBass" and (engine.voices[103]["player"] as AudioStreamPlayer).bus == "PianoWarm", "Re-enabling concert voicing restores role buses on held piano voices")
	engine.current_instrument = "church_organ"
	engine.note_on(105, 60, 108, "lead")
	check(str(engine.voices[105]["role"]).is_empty() and (engine.voices[105]["player"] as AudioStreamPlayer).bus == "GrandPiano", "Non-piano instrument bypasses role voicing")
	engine.current_instrument = "grand_piano"
	check(is_equal_approx(engine._calculate_release_time(45, true, "bass"), engine.SUSTAIN_RELEASE_BASS), "Bass pitch uses bass sustain release")
	check(is_equal_approx(engine._calculate_release_time(60, true, "bass"), engine.SUSTAIN_RELEASE_TREBLE), "Bass role on MIDI 60 follows the pitch-based treble release")
	check(is_equal_approx(engine._calculate_release_time(60, true, "inner"), engine.INNER_SUSTAIN_RELEASE), "Inner role uses capped sustain tail")
	check(is_equal_approx(engine._calculate_release_time(60, true, "lead"), engine.SUSTAIN_RELEASE_TREBLE), "Lead role keeps treble sustain release")

func _test_role_buses() -> void:
	var piano_index: int = AudioServer.get_bus_index("GrandPiano")
	check(piano_index >= 0, "GrandPiano bus exists after engine setup")
	var bus_count_before: int = AudioServer.bus_count
	engine._setup_bus()
	engine._setup_bus()
	check(AudioServer.bus_count == bus_count_before, "Existing bus setup is idempotent")
	var warm_index: int = AudioServer.get_bus_index("PianoWarm")
	if warm_index >= 0:
		AudioServer.remove_bus(warm_index)
	engine._setup_bus()
	check(AudioServer.get_bus_index("PianoWarm") >= 0, "Role setup recreates a missing bus when GrandPiano exists")
	check(AudioServer.get_bus_index("PianoLead") >= 0 and AudioServer.get_bus_index("PianoBass") >= 0, "All role buses are available")

func _test_tail_limits() -> void:
	engine.stop_all()
	engine.concert_voicing_enabled = true
	engine.current_instrument = "grand_piano"
	var tokens: Array[int] = [90, 10, 80, 20, 70, 30, 60, 40, 50]
	for i: int in range(tokens.size()):
		engine.note_on(tokens[i], 60 + i, 90, "inner")
	for token: int in tokens:
		engine.note_off(token)
	engine.note_on(200, 75, 90, "inner")
	check(bool(engine.voices[90]["stolen"]), "Inner tail cap steals oldest voice order despite nonmonotonic tokens")
	check(not bool(engine.voices[10]["stolen"]), "Inner tail cap does not steal the numerically smallest token")
	engine.stop_all()


func _test_bass_damping() -> void:
	engine.stop_all()
	engine.note_on(301, 36, 108, "bass")
	engine.note_off(301)
	engine.note_on(302, 48, 108, "bass")
	check(not bool(engine.voices[301]["stolen"]), "Explicit bass preserves a released octave of the same pitch class")
	engine.note_on(303, 38, 108, "bass")
	check(bool(engine.voices[301]["stolen"]), "Explicit bass damps a released different pitch class")
	check(not bool(engine.voices[302]["stolen"]), "Harmonic damping preserves held bass notes")
	engine.stop_all()
	engine.note_on(304, 36, 108, "bass")
	engine.note_off(304)
	engine.note_on(305, 38, 108)
	check(not bool(engine.voices[304]["stolen"]), "Inferred bass does not trigger explicit harmonic damping")
	engine.stop_all()
