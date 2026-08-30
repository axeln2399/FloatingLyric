# Porting FloatingLyric

What every version of FloatingLyric has to do, written so it can be implemented
in any language — plus what each platform can and cannot deliver.

The macOS app in [`../macos/`](../macos/) is the reference implementation. Where
this document and that code disagree, the code is right and this document is a
bug.

---

## The rule this repo follows

**Platforms share the specification, not the code.**

Each platform directory is self-contained: its own project, build and tests, no
build-time dependency on any other. That is a deliberate choice, and it is worth
understanding before someone "fixes" it.

The macOS app is ~2,600 lines. About 1,000 are platform-agnostic logic — LRC
parsing, the playhead clock, lyrics fetching, the Spotify polling and control,
the visibility rules. The other 1,600 are AppKit and SwiftUI, and don't move
anywhere.

So the prize for sharing code is a thousand lines of parsing and HTTP. The
price is compiling Swift on Android and Windows through toolchains that are
experimental at best, forever, on every build. Rewriting a thousand lines in
each ecosystem's own idioms is cheaper, and the result is code that a developer
on that platform can actually read.

Even inside that "portable" thousand, four pieces are Apple-only anyway:

| macOS file | Depends on | Elsewhere |
|---|---|---|
| `KeychainStore.swift` | Security.framework | Windows Credential Manager, Android Keystore/EncryptedSharedPreferences |
| `CallbackListener.swift` | Network.framework | any socket or embedded HTTP library |
| `PKCE.swift` | CryptoKit | any SHA-256 |
| `Transliteration.swift` | CoreFoundation's ICU tokenizer | Android has `android.icu.text.Transliterator`; Windows has no equivalent |

---

## The specification

Everything below is what the macOS app actually does. Match it and the versions
will feel like the same app.

### Authentication — OAuth 2.0 with PKCE

No client secret. The app is public; PKCE is what makes that safe.

| | Value |
|---|---|
| Authorize | `https://accounts.spotify.com/authorize` |
| Token | `https://accounts.spotify.com/api/token` |
| Scopes | `user-read-playback-state user-modify-playback-state` |
| Challenge method | `S256` |
| Redirect URI | `floatinglyric://callback` (primary), or `http://127.0.0.1:PORT/callback` with PORT tried in order **8888, 8889, 8890** (fallback) |
| Refresh margin | Refresh when the token has **60 s** or less left |

Prefer a **private URL scheme** over a loopback listener where the platform can
intercept one: macOS uses `ASWebAuthenticationSession`, which shows Spotify's
page in a sheet over the app, shares the system browser's cookies, and needs no
local web server, no port, and no firewall permission. Android and iOS have the
same thing in Custom Tabs and `ASWebAuthenticationSession`. Keep the loopback
flow only as a fallback for platforms without one.

If you use loopback: `127.0.0.1`, never `localhost` — Spotify rejects the
latter. Either way the redirect URI must match what's registered in the user's
Spotify dashboard character for character, so whichever scheme a platform uses
must be listed in the setup instructions you give the user.

Store the **refresh token** in the platform's secure store, never in plain
preferences. The client ID is not a secret and lives in ordinary settings.

Verify `state` on the callback and reject a mismatch — that's CSRF protection,
not decoration.

### Now playing — polling

| | Value |
|---|---|
| Endpoint | `GET https://api.spotify.com/v1/me/player/currently-playing` |
| Poll while playing | **3,000 ms** |
| Poll while idle or paused | **10,000 ms** |
| `204` or empty body | Nothing is playing |
| `401` | Refresh the token once, retry once, then report the session expired |
| `429` | Honour `Retry-After`, and never poll faster than it says |

On mobile, prefer Spotify's own iOS/Android SDK over this polling: it reports
local playback state with no lag and no rate limit.

### The playhead clock

Polling every 3 seconds is far too coarse to highlight a lyric line. Between
polls, extrapolate:

