class_name HandIKController
extends RefCounted
## Smooth marker targets and synthesize chains for the GLB's sibling bones.

class FingerChain extends RefCounted:
	var finger_name: String
	var bones: PackedInt32Array = PackedInt32Array()
	var rests: Array[Transform3D] = []
	var segment_lengths: PackedFloat32Array = PackedFloat32Array()
	var rest_angles: PackedFloat32Array = PackedFloat32Array()
	var angles: PackedFloat32Array = PackedFloat32Array()
	var rest_tip: Vector3 = Vector3.ZERO
	var splay: float = 0.0
	var last_midi: int = -1
	var last_state: int = 0
	var strike_impulse: float = 0.0
	var release_rebound: float = 0.0
	var black_blend: float = 0.0
	var root_offset: Vector3 = Vector3.ZERO

const FINGER_NAMES: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]
const REST_SPLAY_LEFT: Array[float] = [-0.34, -0.018, 0.0, 0.018, 0.040]
const REST_SPLAY_RIGHT: Array[float] = [0.34, 0.018, 0.0, -0.018, -0.040]
const ATTACK_SPEED: float = 38.0
const ANTICIPATION_SPEED: float = 16.0
const RELEASE_SPEED: float = 11.0
const WRIST_SPEED: float = 22.0

var side: int = 0
var hand_root: Node3D
var markers: Array[Marker3D] = []
var _skeleton: Skeleton3D
var _chains: Array[FingerChain] = []
var _wrist_velocity_x: float = 0.0

func _init(hand_side: int, hand_node: Node3D, skel: Skeleton3D, marker_parent: Node3D) -> void:
	setup(hand_side, hand_node, skel, marker_parent)

func setup(hand_side: int, hand_node: Node3D, skel: Skeleton3D, marker_parent: Node3D) -> void:
	for marker: Marker3D in markers:
		if is_instance_valid(marker):
			marker.queue_free()
	markers.clear()
	_chains.clear()
	side = hand_side
	hand_root = hand_node
	_skeleton = skel
	var rest_splays: Array[float] = REST_SPLAY_LEFT if side == 0 else REST_SPLAY_RIGHT
	for finger: int in range(FINGER_NAMES.size()):
		var chain: FingerChain = FingerChain.new()
		chain.finger_name = FINGER_NAMES[finger]
		chain.rest_angles = _finger_angles(finger, false, false)
		chain.angles = chain.rest_angles.duplicate()
		chain.splay = rest_splays[finger]
		var prefix: String = "thumb-" if finger == 0 else chain.finger_name + "-finger-"
		var segments: PackedStringArray = PackedStringArray(["metacarpal", "phalanx-proximal", "phalanx-distal", "tip"] if finger == 0 else ["metacarpal", "phalanx-proximal", "phalanx-intermediate", "phalanx-distal", "tip"])
		if _skeleton != null:
			for segment: String in segments:
				var bone: int = _skeleton.find_bone(prefix + segment)
				if bone < 0:
					continue
				var rest: Transform3D = _skeleton.get_bone_rest(bone)
				if not chain.rests.is_empty():
					chain.segment_lengths.append(rest.origin.distance_to(chain.rests.back().origin))
				chain.bones.append(bone)
				chain.rests.append(rest)
			if not chain.rests.is_empty():
				chain.rest_tip = chain.rests.back().origin
		_chains.append(chain)
		var marker: Marker3D = Marker3D.new()
		marker.name = ("LeftFingerMarker%d" if side == 0 else "RightFingerMarker%d") % finger
		marker_parent.add_child(marker)
		marker.global_position = _stage_to_world(_idle_target(chain))
		markers.append(marker)
		_apply_finger_fk(chain)

