# Trash for Rejects + UX Coherence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add "Move Rejects to Trash" (Finder Trash + manifest-backed Move Back, catalog rows removed) and execute the UX coherence pass (progressive disclosure on the Cull HUD/rail/sidebar and Library header, one sheet template, and a normative glyph/button/label system).

**Spec:** `docs/superpowers/specs/2026-07-11-trash-and-ux-coherence-design.md` — read it before any task; its principles section is normative for every UI change.

**Architecture:** Trash rides the existing relocation machinery (`Sources/TeststripCore/Relocation/` — manifest, WorkSession-first, per-file loop) with a new trash mode and an injected recycler; UI joins the existing Move Rejects surfaces. UX work is presentation-first: visibility matrices and glyph names live in testable presentation types (`CullHUDPresentation`, new `DesignGlyph`, new `SheetScaffold`), views become thin.

**Tech Stack:** Swift 6, SwiftPM, XCTest, VM scenario harness (`script/vm_scenario_run.sh`).

## Global Constraints

- Spec principles 1–4 (progressive disclosure; one primary verb per surface; one glyph ↔ one concept; copy register) bind every task.
- Every UI change updates its affected scenario card(s) IN THE SAME TASK — known map in spec §Testing (Part 2). A UI change without its card update is incomplete.
- Non-destructive invariant: original bytes never modified; Trash is a move; Move Back restores byte-identical files.
- TDD per task; full `swift test` green before each commit (baseline 1718/0).
- The Tart VM may be busy with a story-loop card runner — coordinate: do NOT run vm_scenario_run.sh sync/launch while another runner holds it; unit-level verification in-task, live VM verification batched at Task 12.
- Match surrounding style; presentation logic in structs, not view bodies.

---

### Task 1: Trash relocation core (manifest trash mode + recycler)

**Files:**
- Read first: `Sources/TeststripCore/Relocation/` (all), `AppModel.moveRejectsToFolder` + `moveBackRelocation` (AppModel.swift, re-locate by symbol)
- Modify: relocation service/manifest types; Create: recycler protocol + default `FileManager.trashItem` impl
- Test: `Tests/TeststripCoreTests/` sibling of RejectRelocationServiceTests

**Interfaces:**
- Produces: `RelocationMode { case folder(URL), trash }`; manifest entries for trash mode carry resulting trash URL(s) (original + sidecar), full catalog row snapshot (metadata JSON + linkage), preview-cache key; `Recycler` protocol `func trash(_ url: URL) throws -> URL` (returns resulting URL), injected, default uses `FileManager.trashItem(at:resultingItemURL:)`; service API mirrors folder flow (per-file loop, abort flag, skip-with-issue).

- [ ] Write failing tests: trash mode moves file+sidecar via injected fake recycler into a temp "trash", manifest records resulting URLs + row snapshot; abort mid-loop leaves manifest consistent; missing sidecar is not an error.
- [ ] Run focused tests — fail. Implement minimally. Green.
- [ ] One integration test with the real `FileManager.trashItem` against files created in a temp dir (guard: skip on CI-unsafe volumes if trashItem errors with unsupported-volume).
- [ ] Full `swift test`; commit `feat: trash relocation mode in relocation core`.

### Task 2: Catalog removal + Move Back restore

**Files:**
- Modify: `AppModel.swift` (new `moveRejectsToTrash()` mirroring `moveRejectsToFolder`; extend `moveBackRelocation` for trash mode), repository row delete/re-insert APIs as needed (check what exists — `CatalogRepository` deleteAsset/insert paths)
- Test: `Tests/TeststripAppTests/` sibling of the relocation tests

**Interfaces:**
- Consumes: Task 1 mode + manifest. Produces: `AppModel.moveRejectsToTrash(preflight:)` — WorkSession persisted first, per-file: recycle → delete catalog row → delete cached preview → manifest entry; `moveBackRelocation` for a trash-mode session: move each trash URL back to original path, re-insert row from snapshot (same asset ID), report unrecoverable entries (missing trash URL) in the banner summary and continue.

