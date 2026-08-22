shader_type spatial;
render_mode blend_add, cull_disabled, depth_draw_opaque, unshaded;

uniform vec4 base_color : source_color = vec4(0.2, 0.75, 1.0, 0.45);
uniform vec4 scan_color : source_color = vec4(0.8, 0.95, 1.0, 0.85);
uniform float scanline_count : hint_range(5.0, 60.0) = 24.0;
uniform float scan_speed : hint_range(0.1, 5.0) = 1.2;
uniform float grid_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float rim_power : hint_range(0.5, 6.0) = 2.5;

void fragment() {
	// Vertical scanline animation
	float v_scan = sin((UV.y * scanline_count) - (TIME * scan_speed * 3.14159)) * 0.5 + 0.5;
	float h_grid = sin(UV.x * scanline_count * 2.0) * 0.5 + 0.5;
	float grid_pattern = pow(v_scan * h_grid, 0.6) * grid_intensity;

	// Height gradient: fade out near top
	float height_fade = 1.0 - smoothstep(0.75, 1.0, UV.y);
	float bottom_glow = exp(-UV.y * 3.0) * 0.5;

	// View-angle rim glow
	float fresnel = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	float rim = pow(fresnel, rim_power);

	vec3 col = mix(base_color.rgb, scan_color.rgb, grid_pattern * 0.7);
	col += scan_color.rgb * rim * 0.8;
	col += base_color.rgb * bottom_glow;

	ALBEDO = col;
	ALPHA = clamp((base_color.a * (0.3 + grid_pattern * 0.7 + rim * 0.6 + bottom_glow)) * height_fade, 0.0, 0.95);
}
