# FloatingLyric

Time-synced lyrics for whatever you're playing on Spotify, in a window that
floats above everything else.

Lyrics follow your Spotify **account**, not a device — so they work whether
you're playing on this machine, your phone, or a speaker.

## Platforms

| Platform | Status | Where |
|---|---|---|
| **macOS 14+** | **Shipping** — the real app | [`macos/`](macos/) |
| Windows | Not started | [`windows/`](windows/) |
| Android | Not started | [`android/`](android/) |
| iOS | Not started, and not the same app — see below | [`ios/`](ios/) |

Only the macOS app exists today. The other three directories hold the plan for
that platform and nothing else; each README says what it would take and which
decisions are still open.

## Start here

- **Using or building the macOS app:** [`macos/README.md`](macos/README.md)
- **Writing one of the other platforms:** [`docs/porting.md`](docs/porting.md) —
  the behaviour every version has to match, written so it can be implemented in
  any language, plus what each platform can and can't do.
- **Signing and notarizing (macOS):**
  [`macos/docs/apple-developer-id.md`](macos/docs/apple-developer-id.md)

## How this repo is laid out

```
macos/      Swift package: the app, its tests, build.sh   ← run commands here
windows/    plan only
android/    plan only
ios/        plan only
docs/       cross-platform: the porting guide, design notes
```

Each platform directory is self-contained: its own project, build and tests,
with no build-time dependency on any other. **Nothing is shared but the
specification.** [`docs/porting.md`](docs/porting.md) explains why that's
deliberate rather than lazy — briefly, the genuinely shared logic is about a
thousand lines, and the part that makes this app worth using is the floating
overlay, which is different on every platform and impossible on one of them.

## One thing worth knowing before you start a port

**iOS cannot do the floating overlay at all.** There is no API for drawing over
other apps; that's a deliberate sandbox rule, not a gap someone will fill. An
iOS version is a different product — a full-screen lyrics view, or a Live
Activity. Read [`ios/README.md`](ios/README.md) before spending a weekend on it.
