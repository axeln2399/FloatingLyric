using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using FloatingLyric.Core;

namespace FloatingLyric.App;

/// <summary>
/// The lyric window: borderless, always on top, and mostly invisible.
///
/// After a few idle seconds everything but the words fades — including the
/// panel behind them, which is why the background is a sibling of the text
/// rather than its parent. Fading a parent would take the lyrics with it.
/// </summary>
public sealed class LyricWindow : Window
{
    private readonly LyricViewModel _model;
    private readonly Settings _settings;

    private readonly Border _panel = new();
    private readonly StackPanel _header = new();
    private readonly TextBlock _titleText = new();
    private readonly TextBlock _offlineText = new();
    private readonly StackPanel _lines = new();
    private readonly ScrollViewer _linesScroll = new();
    private readonly TextBlock _messageText = new();
    private readonly StackPanel _footer = new();
    private readonly ProgressBar _progress = new();
    private readonly TextBlock _elapsed = new();
    private readonly TextBlock _total = new();
    private readonly Button _previous = new();
    private readonly Button _playPause = new();
    private readonly Button _next = new();

    public LyricWindow(LyricViewModel model, Settings settings)
    {
        _model = model;
        _settings = settings;

        Title = "FloatingLyric";
        SystemDecorations = SystemDecorations.None;
        Topmost = true;
        ShowInTaskbar = false;
        Background = Brushes.Transparent;
        TransparencyLevelHint = [WindowTransparencyLevel.AcrylicBlur, WindowTransparencyLevel.Transparent];
        CanResize = true;
        MinWidth = 280;
        MinHeight = 150;
        Width = settings.WindowWidth;
        Height = settings.WindowHeight;
        if (settings.WindowX is { } x && settings.WindowY is { } y)
        {
            Position = new PixelPoint((int)x, (int)y);
            WindowStartupLocation = WindowStartupLocation.Manual;
        }
        else
        {
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
        }

        Content = BuildContent();
        ApplySettings();

        PointerEntered += (_, _) => _model.SetHovering(true, LyricViewModel.Now());
        PointerExited += (_, _) => _model.SetHovering(false, LyricViewModel.Now());
        PointerPressed += OnPointerPressed;
        _model.PropertyChanged += (_, _) => Render();
        Opened += (_, _) =>
        {
            Interop.SetToolWindow(TryGetPlatformHandle()?.Handle ?? IntPtr.Zero);
            ApplySettings();
        };
        PositionChanged += (_, _) => SaveFrame();
        SizeChanged += (_, _) => SaveFrame();

        Render();
    }

    private Control BuildContent()
    {
        _titleText.FontSize = 11;
        _titleText.Foreground = new SolidColorBrush(Color.FromRgb(0xB8, 0xC0, 0xCC));
        _titleText.TextTrimming = TextTrimming.CharacterEllipsis;

        _offlineText.Text = "offline";
        _offlineText.FontSize = 11;
        _offlineText.Foreground = new SolidColorBrush(Color.FromRgb(0xE9, 0xA1, 0x3B));
        _offlineText.IsVisible = false;

        _header.Orientation = Orientation.Horizontal;
        _header.Spacing = 8;
        _header.Children.Add(_titleText);
        _header.Children.Add(_offlineText);

        _lines.Orientation = Orientation.Vertical;
        _lines.Spacing = 6;
        _linesScroll.Content = _lines;
        _linesScroll.VerticalScrollBarVisibility = ScrollBarVisibility.Hidden;
        _linesScroll.HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled;

        _messageText.TextWrapping = TextWrapping.Wrap;
        _messageText.Foreground = new SolidColorBrush(Color.FromRgb(0xB8, 0xC0, 0xCC));

        var content = new Panel();
        content.Children.Add(_linesScroll);
        content.Children.Add(_messageText);

        _progress.Minimum = 0;
        _progress.Maximum = 1;
        _progress.Height = 3;
        _progress.Foreground = new SolidColorBrush(Color.FromRgb(0xE9, 0xA1, 0x3B));
        _progress.Background = new SolidColorBrush(Color.FromArgb(0x40, 0xFF, 0xFF, 0xFF));

        foreach (var (button, glyph, action) in new (Button, string, Action)[]
                 {
                     (_previous, "⏮", () => _model.PreviousTapped()),
                     (_playPause, "⏵", () => _model.PlayPauseTapped()),
                     (_next, "⏭", () => _model.NextTapped()),
                 })
        {
            button.Content = glyph;
            button.FontSize = 15;
            button.Background = Brushes.Transparent;
            button.BorderThickness = new Thickness(0);
            button.Foreground = Brushes.White;
            button.Padding = new Thickness(10, 2);
            button.Click += (_, _) => action();
        }

        var transport = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Center,
            Spacing = 10,
        };
        transport.Children.Add(_previous);
        transport.Children.Add(_playPause);
        transport.Children.Add(_next);

        _elapsed.FontSize = 10;
        _total.FontSize = 10;
        _elapsed.Foreground = _total.Foreground = new SolidColorBrush(Color.FromRgb(0x8B, 0x95, 0xA5));

        var times = new Grid();
        times.ColumnDefinitions = new ColumnDefinitions("*,Auto");
        Grid.SetColumn(_elapsed, 0);
        Grid.SetColumn(_total, 1);
        times.Children.Add(_elapsed);
        times.Children.Add(_total);

