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
	var rest_posed_tip_x: float = 0.0
	var splay: float = 0.0
	var last_midi: int = -1
	var last_state: int = 0
	var last_strike_serial: int = -1
	var strike_impulse: float = 0.0
	var release_rebound: float = 0.0
	var black_blend: float = 0.0
	var root_offset: Vector3 = Vector3.ZERO
	var strike_flex_deg: float = 0.0
	var collision_lift_deg: float = 0.0

const FINGER_NAMES: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]
const MIN_SCALE_X: float = 0.98
const BASE_SCALE_X: float = 1.06
const MAX_SCALE_X: float = 1.26
const REST_SPLAY_LEFT: Array[float] = [-0.46, -0.015, 0.0, 0.020, 0.045]
const REST_SPLAY_RIGHT: Array[float] = [0.46, 0.015, 0.0, -0.020, -0.045]
const SPLAY_MIN_RIGHT: Array[float] = [-0.14, -0.24, -0.14, -0.11, -0.14]
const SPLAY_MAX_RIGHT: Array[float] = [0.56, 0.10, 0.14, 0.16, 0.26]
const MIN_TIP_GAP: Array[float] = [0.020, 0.016, 0.016, 0.015]
const ATTACK_SPEED: float = 38.0
const ANTICIPATION_SPEED: float = 16.0
const RELEASE_SPEED: float = 11.0
const WRIST_SPEED: float = 22.0
const WHITE_REST_Y: float = 0.090
const WHITE_ACTIVE_Y: float = 0.079
const BLACK_REST_Y: float = 0.094
const WHITE_REST_Z: float = 0.188
const BLACK_REST_Z: float = 0.146

var side: int = 0
var hand_root: Node3D
var markers: Array[Marker3D] = []
var _skeleton: Skeleton3D
var _chains: Array[FingerChain] = []
var _wrist_velocity_x: float = 0.0
var _hold_black_ratio: float = 0.0
var _hold_z: float = WHITE_REST_Z
var _wrist_base_y: float = WHITE_REST_Y
var _wrist_collision_y: float = 0.0
var _hand_scale_x: float = BASE_SCALE_X

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
	_hold_black_ratio = 0.0
	_hold_z = WHITE_REST_Z
	_wrist_base_y = hand_root.position.y if hand_root != null else WHITE_REST_Y
	_wrist_collision_y = 0.0
	_hand_scale_x = BASE_SCALE_X
	if hand_root != null:
		hand_root.scale = Vector3(BASE_SCALE_X, 1.0, 1.0)
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
				chain.rest_posed_tip_x = _unoffset_tip_local(chain, chain.rest_angles, chain.splay).x
		_chains.append(chain)
		var marker: Marker3D = Marker3D.new()
		marker.name = ("LeftFingerMarker%d" if side == 0 else "RightFingerMarker%d") % finger
		marker_parent.add_child(marker)
		marker.global_position = _stage_to_world(_idle_target(chain))
		markers.append(marker)
		_apply_finger_fk(chain)

