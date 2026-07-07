# Teststrip Autopilot (Full Copilot) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Authored against HEAD `240f19a7cc630a3796e6ac372cd28803a50f9b05` (main).** The tree advances quickly; before starting each task, `git log`-verify that the interfaces named in that task's **Interfaces** block still exist at the cited signatures, and rebase. Anchor edits by symbol name, not line number — the line numbers below are orientation aids captured at authoring time.

**Goal:** Ship the full-autopilot Copilot from design 1b (`design-concept/Teststrip.dc.html`): an agent-driven library where a natural-language Ask becomes inspectable filter chips, an on-demand/per-import Autopilot run produces a **provisional bulk proposal** (KEEP/CUT per frame plus keyword suggestions) that is reviewed, committed, and undone as ONE gesture, an honest Agents panel projects the real background work behind it, and an "Autopilot on" toggle wires it into import. Autonomy stays bounded by the standing product rules: catalog-first, originals never modified except through the existing confirm-gated flows, every machine action reviewable and undoable.

**Architecture:** Autopilot orchestrates capabilities that ALREADY EXIST — evaluation providers (`requestEvaluation`, `EvaluationSignal`), stack detection (`AssetStackBuilder`, `CullingStackRecommendation.rankedCandidates`), face clustering (`FaceSuggestionBuilder`, `peopleFaceSuggestions`), review queues (`ReviewQueue`), work sessions, and the worker. It adds one honest new thing: a **proposal set** — a persisted, reviewable batch of proposed per-asset metadata decisions that is NEVER written to `AssetMetadata`/XMP until the user commits, and that commits/reverts as a single undo group. The pipeline is: gather already-computed signals over a scope → build pick/reject/keyword proposals with a pure planner → persist as `pending` proposals → surface (banner + KEEP/CUT badges + review surface) → commit selected/all through the grouped-undo metadata path → Undo all reverts the group and returns proposals to `pending`. The NL layer is an opt-in LLM translation (reusing the `LocalHTTPModelProvider` configuration pattern) that maps NL → the SAME `LibrarySearchIntent` predicates/chips the deterministic parser produces; the deterministic parser stays the always-available fallback. The Agents panel is a projection over live `.recognition` work + proposal-generation counts + existing stack/face suggestion counts.

**Tech Stack:** Swift 6 / macOS 14, SwiftPM, XCTest, SwiftUI presentation-model pattern (no snapshot tests), SQLite via existing `CatalogRepository`. No new hard external dependencies. The NL translation layer's LLM endpoint is opt-in and reuses the existing `LocalHTTPModelTransport` seam — LM Studio / Ollama-style OpenAI-compatible endpoints — so it introduces no build-time dependency and defaults OFF.

## Scoping decision (flag for Jesse before Task 3)

The design lists four proposal kinds: pick/reject per frame, keyword suggestions, stack groupings, face matches. This plan makes **pick/reject/keyword** the first-class *committable, undoable-as-one-group* proposals, because those are the kinds that write `AssetMetadata`/XMP and therefore need the new proposal→commit→undo lifecycle. **Stack grouping and face grouping are surfaced as honest Agents-panel projections that route to their EXISTING provisional flows** (`AssetStackBuilder`-backed stack culling, which never touches originals until the user flags; and `peopleFaceSuggestions` with its existing `confirmPeopleFaceSuggestion`/`dismissPeopleFaceSuggestion` confirm flow). They are deliberately NOT re-persisted as new committable rows: doing so would duplicate two working review flows (violating DRY and "extend Activity's projections, not theater") and would fork the undo model. The auto-cull banner's "dupes→stacks" segment is the near-duplicate agent's detected-stack count with a Review action that opens stack culling. **This is the one place this plan narrows the design; confirm it before Task 3, or expand scope with a follow-up plan for committable stack/face proposal rows.**

## Global Constraints

- **No proposal auto-writes metadata.** Proposal generation (Tasks 3–4) only persists `pending` proposal rows; nothing reaches `AssetMetadata`, flags, ratings, keywords, or XMP until an explicit commit gesture (Tasks 8–9). Only the commit path writes, and only through the existing undoable `applyMetadataSnapshot` path.
- **Evaluations run only through the existing worker flow over CACHED PREVIEWS.** Autopilot never adds a new worker command or background-work kind; it consumes `requestEvaluation(assetID:provider:)` (which gates on `hasCachedPreview`) and reads persisted `EvaluationSignal`s. Proposal generation over a scope proposes ONLY for assets that already carry signals — it never guesses for unevaluated frames.
- **Provider list is always `AppModel.defaultEvaluationProviderNames`** (`["local-image-metrics", "apple-vision", "core-image-faces"]` at authoring time; consuming the constant tracks future additions).
- **Originals are never modified.** No task in this plan relocates or rewrites originals. (The confirm-gated move-rejects-to-folder feature is a separate plan.)
- **NL translation is opt-in and fails safe.** With no configured endpoint, the deterministic `LibrarySearchIntent.parse` is the only path and behavior is byte-identical to today. A configured endpoint's output is rendered as the same removable chips and is fully inspectable; a translation error falls back to the deterministic parser, never blocks the Ask.
- No SwiftUI snapshot tests. UI behavior lands as presentation-model members with XCTest model tests (repo pattern in `Tests/TeststripAppTests`).
- Copy separators are the repo's `·` middle dots and `—` em dashes.
- Run all commands from the repo root `/Users/jesse/git/projects/teststrip`.
- **Every task is independently landable and commits on green.** Later tasks depend on earlier ones only through the exact produced interfaces named in each header.

## File Map

- Modify: `Sources/TeststripApp/AppModel.swift` — grouped undo, proposal state/orchestration, run summary, commit/undo-all, agents projection, autopilot toggle, NL translation wiring.
- Create: `Sources/TeststripCore/Autopilot/AutopilotProposal.swift` — proposal domain model + IDs.
- Create: `Sources/TeststripCore/Autopilot/AutopilotProposalPlanner.swift` — pure signal→proposal planner.
- Create: `Sources/TeststripCore/Autopilot/AutopilotQueryTranslator.swift` — NL translation protocol + LocalHTTP translator.
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift` — `autopilot_proposals` table (schema v15).
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` — proposal CRUD.
- Modify: `Sources/TeststripApp/LibraryGridView.swift` — auto-cull banner, KEEP/CUT badges, review toolbar.
- Modify: `Sources/TeststripApp/CopilotView.swift` — Agents panel section.
- Modify: `Sources/TeststripApp/ImportConfirmationDraft.swift` + `Sources/TeststripApp/ImportFolderPathDraft.swift` — Autopilot-on plan step + flag.
- Tests: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`, `Tests/TeststripCoreTests/AutopilotProposalPlannerTests.swift` (new), `Tests/TeststripCoreTests/AutopilotQueryTranslatorTests.swift` (new), `Tests/TeststripAppTests/AppModelTests.swift`, `Tests/TeststripAppTests/AutopilotBannerPresentationTests.swift` (new), `Tests/TeststripAppTests/CopilotPresentationTests.swift`, `Tests/TeststripAppTests/ImportConfirmationDraftTests.swift`.

---

### Task 1: Grouped metadata undo (wave-2 backlog item 9 — prerequisite)

Today `metadataUndoStack: [MetadataChange]` holds one entry per asset, so a batch action (compare keep/reject, apply-keyword-to-N, batch metadata) takes N presses of Cmd+Z to reverse and in practice is unrecoverable. Autopilot's "Undo all" REQUIRES that a committed batch reverse in one gesture, so this is the foundation. Convert the stack to grouped entries: every user action pushes exactly one labeled group (single-asset edits are groups of one); `undoMetadataChange()` pops and reverts one whole group and names it in the status bar.

**Estimated scope:** ~240 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`MetadataChange` at ~1151; `metadataUndoStack`/`metadataRedoStack` at ~1364; the six append sites; `undoMetadataChange`/`redoMetadataChange` at ~4973)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `applyMetadataSnapshot(assetID:metadata:)` (:5220), `applyCompareFlags(_:to:)` (:3935), `acceptBatchKeywordSuggestion(_:assetIDs:)` (:4618), `applyBatchMetadata(assetIDs:keywordText:caption:creator:copyright:)` (:4705), `updateSelectedAssetMetadata(_:)` (:4985), the two conflict resolvers (:5278, :5349).
- Produces (Tasks 8–9 rely on these):
  - `private struct MetadataChangeGroup: Equatable { var label: String; var changes: [MetadataChange] }`
  - `private var metadataUndoStack: [MetadataChangeGroup]` / `private var metadataRedoStack: [MetadataChangeGroup]`
  - `private func recordMetadataChangeGroup(label: String, changes: [MetadataChange])` — appends the group (skips empty) and clears redo.
  - `public var lastUndoableActionLabel: String?` — `metadataUndoStack.last?.label`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/AppModelTests.swift` (uses `makeModelWithCatalogAssets`, `makeAsset`, `Self.technicalMetadata`; `applyVisibleBatchMetadata` at AppModel.swift:4654 writes without needing signals, so it is the clean batch path to exercise the group):

