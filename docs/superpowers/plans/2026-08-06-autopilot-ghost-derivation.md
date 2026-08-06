# Autopilot Ghost Derivation (SP-D0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the unconfirmed AI flag in `metadata_json` (the ✨ "ghost") the single source of truth for "the machine proposed a flag," derive every proposal surface from it, and delete the `autopilot_proposals` table and its status machine entirely.

**Architecture:** One pure derivation helper (`AutopilotGhost.kind(in:)` over `AssetMetadata`) in `TeststripCore`, plus one catalog-wide SQL finder (`CatalogRepository.assetIDsWithAutopilotGhost()`) that must agree with it. Every surface — KEEP/CUT badges, the review queue, the Cull sidebar's "Autopilot Proposals" source and count, commit/dismiss — reads one of those two. `AutopilotProposal` survives only as an in-memory working type inside `runAutopilot`; nothing persists it, and the table is dropped forward-only.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, SQLite (hand-rolled `CatalogDatabase`/`CatalogRepository`), XCTest.

**Spec:** `docs/superpowers/specs/2026-08-06-autopilot-ghost-derivation-design.md`. Every decision in it is binding.

---

## Global Constraints

Every task's requirements implicitly include this section.

### Invariants (verbatim from the spec, §"Invariants (unchanged, re-asserted in tests)")

> Ghosts are `origin = ai`, unconfirmed: never written to sidecars, never
> counted as decided, never fill progress, never enter the Picks set, never
> export/relocate/trash. Commit flips origin to user and writes the sidecar
> for sidecar-eligible fields; removal records `removed_ai_labels` so
> nothing resurrects. Original bytes untouched.

### Semantic constraints (verbatim from the spec's decisions)

- **Derive, don't store.** "The ghost — the unconfirmed AI flag in asset metadata — is the single source of truth for 'the machine proposed a flag.' No status machine anywhere; it must be possible for a frame to have no status at all."
- **Gone is gone.** "A direct user flag replaces the ghost; pressing `U` afterwards returns the frame to neutral undecided." Nothing resurrects.
- **No ✨ ink at completion.** "The completion summary is purely about the user's decisions: picked / rejected / undecided / skipped / never viewed. No awaiting-review row, no superseded line, no Review-AI-suggestions ceremony."
- **Keywords are ambient.** "Always created, removable like any AI label, 'no big deal' — they exit the review pipeline entirely and never drive a review count or nag." Keywords never enter review.
- **Catalog-wide universe.** "Universe: catalog-wide, matching today's global pending query — the review queue and the sidebar count must not silently shrink to the loaded scope. Badges and the completion summary keep operating on loaded assets, as today."
- **One derivation helper, one home.** "No surface may re-derive ghost state with its own metadata poking." The only two sanctioned derivations are `AutopilotGhost.kind(in:)` (Task 1) and the SQL finder (Task 2), and Task 2's tests pin them to agree.
- **DROP TABLE is forward-only.** No backward compatibility, no re-creation path, no data migration out of `autopilot_proposals`.
- **Out of scope (spec decision 7 and §Out of scope):** batch-clear undo atomicity (AI-label removal has never been undoable — awareness only, no work here); anything in the run-lifecycle spec (start card, lenses, exact resume, scoped mini-runs, unifying `CullingSessionCompletionSummary` with `CullCompletionPresentation`); any change to how ambient AI keywords are applied, displayed, confirmed, or removed; persisting run-undo across relaunch (never supported, stays unsupported).

### Process constraints

- TDD throughout: write the failing test, watch it fail for the right reason, then implement.
- **Test output MUST BE PRISTINE to pass.** No stray prints, no unexpected error logs. If a test intentionally triggers an error, capture and assert on that error.
- Smallest reasonable change. Match the style and formatting of surrounding code.
- Tests assert against **catalog/sidecar ground truth** (`metadata_json`, `removed_ai_labels`, on-disk `.xmp`), not just view state.
- Never `git add -A`. Run `git status` first; stage only the files the task names.
- Never skip, evade, or disable a pre-commit hook.
- The package must build after **every** task: `swift build` clean, `swift test` green.
- Adversarial split: tasks numbered **NA** author tests only and must capture a real red transcript; tasks numbered **NB** implement and are **FORBIDDEN from modifying any file under `Tests/`**.

---

## Frozen facts (resolved at plan time)

Anchors verified against `main` @ `5abefdfd` on 2026-08-06. Line numbers may drift as tasks land; the symbol names are the contract.

### F1 — The metadata representation of an unconfirmed AI flag

| Question | Answer | Evidence |
|---|---|---|
| Where does the ghost live? | `AssetMetadata.flag: PickFlag?` holds the value; `AssetMetadata.aiUnconfirmedFields: Set<MetadataField>` holds the provenance marker. There is no separate label type. | `Sources/TeststripCore/Domain/Metadata.swift:31` (`flag`), `:36` (`aiUnconfirmedFields`), `:16-21` (`MetadataField { flag, caption, rating, keyword }`), `:11-14` (`PickFlag { pick, reject }`) |
| Exact expression that reads "the ghost" | `metadata.aiUnconfirmedFields.contains(.flag) ? metadata.flag : nil` | Derived from `confirmedProjection` below; encapsulated as `AutopilotGhost.kind(in:)` in Task 1 |
| The ghost's **kind** | The ghost's own value, `PickFlag` (`.pick` / `.reject`). No table lookup, no `AutopilotProposalKind`. | Spec §Derivation: "Its kind is the ghost's own value (pick/reject) — no table lookup." |
| How `confirmedProjection` works | It returns a copy with every AI-unconfirmed label dropped: `flag: aiUnconfirmedFields.contains(.flag) ? nil : flag`, `rating: aiUnconfirmedFields.contains(.rating) ? 0 : rating`, `caption` likewise, `keywords` filtered by `aiUnconfirmedKeywords`. It is what XMP exports and what "portable metadata exists" is judged against. | `Sources/TeststripCore/Domain/Metadata.swift:53-65`; consumed by `Sources/TeststripCore/Metadata/XMPPacket.swift:62` and `Sources/TeststripCore/Metadata/MetadataSyncPlanner.swift:43-50` |
| What the **un-projected** label looks like | `AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag])` — `flag` is `.pick` on the raw metadata, `confirmedProjection.flag` is `nil`. Ghost present iff `flag != nil && aiUnconfirmedFields.contains(.flag)`. | Written this way by `applyTentativeAutopilotProposals`, `Sources/TeststripApp/AppModel.swift:9739-9741` |
| Encoding | `aiUnconfirmedFields` is omitted from `metadata_json` when empty and encoded as a **sorted array of raw strings** when present, so `json_each(metadata_json, '$.aiUnconfirmedFields')` yields `"flag"` etc. | `Sources/TeststripCore/Domain/Metadata.swift:197-205` |

### F2 — The catalog-wide ghost query mechanism

**Decision: a new SQL repository query, `CatalogRepository.assetIDsWithAutopilotGhost() throws -> [AssetID]`.**

Justification from real code:

- Today's universe is already catalog-wide via a global SQL query: `pendingAutopilotProposals` is refilled wholesale from `catalog.repository.autopilotProposals(status: .pending)` (`Sources/TeststripApp/AppModel.swift:9702, 9936, 9985, 10015, 10133`), which is `SELECT * FROM autopilot_proposals WHERE status = ?` over the whole table (`Sources/TeststripCore/Catalog/CatalogRepository.swift:2168-2174`). An in-memory derivation over `AppModel.assets` would silently shrink the universe to the loaded scope — the exact regression the spec forbids.
- The codebase already has the mirror-image predicate: `CatalogRepository.confirmedFieldClauseSQL` = `"NOT EXISTS (SELECT 1 FROM json_each(metadata_json, '$.aiUnconfirmedFields') WHERE json_each.value = ?)"` (`Sources/TeststripCore/Catalog/CatalogRepository.swift:3041-3048`), used at `:572` and `:1049`. The ghost query is its positive twin. Its doc comment establishes the safety fact we rely on: *"`json_each` on a path that doesn't exist (an asset with no unconfirmed fields at all, the common case) yields zero rows, so this is always safe to AND in."*
- Return shape follows the existing `assetIDs(...)` family: `SELECT id FROM assets<where> ORDER BY rowid ASC` + `try rows.map(decodeAssetID)` (`Sources/TeststripCore/Catalog/CatalogRepository.swift:402-418`).
- Display-facing listings exclude bonded secondaries via `Self.excludingSecondaries(_:)` (`Sources/TeststripCore/Catalog/CatalogRepository.swift:318-324`). The review queue and sidebar count are display-facing, so the ghost query excludes them too.

**Freshness for the sidebar count.** `cullSourcePresentation` is a computed var re-evaluated on every render (`Sources/TeststripApp/AppModel.swift:5873-5896`), so it cannot issue SQL. It reads a cached array, exactly as it reads `pendingAutopilotProposals` today. The cache is `AppModel.autopilotGhostAssetIDs`, refreshed inside `refreshCatalogSidebarCounts()` (`Sources/TeststripApp/AppModel.swift:13305-13311`) — the same funnel that already maintains `reviewQueueCounts`. `applyMetadataSnapshot` already calls it (`:8523`), which covers every direct P/X/U, confirm, and batch metadata write. Two paths do **not** call it today and get an explicit call in Task 3B: `removeAIField` (`:8393-8417` — the `U`-on-a-ghost path; its omission is a pre-existing sidebar-count bug, since clearing a flag changes the `likelyPick` queue count too) and `runAutopilot`'s tail.

### F3 — Complete grep-verified consumer list

Produced by `grep -rn "pendingAutopilotProposals\|AutopilotProposalStatus\|AutopilotProposal\b\|autopilotProposals\|updateAutopilotProposalStatus\|deleteAutopilotProposals\|autopilotProposalCount\|distinctPendingAutopilotProposalAssetIDs\|reconstructAutopilotStateAfterLoad\|lastAutopilotRunIDByScopeKey\|autopilot_proposals" --include="*.swift" Sources Tests`, plus a second sweep for `autopilotProposalDecision|autopilotReviewProposalCount|autopilotDecision|AutopilotBadgePresentation`.

**`CatalogRepository` proposal APIs (all deleted in Task 6):**

| Symbol | Site | Sole consumers |
|---|---|---|
| `save(_ proposals: [AutopilotProposal])` | `CatalogRepository.swift:2114-2158` | `AppModel.swift:9690`; `CatalogDatabaseTests.swift:51, 3341` |
| `autopilotProposals(runID:)` | `:2160-2166` | `AppModel.swift:10011`; `CatalogDatabaseTests.swift:53, 62, 3344` |
| `autopilotProposals(status:)` | `:2168-2174` | `AppModel.swift:9702, 9936, 9985, 10015, 10133`; `CatalogDatabaseTests.swift:57, 58`; `AppModelTests.swift:5743, 5744` |
| `updateAutopilotProposalStatus(ids:to:)` | `:2176-2187` | `AppModel.swift:9932, 9934, 9984, 10014`; `CatalogDatabaseTests.swift:56` |
| `pendingAutopilotProposalCount()` | `:2189-2195` | `CatalogDatabaseTests.swift:54, 59` only (no production consumer) |
| `deleteAutopilotProposals(runID:)` | `:2197-2202` | `AppModel.swift:9679`; `CatalogDatabaseTests.swift:61` |
| `decodeAutopilotProposal(_:)` (private) | `:2204-2234` | the two query methods above |
| asset-delete cascade line | `:2030` (`DELETE FROM autopilot_proposals WHERE asset_id = ?` inside `deleteAsset(id:)`) | `CatalogDatabaseTests.swift:3320-3344` |

**`AutopilotProposal` / `AutopilotProposalStatus` / `AutopilotProposalKind`:**

| Symbol | Site | Disposition |
|---|---|---|
| `AutopilotProposalStatus` enum | `Sources/TeststripCore/Autopilot/AutopilotProposal.swift:19-23` | **Deleted** (Task 6) |
| `AutopilotProposal.status` property + init param | `AutopilotProposal.swift:33, 45, 56` | **Deleted** (Task 6) |
| `AutopilotProposalPlanner.makeProposal`'s `status: .pending` | `Sources/TeststripCore/Autopilot/AutopilotProposalPlanner.swift:139` | **Deleted** (Task 6) |
| `AutopilotProposal` struct | `AutopilotProposal.swift:25-59` | **Survives** as an in-memory working type: produced by `AutopilotProposalPlanner.proposals(for:runID:now:)` (`AutopilotProposalPlanner.swift:32, 65, 91, 130-143`), consumed by `runAutopilot` (`AppModel.swift:9689, 9696-9698`) and `applyTentativeAutopilotProposals` (`AppModel.swift:9718-9766`) |
| `AutopilotProposalKind` | `AutopilotProposal.swift:13-17` | **Survives** (planner + apply). Removed only from `AutopilotBadgePresentation.badge(for:)` (Task 3), which switches to `PickFlag?` |

**`AppModel` state and methods:**

| Symbol | Site | Disposition |
|---|---|---|
| `pendingAutopilotProposals` (property) | `AppModel.swift:2252` | **Deleted** (Task 5) |
| assignments to it | `:9702` (Task 3), `:9936, 9985` (Task 3), `:10015, 10134` (Task 5) | all removed |
| reads of it | `:5887, 5893` (Task 3), `:9825, 9835, 9858, 9881, 9887, 9962` (Task 3), `LibraryGridView.swift:3849` (Task 4) | all removed |
| `lastAutopilotRunIDByScopeKey` | `:2277`, used `:9678, 9691` | **Deleted** (Task 5) |
| `distinctPendingAutopilotProposalAssetIDs()` | `:9855-9862`, called `:9845, 9946` | **Deleted** (Task 3) |
| `reconstructAutopilotStateAfterLoad()` | `:10131-10147`, called `:4720` | **Deleted** (Task 5) |
| `autopilotProposalDecision(for:)` | `:9824-9828` | **Deleted** (Task 3); callers pass `AutopilotGhost.kind(in: asset.metadata)` |
| `autopilotReviewProposalCount` | `:9834-9836` | **Renamed** `autopilotGhostCount` (Task 3) |
| `beginAutopilotReview()` | `:9841-9853` | **Rewritten** to the catalog-wide ghost query (Task 3) |
| `commitAutopilotProposals(assetIDs:)` | `:9876-9942` | **Rewritten** ghost-driven, flags-only (Task 3) |
| `commitAllAutopilotProposals()` | `:9945-9947` | **Rewritten** (Task 3) |
| `dismissAutopilotProposals(assetIDs:)` | `:9957-9988` | **Rewritten** to `removeAIField(.flag, for:)` per ghost asset (Task 3) |
| `undoAutopilotRun()` status-flip block | `:10010-10016` | **Deleted** (Task 5); the in-memory change-group replay `:10007-10009` is untouched |
| `runAutopilot(scope:)` persistence | `:9677-9680` (delete-prior-run), `:9690` (save), `:9691` (scope-key), `:9702` (refill) | `:9702` → `try refreshCatalogSidebarCounts()` in Task 3; the rest deleted in Task 5 |

**Views:**

| Symbol | Site | Disposition |
|---|---|---|
| `AutopilotBadgePresentation.badge(for:)` | `LibraryGridView.swift:3605-3618` | Parameter type `AutopilotProposalKind?` → `PickFlag?`; the `.keyword` case disappears (Task 3) |
| `AssetGridCell.autopilotDecision` | `LibraryGridView.swift:9670`, rendered `:9706` | Type → `PickFlag?`; **label unchanged** (Task 3) |
| `AssetGridCellAccessibilityValue.value(... autopilotDecision:)` | `LibraryGridView.swift:8330-8351` | Type → `PickFlag?`; label unchanged (Task 3) |
| badge call sites | `LibraryGridView.swift:2370, 7690, 8147` | → `AutopilotGhost.kind(in: asset.metadata)` (Task 3); `asset` is in lexical scope at all three |
| `cullCompletion` kind partition | `LibraryGridView.swift:3842-3865` | **Deleted** (Task 4) |
| `cullCompletionRunDetailText` sparkle segment | `LibraryGridView.swift:4053-4058` | **Deleted** (Task 4) |
| `.reviewAISuggestions` button case | `LibraryGridView.swift:4042-4044` | **Deleted** (Task 4) |
| `CullCompletionPresentation` | `Sources/TeststripApp/CullCompletionPresentation.swift` | `sparkleAwaiting` field, `.reviewAISuggestions` action, both pending-ID params deleted (Task 4) |
| `CullSource.Target.autopilotProposals` / `.Group.autopilotProposals` | `AppModel.swift:722, 732`, routed `:5860`, `CullSidebarView.swift:46` | **Unchanged** — the source stays, only its gate/count change |

