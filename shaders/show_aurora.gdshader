shader_type canvas_item;
render_mode blend_add;

uniform vec2 u_resolution = vec2(1200.0, 600.0);
uniform vec4 u_color : source_color = vec4(0.39, 0.91, 0.82, 1.0);
uniform float u_intensity = 0.5;
uniform float u_time = 0.0;

// High-speed smooth procedural value noise
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

void fragment() {
	vec2 uv = UV;
	
	// Vertical envelope: soft fade at top and bottom
	float v_envelope = smoothstep(0.04, 0.38, uv.y) * smoothstep(1.0, 0.72, uv.y);
	if (v_envelope <= 0.001) {
		discard;
	}
	
	// Curtain wave distortion
	float wave1 = sin(uv.x * 4.5 + u_time * 0.75) * 0.12 + cos(uv.x * 11.0 - u_time * 1.1) * 0.05;
	float wave2 = sin(uv.x * 7.0 - u_time * 0.9) * 0.09 + sin(uv.x * 14.0 + u_time * 1.4) * 0.04;
	
	// Vertically stretched curtain noise sampling
	vec2 uv_curtain1 = vec2(uv.x * 7.0 + wave1, uv.y * 1.8 - u_time * 0.22);
	vec2 uv_curtain2 = vec2(uv.x * 11.0 - wave2, uv.y * 2.2 + u_time * 0.30);
	
	float n1 = noise(uv_curtain1);
	float n2 = noise(uv_curtain2);
	
	// Soft luminous folds
	float curtain1 = pow(n1 * 1.25, 2.2) * smoothstep(0.2, 0.8, uv.y + wave1);
	float curtain2 = pow(n2 * 1.3, 2.4) * smoothstep(0.15, 0.75, uv.y - wave2);
	
	// Rich multi-spectral polar color palette
	vec3 emerald = vec3(0.0, 1.0, 0.65);
	vec3 arctic_cyan = vec3(0.08, 0.85, 1.0);
	vec3 violet = vec3(0.72, 0.38, 1.0);
	
	vec3 col1 = mix(emerald, arctic_cyan, sin(u_time * 0.5 + uv.x * 3.0) * 0.5 + 0.5);
	vec3 col2 = mix(u_color.rgb, violet, cos(u_time * 0.7 - uv.x * 4.0) * 0.5 + 0.5);
	
	float glow_boost = 0.22 + clamp(u_intensity, 0.0, 2.0) * 0.28;
	vec3 result_rgb = (col1 * curtain1 * 0.85 + col2 * curtain2 * 0.75) * v_envelope * glow_boost;
	float result_alpha = clamp((curtain1 + curtain2) * v_envelope * glow_boost, 0.0, 1.0);
	
	COLOR = vec4(result_rgb, result_alpha);
}