```swift
    func testBatchMetadataUndoRevertsAllAssetsInOneStep() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(id: "undo-batch-a", path: "/Photos/Job/undo-batch-a.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let second = makeAsset(id: "undo-batch-b", path: "/Photos/Job/undo-batch-b.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "undo-batch-metadata", assets: [first, second])
        try model.selectSidebarTarget(.allPhotographs)

        let applied = try model.applyVisibleBatchMetadata(keywordText: "patagonia", caption: "", creator: "", copyright: "")
        XCTAssertEqual(applied, 2)
        XCTAssertTrue(model.canUndoMetadataChange)
        XCTAssertEqual(model.lastUndoableActionLabel, "Applied metadata to 2 photos")

        try model.undoMetadataChange()

        XCTAssertEqual(try repository.asset(id: first.id).metadata.keywords, [])
        XCTAssertEqual(try repository.asset(id: second.id).metadata.keywords, [])
        XCTAssertFalse(model.canUndoMetadataChange)
        XCTAssertTrue(model.canRedoMetadataChange)
        XCTAssertEqual(model.statusMessage, "Undid: Applied metadata to 2 photos")
    }

    func testSingleFlagEditRemainsAOneChangeGroup() throws {
        let asset = makeAsset(id: "undo-single", path: "/Photos/Job/undo-single.cr2", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(named: "undo-single", assets: [asset])
        model.select(asset.id)

        try model.setFlagForSelectedAsset(.pick)
        XCTAssertEqual(model.lastUndoableActionLabel, "Flag")

        try model.undoMetadataChange()
        XCTAssertNil(try repository.asset(id: asset.id).metadata.flag)
        try model.redoMetadataChange()
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.flag, .pick)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AppModelTests.testBatchMetadataUndoRevertsAllAssetsInOneStep|AppModelTests.testSingleFlagEditRemainsAOneChangeGroup"`
Expected: compile FAILURE — `value of type 'AppModel' has no member 'lastUndoableActionLabel'`.

- [ ] **Step 3: Introduce the group type and recorder**

In `Sources/TeststripApp/AppModel.swift`, next to `MetadataChange` (~1151):

```swift
private struct MetadataChangeGroup: Equatable {
    var label: String
    var changes: [MetadataChange]
}
```

Change the stack declarations (~1364) to `[MetadataChangeGroup]` and their initializers (~2651). Add near `canUndoMetadataChange` (~1577):

```swift
    public var lastUndoableActionLabel: String? {
        metadataUndoStack.last?.label
    }
```

Add the recorder near `undoMetadataChange`:

```swift
    private func recordMetadataChangeGroup(label: String, changes: [MetadataChange]) {
        let effectiveChanges = changes.filter { $0.before != $0.after }
        guard !effectiveChanges.isEmpty else { return }
        metadataUndoStack.append(MetadataChangeGroup(label: label, changes: effectiveChanges))
        metadataRedoStack.removeAll()
    }
```

Rewrite undo/redo to walk a whole group (revert in reverse for undo, forward for redo):

```swift
    public func undoMetadataChange() throws {
        guard let group = metadataUndoStack.popLast() else { return }
        for change in group.changes.reversed() {
            try applyMetadataSnapshot(assetID: change.assetID, metadata: change.before)
        }
        metadataRedoStack.append(group)
        statusMessage = "Undid: \(group.label)"
    }

    public func redoMetadataChange() throws {
        guard let group = metadataRedoStack.popLast() else { return }
        for change in group.changes {
            try applyMetadataSnapshot(assetID: change.assetID, metadata: change.after)
        }
        metadataUndoStack.append(group)
        statusMessage = "Redid: \(group.label)"
    }
```

- [ ] **Step 4: Convert the six append sites to grouped recording**

Replace each `metadataUndoStack.append(MetadataChange(...))` + `metadataRedoStack.removeAll()` pair with a single `recordMetadataChangeGroup(...)`:

1. `updateSelectedAssetMetadata` (~4998): build a one-element group. Give it a field-appropriate label — the simplest honest label is `"Edit"`; but since callers know the field, add a `label:` parameter to `updateSelectedAssetMetadata(label:_:)` defaulting to `"Edit"` and pass `"Flag"`, `"Rating"`, `"Keywords"`, `"Color label"`, `"Caption"` from the respective callers (`setFlagForSelectedAsset`, etc.). Record `recordMetadataChangeGroup(label: label, changes: [MetadataChange(assetID: selectedAssetID, before: originalAsset.metadata, after: updatedMetadata)])`.
2. `applyCompareFlags` (~3956): accumulate a local `var changes: [MetadataChange]` in the loop, then after the loop `recordMetadataChangeGroup(label: "Culling decision", changes: changes)` (guard on `summary.changedCount > 0` still gates the culling-progress refresh).
3. `acceptBatchKeywordSuggestion` (~4638): accumulate changes; `recordMetadataChangeGroup(label: "Applied \(cleanedKeyword) to \(Self.photoCountDescription(appliedCount))", changes: changes)`.
4. `applyBatchMetadata` (~4794): the function already collects `changes: [(original, updated)]`; record one group `label: "Applied metadata to \(Self.photoCountDescription(changes.count))"`.
5. Both conflict resolvers (~5337, ~5379): `recordMetadataChangeGroup(label: "Resolved XMP conflict", changes: [MetadataChange(...)])`.

Delete every now-unused `metadataRedoStack.removeAll()` at those sites (the recorder clears redo).

- [ ] **Step 5: Run the full app suite**

Run: `swift test --filter AppModelTests`
Expected: PASS (existing undo/redo tests plus the two new ones; existing single-edit tests keep passing because a group of one behaves identically).

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: group metadata undo entries per user action"
```

---

### Task 2: Autopilot proposal model + persistence (schema v15)

Introduce the persisted proposal domain type and a `autopilot_proposals` table with repository CRUD. A proposal is one proposed metadata decision for one asset, tagged with the run that produced it, a rationale, a confidence, and a lifecycle status. Nothing consumes it yet.

**Estimated scope:** ~360 LOC including tests.

**Files:**
- Create: `Sources/TeststripCore/Autopilot/AutopilotProposal.swift`
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift`
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift`
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Consumes: `StableID` (Support/StableID.swift), `AssetID`, `CatalogDatabase.execute`/`rows`/`transaction`, the repository's private `encode`/`decode` JSON helpers (used by `save(_ session:)` at :843).
- Produces:
  - `public struct AutopilotRunID: StableID` and `public struct AutopilotProposalID: StableID`.
  - `public enum AutopilotProposalKind: String, Codable, Sendable { case pick, reject, keyword }`.
  - `public enum AutopilotProposalStatus: String, Codable, Sendable { case pending, committed, dismissed }`.
  - `public struct AutopilotProposal: Codable, Equatable, Sendable` with `id, runID, assetID, kind, keyword: String?, rationale, confidence: Double, status, createdAt, updatedAt`.
  - Repository: `save(_ proposals: [AutopilotProposal])`, `autopilotProposals(runID: AutopilotRunID) -> [AutopilotProposal]`, `autopilotProposals(status: AutopilotProposalStatus) -> [AutopilotProposal]`, `updateAutopilotProposalStatus(ids: [AutopilotProposalID], to: AutopilotProposalStatus)`, `pendingAutopilotProposalCount() -> Int`, `deleteAutopilotProposals(runID: AutopilotRunID)`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/CatalogDatabaseTests.swift` (uses `TestDirectories.makeTemporaryDirectory` and `CatalogRepository(database:)`, and `Asset.testAsset(path:rating:)`):

