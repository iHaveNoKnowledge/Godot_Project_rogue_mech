shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// -----------------------------------------------------------------------------
// ROGUE-MECH MASTER PBR SHADER
// Semi-Realistic Stylized PBR with Triplanar Paneling, Edge Wear, and Emissive
// -----------------------------------------------------------------------------

group_uniforms BaseColors;
uniform vec4 primary_color : source_color = vec4(0.28, 0.32, 0.38, 1.0);
uniform vec4 trim_color : source_color = vec4(0.12, 0.14, 0.18, 1.0);
uniform vec4 undercoat_metal_color : source_color = vec4(0.82, 0.85, 0.90, 1.0);
uniform float trim_mask_amount : hint_range(0.0, 1.0) = 0.0;

group_uniforms PBRProperties;
// Realistic painted armor: paint is DIELECTRIC (non-metal), only bare metal is metallic.
// Default = matte military paint, not plastic chrome.
uniform float metallic : hint_range(0.0, 1.0) = 0.05;
uniform float roughness : hint_range(0.0, 1.0) = 0.68;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.08;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.60;

group_uniforms PanelingAndDetails;
uniform float panel_grid_scale : hint_range(0.0, 30.0) = 0.0; // Disabled by default to avoid bathroom-tile grid
uniform float panel_line_depth : hint_range(0.0, 1.0) = 0.55;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.12;

group_uniforms PBRTextures;
uniform bool use_pbr_maps = false;
uniform bool use_triplanar = true;
uniform sampler2D pbr_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D pbr_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D pbr_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform sampler2D pbr_ao : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float pbr_uv_scale : hint_range(0.1, 20.0) = 1.5;
uniform float normal_strength : hint_range(0.0, 3.0) = 0.8;

group_uniforms SurfaceDetail;
// ComfyUI-generated armor detail texture (neutral mid-gray multiply overlay).
uniform bool has_detail_tex = false;
uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float detail_uv_scale : hint_range(0.0, 20.0) = 2.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.35;

group_uniforms DamageAndWear;
uniform float scorch_amount : hint_range(0.0, 1.0) = 0.0;
uniform float damage_crack_amount : hint_range(0.0, 1.0) = 0.0;

group_uniforms Emissive;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 20.0) = 0.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 0.0;

varying vec3 v_pos;
varying vec3 v_normal;

void vertex() {
	v_pos = VERTEX;
	v_normal = normalize(NORMAL);
}

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