- Each poll **anchors**: store `progressMs` and the current time.
- Position = `anchor + (now − anchorTime)` while playing; frozen at `anchor`
  while paused.
- A poll whose reported progress differs from the extrapolation by more than
  **1,500 ms** is a **seek**, not drift.
- Re-anchor on every poll regardless. That handles ordinary drift, pause and
  seek with one mechanism.
- Tick the UI at **10 Hz**.

Never let the clock run backwards past zero, and never trust that time moves
forward — sleep and clock sync both break that assumption.

### Lyrics — LRCLIB

Free, no key, no account. Send a real `User-Agent` identifying your app.

1. `GET https://lrclib.net/api/get?artist_name=&track_name=&album_name=&duration=`
   — duration in **seconds**. Take it if it returns 2xx and parses.
2. Otherwise `GET https://lrclib.net/api/search?artist_name=&track_name=` and
   take the first result whose duration is within **±5 s** of the track.
3. Otherwise: not found.

Prefer `syncedLyrics`; fall back to `plainLyrics`; then not found.

**Cache on disk, keyed by Spotify track ID.** Successes cache forever — lyrics
don't change. A "not found" caches for **24 hours**, so a missing song isn't
re-fetched every time it plays. A *network failure* caches nothing, ever; that's
the distinction that matters, and it is easy to get wrong.

### LRC parsing

- Timestamps: `[mm:ss.xx]`, `[mm:ss.xxx]`, `[mm:ss]`, and `[mm:ss:xx]`.
- Fractions are left-aligned: `.5` → 500 ms, `.50` → 500 ms, `.500` → 500 ms.
- One line may carry several timestamps — emit one entry per timestamp.
- `[offset:±ms]` shifts every line; apply it, then clamp results at 0.
- Ignore any other `[tag:value]` metadata line.
- Sort by time at the end. Never assume the file is ordered.

Current line = the **last** line whose time ≤ position + user offset. Binary
search it; this runs at 10 Hz.

### Playback control

| Action | Method | Path under `https://api.spotify.com/v1/me/player` |
|---|---|---|
| Play | `PUT` | `/play` |
| Pause | `PUT` | `/pause` |
| Next | `POST` | `/next` |
| Previous | `POST` | `/previous` |

Send `Content-Length: 0` on the PUTs — Spotify rejects a body-less PUT without
it. Responses:

| Status | Means |
|---|---|
| `403` with "scope" in the body | Token predates the control scope — user must log out and back in |
| `403` otherwise | **Spotify Premium required** |
| `404` | No active device |
| `429` | Rate limited; honour `Retry-After` |

Flip the play/pause button **immediately** on tap, then re-poll after ~400 ms.
Spotify applies commands asynchronously, and a button that waits for the next
poll feels broken.

### Romanization

Under any lyric line containing letters outside the Latin blocks, show a Latin
reading. Lines already in Latin script get nothing — an English song must look
untouched.

- "Non-Latin" = any alphabetic character outside U+0000–U+024F, U+0250–U+02AF
  and U+1E00–U+1EFF.
- Try a **language-aware tokenizer first**. Kanji have no single sound: 名 is
  *na* here and *mei* there, and only a tokenizer that has read the surrounding
  words can tell. Detect the language rather than assuming Japanese.
- Fall back to a plain Any→Latin transform, which handles Hangul, Cyrillic,
  Greek and Thai perfectly well.
- Collapse whitespace; strip combining marks only if something non-Latin
  survived.
- Return nothing if the result is empty or identical to the input.

Compute it **once per track**, not per frame — the macOS build measures ~27 ms
for 80 dense Japanese lines, which is fine once and disastrous at 10 Hz.

### Window behaviour

The part users actually feel. Percentages are of full opacity.

| | Value |
|---|---|
| Idle timeout | **3 s** with no pointer over the window |
| On idle | Hide **everything but the lyrics**: header, progress, transport, window buttons, **and the panel background itself** |
| On hover | All of it returns, and stays while the pointer remains |
| Opacity | User-set **0–100 %**, default **60 %** |
| Hover floor | A window under **35 %** rises to 35 % while hovered |
| Font sizes | 14 / 18 / 24 |
| Sync offset | ±2,000 ms, user-adjustable |

