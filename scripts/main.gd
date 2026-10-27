# SwiftPiano
# Copyright (c) 2026 Sebastián Zambrano
# Distributed under the terms of the MIT License.

extends Control
const StudioMenu = preload("res://scripts/studio_menu.gd")
const MusicLibrary = preload("res://scripts/music_library.gd")
const Keymap = preload("res://scripts/keymap_data.gd")
const AudioEngine = preload("res://scripts/audio_engine.gd")
const Visualizer = preload("res://scripts/synth_visualizer.gd")
const Keyboard = preload("res://scripts/piano_keyboard_renderer.gd")
const Parser = preload("res://scripts/sheet_parser.gd")
const MidiImporter = preload("res://scripts/midi_importer.gd")
const CreatorOverlay = preload("res://scripts/creator_overlay.gd")
var midi_dialog: FileDialog
var export_dialog: FileDialog
var image_bg_dialog: FileDialog
var video_bg_dialog: FileDialog
var midi_notice: AcceptDialog

var menu: Panel
var creator_overlay: Control
var camera: Camera2D
var base_stage_bg: ColorRect
var wallpaper_rect: TextureRect
var video_bg_player: VideoStreamPlayer
var bg_opacity: float = 0.4
var custom_bg_image_path: String = ""
var custom_bg_video_path: String = ""
var library = MusicLibrary.new()
var library_sheet = false
var selected_song = "custom"
var drafts: Dictionary = {}
var active_color = Color("#64e8d0")
var rainbow = false
var rhythm_flashes = false
var current_light_mode = "supernova"
var qwerty_enabled = true
var auto_enabled = false
var sustain_enabled = true
var transposition = 0
var velocity = 108
var synth_enabled = true
var space_held = false
var zen_mode: bool = false
var shorts_mode: bool = false
var key_range_mode: String = "full_88"
var kps_hud_enabled: bool = true
var camera_shake_enabled: bool = false
var trauma: float = 0.0
var max_shake_offset: Vector2 = Vector2(14.0, 10.0)
var _recent_shake_notes: Array[int] = []
var bot_enabled: bool = false
var bot_bpm: float = 120.0
var _bot_elapsed: float = 0.0
var _bot_current_delay: float = 0.25
var _bot_note_released: bool = false
var step_delays: Array[float] = []
var audio: Node
var visualizer: Control
var keyboard: Control
var panel: Panel
var ui_layer: CanvasLayer
var popup: Panel
var sheet_text_edit: TextEdit
var volume_slider: HSlider
var volume_label: Label
var next_step: Label
var progress: ProgressBar
var compiled_text = ""
var step_labels: Array[String] = []
var counter: Label
var buttons: Dictionary = {}
var popup_buttons: Dictionary = {}
var indicators: Dictionary = {}
var sources: Dictionary = {}
var pressed: Dictionary = {}
var steps: Array[Dictionary] = []
var step_index = 0
var serial = 0
var dirty_sheet = false
var shutting_down = false
var _midi_dialog_target: String = ""
const SETTINGS_PATH = "user://studio_settings.cfg"
var settings_path: String = SETTINGS_PATH
var _loading_settings: bool = false

func _ready() -> void:
	Engine.max_fps = 60
	get_tree().auto_accept_quit = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if "use_hdr_2d" in get_viewport():
		get_viewport().use_hdr_2d = true
	camera = get_node_or_null("StageCamera") as Camera2D
	if camera == null:
		camera = Camera2D.new()
		camera.name = "StageCamera"
		camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		add_child(camera)
	else:
		camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	base_stage_bg = get_node_or_null("BaseStageBg") as ColorRect
	if base_stage_bg == null:
		base_stage_bg = ColorRect.new()
		base_stage_bg.name = "BaseStageBg"
		base_stage_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		base_stage_bg.color = Color(0.02, 0.027, 0.047, 1.0)
		base_stage_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(base_stage_bg)
	wallpaper_rect = get_node_or_null("WallpaperRect") as TextureRect
	if wallpaper_rect == null:
		wallpaper_rect = TextureRect.new()
		wallpaper_rect.name = "WallpaperRect"
		wallpaper_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wallpaper_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wallpaper_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		wallpaper_rect.modulate = Color(1.0, 1.0, 1.0, bg_opacity)
		wallpaper_rect.visible = false
		wallpaper_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(wallpaper_rect)
	video_bg_player = get_node_or_null("VideoLoopPlayer") as VideoStreamPlayer
	if video_bg_player == null:
		video_bg_player = VideoStreamPlayer.new()
		video_bg_player.name = "VideoLoopPlayer"
		video_bg_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
		video_bg_player.expand = true
		video_bg_player.modulate = Color(1.0, 1.0, 1.0, bg_opacity)
		video_bg_player.visible = false
		video_bg_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(video_bg_player)
	if "loop" in video_bg_player:
		video_bg_player.loop = true
	video_bg_player.finished.connect(func():
		if video_bg_player != null and video_bg_player.visible and video_bg_player.stream != null:
			video_bg_player.play())
	var world = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.background_canvas_max_layer = 0
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.glow_enabled = true
	environment.glow_normalized = false
	environment.glow_intensity = 0.72
	environment.glow_strength = 0.88
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.0
	environment.glow_hdr_luminance_cap = 2.2
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.set_glow_level(0, 0.0)
	environment.set_glow_level(1, 1.0)
	environment.set_glow_level(2, 1.0)
	environment.set_glow_level(3, 0.7)
	environment.set_glow_level(4, 0.5)
	environment.set_glow_level(5, 0.0)
	environment.set_glow_level(6, 0.0)
	world.environment = environment
	add_child(world)
	visualizer = Visualizer.new()
	add_child(visualizer)
	# Composite controls after the world glow: white keys and UI keep their
	# exact colors and only the synth bars contribute to bloom.
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 1
	add_child(ui_layer)
	keyboard = Keyboard.new()
	ui_layer.add_child(keyboard)
	keyboard.mouse_note_changed.connect(_mouse_note)
	creator_overlay = CreatorOverlay.new()
	creator_overlay.main_ref = self
	ui_layer.add_child(creator_overlay)
	_build_ui()
	resized.connect(_layout)
	_layout()
	_compile_sheet()
	_refresh()
	audio = AudioEngine.new()
	add_child(audio)
	_sync_sustain()
	_set_volume(volume_slider.value)
	if menu != null:
		menu.set_active_instrument(audio.get_current_instrument_id())
		if selected_song == "custom":
			menu.song_title.text = "%s  /  88 Teclas" % audio.get_current_instrument_name()
	if DisplayServer.get_name() != "headless":
		load_user_settings(settings_path)
	_sync_creator_song_title()

