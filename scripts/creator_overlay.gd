# SwiftPiano
# Copyright (c) 2026 Sebastián Zambrano
# Distributed under the terms of the MIT License.

extends Control
const Parser = preload("res://scripts/sheet_parser.gd")
const Keymap = preload("res://scripts/keymap_data.gd")

const PREV_ALPHAS: Array[float] = [0.12, 0.22, 0.36]
const NEXT_ALPHAS: Array[float] = [0.95, 0.72, 0.52, 0.36, 0.22]

var active_color: Color = Color("#64e8d0")
var zen_mode: bool = false
var menu_height: float = 112.0

# Component A: BrandingCard state & nodes
var branding_enabled: bool = true
var branding_position: String = "top_left" # "top_left", "top_right", "bottom_above_keys"
var channel_text: String = "@DragonCxbas"
var song_text: String = "Interpretación en Vivo"
var subtitle_text: String = "Virtual Piano Sheet in Description"

var branding_card: PanelContainer
var branding_style: StyleBoxFlat
var accent_pill: Panel
var accent_pill_style: StyleBoxFlat
var channel_label: Label
var song_label: Label
var subtitle_label: Label
var branding_target_pos: Vector2 = Vector2(28, 128)
var _branding_tween: Tween
var _pill_tween: Tween

# Component B: LiveSheetHUD state & nodes
var hud_enabled: bool = true
var hud_position: String = "top_center" # "top_center", "above_piano"
var steps: Array = []
var step_index: int = 0
var live_tokens: Array[String] = []
var _last_live_msec: int = -1000
var _last_live_notes: Array[int] = []

var hud_panel: PanelContainer
var hud_style: StyleBoxFlat
var prev_labels: Array[Label] = []
var current_step_panel: PanelContainer
var current_step_style: StyleBoxFlat
var current_step_label: Label
var next_labels: Array[Label] = []
var hud_target_pos: Vector2 = Vector2.ZERO
var _hud_pos_tween: Tween
var _step_pulse_tween: Tween

# Component C: ShortsFrameMode (9:16)
var shorts_mode: bool = false
var shorts_rect: Rect2 = Rect2()

# Component D: KPS & Combo HUD (Performance Meter)
const FIRE_COLOR: Color = Color("#FF6B35")
var kps_hud_enabled: bool = true
var kps_timestamps: Array[int] = []
var current_kps: int = 0
var combo_count: int = 0
var combo_idle_sec: float = 0.0
var _last_combo_msec: int = -1
var kps_card: PanelContainer
var kps_style: StyleBoxFlat
var kps_value_label: Label
var kps_unit_label: Label
var combo_value_label: Label
var combo_unit_label: Label
var kps_target_pos: Vector2 = Vector2.ZERO
var _kps_pos_tween: Tween
var _combo_pulse_tween: Tween

# Component E: Internal Audio Recorder Indicator (● REC)
var is_recording: bool = false
var rec_elapsed_sec: float = 0.0
var rec_badge: PanelContainer
var rec_style: StyleBoxFlat
var rec_label: Label

# Zen Mode Micro-Toast
var zen_toast: PanelContainer
var zen_toast_style: StyleBoxFlat
var zen_toast_label: Label
var _toast_tween: Tween

var bold_font: FontVariation
var main_ref: Control = null
var overlay_size: Vector2 = Vector2(1600, 900)
var _synced_step_index: int = -1
var _synced_steps_count: int = -1

func _init() -> void:
	name = "CreatorOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	bold_font = FontVariation.new()
	bold_font.base_font = ThemeDB.fallback_font
	bold_font.variation_embolden = 0.45
	
	_build_branding_card()
	_build_live_sheet_hud()
	_build_kps_combo_hud()
	_build_rec_indicator()
	_build_zen_toast()
	_apply_accent_colors()
	_refresh_hud_tokens(false)
	_refresh_kps_combo_labels()
	resized.connect(func(): arrange(size, menu_height, false))
	arrange(size, menu_height, false)

func _effective_size() -> Vector2:
	if overlay_size.x > 0.0 and overlay_size.y > 0.0:
		return overlay_size
	return size

func _exit_tree() -> void:
	main_ref = null
	for tw in [_branding_tween, _pill_tween, _hud_pos_tween, _step_pulse_tween, _toast_tween, _kps_pos_tween, _combo_pulse_tween]:
		if tw != null and tw.is_valid():
			tw.kill()
	_branding_tween = null
	_pill_tween = null
	_hud_pos_tween = null
	_step_pulse_tween = null
	_toast_tween = null
	_kps_pos_tween = null
	_combo_pulse_tween = null
	bold_font = null

