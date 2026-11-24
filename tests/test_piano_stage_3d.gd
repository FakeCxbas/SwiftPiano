# SwiftPiano - PianoStage3D Test Suite
# Copyright (c) 2026 Sebastián Zambrano
# Distributed under the terms of the MIT License.

extends SceneTree
const PianoStage3DClass = preload("res://scripts/piano_stage_3d.gd")
const MainScene = preload("res://scenes/main.tscn")

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, msg: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", msg)

func _thumb_tip_stage_pos(stage: PianoStage3D, side: int) -> Vector3:
	var skel: Skeleton3D = stage._skeletons[side]
	var tip_idx: int = skel.find_bone("thumb-tip")
	return stage.world_root.to_local(skel.to_global(skel.get_bone_pose_position(tip_idx)))

func _thumb_segments_valid(stage: PianoStage3D, side: int) -> bool:
	var skel: Skeleton3D = stage._skeletons[side]
	var names: Array[String] = ["thumb-metacarpal", "thumb-phalanx-proximal", "thumb-phalanx-distal", "thumb-tip"]
	for k: int in range(names.size() - 1):
		var b0: int = skel.find_bone(names[k])
		var b1: int = skel.find_bone(names[k + 1])
		var d_rest: float = skel.get_bone_rest(b1).origin.distance_to(skel.get_bone_rest(b0).origin)
		var d_pose: float = skel.get_bone_pose_position(b1).distance_to(skel.get_bone_pose_position(b0))
		if absf(d_pose - d_rest) >= 0.001:
			return false
	return true

func _min_finger_clearance(stage: PianoStage3D, side: int) -> float:
	var skel: Skeleton3D = stage._skeletons[side]
	var min_clr: float = INF
	var specs: Array = [
		["thumb-phalanx-distal", "thumb-tip"],
		["index-finger-phalanx-distal", "index-finger-tip"],
		["middle-finger-phalanx-distal", "middle-finger-tip"],
		["ring-finger-phalanx-distal", "ring-finger-tip"],
		["pinky-finger-phalanx-distal", "pinky-finger-tip"]
	]
	for pair: Array in specs:
		for j: int in range(pair.size()):
			var b_idx: int = skel.find_bone(str(pair[j]))
			if b_idx < 0:
				continue
			var p_stage: Vector3 = stage.world_root.to_local(skel.to_global(skel.get_bone_pose_position(b_idx)))
			var j_front: float = KeyMap3D.FINGER_TIP_FORWARD if j == pair.size() - 1 else 0.006
			var ceiling: float = stage.key_map.get_surface_ceiling_y(p_stage.x, p_stage.z, stage._depth, KeyMap3D.FINGER_HALF_WIDTH, j_front, 0.006)
			min_clr = minf(min_clr, p_stage.y - (ceiling + KeyMap3D.FINGER_PAD_RADIUS))
	return min_clr

func _check_hand_anatomy(stage: PianoStage3D, side: int) -> Dictionary:
	var skel: Skeleton3D = stage._skeletons[side]
	var sign_dir: float = 1.0 if side == 1 else -1.0
	var finger_bones: Array = [
		["thumb-metacarpal", "thumb-phalanx-proximal", "thumb-phalanx-distal", "thumb-tip"],
		["index-finger-metacarpal", "index-finger-phalanx-proximal", "index-finger-phalanx-intermediate", "index-finger-phalanx-distal", "index-finger-tip"],
		["middle-finger-metacarpal", "middle-finger-phalanx-proximal", "middle-finger-phalanx-intermediate", "middle-finger-phalanx-distal", "middle-finger-tip"],
		["ring-finger-metacarpal", "ring-finger-phalanx-proximal", "ring-finger-phalanx-intermediate", "ring-finger-phalanx-distal", "ring-finger-tip"],
		["pinky-finger-metacarpal", "pinky-finger-phalanx-proximal", "pinky-finger-phalanx-intermediate", "pinky-finger-phalanx-distal", "pinky-finger-tip"]
	]
	var max_long_meta_disp: float = 0.0
	var thumb_meta_disp: float = 0.0
	var min_tip_gap: float = INF
	var max_seg_err: float = 0.0
	var tip_xs: PackedFloat32Array = PackedFloat32Array()
	for spec_idx: int in range(finger_bones.size()):
		var chain_names: Array = finger_bones[spec_idx]
		for k: int in range(chain_names.size() - 1):
			var b0: int = skel.find_bone(str(chain_names[k]))
			var b1: int = skel.find_bone(str(chain_names[k + 1]))
			var d_rest: float = skel.get_bone_rest(b1).origin.distance_to(skel.get_bone_rest(b0).origin)
			var d_pose: float = skel.get_bone_pose_position(b1).distance_to(skel.get_bone_pose_position(b0))
			max_seg_err = maxf(max_seg_err, absf(d_pose - d_rest))
		var meta_idx: int = skel.find_bone(str(chain_names[0]))
		var meta_disp: float = skel.get_bone_pose_position(meta_idx).distance_to(skel.get_bone_rest(meta_idx).origin)
		if spec_idx == 0:
			thumb_meta_disp = meta_disp
		else:
			max_long_meta_disp = maxf(max_long_meta_disp, meta_disp)
		var tip_b: int = skel.find_bone(str(chain_names.back()))
		var tip_stage: Vector3 = stage.world_root.to_local(skel.to_global(skel.get_bone_pose_position(tip_b)))
		tip_xs.append(tip_stage.x)
	for i: int in range(tip_xs.size() - 1):
		min_tip_gap = minf(min_tip_gap, (tip_xs[i + 1] - tip_xs[i]) * sign_dir)
	return {
		"max_long_meta_disp": max_long_meta_disp,
		"thumb_meta_disp": thumb_meta_disp,
		"min_tip_gap": min_tip_gap,
		"max_seg_err": max_seg_err
	}

func _max_assigned_x_error(stage: PianoStage3D, side: int) -> Dictionary:
	var skel: Skeleton3D = stage._skeletons[side]
	var chains: Array = stage.hand_controllers[side]._chains
	var tip_names: Array[String] = ["thumb-tip", "index-finger-tip", "middle-finger-tip", "ring-finger-tip", "pinky-finger-tip"]
	var max_err: float = 0.0
	var count: int = 0
	for i: int in range(chains.size()):
		var ch: HandIKController.FingerChain = chains[i]
		if ch.last_state != FingeringSolver.FingerState.STRIKING or ch.last_midi < 21:
			continue
		var tip_b: int = skel.find_bone(tip_names[i])
		var tip_stage: Vector3 = stage.world_root.to_local(skel.to_global(skel.get_bone_pose_position(tip_b)))
		var key_x: float = stage.key_map.get_key_rest_position(ch.last_midi).x
		max_err = maxf(max_err, absf(tip_stage.x - key_x))
		count += 1
	return {"count": count, "max_err": max_err}

