extends Control

const SixNG := preload("res://src/sixng.gd")
const PreviewStage := preload("res://src/preview_stage.gd")
const RenderControls := preload("res://src/render_controls.gd")
const CODE_PREFIX := "VI1."

var source: Node
var preview_stage: SubViewportContainer
var open_button: Button
var source_label: Label
var search: LineEdit
var categories: OptionButton
var list: ItemList
var count_label: Label
var catalog_note: Label
var view_type: Label
var view_title: Label
var view_meta: Label
var empty_view: Label
var reset_button: Button
var spin_button: Button
var free_button: Button
var configs: OptionButton
var parts_button: Button
var part_hint: Label
var part_box: VBoxContainer
var apply_button: Button
var copy_button: Button
var import_button: Button
var status_label: Label
var progress_bar: ProgressBar
var render_stats: Label
var picker: FileDialog
var import_dialog: ConfirmationDialog
var code_input: TextEdit

var busy := false
var selected := ""
var shown: Dictionary = {}
var parts_loaded := false
var base_only := false
var part_controls: Array[OptionButton] = []


func _ready() -> void:
	theme = _studio_theme()
	source = SixNG.new()
	add_child(source)
	source.progress.connect(_status)
	_build_ui()
	_set_busy(false)
	var game: String = source.saved_game()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game="):
			game = arg.trim_prefix("--game=")
	if not game.is_empty():
		_open_game.call_deferred(game)


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#101014")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var page := MarginContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		page.add_theme_constant_override("margin_" + edge, 17)
	add_child(page)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	page.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 13)
	column.add_child(header)
	var monogram := PanelContainer.new()
	monogram.custom_minimum_size = Vector2(49, 49)
	monogram.add_theme_stylebox_override("panel", _box("#f6b2cf", "#f6b2cf", 13, 0, 0))
	header.add_child(monogram)
	var mark := _label("VI", 24, "#251820")
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	monogram.add_child(mark)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 0)
	header.add_child(heading)
	heading.add_child(_label("Leonida Customs", 22))
	heading.add_child(_label("VEHICLE STUDIO", 11, "#b9a6b8"))
	source_label = _label("未连接游戏目录", 13, "#a8a5b3")
	source_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(source_label)
	open_button = _button("打开游戏目录")
	header.add_child(open_button)
	open_button.pressed.connect(func(): picker.popup_centered_ratio(0.72))

	var panels := HBoxContainer.new()
	panels.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panels.add_theme_constant_override("separation", 12)
	column.add_child(panels)
	var catalog := _panel_column(panels, 220)
	var catalog_header := HBoxContainer.new()
	catalog.add_child(catalog_header)
	var catalog_title := _label("载具库", 17)
	catalog_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_header.add_child(catalog_title)
	count_label = _label("0", 13, "#ada9b7")
	catalog_header.add_child(count_label)
	search = LineEdit.new()
	search.placeholder_text = "搜索名称、厂牌或模型"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text: String): _filter())
	catalog.add_child(search)
	categories = OptionButton.new()
	categories.add_item("全部类别")
	categories.item_selected.connect(func(_i: int): _filter())
	catalog.add_child(categories)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(_on_selected)
	catalog.add_child(list)
	catalog_note = _label("打开游戏目录以读取载具。", 12, "#a8a5b3")
	catalog_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	catalog.add_child(catalog_note)

	var view := PanelContainer.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_theme_stylebox_override("panel", _box("#242330", "#363442", 0, 1, 1))
	panels.add_child(view)
	var layered := Control.new()
	layered.custom_minimum_size.x = 290
	view.add_child(layered)
	preview_stage = PreviewStage.new()
	preview_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layered.add_child(preview_stage)
	var view_overlay := MarginContainer.new()
	view_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		view_overlay.add_theme_constant_override("margin_" + edge, 15)
	layered.add_child(view_overlay)
	var overlays := VBoxContainer.new()
	overlays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_overlay.add_child(overlays)
	view_type = _label("三维预览", 13, "#914155")
	overlays.add_child(view_type)
	view_title = _label("载具预览", 31, "#201f28")
	view_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	overlays.add_child(view_title)
	view_meta = _label("", 13, "#3d4354")
	overlays.add_child(view_meta)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlays.add_child(center)
	empty_view = _label("打开游戏目录，在左侧选择载具。", 15, "#292d3a")
	empty_view.add_theme_color_override("font_shadow_color", Color.WHITE)
	empty_view.add_theme_constant_override("shadow_offset_y", 1)
	center.add_child(empty_view)
	var camera_bar := HBoxContainer.new()
	camera_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camera_bar.add_theme_constant_override("separation", 7)
	overlays.add_child(camera_bar)
	reset_button = _button("重置视角")
	reset_button.pressed.connect(preview_stage.reset_camera)
	camera_bar.add_child(reset_button)
	spin_button = _button("自动旋转")
	spin_button.toggle_mode = true
	spin_button.toggled.connect(func(enabled: bool): preview_stage.spinning = enabled)
	camera_bar.add_child(spin_button)
	var grid_button := _button("网格")
	grid_button.toggle_mode = true
	grid_button.toggled.connect(preview_stage.set_grid)
	camera_bar.add_child(grid_button)
	free_button = _button("自由视角")
	free_button.toggle_mode = true
	free_button.toggled.connect(preview_stage.set_free_view)
	camera_bar.add_child(free_button)
	var instructions := _label("左键旋转  ·  右键平移  ·  滚轮缩放", 12, "#303747")
	instructions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	instructions.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	instructions.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	camera_bar.add_child(instructions)
	preview_stage.free_view_changed.connect(func(active: bool):
		free_button.set_pressed_no_signal(active)
		instructions.text = "左键拖动环视 · WASD 移动 · Q/E 升降 · Esc 退出" if active else "左键旋转 · 右键平移 · 滚轮缩放")

	var controls_panel := _panel_column(panels, 267)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls_panel.add_child(tabs)
	var side := VBoxContainer.new()
	side.name = "预览配置"
	tabs.add_child(side)
	var render_controls := RenderControls.new()
	render_controls.name = "渲染设置"
	tabs.add_child(render_controls)
	render_controls.attach(preview_stage)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)
	var settings := VBoxContainer.new()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_theme_constant_override("separation", 10)
	scroll.add_child(settings)
	settings.add_child(HSeparator.new())
	settings.add_child(_label("原厂配置", 14))
	configs = OptionButton.new()
	configs.fit_to_longest_item = false
	settings.add_child(configs)
	settings.add_child(HSeparator.new())
	var part_header := HBoxContainer.new()
	settings.add_child(part_header)
	var part_title := _label("改装配件", 14)
	part_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	part_header.add_child(part_title)
	parts_button = _button("读取配件")
	parts_button.pressed.connect(_inspect_parts)
	part_header.add_child(parts_button)
	part_hint = _label("选择载具后可查看安装槽。", 12, "#ada9b7")
	part_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings.add_child(part_hint)
	part_box = VBoxContainer.new()
	part_box.add_theme_constant_override("separation", 8)
	settings.add_child(part_box)
	apply_button = _button("更新预览", true)
	apply_button.pressed.connect(_apply_current)
	side.add_child(apply_button)
	var share := HBoxContainer.new()
	side.add_child(share)
	copy_button = _button("复制改车码")
	copy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_button.pressed.connect(_copy_code)
	share.add_child(copy_button)
	import_button = _button("导入改车码")
	import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_button.pressed.connect(_open_import)
	share.add_child(import_button)

	var footer := HBoxContainer.new()
	column.add_child(footer)
	status_label = _label("等待连接游戏目录", 13, "#aeabb9")
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(status_label)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(155, 15)
	progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	progress_bar.show_percentage = false
	progress_bar.hide()
	footer.add_child(progress_bar)
	render_stats = _label("", 12, "#aeabb9")
	footer.add_child(render_stats)

	picker = FileDialog.new()
	picker.title = "选择 GTA VI Xbox 游戏目录"
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	picker.use_native_dialog = true
	picker.dir_selected.connect(_open_game)
	add_child(picker)
	import_dialog = ConfirmationDialog.new()
	import_dialog.title = "导入改车码"
	import_dialog.get_ok_button().text = "应用"
	import_dialog.get_cancel_button().text = "取消"
	code_input = TextEdit.new()
	code_input.placeholder_text = "粘贴 VI1. 开头的改车码"
	code_input.custom_minimum_size = Vector2(430, 110)
	import_dialog.add_child(code_input)
	import_dialog.confirmed.connect(_import_code)
	add_child(import_dialog)


