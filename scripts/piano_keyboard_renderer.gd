extends Control
const Keymap = preload("res://scripts/keymap_data.gd")
signal mouse_note_changed(midi: int)
var key_rects: Dictionary = {}
var active: Dictionary = {}
var labels = Keymap.labels()
var qwerty_enabled = true
var dragging = false
var mouse_note = -1
var font: Font = ThemeDB.fallback_font
var active_color = Color("#64e8d0")
var note_colors: Dictionary = {}
var illumination: Dictionary = {}
var depression: Dictionary = {}
var key_range_mode: String = "full_88"
var visible_midi_range: Vector2i = Vector2i(21, 108)
var shorts_mode: bool = false
var horizontal_bounds: Vector2 = Vector2.ZERO

var key_glow_layer: Node2D
var gaussian_tex: ImageTexture

func set_key_range_mode(mode: String) -> void:
	match mode:
		"central_61":
			key_range_mode = "central_61"
			visible_midi_range = Vector2i(36, 96)
		"melodic_49", "shorts_focus", "shorts":
			key_range_mode = "melodic_49"
			visible_midi_range = Vector2i(48, 96)
		_:
			key_range_mode = "full_88"
			visible_midi_range = Vector2i(21, 108)
	rebuild()

static func _generate_gaussian_texture(size_px: int = 128) -> ImageTexture:
	var img = Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var half = float(size_px) * 0.5
	for y in range(size_px):
		for x in range(size_px):
			var dx = (float(x) - half + 0.5) / half
			var dy = (float(y) - half + 0.5) / half
			var r2 = dx * dx + dy * dy
			var alpha = 0.0
			if r2 < 1.0:
				alpha = exp(-r2 * 5.0)
				alpha *= clampf((1.0 - sqrt(r2)) / 0.25, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)

func recolor(color: Color) -> void:
	for midi in note_colors:
		note_colors[midi] = color
	_request_render()

func _request_render() -> void:
	queue_redraw()
	if key_glow_layer != null:
		key_glow_layer.queue_redraw()

func _process(delta: float) -> void:
	var changed = false
	if not illumination.is_empty():
		for midi in illumination.keys():
			var target = 1.0 if active.has(midi) else 0.0
			var value = move_toward(float(illumination[midi]), target, delta * 5.0)
			if not is_equal_approx(value, illumination[midi]):
				changed = true
			illumination[midi] = value
			if value <= 0:
				illumination.erase(midi)
				note_colors.erase(midi)
	
	if not depression.is_empty() or not active.is_empty():
		for midi in active.keys():
			if not depression.has(midi):
				depression[midi] = 0.0
		for midi in depression.keys():
			var target = 1.0 if active.has(midi) else 0.0
			var speed = 26.0 if target > 0.5 else 16.0
			var value = move_toward(float(depression[midi]), target, delta * speed)
			if not is_equal_approx(value, depression[midi]):
				changed = true
			depression[midi] = value
			if value <= 0.0 and not active.has(midi):
				depression.erase(midi)
				
	if changed:
		_request_render()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gaussian_tex = _generate_gaussian_texture(128)
	
	key_glow_layer = Node2D.new()
	var add_mat = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	key_glow_layer.material = add_mat
	key_glow_layer.draw.connect(_draw_key_glows)
	add_child(key_glow_layer)
	
	resized.connect(rebuild)
	rebuild()

func rebuild() -> void:
	key_rects.clear()
	var min_midi = clampi(visible_midi_range.x, 21, 108)
	var max_midi = clampi(visible_midi_range.y, min_midi, 108)
	var white_count = 0
	for midi in range(min_midi, max_midi + 1):
		if not Keymap.is_black(midi):
			white_count += 1
	white_count = maxi(1, white_count)
	var span_left = horizontal_bounds.x if horizontal_bounds.y > 0.0 else 0.0
	var span_width = horizontal_bounds.y if horizontal_bounds.y > 0.0 else size.x
	var width = span_width / float(white_count)
	var index = 0
	for midi in range(min_midi, max_midi + 1):
		if Keymap.is_black(midi):
			key_rects[midi] = Rect2(round(span_left + index * width - width * 0.31), 4, maxf(2, width * 0.62), maxf(1, (size.y - 4) * 0.63))
		else:
			var x = round(span_left + index * width)
			var next_x = round(span_left + (index + 1) * width)
			key_rects[midi] = Rect2(x, 4, next_x - x, maxf(1, size.y - 4))
			index += 1
	_request_render()

