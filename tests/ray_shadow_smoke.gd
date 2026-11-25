extends SceneTree

const HardwareShadow := preload("res://src/ray_shadow.gd")
var _shadow := HardwareShadow.new()


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	if int(Engine.get_version_info().minor) < 8 or not HardwareShadow.is_supported():
		print("Skipped: this smoke test needs Godot 4.8 with a Vulkan ray tracing GPU.")
		quit(77)
		return
	create_timer(12.0).timeout.connect(func(): quit(2))
	var vertices := PackedVector3Array([Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(0, 1, 1)])
	var indices := PackedInt32Array([0, 1, 2])
	var parameters := PackedFloat32Array([-2, -2, 4, 4, 0, 1, 0, 0.01, 4, 12, 0, 0])
	_shadow.prepare(vertices, indices, parameters, _check_pixels)


func _check_pixels(ok: bool) -> void:
	if not ok:
		printerr("Could not initialize hardware ray tracing.")
		quit(1)
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var pixels := _shadow.texture.get_image()
	var center := HardwareShadow.MAP_SIZE / 2
	var blocked := pixels.get_pixel(center, center).r
	var open_floor := pixels.get_pixel(40, 40).r
	_shadow.release()
	print("Blocked ray: %.3f, unblocked ray: %.3f" % [blocked, open_floor])
	quit(0 if blocked > 0.9 and open_floor < 0.1 else 1)
