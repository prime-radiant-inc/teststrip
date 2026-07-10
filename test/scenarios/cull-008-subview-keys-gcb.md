# cull-008-subview-keys-gcb: G/C/B switch Cull subviews; grid Return/G/Esc jump to and from the loupe

**What this covers**: as a photographer switching between the three Cull
subviews — Grid, Compare, A/B — while working a shoot, I want single
keystrokes (`G`/`C`/`B`) to jump straight there from the loupe, and I want
Return/Space in the grid to drop into the loupe on the focused tile with
`G`/Esc taking me back out. Covers item 25 (loupe-context G/C/B subview
switch) and item 30 (grid Return/Space → loupe, G/Esc → back to grid),
**including resolving the G-key dual-meaning noted in the source digest**.

Source — **the G-key ambiguity is real but is two separate, non-conflicting
key monitors, not one context-sensitive branch**:
- `Sources/TeststripApp/AppModel.swift:5449-5456` — while the **culling
  shortcut monitor** is active (loupe/culling context; `CullingShortcut.showCullGrid`,
  keyed `"g"` at `AppModel.swift:258`), pressing `g` sets
  `selectedView = .cullGrid` — loupe → grid.
- `Sources/TeststripApp/GridKeyCaptureView.swift:37-58` — while
  `GridKeyCaptureNSView.mode == .cullGrid` (the **grid key-capture view**,
  active only when the cull grid subview itself has focus), `command(for:)`
  intercepts `g` *before* the plain `GridKeyCommand(input:)` path and returns
  `.switchCullSubView(.loupe)` — grid → loupe. `Escape` maps to the same
  `.switchCullSubView(.loupe)` in this branch (`:46-47`), so **G and Esc are
  synonyms while in the grid subview**. `c`/`b` in this same branch jump
  straight to `.compare`/`.abCompare` (`:51-52`), skipping the loupe.
- **Resolution — confirmed by the explicit gate, not just by inference**:
  `CullingKeyCaptureGate.isActive(workspace:selectedView:)`
  (`Sources/TeststripApp/CullingKeyCaptureView.swift:11-15`) returns
  `workspace == .cull && selectedView != .cullGrid`, and
  `LibraryGridView.swift:180-202` wires exactly one `CullingKeyCaptureView`
  (gated by `isActive`) and one always-installed `GridKeyCaptureView` (whose
  own `.cullSubViewSwitch` branch only matches when `mode == .cullGrid`,
  `GridKeyCaptureView.swift:222`) as sibling overlays on the same surface.
  The two `g` bindings are therefore mutually exclusive by construction:
  `CullingKeyCaptureNSView`'s local key monitor stays installed while its
  `NSView` is in the window, but `handleLocalKeyDown` guards on `isActive`
  first (`CullingKeyCaptureView.swift:74`) and returns the event unhandled
  when false — so while `.cullGrid` is showing, `CullingKeyCaptureView`'s `g`
  binding is a no-op at the handler level, and only `GridKeyCaptureView`'s
  `g` (which has no such gate, but only matches when `mode == .cullGrid`,
  `GridKeyCaptureView.swift:222`) can fire. Both monitors register as
  `NSEvent.addLocalMonitorForEvents` observers regardless of `isActive` — the
  gating happens inside the handler, not by uninstalling the monitor — so
  there is no double-fire risk, but it does mean **both handlers run per
  keystroke and one no-ops via a state check**, not that only one is ever
  present in the event-monitor list. Worth confirming during the live run
  that this ordering (`CullingKeyCaptureNSView` checks `isActive` before
  doing anything) really does prevent both from matching, since local
  monitors run in installation order and neither explicitly waits for the
  other to decline first. `g` is "go to grid" from everywhere else in the
  Cull workspace and "go back to the loupe" from the grid itself — a real
  toggle, not an unresolved ambiguity, but the multi-monitor mechanics are
  subtle enough to spot-check live.
- `Sources/TeststripApp/GridKeyCaptureView.swift:74-77` — plain grid mode
  (not `.cullGrid`): Return/Space → `.openLoupe`; Escape → `.returnToGrid`.
- `Sources/TeststripApp/AppModel.swift:5309-5334` (`applyGridKeyCommand`) —
  `.openLoupe` in `.cullGrid` selects the asset and sets `selectedView =
  .loupe` (`:5321-5325`); in plain `.grid` it calls
  `openAssetInLibraryLoupe` instead (`:5326-5328`, Library's separate loupe —
  out of scope here, see `library-loupe-no-cull-chrome.md`).

