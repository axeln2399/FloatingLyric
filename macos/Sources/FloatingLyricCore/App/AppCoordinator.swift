import AppKit
import Foundation

@MainActor
public final class AppCoordinator {
    public let viewModel = LyricViewModel()

    private let http: HTTPClient = URLSessionHTTPClient()
    private let store: TokenStore = KeychainStore()
    private let cache: LyricsCaching = LyricsCache()
    private let clock = PlayheadClock()

    private var auth: SpotifyAuth?
    private var playback: PlaybackController?
    private var poller: NowPlayingPoller?
    private var lyricsProvider: LyricsProvider?
    private var window: FloatingWindow?
    private var setupWindow: SetupWindow?
    private var tickTimer: Timer?
    private var currentTrackID: String?
    private var lyricsTask: Task<Void, Never>?

    /// Built lazily: the sheet needs a window to hang from, and there is none
    /// until `start()` has run.
    private lazy var webAuth: WebAuthenticating = WebAuthSession { [weak self] in self?.window }

    public init() {}

    public func start() {
        let window = FloatingWindow(viewModel: viewModel)
        window.orderFrontRegardless()
        self.window = window

        viewModel.onPlayPause = { [weak self] in self?.togglePlayPause() }
        viewModel.onNext = { [weak self] in self?.skip(.next) }
        viewModel.onPrevious = { [weak self] in self?.skip(.previous) }

        lyricsProvider = LyricsProvider(http: http, cache: cache)
        startTicking()
        buildSession()
    }

    // MARK: - Session

    private func buildSession() {
        poller?.stop()
        poller = nil
        playback = nil
        viewModel.canControl = false

        guard let clientID = Defaults.clientID else {
            viewModel.apply(state: .failed(.notConfigured))
            showSetup(.firstRun)
            return
        }

        let auth = SpotifyAuth(clientID: clientID, http: http, store: store)
        self.auth = auth

        guard auth.isLoggedIn else {
            // Nothing can be shown without a session, so ask for one rather
            // than leaving a dead panel on screen.
            viewModel.apply(state: .failed(.notLoggedIn))
            showSetup(.logIn)
            return
        }

        playback = PlaybackController(auth: auth, http: http)
        viewModel.canControl = true

        let poller = NowPlayingPoller(auth: auth, http: http)
        self.poller = poller
        poller.start { state in
            Task { @MainActor [weak self] in self?.handle(state) }
        }
    }

    public func reconfigure(clientID: String) {
        Defaults.clientID = clientID
        auth = SpotifyAuth(clientID: clientID, http: http, store: store)
        logIn()
    }

    public func logIn() {
        guard let auth else {
            showSetup(.firstRun)
            return
        }
        Task { @MainActor in
            do {
                try await logInWithSheet(auth)
                buildSession()
            } catch AppError.authUnavailable {
                // The sheet could not be shown at all. Rather than strand the
                // user, fall back to the browser and a loopback listener.
                await logInWithBrowser(auth)
            } catch let error as AppError {
                viewModel.apply(state: .failed(error))
            } catch {
                viewModel.apply(state: .failed(.authCancelled))
            }
        }
    }

    /// Spotify's own login page, in a sheet over the app.
    private func logInWithSheet(_ auth: SpotifyAuth) async throws {
        let pkce = PKCE.generate()
        let state = PKCE.randomState()
        let url = auth.authorizationURL(challenge: pkce.challenge, state: state,
                                        redirectURI: SpotifyCallback.uri)

        let callback = try await webAuth.authenticate(url: url,
                                                      callbackScheme: SpotifyCallback.scheme)
        switch SpotifyCallback.code(from: callback, expectedState: state) {
        case .success(let code):
            try await auth.exchange(code: code, verifier: pkce.verifier,
                                    redirectURI: SpotifyCallback.uri)
        case .failure(let error):
            throw error
        }
    }

    /// The original flow, kept as a safety net: the default browser plus a
    /// one-shot local listener. Needs the loopback redirect registered in the
    /// Spotify dashboard alongside the app's own scheme.
    private func logInWithBrowser(_ auth: SpotifyAuth) async {
        let pkce = PKCE.generate()
        let state = PKCE.randomState()

        for port in CallbackListener.candidatePorts {
            let redirect = CallbackListener.redirectURI(port: port)
            let listener = Task { try await CallbackListener.waitForCallback(port: port) }
            try? await Task.sleep(nanoseconds: 250_000_000)

            NSWorkspace.shared.open(auth.authorizationURL(challenge: pkce.challenge,
                                                          state: state,
                                                          redirectURI: redirect))
            do {
                let result = try await listener.value
                guard result.state == state, let code = result.code else {
                    viewModel.apply(state: .failed(.authCancelled))
                    return
                }
                try await auth.exchange(code: code, verifier: pkce.verifier,
                                        redirectURI: redirect)
                buildSession()
                return
            } catch AppError.portUnavailable {
                continue                       // try the next candidate port
            } catch {
                viewModel.apply(state: .failed(.authCancelled))
                return
            }
        }
        viewModel.apply(state: .failed(.portUnavailable))
    }

