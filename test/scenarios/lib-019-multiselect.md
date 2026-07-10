# lib-019-multiselect: click / ⌘-click / ⇧-click selection semantics and focus policy

**What this covers**: the grid cell's click-activation logic
(`assetActivation`, `Sources/TeststripApp/LibraryGridView.swift:6535-6587`) —
plain click (primary selection), ⌘-click (toggle batch selection), ⇧-click
(range-select from an anchor), the invariant that clicking for selection must
**not** steal keyboard culling focus, the AX value exposed for selection
state, the "Cull These" context-menu entry, and the toolbar cull fast-path
button.

Exact semantics, verified at `LibraryGridView.swift:6535-6587,
6517-6533, 2894-2900+, 2320-2323`:

- **Plain click** (no modifiers) → `selectAsset(asset.id)`, i.e. sets
  `model.selectedAssetID` (single/primary selection). Per
  `AssetActivationFocusPolicy.shouldFocusCullingSurface(for:
  .singleClickSelection)` → **`false`** (line 6527) — plain-click selection
  explicitly does **not** call `focusCullingSurface()`.
- **⇧-click** → `model.selectBatchRange(to: asset.id)` (range-anchor
  selection). Also gated `.batchSelection` → **`false`** — shift-click also
  does not steal culling focus.
- **⌘-click** → `model.toggleBatchSelection(asset.id)` (add/remove one
  asset from the batch set). Same `.batchSelection` → **`false`** gate.
- **Double-click** (`TapGesture(count: 2)`, simultaneous gesture) →
  `model.openAssetInLoupe(asset.id)`, and *this* activation kind
  (`.openInLoupe`) → **`true`** at line 6529 — double-click legitimately
  focuses the culling surface, since it's actually entering the
  loupe/culling view.
- **VoiceOver/accessibility activation** (`.accessibilityAction`, line
  6574-6579) → also calls `selectAsset`, and its kind `.accessibilitySelection`
  → **`true`** — accessibility-driven selection *does* focus the culling
  surface (differs from the mouse-click cases; presumably because an AX
  client has no separate "enter loupe" gesture available, so selection itself
  needs to move focus for VoiceOver users to keep operating).
- **The core invariant this card must falsify**: `AssetActivationFocusPolicy.
  shouldFocusCullingSurface` returns `false` for exactly
  `{singleClickSelection, batchSelection}` and `true` for exactly
  `{openInLoupe, accessibilitySelection}` (`LibraryGridView.swift:6525-6532`).
  A plain click or ⌘/⇧-click for selection must never move keyboard focus off
  whatever currently owns it (e.g. the query token field, or a sheet) onto
  the culling key-capture view.
- **AX selection value**: `assetSelectionAccessibilityValue`
  (lines 6582-6586) — reads `"Selected"` / `"Not selected"` for the primary
  selection state (`model.selectedAssetID == asset.id`), and appends
  `", batch selected"` when `model.isBatchSelected(asset.id)` is also true.
  So a cell that is both primary-selected and batch-selected reads exactly
  `"Selected, batch selected"`.
