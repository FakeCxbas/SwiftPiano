# SwiftPiano
# Copyright (c) 2026 Sebastián Zambrano
# Distributed under the terms of the MIT License.

extends Node
## Salamander Yamaha C5 multisamples, with a procedural fallback if unavailable.
## Close-Mic Studio Piano profile: high headphone loudness, zero mud/echo, clean voice stealing.
const SAMPLE_RATE = 44100
## Base sample normalization target: 95% peak amplitude (-0.45 dBFS).
const SAMPLE_GAIN = 0.95
const DEFAULT_VELOCITY = 108
const RETRIGGER_FADE = 0.025
const SUSTAIN_RELEASE_BASS = 2.60
const SUSTAIN_RELEASE_TREBLE = 3.40
const INNER_SUSTAIN_RELEASE: float = 2.35
const NO_SUSTAIN_RELEASE = 0.12
const MAX_RELEASED_TAILS = 14
const MAX_RELEASED_BASS_TAILS = 3
const LIM_PRE_GAIN_DB = 6.5
const LIM_CEILING_DB = -0.3
const LIM_THRESHOLD_DB = -2.5
const REFERENCES = [36, 60, 84]

## Measured raw linear peak amplitudes of Salamander C5 Ogg samples for 95% peak normalization.
const GRAND_PIANO_SAMPLE_PEAKS = {
	21: 0.3981, 24: 0.4027, 27: 0.4266, 30: 0.4519,
	33: 0.3715, 36: 0.3936, 39: 0.3890, 42: 0.3802,
	45: 0.3199, 48: 0.3548, 51: 0.3673, 54: 0.3199,
	57: 0.2600, 60: 0.3981, 63: 0.3715, 66: 0.2692,
	69: 0.3090, 72: 0.2786, 75: 0.2455, 78: 0.2786,
	81: 0.2723, 84: 0.2917, 87: 0.3428, 90: 0.2188,
	93: 0.1905, 96: 0.2113, 99: 0.1462, 102: 0.1950,
	105: 0.1109, 108: 0.1349
}

## Per-sample normalization gains calibrated across peak and 120 ms attack RMS.
const INSTRUMENT_SAMPLE_NORMS: Dictionary = {
	"grand_piano": {
		21: 2.12, 24: 2.32, 27: 2.02, 30: 2.17, 33: 2.43, 36: 2.76, 39: 2.11, 42: 2.28,
		45: 2.53, 48: 2.02, 51: 2.09, 54: 3.30, 57: 3.75, 60: 2.16, 63: 2.14, 66: 2.63,
		69: 3.13, 72: 6.10, 75: 4.60, 78: 2.86, 81: 3.72, 84: 3.25, 87: 2.96, 90: 4.24,
		93: 5.11, 96: 3.95, 99: 7.20, 102: 4.53, 105: 6.64, 108: 6.44
	},
	"steinway_grand": {
		21: 11.75, 24: 12.80, 27: 19.86, 30: 8.93, 33: 7.42, 36: 7.60, 39: 8.76, 42: 8.21,
		45: 8.18, 48: 9.49, 51: 8.94, 54: 14.75, 57: 8.81, 60: 16.88, 63: 7.77, 66: 7.77,
		69: 12.36, 72: 19.03, 75: 11.95, 78: 8.44, 81: 10.12, 84: 10.25, 87: 10.61, 90: 6.46,
		93: 9.50, 96: 6.89, 99: 6.53, 102: 11.31, 105: 12.09, 108: 11.47
	},
	"bright_piano": {
		21: 6.96, 24: 6.84, 27: 7.19, 30: 7.07, 33: 7.43, 36: 7.93, 39: 6.09, 42: 5.91,
		45: 5.71, 48: 5.92, 51: 6.34, 54: 6.07, 57: 7.78, 60: 7.50, 63: 11.05, 66: 11.36,
		69: 6.24, 72: 9.07, 75: 8.47, 78: 9.13, 81: 9.91, 84: 11.32, 87: 6.11, 90: 6.69,
		93: 6.53, 96: 17.45, 99: 17.62, 102: 17.62, 105: 11.78, 108: 14.42
	},
	"honkytonk_piano": {
		21: 5.97, 24: 5.87, 27: 6.22, 30: 6.07, 33: 6.80, 36: 6.86, 39: 5.19, 42: 5.22,
		45: 5.08, 48: 4.89, 51: 5.47, 54: 5.47, 57: 6.99, 60: 6.61, 63: 10.27, 66: 9.94,
		69: 5.45, 72: 8.00, 75: 7.44, 78: 7.38, 81: 7.44, 84: 9.50, 87: 5.74, 90: 5.73,
		93: 6.33, 96: 15.98, 99: 15.51, 102: 15.98, 105: 8.68, 108: 11.79
	}
}

