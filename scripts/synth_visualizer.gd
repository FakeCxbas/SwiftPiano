extends Control

const SPEED = 340.0
const MAX_POOLED_BARS = 64

var bars: Dictionary = {}
var released: Array[Dictionary] = []
var key_rects: Dictionary = {}
var key_range_mode: String = "full_88"
var visible_midi_range: Vector2i = Vector2i(21, 108)
var shorts_mode: bool = false
var horizontal_bounds: Vector2 = Vector2.ZERO
var elapsed = 0.0
var enabled = true
var light_mode: String = "supernova"
var bar_style: String = "laser_crystal"
var rhythm_flashes: bool = false
var flash_intensity: float = 0.0
var flash_color: Color = Color("#64e8d0")
var shockwaves: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var spotlights: Array[Dictionary] = []
var aurora_phase: float = 0.0

var key_flares: Array[Dictionary] = []
var key_rings: Array[Dictionary] = []
var note_streak: int = 0

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
	_update_bars()

# Anti-Spam Energy Scale & Activity Density
var recent_strikes: Array[float] = []
var energy_scale: float = 1.0
var key_spark_cooldowns: Dictionary = {}
var last_shockwave_time: float = -1.0

# Equalizer frequency bands for Synthwave show (16 bands)
var eq_bands: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

# Nodes & Rendering layers
var stage_rect: ColorRect
var bg_shader_rect: ColorRect
var bg_mat: ShaderMaterial
var bars_container: Control
var bar_nodes: Array[ColorRect] = []
var halo: Node2D
var gaussian_tex: ImageTexture

# Shaders
var bar_shaders: Dictionary = {}
var show_shaders: Dictionary = {}

func set_custom_background_active(active: bool) -> void:
	if stage_rect != null:
		stage_rect.modulate.a = 0.22 if active else 1.0

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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	stage_rect = ColorRect.new()
	stage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stage_material = ShaderMaterial.new()
	stage_material.shader = preload("res://shaders/stage_background.gdshader")
	stage_rect.material = stage_material
	add_child(stage_rect)
	stage_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	_load_shaders()
	gaussian_tex = _generate_gaussian_texture(128)
	
	# Layer 0: Fullscreen background shader
	bg_shader_rect = ColorRect.new()
	bg_shader_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_mat = ShaderMaterial.new()
	bg_shader_rect.material = bg_mat
	bg_shader_rect.visible = false
	add_child(bg_shader_rect)
	
	# Layer 1: Note bars container with pooled ColorRect nodes
	bars_container = Control.new()
	bars_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bars_container)
	for i in range(MAX_POOLED_BARS):
		var cr = ColorRect.new()
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.visible = false
		var mat = ShaderMaterial.new()
		if bar_shaders.has(bar_style):
			mat.shader = bar_shaders[bar_style]
		cr.material = mat
		bars_container.add_child(cr)
		bar_nodes.append(cr)
	
	# Layer 2: Additive halo node for Gaussian radial emitter & particle sparks
	halo = Node2D.new()
	var additive = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = additive
	halo.draw.connect(_draw_halos)
	add_child(halo)

func _load_shaders() -> void:
	bar_shaders = {
		"laser_crystal": preload("res://shaders/bar_laser_crystal.gdshader"),
		"stardust": preload("res://shaders/bar_stardust.gdshader"),
		"comet": preload("res://shaders/bar_comet.gdshader"),
		"cyber_pulse": preload("res://shaders/bar_cyber_pulse.gdshader"),
		"frosted_glass": preload("res://shaders/bar_frosted_glass.gdshader"),
		"plasma": preload("res://shaders/bar_plasma.gdshader"),
		"harmonic": preload("res://shaders/bar_harmonic.gdshader"),
	}
	show_shaders = {
		"supernova": preload("res://shaders/show_supernova.gdshader"),
		"aurora": preload("res://shaders/show_aurora.gdshader"),
		"rave": preload("res://shaders/show_neon_rave.gdshader"),
		"synthwave": preload("res://shaders/show_synthwave.gdshader"),
	}

