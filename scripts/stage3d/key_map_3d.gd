class_name KeyMap3D
extends RefCounted
## Metric geometry shared by the keyboard, fingering and hand targets.

const FIRST_MIDI: int = 21
const LAST_MIDI: int = 108
const KEY_COUNT: int = 88
const WHITE_STEP: float = 0.0232
const WHITE_WIDTH: float = 0.0214
const WHITE_HEIGHT: float = 0.022
const WHITE_LENGTH: float = 0.150
const BLACK_WIDTH: float = 0.0128
const BLACK_HEIGHT: float = 0.032
const BLACK_LENGTH: float = 0.096
const BLACK_Y: float = 0.027
const BLACK_Z: float = -0.027

var _rest_positions: Array[Vector3] = []
var _black_flags: PackedByteArray = PackedByteArray()

func _init() -> void:
	_black_flags.resize(KEY_COUNT)
	var white_index: int = 0
	for midi: int in range(FIRST_MIDI, LAST_MIDI + 1):
		var black: bool = midi % 12 in [1, 3, 6, 8, 10]
		_black_flags[midi - FIRST_MIDI] = int(black)
		var x: float = (float(white_index) - 25.5 - (0.5 if black else 0.0)) * WHITE_STEP
		_rest_positions.append(Vector3(x, BLACK_Y if black else 0.0, BLACK_Z if black else 0.0))
		if not black:
			white_index += 1

func is_black_key(midi: int) -> bool:
	return _black_flags[get_key_index(midi)] != 0

func get_key_index(midi: int) -> int:
	return clampi(midi - FIRST_MIDI, 0, KEY_COUNT - 1)

func get_key_rest_position(midi: int) -> Vector3:
	return _rest_positions[get_key_index(midi)]

func get_key_dimensions(midi: int) -> Vector3:
	return Vector3(BLACK_WIDTH, BLACK_HEIGHT, BLACK_LENGTH) if is_black_key(midi) else Vector3(WHITE_WIDTH, WHITE_HEIGHT, WHITE_LENGTH)

func get_key_pressed_transform(midi: int, depth_01: float) -> Transform3D:
	var black: bool = is_black_key(midi)
	var rotation: Basis = Basis.IDENTITY if black else Basis(Vector3.RIGHT, deg_to_rad(-3.2) * depth_01)
	return Transform3D(rotation, get_key_rest_position(midi) - Vector3(0.0, depth_01 * (0.009 if black else 0.007), 0.0))

func get_strike_contact_point(midi: int, depth_01: float, is_thumb: bool = false) -> Vector3:
	var rest: Vector3 = get_key_rest_position(midi)
	if is_black_key(midi):
		return Vector3(rest.x, 0.041 - depth_01 * 0.009, 0.006 if is_thumb else -0.012)
	return Vector3(rest.x, 0.009 - depth_01 * 0.007, 0.052 if is_thumb else 0.033)

func get_hover_point(midi: int, is_thumb: bool = false) -> Vector3:
	return get_strike_contact_point(midi, 0.0, is_thumb) + Vector3(0.0, 0.016, 0.002)