```swift
    func testPersistsAndReadsAutopilotProposalsByRunAndStatus() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "autopilot-proposals")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(path: "/Volumes/NAS/Job/frame.cr2", rating: 0)
        try repository.upsert(asset)
        let runID = AutopilotRunID(rawValue: "run-1")
        let keep = AutopilotProposal(
            id: AutopilotProposalID(rawValue: "p-keep"),
            runID: runID,
            assetID: asset.id,
            kind: .pick,
            keyword: nil,
            rationale: "Sharpest frame in its burst",
            confidence: 0.82,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let keyword = AutopilotProposal(
            id: AutopilotProposalID(rawValue: "p-kw"),
            runID: runID,
            assetID: asset.id,
            kind: .keyword,
            keyword: "dog",
            rationale: "Vision detected dog",
            confidence: 0.7,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 11),
            updatedAt: Date(timeIntervalSince1970: 11)
        )
        try repository.save([keep, keyword])

        XCTAssertEqual(try repository.autopilotProposals(runID: runID).map(\.id), [keep.id, keyword.id])
        XCTAssertEqual(try repository.pendingAutopilotProposalCount(), 2)

        try repository.updateAutopilotProposalStatus(ids: [keep.id], to: .committed)
        XCTAssertEqual(try repository.autopilotProposals(status: .committed).map(\.id), [keep.id])
        XCTAssertEqual(try repository.autopilotProposals(status: .pending).map(\.id), [keyword.id])
        XCTAssertEqual(try repository.pendingAutopilotProposalCount(), 1)

        try repository.deleteAutopilotProposals(runID: runID)
        XCTAssertEqual(try repository.autopilotProposals(runID: runID), [])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CatalogDatabaseTests.testPersistsAndReadsAutopilotProposalsByRunAndStatus`
Expected: compile FAILURE — `cannot find 'AutopilotProposal' in scope`.

- [ ] **Step 3: Add the domain type**

Create `Sources/TeststripCore/Autopilot/AutopilotProposal.swift`:

```swift
import Foundation

public struct AutopilotRunID: StableID {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct AutopilotProposalID: StableID {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum AutopilotProposalKind: String, Codable, Hashable, Sendable {
    case pick
    case reject
    case keyword
}

public enum AutopilotProposalStatus: String, Codable, Hashable, Sendable {
    case pending
    case committed
    case dismissed
}

public struct AutopilotProposal: Codable, Equatable, Sendable {
    public var id: AutopilotProposalID
    public var runID: AutopilotRunID
    public var assetID: AssetID
    public var kind: AutopilotProposalKind
    public var keyword: String?
    public var rationale: String
    public var confidence: Double
    public var status: AutopilotProposalStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: AutopilotProposalID,
        runID: AutopilotRunID,
        assetID: AssetID,
        kind: AutopilotProposalKind,
        keyword: String?,
        rationale: String,
        confidence: Double,
        status: AutopilotProposalStatus,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.runID = runID
        self.assetID = assetID
        self.kind = kind
        self.keyword = keyword
        self.rationale = rationale
        self.confidence = confidence
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 4: Add the table and CRUD**

In `Sources/TeststripCore/Catalog/CatalogMigrations.swift`, bump `version` to `15` and append to `statements`:

```swift
        """
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
        """,
        "CREATE INDEX IF NOT EXISTS idx_autopilot_proposals_run ON autopilot_proposals(run_id)",
        "CREATE INDEX IF NOT EXISTS idx_autopilot_proposals_status ON autopilot_proposals(status)"
```

In `Sources/TeststripCore/Catalog/CatalogRepository.swift`, add the CRUD near `save(_ session:)`. Persist rows with `INSERT ... ON CONFLICT(id) DO UPDATE`, ordering reads by `created_at ASC, id ASC`. Decode with a private `decodeAutopilotProposal(_ row:)` mirroring `decodeWorkSession`. Follow the file's existing string-binding conventions (`"\(value.timeIntervalSince1970)"`, optional `keyword` bound as `""`-vs-NULL via a nullable-aware execute — the table allows NULL, so store empty string for `nil` and decode `""`→`nil` to stay within the all-`String` binding surface).

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter "CatalogDatabaseTests.testPersistsAndReadsAutopilotProposalsByRunAndStatus|CatalogDatabaseTests.testMigratesAndPersistsAsset"`
Expected: PASS (new proposal round-trip and the existing migration test, confirming the schema bump did not break v14 tables).

Then: `swift test --filter CatalogDatabaseTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripCore/Autopilot/AutopilotProposal.swift Sources/TeststripCore/Catalog/CatalogMigrations.swift Sources/TeststripCore/Catalog/CatalogRepository.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift
git commit -m "feat: persist autopilot proposal sets"
```

---

### Task 3: AutopilotProposalPlanner — signals → proposals (pure)

A pure Core planner that turns a scope's assets, their evaluation signals, and stack groupings into pick/reject/keyword proposals. It is deterministic and honest: it proposes a keep/cut ONLY inside a detected multi-frame stack (the winner keeps, the rest cut), and keyword proposals ONLY from object/vision labels the assets already carry. Singleton frames with no stack and no signals produce no proposal. This is where the "Culling" and "Auto-keywording" agents' logic lives, reusing `AssetStackBuilder` and `CullingStackRecommendation.rankedCandidates`.

**Estimated scope:** ~420 LOC including tests. **Confirm the scoping decision above before starting.**

**Files:**
- Create: `Sources/TeststripCore/Autopilot/AutopilotProposalPlanner.swift`
- Test: `Tests/TeststripCoreTests/AutopilotProposalPlannerTests.swift` (new)

