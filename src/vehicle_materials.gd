extends RefCounted

const RIM_SHADER := preload("res://src/vehicle_rim.gdshader")
const BODY_SHADER := preload("res://src/vehicle_body.gdshader")
const VEHICLE_OCCLUSION_SLOT := "2bb2ede8"

var painted_surfaces: Array[ShaderMaterial] = []
var vehicle_lamps: Array[BaseMaterial3D] = []
static var _cutout_shader: Shader
var _texture_roots: PackedStringArray
var _textures: Dictionary = {}


func apply(geometries: Array[Node], state: GLTFState, path: String, bounds: AABB, factory_paint: Color, tracked: Dictionary) -> void:
	var vehicle_midline := bounds.get_center().x
	var directory := path.get_base_dir()
	for i in range(4):
		_texture_roots.append(directory)
		directory = directory.get_base_dir()
	var materials := state.get_materials()
	var records: Array = state.json.get("materials", [])
	var by_material: Dictionary = {}
	var wheel_nodes: Dictionary = {}
	var wheel_extents: Dictionary = {}
	var wheels_with_brakes: Dictionary = {}
	var backed_wheels: Dictionary = {}
	for i in range(mini(materials.size(), records.size())):
		if materials[i] != null:
			by_material[materials[i]] = records[i].get("extras", {})
	for node: MeshInstance3D in geometries:
		# Road-wheel polish and brake backing do not apply to track rollers.
		if tracked.has(node):
			continue
		# Godot's imported mesh-node names keep SixNG's wheel and geometry
		# labels, with the original '@' and '/' replaced by underscores.
		var name := str(node.name).to_lower()
		var tag := name.rfind("_wheel_")
		var end := name.find("_geom", tag + 7) if tag >= 0 else -1
		if end < 0:
			continue
		var wheel := name.substr(tag + 1, end - tag - 1)
		wheel_nodes[node] = wheel
		if name.begins_with("rim_"):
			var extent: AABB = node.global_transform * node.get_aabb()
			wheel_extents[wheel] = wheel_extents[wheel].merge(extent) if wheel_extents.has(wheel) else extent
		elif name.begins_with("brakedisc_") or name.begins_with("drumbrake_"):
			wheels_with_brakes[wheel] = true
	for node: MeshInstance3D in geometries:
		var mesh := node.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var original := mesh.surface_get_material(surface) as BaseMaterial3D
			if original == null or not by_material.has(original):
				continue
			var extras: Dictionary = by_material[original]
			var classification: Dictionary = extras.get("classification", {})
			var kind := str(classification.get("stand_in", ""))
			var family := str(classification.get("family", ""))
			var material_class := str(classification.get("class", ""))
			var lamp_shader := family.contains("vehicle lamps") or str(extras.get("shader_name", "")).begins_with("standard_vehicle_emissive")
			var node_name := str(node.name).to_lower()
			var accessory_light := node_name.contains("lightbar") or node_name.contains("siren") or node_name.contains("neon") or node_name.contains("underglow")
			var vehicle_lamp := original.emission_enabled and (lamp_shader or accessory_light)
			var lamp_lens := material_class == "glass" and family.contains("vehicle lamp")
			var window_glass := material_class == "window"
			var occlusion := _vehicle_occlusion(extras)
			if kind not in ["parts", "rim", "rubber"] and not vehicle_lamp and not lamp_lens and not window_glass and occlusion == null:
				continue
			var colours: Variant = mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			var has_colours: bool = colours is PackedColorArray and not colours.is_empty()
			var wheel: String = wheel_nodes.get(node, "")
			if kind == "rim" and wheel_extents.has(wheel):
				var wheel_extent: AABB = wheel_extents[wheel]
				# A centered wheel can be exposed on both sides, as on motorcycles.
				if absf(wheel_extent.get_center().x - vehicle_midline) > 0.25 and wheel_extent.size.x > 0.025:
					var polished := str(node.name).to_lower().begins_with("rim_")
					node.set_surface_override_material(surface, _rim_material(original, occlusion, wheel_extent, vehicle_midline, has_colours, polished))
					if not wheels_with_brakes.has(wheel) and not backed_wheels.has(wheel):
						backed_wheels[wheel] = true
						_add_missing_wheel_backing(node, wheel_extent, vehicle_midline)
					continue
			if kind == "parts" and has_colours and not original.emission_enabled and original.transparency in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]:
				var body := _body_material(original, occlusion, bounds)
				body.set_shader_parameter("factory_paint", factory_paint)
				node.set_surface_override_material(surface, body)
				_track_primary_paint(body, colours)
				continue
			var material := original.duplicate() as BaseMaterial3D
			if occlusion != null:
				# SixNG documents the blue channel as occlusion on both
				# the diffuse and specular sides of this vehicle layer.
				material.ao_enabled = true
				material.ao_texture = occlusion
				material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
				material.ao_light_affect = 0.85
			if vehicle_lamp:
				var emission: Variant = extras.get("emissive_strength")
				if lamp_shader and material.emission_texture != null:
					# Keep authored tint and strong emitters. Low-intensity game
					# lamps use the studio's visible on-state presentation.
					if emission is Dictionary and float(emission.get("strength", 0)) < 1.0:
						var tint: Variant = emission.get("tint")
						if tint is Array and tint.size() == 3:
							material.emission = Color(float(tint[0]), float(tint[1]), float(tint[2])).linear_to_srgb()
					material.emission_energy_multiplier = maxf(material.emission_energy_multiplier, 1.4)
				vehicle_lamps.append(material)
			if lamp_lens or window_glass:
				var tint := material.albedo_color
				tint.a *= 0.42 if lamp_lens else 0.74
				material.albedo_color = tint
				material.roughness = 0.075 if lamp_lens else 0.09
				material.metallic = 0.0
				material.metallic_specular = 0.5 if lamp_lens else 0.38
			if kind in ["parts", "rim", "rubber"] and has_colours and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				material.vertex_color_use_as_albedo = true
				material.vertex_color_is_srgb = false
			node.set_surface_override_material(surface, material)
	_textures.clear()
	_texture_roots.clear()


