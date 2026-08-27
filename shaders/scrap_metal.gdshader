shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ---------------------------------------------------------------------------
// PROCEDURAL SCRAP METAL PLATE SHADER
//
// Renders authentic scavenged scrap plates with welded seam edges, surface rust,
// micro-scratches, carbon scorches, and bolt/rivet accents.
// Rust is MATTE and pitted — not glossy chocolate.
// ---------------------------------------------------------------------------

uniform vec4 plate_color : source_color = vec4(0.30, 0.33, 0.36, 1.0);
uniform vec4 rust_color : source_color = vec4(0.60, 0.28, 0.10, 1.0);
uniform vec4 weld_color : source_color = vec4(0.10, 0.11, 0.13, 1.0);
uniform float rust_intensity : hint_range(0.0, 1.0) = 0.45;
uniform float metalness : hint_range(0.0, 1.0) = 0.62;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.38;


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

	// 1. Multi-tone rust patch generation (3 octaves)
	float n1 = value_noise(p);
	float n2 = value_noise(p * 2.3 + vec3(4.1, 7.2, 2.8));
	float n3 = value_noise(p * 5.7);
	float rust_noise = n1 * 0.52 + n2 * 0.30 + n3 * 0.18;
	// Streaks where rust bleeds down plate
	float streak_n = value_noise(vec3(p.x * 0.55, p.y * 1.8, p.z * 0.55));
	float streak_mask = smoothstep(0.72, 0.88, streak_n) * 0.28;

	float rust_mask = smoothstep(1.0 - rust_intensity * 0.92, 1.0, rust_noise);
	rust_mask = clamp(rust_mask + streak_mask * 0.35, 0.0, 1.0);

	// 2. Weld seam & edge scorch detection via UV coordinates
	vec2 edge_dist = abs(UV - vec2(0.5)) * 2.0;
	float edge_factor = max(edge_dist.x, edge_dist.y);
	float weld_mask = smoothstep(0.78, 0.98, edge_factor);
	// Sooty halo around weld
	float weld_halo = smoothstep(0.70, 0.82, edge_factor) * 0.25;

	// 3. Micro pitting & scratches
	float pit = value_noise(p * 6.0);
	float scratch = value_noise(p * 5.0) * 0.12;

	// 4. Multi-tone rust palette — not flat chocolate
	vec3 rust_light = vec3(0.70, 0.36, 0.12);
	vec3 rust_mid = rust_color.rgb;
	vec3 rust_dark = vec3(0.36, 0.16, 0.06);
	vec3 rust_pit = vec3(0.20, 0.10, 0.05);
	vec3 rust_col = mix(rust_dark, rust_mid, clamp(n1 * 1.35, 0.0, 1.0));
	rust_col = mix(rust_col, rust_light, smoothstep(0.60, 0.85, n2) * 0.40);
	rust_col = mix(rust_col, rust_pit, smoothstep(0.70, 0.92, n3) * 0.18);
	rust_col = mix(rust_col, rust_dark * 0.78, streak_mask * 0.45);

	// 5. Color blending — matte, dusty
	vec3 col = plate_color.rgb;
	// Rust areas get the multi-tone rust, not single chocolate
	col = mix(col, rust_col, rust_mask * 0.96);
	col = mix(col, weld_color.rgb, weld_mask * 0.92);
	col = mix(col, weld_color.rgb * 0.65, weld_halo * rust_mask * 0.5);
	// Micro-AO in pits
	col *= 1.0 - smoothstep(0.70, 0.93, pit) * 0.10 * rust_mask;
	col += (scratch - 0.06) * (1.0 - rust_mask * 0.5);

	ALBEDO = col;

	// 6. PBR — RUST IS DIELECTRIC AND VERY ROUGH (powdery oxide, not metal)
	float rust_rough = 0.96 + n3 * 0.03; // 0.96-0.99
	float plate_rough = roughness_base + pit * 0.08;
	float r = mix(plate_rough, rust_rough, rust_mask * 0.98);
	r = mix(r, 0.88, weld_mask * 0.55);
	ROUGHNESS = clamp(r, 0.0, 1.0);

	float rust_metal = 0.012; // nearly non-metal
	float r_metal = mix(metalness, rust_metal, rust_mask * 0.96);
	r_metal = mix(r_metal, 0.28, weld_mask * 0.45);
	METALLIC = clamp(r_metal, 0.0, 1.0);

	// 7. Subtle normal pitting — breaks flat look
	vec3 h = hash3(p * 38.0);
	vec3 pitting = (h - 0.5) * 0.14 * rust_mask;
	NORMAL = normalize(NORMAL + pitting);
}