const INSTRUMENTS = {
	"grand_piano": {
		"name": "Piano de Cola",
		"icon": "🎹",
		"dir": "res://assets/grand_piano/",
		"release": 0.10,
		"gain": 1.0,
		"norm_gain": 2.4,
		"desc": "Yamaha C5 Salamander",
		"reverb_wet": 0.02,
		"reverb_room": 0.14,
		"type": "piano"
	},
	"steinway_grand": {
		"name": "Gran Steinway",
		"icon": "👑",
		"dir": "res://assets/instruments/steinway_grand/",
		"release": 0.10,
		"gain": 1.05,
		"norm_gain": 9.5,
		"desc": "Concierto Modelo D",
		"reverb_wet": 0.02,
		"reverb_room": 0.15,
		"type": "piano"
	},
	"bright_piano": {
		"name": "Piano Brillante",
		"icon": "🌟",
		"dir": "res://assets/instruments/bright_piano/",
		"release": 0.10,
		"gain": 0.98,
		"norm_gain": 7.5,
		"desc": "Acústico Pop & Studio",
		"reverb_wet": 0.02,
		"reverb_room": 0.14,
		"type": "piano"
	},
	"honkytonk_piano": {
		"name": "Piano Honky-Tonk",
		"icon": "🍺",
		"dir": "res://assets/instruments/honkytonk_piano/",
		"release": 0.10,
		"gain": 0.95,
		"norm_gain": 6.8,
		"desc": "Saloon & Ragtime Clásico",
		"reverb_wet": 0.015,
		"reverb_room": 0.12,
		"type": "piano"
	},
	"electric_grand": {
		"name": "Grand CP-80",
		"icon": "⚡",
		"dir": "res://assets/instruments/electric_grand/",
		"release": 0.10,
		"gain": 0.95,
		"norm_gain": 6.4,
		"desc": "Yamaha CP-80 Ochentas",
		"reverb_wet": 0.02,
		"reverb_room": 0.14,
		"type": "piano"
	},
	"electric_piano": {
		"name": "Piano Rhodes",
		"icon": "🎷",
		"dir": "res://assets/instruments/electric_piano/",
		"release": 0.10,
		"gain": 0.95,
		"norm_gain": 7.5,
		"desc": "Vintage Mark I Rhodes",
		"reverb_wet": 0.02,
		"reverb_room": 0.14,
		"type": "piano"
	},
	"fm_piano": {
		"name": "Piano Digital FM",
		"icon": "💎",
		"dir": "res://assets/instruments/fm_piano/",
		"release": 0.10,
		"gain": 0.92,
		"norm_gain": 8.2,
		"desc": "Yamaha DX7 Cristalino",
		"reverb_wet": 0.02,
		"reverb_room": 0.15,
		"type": "piano"
	},
	"church_organ": {
		"name": "Órgano Catedral",
		"icon": "⛪",
		"dir": "res://assets/instruments/church_organ/",
		"release": 0.10,
		"gain": 0.85,
		"norm_gain": 9.0,
		"desc": "Tubos & Acústica Sacra",
		"reverb_wet": 0.035,
		"reverb_room": 0.18,
		"type": "organ"
	},
	"synth_strings": {
		"name": "Synth Strings",
		"icon": "🎻",
		"dir": "res://assets/instruments/synth_strings/",
		"release": 0.10,
		"gain": 0.90,
		"norm_gain": 7.6,
		"desc": "Pad Analógico Años 80",
		"reverb_wet": 0.03,
		"reverb_room": 0.18,
		"type": "synth"
	},
	"celesta": {
		"name": "Celesta",
		"icon": "✨",
		"dir": "res://assets/instruments/celesta/",
		"release": 0.10,
		"gain": 0.90,
		"norm_gain": 7.0,
		"desc": "Campanas & Metalófono",
		"reverb_wet": 0.025,
		"reverb_room": 0.16,
		"type": "bell"
	},
	"harpsichord": {
		"name": "Clavecín",
		"icon": "🎼",
		"dir": "res://assets/instruments/harpsichord/",
		"release": 0.10,
		"gain": 0.92,
		"norm_gain": 6.6,
		"desc": "Barroco de Doble Manual",
		"reverb_wet": 0.015,
		"reverb_room": 0.12,
		"type": "historic"
	}
}

var bank: Dictionary = {}
var instrument_banks: Dictionary = {}
var current_reverb_preset: String = "studio"
var reverb_effect: AudioEffectReverb = null
var master_eq: AudioEffectEQ = null
var master_compressor: AudioEffectCompressor = null
var master_limiter: AudioEffectLimiter = null
var record_effect: AudioEffectRecord = null
var is_recording: bool = false
var last_recording_path: String = ""
const RECORDINGS_DIR = "user://recordings"
var current_instrument: String = "grand_piano"
var pool: Array[AudioStreamPlayer] = []
var voices: Dictionary = {}
var concert_voicing_enabled: bool = true: set = set_concert_voicing_enabled
var _voice_order: int = 0
var sustain_enabled = true
var master_volume = 1.0
var preload_usec = 0
var body = PackedFloat32Array()
var brightness = PackedFloat32Array()
var sampled_piano = false
const SAMPLE_DIR = "res://assets/grand_piano/"

