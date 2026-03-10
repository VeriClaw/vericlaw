# future/operator-console/

React-based web UI for VeriClaw gateway mode — not included in v1.0-minimal.

## What it is

A browser-based operator console for monitoring and managing a running VeriClaw gateway:
- Session list and conversation inspector
- Channel status and health indicators
- Plugin management
- Live metrics dashboard

## Returns at

v1.3 — when the HTTP gateway mode ships.

## Files

- `app.js` — React application
- `index.html` — Entry point
- `styles.css` — Styling
- `tests/` — UI tests

## Note

In v1.0-minimal, `vericlaw status` and `vericlaw doctor` cover the operational visibility use cases. A web UI is unnecessary when there's one user and one device.
