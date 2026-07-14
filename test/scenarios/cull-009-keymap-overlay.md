# cull-009-keymap-overlay: ? shows the full cull keyboard cheat-sheet

**Reconciled 2026-07-13 (cull-stack-rail branch)**: this card previously
hard-asserted the overlay lists two `isMonitorOnly` rows, `"Previous Stack
(Option)"`/`"Next Stack (Option)"` with keys `"⌥←"`/`"⌥→"` — the
Option-arrow stack-nav alternate. That mechanism (and the `isMonitorOnly`
flag itself) has been **deleted**, not merely relabeled: there is no
Option-arrow branch left in the key-capture path
(`Sources/TeststripApp/CullingKeyCaptureView.swift:128-129`, an Option-held
arrow fails the `relevantModifiers.isEmpty` guard and is never decoded into
any shortcut), and `CullingCommandMenuPresentation` has no `isMonitorOnly`
case on any entry any more. The Navigation section now advertises four
plain, always-live bindings — "Previous/Next Frame in Stack" (↑/↓, within
the current stack) and "Previous/Next Stack" (←/→, across stacks) — with no
Option modifier anywhere. This revision removes the old monitor-only
assertions entirely, rewrites step 5 to the new advertised set, and adds
step 6 for the overlay's new ↑/↓ scroll behavior.

**What this covers**: as a new user of the Cull workspace, I want `?` to pop
up a complete keyboard cheat-sheet reflecting the actual, currently-live
keymap, so I don't have to memorize it from documentation. Covers item 26
(`?` toggles the overlay).

Source:
- `Sources/TeststripApp/AppModel.swift:5887-5889` — `.showKeyMap` toggles
  `isKeyMapOverlayVisible` (`?`, keyed via the exact-case `.character("?")`
  match at `:252-253` in the static key-based mapping, and via the shifted
  `"/"` branch at `CullingKeyCaptureView.swift:141-143` in the live event
  monitor, so plain `?` fires it either way).
- `Sources/TeststripApp/LibraryGridView.swift:221-229` — the overlay is shown
  `if model.isKeyMapOverlayVisible`, and `.onExitCommand` (Esc) also sets it
  false — so **Esc dismisses in addition to** a repeated `?` (the doc
  comment at `LibraryGridView.swift:9236` says "Esc or a repeated `?`
  dismisses it"; a second `?` toggles `isKeyMapOverlayVisible` back to
  false, same boolean). **Line numbers re-verified this pass**: the file has
  grown since this card was first written and `KeyMapOverlayView` has moved
  from its previously-cited `8564-8615` to its current location below —
  don't trust old line citations without re-grepping first.
- `Sources/TeststripApp/LibraryGridView.swift:9234-9296` — `KeyMapOverlayView`:
  heading `"Keyboard Shortcuts"` (`:9246`), a dismiss button (accessibility
  label `"Dismiss key map"`, `:9256`), and a `ScrollViewReader` wrapping
  `ForEach(CullingCommandMenuPresentation.sections)` (`:9259-9287`)
  rendering each section's uppercased title (`:9264`) and each item's
  `title` + `key.displayText` as plain `Text` in an `HStack` (`:9268-9274`).
  `scrollToSectionIndex` (`:9240`, bound to `model.keyMapOverlayScrollIndex`
  at the call site, `LibraryGridView.swift:224`) drives
  `proxy.scrollTo(...)` on change (`:9281-9286`) — this is what step 6
  below exercises.