func _get_bar_node(idx: int) -> ColorRect:
	while idx >= bar_nodes.size():
		var cr = ColorRect.new()
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.visible = false
		var mat = ShaderMaterial.new()
		if bar_shaders.has(bar_style):
			mat.shader = bar_shaders[bar_style]
		cr.material = mat
		bars_container.add_child(cr)
		bar_nodes.append(cr)
	return bar_nodes[idx]

func trigger_flash(color: Color, strength: float = 1.0, midis: Array = []) -> void:
	if not rhythm_flashes or not enabled or light_mode == "off":
		return
	flash_color = color
	flash_intensity = minf(2.0, flash_intensity + strength * 0.85 * energy_scale)
	
	var key_xs: Array[float] = []
	for m in midis:
		if key_rects.has(m):
			var r: Rect2 = key_rects[m]
			key_xs.append(r.position.x + r.size.x * 0.5)
	if key_xs.is_empty():
		key_xs.append(size.x * 0.5)
	
	var chord_center_x = 0.0
	for x in key_xs:
		chord_center_x += x
	chord_center_x /= float(key_xs.size())
	
	match light_mode:
		"supernova":
			# Group simultaneous notes (<60ms) into 1 smooth shockwave, max 6 waves
			if (elapsed - last_shockwave_time > 0.060 or shockwaves.is_empty()) and shockwaves.size() < 6:
				last_shockwave_time = elapsed
				shockwaves.append({
					"radius": 15.0,
					"max_radius": maxf(size.x, size.y) * 1.15,
					"speed": 820.0,
					"alpha": minf(0.50, 0.40 * strength * energy_scale),
					"color": color,
					"origin": Vector2(chord_center_x, size.y)
				})
			for kx in key_xs:
				if sparks.size() < 80:
					for i in range(2):
						sparks.append({
							"pos": Vector2(kx + randf_range(-6, 6), size.y - 4),
							"vel": Vector2(randf_range(-50, 50), randf_range(-100, -240)),
							"color": color,
							"life": randf_range(0.25, 0.50),
							"max_life": 0.50,
							"type": "glint",
							"size": randf_range(1.5, 2.8),
							"twinkle": randf_range(12.0, 28.0)
						})
		"aurora":
			aurora_phase += strength * 0.6 * energy_scale
			for kx in key_xs:
				if sparks.size() < 80:
					sparks.append({
						"pos": Vector2(kx + randf_range(-12, 12), size.y - 8),
						"vel": Vector2(randf_range(-20, 20), randf_range(-50, -140)),
						"color": color,
						"life": randf_range(1.0, 2.0),
						"max_life": 2.0,
						"type": "fairy",
						"size": randf_range(2.0, 3.8),
						"twinkle": randf_range(4.0, 10.0),
						"sway": randf_range(1.5, 3.5),
						"seed": randf() * 100.0
					})
		"starlight":
			for kx in key_xs:
				var last_t = key_spark_cooldowns.get(kx, -1.0)
				if elapsed - last_t < 0.045:
					continue
				key_spark_cooldowns[kx] = elapsed
				if sparks.size() >= 80:
					break
				var count = int(clampf(5.0 * strength * energy_scale, 2.0, 7.0))
				for s in range(count):
					var angle = randf_range(-PI * 0.78, -PI * 0.22)
					var spd = randf_range(280.0, 680.0) * (0.8 + 0.3 * strength)
					sparks.append({
						"pos": Vector2(kx + randf_range(-6, 6), size.y - 2.0),
						"vel": Vector2(cos(angle) * spd, sin(angle) * spd),
						"color": color,
						"life": randf_range(0.35, 0.85),
						"max_life": 0.85,
						"type": "spark",
						"size": randf_range(1.6, 3.0),
						"twinkle": randf_range(10.0, 24.0)
					})
		"rave":
			for kx in key_xs:
				var angle_bias = (size.x * 0.5 - kx) * 0.35
				if spotlights.size() < 6:
					spotlights.append({
						"origin": Vector2(kx, size.y),
						"target_x": kx + angle_bias + randf_range(-45, 45),
						"spread": randf_range(100.0, 160.0),
						"color": color,
						"alpha": minf(0.50, 0.45 * strength * energy_scale),
						"life": 0.38,
						"max_life": 0.38
					})
		"synthwave":
			for m in midis:
				var b = clampi(int(float(m - 21) / 87.0 * 15.0), 0, 15)
				eq_bands[b] = minf(1.0, eq_bands[b] + 0.55 * strength * energy_scale)
	
	queue_redraw()
	if halo != null:
		halo.queue_redraw()

