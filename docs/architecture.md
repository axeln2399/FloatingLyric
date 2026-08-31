# How FloatingLyric works

A tour of the macOS code, for anyone learning the codebase — or porting it.
Diagrams are Mermaid, so GitHub renders them inline.

Paths are relative to [`../macos/`](../macos/).

---

## 1. Where to start reading

If you read four files, read these, in this order:

| File | Why |
|---|---|
| `App/AppCoordinator.swift` | The spine. Owns everything and wires it together. |
| `Playback/PlayheadClock.swift` | 32 lines, and the reason lyrics look smooth. |
| `UI/LyricViewModel.swift` | Every piece of state the window draws. |
| `Lyrics/LyricsProvider.swift` | The fetch-and-cache policy, in one place. |

Everything else hangs off those.

## 2. The shape of it

Five groups. Arrows point the way calls flow — nothing points back up, which
is what keeps the lower layers testable.

```mermaid
flowchart TD
    main["main.swift<br/><i>MainActor.assumeIsolated</i>"] --> delegate["AppDelegate"]
    delegate --> coord["<b>AppCoordinator</b><br/>owns everything"]
    delegate --> menu["MenuBarController<br/><i>the ♪ menu</i>"]
    menu --> coord

    coord --> window["FloatingWindow<br/><i>NSWindow</i>"]
    coord --> setup["SetupWindow<br/><i>login</i>"]
    window --> view["LyricView<br/><i>SwiftUI</i>"]
    view --> vm["<b>LyricViewModel</b><br/><i>@Published state</i>"]
    coord --> vm

    coord --> poller["NowPlayingPoller<br/><i>every 3s</i>"]
    coord --> clock["PlayheadClock<br/><i>extrapolates</i>"]
    coord --> control["PlaybackController<br/><i>play/pause/skip</i>"]
    coord --> provider["LyricsProvider"]

    provider --> cache["LyricsCache<br/><i>~/Library/…/lyrics</i>"]
    provider --> parser["LRCParser"]
    parser --> doc["LyricsDocument<br/>+ Transliteration"]

    poller --> auth["<b>SpotifyAuth</b><br/><i>tokens</i>"]
    control --> auth
    auth --> keychain["KeychainStore<br/><i>refresh token</i>"]
    auth --> http["HTTPClient"]
    poller --> http
    provider --> http

    classDef core fill:#2563eb,stroke:#1e40af,color:#fff
    class coord,vm,auth core
```

**The rule that makes it hang together:** `AppCoordinator` is the only type
that knows about more than its own neighbours. Nothing else reaches sideways.

## 3. Starting up

```mermaid
sequenceDiagram
    participant M as main.swift
    participant D as AppDelegate
    participant C as AppCoordinator
    participant W as FloatingWindow
    participant A as SpotifyAuth

    M->>D: NSApplication.run()
    Note over D: setActivationPolicy(.accessory)<br/>— no Dock icon
    D->>C: start()
    C->>W: create, orderFrontRegardless()
    C->>C: startTicking() — 10 Hz Timer
    C->>C: buildSession()

    alt no Client ID at all
        C->>C: showSetup(.setup) — walkthrough
    else not logged in
        C->>C: showSetup(.welcome / .logIn)
    else has refresh token
        C->>A: build SpotifyAuth + PlaybackController
        C->>C: poller.start { handle(state) }
    end
```

`LoginPrompt.required(clientID:isLoggedIn:hasSignedInBefore:)` makes that
three-way choice, and it's a pure function — which is why it has tests and the
window it opens doesn't need any.

## 4. The two loops

This is the heart of the app, and the one thing to understand if you
understand nothing else.

Spotify is polled **every 3 seconds**. Lyrics need to be right **every
frame**. Those are different clocks, and the gap between them is bridged by
extrapolation rather than by polling harder.

