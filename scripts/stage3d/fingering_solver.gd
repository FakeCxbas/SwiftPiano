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

const LOOKAHEAD_SEC: float = 0.28
const IDLE_LOOKAHEAD_SEC: float = 0.45
const WRIST_MIN_X: float = -0.565
const WRIST_MAX_X: float = 0.565
const DEFAULT_WRIST_X: Array[float] = [-0.18, 0.18]
const FINGER_REST_X_LEFT: Array[float] = [0.052, 0.022, 0.0, -0.020, -0.042]
const FINGER_REST_X_RIGHT: Array[float] = [-0.052, -0.022, 0.0, 0.020, 0.042]

var _last_finger_for_midi: Array[Dictionary] = [{}, {}]
var _held_finger_for_midi: Array[Dictionary] = [{}, {}]
var _last_active_midi: Array[int] = [-1, -1]
var _last_active_finger: Array[int] = [-1, -1]


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
	for side: int in range(2):
		active[side].sort()
	_rebalance_registers(active, upcoming)
	var plans: Array[HandPlan] = []
	for side: int in range(2):
		var plan: HandPlan = HandPlan.new()
		plan.side = side
		var current_x: float = current_wrist_x[side] if side < current_wrist_x.size() else DEFAULT_WRIST_X[side]
		current_x = clampf(current_x, WRIST_MIN_X, WRIST_MAX_X)
		plan.wrist_target_x = current_x
		var has_active: bool = not active[side].is_empty()
		var centroid: float = 0.0
		var total_weight: float = 0.0
		for midi: int in active[side]:
			centroid += key_map.get_key_rest_position(midi).x
			total_weight += 1.0
		var future_midis: Array = upcoming[side].keys()
		future_midis.sort()
		for midi: int in future_midis:
			var time_until: float = float(upcoming[side][midi]) - playback_time
			var future_weight: float = (0.18 if time_until <= 0.12 else 0.08) if has_active else (0.75 if time_until <= 0.12 else 0.35)
			centroid += key_map.get_key_rest_position(midi).x * future_weight
			total_weight += future_weight
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
		var eval_wrist_x: float = plan.wrist_target_x
		if active[side].size() == 1 and absf(plan.wrist_target_x - current_x) <= 0.085:
			eval_wrist_x = lerpf(plan.wrist_target_x, current_x, 0.65)
		var strikes: Dictionary = _assign(key_map, active[side], side, eval_wrist_x, {})
		var anticipations: Dictionary = _assign(key_map, future_midis, side, plan.wrist_target_x, strikes)
		var offsets: Array[float] = FINGER_REST_X_LEFT if side == 0 else FINGER_REST_X_RIGHT
		var anchor_sum: float = 0.0
		var anchor_weight: float = 0.0
		var next_retention: Dictionary = {}
		var black_weight: float = 0.0
		var assigned_weight: float = 0.0
		var highest_strike_midi: int = -1
		var highest_strike_finger: int = -1
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
			anchor_sum += key_map.get_key_rest_position(midi).x - offsets[finger]
			anchor_weight += 1.0
			next_retention[midi] = finger
			if midi > highest_strike_midi:
				highest_strike_midi = midi
				highest_strike_finger = finger
		if highest_strike_midi >= 0:
			_last_active_midi[side] = highest_strike_midi
			_last_active_finger[side] = highest_strike_finger
		for midi: int in anticipations:
			var finger: int = int(anticipations[midi])
			var assignment: FingerAssignment = plan.fingers[finger]
			assignment.midi = midi
			assignment.state = FingerState.ANTICIPATING
			var time_until: float = float(upcoming[side][midi]) - playback_time
			assignment.weight = clampf(1.0 - time_until / LOOKAHEAD_SEC, 0.15, 1.0)
			assignment.is_black = key_map.is_black_key(midi)
			assignment.target_pos = key_map.get_hover_point(midi, finger == 0)
			plan.anticipating_count += 1
			assigned_weight += 0.5
			black_weight += 0.5 if assignment.is_black else 0.0
			var ant_anchor_weight: float = (0.18 if time_until <= 0.12 else 0.08) if has_active else (0.75 if time_until <= 0.12 else 0.35)
			anchor_sum += (key_map.get_key_rest_position(midi).x - offsets[finger] * (1.0 if has_active else 0.85)) * ant_anchor_weight
			anchor_weight += ant_anchor_weight
			next_retention[midi] = finger
		if anchor_weight > 0.0:
			plan.wrist_target_x = clampf(anchor_sum / anchor_weight, WRIST_MIN_X, WRIST_MAX_X)
		if plan.fingers[0].state == FingerState.STRIKING and plan.fingers[0].midi >= 21:
			var thumb_ideal_x: float = key_map.get_key_rest_position(plan.fingers[0].midi).x - offsets[0]
			plan.wrist_target_x = clampf(clampf(plan.wrist_target_x, thumb_ideal_x - 0.024, thumb_ideal_x + 0.024), WRIST_MIN_X, WRIST_MAX_X)
		plan.black_ratio = black_weight / assigned_weight if assigned_weight > 0.0 else 0.0
		_held_finger_for_midi[side] = strikes.duplicate()
		_last_finger_for_midi[side] = next_retention
		if active[side].is_empty() and upcoming[side].is_empty() and idle_upcoming[side].is_empty():
			_last_finger_for_midi[side].clear()
			_last_active_midi[side] = -1
			_last_active_finger[side] = -1
		plans.append(plan)
	return plans


