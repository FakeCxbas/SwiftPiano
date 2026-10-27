extends Panel
## All UI lives in the floating glassmorphism dock and drawer.
const StudioSkin = preload("res://scripts/studio_theme.gd")
signal action(id: String)
signal volume_changed(value: float)
signal song_requested(index: int)
signal appearance_changed(color: Color, rainbow: bool, light_mode: Variant)
signal instrument_changed(id: String)
signal bar_style_changed(id: String)
signal reverb_preset_changed(preset: String)
signal creator_zen_requested()
signal creator_branding_changed(enabled: bool, pos: String)
signal creator_hud_changed(enabled: bool, pos: String)
signal creator_shorts_toggled(enabled: bool)
signal creator_key_range_changed(mode: String)
signal creator_text_changed(channel: String, subtitle: String)
signal creator_kps_toggled(enabled: bool)
signal creator_shake_toggled(enabled: bool)
signal creator_rec_toggled()
signal creator_bot_toggled(enabled: bool)
signal creator_bot_bpm_changed(bpm: float)
signal creator_bg_image_requested()
signal creator_bg_video_requested()
signal creator_bg_clear_requested()
signal creator_bg_opacity_changed(opacity: float)

class PianoIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(20, 15)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w = 20.0
		var h = 15.0
		draw_rect(Rect2(0, 0, w, h), Color("#dcedf7"), true)
		for i in range(1, 4):
			draw_line(Vector2(i * 5.0, 0), Vector2(i * 5.0, h), Color("#0d1722"), 1.0)
		draw_rect(Rect2(3.2, 0, 3.2, 9.0), Color("#0d1722"), true)
		draw_rect(Rect2(8.5, 0, 3.2, 9.0), Color("#0d1722"), true)
		draw_rect(Rect2(13.8, 0, 3.2, 9.0), Color("#0d1722"), true)

class LedDot extends Control:
	var active: bool = true
	var color: Color = Color("#64e8d0")
	func _init() -> void:
		custom_minimum_size = Vector2(10, 10)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if active:
			draw_circle(Vector2(5, 5), 4.5, Color(color.r, color.g, color.b, 0.35))
			draw_circle(Vector2(5, 5), 2.5, Color(color.r * 1.4, color.g * 1.4, color.b * 1.4))
		else:
			draw_circle(Vector2(5, 5), 2.5, Color("#3a5060"))

class PlayPauseIcon extends Control:
	var playing: bool = false
	var color: Color = Color("#64e8d0")
	func _init() -> void:
		custom_minimum_size = Vector2(12, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if playing:
			draw_rect(Rect2(1.5, 1, 3.0, 10), color, true)
			draw_rect(Rect2(7.5, 1, 3.0, 10), color, true)
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(2, 1), Vector2(11, 6), Vector2(2, 11)]), color)

class SpeakerIcon extends Control:
	var color: Color = Color("#8faec2")
	func _init() -> void:
		custom_minimum_size = Vector2(14, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(0, 4, 3, 6), color, true)
		draw_colored_polygon(PackedVector2Array([Vector2(3, 4), Vector2(7, 1), Vector2(7, 13), Vector2(3, 10)]), color)
		draw_arc(Vector2(7, 7), 3.5, -PI * 0.35, PI * 0.35, 6, color, 1.2, true)
		draw_arc(Vector2(7, 7), 6.5, -PI * 0.35, PI * 0.35, 6, Color(color.r, color.g, color.b, 0.6), 1.2, true)

class GlowingIsland extends Panel:
	var accent_color: Color = Color("#64e8d0")
	var base_box: StyleBoxFlat = StyleBoxFlat.new()
	
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rebuild_styles()
	
	func set_accent(color: Color) -> void:
		accent_color = color
		_rebuild_styles()
		queue_redraw()
	
	func _rebuild_styles() -> void:
		base_box = StyleBoxFlat.new()
		base_box.bg_color = Color(0.02, 0.035, 0.055, 0.90)
		base_box.border_color = Color(1.0, 1.0, 1.0, 0.07)
		base_box.set_border_width_all(1)
		base_box.set_corner_radius_all(24)
		base_box.shadow_color = Color(0.0, 0.0, 0.0, 0.7)
		base_box.shadow_size = 22
		base_box.shadow_offset = Vector2(0, 5)
	
	func _draw() -> void:
		base_box.bg_color = Color("#171b22")
		base_box.border_color = Color("#333a43")
		base_box.set_corner_radius_all(16)
		base_box.shadow_size = 14
		draw_style_box(base_box, Rect2(Vector2.ZERO, size))
		draw_line(Vector2(18, 51), Vector2(size.x - 18, 51), Color("#2c323b"), 1.0)
		draw_line(Vector2(20, 0), Vector2(74, 0), accent_color, 2.0)

var buttons = {}
const ConversionPanel = preload("res://scripts/conversion_panel.gd")
var converter: ConversionPanel
var popup_buttons = {}
var indicators = {}
var instrument_buttons = {}
var current_instrument = "grand_piano"
var light_mode_buttons = {}
var current_light_mode = "supernova"
var bar_style_buttons = {}
var current_bar_style = "laser_crystal"
var reverb_buttons = {}
var current_reverb_preset = "studio"
var creator_zen_button: Button
var branding_toggle_btn: Button
var branding_pos_buttons = {}
var current_branding_enabled: bool = true
var current_branding_pos: String = "top_left"
var hud_toggle_btn: Button
var hud_pos_buttons = {}
var current_hud_enabled: bool = true
var current_hud_pos: String = "top_center"
var shorts_toggle_btn: Button
var current_shorts_enabled: bool = false
var kps_toggle_btn: Button
var current_kps_enabled: bool = true
var shake_toggle_btn: Button
var current_shake_enabled: bool = false
var rec_toggle_btn: Button
var current_rec_active: bool = false
var bot_toggle_btn: Button
var current_bot_enabled: bool = false
var bot_bpm_slider: HSlider
var bot_bpm_label: Label
var current_bot_bpm: float = 120.0
var bg_image_btn: Button
var bg_video_btn: Button
var bg_clear_btn: Button
var sala_bg_image_btn: Button
var sala_bg_video_btn: Button
var sala_bg_clear_btn: Button
var bg_opacity_slider: HSlider
var bg_opacity_label: Label
var key_range_buttons = {}
var current_key_range_mode: String = "full_88"
var channel_field: LineEdit
var subtitle_field: LineEdit
var island: Panel
var segmented_panel: Panel
var song_chip_panel: Panel
var piano_icon: PianoIcon
var led_dot: LedDot
var play_icon: PlayPauseIcon
var speaker_icon: SpeakerIcon
var drawer: Panel
var sheet_text_edit: TextEdit
var volume_slider: HSlider
var volume_label: Label
var counter: Label
var next_step: Label
var progress: ProgressBar
var search_field: LineEdit
var song_list: ItemList
var color_picker: ColorPickerButton
var rainbow_toggle: CheckButton
var rhythm_flash_toggle: CheckButton
var header: Label
var song_title: Label
var section_title: Label
var section_hint: Label
var close_button: Button
var load_button: Button
var selection_label: Label
var body: MarginContainer
var body_scroll: ScrollContainer
var pages = {}
var library
var filtered: Array[int] = []
var section = "sheet"
var chosen_color = Color("#64e8d0")
var menu_height = 66.0

