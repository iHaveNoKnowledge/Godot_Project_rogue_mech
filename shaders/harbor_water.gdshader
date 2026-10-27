shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// ---------------------------------------------------------------------------
// HARBOR BASIN WATER SHADER
// Features: Dual scrolling normal wave simulation, depth color absorption,
// shoreline/quay wall foam contact line, and Fresnel water reflection.
// ---------------------------------------------------------------------------

uniform vec4 deep_water_color : source_color = vec4(0.04, 0.12, 0.20, 0.95);
uniform vec4 shallow_water_color : source_color = vec4(0.08, 0.32, 0.42, 0.85);
uniform vec4 foam_color : source_color = vec4(0.85, 0.92, 0.96, 1.0);

uniform float wave_speed_1 : hint_range(0.0, 1.0) = 0.05;
uniform float wave_speed_2 : hint_range(0.0, 1.0) = 0.03;
uniform float wave_scale : hint_range(0.1, 20.0) = 4.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.08;
uniform float metallic : hint_range(0.0, 1.0) = 0.80;
uniform float foam_distance : hint_range(0.0, 3.0) = 0.75;
uniform float depth_distance : hint_range(0.1, 20.0) = 4.5;

uniform sampler2D normal_map_1 : hint_normal, repeat_enable;
uniform sampler2D normal_map_2 : hint_normal, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

void vertex() {
	// Subtle undulating vertex displacement for calm harbor swells
	float t = TIME * 1.2;
	VERTEX.y += sin(VERTEX.x * 0.3 + t) * cos(VERTEX.z * 0.3 + t * 0.8) * 0.08;
}

void fragment() {
	// 1. Dual scrolling wave normal calculation
	vec2 uv1 = UV * wave_scale + vec2(TIME * wave_speed_1, TIME * wave_speed_1 * 0.6);
	vec2 uv2 = UV * wave_scale * 1.4 - vec2(TIME * wave_speed_2 * 0.8, TIME * wave_speed_2);

	vec3 n1 = texture(normal_map_1, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_map_2, uv2).rgb * 2.0 - 1.0;
	vec3 wave_normal = normalize(n1 + n2);

	NORMAL = normalize(mix(NORMAL, wave_normal, 0.65));

	// 2. Depth buffer calculation for depth-based color absorption & contact foam
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_coords /= view_coords.w;
	float linear_depth = -view_coords.z;
	float surface_depth = -VERTEX.z;
	float depth_diff = max(0.0, linear_depth - surface_depth);

	// Deep water vs shallow water gradient
	float depth_factor = clamp(depth_diff / depth_distance, 0.0, 1.0);
	vec4 water_col = mix(shallow_water_color, deep_water_color, depth_factor);

	// Contact foam against quay walls and ship hull
	float foam_factor = clamp((foam_distance - depth_diff) / foam_distance, 0.0, 1.0);
	foam_factor = pow(foam_factor, 1.8);

	// Add noise jitter to the foam line
	foam_factor *= (0.6 + 0.4 * sin(UV.x * 35.0 + TIME * 2.0));

	vec3 final_color = mix(water_col.rgb, foam_color.rgb, foam_factor);

	ALBEDO = final_color;
	ROUGHNESS = mix(roughness, 0.35, foam_factor);
	METALLIC = mix(metallic, 0.0, foam_factor);
	SPECULAR = 0.9;
	ALPHA = mix(water_col.a, 1.0, foam_factor);
}
