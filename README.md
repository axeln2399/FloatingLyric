# FloatingLyric

Time-synced lyrics for whatever you're playing on Spotify, in a translucent
always-on-top window on macOS. Lyrics follow your Spotify *account*, so they
work whether you're playing on this Mac, your phone, or a speaker.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)

---

## How to run

You do **not** need to install anything into `/Applications`. Pick whichever
suits you.

### Option A — run the built app straight from `dist/` (recommended)

```bash
./build.sh                    # produces dist/FloatingLyric.app + dist/FloatingLyric.dmg
open dist/FloatingLyric.app
```

The app is unsigned, so on the very first launch macOS may refuse to open it.
Clear the quarantine flag once and it will launch every time after that:

```bash
xattr -cr dist/FloatingLyric.app
open dist/FloatingLyric.app
```

### Option B — run from source, no bundle at all

```bash
swift run FloatingLyric
```

Fastest loop while changing code. One caveat: run this way there is no
`Info.plist`, so macOS gives it a Dock icon (the bundled app is menu-bar-only).
Everything else behaves identically.

### Option C — install it properly

Only if you want it permanently. Open `dist/FloatingLyric.dmg` and drag the app
to Applications, then `xattr -cr /Applications/FloatingLyric.app`.

### Stopping it

It has no Dock icon, so: menu bar **♪ → Quit FloatingLyric** (⌘Q), or

```bash
pkill -x FloatingLyric
```

### First launch

There is no Spotify account connected yet, so a setup window opens
automatically. Follow the next section.

---

## How to connect your Spotify account

FloatingLyric talks to Spotify through **your own** Spotify developer app, so no
credentials are shared with anyone — not with me, not with a server. Everything
stays on your Mac.

You need this once. It takes about two minutes.

### 1. Log in to the Spotify dashboard

Go to **<https://developer.spotify.com/dashboard>** and log in with the same
Spotify account you actually listen on. Any account works — **free accounts are
fine, Premium is not required**, because the app only *reads* what's playing.

### 2. Create an app

Click **Create app**. Fill in:

| Field | What to put |
|---|---|
| **App name** | Anything, e.g. `FloatingLyric` |
| **App description** | Anything, e.g. `Personal lyrics overlay` |
| **Redirect URI** | `http://127.0.0.1:8888/callback` — see the warning below |
| **Which API/SDKs** | Tick **Web API** |

> ⚠️ **The Redirect URI must match exactly.** Type
> `http://127.0.0.1:8888/callback` — with `http` (not `https`), with
> `127.0.0.1` (**not** `localhost`, Spotify rejects it), and with no trailing
> slash. Click **Add** so it appears in the list, then save. A single character
> off and login will fail with `INVALID_CLIENT: Invalid redirect URI`.

Accept the terms and click **Save**.

### 3. Copy your Client ID

On the app's page, open **Settings**. You'll see **Client ID** — a long string
of letters and numbers. Copy it.

You do **not** need the Client Secret. FloatingLyric uses OAuth PKCE, which is
designed for apps that can't keep a secret safe. Leave the secret hidden.

### 4. Paste it into FloatingLyric

In FloatingLyric's setup window, paste the Client ID and click
**Save and Log In**. Your browser opens Spotify's authorization page once —
click **Agree**. The browser shows "FloatingLyric is connected", and you can
close that tab.

That's it. Play something on Spotify — on any device — and lyrics appear.

### Re-running setup later

Menu bar **♪ → Spotify Setup…** to change the Client ID, or **Log Out** to
disconnect the account.

### What the app can and cannot do with your account

It requests exactly one permission, `user-read-playback-state`. That means it
can see the title, artist, album and playback position of the current track.
It **cannot** control playback, read your playlists, see your library, or change
anything about your account.

Your refresh token is stored in the **macOS Keychain**. The Client ID sits in
`UserDefaults`. Nothing is ever sent anywhere except Spotify's API and LRCLIB.

---

## Using it

- The floating window shows the current line bright and its neighbours dimmed.
- Drag it anywhere. It stays above other apps and follows you across Spaces.

Menu bar icon (**♪**):

| Item | What it does |
|---|---|
| **Show / Hide Lyrics** (⌘L) | Toggle the floating window |
| **Lock Position** | Stop accidental dragging |
| **Click Through** | Window becomes purely visual; clicks pass through to whatever is behind it |
| **Font Size** | Small (14) / Medium (18) / Large (24) |
| **Opacity** | **15% / 45% / 60%** — see below |
| **Sync offset** | Nudge ±2000 ms if the highlight runs early or late |
| **Spotify Setup…** | Re-enter the Client ID |
| **Log Out** | Disconnect the Spotify account |
| **Quit** (⌘Q) | Exit |

### Opacity