```mermaid
flowchart LR
    subgraph slow["Slow loop — every 3s (10s when idle)"]
        poll["NowPlayingPoller<br/>GET /currently-playing"] --> handle["coordinator.handle(state)"]
        handle --> anchor["clock.anchor(<br/>progressMs, isPlaying, now)"]
        handle --> track{"track<br/>changed?"}
        track -->|yes| fetch["fetchLyrics()"]
    end

    subgraph fast["Fast loop — every 100 ms"]
        timer["Timer 10 Hz"] --> pos["clock.positionMs(now)<br/><i>anchor + elapsed</i>"]
        pos --> tick["viewModel.tick(positionMs:)"]
        tick --> index["document.index(atPositionMs:)<br/><i>binary search</i>"]
        index --> draw["@Published display<br/>→ SwiftUI redraws"]
        timer --> hover["window.isPointerInside<br/>→ chrome visibility"]
    end

    anchor -.->|"read by"| pos
```

`PlayheadClock` is the whole trick, and it is 32 lines:

```
position = anchorProgress + (now − anchorTime)     while playing
position = anchorProgress                          while paused
```

Every poll re-anchors, so ordinary drift, a pause, and a seek all correct
themselves through one mechanism. There is no special case for any of them.

> **Why not poll faster?** Spotify rate-limits, and a 10 Hz poll would be
> antisocial and still not smooth. Extrapolation costs nothing and is exact
> between anchors.

## 5. Logging in — OAuth 2.0 with PKCE

No client secret exists anywhere in this app. PKCE replaces it: a random
`verifier` is generated per login, its SHA-256 `challenge` is sent up front,
and the verifier is only revealed when redeeming the code. Intercepting the
code alone gets you nothing.

```mermaid
sequenceDiagram
    participant U as User
    participant S as SetupWindow
    participant C as AppCoordinator
    participant W as WebAuthSession
    participant SP as Spotify
    participant A as SpotifyAuth
    participant K as Keychain

    U->>S: Log In with Spotify
    S->>C: reconfigure / logIn()
    C->>C: PKCE.generate() → verifier + challenge<br/>PKCE.randomState()
    C->>W: authenticate(authorizeURL, "floatinglyric")
    W->>SP: ASWebAuthenticationSession<br/><i>sheet over the app</i>
    U->>SP: username + password → Agree
    SP-->>W: floatinglyric://callback?code=…&state=…
    W-->>C: callback URL
    C->>C: SpotifyCallback.code(from:expectedState:)
    Note over C: state mismatch → reject (CSRF)
    C->>A: exchange(code, verifier, redirectURI)
    A->>SP: POST /api/token
    SP-->>A: access + refresh token
    A->>K: store refresh token
    C->>C: buildSession() → poller starts
```

If the sheet cannot be presented at all, `AppError.authUnavailable` sends the
coordinator down `logInWithBrowser`, the older flow: default browser plus a
one-shot local listener on port 8888–8890. User cancellation deliberately does
**not** trigger that fallback.

Afterwards, `SpotifyAuth.accessToken()` is the only way anything gets a token.
It refreshes when fewer than 60 seconds remain, so no caller ever thinks about
expiry.

## 6. Getting the lyrics

```mermaid
flowchart TD
    start(["track changed"]) --> cache{"cached on disk?"}
    cache -->|"synced / plain"| done(["show"])
    cache -->|"notFound &lt; 24h old"| none(["No lyrics found"])
    cache -->|miss| get["GET lrclib.net/api/get<br/><i>artist, title, album, duration</i>"]

    get -->|2xx + parses| pick
    get -->|no| search["GET /api/search<br/><i>artist, title</i>"]
    search --> match{"duration within<br/>±5 s?"}
    match -->|yes| pick["prefer syncedLyrics<br/>else plainLyrics"]
    match -->|no| none

    pick --> parse["LRCParser.parse()<br/><i>[mm:ss.xx] → ms</i>"]
    parse --> build["LyricsDocument<br/>+ romanization per line"]
    build --> write["cache.write()"]
    write --> done

    get -.->|network error| nocache(["notFound —<br/><b>not</b> cached"])
```