Three traps worth naming, each of which cost the macOS build a bug:

- **Hover must be polled, not tracked.** This app is usually not the active one,
  and enter/exit events are not delivered reliably to a background window. Test
  the pointer position against the window rectangle instead.
- **The background must not be the parent of the lyrics.** Fade a parent and the
  text goes with it. Draw the panel as a sibling *behind* the text.
- **The hover floor is not a nicety.** Without it, dragging opacity to 0 leaves
  a window that cannot be seen, found or recovered.

Lyric lines **wrap**; they are never truncated. If the wrapped lines overflow,
scroll them and keep the current line in view.

### Settings to persist

`clientID`, `syncOffsetMs`, window frame, `fontSize`, `opacityPercent`,
`clickThrough`, `lockPosition`, `showRomaji`, `autoHideChrome`. Refresh token to
the secure store; everything else to ordinary preferences.

---

## What each platform can deliver

### Windows — works

An always-on-top layered window is straightforward. WinUI 3, WPF, Compose
Desktop, Flutter and Tauri can all do it, along with click-through
(`WS_EX_TRANSPARENT`) and per-window opacity.

The one real gap is **romanization**: Windows ships no ICU transliterator. You
need an ICU binding, or a per-language library, or you drop the feature. Decide
before you start — it's a feature users of Japanese and Korean songs will miss.

Distribution is free: ship a plain `.exe` or an MSIX. The Microsoft Store is
optional and costs $19 once.

### Android — works, and is the closest match

`SYSTEM_ALERT_WINDOW` ("Display over other apps") gives a genuine floating
overlay over other apps — the same product as the macOS version. The permission
needs an explicit trip to Settings, which you must walk the user through, and
Play Store review scrutinizes it, but a lyrics overlay is exactly the kind of
use it exists for.

Two things Android gives you free: `android.icu.text.Transliterator` covers
romanization, and Spotify's Android SDK gives local playback state without
polling.

Run the overlay from a **foreground service** with a notification, or Android
will kill it. Play Store registration is $25, once.

### iOS — a different product

**The overlay is impossible.** iOS has no API for drawing over other apps, by
design. Nothing in this section is a toolchain problem someone will solve.

What is possible: a full-screen lyrics app, a **Live Activity** on the Lock
Screen and Dynamic Island, or a widget. All are worth building — none of them is
this app. Decide which product you're making before opening Xcode.

Also: background polling is heavily restricted, so a foreground lyrics view is
the honest shape. Distribution needs the same $99/year account as
[`../macos/docs/apple-developer-id.md`](../macos/docs/apple-developer-id.md).

---

## If you'd rather write it once

Two credible ways to cover Windows and Android with one codebase:

- **Kotlin Multiplatform + Compose Multiplatform** — best Android story, real
  Windows desktop target, shared logic in Kotlin. Most natural if Android is
  the priority.
- **Flutter** — one codebase for both, with existing plugins for desktop
  always-on-top and Android overlays.

Both mean leaving Swift behind for those platforms. That is fine: this repo
already assumes each platform is written in whatever that platform speaks.
macOS stays as it is.

What is **not** recommended: Swift on Windows (no SwiftUI, so you'd rewrite the
UI anyway) or Swift on Android (experimental toolchain, and you would still
rewrite the UI). Both give you the thousand shared lines at the cost of fighting
a build system on every change.

---

## Adding a platform to this repo

1. Create the directory with its own project and build, at the top level.
2. Its README states the stack, how to build it, and where it knowingly differs
   from this specification.
3. Add a row to the table in the [root README](../README.md).
4. Don't add a build-time dependency on another platform directory. If you find
   yourself wanting one, what you actually want is a paragraph added to this
   file.
