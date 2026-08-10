# cull-001-workspace-key-gating: Cull keyboard shortcuts stay scoped to the Cull lens's loupe/compare views, and never fire in a text field

**What this covers**: as a photographer culling a shoot, I want the P/X/rating/
Return/scope keyboard vocabulary to only act on photos when a grid/loupe view
actually has focus — not while I'm typing in the search field, and not routed
through the Cull-specific Return/stack-nav/scope monitor when I'm not looking
at a Cull loupe. Two independent gates cooperate here and this card exercises
both:
- `GridKeyCaptureNSView`/`CullingKeyCaptureNSView.handleLocalKeyDown` both bail
  out when `firstResponder.isTextEditor` (`responder is NSTextView`) —
  a focused text field always wins
  (`Sources/TeststripApp/GridKeyCaptureView.swift:205-212`,
  `Sources/TeststripApp/CullingKeyCaptureView.swift:75-83`).
- `CullingKeyCaptureGate.isActive(lens:selectedView:)` — `lens == .cull &&
  selectedView != .cullGrid` — gates the *second*, Cull-only monitor
  that owns Return-promote, stack up/down nav, colorLabel, zoom, EXIF-cycle,
  scope-cycle, and the g/c/b sub-view switches
  (`Sources/TeststripApp/CullingKeyCaptureView.swift:11-14`, wired at
  `Sources/TeststripApp/LibraryGridView.swift:221`, passing
  `model.selectedLens`/`model.selectedView`). The parameter and its home
  type are unchanged in shape from before this push's lens rewrite — only the
  argument label (`lens:`, not `workspace:`) and the type it's checked
  against (`LibraryLens`, not the deleted `Workspace`) changed.

**Correction to the assumed premise**: P/X/0-5/U are *not* Cull-exclusive.
`GridKeyCaptureView` (a second, always-mounted monitor,
`Sources/TeststripApp/LibraryGridView.swift:228-236`) independently handles
pick/reject/clear-flag/rating for every grid-shaped mode, and
`GridKeyCommand.isAllowed(in:)` (`Sources/TeststripApp/GridKeyCaptureView.swift:97-113`)
allows `.pick`/`.reject`/`.rating` in **both** `.grid` (the Grid lens's plain
grid) and `.cullGrid`. So pressing `P` in the **Grid lens's grid** *does*
flag the selected photo — verified by reading `isAllowed`, not assumed. The
one grid mode where it's filtered out is `.libraryLoupe` (the Loupe lens's
single-photo view), where `isAllowed` only permits `.move(.left/.right)` and
`.returnToGrid` (`GridKeyCaptureView.swift:103-109`) — so P/X/ratings are
silently dropped there, and the Cull-only monitor never fires either
(`lens != .cull`). This card tests the real gates: text-field guard
(lens-independent) and the `CullingKeyCaptureGate` lens/view gate (via
Return-promote, which only that monitor produces), plus documents the
Grid-lens P-does-flag fact so a future reader doesn't relitigate it.

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
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for the Grid lens
   (confirm via `script/ax_drive.sh find --contains "Grid"` in the lens
   switcher, and its `.accessibilityValue("Selected")`).
2. Pick an unflagged asset id from the baseline (`--smoke` pre-flags 11/24 —
   choose one that reads NULL):
   ```bash
   TARGET=$(sqlite3 "$DB" "SELECT id FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NULL LIMIT 1;")
   ```
   Click that tile to select it (`script/ax_drive.sh find` its filename, then
   click), confirming the Grid lens's `.grid` mode has focus.
3. Press `P`. Per `GridKeyCommand.isAllowed(.grid)`, this *does* flag in
   the Grid lens's plain grid — assert it:
   ```bash
   sqlite3 "$DB" "SELECT json_extract(metadata_json,'\$.flag') FROM assets WHERE id = '$TARGET';"
   ```