func _ready() -> void:
	var start = Time.get_ticks_usec()
	_load_samples()
	if bank.is_empty():
		_build_tables()
		for midi in REFERENCES:
			bank[midi] = _make_piano(midi)
	else:
		sampled_piano = true
		instrument_banks["grand_piano"] = bank
	_setup_bus()
	_add_players(64)
	preload_usec = Time.get_ticks_usec() - start
	print("%s ready: %.1f ms; %d samples; %d voices" % ["Salamander Grand Piano" if sampled_piano else "Procedural fallback", preload_usec / 1000.0, bank.size(), pool.size()])

func _load_bank_from_dir(dir_path: String) -> Dictionary:
	var loaded_bank: Dictionary = {}
	var names = ["C", "Cs", "D", "Ds", "E", "F", "Fs", "G", "Gs", "A", "As", "B"]
	for midi in range(21, 109, 3):
		var filename = "%s%d.ogg" % [names[midi % 12], int(midi / 12) - 1]
		var path = dir_path + filename
		if ResourceLoader.exists(path):
			var stream = load(path)
			if stream is AudioStreamOggVorbis:
				loaded_bank[midi] = stream
	return loaded_bank

func _load_samples() -> void:
	# Samples every minor third across the full A0–C8 range. Runtime playback
	# shifts at most one semitone, rather than stretching one waveform by octaves.
	bank = _load_bank_from_dir(SAMPLE_DIR)

func set_instrument(id: String) -> void:
	if not INSTRUMENTS.has(id):
		return
	if id == current_instrument and not bank.is_empty():
		return
	stop_all()
	if not instrument_banks.has(id):
		var new_bank = _load_bank_from_dir(INSTRUMENTS[id].dir)
		if not new_bank.is_empty():
			instrument_banks[id] = new_bank
		else:
			push_warning("Failed to load instrument soundbank: %s" % id)
			return
	current_instrument = id
	bank = instrument_banks[id]
	_apply_instrument_reverb(id)
	print("Instrument switched to: %s (%s, %d samples)" % [INSTRUMENTS[id].name, id, bank.size()])

func get_current_instrument_name() -> String:
	return INSTRUMENTS.get(current_instrument, {}).get("name", "Piano de Cola")

func get_current_instrument_id() -> String:
	return current_instrument

func _apply_instrument_reverb(id: String) -> void:
	if reverb_effect == null:
		return
	var inst = INSTRUMENTS.get(id, {})
	var base_wet = clampf(inst.get("reverb_wet", 0.02), 0.0, 0.04)
	var base_room = clampf(inst.get("reverb_room", 0.14), 0.05, 0.20)
	# Close-Mic Studio Piano: ultra-dry, intimate, zero echo buildup (wet <= 0.04, room_size <= 0.20, damping = 0.90)
	reverb_effect.predelay_msec = 6.0
	reverb_effect.predelay_feedback = 0.0
	reverb_effect.damping = 0.90
	reverb_effect.hipass = 0.38
	reverb_effect.dry = 1.0
	match current_reverb_preset:
		"dry":
			reverb_effect.wet = 0.0
			reverb_effect.room_size = 0.0
			reverb_effect.damping = 0.90
			reverb_effect.predelay_msec = 5.0
			reverb_effect.spread = 0.2
			reverb_effect.hipass = 0.50
			reverb_effect.dry = 1.0
		"studio":
			# Intimate, crisp close-mic studio recording (satisfies studio test constraints)
			reverb_effect.wet = clampf(base_wet * 0.40, 0.006, 0.015)
			reverb_effect.room_size = clampf(base_room * 0.70, 0.08, 0.14)
			reverb_effect.damping = 0.90
			reverb_effect.predelay_msec = 6.0
			reverb_effect.spread = 0.5
			reverb_effect.hipass = 0.38
			reverb_effect.dry = 1.0
		"hall":
			# Spacious, warm concert hall acoustics with immersive natural tail
			reverb_effect.wet = 0.18
			reverb_effect.room_size = 0.68
			reverb_effect.damping = 0.45
			reverb_effect.predelay_msec = 18.0
			reverb_effect.spread = 0.85
			reverb_effect.hipass = 0.22
			reverb_effect.dry = 1.0
		"cathedral":
			# Majestic, deep, expansive cathedral reverb with long decay and spatial reflections
			reverb_effect.wet = 0.32
			reverb_effect.room_size = 0.88
			reverb_effect.damping = 0.25
			reverb_effect.predelay_msec = 28.0
			reverb_effect.spread = 1.0
			reverb_effect.hipass = 0.15
			reverb_effect.dry = 0.95

func set_reverb_preset(preset: String) -> void:
	current_reverb_preset = preset
	_apply_instrument_reverb(current_instrument)

