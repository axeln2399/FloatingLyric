# FloatingLyric for macOS

> This is the macOS app, one platform of the [FloatingLyric monorepo](../README.md).
> Every command below is run from this `macos/` directory.

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

## Logging in

Open FloatingLyric and click **Log In with Spotify**. Spotify's own login page
appears over the app — sign in with your Spotify username and password (or the
Google / Apple / Facebook buttons), click **Agree**, and the window closes
itself.

That's the whole setup. **No developer dashboard, no Client ID to paste** —
FloatingLyric ships with its own Spotify app registration.

> Your password goes to Spotify's page, never through FloatingLyric. The app
> only ever receives an access token. That's what OAuth is for, and it's why
> Spotify offers no way for an app to take your password directly.

The login window shares Safari's cookies, so if you're already signed in to
Spotify there, it's usually one **Agree** click with no password at all.

A **free Spotify account is enough to see lyrics.** The ⏮ ⏯ ⏭ buttons need
Premium — Spotify's rule for every app that controls playback, not this one's.

### Sending it to a friend

Here's the catch, and it's Spotify's, not the app's.

A Spotify app registration starts in **Development Mode**, which admits **at
most 25 users, each added by hand**. Anyone not on that list is turned away at
Spotify's login page with *"app not registered"* — no matter that the app works
perfectly for you.

So before your friend can log in, add them:

1. <https://developer.spotify.com/dashboard> → your app → **Settings** →
   **User Management**.
2. Add their **full name** and the **email address on their Spotify account**.
   It must be the Spotify one, not whichever email they usually give you.
3. Save. They can log in from that moment.

Removing the 25-user cap means applying to Spotify for **Extended Quota Mode**,
which they review by hand and rarely grant to personal projects. Assume the cap
is permanent and you'll be planning honestly.

If you'd rather not manage a list, tell your friend to use their own Client ID
instead — the next section.

### Using your own Client ID

Optional. You'd want this if you'd rather not appear on someone else's app
registration, or you've run out of the 25 slots above.

Menu bar **♪ → Use My Own Client ID…** opens the walkthrough. In short:

#### 1. Log in to the Spotify dashboard

Go to **<https://developer.spotify.com/dashboard>** and log in with the same
Spotify account you actually listen on.

#### 2. Create an app

Click **Create app**. Fill in:

| Field | What to put |
|---|---|
| **App name** | Anything, e.g. `FloatingLyric` |
| **App description** | Anything, e.g. `Personal lyrics overlay` |
| **Redirect URI** | Add **both** of the two below |
| **Which API/SDKs** | Tick **Web API** |

Add these two, clicking **Add** after each so both appear in the list:

```
floatinglyric://callback
http://127.0.0.1:8888/callback
```

> ⚠️ **Both must match exactly.** The first is the one normally used — it's
> what lets Spotify's login appear inside the app. The second is a fallback for
> the rare case the in-app window can't open, and costs one extra click to add
> now instead of a puzzling failure later. Type them literally: `http` not
> `https`, `127.0.0.1` **not** `localhost` (Spotify rejects it), no trailing
> slash. A single character off and login fails with `INVALID_CLIENT: Invalid
> redirect URI`.

Accept the terms and click **Save**.

#### 3. Copy your Client ID

On the app's page, open **Settings**. You'll see **Client ID** — a long string
of letters and numbers. Copy it.

You do **not** need the Client Secret. FloatingLyric uses OAuth PKCE, which is
designed for apps that can't keep a secret safe. Leave the secret hidden.

#### 4. Paste it into FloatingLyric

Paste it into the field and click **Save and Log In**. Clear the field to go
back to the built-in registration.

### Logging in and out

The login window opens by itself whenever there is no session to work with —
the first time you run the app, and again after **Log Out**. It has two faces:

- **First run:** a welcome and a single **Log In with Spotify** button.
- **Logged out:** the same button, worded for someone coming back.
- **No Client ID at all** (only if the built-in one is ever removed): the full
  developer walkthrough.

**Use a different Client ID…** on either of the first two reveals the field, if
you want to point the app at your own Spotify app registration.

Menu bar **♪ → Use My Own Client ID…** opens the walkthrough at any time.

### What the app can and cannot do with your account

It requests exactly two permissions:

| Scope | What it allows |
|---|---|
| `user-read-playback-state` | See the title, artist, album and playback position of the current track |
| `user-modify-playback-state` | Play, pause and skip — only when you press one of the buttons |

It **cannot** read your playlists, see your library, or change anything about
your account.

> Connected before playback control existed? Your saved login only carries the
> first scope. **♪ → Log Out**, then log in again to pick up the second one.

Your refresh token is stored in the **macOS Keychain**. The Client ID sits in
`UserDefaults`. Nothing is ever sent anywhere except Spotify's API and LRCLIB.

---

## Using it

- The floating window shows the current line bright and its neighbours dimmed.
- Drag it anywhere. It stays above other apps and follows you across Spaces.
- Resize it by dragging any edge or corner. Its size is remembered, like its
  position.

