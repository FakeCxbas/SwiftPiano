extends RefCounted
## Pure transformation: always derive variants from the original imported sheet.
const Parser = preload("res://scripts/sheet_parser.gd")
const Keymap = preload("res://scripts/keymap_data.gd")

static func convert(source: String, mode: int = 0, transpose: int = 0) -> Dictionary:
	var reverse = {}
	for key in Keymap.mapping():
		reverse[Keymap.mapping()[key]] = key
	var lines: Array[String] = ["# SwiftPiano · Auto manual · 88 teclas"]
	var row: Array[String] = []
	var count = 0
	var omitted = 0
	var extended = 0
	var steps = 0
	for step in Parser.parse(source, true):
		var notes: Array[int] = []
		for pitch in step.notes:
			var note = int(pitch) + transpose
			if note < 21 or note > 108:
				omitted += 1
			else:
				notes.append(note)
		if notes.is_empty():
			continue
		notes.sort()
		if mode == 1 and notes.size() > 3:
			# Bass, middle voice and melody; never split one chord into many steps.
			var mid_idx: int = int(notes.size() / 2)
			var reduced: Array[int] = [notes[0], notes[mid_idx], notes[-1]]
			notes = reduced
		elif mode == 2:
			var melody: Array[int] = [notes[-1]]
			notes = melody
		var keys = ""
		var absolute: Array[String] = []
		var outside = false
		for note in notes:
			absolute.append(str(note))
			outside = outside or not reverse.has(note)
			keys += str(reverse.get(note, ""))
		count += notes.size()
		steps += 1
		if outside:
			if not row.is_empty():
				lines.append(" ".join(row))
				row.clear()
			lines.append("MIDI: " + " ".join(absolute))
			extended += 1
		else:
			# Brackets also protect isolated '(' from prose/title heuristics.
			row.append("[" + keys + "]")
			if row.size() == 8:
				lines.append(" ".join(row))
				row.clear()
	if not row.is_empty():
		lines.append(" ".join(row))
	return {"sheet": "\n".join(lines), "notes": count, "steps": steps, "omitted": omitted, "extended": extended}
