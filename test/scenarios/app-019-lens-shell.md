# app-019-lens-shell: The unified toolbar lens switcher (six lenses, one sidebar, source/lens orthogonality)

**What this covers**: the unified-shell push (`docs/superpowers/specs/2026-08-07-unified-shell-design.md`)
collapses the old Cull/Library/People workspace Picker into one toolbar lens
switcher — Cull/Grid/Loupe/Timeline/Map/People, ⌘1–⌘6 — over one sidebar.
Every lens is source-scoped, and switching lenses must never change the
selected source. This card is the **only gate** on: the switcher's six
buttons and their disabled state/tooltip, the Stacks sidebar section's
Cull-only gating, the Sets "+" hint popover not leaking onto the Smart
Collections header, the "Cull these" result-header button (case-sensitive,
distinct from the grid's "Cull These" context-menu item), session-restore's
lens handling, and Recent Work's reopen-keeps-lens behavior. No unit test can
reach any of this — the repo has no SwiftUI view-inspection library.

Source: `Sources/TeststripApp/LibraryGridView.swift` (`lensSwitcher`
`:499-526`, `libraryResultHeader`'s "Cull these" button `:964-970`, window
subtitle install `:140`), `Sources/TeststripApp/LibraryLens.swift`
(`LibraryLens` enum `:10-30`, `keyEquivalent` `:46-55`, `defaultViewMode`
`:58-67`, `LensRules.availability`/`.availabilities`/`.resolvedLens`
`:106-144`), `Sources/TeststripApp/AppModel.swift` (`selectLens` `:4752-4754`,
`lensAvailabilities` `:4757-4762`, `applySource`'s resolved-lens fallback
`:4877-4885`, `cullCurrentResults`/`cullTheseSourceTitle` `:5811-5824`,
`SessionRestoreState` restore `:11705-11766` — `isRestorableLens` `:11770-
11772`, `currentMapQuery` `:10900-10910`, `timelinePresentation` `:3324-3325`,
`peopleInCurrentSource` `:2296,3669`), `Sources/TeststripApp/SidebarView.swift`
(Stacks gating `:46-55`, `sectionHeader`/`headerWithAddButton`/`addButton`
`:99-169`), `Sources/TeststripApp/main.swift` (`LensCommands` ⌘1-⌘6
`:168-174`, `InspectorCommands` ⌥⌘1-3 `:586-607`),
`Sources/TeststripApp/SessionRestoreState.swift` (`currentVersion = 2`
`:15`).

**Corrections to the plan** (verified against source in this pass — see the
task-12 report for the grep evidence):
- The sidebar is **not** byte-identical across lenses. Only the **Stacks ·
  Auto-Grouped** section is lens-gated (`SidebarView.swift:46`, `if
  model.selectedLens == .cull`), specifically to keep a per-stack SQL query
  off every other lens's view body. Every other section (`Library`,
  `Imports`, `Smart Collections`, `Sets`, `Folders`, `Recent Work`,
  `Selection`) renders identically regardless of lens.
- The "Cull these" result-header button (`LibraryGridView.swift:964`,
  lowercase *t*) and the grid's "Cull These" context-menu item
  (`AssetGridCellContextMenuPresentation.swift:35`, capital *T*) are
  **different controls that cull different things** — the header button
  culls the current result set (`cullCurrentResults()`), the context-menu
  item culls the current selection (`cullCurrentSelection()`,
  `AppModel.swift:5789`/`:5794`). Match the header button by **exact-case
  label** (`ax_drive.sh find --label "Cull these"`, not `--contains`, and
  never case-insensitively) — a loosened match will silently hit the wrong
  control and cull the wrong set.
- Reading `LibraryLens.defaultViewMode` (`:58-67`) directly: the Cull lens's
  *default* sub-mode is `.loupe`, not a grid. Pressing ⌘1 on a lens the app
  has not visited yet in this session lands straight in the culling loupe
  (`lastCullViewMode` defaults to `.loupe`, `AppModel.swift:2011`), and both
  that route and the Loupe lens's `.libraryLoupe` route render the window
  subtitle `"Loupe"` (`LibraryGridView.swift:8378`). This is a known,
  already-flagged UX quirk (see `app-003-workspace-switching.md`'s note:
  "switcher says Cull but ⌘1 lands on a view subtitled 'Loupe'") — the
  subtitle alone cannot disambiguate Cull-lens-in-loupe from Loupe-lens; Step
  4 below accounts for it.
