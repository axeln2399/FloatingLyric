# REQ-001 — Dynamic lyric line count

Status: APPROVED (Team Lead)
Raised by: Axel (product owner)
Date: 2026-10-04
Platform: macOS (reference port)

## Problem

The floating overlay renders only four lyric lines regardless of window
height. When the window is tall, the lyrics occupy the top portion and the
remainder of the panel is empty. Evidence: user screenshot 2026-10-04
showing a tall panel with four rendered lines ("Oh, angel sent from up
above" … "You came to lift me up") and roughly half the panel blank below.

Cause: `LyricView.syncedLines` rendered a fixed slice
`Array((center - 1)...(center + 2))` — four lines, independent of the
available height.

## Business Value

The overlay's purpose is to show lyrics in sync with playback. A fixed
four-line window wastes the space the user deliberately allocated by
resizing, and gives less context than the panel can display. Honouring the
window size makes the product behave the way users expect a lyrics panel
to behave.

## Scope

- The number of visible lyric lines adapts to the height of the overlay
  window.
- A taller window shows more lines; a shorter window shows fewer.
- The current line stays visually centred as playback advances.
- Behaviour on a short window must remain equivalent to today's.
- Applies to synced (LRC) lyric rendering.
- macOS port only.

## Out of Scope

- Windows, Android, iOS ports.
- Changing fonts, colours, spacing, chrome or transport controls.
- Plain (unsynced) lyric rendering behaviour.
- Any change to lyrics fetching, caching, matching or playback logic.
- New user-facing settings or preferences.

## Assumptions (Constitution #11)

1. "Dynamic by the size of screen" is read as the size of the overlay
   WINDOW, not the physical display. The window is user-resizable and
   floats above other apps; sizing to the display would be meaningless.
2. The existing uncommitted `LyricView.swift` change is the intended
   direction of this work and is to be completed, not discarded.
3. Scroll remains available so off-screen lines stay reachable.

## Acceptance Criteria

AC1. Resizing the overlay taller increases the number of lyric lines shown;
     resizing shorter decreases it. No fixed cap of four.
AC2. The currently-sung line is centred in the visible area and stays
     centred as the song advances.
AC3. On launch mid-song the view opens centred on the current line, not
     scrolled to the top.
AC4. With no sync position yet (currentIndex nil) the view does not crash
     and displays sensibly from the first line.
AC5. A long song (50+ lines) renders without truncation and without
     perceptible scroll or layout jank.
AC6. A short window looks and behaves as it does today.
AC7. Long lines continue to wrap rather than truncate.
AC8. Both existing test suites still pass with no regressions.

## Definition of Done

- Architect has reviewed the design.
- Developer has implemented and the macOS build succeeds.
- QA has validated against AC1–AC8 and issued a release decision.
- Risks documented.
