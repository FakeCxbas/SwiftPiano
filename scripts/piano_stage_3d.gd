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

const WHITE_STEP: float = 0.0232
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
var _energy: PackedFloat32Array = PackedFloat32Array()
var _hands: Array[Node3D] = []
var _skeletons: Array[Skeleton3D] = []
var _notes: Array[StageNote] = []
var _bars: Array[MeshInstance3D] = []
var _bar_shader: Shader
var _playback_time: float = 0.0
var _note_cursor: int = 0
var _hands_enabled: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	stage_viewport = SubViewport.new()
	stage_viewport.name = "StageViewport"
	stage_viewport.own_world_3d = true
	stage_viewport.transparent_bg = true
	stage_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(stage_viewport)
	world_root = Node3D.new()
	world_root.name = "PianoWorld"
	stage_viewport.add_child(world_root)
	camera = Camera3D.new()
	camera.name = "StageCamera"
	camera.position = Vector3(0.0, 0.46, 0.38)
	camera.rotation_degrees = Vector3(-48.0, 0.0, 0.0)
	camera.fov = 50.0
	camera.near = 0.01
	camera.far = 10.0
	world_root.add_child(camera)
	camera.current = true
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c7c4e5")
	environment.ambient_light_energy = 0.3
	environment_node.environment = environment
	world_root.add_child(environment_node)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 0.25
	world_root.add_child(light)
	_build_keyboard()
	_build_hands()
	var cascade: MeshInstance3D = _box("CascadeSurface", Vector3(1.26, 0.004, 1.45 * sqrt(1.1024)), Vector3(0.0, 0.075 + 0.725 * 0.32, -0.875), _material(Color("131420"), 0.6, 0.2))
	cascade.rotation.x = atan(0.32)
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
	return midi % 12 in [1, 3, 6, 8, 10]

func _build_keyboard() -> void:
	_pressed.resize(88)
	_depth.resize(88)
	_energy.resize(88)
	var white_index: int = 0
	for midi in range(21, 109):
		var black: bool = _is_black(midi)
		var x: float = (float(white_index) - 25.5 - (0.5 if black else 0.0)) * WHITE_STEP
		var material: StandardMaterial3D = _material(Color("151419") if black else Color("faf7f2"), 0.35 if black else 0.22, 0.4 if black else 0.6)
		material.emission_enabled = true
		material.emission_energy_multiplier = 0.0
		var dimensions: Vector3 = Vector3(0.0125, 0.032, 0.095) if black else Vector3(0.0232, 0.022, 0.150)
		var location: Vector3 = Vector3(x, 0.027 if black else 0.0, -0.0275 if black else 0.0)
		var key: MeshInstance3D = _box("Key%d" % midi, dimensions, location, material)
		_keys.append(key)
		_key_materials.append(material)
		_rest.append(location)
		if not black:
			white_index += 1
	_box("LacquerChassis", Vector3(1.26, 0.045, 0.26), Vector3(0.0, -0.036, -0.035), _material(Color("100e15"), 0.12, 0.7))
	_box("Fallboard", Vector3(1.26, 0.10, 0.025), Vector3(0.0, 0.025, -0.155), _material(Color("100e15"), 0.12, 0.7))
	_box("GoldMolding", Vector3(1.255, 0.003, 0.004), Vector3(0.0, 0.077, -0.139), _material(Color("c5a059"), 0.24, 0.7))

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
		hand.position = Vector3(-0.18 if side == 0 else 0.18, 0.045, 0.15)
		hand.visible = _hands_enabled
		_apply_hand_material(hand)
		_hands.append(hand)
		_skeletons.append(hand.find_child("Skeleton3D", true, false) as Skeleton3D)

func _apply_hand_material(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh: MeshInstance3D = node as MeshInstance3D
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = ANIME
		material.set_shader_parameter("u_albedo_tex", SKIN)
		var outline: ShaderMaterial = ShaderMaterial.new()
		outline.shader = OUTLINE
		outline.set_shader_parameter("u_outline_width", 0.00065)
		material.next_pass = outline
		mesh.material_override = material
	for child: Node in node.get_children():
		_apply_hand_material(child)

func press_key(midi: int, color: Color) -> void:
	var index: int = midi - 21
	if index < 0 or index >= _keys.size():
		return
	_pressed[index] = 1
	_energy[index] = 2.0
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

func arrange(viewport_size: Vector2) -> void:
	size = Vector2(maxf(1.0, viewport_size.x), maxf(1.0, viewport_size.y))

func _on_resized() -> void:
	arrange(size)

func _process(delta: float) -> void:
	var damping: float = 1.0 - exp(-24.0 * delta)
	for index in range(_keys.size()):
		_depth[index] = lerpf(_depth[index], float(_pressed[index]), damping)
		var black: bool = _is_black(index + 21)
		_keys[index].position = _rest[index] - Vector3(0.0, _depth[index] * (0.009 if black else 0.007), 0.0)
		_keys[index].rotation.x = 0.0 if black else deg_to_rad(-3.2) * _depth[index]
		_energy[index] = 2.0 if _pressed[index] != 0 else _energy[index] * exp(-3.8 * delta)
		_key_materials[index].emission_energy_multiplier = _energy[index]
	_update_hands(damping)
	_update_cascade()

func _update_hands(damping: float) -> void:
	for side in range(_hands.size()):
		var hand: Node3D = _hands[side]
		var sum: float = 0.0
		var count: int = 0
		var fingers: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0])
		for index in range(_keys.size()):
			if _pressed[index] == 0 or (0 if index + 21 < 60 else 1) != side:
				continue
			sum += _rest[index].x
			count += 1
		if count > 0:
			hand.position.x = lerpf(hand.position.x, clampf(sum / count, -0.53, 0.53), damping)
		for index in range(_keys.size()):
			if _pressed[index] != 0 and (0 if index + 21 < 60 else 1) == side:
				var finger: int = clampi(roundi((_rest[index].x - hand.position.x) / 0.024 + 2.0), 0, 4)
				fingers[finger] = 1.0
		var skeleton: Skeleton3D = _skeletons[side]
		if skeleton == null:
			continue
		var names: PackedStringArray = PackedStringArray(["pinky", "ring", "middle", "index", "thumb"] if side == 0 else ["thumb", "index", "middle", "ring", "pinky"])
		for finger in range(5):
			for segment: String in ["proximal", "intermediate", "distal"]:
				var prefix: String = "thumb-phalanx-" if names[finger] == "thumb" else names[finger] + "-finger-phalanx-"
				var bone: int = skeleton.find_bone(prefix + segment)
				if bone < 0:
					continue
				var rest_rotation: Quaternion = skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
				var target: Quaternion = rest_rotation * Quaternion(Vector3.RIGHT, deg_to_rad(-12.0 * fingers[finger]))
				skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(target, damping))

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
		var length: float = maxf((far_time - near_time) / LOOKAHEAD * 1.45, 0.005)
		var distance: float = (near_time + far_time) * 0.5 / LOOKAHEAD * 1.45
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
		bar.position = Vector3(_rest[note.midi - 21].x, 0.085 + distance * 0.32, -0.15 - distance)
		bar.rotation.x = atan(0.32)
		bar.scale = Vector3(0.012 if _is_black(note.midi) else 0.019, 0.006, length * sqrt(1.0 + 0.32 * 0.32))
		var material: ShaderMaterial = bar.material_override as ShaderMaterial
		material.set_shader_parameter("tint", note.color)
		material.set_shader_parameter("dimensions", bar.scale)
		used += 1
	for index in range(used, _bars.size()):
		_bars[index].visible = false
