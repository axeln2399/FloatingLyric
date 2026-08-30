# FloatingLyric — Design

**Date:** 2026-08-30
**Status:** Approved

## Purpose

A macOS menu-bar app that shows time-synced lyrics for whatever the user is
currently playing on Spotify, in a translucent always-on-top window. Modelled on
the Musixmatch desktop floating-lyrics experience.

Track state comes from the Spotify Web API, so lyrics follow playback on any
device signed in to the account — phone, another Mac, a speaker — not just the
local Spotify app.

## Success criteria

1. User logs in to Spotify once; the app stays logged in across restarts.
2. Playing a song on any Spotify device shows its lyrics within ~3 seconds.
3. The highlighted line matches what is being sung, within about half a second
   after the user has set their sync offset.
4. The window floats above other apps, on every Space, without stealing focus.
5. `./build.sh` produces a distributable `FloatingLyric.dmg`.

## Non-goals

Playback controls, lyric translation, contributing lyrics back to LRCLIB, Apple
Music or other players, auto-update, Windows or Linux.

## Constraints

- macOS 14+ (built and tested on macOS 26.0.1).
- Swift 5.9+, SwiftUI with AppKit for windowing. No third-party dependencies.
- No paid Apple Developer account: the `.dmg` is unsigned and un-notarized.
- Spotify developer app stays in development mode (owner + up to 25 added
  users). Reading playback state works on free Spotify accounts; no Premium
  required.

## Architecture

Four units, each with one purpose and a protocol boundary so it can be tested
alone.

```
SpotifyAuth      -- OAuth PKCE login; tokens in Keychain; auto-refresh
    | access token
NowPlayingPoller -- polls /me/player/currently-playing every 3s
    | NowPlaying(trackID, title, artist, album, durationMs, progressMs, isPlaying)
LyricsProvider   -- LRCLIB lookup -> [LyricLine]; on-disk cache
    | [LyricLine(timeMs, text)]
PlayheadClock    -- extrapolates position between polls
    |
LyricView        -- floating NSPanel; highlights the line for the current time
```

`AppCoordinator` owns the four and wires them together. `MenuBarController` owns
the `NSStatusItem` and its menu.

### Module responsibilities

**SpotifyAuth**
- Does: obtains and maintains a valid access token.
- Interface: `func currentAccessToken() async throws -> String`, `func
  logIn() async throws`, `func logOut()`, `var isLoggedIn: Bool`.
- Depends on: Keychain, a local HTTP listener, `URLSession`.

**NowPlayingPoller**
- Does: reports what is playing, or that nothing is.
- Interface: `var state: AsyncStream<PlaybackState>` where `PlaybackState` is
  `.playing(NowPlaying)`, `.paused(NowPlaying)`, `.idle`, `.error(AppError)`.
- Depends on: `SpotifyAuth`, an injected `HTTPClient` protocol.

**LyricsProvider**
- Does: turns a track identity into lyric lines.
- Interface: `func lyrics(for track: TrackIdentity) async -> LyricsResult` where
  `LyricsResult` is `.synced([LyricLine])`, `.plain(String)`, or `.notFound`.
- Depends on: an injected `HTTPClient`, a `LyricsCache`.

**PlayheadClock**
- Does: given the last poll anchor, answers "what millisecond are we at now?"
- Interface: `func anchor(progressMs:at:isPlaying:)`, `func
  positionMs(now:) -> Int`.
- Depends on: nothing. Pure. Fully unit-testable.

**LyricView / FloatingPanel**
- Does: renders lines and the highlight; handles dragging.
- Depends on: a view model exposing `[LyricLine]` and `currentIndex`.

## Authentication

Authorization Code with PKCE. No client secret, so nothing sensitive ships in
the app.

1. First run shows a setup window explaining how to create a Spotify developer
   app and where to paste the Client ID. Redirect URI to register:
   `http://127.0.0.1:8888/callback`. (Spotify permits plain-HTTP loopback
   redirects on `127.0.0.1`; `localhost` is not accepted.)