func _process(delta: float) -> void:
	if main_ref != null:
		if main_ref.steps.size() != _synced_steps_count or main_ref.step_index != _synced_step_index:
			var step_changed = (main_ref.step_index != _synced_step_index and main_ref.steps.size() == _synced_steps_count)
			update_steps(main_ref.steps, main_ref.step_index, step_changed)
	_update_kps_and_combo(delta)
	if is_recording and rec_badge != null:
		rec_elapsed_sec += delta
		var pulse = 0.45 + 0.55 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.01))
		if rec_label != null:
			rec_label.modulate.a = pulse
			var mins = int(rec_elapsed_sec) / 60
			var secs = int(rec_elapsed_sec) % 60
			rec_label.text = "● REC  %02d:%02d" % [mins, secs]

func _build_branding_card() -> void:
	branding_card = PanelContainer.new()
	branding_card.name = "BrandingCard"
	branding_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	branding_style = StyleBoxFlat.new()
	branding_style.bg_color = Color(0.05, 0.06, 0.09, 0.74)
	branding_style.set_corner_radius_all(12)
	branding_style.set_border_width_all(1)
	branding_style.border_color = Color(active_color.r, active_color.g, active_color.b, 0.45)
	branding_style.shadow_size = 10
	branding_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	branding_style.shadow_offset = Vector2(0, 4)
	branding_style.content_margin_left = 12
	branding_style.content_margin_right = 16
	branding_style.content_margin_top = 10
	branding_style.content_margin_bottom = 10
	branding_card.add_theme_stylebox_override("panel", branding_style)
	add_child(branding_card)
	
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 12)
	branding_card.add_child(hbox)
	
	accent_pill = Panel.new()
	accent_pill.name = "AccentPill"
	accent_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	accent_pill.custom_minimum_size = Vector2(4, 46)
	accent_pill_style = StyleBoxFlat.new()
	accent_pill_style.bg_color = active_color
	accent_pill_style.set_corner_radius_all(2)
	accent_pill.add_theme_stylebox_override("panel", accent_pill_style)
	hbox.add_child(accent_pill)
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)
	
	channel_label = Label.new()
	channel_label.name = "ChannelLabel"
	channel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	channel_label.text = channel_text
	channel_label.add_theme_font_override("font", bold_font)
	channel_label.add_theme_font_size_override("font_size", 16)
	channel_label.add_theme_color_override("font_color", Color("#F4F6FF"))
	vbox.add_child(channel_label)
	
	song_label = Label.new()
	song_label.name = "SongLabel"
	song_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	song_label.text = song_text
	song_label.add_theme_font_size_override("font_size", 14)
	song_label.add_theme_color_override("font_color", Color("#C6D0F5"))
	vbox.add_child(song_label)
	
	subtitle_label = Label.new()
	subtitle_label.name = "SubtitleLabel"
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_label.text = subtitle_text
	subtitle_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(subtitle_label)

