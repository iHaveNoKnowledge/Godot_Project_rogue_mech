shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ---------------------------------------------------------------------------
// PROCEDURAL SCRAP METAL PLATE SHADER
//
// Renders authentic scavenged scrap plates with welded seam edges, surface rust,
// micro-scratches, carbon scorches, and bolt/rivet accents.
// ---------------------------------------------------------------------------

uniform vec4 plate_color : source_color = vec4(0.32, 0.35, 0.38, 1.0);
uniform vec4 rust_color : source_color = vec4(0.48, 0.22, 0.08, 1.0);
uniform vec4 weld_color : source_color = vec4(0.12, 0.12, 0.14, 1.0);
uniform float rust_intensity : hint_range(0.0, 1.0) = 0.45;
uniform float metalness : hint_range(0.0, 1.0) = 0.75;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.45;


// 3D hash
vec3 hash3(vec3 p) {
	p = vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	);
	return fract(sin(p) * 43758.5453123);
}


// Value noise for rust patches
float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash3(i + vec3(0, 0, 0)).x;
	float n100 = hash3(i + vec3(1, 0, 0)).x;
	float n010 = hash3(i + vec3(0, 1, 0)).x;
	float n110 = hash3(i + vec3(1, 1, 0)).x;
	float n001 = hash3(i + vec3(0, 0, 1)).x;
	float n101 = hash3(i + vec3(1, 0, 1)).x;
	float n011 = hash3(i + vec3(0, 1, 1)).x;
	float n111 = hash3(i + vec3(1, 1, 1)).x;

	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}


void fragment() {
	vec3 p = VERTEX * 12.0;

	// 1. Rust patch generation (multi-octave noise)
	float n1 = value_noise(p);
	float n2 = value_noise(p * 2.5);
	float rust_noise = mix(n1, n2, 0.4);
	float rust_mask = smoothstep(1.0 - rust_intensity * 0.8, 1.0, rust_noise);

	// 2. Weld seam & edge scorch detection via UV coordinates
	vec2 edge_dist = abs(UV - vec2(0.5)) * 2.0;
	float edge_factor = max(edge_dist.x, edge_dist.y);
	float weld_mask = smoothstep(0.78, 0.98, edge_factor);

	// 3. Surface scratches & micro imperfections
	float scratch = value_noise(p * 5.0) * 0.15;

	// 4. Color blending
	vec3 col = plate_color.rgb;
	col = mix(col, rust_color.rgb, rust_mask * 0.85);
	col = mix(col, weld_color.rgb, weld_mask * 0.9);
	col += (scratch - 0.075);

	ALBEDO = col;
	METALLIC = mix(metalness, 0.05, rust_mask * 0.7 + weld_mask * 0.3);
	ROUGHNESS = mix(roughness_base, 0.9, rust_mask * 0.8 + weld_mask * 0.4);
}
