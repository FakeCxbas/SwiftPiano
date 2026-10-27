shader_type canvas_item;
render_mode blend_add;

uniform vec2 u_resolution = vec2(1200.0, 600.0);
uniform vec4 u_color : source_color = vec4(0.39, 0.91, 0.82, 1.0);
uniform float u_time = 0.0;
uniform float u_intensity = 0.0;

// 16-band reactive frequency equalizer columns
uniform float u_eq[16];

void fragment() {
	vec2 uv = UV;
	
	// Horizon height
	float horizon_y = 0.52;
	
	// Sample frequency bands with cubic smoothing across the screen width
	float band_f = uv.x * 15.0;
	int b0 = clamp(int(floor(band_f)), 0, 15);
	int b1 = clamp(b0 + 1, 0, 15);
	float frac_b = fract(band_f);
	float smooth_frac = frac_b * frac_b * (3.0 - 2.0 * frac_b);
	float peak_height = mix(u_eq[b0], u_eq[b1], smooth_frac) * 0.22 * (0.8 + clamp(u_intensity, 0.0, 2.0) * 0.4);
	
	// 1. Perspective 3D Neon Grid below horizon
	float grid_glow = 0.0;
	if (uv.y > horizon_y) {
		float depth = 1.0 / max(0.005, uv.y - horizon_y);
		vec2 grid_uv = vec2((uv.x - 0.5) * depth * 2.2, depth * 3.5 - u_time * 3.2);
		
		vec2 grid_lines = abs(fract(grid_uv) - vec2(0.5));
		float line_x = smoothstep(0.08, 0.0, grid_lines.x);
		float line_y = smoothstep(0.08, 0.0, grid_lines.y);
		
		float depth_fade = smoothstep(horizon_y, horizon_y + 0.04, uv.y) * smoothstep(1.0, 0.70, uv.y);
		grid_glow = (line_x * 0.55 + line_y * 0.75) * depth_fade * 0.55;
	}
	
	// 2. Glowing Horizon Line with reactive music equalizer peaks
	float horizon_target_y = horizon_y - peak_height;
	float horizon_beam = exp(-pow((uv.y - horizon_target_y) / 0.012, 2.0)) * 1.15;
	float horizon_underglow = exp(-abs(uv.y - horizon_target_y) / 0.06) * 0.28;
	
	// 3. Cyber sunset sky glow above horizon (subtle atmospheric gradient)
	float sky_glow = 0.0;
	if (uv.y <= horizon_y) {
		float sky_dist = (horizon_y - uv.y) / horizon_y;
		sky_glow = exp(-sky_dist * 4.2) * (0.12 + clamp(u_intensity, 0.0, 2.0) * 0.12);
	}
	
	// Synthwave palette: Neon magenta (#ff0080), electric violet (#8a2be2), and piano active color
	vec3 magenta = vec3(1.0, 0.0, 0.55);
	vec3 violet = vec3(0.55, 0.15, 0.95);
	vec3 cyan_accent = mix(u_color.rgb, vec3(0.1, 0.9, 1.0), 0.5);
	
	vec3 grid_color = mix(violet, magenta, uv.y) * grid_glow;
	vec3 horizon_color = mix(magenta, cyan_accent, uv.x) * (horizon_beam + horizon_underglow);
	vec3 sky_color = mix(violet, magenta, 1.0 - uv.y) * sky_glow;
	
	vec3 final_rgb = grid_color + horizon_color + sky_color;
	float final_alpha = clamp(grid_glow + horizon_beam + horizon_underglow + sky_glow, 0.0, 1.0);
	
	COLOR = vec4(final_rgb, final_alpha);
}
