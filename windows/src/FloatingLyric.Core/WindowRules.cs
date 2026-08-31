namespace FloatingLyric.Core;

/// <summary>
/// Whether the window furniture is on screen. After a few idle seconds
/// everything but the lyrics goes; pointing at the window brings it back.
/// </summary>
public static class ChromeVisibility
{
    public const double IdleTimeoutSeconds = 3.0;

    public static bool IsVisible(double now, double lastActivity, bool isHovering)
    {
        if (isHovering) return true;
        var elapsed = now - lastActivity;
        // A backwards clock (sleep, time sync) must not blank the window.
        if (elapsed < 0) return true;
        return elapsed < IdleTimeoutSeconds;
    }
}

/// <summary>The window's transparency, as a free 0–100% setting.</summary>
public static class PanelOpacity
{
    public const int MinimumPercent = 0;
    public const int MaximumPercent = 100;
    public const int DefaultPercent = 60;
    public const int StepPercent = 5;

    /// <summary>0% is invisible, which would also be unfindable. Pointing at
    /// such a window lifts it back to here, so the setting can be undone.</summary>
    public const int HoverFloorPercent = 35;

    public static int Clamped(int percent) =>
        Math.Min(MaximumPercent, Math.Max(MinimumPercent, percent));

    public static double Alpha(int percent) => Clamped(percent) / 100.0;

    /// <summary>Hovering never makes a window more transparent than it is —
    /// it only rescues a near-invisible one.</summary>
    public static double Alpha(int percent, bool isHovering)
    {
        var effective = isHovering
            ? Math.Max(Clamped(percent), HoverFloorPercent)
            : Clamped(percent);
        return effective / 100.0;
    }

    public static int Stepped(int percent, int delta) => Clamped(Clamped(percent) + delta);
}

public enum PanelAction { Show, Hide, Restore }

public static class PanelToggle
{
    /// <summary>Minimized has to be checked before visible, or the window gets
    /// hidden while still in the taskbar — unreachable from either place.</summary>
    public static PanelAction Action(bool isMinimized, bool isVisible) =>
        isMinimized ? PanelAction.Restore : isVisible ? PanelAction.Hide : PanelAction.Show;
}