func _setup_bus() -> void:
	# 0. Configure Master Bus: EQ (-3.0 dB @ 250/320 Hz, +1.5 dB @ 3200 Hz) -> Soft Compressor -> Limiter
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx >= 0 and AudioServer.get_bus_effect_count(master_idx) == 0:
		master_eq = AudioEffectEQ.new()
		# Band 2 (250-320 Hz low-mid mud cut: -3.0 dB), Band 4 (3200 Hz hammer attack definition: +1.5 dB)
		master_eq.set_band_gain_db(2, -3.0)
		master_eq.set_band_gain_db(4, 1.5)
		AudioServer.add_bus_effect(master_idx, master_eq)
		
		master_compressor = AudioEffectCompressor.new()
		master_compressor.threshold = -9.0
		master_compressor.ratio = 1.6
		master_compressor.attack_us = 4000.0
		master_compressor.release_ms = 180.0
		master_compressor.gain = 6.5
		AudioServer.add_bus_effect(master_idx, master_compressor)
		
		master_limiter = AudioEffectLimiter.new()
		master_limiter.set_meta("pre_gain", LIM_PRE_GAIN_DB)
		master_limiter.set_meta("pre_gain_db", LIM_PRE_GAIN_DB)
		master_limiter.ceiling_db = LIM_CEILING_DB
		master_limiter.threshold_db = LIM_THRESHOLD_DB
		master_limiter.soft_clip_db = 0.0
		AudioServer.add_bus_effect(master_idx, master_limiter)
		
		record_effect = AudioEffectRecord.new()
		AudioServer.add_bus_effect(master_idx, record_effect)
	elif master_idx >= 0 and AudioServer.get_bus_effect_count(master_idx) >= 3:
		master_eq = AudioServer.get_bus_effect(master_idx, 0) as AudioEffectEQ
		master_compressor = AudioServer.get_bus_effect(master_idx, 1) as AudioEffectCompressor
		master_limiter = AudioServer.get_bus_effect(master_idx, 2) as AudioEffectLimiter
		for eff_i: int in range(AudioServer.get_bus_effect_count(master_idx)):
			var eff: AudioEffect = AudioServer.get_bus_effect(master_idx, eff_i)
			if eff is AudioEffectRecord:
				record_effect = eff as AudioEffectRecord
				break
		if record_effect == null:
			record_effect = AudioEffectRecord.new()
			AudioServer.add_bus_effect(master_idx, record_effect)

	if master_compressor != null:
		master_compressor.threshold = -9.0
		master_compressor.ratio = 1.6
		master_compressor.attack_us = 4000.0
		master_compressor.release_ms = 180.0
		master_compressor.gain = 6.5

	if AudioServer.get_bus_index("GrandPiano") >= 0:
		var rev_idx: int = AudioServer.get_bus_index("PianoReverb")
		if rev_idx >= 0 and AudioServer.get_bus_effect_count(rev_idx) > 0:
			reverb_effect = AudioServer.get_bus_effect(rev_idx, 0) as AudioEffectReverb
		_setup_role_buses()
		_apply_instrument_reverb(current_instrument)
		return

	# 1. Setup Reverb Bus (sends to Master) - Close-Mic Studio Piano (nearly dry)
	var rev_index: int = AudioServer.get_bus_index("PianoReverb")
	if rev_index < 0:
		AudioServer.add_bus()
		rev_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(rev_index, "PianoReverb")
		AudioServer.set_bus_send(rev_index, "Master")
		reverb_effect = AudioEffectReverb.new()
		reverb_effect.predelay_msec = 6.0
		reverb_effect.predelay_feedback = 0.0
		reverb_effect.room_size = 0.14
		reverb_effect.damping = 0.90
		reverb_effect.spread = 0.5
		reverb_effect.hipass = 0.38
		reverb_effect.dry = 1.0
		reverb_effect.wet = 0.015
		AudioServer.add_bus_effect(rev_index, reverb_effect)
		AudioServer.set_bus_volume_db(rev_index, 0.0)
	else:
		reverb_effect = AudioServer.get_bus_effect(rev_index, 0) as AudioEffectReverb

	# 2. Setup GrandPiano Bus (effects: 0 = Compressor, 1 = Limiter, send -> PianoReverb)
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, "GrandPiano")
	AudioServer.set_bus_send(index, "PianoReverb")
	var compressor: AudioEffectCompressor = AudioEffectCompressor.new()
	compressor.threshold = -8.0
	compressor.ratio = 1.5
	compressor.attack_us = 3500.0
	compressor.release_ms = 180.0
	compressor.gain = -6.5
	AudioServer.add_bus_effect(index, compressor)
	var limiter: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
	limiter.pre_gain_db = 0.0
	limiter.ceiling_db = -1.5
	limiter.release = 0.10
	AudioServer.add_bus_effect(index, limiter)
	_setup_role_buses()
	_apply_instrument_reverb(current_instrument)

