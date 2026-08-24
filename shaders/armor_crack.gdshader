shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// ---------------------------------------------------------------------------
// PROCEDURAL DYNAMIC ARMOR DAMAGE SHADER
//
// Projects 3D procedural cracks, branch fractures, scratches and scorch grime
// onto any mesh in MODEL space so the damage pattern is anchored to the
// geometry itself — it never swims when the camera or the mech moves. No custom
// UV coordinates required; works on built-in mecha meshes and custom imported
// 3D models alike.
//
// Hit-localized: cracks radiate from `hit_pos` and spread outward as damage
// grows. When `hit_radius` == 0 the shader falls back to uniform global cracks
// (used for restored save damage where no hit origin was recorded).
// ---------------------------------------------------------------------------

uniform float damage_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 noise_offset = vec3(0.0);
uniform float crack_scale : hint_range(1.0, 25.0) = 11.0;
uniform float scratch_scale : hint_range(5.0, 60.0) = 36.0;

uniform vec4 crack_color : source_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform vec4 exposed_metal_color : source_color = vec4(0.42, 0.44, 0.48, 1.0);
uniform vec4 scorch_color : source_color = vec4(0.16, 0.13, 0.11, 1.0);

// Impact origin in mesh-local space (set per-slot by ArmorDamageVisuals).
// hit_radius == 0 → uniform global cracks (save-restore, no origin).
uniform vec3 hit_pos = vec3(0.0);
uniform float hit_radius : hint_range(0.0, 6.0) = 0.0;
uniform float hit_spread : hint_range(0.0, 8.0) = 3.2;

varying vec3 model_pos; // mesh-local surface position captured in vertex()


void vertex() {
	// Capture LOCAL-space position BEFORE any offset: in fragment() VERTEX is
	// view space, which would make cracks slide around with the camera.
	model_pos = VERTEX;
	// Slight offset along normal so the overlay pass never z-fights the base.
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


// 3D value noise for scratch abrasions
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
	if (damage_amount <= 0.001) {
		ALPHA = 0.0;
		discard;
	}

	float dmg = clamp(damage_amount, 0.0, 1.0);
	vec3 pos = model_pos + noise_offset;

	// 0. Hit-localization factor: cracks strongest near the impact and fade
	// outward. As damage grows the effective radius widens, so cracks "spread"
	// from the hit into pristine areas. When hit_radius == 0 → uniform = 1.
	float hit_factor = 1.0;
	if (hit_radius > 0.001) {
		float d = length(model_pos - hit_pos);
		float effective = hit_radius + dmg * hit_spread;
		effective = max(effective, 0.18);
		float core = 1.0 - smoothstep(effective * 0.55, effective, d);
		float ambient = 0.06 + dmg * 0.18; // faint global at high dmg
		// Low damage → almost no distant cracks; high damage → distant cracks creep in
		hit_factor = mix(ambient, 1.0, core);
		// Add a subtle ring bias so a faint circle reads as impact epicentre
		float ring = 1.0 - smoothstep(0.02, 0.12, abs(d - hit_radius * 0.55));
		hit_factor = clamp(hit_factor + ring * 0.18 * dmg, 0.0, 1.0);
	}

	// 1. Main fracture network (Voronoi borders — thinner than before)
	float crack_dist = voronoi_cracks(pos * crack_scale);
	float crack_width = mix(0.012, 0.085, dmg);
	// Thinner core + sharper edge: cracks are hairline, not fat chasms
	float crack_mask = 1.0 - smoothstep(crack_width * 0.25, crack_width, crack_dist);
	crack_mask *= hit_factor;

	// 2. Branch hairline fractures spread past 45% damage (pushed higher + thinner)
	float branch_dist = 1.0;
	float branch_mask = 0.0;
	if (dmg > 0.45) {
		branch_dist = voronoi_cracks(pos * crack_scale * 1.85 + vec3(17.31));
		float branch_width = (dmg - 0.45) * 0.16;
		branch_mask = 1.0 - smoothstep(branch_width * 0.28, branch_width, branch_dist);
		branch_mask *= hit_factor;
	}

	// 3. Scratches / surface abrasions (finer, less aggressive)
	float scratch_noise = value_noise(pos * scratch_scale);
	float scratch_threshold = max(1.0 - dmg * 0.35, 0.15);
	float scratch_factor = smoothstep(scratch_threshold, 1.0, scratch_noise) * (dmg * 0.55);
	scratch_factor *= mix(0.35, 1.0, hit_factor);

	// 4. Scorch halo darkening around every fracture (narrower, softer)
	float halo_dist = min(crack_dist, branch_dist);
	float halo_mask = 1.0 - smoothstep(crack_width, crack_width * 2.2, halo_dist);

	float fracture = clamp(crack_mask * 1.2 + branch_mask * 0.55, 0.0, 1.0);
	float total_alpha = clamp(fracture + scratch_factor * 0.5 + halo_mask * dmg * 0.22 * hit_factor, 0.0, 1.0);

	if (total_alpha < 0.018) {
		ALPHA = 0.0;
		discard;
	}

	// 5. Color blending: scorched plate -> bright exposed metal rim -> black crack core
	float rim = 1.0 - smoothstep(crack_width * 0.55, crack_width * 1.9, crack_dist);
	vec3 col = mix(scorch_color.rgb, exposed_metal_color.rgb, smoothstep(0.15, 0.82, rim));
	col = mix(col, crack_color.rgb, fracture);

	ALBEDO = col;
	METALLIC = mix(0.75, 0.25, fracture);
	ROUGHNESS = mix(0.28, 0.88, fracture);
	ALPHA = total_alpha;
}
