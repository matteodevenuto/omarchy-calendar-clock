# Changelog

## 1.0.3 — 2026-09-09

- Fix Omarchy Quattro freeze when opening the calendar popup. Third-party
  plugins now receive a read-only `centerHoverRevealSuppressed` flag on the
  bar API; writing it threw `TypeError` in a loop and wedged `omarchy-shell`.
  Call `bar.setCenterHoverRevealSuppressed(value)` instead, matching stock
  `omarchy.clock`.
