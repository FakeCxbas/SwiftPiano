shader_type canvas_item;

uniform vec4 u_color : source_color = vec4(0.39, 0.91, 0.82, 1.0);
uniform vec2 u_size = vec2(20.0, 100.0);
uniform float u_time = 0.0;
uniform float u_born = 0.0;
uniform bool u_held = false;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * u_size;
	float r = u_size.x * 0.5;
	float h = max(0.0, u_size.y * 0.5 - r);
	
	// Capsule SDF
	float dist = length(vec2(p.x, max(0.0, abs(p.y) - h))) - r;
	float alpha = 1.0 - smoothstep(-1.5, 0.0, dist);
	if (alpha <= 0.001) {
		discard;
	}
	
	// Celestial gradient
	float v_gradient = 0.7 + 0.3 * UV.y;
	float edge_falloff = 1.0 - smoothstep(0.0, 1.0, abs(p.x) / r);
	
	// Soft luminous core
	float core = (1.0 - smoothstep(0.0, r * 0.35, abs(p.x))) * 1.35;
	
	// Animated 4-point star diamonds
	vec2 pixel_coord = UV * u_size;
	float grid_spacing = 26.0;
	float cell_y = floor((pixel_coord.y + u_born * 35.0) / grid_spacing);
	float star_center_y = cell_y * grid_spacing + grid_spacing * 0.5 - u_born * 35.0;
	float star_center_x = u_size.x * 0.5;
	
	vec2 d_star = abs(pixel_coord - vec2(star_center_x, star_center_y));
	float star_phase = fract(sin(cell_y * 12.9898 + u_born * 78.233) * 43758.5453);
	float tw = sin(u_time * 14.0 + star_phase * 6.28) * 0.5 + 0.5;
	
	// 4-point star SDF
	float arm_h = max(0.0, 1.0 - d_star.x / (4.5 * tw + 1.0)) * max(0.0, 1.0 - d_star.y / (1.5 * tw + 0.5));
	float arm_v = max(0.0, 1.0 - d_star.y / (4.5 * tw + 1.0)) * max(0.0, 1.0 - d_star.x / (1.5 * tw + 0.5));
	float star_core = max(0.0, 1.0 - length(d_star) / (2.2 * tw + 0.8));
	float star_flare = (arm_h + arm_v + star_core) * tw * 2.2;
	
	// Leading head diamond star
	float head_dist = length(pixel_coord - vec2(star_center_x, u_size.y - r));
	float head_star = 0.0;
	if (u_held) {
		vec2 d_head = abs(pixel_coord - vec2(star_center_x, u_size.y - r));
		float h_arm_x = max(0.0, 1.0 - d_head.x / (r * 1.5)) * max(0.0, 1.0 - d_head.y / 2.0);
		float h_arm_y = max(0.0, 1.0 - d_head.y / (r * 1.8)) * max(0.0, 1.0 - d_head.x / 2.0);
		head_star = (h_arm_x + h_arm_y + max(0.0, 1.0 - head_dist / (r * 0.5))) * 2.2;
	}
	
	vec3 base = u_color.rgb * 1.25 * v_gradient * edge_falloff;
	vec3 core_col = mix(u_color.rgb, vec3(1.0), 0.75) * core;
	vec3 star_col = vec3(1.0) * (star_flare + head_star);
	
	vec3 final_rgb = base + core_col + star_col;
	
	COLOR = vec4(final_rgb, alpha);
}
