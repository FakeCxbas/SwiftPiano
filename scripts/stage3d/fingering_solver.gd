class_name FingeringSolver
extends RefCounted

enum FingerState { IDLE = 0, ANTICIPATING = 1, STRIKING = 2 }

class FingerAssignment extends RefCounted:
	var finger_index: int = 0
	var midi: int = -1
	var state: int = FingerState.IDLE
	var weight: float = 0.0
	var is_black: bool = false
	var target_pos: Vector3 = Vector3.ZERO

class HandPlan extends RefCounted:
	var side: int = 0
	var wrist_target_x: float = 0.0
	var black_ratio: float = 0.0
	var active_count: int = 0
	var anticipating_count: int = 0
	var fingers: Array[FingerAssignment] = []

const LOOKAHEAD_SEC: float = 0.26
const IDLE_LOOKAHEAD_SEC: float = 0.45
const WRIST_MIN_X: float = -0.565
const WRIST_MAX_X: float = 0.565
const DEFAULT_WRIST_X: Array[float] = [-0.18, 0.18]
const FINGER_REST_X_LEFT: Array[float] = [0.052, 0.022, 0.0, -0.020, -0.042]
const FINGER_REST_X_RIGHT: Array[float] = [-0.052, -0.022, 0.0, 0.020, 0.042]

var _last_finger_for_midi: Array[Dictionary] = [{}, {}]


func solve(key_map: KeyMap3D, pressed: PackedByteArray, depth: PackedFloat32Array, notes: Array, note_cursor: int, playback_time: float, current_wrist_x: Array[float]) -> Array[HandPlan]:
	var active: Array[Array] = [[], []]
	var upcoming: Array[Dictionary] = [{}, {}]
	var idle_upcoming: Array[Dictionary] = [{}, {}]
	for midi: int in range(21, 109):
		var key_index: int = key_map.get_key_index(midi)
		if key_index >= 0 and key_index < pressed.size() and pressed[key_index] != 0:
			active[0 if midi < 60 else 1].append(midi)
	for index: int in range(maxi(note_cursor, 0), notes.size()):
		var note: Variant = notes[index]
		var start: float = float(note.start)
		if start > playback_time + IDLE_LOOKAHEAD_SEC:
			break
		if start <= playback_time:
			continue
		var midi: int = int(note.midi)
		if midi < 21 or midi > 108:
			continue
		var side: int = 0 if midi < 60 else 1
		if not idle_upcoming[side].has(midi) or start < float(idle_upcoming[side][midi]):
			idle_upcoming[side][midi] = start
		if start <= playback_time + LOOKAHEAD_SEC and not active[side].has(midi):
			if not upcoming[side].has(midi) or start < float(upcoming[side][midi]):
				upcoming[side][midi] = start
	_rebalance_registers(active, upcoming)
	var plans: Array[HandPlan] = []
	for side: int in range(2):
		var plan: HandPlan = HandPlan.new()
		plan.side = side
		var current_x: float = current_wrist_x[side] if side < current_wrist_x.size() else DEFAULT_WRIST_X[side]
		current_x = clampf(current_x, WRIST_MIN_X, WRIST_MAX_X)
		plan.wrist_target_x = current_x
		var centroid: float = 0.0
		var total_weight: float = 0.0
		for midi: int in active[side]:
			centroid += key_map.get_key_rest_position(midi).x
			total_weight += 1.0
		var future_midis: Array = upcoming[side].keys()
		future_midis.sort()
		for midi: int in future_midis:
			centroid += key_map.get_key_rest_position(midi).x * 0.45
			total_weight += 0.45
		if total_weight > 0.0:
			plan.wrist_target_x = clampf(centroid / total_weight, WRIST_MIN_X, WRIST_MAX_X)
		elif not idle_upcoming[side].is_empty():
			var idle_centroid: float = 0.0
			for midi: int in idle_upcoming[side]:
				idle_centroid += key_map.get_key_rest_position(midi).x
			idle_centroid /= float(idle_upcoming[side].size())
			plan.wrist_target_x = clampf(lerpf(current_x, idle_centroid, 0.65), WRIST_MIN_X, WRIST_MAX_X)
		for finger_index: int in range(5):
			var assignment: FingerAssignment = FingerAssignment.new()
			assignment.finger_index = finger_index
			plan.fingers.append(assignment)
		var strikes: Dictionary = _assign(key_map, active[side], side, plan.wrist_target_x, {})
		var anticipations: Dictionary = _assign(key_map, future_midis, side, plan.wrist_target_x, strikes)
		var offsets: Array[float] = FINGER_REST_X_LEFT if side == 0 else FINGER_REST_X_RIGHT
		var anchor_sum: float = 0.0
		var anchor_weight: float = 0.0
		var next_retention: Dictionary = {}
		var black_weight: float = 0.0
		var assigned_weight: float = 0.0
		for midi: int in strikes:
			var finger: int = int(strikes[midi])
			var assignment: FingerAssignment = plan.fingers[finger]
			assignment.midi = midi
			assignment.state = FingerState.STRIKING
			assignment.weight = 1.0
			assignment.is_black = key_map.is_black_key(midi)
			var key_index: int = key_map.get_key_index(midi)
			var key_depth: float = clampf(depth[key_index], 0.0, 1.0) if key_index >= 0 and key_index < depth.size() else 0.0
			assignment.target_pos = key_map.get_strike_contact_point(midi, key_depth, finger == 0)
			plan.active_count += 1
			assigned_weight += 1.0
			black_weight += 1.0 if assignment.is_black else 0.0
			anchor_sum += key_map.get_key_rest_position(midi).x - offsets[finger] * 0.70
			anchor_weight += 1.0
			next_retention[midi] = finger
		for midi: int in anticipations:
			var finger: int = int(anticipations[midi])
			var assignment: FingerAssignment = plan.fingers[finger]
			assignment.midi = midi
			assignment.state = FingerState.ANTICIPATING
			assignment.weight = clampf(1.0 - (float(upcoming[side][midi]) - playback_time) / LOOKAHEAD_SEC, 0.15, 1.0)
			assignment.is_black = key_map.is_black_key(midi)
			assignment.target_pos = key_map.get_hover_point(midi, finger == 0)
			plan.anticipating_count += 1
			assigned_weight += 0.5
			black_weight += 0.5 if assignment.is_black else 0.0
			anchor_sum += (key_map.get_key_rest_position(midi).x - offsets[finger] * 0.70) * 0.45
			anchor_weight += 0.45
			next_retention[midi] = finger
		if anchor_weight > 0.0:
			plan.wrist_target_x = clampf(anchor_sum / anchor_weight, WRIST_MIN_X, WRIST_MAX_X)
		plan.black_ratio = black_weight / assigned_weight if assigned_weight > 0.0 else 0.0
		_last_finger_for_midi[side] = next_retention
		plans.append(plan)
	return plans