func update_hand(plan: FingeringSolver.HandPlan, key_map: KeyMap3D, delta: float, elapsed_time: float) -> void:
	var step: float = maxf(delta, 0.0)
	var wrist_damping: float = 1.0 - exp(-WRIST_SPEED * step)
	var ratio: float = clampf(plan.black_ratio, 0.0, 1.0)
	var target_y: float = lerpf(0.078, 0.086, ratio)
	if plan.active_count > 0 and ratio < 0.5:
		target_y = 0.072
	if plan.active_count == 0:
		target_y += sin(elapsed_time * 2.1 + float(side) * 1.3) * 0.0012
	var target_x: float = plan.wrist_target_x
	var prev_x: float = hand_root.position.x
	var x_speed: float = lerpf(WRIST_SPEED, ATTACK_SPEED, clampf(absf(target_x - prev_x) / 0.14, 0.0, 1.0))
	var raw_next_x: float = lerpf(prev_x, target_x, 1.0 - exp(-x_speed * step))
	var max_step: float = maxf(0.038, 1.8 * step)
	var next_x: float = prev_x + clampf(raw_next_x - prev_x, -max_step, max_step)
	var target_z: float = lerpf(0.172, 0.136, ratio)
	var thumb_assignment: FingeringSolver.FingerAssignment = plan.fingers[0] if not plan.fingers.is_empty() else null
	if thumb_assignment != null:
		if thumb_assignment.state == FingeringSolver.FingerState.STRIKING:
			target_z = minf(target_z, 0.124 if thumb_assignment.is_black else 0.156)
		elif thumb_assignment.state == FingeringSolver.FingerState.ANTICIPATING:
			var thumb_ant_z: float = 0.132 if thumb_assignment.is_black else 0.160
			target_z = lerpf(target_z, minf(target_z, thumb_ant_z), thumb_assignment.weight)
	var target: Vector3 = Vector3(next_x, target_y, target_z)
	hand_root.position = hand_root.position.lerp(target, wrist_damping)
	hand_root.position.x = next_x
	if step > 0.0001:
		var inst_vel: float = clampf((next_x - prev_x) / maxf(step, 0.001), -2.5, 2.5)
		_wrist_velocity_x = lerpf(_wrist_velocity_x, inst_vel, wrist_damping)
	var center_x: float = 0.0
	var assigned_count: int = 0
	for assignment: FingeringSolver.FingerAssignment in plan.fingers:
		if assignment.state != FingeringSolver.FingerState.IDLE:
			center_x += assignment.target_pos.x
			assigned_count += 1
	var reach_offset: float = center_x / float(assigned_count) - hand_root.position.x if assigned_count > 0 else 0.0
	var target_roll: float = clampf(-reach_offset * 0.55 - clampf(_wrist_velocity_x * 0.055, -0.05, 0.05), -0.095, 0.095)
	var target_yaw: float = clampf(_wrist_velocity_x * 0.045 + reach_offset * 0.35, -0.085, 0.085)
	var target_pitch: float = PI * 0.5 + deg_to_rad(-3.8 * float(plan.active_count > 0 and ratio < 0.5) + 2.2 * ratio)
	hand_root.rotation.x = lerpf(hand_root.rotation.x, target_pitch, wrist_damping)
	hand_root.rotation.y = lerpf(hand_root.rotation.y, target_yaw, wrist_damping)
	hand_root.rotation.z = lerpf(hand_root.rotation.z, target_roll, wrist_damping)
	var rest_splays: Array[float] = REST_SPLAY_LEFT if side == 0 else REST_SPLAY_RIGHT
	var hand_inv: Transform3D = hand_root.transform.affine_inverse()
	for finger: int in range(_chains.size()):
		var chain: FingerChain = _chains[finger]
		var assignment: FingeringSolver.FingerAssignment = plan.fingers[finger]
		var striking: bool = assignment.state == FingeringSolver.FingerState.STRIKING
		var anticipating: bool = assignment.state == FingeringSolver.FingerState.ANTICIPATING
		if striking and (chain.last_state != FingeringSolver.FingerState.STRIKING or chain.last_midi != assignment.midi):
			chain.strike_impulse = 1.0
			chain.release_rebound = 0.0
		elif not striking and not anticipating and chain.last_state == FingeringSolver.FingerState.STRIKING:
			chain.release_rebound = 1.0
			chain.strike_impulse = 0.0
		chain.strike_impulse *= exp(-13.0 * step)
		chain.release_rebound *= exp(-11.0 * step)
		chain.last_state = assignment.state
		chain.last_midi = assignment.midi
		var rate: float = ATTACK_SPEED if striking else (ANTICIPATION_SPEED if anticipating else RELEASE_SPEED)
		var damping: float = 1.0 - exp(-rate * step)
		chain.black_blend = lerpf(chain.black_blend, 1.0 if ((striking or anticipating) and assignment.is_black) else 0.0, damping)
		var marker_target: Vector3 = assignment.target_pos if striking or anticipating else _idle_target(chain)
		markers[finger].global_position = markers[finger].global_position.lerp(_stage_to_world(marker_target), damping)
		var black: bool = key_map.is_black_key(assignment.midi) if striking else false
		var targets: PackedFloat32Array = _finger_angles(finger, striking, black)
		if striking:
			targets[0] -= 5.0 * chain.strike_impulse
			targets[1] -= 8.0 * chain.strike_impulse
			if targets.size() > 2:
				targets[2] -= 4.0 * chain.strike_impulse
		elif anticipating:
			targets[0] += 8.0 * assignment.weight
			targets[1] += 12.0 * assignment.weight
			if targets.size() > 2:
				targets[2] += 4.0 * assignment.weight
		elif chain.release_rebound > 0.01:
			targets[0] += 6.0 * chain.release_rebound
			targets[1] += 9.0 * chain.release_rebound
		elif _has_striking_neighbor(plan, finger):
			targets[1] += 3.0
		for joint: int in range(chain.angles.size()):
			chain.angles[joint] = lerpf(chain.angles[joint], targets[joint], damping)
		var target_splay: float = rest_splays[finger]
		if striking or anticipating:
			var marker_local: Vector3 = hand_inv * _world_to_stage(markers[finger].global_position)
			if finger == 0:
				var thumb_rest_x: float = 0.052 if side == 0 else -0.052
				target_splay = clampf(rest_splays[0] + (marker_local.x - thumb_rest_x) * 6.5, -0.62, 0.62)
			else:
				target_splay = clampf((marker_local.x - chain.rest_tip.x) * 5.2, -0.32, 0.32)
		chain.splay = lerpf(chain.splay, target_splay, damping)
		var target_root_offset: Vector3 = Vector3.ZERO
		if striking or anticipating:
			var desired_stage: Vector3 = assignment.target_pos if striking else _world_to_stage(markers[finger].global_position)
			var desired_local: Vector3 = hand_inv * desired_stage
			var unoffset_tip: Vector3 = _unoffset_tip_local(chain, chain.angles, chain.splay)
			var delta_local: Vector3 = desired_local - unoffset_tip
			if finger == 0:
				target_root_offset = Vector3(
					clampf(delta_local.x, -0.032, 0.032),
					clampf(delta_local.y, -0.045, 0.020),
					clampf(delta_local.z, -0.025, 0.028)
				)
			else:
				target_root_offset = Vector3(
					clampf(delta_local.x, -0.018, 0.018),
					clampf(delta_local.y, -0.028, 0.014),
					clampf(delta_local.z, -0.016, 0.018)
				)
		else:
			target_root_offset = Vector3(0.0, -0.003 * chain.release_rebound, -0.0045 * chain.release_rebound)
		chain.root_offset = chain.root_offset.lerp(target_root_offset, damping)
		_apply_finger_fk(chain)