### Window controls

The window has the standard macOS **traffic lights** in its top-left corner —
the same red and yellow buttons as any Mac window. There is no title bar; the
buttons sit directly over the blurred background.

| Button | What it does |
|---|---|
| 🔴 **Red — close** | Closes the window. **The app keeps running** in the menu bar — it does not quit. Reopen with ♪ → Show / Hide Lyrics (⌘L). |
| 🟡 **Yellow — minimize** | Sends the window to the Dock. Click its Dock thumbnail, or ♪ → Show / Hide Lyrics, to bring it back. |
| ⚪ **Zoom** | Hidden on purpose. Zoom and full screen make no sense for a window that floats over your work — resize it by dragging an edge instead. |

The same actions are in the menu bar as **Minimize Window** (⌘M) and
**Close Window** (⌘W), so you can reach them even when the window is
click-through or off-screen.

To actually quit the app, use ♪ → **Quit FloatingLyric** (⌘Q).

### Resizing, and long lines

Drag any edge or corner. The window will not go below **280 × 150** — small
enough to be a thin strip of one line — and has no upper limit.

Lyric lines are never cut off: a line longer than the window **wraps onto as
many lines as it needs**, and its romaji wraps with it. Two ways to deal with a
song full of long lines:

- **Make the window wider** — the usual fix, and now the whole point of being
  able to resize it.
- **Make it taller** — if four wrapped lines don't fit, the lyric area scrolls,
  and the current line is scrolled back into view every time it changes. You can
  also scroll it by hand to read ahead.

A smaller **Font Size** (♪ → Font Size → Small) fits more per line too.

> With **Click Through** on, the traffic lights are hidden rather than left as
> dead buttons you can't click. Use the menu bar items instead, or turn Click
> Through off to get them back.

Menu bar icon (**♪**):

