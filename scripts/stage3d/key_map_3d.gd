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
const KEY_HINGE_Z: float = -0.075
const WHITE_TILT_DEG: float = 5.2
const BLACK_TILT_DEG: float = 6.5
const WHITE_SINK: float = 0.0012
const BLACK_SINK: float = 0.0025
const FINGER_PAD_RADIUS: float = 0.0082
const FINGER_TIP_FORWARD: float = 0.0115
const FINGER_HALF_WIDTH: float = 0.0085
const WHITE_CONTACT_Z: float = 0.040
const WHITE_THUMB_CONTACT_Z: float = 0.056
const BLACK_CONTACT_Z: float = -0.012
const BLACK_THUMB_CONTACT_Z: float = 0.006

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
	var d: float = clampf(depth_01, -0.06, 1.12)
	var angle: float = deg_to_rad(BLACK_TILT_DEG if black else WHITE_TILT_DEG) * d
	var rot: Basis = Basis(Vector3.RIGHT, angle)
	var rest: Vector3 = get_key_rest_position(midi)
	var pivot: Vector3 = Vector3(rest.x, rest.y, KEY_HINGE_Z)
	var sink: float = (BLACK_SINK if black else WHITE_SINK) * d
	var pos: Vector3 = pivot + rot * (rest - pivot) - Vector3(0.0, sink, 0.0)
	return Transform3D(rot, pos)

func get_key_top_y(midi: int, z: float, depth_01: float) -> float:
	var d: float = clampf(depth_01, -0.06, 1.12)
	if is_black_key(midi):
		var cz: float = clampf(z, KEY_HINGE_Z, BLACK_Z + BLACK_LENGTH * 0.5)
		return (BLACK_Y + BLACK_HEIGHT * 0.5) - (sin(deg_to_rad(BLACK_TILT_DEG) * d) * (cz - KEY_HINGE_Z) + BLACK_SINK * d)
	var cz: float = clampf(z, KEY_HINGE_Z, WHITE_LENGTH * 0.5)
	return (WHITE_HEIGHT * 0.5) - (sin(deg_to_rad(WHITE_TILT_DEG) * d) * (cz - KEY_HINGE_Z) + WHITE_SINK * d)

func get_surface_ceiling_y(x: float, z: float, depth: PackedFloat32Array = PackedFloat32Array(), half_x: float = FINGER_HALF_WIDTH, front_z: float = FINGER_TIP_FORWARD, back_z: float = 0.006) -> float:
	var ceiling: float = -0.0135
	var z_min: float = z - front_z
	var z_max: float = z + back_z
	var depth_count: int = depth.size()
	for index: int in range(KEY_COUNT):
		var midi: int = FIRST_MIDI + index
		var black: bool = is_black_key(midi)
		var key_half_w: float = BLACK_WIDTH * 0.5 if black else WHITE_WIDTH * 0.5
		var rest: Vector3 = _rest_positions[index]
		if absf(rest.x - x) > key_half_w + half_x:
			continue
		var key_front_z: float = (BLACK_Z + BLACK_LENGTH * 0.5) if black else (WHITE_LENGTH * 0.5)
		if z_min <= key_front_z and z_max >= KEY_HINGE_Z:
			var d: float = depth[index] if index < depth_count else 0.0
			var sample_z: float = clampf(z_min, KEY_HINGE_Z, key_front_z)
			ceiling = maxf(ceiling, get_key_top_y(midi, sample_z, d))
	return ceiling

func get_strike_contact_point(midi: int, depth_01: float, is_thumb: bool = false) -> Vector3:
	var rest: Vector3 = get_key_rest_position(midi)
	var black: bool = is_black_key(midi)
	var contact_z: float = (BLACK_THUMB_CONTACT_Z if is_thumb else BLACK_CONTACT_Z) if black else (WHITE_THUMB_CONTACT_Z if is_thumb else WHITE_CONTACT_Z)
	var surface_y: float = get_key_top_y(midi, contact_z, clampf(depth_01, 0.0, 1.12))
	return Vector3(rest.x, surface_y + FINGER_PAD_RADIUS, contact_z)

func get_hover_point(midi: int, is_thumb: bool = false) -> Vector3:
	return get_strike_contact_point(midi, 0.0, is_thumb) + Vector3(0.0, 0.016, 0.002)
