shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ---------------------------------------------------------------------------
// PROCEDURAL CORRUGATED CONTAINER SHADER
// Renders authentic ISO shipping container corrugation, groove grime,
// rust weathering, and edge wear — removing the flat plastic look.
// ---------------------------------------------------------------------------

uniform vec4 container_color : source_color = vec4(0.18, 0.40, 0.65, 1.0);
uniform vec4 rust_color : source_color = vec4(0.48, 0.22, 0.12, 1.0);
uniform vec4 grime_color : source_color = vec4(0.12, 0.12, 0.13, 1.0);

uniform float rib_frequency : hint_range(5.0, 50.0) = 18.0;
uniform float rib_depth : hint_range(0.0, 2.0) = 0.85;
uniform float rust_amount : hint_range(0.0, 1.0) = 0.35;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.40;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.62;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.28;

uniform sampler2D detail_noise : hint_default_black, repeat_enable;

// Pseudo-random hash
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// Triplanar or projected local coordinate determination
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_norm = abs(normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz));

	// Pick coordinate along length for side walls vs end walls
	float rib_coord = (world_norm.x > 0.5) ? world_pos.z : world_pos.x;
	float vert_coord = world_pos.y;

	// 1. Trapezoidal wave for corrugated ribs
	float phase = fract(rib_coord * (rib_frequency * 0.1));
	// S-curve for steep corrugated ridge flanks
	float rib_slope = clamp((phase - 0.25) * 8.0, -1.0, 1.0) - clamp((phase - 0.75) * 8.0, -1.0, 1.0);
	float rib_height = clamp(sin(phase * TAU) * 1.5, -1.0, 1.0);

	// Normal perturbation for corrugation
	vec3 perturbed_normal = NORMAL;
	if (world_norm.y < 0.8) { // Only corrugate vertical walls, keep roof flat
		perturbed_normal.x += rib_slope * rib_depth * (world_norm.z > 0.5 ? 1.0 : 0.0);
		perturbed_normal.z += rib_slope * rib_depth * (world_norm.x > 0.5 ? 1.0 : 0.0);
	}
	NORMAL = normalize(perturbed_normal);

	// 2. Grime in recessed grooves
	float in_groove = clamp(1.0 - rib_height, 0.0, 1.0) * 0.6;

	// 3. Procedural Weathering & Rust Patches
	vec2 uv_noise = vec2(rib_coord * 0.8, vert_coord * 0.6);
	float n = noise(uv_noise * 3.0) * 0.6 + noise(uv_noise * 8.0) * 0.4;
	
	// Rust drips down from top rim and collects at bottom
	float bottom_bias = clamp((2.6 - vert_coord) * 0.4, 0.0, 1.0);
	float top_bias = clamp((vert_coord - 2.0) * 0.5, 0.0, 0.8);
	float rust_mask = smoothstep(0.70 - rust_amount * 0.35, 1.0, n + bottom_bias * 0.3 + top_bias * 0.2);

	// 4. Combine Albedo
	vec3 col = container_color.rgb;
	col = mix(col, grime_color.rgb, in_groove * 0.4);
	col = mix(col, rust_color.rgb, rust_mask);

	// Chipped paint edge highlights
	float edge_chip = smoothstep(0.85, 0.95, n) * edge_wear;
	col = mix(col, vec3(0.18, 0.19, 0.20), edge_chip);

	ALBEDO = col;
	// Rust is matte and rough; steel paint has slight sheen
	ROUGHNESS = mix(base_roughness, 0.92, rust_mask);
	METALLIC = mix(base_metallic, 0.05, rust_mask);
	SPECULAR = 0.35;
}
