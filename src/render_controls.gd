extends ScrollContainer

var _stage: SubViewportContainer
var _stack: VBoxContainer
var _aa: OptionButton
var _scale: HSlider
var _light: Dictionary
var _sliders: Dictionary = {}
var _key_color: ColorPickerButton
var _backdrop: ColorPickerButton
var _ssr: CheckButton
var _ao: CheckButton
var _ssil: CheckButton
var _bloom: CheckButton
var _ray: CheckButton
var _samples: OptionButton
var _ray_status: Label


func attach(stage: SubViewportContainer) -> void:
	_stage = stage
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_stack = VBoxContainer.new()
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.add_theme_constant_override("separation", 7)
	add_child(_stack)
	_light = _stage.lighting_defaults()

	var gpu_time := Label.new()
	gpu_time.add_theme_color_override("font_color", Color("#ada9b7"))
	gpu_time.add_theme_font_size_override("font_size", 12)
	_stack.add_child(gpu_time)
	var meter := Timer.new()
	meter.wait_time = 0.5
	meter.autostart = true
	meter.timeout.connect(func():
		if is_visible_in_tree():
			var ms: float = _stage.gpu_frame_ms()
			gpu_time.text = "3D GPU %.2f ms · %d FPS" % [ms, Engine.get_frames_per_second()] if ms > 0.0 else "GPU 计时暂不可用")
	add_child(meter)
	_heading("画质")
	var presets := OptionButton.new()
	presets.add_item("摄影棚 · 高画质")
	presets.add_item("平衡 · FSR 2.2 质量")
	presets.add_item("流畅 · FSR 2.2 性能")
	_stack.add_child(presets)
	_aa = OptionButton.new()
	for label in ["关闭", "FXAA", "SMAA", "TAA", "MSAA 2×", "MSAA 4×", "MSAA 8×", "FSR 2.2（时间抗锯齿）"]:
		_aa.add_item(label)
	_stack.add_child(_aa)
	_aa.item_selected.connect(func(_index: int): _apply_quality())
	_scale = _slider("3D 渲染比例", 0.50, 1.0, 0.01, 1.0, true)
	_scale.value_changed.connect(func(_value: float): _apply_quality())
	_ssr = _check("屏幕空间反射 · SSR")
	_ao = _check("环境光遮蔽 · SSAO")
	_ssil = _check("间接光照 · SSIL")
	_bloom = _check("高光辉光")
	for effect in [_ssr, _ao, _ssil, _bloom]:
		effect.toggled.connect(func(_on: bool): _apply_effects())

	_heading("硬件光追阴影")
	_ray = _check("车辆投影到地面")
	_ray.disabled = not _stage.supports_ray_shadows()
	_ray.toggled.connect(func(_on: bool): _apply_ray())
	_samples = OptionButton.new()
	for count in [8, 16, 32, 64]:
		_samples.add_item("%s 条光线 / 采样点" % count, count)
	_samples.select(1)
	_samples.item_selected.connect(func(_index: int): _apply_ray())
	_stack.add_child(_samples)
	_ray_status = Label.new()
	_ray_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ray_status.add_theme_font_size_override("font_size", 12)
	_stack.add_child(_ray_status)
	_stage.ray_status_changed.connect(_on_ray_status)

	_heading("灯光")
	_light_slider("key", "主光强度", 0.0, 4.0, 0.05)
	_light_slider("azimuth", "主光方位 °", -180.0, 180.0, 1.0)
	_light_slider("elevation", "主光高度 °", 15.0, 85.0, 1.0)
	_light_slider("size", "主光角直径 °", 0.0, 40.0, 0.5)
	_light_slider("specular", "主光高光", 0.0, 0.50, 0.005)
	_light_slider("fill", "柔光强度", 0.0, 1.5, 0.01)
	_light_slider("ambient", "环境光", 0.0, 1.5, 0.02)
	_light_slider("exposure", "曝光", 0.35, 2.7, 0.025)
	_light_slider("floor_roughness", "地面粗糙度", 0.08, 0.90, 0.01)
	_key_color = _color_row("主光色", "light_color")
	_backdrop = _color_row("背景色", "background_color")
	var reset := Button.new()
	reset.text = "重置灯光"
	reset.pressed.connect(_reset_lighting)
	_stack.add_child(reset)
	presets.item_selected.connect(_preset)
	_preset(0)


func _preset(index: int) -> void:
	_aa.select(3 if index == 0 else 7)
	_scale.value = [1.0, 0.80, 0.60][index]
	_ssr.set_pressed_no_signal(index < 2)
	_ao.set_pressed_no_signal(true)
	_ssil.set_pressed_no_signal(index == 0)
	_bloom.set_pressed_no_signal(index < 2)
	_ray.set_pressed_no_signal(index == 0 and not _ray.disabled)
	_samples.select(1 if index == 0 else 0)
	_apply_quality()
	_apply_effects()
	_apply_ray()


func _apply_quality() -> void:
	_stage.set_quality(_aa.selected, _scale.value)


func _apply_effects() -> void:
	_stage.set_effects(_ssr.button_pressed, _ao.button_pressed, _ssil.button_pressed, _bloom.button_pressed)


func _apply_ray() -> void:
	var active := _ray.button_pressed and not _ray.disabled
	_samples.disabled = not active
	_stage.set_ray_shadows(active, _samples.get_selected_id())


func _on_ray_status(message: String) -> void:
	_ray_status.text = message


func _heading(title: String) -> void:
	_stack.add_child(HSeparator.new())
	var label := Label.new()
	label.text = title
	label.add_theme_color_override("font_color", Color("#f6b2cf"))
	_stack.add_child(label)


func _check(title: String) -> CheckButton:
	var button := CheckButton.new()
	button.text = title
	_stack.add_child(button)
	return button


func _slider(title: String, low: float, high: float, step: float, initial: float, percent := false) -> HSlider:
	var row := HBoxContainer.new()
	var name := Label.new()
	name.text = title
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var number := Label.new()
	var format_value := func(value: float) -> String:
		return "%d%%" % roundi(value * 100.0) if percent else "%.2f" % value
	number.text = format_value.call(initial)
	row.add_child(number)
	_stack.add_child(row)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = initial
	slider.value_changed.connect(func(value: float): number.text = format_value.call(value))
	_stack.add_child(slider)
	return slider


func _light_slider(key: String, title: String, low: float, high: float, step: float) -> void:
	var slider := _slider(title, low, high, step, _light[key])
	_sliders[key] = slider
	slider.value_changed.connect(func(value: float):
		_light[key] = value
		_stage.set_lighting(_light))


func _color_row(title: String, key: String) -> ColorPickerButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var button := ColorPickerButton.new()
	button.edit_alpha = false
	button.custom_minimum_size = Vector2(44, 26)
	button.color = _light[key]
	row.add_child(button)
	_stack.add_child(row)
	button.color_changed.connect(func(color: Color):
		_light[key] = color
		_stage.set_lighting(_light))
	return button


func _reset_lighting() -> void:
	var initial: Dictionary = _stage.lighting_defaults()
	for setting: String in _sliders:
		_sliders[setting].value = initial[setting]
	_light = initial
	_key_color.color = initial.light_color
	_backdrop.color = initial.background_color
	_stage.set_lighting(_light)
