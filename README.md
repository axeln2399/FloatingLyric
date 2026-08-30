# FloatingLyric

Time-synced lyrics for whatever you're playing on Spotify, in a translucent
always-on-top window on macOS. Lyrics follow your Spotify *account*, so they
work whether you're playing on this Mac, your phone, or a speaker.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)

## Install

1. Download or build `FloatingLyric.dmg` (see [Build](#build-from-source)).
2. Open the DMG and drag **FloatingLyric** into **Applications**.
3. The app is unsigned, so macOS blocks the first launch. Either:
   - right-click **FloatingLyric** in Applications → **Open** → **Open**, or
   - run `xattr -cr /Applications/FloatingLyric.app`

## Set up Spotify (one time, ~2 minutes)

FloatingLyric talks to your own Spotify developer app, so no credentials are
shared with anyone.

1. Go to <https://developer.spotify.com/dashboard> and click **Create app**.
2. Name it anything (e.g. `FloatingLyric`).
3. Set **Redirect URI** to exactly:

   ```
   http://127.0.0.1:8888/callback
   ```

4. Tick **Web API**, save, then copy the **Client ID**.
5. Paste the Client ID into FloatingLyric's setup window and click
   **Save and Log In**. Your browser opens once to authorize.

Reading playback works on **free** Spotify accounts — Premium is not required.
The app requests only the `user-read-playback-state` scope, so it can never
control playback or see anything else about your account.

## Using it

- The floating window shows the current line bright and its neighbours dimmed.
- Drag it anywhere. It stays above other apps and follows you across Spaces.
- Menu bar icon (♪):
  - **Show / Hide Lyrics** (⌘L)
  - **Lock Position** — stop accidental dragging
  - **Click Through** — make the window purely visual; clicks pass through to
    whatever is behind it
  - **Font Size** — Small / Medium / Large
  - **Sync offset** — nudge ±2000 ms if the highlight runs early or late
  - **Spotify Setup…**, **Log Out**, **Quit** (⌘Q)

## How it works

```
SpotifyAuth      OAuth PKCE login; refresh token in the macOS Keychain
    ↓
NowPlayingPoller polls /me/player/currently-playing every 3s
    ↓
PlayheadClock    extrapolates the playhead between polls, 10x a second
    ↓
LyricsProvider   LRCLIB lookup → parsed .lrc lines, cached on disk
    ↓
FloatingPanel    highlights the line matching the current time
```

Polling only gives a position every 3 seconds, so `PlayheadClock` advances the
playhead locally between polls and re-anchors on each one. That's what makes
the highlight move smoothly instead of jumping in 3-second steps.

## Where lyrics come from

[LRCLIB](https://lrclib.net) — a free, community-maintained database of
time-synced lyrics. No API key needed. Songs without an entry show
"No lyrics found"; songs with only plain lyrics show the full text without
highlighting. Fetched lyrics are cached in
`~/Library/Application Support/FloatingLyric/lyrics/`, so replays are instant
and work offline.

## Build from source

```bash
swift test     # 75 tests, all offline
./build.sh     # → dist/FloatingLyric.app and dist/FloatingLyric.dmg
```

Requires macOS 14+ and **Xcode** (not just the Command Line Tools — `swift test`
needs XCTest, which only ships with Xcode). `build.sh` points at
`/Applications/Xcode.app` automatically if `xcode-select` isn't set to it.

No third-party dependencies — Apple frameworks only.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "App is damaged and can't be opened" | `xattr -cr /Applications/FloatingLyric.app` |
| Login browser page never returns | Redirect URI must be `http://127.0.0.1:8888/callback` exactly — not `localhost` |
| "Port 8888–8890 in use" | Quit whatever holds those ports, then log in again |
| Highlight runs early or late | Adjust **Sync offset** in the menu bar |
| "Session expired" | Menu bar → **Log Out**, then log in again |
| `no such module 'XCTest'` when building | `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` |

## Privacy

The refresh token lives in your macOS Keychain. The Client ID lives in
`UserDefaults`. Nothing is sent anywhere except Spotify's API and LRCLIB.

## Docs

- Design: `docs/superpowers/specs/2026-08-30-floatinglyric-design.md`
- Implementation plan: `docs/superpowers/plans/2026-08-30-floatinglyric.md`
