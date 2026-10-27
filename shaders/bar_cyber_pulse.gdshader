shader_type canvas_item;

uniform vec4 u_color : source_color = vec4(0.39, 0.91, 0.82, 1.0);
uniform vec2 u_size = vec2(20.0, 100.0);
uniform float u_time = 0.0;
uniform float u_born = 0.0;
uniform bool u_held = false;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * u_size;
	vec2 half_sz = u_size * 0.5;
	
	// Box SDF with 3px tech bevel
	vec2 d_box = abs(p) - (half_sz - vec2(3.0));
	float dist = length(max(d_box, vec2(0.0))) + min(max(d_box.x, d_box.y), 0.0) - 3.0;
	float alpha = 1.0 - smoothstep(-1.5, 0.0, dist);
	if (alpha <= 0.001) {
		discard;
	}
	
	// 1. Solid energy gradient background
	float v_grad = 0.75 + 0.25 * UV.y;
	vec3 energy_bg = u_color.rgb * 1.25 * v_grad;
	
	// 2. Fine moving horizontal scanlines
	float scanline = 0.88 + 0.12 * sin(UV.y * u_size.y * 0.85 - u_time * 18.0);
	energy_bg *= scanline;
	
	// 3. Intense HDR side rails (intensity 2.2)
	float edge_dist_x = abs(p.x);
	float rail_peak = smoothstep(half_sz.x - 3.5, half_sz.x - 1.0, edge_dist_x) * 2.2;
	
	// 4. Chromatic aberration: 1.5px cyan / magenta fringe at outer borders
	float fringe_px = 1.5;
	float dist_r = abs(p.x + fringe_px) - (half_sz.x - 1.5);
	float dist_b = abs(p.x - fringe_px) - (half_sz.x - 1.5);
	float cyan_fringe = (1.0 - smoothstep(-1.0, 1.0, dist_b)) * smoothstep(-3.0, 0.0, dist_b) * 1.4;
	float magenta_fringe = (1.0 - smoothstep(-1.0, 1.0, dist_r)) * smoothstep(-3.0, 0.0, dist_r) * 1.4;
	
	vec3 chromatic = vec3(magenta_fringe * 0.9, cyan_fringe * 0.4, (cyan_fringe + magenta_fringe) * 0.8);
	
	// 5. Upward traveling bright data packet pulse
	float pulse_y = fract(u_time * 2.2 - u_born * 0.35);
	float pulse = exp(-pow((UV.y - (1.0 - pulse_y)) / 0.065, 2.0)) * 2.0;
	vec3 pulse_col = mix(u_color.rgb, vec3(1.0), 0.85) * pulse;
	
	// 6. Center filament
	float center_line = (1.0 - smoothstep(0.0, 1.5, abs(p.x))) * 1.2;
	
	// 7. Tech end brackets
	float top_cap = smoothstep(2.5, 0.0, abs(p.y + half_sz.y - 1.5)) * 1.8;
	float bot_cap = smoothstep(2.5, 0.0, abs(p.y - half_sz.y + 1.5)) * 1.8;
	
	vec3 rails_col = mix(u_color.rgb, vec3(1.0), 0.4) * (rail_peak + top_cap + bot_cap);
	
	vec3 final_rgb = energy_bg + rails_col + chromatic + pulse_col + vec3(center_line);
	
	COLOR = vec4(final_rgb, alpha);
}
