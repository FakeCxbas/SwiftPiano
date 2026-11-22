shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D u_albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 u_skin_color : source_color = vec4(0.98, 0.92, 0.88, 1.0);
uniform vec4 u_shadow_color : source_color = vec4(0.88, 0.77, 0.72, 1.0);
uniform vec4 u_nail_color : source_color = vec4(0.07, 0.06, 0.10, 1.0);
uniform float u_nail_specular = 0.85;
uniform float u_wrist_fade_start = -0.015;
uniform float u_wrist_fade_end = 0.018;

varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
}

void fragment() {
	vec4 tex = texture(u_albedo_tex, UV);
	// Nails are painted black (< 0.25) in the baked UV texture
	bool is_nail = (tex.r < 0.25 && tex.g < 0.25 && tex.b < 0.25);
	
	if (is_nail) {
		ALBEDO = u_nail_color.rgb;
		ROUGHNESS = 0.12;
		METALLIC = 0.18;
		SPECULAR = u_nail_specular;
	} else {
		ALBEDO = u_skin_color.rgb;
		ROUGHNESS = 0.60;
		METALLIC = 0.0;
		SPECULAR = 0.10;
	}
	
	// Wrist fade: smooth transition to transparent before the severed stump edge
	float fade = clamp((u_wrist_fade_end - v_local_pos.z) / (u_wrist_fade_end - u_wrist_fade_start), 0.0, 1.0);
	if (fade <= 0.005) {
		discard;
	}
	ALPHA = fade;
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	// 2-band anime cel shade transition
	float cel_band = smoothstep(-0.02, 0.10, NdotL);
	vec3 cel_albedo = mix(u_shadow_color.rgb, ALBEDO, cel_band);
	
	DIFFUSE_LIGHT += cel_albedo * LIGHT_COLOR * ATTENUATION;
	
	// Toon specular highlight on glossy nails
	vec3 H = normalize(VIEW + LIGHT);
	float NdotH = dot(NORMAL, H);
	float spec = smoothstep(0.85, 0.93, NdotH) * u_nail_specular * 0.6;
	SPECULAR_LIGHT += vec3(spec) * LIGHT_COLOR * ATTENUATION;
}
