shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Textures and PBR parameters
uniform bool has_albedo_tex = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;

uniform bool has_normal_tex = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;

uniform bool has_roughness_tex = false;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness_scale : hint_range(0.0, 1.0) = 0.85;
uniform float uv_scale : hint_range(0.5, 8.0) = 2.0;

// Edge feathering & Organic Blending
uniform float edge_feather : hint_range(0.01, 0.45) = 0.22;
uniform float noise_blend_strength : hint_range(0.0, 1.0) = 0.48;

// Interactive Highlights
uniform vec4 highlight_color : source_color = vec4(0.25, 0.75, 1.0, 1.0);
uniform float highlight_intensity : hint_range(0.0, 2.0) = 0.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 3.0;

// Weather Tinting
uniform vec4 weather_tint_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float weather_tint_strength : hint_range(0.0, 1.0) = 0.0;
uniform float weather_roughness_mod : hint_range(-1.0, 1.0) = 0.0;

// Simple procedural hash noise for organic border distortion
float hash2d(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float smooth_noise(vec2 uv) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2d(i);
	float b = hash2d(i + vec2(1.0, 0.0));
	float c = hash2d(i + vec2(0.0, 1.0));
	float d = hash2d(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 uv) {
	float val = 0.0;
	float amp = 0.5;
	for (int n = 0; n < 3; n++) {
		val += amp * smooth_noise(uv);
		uv *= 2.1;
		amp *= 0.5;
	}
	return val;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 tex_color = has_albedo_tex ? texture(albedo_tex, uv) : vec4(1.0);
	vec3 norm = has_normal_tex ? (texture(normal_tex, uv).rgb * 2.0 - 1.0) : vec3(0.0, 0.0, 1.0);
	float rough = has_roughness_tex ? (texture(roughness_tex, uv).r * roughness_scale) : roughness_scale;

	// Calculate distance to tile borders [0..1]
	vec2 border_dist = min(UV, vec2(1.0) - UV);
	float min_dist = min(border_dist.x, border_dist.y);

	// Add procedural noise to break the straight square cut lines
	float noise_val = (fbm(UV * 12.0) - 0.5) * noise_blend_strength;
	float blend_factor = smoothstep(0.0, edge_feather, min_dist + noise_val * edge_feather);

	// Composite albedo with base tint
	vec3 final_color = tex_color.rgb * base_color.rgb;

	// Highlight pulse (for reachable / selected / hovered tiles)
	if (highlight_intensity > 0.01) {
		float pulse = sin(TIME * pulse_speed) * 0.25 + 0.75;
		final_color = mix(final_color, highlight_color.rgb * 1.3, highlight_intensity * pulse);
		rough = mix(rough, 0.3, highlight_intensity * 0.5);
	}

	// Weather tinting (fog=blue, rain=wet sheen, sandstorm=amber, dust=warm haze)
	if (weather_tint_strength > 0.01) {
		final_color = mix(final_color, weather_tint_color.rgb, weather_tint_strength * 0.35);
		rough = clamp(rough + weather_roughness_mod * weather_tint_strength, 0.0, 1.0);
	}

	// Soft edge transition to avoid sharp square tile seams
	ALBEDO = final_color;
	NORMAL_MAP = norm;
	NORMAL_MAP_DEPTH = 0.75;
	ROUGHNESS = rough;
	METALLIC = 0.05;
	ALPHA = mix(0.85, 1.0, blend_factor);
}
