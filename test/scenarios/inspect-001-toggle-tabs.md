# inspect-001-toggle-tabs: ⌘I toggle, ⌥⌘1-3 scroll-to-section, and the elementsByTab anti-orphan mapping

**Reconciled 2026-07-13 (feat/unified-single-view branch, Task 6/9)**: this
card previously described a **segmented Picker** switching among three
mutually-exclusive Info/Describe/AI tabs (`AXRadioButton` hunting, ⌥⌘1-3
"selecting" a tab, `model.inspectorTab` as the one-at-a-time selection
state), plus a Cull-specific special case where ⌘I switched the workspace
to Library before showing the panel (Cull had no inspector column at all).
Both are gone. The inspector is now **one continuous vertical scroll** of
four **stacked** sections — Info, Describe, AI, and a new **People**
section — all simultaneously present in a plain `VStack`
(`Sources/TeststripApp/InspectorView.swift:557`, not lazy, so nothing here
depends on scroll position for AX presence). ⌥⌘1-3
(`Sources/TeststripApp/main.swift:590-611`, `InspectorCommands`) now
**scroll** the `ScrollViewReader` to a section's anchor
(`InspectorView.swift:586-590`) rather than switching a picker-bound
selection; there is no more "selected tab" state to query. And
`LensChromePolicy.showsInspector` (renamed from `WorkspaceChromePolicy` by
the later unified-shell push; same unconditional `true`,
`LibraryGridView.swift:8291-8293`) — Cull now shows the inspector directly,
so `toggleInspector()` (`AppModel.swift:4766-4768`) is a bare
`isInspectorVisible.toggle()` with no lens-switching side effect at all. This revision rewrites the tab-switching steps into section-scroll
steps, drops the segmented-Picker- and Cull-tab-select-without-visibility-
specific assertions (items 7-9 and 12 of the prior draft), and keeps the
still-valid legs: ⌘I open/close, the no-selection empty state, and the
fixed panel width. Deep per-face People-section coverage (naming, rejecting,
removing, box overlay) is **not** duplicated here — that's
`inspect-010-photo-faces.md`'s job; this card stays focused on the
inspector's own entry/exit chrome and section-scroll mechanism.

**What this covers**: the inspector's entry/exit chrome — ⌘I toggling the
panel in every lens including Cull (no more auto-switch-to-Library),
⌥⌘1-3 scrolling to the Info/Describe/AI sections (`InspectorTab.keyEquivalent`,
`InspectorView.swift:470-476`: "1"/"2"/"3"), the
`InspectorTabPresentation.elementsByTab` mapping still correctly assigning
every element to exactly one section (an anti-orphan/anti-duplicate
concern, now about *content ownership* rather than *tab exclusivity* since
all sections render at once), the panel's fixed width, and the
"No selection" empty state.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
SRC=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1;")
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘1 to select the Cull
   lens (`LibraryLens.keyEquivalent`, `Sources/TeststripApp/LibraryLens.swift:
   46-55` — ⌘1 Cull/⌘2 Grid/⌘3 Loupe/⌘4 Timeline/⌘5 Map/⌘6 People). **Do not
   assume Cull is already active on a fresh launch**: `AppModel.load(catalog:...)`
   constructs the model with `selectedView: .grid` unconditionally
   (`AppModel.swift:4431`), and `restoreSessionStateIfAvailable()` only
   changes that if a prior session's `SessionRestoreState` exists — on a
   genuinely fresh `--smoke`/`--isolated` launch (no saved state), the
   lens actually active at first paint is **Grid**, not Cull. Press ⌘1
   explicitly rather than trusting the launch default either way.
2. Press ⌘I. Assert the inspector panel becomes visible **while staying in
   Cull** — assert a Cull-only control (e.g. the stack rail) is still
   present alongside the now-visible inspector column. **Fails if** the
   lens changes at all; the old Library-switch special case must not
   resurface.
