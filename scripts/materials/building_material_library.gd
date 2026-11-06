@tool
class_name BuildingMaterialLibrary
extends RefCounted
## Shared source maps and validation for the building-material authoring model.

const SET_NAMES := ["brick", "panel", "roofing", "wood", "window", "base_color"]
const SET_HINT := "Brick,Panel,Roofing,Wood,Window,Base Color"
const FIELDS := ["texture_set", "tint", "uv_scale", "uv_rotation", "uv_offset", "opacity"]
const DEFAULTS := {
	"texture_set": "brick", "tint": Color.WHITE, "uv_scale": Vector2.ONE,
	"uv_rotation": 0.0, "uv_offset": Vector2.ZERO, "opacity": 0.35,
}
const WINDOW_SHADER := preload("res://shaders/building_window.gdshader")
const SHADER := preload("res://shaders/building_material.gdshader")
# Static dependencies keep every selectable set in scene-based game exports.
# These are shared Resource references, not image copies per material.
const TEXTURE_SETS := {
	"brick": {
		"base_color_texture": preload("res://art/textures/material_textures/brick_texture/BaseColor.png"),
		"normal_texture": preload("res://art/textures/material_textures/brick_texture/Normal.png"),
		"orm_texture": preload("res://art/textures/material_textures/brick_texture/ORM.png"),
	},
	"panel": {
		"base_color_texture": preload("res://art/textures/material_textures/panel_texture/BaseColor.png"),
		"normal_texture": preload("res://art/textures/material_textures/panel_texture/Normal.png"),
		"orm_texture": preload("res://art/textures/material_textures/panel_texture/ORM.png"),
	},
	"roofing": {
		"base_color_texture": preload("res://art/textures/material_textures/roofing_texture/BaseColor.png"),
		"normal_texture": preload("res://art/textures/material_textures/roofing_texture/Normal.png"),
		"orm_texture": preload("res://art/textures/material_textures/roofing_texture/ORM.png"),
	},
	"wood": {
		"base_color_texture": preload("res://art/textures/material_textures/wood_texture/BaseColor.png"),
		"normal_texture": preload("res://art/textures/material_textures/wood_texture/Normal.png"),
		"orm_texture": preload("res://art/textures/material_textures/wood_texture/ORM.png"),
	},
}


static func resolve(values: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate()
	for field in FIELDS:
		if values.has(field) and typeof(values[field]) == typeof(DEFAULTS[field]):
			result[field] = values[field]
	if values.get("uv_rotation") is int:
		result.uv_rotation = float(values.uv_rotation)
	if result.texture_set not in SET_NAMES:
		result.texture_set = "brick"
	var scale: Vector2 = result.uv_scale
	result.uv_scale = Vector2(maxf(scale.x, 0.001), maxf(scale.y, 0.001)) if scale.is_finite() else Vector2.ONE
	if not is_finite(result.uv_rotation):
		result.uv_rotation = 0.0
	if not (result.uv_offset as Vector2).is_finite():
		result.uv_offset = Vector2.ZERO
	var tint: Color = result.tint
	if not (is_finite(tint.r) and is_finite(tint.g) and is_finite(tint.b)):
		result.tint = Color.WHITE
	result.opacity = clampf(float(result.opacity), 0.0, 1.0) if is_finite(result.opacity) else 0.35
	return result


static func textures_for(texture_set: String) -> Dictionary:
	var key := texture_set if texture_set in SET_NAMES else "brick"
	return TEXTURE_SETS.get(key, {})


static func apply(material: ShaderMaterial, settings: Dictionary) -> void:
	material.shader = WINDOW_SHADER if settings.texture_set == "window" else SHADER
	if settings.texture_set == "window":
		material.set_shader_parameter("opacity", settings.opacity)
		material.set_shader_parameter("tint", settings.tint)
		return
	else:
		material.set_shader_parameter("use_textures", settings.texture_set != "base_color")
	var maps := textures_for(settings.texture_set)
	for parameter in maps:
		material.set_shader_parameter(parameter, maps[parameter])
	material.set_shader_parameter("tint", settings.tint)
	material.set_shader_parameter("uv_scale", settings.uv_scale)
	material.set_shader_parameter("uv_offset", settings.uv_offset)
	var angle := deg_to_rad(float(settings.uv_rotation))
	material.set_shader_parameter("uv_rotation_cs", Vector2(cos(angle), sin(angle)))
