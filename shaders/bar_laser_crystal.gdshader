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
	
	// Smooth lateral falloff
	float edge_dist = abs(p.x) / r;
	float body_glow = 1.0 - smoothstep(0.0, 1.0, edge_dist * 0.85);
	
	// Intense white-hot HDR laser core filament
	float core_dist = abs(p.x) / (r * 0.32);
	float core = (1.0 - smoothstep(0.0, 1.0, core_dist)) * 1.85;
	
	// Diagonal specular bevel sheen
	float sheen = smoothstep(0.42, 0.58, sin((p.x * 1.2 + p.y * 0.8) * 0.06 - u_time * 2.5)) * 0.35;
	
	// Top specular glass rim
	float top_rim = smoothstep(2.0, 0.0, abs(p.y + h + r * 0.5)) * 0.6;
	
	// Anamorphic horizontal flare at bottom piano contact line
	float contact_flare = 0.0;
	if (u_held && UV.y > 0.92) {
		contact_flare = (1.0 - smoothstep(0.92, 1.0, UV.y)) * 1.5;
	}
	
	vec3 base_color = u_color.rgb * 1.35 * body_glow;
	vec3 core_color = mix(u_color.rgb, vec3(1.0), 0.82) * core;
	vec3 sheen_color = vec3(1.0) * (sheen + top_rim + contact_flare);
	
	vec3 final_rgb = base_color + core_color + sheen_color;
	
	COLOR = vec4(final_rgb, alpha);
}
