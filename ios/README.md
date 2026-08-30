# FloatingLyric for iOS

**Status: not started — and it would not be the same app.**

Read this before starting. The core idea of FloatingLyric does not survive the
trip to iOS, and it is better to know that now than after a weekend.

## The overlay is impossible

iOS has **no API for drawing over other apps.** An app's UI is confined to its
own window, and the moment it goes to the background it stops drawing. This is
a deliberate sandbox rule, not a missing feature, not a toolchain limitation,
and not something a future SDK will relax. There is no iOS equivalent of
Android's `SYSTEM_ALERT_WINDOW`.

Corollaries worth stating plainly, because each one gets suggested eventually:

- **Picture-in-Picture** can technically keep a video layer on screen, and
  people have abused it for overlays. It is fragile, it fights the system, and
  it is a reliable way to fail App Store review.
- **Background polling** is heavily restricted. A 3-second poll loop will not
  run in the background, whatever you promise `BGTaskScheduler`.

## What is actually worth building

Pick one — they're different products:

1. **A full-screen lyrics app.** Opens, shows synced lyrics with romaji,
   controls playback. Everything in
   [`../docs/porting.md`](../docs/porting.md) applies except the window
   behaviour section. The most straightforward option.
2. **A Live Activity** on the Lock Screen and in the Dynamic Island. The closest
   thing iOS has to "lyrics while you do something else", and genuinely nice for
   this use. Limited space: the current line, maybe one more.
3. **A widget.** Cheap, but updates are rate-limited to minutes — far too coarse
   for line-by-line sync. Fine for "what's playing", useless for lyrics.

## If you build it

- **Use Spotify's iOS SDK** (`SPTAppRemote`) rather than Web API polling. It
  reports the local player instantly, and iOS background limits make polling a
  losing game anyway.
- The **redirect URI** must be a registered custom scheme
  (`floatinglyric://callback`), not the loopback listener the macOS app uses.
- **Keychain** works exactly as it does on macOS — that file ports nearly
  as-is, unlike almost everything else.

## Cost

The same **$99/year** Apple Developer Program as macOS notarization; see
[`../macos/docs/apple-developer-id.md`](../macos/docs/apple-developer-id.md).
Unlike macOS, there is no way to distribute outside the App Store, so on iOS
that fee is not optional — it is the price of running the app on anyone's
device but your own.