func note_on(token: int, midi: int, color: Color = Color("#64e8d0")) -> void:
	recent_strikes.append(elapsed)
	bars[token] = {"midi": midi, "born": elapsed, "released": -1.0, "color": color}
	_trigger_key_splash(midi, color)
	_record_streak(color)

func _record_streak(_color: Color) -> void:
	note_streak += 1

func _trigger_key_splash(midi: int, color: Color) -> void:
	if not key_rects.has(midi) or not enabled:
		return
	var r: Rect2 = key_rects[midi]
	var kx = r.position.x + r.size.x * 0.5
	var ky = size.y
	
	if key_flares.size() < 24:
		key_flares.append({
			"pos": Vector2(kx, ky),
			"color": color,
			"life": 0.28,
			"max_life": 0.28,
			"width": r.size.x
		})
	
	if key_rings.size() < 24:
		key_rings.append({
			"pos": Vector2(kx, ky),
			"radius": 4.0,
			"max_radius": maxf(18.0, r.size.x * 1.6),
			"color": color,
			"alpha": 0.85,
			"speed": 110.0
		})
	
	if sparks.size() < 80:
		for i in range(2):
			var angle = randf_range(-PI * 0.72, -PI * 0.28)
			var spd = randf_range(160.0, 360.0)
			sparks.append({
				"pos": Vector2(kx + randf_range(-r.size.x * 0.2, r.size.x * 0.2), ky - 2.0),
				"vel": Vector2(cos(angle) * spd, sin(angle) * spd),
				"color": color,
				"life": randf_range(0.3, 0.55),
				"max_life": 0.55,
				"type": "spark",
				"size": randf_range(1.5, 2.6),
				"twinkle": randf_range(14.0, 26.0)
			})

func note_off(token: int) -> void:
	if bars.has(token):
		var bar: Dictionary = bars[token]
		bar.released = elapsed
		released.append(bar)
		bars.erase(token)

func bar_rect(bar: Dictionary) -> Rect2:
	var key: Rect2 = key_rects.get(bar.midi, Rect2())
	var end: float = elapsed if bar.released < 0 else bar.released
	var bottom = size.y - SPEED * (elapsed - end)
	var height = maxf(key.size.x, SPEED * (end - float(bar.born)))
	return Rect2(key.position.x, bottom - height, key.size.x, height)

