shader_type canvas_item;

// Finger press dip amounts for fingers 0 to 4 (0.0: idle/rest, 1.0: fully pressed down)
uniform vec4 u_finger_dips_1_4 = vec4(0.0); // x: finger 0, y: finger 1, z: finger 2, w: finger 3
uniform float u_finger_dip_5 = 0.0;         // finger 4

// Finger horizontal center in UV space [0.0, 1.0]
uniform vec4 u_finger_centers_1_4 = vec4(0.071, 0.285, 0.445, 0.640);
uniform float u_finger_center_5 = 0.943;

// Finger column width influence (gaussian spread)
uniform vec4 u_finger_widths_1_4 = vec4(0.065, 0.055, 0.055, 0.065);
uniform float u_finger_width_5 = 0.085;

// Physical displacement settings (normalized to hand scale)
uniform float u_max_dip = 0.055;
uniform float u_flesh_spread = 0.018;
uniform float u_wrist_fade_start = 0.72;
uniform float u_time = 0.0;
uniform bool u_is_shadow = false;

void vertex() {
	// UV is in range [0, 1]. Fingertips are at UV.y ~ 0.0, wrist is at UV.y ~ 1.0.
	// Only the fingers and knuckles articulate (UV.y < 0.65). Palm & wrist remain stable.
	float vert_reach = smoothstep(0.68, 0.05, UV.y);
	
	// Gaussian weights for each finger column
	float d0 = UV.x - u_finger_centers_1_4.x;
	float w0 = exp(-d0 * d0 / (2.0 * u_finger_widths_1_4.x * u_finger_widths_1_4.x));
	
	float d1 = UV.x - u_finger_centers_1_4.y;
	float w1 = exp(-d1 * d1 / (2.0 * u_finger_widths_1_4.y * u_finger_widths_1_4.y));
	
	float d2 = UV.x - u_finger_centers_1_4.z;
	float w2 = exp(-d2 * d2 / (2.0 * u_finger_widths_1_4.z * u_finger_widths_1_4.z));
	
	float d3 = UV.x - u_finger_centers_1_4.w;
	float w3 = exp(-d3 * d3 / (2.0 * u_finger_widths_1_4.w * u_finger_widths_1_4.w));
	
	float d4 = UV.x - u_finger_center_5;
	float w4 = exp(-d4 * d4 / (2.0 * u_finger_width_5 * u_finger_width_5));
	
	// Natural idle breathing micro-motion per finger
	float micro0 = sin(u_time * 2.2 + 0.0) * 0.05;
	float micro1 = sin(u_time * 2.4 + 1.2) * 0.05;
	float micro2 = sin(u_time * 2.1 + 2.3) * 0.05;
	float micro3 = sin(u_time * 2.5 + 3.4) * 0.05;
	float micro4 = sin(u_time * 2.0 + 4.5) * 0.05;
	
	float dip0 = u_finger_dips_1_4.x + micro0;
	float dip1 = u_finger_dips_1_4.y + micro1;
	float dip2 = u_finger_dips_1_4.z + micro2;
	float dip3 = u_finger_dips_1_4.w + micro3;
	float dip4 = u_finger_dip_5 + micro4;
	
	// Vertical displacement: finger tips extend and press down onto the key surface
	float total_dip = (w0 * dip0 + w1 * dip1 + w2 * dip2 + w3 * dip3 + w4 * dip4);
	float disp_y = total_dip * u_max_dip * vert_reach;
	
	// Horizontal flesh spreading: fingertips cushion against the key on contact
	float spread_x = (w0 * d0 * dip0 +
	                  w1 * d1 * dip1 +
	                  w2 * d2 * dip2 +
	                  w3 * d3 * dip3 +
	                  w4 * d4 * dip4) * u_flesh_spread * vert_reach;
	
	VERTEX.y += disp_y;
	VERTEX.x += spread_x;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Smooth wrist fade-out gradient to cleanly blend the arm into the lower screen
	float wrist_alpha = 1.0 - smoothstep(u_wrist_fade_start, 1.0, UV.y);
	
	if (u_is_shadow) {
		COLOR = vec4(0.0, 0.0, 0.0, tex.a * wrist_alpha * 0.22);
	} else {
		COLOR = vec4(tex.rgb, tex.a * wrist_alpha * COLOR.a);
	}
}
