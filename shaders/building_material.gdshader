shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform sampler2D base_color_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_textures = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform vec2 uv_rotation_cs = vec2(1.0, 0.0);

void fragment() {
	vec2 p = (UV - vec2(0.5)) * uv_scale;
	float c = uv_rotation_cs.x;
	float s = uv_rotation_cs.y;
	vec2 mapped_uv = vec2(c * p.x - s * p.y, s * p.x + c * p.y) + vec2(0.5) + uv_offset;
	ALBEDO = tint.rgb;
	AO = 1.0;
	ROUGHNESS = 0.0;
	METALLIC = 0.0;
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	if (use_textures) {
		ALBEDO = texture(base_color_texture, mapped_uv).rgb * tint.rgb;
		vec3 orm = texture(orm_texture, mapped_uv).rgb;
		AO = orm.r;
		ROUGHNESS = 0.0;
		METALLIC = orm.b;

		// Use the mesh's imported tangent frame, just like StandardMaterial3D.
		// UV repetition changes frequency, not normal strength or handedness.
		vec2 normal_xy = texture(normal_texture, mapped_uv).rg * 2.0 - 1.0;
		vec2 rotated_normal = vec2(c * normal_xy.x - s * normal_xy.y,
			s * normal_xy.x + c * normal_xy.y);
		NORMAL_MAP = vec3(rotated_normal * 0.5 + vec2(0.5), 1.0);
	}
}
