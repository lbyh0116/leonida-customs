extends SubViewportContainer

signal free_view_changed(active: bool)

const FLOOR_SHADER := preload("res://src/render_studio_floor.gdshader")
const VehicleMaterials := preload("res://src/vehicle_materials.gd")
const PANEL_SIZE := Vector2(5.5, 7.2)
const PANEL_HEIGHT := 3.35

var stage: Node3D
var viewport: SubViewport
var environment: Environment
var floor_surface: MeshInstance3D
var _floor_material: ShaderMaterial
var _path_floor: StandardMaterial3D
var _raster_floor_mesh: PlaneMesh
var _path_floor_mesh: ArrayMesh
var _path_tracing := false
var _panel: AreaLight3D
var _mirror_view: SubViewport
var _mirror_camera: Camera3D
var _mirror_transform := Transform3D.IDENTITY
var _mirror_active := false
var _mirror_dirty := true
var _reflections := true
var _painted_surfaces: Array[ShaderMaterial] = []
var _vehicle_lamps: Array[BaseMaterial3D] = []
var _lamps_enabled := true
var _paint_finish := 0
var _paint_color := ""
var _fly_speed := 4.0
var _free_view := false
var external_input := false
var _remote_keys: Dictionary = {}
var _lighting := {
	"key": 0.88, "azimuth": -42.0, "elevation": 65.0, "size": 6.0, "specular": 0.0,
	"fill": 0.70, "ambient": 0.16, "exposure": 1.07, "floor_roughness": 0.15,
	"light_color": Color("#fff3e8"), "background_color": Color("#e9edf1"),
	"floor_color": Color("#c5c8cf"),
}
var camera: Camera3D
var model: Node3D
var spinning := false
var _target := Vector3.ZERO
var _center := Vector3.ZERO
var _radius := 3.0
var _distance := 9.0
var _yaw := PI * 0.78
var _pitch := 0.27
var _key: DirectionalLight3D


func _ready() -> void:
	stretch = true
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	viewport = SubViewport.new()
	viewport.size = Vector2i(800, 550)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.use_taa = true
	viewport.positional_shadow_atlas_size = 4096
	add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	_add_environment()
	_key = DirectionalLight3D.new()
	_key.rotation_degrees = Vector3(-46, -42, 0)
	_key.light_color = _lighting.light_color
	_key.light_energy = _lighting.key
	_key.shadow_enabled = true
	_key.light_angular_distance = _lighting.size
	_key.directional_shadow_max_distance = 38.0
	stage.add_child(_key)
	_add_light_panel()
	_raster_floor_mesh = PlaneMesh.new()
	_raster_floor_mesh.size = Vector2(400, 400)
	_floor_material = ShaderMaterial.new()
	_floor_material.shader = FLOOR_SHADER
	floor_surface = MeshInstance3D.new()
	floor_surface.mesh = _raster_floor_mesh
	floor_surface.material_override = _floor_material
	floor_surface.layers = 2
	floor_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(floor_surface)
	_set_floor(false)
	_path_floor = StandardMaterial3D.new()
	_path_floor.cull_mode = BaseMaterial3D.CULL_DISABLED
	_path_floor.metallic_specular = 0.49
	camera = Camera3D.new()
	camera.fov = 38
	camera.near = 0.04
	camera.far = 500
	stage.add_child(camera)
	_add_floor_reflection()
	viewport.size_changed.connect(_move_camera)
	set_lighting(_lighting)
	set_effects(true, true, true, true)
	reset_camera()


func _add_environment() -> void:
	var world := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = _lighting.background_color
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color("#e8edf4")
	environment.ambient_light_energy = _lighting.ambient
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var image := Image.create_empty(512, 256, false, Image.FORMAT_RGBAH)
	for y in range(256):
		var latitude := PI * (float(y) + 0.5) / 256.0
		var direction_y := cos(latitude)
		for x in range(512):
			var colour := Color(0.040, 0.046, 0.057).lerp(Color(0.16, 0.17, 0.19), smoothstep(-0.4, 0.8, direction_y))
			var longitude := TAU * (float(x) + 0.5) / 512.0
			var horizontal := Vector2(sin(longitude), -cos(longitude)) * sin(latitude)
			if direction_y > 0.15:
				var ceiling := (horizontal * (PANEL_HEIGHT / direction_y)).abs()
				var edge := PANEL_SIZE * 0.5
				var width := 1.0 - smoothstep(edge.x - 0.13, edge.x, ceiling.x)
				var length := 1.0 - smoothstep(edge.y - 0.15, edge.y, ceiling.y)
				var bright_edge := smoothstep(edge.x - 0.80, edge.x - 0.16, ceiling.x)
				colour += Color(2.15, 2.25, 2.4) * width * length * lerpf(1.0, 1.65, bright_edge)
			# The long white walls give curved panels and polished metal a
			# continuous highlight, with no fill light aimed into the cavities.
			if absf(horizontal.x) > 0.15:
				var wall := Vector2(direction_y, horizontal.y) * (4.4 / absf(horizontal.x))
				var height := 1.0 - smoothstep(0.47, 0.80, absf(wall.x - 0.83))
				var length := 1.0 - smoothstep(3.0, 4.0, absf(wall.y))
				colour += Color(2.35, 2.49, 2.68) * height * length
			colour.a = 1.0
			image.set_pixel(x, y, colour)
	# The sky supplies the overhead reflection while the area light lights the stage.
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = ImageTexture.create_from_image(image)
	var sky := Sky.new()
	sky.sky_material = panorama
	environment.sky = sky
	world.environment = environment
	stage.add_child(world)


