shader_type canvas_item;
render_mode unshaded;

// Static studio lighting: no time-dependent noise or additional textures.
void fragment() {
	vec2 p = UV;
	vec3 base = vec3(0.004, 0.006, 0.010);
	float mint = exp(-8.0 * length((p - vec2(0.24, 0.9)) * vec2(1.0, 0.7)));
	float amber = exp(-9.0 * length((p - vec2(0.85, 0.6)) * vec2(1.0, 0.8)));
	base += vec3(0.007, 0.024, 0.020) * mint;
	base += vec3(0.016, 0.009, 0.004) * amber;
	float edge = min(fract(p.x * 8.0), 1.0 - fract(p.x * 8.0));
	float grid = 1.0 - smoothstep(0.0, fwidth(p.x * 8.0), edge);
	base += vec3(0.002) * grid * smoothstep(0.2, 1.0, p.y);
	COLOR = vec4(base, 1.0);
}