    public func logOut() {
        poller?.stop()
        poller = nil
        playback = nil
        viewModel.canControl = false
        auth?.logOut()
        currentTrackID = nil
        viewModel.apply(state: .failed(.notLoggedIn))
        // Logging out is nearly always a prelude to logging back in — as a
        // different account, or to pick up a new permission.
        showSetup(.logIn)
    }

    /// Shows the login window. Without an argument it works out which face to
    /// show from what is actually stored.
    public func showSetup(_ prompt: LoginPrompt? = nil) {
        let prompt = prompt ?? LoginPrompt.required(clientID: Defaults.clientID,
                                                    isLoggedIn: auth?.isLoggedIn ?? false)
                             ?? .firstRun

        // Re-showing while it is already up would stack a second window
        // behind the first.
        if let existing = setupWindow, existing.prompt == prompt,
           existing.window?.isVisible == true {
            existing.present()
            return
        }

        let window = SetupWindow(prompt: prompt) { [weak self] clientID in
            self?.reconfigure(clientID: clientID)
        }
        setupWindow = window
        window.present()
    }

    public func togglePanel() {
        guard let window else { return }
        switch PanelToggle.action(isMiniaturized: window.isMiniaturized,
                                  isVisible: window.isVisible) {
        case .restore: window.deminiaturize(nil)
        case .hide:    window.orderOut(nil)
        case .show:    window.orderFrontRegardless()
        }
    }

    public func minimizePanel() {
        guard let window, window.isVisible, !window.isMiniaturized else { return }
        window.miniaturize(nil)
    }

    public func closePanel() {
        window?.close()
    }

    public func applyPanelPreferences() {
        window?.applyPreferences()
        viewModel.fontSize = Defaults.fontSize
        viewModel.setShowRomaji(Defaults.showRomaji)
        viewModel.noteActivity()
    }

    // MARK: - Playback control

    private enum Skip { case next, previous }

    /// Private on purpose: it reads the button state the view has *already*
    /// flipped, so it is only correct when reached through `playPauseTapped()`.
    private func togglePlayPause() {
        guard let playback else { return }
        let wasPlaying = !viewModel.isPlaying
        run { await playback.toggle(isPlaying: wasPlaying) }
    }

    public func nextTrack() { viewModel.nextTapped() }
    public func previousTrack() { viewModel.previousTapped() }
    public func playPause() { viewModel.playPauseTapped() }

    private func skip(_ direction: Skip) {
        guard let playback else { return }
        run { direction == .next ? await playback.next() : await playback.previous() }
    }

    /// Runs a control call, reports any failure in the panel, then re-polls so
    /// the display catches up without waiting for the next scheduled poll.
    private func run(_ call: @escaping () async -> AppError?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error = await call() {
                self.viewModel.report(controlError: error)
            }
            // Spotify applies the command asynchronously; a beat of delay
            // keeps the follow-up poll from reading the pre-command state.
            try? await Task.sleep(nanoseconds: 400_000_000)
            if let state = await self.poller?.pollOnce() {
                self.handle(state)
            }
        }
    }

    // MARK: - State plumbing

    private func handle(_ state: PlaybackState) {
        viewModel.apply(state: state)

        guard let np = state.nowPlaying else {
            if case .idle = state { currentTrackID = nil }
            return
        }

        // Every poll re-anchors, which covers ordinary drift, pause and seek alike.
        let now = Date().timeIntervalSinceReferenceDate
        clock.anchor(progressMs: np.progressMs, isPlaying: np.isPlaying, now: now)

        guard np.track.id != currentTrackID else { return }
        currentTrackID = np.track.id
        fetchLyrics(for: np.track)
    }

    private func fetchLyrics(for track: TrackIdentity) {
        lyricsTask?.cancel()
        guard let provider = lyricsProvider else { return }
        lyricsTask = Task { @MainActor [weak self] in
            let result = await provider.lyrics(for: track)
            guard !Task.isCancelled, self?.currentTrackID == track.id else { return }
            self?.viewModel.apply(lyrics: result)
        }
    }

    private func startTicking() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Date().timeIntervalSinceReferenceDate
                self.viewModel.tick(positionMs: self.clock.positionMs(now: now))
                self.viewModel.setHovering(self.window?.isPointerInside ?? false, now: now)
                self.window?.setChrome(visible: self.viewModel.chromeVisible,
                                       isHovering: self.viewModel.isHovering)
            }
        }
    }
}
