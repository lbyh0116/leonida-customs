using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.System;
using WinRT.Interop;

using static VehicleStudio.UiText;

namespace VehicleStudio;

public sealed partial class MainWindow
{
    private async void SaveScreenshot(object sender, RoutedEventArgs args)
    {
        if (savingScreenshot || previewBitmap is not { } bitmap)
            return;
        savingScreenshot = true;
        ScreenshotButton.IsEnabled = false;
        try
        {
            var snapshot = new byte[bitmap.PixelWidth * bitmap.PixelHeight * 4];
            using (var pixels = bitmap.PixelBuffer.AsStream())
                pixels.ReadExactly(snapshot);
            var picker = new FileSavePicker
            {
                SuggestedStartLocation = PickerLocationId.PicturesLibrary,
                SuggestedFileName = $"{displayed?.Model ?? selected?.Id ?? "leonida"}-{DateTime.Now:yyyyMMdd-HHmmss}"
            };
            picker.FileTypeChoices.Add("PNG", [".png"]);
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
            if (await picker.PickSaveFileAsync() is not { } file)
                return;
            using var stream = await file.OpenAsync(FileAccessMode.ReadWrite);
            stream.Size = 0;
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
            encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore,
                (uint)bitmap.PixelWidth, (uint)bitmap.PixelHeight, 96, 96, snapshot);
            await encoder.FlushAsync();
            Report(T("已保存视口截图。"));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or COMException)
        {
            Report(T("无法保存截图。请选择可以写入的位置。"), error: true);
        }
        finally
        {
            savingScreenshot = false;
            ScreenshotButton.IsEnabled = previewBitmap is not null && !closing;
        }
    }

    private async void OpenHelp(object sender, RoutedEventArgs args)
    {
        var version = typeof(MainWindow).Assembly.GetName().Version?.ToString(3) ?? T("开发版");
        var diagnostics = $"Leonida Customs {version} · Windows {Environment.OSVersion.Version} ({RuntimeInformation.OSArchitecture})\n"
            + F("渲染器 {0}{1} · 路径追踪 {2} · DLSS {3}", connected ? T("已连接") : T("未连接"),
                safeMode ? T(" · 安全模式") : "", T(pathAvailable ? "可用" : "不可用"), T(dlssAvailable ? "可用" : "不可用")) + "\n"
            + F("视口 {0}", previewBitmap is { } bitmap ? $"{bitmap.PixelWidth} × {bitmap.PixelHeight}" : T("待初始化"));
        var content = new StackPanel { Spacing = 10 };
        content.Children.Add(new TextBlock
        {
            Text = T("打开包含 levels.rpf、packs.rpf 和 data.rpf 的 Xbox 版资源目录。首次扫描可能需要数分钟，资源始终留在本机。"),
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new TextBlock { Text = diagnostics, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
        var links = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        links.Children.Add(new HyperlinkButton { Content = T("使用说明"), NavigateUri = new Uri("https://github.com/lbyh0116/leonida-customs#readme") });
        links.Children.Add(new HyperlinkButton { Content = T("提交问题"), NavigateUri = new Uri("https://github.com/lbyh0116/leonida-customs/issues/new/choose") });
        content.Children.Add(links);
        var dialog = new ContentDialog
        {
            XamlRoot = Shell.XamlRoot, Title = T("帮助与诊断"), Content = content,
            PrimaryButtonText = T("复制诊断信息"), SecondaryButtonText = projectFolder is null ? "" : T("打开日志目录"), CloseButtonText = T("关闭对话框")
        };
        try
        {
            var result = await dialog.ShowAsync();
            if (result == ContentDialogResult.Primary)
            {
                var data = new DataPackage();
                data.SetText(diagnostics);
                Clipboard.SetContent(data);
                Report(T("已复制诊断信息。"));
            }
            else if (result == ContentDialogResult.Secondary && projectFolder is { } folder)
            {
                var path = Directory.CreateDirectory(Path.Combine(folder, "work")).FullName;
                await Launcher.LaunchFolderAsync(await StorageFolder.GetFolderFromPathAsync(path));
            }
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or UnauthorizedAccessException or COMException)
        {
            Report(T("无法打开日志目录或访问剪贴板。"), error: true);
        }
    }
}