func label(text: String, font_size: int = 14, color: Color = Color("#c3cddd")) -> Label:
	var item = Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	item.clip_text = true
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

func button(text: String, primary: bool = false) -> Button:
	var item = Button.new()
	item.text = text
	item.focus_mode = Control.FOCUS_NONE
	item.clip_text = true
	item.custom_minimum_size.y = 30
	item.custom_minimum_size.x = 76
	StudioSkin.decorate(item, primary)
	return item

func build(song_library) -> void:
	library = song_library
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	island = GlowingIsland.new()
	island.set_accent(chosen_color)
	add_child(island)
	
	piano_icon = PianoIcon.new()
	add_child(piano_icon)
	header = label("SWIFTPIANO", 12, Color("#f2f8fc"))
	add_child(header)
	
	song_chip_panel = Panel.new()
	song_chip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	song_chip_panel.add_theme_stylebox_override("panel", StudioSkin.chip(Color(0.06, 0.12, 0.18, 0.65), Color(0.25, 0.45, 0.55, 0.4), 12))
	add_child(song_chip_panel)
	song_title = label("Grand Studio  /  88 Teclas", 11, Color("#99c6d8"))
	add_child(song_title)
	
	segmented_panel = Panel.new()
	segmented_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	segmented_panel.add_theme_stylebox_override("panel", StudioSkin.segmented_dock(16))
	add_child(segmented_panel)
	
	var titles = {"library": "Biblioteca", "sheet": "Hoja", "appearance": "Estudio", "sustain": "Sustain ON", "auto": "Activar Auto"}
	for id in ["library", "sheet", "appearance"]:
		var item = Button.new()
		item.text = titles[id]
		item.focus_mode = Control.FOCUS_NONE
		item.clip_text = true
		StudioSkin.segment_button(item, false, chosen_color)
		buttons[id] = item
		add_child(item)
		item.pressed.connect(func(): action.emit(id))
		var indicator = Control.new()
		indicator.visible = false
		indicators[id] = indicator
		item.add_child(indicator)
	
	var sus_btn = Button.new()
	sus_btn.text = "Sustain ON"
	sus_btn.focus_mode = Control.FOCUS_NONE
	sus_btn.clip_text = true
	StudioSkin.sustain_button(sus_btn, true, chosen_color)
	buttons["sustain"] = sus_btn
	add_child(sus_btn)
	sus_btn.pressed.connect(func(): action.emit("sustain"))
	var sus_ind = Control.new()
	sus_ind.visible = false
	indicators["sustain"] = sus_ind
	sus_btn.add_child(sus_ind)
	led_dot = LedDot.new()
	led_dot.color = chosen_color
	led_dot.active = true
	sus_btn.add_child(led_dot)
	
	var auto_btn = Button.new()
	auto_btn.text = "Activar Auto"
	auto_btn.focus_mode = Control.FOCUS_NONE
	auto_btn.clip_text = true
	StudioSkin.auto_button(auto_btn, false, chosen_color)
	buttons["auto"] = auto_btn
	add_child(auto_btn)
	auto_btn.pressed.connect(func(): action.emit("auto"))
	var auto_ind = Control.new()
	auto_ind.visible = false
	indicators["auto"] = auto_ind
	auto_btn.add_child(auto_ind)
	play_icon = PlayPauseIcon.new()
	play_icon.color = chosen_color
	play_icon.playing = false
	auto_btn.add_child(play_icon)
	
	speaker_icon = SpeakerIcon.new()
	add_child(speaker_icon)
	
	volume_label = label("100%", 11, Color("#9cb6c7"))
	add_child(volume_label)
	
	volume_slider = HSlider.new()
	volume_slider.max_value = 100
	volume_slider.value = 100
	volume_slider.step = 1
	volume_slider.focus_mode = Control.FOCUS_NONE
	volume_slider.tooltip_text = "Nivel de salida general (0% a 100%)."
	var track = StudioSkin.surface(Color("#1d303d"), Color("#274253"), 2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	volume_slider.add_theme_stylebox_override("slider", track)
	volume_slider.add_theme_stylebox_override("grabber_area", StudioSkin.surface(chosen_color, chosen_color, 2))
	volume_slider.value_changed.connect(func(value):
		volume_label.text = "%d%%" % int(value)
		volume_changed.emit(value))
	add_child(volume_slider)
	
	drawer = Panel.new()
	drawer.clip_contents = true
	drawer.visibility_changed.connect(_update_nav_styles)
	drawer.add_theme_stylebox_override("panel", StudioSkin.glass_panel())
	add_child(drawer)
	drawer.hide()
	
	section_title = label("", 21, Color("#ecf5fc"))
	drawer.add_child(section_title)
	section_hint = label("", 12, Color("#8fa6b0"))
	drawer.add_child(section_hint)
	close_button = button("✕ Cerrar")
	close_button.clip_text = false
	drawer.add_child(close_button)
	close_button.pressed.connect(func(): action.emit("Exit"))
	popup_buttons["Exit"] = close_button
	body = MarginContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll = ScrollContainer.new()
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	drawer.add_child(body_scroll)
	body_scroll.add_child(body)
	_build_library()
	_build_sheet()
	converter = ConversionPanel.new()
	pages.conversion = converter
	body.add_child(converter)
	converter.choose_requested.connect(func(): action.emit("ChooseConversionMidi"))
	_build_appearance()
	show_section("sheet", false)

func update_playback_state(sustain_active: bool, auto_active: bool, accent: Color = chosen_color) -> void:
	chosen_color = accent
	if island != null and island.has_method("set_accent"):
		island.set_accent(accent)
	if buttons.has("sustain"):
		StudioSkin.sustain_button(buttons.sustain, sustain_active, accent)
		if led_dot != null:
			led_dot.active = sustain_active
			led_dot.color = accent
			led_dot.queue_redraw()
	if buttons.has("auto"):
		StudioSkin.auto_button(buttons.auto, auto_active, accent)
		if play_icon != null:
			play_icon.playing = auto_active
			play_icon.color = Color("#052019") if auto_active else accent
			play_icon.queue_redraw()
	_update_nav_styles()

func _update_nav_styles() -> void:
	for key in ["library", "sheet", "appearance"]:
		if buttons.has(key):
			var active = ((key == section) or (key == "sheet" and section == "conversion")) and drawer != null and drawer.visible
			StudioSkin.segment_button(buttons[key], active, chosen_color)

func _build_library() -> void:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	pages.library = box
	body.add_child(box)
	search_field = LineEdit.new()
	search_field.placeholder_text = "Buscar canción, versión o fragmento…"
	search_field.custom_minimum_size.y = 42
	search_field.add_theme_font_size_override("font_size", 15)
	search_field.add_theme_stylebox_override("normal", StudioSkin.surface(Color("#11151c"), Color("#363e49")))
	search_field.text_changed.connect(_filter_library)
	box.add_child(search_field)
	song_list = ItemList.new()
	song_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	song_list.add_theme_stylebox_override("panel", StudioSkin.surface(Color("#11151c"), Color("#2c333d")))
	song_list.add_theme_stylebox_override("selected", StudioSkin.surface(Color("#28453e"), Color("#64e8d0"), 6))
	song_list.add_theme_stylebox_override("selected_focus", StudioSkin.surface(Color("#28453e"), Color("#64e8d0"), 6))
	song_list.add_theme_stylebox_override("hovered", StudioSkin.surface(Color("#232c34"), Color("#3a454e"), 6))
	song_list.add_theme_constant_override("v_separation", 20)
	song_list.add_theme_font_size_override("font_size", 15)
	song_list.item_selected.connect(_selection_changed)
	song_list.item_activated.connect(func(index): _select_song(index))
	box.add_child(song_list)
	var footer = HBoxContainer.new()
	box.add_child(footer)
	selection_label = label("Selecciona una hoja. No inicia el sonido automáticamente.", 12)
	selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(selection_label)
	load_button = button("Cargar hoja →", true)
	load_button.custom_minimum_size.x = 140
	load_button.disabled = true
	load_button.pressed.connect(func():
		var selected = song_list.get_selected_items()
		if not selected.is_empty():
			_select_song(selected[0]))
	footer.add_child(load_button)
	_filter_library("")

func _filter_library(query: String) -> void:
	filtered = library.search(query)
	song_list.clear()
	for index in filtered:
		var song = library.songs[index]
		var suffix = " · sin notas" if not song.has_sheet else ""
		song_list.add_item(str(song.title) + (" · compartida" if song.has("source") else " · p. %d" % song.page) + suffix)
		song_list.set_item_tooltip(song_list.item_count - 1, str(song.title) + "\n" + library.source_description(song) + suffix)
	load_button.disabled = true
	selection_label.text = "%d entradas · PDF y hojas compartidas" % filtered.size() if not filtered.is_empty() else "No hay coincidencias"

func _selection_changed(index: int) -> void:
	var song = library.songs[filtered[index]]
	load_button.disabled = not song.has_sheet
	selection_label.text = library.source_description(song) if song.has_sheet else "El PDF incluye el título, pero no contiene notas."

func _select_song(index: int) -> void:
	var selected = filtered[index]
	if library.songs[selected].has_sheet:
		search_field.release_focus()
		song_list.release_focus()
		song_requested.emit(selected)

func _build_sheet() -> void:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	pages.sheet = box
	body.add_child(box)
	var toolbar = HFlowContainer.new()
	box.add_child(toolbar)
	for entry in [["conversion", "Convertidor MIDI"], ["ExportSheet", "Guardar hoja"], ["Paste", "Pegar"], ["Clear", "Borrar"], ["Reset", "Reiniciar"]]:
		var item = button(entry[1])
		item.clip_text = false
		item.custom_minimum_size.x = 96 if entry[0] == "Reset" else 72
		popup_buttons[entry[0]] = item
		item.pressed.connect(func(): action.emit(entry[0]))
		toolbar.add_child(item)
	popup_buttons["ImportMidi"] = popup_buttons["conversion"]
	sheet_text_edit = TextEdit.new()
	sheet_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	sheet_text_edit.placeholder_text = "Carga una canción de Biblioteca o pega tu hoja aquí."
	sheet_text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet_text_edit.custom_minimum_size.y = 30
	sheet_text_edit.add_theme_font_size_override("font_size", 17)
	for state in ["normal", "focus", "read_only"]:
		var style = StudioSkin.surface(Color("#11151c"), chosen_color if state == "focus" else Color("#363e49"))
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		sheet_text_edit.add_theme_stylebox_override(state, style)
	sheet_text_edit.add_theme_color_override("font_color", Color("#e0ecf5"))
	sheet_text_edit.add_theme_color_override("font_readonly_color", Color("#bfd2df"))
	box.add_child(sheet_text_edit)
	var footer = HBoxContainer.new()
	box.add_child(footer)
	counter = label("", 12)
	counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(counter)
	next_step = label("", 15, chosen_color)
	next_step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(next_step)
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size.y = 4
	progress.add_theme_stylebox_override("background", StudioSkin.surface(Color("#233540"), Color("#233540"), 2))
	progress.add_theme_stylebox_override("fill", StudioSkin.surface(chosen_color, chosen_color, 2))
	box.add_child(progress)
	popup_buttons["Auto"] = buttons.auto
	indicators["popup_Auto"] = indicators.auto

func _studio_page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 16)
	scroll.add_child(box)
	return box

