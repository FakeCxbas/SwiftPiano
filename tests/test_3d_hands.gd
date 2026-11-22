# SwiftPiano - 3D Rigged Hands Test Suite
# Copyright (c) 2026 Sebastián Zambrano
# Distributed under the terms of the MIT License.

extends SceneTree
const Main = preload("res://scenes/main.tscn")

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
	print("--- Running 3D Rigged Hands Tests ---")
	root.size = Vector2i(1920, 1080)
	var app = Main.instantiate()
	root.add_child(app)
	await process_frame
	app.size = Vector2(1920, 1080)
	app._layout()
	await process_frame
	
	var keyboard = app.keyboard
	check(keyboard != null, "Keyboard exists")
	check(keyboard.hands_mode == "3d", "Default hands_mode is 3d")
	check(keyboard.hands_3d_container != null, "3D hands container initialized")
	check(keyboard.hands_3d_viewport != null, "3D hands viewport initialized")
	check(keyboard.hands_3d_camera != null, "3D hands camera initialized")
	check(keyboard.left_hand_3d != null, "Left 3D hand instantiated")
	check(keyboard.right_hand_3d != null, "Right 3D hand instantiated")
	check(keyboard.left_hand_skel != null, "Left skeleton found")
	check(keyboard.right_hand_skel != null, "Right skeleton found")
	
	check(keyboard.left_hand_skel.get_bone_count() == 25, "Left hand has 25 bones")
	check(keyboard.right_hand_skel.get_bone_count() == 25, "Right hand has 25 bones")
	check(keyboard.left_finger_bones.size() == 5, "Left hand has 5 finger bone mappings")
	check(keyboard.right_finger_bones.size() == 5, "Right hand has 5 finger bone mappings")
	
	# Visibility checks
	check(keyboard.hands_3d_container.visible == true, "3D hands visible in 3d mode")
	check(keyboard.left_hand_mesh_node.visible == false, "2D mesh hidden in 3d mode")
	
	keyboard.hands_mode = "2d"
	check(keyboard.hands_3d_container.visible == false, "3D hands hidden in 2d mode")
	check(keyboard.left_hand_mesh_node.visible == true, "2D mesh visible in 2d mode")
	
	keyboard.anime_hands_enabled = false
	check(keyboard.hands_3d_container.visible == false, "3D hands hidden when anime_hands_enabled=false")
	check(keyboard.left_hand_mesh_node.visible == false, "2D mesh hidden when anime_hands_enabled=false")
	
	keyboard.anime_hands_enabled = true
	keyboard.hands_mode = "3d"
	check(keyboard.hands_3d_container.visible == true, "3D hands restored")
	
	# Trigger chord press on left and right hands
	app._press_source("test_3d", [48, 52, 60, 67, 72])
	keyboard._process(0.016)
	
	check(keyboard.left_hand_target_x > 0.0, "Left hand target calculated")
	check(keyboard.right_hand_target_x > 0.0, "Right hand target calculated")
	
	# Verify bone rotations applied without error
	var test_bone_idx = keyboard.left_finger_bones[3][0] # Index proximal
	var pose_rot = keyboard.left_hand_skel.get_bone_pose_rotation(test_bone_idx)
	check(pose_rot != Quaternion.IDENTITY, "Bone pose rotation applied on key press")
	
	app._release_source("test_3d")
	keyboard._process(0.5)
	
	print("3D HANDS CHECKS: %d; FAILURES: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)