## Pre-state
```bash
./script/build_and_run.sh --smoke
script/ax_drive.sh wait-vended Teststrip
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. ⌘1 for Cull; select any frame and press Return to open the loupe
   (`selectedView == .loupe`).
2. Press `G`. Assert the cull grid subview is now active — look for an AX
   element unique to the grid (e.g. `script/ax_drive.sh wait --role
   AXScrollArea --contains` a grid-tile filename, or the subview's container
   identifier if one exists; confirm the concrete AX marker by inspecting
   the live tree, since no dedicated "subview active" AX label was found by
   reading source alone).
3. Press `C`. This requires 2+ frames in the current compare/candidate set
   to be meaningful (see items 55-62's prerequisites); keep this step simple
   and just assert the subview switched (`selectedView == .compare`) even
   under default single-selection — assert via whatever compare-specific AX
   chrome renders (e.g. the `"A/B"` label only appears in A/B, not Compare,
   so look for Compare-specific chrome instead). If Compare renders nothing
   distinguishing with <2 frames, note that as a fixture gap here rather
   than forcing a false-positive assertion.
4. Press `B`. Assert A/B compare is active: `script/ax_drive.sh find
   --contains "A/B"` (the header label at `LibraryGridView.swift:5851`).
5. From A/B, press `G` again to return to the grid subview. Per
   `CullingKeyCaptureGate.isActive` (`workspace == .cull && selectedView !=
   .cullGrid`), the culling-shortcut monitor is active for `.abCompare` too
   (it's gated only against `.cullGrid`, not scoped to `.loupe` alone), so
   this should behave the same as step 7 below.
6. In the cull grid subview, press Return (or Space) on a tile. Assert the
   loupe opens on that exact asset:
   ```bash
   sqlite3 "$DB" "SELECT originalUrl FROM assets WHERE id = '<tile-asset-id>';"
   ```
   compare the loupe's filename/label to this on-disk id.
7. From the loupe, press `G` to return to the grid subview again — confirms
   the round trip.
8. From the grid subview, press Escape. Assert this behaves identically to
   step 7's `G` press — same `.switchCullSubView(.loupe)` target
   (`GridKeyCaptureView.swift:46-47`).

## Expected
- Step 2: `selectedView == .cullGrid`, loupe chrome (pick/reject pills) gone,
  grid tiles visible.
- Step 3/4: `selectedView` becomes `.compare`/`.abCompare` respectively;
  step 4's A/B header (`"A/B"` label) is present.
- Step 5: `selectedView` returns to `.cullGrid`. **Fails if** `G` from A/B
  does nothing — that would contradict `CullingKeyCaptureGate.isActive`'s
  stated scope (`workspace == .cull && selectedView != .cullGrid`, which
  includes `.abCompare`) and is worth flagging as a real bug, not softened.
- Step 6: the loupe opens on the exact tile that was pressed, not an
  arbitrary/first asset. **Fails if** the wrong asset opens, or if Return
  does nothing in `.cullGrid` mode.
- Step 7/8: both `G` and Esc return `.cullGrid → .loupe`, and their observed
  effect is identical. **Fails if** they diverge (e.g. Esc exits to
  `.grid`/plain library grid instead of the loupe) — that would falsify the
  "synonyms in `.cullGrid`" reading of `GridKeyCaptureView.swift:37-58` above.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **The G-key "ambiguity" is resolved by code-reading, not by a live run**:
  two independent key-capture layers (`CullingShortcut`'s monitor and
  `GridKeyCaptureNSView`) each bind `g` to a different one-way transition,
  and by construction they're never both live for the same view. This still
  needs a live run to confirm the *practical* claim — that AppKit's
  first-responder routing actually keeps only one of the two monitors "hot"
  at a time in the assembled app, since both could in principle be
  `NSEvent.addLocalMonitorForEvents` observers that both see every keydown
  (`GridKeyCaptureNSView.installLocalKeyMonitor`,
  `GridKeyCaptureView.swift:232-237`) — local monitors do **not** consume
  events by default, they only stop propagation if the handler returns
  `nil` (`handleLocalKeyDown` returns `nil` only when it matches a command,
  `:216-217`). If both monitors are installed simultaneously in `.cullGrid`
  context, whichever registers `g` first could double-fire — a real
  candidate bug that only a live keystroke trace would catch. Flag this to
  Jesse as a verification target during the human-present run, not assumed
  safe from source alone.
- Step 5's claim (culling-shortcut monitor active from `.abCompare`) is
  written as an open question in the Steps above deliberately — this draft
  did not locate and read the monitor's install/scope code to confirm which
  `selectedView` values it's live for. Resolve during the run.
- Step 3 (Compare with <2 frames) may render no distinguishing AX chrome;
  if so this card's Compare-subview assertion is the weakest of the four and
  should be strengthened once a real multi-candidate fixture exists.

## Run status
UNRUN — needs human-present execution per test/scenarios/README.md. The
G-key monitor-overlap question in Sharp edges is an open verification item,
not resolved by this draft.