3. Press ⌘I again. Assert the inspector panel closes (still in Cull).
4. Press ⌘I a third time. Assert it opens again, still in Cull.
5. **No-selection empty state**: press ⌘2 (Library) with nothing selected;
   assert the inspector body reads "No selection" (`ax_drive.sh find
   --role AXStaticText --contains "No selection"`).
6. Select `$SRC`'s grid cell. Assert "No selection" is gone and all four
   section headers are present as plain `AXStaticText` — "Info",
   "Describe", "AI", "People" (`ax_drive.sh find --role AXStaticText
   --label "<title>"` for each) — **simultaneously**, without needing to
   scroll first (the `VStack` at `InspectorView.swift:557` is not lazy).
7. **Content ownership, not tab exclusivity.** With one asset selected,
   assert elements from *all three* `InspectorTabPresentation.elementsByTab`
   groups (`InspectorView.swift:513-544`) are present in the AX tree at
   once: Info's read-only rating/flag/label summary (`.ratingDisplay`) and
   (if present) EXIF rows; Describe's edit controls (`.ratingEditButtons`,
   `.flagEditButtons`, `.labelEditButtons`, keywords field); AI's verdict
   groups/technical-details disclosure if evaluation signals exist. This
   replaces the old "only the selected tab's elements render" check — the
   new anti-orphan concern is that each element still appears under
   exactly one section header and none is missing or duplicated, not that
   other sections' elements are hidden (there are no hidden sections
   anymore).
8. **⌥⌘1-3 scroll-to-section.** There is no AX-exposed "current scroll
   position" property, so fall back to a screenshot comparison (same
   fallback `cull-006-zoom-and-face-zoom.md` uses for the loupe's
   untracked zoom state): capture a screenshot, press ⌥⌘3 (scroll to AI),
   capture another, and confirm the AI section's content (verdict groups /
   empty-state text) is now visible near the top of the inspector column
   while Info's preview/identity header has scrolled out of view. Press
   ⌥⌘1 (scroll to Info); capture again and confirm Info's content is back
   near the top. Press ⌥⌘2 (Describe); confirm Describe's keyword field is
   now near the top.
9. **⌥⌘1-3 opens the inspector if it's currently closed, in every lens
   including Cull.** Press ⌘I to close the inspector, then ⌘1 to
   return to Cull. With the inspector hidden and in Cull, press ⌥⌘2.
   Assert the inspector becomes visible (still in Cull) and scrolled to
   Describe — `scrollInspector(to:)` (`AppModel.swift:4773-4779`) sets
   `isInspectorVisible = true` whenever `LensChromePolicy.showsInspector`
   allows it, which is now every lens. This is the direct replacement
   for the prior draft's item 12 ("tab-select-without-visibility in Cull"),
   which no longer applies now that Cull always shows the inspector.
10. **Fixed width.** Capture the inspector panel's frame
    (`ax_drive.sh find --role AXGroup ...` or read `kAXSizeAttribute` on
    the panel) after each of the three ⌥⌘n scrolls in step 8. Assert width
    is constant at 286pt (`InspectorPreviewLayout.columnWidth` = 258 +
    2*14, `InspectorView.swift:5-8`) regardless of scroll position or
    section content length — this constant and its derivation are
    unaffected by the tabs-to-stack change.

## Expected
- Step 2: inspector becomes visible, lens stays Cull. **Fails if** any
  lens switch happens (would mean the removed special case came back)
  or the panel stays hidden.
- Step 3-4: toggling is a pure show/hide. **Fails if** repeated ⌘I mutates
  the lens or scroll position.
- Step 5: "No selection" text visible with no asset selected. **Fails if**
  stale content from a prior selection lingers.
- Step 6: all four headers present without scrolling. **Fails if** any is
  missing, duplicated, or requires a scroll to appear (would mean the
  stack became lazy).
- Step 7: every element from all three tabs' `elementsByTab` lists is
  simultaneously present. **Fails if** any element is missing (an orphan)
  or an element the mapping assigns to one section actually renders under
  another (a mis-assignment — still a real regression class even without
  tab exclusivity to hide it).
