using Avalonia.Controls;
using Avalonia.Threading;
using FloatingLyric.Core;

namespace FloatingLyric.App;

/// <summary>
/// The spine: owns everything and wires it together. A port of
/// AppCoordinator.swift, including the two loops it drives.
/// </summary>
public sealed class Coordinator
{
    public Settings Settings { get; }
    public LyricViewModel ViewModel { get; }

    private readonly IHttpClient _http = new RealHttpClient();
    private readonly ITokenStore _store;
    private readonly ILyricsCache _cache = new LyricsCache();
    private readonly PlayheadClock _clock = new();

    private SpotifyAuth? _auth;
    private PlaybackController? _playback;
    private NowPlayingPoller? _poller;
    private LyricsProvider? _provider;
    private LyricWindow? _window;
    private LoginWindow? _loginWindow;
    private DispatcherTimer? _timer;
    private TrackIdentity? _currentTrack;
    private CancellationTokenSource? _lyricsTask;

    public Coordinator()
    {
        Settings = Settings.Load();
        Settings.ClampForStorage();
        ViewModel = new LyricViewModel(Settings);
        _store = OperatingSystem.IsWindows()
            ? new DpapiTokenStore()
            // Only reachable when running the app on a developer's Mac or
            // Linux box: DPAPI is Windows-only, and a session that vanishes on
            // quit is better than storing a token in the clear.
            : new InMemoryTokenStore();
    }

    public LyricWindow Start()
    {
        var window = new LyricWindow(ViewModel, Settings);
        _window = window;

        ViewModel.PlayPauseRequested = TogglePlayPause;
        ViewModel.NextRequested = () => Skip(next: true);
        ViewModel.PreviousRequested = () => Skip(next: false);

        _provider = new LyricsProvider(_http, _cache);
        StartTicking();
        BuildSession();
        return window;
    }

    // MARK: session

    private void BuildSession()
    {
        _poller?.Stop();
        _poller = null;
        _playback = null;
        ViewModel.CanControl = false;

        if (Settings.ClientId is not { } clientId)
        {
            ViewModel.Apply(new PlaybackState.Failed(new AppError.NotConfigured()));
            ShowLogin(LoginPrompt.Setup);
            return;
        }

        var auth = new SpotifyAuth(clientId, _http, _store);
        _auth = auth;

        if (!auth.IsLoggedIn)
        {
            // Nothing can be shown without a session, so ask for one rather
            // than leaving a dead panel on screen.
            ViewModel.Apply(new PlaybackState.Failed(new AppError.NotLoggedIn()));
            ShowLogin(Settings.HasSignedInBefore ? LoginPrompt.LogIn : LoginPrompt.Welcome);
            return;
        }

        Settings.HasSignedInBefore = true;
        Settings.Save();

        _playback = new PlaybackController(auth, _http);
        ViewModel.CanControl = true;

        var poller = new NowPlayingPoller(auth, _http);
        _poller = poller;
        poller.Start(state => Dispatcher.UIThread.Post(() => Handle(state)));
    }

    public void ShowLogin(LoginPrompt? prompt = null)
    {
        var resolved = prompt ?? LoginPrompts.Required(
            Settings.ClientId, _auth?.IsLoggedIn ?? false, Settings.HasSignedInBefore)
            ?? LoginPrompt.LogIn;

        if (_loginWindow is { IsVisible: true } existing && existing.Prompt == resolved)
        {
            existing.Activate();
            return;
        }

        var window = new LoginWindow(resolved, Settings.ClientIdOverride, clientId =>
        {
            if (clientId.Length > 0 && clientId != AppCredentials.BuiltInClientId)
            {
                Settings.ClientIdOverride = clientId;
                Settings.Save();
            }
            _ = LogInAsync();
        });
        _loginWindow = window;
        window.Show();
    }

