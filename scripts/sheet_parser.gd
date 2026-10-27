# SwiftPiano
# Copyright (c) 2026 Sebastián Zambrano
# Distributed under the terms of the MIT License.

extends RefCounted
const Keymap = preload("res://scripts/keymap_data.gd")

static func normalize(text: String) -> String:
	text = text.replace("&#x20;", " ").replace("&#32;", " ").replace("&nbsp;", " ")
	# Standard typographic ligatures frequently pasted from PDFs or macOS text editors
	text = text.replace("ﬂ", "fl")
	text = text.replace("ﬁ", "fi")
	text = text.replace("ﬀ", "ff")
	text = text.replace("ﬃ", "ffi")
	text = text.replace("ﬄ", "ffl")
	text = text.replace("ﬅ", "ft")
	text = text.replace("ﬆ", "st")
	# Asian / full-width brackets
	text = text.replace("［", "[").replace("］", "]")
	text = text.replace("【", "[").replace("】", "]")
	text = text.replace("〔", "[").replace("〕", "]")
	return text

static func format_notes(notes: Array) -> String:
	if notes.is_empty():
		return ""
	var labels = Keymap.labels()
	var sorted = notes.duplicate()
	sorted.sort()
	if sorted.size() == 1:
		var single_midi = int(sorted[0])
		return str(labels.get(single_midi, single_midi))
	var names = PackedStringArray()
	for n in sorted:
		names.append(str(labels.get(int(n), n)))
	return "[" + "".join(names) + "]"

static func format_step(step: Dictionary) -> String:
	if step.has("token") and not str(step["token"]).is_empty():
		return str(step["token"])
	return format_notes(step.get("notes", []))

static func parse_delays(text: String) -> Array[float]:
	var delays: Array[float] = []
	var ticks: Array[int] = []
	var tick_re = RegEx.new()
	tick_re.compile("tick\\s+(\\d+)")
	for raw_line in text.replace("\r", "").split("\n"):
		var line = raw_line.strip_edges()
		if line.begins_with("MIDI:"):
			var m = tick_re.search(line)
			if m != null:
				ticks.append(int(m.get_string(1)))
			else:
				return []
	if ticks.is_empty():
		return []
	for idx in range(ticks.size()):
		var curr_tick = ticks[idx]
		var next_tick = ticks[idx + 1] if idx + 1 < ticks.size() else (curr_tick + 480)
		var step_delay = clampf(float(maxi(1, next_tick - curr_tick)) * (0.5 / 480.0), 0.04, 4.0)
		delays.append(step_delay)
	return delays

static func parse(text: String, library_sheet: bool = false) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	var map = Keymap.parser_mapping()
	var transpose = null
	var chord: Array[int] = []
	var chord_chars = PackedStringArray()
	var inside = false
	var directive = RegEx.new()
	directive.compile("(?i)^\\s*(?:Transposition|Transpose)\\s*:?\\s*([+-]?\\d+)\\s*$")
	var metadata = RegEx.new()
	metadata.compile("(?i)^(title|song|artist|by|titulo|título|canción|autor)\\s*:")
	var normalized = normalize(text)
	for raw_line in normalized.replace("\r", "").split("\n"):
		var line = raw_line.strip_edges()
		# Explicit absolute pitches preserve the complete 88-key range in MIDI sheets.
		if line.begins_with("MIDI:"):
			var notes: Array[int] = []
			var valid = true
			for token in line.substr(5).split("#", true, 1)[0].strip_edges().split(" ", false):
				if not token.is_valid_int() or int(token) < 21 or int(token) > 108:
					valid = false
					break
				if not notes.has(int(token)):
					notes.append(int(token))
			if valid and not notes.is_empty():
				steps.append({"notes": notes, "transposition": 0, "token": format_notes(notes)})
			continue
		var found = directive.search(line)
		if found:
			transpose = clampi(int(found.get_string(1)), -87, 87)
			continue
		if line.begins_with("# ") or line == "#" or line.begins_with("//") or metadata.search(line):
			continue
		if not library_sheet and _looks_like_title(line):
			continue
		for character in raw_line:
			if character == "[":
				if not chord.is_empty():
					steps.append({"notes": chord.duplicate(), "transposition": transpose, "token": "[" + "".join(chord_chars) + "]"})
				chord.clear()
				chord_chars.clear()
				inside = true
			elif character == "]":
				if not chord.is_empty():
					steps.append({"notes": chord.duplicate(), "transposition": transpose, "token": "[" + "".join(chord_chars) + "]"})
				chord.clear()
				chord_chars.clear()
				inside = false
			elif map.has(character):
				var midi: int = map[character]
				if inside:
					if not chord.has(midi):
						chord.append(midi)
						chord_chars.append(character)
				else:
					steps.append({"notes": [midi], "transposition": transpose, "token": character})
	if not chord.is_empty():
		steps.append({"notes": chord.duplicate(), "transposition": transpose, "token": "[" + "".join(chord_chars) + "]"})
	return steps

static func _looks_like_title(line: String) -> bool:
	# Unmarked prose and valid note letters are inherently ambiguous.
	# Only skip recognizable multi-word Title Case; explicit Title: is reliable.
	if line.contains("["):
		return false
	for sym in ["!", "@", "$", "%", "^", "*", "(", ")", "#", "&"]:
		if line.contains(sym):
			return false
	var words = line.split(" ", false)
	if words.size() < 2:
		return false
	var long_word = false
	for word in words:
		if word.length() < 1 or word[0] == word[0].to_lower():
			return false
		if word.length() > 1 and word.substr(1) != word.substr(1).to_lower():
			return false
		long_word = long_word or word.length() >= 3
	return long_word

