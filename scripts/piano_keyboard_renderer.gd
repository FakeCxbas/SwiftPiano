# SwiftPiano
# Copyright (c) 2026 Sebastián Zambrano
# Distributed under the terms of the MIT License.

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

var hand_left_tex: Texture2D = preload("res://assets/hands/hand_left.png")
var hand_right_tex: Texture2D = preload("res://assets/hands/hand_right.png")
var hand_shader: Shader = preload("res://shaders/hand_articulation.gdshader")
var hand_3d_left_scene: PackedScene = preload("res://assets/hands/hand_3d_left.glb")
var hand_3d_right_scene: PackedScene = preload("res://assets/hands/hand_3d_right.glb")

var hands_mode: String = "3d": # "3d", "2d", "off"
	set(mode):
		hands_mode = mode
		_sync_hand_mesh_visibility()
		queue_redraw()

var hands_3d_container: SubViewportContainer
var hands_3d_viewport: SubViewport
var hands_3d_camera: Camera3D
var left_hand_3d: Node3D
var right_hand_3d: Node3D
var left_hand_skel: Skeleton3D
var right_hand_skel: Skeleton3D
var left_finger_bones: Array = []
var right_finger_bones: Array = []
var hands_3d_cam_size: float = 0.55

var anime_hands_enabled: bool = true:
	set(enabled):
		anime_hands_enabled = enabled
		if not enabled:
			left_hand_dip = 0.0
			right_hand_dip = 0.0
			for i in range(5):
				left_finger_dips[i] = 0.0
				right_finger_dips[i] = 0.0
		_sync_hand_mesh_visibility()
		queue_redraw()

var left_hand_x: float = 0.0
var right_hand_x: float = 0.0
var left_hand_dip: float = 0.0
var right_hand_dip: float = 0.0
var left_hand_target_x: float = 0.0
var right_hand_target_x: float = 0.0
var left_hand_rot: float = 0.0
var right_hand_rot: float = 0.0
var hand_anticipation_left_x: float = -1.0
var hand_anticipation_right_x: float = -1.0
var elapsed_hands: float = 0.0
var hand_width: float = 120.0
var hand_size: Vector2 = Vector2(120.0, 180.0)

var left_finger_dips: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var right_finger_dips: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var left_finger_targets: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var right_finger_targets: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])

const LEFT_FINGER_UV_CENTERS = [0.071, 0.285, 0.445, 0.640, 0.943]
const RIGHT_FINGER_UV_CENTERS = [0.053, 0.356, 0.551, 0.712, 0.925]

var hand_grid_mesh: ArrayMesh
var left_hand_mesh_node: MeshInstance2D
var right_hand_mesh_node: MeshInstance2D
var left_hand_shadow_node: MeshInstance2D
var right_hand_shadow_node: MeshInstance2D
var left_hand_mat: ShaderMaterial
var right_hand_mat: ShaderMaterial
var left_hand_shadow_mat: ShaderMaterial
var right_hand_shadow_mat: ShaderMaterial

var key_glow_layer: Node2D
var gaussian_tex: ImageTexture
var beam_tex: ImageTexture

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

