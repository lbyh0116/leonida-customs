extends RefCounted


static func fit(root: Node3D, geometry: Array[Node], source: Dictionary) -> Dictionary:
	var rigs := root.find_children("*", "Skeleton3D", true, false)
	var by_rig := {}
	for rig: Skeleton3D in rigs:
		var links := {}
		for index in rig.get_bone_count():
			var bone := str(rig.get_bone_name(index)).to_lower()
			if bone.begins_with("tracks_skinbone_"):
				links[index] = bone.get_slice("_", 2)
			elif bone.begins_with("track_") and bone.get_slice("_", 2).is_valid_int():
				links[index] = bone.get_slice("_", 1)
		if not links.is_empty():
			by_rig[rig] = links
	if by_rig.is_empty():
		return {}

	var tracks := _track_extents(geometry, by_rig)
	if tracks.is_empty():
		return {}
	var fitted := {}
	for node: MeshInstance3D in geometry:
		var name := str(node.name).to_lower()
		if node.mesh == null or not name.begins_with("rim_") or not name.contains("_wheel_"):
			continue
		var bounds: AABB = node.global_transform * node.get_aabb()
		var band := _closest_track(tracks, bounds.get_center())
		if band.size.x <= 0.0 or bounds.size.x <= 0.0:
			continue
		var width := minf(bounds.size.x, band.size.x * 0.94)
		var scale_x := width / bounds.size.x
		var center := bounds.get_center()
		var radius := maxf(bounds.size.y, bounds.size.z) * 0.5
		var radial_scale := _track_clearance(band, center, radius) / radius if radius > 0.0 else 1.0
		var basis := Basis.from_scale(Vector3(scale_x, radial_scale, radial_scale))
		var target := Vector3(band.get_center().x, center.y, center.z)
		# SixNG bakes the wheel in chassis coordinates. Remove its static bind
		# before correcting the disc width, so the skeleton cannot cancel the offset.
		node.skin = null
		node.skeleton = NodePath()
		node.global_transform = Transform3D(basis, target - basis * center) * node.global_transform
		fitted[node] = true

	if source.has("mounts"):
		_add_missing_wheels(root, tracks, source, geometry)
	return fitted


static func _track_extents(geometry: Array[Node], by_rig: Dictionary) -> Dictionary:
	var tracks := {}
	var bind_groups := {}
	for node: MeshInstance3D in geometry:
		if node.mesh == null or node.skin == null:
			continue
		var rig := node.get_node_or_null(node.skeleton) as Skeleton3D
		if not by_rig.has(rig):
			continue
		var skin := node.skin
		if not bind_groups.has(skin):
			var links: Dictionary = by_rig[rig]
			var bind_to_group := {}
			for index in skin.get_bind_count():
				var bone := skin.get_bind_bone(index)
				if bone < 0:
					bone = rig.find_bone(skin.get_bind_name(index))
				if links.has(bone):
					bind_to_group[index] = links[bone]
			bind_groups[skin] = bind_to_group
		var groups: Dictionary = bind_groups[skin]
		if groups.is_empty():
			continue
		var pose := node.global_transform
		for surface in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(surface)
			var bones: Variant = arrays[Mesh.ARRAY_BONES]
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if bones == null or bones.is_empty() or points.is_empty():
				continue
			var stride: int = bones.size() / points.size()
			for index in points.size():
				var group: String = groups.get(bones[index * stride], "")
				if group.is_empty():
					continue
				var point := pose * points[index]
				tracks[group] = tracks[group].expand(point) if tracks.has(group) else AABB(point, Vector3.ZERO)
	return tracks


static func _closest_track(tracks: Dictionary, center: Vector3) -> AABB:
	var nearest := AABB()
	var best := INF
	for band: AABB in tracks.values():
		if center.z < band.position.z or center.z > band.end.z or band.size.x < 0.16:
			continue
		var offset := absf(center.x - band.get_center().x)
		if offset < best and offset < band.size.x * 0.72:
			best = offset
			nearest = band
	return nearest


static func _track_clearance(band: AABB, center: Vector3, radius: float) -> float:
	var vertical := minf(center.y - band.position.y, band.end.y - center.y)
	var longitudinal := minf(center.z - band.position.z, band.end.z - center.z)
	var limit := minf(vertical, longitudinal)
	return minf(radius, limit * 0.99) if limit > 0.0 else radius


static func _add_missing_wheels(root: Node3D, tracks: Dictionary, source: Dictionary, geometry: Array[Node]) -> void:
	var meshes := {}
	for slot in ["rims_front", "rims_rear"]:
		var path := str(source.get(slot, ""))
		if path.is_empty():
			continue
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		if gltf.append_from_file(path, state) != OK:
			continue
		var asset := gltf.generate_scene(state)
		if asset == null:
			continue
		var pieces: Array[Mesh] = []
		for part: MeshInstance3D in asset.find_children("*", "MeshInstance3D", true, false):
			if part.mesh != null:
				pieces.append(part.mesh)
		asset.free()
		meshes[slot] = pieces
	var front := INF
	for mount: Dictionary in source.mounts:
		if mount.get("centre") is Array and mount.centre.size() == 3:
			front = minf(front, -float(mount.centre[1]))
	for mount: Dictionary in source.mounts:
		if not mount.get("centre") is Array or mount.centre.size() != 3 or mount.get("radius") == null or mount.get("half_width") == null:
			continue
		var center := Vector3(mount.centre[0], mount.centre[2], -mount.centre[1])
		var band := _closest_track(tracks, center)
		if band.size.x <= 0.0:
			continue
		var width := minf(float(mount.half_width) * 2.0, band.size.x * 0.94)
		var radius := _track_clearance(band, center, float(mount.radius))
		var slot := "rims_front" if center.z <= front + 0.28 else "rims_rear"
		for piece: Mesh in meshes.get(slot, []):
			var bounds := piece.get_aabb()
			var diameter := maxf(bounds.size.y, bounds.size.z)
			if minf(bounds.size.x, diameter) <= 0.0:
				continue
			var radial_scale := radius * 2.0 / diameter
			var signed_width := width if center.x < 0.0 else -width
			var basis := Basis.from_scale(Vector3(signed_width / bounds.size.x, radial_scale, radial_scale))
			var wheel := MeshInstance3D.new()
			wheel.name = "TrackWheel_" + str(mount.bone)
			wheel.mesh = piece
			wheel.transform = Transform3D(basis, center - basis * bounds.get_center())
			root.add_child(wheel)
			geometry.append(wheel)
