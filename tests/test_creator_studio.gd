extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Parser = preload("res://scripts/sheet_parser.gd")

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func send_key(app: Node, code: int, down: bool, ctrl: bool = false, shift: bool = false, unicode: int = 0) -> void:
	var ev = InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	if unicode != 0:
		ev.unicode = unicode
	app._input(ev)

func _run() -> void:
	root.size = Vector2i(1600, 900)
	var app = Main.instantiate()
	root.add_child(app)
	await process_frame
	app.size = Vector2(1600, 900)
	app._layout()
	await process_frame

	# 1. Verify CreatorOverlay hierarchy in ui_layer & visibility during zen_mode
	check(app.creator_overlay != null, "CreatorOverlay is instantiated on main")
	check(app.creator_overlay.get_parent() == app.ui_layer, "CreatorOverlay is a direct child of ui_layer (CanvasLayer layer=1)")
	check(app.ui_layer.layer == 1, "ui_layer is on layer 1 (exempt from WorldEnvironment bloom)")
	var kb_idx = app.keyboard.get_index()
	var co_idx = app.creator_overlay.get_index()
	var menu_idx = app.menu.get_index()
	check(kb_idx < co_idx and co_idx < menu_idx, "CreatorOverlay is ordered between keyboard and menu in ui_layer")
	check(app.creator_overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "CreatorOverlay ignores mouse events")
	
	# Check BrandingCard defaults & positioning when zen_mode == false vs true
	var co = app.creator_overlay
	check(co.branding_enabled and co.branding_card.visible, "BrandingCard enabled and visible by default")
	check(co.badge_icon != null and co.badge_icon.text == "♪", "BrandingCard features illuminated music note badge")
	check(co.tag_panel != null and not co.tag_panel.visible, "Tag pill 'PIANO' is hidden per user request")
	check(co.divider_panel != null and co.divider_panel.name == "NeonLaserDivider", "BrandingCard features NeonLaserDivider laser bloom")
	check(co.channel_label.text == "@DragonCxbas", "Default channel label is @DragonCxbas")
	check(co.subtitle_label.text == "Virtual Piano Sheet in Description", "Default subtitle CTA is set")
	check(co.branding_style.border_color.a <= 0.35, "BrandingCard border has subtle liquid glass rim")
	check(co.neon_beam != null and not co.neon_beam.visible, "NeonTopBeam hidden to prevent floating grey line bug")
	check(co.branding_style.shadow_color.is_equal_approx(Color(0.0, 0.0, 0.0, 0.55)), "BrandingCard has deep liquid glass drop shadow")
	check(co.glass_rect != null and co.glass_mat != null, "BrandingCard features authentic Liquid Glass shader background")
	check(co.hud_glass_rect != null and co.hud_glass_mat != null, "LiveSheetHUD features authentic Liquid Glass shader background")
	check(co.hud_style.border_color.a <= 0.35, "LiveSheetHUD border has subtle liquid glass rim")
	check(co.hud_target_pos.x >= co.branding_target_pos.x + co.branding_card.size.x + 10.0, "LiveSheetHUD does not overlap with BrandingCard")
	check(is_equal_approx(co.branding_target_pos.x, 28.0) and is_equal_approx(co.branding_target_pos.y, app.menu.menu_height + 16.0), "BrandingCard sits below top menu when zen_mode is false")
	
	# Toggle Zen mode via '|' key
	send_key(app, KEY_BAR, true, false, false, 124)
	send_key(app, KEY_BAR, false, false, false, 124)
	check(app.zen_mode and not app.menu.visible, "Zen mode hides studio_menu")
	check(co.visible and co.branding_card.visible and co.hud_panel.visible, "CreatorOverlay, BrandingCard and LiveSheetHUD remain visible in zen_mode")
	check(is_equal_approx(co.branding_target_pos.x, 28.0) and is_equal_approx(co.branding_target_pos.y, 24.0), "BrandingCard moves to Vector2(28, 24) in zen_mode")
	check(co.zen_toast.visible and co.zen_toast.modulate.a > 0.5, "Zen mode micro-toast appears on entering zen_mode")
	check(co.zen_toast_label.text == "Modo Grabación Activo • [|] o [Esc] para mostrar menú", "Zen toast has exact required text")
	
	# Exit Zen mode via Escape
	send_key(app, KEY_ESCAPE, true)
	send_key(app, KEY_ESCAPE, false)
	check(not app.zen_mode and app.menu.visible, "Escape exits zen_mode and restores studio_menu")

	# 2. Howl's Moving Castle sheet & LiveSheetHUD exact token formatting
	var howl_sheet = "Title: Howl's Moving Castle\n[@(YD] [%WOH] [7rak] 3 [0uf] [ig] [zd] [ZSl] [5^h] [R] [Sqet]"
	app.sheet_text_edit.text = howl_sheet
	app.compiled_text = ""
	app._compile_sheet()
	app._refresh()
	
	check(app.steps.size() == 11, "Howl's Moving Castle parses into 11 steps")
	check(co.song_label.text == "Howl's Moving Castle", "BrandingCard syncs song title from sheet metadata")
	
	# Step 0: [@(YD]
	check(co.get_current_token() == "[@(YD]", "Step 0 displays exact token [@(YD] (got: %s)" % co.get_current_token())
	check(co.next_labels[0].text == "[%WOH]" and co.next_labels[1].text == "[7rak]" and co.next_labels[2].text == "3", "Next steps preview shows [%WOH], [7rak], 3")
	
	# Advance to step 3: "3"
	app.step_index = 3
	app._refresh_progress()
	check(co.get_current_token() == "3", "Step 3 displays single-note token '3'")
	check(co.prev_labels[0].text == "[@(YD]" and co.prev_labels[1].text == "[%WOH]" and co.prev_labels[2].text == "[7rak]", "Previous 3 steps window shows [@(YD], [%WOH], [7rak]")
	
	# Advance to step 8: [5^h]
	app.step_index = 8
	app._refresh_progress()
	check(co.get_current_token() == "[5^h]", "Step 8 displays exact token [5^h] (got: %s)" % co.get_current_token())
	check(co.next_labels[0].text == "[R]" and co.next_labels[1].text == "[Sqet]", "Steps 9 and 10 preview shows [R] and [Sqet]")
	
	# Advance to step 9: [R]
	app.step_index = 9
	app._refresh_progress()
	check(co.get_current_token() == "[R]", "Step 9 displays exact token [R] (got: %s)" % co.get_current_token())
	
	# Advance to step 10: [Sqet]
	app.step_index = 10
	app._refresh_progress()
	check(co.get_current_token() == "[Sqet]", "Step 10 displays exact token [Sqet] (got: %s)" % co.get_current_token())

	# Test long song title layout overlap prevention
	co.set_song_title("Touhou - Death WaltzLast Brutal Sister Flandre S UNTRANSPOSED")
	co.arrange(app.size, app.menu.menu_height, false)
	await process_frame
	check(co.branding_card.size.x <= 340.0, "BrandingCard width is capped to 340px max on long song titles (got: %f)" % co.branding_card.size.x)
	check(co.branding_card.size.x >= 220.0, "BrandingCard width is at least 220px to prevent text collapse (got: %f)" % co.branding_card.size.x)
	check(co.channel_label.size.x > 50.0, "ChannelLabel text has visible non-zero width (got: %f)" % co.channel_label.size.x)
	check(co.song_label.visible and co.song_label.size.x > 50.0, "SongLabel text has visible non-zero width (got: %f)" % co.song_label.size.x)
	check(co.hud_target_pos.x >= co.branding_target_pos.x + co.branding_card.size.x + 10.0, "LiveSheetHUD does not overlap BrandingCard with long song title")

	# 3. Verify global shortcuts Ctrl+B, Ctrl+H, Ctrl+Y, Ctrl+K do NOT trigger any musical notes
	app.audio.stop_all()
	for s in app.sources.keys():
		app._release_source(s)
	var serial_before = app.serial
	
	# Test both with auto_enabled = false and auto_enabled = true
	for auto_state in [false, true]:
		app.auto_enabled = auto_state
		var step_before = app.step_index
		
		# Ctrl + B -> toggles BrandingCard
		var b_initial = co.branding_enabled
		send_key(app, KEY_B, true, true)
		send_key(app, KEY_B, false, true)
		check(co.branding_enabled == (not b_initial) and co.branding_card.visible == co.branding_enabled, "Ctrl+B toggles BrandingCard (auto=%s)" % str(auto_state))
		send_key(app, KEY_B, true, true)
		send_key(app, KEY_B, false, true)
		check(co.branding_enabled == b_initial, "Second Ctrl+B restores BrandingCard")
		
		# Ctrl + H -> toggles LiveSheetHUD
		var h_initial = co.hud_enabled
		send_key(app, KEY_H, true, true)
		send_key(app, KEY_H, false, true)
		check(co.hud_enabled == (not h_initial) and co.hud_panel.visible == co.hud_enabled, "Ctrl+H toggles LiveSheetHUD (auto=%s)" % str(auto_state))
		send_key(app, KEY_H, true, true)
		send_key(app, KEY_H, false, true)
		check(co.hud_enabled == h_initial, "Second Ctrl+H restores LiveSheetHUD")
		
		# Ctrl + Y -> toggles ShortsFrameMode (9:16)
		var y_initial = app.shorts_mode
		send_key(app, KEY_Y, true, true)
		send_key(app, KEY_Y, false, true)
		check(app.shorts_mode == (not y_initial) and co.shorts_mode == app.shorts_mode, "Ctrl+Y toggles ShortsFrameMode (auto=%s)" % str(auto_state))
		send_key(app, KEY_Y, true, true)
		send_key(app, KEY_Y, false, true)
		check(app.shorts_mode == y_initial, "Second Ctrl+Y restores ShortsFrameMode")
		
		# Ctrl + K -> cycles keyboard zoom (full_88 -> central_61 -> full_88)
		check(app.key_range_mode == "full_88", "Starts in full_88 mode")
		send_key(app, KEY_K, true, true)
		send_key(app, KEY_K, false, true)
		check(app.key_range_mode == "central_61" and app.keyboard.visible_midi_range == Vector2i(36, 96), "Ctrl+K switches to central_61 (MIDI 36..96)")
		send_key(app, KEY_K, true, true)
		send_key(app, KEY_K, false, true)
		check(app.key_range_mode == "full_88" and app.keyboard.visible_midi_range == Vector2i(21, 108), "Second Ctrl+K returns to full_88 (MIDI 21..108)")
		
		# Ctrl + M -> toggles KPS & Combo HUD
		var m_initial = co.kps_hud_enabled
		send_key(app, KEY_M, true, true)
		send_key(app, KEY_M, false, true)
		check(co.kps_hud_enabled == (not m_initial) and co.kps_card.visible == co.kps_hud_enabled, "Ctrl+M toggles KPS & Combo HUD (auto=%s)" % str(auto_state))
		send_key(app, KEY_M, true, true)
		send_key(app, KEY_M, false, true)
		check(co.kps_hud_enabled == m_initial, "Second Ctrl+M restores KPS & Combo HUD")
		
		check(app.serial == serial_before and app.audio.voices.is_empty() and app.sources.is_empty(), "Zero notes triggered in audio_engine during Ctrl+B/H/Y/K/M shortcuts (auto=%s)" % str(auto_state))
		check(app.step_index == step_before, "Step index unchanged during Ctrl shortcuts (auto=%s)" % str(auto_state))

	app.auto_enabled = false

	# 4. Verify X coordinate and width alignment between synth_visualizer.gd bars and piano_keyboard_renderer.gd keys across zoom modes & shorts_mode
	var test_midis = [48, 60, 61, 72, 84, 96]
	for s_mode in [false, true]:
		app.set_shorts_mode(s_mode)
		for z_mode in ["full_88", "central_61", "melodic_49"]:
			app.set_key_range_mode(z_mode)
			app._press_source("align-test", test_midis)
			app.visualizer._update_bars()
			for m in test_midis:
				check(app.keyboard.key_rects.has(m), "Keyboard has key_rect for MIDI %d in mode %s (shorts=%s)" % [m, z_mode, str(s_mode)])
				var k_rect: Rect2 = app.keyboard.key_rects[m]
				var matched_bar = false
				for bar in app.visualizer.bars.values():
					if bar.midi == m:
						var b_rect: Rect2 = app.visualizer.bar_rect(bar)
						check(is_equal_approx(b_rect.position.x, k_rect.position.x) and is_equal_approx(b_rect.size.x, k_rect.size.x), "Bar X (%.2f, w=%.2f) matches Key X (%.2f, w=%.2f) for MIDI %d in %s (shorts=%s)" % [b_rect.position.x, b_rect.size.x, k_rect.position.x, k_rect.size.x, m, z_mode, str(s_mode)])
						matched_bar = true
				check(matched_bar, "Active bar found for MIDI %d" % m)
			if s_mode:
				var sr = co.get_shorts_rect(app.size)
				var expected_w = app.size.y * (9.0 / 16.0)
				check(is_equal_approx(sr.size.x, expected_w), "Shorts 9:16 width is size.y * 9/16")
				check(co.branding_target_pos.x >= sr.position.x and co.branding_target_pos.x + co.branding_card.size.x <= sr.end.x, "BrandingCard relocated inside 9:16 shorts_rect")
				check(co.hud_target_pos.x >= sr.position.x and co.hud_target_pos.x + co.hud_panel.size.x <= sr.end.x, "LiveSheetHUD relocated inside 9:16 shorts_rect")
			app._release_source("align-test")
			app.visualizer.bars.clear()
			app.visualizer.released.clear()

	# Restore default full_88 and shorts_mode = false
	app.set_shorts_mode(false)
	app.set_key_range_mode("full_88")
	check(app.keyboard.key_rects.size() == 88, "Restored full 88 keys")

	# 5. Verify LineEdit focus in studio_menu blocks musical note triggering and releases on Escape
	app.menu.show_section("appearance", false)
	app.popup.show()
	app.menu.channel_field.grab_focus()
	await process_frame
	check(app.menu.editing_input(), "Focused channel_field sets menu.editing_input() to true")
	var voices_before = app.audio.voices.size()
	send_key(app, KEY_Q, true)
	send_key(app, KEY_Q, false)
	check(app.audio.voices.size() == voices_before and app.sources.is_empty(), "Typing in channel_field does not trigger musical notes")
	send_key(app, KEY_ESCAPE, true)
	send_key(app, KEY_ESCAPE, false)
	check(not app.menu.channel_field.has_focus(), "Escape releases channel_field focus")

	# 6. Verify KPS & Combo HUD (> 8 KPS fire color & 1.8s combo timeout)
	co.kps_timestamps.clear()
	co.combo_count = 0
	co.combo_idle_sec = 0.0
	co.on_note_triggered([60, 64, 67, 72, 76, 79, 84, 88, 91]) # 9 notes in < 1000ms
	check(co.current_kps == 9 and co.combo_count == 9, "KPS & Combo count 9 notes accurately")
	check(co.kps_value_label.get_theme_color("font_color").is_equal_approx(co.FIRE_COLOR), "KPS > 8 switches KPS label to warm fire color")
	co.advance_combo_idle(1.9)
	check(co.combo_count == 0 and co.combo_value_label.text == "0x", "Combo resets to 0 after > 1.8s without notes")

	# 7. Verify Dynamic Camera Shake (Camera2D, trauma, heavy chords & bass notes)
	check(app.camera != null and app.camera is Camera2D and app.camera.anchor_mode == Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT, "StageCamera Camera2D present with ANCHOR_MODE_FIXED_TOP_LEFT")
	check(app.camera_shake_enabled == false and is_zero_approx(app.trauma), "Camera shake OFF by default")
	app._press_source("shake-off-test", [36, 48, 60, 64])
	app._release_source("shake-off-test")
	check(is_zero_approx(app.trauma) and app.camera.offset == Vector2.ZERO, "No trauma added when camera_shake_enabled is false")
	app.set_camera_shake_enabled(true)
	app._press_source("shake-chord-test", [48, 55, 60, 64])
	app._release_source("shake-chord-test")
	check(app.trauma >= 0.39 and app.camera.offset != Vector2.ZERO, "4-note heavy chord adds trauma and offsets Camera2D")
	app._process(1.0)
	check(is_zero_approx(app.trauma) and app.camera.offset == Vector2.ZERO, "Camera trauma decays to 0 and resets offset")
	app._press_source("shake-bass-test", [36]) # MIDI 36 < 45 with velocity 108
	app._release_source("shake-bass-test")
	check(app.trauma >= 0.39, "Deep bass note (MIDI < 45) triggers camera trauma")
	app.set_camera_shake_enabled(false)
	check(is_zero_approx(app.trauma) and app.camera.offset == Vector2.ZERO, "Disabling camera shake clears trauma and offset")

	# 8. Verify Internal Studio .WAV Audio Recorder (Ctrl + R & user://recordings/)
	check(app.audio.record_effect != null and app.audio.record_effect is AudioEffectRecord, "AudioEffectRecord present on Master bus")
	var serial_rec = app.serial
	send_key(app, KEY_R, true, true)
	send_key(app, KEY_R, false, true)
	check(app.audio.is_recording == true and co.is_recording == true and co.rec_badge.visible == true, "Ctrl+R starts .WAV recording and shows ● REC badge")
	check(app.serial == serial_rec and app.sources.is_empty(), "Ctrl+R does not trigger musical notes")
	send_key(app, KEY_R, true, true)
	send_key(app, KEY_R, false, true)
	check(app.audio.is_recording == false and co.is_recording == false and co.rec_badge.visible == false, "Second Ctrl+R stops recording and hides ● REC badge")
	check(app.audio.last_recording_path.begins_with("user://recordings/SwiftPiano_REC_") and app.audio.last_recording_path.ends_with(".wav"), "Saved .WAV path follows user://recordings/SwiftPiano_REC_*.wav format")
	check(FileAccess.file_exists(app.audio.last_recording_path), "Recorded .WAV file exists on disk in user://recordings/")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(app.audio.last_recording_path))

	# 9. Verify Custom Backgrounds (WallpaperRect TextureRect & VideoLoopPlayer VideoStreamPlayer)
	check(app.wallpaper_rect != null and app.wallpaper_rect is TextureRect and app.wallpaper_rect.expand_mode == TextureRect.EXPAND_IGNORE_SIZE, "WallpaperRect TextureRect configured with EXPAND_IGNORE_SIZE")
	check(app.video_bg_player != null and app.video_bg_player is VideoStreamPlayer and app.video_bg_player.expand == true, "VideoLoopPlayer VideoStreamPlayer configured with expand=true")
	check(app.menu.bg_image_btn != null and app.menu.bg_video_btn != null and app.menu.bg_clear_btn != null, "Custom background buttons present in studio_menu")
	var test_img_path = "user://test_wallpaper.png"
	var test_img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	test_img.fill(Color(0.2, 0.5, 0.9, 1.0))
	test_img.save_png(test_img_path)
	check(app.load_custom_wallpaper(ProjectSettings.globalize_path(test_img_path)), "load_custom_wallpaper loads PNG image")
	check(app.wallpaper_rect.visible == true and app.wallpaper_rect.texture != null, "WallpaperRect visible with loaded texture")
	app.clear_custom_background()
	check(app.wallpaper_rect.visible == false and app.wallpaper_rect.texture == null, "clear_custom_background hides WallpaperRect")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_img_path))

	# 10. Verify Bot Showcase (Auto-Play at Real Tempo, Ctrl + P & bot_bpm)
	app._reset_auto()
	check(app.bot_enabled == false and app.step_index == 0, "Bot starts disabled at step 0")
	var serial_bot_before = app.serial
	app.set_bot_bpm(240.0) # 0.125s per step
	send_key(app, KEY_P, true, true)
	send_key(app, KEY_P, false, true)
	check(app.bot_enabled == true and app.step_index == 1 and app.serial > serial_bot_before, "Ctrl+P activates Bot Showcase and plays first step immediately")
	app._process(0.14)
	check(app.step_index == 2, "Bot Showcase advances step_index automatically in _process based on bot_bpm")
	send_key(app, KEY_P, true, true)
	send_key(app, KEY_P, false, true)
	check(app.bot_enabled == false and not app.sources.has("bot"), "Second Ctrl+P pauses Bot Showcase and releases bot notes")
	
	# Test Bot Showcase completion with auto_loop_enabled == false vs true
	check(app.menu.auto_loop_btn != null, "auto_loop_btn present in studio_menu")
	check(app.auto_loop_enabled == true, "auto_loop_enabled is true by default (classic loop)")
	check(app.menu.auto_loop_btn.text.contains("En bucle"), "auto_loop_btn displays 'En bucle' by default")
	
	# Toggle auto_loop_btn to false (Mantener final)
	app.menu.auto_loop_btn.pressed.emit()
	check(app.auto_loop_enabled == false, "Clicking auto_loop_btn switches to Mantener final (false)")
	check(app.menu.auto_loop_btn.text.contains("Mantener final"), "auto_loop_btn displays 'Mantener final' when false")

	# Bot mode completion with auto_loop_enabled == false
	app.step_index = app.steps.size() - 1
	app.bot_enabled = true
	app._bot_elapsed = app._bot_current_delay + 0.01
	app._process(0.01)
	check(app.bot_enabled == false, "Bot finishes and stops automatically at last step when auto_loop_enabled is false")
	check(app.step_index == app.steps.size() - 1, "Bot holds at last step index when auto_loop_enabled is false")
	check(co.get_current_token() == "[Sqet]", "Sheet HUD retains last token [Sqet] when song finishes")
	check(app.next_step.text.contains("Fin de canción"), "Next step label indicates song completion")

	# Interactive Auto mode note advancement with auto_loop_enabled == false
	app.auto_enabled = true
	app.step_index = app.steps.size() - 1
	send_key(app, KEY_1, true)
	send_key(app, KEY_1, false)
	check(app.step_index == app.steps.size() - 1, "Auto mode note play holds at last step when auto_loop_enabled is false")
	check(co.get_current_token() == "[Sqet]", "Sheet HUD maintains last step lyrics/token on subsequent note keys")
	
	# Toggle auto_loop_btn back to true
	app.menu.auto_loop_btn.pressed.emit()
	check(app.auto_loop_enabled == true, "Clicking auto_loop_btn enables auto_loop_enabled")
	check(app.menu.auto_loop_btn.text.contains("En bucle"), "auto_loop_btn displays 'En bucle' when active")
	
	# Interactive Auto mode note advancement with auto_loop_enabled == true
	send_key(app, KEY_1, true)
	send_key(app, KEY_1, false)
	check(app.step_index == 0, "Auto mode wraps back to step 0 when auto_loop_enabled is true")
	check(co.get_current_token() == "[@(YD]", "Sheet HUD wraps to step 0 token when loop is enabled")

	# Restore auto_loop_enabled to true and auto_enabled to false
	app.set_auto_loop_enabled(true)
	app.auto_enabled = false
	app.set_bot_bpm(120.0)

	# 11. Verify Color & Studio Settings Persistence (save_user_settings / load_user_settings)
	var test_cfg_path = "user://test_studio_settings.cfg"
	var custom_color = Color("#f2409e")
	app._set_appearance(custom_color, true, "aurora")
	app._change_bar_style("ember_particles")
	app.set_branding_config(true, "top_right")
	app.set_hud_config(true, "above_piano")
	app.set_shorts_mode(true)
	app.set_key_range_mode("central_61")
	app.set_kps_hud_enabled(false)
	app.set_camera_shake_enabled(true)
	app.set_bot_bpm(155.0)
	app.set_creator_texts("@TestCreator", "Custom Persistent Subtitle")
	app.set_auto_loop_enabled(false)
	app._set_volume(45.0)
	app.save_user_settings(test_cfg_path)
	check(FileAccess.file_exists(test_cfg_path), "Settings config file saved to user://")

	# Reset values to defaults in memory, then reload from config file
	app._set_appearance(Color("#64e8d0"), false, "supernova")
	app._change_bar_style("laser_crystal")
	app.set_branding_config(true, "top_left")
	app.set_hud_config(true, "top_center")
	app.set_shorts_mode(false)
	app.set_key_range_mode("full_88")
	app.set_kps_hud_enabled(true)
	app.set_camera_shake_enabled(false)
	app.set_bot_bpm(120.0)
	app.set_creator_texts("@DragonCxbas", "Virtual Piano Sheet in Description")
	app.set_auto_loop_enabled(true)
	app._set_volume(100.0)

	app.load_user_settings(test_cfg_path)
	check(is_equal_approx(app.volume_slider.value, 45.0), "Persisted volume restored to 45%")
	check(app.volume_label.text == "45%", "Persisted volume label restored")
	check(co.wave_badge != null and co.wave_badge.get_parent() == co.accent_pill, "LiveWaveBadge present and attached to accent_pill")
	check(co.branding_style.border_color.a <= 0.35, "Branding card uses subtle liquid glass rim")
	check(app.active_color.is_equal_approx(custom_color), "Persisted active_color restored accurately")
	check(app.menu.chosen_color.is_equal_approx(custom_color), "Menu ColorPickerButton synced with persisted active_color")
	check(app.rainbow == true and app.menu.rainbow_toggle.button_pressed == true, "Persisted rainbow mode restored and synced with menu")
	check(app.visualizer.bar_style == "ember_particles" and app.menu.current_bar_style == "ember_particles", "Persisted bar_style restored and synced with menu")
	check(app.current_light_mode == "aurora" and app.menu.current_light_mode == "aurora", "Persisted light_mode restored and synced with menu")
	check(co.branding_position == "top_right", "Persisted branding_position restored")
	check(co.hud_position == "above_piano", "Persisted hud_position restored")
	check(app.shorts_mode == true, "Persisted shorts_mode restored")
	check(app.key_range_mode == "central_61", "Persisted key_range_mode restored")
	check(app.kps_hud_enabled == false and co.kps_hud_enabled == false, "Persisted kps_hud_enabled restored")
	check(app.camera_shake_enabled == true, "Persisted camera_shake_enabled restored")
	check(is_equal_approx(app.bot_bpm, 155.0), "Persisted bot_bpm restored")
	check(co.channel_text == "@TestCreator" and app.menu.channel_field.text == "@TestCreator", "Persisted channel_text restored")
	check(app.auto_loop_enabled == false and app.menu.current_auto_loop == false, "Persisted auto_loop_enabled (false) restored")
	# 8. Verify editable song_title and song_field two-way synchronization
	check(app.menu.song_title is LineEdit, "Top bar song_title is an interactive LineEdit")
	check(app.menu.song_field is LineEdit, "Creator drawer song_field is an interactive LineEdit")
	
	# Edit from top bar song_title
	app.menu.song_title.text = "Custom Sonata in C Major"
	app.menu.song_title.text_changed.emit("Custom Sonata in C Major")
	check(app.menu.song_field.text == "Custom Sonata in C Major", "Editing song_title syncs to song_field")
	check(app.user_custom_title == "Custom Sonata in C Major", "Editing song_title sets user_custom_title")
	check(co.song_text == "Custom Sonata in C Major", "Editing song_title updates Creator watermark overlay")
	
	# Edit from creator drawer song_field
	app.menu.song_field.text = "Fairy Fountain Fantasy"
	app.menu.song_field.text_changed.emit("Fairy Fountain Fantasy")
	check(app.menu.song_title.text == "Fairy Fountain Fantasy", "Editing song_field syncs to top bar song_title")
	check(app.user_custom_title == "Fairy Fountain Fantasy", "Editing song_field sets user_custom_title")
	check(co.song_text == "Fairy Fountain Fantasy", "Editing song_field updates Creator watermark overlay")
	
	# Verify editing_input prevents keyboard note interception
	app.menu.song_title.grab_focus()
	check(app.menu.editing_input() == true, "editing_input() is true when song_title has focus")
	app.menu.release_creator_focus()
	check(not app.menu.song_title.has_focus() and not app.menu.song_field.has_focus(), "release_creator_focus() drops focus from song title inputs")
	
	# Verify ExportSheet adopts sanitized custom title as filename
	app._menu_action("ExportSheet")
	check(app.export_dialog.current_file == "Fairy Fountain Fantasy.txt", "ExportSheet suggests custom title filename")
	app.export_dialog.hide()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_cfg_path))

	app.audio.stop_all()
	await create_timer(0.15).timeout
	app.queue_free()
	await process_frame
	await process_frame
	await process_frame
	print("CREATOR STUDIO CHECKS: %d; FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