4. Open that same asset in the **Loupe lens** (`.libraryLoupe`, not
   `.cullGrid`/the Cull lens's loupe) — double-click the tile or press
   Return/Space from the grid to open it. Pick a second, still-unflagged
   asset id (`TARGET2`) and press `P` while the Loupe lens has focus. Assert
   **nothing** changed:
   ```bash
   sqlite3 "$DB" "SELECT json_extract(metadata_json,'\$.flag') FROM assets WHERE id = '$TARGET2';"
   ```
5. Switch to Cull (⌘1). Confirm the lens switcher's "Cull" button reads
   selected (`script/ax_drive.sh find --role AXButton --label "Cull"`, check
   `.accessibilityValue`), landing in the Cull lens's loupe
   (`selectedView == .loupe`, its default sub-mode, satisfying
   `CullingKeyCaptureGate.isActive`).
6. **Corrected premise**: the search/query token field (placeholder "Search
   photos, people, places, or rating:3 camera:… ") is chrome gated by
   `LensChromePolicy.showsBrowseChrome` — present only in the four browse
   lenses (Grid/Loupe/Timeline/Map), absent in Cull and People
   (`Sources/TeststripApp/LibraryGridView.swift:8264-8270`). The Cull lens
   has no such field. An iteration-1 live run confirmed this by AX
   inspection: `ax find --role AXTextField` (unfiltered) returned no match
   anywhere in the Cull lens's tree. This step therefore asserts the
   field's **absence** in Cull (the actual chrome-policy behavior), rather
   than typing into a field that doesn't exist there:
   ```bash
   script/ax_drive.sh find --role AXTextField --contains "Search photos"
   ```
   Assert this returns **no match** while the Cull lens is active. (The
   text-editor guard itself — `firstResponder.isTextEditor` bailing both
   monitors — is exercised in the Grid lens, where the field actually lives;
   see cull-002+ for that coverage, or add it there if missing.)
7. Press `Return` (promote-and-reject-siblings — a shortcut only the
   Cull-only monitor produces) with the Cull loupe focused on the current
   `--smoke` seed. **Corrected premise**: the `--smoke` seed's assets are not
   members of any stack, and `AppModel.promoteCurrentFrameAndRejectSiblings`
   guards on stack membership — with no stack, this is a **designed no-op**,
   not evidence the monitor isn't firing. Record the selected asset's flag
   before and after and assert it is **unchanged**:
   ```bash
   sqlite3 "$DB" "SELECT json_extract(metadata_json,'\$.flag') FROM assets WHERE id = '<cull-loupe-selected-id>';"
   ```
   Positive promote-and-reject-siblings coverage (asserting the write *does*
   land, plus sibling rejection) is `cull-004-stack-promote-return.md`'s job.

## Expected
- Step 3: `$TARGET`'s flag becomes `pick`. **Fails if** it stays NULL — would
  mean the Grid lens unexpectedly stopped supporting the flag shortcuts (a
  real regression, not the originally-assumed gating).
- Step 4: `$TARGET2`'s flag stays NULL. **Fails if** it becomes `pick` — the
  Loupe lens would be leaking Cull-only shortcuts.
- Step 6: `ax find --role AXTextField --contains "Search photos"` returns no
  match in the Cull lens. **Fails if** a search field is found there —
  would mean Cull unexpectedly grew browse chrome (or this card's
  lens assumption about where the field lives is wrong).
- Step 7: the Cull-loupe selected asset's flag is unchanged after `Return` on
  the stackless `--smoke` seed. **Fails if** the flag changes — would mean
  `promoteCurrentFrameAndRejectSiblings` stopped guarding on stack
  membership, applying to a stackless asset when it shouldn't.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The task brief that generated the original version of this card assumed
  P/X have no meaning outside Cull. That's false for the Grid lens's plain
  **grid** — only the **Loupe lens** filters them out. Get this distinction
  right or the card asserts something the code doesn't do.
- `eventTargetsWindow` in both monitors treats *any* key-down while the app's
  window is key as in-scope, even if the event's own `windowNumber` differs
  (`targetWindowIsKey` fallback) — not exercised directly here, but relevant
  if a future card needs to test cross-window focus edge cases (e.g. a
  detached inspector panel).
- Step 6 asserts the search field's absence rather than typing into it,
  since Cull has no such field; the text-editor guard itself needs a
  Grid-lens card, not this one.
- Step 7 is a designed no-op on `--smoke` (no stacks); a stack fixture
  (`cull-004`) is needed for positive promote-and-reject-siblings coverage.

## Run status
**Reconciled 2026-08-09 (Task 13, unified-shell scenario-card sweep)**:
retitled ("...scoped to the Cull lens") and reworded every "workspace"
reference to "lens" throughout. Re-verified `CullingKeyCaptureGate.isActive`
directly against source: its parameter is now `lens: LibraryLens` (was
`workspace: Workspace`), the predicate itself (`lens == .cull &&
selectedView != .cullGrid`) is byte-identical to what it checked before —
only the type being compared changed, not the logic. Also corrected the
text-editor-guard citations, which had drifted (`GridKeyCaptureView.swift`'s
guard is at `:205-212`, not `:205-218`; `CullingKeyCaptureView.swift`'s is at
`:75-83`, not `:58-82`) — found by grepping `NSTextView`/`isTextEditor`
directly rather than trusting the prior line numbers. Replaced "Library
grid"/"Library Loupe"/"workspace switcher" with "Grid lens"/"Loupe lens"/
"lens switcher" throughout Steps 1-7. Supersedes prior status: the prior
UNRUN note cited a `workspace:`-labeled gate signature that no longer
compiles; nothing about that non-run carries forward, since the very
function signature it described has changed. Needs a fresh VM run.
