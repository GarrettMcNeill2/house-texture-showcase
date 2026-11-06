shader_type spatial;
render_mode diffuse_toon, specular_toon, blend_mix, depth_prepass_alpha, cull_disabled;

uniform vec4 tint : source_color = vec4(0.65, 0.8, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = opacity;
	ROUGHNESS = 0.0;
	METALLIC = 0.0;
}
