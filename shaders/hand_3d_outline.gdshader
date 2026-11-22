shader_type spatial;
render_mode blend_mix, cull_front, unshaded, depth_draw_opaque;

uniform float u_outline_width = 0.0016;
uniform vec4 u_outline_color : source_color = vec4(0.09, 0.08, 0.13, 1.0);
uniform float u_wrist_fade_start = -0.015;
uniform float u_wrist_fade_end = 0.018;

varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
	VERTEX += NORMAL * u_outline_width;
}

void fragment() {
	float fade = clamp((u_wrist_fade_end - v_local_pos.z) / (u_wrist_fade_end - u_wrist_fade_start), 0.0, 1.0);
	if (fade <= 0.005) {
		discard;
	}
	ALBEDO = u_outline_color.rgb;
	ALPHA = u_outline_color.a * fade;
}
