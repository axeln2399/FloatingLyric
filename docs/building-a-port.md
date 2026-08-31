# Building FloatingLyric for another platform

A practical how-to: what to install, what to write, in what order, and how to
ship it.

This is the *doing* half. The *what* half — endpoints, timings, parsing rules,
window behaviour — is in [`porting.md`](porting.md), and how the existing code
is arranged is in [`architecture.md`](architecture.md). Keep `porting.md` open
beside you; this file assumes it.

---

## What you already have

Checked on this Mac:

| | Status |
|---|---|
| **Xcode 26.2** | installed — iOS ready |
| **Android Studio** + SDK 35/36, emulator, `adb` | installed — Android ready |
| **Java 17** | installed |
| Flutter / Dart | not installed |
| .NET | not installed |

So **Android is the port you can start this afternoon** with nothing new to
install.

**Windows can be built from a Mac — with the right stack.** An earlier version
of this file said otherwise, and that was wrong in an important way. WinUI, WPF,
Flutter-for-Windows and `jpackage` do all need to *run on Windows*. **.NET does
not:** `dotnet publish -r win-x64` on macOS emits a genuine PE32+ x86-64
executable. That is exactly why [`../windows/`](../windows/) is C# and Avalonia
— the whole port was written, built and published from this Mac.

If you pick a stack that cannot cross-compile, three ways round it:

1. **GitHub Actions** with a `windows-latest` runner — free for public repos,
   and already wired up at
   [`../.github/workflows/windows.yml`](../.github/workflows/windows.yml).
2. A Windows PC, or Windows in a VM.
3. Compose Desktop, which runs on any JVM — develop on the Mac, and only need
   Windows for the final installer.

Building is not the same as *verifying*, though. Nothing on a Mac tells you
whether an always-on-top window behaves, whether P/Invoke works, or whether the
tray icon renders. Plan on someone running it there.

---

## The build order

Do not start with the window. Start with the part you can prove is right.

Each milestone below ends in something runnable. Resist merging them: a port
that stalls at 70 % is usually one that had nothing to show for the first three
weeks.

### 0 — Port the pure types, and their tests

The macOS app keeps every real decision in a type that takes its inputs as
arguments — no clocks, no preferences, no windows. Those port almost
mechanically, **and so do their tests.** This is the cheapest correctness you
will ever buy: a day's work that pins down the fiddly half of the app.

| Port this | Its tests | Roughly |
|---|---|---|
| `LRCParser` | `LRCParserTests` | 66 lines |
| `PlayheadClock` | `PlayheadClockTests` | 32 lines |
| `LyricsDocument` | `LyricsDocumentTests` | 50 lines |
| `ChromeVisibility` | `ChromeVisibilityTests` | 18 lines |
| `PanelOpacity` | `PanelOpacityTests` | 39 lines |
| `LoginPrompt` | `LoginPromptTests` | 30 lines |
| `SpotifyCallback` | `SpotifyCallbackTests` | 37 lines |

Read the Swift — 272 lines across all seven — write the equivalent in your
language, then translate the test file line by line. When those pass, the timing logic is done and you never have
to think about `[mm:ss.xx]` again.

### 1 — A window that stays on top

Nothing in it but the word "FloatingLyric". Prove you can float above other
apps, drag it, and resize it, on the platform's own terms. On Android, this is
where you fight the overlay permission. Get the fight over with early.

### 2 — Lyrics from a file, on a fake clock

Hard-code an `.lrc` file and a slider standing in for playback position. Wire
`LRCParser` → `LyricsDocument` → the view. **You now have the whole product,
minus Spotify** — the current line highlights, lines wrap, romaji sits
underneath.

This is the milestone that tells you whether your UI framework choice was
right, and it is much cheaper to discover it here.

### 3 — Real lyrics from LRCLIB

No auth needed — LRCLIB takes no key. Feed it a hard-coded artist and title.
Implement the cache rules from `porting.md`, including the one that matters:
"no lyrics exist" caches for 24 hours, "the network failed" caches never.

### 4 — Log in to Spotify

PKCE, the platform's browser-tab API, secure storage for the refresh token.
Per-platform details below. Prove it end to end by printing the current track
title to the console.

### 5 — The two clocks