func _track_primary_paint(material: ShaderMaterial, colours: PackedColorArray) -> void:
	for colour in colours:
		if roundi(colour.a * 255.0) == 254:
			painted_surfaces.append(material)
			return


static func _body_material(original: BaseMaterial3D, occlusion: Texture2D, bounds: AABB) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	if original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		if _cutout_shader == null:
			_cutout_shader = Shader.new()
			_cutout_shader.code = BODY_SHADER.code.replace("shader_type spatial;", "shader_type spatial;\n#define VEHICLE_CUTOUT")
		material.shader = _cutout_shader
		material.set_shader_parameter("alpha_cutoff", original.alpha_scissor_threshold)
	else:
		material.shader = BODY_SHADER
	material.set_shader_parameter("front_bounds", Vector3(bounds.position.z, maxf(0.01, bounds.size.z), maxf(0.01, bounds.end.y)))
	material.set_shader_parameter("base_tint", original.albedo_color)
	material.set_shader_parameter("base_metallic", original.metallic)
	material.set_shader_parameter("base_roughness", original.roughness)
	if original.albedo_texture != null:
		material.set_shader_parameter("base_map", original.albedo_texture)
	if occlusion != null:
		material.set_shader_parameter("occlusion_map", occlusion)
	if original.normal_texture != null:
		material.set_shader_parameter("normal_map", original.normal_texture)
		material.set_shader_parameter("use_normal_map", true)
		material.set_shader_parameter("normal_scale", original.normal_scale)
	return material


func _vehicle_occlusion(extras: Dictionary) -> Texture2D:
	for slot: Dictionary in extras.get("textures", []):
		if slot.get("param_hash") != VEHICLE_OCCLUSION_SLOT or slot.get("status") != "ok":
			continue
		var path := str(slot.get("png", ""))
		if not path.begins_with("textures/") or path.contains("..") or path.contains("\\"):
			continue
		if not _textures.has(path):
			_textures[path] = _load_texture(path)
		return _textures[path]
	return null


func _load_texture(relative_path: String) -> Texture2D:
	for root in _texture_roots:
		var path := root.path_join(relative_path)
		if not FileAccess.file_exists(path):
			continue
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			image.generate_mipmaps()
			return ImageTexture.create_from_image(image)
	return null


static func _rim_material(original: BaseMaterial3D, occlusion: Texture2D, extent: AABB, midline: float, has_colours: bool, polished: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = RIM_SHADER
	var right := extent.get_center().x > midline
	material.set_shader_parameter("outward_sign", 1.0 if right else -1.0)
	material.set_shader_parameter("opening_x", extent.end.x if right else extent.position.x)
	material.set_shader_parameter("barrel_width", extent.size.x)
	material.set_shader_parameter("use_vertex_tint", has_colours)
	material.set_shader_parameter("polished", polished)
	material.set_shader_parameter("base_tint", original.albedo_color)
	material.set_shader_parameter("surface_roughness", original.roughness)
	if occlusion != null:
		material.set_shader_parameter("occlusion_map", occlusion)
	if original.normal_texture != null:
		material.set_shader_parameter("normal_map", original.normal_texture)
		material.set_shader_parameter("use_normal_map", true)
		material.set_shader_parameter("normal_scale", original.normal_scale)
	return material


# Use a neutral rotor and hub when the export omits the brake assembly.
static func _add_missing_wheel_backing(node: MeshInstance3D, extent: AABB, midline: float) -> void:
	var center := extent.get_center()
	var radius := minf(extent.size.y, extent.size.z) * 0.5
	if radius < 0.09:
		return
	var outwards := 1.0 if center.x > midline else -1.0
	var outer := extent.end.x if outwards > 0.0 else extent.position.x
	center.x = outer - outwards * extent.size.x * 0.50
	var axle := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), center)
	var rotor := _add_brake_surface(node, axle, radius * 0.75, 0.022, Color("#6b6c6e"), 0.70)
	rotor.name = "PreviewBrakeRotor"
	axle.origin.x += outwards * 0.016
	var hub := _add_brake_surface(node, axle, radius * 0.31, 0.030, Color("#33363a"), 0.38)
	hub.name = "PreviewBrakeHub"


static func _add_brake_surface(node: MeshInstance3D, pose: Transform3D, radius: float, thickness: float, color: Color, metallic: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = thickness
	mesh.radial_segments = 48
	mesh.rings = 0
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.46
	material.metallic = metallic
	var surface := MeshInstance3D.new()
	surface.mesh = mesh
	surface.material_override = material
	node.add_child(surface)
	surface.global_transform = pose
	return surface
