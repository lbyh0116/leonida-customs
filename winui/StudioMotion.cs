using System.Numerics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI.ViewManagement;

namespace VehicleStudio;

internal static class StudioMotion
{
    private static readonly UISettings Settings = new();

    public static bool Enabled => Settings.AnimationsEnabled;

    public static void Enter(UIElement element, Vector3 offset, int milliseconds = 200)
    {
        if (!Enabled || element.XamlRoot is null)
            return;

        var compositor = CompositionTarget.GetCompositorForCurrentThread();
        var ease = compositor.CreateCubicBezierEasingFunction(new Vector2(.17f, .72f), new Vector2(.28f, 1f));
        var slide = compositor.CreateVector3KeyFrameAnimation();
        slide.Target = "Translation";
        slide.Duration = TimeSpan.FromMilliseconds(milliseconds);
        slide.InsertKeyFrame(0, offset);
        slide.InsertKeyFrame(1, Vector3.Zero, ease);
        var fade = compositor.CreateScalarKeyFrameAnimation();
        fade.Target = "Opacity";
        fade.Duration = slide.Duration;
        fade.InsertKeyFrame(0, .64f);
        fade.InsertKeyFrame(1, 1, ease);
        element.StartAnimation(slide);
        element.StartAnimation(fade);
    }

    public static void Pressed(FrameworkElement element)
    {
        if (!Enabled || element.XamlRoot is null || element.ActualWidth <= 0)
            return;

        var compositor = CompositionTarget.GetCompositorForCurrentThread();
        var release = compositor.CreateVector3KeyFrameAnimation();
        release.Target = "Scale";
        release.Duration = TimeSpan.FromMilliseconds(165);
        release.InsertKeyFrame(0, Vector3.One);
        release.InsertKeyFrame(.28f, new Vector3(.965f, .965f, 1f));
        release.InsertKeyFrame(1, Vector3.One,
            compositor.CreateCubicBezierEasingFunction(new Vector2(.15f, .7f), new Vector2(.3f, 1f)));
        element.CenterPoint = new Vector3((float)element.ActualWidth / 2, (float)element.ActualHeight / 2, 0);
        element.StartAnimation(release);
    }
}
