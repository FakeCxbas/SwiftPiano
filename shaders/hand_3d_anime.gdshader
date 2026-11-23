shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D u_albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 u_skin_color : source_color = vec4(0.84, 0.67, 0.56, 1.0);
uniform vec4 u_shadow_color : source_color = vec4(0.24, 0.16, 0.15, 1.0);
uniform vec4 u_nail_color : source_color = vec4(0.88, 0.73, 0.67, 1.0);
uniform float u_nail_specular = 0.90;
varying float nail_mask;

void fragment() {
	vec3 tex = texture(u_albedo_tex, UV).rgb;
	// The baked dark nail regions act as a mask for the warm nail tint.
	nail_mask = 1.0 - step(0.25, max(tex.r, max(tex.g, tex.b)));
	ALBEDO = mix(u_skin_color.rgb, u_nail_color.rgb, nail_mask);
	ROUGHNESS = mix(0.62, 0.25, nail_mask);
	METALLIC = 0.0;
	SPECULAR = mix(0.18, u_nail_specular, nail_mask);
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndotl + 0.22) / 1.22, 0.0, 1.0);
	float band = smoothstep(0.05, 0.55, ndotl);
	float ndotv = max(dot(NORMAL, VIEW), 0.0);
	// Darken grazing cylinder edges so adjacent fingers read with clear dark seams.
	float edge_ao = smoothstep(0.08, 0.58, ndotv);
	vec3 shadow_ratio = u_shadow_color.rgb / max(u_skin_color.rgb, vec3(0.001));
	vec3 tint = mix(shadow_ratio * 0.82, vec3(1.0), band * mix(0.38, 1.0, edge_ao));
	float luma = dot(LIGHT_COLOR, vec3(0.299, 0.587, 0.114));
	vec3 balanced_light = mix(vec3(luma), LIGHT_COLOR, 0.28);
	vec3 diff_contrib = tint * wrapped * balanced_light * ATTENUATION;
	DIFFUSE_LIGHT += diff_contrib / (vec3(1.0) + diff_contrib * 0.45);
	vec3 half_vector = normalize(VIEW + LIGHT);
	float gloss = pow(max(dot(NORMAL, half_vector), 0.0), mix(30.0, 68.0, nail_mask));
	float strength = mix(0.035, u_nail_specular * 0.20, nail_mask);
	SPECULAR_LIGHT += gloss * strength * max(ndotl, 0.0) * edge_ao * balanced_light * ATTENUATION;
}