func update_hand(plan: FingeringSolver.HandPlan, key_map: KeyMap3D, delta: float, elapsed_time: float, strike_serial: PackedInt32Array = PackedInt32Array(), key_depth: PackedFloat32Array = PackedFloat32Array()) -> void:
	var step: float = maxf(delta, 0.0)
	var wrist_damping: float = 1.0 - exp(-WRIST_SPEED * step)
	var max_imp: float = 0.0
	var max_reb: float = 0.0
	for finger: int in range(_chains.size()):
		var chain: FingerChain = _chains[finger]
		var assignment: FingeringSolver.FingerAssignment = plan.fingers[finger]
		var striking: bool = assignment.state == FingeringSolver.FingerState.STRIKING
		var curr_serial: int = strike_serial[assignment.midi - 21] if (striking and assignment.midi >= 21 and assignment.midi - 21 < strike_serial.size()) else -1
		if striking and (chain.last_state != FingeringSolver.FingerState.STRIKING or chain.last_midi != assignment.midi or (curr_serial >= 0 and curr_serial != chain.last_strike_serial)):
			chain.strike_impulse = 1.0
			chain.release_rebound = 0.0
		elif not striking and chain.last_state == FingeringSolver.FingerState.STRIKING:
			chain.release_rebound = 1.0
			chain.strike_impulse = 0.0
		chain.strike_impulse *= exp(-13.0 * step)
		chain.release_rebound *= exp(-11.0 * step)
		if striking:
			chain.last_strike_serial = curr_serial
		chain.last_state = assignment.state
		chain.last_midi = assignment.midi
		max_imp = maxf(max_imp, chain.strike_impulse)
		max_reb = maxf(max_reb, chain.release_rebound)
	var chord_span: float = plan.chord_span if plan.active_count >= 2 else 0.0
	var plan_ratio: float = clampf(plan.black_ratio, 0.0, 1.0)
	var plan_z: float = lerpf(WHITE_REST_Z, BLACK_REST_Z, plan_ratio)
	var thumb_assignment: FingeringSolver.FingerAssignment = plan.fingers[0] if not plan.fingers.is_empty() else null
	if thumb_assignment != null:
		if thumb_assignment.state == FingeringSolver.FingerState.STRIKING:
			if thumb_assignment.is_black:
				plan_z = minf(plan_z, 0.118)
			else:
				var wide_t: float = clampf((chord_span - 0.115) / 0.065, 0.0, 1.0)
				plan_z = minf(plan_z, lerpf(0.180, 0.166, wide_t))
		elif thumb_assignment.state == FingeringSolver.FingerState.ANTICIPATING:
			var thumb_ant_z: float = 0.124 if thumb_assignment.is_black else 0.191
			plan_z = lerpf(plan_z, minf(plan_z, thumb_ant_z), thumb_assignment.weight)
	var max_ant_weight: float = 0.0
	for assignment: FingeringSolver.FingerAssignment in plan.fingers:
		if assignment.state == FingeringSolver.FingerState.ANTICIPATING:
			max_ant_weight = maxf(max_ant_weight, assignment.weight)
	var ratio: float = _hold_black_ratio
	var target_z: float = _hold_z
	if plan.active_count > 0:
		ratio = plan_ratio
		target_z = plan_z
		_hold_black_ratio = ratio
		_hold_z = target_z
	elif plan.anticipating_count > 0:
		var z_blend: float = max_ant_weight * max_ant_weight
		ratio = lerpf(_hold_black_ratio, plan_ratio, z_blend)
		target_z = lerpf(_hold_z, plan_z, z_blend)
	var target_y: float = lerpf(WHITE_ACTIVE_Y, BLACK_REST_Y, ratio) if plan.active_count > 0 else lerpf(WHITE_REST_Y, BLACK_REST_Y, ratio)
	if plan.active_count == 0:
		target_y += sin(elapsed_time * 2.1 + float(side) * 1.3) * 0.0012
	target_y += -0.0035 * max_imp + 0.003 * max_reb
	var target_x: float = plan.wrist_target_x
	var prev_x: float = hand_root.position.x
	var x_speed: float = lerpf(WRIST_SPEED, ATTACK_SPEED, clampf(absf(target_x - prev_x) / 0.14, 0.0, 1.0))
	var raw_next_x: float = lerpf(prev_x, target_x, 1.0 - exp(-x_speed * step))
	var max_step: float = maxf(0.038, 1.8 * step)
	var next_x: float = prev_x + clampf(raw_next_x - prev_x, -max_step, max_step)
	_wrist_base_y = lerpf(_wrist_base_y, target_y, wrist_damping)
	hand_root.position = Vector3(next_x, _wrist_base_y, lerpf(hand_root.position.z, target_z, wrist_damping))
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
	var target_roll: float = clampf(-reach_offset * 0.45 - clampf(_wrist_velocity_x * 0.055, -0.045, 0.045), -0.085, 0.085)
	var target_yaw: float = clampf(_wrist_velocity_x * 0.045 + reach_offset * 0.35, -0.095, 0.095)
	var target_pitch: float = PI * 0.5 + deg_to_rad(-2.0 * (1.0 - ratio) * float(plan.active_count > 0) + 1.0 * ratio)
	hand_root.rotation.x = lerpf(hand_root.rotation.x, target_pitch, wrist_damping)
	hand_root.rotation.y = lerpf(hand_root.rotation.y, target_yaw, wrist_damping)
	hand_root.rotation.z = lerpf(hand_root.rotation.z, target_roll, wrist_damping)
	var target_scale_x: float = clampf(plan.target_scale_x, MIN_SCALE_X, MAX_SCALE_X) if plan.active_count > 0 else BASE_SCALE_X
	_hand_scale_x = lerpf(_hand_scale_x, target_scale_x, wrist_damping)
	hand_root.scale = Vector3(_hand_scale_x, 1.0, 1.0)
	var rest_splays: Array[float] = REST_SPLAY_LEFT if side == 0 else REST_SPLAY_RIGHT
	var hand_inv: Transform3D = hand_root.transform.affine_inverse()
	var target_splays: PackedFloat32Array = PackedFloat32Array()
	var finger_dampings: PackedFloat32Array = PackedFloat32Array()
	target_splays.resize(_chains.size())
	finger_dampings.resize(_chains.size())
	for finger: int in range(_chains.size()):
		var chain: FingerChain = _chains[finger]
		var assignment: FingeringSolver.FingerAssignment = plan.fingers[finger]
		var striking: bool = assignment.state == FingeringSolver.FingerState.STRIKING
		var anticipating: bool = assignment.state == FingeringSolver.FingerState.ANTICIPATING
		var rate: float = ATTACK_SPEED if striking else (ANTICIPATION_SPEED if anticipating else RELEASE_SPEED)
		var damping: float = 1.0 - exp(-rate * step)
		finger_dampings[finger] = damping
		chain.black_blend = lerpf(chain.black_blend, 1.0 if ((striking or anticipating) and assignment.is_black) else 0.0, damping)
		var marker_target: Vector3 = assignment.target_pos if striking or anticipating else _idle_target(chain)
		markers[finger].global_position = markers[finger].global_position.lerp(_stage_to_world(marker_target), damping)
		var black: bool = key_map.is_black_key(assignment.midi) if striking else false
		var targets: PackedFloat32Array = _finger_angles(finger, striking, black)
		if striking:
			targets[0] -= 3.5 * chain.strike_impulse
			targets[1] -= 6.5 * chain.strike_impulse
			if targets.size() > 2:
				targets[2] -= 3.0 * chain.strike_impulse
		elif anticipating:
			var lift: float = maxf(assignment.weight, chain.release_rebound)
			targets[0] += 4.5 * lift
			targets[1] += 5.0 * lift
			if targets.size() > 2:
				targets[2] -= 2.5 * lift
			if targets.size() > 3:
				targets[3] -= 2.5 * lift
		else:
			if chain.release_rebound > 0.01:
				targets[0] += 5.0 * chain.release_rebound
				targets[1] += 7.5 * chain.release_rebound
			elif _has_striking_neighbor(plan, finger):
				targets[0] += 4.0
				targets[1] += 7.5
				if targets.size() > 2:
					targets[2] -= 3.0
			var breath: float = sin(elapsed_time * 2.6 + float(finger) * 0.85 + float(side) * 1.4) * 1.2
			targets[1] += breath
			if targets.size() > 2:
				targets[2] += breath * 0.8
		for joint: int in range(chain.angles.size()):
			chain.angles[joint] = lerpf(chain.angles[joint], targets[joint], damping)
		var target_splay: float = rest_splays[finger]
		if striking or anticipating:
			var desired_for_splay: Vector3 = hand_inv * (assignment.target_pos if striking else _world_to_stage(markers[finger].global_position))
			target_splay = _solve_splay_for_x(chain, chain.angles, desired_for_splay.x, rest_splays[finger], _splay_bounds(finger))
		target_splays[finger] = target_splay
	for finger: int in range(1, _chains.size()):
		if plan.fingers[finger].state != FingeringSolver.FingerState.IDLE:
			continue
		var pull: float = 0.0
		if finger - 1 >= 1 and plan.fingers[finger - 1].state != FingeringSolver.FingerState.IDLE:
			pull += (target_splays[finger - 1] - rest_splays[finger - 1]) * 0.42
		if finger + 1 < _chains.size() and plan.fingers[finger + 1].state != FingeringSolver.FingerState.IDLE:
			pull += (target_splays[finger + 1] - rest_splays[finger + 1]) * 0.52
		if finger == 1 and not _chains.is_empty() and plan.fingers[0].state != FingeringSolver.FingerState.IDLE:
			pull += (target_splays[0] - rest_splays[0]) * 0.12
		if not is_zero_approx(pull):
			var bounds: Vector2 = _splay_bounds(finger)
			target_splays[finger] = clampf(rest_splays[finger] + pull, bounds.x, bounds.y)
	for finger: int in range(_chains.size()):
		_chains[finger].splay = lerpf(_chains[finger].splay, target_splays[finger], finger_dampings[finger])
	_enforce_finger_separation(plan)
	var needed_wrist_y: float = 0.0
	for finger: int in range(1, _chains.size()):
		needed_wrist_y = maxf(needed_wrist_y, _solve_long_finger_strike_and_collision(_chains[finger], plan.fingers[finger], key_map, key_depth, finger_dampings[finger], step))
	var req_wrist_y: float = clampf(needed_wrist_y, 0.0, 0.036)
	var wrist_clr_decay: float = 1.0 - exp(-18.0 * step)
	_wrist_collision_y = req_wrist_y if req_wrist_y >= _wrist_collision_y else lerpf(_wrist_collision_y, req_wrist_y, wrist_clr_decay)
	hand_root.position.y = _wrist_base_y + _wrist_collision_y
	hand_inv = hand_root.transform.affine_inverse()
	for finger: int in range(1, _chains.size()):
		var assignment: FingeringSolver.FingerAssignment = plan.fingers[finger]
		if assignment.state == FingeringSolver.FingerState.STRIKING:
			var ch: FingerChain = _chains[finger]
			var desired_loc: Vector3 = hand_inv * assignment.target_pos
			var refined_sp: float = _solve_splay_for_x(ch, _effective_angles(ch), desired_loc.x, ch.splay, _splay_bounds(finger))
			ch.splay = lerpf(ch.splay, refined_sp, finger_dampings[finger])
	if not _chains.is_empty():
		_solve_thumb_reach(plan.fingers[0], finger_dampings[0], hand_inv)
	_enforce_finger_separation(plan, true)
	if not _chains.is_empty():
		_solve_thumb_collision_and_wrist_guard(plan, key_map, key_depth, step)
	for chain: FingerChain in _chains:
		_apply_finger_fk(chain)

