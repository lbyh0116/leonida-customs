using System.Runtime.InteropServices;

namespace VehicleStudio;

internal sealed class NativeViewport : IDisposable
{
    private nint renderer;

    public nint RendererWindow => renderer;

    public bool TryAttach(int processId)
    {
        EnumWindows((candidate, _) =>
        {
            GetWindowThreadProcessId(candidate, out var owner);
            if (owner != processId || GetWindow(candidate, 4) != 0)
                return true;
            renderer = candidate;
            return false;
        }, 0);
        if (renderer == 0)
            return false;

        var style = GetWindowLongPtr(renderer, -20).ToInt64();
        SetWindowLongPtr(renderer, -20, (nint)((style & ~0x40000L) | 0x80L | 0x08000000L));
        SetWindowPos(renderer, 0, -20000, -20000, 0, 0, 0x0010 | 0x0004 | 0x0001 | 0x0020);
        return true;
    }

    public void Dispose() => renderer = 0;

    private delegate bool WindowCallback(nint hwnd, nint data);
    [DllImport("user32.dll")]
    private static extern bool EnumWindows(WindowCallback callback, nint data);
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint window, out uint processId);
    [DllImport("user32.dll")]
    private static extern nint GetWindow(nint window, uint command);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern nint GetWindowLongPtr(nint window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern nint SetWindowLongPtr(nint window, int index, nint value);
    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(nint window, nint next, int x, int y, int width, int height, uint flags);
}