func _run() -> void:
	print("--- Running PianoStage3D Tests ---")
	root.size = Vector2i(1920, 1080)
	var stage = PianoStage3DClass.new()
	root.add_child(stage)
	await process_frame
	stage.size = Vector2(1920, 1080)
	stage.arrange(stage.size)
	await process_frame
	
	check(stage != null, "Stage instantiated")
	check(stage.stage_viewport != null, "SubViewport initialized")
	check(stage.camera != null, "Camera3D initialized")
	check(stage.world_root != null, "World3D root initialized")
	check(stage._keys.size() == 88, "88 3D keys generated")
	check(stage._hands.size() == 2, "2 3D hands instantiated")
	check(stage._skeletons.size() == 2, "2 3D skeletons tracked")
	var init_clr_l: float = _min_finger_clearance(stage, 0)
	var init_clr_r: float = _min_finger_clearance(stage, 1)
	check(init_clr_l >= -0.0025 and init_clr_r >= -0.0025, "Idle rest hands clear black and white keys without clipping (L=%.2fmm, R=%.2fmm)" % [init_clr_l * 1000.0, init_clr_r * 1000.0])
	var init_anat_l: Dictionary = _check_hand_anatomy(stage, 0)
	var init_anat_r: Dictionary = _check_hand_anatomy(stage, 1)
	check(float(init_anat_l["max_long_meta_disp"]) < 0.0005 and float(init_anat_r["max_long_meta_disp"]) < 0.0005 and float(init_anat_l["min_tip_gap"]) >= 0.013 and float(init_anat_r["min_tip_gap"]) >= 0.013 and float(init_anat_l["max_seg_err"]) < 0.001 and float(init_anat_r["max_seg_err"]) < 0.001, "Idle hands preserve zero long-metacarpal dislocation, bone lengths, and finger separation (L_gap=%.1fmm, R_gap=%.1fmm)" % [float(init_anat_l["min_tip_gap"]) * 1000.0, float(init_anat_r["min_tip_gap"]) * 1000.0])
	
	# Test key depression
	stage.press_key(60, Color.CYAN)
	stage.press_key(48, Color.MAGENTA)
	check(stage._pressed[60 - 21] == 1, "Middle C (60) marked pressed")
	check(stage._pressed[48 - 21] == 1, "C3 (48) marked pressed")
	
	# Process physics frames
	for f in range(5):
		stage._process(0.016)
	
	check(stage._depth[60 - 21] > 0.05, "Key 60 physical depth depressed")
	check(stage._energy[60 - 21] > 1.0, "Key 60 emission energy active")
	
	# Test waterfall notes
	var notes: Array[PianoStage3D.StageNote] = [
		PianoStage3D.StageNote.new(60, 0.5, 0.4, Color.CYAN),
		PianoStage3D.StageNote.new(64, 1.0, 0.4, Color.YELLOW),
		PianoStage3D.StageNote.new(67, 1.5, 0.4, Color.MAGENTA)
	]
	stage.set_notes(notes)
	check(stage._notes.size() == 3, "3 stage notes loaded")
	
	stage.set_playback_time(0.6)
	stage._process(0.016)
	check(stage._playback_time == 0.6, "Playback time updated")
	
	# Test release
	stage.release_key(60)
	check(stage._pressed[60 - 21] == 0, "Key 60 released")
	
	stage.release_all()
	for f in range(20):
		stage._process(0.016)
	
	check(stage._depth[60 - 21] < 0.02, "Key 60 returned to rest position")

	# KeyMap3D metrics and pressed transform checks
	check(stage.key_map != null, "KeyMap3D initialized")
	check(not stage.key_map.is_black_key(60) and stage.key_map.is_black_key(61), "KeyMap3D differentiates white (60) and black (61) keys")
	var white_contact: Vector3 = stage.key_map.get_strike_contact_point(60, 0.0, false)
	var black_contact: Vector3 = stage.key_map.get_strike_contact_point(61, 0.0, false)
	var white_hover: Vector3 = stage.key_map.get_hover_point(60, false)
	check(black_contact.y > white_contact.y and black_contact.z < white_contact.z, "Black key contact target sits higher and further back in Z than white key")
	check(white_hover.y > white_contact.y, "Hover point floats cleanly above strike surface")

	# Camera framing: all 88 keys visible horizontally and anchored in lower band
	var p_a0: Vector2 = stage.camera.unproject_position(stage._keys[0].global_position)
	var p_c8: Vector2 = stage.camera.unproject_position(stage._keys[87].global_position)
	var p_mid: Vector2 = stage.camera.unproject_position(stage._keys[39].global_position)
	check(p_a0.x >= 0.0 and p_c8.x <= stage.size.x and p_c8.x > p_a0.x, "All 88 keys project cleanly within horizontal viewport bounds")
	check(p_mid.y > stage.size.y * 0.70 and p_mid.y < stage.size.y, "Keyboard projects in the lower screen band")

	# FingeringSolver active + anticipation lookahead + non-crossing order
	var future_notes: Array[PianoStage3D.StageNote] = [
		PianoStage3D.StageNote.new(64, 0.10, 0.3, Color.CYAN),
		PianoStage3D.StageNote.new(67, 0.10, 0.3, Color.CYAN)
	]
	stage.set_notes(future_notes)
	stage.set_playback_time(0.0)
	stage.press_key(60, Color.CYAN)
	var wrist_xs: Array[float] = [-0.18, 0.18]
	var plans: Array = stage.fingering_solver.solve(stage.key_map, stage._pressed, stage._depth, stage._notes, 0, 0.0, wrist_xs)
	var r_plan: FingeringSolver.HandPlan = plans[1]
	check(r_plan.active_count == 1 and r_plan.anticipating_count == 2, "FingeringSolver assigns active notes and upcoming notes within 0.28s window")
	var used_fingers: Array[int] = []
	for fa: FingeringSolver.FingerAssignment in r_plan.fingers:
		if fa.state != FingeringSolver.FingerState.IDLE:
			used_fingers.append(fa.finger_index)
	check(used_fingers.size() == 3, "FingeringSolver assigns distinct fingers without colliding")
	stage.release_all()
	var empty_notes: Array[PianoStage3D.StageNote] = []
	stage.set_notes(empty_notes)
	for _f in range(20):
		stage._process(0.016)

	# HandIKController: Marker3D targets, 25-bone FK chain integrity, and black-key wrist advance
	check(stage.hand_controllers.size() == 2 and stage.hand_controllers[1].markers.size() == 5, "HandIKController creates 5 Marker3D nodes per hand")
	var skel_r: Skeleton3D = stage._skeletons[1]
	var prox_idx: int = skel_r.find_bone("index-finger-phalanx-proximal")
	var inter_idx: int = skel_r.find_bone("index-finger-phalanx-intermediate")
	var tip_idx: int = skel_r.find_bone("index-finger-tip")
	var rest_seg_len: float = skel_r.get_bone_rest(inter_idx).origin.distance_to(skel_r.get_bone_rest(prox_idx).origin)
	var rest_wrist_z: float = stage._hands[1].position.z
	var tip_pose_before: Vector3 = skel_r.get_bone_pose_position(tip_idx)
	stage.press_key(61, Color.MAGENTA)
	for _f in range(15):
		stage._process(0.016)
	var tip_pose_after: Vector3 = skel_r.get_bone_pose_position(tip_idx)
	var pose_seg_len: float = skel_r.get_bone_pose_position(inter_idx).distance_to(skel_r.get_bone_pose_position(prox_idx))
	check(absf(pose_seg_len - rest_seg_len) < 0.001, "25-bone FK preserves rigid phalanx distance without detaching finger segments")
	check(tip_pose_before.distance_to(tip_pose_after) > 0.002 and skel_r.get_bone_pose_rotation(tip_idx) != skel_r.get_bone_rest(tip_idx).basis.get_rotation_quaternion(), "FK updates both pose position and rotation on distal/tip joints")
	check(stage._hands[1].position.z < rest_wrist_z - 0.01, "Wrist advances forward in -Z when playing black keys")
	stage.release_all()
	for _f in range(25):
		stage._process(0.016)

	# Biomechanical refinement regression: curl depth, lateral range, 60-frame continuity, lighting balance
	var hc_r: HandIKController = stage.hand_controllers[1]
	var rest_curl_sum: float = 0.0
	var white_curl_sum: float = 0.0
	var black_curl_sum: float = 0.0
	for j: int in range(1, 4):
		rest_curl_sum += -hc_r._finger_angles(2, false, false)[j]
		white_curl_sum += -hc_r._finger_angles(2, true, false)[j]
		black_curl_sum += -hc_r._finger_angles(2, true, true)[j]
	check(white_curl_sum > rest_curl_sum + 12.0 and black_curl_sum > rest_curl_sum + 2.0, "STRIKING flexion exceeds IDLE dome curl on both white and black keys")

	var continuity_ok: bool = true
	var jump_clearance_ok: bool = true
	var jump_anatomy_ok: bool = true
	var min_jump_clr: float = INF
	var min_jump_gap: float = INF
	var max_jump_meta: float = 0.0
	var max_jump_thumb_meta: float = 0.0
	var max_wrist_step: float = 0.0
	var max_light_energy: float = 0.0
	var chord_seq: Array = [[25, 28, 32], [103, 106, 108], [61, 66, 70], [42, 46, 51], [85, 90, 97]]
	var prev_wx: Array[float] = [stage._hands[0].position.x, stage._hands[1].position.x]
	for frame_idx: int in range(60):
		if frame_idx % 12 == 0:
			stage.release_all()
			var grp: Array = chord_seq[int(frame_idx / 12) % chord_seq.size()]
			for n_midi: int in grp:
				stage.press_key(n_midi, Color.RED if n_midi >= 60 else Color.CYAN)
		stage._process(0.016)
		for side_i: int in range(2):
			max_wrist_step = maxf(max_wrist_step, absf(stage._hands[side_i].position.x - prev_wx[side_i]))
			prev_wx[side_i] = stage._hands[side_i].position.x
			max_light_energy = maxf(max_light_energy, stage._hand_lights[side_i].light_energy)
			var frame_clr: float = _min_finger_clearance(stage, side_i)
			min_jump_clr = minf(min_jump_clr, frame_clr)
			if frame_clr < -0.003:
				jump_clearance_ok = false
			var anat: Dictionary = _check_hand_anatomy(stage, side_i)
			min_jump_gap = minf(min_jump_gap, float(anat["min_tip_gap"]))
			max_jump_meta = maxf(max_jump_meta, float(anat["max_long_meta_disp"]))
			max_jump_thumb_meta = maxf(max_jump_thumb_meta, float(anat["thumb_meta_disp"]))
			if float(anat["max_long_meta_disp"]) >= 0.0005 or float(anat["thumb_meta_disp"]) > 0.025 or float(anat["min_tip_gap"]) < 0.013 or float(anat["max_seg_err"]) >= 0.001:
				jump_anatomy_ok = false
			var sk_i: Skeleton3D = stage._skeletons[side_i]
			for f_name: String in ["index", "middle", "ring", "pinky"]:
				var b_names: Array[String] = [f_name + "-finger-phalanx-proximal", f_name + "-finger-phalanx-intermediate", f_name + "-finger-phalanx-distal", f_name + "-finger-tip"]
				for k: int in range(3):
					var bi0: int = sk_i.find_bone(b_names[k])
					var bi1: int = sk_i.find_bone(b_names[k + 1])
					var d_rest: float = sk_i.get_bone_rest(bi1).origin.distance_to(sk_i.get_bone_rest(bi0).origin)
					var d_pose: float = sk_i.get_bone_pose_position(bi1).distance_to(sk_i.get_bone_pose_position(bi0))
					if absf(d_pose - d_rest) > 0.001:
						continuity_ok = false
	check(continuity_ok, "60-frame rapid octave jumps & black chords preserve all phalanx bone lengths within 1mm")
	check(jump_clearance_ok, "60-frame rapid octave jumps keep all 10 fingers above key surfaces (min clr=%.2fmm)" % [min_jump_clr * 1000.0])
	check(jump_anatomy_ok, "60-frame rapid octave jumps preserve anatomy without crossing or metacarpal dislocation (min_gap=%.1fmm, long_meta=%.2fmm, thumb_meta=%.1fmm)" % [min_jump_gap * 1000.0, max_jump_meta * 1000.0, max_jump_thumb_meta * 1000.0])
	check(max_wrist_step < 0.05, "Rapid octave jumps interpolate smoothly without abrupt per-frame teleport steps")
	check(max_light_energy <= 0.56, "Hand reactive OmniLight3D stays balanced and capped below saturation")

	stage.release_all()
	stage.press_key(105, Color.RED)
	for _f in range(35):
		stage._process(0.016)
	check(stage._hands[1].position.x > 0.45, "Right wrist decisively tracks high-register outer keys")
	stage.release_all()
	for _f in range(25):
		stage._process(0.016)

	# Expressive 4-phase attack impulse & release rebound + melodic finger alternation
	var imp_solver: FingeringSolver = FingeringSolver.new()
	var p_buf: PackedByteArray = PackedByteArray()
	var d_buf: PackedFloat32Array = PackedFloat32Array()
	p_buf.resize(88)
	d_buf.resize(88)
	p_buf[60 - 21] = 1
	var empty_n: Array[PianoStage3D.StageNote] = []
	var w_pos: Array[float] = [-0.18, 0.14]
	var plan_60: FingeringSolver.HandPlan = imp_solver.solve(stage.key_map, p_buf, d_buf, empty_n, 0, 0.0, w_pos)[1]
	var f_60: int = -1
	for fa: FingeringSolver.FingerAssignment in plan_60.fingers:
		if fa.midi == 60:
			f_60 = fa.finger_index
	p_buf[60 - 21] = 0
	p_buf[62 - 21] = 1
	var plan_62: FingeringSolver.HandPlan = imp_solver.solve(stage.key_map, p_buf, d_buf, empty_n, 0, 0.0, w_pos)[1]
	var f_62: int = -1
	for fa: FingeringSolver.FingerAssignment in plan_62.fingers:
		if fa.midi == 62:
			f_62 = fa.finger_index
	check(f_60 >= 0 and f_62 >= 0 and f_60 != f_62, "FingeringSolver alternates fingers on consecutive notes 60 -> 62 (%d vs %d)" % [f_60, f_62])

	stage.press_key(64, Color.CYAN)
	stage._process(0.016)
	var imp_chain: HandIKController.FingerChain = null
	for ch: HandIKController.FingerChain in stage.hand_controllers[1]._chains:
		if ch.last_midi == 64 and ch.last_state == FingeringSolver.FingerState.STRIKING:
			imp_chain = ch
			break
	check(imp_chain != null and imp_chain.strike_impulse > 0.5, "Pressing note triggers strong initial strike_impulse")
	var peak_attack_prox: float = imp_chain.angles[1] if imp_chain != null else 0.0
	for _f in range(6):
		stage._process(0.016)
		if imp_chain != null:
			peak_attack_prox = minf(peak_attack_prox, imp_chain.angles[1])
	for _f in range(30):
		stage._process(0.016)
	var steady_hold_prox: float = imp_chain.angles[1] if imp_chain != null else 0.0
	check(peak_attack_prox < steady_hold_prox - 1.5, "Initial attack impulse bends proximal joint deeper (%0.2f deg) than steady hold (%0.2f deg)" % [peak_attack_prox, steady_hold_prox])
	stage.release_all()
	stage._process(0.016)
	check(imp_chain.release_rebound > 0.5, "Releasing note triggers upward release_rebound")
	check(stage.stage_viewport.msaa_3d == SubViewport.MSAA_4X, "SubViewport MSAA 4X active for clean finger silhouettes")
	for _f in range(25):
		stage._process(0.016)

	# Thumb 3D contact precision, opposition adduction, and two-hand closing chord balance
	var verify_thumb := func(label: String, chord: Array, side: int, expected_midi: int) -> void:
		stage.release_all()
		for _f in range(10):
			stage._process(0.016)
		for m: int in chord:
			stage.press_key(m, Color.CYAN if m < 60 else Color.MAGENTA)
		for _f in range(25):
			stage._process(0.016)
		var ch: HandIKController.FingerChain = stage.hand_controllers[side]._chains[0]
		var target_pos: Vector3 = stage.key_map.get_strike_contact_point(expected_midi, stage._depth[expected_midi - 21], true)
		var tip_pos: Vector3 = _thumb_tip_stage_pos(stage, side)
		var err_m: float = tip_pos.distance_to(target_pos)
		check(ch.last_state == FingeringSolver.FingerState.STRIKING and ch.last_midi == expected_midi, "%s assigns thumb to MIDI %d (got state=%d midi=%d)" % [label, expected_midi, ch.last_state, ch.last_midi])
		check(err_m < 0.008, "%s 3D thumb-tip lands within 8mm of target key (err=%.2f mm, target=%s, actual=%s)" % [label, err_m * 1000.0, str(target_pos), str(tip_pos)])
		check(_thumb_segments_valid(stage, side), "%s preserves invariant thumb phalanx lengths" % label)

	verify_thumb.call("Right thumb white triad", [60, 64, 67], 1, 60)
	verify_thumb.call("Right thumb black-key chord", [61, 65, 68, 73], 1, 61)
	verify_thumb.call("Left thumb white triad", [48, 52, 55], 0, 55)
	verify_thumb.call("Left thumb black-key chord", [44, 49, 53, 56], 0, 56)
	verify_thumb.call("Left thumb black-top triad", [48, 51, 54], 0, 54)
	verify_thumb.call("Left thumb 2-note third", [54, 57], 0, 57)

	# Closing chord spanning across C4 (La Campanella finale)
	stage.release_all()
	for _f in range(10):
		stage._process(0.016)
	var closing_chord: Array[int] = [56, 60, 63, 68, 80, 84, 87, 92]
	for m: int in closing_chord:
		stage.press_key(m, Color.RED)
	for _f in range(30):
		stage._process(0.016)
	var lh_thumb: HandIKController.FingerChain = stage.hand_controllers[0]._chains[0]
	var rh_thumb: HandIKController.FingerChain = stage.hand_controllers[1]._chains[0]
	var lh_target: Vector3 = stage.key_map.get_strike_contact_point(68, stage._depth[68 - 21], true)
	var rh_target: Vector3 = stage.key_map.get_strike_contact_point(80, stage._depth[80 - 21], true)
	var lh_err: float = _thumb_tip_stage_pos(stage, 0).distance_to(lh_target)
	var rh_err: float = _thumb_tip_stage_pos(stage, 1).distance_to(rh_target)
	check(lh_thumb.last_midi == 68 and rh_thumb.last_midi == 80, "Wide closing chord rebalances across C4 so LH thumb hits 68 (got %d) and RH thumb hits 80 (got %d)" % [lh_thumb.last_midi, rh_thumb.last_midi])
	check(lh_err < 0.008 and rh_err < 0.008, "Both thumbs physically land on wide closing chord keys (LH=%.2fmm, RH=%.2fmm)" % [lh_err * 1000.0, rh_err * 1000.0])

	stage.release_all()
	for _f in range(35):
		stage._process(0.016)
	check(lh_thumb.last_state == FingeringSolver.FingerState.IDLE and rh_thumb.last_state == FingeringSolver.FingerState.IDLE and absf(lh_thumb.root_offset.x) < 0.002 and absf(rh_thumb.root_offset.x) < 0.002 and lh_thumb.root_offset.length() < 0.01 and rh_thumb.root_offset.length() < 0.01, "Thumbs return cleanly to IDLE dome after closing release")

	# Waltz liveness: single-note melody tracking, bass-chord stride, anticipation dome, and re-strike rebound
	stage.release_all()
	var mel_xs: Array[float] = []
	for m: int in [72, 76, 80, 84]:
		stage.release_all()
		stage.press_key(m, Color.CYAN)
		for _f in range(12):
			stage._process(0.016)
		mel_xs.append(stage._hands[1].position.x)
	check(mel_xs[3] > mel_xs[0] + 0.14 and mel_xs[2] > mel_xs[1] + 0.02, "Single-note melody moves RH wrist continuously without self-locking (%0.3f -> %0.3f)" % [mel_xs[0], mel_xs[3]])

	stage.release_all()
	stage.press_key(45, Color.CYAN)
	for _f in range(12):
		stage._process(0.016)
	var bass_x: float = stage._hands[0].position.x
	stage.release_all()
	for m: int in [48, 52, 55]:
		stage.press_key(m, Color.CYAN)
	for _f in range(12):
		stage._process(0.016)
	var triad_x: float = stage._hands[0].position.x
	check(triad_x > bass_x + 0.06, "Left-hand waltz bass -> triad stride moves LH wrist decisively (%0.3f -> %0.3f)" % [bass_x, triad_x])

	var struck_52: HandIKController.FingerChain = null
	for ch: HandIKController.FingerChain in stage.hand_controllers[0]._chains:
		if ch.last_midi == 52 and ch.last_state == FingeringSolver.FingerState.STRIKING:
			struck_52 = ch
			break
	check(struck_52 != null, "Left hand assigns a striking finger to MIDI 52 in [48, 52, 55]")

	var waltz_repeat: Array[PianoStage3D.StageNote] = [
		PianoStage3D.StageNote.new(48, 0.25, 0.20, Color.CYAN),
		PianoStage3D.StageNote.new(52, 0.25, 0.20, Color.CYAN),
		PianoStage3D.StageNote.new(55, 0.25, 0.20, Color.CYAN),
		PianoStage3D.StageNote.new(48, 0.50, 0.20, Color.CYAN),
		PianoStage3D.StageNote.new(52, 0.50, 0.20, Color.CYAN),
		PianoStage3D.StageNote.new(55, 0.50, 0.20, Color.CYAN)
	]
	stage.set_notes(waltz_repeat)
	stage.set_playback_time(0.40)
	stage.release_all()
	stage._process(0.016)
	check(struck_52 != null and struck_52.release_rebound > 0.5, "Releasing chord into anticipation of next beat still triggers release_rebound")
	for _f in range(5):
		stage._process(0.016)
	var ant_chain: HandIKController.FingerChain = null
	for fi: int in range(1, 5):
		var ch: HandIKController.FingerChain = stage.hand_controllers[0]._chains[fi]
		if ch.last_state == FingeringSolver.FingerState.ANTICIPATING:
			ant_chain = ch
			break
	var ant_curl_sum: float = (ant_chain.angles[1] + ant_chain.angles[2] + ant_chain.angles[3]) if ant_chain != null else 0.0
	check(ant_chain != null and ant_curl_sum < -40.0, "Anticipating fingers maintain natural curved dome (curl sum=%0.1f deg)" % ant_curl_sum)
	stage.set_playback_time(0.51)
	for m: int in [48, 52, 55]:
		stage.press_key(m, Color.CYAN)
	stage._process(0.016)
	var restruck_any: bool = false
	for ch: HandIKController.FingerChain in stage.hand_controllers[0]._chains:
		if ch.last_midi == 52 and ch.strike_impulse > 0.5:
			restruck_any = true
			break
	check(restruck_any and stage._note_cursor >= 3, "Re-striking repeated chord triggers strike_impulse and advances _note_cursor")
	var cleared_notes: Array[PianoStage3D.StageNote] = []
	stage.set_notes(cleared_notes)
	stage.release_all()
	for _f in range(25):
		stage._process(0.016)

	# Test Main scene integration
	var app = MainScene.instantiate()
	root.add_child(app)
	await process_frame
	app.size = Vector2(1920, 1080)
	app._layout()
	await process_frame

	check(app.stage_3d != null and app.stage_mode == "3d", "Main initializes 3D stage mode")
	check(app.stage_3d.visible and not app.visualizer.visible and not app.keyboard.draw_2d_keys, "Main shows 3D stage and hides 2D visuals")

	app._press_source("test_stage_sync", [60, 64])
	check(app.stage_3d._pressed[60 - 21] == 1 and app.stage_3d._pressed[64 - 21] == 1, "Main key presses propagate to 3D stage")
	app._release_source("test_stage_sync")
	check(app.stage_3d._pressed[60 - 21] == 0 and app.stage_3d._pressed[64 - 21] == 0, "Main key releases propagate to 3D stage")

	app.set_anime_hands_enabled(false)
	check(not app.stage_3d._hands[0].visible and not app.stage_3d._hands[1].visible, "Hands toggle hides 3D hands")
	app.set_anime_hands_enabled(true)
	check(app.stage_3d._hands[0].visible and app.stage_3d._hands[1].visible, "Hands toggle restores 3D hands")

	app.set_stage_mode("2d")
	check(app.stage_mode == "2d" and not app.stage_3d.visible and app.visualizer.visible and app.keyboard.draw_2d_keys, "Main switches to 2D mode")
	app.set_stage_mode("3d")
	check(app.stage_mode == "3d" and app.stage_3d.visible and not app.visualizer.visible and not app.keyboard.draw_2d_keys, "Main restores 3D mode")

	# Regression: monotonic clock on non-looping completion and cursor preservation on mid-song note rebuild
	app.set_bot_enabled(false)
	app.set_auto_loop_enabled(false)
	app.set_bot_bpm(120.0)
	app.steps.clear()
	app.steps.append({"notes": [60], "transposition": 0})
	app.steps.append({"notes": [62], "transposition": 0})
	app.steps.append({"notes": [64], "transposition": 0})
	app.step_delays.clear()
	app.step_delays.append(0.25)
	app.step_delays.append(0.25)
	app.step_delays.append(0.25)
	app.step_index = 0
	app._sync_stage_3d_notes()
	app.set_bot_enabled(true)
	var prev_clock: float = app._get_current_song_time()
	check(is_zero_approx(prev_clock), "Clock starts at 0.0 on step 0")
	app._process(0.26)
	var step1_clock: float = app._get_current_song_time()
	check(step1_clock > prev_clock and step1_clock >= 0.25, "Clock advances monotonically onto step 1")
	app._sync_stage_3d_notes()
	check(app.stage_3d._note_cursor >= 1 and is_equal_approx(app.stage_3d._playback_time, step1_clock), "Mid-playback rebuild preserves cursor and playback clock")
	app._process(0.26)
	var step2_clock: float = app._get_current_song_time()
	check(step2_clock > step1_clock and app._bot_finishing, "Clock advances monotonically through final step while _bot_finishing is active")
	app._process(0.26)
	var end_clock: float = app._get_current_song_time()
	check(not app.bot_enabled and end_clock >= 0.75 and end_clock >= step2_clock, "Clock stays at song end without rewinding after non-looping completion")

	# Regression: overlapping sources and song replacement clearing stale 3D presses
	app.transposition = 0
	app.user_transposition = 0
	app._press_source("hold-a", [60])
	app._press_source("hold-b", [60])
	app._release_source("hold-a")
	check(app.stage_3d._pressed[60 - 21] == 1, "Shared pitch remains pressed in 3D stage until final source releases")
	app._release_source("hold-b")
	check(app.stage_3d._pressed[60 - 21] == 0, "Shared pitch releases in 3D stage once all sources release")
	app._press_source("held-before-replace", [62])
	app.sheet_text_edit.text = "t u o"
	app.compiled_text = ""
	app._compile_sheet()
	check(app.stage_3d._pressed[62 - 21] == 0, "Recompiling/replacing sheet clears stale 3D pressed keys")

	# Regression: hands stay poised on last played key (X and black-key Z depth) until next active/imminent note
	stage.set_anticipation_enabled(false)
	var paused_sheet: Array[PianoStage3D.StageNote] = [
		PianoStage3D.StageNote.new(60, 0.05, 0.25, Color.CYAN),
		PianoStage3D.StageNote.new(64, 0.15, 0.25, Color.CYAN)
	]
	stage.set_notes(paused_sheet)
	stage.set_playback_time(0.0)
	stage.release_all()
	stage.press_key(97, Color.RED)
	for _f in range(25):
		stage._process(0.016)
	var rh_x_97: float = stage._hands[1].position.x
	var rh_z_97: float = stage._hands[1].position.z
	check(rh_x_97 > 0.35 and rh_z_97 < 0.155, "Right hand moves over high black key 97 (%0.3f, Z=%0.3f)" % [rh_x_97, rh_z_97])
	stage.release_all()
	for _f in range(30):
		stage._process(0.016)
	check(absf(stage._hands[1].position.x - rh_x_97) < 0.005 and absf(stage._hands[1].position.z - rh_z_97) < 0.005, "With anticipation disabled, releasing key 97 keeps hand poised over 97 instead of pulling to paused sheet")
	check(stage.hand_controllers[1]._chains[2].last_state == FingeringSolver.FingerState.IDLE, "Fingers release cleanly to IDLE dome while wrist remains on last key")

	stage.set_anticipation_enabled(true)
	var distant_sheet: Array[PianoStage3D.StageNote] = [
		PianoStage3D.StageNote.new(60, 0.40, 0.25, Color.CYAN)
	]
	stage.set_notes(distant_sheet)
	stage.set_playback_time(0.0)
	for _f in range(20):
		stage._process(0.016)
	check(absf(stage._hands[1].position.x - rh_x_97) < 0.005, "With anticipation enabled, hand stays over 97 when next note is > 0.28s away")
	var no_notes_after_hold: Array[PianoStage3D.StageNote] = []
	stage.set_notes(no_notes_after_hold)

	# Regression: Main keeps 3D anticipation disabled in startup/Auto modes and hands stay over released key
	check(not app.bot_enabled and not app.stage_3d._anticipation_enabled, "Main keeps 3D sheet anticipation disabled when Bot is off")
	app._popup_action("Auto")
	app._process(0.016)
	check(app.auto_enabled and not app.bot_enabled and not app.stage_3d._anticipation_enabled, "Auto mode keeps Bot off and 3D anticipation disabled")
	app._press_source("auto-hold-test", [97])
	for _f in range(25):
		app.stage_3d._process(0.016)
	var app_rh_x_97: float = app.stage_3d._hands[1].position.x
	app._release_source("auto-hold-test")
	for _f in range(25):
		app._process(0.016)
		app.stage_3d._process(0.016)
	check(app_rh_x_97 > 0.35 and absf(app.stage_3d._hands[1].position.x - app_rh_x_97) < 0.01, "In Auto mode with paused sheet at t=0, 3D hand stays over last played key 97")
	app.set_bot_enabled(true)
	check(app.bot_enabled and not app.auto_enabled and app.stage_3d._anticipation_enabled, "Activating Bot disables Auto and enables 3D anticipation")
	app.set_bot_enabled(false)

	# Regression: top-rail-only glow, hand-only OmniLights, downward hinged key animation, and physical albedo shading
	stage.release_all()
	for _f in range(70):
		stage._process(0.016)
	var w_idx: int = 60 - 21
	var b_idx: int = 61 - 21
	var w_rest_front_y: float = (stage._keys[w_idx].transform * Vector3(0.0, KeyMap3D.WHITE_HEIGHT * 0.5, KeyMap3D.WHITE_LENGTH * 0.5)).y
	var w_rest_back_y: float = (stage._keys[w_idx].transform * Vector3(0.0, KeyMap3D.WHITE_HEIGHT * 0.5, -KeyMap3D.WHITE_LENGTH * 0.5)).y
	var b_rest_front_y: float = (stage._keys[b_idx].transform * Vector3(0.0, KeyMap3D.BLACK_HEIGHT * 0.5, KeyMap3D.BLACK_LENGTH * 0.5)).y
	var b_rest_back_y: float = (stage._keys[b_idx].transform * Vector3(0.0, KeyMap3D.BLACK_HEIGHT * 0.5, -KeyMap3D.BLACK_LENGTH * 0.5)).y
	var w_rest_albedo: Color = stage._key_materials[w_idx].albedo_color
	var b_rest_albedo: Color = stage._key_materials[b_idx].albedo_color
	check(stage._hand_lights[0].light_cull_mask == 2 and stage._hand_lights[1].light_cull_mask == 2, "Hand OmniLight3D nodes isolate illumination to layer 2 hands only")
	stage.press_key(60, Color.CYAN)
	stage.press_key(61, Color.RED)
	for _f in range(12):
		stage._process(0.016)
	check(is_zero_approx(stage._key_materials[w_idx].emission_energy_multiplier) and is_zero_approx(stage._key_materials[b_idx].emission_energy_multiplier), "Pressed key bodies have zero neon emission")
	check(stage._rail_segments[w_idx].visible and stage._rail_halos[w_idx].visible and stage._rail_segments[b_idx].visible and stage._rail_halos[b_idx].visible, "Top rail glow segments and halos activate for pressed white and black keys")
	check(stage._rail_segments[w_idx].position.z <= -0.076 and stage._rail_halos[w_idx].position.z <= -0.076 and stage._rail_segments[b_idx].position.z <= -0.076 and stage._rail_halos[b_idx].position.z <= -0.076, "Rail glow emitters stay strictly on the bar above the keys")
	var w_pressed_front_y: float = (stage._keys[w_idx].transform * Vector3(0.0, KeyMap3D.WHITE_HEIGHT * 0.5, KeyMap3D.WHITE_LENGTH * 0.5)).y
	var w_pressed_back_y: float = (stage._keys[w_idx].transform * Vector3(0.0, KeyMap3D.WHITE_HEIGHT * 0.5, -KeyMap3D.WHITE_LENGTH * 0.5)).y
	var b_pressed_front_y: float = (stage._keys[b_idx].transform * Vector3(0.0, KeyMap3D.BLACK_HEIGHT * 0.5, KeyMap3D.BLACK_LENGTH * 0.5)).y
	var b_pressed_back_y: float = (stage._keys[b_idx].transform * Vector3(0.0, KeyMap3D.BLACK_HEIGHT * 0.5, -KeyMap3D.BLACK_LENGTH * 0.5)).y
	check(w_pressed_front_y < w_rest_front_y - 0.010 and w_pressed_back_y <= w_rest_back_y + 0.0005, "White key pivots downward around back hinge (>10mm front drop, back edge stays down)")
	check(b_pressed_front_y < b_rest_front_y - 0.010 and b_pressed_back_y <= b_rest_back_y + 0.0005, "Black key pivots downward around back hinge (>10mm front drop, back edge stays down)")
	check(stage._key_materials[w_idx].albedo_color.v < w_rest_albedo.v - 0.05 and stage._key_materials[b_idx].albedo_color.v > b_rest_albedo.v + 0.05, "Pressed keys show subtle physical albedo shift without glowing")
	var red_seg_col: Color = stage._rail_segment_materials[b_idx].albedo_color
	var red_halo_tint: Color = stage._rail_halo_materials[b_idx].get_shader_parameter("tint")
	check(red_seg_col.r >= 0.90 and red_seg_col.g <= 0.05 and red_seg_col.b <= 0.05 and red_halo_tint.r >= 0.90 and red_halo_tint.g <= 0.05 and red_halo_tint.b <= 0.05, "Red active rail segment and halo preserve vivid pure red without washing out (seg=%s halo=%s)" % [red_seg_col, red_halo_tint])
	stage.release_key(61)
	check(not stage._rail_segments[b_idx].visible and not stage._rail_halos[b_idx].visible and is_zero_approx(stage._energy[b_idx]) and is_zero_approx(stage._rail_pulse[b_idx]), "Releasing a single key extinguishes top rail glow immediately at 0 frames")
	check(stage._rail_segments[w_idx].visible and stage._rail_halos[w_idx].visible, "Other held keys keep top rail glow active when one key releases")
	stage.release_all()
	check(not stage._rail_segments[w_idx].visible and not stage._rail_halos[w_idx].visible and is_zero_approx(stage._energy[w_idx]) and is_zero_approx(stage._rail_pulse[w_idx]), "release_all extinguishes remaining top rail glow immediately at 0 frames")
	for _f in range(70):
		stage._process(0.016)
	check(not stage._rail_segments[w_idx].visible and not stage._rail_halos[w_idx].visible and not stage._rail_segments[b_idx].visible and not stage._rail_halos[b_idx].visible, "Top rail glow segments and halos hide cleanly after release decay")
	check(stage._key_materials[w_idx].albedo_color.is_equal_approx(Color("f4f1ea")) and stage._key_materials[b_idx].albedo_color.is_equal_approx(Color("171822")), "Released keys restore resting ivory and ebony albedos")
	app.set_stage_mode("3d")
	check(app.keyboard.key_glow_layer != null and not app.keyboard.key_glow_layer.visible, "2D key_glow_layer stays hidden in 3D mode")
	app.set_stage_mode("2d")
	check(app.keyboard.key_glow_layer != null and app.keyboard.key_glow_layer.visible, "2D key_glow_layer becomes visible in 2D mode")
	app.set_stage_mode("3d")

	# Regression: per-finger collision clearance on white key between black keys, white triad, and black chords
	stage.release_all()
	for _f in range(30):
		stage._process(0.016)
	stage.press_key(67, Color.CYAN)
	for _f in range(25):
		stage._process(0.016)
	var clr_white_67: float = _min_finger_clearance(stage, 1)
	check(clr_white_67 >= -0.0025, "Single white key G4 (67) clears adjacent black keys F#4/G#4 (clr=%.2fmm)" % [clr_white_67 * 1000.0])
	stage.release_all()
	for _f in range(15):
		stage._process(0.016)
	for m: int in [60, 64, 67]:
		stage.press_key(m, Color.CYAN)
	for _f in range(25):
		stage._process(0.016)
	var clr_white_triad: float = _min_finger_clearance(stage, 1)
	var anat_white_triad: Dictionary = _check_hand_anatomy(stage, 1)
	check(clr_white_triad >= -0.0025, "White triad [60, 64, 67] avoids finger/black-key clipping (clr=%.2fmm)" % [clr_white_triad * 1000.0])
	check(float(anat_white_triad["max_long_meta_disp"]) < 0.0005 and float(anat_white_triad["thumb_meta_disp"]) <= 0.025 and float(anat_white_triad["min_tip_gap"]) >= 0.013 and float(anat_white_triad["max_seg_err"]) < 0.001, "White triad [60, 64, 67] preserves anatomical hand shape (min_gap=%.1fmm, long_meta=%.2fmm)" % [float(anat_white_triad["min_tip_gap"]) * 1000.0, float(anat_white_triad["max_long_meta_disp"]) * 1000.0])
	stage.release_all()
	for _f in range(15):
		stage._process(0.016)
	for m: int in [61, 65, 68, 73, 44, 49, 53, 56]:
		stage.press_key(m, Color.RED if m >= 60 else Color.CYAN)
	for _f in range(25):
		stage._process(0.016)
	var clr_black_l: float = _min_finger_clearance(stage, 0)
	var clr_black_r: float = _min_finger_clearance(stage, 1)
	var anat_black_l: Dictionary = _check_hand_anatomy(stage, 0)
	var anat_black_r: Dictionary = _check_hand_anatomy(stage, 1)
	check(clr_black_l >= -0.0025 and clr_black_r >= -0.0025, "Black-key chords keep all fingers clear of unpressed black keys (L=%.2fmm, R=%.2fmm)" % [clr_black_l * 1000.0, clr_black_r * 1000.0])
	check(float(anat_black_l["max_long_meta_disp"]) < 0.0005 and float(anat_black_r["max_long_meta_disp"]) < 0.0005 and float(anat_black_l["min_tip_gap"]) >= 0.013 and float(anat_black_r["min_tip_gap"]) >= 0.013 and float(anat_black_l["thumb_meta_disp"]) <= 0.025 and float(anat_black_r["thumb_meta_disp"]) <= 0.025, "Black-key chords preserve anatomical integrity on both hands (L_gap=%.1fmm, R_gap=%.1fmm)" % [float(anat_black_l["min_tip_gap"]) * 1000.0, float(anat_black_r["min_tip_gap"]) * 1000.0])

	# Regression: wide octaves and mixed chords (Howl's Moving Castle [zd3]/[zutdO] shapes) never cross or dislocate fingers
	var wide_chords: Array = [
		{"label": "Wide octave [74, 86]", "midis": [74, 86]},
		{"label": "Wide octave triad [75, 79, 87]", "midis": [75, 79, 87]},
		{"label": "Dense mixed chord [74, 75, 77, 81, 86]", "midis": [74, 75, 77, 81, 86]}
	]
	for wc: Dictionary in wide_chords:
		stage.release_all()
		for _f in range(15):
			stage._process(0.016)
		for m: int in wc["midis"]:
			stage.press_key(m, Color.RED)
		for _f in range(25):
			stage._process(0.016)
		var wc_clr: float = _min_finger_clearance(stage, 1)
		var wc_anat: Dictionary = _check_hand_anatomy(stage, 1)
		check(wc_clr >= -0.0025, "%s clears keys cleanly (clr=%.2fmm)" % [str(wc["label"]), wc_clr * 1000.0])
		check(float(wc_anat["max_long_meta_disp"]) < 0.0005 and float(wc_anat["thumb_meta_disp"]) <= 0.025 and float(wc_anat["min_tip_gap"]) >= 0.013 and float(wc_anat["max_seg_err"]) < 0.001, "%s keeps cohesive anatomy without crossing or metacarpal dislocation (min_gap=%.1fmm, long_meta=%.2fmm, thumb_meta=%.1fmm)" % [str(wc["label"]), float(wc_anat["min_tip_gap"]) * 1000.0, float(wc_anat["max_long_meta_disp"]) * 1000.0, float(wc_anat["thumb_meta_disp"]) * 1000.0])

	# Regression (Opción 1): full multi-finger key reach on octaves, 9ths, and automatic two-hand 10th split
	var reach_cases: Array = [
		{"label": "LH octave D2-G2-D3 [38, 43, 50]", "side": 0, "midis": [38, 43, 50], "expected_count": 3, "max_x_err": 0.006},
		{"label": "LH octave D3-G3-D4 [50, 55, 62]", "side": 0, "midis": [50, 55, 62], "expected_count": 3, "max_x_err": 0.006},
		{"label": "RH 4-note octave [60, 64, 67, 72]", "side": 1, "midis": [60, 64, 67, 72], "expected_count": 4, "max_x_err": 0.006}
	]
	for rc: Dictionary in reach_cases:
		stage.release_all()
		for _f in range(15):
			stage._process(0.016)
		var rc_side: int = int(rc["side"])
		for m: int in rc["midis"]:
			stage.press_key(m, Color.RED if rc_side == 1 else Color.CYAN)
		for _f in range(25):
			stage._process(0.016)
		var rc_reach: Dictionary = _max_assigned_x_error(stage, rc_side)
		var rc_anat: Dictionary = _check_hand_anatomy(stage, rc_side)
		var rc_clr: float = _min_finger_clearance(stage, rc_side)
		check(int(rc_reach["count"]) == int(rc["expected_count"]) and float(rc_reach["max_err"]) < float(rc["max_x_err"]), "%s reaches all keys within %.1fmm (count=%d, max_x_err=%.2fmm)" % [str(rc["label"]), float(rc["max_x_err"]) * 1000.0, int(rc_reach["count"]), float(rc_reach["max_err"]) * 1000.0])
		check(float(rc_anat["max_long_meta_disp"]) < 0.0005 and float(rc_anat["min_tip_gap"]) >= 0.013 and float(rc_anat["max_seg_err"]) < 0.001 and rc_clr >= -0.0025, "%s keeps clean anatomy and key clearance (min_gap=%.1fmm, clr=%.2fmm)" % [str(rc["label"]), float(rc_anat["min_tip_gap"]) * 1000.0, rc_clr * 1000.0])

	# Left-hand 9th [48, 55, 62] while RH is occupied on [72, 76]
	stage.release_all()
	for _f in range(15):
		stage._process(0.016)
	for m: int in [48, 55, 62, 72, 76]:
		stage.press_key(m, Color.RED if m >= 72 else Color.CYAN)
	for _f in range(25):
		stage._process(0.016)
	var ninth_l: Dictionary = _max_assigned_x_error(stage, 0)
	var ninth_anat_l: Dictionary = _check_hand_anatomy(stage, 0)
	var ninth_clr_l: float = _min_finger_clearance(stage, 0)
	check(int(ninth_l["count"]) == 3 and float(ninth_l["max_err"]) < 0.012, "LH 9th [48, 55, 62] with busy RH covers all 3 notes within 12mm (count=%d, max_x_err=%.2fmm)" % [int(ninth_l["count"]), float(ninth_l["max_err"]) * 1000.0])
	check(float(ninth_anat_l["max_long_meta_disp"]) < 0.0005 and float(ninth_anat_l["min_tip_gap"]) >= 0.013 and float(ninth_anat_l["max_seg_err"]) < 0.001 and ninth_clr_l >= -0.0025, "LH 9th preserves hand anatomy and clearance (min_gap=%.1fmm, clr=%.2fmm)" % [float(ninth_anat_l["min_tip_gap"]) * 1000.0, ninth_clr_l * 1000.0])

	# Automatic two-hand handoff on a 10th [48, 55, 64] when RH is idle
	stage.release_all()
	for _f in range(15):
		stage._process(0.016)
	for m: int in [48, 55, 64]:
		stage.press_key(m, Color.CYAN)
	for _f in range(25):
		stage._process(0.016)
	var tenth_l: Dictionary = _max_assigned_x_error(stage, 0)
	var tenth_r: Dictionary = _max_assigned_x_error(stage, 1)
	check(int(tenth_l["count"]) >= 1 and int(tenth_r["count"]) >= 1 and int(tenth_l["count"]) + int(tenth_r["count"]) == 3 and float(tenth_l["max_err"]) < 0.006 and float(tenth_r["max_err"]) < 0.006, "10th [48, 55, 64] splits automatically across both hands within 6mm (L=%d/%.2fmm, R=%d/%.2fmm)" % [int(tenth_l["count"]), float(tenth_l["max_err"]) * 1000.0, int(tenth_r["count"]), float(tenth_r["max_err"]) * 1000.0])
	stage.release_all()

	# Regression: perspective pill cascade, white-bordered note names, strike rail clip, and rising live cascade in Normal/Auto modes
	check(PianoStage3DClass.musical_note_name(71) == "B" and PianoStage3DClass.musical_note_name(74) == "D" and PianoStage3DClass.musical_note_name(61) == "C#", "Musical note names resolve natural and sharp pitches without octave numbers")
	check(PianoStage3DClass.musical_note_name(20).is_empty() and PianoStage3DClass.musical_note_name(109).is_empty(), "Musical note names reject out-of-range pitches")
	check(stage._overlay_clip != null and stage._overlay_clip.clip_contents and stage._overlay_clip.size.y > 0.0 and stage._overlay_clip.size.y < p_mid.y, "Cascade overlay clips cleanly strictly above 3D keys (clip_h=%.1f, key_mid_y=%.1f)" % [stage._overlay_clip.size.y if stage._overlay_clip != null else -1.0, p_mid.y])

	var loaded_sheet: Array[PianoStage3D.StageNote] = [
		PianoStage3D.StageNote.new(71, 0.2, 0.4, Color.RED),
		PianoStage3D.StageNote.new(74, 0.4, 0.4, Color.RED)
	]
	stage.set_notes(loaded_sheet)
	stage.set_playback_time(0.0)
	stage.set_live_cascade_enabled(true)
	for _f in range(5):
		stage._process(0.016)
	check(stage.get_visible_pills().is_empty(), "Live cascade mode hides frozen sheet notes when no keys are struck")

	stage.press_key(71, Color.RED, 101)
	stage.press_key(74, Color.RED, 102)
	var held_pills_0: Array[Dictionary] = stage.get_visible_pills()
	check(held_pills_0.size() == 2, "Pressing B4 (71) and D5 (74) creates 2 live pills")
	var found_b_0: Dictionary = {}
	var found_d_0: Dictionary = {}
	for p: Dictionary in held_pills_0:
		if int(p["midi"]) == 71:
			found_b_0 = p
		elif int(p["midi"]) == 74:
			found_d_0 = p
	check(str(found_b_0.get("label", "")) == "B" and str(found_d_0.get("label", "")) == "D", "Live pills carry exact note labels B and D")
	check(is_zero_approx(float(found_b_0.get("dist_near", -1.0))) and is_zero_approx(float(found_d_0.get("dist_near", -1.0))), "Newly held live pills anchor at dist_near == 0.0")
	var len_b_before: float = float(found_b_0.get("dist_far", 0.0)) - float(found_b_0.get("dist_near", 0.0))
	for _f in range(12):
		stage._process(0.016)
	var held_pills_1: Array[Dictionary] = stage.get_visible_pills()
	var len_b_after: float = 0.0
	for p: Dictionary in held_pills_1:
		if int(p["midi"]) == 71:
			len_b_after = float(p["dist_far"]) - float(p["dist_near"])
	check(len_b_after > len_b_before + 0.01, "Held live pill elongates smoothly over time (%.4f -> %.4f)" % [len_b_before, len_b_after])

	stage.release_key(71)
	stage.release_key(74)
	stage._process(0.016)
	var rise_1: Array[Dictionary] = stage.get_visible_pills()
	var d_b_1: float = -1.0
	for p: Dictionary in rise_1:
		if int(p["midi"]) == 71:
			d_b_1 = float(p["dist_near"])
	for _f in range(10):
		stage._process(0.016)
	var rise_2: Array[Dictionary] = stage.get_visible_pills()
	var d_b_2: float = -1.0
	for p: Dictionary in rise_2:
		if int(p["midi"]) == 71:
			d_b_2 = float(p["dist_near"])
	check(d_b_1 > 0.0 and d_b_2 > d_b_1 + 0.02, "Released live pills detach and climb upward monotonically (%.4f -> %.4f)" % [d_b_1, d_b_2])

	for _f in range(380):
		stage._process(0.016)
	check(stage.get_visible_pills().is_empty(), "Live pills prune cleanly once they travel above cascade span")

	stage.press_key(71, Color.RED, 201)
	for _f in range(5):
		stage._process(0.016)
	stage.press_key(71, Color.RED, 202)
	stage._process(0.016)
	var retrigger_pills: Array[Dictionary] = stage.get_visible_pills()
	var retrigger_b_count: int = 0
	var has_rising_b: bool = false
	var has_anchored_b: bool = false
	for p: Dictionary in retrigger_pills:
		if int(p["midi"]) == 71 and str(p["label"]) == "B":
			retrigger_b_count += 1
			if float(p["dist_near"]) > 0.0:
				has_rising_b = true
			else:
				has_anchored_b = true
	check(retrigger_b_count == 2 and has_rising_b and has_anchored_b, "Rapid retrigger on same pitch spawns distinct climbing and anchored B pills")
	stage.release_all()
	for _f in range(10):
		stage._process(0.016)
	stage._live_notes.clear()
	stage.set_live_cascade_enabled(false)

	# Main integration: Normal mode, Auto mode, and Bot mode cascade behavior
	app.set_bot_enabled(false)
	app.auto_enabled = false
	app.stage_3d._live_notes.clear()
	app.set_stage_mode("3d")
	app.transposition = 0
	app.user_transposition = 0
	app.steps.clear()
	app.steps.append({"notes": [71, 74], "transposition": 0})
	app.steps.append({"notes": [72, 76], "transposition": 0})
	app.step_delays.clear()
	app.step_delays.append(0.35)
	app.step_delays.append(0.35)
	app.step_index = 0
	app._sync_stage_3d_notes()
	app._process(0.016)
	app.stage_3d._process(0.016)
	check(app.stage_3d._live_cascade_enabled and app.stage_3d.get_visible_pills().is_empty(), "Main Normal mode enables live rising cascade and hides frozen sheet bars")
	app._press_source("normal-pills", [71, 74])
	var normal_pills: Array[Dictionary] = app.stage_3d.get_visible_pills()
	var normal_labels: PackedStringArray = PackedStringArray()
	for p: Dictionary in normal_pills:
		normal_labels.append(str(p["label"]))
	check(normal_pills.size() == 2 and "B" in normal_labels and "D" in normal_labels, "Main Normal mode key press spawns B and D pills")
	app._release_source("normal-pills")
	app.stage_3d._process(0.016)
	var normal_released_pills: Array[Dictionary] = app.stage_3d.get_visible_pills()
	check(normal_released_pills.size() == 2 and float(normal_released_pills[0]["dist_near"]) > 0.0 and float(normal_released_pills[1]["dist_near"]) > 0.0, "Releasing Normal mode source detaches rising pills to travel upward")

	app.stage_3d._live_notes.clear()
	app._popup_action("Auto")
	app._process(0.016)
	app.stage_3d._process(0.016)
	check(app.auto_enabled and not app.bot_enabled and app.stage_3d._live_cascade_enabled, "Auto mode keeps 3D live pill cascade active without Bot")
	check(app.stage_3d.get_visible_pills().is_empty(), "Auto mode starts with clean stage without frozen sheet bars")
	var auto_press_ev: InputEventKey = InputEventKey.new()
	auto_press_ev.keycode = KEY_F
	auto_press_ev.physical_keycode = KEY_F
	auto_press_ev.pressed = true
	app._input(auto_press_ev)
	var auto_pills: Array[Dictionary] = app.stage_3d.get_visible_pills()
	var auto_labels: PackedStringArray = PackedStringArray()
	for p: Dictionary in auto_pills:
		auto_labels.append(str(p["label"]))
	check(auto_pills.size() == 2 and "B" in auto_labels and "D" in auto_labels, "Auto mode step input spawns rising pills with musical labels B and D")
	var auto_release_ev: InputEventKey = InputEventKey.new()
	auto_release_ev.keycode = KEY_F
	auto_release_ev.physical_keycode = KEY_F
	auto_release_ev.pressed = false
	app._input(auto_release_ev)

	app.step_index = 0
	app.set_bot_enabled(true)
	check(app.bot_enabled and not app.stage_3d._live_cascade_enabled, "Bot mode switches 3D cascade to falling sheet mode")
	var bot_pills: Array[Dictionary] = app.stage_3d.get_visible_pills()
	check(not bot_pills.is_empty() and str(bot_pills[0]["label"]) in ["B", "D"], "Bot mode falling pills carry musical note labels")
	app.set_bot_enabled(false)
	check(app.stage_3d._live_cascade_enabled and app.stage_3d._live_notes.is_empty(), "Disabling Bot restores live cascade mode with cleared live pills")

	# Regression: full-key occlusion shade overlay, stronger physical depression, and zero key neon emission
	stage.release_all()
	for _f in range(70):
		stage._process(0.016)
	check(stage._key_shades.size() == 88 and stage._key_shade_materials.size() == 88, "Builds 88 KeyShade overlays matched 1:1 with 3D keys")
	var shade_w_idx: int = 60 - 21
	var shade_b_idx: int = 61 - 21
	check(stage._key_shades[shade_w_idx].get_parent() == stage._keys[shade_w_idx] and not stage._key_shades[shade_w_idx].visible and not stage._key_shades[shade_b_idx].visible, "KeyShade overlays parent to each key and stay hidden at rest")
	var w_rest_front_2: float = (stage._keys[shade_w_idx].transform * Vector3(0.0, KeyMap3D.WHITE_HEIGHT * 0.5, KeyMap3D.WHITE_LENGTH * 0.5)).y
	var b_rest_front_2: float = (stage._keys[shade_b_idx].transform * Vector3(0.0, KeyMap3D.BLACK_HEIGHT * 0.5, KeyMap3D.BLACK_LENGTH * 0.5)).y
	var w_rest_alb_2: Color = stage._key_materials[shade_w_idx].albedo_color
	stage.press_key(60, Color.RED)
	stage.press_key(61, Color.CYAN)
	for _f in range(15):
		stage._process(0.016)
	var w_press_shader: float = float(stage._key_shade_materials[shade_w_idx].get_shader_parameter("press"))
	var b_press_shader: float = float(stage._key_shade_materials[shade_b_idx].get_shader_parameter("press"))
	var w_down_front_2: float = (stage._keys[shade_w_idx].transform * Vector3(0.0, KeyMap3D.WHITE_HEIGHT * 0.5, KeyMap3D.WHITE_LENGTH * 0.5)).y
	var b_down_front_2: float = (stage._keys[shade_b_idx].transform * Vector3(0.0, KeyMap3D.BLACK_HEIGHT * 0.5, KeyMap3D.BLACK_LENGTH * 0.5)).y
	check(stage._key_shades[shade_w_idx].visible and stage._key_shades[shade_b_idx].visible and w_press_shader > 0.5 and b_press_shader > 0.5, "Pressed white and black keys activate full-key KeyShade overlays (press=%.2f/%.2f)" % [w_press_shader, b_press_shader])
	check(stage._key_materials[shade_w_idx].albedo_color.v < w_rest_alb_2.v - 0.15 and is_zero_approx(stage._key_materials[shade_w_idx].emission_energy_multiplier) and is_zero_approx(stage._key_materials[shade_b_idx].emission_energy_multiplier), "Pressed white key darkens strongly with zero neon body emission")
	check(w_rest_front_2 - w_down_front_2 > 0.014 and b_rest_front_2 - b_down_front_2 > 0.012, "Deepened physical depression drops key front cleanly (W=%.1fmm, B=%.1fmm)" % [(w_rest_front_2 - w_down_front_2) * 1000.0, (b_rest_front_2 - b_down_front_2) * 1000.0])
	stage.release_all()
	for _f in range(70):
		stage._process(0.016)
	check(not stage._key_shades[shade_w_idx].visible and not stage._key_shades[shade_b_idx].visible, "KeyShade overlays hide cleanly after full key release")

	# Regression: Auto cascade toggle between 'Desde abajo' ('rising') and 'En cascada' ('falling')
	app.set_bot_enabled(false)
	app.auto_enabled = false
	app.set_auto_cascade_mode("rising")
	app.set_stage_mode("3d")
	app.steps.clear()
	app.steps.append({"notes": [71, 74], "transposition": 0})
	app.steps.append({"notes": [72, 76], "transposition": 0})
	app.steps.append({"notes": [74, 79], "transposition": 0})
	app.step_delays.clear()
	app.step_delays.append(0.35)
	app.step_delays.append(0.35)
	app.step_delays.append(0.35)
	app.step_index = 0
	app._sync_stage_3d_notes()
	check(app.auto_cascade_mode == "rising" and app.menu.current_auto_cascade_mode == "rising", "Default Auto cascade mode starts in 'rising' (Desde abajo)")
	check(app.menu.sheet_auto_cascade_btn != null and "Desde abajo" in app.menu.sheet_auto_cascade_btn.text, "Sheet toolbar toggle reflects 'Desde abajo'")

	app._popup_action("Auto")
	app._process(0.016)
	check(app.auto_enabled and app.stage_3d._live_cascade_enabled and not app.stage_3d._smooth_cascade_clock, "Auto in 'rising' keeps live rising cascade enabled")

	var ctrl_n_ev: InputEventKey = InputEventKey.new()
	ctrl_n_ev.keycode = KEY_N
	ctrl_n_ev.physical_keycode = KEY_N
	ctrl_n_ev.ctrl_pressed = true
	ctrl_n_ev.pressed = true
	app._input(ctrl_n_ev)
	check(app.auto_cascade_mode == "falling" and app.menu.current_auto_cascade_mode == "falling", "Ctrl+N toggles Auto cascade mode to 'falling' (En cascada)")
	check(app.menu.sheet_auto_cascade_btn != null and "En cascada" in app.menu.sheet_auto_cascade_btn.text, "Sheet toolbar toggle updates text to 'En cascada'")
	check(not app.stage_3d._live_cascade_enabled and app.stage_3d._smooth_cascade_clock and not app.stage_3d._anticipation_enabled, "Auto in 'falling' enables smooth falling cascade without Bot anticipation")
	var auto_falling_pills: Array[Dictionary] = app.stage_3d.get_visible_pills()
	check(not auto_falling_pills.is_empty() and str(auto_falling_pills[0]["label"]) in ["B", "D"], "Auto in 'falling' renders waiting sheet pills from top cascade")

	var vis_t0: float = app.stage_3d._visual_playback_time
	var step_ev_down: InputEventKey = InputEventKey.new()
	step_ev_down.keycode = KEY_F
	step_ev_down.physical_keycode = KEY_F
	step_ev_down.pressed = true
	app._input(step_ev_down)
	check(app.step_index == 1 and app.stage_3d._playback_time > vis_t0 + 0.25, "Stepping in Auto updates target cascade clock immediately")
	app.stage_3d._process(0.016)
	var vis_t1: float = app.stage_3d._visual_playback_time
	check(vis_t1 > vis_t0 and vis_t1 < app.stage_3d._playback_time, "Smooth cascade clock glides visual time progressively between Auto taps (%.4f -> %.4f -> %.4f)" % [vis_t0, vis_t1, app.stage_3d._playback_time])
	var step_ev_up: InputEventKey = InputEventKey.new()
	step_ev_up.keycode = KEY_F
	step_ev_up.physical_keycode = KEY_F
	step_ev_up.pressed = false
	app._input(step_ev_up)

	# Leaving Auto while in 'falling' still renders Normal mode from bottom without frozen sheet bars
	app._popup_action("Auto")
	app._process(0.016)
	check(not app.auto_enabled and app.stage_3d._live_cascade_enabled and not app.stage_3d._smooth_cascade_clock, "Normal mode stays on rising live cascade even when Auto preference is 'falling'")

	# Persistence roundtrip for auto_cascade_mode
	var tmp_cfg: String = "user://test_auto_cascade_settings.cfg"
	app._loading_settings = false
	app.set_auto_cascade_mode("falling")
	app.save_user_settings(tmp_cfg)
	app.set_auto_cascade_mode("rising")
	var loaded_ok: bool = app.load_user_settings(tmp_cfg)
	check(loaded_ok and app.auto_cascade_mode == "falling" and app.menu.current_auto_cascade_mode == "falling", "User settings persist and restore auto_cascade_mode across sessions")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_cfg))

	# Regression (Joint Tracking): exact finger-to-key alignment across screenshot chord and interval/5-finger sweep
	var empty_trk: Array[PianoStage3D.StageNote] = []
	stage.set_notes(empty_trk)
	stage.set_anticipation_enabled(false)
	stage.release_all()
	for _f in range(25):
		stage._process(0.016)
	for m: int in [52, 57, 65, 69]:
		stage.press_key(m, Color.RED)
	for _f in range(30):
		stage._process(0.016)
	var sc_reach_l: Dictionary = _max_assigned_x_error(stage, 0)
	var sc_reach_r: Dictionary = _max_assigned_x_error(stage, 1)
	var sc_anat_l: Dictionary = _check_hand_anatomy(stage, 0)
	var sc_anat_r: Dictionary = _check_hand_anatomy(stage, 1)
	var sc_clr_l: float = _min_finger_clearance(stage, 0)
	var sc_clr_r: float = _min_finger_clearance(stage, 1)
	var sc_lh_thumb_z: float = _thumb_tip_stage_pos(stage, 0).z
	var sc_rh_thumb_z: float = _thumb_tip_stage_pos(stage, 1).z
	check(int(sc_reach_l["count"]) == 2 and int(sc_reach_r["count"]) == 2 and float(sc_reach_l["max_err"]) < 0.0045 and float(sc_reach_r["max_err"]) < 0.0045, "Screenshot chord [52,57,65,69] aligns all 4 fingers within 4.5mm (L=%.2fmm, R=%.2fmm)" % [float(sc_reach_l["max_err"]) * 1000.0, float(sc_reach_r["max_err"]) * 1000.0])
	check(sc_lh_thumb_z <= 0.068 and sc_rh_thumb_z <= 0.068, "Both thumbs rest solidly inside white keys (LH z=%.1fmm, RH z=%.1fmm)" % [sc_lh_thumb_z * 1000.0, sc_rh_thumb_z * 1000.0])
	check(float(sc_anat_l["max_long_meta_disp"]) < 0.0005 and float(sc_anat_r["max_long_meta_disp"]) < 0.0005 and float(sc_anat_l["min_tip_gap"]) >= 0.013 and float(sc_anat_r["min_tip_gap"]) >= 0.013 and sc_clr_l >= -0.0025 and sc_clr_r >= -0.0025, "Screenshot chord preserves anatomy and key clearance (gaps=%.1f/%.1fmm, clrs=%.2f/%.2fmm)" % [float(sc_anat_l["min_tip_gap"]) * 1000.0, float(sc_anat_r["min_tip_gap"]) * 1000.0, sc_clr_l * 1000.0, sc_clr_r * 1000.0])

	var tracking_sweep: Array = [
		{"label": "Single E1 (28)", "side": 0, "midis": [28]},
		{"label": "Single A2 (45)", "side": 0, "midis": [45]},
		{"label": "Single C4 (60)", "side": 1, "midis": [60]},
		{"label": "Single E5 (76)", "side": 1, "midis": [76]},
		{"label": "Single A7 (105)", "side": 1, "midis": [105]},
		{"label": "RH m2 [60,61]", "side": 1, "midis": [60, 61]},
		{"label": "RH M2 [60,62]", "side": 1, "midis": [60, 62]},
		{"label": "RH m3 [60,63]", "side": 1, "midis": [60, 63]},
		{"label": "RH M3 [60,64]", "side": 1, "midis": [60, 64]},
		{"label": "RH P4 [60,65]", "side": 1, "midis": [60, 65]},
		{"label": "RH P5 [60,67]", "side": 1, "midis": [60, 67]},
		{"label": "RH M6 [60,69]", "side": 1, "midis": [60, 69]},
		{"label": "RH triad [60,64,67]", "side": 1, "midis": [60, 64, 67]},
		{"label": "RH cluster [60,62,64]", "side": 1, "midis": [60, 62, 64]},
		{"label": "RH 5-finger [60,62,64,65,67]", "side": 1, "midis": [60, 62, 64, 65, 67]},
		{"label": "LH M3 [53,57]", "side": 0, "midis": [53, 57]},
		{"label": "LH P4 [52,57]", "side": 0, "midis": [52, 57]},
		{"label": "LH P5 [48,55]", "side": 0, "midis": [48, 55]}
	]
	for item: Dictionary in tracking_sweep:
		stage.release_all()
		for _f in range(18):
			stage._process(0.016)
		var sw_side: int = int(item["side"])
		var sw_midis: Array = item["midis"]
		for m: int in sw_midis:
			stage.press_key(m, Color.RED if sw_side == 1 else Color.CYAN)
		for _f in range(30):
			stage._process(0.016)
		var sw_reach: Dictionary = _max_assigned_x_error(stage, sw_side)
		var sw_anat: Dictionary = _check_hand_anatomy(stage, sw_side)
		var sw_clr: float = _min_finger_clearance(stage, sw_side)
		check(int(sw_reach["count"]) == sw_midis.size() and float(sw_reach["max_err"]) < 0.0055, "%s aligns all %d fingers within 5.5mm (count=%d, max_err=%.2fmm)" % [str(item["label"]), sw_midis.size(), int(sw_reach["count"]), float(sw_reach["max_err"]) * 1000.0])
		check(float(sw_anat["max_long_meta_disp"]) < 0.0005 and float(sw_anat["min_tip_gap"]) >= 0.013 and float(sw_anat["max_seg_err"]) < 0.001 and sw_clr >= -0.0025, "%s keeps cohesive anatomy and key clearance (gap=%.1fmm, clr=%.2fmm)" % [str(item["label"]), float(sw_anat["min_tip_gap"]) * 1000.0, sw_clr * 1000.0])
	stage.release_all()

	stage.queue_free()
	app.queue_free()
	await process_frame
	
	print("STAGE 3D CHECKS: %d; FAILURES: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)
