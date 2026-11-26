extends Node

signal progress(message: String, percent: float)

const REQUIRED := ["levels.rpf", "packs.rpf", "data.rpf"]
const SIXNG_FOLDER := "SixNG-v0.11.0-windows-x64"
const PREVIOUS_SIXNG_FOLDER := "SixNG-v0.9.0-windows-x64"
const VEHICLE_CATALOG := preload("res://src/vehicle_catalog.gd")
const VEHICLE_PROGRESS := preload("res://src/vehicle_progress.gd")
const HASH_PATTERN := "^[0-9a-f]{8}$"
const MODEL_PATTERN := "^[a-z0-9_]{1,80}$"

var workspace: String
var decoder: String
var game := ""
var source_dir := ""
var stamp := ""
var vehicles: Dictionary = {}
var unnamed := 0
var _parts: Dictionary = {}
var _stock: Dictionary = {}
var _pid := 0


func _ready() -> void:
	var base := ProjectSettings.globalize_path("res://")
	if not OS.has_feature("editor"):
		base = OS.get_executable_path().get_base_dir()
	workspace = base.path_join("work")
	decoder = OS.get_environment("SIXNG_EXE")
	if decoder.is_empty():
		decoder = base.path_join("tools").path_join(SIXNG_FOLDER).path_join("sixng.exe")
	DirAccess.make_dir_recursive_absolute(workspace)
	OS.set_environment("TEMP", workspace)
	OS.set_environment("TMP", workspace)


func _exit_tree() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)


func saved_game() -> String:
	var saved := _read_dictionary(workspace.path_join("last-source.json"))
	return str(saved.get("game", ""))