**Interfaces:**
- Consumes: `AssetStackBuilder.stacks(from:visualSimilarityVectorsByAssetID:) -> [AssetStack]` (AssetStackBuilder.swift:28), `CullingStackRecommendation.rankedCandidates(stackAssetIDs:evaluationSignalsByAssetID:)` — **cross-module boundary: `CullingStackRecommendation` lives in `TeststripApp`, not Core.** The planner must NOT import App. Reproduce the minimal ranking the planner needs from raw `EvaluationSignal` scores (a `bestFrame(in:signalsByAssetID:)` that picks the highest summed defect-inverted score) inside Core, OR — preferred — move the pure scoring core (`CullingStackRecommendation.qualityComponent`) into a Core helper the App struct also consumes. Pick the move if the culling-signals owners agree; otherwise inline a Core-local scorer. Flag this as a coordination point.
- Produces:
  - `public struct AutopilotPlanInput { public var assets: [Asset]; public var signalsByAssetID: [AssetID: [EvaluationSignal]]; public var keywordCandidatesByAssetID: [AssetID: [String]] }` (keyword candidates pre-extracted by the caller from object labels so the planner has no vision dependency).
  - `public struct AutopilotProposalPlanner { public var stackBuilder: AssetStackBuilder; public init(stackBuilder:); public func proposals(for input: AutopilotPlanInput, runID: AutopilotRunID, now: Date) -> [AutopilotProposal] }`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TeststripCoreTests/AutopilotProposalPlannerTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class AutopilotProposalPlannerTests: XCTestCase {
    func testProposesKeepForStackWinnerAndCutForAlternates() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = asset(id: "lead", capturedAt: capturedAt)
        let alternate = asset(id: "alt", capturedAt: capturedAt.addingTimeInterval(1))
        let planner = AutopilotProposalPlanner(stackBuilder: AssetStackBuilder(maximumCaptureGap: 2))
        let input = AutopilotPlanInput(
            assets: [lead, alternate],
            signalsByAssetID: [
                lead.id: [signal(lead.id, .focus, 0.30)],
                alternate.id: [signal(alternate.id, .focus, 0.95)]
            ],
            keywordCandidatesByAssetID: [:]
        )

        let proposals = planner.proposals(for: input, runID: AutopilotRunID(rawValue: "r"), now: capturedAt)

        XCTAssertEqual(proposals.first { $0.assetID == alternate.id }?.kind, .pick)
        XCTAssertEqual(proposals.first { $0.assetID == lead.id }?.kind, .reject)
        XCTAssertTrue(proposals.allSatisfy { $0.status == .pending && $0.runID.rawValue == "r" })
    }

    func testProposesNoCullForSingletonFrames() {
        let lead = asset(id: "solo", capturedAt: Date(timeIntervalSince1970: 100))
        let planner = AutopilotProposalPlanner(stackBuilder: AssetStackBuilder(maximumCaptureGap: 2))
        let input = AutopilotPlanInput(
            assets: [lead],
            signalsByAssetID: [lead.id: [signal(lead.id, .focus, 0.9)]],
            keywordCandidatesByAssetID: [:]
        )

        let proposals = planner.proposals(for: input, runID: AutopilotRunID(rawValue: "r"), now: Date())

        XCTAssertTrue(proposals.filter { $0.kind == .pick || $0.kind == .reject }.isEmpty)
    }

    func testProposesKeywordsFromCandidates() {
        let lead = asset(id: "kw", capturedAt: Date(timeIntervalSince1970: 100))
        let planner = AutopilotProposalPlanner(stackBuilder: AssetStackBuilder(maximumCaptureGap: 2))
        let input = AutopilotPlanInput(
            assets: [lead],
            signalsByAssetID: [:],
            keywordCandidatesByAssetID: [lead.id: ["dog", "beach"]]
        )

        let proposals = planner.proposals(for: input, runID: AutopilotRunID(rawValue: "r"), now: Date())

        XCTAssertEqual(Set(proposals.filter { $0.kind == .keyword }.compactMap(\.keyword)), ["dog", "beach"])
    }

    private func asset(id: String, capturedAt: Date) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(id).cr2"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: capturedAt),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000, pixelHeight: 4000, capturedAt: capturedAt,
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        )
    }

    private func signal(_ assetID: AssetID, _ kind: EvaluationKind, _ score: Double) -> EvaluationSignal {
        EvaluationSignal(
            assetID: assetID, kind: kind, value: .score(score), confidence: 0.9,
            provenance: ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "1", settingsHash: "default")
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AutopilotProposalPlannerTests`
Expected: compile FAILURE — `cannot find 'AutopilotProposalPlanner' in scope`.

- [ ] **Step 3: Implement the planner**

Create `Sources/TeststripCore/Autopilot/AutopilotProposalPlanner.swift`. Detect stacks with `stackBuilder.stacks(from: input.assets, visualSimilarityVectorsByAssetID: [:])`. For each stack of `count > 1`: rank member frames by summed defect-inverted score of their `.score`-valued signals (Core-local scorer or the moved `qualityComponent`); the top frame becomes a `.pick` proposal (`rationale: "Sharpest frame in its burst of \(count)"`, `confidence` = normalized winning margin), the rest become `.reject` (`rationale: "Weaker frame in a burst of \(count)"`). Skip a stack entirely if no member carries a `.score` signal (nothing to rank honestly). For every asset with keyword candidates, emit `.keyword` proposals (dedup per asset, `confidence: 0.6`, `rationale: "Detected \(keyword)"`). Assign deterministic IDs (`"\(runID.rawValue)-\(assetID.rawValue)-\(kind)-\(keyword ?? "")"`) so re-running a scope is idempotent. Stamp `createdAt`/`updatedAt` = `now`, `status: .pending`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AutopilotProposalPlannerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Autopilot/AutopilotProposalPlanner.swift Tests/TeststripCoreTests/AutopilotProposalPlannerTests.swift
git commit -m "feat: plan autopilot proposals from signals and stacks"
```

---

### Task 4: runAutopilot orchestration + run summary (model)

Wire the planner into `AppModel`. `runAutopilot(scope:)` gathers the scope's assets, reads their persisted signals and extracts keyword candidates (reusing the existing object-label extraction), builds proposals via the planner, deletes any prior pending proposals for the same scope run, persists the new set, and publishes an `AutopilotRunSummary`. Nothing is written to metadata. This is the on-demand entry point; Task 12 wires it to import.

**Estimated scope:** ~400 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift`
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `evaluationSignals(for:)` (:1780), `Self.objectLabels(from:)` (private static, used by `keywordSuggestions`), `assets` scope, `stackBuilder()` (:4003 usage), repository proposal CRUD (Task 2), `AutopilotProposalPlanner` (Task 3).
- Produces:
  - `public enum AutopilotScope: Equatable, Sendable { case visible; case assetIDs([AssetID]) }`
  - `public struct AutopilotRunSummary: Equatable, Identifiable, Sendable { public var runID: AutopilotRunID; public var keeperCount: Int; public var rejectCount: Int; public var keywordCount: Int; public var stackCount: Int; public var id: String { runID.rawValue }; public var bannerText: String }`
  - `public private(set) var autopilotRunSummary: AutopilotRunSummary?`
  - `public private(set) var pendingAutopilotProposals: [AutopilotProposal]`
  - `@discardableResult public func runAutopilot(scope: AutopilotScope = .visible) throws -> AutopilotRunSummary`
  - `public func autopilotProposalDecision(for assetID: AssetID) -> AutopilotProposalKind?` (first pending `.pick`/`.reject` for the asset; Task 6's badges consume it)

`bannerText` renders `"\(keeperCount) keepers · \(rejectCount) rejects"` and appends ` · dupes→stacks` when `stackCount > 0`, matching the design's "890 keepers · 340 rejects · dupes→stacks".

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/AppModelTests.swift`:

```swift
    func testRunAutopilotProducesPendingProposalsWithoutWritingMetadata() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "ap-lead", path: "/Photos/Job/ap-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "ap-alt", path: "/Photos/Job/ap-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "run-autopilot", assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "1", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.30), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)

        let summary = try model.runAutopilot(scope: .visible)

        XCTAssertEqual(summary.keeperCount, 1)
        XCTAssertEqual(summary.rejectCount, 1)
        XCTAssertEqual(summary.stackCount, 1)
        XCTAssertEqual(summary.bannerText, "1 keepers · 1 rejects · dupes→stacks")
        XCTAssertEqual(model.autopilotProposalDecision(for: alternate.id), .pick)
        XCTAssertEqual(model.autopilotProposalDecision(for: lead.id), .reject)
        // Provisional only: nothing written.
        XCTAssertNil(try repository.asset(id: lead.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: alternate.id).metadata.flag)
        XCTAssertEqual(try repository.pendingAutopilotProposalCount(), 2)
    }

    func testRunAutopilotIsIdempotentForTheSameScope() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "ap2-lead", path: "/Photos/Job/ap2-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "ap2-alt", path: "/Photos/Job/ap2-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "run-autopilot-idem", assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "1", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.30), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)

        _ = try model.runAutopilot(scope: .visible)
        _ = try model.runAutopilot(scope: .visible)

        XCTAssertEqual(try repository.pendingAutopilotProposalCount(), 2)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AppModelTests.testRunAutopilotProducesPendingProposalsWithoutWritingMetadata|AppModelTests.testRunAutopilotIsIdempotentForTheSameScope"`
Expected: compile FAILURE — `value of type 'AppModel' has no member 'runAutopilot'`.

- [ ] **Step 3: Implement orchestration**

Add the state near `cullingSessionCompletion` (~965 region) and the method near `requestVisibleAssetEvaluations`. Resolve the scope's assets (`.visible` → `assets`; `.assetIDs` → repository lookups). Build `keywordCandidatesByAssetID` by mapping each asset's signals through `Self.objectLabels(from:)` + `Self.cleanedKeyword`. Assign a fresh `AutopilotRunID.new()`. Call `AutopilotProposalPlanner(stackBuilder: stackBuilder()).proposals(...)`. For idempotency, key the run by scope hash: before saving, `try catalog.repository.deleteAutopilotProposals(runID:)` for any prior run over the identical asset set (track `lastAutopilotRunIDByScopeKey: [String: AutopilotRunID]`, scope key = sorted asset-id join). Persist, set `pendingAutopilotProposals` and `autopilotRunSummary`, and `statusMessage = "Autopilot: \(summary.bannerText)"`. Never call `applyMetadataSnapshot`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "AppModelTests.testRunAutopilotProducesPendingProposalsWithoutWritingMetadata|AppModelTests.testRunAutopilotIsIdempotentForTheSameScope"`
Expected: PASS. Then `swift test --filter AppModelTests` — PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: orchestrate autopilot proposal runs over a scope"
```

---

### Task 5: Auto-cull summary banner (Grid + loupe)

Render `autopilotRunSummary` as the design's banner — "N keepers · N rejects · dupes→stacks" with **Review**, **Undo all**, and **Dismiss**. Presentation-model-first: a `AutopilotBannerPresentation` struct owns the copy and button enablement; the SwiftUI view is thin. Review and Undo all call into methods that land in Tasks 7 and 9 respectively; until then they are wired to stubs that set a status message, so this task stays landable on its own.

**Estimated scope:** ~300 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift`
- Test: `Tests/TeststripAppTests/AutopilotBannerPresentationTests.swift` (new)

**Interfaces:**
- Consumes: `AppModel.autopilotRunSummary` (Task 4), `dismissAutopilotRunSummary()` (add: sets `autopilotRunSummary = nil`).
- Produces: `struct AutopilotBannerPresentation: Equatable { init(summary: AutopilotRunSummary); var title: String; var detailText: String; var canUndoAll: Bool }` and a `fileprivate struct AutopilotBannerView`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripAppTests/AutopilotBannerPresentationTests.swift`:

```swift
import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class AutopilotBannerPresentationTests: XCTestCase {
    func testBannerSummarizesKeepersRejectsAndStacks() {
        let summary = AutopilotRunSummary(
            runID: AutopilotRunID(rawValue: "r"),
            keeperCount: 890, rejectCount: 340, keywordCount: 12, stackCount: 27
        )
        let presentation = AutopilotBannerPresentation(summary: summary)
        XCTAssertEqual(presentation.title, "Autopilot reviewed 1,230 frames")
        XCTAssertEqual(presentation.detailText, "890 keepers · 340 rejects · dupes→stacks")
        XCTAssertTrue(presentation.canUndoAll == false) // no committed batch yet
    }

    func testBannerHidesStacksSegmentWithoutStacks() {
        let summary = AutopilotRunSummary(
            runID: AutopilotRunID(rawValue: "r"),
            keeperCount: 5, rejectCount: 2, keywordCount: 0, stackCount: 0
        )
        XCTAssertEqual(AutopilotBannerPresentation(summary: summary).detailText, "5 keepers · 2 rejects")
    }
}
```

(Requires `AutopilotRunSummary` to have a memberwise `init` with these fields — add it in Task 4's struct.)

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AutopilotBannerPresentationTests`
Expected: compile FAILURE — `cannot find 'AutopilotBannerPresentation' in scope`.

- [ ] **Step 3: Implement presentation + view**

Add `AutopilotBannerPresentation` and `AutopilotBannerView` to `LibraryGridView.swift` (near `CullingCompletionBannerView`). `title` = `"Autopilot reviewed \(number(keeperCount + rejectCount)) frames"` using the repo's grouped number formatting (`Self`-level formatter or `NumberFormatter` with grouping; match existing usage). `detailText` = the summary's `bannerText`. `canUndoAll` reflects whether a committed batch exists — expose `AppModel.canUndoAutopilotRun` (returns false until Task 9; wire it now as `metadataUndoStack.last?.label == "Autopilot"` once Task 8 lands, but this task ships it hardcoded `false` with a TODO comment referencing Task 9). Render the banner at the top of the Grid content and in `LoupeView.body` when `model.autopilotRunSummary != nil`, with Review (calls `model.beginAutopilotReview()` — stub in this task: `statusMessage = "Autopilot review coming"`), Undo all (disabled unless `canUndoAll`), Dismiss (`model.dismissAutopilotRunSummary()`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AutopilotBannerPresentationTests`
Expected: PASS. Then `swift test --filter TeststripAppTests` — PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/AutopilotBannerPresentationTests.swift
git commit -m "feat: render the autopilot auto-cull banner"
```

---

### Task 6: KEEP / CUT badges on grid results

Every grid cell whose asset has a pending pick/reject proposal shows a KEEP or CUT badge (design 1b's result badges), distinct from the committed flag overlay so the user can tell "proposed" from "decided" at a glance. Driven by `autopilotProposalDecision(for:)` (Task 4).

**Estimated scope:** ~230 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (main grid cell body; `filmstripDecisionOverlay` sibling)
- Test: `Tests/TeststripAppTests/LibraryGridChromeTests.swift`

**Interfaces:**
- Consumes: `AppModel.autopilotProposalDecision(for:)` (Task 4).
- Produces: `struct AutopilotBadgePresentation: Equatable { static func badge(for kind: AutopilotProposalKind?) -> (text: String, isKeep: Bool)? }` and a `gridAutopilotBadge(for:)` view helper in the grid cell.

- [ ] **Step 1: Write the failing test**

Add to `Tests/TeststripAppTests/LibraryGridChromeTests.swift`:

```swift
    func testAutopilotBadgeMapsKindToKeepOrCut() {
        XCTAssertEqual(AutopilotBadgePresentation.badge(for: .pick)?.text, "KEEP")
        XCTAssertEqual(AutopilotBadgePresentation.badge(for: .pick)?.isKeep, true)
        XCTAssertEqual(AutopilotBadgePresentation.badge(for: .reject)?.text, "CUT")
        XCTAssertEqual(AutopilotBadgePresentation.badge(for: .reject)?.isKeep, false)
        XCTAssertNil(AutopilotBadgePresentation.badge(for: .keyword))
        XCTAssertNil(AutopilotBadgePresentation.badge(for: nil))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LibraryGridChromeTests.testAutopilotBadgeMapsKindToKeepOrCut`
Expected: compile FAILURE — `cannot find 'AutopilotBadgePresentation' in scope`.

- [ ] **Step 3: Implement badge + overlay**

Add `AutopilotBadgePresentation` to `LibraryGridView.swift`. In the main grid cell body (the `CachedPreviewImage` cell around ~grid content), add a top-leading overlay: when `AutopilotBadgePresentation.badge(for: model.autopilotProposalDecision(for: asset.id))` is non-nil, render a small capsule ("KEEP" green / "CUT" red, `.caption2.weight(.bold)`, translucent black backing) positioned so it does not collide with the existing flag/rating overlay (place KEEP/CUT top-leading, keep flags bottom-leading). Add an accessibility value segment "Proposed keep"/"Proposed cut".

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LibraryGridChromeTests`
Expected: PASS. Then `swift test --filter TeststripAppTests` — PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/LibraryGridChromeTests.swift
git commit -m "feat: show KEEP and CUT badges on proposed grid frames"
```

---

### Task 7: Autopilot review surface

"Review" loads the pending-proposal assets into the grid as a dedicated scope with the KEEP/CUT badges visible and a review toolbar exposing **Commit selected**, **Commit all**, and **Dismiss selected**. Reuses the existing multi-select grid; the toolbar acts on the selection. Commit/dismiss land in Task 8 — this task builds the scope + toolbar and wires the buttons to Task 8's methods as stubs that throw `invalidState("not yet implemented")` guarded behind a feature check, OR (cleaner) sequence Task 8 to merge immediately after and land the buttons live. Recommended: land Task 7 with the review scope + toolbar rendering, buttons calling Task 8 methods that this task adds as no-op-safe stubs returning 0, then Task 8 fills them in.

**Estimated scope:** ~300 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`beginAutopilotReview()`, review scope)
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (review toolbar)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `pendingAutopilotProposals` (Task 4), `applyAssetSet`/grid loading machinery, `selectedBatchAssetIDsInCatalogOrder` (:4614 usage).
- Produces:
  - `public func beginAutopilotReview() throws` — loads the distinct pending-proposal asset IDs into `assets` (via an in-memory scope, mirroring how `applyReviewQueue` narrows the grid), sets `selectedView = .grid`, publishes an `isAutopilotReviewActive = true` flag.
  - `public private(set) var isAutopilotReviewActive: Bool`
  - `public var autopilotReviewProposalCount: Int`

- [ ] **Step 1: Write the failing test**

```swift
    func testBeginAutopilotReviewLoadsProposedAssets() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "rev-lead", path: "/Photos/Job/rev-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "rev-alt", path: "/Photos/Job/rev-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, _) = try makeModelWithCatalogAssets(named: "autopilot-review", assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "1", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.3), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)
        _ = try model.runAutopilot(scope: .visible)

        try model.beginAutopilotReview()

        XCTAssertTrue(model.isAutopilotReviewActive)
        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(Set(model.assets.map(\.id)), [lead.id, alternate.id])
        XCTAssertEqual(model.autopilotReviewProposalCount, 2)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppModelTests.testBeginAutopilotReviewLoadsProposedAssets`
Expected: compile FAILURE — `value of type 'AppModel' has no member 'beginAutopilotReview'`.

- [ ] **Step 3: Implement the review scope + toolbar**

Implement `beginAutopilotReview()` to narrow the grid to the distinct asset IDs across `pendingAutopilotProposals` (load those assets from the repository into `assets`, clearing set/query filters like `applyReviewQueue` does, but source the membership from the proposal set rather than a `SetQuery`). Set `isAutopilotReviewActive`, exit it on any subsequent `reload()`/sidebar navigation. In `LibraryGridView`, when `model.isAutopilotReviewActive`, render a review toolbar above the grid with "Commit \(selectedCount)" / "Commit all \(count)" / "Dismiss selected" buttons calling `model.commitAutopilotProposals(assetIDs:)` / `model.commitAllAutopilotProposals()` / `model.dismissAutopilotProposals(assetIDs:)` (Task 8). Point the banner's Review button (`beginAutopilotReview()`) at this now.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppModelTests.testBeginAutopilotReviewLoadsProposedAssets`
Expected: PASS. Then `swift test --filter TeststripAppTests` — PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: add the autopilot proposal review surface"
```

---

### Task 8: Commit lifecycle (commit selected / commit all)

Committing pending proposals applies their metadata changes through the grouped-undo path (Task 1) as ONE group labeled `"Autopilot"`, then marks those proposals `committed`. Pick/reject set the flag; keyword appends the keyword. A commit for a scope produces exactly one undo group regardless of asset count, so Task 9's Undo all is a single gesture.

**Estimated scope:** ~360 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift`
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `applyMetadataSnapshot(assetID:metadata:)` (:5220), `recordMetadataChangeGroup(label:changes:)` (Task 1), repository `updateAutopilotProposalStatus`, `pendingAutopilotProposals`.
- Produces:
  - `@discardableResult public func commitAutopilotProposals(assetIDs: [AssetID]) throws -> Int`
  - `@discardableResult public func commitAllAutopilotProposals() throws -> Int`
  - `@discardableResult public func dismissAutopilotProposals(assetIDs: [AssetID]) throws -> Int`
  - `public private(set) var lastCommittedAutopilotRunID: AutopilotRunID?`

- [ ] **Step 1: Write the failing tests**

```swift
    func testCommitAllAutopilotProposalsWritesFlagsAndKeywordsAsOneUndoGroup() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "commit-lead", path: "/Photos/Job/commit-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "commit-alt", path: "/Photos/Job/commit-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "commit-autopilot", assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "1", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.3), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)
        _ = try model.runAutopilot(scope: .visible)

        let committed = try model.commitAllAutopilotProposals()

        XCTAssertEqual(committed, 2)
        XCTAssertEqual(try repository.asset(id: alternate.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: lead.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.pendingAutopilotProposalCount(), 0)
        XCTAssertEqual(model.lastUndoableActionLabel, "Autopilot")

        // Exactly one undo group reverts the whole batch.
        try model.undoMetadataChange()
        XCTAssertNil(try repository.asset(id: alternate.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: lead.id).metadata.flag)
        XCTAssertFalse(model.canUndoMetadataChange)
    }

    func testDismissAutopilotProposalsLeavesMetadataUntouched() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "dismiss-lead", path: "/Photos/Job/dismiss-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "dismiss-alt", path: "/Photos/Job/dismiss-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "dismiss-autopilot", assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "1", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.3), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)
        _ = try model.runAutopilot(scope: .visible)

        let dismissed = try model.dismissAutopilotProposals(assetIDs: [lead.id])

        XCTAssertEqual(dismissed, 1)
        XCTAssertNil(try repository.asset(id: lead.id).metadata.flag)
        XCTAssertEqual(model.autopilotProposalDecision(for: lead.id), nil)
        XCTAssertEqual(model.autopilotProposalDecision(for: alternate.id), .pick)
        XCTAssertFalse(model.canUndoMetadataChange)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AppModelTests.testCommitAllAutopilotProposalsWritesFlagsAndKeywordsAsOneUndoGroup|AppModelTests.testDismissAutopilotProposalsLeavesMetadataUntouched"`
Expected: compile FAILURE — `value of type 'AppModel' has no member 'commitAllAutopilotProposals'`.

- [ ] **Step 3: Implement commit/dismiss**

For a commit set: read the target pending proposals, group by asset, compute each asset's `updatedMetadata` (apply `.pick`/`.reject` to `flag`, append `keyword`s), call `applyMetadataSnapshot` per asset, accumulate `MetadataChange`s, then `recordMetadataChangeGroup(label: "Autopilot", changes: changes)` ONCE. Mark those proposal IDs `committed` via the repository, refresh `pendingAutopilotProposals`, set `lastCommittedAutopilotRunID`, XMP sync rides `applyMetadataSnapshot` (via `syncMetadataSidecar`) exactly like every other write. `dismissAutopilotProposals` marks proposal IDs `dismissed` and refreshes — no metadata write, no undo entry. `commitAllAutopilotProposals` = commit the distinct asset IDs of all pending proposals. Set status messages (`"Committed \(count) autopilot decisions"`, `"Dismissed \(count) proposals"`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "AppModelTests.testCommitAllAutopilotProposalsWritesFlagsAndKeywordsAsOneUndoGroup|AppModelTests.testDismissAutopilotProposalsLeavesMetadataUntouched"`
Expected: PASS. Then `swift test --filter AppModelTests` — PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: commit autopilot proposals as one undoable group"
```

---

### Task 9: Undo all

The banner's **Undo all** reverses the last committed autopilot batch in one gesture and returns those proposals to `pending` so they are reviewable again. It reverts the `"Autopilot"` undo group (Task 8) and flips the committed proposals back to `pending`, restoring the KEEP/CUT badges.

**Estimated scope:** ~230 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (enable the banner's Undo all)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `undoMetadataChange()` (Task 1), `metadataUndoStack.last?.label`, `lastCommittedAutopilotRunID` (Task 8), repository `updateAutopilotProposalStatus`.
- Produces:
  - `public var canUndoAutopilotRun: Bool` (`metadataUndoStack.last?.label == "Autopilot"`)
  - `public func undoAutopilotRun() throws`

- [ ] **Step 1: Write the failing test**

```swift
    func testUndoAutopilotRunRevertsMetadataAndRestoresPendingProposals() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "undoall-lead", path: "/Photos/Job/undoall-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "undoall-alt", path: "/Photos/Job/undoall-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "undo-all-autopilot", assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "1", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.3), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)
        _ = try model.runAutopilot(scope: .visible)
        _ = try model.commitAllAutopilotProposals()
        XCTAssertTrue(model.canUndoAutopilotRun)

        try model.undoAutopilotRun()

        XCTAssertNil(try repository.asset(id: alternate.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: lead.id).metadata.flag)
        XCTAssertEqual(try repository.pendingAutopilotProposalCount(), 2)
        XCTAssertEqual(model.autopilotProposalDecision(for: alternate.id), .pick)
        XCTAssertFalse(model.canUndoAutopilotRun)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppModelTests.testUndoAutopilotRunRevertsMetadataAndRestoresPendingProposals`
Expected: compile FAILURE — `value of type 'AppModel' has no member 'canUndoAutopilotRun'`.

- [ ] **Step 3: Implement undo-all**

`undoAutopilotRun()` guards `canUndoAutopilotRun`, captures `lastCommittedAutopilotRunID`, calls `undoMetadataChange()` (reverts the "Autopilot" group), then flips that run's `committed` proposals back to `pending` via `updateAutopilotProposalStatus`, refreshes `pendingAutopilotProposals`, and sets `statusMessage = "Undid autopilot batch"`. Enable the banner's Undo all button (`AutopilotBannerPresentation.canUndoAll = model.canUndoAutopilotRun`, calling `model.undoAutopilotRun()`); remove the Task 5 TODO.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppModelTests.testUndoAutopilotRunRevertsMetadataAndRestoresPendingProposals`
Expected: PASS. Then `swift test --filter TeststripAppTests` — PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: undo a committed autopilot batch in one gesture"
```

---

### Task 10: Natural-language Ask translation (opt-in LLM, deterministic fallback)

Translate a natural-language Ask ("TESTSTRIP READS" in design 1b) into the SAME `LibrarySearchIntent` predicates/chips the deterministic parser produces, so the result renders as fully-removable chips. The LLM path is opt-in (an endpoint configuration reusing the `LocalHTTPModelProvider` seam) and defaults OFF; with no endpoint or on any error, the deterministic `LibrarySearchIntent.parse` is the sole path and behavior is unchanged.

**Estimated scope:** ~560 LOC including tests.

**Files:**
- Create: `Sources/TeststripCore/Autopilot/AutopilotQueryTranslator.swift`
- Modify: `Sources/TeststripApp/AppModel.swift` (translation wiring behind the Ask)
- Test: `Tests/TeststripCoreTests/AutopilotQueryTranslatorTests.swift` (new), `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `LocalHTTPModelTransport` + `LocalHTTPModelHTTPResponse` (Evaluation/LocalHTTPModelProvider.swift), `LibrarySearchIntent.parse` (LibrarySearchIntent.swift:22) as the fallback and as the canonical chip/predicate vocabulary, `librarySearchText`.
- Produces:
  - `public struct AutopilotQueryTranslatorConfiguration: Equatable, Sendable { public var endpoint: URL; public var model: String; public var timeout: TimeInterval }`
  - `public protocol AutopilotQueryTranslator: Sendable { func translate(_ naturalLanguage: String) throws -> String }` (returns a canonical query string in the deterministic parser's field syntax, e.g. `"rating:4 keyword:dog from:2023-06-01"`, which is then fed to `LibrarySearchIntent.parse` so there is ONE predicate vocabulary).
  - `public struct LocalHTTPQueryTranslator: AutopilotQueryTranslator` — POSTs the NL text with a strict prompt to the OpenAI-compatible endpoint, extracts the canonical query string from the response.
  - AppModel: `public var autopilotQueryTranslator: (any AutopilotQueryTranslator)?` (nil = off), `public func applyNaturalLanguageAsk(_ text: String) throws` — translates when a translator is set, else uses the raw text; either way assigns `librarySearchText` (so `activeLibraryFilterRows` renders removable chips) and reloads. On translation failure, fall back to the raw text and set a non-fatal `statusMessage`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TeststripCoreTests/AutopilotQueryTranslatorTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class AutopilotQueryTranslatorTests: XCTestCase {
    func testLocalHTTPTranslatorExtractsCanonicalQueryFromChatResponse() throws {
        let json = """
        {"choices":[{"message":{"content":"{\\"query\\":\\"rating:4 keyword:dog\\"}"}}]}
        """
        let transport = StubTransport(response: LocalHTTPModelHTTPResponse(statusCode: 200, data: Data(json.utf8)))
        let translator = LocalHTTPQueryTranslator(
            configuration: AutopilotQueryTranslatorConfiguration(
                endpoint: URL(string: "http://127.0.0.1:1234/v1/chat/completions")!,
                model: "qwen", timeout: 5
            ),
            transport: transport
        )

        let query = try translator.translate("my four star dog photos")

        XCTAssertEqual(query, "rating:4 keyword:dog")
        // The translated query flows through the SAME deterministic vocabulary.
        let intent = LibrarySearchIntent.parse(query)
        XCTAssertTrue(intent.chips.contains("Rating >= 4"))
        XCTAssertTrue(intent.chips.contains("Keyword: dog"))
    }

    private struct StubTransport: LocalHTTPModelTransport {
        var response: LocalHTTPModelHTTPResponse
        func response(for request: URLRequest) throws -> LocalHTTPModelHTTPResponse { response }
    }
}
```

Add to `Tests/TeststripAppTests/AppModelTests.swift`:

```swift
    func testAskFallsBackToDeterministicParserWithoutTranslator() throws {
        let asset = makeAsset(id: "ask-fallback", path: "/Photos/Job/ask-fallback.cr2", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(named: "ask-fallback", assets: [asset])
        try model.selectSidebarTarget(.allPhotographs)

        try model.applyNaturalLanguageAsk("rating:5")

        XCTAssertEqual(model.librarySearchText, "rating:5")
        XCTAssertTrue(model.activeLibraryFilterChips.contains("Rating >= 5"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AutopilotQueryTranslatorTests|AppModelTests.testAskFallsBackToDeterministicParserWithoutTranslator"`
Expected: compile FAILURE — `cannot find 'LocalHTTPQueryTranslator' in scope`.

- [ ] **Step 3: Implement the translator + Ask wiring**

Create `AutopilotQueryTranslator.swift`. `LocalHTTPQueryTranslator.translate` builds an OpenAI-compatible chat request (mirroring `LocalHTTPModelProvider.request` minus the image content) with a system/user prompt that instructs the model to emit ONLY `{"query":"<canonical field syntax>"}` using the deterministic parser's supported fields (enumerate them from `LibrarySearchIntent`: `rating:`, `keyword:`, `camera:`, `lens:`, `iso:`, `from:`/`before:`/`date:`, `color:`, `flag`, `folder:`, `signal:`, plus bare `pick`/`reject`/`unevaluated`). Parse the JSON, extract `query`, return it. In `AppModel`, `applyNaturalLanguageAsk` uses the translator when set (guarding errors → fallback to raw text + `statusMessage = "Ask used plain-text search (model unavailable)"`), assigns `librarySearchText`, and `try reload()`. Do NOT auto-run autopilot from the Ask; the Ask is filtering only. Leave `autopilotQueryTranslator` unset by default (opt-in).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "AutopilotQueryTranslatorTests|AppModelTests.testAskFallsBackToDeterministicParserWithoutTranslator"`
Expected: PASS. Then `swift test` — PASS (full suite; confirms the deterministic path is untouched).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Autopilot/AutopilotQueryTranslator.swift Sources/TeststripApp/AppModel.swift Tests/TeststripCoreTests/AutopilotQueryTranslatorTests.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: translate natural-language Ask into removable filter chips"
```

---

### Task 11: Agents panel (honest projection over real work)

Add the design's Agents panel to the Copilot view: named agents — **Culling**, **Auto-keywording**, **Near-duplicate stacking**, **Face grouping**, **Blur & eyes-closed scan** — each with a live status/progress line and a review count, projected from REAL state: running `.recognition` work items, pending proposal counts by kind, detected-stack counts, and `peopleFaceSuggestions`. No agent shows theater; an idle agent reads "idle" with a zero count. This is a presentation-model extension of `CopilotPresentation`, not a new subsystem.

**Estimated scope:** ~500 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/CopilotView.swift` (`CopilotPresentation` + a new `agentRows` section)
- Modify: `Sources/TeststripApp/AppModel.swift` (expose the projection inputs)
- Test: `Tests/TeststripAppTests/CopilotPresentationTests.swift`

**Interfaces:**
- Consumes: `visibleWorkActivities` (:1589, for running recognition work), `pendingAutopilotProposals` (Task 4, counts by kind), `catalogEvaluationKindSummaries` (already fed to `CopilotPresentation`), `peopleFaceSuggestions` (:1262), stack detection count (add `autopilotStackCount` — reuse Task 4's summary or compute over `assets`).
- Produces:
  - `struct AutopilotAgentRow: Equatable, Identifiable { var id: String; var title: String; var statusText: String; var reviewCount: Int; var isBusy: Bool; var systemImage: String }`
  - `CopilotPresentation.agentRows: [AutopilotAgentRow]` (pure derivation) plus the new struct fields it needs (`pendingProposalPickCount`, `pendingProposalKeywordCount`, `detectedStackCount`, `faceSuggestionCount`, `runningRecognitionCount`).

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/CopilotPresentationTests.swift`:

```swift
    func testAgentRowsProjectRealWorkAndProposalCounts() {
        let presentation = CopilotPresentation(
            totalAssetCount: 1000,
            activeFilterChips: [],
            visibleWorkActivities: [
                AppWorkActivity(kind: .recognition, status: .running, title: "Evaluate photo", detail: "Running apple-vision", completedUnitCount: 0, totalUnitCount: 1, failureCount: 0)
            ],
            reviewQueueCounts: [:],
            evaluationSummaries: [],
            pendingMetadataSyncCount: 0,
            metadataSyncConflictCount: 0,
            canRequestVisibleAssetEvaluations: true,
            pendingProposalPickCount: 340,
            pendingProposalKeywordCount: 12,
            detectedStackCount: 27,
            faceSuggestionCount: 4,
            runningRecognitionCount: 1
        )

        let rows = Dictionary(uniqueKeysWithValues: presentation.agentRows.map { ($0.id, $0) })
        XCTAssertEqual(rows["culling"]?.reviewCount, 340)
        XCTAssertEqual(rows["auto-keywording"]?.reviewCount, 12)
        XCTAssertEqual(rows["near-duplicate-stacking"]?.reviewCount, 27)
        XCTAssertEqual(rows["face-grouping"]?.reviewCount, 4)
        XCTAssertEqual(rows["blur-eyes-closed"]?.isBusy, true) // recognition work running
        XCTAssertEqual(rows["culling"]?.statusText, "340 proposed decisions to review")
    }

    func testAgentRowsReadIdleWhenNothingIsHappening() {
        let presentation = CopilotPresentation(
            totalAssetCount: 0, activeFilterChips: [], visibleWorkActivities: [],
            reviewQueueCounts: [:], evaluationSummaries: [], pendingMetadataSyncCount: 0,
            metadataSyncConflictCount: 0, canRequestVisibleAssetEvaluations: false,
            pendingProposalPickCount: 0, pendingProposalKeywordCount: 0,
            detectedStackCount: 0, faceSuggestionCount: 0, runningRecognitionCount: 0
        )
        XCTAssertTrue(presentation.agentRows.allSatisfy { !$0.isBusy && $0.reviewCount == 0 })
        XCTAssertEqual(presentation.agentRows.first { $0.id == "culling" }?.statusText, "Idle")
    }
```

(The new `CopilotPresentation` fields need memberwise defaults so existing `CopilotPresentationTests` keep compiling — give each a default of `0`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "CopilotPresentationTests.testAgentRowsProjectRealWorkAndProposalCounts|CopilotPresentationTests.testAgentRowsReadIdleWhenNothingIsHappening"`
Expected: compile FAILURE — `CopilotPresentation` has no member `pendingProposalPickCount`.

- [ ] **Step 3: Implement the projection + panel**

Extend `CopilotPresentation` with the five count fields (defaulted) and `agentRows`. Map:
- Culling → pick/reject proposal count; busy when recognition work runs.
- Auto-keywording → keyword proposal count; busy when recognition runs.
- Near-duplicate stacking → detected-stack count; review routes to stack culling.
- Face grouping → `faceSuggestionCount`; review routes to People.
- Blur & eyes-closed scan → busy iff `runningRecognitionCount > 0` (it is the evaluation pass over previews); review count = `likelyIssues` from `reviewQueueCounts`.
Each row: `isBusy ? "Running…" : (reviewCount > 0 ? "\(reviewCount) proposed decisions to review" : "Idle")` (tune per-agent copy). In `CopilotView`, add an `agentsPanel` section rendering the rows (icon, title, status, count) with a Review affordance for non-zero counts routing to the right surface (`beginAutopilotReview()` for culling/keywording; existing People/stack entry for the others). Feed the new fields in `CopilotView.presentation` from the model.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CopilotPresentationTests`
Expected: PASS. Then `swift test --filter TeststripAppTests` — PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/CopilotView.swift Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/CopilotPresentationTests.swift
git commit -m "feat: project real background work into the agents panel"
```

---

### Task 12: Autopilot toggle wiring (per-import + on-demand)

The "Autopilot on" toggle: when ON, a finished import (after Task-2-of-culling-arc auto-evaluation drains) triggers `runAutopilot(scope: importedAssets)` so the auto-cull banner appears; when OFF, import behaves as today. The toggle persists across launches (reuse the app's existing preference persistence) and is exposed in the import confirmation plan and a top-bar control. On-demand `runAutopilot` (Task 4) is always available regardless of the toggle.

**Estimated scope:** ~360 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/ImportConfirmationDraft.swift` + `Sources/TeststripApp/ImportFolderPathDraft.swift` (Autopilot plan step + flag, mirroring the existing `evaluateAfterImport` pattern)
- Modify: `Sources/TeststripApp/AppModel.swift` (persisted toggle; trigger after import auto-eval settles)
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (toggle control in the import sheet + top bar)
- Test: `Tests/TeststripAppTests/ImportConfirmationDraftTests.swift`, `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: the `evaluateAfterImport`/`importAutoEvaluationEnabled` pattern (ImportConfirmationDraft + AppModel, already in the tree), `pendingImportEvaluationAssetIDs` drain point (`enqueueImportEvaluationsForCachedPreviews`, :6098), `runAutopilot(scope:)` (Task 4).
- Produces:
  - `ImportConfirmationDraft.autopilotAfterImport: Bool` (default = the persisted app setting)
  - `ImportPlanSteps.autopilot: ImportPlanStep`
  - `AppModel.autopilotEnabled: Bool` (persisted; `didSet` writes to the app's preference store)
  - `AppModel.beginImportFolder(_:evaluateAfterImport:autopilotAfterImport:)` / `beginImportCard(...:autopilotAfterImport:)` extended signatures
  - private `runImportAutopilotIfEnabled(importedAssetIDs:)` — invoked once the imported set's evaluations have all been queued/completed.

**Design note on the trigger point:** proposal quality depends on signals existing. Trigger `runAutopilot` when the imported set's evaluations have COMPLETED, not merely queued — hook the point where `pendingImportEvaluationAssetIDs` for the import empties AND the corresponding `.recognition` items have finished. Simplest honest implementation: after each recognition-completion in `handleWorkerCommandCompleted`, if autopilot is armed for the active import and no imported asset still has an in-flight/queued evaluation, run autopilot once over the imported asset IDs and disarm. Track `armedAutopilotImportAssetIDs: Set<AssetID>?`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/ImportConfirmationDraftTests.swift`:

```swift
    func testDraftCarriesAutopilotAfterImportDefault() {
        var draft = ImportConfirmationDraft.folder(URL(fileURLWithPath: "/Volumes/Archive/Decades", isDirectory: true))
        draft.autopilotAfterImport = true
        XCTAssertTrue(draft.planSteps.contains { $0.title == "Autopilot cull" })
        draft.autopilotAfterImport = false
        XCTAssertFalse(draft.planSteps.contains { $0.title == "Autopilot cull" })
    }
```

Add to `Tests/TeststripAppTests/AppModelTests.swift` (worker-backed, mirrors `testWorkerImportCompletionQueuesEvaluationsForCachedPreviews`; after the import's evaluations complete, a run summary appears):

```swift
    @MainActor
    func testAutopilotArmedImportPublishesRunSummaryAfterEvaluationsComplete() async throws {
        // Arrange a worker-backed import with autopilot armed, drive one imported
        // asset's preview + evaluation completions, then assert autopilotRunSummary
        // is published and no metadata was written (provisional only).
        // (Follow the RecordingWorkerTransport + emitOutputLine choreography used by
        // testWorkerImportCompletionQueuesEvaluationsForCachedPreviews; set
        // model.autopilotEnabled = true before beginImportFolder.)
    }
```

Fill the second test body following the existing worker-import test choreography (arrange model with `WorkerSupervisor`, `model.autopilotEnabled = true`, `beginImportFolder`, upsert imported asset with a `.focus` `.score` signal, write preview placeholder, emit `completedImport` then the evaluation `completed` for each provider, wait, assert `model.autopilotRunSummary != nil` and the imported asset's `metadata.flag == nil`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "ImportConfirmationDraftTests.testDraftCarriesAutopilotAfterImportDefault|AppModelTests.testAutopilotArmedImportPublishesRunSummaryAfterEvaluationsComplete"`
Expected: FAIL — no `autopilotAfterImport` member / no run summary appears.

- [ ] **Step 3: Implement the toggle + trigger**

Add `autopilotAfterImport` + the `ImportPlanSteps.autopilot` step (title "Autopilot cull", honest detail: "After reads finish, Autopilot proposes keeps and cuts for review — nothing is written until you commit."), conditional on the flag, mirroring `evaluateAfterImport`. Add `autopilotEnabled` persisted flag to `AppModel` (persist via the same mechanism the app uses for other UI prefs — verify the concrete store; do NOT invent one). Thread `autopilotAfterImport` through `beginImportFolder`/`beginImportCard` to arm `armedAutopilotImportAssetIDs`. In the recognition-completion hook, when the armed set's evaluations are all resolved, call `runImportAutopilotIfEnabled` (which runs `runAutopilot(scope: .assetIDs(...))`) once and disarms. Add the toggle control to the import sheet and a top-bar "Autopilot" control bound to `autopilotEnabled`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "ImportConfirmationDraftTests|AppModelTests.testAutopilotArmedImportPublishesRunSummaryAfterEvaluationsComplete"`
Expected: PASS. Then the full ladder below.

- [ ] **Step 5: Full verification**

Run: `swift test`
Expected: PASS (entire suite).

Run: `./script/verify_headless_workflows.sh`
Expected: the headless gate stays green (no regressions to the import/culling ladder).

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripApp/ImportConfirmationDraft.swift Sources/TeststripApp/ImportFolderPathDraft.swift Sources/TeststripApp/AppModel.swift Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/ImportConfirmationDraftTests.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: wire the autopilot toggle into import and on-demand runs"
```

---

## Sequencing and dependencies

1 (grouped undo) → 2 (persistence) → 3 (planner) → 4 (orchestration) are a strict chain. 5 (banner) and 6 (badges) depend on 4. 7 (review surface) depends on 4; 8 (commit) depends on 1 + 7; 9 (undo-all) depends on 8. 10 (NL Ask) depends only on the existing `LibrarySearchIntent` + `LocalHTTPModelTransport` and can land any time after Task 2's module directory exists (it is otherwise independent — it can even precede 3–9). 11 (agents panel) depends on 4 (proposal counts). 12 (toggle) depends on 4 + on the culling-arc auto-evaluation path already in the tree.

**Wave-1 dependencies to honor:** the run-summary and pending-proposal state must survive session restore (wave-1 session restore) — proposals persist in SQLite (Task 2) so a relaunch re-reads pending proposals; on load, rebuild `pendingAutopilotProposals` from `autopilotProposals(status: .pending)` and reconstruct `autopilotRunSummary` from the most recent run's counts. Add that reconstruction to `AppModel.load` as part of Task 4 (note it there). The Ask control (Task 10) shares the top bar with wave-1 search UI; coordinate the field ownership. Loupe zoom, folder sidebar, person filter, and export presets are orthogonal.

## Coordination flags

- **Cross-module scoring (Task 3):** `CullingStackRecommendation` lives in `TeststripApp`; the Core planner cannot import it. Either move its pure `qualityComponent` scorer into Core (coordinate with the culling-signals owners) or inline a Core-local scorer. Do not duplicate divergent scoring logic — that would let the banner's read and the ranking disagree.
- **Scoping decision (flag before Task 3):** committable proposals = pick/reject/keyword only; stacks/faces are projections routed to existing flows. Get Jesse's explicit confirmation; if he wants committable stack/face rows, that is a separate follow-up plan, not a silent expansion here.
- **Preference store (Task 12):** persist `autopilotEnabled` via the app's real preference mechanism — verify it in code before writing; do not invent a store.
