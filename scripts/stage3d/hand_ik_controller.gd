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

const FINGER_NAMES: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]
const ATTACK_SPEED: float = 34.0
const ANTICIPATION_SPEED: float = 16.0
const RELEASE_SPEED: float = 11.0
const WRIST_SPEED: float = 18.0

var side: int = 0
var hand_root: Node3D
var markers: Array[Marker3D] = []
var _skeleton: Skeleton3D
var _chains: Array[FingerChain] = []

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
	for finger: int in range(FINGER_NAMES.size()):
		var chain: FingerChain = FingerChain.new()
		chain.finger_name = FINGER_NAMES[finger]
		chain.rest_angles = _finger_angles(finger, false, false)
		chain.angles = chain.rest_angles.duplicate()
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
	var target_y: float = lerpf(0.072, 0.078, ratio)
	if plan.active_count > 0 and ratio < 0.5:
		target_y -= 0.004
	if plan.active_count == 0:
		target_y += sin(elapsed_time * 2.1 + float(side) * 1.3) * 0.0012
	var target_x: float = plan.wrist_target_x
	var target: Vector3 = Vector3(target_x, target_y, lerpf(0.192, 0.152, ratio))
	var x_speed: float = ATTACK_SPEED if absf(target_x - hand_root.position.x) > 0.10 else WRIST_SPEED
	var next_x: float = lerpf(hand_root.position.x, target_x, 1.0 - exp(-x_speed * step))
	hand_root.position = hand_root.position.lerp(target, wrist_damping)
	hand_root.position.x = next_x
	var center_x: float = 0.0
	var assigned_count: int = 0
	for assignment: FingeringSolver.FingerAssignment in plan.fingers:
		if assignment.state != FingeringSolver.FingerState.IDLE:
			center_x += assignment.target_pos.x
			assigned_count += 1
	var reach_offset: float = center_x / float(assigned_count) - hand_root.position.x if assigned_count > 0 else 0.0
	var roll: float = clampf(-reach_offset * 0.55 - (target_x - hand_root.position.x) * 0.35, -0.075, 0.075)
	hand_root.rotation.x = lerpf(hand_root.rotation.x, PI * 0.5 + deg_to_rad(-2.5 * float(plan.active_count > 0) + 2.0 * ratio), wrist_damping)
	hand_root.rotation.z = lerpf(hand_root.rotation.z, roll, wrist_damping)
	for finger: int in range(_chains.size()):
		var chain: FingerChain = _chains[finger]
		var assignment: FingeringSolver.FingerAssignment = plan.fingers[finger]
		var striking: bool = assignment.state == FingeringSolver.FingerState.STRIKING
		var anticipating: bool = assignment.state == FingeringSolver.FingerState.ANTICIPATING
		var rate: float = ATTACK_SPEED if striking else (ANTICIPATION_SPEED if anticipating else RELEASE_SPEED)
		var damping: float = 1.0 - exp(-rate * step)
		var marker_target: Vector3 = assignment.target_pos if striking or anticipating else _idle_target(chain)
		markers[finger].global_position = markers[finger].global_position.lerp(_stage_to_world(marker_target), damping)
		var black: bool = key_map.is_black_key(assignment.midi) if striking else false
		var targets: PackedFloat32Array = _finger_angles(finger, striking, black)
		if anticipating:
			targets[0] += 4.0
			targets[1] += 4.0
		elif not striking and _has_striking_neighbor(plan, finger):
			var sympathetic: PackedFloat32Array = _finger_angles(finger, true, false)
			for joint: int in range(targets.size()):
				targets[joint] = lerpf(targets[joint], sympathetic[joint], 0.15)
		for joint: int in range(chain.angles.size()):
			chain.angles[joint] = lerpf(chain.angles[joint], targets[joint], damping)
		var marker_stage: Vector3 = _world_to_stage(markers[finger].global_position)
		var target_splay: float = clampf((marker_stage.x - hand_root.position.x - chain.rest_tip.x) * 4.5, -0.25, 0.25)
		chain.splay = lerpf(chain.splay, target_splay, damping)
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
	return hand_root.position + Vector3(chain.rest_tip.x, -0.050, -0.150)

func _finger_angles(finger: int, striking: bool, black: bool) -> PackedFloat32Array:
	if finger == 0:
		return PackedFloat32Array(([4, 2, 0] if black else [-2, -4, -6]) if striking else [8, 6, 4])
	if striking and black:
		return PackedFloat32Array([-2, -8, -10, -6])
	if finger == 4:
		return PackedFloat32Array([-6, -20, -18, -12] if striking else [-3, -12, -14, -10])
	return PackedFloat32Array([-6, -22, -22, -14] if striking else [-3, -14, -18, -12])

func _apply_finger_fk(chain: FingerChain) -> void:
	if _skeleton == null:
		return
	var cumulative: Basis = Basis.IDENTITY
	var position: Vector3 = Vector3.ZERO
	var previous_rest: Vector3 = Vector3.ZERO
	var axis: Vector3 = Vector3(1.0, 0.35 if side == 0 else -0.35, 0.0).normalized() if chain.finger_name == "thumb" else Vector3.RIGHT
	for joint: int in range(chain.bones.size()):
		var rest: Transform3D = chain.rests[joint]
		position = rest.origin if joint == 0 else position + cumulative * (rest.origin - previous_rest)
		var delta_basis: Basis = Basis.IDENTITY
		if joint < chain.angles.size():
			delta_basis = Basis(axis, deg_to_rad(chain.angles[joint]))
		if joint == 1:
			delta_basis = Basis(Vector3.BACK, chain.splay) * delta_basis
		cumulative = cumulative * delta_basis
		_skeleton.set_bone_pose_position(chain.bones[joint], position)
		_skeleton.set_bone_pose_rotation(chain.bones[joint], (cumulative * rest.basis).get_rotation_quaternion())
		previous_rest = rest.origin
