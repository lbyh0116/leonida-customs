using System.Runtime.InteropServices;

namespace VehicleStudio;

internal static class RendererWindow
{
    public static bool TryHide(int processId)
    {
        if (processId <= 0)
            return false;
        bool found = false;
        bool hidden = true;
        EnumWindows((window, _) =>
        {
            GetWindowThreadProcessId(window, out var owner);
            if (owner != processId)
                return true;
            found = true;
            if (IsWindowVisible(window))
            {
                ShowWindowAsync(window, 0); // SW_HIDE keeps the Vulkan window alive.
                hidden = false;
            }
            return true;
        }, 0);
        return found && hidden;
    }

    private delegate bool WindowCallback(nint window, nint data);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(WindowCallback callback, nint data);
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint window, out uint processId);
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(nint window);
    [DllImport("user32.dll")]
    private static extern bool ShowWindowAsync(nint window, int command);
}
