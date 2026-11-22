shader_type spatial;
render_mode blend_mix, cull_front, unshaded, depth_draw_opaque;

uniform float u_outline_width = 0.0016;
uniform vec4 u_outline_color : source_color = vec4(0.09, 0.08, 0.14, 1.0);

void vertex() {
	VERTEX += NORMAL * u_outline_width;
}

void fragment() {
	ALBEDO = u_outline_color.rgb;
	ALPHA = 1.0;
}
