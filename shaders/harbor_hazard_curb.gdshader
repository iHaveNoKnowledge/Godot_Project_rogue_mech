shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ---------------------------------------------------------------------------
// HARBOR HAZARD CURB SHADER
// Renders 45-degree yellow/black safety stripes with chipped paint and concrete scuffs.
// ---------------------------------------------------------------------------

uniform vec4 yellow_color : source_color = vec4(0.92, 0.74, 0.10, 1.0);
uniform vec4 black_color : source_color = vec4(0.12, 0.13, 0.14, 1.0);
uniform vec4 concrete_color : source_color = vec4(0.52, 0.54, 0.56, 1.0);

uniform float stripe_scale : hint_range(0.5, 10.0) = 2.0;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.35;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;

float hash(vec2 p) {
	p = fract(p * vec2(234.34, 435.21));
	p += dot(p, p + 23.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Diagonal stripe coordinate
	float coord = (world_pos.x + world_pos.z) * stripe_scale;
	float stripe = step(0.5, fract(coord));

	vec3 base_col = mix(black_color.rgb, yellow_color.rgb, stripe);

	// Scuffs, chips, and exposed concrete
	vec2 uv_noise = world_pos.xz * 2.5;
	float n = noise(uv_noise) * 0.7 + noise(uv_noise * 4.0) * 0.3;
	float chip = smoothstep(1.0 - wear_amount * 0.5, 1.0, n);

	vec3 final_col = mix(base_col, concrete_color.rgb, chip);

	ALBEDO = final_col;
	ROUGHNESS = mix(roughness, 0.95, chip);
	METALLIC = 0.05;
	SPECULAR = 0.25;
}
