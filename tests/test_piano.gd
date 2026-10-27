extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Keymap = preload("res://scripts/keymap_data.gd")
const Parser = preload("res://scripts/sheet_parser.gd")
var failures = 0
var checks = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func key(app: Node, code: int, down: bool, shift = false, echo = false, unicode = 0) -> void:
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	event.shift_pressed = shift
	event.echo = echo
	if unicode != 0:
		event.unicode = unicode
	app._input(event)

func _run() -> void:
	var app = Main.instantiate()
	root.add_child(app)
	await process_frame
	check(Keymap.mapping().size() == 61, "61 QWERTY bindings")
	check(Keymap.manual_note(KEY_SHIFT, false) == -1 and Keymap.manual_note(KEY_LEFT, false) == -1, "Modifiers and navigation keys ignored")
	check(Keymap.BLACKS.length() == 25 and Keymap.BLACK_PHYSICAL.length() == 25, "25 shifted bindings")
	for midi in range(36, 97):
		check(Keymap.labels().has(midi), "Missing label %d" % midi)
	check(app.keyboard.key_rects.size() == 88, "88 keys")
	var whites = 0
	for midi in app.keyboard.key_rects:
		if not Keymap.is_black(midi):
			whites += 1
	check(whites == 52, "52 whites / 36 blacks")
	check(app.qwerty_enabled and app.sustain_enabled and app.synth_enabled, "Initial toggles ON")
	check(app.indicators.sustain.visible and app.buttons.size() == 5, "All studio actions in top dock")
	check(app.volume_slider.max_value == 100 and app.volume_slider.value == 100 and app.audio.master_volume == 2.0, "New default 100 percent equals old 200 percent")
	check(app.audio.pool.size() == 64, "64 preallocated players")
	check(app.audio.sampled_piano and app.audio.bank.size() == 30, "30 real grand piano samples loaded")
	check(app.velocity == 108 and is_equal_approx(app.audio.SAMPLE_GAIN, 0.95), "Default velocity 108 and 95% base sample amplitude")
	app.audio.note_on(99000, 60, app.velocity)
	var expected_gain = pow(app.velocity / 127.0, 1.15) * 0.95
	check(is_equal_approx(app.audio.voices[99000].gain, expected_gain), "Normalized 95% sample gain at default velocity 108")
	var master_bus = AudioServer.get_bus_index("Master")
	var master_eq = AudioServer.get_bus_effect(master_bus, 0) as AudioEffectEQ
	var master_comp = AudioServer.get_bus_effect(master_bus, 1) as AudioEffectCompressor
	var master_lim = AudioServer.get_bus_effect(master_bus, 2) as AudioEffectLimiter
	check(master_eq != null and is_equal_approx(master_eq.get_band_gain_db(2), -3.0) and is_equal_approx(master_eq.get_band_gain_db(4), 1.5), "Master EQ cuts -3.0 dB at 250/320 Hz and boosts +1.5 dB at 3200 Hz")
	check(master_comp != null and is_equal_approx(master_comp.gain, 6.5) and master_lim != null and is_equal_approx(float(master_lim.get_meta("pre_gain", 0.0)), 6.5) and is_equal_approx(master_lim.ceiling_db, -0.3) and is_equal_approx(master_lim.threshold_db, -2.5), "Master Compressor and Limiter (+6.5 dB pre_gain, -0.3 dB ceiling, -2.5 dB threshold)")
	check(app.audio.reverb_effect != null and app.audio.reverb_effect.wet <= 0.04 and app.audio.reverb_effect.room_size <= 0.20 and is_equal_approx(app.audio.reverb_effect.damping, 0.90), "Close-Mic Studio Piano dry reverb (wet <= 0.04, room_size <= 0.20, damping = 0.90)")
	var piano_bus = AudioServer.get_bus_index("GrandPiano")
	var limiter = AudioServer.get_bus_effect(piano_bus, 1)
	check(limiter is AudioEffectHardLimiter and limiter.ceiling_db == -1.5 and AudioServer.is_bus_effect_enabled(piano_bus, 1), "Predictive limiter preserves headroom without soft clipping")
	app.audio.stop_all()
	for stream in app.audio.bank.values():
		check(stream is AudioStreamOggVorbis and stream.get_length() > 2, "Real recorded sample with natural decay")
	var reachable: Dictionary = {}
	var codes = range(KEY_0, KEY_Z + 1) + Keymap.LOW_KEYS + Keymap.HIGH_KEYS
	for code in codes:
		for shifted in [false, true]:
			var pitch = Keymap.manual_note(code, shifted)
			if pitch < 0:
				continue
			key(app, code, true, shifted)
			check(app.keyboard.active.has(pitch), "Fixed physical access to MIDI %d" % pitch)
			check(app.keyboard.labels.has(pitch), "All notes have visible bindings")
			reachable[pitch] = true
			key(app, code, false)
			app.audio.stop_all()
	check(reachable.size() == 88 and app.keyboard.labels.size() == 88, "88 permanent mappings without switching banks")
	key(app, KEY_RIGHT, true)
	key(app, KEY_RIGHT, false)
	key(app, KEY_M, true)
	check(app.keyboard.active.has(96), "Arrows do not change fixed mapping")
	key(app, KEY_F1, true)
	key(app, KEY_PAGEDOWN, true)
	check(app.keyboard.active.has(21) and app.keyboard.active.has(108), "Both extreme notes playable together")
	key(app, KEY_F1, false)
	key(app, KEY_PAGEDOWN, false)
	key(app, KEY_M, false)
	check(app.keyboard.active.is_empty(), "All sources released")
	for midi in range(21, 109):
		var rect: Rect2 = app.keyboard.key_rects[midi]
		var point = Vector2(rect.get_center().x, rect.get_center().y if Keymap.is_black(midi) else rect.end.y - 2)
		check(app.keyboard.hit_key(point) == midi, "Mouse access MIDI %d" % midi)
		app.audio.note_on(9000, midi, 59)
		var ratio: float = app.audio.voices[9000].player.pitch_scale
		check(absf(12 * log(ratio) / log(2)) < 1.01, "Sample nearest neighbor at most one semitone")
		app.audio.stop_all()
	check(app.steps.size() == 34, "Exact demo 34 steps")
	var sheet = Parser.parse("Title: My Song\nTransposition: 4\n6[er][680][W0ryd]\nTransposition: 0\nr[yI]")
	check(sheet.size() == 6, "Mixed continuous/chord steps")
	check(sheet[3].notes.size() == 5, "Mixed case chord")
	check(sheet[0].transposition == 4 and sheet[5].transposition == 0, "Transposition directives")
	check(Parser.parse("My Song\n[er|\n?wt] - ?.").size() == 1, "Ignore title / punctuation and preserve multiline chord")
	check(Parser.parse("W E").size() == 2, "Single uppercase notes are not titles")
	check(Parser.parse("[ﬂ]").size() == 1 and Parser.parse("[ﬂ]")[0].notes.size() == 2, "Unicode ligature ﬂ decomposes into f and l")
	check(Parser.parse("[ﬁ]").size() == 1 and Parser.parse("[ﬁ]")[0].notes.size() == 2, "Unicode ligature ﬁ decomposes into f and i")
	# Verify mandatory aliases for shifted keys without black keys: R, U, A, F, K, X, N, M, #, &, )
	var alias_expected = {"R": 59, "U": 64, "A": 71, "F": 76, "K": 83, "X": 88, "N": 95, "M": 96, "#": 40, "&": 47, ")": 52}
	for a_char in alias_expected:
		var a_parsed = Parser.parse("[" + a_char + "]")
		check(a_parsed.size() == 1 and a_parsed[0].notes == [alias_expected[a_char]], "Alias %s maps to MIDI %d" % [a_char, alias_expected[a_char]])
	# Verify Howl's Moving Castle 11-step sequence and black key symbols (! @ $ % ^ * ()
	var howl = Parser.parse("[@(YD] [%WOH] [7rak] 3 [0uf] [ig] [zd] [ZSl] [5^h] [R] [Sqet]")
	check(howl.size() == 11, "Howl's Moving Castle sequence produces exactly 11 steps")
	check(howl[0].notes == [39, 51, 63, 75], "[@(YD] triggers [39, 51, 63, 75]")
	check(howl[8].notes == [43, 46, 79], "[5^h] triggers [43, 46, 79]")
	check(howl[9].notes == [59], "[R] triggers [59]")
	key(app, KEY_1, true, true)
	check(app.keyboard.active.has(37), "Shift+1 = C#2")
	app.transposition = 12
	key(app, KEY_1, false)
	check(app.keyboard.active.is_empty(), "Release captured pitch after transpose change")
	app.transposition = 0
	app.popup.show()
	app.sheet_text_edit.text = "[er] [er]"
	app._popup_action("Auto")
	check(app.auto_enabled and not app.sheet_text_edit.editable and not app.sheet_text_edit.has_focus(), "Auto releases focus and disables editing")
	key(app, KEY_A, true)
	key(app, KEY_A, true, false, true)
	check(app.step_index == 1 and app.visualizer.bars.size() == 2, "Auto ignores echo")
	app._popup_action("Auto")
	app._popup_action("Auto")
	check(app.step_index == 1 and app.auto_enabled, "Auto resumes without recompiling or resetting")
	key(app, KEY_S, true)
	check(app.visualizer.bars.size() == 4 and app.step_index == 0, "Overlapping chord and wrap")
	app.visualizer.elapsed += 0.5
	for bar in app.visualizer.bars.values():
		check(is_equal_approx(app.visualizer.bar_rect(bar).end.y, app.visualizer.size.y), "Hold anchored at keyboard")
	key(app, KEY_A, false)
	check(app.keyboard.active.size() == 2 and app.visualizer.bars.size() == 2, "One source release preserves overlapping chord")
	key(app, KEY_S, false)
	check(app.keyboard.active.is_empty(), "All chord keys released")
	app.visualizer.elapsed += 0.5
	for bar in app.visualizer.released:
		check(app.visualizer.bar_rect(bar).end.y < app.visualizer.size.y, "Released bar travels upward")
	app._popup_action("Clear")
	check(not app.auto_enabled and app.steps.is_empty() and app.step_index == 0, "Clear resets")
	app._popup_action("Auto")
	check(not app.auto_enabled, "Empty sheet cannot activate Auto")
	app.sheet_text_edit.grab_focus()
	await process_frame
	key(app, KEY_ESCAPE, true)
	check(not app.sheet_text_edit.has_focus(), "Escape blurs editor")
	app._control("sustain", 1)
	key(app, KEY_SPACE, true)
	check(app.audio.sustain_enabled, "Space holds pedal when sustain toggle is off")
	key(app, KEY_SPACE, false)
	check(not app.audio.sustain_enabled, "Space release lifts pedal")
	app._control("sustain", 1)
	key(app, KEY_SPACE, true)
	key(app, KEY_SPACE, false)
	check(app.sustain_enabled and app.audio.sustain_enabled, "Space preserves latched Sustain")
	key(app, KEY_SPACE, true, true)
	key(app, KEY_SPACE, false, true)
	check(not app.sustain_enabled and not app.audio.sustain_enabled, "Shift-Space disables latch")
	key(app, KEY_SPACE, true, true)
	key(app, KEY_SPACE, false, true)
	check(app.sustain_enabled and app.audio.sustain_enabled, "Shift-Space latch survives key-up")
	app.menu.search_field.grab_focus()
	key(app, KEY_SPACE, true)
	key(app, KEY_SPACE, false)
	check(app.sustain_enabled, "Typing a space in search preserves latched Sustain")
	app.menu.search_field.release_focus()
	app._control("sustain", 1)
	app._mouse_note(60)
	check(app.keyboard.active.has(60), "Mouse note")
	app._mouse_note(62)
	check(not app.keyboard.active.has(60) and app.keyboard.active.has(62), "Mouse drag")
	app._mouse_note(-1)
	app.audio.stop_all()
	for i in range(80):
		app.audio.note_on(1000 + i, 21 + (i % 80), 108)
	check(app.audio.voices.size() == 80 and app.audio.pool.size() == 80, "Pool expands for 80 distinct voices")
	app.audio.set_sustain(false)
	app.audio.note_off(1000)
	await create_timer(0.18).timeout
	await process_frame
	check(not app.audio.voices.has(1000) and app.audio.voices.has(1001), "Independent 0.10s release with Sustain OFF")
	app.audio.stop_all()
	# Voice stealing on same MIDI note (0.025s ultra-fast fade-out)
	app.audio.set_sustain(true)
	app.audio.note_on(3000, 60, 108)
	app.audio.note_off(3000)
	app.audio.note_on(3001, 60, 108)
	check(app.audio.voices[3000].stolen, "Previous voice on same MIDI note marked stolen for 0.025s cut")
	await create_timer(0.06).timeout
	check(not app.audio.voices.has(3000) and app.audio.voices.has(3001), "Stolen voice faded out in 0.025s without accumulating copies")
	app.audio.stop_all()
	# Sustain ON controlled release: bass (<55) <= 0.75s, treble (>=55) <= 0.95s
	app.size = Vector2(751, 852)
	app.audio.set_sustain(true)
	app.audio.note_on(2000, 48, 108)
	app.audio.note_off(2000)
	check(app.audio.voices[2000].tween != null and is_equal_approx(app.audio._calculate_release_time(48, true), 2.60), "Bass note (<55) under Sustain ON uses 2.60s sustain envelope")
	check(is_equal_approx(app.audio._calculate_release_time(64, true), 3.40) and is_equal_approx(app.audio._calculate_release_time(64, false), 0.12), "Treble sustain release is 3.40s and Sustain OFF is 0.12s")
	app.volume_slider.value = 100
	check(is_equal_approx(app.audio.master_volume, 2.0) and is_equal_approx(AudioServer.get_bus_volume_db(master_bus), 0.0) and not AudioServer.is_bus_mute(master_bus), "100 percent maps to 0.0 dB on Master bus")
	check(is_equal_approx(app.audio.voices[2000].player.volume_linear, app.audio.voices[2000].gain * app.audio.voices[2000].norm * 2), "Volume updates sustained notes")
	app.volume_slider.value = 0
	check(is_zero_approx(app.audio.voices[2000].player.volume_linear) and AudioServer.is_bus_mute(master_bus), "Volume zero mutes existing notes and Master bus")
	app.volume_slider.value = 100
	app.volume_slider.value = 50
	check(is_equal_approx(app.audio.master_volume, 1.0) and is_equal_approx(AudioServer.get_bus_volume_db(master_bus), linear_to_db(0.5)), "50 percent attenuates Master bus post-limiter by -6.02 dB")
	app.volume_slider.value = 100
	app.audio.note_on(2001, 60, 108)
	app.audio.set_sustain(false)
	check(app.audio.voices[2000].tween != null and app.audio.voices[2001].tween == null, "Pedal up damps only released notes")
	await create_timer(0.18).timeout
	check(not app.audio.voices.has(2000) and app.audio.voices.has(2001), "Pedal release ends sustained note in 0.10s, preserves held note")
	app.audio.stop_all()
	app._layout()
	check(is_equal_approx(app.keyboard.size.x, 751), "Full-width 88 keys in tiled window")
	check(app.panel.position.y == 0 and app.popup.position.y >= app.panel.size.y, "Controls and editor at top")
	check(is_equal_approx(app.visualizer.position.y + app.visualizer.size.y, app.keyboard.position.y), "Waterfall meets keyboard")
	for viewport_size in [Vector2(320, 480), Vector2(743, 419), Vector2(1600, 900)]:
		app.size = viewport_size
		app._layout()
		check(app.volume_slider.position.x >= 0 and not app.volume_slider.get_rect().intersects(app.buttons.sustain.get_rect()), "Volume fits without overlapping buttons")
		check(app.popup.get_rect().end.y <= app.keyboard.position.y, "Auto panel stays above all 88 keys")
	app.size = Vector2(751, 852)
	app._layout()
	app._press_source(KEY_A, [60])
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	app.audio.stop_all()
	check(app.sources.is_empty(), "Source cleanup")
	check(app.library.songs.size() == 96, "92 PDF entries and four shared songs")
	var playable = 0
	for song in app.library.songs:
		var parsed = Parser.parse(song.sheet, true)
		if song.has_sheet:
			playable += 1
			check(not parsed.is_empty(), "Library sheet parses: " + song.title)
		else:
			check(song.title == "Love Story" and parsed.is_empty(), "Title-only entry is not invented")
	check(playable == 95, "95 playable entries and one title-only entry")
	check(Parser.parse("[(w]", true)[0].notes.has(Keymap.mapping()["("]), "Library preserves sharp symbol in PDF")
	check(Parser.parse("Transpose -11\n[ceg]", true)[0].transposition == -11, "PDF transpose directive without colon")
	check(app.library.search("old doll").size() == 2, "Case-insensitive title search")
	app.menu._filter_library("no-such-song-xyz")
	check(app.menu.song_list.item_count == 0 and app.menu.load_button.disabled, "Empty search handled")
	app.menu._filter_library("")
	app.menu.buttons.library.pressed.emit()
	check(app.menu.section == "library" and app.popup.visible, "Library button opens top drawer")
	app.menu.song_list.select(1)
	app.menu.song_list.item_selected.emit(1)
	check(not app.menu.load_button.disabled, "Selected playable song enables Load")
	app.menu.load_button.pressed.emit()
	check(app.selected_song == "letras-002" and not app.auto_enabled and app.step_index == 0, "Song loads paused from library")
	app.sheet_text_edit.text = "[ceg] t"
	app._load_song(2)
	app._load_song(1)
	check(app.sheet_text_edit.text == "[ceg] t", "Edits preserved as session drafts")
	app._popup_action("Auto")
	app.menu.show_section("library")
	app.menu.search_field.grab_focus()
	await process_frame
	var step_before = app.step_index
	key(app, KEY_A, true)
	key(app, KEY_A, false)
	check(app.step_index == step_before and app.sources.is_empty(), "Typing in library never plays Auto")
	app._menu_action("sheet")
	app._set_appearance(Color("#ff84b5"), false)
	app._press_source("color-test", [60])
	check(app.keyboard.note_colors[60].is_equal_approx(Color("#ff84b5")), "Selected color reaches pressed key")
	check(app.visualizer.bars.values()[-1].color.is_equal_approx(Color("#ff84b5")), "Selected color reaches waterfall")
	app._release_source("color-test")
	check(app.keyboard.illumination.has(60), "Key release leaves short fade")
	await create_timer(0.25).timeout
	check(not app.keyboard.illumination.has(60), "Key fade expires without sticky lights")
	app._set_appearance(Color("#64e8d0"), false)
	
	# Bar styles and key impact flare tests
	check(app.menu.bar_style_buttons.size() == 7, "7 selectable bar styles registered")
	for style_id in ["laser_crystal", "stardust", "comet", "cyber_pulse", "frosted_glass", "plasma", "harmonic"]:
		app.menu.set_active_bar_style(style_id)
		check(app.menu.current_bar_style == style_id, "Menu current_bar_style set to %s" % style_id)
		check(app.visualizer.bar_style == style_id, "Visualizer bar_style synced to %s" % style_id)
	
	# Light modes tests
	check(app.menu.light_mode_buttons.size() == 6, "6 selectable light modes registered")
	for mode_id in ["off", "supernova", "aurora", "starlight", "rave", "synthwave"]:
		app.menu.set_active_light_mode(mode_id)
		check(app.menu.current_light_mode == mode_id, "Menu current_light_mode set to %s" % mode_id)
		check(app.visualizer.light_mode == mode_id, "Visualizer light_mode synced to %s" % mode_id)
	
	app.visualizer.key_flares.clear()
	app.visualizer.key_rings.clear()
	app._press_source("splash-test", [64])
	check(not app.visualizer.key_flares.is_empty(), "Key flare created on note_on")
	check(not app.visualizer.key_rings.is_empty(), "Contact ripple ring created on note_on")
	check(app.visualizer.note_streak >= 1, "Note streak increments on note_on")
	app._release_source("splash-test")
	app.menu.set_active_bar_style("laser_crystal")
	app.menu.set_active_light_mode("supernova")
	
	# Zen mode toggle and Auto Tab reset tests
	check(not app.zen_mode, "Zen mode starts off")
	key(app, KEY_BAR, true, false, false, 124)
	key(app, KEY_BAR, false, false, false, 124)
	check(app.zen_mode and not app.menu.visible, "Pipe toggles Zen mode ON and hides top dock")
	
	# While Zen mode is on and Auto is enabled:
	app.auto_enabled = true
	app.steps = Parser.parse("[ceg] [dfa]", false)
	app.step_index = 1
	key(app, KEY_BAR, true, false, false, 124)
	key(app, KEY_BAR, false, false, false, 124)
	check(not app.zen_mode and app.menu.visible, "Pipe toggles Zen mode OFF and restores top dock")
	check(app.step_index == 1, "Pipe does not reset Auto step index")
	
	# Tab resets Auto step index without touching Zen mode
	key(app, KEY_TAB, true)
	key(app, KEY_TAB, false)
	check(app.step_index == 0, "Tab resets Auto step index to 0")
	check(not app.zen_mode, "Tab does not trigger Zen mode")
	
	# Anti-Spam & HDR Tonemapping verification (50 consecutive chords/notes)
	var world_env: WorldEnvironment = null
	for child in app.get_children():
		if child is WorldEnvironment:
			world_env = child
			break
	check(world_env != null and world_env.environment.tonemap_mode == Environment.TONE_MAPPER_ACES, "WorldEnvironment uses TONE_MAPPER_ACES")
	check(world_env != null and world_env.environment.glow_blend_mode == Environment.GLOW_BLEND_MODE_SCREEN, "WorldEnvironment uses GLOW_BLEND_MODE_SCREEN")
	check(world_env != null and is_equal_approx(world_env.environment.glow_hdr_luminance_cap, 2.2), "WorldEnvironment glow_hdr_luminance_cap is 2.2")
	for spam_i in range(50):
		var base_n = 36 + (spam_i % 48)
		app._press_source("spam-%d" % spam_i, [base_n, base_n + 4, base_n + 7])
	app.visualizer._process(0.016)
	check(app.visualizer.energy_scale <= 0.25 and app.visualizer.energy_scale >= 0.16, "50-chord spam attenuates energy_scale dynamically (%.3f)" % app.visualizer.energy_scale)
	check(app.visualizer.bg_shader_rect.modulate.a <= 0.35, "Background show opacity strictly capped <= 0.35 under 50-chord spam")
	for spam_i in range(50):
		app._release_source("spam-%d" % spam_i)
	app.visualizer.bars.clear()
	app.visualizer.released.clear()
	app.visualizer.recent_strikes.clear()
	
	app.auto_enabled = false
	app.library_sheet = false
	app.compiled_text = ""
	app.audio.stop_all()
	if "--capture" in OS.get_cmdline_user_args():
		app.visualizer.bars.clear()
		app.visualizer.released.clear()
		app.visualizer.elapsed = 0.0
		app.size = root.get_visible_rect().size
		app._layout()
		app.popup.show()
		app.menu.show_section("sheet", false)
		app.popup.show()
		app.sheet_text_edit.text = Keymap.DEMO
		app._compile_sheet()
		app._refresh()
		if "--library-capture" in OS.get_cmdline_user_args():
			app.menu.show_section("library")
			app.popup.show()
		elif "--appearance-capture" in OS.get_cmdline_user_args():
			app.menu.show_section("appearance")
			app.popup.show()
		for chord in [[48, 52, 55], [60, 64, 67], [65, 69, 72]]:
			app._press_source("preview", chord)
			await create_timer(0.2).timeout
			app._release_source("preview")
		app._press_source("held", [60, 64, 67])
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var capture = root.get_texture().get_image()
		# HDR viewport readback is linear; PNG viewers expect sRGB.
		if capture.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]:
			for y in range(capture.get_height()):
				for x in range(capture.get_width()):
					capture.set_pixel(x, y, capture.get_pixel(x, y).linear_to_srgb())
			capture.convert(Image.FORMAT_RGBA8)
		capture.save_png("/tmp/swiftpiano-godot.png")
		app._release_source("held")
	app.audio.stop_all()
	# AudioServer retires stopped playbacks on its next mixer updates.
	await create_timer(0.15).timeout
	app.queue_free()
	await process_frame
	await process_frame
	await process_frame
	print("CHECKS: %d; FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
