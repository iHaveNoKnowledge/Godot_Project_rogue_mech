shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// ---------------------------------------------------------------------------
// PROCEDURAL DYNAMIC ARMOR DAMAGE & DURABILITY WEAR SHADER
//
// Dual-Layer Visual Pipeline:
// 1. Durability Wear (1.0 - Durability): Shows field-repaired weld seams,
//    scrap metal patches, oxidation rust, and paint abrasions from past battles.
//    Rust is now NON-SHINY, pitted, and multi-tone — not flat chocolate.
// 2. Real-time Combat Damage: Radiates structural cracks, deep breaches,
//    and impact scorch halos from incoming hits.
// ---------------------------------------------------------------------------

uniform float damage_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.0; // Driven by (1.0 - durability)
uniform vec3 noise_offset = vec3(0.0);
uniform float crack_scale : hint_range(1.0, 25.0) = 11.0;
uniform float scratch_scale : hint_range(5.0, 60.0) = 36.0;

uniform vec4 crack_color : source_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform vec4 exposed_metal_color : source_color = vec4(0.42, 0.44, 0.48, 1.0);
uniform vec4 scorch_color : source_color = vec4(0.16, 0.13, 0.11, 1.0);
// Base rust tone (mid). Shader blends dark / light variants internally.
uniform vec4 rust_color : source_color = vec4(0.60, 0.28, 0.10, 1.0);
uniform vec4 weld_color : source_color = vec4(0.10, 0.11, 0.13, 1.0);

// Impact origin in mesh-local space (set per-slot by ArmorDamageVisuals).
uniform vec3 hit_pos = vec3(0.0);
uniform float hit_radius : hint_range(0.0, 6.0) = 0.0;
uniform float hit_spread : hint_range(0.0, 8.0) = 3.2;

varying vec3 model_pos; // mesh-local surface position captured in vertex()


void vertex() {
	model_pos = VERTEX;
	VERTEX += NORMAL * 0.004;
}


// Fast 3D hash
vec3 hash3(vec3 p) {
	p = vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	);
	return fract(sin(p) * 43758.5453123);
}


// 3D Voronoi returning distance to cell boundary (F2 - F1)
float voronoi_cracks(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);

	float d1 = 8.0;
	float d2 = 8.0;

	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec3 b = vec3(float(i), float(j), float(k));
				vec3 r = b - f + hash3(p + b);
				float d = dot(r, r);

				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}


