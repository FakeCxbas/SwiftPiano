shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 glass_tint : source_color = vec4(0.05, 0.07, 0.12, 0.55);
uniform vec4 rim_color : source_color = vec4(1.0, 0.25, 0.25, 0.35);
uniform vec2 size = vec2(300.0, 64.0);
uniform float corner_radius = 16.0;

// Signed Distance Field for Rounded Box
float sdRoundedBox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void fragment() {
	vec2 half_size = size * 0.5;
	vec2 p = (UV - vec2(0.5)) * size;
	float dist = sdRoundedBox(p, half_size, corner_radius);
	
	// Antialiased mask
	float mask = 1.0 - smoothstep(-1.0, 1.0, dist);
	if (mask <= 0.001) {
		discard;
	}
	
	// Refraction near the glass perimeter
	vec2 norm = p / max(vec2(1.0), half_size);
	float edge_factor = smoothstep(-18.0, 0.0, dist);
	vec2 refract_offset = norm * edge_factor * 0.015;
	
	// Multi-tap frosted glass blur
	vec2 uv = SCREEN_UV + refract_offset;
	vec2 texel = SCREEN_PIXEL_SIZE * 2.5;
	vec4 bg = texture(screen_tex, uv) * 0.28;
	bg += texture(screen_tex, uv + vec2(texel.x, 0.0)) * 0.12;
	bg += texture(screen_tex, uv - vec2(texel.x, 0.0)) * 0.12;
	bg += texture(screen_tex, uv + vec2(0.0, texel.y)) * 0.12;
	bg += texture(screen_tex, uv - vec2(0.0, texel.y)) * 0.12;
	bg += texture(screen_tex, uv + vec2(texel.x, texel.y) * 0.7) * 0.09;
	bg += texture(screen_tex, uv + vec2(-texel.x, texel.y) * 0.7) * 0.09;
	bg += texture(screen_tex, uv + vec2(texel.x, -texel.y) * 0.7) * 0.09;
	bg += texture(screen_tex, uv + vec2(-texel.x, -texel.y) * 0.7) * 0.09;
	
	// Subtle top-down glass luminance gradient (reflects light from above)
	float v_grad = clamp(0.5 - (p.y / size.y), 0.0, 1.0);
	vec3 glass_lum = mix(vec3(0.02, 0.03, 0.05), vec3(0.10, 0.12, 0.18), v_grad * 0.6);
	
	// Glass body
	vec3 col = mix(bg.rgb, glass_tint.rgb + glass_lum, glass_tint.a);
	
	// Specular highlight: top rim catches ambient light
	float top_factor = clamp(0.5 - (p.y / size.y), 0.0, 1.0);
	float top_sheen = smoothstep(-3.0, 0.0, dist) * pow(top_factor, 1.5) * 0.55;
	vec3 specular = vec3(1.0, 1.0, 1.0) * top_sheen;
	
	// Delicate glass rim
	float border = smoothstep(-1.6, 0.0, dist) * (1.0 - smoothstep(-2.8, -1.6, dist));
	vec3 border_rgb = mix(rim_color.rgb, vec3(1.0, 1.0, 1.0), top_sheen * 0.7);
	
	// Inner subtle refraction
	float inner_glow = smoothstep(-14.0, -1.5, dist) * 0.14;
	col += rim_color.rgb * inner_glow;
	
	col = mix(col, border_rgb, border * rim_color.a * 1.5);
	col += specular;
	
	COLOR = vec4(col, mask * 0.94);
}
