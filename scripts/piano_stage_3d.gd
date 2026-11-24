class_name PianoStage3D
extends SubViewportContainer
## One metric world for keys, skinned hands and the playback cascade.
## Cascade times are seconds on the caller's playback clock (including seeks).

class StageNote extends RefCounted:
	var midi: int
	var start: float
	var duration: float
	var color: Color
	func _init(pitch: int = 60, time: float = 0.0, length: float = 0.25, tint: Color = Color.CYAN) -> void:
		midi = pitch
		start = time
		duration = maxf(length, 0.01)
		color = tint

class LiveNote extends RefCounted:
	var token: int
	var midi: int
	var born: float
	var released: float
	var color: Color
	func _init(note_token: int = -1, pitch: int = 60, time: float = 0.0, tint: Color = Color.CYAN) -> void:
		token = note_token
		midi = pitch
		born = time
		released = -1.0
		color = tint

const KeyMap3DClass = preload("res://scripts/stage3d/key_map_3d.gd")
const FingeringSolverClass = preload("res://scripts/stage3d/fingering_solver.gd")
const HandIKControllerClass = preload("res://scripts/stage3d/hand_ik_controller.gd")
const SLOPE: float = 0.08
const CASCADE_SPAN: float = 1.15
const STRIKE_Z: float = -0.082
const STRIKE_Y: float = 0.028
const LIVE_RISE_SPEED: float = 0.24
const PILL_WHITE_WIDTH: float = 0.0206
const PILL_BLACK_WIDTH: float = 0.0148
const PILL_MIN_LEN_WHITE: float = 0.028
const PILL_MIN_LEN_BLACK: float = 0.024
const MAX_BARS: int = 384
const MAX_LIVE_NOTES: int = 256
const LOOKAHEAD: float = 4.0
const NOTE_NAMES: PackedStringArray = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const HAND_SCENES: Array[PackedScene] = [preload("res://assets/hands/hand_3d_left.glb"), preload("res://assets/hands/hand_3d_right.glb")]
const ANIME: Shader = preload("res://shaders/hand_3d_anime.gdshader")
const OUTLINE: Shader = preload("res://shaders/hand_3d_outline.gdshader")
const SKIN: Texture2D = preload("res://assets/hands/hand_anime_texture.png")
var stage_viewport: SubViewport
var camera: Camera3D
var world_root: Node3D
var _keys: Array[MeshInstance3D] = []
var _key_materials: Array[StandardMaterial3D] = []
var _rest: Array[Vector3] = []
var _pressed: PackedByteArray = PackedByteArray()
var _depth: PackedFloat32Array = PackedFloat32Array()
var _depth_vel: PackedFloat32Array = PackedFloat32Array()
var _energy: PackedFloat32Array = PackedFloat32Array()
var _rail_pulse: PackedFloat32Array = PackedFloat32Array()
var _strike_serial: PackedInt32Array = PackedInt32Array()
var _key_colors: Array[Color] = []
var _key_shades: Array[MeshInstance3D] = []
var _key_shade_materials: Array[ShaderMaterial] = []
var _key_shade_shader: Shader
var _rail_segments: Array[MeshInstance3D] = []
var _rail_segment_materials: Array[StandardMaterial3D] = []
var _rail_halos: Array[MeshInstance3D] = []
var _rail_halo_materials: Array[ShaderMaterial] = []
var _rail_halo_shader: Shader
var _hands: Array[Node3D] = []
var _skeletons: Array[Skeleton3D] = []
var key_map: KeyMap3D = KeyMap3DClass.new()
var fingering_solver: FingeringSolver = FingeringSolverClass.new()
var hand_controllers: Array[HandIKController] = []
var _elapsed_time: float = 0.0
var _hand_lights: Array[OmniLight3D] = []
var _notes: Array[StageNote] = []
var _live_cascade_enabled: bool = false
var _live_notes: Array[LiveNote] = []
var _overlay_root: Node2D
var _overlay_clip: Control
var _pill_layer: Node2D
var _flare_layer: Node2D
var _gaussian_tex: ImageTexture
var _pill_font: FontVariation
var _strike_rail_y: float = 0.0
var _overlay_had_content: bool = false
var _playback_time: float = 0.0
var _note_cursor: int = 0
var _visual_playback_time: float = 0.0
var _visual_note_cursor: int = 0
var _smooth_cascade_clock: bool = false
var _hands_enabled: bool = true
var _anticipation_enabled: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	stage_viewport = SubViewport.new()
	stage_viewport.name = "StageViewport"
	stage_viewport.own_world_3d = true
	stage_viewport.transparent_bg = true
	stage_viewport.msaa_3d = SubViewport.MSAA_4X
	stage_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(stage_viewport)
	world_root = Node3D.new()
	world_root.name = "PianoWorld"
	stage_viewport.add_child(world_root)
	camera = Camera3D.new()
	camera.name = "StageCamera"
	camera.position = Vector3(0.0, 1.65, 0.10)
	camera.rotation_degrees = Vector3(-79.0, 0.0, 0.0)
	camera.fov = 50.0
	camera.near = 0.01
	camera.far = 10.0
	world_root.add_child(camera)
	camera.current = true
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("242838")
	environment.ambient_light_energy = 0.18
	environment_node.environment = environment
	world_root.add_child(environment_node)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	light.light_energy = 0.72
	light.shadow_enabled = true
	light.shadow_opacity = 0.70
	light.shadow_bias = 0.0004
	light.shadow_normal_bias = 0.25
	light.directional_shadow_max_distance = 2.4
	world_root.add_child(light)
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.name = "HandRimLight"
	rim.rotation_degrees = Vector3(-135.0, 18.0, 0.0)
	rim.light_energy = 0.42
	rim.light_color = Color("b8d2ff")
	world_root.add_child(rim)
	_build_keyboard()
	_build_hands()
	for side in range(2):
		var hand_light: OmniLight3D = OmniLight3D.new()
		hand_light.name = "LeftKeyLight" if side == 0 else "RightKeyLight"
		hand_light.position = Vector3(-0.18 if side == 0 else 0.18, 0.065, -0.020)
		hand_light.omni_range = 0.30
		hand_light.light_energy = 0.0
		hand_light.light_cull_mask = 2
		world_root.add_child(hand_light)
		_hand_lights.append(hand_light)
	var cascade: MeshInstance3D = _box("CascadeSurface", Vector3(1.26, 0.004, CASCADE_SPAN * sqrt(1.0 + SLOPE * SLOPE)), Vector3(0.0, STRIKE_Y - 0.006 + CASCADE_SPAN * 0.5 * SLOPE, STRIKE_Z - CASCADE_SPAN * 0.5), _material(Color("131420"), 0.6, 0.2))
	cascade.rotation.x = atan(SLOPE)
	for midi in range(24, 109, 12):
		var guide: MeshInstance3D = _box("OctaveGuide%d" % midi, Vector3(0.0005, 0.0004, CASCADE_SPAN * sqrt(1.0 + SLOPE * SLOPE)), Vector3(_rest[midi - 21].x - KeyMap3D.WHITE_STEP * 0.5, STRIKE_Y - 0.0035 + CASCADE_SPAN * 0.5 * SLOPE, STRIKE_Z - CASCADE_SPAN * 0.5), _material(Color("303342"), 0.8, 0.1))
		guide.rotation.x = atan(SLOPE)
	_pill_font = FontVariation.new()
	_pill_font.base_font = ThemeDB.fallback_font
	_pill_font.variation_embolden = 0.28
	_gaussian_tex = _generate_gaussian_texture(128)
	_overlay_root = Node2D.new()
	_overlay_root.name = "CascadeOverlayRoot"
	add_child(_overlay_root)
	_overlay_clip = Control.new()
	_overlay_clip.name = "CascadeOverlayClip"
	_overlay_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_clip.clip_contents = true
	_overlay_root.add_child(_overlay_clip)
	_pill_layer = Node2D.new()
	_pill_layer.name = "CascadePillLayer"
	_pill_layer.draw.connect(_draw_cascade_pills)
	_overlay_clip.add_child(_pill_layer)
	_flare_layer = Node2D.new()
	_flare_layer.name = "CascadeFlareLayer"
	var flare_additive: CanvasItemMaterial = CanvasItemMaterial.new()
	flare_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flare_layer.material = flare_additive
	_flare_layer.draw.connect(_draw_cascade_flares)
	_overlay_clip.add_child(_flare_layer)
	resized.connect(_on_resized)
	arrange(size)

