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
	// Soft bands retain the anime silhouette while following cylindrical fingers.
	float diffuse = max(ndotl, 0.0);
	float band = smoothstep(0.02, 0.42, ndotl);
	vec3 shadow_ratio = u_shadow_color.rgb / max(u_skin_color.rgb, vec3(0.001));
	vec3 tint = mix(shadow_ratio, vec3(1.0), band);
	DIFFUSE_LIGHT += ALBEDO * tint * diffuse * LIGHT_COLOR * ATTENUATION / PI;
	vec3 half_vector = normalize(VIEW + LIGHT);
	float gloss = pow(max(dot(NORMAL, half_vector), 0.0), mix(28.0, 72.0, nail_mask));
	float strength = mix(0.06, u_nail_specular * 0.24, nail_mask);
	SPECULAR_LIGHT += gloss * strength * diffuse * LIGHT_COLOR * ATTENUATION;
}