Poll every 3 s, anchor `PlayheadClock` on every poll, tick the UI at 10 Hz.
Section 4 of [`architecture.md`](architecture.md) explains the mechanism; you
already ported the clock in milestone 0.

**At this point the app works.** Everything after is polish, and can ship
incrementally.

### 6 — Playback controls, romaji, auto-hide

In that order — controls are the most asked-for, romaji is the most fiddly,
auto-hide is the most platform-specific.

### 7 — Package it

Per-platform below.

---

## Spotify setup for any port

All ports can share one Spotify app registration — including the one this repo
already ships (`AppCredentials.builtInClientID`). Two things to do:

1. **Add your platform's redirect URI** in the dashboard, alongside the
   existing ones. `floatinglyric://callback` works for Android and iOS as-is.
   Desktop platforms without a browser-tab API need a loopback URI.
2. **Remember the 25-user cap is shared.** Development Mode allows 25 users
   *per registration*, not per platform. A user added for the Mac app can log
   in to the Android one; a user not added can log in to neither.

Never ship a client secret. There isn't one — that's the point of PKCE.

---

## Android

The closest thing to the real product, and the one you can start today.

### Stack

Kotlin + Jetpack Compose, in Android Studio. Choose Compose Multiplatform
instead only if you want Windows to share this codebase — it costs some
Android-specific convenience.

### Setup

```bash
# You already have the SDK; check the tools answer:
~/Library/Android/sdk/platform-tools/adb devices
```

New project in Android Studio: **Empty Activity**, Kotlin, minimum SDK **26**
(Android 8) — that gets you `android.icu.text.Transliterator` for romaji and
modern foreground-service behaviour.

### The overlay

This is the part with no macOS equivalent, so it's worth spelling out.

`AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.INTERNET" />

<service
    android:name=".LyricOverlayService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="false" />
```

Three rules, each of which will otherwise cost you an afternoon:

- **The permission cannot be granted in-app.** Send the user out with
  `Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)`, and explain *before* you
  do — an app that silently opens a system settings screen reads as malware.
  Check with `Settings.canDrawOverlays(context)` on the way back.
- **The overlay must be owned by a foreground service** with a visible
  notification, or Android kills it. That notification is not optional; design
  it rather than apologising for it.
- **Add the view with `WindowManager`**, type
  `TYPE_APPLICATION_OVERLAY`, flags `FLAG_NOT_FOCUSABLE` (plus
  `FLAG_NOT_TOUCHABLE` for the click-through mode). `LayoutParams.x/y` is your
  drag; there is no "remember the frame" for free.

### Two things Android gives you free

- **Romaji:** `android.icu.text.Transliterator.getInstance("Any-Latin; Latin-ASCII")`
  is the same ICU engine macOS uses, so readings match. Japanese still wants
  the tokenizer path — see the romanization section of `porting.md`.
- **Playback state:** Spotify's `SpotifyAppRemote` SDK reports the local player
  with no polling and no rate limit. Prefer it to the 3-second Web API loop,
  and keep the Web API for *control* and for when Spotify isn't installed.

### Auth

Chrome Custom Tabs, not a WebView — Spotify's login refuses embedded WebViews,
and Custom Tabs share the browser's cookies the way the macOS sheet does.
Redirect to `floatinglyric://callback` via an `<intent-filter>`. Store the
refresh token in `EncryptedSharedPreferences`, never plain prefs.

### There is no hover

The 3-second auto-hide needs a different trigger: tap to reveal, hide again
after the timeout. Everything else in `ChromeVisibility` still applies —
including that a 0 % overlay must stay recoverable.

### Build and ship