- Session restore does not special-case "mid-cull" — reading
  `isRestorableLens` (`AppModel.swift:11770-11772`) directly, **every** quit
  while the Cull lens is selected relaunches on Grid, whether or not a
  culling run was active; the other five lenses always restore as-is. Step 9
  below asserts the actual (simpler, unconditional) rule rather than the
  plan's "mid-cull" framing.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. Assert the toolbar's principal slot holds an accessibility container
   labelled `"Lens"` (`lensSwitcher`'s `.accessibilityLabel("Lens")`,
   `LibraryGridView.swift:525`) containing six buttons labelled `Cull`,
   `Grid`, `Loupe`, `Timeline`, `Map`, `People` in that order
   (`LibraryLens.allCases`/`.title`, `LibraryLens.swift:11-16,20-29`):
   ```bash
   for name in Cull Grid Loupe Timeline Map People; do
     script/ax_drive.sh find --role AXButton --label "$name"
   done
   ```
3. Assert **absence** of the deleted controls:
   ```bash
   script/ax_drive.sh find --role AXRadioButton --label "Workspace"   # expect not-found
   script/ax_drive.sh find --contains "Library View"                 # expect not-found
   ```
4. Press ⌘1 through ⌘6 in turn (`LensCommands`, `main.swift:168-174`, key
   equivalents `1`-`6` per `LibraryLens.keyEquivalent`,
   `LibraryLens.swift:46-55`). After each, read `.navigationSubtitle`
   (`LibraryGridChromePolicy.windowSubtitle(for:)`, `LibraryGridView.swift:
   8375-8386`) via the window's AXSubrole/title, and assert the scope line's
   source title (`model.scopeLine.sourceTitle`, rendered by `scopeLineBar`,
   `LibraryGridView.swift:750-767`, AX label `"Scope"`) is **unchanged**
   across all six:
   - ⌘1 (Cull) → subtitle `"Loupe"` (default sub-mode; see the correction
     above — do not read this as a bug if seen for the first ⌘1 press)
   - ⌘2 (Grid) → `"Grid"`
   - ⌘3 (Loupe) → `"Loupe"`
   - ⌘4 (Timeline) → `"Timeline"`
   - ⌘5 (Map) → `"Map"`
   - ⌘6 (People) → `"People"`
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "<expected subtitle>"
   ```
5. Select a source (a smart collection row in the sidebar with a nonzero
   count, e.g. whichever of `Rejects`/`Five Stars`/`Needs Keywords` is
   present on `--smoke` — see `cull-015-sidebar-sources.md` for the exact
   predicate set), note its title in the scope line, then cycle ⌘1–⌘6 again
   and assert the scope line's source title still names that source after
   **every** switch — the ⌘1–⌘6 orthogonality contract
   (`applySource`'s lens-preserving fallback, `AppModel.swift:4877-4885`;
   `selectLens` only ever changes `selectedView`, never `selectedSource`,
   `AppModel.swift:4752-4754`).
6. Assert the sidebar's non-Stacks sections are identical across all six
   lenses, and that **Stacks · Auto-Grouped is Cull-only** — the corrected
   assertion (see above), asserted in both directions:
   ```bash
   # Present-everywhere sections: pick two that should always render.
   script/ax_drive.sh find --contains "Library"
   script/ax_drive.sh find --contains "Smart Collections"
   ```
   With a stack-bearing fixture (`--smoke` has none per
   `test/scenarios/README.md` — this half is expected untestable-without-
   fixture, note it as such rather than fabricating one):
   - In the Cull lens: `script/ax_drive.sh find --contains "Auto-Grouped"` →
     found (if `model.cullingStackListEntries()` is nonempty).
   - In every other lens: `script/ax_drive.sh find --contains "Auto-Grouped"`
     → **not found**, even with the identical stack data present — this is
     the load-bearing negative half of the assertion and must be checked
     explicitly, not assumed from the Cull-lens positive.
7. Force an `Analysis Failures` (`SmartCollection.providerFailures`) row into
   existence — `--smoke` seeds no provider failures, so hand-seed one row
   directly (the same "prove the wiring, not the detection" pattern
   `inspect-004-retry-surfaces.md` already uses for provider-failure rows):
   ```bash
   ASSET_ID=$(sqlite3 "$DB" "SELECT id FROM assets LIMIT 1;")
   sqlite3 "$DB" "INSERT INTO evaluation_failures (asset_id, provider, message, failed_at, updated_at) VALUES ('$ASSET_ID', 'test-provider', 'synthetic failure', strftime('%s','now'), strftime('%s','now'));"
   ```
   Relaunch or trigger a sidebar refresh so `smartCollectionCounts` picks it
   up, then select the `Analysis Failures` row while in the Cull lens.
   Assert the app falls back to Grid (`LensRules.resolvedLens`,
   `LibraryLens.swift:137-144`) and the Cull segment renders `.disabled`
   with AXHelp `"Nothing here is cullable"` (`LensRules.availability`'s
   `sourceIsDiagnostic` branch, `LibraryLens.swift:118-120`; `LibrarySource
   .isDiagnostic`'s `.smartCollection(.providerFailures)` case,
   `LibrarySource.swift:78-79`):
   ```bash
   script/ax_drive.sh find --role AXButton --label "Cull" --help "Nothing here is cullable"
   ```
8. Run a token search (`rating:5`), press the result-header **"Cull these"**
   button (exact-case match — see the correction above:
   `script/ax_drive.sh find --label "Cull these"` then `press --label "Cull
   these"`, never `--contains`), and assert the scope line names the search
   (the chip text, since `cullTheseSourceTitle()` prefers
   `activeLibraryFilterChips` over the raw source title,
   `AppModel.swift:5822-5825`) and the catalog gained a `culling` work
   session:
   ```bash
   sqlite3 "$DB" "SELECT kind, title FROM work_sessions WHERE kind='culling' ORDER BY created_at DESC LIMIT 1;"
   ```