- `Sources/TeststripApp/AppModel.swift:509-517` —
  `CullingCommandMenuPresentation.sections`, the single source of truth for
  what the overlay lists. Real section titles: `"Navigation"`, `"Ratings"`,
  `"Color Labels"`, `"Flags"`, `"Loupe"`, `"Filter"`, `"Compare"`. The
  **Navigation** section (`:511-516`) now lists exactly: `"Previous Frame in
  Stack"` (key `↑`), `"Next Frame in Stack"` (key `↓`), `"Previous Stack"`
  (key `←`), `"Next Stack"` (key `→`), `"Promote Frame & Reject Siblings"`
  (key `Return`) — five plain items, none flagged `isMonitorOnly` (the field
  and both Option-arrow rows are gone from the source entirely, not merely
  hidden).
  **Note**: `G`/`C`/`B` (subview switches, item 25) are **not** listed in
  `CullingCommandMenuPresentation` at all — they have no section/menu entry.
  Don't assert their presence in the overlay; that would be a false
  assertion this draft caught by reading the actual section list.

## Pre-state
```bash
./script/build_and_run.sh --smoke
script/ax_drive.sh wait-vended Teststrip
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. ⌘1 for Cull; select a frame and open the loupe (Return). On this FIRST
   entry to the Cull workspace in the session, assert the one-time
   discoverability hint appears via the decision toast:
   `script/ax_drive.sh find --contains "Press ? for keyboard shortcuts"`
   (within its 2s window). Leave Cull (⌘2) and return (⌘1): assert the hint
   does NOT reappear — it is once per session (persona-8 defect: the ?
   overlay was undiscoverable).
2. Press `?`. Assert the overlay appears:
   `script/ax_drive.sh wait --role AXStaticText --contains "Keyboard Shortcuts"`.
3. Assert at least three real section headings render (quoting the actual
   values from `CullingCommandMenuPresentation`, not guessed ones):
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "NAVIGATION"
   script/ax_drive.sh find --role AXStaticText --contains "FLAGS"
   script/ax_drive.sh find --role AXStaticText --contains "LOUPE"
   ```
   (section titles are rendered `.uppercased()` at
   `LibraryGridView.swift:9264`, so match the uppercased form.)