- Step 8: each ⌥⌘n scrolls the corresponding section's content toward the
  top of the visible area. **Fails if** the screenshots are visually
  identical across presses (scrolling isn't wired) or the wrong section
  comes to the top.
- Step 9: ⌥⌘2 both opens the inspector and scrolls to Describe, from a
  cold (hidden) start, in Cull. **Fails if** it scrolls a hidden/invisible
  panel without also presenting it, or only works in Library/People.
- Step 10: width is 286pt regardless of scroll position. **Fails if** it
  varies with which section is scrolled to or its content length.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **No AX-exposed scroll position.** Unlike the old segmented Picker (whose
  selected segment was a directly queryable AX property), a `ScrollView`'s
  scroll offset has no equivalent — step 8's fallback to screenshot
  comparison is the honest limit, not a shortcut; don't invent an AX
  property that doesn't exist.
- **People has no ⌥⌘-shortcut and no `InspectorTab` case**
  (`InspectorView.swift:455-459`: only `.info`/`.describe`/`.ai`) — it's
  reachable only by scrolling or by ⌘I landing wherever the scroll
  currently sits. Don't expect an ⌥⌘4 for it.
- This card intentionally stays shallow on the People section itself (just
  confirming its header renders as part of step 6/7's "all four sections
  present" check) — its face-list/naming/reject/remove/box-overlay
  behavior is `inspect-010-photo-faces.md`'s full scope, to avoid
  duplicating that coverage here.

## Run status
NOT RUN AGAINST THE RECONCILED CONTENT — reconciled 2026-07-13 to the
stacked-sections inspector (segmented-Picker tab switching removed, ⌥⌘1-3
now scroll-to-section, Cull's ⌘I-switches-to-Library special case removed,
People section added) and source-cited against the current working tree.
The LEDGER's prior "Tested-Pass" status for this card ("PASS; width/no-
selection legs unmeasurable in VM") covers the *old* tabbed-Picker UX only
and must not be read as covering this revision; needs a fresh
human-present/VM execution per `test/scenarios/README.md`.

**Reconciled 2026-08-09 (Task 13, unified-shell scenario-card sweep)**:
⌥⌘1/⌥⌘2/⌥⌘3 themselves are unchanged by the unified-shell push —
`InspectorCommands`/`InspectorTab.keyEquivalent` (`main.swift:586-607`,
`InspectorView.swift:470-476`) still bind them to the Info/Describe/AI
scroll-to-section actions this card's 2026-07-13 revision already
documents. What changed is what now sits directly *above* them: ⌘1-⌘3 were
the deleted `Workspace` shortcuts (Cull/Library/People) and are now three of
the six `LibraryLens` shortcuts (Cull/Grid/Loupe) — the modifier is the only
thing keeping the two sets from colliding, unchanged in kind from before
this push, just a different enum underneath ⌘1-⌘3. This card's own
2026-07-13 preamble (documenting the tabs-to-stack rewrite) is the
precedent this note follows: state what changed, state what didn't, and
don't re-litigate the parts that still hold. Also corrected Step 1, which
cited the deleted `Workspace.keyEquivalent` and wrongly asserted Cull is
the default lens on a fresh launch — `AppModel.load(catalog:...)`
constructs with `selectedView: .grid` unconditionally
(`AppModel.swift:4431`); Grid, not Cull, is what a truly fresh
`--smoke`/`--isolated` launch shows before this card's Step 1 explicitly
presses ⌘1. Supersedes prior status: the 2026-07-13 revision's Step 1 asserted Cull as
the launch default without citing `AppModel.load`'s actual constructor call
— reading it now (this pass, on this branch) shows `selectedView: .grid`
unconditionally; whether that was already true in 2026-07-13's tree wasn't
re-derived here, only that the claim doesn't hold today, which is enough to
correct it. Everything else in the 2026-07-13 reconciliation (the stacked-sections
inspector, ⌥⌘1-3 as scroll-not-select, the Cull-shows-inspector-directly
fix) is unaffected by this push and remains valid evidence pending a fresh
run. Needs a fresh VM run.
