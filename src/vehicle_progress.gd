extends RefCounted

const FILTERS := {
	"vehicles_cars_coupe": "双门轿跑",
	"vehicles_cars_muscle": "肌肉车",
	"vehicles_cars_offroad": "越野车",
	"vehicles_cars_pickup": "皮卡",
	"vehicles_cars_sedan": "轿车",
	"vehicles_cars_sports": "跑车",
	"vehicles_cars_super": "超级跑车",
	"vehicles_cars_suv": "SUV",
	"vehicles_cars_vans": "厢式车",
	"vehicles_bikes_items": "摩托车",
	"vehicles_watercraft_items": "船艇",
	"vehicles_aircraft_items": "飞机",
	"vehicles_service_trucks": "商用车辆",
	"vehicles_service_utility": "多用途车",
	"vehicles_service_emergency": "应急车辆",
	"vehicles_service_military": "军用车辆",
	"vehicles_service_industrial": "工业车辆",
	"vehicles_service_transport": "巴士",
}
const METERS := {
	"SPEED": "speed",
	"ACCELERATION": "acceleration",
	"ASPHALT_HANDLING": "roadHandling",
	"OFFROAD_HANDLING": "offroadHandling",
	"STRENGTH": "strength",
}
const ITEM_ATTRIBUTES := ["CurrentValue", "MaxValue", "IconType", "SecondaryIconType"]
const ITEM_TEXT := ["ID", "ItemLabel", "ValueRawText", "SecondaryValueRawText", "DescriptionLabel"]


static func read_directory(directory: String) -> Dictionary:
	var index := FileAccess.open(directory.path_join("index.jsonl"), FileAccess.READ)
	if index == null:
		return {}
	var values := {}
	var aliases := {}
	while not index.eof_reached():
		var line := index.get_line()
		if not line.contains("uiProgressDataset"):
			continue
		var entry: Variant = JSON.parse_string(line)
		if entry is Dictionary and entry.get("stats", {}).get("root") == "uiProgressDataset":
			_read_file(directory.path_join(entry.file.get_file()), values, aliases)
	values.merge(aliases)
	return values


static func _read_file(path: String, output: Dictionary, aliases: Dictionary) -> void:
	var parser := XMLParser.new()
	if parser.open(path) != OK:
		return
	var nodes: PackedStringArray = []
	var items: Array[Dictionary] = []
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var name := parser.get_node_name()
				if name == "Item" and not parser.is_empty():
					items.append({})
				if parser.is_empty():
					if not items.is_empty() and nodes[-1] == "Item" and name in ITEM_ATTRIBUTES:
						items[-1][name] = parser.get_named_attribute_value_safe("value")
				else:
					nodes.append(name)
			XMLParser.NODE_TEXT:
				if nodes.size() >= 2 and nodes[-2] == "Item" and nodes[-1] in ITEM_TEXT:
					var value := parser.get_node_data().strip_edges()
					if not value.is_empty():
						items[-1][nodes[-1]] = value
			XMLParser.NODE_ELEMENT_END:
				if nodes[-1] == "Item":
					var item: Dictionary = items.pop_back()
					if not items.is_empty():
						_collect_item(item, items[-1], nodes[-2], output, aliases)
				nodes.resize(nodes.size() - 1)


static func _collect_item(item: Dictionary, parent: Dictionary, container: String, output: Dictionary, aliases: Dictionary) -> void:
	match container:
		"ItemSet":
			var label: String = item.get("ItemLabel", "")
			if not label.begins_with("PROG_VEHICLES_"):
				return
			var values: Dictionary = parent.get("values", {})
			if label == "PROG_VEHICLES_RACING":
				_read_rating(values, item.get("IconType", ""), item.get("ValueRawText", ""))
				_read_rating(values, item.get("SecondaryIconType", ""), item.get("SecondaryValueRawText", ""))
			else:
				var field: String = METERS.get(label.trim_prefix("PROG_VEHICLES_"), "")
				var maximum: String = item.get("MaxValue", "")
				var score: String = item.get("CurrentValue", "")
				if not field.is_empty() and maximum.is_valid_float() and float(maximum) == 10.0 and score.is_valid_float():
					values[field] = clampf(float(score), 0.0, 10.0)
			parent.values = values
		"UnlockedInfoPanelPages":
			var values: Dictionary = parent.get("values", {})
			values.merge(item.get("values", {}))
			parent.values = values
			var description: String = item.get("DescriptionLabel", "")
			if description.begins_with("VEHICLESPEC_") and description.ends_with("_BASE_SPEC_ITEM_DESC"):
				parent.model = description.trim_prefix("VEHICLESPEC_").trim_suffix("_BASE_SPEC_ITEM_DESC").to_lower()
		"Items":
			var filter: String = FILTERS.get(parent.get("ID", ""), "")
			var id: String = item.get("ID", "").to_lower()
			if filter.is_empty() or id.is_empty():
				return
			var values: Dictionary = output.get(id, {})
			values["category"] = filter
			values.merge(item.get("values", {}), true)
			output[id] = values
			var model: String = item.get("model", "")
			if not model.is_empty() and model != id:
				aliases[model] = values


static func _read_rating(output: Dictionary, icon: String, value: String) -> void:
	if value.is_valid_int() and int(value) > 0:
		match icon:
			"0": output.roadRating = int(value)
			"1": output.dirtRating = int(value)
