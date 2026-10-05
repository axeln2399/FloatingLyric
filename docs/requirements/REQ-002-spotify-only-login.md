# REQ-002 — Spotify-only login window, native macOS polish

Status: APPROVED (Team Lead)
Raised by: Axel (product owner)
Date: 2026-10-04
Platform: macOS (reference port)

## Problem

The login window presents three competing actions with no visual
hierarchy — "Use a different Client ID…", "Open Spotify Dashboard", and
"Log In with Spotify" — so a developer escape hatch sits at the same
weight as the one action every user needs. Evidence: user screenshot
2026-10-04.

Two consequences:

1. The window does not read as a Spotify login. It reads as a
   configuration dialog that happens to mention Spotify.
2. The presentation is plain system text and default blue links with no
   branding, iconography or deliberate spacing — generic rather than
   hand-crafted.

## Business Value

Login is the first screen a new user meets and the only thing standing
between them and the product working. A single-purpose, visibly native
window raises confidence at exactly the moment the app asks for account
access. Developer affordances still exist for the rare user who needs
them, but they stop taxing everyone else.

## Scope

### A. Spotify-only login window

- The login window offers exactly one action: log in with Spotify.
- "Use a different Client ID…" is REMOVED from the login window and
  relocated to the menu bar menu.
- "Open Spotify Dashboard" is removed from the login window.
- The custom Client ID capability is retained and reachable, via the
  menu bar only.
- The `.setup` walkthrough face remains reachable for users with no
  built-in Client ID — it must not become orphaned.

### B. Native macOS visual polish

- The app icon is shown in the window.
- Clear visual hierarchy: icon, title, one line of supporting text,
  primary action.
- A Spotify-branded primary button (Spotify green, prominent).
- Deliberate spacing and alignment; no default-styled link row.
- Standard macOS idioms only — system materials, SF Symbols, dynamic
  type, light/dark appearance support.

## Out of Scope

- Windows, Android, iOS ports.
- Any change to the OAuth/PKCE flow, scopes, token storage or refresh.
- Any change to the floating lyric overlay itself.
- Shipping Spotify's own logo artwork (see Assumption 3).
- New user-facing settings beyond relocating the existing Client ID entry.
- Changing the built-in Client ID or Spotify app registration.

## Assumptions (Constitution #11)

1. "Make the UI not to AI" is read as: make it look deliberately designed
   and native to macOS, not generically generated. Confirmed with the
   product owner.
2. The Client ID escape hatch is retained behind a menu bar item, NOT
   deleted. Confirmed with the product owner. Rationale: the built-in
   Client ID runs in Spotify Development Mode, capped at 25 hand-added
   users; without any override the app would have no recovery path if
   that cap is reached or the ID revoked.
3. Spotify brand assets are NOT bundled. Use Spotify's brand colour
   (#1DB954) and a neutral glyph. Shipping Spotify's logo would require
   compliance with their brand guidelines and is deliberately avoided.
4. Existing authentication behaviour is unchanged; this is presentation
   and placement only.

## Acceptance Criteria

AC1. The login window presents exactly one primary action: log in with
     Spotify. No Client ID field and no dashboard link are visible on the
     `.welcome` or `.logIn` faces.
AC2. The custom Client ID entry is reachable from the menu bar and still
     persists a Client ID exactly as before.
AC3. The `.setup` face (no built-in Client ID) remains reachable and
     functional, with its walkthrough intact.
AC4. The window shows the app icon and a clear hierarchy of
     icon → title → supporting text → primary button.
AC5. The primary button is visually Spotify-branded (#1DB954) and is the
     clear focal point of the window.
AC6. The window renders correctly in both light and dark appearance.
AC7. Logging in still succeeds end to end; no change to OAuth behaviour.
AC8. Both existing test suites pass with no regressions, and
     LoginPrompt's existing tests continue to pass.

## Definition of Done

- Architect has reviewed the design.
- Developer has implemented and the macOS build succeeds.
- QA has validated against AC1–AC8 and issued a release decision.
- Risks documented.