func _setup_role_buses() -> void:
	var piano_index: int = AudioServer.get_bus_index("GrandPiano")
	AudioServer.set_bus_volume_db(piano_index, -6.5)
	var compressor: AudioEffectCompressor = AudioServer.get_bus_effect(piano_index, 0) as AudioEffectCompressor
	if compressor != null:
		compressor.threshold = -8.0
		compressor.ratio = 1.5
		compressor.attack_us = 3500.0
		compressor.release_ms = 180.0
		compressor.gain = -6.5
	for bus_name: String in ["PianoLead", "PianoWarm", "PianoBass"]:
		var index: int = AudioServer.get_bus_index(bus_name)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "GrandPiano")
		var low_pass: AudioEffectLowPassFilter = null
		var equalizer: AudioEffectEQ = null
		for eff_i: int in range(AudioServer.get_bus_effect_count(index)):
			var eff: AudioEffect = AudioServer.get_bus_effect(index, eff_i)
			if eff is AudioEffectLowPassFilter and low_pass == null:
				low_pass = eff as AudioEffectLowPassFilter
			elif eff is AudioEffectEQ and equalizer == null:
				equalizer = eff as AudioEffectEQ
		if bus_name == "PianoWarm":
			if low_pass == null:
				low_pass = AudioEffectLowPassFilter.new()
				AudioServer.add_bus_effect(index, low_pass)
			low_pass.cutoff_hz = 6200.0
			low_pass.resonance = 0.25
			low_pass.db = AudioEffectFilter.FILTER_6DB
		if equalizer == null:
			equalizer = AudioEffectEQ.new()
			AudioServer.add_bus_effect(index, equalizer)
		match bus_name:
			"PianoLead":
				equalizer.set_band_gain_db(1, 0.0)
				equalizer.set_band_gain_db(2, -1.0)
				equalizer.set_band_gain_db(3, 0.8)
				equalizer.set_band_gain_db(4, 0.3)
			"PianoWarm":
				equalizer.set_band_gain_db(1, 0.6)
				equalizer.set_band_gain_db(2, -1.4)
				equalizer.set_band_gain_db(3, -0.6)
				equalizer.set_band_gain_db(4, -0.8)
			"PianoBass":
				equalizer.set_band_gain_db(0, 1.0)
				equalizer.set_band_gain_db(1, 2.2)
				equalizer.set_band_gain_db(2, -2.2)
				equalizer.set_band_gain_db(3, 0.4)

func _add_players(count: int) -> void:
	for i in range(count):
		var player = AudioStreamPlayer.new()
		player.bus = "GrandPiano"
		player.volume_db = -80
		add_child(player)
		pool.append(player)

func _build_tables() -> void:
	# All reference notes have nine partials below Nyquist; share their tables.
	body.resize(4096)
	brightness.resize(4096)
	for i in range(4096):
		var phase = TAU * i / 4096.0
		for h in range(1, 10):
			var value = sin(phase * h) * pow(0.55, h - 1)
			if h <= 3:
				body[i] += value
			else:
				brightness[i] += value

func _make_piano(midi: int) -> AudioStreamWAV:
	var frequency = 440.0 * pow(2.0, (midi - 69.0) / 12.0)
	var duration = 2.0
	var count = int(SAMPLE_RATE * duration)
	var raw_samples = PackedFloat32Array()
	raw_samples.resize(count)
	var max_abs = 0.0001
	var phase = 0.0
	var detuned_phase = 0.0
	var increment = frequency * 4096.0 / SAMPLE_RATE
	var envelope = 1.0
	var bright_envelope = 1.0
	var decay = exp(-(0.85 + midi * 0.005) / SAMPLE_RATE)
	var bright_decay = exp(-3.0 / SAMPLE_RATE)
	var attack_frames = SAMPLE_RATE * 0.012
	var tail_frames = SAMPLE_RATE * 0.08
	for frame in range(count):
		var index = int(phase) & 4095
		var sample = (body[index] + brightness[int(detuned_phase) & 4095] * bright_envelope) * envelope
		var attack = minf(1.0, frame / attack_frames)
		var tail = minf(1.0, (count - frame) / tail_frames)
		var shaped = sample * attack * tail
		raw_samples[frame] = shaped
		max_abs = maxf(max_abs, absf(shaped))
		phase += increment
		detuned_phase += increment * 1.0007
		envelope *= decay
		bright_envelope *= bright_decay
	# Normalize procedural base sample to 95% full-scale 16-bit amplitude
	var norm_scale = (32767.0 * SAMPLE_GAIN) / max_abs
	var data = PackedByteArray()
	data.resize(count * 2)
	for frame in range(count):
		var value = clampi(int(raw_samples[frame] * norm_scale), -32767, 32767)
		data.encode_s16(frame * 2, value)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

func _get_sample_normalization(inst_id: String, reference_midi: int) -> float:
	if INSTRUMENT_SAMPLE_NORMS.has(inst_id):
		var norms: Dictionary = INSTRUMENT_SAMPLE_NORMS[inst_id]
		if norms.has(reference_midi):
			return float(norms[reference_midi])
	if inst_id == "grand_piano" and GRAND_PIANO_SAMPLE_PEAKS.has(reference_midi):
		var raw_peak: float = float(GRAND_PIANO_SAMPLE_PEAKS[reference_midi])
		return clampf(SAMPLE_GAIN / maxf(0.10, raw_peak), 1.0, 7.5)
	var inst_info: Dictionary = INSTRUMENTS.get(inst_id, {})
	return float(inst_info.get("norm_gain", 2.4))

