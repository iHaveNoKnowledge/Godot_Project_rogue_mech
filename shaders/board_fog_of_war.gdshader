shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// Volumetric Shroud Parameters
uniform vec4 fog_color : source_color = vec4(0.08, 0.10, 0.14, 0.94);
uniform vec4 fog_edge_color : source_color = vec4(0.18, 0.22, 0.32, 1.0);
uniform vec4 dissolve_burn_color : source_color = vec4(0.3, 0.8, 1.0, 1.0);

uniform float density : hint_range(0.1, 2.0) = 1.0;
uniform float animation_speed : hint_range(0.0, 2.0) = 0.35;
uniform float noise_scale : hint_range(1.0, 20.0) = 6.0;

// Dissolve progress: 0.0 = fully shrouded in dense fog, 1.0 = fully dissolved/revealed
uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;

float hash3d(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.1, 0.1));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3d(i + vec3(0,0,0)), hash3d(i + vec3(1,0,0)), f.x),
	               mix(hash3d(i + vec3(0,1,0)), hash3d(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash3d(i + vec3(0,0,1)), hash3d(i + vec3(1,0,1)), f.x),
	               mix(hash3d(i + vec3(0,1,1)), hash3d(i + vec3(1,1,1)), f.x), f.y), f.z);
}

float fbm3d(vec3 p) {
	float val = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 3; i++) {
		val += amp * noise3d(p);
		p *= 2.05;
		amp *= 0.5;
	}
	return val;
}

void vertex() {
	// Slight billow displacement on fog surface
	vec3 world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(TIME * 1.5 + world_p.x * 0.8 + world_p.z * 0.8) * 0.08;
	VERTEX.y += wave * (1.0 - dissolve_progress);
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wind = vec3(TIME * animation_speed * 0.6, TIME * animation_speed * 0.2, TIME * animation_speed * 0.4);
	float n = fbm3d((world_pos + wind) * (noise_scale * 0.05));

	// Distance from center of tile
	vec2 center_dist = abs(UV - vec2(0.5)) * 2.0;
	float edge_mask = 1.0 - smoothstep(0.7, 1.0, max(center_dist.x, center_dist.y));

	// Dissolve logic: higher dissolve_progress strips fog from center outward
	float dissolve_thresh = dissolve_progress * 1.35;
	float mask = smoothstep(dissolve_thresh - 0.15, dissolve_thresh + 0.15, n * edge_mask);

	// Luminous burn edge during reveal
	float burn_edge = smoothstep(dissolve_thresh - 0.08, dissolve_thresh, n * edge_mask) * (1.0 - smoothstep(dissolve_thresh, dissolve_thresh + 0.08, n * edge_mask));

	vec3 col = mix(fog_color.rgb, fog_edge_color.rgb, n * 0.6);
	if (dissolve_progress > 0.01 && dissolve_progress < 0.99) {
		col += dissolve_burn_color.rgb * burn_edge * 3.0;
	}

	ALBEDO = col;
	ALPHA = (1.0 - dissolve_progress) * mask * fog_color.a;
}
