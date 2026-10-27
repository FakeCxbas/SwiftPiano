extends RefCounted
## Bounded Standard MIDI File reader (formats 0/1). No audio or external libraries.
const MAX_BYTES = 8 * 1024 * 1024
const MAX_EVENTS = 200000
const MAX_STEPS = 10000
const Keymap = preload("res://scripts/keymap_data.gd")
var data = PackedByteArray()
var pos = 0
var limit = 0
var error = ""

func read_uint(count: int) -> int:
	if pos + count > limit:
		error = "MIDI truncado: faltan datos."
		return 0
	var value = 0
	for i in range(count):
		value = (value << 8) | data[pos]
		pos += 1
	return value

func vlq() -> int:
	var value = 0
	for i in range(4):
		var byte = read_uint(1)
		value = (value << 7) | (byte & 127)
		if byte < 128:
			return value
	error = "MIDI inválido: longitud variable demasiado larga."
	return 0

func skip(count: int) -> void:
	if count < 0 or pos + count > limit:
		error = "MIDI truncado: longitud de evento incorrecta."
	else:
		pos += count

func import_file(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "No se pudo abrir el archivo MIDI."}
	if file.get_length() > MAX_BYTES:
		return {"error": "El MIDI supera el límite de 8 MB."}
	return parse_bytes(file.get_buffer(file.get_length()), path.get_file())

func parse_bytes(bytes: PackedByteArray, title: String = "MIDI") -> Dictionary:
	data = bytes
	pos = 0
	limit = data.size()
	error = ""
	if limit > MAX_BYTES or read_uint(4) != 0x4d546864:
		return {"error": "No es un archivo MIDI estándar válido."}
	var header_size = read_uint(4)
	if header_size < 6 or header_size > limit - pos:
		return {"error": "Cabecera MIDI incompleta."}
	var format = read_uint(2)
	var tracks = read_uint(2)
	var division = read_uint(2)
	skip(header_size - 6)
	if format > 1 or tracks < 1 or tracks > 256 or (format == 0 and tracks != 1):
		return {"error": "Se admiten MIDI tipo 0 y 1, con hasta 256 pistas."}
	if division == 0 or division & 0x8000:
		return {"error": "Se requiere división musical PPQN; SMPTE no está disponible."}
	var onsets: Dictionary = {}
	var omitted = 0
	var percussion = 0
	var events = 0
	var us_per_qn = 500000
	for track in range(tracks):
		limit = data.size()
		if read_uint(4) != 0x4d54726b:
			return {"error": "No se encontró una pista MIDI válida."}
		var length = read_uint(4)
		if not error.is_empty() or length > limit - pos:
			return {"error": "Pista MIDI truncada."}
		limit = pos + length
		var tick = 0
		var running = 0
		var ended = false
		while pos < limit and error.is_empty():
			events += 1
			if events > MAX_EVENTS:
				return {"error": "MIDI demasiado complejo (máximo 200.000 eventos)."}
			tick += vlq()
			var status = read_uint(1)
			if status < 128:
				if running == 0:
					error = "Running status MIDI inválido."
					break
				pos -= 1
				status = running
			if status == 0xff:
				running = 0
				var meta = read_uint(1)
				var size = vlq()
				if meta == 0x51 and size == 3:
					var t_val = read_uint(3)
					if error.is_empty() and t_val > 0:
						us_per_qn = t_val
				else:
					skip(size)
				if meta == 0x2f:
					if size != 0:
						error = "Fin de pista MIDI inválido."
					ended = true
					pos = limit
			elif status == 0xf0 or status == 0xf7:
				running = 0
				skip(vlq())
			elif status >= 0x80 and status <= 0xef:
				running = status
				var kind = status & 0xf0
				var note = read_uint(1)
				var value = 0 if kind in [0xc0, 0xd0] else read_uint(1)
				if note >= 128 or value >= 128:
					error = "Datos de canal MIDI inválidos."
				if kind == 0x90 and value > 0:
					if (status & 15) == 9:
						percussion += 1
					elif note < 21 or note > 108:
						omitted += 1
					else:
						if not onsets.has(tick):
							if onsets.size() >= MAX_STEPS:
								return {"error": "La hoja supera los 10.000 pasos. Divide el MIDI en fragmentos."}
							onsets[tick] = []
						if not onsets[tick].has(note):
							onsets[tick].append(note)
			else:
				error = "Evento MIDI no admitido."
		if not error.is_empty():
			return {"error": error}
		if not ended:
			return {"error": "Falta el evento de fin de pista."}
	if onsets.is_empty():
		return {"error": "No hay notas melódicas en el rango A0–C8."}
	var ticks = onsets.keys()
	ticks.sort()
	var delays: Array[float] = []
	var sec_per_tick = (float(us_per_qn) / 1000000.0) / float(maxi(1, division))
	var lines = PackedStringArray()
	lines.append("# MIDI: " + title.replace("\n", " ").replace("\r", " "))
	lines.append("# Auto: un paso por ataque; tú controlas el ritmo y la duración.")
	lines.append("# Percusión omitida: %d · Fuera de A0–C8: %d" % [percussion, omitted])
	var labels = Keymap.labels()
	for idx in range(ticks.size()):
		var tick = ticks[idx]
		var next_tick = ticks[idx + 1] if idx + 1 < ticks.size() else (tick + division)
		var step_delay = clampf(float(maxi(1, next_tick - tick)) * sec_per_tick, 0.04, 4.0)
		delays.append(step_delay)
		var chord: Array = onsets[tick]
		chord.sort()
		var notes = PackedStringArray()
		var keys = PackedStringArray()
		for note in chord:
			notes.append(str(note))
			keys.append(labels[note])
		lines.append("MIDI: %s # teclas: %s · tick %d" % [" ".join(notes), " ".join(keys), tick])
	return {"error": "", "sheet": "\n".join(lines), "steps": ticks.size(), "delays": delays, "percussion": percussion, "omitted": omitted, "tracks": tracks}

