shader_type canvas_item;

uniform float damage_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.8, 0.0, 0.0, 0.5);

void fragment() {
	vec2 uv = UV;
	vec2 center = uv - vec2(0.5);
	float dist = length(center);
	float vignette = smoothstep(0.3, 0.8, dist);
	COLOR = mix(vec4(0.0), vignette_color, vignette * damage_amount);
}
