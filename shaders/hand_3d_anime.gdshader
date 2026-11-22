shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D u_albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 u_skin_color : source_color = vec4(0.98, 0.91, 0.86, 1.0);
uniform vec4 u_shadow_color : source_color = vec4(0.86, 0.74, 0.68, 1.0);
uniform vec4 u_nail_color : source_color = vec4(0.06, 0.05, 0.09, 1.0);
uniform float u_nail_specular = 0.90;

void fragment() {
	vec4 tex = texture(u_albedo_tex, UV);
	// Nails are painted dark (< 0.25) in the baked UV map
	bool is_nail = (tex.r < 0.25 && tex.g < 0.25 && tex.b < 0.25);
	
	if (is_nail) {
		ALBEDO = u_nail_color.rgb;
		ROUGHNESS = 0.10;
		METALLIC = 0.16;
		SPECULAR = u_nail_specular;
	} else {
		ALBEDO = u_skin_color.rgb;
		ROUGHNESS = 0.68;
		METALLIC = 0.0;
		SPECULAR = 0.08;
	}
	
	// Solid opaque anime skin, eliminating any ghost/translucent artifact
	ALPHA = 1.0;
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	// 2-band stepped anime cel-shade transition
	float cel_band = smoothstep(-0.02, 0.12, NdotL);
	vec3 cel_albedo = mix(u_shadow_color.rgb, ALBEDO, cel_band);
	
	DIFFUSE_LIGHT += cel_albedo * LIGHT_COLOR * ATTENUATION;
	
	// Toon specular gleam on polished nails
	vec3 H = normalize(VIEW + LIGHT);
	float NdotH = dot(NORMAL, H);
	float spec = smoothstep(0.85, 0.93, NdotH) * u_nail_specular * 0.7;
	SPECULAR_LIGHT += vec3(spec) * LIGHT_COLOR * ATTENUATION;
}
