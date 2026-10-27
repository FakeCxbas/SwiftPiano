shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
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
	
	// Surface normal approximation for realistic refraction
	vec2 norm = vec2(p.x / r, clamp(p.y / max(1.0, h + r), -1.0, 1.0));
	vec2 refract_offset = norm * 0.012;
	
	// Small fixed blur without generating screen mipmaps on viewport resize.
	vec2 uv = SCREEN_UV + refract_offset;
	vec2 texel = SCREEN_PIXEL_SIZE * 2.0;
	vec4 bg_sample = texture(screen_tex, uv) * 0.4;
	bg_sample += texture(screen_tex, uv + vec2(texel.x, 0.0)) * 0.15;
	bg_sample += texture(screen_tex, uv - vec2(texel.x, 0.0)) * 0.15;
	bg_sample += texture(screen_tex, uv + vec2(0.0, texel.y)) * 0.15;
	bg_sample += texture(screen_tex, uv - vec2(0.0, texel.y)) * 0.15;
	
	// Soft glass body tinted with note color
	vec3 glass_body = mix(bg_sample.rgb, u_color.rgb, 0.42);
	
	// Inner soft luminous velvet gradient
	float velvet = (1.0 - smoothstep(0.0, r * 0.85, abs(p.x))) * 0.35;
	glass_body += u_color.rgb * velvet;
	
	// Fine frosted border (1.5px wide)
	float border = smoothstep(-1.5, 0.0, dist) * (1.0 - smoothstep(-3.0, -1.5, dist)) * 1.6;
	vec3 border_col = mix(vec3(1.0), u_color.rgb, 0.3) * border;
	
	// Specular corner & top rim reflections
	float top_specular = smoothstep(1.8, 0.0, abs(p.y + h + r * 0.4)) * 0.75;
	float corner_glint = max(0.0, 1.0 - length(p - vec2(-r * 0.4, -h - r * 0.4)) / 4.0) * 1.2;
	
	vec3 specular = vec3(1.0) * (top_specular + corner_glint);
	
	vec3 final_rgb = glass_body + border_col + specular;
	
	COLOR = vec4(final_rgb, alpha * 0.88);
}
