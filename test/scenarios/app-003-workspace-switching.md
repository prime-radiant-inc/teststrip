# app-003-workspace-switching: superseded by the lens shell

**Superseded by `app-019-lens-shell.md`** (unified shell, 2026-08-07). The
two-workspace model this card tested — `Workspace` (Cull/Library/People),
its toolbar `Picker("Workspace", ...)`, and the shared ⌘1/⌘2/⌘3 shortcuts
routed through `AppModel.selectWorkspace(_:)` — no longer exists in any
form; `Workspace` has had two cases since People became a Library sub-view,
and this push deleted it outright. ⌘1–⌘6 now select one of six lenses
(`LibraryLens`: Cull/Grid/Loupe/Timeline/Map/People) over a single sidebar
and source, via the toolbar `lensSwitcher` (`Sources/TeststripApp/LibraryGridView.swift:531`). See `app-019-lens-shell.md` for the current
switcher/keyboard/session-restore contract this card used to own.

This file is kept (rather than deleted) so its LEDGER row and inbound
cross-references stay resolvable.

**Known UX quirk this card originally flagged (persona-8), carried forward**:
the switcher's Cull segment is labelled "Cull", but pressing ⌘1 on a lens not
yet visited this session lands on a view whose window subtitle reads
"Loupe" — `LibraryLens.defaultViewMode` for `.cull` is `.loupe`
(`Sources/TeststripApp/LibraryLens.swift:47-55`), and that subtitle is
identical to the separate Loupe lens's (`.libraryLoupe`) subtitle. The
subtitle alone cannot disambiguate "Cull, currently in its loupe sub-mode"
from "the Loupe lens" — `app-019-lens-shell.md`'s corrections section and its
Step 4 are where this quirk is now tracked and asserted live (the lens
switcher's own `.accessibilityValue("Selected"/"Not selected")` per button is
the disambiguator a driver should read instead of the subtitle).

## Run status
**Reconciled 2026-08-09 (Task 13, unified-shell scenario-card sweep)**:
replaced wholesale with this stub. The card's entire contract — the
`Workspace` enum, `WorkspaceCommands`, the toolbar workspace `Picker`, and
`Workspace.defaultSubView`/`lastSubView` sub-view memory — was deleted by
this push; nothing in the prior file describes code that still exists.
Supersedes prior status: the 2026-08-06 "Reviewed... No edit needed" note
above only checked for stale `autopilot_proposals` language and explicitly
did not re-examine the workspace model itself, which is now the entire
reason this card is void — that review is not evidence for anything about
the current shell. The prior LEDGER `Reconciled — NOT re-run` PASS-derived
content predates this push entirely and describes a control
(`AppModel.selectWorkspace`) that no longer compiles. No further run is
possible or needed for this file; verification of the replacement contract
lives in `app-019-lens-shell.md`, which needs a fresh VM run.

## Run status — 2026-09-14 (live VM run, batch 6)

**Stub verified accurate** 2026-09-14 (main@5644c66f, static only — this card has no steps left to drive). `grep -rn "enum Workspace / selectWorkspace" Sources/` returns nothing; `LibraryLens` has exactly cull/grid/loupe/timeline/map/people (`LibraryLens.swift:10-16`); `defaultViewMode` `.cull -> .loupe` at `LibraryLens.swift:47-49`; the toolbar `lensSwitcher` is at `LibraryGridView.swift:531`. The pointer to `app-019-lens-shell.md` resolves, and no behavior claim is wrong. Minor citation drift noted at that pass (stub cited `LibraryLens.swift:58-67` and `LibraryGridView.swift:528-555`) has since been corrected in the body — see the 2026-09-14 verification section below. No further run of this card is possible or needed; the replacement contract is verified in `app-019-lens-shell.md`.

## Run status — 2026-09-14 (stub verified accurate, no steps to drive)

Re-verified 2026-09-14 (main checkout, static only — this card has **no
executable steps**; it is a pointer stub). Checks:
- `grep -rn "enum Workspace|selectWorkspace|WorkspaceCommands|defaultSubView|lastSubView" Sources/`
  returns **nothing** — the entire two-workspace contract the old card tested is
  gone, so the stub's supersession claim holds.
- `LibraryLens` has exactly six cases, `cull, grid, loupe, timeline, map,
  people` (`LibraryLens.swift:10-17`).
- `defaultViewMode`'s `.cull -> .loupe` is at `LibraryLens.swift:47-49`.
- the toolbar switcher is `lensSwitcher` at `LibraryGridView.swift:531`
  (its `.accessibilityLabel("Lens")` at `:557`).
- the pointer target `app-019-lens-shell.md` exists and is the live card for
  this contract (re-run 2026-09-14 — see its own Run status).

No behavior claim in the stub is wrong. Citations corrected in the body this
pass: `LibraryLens.swift:58-67`→`:47-55`,
`LibraryGridView.swift:528-555`→`:531`. **No further run of this card is
possible or needed** — the replacement contract is exercised by
`app-019-lens-shell.md`.