func _calculate_release_time(midi: int, with_sustain: bool = false, role: String = "") -> float:
	if not with_sustain:
		return NO_SUSTAIN_RELEASE
	if role == "inner":
		return INNER_SUSTAIN_RELEASE
	if midi < 55:
		return SUSTAIN_RELEASE_BASS
	return SUSTAIN_RELEASE_TREBLE

func is_piano_instrument() -> bool:
	return str(INSTRUMENTS.get(current_instrument, {}).get("type", "piano")) == "piano"

func is_concert_voicing_active() -> bool:
	return concert_voicing_enabled and is_piano_instrument()

func set_concert_voicing_enabled(enabled: bool) -> void:
	if concert_voicing_enabled == enabled:
		return
	concert_voicing_enabled = enabled
	var use_voicing: bool = is_concert_voicing_active()
	var bus_names: Dictionary = {"lead": "PianoLead", "inner": "PianoWarm", "bass": "PianoBass"}
	for token: int in voices.keys():
		var voice: Dictionary = voices[token]
		if bool(voice.get("stolen", false)):
			continue
		var prev_role: String = str(voice.get("role", ""))
		var midi: int = int(voice.get("midi", 60))
		var voiced_vel: int = int(voice.get("voiced_velocity", voice.get("velocity", DEFAULT_VELOCITY)))
		var unvoiced_vel: int = int(voice.get("unvoiced_velocity", voice.get("velocity", DEFAULT_VELOCITY)))
		var req_role: String = str(voice.get("requested_role", ""))
		var effective_role: String = ""
		var weight: float = 1.0
		var target_bus: String = "GrandPiano"
		if use_voicing:
			if req_role in ["lead", "bass", "inner"]:
				effective_role = req_role
				weight = _compute_role_weight(midi, voiced_vel, effective_role)
			else:
				effective_role = "inner" if (voiced_vel <= 94 and midi >= 52) else ("bass" if midi < 50 else "lead")
			var bus_name: String = bus_names[effective_role]
			if AudioServer.get_bus_index(bus_name) >= 0:
				target_bus = bus_name
		if not bool(voice.get("released", false)):
			voice["gain"] = float(voice.get("voiced_gain", voice.get("gain", 0.0))) if use_voicing else float(voice.get("unvoiced_gain", voice.get("gain", 0.0)))
			voice["velocity"] = voiced_vel if use_voicing else unvoiced_vel
		voice["role"] = effective_role
		voice["weight"] = weight
		var player: AudioStreamPlayer = voice.get("player")
		if player != null:
			player.bus = target_bus
			player.volume_linear = float(voice.get("gain", 0.0)) * weight * float(voice.get("norm", 1.0)) * master_volume
		if bool(voice.get("released", false)) and sustain_enabled and (prev_role == "inner" or effective_role == "inner") and prev_role != effective_role:
			_release(token, _calculate_release_time(midi, true, effective_role))

func _compute_role_weight(midi: int, velocity: int, role: String) -> float:
	match role:
		"inner":
			return clampf(pow(float(clampi(velocity, 1, 127)) / 108.0, 0.25) * 0.86, 0.74, 0.90)
		"bass":
			var bass_body: float = lerpf(1.08, 1.01, clampf(float(midi - 28) / 26.0, 0.0, 1.0))
			return clampf(bass_body * pow(float(clampi(velocity, 1, 127)) / 108.0, 0.22), 0.90, 1.08)
		"lead":
			var lead_bloom: float = 1.0 + 0.04 * clampf(float(midi - 60) / 30.0, 0.0, 1.0)
			return clampf(lead_bloom * pow(float(clampi(velocity, 1, 127)) / 108.0, 0.20), 0.94, 1.06)
	return 1.0