9. Quit and relaunch. Assert the source and lens come back
   (`SessionRestoreState` v2, `SessionRestoreState.swift:15`) **for every
   lens except Cull**; and that quitting while the Cull lens was selected —
   regardless of whether a culling run was active — relaunches on the same
   source in **Grid**, per `isRestorableLens` (`AppModel.swift:11770-11772`,
   `lens != .cull`, unconditional). Drive this twice: once quitting from the
   Timeline lens (expect Timeline restored), once quitting from the Cull
   lens (expect Grid, not Cull).
10. **Every lens is source-scoped — assert it, don't assume it.** With a
    saved static Set selected (create one via the Sets "+" button on a
    multi-asset selection first if none exists), press ⌘5 (Map) and assert
    the coverage badge (`model.geotaggedCoverage`, `LibraryGridView.swift:
    7596,7674`) counts the **set**, not the catalog (behaviour change 11,
    `currentMapQuery()`, `AppModel.swift:10900-10910`, which ANDs in
    `.assetSet(selectedAssetSetID)` for explicit-ID sources):
    ```bash
    sqlite3 "$DB" "SELECT COUNT(*) FROM json_each((SELECT json_extract(membership_json,'\$.manual._0') FROM asset_sets WHERE name='<set name>'));"
    ```
    (This `.manual._0` JSON path is the same pattern already used and
    live-verified in `cull-020-pass-scope-and-undo.md:58` and
    `cull-025-run-strip-completion.md:385` for `AssetSet.Membership`'s
    synthesized Codable shape — not guessed here.)
    Then press ⌘4 (Timeline) and assert the year ribbon's total matches the
    same number (behaviour change 7, `timelinePresentation`,
    `AppModel.swift:3324-3325`, source-scoped via `model.assets`), and ⌘6
    (People) and assert the people list (`model.peopleInCurrentSource`,
    `AppModel.swift:2296,3669`, populated via `catalog.repository.people
    (assetIDs: scopeAssetIDs)`) holds only people present in the set.
11. Reopen a culling session from the sidebar's Recent Work section
    (`applySource`'s `.workSession` case → `applyWorkSession`,
    `AppModel.swift:4870,4888-4907`) while in the Grid lens. Assert the lens
    is **still Grid** (behaviour change 10 — `applySource`'s resolved-lens
    fallback at `:4877-4885` only forces a lens change when the *current*
    lens is disabled for the reopened source; it used to force the loupe
    unconditionally).
