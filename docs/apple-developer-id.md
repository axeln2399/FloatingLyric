# The day you get an Apple Developer account

Everything you need to change to ship FloatingLyric signed and notarized, so it
opens silently on any Mac.

**Short version: no code changes.** `build.sh` has supported this since the
start. You set two environment variables and do some one-time setup on Apple's
side. Nothing in `Sources/` moves.

---

## The whole checklist

```bash
# ── one time, after joining the program ───────────────────────────────
# 1. Create the certificate (Xcode → Settings → Accounts → Manage
#    Certificates → + → Developer ID Application), then confirm:
security find-identity -v -p codesigning

# 2. Store notarization credentials (needs an app-specific password):
xcrun notarytool store-credentials "floatinglyric" \
  --apple-id "you@example.com" \
  --team-id "TEAM123456" \
  --password "xxxx-xxxx-xxxx-xxxx"

# ── every release build from then on ──────────────────────────────────
SIGN_IDENTITY="Developer ID Application: Your Name (TEAM123456)" \
NOTARY_PROFILE="floatinglyric" \
./build.sh
```

That's it. The rest of this file explains each step and how to check it worked.

---

## 1. Join and create the certificate

The [Apple Developer Program](https://developer.apple.com/programs/) is
**$99/year**. Membership is what gets you a Developer ID; there is no free tier
that Gatekeeper accepts.

Once you're in:

1. **Xcode → Settings → Accounts**, add your Apple ID.
2. Select your team → **Manage Certificates…** → **+** →
   **Developer ID Application**.

> Pick **Developer ID Application**, not "Apple Development" or "Mac App
> Distribution". Only Developer ID is for apps distributed outside the App
> Store, which is what a DMG is.

Confirm it installed:

```bash
security find-identity -v -p codesigning
```

You're looking for:

```
1) A1B2C3... "Developer ID Application: Your Name (TEAM123456)"
```

That entire quoted string — name, spaces, parentheses and all — is your
`SIGN_IDENTITY`. The code inside the parentheses is your **Team ID**.

## 2. Set up notarization

Notarization is Apple scanning your build for malware and issuing a ticket
saying it passed. It needs credentials that aren't your Apple ID password.

1. <https://appleid.apple.com> → **Sign-In and Security** → **App-Specific
   Passwords** → generate one. Name it `notarytool`. Copy it — it is shown
   once.
2. Save it into the keychain as a named profile, so it never touches your shell
   history or this repo:

```bash
xcrun notarytool store-credentials "floatinglyric" \
  --apple-id "you@example.com" \
  --team-id "TEAM123456" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

`floatinglyric` is the profile name, and it is your `NOTARY_PROFILE`.

## 3. Build

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAM123456)" \
NOTARY_PROFILE="floatinglyric" \
./build.sh
```

`build.sh` will now take the Developer ID path (`build.sh:53`): it signs the app
with the **hardened runtime** and a **secure timestamp** — both mandatory for
notarization — signs the DMG, uploads it, waits, and staples the ticket. Expect
**1–5 minutes** for the Apple round trip. `--wait` blocks until it's done, so
don't kill the build when it looks stalled.

If you'll build often, put the two variables in your shell profile rather than
retyping them:

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAM123456)"
export NOTARY_PROFILE="floatinglyric"
```

## 4. Verify it actually worked

Don't trust the absence of errors — check:

```bash
# The ticket is attached to the DMG
xcrun stapler validate dist/FloatingLyric.dmg

# Gatekeeper's own verdict
spctl -a -t open --context context:primary-signature -v dist/FloatingLyric.dmg

# What the app is signed with
codesign -dvvv dist/FloatingLyric.app 2>&1 | grep -E "Authority|TeamIdentifier|Signature"
```

You want `source=Notarized Developer ID` from `spctl`, a real `TeamIdentifier`,
and `Authority=Developer ID Application: ...` where it used to say
`Signature=adhoc`.

The honest test is still someone else's Mac: AirDrop the DMG and open it. No
warning, no right-click → Open, no `xattr`.

---

## What changes for you, in practice

| | Before | After |
|---|---|---|
| First launch elsewhere | Right-click → Open, or `xattr -cr` | Just opens |
| Keychain prompt | Returns after every code change | Approve once, ever |
| Build time | ~30s | ~30s + 1–5 min notarization |
| `dist/FloatingLyric.dmg` | Unsigned | Signed, notarized, stapled |

### The Keychain will ask one more time

Your Spotify token's access list is tied to a code identity, and switching from
ad-hoc (or from the local self-signed certificate) to a Developer ID **is** a
new identity. Expect the *"FloatingLyric wants to use your confidential
information"* prompt once more on the first Developer ID build. Click **Always
Allow**. It won't come back after that, because a certificate identity survives
rebuilds — that's the entire point of it.

### Retire the local certificate

If you ran `make-signing-cert.sh`, it's now redundant. `build.sh` prefers
`SIGN_IDENTITY` and only falls back to the local certificate when that variable
is empty (`build.sh:28`), so nothing breaks if you leave it. To clean up: open
**Keychain Access**, find **FloatingLyric Local Signing**, delete it.

### Bump the version before a release

`Resources/Info.plist` still says `1.0` / `1`. Not required by anything, but
once other people have copies, `CFBundleShortVersionString` (what users see) and
`CFBundleVersion` (which must increase) are how you tell builds apart.

### No entitlements needed

The hardened runtime blocks a specific list of things — JIT, loading unsigned
libraries, disabling library validation — and FloatingLyric does none of them.
Outgoing network connections and Keychain access are both fine without
entitlements, so there is no entitlements file to write. If you ever add one,
it gets passed via `codesign --entitlements`.

---

## If something fails

| Symptom | Cause |
|---|---|
| `errSecInternalComponent` from codesign | The private key isn't accessible. Open Keychain Access → your certificate → expand → private key → Get Info → Access Control → allow `codesign`. |
| `The specified item could not be found in the keychain` | `SIGN_IDENTITY` doesn't match a line from `security find-identity -v -p codesigning` character for character. |
| notarytool: `Invalid credentials` | The app-specific password is wrong, or `--team-id` doesn't match the certificate's Team ID. Re-run `store-credentials`. |
| notarytool: `Invalid` status | Fetch the reason: `xcrun notarytool log <submission-id> --keychain-profile "floatinglyric"`. Usually a missing hardened runtime or timestamp — both of which `build.sh` already passes, so this should not happen. |
| Gatekeeper still warns after notarizing | The ticket wasn't stapled, or you're testing the `.app` instead of the DMG you shipped. Re-check `stapler validate`. |

## If your membership lapses

Builds you already notarized and stapled **keep working forever** — the ticket
is attached to the DMG and doesn't phone home. You just can't sign or notarize
new ones. The certificate itself is valid 5 years, but it stops being trusted
for new notarization once membership ends.

---

## Is it worth $99?

Only if you're sharing the app.

- **Just your Macs?** No. `./make-signing-cert.sh` kills the Keychain prompt for
  free, and `xattr -cr` handles Gatekeeper once per machine.
- **Sending it to friends?** Probably — you're asking each of them to
  right-click → Open and trust you, which is precisely the friction Apple
  charges to remove.
- **Publishing it publicly?** Yes. Strangers will not run an app that macOS
  says is from an unidentified developer.