        _footer.Orientation = Orientation.Vertical;
        _footer.Spacing = 4;
        _footer.Children.Add(transport);
        _footer.Children.Add(_progress);
        _footer.Children.Add(times);

        var layout = new DockPanel { LastChildFill = true };
        DockPanel.SetDock(_header, Dock.Top);
        DockPanel.SetDock(_footer, Dock.Bottom);
        layout.Children.Add(_header);
        layout.Children.Add(_footer);
        layout.Children.Add(content);

        _panel.Background = new SolidColorBrush(Color.FromArgb(0xD8, 0x11, 0x15, 0x1B));
        _panel.CornerRadius = new CornerRadius(10);
        _panel.BorderBrush = new SolidColorBrush(Color.FromArgb(0x50, 0xFF, 0xFF, 0xFF));
        _panel.BorderThickness = new Thickness(1);

        // The panel is a SIBLING behind the text, never its parent: fading a
        // parent would take the lyrics with it, and the lyrics are the one
        // thing that stays.
        var root = new Panel { Margin = new Thickness(0) };
        root.Children.Add(_panel);
        root.Children.Add(new Border { Child = layout, Padding = new Thickness(16, 12) });
        return root;
    }

    private void OnPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        _model.NoteActivity();
        if (_settings.LockPosition || _settings.ClickThrough) return;
        if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed) BeginMoveDrag(e);
    }

    public void ApplySettings()
    {
        Opacity = PanelOpacity.Alpha(_settings.OpacityPercent, _model.IsHovering);
        Interop.SetClickThrough(TryGetPlatformHandle()?.Handle ?? IntPtr.Zero, _settings.ClickThrough);
        Render();
    }

    private void SaveFrame()
    {
        if (WindowState == WindowState.Minimized) return;
        _settings.WindowX = Position.X;
        _settings.WindowY = Position.Y;
        _settings.WindowWidth = Width;
        _settings.WindowHeight = Height;
        _settings.Save();
    }

    /// <summary>Rebuilds what changed. Called on every view-model change and
    /// every tick — cheap enough at four lines of text.</summary>
    private void Render()
    {
        var chrome = _model.ChromeVisible ? 1.0 : 0.0;
        _header.Opacity = chrome;
        _footer.Opacity = chrome;
        _panel.Opacity = chrome;
        _footer.IsHitTestVisible = _model.ChromeVisible;

        _titleText.Text = _model.ControlMessage
            ?? (_model.Artist.Length > 0 ? $"{_model.Title} — {_model.Artist}" : _model.Title);
        _titleText.Foreground = _model.ControlMessage is null
            ? new SolidColorBrush(Color.FromRgb(0xB8, 0xC0, 0xCC))
            : new SolidColorBrush(Color.FromRgb(0xE9, 0xA1, 0x3B));
        _offlineText.IsVisible = _model.IsOffline;

        _playPause.Content = _model.IsPlaying ? "⏸" : "⏵";
        foreach (var button in new[] { _previous, _playPause, _next })
        {
            button.IsEnabled = _model.CanControl;
            button.Opacity = _model.CanControl ? 1 : 0.35;
        }

        _progress.Value = _model.DurationMs > 0
            ? Math.Min(1, (double)_model.PositionMs / _model.DurationMs) : 0;
        _elapsed.Text = Timecode(_model.PositionMs);
        _total.Text = Timecode(_model.DurationMs);

        RenderLines();
    }

    private void RenderLines()
    {
        if (_model.Document is not { } document || _model.CurrentIndex is null && document.Lines.Count == 0)
        {
            _linesScroll.IsVisible = false;
            _messageText.IsVisible = true;
            _messageText.Text = _model.Message;
            _messageText.FontSize = _model.FontSize;
            return;
        }

        _linesScroll.IsVisible = true;
        _messageText.IsVisible = false;

        var center = _model.CurrentIndex ?? -1;
        var wanted = Enumerable.Range(center - 1, 4).ToList();

        _lines.Children.Clear();
        foreach (var index in wanted)
        {
            if (index < 0 || index >= document.Lines.Count) continue;
            var isCurrent = index == center;

            var block = new StackPanel { Orientation = Orientation.Vertical, Spacing = 1 };
            block.Children.Add(new TextBlock
            {
                Text = document.Lines[index].Text,
                FontSize = _model.FontSize,
                FontWeight = isCurrent ? FontWeight.Bold : FontWeight.Normal,
                Foreground = isCurrent
                    ? Brushes.White
                    : new SolidColorBrush(Color.FromArgb(0x88, 0xFF, 0xFF, 0xFF)),
                // Long lines wrap rather than truncate.
                TextWrapping = TextWrapping.Wrap,
            });

            if (_model.ShowRomaji && document.RomanizationAt(index) is { } romaji)
            {
                block.Children.Add(new TextBlock
                {
                    Text = romaji,
                    FontSize = Math.Max(9, _model.FontSize - 6),
                    Foreground = new SolidColorBrush(Color.FromArgb(isCurrent ? (byte)0xAA : (byte)0x66,
                                                                    0xFF, 0xFF, 0xFF)),
                    TextWrapping = TextWrapping.Wrap,
                });
            }

            _lines.Children.Add(block);
        }
    }

    private static string Timecode(int ms)
    {
        var total = Math.Max(0, ms) / 1000;
        return $"{total / 60}:{total % 60:00}";
    }
}