func _build_live_sheet_hud() -> void:
	hud_panel = PanelContainer.new()
	hud_panel.name = "LiveSheetHUD"
	hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	hud_style = StyleBoxFlat.new()
	hud_style.bg_color = Color(0.05, 0.06, 0.09, 0.82)
	hud_style.set_corner_radius_all(14)
	hud_style.set_border_width_all(1)
	hud_style.border_color = Color(active_color.r, active_color.g, active_color.b, 0.40)
	hud_style.shadow_size = 10
	hud_style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	hud_style.shadow_offset = Vector2(0, 4)
	hud_style.content_margin_left = 16
	hud_style.content_margin_right = 16
	hud_style.content_margin_top = 6
	hud_style.content_margin_bottom = 8
	hud_panel.add_theme_stylebox_override("panel", hud_style)
	hud_panel.draw.connect(_draw_hud_progress)
	add_child(hud_panel)
	
	var inner = Control.new()
	inner.name = "HudInner"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.clip_contents = true
	hud_panel.add_child(inner)
	
	# Current step capsule (step_index) - mathematically locked to exact center of inner
	current_step_panel = PanelContainer.new()
	current_step_panel.name = "CurrentStepCapsule"
	current_step_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	current_step_style = StyleBoxFlat.new()
	current_step_style.bg_color = Color(active_color.r, active_color.g, active_color.b, 0.24)
	current_step_style.border_color = Color(active_color.r, active_color.g, active_color.b, 0.95)
	current_step_style.set_border_width_all(1)
	current_step_style.set_corner_radius_all(8)
	current_step_style.content_margin_left = 12
	current_step_style.content_margin_right = 12
	current_step_style.content_margin_top = 3
	current_step_style.content_margin_bottom = 3
	current_step_panel.add_theme_stylebox_override("panel", current_step_style)
	current_step_panel.custom_minimum_size = Vector2(88.0, 34.0)
	current_step_panel.anchor_left = 0.5
	current_step_panel.anchor_right = 0.5
	current_step_panel.anchor_top = 0.5
	current_step_panel.anchor_bottom = 0.5
	current_step_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	current_step_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	inner.add_child(current_step_panel)
	
	current_step_label = Label.new()
	current_step_label.name = "CurrentStepLabel"
	current_step_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	current_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	current_step_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	current_step_label.add_theme_font_override("font", bold_font)
	current_step_label.add_theme_font_size_override("font_size", 19)
	current_step_label.add_theme_color_override("font_color", Color("#FFFFFF"))
	current_step_panel.add_child(current_step_label)
	
	# Left container for 3 previous steps (anchored 0.0 to 0.5, ending before center capsule)
	var left_box = HBoxContainer.new()
	left_box.name = "PrevStepsBox"
	left_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_box.anchor_left = 0.0
	left_box.anchor_right = 0.5
	left_box.anchor_top = 0.0
	left_box.anchor_bottom = 1.0
	left_box.offset_right = -50.0
	left_box.alignment = BoxContainer.ALIGNMENT_END
	left_box.add_theme_constant_override("separation", 8)
	inner.add_child(left_box)
	
	prev_labels.clear()
	for i in range(3):
		var lbl = Label.new()
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.72, 0.80, 0.90, PREV_ALPHAS[i]))
		left_box.add_child(lbl)
		prev_labels.append(lbl)
	
	# Right container for 5 upcoming steps (anchored 0.5 to 1.0, starting after center capsule)
	var right_box = HBoxContainer.new()
	right_box.name = "NextStepsBox"
	right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_box.anchor_left = 0.5
	right_box.anchor_right = 1.0
	right_box.anchor_top = 0.0
	right_box.anchor_bottom = 1.0
	right_box.offset_left = 50.0
	right_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	right_box.add_theme_constant_override("separation", 8)
	inner.add_child(right_box)
	
	next_labels.clear()
	for i in range(5):
		var lbl = Label.new()
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 16 if i == 0 else (15 - i))
		lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, NEXT_ALPHAS[i]))
		right_box.add_child(lbl)
		next_labels.append(lbl)

func _build_kps_combo_hud() -> void:
	kps_card = PanelContainer.new()
	kps_card.name = "KpsComboHUD"
	kps_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	kps_style = StyleBoxFlat.new()
	kps_style.bg_color = Color(0.05, 0.06, 0.09, 0.74)
	kps_style.set_corner_radius_all(12)
	kps_style.set_border_width_all(1)
	kps_style.border_color = Color(active_color.r, active_color.g, active_color.b, 0.45)
	kps_style.shadow_size = 10
	kps_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	kps_style.shadow_offset = Vector2(0, 4)
	kps_style.content_margin_left = 14
	kps_style.content_margin_right = 14
	kps_style.content_margin_top = 8
	kps_style.content_margin_bottom = 8
	kps_card.add_theme_stylebox_override("panel", kps_style)
	add_child(kps_card)
	
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 14)
	kps_card.add_child(hbox)
	
	# KPS Column
	var kps_vbox = VBoxContainer.new()
	kps_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kps_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	kps_vbox.add_theme_constant_override("separation", 0)
	hbox.add_child(kps_vbox)
	
	kps_value_label = Label.new()
	kps_value_label.name = "KpsValueLabel"
	kps_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kps_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kps_value_label.text = "0"
	kps_value_label.add_theme_font_override("font", bold_font)
	kps_value_label.add_theme_font_size_override("font_size", 18)
	kps_value_label.add_theme_color_override("font_color", Color("#F4F6FF"))
	kps_vbox.add_child(kps_value_label)
	
	kps_unit_label = Label.new()
	kps_unit_label.name = "KpsUnitLabel"
	kps_unit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kps_unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kps_unit_label.text = "KPS"
	kps_unit_label.add_theme_font_size_override("font_size", 10)
	kps_unit_label.add_theme_color_override("font_color", Color("#9CB6C7"))
	kps_vbox.add_child(kps_unit_label)
	
	var vsep = VSeparator.new()
	vsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vsep)
	
	# Combo Column
	var combo_vbox = VBoxContainer.new()
	combo_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	combo_vbox.add_theme_constant_override("separation", 0)
	hbox.add_child(combo_vbox)
	
	combo_value_label = Label.new()
	combo_value_label.name = "ComboValueLabel"
	combo_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_value_label.text = "0x"
	combo_value_label.add_theme_font_override("font", bold_font)
	combo_value_label.add_theme_font_size_override("font_size", 18)
	combo_value_label.add_theme_color_override("font_color", Color("#F4F6FF"))
	combo_vbox.add_child(combo_value_label)
	
	combo_unit_label = Label.new()
	combo_unit_label.name = "ComboUnitLabel"
	combo_unit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_unit_label.text = "COMBO"
	combo_unit_label.add_theme_font_size_override("font_size", 10)
	combo_unit_label.add_theme_color_override("font_color", Color("#9CB6C7"))
	combo_vbox.add_child(combo_unit_label)