2. On "Log in": generate `code_verifier` and `code_challenge`, start a
   single-shot `NWListener` on 127.0.0.1:8888, open the system browser to
   `https://accounts.spotify.com/authorize`.
3. Catch the redirect, verify `state`, respond with a small "you can close this
   tab" page, shut the listener down.
4. Exchange the code at `https://accounts.spotify.com/api/token`.
5. Store the refresh token in the Keychain (`kSecClassGenericPassword`, service
   `com.floatinglyric.tokens`). Keep the access token in memory only.
6. Refresh 60 seconds before expiry, and on any 401 (once, then surface the
   error).

Scope requested: `user-read-playback-state` only.

If port 8888 is occupied, try 8889 and 8890, then show an error asking the user
to free the port. The Client ID is stored in `UserDefaults` (not secret).

## Polling and sync

`NowPlayingPoller` requests `GET /v1/me/player/currently-playing` every 3
seconds while a song is playing, and every 10 seconds while idle or paused
(saves battery and rate limit; the API allows far more than this).

Response handling:
- `204 No Content` or null item → `.idle`.
- `429` → back off for the `Retry-After` interval.
- `401` → ask `SpotifyAuth` to refresh, retry once.
- Network failure → `.error`, keep the previous lyrics on screen, retry next tick.

Each successful poll re-anchors `PlayheadClock` with `progress_ms` and the
receipt time. Between polls a 100 ms UI timer advances the position from that
anchor, so the highlight moves smoothly rather than in 3-second steps.

A track change is detected by comparing track ID; a seek is detected when the
polled position differs from the extrapolated position by more than 1500 ms. In
both cases the clock re-anchors immediately, and a track change triggers a
lyrics fetch.

**Sync offset.** Network latency and the API's own granularity can put the
highlight a few hundred milliseconds off. The menu carries a user-adjustable
offset from -2000 ms to +2000 ms, applied when selecting the current line, and
persisted in `UserDefaults`.

## Lyrics

Source: LRCLIB (`https://lrclib.net`), free and keyless.

1. `GET /api/get?artist_name=&track_name=&album_name=&duration=` with the values
   from Spotify. `duration` is in seconds; LRCLIB matches within a couple of
   seconds' tolerance.
2. On 404, `GET /api/search?artist_name=&track_name=` and take the first result
   whose duration is within 5 seconds of the Spotify duration.
3. Prefer the `syncedLyrics` field. If it is null but `plainLyrics` is present,
   return `.plain`. If neither, `.notFound`.

Requests send a descriptive `User-Agent`
(`FloatingLyric/1.0 (macOS lyrics overlay; contact via app repository)`), as
LRCLIB asks.

**LRC parsing.** Lines look like `[mm:ss.xx] text`. The parser must handle:
multiple timestamps on one line (repeat the text for each), metadata tags
(`[ar:]`, `[ti:]`, `[offset:]` — apply `offset` if present, ignore the rest),
blank lyric lines (keep them, they are pauses), malformed lines (skip), and
unsorted timestamps (sort by time after parsing).

**Current line selection.** Binary search for the last line whose timestamp is
less than or equal to `position + offset`. Before the first timestamp, no line
is highlighted.

**Cache.** `~/Library/Application Support/FloatingLyric/lyrics/<trackID>.json`,
holding the parsed lines and a fetch date. Cache negative results too, for 24
hours, so missing songs are not re-requested every replay. No size limit
initially; entries are a few kilobytes.

## The window

A borderless `NSPanel` subclass:
- `styleMask`: `.borderless`, `.nonactivatingPanel`.
- `level`: `.floating`. `collectionBehavior`: `.canJoinAllSpaces`,
  `.fullScreenAuxiliary`, `.stationary`.
- `isOpaque = false`, clear background, an `NSVisualEffectView` (`.hudWindow`,
  behind-window blending) for the blur.
- Dragging: `isMovableByWindowBackground = true`. Frame saved to `UserDefaults`
  and restored, clamped to a visible screen on launch in case a display was
  removed.