func _add_light_panel() -> void:
	_panel = AreaLight3D.new()
	_panel.position = Vector3(0.0, PANEL_HEIGHT, 0.0)
	_panel.rotation_degrees.x = -90.0
	_panel.light_color = Color("#edf4ff")
	_panel.area_size = PANEL_SIZE
	_panel.area_range = 12.0
	_panel.shadow_enabled = true
	_panel.shadow_bias = 0.035
	_panel.shadow_normal_bias = 0.24
	stage.add_child(_panel)


func _add_floor_reflection() -> void:
	_mirror_view = SubViewport.new()
	_mirror_view.world_3d = viewport.find_world_3d()
	_mirror_view.transparent_bg = true
	_mirror_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mirror_view.positional_shadow_atlas_size = 1024
	viewport.add_child(_mirror_view)
	_mirror_camera = Camera3D.new()
	_mirror_camera.cull_mask = 1
	_mirror_camera.environment = environment.duplicate()
	_mirror_camera.environment.background_color = Color.BLACK
	_mirror_camera.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_mirror_camera.environment.tonemap_exposure = 1.0
	_mirror_view.add_child(_mirror_camera)
	_floor_material.set_shader_parameter("floor_reflection", _mirror_view.get_texture())
	viewport.size_changed.connect(_resize_floor_reflection)
	_resize_floor_reflection()


func _resize_floor_reflection() -> void:
	_mirror_view.size = (viewport.size / 2).max(Vector2i(4, 4))
	_mirror_dirty = true


func _update_floor_reflection() -> void:
	var active := _reflections and not _path_tracing and model != null and camera.position.y > camera.near
	if active != _mirror_active:
		_mirror_active = active
		_floor_parameter("show_reflection", active)
		_mirror_dirty = true
	if not active:
		return
	var current := camera.global_transform
	if not _mirror_dirty and _mirror_transform.is_equal_approx(current):
		return
	_mirror_dirty = false
	_mirror_transform = current
	var reflected := current
	reflected.origin.y = -reflected.origin.y
	reflected.basis.x *= Vector3(-1.0, 1.0, -1.0)
	reflected.basis.y.y = -reflected.basis.y.y
	reflected.basis.z.y = -reflected.basis.z.y
	_mirror_camera.global_transform = reflected
	_mirror_camera.fov = camera.fov
	_mirror_camera.near = camera.near
	_mirror_camera.far = camera.far
	_mirror_view.render_target_update_mode = SubViewport.UPDATE_ONCE


func render_capabilities() -> Dictionary:
	var device := RenderingServer.get_rendering_device()
	var trace_feature := ClassDB.class_get_integer_constant("RenderingDevice", "SUPPORTS_RAYTRACING_PIPELINE") if ClassDB.class_has_integer_constant("RenderingDevice", "SUPPORTS_RAYTRACING_PIPELINE") else -1
	var path_tracing := environment.has_method("set_pathtracing_enabled") and device != null and trace_feature >= 0 and device.has_feature(trace_feature)
	var dlss := false
	var reconstruction := false
	if ClassDB.class_has_integer_constant("Viewport", "SCALING_3D_MODE_DLSS") and Engine.has_singleton("Streamline"):
		var streamline := Engine.get_singleton("Streamline")
		dlss = streamline.call("get_capability", ClassDB.class_get_integer_constant("Streamline", "STREAMLINE_CAPABILITY_DLSS"))
		reconstruction = streamline.call("get_capability", ClassDB.class_get_integer_constant("Streamline", "STREAMLINE_CAPABILITY_DLSS_RR"))
	return {"path_tracing": path_tracing, "dlss": dlss, "ray_reconstruction": reconstruction}


