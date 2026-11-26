extends Control

const SixNG := preload("res://src/sixng.gd")
const PreviewStage := preload("res://src/preview_stage.gd")
const MAX_MESSAGE := 1 << 20

var _transport := StreamPeerTCP.new()
var _incoming := PackedByteArray()
var _source: Node
var _stage: SubViewportContainer
var _token := ""
var _connected := false
var _busy := false
var _elapsed := 0.0
var _frame_elapsed := 0.0
var _frame_credit := false
var _path_active := false
var _path_warmup_until := 0
var _path_wait_until := 0


func _ready() -> void:
	var port := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--studio-port="):
			port = argument.get_slice("=", 1).to_int()
		elif argument.begins_with("--studio-token="):
			_token = argument.get_slice("=", 1)
	if port <= 0 or port > 65535 or _token.length() != 48:
		get_tree().quit(2)
		return
	get_window().title = "车辆摄影棚"
	get_window().min_size = Vector2i(1, 1)
	get_window().borderless = true
	get_window().position = Vector2i(-20000, -20000)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_source = SixNG.new()
	add_child(_source)
	_source.progress.connect(func(message: String, percent: float):
		_send({"event": "progress", "message": message, "percent": percent}))
	_stage = PreviewStage.new()
	_stage.external_input = true
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)
	_stage.stretch = false
	_stage.free_view_changed.connect(func(enabled: bool):
		_send({"event": "camera", "free": enabled}))
	if _transport.connect_to_host("127.0.0.1", port) != OK:
		get_tree().quit(2)


func _process(delta: float) -> void:
	_transport.poll()
	var status := _transport.get_status()
	if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		get_tree().quit(2)
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return
	if not _connected:
		_connected = true
		var lighting: Dictionary = _stage.lighting_defaults()
		for key in lighting:
			if lighting[key] is Color:
				lighting[key] = "#" + lighting[key].to_html(false)
		_send({
			"event": "hello", "token": _token, "saved_game": _source.saved_game(),
			"capabilities": _stage.render_capabilities(), "lighting": lighting
		})
	var amount := _transport.get_available_bytes()
	if amount > 0:
		_read(amount)
	_frame_elapsed += delta
	if _frame_credit and _frame_elapsed >= 1.0 / 30.0 and _stage.viewport.size.x > 8:
		_frame_elapsed = 0.0
		if _frame_ready():
			var frame: Image = _stage.viewport.get_texture().get_image()
			if frame != null and not frame.is_empty():
				_frame_credit = false
				_send({"event": "frame", "jpeg": Marshalls.raw_to_base64(frame.save_jpg_to_buffer(0.93))})
	_elapsed += delta
	if _elapsed >= 0.65:
		_elapsed = 0.0
		_send({"event": "timing", "gpu_ms": _stage.gpu_frame_ms(), "fps": Engine.get_frames_per_second()})


func _prepare_path_frame() -> void:
	if _path_active and RenderingServer.has_method("get_rendering_not_ready_reasons"):
		_path_warmup_until = Time.get_ticks_msec() + 250
		_path_wait_until = _path_warmup_until + 20000
		_send({"event": "path_warmup", "active": true})


func _frame_ready() -> bool:
	if _path_wait_until == 0:
		return true
	var now := Time.get_ticks_msec()
	if _path_active and now < _path_wait_until:
		if now < _path_warmup_until or int(RenderingServer.call("get_rendering_not_ready_reasons")) != 0:
			return false
	_path_wait_until = 0
	_send({"event": "path_warmup", "active": false})
	return true


func _read(amount: int) -> void:
	if _incoming.size() + amount > MAX_MESSAGE:
		get_tree().quit(2)
		return
	var data := _transport.get_data(amount)
	if data[0] != OK:
		get_tree().quit(2)
		return
	_incoming.append_array(data[1])
	var newline := _incoming.find(10)
	while newline >= 0:
		var message: Variant = JSON.parse_string(_incoming.slice(0, newline).get_string_from_utf8())
		_incoming = _incoming.slice(newline + 1)
		if message is Dictionary:
			_handle(message)
		newline = _incoming.find(10)


func _send(message: Dictionary) -> void:
	if _connected:
		_transport.put_data((JSON.stringify(message) + "\n").to_utf8_buffer())


func _handle(request: Dictionary) -> void:
	var id := int(request.get("id", 0))
	var command := str(request.get("command", ""))
	var data: Dictionary = request.get("data", {})
	var result := {"ok": true}
	match command:
		"load", "parts", "preview":
			if _busy:
				result = {"ok": false, "error": "正在处理上一项资源请求。"}
			else:
				_busy = true
				result = await _run_asset_command(command, data)
				_busy = false
		"quality":
			_stage.set_quality(int(data.aa), float(data.scale))
			_stage.set_effects(data.ssr, data.ao, data.ssil, data.bloom)
			var path_active: bool = _stage.set_render_mode(data.path_tracing, int(data.samples), data.ray_reconstruction)
			if _path_active != path_active:
				_path_active = path_active
				_prepare_path_frame()
		"lighting":
			var lighting: Dictionary = _stage.lighting_defaults()
			for key in lighting:
				if not data.has(key):
					continue
				lighting[key] = Color.from_string(str(data[key]), lighting[key]) if lighting[key] is Color else float(data[key])
			_stage.set_lighting(lighting)
		"paint":
			_stage.set_paint(int(data.get("finish", 0)), str(data.get("color", "")))
		"lamps":
			_stage.set_vehicle_lamps(bool(data.get("enabled", true)))
		"camera":
			match str(data.action):
				"reset": _stage.reset_camera()
				"rotate": _stage.spinning = data.enabled
				"grid": _stage.set_grid(data.enabled)
				"free":
					_stage.set_free_view(data.enabled)
				_:	_stage.remote_camera_input(str(data.action), data)
		"resize":
			_stage.viewport.size = Vector2i(clampi(int(data.width), 8, 1440), clampi(int(data.height), 8, 960))
		"frame_ack":
			_frame_credit = true
		"shutdown":
			get_tree().quit()
			return
		_:
			result = {"ok": false, "error": "未知的预览器命令。"}
	if id != 0:
		result["id"] = id
		_send(result)


func _run_asset_command(command: String, data: Dictionary) -> Dictionary:
	match command:
		"load":
			var loaded: Dictionary = await _source.load_source(str(data.path))
			if not loaded.get("ok", false):
				return loaded
			_stage.clear_model()
			return {"ok": true, "game": _source.game, "vehicles": _source.vehicles.values(), "unnamed": _source.unnamed}
		"parts":
			return await _source.list_parts(str(data.model))
		"preview":
			var result: Dictionary = await _source.preview(str(data.model), int(data.config), data.parts)
			if not result.get("ok", false):
				return result
			var asset: Dictionary = _stage.show_model(result.path)
			if asset.has("error"):
				return {"ok": false, "error": asset.error}
			_prepare_path_frame()
			var size: Vector3 = asset.size
			return {
				"ok": true, "meshes": asset.meshes, "size": [size.x, size.y, size.z], "paintable": asset.paintable,
				"issues": int(result.asset.get("issues", 0)), "base": result.asset.get("base", false)
			}
	return {"ok": false, "error": "未知的资源命令。"}