- [ ] Failing tests: trash N rejects → rows gone, previews gone, manifest complete; move back → rows re-inserted with identical IDs/metadata, files at original paths; emptied-trash entry → skipped + reported, others restored.
- [ ] Implement. Green. Full suite. Commit `feat: move rejects to Trash with catalog removal and manifest-backed restore`.

### Task 3: Trash UI (menu + end-of-set + preflight sheet)

**Files:**
- Modify: `main.swift` (Culling ▸ "Move Rejects to Trash…" beside the folder item, request-token pattern), `LibraryGridView.swift` (end-of-set state gains the action; preflight sheet variant), `CullCompletionPresentation` (new action)
- Test: presentation tests (completion actions include trash; preflight presentation copy)

**Interfaces:**
- Consumes: Task 2 model API. Produces: preflight sheet with warning copy per spec (macOS Trash + catalog forgets), primary button "Move N to Trash"; banner reuses existing relocation banner with trash-aware detail text.

- [ ] TDD presentation additions; wire UI; MenuCoveragePresentationTests extended for the new menu item.
- [ ] Author scenario card `test/scenarios/app-017-move-rejects-to-trash.md` per spec §Part 1 Testing; add LEDGER row (coordinate: ledger is orchestrator-owned — the task ADDS the card and REPORTS the row for the orchestrator to insert; do not edit LEDGER.md).
- [ ] Full suite. Commit `feat: Move Rejects to Trash surfaces`.

### Task 4: DesignGlyph system

**Files:**
- Create: `Sources/TeststripApp/DesignGlyph.swift`; Test: `Tests/TeststripAppTests/DesignGlyphTests.swift`

**Interfaces:**
- Produces: `enum DesignGlyph: String, CaseIterable` mapping every concept in spec §2d to its SF Symbol name (`pick=flag.fill`, `reject=xmark`, `rating=star.fill`, `stack=rectangle.stack`, `ai=sparkles`, `importPhotos=square.and.arrow.down`, `exportPhotos=square.and.arrow.up`, `trashRejects=trash`, `filterMenu=line.3.horizontal.decrease`, `sort=arrow.up.arrow.down`, `activityIdle=bell`, availability family, …); uniqueness test (no two concepts share a symbol); helper `.image` / `.symbolName`.

- [ ] TDD uniqueness + completeness (every concept in the spec table present). Implement. Commit `feat: DesignGlyph single-source icon inventory`.

### Task 5: Glyph adoption sweep

**Files:**
- Modify: every hardcoded symbol usage for inventoried concepts across `LibraryGridView.swift`, `CullSidebarView.swift`, `InspectorView.swift`, `PeopleView.swift`, `ActivityCenterView.swift`, `main.swift` (grep `systemName:` and map each hit: inventoried concept → DesignGlyph; non-inventoried → leave)
- Test: existing presentation tests keep passing; spot AXHelp stability

**Interfaces:** Consumes Task 4. Produces: no behavior change; icon-only controls all carry `.help`.

- [ ] Sweep + audit table in the commit message (symbol → glyph case, or "left: not inventoried"). Any icon-only control missing `.help` gets one (stable strings — scenario cards match on AXHelp; if an AXHelp string must change, update the matching card in the same commit; expected: activity cards).
- [ ] Full suite. Commit `refactor: adopt DesignGlyph across inventoried concepts`.

### Task 6: Cull HUD progressive disclosure

**Files:**
- Modify: `CullHUDPresentation.swift` (visibility matrix), `LibraryGridView.swift` cullHUD
- Test: extend CullHUDPresentationTests

**Interfaces:**
- Produces: `CullHUDPresentation` gains `showsScopeChip` (scope != .all), `showsRating` (rating > 0 or 2s echo after a rating keystroke — reuse the decision-toast timing source), `showsLabelDot` (label != nil), session cluster string `"✓ 38 · ✕ 71 · 209 left"` (monospaced digits) with progress bar beneath.

- [ ] TDD the matrix (undecided default-scope frame → filename + cluster only). Implement + rewire.
- [ ] Update card cull-011 expectations in the same task.
- [ ] Full suite. Commit `feat: cull HUD shows state only when it carries information`.

### Task 7: Stack rail + cull sidebar disclosure

