# cull-001-workspace-key-gating: Cull keyboard shortcuts stay scoped to the Cull loupe/compare views, and never fire in a text field

**What this covers**: as a photographer culling a shoot, I want the P/X/rating/
Return/scope keyboard vocabulary to only act on photos when a grid/loupe view
actually has focus — not while I'm typing in the search field, and not routed
through the Cull-specific Return/stack-nav/scope monitor when I'm not looking
at a Cull loupe. Two independent gates cooperate here and this card exercises
both:
- `GridKeyCaptureNSView`/`CullingKeyCaptureNSView.handleLocalKeyDown` both bail
  out when `firstResponder is NSTextView` — a focused text field always wins
  (`Sources/TeststripApp/GridKeyCaptureView.swift:205-218`,
  `Sources/TeststripApp/CullingKeyCaptureView.swift:58-82`).
- `CullingKeyCaptureGate.isActive(workspace:selectedView:)` — `workspace ==
  .cull && selectedView != .cullGrid` — gates the *second*, Cull-only monitor
  that owns Return-promote, stack up/down nav, colorLabel, zoom, EXIF-cycle,
  scope-cycle, and the g/c/b sub-view switches
  (`Sources/TeststripApp/CullingKeyCaptureView.swift:11-15`, wired at
  `Sources/TeststripApp/LibraryGridView.swift:180-192`).

**Correction to the assumed premise**: P/X/0-5/U are *not* Cull-exclusive.
`GridKeyCaptureView` (a second, always-mounted monitor,
`Sources/TeststripApp/LibraryGridView.swift:194-202`) independently handles
pick/reject/clear-flag/rating for every grid-shaped mode, and
`GridKeyCommand.isAllowed(in:)` (`Sources/TeststripApp/GridKeyCaptureView.swift:97-113`)
allows `.pick`/`.reject`/`.rating` in **both** `.grid` (Library's grid) and
`.cullGrid`. So pressing `P` in the plain **Library grid** *does* flag the
selected photo — verified by reading `isAllowed`, not assumed. The one grid
mode where it's filtered out is `.libraryLoupe` (Library's single-photo view),
where `isAllowed` only permits `.move(.left/.right)` and `.returnToGrid`
(`GridKeyCaptureView.swift:103-109`) — so P/X/ratings are silently dropped
there, and the Cull-only monitor never fires either (`workspace != .cull`).
This card tests the real gates: text-field guard (workspace-independent) and
the `CullingKeyCaptureGate` workspace/view gate (via Return-promote, which
only that monitor produces), plus documents the Library-grid P-does-flag
fact so a future reader doesn't relitigate it.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Fallback if the host console is locked: `script/vm_scenario_run.sh setup`,
then `sync smoke`, `launch smoke`, and drive with `script/vm_scenario_run.sh ax
...` / `sql smoke ...` instead of the direct `ax_drive.sh`/`sqlite3` calls
below.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library
   (confirm via `script/ax_drive.sh find --contains "Library"` in the
   workspace switcher).
2. Pick an unflagged asset id from the baseline (`--smoke` pre-flags 11/24 —
   choose one that reads NULL):
   ```bash
   TARGET=$(sqlite3 "$DB" "SELECT id FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NULL LIMIT 1;")
   ```
   Click that tile to select it (`script/ax_drive.sh find` its filename, then
   click), confirming Library's grid (`.grid` mode) has focus.
3. Press `P`. Per `GridKeyCommand.isAllowed(.grid)`, this *does* flag in
   Library's plain grid — assert it:
   ```bash
   sqlite3 "$DB" "SELECT json_extract(metadata_json,'\$.flag') FROM assets WHERE id = '$TARGET';"
   ```
4. Open that same asset in the **Library Loupe** (`.libraryLoupe`, not
   `.cullGrid`/Cull's loupe) — double-click the tile or press Return/Space
   from the grid to open it. Pick a second, still-unflagged asset id
   (`TARGET2`) and press `P` while the Library Loupe has focus. Assert
   **nothing** changed:
   ```bash
   sqlite3 "$DB" "SELECT json_extract(metadata_json,'\$.flag') FROM assets WHERE id = '$TARGET2';"
   ```
5. Switch to Cull (⌘1). Confirm the workspace switcher reads "Cull"
   (`script/ax_drive.sh find --contains "Cull"`), landing in the Cull loupe
   (`selectedView == .loupe`, satisfying `CullingKeyCaptureGate.isActive`).
6. Click into the search/query token field (placeholder "Search photos,
   people, places, or rating:3 camera:… "):
   ```bash
   script/ax_drive.sh find --role AXTextField --contains "Search photos"
   ```
   then click it to focus, and press `P`. Because
   `firstResponder is NSTextView`, both monitors bail before the shortcut
   fires — assert the letter `P` was typed into the field instead:
   ```bash
   script/ax_drive.sh wait --role AXTextField --contains "P"
   ```
   and assert the currently-selected Cull-loupe asset's flag is unchanged
   (record its id/flag before this step, re-check after).
7. Clear the field (⌘A, Delete) and press Escape or click the loupe stage to
   return focus to the Cull loupe. Press `Return` (promote-and-reject-
   siblings — a shortcut only the Cull-only monitor produces, so this
   isolates `CullingKeyCaptureGate` from the text-field guard already proven
   in step 6). Assert the flag write happened this time:
   ```bash
   sqlite3 "$DB" "SELECT json_extract(metadata_json,'\$.flag') FROM assets WHERE id = '<cull-loupe-selected-id>';"
   ```

## Expected
- Step 3: `$TARGET`'s flag becomes `pick`. **Fails if** it stays NULL — would
  mean Library's grid unexpectedly stopped supporting the flag shortcuts (a
  real regression, not the originally-assumed gating).
- Step 4: `$TARGET2`'s flag stays NULL. **Fails if** it becomes `pick` — the
  Library Loupe would be leaking Cull-only shortcuts.
- Step 6: the search field's AX value contains `P`, and the tracked asset's
  flag is unchanged. **Fails if** the keystroke instead flagged/rejected a
  photo — the text-editor guard is the confirm-before-write-adjacent
  invariant here (never act on typed input as a shortcut).
- Step 7: the Return-promote write lands (flag becomes non-NULL on the
  Return target, and — if it's part of a stack — siblings reject). **Fails
  if** nothing happens, meaning the Cull-only monitor isn't actually active
  in the Cull loupe.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The task brief that generated this card assumed P/X have no meaning in
  Library. That's false for the plain Library **grid** — only the Library
  **Loupe** filters them out. Get this distinction right or the card asserts
  something the code doesn't do.
- `eventTargetsWindow` in both monitors treats *any* key-down while the app's
  window is key as in-scope, even if the event's own `windowNumber` differs
  (`targetWindowIsKey` fallback) — not exercised directly here, but relevant
  if a future card needs to test cross-window focus edge cases (e.g. a
  detached inspector panel).
- Step 6/7 split the text-field guard (workspace-independent) from the
  workspace/view gate (`CullingKeyCaptureGate`) deliberately — collapsing
  them into one keystroke wouldn't tell you *which* gate is doing the work if
  the assertion failed.

## Run status
UNRUN — SQL not yet dry-run against a live catalog; needs human-present
execution per test/scenarios/README.md.