func _solve_splay_for_x(chain: FingerChain, eval_angles: PackedFloat32Array, desired_local_x: float, init_splay: float, bounds: Vector2) -> float:
	var sp: float = clampf(init_splay, bounds.x, bounds.y)
	for _iter: int in range(4):
		var tx: float = _unoffset_tip_local(chain, eval_angles, sp).x
		var dx: float = (_unoffset_tip_local(chain, eval_angles, sp + 0.01).x - tx) / 0.01
		if absf(dx) <= 0.01:
			break
		sp = clampf(sp + (desired_local_x - tx) / dx, bounds.x, bounds.y)
	return sp

func _splay_bounds(finger: int) -> Vector2:
	if side == 1:
		return Vector2(SPLAY_MIN_RIGHT[finger], SPLAY_MAX_RIGHT[finger])
	return Vector2(-SPLAY_MAX_RIGHT[finger], -SPLAY_MIN_RIGHT[finger])

func _enforce_finger_separation(plan: FingeringSolver.HandPlan, use_stage_and_offsets: bool = false) -> void:
	var sign_dir: float = 1.0 if side == 1 else -1.0
	var xs: PackedFloat32Array = PackedFloat32Array()
	xs.resize(_chains.size())
	for _iter: int in range(4):
		for f: int in range(_chains.size()):
			var chain: FingerChain = _chains[f]
			if use_stage_and_offsets:
				var pts: PackedVector3Array = _eval_joint_positions_local(chain, _effective_angles(chain), chain.splay, chain.root_offset)
				xs[f] = (hand_root.transform * pts[pts.size() - 1]).x if not pts.is_empty() else hand_root.position.x
			else:
				xs[f] = _unoffset_tip_local(chain, chain.angles, chain.splay).x * _hand_scale_x
		for f: int in range(mini(MIN_TIP_GAP.size(), _chains.size() - 1)):
			var gap: float = (xs[f + 1] - xs[f]) * sign_dir
			if gap >= MIN_TIP_GAP[f]:
				continue
			var deficit: float = MIN_TIP_GAP[f] - gap
			var d_splay: float = (deficit / (0.090 * _hand_scale_x)) * sign_dir
			var f_strike: bool = plan.fingers[f].state == FingeringSolver.FingerState.STRIKING
			var next_strike: bool = plan.fingers[f + 1].state == FingeringSolver.FingerState.STRIKING
			var w0: float = 0.0 if (f_strike and not next_strike) else (1.0 if (not f_strike and next_strike) else 0.5)
			var w1: float = 1.0 - w0
			var b0: Vector2 = _splay_bounds(f)
			var b1: Vector2 = _splay_bounds(f + 1)
			var prev0: float = _chains[f].splay
			var prev1: float = _chains[f + 1].splay
			_chains[f].splay = clampf(prev0 - d_splay * w0, b0.x, b0.y)
			_chains[f + 1].splay = clampf(prev1 + d_splay * w1, b1.x, b1.y)
			var applied: float = ((prev0 - _chains[f].splay) + (_chains[f + 1].splay - prev1)) * sign_dir
			var rem_splay: float = (d_splay * sign_dir) - applied
			if rem_splay > 0.0005:
				_chains[f].splay = clampf(_chains[f].splay - rem_splay * 0.5 * sign_dir, b0.x, b0.y)
				_chains[f + 1].splay = clampf(_chains[f + 1].splay + rem_splay * 0.5 * sign_dir, b1.x, b1.y)

