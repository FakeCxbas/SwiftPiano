# SwiftPiano
# Copyright (c) 2026 Sebastián Zambrano
# Distributed under the terms of the MIT License.

extends SceneTree

const MusicLibrary = preload("res://scripts/music_library.gd")
const SheetParser = preload("res://scripts/sheet_parser.gd")

func _init() -> void:
	var lib = MusicLibrary.new()
	var total_songs = lib.songs.size()
	print("Checking music library songs: %d total" % total_songs)
	assert(total_songs > 0, "Music library should not be empty")

	var songs_with_sheet = 0
	for song in lib.songs:
		if song is Dictionary and song.get("has_sheet", false):
			songs_with_sheet += 1
			var title = str(song.get("title", ""))
			var sheet = str(song.get("sheet", ""))
			assert(not sheet.strip_edges().is_empty(), "Song '%s' has has_sheet=true but empty sheet!" % title)
			var steps = SheetParser.parse(sheet, true)
			assert(steps.size() > 0, "Song '%s' sheet produced 0 steps!" % title)

	print("PASSED: %d songs with sheets verified successfully." % songs_with_sheet)
	quit(0)