func _build_appearance() -> void:
	var tabs = TabContainer.new()
	tabs.add_theme_stylebox_override("panel", StudioSkin.surface(Color("#171b22"), Color("#171b22"), 6))
	tabs.add_theme_stylebox_override("tab_selected", StudioSkin.chip(Color("#28453e"), Color("#4d887b"), 8))
	tabs.add_theme_stylebox_override("tab_unselected", StudioSkin.chip(Color("#20262e"), Color("#333943"), 8))
	tabs.add_theme_font_size_override("font_size", 13)
	pages.appearance = tabs
	body.add_child(tabs)
	var box = _studio_page(tabs, "Pianos")
	
	box.add_child(label("TIMBRE DEL INSTRUMENTO", 12, Color("#82a7b9")))
	var inst_desc = label("Selecciona el sonido multisampleado para el piano (30 notas en cada banco).", 14)
	inst_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inst_desc.custom_minimum_size.y = 38
	box.add_child(inst_desc)
	
	var inst_flow = HFlowContainer.new()
	inst_flow.add_theme_constant_override("h_separation", 10)
	inst_flow.add_theme_constant_override("v_separation", 10)
	box.add_child(inst_flow)
	
	var instruments_data = [
		["grand_piano", "🎹  Piano de Cola", "Yamaha C5 Salamander"],
		["steinway_grand", "👑  Gran Steinway", "Modelo D de Concierto"],
		["bright_piano", "🌟  Piano Brillante", "Acústico Pop & Studio"],
		["honkytonk_piano", "🍺  Piano Honky-Tonk", "Saloon & Ragtime Clásico"],
		["electric_grand", "⚡  Grand CP-80", "Yamaha CP-80 Ochentas"],
		["electric_piano", "🎷  Piano Rhodes", "Vintage Mark I Rhodes"],
		["fm_piano", "💎  Piano Digital FM", "Yamaha DX7 Cristalino"],
		["church_organ", "⛪  Órgano Catedral", "Tubos & Acústica Sacra"],
		["synth_strings", "🎻  Synth Strings", "Pad Analógico Años 80"],
		["celesta", "✨  Celesta", "Campanas & Metalófono"],
		["harpsichord", "🎼  Clavecín", "Barroco de Doble Manual"]
	]
	
	for entry in instruments_data:
		var id = entry[0]
		var title = entry[1]
		var sub = entry[2]
		var btn = Button.new()
		btn.text = "%s\n%s" % [title, sub]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(230, 50)
		btn.pressed.connect(func():
			set_active_instrument(id)
			instrument_changed.emit(id))
		instrument_buttons[id] = btn
		inst_flow.add_child(btn)
	
	set_active_instrument(current_instrument)
	box = _studio_page(tabs, "Sala")
	
	var sep_rev = HSeparator.new()
	sep_rev.add_theme_stylebox_override("separator", StudioSkin.surface(Color("#1e3343"), Color("#1e3343"), 1))
	box.add_child(sep_rev)
	
	box.add_child(label("ACÚSTICA & ESPACIO (REVERB)", 12, Color("#82a7b9")))
	var rev_desc = label("Simulación acústica del entorno y resonancia de sala para los instrumentos.", 14)
	rev_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rev_desc.custom_minimum_size.y = 38
	box.add_child(rev_desc)
	
	var rev_flow = HFlowContainer.new()
	rev_flow.add_theme_constant_override("h_separation", 10)
	rev_flow.add_theme_constant_override("v_separation", 10)
	box.add_child(rev_flow)
	
	var reverb_presets_data = [
		["dry", "🔇  Seco / Directo", "Sin reverberación (Monitores)"],
		["studio", "🎙️  Estudio · Claro", "Notas definidas · recomendado"],
		["hall", "🏛️  Sala de Conciertos", "Ambiente original, más envolvente"],
		["cathedral", "⛪  Gran Catedral", "Reflexiones profundas e inmersivas"]
	]
	
	for entry in reverb_presets_data:
		var id = entry[0]
		var title = entry[1]
		var sub = entry[2]
		var btn = Button.new()
		btn.text = "%s\n%s" % [title, sub]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(230, 50)
		btn.pressed.connect(func():
			set_active_reverb_preset(id))
		reverb_buttons[id] = btn
		rev_flow.add_child(btn)
	
	set_active_reverb_preset(current_reverb_preset)
	
	var sep_bg_sala = HSeparator.new()
	sep_bg_sala.add_theme_stylebox_override("separator", StudioSkin.surface(Color("#1e3343"), Color("#1e3343"), 1))
	box.add_child(sep_bg_sala)
	
	box.add_child(label("FONDOS PERSONALIZADOS (WALLPAPER / VIDEO LOOP)", 12, Color("#82a7b9")))
	var sala_bg_row = HFlowContainer.new()
	sala_bg_row.add_theme_constant_override("h_separation", 8)
	sala_bg_row.add_theme_constant_override("v_separation", 8)
	box.add_child(sala_bg_row)
	
	sala_bg_image_btn = button("🖼️ Cargar Imagen de Fondo")
	sala_bg_image_btn.clip_text = false
	sala_bg_image_btn.custom_minimum_size = Vector2(190, 34)
	sala_bg_image_btn.pressed.connect(func(): creator_bg_image_requested.emit())
	sala_bg_row.add_child(sala_bg_image_btn)
	
	sala_bg_video_btn = button("🎞️ Cargar Video de Fondo")
	sala_bg_video_btn.clip_text = false
	sala_bg_video_btn.custom_minimum_size = Vector2(190, 34)
	sala_bg_video_btn.pressed.connect(func(): creator_bg_video_requested.emit())
	sala_bg_row.add_child(sala_bg_video_btn)
	
	sala_bg_clear_btn = button("🗑️ Borrar Fondo")
	sala_bg_clear_btn.clip_text = false
	sala_bg_clear_btn.custom_minimum_size = Vector2(130, 34)
	sala_bg_clear_btn.pressed.connect(func(): creator_bg_clear_requested.emit())
	sala_bg_row.add_child(sala_bg_clear_btn)
	
	box = _studio_page(tabs, "Color")
	
	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", StudioSkin.surface(Color("#1e3343"), Color("#1e3343"), 1))
	box.add_child(sep)
	
	box.add_child(label("LUZ DE LAS TECLAS", 12, Color("#82a7b9")))
	var description = label("Elige el color de las teclas pulsadas y las barras.", 14)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.y = 38
	box.add_child(description)
	var presets = HFlowContainer.new()
	box.add_child(presets)
	for pair in [["Menta", "#64e8d0"], ["Cielo", "#69b7ff"], ["Lila", "#b5a0ff"], ["Rosa", "#ff84b5"], ["Ámbar", "#ffca79"]]:
		var item = button(pair[0])
		item.add_theme_color_override("font_color", Color(pair[1]))
		item.pressed.connect(func():
			rainbow_toggle.button_pressed = false
			color_picker.color = Color(pair[1])
			_emit_appearance())
		presets.add_child(item)
	var row = HBoxContainer.new()
	box.add_child(row)
	var custom_label = label("Color personalizado", 14)
	custom_label.custom_minimum_size = Vector2(160, 28)
	row.add_child(custom_label)
	color_picker = ColorPickerButton.new()
	color_picker.color = chosen_color
	color_picker.edit_alpha = false
	color_picker.custom_minimum_size = Vector2(80, 34)
	color_picker.focus_mode = Control.FOCUS_NONE
	color_picker.color_changed.connect(func(_color): _emit_appearance())
	row.add_child(color_picker)
	rainbow_toggle = CheckButton.new()
	rainbow_toggle.text = "Arcoíris dinámico"
	rainbow_toggle.focus_mode = Control.FOCUS_NONE
	rainbow_toggle.toggled.connect(func(_value): _emit_appearance())
	box.add_child(rainbow_toggle)
	
	box = _studio_page(tabs, "Efectos")
	var sep_bar = HSeparator.new()
	sep_bar.add_theme_stylebox_override("separator", StudioSkin.surface(Color("#1e3343"), Color("#1e3343"), 1))
	box.add_child(sep_bar)
	
	box.add_child(label("ESTILO DE LAS BARRAS DE NOTAS", 12, Color("#82a7b9")))
	var bar_desc = label("Personaliza la apariencia y física visual de las barras que ascienden al pulsar las teclas.", 14)
	bar_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar_desc.custom_minimum_size.y = 38
	box.add_child(bar_desc)
	
	var bar_flow = HFlowContainer.new()
	bar_flow.add_theme_constant_override("h_separation", 10)
	bar_flow.add_theme_constant_override("v_separation", 10)
	box.add_child(bar_flow)
	
	var bar_styles_data = [
		["laser_crystal", "💎  Cristal Láser", "Bisel radiante & núcleo HDR"],
		["stardust", "✨  Polvo Estelar", "Cruces estelares & micro-chispas"],
		["comet", "☄️  Estela de Cometa", "Cabeza de plasma & cola cónica"],
		["cyber_pulse", "⚡  Pulso Cyberpunk", "Scanlines, aberración & pulsos"],
		["frosted_glass", "🧊  Vidrio Esmerilado", "Refracción de pantalla real"],
		["plasma", "🔥  Plasma Etéreo", "FBM orgánico & núcleo térmico"],
		["harmonic", "🧬  Cuerda Armónica", "Hélice doble & vibración tonal"]
	]
	
	for entry in bar_styles_data:
		var id = entry[0]
		var title = entry[1]
		var sub = entry[2]
		var btn = Button.new()
		btn.text = "%s\n%s" % [title, sub]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(230, 50)
		btn.pressed.connect(func():
			set_active_bar_style(id))
		bar_style_buttons[id] = btn
		bar_flow.add_child(btn)
	
	set_active_bar_style(current_bar_style)
	
	rhythm_flash_toggle = CheckButton.new()
	rhythm_flash_toggle.visible = false
	rhythm_flash_toggle.button_pressed = (current_light_mode != "off")
	rhythm_flash_toggle.toggled.connect(func(v):
		set_active_light_mode("supernova" if v else "off"))
	box.add_child(rhythm_flash_toggle)
	
	var sep2 = HSeparator.new()
	sep2.add_theme_stylebox_override("separator", StudioSkin.surface(Color("#1e3343"), Color("#1e3343"), 1))
	box.add_child(sep2)
	
	box.add_child(label("SHOW DE LUCES Y EFECTOS RÍTMICOS", 12, Color("#82a7b9")))
	var light_desc = label("Elige el estilo visual con el que la pantalla resplandece al ritmo de la música.", 14)
	light_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	light_desc.custom_minimum_size.y = 38
	box.add_child(light_desc)
	
	var light_flow = HFlowContainer.new()
	light_flow.add_theme_constant_override("h_separation", 10)
	light_flow.add_theme_constant_override("v_separation", 10)
	box.add_child(light_flow)
	
	var modes_data = [
		["off", "✕  Desactivado", "Modo minimalista sin destellos"],
		["supernova", "🌌  Supernova", "Shockwaves gaussianas & nebulosa"],
		["aurora", "🌊  Aurora Boreal", "Cortinas de luz polar en shader"],
		["starlight", "✨  Lluvia de Estrellas", "Estelas estiradas & física suave"],
		["rave", "🔦  Concierto Neón", "Focos volumétricos con bruma"],
		["synthwave", "🌆  Horizonte Synthwave", "Grid 3D & ecualizador reactivo"]
	]
	
	for entry in modes_data:
		var id = entry[0]
		var title = entry[1]
		var sub = entry[2]
		var btn = Button.new()
		btn.text = "%s\n%s" % [title, sub]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(230, 50)
		btn.pressed.connect(func():
			set_active_light_mode(id))
		light_mode_buttons[id] = btn
		light_flow.add_child(btn)
	
	set_active_light_mode(current_light_mode)
	
	var help = label("Iluminación al pulsar, relieve y desvanecimiento al soltar.\nSustain prolonga el audio, no deja la tecla visualmente atascada.", 13)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	
	# ---------------------------------------------------------
	# 🎬 MODO CREADOR / YOUTUBE (@DragonCxbas)
	# ---------------------------------------------------------
	box = _studio_page(tabs, "Creador")
	var sep_creator = HSeparator.new()
	sep_creator.add_theme_stylebox_override("separator", StudioSkin.surface(Color("#1e3343"), Color("#1e3343"), 1))
	box.add_child(sep_creator)
	
	box.add_child(label("🎬 MODO CREADOR / YOUTUBE (@DragonCxbas)", 12, Color("#82a7b9")))
	var creator_desc = label("Configura las tarjetas en pantalla, el Teleprompter de acordes en vivo y el encuadre vertical 9:16 para tus grabaciones.", 14)
	creator_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	creator_desc.custom_minimum_size.y = 38
	box.add_child(creator_desc)
	
	creator_zen_button = button("🎥 Activar Escenario de Grabación (Modo Zen |)", true)
	creator_zen_button.clip_text = false
	creator_zen_button.custom_minimum_size = Vector2(360, 38)
	creator_zen_button.pressed.connect(func():
		release_creator_focus()
		drawer.hide()
		creator_zen_requested.emit())
	box.add_child(creator_zen_button)
	
	# 1. Branding Card toggle & position chips
	var brand_row = HFlowContainer.new()
	brand_row.add_theme_constant_override("h_separation", 8)
	brand_row.add_theme_constant_override("v_separation", 8)
	box.add_child(brand_row)
	
	branding_toggle_btn = button("🏷️ Marca @DragonCxbas")
	branding_toggle_btn.clip_text = false
	branding_toggle_btn.custom_minimum_size = Vector2(190, 34)
	branding_toggle_btn.pressed.connect(func():
		set_creator_branding(not current_branding_enabled, current_branding_pos if not current_branding_enabled else "hidden", true))
	brand_row.add_child(branding_toggle_btn)
	
	for entry in [["top_left", "Izquierda"], ["top_right", "Derecha"], ["hidden", "Oculto"]]:
		var pos_id = entry[0]
		var pos_btn = button(entry[1])
		pos_btn.clip_text = false
		pos_btn.custom_minimum_size = Vector2(92, 34)
		pos_btn.pressed.connect(func():
			if pos_id == "hidden":
				set_creator_branding(false, "hidden", true)
			else:
				set_creator_branding(true, pos_id, true))
		branding_pos_buttons[pos_id] = pos_btn
		brand_row.add_child(pos_btn)
	
	# 2. LiveSheetHUD Teleprompter toggle & position chips
	var hud_row = HFlowContainer.new()
	hud_row.add_theme_constant_override("h_separation", 8)
	hud_row.add_theme_constant_override("v_separation", 8)
	box.add_child(hud_row)
	
	hud_toggle_btn = button("📜 Teleprompter de Hoja en Vivo")
	hud_toggle_btn.clip_text = false
	hud_toggle_btn.custom_minimum_size = Vector2(230, 34)
	hud_toggle_btn.pressed.connect(func():
		set_creator_hud(not current_hud_enabled, current_hud_pos if not current_hud_enabled else "hidden", true))
	hud_row.add_child(hud_toggle_btn)
	
	for entry in [["top_center", "Arriba Centro"], ["above_piano", "Sobre el Piano"], ["hidden", "Oculto"]]:
		var pos_id = entry[0]
		var pos_btn = button(entry[1])
		pos_btn.clip_text = false
		pos_btn.custom_minimum_size = Vector2(112, 34)
		pos_btn.pressed.connect(func():
			if pos_id == "hidden":
				set_creator_hud(false, "hidden", true)
			else:
				set_creator_hud(true, pos_id, true))
		hud_pos_buttons[pos_id] = pos_btn
		hud_row.add_child(pos_btn)
	
	# 3. Shorts 9:16 Frame, KPS/Combo HUD, Camera Shake & Audio Recorder
	var shorts_row = HFlowContainer.new()
	shorts_row.add_theme_constant_override("h_separation", 8)
	shorts_row.add_theme_constant_override("v_separation", 8)
	box.add_child(shorts_row)
	
	shorts_toggle_btn = button("📱 Encuadre Shorts 9:16")
	shorts_toggle_btn.clip_text = false
	shorts_toggle_btn.custom_minimum_size = Vector2(196, 34)
	shorts_toggle_btn.pressed.connect(func():
		set_creator_shorts(not current_shorts_enabled, true))
	shorts_row.add_child(shorts_toggle_btn)
	
	kps_toggle_btn = button("⚡ KPS & Combo HUD (Ctrl+M)")
	kps_toggle_btn.clip_text = false
	kps_toggle_btn.custom_minimum_size = Vector2(215, 34)
	kps_toggle_btn.pressed.connect(func():
		set_creator_kps(not current_kps_enabled, true))
	shorts_row.add_child(kps_toggle_btn)
	
	shake_toggle_btn = button("💥 Camera Shake Graves")
	shake_toggle_btn.clip_text = false
	shake_toggle_btn.custom_minimum_size = Vector2(185, 34)
	shake_toggle_btn.pressed.connect(func():
		set_creator_shake(not current_shake_enabled, true))
	shorts_row.add_child(shake_toggle_btn)
	
	rec_toggle_btn = button("🔴 Grabar Audio .WAV (Ctrl+R)")
	rec_toggle_btn.clip_text = false
	rec_toggle_btn.custom_minimum_size = Vector2(220, 34)
	rec_toggle_btn.pressed.connect(func():
		creator_rec_toggled.emit())
	shorts_row.add_child(rec_toggle_btn)
	
	var zoom_row = HFlowContainer.new()
	zoom_row.add_theme_constant_override("h_separation", 8)
	zoom_row.add_theme_constant_override("v_separation", 8)
	box.add_child(zoom_row)
	
	var zoom_lbl = label("🎹 Zoom de Teclado:", 13, Color("#c3cddd"))
	zoom_lbl.custom_minimum_size = Vector2(145, 32)
	zoom_row.add_child(zoom_lbl)
	
	for entry in [["full_88", "88 Teclas (A0-C8)"], ["central_61", "61 Teclas QWERTY (C2-C7)"], ["melodic_49", "Enfoque Shorts"]]:
		var mode_id = entry[0]
		var z_btn = button(entry[1])
		z_btn.clip_text = false
		z_btn.custom_minimum_size = Vector2(160, 34)
		z_btn.pressed.connect(func():
			set_creator_key_range(mode_id, true))
		key_range_buttons[mode_id] = z_btn
		zoom_row.add_child(z_btn)
	
	# 4. Bot Showcase (Auto-Play a Tempo Real) + BPM Slider
	var bot_row = HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", 12)
	box.add_child(bot_row)
	
	bot_toggle_btn = button("🤖 Bot Showcase (Ctrl+P)")
	bot_toggle_btn.clip_text = false
	bot_toggle_btn.custom_minimum_size = Vector2(210, 34)
	bot_toggle_btn.pressed.connect(func():
		set_creator_bot(not current_bot_enabled, true))
	bot_row.add_child(bot_toggle_btn)
	
	var bpm_title = label("Tempo Bot:", 13, Color("#9cb6c7"))
	bpm_title.custom_minimum_size = Vector2(82, 28)
	bot_row.add_child(bpm_title)
	
	bot_bpm_slider = HSlider.new()
	bot_bpm_slider.min_value = 30
	bot_bpm_slider.max_value = 360
	bot_bpm_slider.step = 1
	bot_bpm_slider.value = 120
	bot_bpm_slider.focus_mode = Control.FOCUS_NONE
	bot_bpm_slider.custom_minimum_size = Vector2(180, 26)
	bot_bpm_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bpm_track = StudioSkin.surface(Color("#1d303d"), Color("#274253"), 2)
	bpm_track.content_margin_top = 2
	bpm_track.content_margin_bottom = 2
	bot_bpm_slider.add_theme_stylebox_override("slider", bpm_track)
	bot_bpm_slider.add_theme_stylebox_override("grabber_area", StudioSkin.surface(chosen_color, chosen_color, 2))
	bot_bpm_slider.value_changed.connect(func(v):
		set_creator_bot_bpm(v, true))
	bot_row.add_child(bot_bpm_slider)
	
	bot_bpm_label = label("120 BPM", 13, Color("#f4f6ff"))
	bot_bpm_label.custom_minimum_size = Vector2(76, 28)
	bot_row.add_child(bot_bpm_label)
	
	# 5. Custom Backgrounds (Wallpaper / Video Loop)
	var bg_row = HFlowContainer.new()
	bg_row.add_theme_constant_override("h_separation", 8)
	bg_row.add_theme_constant_override("v_separation", 8)
	box.add_child(bg_row)
	
	bg_image_btn = button("🖼️ Cargar Imagen de Fondo")
	bg_image_btn.clip_text = false
	bg_image_btn.custom_minimum_size = Vector2(195, 34)
	bg_image_btn.pressed.connect(func(): creator_bg_image_requested.emit())
	bg_row.add_child(bg_image_btn)
	
	bg_video_btn = button("🎞️ Cargar Video de Fondo")
	bg_video_btn.clip_text = false
	bg_video_btn.custom_minimum_size = Vector2(195, 34)
	bg_video_btn.pressed.connect(func(): creator_bg_video_requested.emit())
	bg_row.add_child(bg_video_btn)
	
	bg_clear_btn = button("🗑️ Borrar Fondo")
	bg_clear_btn.clip_text = false
	bg_clear_btn.custom_minimum_size = Vector2(130, 34)
	bg_clear_btn.pressed.connect(func(): creator_bg_clear_requested.emit())
	bg_row.add_child(bg_clear_btn)
	
	var bg_op_lbl = label("Opacidad:", 13, Color("#9cb6c7"))
	bg_op_lbl.custom_minimum_size = Vector2(72, 28)
	bg_row.add_child(bg_op_lbl)
	
	bg_opacity_slider = HSlider.new()
	bg_opacity_slider.min_value = 10
	bg_opacity_slider.max_value = 100
	bg_opacity_slider.step = 1
	bg_opacity_slider.value = 40
	bg_opacity_slider.focus_mode = Control.FOCUS_NONE
	bg_opacity_slider.custom_minimum_size = Vector2(110, 26)
	bg_opacity_slider.add_theme_stylebox_override("slider", bpm_track)
	bg_opacity_slider.add_theme_stylebox_override("grabber_area", StudioSkin.surface(chosen_color, chosen_color, 2))
	bg_opacity_slider.value_changed.connect(func(v):
		if bg_opacity_label != null:
			bg_opacity_label.text = "%d%%" % int(v)
		creator_bg_opacity_changed.emit(clampf(v / 100.0, 0.05, 1.0)))
	bg_row.add_child(bg_opacity_slider)
	
	bg_opacity_label = label("40%", 13, Color("#f4f6ff"))
	bg_opacity_label.custom_minimum_size = Vector2(46, 28)
	bg_row.add_child(bg_opacity_label)
	
	# 6. Editable Channel & Subtitle LineEdits
	var fields_grid = GridContainer.new()
	fields_grid.columns = 2
	fields_grid.add_theme_constant_override("h_separation", 12)
	fields_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(fields_grid)
	
	var ch_lbl = label("Canal / Handle:", 13, Color("#9cb6c7"))
	ch_lbl.custom_minimum_size = Vector2(140, 34)
	fields_grid.add_child(ch_lbl)
	
	channel_field = LineEdit.new()
	channel_field.text = "@DragonCxbas"
	channel_field.placeholder_text = "@DragonCxbas"
	channel_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	channel_field.custom_minimum_size = Vector2(260, 36)
	channel_field.add_theme_stylebox_override("normal", StudioSkin.surface(Color("#11151c"), Color("#363e49")))
	channel_field.add_theme_stylebox_override("focus", StudioSkin.surface(Color("#11151c"), chosen_color))
	channel_field.text_changed.connect(func(_t):
		creator_text_changed.emit(channel_field.text, subtitle_field.text if subtitle_field != null else ""))
	channel_field.text_submitted.connect(func(_t):
		channel_field.release_focus()
		creator_text_changed.emit(channel_field.text, subtitle_field.text if subtitle_field != null else ""))
	fields_grid.add_child(channel_field)
	
	var sub_lbl = label("Subtítulo en Video:", 13, Color("#9cb6c7"))
	sub_lbl.custom_minimum_size = Vector2(140, 34)
	fields_grid.add_child(sub_lbl)
	
	subtitle_field = LineEdit.new()
	subtitle_field.text = "Virtual Piano Sheet in Description"
	subtitle_field.placeholder_text = "Virtual Piano Sheet in Description"
	subtitle_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle_field.custom_minimum_size = Vector2(260, 36)
	subtitle_field.add_theme_stylebox_override("normal", StudioSkin.surface(Color("#11151c"), Color("#363e49")))
	subtitle_field.add_theme_stylebox_override("focus", StudioSkin.surface(Color("#11151c"), chosen_color))
	subtitle_field.text_changed.connect(func(_t):
		creator_text_changed.emit(channel_field.text if channel_field != null else "@DragonCxbas", subtitle_field.text))
	subtitle_field.text_submitted.connect(func(_t):
		subtitle_field.release_focus()
		creator_text_changed.emit(channel_field.text if channel_field != null else "@DragonCxbas", subtitle_field.text))
	fields_grid.add_child(subtitle_field)
	
	_refresh_creator_styles()