**Files:**
- Modify: `LibraryGridView.swift` (rail suppression + ellipsis menu), `CullSidebarView.swift` (omit zero-count sources; empty state "Nothing to cull"; remove Diagnostics group), `ActivityCenterView.swift` (absorb diagnostics rows into job details), presentations as needed
- Test: presentation tests (rail hidden on stackless session; source omission; empty state)

- [ ] TDD; implement; update cards cull-014, cull-015 (+ activity-003 if diagnostics surface there).
- [ ] Full suite. Commit `feat: stack rail and cull sources appear only when actionable`.

### Task 8: Library header consolidation

**Files:**
- Modify: `LibraryGridView.swift` (filter menu into search field leading accessory; sort → icon menu with checkmarks; chip row emptiness gating; remove Find Best Shots + Cull toolbar buttons — verify Culling-menu equivalents remain per MenuCoverage), `LibraryResultHeaderPresentation` if gating moves there
- Test: presentation tests for chip-row gating; MenuCoverage still green

- [ ] TDD gating; implement; cards lib-006, lib-007, lib-009, lib-010 updated same task (AXHelp "Sort", filter-menu glyph).
- [ ] Full suite. Commit `feat: one query control, compact sort, content-gated result row`.

### Task 9: SheetScaffold template

**Files:**
- Create: `Sources/TeststripApp/SheetScaffold.swift` (title + subtitle + content + Options disclosure + Cancel/primary-verb footer, shared width/spacing)
- Modify: convert Export review, Import review, Card import, Move Rejects (both), Batch Metadata, Save Set/Search/Snapshot, Rename, People naming sheets
- Test: scaffold presentation tests (primary label = verb+count; Options collapsed default)

- [ ] TDD scaffold; convert sheets one commit each or grouped logically; primary buttons renamed to verb+object+count per spec; extra confirm toggles dropped except catalog-wide/destructive.
- [ ] Cards app-009, app-010 updated (button labels changed!). Also inspect-005's unlabeled creator/copyright AXTextFields get `.accessibilityLabel` (spec §Out of scope carve-in).
- [ ] Full suite. Commit(s) `feat: unified sheet scaffold` + conversions.

### Task 10: Copy register sweep

**Files:** user-facing strings in the files above (grep "scope"/"provider"/"evaluation kind" in UI strings)
- [ ] Replace jargon per spec principle 4; Title Case actions audit; counts already mono via cluster work. Update any card matching changed strings. Full suite. Commit `refactor: user-facing copy register`.

### Task 11: Story-loop functional fixes riding this branch

(from the ledger: real bugs, clear fixes, no product decision)
- [ ] XMP pending Retry never drains (inspect-003 evidence): root-cause (`retryPendingMetadataSync` path — why does Retry not enqueue/execute sidecar writes while a later edit does?); TDD; fix.
- [ ] Tolerant preview-level decode (inspect-004): an invalid `preview_generation_queue.level` (or wherever `PreviewLevel` decodes) must not fatalError the app at launch — decode failure marks the row failed and continues; TDD with a corrupted-row fixture; update card inspect-004 + app-001's crash-loop Sharp edge.
- [ ] Full suite. Commits per fix.

### Task 12: Live VM verification batch + docs

- [ ] Coordinate with the orchestrator for VM access. `sync smoke faces burst`; run/re-run affected cards: app-017 (new), cull-011, cull-014, cull-015, lib-006/007/009/010, app-009, app-010, inspect-003, inspect-004, inspect-005 — per-assertion evidence, fix regressions found (loop within task).
- [ ] Update `docs/dogfooding.md` for changed chrome; spec §2d table referenced from CLAUDE.md's docs list if appropriate.
- [ ] Full suite + report per-card verdicts for the orchestrator's ledger.

## Self-review notes
- Spec coverage: Part 1 → T1-3; §2a → T6-7; §2b → T8; §2c → T9; §2d → T4-5; principle 4 → T10; carve-in a11y labels → T9; story-loop fixes → T11; card-update constraint → embedded per task; VM batch → T12.
- Ledger single-writer preserved: tasks report rows; orchestrator writes.
