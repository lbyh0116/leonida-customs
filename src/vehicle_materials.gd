extends RefCounted

const RIM_SHADER := preload("res://src/vehicle_rim.gdshader")
const VEHICLE_OCCLUSION_SLOT := "2bb2ede8"

var _texture_roots: PackedStringArray
var _textures: Dictionary = {}


func apply(geometries: Array[Node], state: GLTFState, path: String, vehicle_midline: float) -> void:
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
			var parked_lamp := material_class == "emissive" and (
				family.contains("vehicle lamps") or str(extras.get("shader_name", "")).begins_with("standard_vehicle_emissive"))
			var lamp_lens := material_class == "glass" and family.contains("vehicle lamp")
			var occlusion := _vehicle_occlusion(extras)
			if kind not in ["parts", "rim", "rubber"] and not parked_lamp and not lamp_lens and occlusion == null:
				continue
			var colours: Variant = mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			var has_colours: bool = colours is PackedColorArray and not colours.is_empty()
			var wheel: String = wheel_nodes.get(node, "")
			if kind == "rim" and wheel_extents.has(wheel):
				var wheel_extent: AABB = wheel_extents[wheel]
				# A centered wheel can be exposed on both sides, as on motorcycles.
				if absf(wheel_extent.get_center().x - vehicle_midline) > 0.25 and wheel_extent.size.x > 0.025:
					node.set_surface_override_material(surface, _rim_material(original, occlusion, wheel_extent, vehicle_midline, has_colours))
					if not wheels_with_brakes.has(wheel) and not backed_wheels.has(wheel):
						backed_wheels[wheel] = true
						_add_missing_wheel_backing(node, wheel_extent, vehicle_midline)
					continue
			var material := original.duplicate() as BaseMaterial3D
			if occlusion != null:
				# SixNG documents the blue channel as occlusion on both
				# the diffuse and specular sides of this vehicle layer.
				material.ao_enabled = true
				material.ao_texture = occlusion
				material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
				material.ao_light_affect = 0.85
			if parked_lamp:
				# glTF exports the emission texture but has no lamp power
				# state. The studio previews the vehicle with the lamps off.
				material.emission_enabled = false
			if lamp_lens:
				var tint := material.albedo_color
				tint.a *= 0.42
				material.albedo_color = tint
				material.roughness = 0.075
				material.metallic = 0.0
				material.metallic_specular = 0.5
			if kind in ["parts", "rim", "rubber"] and has_colours and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				material.vertex_color_use_as_albedo = true
				material.vertex_color_is_srgb = false
				if kind == "parts":
					_apply_surface_finish(material, colours)
			node.set_surface_override_material(surface, material)
	_textures.clear()
	_texture_roots.clear()


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


static func _rim_material(original: BaseMaterial3D, occlusion: Texture2D, extent: AABB, midline: float, has_colours: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = RIM_SHADER
	var right := extent.get_center().x > midline
	material.set_shader_parameter("outward_sign", 1.0 if right else -1.0)
	material.set_shader_parameter("opening_x", extent.end.x if right else extent.position.x)
	material.set_shader_parameter("barrel_width", extent.size.x)
	material.set_shader_parameter("use_vertex_tint", has_colours)
	material.set_shader_parameter("base_tint", original.albedo_color)
	material.set_shader_parameter("surface_roughness", original.roughness)
	if occlusion != null:
		material.set_shader_parameter("occlusion_map", occlusion)
	if original.normal_texture != null:
		material.set_shader_parameter("normal_map", original.normal_texture)
		material.set_shader_parameter("use_normal_map", true)
		material.set_shader_parameter("normal_scale", original.normal_scale)
	return material


# With a missing disc or drum, the floor can be visible straight through
# the rim. A recessed, matte backing represents the closed wheel cavity.
static func _add_missing_wheel_backing(node: MeshInstance3D, extent: AABB, midline: float) -> void:
	var center := extent.get_center()
	var radius := minf(extent.size.y, extent.size.z) * 0.5
	if radius < 0.09:
		return
	var outwards := 1.0 if center.x > midline else -1.0
	var outer := extent.end.x if outwards > 0.0 else extent.position.x
	center.x = outer - outwards * extent.size.x * 0.64

	var backing_mesh := CylinderMesh.new()
	backing_mesh.top_radius = radius * 0.94
	backing_mesh.bottom_radius = backing_mesh.top_radius
	backing_mesh.height = 0.012
	backing_mesh.radial_segments = 32
	backing_mesh.rings = 0
	var backing_material := StandardMaterial3D.new()
	backing_material.albedo_color = Color("#101014")
	backing_material.roughness = 0.95
	backing_material.metallic_specular = 0.1
	var backing := MeshInstance3D.new()
	backing.name = "WheelCavityBacking"
	backing.mesh = backing_mesh
	backing.material_override = backing_material
	node.add_child(backing)
	backing.global_transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), center)


# SixNG puts paint and part colours in COLOR_0. Its alpha channel marks
# primary paint or stores the surface finish, so it is not opacity.
static func _apply_surface_finish(material: BaseMaterial3D, colours: PackedColorArray) -> void:
	var sample_count := mini(colours.size(), 96)
	var step := maxi(1, colours.size() / sample_count)
	var codes: Dictionary = {}
	for i in range(sample_count):
		var code := roundi(colours[i * step].a * 255.0)
		codes[code] = int(codes.get(code, 0)) + 1
	for code: int in codes:
		if int(codes[code]) * 5 < sample_count * 4:
			continue
		if code == 254:
			material.albedo_texture = null
			material.metallic = 0.43
			material.roughness = 0.34
			material.clearcoat_enabled = true
			material.clearcoat = 0.57
			material.clearcoat_roughness = 0.31
		elif code < 200:
			material.metallic = floorf(code / 50.0) / 3.0
			material.roughness = clampf((code % 50) / 49.0, 0.05, 1.0)
		return
