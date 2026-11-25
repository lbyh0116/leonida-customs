extends SubViewportContainer

signal free_view_changed(active: bool)
signal ray_status_changed(message: String)

const FLOOR_SHADER := preload("res://src/render_studio_floor.gdshader")
const STRIP_SHADER := preload("res://src/studio_strip.gdshader")
const RayShadow := preload("res://src/ray_shadow.gd")
const VehicleMaterials := preload("res://src/vehicle_materials.gd")
const STRIP_SIZE := Vector2(0.24, 7.2)
const STRIP_HEIGHT := 3.35
const STRIP_OFFSETS := [-2.35, -0.78, 0.78, 2.35]

var stage: Node3D
var viewport: SubViewport
var environment: Environment
var floor_surface: MeshInstance3D
var _floor_material: ShaderMaterial
var _ray_floor: ShaderMaterial
var _ray_trace: RefCounted
var _ray_timer: Timer
var _ray_enabled := false
var _ray_ready := false
var _ray_samples := 16
var _ray_request := 0
var _model_height := 1.0
var _fill: Array[AreaLight3D] = []
var _strip_material: ShaderMaterial
var _mirror_view: SubViewport
var _mirror_camera: Camera3D
var _reflections := true
var _painted_surfaces: Array[ShaderMaterial] = []
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
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
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
	_add_strips()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(400, 400)
	_floor_material = ShaderMaterial.new()
	_floor_material.shader = FLOOR_SHADER
	floor_surface = MeshInstance3D.new()
	floor_surface.mesh = floor_mesh
	floor_surface.material_override = _floor_material
	floor_surface.layers = 2
	floor_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(floor_surface)
	_set_floor(false)
	_ray_timer = Timer.new()
	_ray_timer.one_shot = true
	_ray_timer.wait_time = 0.09
	_ray_timer.timeout.connect(_update_ray_shadows)
	add_child(_ray_timer)
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
			if direction_y > 0.15:
				var longitude := TAU * (float(x) + 0.5) / 512.0
				var ceiling := Vector2(sin(longitude), -cos(longitude)) * (sin(latitude) * STRIP_HEIGHT / direction_y)
				for offset: float in STRIP_OFFSETS:
					var distance_x := absf(ceiling.x - offset)
					var width := 1.0 - smoothstep(0.07, 0.19, distance_x)
					var length := 1.0 - smoothstep(3.50, 3.65, absf(ceiling.y))
					colour += Color(4.9, 5.0, 5.2) * width * length
			colour.a = 1.0
			image.set_pixel(x, y, colour)
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = ImageTexture.create_from_image(image)
	var sky := Sky.new()
	sky.sky_material = panorama
	environment.sky = sky
	world.environment = environment
	stage.add_child(world)


func _add_strips() -> void:
	_strip_material = ShaderMaterial.new()
	_strip_material.shader = STRIP_SHADER
	var diffuser := BoxMesh.new()
	diffuser.size = Vector3(STRIP_SIZE.x, 0.025, STRIP_SIZE.y)
	for offset: float in STRIP_OFFSETS:
		var light := AreaLight3D.new()
		light.position = Vector3(offset, STRIP_HEIGHT, 0.0)
		light.rotation_degrees.x = -90.0
		light.light_color = Color("#edf4ff")
		light.area_size = STRIP_SIZE
		light.area_range = 12.0
		light.shadow_enabled = true
		light.shadow_bias = 0.035
		light.shadow_normal_bias = 0.24
		stage.add_child(light)
		_fill.append(light)
		var fixture := MeshInstance3D.new()
		fixture.position = light.position
		fixture.mesh = diffuser
		fixture.material_override = _strip_material
		fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stage.add_child(fixture)


func _add_floor_reflection() -> void:
	_mirror_view = SubViewport.new()
	_mirror_view.world_3d = viewport.find_world_3d()
	_mirror_view.transparent_bg = true
	_mirror_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mirror_view.positional_shadow_atlas_size = 1024
	viewport.add_child(_mirror_view)
	RenderingServer.viewport_set_measure_render_time(_mirror_view.get_viewport_rid(), true)
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


func _update_floor_reflection() -> void:
	var active := _reflections and model != null and camera.position.y > camera.near
	if active:
		var reflected := camera.global_transform
		reflected.origin.y = -reflected.origin.y
		reflected.basis.x *= Vector3(-1.0, 1.0, -1.0)
		reflected.basis.y.y = -reflected.basis.y.y
		reflected.basis.z.y = -reflected.basis.z.y
		_mirror_camera.global_transform = reflected
		_mirror_camera.fov = camera.fov
		_mirror_camera.near = camera.near
		_mirror_camera.far = camera.far
	_mirror_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	_floor_parameter("show_reflection", active)


