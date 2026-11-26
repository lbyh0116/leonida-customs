using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage.Streams;
using Windows.Foundation;
using Windows.System;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace VehicleStudio;

public sealed partial class MainWindow : Window
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly Regex ModelPattern = new("^[a-z0-9_]{1,80}$", RegexOptions.CultureInvariant);
    private static readonly Regex PartPattern = new("^[0-9a-f]{8}$", RegexOptions.CultureInvariant);
    private static readonly Regex ColorPattern = new("^#[0-9a-fA-F]{6}$", RegexOptions.CultureInvariant);
    private static readonly string[] Arguments = Environment.GetCommandLineArgs();
    private readonly RendererClient renderer = new();
    private readonly List<ComboBox> partChoices = new();
    private readonly Dictionary<string, Slider> lightSliders = new();
    private readonly Dictionary<string, TextBox> lightColors = new();
    private readonly Dictionary<string, object> lighting = new();
    private Dictionary<string, object> lightDefaults = new();
    private IReadOnlyList<Vehicle> vehicles = [];
    private NativeViewport? viewport;
    private Vehicle? selected;
    private BuildCode? displayed;
    private bool started;
    private bool connected;
    private bool busy;
    private bool populating;
    private bool partsLoaded;
    private bool pathAvailable;
    private bool dlssAvailable;
    private bool rayReconstruction;
    private bool appearanceReady;
    private string? preferencePath;
    private Preferences preferences = new();
    private bool paintable;
    private bool closing;
    private Point? pointerPosition;
    private readonly HashSet<VirtualKey> heldKeys = new();

    public MainWindow()
    {
        InitializeComponent();
        Shell.ActualThemeChanged += (_, _) => UpdateTitleTheme();
        PaintFinish.SelectionChanged += async (_, _) => await UpdatePaintAsync();
        PaintColor.LostFocus += async (_, _) => await UpdatePaintAsync();
        PaintColor.KeyDown += async (_, args) =>
        {
            if (args.Key == VirtualKey.Enter)
                await UpdatePaintAsync();
        };
        PreviewSurface.SizeChanged += async (_, _) => await ResizePreviewAsync();
        PreviewSurface.PointerPressed += (sender, args) =>
        {
            pointerPosition = args.GetCurrentPoint(PreviewSurface).Position;
            PreviewSurface.CapturePointer(args.Pointer);
        };
        PreviewSurface.PointerReleased += (_, args) => PreviewSurface.ReleasePointerCapture(args.Pointer);
        PreviewSurface.PointerExited += (_, _) => pointerPosition = null;
        PreviewSurface.PointerMoved += PreviewPointerMoved;
        PreviewSurface.PointerWheelChanged += async (_, args) =>
        {
            var wheel = args.GetCurrentPoint(PreviewSurface).Properties.MouseWheelDelta;
            args.Handled = true;
            await PostAsync("camera", new { action = "wheel", up = wheel > 0 });
        };
        PreviewSurface.DoubleTapped += async (_, _) => await PostAsync("camera", new { action = "reset" });
        Shell.AddHandler(UIElement.KeyDownEvent, new KeyEventHandler(StudioKeyDown), true);
        Shell.AddHandler(UIElement.KeyUpEvent, new KeyEventHandler(StudioKeyUp), true);
        Activated += async (_, args) =>
        {
            if (args.WindowActivationState == WindowActivationState.Deactivated && Fly.IsChecked == true)
                await ExitFlyAsync();
        };
        Title = "Leonida Motorworks · 载具预览器";
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "leonida.ico"));
        var workArea = Microsoft.UI.Windowing.DisplayArea.GetFromWindowId(AppWindow.Id,
            Microsoft.UI.Windowing.DisplayAreaFallback.Primary).WorkArea;
        var width = Math.Min(1400, workArea.Width - 24);
        var height = Math.Min(850, workArea.Height - 22);
        AppWindow.MoveAndResize(new RectInt32(workArea.X + (workArea.Width - width) / 2,
            workArea.Y + (workArea.Height - height) / 2, width, height));
        AppWindow.Closing += async (_, args) =>
        {
            if (closing)
                return;
            args.Cancel = true;
            closing = true;
            await renderer.CloseAsync();
            viewport?.Dispose();
            Close();
        };
    }

    private async void ShellLoaded(object sender, RoutedEventArgs args)
    {
        if (started)
            return;
        started = true;
        SetBusy(true);
        try
        {
            var root = LocateProject();
            preferencePath = Path.Combine(root, "work", "viewer-preferences.json");
            LoadPreferences();
            viewport = new NativeViewport();
            renderer.Notification += message => DispatcherQueue.TryEnqueue(() => OnRendererEvent(message));
            renderer.Disconnected += message => DispatcherQueue.TryEnqueue(() =>
            {
                connected = false;
                SetBusy(false);
                Report(message, error: true);
            });
            var hello = await renderer.StartAsync(root);
            for (var attempt = 0; attempt < 20 && viewport.RendererWindow == 0; attempt++)
            {
                if (!viewport.TryAttach(renderer.ProcessId))
                    await Task.Delay(50);
            }
            if (viewport.RendererWindow == 0)
                throw new InvalidOperationException("未能把 Godot 视口嵌入 WinUI 窗口。");

            connected = true;
            var capabilities = hello.GetProperty("capabilities");
            pathAvailable = capabilities.GetProperty("path_tracing").GetBoolean();
            dlssAvailable = capabilities.GetProperty("dlss").GetBoolean();
            rayReconstruction = capabilities.GetProperty("ray_reconstruction").GetBoolean();
            PathTracingOption.IsEnabled = pathAvailable;
            DlssSwitch.IsEnabled = dlssAvailable;
            populating = true;
            BuildLighting(hello.GetProperty("lighting"));
            RenderMode.SelectedIndex = 0;
            Samples.SelectedIndex = 0;
            populating = false;
            Preset.SelectedIndex = 0;
            if (pathAvailable && Arguments.Contains("--ray-tracing"))
                RenderMode.SelectedIndex = 1;
            await SendQualityAsync();
            await ApplyPreviewPreferencesAsync();
            await ResizePreviewAsync();
            await PostAsync("frame_ack", new { });
            SetBusy(false);
            var saved = Arguments.FirstOrDefault(arg => arg.StartsWith("--game=", StringComparison.Ordinal))?[7..]
                ?? hello.GetProperty("saved_game").GetString();
            if (!string.IsNullOrWhiteSpace(saved))
                await LoadGameAsync(saved);
            else
                Report("请选择含有 levels.rpf、packs.rpf 和 data.rpf 的目录。");
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            connected = false;
            SetBusy(false);
            viewport?.Dispose();
            renderer.Dispose();
            Report(ex is OperationCanceledException ? "预览进程启动超时。请查看 work 目录中的渲染日志。" : ex.Message, error: true);
        }
    }

    private static string LocateProject()
    {
        for (DirectoryInfo? dir = new(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
            if (File.Exists(Path.Combine(dir.FullName, "project.godot")))
                return dir.FullName;
        throw new InvalidOperationException("找不到 project.godot。请从项目目录的启动脚本打开。");
    }

    private void OnRendererEvent(JsonElement message)
    {
        switch (message.GetProperty("event").GetString())
        {
            case "progress":
                Report(message.GetProperty("message").GetString() ?? "", message.GetProperty("percent").GetDouble());
                break;
            case "camera":
                Fly.IsChecked = message.GetProperty("free").GetBoolean();
                if (Fly.IsChecked != true)
                    heldKeys.Clear();
                CameraHint.Text = Fly.IsChecked == true
                    ? "WASD 移动 · Q/E 升降 · Esc 退出"
                    : "拖动旋转 · 右键平移 · 滚轮缩放";
                break;
            case "path_warmup":
                PreviewProgress.Visibility = message.GetProperty("active").GetBoolean() ? Visibility.Visible : Visibility.Collapsed;
                break;
            case "frame":
                _ = PresentFrameAsync(message.GetProperty("jpeg").GetString() ?? "");
                break;
            case "timing":
                var gpu = message.GetProperty("gpu_ms").GetDouble();
                if (gpu > 0)
                    GpuTime.Text = $"3D GPU {gpu:F2} ms";
                break;
        }
    }

    private Task ResizePreviewAsync()
    {
        if (PreviewSurface.XamlRoot is null || PreviewSurface.ActualWidth < 8 || PreviewSurface.ActualHeight < 8)
            return Task.CompletedTask;
        var scale = PreviewSurface.XamlRoot.RasterizationScale;
        var fit = Math.Min(scale, Math.Min(1440.0 / PreviewSurface.ActualWidth, 960.0 / PreviewSurface.ActualHeight));
        var width = (int)Math.Round(PreviewSurface.ActualWidth * fit);
        var height = (int)Math.Round(PreviewSurface.ActualHeight * fit);
        return PostAsync("resize", new { width, height });
    }

    private async Task PresentFrameAsync(string encoded)
    {
        try
        {
            if (!closing)
            {
                using var stream = new InMemoryRandomAccessStream();
                using (var buffer = new DataWriter(stream))
                {
                    buffer.WriteBytes(Convert.FromBase64String(encoded));
                    await buffer.StoreAsync();
                    buffer.DetachStream();
                }
                stream.Seek(0);
                var bitmap = new BitmapImage();
                await bitmap.SetSourceAsync(stream);
                PreviewImage.Source = bitmap;
            }
        }
        catch (Exception ex) when (ex is FormatException or IOException or System.Runtime.InteropServices.COMException)
        {
            Report("无法显示渲染画面。", error: true);
        }
        finally
        {
            await PostAsync("frame_ack", new { });
        }
    }

    private async void OpenFolderClicked(object sender, RoutedEventArgs args)
    {
        try
        {
            var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.ComputerFolder };
            picker.FileTypeFilter.Add("*");
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
            if (await picker.PickSingleFolderAsync() is { } folder)
                await LoadGameAsync(folder.Path);
        }
        catch (Exception ex)
        {
            Report(ex.Message, error: true);
        }
    }

    private async Task LoadGameAsync(string path)
    {
        await RunAssetActionAsync("正在检查游戏目录…", async () =>
        {
            var response = await renderer.RequestAsync("load", new { path });
            vehicles = response.GetProperty("vehicles").Deserialize<List<Vehicle>>(JsonOptions) ?? [];
            selected = null;
            displayed = null;
            paintable = false;
            ViewTitle.Text = "白色摄影棚";
            ViewSubtitle.Text = "选择载具即可预览";
            MeshDetails.Text = "";
            Factory.Items.Clear();
            PartsPanel.Children.Clear();
            partChoices.Clear();
            partsLoaded = false;
            SourceSummary.Text = "Xbox RPF9 · 本地只读";
            ToolTipService.SetToolTip(SourceSummary, response.GetProperty("game").GetString());
            CatalogNote.Text = response.GetProperty("unnamed").GetInt32() is var unnamed && unnamed > 0
                ? $"另有 {unnamed} 条记录未恢复名称。"
                : "所有资源均来自本机。";
            populating = true;
            Search.Text = "";
            Category.ItemsSource = new[] { "全部类别" }.Concat(vehicles.Select(v => v.Category).Distinct().Order()).ToArray();
            Category.SelectedIndex = 0;
            populating = false;
            RefreshVehicles();
            if ((vehicles.FirstOrDefault(v => v.Id == "comet7") ?? vehicles.FirstOrDefault()) is { } first)
            {
                SelectVehicle(first);
                await RenderAsync(0, []);
            }
        });
    }

    private void SearchChanged(object sender, TextChangedEventArgs args) => RefreshVehicles();
    private void FilterChanged(object sender, SelectionChangedEventArgs args) => RefreshVehicles();

    private void RefreshVehicles()
    {
        if (populating || VehicleList is null)
            return;
        var query = Search.Text.Trim();
        var category = Category.SelectedIndex > 0 ? Category.SelectedItem as string : null;
        var filtered = vehicles.Where(v =>
            (category is null || v.Category == category) &&
            (query.Length == 0 || (v.Name + " " + v.Make + " " + v.Id).Contains(query, StringComparison.OrdinalIgnoreCase)))
            .OrderBy(v => v.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
        populating = true;
        VehicleList.ItemsSource = filtered;
        VehicleList.SelectedItem = selected;
        VehicleCount.Text = $"{filtered.Count} / {vehicles.Count}";
        populating = false;
    }

    private async void VehicleSelected(object sender, SelectionChangedEventArgs args)
    {
        if (populating || busy || VehicleList.SelectedItem is not Vehicle vehicle || vehicle == selected)
            return;
        SelectVehicle(vehicle);
        await RunAssetActionAsync("正在生成整车预览…", () => RenderAsync(0, []));
    }

    private void SelectVehicle(Vehicle vehicle)
    {
        selected = vehicle;
        populating = true;
        VehicleList.SelectedItem = vehicle;
        VehicleList.ScrollIntoView(vehicle);
        populating = false;
        Factory.Items.Clear();
        for (var i = 0; i < vehicle.Configurations.Count; i++)
        {
            var color = vehicle.Configurations[i].Color;
            Factory.Items.Add($"配置 {i + 1:00}" + (string.IsNullOrEmpty(color) ? "" : $" · {color}"));
        }
        if (Factory.Items.Count == 0)
            Factory.Items.Add("基础模型");
        Factory.SelectedIndex = 0;
        PartsPanel.Children.Clear();
        partChoices.Clear();
        partsLoaded = false;
        PartsNote.Text = vehicle.Configurations.Count == 0
            ? "此车型没有可组装的原厂配置。"
            : "读取配件后，可按安装槽选择模型。";
    }

    private async void ReadPartsClicked(object sender, RoutedEventArgs args)
    {
        if (selected is not { } vehicle)
            return;
        await RunAssetActionAsync("正在读取可用配件…", async () =>
        {
            var options = await GetPartsAsync(vehicle);
            ShowParts(options, []);
            Report($"已读取 {options.Count} 个可用配件。");
        });
    }

    private async Task<List<PartOption>> GetPartsAsync(Vehicle vehicle)
    {
        var reply = await renderer.RequestAsync("parts", new { model = vehicle.Id });
        return reply.GetProperty("parts").Deserialize<List<PartOption>>(JsonOptions) ?? [];
    }

    private void ShowParts(List<PartOption> parts, string[] picks)
    {
        PartsPanel.Children.Clear();
        partChoices.Clear();
        partsLoaded = true;
        PartsNote.Text = parts.Count > 0 ? "选好配件后点击「更新预览」。" : "未找到有可解析模型的配件。";
        foreach (var group in parts.GroupBy(part => part.Slot))
        {
            var slot = group.First().SlotName?.Replace('_', ' ') ?? $"安装槽 {group.Key}";
            PartsPanel.Children.Add(new TextBlock { Text = slot, FontSize = 12 });
            var combo = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
            combo.Items.Add(new ComboBoxItem { Content = "沿用原厂配置", Tag = "" });
            combo.SelectedIndex = 0;
            foreach (var part in group)
            {
                var label = part.Label.Length > 28 ? part.Label[..25] + "…" : part.Label;
                var item = new ComboBoxItem { Content = label, Tag = part.Id };
                ToolTipService.SetToolTip(item, $"{part.Label} · {part.Id}");
                combo.Items.Add(item);
                if (picks.Contains(part.Id))
                    combo.SelectedItem = item;
            }
            partChoices.Add(combo);
            PartsPanel.Children.Add(combo);
        }
    }

    private async void ApplyClicked(object sender, RoutedEventArgs args)
    {
        var picks = partChoices.Select(combo => (combo.SelectedItem as ComboBoxItem)?.Tag as string)
            .OfType<string>().Where(id => id.Length > 0).ToArray();
        await RunAssetActionAsync("正在重新组装整车…", () => RenderAsync(Factory.SelectedIndex, picks));
    }

    private async Task RenderAsync(int config, string[] parts)
    {
        if (selected is not { } vehicle || config < 0)
            return;
        var reply = await renderer.RequestAsync("preview", new { model = vehicle.Id, config, parts });
        var size = reply.GetProperty("size").EnumerateArray().Select(d => d.GetDouble()).ToArray();
        var issues = reply.GetProperty("issues").GetInt32();
        var baseModel = reply.GetProperty("base").GetBoolean();
        paintable = reply.GetProperty("paintable").GetBoolean();
        displayed = baseModel ? null : new BuildCode(vehicle.Id, config, parts.Order(StringComparer.Ordinal).ToArray());
        ViewTitle.Text = vehicle.Name;
        ViewSubtitle.Text = $"{vehicle.Category}  ·  {vehicle.Subtitle}";
        MeshDetails.Text = $"{reply.GetProperty("meshes").GetInt32()} 组网格 · {size[0]:F2} × {size[1]:F2} × {size[2]:F2} m";
        Report((baseModel ? "已载入基础模型" : "已载入整车预览")
            + (issues > 0 ? $" · SixNG 报告 {issues} 项配件或贴图警告" : ""));
    }

    private Task UpdatePaintAsync()
    {
        PaintColor.IsEnabled = PaintFinish.IsEnabled && PaintFinish.SelectedIndex > 0;
        if (!PaintFinish.IsEnabled)
            return Task.CompletedTask;
        var color = PaintColor.Text.Trim();
        if (PaintColor.IsEnabled && color.Length > 0 && !ColorPattern.IsMatch(color))
        {
            Report("漆色请输入 #RRGGBB，留空使用原车颜色。", error: true);
            return Task.CompletedTask;
        }
        return PostAsync("paint", new { finish = PaintFinish.SelectedIndex, color });
    }

    private void CopyClicked(object sender, RoutedEventArgs args)
    {
        if (displayed is null)
            return;
        var text = Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(displayed, JsonOptions))
            .TrimEnd('=').Replace('+', '-').Replace('/', '_');
        var package = new DataPackage();
        package.SetText("VI1." + text);
        Clipboard.SetContent(package);
        Report("已复制当前预览的改车码。");
    }

    private async void ImportClicked(object sender, RoutedEventArgs args)
    {
        var box = new TextBox { PlaceholderText = "粘贴 VI1. 开头的改车码", MaxLength = 4096, AcceptsReturn = true };
        var editor = new ContentDialog
        {
            Title = "导入改车码", PrimaryButtonText = "应用", CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary, XamlRoot = Shell.XamlRoot, Content = box
        };
        ContentDialogResult answer;
        answer = await editor.ShowAsync();
        if (answer != ContentDialogResult.Primary)
            return;
        await RunAssetActionAsync("正在核对改车码…", async () =>
        {
            var code = ParseCode(box.Text);
            var vehicle = vehicles.FirstOrDefault(v => v.Id == code.Model && code.Config < v.Configurations.Count)
                ?? throw new InvalidOperationException("本地目录中找不到这个车型或配置。");
            var options = code.Parts.Length == 0 ? [] : await GetPartsAsync(vehicle);
            var slots = new HashSet<string>();
            foreach (var pick in code.Parts)
            {
                var option = options.FirstOrDefault(part => part.Id == pick);
                if (option is null || !slots.Add(option.Slot))
                    throw new InvalidOperationException("改车码中有不可用或占用同一安装槽的配件。");
            }
            Search.Text = "";
            Category.SelectedIndex = 0;
            SelectVehicle(vehicle);
            Factory.SelectedIndex = code.Config;
            if (options.Count > 0)
                ShowParts(options, code.Parts);
            await RenderAsync(code.Config, code.Parts);
            Report("已应用改车码。");
        });
    }

    private static BuildCode ParseCode(string input)
    {
        var raw = input.Trim();
        try
        {
            if (!raw.StartsWith("VI1.", StringComparison.Ordinal) || raw.Length > 4096)
                throw new FormatException();
            var data = raw[4..].Replace('-', '+').Replace('_', '/');
            data = data.PadRight((data.Length + 3) / 4 * 4, '=');
            var code = JsonSerializer.Deserialize<BuildCode>(Convert.FromBase64String(data), JsonOptions);
            if (code is null || code.Model is null || !ModelPattern.IsMatch(code.Model) ||
                code.Config < 0 || code.Parts is null || code.Parts.Length > 100 ||
                code.Parts.Any(part => part is null || !PartPattern.IsMatch(part)))
                throw new FormatException();
            return code;
        }
        catch (Exception ex) when (ex is FormatException or JsonException)
        {
            throw new InvalidOperationException("改车码格式无效。", ex);
        }
    }

    private async void PreviewPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        var sample = args.GetCurrentPoint(PreviewSurface);
        var previous = pointerPosition;
        pointerPosition = sample.Position;
        var buttons = (sample.Properties.IsLeftButtonPressed ? 1 : 0)
            | (sample.Properties.IsRightButtonPressed ? 2 : 0)
            | (sample.Properties.IsMiddleButtonPressed ? 4 : 0);
        if (previous is null || (buttons == 0 && Fly.IsChecked != true))
            return;
        var x = sample.Position.X - previous.Value.X;
        var y = sample.Position.Y - previous.Value.Y;
        if (x != 0 || y != 0)
            await PostAsync("camera", new { action = "motion", x, y, buttons });
    }

    private async void StudioKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (Fly.IsChecked != true)
            return;
        if (args.Key == VirtualKey.Escape)
        {
            args.Handled = true;
            await ExitFlyAsync();
            return;
        }
        if (args.Key is not (VirtualKey.W or VirtualKey.A or VirtualKey.S or VirtualKey.D or VirtualKey.Q or VirtualKey.E or VirtualKey.Shift))
            return;
        args.Handled = true;
        if (heldKeys.Add(args.Key))
            await PostAsync("camera", new { action = "key", key = args.Key.ToString(), pressed = true });
    }

    private async void StudioKeyUp(object sender, KeyRoutedEventArgs args)
    {
        if (!heldKeys.Remove(args.Key))
            return;
        args.Handled = true;
        await PostAsync("camera", new { action = "key", key = args.Key.ToString(), pressed = false });
    }

    private Task ExitFlyAsync()
    {
        heldKeys.Clear();
        Fly.IsChecked = false;
        return PostAsync("camera", new { action = "free", enabled = false });
    }

    private async void ResetCamera(object sender, RoutedEventArgs args) => await PostAsync("camera", new { action = "reset" });
    private async void ToggleCamera(object sender, RoutedEventArgs args)
    {
        var toggle = (Microsoft.UI.Xaml.Controls.Primitives.ToggleButton)sender;
        await PostAsync("camera", new { action = toggle.Tag, enabled = toggle.IsChecked == true });
    }

    private async void PresetChanged(object sender, SelectionChangedEventArgs args)
    {
        if (!connected || Preset.SelectedIndex < 0)
            return;
        var index = Preset.SelectedIndex;
        populating = true;
        Antialias.SelectedIndex = index == 0 ? 3 : 7;
        Scale.Value = new[] { 100, 80, 60 }[index];
        Ssr.IsChecked = index < 2;
        Ao.IsChecked = true;
        Ssil.IsChecked = index == 0;
        Bloom.IsChecked = index < 2;
        populating = false;
        await SendQualityAsync();
    }

    private async void RenderModeChanged(object sender, SelectionChangedEventArgs args)
    {
        if (!connected || populating)
            return;
        if (RenderMode.SelectedIndex == 1)
        {
            populating = true;
            DlssSwitch.IsOn = dlssAvailable;
            Scale.Value = dlssAvailable ? 67 : 100;
            populating = false;
        }
        await SendQualityAsync();
    }

    private async void QualityChanged(object sender, RoutedEventArgs args)
    {
        if (connected && !populating)
            await SendQualityAsync();
    }

    private Task SendQualityAsync()
    {
        var path = pathAvailable && RenderMode.SelectedIndex == 1;
        var dlss = dlssAvailable && DlssSwitch.IsOn;
        var reconstruct = path && dlss && rayReconstruction;
        Samples.IsEnabled = path;
        Antialias.IsEnabled = !path && !dlss;
        Ssr.IsEnabled = Ao.IsEnabled = Ssil.IsEnabled = !path;
        GridLines.IsEnabled = !path;
        RayStatus.Text = path
            ? (reconstruct ? "全路径追踪 · DLSS 光线重建" : "全路径追踪 · 原始采样")
            : !pathAvailable ? "纯光栅 · 当前运行时或 GPU 不支持路径追踪"
            : dlss ? "纯光栅 · DLSS 已启用" : "纯光栅 · DLSS " + (dlssAvailable ? "可用" : "不可用");
        return PostAsync("quality", new
        {
            aa = dlss ? 8 : path ? 0 : Antialias.SelectedIndex, scale = Scale.Value / 100,
            ssr = Ssr.IsChecked == true, ao = Ao.IsChecked == true, ssil = Ssil.IsChecked == true,
            bloom = Bloom.IsChecked == true, path_tracing = path, ray_reconstruction = reconstruct,
            samples = new[] { 1, 2, 4, 8 }[Math.Max(0, Samples.SelectedIndex)]
        });
    }

    private void BuildLighting(JsonElement defaults)
    {
        lightDefaults = defaults.EnumerateObject().ToDictionary(
            pair => pair.Name, pair => pair.Value.ValueKind == JsonValueKind.String
                ? (object)pair.Value.GetString()! : pair.Value.GetDouble());
        foreach (var pair in lightDefaults)
            lighting[pair.Key] = pair.Value;
        AddLightSlider("主光强度", "key", 0, 4, .05);
        AddLightSlider("主光方位（°）", "azimuth", -180, 180, 1);
        AddLightSlider("主光高度（°）", "elevation", 15, 85, 1);
        AddLightSlider("主光角直径（°）", "size", 0, 40, .5);
        AddLightSlider("主光高光", "specular", 0, .5, .005);
        AddLightSlider("顶灯强度", "fill", 0, 1.5, .01);
        AddLightSlider("环境光", "ambient", 0, 1.5, .02);
        AddLightSlider("曝光", "exposure", .35, 2.7, .025);
        AddLightSlider("地面粗糙度", "floor_roughness", .08, .90, .01);
        AddLightColor("主光色", "light_color");
        AddLightColor("背景色", "background_color");
        var savedColor = preferences.FloorColor;
        SetFloorPicker(savedColor is not null && ColorPattern.IsMatch(savedColor) ? savedColor : (string)lightDefaults["floor_color"]);
    }

    private void SetFloorPicker(string hex)
    {
        lighting["floor_color"] = hex;
        FloorColorButton.Content = "地面颜色 · " + hex.ToUpperInvariant();
        var rgb = Convert.ToUInt32(hex[1..], 16);
        FloorPicker.Color = Windows.UI.Color.FromArgb(255, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
    }

    private async void FloorColorChanged(ColorPicker sender, ColorChangedEventArgs args)
    {
        if (!connected || populating || !lighting.ContainsKey("floor_color"))
            return;
        var color = args.NewColor;
        var hex = $"#{color.R:X2}{color.G:X2}{color.B:X2}";
        lighting["floor_color"] = hex;
        FloorColorButton.Content = "地面颜色 · " + hex;
        preferences = preferences with { FloorColor = hex };
        SavePreferences();
        await PostAsync("lighting", lighting);
    }

    private void AddLightSlider(string title, string key, double min, double max, double step)
    {
        var slider = new Slider { Header = title, Minimum = min, Maximum = max, StepFrequency = step,
            Value = (double)lightDefaults[key], IsThumbToolTipEnabled = true };
        slider.ValueChanged += async (_, e) =>
        {
            lighting[key] = e.NewValue;
            if (!populating)
                await PostAsync("lighting", lighting);
        };
        lightSliders[key] = slider;
        LightingPanel.Children.Add(slider);
    }

    private void AddLightColor(string title, string key)
    {
        var color = new TextBox { Header = $"{title} · #RRGGBB", Text = (string)lightDefaults[key], MaxLength = 7 };
        color.LostFocus += async (_, _) =>
        {
            if (!Regex.IsMatch(color.Text, "^#[0-9a-fA-F]{6}$", RegexOptions.CultureInvariant))
            {
                color.Text = (string)lighting[key];
                return;
            }
            lighting[key] = color.Text;
            await PostAsync("lighting", lighting);
        };
        lightColors[key] = color;
        LightingPanel.Children.Add(color);
    }

    private async void ResetLighting(object sender, RoutedEventArgs args)
    {
        populating = true;
        foreach (var (key, value) in lightDefaults)
        {
            if (lightSliders.TryGetValue(key, out var slider))
                slider.Value = (double)value;
            else if (key == "floor_color")
                SetFloorPicker((string)value);
            else
                lightColors[key].Text = (string)value;
            lighting[key] = value;
        }
        populating = false;
        preferences = preferences with { FloorColor = "" };
        SavePreferences();
        await PostAsync("lighting", lighting);
    }

    private async void ToggleSettings(object sender, RoutedEventArgs args)
    {
        bool open = SettingsPage.Visibility != Visibility.Visible;
        if (open && Fly.IsChecked == true)
            await ExitFlyAsync();
        StudioPage.Visibility = open ? Visibility.Collapsed : Visibility.Visible;
        SettingsPage.Visibility = open ? Visibility.Visible : Visibility.Collapsed;
        SettingsButton.Content = open ? "返回车库" : "设置";
    }

    private void LoadPreferences()
    {
        if (File.Exists(preferencePath))
        {
            try { preferences = JsonSerializer.Deserialize<Preferences>(File.ReadAllText(preferencePath!), JsonOptions) ?? new(); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException) { }
        }
        ThemeChoice.SelectedIndex = Math.Clamp(preferences.Theme, 0, 2);
        MicaSwitch.IsOn = preferences.Mica;
        LampSwitch.IsOn = preferences.Lamps;
        GridLines.IsOn = preferences.Grid;
        appearanceReady = true;
        ApplyAppearance();
    }

    private void SavePreferences()
    {
        if (preferencePath is null)
            return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(preferencePath)!);
            var staging = preferencePath + ".tmp";
            File.WriteAllText(staging, JsonSerializer.Serialize(preferences, JsonOptions));
            File.Move(staging, preferencePath, overwrite: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    private void ApplyAppearance()
    {
        Shell.RequestedTheme = ThemeChoice.SelectedIndex switch
        {
            1 => ElementTheme.Light,
            2 => ElementTheme.Dark,
            _ => ElementTheme.Default
        };
        SystemBackdrop = MicaSwitch.IsOn ? SystemBackdrop as MicaBackdrop ?? new MicaBackdrop() : null;
        SolidBackdrop.Visibility = MicaSwitch.IsOn ? Visibility.Collapsed : Visibility.Visible;
        UpdateTitleTheme();
    }

    private void UpdateTitleTheme()
    {
        if (AppWindowTitleBar.IsCustomizationSupported())
            AppWindow.TitleBar.PreferredTheme = Shell.ActualTheme == ElementTheme.Dark ? TitleBarTheme.Dark : TitleBarTheme.Light;
    }

    private void AppearanceChanged(object sender, RoutedEventArgs args)
    {
        if (!appearanceReady)
            return;
        preferences = preferences with { Theme = ThemeChoice.SelectedIndex, Mica = MicaSwitch.IsOn };
        ApplyAppearance();
        SavePreferences();
    }

    private async void PreviewPreferenceChanged(object sender, RoutedEventArgs args)
    {
        if (!appearanceReady)
            return;
        preferences = preferences with { Lamps = LampSwitch.IsOn, Grid = GridLines.IsOn };
        SavePreferences();
        await ApplyPreviewPreferencesAsync();
    }

    private async Task ApplyPreviewPreferencesAsync()
    {
        await PostAsync("lamps", new { enabled = LampSwitch.IsOn });
        await PostAsync("camera", new { action = "grid", enabled = GridLines.IsOn });
        await PostAsync("lighting", lighting);
    }

    private async Task PostAsync(string command, object data)
    {
        if (!connected || closing)
            return;
        try { await renderer.PostAsync(command, data); }
        catch (Exception ex) when (ex is IOException or OperationCanceledException or InvalidOperationException)
        {
            if (!closing)
                Report(ex.Message, error: true);
        }
    }

    private async Task RunAssetActionAsync(string message, Func<Task> action)
    {
        if (!connected || busy)
            return;
        SetBusy(true);
        Report(message);
        try { await action(); }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            if (!closing)
                Report(ex.Message, error: true);
        }
        finally { SetBusy(false); }
    }

    private void SetBusy(bool value)
    {
        busy = value;
        OpenFolder.IsEnabled = connected && !busy;
        VehicleList.IsEnabled = connected && !busy;
        Factory.IsEnabled = !busy && selected?.Configurations.Count > 0;
        PaintFinish.IsEnabled = connected && !busy && paintable;
        PaintColor.IsEnabled = PaintFinish.IsEnabled && PaintFinish.SelectedIndex > 0;
        Apply.IsEnabled = !busy && selected is not null;
        ReadParts.IsEnabled = !busy && !partsLoaded && selected?.Configurations.Count > 0;
        CopyCode.IsEnabled = !busy && displayed is not null;
        ImportCode.IsEnabled = !busy && vehicles.Count > 0;
        foreach (var control in partChoices)
            control.IsEnabled = !busy;
    }

    private void Report(string text, double progress = -1, bool error = false)
    {
        Status.Text = text;
        if (error)
            Status.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.IndianRed);
        else
            Status.ClearValue(TextBlock.ForegroundProperty);
        ToolTipService.SetToolTip(Status, text);
        Progress.Visibility = progress >= 0 ? Visibility.Visible : Visibility.Collapsed;
        Progress.Value = Math.Max(0, progress);
    }

    public sealed record Vehicle(string Id, string Name, string Make, string Category, List<FactoryOption> Configurations)
    {
        public string Subtitle => string.IsNullOrEmpty(Make) ? Id : $"{Make} · {Id}";
    }

    public sealed record FactoryOption(string? Color, int Count);
    private sealed record PartOption(string Id, string Slot, [property: System.Text.Json.Serialization.JsonPropertyName("slot_name")] string? SlotName, string Label);
    private sealed record BuildCode(string Model, int Config, string[] Parts);
    private sealed record Preferences(int Theme = 0, bool Mica = true, bool Lamps = true, bool Grid = false, string FloorColor = "");
}
