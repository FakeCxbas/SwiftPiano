shader_type canvas_item;

uniform vec4 u_color : source_color = vec4(0.39, 0.91, 0.82, 1.0);
uniform vec2 u_size = vec2(20.0, 100.0);
uniform float u_time = 0.0;
uniform float u_born = 0.0;
uniform bool u_held = false;
uniform float u_pitch = 0.5; // Normalized midi 0.0 - 1.0

void fragment() {
	vec2 uv = UV;
	
	// Oscillation frequency proportional to pitch
	float freq = 16.0 + u_pitch * 24.0;
	float speed = 12.0 + u_pitch * 16.0;
	
	// Two interwoven sinusoidal filaments (180 deg out of phase)
	float amp = 0.36;
	float w1 = sin(uv.y * freq + u_time * speed) * amp + 0.5;
	float w2 = sin(uv.y * freq + u_time * speed + 3.1415926) * amp + 0.5;
	
	// Distance to filaments in pixels
	float d1 = abs(uv.x - w1) * u_size.x;
	float d2 = abs(uv.x - w2) * u_size.x;
	
	// Gaussian filament cores
	float strand1 = exp(-pow(d1 / 2.2, 2.0));
	float strand2 = exp(-pow(d2 / 2.2, 2.0));
	
	// Harmonic bridge resonance at intersection nodes
	float node_dist = abs(w1 - w2) * u_size.x;
	float bridge = exp(-pow(node_dist / 3.5, 2.0)) * 0.75;
	
	// Soft additive halo around filaments
	float halo1 = exp(-d1 / 7.0) * 0.45;
	float halo2 = exp(-d2 / 7.0) * 0.45;
	
	// Vertical edge fade
	float v_fade = smoothstep(0.0, 0.06, uv.y) * (1.0 - smoothstep(0.94, 1.0, uv.y));
	if (u_held) {
		v_fade = smoothstep(0.0, 0.06, uv.y);
	}
	
	float total_light = strand1 + strand2 + bridge + halo1 + halo2;
	if (total_light <= 0.005) {
		discard;
	}
	
	vec3 neon_body = u_color.rgb * 1.5 * (halo1 + halo2 + bridge);
	vec3 strand_core = mix(u_color.rgb, vec3(1.0), 0.85) * (strand1 + strand2) * 2.2;
	
	vec3 final_rgb = neon_body + strand_core;
	float alpha = clamp(total_light, 0.0, 1.0) * v_fade;
	
	COLOR = vec4(final_rgb, alpha);
}
