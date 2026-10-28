shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// ---------------------------------------------------------------------------
// ADVANCED GERSTNER FLUID WATER SHADER
// 4-component Trochoidal Gerstner Waves, screen-space refraction,
// depth color absorption (Beer-Lambert law), wave crest foam, and shore contact.
// ---------------------------------------------------------------------------

uniform vec4 deep_color : source_color = vec4(0.03, 0.10, 0.18, 0.95);
uniform vec4 shallow_color : source_color = vec4(0.08, 0.36, 0.44, 0.82);
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);

uniform float beer_law_factor : hint_range(0.01, 2.0) = 0.35;
uniform float refraction_strength : hint_range(0.0, 0.1) = 0.035;
uniform float wave_steepness : hint_range(0.0, 1.0) = 0.28;
uniform float time_speed : hint_range(0.0, 3.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.06;
uniform float metallic : hint_range(0.0, 1.0) = 0.85;

uniform sampler2D normal_bump_1 : hint_normal, repeat_enable;
uniform sampler2D normal_bump_2 : hint_normal, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Gerstner Wave parameters: dir_x, dir_z, steepness, wavelength
const vec4 wave_1 = vec4(1.0, 0.2, 0.25, 12.0);
const vec4 wave_2 = vec4(0.6, 0.8, 0.20, 8.5);
const vec4 wave_3 = vec4(-0.3, 0.95, 0.15, 5.0);
const vec4 wave_4 = vec4(0.8, -0.6, 0.12, 3.2);

vec3 gerstner_wave(vec4 wave, vec3 p, inout vec3 tangent, inout vec3 binormal, float t) {
	float steepness = wave.z * wave_steepness;
	float wavelength = wave.w;
	float k = 2.0 * PI / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(wave.xy);
	float f = k * (dot(d, p.xz) - c * t);
	float a = steepness / k;

	tangent += vec3(
		-d.x * d.x * (steepness * sin(f)),
		d.x * (steepness * cos(f)),
		-d.x * d.y * (steepness * sin(f))
	);
	binormal += vec3(
		-d.x * d.y * (steepness * sin(f)),
		d.y * (steepness * cos(f)),
		-d.y * d.y * (steepness * sin(f))
	);

	return vec3(
		d.x * (a * cos(f)),
		a * sin(f),
		d.y * (a * cos(f))
	);
}

varying float v_crest_foam;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * time_speed;

	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 wave_disp = vec3(0.0);

	wave_disp += gerstner_wave(wave_1, world_pos, tangent, binormal, t);
	wave_disp += gerstner_wave(wave_2, world_pos, tangent, binormal, t);
	wave_disp += gerstner_wave(wave_3, world_pos, tangent, binormal, t);
	wave_disp += gerstner_wave(wave_4, world_pos, tangent, binormal, t);

	VERTEX += (VIEW_MATRIX * vec4(wave_disp, 0.0)).xyz;
	vec3 normal = normalize(cross(binormal, tangent));
	NORMAL = (VIEW_MATRIX * vec4(normal, 0.0)).xyz;

	// Crest foam on wave peaks
	v_crest_foam = clamp((wave_disp.y - 0.15) * 4.0, 0.0, 1.0);
}

void fragment() {
	float t = TIME * time_speed * 0.4;
	vec2 uv_detail = UV * 12.0;
	vec3 n1 = texture(normal_bump_1, uv_detail + vec2(t * 0.05, t * 0.02)).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_bump_2, uv_detail * 1.5 - vec2(t * 0.03, t * 0.06)).rgb * 2.0 - 1.0;
	vec3 micro_normal = normalize(n1 + n2);
	NORMAL = normalize(mix(NORMAL, micro_normal, 0.35));

	// 1. Depth & Shore Foam Calculation
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_coords /= view_coords.w;
	float linear_depth = -view_coords.z;
	float surface_depth = -VERTEX.z;
	float depth_diff = max(0.0, linear_depth - surface_depth);

	// Beer-Lambert law depth transmission
	float depth_transmission = exp(-depth_diff * beer_law_factor);
	vec3 water_color = mix(deep_color.rgb, shallow_color.rgb, depth_transmission);

	// 2. Refraction distortion
	vec2 refr_offset = NORMAL.xz * refraction_strength * clamp(depth_diff * 0.5, 0.0, 1.0);
	vec3 refracted_scene = texture(screen_texture, SCREEN_UV + refr_offset).rgb;
	// Blend water tint with distorted underwater view
	vec3 final_fluid = mix(water_color, refracted_scene, depth_transmission * 0.5);

	// 3. Shoreline & Quay Wall Contact Foam
	float shore_foam = clamp((0.85 - depth_diff) / 0.85, 0.0, 1.0);
	shore_foam = pow(shore_foam, 1.6);
	shore_foam *= (0.7 + 0.3 * sin(UV.x * 40.0 + TIME * 3.0));

	// Combine wave crest foam and shore foam
	float total_foam = clamp(shore_foam + v_crest_foam * 0.75, 0.0, 1.0);
	vec3 final_albedo = mix(final_fluid, foam_color.rgb, total_foam);

	ALBEDO = final_albedo;
	ROUGHNESS = mix(roughness, 0.45, total_foam);
	METALLIC = mix(metallic, 0.0, total_foam);
	SPECULAR = 0.95;
	ALPHA = mix(clamp(1.0 - depth_transmission * 0.3, 0.85, 1.0), 1.0, total_foam);
}
