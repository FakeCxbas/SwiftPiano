extends RefCounted
## Physical US-QWERTY positions are independent of Caps Lock and keyboard locale.
const MIN_MIDI = 21
const MAX_MIDI = 108
const WHITES = "1234567890qwertyuiopasdfghjklzxcvbnm"
const BLACKS = "!@$%^*(QWETYIOPSDGHJLZCVB"
const BLACK_PHYSICAL = "1245689qwetyiopsdghjlzcvb"
const LOW_KEYS = [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12, KEY_QUOTELEFT, KEY_MINUS, KEY_EQUAL]
const LOW_LABELS = ["·1", "·2", "·3", "·4", "·5", "·6", "·7", "·8", "·9", "·0", "·q", "·w", "·e", "·r", "·t"]
const HIGH_KEYS = [KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_BACKSLASH, KEY_SEMICOLON, KEY_APOSTROPHE, KEY_COMMA, KEY_PERIOD, KEY_SLASH, KEY_INSERT, KEY_DELETE, KEY_PAGEUP, KEY_PAGEDOWN]
const HIGH_LABELS = ["·y", "·u", "·i", "·o", "·p", "·a", "·s", "·d", "·f", "·g", "·h", "·j"]
const ROBLOX_CTRL_LOW = {
	KEY_1: 21,
	KEY_2: 22,
	KEY_3: 23,
	KEY_4: 24,
	KEY_5: 25,
	KEY_6: 26,
	KEY_7: 27,
	KEY_8: 28,
	KEY_9: 29,
	KEY_0: 30,
	KEY_Q: 31,
	KEY_W: 32,
	KEY_E: 33,
	KEY_R: 34,
	KEY_T: 35
}
const ROBLOX_CTRL_HIGH = {
	KEY_Y: 97,
	KEY_U: 98,
	KEY_I: 99,
	KEY_O: 100,
	KEY_P: 101,
	KEY_A: 102,
	KEY_S: 103,
	KEY_D: 104,
	KEY_F: 105,
	KEY_G: 106,
	KEY_H: 107,
	KEY_J: 108
}
const SHIFT_ALIASES = {
	"R": 59,
	"U": 64,
	"A": 71,
	"F": 76,
	"K": 83,
	"X": 88,
	"N": 95,
	"M": 96,
	"#": 40,
	"&": 47,
	")": 52,
}
const DEMO = "6 [er] [er] 3 [er] [er] 6 [er] [er] [wt] 8 [wt] [wt] [qe] 8 [qe] [qe] 6 [er] [er] 3 [er] [er] 6 [er] [er] [wt] 8 [wt] [wt] [qe] 8 [qe] [qe]"

static func is_black(midi: int) -> bool:
	return midi % 12 in [1, 3, 6, 8, 10]

static func mapping() -> Dictionary:
	var result: Dictionary = {}
	var w = 0
	var b = 0
	for midi in range(36, 97):
		if is_black(midi):
			result[BLACKS[b]] = midi
			b += 1
		else:
			result[WHITES[w]] = midi
			w += 1
	return result

static func parser_mapping() -> Dictionary:
	var result = mapping()
	for alias in SHIFT_ALIASES:
		result[alias] = SHIFT_ALIASES[alias]
	return result

static func labels() -> Dictionary:
	var result: Dictionary = {}
	var map = mapping()
	for character in map:
		result[map[character]] = character
	for i in range(LOW_KEYS.size()):
		result[21 + i] = LOW_LABELS[i]
	for i in range(HIGH_KEYS.size()):
		result[97 + i] = HIGH_LABELS[i]
	return result

static func physical(event: InputEventKey) -> int:
	return event.physical_keycode if event.physical_keycode != 0 else event.keycode

static func is_note_key(code: int) -> bool:
	return (code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9)

static func manual_note(code: int, shifted: bool, ctrl: bool = false) -> int:
	if ctrl:
		if ROBLOX_CTRL_LOW.has(code):
			return ROBLOX_CTRL_LOW[code]
		if ROBLOX_CTRL_HIGH.has(code):
			return ROBLOX_CTRL_HIGH[code]
	var low = LOW_KEYS.find(code)
	if low >= 0:
		return 21 + low
	var high = HIGH_KEYS.find(code)
	if high >= 0:
		return 97 + high
	if code > 0 and code < 128:
		var raw_char = String.chr(code)
		if SHIFT_ALIASES.has(raw_char):
			return SHIFT_ALIASES[raw_char]
	if not is_note_key(code):
		return -1
	var character = String.chr(code).to_lower()
	var map = mapping()
	if shifted:
		var index = BLACK_PHYSICAL.find(character)
		if index >= 0:
			return map.get(BLACKS[index], -1)
	return map.get(character, -1)