func set_creator_branding(enabled: bool, pos: String = "top_left", emit_sig: bool = false) -> void:
	current_branding_enabled = enabled
	if pos != "hidden" and not pos.is_empty():
		current_branding_pos = pos
	_refresh_creator_styles()
	if emit_sig:
		creator_branding_changed.emit(current_branding_enabled, "hidden" if not current_branding_enabled else current_branding_pos)

func set_creator_hud(enabled: bool, pos: String = "top_center", emit_sig: bool = false) -> void:
	current_hud_enabled = enabled
	if pos != "hidden" and not pos.is_empty():
		current_hud_pos = pos
	_refresh_creator_styles()
	if emit_sig:
		creator_hud_changed.emit(current_hud_enabled, "hidden" if not current_hud_enabled else current_hud_pos)

func set_creator_shorts(enabled: bool, emit_sig: bool = false) -> void:
	current_shorts_enabled = enabled
	_refresh_creator_styles()
	if emit_sig:
		creator_shorts_toggled.emit(current_shorts_enabled)

func set_creator_kps(enabled: bool, emit_sig: bool = false) -> void:
	current_kps_enabled = enabled
	_refresh_creator_styles()
	if emit_sig:
		creator_kps_toggled.emit(current_kps_enabled)

func set_creator_shake(enabled: bool, emit_sig: bool = false) -> void:
	current_shake_enabled = enabled
	_refresh_creator_styles()
	if emit_sig:
		creator_shake_toggled.emit(current_shake_enabled)

