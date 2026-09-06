# Changelog

## 0.4.0 — 2026-09-06

- Hover a running taskbar icon to see a miniature even when there is only one window
- Middle-click a taskbar icon (or a miniature) to close that window / those windows

## 0.3.3 — 2026-09-06

- Right-click a grouped taskbar icon: the close action is "Close all"
- Each hover miniature has an X to close that window

## 0.3.2 — 2026-09-06

- Keep hover miniatures open when moving the cursor from the icon onto a thumbnail, so you can click one to restore that window

## 0.3.1 — 2026-09-06

- Fix hover miniatures: do not stash compositor objects on the taskbar model (that broke plugin reload and threw a runtime error when a second window opened)

## 0.3.0 — 2026-09-06

- Hover a taskbar icon that has more than one window to show live miniatures; click a miniature to raise that window

## 0.2.1 — 2026-09-06

- Stop the work-area clamp from fighting titlebar drag (windows stay where you put them)
- Prefer a real titlebar: GTK_CSD=0, Chromium system frame, no CSD-tab dragging

## 0.2.0 — 2026-09-05

- Double-click a window titlebar to maximize or restore (same work-area maximize as the yellow button)

## 0.1.1 — 2026-09-05

- `install.sh` snapshots OCD/Hyprland files (and fetches stock OCD dock + `ocd.lua`) on first install
- `uninstall.sh` restores that snapshot, strips leftover overlay hunks, re-enables the OCD dock, and removes overlay helpers

## 0.1.0 — 2026-09-05

Initial overlay on top of OCD v1.2.

- Icon taskbar with per-app grouping, pins, and a right-click menu
- `ocd-window` helpers: raise, maximize-as-float, minimize, close, fit
- Hyprland classic desktop: all windows float, snap, click-to-front, work-area clamp
- Click-to-focus and tiling key unbinds
- Titlebars sit outside the client; maximize uses the work area instead of exclusive fullscreen
