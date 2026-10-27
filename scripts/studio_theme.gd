# SwiftPiano
# Copyright (c) 2026 Sebastián Zambrano
# Distributed under the terms of the MIT License.

extends RefCounted
## Shared native skin: graphite surfaces, ivory text and restrained mint accents.
const ACCENT = Color("#64e8d0")

static func surface(fill: Color, edge: Color, radius: int = 10) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14
	box.content_margin_right = 14
	return box

static func glass_panel(fill: Color = Color("#171b22"), edge: Color = Color("#333943"), radius: int = 18, shadow_size: int = 20) -> StyleBoxFlat:
	var box = surface(fill, edge, radius)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = shadow_size
	box.shadow_offset = Vector2(0, 8)
	return box

static func chip(fill: Color = Color("#20262e"), edge: Color = Color("#343c45"), radius: int = 8) -> StyleBoxFlat:
	var box = surface(fill, edge, radius)
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box

static func segmented_dock(radius: int = 10) -> StyleBoxFlat:
	return surface(Color("#10141b"), Color("#282e37"), radius)

static func _button(button: Button, active: bool, accent: Color, solid: bool = false) -> void:
	var state_key = "%d_%s_%d" % [1 if active else 0, accent.to_html(false), 1 if solid else 0]
	if button.has_meta("_skin_state") and button.get_meta("_skin_state") == state_key:
		return
	button.set_meta("_skin_state", state_key)
	var fill = accent if active and solid else Color("#263c3a") if active else Color("#222831")
	var edge = accent.darkened(0.35) if active else Color("#363e49")
	var normal = surface(fill, edge, 12)
	normal.shadow_color = Color(0, 0, 0, 0.18)
	normal.shadow_size = 3
	normal.shadow_offset = Vector2(0, 2)
	var hover = surface(fill.lightened(0.08), accent.lightened(0.12), 12)
	var pressed = surface(fill.darkened(0.10), accent)
	var focus = surface(Color(0, 0, 0, 0), accent)
	button.begin_bulk_theme_override()
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", surface(Color("#191e25"), Color("#292f38")))
	var ink = Color("#102c26") if active and solid else Color("#f0eee8")
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, ink)
	button.add_theme_color_override("font_disabled_color", Color("#69747e"))
	button.add_theme_font_size_override("font_size", 13)
	button.end_bulk_theme_override()

static func segment_button(button: Button, active: bool = false, accent: Color = ACCENT) -> void:
	button.remove_meta("_skin_state")
	_button(button, active, accent)
	button.begin_bulk_theme_override()
	for state in ["normal", "hover", "pressed"]:
		var box = button.get_theme_stylebox(state).duplicate()
		box.content_margin_left = 6
		box.content_margin_right = 6
		if not active and state == "normal":
			box.bg_color = Color(0, 0, 0, 0)
			box.border_color = Color(0, 0, 0, 0)
		button.add_theme_stylebox_override(state, box)
	button.end_bulk_theme_override()

static func sustain_button(button: Button, active: bool = false, accent: Color = ACCENT) -> void:
	button.remove_meta("_skin_state")
	_button(button, active, accent)
	_icon_padding(button, 19)

static func auto_button(button: Button, active: bool = false, accent: Color = ACCENT) -> void:
	button.remove_meta("_skin_state")
	_button(button, active, accent, true)
	_icon_padding(button, 23)

static func _icon_padding(button: Button, left: int) -> void:
	button.begin_bulk_theme_override()
	for state in ["normal", "hover", "pressed"]:
		var box = button.get_theme_stylebox(state).duplicate()
		box.content_margin_left = left
		box.content_margin_right = 6
		button.add_theme_stylebox_override(state, box)
	button.end_bulk_theme_override()

static func decorate(button: Button, primary: bool = false) -> void:
	_button(button, primary, ACCENT, primary)

static func instrument_button(button: Button, active: bool = false, accent: Color = ACCENT) -> void:
	var inst_key = "inst_%d_%s" % [1 if active else 0, accent.to_html(false)]
	if button.has_meta("_inst_skin_state") and button.get_meta("_inst_skin_state") == inst_key:
		return
	button.set_meta("_inst_skin_state", inst_key)
	button.remove_meta("_skin_state")
	_button(button, active, accent)
	button.clip_text = true
	button.tooltip_text = button.text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.begin_bulk_theme_override()
	for state in ["normal", "hover", "pressed"]:
		var box = button.get_theme_stylebox(state).duplicate()
		box.content_margin_top = 12
		box.content_margin_bottom = 12
		box.border_width_left = 3 if active else 1
		button.add_theme_stylebox_override(state, box)
	button.end_bulk_theme_override()