func _build_rec_indicator() -> void:
	rec_badge = PanelContainer.new()
	rec_badge.name = "RecIndicator"
	rec_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rec_badge.visible = false
	
	rec_style = StyleBoxFlat.new()
	rec_style.bg_color = Color(0.16, 0.03, 0.05, 0.88)
	rec_style.set_corner_radius_all(14)
	rec_style.set_border_width_all(1)
	rec_style.border_color = Color(1.0, 0.22, 0.28, 0.90)
	rec_style.shadow_size = 8
	rec_style.shadow_color = Color(0.95, 0.10, 0.18, 0.35)
	rec_style.content_margin_left = 14
	rec_style.content_margin_right = 14
	rec_style.content_margin_top = 5
	rec_style.content_margin_bottom = 5
	rec_badge.add_theme_stylebox_override("panel", rec_style)
	add_child(rec_badge)
	
	rec_label = Label.new()
	rec_label.name = "RecLabel"
	rec_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rec_label.text = "● REC  00:00"
	rec_label.add_theme_font_override("font", bold_font)
	rec_label.add_theme_font_size_override("font_size", 13)
	rec_label.add_theme_color_override("font_color", Color("#FF3B47"))
	rec_badge.add_child(rec_label)

func _build_zen_toast() -> void:
	zen_toast = PanelContainer.new()
	zen_toast.name = "ZenToast"
	zen_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zen_toast.visible = false
	zen_toast.modulate.a = 0.0
	
	zen_toast_style = StyleBoxFlat.new()
	zen_toast_style.bg_color = Color(0.04, 0.05, 0.08, 0.86)
	zen_toast_style.set_corner_radius_all(18)
	zen_toast_style.set_border_width_all(1)
	zen_toast_style.border_color = Color(active_color.r, active_color.g, active_color.b, 0.55)
	zen_toast_style.content_margin_left = 18
	zen_toast_style.content_margin_right = 18
	zen_toast_style.content_margin_top = 7
	zen_toast_style.content_margin_bottom = 7
	zen_toast.add_theme_stylebox_override("panel", zen_toast_style)
	add_child(zen_toast)
	
	zen_toast_label = Label.new()
	zen_toast_label.name = "ZenToastLabel"
	zen_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zen_toast_label.text = "Modo Grabación Activo • [|] o [Esc] para mostrar menú"
	zen_toast_label.add_theme_font_size_override("font_size", 12)
	zen_toast_label.add_theme_color_override("font_color", Color("#F4F6FF"))
	zen_toast.add_child(zen_toast_label)

func _draw_hud_progress() -> void:
	if hud_panel == null:
		return
	var w = hud_panel.size.x
	var h = hud_panel.size.y
	var pad = 12.0
	var bar_w = maxf(0.0, w - pad * 2.0)
	var bar_y = h - 3.0
	hud_panel.draw_rect(Rect2(pad, bar_y, bar_w, 2.0), Color(1.0, 1.0, 1.0, 0.09), true)
	var ratio = 0.0
	if not steps.is_empty():
		ratio = clampf(float(step_index) / float(maxi(1, steps.size())), 0.0, 1.0)
	elif not live_tokens.is_empty():
		ratio = 1.0
	if ratio > 0.0:
		hud_panel.draw_rect(Rect2(pad, bar_y, bar_w * ratio, 2.0), Color(active_color.r, active_color.g, active_color.b, 0.92), true)

func set_active_color(color: Color) -> void:
	active_color = Color(color.r, color.g, color.b, 1.0)
	_apply_accent_colors()
	queue_redraw()
	if hud_panel != null:
		hud_panel.queue_redraw()

