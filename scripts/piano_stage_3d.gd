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

const KeyMap3DClass = preload("res://scripts/stage3d/key_map_3d.gd")
const FingeringSolverClass = preload("res://scripts/stage3d/fingering_solver.gd")
const HandIKControllerClass = preload("res://scripts/stage3d/hand_ik_controller.gd")
const SLOPE: float = 0.08
const CASCADE_SPAN: float = 1.15
const STRIKE_Z: float = -0.082
const STRIKE_Y: float = 0.028
const MAX_BARS: int = 384
const LOOKAHEAD: float = 4.0
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
var _bars: Array[MeshInstance3D] = []
var _bar_shader: Shader
var _playback_time: float = 0.0
var _note_cursor: int = 0
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
	light.rotation_degrees = Vector3(-58.0, -22.0, 0.0)
	light.light_energy = 0.72
	light.shadow_enabled = true
	light.shadow_opacity = 0.55
	light.shadow_bias = 0.0006
	light.shadow_normal_bias = 1.0
	light.directional_shadow_max_distance = 3.0
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
	_bar_shader = Shader.new()
	_bar_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 tint : source_color = vec4(0.3,0.8,1.0,1.0);
uniform vec3 dimensions = vec3(0.019,0.006,0.1);
void vertex() {
 vec3 p = VERTEX * dimensions;
 float radius = min(0.0025, min(dimensions.x, min(dimensions.y,dimensions.z))*0.45);
 vec3 inner = max(dimensions*0.5-vec3(radius),vec3(0.0001));
 vec3 nearest = clamp(p,-inner,inner);
 vec3 direction = normalize(p-nearest);
 VERTEX = (nearest + direction*radius)/dimensions;
 NORMAL = normalize(direction*dimensions);
}
void fragment() {
 ALBEDO = tint.rgb;
 EMISSION = tint.rgb * 1.5;
}
"""
	resized.connect(_on_resized)
	arrange(size)

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

func press_key(midi: int, color: Color) -> void:
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

func release_key(midi: int) -> void:
	var index: int = midi - 21
	if index >= 0 and index < _pressed.size():
		_pressed[index] = 0

func release_all() -> void:
	_pressed.fill(0)

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

func set_playback_time(seconds: float) -> void:
	if seconds < _playback_time:
		_note_cursor = 0
	_playback_time = maxf(seconds, 0.0)

func set_anticipation_enabled(enabled: bool) -> void:
	_anticipation_enabled = enabled

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
			mat.albedo_color = Color("171822").lerp(Color("2c3244"), press_vis * 0.70)
			mat.roughness = lerpf(0.25, 0.16, press_vis)
		else:
			mat.albedo_color = Color("f4f1ea").lerp(Color("c9cfd9"), press_vis * 0.85)
			mat.roughness = lerpf(0.24, 0.36, press_vis)
		mat.emission_energy_multiplier = 0.0
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
	_update_cascade()

func _update_hands(delta: float) -> void:
	while _note_cursor < _notes.size() and _notes[_note_cursor].start + _notes[_note_cursor].duration < _playback_time:
		_note_cursor += 1
	var wrists: Array[float] = []
	for hand: Node3D in _hands:
		wrists.append(hand.position.x)
	var plans: Array[FingeringSolver.HandPlan] = fingering_solver.solve(key_map, _pressed, _depth, _notes, _note_cursor, _playback_time, wrists, _anticipation_enabled)
	for side: int in range(hand_controllers.size()):
		hand_controllers[side].update_hand(plans[side], key_map, delta, _elapsed_time, _strike_serial, _depth)

func _update_cascade() -> void:
	if world_root == null or _bar_shader == null:
		return
	while _note_cursor < _notes.size() and _notes[_note_cursor].start + _notes[_note_cursor].duration < _playback_time:
		_note_cursor += 1
	var used: int = 0
	for index in range(_note_cursor, _notes.size()):
		var note: StageNote = _notes[index]
		if note.start > _playback_time + LOOKAHEAD or used >= MAX_BARS:
			break
		if note.start + note.duration < _playback_time:
			continue
		var near_time: float = clampf(note.start - _playback_time, 0.0, LOOKAHEAD)
		var far_time: float = clampf(note.start + note.duration - _playback_time, 0.0, LOOKAHEAD)
		var length: float = maxf((far_time - near_time) / LOOKAHEAD * CASCADE_SPAN, 0.005)
		var distance: float = (near_time + far_time) * 0.5 / LOOKAHEAD * CASCADE_SPAN
		if used >= _bars.size():
			var material: ShaderMaterial = ShaderMaterial.new()
			material.shader = _bar_shader
			var new_bar: MeshInstance3D = _box("NoteBar%d" % used, Vector3.ONE, Vector3.ZERO, material)
			var box_mesh: BoxMesh = new_bar.mesh as BoxMesh
			box_mesh.subdivide_width = 6
			box_mesh.subdivide_height = 4
			box_mesh.subdivide_depth = 6
			_bars.append(new_bar)
		var bar: MeshInstance3D = _bars[used]
		bar.visible = true
		bar.position = Vector3(_rest[note.midi - 21].x, STRIKE_Y + distance * SLOPE, STRIKE_Z - distance)
		bar.rotation.x = atan(SLOPE)
		bar.scale = Vector3(0.012 if _is_black(note.midi) else 0.019, 0.006, length * sqrt(1.0 + SLOPE * SLOPE))
		var material: ShaderMaterial = bar.material_override as ShaderMaterial
		material.set_shader_parameter("tint", note.color)
		material.set_shader_parameter("dimensions", bar.scale)
		used += 1
	for index in range(used, _bars.size()):
		_bars[index].visible = false

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