func _has_striking_neighbor(plan: FingeringSolver.HandPlan, finger: int) -> bool:
	for neighbor: int in [finger - 1, finger + 1]:
		if neighbor >= 0 and neighbor < plan.fingers.size() and plan.fingers[neighbor].state == FingeringSolver.FingerState.STRIKING:
			return true
	return false

func _stage_to_world(point: Vector3) -> Vector3:
	var stage: Node3D = hand_root.get_parent() as Node3D
	return stage.to_global(point) if stage != null else point

func _world_to_stage(point: Vector3) -> Vector3:
	var stage: Node3D = hand_root.get_parent() as Node3D
	return stage.to_local(point) if stage != null else point

func _idle_target(chain: FingerChain) -> Vector3:
	if chain.finger_name == "thumb":
		return hand_root.position + Vector3(0.052 if side == 0 else -0.052, -0.042, -0.106)
	return hand_root.position + Vector3(chain.rest_tip.x, -0.044, -0.140)

func _finger_angles(finger: int, striking: bool, black: bool) -> PackedFloat32Array:
	match finger:
		0:
			return PackedFloat32Array(([2.0, -5.0, -7.0] if black else [-4.0, -10.0, -12.0]) if striking else [8.0, 4.0, 2.0])
		1:
			return PackedFloat32Array(([1.0, -19.0, -21.0, -14.0] if black else [-4.0, -27.0, -25.0, -16.0]) if striking else [5.0, -14.0, -18.0, -12.0])
		2:
			return PackedFloat32Array(([1.0, -20.0, -22.0, -14.0] if black else [-4.0, -28.0, -26.0, -17.0]) if striking else [5.0, -15.0, -20.0, -13.0])
		3:
			return PackedFloat32Array(([1.0, -19.0, -21.0, -14.0] if black else [-4.0, -27.0, -25.0, -16.0]) if striking else [5.0, -15.0, -19.0, -12.0])
		_:
			return PackedFloat32Array(([2.0, -17.0, -19.0, -12.0] if black else [-3.0, -25.0, -23.0, -15.0]) if striking else [6.0, -13.0, -17.0, -11.0])