func _solve_long_finger_strike_and_collision(chain: FingerChain, assignment: FingeringSolver.FingerAssignment, key_map: KeyMap3D, key_depth: PackedFloat32Array, damping: float, step: float) -> float:
	chain.root_offset = Vector3.ZERO
	var striking: bool = assignment.state == FingeringSolver.FingerState.STRIKING
	var target_strike_flex: float = 0.0
	if striking:
		var tip_stage: Vector3 = hand_root.transform * _unoffset_tip_local(chain, chain.angles, chain.splay)
		var err_y: float = assignment.target_pos.y - tip_stage.y
		target_strike_flex = clampf(rad_to_deg(asin(clampf(err_y / 0.085, -0.35, 0.35))), -10.0, 12.0)
	chain.strike_flex_deg = lerpf(chain.strike_flex_deg, target_strike_flex, damping)
	if key_map == null or chain.rests.is_empty():
		chain.collision_lift_deg = 0.0
		return 0.0
	var needed_lift: float = _probe_collision_lift(chain, _apply_flex_and_lift(chain, 0.0), key_map, key_depth, striking)
	var req_deg: float = clampf(rad_to_deg(asin(clampf(needed_lift / 0.060, 0.0, 0.65))), 0.0, 28.0) if needed_lift > 0.0 else 0.0
	var decay: float = 1.0 - exp(-16.0 * step)
	chain.collision_lift_deg = req_deg if req_deg >= chain.collision_lift_deg else lerpf(chain.collision_lift_deg, req_deg, decay)
	return maxf(0.0, _probe_collision_lift(chain, _effective_angles(chain), key_map, key_depth, striking))

