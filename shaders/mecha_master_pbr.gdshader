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
uniform float panel_grid_scale : hint_range(0.0, 30.0) = 5.0;
uniform float panel_line_depth : hint_range(0.0, 1.0) = 0.55;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.12;

group_uniforms SurfaceDetail;
// ComfyUI-generated armor detail texture (neutral mid-gray multiply overlay).
// Off by default so existing look is unchanged until a texture is bound.
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

	// 1b. ComfyUI surface detail texture (triplanar, neutral mid-gray multiply:
	// mid-gray 0.5 reads as neutral 1.0, darker grime darkens, worn streaks lighten)
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

	// 2. Triplanar Procedural Panel Seams (if enabled)
	float panel_seam = 0.0;
	if (panel_grid_scale > 0.01 && panel_line_depth > 0.001) {
		vec3 p = v_pos * panel_grid_scale;
		vec3 grid = abs(fract(p - 0.5) - 0.5);
		vec3 fw = max(fwidth(p), vec3(0.001));
		vec3 lines = smoothstep(fw * 0.8, vec3(0.0), grid);

		vec3 n_weight = abs(v_normal);
		n_weight /= max(n_weight.x + n_weight.y + n_weight.z, 0.001);
		panel_seam = (lines.x * (n_weight.y + n_weight.z) +
		              lines.y * (n_weight.x + n_weight.z) +
		              lines.z * (n_weight.x + n_weight.y)) * 0.5;
		panel_seam = clamp(panel_seam * panel_line_depth, 0.0, 1.0);
		
		// Darken paint inside panel seams - seams collect dust, rougher and darker
		base_color = mix(base_color, base_color * 0.35, panel_seam);
		cur_roughness = mix(cur_roughness, 0.82, panel_seam * 0.6);
	}

	// 3. Edge Wear & Scratches revealing raw underlying metal
	// Real bare steel is NOT chrome mirror - brushed steel roughness ~0.35-0.45
	float wear_mask = 0.0;
	if (edge_wear > 0.001) {
		float n1 = hash31(floor(v_pos * 24.0));
		float n2 = hash31(floor(v_pos * 48.0));
		float micro_noise = (n1 * 0.6 + n2 * 0.4);
		wear_mask = smoothstep(1.0 - edge_wear * 1.2, 1.0, micro_noise);
		
		// Blend raw metal on worn edges - brushed steel, not mirror chrome
		base_color = mix(base_color, undercoat_metal_color.rgb, wear_mask);
		cur_metallic = mix(cur_metallic, 0.75, wear_mask);
		cur_roughness = mix(cur_roughness, 0.38, wear_mask);
	}

	// 4. Battle Scorch & Thermal Charring - carbon soot is dielectric and very matte
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

	// Output PBR channels - SPECULAR lowered for realistic paint (dielectric F0 ~0.04)
	ALBEDO = base_color;
	METALLIC = cur_metallic;
	ROUGHNESS = clamp(cur_roughness, 0.0, 1.0);
	SPECULAR = 0.35;
	RIM = rim_strength * 0.4;
	RIM_TINT = 0.2;
	AO = 1.0 - (panel_seam * ao_strength);
	AO_LIGHT_AFFECT = 0.65;
	EMISSION = emissive_out;
}
