shader_type spatial;

uniform float damage_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 damage_color : source_color = vec4(0.8, 0.1, 0.1, 1.0);

void fragment() {
	vec4 albedo = ALBEDO;
	albedo = mix(albedo, damage_color, damage_amount * 0.3);
	ALBEDO = albedo.rgb;
	SPECULAR = mix(SPECULAR, 0.1, damage_amount);
}