func _thumb_axis() -> Vector3:
	return Vector3(1.0, 0.35 if side == 0 else -0.35, 0.0).normalized()

func _joint_delta_basis(chain: FingerChain, joint: int, eval_angles: PackedFloat32Array, eval_splay: float, axis: Vector3) -> Basis:
	var delta_basis: Basis = Basis.IDENTITY
	if joint < eval_angles.size():
		delta_basis = Basis(axis, deg_to_rad(eval_angles[joint]))
	if chain.finger_name == "thumb":
		if joint == 0:
			delta_basis = Basis(Vector3.BACK, eval_splay * 0.65) * delta_basis
		elif joint == 1:
			delta_basis = Basis(Vector3.BACK, eval_splay * 0.35) * delta_basis
	elif joint == 1:
		delta_basis = Basis(Vector3.BACK, eval_splay) * delta_basis
	return delta_basis

func _unoffset_tip_local(chain: FingerChain, eval_angles: PackedFloat32Array, eval_splay: float) -> Vector3:
	if chain.rests.is_empty():
		return Vector3.ZERO
	var cumulative: Basis = Basis.IDENTITY
	var position: Vector3 = Vector3.ZERO
	var previous_rest: Vector3 = Vector3.ZERO
	var axis: Vector3 = _thumb_axis() if chain.finger_name == "thumb" else Vector3.RIGHT
	for joint: int in range(chain.rests.size()):
		var rest: Transform3D = chain.rests[joint]
		position = rest.origin if joint == 0 else position + cumulative * (rest.origin - previous_rest)
		cumulative = cumulative * _joint_delta_basis(chain, joint, eval_angles, eval_splay, axis)
		previous_rest = rest.origin
	return position

func _apply_finger_fk(chain: FingerChain) -> void:
	if _skeleton == null:
		return
	var cumulative: Basis = Basis.IDENTITY
	var position: Vector3 = Vector3.ZERO
	var previous_rest: Vector3 = Vector3.ZERO
	var axis: Vector3 = _thumb_axis() if chain.finger_name == "thumb" else Vector3.RIGHT
	for joint: int in range(chain.bones.size()):
		var rest: Transform3D = chain.rests[joint]
		position = rest.origin + chain.root_offset if joint == 0 else position + cumulative * (rest.origin - previous_rest)
		cumulative = cumulative * _joint_delta_basis(chain, joint, chain.angles, chain.splay, axis)
		_skeleton.set_bone_pose_position(chain.bones[joint], position)
		_skeleton.set_bone_pose_rotation(chain.bones[joint], (cumulative * rest.basis).get_rotation_quaternion())
		previous_rest = rest.origin
