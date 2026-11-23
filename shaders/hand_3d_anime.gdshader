shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D u_albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 u_skin_color : source_color = vec4(0.86, 0.69, 0.58, 1.0);
uniform vec4 u_shadow_color : source_color = vec4(0.30, 0.21, 0.19, 1.0);
uniform vec4 u_nail_color : source_color = vec4(0.88, 0.73, 0.67, 1.0);
uniform float u_nail_specular = 0.90;
varying float nail_mask;

void fragment() {
	vec3 tex = texture(u_albedo_tex, UV).rgb;
	// The baked dark nail regions act as a mask for the warm nail tint.
	nail_mask = 1.0 - step(0.25, max(tex.r, max(tex.g, tex.b)));
	ALBEDO = mix(u_skin_color.rgb, u_nail_color.rgb, nail_mask);
	ROUGHNESS = mix(0.58, 0.25, nail_mask);
	METALLIC = 0.0;
	SPECULAR = mix(0.22, u_nail_specular, nail_mask);
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	// Soft bands retain anatomical volume across cylindrical phalanges without double-multiplying ALBEDO.
	float wrapped = clamp((ndotl + 0.25) / 1.25, 0.0, 1.0);
	float band = smoothstep(0.05, 0.55, ndotl);
	vec3 shadow_ratio = u_shadow_color.rgb / max(u_skin_color.rgb, vec3(0.001));
	vec3 tint = mix(shadow_ratio, vec3(1.0), band);
	float luma = dot(LIGHT_COLOR, vec3(0.299, 0.587, 0.114));
	vec3 balanced_light = mix(vec3(luma), LIGHT_COLOR, 0.28);
	DIFFUSE_LIGHT += tint * wrapped * balanced_light * ATTENUATION;
	vec3 half_vector = normalize(VIEW + LIGHT);
	float gloss = pow(max(dot(NORMAL, half_vector), 0.0), mix(26.0, 68.0, nail_mask));
	float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0) * 0.14;
	float strength = mix(0.05, u_nail_specular * 0.22, nail_mask);
	SPECULAR_LIGHT += (gloss * strength * max(ndotl, 0.0) + fresnel) * balanced_light * ATTENUATION;
}