func _solve_thumb_reach(t_assignment: FingeringSolver.FingerAssignment, t_damping: float, hand_inv: Transform3D) -> void:
	var t_chain: FingerChain = _chains[0]
	var t_striking: bool = t_assignment.state == FingeringSolver.FingerState.STRIKING
	if t_striking:
		var tip0: Vector3 = hand_root.transform * _unoffset_tip_local(t_chain, t_chain.angles, t_chain.splay)
		var err_y: float = t_assignment.target_pos.y - tip0.y
		var target_t_flex: float = clampf(rad_to_deg(asin(clampf(err_y / 0.055, -0.5, 0.5))), -10.0, 14.0)
		t_chain.strike_flex_deg = lerpf(t_chain.strike_flex_deg, target_t_flex, t_damping)
		var flex_angles: PackedFloat32Array = _apply_flex_and_lift(t_chain, 0.0)
		var desired_local: Vector3 = hand_inv * t_assignment.target_pos
		var unoff_tip: Vector3 = _unoffset_tip_local(t_chain, flex_angles, t_chain.splay)
		var dloc: Vector3 = desired_local - unoff_tip
		var ro: Vector3 = Vector3(
			clampf(dloc.x, -0.012, 0.012),
			clampf(dloc.y, -0.018, 0.010),
			clampf(dloc.z, -0.012, 0.014)
		)
		t_chain.root_offset = t_chain.root_offset.lerp(ro, t_damping)
	else:
		t_chain.strike_flex_deg = lerpf(t_chain.strike_flex_deg, 0.0, t_damping)
		t_chain.root_offset = t_chain.root_offset.lerp(Vector3.ZERO, t_damping)
	if _chains.size() > 1:
		var sign_dir: float = 1.0 if side == 1 else -1.0
		var idx_pts: PackedVector3Array = _eval_joint_positions_local(_chains[1], _effective_angles(_chains[1]), _chains[1].splay, _chains[1].root_offset)
		var t_pts: PackedVector3Array = _eval_joint_positions_local(t_chain, _effective_angles(t_chain), t_chain.splay, t_chain.root_offset)
		if not idx_pts.is_empty() and not t_pts.is_empty():
			var idx_x: float = (hand_root.transform * idx_pts[idx_pts.size() - 1]).x
			var t_x: float = (hand_root.transform * t_pts[t_pts.size() - 1]).x
			var t_gap: float = (idx_x - t_x) * sign_dir
			if t_gap < 0.018:
				var push_local: Vector3 = hand_inv.basis * Vector3(-(0.018 - t_gap) * sign_dir, 0.0, 0.0)
				t_chain.root_offset.x = clampf(t_chain.root_offset.x + push_local.x, -0.014, 0.014)

