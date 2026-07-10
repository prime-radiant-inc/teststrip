# inspect-001-toggle-tabs: ⌘I toggle, tab switching, and the elementsByTab anti-orphan mapping

**What this covers**: the inspector's entry/exit chrome — ⌘I opening the
panel (and its Cull-workspace special case of switching to Library first),
switching among the Info/Describe/AI tabs by click and by ⌥⌘1-3, the
`InspectorTabPresentation.elementsByTab` mapping actually rendering the
elements it predicts per tab, the panel's fixed width, and the "No selection"
empty state.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
SRC=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1;")
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘3 (Cull) if not already
   there (Cull is the default workspace on a fresh launch).
2. Press ⌘I. Assert the app switches to Library (⌘2) **and** the inspector
   panel becomes visible — Cull has no inspector column, so ⌘I from Cull must
   both switch workspace and show the panel in one gesture.
3. Press ⌘I again. Assert the inspector panel closes (still in Library).
4. Press ⌘I a third time (now in Library, inspector hidden). Assert it opens
   again, still in Library this time (no further workspace switch).
5. **No-selection empty state**: with no asset selected, assert the inspector
   body reads "No selection" (`ax_drive.sh find --role AXStaticText --contains
   "No selection"`).
6. Select `$SRC`'s grid cell. Assert "No selection" is gone and the segmented
   tab picker (Info/Describe/AI) is present.
7. **Tab switching by click.** Click the "Describe" segment
   (`ax_drive.sh press --role AXRadioButton --label "Describe"` or the
   picker's actual AX role — confirm via dump if AXRadioButton doesn't match).
   Assert Describe-tab content renders: the rating/flag/label edit buttons and
   the Keywords field (`elementsByTab[.describe]` includes `.ratingEditButtons`,
   `.flagEditButtons`, `.labelEditButtons`, `.keywordField` per
   `Sources/TeststripApp/InspectorView.swift:523-535`).
8. Click back to "Info". Assert Info-tab content renders: the read-only
   rating/flag/label summary text and (if present) EXIF rows —
   `elementsByTab[.info]` (`InspectorView.swift:512-522`) — and that the
   Describe-only edit buttons are gone (Info shows `.ratingDisplay`, not
   `.ratingEditButtons`).
9. Click "AI". Assert the AI-tab content area renders (verdict groups if
   evaluation signals exist for `$SRC`, else an empty/quiet state) —
   `elementsByTab[.ai]` = `.verdictGroups`, `.technicalDetailsDisclosure`,
   `.providerFailureRetry` (`InspectorView.swift:536-540`).
10. **⌥⌘1-3 shortcuts.** With focus elsewhere in the window (click the grid),
    press ⌥⌘1. Assert the tab picker now shows Info selected. Press ⌥⌘2:
    Describe selected. Press ⌥⌘3: AI selected.
11. **Fixed width.** Capture the inspector panel's frame
    (`ax_drive.sh find --role AXGroup ...` or read `kAXSizeAttribute` on the
    panel) at Info, Describe, and AI tabs. Assert width is constant at 286pt
    (`InspectorPreviewLayout.columnWidth` = 258 + 2*14, `InspectorView.swift:5-8`)
    regardless of tab or content length.
12. **Cull tab-select-without-visibility.** Press ⌘I to close the inspector,
    then ⌘3 to return to Cull. With the inspector hidden and in Cull, press
    ⌥⌘2 (Describe). Assert the tab *selection* changes (verify via a
    subsequent ⌘I → Describe already selected) but the inspector panel does
    **not** become visible in Cull — `WorkspaceChromePolicy.showsInspector(.cull)`
    gates visibility (`AppModel.swift:4031-4037`, `selectInspectorTab`).

## Expected
- Step 2: workspace becomes Library and inspector visible. **Fails if** ⌘I
  from Cull doesn't switch workspace, or switches but leaves the panel hidden.
- Step 3-4: toggling is a pure show/hide once already in a workspace with an
  inspector. **Fails if** repeated ⌘I mutates the workspace again.
- Step 5: "No selection" text visible with no asset selected. **Fails if**
  stale content from a prior selection lingers.
- Step 7-9: each tab renders only its own `elementsByTab` elements — Describe
  shows edit controls, Info shows read-only summary + EXIF, AI shows
  verdicts/disclosure. **Fails if** a tab renders another tab's elements (an
  orphan-mapping regression) or omits one of its own.
- Step 10: ⌥⌘1/2/3 select Info/Describe/AI respectively regardless of prior
  focus. **Fails if** a shortcut is inert or selects the wrong tab.
- Step 11: width is 286pt on all three tabs. **Fails if** it varies with
  content (e.g. Describe's longer form pushes the panel wider).
- Step 12: tab selection persists across the visibility gate but Cull itself
  never shows the panel. **Fails if** ⌥⌘2 in Cull pops the inspector visible
  anyway (violates the "Cull has no inspector column" design).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The segmented Picker's AX role for SwiftUI `.pickerStyle(.segmented)` may
  present as `AXRadioGroup`/`AXRadioButton` rather than a generic button —
  dump the tree once live to get the exact role/label combination before
  relying on step 7's exact invocation.
- Step 12 is inherently a two-hop assertion (select tab while hidden, then
  open and check) since there's no direct AX property exposing "selected tab
  while panel is hidden" — that's intentional, it's testing the same state
  the model holds (`model.inspectorTab`) rather than a separate surface.

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Wiring confirmed
statically: `Sources/TeststripApp/InspectorView.swift:452-474` (`InspectorTab`
enum, `.keyEquivalent` "1"/"2"/"3"), `:478-542` (`InspectorElement` cases and
`InspectorTabPresentation.elementsByTab`), `:544-601` (`InspectorView.body`,
segmented picker, "No selection" state, fixed `columnWidth`),
`Sources/TeststripApp/AppModel.swift:4020-4037` (`toggleInspector`,
`selectInspectorTab`, the Cull-switches-to-Library special case),
`Sources/TeststripApp/main.swift:538-556` (`InspectorCommands`: ⌘I and
⌥⌘1-3 menu bindings). Needs a human-present re-run. All SQL in this card was
run headlessly against a seeded --smoke catalog on 2026-07-10 (schema per
Sources/TeststripCore/Catalog/CatalogMigrations.swift).