func _process(delta: float) -> void:
	elapsed += delta
	for i in range(released.size() - 1, -1, -1):
		if bar_rect(released[i]).end.y < -24:
			released.remove_at(i)
	
	if flash_intensity > 0.0:
		flash_intensity = maxf(0.0, flash_intensity - delta * 3.2)
	
	# Anti-Spam: Dynamic Density Attenuation over the last 350ms
	var cutoff = elapsed - 0.350
	while not recent_strikes.is_empty() and recent_strikes[0] < cutoff:
		recent_strikes.remove_at(0)
	var active_density = float(bars.size() + recent_strikes.size())
	energy_scale = clampf(1.0 / sqrt(maxf(1.0, active_density * 0.40)), 0.16, 1.0)
	
	# Synthwave equalizer band decay and surge
	for b in range(16):
		eq_bands[b] = maxf(0.0, eq_bands[b] - delta * 2.6)
	for bar in bars.values():
		var band_idx = clampi(int(float(bar.midi - 21) / 87.0 * 15.0), 0, 15)
		eq_bands[band_idx] = minf(1.0, eq_bands[band_idx] + delta * 6.0 * energy_scale)
	
	for i in range(shockwaves.size() - 1, -1, -1):
		var sw: Dictionary = shockwaves[i]
		sw.radius += sw.speed * delta
		sw.alpha -= delta * 1.6
		if sw.alpha <= 0.0 or sw.radius >= sw.max_radius:
			shockwaves.remove_at(i)
	
	for i in range(sparks.size() - 1, -1, -1):
		var p: Dictionary = sparks[i]
		p.life -= delta
		if p.life <= 0.0:
			sparks.remove_at(i)
			continue
		if p.type == "fairy":
			p.pos.y += p.vel.y * delta
			p.pos.x += sin(elapsed * p.sway + p.seed) * 35.0 * delta
		elif p.type == "spark":
			p.vel.y += 440.0 * delta
			p.vel *= (1.0 - 0.70 * delta)
			p.pos += p.vel * delta
		elif p.type == "glint":
			p.pos += p.vel * delta
	
	for i in range(spotlights.size() - 1, -1, -1):
		var sp: Dictionary = spotlights[i]
		sp.life -= delta
		sp.alpha = (sp.life / sp.max_life) * 0.50 * energy_scale
		if sp.life <= 0.0:
			spotlights.remove_at(i)
	
	for i in range(key_flares.size() - 1, -1, -1):
		var kf: Dictionary = key_flares[i]
		kf.life -= delta
		if kf.life <= 0.0:
			key_flares.remove_at(i)
	
	for i in range(key_rings.size() - 1, -1, -1):
		var kr: Dictionary = key_rings[i]
		kr.radius += kr.speed * delta
		kr.alpha -= delta * 2.8
		if kr.alpha <= 0.0 or kr.radius >= kr.max_radius:
			key_rings.remove_at(i)
	
	# Update background show shader
	_update_bg_shader(delta)
	
	# Update note bar nodes
	_update_bars()
	
	var has_impacts = (
		not key_flares.is_empty()
		or not key_rings.is_empty()
	)
	var has_flash = rhythm_flashes and (
		flash_intensity > 0.005 
		or not shockwaves.is_empty() 
		or not spotlights.is_empty()
		or light_mode == "aurora"
		or light_mode == "synthwave"
	)
	
	if not bars.is_empty() or not released.is_empty() or has_flash or has_impacts or not sparks.is_empty():
		queue_redraw()
		halo.queue_redraw()
	elif halo.visible:
		queue_redraw()
		halo.queue_redraw()
	halo.visible = enabled and (not bars.is_empty() or not released.is_empty() or has_flash or has_impacts or not sparks.is_empty())