| Item | What it does |
|---|---|
| **Show / Hide Lyrics** (⌘L) | Toggle the floating window |
| **Minimize Window** (⌘M) | Send it to the Dock |
| **Close Window** (⌘W) | Close it — the app keeps running |
| **Lock Position** | Stop accidental dragging |
| **Click Through** | Window becomes purely visual; clicks pass through to whatever is behind it |
| **Play / Pause** (⌘P) | Play or pause Spotify |
| **Next Track** (⌘]) | Skip forward |
| **Previous Track** (⌘[) | Skip back |
| **Font Size** | Small (14) / Medium (18) / Large (24) |
| **Opacity** | A 0–100% slider — see below |
| **More Opaque** (⌘=) / **More Transparent** (⌘-) | Nudge the opacity 5% at a time |
| **Sync offset** | Nudge ±2000 ms if the highlight runs early or late |
| **Romaji Under Lyrics** | Print a Latin reading under non-Latin lines |
| **Auto-Hide Controls** | Fade everything but the lyrics after 3 idle seconds |
| **Use My Own Client ID…** | Point the app at your own Spotify app registration |
| **Log Out** | Disconnect the Spotify account |
| **Quit** (⌘Q) | Exit |

### Opacity

**♪ → Opacity** is a slider running the whole range from **0%** (completely
invisible) to **100%** (solid). The default is 60%. ⌘= and ⌘- nudge it 5% at a
time without opening the menu, and the setting is remembered across restarts.

| Setting | Feel |
|---|---|
| **0–15%** | A ghost you glance at — won't distract while working |
| **45%** | Half-there: readable, but the window behind still shows through |
| **60%** | Most readable — the default |
| **100%** | Solid |

> **A 0% window is not lost.** Move the pointer over where it sits and it fades
> back up to 35% so you can find it, grab it, and raise the slider again. Let
> go and it disappears once more.

Pair a low opacity with **Click Through** and the lyrics become a pure heads-up
display — visible, but completely non-interactive. (Click Through also switches
off the hover rescue above, since the window no longer sees the pointer at all;
raise the opacity from the menu bar instead.)

### Playback controls

The panel carries **⏮ ⏯ ⏭** under the progress bar, and the same three commands
are in the menu bar. They drive Spotify itself, so they work on whichever device
is playing — your Mac, your phone, a speaker.

Two things Spotify requires for these:

- **Spotify Premium.** The Web API refuses playback commands from free
  accounts; the panel says *"Spotify Premium required to control playback"*.
- **An active device.** If nothing has played recently there is nothing to
  command, and you'll see *"No active Spotify device"* — start a track in
  Spotify first.

If you connected your account before playback control existed, your saved login
predates the permission it needs. The panel says *"Log out and back in to enable
playback controls"* — do exactly that (♪ → Log Out, then log back in).

### Romaji under non-Latin lyrics

For a song written in Japanese, Korean, Chinese, Cyrillic, Greek, Thai and the
like, FloatingLyric prints a Latin reading under each line, so you can sing
along without reading the script:

```
君の名は
kimi no na ha
```

Lines already in Latin script are left exactly as they are, so an English song
looks no different. Turn it off with **♪ → Romaji Under Lyrics**.

The readings come from macOS's own text engine, which picks a kanji reading
from the surrounding words. It is a good guess, not a lyricist's transcription —
names and unusual readings will sometimes come out wrong.

### Auto-hiding controls

After **3 seconds** with no pointer over the window, everything but the lyrics
fades out: the track header, the progress bar, the transport buttons, the
traffic lights **and the blurred panel itself**. No frame, no shadow, no
background — what is left is bare words floating over whatever you're working
on. They carry a soft shadow so they stay readable over a light wallpaper.

Move the pointer onto the window and it all comes back, staying up for as long
as you hover. Nothing moves as it fades — the layout holds its place, so the
lyrics never jump.

Turn it off with **♪ → Auto-Hide Controls** to keep the window furniture on
screen permanently.

---

## Stopping the Keychain prompt (free)

Sooner or later you'll see:

> **"FloatingLyric wants to use your confidential information stored in
> com.floatinglyric.tokens in your keychain."**

That is macOS asking whether this program may read **its own** Spotify refresh
token. Nothing is wrong — but it comes back every time you rebuild after
changing code, and here is why.

The Keychain identifies a program by its code signature. An ad-hoc signed build
has no certificate behind it, so there is no stable identity to record, and
macOS falls back to the exact hash of the code. Rebuilding unchanged source
gives the same hash and stays quiet; change one line and the hash changes, at
which point macOS sees a program it has never met asking for your token.

**"Always Allow" is safe** — it adds that build to the item's list. It just
doesn't survive your next code change.

The permanent, free fix is to give every build the same identity with a
self-signed certificate:

```
./make-signing-cert.sh    # once — asks for your login password
./build.sh                # picks the certificate up automatically
```

Approve the Keychain prompt one last time (and "Always Allow" the signing key
if the build asks), and neither prompt returns, however much the code changes.

This is **not** an Apple Developer ID. It stops the Keychain asking on *this*
Mac. It does nothing for Gatekeeper on anyone else's — for that, read on.

To go back to ad-hoc builds, delete "FloatingLyric Local Signing" in Keychain
Access; `build.sh` stops finding it and falls back on its own.

---

## Signing with an Apple Developer account

Everything above works without paying Apple a cent. The only cost is that an
unsigned app trips Gatekeeper on first launch, and anyone you share the `.dmg`
with has to right-click → Open.

If you have (or get) a **paid Apple Developer account — $99/year** — you can
sign and notarize the build so it opens cleanly on any Mac, with no warning at
all. `build.sh` already supports this; it just needs two environment variables.

> The step-by-step runbook, with verification and what to do when a step fails,
> is in **[`docs/apple-developer-id.md`](docs/apple-developer-id.md)**. What
> follows is the summary.

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
swift test     # 94 tests, all offline
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
| `INVALID_CLIENT: Invalid redirect URI` | The dashboard needs **both** `floatinglyric://callback` and `http://127.0.0.1:8888/callback`, each exact — `http` not `https`, `127.0.0.1` not `localhost`, no trailing slash |
| "Could not open the Spotify login window" | The in-app window failed; the app falls back to your browser, which needs the loopback URI above registered |
| Login page never returns | Redirect URI mismatch, as above; if it fell back to the browser, also check nothing else holds port 8888 |
| "Port 8888–8890 in use" | Only reachable via the browser fallback — quit whatever holds those ports, then log in again |
| Nothing appears on screen | The window may be near 0% opacity — hover where it sits, or drag ♪ → Opacity back up |
| Can't find the window at all | ♪ → Show / Hide Lyrics twice; it re-centres if its saved position is off-screen |
| Closed the window by accident | ♪ → Show / Hide Lyrics (⌘L). Closing never quits the app. |
| Minimized it and can't get it back | Click its thumbnail in the Dock, or ♪ → Show / Hide Lyrics |
| No traffic light buttons visible | **Click Through** is on — turn it off in the menu bar |
| Highlight runs early or late | Adjust **Sync offset** in the menu bar |
| "Session expired" | ♪ → **Log Out**, then log in again |
| Keychain asks about `com.floatinglyric.tokens` after every rebuild | Ad-hoc builds have no stable identity — run `./make-signing-cert.sh` once (see above) |
| `no such module 'XCTest'` when building | `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or permanently: `sudo xcode-select -s /Applications/Xcode.app` |

## Docs

- **Getting an Apple Developer account: [`docs/apple-developer-id.md`](docs/apple-developer-id.md)** — the full runbook for signing and notarizing, for the day you have one
- How the code works, with diagrams: [`../docs/architecture.md`](../docs/architecture.md)
- Porting to other platforms: [`../docs/porting.md`](../docs/porting.md)
- Design: `../docs/superpowers/specs/2026-08-30-floatinglyric-design.md`
- Implementation plan: `../docs/superpowers/plans/2026-08-30-floatinglyric.md`
