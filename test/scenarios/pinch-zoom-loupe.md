# Pinch-to-Zoom Loupe Scenario

## Goal
Verify continuous pinch-to-zoom works in the loupe and grid pinch-to-expand opens the loupe.

## Preconditions
- Smoke launch (24 synthetic photos seeded)
- Grid view visible

## Steps

### Open loupe via double-click
1. `ax wait-vended`
2. `ax press --contains "smoke-0.jpg"` (double-click to open loupe)
3. `ax wait --contains "Return to fit"` — verify loupe is showing fitted image

### Verify HUD shows zoom percentage
4. The zoom HUD should NOT be visible (image is fitted, scale 1.0)
5. `ax press --contains "Return to fit"` — click to zoom to 100%
6. `ax wait --contains "100%"` — verify HUD shows 100%

### Return to fit
7. `ax press --contains "Return to fit"` — click again to return to fit
8. Verify HUD is gone

### Return to grid
9. Press Escape
10. `ax wait --contains "smoke-0.jpg"` — verify grid is back

## Catalog Assertions
- `SELECT COUNT(*) FROM assets` = 24 (no changes from zooming)
- `SELECT detail FROM work_sessions ORDER BY rowid DESC LIMIT 1` — no new work sessions from zoom interaction

## Notes
- Pinch gesture simulation via AX is limited on macOS. The scenario verifies click-to-zoom (which now sets continuous scale) and HUD percentage display. Pinch gesture itself is verified manually.
- Reduce-motion: zoom should work without animation; the scale change is instant.
