# SwiftPiano
# Copyright (c) 2026 Sebastián Zambrano
# Distributed under the terms of the MIT License.

extends RefCounted
const PATH = "res://assets/library/letras.json"
var songs: Array = []

func _find_song_sheet(song_id: String) -> String:
	for song in songs:
		if song is Dictionary and song.get("id") == song_id:
			return str(song.get("sheet", ""))
	return ""

func _load_sheet_file(res_path: String, fallback_id: String = "") -> String:
	var content = FileAccess.get_file_as_string(res_path)
	if not content.is_empty():
		return content
	if not fallback_id.is_empty():
		return _find_song_sheet(fallback_id)
	return ""

func _init() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data is Dictionary and data.get("songs") is Array:
		songs = data.songs
	songs.append({"id": "shared-2026-10-19", "title": "When Devil Falls in Love — hoja compartida", "page": 0, "end_page": 0, "source": "Hoja compartida · título provisional", "has_sheet": true, "sheet": _load_sheet_file("res://assets/library/hoja_compartida.txt")})
	songs.append({"id": "chopin-etude-op10-no4", "title": "Chopin - Etude Op. 10 No. 4 (Torrent)", "page": 0, "end_page": 0, "source": "Virtual Piano Sheet", "has_sheet": true, "sheet": _load_sheet_file("res://assets/library/chopin_etude_op10_no4.txt")})
	songs.append({"id": "love-is-orange", "title": "Love Is Orange (MEGIDDO MIX) - Orange Lounge", "page": 0, "end_page": 0, "source": "Transcripción de Video / Synthesia", "has_sheet": true, "sheet": _load_sheet_file("res://assets/library/love_is_orange.txt")})
	songs.append({"id": "great-fairy-fountain", "title": "Great Fairy Fountain (Liszt Concert Paraphrase) - Zelda", "page": 0, "end_page": 0, "source": "Paráfrasis de Concierto a lo Franz Liszt", "has_sheet": true, "sheet": _load_sheet_file("res://assets/library/great_fairy_fountain.txt", "letras-011")})
	songs.append({"id": "howls-moving-castle-v1", "title": "Howl's Moving Castle (Merry-Go-Round of Life) - Versión 1", "page": 0, "end_page": 0, "source": "Joe Hisaishi / Vals en 3/4", "has_sheet": true, "sheet": _load_sheet_file("res://assets/library/howls_moving_castle_v1.txt", "letras-005")})
	songs.append({"id": "howls-moving-castle-liszt", "title": "Howl's Moving Castle (Liszt Concert Paraphrase) - Hisaishi", "page": 0, "end_page": 0, "source": "Paráfrasis de Concierto a lo Franz Liszt", "has_sheet": true, "sheet": _load_sheet_file("res://assets/library/howls_moving_castle_liszt.txt", "howls-moving-castle-v1")})
	songs.append({"id": "howls-moving-castle-god-maniac", "title": "Howl's Moving Castle (Parte God Maníaca) - Joe Hisaishi", "page": 0, "end_page": 0, "source": "Tango / Vals Maníaco con Octavas", "has_sheet": true, "sheet": _load_sheet_file("res://assets/library/howls_moving_castle_parte_god_maniaca.txt", "letras-040")})
	songs.append({"id": "kamyus-waltz", "title": "Kamyu's Waltz - Dragon Quest XI (Erik's Theme)", "page": 0, "end_page": 0, "source": "Dragon Quest XI / Sugiyama", "has_sheet": true, "sheet": _load_sheet_file("res://assets/library/kamyus_waltz.txt")})


static func source_description(song: Dictionary) -> String:
	return song.get("source", "Letras.pdf · páginas %d–%d" % [song.page, song.end_page])

func search(query: String) -> Array[int]:
	var result: Array[int] = []
	var normalized = query.strip_edges().to_lower()
	for i in range(songs.size()):
		if normalized.is_empty() or normalized in str(songs[i].title).to_lower():
			result.append(i)
	return result