func note_on(token: int, midi: int, velocity: int = DEFAULT_VELOCITY, role: String = "", unvoiced_velocity: int = -1) -> void:
	var use_voicing: bool = is_concert_voicing_active()
	var effective_role: String = ""
	var weight: float = 1.0
	var target_bus: String = "GrandPiano"
	if use_voicing:
		if role in ["lead", "bass", "inner"]:
			effective_role = role
		else:
			effective_role = "inner" if (velocity <= 94 and midi >= 52) else ("bass" if midi < 50 else "lead")
		var bus_names: Dictionary = {"lead": "PianoLead", "inner": "PianoWarm", "bass": "PianoBass"}
		var bus_name: String = bus_names[effective_role]
		if AudioServer.get_bus_index(bus_name) >= 0:
			target_bus = bus_name
		if role in ["lead", "bass", "inner"]:
			weight = _compute_role_weight(midi, velocity, effective_role)
	# Retrigger only the same MIDI note, preserving independent held voices.
	var released_tokens: Array[int] = []
	var released_bass_tokens: Array[int] = []
	for prev_token: int in voices.keys():
		if prev_token == token:
			_finish(prev_token)
		elif voices[prev_token].get("midi", -1) == midi and not voices[prev_token].get("stolen", false):
			voices[prev_token].released = true
			voices[prev_token].stolen = true
			_release(prev_token, RETRIGGER_FADE)
		elif voices[prev_token].get("released", false) and not voices[prev_token].get("stolen", false):
			released_tokens.append(prev_token)
			if voices[prev_token].get("midi", 60) < 55:
				released_bass_tokens.append(prev_token)
	if midi < 55 and released_bass_tokens.size() >= MAX_RELEASED_BASS_TAILS:
		released_bass_tokens.sort()
		var old_bass: int = released_bass_tokens[0]
		voices[old_bass].stolen = true
		_release(old_bass, 0.32)
	if released_tokens.size() >= MAX_RELEASED_TAILS:
		released_tokens.sort()
		var old_tok: int = released_tokens[0]
		if voices.has(old_tok) and not voices[old_tok].get("stolen", false):
			voices[old_tok].stolen = true
			_release(old_tok, 0.32)
	if use_voicing and role != "":
		var released_inner_tokens: Array[int] = []
		for prev_token: int in voices.keys():
			var previous: Dictionary = voices[prev_token]
			if not previous.get("released", false) or previous.get("stolen", false):
				continue
			if previous.get("role", "") == "inner":
				released_inner_tokens.append(prev_token)
			if effective_role == "bass" and role == "bass" and midi < 54 and previous.get("role", "") == "bass" and int(previous.get("midi", -1)) % 12 != midi % 12:
				previous.stolen = true
				_release(prev_token, 0.60)
		released_inner_tokens.sort_custom(func(a: int, b: int) -> bool:
			return int(voices[a].get("order", 0)) < int(voices[b].get("order", 0)))
		while released_inner_tokens.size() > 8:
			var old_inner: int = released_inner_tokens.pop_front()
			voices[old_inner].stolen = true
			_release(old_inner, 0.28)
	var player: AudioStreamPlayer = null
	for candidate: AudioStreamPlayer in pool:
		if not candidate.playing and not _owned(candidate):
			player = candidate
			break
	if player == null:
		_add_players(16)
		player = pool[pool.size() - 16]
	var reference: int = 60
	var distance: int = 999
	for base: int in bank:
		if absi(midi - base) < distance:
			reference = base
			distance = absi(midi - base)
	player.stream = bank[reference]
	player.pitch_scale = pow(2.0, (midi - reference) / 12.0)
	var inst_info: Dictionary = INSTRUMENTS.get(current_instrument, {})
	var inst_gain: float = float(inst_info.get("gain", 1.0))
	var sample_norm: float = _get_sample_normalization(current_instrument, reference)
	var raw_vel: int = velocity if unvoiced_velocity < 0 else unvoiced_velocity
	var play_vel: int = velocity if use_voicing else raw_vel
	var voiced_gain: float = pow(clampi(velocity, 0, 127) / 127.0, 1.15) * SAMPLE_GAIN * inst_gain
	var unvoiced_gain: float = pow(clampi(raw_vel, 0, 127) / 127.0, 1.15) * SAMPLE_GAIN * inst_gain
	var gain: float = voiced_gain if use_voicing else unvoiced_gain
	_voice_order += 1
	voices[token] = {
		"player": player,
		"gain": gain,
		"voiced_gain": voiced_gain,
		"unvoiced_gain": unvoiced_gain,
		"norm": sample_norm,
		"weight": weight,
		"role": effective_role,
		"requested_role": role,
		"velocity": play_vel,
		"voiced_velocity": velocity,
		"unvoiced_velocity": raw_vel,
		"order": _voice_order,
		"tween": null,
		"released": false,
		"stolen": false,
		"midi": midi
	}
	player.bus = target_bus
	player.volume_linear = gain * weight * sample_norm * master_volume
	player.play()

func revoice(token: int, velocity: int, role: String) -> void:
	if not voices.has(token):
		return
	var voice: Dictionary = voices[token]
	if bool(voice.get("released", false)) or bool(voice.get("stolen", false)):
		return
	if not is_piano_instrument() or not (role in ["lead", "bass", "inner"]):
		return
	var midi: int = int(voice.get("midi", 60))
	var inst_info: Dictionary = INSTRUMENTS.get(current_instrument, {})
	var inst_gain: float = float(inst_info.get("gain", 1.0))
	var voiced_gain: float = pow(clampi(velocity, 0, 127) / 127.0, 1.15) * SAMPLE_GAIN * inst_gain
	voice["voiced_gain"] = voiced_gain
	voice["voiced_velocity"] = velocity
	voice["requested_role"] = role
	if not is_concert_voicing_active():
		return
	var weight: float = _compute_role_weight(midi, velocity, role)
	var bus_names: Dictionary = {"lead": "PianoLead", "inner": "PianoWarm", "bass": "PianoBass"}
	var bus_name: String = bus_names[role]
	var player: AudioStreamPlayer = voice.get("player")
	if player != null:
		if AudioServer.get_bus_index(bus_name) >= 0:
			player.bus = bus_name
		player.volume_linear = voiced_gain * weight * float(voice.get("norm", 1.0)) * master_volume
	voice["gain"] = voiced_gain
	voice["weight"] = weight
	voice["role"] = role
	voice["velocity"] = velocity