The distinction that matters: **"no lyrics exist" is cached for 24 hours; "the
network failed" is never cached.** Get that backwards and one flaky moment
poisons a song forever.

Romanization happens once here, at document construction — never in the view,
which redraws ten times a second.

## 7. Chrome visibility

After 3 idle seconds, everything but the lyrics fades: header, progress bar,
transport, traffic lights, and the blurred panel itself.

```mermaid
stateDiagram-v2
    [*] --> Visible
    Visible --> Hidden: 3 s with no pointer
    Hidden --> Visible: pointer enters
    Visible --> Visible: track change,<br/>button press,<br/>any activity

    note right of Hidden
        Lyrics still drawn.
        Panel alpha → 0, shadow off,
        traffic lights hidden.
    end note
```

Three details that each cost a bug:

- **Hover is polled**, not tracked — `FloatingWindow.isPointerInside` tests the
  mouse location against the window rect. This app is usually not the active
  one, and enter/exit events don't reliably reach a background window.
- **The blur is a sibling of the lyrics, not their parent.** Fading a parent
  fades its children; the words have to outlive the panel.
- **Hovering lifts opacity to a 35 % floor.** Without it, dragging the slider
  to 0 % leaves a window nobody can find again.

## 8. Pressing play

```mermaid
sequenceDiagram
    participant U as User
    participant V as LyricViewModel
    participant C as AppCoordinator
    participant P as PlaybackController
    participant S as Spotify

    U->>V: tap ⏯
    V->>V: isPlaying.toggle() — <b>immediately</b>
    V->>C: onPlayPause()
    C->>P: toggle(isPlaying: wasPlaying)
    P->>S: PUT /me/player/pause
    alt 403 / 404 / 429
        P-->>C: AppError
        C->>V: report(controlError:) — shown 3 s
    end
    C->>C: sleep 400 ms
    C->>C: poller.pollOnce() → handle(state)
    Note over V: the real state overwrites the optimistic guess
```

The optimistic flip is deliberate. Spotify applies commands asynchronously; a
button that waits for the next poll feels broken, so it lies for 400 ms and
then tells the truth.

## 9. Who runs on which thread

```mermaid
flowchart LR
    subgraph mainactor["@MainActor — UI only"]
        AC["AppCoordinator"]
        VM["LyricViewModel"]
        FW["FloatingWindow"]
        MB["MenuBarController"]
    end

    subgraph background["Sendable — any thread"]
        NP["NowPlayingPoller"]
        LP["LyricsProvider"]
        SA["SpotifyAuth"]
        PC["PlaybackController"]
    end

    NP -->|"Task { @MainActor }"| AC
    LP -->|"await → hop"| AC
    AC --> VM
```

Everything that touches AppKit or SwiftUI is `@MainActor`. Everything that does
network work is `Sendable` and runs anywhere. The boundary is crossed in
exactly one direction, with an explicit hop.

## 10. Why so much of it is testable

173 tests run in about half a second, with no network and no window server.
That's not luck — decisions are pulled out into pure types that take their
inputs as arguments:

| Type | Decides | Notice |
|---|---|---|
| `PlayheadClock` | where the playhead is | takes `now` as a parameter |
| `ChromeVisibility` | is the chrome shown | takes `now` and `lastActivity` |
| `LoginPrompt` | which login screen | takes the stored state |
| `PanelOpacity` | alpha from percent | no window involved |
| `PanelToggle` | show / hide / restore | takes two booleans |
| `SpotifyCallback` | is this callback valid | takes a URL |
| `LRCParser` | text → timed lines | a string in, an array out |

None of them read a clock, a `UserDefaults`, or a window. The awkward,
untestable parts — AppKit, timers, the network — are kept thin and stupid on
purpose, and `StubHTTPClient` covers the rest.

---

## Reading the rest

- Behaviour to match when porting: [`porting.md`](porting.md)
- Using the app: [`../macos/README.md`](../macos/README.md)
- Original design and plan: [`superpowers/`](superpowers/)