func load_source(path: String) -> Dictionary:
	var normalized := path.strip_edges().replace("\\", "/").simplify_path()
	if not normalized.is_absolute_path() or normalized.begins_with("//"):
		return _error("请选择本机磁盘上的游戏目录。")
	var archive_fields: Array = []
	var last_modified := 0
	for name in REQUIRED:
		var archive := normalized.path_join(name)
		var file := FileAccess.open(archive, FileAccess.READ)
		if file == null:
			return _error("找不到 %s。请选择含 levels.rpf、packs.rpf 和 data.rpf 的游戏目录。" % name)
		var header := file.get_buffer(24)
		var modified := FileAccess.get_modified_time(archive)
		if header.size() != 24 or header.slice(0, 4).get_string_from_ascii() != "9FPR":
			return _error("%s 的档案头与 Xbox RPF9 格式不同。" % name)
		archive_fields.append([name, file.get_length(), modified, header.hex_encode()])
		last_modified = maxi(last_modified, modified)
	if not FileAccess.file_exists(decoder):
		return _error("找不到 SixNG。请在项目目录运行 tools/install-sixng.ps1。")
	var id := normalized.replace("/", "\\").to_lower().sha256_text().left(24)
	var folder := workspace.path_join("sources").path_join(id)
	var signature := JSON.stringify([SIXNG_FOLDER, archive_fields]).sha256_text()
	var marker_path := folder.path_join("source.json")
	var previous := _read_dictionary(marker_path)
	var output := folder.path_join("vehicles/vehicles.json")
	var can_use_cache: bool = previous.get("stamp") == signature
	var can_reuse_index: bool = can_use_cache or previous.get("stamp") == JSON.stringify(
		[PREVIOUS_SIXNG_FOLDER, archive_fields]).sha256_text()
	for name in REQUIRED:
		can_reuse_index = can_reuse_index and FileAccess.file_exists(folder.path_join("index/%s.json" % name.get_basename()))
	# A catalog prepared by the same CLI can be used on first launch.
	if previous.is_empty() and FileAccess.file_exists(output):
		can_use_cache = FileAccess.get_modified_time(output) > last_modified
		for name in REQUIRED:
			can_use_cache = can_use_cache and FileAccess.file_exists(folder.path_join("index/%s.json" % name.get_basename()))
	var catalog := _read_dictionary(output) if can_use_cache else {}
	if not catalog.get("vehicles") is Array:
		var create := DirAccess.make_dir_recursive_absolute(folder)
		if create != OK:
			return _error("无法在工作目录写入索引。")
		if not can_reuse_index:
			progress.emit("正在扫描 RPF9 档案", -1.0)
			var indexed := await _run(normalized, folder, ["index", "packs", "data", "levels"])
			if not indexed.get("ok", false):
				return indexed
		progress.emit("正在整理载具目录", -1.0)
		var result := await _run(normalized, folder, ["vehicles", "packs", "--out", folder])
		if not result.get("ok", false):
			return result
		catalog = _read_dictionary(output)
	if not catalog.get("vehicles") is Array:
		return _error("SixNG 没有生成可读的载具目录。")
	var details := await _load_catalog_details(normalized, folder, signature, catalog.vehicles)
	var local_names: Dictionary = details.get("labels", {})
	var handling: Dictionary = details.get("handling", {})
	var progress_cards: Dictionary = details.get("cardsV2", {})
	var records: Dictionary = {}
	var stock: Dictionary = {}
	var unresolved := 0
	for record: Dictionary in catalog.vehicles:
		if not matches_pattern(record.get("model"), MODEL_PATTERN):
			unresolved += 1
			continue
		var info: Dictionary = record.get("model_info") if record.get("model_info") is Dictionary else {}
		var english_name: String = record.get("display_name") if record.get("display_name") is String else record.model
		var english_make: String = record.get("make") if record.get("make") is String else ""
		var name_hash := VEHICLE_CATALOG.label_hash(info.get("gameName"))
		var make_hash := VEHICLE_CATALOG.label_hash(info.get("vehicleMakeName"))
		var handling_hash := VEHICLE_CATALOG.label_hash(info.get("handlingId"))
		var card: Dictionary = progress_cards.get(record.model, {})
		var configurations: Array = []
		var stock_parts: Array[Dictionary] = []
		for config: Dictionary in record.get("configurations", []):
			var colour: Variant = config.get("colour")
			configurations.append({
				"color": str(colour.get("srgb_if_linear", colour.get("rgb", ""))) if colour is Dictionary else "",
				"count": config.get("parts", []).size()
			})
			var part_keys := {}
			for part: Variant in config.get("parts", []):
				if part is String:
					part_keys[VEHICLE_CATALOG.part_hash(part)] = true
			stock_parts.append(part_keys)
		stock[record.model] = stock_parts
		records[record.model] = {
			"id": record.model,
			"name": local_names.get(name_hash, english_name),
			"make": local_names.get(make_hash, english_make),
			"englishName": english_name,
			"englishMake": english_make,
			"category": VEHICLE_CATALOG.category(record.model, info, card.get("category", "")),
			"configurations": configurations
		}
		records[record.model].merge(handling.get(handling_hash, {}))
		records[record.model].merge(card)
		for field in ["gears", "roadRating", "dirtRating"]:
			if records[record.model].has(field):
				records[record.model][field] = int(records[record.model][field])
	if records.is_empty():
		return _error("目录中没有已恢复模型名称的载具。")
	_write_dictionary(marker_path, {"stamp": signature})
	_write_dictionary(workspace.path_join("last-source.json"), {"game": normalized})
	game = normalized
	source_dir = folder
	stamp = signature
	vehicles = records
	unnamed = unresolved
	_parts.clear()
	_stock = stock
	return {"ok": true}


func list_parts(model: String) -> Dictionary:
	if not vehicles.has(model):
		return _error("本地目录中找不到该车型。")
	if _parts.has(model):
		return {"ok": true, "parts": _parts[model]}
	var list := await _run(game, source_dir, ["vehicle", model, "--list-parts", "--data", _catalog()])
	if not list.get("ok", false):
		return list
	var available: Array[Dictionary] = []
	for part: Dictionary in list.get("parts", []):
		if not matches_pattern(part.get("part"), HASH_PATTERN) or not part.get("slot") is String:
			continue
		var names := PackedStringArray()
		for asset: Variant in part.get("models", []):
			if asset is String:
				names.append(asset)
		if names.is_empty():
			continue
		var stock_configs: Array[int] = []
		var configurations: Array = _stock.get(model, [])
		for index in configurations.size():
			if configurations[index].has(part.part):
				stock_configs.append(index)
		available.append({
			"id": part.part, "slot": part.slot, "slot_name": part.slot_name,
			"label": " · ".join(names), "stockConfigs": stock_configs
		})
	_parts[model] = available
	return {"ok": true, "parts": available}


