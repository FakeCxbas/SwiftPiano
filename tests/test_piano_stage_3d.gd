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