static func musical_note_name(midi: int) -> String:
	if midi < 21 or midi > 108:
		return ""
	return NOTE_NAMES[midi % 12]

static func _generate_gaussian_texture(size_px: int = 128) -> ImageTexture:
	var img: Image = Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var half: float = float(size_px) * 0.5
	for y: int in range(size_px):
		for x: int in range(size_px):
			var dx: float = (float(x) - half + 0.5) / half
			var dy: float = (float(y) - half + 0.5) / half
			var r2: float = dx * dx + dy * dy
			var alpha: float = 0.0
			if r2 < 1.0:
				alpha = exp(-r2 * 5.0)
				alpha *= clampf((1.0 - sqrt(r2)) / 0.25, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)

func _material(tint: Color, roughness: float, specular: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = roughness
	material.metallic_specular = specular
	return material

func _box(label: String, dimensions: Vector3, location: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.material_override = material
	node.position = location
	world_root.add_child(node)
	return node

func _is_black(midi: int) -> bool:
	return key_map.is_black_key(midi)

func _build_keyboard() -> void:
	_pressed.resize(88)
	_depth.resize(88)
	_depth_vel.resize(88)
	_energy.resize(88)
	_rail_pulse.resize(88)
	_strike_serial.resize(88)
	_key_colors.clear()
	_key_shades.clear()
	_key_shade_materials.clear()
	_key_shade_shader = Shader.new()
	_key_shade_shader.code = """shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back;
uniform float press = 0.0;
uniform float is_black = 0.0;
void fragment() {
	float edge_x = min(UV.x, 1.0 - UV.x);
	float edge_y = min(UV.y, 1.0 - UV.y);
	if (is_black < 0.5) {
		float side_ao = pow(1.0 - smoothstep(0.0, 0.30, edge_x), 1.55);
		float back_ao = 1.0 - smoothstep(0.0, 0.55, UV.y);
		float front_lip = smoothstep(0.88, 1.0, UV.y);
		float a = clamp((0.20 + 0.44 * side_ao + 0.24 * back_ao + 0.28 * front_lip) * press, 0.0, 0.70);
		ALBEDO = vec3(0.05, 0.07, 0.13);
		ALPHA = a;
	} else {
		float perimeter = max(1.0 - smoothstep(0.0, 0.22, edge_x), 1.0 - smoothstep(0.0, 0.16, edge_y));
		float inner_sheen = smoothstep(0.16, 0.44, edge_x) * smoothstep(0.08, 0.72, UV.y) * (1.0 - smoothstep(0.86, 1.0, UV.y));
		ALBEDO = mix(vec3(0.02, 0.03, 0.06), vec3(0.56, 0.63, 0.78), inner_sheen);
		ALPHA = clamp((0.36 * perimeter + 0.42 * inner_sheen) * press, 0.0, 0.58);
	}
}
"""
	_rail_halo_shader = Shader.new()
	_rail_halo_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 tint : source_color = vec4(0.39, 0.91, 0.82, 1.0);
uniform float intensity = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float core = exp(-(p.x * p.x * 2.8 + p.y * p.y * 5.2));
	float edge = smoothstep(1.0, 0.15, length(p));
	float a = core * edge * clamp(intensity, 0.0, 2.2);
	vec3 col = mix(tint.rgb, vec3(1.0), clamp(core * 0.55 * min(intensity, 1.0), 0.0, 0.65));
	ALBEDO = col * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
	for midi in range(21, 109):
		var black: bool = _is_black(midi)
		var material: StandardMaterial3D = _material(Color("171822") if black else Color("f4f1ea"), 0.25 if black else 0.24, 0.68 if black else 0.55)
		material.emission_enabled = true
		material.emission_energy_multiplier = 0.0
		var dimensions: Vector3 = key_map.get_key_dimensions(midi)
		var location: Vector3 = key_map.get_key_rest_position(midi)
		var key: MeshInstance3D = _box("Key%d" % midi, dimensions, location, material)
		_keys.append(key)
		_key_materials.append(material)
		_rest.append(location)
		_key_colors.append(Color.CYAN)
		var shade_mat: ShaderMaterial = ShaderMaterial.new()
		shade_mat.shader = _key_shade_shader
		shade_mat.set_shader_parameter("press", 0.0)
		shade_mat.set_shader_parameter("is_black", 1.0 if black else 0.0)
		var shade_mesh: PlaneMesh = PlaneMesh.new()
		shade_mesh.size = Vector2(dimensions.x * 0.995, dimensions.z * 0.995)
		var shade: MeshInstance3D = MeshInstance3D.new()
		shade.name = "KeyShade%d" % midi
		shade.mesh = shade_mesh
		shade.material_override = shade_mat
		shade.position = Vector3(0.0, dimensions.y * 0.5 + 0.00025, 0.0)
		shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shade.visible = false
		key.add_child(shade)
		_key_shades.append(shade)
		_key_shade_materials.append(shade_mat)
		var seg_w: float = KeyMap3D.BLACK_WIDTH * 1.15 if black else KeyMap3D.WHITE_WIDTH * 1.04
		var seg_mat: StandardMaterial3D = StandardMaterial3D.new()
		seg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		seg_mat.albedo_color = Color.CYAN
		var seg: MeshInstance3D = _box("RailGlow%d" % midi, Vector3(seg_w, 0.0044, 0.0044), Vector3(location.x, 0.0246, -0.079), seg_mat)
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.visible = false
		_rail_segments.append(seg)
		_rail_segment_materials.append(seg_mat)
		var halo_mat: ShaderMaterial = ShaderMaterial.new()
		halo_mat.shader = _rail_halo_shader
		halo_mat.set_shader_parameter("tint", Color.CYAN)
		halo_mat.set_shader_parameter("intensity", 0.0)
		var halo_mesh: PlaneMesh = PlaneMesh.new()
		halo_mesh.size = Vector2(seg_w * 2.2, 0.014)
		var halo: MeshInstance3D = MeshInstance3D.new()
		halo.name = "RailHalo%d" % midi
		halo.mesh = halo_mesh
		halo.material_override = halo_mat
		halo.position = Vector3(location.x, 0.0265, -0.0835)
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		halo.visible = false
		world_root.add_child(halo)
		_rail_halos.append(halo)
		_rail_halo_materials.append(halo_mat)
	_box("LacquerChassis", Vector3(1.28, 0.045, 0.29), Vector3(0.0, -0.036, -0.045), _material(Color("0b0c12"), 0.2, 0.7))
	var rail_material: StandardMaterial3D = _material(Color("3b647a"), 0.3, 0.55)
	rail_material.emission_enabled = true
	rail_material.emission = Color("4a90ab")
	rail_material.emission_energy_multiplier = 0.45
	_box("StrikeLineRail", Vector3(1.23, 0.003, 0.003), Vector3(0.0, 0.024, -0.079), rail_material)

func _build_hands() -> void:
	for side in range(2):
		var hand: Node3D = HAND_SCENES[side].instantiate() as Node3D
		if hand == null:
			continue
		hand.name = "LeftHand3D" if side == 0 else "RightHand3D"
		world_root.add_child(hand)
		# GLB is already metric: Y spans -0.190..0.022, wrist at origin.
		# +90 degrees maps the negative-Y fingers toward the piano's -Z;
		# original positive-Z palm surface faces down toward the key tops.
		hand.rotation.x = PI * 0.5
		hand.position = Vector3(-0.18 if side == 0 else 0.18, HandIKControllerClass.WHITE_REST_Y, HandIKControllerClass.WHITE_REST_Z)
		hand.visible = _hands_enabled
		_apply_hand_material(hand)
		_hands.append(hand)
		var skeleton: Skeleton3D = hand.find_child("Skeleton3D", true, false) as Skeleton3D
		_skeletons.append(skeleton)
		hand_controllers.append(HandIKControllerClass.new(side, hand, skeleton, world_root))
	_update_hands(1.0)

func _apply_hand_material(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh: MeshInstance3D = node as MeshInstance3D
		mesh.layers = 3
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = ANIME
		material.set_shader_parameter("u_albedo_tex", SKIN)
		material.set_shader_parameter("u_skin_color", Color(0.84, 0.67, 0.56, 1.0))
		material.set_shader_parameter("u_shadow_color", Color(0.24, 0.16, 0.15, 1.0))
		material.set_shader_parameter("u_nail_color", Color(0.88, 0.73, 0.67, 1.0))
		var outline: ShaderMaterial = ShaderMaterial.new()
		outline.shader = OUTLINE
		outline.set_shader_parameter("u_outline_width", 0.00038)
		outline.set_shader_parameter("u_outline_color", Color(0.11, 0.07, 0.08, 1.0))
		material.next_pass = outline
		mesh.material_override = material
	for child: Node in node.get_children():
		_apply_hand_material(child)

func press_key(midi: int, color: Color, token: int = -1) -> void:
	var index: int = midi - 21
	if index < 0 or index >= _keys.size():
		return
	_pressed[index] = 1
	_depth[index] = minf(_depth[index], 0.25)
	_depth_vel[index] = maxf(_depth_vel[index], 12.0)
	_strike_serial[index] += 1
	_energy[index] = 2.0
	_rail_pulse[index] = 1.0
	_key_colors[index] = color
	_key_materials[index].emission = color
	if _live_cascade_enabled:
		for existing: LiveNote in _live_notes:
			if existing.midi == midi and existing.released < 0.0:
				existing.released = _elapsed_time
		_live_notes.append(LiveNote.new(token, midi, _elapsed_time, color))
		while _live_notes.size() > MAX_LIVE_NOTES:
			_live_notes.pop_front()
		_request_cascade_redraw()

func release_live_note(token: int) -> void:
	if token < 0:
		return
	var changed: bool = false
	for live_note: LiveNote in _live_notes:
		if live_note.token == token and live_note.released < 0.0:
			live_note.released = _elapsed_time
			changed = true
	if changed:
		_request_cascade_redraw()

func release_key(midi: int) -> void:
	var index: int = midi - 21
	if index >= 0 and index < _pressed.size():
		_pressed[index] = 0
	var changed: bool = false
	for live_note: LiveNote in _live_notes:
		if live_note.midi == midi and live_note.released < 0.0:
			live_note.released = _elapsed_time
			changed = true
	if changed:
		_request_cascade_redraw()

func release_all() -> void:
	_pressed.fill(0)
	var changed: bool = false
	for live_note: LiveNote in _live_notes:
		if live_note.released < 0.0:
			live_note.released = _elapsed_time
			changed = true
	if changed:
		_request_cascade_redraw()

func set_live_cascade_enabled(enabled: bool) -> void:
	if _live_cascade_enabled == enabled:
		return
	_live_cascade_enabled = enabled
	if not _live_cascade_enabled:
		_live_notes.clear()
	_overlay_had_content = true
	_request_cascade_redraw()

func recolor_active_live_notes(color: Color) -> void:
	var changed: bool = false
	for live_note: LiveNote in _live_notes:
		if live_note.released < 0.0:
			live_note.color = color
			changed = true
	if changed:
		_request_cascade_redraw()

func _request_cascade_redraw() -> void:
	if _pill_layer != null:
		_pill_layer.queue_redraw()
	if _flare_layer != null:
		_flare_layer.queue_redraw()

func set_hands_visible(enabled: bool) -> void:
	_hands_enabled = enabled
	for hand: Node3D in _hands:
		hand.visible = enabled

func set_notes(notes: Array[StageNote]) -> void:
	_notes.clear()
	for note: StageNote in notes:
		if note != null and note.midi >= 21 and note.midi <= 108:
			_notes.append(StageNote.new(note.midi, note.start, note.duration, note.color))
	_notes.sort_custom(func(a: StageNote, b: StageNote) -> bool: return a.start < b.start)
	_note_cursor = 0
	while _note_cursor < _notes.size() and _notes[_note_cursor].start + _notes[_note_cursor].duration < _playback_time:
		_note_cursor += 1
	_visual_note_cursor = 0
	while _visual_note_cursor < _notes.size() and _notes[_visual_note_cursor].start + _notes[_visual_note_cursor].duration < _visual_playback_time:
		_visual_note_cursor += 1
	if not _live_cascade_enabled:
		_request_cascade_redraw()

func set_playback_time(seconds: float) -> void:
	var next_t: float = maxf(seconds, 0.0)
	if next_t < _playback_time:
		_note_cursor = 0
		_visual_note_cursor = 0
		_visual_playback_time = next_t
	_playback_time = next_t
	if not _smooth_cascade_clock:
		_visual_playback_time = _playback_time

func set_smooth_cascade_clock(enabled: bool) -> void:
	if _smooth_cascade_clock == enabled:
		return
	_smooth_cascade_clock = enabled
	snap_cascade_clock()

func snap_cascade_clock() -> void:
	_visual_playback_time = _playback_time
	_visual_note_cursor = 0
	while _visual_note_cursor < _notes.size() and _notes[_visual_note_cursor].start + _notes[_visual_note_cursor].duration < _visual_playback_time:
		_visual_note_cursor += 1
	_request_cascade_redraw()

func set_anticipation_enabled(enabled: bool) -> void:
	_anticipation_enabled = enabled

func _project_3d(world_pos: Vector3) -> Vector2:
	if camera == null or stage_viewport == null:
		return Vector2.ZERO
	var vp_size: Vector2 = stage_viewport.get_visible_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		return Vector2.ZERO
	var projected: Vector2 = camera.unproject_position(world_pos)
	return Vector2(projected.x * size.x / vp_size.x, projected.y * size.y / vp_size.y)

func _cascade_point_3d(x: float, dist: float) -> Vector3:
	return Vector3(x, STRIKE_Y + dist * SLOPE, STRIKE_Z - dist)

func _update_overlay_bounds() -> void:
	if _overlay_clip == null:
		return
	var rail_p: Vector2 = _project_3d(Vector3(0.0, 0.024, -0.079))
	if rail_p.y <= 1.0:
		_strike_rail_y = clampf(size.y * 0.80, 1.0, maxf(1.0, size.y))
	else:
		_strike_rail_y = clampf(rail_p.y, 1.0, maxf(1.0, size.y))
	var new_size: Vector2 = Vector2(maxf(1.0, size.x), _strike_rail_y)
	var changed: bool = not _overlay_clip.size.is_equal_approx(new_size)
	_overlay_clip.position = Vector2.ZERO
	_overlay_clip.size = new_size
	if changed:
		_request_cascade_redraw()

func arrange(viewport_size: Vector2) -> void:
	size = Vector2(maxf(1.0, viewport_size.x), maxf(1.0, viewport_size.y))
	if camera == null:
		return
	var pitch: float = deg_to_rad(-79.0)
	var aspect: float = maxf(size.x / maxf(size.y, 1.0), 0.01)
	var c: float = cos(pitch)
	var s: float = sin(pitch)
	var dy_front: float = KeyMap3D.WHITE_HEIGHT * 0.5 - 1.65
	var fov: float = 25.0
	var z0: float = 0.10
	# Solve front-edge depth and vertical FOV together, keeping its screen Y at 95%.
	for _iter in range(4):
		var tan_h: float = tan(deg_to_rad(fov) * 0.5)
		var k: float = -0.90 * tan_h
		var dz: float = (-dy_front * c + k * dy_front * s) / (s + k * c)
		var depth_front: float = dy_front * s - dz * c
		z0 = 0.075 - dz
		var half_width: float = key_map.get_key_rest_position(108).x + KeyMap3D.WHITE_WIDTH * 0.5
		var tan_h_new: float = half_width / (0.962 * maxf(depth_front, 0.1) * aspect)
		fov = clampf(rad_to_deg(2.0 * atan(tan_h_new)), 1.0, 179.0)
	camera.fov = fov
	camera.position = Vector3(0.0, 1.65, z0)
	camera.rotation_degrees = Vector3(-79.0, 0.0, 0.0)
	_update_overlay_bounds()
	_request_cascade_redraw()

func _on_resized() -> void:
	arrange(size)

func _process(delta: float) -> void:
	var dt: float = clampf(delta, 0.0, 0.033)
	var damping: float = 1.0 - exp(-24.0 * delta)
	for index in range(_keys.size()):
		var target_depth: float = float(_pressed[index])
		var stiffness: float = 780.0 if _pressed[index] != 0 else 460.0
		var damp: float = 44.0 if _pressed[index] != 0 else 34.0
		var accel: float = (target_depth - _depth[index]) * stiffness - _depth_vel[index] * damp
		_depth_vel[index] += accel * dt
		_depth[index] = clampf(_depth[index] + _depth_vel[index] * dt, -0.04, 1.08)
		if absf(_depth[index] - target_depth) < 0.0005 and absf(_depth_vel[index]) < 0.005:
			_depth[index] = target_depth
			_depth_vel[index] = 0.0
		_keys[index].transform = key_map.get_key_pressed_transform(index + 21, _depth[index])
		var press_vis: float = clampf(_depth[index], 0.0, 1.0)
		var mat: StandardMaterial3D = _key_materials[index]
		if _is_black(index + 21):
			mat.albedo_color = Color("171822").lerp(Color("4a546e"), press_vis * 0.92)
			mat.roughness = lerpf(0.25, 0.12, press_vis)
			mat.metallic_specular = lerpf(0.68, 0.96, press_vis)
		else:
			mat.albedo_color = Color("f4f1ea").lerp(Color("9ea8bc"), press_vis * 0.92)
			mat.roughness = lerpf(0.24, 0.56, press_vis)
			mat.metallic_specular = lerpf(0.55, 0.16, press_vis)
		mat.emission_energy_multiplier = 0.0
		var shade: MeshInstance3D = _key_shades[index]
		shade.visible = press_vis > 0.005
		if shade.visible:
			_key_shade_materials[index].set_shader_parameter("press", press_vis)
		_energy[index] = 2.0 if _pressed[index] != 0 else _energy[index] * exp(-5.0 * dt)
		_rail_pulse[index] *= exp(-14.0 * dt)
		var active_glow: bool = _energy[index] > 0.01
		var seg: MeshInstance3D = _rail_segments[index]
		var halo: MeshInstance3D = _rail_halos[index]
		seg.visible = active_glow
		halo.visible = active_glow
		if active_glow:
			var pulse: float = _rail_pulse[index]
			var e_norm: float = clampf(_energy[index] * 0.5, 0.0, 1.0)
			var tint: Color = _key_colors[index]
			var core_col: Color = tint.lerp(Color.WHITE, 0.40 + 0.30 * pulse) * (1.1 + 0.7 * e_norm + 0.6 * pulse)
			core_col.a = 1.0
			_rail_segment_materials[index].albedo_color = core_col
			seg.scale = Vector3(1.0 + 0.14 * pulse, 1.0 + 0.55 * pulse, 1.0 + 0.50 * pulse)
			_rail_halo_materials[index].set_shader_parameter("tint", tint)
			_rail_halo_materials[index].set_shader_parameter("intensity", _energy[index] * 0.55 + pulse * 0.65)
			halo.scale = Vector3(1.0 + 0.25 * pulse, 1.0, 1.0 + 0.35 * pulse)
	_elapsed_time += delta
	_update_hands(delta)
	_update_hand_lights(damping)
	_update_cascade(delta)

func _update_hands(delta: float) -> void:
	while _note_cursor < _notes.size() and _notes[_note_cursor].start + _notes[_note_cursor].duration < _playback_time:
		_note_cursor += 1
	var wrists: Array[float] = []
	for hand: Node3D in _hands:
		wrists.append(hand.position.x)
	var plans: Array[FingeringSolver.HandPlan] = fingering_solver.solve(key_map, _pressed, _depth, _notes, _note_cursor, _playback_time, wrists, _anticipation_enabled)
	for side: int in range(hand_controllers.size()):
		hand_controllers[side].update_hand(plans[side], key_map, delta, _elapsed_time, _strike_serial, _depth)

func get_visible_pills() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _live_cascade_enabled:
		for live_note: LiveNote in _live_notes:
			var is_black: bool = _is_black(live_note.midi)
			var min_len: float = PILL_MIN_LEN_BLACK if is_black else PILL_MIN_LEN_WHITE
			var end_t: float = _elapsed_time if live_note.released < 0.0 else live_note.released
			var dist_near: float = LIVE_RISE_SPEED * maxf(0.0, _elapsed_time - end_t)
			if dist_near > CASCADE_SPAN + 0.08:
				continue
			var length: float = maxf(min_len, LIVE_RISE_SPEED * maxf(0.0, end_t - live_note.born))
			var dist_far: float = dist_near + length
			result.append({
				"midi": live_note.midi,
				"label": musical_note_name(live_note.midi),
				"dist_near": dist_near,
				"dist_far": dist_far,
				"color": live_note.color,
				"is_black": is_black,
				"held": live_note.released < 0.0
			})
		return result
	var display_t: float = _visual_playback_time if _smooth_cascade_clock else _playback_time
	if _smooth_cascade_clock:
		while _visual_note_cursor < _notes.size() and _notes[_visual_note_cursor].start + _notes[_visual_note_cursor].duration < display_t:
			_visual_note_cursor += 1
	else:
		while _note_cursor < _notes.size() and _notes[_note_cursor].start + _notes[_note_cursor].duration < display_t:
			_note_cursor += 1
	var cursor: int = _visual_note_cursor if _smooth_cascade_clock else _note_cursor
	var used: int = 0
	for index: int in range(cursor, _notes.size()):
		var note: StageNote = _notes[index]
		if note.start > display_t + LOOKAHEAD or used >= MAX_BARS:
			break
		if note.start + note.duration < display_t:
			continue
		var is_black: bool = _is_black(note.midi)
		var min_len: float = PILL_MIN_LEN_BLACK if is_black else PILL_MIN_LEN_WHITE
		var raw_near: float = (note.start - display_t) / LOOKAHEAD * CASCADE_SPAN
		var raw_far: float = maxf((note.start + note.duration - display_t) / LOOKAHEAD * CASCADE_SPAN, raw_near + min_len)
		var dist_near: float = maxf(raw_near, 0.0)
		var dist_far: float = minf(raw_far, CASCADE_SPAN)
		if dist_far <= dist_near + 0.002:
			continue
		result.append({
			"midi": note.midi,
			"label": musical_note_name(note.midi),
			"dist_near": dist_near,
			"dist_far": dist_far,
			"color": note.color,
			"is_black": is_black,
			"held": raw_near <= 0.0
		})
		used += 1
	return result

func _update_cascade(delta: float = 0.0) -> void:
	var dt: float = clampf(delta, 0.0, 0.05)
	if _smooth_cascade_clock:
		if _visual_playback_time > _playback_time:
			_visual_playback_time = _playback_time
			_visual_note_cursor = 0
		else:
			_visual_playback_time = lerpf(_visual_playback_time, _playback_time, 1.0 - exp(-18.0 * dt))
			if absf(_playback_time - _visual_playback_time) < 0.0008:
				_visual_playback_time = _playback_time
	else:
		_visual_playback_time = _playback_time
	while _note_cursor < _notes.size() and _notes[_note_cursor].start + _notes[_note_cursor].duration < _playback_time:
		_note_cursor += 1
	while _visual_note_cursor < _notes.size() and _notes[_visual_note_cursor].start + _notes[_visual_note_cursor].duration < _visual_playback_time:
		_visual_note_cursor += 1
	for index: int in range(_live_notes.size() - 1, -1, -1):
		var live_note: LiveNote = _live_notes[index]
		if live_note.released >= 0.0 and LIVE_RISE_SPEED * maxf(0.0, _elapsed_time - live_note.released) > CASCADE_SPAN + 0.15:
			_live_notes.remove_at(index)
	_update_overlay_bounds()
	var display_t: float = _visual_playback_time if _smooth_cascade_clock else _playback_time
	var cursor: int = _visual_note_cursor if _smooth_cascade_clock else _note_cursor
	var has_pills: bool = not _live_notes.is_empty() if _live_cascade_enabled else false
	if not _live_cascade_enabled:
		for index: int in range(cursor, _notes.size()):
			var note: StageNote = _notes[index]
			if note.start > display_t + LOOKAHEAD:
				break
			if note.start + note.duration >= display_t:
				has_pills = true
				break
	var has_glow: bool = false
	for index: int in range(_energy.size()):
		if _energy[index] > 0.01:
			has_glow = true
			break
	var gliding: bool = _smooth_cascade_clock and absf(_playback_time - _visual_playback_time) > 0.0005
	var has_content: bool = has_pills or has_glow or gliding
	if visible and (has_content or _overlay_had_content):
		_request_cascade_redraw()
	_overlay_had_content = has_content

func _draw_cascade_pills() -> void:
	if _pill_layer == null or _strike_rail_y <= 1.0:
		return
	var pills: Array[Dictionary] = get_visible_pills()
	for pass_black: int in range(2):
		var want_black: bool = pass_black == 1
		for pill: Dictionary in pills:
			if bool(pill["is_black"]) == want_black:
				_draw_3d_pill(pill)

func _draw_3d_pill(pill: Dictionary) -> void:
	if _pill_layer == null or _strike_rail_y <= 1.0 or camera == null:
		return
	var midi: int = int(pill["midi"])
	var index: int = midi - 21
	if index < 0 or index >= _rest.size():
		return
	var d0: float = float(pill["dist_near"])
	var d1: float = minf(float(pill["dist_far"]), CASCADE_SPAN + 0.08)
	var len_3d: float = maxf(0.004, d1 - d0)
	var d_high: float = d0 + len_3d
	var center_x: float = _rest[index].x
	var is_black: bool = bool(pill["is_black"])
	var width_3d: float = PILL_BLACK_WIDTH if is_black else PILL_WHITE_WIDTH
	var half_w: float = width_3d * 0.5
	var p0: Vector3 = _cascade_point_3d(center_x, d0)
	var p1: Vector3 = _cascade_point_3d(center_x, d_high)
	if camera.is_position_behind(p0) or camera.is_position_behind(p1):
		return
	var r: float = minf(width_3d * 0.46, len_3d * 0.50)
	var x_left: float = center_x - half_w
	var x_right: float = center_x + half_w
	var corner_x: PackedFloat32Array = PackedFloat32Array([x_left + r, x_right - r, x_right - r, x_left + r])
	var corner_d: PackedFloat32Array = PackedFloat32Array([d_high - r, d_high - r, d0 + r, d0 + r])
	var points: PackedVector2Array = PackedVector2Array()
	var min_y: float = INF
	var max_y: float = -INF
	for corner: int in range(4):
		var cx: float = corner_x[corner]
		var cd: float = corner_d[corner]
		for seg: int in range(7):
			var angle: float = PI + float(corner) * PI * 0.5 + float(seg) * PI / 12.0
			var pt: Vector2 = _project_3d(_cascade_point_3d(cx + cos(angle) * r, cd - sin(angle) * r))
			min_y = minf(min_y, pt.y)
			max_y = maxf(max_y, pt.y)
			if points.is_empty() or points[points.size() - 1].distance_squared_to(pt) > 0.01:
				points.append(pt)
	if points.size() < 3 or max_y < -4.0 or min_y > _strike_rail_y + 4.0:
		return
	var base_col: Color = pill["color"]
	if is_black:
		base_col = base_col.darkened(0.10)
	var fill_col: Color = Color(base_col.r, base_col.g, base_col.b, 0.94)
	_pill_layer.draw_colored_polygon(points, fill_col)
	var outline_pts: PackedVector2Array = points.duplicate()
	outline_pts.append(points[0])
	_pill_layer.draw_polyline(outline_pts, Color(1.0, 1.0, 1.0, 0.72), 1.35, true)
	var label: String = str(pill["label"])
	if label.is_empty():
		return
	var bottom_p: Vector2 = _project_3d(p0)
	var top_p: Vector2 = _project_3d(p1)
	var vis_d1: float = d_high
	if top_p.y < 0.0 and bottom_p.y > top_p.y + 1.0:
		var vis_frac: float = clampf(bottom_p.y / (bottom_p.y - top_p.y), 0.12, 1.0)
		vis_d1 = lerpf(d0, d_high, vis_frac)
	var d_min_lbl: float = d0 + r * 0.85
	var d_max_lbl: float = maxf(d_min_lbl, d_high - r * 0.85)
	var label_d: float = clampf((d0 + vis_d1) * 0.5, d_min_lbl, d_max_lbl)
	var center_2d: Vector2 = _project_3d(_cascade_point_3d(center_x, label_d))
	var left_2d: Vector2 = _project_3d(_cascade_point_3d(x_left, label_d))
	var right_2d: Vector2 = _project_3d(_cascade_point_3d(x_right, label_d))
	var proj_w: float = maxf(0.0, right_2d.x - left_2d.x)
	var proj_h: float = maxf(0.0, minf(bottom_p.y, _strike_rail_y) - maxf(top_p.y, 0.0))
	var font: Font = _pill_font if _pill_font != null else ThemeDB.fallback_font
	var font_size: int = clampi(int(proj_w * 0.56), 5, 16)
	var label_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var max_w: float = maxf(0.0, proj_w - 2.0)
	while font_size > 5 and (label_size.x > max_w or float(font_size) + 2.0 > proj_h):
		font_size -= 1
		label_size = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	if label_size.x <= max_w and proj_h >= float(font_size) + 2.0:
		var lum: float = fill_col.r * 0.2126 + fill_col.g * 0.7152 + fill_col.b * 0.0722
		var text_col: Color = Color("#141c2a") if lum > 0.74 else Color.WHITE
		var baseline_y: float = center_2d.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		_pill_layer.draw_string(font, Vector2(center_2d.x - label_size.x * 0.5, baseline_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_col)

func _draw_cascade_flares() -> void:
	if _flare_layer == null or _gaussian_tex == null or _strike_rail_y <= 1.0 or _rest.size() < 88:
		return
	var x_left: float = _project_3d(Vector3(_rest[0].x - KeyMap3D.WHITE_WIDTH * 0.5, 0.024, -0.079)).x
	var x_right: float = _project_3d(Vector3(_rest[87].x + KeyMap3D.WHITE_WIDTH * 0.5, 0.024, -0.079)).x
	if x_right <= x_left:
		x_left = 0.0
		x_right = size.x
	var active_count: int = 0
	var avg_color: Color = Color(0.0, 0.0, 0.0, 0.0)
	for index: int in range(_energy.size()):
		if _energy[index] > 0.01:
			active_count += 1
			avg_color += _key_colors[index]
	var line_tint: Color = Color(0.55, 0.66, 1.0)
	if active_count > 0:
		line_tint = (avg_color / float(active_count)).lerp(Color(0.85, 0.90, 1.0), 0.35)
	var line_y: float = _strike_rail_y - 1.0
	for spread: int in range(8, 0, -1):
		var a: float = (0.006 + 0.018 * exp(-float(spread) * 0.32)) * (1.35 if active_count > 0 else 0.75)
		_flare_layer.draw_line(Vector2(x_left, line_y), Vector2(x_right, line_y), Color(line_tint.r, line_tint.g, line_tint.b, a), float(spread) * 2.0, true)
	_flare_layer.draw_line(Vector2(x_left, line_y), Vector2(x_right, line_y), Color(1.4, 1.4, 1.4, 0.55), 1.2, true)
	if active_count == 0:
		return
	var density_scale: float = clampf(1.0 / sqrt(maxf(1.0, float(active_count) * 0.40)), 0.28, 1.0)
	for index: int in range(_energy.size()):
		if _energy[index] <= 0.01:
			continue
		var midi: int = index + 21
		var key_x: float = _rest[index].x
		var half_w: float = (KeyMap3D.BLACK_WIDTH if _is_black(midi) else KeyMap3D.WHITE_WIDTH) * 0.5
		var base_pos: Vector2 = _project_3d(Vector3(key_x, 0.024, -0.079))
		var edge_l: Vector2 = _project_3d(Vector3(key_x - half_w, 0.024, -0.079))
		var edge_r: Vector2 = _project_3d(Vector3(key_x + half_w, 0.024, -0.079))
		var key_w: float = maxf(6.0, absf(edge_r.x - edge_l.x))
		var pulse: float = _rail_pulse[index]
		var e_norm: float = clampf(_energy[index] * 0.5, 0.0, 1.0)
		var tint: Color = _key_colors[index]
		var fw: float = key_w * (4.4 + 1.4 * pulse)
		var fh: float = key_w * (3.0 + 1.0 * pulse)
		var f_alpha: float = clampf((0.42 * e_norm + 0.36 * pulse) * density_scale, 0.0, 0.92)
		_flare_layer.draw_texture_rect(_gaussian_tex, Rect2(base_pos.x - fw * 0.5, _strike_rail_y - fh * 0.5, fw, fh), false, Color(tint.r * 1.25, tint.g * 1.25, tint.b * 1.25, f_alpha))
		var cw: float = key_w * (2.2 + 0.7 * pulse)
		var ch: float = key_w * (1.6 + 0.5 * pulse)
		var c_alpha: float = clampf((0.55 * e_norm + 0.50 * pulse) * density_scale, 0.0, 1.0)
		_flare_layer.draw_texture_rect(_gaussian_tex, Rect2(base_pos.x - cw * 0.5, _strike_rail_y - ch * 0.5, cw, ch), false, Color(1.75, 1.55, 1.65, c_alpha))

func _update_hand_lights(damping: float) -> void:
	for side in range(_hand_lights.size()):
		var light: OmniLight3D = _hand_lights[side]
		var tint: Color = Color(0.0, 0.0, 0.0, 0.0)
		var count: int = 0
		for index in range(_pressed.size()):
			if _pressed[index] == 0:
				continue
			var owner_side: int = 0 if index + 21 < 60 else 1
			if _hands.size() == 2:
				owner_side = 0 if absf(_rest[index].x - _hands[0].position.x) <= absf(_rest[index].x - _hands[1].position.x) else 1
			if owner_side == side:
				tint += _key_colors[index]
				count += 1
		if side < _hands.size():
			light.position.x = lerpf(light.position.x, _hands[side].position.x, damping)
		if count > 0:
			tint /= float(count)
			tint.a = 1.0
			tint = tint.lerp(Color(1.0, 0.96, 0.92, 1.0), 0.45)
			light.light_color = light.light_color.lerp(tint, damping)
		light.light_energy = lerpf(light.light_energy, minf(0.55, 0.22 + 0.08 * float(count)) if count > 0 else 0.0, damping)
