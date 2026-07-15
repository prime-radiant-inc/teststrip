# lib-012-grid-keys: grid keyboard navigation, rating shortcuts, and loupe transition

**What this covers**: the Library grid's own keyboard monitor
(`GridKeyCaptureNSView`, `Sources/TeststripApp/GridKeyCaptureView.swift`) —
arrow/Home/End movement, digit-key ratings 0-5, `p`/`x`/`u` pick/reject/clear,
and Return/Space opening the loupe (`.grid`/`.cullGrid` → `.libraryLoupe`/
`.loupe`). This is a distinct monitor from the culling loupe's
`CullingKeyCaptureView` (see `people-confirm-writes-on-return.md` and
`cull-pass-scope-and-undo.md` for that one) — `CullingKeyCaptureGate.isActive`
is explicitly false while `.cullGrid` is showing (comment at
`CullingKeyCaptureView.swift:4-10`), so grid keys are the *only* monitor live
on the grid.

Exact key→command mapping, verified at `GridKeyCaptureView.swift:60-113`:
- Left/Right/Up/Down arrows → `.move(.left/.right/.up/.down)` (`GridSelectionMovement.nextIndex`, clamped at grid edges, `.up`/`.down` step by the live column count).
- Home/End → `.move(.home/.end)` (jump to index 0 / count-1).
- Return or keypad Enter, or Space → `.openLoupe`.
- Escape → `.returnToGrid` (only allowed while `mode == .loupe`; a no-op in `.grid`/`.cullGrid` per `isAllowed(in:)` at line 97-113).
- `0`…`5` → `.rating(0)`…`.rating(5)`.
- `p` → `.pick`, `x` → `.reject`, `u` → `.clearFlag`.
- Any event carrying ⌘/⌃/⌥ is rejected outright (`GridKeyInput.init(event:)` line 259: `disallowedModifiers` must be empty) — so e.g. ⌘1/⌘2 workspace switches never get eaten by this monitor.
- Key capture is suppressed while the first responder is an `NSTextView` (`isTextEditor`, line 306) — typing in the query token field must not fire grid shortcuts.

`isAllowed(in mode:)` (line 97-113) also gates by mode: in `.grid`/`.cullGrid`
everything but `.returnToGrid` is allowed; in `.libraryLoupe` only
left/right/`.returnToGrid` are allowed (no rating/pick/reject there — the
Library loupe has no culling chrome, see `library-loupe-no-cull-chrome.md`).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
`--smoke` seeds 24 synthetic assets; grid keyboard nav needs no special
fixture. Note the pre-seeded state: 11/24 flagged, 4/24 rated 3 — ratings
written by this card's `p`/`x`/digit steps must be diffed against that
baseline, not against "0 rated" assumption.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library workspace
   (plain grid, not Cull).
2. `ax_drive.sh press --role AXButton --help "Rate 1"` is not applicable here
   (that's the loupe's rating control) — instead click a grid cell directly
   (`ax_drive.sh find --role AXButton` to locate one, then a raw AX press) to
   establish keyboard focus/selection on asset index 0. Confirm via the
   cell's `AXValue` reading `"Selected"` (see `assetSelectionAccessibilityValue`,
   `LibraryGridView.swift:6582-6586`).
3. Send the Right arrow key (via `osascript`/`cliclick` keystroke, since
   `ax_drive.sh` has no dedicated arrow-key verb — check its `--help` first for
   a `key`/`keystroke` verb and use that if present). Assert selection moved
   to index 1 (its cell now reads `"Selected"`, index 0 reads
   `"Not selected"`).
4. Send Down arrow; assert selection moved by the live column count (query
   `model.libraryColumnCount`-equivalent — cross-check by noting which row the
   focus visually lands on, or infer from the grid's column count at the
   current window width).
5. Send End; assert the last asset (id order from
   `SELECT id FROM assets ORDER BY rowid`) is selected. Send Home; assert
   index 0 is selected again.
6. With a cell focused, send `3`; then query
   `SELECT json_extract(metadata_json,'$.rating') FROM assets WHERE id='<id>';`
   — assert it reads `3`, and that a `.xmp` sidecar was written next to that
   asset's original (per the non-destructive/confirm-before-write invariant —
   a keyboard rating is itself the confirming gesture, so a sidecar write here
   is expected, not a violation).
7. Send `p` on a different, unpicked asset; query the asset's flag in
   `metadata_json` (`$.flag` or equivalent verified against
   `CatalogMigrations.swift`) — assert it now reads "pick". Send `u` on the
   same asset; assert the flag clears back to unset.
8. Send `x` on a third asset; assert it reads "reject".
9. Press Return on a focused grid cell. Assert the view transitions to the
   loupe (`.libraryLoupe` from `.grid`, or `.loupe` if driving from
   `.cullGrid`) — check for the loupe's distinguishing chrome (large single
   image, no grid) via `ax_drive.sh wait --role AXImage` or similar. Press
   Escape; assert it returns to the grid.
10. Repeat step 9 using Space instead of Return; same expected transition.

## Expected
- Steps 3-5: selection index changes match `GridSelectionMovement.nextIndex`
  arithmetic exactly, clamped at edges (Left at index 0 stays at 0; Right at
  the last index stays there) — **fails if** movement overshoots/undershoots
  or wraps.
- Step 6: `metadata_json` rating is exactly `3` and a sidecar exists —
  **fails if** the rating didn't persist, or a sidecar was written for a
  *different* asset than the focused one.
- Step 7: flag toggles pick→(via u)→cleared correctly — **fails if** `u`
  clears a different asset's flag, or leaves the pick flag in place.
- Steps 9-10: both Return and Space open the loupe; Escape returns to grid —
  **fails if** either key is silently swallowed (no transition) or if Escape
  in `.grid` mode incorrectly does something (per `isAllowed`, it should be a
  no-op — no `.returnToGrid` in `.grid` mode, so pressing Escape while already
  on the grid should have no visible effect; only test its effect from the
  loupe).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- Rating and pick/reject *from the plain grid* write immediately (no
  confirmation sheet) — unlike Autopilot proposals, a direct keyboard rating
  IS the confirming user gesture, so this is correct per the
  confirm-before-write invariant, not a violation. Worth calling out
  explicitly in Expected so a future reader doesn't mistake it for a bug.
- `ax_drive.sh` (as of this writing, see README) has no documented
  arrow-key/character-key send verb distinct from `type` (which targets a
  specific field) — confirm its `--help` output for a raw keystroke verb
  before driving this card; if none exists, this is a driver gap worth
  reporting, not something to route around with an undocumented `osascript`
  hack baked silently into the card.

## Run status
NOT RUN — no live GUI launch performed for this task (headless-only
constraint). Key→command mapping and mode gating verified by direct source
read at `Sources/TeststripApp/GridKeyCaptureView.swift:60-113, 220-230,
257-291`; `CullingKeyCaptureGate` isolation verified at
`Sources/TeststripApp/CullingKeyCaptureView.swift:11-15`. Needs a live AX
session to execute Steps 1-10.
