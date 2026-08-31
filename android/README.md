# FloatingLyric for Android

**Status: not started.** This directory holds the plan. There is no code yet.

The behaviour to implement is in [`../docs/porting.md`](../docs/porting.md).
This file only covers what is specific to Android.

> **How to actually build it:**
> [`../docs/building-a-port.md`](../docs/building-a-port.md) — toolchain setup,
> the milestone order, and packaging.

## Why this is the closest match to the macOS app

Android is the one other platform where the *actual product* — lyrics floating
over whatever else you're doing — is possible. `SYSTEM_ALERT_WINDOW`, shown to
users as **"Display over other apps"**, is exactly that permission.

Two things Android hands you for free that Windows does not:

- **Romanization**: `android.icu.text.Transliterator` is in the framework
  (API 24+), with `Any-Latin`, and a real tokenizer for Japanese. The same ICU
  engine macOS uses, so readings will match.
- **Playback state**: Spotify's Android SDK (`SpotifyAppRemote`) reports the
  local player with no polling and no rate limit. Prefer it over the Web API
  poll loop; keep the Web API for playback *control* and for when Spotify isn't
  installed.

## Decisions still open

**Stack.** Kotlin + Jetpack Compose is the default answer. Compose
Multiplatform or Flutter if you want Windows to share the codebase.

**Overlay vs. in-app.** The overlay needs a permission users must grant in
Settings, which is friction at first run. Consider shipping a normal in-app
lyrics screen first and adding the overlay behind a toggle.

## Things that will bite

- **The permission is a trip to Settings.** `ACTION_MANAGE_OVERLAY_PERMISSION`
  opens a system screen; you cannot grant it in-app. Explain why before sending
  the user there, or it looks like malware.
- **You need a foreground service** with a persistent notification, or Android
  will kill the overlay. That notification is not optional and users will see
  it.
- **Play Store review scrutinizes `SYSTEM_ALERT_WINDOW`.** A lyrics overlay is
  a legitimate use, but expect to justify it in the listing.
- **Battery optimization** will still throttle you on some OEM builds (Xiaomi,
  Samsung and Huawei are the usual suspects). The `SpotifyAppRemote` route
  suffers far less than a polling loop.
- **The loopback redirect does not work the same way.** Register a custom scheme
  (`floatinglyric://callback`) in the Spotify dashboard and use an
  Android App Link or `<intent-filter>` instead of a local HTTP listener.
  This is a real difference from the porting guide's redirect section.
- **Hover doesn't exist.** There is no pointer, so the 3-second auto-hide needs
  a different trigger: tap to reveal, and hide again after the timeout.

## Distribution

Google Play registration is **$25, once** — no annual fee. Sideloading an APK
is free and needs no account at all.
