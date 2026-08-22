shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// ---------------------------------------------------------------------------
// PROCEDURAL CLOTH / ARMOR BANDAGE WRAP SHADER
//
// Renders woven cloth bandages, wraps, and cloaks with fabric texture,
// frayed fiber noise, dirt/oil stains, and realistic cloth micro-roughness.
// ---------------------------------------------------------------------------

uniform vec4 cloth_color : source_color = vec4(0.72, 0.68, 0.60, 1.0);
uniform vec4 stain_color : source_color = vec4(0.18, 0.16, 0.14, 1.0);
uniform float weave_density : hint_range(10.0, 150.0) = 60.0;
uniform float stain_intensity : hint_range(0.0, 1.0) = 0.55;


// Fast hash
float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// 2D noise for stains
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


void fragment() {
	// 1. Procedural fabric cross-weave pattern
	vec2 uv_scaled = UV * weave_density;
	float weave_x = sin(uv_scaled.x * 3.14159);
	float weave_y = cos(uv_scaled.y * 3.14159);
	float weave_pattern = (weave_x * weave_y) * 0.12;

	// 2. Grease, oil & battle dirt stains
	float stain_noise = noise2(UV * 8.0) * 0.7 + noise2(UV * 18.0) * 0.3;
	float stain_factor = smoothstep(1.0 - stain_intensity * 0.75, 1.0, stain_noise);

	// 3. Shading & Color
	vec3 base = cloth_color.rgb + vec3(weave_pattern);
	vec3 final_color = mix(base, stain_color.rgb, stain_factor * 0.85);

	ALBEDO = final_color;
	ROUGHNESS = mix(0.92, 0.65, stain_factor); // Wet grease is slightly smoother
	METALLIC = 0.0;
	SPECULAR = 0.1;
}
