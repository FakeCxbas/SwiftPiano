extends SceneTree
const MainScene = preload("res://scenes/main.tscn")
const Converter = preload("res://scripts/sheet_converter.gd")
const ConversionPanel = preload("res://scripts/conversion_panel.gd")
const Parser = preload("res://scripts/sheet_parser.gd")
const Keymap = preload("res://scripts/keymap_data.gd")
const Importer = preload("res://scripts/midi_importer.gd")

var checks = 0
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILURE: " + message)

func run() -> void:
	print("--- Running Sheet Converter Tests ---")
	test_88_notes_roundtrip()
	test_chord_reduction()
	test_melody_extraction()
	test_transposition_and_limits()
	test_html_entities_and_parentheses()
	test_non_accumulative_conversions()
	test_conversion_panel_ui()
	test_corrupt_file_preserves_state()
	await test_main_integration()
	test_shared_song_library_load()

	print("CONVERTER CHECKS: %d; FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_88_notes_roundtrip() -> void:
	# Build a sheet with all 88 keys: A0 (21) through C8 (108)
	var source_lines: Array[String] = []
	for midi in range(21, 109):
		source_lines.append("MIDI: %d" % midi)
	var source = "\n".join(source_lines)
	
	var result = Converter.convert(source, 0, 0)
	check(result.notes == 88, "Roundtrip notes count is 88")
	check(result.steps == 88, "Roundtrip steps count is 88")
	check(result.omitted == 0, "Zero notes omitted without transposition")
	
	var parsed = Parser.parse(result.sheet, true)
	check(parsed.size() == 88, "Parsed steps count is 88")
	var notes_found: Array[int] = []
	for step in parsed:
		for n in step.notes:
			notes_found.append(n)
	check(notes_found.size() == 88, "Parsed contains all 88 individual notes")
	var all_match = true
	for i in range(88):
		if notes_found[i] != 21 + i:
			all_match = false
			break
	check(all_match, "All 88 pitches match exactly from A0 (21) to C8 (108)")

func test_chord_reduction() -> void:
	# 5-note chord and 4-note chord
	var source = "MIDI: 48 52 55 59 62\nMIDI: 60 64 67 71\nMIDI: 60 64 67"
	var res_all = Converter.convert(source, 0, 0)
	var res_reduced = Converter.convert(source, 1, 0)
	
	check(res_reduced.steps == res_all.steps, "Reduced chord mode preserves step count (3 steps)")
	var parsed = Parser.parse(res_reduced.sheet, true)
	check(parsed.size() == 3, "Parsed reduced sheet has 3 steps")
	
	# First step had 5 notes: [48, 52, 55, 59, 62]. Middle is index 5/2 = 2 (55).
	# Reduced should be [48, 55, 62] (bass, middle, soprano).
	check(parsed[0].notes == [48, 55, 62], "5-note chord reduced to 3 notes [48, 55, 62]")
	
	# Second step had 4 notes: [60, 64, 67, 71]. Middle is index 4/2 = 2 (67).
	# Reduced should be [60, 67, 71].
	check(parsed[1].notes == [60, 67, 71], "4-note chord reduced to 3 notes [60, 67, 71]")
	
	# Third step had 3 notes: [60, 64, 67]. Mode 1 keeps <=3 untouched.
	check(parsed[2].notes == [60, 64, 67], "3-note chord preserved untouched in mode 1")

func test_melody_extraction() -> void:
	var source = "MIDI: 48 52 55 59 62\nMIDI: 60 64 67 71\nMIDI: 60 64 67\nMIDI: 72"
	var res_melody = Converter.convert(source, 2, 0)
	check(res_melody.steps == 4, "Melody mode preserves step count")
	var parsed = Parser.parse(res_melody.sheet, true)
	check(parsed.size() == 4, "Parsed melody has 4 steps")
	check(parsed[0].notes == [62], "Step 0 melody is highest pitch 62")
	check(parsed[1].notes == [71], "Step 1 melody is highest pitch 71")
	check(parsed[2].notes == [67], "Step 2 melody is highest pitch 67")
	check(parsed[3].notes == [72], "Step 3 melody is highest pitch 72")

func test_transposition_and_limits() -> void:
	var source = "MIDI: 21 60 108"
	# Transpose +2: 21 -> 23, 60 -> 62, 108 -> 110 (out of range, omitted!)
	var res_up = Converter.convert(source, 0, 2)
	check(res_up.omitted == 1, "Transpose +2 on C8 exceeds 108 and is counted as omitted")
	var parsed_up = Parser.parse(res_up.sheet, true)
	check(parsed_up[0].notes == [23, 62], "Transposed notes are 23 and 62")
	
	# Transpose -2: 21 -> 19 (out of range, omitted!), 60 -> 58, 108 -> 106
	var res_down = Converter.convert(source, 0, -2)
	check(res_down.omitted == 1, "Transpose -2 on A0 below 21 is counted as omitted")
	var parsed_down = Parser.parse(res_down.sheet, true)
	check(parsed_down[0].notes == [58, 106], "Transposed notes are 58 and 106")
	
	# Extreme transposition that omits everything
	var res_extreme = Converter.convert("MIDI: 108", 0, 10)
	check(res_extreme.omitted == 1 and res_extreme.steps == 0, "Completely omitted note results in 0 steps")

func test_html_entities_and_parentheses() -> void:
	var raw_html = "t&#x20;y&#32;u&nbsp;i"
	var normalized = Parser.normalize(raw_html)
	check(normalized == "t y u i", "HTML entities normalized to single spaces")
	
	var parsed_html = Parser.parse(raw_html, true)
	check(parsed_html.size() == 4, "Parsed 4 notes without false entities notes")
	
	# Parenthesis '('
	var vp_sheet = "[9(]"
	var parsed_vp = Parser.parse(vp_sheet, true)
	check(parsed_vp.size() == 1, "Parenthesis parsed as valid chord in library mode")
	check(parsed_vp[0].notes.has(Keymap.mapping()["("]), "Parenthesis '(' maps correctly to its MIDI note")

func test_non_accumulative_conversions() -> void:
	var source = "MIDI: 48 52 55 59 62\nMIDI: 60 64 67"
	var run1 = Converter.convert(source, 1, 0)
	var run2 = Converter.convert(source, 2, 0)
	var run3 = Converter.convert(source, 0, 0)
	
	check(run1.notes == 6, "Mode 1 has 3 + 3 = 6 notes")
	check(run2.notes == 2, "Mode 2 has 1 + 1 = 2 notes")
	check(run3.notes == 8, "Mode 0 has 5 + 3 = 8 notes")
	
	# Running again gives exact same result (pure function)
	var run1_again = Converter.convert(source, 1, 0)
	check(run1_again.sheet == run1.sheet, "Converter is pure and non-accumulative")

func test_conversion_panel_ui() -> void:
	var panel = ConversionPanel.new()
	var mock_res = {
		"sheet": "MIDI: 60 64 67",
		"tracks": 1,
		"percussion": 0,
		"omitted": 0
	}
	panel.load_result(mock_res, "user://test_song.mid")
	check(panel.source_title == "test_song", "Source title extracted correctly")
	check(not panel.generate.disabled, "Generate button enabled")
	check(not panel.copy.disabled and not panel.use_sheet.disabled, "Initial conversion enables copy and use_sheet")
	check(not panel.options_dirty, "Initial state has options_dirty false")
	
	# Changing transpose marks options dirty and disables copy/use_sheet
	panel.transpose.value = 5
	panel.transpose.value_changed.emit(5)
	check(panel.options_dirty, "Changing transpose sets options_dirty")
	check(panel.copy.disabled and panel.use_sheet.disabled, "Dirty options disable copy and use_sheet")
	
	# Editing preview while dirty does NOT re-enable copy/use_sheet
	panel.preview.text += " "
	panel.preview.text_changed.emit()
	check(panel.copy.disabled and panel.use_sheet.disabled, "Editing preview while dirty leaves buttons disabled")
	
	# Reverting transpose to applied value restores options_dirty = false
	panel.transpose.value = 0
	panel.transpose.value_changed.emit(0)
	check(not panel.options_dirty, "Reverting transpose to applied value clears options_dirty")
	check(not panel.copy.disabled and not panel.use_sheet.disabled, "Clearing options_dirty re-enables buttons")
	
	# Regenerate updates preview and resets dirty state
	panel.transpose.value = 3
	panel.transpose.value_changed.emit(3)
	check(panel.options_dirty, "Options marked dirty again")
	panel.regenerate()
	check(not panel.options_dirty, "Regenerate clears options_dirty")
	check(not panel.copy.disabled and not panel.use_sheet.disabled, "Regenerate re-enables buttons")
	
	# Empty preview disables copy/use_sheet
	panel.preview.text = ""
	panel.preview.text_changed.emit()
	check(panel.copy.disabled and panel.use_sheet.disabled, "Empty preview disables copy and use_sheet")
	panel.free()

func test_corrupt_file_preserves_state() -> void:
	var importer = Importer.new()
	var corrupt_bytes = "Not a MIDI file".to_ascii_buffer()
	var res = importer.parse_bytes(corrupt_bytes)
	check(not res.error.is_empty(), "Corrupt MIDI rejected with error message")

func test_main_integration() -> void:
	var app = MainScene.instantiate()
	root.add_child(app)
	await process_frame
	
	# Setup initial state
	app.sheet_text_edit.text = "Initial draft text [158]"
	app.selected_song = "test_prev_song"
	app._popup_action("Auto")
	check(app.auto_enabled, "Auto enabled initially")
	
	# Apply conversion
	var converted_text = "[ceg] [fha]"
	app._apply_conversion(converted_text, "MyConvertedPiece")
	
	check(not app.auto_enabled, "Applying conversion pauses Auto")
	check(app.drafts["test_prev_song"] == "Initial draft text [158]", "Previous song draft preserved")
	check(app.sheet_text_edit.text == converted_text, "Atril text updated with converted sheet")
	check(app.steps.size() == 2, "Converted sheet compiled into 2 playable steps")
	check(app.menu.section == "sheet", "Atril section active")
	check(app.popup.visible, "Atril drawer visible")
	check(app.menu.song_title.text == "MyConvertedPiece", "Song title updated to converted piece name")
	
	app.audio.stop_all()
	await create_timer(0.15).timeout
	app.queue_free()
	await process_frame

func test_shared_song_library_load() -> void:
	var library = preload("res://scripts/music_library.gd").new()
	var found = false
	var shared_song = {}
	for song in library.songs:
		if song.id == "shared-2026-10-19":
			found = true
			shared_song = song
			break
	check(found, "Shared song 'shared-2026-10-19' found in library")
	check(shared_song.has_sheet, "Shared song marked as has_sheet")
	check(shared_song.sheet.begins_with("[9o]"), "Shared song begins with [9o]")
	check(shared_song.sheet.strip_edges().ends_with("1-[(5otwY]----"), "Shared song ends with 1-[(5otwY]----")
	var parsed = Parser.parse(shared_song.sheet, true)
	check(parsed.size() > 100, "Shared song parses into over 100 steps (actual: %d)" % parsed.size())