func _midi_span(midis: Array) -> int:
	if midis.size() < 2:
		return 0
	return int(midis.back()) - int(midis.front())


func _trim_playable_cluster(midis: Array, side: int) -> Array:
	var sorted_midis: Array[int] = []
	for m: int in midis:
		if not sorted_midis.has(m):
			sorted_midis.append(m)
	sorted_midis.sort()
	if sorted_midis.size() <= 1:
		return sorted_midis
	var best_win: Array[int] = []
	for i: int in range(sorted_midis.size()):
		var start_m: int = sorted_midis[i]
		var win: Array[int] = []
		for m: int in sorted_midis:
			if m >= start_m and m <= start_m + 14:
				win.append(m)
		if win.size() > 5:
			win = [win[0], win[1], win[int(win.size() / 2)], win[win.size() - 2], win[win.size() - 1]]
		if win.size() > best_win.size() or (win.size() == best_win.size() and not best_win.is_empty() and ((side == 1 and win[0] >= best_win[0]) or (side == 0 and win.back() <= best_win.back()))):
			best_win = win
	return best_win


func _rebalance_registers(active: Array[Array], upcoming: Array[Dictionary]) -> void:
	var all_active: Array[int] = []
	for side: int in range(2):
		for m: int in active[side]:
			if not all_active.has(m):
				all_active.append(m)
	all_active.sort()
	if all_active.size() >= 2:
		var overloaded: bool = active[0].size() > 5 or active[1].size() > 5 or _midi_span(active[0]) > 12 or _midi_span(active[1]) > 12
		var one_empty_wide: bool = (active[0].is_empty() and upcoming[0].is_empty() and _midi_span(all_active) > 12) or (active[1].is_empty() and upcoming[1].is_empty() and _midi_span(all_active) > 12)
		if overloaded or one_empty_wide:
			var best_k: int = 1
			var best_score: float = -INF
			for k: int in range(1, all_active.size()):
				var span_l: int = all_active[k - 1] - all_active[0]
				var span_r: int = all_active[all_active.size() - 1] - all_active[k]
				var gap: int = all_active[k] - all_active[k - 1]
				var mid_pitch: float = 0.5 * float(all_active[k - 1] + all_active[k])
				var score: float = float(gap) * 2.5 - (maxf(0.0, float(span_l - 12)) + maxf(0.0, float(span_r - 12))) * 3.0 - float(maxi(0, k - 5) + maxi(0, all_active.size() - k - 5)) * 8.0 - absf(mid_pitch - 60.0) * 0.15
				if score > best_score:
					best_score = score
					best_k = k
			active[0] = all_active.slice(0, best_k)
			active[1] = all_active.slice(best_k)
	elif all_active.is_empty():
		for busy: int in range(2):
			var empty_side: int = 1 - busy
			if not active[empty_side].is_empty() or not upcoming[empty_side].is_empty():
				continue
			var combined: Array[int] = []
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
			var moved_up: Array[int] = []
			for m: int in upcoming[busy].keys():
				if (busy == 1 and m <= split_midi) or (busy == 0 and m >= split_midi):
					upcoming[empty_side][m] = upcoming[busy][m]
					moved_up.append(m)
			for m: int in moved_up:
				upcoming[busy].erase(m)
	for side: int in range(2):
		if active[side].size() > 5 or _midi_span(active[side]) > 14:
			active[side] = _trim_playable_cluster(active[side], side)


