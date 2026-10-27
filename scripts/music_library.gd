extends RefCounted
const PATH = "res://assets/library/letras.json"
var songs: Array = []

func _init() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data is Dictionary and data.get("songs") is Array:
		songs = data.songs
	songs.append({"id": "shared-2026-10-19", "title": "When Devil Falls in Love — hoja compartida", "page": 0, "end_page": 0, "source": "Hoja compartida · título provisional", "has_sheet": true, "sheet": FileAccess.get_file_as_string("res://assets/library/hoja_compartida.txt")})
	songs.append({"id": "chopin-etude-op10-no4", "title": "Chopin - Etude Op. 10 No. 4 (Torrent)", "page": 0, "end_page": 0, "source": "Virtual Piano Sheet", "has_sheet": true, "sheet": FileAccess.get_file_as_string("res://assets/library/chopin_etude_op10_no4.txt")})
	songs.append({"id": "love-is-orange", "title": "Love Is Orange (MEGIDDO MIX) - Orange Lounge", "page": 0, "end_page": 0, "source": "Transcripción de Video / Synthesia", "has_sheet": true, "sheet": FileAccess.get_file_as_string("res://assets/library/love_is_orange.txt")})
	songs.append({"id": "great-fairy-fountain", "title": "Great Fairy Fountain (Piano Etude) - Zelda", "page": 0, "end_page": 0, "source": "Erik Correll / @fallingkeys", "has_sheet": true, "sheet": FileAccess.get_file_as_string("res://assets/library/great_fairy_fountain.txt")})


static func source_description(song: Dictionary) -> String:
	return song.get("source", "Letras.pdf · páginas %d–%d" % [song.page, song.end_page])

func search(query: String) -> Array[int]:
	var result: Array[int] = []
	var normalized = query.strip_edges().to_lower()
	for i in range(songs.size()):
		if normalized.is_empty() or normalized in str(songs[i].title).to_lower():
			result.append(i)
	return result