func preview(model: String, config: int, selection: Array) -> Dictionary:
	if not vehicles.has(model):
		return _error("本地目录中找不到该车型。")
	var cfgs: Array = vehicles[model].configurations
	if cfgs.is_empty() and config == 0 and selection.is_empty():
		return await _preview_base(model)
	if config < 0 or config >= cfgs.size():
		return _error("该车型没有这个原厂配置。")
	if not selection.is_empty():
		var parts := await list_parts(model)
		if not parts.get("ok", false):
			return parts
		var slots: Dictionary = {}
		for id: Variant in selection:
			var slot := ""
			for part: Dictionary in parts.parts:
				if part.id == id:
					slot = part.slot
					break
			if slot.is_empty() or slots.has(slot):
				return _error("配件不可用，或多个配件占用了同一安装位置。")
			slots[slot] = true
	var picks := selection.duplicate()
	picks.sort()
	var key := JSON.stringify([stamp, "warnings-v1", model, config, picks]).sha256_text().left(24)
	var folder := source_dir.path_join("models").path_join(key)
	var path := folder.path_join("vehicle.glb")
	var info_path := folder.path_join("preview.json")
	var metadata := _read_dictionary(info_path)
	if not metadata.is_empty() and FileAccess.file_exists(path):
		return {"ok": true, "path": path, "asset": metadata}
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return _error("无法创建预览缓存目录。")
	var building := folder.path_join("vehicle-%s.glb" % OS.get_process_id())
	var args := ["vehicle", model, "--config", str(config), "--data", _catalog(), "--out", building, "--tex", "png"]
	if not picks.is_empty():
		args.append_array(["--with", ",".join(picks)])
	var result := await _run(game, source_dir, args)
	if not result.get("ok", false):
		return result
	if DirAccess.rename_absolute(building, path) != OK:
		return _error("无法保存整车 GLB 缓存。")
	var exported: Dictionary = result.get("result", {})
	var requested_warnings: Array[String] = []
	for field in ["not_fitted", "left_out"]:
		for warning: Variant in exported.get(field, []):
			if not warning is String:
				continue
			for pick: String in picks:
				if warning.contains(pick):
					requested_warnings.append(warning)
					break
	metadata = {
		"requestedWarnings": requested_warnings,
		"pieces": exported.get("pieces", []).size(),
		"wheels": exported.get("wheels"),
		"issues": exported.get("left_out", []).size() + exported.get("not_fitted", []).size() + exported.get("warnings", []).size()
	}
	_write_dictionary(info_path, metadata)
	return {"ok": true, "path": path, "asset": metadata}


func _preview_base(model: String) -> Dictionary:
	var key := JSON.stringify([stamp, "base", model]).sha256_text().left(24)
	var folder := source_dir.path_join("models").path_join(key)
	var exported := folder.path_join("models/levels")
	for suffix in ["_hi", "_mid", ""]:
		var asset_name: String = model + suffix
		var cached := _find_base_glb(exported, asset_name)
		if not cached.is_empty():
			return {"ok": true, "path": cached, "asset": {"issues": 0, "base": true}}
		progress.emit("正在读取 %s 的基础模型" % model, -1.0)
		var result := await _run(game, source_dir, [
			"extract", "levels", "--name", "^" + asset_name + "$", "--limit", "1", "--out", folder
		])
		if not result.get("ok", false):
			return result
		var path := _find_base_glb(exported, asset_name)
		if not path.is_empty():
			return {"ok": true, "path": path, "asset": {"issues": int(result.get("warning_count", 0)), "base": true}}
	return _error("找不到此车型可渲染的基础模型。")


func _find_base_glb(folder: String, asset_name: String) -> String:
	var dir := DirAccess.open(folder)
	if dir == null:
		return ""
	var pattern := RegEx.create_from_string("^%s_[0-9a-f]+$" % asset_name)
	for child: String in dir.get_directories():
		if pattern.search(child) != null:
			var path := folder.path_join(child).path_join("model.glb")
			if FileAccess.file_exists(path):
				return path
	return ""


