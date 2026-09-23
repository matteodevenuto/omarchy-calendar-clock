# Changelog

## 1.0.4 — 2026-09-23

- Run the sync backend as `/usr/bin/python3 -I` with a cleared environment
  (only `HOME`, `TZ`, `LC_ALL`), and invoke `/usr/bin/curl -q` with a minimal
  env, so no ambient `PATH`, `PYTHONPATH`, user site dir, or `~/.curlrc`
  can influence runtime code.

## 1.0.3 — 2026-09-09

- Fix Omarchy Quattro freeze when opening the calendar popup. Third-party
  plugins now receive a read-only `centerHoverRevealSuppressed` flag on the
  bar API; writing it threw `TypeError` in a loop and wedged `omarchy-shell`.
  Call `bar.setCenterHoverRevealSuppressed(value)` instead, matching stock
  `omarchy.clock`.