func set_creator_recording(active: bool) -> void:
	current_rec_active = active
	if rec_toggle_btn != null:
		rec_toggle_btn.text = "⏹️ Detener .WAV (Ctrl+R)" if current_rec_active else "🔴 Grabar Audio .WAV (Ctrl+R)"
	_refresh_creator_styles()

func set_creator_bot(enabled: bool, emit_sig: bool = false) -> void:
	current_bot_enabled = enabled
	if bot_toggle_btn != null:
		bot_toggle_btn.text = "⏸️ Pausar Bot (Ctrl+P)" if current_bot_enabled else "🤖 Bot Showcase (Ctrl+P)"
	_refresh_creator_styles()
	if emit_sig:
		creator_bot_toggled.emit(current_bot_enabled)

func set_creator_bot_bpm(bpm: float, emit_sig: bool = false) -> void:
	current_bot_bpm = clampf(bpm, 30.0, 360.0)
	if bot_bpm_slider != null and not is_equal_approx(bot_bpm_slider.value, current_bot_bpm):
		bot_bpm_slider.set_value_no_signal(current_bot_bpm)
	if bot_bpm_label != null:
		bot_bpm_label.text = "%d BPM" % int(round(current_bot_bpm))
	if emit_sig:
		creator_bot_bpm_changed.emit(current_bot_bpm)

