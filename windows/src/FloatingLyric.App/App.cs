using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Platform;
using Avalonia.Themes.Fluent;
using FloatingLyric.Core;

namespace FloatingLyric.App;

/// <summary>
/// No main window in the usual sense: a tray icon, and a panel that floats
/// above everything else.
/// </summary>
public sealed class FloatingLyricApp : Application
{
    private Coordinator? _coordinator;
    private TrayIcon? _tray;

    public override void Initialize() => Styles.Add(new FluentTheme());

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            // Closing the lyric window must not quit: it is reopened from the
            // tray, exactly as the Mac build reopens from the menu bar.
            desktop.ShutdownMode = ShutdownMode.OnExplicitShutdown;

            var coordinator = new Coordinator();
            _coordinator = coordinator;
            var window = coordinator.Start();
            window.Show();

            BuildTray(desktop, coordinator);
        }

        base.OnFrameworkInitializationCompleted();
    }

    private void BuildTray(IClassicDesktopStyleApplicationLifetime desktop, Coordinator coordinator)
    {
        var settings = coordinator.Settings;
        var menu = new NativeMenu();

        menu.Add(Item("Show / Hide Lyrics", coordinator.TogglePanel));
        menu.Add(Item("Refetch Lyrics", coordinator.RefetchLyrics));
        menu.Add(new NativeMenuItemSeparator());

        menu.Add(Item("Play / Pause", coordinator.PlayPause));
        menu.Add(Item("Next Track", coordinator.NextTrack));
        menu.Add(Item("Previous Track", coordinator.PreviousTrack));
        menu.Add(new NativeMenuItemSeparator());

        menu.Add(Toggle("Lock Position", settings.LockPosition,
            on => { settings.LockPosition = on; coordinator.ApplyPanelSettings(); }));
        menu.Add(Toggle("Click Through", settings.ClickThrough,
            on => { settings.ClickThrough = on; coordinator.ApplyPanelSettings(); }));
        menu.Add(Toggle("Romaji Under Lyrics", settings.ShowRomaji,
            on => { settings.ShowRomaji = on; coordinator.ApplyPanelSettings(); }));
        menu.Add(Toggle("Auto-Hide Controls", settings.AutoHideChrome,
            on => { settings.AutoHideChrome = on; coordinator.ApplyPanelSettings(); }));

        var fontMenu = new NativeMenu();
        foreach (var (label, size) in new[] { ("Small", 14), ("Medium", 18), ("Large", 24) })
            fontMenu.Add(Item(label, () => { settings.FontSize = size; coordinator.ApplyPanelSettings(); }));
        menu.Add(new NativeMenuItem("Font Size") { Menu = fontMenu });

        // A tray menu cannot hold a slider, so opacity is a list of steps plus
        // two nudges — the same 0–100 range, reached differently.
        var opacityMenu = new NativeMenu();
        foreach (var percent in new[] { 0, 15, 30, 45, 60, 75, 90, 100 })
            opacityMenu.Add(Item($"{percent}%", () =>
            {
                settings.OpacityPercent = percent;
                coordinator.ApplyPanelSettings();
            }));
        opacityMenu.Add(new NativeMenuItemSeparator());
        opacityMenu.Add(Item("More Opaque", () => StepOpacity(coordinator, PanelOpacity.StepPercent)));
        opacityMenu.Add(Item("More Transparent", () => StepOpacity(coordinator, -PanelOpacity.StepPercent)));
        menu.Add(new NativeMenuItem("Opacity") { Menu = opacityMenu });

        var offsetMenu = new NativeMenu();
        foreach (var offset in new[] { -1000, -500, -250, 0, 250, 500, 1000 })
            offsetMenu.Add(Item($"{offset:+#;-#;0} ms", () =>
            {
                settings.SyncOffsetMs = offset;
                coordinator.ApplyPanelSettings();
            }));
        menu.Add(new NativeMenuItem("Sync Offset") { Menu = offsetMenu });
        menu.Add(new NativeMenuItemSeparator());

        menu.Add(Item("Use My Own Client ID…", () => coordinator.ShowLogin(LoginPrompt.Setup)));
        menu.Add(Item("Log Out", coordinator.LogOut));
        menu.Add(new NativeMenuItemSeparator());
        menu.Add(Item("Quit FloatingLyric", () => desktop.Shutdown()));

        _tray = new TrayIcon
        {
            ToolTipText = "FloatingLyric",
            Menu = menu,
            IsVisible = true,
        };

        try
        {
            using var stream = AssetLoader.Open(new Uri("avares://FloatingLyric/icon.png"));
            _tray.Icon = new WindowIcon(stream);
        }
        catch (Exception)
        {
            // A tray icon with no bitmap still works; it just looks blank.
        }

        TrayIcon.SetIcons(this, [_tray]);
    }

    private static void StepOpacity(Coordinator coordinator, int delta)
    {
        coordinator.Settings.OpacityPercent =
            PanelOpacity.Stepped(coordinator.Settings.OpacityPercent, delta);
        coordinator.ApplyPanelSettings();
    }

    private static NativeMenuItem Item(string header, Action action)
    {
        var item = new NativeMenuItem(header);
        item.Click += (_, _) => action();
        return item;
    }

    private static NativeMenuItem Toggle(string header, bool isChecked, Action<bool> action)
    {
        var item = new NativeMenuItem(header)
        {
            ToggleType = NativeMenuItemToggleType.CheckBox,
            IsChecked = isChecked,
        };
        item.Click += (_, _) =>
        {
            item.IsChecked = !item.IsChecked;
            action(item.IsChecked);
        };
        return item;
    }
}
