using System.ComponentModel;
using System.Runtime.CompilerServices;
using FloatingLyric.Core;

namespace FloatingLyric.App;

/// <summary>Every piece of state the window draws. A port of LyricViewModel.swift.</summary>
public sealed class LyricViewModel : INotifyPropertyChanged
{
    private string _title = "FloatingLyric";
    private string _artist = "";
    private string _message = "Set up Spotify to begin";
    private LyricsDocument? _document;
    private int? _currentIndex;
    private int _positionMs;
    private int _durationMs;
    private int _fontSize = 18;
    private bool _isOffline;
    private bool _isPlaying;
    private bool _canControl;
    private string? _controlMessage;
    private bool _chromeVisible = true;
    private bool _showRomaji = true;
    private bool _isHovering;

    private string? _plainText;
    private string? _plainWithRomaji;
    private double _lastActivity;
    private double? _messageExpiry;

    public Settings Settings { get; }

    public LyricViewModel(Settings settings)
    {
        Settings = settings;
        _fontSize = settings.FontSize;
        _showRomaji = settings.ShowRomaji;
    }

    public string Title { get => _title; private set => Set(ref _title, value); }
    public string Artist { get => _artist; private set => Set(ref _artist, value); }
    public string Message { get => _message; private set => Set(ref _message, value); }
    public LyricsDocument? Document { get => _document; private set => Set(ref _document, value); }
    public int? CurrentIndex { get => _currentIndex; private set => Set(ref _currentIndex, value); }
    public int PositionMs { get => _positionMs; private set => Set(ref _positionMs, value); }
    public int DurationMs { get => _durationMs; private set => Set(ref _durationMs, value); }
    public int FontSize { get => _fontSize; set => Set(ref _fontSize, value); }
    public bool IsOffline { get => _isOffline; private set => Set(ref _isOffline, value); }
    public bool IsPlaying { get => _isPlaying; set => Set(ref _isPlaying, value); }
    public bool CanControl { get => _canControl; set => Set(ref _canControl, value); }
    public string? ControlMessage { get => _controlMessage; private set => Set(ref _controlMessage, value); }
    public bool ChromeVisible { get => _chromeVisible; private set => Set(ref _chromeVisible, value); }
    public bool ShowRomaji { get => _showRomaji; private set => Set(ref _showRomaji, value); }
    public bool IsHovering => _isHovering;

    public Action? PlayPauseRequested { get; set; }
    public Action? NextRequested { get; set; }
    public Action? PreviousRequested { get; set; }

    public void Apply(PlaybackState state)
    {
        switch (state)
        {
            case PlaybackState.Idle:
                Title = "Nothing playing";
                Artist = "";
                Document = null;
                Message = "Nothing playing";
                IsOffline = false;
                SetPlaying(false);
                break;

            case PlaybackState.Playing or PlaybackState.Paused:
                var np = state.NowPlaying!;
                Title = np.Track.Title;
                Artist = np.Track.Artist;
                DurationMs = np.Track.DurationMs;
                IsOffline = false;
                SetPlaying(np.IsPlaying);
                break;

            case PlaybackState.Failed failed:
                switch (failed.Error)
                {
                    case AppError.NotConfigured or AppError.NotLoggedIn or AppError.SessionExpired:
                        Document = null;
                        Title = "FloatingLyric";
                        Artist = "";
                        Message = failed.Error.DisplayMessage;
                        IsOffline = false;
                        break;
                    case AppError.Network:
                        IsOffline = true;      // keep whatever lyrics are on screen
                        break;
                    // Everything else is transient; leave the display alone.
                }
                break;
        }
    }

    public void Apply(LyricsResult lyrics)
    {
        switch (lyrics)
        {
            case LyricsResult.Synced synced:
                Document = new LyricsDocument(synced.Lines);
                _plainText = _plainWithRomaji = null;
                CurrentIndex = Document.IndexAt(PositionMs, Settings.SyncOffsetMs);
                break;
            case LyricsResult.Plain plain:
                Document = null;
                _plainText = plain.Text;
                _plainWithRomaji = InterleaveRomaji(plain.Text);
                Message = PlainDisplayText;
                break;
            default:
                Document = null;
                _plainText = _plainWithRomaji = null;
                Message = "No lyrics found";
                break;
        }
        NoteActivity();
    }

    public void Tick(int positionMs)
    {
        PositionMs = positionMs;
        if (Document is not { } document) return;
        CurrentIndex = document.IndexAt(positionMs, Settings.SyncOffsetMs);
    }

    // MARK: romaji

    /// <summary>Plain lyrics arrive as one blob, so the reading goes under
    /// each line here rather than in the view.</summary>
    private static string InterleaveRomaji(string text) => string.Join('\n',
        text.Split('\n').Select(line =>
            Transliteration.Romanize(line) is { } romaji ? line + "\n" + romaji : line));

    private string PlainDisplayText => (ShowRomaji ? _plainWithRomaji : _plainText) ?? _plainText ?? "";

    public void SetShowRomaji(bool show)
    {
        if (ShowRomaji == show) return;
        ShowRomaji = show;
        if (_plainText is not null) Message = PlainDisplayText;
        NoteActivity();
    }

    // MARK: transport

    private void SetPlaying(bool playing)
    {
        if (IsPlaying == playing) return;
        IsPlaying = playing;
        NoteActivity();
    }

    /// <summary>Flips straight away: Spotify applies commands asynchronously
    /// and a button that waits for the next poll feels broken.</summary>
    public void PlayPauseTapped()
    {
        NoteActivity();
        IsPlaying = !IsPlaying;
        PlayPauseRequested?.Invoke();
    }

    public void NextTapped() { NoteActivity(); NextRequested?.Invoke(); }
    public void PreviousTapped() { NoteActivity(); PreviousRequested?.Invoke(); }

    public void ReportControlError(AppError error, double now)
    {
        ControlMessage = error.DisplayMessage;
        // Matches the chrome timeout, so the message never outlives the row
        // it is printed in.
        _messageExpiry = now + ChromeVisibility.IdleTimeoutSeconds;
        NoteActivity(now);
    }

    // MARK: chrome

    /// <summary>Called every tick with the current pointer state, so only a
    /// change counts as activity — otherwise the countdown never starts.</summary>
    public void SetHovering(bool hovering, double now)
    {
        if (_isHovering != hovering) _lastActivity = now;
        _isHovering = hovering;
        RefreshChrome(now);
    }

    public void NoteActivity(double? now = null)
    {
        var timestamp = now ?? Now();
        _lastActivity = timestamp;
        RefreshChrome(timestamp);
    }

    public void RefreshChrome(double now)
    {
        if (_messageExpiry is { } expiry && now >= expiry)
        {
            _messageExpiry = null;
            ControlMessage = null;
        }
        var visible = !Settings.AutoHideChrome ||
                      ChromeVisibility.IsVisible(now, _lastActivity, _isHovering);
        if (ChromeVisible != visible) ChromeVisible = visible;
    }

    public static double Now() => Environment.TickCount64 / 1000.0;

    public event PropertyChangedEventHandler? PropertyChanged;

    private void Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
