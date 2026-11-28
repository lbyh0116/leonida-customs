extends RefCounted

const CLASS_NAMES := [
	"紧凑型", "轿车", "SUV", "双门轿跑", "肌肉车", "经典跑车", "跑车", "超级跑车",
	"摩托车", "越野车", "工业车辆", "多用途车", "厢式车", "自行车", "船艇", "直升机",
	"飞机", "巴士", "应急车辆", "军用车辆", "商用车辆", "轨道车辆", "开轮赛车"
]
const MODEL_CLASSES := {
	"cometretro": 6, "jugular": 6, "sentinelclassic2": 6,
	"dominator7": 4, "dominatorclassic": 4, "impaler5": 4, "stallion": 4, "vigero3": 4,
	"dominatorbuggy": 9, "marshall": 9, "patriot3": 9
}
const TRAILERS := ["baletrailer", "freighttrailer", "graintrailer", "quadtrailer", "voyager"]
## Reviewed against https://www.gtacn.org/vehicles using the GTA VI display name and variant.
const REVIEWED_NAMES := {
	"asterope2": ["Asterope GZ", "爱硕普 GZ"],
	"baletrailer": ["Bale Trailer", "草捆拖车"],
	"baller8": ["Baller ST-D", "行者 ST-D"],
	"bulldozer": ["Bulldozer", "推土机"],
	"carbonrs": ["Carbon RS", "碳纤 RS 型"],
	"cavalcade3": ["Cavalcade XL", "骑兵 XL"],
	"comet7": ["Comet S2", "陆上彗星 S2"],
	"coquette4": ["Coquette D10", "艳妇 D10"],
	"dominator7": ["Dominator ASP", "公路霸者 ASP"],
	"dominator9": ["Dominator GT", "公路霸者 GT"],
	"double": ["Double-T", "双 T"],
	"drafter": ["8F Drafter", "8F 尾随者"],
	"graintrailer": ["graintrailer", "谷物拖车"],
	"granger": ["Granger", "屌王"],
	"granger3600lx": ["Granger 3600LX", "屌王 3600LX"],
	"impaler5": ["'95 Impaler SZ", "'95刺刑官 SZ"],
	"italirsx": ["Itali RSX", "义塔力 RSX"],
	"landstalker2": ["Landstalker XL", "追捕者 XL"],
	"lazer": ["P-996 LAZER", "P-996 天煞"],
	"nimbus": ["Nimbus", "灵气号"],
	"penumbraff": ["'97 Penumbra FF", "'97半影使者 FF"],
	"reblagts": ["Rebla GTS", "瑞巴 GTS"],
	"sandking_4dr": ["Sandking XL", "大脚霸王 XL"],
	"schafter3": ["Schafter V12", "莎夫特 V12"],
	"shamal": ["Shamal", "夏玛尔客机"],
	"tailgater2": ["Tailgater S", "密探 S"],
	"tulip2": ["'78 Tulip M-100", "'78郁金 M-100"],
	"vigero3": ["Vigero ZX Convertible", "活力够 ZX 敞篷版"],
	"yosemite1500": ["Yosemite 1500", "约塞米蒂 1500"],
}


static func reviewed_name(model: String, english_name: String, original_name: String) -> String:
	var reviewed: Array = REVIEWED_NAMES.get(model, [])
	if not reviewed.is_empty() and english_name.nocasecmp_to(reviewed[0]) == 0:
		return reviewed[1]
	return original_name


static func category(model: String, info: Dictionary, progress_category: String) -> String:
	var chassis := tag(info.get("type"))
	var original := tag(info.get("vehicleClass"))
	if chassis in [12, 13]:
		return CLASS_NAMES[21]
	if chassis == 1:
		return CLASS_NAMES[16]
	if chassis == 5:
		return CLASS_NAMES[15]
	if original == 13 or chassis == 8:
		return CLASS_NAMES[13]
	if original == 8 or chassis == 7:
		return CLASS_NAMES[8]
	if not progress_category.is_empty():
		return progress_category
	if original == 11 and (model.begins_with("trailer") or model in TRAILERS):
		return "拖挂车辆"
	if original in [28, 29]:
		return "皮卡"
	var index: int = MODEL_CLASSES.get(model, original)
	return CLASS_NAMES[index] if index >= 0 and index < CLASS_NAMES.size() else "未分类"


static func tag(value: Variant) -> int:
	if value is Dictionary:
		value = value.get("tag")
	return int(value) if value is int or value is float else -1


static func label_hash(value: Variant) -> String:
	return "%08x" % int(value) if (value is int or value is float) and value > 0 else ""


static func label_ids(records: Array) -> PackedStringArray:
	var ids: Dictionary = {}
	for record: Dictionary in records:
		var info: Dictionary = record.get("model_info") if record.get("model_info") is Dictionary else {}
		for field in ["gameName", "vehicleMakeName"]:
			var id := label_hash(info.get(field))
			if not id.is_empty():
				ids["0x" + id] = true
	return PackedStringArray(ids.keys())


static func simplified_labels(result: Dictionary) -> Dictionary:
	var tables: Dictionary = {}
	var han := RegEx.create_from_string("[一-鿿]")
	var kana := RegEx.create_from_string("[ぁ-ヿ]")
	for entry: Dictionary in result.get("labels", []):
		for hit: Dictionary in entry.get("found", []):
			var table := str(hit.get("table", ""))
			var label := str(hit.get("text", "")).strip_edges()
			if not table.is_empty() and not label.is_empty():
				if not tables.has(table):
					tables[table] = {}
				tables[table][entry.hash] = label
	var best: Dictionary = {}
	var best_score := 0
	for labels: Dictionary in tables.values():
		var score := 0
		for label: String in labels.values():
			if kana.search(label):
				score -= 4
			elif han.search(label):
				score += 1
		# Prefer the Simplified Chinese table if both Chinese locales are present.
		if str(labels.get("440851d8", "")).contains("陆上"):
			score += labels.size()
		if score > best_score:
			best = labels
			best_score = score
	return best


static func handling_data(records: Array) -> Dictionary:
	var result: Dictionary = {}
	for record: Dictionary in records:
		var id := str(record.get("handling", ""))
		if id.is_empty() or result.has(id):
			continue
		var values := {}
		for component: Dictionary in record.get("components", []):
			match component.get("_component"):
				"body (mass, drag)":
					var mass: Variant = component.get("fMass")
					if mass is float and mass > 0:
						values.mass = mass
				"transmission":
					var gears: Variant = component.get("fGearRatios")
					if gears is Array:
						var forward := 0
						for gear: Variant in gears:
							if (gear is float or gear is int) and gear > 0:
								forward += 1
						if forward > 0:
							values.gears = forward
							if component.has("fDriveBiasFront") and component.has("fDriveBiasRear"):
								var front := float(component.fDriveBiasFront)
								var rear := float(component.fDriveBiasRear)
								values.drive = "四驱" if front > 0 and rear > 0 else ("前驱" if front > 0 else "后驱")
		result[id] = values
	return result


static func part_hash(name: String) -> String:
	if name.length() == 8 and name.is_valid_hex_number(false):
		return name
	var hash := 0
	for byte: int in name.to_lower().to_utf8_buffer():
		hash = (hash + byte) & 0xffffffff
		hash = (hash + (hash << 10)) & 0xffffffff
		hash ^= hash >> 6
	hash = (hash + (hash << 3)) & 0xffffffff
	hash ^= hash >> 11
	hash = (hash + (hash << 15)) & 0xffffffff
	return "%08x" % hash