// 3D value noise for scratch & rust abrasions
float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
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
	float dmg = clamp(damage_amount, 0.0, 1.0);
	float wear = clamp(wear_amount, 0.0, 1.0);

	if (dmg <= 0.001 && wear <= 0.001) {
		ALPHA = 0.0;
		discard;
	}

	vec3 pos = model_pos + noise_offset;

	// -----------------------------------------------------------------------
	// SECTION A: DURABILITY WEAR — MATTE, PITTED, NON-SHINY RUST
	// -----------------------------------------------------------------------
	float wear_alpha = 0.0;
	vec3 wear_col = exposed_metal_color.rgb;

	if (wear > 0.005) {
		// 1. Torch-welded seam lines (scrap patch joints) — slightly sooty, not glossy
		float weld_dist = voronoi_cracks(pos * 5.5);
		float weld_mask = (1.0 - smoothstep(0.015, 0.055, weld_dist)) * wear * 0.92;

		// 2. Multi-tone oxidation / Rust — 3 octaves + vertical streaks
		float rust_n1 = value_noise(pos * 9.0 + noise_offset * 0.4);
		float rust_n2 = value_noise(pos * 22.0 + vec3(7.3, 14.1, 2.9));
		float rust_n3 = value_noise(pos * 44.0 + vec3(-8.5, 3.2, 11.0));
		// Fine pitting detail
		float rust_pit_n = value_noise(pos * 68.0);
		// Streak noise: vertical gravity runs where rust bleeds down
		float streak_n = value_noise(vec3(pos.x * 6.0, pos.y * 18.0 + rust_n1 * 2.0, pos.z * 5.0));
		float streak_mask = smoothstep(0.70, 0.88, streak_n) * wear * 0.35;

		float rust_noise = rust_n1 * 0.55 + rust_n2 * 0.32 + rust_n3 * 0.13;
		// Broader coverage — wear 0.3 already shows patchy rust, 0.7 is heavily rusted
		float rust_coverage = smoothstep(1.0 - wear * 0.88, 1.0, rust_noise * 1.18);
		float rust_mask = rust_coverage * wear * 0.96;
		rust_mask = clamp(rust_mask + streak_mask * 0.45, 0.0, 1.0);

		// 3. Paint chipping & exposed raw metal primer — flaky edges
		float chip_noise = value_noise(pos * scratch_scale * 0.58 + noise_offset * 0.3);
		float chip_mask = smoothstep(0.72 - wear * 0.52, 0.98, chip_noise) * wear * 0.62;

		wear_alpha = clamp(weld_mask * 1.0 + rust_mask * 1.02 + chip_mask * 0.58, 0.0, 0.98);

		// --- Multi-tone rust palette (not flat chocolate) ---
		vec3 rust_light = vec3(0.72, 0.36, 0.12); // bright orange, fresh oxidation
		vec3 rust_mid = rust_color.rgb;          // user-tunable mid (default 0.60,0.28,0.10)
		vec3 rust_dark = vec3(0.36, 0.16, 0.06);  // deep brown, old scale
		vec3 rust_pit_col = vec3(0.20, 0.10, 0.05); // near-black pit / cavity
		vec3 rust_highlight = vec3(0.82, 0.48, 0.16); // sun-bleached flaky edge

		// Vary rust tone per fragment from noise
		vec3 rust_base = mix(rust_dark, rust_mid, clamp(rust_n1 * 1.35, 0.0, 1.0));
		rust_base = mix(rust_base, rust_light, smoothstep(0.62, 0.88, rust_n2) * 0.45);
		// Darken pits where fine noise is high
		rust_base = mix(rust_base, rust_pit_col, smoothstep(0.72, 0.93, rust_pit_n) * 0.22);
		// Streaks are darker, wetter-looking runs
		rust_base = mix(rust_base, rust_dark * 0.75, streak_mask * 0.55);
		// Flaky highlight on exposed edges of rust patches
		float edge_highlight = smoothstep(0.35, 0.55, rust_mask) * (1.0 - smoothstep(0.55, 0.85, rust_mask));
		rust_base = mix(rust_base, rust_highlight, edge_highlight * 0.25 * smoothstep(0.2, 0.7, wear));

		// Steel base gets slightly desaturated where wear is heavy
		vec3 steel_col = exposed_metal_color.rgb * (0.90 + value_noise(pos * 38.0) * 0.10);
		steel_col = mix(steel_col, vec3(0.38, 0.40, 0.44) * 0.92, wear * 0.15); // dusty steel

		wear_col = mix(steel_col, rust_base, rust_mask / max(wear_alpha, 0.001));
		wear_col = mix(wear_col, weld_color.rgb, weld_mask / max(wear_alpha, 0.001));
		// Micro-AO: pits are slightly darker, adds depth without gloss
		wear_col *= 1.0 - smoothstep(0.68, 0.92, rust_pit_n) * 0.14 * rust_mask;
	}

	// -----------------------------------------------------------------------
	// SECTION B: REAL-TIME COMBAT DAMAGE (Localized Cracks & Breaches)
	// -----------------------------------------------------------------------
	float dmg_alpha = 0.0;
	vec3 dmg_col = exposed_metal_color.rgb;

	if (dmg > 0.005) {
		float hit_factor = 1.0;
		if (hit_radius > 0.001) {
			float d = length(model_pos - hit_pos);
			float effective_radius = max(hit_radius, 0.40) + dmg * (hit_spread * 0.85);
			float core = 1.0 - smoothstep(effective_radius * 0.35, effective_radius, d);
			float ambient = smoothstep(0.75, 1.0, dmg) * 0.12;
			hit_factor = clamp(core + ambient, 0.0, 1.0);
		}

		if (hit_factor > 0.005) {
			// Scratches & abrasions
			float scratch_noise = value_noise(pos * scratch_scale);
			float scratch_thresh = mix(0.75, 0.30, dmg);
			float scratch_factor = smoothstep(scratch_thresh, 1.0, scratch_noise) * clamp(dmg * 2.2, 0.0, 1.0) * hit_factor;

			// Hairline cracks
			float crack_intensity = smoothstep(0.25, 0.65, dmg);
			float crack_dist = voronoi_cracks(pos * crack_scale);
			float crack_width = mix(0.010, 0.045, clamp((dmg - 0.25) / 0.75, 0.0, 1.0));
			float crack_mask = (1.0 - smoothstep(crack_width * 0.20, crack_width, crack_dist)) * crack_intensity * hit_factor;

			// Severe fractures & breach
			float severe_intensity = smoothstep(0.60, 0.90, dmg);
			float branch_dist = 1.0;
			float branch_mask = 0.0;
			if (dmg > 0.60) {
				branch_dist = voronoi_cracks(pos * crack_scale * 1.75 + vec3(23.41, 11.17, 7.89));
				float branch_width = (dmg - 0.60) * 0.12;
				branch_mask = (1.0 - smoothstep(branch_width * 0.25, branch_width, branch_dist)) * severe_intensity * hit_factor;
			}

			// Scorch halo
			float halo_dist = min(crack_dist, branch_dist);
			float halo_mask = (1.0 - smoothstep(crack_width, crack_width * 2.4, halo_dist)) * severe_intensity * hit_factor;

			float total_fracture = clamp(crack_mask * 1.1 + branch_mask * 0.85, 0.0, 1.0);
			dmg_alpha = clamp(scratch_factor * 0.65 + total_fracture + halo_mask * 0.35, 0.0, 1.0);

			float rim = 1.0 - smoothstep(crack_width * 0.4, crack_width * 1.8, crack_dist);
			dmg_col = mix(scorch_color.rgb, exposed_metal_color.rgb, smoothstep(0.20, 0.80, rim));
			dmg_col = mix(dmg_col, crack_color.rgb, total_fracture);
		}
	}

	// -----------------------------------------------------------------------
	// COMPOSITION: Combine wear & real-time damage
	// -----------------------------------------------------------------------
	float total_alpha = clamp(wear_alpha + dmg_alpha, 0.0, 1.0);
	if (total_alpha < 0.015) {
		ALPHA = 0.0;
		discard;
	}

	vec3 final_col = mix(wear_col, dmg_col, dmg_alpha / max(total_alpha, 0.001));

	ALBEDO = final_col;

	// ----- MATTE, NON-SHINY RUST: metallic ~0 for rust, roughness ~0.97 -----
	// Rust is dielectric (not metal) and powdery — must be DULL, not chocolate-gloss.
	if (wear_alpha > 0.001) {
		float rust_n1 = value_noise(pos * 9.0 + noise_offset * 0.4);
		float rust_n3 = value_noise(pos * 44.0);
		float weld_dist = voronoi_cracks(pos * 5.5);
		float weld_mask_c = (1.0 - smoothstep(0.015, 0.055, weld_dist)) * wear;
		float rust_noise_tmp = rust_n1 * 0.55 + value_noise(pos * 22.0 + vec3(7.3,14.1,2.9)) * 0.32 + rust_n3 * 0.13;
		float rust_cov = smoothstep(1.0 - wear * 0.88, 1.0, rust_noise_tmp * 1.18);
		float rust_m = rust_cov * wear;
		float rust_factor = clamp(rust_m / max(wear_alpha, 0.001), 0.0, 1.0);
		float weld_factor = clamp(weld_mask_c / max(wear_alpha, 0.001), 0.0, 1.0);
		// chip factor is remainder
		float chip_factor = clamp(1.0 - rust_factor - weld_factor, 0.0, 1.0);

		// Per-type PBR: rust = dielectric matte, weld = slightly metallic soot, chip = bare steel
		float rust_metal = 0.015; // almost non-metal
		float rust_rough = 0.96 + rust_n3 * 0.03; // 0.96-0.99, splotchy but always rough
		float weld_metal = 0.28;
		float weld_rough = 0.88;
		float chip_metal = 0.60;
		float chip_rough = 0.48;

		float wear_metal = rust_metal * rust_factor + weld_metal * weld_factor + chip_metal * chip_factor;
		float wear_rough = rust_rough * rust_factor + weld_rough * weld_factor + chip_rough * chip_factor;
		// Blend wear PBR into base, but rust must stay matte even when mixed with cracks
		float wear_blend = clamp(wear_alpha * 0.98, 0.0, 1.0);
		METALLIC = mix(0.62, wear_metal, wear_blend);
		ROUGHNESS = mix(0.35, wear_rough, wear_blend);
		// Durability 0.2 (wear 0.8) = heavily pitted, always rough — push to 1.0
		ROUGHNESS = mix(ROUGHNESS, 0.98, smoothstep(0.5, 0.85, wear) * rust_factor * 0.85);
		// Rust pits add micro-roughness variance (not uniform)
		ROUGHNESS = clamp(ROUGHNESS + (rust_n3 - 0.5) * 0.04 * rust_factor, 0.0, 1.0);
		// Mix cracks (cracks are dark crevices, also rough)
		METALLIC = mix(METALLIC, 0.06, clamp(dmg_alpha * 0.9, 0.0, 1.0));
		ROUGHNESS = mix(ROUGHNESS, 0.94, clamp(dmg_alpha * 0.7, 0.0, 1.0));
	} else {
		METALLIC = mix(0.62, 0.06, clamp(dmg_alpha * 0.9, 0.0, 1.0));
		ROUGHNESS = mix(0.35, 0.94, clamp(dmg_alpha * 0.7, 0.0, 1.0));
	}

	// Subtle normal pitting for rust scale — breaks the flat "chocolate spread" look
	if (wear > 0.08) {
		vec3 h = hash3(pos * 41.0);
		vec3 pitting = (h - 0.5) * 0.18 * wear * clamp(wear_alpha, 0.0, 1.0);
		// Only perturb where rust exists, not on clean paint
		float rust_n1p = value_noise(pos * 9.0 + noise_offset * 0.4);
		float rust_presence = smoothstep(0.35, 0.75, rust_n1p) * wear;
		NORMAL = normalize(NORMAL + pitting * rust_presence);
	}

	ALPHA = total_alpha;
}