```bash
./gradlew assembleDebug          # APK for testing
./gradlew bundleRelease          # AAB for Play

adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Google Play registration is **$25, once**. Sideloading an APK is free. Expect
Play review to ask why you need `SYSTEM_ALERT_WINDOW`; "a lyrics overlay the
user explicitly enables" is an answer they accept.

---

## Windows

### Pick a route first

| Route | Build on a Mac? | Good when |
|---|---|---|
| **Compose Desktop** (Kotlin) | develop yes, installer no | you're also doing Android |
| **Flutter** | develop no | you want one codebase and don't mind Dart |
| **WinUI 3 / .NET** | no | you want the most native result |
| **Tauri** (Rust + web UI) | develop no | you're comfortable in web tech |

Compose Desktop is the pragmatic pick given the Android tooling you already
have.

### The window

| macOS | Windows |
|---|---|
| `level = .floating` | `WS_EX_TOPMOST` |
| `alphaValue` | `SetLayeredWindowAttributes` |
| click-through | `WS_EX_TRANSPARENT` |
| `LSUIElement` (no Dock icon) | `WS_EX_TOOLWINDOW` + tray icon |
| menu bar item | tray icon with context menu |

Handle **per-monitor DPI v2** from the start, or the overlay blurs the moment
it's dragged to a second monitor. And accept that a full-screen exclusive game
will cover a topmost window; there is no reliable fix.

### Romanization is the real gap

Windows ships no ICU transliterator. Bundle ICU4C, find a per-language library,
or ship without the feature and say so in the README. Decide before you start —
it's the feature Japanese and Korean listeners will miss.

### Secure storage

Windows Credential Manager (`PasswordVault` / `CredentialProtect`) for the
refresh token. Not the registry, not a file.

### Building without a Windows PC

Add `.github/workflows/windows.yml`:

```yaml
name: Windows build
on:
  push:
    branches: [main]
    paths: ["windows/**", ".github/workflows/windows.yml"]
  workflow_dispatch:

jobs:
  build:
    runs-on: windows-latest
    defaults:
      run:
        working-directory: windows
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"
      - run: ./gradlew packageReleaseMsi   # Compose Desktop
      - uses: actions/upload-artifact@v4
        with:
          name: FloatingLyric-windows
          path: windows/build/compose/binaries/**/*.msi
```

Push, then download the `.msi` from the run's artifacts. Free on public repos,
and it means you never need to own a Windows machine to ship one.

### Distribution

Free — ship the `.exe` or `.msi`. SmartScreen warns on unsigned binaries much
as Gatekeeper does; an Authenticode certificate (~$100–400/year, unrelated to
Apple's program) removes it. The Microsoft Store is $19 once, and optional.

---

## iOS

**Read [`../ios/README.md`](../ios/README.md) before writing any code.** The
floating overlay is impossible on iOS — no API draws over other apps, by
design. What you build instead is a different product: a full-screen lyrics
app, or a Live Activity on the Lock Screen and Dynamic Island.

### Setup

You have Xcode 26.2. New project → **App** → SwiftUI. Then:

- **Reuse the Swift, genuinely.** This is the one port where the existing code
  moves nearly as-is: `LRCParser`, `PlayheadClock`, `LyricsDocument`,
  `LyricsProvider`, `SpotifyAuth`, `PKCE`, `KeychainStore` and `Transliteration`
  all compile on iOS unchanged. Only AppKit has to go.
- Auth: `ASWebAuthenticationSession` works identically, with
  `floatinglyric://callback` registered as a URL type.
- Prefer Spotify's `SPTAppRemote` over Web API polling — iOS background limits
  make a 3-second loop a losing game.

### Running it

On the simulator: free, immediately. On your own iPhone: free with a personal
Apple ID, but the build **expires after 7 days** and must be reinstalled from
Xcode. On anyone else's device, or the App Store: the same **$99/year** account
as [`../macos/docs/apple-developer-id.md`](../macos/docs/apple-developer-id.md).
Unlike macOS, there is no distribution outside the App Store, so on iOS that
fee isn't optional.

---

## Definition of done

A port is finished when all of these are true — not when it displays lyrics.

- [ ] The pure types and their translated tests pass.
- [ ] A song with `[offset:]` and repeated timestamps parses correctly.
- [ ] Lyrics stay in sync across a pause, a seek, and a track change.
- [ ] A song with no lyrics doesn't re-fetch on every play; a network failure
      does retry.
- [ ] Login survives a restart (refresh token in the secure store) and a
      1-hour-expired access token.
- [ ] Playback control reports Premium, no-device and rate-limit distinctly.
- [ ] A Japanese song shows readings; an English one looks untouched.
- [ ] The chrome hides and returns, and a fully transparent window is still
      recoverable.
- [ ] It builds from a clean checkout with documented commands.
- [ ] Its README says what it does *differently* from this spec, and why.

Add a row to the [root README](../README.md) table when it ships.

---

*Commands here are written from the platforms' documented behaviour, not run on
this machine — only the Xcode and Android SDK checks at the top were verified.
Expect to adjust versions.*
