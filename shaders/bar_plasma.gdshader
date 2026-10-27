shader_type canvas_item;

uniform vec4 u_color : source_color = vec4(0.39, 0.91, 0.82, 1.0);
uniform vec2 u_size = vec2(20.0, 100.0);
uniform float u_time = 0.0;
uniform float u_born = 0.0;
uniform bool u_held = false;

// Compact pseudo-noise functions
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float val = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		val += amp * noise(p);
		p *= 2.05;
		amp *= 0.5;
	}
	return val;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * u_size;
	float r = u_size.x * 0.5;
	float h = max(0.0, u_size.y * 0.5 - r);
	
	// Living FBM domain warping
	vec2 np = vec2(UV.x * 3.0, UV.y * 6.0 - u_time * 2.8 + u_born);
	float n = fbm(np + vec2(fbm(np + vec2(0.0, u_time * 0.8))));
	
	// Perturb capsule SDF with flowing plasma edge
	float edge_warp = (n - 0.5) * 4.5;
	float dist = length(vec2(p.x, max(0.0, abs(p.y) - h))) - (r + edge_warp);
	float alpha = 1.0 - smoothstep(-2.0, 0.0, dist);
	if (alpha <= 0.001) {
		discard;
	}
	
	// Normalized distance from center spine
	float center_dist = abs(p.x) / r;
	
	// Thermal plasma layers
	float outer_rim = smoothstep(0.4, 0.95, center_dist) * (0.8 + 0.4 * n);
	float mid_flame = (1.0 - smoothstep(0.15, 0.75, center_dist)) * (0.7 + 0.6 * n) * 1.5;
	float white_core = (1.0 - smoothstep(0.0, 0.25, center_dist)) * (0.8 + 0.5 * n) * 2.4;
	
	// Color thermal gradient
	vec3 col_rim = u_color.rgb * 1.5 * outer_rim;
	vec3 col_mid = mix(u_color.rgb, vec3(1.0, 0.65, 0.2), 0.55) * mid_flame;
	vec3 col_core = mix(u_color.rgb, vec3(1.0), 0.88) * white_core;
	
	vec3 final_rgb = col_rim + col_mid + col_core;
	
	COLOR = vec4(final_rgb, alpha);
}
