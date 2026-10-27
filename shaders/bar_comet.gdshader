shader_type canvas_item;

uniform vec4 u_color : source_color = vec4(0.39, 0.91, 0.82, 1.0);
uniform vec2 u_size = vec2(20.0, 100.0);
uniform float u_time = 0.0;
uniform float u_born = 0.0;
uniform bool u_held = false;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * u_size;
	float r_head = u_size.x * 0.5;
	float r_tail = max(1.0, r_head * 0.12);
	float h = max(0.0, u_size.y * 0.5 - r_head);
	
	// Aerodynamic subtle wave along tail
	float wave = sin(UV.y * 12.0 - u_time * 8.0 + u_born) * (UV.y * 0.05 * u_size.x);
	float px = p.x + wave;
	
	// Tapered radius along length (0.0 at top head, 1.0 at tail bottom: 100% down to 12%)
	float t = clamp((p.y + h) / max(1.0, 2.0 * h), 0.0, 1.0);
	float r = mix(r_head, r_tail, pow(t, 0.85));
	
	// Continuous smooth tapered capsule SDF
	float dist;
	if (p.y < -h) {
		dist = length(vec2(px, p.y + h)) - r_head;
	} else if (p.y > h) {
		dist = length(vec2(px, p.y - h)) - r_tail;
	} else {
		dist = abs(px) - r;
	}
	
	float edge = 1.0 - smoothstep(-1.5, 0.0, dist);
	if (edge <= 0.001) {
		discard;
	}
	
	// Exponential opacity decay along the comet tail
	float tail_fade = exp(-t * 1.6);
	
	// Lateral profile
	float lat_dist = abs(px);
	
	// Incandescent plasma core
	float core_w = r * 0.35;
	float core = (1.0 - smoothstep(0.0, core_w, lat_dist)) * exp(-t * 2.0) * 2.4;
	
	// Plasma head incandescent bulb
	float bulb = exp(-t * 4.5) * (1.0 - smoothstep(0.0, r_head * 0.85, length(vec2(px, max(0.0, -(p.y + h)))))) * 2.0;
	
	float alpha = edge * tail_fade;
	
	vec3 plasma_color = mix(u_color.rgb, vec3(1.0), 0.35) * 1.45;
	vec3 core_color = mix(u_color.rgb, vec3(1.0), 0.88) * (core + bulb);
	
	COLOR = vec4(plasma_color + core_color, alpha);
}
