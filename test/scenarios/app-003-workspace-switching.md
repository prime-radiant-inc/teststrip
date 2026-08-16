# app-003-workspace-switching: superseded by the lens shell

**Superseded by `app-019-lens-shell.md`** (unified shell, 2026-08-07). The
two-workspace model this card tested — `Workspace` (Cull/Library/People),
its toolbar `Picker("Workspace", ...)`, and the shared ⌘1/⌘2/⌘3 shortcuts
routed through `AppModel.selectWorkspace(_:)` — no longer exists in any
form; `Workspace` has had two cases since People became a Library sub-view,
and this push deleted it outright. ⌘1–⌘6 now select one of six lenses
(`LibraryLens`: Cull/Grid/Loupe/Timeline/Map/People) over a single sidebar
and source, via the toolbar `lensSwitcher` (`Sources/TeststripApp/
LibraryGridView.swift:499-526`). See `app-019-lens-shell.md` for the current
switcher/keyboard/session-restore contract this card used to own.

This file is kept (rather than deleted) so its LEDGER row and inbound
cross-references stay resolvable.

**Known UX quirk this card originally flagged (persona-8), carried forward**:
the switcher's Cull segment is labelled "Cull", but pressing ⌘1 on a lens not
yet visited this session lands on a view whose window subtitle reads
"Loupe" — `LibraryLens.defaultViewMode` for `.cull` is `.loupe`
(`Sources/TeststripApp/LibraryLens.swift:58-67`), and that subtitle is
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