func hit_key(point: Vector2) -> int:
	for black in [true, false]:
		for midi in key_rects:
			if Keymap.is_black(midi) == black and key_rects[midi].has_point(point):
				return midi
	return -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		_change_mouse(hit_key(event.position) if dragging else -1)
		accept_event()

func _input(event: InputEvent) -> void:
	if not dragging:
		return
	if event is InputEventMouseMotion:
		_change_mouse(hit_key(get_local_mouse_position()))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		_change_mouse(-1)

func _change_mouse(midi: int) -> void:
	if midi != mouse_note:
		mouse_note = midi
		mouse_note_changed.emit(midi)

func press(midi: int, color: Color = active_color) -> void:
	active[midi] = active.get(midi, 0) + 1
	illumination[midi] = 1.0
	depression[midi] = maxf(depression.get(midi, 0.0), 0.85)
	note_colors[midi] = color
	_request_render()

func release(midi: int) -> void:
	if active.has(midi):
		active[midi] -= 1
		if active[midi] <= 0:
			active.erase(midi)
	_request_render()

func _draw() -> void:
	# 0. Wooden Keybed Frame Background (recess behind the keys)
	draw_rect(Rect2(0, 0, size.x, size.y), Color("#060a10"))
	
	# 0B. Concert Grand Red Velvet Damper Rail (Iconic Steinway/Yamaha acoustic red felt bushing)
	draw_rect(Rect2(0, 0, size.x, 5), Color("#7d1222"))
	draw_line(Vector2(0, 0.5), Vector2(size.x, 0.5), Color("#4a0812"), 1.0)
	draw_line(Vector2(0, 4.5), Vector2(size.x, 4.5), Color(0.85, 0.72, 0.38, 0.70), 1.0)
	
	# ---------------------------------------------------------
	# 1. WHITE KEYS (Acoustic Polished Ivory with Chamfered Corners & Depression Physics)
	# ---------------------------------------------------------
	for midi in key_rects:
		if Keymap.is_black(midi):
			continue
		var rect: Rect2 = key_rects[midi]
		var dep: float = depression.get(midi, 0.0)
		var light: float = illumination.get(midi, 0.0)
		
		# Physical depression travel (sinking lever mechanism)
		var travel_y = dep * 3.2
		var k_x = rect.position.x
		var k_w = rect.size.x
		var k_y = rect.position.y + travel_y * 0.35
		var k_h = rect.size.y - travel_y * 0.35
		
		# Felt compression above pressed key
		if dep > 0.05:
			draw_rect(Rect2(k_x, 0, k_w, 5), Color(0.32, 0.05, 0.09, dep * 0.75))
		
		# Base color: Ivory gradient darkening opaquely under mechanical pressure
		var ivory_top = Color("#f8f5eb")
		var ivory_mid = Color("#e8e5dc")
		var ivory_bot = Color("#c8c9c5")
		var pressed_slate = Color("#b6bcc6")
		
		var c_top = ivory_top.lerp(pressed_slate.darkened(0.06), dep)
		var c_mid = ivory_mid.lerp(pressed_slate, dep)
		var c_bot = ivory_bot.lerp(pressed_slate.darkened(0.12), dep)
		
		# Draw subtle 3-stop vertical gradient for realistic ivory curvature
		var half_h = k_h * 0.55
		# Top quad
		var pts_top = PackedVector2Array([
			Vector2(k_x, k_y),
			Vector2(k_x + k_w, k_y),
			Vector2(k_x + k_w, k_y + half_h),
			Vector2(k_x, k_y + half_h)
		])
		var cols_top = PackedColorArray([c_top, c_top, c_mid, c_mid])
		draw_polygon(pts_top, cols_top)
		
		# Bottom quad
		var pts_bot = PackedVector2Array([
			Vector2(k_x, k_y + half_h),
			Vector2(k_x + k_w, k_y + half_h),
			Vector2(k_x + k_w, k_y + k_h),
			Vector2(k_x, k_y + k_h)
		])
		var cols_bot = PackedColorArray([c_mid, c_mid, c_bot, c_bot])
		draw_polygon(pts_bot, cols_bot)
		
		# Bottom rounded corner chamfers
		draw_line(Vector2(k_x, k_y + k_h - 1.5), Vector2(k_x + 1.5, k_y + k_h), Color("#060a10"), 1.0)
		draw_line(Vector2(k_x + k_w, k_y + k_h - 1.5), Vector2(k_x + k_w - 1.5, k_y + k_h), Color("#060a10"), 1.0)
		
		# Tactile key edges: 1px specular left, 1.5px slit shadow right
		draw_line(Vector2(k_x + 0.5, k_y), Vector2(k_x + 0.5, k_y + k_h - 4), Color(1.0, 1.0, 1.0, 0.50 * (1.0 - dep * 0.45)), 1.0)
		draw_line(Vector2(k_x + k_w - 0.5, k_y), Vector2(k_x + k_w - 0.5, k_y + k_h), Color(0.04, 0.08, 0.14, 0.80 + dep * 0.20), 1.0)
		
		# Front lip (rounded chamfered bottom edge)
		var lip_h = maxf(2.5, 5.0 - dep * 1.5)
		var lip_r = Rect2(k_x + 1, k_y + k_h - lip_h, maxf(1, k_w - 2), lip_h)
		draw_rect(lip_r, c_bot.darkened(0.25 + dep * 0.15))
		draw_line(Vector2(k_x + 1, k_y + k_h - lip_h), Vector2(k_x + k_w - 1, k_y + k_h - lip_h), Color(0.0, 0.0, 0.0, 0.22 + dep * 0.20), 1.0)
		
		# Contact light gradient (Gouraud fade to 45% height)
		if light > 0.001:
			var tint: Color = note_colors.get(midi, active_color)
			var grad_h = k_h * 0.45
			var c_glow_top = Color(tint.r, tint.g, tint.b, light * 0.60)
			var c_glow_bot = Color(tint.r, tint.g, tint.b, 0.0)
			var g_pts = PackedVector2Array([
				Vector2(k_x + 1, k_y),
				Vector2(k_x + k_w - 1, k_y),
				Vector2(k_x + k_w - 1, k_y + grad_h),
				Vector2(k_x + 1, k_y + grad_h)
			])
			var g_cols = PackedColorArray([c_glow_top, c_glow_top, c_glow_bot, c_glow_bot])
			draw_polygon(g_pts, g_cols)
		
		# Labels (animated sinking along with key depression)
		if qwerty_enabled and labels.has(midi):
			var text_color = Color("#384c5c") if c_mid.get_luminance() > 0.4 else Color("#f5fbff")
			if dep > 0.5:
				text_color = Color("#121e29")
			var font_size = clampi(int(k_w - 2), 8, 14)
			var label: String = labels[midi]
			if label.begins_with("·"):
				var sub_char = label.substr(1)
				var char_w = font.get_string_size(sub_char, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				var y_char = k_y + k_h * 0.82
				# Draw dot above
				var dot_y = y_char - font_size * 0.95
				draw_circle(Vector2(k_x + k_w * 0.5, dot_y), 1.8, text_color)
				draw_string(font, Vector2(k_x + (k_w - char_w) * 0.5, y_char), sub_char, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
			else:
				var text_width = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				var y = k_y + k_h * 0.82
				if text_width > k_w - 2:
					draw_set_transform(Vector2(k_x + k_w * 0.5 + font_size * 0.3, y), -PI / 2)
					draw_string(font, Vector2.ZERO, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
					draw_set_transform(Vector2.ZERO)
				else:
					draw_string(font, Vector2(k_x + (k_w - text_width) * 0.5, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	# ---------------------------------------------------------
	# 2. BLACK KEYS DROP SHADOWS (Double-Layer 3D Depth cast onto white keys)
	# ---------------------------------------------------------
	for midi in key_rects:
		if not Keymap.is_black(midi):
			continue
		var rect: Rect2 = key_rects[midi]
		var dep: float = depression.get(midi, 0.0)
		# Shadow shrinks as the key depresses closer to the white key bed
		var shadow_x = lerpf(3.4, 1.2, dep)
		var shadow_y = lerpf(4.4, 1.5, dep)
		# Layer A: Sharp contact occlusion shadow
		draw_rect(Rect2(rect.position.x + 0.8, rect.position.y + 1.5, rect.size.x + shadow_x * 0.6, rect.size.y + shadow_y * 0.6), Color(0.0, 0.0, 0.0, lerpf(0.46, 0.25, dep)))
		# Layer B: Soft ambient drop shadow
		draw_rect(Rect2(rect.position.x + 1.8, rect.position.y + 2.5, rect.size.x + shadow_x, rect.size.y + shadow_y), Color(0.0, 0.0, 0.0, lerpf(0.24, 0.12, dep)))

	# ---------------------------------------------------------
	# 3. BLACK KEYS (Matte Ebony Crown, Tapering, 3D Chamfer & Depression Travel)
	# ---------------------------------------------------------
	for midi in key_rects:
		if not Keymap.is_black(midi):
			continue
		var rect: Rect2 = key_rects[midi]
		var dep: float = depression.get(midi, 0.0)
		var light: float = illumination.get(midi, 0.0)
		
		# Physical depression travel (black key sinks 3.8px)
		var travel_y = dep * 3.8
		var k_x = rect.position.x
		var k_w = rect.size.x
		var k_y = rect.position.y + travel_y
		var k_h = maxf(1.0, rect.size.y - travel_y * 0.4)
		
		# Felt compression above pressed black key
		if dep > 0.05:
			draw_rect(Rect2(k_x, 0, k_w, 5), Color(0.32, 0.05, 0.09, dep * 0.75))
		
		# Ebony body colors (opaque slate pressure response)
		var ebony_top = Color("#303238").lerp(Color("#191c22"), dep)
		var ebony_bot = Color("#11141a").lerp(Color("#292b32"), dep)
		
		# Top quad & body with slight 0.8px crown taper
		var front_h = 6.5
		var body_h = maxf(1.0, k_h - front_h)
		var pts_b = PackedVector2Array([
			Vector2(k_x + 0.8, k_y),
			Vector2(k_x + k_w - 0.8, k_y),
			Vector2(k_x + k_w, k_y + body_h),
			Vector2(k_x, k_y + body_h)
		])
		var cols_b = PackedColorArray([ebony_top, ebony_top, ebony_bot, ebony_bot])
		draw_polygon(pts_b, cols_b)
		
		# Slanted front cap (slopes down toward the front)
		var cap_top = ebony_bot
		var cap_bot = ebony_bot.darkened(0.38 + dep * 0.15)
		var pts_cap = PackedVector2Array([
			Vector2(k_x, k_y + body_h),
			Vector2(k_x + k_w, k_y + body_h),
			Vector2(k_x + k_w - 1.0, k_y + k_h),
			Vector2(k_x + 1.0, k_y + k_h)
		])
		var cols_cap = PackedColorArray([cap_top, cap_top, cap_bot, cap_bot])
		draw_polygon(pts_cap, cols_cap)
		
		# Chamfered specular highlights and edge ridges
		draw_line(Vector2(k_x + 0.5, k_y + 1.0), Vector2(k_x + 0.5, k_y + body_h), Color(1.0, 1.0, 1.0, 0.22 * (1.0 - dep * 0.4)), 1.0)
		draw_line(Vector2(k_x + k_w - 0.5, k_y + 1.0), Vector2(k_x + k_w - 0.5, k_y + k_h), Color(0.0, 0.0, 0.0, 0.75), 1.0)
		draw_line(Vector2(k_x, k_y + k_h), Vector2(k_x + k_w, k_y + k_h), Color(0.0, 0.0, 0.0, 0.95), 1.0)
		
		# Contact light gradient (Gouraud fade to 45% height)
		if light > 0.001:
			var tint: Color = note_colors.get(midi, active_color)
			var grad_h = k_h * 0.45
			var c_glow_top = Color(tint.r, tint.g, tint.b, light * 0.72)
			var c_glow_bot = Color(tint.r, tint.g, tint.b, 0.0)
			var g_pts = PackedVector2Array([
				Vector2(k_x + 1, k_y),
				Vector2(k_x + k_w - 1, k_y),
				Vector2(k_x + k_w - 1, k_y + grad_h),
				Vector2(k_x + 1, k_y + grad_h)
			])
			var g_cols = PackedColorArray([c_glow_top, c_glow_top, c_glow_bot, c_glow_bot])
			draw_polygon(g_pts, g_cols)
		
		# Labels (animated sinking along with black key depression)
		if qwerty_enabled and labels.has(midi):
			var font_size = clampi(int(k_w - 2), 8, 14)
			var label: String = labels[midi]
			var text_color = Color("#e5f0fa")
			if label.begins_with("·"):
				var sub_char = label.substr(1)
				var char_w = font.get_string_size(sub_char, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				var y_char = k_y + k_h - 7
				var dot_y = y_char - font_size * 0.95
				draw_circle(Vector2(k_x + k_w * 0.5, dot_y), 1.6, text_color)
				draw_string(font, Vector2(k_x + (k_w - char_w) * 0.5, y_char), sub_char, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
			else:
				var text_width = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				var y = k_y + k_h - 7
				if text_width > k_w - 2:
					draw_set_transform(Vector2(k_x + k_w * 0.5 + font_size * 0.3, y), -PI / 2)
					draw_string(font, Vector2.ZERO, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
					draw_set_transform(Vector2.ZERO)
				else:
					draw_string(font, Vector2(k_x + (k_w - text_width) * 0.5, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	
	# Luminous Neon Horizon Line (Laser Bar above the keyboard)
	# 1. Broad atmospheric neon aura
	draw_rect(Rect2(0, -6, size.x, 14), Color(active_color.r, active_color.g, active_color.b, 0.05))
	# 2. Concentrated neon beam halo
	draw_rect(Rect2(0, -2, size.x, 6), Color(active_color.r, active_color.g, active_color.b, 0.12))
	# 3. Vibrant saturated laser beam
	draw_rect(Rect2(0, 0, size.x, 2), Color(active_color.r, active_color.g, active_color.b, 0.65))
	# 4. White-hot pure center filament
	draw_rect(Rect2(0, 0.5, size.x, 0.8), Color(1.0, 1.0, 1.0, 0.25))

func _draw_key_glows() -> void:
	if gaussian_tex == null or illumination.is_empty():
		return
	
	# Auto-gain density attenuation across active keyboard keys
	var active_count = 0
	for midi in illumination:
		if illumination[midi] > 0.05:
			active_count += 1
	var k_scale = clampf(1.0 / sqrt(maxf(1.0, float(active_count) * 0.40)), 0.20, 1.0)
	
	for midi in illumination:
		var light: float = illumination[midi]
		if light <= 0.01 or not key_rects.has(midi):
			continue
		var rect: Rect2 = key_rects[midi]
		var tint: Color = note_colors.get(midi, active_color)
		var center_x = rect.position.x + rect.size.x * 0.5
		var top_y = rect.position.y
		
		# 1. Broad soft diffuse outer halo (width 2.8x, height 1.6x of key width)
		# Merges neighboring active keys into a single continuous cloud of light without square corners
		var halo_w = rect.size.x * 2.8
		var halo_h = rect.size.x * 1.6
		var halo_rect = Rect2(center_x - halo_w * 0.5, top_y - halo_h * 0.5, halo_w, halo_h)
		var halo_alpha = 0.50 * light * k_scale
		key_glow_layer.draw_texture_rect(gaussian_tex, halo_rect, false, Color(tint.r, tint.g, tint.b, halo_alpha))
		
		# 2. Central HDR Hotspot: smaller ellipse with warm bright white
		var spot_w = rect.size.x * 1.15
		var spot_h = rect.size.x * 0.70
		var spot_rect = Rect2(center_x - spot_w * 0.5, top_y - spot_h * 0.5, spot_w, spot_h)
		var spot_col = tint.lerp(Color.WHITE, 0.25)
		spot_col.a = 0.75 * light * k_scale
		key_glow_layer.draw_texture_rect(gaussian_tex, spot_rect, false, spot_col)