12. Assert the Sets "+" hint popover does **not** fire on the Smart
    Collections header. The Sets header's add button
    (`accessibilityLabel("New Set from Selection")`) is bound to
    `isShowingSavedSetsNoSelectionHint` (`SidebarView.swift:107`); the Smart
    Collections header's add button
    (`accessibilityLabel("New from search")`) passes `hintBinding: nil`
    (`SidebarView.swift:115`, `headerWithAddButton`/`addButton` at
    `:123-169` — a single shared `@State` bound to two `.popover`s was the
    bug this guards against). With no selection, click each header's "+" in
    turn. On `--smoke`, first run the zero-result search `zzzznotfound`, wait
    until the result header reports 0 photos, and do not batch-select anything;
    this establishes the actual no-selection branch
    (`canSaveSelectedAssetAsManualSet`, `AppModel.swift:3282-3284`). SwiftUI
    vends each header/button pair as one `AXHeading`, with the button's exact
    U+2026-ellipsis help string on that heading, so drive the live-proven
    heading/help routes rather than the discarded button labels:
    ```bash
    script/ax_drive.sh press --role AXHeading --label "Smart Collections" --help "New from search…"
    script/ax_drive.sh find --contains "Select photos, then save them as a set"   # expect not-found
    script/ax_drive.sh press --role AXHeading --label "Sets" --help "New Set from Selection…"
    script/ax_drive.sh find --contains "Select photos, then save them as a set"   # expect found
    ```
13. **Sharp edge to record:** ⌥⌘1/⌥⌘2/⌥⌘3 remain the inspector-section
    scrolls (`InspectorCommands`, `main.swift:586-607`, `InspectorTab
    .keyEquivalent` `1`/`2`/`3`, `InspectorView.swift:495-500`) and sit
    directly beneath ⌘1–⌘3, which are now lens selectors, not the old
    workspace switch; `inspect-001-toggle-tabs.md` is the card that pins the
    inspector side of this binding.

## Expected
- Step 2: **fails if** any of the six buttons is missing, mislabeled, or out
  of order, or if the container's accessibility label isn't `"Lens"`.
- Step 3: **fails if** either deleted control is still reachable.
- Step 4: **fails if** any subtitle doesn't match the table (the Cull/Loupe
  collision is expected and documented, not a failure by itself — a failure
  here means a *different* lens's subtitle disagrees with `windowSubtitle
  (for:)`), or if the scope line's source title changes across the six
  presses.
- Step 5: **fails if** the scope line's source title ever reverts to a
  different source mid-cycle — that would mean a lens switch silently
  re-scoped.
- Step 6: **fails if** any non-Stacks section differs between lenses, if
  Stacks renders outside the Cull lens, or if Stacks is absent from the Cull
  lens despite `cullingStackListEntries()` being nonempty.
- Step 7: **fails if** the Cull segment is enabled while `Analysis Failures`
  is selected, if the AXHelp text doesn't read exactly `"Nothing here is
  cullable"`, or if the app doesn't fall back to Grid.
- Step 8: **fails if** `find --label "Cull these"` matches the grid's "Cull
  These" context-menu item instead (case mismatch would indicate the AX
  driver's match is not case-sensitive — flag immediately, don't loosen the
  card), if the scope line doesn't name the search, or if no `culling`
  session row appears.
- Step 9: **fails if** any of the five non-Cull lenses fails to restore, or
  if a Cull-lens quit restores to anything other than Grid.
- Step 10: **fails if** the Map coverage badge, the Timeline year-ribbon
  total, or the People list count the whole catalog instead of the set —
  this is exactly the pre-existing gap behaviour change 11 fixes; a
  regression here is a P0 for this push.
- Step 11: **fails if** reopening the culling session forces the loupe
  (Cull lens) instead of leaving Grid selected.
- Step 12: **fails if** the Smart Collections "+" shows the "save them as a
  set" hint popover, or if the Sets "+" fails to show it.

