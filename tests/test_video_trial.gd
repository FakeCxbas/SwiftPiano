extends SceneTree
const Importer = preload("res://scripts/midi_importer.gd")
const Parser = preload("res://scripts/sheet_parser.gd")
var failed = false

func _initialize() -> void:
	var folder = "res://artifacts/whatsapp-piano/"
	var arguments = OS.get_cmdline_user_args()
	if not arguments.is_empty():
		folder = arguments[0].trim_suffix("/") + "/"
	for name in ["auto-acordes", "auto-facil"]:
		var path = folder + name
		var imported = Importer.new().import_file(path + ".mid")
		if not imported.error.is_empty():
			push_error(imported.error)
			failed = true
			continue
		var expected = Parser.parse(FileAccess.get_file_as_string(path + ".txt"))
		var actual = Parser.parse(imported.sheet)
		if expected != actual or actual.is_empty():
			push_error("MIDI and Auto sheet differ: " + name)
			failed = true
		var chords = 0
		for step in actual:
			if step.notes.size() > 1:
				chords += 1
			if step.notes.size() > 6:
				failed = true
		if chords < actual.size() / 2:
			failed = true
		print("%s: %d playable steps, %d chords; MIDI/sheet match=%s" % [name, actual.size(), chords, expected == actual])
	quit(1 if failed else 0)