4. Assert at least two real item rows render by title:
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "Promote Frame & Reject Siblings"
   script/ax_drive.sh find --role AXStaticText --contains "Cycle EXIF Overlay"
   ```
5. **Reconciled**: assert the Navigation section's current, always-live
   rows (no monitor-only rows exist any more — see header note):
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "Previous Frame in Stack"
   script/ax_drive.sh find --role AXStaticText --contains "Next Frame in Stack"
   script/ax_drive.sh find --role AXStaticText --contains "Previous Stack"
   script/ax_drive.sh find --role AXStaticText --contains "Next Stack"
   ```
   and that neither retired string is present any more (the actual
   regression this reconciliation targets — a stale menu presentation that
   still shows the deleted rows):
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "(Option)"   # must NOT match
   script/ax_drive.sh find --role AXStaticText --contains "⌥"          # must NOT match
   ```
6. **Overlay scroll is now ↑/↓** (new this branch): while the overlay is
   visible, `applyCullingShortcut` intercepts `.previousCandidateInStack`/
   `.nextCandidateInStack` (↑/↓) and routes them to `scrollKeyMapOverlay`
   instead of moving the underlying selection
   (`Sources/TeststripApp/AppModel.swift:5832-5843`; PgUp/PgDn
   (`.keyMapPageUp`/`.keyMapPageDown`) scroll the same way while the overlay
   is visible, by 3 sections per press instead of 1 —
   `KeyMapOverlayScrolling.nextIndex`, `:566-580` — but are a genuine no-op
   outside overlay mode, `:5906-5907`; this step only drives ↑/↓, per the
   task). Record the current selected asset id, then press `Down`
   repeatedly (the section list has 7 sections, so up to 6 presses)
   until the last section's heading is visible:
   `script/ax_drive.sh find --role AXStaticText --contains "COMPARE"`.
   Assert two things: the previously-recorded asset selection is unchanged
   (proving ↓ was consumed by the overlay, not passed through to
   `.nextCandidateInStack`'s normal effect), and the "COMPARE" heading —
   off-screen at the fixed `360×420` frame's default scroll position per
   Sharp edges — is now AX-findable. Press `Up` the same number of times;
   assert scrolling back reaches "NAVIGATION" again.
7. Press Esc. Assert the overlay is gone:
   `script/ax_drive.sh find --role AXStaticText --contains "Keyboard Shortcuts"`
   should now fail to match, and the loupe's normal chrome (e.g. pick/reject
   pills) should be reachable again (a subsequent keystroke like `p` should
   pick the frame, proving focus returned to the culling surface rather than
   being stuck on the dismissed overlay).
8. Re-open with `?`, then press `?` again (not Esc). Assert this also
   dismisses the overlay (the "repeated `?` dismisses it" claim from the
   doc comment) — same assertion as step 7.

## Expected
- Step 2: overlay heading appears within a couple seconds of the keypress.
  **Fails if** it never appears — `.showKeyMap`/`isKeyMapOverlayVisible`
  wiring broken.
- Step 3/4: the quoted section and item titles render verbatim (case-
  sensitive per the actual uppercasing/title-casing in source). **Fails if**
  any of these specific strings are absent — don't substitute a looser
  substring that would pass even if the section list changed.
- Step 5: the four reconciled Navigation rows render, and neither
  `"(Option)"` nor `"⌥"` appears anywhere in the overlay. **Fails if** a row
  is missing (regression in the advertised keymap) or if either retired
  string still renders (stale menu data — the exact defect this
  reconciliation exists to catch).
- Step 6: ↓ scrolls the overlay to reveal "COMPARE" without moving the
  underlying selection; ↑ scrolls back to "NAVIGATION". **Fails if** the
  selection changes while the overlay is open (arrows leaking through to
  `.nextCandidateInStack`'s normal effect instead of being intercepted), or
  if the scroll never reaches the last section.
- Step 7: overlay fully dismissed via Esc, and keyboard focus/routing
  recovers (proven by a working `p` keystroke afterward).
- Step 8: overlay fully dismissed via a second `?` press, independent of
  Esc.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **G/C/B (item 25's subview-switch shortcuts) are absent from the overlay
  by design** (not a bug this card should report) — `CullingCommandMenuPresentation.sections`
  has no entries for `.showCullGrid`/`.showCompare`/`.showABCompare`. Don't
  confuse this with the section *titled* `"Compare"` that does exist
  (`AppModel.swift:548-551`) — that section lists `,`/`.` for
  `.keepAOverB`/`.keepBOverA` (A/B Compare's keyboard verdicts), a
  completely different pair of shortcuts from the `.showCompare` subview
  switch this bullet is about. If a future change is expected to add
  G/C/B, that's a product decision for Jesse, not something to assert
  against here.
- The overlay's frame is fixed at `360×420` with a `ScrollView`
  (`LibraryGridView.swift:9259-9292`); step 6 now gives a concrete,
  keyboard-driven way to reach a late section (↓ to the last section,
  `"Compare"`) instead of hoping the default scroll position happens to
  show it — prefer that over guessing at mouse-scroll behavior in `ax_drive.sh`,
  which has no scroll-wheel verb.
- This card only drives from the loupe (`CullingKeyCaptureGate.isActive`
  requires `workspace == .cull && selectedView != .cullGrid` — see
  `cull-008-subview-keys-gcb.md`); `?` is not wired while `.cullGrid` is
  showing (GridKeyCaptureView has no `?` binding), so don't try to trigger
  this overlay from the grid subview.

## Run status
NOT RUN AGAINST THE RECONCILED CONTENT — reconciled 2026-07-13 to the
branch's remapped Navigation section (no `isMonitorOnly`/Option-arrow rows;
↑/↓ scroll the overlay while it's visible) and source-cited against the
current working tree. The LEDGER's prior "Verified" status for this card
covers the *old* overlay content (with the now-deleted Option-arrow rows)
and must not be read as covering this revision; needs a fresh
human-present/VM execution per `test/scenarios/README.md`.
