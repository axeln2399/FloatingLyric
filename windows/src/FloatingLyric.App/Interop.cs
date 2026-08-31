using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace FloatingLyric.App;

/// <summary>
/// The two things Avalonia cannot express, both Windows-only and both no-ops
/// elsewhere so the app still runs on this developer's Mac.
/// </summary>
internal static class Interop
{
    private const int GwlExStyle = -20;
    private const int WsExTransparent = 0x00000020;
    private const int WsExToolWindow = 0x00000080;
    private const int WsExLayered = 0x00080000;

    [SupportedOSPlatform("windows")]
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int index);

    [SupportedOSPlatform("windows")]
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int index, IntPtr value);

    /// <summary>
    /// Click-through: the window is drawn but the mouse passes to whatever is
    /// behind it. WS_EX_LAYERED must be set alongside WS_EX_TRANSPARENT or
    /// Windows ignores the request.
    /// </summary>
    public static void SetClickThrough(IntPtr handle, bool enabled)
    {
        if (!OperatingSystem.IsWindows() || handle == IntPtr.Zero) return;
        try
        {
            var style = (long)GetWindowLongPtr(handle, GwlExStyle);
            style = enabled
                ? style | WsExTransparent | WsExLayered
                : style & ~WsExTransparent;
            SetWindowLongPtr(handle, GwlExStyle, (IntPtr)style);
        }
        catch (EntryPointNotFoundException)
        {
            // 32-bit Windows exports GetWindowLongW instead; not worth a
            // second path for a build that ships x64 only.
        }
    }

    /// <summary>Keeps the overlay out of the taskbar and out of Alt-Tab.</summary>
    public static void SetToolWindow(IntPtr handle)
    {
        if (!OperatingSystem.IsWindows() || handle == IntPtr.Zero) return;
        try
        {
            var style = (long)GetWindowLongPtr(handle, GwlExStyle);
            SetWindowLongPtr(handle, GwlExStyle, (IntPtr)(style | WsExToolWindow));
        }
        catch (EntryPointNotFoundException) { }
    }
}