func set_creator_key_range(mode: String, emit_sig: bool = false) -> void:
	current_key_range_mode = mode
	_refresh_creator_styles()
	if emit_sig:
		creator_key_range_changed.emit(current_key_range_mode)

func _refresh_creator_styles() -> void:
	if creator_zen_button != null:
		StudioSkin._button(creator_zen_button, true, chosen_color, true)
	if branding_toggle_btn != null:
		StudioSkin._button(branding_toggle_btn, current_branding_enabled, chosen_color)
	var active_b_pos = "hidden" if not current_branding_enabled else current_branding_pos
	for k in branding_pos_buttons:
		StudioSkin._button(branding_pos_buttons[k], k == active_b_pos, chosen_color)
	if hud_toggle_btn != null:
		StudioSkin._button(hud_toggle_btn, current_hud_enabled, chosen_color)
	var active_h_pos = "hidden" if not current_hud_enabled else current_hud_pos
	for k in hud_pos_buttons:
		StudioSkin._button(hud_pos_buttons[k], k == active_h_pos, chosen_color)
	if shorts_toggle_btn != null:
		StudioSkin._button(shorts_toggle_btn, current_shorts_enabled, chosen_color)
	if kps_toggle_btn != null:
		StudioSkin._button(kps_toggle_btn, current_kps_enabled, chosen_color)
	if shake_toggle_btn != null:
		StudioSkin._button(shake_toggle_btn, current_shake_enabled, chosen_color)
	if rec_toggle_btn != null:
		StudioSkin._button(rec_toggle_btn, current_rec_active, Color("#ff3b47") if current_rec_active else chosen_color)
	if bot_toggle_btn != null:
		StudioSkin._button(bot_toggle_btn, current_bot_enabled, chosen_color)
	for k in key_range_buttons:
		StudioSkin._button(key_range_buttons[k], k == current_key_range_mode, chosen_color)