func set_render_mode(enabled: bool, samples: int, denoise: bool) -> bool:
	var path_tracing: bool = enabled and render_capabilities().path_tracing
	if path_tracing != _path_tracing:
		_path_tracing = path_tracing
		_mirror_dirty = true
		for material in _painted_surfaces:
			material.set_shader_parameter("path_tracing", _path_tracing)
	if environment.has_method("set_pathtracing_enabled"):
		environment.call("set_pathtracing_enabled", _path_tracing)
		environment.call("set_pathtracing_samples_per_pixel", clampi(samples, 1, 16))
		environment.call("set_pathtracing_max_bounces", 5)
		var mode := "PT_DENOISER_DLSS_RAY_RECONSTRUCTION" if denoise else "PT_DENOISER_NONE"
		environment.call("set_pathtracing_denoiser", ClassDB.class_get_integer_constant("RenderingServer", mode))
	if _path_tracing and _path_floor_mesh == null:
		_path_floor_mesh = _make_cyclorama()
	floor_surface.mesh = _path_floor_mesh if _path_tracing else _raster_floor_mesh
	floor_surface.material_override = _path_floor if _path_tracing else _floor_material
	return _path_tracing


func _make_cyclorama() -> ArrayMesh:
	var profile := PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0)])
	for step in range(1, 13):
		var bend := PI * 0.5 * step / 12.0
		profile.append(Vector3(10.0 + 4.0 * sin(bend), 4.0 * (1.0 - cos(bend)), bend))
	profile.append(Vector3(14, 15, PI * 0.5))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	const SEGMENTS := 64
	for row in profile:
		for column in range(SEGMENTS):
			var angle := TAU * column / SEGMENTS
			var direction := Vector3(cos(angle), 0, sin(angle))
			vertices.append(direction * row.x + Vector3.UP * row.y)
			normals.append(Vector3.UP * cos(row.z) - direction * sin(row.z))
	for row in range(profile.size() - 1):
		for column in range(SEGMENTS):
			var left := row * SEGMENTS + column
			var right := row * SEGMENTS + (column + 1) % SEGMENTS
			if row > 0:
				indices.append_array(PackedInt32Array([left, right + SEGMENTS, right]))
			indices.append_array(PackedInt32Array([left, left + SEGMENTS, right + SEGMENTS]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func set_quality(aa: int, scale: float) -> void:
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.use_taa = aa == 3
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	if aa == 8 and render_capabilities().dlss:
		viewport.scaling_3d_mode = ClassDB.class_get_integer_constant("Viewport", "SCALING_3D_MODE_DLSS")
	else:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if aa == 7 else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = clampf(scale, 0.50, 1.0)
	viewport.fsr_sharpness = 0.33
	match aa:
		1: viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		2: viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		4: viewport.msaa_3d = Viewport.MSAA_2X
		5: viewport.msaa_3d = Viewport.MSAA_4X
		6: viewport.msaa_3d = Viewport.MSAA_8X


func set_effects(reflections: bool, occlusion: bool, bounced_light: bool, bloom: bool) -> void:
	_reflections = reflections
	environment.ssr_enabled = reflections
	environment.ssr_max_steps = 100
	environment.ssr_depth_tolerance = 0.20
	environment.ssao_enabled = occlusion
	environment.ssao_radius = 0.37
	environment.ssao_intensity = 2.2
	environment.ssao_light_affect = 0.35
	environment.ssil_enabled = bounced_light
	environment.ssil_radius = 2.8
	environment.ssil_intensity = 0.24
	environment.glow_enabled = bloom
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.glow_intensity = 0.14
	environment.glow_hdr_threshold = 1.65


func lighting_defaults() -> Dictionary:
	return _lighting.duplicate()


func set_lighting(options: Dictionary) -> void:
	_key.light_color = options.light_color
	_key.light_energy = options.key
	_key.light_specular = options.specular
	_key.rotation_degrees = Vector3(-options.elevation, options.azimuth, 0.0)
	_key.light_angular_distance = options.size
	_panel.light_energy = options.fill
	_mirror_dirty = true
	environment.ambient_light_energy = options.ambient
	_mirror_camera.environment.ambient_light_energy = options.ambient
	environment.tonemap_exposure = options.exposure
	environment.background_color = options.background_color
	_floor_material.set_shader_parameter("surface_roughness", options.floor_roughness)
	_floor_material.set_shader_parameter("backdrop_color", options.background_color)
	_floor_parameter("floor_color", options.floor_color)
	_path_floor.albedo_color = options.floor_color
	_path_floor.roughness = options.floor_roughness


func _set_floor(enabled: bool) -> void:
	_floor_parameter("show_grid", enabled)


func _floor_parameter(key: String, value: Variant) -> void:
	_floor_material.set_shader_parameter(key, value)


func _update_tire_contacts(geometries: Array[Node]) -> void:
	var patches := PackedVector4Array()
	patches.resize(8)
	var count := 0
	for node: MeshInstance3D in geometries:
		if count == patches.size() or node.mesh == null:
			continue
		var tire := str(node.name).to_lower()
		if not tire.begins_with("tyre_") or not tire.contains("_wheel_"):
			continue
		var bounds: AABB = node.global_transform * node.get_aabb()
		if bounds.position.y > 0.12:
			continue
		var center := bounds.get_center()
		patches[count] = Vector4(center.x, center.z, maxf(0.06, bounds.size.x * 0.63), maxf(0.06, bounds.size.z * 0.25))
		count += 1
	_floor_parameter("tire_patches", patches)
	_floor_parameter("tire_count", count)


func show_model(path: String) -> Dictionary:
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var error := gltf.append_from_file(path, state)
	if error != OK:
		return {"error": "Godot 无法读取整车 GLB（%s）。" % error_string(error)}
	var imported := gltf.generate_scene(state) as Node3D
	if imported == null:
		return {"error": "GLB 中没有可预览的 3D 场景。"}
	var holder := Node3D.new()
	holder.add_child(imported)
	stage.add_child(holder)
	var geometries := imported.find_children("*", "MeshInstance3D", true, false)
	if geometries.is_empty():
		holder.free()
		return {"error": "GLB 中没有网格。"}
	var bounds := AABB()
	var initialized := false
	for child: MeshInstance3D in geometries:
		if child.mesh == null:
			continue
		var mesh_bounds: AABB = child.global_transform * child.get_aabb()
		bounds = bounds.merge(mesh_bounds) if initialized else mesh_bounds
		initialized = true
	if not initialized or not bounds.size.is_finite() or not bounds.position.is_finite() or bounds.size.length() <= 0.001:
		holder.free()
		return {"error": "车辆的网格边界无效。"}
	var center := bounds.get_center()
	holder.position = Vector3(-center.x, -bounds.position.y + 0.002, -center.z)
	var materials := VehicleMaterials.new()
	materials.apply(geometries, state, path, holder.transform * bounds)
	_painted_surfaces = materials.painted_surfaces
	_vehicle_lamps = materials.vehicle_lamps
	set_vehicle_lamps(_lamps_enabled)
	set_paint(_paint_finish, _paint_color)
	_update_tire_contacts(geometries)
	var first_or_different := model == null or not is_equal_approx(_radius, bounds.size.length() / 2.0)
	if model != null:
		model.queue_free()
	model = holder
	_center = Vector3(0, bounds.size.y * 0.40, 0)
	_radius = maxf(0.25, bounds.size.length() / 2.0)
	_key.directional_shadow_max_distance = maxf(22.0, _radius * 5.0)
	if first_or_different:
		reset_camera()
	return {"meshes": geometries.size(), "size": bounds.size, "paintable": not _painted_surfaces.is_empty()}


func set_paint(finish: int, color: String) -> void:
	_mirror_dirty = true
	_paint_finish = clampi(finish, 0, 4)
	_paint_color = color
	var custom_color := color.length() == 7 and color.begins_with("#") and Color.html_is_valid(color)
	for surface in _painted_surfaces:
		surface.set_shader_parameter("path_tracing", _path_tracing)
		surface.set_shader_parameter("finish", _paint_finish)
		surface.set_shader_parameter("recolor", _paint_finish != 0 and custom_color)
		if custom_color:
			surface.set_shader_parameter("paint_color", Color.html(color))


func set_vehicle_lamps(enabled: bool) -> void:
	_mirror_dirty = true
	_lamps_enabled = enabled
	for material in _vehicle_lamps:
		material.emission_enabled = enabled



func clear_model() -> void:
	if model != null:
		model.queue_free()
		model = null
	_painted_surfaces.clear()
	_vehicle_lamps.clear()
	_floor_parameter("tire_count", 0)
	_center = Vector3.ZERO
	_radius = 3.0
	reset_camera()


func reset_camera() -> void:
	set_free_view(false)
	_target = _center
	_yaw = PI * 0.78
	_pitch = 0.23
	_distance = _radius * 2.78
	_move_camera()


func set_grid(enabled: bool) -> void:
	_set_floor(enabled)


func _process(delta: float) -> void:
	if _free_view:
		_move_free_camera(delta)
	elif spinning and model != null:
		_yaw += delta * 0.40
		_move_camera()
	_update_floor_reflection()


func _gui_input(event: InputEvent) -> void:
	if model == null or _free_view:
		return
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_yaw -= event.relative.x * 0.009
			_pitch = clampf(_pitch + event.relative.y * 0.009, -0.12, 1.45)
		elif event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			var scale_factor := _distance * 0.0015
			_target += (-camera.global_basis.x * event.relative.x + camera.global_basis.y * event.relative.y) * scale_factor
		else:
			return
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance *= 0.89
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance /= 0.89
		elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			reset_camera()
			accept_event()
			return
		else:
			return
		_distance = clampf(_distance, _radius * 1.1, _radius * 12.0)
	else:
		return
	_move_camera()
	accept_event()


func _move_camera() -> void:
	if not is_instance_valid(camera) or _free_view:
		return
	var direction := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	var framing := _aspect_framing()
	camera.position = _target + direction * _distance * framing
	camera.look_at(_target, Vector3.UP)


func set_free_view(active: bool) -> void:
	if active == _free_view or (active and model == null):
		return
	_free_view = active
	if active:
		_fly_speed = clampf(_radius * 1.5, 1.0, 20.0)
		if not external_input:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_remote_keys.clear()
		if not external_input:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var back := camera.global_basis.z
		_yaw = atan2(back.x, back.z)
		_pitch = asin(clampf(back.y, -1.0, 1.0))
		_target = camera.position - back * _distance * _aspect_framing()
	free_view_changed.emit(_free_view)


func _aspect_framing() -> float:
	var area := Vector2(viewport.size) if external_input else size
	return maxf(1.0, 0.98 / maxf(0.1, area.x / maxf(area.y, 1.0)))


func _move_free_camera(delta: float) -> void:
	var move := Vector3.ZERO
	if _key_held(KEY_W): move -= camera.basis.z
	if _key_held(KEY_S): move += camera.basis.z
	if _key_held(KEY_A): move -= camera.basis.x
	if _key_held(KEY_D): move += camera.basis.x
	if _key_held(KEY_E): move += Vector3.UP
	if _key_held(KEY_Q): move += Vector3.DOWN
	if move.length_squared() > 0.0:
		var boost := 3.0 if _key_held(KEY_SHIFT) else 1.0
		camera.position += move.normalized() * _fly_speed * boost * delta


func _input(event: InputEvent) -> void:
	if not _free_view or external_input:
		return
	if event is InputEventMouseMotion:
		camera.rotation.y -= event.screen_relative.x * 0.0028
		camera.rotation.x = clampf(camera.rotation.x - event.screen_relative.y * 0.0028, -1.54, 1.54)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_fly_speed = minf(_fly_speed * 1.22, 65.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_fly_speed = maxf(_fly_speed / 1.22, 0.35)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		set_free_view(false)
	else:
		return
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _free_view and not external_input:
		set_free_view(false)



func _exit_tree() -> void:
	if _free_view:
		_remote_keys.clear()
		if not external_input:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _key_held(key: Key) -> bool:
	return _remote_keys.has(key) if external_input else Input.is_physical_key_pressed(key)


func remote_camera_input(action: String, data: Dictionary) -> void:
	if model == null:
		return
	match action:
		"key":
			var key := int({"W": KEY_W, "A": KEY_A, "S": KEY_S, "D": KEY_D, "Q": KEY_Q, "E": KEY_E, "Shift": KEY_SHIFT}.get(data.key, KEY_NONE)) as Key
			if data.pressed and _free_view:
				_remote_keys[key] = true
			else:
				_remote_keys.erase(key)
		"motion":
			var motion := Vector2(data.x, data.y)
			if _free_view:
				camera.rotation.y -= motion.x * 0.0028
				camera.rotation.x = clampf(camera.rotation.x - motion.y * 0.0028, -1.54, 1.54)
			else:
				var event := InputEventMouseMotion.new()
				event.relative = motion
				event.button_mask = int(data.buttons) as MouseButtonMask
				_gui_input(event)
		"wheel":
			if _free_view:
				_fly_speed = clampf(_fly_speed * (1.22 if data.up else 1.0 / 1.22), 0.35, 65.0)
			else:
				var event := InputEventMouseButton.new()
				event.button_index = MOUSE_BUTTON_WHEEL_UP if data.up else MOUSE_BUTTON_WHEEL_DOWN
				event.pressed = true
				_gui_input(event)
