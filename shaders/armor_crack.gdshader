shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// ---------------------------------------------------------------------------
// PROCEDURAL DYNAMIC ARMOR DAMAGE SHADER
//
// Projects 3D procedural cracks, branch fractures, scratches, scorch grime and
// glowing breach heat onto any mesh in MODEL space so the damage pattern is
// anchored to the geometry itself — it never swims when the camera or the mech
// moves. No custom UV coordinates required; works on built-in mecha meshes and
// custom imported 3D models alike.
// ---------------------------------------------------------------------------

uniform float damage_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 noise_offset = vec3(0.0);
uniform float crack_scale : hint_range(1.0, 25.0) = 6.5;
uniform float scratch_scale : hint_range(5.0, 60.0) = 24.0;

uniform vec4 crack_color : source_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform vec4 exposed_metal_color : source_color = vec4(0.42, 0.44, 0.48, 1.0);
uniform vec4 scorch_color : source_color = vec4(0.16, 0.13, 0.11, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.38, 0.08, 1.0);
uniform float glow_intensity : hint_range(0.0, 10.0) = 4.5;

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

	// 1. Main fracture network (Voronoi borders widen as damage grows)
	float crack_dist = voronoi_cracks(pos * crack_scale);
	float crack_width = mix(0.02, 0.22, dmg);
	float crack_mask = 1.0 - smoothstep(crack_width * 0.3, crack_width, crack_dist);

	// 2. Branch hairline fractures spread past 35% damage
	// (computed only when active — a zero-width ramp would divide by zero)
	float branch_dist = 1.0;
	float branch_mask = 0.0;
	if (dmg > 0.35) {
		branch_dist = voronoi_cracks(pos * crack_scale * 1.85 + vec3(17.31));
		float branch_width = (dmg - 0.35) * 0.28;
		branch_mask = 1.0 - smoothstep(branch_width * 0.3, branch_width, branch_dist);
	}

	// 3. Scratches / surface abrasions
	float scratch_noise = value_noise(pos * scratch_scale);
	float scratch_threshold = max(1.0 - dmg * 0.45, 0.05);
	float scratch_factor = smoothstep(scratch_threshold, 1.0, scratch_noise) * (dmg * 0.8);

	// 4. Scorch halo darkening around every fracture
	float halo_dist = min(crack_dist, branch_dist);
	float halo_mask = 1.0 - smoothstep(crack_width, crack_width * 3.5, halo_dist);

	float fracture = clamp(crack_mask * 1.5 + branch_mask * 0.85, 0.0, 1.0);
	float total_alpha = clamp(fracture + scratch_factor * 0.7 + halo_mask * dmg * 0.35, 0.0, 1.0);

	if (total_alpha < 0.02) {
		ALPHA = 0.0;
		discard;
	}

	// 5. Color blending: scorched plate -> bright exposed metal rim -> black crack core
	float rim = 1.0 - smoothstep(crack_width * 0.6, crack_width * 2.6, crack_dist);
	vec3 col = mix(scorch_color.rgb, exposed_metal_color.rgb, smoothstep(0.1, 0.85, rim));
	col = mix(col, crack_color.rgb, fracture);

	// 6. Glowing internal heat on severe damage (>65% damaged)
	float glow_mask = 0.0;
	if (dmg > 0.65) {
		float heat = (dmg - 0.65) / 0.35;
		glow_mask = 1.0 - smoothstep(0.0, crack_width * 0.55, crack_dist);
		glow_mask += (1.0 - smoothstep(0.0, (dmg - 0.35) * 0.28 * 0.55, branch_dist)) * 0.6;
		glow_mask = clamp(glow_mask * heat, 0.0, 1.0);
	}

	ALBEDO = col;
	EMISSION = glow_color.rgb * (glow_mask * glow_intensity);
	METALLIC = mix(0.75, 0.25, fracture);
	ROUGHNESS = mix(0.28, 0.88, fracture);
	ALPHA = total_alpha;
}