func release_creator_focus() -> void:
	if channel_field != null:
		channel_field.release_focus()
	if subtitle_field != null:
		subtitle_field.release_focus()

func set_active_instrument(id: String) -> void:
	current_instrument = id
	for key in instrument_buttons:
		StudioSkin.instrument_button(instrument_buttons[key], key == current_instrument, chosen_color)

func set_active_reverb_preset(id: String) -> void:
	current_reverb_preset = id
	for key in reverb_buttons:
		StudioSkin.instrument_button(reverb_buttons[key], key == current_reverb_preset, chosen_color)
	reverb_preset_changed.emit(current_reverb_preset)

func set_active_bar_style(id: String) -> void:
	current_bar_style = id
	for key in bar_style_buttons:
		StudioSkin.instrument_button(bar_style_buttons[key], key == current_bar_style, chosen_color)
	bar_style_changed.emit(current_bar_style)

func set_active_light_mode(id: String) -> void:
	current_light_mode = id
	if rhythm_flash_toggle != null:
		rhythm_flash_toggle.set_pressed_no_signal(current_light_mode != "off")
	for key in light_mode_buttons:
		StudioSkin.instrument_button(light_mode_buttons[key], key == current_light_mode, chosen_color)
	_emit_appearance()

func apply_appearance_state(color: Color, use_rainbow: bool, light_id: String = current_light_mode) -> void:
	chosen_color = Color(color.r, color.g, color.b, 1.0)
	current_light_mode = light_id
	if color_picker != null:
		color_picker.color = chosen_color
	if rainbow_toggle != null:
		rainbow_toggle.set_pressed_no_signal(use_rainbow)
	if rhythm_flash_toggle != null:
		rhythm_flash_toggle.set_pressed_no_signal(current_light_mode != "off")
	_sync_accent_widgets()