func _rebalance_registers(active: Array[Array], upcoming: Array[Dictionary]) -> void:
	for busy: int in range(2):
		var empty_side: int = 1 - busy
		if not active[empty_side].is_empty() or not upcoming[empty_side].is_empty():
			continue
		var combined: Array[int] = []
		for m: int in active[busy]:
			if not combined.has(m):
				combined.append(m)
		for m: int in upcoming[busy].keys():
			if not combined.has(m):
				combined.append(m)
		if combined.size() < 2:
			continue
		combined.sort()
		var span: int = combined.back() - combined.front()
		if span <= 14:
			continue
		var split_midi: int = int(floor(float(combined.front() + combined.back()) * 0.5))
		var kept_active: Array = []
		for m: int in active[busy]:
			if (busy == 1 and m <= split_midi) or (busy == 0 and m >= split_midi):
				active[empty_side].append(m)
			else:
				kept_active.append(m)
		active[busy] = kept_active
		active[empty_side].sort()
		var moved_up: Array[int] = []
		for m: int in upcoming[busy].keys():
			if (busy == 1 and m <= split_midi) or (busy == 0 and m >= split_midi):
				if not active[empty_side].has(m):
					upcoming[empty_side][m] = upcoming[busy][m]
				moved_up.append(m)
		for m: int in moved_up:
			upcoming[busy].erase(m)


# A five-bit dynamic program maximizes cardinality before minimizing travel.
# Ascending MIDI visits ascending anatomical rank, so fingers cannot cross.
func _assign(key_map: KeyMap3D, midis: Array, side: int, wrist_x: float, fixed: Dictionary) -> Dictionary:
	var states: Dictionary = {0: {"cost": 0.0, "pairs": {}}}
	for midi: int in midis:
		var next_states: Dictionary = states.duplicate()
		for mask: int in states:
			var previous: Dictionary = states[mask]
			for rank: int in range(5):
				# All earlier selected notes must occupy strictly lower ranks.
				if mask >= (1 << rank) or not _fits_fixed(midi, rank, side, fixed):
					continue
				var finger: int = 4 - rank if side == 0 else rank
				var cost: float = float(previous["cost"]) + _finger_cost(key_map, midi, finger, side, wrist_x, fixed)
				var next_mask: int = mask | (1 << rank)
				if next_states.has(next_mask) and float(next_states[next_mask]["cost"]) <= cost:
					continue
				var pairs: Dictionary = previous["pairs"].duplicate()
				pairs[midi] = finger
				next_states[next_mask] = {"cost": cost, "pairs": pairs}
		states = next_states
	var best_pairs: Dictionary = {}
	var best_cost: float = INF
	for mask: int in states:
		var candidate: Dictionary = states[mask]
		var pairs: Dictionary = candidate["pairs"]
		var cost: float = float(candidate["cost"])
		if pairs.size() > best_pairs.size() or (pairs.size() == best_pairs.size() and cost < best_cost):
			best_pairs = pairs
			best_cost = cost
	return best_pairs


func _fits_fixed(midi: int, rank: int, side: int, fixed: Dictionary) -> bool:
	for fixed_midi: int in fixed:
		var finger: int = int(fixed[fixed_midi])
		var fixed_rank: int = 4 - finger if side == 0 else finger
		if rank == fixed_rank or (midi < fixed_midi and rank >= fixed_rank) or (midi > fixed_midi and rank <= fixed_rank):
			return false
	return true


func _finger_cost(key_map: KeyMap3D, midi: int, finger: int, side: int, wrist_x: float, fixed: Dictionary) -> float:
	var offsets: Array[float] = FINGER_REST_X_LEFT if side == 0 else FINGER_REST_X_RIGHT
	var key_x: float = key_map.get_key_rest_position(midi).x
	var cost: float = absf(key_x - wrist_x - offsets[finger])
	if finger == 0 and key_map.is_black_key(midi):
		for inner_finger: int in range(1, 4):
			var rank: int = 4 - inner_finger if side == 0 else inner_finger
			if _fits_fixed(midi, rank, side, fixed) and absf(key_x - wrist_x - offsets[inner_finger]) <= 0.07:
				cost += 0.035
				break
	if int(_last_finger_for_midi[side].get(midi, -1)) == finger:
		cost -= 0.012
	return cost