func _apply_accent_colors() -> void:
	if branding_style != null:
		branding_style.border_color = Color(active_color.r, active_color.g, active_color.b, 0.45)
	if accent_pill_style != null:
		accent_pill_style.bg_color = active_color
	if subtitle_label != null:
		var light_accent = active_color.lightened(0.32)
		subtitle_label.add_theme_color_override("font_color", Color(light_accent.r, light_accent.g, light_accent.b, 0.85))
	if hud_style != null:
		hud_style.border_color = Color(active_color.r, active_color.g, active_color.b, 0.40)
	if current_step_style != null:
		current_step_style.bg_color = Color(active_color.r, active_color.g, active_color.b, 0.22)
		current_step_style.border_color = Color(active_color.r, active_color.g, active_color.b, 0.90)
	if zen_toast_style != null:
		zen_toast_style.border_color = Color(active_color.r, active_color.g, active_color.b, 0.55)
	_refresh_kps_combo_labels()

func set_kps_hud_enabled(enabled: bool) -> void:
	kps_hud_enabled = enabled
	if kps_card != null:
		kps_card.visible = kps_hud_enabled
	arrange(_effective_size(), menu_height, true)

func set_recording_state(active: bool) -> void:
	is_recording = active
	rec_elapsed_sec = 0.0
	if rec_badge != null:
		rec_badge.visible = is_recording
	if rec_label != null:
		rec_label.modulate.a = 1.0
		rec_label.text = "● REC  00:00"
	_layout_rec_badge()

func _update_kps_and_combo(delta: float) -> void:
	var now_ms = Time.get_ticks_msec()
	var changed = false
	while not kps_timestamps.is_empty() and (now_ms - kps_timestamps[0]) > 1000:
		kps_timestamps.pop_front()
		changed = true
	if current_kps != kps_timestamps.size():
		current_kps = kps_timestamps.size()
		changed = true
	if combo_count > 0:
		combo_idle_sec += delta
		var ms_elapsed = (now_ms - _last_combo_msec) if _last_combo_msec >= 0 else 0
		if combo_idle_sec > 1.8 or ms_elapsed > 1800:
			combo_count = 0
			combo_idle_sec = 0.0
			changed = true
	if changed:
		_refresh_kps_combo_labels()

func advance_combo_idle(seconds: float) -> void:
	_update_kps_and_combo(seconds)

func _refresh_kps_combo_labels() -> void:
	var is_fire = current_kps > 8
	var kps_col = FIRE_COLOR if is_fire else Color("#F4F6FF")
	if kps_value_label != null:
		kps_value_label.text = str(current_kps)
		kps_value_label.add_theme_color_override("font_color", kps_col)
	if kps_unit_label != null:
		kps_unit_label.add_theme_color_override("font_color", FIRE_COLOR.lightened(0.2) if is_fire else Color("#9CB6C7"))
	if combo_value_label != null:
		combo_value_label.text = "%dx" % combo_count
		var combo_col = active_color.lightened(0.25) if combo_count >= 10 else Color("#F4F6FF")
		combo_value_label.add_theme_color_override("font_color", combo_col)
	if kps_style != null:
		kps_style.border_color = Color(FIRE_COLOR.r, FIRE_COLOR.g, FIRE_COLOR.b, 0.78) if is_fire else Color(active_color.r, active_color.g, active_color.b, 0.45)

func set_channel_text(value: String) -> void:
	channel_text = value if not value.strip_edges().is_empty() else "@DragonCxbas"
	if channel_label != null:
		channel_label.text = channel_text
	arrange(_effective_size(), menu_height, false)

func set_song_title(value: String) -> void:
	var cleaned = value.strip_edges()
	if cleaned.is_empty() or cleaned.ends_with("/  88 Teclas"):
		song_text = "Interpretación en Vivo"
	else:
		song_text = cleaned
	if song_label != null:
		song_label.text = song_text
	arrange(_effective_size(), menu_height, false)

func set_subtitle_text(value: String) -> void:
	subtitle_text = value if not value.strip_edges().is_empty() else "Virtual Piano Sheet in Description"
	if subtitle_label != null:
		subtitle_label.text = subtitle_text
	arrange(_effective_size(), menu_height, false)

func set_branding_config(enabled: bool, pos: String = "") -> void:
	if not pos.is_empty():
		if pos == "hidden":
			branding_enabled = false
		else:
			branding_position = pos
			branding_enabled = enabled
	else:
		branding_enabled = enabled
	if branding_card != null:
		branding_card.visible = branding_enabled
	arrange(_effective_size(), menu_height, true)

func set_hud_config(enabled: bool, pos: String = "") -> void:
	if not pos.is_empty():
		if pos == "hidden":
			hud_enabled = false
		else:
			hud_position = pos
			hud_enabled = enabled
	else:
		hud_enabled = enabled
	if hud_panel != null:
		hud_panel.visible = hud_enabled
	arrange(_effective_size(), menu_height, true)

