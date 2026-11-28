using System.Text.RegularExpressions;

namespace VehicleStudio;

internal static class PartLabels
{
    private static readonly Dictionary<string, string> Slots = new(StringComparer.OrdinalIgnoreCase)
    {
        ["aerial_mounts"] = "天线底座", ["aerials"] = "天线", ["aerocover_motorbike_f"] = "摩托车前导流罩", ["aerocover_motorbike_r"] = "摩托车后导流罩",
        ["arch_covers"] = "轮眉", ["badges"] = "车标", ["bike_fairing_front"] = "摩托车前整流罩", ["bike_fairing_rear"] = "摩托车后整流罩",
        ["bike_forks"] = "前叉", ["bike_handguards"] = "手把护板", ["bike_handlebars"] = "车把", ["bike_mudguard_f"] = "摩托车前挡泥板",
        ["bike_mudguard_r"] = "摩托车后挡泥板", ["bike_nerfguards"] = "摩托车侧护架", ["bike_rear_extras"] = "摩托车尾部附件", ["bike_sissybar"] = "后座靠背",
        ["bike_sumpguard"] = "摩托车发动机护板", ["bike_windshield"] = "摩托车风挡", ["body_kit"] = "车身套件", ["bodyshell"] = "车壳",
        ["bonnet"] = "引擎盖", ["bonnet_accessories"] = "引擎盖附件", ["bonnet_catches"] = "引擎盖锁扣", ["boot"] = "后备厢盖",
        ["boot_accessories"] = "后备厢附件", ["brakediscs"] = "刹车盘", ["brakediscs_rear"] = "后刹车盘", ["bullbars"] = "前护杠",
        ["bumper_f"] = "前保险杠", ["bumper_f_accessories"] = "前保险杠附件", ["bumper_f_canards"] = "前保险杠导流翼", ["bumper_r"] = "后保险杠",
        ["bumper_r_accessories"] = "后保险杠附件", ["bumper_r_dangle"] = "后保险杠挂饰", ["calipers"] = "刹车卡钳", ["calipers_front"] = "前刹车卡钳",
        ["calipers_rear"] = "后刹车卡钳", ["cargo"] = "货物", ["chassis"] = "底盘", ["chassis_damage"] = "底盘损伤",
        ["curbfeelers"] = "路沿探杆", ["diffuser"] = "后扩散器", ["dirt"] = "污渍", ["doorcard"] = "车门内饰板",
        ["doors"] = "车门", ["doors_front"] = "前车门", ["doors_rear"] = "后车门", ["drag_chute"] = "减速伞",
        ["engine"] = "发动机", ["engine_boat"] = "船用发动机", ["exhaust"] = "排气管", ["flag"] = "旗帜",
        ["fuel_tank"] = "油箱", ["grill"] = "进气格栅", ["headlights"] = "前大灯", ["heli_body"] = "直升机机身",
        ["heli_rotors"] = "直升机旋翼", ["induction"] = "进气系统", ["intakes"] = "进气口", ["interior"] = "内饰",
        ["interior_accessories"] = "内饰附件", ["interior_boot"] = "后备厢内饰", ["interior_dashcam"] = "行车记录仪", ["interior_extras"] = "内饰扩展件",
        ["interior_rollcage"] = "防滚架", ["interior_shifter_arm"] = "换挡杆", ["interior_shifter_head"] = "换挡杆头", ["kits"] = "套件",
        ["lights_front"] = "前辅助灯", ["lights_rims"] = "轮毂灯", ["lights_rims_rear"] = "后轮毂灯", ["lights_roof"] = "车顶灯",
        ["lights_truckbed"] = "货厢灯", ["lights_truckbed2"] = "货厢灯（第二组）", ["livery"] = "车身涂装", ["main_trim"] = "主饰条",
        ["mudflaps_f"] = "前挡泥板", ["mudflaps_m"] = "中部挡泥板", ["mudflaps_r"] = "后挡泥板", ["overlays_bodyshell"] = "车壳覆盖层",
        ["overlays_chassis"] = "底盘覆盖层", ["overlays_front"] = "车头覆盖层", ["overlays_left"] = "左侧覆盖层", ["overlays_rear"] = "车尾覆盖层",
        ["overlays_right"] = "右侧覆盖层", ["overlays_roof"] = "车顶覆盖层", ["plaques"] = "装饰铭牌", ["plate_base"] = "牌照底座",
        ["plate_front_rear"] = "前后牌照", ["plate_reader"] = "牌照识别器", ["police_scanner"] = "警用扫描仪", ["rims"] = "轮毂",
        ["rims_front"] = "前轮毂", ["rims_rear"] = "后轮毂", ["roof"] = "车顶", ["roof_accessories"] = "车顶附件",
        ["roof_attachments"] = "车顶安装件", ["roof_extras"] = "车顶扩展件", ["roof_scoops"] = "车顶进气口", ["roof_spoiler"] = "车顶扰流板",
        ["searchlight"] = "探照灯", ["seat_lf"] = "左前座椅", ["seat_rf"] = "右前座椅", ["seats"] = "座椅",
        ["sidestep_l"] = "左侧踏板", ["sidestep_r"] = "右侧踏板", ["sidesteps"] = "侧踏板", ["sign_mesh"] = "标识件",
        ["sirens_ext"] = "外置警灯", ["sirens_ext2"] = "外置警灯（第二组）", ["sirens_ext_bumper_f"] = "前杠警灯", ["sirens_ext_grill"] = "格栅警灯",
        ["sirens_ext_misc_2"] = "其他外置警灯", ["sirens_roof"] = "车顶警灯", ["sirens_roofbar1"] = "车顶警示灯条", ["sirens_roofbar1_extras"] = "警示灯条附件",
        ["skidplate"] = "底盘护板", ["skirt_splitter"] = "侧裙导流板", ["skirts"] = "侧裙", ["snorkel"] = "涉水喉",
        ["snorkel_body"] = "车身涉水喉", ["spare_wheels"] = "备胎", ["splitter"] = "前唇", ["spoiler"] = "尾翼",
        ["sprocket"] = "链轮", ["steering"] = "方向盘", ["sticker"] = "贴纸", ["toolbox_l"] = "左侧工具箱",
        ["toolbox_r"] = "右侧工具箱", ["towing"] = "拖车装置", ["towing_front"] = "前拖车装置", ["truckbed"] = "货厢",
        ["truckbed_accessories"] = "货厢附件", ["truckbed_crane_top"] = "货厢起重机上装", ["truckbed_extras"] = "货厢扩展件", ["turret"] = "炮塔",
        ["turret1"] = "炮塔组件", ["tyres"] = "轮胎", ["tyres_rear"] = "后轮胎", ["utility"] = "功能附件",
        ["wheelie_bar"] = "防翘尾杆", ["wind_deflectors"] = "导风板", ["windows"] = "车窗", ["wing_l"] = "左翼子板",
        ["wing_mirrors"] = "后视镜", ["wing_r"] = "右翼子板", ["wings"] = "翼子板"
    };