**Tests touching any of the above:**

`Tests/TeststripCoreTests/CatalogDatabaseTests.swift:19-63` (`testPersistsAndReadsAutopilotProposalsByRunAndStatus`), `:3320-3344` (`testDeleteAssetRemovesPendingAutopilotProposal`); `Tests/TeststripAppTests/AppModelTests.swift:5394-5890` (the autopilot region: 17 tests), `:14919-15049` (armed-import runs — assert `autopilotRunSummary` only, unaffected); `Tests/TeststripAppTests/CullCompletionTests.swift` (entire file uses the two pending-ID params); `Tests/TeststripAppTests/CullSourcePresentationTests.swift:55, 87-90`; `Tests/TeststripAppTests/LibraryGridChromeTests.swift:6-13`; `Tests/TeststripAppTests/LibraryGridLayoutTests.swift:170-238` (compiles unchanged once the type is `PickFlag?`).

### F4 — Scenario-card audit

Full sweep of `test/scenarios/*.md` (48 cards + `README.md` + `LEDGER.md`). **Next free number: `cull-029`** (highest today is `cull-028-face-report-cards.md`; numbering is dense with no gaps).

**Tier 1 — flatly wrong after this push (must be reconciled in Task 9):**

| Card | Lines | Stale content |
|---|---|---|
| `test/scenarios/cull-025-run-strip-completion.md` | 1, 13-15, 114-169, 174-176, 180-182, 198-217, 228-234, 252, 380-384, 409, 411-419, 493-513, 556-564, 589-603, 622-649, 662-666, 725-758 | Title claims "six counts … the cull view's only ✨ surface"; the whole `sparkleAwaiting` kind-aware contract block; the verbatim `"\(skipped) skipped · \(neverViewed) never viewed · \(sparkleAwaiting) AI … awaiting review"` detail line; the six-title ceremony list incl. `"Review AI Suggestions"`; the `INSERT INTO autopilot_proposals (…)` fixture seed; `SELECT count(*) FROM autopilot_proposals WHERE status='pending'` assertions; the `reconstructAutopilotStateAfterLoad()` banner-at-launch sharp edge |
| `test/scenarios/cull-017-autopilot-review.md` | whole card | Built on `autopilot_proposals` rows as ground truth (`:59, 71, 82-83, 110`), badges "matching `autopilot_proposals.kind`" (`:77-78`), "read `autopilot_proposals` directly via `autopilotProposalDecision(for:)`" (`:96-99, 113-114`), Expected `:157-186` |
| `test/scenarios/import-008-auto-cull-toggle.md` | 20, 57, 65-70, 83-88, 89-93, 100-108 | `SELECT count(*) FROM autopilot_proposals`, `SELECT DISTINCT asset_id FROM autopilot_proposals`, `SELECT status, count(*) … GROUP BY status` |
| `test/scenarios/app-012-autopilot-evaluate-commands.md` | 39, 49-51, 59, 69, 73 | `SELECT count(*) FROM autopilot_proposals; # still 0`; `JOIN autopilot_proposals p ON …` |
| `test/scenarios/cull-015-sidebar-sources.md` | 4-5, 10, 35, 42-43, 53-54, 75, 79 | `` `.autopilotProposals`: present only if `!pendingAutopilotProposals.isEmpty` `` |
| `test/scenarios/lib-016-grid-badges.md` | 7, 43, 46-48, 126-128 | `` `.keyword` proposal or `nil` → no badge ``; "needs a pending Autopilot proposal in place" |
| `test/scenarios/worker-002-evaluation-verdicts.md` | 5-7, 58-66, 75-82, 94-95 | `SELECT kind, status FROM autopilot_proposals WHERE asset_id = …`; badge "driven by a *committed* `AutopilotProposalKind`" |
| `test/scenarios/people-020-ai-label-provenance.md` | 305-311, 359-368, 464-467 | `SELECT run_id FROM autopilot_proposals ORDER BY created_at DESC LIMIT 1`; `JOIN autopilot_proposals p …` |
| `test/scenarios/dev-009-bench-seeds.md` | 113 | schema-table inventory listing `autopilot_proposals` |

**Tier 2 — stale prose / cross-references (also reconciled in Task 9):**