    /// <summary>
    /// Browser plus a one-shot loopback listener. Windows has no
    /// ASWebAuthenticationSession, so this is the flow the Mac app keeps only
    /// as its fallback.
    /// </summary>
    public async Task LogInAsync()
    {
        if (Settings.ClientId is not { } clientId) { ShowLogin(LoginPrompt.Setup); return; }
        var auth = _auth ?? new SpotifyAuth(clientId, _http, _store);
        _auth = auth;

        var pkce = Pkce.Generate();
        var state = Pkce.RandomState();

        foreach (var port in SpotifyCallback.CandidatePorts)
        {
            var redirect = SpotifyCallback.RedirectUri(port);
            using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(5));
            var listener = CallbackListener.WaitForCallbackAsync(port, timeout.Token);

            await Task.Delay(250);
            OpenBrowser(auth.AuthorizationUrl(pkce.Challenge, state, redirect).ToString());

            try
            {
                var callback = await listener;
                var result = SpotifyCallback.Code(callback, state);
                if (!result.IsSuccess)
                {
                    Report(result.Error!);
                    return;
                }
                await auth.ExchangeAsync(result.Value!, pkce.Verifier, redirect);
                Dispatcher.UIThread.Post(BuildSession);
                return;
            }
            catch (AppErrorException e) when (e.Error is AppError.PortUnavailable)
            {
                continue;                       // try the next candidate port
            }
            catch (AppErrorException e)
            {
                Report(e.Error);
                return;
            }
            catch (Exception)
            {
                Report(new AppError.AuthCancelled());
                return;
            }
        }
        Report(new AppError.PortUnavailable());
    }

    public void LogOut()
    {
        _poller?.Stop();
        _poller = null;
        _playback = null;
        ViewModel.CanControl = false;
        _auth?.LogOut();
        _currentTrack = null;
        ViewModel.Apply(new PlaybackState.Failed(new AppError.NotLoggedIn()));
        // Logging out is nearly always a prelude to logging back in.
        ShowLogin(LoginPrompt.LogIn);
    }

    // MARK: window

    public void TogglePanel()
    {
        if (_window is not { } window) return;
        switch (PanelToggle.Action(window.WindowState == WindowState.Minimized, window.IsVisible))
        {
            case PanelAction.Restore: window.WindowState = WindowState.Normal; break;
            case PanelAction.Hide: window.Hide(); break;
            case PanelAction.Show: window.Show(); break;
        }
    }

    public void ApplyPanelSettings()
    {
        Settings.ClampForStorage();
        Settings.Save();
        ViewModel.FontSize = Settings.FontSize;
        ViewModel.SetShowRomaji(Settings.ShowRomaji);
        ViewModel.NoteActivity();
        _window?.ApplySettings();
    }

    // MARK: playback

    private void TogglePlayPause()
    {
        if (_playback is not { } playback) return;
        // The view has already flipped its own button optimistically.
        var wasPlaying = !ViewModel.IsPlaying;
        Run(() => playback.ToggleAsync(wasPlaying));
    }

    private void Skip(bool next)
    {
        if (_playback is not { } playback) return;
        Run(() => next ? playback.NextAsync() : playback.PreviousAsync());
    }

    public void PlayPause() => ViewModel.PlayPauseTapped();
    public void NextTrack() => ViewModel.NextTapped();
    public void PreviousTrack() => ViewModel.PreviousTapped();
    public bool HasCurrentTrack => _currentTrack is not null;

    /// <summary>Runs a control call, reports failure, then re-polls so the
    /// display catches up without waiting for the next scheduled poll.</summary>
    private void Run(Func<Task<AppError?>> call) => _ = Task.Run(async () =>
    {
        var error = await call();
        if (error is not null) Report(error);

        // Spotify applies the command asynchronously; a beat of delay keeps
        // the follow-up poll from reading the pre-command state.
        await Task.Delay(400);
        if (_poller is { } poller)
        {
            var state = await poller.PollOnceAsync();
            Dispatcher.UIThread.Post(() => Handle(state));
        }
    });

    /// <summary>Throws away what is cached for the current track and asks
    /// LRCLIB again — the only way past a stale miss without waiting a day.</summary>
    public void RefetchLyrics()
    {
        if (_currentTrack is not { } track) return;
        _cache.Remove(track.Id);
        ViewModel.Apply(LyricsResult.None);
        FetchLyrics(track);
    }

    // MARK: state plumbing

    private void Handle(PlaybackState state)
    {
        ViewModel.Apply(state);

        if (state.NowPlaying is not { } np)
        {
            if (state is PlaybackState.Idle) _currentTrack = null;
            return;
        }

        // Every poll re-anchors, which covers drift, pause and seek alike.
        _clock.Anchor(np.ProgressMs, np.IsPlaying, LyricViewModel.Now());

        if (np.Track.Id == _currentTrack?.Id) return;
        _currentTrack = np.Track;
        FetchLyrics(np.Track);
    }

    private void FetchLyrics(TrackIdentity track)
    {
        _lyricsTask?.Cancel();
        var cts = new CancellationTokenSource();
        _lyricsTask = cts;
        if (_provider is not { } provider) return;

        _ = Task.Run(async () =>
        {
            var result = await provider.LyricsAsync(track);
            if (cts.IsCancellationRequested) return;
            Dispatcher.UIThread.Post(() =>
            {
                if (_currentTrack?.Id != track.Id) return;
                ViewModel.Apply(result);
            });
        });
    }

    private void StartTicking()
    {
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
        _timer.Tick += (_, _) =>
        {
            var now = LyricViewModel.Now();
            ViewModel.Tick(_clock.PositionMs(now));
            ViewModel.RefreshChrome(now);
            _window?.ApplySettings();
        };
        _timer.Start();
    }

    private void Report(AppError error) => Dispatcher.UIThread.Post(() =>
        ViewModel.ReportControlError(error, LyricViewModel.Now()));

    private static void OpenBrowser(string url)
    {
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = url,
                UseShellExecute = true,
            });
        }
        catch (Exception)
        {
            // Nothing sensible to do: the user simply never sees the page.
        }
    }
}
