using Microsoft.UI.Xaml;

namespace VehicleStudio;

public partial class App : Application
{
    private MainWindow? window;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args) => OpenWindow();

    internal void OpenWindow(string? game = null, string? model = null, bool settings = false)
    {
        window = new MainWindow(game, model, settings);
        window.Activate();
    }
}