func _update_bg_shader(_delta: float) -> void:
	if bg_shader_rect == null:
		return
	
	bg_shader_rect.size = size
	
	if not enabled or not rhythm_flashes or light_mode == "off":
		bg_shader_rect.visible = false
		return
	
	# Strict opacity cap of <= 0.35 to guarantee the background never clarifies into white
	bg_shader_rect.modulate.a = clampf(0.35 * energy_scale, 0.08, 0.35)
	
	match light_mode:
		"supernova":
			var is_active = (flash_intensity > 0.005 or not shockwaves.is_empty())
			bg_shader_rect.visible = is_active
			if is_active:
				if bg_mat.shader != show_shaders["supernova"]:
					bg_mat.shader = show_shaders["supernova"]
				bg_mat.set_shader_parameter("u_resolution", size)
				bg_mat.set_shader_parameter("u_color", flash_color)
				bg_mat.set_shader_parameter("u_flash_intensity", flash_intensity * energy_scale)
				bg_mat.set_shader_parameter("u_time", elapsed)
				var center = Vector2(0.5, 1.0)
				var rad = 0.0
				if not shockwaves.is_empty():
					var sw = shockwaves[-1]
					center = Vector2(sw.origin.x / maxf(1.0, size.x), sw.origin.y / maxf(1.0, size.y))
					rad = sw.radius
				bg_mat.set_shader_parameter("u_center", center)
				bg_mat.set_shader_parameter("u_radius", rad)
		
		"aurora":
			bg_shader_rect.visible = true
			if bg_mat.shader != show_shaders["aurora"]:
				bg_mat.shader = show_shaders["aurora"]
			bg_mat.set_shader_parameter("u_resolution", size)
			bg_mat.set_shader_parameter("u_color", flash_color)
			bg_mat.set_shader_parameter("u_intensity", clampf(0.35 + flash_intensity * 0.65, 0.0, 2.0) * energy_scale)
			bg_mat.set_shader_parameter("u_time", elapsed * 0.8 + aurora_phase)
		
		"rave":
			var beam_count = mini(6, spotlights.size())
			var is_active = (flash_intensity > 0.005 or beam_count > 0)
			bg_shader_rect.visible = is_active
			if is_active:
				if bg_mat.shader != show_shaders["rave"]:
					bg_mat.shader = show_shaders["rave"]
				bg_mat.set_shader_parameter("u_resolution", size)
				bg_mat.set_shader_parameter("u_color", flash_color)
				bg_mat.set_shader_parameter("u_time", elapsed)
				bg_mat.set_shader_parameter("u_intensity", flash_intensity * energy_scale)
				var beams: Array[Vector4] = []
				for i in range(beam_count):
					var sp = spotlights[i]
					beams.append(Vector4(sp.origin.x / maxf(1.0, size.x), sp.target_x / maxf(1.0, size.x), sp.alpha, sp.spread))
				while beams.size() < 6:
					beams.append(Vector4.ZERO)
				bg_mat.set_shader_parameter("u_beams", beams)
				bg_mat.set_shader_parameter("u_num_beams", beam_count)
		
		"synthwave":
			bg_shader_rect.visible = true
			if bg_mat.shader != show_shaders["synthwave"]:
				bg_mat.shader = show_shaders["synthwave"]
			bg_mat.set_shader_parameter("u_resolution", size)
			bg_mat.set_shader_parameter("u_color", flash_color)
			bg_mat.set_shader_parameter("u_time", elapsed)
			bg_mat.set_shader_parameter("u_intensity", flash_intensity * energy_scale)
			bg_mat.set_shader_parameter("u_eq", eq_bands)
		
		_:
			bg_shader_rect.visible = false

func _update_bars() -> void:
	if not enabled or bars_container == null:
		for node in bar_nodes:
			node.visible = false
		return
	
	var target_shader: Shader = bar_shaders.get(bar_style, bar_shaders.get("laser_crystal"))
	var visible_list = _visible_bars()
	var active_count = 0
	
	for bar in visible_list:
		if not key_rects.has(bar.midi):
			continue
		var rect = bar_rect(bar)
		if rect.size.x <= 0 or rect.end.y < 0 or rect.position.y > size.y:
			continue
		
		var node = _get_bar_node(active_count)
		active_count += 1
		
		var mat: ShaderMaterial = node.material as ShaderMaterial
		if mat == null:
			mat = ShaderMaterial.new()
			node.material = mat
		if mat.shader != target_shader:
			mat.shader = target_shader
		
		node.position = rect.position
		node.size = rect.size
		node.visible = true
		
		mat.set_shader_parameter("u_color", bar.color)
		mat.set_shader_parameter("u_size", rect.size)
		mat.set_shader_parameter("u_time", elapsed)
		mat.set_shader_parameter("u_born", float(bar.born))
		mat.set_shader_parameter("u_held", bar.released < 0.0)
		if bar_style == "harmonic":
			mat.set_shader_parameter("u_pitch", clampf(float(bar.midi - 21) / 88.0, 0.0, 1.0))
	
	for i in range(active_count, bar_nodes.size()):
		bar_nodes[i].visible = false

func _visible_bars() -> Array:
	return bars.values() + released

func _draw() -> void:
	pass