func _process(delta: float) -> void:
	if trauma > 0.0:
		trauma = maxf(trauma - delta * 1.5, 0.0)
		if camera != null:
			if trauma > 0.0 and camera_shake_enabled:
				var shake = trauma * trauma
				camera.offset = Vector2(randf_range(-1.0, 1.0) * max_shake_offset.x, randf_range(-1.0, 1.0) * max_shake_offset.y) * shake
			else:
				camera.offset = Vector2.ZERO
	elif camera != null and camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO
	
	if bot_enabled:
		if steps.is_empty():
			set_bot_enabled(false)
		else:
			_bot_elapsed += delta
			if not _bot_note_released and _bot_elapsed >= _bot_current_delay * 0.82:
				_release_source("bot")
				_bot_note_released = true
			while bot_enabled and not steps.is_empty() and _bot_elapsed >= _bot_current_delay:
				_bot_elapsed -= _bot_current_delay
				_trigger_bot_step()

func _build_ui() -> void:
	menu = StudioMenu.new()
	ui_layer.add_child(menu)
	menu.build(library)
	panel = menu
	popup = menu.drawer
	buttons = menu.buttons
	popup_buttons = menu.popup_buttons
	indicators = menu.indicators
	sheet_text_edit = menu.sheet_text_edit
	sheet_text_edit.text = Keymap.DEMO
	sheet_text_edit.text_changed.connect(func(): dirty_sheet = true)
	volume_slider = menu.volume_slider
	volume_label = menu.volume_label
	counter = menu.counter
	next_step = menu.next_step
	progress = menu.progress
	menu.action.connect(_menu_action)
	menu.volume_changed.connect(_set_volume)
	menu.song_requested.connect(_load_song)
	menu.appearance_changed.connect(_set_appearance)
	menu.instrument_changed.connect(_change_instrument)
	menu.bar_style_changed.connect(_change_bar_style)
	menu.reverb_preset_changed.connect(_change_reverb_preset)
	menu.creator_zen_requested.connect(func(): set_zen_mode(true))
	menu.creator_branding_changed.connect(set_branding_config)
	menu.creator_hud_changed.connect(set_hud_config)
	menu.creator_shorts_toggled.connect(set_shorts_mode)
	menu.creator_key_range_changed.connect(set_key_range_mode)
	menu.creator_text_changed.connect(set_creator_texts)
	menu.creator_kps_toggled.connect(set_kps_hud_enabled)
	menu.creator_shake_toggled.connect(set_camera_shake_enabled)
	menu.creator_rec_toggled.connect(toggle_audio_recording)
	menu.creator_bot_toggled.connect(set_bot_enabled)
	menu.creator_bot_bpm_changed.connect(set_bot_bpm)
	menu.creator_bg_image_requested.connect(_open_bg_image_dialog)
	menu.creator_bg_video_requested.connect(_open_bg_video_dialog)
	menu.creator_bg_clear_requested.connect(clear_custom_background)
	menu.creator_bg_opacity_changed.connect(set_background_opacity)
	keyboard.active_color = active_color
	_build_file_dialogs()

func _build_file_dialogs() -> void:
	menu.converter.apply_requested.connect(_apply_conversion)
	midi_dialog = FileDialog.new()
	midi_dialog.title = "Importar MIDI como hoja"
	midi_dialog.access = FileDialog.ACCESS_FILESYSTEM
	midi_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	midi_dialog.filters = PackedStringArray(["*.mid,*.midi ; Archivos MIDI"])
	add_child(midi_dialog)
	midi_dialog.file_selected.connect(func(path):
		var target = _midi_dialog_target if not _midi_dialog_target.is_empty() else ("conversion" if menu.section == "conversion" else "import")
		_midi_dialog_target = ""
		if target == "conversion":
			var result = MidiImporter.new().import_file(path)
			if result.error.is_empty():
				menu.converter.load_result(result, path)
			else:
				midi_notice.dialog_text = result.error + "\nLa hoja y la vista previa se conservan."
				midi_notice.popup_centered(Vector2i(480, 180))
		else:
			_import_midi(path))
	export_dialog = FileDialog.new()
	export_dialog.title = "Guardar hoja de SwiftPiano"
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.filters = PackedStringArray(["*.txt ; Hoja de SwiftPiano"])
	add_child(export_dialog)
	export_dialog.file_selected.connect(_export_sheet)
	image_bg_dialog = FileDialog.new()
	image_bg_dialog.title = "Cargar Imagen de Fondo"
	image_bg_dialog.access = FileDialog.ACCESS_FILESYSTEM
	image_bg_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	image_bg_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Imágenes"])
	add_child(image_bg_dialog)
	image_bg_dialog.file_selected.connect(load_custom_wallpaper)
	video_bg_dialog = FileDialog.new()
	video_bg_dialog.title = "Cargar Video de Fondo (Loop)"
	video_bg_dialog.access = FileDialog.ACCESS_FILESYSTEM
	video_bg_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	video_bg_dialog.filters = PackedStringArray(["*.ogv,*.webm ; Videos"])
	add_child(video_bg_dialog)
	video_bg_dialog.file_selected.connect(load_custom_video_loop)
	midi_notice = AcceptDialog.new()
	midi_notice.title = "Importación MIDI"
	add_child(midi_notice)

