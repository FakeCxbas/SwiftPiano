extends SceneTree

const Visualizer = preload("res://scripts/synth_visualizer.gd")

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func near(a: float, b: float, tolerance: float = 0.01) -> bool:
	return absf(a - b) <= tolerance

func run() -> void:
	var visualizer = Visualizer.new()
	visualizer.size = Vector2(1760.0, 880.0)
	var keys: Dictionary = {}
	for midi: int in range(21, 109):
		var left: float = float(midi - 21) * 20.0
		keys[midi] = Rect2(left, 820.0, 20.0, 60.0)
	visualizer.key_rects = keys

	# Every one of the 88 note lanes must converge to its matching key at impact.
	for midi: int in range(21, 109):
		var key: Rect2 = keys[midi]
		var contact: Vector2 = visualizer.project_point(Vector2(key.position.x, visualizer.size.y))
		var projected_edges: Vector2 = visualizer.projected_key_edges(midi, visualizer.size.y)
		check(near(contact.x, key.position.x) and near(contact.y, visualizer.size.y), "Impact point remains on MIDI %d key" % midi)
		check(near(projected_edges.x, key.position.x) and near(projected_edges.y, key.end.x), "Impact edges align with MIDI %d key" % midi)

	# The horizon narrows the full keyboard by the configured 0.72 ratio.
	var horizon_left: Vector2 = visualizer.projected_key_edges(21, 0.0)
	var horizon_right: Vector2 = visualizer.projected_key_edges(108, 0.0)
	var horizon_width: float = horizon_right.y - horizon_left.x
	check(near(horizon_width / 1760.0, 0.72, 0.001), "Horizon width uses 0.72 taper")
	check(visualizer.project_point(Vector2(100.0, 0.0)).y < visualizer.size.y, "Horizon sits above keyboard impact plane")
	check(Visualizer.musical_note_name(21) == "A" and Visualizer.musical_note_name(108) == "C", "MIDI labels cover piano endpoints without octave numbers")
	check(Visualizer.musical_note_name(20).is_empty() and Visualizer.musical_note_name(109).is_empty(), "MIDI labels reject out-of-range pitches")

	# Playback index means the next step. Durations should order notes into a
	# forward cascade, with elapsed playback progress moving the next note down.
	visualizer.set_playback_timing([0.5, 0.5, 0.5], 0.5)
	var steps: Array = [
		{"notes": [60]},
		{"notes": [64]},
		{"notes": [67]},
	]
	visualizer.set_playback_context(steps, 1, 0.0, 120.0, true)
	var upcoming: Array[Dictionary] = visualizer.upcoming_notes()
	check(upcoming.size() == 2, "Upcoming notes start at the next playback index")
	if upcoming.size() >= 2:
		var first: Dictionary = upcoming[0]
		var second: Dictionary = upcoming[1]
		check(int(first.midi) == 64 and int(second.midi) == 67, "Current index points to next step")
		check(first.rect.position.y > second.rect.position.y, "Later notes appear farther up the cascade")
		visualizer.set_playback_context(steps, 1, 0.5, 120.0, true)
		var advanced: Array[Dictionary] = visualizer.upcoming_notes()
		check(advanced.size() == 2 and float(advanced[0].rect.position.y) > float(first.rect.position.y), "Playback progress advances notes toward impact")

	# Transposition, missing lanes, malformed/empty steps and disabled playback.
	visualizer.set_playback_timing([0.5], 0.5, 2)
	visualizer.set_playback_context([{"notes": [60], "transposition": 1}, {"notes": [120, "bad"]}], 0, 0.0, 120.0, true)
	upcoming = visualizer.upcoming_notes()
	check(upcoming.size() == 1 and int(upcoming[0].midi) == 63, "User and step transposition apply; invalid pitches are skipped")
	visualizer.set_playback_timing([0.5], 0.5, 0)
	visualizer.set_playback_context([{"notes": [60, 120, "bad"]}], 0, 0.0, 120.0, true)
	upcoming = visualizer.upcoming_notes()
	check(upcoming.size() == 1 and int(upcoming[0].midi) == 60 and bool(upcoming[0].melody), "Invalid pitches do not hide the highest valid melody note")
	visualizer.set_playback_timing([0.5], 0.5, 0)
	visualizer.set_playback_context([{"notes": [20, 70], "transposition": 40}], 0, 0.0, 120.0, true)
	upcoming = visualizer.upcoming_notes()
	check(upcoming.size() == 1 and int(upcoming[0].midi) == 60 and bool(upcoming[0].melody), "Out-of-range transposed pitches do not hide the highest valid melody note")
	visualizer.set_playback_context([], 0, 0.0, 120.0, true)
	check(visualizer.upcoming_notes().is_empty(), "Empty playback has no upcoming notes")
	visualizer.set_playback_context(steps, 0, 0.0, 120.0, false)
	check(visualizer.upcoming_notes().is_empty(), "Inactive playback has no upcoming notes")
	visualizer.size.y = 0.0
	visualizer.set_playback_context(steps, 0, 0.0, 120.0, true)
	check(visualizer.upcoming_notes().is_empty(), "Zero-height viewport has no upcoming notes")

	# The legacy live-bar rectangle retains its original timing and lane geometry.
	visualizer.size = Vector2(1760.0, 880.0)
	visualizer.elapsed = 2.0
	var live_bar: Dictionary = {"midi": 60, "born": 1.0, "released": -1.0}
	var legacy_rect: Rect2 = visualizer.bar_rect(live_bar)
	check(near(legacy_rect.position.x, keys[60].position.x) and near(legacy_rect.size.x, keys[60].size.x), "Live bar preserves legacy key lane")
	check(near(legacy_rect.end.y, visualizer.size.y) and near(legacy_rect.size.y, 340.0), "Live bar preserves legacy contact and speed")
	var released_bar: Dictionary = {"midi": 60, "born": 1.0, "released": 1.5}
	var released_rect: Rect2 = visualizer.bar_rect(released_bar)
	check(near(released_rect.end.y, 710.0) and near(released_rect.size.y, 170.0), "Released bar preserves release-time geometry")

	# Resizing must preserve the contact plane and bounds-aware center.
	visualizer.size = Vector2(1200.0, 600.0)
	visualizer.horizontal_bounds = Vector2(80.0, 1120.0)
	var resized_key: Rect2 = keys[60]
	var resized_contact: Vector2 = visualizer.project_point(Vector2(resized_key.position.x, visualizer.size.y))
	check(near(resized_contact.x, resized_key.position.x) and near(resized_contact.y, 600.0), "Resizing keeps impact point anchored")
	var horizon_point: Vector2 = visualizer.project_point(Vector2(600.0, 0.0))
	check(near(horizon_point.x, 600.0), "Horizontal bounds center the perspective projection")

	visualizer.free()
	print("PERSPECTIVE CHECKS: %d; FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