func _draw_sparks() -> void:
	for p in sparks:
		var frac = clampf(p.life / p.max_life, 0.0, 1.0)
		var col: Color = p.color
		var a = frac * 0.90 * energy_scale
		if p.type == "fairy":
			halo.draw_circle(p.pos, p.size * 2.0, Color(col.r, col.g, col.b, a * 0.25))
			halo.draw_circle(p.pos, p.size * 0.85, Color(1.0, 1.0, 1.0, a * 0.90))
		elif p.type == "spark":
			var spd = p.vel.length()
			var dir = p.vel.normalized() if spd > 2.0 else Vector2.UP
			var stretch_len = clampf(spd * 0.042, 2.0, 22.0)
			# Velocity-stretched luminous teardrop / streak
			halo.draw_line(p.pos - dir * stretch_len, p.pos, Color(col.r * 1.7, col.g * 1.7, col.b * 1.7, a * 0.70), p.size * 0.85)
			# Twinkling 4-point star cross at particle head
			var sz = p.size * (1.3 + 0.5 * sin(elapsed * p.twinkle)) * frac
			halo.draw_line(p.pos - Vector2(sz, 0), p.pos + Vector2(sz, 0), Color(1.0, 1.0, 1.0, a * 0.90), 1.0)
			halo.draw_line(p.pos - Vector2(0, sz), p.pos + Vector2(0, sz), Color(1.0, 1.0, 1.0, a * 0.90), 1.0)
			halo.draw_circle(p.pos, p.size * 0.5 * frac, Color(1.0, 1.0, 1.0, a))
		elif p.type == "glint":
			halo.draw_circle(p.pos, p.size * 1.2, Color(col.r * 1.5, col.g * 1.5, col.b * 1.5, a * 0.85))
			halo.draw_circle(p.pos, p.size * 0.5, Color(1.0, 1.0, 1.0, a))

func _draw_halos() -> void:
	if not enabled or gaussian_tex == null:
		return
	
	# 1. Contact point: Broad soft diffuse outer halo and Central HDR Hotspot for every active note
	# Zero rects, zero arcs: Gaussian radial light emitter in BLEND_MODE_ADD
	for bar in bars.values():
		if key_rects.has(bar.midi):
			var r: Rect2 = key_rects[bar.midi]
			var kx = r.position.x + r.size.x * 0.5
			var ky = size.y
			var col: Color = bar.color
			
			# Broad diffuse outer halo (width 2.8x, height 1.6x of key width)
			# Neighboring active keys blend seamlessly into a continuous cloud of light
			var hw = r.size.x * 2.8
			var hh = r.size.x * 1.6
			var hrect = Rect2(kx - hw * 0.5, ky - hh * 0.5, hw, hh)
			var h_alpha = 0.50 * energy_scale
			halo.draw_texture_rect(gaussian_tex, hrect, false, Color(col.r, col.g, col.b, h_alpha))
			
			# Central HDR Hotspot
			var sw = r.size.x * 1.15
			var sh = r.size.x * 0.70
			var srect = Rect2(kx - sw * 0.5, ky - sh * 0.5, sw, sh)
			var scol = Color(1.8, 1.6, 1.8, 0.90 * energy_scale)
			halo.draw_texture_rect(gaussian_tex, srect, false, scol)
	
	# 2. Key Strike soft Gaussian pulses (replaces old hard lines and circles)
	for kf in key_flares:
		var frac = kf.life / kf.max_life
		var alpha = frac * 0.75 * energy_scale
		var col: Color = kf.color
		var w: float = kf.width
		var pos: Vector2 = kf.pos
		var fw = maxf(22.0, w * 2.4) * (1.0 + (1.0 - frac) * 0.5)
		var fh = maxf(12.0, w * 1.4) * (1.0 + (1.0 - frac) * 0.5)
		var frect = Rect2(pos.x - fw * 0.5, pos.y - fh * 0.5, fw, fh)
		halo.draw_texture_rect(gaussian_tex, frect, false, Color(col.r * 1.5, col.g * 1.5, col.b * 1.5, alpha))
	
	# 3. Key contact expanding soft Gaussian halos (replaces old draw_arc semicircles)
	for kr in key_rings:
		var frac = kr.radius / kr.max_radius
		var a = kr.alpha * (1.0 - frac) * 0.65 * energy_scale
		var col: Color = kr.color
		var rw = kr.radius * 2.2
		var rh = kr.radius * 1.4
		var rrect = Rect2(kr.pos.x - rw * 0.5, kr.pos.y - rh * 0.5, rw, rh)
		halo.draw_texture_rect(gaussian_tex, rrect, false, Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, a))
	
	# 4. Particles (Star shower, sparks, glints) with physics & velocity stretch
	if not sparks.is_empty():
		_draw_sparks()
