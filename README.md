# Leonida Customs · GTA VI 载具预览器

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

工位使用顶置长灯条和可调颜色、粗糙度的亮面地板。Godot 按中央视口的物理像素尺寸输出画面，并无损传给 WinUI，预览传输上限为 30 帧每秒。视口右上角显示实际输出尺寸与 GPU 耗时。

- 右上角「设置」集中管理界面主题、Mica、车灯、地面网格、渲染和灯光。「灯光与地面」的颜色选择器支持十六进制输入。车灯默认打开，外观、车灯、网格和地面颜色保存在项目的 `work/viewer-preferences.json`。
- 「纯光栅」使用 Forward+，可切换 SSR、平面倒影、SSAO、SSIL 和辉光。抗锯齿支持 TAA、FXAA、SMAA、MSAA、FSR 2.2 和关闭。
- 安装官方 NVIDIA Godot RTX 运行时后，可在同一窗口切换「全路径追踪」。路径追踪画质提供性能、平衡、质量、极致四档，分别使用每像素 1、2、4、8 个样本。首次切换或加载新材质时，视口会提示正在准备着色器。
- 先选抗锯齿与超分方法，再选对应的档位。MSAA 支持 2×、4×、8×，FSR 2.2 提供原生 AA 和超分档位。NVIDIA DLSS 需要另装 Streamline 并通过硬件检测，提供原生 DLAA、质量、平衡和性能。超分档位改变 3D 内部采样，输出仍按 WinUI 视口尺寸。支持光线重建时，路径追踪搭配 DLSS 或 DLAA 自动启用光线重建，默认用原生 DLAA 和每像素 4 个样本。
- 点击预览底部「自由视角」后，鼠标在预览区域内控制朝向，WASD 平移，Q/E 降低或抬高，Shift 加速，滚轮调移动速度，Esc 退出。普通环绕模式仍可用。

### 可选 RTX 运行时

默认入口在安装 RTX 运行时后自动使用它，并从纯光栅起步。`Start-Viewer-RayTracing.cmd` 在本机支持时直接进入全路径追踪。

`setup.ps1 -RayTracing` 通过已登录的 GitHub CLI 获取 [NVIDIA 官方 Windows 构建](https://github.com/NVIDIA-RTX/godot/actions/runs/41390391716)。可用 `setup.ps1 -DLSS` 同时安装 [NVIDIA Streamline 2.10.0](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.10.0)。构建归档到期后，也可从 [NVIDIA Godot RTX 对应提交](https://github.com/NVIDIA-RTX/godot/tree/49a825dc52c0f1892ff5ce5cdbbe7572c638d41a) 编译 Windows x64 编辑器，将可执行文件放入 `tools/godot-rtx`，命名为 `godot.windows.editor.x86_64.exe`。

可运行不依赖游戏文件的渲染切换检查：

```powershell
.\tools\godot-rtx\godot.windows.editor.x86_64.exe --path . --script tests/render_mode_smoke.gd -- --require-rtx --require-dlss
```

## 当前范围

- 实测 Xbox Series 1.0.2.1。此版本的 SixNG 能恢复部分资源名称，缺少原厂配置的车型会尝试加载基础模型。
- 预览会读取可用的车辆遮蔽贴图，保留格栅的镂空遮罩，并为前进气口内的深色零件和轮腔补充遮蔽。轮毂外圈与辐条使用抛光金属响应，制动件使用独立材质。可识别的车灯使用导出资源的发光贴图，灯罩与反光面分别处理。缺失刹车盘或鼓时使用内侧遮挡。
- 对带有 SixNG 主漆标记的模型，可在 WinUI「车辆配置」实时切换亮光实色、金属漆、哑光和珠光。可沿用原车颜色或输入 `#RRGGBB`。这些饰面使用预览器的参数，当前改车码仅记录原厂配置和配件。Xbox BCPack 解码、游戏专用着色器、涂装及部分配件数据会影响复现精度。
- 改装属于本地预览，配件随 SixNG 对该车型的解析能力而定。改车码在同版本资源之间最容易复现。

## 开发

使用 `Build-WinUI.ps1` 重新编译本地界面，或直接打开 `winui/VehicleStudio.csproj`。启动脚本会连接 `preview-worker.tscn`。Godot 的 `main.tscn` 可用于单独调试渲染器。

## 依赖

- [Windows App SDK / WinUI 3](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/) · 2.6.5，通过 NuGet 还原。
- [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) · MIT。路径追踪可选 NVIDIA Godot RTX。Streamline 运行时按 NVIDIA 的许可单独获取。
- [SixNG 0.9.0](https://github.com/holdmysocks/SixNG/releases/tag/v0.9.0) · GPL-3.0。按独立进程调用 `index`、`vehicles` 和 `vehicle`；在项目目录外使用自带的兼容版本可设置 `SIXNG_EXE`。
