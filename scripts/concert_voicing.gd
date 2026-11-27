class_name ConcertVoicing
extends RefCounted

const ROLE_LEAD: String = "lead"
const ROLE_BASS: String = "bass"
const ROLE_INNER: String = "inner"


static func build_step_voicing(steps: Array[Dictionary], extra_transposition: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var metadata: Array[Dictionary] = []
	for step: Dictionary in steps:
		var transpose_value: Variant = step.get("transposition", 0)
		var transposition: int = (0 if transpose_value == null else int(transpose_value)) + extra_transposition
		var candidates: Array[int] = []
		for raw_note: Variant in step.get("notes", []):
			candidates.append(int(raw_note))
		candidates.sort()
		var raw_sorted: Array[int] = []
		var effective: Array[int] = []
		for raw_note: int in candidates:
			var p: int = raw_note + transposition
			if p >= 21 and p <= 108:
				raw_sorted.append(raw_note)
				effective.append(p)
		metadata.append({
			"raw_sorted": raw_sorted,
			"pitches": effective,
			"top": effective[-1] if not effective.is_empty() else -1,
			"count": effective.size(),
		})

	for i: int in range(steps.size()):
		var raw_sorted: Array[int] = metadata[i]["raw_sorted"]
		var pitches: Array[int] = metadata[i]["pitches"]
		var k: int = pitches.size()
		var velocities: Dictionary = {}
		var roles: Dictionary = {}
		if k > 0:
			var top: int = pitches[k - 1]
			var window_tops: Array[int] = []
			var solo_top_counts: Dictionary = {}
			var bounces_by_pitch: Dictionary = {}
			var lower_distinct_by_pitch: Dictionary = {}
			var prev_valid_top: int = -1
			var prev_valid_count: int = 0
			for neighbor: int in range(maxi(0, i - 6), mini(steps.size(), i + 7)):
				var neighbor_pitches: Array[int] = metadata[neighbor]["pitches"]
				if neighbor_pitches.is_empty():
					continue
				var nt: int = int(metadata[neighbor]["top"])
				var nc: int = int(metadata[neighbor]["count"])
				window_tops.append(nt)
				if nc == 1:
					solo_top_counts[nt] = int(solo_top_counts.get(nt, 0)) + 1
				if prev_valid_top >= 0:
					if prev_valid_count == 1 and prev_valid_top >= 78 and nt <= prev_valid_top - 5:
						bounces_by_pitch[prev_valid_top] = int(bounces_by_pitch.get(prev_valid_top, 0)) + 1
						var low_set_a: Dictionary = lower_distinct_by_pitch.get(prev_valid_top, {})
						low_set_a[nt] = true
						lower_distinct_by_pitch[prev_valid_top] = low_set_a
					elif nc == 1 and nt >= 78 and prev_valid_top <= nt - 5:
						bounces_by_pitch[nt] = int(bounces_by_pitch.get(nt, 0)) + 1
						var low_set_b: Dictionary = lower_distinct_by_pitch.get(nt, {})
						low_set_b[prev_valid_top] = true
						lower_distinct_by_pitch[nt] = low_set_b
				prev_valid_top = nt
				prev_valid_count = nc
			var pedal_pitches: Dictionary = {}
			for cand_var: Variant in solo_top_counts.keys():
				var cand: int = int(cand_var)
				var low_set: Dictionary = lower_distinct_by_pitch.get(cand, {})
				if cand >= 78 and int(solo_top_counts.get(cand, 0)) >= 3 and int(bounces_by_pitch.get(cand, 0)) >= 3 and low_set.size() >= 2:
					pedal_pitches[cand] = true
			var filtered_tops: Array[int] = []
			for nt: int in window_tops:
				if pedal_pitches.has(nt) and nt > top + 4:
					continue
				filtered_tops.append(nt)
			if filtered_tops.is_empty():
				filtered_tops = window_tops.duplicate()
			filtered_tops.sort()
			var ceiling_index: int = mini(filtered_tops.size() - 1, int(floor(0.8 * float(filtered_tops.size() - 1))))
			var ceiling: int = filtered_tops[ceiling_index]
			var drop: int = ceiling - top
			var is_bell_pedal: bool = k == 1 and pedal_pitches.has(top)
			if k == 1:
				if pitches[0] < 55:
					velocities[raw_sorted[0]] = 98
					roles[raw_sorted[0]] = ROLE_BASS
				elif pitches[0] >= 60 or drop <= 7:
					if is_bell_pedal:
						var bell_rep: int = 3 if i > 0 and metadata[i - 1]["raw_sorted"] == raw_sorted else 0
						velocities[raw_sorted[0]] = 103 - bell_rep
					else:
						velocities[raw_sorted[0]] = clampi(106 + clampi(int(round(float(top - 66) * 0.22)), -2, 5), 104, 112)
					roles[raw_sorted[0]] = ROLE_LEAD
				else:
					velocities[raw_sorted[0]] = 92
					roles[raw_sorted[0]] = ROLE_INNER
			else:
				var melody: bool = (
					drop <= 4
					or (top >= 60 and top - pitches[k - 2] >= 7 and drop <= 14)
					or (k == 2 and top - pitches[0] == 12 and drop <= 9)
					or (k >= 4 and top >= 60 and top - pitches[0] >= 12)
				)
				if melody:
					velocities[raw_sorted[k - 1]] = clampi(107 + clampi(int(round(float(top - 66) * 0.25)), -3, 6) + (2 if k >= 3 else 0), 104, 114)
					roles[raw_sorted[k - 1]] = ROLE_LEAD
					var bottom_is_bass: bool = pitches[0] < 55 or (pitches[0] <= 60 and top - pitches[0] >= 12)
					if bottom_is_bass:
						velocities[raw_sorted[0]] = clampi((102 if pitches[0] < 48 else 96) - maxi(0, k - 4), 90, 104)
						roles[raw_sorted[0]] = ROLE_BASS
					elif k == 2 and top - pitches[0] >= 12:
						velocities[raw_sorted[0]] = 94
						roles[raw_sorted[0]] = ROLE_INNER
					else:
						velocities[raw_sorted[0]] = 86
						roles[raw_sorted[0]] = ROLE_INNER
					for j: int in range(1, k - 1):
						velocities[raw_sorted[j]] = clampi(86 - 2 * maxi(0, k - 3), 78, 88)
						roles[raw_sorted[j]] = ROLE_INNER
				else:
					var rep_atten: int = 3 if i > 0 and metadata[i - 1]["raw_sorted"] == raw_sorted else 0
					velocities[raw_sorted[k - 1]] = clampi(88 - 2 * maxi(0, k - 3) - rep_atten, 80, 90)
					roles[raw_sorted[k - 1]] = ROLE_INNER
					if pitches[0] < 55:
						velocities[raw_sorted[0]] = clampi(95 - 2 * maxi(0, k - 3) - rep_atten, 86, 97)
						roles[raw_sorted[0]] = ROLE_BASS
					else:
						velocities[raw_sorted[0]] = clampi(84 - 2 * maxi(0, k - 3) - rep_atten, 76, 86)
						roles[raw_sorted[0]] = ROLE_INNER
					for j: int in range(1, k - 1):
						velocities[raw_sorted[j]] = clampi(82 - 2 * maxi(0, k - 3) - rep_atten, 74, 84)
						roles[raw_sorted[j]] = ROLE_INNER
			var explicit_velocities: Variant = steps[i].get("velocities", {})
			if explicit_velocities is Dictionary:
				for raw_note: int in raw_sorted:
					if explicit_velocities.has(raw_note):
						velocities[raw_note] = explicit_velocities[raw_note]
		result.append({
			"voiced_velocities": velocities,
			"voice_roles": roles,
		})
	return result


static func voice_steps(steps: Array[Dictionary], extra_transposition: int = 0) -> void:
	var computed: Array[Dictionary] = build_step_voicing(steps, extra_transposition)
	for i: int in range(mini(steps.size(), computed.size())):
		steps[i]["voiced_velocities"] = computed[i]["voiced_velocities"]
		steps[i]["voice_roles"] = computed[i]["voice_roles"]


static func voice_live_chord(pitches: Array[int], base_velocity: int = 108) -> Dictionary:
	var sorted_pitches: Array[int] = []
	for pitch: int in pitches:
		if not sorted_pitches.has(pitch):
			sorted_pitches.append(pitch)
	sorted_pitches.sort()
	var velocities: Dictionary = {}
	var roles: Dictionary = {}
	var k: int = sorted_pitches.size()
	if k == 1:
		velocities[sorted_pitches[0]] = clampi(base_velocity, 1, 127)
		roles[sorted_pitches[0]] = ROLE_BASS if sorted_pitches[0] < 50 else ROLE_LEAD
	elif k >= 2:
		var bottom: int = sorted_pitches[0]
		var top: int = sorted_pitches[k - 1]
		velocities[top] = clampi(base_velocity + 2, 1, 114)
		roles[top] = ROLE_LEAD
		var bottom_is_bass: bool = bottom < 55 or (bottom <= 60 and top - bottom >= 12)
		if bottom_is_bass:
			velocities[bottom] = clampi(base_velocity - 6, 72, 104)
			roles[bottom] = ROLE_BASS
		elif k == 2 and top - bottom >= 12:
			velocities[bottom] = clampi(base_velocity - 10, 76, 98)
			roles[bottom] = ROLE_INNER
		else:
			velocities[bottom] = clampi(base_velocity - 18, 72, 94)
			roles[bottom] = ROLE_INNER
		for j: int in range(1, k - 1):
			velocities[sorted_pitches[j]] = clampi(base_velocity - 22, 70, 90)
			roles[sorted_pitches[j]] = ROLE_INNER
	return {"velocities": velocities, "roles": roles}
