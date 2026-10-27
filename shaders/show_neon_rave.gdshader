shader_type canvas_item;
render_mode blend_add;

uniform vec2 u_resolution = vec2(1200.0, 600.0);
uniform vec4 u_color : source_color = vec4(0.39, 0.91, 0.82, 1.0);
uniform float u_time = 0.0;
uniform float u_intensity = 0.0;

// Up to 6 active volumetric spotlight shafts (origin_x, target_x, intensity, spread)
uniform vec4 u_beams[6];
uniform int u_num_beams = 0;

void fragment() {
	vec2 uv = UV;
	vec2 pixel_coord = uv * u_resolution;
	
	// Subtle atmospheric haze
	float haze = (1.0 - uv.y) * 0.04 * (1.0 + u_intensity * 0.5);
	vec4 total_light = u_color * haze;
	
	for (int i = 0; i < 6; i++) {
		if (i >= u_num_beams) {
			break;
		}
		vec4 b = u_beams[i];
		float ox = b.x * u_resolution.x;
		float tx = b.y * u_resolution.x;
		float intensity = b.z;
		float spread_base = max(25.0, b.w);
		
		vec2 origin = vec2(ox, u_resolution.y);
		vec2 target = vec2(tx, 0.0);
		vec2 dir = normalize(target - origin);
		vec2 normal = vec2(-dir.y, dir.x);
		
		vec2 to_p = pixel_coord - origin;
		float proj_along = dot(to_p, dir);
		float lateral_d = abs(dot(to_p, normal));
		
		// Beam spreads widening toward the ceiling
		float height_factor = (u_resolution.y - pixel_coord.y) / u_resolution.y;
		float spread = spread_base * (1.0 + height_factor * 2.8);
		
		// Gaussian volumetric cross-section decay
		float volumetric = exp(-pow(lateral_d / spread, 2.0));
		
		// Vertical extinction
		float v_extinct = smoothstep(0.0, 0.25, height_factor) * smoothstep(1.0, 0.75, height_factor);
		
		// Micro-dust particle twinkle inside beam
		float dust = 0.92 + 0.08 * sin(pixel_coord.y * 0.5 + u_time * 12.0 + float(i) * 5.0);
		
		vec4 beam_col = mix(u_color, vec4(1.0, 1.0, 1.0, 1.0), 0.35);
		total_light += beam_col * volumetric * v_extinct * intensity * dust * 1.6;
	}
	
	COLOR = total_light;
}