func _catalog() -> String:
	return source_dir.path_join("vehicles/vehicles.json")


func _run(path: String, folder: String, args: Array) -> Dictionary:
	var flags := PackedStringArray(["--game", path, "--work", folder])
	flags.append_array(PackedStringArray(args))
	var process := OS.execute_with_pipe(decoder, flags, false)
	if process.is_empty():
		return _error("无法启动 SixNG。")
	_pid = int(process.pid)
	var output := PackedByteArray()
	var errors := PackedByteArray()
	var last_error := ""
	while true:
		var running := OS.is_process_running(_pid)
		output.append_array(_read_pipe(process.stdio))
		errors.append_array(_read_pipe(process.stderr))
		var newline := errors.find(10)
		while newline >= 0:
			var line := errors.slice(0, newline).get_string_from_utf8().strip_edges()
			errors = errors.slice(newline + 1)
			var event: Variant = JSON.parse_string(line)
			if event is Dictionary and event.get("event") == "progress":
				var stage := str(event.get("stage", ""))
				progress.emit(stage.replace(":names", " · 恢复名称").replace(":scan", " · 扫描档案"), float(event.get("pct", -1)))
			elif not line.is_empty():
				last_error = str(event.get("error", line)) if event is Dictionary else line
			newline = errors.find(10)
		if not running:
			break
		await get_tree().create_timer(0.08).timeout
	var exit_code := OS.get_process_exit_code(_pid)
	_pid = 0
	var result: Variant = JSON.parse_string(output.get_string_from_utf8().strip_edges())
	if result is Dictionary and result.get("ok", false) and exit_code <= 0:
		return result
	if result is Dictionary and result.has("error"):
		last_error = str(result.error)
	if last_error.is_empty():
		last_error = errors.get_string_from_utf8().strip_edges()
	if last_error.is_empty():
		last_error = "SixNG 未返回有效结果（退出码 %s）。" % exit_code
	return _error(last_error)


func _read_pipe(pipe: FileAccess) -> PackedByteArray:
	var data := PackedByteArray()
	while true:
		var chunk := pipe.get_buffer(8192)
		data.append_array(chunk)
		if chunk.size() < 8192:
			break
	return data


func _load_catalog_details(path: String, folder: String, signature: String, records: Array) -> Dictionary:
	var cache_path := folder.path_join("catalog-details-v1.json")
	var previous := _read_dictionary(cache_path)
	if previous.get("stamp") != signature:
		previous = {"stamp": signature}
	var ids := VEHICLE_CATALOG.label_ids(records)
	if not ids.is_empty() and not previous.has("labels"):
		progress.emit("正在读取游戏简中车型名称", -1.0)
		var result := await _run(path, folder, ["text", "data", "--plain", "--label", ",".join(ids), "--quiet"])
		var labels := VEHICLE_CATALOG.simplified_labels(result)
		if not labels.is_empty():
			previous.labels = labels
	if not previous.has("handling"):
		progress.emit("正在读取本地车辆参数", -1.0)
		var result := await _run(path, folder, ["handling", "--out", folder, "--quiet"])
		if result.get("ok", false):
			var handling := _read_dictionary(folder.path_join("pso/handling.json"))
			var values := VEHICLE_CATALOG.handling_data(handling.get("records", []))
			if not values.is_empty():
				previous.handling = values
	if not previous.has("cardsV2"):
		progress.emit("正在读取载具图鉴与性能数据", -1.0)
		var result := await _run(path, folder, ["rbf", "data", "--out", folder, "--quiet"])
		if result.get("ok", false):
			var cards := VEHICLE_PROGRESS.read_directory(folder.path_join("rbf/data"))
			if not cards.is_empty():
				previous.cardsV2 = cards
	_write_dictionary(cache_path, previous)
	return previous


static func matches_pattern(value: Variant, pattern: String) -> bool:
	return value is String and RegEx.create_from_string(pattern).search(value) != null


static func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


static func _write_dictionary(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value))


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
