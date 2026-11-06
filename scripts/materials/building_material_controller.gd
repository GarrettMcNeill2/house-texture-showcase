@tool
class_name BuildingMaterialController
extends Node3D
## Applies derived per-role materials without writing generated state into scenes.

signal settings_changed

@export_storage var style: BuildingMaterialStyle:
	set(value):
		if style != null and style.changed.is_connected(_settings_changed):
			style.changed.disconnect(_settings_changed)
		style = value
		if style != null and not style.changed.is_connected(_settings_changed):
			style.changed.connect(_settings_changed)
		_settings_changed()

## Each entry: role, mesh_path relative to this node, surface, surface_name.
@export_storage var bindings: Array[Dictionary] = []:
	set(value):
		bindings = value.duplicate(true)
		_settings_changed()

## Presence of a field explicitly enables that override, including white/identity.
@export_storage var local_overrides: Dictionary = {}:
	set(value):
		local_overrides = value.duplicate(true)
		_settings_changed()

## Corresponding slots in repeated PackedScene parts, scoped to this controller.
@export_storage var linked_scene_slots := PackedStringArray()

var _materials: Dictionary = {}
var _applied: Array[Dictionary] = []
var _watched_meshes: Array[Mesh] = []
var _watched_targets: Array[WeakRef] = []
var _refresh_pending := false


var _native_fields: Dictionary = {}
var _native_layout := ""
var _show_hidden_materials := false


