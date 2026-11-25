# GTA VI 载具预览器

Windows x64 上的离线载具查看器。WinUI 3 提供载具库和设置，同一窗口内的白色摄影棚由 Godot 4 渲染，SixNG 读取 Xbox RPF9 载具资源。应用按 GPL-3.0-only 开源。查看游戏内容时，请在本机提供自己的游戏文件。

## 启动

1. 在 Windows 上安装 .NET 10 SDK，把源码放在有空间的本地磁盘。首次运行时，在项目目录执行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1`。此步骤从官方发布页下载 Godot 4.7.2 与 SixNG 0.9.0，验证 SHA-256，把工具放入项目的 `tools` 目录，并将 WinUI 应用编译到 `work/winui`。
2. 双击 `Start-Viewer.cmd`。点「打开游戏目录」，选择含有 `levels.rpf`、`packs.rpf` 与 `data.rpf` 的 Xbox 版目录。也可以用 `Start-Viewer.cmd "--game=G:\你的游戏目录"`。
3. 第一次打开时会扫描档案并恢复模型名称。进度显示在窗口底部。扫描完成后应用会记住目录，旧索引可用于同一份资源。

首次扫描和整车缓存均位于项目内的 `work`。把项目放在 E 盘即可把这些大文件留在 E 盘。首扫需要数分钟，具体取决于磁盘速度。重新打开已索引的同一目录可复用缓存。预览器对原始游戏目录只读，离线操作，无需启动游戏。源码仓库忽略本地游戏资源、索引、GLB 缓存和依赖二进制文件。

## 预览与改装

- 在左侧按游戏载具类别筛选，或按显示名、厂牌和模型 ID 搜索。左键拖动旋转，右键拖动平移，滚轮缩放，双击或使用「重置视角」恢复构图。
- 在右侧选原厂配置。点「读取配件」，按安装槽选模型，再点「更新预览」。SixNG 会读取相关模型与贴图并重新生成整车 GLB。
- 「复制改车码」复制当前已成功显示的配置。「导入改车码」用接收方自己的本地资源应用同一配置。码中仅含车型、配置编号和配件编号。格式见 [SHARE-CODE.md](SHARE-CODE.md)。

## 渲染设置与自由视角

白色工位使用顶置长灯条、亮面地板和轮胎接触阴影。Godot 在独立的本地渲染进程生成画面，由 WinUI 在中央视口显示，预览传输上限为 30 帧每秒。GPU 计时包含启用时的地板倒影。

- `Start-Viewer.cmd` 使用 Godot 4.7.2 的稳定版 Forward+。要使用硬件光追，在同一目录运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -RayTracing`，然后双击 `Start-Viewer-RayTracing.cmd`。光追入口使用 Godot 4.8 Beta 5，两者复用本地载具目录和缓存。
- 右侧「渲染设置」中可切换画质预设、抗锯齿和 3D 渲染比例。可用模式为 TAA、FXAA、SMAA、MSAA 2×/4×/8×、FSR 2.2 和关闭。降低渲染比例会减少 3D 像素开销，界面按原分辨率显示。顶部 GPU 毫秒用于比较设置的开销。
- 「反射」同时控制 SSR 和半分辨率的地板平面倒影。还可分别切换环境光遮蔽、间接光照和辉光，并调整顶灯、主光、曝光、地面粗糙度和颜色。
- 「摄影棚 · 高画质」会在支持的 Vulkan 设备上开启硬件光追。光追通过车辆网格计算地面软阴影，可选每采样点 8/16/32/64 条光线。移动摄像机时复用世界空间阴影，改变车辆或主光方向时重新计算。车体材质和自身阴影使用 Forward+。
- 点击预览底部「自由视角」后，鼠标在预览区域内控制朝向，WASD 平移，Q/E 降低或抬高，Shift 加速，滚轮调移动速度，Esc 退出。普通环绕模式仍可用。

光追可用性验证可在已安装 4.8 Beta 5 的 Windows 上运行：

```powershell
.\tools\godot-preview\Godot_v4.8-beta5_win64_console.exe --path . --script tests/ray_shadow_smoke.gd
```

## 当前范围

- 实测 Xbox Series 1.0.2.1。此版本的 SixNG 能恢复部分资源名称，缺少原厂配置的车型会尝试加载基础模型。
- 预览会读取可用的车辆遮蔽贴图，保留格栅的镂空遮罩，并为前进气口内的深色零件和轮腔补充遮蔽。可识别的车灯按熄灯状态显示，并分别处理灯罩和反光面。缺失刹车盘或鼓时使用内侧遮挡。
- 对带有 SixNG 主漆标记的模型，可在 WinUI「车辆配置」实时切换亮光实色、金属漆、哑光和珠光。可沿用原车颜色或输入 `#RRGGBB`。这些饰面使用预览器的参数，当前改车码仅记录原厂配置和配件。Xbox BCPack 解码、游戏专用着色器、涂装及部分配件数据会影响复现精度。
- 改装属于本地预览，配件随 SixNG 对该车型的解析能力而定。改车码在同版本资源之间最容易复现。

## 开发

使用 `Build-WinUI.ps1` 重新编译本地界面，或直接打开 `winui/VehicleStudio.csproj`。启动脚本会连接 `preview-worker.tscn`。Godot 的 `main.tscn` 可用于单独调试渲染器。

## 依赖

- [Windows App SDK / WinUI 3](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/) · 2.6.5，通过 NuGet 还原。
- [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) · MIT。默认使用 Forward+。硬件光追入口可选 [Godot 4.8 Beta 5](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-5/)。
- [SixNG 0.9.0](https://github.com/holdmysocks/SixNG/releases/tag/v0.9.0) · GPL-3.0。按独立进程调用 `index`、`vehicles` 和 `vehicle`；在项目目录外使用自带的兼容版本可设置 `SIXNG_EXE`。
