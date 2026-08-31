# FloatingLyric for Windows

Time-synced lyrics in a window that floats above everything else, driven by
your Spotify account. The Windows port of [`../macos/`](../macos/).

**Status: complete, unverified on Windows.** Every feature of the macOS app is
implemented and 127 tests pass, but it has only ever been *run* on macOS —
Avalonia is cross-platform, so the UI starts there, but nobody has yet launched
the `.exe` on real Windows. See [What is and isn't verified](#what-is-and-isnt-verified).

## Build it

```bash
dotnet test                                   # 127 tests, no network
dotnet publish src/FloatingLyric.App/FloatingLyric.App.csproj \
  -c Release -r win-x64 --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
  -o dist/win-x64
```

Out comes `dist/win-x64/FloatingLyric.exe` — a single self-contained file
(~92 MB, because it carries its own .NET runtime, so nobody installs anything
to run it).

**This works from macOS or Linux.** Unlike WinUI, WPF, Flutter-for-Windows and
`jpackage`, .NET cross-publishes: the `.exe` is a genuine PE32+ x86-64 binary
whichever machine builds it. That is why this port uses Avalonia.

Needs the .NET 9 SDK. A push to `main` also builds it on a free
`windows-latest` runner — see
[`.github/workflows/windows.yml`](../.github/workflows/windows.yml) — and the
`.exe` lands in that run's artifacts.

## Run it

Double-click the `.exe`. There is no installer and nothing is written outside
`%APPDATA%\FloatingLyric`.

The first launch offers a single **Log In with Spotify** button — the app ships
with its own Spotify registration, so there is no Client ID to paste. Your
browser opens Spotify's own page; sign in, click Agree, and the tab reports
back.

> Your friend still has to be added to the Spotify app's user list before they
> can log in — a registration in Development Mode admits 25 users, added by
> hand. See the macOS README's "Sending it to a friend".

Windows may warn that the publisher is unknown (SmartScreen): **More info →
Run anyway**. An Authenticode certificate would remove that; there isn't one.

## Using it

Everything lives in the tray icon (**♪**), because the window has no title bar
and no taskbar button:

| Item | What it does |
|---|---|
| **Show / Hide Lyrics** | Toggle the floating window |
| **Refetch Lyrics** | Drop what's cached for this track and ask again |
| **Play / Pause**, **Next**, **Previous** | Control Spotify — needs Premium |
| **Lock Position** | Stop accidental dragging |
| **Click Through** | Clicks pass through to whatever is behind |
| **Romaji Under Lyrics** | Latin readings under non-Latin lines |
| **Auto-Hide Controls** | Fade everything but the lyrics after 3 idle seconds |
| **Font Size** | Small / Medium / Large |
| **Opacity** | 0–100%, in steps, plus nudges |
| **Sync Offset** | ±1000 ms if the highlight runs early or late |
| **Use My Own Client ID…** | Point the app at your own Spotify registration |

Drag the window anywhere; it remembers position and size in
`%APPDATA%\FloatingLyric\settings.json`.

After three seconds without the pointer, everything but the lyrics fades —
including the panel behind them. Hovering brings it back. A window dragged to
0% opacity rises to 35% while hovered, so it can always be found again.

## What is and isn't verified

Honesty matters more here than a green badge, because this port was written and
built entirely on a Mac.

**Verified:**

- 127 tests pass, covering the parsing, timing, matching, auth and error
  handling — including the tests translated line by line from the Swift suite.
- `dotnet publish` emits a real Windows binary: `PE32+ executable (GUI)
  x86-64`, checked by reading the PE header.
- The app launches and runs on macOS without crashing, which exercises the
  window, tray icon, coordinator, timer loop and settings.

**Not verified — needs someone on Windows:**

- That the `.exe` starts at all on Windows.
- Always-on-top behaviour against real applications, and against full-screen
  games (a topmost window loses to exclusive full screen; that is a Windows
  rule, not a bug here).
- Click-through, which is `WS_EX_TRANSPARENT` set through P/Invoke.
- DPAPI storage of the refresh token — on a Mac the app falls back to an
  in-memory store, so login does not survive a restart there.
- The full Spotify login round trip.
- Tray icon rendering and menu behaviour.

If something fails, [`../docs/architecture.md`](../docs/architecture.md)
explains what the code is trying to do.

## Where it differs from the macOS app

Not omissions to fix later — each is a platform constraint:

| | macOS | Windows |
|---|---|---|
| **Romaji** | Kana, kanji, Hangul, Cyrillic, Greek, Thai, via ICU | **Kana, Cyrillic and Greek only.** Windows ships no transliteration engine, so the tables here are hand-written. **Kanji are refused rather than guessed** — reading them needs a dictionary and the surrounding words, and half a line in Latin is worse than none. |
| **Login** | Sheet inside the app (`ASWebAuthenticationSession`) | The default browser plus a one-shot loopback listener on 8888–8890. Windows has no equivalent API. Needs `http://127.0.0.1:8888/callback` in the dashboard. |
| **Token storage** | Keychain | DPAPI, scoped to the Windows user account |
| **Opacity** | A live slider in the menu | Steps plus nudges — a tray menu cannot hold a slider |
| **Chrome fade** | Animated | Instant. Avalonia can animate it; nobody has tuned it against real Windows compositing yet |

## Layout

```
src/FloatingLyric.Core/   all the logic, no UI — the part with tests
src/FloatingLyric.App/    Avalonia: window, tray icon, coordinator
tests/                    127 xunit tests, no network
```

`FloatingLyric.Core` deliberately references nothing but the .NET base library,
which is why its tests run in 26 ms and why the whole of it could be reused by
another Windows UI if Avalonia ever proves the wrong bet.