void fragment() {
	// 1. Base Paint Blend (Primary Hull vs. Secondary Trim)
	vec3 base_color = mix(primary_color.rgb, trim_color.rgb, trim_mask_amount);
	float cur_metallic = metallic;
	float cur_roughness = roughness;
	float cur_ao = 1.0;

	// 1b. Poly Haven PBR Texture Maps (Real metal surface, micro-scratches & roughness variation)
	if (use_pbr_maps) {
		vec3 nw = abs(v_normal);
		float dw = max(nw.x + nw.y + nw.z, 0.001);
		nw /= dw;

		vec3 pbr_alb_val;
		vec3 pbr_norm_val;
		float pbr_rough_val;
		float pbr_ao_val;

		if (use_triplanar) {
			vec3 dp = v_pos * pbr_uv_scale;
			pbr_alb_val = (texture(pbr_albedo, dp.xy).rgb * nw.z +
			               texture(pbr_albedo, dp.xz).rgb * nw.y +
			               texture(pbr_albedo, dp.yz).rgb * nw.x);
			pbr_norm_val = (texture(pbr_normal, dp.xy).rgb * nw.z +
			                texture(pbr_normal, dp.xz).rgb * nw.y +
			                texture(pbr_normal, dp.yz).rgb * nw.x);
			pbr_rough_val = (texture(pbr_roughness, dp.xy).r * nw.z +
			                 texture(pbr_roughness, dp.xz).r * nw.y +
			                 texture(pbr_roughness, dp.yz).r * nw.x);
			pbr_ao_val = (texture(pbr_ao, dp.xy).r * nw.z +
			              texture(pbr_ao, dp.xz).r * nw.y +
			              texture(pbr_ao, dp.yz).r * nw.x);
		} else {
			vec2 uv_scaled = UV * pbr_uv_scale;
			pbr_alb_val = texture(pbr_albedo, uv_scaled).rgb;
			pbr_norm_val = texture(pbr_normal, uv_scaled).rgb;
			pbr_rough_val = texture(pbr_roughness, uv_scaled).r;
			pbr_ao_val = texture(pbr_ao, uv_scaled).r;
		}

		// Tint base paint color with metal micro-grain (luminance normalized around 0.5)
		float alb_lum = dot(pbr_alb_val, vec3(0.299, 0.587, 0.114)) * 1.8;
		base_color *= mix(vec3(1.0), vec3(alb_lum), 0.35);

		// Blend roughness and ambient occlusion
		cur_roughness = clamp(mix(cur_roughness, cur_roughness * (0.6 + 0.8 * pbr_rough_val), 0.7), 0.0, 1.0);
		cur_ao *= pbr_ao_val;

		NORMAL_MAP = pbr_norm_val;
		NORMAL_MAP_DEPTH = normal_strength;
	}

	// 1c. ComfyUI surface detail texture overlay (optional)
	if (has_detail_tex) {
		vec3 dp = v_pos * detail_uv_scale;
		vec3 nw = abs(v_normal);
		vec3 dt = texture(detail_tex, dp.xy).rgb * nw.z
		        + texture(detail_tex, dp.xz).rgb * nw.y
		        + texture(detail_tex, dp.yz).rgb * nw.x;
		float dw = max(nw.x + nw.y + nw.z, 0.001);
		dt /= dw;
		float dg = dot(dt, vec3(0.3333)) * 2.0;
		base_color *= mix(vec3(1.0), vec3(dg), detail_strength);
		cur_roughness = clamp(cur_roughness + (1.0 - dg) * 0.15 * detail_strength, 0.0, 1.0);
	}

	// 2. Procedural Panel Seams (only if intentionally enabled > 0)
	float panel_seam = 0.0;
	if (panel_grid_scale > 0.01 && panel_line_depth > 0.001) {
		vec3 p = v_pos * panel_grid_scale;
		vec3 grid = abs(fract(p - 0.5) - 0.5);
		vec3 fw = max(fwidth(p), vec3(0.001));
		vec3 lines = smoothstep(fw * 0.8, vec3(0.0), grid);

		vec3 n_weight = abs(v_normal);
		n_weight /= max(n_weight.x + n_weight.y + n_weight.z, 0.001);
		panel_seam = (lines.x * (n_weight.y + n_weight.z) +
		              lines.y * (n_weight.x + n_weight.y) +
		              lines.z * (n_weight.x + n_weight.y)) * 0.5;
		panel_seam = clamp(panel_seam * panel_line_depth, 0.0, 1.0);
		
		base_color = mix(base_color, base_color * 0.35, panel_seam);
		cur_roughness = mix(cur_roughness, 0.82, panel_seam * 0.6);
	}

	// 3. Geometry-Aware Edge Wear: paint chips along actual 3D chamfers and silhouette edges
	float wear_mask = 0.0;
	if (edge_wear > 0.001) {
		float geom_edge = clamp(length(fwidth(v_normal)) * 2.8, 0.0, 1.0);
		float n1 = hash31(floor(v_pos * 24.0));
		float n2 = hash31(floor(v_pos * 48.0));
		float micro_noise = (n1 * 0.6 + n2 * 0.4);
		float combined_edge = mix(micro_noise, geom_edge * 0.75 + micro_noise * 0.25, 0.70);
		wear_mask = smoothstep(1.0 - edge_wear * 1.5, 1.0, combined_edge);
		
		// Blend raw metal on worn edges - realistic brushed steel
		base_color = mix(base_color, undercoat_metal_color.rgb, wear_mask);
		cur_metallic = mix(cur_metallic, 0.75, wear_mask);
		cur_roughness = mix(cur_roughness, 0.38, wear_mask);
	}

	// 4. Battle Scorch & Thermal Charring
	if (scorch_amount > 0.001) {
		float scorch_noise = hash31(floor(v_pos * 12.0));
		float char_factor = clamp(scorch_amount * (0.7 + 0.3 * scorch_noise), 0.0, 1.0);
		base_color = mix(base_color, vec3(0.04, 0.04, 0.045), char_factor * 0.88);
		cur_metallic = mix(cur_metallic, 0.02, char_factor * 0.9);
		cur_roughness = mix(cur_roughness, 0.92, char_factor * 0.85);
	}

	// 5. Emissive Glow & Pulsing
	float pulse = 1.0;
	if (pulse_speed > 0.01) {
		pulse = 0.75 + 0.25 * sin(TIME * pulse_speed);
	}
	vec3 emissive_out = emission_color.rgb * (emission_energy * pulse);

	// Output PBR channels
	ALBEDO = base_color;
	METALLIC = cur_metallic;
	ROUGHNESS = clamp(cur_roughness, 0.0, 1.0);
	SPECULAR = 0.35;
	RIM = rim_strength * 0.4;
	RIM_TINT = 0.2;
	AO = cur_ao * (1.0 - (panel_seam * ao_strength));
	AO_LIGHT_AFFECT = 0.65;
	EMISSION = emissive_out;
}
