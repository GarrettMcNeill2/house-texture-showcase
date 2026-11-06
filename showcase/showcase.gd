extends Node3D

const HOUSE := preload("res://scenes/world_objects/buildings/house_two.tscn")
const FINISHES := ["brick", "panel", "wood", "base_color"]
const FINISH_LABELS := ["Brick", "Panel", "Wood", "Solid color"]
const WALL_ROLE := "slot:house_base/house_base:1"
const WALL_TINT := Color("#e4b293")

var _style := BuildingMaterialStyle.new()
var _left: BuildingMaterialController
var _right: BuildingMaterialController
var _left_wall: Dictionary
var _left_glass: Dictionary
var _finish: OptionButton
var _tint: ColorPickerButton
var _scale: HSlider
var _override: CheckButton
var _opacity: HSlider


func _ready() -> void:
	_style.slots = {"walls": {"texture_set": "brick", "tint": WALL_TINT, "uv_scale": Vector2(3, 3)}}
	_left = _add_house(Vector3(-5.8, 0, 0))
	_right = _add_house(Vector3(5.8, 0, 0))
	_left_wall = _surface(_left, "house_base/house_base", 1)
	_left_glass = _surface(_left, "window/window", 0)
	_add_stage()
	_add_controls()
	var args := OS.get_cmdline_user_args()
	if "--smoke" in args:
		await _smoke()
	elif "--capture" in args:
		await _capture()


func _add_house(at: Vector3) -> BuildingMaterialController:
	var house := HOUSE.instantiate() as BuildingMaterialController
	var bindings := house.bindings.duplicate(true)
	for binding in bindings:
		if binding.role == WALL_ROLE:
			binding.style_role = "walls"
	house.bindings = bindings
	var overrides := house.local_overrides.duplicate(true)
	overrides.erase(WALL_ROLE)
	house.local_overrides = overrides
	house.style = _style
	house.position = at
	add_child(house)
	return house


func _surface(house: BuildingMaterialController, path: String, index: int) -> Dictionary:
	for surface in house.available_surfaces():
		if str(surface.mesh_path) == path and surface.surface == index:
			return surface
	return {}


func _add_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#222f3d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#dbe8fc")
	environment.ambient_light_energy = 0.5
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -27, 0)
	light.light_color = Color("#fff1de")
	light.light_energy = 1.0
	light.shadow_enabled = true
	add_child(light)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(150, 150)
	ground.mesh = plane
	ground.position.y = -0.07
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#485d68")
	material.roughness = 1.0
	ground.material_override = material
	add_child(ground)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 19.0
	camera.position = Vector3(-11.9, 16, 31)
	add_child(camera)
	camera.look_at(Vector3(-3.4, 5.0, 0))


func _add_controls() -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size.x = 292
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#17212d")
	background.set_corner_radius_all(12)
	background.content_margin_left = 20
	background.content_margin_right = 20
	background.content_margin_top = 18
	background.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", background)
	overlay.add_child(panel)

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	panel.add_child(controls)
	_label(controls, "House Texture System", 23)
	controls.add_child(HSeparator.new())
	_label(controls, "Shared walls · both houses", 18)

	_label(controls, "Finish")
	_finish = OptionButton.new()
	for label in FINISH_LABELS:
		_finish.add_item(label)
	controls.add_child(_finish)
	_finish.item_selected.connect(func(index: int) -> void:
		_style.set_role_field("walls", "texture_set", FINISHES[index]))

	_label(controls, "Color")
	_tint = ColorPickerButton.new()
	_tint.custom_minimum_size.y = 32
	_tint.edit_alpha = false
	_tint.color = WALL_TINT
	controls.add_child(_tint)
	_tint.color_changed.connect(func(color: Color) -> void: _style.set_role_field("walls", "tint", color))

	_scale = _slider(controls, "Texture repeats", 1, 8, 3)
	_scale.value_changed.connect(func(value: float) -> void:
		_style.set_role_field("walls", "uv_scale", Vector2(value, value)))

	controls.add_child(HSeparator.new())
	_label(controls, "Left house", 18)
	_override = CheckButton.new()
	_override.text = "Use local wall color"
	controls.add_child(_override)
	_override.toggled.connect(_set_local_color)

	_opacity = _slider(controls, "Linked window opacity", 0, 1, 0.35)
	_opacity.value_changed.connect(_set_glass_opacity)

	var reset := Button.new()
	reset.text = "Reset"
	controls.add_child(reset)
	reset.pressed.connect(_reset)


func _label(parent: Control, title: String, font_size: int = 16) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)


func _slider(parent: Control, title: String, minimum: float, maximum: float, initial: float) -> HSlider:
	_label(parent, title)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = initial
	parent.add_child(slider)
	return slider


func _set_local_color(enabled: bool) -> void:
	var config := _left.edited_slot_configuration(_left_wall, "tint", Color("#8ebcaa")) if enabled else _left.reset_slot_configuration(_left_wall, "tint")
	_left.set("material_slots", config)


func _set_glass_opacity(value: float) -> void:
	_left.set("material_slots", _left.edited_slot_configuration(_left_glass, "opacity", value))


func _reset() -> void:
	_finish.select(0)
	_finish.item_selected.emit(0)
	_tint.color = WALL_TINT
	_tint.color_changed.emit(WALL_TINT)
	_scale.value = 3
	_override.button_pressed = false
	_opacity.value = 0.35


func _capture() -> void:
	await _save_frame("01-shared-brick.png")
	_finish.select(1)
	_finish.item_selected.emit(1)
	_override.button_pressed = true
	_opacity.value = 0.85
	await _save_frame("02-panel-with-local-color.png")
	get_tree().quit()


func _save_frame(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png("res://media/" + file_name)
	if result != OK:
		push_error("Capture failed: " + error_string(result))


func _smoke() -> void:
	await get_tree().process_frame
	_finish.select(1)
	_finish.item_selected.emit(1)
	_scale.value = 5
	_override.button_pressed = true
	_opacity.value = 0.8
	await get_tree().process_frame
	var left := _left.slot_settings(_left_wall)
	var right := _right.resolve_slot_settings(WALL_ROLE)
	var other_glass := _surface(_left, "window2/window", 0)
	var right_glass := _surface(_right, "window/window", 0)
	var material := _left.get_role_material(WALL_ROLE)
	var passed: bool = left.texture_set == "panel" and right.texture_set == "panel"
	passed = passed and left.uv_scale == Vector2(5, 5) and right.uv_scale == Vector2(5, 5)
	passed = passed and left.tint == Color("#8ebcaa") and right.tint == WALL_TINT
	passed = passed and is_equal_approx(_left.slot_settings(_left_glass).opacity, 0.8)
	passed = passed and is_equal_approx(_left.slot_settings(other_glass).opacity, 0.8)
	passed = passed and is_equal_approx(_right.slot_settings(right_glass).opacity, 0.35)
	passed = passed and material != null and material.get_shader_parameter("uv_scale") == Vector2(5, 5)
	_reset()
	await get_tree().process_frame
	passed = passed and _left.slot_settings(_left_wall).tint == WALL_TINT
	passed = passed and _right.resolve_slot_settings(WALL_ROLE).texture_set == "brick"
	passed = passed and is_equal_approx(_left.slot_settings(other_glass).opacity, 0.35)
	print("House texture smoke: ", "PASS" if passed else "FAIL")
	get_tree().quit(0 if passed else 1)