func set_shorts_mode(enabled: bool) -> void:
	shorts_mode = enabled
	arrange(_effective_size(), menu_height, false)
	queue_redraw()

func set_zen_mode(enabled: bool, current_menu_height: float = 112.0, show_toast: bool = true) -> void:
	var entering_zen = enabled and not zen_mode
	zen_mode = enabled
	menu_height = current_menu_height
	arrange(_effective_size(), menu_height, true)
	if entering_zen and show_toast:
		trigger_zen_toast()
	elif not zen_mode and zen_toast != null:
		if _toast_tween != null and _toast_tween.is_valid():
			_toast_tween.kill()
		zen_toast.modulate.a = 0.0
		zen_toast.visible = false

func trigger_zen_toast() -> void:
	if zen_toast == null:
		return
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	zen_toast.visible = true
	zen_toast.modulate.a = 1.0
	_position_zen_toast()
	if is_inside_tree():
		_toast_tween = create_tween()
		_toast_tween.tween_interval(1.1)
		_toast_tween.tween_property(zen_toast, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_toast_tween.tween_callback(func():
			zen_toast.modulate.a = 0.0
			zen_toast.visible = false)

func on_note_triggered(pitches: Array = []) -> void:
	var now_ms = Time.get_ticks_msec()
	# 0. Update KPS (1000ms sliding window) & Combo counter
	var note_count = maxi(1, pitches.size())
	for _i in range(note_count):
		kps_timestamps.append(now_ms)
	while not kps_timestamps.is_empty() and (now_ms - kps_timestamps[0]) > 1000:
		kps_timestamps.pop_front()
	current_kps = kps_timestamps.size()
	if _last_combo_msec >= 0 and (combo_idle_sec > 1.8 or (now_ms - _last_combo_msec) > 1800):
		combo_count = 0
	combo_count += note_count
	combo_idle_sec = 0.0
	_last_combo_msec = now_ms
	_refresh_kps_combo_labels()

	# 1. Subtle brightness & scale pulse on BrandingCard left pill
	if accent_pill != null and branding_enabled:
		accent_pill.pivot_offset = accent_pill.size * 0.5
		accent_pill.modulate = Color(1.55, 1.55, 1.55, 1.0)
		accent_pill.scale = Vector2(1.25, 1.08)
		if is_inside_tree():
			if _pill_tween != null and _pill_tween.is_valid():
				_pill_tween.kill()
			_pill_tween = create_tween().set_parallel(true)
			_pill_tween.tween_property(accent_pill, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_pill_tween.tween_property(accent_pill, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 2. If in free improvisation mode (steps is empty), record live token for LiveSheetHUD
	if steps.is_empty() and not pitches.is_empty():
		if now_ms - _last_live_msec <= 55 and not live_tokens.is_empty():
			for p in pitches:
				if not _last_live_notes.has(int(p)):
					_last_live_notes.append(int(p))
			live_tokens[-1] = Parser.format_notes(_last_live_notes)
		else:
			_last_live_notes.clear()
			for p in pitches:
				if not _last_live_notes.has(int(p)):
					_last_live_notes.append(int(p))
			live_tokens.append(Parser.format_notes(_last_live_notes))
			if live_tokens.size() > 16:
				live_tokens.pop_front()
		_last_live_msec = now_ms
		_refresh_hud_tokens(true)

static func format_step_token(step: Dictionary) -> String:
	return Parser.format_step(step)

func get_step_token(index: int) -> String:
	if index < 0 or index >= steps.size():
		return ""
	return Parser.format_step(steps[index])

func get_current_token() -> String:
	if current_step_label == null:
		return ""
	return current_step_label.text

func update_steps(new_steps: Array, new_index: int = 0, animate_pulse: bool = false) -> void:
	steps = new_steps
	step_index = clampi(new_index, 0, maxi(0, steps.size() - 1)) if not steps.is_empty() else 0
	_synced_steps_count = steps.size()
	_synced_step_index = new_index
	_refresh_hud_tokens(animate_pulse)

func set_step_index(new_index: int, animate_pulse: bool = true) -> void:
	step_index = clampi(new_index, 0, maxi(0, steps.size() - 1)) if not steps.is_empty() else 0
	_synced_step_index = new_index
	_refresh_hud_tokens(animate_pulse)

func _refresh_hud_tokens(animate_pulse: bool = false) -> void:
	if current_step_label == null:
		return
	if not steps.is_empty():
		var idx = clampi(step_index, 0, steps.size() - 1)
		for i in range(3):
			var p_idx = idx - (3 - i)
			if p_idx >= 0 and p_idx < steps.size():
				prev_labels[i].text = get_step_token(p_idx)
				prev_labels[i].visible = true
			else:
				prev_labels[i].text = ""
				prev_labels[i].visible = false
		
		current_step_label.text = get_step_token(idx)
		
		for i in range(5):
			var n_idx = idx + (i + 1)
			if n_idx >= 0 and n_idx < steps.size():
				next_labels[i].text = get_step_token(n_idx)
				next_labels[i].visible = true
			else:
				next_labels[i].text = ""
				next_labels[i].visible = false
	else:
		# Free improvisation mode
		var total_live = live_tokens.size()
		for i in range(3):
			var l_idx = (total_live - 1) - (3 - i)
			if l_idx >= 0 and l_idx < total_live:
				prev_labels[i].text = live_tokens[l_idx]
				prev_labels[i].visible = true
			else:
				prev_labels[i].text = ""
				prev_labels[i].visible = false
		current_step_label.text = live_tokens[-1] if total_live > 0 else "🎹 En Vivo"
		for i in range(5):
			next_labels[i].text = ""
			next_labels[i].visible = false
	
	if animate_pulse and current_step_panel != null:
		current_step_panel.modulate = Color(1.5, 1.5, 1.5, 1.0)
		if is_inside_tree():
			if _step_pulse_tween != null and _step_pulse_tween.is_valid():
				_step_pulse_tween.kill()
			_step_pulse_tween = create_tween()
			_step_pulse_tween.tween_property(current_step_panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	if hud_panel != null:
		hud_panel.queue_redraw()

func get_shorts_rect(view_size: Vector2 = Vector2.ZERO) -> Rect2:
	var vs = view_size if (view_size.x > 0.0 and view_size.y > 0.0) else _effective_size()
	if shorts_mode and vs.x > vs.y and vs.y > 0.0:
		var shorts_width = vs.y * (9.0 / 16.0)
		var left_x = (vs.x - shorts_width) * 0.5
		return Rect2(left_x, 0.0, shorts_width, vs.y)
	return Rect2(0.0, 0.0, vs.x, vs.y)

func arrange(view_size: Vector2, current_menu_height: float = 112.0, animate: bool = false) -> void:
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	overlay_size = view_size
	menu_height = current_menu_height
	shorts_rect = get_shorts_rect(view_size)
	_layout_branding(animate)
	_layout_hud(animate)
	_layout_kps_hud(animate)
	_layout_rec_badge()
	_position_zen_toast()
	queue_redraw()

func _layout_branding(animate: bool = false) -> void:
	if branding_card == null:
		return
	var vs = _effective_size()
	branding_card.visible = branding_enabled
	branding_card.reset_size()
	var card_size = branding_card.get_combined_minimum_size()
	var frame = get_shorts_rect(vs)
	var is_shorts_active = shorts_mode and vs.x > vs.y
	if is_shorts_active:
		card_size.x = minf(card_size.x, maxf(140.0, frame.size.x - 24.0))
	branding_card.size = card_size
	
	var margin_x = 14.0 if is_shorts_active else 28.0
	var top_y = 24.0 if zen_mode else (menu_height + 16.0)
	var target = Vector2(frame.position.x + margin_x, top_y)
	
	match branding_position:
		"top_right":
			target = Vector2(frame.end.x - card_size.x - margin_x, top_y)
		"bottom_above_keys":
			target = Vector2(frame.position.x + margin_x, vs.y * 0.8 - card_size.y - 16.0)
		_:
			target = Vector2(frame.position.x + margin_x, top_y)
	
	branding_target_pos = target
	if animate and is_inside_tree():
		if _branding_tween != null and _branding_tween.is_valid():
			_branding_tween.kill()
		_branding_tween = create_tween()
		_branding_tween.tween_property(branding_card, "position", target, 0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		branding_card.position = target

func _layout_hud(animate: bool = false) -> void:
	if hud_panel == null:
		return
	var vs = _effective_size()
	hud_panel.visible = hud_enabled
	var frame = get_shorts_rect(vs)
	var is_shorts_active = shorts_mode and vs.x > vs.y
	
	var target_w = minf(560.0, vs.x - 32.0)
	if is_shorts_active:
		target_w = clampf(frame.size.x - 24.0, 260.0, 560.0)
	var target_h = 48.0
	hud_panel.custom_minimum_size = Vector2(target_w, target_h)
	hud_panel.size = Vector2(target_w, target_h)
	
	var center_x = frame.position.x + (frame.size.x - target_w) * 0.5
	var top_y = 24.0 if zen_mode else (menu_height + 16.0)
	if is_shorts_active and branding_enabled and branding_position in ["top_left", "top_right"]:
		top_y = branding_target_pos.y + branding_card.size.y + 10.0
	
	var target_y = (vs.y * 0.8 - 58.0) if hud_position == "above_piano" else top_y
	var target = Vector2(clampf(center_x, frame.position.x + 8.0, maxf(frame.position.x + 8.0, frame.end.x - target_w - 8.0)), target_y)
	hud_target_pos = target
	
	if animate and is_inside_tree():
		if _hud_pos_tween != null and _hud_pos_tween.is_valid():
			_hud_pos_tween.kill()
		_hud_pos_tween = create_tween()
		_hud_pos_tween.tween_property(hud_panel, "position", target, 0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		hud_panel.position = target

func _layout_kps_hud(animate: bool = false) -> void:
	if kps_card == null:
		return
	var vs = _effective_size()
	kps_card.visible = kps_hud_enabled
	kps_card.reset_size()
	var k_size = kps_card.get_combined_minimum_size()
	kps_card.size = k_size
	var frame = get_shorts_rect(vs)
	var is_shorts_active = shorts_mode and vs.x > vs.y
	var margin_x = 14.0 if is_shorts_active else 28.0
	var top_y = 24.0 if zen_mode else (menu_height + 16.0)
	var target = Vector2(frame.end.x - k_size.x - margin_x, top_y)
	if branding_enabled and branding_position == "top_right":
		target = Vector2(frame.position.x + margin_x, top_y)
	elif is_shorts_active and branding_enabled:
		target = Vector2(frame.end.x - k_size.x - margin_x, vs.y * 0.8 - k_size.y - 16.0)
	kps_target_pos = target
	if animate and is_inside_tree():
		if _kps_pos_tween != null and _kps_pos_tween.is_valid():
			_kps_pos_tween.kill()
		_kps_pos_tween = create_tween()
		_kps_pos_tween.tween_property(kps_card, "position", target, 0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		kps_card.position = target

func _layout_rec_badge() -> void:
	if rec_badge == null:
		return
	var vs = _effective_size()
	rec_badge.visible = is_recording
	rec_badge.reset_size()
	var r_size = rec_badge.get_combined_minimum_size()
	rec_badge.size = r_size
	var frame = get_shorts_rect(vs)
	var is_shorts_active = shorts_mode and vs.x > vs.y
	var margin_x = 14.0 if is_shorts_active else 28.0
	var top_y = 24.0 if zen_mode else (menu_height + 16.0)
	var rx = frame.end.x - r_size.x - margin_x
	var ry = top_y
	if kps_hud_enabled and kps_card != null:
		ry = kps_target_pos.y + kps_card.size.y + 8.0
		rx = kps_target_pos.x + (kps_card.size.x - r_size.x)
	rec_badge.position = Vector2(clampf(rx, frame.position.x + 8.0, maxf(frame.position.x + 8.0, frame.end.x - r_size.x - 8.0)), ry)

func _position_zen_toast() -> void:
	if zen_toast == null:
		return
	var vs = _effective_size()
	zen_toast.reset_size()
	var t_size = zen_toast.get_combined_minimum_size()
	zen_toast.size = t_size
	var frame = get_shorts_rect(vs)
	var tx = frame.position.x + (frame.size.x - t_size.x) * 0.5
	var ty = vs.y * 0.8 - t_size.y - 16.0
	if hud_enabled and hud_position == "above_piano":
		ty -= 54.0
	zen_toast.position = Vector2(tx, maxf(24.0, ty))

func _draw() -> void:
	var vs = _effective_size()
	if shorts_mode and vs.x > vs.y and vs.y > 0.0:
		var sr = get_shorts_rect(vs)
		var veil = Color(0.01, 0.01, 0.02, 0.78)
		if sr.position.x > 0.0:
			draw_rect(Rect2(0.0, 0.0, sr.position.x, vs.y), veil, true)
		if sr.end.x < vs.x:
			draw_rect(Rect2(sr.end.x, 0.0, vs.x - sr.end.x, vs.y), veil, true)
		var divider_col = Color(active_color.r, active_color.g, active_color.b, 0.35)
		draw_line(Vector2(sr.position.x, 0.0), Vector2(sr.position.x, vs.y), divider_col, 1.0)
		draw_line(Vector2(sr.end.x, 0.0), Vector2(sr.end.x, vs.y), divider_col, 1.0)
