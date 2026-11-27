using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Numerics;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
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
    private readonly bool safeMode = Arguments.Contains("--safe-mode");
    private readonly RendererClient renderer = new();
    private readonly List<ComboBox> partChoices = new();
    private readonly Dictionary<string, Slider> lightSliders = new();
    private readonly Dictionary<string, TextBox> lightColors = new();
    private readonly Dictionary<string, object> lighting = new();
    private Dictionary<string, object> lightDefaults = new();
    private IReadOnlyList<Vehicle> vehicles = [];
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
    private bool assemblingVehicle;
    private bool applyingParts;
    private readonly SemaphoreSlim assetGate = new(1);
    private BuildCode? pendingParts;
    private bool preparingPathFrame;
    private WriteableBitmap? previewBitmap;
    private (int Width, int Height) previewSize;
    private readonly DispatcherTimer fpsTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly Stopwatch fpsClock = new();
    private int framesPresented;
    private string? projectFolder;
    private bool savingScreenshot;
    private bool applyingGraphics;
    private int graphicsRevision;
    private IReadOnlyList<AaChoice> aaMethods = [];
    private IReadOnlyList<AaTier> aaTiers = [];
    private readonly Dictionary<AaMethod, int> selectedTiers = new();
    private Point? pointerPosition;
    private readonly HashSet<VirtualKey> heldKeys = new();

    public MainWindow()
    {
        InitializeComponent();
        fpsTimer.Tick += (_, _) => UpdateFps();
        Shell.ActualThemeChanged += (_, _) => UpdateTitleTheme();
        foreach (var button in new[] { OpenFolder, SettingsButton, ReadParts, CopyCode, ImportCode })
            button.Click += (_, _) => StudioMotion.Pressed(button);
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
        Title = "Leonida Customs";
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "leonida.ico"));
        AppWindow.Closing += async (_, args) =>
        {
            if (closing)
                return;
            args.Cancel = true;
            closing = true;
            fpsTimer.Stop();
            await renderer.CloseAsync();
            Close();
        };
    }

    private async void ShellLoaded(object sender, RoutedEventArgs args)
    {
        if (started)
            return;
        started = true;
        StudioMotion.Enter(WorkshopMark, new Vector3(-9, 0, 0), 260);
        var scale = Shell.XamlRoot.RasterizationScale;
        var workArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        var width = Math.Min((int)Math.Round(1400 * scale), workArea.Width - 24);
        var height = Math.Min((int)Math.Round(850 * scale), workArea.Height - 22);
        AppWindow.MoveAndResize(new RectInt32(workArea.X + (workArea.Width - width) / 2,
            workArea.Y + (workArea.Height - height) / 2, width, height));
        Shell.XamlRoot.Changed += async (_, _) => await ResizePreviewAsync();
        SetBusy(true);
        try
        {
            var root = projectFolder = LocateProject();
            preferencePath = Path.Combine(root, "work", "viewer-preferences.json");
            LoadPreferences();
            renderer.Notification += message => DispatcherQueue.TryEnqueue(() => OnRendererEvent(message));
            renderer.FrameReceived += frame =>
            {
                if (!DispatcherQueue.TryEnqueue(() => _ = PresentFrameAsync(frame)))
                    frame.Dispose();
            };
            renderer.Disconnected += message => DispatcherQueue.TryEnqueue(() =>
            {
                connected = false;
                fpsTimer.Stop();
                FpsLabel.Text = "";
                ApplyGraphicsButton.IsEnabled = false;
                preparingPathFrame = false;
                UpdatePreviewLoading();
                SetBusy(false);
                Report(message, error: true);
            });
            var hello = await renderer.StartAsync(root, safeMode);
            var hidden = RendererWindow.TryHide(renderer.ProcessId);
            for (var attempt = 0; !hidden && attempt < 20; attempt++)
            {
                await Task.Delay(50);
                hidden = RendererWindow.TryHide(renderer.ProcessId);
            }
            if (!hidden)
                throw new InvalidOperationException("未能隐藏渲染辅助窗口。");

            connected = true;
            var capabilities = hello.GetProperty("capabilities");
            pathAvailable = capabilities.GetProperty("path_tracing").GetBoolean();
            dlssAvailable = capabilities.GetProperty("dlss").GetBoolean();
            rayReconstruction = capabilities.GetProperty("ray_reconstruction").GetBoolean();
            PathTracingSwitch.IsEnabled = pathAvailable;
            populating = true;
            BuildLighting(hello.GetProperty("lighting"));
            ApplyGraphicsPreferences(Arguments.Contains("--ray-tracing"));
            populating = false;
            await ApplyGraphicsAsync(save: false);
            await ApplyPreviewPreferencesAsync();
            await ResizePreviewAsync();
            fpsClock.Restart();
            fpsTimer.Start();
            await PostAsync("frame_ack", new { });
            SetBusy(false);
            var saved = Arguments.FirstOrDefault(arg => arg.StartsWith("--game=", StringComparison.Ordinal))?[7..]
                ?? (safeMode ? null : hello.GetProperty("saved_game").GetString());
            if (!string.IsNullOrWhiteSpace(saved))
                await LoadGameAsync(saved);
            else
                Report("用「打开游戏目录」选择自己的 Xbox 版资源。需要帮助时点右上角「帮助」。");
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            connected = false;
            if (closing)
                return;
            SetBusy(false);
            renderer.Dispose();
            RenderPanel.Visibility = Visibility.Collapsed;
            Report(ex is OperationCanceledException ? "预览进程启动超时。可使用安全模式或从「帮助」打开日志。" : ex.Message, error: true);
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
                preparingPathFrame = message.GetProperty("active").GetBoolean();
                UpdatePreviewLoading();
                break;
        }
    }

    private Task ResizePreviewAsync()
    {
        if (PreviewSurface.XamlRoot is null || PreviewSurface.ActualWidth < 8 || PreviewSurface.ActualHeight < 8)
            return Task.CompletedTask;
        var scale = PreviewSurface.XamlRoot.RasterizationScale;
        var width = (int)Math.Round(PreviewSurface.ActualWidth * scale);
        var height = (int)Math.Round(PreviewSurface.ActualHeight * scale);
        if (!connected || (width, height) == previewSize)
            return Task.CompletedTask;
        previewSize = (width, height);
        var fit = Math.Min(1, Math.Min(16384.0 / Math.Max(width, height), Math.Sqrt(RendererClient.MaxFramePixels / ((double)width * height))));
        if (fit < 1)
        {
            width = (int)Math.Floor(width * fit);
            height = (int)Math.Floor(height * fit);
        }
        return PostAsync("resize", new { width, height });
    }

    private async Task PresentFrameAsync(PreviewFrame frame)
    {
        try
        {
            if (!closing && !assemblingVehicle && !applyingParts)
            {
                if (previewBitmap is null || previewBitmap.PixelWidth != frame.Width || previewBitmap.PixelHeight != frame.Height)
                {
                    previewBitmap = new WriteableBitmap(frame.Width, frame.Height);
                    PreviewImage.Source = previewBitmap;
                }
                using var pixels = previewBitmap.PixelBuffer.AsStream();
                pixels.Write(frame.Pixels.Span);
                previewBitmap.Invalidate();
                framesPresented++;
                ScreenshotButton.IsEnabled = !savingScreenshot;
            }
        }
        catch (Exception ex) when (ex is FormatException or IOException or System.Runtime.InteropServices.COMException)
        {
            Report("无法显示渲染画面。", error: true);
        }
        finally
        {
            frame.Dispose();
            await PostAsync("frame_ack", new { });
        }
    }

    private void UpdateFps()
    {
        var seconds = fpsClock.Elapsed.TotalSeconds;
        if (seconds > 0 && previewBitmap is not null)
            FpsLabel.Text = $"{framesPresented / seconds:F0} FPS";
        framesPresented = 0;
        fpsClock.Restart();
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
            partChoices.Clear();
            PartsPanel.Children.Clear();
            partsLoaded = false;
            SourceSummary.Text = "Xbox RPF9 · 本地只读";
            ToolTipService.SetToolTip(SourceSummary, response.GetProperty("game").GetString());
            VehicleInfo.Text = "";
            PerformancePanel.Children.Clear();
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
                await LoadPartsAndRenderAsync(first, 0);
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
            (query.Length == 0 || (v.Name + " " + v.Make + " " + v.EnglishName + " " + v.EnglishMake + " " + v.Id).Contains(query, StringComparison.OrdinalIgnoreCase)))
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
        await RunAssetActionAsync("正在读取配置和改装配件…", () => LoadPartsAndRenderAsync(vehicle, 0));
    }

    private void SelectVehicle(Vehicle vehicle)
    {
        selected = vehicle;
        populating = true;
        Search.Text = "";
        Category.SelectedItem = vehicle.Category;
        Factory.Items.Clear();
        for (var i = 0; i < vehicle.Configurations.Count; i++)
        {
            var color = vehicle.Configurations[i].Color;
            Factory.Items.Add($"配置 {i + 1:00}" + (string.IsNullOrEmpty(color) ? "" : $" · {color}"));
        }
        if (Factory.Items.Count == 0)
            Factory.Items.Add("基础模型");
        Factory.SelectedIndex = 0;
        populating = false;
        RefreshVehicles();
        VehicleList.ScrollIntoView(vehicle);
        ShowVehicleData(vehicle);
        partChoices.Clear();
        PartsPanel.Children.Clear();
        partsLoaded = false;
        ReadParts.Visibility = Visibility.Collapsed;
        PartsNote.Text = vehicle.Configurations.Count == 0
            ? "此车型没有可组装的原厂配置。"
            : "正在读取可用配件…";
        StudioMotion.Enter(VehicleOptions, new Vector3(0, 9, 0), 175);
    }

    private void ShowVehicleData(Vehicle vehicle)
    {
        var data = new List<string>();
        if (vehicle.Drive is { Length: > 0 } drive)
            data.Add(drive);
        if (vehicle.Gears is > 0)
            data.Add($"{vehicle.Gears} 速");
        if (vehicle.Mass is > 0)
            data.Add($"{vehicle.Mass:N0} kg");
        if (vehicle.RoadRating.HasValue)
            data.Add($"公路评级 {vehicle.RoadRating}");
        if (vehicle.DirtRating.HasValue)
            data.Add($"越野评级 {vehicle.DirtRating}");
        VehicleInfo.Text = data.Count == 0 ? "暂无本地车辆数据" : string.Join(" · ", data);
        PerformancePanel.Children.Clear();
        var ratings = new (string Name, double? Value)[]
        {
            ("速度", vehicle.Speed),
            ("加速", vehicle.Acceleration),
            ("柏油路操控性", vehicle.RoadHandling),
            ("越野操控性", vehicle.OffroadHandling),
            ("强度", vehicle.Strength)
        };
        foreach (var (name, value) in ratings)
        {
            var row = new Grid();
            row.Children.Add(new TextBlock { Text = name, FontSize = 12 });
            row.Children.Add(new TextBlock { Text = value is double score ? score.ToString("F1") : "—",
                FontSize = 12, HorizontalAlignment = HorizontalAlignment.Right });
            var bar = new ProgressBar { Minimum = 0, Maximum = 10, Value = value ?? 0, Opacity = value.HasValue ? 1 : .5 };
            PerformancePanel.Children.Add(row);
            PerformancePanel.Children.Add(bar);
        }
    }

    private async void FactoryChanged(object sender, SelectionChangedEventArgs args)
    {
        if (populating || busy || selected is not { } vehicle || Factory.SelectedIndex < 0)
            return;
        int index = Factory.SelectedIndex;
        await RunAssetActionAsync("正在加载原厂配置和改装配件…", () => LoadPartsAndRenderAsync(vehicle, index));
    }

    private async Task LoadPartsAndRenderAsync(Vehicle vehicle, int config)
    {
        if (vehicle.Configurations.Count > 0)
            await LoadPartsForConfigAsync(vehicle, config);
        await RenderAsync(config, []);
    }

    private async Task LoadPartsForConfigAsync(Vehicle vehicle, int config)
    {
        PartsNote.Text = "正在读取可用配件…";
        partChoices.Clear();
        PartsPanel.Children.Clear();
        partsLoaded = false;
        ReadParts.Visibility = Visibility.Collapsed;
        try
        {
            ShowParts(await GetPartsAsync(vehicle), [], config);
        }
        catch (InvalidOperationException ex)
        {
            PartsNote.Text = "读取配件失败 · " + ex.Message;
            ReadParts.Visibility = Visibility.Visible;
        }
    }

    private async void ReadPartsClicked(object sender, RoutedEventArgs args)
    {
        if (selected is not { } vehicle || Factory.SelectedIndex < 0)
            return;
        int config = Factory.SelectedIndex;
        await RunAssetActionAsync("正在读取可用配件…", () => LoadPartsForConfigAsync(vehicle, config));
    }

    private async Task<List<PartOption>> GetPartsAsync(Vehicle vehicle)
    {
        var reply = await renderer.RequestAsync("parts", new { model = vehicle.Id });
        return reply.GetProperty("parts").Deserialize<List<PartOption>>(JsonOptions) ?? [];
    }

    private void ShowParts(List<PartOption> parts, string[] picks, int config)
    {
        partChoices.Clear();
        PartsPanel.Children.Clear();
        partsLoaded = true;
        PartsNote.Text = parts.Count > 0 ? "选中配件后自动应用到预览。" : "未找到有可解析模型的配件。";
        foreach (var group in parts.GroupBy(part => part.Slot))
        {
            var slot = PartLabels.Slot(group.First().SlotName, group.Key);
            PartsPanel.Children.Add(new TextBlock { Text = slot, FontSize = 12 });
            var combo = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
            var options = group.Select((part, index) => (Part: part, Title: PartLabels.Option(slot, part.Label, index + 1))).ToArray();
            var stock = options.FirstOrDefault(option => option.Part.StockConfigs?.Contains(config) == true);
            var stockItem = new ComboBoxItem { Content = stock.Part is null ? "沿用原厂配置" : $"原厂 · {stock.Title}", Tag = "" };
            if (stock.Part is not null)
                ToolTipService.SetToolTip(stockItem, $"{stock.Part.Label} · {stock.Part.Id}");
            combo.Items.Add(stockItem);
            combo.SelectedIndex = 0;
            foreach (var (part, title) in options)
            {
                var item = new ComboBoxItem { Content = title, Tag = part.Id };
                ToolTipService.SetToolTip(item, $"{part.Label} · {part.Id}");
                combo.Items.Add(item);
                if (picks.Contains(part.Id))
                    combo.SelectedItem = item;
            }
            combo.SelectionChanged += PartChanged;
            partChoices.Add(combo);
            PartsPanel.Children.Add(combo);
        }
        if (partChoices.Count > 0)
            StudioMotion.Enter(PartsPanel, new Vector3(0, 8, 0), 175);
    }

    private async void PartChanged(object sender, SelectionChangedEventArgs args)
    {
        if (populating || busy || !connected || sender is not ComboBox combo || !partChoices.Contains(combo)
            || selected is not { } vehicle || Factory.SelectedIndex < 0)
            return;
        var picks = partChoices.Select(choice => (choice.SelectedItem as ComboBoxItem)?.Tag as string)
            .OfType<string>().Where(id => id.Length > 0).ToArray();
        pendingParts = new BuildCode(vehicle.Id, Factory.SelectedIndex, picks);
        if (applyingParts)
            return;

        applyingParts = true;
        UpdatePreviewLoading();
        UpdateAssetControls();

        await assetGate.WaitAsync();
        try
        {
            while (pendingParts is { } next && connected && !busy && !closing)
            {
                pendingParts = null;
                try { await RenderAsync(next.Config, next.Parts); }
                catch (Exception ex) when (ex is not OutOfMemoryException)
                {
                    if (!busy && !closing && pendingParts is null)
                    {
                        RestoreDisplayedParts(next);
                        Report(ex.Message, error: true);
                    }
                }
            }
        }
        finally
        {
            assetGate.Release();
            applyingParts = false;
            UpdatePreviewLoading();
            UpdateAssetControls();
        }
    }

    private void RestoreDisplayedParts(BuildCode request)
    {
        string[] parts = displayed is { } current && current.Model == request.Model && current.Config == request.Config
            ? current.Parts : [];
        populating = true;
        foreach (var combo in partChoices)
            combo.SelectedItem = combo.Items.OfType<ComboBoxItem>()
                .FirstOrDefault(item => item.Tag is string id && parts.Contains(id)) ?? combo.Items[0];
        populating = false;
    }

    private async Task RenderAsync(int config, string[] parts)
    {
        if (selected is not { } vehicle || config < 0)
            return;
        assemblingVehicle = true;
        UpdatePreviewLoading();
        JsonElement reply;
        try
        {
            reply = await renderer.RequestAsync("preview", new { model = vehicle.Id, config, parts });
        }
        finally
        {
            assemblingVehicle = false;
            UpdatePreviewLoading();
        }
        if (closing || selected != vehicle || Factory.SelectedIndex != config)
            return;
        var size = reply.GetProperty("size").EnumerateArray().Select(d => d.GetDouble()).ToArray();
        var issues = reply.GetProperty("issues").GetInt32();
        var baseModel = reply.GetProperty("base").GetBoolean();
        paintable = reply.GetProperty("paintable").GetBoolean();
        displayed = baseModel ? null : new BuildCode(vehicle.Id, config, parts.Order(StringComparer.Ordinal).ToArray());
        ViewTitle.Text = vehicle.Name;
        ViewSubtitle.Text = $"{vehicle.Category}  ·  {vehicle.Subtitle}";
        if (!applyingParts)
            StudioMotion.Enter(VehicleHeading, new Vector3(0, 7, 0), 175);
        MeshDetails.Text = $"{reply.GetProperty("meshes").GetInt32()} 组网格 · {size[0]:F2} × {size[1]:F2} × {size[2]:F2} m";
        var requestedWarnings = reply.GetProperty("requestedWarnings").EnumerateArray()
            .Select(warning => warning.GetString()).OfType<string>().ToArray();
        ToolTipService.SetToolTip(MeshDetails, requestedWarnings.Length == 0 ? null : string.Join("\n", requestedWarnings));
        Report((baseModel ? "已载入基础模型" : "已载入整车预览")
            + (requestedWarnings.Length > 0 ? $" · 所选配件有 {requestedWarnings.Length} 个组件未装上" :
                issues > 0 ? $" · SixNG 报告 {issues} 项配件或贴图警告" : ""));
    }

    private void UpdatePreviewLoading()
    {
        bool loading = assemblingVehicle || applyingParts || preparingPathFrame;
        bool wasVisible = PreviewLoading.Visibility == Visibility.Visible;
        PreviewLoading.Visibility = loading ? Visibility.Visible : Visibility.Collapsed;
        PreviewSpinner.IsActive = loading && StudioMotion.Enabled;
        if (loading)
        {
            PreviewLoadingText.Text = applyingParts ? "正在应用配件…" : assemblingVehicle ? "正在组装载具预览…" : "正在准备路径追踪画面…";
            if (!wasVisible)
                StudioMotion.Enter(PreviewLoading, new Vector3(0, -6, 0), 160);
        }
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
            List<PartOption> options = code.Parts.Length > 0 ? await GetPartsAsync(vehicle) : [];
            var slots = new HashSet<string>();
            foreach (var pick in code.Parts)
            {
                var option = options.FirstOrDefault(part => part.Id == pick);
                if (option is null || !slots.Add(option.Slot))
                    throw new InvalidOperationException("改车码中有不可用或占用同一安装槽的配件。");
            }
            SelectVehicle(vehicle);
            Factory.SelectedIndex = code.Config;
            if (code.Parts.Length == 0)
                await LoadPartsForConfigAsync(vehicle, code.Config);
            else
                ShowParts(options, code.Parts, code.Config);
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

    private bool PathSelected => pathAvailable && PathTracingSwitch.IsOn;

    private void PopulateAaMethods(AaMethod wanted)
    {
        var methods = new List<AaChoice>
        {
            new(AaMethod.None, "关闭"),
            new(AaMethod.Fxaa, "FXAA"),
            new(AaMethod.Smaa, "SMAA"),
            new(AaMethod.Taa, "TAA"),
            new(AaMethod.Msaa, "MSAA"),
            new(AaMethod.Fsr2, "AMD FSR 2.2")
        };
        if (dlssAvailable)
            methods.Add(new(AaMethod.Dlss, "NVIDIA DLSS 4.5"));

        aaMethods = methods;
        Antialias.ItemsSource = methods.Select(choice => choice.Label).ToArray();
        Antialias.SelectedIndex = Math.Max(0, methods.FindIndex(choice => choice.Method == wanted));
        PopulateAaTiers();
    }

    private void PopulateAaTiers()
    {
        var method = aaMethods[Antialias.SelectedIndex].Method;
        aaTiers = method switch
        {
            AaMethod.Dlss => [
                new("DLAA · 原生 (100%)", 8, 1.0),
                new("质量 (67%)", 8, 0.67),
                new("平衡 (58%)", 8, 0.58),
                new("性能 (50%)", 8, 0.50)
            ],
            AaMethod.Fsr2 => [
                new("原生 AA (100%)", 7, 1.0),
                new("超高质量 (77%)", 7, 0.77),
                new("质量 (67%)", 7, 0.67),
                new("平衡 (59%)", 7, 0.59),
                new("性能 (50%)", 7, 0.50)
            ],
            AaMethod.Msaa => [
                new("2×", 4, 1.0),
                new("4×", 5, 1.0),
                new("8×", 6, 1.0)
            ],
            _ => [new("原生 (100%)", (int)method, 1.0)]
        };
        AaQuality.ItemsSource = aaTiers.Select(tier => tier.Label).ToArray();
        AaQuality.IsEnabled = aaTiers.Count > 1;
        var defaultTier = method == AaMethod.Msaa ? 1 : 0;
        AaQuality.SelectedIndex = Math.Clamp(selectedTiers.GetValueOrDefault(method, defaultTier), 0, aaTiers.Count - 1);
    }

    private void AaMethodChanged(object sender, SelectionChangedEventArgs args)
    {
        if (!connected || populating || Antialias.SelectedIndex < 0)
            return;
        populating = true;
        PopulateAaTiers();
        populating = false;
        MarkGraphicsPending();
    }

    private void AaQualityChanged(object sender, SelectionChangedEventArgs args)
    {
        if (!connected || populating || AaQuality.SelectedIndex < 0 || Antialias.SelectedIndex < 0)
            return;
        selectedTiers[aaMethods[Antialias.SelectedIndex].Method] = AaQuality.SelectedIndex;
        MarkGraphicsPending();
    }

    private void QualityChanged(object sender, RoutedEventArgs args)
    {
        if (connected && !populating)
            MarkGraphicsPending();
    }

    private void ApplyGraphicsPreferences(bool requestPath = false, bool reset = false)
    {
        var options = safeMode || reset ? new() : preferences.Graphics ?? new();
        PathTracingSwitch.IsOn = pathAvailable && (requestPath || options.Path);
        PathQuality.SelectedIndex = Math.Clamp(options.PathQuality, 0, 3);
        AaMethod legacy = options.Path || (requestPath && preferences.Graphics is null) ? options.PathAa : options.RasterAa;
        var method = options.AntialiasMethod ?? legacy;
        selectedTiers.Clear();
        foreach (var tier in (options.Tiers ?? []).OrderBy(tier => tier.Path == options.Path))
            selectedTiers[tier.Method] = tier.Index;
        Ssr.IsChecked = options.Reflections;
        Ao.IsChecked = options.Occlusion;
        Ssil.IsChecked = options.IndirectLight;
        Bloom.IsChecked = options.Bloom;
        UncapPreview.IsChecked = options.UncapPreview;
        PopulateAaMethods(Enum.IsDefined(method) ? method : AaMethod.Taa);
    }

    private void MarkGraphicsPending()
    {
        graphicsRevision++;
        UpdateGraphicsControls();
        ApplyGraphicsButton.IsEnabled = !applyingGraphics;
        GraphicsStatus.Text = "有未应用的画质设置。";
    }

    private void ResetGraphics(object sender, RoutedEventArgs args)
    {
        if (!connected)
            return;
        populating = true;
        ApplyGraphicsPreferences(reset: true);
        populating = false;
        MarkGraphicsPending();
    }

    private async void ApplyGraphicsClicked(object sender, RoutedEventArgs args)
    {
        if (!connected || applyingGraphics)
            return;
        applyingGraphics = true;
        ApplyGraphicsButton.IsEnabled = false;
        GraphicsStatus.Text = "正在应用画质…";
        try
        {
            await ApplyGraphicsAsync(save: !safeMode);
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or OperationCanceledException)
        {
            if (!closing)
            {
                GraphicsStatus.Text = "画质未确认应用。";
                ApplyGraphicsButton.IsEnabled = connected;
                Report(ex.Message, error: true);
            }
        }
        finally
        {
            applyingGraphics = false;
        }
    }

    private void UpdateGraphicsControls()
    {
        bool path = PathSelected;
        PathQuality.IsEnabled = path;
        Ssr.IsEnabled = Ao.IsEnabled = Ssil.IsEnabled = !path;
        RayStatus.Text = !pathAvailable ? "当前运行时或 GPU 不支持路径追踪。" :
            path && aaMethods.ElementAtOrDefault(Antialias.SelectedIndex)?.Method == AaMethod.Msaa
                ? "MSAA 只处理光栅几何，当前路径追踪画面不会使用它。" : "";
    }

    private async Task ApplyGraphicsAsync(bool save)
    {
        UpdateGraphicsControls();
        int revision = graphicsRevision;
        bool path = PathSelected;
        var method = aaMethods[Antialias.SelectedIndex];
        var tier = aaTiers[AaQuality.SelectedIndex];
        bool reconstruct = path && tier.EngineMode == 8 && rayReconstruction;
        var settings = new GraphicsPreferences(Path: path, PathQuality: PathQuality.SelectedIndex,
            Reflections: Ssr.IsChecked == true, Occlusion: Ao.IsChecked == true,
            IndirectLight: Ssil.IsChecked == true, Bloom: Bloom.IsChecked == true,
            Tiers: selectedTiers.Select(tier => new SavedTier(path, tier.Key, tier.Value)).ToArray(),
            UncapPreview: UncapPreview.IsChecked == true, AntialiasMethod: method.Method);
        var reply = await renderer.RequestAsync("quality", new
        {
            aa = tier.EngineMode, scale = tier.Scale,
            ssr = settings.Reflections, ao = settings.Occlusion, ssil = settings.IndirectLight,
            bloom = settings.Bloom, path_tracing = path, ray_reconstruction = reconstruct,
            samples = 1 << Math.Max(0, settings.PathQuality), uncapped = settings.UncapPreview
        });
        bool actualPath = reply.GetProperty("path_tracing").GetBoolean();
        GridLines.IsEnabled = !actualPath;
        if (save)
        {
            preferences = preferences with { Graphics = settings };
            SavePreferences();
        }

        ApplyGraphicsButton.IsEnabled = revision != graphicsRevision;
        if (revision == graphicsRevision)
        {
            double scale = reply.GetProperty("scale").GetDouble();
            bool capped = reply.GetProperty("fps_limit").GetInt32() != 0;
            string mode = actualPath ? (reconstruct ? "全路径追踪 · 光线重建" : "全路径追踪") : "纯光栅";
            string methodLabel = method.Method is AaMethod.Dlss or AaMethod.Fsr2 or AaMethod.Msaa
                ? $"{method.Label} · {tier.Label.Split('(', 2)[0].TrimEnd()}" : method.Label;
            if (reply.GetProperty("aa").GetInt32() != tier.EngineMode)
                methodLabel += "（当前不生效）";
            GraphicsStatus.Text = $"已应用 {mode} · {methodLabel} · 3D 比例设定 {scale:P0} · "
                + (capped ? "预览上限 30 FPS" : "预览限帧已关闭");
        }
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
        StudioPage.Visibility = open ? Visibility.Collapsed : Visibility.Visible;
        SettingsPage.Visibility = open ? Visibility.Visible : Visibility.Collapsed;
        SettingsButton.Content = open ? "返回车库" : "设置";
        StudioMotion.Enter(open ? SettingsPage : StudioPage, new Vector3(open ? 16 : -16, 0, 0));
        if (open && Fly.IsChecked == true)
            await ExitFlyAsync();
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
        bool mica = MicaSwitch.IsOn && OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000);
        MicaSwitch.IsEnabled = OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000);
        SystemBackdrop = mica ? SystemBackdrop as MicaBackdrop ?? new MicaBackdrop() : null;
        SolidBackdrop.Visibility = mica ? Visibility.Collapsed : Visibility.Visible;
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
        pendingParts = null;
        Report(message);
        await assetGate.WaitAsync();
        try
        {
            if (connected && !closing)
                await action();
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            if (!closing)
                Report(ex.Message, error: true);
        }
        finally
        {
            assetGate.Release();
            SetBusy(false);
        }
    }

    private void SetBusy(bool value)
    {
        busy = value;
        UpdateAssetControls();
    }

    private void UpdateAssetControls()
    {
        OpenFolder.IsEnabled = connected && !busy;
        VehicleList.IsEnabled = connected && !busy;
        Factory.IsEnabled = !busy && selected?.Configurations.Count > 0;
        PaintFinish.IsEnabled = connected && !busy && paintable;
        PaintColor.IsEnabled = PaintFinish.IsEnabled && PaintFinish.SelectedIndex > 0;
        ReadParts.IsEnabled = !busy && !partsLoaded && selected?.Configurations.Count > 0;
        CopyCode.IsEnabled = connected && !busy && !applyingParts && displayed is not null;
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

    public sealed record Vehicle(string Id, string Name, string Make, string Category, List<FactoryOption> Configurations,
        string? EnglishName, string? EnglishMake, string? Drive, int? Gears, double? Mass,
        double? Speed, double? Acceleration, double? RoadHandling, double? OffroadHandling,
        double? Strength, int? RoadRating, int? DirtRating)
    {
        public string Subtitle => string.IsNullOrEmpty(Make) ? Id : $"{Make} · {Id}";
    }

    public sealed record FactoryOption(string? Color, int Count);
    private sealed record PartOption(string Id, string Slot, [property: System.Text.Json.Serialization.JsonPropertyName("slot_name")] string? SlotName, string Label, int[]? StockConfigs);
    private sealed record BuildCode(string Model, int Config, string[] Parts);
    private enum AaMethod { None = 0, Fxaa = 1, Smaa = 2, Taa = 3, Msaa = 4, Fsr2 = 7, Dlss = 8 }
    private sealed record AaChoice(AaMethod Method, string Label);
    private sealed record AaTier(string Label, int EngineMode, double Scale);
    private sealed record Preferences(int Theme = 0, bool Mica = true, bool Lamps = true, bool Grid = false,
        string FloorColor = "", GraphicsPreferences? Graphics = null);
    private sealed record GraphicsPreferences(bool Path = false, int PathQuality = 2,
        AaMethod RasterAa = AaMethod.Taa, AaMethod PathAa = AaMethod.Dlss, bool Reflections = true,
        bool Occlusion = true, bool IndirectLight = true, bool Bloom = true, SavedTier[]? Tiers = null,
        bool UncapPreview = false, AaMethod? AntialiasMethod = null);
    private sealed record SavedTier(bool Path, AaMethod Method, int Index);
}
