shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// War Terrain — whole-map PBR for 2000x2000 WarBiomeGenerator chunks
// Uses per-vertex COLOR (biome tint + slope shading) * tiled albedo texture
// No extra textures required: works with vertex color only, but supports optional maps.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_tex = false;

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal_tex = false;

uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_roughness_tex = false;

uniform float uv_scale : hint_range(0.5, 32.0) = 8.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.02;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

// World height tint — canyon darkening / mesa sun lift already in vertex color,
// this adds macro AO at edges of map.
uniform float edge_darkening : hint_range(0.0, 0.5) = 0.12;

varying vec3 world_pos;
varying vec4 v_color;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_color = COLOR;
}

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV * uv_scale;

	vec3 tex_albedo = has_albedo_tex ? texture(albedo_tex, uv).rgb : vec3(1.0);
	// Micro hash breaks flat plastic look when no texture
	float micro = hash2(floor(uv * 64.0));
	float micro2 = hash2(floor(uv * 113.0 + vec2(17.0, 9.0)));

	// Base = vertex biome color * texture (if any)
	vec3 base = v_color.rgb * tex_albedo;
	// Slight micro bright/dark variation +-4%
	base *= 0.96 + micro * 0.08;

	// Normal
	vec3 n = vec3(0.0, 0.0, 1.0);
	if (has_normal_tex) {
		n = texture(normal_tex, uv).rgb * 2.0 - 1.0;
		n.xy *= normal_strength;
		n = normalize(n);
	} else {
		// Procedural wobble to avoid flat clay
		float n1 = hash2(uv * 32.0);
		float n2 = hash2(uv * 64.0 + vec2(7.0, 3.0));
		n = normalize(vec3((n1 - 0.5) * 0.35, (n2 - 0.5) * 0.35, 1.0));
	}

	// Roughness with micro jitter
	float r = roughness;
	if (has_roughness_tex) {
		r = texture(roughness_tex, uv).r * roughness;
	} else {
		r = clamp(r + (micro2 - 0.5) * 0.16, 0.72, 0.98);
	}

	// Height-based edge darkening: mesa top slightly lighter, canyon slightly darker
	// Already baked in vertex color, add subtle world-space noise
	float height_factor = clamp((world_pos.y + 14.0) / 38.0, 0.0, 1.0); // -14 .. +24
	base = mix(base * 0.88, base * 1.06, height_factor);

	// Map border soft darken (2000x2000 half=1000)
	float edge = max(abs(world_pos.x), abs(world_pos.z));
	if (edge > 850.0) {
		float t = clamp((edge - 850.0) / 150.0, 0.0, 1.0);
		base *= mix(1.0, 1.0 - edge_darkening, t);
	}

	ALBEDO = base;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = r;
	METALLIC = metallic;
	SPECULAR = 0.30;
}
