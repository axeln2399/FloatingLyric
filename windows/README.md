# FloatingLyric for Windows

**Status: not started.** This directory holds the plan. There is no code yet.

The behaviour to implement is in [`../docs/porting.md`](../docs/porting.md) —
auth, polling, the playhead clock, LRCLIB, parsing, control, and the window
rules. This file only covers what is specific to Windows.

## Why this one is straightforward

An always-on-top overlay is a normal thing to build on Windows. Everything the
macOS app does to its window has a direct equivalent:

| macOS | Windows |
|---|---|
| `level = .floating` | `WS_EX_TOPMOST` |
| `alphaValue` | `SetLayeredWindowAttributes`, or the framework's own opacity |
| Click-through | `WS_EX_TRANSPARENT` |
| Hidden from the Dock (`LSUIElement`) | `WS_EX_TOOLWINDOW`, plus a tray icon |
| Menu bar item | System tray icon with a context menu |

## Decisions still open

**Stack.** WinUI 3, WPF, Compose Desktop, Flutter or Tauri all work. If Windows
is the only other platform you want, pick whatever you'll enjoy. If Android is
coming too, choose Compose Multiplatform or Flutter and share with it.

**Romanization.** This is the real gap: Windows ships no ICU transliterator, so
the romaji feature has no free ride. Options, in rough order of effort:

1. Bundle ICU4C and call `Transliterator` — the same engine macOS uses, so the
   output matches.
2. .NET has `System.Globalization` but no transliteration; you'd be reaching for
   a per-language NuGet package, and quality varies a lot by script.
3. Ship without it. Say so in this README if you do.

Kanji still need a **language-aware tokenizer** for correct readings — see the
romanization section of the porting guide for why a plain character map gets
名 wrong.

**Secure storage.** Windows Credential Manager (`CredentialProtect` /
`PasswordVault`) for the refresh token. Not a file, not the registry.

## Things that will bite

- **DPI.** Per-monitor DPI v2, or the overlay will blur the moment it's dragged
  to a second monitor.
- **Full-screen games and apps** will cover a topmost window. There is no
  reliable fix; a window with `WS_EX_TOPMOST` still loses to exclusive
  full screen.
- **The loopback redirect** (`http://127.0.0.1:8888/callback`) works fine, but
  Windows Firewall may prompt on the first listen. Expect it, and don't make it
  look like an error.
- **Hover detection**: poll the cursor position rather than relying on
  enter/leave messages, for the same reason macOS does — see the porting guide.

## Distribution

Free. Ship the `.exe`, or an MSIX for a tidier install. SmartScreen will warn on
an unsigned binary much as Gatekeeper does; an Authenticode certificate (~$100–
400/year from a CA, separate from Apple's program) removes it. The Microsoft
Store is $19 once, and optional.
