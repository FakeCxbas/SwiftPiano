shader_type canvas_item;
render_mode blend_add;

uniform vec2 u_resolution = vec2(1200.0, 600.0);
uniform vec4 u_color : source_color = vec4(0.39, 0.91, 0.82, 1.0);
uniform float u_flash_intensity = 0.0;
uniform vec2 u_center = vec2(0.5, 1.0);
uniform float u_radius = 0.0;
uniform float u_time = 0.0;

void fragment() {
	vec2 pixel_coord = UV * u_resolution;
	vec2 center_px = u_center * u_resolution;
	float dist = length(pixel_coord - center_px);
	
	// 1. Pulsing cosmic nebula background (soft ambient)
	float nebula_decay = exp(-dist / (u_resolution.y * 0.75));
	float nebula = nebula_decay * u_flash_intensity * 0.22;
	
	// 2. Thick Gaussian shockwave expansion ring
	float ring = 0.0;
	float echo_ring = 0.0;
	if (u_radius > 1.0) {
		float ring_width = 24.0 + u_radius * 0.045;
		float ring_fade = exp(-u_radius / (u_resolution.y * 1.1)) * clamp(u_flash_intensity * 0.65 + 0.35, 0.0, 1.0);
		ring = exp(-pow((dist - u_radius) / ring_width, 2.0)) * ring_fade * 1.35;
		float echo_r = u_radius * 0.76;
		echo_ring = exp(-pow((dist - echo_r) / (ring_width * 1.3), 2.0)) * ring_fade * 0.35;
	}
	
	// 3. Soft vertical atmosphere horizon at the bottom
	float horizon = exp(-(u_resolution.y - pixel_coord.y) / 55.0) * u_flash_intensity * 0.28;
	
	// Composite in HDR overbright
	vec3 col_nebula = u_color.rgb * nebula;
	vec3 col_ring = mix(u_color.rgb, vec3(1.0), 0.65) * (ring + echo_ring);
	vec3 col_horizon = mix(u_color.rgb, vec3(1.0), 0.35) * horizon;
	
	vec3 final_rgb = col_nebula + col_ring + col_horizon;
	float final_alpha = clamp(nebula + ring + echo_ring + horizon, 0.0, 1.0);
	
	COLOR = vec4(final_rgb, final_alpha);
}
