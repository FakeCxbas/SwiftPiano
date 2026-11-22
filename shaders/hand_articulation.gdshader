shader_type canvas_item;

// Clean solid rendering with smooth wrist gradient fade and contact illumination
uniform vec4 u_finger_dips_1_4 = vec4(0.0);
uniform float u_finger_dip_5 = 0.0;
uniform float u_wrist_fade_start = 0.72;
uniform float u_time = 0.0;
uniform bool u_is_shadow = false;

void vertex() {
	// Pristine lineart geometry without rubbery vertex stretching
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Smooth wrist fade-out gradient to cleanly blend the arm into the lower screen
	float wrist_alpha = 1.0 - smoothstep(u_wrist_fade_start, 1.0, UV.y);
	
	if (u_is_shadow) {
		COLOR = vec4(0.0, 0.0, 0.0, tex.a * wrist_alpha * 0.22);
	} else {
		COLOR = vec4(tex.rgb, tex.a * wrist_alpha * COLOR.a);
	}
}
