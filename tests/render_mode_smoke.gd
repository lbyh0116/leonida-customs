extends SceneTree

const PreviewStage := preload("res://src/preview_stage.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var preview := PreviewStage.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(preview)
	var capabilities := preview.render_capabilities()
	var args := OS.get_cmdline_user_args()
	if (args.has("--require-rtx") and not capabilities.path_tracing) or (args.has("--require-dlss") and not (capabilities.dlss and capabilities.ray_reconstruction)):
		printerr("Missing required capabilities: ", capabilities)
		quit(1)
		return
	var floor := preview.floor_surface
	var raster_mesh := floor.mesh
	preview.set_quality(8, 0.67)
	var expected_mode := ClassDB.class_get_integer_constant("Viewport", "SCALING_3D_MODE_DLSS") if capabilities.dlss else Viewport.SCALING_3D_MODE_BILINEAR
	if preview.viewport.scaling_3d_mode != expected_mode:
		printerr("Unexpected scaling mode.")
		quit(2)
		return
	preview.set_render_mode(true, 2, capabilities.ray_reconstruction)
	if (floor.mesh != raster_mesh) != capabilities.path_tracing:
		printerr("Render mode selected the wrong floor.")
		quit(3)
		return
	await RenderingServer.frame_post_draw
	preview.set_render_mode(false, 1, false)
	if floor.mesh != raster_mesh or (capabilities.path_tracing and preview.environment.get("pathtracing_enabled")):
		printerr("Unable to return to raster mode.")
		quit(4)
		return
	print(capabilities)
	quit()
