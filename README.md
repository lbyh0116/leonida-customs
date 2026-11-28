<p align="center">
  <img src="winui/Assets/leonida-mark.png" width="112" height="112" alt="Leonida Customs">
</p>
<h1 align="center">Leonida Customs</h1>
<p align="center"><strong>挑一辆车，换上配件，在灯光下看看新车漆。</strong><br>面向 Windows 的 GTA VI 离线载具预览与改装工具。</p>
<p align="center"><a href="README.md">简体中文</a> · <a href="README.en.md">English</a></p>
<p align="center">
  <a href="https://github.com/lbyh0116/leonida-customs/releases/latest"><img src="https://img.shields.io/github/v/release/lbyh0116/leonida-customs?style=flat-square&amp;color=0f9d92" alt="GitHub release"></a>
  <img src="https://img.shields.io/badge/Windows-x64-1575ee?style=flat-square" alt="Windows x64">
  <img src="https://img.shields.io/badge/WinUI-3-6550db?style=flat-square" alt="WinUI 3">
  <img src="https://img.shields.io/badge/Languages-2-0f9d92?style=flat-square" alt="支持两种语言">
</p>
<p align="center"><a href="https://github.com/lbyh0116/leonida-customs/releases/latest"><strong>↓ 下载 Windows 版</strong></a> &nbsp; · &nbsp; <a href="https://github.com/lbyh0116/leonida-customs/issues">反馈问题</a></p>

---

## 下载与运行

最新正式版为 **v0.2.1 · Windows x64 便携版**。

1. 下载 [Leonida-Customs-0.2.1-windows-x64.zip](https://github.com/lbyh0116/leonida-customs/releases/download/v0.2.1/Leonida-Customs-0.2.1-windows-x64.zip)，完整解压到空间充足的磁盘。
2. 运行 `Start-Viewer.cmd`。首次启动会联网下载并校验 Godot 和 SixNG，之后可离线使用。
3. 点击「打开游戏目录」，选择自己 Xbox 版游戏副本中包含 `levels.rpf`、`packs.rpf` 和 `data.rpf` 的文件夹。首次建立索引可能需要几分钟。
4. 在左侧载具库选择车型。预览加载后，可在右侧选择原厂配置、试装配件或调整车漆。

需要 Windows 10 2004（内部版本 19041）或更高版本，以及支持 Vulkan 的显卡和驱动。已验证的游戏版本为 Xbox Series 1.0.2.1。软件只读访问玩家提供的资源，发行包不含游戏文件。

在「设置 → 界面语言」选择简体中文或 English，再点击「应用语言」。索引、缓存、设置和日志保存在便携目录的 `work` 文件夹。

首次下载遇到断线时，重新运行启动脚本即可尝试续传。也可在网络稳定的设备上下载 [Godot ZIP](https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip) 和 [SixNG ZIP](https://github.com/holdmysocks/SixNG/releases/download/v0.11.0/SixNG-v0.11.0-windows-x64.zip)，保留原文件名，放入软件目录的 `work` 文件夹，再运行启动脚本校验并安装。

## 车库与摄影棚

<table>
<tr>
<td width="50%" valign="top"><strong>载具库</strong><br><br>按类别浏览，支持用中英文车名、品牌和模型 ID 搜索。载具数据来自本地档案与游戏图鉴。</td>
<td width="50%" valign="top"><strong>配件和车漆</strong><br><br>选择原厂配置，然后在配件列表试装零件或预览实色亮光、金属漆、哑光与珠光。换件会保留当前视角，切换车型会重新从原厂配置开始。</td>
</tr>
<tr>
<td width="50%" valign="top"><strong>改车码</strong><br><br>复制车型、原厂配置与配件选择。其他玩家可用自己的资源导入。<a href="SHARE-CODE.md">改车码格式</a></td>
<td width="50%" valign="top"><strong>摄影棚</strong><br><br>提供黑白背景预设，支持调光、曝光、地面颜色和粗糙度。车灯默认开启，可把当前视口保存为 PNG。</td>
</tr>
</table>

左键拖动环绕，右键拖动平移，滚轮缩放，双击视口重置。自由视角中，左键拖动环视，WASD 移动，Q/E 升降，Shift 加速，滚轮调速度，Esc 退出。

| 图形模式 | 支持情况 |
| --- | --- |
| 纯光栅 | Godot Forward+，支持 TAA、FXAA、SMAA、MSAA 和 FSR 2.2，以及反射、环境光遮蔽和间接光照选项。 |
| 全路径追踪 | 需安装 Godot RTX，且当前渲染显卡支持硬件光追管线。可选每像素 1、2、4 或 8 个样本。 |
| NVIDIA DLSS | 需支持的 NVIDIA RTX 显卡与 Streamline。提供 DLSS 4.5 Transformer Model M、DLAA、质量、平衡和性能档。路径追踪可选光线重建。 |

修改画质后点击「应用画质」。视口 FPS 显示 WinUI 实际更新画面的频率，默认上限为 30 FPS。「帮助」中可查看视口输出尺寸。

## 兼容性与排查

- 部分原厂配置、配件、贴图和游戏专用材质仍受解码支持限制。载具缺少可组装配置时会尝试载入基础模型，无法装上的组件会显示警告。
- 改车码目前记录车型、配置和配件。车漆预览留在本次本地预览。不同图形模式下，部分漆面的清漆高光采用不同近似方式。
- 启动遇到问题时，运行 `Start-Viewer-Safe-Mode.cmd` 使用稳定版 Godot 和纯光栅，并跳过自动读档。「帮助」可以复制诊断信息和打开日志目录。
- 部分跨代车型名称参考洛圣都档案，并按英文车型与版本核对。[GTA V 载具数据库](https://www.gtacn.org/vehicles)

## 安装 RTX 运行时

从项目或便携版根目录运行。提前安装并登录 GitHub CLI。只装路径追踪时，使用 `-RayTracing`。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ViewerRuntime.ps1 -DLSS
```

`Start-Viewer-RayTracing.cmd` 可在支持的设备上直接启动路径追踪。如果 CI 构建已过期，可编译指定版本，然后将 `godot.windows.editor.x86_64.exe` 放入 `tools/godot-rtx`。 [NVIDIA build](https://github.com/NVIDIA-RTX/godot/actions/runs/41390391716) · [Pinned Godot revision](https://github.com/NVIDIA-RTX/godot/tree/49a825dc52c0f1892ff5ce5cdbbe7572c638d41a) · [Streamline 2.10.0](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.10.0)

## 从源码构建

安装 .NET 10 SDK。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
.\Start-Viewer.cmd
```

- `Build-WinUI.ps1` — 编译 WinUI。
- `Package-Viewer.ps1` — 生成便携 ZIP 与 SHA-256 至 `work/dist`。
- `main.tscn` — 单独调试摄影棚。

```powershell
.\tools\godot-rtx\godot.windows.editor.x86_64.exe --path . --script tests/render_mode_smoke.gd -- --require-rtx --require-dlss
```

## 许可与依赖

Leonida Customs 是独立项目，与 Rockstar Games 无关联。

[GPL-3.0-only](LICENSE) · [WinUI 3 / Windows App SDK](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/) · [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) · [SixNG 0.11.0](https://github.com/holdmysocks/SixNG/releases/tag/v0.11.0)