# Cached analytic light falloff: soft across the key, fading toward its foot.
static func _generate_beam_texture() -> ImageTexture:
	var img: Image = Image.create(64, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		var depth: float = float(y) / 127.0
		for x in range(64):
			var lateral: float = absf(float(x) / 63.0 * 2.0 - 1.0)
			var alpha: float = exp(-lateral * lateral * 5.0) * (1.0 - smoothstep(0.0, 1.0, lateral)) * pow(1.0 - depth, 1.5)
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
	elapsed_hands += delta
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
				
	if anime_hands_enabled:
		_update_hand_targets()
		_update_finger_targets()
		var weight: float = clampf(delta * 12.0, 0.0, 1.0)
		left_hand_x = lerpf(left_hand_x, left_hand_target_x, weight)
		right_hand_x = lerpf(right_hand_x, right_hand_target_x, weight)
		left_hand_rot = lerpf(left_hand_rot, clampf((left_hand_target_x - left_hand_x) * 0.002, -0.06, 0.06), minf(delta * 8.0, 1.0))
		right_hand_rot = lerpf(right_hand_rot, clampf((right_hand_target_x - right_hand_x) * 0.002, -0.06, 0.06), minf(delta * 8.0, 1.0))
		left_hand_dip = move_toward(left_hand_dip, 0.0, delta * 24.0)
		right_hand_dip = move_toward(right_hand_dip, 0.0, delta * 24.0)
		
		for i in range(5):
			if is_zero_approx(delta):
				left_finger_dips[i] = left_finger_targets[i]
				right_finger_dips[i] = right_finger_targets[i]
			else:
				var l_spd: float = 34.0 if left_finger_targets[i] > 0.5 else 18.0
				left_finger_dips[i] = move_toward(left_finger_dips[i], left_finger_targets[i], delta * l_spd)
				var r_spd: float = 34.0 if right_finger_targets[i] > 0.5 else 18.0
				right_finger_dips[i] = move_toward(right_finger_dips[i], right_finger_targets[i], delta * r_spd)
		
		_sync_hand_mesh_transforms()
		_update_3d_hands_transforms()
		queue_redraw()
	if changed:
		_request_render()

static func _create_hand_mesh(cols: int = 24, rows: int = 20) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts = PackedVector2Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	for r in range(rows + 1):
		var v = float(r) / float(rows)
		for c in range(cols + 1):
			var u = float(c) / float(cols)
			verts.append(Vector2(u - 0.5, v - 0.72))
			uvs.append(Vector2(u, v))
	for r in range(rows):
		for c in range(cols):
			var p0 = r * (cols + 1) + c
			var p1 = p0 + 1
			var p2 = (r + 1) * (cols + 1) + c
			var p3 = p2 + 1
			indices.append(p0)
			indices.append(p1)
			indices.append(p2)
			indices.append(p1)
			indices.append(p3)
			indices.append(p2)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _setup_anime_hand_nodes() -> void:
	if hand_grid_mesh == null:
		hand_grid_mesh = _create_hand_mesh(24, 20)
	
	if hand_shader == null:
		return
		
	left_hand_shadow_mat = ShaderMaterial.new()
	left_hand_shadow_mat.shader = hand_shader
	left_hand_shadow_mat.set_shader_parameter("u_is_shadow", true)
	left_hand_shadow_mat.set_shader_parameter("u_finger_centers_1_4", Vector4(LEFT_FINGER_UV_CENTERS[0], LEFT_FINGER_UV_CENTERS[1], LEFT_FINGER_UV_CENTERS[2], LEFT_FINGER_UV_CENTERS[3]))
	left_hand_shadow_mat.set_shader_parameter("u_finger_center_5", LEFT_FINGER_UV_CENTERS[4])
	
	left_hand_shadow_node = MeshInstance2D.new()
	left_hand_shadow_node.mesh = hand_grid_mesh
	left_hand_shadow_node.texture = hand_left_tex
	left_hand_shadow_node.material = left_hand_shadow_mat
	left_hand_shadow_node.z_index = 8
	add_child(left_hand_shadow_node)
	
	left_hand_mat = ShaderMaterial.new()
	left_hand_mat.shader = hand_shader
	left_hand_mat.set_shader_parameter("u_is_shadow", false)
	left_hand_mat.set_shader_parameter("u_finger_centers_1_4", Vector4(LEFT_FINGER_UV_CENTERS[0], LEFT_FINGER_UV_CENTERS[1], LEFT_FINGER_UV_CENTERS[2], LEFT_FINGER_UV_CENTERS[3]))
	left_hand_mat.set_shader_parameter("u_finger_center_5", LEFT_FINGER_UV_CENTERS[4])
	
	left_hand_mesh_node = MeshInstance2D.new()
	left_hand_mesh_node.mesh = hand_grid_mesh
	left_hand_mesh_node.texture = hand_left_tex
	left_hand_mesh_node.material = left_hand_mat
	left_hand_mesh_node.z_index = 9
	add_child(left_hand_mesh_node)
	
	right_hand_shadow_mat = ShaderMaterial.new()
	right_hand_shadow_mat.shader = hand_shader
	right_hand_shadow_mat.set_shader_parameter("u_is_shadow", true)
	right_hand_shadow_mat.set_shader_parameter("u_finger_centers_1_4", Vector4(RIGHT_FINGER_UV_CENTERS[0], RIGHT_FINGER_UV_CENTERS[1], RIGHT_FINGER_UV_CENTERS[2], RIGHT_FINGER_UV_CENTERS[3]))
	right_hand_shadow_mat.set_shader_parameter("u_finger_center_5", RIGHT_FINGER_UV_CENTERS[4])
	
	right_hand_shadow_node = MeshInstance2D.new()
	right_hand_shadow_node.mesh = hand_grid_mesh
	right_hand_shadow_node.texture = hand_right_tex
	right_hand_shadow_node.material = right_hand_shadow_mat
	right_hand_shadow_node.z_index = 8
	add_child(right_hand_shadow_node)
	
	right_hand_mat = ShaderMaterial.new()
	right_hand_mat.shader = hand_shader
	right_hand_mat.set_shader_parameter("u_is_shadow", false)
	right_hand_mat.set_shader_parameter("u_finger_centers_1_4", Vector4(RIGHT_FINGER_UV_CENTERS[0], RIGHT_FINGER_UV_CENTERS[1], RIGHT_FINGER_UV_CENTERS[2], RIGHT_FINGER_UV_CENTERS[3]))
	right_hand_mat.set_shader_parameter("u_finger_center_5", RIGHT_FINGER_UV_CENTERS[4])
	
	right_hand_mesh_node = MeshInstance2D.new()
	right_hand_mesh_node.mesh = hand_grid_mesh
	right_hand_mesh_node.texture = hand_right_tex
	right_hand_mesh_node.material = right_hand_mat
	right_hand_mesh_node.z_index = 9
	add_child(right_hand_mesh_node)
	
	_sync_hand_mesh_visibility()

func _sync_hand_mesh_visibility() -> void:
	var show_2d = anime_hands_enabled and (hands_mode == "2d")
	var show_3d = anime_hands_enabled and (hands_mode == "3d")
	
	if left_hand_mesh_node != null:
		left_hand_mesh_node.visible = show_2d
	if right_hand_mesh_node != null:
		right_hand_mesh_node.visible = show_2d
	if left_hand_shadow_node != null:
		left_hand_shadow_node.visible = show_2d
	if right_hand_shadow_node != null:
		right_hand_shadow_node.visible = show_2d
		
	if hands_3d_container != null:
		hands_3d_container.visible = show_3d

func _setup_3d_hands() -> void:
	if hand_3d_left_scene == null or hand_3d_right_scene == null:
		return
		
	hands_3d_container = SubViewportContainer.new()
	hands_3d_container.name = "Hands3DContainer"
	hands_3d_container.stretch = true
	hands_3d_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hands_3d_container.z_index = 10
	add_child(hands_3d_container)
	
	hands_3d_viewport = SubViewport.new()
	hands_3d_viewport.name = "Hands3DViewport"
	hands_3d_viewport.transparent_bg = true
	hands_3d_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	hands_3d_container.add_child(hands_3d_viewport)
	
	var world = World3D.new()
	hands_3d_viewport.world_3d = world
	
	hands_3d_camera = Camera3D.new()
	hands_3d_camera.name = "Hands3DCamera"
	hands_3d_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	hands_3d_camera.size = hands_3d_cam_size
	hands_3d_camera.position = Vector3(0.0, 0.50, 0.08)
	hands_3d_camera.rotation_degrees = Vector3(-70.0, 0.0, 0.0)
	hands_3d_viewport.add_child(hands_3d_camera)
	
	var main_light = DirectionalLight3D.new()
	main_light.name = "StudioMainLight"
	main_light.light_energy = 3.8
	main_light.light_color = Color(1.0, 0.98, 0.95)
	main_light.rotation_degrees = Vector3(-60.0, 15.0, 0.0)
	hands_3d_viewport.add_child(main_light)
	
	var fill_light = DirectionalLight3D.new()
	fill_light.name = "StudioFillLight"
	fill_light.light_energy = 1.4
	fill_light.light_color = Color(0.85, 0.90, 1.0)
	fill_light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	hands_3d_viewport.add_child(fill_light)
	
	left_hand_3d = hand_3d_left_scene.instantiate() as Node3D
	left_hand_3d.name = "LeftHand3D"
	hands_3d_viewport.add_child(left_hand_3d)
	left_hand_skel = left_hand_3d.find_child("Skeleton3D", true, false) as Skeleton3D
	
	right_hand_3d = hand_3d_right_scene.instantiate() as Node3D
	right_hand_3d.name = "RightHand3D"
	hands_3d_viewport.add_child(right_hand_3d)
	right_hand_skel = right_hand_3d.find_child("Skeleton3D", true, false) as Skeleton3D
	
	var map_bones = func(skel: Skeleton3D, prefixes: Array) -> Array:
		var res = []
		if skel == null:
			return res
		for p in prefixes:
			var arr = []
			if p == "thumb":
				arr.append(skel.find_bone("thumb-phalanx-proximal"))
				arr.append(skel.find_bone("thumb-phalanx-distal"))
			else:
				arr.append(skel.find_bone(p + "-finger-phalanx-proximal"))
				arr.append(skel.find_bone(p + "-finger-phalanx-intermediate"))
				arr.append(skel.find_bone(p + "-finger-phalanx-distal"))
			res.append(arr)
		return res
		
	left_finger_bones = map_bones.call(left_hand_skel, ["pinky", "ring", "middle", "index", "thumb"])
	right_finger_bones = map_bones.call(right_hand_skel, ["thumb", "index", "middle", "ring", "pinky"])
	
	_sync_hand_mesh_visibility()

func _sync_hand_mesh_transforms() -> void:
	if left_hand_mesh_node == null or right_hand_mesh_node == null:
		return
	var is_visible: bool = anime_hands_enabled
	_sync_hand_mesh_visibility()
	if not is_visible:
		return
	
	var idle_y: float = sin(elapsed_hands * 2.2) * 1.5 if (active.is_empty() and left_hand_dip <= 0.1 and right_hand_dip <= 0.1) else 0.0
	var pivot_y: float = size.y * 0.15 + hand_size.y * 0.72 + idle_y
	
	var l_pos = Vector2(left_hand_x, pivot_y + left_hand_dip)
	left_hand_mesh_node.position = l_pos
	left_hand_mesh_node.rotation = left_hand_rot
	left_hand_mesh_node.scale = hand_size
	if left_hand_shadow_node != null:
		left_hand_shadow_node.position = l_pos + Vector2(2.0, 3.0)
		left_hand_shadow_node.rotation = left_hand_rot
		left_hand_shadow_node.scale = hand_size
	
	left_hand_mat.set_shader_parameter("u_finger_dips_1_4", Vector4(left_finger_dips[0], left_finger_dips[1], left_finger_dips[2], left_finger_dips[3]))
	left_hand_mat.set_shader_parameter("u_finger_dip_5", left_finger_dips[4])
	left_hand_mat.set_shader_parameter("u_time", elapsed_hands)
	if left_hand_shadow_mat != null:
		left_hand_shadow_mat.set_shader_parameter("u_finger_dips_1_4", Vector4(left_finger_dips[0], left_finger_dips[1], left_finger_dips[2], left_finger_dips[3]))
		left_hand_shadow_mat.set_shader_parameter("u_finger_dip_5", left_finger_dips[4])
		left_hand_shadow_mat.set_shader_parameter("u_time", elapsed_hands)
	
	var r_pos = Vector2(right_hand_x, pivot_y + right_hand_dip)
	right_hand_mesh_node.position = r_pos
	right_hand_mesh_node.rotation = right_hand_rot
	right_hand_mesh_node.scale = hand_size
	if right_hand_shadow_node != null:
		right_hand_shadow_node.position = r_pos + Vector2(2.0, 3.0)
		right_hand_shadow_node.rotation = right_hand_rot
		right_hand_shadow_node.scale = hand_size
		
	right_hand_mat.set_shader_parameter("u_finger_dips_1_4", Vector4(right_finger_dips[0], right_finger_dips[1], right_finger_dips[2], right_finger_dips[3]))
	right_hand_mat.set_shader_parameter("u_finger_dip_5", right_finger_dips[4])
	right_hand_mat.set_shader_parameter("u_time", elapsed_hands)
	if right_hand_shadow_mat != null:
		right_hand_shadow_mat.set_shader_parameter("u_finger_dips_1_4", Vector4(right_finger_dips[0], right_finger_dips[1], right_finger_dips[2], right_finger_dips[3]))
		right_hand_shadow_mat.set_shader_parameter("u_finger_dip_5", right_finger_dips[4])
		right_hand_shadow_mat.set_shader_parameter("u_time", elapsed_hands)

func _update_3d_hands_transforms() -> void:
	if hands_3d_container == null or not hands_3d_container.visible:
		return
	if left_hand_3d == null or right_hand_3d == null or hand_width <= 0.0 or size.y <= 0.0:
		return
		
	var scale_factor: float = hands_3d_cam_size / size.y
	var center_x: float = size.x * 0.5
	
	var idle_dip: float = sin(elapsed_hands * 2.2) * 0.002 if (active.is_empty() and left_hand_dip <= 0.1 and right_hand_dip <= 0.1) else 0.0
	
	var l_world_x = (left_hand_x - center_x) * scale_factor
	var l_world_y = -left_hand_dip * 0.003 + idle_dip
	left_hand_3d.position = Vector3(l_world_x, l_world_y, 0.0)
	left_hand_3d.rotation = Vector3(0.0, 0.0, -left_hand_rot * 1.5)
	
	var r_world_x = (right_hand_x - center_x) * scale_factor
	var r_world_y = -right_hand_dip * 0.003 + idle_dip
	right_hand_3d.position = Vector3(r_world_x, r_world_y, 0.0)
	right_hand_3d.rotation = Vector3(0.0, 0.0, -right_hand_rot * 1.5)
	
	if left_hand_skel != null:
		for f in range(left_finger_bones.size()):
			var dip: float = left_finger_dips[f]
			var bones: Array = left_finger_bones[f]
			if bones.size() == 2:
				var r0 = lerpf(deg_to_rad(-6.0), deg_to_rad(-24.0), dip)
				var r1 = lerpf(deg_to_rad(-8.0), deg_to_rad(-32.0), dip)
				if bones[0] >= 0: left_hand_skel.set_bone_pose_rotation(bones[0], Quaternion(Vector3.RIGHT, r0))
				if bones[1] >= 0: left_hand_skel.set_bone_pose_rotation(bones[1], Quaternion(Vector3.RIGHT, r1))
			elif bones.size() == 3:
				var r0 = lerpf(deg_to_rad(-8.0), deg_to_rad(-30.0), dip)
				var r1 = lerpf(deg_to_rad(-12.0), deg_to_rad(-45.0), dip)
				var r2 = lerpf(deg_to_rad(-6.0), deg_to_rad(-24.0), dip)
				if bones[0] >= 0: left_hand_skel.set_bone_pose_rotation(bones[0], Quaternion(Vector3.RIGHT, r0))
				if bones[1] >= 0: left_hand_skel.set_bone_pose_rotation(bones[1], Quaternion(Vector3.RIGHT, r1))
				if bones[2] >= 0: left_hand_skel.set_bone_pose_rotation(bones[2], Quaternion(Vector3.RIGHT, r2))

	if right_hand_skel != null:
		for f in range(right_finger_bones.size()):
			var dip: float = right_finger_dips[f]
			var bones: Array = right_finger_bones[f]
			if bones.size() == 2:
				var r0 = lerpf(deg_to_rad(-6.0), deg_to_rad(-24.0), dip)
				var r1 = lerpf(deg_to_rad(-8.0), deg_to_rad(-32.0), dip)
				if bones[0] >= 0: right_hand_skel.set_bone_pose_rotation(bones[0], Quaternion(Vector3.RIGHT, r0))
				if bones[1] >= 0: right_hand_skel.set_bone_pose_rotation(bones[1], Quaternion(Vector3.RIGHT, r1))
			elif bones.size() == 3:
				var r0 = lerpf(deg_to_rad(-8.0), deg_to_rad(-30.0), dip)
				var r1 = lerpf(deg_to_rad(-12.0), deg_to_rad(-45.0), dip)
				var r2 = lerpf(deg_to_rad(-6.0), deg_to_rad(-24.0), dip)
				if bones[0] >= 0: right_hand_skel.set_bone_pose_rotation(bones[0], Quaternion(Vector3.RIGHT, r0))
				if bones[1] >= 0: right_hand_skel.set_bone_pose_rotation(bones[1], Quaternion(Vector3.RIGHT, r1))
				if bones[2] >= 0: right_hand_skel.set_bone_pose_rotation(bones[2], Quaternion(Vector3.RIGHT, r2))

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gaussian_tex = _generate_gaussian_texture(128)
	beam_tex = _generate_beam_texture()
	
	key_glow_layer = Node2D.new()
	var add_mat = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	key_glow_layer.material = add_mat
	key_glow_layer.draw.connect(_draw_key_glows)
	add_child(key_glow_layer)
	
	_setup_anime_hand_nodes()
	_setup_3d_hands()
	
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
	var white_key_width: float = 0.0
	var white_k_count: int = 0
	for m: int in key_rects:
		if not Keymap.is_black(m):
			white_key_width += key_rects[m].size.x
			white_k_count += 1
	if white_k_count > 0 and hand_left_tex != null:
		hand_width = white_key_width / float(white_k_count) * 4.5
		hand_size = Vector2(hand_width, hand_width * float(hand_left_tex.get_height()) / float(hand_left_tex.get_width()))
	if hands_3d_container != null and size.x > 0.0 and size.y > 0.0:
		hands_3d_container.size = size
		if hands_3d_camera != null and hand_width > 0.0:
			hands_3d_cam_size = 0.15 * size.y / hand_width
			hands_3d_camera.size = hands_3d_cam_size
	_update_hand_targets()
	left_hand_x = left_hand_target_x
	right_hand_x = right_hand_target_x
	_sync_hand_mesh_transforms()
	_update_3d_hands_transforms()
	_request_render()

func _find_closest_finger(rel_u: float, is_left: bool) -> int:
	var centers = LEFT_FINGER_UV_CENTERS if is_left else RIGHT_FINGER_UV_CENTERS
	var closest_idx: int = 0
	var min_dist: float = 999.0
	for i in range(5):
		var d = absf(rel_u - centers[i])
		if d < min_dist:
			min_dist = d
			closest_idx = i
	return closest_idx

func _update_finger_targets() -> void:
	for i in range(5):
		left_finger_targets[i] = 0.0
		right_finger_targets[i] = 0.0
	if hand_width <= 0.0:
		return
	for midi in active:
		if not key_rects.has(midi):
			continue
		var key_center: float = key_rects[midi].get_center().x
		if midi < 60:
			var rel_u: float = clampf((key_center - (left_hand_x - hand_width * 0.5)) / hand_width, 0.0, 1.0)
			left_finger_targets[_find_closest_finger(rel_u, true)] = 1.0
		else:
			var rel_u: float = clampf((key_center - (right_hand_x - hand_width * 0.5)) / hand_width, 0.0, 1.0)
			right_finger_targets[_find_closest_finger(rel_u, false)] = 1.0

func _hand_centroid(left: bool, rest_midi: int) -> float:
	var total: float = 0.0
	var count: int = 0
	for midi: int in active:
		if (midi < 60) == left and key_rects.has(midi):
			var rect: Rect2 = key_rects[midi]
			total += rect.get_center().x
			count += 1
	if count > 0:
		return total / float(count)
	var anticipation: float = hand_anticipation_left_x if left else hand_anticipation_right_x
	if anticipation > 0.0:
		return anticipation
	var rest: int = clampi(rest_midi, visible_midi_range.x, visible_midi_range.y)
	var rest_rect: Rect2 = key_rects.get(rest, Rect2())
	return rest_rect.get_center().x

func set_hand_anticipation(left_x: float, right_x: float) -> void:
	hand_anticipation_left_x = left_x
	hand_anticipation_right_x = right_x

func _update_hand_targets() -> void:
	left_hand_target_x = _hand_centroid(true, 48)
	right_hand_target_x = _hand_centroid(false, 72)

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
	if anime_hands_enabled:
		if midi < 60:
			left_hand_dip = 4.5
			if key_rects.has(midi) and hand_width > 0.0:
				var key_center: float = key_rects[midi].get_center().x
				var rel_u: float = clampf((key_center - (left_hand_x - hand_width * 0.5)) / hand_width, 0.0, 1.0)
				var f_idx: int = _find_closest_finger(rel_u, true)
				left_finger_dips[f_idx] = 1.0
				left_finger_targets[f_idx] = 1.0
		else:
			right_hand_dip = 4.5
			if key_rects.has(midi) and hand_width > 0.0:
				var key_center: float = key_rects[midi].get_center().x
				var rel_u: float = clampf((key_center - (right_hand_x - hand_width * 0.5)) / hand_width, 0.0, 1.0)
				var f_idx: int = _find_closest_finger(rel_u, false)
				right_finger_dips[f_idx] = 1.0
				right_finger_targets[f_idx] = 1.0
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

	_sync_hand_mesh_transforms()

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
		
		if beam_tex != null:
			var beam_color: Color = tint
			beam_color.a = 0.65 * light * k_scale
			key_glow_layer.draw_texture_rect(beam_tex, rect, false, beam_color)
			var core_rect: Rect2 = Rect2(center_x - rect.size.x * 0.12, top_y, rect.size.x * 0.24, rect.size.y)
			var core_color: Color = tint.lerp(Color.WHITE, 0.55)
			core_color.a = 0.30 * light * k_scale
			key_glow_layer.draw_texture_rect(beam_tex, core_rect, false, core_color)

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
