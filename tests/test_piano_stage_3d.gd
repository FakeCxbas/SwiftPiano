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
	stage.release_all()
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
	stage.release_all()

	stage.queue_free()
	app.queue_free()
	await process_frame
	
	print("STAGE 3D CHECKS: %d; FAILURES: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)