func _panel_column(parent: HBoxContainer, width: int) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	panel.add_child(box)
	return box


func _label(text: String, font_size: int, color := "#efedf4") -> Label:
	var value := Label.new()
	value.text = text
	value.add_theme_font_size_override("font_size", font_size)
	value.add_theme_color_override("font_color", Color(color))
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return value


func _button(text: String, accent := false) -> Button:
	var button := Button.new()
	button.text = text
	if accent:
		button.add_theme_stylebox_override("normal", _box("#f6b2cf", "#f6b2cf", 7, 1, 8))
		button.add_theme_stylebox_override("hover", _box("#ffd1e3", "#ffd1e3", 7, 1, 8))
		button.add_theme_stylebox_override("pressed", _box("#d992b0", "#d992b0", 7, 1, 8))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, Color("#281922"))
	return button


func _box(background: String, edge: String, radius: int, border: int, pad: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(background)
	style.border_color = Color(edge)
	style.set_border_width_all(border)
	style.set_corner_radius_all(radius)
	style.content_margin_left = pad
	style.content_margin_right = pad
	style.content_margin_top = pad
	style.content_margin_bottom = pad
	return style


func _studio_theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Segoe UI"])
	result.default_font = font
	result.default_font_size = 14
	result.set_stylebox("panel", "PanelContainer", _box("#19191f", "#34343d", 12, 1, 12))
	for control in ["Button", "OptionButton"]:
		result.set_stylebox("normal", control, _box("#26262f", "#41404b", 7, 1, 7))
		result.set_stylebox("hover", control, _box("#32323e", "#5e596d", 7, 1, 7))
		result.set_stylebox("pressed", control, _box("#493245", "#815b75", 7, 1, 7))
		result.set_stylebox("disabled", control, _box("#1d1d24", "#36353e", 7, 1, 7))
	var focus := _box("#00000000", "#f3b3d3", 7, 1, 0)
	for control in ["Button", "OptionButton", "LineEdit", "ItemList", "TextEdit"]:
		result.set_stylebox("focus", control, focus)
	for control in ["LineEdit", "TextEdit"]:
		result.set_stylebox("normal", control, _box("#121218", "#36363f", 7, 1, 7))
	result.set_stylebox("panel", "ItemList", _box("#15151b", "#303039", 7, 1, 4))
	for state in ["selected", "selected_focus"]:
		result.set_stylebox(state, "ItemList", _box("#3e2b3f", "#694a64", 5, 1, 5))
	result.set_stylebox("hovered", "ItemList", _box("#25252e", "#25252e", 5, 1, 5))
	result.set_constant("v_separation", "ItemList", 10)
	result.set_stylebox("fill", "ProgressBar", _box("#eea1c1", "#eea1c1", 4, 0, 0))
	result.set_stylebox("background", "ProgressBar", _box("#30303a", "#30303a", 4, 0, 0))
	return result


func _open_game(path: String) -> void:
	if busy:
		return
	_set_busy(true)
	_status("正在检查游戏目录…")
	await get_tree().process_frame
	var result: Dictionary = await source.load_source(path)
	_set_busy(false)
	if not result.get("ok", false):
		_failure(result.error)
		return
	picker.current_dir = source.game
	source_label.text = "●  Xbox RPF9  ·  本地只读"
	source_label.add_theme_color_override("font_color", Color("#a3d5b5"))
	source_label.tooltip_text = source.game
	selected = ""
	shown.clear()
	preview_stage.clear_model()
	search.clear()
	_rebuild_categories()
	_filter()
	catalog_note.text = "另有 %s 条记录未恢复模型名称。" % source.unnamed if source.unnamed else "资源来自本机游戏目录。"
	_status("已读取 %s 辆命名载具。" % source.vehicles.size())
	var first := "comet7" if source.vehicles.has("comet7") else ""
	if first.is_empty():
		for id: String in source.vehicles.keys():
			if not source.vehicles[id].configurations.is_empty():
				first = id
				break
	if not first.is_empty():
		_select(first)
		await _render(0, [])


func _rebuild_categories() -> void:
	categories.clear()
	categories.add_item("全部类别")
	var values: Dictionary = {}
	for record: Dictionary in source.vehicles.values():
		values[record.category] = true
	var ordered := values.keys()
	ordered.sort()
	for category: String in ordered:
		categories.add_item(category)


func _filter() -> void:
	if not is_instance_valid(list):
		return
	var query := search.text.strip_edges().to_lower()
	var category := categories.get_item_text(categories.selected) if categories.selected > 0 else ""
	var records: Array = source.vehicles.values()
	records.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	list.clear()
	for vehicle: Dictionary in records:
		if not category.is_empty() and category != vehicle.category:
			continue
		var searchable := "%s %s %s %s %s %s" % [vehicle.name, vehicle.originalName, vehicle.make, vehicle.englishName, vehicle.englishMake, vehicle.id]
		if not query.is_empty() and not searchable.to_lower().contains(query):
			continue
		var index := list.add_item(str(vehicle.name))
		list.set_item_metadata(index, vehicle.id)
		list.set_item_tooltip(index, "%s · %s" % [vehicle.id, vehicle.category])
		if selected == vehicle.id:
			list.select(index)
	count_label.text = "%s / %s" % [list.item_count, source.vehicles.size()]


func _on_selected(index: int) -> void:
	if busy:
		_filter()
		return
	var id: String = list.get_item_metadata(index)
	if id == selected:
		return
	_select(id)
	if configs.item_count > 0:
		await _render(0, [])


func _select(id: String) -> void:
	selected = id
	var vehicle: Dictionary = source.vehicles[id]
	shown.clear()
	preview_stage.clear_model()
	render_stats.text = ""
	view_type.text = vehicle.category
	view_title.text = str(vehicle.name)
	view_meta.text = "%s · %s" % [vehicle.make, id] if not str(vehicle.make).is_empty() else id
	configs.clear()
	base_only = vehicle.configurations.is_empty()
	if base_only:
		configs.add_item("基础模型")
	for i in range(vehicle.configurations.size()):
		var config: Dictionary = vehicle.configurations[i]
		var colour: String = (" · #" + config.color.trim_prefix("#")) if not config.color.is_empty() else ""
		if config.get("colorSource") == "palette":
			colour += "（调色板）"
		elif config.get("colorSource") == "neutral":
			colour += "（预览底色）"
		configs.add_item("配置 %02d%s" % [i + 1, colour])
	_clear_parts()
	empty_view.text = "正在准备基础模型…" if base_only else "正在准备整车预览…"
	empty_view.show()
	_status(empty_view.text)
	_filter()
	for index in list.get_selected_items():
		list.ensure_current_is_visible()
	_set_busy(false)


func _clear_parts() -> void:
	parts_loaded = false
	part_hint.text = "此车型缺少可组装的原厂配置。" if base_only else "读取配件后，可按安装槽选择模型。"
	part_controls.clear()
	for child in part_box.get_children():
		part_box.remove_child(child)
		child.queue_free()


func _inspect_parts() -> void:
	if busy or selected.is_empty():
		return
	_set_busy(true)
	_status("正在读取可用的配件模型…")
	var result: Dictionary = await source.list_parts(selected)
	_set_busy(false)
	if not result.get("ok", false):
		_failure(result.error)
		return
	_show_parts(result.parts, [])
	_status("已读取 %s 个可用配件。" % result.parts.size())


func _show_parts(parts: Array, picks: Array) -> void:
	_clear_parts()
	parts_loaded = true
	var by_slot: Dictionary = {}
	for part: Dictionary in parts:
		if not by_slot.has(part.slot):
			by_slot[part.slot] = []
		by_slot[part.slot].append(part)
	part_hint.text = "选择配件后点击「更新预览」。" if not by_slot.is_empty() else "未找到具有可解析模型的配件。"
	for group: Array in by_slot.values():
		var first: Dictionary = group[0]
		var slot_label: String = str(first.slot_name).replace("_", " ") if first.slot_name is String else "安装槽 " + first.slot
		part_box.add_child(_label(slot_label, 12, "#c5bfce"))
		var option := OptionButton.new()
		option.fit_to_longest_item = false
		option.add_item("沿用原厂配置")
		option.set_item_metadata(0, "")
		for part: Dictionary in group:
			var caption: String = part.label
			if caption.length() > 25:
				caption = caption.left(22) + "…"
			option.add_item(caption)
			var index := option.item_count - 1
			option.set_item_tooltip(index, "%s · %s" % [part.label, part.id])
			option.set_item_metadata(index, part.id)
			if picks.has(part.id):
				option.select(index)
		part_box.add_child(option)
		part_controls.append(option)
	_set_busy(busy)


func _apply_current() -> void:
	if busy or configs.selected < 0:
		return
	var picks: Array = []
	for option in part_controls:
		if option.selected > 0:
			picks.append(option.get_item_metadata(option.selected))
	await _render(configs.selected, picks)


func _render(config: int, picks: Array) -> bool:
	_set_busy(true)
	_status("正在生成整车模型和贴图…")
	var result: Dictionary = await source.preview(selected, config, picks)
	if not result.get("ok", false):
		_set_busy(false)
		if shown.is_empty():
			empty_view.text = "无法生成预览，请查看下方状态。"
		_failure(result.error)
		return false
	_status("正在加载整车 GLB…")
	await get_tree().process_frame
	var imported: Dictionary = preview_stage.show_model(result.path, shown.get("model") == selected,
		false, str(result.get("paintFallback", "")), result.get("trackGear", {}))
	_set_busy(false)
	if imported.has("error"):
		if shown.is_empty():
			empty_view.text = "Godot 无法加载该车辆。"
		_failure(imported.error)
		return false
	var stable := picks.duplicate()
	stable.sort()
	shown = {"model": selected, "config": config, "parts": stable}
	var info: Dictionary = result.asset
	var size: Vector3 = imported.size
	render_stats.text = "%s 组网格  ·  %.2f × %.2f × %.2f m" % [imported.meshes, size.x, size.y, size.z]
	empty_view.hide()
	_set_busy(false)
	var message := "已加载基础模型" if info.get("base", false) else "已加载整车预览"
	if int(info.issues) > 0:
		message += " · SixNG 报告 %s 项配件或贴图警告" % int(info.issues)
	_status(message)
	return true


func _copy_code() -> void:
	if shown.is_empty():
		return
	var encoded := Marshalls.utf8_to_base64(JSON.stringify(shown))
	var code := CODE_PREFIX + encoded.replace("+", "-").replace("/", "_").replace("=", "")
	DisplayServer.clipboard_set(code)
	_status("已复制当前预览的改车码。")


func _open_import() -> void:
	code_input.clear()
	import_dialog.popup_centered()
	code_input.grab_focus()


func _import_code() -> void:
	if busy:
		return
	var code := code_input.text.strip_edges()
	var payload := code.trim_prefix(CODE_PREFIX)
	if not code.begins_with(CODE_PREFIX) or not SixNG.matches_pattern(payload, "^[A-Za-z0-9_-]{1,4092}$") or payload.length() % 4 == 1:
		_failure("改车码格式无效。")
		return
	payload = payload.replace("-", "+").replace("_", "/")
	payload += "=".repeat((4 - payload.length() % 4) % 4)
	var spec: Variant = JSON.parse_string(Marshalls.base64_to_utf8(payload))
	if not spec is Dictionary or not SixNG.matches_pattern(spec.get("model"), SixNG.MODEL_PATTERN) or not spec.get("parts") is Array:
		_failure("改车码内容无效。")
		return
	var config: Variant = spec.get("config")
	if (not config is float and not config is int) or config < 0 or config != floorf(config) or config > 10000 or spec.parts.size() > 100:
		_failure("改车码中的配置或配件无效。")
		return
	for part: Variant in spec.parts:
		if not SixNG.matches_pattern(part, SixNG.HASH_PATTERN):
			_failure("改车码中有无效的配件编号。")
			return
	if not source.vehicles.has(spec.model) or int(config) >= source.vehicles[spec.model].configurations.size():
		_failure("本地目录中找不到这个车型或原厂配置。")
		return
	var parts: Array = []
	if not spec.parts.is_empty():
		_set_busy(true)
		_status("正在核对改车码中的配件…")
		var options: Dictionary = await source.list_parts(spec.model)
		_set_busy(false)
		if not options.get("ok", false):
			_failure(options.error)
			return
		parts = options.parts
		var by_id: Dictionary = {}
		for item: Dictionary in parts:
			by_id[item.id] = item.slot
		var slots: Dictionary = {}
		for id: String in spec.parts:
			if not by_id.has(id) or slots.has(by_id[id]):
				_failure("改车码中有不可用或占用同一安装槽的配件。")
				return
			slots[by_id[id]] = true
	search.clear()
	categories.select(0)
	_select(spec.model)
	configs.select(int(config))
	if not spec.parts.is_empty():
		_show_parts(parts, spec.parts)
	if await _render(int(config), spec.parts):
		_status("已应用改车码。")


func _set_busy(value: bool) -> void:
	busy = value
	open_button.disabled = value
	configs.disabled = value or configs.item_count == 0 or base_only
	parts_button.disabled = value or configs.item_count == 0 or parts_loaded or base_only
	apply_button.disabled = value or configs.item_count == 0
	copy_button.disabled = value or shown.is_empty() or base_only
	import_button.disabled = value or source.vehicles.is_empty()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
	for option in part_controls:
		option.disabled = value
	reset_button.disabled = shown.is_empty()
	spin_button.disabled = shown.is_empty()
	free_button.disabled = shown.is_empty()


func _status(message: String, percent := -1.0) -> void:
	status_label.text = message
	status_label.tooltip_text = message
	status_label.add_theme_color_override("font_color", Color("#aeabb9"))
	progress_bar.visible = percent >= 0
	progress_bar.value = maxf(0.0, percent)


func _failure(message: String) -> void:
	_status(message)
	status_label.add_theme_color_override("font_color", Color("#ffaaaa"))