func _solve_thumb_collision_and_wrist_guard(plan: FingeringSolver.HandPlan, key_map: KeyMap3D, key_depth: PackedFloat32Array, step: float) -> void:
	var t_chain: FingerChain = _chains[0]
	var t_striking: bool = plan.fingers[0].state == FingeringSolver.FingerState.STRIKING
	if key_map == null or t_chain.rests.is_empty():
		t_chain.collision_lift_deg = 0.0
		return
	var needed_lift: float = _probe_collision_lift(t_chain, _apply_flex_and_lift(t_chain, 0.0), key_map, key_depth, t_striking)
	var req_deg: float = clampf(rad_to_deg(asin(clampf(needed_lift / 0.055, 0.0, 0.65))), 0.0, 22.0) if needed_lift > 0.0 else 0.0
	var decay: float = 1.0 - exp(-16.0 * step)
	t_chain.collision_lift_deg = req_deg if req_deg >= t_chain.collision_lift_deg else lerpf(t_chain.collision_lift_deg, req_deg, decay)
	var extra_wy: float = 0.0
	for finger: int in range(_chains.size()):
		var ch: FingerChain = _chains[finger]
		if not ch.rests.is_empty():
			var st: bool = plan.fingers[finger].state == FingeringSolver.FingerState.STRIKING
			extra_wy = maxf(extra_wy, _probe_collision_lift(ch, _effective_angles(ch), key_map, key_depth, st))
	if extra_wy > 0.0:
		var add_y: float = clampf(extra_wy, 0.0, 0.045 - _wrist_collision_y)
		if add_y > 0.0:
			_wrist_collision_y += add_y
			hand_root.position.y = _wrist_base_y + _wrist_collision_y

func _probe_collision_lift(chain: FingerChain, eval_angles: PackedFloat32Array, key_map: KeyMap3D, key_depth: PackedFloat32Array, striking: bool) -> float:
	var start_joint: int = 1 if chain.finger_name == "thumb" else 2
	var tip_joint: int = chain.rests.size() - 1
	var front_margin: float = KeyMap3D.FINGER_TIP_FORWARD if striking else (KeyMap3D.FINGER_TIP_FORWARD + 0.003)
	var clearance_pad: float = (KeyMap3D.FINGER_PAD_RADIUS - 0.0015) if striking else (KeyMap3D.FINGER_PAD_RADIUS + 0.003)
	var pts: PackedVector3Array = _eval_joint_positions_local(chain, eval_angles, chain.splay, chain.root_offset)
	var needed_lift: float = 0.0
	for joint: int in range(start_joint, pts.size()):
		var p_stage: Vector3 = hand_root.transform * pts[joint]
		var j_front: float = front_margin if joint == tip_joint else 0.006
		var min_y: float = key_map.get_surface_ceiling_y(p_stage.x, p_stage.z, key_depth, KeyMap3D.FINGER_HALF_WIDTH, j_front, 0.006) + clearance_pad
		needed_lift = maxf(needed_lift, min_y - p_stage.y)
	return needed_lift

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
		return hand_root.position + Vector3(0.058 if side == 0 else -0.058, -0.048, -0.114)
	return hand_root.position + Vector3(chain.rest_posed_tip_x * _hand_scale_x, -0.044, -0.140)

