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
	check(r_plan.active_count == 1 and r_plan.anticipating_count == 2, "FingeringSolver assigns active notes and upcoming notes within 0.16s window")
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

	stage.queue_free()
	app.queue_free()
	await process_frame
	
	print("STAGE 3D CHECKS: %d; FAILURES: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)