## Cleanup
```bash
sqlite3 "$DB" "DELETE FROM evaluation_failures WHERE provider = 'test-provider';"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- Step 6's stack-presence positive half is untestable on `--smoke` (no
  persisted stacks, per `test/scenarios/README.md`) — same gap already
  tracked by `cull-013-filmstrip.md`/`cull-014-stack-rail.md`/
  `cull-015-sidebar-sources.md`. The negative half (Stacks absent outside
  Cull) is testable on any fixture, including `--smoke`, and must not be
  skipped.
- Step 7's hand-seeded `evaluation_failures` row proves the wiring
  (`isDiagnostic` → `LensRules.availability` → disabled segment with the
  right AXHelp), not that the app's own evaluation pipeline ever produces
  such a row live — same caveat `inspect-004-retry-surfaces.md` already
  notes for its own synthesized failure rows.
- Step 10 needs a saved static Set with a known, small membership to make
  the "counts the set, not the catalog" comparison legible; the card leaves
  the exact set-creation gesture to whoever drives it live (any nonzero-size
  multi-select saved via the Sets "+" works), and doesn't prescribe photo
  count so the query is written against whatever set gets created.
- The window subtitle collision noted in the corrections (Cull's `.loupe`
  default vs. the Loupe lens's `.libraryLoupe`, both rendering `"Loupe"`) is
  a genuine AX ambiguity: a driver relying on the subtitle text alone cannot
  tell which lens is active when the subtitle reads `"Loupe"`. The lens
  switcher's own `.accessibilityValue("Selected"/"Not selected")` per button
  (`LibraryGridView.swift:519`) is the disambiguator — read that instead of
  (or in addition to) the subtitle whenever the two lenses might be
  confused.

## Run status
UNRUN — authored 2026-08-08 for the unified-shell push (Task 12), source-cited
against `feat/unified-shell` @ `496abf1e`. Pending a live VM run per
`script/vm_scenario_run.sh`.

**Reconciled 2026-08-09 (Task 13, citation fixes)**: two drifted line
citations found in review and corrected here, both re-verified directly
against source: Step 8's `cullTheseSourceTitle()` citation
(`AppModel.swift:5820-5823` → `:5822-5825`) previously excluded the
function's own declaration line and its operative return statement (the
"prefers chips over source title" logic actually sits on the line the old
range cut off); the Source section's and Step 4's two disagreeing
`LensCommands` ⌘1-⌘6 citations (`:164-184` and `:164-183`) were both wider
than the actual keyboardShortcut-binding block and disagreed with each
other — tightened both to `:168-174`, the `ForEach`/`.keyboardShortcut`
block itself. No step or assertion changed, only citations. Steps
themselves not re-verified live.

**PASS (11 of 12 steps) — live VM run 2026-08-09**, `feat/unified-shell` @
`8f598239`, `script/vm_scenario_run.sh launch smoke` in the `teststrip-e2e`
Tart VM. Steps 1-5 and 7-12 run and passed; Step 6 ran in part (see below);
Step 13 is a documentation note, not an assertion, and was not driven beyond
confirming the View menu carries all six lens items.

What passed, with the evidence:
- **Step 2** — the toolbar's principal slot holds `AXGroup desc="Lens"` with
  exactly six `AXButton`s in order `Cull, Grid, Loupe, Timeline, Map, People`,
  each carrying `value="Selected"/"Not selected"`.
- **Step 3** — neither deleted control is reachable: `--role AXRadioButton
  --label Workspace` and `--contains "Library View"` both not-found.
- **Step 4** — ⌘1→`Teststrip – Loupe` (the documented Cull-default-sub-mode
  collision), ⌘2→`Grid`, ⌘3→`Loupe`, ⌘4→`Timeline`, ⌘5→`Map`, ⌘6→`People`.
  The scope line held `"All Photos, 24 photos"` across all six, and the
  switcher's `value="Selected"` tracked the pressed lens every time.
- **Step 5** — with `5 Stars` selected, the scope line's source title stayed
  `5 Stars, 4 photos` across all six presses. (Detail-only note, not a
  failure: the Cull lens renders the scope line without the `· Rating >= 5`
  filter-chip suffix the other five show. The *source title* — what this step
  asserts — is unchanged.)
- **Step 7** — hand-seeded `evaluation_failures` row surfaced an `Analysis
  Failures` sidebar row; selecting it from the Cull lens fell back to Grid
  (`AXWindow title="Teststrip – Grid"`, `Grid value="Selected"`) and the Cull
  segment rendered `AXButton desc="Cull" value="Not selected" help="Nothing
  here is cullable" enabled=false` — exact-match on the specified help text.
- **Step 8** — `find --label "Cull these"` matched; `find --label "Cull These"`
  (capital T) did **not** match anywhere on the canvas, so the driver's
  matching is genuinely case-sensitive. Pressing it entered the Cull lens with
  scope `Rating >= 5, 4 photos · ✓ 0 · ✕ 1 · 3 left` (the chip text, per
  `cullTheseSourceTitle()`), and the catalog gained
  `culling|Rating >= 5|running`.
- **Step 9** — both directions. Quit from Timeline → relaunch restored
  `Teststrip – Timeline` on the same source. Quit from Cull → relaunch came
  back on `Teststrip – Grid`, same source, per `isRestorableLens`.
- **Step 10** — with a hand-made 2-photo static set `ScopeProbeSet` selected
  (catalog total 24): Map read `"2 photos" / "0 locations · 0 geotagged"`,
  Timeline read `"2 photos across 1 day"` and `"2 photos - 1 year"`, People
  read `"0 people · 2 photos"`. All three count the set, not the catalog.