func set_quality(aa: int, scale: float) -> void:
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.use_taa = aa == 3
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if aa == 7 else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = clampf(scale, 0.50, 1.0)
	viewport.fsr_sharpness = 0.33
	match aa:
		1: viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		2: viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		4: viewport.msaa_3d = Viewport.MSAA_2X
		5: viewport.msaa_3d = Viewport.MSAA_4X
		6: viewport.msaa_3d = Viewport.MSAA_8X


func gpu_frame_ms() -> float:
	var main := RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
	if _mirror_view.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		main += RenderingServer.viewport_get_measured_render_time_gpu(_mirror_view.get_viewport_rid())
	return main


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
	var previous_rotation := _key.rotation
	var previous_size := _key.light_angular_distance
	_key.light_color = options.light_color
	_key.light_energy = options.key
	_key.light_specular = options.specular
	_key.rotation_degrees = Vector3(-options.elevation, options.azimuth, 0.0)
	_key.light_angular_distance = options.size
	for panel in _fill:
		panel.light_energy = options.fill
	_strip_material.set_shader_parameter("brightness", options.fill * 3.5)
	environment.ambient_light_energy = options.ambient
	_mirror_camera.environment.ambient_light_energy = options.ambient
	environment.tonemap_exposure = options.exposure
	environment.background_color = options.background_color
	_floor_material.set_shader_parameter("surface_roughness", options.floor_roughness)
	_floor_material.set_shader_parameter("backdrop_color", options.background_color)
	if _ray_floor != null:
		_ray_floor.set_shader_parameter("surface_roughness", options.floor_roughness)
		_ray_floor.set_shader_parameter("backdrop_color", options.background_color)
		_ray_floor.set_shader_parameter("shadow_strength", _shadow_strength())
	if _ray_ready and (not previous_rotation.is_equal_approx(_key.rotation) or not is_equal_approx(previous_size, _key.light_angular_distance)):
		_ray_timer.start()


func _set_floor(enabled: bool) -> void:
	_floor_parameter("show_grid", enabled)


func _floor_parameter(key: String, value: Variant) -> void:
	_floor_material.set_shader_parameter(key, value)
	if _ray_floor != null:
		_ray_floor.set_shader_parameter(key, value)


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
	set_paint(_paint_finish, _paint_color)
	_update_tire_contacts(geometries)
	var first_or_different := model == null or not is_equal_approx(_radius, bounds.size.length() / 2.0)
	if model != null:
		model.queue_free()
	model = holder
	_center = Vector3(0, bounds.size.y * 0.40, 0)
	_radius = maxf(0.25, bounds.size.length() / 2.0)
	_model_height = bounds.size.y
	_invalidate_ray_shadows()
	if _ray_enabled:
		_request_ray_geometry.call_deferred(_ray_request)
	_key.directional_shadow_max_distance = maxf(22.0, _radius * 5.0)
	if first_or_different:
		reset_camera()
	return {"meshes": geometries.size(), "size": bounds.size, "paintable": not _painted_surfaces.is_empty()}


func set_paint(finish: int, color: String) -> void:
	_paint_finish = clampi(finish, 0, 4)
	_paint_color = color
	var custom_color := color.length() == 7 and color.begins_with("#") and Color.html_is_valid(color)
	for surface in _painted_surfaces:
		surface.set_shader_parameter("finish", _paint_finish)
		surface.set_shader_parameter("recolor", _paint_finish != 0 and custom_color)
		if custom_color:
			surface.set_shader_parameter("paint_color", Color.html(color))



func clear_model() -> void:
	_invalidate_ray_shadows()
	if model != null:
		model.queue_free()
		model = null
	_painted_surfaces.clear()
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



func supports_ray_shadows() -> bool:
	return int(Engine.get_version_info().minor) >= 8 and RayShadow.is_supported()


func set_ray_shadows(active: bool, samples: int) -> void:
	_ray_samples = clampi(samples, 8, 64)
	_ray_enabled = active and supports_ray_shadows()
	if not _ray_enabled:
		_invalidate_ray_shadows()
	elif _ray_ready:
		_ray_timer.start()
	elif model != null:
		_invalidate_ray_shadows()
		_request_ray_geometry.call_deferred(_ray_request)
	else:
		ray_status_changed.emit("载入车辆后启用硬件光追。")


