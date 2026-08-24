shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Tabletop ground that extends BEYOND the tile grid and fades to transparent
// at the outer edge — removes the hard square “tile cutoff” and reads as an
// island/table fading into void.
uniform vec4 ground_color : source_color = vec4(0.09, 0.11, 0.09, 1.0);
uniform vec4 table_color  : source_color = vec4(0.07, 0.08, 0.09, 1.0);
uniform float fade_start : hint_range(0.0, 1.0) = 0.68; // where fade begins (0=center,1=edge)
uniform float fade_softness : hint_range(0.01, 0.5) = 0.22;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.18;
uniform float roughness_val : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) { p = fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
float noise(vec2 uv){
	vec2 i=floor(uv); vec2 f=fract(uv); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}

void fragment() {
	// UV 0..1 across the PlaneMesh; 0.5 is centre.
	vec2 d = abs(UV - vec2(0.5)) * 2.0;
	float outer = max(d.x, d.y);

	// Add subtle noise to the fade radius so the border is irregular, not a perfect square.
	float n = noise(UV * 18.0) * 0.5 + noise(UV * 38.0) * 0.25;
	float wobbled = outer + (n - 0.5) * noise_strength * 0.12;

	float fade = 1.0 - smoothstep(fade_start, fade_start + fade_softness, wobbled);
	// Inner tabletop vs outer void colour blend (slightly darker outer)
	vec3 col = mix(table_color.rgb, ground_color.rgb, smoothstep(0.0, 0.55, wobbled));
	// Add faint vignette inside for depth
	col *= mix(1.0, 0.88, smoothstep(0.0, 0.9, wobbled) * 0.22 + n * 0.06);

	ALBEDO = col;
	ROUGHNESS = roughness_val;
	METALLIC = 0.02;
	ALPHA = fade;
	// Ensure the plane still writes depth where visible but fades to 0 at edge
}