- **Step 11** — reopening the culling session from Recent Work while in Grid
  left the lens on Grid (`Grid value="Selected"`), scope
  `Rating >= 5, 4 photos · Session: 1E5E…`. The old force-the-loupe behaviour
  is gone.
- **Step 12** — behaviour correct in both directions: the Smart Collections
  "+" opens the `New Smart Collection` popover and does **not** show the
  `"Select photos, then save them as a set"` hint; the Sets "+" **does** show
  it. Verified twice, including with both headers exercised in the same
  no-selection state.

Two corrections the live run found in the then-current driving instructions
(the app was right; the assertions were stale):
- **Step 12's matchers were wrong in the version driven.** The add buttons
  were *not* reachable as
  `--role AXButton --label "New from search"` / `"New Set from Selection"` —
  both came back not-found. SwiftUI folded each section header's
  `HStack { Text; Button }` into one combined element, so what the tree
  actually vended was `AXHeading desc="Smart Collections" help="New from
  search…"` and `AXHeading desc="Sets" help="New Set from Selection…"`; the
  button's `accessibilityLabel` was discarded and its `.help` landed on the
  heading. The executable step above now uses both exact `AXHeading` labels
  and exact help strings, including the U+2026 ellipsis.
- **Step 12's "with no selection" precondition needed manufacturing on
  `--smoke` in the version driven.**
  `canSaveSelectedAssetAsManualSet` reads the current manual-selection IDs
  (`AppModel.swift:3282-3284`), which remain nonempty on an ordinary nonempty
  scope. Reaching the hint branch required a zero-result scope; that run used
  `zzzznotfound` on top of `5 Stars`. The executable step above now establishes
  that state explicitly. This reconciliation does not change the recorded
  **11 of 12** status: Step 6's positive Stacks fixture half and the visible
  tooltip gap remain open.

Not verified, and why:
- **Step 6's Stacks positive half — NOT RUN, no fixture.** The negative half
  passed (`Auto-Grouped` absent in all six lenses) and the non-Stacks sections
  were byte-identical across all six (`Library`, `Smart Collections`, `Sets`,
  `Folders`, `Selection`, plus `Imports`/`Recent Work` when populated) — but
  with `--smoke` carrying no stacks, "absent outside Cull" is trivially true
  and proves little. The positive half is **not reachable by hand-seeding**:
  `cullingStackListEntries()` needs `selectedAssetSetID` to sit inside an
  active culling session whose `inputSetIDs` carry the `work-stack-` prefix
  (`AppModel.swift:6960-6983`, `:12535-12558`), and
  `visibleSavedAssetSets` explicitly filters `work-stack-` sets out of the
  Sets section (`UnifiedSidebarPresentation.swift:116`), so no UI gesture can
  select one. The right fixture is the **`burst` seed variant** (four
  auto-groupable stacks); it was not synced to this VM and syncing it needs a
  host build, which this run was scoped out of. This half stays open.
- **Whether `.help` renders a *visible tooltip* on a `.disabled()` plain-style
  Button — NOT VERIFIED, method could not discriminate.** The disabled state
  itself is proven (`enabled=false` + exact `AXHelp`, Step 7 above, and again
  as `help="No photos to cull"` on an empty result set). For the rendered
  tooltip, the cursor was warped onto the control with mouse-moved events and
  held still for 4-8s, then the screen captured: no tooltip. But the **control
  experiment failed too** — an *enabled* lens button (`Timeline`, same `.help`
  mechanism) hovered the same way for 6s with the cursor verifiably on it
  (`NSEvent.mouseLocation` (602.5, 711) on a 1024x768 screen; cursor visible
  over "Timeline" in a `screencapture -C`) also produced no tooltip and no
  hover highlight. Synthetic hover does not drive AppKit's tooltip timer in
  this headless VM session, so the absent tooltip on the disabled button is
  not attributable to its being disabled. Needs a human-eye check or a
  different mechanism.

Environment notes: the **Sparkle updater modal fired on the first launch**
(kata #20) with `Install Update` / `Remind Me Later` / `Skip This Version`
buttons in the tree. It did **not** wedge the AX tree — the window subtree
stayed fully drivable — and was dismissed with `press --role AXButton --label
"Remind Me Later"`. Subsequent launches were suppressed for the rest of the
session with `defaults write com.teststrip.app SUEnableAutomaticChecks -bool
NO` in the VM; no further modal appeared. No idle-wedge occurred.