func _sync_accent_widgets() -> void:
	if island != null and island.has_method("set_accent"):
		island.set_accent(chosen_color)
	if volume_slider != null:
		volume_slider.add_theme_stylebox_override("grabber_area", StudioSkin.surface(chosen_color, chosen_color, 2))
	if bot_bpm_slider != null:
		bot_bpm_slider.add_theme_stylebox_override("grabber_area", StudioSkin.surface(chosen_color, chosen_color, 2))
	if bg_opacity_slider != null:
		bg_opacity_slider.add_theme_stylebox_override("grabber_area", StudioSkin.surface(chosen_color, chosen_color, 2))
	if next_step != null:
		next_step.add_theme_color_override("font_color", chosen_color)
	if progress != null:
		progress.add_theme_stylebox_override("fill", StudioSkin.surface(chosen_color, chosen_color, 2))
	if channel_field != null:
		channel_field.add_theme_stylebox_override("focus", StudioSkin.surface(Color("#11151c"), chosen_color))
	if subtitle_field != null:
		subtitle_field.add_theme_stylebox_override("focus", StudioSkin.surface(Color("#11151c"), chosen_color))
	for key in instrument_buttons:
		StudioSkin.instrument_button(instrument_buttons[key], key == current_instrument, chosen_color)
	for key in reverb_buttons:
		StudioSkin.instrument_button(reverb_buttons[key], key == current_reverb_preset, chosen_color)
	for key in bar_style_buttons:
		StudioSkin.instrument_button(bar_style_buttons[key], key == current_bar_style, chosen_color)
	for key in light_mode_buttons:
		StudioSkin.instrument_button(light_mode_buttons[key], key == current_light_mode, chosen_color)
	_refresh_creator_styles()

func _emit_appearance() -> void:
	chosen_color = color_picker.color
	_sync_accent_widgets()
	if rhythm_flash_toggle != null:
		rhythm_flash_toggle.set_pressed_no_signal(current_light_mode != "off")
	appearance_changed.emit(chosen_color, rainbow_toggle.button_pressed, current_light_mode)

func editing_input() -> bool:
	var creator_focused = (channel_field != null and channel_field.has_focus()) or (subtitle_field != null and subtitle_field.has_focus())
	return (drawer.visible and section == "conversion") or search_field.has_focus() or song_list.has_focus() or color_picker.get_popup().visible or creator_focused

func show_section(id: String, toggle: bool = true) -> void:
	var hide_current = toggle and drawer.visible and section == id
	if not pages.has(id):
		return
	section = id
	for key in pages:
		pages[key].visible = key == section
	section_title.text = {"library": "Tu biblioteca", "sheet": "Atril · tu interpretación", "appearance": "Tu estudio", "conversion": "MIDI → tu próxima interpretación"}[id]
	section_hint.text = {"library": "Encuentra tu próxima interpretación", "sheet": "Importa, prepara y toca a tu ritmo", "appearance": "Dale tu carácter al sonido y a la luz", "conversion": "Importa · simplifica · edita · toca"}[id]
	drawer.visible = not hide_current if toggle else false
	_update_nav_styles()

func arrange(view_size: Vector2, keyboard_top: float) -> void:
	var narrow = view_size.x < 500.0
	menu_height = 144.0 if narrow else 112.0
	position = Vector2.ZERO
	size = Vector2(view_size.x, menu_height)
	var left = 10.0
	var width = view_size.x - 20.0
	island.position = Vector2(left, 8)
	island.size = Vector2(width, menu_height - 16)
	piano_icon.position = Vector2(left + 16, 25)
	piano_icon.size = Vector2(20, 15)
	header.position = Vector2(left + 45, 18)
	header.size = Vector2(100 if narrow else 140, 22)
	header.add_theme_font_size_override("font_size", 13 if narrow else 15)
	song_chip_panel.visible = view_size.x >= 700
	song_chip_panel.position = Vector2(left + 182, 16)
	song_chip_panel.size = Vector2(clampf(width - 394, 0, 420), 28)
	song_title.visible = view_size.x >= 700
	song_title.position = Vector2(left + 190, 18)
	song_title.size = Vector2(clampf(width - 410, 0, 400), 24)
	song_title.add_theme_font_size_override("font_size", 13)
	var right = left + width - 16
	volume_label.position = Vector2(right - 42, 20)
	volume_label.size = Vector2(42, 22)
	volume_label.add_theme_font_size_override("font_size", 13)
	var slider_width = 58.0 if narrow else 108.0
	volume_slider.position = Vector2(right - 50 - slider_width, 19)
	volume_slider.size = Vector2(slider_width, 24)
	speaker_icon.position = Vector2(right - 70 - slider_width, 24)
	speaker_icon.size = Vector2(14, 14)
	segmented_panel.hide()
	var nav_width = (width - 32) / 3.0 if narrow else minf(116, (width - 268) / 3.0)
	for i in range(3):
		var item = buttons[["library", "sheet", "appearance"][i]]
		item.position = Vector2(left + 12 + i * nav_width, 68)
		item.size = Vector2(nav_width - 4, 32)
		item.add_theme_font_size_override("font_size", 12 if view_size.x < 700 else 14)
	var controls_y = 104.0 if narrow else 68.0
	buttons.sustain.position = Vector2(left + 12 if narrow else right - 234, controls_y)
	buttons.sustain.size = Vector2(108, 30 if narrow else 32)
	buttons.auto.position = Vector2(left + 128 if narrow else right - 118, controls_y)
	buttons.auto.size = Vector2(118, 30 if narrow else 32)
	led_dot.position = Vector2(7, 11)
	play_icon.position = Vector2(7, 10)
	var drawer_width = minf(1000.0, view_size.x - 28)
	var drawer_top = menu_height + 8
	var max_h = maxf(0, keyboard_top - drawer_top - 12)
	drawer.position = Vector2((view_size.x - drawer_width) / 2, drawer_top)
	drawer.size = Vector2(drawer_width, minf(580, max_h))
	section_title.position = Vector2(20, 14)
	section_title.size = Vector2(drawer.size.x - 132, 30)
	close_button.position = Vector2(drawer.size.x - 108, 14)
	close_button.size = Vector2(88, 30)
	section_hint.visible = drawer.size.y >= 340
	section_hint.position = Vector2(20, 44)
	section_hint.size = Vector2(drawer.size.x - 40, 20)
	var content_y = 78 if section_hint.visible else 58
	body_scroll.position = Vector2(20, content_y)
	body_scroll.size = Vector2(drawer.size.x - 40, maxf(0, drawer.size.y - content_y - 18))