`test/scenarios/app-003-workspace-switching.md:25-26`; `app-005-chrome-policy.md:19-20`; `app-011-find-best-shots.md:37, 41, 71`; `cull-016-completion-stage.md:32-40` (its three-action set already conflicts with cull-025's six-title list — Task 9 makes one authoritative post-drop action set) and `:118-122`; `cull-014-stack-rail.md:335-338`; `cull-024-honest-states.md:574-582`; `cull-026-tentative-never-commits.md:352-354` (cross-reference to cull-017); `lib-012-grid-keys.md:103`; `test/scenarios/README.md:128`; `test/scenarios/LEDGER.md` rows for cull-017, lib-016, import-008, app-012.

**Tier 3 — audited and clean, no change:** `cull-011-hud.md` (confirmed-projection only), `cull-023-return-commit-undo.md` and `cull-026-tentative-never-commits.md` (hand-seed `aiUnconfirmedFields` directly, never the table), `cull-024-honest-states.md` body, `app-006-session-restore.md`. "Sparkle" hits in `app-001/app-014/dev-004/dev-005/dev-011/cull-028` are the **updater framework**, not the ✨ glyph. `people-022/023/024`'s "✨ Proposed" is the **face**-proposal surface (`person_faces`, `origin='ai'`), out of scope.

**Gaps (no existing card asserts these — they are exactly what cull-029 adds):** nothing asserts "U after overriding a ghost does not resurrect the badge"; nothing asserts banner survival across relaunch as a pass/fail condition (cull-025:210-217 and :556-564 mention it informationally only).

### F5 — Migration structure and the DROP TABLE shape

- `CatalogMigrations` is not a numbered-step framework. It is a `static let statements = [...]` array of **idempotent** `CREATE TABLE IF NOT EXISTS` / `CREATE INDEX IF NOT EXISTS` strings, executed in order on **every** open, plus a separate `static let coordinateIndexStatement` and a `static let version` (currently `22`). (`Sources/TeststripCore/Catalog/CatalogMigrations.swift:1-282`)
- `CatalogDatabase.migrate()` runs the `statements` loop, then a sequence of `addColumnIfMissing(...)` patches, then `coordinateIndexStatement`, then writes `catalog_meta.schema_version` from `CatalogMigrations.version`. (`Sources/TeststripCore/Catalog/CatalogDatabase.swift:35-64`)
- There is **no existing DROP** anywhere in `Sources/` or `Tests/` (`grep -rn "DROP TABLE\|DROP INDEX"` → no hits). This plan establishes the shape: a new `static let dropStatements = [...]` array on `CatalogMigrations`, executed by a loop in `migrate()` immediately after the `statements` loop. `DROP TABLE` removes the table's indexes with it, so `idx_autopilot_proposals_run` / `idx_autopilot_proposals_status` need no separate statement.
- **Existing migration-test patterns to copy:**
  - Version floor: `Tests/TeststripCoreTests/CatalogRepositoryContentHashTests.swift:23-28` — `XCTAssertGreaterThanOrEqual(CatalogMigrations.version, 15)` with a comment explaining why it asserts a floor, not a literal. Same shape at `Tests/TeststripCoreTests/ContactReferenceFacesTests.swift:15`.
  - Reopen-and-re-migrate: `Tests/TeststripCoreTests/MetadataSyncTests.swift:374-393` — open at a URL, migrate, write, `CatalogDatabase.open(at: sameURL)` again, `migrate()` again, assert through a fresh `CatalogRepository`.
  - Raw SQL from tests: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift` uses `@testable import TeststripCore`, so the internal `database.execute(_:bindings:)` and `database.rows(_:bindings:)` are reachable (see `:73-80` executing `BEGIN IMMEDIATE TRANSACTION` directly).
  - Temp dirs: `TestDirectories.makeTemporaryDirectory(named:)`.

---

## File structure

**Created:**

- `Sources/TeststripCore/Autopilot/AutopilotGhost.swift` — the one derivation helper. Pure, no I/O.
- `Tests/TeststripCoreTests/AutopilotGhostTests.swift` — derivation unit tests.
- `Tests/TeststripCoreTests/AutopilotGhostQueryTests.swift` — the catalog-wide finder, incl. its agreement-with-the-helper test.
- `Tests/TeststripCoreTests/CatalogMigrationDropTests.swift` — the DROP TABLE migration.
- `test/scenarios/cull-029-autopilot-ghost-derivation.md` — the new E2E card.

**Modified:**

- `Sources/TeststripCore/Catalog/CatalogRepository.swift` — add `assetIDsWithAutopilotGhost()`; delete the seven proposal APIs + the cascade line.
- `Sources/TeststripCore/Catalog/CatalogMigrations.swift` — drop the table's CREATEs, add `dropStatements`, bump `version`.
- `Sources/TeststripCore/Catalog/CatalogDatabase.swift` — run `dropStatements`.
- `Sources/TeststripCore/Autopilot/AutopilotProposal.swift` — delete `AutopilotProposalStatus` and `AutopilotProposal.status`.
- `Sources/TeststripCore/Autopilot/AutopilotProposalPlanner.swift` — drop `status:` from the initializer call.
- `Sources/TeststripApp/AppModel.swift` — the ghost cache, the rewritten review/commit/dismiss/badge surface, and every deletion in F3.
- `Sources/TeststripApp/CullCompletionPresentation.swift` — drop the ✨ counts, params, and action.
- `Sources/TeststripApp/LibraryGridView.swift` — badge type, completion call site, detail line, ceremony button.
- `Tests/TeststripAppTests/AppModelTests.swift`, `CullCompletionTests.swift`, `CullSourcePresentationTests.swift`, `LibraryGridChromeTests.swift`; `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`.
- The scenario cards listed in F4 Tier 1 + Tier 2, plus `test/scenarios/LEDGER.md`.

---

## Task 1A: Ghost derivation helper — tests (test author)

**Files:**
- Test: `Tests/TeststripCoreTests/AutopilotGhostTests.swift` (create)

**Interfaces:**
- Produces (for Task 1B to implement): `public enum AutopilotGhost { public static func kind(in metadata: AssetMetadata) -> PickFlag? }` in module `TeststripCore`.

**You are the test author. Do not write any file under `Sources/`.** Your deliverable is a failing test file plus the captured red transcript in your task report.

- [ ] **Step 1: Write the failing test file**

Create `Tests/TeststripCoreTests/AutopilotGhostTests.swift`:

```swift
import XCTest
@testable import TeststripCore

// The ghost — an AI-origin, unconfirmed flag in asset metadata — is the single
// source of truth for "the machine proposed a flag". `AutopilotGhost.kind(in:)`
// is the only place that derivation is written; every surface reads it.
final class AutopilotGhostTests: XCTestCase {
    func testGhostKindIsTheFlagValueWhenTheFlagIsAIUnconfirmed() {
        let pick = AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag])
        let reject = AssetMetadata(flag: .reject, aiUnconfirmedFields: [.flag])

        XCTAssertEqual(AutopilotGhost.kind(in: pick), .pick)
        XCTAssertEqual(AutopilotGhost.kind(in: reject), .reject)
    }

    func testUserOriginFlagIsNotAGhost() {
        let pick = AssetMetadata(flag: .pick)
        let reject = AssetMetadata(flag: .reject)

        XCTAssertNil(AutopilotGhost.kind(in: pick))
        XCTAssertNil(AutopilotGhost.kind(in: reject))
    }

    // A frame is allowed to have no status at all — that is the whole point of
    // deriving instead of storing.
    func testNoFlagIsNotAGhost() {
        XCTAssertNil(AutopilotGhost.kind(in: AssetMetadata()))
    }

    // Other unconfirmed fields are a different proposal entirely; only `.flag`
    // makes a flag ghost.
    func testUnconfirmedCaptionOrRatingAloneIsNotAFlagGhost() {
        let caption = AssetMetadata(caption: "a dog", aiUnconfirmedFields: [.caption])
        let rating = AssetMetadata(rating: 4, aiUnconfirmedFields: [.rating])

        XCTAssertNil(AutopilotGhost.kind(in: caption))
        XCTAssertNil(AutopilotGhost.kind(in: rating))
    }

    // Ambient AI keywords are invisible to flag-ghost derivation (spec
    // decision 2: keywords exit the review pipeline entirely).
    func testAmbientAIKeywordsAreInvisibleToGhostDerivation() {
        let keywordsOnly = AssetMetadata(
            keywords: ["dog", "beach"],
            aiUnconfirmedKeywords: ["dog", "beach"]
        )

        XCTAssertNil(AutopilotGhost.kind(in: keywordsOnly))
    }

    // Defensive: a marker left behind with no value is not a ghost. Nothing
    // should produce this state, and if something does, the derivation must
    // report "no status" rather than a phantom.
    func testUnconfirmedMarkerWithoutAFlagValueIsNotAGhost() {
        let orphanedMarker = AssetMetadata(flag: nil, aiUnconfirmedFields: [.flag])

        XCTAssertNil(AutopilotGhost.kind(in: orphanedMarker))
    }

    // The ghost is exactly what `confirmedProjection` filters out — these two
    // must never disagree about whether a flag is a real user decision.
    func testGhostIsExactlyWhatConfirmedProjectionDrops() {
        let ghost = AssetMetadata(flag: .reject, aiUnconfirmedFields: [.flag])
        let userFlag = AssetMetadata(flag: .reject)

        XCTAssertNil(ghost.confirmedProjection.flag)
        XCTAssertNotNil(AutopilotGhost.kind(in: ghost))
        XCTAssertNotNil(userFlag.confirmedProjection.flag)
        XCTAssertNil(AutopilotGhost.kind(in: userFlag))
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail for the right reason**

Run: `swift test --filter TeststripCoreTests.AutopilotGhostTests 2>&1 | tail -40`

Expected: **compile failure**, `cannot find 'AutopilotGhost' in scope`, in `AutopilotGhostTests.swift`. This is a genuine red — the helper does not exist. No falsification step is needed.

- [ ] **Step 3: Capture the red transcript into your task report**

Paste the exact compiler output (the `error:` lines and the file/line they point at) into your report. A report without a verbatim red transcript is an incomplete task.

- [ ] **Step 4: Commit**

```bash
git status
git add Tests/TeststripCoreTests/AutopilotGhostTests.swift
git commit -m "test: pin autopilot ghost derivation semantics (red)"
```

Note: this commit leaves `swift test` red. That is intended and is the only point in this plan where it happens; Task 1B closes it immediately.

---

## Task 1B: Ghost derivation helper — implementation

**Files:**
- Create: `Sources/TeststripCore/Autopilot/AutopilotGhost.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `AutopilotGhost.kind(in: AssetMetadata) -> PickFlag?` (public, module `TeststripCore`). Task 2, 3, and 7 all call it.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.** If a test looks wrong, stop and report it rather than editing it.

- [ ] **Step 1: Write the implementation**

Create `Sources/TeststripCore/Autopilot/AutopilotGhost.swift`:

```swift
/// The machine's flag opinion on an asset — the ✨ "ghost". An asset's
/// autopilot ghost is its flag label when the label is AI-origin and
/// unconfirmed; every proposal state (proposed / overridden / dismissed /
/// never applied) is derived from metadata here, never stored. There is no
/// status machine: a frame is allowed to have no status at all.
///
/// This is the single derivation source. No surface may re-derive ghost state
/// with its own metadata poking — the only other reader of the raw
/// representation is `CatalogRepository.assetIDsWithAutopilotGhost()`, the
/// catalog-wide SQL twin, whose tests pin it to agree with this function.
public enum AutopilotGhost {
    /// The ghost's kind — its own flag value — or `nil` when the asset carries
    /// no ghost (a user-origin flag, no flag at all, or only non-flag AI
    /// labels such as ambient keywords).
    public static func kind(in metadata: AssetMetadata) -> PickFlag? {
        guard metadata.aiUnconfirmedFields.contains(.flag) else { return nil }
        return metadata.flag
    }
}
```

- [ ] **Step 2: Run the tests and verify they pass**

Run: `swift test --filter TeststripCoreTests.AutopilotGhostTests`
Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 3: Verify the whole package still builds and the full suite is green**

Run: `swift build && swift test 2>&1 | tail -20`
Expected: build succeeds; the suite reports 0 failures. Nothing else in the tree references `AutopilotGhost` yet, so no other test can move.

- [ ] **Step 4: Commit**

```bash
git status
git add Sources/TeststripCore/Autopilot/AutopilotGhost.swift
git commit -m "feat: derive the autopilot ghost from asset metadata"
```

---

## Task 2A: Catalog-wide ghost query — tests (test author)

**Files:**
- Test: `Tests/TeststripCoreTests/AutopilotGhostQueryTests.swift` (create)

**Interfaces:**
- Consumes: `AutopilotGhost.kind(in:)` (Task 1B).
- Produces (for Task 2B): `public func assetIDsWithAutopilotGhost() throws -> [AssetID]` on `CatalogRepository`.

**You are the test author. Do not write any file under `Sources/`.**

- [ ] **Step 1: Write the failing test file**

Create `Tests/TeststripCoreTests/AutopilotGhostQueryTests.swift`:

```swift
import XCTest
@testable import TeststripCore

// The review queue's and sidebar count's universe is catalog-wide, not the
// loaded scope. This is the SQL twin of `AutopilotGhost.kind(in:)`; the
// agreement test below is what keeps the two derivations honest.
final class AutopilotGhostQueryTests: XCTestCase {
    private func makeRepository(named name: String) throws -> CatalogRepository {
        let directory = try TestDirectories.makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    private func asset(path: String, metadata: AssetMetadata) -> Asset {
        Asset(
            id: .new(),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: metadata
        )
    }

    func testFindsOnlyGhostCarryingAssets() throws {
        let repository = try makeRepository(named: "ghost-query-basic")
        let ghostPick = asset(path: "/Photos/ghost-pick.cr2", metadata: AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag]))
        let ghostReject = asset(path: "/Photos/ghost-reject.cr2", metadata: AssetMetadata(flag: .reject, aiUnconfirmedFields: [.flag]))
        let userFlag = asset(path: "/Photos/user-flag.cr2", metadata: AssetMetadata(flag: .pick))
        let noFlag = asset(path: "/Photos/no-flag.cr2", metadata: AssetMetadata())
        for stored in [ghostPick, ghostReject, userFlag, noFlag] {
            try repository.upsert(stored)
        }

        XCTAssertEqual(
            Set(try repository.assetIDsWithAutopilotGhost()),
            Set([ghostPick.id, ghostReject.id])
        )
    }

    // Ambient AI keywords never enroll an asset in the review queue.
    func testAmbientAIKeywordsDoNotEnrollAnAsset() throws {
        let repository = try makeRepository(named: "ghost-query-keywords")
        let keywordsOnly = asset(
            path: "/Photos/keywords.cr2",
            metadata: AssetMetadata(keywords: ["dog"], aiUnconfirmedKeywords: ["dog"])
        )
        let captionOnly = asset(
            path: "/Photos/caption.cr2",
            metadata: AssetMetadata(caption: "a dog", aiUnconfirmedFields: [.caption])
        )
        let ratingOnly = asset(
            path: "/Photos/rating.cr2",
            metadata: AssetMetadata(rating: 4, aiUnconfirmedFields: [.rating])
        )
        for stored in [keywordsOnly, captionOnly, ratingOnly] {
            try repository.upsert(stored)
        }

        XCTAssertEqual(try repository.assetIDsWithAutopilotGhost(), [])
    }

    func testEmptyCatalogYieldsNoGhosts() throws {
        let repository = try makeRepository(named: "ghost-query-empty")

        XCTAssertEqual(try repository.assetIDsWithAutopilotGhost(), [])
    }

    // Display-facing listing: a bonded JPEG secondary must never surface as its
    // own review-queue row, same rule the other id listings follow.
    func testBondedSecondaryIsExcluded() throws {
        let repository = try makeRepository(named: "ghost-query-bonded")
        let primary = asset(path: "/Photos/frame.cr2", metadata: AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag]))
        let secondary = asset(path: "/Photos/frame.jpg", metadata: AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag]))
        try repository.upsert(primary)
        try repository.upsert(secondary)
        try repository.setBonds([AssetBond(primaryID: primary.id, secondaryID: secondary.id)])

        XCTAssertEqual(try repository.assetIDsWithAutopilotGhost(), [primary.id])
    }

    // The two sanctioned derivations must never disagree: whatever the pure
    // helper calls a ghost is exactly what the SQL finder returns, across the
    // whole matrix of metadata shapes.
    func testSQLFinderAgreesWithTheDerivationHelperAcrossTheMatrix() throws {
        let repository = try makeRepository(named: "ghost-query-agreement")
        let matrix: [AssetMetadata] = [
            AssetMetadata(),
            AssetMetadata(flag: .pick),
            AssetMetadata(flag: .reject),
            AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag]),
            AssetMetadata(flag: .reject, aiUnconfirmedFields: [.flag]),
            AssetMetadata(flag: nil, aiUnconfirmedFields: [.flag]),
            AssetMetadata(rating: 4, aiUnconfirmedFields: [.rating]),
            AssetMetadata(caption: "x", aiUnconfirmedFields: [.caption]),
            AssetMetadata(keywords: ["dog"], aiUnconfirmedKeywords: ["dog"]),
            AssetMetadata(rating: 5, flag: .pick, keywords: ["dog"], caption: "x", aiUnconfirmedKeywords: ["dog"], aiUnconfirmedFields: [.flag, .caption]),
            AssetMetadata(rating: 5, flag: .pick, keywords: ["dog"], caption: "x", aiUnconfirmedKeywords: ["dog"], aiUnconfirmedFields: [.caption])
        ]
        var expected: Set<AssetID> = []
        for (index, metadata) in matrix.enumerated() {
            let stored = asset(path: "/Photos/matrix-\(index).cr2", metadata: metadata)
            try repository.upsert(stored)
            if AutopilotGhost.kind(in: metadata) != nil {
                expected.insert(stored.id)
            }
        }

        XCTAssertEqual(Set(try repository.assetIDsWithAutopilotGhost()), expected)
        XCTAssertEqual(expected.count, 3, "matrix must contain exactly three ghosts, or the agreement check is vacuous")
    }
}
```

- [ ] **Step 2: Check the fixture helpers actually exist before running**

Run:
```bash
grep -n "struct AssetBond\|func setBonds" Sources/TeststripCore/Catalog/*.swift Sources/TeststripCore/Domain/*.swift
grep -n "makeTemporaryDirectory" Tests/TeststripCoreTests/*.swift | head -3
```
Expected: `setBonds` and an `AssetBond`-shaped value exist in `CatalogRepository` (`Sources/TeststripCore/Catalog/CatalogRepository.swift:315` calls `try setBonds(bonds)`). If the bond value's initializer label differs from `AssetBond(primaryID:secondaryID:)`, adjust **only** the `testBondedSecondaryIsExcluded` fixture to the real API and say so in your report. Everything else is fixed.

- [ ] **Step 3: Run the tests and verify they fail for the right reason**

Run: `swift test --filter TeststripCoreTests.AutopilotGhostQueryTests 2>&1 | tail -40`
Expected: **compile failure**, `value of type 'CatalogRepository' has no member 'assetIDsWithAutopilotGhost'`. Genuine red; no falsification step needed.

- [ ] **Step 4: Capture the red transcript into your task report**

- [ ] **Step 5: Commit**

```bash
git status
git add Tests/TeststripCoreTests/AutopilotGhostQueryTests.swift
git commit -m "test: pin the catalog-wide ghost query and its agreement with the helper (red)"
```

---

## Task 2B: Catalog-wide ghost query — implementation

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (add one method next to the `assetIDs(...)` family, after `assetIDs(ids:matching:)` which ends at `:437`)

**Interfaces:**
- Consumes: `AutopilotGhost.kind(in:)` (semantics only), `Self.excludingSecondaries(_:)` (`:318-324`), `decodeAssetID` (used at `:405, 417, 434`).
- Produces: `public func assetIDsWithAutopilotGhost() throws -> [AssetID]`. Task 3B calls it from `AppModel`.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.**

- [ ] **Step 1: Add the query**

Insert immediately after `assetIDs(ids:matching:)` in `Sources/TeststripCore/Catalog/CatalogRepository.swift`:

```swift
    /// Every asset carrying an autopilot ghost — an AI-origin, unconfirmed
    /// flag in `metadata_json`. The SQL twin of `AutopilotGhost.kind(in:)`,
    /// and the positive mirror of `confirmedFieldClauseSQL`: `json_each` on a
    /// path that doesn't exist (an asset with no unconfirmed fields at all,
    /// the common case) yields zero rows, so the EXISTS is safe on every row.
    ///
    /// Catalog-wide by design — the review queue and the Cull sidebar's
    /// "Autopilot Proposals" count must not silently shrink to whatever the
    /// grid happens to have loaded. Display-facing, so bonded secondaries are
    /// excluded like the other id listings.
    public func assetIDsWithAutopilotGhost() throws -> [AssetID] {
        let ghostClauseSQL = """
        json_extract(metadata_json, '$.flag') IS NOT NULL
        AND EXISTS (SELECT 1 FROM json_each(metadata_json, '$.aiUnconfirmedFields') WHERE json_each.value = ?)
        """
        let whereSQL = Self.excludingSecondaries(" WHERE \(ghostClauseSQL)")
        let rows = try database.rows(
            "SELECT id FROM assets\(whereSQL) ORDER BY rowid ASC",
            bindings: [MetadataField.flag.rawValue]
        )
        return try rows.map(decodeAssetID)
    }
```

- [ ] **Step 2: Run the tests and verify they pass**

Run: `swift test --filter TeststripCoreTests.AutopilotGhostQueryTests`
Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 3: Verify the whole package still builds and the full suite is green**

Run: `swift build && swift test 2>&1 | tail -20`
Expected: build succeeds, 0 failures. No production code calls the new method yet, so nothing else can move.

- [ ] **Step 4: Commit**

```bash
git status
git add Sources/TeststripCore/Catalog/CatalogRepository.swift
git commit -m "feat: find ghost-carrying assets catalog-wide"
```

---

## Task 3A: Ghost-derived badges, review queue, sidebar, commit/dismiss — tests (test author)

**Files:**
- Test: `Tests/TeststripAppTests/AppModelTests.swift` (rewrite the autopilot region, currently `:5394-5890`)
- Test: `Tests/TeststripAppTests/CullSourcePresentationTests.swift` (`:55, 87-90`)
- Test: `Tests/TeststripAppTests/LibraryGridChromeTests.swift` (`:6-13`)

**Interfaces (what Task 3B must produce — write your tests against exactly these names):**
- `AppModel.autopilotGhostAssetIDs: [AssetID]` — `public private(set)`, the cached catalog-wide ghost set.
- `AppModel.autopilotGhostCount: Int` — `autopilotGhostAssetIDs.count`. Replaces `autopilotReviewProposalCount`.
- `AppModel.beginAutopilotReview() throws` — unchanged signature; loads the catalog-wide ghost set.
- `AppModel.commitAutopilotProposals(assetIDs: [AssetID]) throws -> Int` — unchanged signature; flags only.
- `AppModel.commitAllAutopilotProposals() throws -> Int` — unchanged signature.
- `AppModel.dismissAutopilotProposals(assetIDs: [AssetID]) throws -> Int` — unchanged signature; flags only; records `removed_ai_labels`.
- `AutopilotBadgePresentation.badge(for: PickFlag?) -> (text: String, isKeep: Bool)?` — type changed from `AutopilotProposalKind?`.
- `AppModel.autopilotProposalDecision(for:)` and `distinctPendingAutopilotProposalAssetIDs()` are **gone**; read the ghost with `AutopilotGhost.kind(in: try repository.asset(id: someID).metadata)`.

**You are the test author. Do not write any file under `Sources/`.** Your job is to make the semantic change falsifiable before anyone implements it.

- [ ] **Step 1: Read the region you are rewriting**

Read `Tests/TeststripAppTests/AppModelTests.swift:5394-5890` end to end and list, in your report, every existing test and whether you keep it, rewrite it, or delete it. The 17 tests in that region are:
`testRunAutopilotAppliesTentativeFlagsOnRun`, `testRunAutopilotAppliesTentativeFlagsCatalogOnlyNoSidecar`, `testRunAutopilotSkipsAssetWithUserConfirmedFlag`, `testUndoAutopilotRunRevertsTentativeWrites`, `testRunAutopilotOnCurrentScopeAppliesTentativeFlagsOnRun`, `testRunAutopilotOnFlatDistinctLibrarySurfacesKeywordOutcomeNotBareZero`, `testRunAutopilotOnCurrentScopeWithoutEvaluationsSetsStatusMessage`, `testBeginAutopilotReviewLoadsProposedAssets`, `testRunAutopilotIsIdempotentForTheSameScope`, `testCommitAllAutopilotProposalsConfirmsTentativeFlagsAsOneUndoGroup`, `testCommitAutopilotProposalsConfirmsTentativeKeyword`, `testCommitAllAutopilotProposalsSkipsDanglingProposalForMissingAsset`, `testUndoAutopilotRunRevertsMetadataAndRestoresPendingProposals`, `testUndoAutopilotRunPreservesInterveningUserEdits`, `testCommitAutopilotProposalsWritesConfirmedFlagToSidecar`, `testDismissAutopilotProposalsClearsTheirTentativeMetadata`.

Required dispositions (these are decisions, not suggestions):
- **Rewrite** `testRunAutopilotAppliesTentativeFlagsOnRun`, `testRunAutopilotOnCurrentScopeAppliesTentativeFlagsOnRun`, `testRunAutopilotSkipsAssetWithUserConfirmedFlag`, `testBeginAutopilotReviewLoadsProposedAssets`, `testRunAutopilotIsIdempotentForTheSameScope`, `testCommitAllAutopilotProposalsConfirmsTentativeFlagsAsOneUndoGroup`, `testCommitAllAutopilotProposalsSkipsDanglingProposalForMissingAsset`, `testDismissAutopilotProposalsClearsTheirTentativeMetadata` — replace `model.autopilotProposalDecision(for:)` / `model.autopilotReviewProposalCount` / `repository.autopilotProposals(...)` assertions with ghost assertions against `metadata_json` and `model.autopilotGhostAssetIDs`.
- **Delete** `testCommitAutopilotProposalsConfirmsTentativeKeyword`. Commit is flags-only now (spec decision 2: keywords "exit the review pipeline entirely"); the ambient-keyword confirm gesture is `confirmAIKeyword`, covered at `AppModelTests.swift:12980-12995`. Say so in your report — this is a deliberate coverage move, not a coverage loss, and the replacement `testAmbientAIKeywordsNeverEnterTheReviewQueue` below pins the new contract.
- **Keep unchanged**: `testRunAutopilotAppliesTentativeFlagsCatalogOnlyNoSidecar`, `testUndoAutopilotRunRevertsTentativeWrites`, `testUndoAutopilotRunPreservesInterveningUserEdits`, `testRunAutopilotOnFlatDistinctLibrarySurfacesKeywordOutcomeNotBareZero`, `testRunAutopilotOnCurrentScopeWithoutEvaluationsSetsStatusMessage`, `testCommitAutopilotProposalsWritesConfirmedFlagToSidecar`.
- **Leave for Task 5A**: `testUndoAutopilotRunRevertsMetadataAndRestoresPendingProposals` (its `pendingAutopilotProposals`/status assertions belong to the persistence-removal task). Do not touch it.

- [ ] **Step 2: Add the shared fixture helper**

Add this `private func` to the same test class, next to the other `makeModel…` helpers (`Tests/TeststripAppTests/AppModelTests.swift:19198`). It is the setup from `testRunAutopilotAppliesTentativeFlagsOnRun` (`:5394-5411`) lifted verbatim, so it uses only APIs that already exist: `makeAsset(id:path:rating:technicalMetadata:)` (`:18825`), `Self.technicalMetadata(capturedAt:)`, `makeModelWithCatalogAssets(named:assets:configureRepository:)` (`:19198`), and `selectSidebarTarget(.allPhotographs)`.

```swift
    // SP-D0 shared fixture: two evaluated near-dup frames run through
    // autopilot, so `alternate` carries a `.pick` ghost and `lead` a
    // `.reject` ghost.
    private func makeAutopilotModelWithGhosts(
        named name: String
    ) throws -> (model: AppModel, repository: CatalogRepository, lead: AssetID, alternate: AssetID) {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(
            id: "\(name)-lead",
            path: "/Photos/Job/\(name)-lead.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let alternate = makeAsset(
            id: "\(name)-alt",
            path: "/Photos/Job/\(name)-alt.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, repository) = try makeModelWithCatalogAssets(named: name, assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.30), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)
        _ = try model.runAutopilot(scope: .visible)
        return (model, repository, lead.id, alternate.id)
    }
```

- [ ] **Step 3: Add the new behavior tests**

Append these to the autopilot region of `Tests/TeststripAppTests/AppModelTests.swift`.

```swift
    // MARK: - SP-D0: gone is gone

    // The load-bearing behavior change. A direct user flag replaces the ghost;
    // pressing U afterwards returns the frame to neutral undecided. Nothing
    // resurrects — not the badge, not the review queue, not the sidebar count.
    func testDirectFlagThenClearLeavesNoGhostAnywhere() throws {
        let (model, repository, _, ghostAssetID) = try makeAutopilotModelWithGhosts(named: "ghost-gone-is-gone")
        XCTAssertNotNil(AutopilotGhost.kind(in: try repository.asset(id: ghostAssetID).metadata))

        model.select(ghostAssetID)
        try model.setFlagForSelectedAsset(.reject)

        // The override confirmed the flag: user origin, no ghost left.
        let overridden = try repository.asset(id: ghostAssetID).metadata
        XCTAssertEqual(overridden.flag, .reject)
        XCTAssertNil(AutopilotGhost.kind(in: overridden))
        XCTAssertEqual(overridden.confirmedProjection.flag, .reject)

        try model.setFlagForSelectedAsset(nil)

        // Neutral undecided. No flag, no ghost, no queue membership, no count.
        let cleared = try repository.asset(id: ghostAssetID).metadata
        XCTAssertNil(cleared.flag)
        XCTAssertNil(AutopilotGhost.kind(in: cleared))
        XCTAssertFalse(model.autopilotGhostAssetIDs.contains(ghostAssetID))
        XCTAssertFalse(try repository.assetIDsWithAutopilotGhost().contains(ghostAssetID))
        try model.beginAutopilotReview()
        XCTAssertFalse(model.assets.map(\.id).contains(ghostAssetID))
    }

    // U on a still-tentative ghost is the REMOVE gesture: the value is
    // recorded in removed_ai_labels so a later run can never resurrect it.
    func testClearingATentativeGhostRecordsItsRemovalAndSuppressesTheNextRun() throws {
        let (model, repository, _, ghostAssetID) = try makeAutopilotModelWithGhosts(named: "ghost-suppression")
        let ghostValue = try XCTUnwrap(AutopilotGhost.kind(in: try repository.asset(id: ghostAssetID).metadata))

        model.select(ghostAssetID)
        try model.setFlagForSelectedAsset(nil)

        XCTAssertTrue(
            try repository.removedAILabels(assetID: ghostAssetID)
                .contains(RemovedAILabel(field: .flag, value: ghostValue.rawValue))
        )
        XCTAssertNil(AutopilotGhost.kind(in: try repository.asset(id: ghostAssetID).metadata))

        // Never applied: the suppressed proposal produces no ghost at all, so
        // no count can be inflated by it.
        try model.runAutopilot(scope: .assetIDs([ghostAssetID]))

        XCTAssertNil(AutopilotGhost.kind(in: try repository.asset(id: ghostAssetID).metadata))
        XCTAssertFalse(model.autopilotGhostAssetIDs.contains(ghostAssetID))
        XCTAssertFalse(try repository.assetIDsWithAutopilotGhost().contains(ghostAssetID))
    }

    // MARK: - SP-D0: the review queue is catalog-wide and flags-only

    // The queue's universe is catalog-wide: narrowing the loaded scope to one
    // ghost must not shrink the review queue to one ghost.
    func testBeginAutopilotReviewLoadsGhostsOutsideTheLoadedScope() throws {
        let (model, repository, lead, alternate) = try makeAutopilotModelWithGhosts(named: "ghost-catalog-wide")
        let allGhostIDs = try repository.assetIDsWithAutopilotGhost()
        XCTAssertEqual(Set(allGhostIDs), Set([lead, alternate]))
        // Narrow the loaded scope through a real gesture: a one-asset manual
        // set. `applyAssetSet` replaces `model.assets` with just that member.
        let narrowSetID = AssetSetID(rawValue: "ghost-catalog-wide-narrow")
        try repository.upsert(AssetSet.manual(id: narrowSetID, name: "Narrow", assetIDs: [lead]))
        try model.applyAssetSet(id: narrowSetID)
        XCTAssertEqual(model.assets.map(\.id), [lead])

        try model.beginAutopilotReview()

        XCTAssertEqual(Set(model.assets.map(\.id)), Set(allGhostIDs))
        XCTAssertEqual(model.autopilotGhostCount, allGhostIDs.count)
        XCTAssertTrue(model.isAutopilotReviewActive)
    }

    func testAmbientAIKeywordsNeverEnterTheReviewQueue() throws {
        let (model, repository, lead, alternate) = try makeAutopilotModelWithGhosts(named: "ghost-ambient-keywords")
        // Turn `lead` into a keyword-only AI asset: no flag ghost, one ambient
        // AI keyword.
        try repository.updateMetadata(assetID: lead) { metadata in
            metadata.flag = nil
            metadata.aiUnconfirmedFields.remove(.flag)
            metadata.keywords.append("dog")
            metadata.aiUnconfirmedKeywords.insert("dog")
        }

        try model.beginAutopilotReview()

        XCTAssertEqual(model.assets.map(\.id), [alternate])
        XCTAssertFalse(model.autopilotGhostAssetIDs.contains(lead))
        // The ambient keyword itself is untouched — this spec changes nothing
        // about how keywords are applied, displayed, confirmed, or removed.
        XCTAssertTrue(try repository.asset(id: lead).metadata.keywords.contains("dog"))
        XCTAssertTrue(try repository.asset(id: lead).metadata.aiUnconfirmedKeywords.contains("dog"))
    }

    // MARK: - SP-D0: dismiss records the removal

    func testDismissRecordsRemovedAILabelSoNothingResurrects() throws {
        let (model, repository, _, ghostAssetID) = try makeAutopilotModelWithGhosts(named: "ghost-dismiss")
        let ghostValue = try XCTUnwrap(AutopilotGhost.kind(in: try repository.asset(id: ghostAssetID).metadata))

        let dismissed = try model.dismissAutopilotProposals(assetIDs: [ghostAssetID])

        XCTAssertEqual(dismissed, 1)
        XCTAssertNil(AutopilotGhost.kind(in: try repository.asset(id: ghostAssetID).metadata))
        XCTAssertTrue(
            try repository.removedAILabels(assetID: ghostAssetID)
                .contains(RemovedAILabel(field: .flag, value: ghostValue.rawValue))
        )
        // Dismiss writes no sidecar: nothing confirmed changed.
        let sidecarURL = try repository.asset(id: ghostAssetID).originalURL
            .appendingPathExtension("xmp")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path))
    }

    // MARK: - SP-D0: the sidebar source is derived from ghosts

    func testSidebarAutopilotSourceAppearsOnlyWhileGhostsExist() throws {
        let (model, _, _, _) = try makeAutopilotModelWithGhosts(named: "ghost-sidebar-source")
        let ghostIDs = model.autopilotGhostAssetIDs
        XCTAssertFalse(ghostIDs.isEmpty)

        let source = try XCTUnwrap(
            model.cullSourcePresentation.sources.first { $0.target == CullSource.Target.autopilotProposals }
        )
        XCTAssertEqual(source.count, ghostIDs.count)

        _ = try model.dismissAutopilotProposals(assetIDs: ghostIDs)

        XCTAssertTrue(model.autopilotGhostAssetIDs.isEmpty)
        XCTAssertFalse(
            model.cullSourcePresentation.sources.contains { $0.target == CullSource.Target.autopilotProposals }
        )
    }
```

**Verified APIs used above** (do not invent alternatives): `AppModel.select(_:)` is public at `Sources/TeststripApp/AppModel.swift:4808` — `selectAssetID(_:)` at `:4858` is **private** and unavailable to tests. `AppModel.applyAssetSet(id:)` is public at `:5470`. `AssetSet.manual(id:name:assetIDs:)` is the factory used at `AppModel.swift:5842`. `CatalogRepository.updateMetadata(assetID:_:)` and `removedAILabels(assetID:)` are public (`CatalogRepository.swift:1819`). If `applyAssetSet` turns out not to replace `model.assets` with exactly the set's members, drop `testBeginAutopilotReviewLoadsGhostsOutsideTheLoadedScope` and report that the catalog-wide guarantee rests on `AutopilotGhostQueryTests` plus scenario card cull-029 — **do not add a test-only hook to `AppModel`.**

- [ ] **Step 4: Update the two small presentation test files**

In `Tests/TeststripAppTests/LibraryGridChromeTests.swift`, delete line `:11` (`XCTAssertNil(AutopilotBadgePresentation.badge(for: .keyword))`) — `.keyword` is not a `PickFlag`. Leave the other four assertions; they compile unchanged against `PickFlag?`. Add:

```swift
        // The badge reads the ghost's own value; there is no third kind that
        // could reach this surface.
        XCTAssertNil(AutopilotBadgePresentation.badge(for: PickFlag?.none))
```

In `Tests/TeststripAppTests/CullSourcePresentationTests.swift:90`, change
`XCTAssertEqual(proposalsSource.count, model.pendingAutopilotProposals.count)` to
`XCTAssertEqual(proposalsSource.count, model.autopilotGhostAssetIDs.count)`.

- [ ] **Step 5: Run the tests and verify they fail for the right reasons**

Run: `swift test --filter TeststripAppTests 2>&1 | tail -60`

Expected: compile failures naming `autopilotGhostAssetIDs`, `autopilotGhostCount`, and `assetIDsWithAutopilotGhost` on `AppModel`, plus `cannot convert value of type 'AutopilotProposalKind?'` if you changed the badge assertions. These are genuine reds.

- [ ] **Step 6: Falsification red proof for the tests that would pass against current behavior**

Three of your assertions describe behavior the tree already has. Prove each is load-bearing by breaking the implementation, running, capturing the failure, and reverting. Do these **one at a time**, reverting fully between each.

1. **Suppression skip rule.** In `Sources/TeststripApp/AppModel.swift`, inside `applyTentativeAutopilotProposals`, delete the clause
   `!removedLabels.contains(RemovedAILabel(field: .flag, value: flagValue.rawValue))`
   from the `guard` at `:9735-9738`. Run `swift test --filter TeststripAppTests.AppModelTests/testClearingATentativeGhostRecordsItsRemovalAndSuppressesTheNextRun`. Expected: the post-run ghost assertion fails. Capture the output. `git checkout -- Sources/TeststripApp/AppModel.swift`.
2. **Ghosts are catalog-only (no sidecar).** In `applyTentativeAutopilotProposals`, replace
   `try catalog.repository.updateMetadata(assetID: assetID) { $0 = updatedMetadata }` (`:9754`)
   with `try applyMetadataSnapshot(assetID: assetID, metadata: updatedMetadata)`. Run `swift test --filter TeststripAppTests.AppModelTests/testRunAutopilotAppliesTentativeFlagsCatalogOnlyNoSidecar`. Expected: the sidecar-absence assertion fails. Capture. Revert.
3. **Commit writes the sidecar.** In `commitAutopilotProposals`, replace the `applyMetadataSnapshot(...)` call (`:9922`) with `try catalog.repository.updateMetadata(assetID: assetID) { $0 = updatedMetadata }`. Run `swift test --filter TeststripAppTests.AppModelTests/testCommitAutopilotProposalsWritesConfirmedFlagToSidecar`. Expected: the sidecar-existence assertion fails. Capture. Revert.

Verify you reverted cleanly: `git diff --stat -- Sources/` must be empty before you commit.

- [ ] **Step 7: Capture every red transcript into your task report**

Report must contain: the Step 5 compile-failure transcript, and the three Step 6 falsification transcripts each with the named break, the failing assertion, and confirmation of the revert.

- [ ] **Step 8: Commit**

```bash
git status
git add Tests/TeststripAppTests/AppModelTests.swift Tests/TeststripAppTests/CullSourcePresentationTests.swift Tests/TeststripAppTests/LibraryGridChromeTests.swift
git commit -m "test: pin ghost-derived badges, review queue, sidebar, and dismiss-records-removal (red)"
```

---

## Task 3B: Ghost-derived badges, review queue, sidebar, commit/dismiss — implementation

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift`

**Interfaces:**
- Consumes: `AutopilotGhost.kind(in:)` (Task 1B), `CatalogRepository.assetIDsWithAutopilotGhost()` (Task 2B).
- Produces: everything listed in Task 3A's Interfaces block. Task 4 and Task 5 build on `refreshCatalogSidebarCounts()` being the ghost-cache funnel.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.**

- [ ] **Step 1: Add the ghost cache and its refresh**

In `Sources/TeststripApp/AppModel.swift`, immediately after `public private(set) var pendingAutopilotProposals: [AutopilotProposal] = []` (`:2252`), add:

```swift
    /// The catalog-wide set of assets carrying an autopilot ghost — derived,
    /// never stored. Backs the Cull sidebar's "Autopilot Proposals" source and
    /// its count; refreshed through `refreshCatalogSidebarCounts()`, the same
    /// funnel that maintains `reviewQueueCounts`.
    public private(set) var autopilotGhostAssetIDs: [AssetID] = []
```

Add this private helper next to `refreshCatalogSidebarCounts()` (`:13305`):

```swift
    private func refreshAutopilotGhostAssetIDs() throws {
        guard let catalog else { return }
        autopilotGhostAssetIDs = try catalog.repository.assetIDsWithAutopilotGhost()
    }
```

and call it from `refreshCatalogSidebarCounts()`, after the `reviewQueueCounts` line:

```swift
    private func refreshCatalogSidebarCounts() throws {
        guard let catalog else { return }
        reviewQueueCounts = try Self.reviewQueueCounts(repository: catalog.repository)
        try refreshAutopilotGhostAssetIDs()
        assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        refreshLatestImportPresentation()
        rebuildSidebarSections()
    }
```

- [ ] **Step 2: Populate the cache at load**

In the static `load(...)` path, immediately **after** `try model.reconstructAutopilotStateAfterLoad()` (`:4720`), add:

```swift
        try model.refreshAutopilotGhostAssetIDs()
```

(Task 5B deletes the `reconstructAutopilotStateAfterLoad()` line above it; this one stays.)

- [ ] **Step 3: Close the two sidebar-count refresh gaps**

At the end of `removeAIField(_:for:)` (`:8393-8417`), after `try refreshInMemoryAsset(assetID)`, add:

```swift
        // Clearing an AI label changes catalog-derived counts (the ghost set,
        // and the likely-pick queue that keys off a null flag), so the sidebar
        // has to be told — the confirmed-write path already does this via
        // `applyMetadataSnapshot`.
        try refreshCatalogSidebarCounts()
```

In `runAutopilot(scope:)`, replace
`pendingAutopilotProposals = (try? catalog.repository.autopilotProposals(status: .pending)) ?? []` (`:9702`)
with:

```swift
        try refreshCatalogSidebarCounts()
```

- [ ] **Step 4: Derive the sidebar source from ghosts**

In `cullSourcePresentation` (`:5885-5896`), replace the block with:

```swift
        // The confirm-before-write review path for machine labels: present
        // only while ghosts exist so it never renders as a dead row.
        if !autopilotGhostAssetIDs.isEmpty {
            sources.append(CullSource(
                id: "autopilot-proposals",
                group: .autopilotProposals,
                title: "Autopilot Proposals",
                systemImage: "wand.and.stars",
                count: autopilotGhostAssetIDs.count,
                target: .autopilotProposals
            ))
        }
```

- [ ] **Step 5: Rewrite the review-surface methods**

Delete `autopilotProposalDecision(for:)` (`:9824-9828`) and `distinctPendingAutopilotProposalAssetIDs()` (`:9855-9862`) outright.

Replace `autopilotReviewProposalCount` (`:9834-9836`) with:

```swift
    public var autopilotGhostCount: Int {
        autopilotGhostAssetIDs.count
    }
```

Replace `beginAutopilotReview()` (`:9838-9853`, doc comment included) with:

```swift
    /// Narrows the grid to just the assets carrying an autopilot ghost so the
    /// user can review the provisional keeps/cuts (KEEP/CUT badges stay
    /// visible) and commit or dismiss them. The universe is catalog-wide, not
    /// the loaded scope — the review queue must never silently shrink to
    /// whatever the grid happens to hold. Reads only; writes nothing.
    public func beginAutopilotReview() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetIDs = try catalog.repository.assetIDsWithAutopilotGhost()
        autopilotGhostAssetIDs = assetIDs
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        let loadedAssets = try catalog.repository.assets(ids: assetIDs, limit: assetIDs.count)
        replaceAssets(loadedAssets)
        totalAssetCount = try catalog.repository.assetCount(ids: assetIDs)
        isAutopilotReviewActive = true
        selectedView = .grid
    }
```

Replace `commitAutopilotProposals(assetIDs:)` (`:9864-9942`, doc comment included) with:

```swift
    /// Confirms the ghosts on the given assets: each one's tentative
    /// pick/reject is already sitting in `metadata_json` as AI-unconfirmed
    /// (`applyTentativeAutopilotProposals`, run time) — commit graduates it to
    /// confirmed by clearing `.flag` from `aiUnconfirmedFields`, through the
    /// grouped-undo, sidecar-syncing metadata path (`applyMetadataSnapshot`)
    /// as ONE undo group labeled "Autopilot" (the same generic Cmd+Z path
    /// `confirmAIField` feeds for a single asset — batched here since
    /// committing is a multi-asset gesture). This is the explicit user gesture
    /// that makes a tentative autopilot decision portable to the XMP sidecar.
    /// Flags only: ambient AI keywords never enter review and are confirmed
    /// from the Inspector instead.
    @discardableResult
    public func commitAutopilotProposals(assetIDs: [AssetID]) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        var changes: [MetadataChange] = []
        var missingAssetCount = 0
        for assetID in assetIDs {
            let originalAsset: Asset
            do {
                originalAsset = try catalog.repository.asset(id: assetID)
            } catch CatalogError.notFound {
                // The asset was trashed/deleted after the run. Keep committing
                // the rest of the batch rather than aborting.
                missingAssetCount += 1
                continue
            }
            guard AutopilotGhost.kind(in: originalAsset.metadata) != nil else { continue }
            var updatedMetadata = originalAsset.metadata
            updatedMetadata.aiUnconfirmedFields.remove(.flag)
            try applyMetadataSnapshot(assetID: assetID, metadata: updatedMetadata)
            changes.append(MetadataChange(
                assetID: assetID,
                before: originalAsset.metadata,
                after: updatedMetadata
            ))
        }
        guard !changes.isEmpty || missingAssetCount > 0 else { return 0 }
        recordMetadataChangeGroup(label: "Autopilot", changes: changes)
        statusMessage = missingAssetCount == 0
            ? "Committed \(changes.count) autopilot decisions"
            : "Committed \(changes.count) autopilot decisions (\(missingAssetCount) skipped — asset no longer available)"
        return changes.count
    }
```

Replace `commitAllAutopilotProposals()` (`:9944-9947`) with:

```swift
    @discardableResult
    public func commitAllAutopilotProposals() throws -> Int {
        try commitAutopilotProposals(assetIDs: autopilotGhostAssetIDs)
    }
```

Replace `dismissAutopilotProposals(assetIDs:)` (`:9949-9988`, doc comment included) with:

```swift
    /// Dismisses the ghosts on the given assets: the tentative pick/reject is
    /// cleared from `metadata_json` and its specific value recorded in
    /// `removed_ai_labels`, so a later run can never resurrect it — the same
    /// recorded-removal gesture `U` on a ✨ flag uses (`removeAIField`).
    /// Catalog-only: a value that was never confirmed has no sidecar
    /// projection to update. Flags only, same as commit.
    @discardableResult
    public func dismissAutopilotProposals(assetIDs: [AssetID]) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        var dismissedCount = 0
        for assetID in assetIDs {
            let metadata: AssetMetadata
            do {
                metadata = try catalog.repository.asset(id: assetID).metadata
            } catch CatalogError.notFound {
                continue
            }
            guard AutopilotGhost.kind(in: metadata) != nil else { continue }
            try removeAIField(.flag, for: assetID)
            dismissedCount += 1
        }
        guard dismissedCount > 0 else { return 0 }
        statusMessage = "Dismissed \(dismissedCount) proposals"
        return dismissedCount
    }
```

- [ ] **Step 6: Point the badge surface at the ghost**

In `Sources/TeststripApp/LibraryGridView.swift`:

Replace `AutopilotBadgePresentation` (`:3605-3618`) with:

```swift
struct AutopilotBadgePresentation: Equatable {
    // Maps the ghost's own value to the grid cell's KEEP/CUT badge. An asset
    // with no ghost carries no badge.
    static func badge(for ghost: PickFlag?) -> (text: String, isKeep: Bool)? {
        switch ghost {
        case .pick:
            return (text: "KEEP", isKeep: true)
        case .reject:
            return (text: "CUT", isKeep: false)
        case nil:
            return nil
        }
    }
}
```

Change `AssetGridCell`'s stored property (`:9670`) from
`var autopilotDecision: AutopilotProposalKind? = nil` to
`var autopilotDecision: PickFlag? = nil`.

Change `AssetGridCellAccessibilityValue.value`'s parameter (`:8335`) from
`autopilotDecision: AutopilotProposalKind?` to
`autopilotDecision: PickFlag?`.

At all three call sites — `:2370`, `:7690`, `:8147` — replace
`model.autopilotProposalDecision(for: asset.id)` with
`AutopilotGhost.kind(in: asset.metadata)`.

In the review toolbar, replace `model.autopilotReviewProposalCount` at `:2523` and `:2534` with `model.autopilotGhostCount`. **Leave the visible strings byte-identical** (`"Reviewing \(…) proposals"`, `"Commit all \(…)"`) — the copy is not part of this spec.

- [ ] **Step 7: Build and run the scoped tests**

Run: `swift build`
Expected: succeeds. If it does not, the most likely cause is a missed `pendingAutopilotProposals` reader — `grep -n "pendingAutopilotProposals" Sources/TeststripApp/*.swift` should now show only the property declaration (`:2252`) and its remaining writers in `undoAutopilotRun` / `reconstructAutopilotStateAfterLoad`, plus the completion partition in `LibraryGridView.swift` (Task 4 removes that one).

Run: `swift test --filter TeststripAppTests 2>&1 | tail -30`
Expected: 0 failures.

- [ ] **Step 8: Run the whole suite**

Run: `swift test 2>&1 | tail -20`
Expected: 0 failures.

- [ ] **Step 9: Commit**

```bash
git status
git add Sources/TeststripApp/AppModel.swift Sources/TeststripApp/LibraryGridView.swift
git commit -m "feat: derive badges, review queue, and the sidebar source from the ghost"
```

---

## Task 4A: Completion summary drops the ✨ ink — tests (test author)

**Files:**
- Test: `Tests/TeststripAppTests/CullCompletionTests.swift`

**Interfaces (what Task 4B must produce):**
- `CullCompletionPresentation` loses the `sparkleAwaiting: Int` stored property and the `.reviewAISuggestions` case of `Action`.
- `static func summary(assets:viewedAssetIDs:skippedAssetIDs:) -> CullCompletionPresentation` — both pending-ID parameters removed.
- `static func presentation(assets:viewedAssetIDs:skippedAssetIDs:scope:) -> CullCompletionPresentation?` — both pending-ID parameters removed.

**You are the test author. Do not write any file under `Sources/`.**

- [ ] **Step 1: Delete the tests that only existed to describe the ✨ ink**

Delete these from `Tests/TeststripAppTests/CullCompletionTests.swift` in full, along with the two `// MARK: - sparkleAwaiting …` headers at `:174` and `:232`:
`testSparkleAwaitingExcludesAssetWithPendingProposalAndConfirmedFlag` (`:182`), `testSparkleAwaitingStillCountsAssetWithPendingProposalAndTentativeOnlyFlag` (`:200`), `testSparkleAwaitingCountsOnlyTheUserUndecidedSubsetOfPendingProposals` (`:215`), `testSparkleAwaitingCountsPendingKeywordProposalEvenWithConfirmedFlag` (`:241`), `testSparkleAwaitingStillExcludesPendingFlagProposalWithConfirmedFlag` (`:257`), `testSparkleAwaitingCountsMixedFlagAndKeywordProposalsExactly` (`:273`), `testActionsOmitReviewAISuggestionsWhenTheOnlyPendingAssetIsUserDecided` (`:350`).

These describe the kata-4 display filter, which the spec deletes ("The kata-4 kind-aware display filter and the completion call site's kind partition"). Record the deletion and its justification in your report.

- [ ] **Step 2: Update the surviving tests to the new signatures**

Remove `pendingFlagProposalAssetIDs:` and `pendingKeywordProposalAssetIDs:` from every remaining `summary(...)` / `presentation(...)` call in the file (`:19-20, 31-32, 44-45, 63-64, 83-84, 113-114, 137-138, 154-155, 166-167, 307-308, 327-328, 340-341, 359-360, 407-408`), and drop the `sparkleAwaiting` assertions at `:124, 160, 317`.

Rename `testSummaryCountsClassifyScopeAgainstTrackerAndProposals` (`:97`) to `testSummaryCountsClassifyScopeAgainstTracker` and drop its now-meaningless out-of-scope proposal id.

Rename `testTentativeOnlyFlagCountsAsUndecidedAndSparkleAwaitingNeverPickedOrRejected` (`:147`) to `testTentativeOnlyFlagCountsAsUndecidedNeverPickedOrRejected` and keep its undecided/picked/rejected assertions — the tentative-counts-as-undecided invariant survives untouched.

- [ ] **Step 3: Add the new negative tests**

```swift
    // MARK: - SP-D0: no ✨ ink at completion

    // The completion summary is purely about the user's decisions. A scope
    // full of ghosts offers exactly the same ceremonies as one with none —
    // review stays reachable mid-run from the sidebar source and the banner.
    func testCompletionOffersNoReviewAISuggestionsCeremonyWithOrWithoutGhosts() {
        let withGhosts = [
            Self.asset(id: "ghost-pick", flag: .pick),
            Self.asset(id: "ghost-tentative", flag: .reject, tentative: true)
        ]
        let withoutGhosts = [
            Self.asset(id: "plain-pick", flag: .pick),
            Self.asset(id: "plain-reject", flag: .reject)
        ]

        for assets in [withGhosts, withoutGhosts] {
            let summary = CullCompletionPresentation.summary(
                assets: assets,
                viewedAssetIDs: Set(assets.map(\.id)),
                skippedAssetIDs: []
            )
            XCTAssertEqual(
                summary.actions,
                [.export, .moveRejects, .moveRejectsToTrash, .reviewPicks, .savePicksAsSet]
            )
        }
    }

    // A ghost is undecided, so a scope carrying one is not complete at all —
    // the summary is suppressed, and there is no ✨ row to be honest about.
    func testCompletionIsSuppressedWhileAGhostLeavesTheScopeUndecided() {
        let assets = [
            Self.asset(id: "decided", flag: .pick),
            Self.asset(id: "ghost", flag: .reject, tentative: true)
        ]

        let presentation = CullCompletionPresentation.presentation(
            assets: assets,
            viewedAssetIDs: Set(assets.map(\.id)),
            skippedAssetIDs: [],
            scope: .all
        )

        XCTAssertNil(presentation)
    }
```

`Self.asset(id:flag:tentative:)` is the file's existing private factory at `Tests/TeststripAppTests/CullCompletionTests.swift:523-537` — `tentative: true` sets `aiUnconfirmedFields = [.flag]`. Do not add a new factory.

- [ ] **Step 4: Run the tests and verify they fail for the right reason**

Run: `swift test --filter TeststripAppTests.CullCompletionTests 2>&1 | tail -40`
Expected: compile failure — `extra argument 'scope' in call` / `incorrect argument labels` on the reduced signatures, and `type 'CullCompletionPresentation.Action' has no member 'reviewAISuggestions'` is *not* yet reported because the case still exists. The load-bearing red is the `actions` equality in `testCompletionOffersNoReviewAISuggestionsCeremonyWithOrWithoutGhosts`, which cannot even be reached until the signature changes. Genuine red; no falsification needed.

- [ ] **Step 5: Capture the red transcript into your task report**

- [ ] **Step 6: Commit**

```bash
git status
git add Tests/TeststripAppTests/CullCompletionTests.swift
git commit -m "test: completion carries no AI-suggestion ink (red)"
```

---

## Task 4B: Completion summary drops the ✨ ink — implementation

**Files:**
- Modify: `Sources/TeststripApp/CullCompletionPresentation.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`:3842-3865`, `:3873-3885`, `:4042-4044`, `:4053-4058`)

**Interfaces:**
- Consumes: nothing new.
- Produces: the reduced `CullCompletionPresentation` API in Task 4A's Interfaces block. After this task, `AppModel.pendingAutopilotProposals` has **no readers left**, which is what makes Task 5 possible.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.**

- [ ] **Step 1: Reduce `CullCompletionPresentation`**

In `Sources/TeststripApp/CullCompletionPresentation.swift`:

Update the type doc comment (`:3-7`) to:

```swift
/// The stage-replacing state shown in the cull loupe once nothing is left
/// undecided in the session: a handoff offering the next move (export,
/// relocate rejects, review picks, or save the picks as a set) instead of an
/// empty stage, plus the run's quality-of-coverage counts (skipped, never
/// viewed). Purely about the user's decisions — machine suggestions are
/// ambient and never nag from here.
```

Delete the `case reviewAISuggestions` from `Action` (`:14`) and the `var sparkleAwaiting: Int` property (`:23`).

Replace `summary(...)` (`:26-101`, doc comment included) with:

```swift
    /// The run-summary math, ungated: classifies every frame in the scope by
    /// its CONFIRMED flag — a tentative (AI-unconfirmed) flag counts as
    /// undecided and never as a pick/reject (the provenance invariant), so a
    /// scope still carrying a ghost is not complete and never reaches here.
    /// skipped = skipped ∖ decided (a skipped-then-decided frame counts as
    /// decided, subtracted here so the tracker never needs a write-back);
    /// neverViewed = scope ∖ viewed.
    static func summary(
        assets: [Asset],
        viewedAssetIDs: Set<AssetID>,
        skippedAssetIDs: Set<AssetID>
    ) -> CullCompletionPresentation {
        var pickCount = 0
        var rejectCount = 0
        var undecidedCount = 0
        var neverViewedCount = 0
        var decidedAssetIDs: Set<AssetID> = []
        for asset in assets {
            switch asset.metadata.confirmedProjection.flag {
            case .pick:
                pickCount += 1
                decidedAssetIDs.insert(asset.id)
            case .reject:
                rejectCount += 1
                decidedAssetIDs.insert(asset.id)
            case nil:
                undecidedCount += 1
            }
            if !viewedAssetIDs.contains(asset.id) {
                neverViewedCount += 1
            }
        }
        let scopeAssetIDs = Set(assets.map(\.id))
        let skippedCount = skippedAssetIDs
            .intersection(scopeAssetIDs)
            .subtracting(decidedAssetIDs)
            .count
        // The core four always; Save Picks only when it has work to do — a
        // Save Picks row with no picks would be a dead control.
        var actions: [Action] = [.export, .moveRejects, .moveRejectsToTrash, .reviewPicks]
        if pickCount > 0 {
            actions.append(.savePicksAsSet)
        }
        return CullCompletionPresentation(
            picks: pickCount,
            rejects: rejectCount,
            undecided: undecidedCount,
            skipped: skippedCount,
            neverViewed: neverViewedCount,
            actions: actions
        )
    }
```

In `presentation(...)` (`:113-132`), delete both pending-ID parameters from the signature and from the inner `summary(...)` call. Leave the `scope` guard and the `undecided == 0` guard exactly as they are.

- [ ] **Step 2: Simplify the completion call site**

In `Sources/TeststripApp/LibraryGridView.swift`, replace `cullCompletion` (`:3837-3865`, comment included) with:

```swift
    // Nil unless the loupe is in cull chrome, nothing in the session is
    // left unflagged, the session isn't empty, and the scope is a deciding
    // scope (unrated/all — the picks/rejects review scopes never show it);
    // also suppressed once the user dismisses it for the current
    // asset/scope.
    private var cullCompletion: CullCompletionPresentation? {
        guard !isCullCompletionDismissed else { return nil }
        return CullCompletionPresentation.presentation(
            assets: model.assets,
            viewedAssetIDs: model.cullRunTracker.viewedAssetIDs,
            skippedAssetIDs: model.cullRunTracker.skippedAssetIDs,
            scope: model.cullScope
        )
    }
```

- [ ] **Step 3: Drop the ✨ segment from the detail line**

Replace `cullCompletionRunDetailText` (`:4053-4058`) with:

```swift
    private func cullCompletionRunDetailText(_ completion: CullCompletionPresentation) -> String {
        "\(completion.skipped) skipped · \(completion.neverViewed) never viewed"
    }
```

Update the comment above the detail-line `Text` (`:3989-3991`) to:

```swift
            // The run-coverage row: what "done" glossed over — frames Space
            // skipped (and never decided) and frames the run never landed on.
```

- [ ] **Step 4: Drop the ceremony button and its stale banner comment**

Delete the `case .reviewAISuggestions:` arm from `cullCompletionActionButton` (`:4042-4044`).

Replace the banner comment (`:3873-3885`) with:

```swift
                // An undismissed autopilot banner (with its own Review/Undo
                // All buttons) reappears inside `cullCompletionStage` once
                // completion takes over above the stage — gated on
                // `model.autopilotRunSummary`, same as here — so its review
                // affordance survives completion. Once the banner IS
                // dismissed, review stays reachable from the Cull sidebar's
                // "Autopilot Proposals" source; the completion stage carries
                // no AI-suggestion ceremony of its own.
```

`reviewAutopilotRun()` (`:3957-3963`) stays — the folded banner still calls it.

- [ ] **Step 5: Build and run the scoped tests**

Run: `swift build`
Expected: succeeds.

Run: `swift test --filter TeststripAppTests.CullCompletionTests`
Expected: 0 failures.

- [ ] **Step 6: Confirm `pendingAutopilotProposals` now has no readers**

Run: `grep -rn "pendingAutopilotProposals" Sources/`
Expected: only the declaration at `AppModel.swift:2252` and its three assignment sites (`undoAutopilotRun`, `reconstructAutopilotStateAfterLoad`). If any *read* remains, stop and report it — Task 5 depends on this being clean.

- [ ] **Step 7: Run the whole suite**

Run: `swift test 2>&1 | tail -20`
Expected: 0 failures.

- [ ] **Step 8: Commit**

```bash
git status
git add Sources/TeststripApp/CullCompletionPresentation.swift Sources/TeststripApp/LibraryGridView.swift
git commit -m "feat: completion summary reports only the user's decisions"
```

---

## Task 5A: Stop persisting proposals, drop the undo status flip — tests (test author)

**Files:**
- Test: `Tests/TeststripAppTests/AppModelTests.swift`
- Test: `Tests/TeststripAppTests/AppModelSessionRestoreTests.swift`

**Interfaces (what Task 5B must produce):**
- `AppModel.pendingAutopilotProposals`, `AppModel.lastAutopilotRunIDByScopeKey`, and `AppModel.reconstructAutopilotStateAfterLoad()` no longer exist.
- `runAutopilot(scope:)` writes no rows to `autopilot_proposals`.
- `undoAutopilotRun()` replays only the in-memory `AutopilotTentativeChangeGroup`; it touches no table.

**You are the test author. Do not write any file under `Sources/`.**

- [ ] **Step 1: Rewrite `testUndoAutopilotRunRevertsMetadataAndRestoresPendingProposals`** (in `Tests/TeststripAppTests/AppModelTests.swift`)

Currently at `Tests/TeststripAppTests/AppModelTests.swift:5747-5779`. Rename it `testUndoAutopilotRunRevertsMetadataAndRestoresGhosts`, delete its `pendingAutopilotProposals` / `autopilotProposals(status:)` assertions, and assert the ghost instead:

```swift
        try model.undoAutopilotRun()

        // The run's tentative writes are gone from metadata, so the ghosts
        // they created are gone with them — nothing else records their
        // existence.
        XCTAssertNil(AutopilotGhost.kind(in: try repository.asset(id: lead.id).metadata))
        XCTAssertNil(AutopilotGhost.kind(in: try repository.asset(id: alternate.id).metadata))
        XCTAssertTrue(model.autopilotGhostAssetIDs.isEmpty)
        XCTAssertFalse(model.canUndoAutopilotRun)
```

Keep the rest of the test's setup and its merge-aware assertions byte-for-byte.

- [ ] **Step 2: Add the no-persistence test**

```swift
    // SP-D0: nothing persists a proposal. The ghost in metadata_json is the
    // only record a run leaves behind.
    func testRunAutopilotPersistsNoProposals() throws {
        let (model, repository, _, _) = try makeAutopilotModelWithGhosts(named: "ghost-no-persistence")

        XCTAssertFalse(model.autopilotGhostAssetIDs.isEmpty, "fixture must produce at least one ghost")
        XCTAssertEqual(try repository.autopilotProposals(status: .pending), [])
        XCTAssertEqual(try repository.autopilotProposals(status: .committed), [])
        XCTAssertEqual(try repository.autopilotProposals(status: .dismissed), [])
    }
```

This uses the repository API that still exists at this point in the plan. **Task 6 deletes this test along with the API** — its guarantee becomes structural once the API and the table are gone, and Task 7 asserts the table's absence directly. Note that hand-off explicitly in your report.

- [ ] **Step 3: Add the two relaunch tests**

These go in `Tests/TeststripAppTests/AppModelSessionRestoreTests.swift`, which already owns the reopen pattern: `makeTemporaryDirectory(named:)` → `makeCatalog(directory:)` → `AppModel.load(catalog:sessionRestoreDefaults:)`, twice against the same directory (`:7-26`). Reuse its `makeIsolatedDefaults()`, `makeCatalog(directory:)`, and `makeAsset(id:filename:rating:)` helpers verbatim.

```swift
    // SP-D0: ghost badges survive relaunch natively — the unconfirmed AI flag
    // lives in metadata_json, so nothing has to be reconstructed for them.
    func testGhostsSurviveRelaunch() throws {
        let directory = try makeTemporaryDirectory(named: "restore-ghosts")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        var ghostAsset = makeAsset(id: "ghost-1", filename: "ghost-1.dng")
        ghostAsset.metadata.flag = .pick
        ghostAsset.metadata.aiUnconfirmedFields = [.flag]
        let plainAsset = makeAsset(id: "plain-1", filename: "plain-1.dng")
        try catalogA.repository.upsert([ghostAsset, plainAsset])
        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        XCTAssertEqual(modelA.autopilotGhostAssetIDs, [ghostAsset.id])

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.autopilotGhostAssetIDs, [ghostAsset.id])
        XCTAssertEqual(
            AutopilotGhost.kind(in: try catalogB.repository.asset(id: ghostAsset.id).metadata),
            .pick
        )
    }

    // SP-D0: the autopilot banner is run-time only. It used to be rebuilt at
    // load from pending proposal rows (its Undo button was already dead by
    // then); nothing reconstructs it now.
    func testAutopilotBannerDoesNotSurviveRelaunch() throws {
        let directory = try makeTemporaryDirectory(named: "restore-autopilot-banner")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        var ghostAsset = makeAsset(id: "ghost-1", filename: "ghost-1.dng")
        ghostAsset.metadata.flag = .pick
        ghostAsset.metadata.aiUnconfirmedFields = [.flag]
        try catalogA.repository.upsert([ghostAsset])
        // A stale pending proposal row, exactly what a pre-SP-D0 catalog holds.
        try catalogA.repository.save([AutopilotProposal(
            id: AutopilotProposalID(rawValue: "p-1"),
            runID: AutopilotRunID(rawValue: "run-1"),
            assetID: ghostAsset.id,
            kind: .pick,
            keyword: nil,
            rationale: "Sharpest frame in its burst",
            confidence: 0.82,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )])

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertNil(modelB.autopilotRunSummary)
        // The ghost is unaffected by the row's presence or absence.
        XCTAssertEqual(modelB.autopilotGhostAssetIDs, [ghostAsset.id])
    }
```

`testAutopilotBannerDoesNotSurviveRelaunch` uses `repository.save(_:)` and `AutopilotProposalStatus`, both of which **Task 6 deletes** — Task 6 deletes this test with them, and the guarantee is then structural (`reconstructAutopilotStateAfterLoad` no longer exists) plus covered live by cull-029 step 7. Say so in your report.

If `AppModel.load(catalog:sessionRestoreDefaults:)` does not accept this exact argument list, copy the call verbatim from `AppModelSessionRestoreTests.swift:12`. If `CatalogRepository.upsert` takes a single asset rather than an array here, adjust — check `Sources/TeststripCore/Catalog/CatalogRepository.swift` for the overload the file already uses.

- [ ] **Step 4: Run and verify the reds**

Run: `swift test --filter TeststripAppTests 2>&1 | tail -40`
Expected: `testRunAutopilotPersistsNoProposals` **fails** with three non-empty proposal arrays (the run still saves today); `testAutopilotBannerDoesNotSurviveRelaunch` **fails** on `XCTAssertNil(modelB.autopilotRunSummary)` (today `reconstructAutopilotStateAfterLoad` rebuilds it from the pending row). Both are genuine reds.

`testGhostsSurviveRelaunch` and `testUndoAutopilotRunRevertsMetadataAndRestoresGhosts` will pass immediately. Falsify both:

- [ ] **Step 5: Falsification red proofs for the two tests that pass against current behavior**

**(a) Ghost survival across relaunch.** In `Sources/TeststripApp/AppModel.swift`, comment out the `try model.refreshAutopilotGhostAssetIDs()` line in the static `load(...)` path (added in Task 3B, just after `reconstructAutopilotStateAfterLoad()`). Run `swift test --filter TeststripAppTests.AppModelSessionRestoreTests/testGhostsSurviveRelaunch`. Expected: `XCTAssertEqual(modelA.autopilotGhostAssetIDs, [ghostAsset.id])` fails with `[]`. Capture. `git checkout -- Sources/TeststripApp/AppModel.swift`.

**(b) Undo reverts the ghost.**

In `Sources/TeststripApp/AppModel.swift`, inside `revertAutopilotTentativeChange`, change the flag arm (`:10054-10056`) from

```swift
                case .flag:
                    guard metadata.flag == change.after.flag else { continue }
                    metadata.flag = change.before.flag
```

to

```swift
                case .flag:
                    continue
```

Run `swift test --filter TeststripAppTests.AppModelTests/testUndoAutopilotRunRevertsMetadataAndRestoresGhosts`. Expected: the `AutopilotGhost.kind(...)` assertions fail because the ghost is still there. Capture the output. Then `git checkout -- Sources/TeststripApp/AppModel.swift` and confirm `git diff --stat -- Sources/` is empty.

- [ ] **Step 6: Capture every red transcript into your task report**

Report must contain: the Step 4 failure transcript for both genuinely-red tests, and both Step 5 falsification transcripts with their named breaks and revert confirmations.

- [ ] **Step 7: Commit**

```bash
git status
git add Tests/TeststripAppTests/AppModelTests.swift Tests/TeststripAppTests/AppModelSessionRestoreTests.swift
git commit -m "test: a run persists nothing and the banner does not survive relaunch (red)"
```

---

## Task 5B: Stop persisting proposals, drop the undo status flip — implementation

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift`

**Interfaces:**
- Consumes: `autopilotGhostAssetIDs` / `refreshAutopilotGhostAssetIDs()` (Task 3B).
- Produces: an `AppModel` with **zero** references to any `CatalogRepository` proposal API, which is the precondition for Task 6.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.**

- [ ] **Step 1: Delete the persistence state**

Delete `public private(set) var pendingAutopilotProposals: [AutopilotProposal] = []` (`:2252`).

Delete `private var lastAutopilotRunIDByScopeKey: [String: AutopilotRunID] = [:]` (`:2277`) and its two-line comment above it (`:2274-2276`).

In the comment block above `lastAutopilotRunUndoGroup` (`:2254-2261`), replace "and the run it belongs to, so `undoAutopilotRun` can revert the whole batch and flip that run's proposals back to `pending`" with "and the run it belongs to, so `undoAutopilotRun` can revert the whole batch".

- [ ] **Step 2: Strip persistence out of `runAutopilot`**

Delete the scope-key block (`:9677-9680`):

```swift
        let scopeKey = scopeAssets.map(\.id.rawValue).sorted().joined(separator: ",")
        if let priorRunID = lastAutopilotRunIDByScopeKey[scopeKey] {
            try catalog.repository.deleteAutopilotProposals(runID: priorRunID)
        }
```

Delete `try catalog.repository.save(proposals)` (`:9690`) and `lastAutopilotRunIDByScopeKey[scopeKey] = runID` (`:9691`).

Update the method's doc comment (`:9636-9646`): replace "replaces any prior pending proposals for the identical scope, persists the new set for run tracking/rationale, and immediately applies" with "and immediately applies", and replace "A later `commitAutopilotProposals` confirms them" with "Nothing persists a proposal — the tentative flag in `metadata_json` (the ghost) is the whole record. A later `commitAutopilotProposals` confirms it". Re-running the identical scope is now idempotent by construction: `applyTentativeAutopilotProposals` writes nothing when the metadata already matches (`:9753`).

- [ ] **Step 3: Delete the undo status-flip block**

In `undoAutopilotRun()`, delete `:10010-10016`:

```swift
        if let runID = lastAutopilotRunUndoRunID {
            let committedProposalIDs = try catalog.repository.autopilotProposals(runID: runID)
                .filter { $0.status == .committed }
                .map(\.id)
            try catalog.repository.updateAutopilotProposalStatus(ids: committedProposalIDs, to: .pending)
            pendingAutopilotProposals = (try? catalog.repository.autopilotProposals(status: .pending)) ?? []
        }
```

and add, in its place, so the sidebar reflects the reverted ghosts:

```swift
        try refreshCatalogSidebarCounts()
```

The `guard let catalog else { throw … }` at `:10004-10006` is now unused by the body — delete it too, and delete `lastAutopilotRunUndoRunID = nil` only if `lastAutopilotRunUndoRunID` has no remaining readers (`grep -n lastAutopilotRunUndoRunID Sources/TeststripApp/AppModel.swift`); if it has none, delete the property (`:2263`) and both assignments (`:9765`, `:10018`) as well.

Update the method doc comment (`:9994-10001`): drop "then returns that run's proposals (including any since committed) to `pending` so they are reviewable again (and their KEEP/CUT badges reappear)" — the reverted metadata restores the pre-run ghost state directly.

Also update `revertAutopilotTentativeChange`'s doc comment (`:10022-10039`) where it says "per `undoAutopilotRun`'s 'including any since committed' contract" — replace with "undo-run intentionally reaches back through a commit". Keep the rest of that comment (the merge-aware and sidecar-fix-up reasoning) verbatim; that behavior is untouched.

- [ ] **Step 4: Delete `reconstructAutopilotStateAfterLoad`**

Delete the whole method (`:10128-10147`, doc comment included) and its call site at `:4720` (`try model.reconstructAutopilotStateAfterLoad()`). The `try model.refreshAutopilotGhostAssetIDs()` line added in Task 3B stays and is now the only autopilot state restored at load — ghosts survive relaunch natively via `metadata_json`; the banner does not.

- [ ] **Step 5: Verify nothing in `Sources/` still touches the proposal APIs**

Run:
```bash
grep -rn "pendingAutopilotProposals\|autopilotProposals(\|updateAutopilotProposalStatus\|deleteAutopilotProposals\|pendingAutopilotProposalCount\|lastAutopilotRunIDByScopeKey\|reconstructAutopilotStateAfterLoad" Sources/
```
Expected: **only** the `CatalogRepository.swift` definitions themselves. Zero hits in `TeststripApp`. If not, fix before proceeding — Task 6 cannot compile otherwise.

- [ ] **Step 6: Build and run the scoped tests**

Run: `swift build && swift test --filter TeststripAppTests.AppModelTests 2>&1 | tail -30`
Expected: 0 failures.

- [ ] **Step 7: Run the whole suite**

Run: `swift test 2>&1 | tail -20`
Expected: 0 failures. `CatalogDatabaseTests`' proposal tests still pass — the table and APIs are still there, just unused by the app.

- [ ] **Step 8: Commit**

```bash
git status
git add Sources/TeststripApp/AppModel.swift
git commit -m "feat: a run persists nothing; undo replays only the in-memory group"
```

---

## Task 6: Delete the proposal persistence layer (mechanical sweep)

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift`
- Modify: `Sources/TeststripCore/Autopilot/AutopilotProposal.swift`
- Modify: `Sources/TeststripCore/Autopilot/AutopilotProposalPlanner.swift`
- Modify: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`
- Modify: `Tests/TeststripAppTests/AppModelTests.swift`
- Modify: `Tests/TeststripAppTests/AppModelSessionRestoreTests.swift`

**Interfaces:**
- Consumes: an `AppModel` with zero proposal-API references (Task 5B).
- Produces: `AutopilotProposal` without `status`; no `AutopilotProposalStatus`; no proposal methods on `CatalogRepository`. Task 7 drops the table these used to touch.

This is a pure deletion sweep with no new behavior, so it is a single task with no test/impl split. It **does** edit test files — the tests being deleted are the ones that exist only to exercise the deleted APIs.

- [ ] **Step 1: Delete the repository proposal APIs**

In `Sources/TeststripCore/Catalog/CatalogRepository.swift`, delete in full:
`save(_ proposals: [AutopilotProposal])` (`:2114-2158`), `autopilotProposals(runID:)` (`:2160-2166`), `autopilotProposals(status:)` (`:2168-2174`), `updateAutopilotProposalStatus(ids:to:)` (`:2176-2187`), `pendingAutopilotProposalCount()` (`:2189-2195`), `deleteAutopilotProposals(runID:)` (`:2197-2202`), and the private `decodeAutopilotProposal(_:)` (`:2204-2234`).

In `deleteAsset(id:)`, delete the cascade line (`:2030`):

```swift
            try database.execute("DELETE FROM autopilot_proposals WHERE asset_id = ?", bindings: [id.rawValue])
```

- [ ] **Step 2: Delete the status type**

In `Sources/TeststripCore/Autopilot/AutopilotProposal.swift`, delete the `AutopilotProposalStatus` enum (`:19-23`), the `public var status: AutopilotProposalStatus` property (`:33`), the `status: AutopilotProposalStatus,` init parameter (`:45`), and `self.status = status` (`:56`).

Add a doc comment above `public struct AutopilotProposal` explaining what it now is:

```swift
/// One run's working proposal, in memory only. Produced by
/// `AutopilotProposalPlanner` and consumed by the run that applies it as a
/// tentative AI label; nothing persists it. The durable record of "the machine
/// proposed a flag" is the ghost in `metadata_json` (`AutopilotGhost`).
```

- [ ] **Step 3: Update the planner**

In `Sources/TeststripCore/Autopilot/AutopilotProposalPlanner.swift`, delete `status: .pending,` from the `AutopilotProposal(...)` call (`:139`).

- [ ] **Step 4: Delete the tests that only exercised the deleted APIs**

In `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`, delete `testPersistsAndReadsAutopilotProposalsByRunAndStatus` (`:19-63`) and `testDeleteAssetRemovesPendingAutopilotProposal` (`:3320-3344`) in full.

In `Tests/TeststripAppTests/AppModelTests.swift`, delete `testRunAutopilotPersistsNoProposals` (added in Task 5A). Its guarantee becomes structural: with the API and (after Task 7) the table gone, persistence is impossible, and Task 7's migration test asserts the table's absence directly.

In `Tests/TeststripAppTests/AppModelSessionRestoreTests.swift`, delete `testAutopilotBannerDoesNotSurviveRelaunch` (added in Task 5A) — it seeds a row through `repository.save(_:)` and names `AutopilotProposalStatus`, both deleted here. Its guarantee is structural too (`reconstructAutopilotStateAfterLoad` no longer exists) and is covered live by scenario card cull-029 step 7. **Keep `testGhostsSurviveRelaunch`** — it depends on nothing being deleted.

- [ ] **Step 5: Verify nothing references the deleted symbols**

Run:
```bash
grep -rn "AutopilotProposalStatus\|autopilotProposals(\|updateAutopilotProposalStatus\|deleteAutopilotProposals\|pendingAutopilotProposalCount\|\.status" Sources/TeststripCore/Autopilot Sources/TeststripCore/Catalog | grep -i autopilot
```
Expected: no hits.

- [ ] **Step 6: Build and run the whole suite**

Run: `swift build && swift test 2>&1 | tail -20`
Expected: build succeeds, 0 failures. Note that `autopilot_proposals` is still created by the migration and is now completely unreferenced from Swift — Task 7 removes it.

- [ ] **Step 7: Commit**

```bash
git status
git add Sources/TeststripCore/Catalog/CatalogRepository.swift Sources/TeststripCore/Autopilot/AutopilotProposal.swift Sources/TeststripCore/Autopilot/AutopilotProposalPlanner.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift Tests/TeststripAppTests/AppModelTests.swift Tests/TeststripAppTests/AppModelSessionRestoreTests.swift
git commit -m "refactor: delete the autopilot proposal persistence layer"
```

---

## Task 7A: DROP TABLE migration — tests (test author)

**Files:**
- Test: `Tests/TeststripCoreTests/CatalogMigrationDropTests.swift` (create)

**Interfaces (what Task 7B must produce):**
- `CatalogMigrations.version` bumped from `22` to `23`.
- `CatalogMigrations.dropStatements: [String]` containing `"DROP TABLE IF EXISTS autopilot_proposals"`.
- `CatalogDatabase.migrate()` executes `dropStatements` after `statements`.
- `autopilot_proposals` is no longer in `CatalogMigrations.statements`.

**You are the test author. Do not write any file under `Sources/`.**

- [ ] **Step 1: Write the failing test file**

Create `Tests/TeststripCoreTests/CatalogMigrationDropTests.swift`:

```swift
import XCTest
@testable import TeststripCore

// SP-D0 drops `autopilot_proposals` forward-only. The stale rows in a real
// catalog are bookkeeping, not truth; the ghosts in `metadata_json` are the
// truth and must come through the migration untouched.
final class CatalogMigrationDropTests: XCTestCase {
    private static let legacyProposalsTableSQL = """
    CREATE TABLE IF NOT EXISTS autopilot_proposals (
        id TEXT PRIMARY KEY NOT NULL,
        run_id TEXT NOT NULL,
        asset_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        keyword TEXT,
        rationale TEXT NOT NULL,
        confidence REAL NOT NULL,
        status TEXT NOT NULL,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
    )
    """

    private func tableExists(_ name: String, in database: CatalogDatabase) throws -> Bool {
        let rows = try database.rows(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
            bindings: [name]
        )
        return !rows.isEmpty
    }

    func testMigrationVersionCoversTheProposalTableDrop() {
        // autopilot_proposals was dropped at schema 23; later migrations only
        // raise the version, so assert the floor rather than pinning a literal
        // that every future migration would break.
        XCTAssertGreaterThanOrEqual(CatalogMigrations.version, 23)
    }

    func testFreshCatalogNeverCreatesTheProposalTable() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "drop-proposals-fresh")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()

        XCTAssertFalse(try tableExists("autopilot_proposals", in: database))
        XCTAssertFalse(
            CatalogMigrations.statements.contains { $0.contains("autopilot_proposals") },
            "the CREATE must be gone, not merely shadowed by the DROP"
        )
    }

    func testLegacyCatalogWithProposalRowsOpensCleanAndKeepsItsGhosts() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "drop-proposals-legacy")
        let catalogURL = directory.appendingPathComponent("catalog.sqlite")

        // Build a "legacy" catalog: current schema plus the old table, with a
        // row in it, alongside an asset carrying a ghost.
        let legacyDatabase = try CatalogDatabase.open(at: catalogURL)
        try legacyDatabase.migrate()
        try legacyDatabase.execute(Self.legacyProposalsTableSQL)
        try legacyDatabase.execute(
            "CREATE INDEX IF NOT EXISTS idx_autopilot_proposals_status ON autopilot_proposals(status)"
        )
        try legacyDatabase.execute(
            """
            INSERT INTO autopilot_proposals
                (id, run_id, asset_id, kind, keyword, rationale, confidence, status, created_at, updated_at)
            VALUES ('p-1', 'run-1', 'asset-1', 'pick', NULL, 'Sharpest frame in its burst', 0.82, 'pending', 1.0, 1.0)
            """
        )
        let ghostAsset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: URL(fileURLWithPath: "/Photos/ghost.cr2"),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag])
        )
        try CatalogRepository(database: legacyDatabase).upsert(ghostAsset)
        XCTAssertTrue(try tableExists("autopilot_proposals", in: legacyDatabase))

        // Reopen: the drop runs, and nothing throws.
        let reopened = try CatalogDatabase.open(at: catalogURL)
        try reopened.migrate()

        XCTAssertFalse(try tableExists("autopilot_proposals", in: reopened))
        XCTAssertTrue(
            try reopened.rows(
                "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_autopilot_proposals%'"
            ).isEmpty,
            "DROP TABLE takes the table's indexes with it"
        )

        // The ghost is untouched — metadata_json is the truth, not the table.
        let reopenedRepository = CatalogRepository(database: reopened)
        let restored = try reopenedRepository.asset(id: ghostAsset.id)
        XCTAssertEqual(AutopilotGhost.kind(in: restored.metadata), .pick)
        XCTAssertNil(restored.metadata.confirmedProjection.flag)
        XCTAssertEqual(try reopenedRepository.assetIDsWithAutopilotGhost(), [ghostAsset.id])
    }

    // Idempotence: the drop runs on every open, including opens where the
    // table was never there.
    func testMigrationIsIdempotentAcrossRepeatedOpens() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "drop-proposals-idempotent")
        let catalogURL = directory.appendingPathComponent("catalog.sqlite")
        for _ in 0..<3 {
            let database = try CatalogDatabase.open(at: catalogURL)
            try database.migrate()
            XCTAssertFalse(try tableExists("autopilot_proposals", in: database))
        }
    }
}
```

- [ ] **Step 2: Run and verify the reds**

Run: `swift test --filter TeststripCoreTests.CatalogMigrationDropTests 2>&1 | tail -40`
Expected, in order: `testMigrationVersionCoversTheProposalTableDrop` fails (`22 is not greater than or equal to 23`); `testFreshCatalogNeverCreatesTheProposalTable` fails on both assertions (the CREATE is still in `statements`); `testLegacyCatalogWithProposalRowsOpensCleanAndKeepsItsGhosts` fails on `XCTAssertFalse(try tableExists(...))`; `testMigrationIsIdempotentAcrossRepeatedOpens` fails likewise. Genuine reds throughout; no falsification needed.

Note: the ghost assertions inside the legacy test would pass on their own today. They are not separable — they run after the table assertion in the same test, and the test as a whole is red. State that in your report.

- [ ] **Step 3: Capture the red transcript into your task report**

- [ ] **Step 4: Commit**

```bash
git status
git add Tests/TeststripCoreTests/CatalogMigrationDropTests.swift
git commit -m "test: autopilot_proposals is dropped forward-only and ghosts survive (red)"
```

---

## Task 7B: DROP TABLE migration — implementation

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift`
- Modify: `Sources/TeststripCore/Catalog/CatalogDatabase.swift`

**Interfaces:**
- Consumes: a tree with no Swift references to `autopilot_proposals` (Task 6).
- Produces: schema version 23 with the table gone.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.**

- [ ] **Step 1: Bump the version and delete the CREATEs**

In `Sources/TeststripCore/Catalog/CatalogMigrations.swift`, change `static let version = 22` to `static let version = 23`.

Delete from `statements` the `CREATE TABLE IF NOT EXISTS autopilot_proposals (...)` block (`:208-221`) and both index statements (`:222-223`).

- [ ] **Step 2: Add the drop list**

Add after the `statements` array closes (`:269`), before `coordinateIndexStatement`:

```swift
    // Forward-only drops for tables whose data is no longer truth. Run right
    // after `statements` so a catalog that still carries the table loses it —
    // and its indexes, which `DROP TABLE` takes with it — on the next open.
    // There is no back-out: `autopilot_proposals` went away with SP-D0,
    // because the machine's flag opinion is derived from the unconfirmed AI
    // flag in `metadata_json` (`AutopilotGhost`) and never stored in a status
    // row. The stale rows were bookkeeping; the ghosts are untouched.
    static let dropStatements = [
        "DROP TABLE IF EXISTS autopilot_proposals"
    ]
```

- [ ] **Step 3: Run the drops during migration**

In `Sources/TeststripCore/Catalog/CatalogDatabase.swift`, inside `migrate()`, immediately after the `statements` loop (`:36-38`):

```swift
        for statement in CatalogMigrations.dropStatements {
            try execute(statement)
        }
```

- [ ] **Step 4: Run the scoped tests**

Run: `swift test --filter TeststripCoreTests.CatalogMigrationDropTests`
Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Run the whole suite and confirm the tree is clean of the table**

Run: `swift build && swift test 2>&1 | tail -20`
Expected: 0 failures.

Run: `grep -rn "autopilot_proposals" Sources/`
Expected: exactly one hit — the `DROP TABLE IF EXISTS` string in `CatalogMigrations.swift`.

- [ ] **Step 6: Commit**

```bash
git status
git add Sources/TeststripCore/Catalog/CatalogMigrations.swift Sources/TeststripCore/Catalog/CatalogDatabase.swift
git commit -m "feat: drop the autopilot_proposals table forward-only"
```

---

## Task 8: New E2E scenario card — cull-029

**Files:**
- Create: `test/scenarios/cull-029-autopilot-ghost-derivation.md`
- Modify: `test/scenarios/LEDGER.md`

**Interfaces:** none (documentation). Read `test/scenarios/README.md` end to end before writing, especially "Running scenarios in a Tart VM" (`:151-192`) and the virtualized-grid and idle-wedge gotchas.

**This task authors the card only.** The live VM run is a separate step performed by the controller's execution flow. The card's `## Run status` must say so.

- [ ] **Step 1: Write the card**

Create `test/scenarios/cull-029-autopilot-ghost-derivation.md` with exactly these sections, in this order: `# <title>`, `**What this covers**`, `## Pre-state`, `## Steps`, `## Expected`, `## Cleanup`, `## Sharp edges`, `## Run status`. Match the house style of `test/scenarios/cull-017-autopilot-review.md` and `test/scenarios/cull-025-run-strip-completion.md`: `**Fails if**` bolded in every Expected bullet, SQL in fenced `bash` blocks with inline `# expected` comments, `\$` escaping inside `json_extract(metadata_json,'\$.flag')`.

Title:

```markdown
# cull-029-autopilot-ghost-derivation: the unconfirmed AI flag is the only record of a machine proposal — badges, review queue, and sidebar count all derive from it, and a user override never resurrects
```

`**What this covers**`: Jesse runs autopilot on a seeded batch, sees ghost badges, overrides one with `X`, presses `U`, and the badge stays gone forever. Cite the source symbols with file:line as the house style requires: `AutopilotGhost.kind(in:)` (`Sources/TeststripCore/Autopilot/AutopilotGhost.swift`), `CatalogRepository.assetIDsWithAutopilotGhost()` (`Sources/TeststripCore/Catalog/CatalogRepository.swift`), `AppModel.beginAutopilotReview()` / `autopilotGhostAssetIDs` / `cullSourcePresentation` (`Sources/TeststripApp/AppModel.swift`), `AutopilotBadgePresentation.badge(for:)` (`Sources/TeststripApp/LibraryGridView.swift`), `CullCompletionPresentation.summary(assets:viewedAssetIDs:skippedAssetIDs:)` (`Sources/TeststripApp/CullCompletionPresentation.swift`). **Re-verify every line number against the working tree at the moment you write the card** and date the citation line.

`## Pre-state` — VM, `smoke` variant:

```bash
script/vm_scenario_run.sh sync smoke
script/vm_scenario_run.sh launch smoke
script/vm_scenario_run.sh ax wait-vended Teststrip
```

Baselines (note `sql smoke` targets the launched run's catalog):

```bash
script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='autopilot_proposals';"   # expect 0 — the table is gone
script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"   # GHOST0 (expect 0)
script/vm_scenario_run.sh sql smoke "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"   # GEN0
```

`## Steps` — write these seven, each with its own SQL ground truth:

1. **Evaluate the visible scope.** Press ⇧⌘E; poll `SELECT count(*) FROM evaluation_signals;` until it grows. Keep the app warm between polls with `ax wait-vended` (idle-wedge).
2. **Run autopilot.** Culling ▸ Run Autopilot. Poll until ghosts appear:
   ```bash
   script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"   # GHOSTN > GHOST0
   ```
   Record the ghost asset ids and their flag values:
   ```bash
   script/vm_scenario_run.sh sql smoke "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag') ORDER BY rowid;"
   ```
3. **Ghost badges render.** In Library, scroll a ghost tile into view (README's virtualized-grid gotcha) and assert its accessibility value:
   ```bash
   script/vm_scenario_run.sh ax find --contains "Autopilot proposes keep"   # or "Autopilot proposes cut", matching that asset's flag from step 2
   ```
   Assert the badge kind matches `json_extract(metadata_json,'$.flag')` for that exact asset id — no table is consulted anywhere.
4. **Sidebar source and count.** In Cull, assert the "Autopilot Proposals" source is present and its count equals `GHOSTN`:
   ```bash
   script/vm_scenario_run.sh ax find --contains "Autopilot Proposals"
   ```
5. **Override, then clear — gone is gone.** Select one ghost asset (call it `$G`, recorded in step 2), press `x`, then press `u`. Assert against `metadata_json` that the ghost does not return:
   ```bash
   script/vm_scenario_run.sh sql smoke "SELECT json_extract(metadata_json,'\$.flag'), json_extract(metadata_json,'\$.aiUnconfirmedFields') FROM assets WHERE id='\$G';"   # expect NULL, NULL
   script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM removed_ai_labels WHERE asset_id='\$G' AND field='flag';"   # expect 1
   script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM assets WHERE id='\$G' AND EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"   # expect 0
   ```
   Re-check the tile's accessibility value: neither "Autopilot proposes keep" nor "Autopilot proposes cut" may appear for `$G`. Then re-run Culling ▸ Run Autopilot and re-run the same three queries — still 0, still 1: `removed_ai_labels` suppresses the re-proposal, so nothing can resurrect it.
6. **Complete the run; no ✨ line.** Decide every remaining frame (`p`/`x` through the scope until `SELECT count(*) FROM assets WHERE json_extract(metadata_json,'$.flag') IS NULL` reaches 0 and no `aiUnconfirmedFields` flag markers remain). Assert the completion stage:
   ```bash
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "Nothing left to decide"
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "skipped"      # detail line, e.g. "0 skipped · 0 never viewed"
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "awaiting review"          # expect NOT-FOUND
   script/vm_scenario_run.sh ax find --role AXButton --contains "Review AI Suggestions"        # expect NOT-FOUND
   ```
7. **Relaunch: badges survive, banner does not.** Quit and `script/vm_scenario_run.sh launch smoke` against the same run directory (do **not** re-copy the template — say explicitly in the card how the runner reuses the run dir; if `launch` always copies fresh, seed a ghost into the run dir before relaunch and note that in `## Sharp edges`). Assert a ghost tile still shows its KEEP/CUT badge and that no autopilot banner is present:
   ```bash
   script/vm_scenario_run.sh ax find --contains "Autopilot proposes"        # expect FOUND for a surviving ghost
   script/vm_scenario_run.sh ax find --contains "Autopilot reviewed"        # expect NOT-FOUND (the banner)
   ```

`## Expected` — one bullet per step, each ending in a `**Fails if**` clause. The safety-critical ones:

- Step 2: **Fails if** any row appears in a table named `autopilot_proposals` (it must not exist), or a ghost asset's `flag` is set without `aiUnconfirmedFields` containing `flag` — a tentative verdict silently landing as confirmed is a provenance-invariant violation: report immediately, do not soften it.
- Step 5: **Fails if** the ghost returns in `metadata_json` after `U`, if the badge reappears on the tile, or if the second autopilot run re-proposes a flag for `$G`. Resurrection is the exact bug this spec exists to kill — this is a P0, not a nitpick.
- Step 6: **Fails if** the detail line contains "awaiting review", if a "Review AI Suggestions" button is present, or if any ✨ count appears in the completion stage.
- Step 7: **Fails if** a ghost tile loses its badge across relaunch (ghosts must survive natively via `metadata_json`) or if the autopilot banner reappears (it is run-time only).

`## Cleanup`: quit the VM app instance; `script/vm_scenario_run.sh` run dirs are per-launch throwaways — state whether any template mutation was made and how it is reset.

`## Sharp edges`: the `smoke` seed's 24 synthetic photos may not cross any proposal threshold, so autopilot can legitimately produce zero ghosts — if `GHOSTN == GHOST0` after a full evaluation drain, that is a **fixture gap, not a failure**; say so and mark the card NOT-RUN rather than forcing a pass. Also note the idle-wedge (`wait-vended` on every poll) and the virtualized-grid scroll requirement.

`## Run status`: `NOT RUN — card authored <date> alongside the SP-D0 ghost-derivation push; source-cited against the working tree, not yet driven. Needs a live VM run.`

- [ ] **Step 2: Add the LEDGER row**

Append to `test/scenarios/LEDGER.md`, matching the existing seven-column format:

```
| cull-029-autopilot-ghost-derivation | cull-029-autopilot-ghost-derivation.md — the unconfirmed AI flag is the only record of a machine proposal; badges/review/sidebar all derive from it and a user override never resurrects | Spec'd | VM e2e (ax+sql) | — | new card authored <date> for the SP-D0 ghost-derivation push; source-cited, not yet driven | pending live VM run; documents an honest fixture gap — the `smoke` seed's synthetic frames may produce zero proposals even after a full evaluation drain |
```

- [ ] **Step 3: Verify the card's SQL is syntactically valid**

Run each `SELECT` from the card against a throwaway migrated catalog to catch quoting mistakes before a VM run burns time:

```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
sqlite3 "$ISOLATED/Teststrip/catalog.sqlite" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='autopilot_proposals';"
sqlite3 "$ISOLATED/Teststrip/catalog.sqlite" "SELECT count(*) FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"
```
Expected: the first returns `0` (the table is gone after Task 7), the second returns a number without a SQL error. Quit the app afterwards and `./script/reset_isolated_test_data.sh --delete`. This is a launch-and-quit smoke check, host-safe per CLAUDE.md.

- [ ] **Step 4: Commit**

```bash
git status
git add test/scenarios/cull-029-autopilot-ghost-derivation.md test/scenarios/LEDGER.md
git commit -m "test: add cull-029 scenario card for ghost derivation"
```

---

## Task 9: Reconcile the stale scenario cards

**Files:** every card listed in Frozen fact F4 Tier 1 and Tier 2, plus `test/scenarios/README.md:128` and `test/scenarios/LEDGER.md`.

**Interfaces:** none (documentation).

Documentation-only sweep, so no test/impl split. Work card by card and commit in small batches. **Every card you touch gets a dated reconciliation note appended to its `## Run status`, in the house style** — see `test/scenarios/cull-017-autopilot-review.md:229-240` for the pattern: state what was reconciled, then `supersedes prior status: <why the old evidence is no longer valid> — needs a fresh VM run.`

- [ ] **Step 1: Reconcile the two big Tier-1 cards**

`test/scenarios/cull-025-run-strip-completion.md`:
- Title (`:1`): drop "the cull view's only ✨ surface" and change "six counts" to "five counts".
- `:13-15`: the count list becomes `picked / rejected / undecided / skipped / never-viewed`.
- Delete the whole `sparkleAwaiting` kind-aware contract block (`:114-169`) and the ceremony-gating sentence at `:158-159`.
- `:174-176`: the detail-line quote becomes `"\(skipped) skipped · \(neverViewed) never viewed"`.
- `:180-182`: the ceremony list becomes the five titles `"Export"`, `"Move Rejects…"`, `"Move Rejects to Trash…"`, `"Review Picks"`, `"Save Picks as Set"`; delete the `"Review AI Suggestions"` entry and its `reviewAutopilotRun()` note.
- `:198-217`, `:228-234`, `:252`, `:409`: delete the `autopilot_proposals` fixture seed, all `SELECT … FROM autopilot_proposals` assertions, and the `reconstructAutopilotStateAfterLoad()` reload claim. Replace the fixture technique with the `aiUnconfirmedFields` template patch that `cull-023`/`cull-026` already use (see `cull-023-return-commit-undo.md:143-149`).
- `:380-384`: the expected detail string loses its `… AI suggestions awaiting review` segment.
- `:411-419`, `:493-513`: keep the "Review AI Suggestions is absent" assertion but reframe it — it is now unconditionally absent, not conditionally absent, so drop the `sparkleAwaiting` conditions.
- `:556-564`: delete the banner-at-launch sharp edge; replace with "the banner is run-time only and never survives relaunch (`reconstructAutopilotStateAfterLoad` was deleted in SP-D0); ghost badges survive natively via `metadata_json`."
- `:589-603`, `:622-649`, `:662-666`, `:725-758`: prune the historical blocks of their `sparkleAwaiting` / "Review AI Suggestions" claims and append the new reconciliation note.

`test/scenarios/cull-017-autopilot-review.md` — rewrite wholesale to ghost ground truth:
- Every `SELECT … FROM autopilot_proposals` (`:59, 71, 82-83, 110`) becomes the ghost query used in cull-029 step 2.
- `:77-78`: the badge matches `json_extract(metadata_json,'$.flag')` on a ghost-carrying asset, not `autopilot_proposals.kind`.
- `:96-99`, `:113-114`: replace "read `autopilot_proposals` directly via `autopilotProposalDecision(for:)`" with "read the ghost via `AutopilotGhost.kind(in: asset.metadata)` — no table is consulted".
- `:215-224` (the "open question: is Review reachable after Dismiss" sharp edge): **resolve it** — review is now reachable from the Cull sidebar's "Autopilot Proposals" source (`AppModel.activateCullSource(.autopilotProposals)` → `beginAutopilotReview()`), so banner Dismiss is no longer a one-way door. Update the step ordering accordingly and delete the two-separate-import-runs workaround.
- Expected bullets `:157-186`: re-anchor on `metadata_json` and `removed_ai_labels`; add a bullet that dismiss records `removed_ai_labels` and writes no sidecar.

- [ ] **Step 2: Commit that batch**

```bash
git status
git add test/scenarios/cull-025-run-strip-completion.md test/scenarios/cull-017-autopilot-review.md
git commit -m "test: reconcile cull-017 and cull-025 to ghost derivation"
```

- [ ] **Step 3: Reconcile the remaining Tier-1 cards**

- `test/scenarios/import-008-auto-cull-toggle.md` (`:20, 57, 65-70, 83-88, 89-93, 100-108`): every proposal-table query becomes the ghost query; "commit the proposals" becomes "commit the ghosts from the sidebar's Autopilot Proposals source".
- `test/scenarios/app-012-autopilot-evaluate-commands.md` (`:39, 49-51, 59, 69, 73`): `SELECT count(*) FROM autopilot_proposals; # still 0` becomes the ghost count staying at its baseline; the `JOIN autopilot_proposals p …` becomes a plain `WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'$.aiUnconfirmedFields') WHERE value='flag')`.
- `test/scenarios/cull-015-sidebar-sources.md` (`:4-5, 10, 35, 42-43, 53-54, 75, 79`): `!pendingAutopilotProposals.isEmpty` becomes `!autopilotGhostAssetIDs.isEmpty`; the count is the ghost-carrying asset count.
- `test/scenarios/lib-016-grid-badges.md` (`:7, 43, 46-48, 126-128`): the badge maps `PickFlag` (`.pick` → KEEP, `.reject` → CUT, no ghost → no badge); delete the `.keyword` row; "needs a pending Autopilot proposal in place" becomes "needs an asset carrying a ghost (`aiUnconfirmedFields` contains `flag`)".
- `test/scenarios/worker-002-evaluation-verdicts.md` (`:5-7, 58-66, 75-82, 94-95`): replace the `kind, status` query with the ghost query; drop "driven by a *committed* `AutopilotProposalKind`" — the badge is driven by the ghost's own value and disappears the moment the flag is confirmed.
- `test/scenarios/people-020-ai-label-provenance.md` (`:305-311, 359-368, 464-467`): drop the `run_id` lookup and the join; select ghost assets directly. The Commit step stays (it still calls `commitAutopilotProposals`).
- `test/scenarios/dev-009-bench-seeds.md` (`:113`): remove `autopilot_proposals` from the captured schema-table inventory.

- [ ] **Step 4: Reconcile the Tier-2 prose**

- `test/scenarios/app-003-workspace-switching.md:25-26` and `test/scenarios/app-005-chrome-policy.md:19-20`: "appears only when a proposal batch is pending" → "appears only while ghosts exist".
- `test/scenarios/app-011-find-best-shots.md:37, 41, 71`: "proposals" → "ghosts".
- `test/scenarios/cull-016-completion-stage.md:32-40`: make this the **authoritative** post-drop completion action set — the five titles from Step 1 — and cross-reference cull-025 so the two no longer conflict. `:118-122`: keep the banner-suppression note, drop the cull-017-fixture caveat.
- `test/scenarios/cull-014-stack-rail.md:335-338` and `test/scenarios/cull-024-honest-states.md:574-582`: the `cullCompletion` proposal-kind partition no longer exists; rewrite those citation-shift notes to say it was deleted in SP-D0.
- `test/scenarios/cull-026-tentative-never-commits.md:352-354`: the cross-reference to cull-017 stays valid; add a pointer to `cull-029` for the U-after-override leg its `:324-337` gap note asks for, and update that gap note to say the leg now exists.
- `test/scenarios/lib-012-grid-keys.md:103`: "unlike Autopilot proposals" → "unlike an autopilot ghost".
- `test/scenarios/README.md:128`: the adopted-card row description → "Autopilot ghost → Review → Commit → Undo all".
- `test/scenarios/LEDGER.md`: update the Notes column for `cull-017` (delete the "open q: banner Dismiss may make Review unreachable" note — resolved), `lib-016`, `import-008`, `app-012`, and add `Reconciled — NOT re-run` status to every card this task touched.

- [ ] **Step 5: Verify no stale references remain**

Run:
```bash
grep -rn "autopilot_proposals\|sparkleAwaiting\|awaiting review\|Review AI Suggestions\|pendingAutopilotProposals\|autopilotProposalDecision\|AutopilotProposalStatus" test/scenarios/
```
Expected: zero hits, except inside a card's `## Run status` history where the note deliberately quotes what was removed. Inspect each survivor and confirm it is a history line, not a live assertion.

- [ ] **Step 6: Commit**

```bash
git status
git add test/scenarios/
git commit -m "test: reconcile scenario cards to ghost derivation"
```

---

## Post-plan: the live VM run

After Task 9, `cull-029-autopilot-ghost-derivation.md` must be driven live in the Tart VM per `test/scenarios/README.md` ("Running scenarios in a Tart VM"), and its `## Run status` and the LEDGER row updated with the real result. That run is a separate step in the controller's execution flow, not a task in this plan.