# A five-bit dynamic program maximizes cardinality before minimizing travel.
# Ascending MIDI visits ascending anatomical rank, so fingers cannot cross.
func _assign(key_map: KeyMap3D, midis: Array, side: int, wrist_x: float, fixed: Dictionary) -> Dictionary:
	var states: Dictionary = {0: {"cost": 0.0, "pairs": {}}}
	var is_thumb_chord: bool = false
	var inner_midi: int = -1
	if midis.size() >= 2 and fixed.is_empty():
		is_thumb_chord = midis.size() >= 3 or (int(midis.back()) - int(midis.front())) >= 5
		inner_midi = int(midis.front()) if side == 1 else int(midis.back())
	for midi: int in midis:
		var next_states: Dictionary = states.duplicate()
		var prefer_thumb: bool = is_thumb_chord and midi == inner_midi
		for mask: int in states:
			var previous: Dictionary = states[mask]
			for rank: int in range(5):
				# All earlier selected notes must occupy strictly lower ranks.
				if mask >= (1 << rank) or not _fits_fixed(midi, rank, side, fixed):
					continue
				var finger: int = 4 - rank if side == 0 else rank
				var cost: float = float(previous["cost"]) + _finger_cost(key_map, midi, finger, side, wrist_x, fixed, prefer_thumb)
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


func _finger_cost(key_map: KeyMap3D, midi: int, finger: int, side: int, wrist_x: float, fixed: Dictionary, prefer_thumb: bool = false) -> float:
	var offsets: Array[float] = FINGER_REST_X_LEFT if side == 0 else FINGER_REST_X_RIGHT
	var key_x: float = key_map.get_key_rest_position(midi).x
	var cost: float = absf(key_x - wrist_x - offsets[finger])
	var thumb_black_avoid: bool = false
	if finger == 0 and key_map.is_black_key(midi):
		for inner_finger: int in range(1, 4):
			var rank: int = 4 - inner_finger if side == 0 else inner_finger
			if _fits_fixed(midi, rank, side, fixed) and absf(key_x - wrist_x - offsets[inner_finger]) <= 0.07:
				cost += 0.035
				thumb_black_avoid = true
				break
	if finger == 0 and prefer_thumb and not thumb_black_avoid:
		cost -= 0.018
	if int(_held_finger_for_midi[side].get(midi, -1)) == finger:
		cost -= 0.15
	elif int(_last_finger_for_midi[side].get(midi, -1)) == finger:
		cost -= 0.012
	if not _held_finger_for_midi[side].has(midi) and _last_active_midi[side] >= 0 and _last_active_midi[side] != midi and _last_active_finger[side] >= 0:
		if _last_active_finger[side] == finger:
			cost += 0.032
		var rank: int = 4 - finger if side == 0 else finger
		var prev_rank: int = 4 - _last_active_finger[side] if side == 0 else _last_active_finger[side]
		if (midi > _last_active_midi[side] and rank > prev_rank) or (midi < _last_active_midi[side] and rank < prev_rank):
			cost -= 0.010
	return cost