func _finger_angles(finger: int, striking: bool, black: bool) -> PackedFloat32Array:
	match finger:
		0:
			return PackedFloat32Array(([-1.0, -6.0, -7.0] if black else [-3.0, -7.0, -8.0]) if striking else [2.0, -4.0, -5.0])
		1:
			return PackedFloat32Array(([1.0, -18.0, -21.0, -13.0] if black else [-3.0, -26.0, -26.0, -16.0]) if striking else [3.0, -13.0, -19.0, -13.0])
		2:
			return PackedFloat32Array(([1.0, -19.0, -21.0, -13.0] if black else [-3.0, -27.0, -27.0, -16.0]) if striking else [3.0, -14.0, -20.0, -13.0])
		3:
			return PackedFloat32Array(([1.0, -18.0, -21.0, -13.0] if black else [-3.0, -26.0, -26.0, -16.0]) if striking else [3.0, -13.0, -19.0, -13.0])
		_:
			return PackedFloat32Array(([2.0, -17.0, -19.0, -12.0] if black else [-2.0, -24.0, -24.0, -15.0]) if striking else [4.0, -13.0, -19.0, -13.0])

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
	else:
		var w0: float = 0.20 if chain.finger_name == "middle" else 0.32
		if joint == 0:
			delta_basis = Basis(Vector3.BACK, eval_splay * w0) * delta_basis
		elif joint == 1:
			delta_basis = Basis(Vector3.BACK, eval_splay * (1.0 - w0)) * delta_basis
	return delta_basis

func _eval_joint_positions_local(chain: FingerChain, eval_angles: PackedFloat32Array, eval_splay: float, root_off: Vector3) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	if chain.rests.is_empty():
		return result
	var cumulative: Basis = Basis.IDENTITY
	var position: Vector3 = Vector3.ZERO
	var previous_rest: Vector3 = Vector3.ZERO
	var axis: Vector3 = _thumb_axis() if chain.finger_name == "thumb" else Vector3.RIGHT
	for joint: int in range(chain.rests.size()):
		var rest: Transform3D = chain.rests[joint]
		position = rest.origin + root_off if joint == 0 else position + cumulative * (rest.origin - previous_rest)
		result.append(position)
		cumulative = cumulative * _joint_delta_basis(chain, joint, eval_angles, eval_splay, axis)
		previous_rest = rest.origin
	return result

func _apply_flex_and_lift(chain: FingerChain, lift_deg: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = chain.angles.duplicate()
	if chain.finger_name == "thumb":
		if not out.is_empty():
			out[0] += chain.strike_flex_deg * 0.6 + lift_deg
		if out.size() > 1:
			out[1] += chain.strike_flex_deg * 0.4
	elif out.size() > 1:
		out[1] += chain.strike_flex_deg + lift_deg
		if out.size() > 2:
			out[2] -= lift_deg * 0.65
	return out

func _effective_angles(chain: FingerChain) -> PackedFloat32Array:
	return _apply_flex_and_lift(chain, chain.collision_lift_deg)

func _unoffset_tip_local(chain: FingerChain, eval_angles: PackedFloat32Array, eval_splay: float) -> Vector3:
	var pts: PackedVector3Array = _eval_joint_positions_local(chain, eval_angles, eval_splay, Vector3.ZERO)
	return pts[pts.size() - 1] if not pts.is_empty() else Vector3.ZERO

func _apply_finger_fk(chain: FingerChain) -> void:
	if _skeleton == null:
		return
	var eval_angles: PackedFloat32Array = _effective_angles(chain)
	var cumulative: Basis = Basis.IDENTITY
	var position: Vector3 = Vector3.ZERO
	var previous_rest: Vector3 = Vector3.ZERO
	var axis: Vector3 = _thumb_axis() if chain.finger_name == "thumb" else Vector3.RIGHT
	for joint: int in range(chain.bones.size()):
		var rest: Transform3D = chain.rests[joint]
		position = rest.origin + chain.root_offset if joint == 0 else position + cumulative * (rest.origin - previous_rest)
		cumulative = cumulative * _joint_delta_basis(chain, joint, eval_angles, chain.splay, axis)
		_skeleton.set_bone_pose_position(chain.bones[joint], position)
		_skeleton.set_bone_pose_rotation(chain.bones[joint], (cumulative * rest.basis).get_rotation_quaternion())
		previous_rest = rest.origin