func _pause_for_file_dialog() -> void:
	set_bot_enabled(false)
	for source in sources.keys():
		_release_source(source)
	pressed.clear()
	space_held = false
	audio.stop_all()
	_sync_sustain()
	auto_enabled = false
	_refresh()

func _open_bg_image_dialog() -> void:
	_pause_for_file_dialog()
	image_bg_dialog.popup_centered_ratio(0.8)

func _open_bg_video_dialog() -> void:
	_pause_for_file_dialog()
	video_bg_dialog.popup_centered_ratio(0.8)

func load_custom_wallpaper(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return false
	var tex = ImageTexture.create_from_image(img)
	if tex == null:
		return false
	if video_bg_player != null:
		video_bg_player.stop()
		video_bg_player.stream = null
		video_bg_player.visible = false
	custom_bg_video_path = ""
	custom_bg_image_path = path
	if wallpaper_rect != null:
		wallpaper_rect.texture = tex
		wallpaper_rect.modulate = Color(1.0, 1.0, 1.0, bg_opacity)
		wallpaper_rect.visible = true
	if visualizer != null and visualizer.has_method("set_custom_background_active"):
		visualizer.set_custom_background_active(true)
	return true

func load_custom_video_loop(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var stream: VideoStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as VideoStream
	if stream == null and ClassDB.class_exists("VideoStreamTheora"):
		var theora = ClassDB.instantiate("VideoStreamTheora") as VideoStream
		if theora != null:
			theora.file = path
			stream = theora
	if stream == null:
		stream = VideoStream.new()
		stream.file = path
	if wallpaper_rect != null:
		wallpaper_rect.texture = null
		wallpaper_rect.visible = false
	custom_bg_image_path = ""
	custom_bg_video_path = path
	if video_bg_player != null:
		video_bg_player.stream = stream
		video_bg_player.modulate = Color(1.0, 1.0, 1.0, bg_opacity)
		video_bg_player.visible = true
		video_bg_player.play()
	if visualizer != null and visualizer.has_method("set_custom_background_active"):
		visualizer.set_custom_background_active(true)
	return true

func clear_custom_background() -> void:
	custom_bg_image_path = ""
	custom_bg_video_path = ""
	if wallpaper_rect != null:
		wallpaper_rect.texture = null
		wallpaper_rect.visible = false
	if video_bg_player != null:
		video_bg_player.stop()
		video_bg_player.stream = null
		video_bg_player.visible = false
	if visualizer != null and visualizer.has_method("set_custom_background_active"):
		visualizer.set_custom_background_active(false)

func set_background_opacity(opacity: float) -> void:
	bg_opacity = clampf(opacity, 0.05, 1.0)
	if wallpaper_rect != null:
		wallpaper_rect.modulate.a = bg_opacity
	if video_bg_player != null:
		video_bg_player.modulate.a = bg_opacity

func _import_midi(path: String) -> void:
	var result = MidiImporter.new().import_file(path)
	if not result.error.is_empty():
		midi_notice.dialog_text = result.error + "\nLa hoja actual se conserva."
		midi_notice.popup_centered(Vector2i(440, 160))
		return
	# Keep the previous draft until conversion has succeeded.
	drafts[selected_song] = sheet_text_edit.text
	_pause_for_file_dialog()
	selected_song = "midi:" + path
	library_sheet = false
	transposition = 0
	sheet_text_edit.text = result.sheet
	compiled_text = ""
	_compile_sheet()
	if result.has("delays") and result.delays is Array and result.delays.size() == steps.size():
		step_delays.clear()
		for d in result.delays:
			step_delays.append(float(d))
	menu.song_title.text = path.get_file().get_basename()
	menu.song_title.tooltip_text = path
	_sync_creator_song_title()
	menu.show_section("sheet", false)
	popup.show()
	_refresh()
	midi_notice.dialog_text = "%d pasos de %d pistas.\nPercusión omitida: %d · Fuera de A0–C8: %d\nActiva Auto y pulsa letras o números para avanzar.\nEl ritmo, la duración y el pedal los controlas tú.\nUsa Guardar hoja para conservar el resultado." % [result.steps, result.tracks, result.percussion, result.omitted]
	midi_notice.popup_centered(Vector2i(520, 220))

func _apply_conversion(text: String, title: String) -> void:
	drafts[selected_song] = sheet_text_edit.text
	_pause_for_file_dialog()
	selected_song = "conversion:" + title
	library_sheet = true
	transposition = 0
	sheet_text_edit.text = text
	compiled_text = ""
	_compile_sheet()
	menu.song_title.text = title
	menu.song_title.tooltip_text = "Hoja convertida desde MIDI"
	_sync_creator_song_title()
	menu.show_section("sheet", false)
	popup.show()
	_refresh()

func _export_sheet(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		midi_notice.dialog_text = "No se pudo guardar la hoja en esa ubicación."
	else:
		file.store_string(sheet_text_edit.text)
		file.flush()
		midi_notice.dialog_text = "Hoja guardada. Puedes volver a pegar su texto en el editor." if file.get_error() == OK else "No se pudo completar la escritura."
	midi_notice.popup_centered(Vector2i(480, 160))

func _layout() -> void:
	if keyboard == null or menu == null:
		return
	var top = size.y * 0.8
	if zen_mode:
		menu.hide()
		popup.hide()
		visualizer.position = Vector2.ZERO
		visualizer.size = Vector2(size.x, top)
	else:
		menu.show()
		menu.arrange(size, top)
		visualizer.position = Vector2(0, menu.menu_height)
		visualizer.size = Vector2(size.x, maxf(1, top - menu.menu_height))
	if base_stage_bg != null:
		base_stage_bg.position = visualizer.position
		base_stage_bg.size = visualizer.size
	if wallpaper_rect != null:
		wallpaper_rect.position = visualizer.position
		wallpaper_rect.size = visualizer.size
	if video_bg_player != null:
		video_bg_player.position = visualizer.position
		video_bg_player.size = visualizer.size
	if creator_overlay != null:
		creator_overlay.zen_mode = zen_mode
		creator_overlay.shorts_mode = shorts_mode
		creator_overlay.arrange(size, menu.menu_height, false)
	var h_bounds = Vector2.ZERO
	if shorts_mode and size.x > size.y and size.y > 0.0:
		var sr = creator_overlay.get_shorts_rect(size) if creator_overlay != null else Rect2((size.x - size.y * (9.0 / 16.0)) * 0.5, 0.0, size.y * (9.0 / 16.0), size.y)
		h_bounds = Vector2(sr.position.x, sr.size.x)
	keyboard.position = Vector2(0, top)
	keyboard.size = Vector2(size.x, size.y - top)
	keyboard.shorts_mode = shorts_mode
	keyboard.horizontal_bounds = h_bounds
	keyboard.rebuild()
	visualizer.visible_midi_range = keyboard.visible_midi_range
	visualizer.key_range_mode = keyboard.key_range_mode
	visualizer.shorts_mode = shorts_mode
	visualizer.horizontal_bounds = h_bounds
	visualizer.key_rects = keyboard.key_rects
	visualizer._update_bars()

func set_zen_mode(enabled: bool) -> void:
	var changed = (zen_mode != enabled)
	zen_mode = enabled
	if creator_overlay != null and changed:
		creator_overlay.set_zen_mode(zen_mode, menu.menu_height if menu != null else 112.0, true)
	_layout()

func set_branding_config(enabled: bool, pos: String = "") -> void:
	if creator_overlay != null:
		creator_overlay.set_branding_config(enabled, pos)
		if menu != null:
			menu.set_creator_branding(creator_overlay.branding_enabled, creator_overlay.branding_position, false)
	save_user_settings()

func toggle_branding_card() -> void:
	if creator_overlay != null:
		set_branding_config(not creator_overlay.branding_enabled, creator_overlay.branding_position)

func set_hud_config(enabled: bool, pos: String = "") -> void:
	if creator_overlay != null:
		creator_overlay.set_hud_config(enabled, pos)
		if menu != null:
			menu.set_creator_hud(creator_overlay.hud_enabled, creator_overlay.hud_position, false)
	save_user_settings()

func toggle_live_sheet_hud() -> void:
	if creator_overlay != null:
		set_hud_config(not creator_overlay.hud_enabled, creator_overlay.hud_position)

func set_shorts_mode(enabled: bool) -> void:
	shorts_mode = enabled
	if creator_overlay != null:
		creator_overlay.set_shorts_mode(shorts_mode)
	if menu != null:
		menu.set_creator_shorts(shorts_mode, false)
	_layout()
	save_user_settings()

func toggle_shorts_mode() -> void:
	set_shorts_mode(not shorts_mode)

func set_kps_hud_enabled(enabled: bool) -> void:
	kps_hud_enabled = enabled
	if creator_overlay != null:
		creator_overlay.set_kps_hud_enabled(kps_hud_enabled)
	if menu != null:
		menu.set_creator_kps(kps_hud_enabled, false)
	save_user_settings()

func toggle_kps_hud() -> void:
	set_kps_hud_enabled(not kps_hud_enabled)

func set_camera_shake_enabled(enabled: bool) -> void:
	camera_shake_enabled = enabled
	if not camera_shake_enabled:
		trauma = 0.0
		if camera != null:
			camera.offset = Vector2.ZERO
	if menu != null:
		menu.set_creator_shake(camera_shake_enabled, false)
	save_user_settings()

func toggle_camera_shake() -> void:
	set_camera_shake_enabled(not camera_shake_enabled)

func add_trauma(amount: float) -> void:
	if not camera_shake_enabled:
		return
	trauma = clampf(trauma + amount, 0.0, 1.0)
	if camera != null and trauma > 0.0:
		var shake = trauma * trauma
		var ox = randf_range(-1.0, 1.0) * max_shake_offset.x * shake
		var oy = randf_range(-1.0, 1.0) * max_shake_offset.y * shake
		if is_zero_approx(ox) and is_zero_approx(oy):
			ox = max_shake_offset.x * 0.5 * shake
		camera.offset = Vector2(ox, oy)

func toggle_audio_recording() -> bool:
	if audio == null:
		return false
	var active = audio.toggle_recording()
	if creator_overlay != null:
		creator_overlay.set_recording_state(active)
	if menu != null:
		menu.set_creator_recording(active)
	return active

func set_bot_bpm(bpm: float) -> void:
	bot_bpm = clampf(bpm, 30.0, 360.0)
	if menu != null:
		menu.set_creator_bot_bpm(bot_bpm, false)
	save_user_settings()

func _get_step_delay(idx: int) -> float:
	if idx >= 0 and idx < step_delays.size() and step_delays[idx] > 0.0:
		return clampf(step_delays[idx] * (120.0 / maxf(1.0, bot_bpm)), 0.03, 4.0)
	return clampf(60.0 / maxf(1.0, bot_bpm * 2.0), 0.04, 2.0)

func _trigger_bot_step() -> void:
	if steps.is_empty():
		set_bot_enabled(false)
		return
	_release_source("bot")
	var idx = clampi(step_index, 0, steps.size() - 1)
	var step = steps[idx]
	if step.transposition != null:
		transposition = step.transposition
	_bot_current_delay = _get_step_delay(idx)
	_bot_note_released = false
	_press_source("bot", step.notes)
	step_index = (idx + 1) % steps.size()
	_refresh_progress()

func set_bot_enabled(enabled: bool) -> void:
	var next_state = enabled and not steps.is_empty()
	if bot_enabled == next_state:
		if menu != null:
			menu.set_creator_bot(bot_enabled, false)
		return
	bot_enabled = next_state
	_bot_elapsed = 0.0
	if bot_enabled:
		_trigger_bot_step()
	else:
		_release_source("bot")
		_bot_note_released = true
	if menu != null:
		menu.set_creator_bot(bot_enabled, false)
	_refresh()

func toggle_bot_mode() -> void:
	set_bot_enabled(not bot_enabled)

func set_key_range_mode(mode: String) -> void:
	if keyboard != null:
		keyboard.set_key_range_mode(mode)
		key_range_mode = keyboard.key_range_mode
	else:
		key_range_mode = mode
	if visualizer != null:
		visualizer.set_key_range_mode(key_range_mode)
	if menu != null:
		menu.set_creator_key_range(key_range_mode, false)
	_layout()
	save_user_settings()

func cycle_key_range_mode() -> void:
	var next_mode = "central_61" if key_range_mode == "full_88" else "full_88"
	set_key_range_mode(next_mode)

func set_creator_texts(channel: String, subtitle: String) -> void:
	if creator_overlay != null:
		creator_overlay.set_channel_text(channel)
		creator_overlay.set_subtitle_text(subtitle)
	save_user_settings()

func save_user_settings(path: String = settings_path) -> void:
	if _loading_settings:
		return
	if path == SETTINGS_PATH and DisplayServer.get_name() == "headless":
		return
	var cfg = ConfigFile.new()
	cfg.set_value("appearance", "active_color", "#" + active_color.to_html(false))
	cfg.set_value("appearance", "rainbow", rainbow)
	cfg.set_value("appearance", "light_mode", current_light_mode)
	if visualizer != null:
		cfg.set_value("appearance", "bar_style", visualizer.bar_style)
	if audio != null:
		cfg.set_value("audio", "instrument", audio.get_current_instrument_id())
		cfg.set_value("audio", "reverb_preset", audio.current_reverb_preset)
	if creator_overlay != null:
		cfg.set_value("creator", "branding_enabled", creator_overlay.branding_enabled)
		cfg.set_value("creator", "branding_position", creator_overlay.branding_position)
		cfg.set_value("creator", "hud_enabled", creator_overlay.hud_enabled)
		cfg.set_value("creator", "hud_position", creator_overlay.hud_position)
		cfg.set_value("creator", "shorts_mode", shorts_mode)
		cfg.set_value("creator", "key_range_mode", key_range_mode)
		cfg.set_value("creator", "kps_hud_enabled", kps_hud_enabled)
		cfg.set_value("creator", "camera_shake_enabled", camera_shake_enabled)
		cfg.set_value("creator", "bot_bpm", bot_bpm)
		cfg.set_value("creator", "channel_text", creator_overlay.channel_text)
		cfg.set_value("creator", "subtitle_text", creator_overlay.subtitle_text)
	cfg.save(path)

func load_user_settings(path: String = settings_path) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var cfg = ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	_loading_settings = true
	var col_str = str(cfg.get_value("appearance", "active_color", "#" + active_color.to_html(false)))
	var saved_color = Color.from_string(col_str, active_color)
	var saved_rainbow = bool(cfg.get_value("appearance", "rainbow", rainbow))
	var saved_light = str(cfg.get_value("appearance", "light_mode", current_light_mode))
	var saved_bar = str(cfg.get_value("appearance", "bar_style", visualizer.bar_style if visualizer != null else "laser_crystal"))
	if menu != null:
		menu.apply_appearance_state(saved_color, saved_rainbow, saved_light)
		menu.set_active_bar_style(saved_bar)
	_set_appearance(saved_color, saved_rainbow, saved_light)
	_change_bar_style(saved_bar)
	if audio != null:
		var saved_inst = str(cfg.get_value("audio", "instrument", audio.get_current_instrument_id()))
		var saved_rev = str(cfg.get_value("audio", "reverb_preset", audio.current_reverb_preset))
		if menu != null:
			menu.set_active_instrument(saved_inst)
			menu.set_active_reverb_preset(saved_rev)
		_change_instrument(saved_inst)
		_change_reverb_preset(saved_rev)
	if creator_overlay != null:
		var b_en = bool(cfg.get_value("creator", "branding_enabled", creator_overlay.branding_enabled))
		var b_pos = str(cfg.get_value("creator", "branding_position", creator_overlay.branding_position))
		var h_en = bool(cfg.get_value("creator", "hud_enabled", creator_overlay.hud_enabled))
		var h_pos = str(cfg.get_value("creator", "hud_position", creator_overlay.hud_position))
		var s_mode = bool(cfg.get_value("creator", "shorts_mode", shorts_mode))
		var k_mode = str(cfg.get_value("creator", "key_range_mode", key_range_mode))
		var kps_en = bool(cfg.get_value("creator", "kps_hud_enabled", kps_hud_enabled))
		var shake_en = bool(cfg.get_value("creator", "camera_shake_enabled", camera_shake_enabled))
		var saved_bpm = float(cfg.get_value("creator", "bot_bpm", bot_bpm))
		var ch_txt = str(cfg.get_value("creator", "channel_text", creator_overlay.channel_text))
		var sub_txt = str(cfg.get_value("creator", "subtitle_text", creator_overlay.subtitle_text))
		set_branding_config(b_en, b_pos)
		set_hud_config(h_en, h_pos)
		set_shorts_mode(s_mode)
		set_key_range_mode(k_mode)
		set_kps_hud_enabled(kps_en)
		set_camera_shake_enabled(shake_en)
		set_bot_bpm(saved_bpm)
		set_creator_texts(ch_txt, sub_txt)
		if menu != null:
			if menu.channel_field != null:
				menu.channel_field.text = ch_txt
			if menu.subtitle_field != null:
				menu.subtitle_field.text = sub_txt
	_loading_settings = false
	return true

func _sync_creator_song_title() -> void:
	if creator_overlay == null:
		return
	if steps.is_empty():
		creator_overlay.set_song_title("Interpretación en Vivo")
		return
	var meta_re = RegEx.new()
	meta_re.compile("(?i)^(?:title|song|titulo|título|canción)\\s*:\\s*(.+)$")
	if sheet_text_edit != null:
		for raw_line in sheet_text_edit.text.split("\n"):
			var m = meta_re.search(raw_line.strip_edges())
			if m != null:
				creator_overlay.set_song_title(m.get_string(1).strip_edges())
				return
	if selected_song != "custom" and menu != null and not menu.song_title.text.strip_edges().is_empty():
		creator_overlay.set_song_title(menu.song_title.text)
	elif menu != null and not menu.song_title.text.ends_with("/  88 Teclas") and not menu.song_title.text.strip_edges().is_empty():
		creator_overlay.set_song_title(menu.song_title.text)
	else:
		creator_overlay.set_song_title("Interpretación en Vivo")

func _menu_action(id: String) -> void:
	_blur()
	menu.search_field.release_focus()
	menu.song_list.release_focus()
	menu.release_creator_focus()
	if id in ["ImportMidi", "ExportSheet", "ChooseConversionMidi"]:
		_pause_for_file_dialog()
		if id in ["ImportMidi", "ChooseConversionMidi"]:
			_midi_dialog_target = "conversion" if id == "ChooseConversionMidi" else "import"
			midi_dialog.popup_centered_ratio(0.8)
		else:
			export_dialog.current_file = "mi-hoja.txt"
			export_dialog.popup_centered_ratio(0.8)
		return
	if id in ["library", "sheet", "appearance", "conversion"]:
		if id == "conversion":
			_pause_for_file_dialog()
		menu.show_section(id)
	elif id == "auto":
		_popup_action("Auto")
	elif id == "sustain":
		_control("sustain", 1)
	else:
		_popup_action(id)

func _load_song(index: int) -> void:
	if index < 0 or index >= library.songs.size():
		return
	var song = library.songs[index]
	if not song.has_sheet:
		return
	menu.search_field.release_focus()
	menu.song_list.release_focus()
	menu.release_creator_focus()
	if not sheet_text_edit.text.strip_edges().is_empty():
		drafts[selected_song] = sheet_text_edit.text
	elif drafts.has(selected_song):
		drafts.erase(selected_song)
	for source in sources.keys():
		_release_source(source)
	audio.stop_all()
	auto_enabled = false
	selected_song = song.id
	library_sheet = true
	transposition = 0
	var draft_text = drafts.get(selected_song, "")
	if not draft_text.strip_edges().is_empty():
		sheet_text_edit.text = draft_text
	else:
		sheet_text_edit.text = song.sheet
	compiled_text = ""
	_compile_sheet()
	menu.song_title.text = song.title
	menu.song_title.tooltip_text = str(song.title) + " · " + library.source_description(song)
	_sync_creator_song_title()
	menu.show_section("sheet")
	popup.show()
	_refresh()

func _set_appearance(color: Color, use_rainbow: bool, light_setting: Variant = "supernova") -> void:
	active_color = Color(color.r, color.g, color.b, 1.0)
	rainbow = use_rainbow
	if typeof(light_setting) == TYPE_BOOL:
		current_light_mode = "supernova" if light_setting else "off"
	else:
		current_light_mode = str(light_setting)
	rhythm_flashes = (current_light_mode != "off")
	if visualizer != null:
		visualizer.rhythm_flashes = rhythm_flashes
		visualizer.light_mode = current_light_mode
	keyboard.active_color = active_color
	keyboard.recolor(active_color)
	if not rainbow:
		for bar in visualizer.bars.values():
			bar.color = active_color
	keyboard.queue_redraw()
	if menu != null:
		menu.apply_appearance_state(active_color, rainbow, current_light_mode)
		menu.update_playback_state(_sustain_active(), auto_enabled, active_color)
	if creator_overlay != null:
		creator_overlay.set_active_color(active_color)
	save_user_settings()

func _change_instrument(id: String) -> void:
	if audio != null:
		audio.set_instrument(id)
		if selected_song == "custom" and menu != null:
			menu.song_title.text = "%s  /  88 Teclas" % audio.get_current_instrument_name()
	save_user_settings()

func _change_bar_style(style: String) -> void:
	if visualizer != null:
		visualizer.bar_style = style
		visualizer.queue_redraw()
		if visualizer.halo != null:
			visualizer.halo.queue_redraw()
	save_user_settings()

func _change_reverb_preset(preset: String) -> void:
	if audio != null:
		audio.set_reverb_preset(preset)
	save_user_settings()

func _set_volume(value: float) -> void:
	volume_label.text = "%d%%" % int(value)
	if audio != null:
		audio.set_volume(int(clampf(value, 0, 100) * 2))

func _refresh_progress() -> void:
	counter.text = ("ACTIVO" if auto_enabled else "EN PAUSA") + "  ·  Paso %d de %d" % [step_index + 1 if not steps.is_empty() else 0, steps.size()]
	next_step.text = "Siguiente: " + step_labels[step_index] if not steps.is_empty() else "Pega una hoja para comenzar"
	progress.max_value = maxi(1, steps.size())
	progress.value = step_index
	if creator_overlay != null:
		creator_overlay.update_steps(steps, step_index, true)

func _refresh() -> void:
	buttons.auto.disabled = steps.is_empty()
	buttons.sustain.text = "Sustain " + ("ON" if _sustain_active() else "OFF")
	buttons.auto.text = "Pausar Auto" if auto_enabled else "Activar Auto"
	indicators.sustain.visible = _sustain_active()
	indicators.auto.visible = auto_enabled
	indicators.popup_Auto.visible = auto_enabled
	popup_buttons.Auto.text = "Pausar Auto" if auto_enabled else "Activar Auto"
	popup_buttons.Reset.disabled = steps.is_empty()
	sheet_text_edit.editable = not auto_enabled
	if menu != null:
		menu.update_playback_state(_sustain_active(), auto_enabled, active_color)
	_refresh_progress()

func _control(id: String, _delta: int) -> void:
	_blur()
	match id:
		"auto": popup.visible = not popup.visible
		"sustain": sustain_enabled = not sustain_enabled
	_sync_sustain()
	_refresh()

func _popup_action(action: String) -> void:
	_blur()
	match action:
		"Auto":
			auto_enabled = not auto_enabled and not steps.is_empty()
		"Paste":
			if drafts.has(selected_song):
				drafts.erase(selected_song)
			selected_song = "custom"
			library_sheet = false
			compiled_text = ""
			auto_enabled = false
			sheet_text_edit.text = Parser.normalize(DisplayServer.clipboard_get())
			_compile_sheet()
		"Clear":
			auto_enabled = false
			sheet_text_edit.text = ""
			if drafts.has(selected_song):
				drafts.erase(selected_song)
			selected_song = "custom"
			library_sheet = false
			if audio != null and menu != null:
				menu.song_title.text = "%s  /  88 Teclas" % audio.get_current_instrument_name()
			_compile_sheet()
		"Reset": _reset_auto()
		"Exit": popup.hide()
	sheet_text_edit.release_focus()
	_refresh()

func _reset_auto() -> void:
	for source in sources.keys():
		_release_source(source)
	step_index = 0
	if not steps.is_empty() and steps[0].transposition != null:
		transposition = steps[0].transposition
	else:
		transposition = 0
	_refresh_progress()
	_refresh()

func _compile_sheet() -> void:
	if compiled_text == sheet_text_edit.text and not steps.is_empty():
		dirty_sheet = false
		return
	compiled_text = sheet_text_edit.text
	sheet_text_edit.set_caret_line(0)
	sheet_text_edit.set_caret_column(0)
	sheet_text_edit.scroll_vertical = 0
	steps = Parser.parse(compiled_text, library_sheet)
	step_delays = Parser.parse_delays(compiled_text)
	step_labels.clear()
	var labels = Keymap.labels()
	for step in steps:
		var names = PackedStringArray()
		for note in step.notes:
			names.append(str(labels.get(note, note)))
		step_labels.append("[" + " ".join(names) + "]" if names.size() > 1 else " ".join(names))
	step_index = 0
	dirty_sheet = false
	if steps.is_empty():
		auto_enabled = false
		if bot_enabled:
			set_bot_enabled(false)
	elif steps[0].transposition != null:
		transposition = steps[0].transposition
	if creator_overlay != null:
		creator_overlay.update_steps(steps, step_index, false)
	_sync_creator_song_title()

func _blur() -> void:
	sheet_text_edit.release_focus()
	sheet_text_edit.editable = not auto_enabled
	if dirty_sheet or compiled_text != sheet_text_edit.text:
		_compile_sheet()
		_refresh()

func _sustain_active() -> bool:
	return sustain_enabled or space_held

func _sync_sustain() -> void:
	if audio != null:
		audio.set_sustain(_sustain_active())

func _input(event: InputEvent) -> void:
	if sheet_text_edit == null:
		return
	if midi_dialog != null and (midi_dialog.visible or export_dialog.visible or midi_notice.visible or (image_bg_dialog != null and image_bg_dialog.visible) or (video_bg_dialog != null and video_bg_dialog.visible)):
		return
	if event is InputEventMouseButton and event.pressed:
		if not sheet_text_edit.get_global_rect().has_point(event.position):
			_blur()
		if menu != null:
			if menu.channel_field != null and not menu.channel_field.get_global_rect().has_point(event.position):
				menu.channel_field.release_focus()
			if menu.subtitle_field != null and not menu.subtitle_field.get_global_rect().has_point(event.position):
				menu.subtitle_field.release_focus()
	if not event is InputEventKey:
		return
	var code = Keymap.physical(event)
	var is_plus = (code == KEY_PLUS or code == KEY_KP_ADD or (event.unicode == 43 and code != KEY_EQUAL))
	var is_pipe = (event.unicode == 124 or code == KEY_BAR or event.key_label == KEY_BAR or event.key_label == 124)
	var is_reset_key = (code == KEY_TAB)
	if not event.pressed:
		pressed.erase(code)
		_release_source(code)
		if code == KEY_SPACE:
			space_held = false
			_sync_sustain()
			_refresh()
			get_viewport().set_input_as_handled()
			return
		if is_plus or is_pipe or is_reset_key:
			get_viewport().set_input_as_handled()
			return
		return
	if event.echo:
		return
	if code == KEY_ESCAPE:
		if zen_mode:
			set_zen_mode(false)
		_blur()
		menu.search_field.release_focus()
		menu.song_list.release_focus()
		menu.release_creator_focus()
		popup.hide()
		get_viewport().set_input_as_handled()
		return
	if menu.editing_input():
		return
	if sheet_text_edit.has_focus() and not auto_enabled:
		return
	if event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		match code:
			KEY_B:
				toggle_branding_card()
				get_viewport().set_input_as_handled()
				return
			KEY_H:
				toggle_live_sheet_hud()
				get_viewport().set_input_as_handled()
				return
			KEY_Y:
				toggle_shorts_mode()
				get_viewport().set_input_as_handled()
				return
			KEY_K:
				cycle_key_range_mode()
				get_viewport().set_input_as_handled()
				return
			KEY_M:
				toggle_kps_hud()
				get_viewport().set_input_as_handled()
				return
			KEY_R:
				toggle_audio_recording()
				get_viewport().set_input_as_handled()
				return
			KEY_P:
				toggle_bot_mode()
				get_viewport().set_input_as_handled()
				return
		if auto_enabled:
			return
		if not Keymap.ROBLOX_CTRL_LOW.has(code) and not Keymap.ROBLOX_CTRL_HIGH.has(code):
			return
		if not Keymap.ROBLOX_CTRL_LOW.has(code) and not Keymap.ROBLOX_CTRL_HIGH.has(code):
			return
	if is_pipe:
		set_zen_mode(not zen_mode)
		get_viewport().set_input_as_handled()
		return
	if is_reset_key:
		_reset_auto()
		get_viewport().set_input_as_handled()
		return
	if is_plus:
		_popup_action("Auto")
		get_viewport().set_input_as_handled()
		return
	if auto_enabled:
		get_viewport().set_input_as_handled()
	if pressed.has(code):
		return
	pressed[code] = true
	if code == KEY_SPACE:
		if event.shift_pressed:
			sustain_enabled = not sustain_enabled
			space_held = false
		else:
			space_held = true
		_sync_sustain()
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event.alt_pressed or event.meta_pressed:
		return
	if auto_enabled and Keymap.is_note_key(code):
		if not steps.is_empty():
			var step = steps[step_index]
			if step.transposition != null:
				transposition = step.transposition
			_press_source(code, step.notes)
			step_index = (step_index + 1) % steps.size()
			_refresh_progress()
	elif not auto_enabled:
		var midi = Keymap.manual_note(code, event.shift_pressed, event.ctrl_pressed)
		if midi >= 0:
			_press_source(code, [midi])
			get_viewport().set_input_as_handled()

func _press_source(source: Variant, notes: Array) -> void:
	if sources.has(source):
		return
	var group: Array[Dictionary] = []
	var first_color: Color = active_color
	var pitches: Array[int] = []
	var has_deep_bass: bool = false
	for midi in notes:
		var pitch = int(midi) + transposition
		if pitch < 21 or pitch > 108:
			continue
		pitches.append(pitch)
		if pitch < 45 and velocity >= 85:
			has_deep_bass = true
		serial += 1
		group.append({"token": serial, "midi": pitch})
		audio.note_on(serial, pitch, velocity)
		var color = Color.from_hsv(fmod(Time.get_ticks_msec() * 0.00008, 1.0), 0.65, 1.0) if rainbow else active_color
		first_color = color
		keyboard.press(pitch, color)
		visualizer.note_on(serial, pitch, color)
	sources[source] = group
	if not pitches.is_empty():
		var now_ms = Time.get_ticks_msec()
		while not _recent_shake_notes.is_empty() and (now_ms - _recent_shake_notes[0]) > 50:
			_recent_shake_notes.pop_front()
		for _p in pitches:
			_recent_shake_notes.append(now_ms)
		if camera_shake_enabled and (pitches.size() >= 4 or _recent_shake_notes.size() >= 4 or has_deep_bass):
			add_trauma(0.4)
		if creator_overlay != null:
			creator_overlay.on_note_triggered(pitches)
	if rhythm_flashes and not group.is_empty():
		var chord_strength = clampf(float(group.size()) / 2.0, 0.9, 2.2)
		visualizer.trigger_flash(first_color, chord_strength, pitches)

func _release_source(source: Variant) -> void:
	if not sources.has(source):
		return
	for voice in sources[source]:
		audio.note_off(voice.token)
		keyboard.release(voice.midi)
		visualizer.note_off(voice.token)
	sources.erase(source)

func _mouse_note(midi: int) -> void:
	_release_source("mouse")
	if midi >= 0:
		_press_source("mouse", [midi])

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not shutting_down:
		_shutdown()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and audio != null:
		_blur()
		for source in sources.keys():
			_release_source(source)
		pressed.clear()
		space_held = false
		keyboard.dragging = false
		keyboard.mouse_note = -1
		audio.stop_all()
		_sync_sustain()
		_refresh()

func _shutdown() -> void:
	shutting_down = true
	set_process_input(false)
	if audio != null:
		audio.stop_all()
	# Let the audio server drain stopped voices before destroying the scene.
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()