Three transparency steps, under **♪ → Opacity**:

| Step | Feel |
|---|---|
| **15%** | Nearly invisible — a ghost you glance at, won't distract while working |
| **45%** | Half-there — readable but the window behind still shows through |
| **60%** | Most readable — the default |

**♪ → Opacity → Cycle** (⌘T) steps 15% → 45% → 60% → 15%, so you can flick
between them without opening the submenu. The choice is remembered across
restarts.

Pair **15%** with **Click Through** and the lyrics become a pure heads-up
display — visible, but completely non-interactive.

---

## Signing with an Apple Developer account

Everything above works without paying Apple a cent. The only cost is that an
unsigned app trips Gatekeeper on first launch, and anyone you share the `.dmg`
with has to right-click → Open.

If you have (or get) a **paid Apple Developer account — $99/year** — you can
sign and notarize the build so it opens cleanly on any Mac, with no warning at
all. `build.sh` already supports this; it just needs two environment variables.

### 1. Get a Developer ID Application certificate

1. Join the [Apple Developer Program](https://developer.apple.com/programs/)
   ($99/year).
2. In **Xcode → Settings → Accounts**, add your Apple ID.
3. Select your team → **Manage Certificates…** → **+** →
   **Developer ID Application**.

Confirm it landed:

```bash
security find-identity -v -p codesigning
```

You want the line reading `Developer ID Application: Your Name (TEAM123456)`.
That whole string is your `SIGN_IDENTITY`.

### 2. Create an app-specific password for notarization

Notarization uploads the app to Apple for an automated malware scan.

1. Go to <https://appleid.apple.com> → **Sign-In and Security** →
   **App-Specific Passwords** → generate one, name it `notarytool`.
2. Store it as a keychain profile so it isn't sitting in your shell history:

```bash
xcrun notarytool store-credentials "floatinglyric" \
  --apple-id "you@example.com" \
  --team-id "TEAM123456" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

`floatinglyric` is the profile name — that's your `NOTARY_PROFILE`. Your Team ID
is the code in parentheses in the certificate name, also shown at
<https://developer.apple.com/account> under Membership.

### 3. Build signed and notarized

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAM123456)" \
NOTARY_PROFILE="floatinglyric" \
./build.sh
```

`build.sh` then signs the app with the hardened runtime and a secure timestamp,
signs the DMG, submits it to Apple, waits for the result, and staples the
ticket to the DMG. Expect 1–5 minutes for the notarization step.

Verify the result:

```bash
xcrun stapler validate dist/FloatingLyric.dmg
spctl -a -t open --context context:primary-signature -v dist/FloatingLyric.dmg
```

`source=Notarized Developer ID` means it will open silently on any Mac.

### What the variables do

| Variables set | Result |
|---|---|
| Neither | Ad-hoc signed. Works for you; Gatekeeper warns on first launch. |
| `SIGN_IDENTITY` only | Properly signed, not notarized. Gatekeeper still warns on *other* Macs. |
| Both | Signed **and** notarized. No warnings anywhere. |

Notarization is only worth it if you're sharing the app. For your own Mac, the
one-time `xattr -cr` is entirely sufficient.

---

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
swift test     # 82 tests, all offline
./build.sh     # → dist/FloatingLyric.app and dist/FloatingLyric.dmg
```

Requires macOS 14+ and **Xcode** — not just the Command Line Tools, because
`swift test` needs XCTest, which only ships with Xcode. `build.sh` points at
`/Applications/Xcode.app` automatically if `xcode-select` isn't set to it.

No third-party dependencies — Apple frameworks only.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "App is damaged and can't be opened" | `xattr -cr dist/FloatingLyric.app` |
| `INVALID_CLIENT: Invalid redirect URI` | The Redirect URI in the Spotify dashboard must be `http://127.0.0.1:8888/callback` exactly — `http` not `https`, `127.0.0.1` not `localhost`, no trailing slash |
| Login browser page never returns | Same as above; also check nothing else is on port 8888 |
| "Port 8888–8890 in use" | Quit whatever holds those ports, then log in again |
| Nothing appears on screen | The window may be at 15% opacity — ♪ → Opacity → 60% |
| Can't find the window at all | ♪ → Show / Hide Lyrics twice; it re-centres if its saved position is off-screen |
| Highlight runs early or late | Adjust **Sync offset** in the menu bar |
| "Session expired" | ♪ → **Log Out**, then log in again |
| `no such module 'XCTest'` when building | `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or permanently: `sudo xcode-select -s /Applications/Xcode.app` |

## Docs

- Design: `docs/superpowers/specs/2026-08-30-floatinglyric-design.md`
- Implementation plan: `docs/superpowers/plans/2026-08-30-floatinglyric.md`