    private static readonly Dictionary<string, string> Details = new(StringComparer.OrdinalIgnoreCase)
    {
        ["carbon"] = "碳纤维", ["chrome"] = "镀铬", ["forged"] = "锻造", ["sports"] = "运动",
        ["sport"] = "运动", ["offr"] = "越野", ["offroad"] = "越野", ["race"] = "赛用",
        ["tinted"] = "着色", ["integrated"] = "集成式"
    };

    public static string Slot(string? name, string id)
    {
        if (string.IsNullOrWhiteSpace(name))
            return UiText.F("配件槽位 {0}", id);
        if (!UiText.English)
            return Slots.GetValueOrDefault(name, UiText.F("配件槽位 {0}", id));
        return name switch
        {
            "bumper_f" => "Front bumper",
            "bumper_r" => "Rear bumper",
            "bumper_f_canards" => "Front bumper canards",
            "rims_front" => "Front wheels",
            "rims_rear" => "Rear wheels",
            "calipers_front" => "Front brake calipers",
            "calipers_rear" => "Rear brake calipers",
            "brakediscs" => "Brake discs",
            "brakediscs_rear" => "Rear brake discs",
            "tyres_rear" => "Rear tires",
            "seat_lf" => "Front left seat",
            "seat_rf" => "Front right seat",
            "wing_l" => "Left fender",
            "wing_r" => "Right fender",
            _ => char.ToUpperInvariant(name[0]) + name[1..].Replace('_', ' ')
        };
    }

    public static string Option(string label, string modelNames, int number)
    {
        var details = Regex.Split(modelNames, "[^a-zA-Z0-9]+")
            .Select(token => Details.GetValueOrDefault(token))
            .OfType<string>().Distinct().Take(2).ToArray();
        var style = details.Length == 0 ? UiText.T("样式") : string.Join(" / ", details.Select(UiText.T));
        return $"{label} · {style} {number:00}";
    }
}