Content: track title and artist at the top, three to five lyric lines with the
current one at full opacity and larger weight while neighbours dim, and a thin
progress bar with elapsed/total time. Line transitions animate over ~250 ms.

`Info.plist` sets `LSUIElement = true`, so there is no Dock icon and the app
never takes focus.

**Menu bar** (`NSStatusItem`): Show/Hide Lyrics · Lock Position · Click Through ·
Font Size (S/M/L) · Sync Offset (a slider item) · Log Out · Quit.

"Click Through" sets `ignoresMouseEvents = true` so the panel becomes purely
visual; it is turned off again from the menu.

## Error states

Every failure is a legible state inside the panel, never a crash or a dialog:

| Condition | Panel shows |
|---|---|
| No Client ID configured | "Set up Spotify to begin" + button opening setup |
| Not logged in | "Log in to Spotify" + button |
| Nothing playing | "Nothing playing" + app name |
| Paused | Lyrics stay, dimmed, highlight frozen |
| Lyrics not found | Track title + "No lyrics found" |
| Unsynced lyrics only | Full text, scrollable, no highlight |
| Network down | Last lyrics stay + a small "offline" indicator |
| Token refresh failed | "Session expired — log in again" + button |

## Testing

Unit tests (`swift test`), no network:

- **LRC parser**: well-formed input; multiple timestamps per line; `[offset:]`
  applied; metadata ignored; malformed lines skipped; empty input; unsorted
  timestamps sorted; blank lyric lines preserved.
- **Current-line selection**: exactly on a timestamp; between two; before the
  first; after the last; with positive and negative offsets; single-line lyrics.
- **PlayheadClock**: extrapolation while playing; frozen while paused; re-anchor
  on seek; seek-detection threshold at its boundary.
- **Token lifecycle**: refresh triggered before expiry; 401 triggers exactly one
  retry; refresh failure surfaces `.error`.
- **LyricsProvider**: `/api/get` hit; 404 falling back to search; search result
  rejected on duration mismatch; synced preferred over plain; cache hit avoids a
  request; negative cache expires after 24 hours.

`HTTPClient` is a protocol; tests inject a stub returning canned responses.

Manual verification: run against the user's real Spotify account and confirm
login, track change, pause, seek, a song with no lyrics, and the offset slider.

## Packaging

`build.sh`:
1. `swift build -c release --arch arm64 --arch x86_64` (universal binary).
2. Assemble `FloatingLyric.app` — `Contents/MacOS/FloatingLyric`,
   `Contents/Info.plist`, `Contents/Resources/AppIcon.icns`.
3. Ad-hoc sign: `codesign --force --deep -s - FloatingLyric.app`.
4. Stage the app plus an `/Applications` symlink, then `hdiutil create
   -format UDZO` → `FloatingLyric.dmg`.

Because the app is unsigned by a Developer ID, Gatekeeper blocks the first
launch. The README documents both fixes: right-click the app → Open → Open, or
`xattr -cr /Applications/FloatingLyric.app`.

## Repository layout

```
Package.swift
build.sh
README.md
Sources/FloatingLyric/
  App/            AppDelegate, AppCoordinator, MenuBarController
  Auth/           SpotifyAuth, PKCE, KeychainStore, CallbackListener
  Playback/       NowPlayingPoller, PlayheadClock, Models
  Lyrics/         LyricsProvider, LRCParser, LyricsCache
  UI/             FloatingPanel, LyricView, SetupWindow
  Support/        HTTPClient, AppError
Tests/FloatingLyricTests/
Resources/        Info.plist, AppIcon.icns
docs/superpowers/specs/
```

## Open risks

- LRCLIB coverage is community-driven; obscure tracks may have no lyrics. The
  `.notFound` state handles it, and nothing else in the app depends on lyrics
  existing.
- Spotify could change Web API redirect or scope policy. Auth is isolated in one
  module, so a change is contained there.
- If sync via the Web API proves too loose in practice even with the offset, a
  later enhancement could read position from the local Spotify app via
  AppleScript when it is running. Deliberately not built now.