func _get_property_list() -> Array[Dictionary]:
	# Only native scalar/color/vector/resource properties are exposed. Storage
	# dictionaries are never Inspector properties, even without the editor addon.
	var properties: Array[Dictionary] = []
	_native_fields.clear()
	properties.append({"name": "Building Materials", "type": TYPE_NIL, "usage": PROPERTY_USAGE_CATEGORY})
	properties.append({"name": "material_slot_count", "type": TYPE_INT, "usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY})
	var surfaces := building_surfaces(_show_hidden_materials)
	for i in surfaces.size():
		var surface: Dictionary = surfaces[i]
		var prefix := "material_slot_%d_" % i
		var mesh_name := str(surface.mesh_path)
		var title := "%s / Slot %d" % [mesh_name, int(surface.surface) + 1]
		if not str(surface.surface_name).is_empty():
			title += " · " + str(surface.surface_name)
		properties.append({"name": title, "type": TYPE_NIL, "hint_string": prefix, "usage": PROPERTY_USAGE_GROUP})
		_append_native_field(properties, prefix + "texture_type", surface, "texture_set", TYPE_INT,
			PROPERTY_HINT_ENUM, "Original Material," + BuildingMaterialLibrary.SET_HINT)
		if scene_copy_surfaces(surface).size() > 1:
			_append_native_field(properties, prefix + "link_scene_copies", surface, "link_scene_copies", TYPE_BOOL,
				PROPERTY_HINT_NONE, "")
		properties.append({"name": "Shader Parameters", "type": TYPE_NIL, "hint_string": prefix + "shader_", "usage": PROPERTY_USAGE_SUBGROUP})
		var shader_usage := PROPERTY_USAGE_EDITOR
		if not slot_is_managed(surface):
			shader_usage |= PROPERTY_USAGE_READ_ONLY
		_append_native_field(properties, prefix + "shader_color", surface, "tint", TYPE_COLOR,
			PROPERTY_HINT_COLOR_NO_ALPHA, "", shader_usage)
		_append_native_field(properties, prefix + "shader_uv_scale", surface, "uv_scale", TYPE_VECTOR2,
			PROPERTY_HINT_RANGE, "0.001,10,0.01,or_greater,hide_slider", shader_usage)
		_append_native_field(properties, prefix + "shader_uv_rotation", surface, "uv_rotation", TYPE_FLOAT,
			PROPERTY_HINT_RANGE, "-360,360,0.1,or_less,or_greater,suffix:°", shader_usage)
		_append_native_field(properties, prefix + "shader_uv_offset", surface, "uv_offset", TYPE_VECTOR2,
			PROPERTY_HINT_NONE, "", shader_usage)
		if slot_settings(surface).texture_set == "window":
			_append_native_field(properties, prefix + "shader_opacity", surface, "opacity", TYPE_FLOAT,
				PROPERTY_HINT_RANGE, "0,1,0.01", shader_usage)
		if style != null:
			properties.append({"name": "Area Linking", "type": TYPE_NIL, "hint_string": prefix + "area_", "usage": PROPERTY_USAGE_SUBGROUP})
			_append_native_field(properties, prefix + "area_shared_slot", surface, "style_role", TYPE_INT,
				PROPERTY_HINT_ENUM, "No Shared Slot," + ",".join(style.slots.keys()))
	properties.append({"name": "Area Style", "type": TYPE_NIL, "hint_string": "area_", "usage": PROPERTY_USAGE_GROUP})
	properties.append({"name": "area_style", "type": TYPE_OBJECT, "hint": PROPERTY_HINT_RESOURCE_TYPE,
		"hint_string": "BuildingMaterialStyle", "usage": PROPERTY_USAGE_EDITOR})
	properties.append({"name": "Display", "type": TYPE_NIL, "hint_string": "display_", "usage": PROPERTY_USAGE_GROUP})
	properties.append({"name": "display_hidden_meshes", "type": TYPE_BOOL, "usage": PROPERTY_USAGE_EDITOR})
	return properties


func _append_native_field(properties: Array[Dictionary], name_text: String, surface: Dictionary,
		field: String, type: int, hint: int, hint_string: String, usage: int = PROPERTY_USAGE_EDITOR) -> void:
	_native_fields[name_text] = {"surface": surface, "field": field}
	properties.append({"name": name_text, "type": type, "hint": hint, "hint_string": hint_string, "usage": usage})


func native_slot_property(surface: Dictionary, field: String) -> StringName:
	_get_property_list()
	for property in _native_fields:
		var entry: Dictionary = _native_fields[property]
		if entry.field == field and str(entry.surface.mesh_path) == str(surface.mesh_path) and int(entry.surface.surface) == int(surface.surface):
			return StringName(property)
	return &""


func _get(property: StringName) -> Variant:
	if property == &"material_slots":
		return slot_configuration() # Legacy programmatic API; never exposed.
	if property == &"material_slot_count":
		return building_surfaces(_show_hidden_materials).size()
	if property == &"area_style":
		return style
	if property == &"display_hidden_meshes":
		return _show_hidden_materials
	if _native_fields.has(str(property)):
		var entry: Dictionary = _native_fields[str(property)]
		if entry.field == "link_scene_copies":
			return _scene_copy_key(entry.surface) in linked_scene_slots
		if entry.field == "texture_set":
			return BuildingMaterialLibrary.SET_NAMES.find(slot_settings(entry.surface).texture_set) + 1 if slot_is_managed(entry.surface) else 0
		if entry.field == "style_role":
			return style.slots.keys().find(slot_style_role(entry.surface)) + 1 if style != null else 0
		return slot_settings(entry.surface)[entry.field]
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == &"material_slots" and value is Dictionary:
		_apply_slot_configuration(value)
		return true
	if property == &"area_style":
		style = value as BuildingMaterialStyle
		return true
	if property == &"display_hidden_meshes":
		_show_hidden_materials = bool(value)
		notify_property_list_changed()
		return true
	if not _native_fields.has(str(property)):
		return false
	var entry: Dictionary = _native_fields[str(property)]
	var surface: Dictionary = entry.surface
	var field: String = entry.field
	if field == "link_scene_copies":
		var key := _scene_copy_key(surface)
		if key.is_empty():
			return false
		if bool(value):
			if key not in linked_scene_slots:
				linked_scene_slots.append(key)
			_apply_slot_configuration(_sync_scene_copies(slot_configuration(), surface))
		else:
			var index := linked_scene_slots.find(key)
			if index >= 0:
				linked_scene_slots.remove_at(index)
			_settings_changed()
		return true
	if field == "texture_set":
		if not value is int or value < 0 or value > BuildingMaterialLibrary.SET_NAMES.size():
			return false
		if value == 0:
			_apply_slot_configuration(original_slot_configuration(surface))
			return true
		value = BuildingMaterialLibrary.SET_NAMES[value - 1]
	elif field == "style_role":
		if style == null or not value is int or value < 0 or value > style.slots.size():
			return false
		_apply_slot_configuration(edited_slot_configuration(surface, field, str(style.slots.keys()[value - 1]) if value > 0 else ""))
		return true
	var shared := _shared_slot_settings(surface)
	if slot_is_managed(surface) and value == shared[field]:
		_apply_slot_configuration(reset_slot_configuration(surface, field))
	else:
		_apply_slot_configuration(edited_slot_configuration(surface, field, value))
	return true


func _apply_slot_configuration(value: Dictionary) -> void:
	var updated_bindings: Array[Dictionary] = []
	updated_bindings.assign(value.get("bindings", []))
	bindings = updated_bindings
	local_overrides = value.get("local_overrides", {})
	style = value.get("style") as BuildingMaterialStyle


func _get_linked_undo_properties(property: StringName, _value: Variant) -> PackedStringArray:
	# Native Inspector snapshots these saved fields with each displayed scalar.
	# Undoing a first texture assignment therefore also removes its new binding.
	if _native_fields.has(str(property)) or property == &"area_style":
		return PackedStringArray(["bindings", "local_overrides", "style", "linked_scene_slots"])
	return PackedStringArray()


func _shared_slot_settings(surface: Dictionary) -> Dictionary:
	var shared_role := slot_style_role(surface)
	return style.settings_for(shared_role) if style != null and not shared_role.is_empty() else BuildingMaterialLibrary.DEFAULTS.duplicate()


func _property_can_revert(property: StringName) -> bool:
	return _native_fields.has(str(property)) and _native_fields[str(property)].field not in ["style_role", "link_scene_copies"]


func _property_get_revert(property: StringName) -> Variant:
	if not _native_fields.has(str(property)):
		return null
	var entry: Dictionary = _native_fields[str(property)]
	var shared := _shared_slot_settings(entry.surface)
	if entry.field == "texture_set":
		return BuildingMaterialLibrary.SET_NAMES.find(shared.texture_set) + 1 if style != null and style.slots.has(slot_style_role(entry.surface)) else 0
	return shared[entry.field]


func _refresh_native_layout() -> void:
	var surfaces := building_surfaces(_show_hidden_materials)
	var managed: Array[bool] = []
	for surface in surfaces:
		managed.append(slot_is_managed(surface))
		managed.append(slot_settings(surface).texture_set == "window")
	var layout := str(surfaces) + str(managed) + str(style.slots.keys() if style != null else []) + str(style != null)
	if layout != _native_layout:
		_native_layout = layout
		notify_property_list_changed()


func slot_configuration() -> Dictionary:
	return {"bindings": bindings.duplicate(true), "local_overrides": local_overrides.duplicate(true), "style": style}


func slot_binding(surface: Dictionary) -> Dictionary:
	for binding in bindings:
		if str(binding.get("mesh_path", "")) == str(surface.mesh_path) and int(binding.get("surface", -1)) == int(surface.surface):
			return binding
	return {}


func slot_is_managed(surface: Dictionary) -> bool:
	var binding := slot_binding(surface)
	var mesh := _binding_mesh(surface)
	return not binding.is_empty() and mesh != null and mesh.mesh != null and mesh.material_override == null and _surface_matches(mesh.mesh, binding)


func slot_settings(surface: Dictionary) -> Dictionary:
	var binding := slot_binding(surface)
	return resolve_slot_settings(str(binding.role)) if slot_is_managed(surface) else BuildingMaterialLibrary.DEFAULTS.duplicate()


func slot_style_role(surface: Dictionary) -> String:
	var binding := slot_binding(surface)
	return str(binding.get("style_role", binding.get("role", surface.get("surface_name", ""))))


func edited_slot_configuration(surface: Dictionary, field: String, value: Variant) -> Dictionary:
	var config := slot_configuration()
	var binding := _unique_slot_binding(surface, config)
	var role: String = binding.role
	if field == "style_role":
		binding.style_role = str(value)
	elif field in BuildingMaterialLibrary.FIELDS:
		var values: Dictionary = config.local_overrides.get(role, {}).duplicate()
		values[field] = value
		config.local_overrides[role] = values
	return _sync_scene_copies(config, surface)


func reset_slot_configuration(surface: Dictionary, field: String) -> Dictionary:
	var config := slot_configuration()
	if slot_binding(surface).is_empty():
		return config
	# Split a shared role only when resetting one slot must leave its peers alone.
	var binding := _unique_slot_binding(surface, config)
	var role: String = binding.role
	var values: Dictionary = config.local_overrides.get(role, {}).duplicate()
	values.erase(field)
	if values.is_empty():
		config.local_overrides.erase(role)
	else:
		config.local_overrides[role] = values
	return _sync_scene_copies(config, surface)


func original_slot_configuration(surface: Dictionary) -> Dictionary:
	var config := slot_configuration()
	var retained: Array[Dictionary] = []
	var removed_role := ""
	for binding in config.bindings:
		if str(binding.get("mesh_path", "")) == str(surface.mesh_path) and int(binding.get("surface", -1)) == int(surface.surface):
			removed_role = str(binding.get("role", ""))
		else:
			retained.append(binding)
	config.bindings = retained
	if not retained.any(func(binding: Dictionary): return str(binding.get("role", "")) == removed_role):
		config.local_overrides.erase(removed_role)
	return _sync_scene_copies(config, surface)


func _unique_slot_binding(surface: Dictionary, config: Dictionary) -> Dictionary:
	var index := -1
	for i in config.bindings.size():
		var candidate: Dictionary = config.bindings[i]
		if str(candidate.get("mesh_path", "")) == str(surface.mesh_path) and int(candidate.get("surface", -1)) == int(surface.surface):
			index = i
			break
	var binding: Dictionary = config.bindings[index] if index >= 0 else surface.duplicate()
	var old_role := str(binding.get("role", ""))
	var shared_role := str(binding.get("style_role", old_role if not old_role.is_empty() else surface.get("surface_name", "")))
	var shared_count := 0
	for candidate in config.bindings:
		if str(candidate.get("role", "")) == old_role:
			shared_count += 1
	if old_role.is_empty() or shared_count > 1:
		var role := "slot:%s:%d" % [surface.mesh_path, surface.surface]
		# Keep an imported material name as the style key; private IDs stay internal.
		binding.role = role
		binding.style_role = shared_role
		if not old_role.is_empty() and config.local_overrides.has(old_role):
			config.local_overrides[role] = config.local_overrides[old_role].duplicate()
	binding.surface_name = surface.get("surface_name", "")
	if index >= 0:
		config.bindings[index] = binding
	else:
		config.bindings.append(binding)
	return binding


func _scene_copy_key(surface: Dictionary) -> String:
	var mesh := _binding_mesh(surface)
	if mesh == null:
		return ""
	var node: Node = mesh
	while node != null and node != self:
		if not node.scene_file_path.is_empty():
			return "%s|%s|%d|%s" % [node.scene_file_path, node.get_path_to(mesh), int(surface.surface), surface.get("surface_name", "")]
		node = node.get_parent()
	return ""


func scene_copy_surfaces(surface: Dictionary) -> Array[Dictionary]:
	var key := _scene_copy_key(surface)
	var result: Array[Dictionary] = []
	if key.is_empty():
		return result
	for candidate in available_surfaces():
		if _scene_copy_key(candidate) == key:
			result.append(candidate)
	return result


func _sync_scene_copies(config: Dictionary, source: Dictionary) -> Dictionary:
	var key := _scene_copy_key(source)
	if key.is_empty() or key not in linked_scene_slots:
		return config
	var source_binding: Dictionary = {}
	for binding in config.bindings:
		if str(binding.get("mesh_path", "")) == str(source.mesh_path) and int(binding.get("surface", -1)) == int(source.surface):
			source_binding = binding
			break
	var local_values: Dictionary = config.local_overrides.get(str(source_binding.get("role", "")), {}).duplicate(true)
	var shared_role := str(source_binding.get("style_role", source_binding.get("role", "")))
	for peer in scene_copy_surfaces(source):
		if str(peer.mesh_path) == str(source.mesh_path):
			continue
		if source_binding.is_empty():
			var kept: Array[Dictionary] = []
			for binding in config.bindings:
				if str(binding.get("mesh_path", "")) == str(peer.mesh_path) and int(binding.get("surface", -1)) == int(peer.surface):
					var role := str(binding.get("role", ""))
					if not config.bindings.any(func(other: Dictionary): return other != binding and str(other.get("role", "")) == role):
						config.local_overrides.erase(role)
				else:
					kept.append(binding)
			config.bindings = kept
		else:
			var target := _unique_slot_binding(peer, config)
			target.style_role = shared_role
			if local_values.is_empty():
				config.local_overrides.erase(str(target.role))
			else:
				config.local_overrides[str(target.role)] = local_values.duplicate(true)
	return config


func _adopt_scene_copies() -> void:
	if linked_scene_slots.is_empty():
		return
	var config := slot_configuration()
	var visited := {}
	for surface in available_surfaces():
		var key := _scene_copy_key(surface)
		if key in linked_scene_slots and not visited.has(key) and not slot_binding(surface).is_empty():
			visited[key] = true
			config = _sync_scene_copies(config, surface)
	if config.bindings != bindings or config.local_overrides != local_overrides:
		_apply_slot_configuration(config)


func building_surfaces(include_hidden: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for surface in available_surfaces():
		var mesh := _binding_mesh(surface)
		var visible := true
		var node: Node = mesh
		while node != null and node != self:
			if node is Node3D and not node.visible:
				visible = false
			node = node.get_parent()
		if include_hidden or visible:
			result.append(surface)
	return result


func _enter_tree() -> void:
	if style != null and not style.changed.is_connected(_settings_changed):
		style.changed.connect(_settings_changed)
	_settings_changed()


func _exit_tree() -> void:
	restore_owned_overrides()
	_materials.clear()
	_disconnect_meshes()
	if style != null and style.changed.is_connected(_settings_changed):
		style.changed.disconnect(_settings_changed)


func _settings_changed() -> void:
	settings_changed.emit()
	if is_inside_tree() and not _refresh_pending:
		_refresh_pending = true
		_refresh_deferred.call_deferred()


func _refresh_deferred() -> void:
	_refresh_pending = false
	if is_inside_tree():
		refresh_materials()
		_refresh_native_layout()


func roles() -> PackedStringArray:
	var result := PackedStringArray()
	for binding in bindings:
		var role := str(binding.get("role", "")).strip_edges()
		if not role.is_empty() and role not in result:
			result.append(role)
	return result


func resolve_slot_settings(role: String) -> Dictionary:
	var shared_role := role
	for binding in bindings:
		if str(binding.get("role", "")) == role:
			shared_role = str(binding.get("style_role", role))
			break
	var values := style.settings_for(shared_role) if style != null and not shared_role.is_empty() else BuildingMaterialLibrary.DEFAULTS.duplicate()
	var overrides: Variant = local_overrides.get(role, {})
	if overrides is Dictionary:
		values.merge(overrides, true)
	return BuildingMaterialLibrary.resolve(values)


func get_role_material(role: String) -> ShaderMaterial:
	return _materials.get(role) as ShaderMaterial


func refresh_materials() -> void:
	restore_owned_overrides()
	_disconnect_meshes()
	if not is_inside_tree():
		return
	# Asset Placer owns its translucent ghost materials. Placed instances are
	# created fresh outside that preview container and receive the role materials.
	if _inside_placement_preview():
		_materials.clear()
		return
	_adopt_scene_copies()
	_watch_hierarchy(self)
	var used_roles := {}
	var used_surfaces := {}
	for binding in bindings:
		var mesh := _binding_mesh(binding)
		if mesh == null or mesh.mesh == null:
			continue
		var surface := int(binding.get("surface", -1))
		var role := str(binding.get("role", "")).strip_edges()
		if role.is_empty() or surface < 0 or surface >= mesh.mesh.get_surface_count():
			continue
		if not _surface_matches(mesh.mesh, binding) or mesh.material_override != null:
			continue
		var key := "%s:%s" % [mesh.get_instance_id(), surface]
		if used_surfaces.has(key):
			continue
		used_surfaces[key] = true
		if not used_roles.has(role):
			if not _materials.has(role):
				_materials[role] = ShaderMaterial.new()
			BuildingMaterialLibrary.apply(_materials[role], resolve_slot_settings(role))
			used_roles[role] = true
		# Bypass the Node's serialized property. MeshInstance3D retains the original
		# authored override; rendering gets a transient per-instance surface RID.
		RenderingServer.instance_set_surface_override_material(mesh.get_instance(), surface, _materials[role].get_rid())
		_applied.append({"target": weakref(mesh), "surface": surface})
	for role in _materials.keys():
		if not used_roles.has(role):
			_materials.erase(role)
	if Engine.is_editor_hint():
		update_configuration_warnings()


func restore_owned_overrides() -> void:
	for entry in _applied:
		var mesh := entry.target.get_ref() as MeshInstance3D
		var surface: int = entry.surface
		if mesh == null or mesh.mesh == null or surface >= mesh.mesh.get_surface_count():
			continue
		var original := mesh.get_surface_override_material(surface)
		RenderingServer.instance_set_surface_override_material(mesh.get_instance(), surface, original.get_rid() if original != null else RID())
	_applied.clear()


func _watch_hierarchy(node: Node) -> void:
	if node != self and node is BuildingMaterialController:
		return
	_watched_targets.append(weakref(node))
	node.child_order_changed.connect(_settings_changed)
	node.renamed.connect(_settings_changed)
	node.tree_exiting.connect(_settings_changed)
	if node is Node3D:
		node.visibility_changed.connect(_settings_changed)
	if node is MeshInstance3D and node.mesh != null and node.mesh not in _watched_meshes:
		_watched_meshes.append(node.mesh)
		node.mesh.changed.connect(_settings_changed)
	for child in node.get_children():
		_watch_hierarchy(child)


func _disconnect_meshes() -> void:
	for ref in _watched_targets:
		var target := ref.get_ref() as Node
		if target != null:
			for signal_name in [&"child_order_changed", &"renamed", &"tree_exiting"]:
				if target.is_connected(signal_name, _settings_changed):
					target.disconnect(signal_name, _settings_changed)
			if target is Node3D and target.visibility_changed.is_connected(_settings_changed):
				target.visibility_changed.disconnect(_settings_changed)
	_watched_targets.clear()
	for mesh in _watched_meshes:
		if mesh.changed.is_connected(_settings_changed):
			mesh.changed.disconnect(_settings_changed)
	_watched_meshes.clear()


func _inside_placement_preview() -> bool:
	var parent := get_parent()
	while parent != null:
		var script := parent.get_script() as Script
		if script != null and script.get_global_name() == &"AssetPreviewContainer":
			return true
		parent = parent.get_parent()
	return false


func _binding_mesh(binding: Dictionary) -> MeshInstance3D:
	var mesh := get_node_or_null(NodePath(str(binding.get("mesh_path", "")))) as MeshInstance3D
	if mesh == null or not is_ancestor_of(mesh):
		return null
	var parent: Node = mesh.get_parent()
	while parent != self:
		if parent is BuildingMaterialController:
			return null
		parent = parent.get_parent()
	return mesh


func available_surfaces() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_collect_surfaces(self, result)
	return result


func _collect_surfaces(node: Node, result: Array[Dictionary]) -> void:
	for child in node.get_children():
		if child is BuildingMaterialController:
			continue
		if child is MeshInstance3D and child.mesh != null:
			for surface in child.mesh.get_surface_count():
				result.append({"mesh_path": get_path_to(child), "surface": surface,
					"surface_name": _surface_name(child.mesh, surface)})
		_collect_surfaces(child, result)


static func _surface_name(mesh: Mesh, surface: int) -> String:
	return mesh.surface_get_name(surface) if mesh is ArrayMesh else ""


static func _surface_matches(mesh: Mesh, binding: Dictionary) -> bool:
	var expected := str(binding.get("surface_name", ""))
	return expected.is_empty() or expected == _surface_name(mesh, int(binding.surface))


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var seen := {}
	for binding in bindings:
		var path := NodePath(str(binding.get("mesh_path", "")))
		var mesh := _binding_mesh(binding)
		var surface := int(binding.get("surface", -1))
		if mesh == null or mesh.mesh == null:
			warnings.append("Missing mesh or mesh owned by another controller: %s. Reassign its surface binding." % path)
			continue
		if surface < 0 or surface >= mesh.mesh.get_surface_count() or not _surface_matches(mesh.mesh, binding):
			warnings.append("Surface changed on %s. Reassign its binding after reimport." % path)
			continue
		if mesh.material_override != null:
			warnings.append("Clear whole-mesh Material Override on %s to use slot materials." % path)
		var key := "%s:%s" % [path, surface]
		if seen.has(key):
			warnings.append("Duplicate binding: %s surface %d." % [path, surface])
		seen[key] = true
	return warnings
