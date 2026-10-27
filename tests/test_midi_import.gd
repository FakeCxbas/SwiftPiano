extends SceneTree
const Importer = preload("res://scripts/midi_importer.gd")
const Parser = preload("res://scripts/sheet_parser.gd")
var checks = 0
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func be(value: int, count: int) -> PackedByteArray:
	var bytes = PackedByteArray()
	for i in range(count - 1, -1, -1):
		bytes.append((value >> (8 * i)) & 255)
	return bytes

func midi(tracks: Array, format: int = 0, division: int = 480) -> PackedByteArray:
	var bytes = "MThd".to_ascii_buffer() + be(6, 4) + be(format, 2) + be(tracks.size(), 2) + be(division, 2)
	for track in tracks:
		bytes.append_array("MTrk".to_ascii_buffer() + be(track.size(), 4) + PackedByteArray(track))
	return bytes

func key(app: Node, down: bool) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = KEY_A
	event.keycode = KEY_A
	event.pressed = down
	app._input(event)

func run() -> void:
	# Program change (one byte), note-on/running status, zero velocity, note-off,
	# percussion, out-of-range notes, tempo metadata, SysEx and end of track.
	var track = [0, 0xc0, 0, 0, 0x90, 21, 88, 0, 60, 88, 0, 108, 88,
		0, 62, 0, 0, 0x99, 40, 88, 0, 0x90, 20, 88,
		0, 0xff, 0x51, 3, 7, 161, 32, 0, 0xf0, 2, 1, 0xf7,
		0x81, 0x70, 0x90, 64, 88, 0, 0x80, 64, 0, 0, 0xff, 0x2f, 0]
	var bytes = midi([track])
	var result = Importer.new().parse_bytes(bytes)
	check(result.error.is_empty(), "Valid type 0 MIDI")
	if not result.error.is_empty():
		quit(1)
		return
	check(result.steps == 2 and result.percussion == 1 and result.omitted == 1, "Onsets and excluded notes")
	var steps = Parser.parse(result.sheet)
	check(steps.size() == 2, "Generated sheet parses")
	check(steps[0].notes == [21, 60, 108] and steps[1].notes == [64], "88-key extremes and running status survive")
	check(steps[0].transposition == 0, "Imported pitches are absolute")
	var second = [0, 0x90, 67, 88, 0, 60, 88, 0, 0xff, 0x2f, 0]
	var multi = Importer.new().parse_bytes(midi([track, second], 1))
	check(multi.error.is_empty(), "Type 1 accepted")
	check(Parser.parse(multi.sheet)[0].notes == [21, 60, 67, 108], "Tracks merge at common tick and deduplicate pitches")
	for cut in range(bytes.size()):
		check(not Importer.new().parse_bytes(bytes.slice(0, cut)).error.is_empty(), "Truncation rejected at %d" % cut)
	check(not Importer.new().parse_bytes(midi([track], 2)).error.is_empty(), "Format 2 rejected explicitly")
	check(not Importer.new().parse_bytes(midi([track], 0, 0xe728)).error.is_empty(), "SMPTE rejected explicitly")
	check(not Importer.new().parse_bytes(midi([[0, 60, 88]])).error.is_empty(), "Invalid running status rejected")
	check(not Importer.new().parse_bytes(midi([[128, 128, 128, 128, 0]])).error.is_empty(), "Oversized VLQ rejected")
	check(not Importer.new().parse_bytes(midi([[0, 0xff, 0x2f, 0]])).error.is_empty(), "Empty song rejected")
	check(Parser.parse("MIDI: 60 abc\nMIDI: 128\nMIDI: 21 108 # keys").size() == 1, "Malformed explicit lines never become QWERTY notes")
	check(Parser.parse("[ceg] t u").size() == 3, "Legacy VP remains supported")
	var path = "user://midi-test-%d.mid" % Time.get_ticks_usec()
	var output = path + ".txt"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.audio.set_volume(0)
	var previous = app.sheet_text_edit.text
	app._import_midi(path + ".missing")
	check(app.sheet_text_edit.text == previous, "Failed import preserves existing sheet")
	app.midi_notice.hide()
	app._import_midi(path)
	check(app.steps.size() == 2 and not app.auto_enabled, "Import loads paused playable sheet")
	key(app, true)
	check(app.sources.is_empty(), "Import notice blocks piano input")
	app.midi_notice.hide()
	app._popup_action("Auto")
	key(app, true)
	check(app.keyboard.active.has(21) and app.keyboard.active.has(108) and app.keyboard.active.has(60), "Auto plays imported chord across 88 keys")
	key(app, false)
	check(app.keyboard.active.is_empty(), "Imported chord releases on key-up")
	app._export_sheet(output)
	check(Parser.parse(FileAccess.get_file_as_string(output)) == app.steps, "Saved sheet round-trips without losing pitches")
	app.midi_notice.hide()
	app._menu_action("ImportMidi")
	check(app.midi_dialog.visible and not app.auto_enabled, "Import action opens picker and pauses Auto")
	app.midi_dialog.hide()
	app.audio.stop_all()
	# Let the audio thread release Ogg playback before destroying the fixture.
	await create_timer(0.2).timeout
	app.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(output))
	print("MIDI CHECKS: %d; FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
