@tool
class_name BuildingMaterialStyle
extends Resource
## Saved role data stays private. The Inspector exposes native enum/color/UV fields.

@export_storage var slots: Dictionary = {}:
	set(value):
		var shape_changed := slots.keys() != value.keys()
		slots = value.duplicate(true)
		emit_changed()
		if shape_changed:
			notify_property_list_changed()

var _native_fields: Dictionary = {}


func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = [
		{"name": "Material Slots", "type": TYPE_NIL, "usage": PROPERTY_USAGE_CATEGORY},
		{"name": "material_slot_count", "type": TYPE_INT, "hint": PROPERTY_HINT_RANGE,
			"hint_string": "0,64,1", "usage": PROPERTY_USAGE_EDITOR},
	]
	_native_fields.clear()
	var keys := slots.keys()
	for i in keys.size():
		var role := str(keys[i])
		var prefix := "shared_slot_%d_" % i
		properties.append({"name": "Slot %d · %s" % [i + 1, role], "type": TYPE_NIL,
			"hint_string": prefix, "usage": PROPERTY_USAGE_GROUP})
		_append_field(properties, prefix + "texture_type", role, "texture_set", TYPE_INT,
			PROPERTY_HINT_ENUM, BuildingMaterialLibrary.SET_HINT)
		_append_field(properties, prefix + "color", role, "tint", TYPE_COLOR, PROPERTY_HINT_COLOR_NO_ALPHA)
		_append_field(properties, prefix + "uv_scale", role, "uv_scale", TYPE_VECTOR2, PROPERTY_HINT_RANGE, "0.001,10,0.01,or_greater,hide_slider")
		_append_field(properties, prefix + "uv_rotation", role, "uv_rotation", TYPE_FLOAT, PROPERTY_HINT_RANGE, "-360,360,0.1,or_less,or_greater,suffix:°")
		_append_field(properties, prefix + "uv_offset", role, "uv_offset", TYPE_VECTOR2)
		if settings_for(role).texture_set == "window":
			_append_field(properties, prefix + "opacity", role, "opacity", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,1,0.01")
	return properties


func _append_field(properties: Array[Dictionary], name_text: String, role: String, field: String,
		type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
	_native_fields[name_text] = {"role": role, "field": field}
	properties.append({"name": name_text, "type": type, "hint": hint, "hint_string": hint_string,
		"usage": PROPERTY_USAGE_EDITOR})


func native_slot_property(role: String, field: String) -> StringName:
	_get_property_list()
	for property in _native_fields:
		if _native_fields[property].role == role and _native_fields[property].field == field:
			return StringName(property)
	return &""


func _get(property: StringName) -> Variant:
	if property == &"material_slot_count":
		return slots.size()
	if _native_fields.has(str(property)):
		var entry: Dictionary = _native_fields[str(property)]
		var values := settings_for(entry.role)
		return BuildingMaterialLibrary.SET_NAMES.find(values.texture_set) if entry.field == "texture_set" else values[entry.field]
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == &"material_slot_count":
		var count := clampi(int(value), 0, 64)
		var updated := slots.duplicate(true)
		while updated.size() > count:
			updated.erase(updated.keys().back())
		while updated.size() < count:
			var suffix := updated.size() + 1
			while updated.has("slot_%d" % suffix):
				suffix += 1
			updated["slot_%d" % suffix] = {}
		slots = updated
		notify_property_list_changed()
		return true
	if not _native_fields.has(str(property)):
		return false
	var entry: Dictionary = _native_fields[str(property)]
	if entry.field == "texture_set":
		if not value is int or value < 0 or value >= BuildingMaterialLibrary.SET_NAMES.size():
			return false
		value = BuildingMaterialLibrary.SET_NAMES[value]
	set_role_field(entry.role, entry.field, value)
	return true


func _get_linked_undo_properties(property: StringName, _value: Variant) -> PackedStringArray:
	return PackedStringArray(["slots"]) if property == &"material_slot_count" or _native_fields.has(str(property)) else PackedStringArray()


func _property_can_revert(property: StringName) -> bool:
	return _native_fields.has(str(property))


func _property_get_revert(property: StringName) -> Variant:
	if not _native_fields.has(str(property)):
		return null
	var field: String = _native_fields[str(property)].field
	return 0 if field == "texture_set" else BuildingMaterialLibrary.DEFAULTS[field]


func settings_for(role: String) -> Dictionary:
	var values: Variant = slots.get(role, {})
	return BuildingMaterialLibrary.resolve(values if values is Dictionary else {})


func set_role_field(role: String, field: String, value: Variant) -> void:
	if field not in BuildingMaterialLibrary.FIELDS:
		return
	var shape_changed := not slots.has(role)
	var updated := slots.duplicate(true)
	var settings: Dictionary = updated.get(role, {}).duplicate()
	settings[field] = value
	updated[role] = settings
	slots = updated
	if shape_changed or field == "texture_set":
		notify_property_list_changed()