func _invalidate_ray_shadows() -> void:
	_ray_request += 1
	_ray_ready = false
	_ray_timer.stop()
	floor_surface.material_override = _floor_material
	if not _ray_enabled:
		ray_status_changed.emit("使用光栅阴影。" if supports_ray_shadows() else "硬件光追需要 4.8 Beta 光追入口及受支持的 Vulkan 显卡。")


func _request_ray_geometry(request: int) -> void:
	if request != _ray_request or not _ray_enabled or model == null:
		return
	ray_status_changed.emit("正在为当前车辆构建光追加速结构…")
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node.mesh as ArrayMesh
		if mesh == null:
			continue
		var transform_to_world := node.global_transform
		for surface in range(mesh.get_surface_count()):
			var material := node.get_active_material(surface) as BaseMaterial3D
			if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES or (
				material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
			):
				continue
			var arrays := mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var start := vertices.size()
			vertices.resize(start + points.size())
			for index in range(points.size()):
				vertices[start + index] = transform_to_world * points[index]
			var triangles: Variant = arrays[Mesh.ARRAY_INDEX]
			if triangles is PackedInt32Array and not triangles.is_empty():
				var offset := indices.size()
				indices.resize(offset + triangles.size())
				for index in range(triangles.size()):
					indices[offset + index] = start + triangles[index]
			else:
				for index in range(points.size() - points.size() % 3):
					indices.append(start + index)

	if indices.size() < 3:
		ray_status_changed.emit("当前车辆没有可用于光追的三角面。")
		return
	if _ray_trace == null:
		_ray_trace = RayShadow.new()
	_ray_trace.prepare(vertices, indices, _ray_parameters(), _on_ray_ready.bind(request))


func _on_ray_ready(ok: bool, request: int) -> void:
	if request != _ray_request or not _ray_enabled or not is_inside_tree():
		return
	if not ok:
		ray_status_changed.emit("无法启用光追，已使用光栅阴影。")
		return
	if _ray_floor == null:
		_ray_floor = _floor_material.duplicate()
		var shader := Shader.new()
		shader.code = FLOOR_SHADER.code.replace("render_mode cull_disabled;", "render_mode cull_disabled, shadows_disabled;")
		_ray_floor.shader = shader
	_ray_floor.set_shader_parameter("ray_shadow", _ray_trace.texture)
	_ray_floor.set_shader_parameter("surface_roughness", _floor_material.get_shader_parameter("surface_roughness"))
	_ray_floor.set_shader_parameter("backdrop_color", _floor_material.get_shader_parameter("backdrop_color"))
	_ray_floor.set_shader_parameter("show_grid", _floor_material.get_shader_parameter("show_grid"))
	_ray_floor.set_shader_parameter("floor_reflection", _mirror_view.get_texture())
	_ray_floor.set_shader_parameter("tire_patches", _floor_material.get_shader_parameter("tire_patches"))
	_ray_floor.set_shader_parameter("tire_count", _floor_material.get_shader_parameter("tire_count"))
	_ray_floor.set_shader_parameter("shadow_strength", _shadow_strength())
	_ray_ready = true
	_update_ray_shadows()
	floor_surface.material_override = _ray_floor


func _shadow_strength() -> float:
	return clampf(1.06 * _key.light_energy / (_key.light_energy + 0.20), 0.0, 0.92)


func _ray_parameters() -> PackedFloat32Array:
	var sun := _key.global_basis.z.normalized()
	var radius := tan(deg_to_rad(minf(_key.light_angular_distance * 0.5, absf(_key.rotation_degrees.x) * 0.8)))
	var reach := _model_height * (1.0 + radius) / maxf(0.18, sun.y - radius)
	var ground_shift := -Vector2(sun.x, sun.z) * reach
	var object_border := Vector2.ONE * (_radius * 1.13 + 0.5 + reach * radius)
	var corner := -object_border + ground_shift.min(Vector2.ZERO)
	var cover := 2.0 * object_border + ground_shift.abs()
	return PackedFloat32Array([
		corner.x, corner.y, cover.x, cover.y,
		sun.x, sun.y, sun.z, radius, float(_ray_samples), maxf(_radius * 10.0, reach * 2.0), 0.0, 0.0
	])


func _update_ray_shadows() -> void:
	if not _ray_enabled or not _ray_ready:
		return
	var parameters := _ray_parameters()
	_ray_trace.update(parameters)
	_ray_floor.set_shader_parameter("shadow_rect", Vector4(parameters[0], parameters[1], parameters[2], parameters[3]))
	ray_status_changed.emit("Vulkan 硬件光追 · %s 条光线 / 采样点" % _ray_samples)


func _exit_tree() -> void:
	if _free_view:
		_remote_keys.clear()
		if not external_input:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _ray_trace != null:
		_ray_trace.release()


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