- **Context menu "Cull These"** (line 2320-2323): right-click context menu
  entry; per the comment at line 2892 ("Right-click 'Cull These': culls the
  batch selection if the clicked...") it culls the current batch selection —
  confirm from the surrounding code whether right-clicking an
  unselected/non-batch cell culls just that one cell or requires an existing
  batch selection first; read `cullSelection(anchoredOn:)`
  (line 2894) fully before asserting the exact anchor semantics in Expected.
- **Toolbar cull fast-path**: a toolbar button that starts a culling session
  from the current selection — locate its exact AXHelp/label in
  `LibraryGridView.swift` (grep `canBeginCullingSession`, referenced at
  line ~283 per the disabled-state grep in `lib-018`'s sibling read) and cite
  it precisely before driving; it's disabled when `!model.canBeginCullingSession`.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
`--smoke`'s 24 assets are enough for range-select and toggle testing; no
special fixture needed.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library. First
   put keyboard focus somewhere *other* than the grid's culling surface — the
   query token field is the easiest: `ax_drive.sh press --role AXTextField
   --contains "Search your library"` (per `token-query-filter.md`'s field
   reference) to give it first-responder status.
2. Plain-click grid cell at index 0. Assert: cell 0's AX value reads
   `"Selected"`; and — the invariant — the query token field is *still* the
   window's first responder (query it, e.g. by typing a character and
   confirming it lands in the field, not swallowed as a grid shortcut; or via
   `AXFocusedUIElement` if `ax_drive.sh` exposes that).
3. Refocus the query field again (repeat step 1's setup). ⇧-click cell at
   index 3. Assert: cells 0-3 (the anchor-to-target range) all read
   `"Selected"` or the batch-selected variant per whatever
   `selectBatchRange` actually sets — confirm from source whether range
   selection sets the *primary* selectedAssetID too, or purely batch state,
   before writing this assertion as `"Selected"` vs `"...batch selected"`.
   Confirm the query field is still first responder (focus not stolen).
4. Refocus the query field. ⌘-click cell at index 5 (not previously
   selected). Assert cell 5 now reads batch-selected; focus still on the
   query field. ⌘-click cell 5 again — assert it toggles back to not
   batch-selected (`toggleBatchSelection` is a true toggle).
5. Double-click cell 0. Assert the loupe opens (per `lib-012-grid-keys.md`'s
   Return/Space transition) — and this time, *do* expect the culling surface
   to receive keyboard focus (per `.openInLoupe` → `true`) — verify by
   sending a culling shortcut key (e.g. `p`) right after the double-click and
   confirming it acts as a cull shortcut rather than landing in the (now
   dismissed) query field.
6. Return to grid. Batch-select 2-3 cells via ⌘-click. Right-click one of
   them; assert a context menu appears containing "Cull These"
   (`ax_drive.sh find --role AXMenuItem --label "Cull These"` after
   triggering the right-click, if `ax_drive.sh` supports a right-click/
   secondary-click verb — confirm its `--help` first).
7. Locate and press the toolbar cull fast-path button (exact label TBD —
   confirm from source before driving) with the same batch selection active;
   assert it starts a culling session equivalent to "Cull These".

## Expected
- Step 2: plain click selects but never steals focus from the query field —
  **fails if** clicking a cell yanks first-responder status away from
  wherever it was.
- Step 3: range selection covers exactly the anchor-to-target span, no more,
  no less, and — same invariant — leaves focus alone.
- Step 4: ⌘-click is a true toggle (on then off returns to original state);
  focus untouched both times.
- Step 5: double-click is the one activation that legitimately moves focus
  to the culling surface — **fails if** it does NOT (a `p` keypress right
  after double-click should register as pick, not get swallowed/misrouted).
- Steps 6-7: "Cull These" and the toolbar fast-path both act on the current
  batch selection and produce the same downstream effect (starting a culling
  session scoped to those assets) — **fails if** they diverge in scope (e.g.
  one culls only the right-clicked cell while the other culls the full batch).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The focus-preservation invariant (steps 2-4) is easy to assert wrong if the
  chosen "focus witness" (typing into the query field) itself has side
  effects that confuse the assertion — pick a witness action that's cheap to
  verify and cheap to undo (e.g. type one character, check it landed, delete
  it) rather than committing a real query.
- Range-select's exact effect on `selectedAssetID` vs. pure batch-membership
  needs to be read from `selectBatchRange`'s implementation (not located in
  this pass — only its call site at line 6553) before Step 3's assertion can
  be written precisely; don't guess the AX-value string.
- "Cull These"'s exact anchor semantics (culls the right-clicked cell alone
  vs. the whole existing batch selection) needs `cullSelection(anchoredOn:)`
  (line 2894) read in full — flagged, not resolved, in this pass.

## Run status
NOT RUN — no live GUI launch performed for this task (headless-only
constraint). Click/modifier→command mapping and the focus-policy invariant
verified by direct source read at `Sources/TeststripApp/LibraryGridView.swift:
6517-6587`; AX selection-value format verified at lines 6582-6586; context
menu location verified at lines 2320-2323, 2892. `selectBatchRange`'s and
`cullSelection(anchoredOn:)`'s full bodies, and the toolbar cull button's
exact label, were **not** read in this pass — resolve those before the first
live run so Steps 3, 6, and 7 aren't driven against a guess.