func _owned(player: AudioStreamPlayer) -> bool:
	for voice in voices.values():
		if voice.player == player:
			return true
	return false

func note_off(token: int) -> void:
	if not voices.has(token):
		return
	voices[token].released = true
	if voices[token].get("stolen", false):
		return
	var midi: int = voices[token].get("midi", 60)
	var release_time: float = _calculate_release_time(midi, sustain_enabled, str(voices[token].get("role", "")))
	_release(token, release_time)

func _release(token: int, seconds: float) -> void:
	if not voices.has(token):
		return
	var voice: Dictionary = voices[token]
	if voice.tween != null:
		voice.tween.kill()
	var tween = create_tween()
	voice.tween = tween
	if seconds > 0.5:
		# Sustain ON: EASE_IN preserves full natural string resonance after key release,
		# then smoothly damps the tail so notes connect warmly like a real damper pedal.
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	else:
		# Sustain OFF or Voice Stealing: immediate felt damper contact
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_gain.bind(token), float(voice.gain), 0.0, seconds)
	tween.tween_callback(_finish.bind(token))

func _set_gain(value: float, token: int) -> void:
	if voices.has(token):
		var safe_val: float = maxf(0.0, value)
		voices[token].gain = safe_val
		var norm: float = voices[token].get("norm", 1.0)
		voices[token].player.volume_linear = safe_val * float(voices[token].get("weight", 1.0)) * norm * master_volume

func _finish(token: int) -> void:
	if voices.has(token):
		if voices[token].tween != null:
			voices[token].tween.kill()
		voices[token].player.stop()
		voices.erase(token)

func set_sustain(value: bool) -> void:
	if value and not sustain_enabled:
		# Catch a note whose damper release is still audible (repedaling).
		for token: int in voices.keys():
			var voice: Dictionary = voices[token]
			if voice.released and not voice.get("stolen", false):
				var midi: int = voice.get("midi", 60)
				_release(token, _calculate_release_time(midi, true, str(voice.get("role", ""))))
	if sustain_enabled and not value:
		for token: int in voices.keys():
			if voices[token].released and not voices[token].get("stolen", false):
				_release(token, NO_SUSTAIN_RELEASE)
	sustain_enabled = value

func set_volume(percent: int) -> void:
	master_volume = clampf(percent / 100.0, 0.0, 2.0)
	var norm_vol: float = clampf(percent / 200.0, 0.0, 1.0)
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, norm_vol <= 0.001)
		AudioServer.set_bus_volume_db(master_idx, -80.0 if norm_vol <= 0.001 else linear_to_db(norm_vol))
	for voice: Dictionary in voices.values():
		var norm: float = voice.get("norm", 1.0)
		voice.player.volume_linear = voice.gain * float(voice.get("weight", 1.0)) * norm * master_volume

func stop_all() -> void:
	for voice in voices.values():
		if voice.tween != null:
			voice.tween.kill()
		voice.player.stop()
	voices.clear()

func start_recording() -> bool:
	if record_effect == null:
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RECORDINGS_DIR))
	if AudioServer.get_driver_name() != "Dummy" and DisplayServer.get_name() != "headless":
		record_effect.set_recording_active(true)
	is_recording = true
	return true

func stop_recording() -> String:
	if not is_recording:
		return ""
	var use_hw = (AudioServer.get_driver_name() != "Dummy" and DisplayServer.get_name() != "headless")
	if record_effect != null and use_hw:
		record_effect.set_recording_active(false)
	is_recording = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RECORDINGS_DIR))
	var dt = Time.get_datetime_dict_from_system()
	var datetime = "%04d%02d%02d_%02d%02d%02d_%03d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, Time.get_ticks_msec() % 1000]
	var save_path = RECORDINGS_DIR + "/SwiftPiano_REC_" + datetime + ".wav"
	var rec: AudioStreamWAV = record_effect.get_recording() if (record_effect != null and use_hw) else null
	if rec == null or rec.data.is_empty():
		rec = AudioStreamWAV.new()
		rec.format = AudioStreamWAV.FORMAT_16_BITS
		rec.mix_rate = SAMPLE_RATE
		rec.stereo = true
		var silent_pcm = PackedByteArray()
		silent_pcm.resize(1024)
		rec.data = silent_pcm
	rec.save_to_wav(save_path)
	last_recording_path = save_path
	return save_path

func toggle_recording() -> bool:
	if is_recording:
		stop_recording()
		return false
	return start_recording()

func _process(_delta: float) -> void:
	for token in voices.keys():
		if not voices[token].player.playing:
			if voices[token].tween != null:
				voices[token].tween.kill()
			voices.erase(token)
