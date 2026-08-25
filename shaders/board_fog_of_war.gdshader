shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Volumetric Mist & Cloud Shroud — continuous organic canopy across the battlefield
uniform vec4 fog_color : source_color = vec4(0.08, 0.11, 0.17, 0.96);
uniform vec4 fog_edge_color : source_color = vec4(0.22, 0.32, 0.46, 0.85);
uniform vec4 dissolve_burn_color : source_color = vec4(0.30, 0.85, 1.0, 1.0);

uniform float density : hint_range(0.1, 2.0) = 1.0;
uniform float animation_speed : hint_range(0.0, 2.0) = 0.35;
uniform float noise_scale : hint_range(1.0, 20.0) = 3.8;

// Dissolve progress: 0.0 = fully shrouded in dense fog, 1.0 = fully revealed
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
	float amp = 0.52;
	for (int n = 0; n < 3; n++) {
		val += amp * noise3d(p);
		p *= 2.08;
		amp *= 0.48;
	}
	return val;
}

void vertex() {
	vec3 world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Gentle undulating atmospheric fog waves across world space
	float t = TIME * animation_speed;
	float wave1 = sin(t * 1.2 + world_p.x * 0.35 + world_p.z * 0.28) * 0.30;
	float wave2 = cos(t * 0.9 + world_p.x * 0.22 - world_p.z * 0.40) * 0.22;
	float wave3 = sin(t * 1.8 + (world_p.x + world_p.z) * 0.60) * 0.12;
	float total_wave = (wave1 + wave2 + wave3) * (1.0 - dissolve_progress);

	// Smooth radial dome shaping so fog peaks near center and tapers at perimeter
	// FIX desert: half-size is now 4.2 (plane 8.4), so dome must match to avoid
	// a low transparent rim that looked like missing fog on bright sand.
	float r = length(VERTEX.xz);
	float dome_profile = clamp(1.0 - (r / 4.2) * (r / 4.2), 0.0, 1.0);
	
	VERTEX.y = VERTEX.y * 0.4 + (total_wave + 0.95) * (dome_profile * 0.85 + 0.15);
	VERTEX.x += sin(t * 0.7 + world_p.z * 0.3) * 0.12 * (1.0 - dissolve_progress);
	VERTEX.z += cos(t * 0.7 + world_p.x * 0.3) * 0.12 * (1.0 - dissolve_progress);
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Multi-directional drifting mist FBM
	vec3 drift1 = vec3(TIME * animation_speed * 0.25, TIME * animation_speed * 0.08, TIME * animation_speed * 0.18);
	vec3 drift2 = vec3(-TIME * animation_speed * 0.15, TIME * animation_speed * 0.05, TIME * animation_speed * 0.22);
	float n1 = fbm3d((world_pos + drift1 * 8.0) * (noise_scale * 0.038));
	float n2 = fbm3d((world_pos * 1.5 + drift2 * 8.0) * (noise_scale * 0.045));
	float cloud_density = clamp(mix(n1, n2, 0.45) * 1.6, 0.0, 1.0);

	// Soft circular radial fade to ensure seamless blending between neighboring tiles
	// FIX desert: opaque core enlarged to 2.6→4.2 so diagonal midpoints (2.83) stay
	// opaque and bright sand no longer shows through as a gap.
	float local_dist = length(VERTEX.xz);
	float radial_fade = 1.0 - smoothstep(2.6, 4.2, local_dist);

	// Dissolve logic driven by world noise and reveal progress
	float dissolve_thresh = dissolve_progress * 1.35;
	float dissolve_mask = smoothstep(dissolve_thresh - 0.15, dissolve_thresh + 0.15, cloud_density);

	// Luminous holographic reveal edge
	float burn_edge = smoothstep(dissolve_thresh - 0.12, dissolve_thresh, cloud_density) * 
	                  (1.0 - smoothstep(dissolve_thresh, dissolve_thresh + 0.12, cloud_density));

	// Ethereal atmospheric coloring and fresnel rim
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	vec3 col = mix(fog_color.rgb, fog_edge_color.rgb, cloud_density * 0.85);
	col += fog_edge_color.rgb * (fresnel * 0.4);

	if (dissolve_progress > 0.01 && dissolve_progress < 0.99) {
		col += dissolve_burn_color.rgb * burn_edge * 3.5 * radial_fade;
	}

	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	
	// Slightly more opaque base so fog reads on bright desert sand.
	// Raised minimum from 0.35→0.52 and clamp to 0.98 so unrevealed tiles are clearly shrouded.
	float final_alpha = (1.0 - dissolve_progress) * radial_fade * dissolve_mask * 
	                    (cloud_density * 0.48 + 0.52) * fog_color.a;
	ALPHA = clamp(final_alpha, 0.0, 0.98);
}
