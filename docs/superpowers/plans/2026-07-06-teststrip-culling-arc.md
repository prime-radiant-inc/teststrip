# Teststrip Culling Arc Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the narrative-select culling arc: evaluations queue automatically after import (opt-out at the import confirmation), stack entry lands on the recommended frame so Enter keeps it, survey compare advances group-to-group, the computed recommendation is visible on frames, a completed culling session hands off to its Picks set, and Narrative-Select-style Potential Picks and Close-Ups land on existing infrastructure.

**Architecture:** All work rides existing paths: the import-plan toggle threads a `Bool` from `ImportConfirmationDraft` into `AppModel`'s import entry points; auto-evaluation seeds a pending set at import completion and drains it through the existing `requestEvaluation` worker path as preview-generation work items complete; Enter semantics and stack navigation reuse `CullingStackRecommendation.rankedCandidates` (made internal); completion payoff is a published summary set at the existing status-transition point; Potential Picks is a new `SetQuery` predicate plus `ReviewQueue` case; Close-Ups runs the culling-signals plan's `CoreImageFaceExpressionAnalyzer` on demand over the cached preview — display-only, nothing persists.

**Tech Stack:** Swift 6 / macOS 14, SwiftPM, XCTest, SwiftUI presentation-model pattern (no snapshot tests), SQLite via existing `CatalogRepository`. No new dependencies.

## Global Constraints

- Machine output is DISPLAY-ONLY and provisional. No task auto-writes `AssetMetadata`, flags, ratings, keywords, or XMP. Only explicit user gestures (Enter, P/X, buttons) commit decisions through the existing undoable metadata paths.
- Evaluations run only through the existing `runEvaluation` worker flow over CACHED PREVIEWS (`requestEvaluation(assetID:provider:)` already gates on `hasCachedPreview`); no new worker commands, no new background-work kinds.
- Provider list is always `AppModel.defaultEvaluationProviderNames` (currently `["local-image-metrics", "apple-vision"]`; the concurrent culling-signals plan Task 5 appends `"core-image-faces"` — consuming the constant picks it up automatically).
- No SwiftUI snapshot tests. UI behavior lands as presentation-model members with XCTest model tests (repo pattern in `Tests/TeststripAppTests`).
- Copy separators are the repo's `·` middle dots and `—` em dashes.
- Run all commands from the repo root `/Users/jesse/git/projects/teststrip`.
- **Concurrent-plan coordination:** `docs/superpowers/plans/2026-07-06-teststrip-culling-signals.md` is being implemented in parallel and owns: `EvaluationKind.smile/.eyesOpen/.eyeSharpness`, `FaceExpressionEvaluationProvider` / `CoreImageFaceExpressionAnalyzer`, `CullingAssistPresentation` rationale phrases, `CullingStackRecommendation.rationalePhrases` + eye weights in `weightedQualityScore`, and `CompareSurveyPresentation.signalBadges` (`✦ BEST` badge). Tasks 1–8 here are independent of that plan (rebase before starting any task that touches `LibraryGridView.swift`). Tasks 9 and 10 are **BLOCKED** until the culling-signals tasks named in their headers have landed on main — verify with `git log` before starting them.

## File Map

- Modify: `Sources/TeststripApp/ImportConfirmationDraft.swift` — `evaluateAfterImport` toggle + conditional plan step.
- Modify: `Sources/TeststripApp/ImportFolderPathDraft.swift` — the auto-evaluation `ImportPlanStep`.
- Modify: `Sources/TeststripApp/AppModel.swift` — auto-evaluation seeding/drain, recommended-frame stack entry, survey-advance, completion summary, stack list entries, Potential Picks queue plumbing.
- Modify: `Sources/TeststripApp/LibraryGridView.swift` — confirmation-sheet toggle, `CullingStackRecommendation` access + read helpers, recommendation markers, completion banner, stack list rail, verdict strip, Close-Ups panel wiring.
- Modify: `Sources/TeststripCore/Search/SetQuery.swift` + `Sources/TeststripCore/Catalog/CatalogRepository.swift` — `likelyPick` predicate.
- Create: `Sources/TeststripApp/CloseUpFacesPresentation.swift` — face-crop geometry (Task 10).
- Tests: `Tests/TeststripAppTests/ImportConfirmationDraftTests.swift`, `Tests/TeststripAppTests/AppModelTests.swift`, `Tests/TeststripAppTests/CullingStackRailPresentationTests.swift`, `Tests/TeststripAppTests/CullingAssistPresentationTests.swift`, `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`, `Tests/TeststripAppTests/CloseUpFacesPresentationTests.swift` (new).

---

### Task 1: Import-plan toggle "Evaluate imported frames" (default ON)

The staged import confirmation ("Teststrip will", design 4a) gains a checkbox that controls post-import auto-evaluation and an honest plan step describing it. This task only threads the flag to `AppModel`'s import entry points; Task 2 makes the flag do something.

**Estimated scope:** ~120 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/ImportFolderPathDraft.swift` (add step to `ImportPlanSteps`)
- Modify: `Sources/TeststripApp/ImportConfirmationDraft.swift:171-260`
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`importConfirmationSheet` at ~1465, `confirmImport` at ~2249, `importFolder`/`importCard` at ~2275)
- Modify: `Sources/TeststripApp/AppModel.swift` (`beginImportFolder` at ~7918, `beginImportCard` at ~7989)
- Test: `Tests/TeststripAppTests/ImportConfirmationDraftTests.swift`

**Interfaces:**
- Consumes: `ImportConfirmationDraft` (memberwise struct with static `.folder(_:)` / `.card(source:destinationRoot:)` factories), `ImportPlanStep(title:detail:stage:)`.
- Produces (Task 2 relies on these exact signatures):
  - `ImportConfirmationDraft.evaluateAfterImport: Bool` (default `true`)
  - `ImportPlanSteps.autoEvaluation: ImportPlanStep`
  - `AppModel.beginImportFolder(_ folderURL: URL, evaluateAfterImport: Bool = true)`
  - `AppModel.beginImportCard(source: URL, destinationRoot: URL, evaluateAfterImport: Bool = true)`
  - `AppModel.importAutoEvaluationEnabled` (private stored flag, set by both entry points)

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/ImportConfirmationDraftTests.swift`:

```swift
    func testDraftDefaultsToEvaluatingImportedFramesWithPlanStep() {
        let draft = ImportConfirmationDraft.folder(URL(fileURLWithPath: "/Volumes/Archive/Decades", isDirectory: true))

        XCTAssertTrue(draft.evaluateAfterImport)
        XCTAssertEqual(draft.planSteps.last, ImportPlanStep(
            title: "Read imported frames",
            detail: "Focus, exposure, and face reads queue over cached previews as they finish; reads stay provisional until you act.",
            stage: .followUpSetup
        ))
    }

    func testDisablingEvaluateAfterImportRemovesThePlanStep() {
        var draft = ImportConfirmationDraft.folder(URL(fileURLWithPath: "/Volumes/Archive/Decades", isDirectory: true))
        draft.evaluateAfterImport = false

        XCTAssertFalse(draft.planSteps.contains { $0.title == "Read imported frames" })
        XCTAssertEqual(draft.planSteps, ImportPlanSteps.folderInPlace)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "ImportConfirmationDraftTests.testDraftDefaultsToEvaluatingImportedFramesWithPlanStep|ImportConfirmationDraftTests.testDisablingEvaluateAfterImportRemovesThePlanStep"`
Expected: compile FAILURE — `value of type 'ImportConfirmationDraft' has no member 'evaluateAfterImport'`

- [ ] **Step 3: Add the step, the flag, and the conditional plan**

In `Sources/TeststripApp/ImportFolderPathDraft.swift`, add to `enum ImportPlanSteps` (after `followUpSetupSteps`):

```swift
    static let autoEvaluation = ImportPlanStep(
        title: "Read imported frames",
        detail: "Focus, exposure, and face reads queue over cached previews as they finish; reads stay provisional until you act.",
        stage: .followUpSetup
    )
```

In `Sources/TeststripApp/ImportConfirmationDraft.swift`, add the stored property after `var sourceSummary: ImportSourceSummary`:

```swift
    var evaluateAfterImport = true
```

(The static `.folder` / `.card` factories use the memberwise init without this field only if it has a default — they construct `ImportConfirmationDraft(mode:sourceURL:destinationRootURL:destinationUnavailableReason:sourceSummary:)`, which still compiles because the new property has an initial value outside the memberwise list. If the compiler complains at the two factory call sites, add `evaluateAfterImport: true` explicitly there.)

Replace `planSteps` (line ~252):

```swift
    var planSteps: [ImportPlanStep] {
        let baseSteps: [ImportPlanStep]
        switch mode {
        case .folder:
            baseSteps = ImportPlanSteps.folderInPlace
        case .card:
            baseSteps = ImportPlanSteps.cardCopy(destinationName: destinationName ?? "the destination")
        }
        guard evaluateAfterImport else { return baseSteps }
        return baseSteps + [ImportPlanSteps.autoEvaluation]
    }
```

- [ ] **Step 4: Fix the two existing full-array plan expectations**

`Tests/TeststripAppTests/ImportConfirmationDraftTests.swift` has two tests that assert the complete `planSteps` array (`testFolderDraftSummarizesInPlaceCatalogImport` and the card-mode equivalent). Append the new step to the END of each expected array:

```swift
            ImportPlanStep(
                title: "Read imported frames",
                detail: "Focus, exposure, and face reads queue over cached previews as they finish; reads stay provisional until you act.",
                stage: .followUpSetup
            )
```

- [ ] **Step 5: Thread the flag through the sheet and the model entry points**

In `Sources/TeststripApp/LibraryGridView.swift`, inside `importConfirmationSheet(_ draft:)` (line ~1465), insert between `importPlanView(steps: draft.planSteps, width: 440)` and the `HStack` of buttons:

```swift
            Toggle(
                "Read imported frames automatically",
                isOn: Binding(
                    get: { importConfirmationDraft?.evaluateAfterImport ?? true },
                    set: { importConfirmationDraft?.evaluateAfterImport = $0 }
                )
            )
            .toggleStyle(.checkbox)
            .font(.caption)
            .help("Queues the standard evaluation passes over the imported set's cached previews as previews complete. Reads stay provisional; nothing is written without your action.")
```

(`importConfirmationDraft` is the `@State` optional at LibraryGridView.swift:41; `draft.id` does not include `evaluateAfterImport`, so toggling does not re-present the sheet.)

In the same file, update `confirmImport(_ draft:)` (~2249) and the two forwarding helpers (~2275):

```swift
        case .folder:
            FolderSelectionPanel.rememberImportFolder(draft.sourceURL)
            importFolder(draft.sourceURL, evaluateAfterImport: draft.evaluateAfterImport)
        case .card:
            guard let destinationRootURL = draft.destinationRootURL else {
                model.errorMessage = "Card import destination is missing"
                return
            }
            importCard(source: draft.sourceURL, destinationRoot: destinationRootURL, evaluateAfterImport: draft.evaluateAfterImport)
```

```swift
    private func importFolder(_ folderURL: URL, evaluateAfterImport: Bool = true) {
        model.beginImportFolder(folderURL, evaluateAfterImport: evaluateAfterImport)
    }

    private func importCard(source: URL, destinationRoot: URL, evaluateAfterImport: Bool = true) {
        model.beginImportCard(source: source, destinationRoot: destinationRoot, evaluateAfterImport: evaluateAfterImport)
    }
```

In `Sources/TeststripApp/AppModel.swift`, add the stored flag near the other private import state (e.g. next to `workerImportContextsByItemID`):

```swift
    // Captured per import at begin time; only one import runs at a time (isImporting guard).
    private var importAutoEvaluationEnabled = true
```

Change the two public entry-point signatures and set the flag as the FIRST statement in each body:

```swift
    public func beginImportFolder(_ folderURL: URL, evaluateAfterImport: Bool = true) {
        importAutoEvaluationEnabled = evaluateAfterImport
```

```swift
    public func beginImportCard(source: URL, destinationRoot: URL, evaluateAfterImport: Bool = true) {
        importAutoEvaluationEnabled = evaluateAfterImport
```

Also set `importAutoEvaluationEnabled = true` as the first statement of `importFolderInBackground(_:)` (~7846) and `importCardInBackground(source:destinationRoot:)` (~7881) so the programmatic import paths keep the default-ON behavior.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter ImportConfirmationDraftTests`
Expected: PASS (all existing + 2 new, including the two updated full-array tests)

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripApp/ImportFolderPathDraft.swift Sources/TeststripApp/ImportConfirmationDraft.swift Sources/TeststripApp/LibraryGridView.swift Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/ImportConfirmationDraftTests.swift
git commit -m "feat: add evaluate-after-import toggle to the import plan"
```

---

### Task 2: Auto-evaluation of the imported set as previews complete (arc-blocker #1)

At import completion (when the Task 1 flag is ON), every imported asset joins a pending set. Assets whose previews are already cached get their evaluation passes queued immediately; the rest are queued one-by-one from the existing preview-completion hook. Each queued pass is a normal `.recognition` background-work item — visible, pausable, and cancellable in the existing Activity/queue UI — and the pending set is bounded by the import size.

**Estimated scope:** ~220 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`handleWorkerCommandCompleted` at ~5840, `handleWorkerImportCompleted` at ~6103, `beginImportFolder`/`beginImportCard` in-process completion blocks at ~7960/~8035, `importFolderInBackground` at ~7846, `importCardInBackground` at ~7881)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `importAutoEvaluationEnabled` (Task 1), `requestEvaluation(assetID:provider:)` (AppModel.swift:5558, dedups by item ID `evaluation-<asset>-<provider>`), `hasCachedPreview(for:)` (:8562), `Self.previewAssetID(from:)` (:5980), `AppModel.defaultEvaluationProviderNames` (:1295), `LibraryImportResult.importedAssets`.
- Produces:
  - `private var pendingImportEvaluationAssetIDs: Set<AssetID>`
  - `private func scheduleImportAutoEvaluationIfEnabled(result: LibraryImportResult)`
  - `private func enqueueImportEvaluationsForCachedPreviews(assetIDs: [AssetID])`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/AppModelTests.swift` (mirrors `testBeginImportFolderWithWorkerEnqueuesManagedImportAndReloadsOnCompletion` at ~10637; `RecordingWorkerTransport`, `waitForSelectedAsset`, and `writePreviewPlaceholder` already exist in this file):

```swift
    @MainActor
    func testWorkerImportCompletionQueuesEvaluationsForCachedPreviews() async throws {
        let directory = try makeTemporaryDirectory(named: "auto-eval-cached-preview")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 8), transport: transport)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let importedAsset = Asset(
            id: AssetID(rawValue: "auto-eval-imported"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        // Preview already cached before the import completes: evaluations queue immediately.
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: importedAsset.id, level: .grid)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForSelectedAsset(importedAsset.id, in: model)

        let evaluationItemIDs = model.backgroundWorkQueue.items
            .filter { $0.kind == .recognition }
            .map(\.id.rawValue)
        XCTAssertEqual(evaluationItemIDs.sorted(), AppModel.defaultEvaluationProviderNames.map { provider in
            "evaluation-\(importedAsset.id.rawValue)-\(provider)"
        }.sorted())
    }

    @MainActor
    func testPreviewCompletionQueuesEvaluationsForPendingImportedAsset() async throws {
        let directory = try makeTemporaryDirectory(named: "auto-eval-preview-drain")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 8), transport: transport)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let importedAsset = Asset(
            id: AssetID(rawValue: "auto-eval-drained"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        try catalog.repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: importedAsset.id, level: .micro))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForSelectedAsset(importedAsset.id, in: model)
        // No cached preview yet, so nothing queued at completion time.
        XCTAssertFalse(model.backgroundWorkQueue.items.contains { $0.kind == .recognition })

        // The micro preview finishes: the completion hook queues the evaluation passes.
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: importedAsset.id, level: .micro)))
        let previewItemID = WorkSessionID(rawValue: "preview-\(importedAsset.id.rawValue)-micro")
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: previewItemID,
            message: "generated micro preview"
        )))
        try await waitForRecognitionItemCount(AppModel.defaultEvaluationProviderNames.count, in: model)

        let evaluationItemIDs = model.backgroundWorkQueue.items
            .filter { $0.kind == .recognition }
            .map(\.id.rawValue)
        XCTAssertEqual(evaluationItemIDs.sorted(), AppModel.defaultEvaluationProviderNames.map { provider in
            "evaluation-\(importedAsset.id.rawValue)-\(provider)"
        }.sorted())
    }

    @MainActor
    func testDisabledEvaluateAfterImportQueuesNoEvaluations() async throws {
        let directory = try makeTemporaryDirectory(named: "auto-eval-disabled")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 8), transport: transport)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder, evaluateAfterImport: false)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let importedAsset = Asset(
            id: AssetID(rawValue: "auto-eval-off"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: importedAsset.id, level: .grid)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForSelectedAsset(importedAsset.id, in: model)

        XCTAssertFalse(model.backgroundWorkQueue.items.contains { $0.kind == .recognition })
    }
```

And the wait helper next to `waitForSelectedAsset` (~13719):

```swift
    @MainActor
    private func waitForRecognitionItemCount(_ count: Int, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.backgroundWorkQueue.items.filter({ $0.kind == .recognition }).count >= count {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for \(count) recognition work items")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AppModelTests.testWorkerImportCompletionQueuesEvaluationsForCachedPreviews|AppModelTests.testPreviewCompletionQueuesEvaluationsForPendingImportedAsset|AppModelTests.testDisabledEvaluateAfterImportQueuesNoEvaluations"`
Expected: FAIL — no `.recognition` items appear (assertion failures, not compile errors, except the third test compiles only after Task 1 landed).

- [ ] **Step 3: Write the minimal implementation**

In `Sources/TeststripApp/AppModel.swift`, add the pending set next to `importAutoEvaluationEnabled`:

```swift
    private var pendingImportEvaluationAssetIDs: Set<AssetID> = []
```

Add the two helpers (near `requestLatestImportAssetEvaluations`, ~5657):

```swift
    // Seeds the provisional read pass for a finished import. Bounded by the
    // import's asset list; each queued pass is a normal cancellable
    // .recognition work item, so Activity shows and controls all of it.
    private func scheduleImportAutoEvaluationIfEnabled(result: LibraryImportResult) {
        guard importAutoEvaluationEnabled, workerSupervisor != nil else { return }
        let importedAssetIDs = result.importedAssets.map(\.id)
        guard !importedAssetIDs.isEmpty else { return }
        pendingImportEvaluationAssetIDs = Set(importedAssetIDs)
        enqueueImportEvaluationsForCachedPreviews(assetIDs: importedAssetIDs)
    }

    private func enqueueImportEvaluationsForCachedPreviews(assetIDs: [AssetID]) {
        guard workerSupervisor != nil else { return }
        for assetID in assetIDs where pendingImportEvaluationAssetIDs.contains(assetID) {
            guard hasCachedPreview(for: assetID) else { continue }
            pendingImportEvaluationAssetIDs.remove(assetID)
            for provider in AppModel.defaultEvaluationProviderNames {
                do {
                    try requestEvaluation(assetID: assetID, provider: provider)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
```

Hook preview completion: in `handleWorkerCommandCompleted` (~5840), extend the `.completed` branch — after the existing `if completedPreview { ... }` block:

```swift
            if completedPreview,
               let itemID,
               let previewAssetID = Self.previewAssetID(from: itemID) {
                enqueueImportEvaluationsForCachedPreviews(assetIDs: [previewAssetID])
            }
```

Seed at every import-completion site, immediately after the existing `recordCompletedImportActivity(...)` call in each:

1. `handleWorkerImportCompleted` (~6135): after `let outputSetIDs = recordCompletedImportActivity(...)` add `scheduleImportAutoEvaluationIfEnabled(result: result)`.
2. `beginImportFolder`'s in-process `Task` block (after `let outputSetIDs = self.recordCompletedImportActivity(folderURL: folderURL, result: output.result)`): `self.scheduleImportAutoEvaluationIfEnabled(result: output.result)`.
3. `beginImportCard`'s in-process `Task` block: same one-liner.
4. `importFolderInBackground` (~7872): after `let outputSetIDs = recordCompletedImportActivity(folderURL: folderURL, result: output.result)` add `scheduleImportAutoEvaluationIfEnabled(result: output.result)`.
5. `importCardInBackground` (~7908): same one-liner.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "AppModelTests.testWorkerImportCompletionQueuesEvaluationsForCachedPreviews|AppModelTests.testPreviewCompletionQueuesEvaluationsForPendingImportedAsset|AppModelTests.testDisabledEvaluateAfterImportQueuesNoEvaluations"`
Expected: PASS

Then guard against regressions in the import/evaluation suites:

Run: `swift test --filter AppModelTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: queue import evaluations automatically as previews complete"
```

---

### Task 3: Stack entry selects the recommended frame (arc-blocker #2)

Design decision (adopted): stack entry selects the RECOMMENDED frame when one exists, so "Enter keeps what's highlighted" remains the single mental model and keyboard-only Enter-Enter-Enter keeps the ranked best instead of frame 1. When no frames carry quality signals the ranking is empty and entry falls back to the first frame — existing tests keep passing unchanged.

**Estimated scope:** ~110 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift:4125` (`private struct CullingStackRecommendation` → internal)
- Modify: `Sources/TeststripApp/AppModel.swift` (`selectPersistedCullingStack` at ~4074, `beginStackCullingFromLatestImportCompletion` at ~2974)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `CullingStackRecommendation.rankedCandidates(stackAssetIDs:evaluationSignalsByAssetID:) -> [CullingStackRecommendation]` (LibraryGridView.swift:4130 — unchanged shape; the culling-signals plan Task 7 only adds weights inside it), `evaluationSignals(for:)` (AppModel.swift:1701), `selectedExplicitAssetIDs` (:7313).
- Produces (Tasks 4 and 7 reuse this): `AppModel.recommendedCullingStackAssetID(in assetIDs: [AssetID]) -> AssetID?` (private).

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/AppModelTests.swift` (uses the existing `makePersistedStackCullingFixture`, `makeModelWithCompletedImportSession`, `makeAsset(id:path:rating:technicalMetadata:)`, and `Self.technicalMetadata(capturedAt:)` helpers):

```swift
    func testNextStackNavigationSelectsRecommendedFrameWhenRanked() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "stack-entry-recommended",
            sessionID: "stack-entry-recommended-session"
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "1", settingsHash: "default")
        try fixture.repository.recordEvaluationSignals([
            EvaluationSignal(assetID: fixture.secondLead.id, kind: .focus, value: .score(0.4), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: fixture.secondAlternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
        ])
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)

        try fixture.model.applyCullingShortcut(.nextStack)

        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedAssetID, fixture.secondAlternate.id)
        XCTAssertEqual(fixture.model.selectedView, .loupe)
    }

    func testNextStackNavigationFallsBackToFirstFrameWithoutSignals() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "stack-entry-fallback",
            sessionID: "stack-entry-fallback-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)

        try fixture.model.applyCullingShortcut(.nextStack)

        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedAssetID, fixture.secondLead.id)
    }

    func testBeginningStackCullingSelectsRecommendedFrameOfFirstStack() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let stackFirst = makeAsset(
            id: "recommended-entry-first",
            path: "/Photos/Import/recommended-entry-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let stackSecond = makeAsset(
            id: "recommended-entry-second",
            path: "/Photos/Import/recommended-entry-second.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, repository, _) = try makeModelWithCompletedImportSession(
            named: "recommended-entry-stack-culling",
            assets: [stackFirst, stackSecond],
            outputAssetIDs: [stackFirst.id, stackSecond.id]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: stackSecond.id, kind: .focus, value: .score(0.92), confidence: 0.9, provenance: provenance)
        ])

        _ = try model.beginStackCullingFromLatestImportCompletion()

        XCTAssertEqual(model.selectedAssetID, stackSecond.id)
        XCTAssertEqual(model.selectedView, .loupe)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AppModelTests.testNextStackNavigationSelectsRecommendedFrameWhenRanked|AppModelTests.testNextStackNavigationFallsBackToFirstFrameWithoutSignals|AppModelTests.testBeginningStackCullingSelectsRecommendedFrameOfFirstStack"`
Expected: FAIL — the ranked tests select the stack's FIRST frame (`secondLead` / `stackFirst`); the fallback test passes (locks the behavior).

- [ ] **Step 3: Write the minimal implementation**

In `Sources/TeststripApp/LibraryGridView.swift:4125`, change the access level (one word — coordinate with the culling-signals plan Task 7 which edits this struct's internals; rebase first):

```swift
struct CullingStackRecommendation: Equatable {
```

In `Sources/TeststripApp/AppModel.swift`, add the helper near `selectedCullingStackEvaluationSignals()` (~3932):

```swift
    // The ranked best-of-stack frame, or nil when no frame carries quality signals.
    private func recommendedCullingStackAssetID(in assetIDs: [AssetID]) -> AssetID? {
        guard assetIDs.count > 1 else { return nil }
        let signalsByAssetID = Dictionary(uniqueKeysWithValues: assetIDs.map { assetID in
            (assetID, evaluationSignals(for: assetID))
        })
        return CullingStackRecommendation.rankedCandidates(
            stackAssetIDs: assetIDs,
            evaluationSignalsByAssetID: signalsByAssetID
        ).first?.assetID
    }
```

In `selectPersistedCullingStack(_:)` (~4074) replace the selection line:

```swift
        try applyAssetSet(id: targetSetID)
        let stackAssetIDs = selectedExplicitAssetIDs ?? []
        selectAssetID(recommendedCullingStackAssetID(in: stackAssetIDs) ?? stackAssetIDs.first)
        selectedView = .loupe
        return true
```

In `beginStackCullingFromLatestImportCompletion()` (~2974) replace:

```swift
        if let firstAssetID = stacks.first?.assetIDs.first {
            selectAssetID(firstAssetID)
        }
```

with:

```swift
        if let firstStackAssetIDs = stacks.first?.assetIDs {
            selectAssetID(recommendedCullingStackAssetID(in: firstStackAssetIDs) ?? firstStackAssetIDs.first)
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppModelTests`
Expected: PASS — including the pre-existing `testBeginningStackCullingFromLatestImportSelectsFirstDetectedStack` and `testAcceptingPersistedStackSelectionUpdatesCullingSessionProgress`, whose fixtures carry no quality signals and therefore still land on the first frame.

Also run: `swift test --filter CullingStackRailPresentationTests`
Expected: PASS (access-level change only)

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: select the recommended frame on culling stack entry"
```

---

### Task 4: Survey compare advances to the next group after a decision (arc-blocker #4)

After "Keep primary/top signal · reject N" or "Keep all", the compare surface moves to the next group: the next persisted stack for stack sessions (staying in `.compare`), or the next candidate-stack/window in the loaded scope otherwise. ↑/↓ stack navigation also stops kicking the user out of compare.

**Estimated scope:** ~170 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`selectPersistedCullingStack` at ~4074, `keepCompareAssetAndRejectAlternates(assetID:compareGroup:)` at ~3566, `keepAllCompareAssets` at ~3582)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `recommendedCullingStackAssetID(in:)` (Task 3), `compareAssets(limit:)` (:3513), `updateCompareSetAfterSelectionChange` behavior (:3712 — re-anchors `compareAssetIDs` automatically when the selection leaves the current set), `hasMoreAssets` (:1423), `loadMoreAssets()`.
- Produces: `private func advanceCompareGroupAfterDecision(previousGroup: [Asset]) throws` — final `selectPersistedCullingStack` body below is the combined Task 3 + Task 4 version.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/AppModelTests.swift`:

```swift
    func testCompareGroupDecisionAdvancesToNextPersistedStackInCompare() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "compare-advance-persisted",
            sessionID: "compare-advance-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)
        fixture.model.selectedView = .compare
        XCTAssertEqual(fixture.model.compareAssets().map(\.id), [fixture.firstLead.id, fixture.firstAlternate.id])

        try fixture.model.keepComparePrimaryAndRejectAlternates()

        XCTAssertEqual(try fixture.repository.asset(id: fixture.firstLead.id).metadata.flag, .pick)
        XCTAssertEqual(try fixture.repository.asset(id: fixture.firstAlternate.id).metadata.flag, .reject)
        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedView, .compare)
        XCTAssertEqual(fixture.model.compareAssets().map(\.id), [fixture.secondLead.id, fixture.secondAlternate.id])
    }

    func testCompareGroupDecisionAdvancesToNextCandidateStackWindow() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let firstBurstLead = makeAsset(
            id: "compare-advance-a1",
            path: "/Photos/Job/compare-advance-a1.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let firstBurstAlternate = makeAsset(
            id: "compare-advance-a2",
            path: "/Photos/Job/compare-advance-a2.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let secondBurstLead = makeAsset(
            id: "compare-advance-b1",
            path: "/Photos/Job/compare-advance-b1.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(60))
        )
        let secondBurstAlternate = makeAsset(
            id: "compare-advance-b2",
            path: "/Photos/Job/compare-advance-b2.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(61))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-advance-window",
            assets: [firstBurstLead, firstBurstAlternate, secondBurstLead, secondBurstAlternate]
        )
        model.select(firstBurstLead.id)
        model.selectedView = .compare
        XCTAssertEqual(model.compareAssets().map(\.id), [firstBurstLead.id, firstBurstAlternate.id])

        try model.keepComparePrimaryAndRejectAlternates()

        XCTAssertEqual(try repository.asset(id: firstBurstLead.id).metadata.flag, .pick)
        XCTAssertEqual(model.selectedAssetID, secondBurstLead.id)
        XCTAssertEqual(model.selectedView, .compare)
        XCTAssertEqual(model.compareAssets().map(\.id), [secondBurstLead.id, secondBurstAlternate.id])
    }

    func testCompareGroupDecisionStaysPutOnLastGroup() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "compare-advance-last",
            sessionID: "compare-advance-last-session"
        )
        try fixture.model.applyAssetSet(id: fixture.secondSet.id)
        fixture.model.select(fixture.secondLead.id)
        fixture.model.selectedView = .compare

        try fixture.model.keepComparePrimaryAndRejectAlternates()

        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedView, .compare)
        XCTAssertEqual(fixture.model.statusMessage, "Kept \(fixture.secondLead.originalURL.lastPathComponent); rejected 1 alternates")
    }

    func testStackNavigationStaysInCompareWhenCompareIsActive() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "compare-stack-navigation",
            sessionID: "compare-stack-navigation-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)
        fixture.model.selectedView = .compare

        try fixture.model.applyCullingShortcut(.nextStack)

        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedView, .compare)
        XCTAssertEqual(fixture.model.compareAssets().map(\.id), [fixture.secondLead.id, fixture.secondAlternate.id])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AppModelTests.testCompareGroupDecisionAdvancesToNextPersistedStackInCompare|AppModelTests.testCompareGroupDecisionAdvancesToNextCandidateStackWindow|AppModelTests.testCompareGroupDecisionStaysPutOnLastGroup|AppModelTests.testStackNavigationStaysInCompareWhenCompareIsActive"`
Expected: FAIL — decisions leave the compare set in place, and stack navigation flips `selectedView` to `.loupe`.

- [ ] **Step 3: Write the minimal implementation**

In `Sources/TeststripApp/AppModel.swift`, replace the full body of `selectPersistedCullingStack(_:)` with the combined Task 3 + Task 4 version:

```swift
    @discardableResult
    private func selectPersistedCullingStack(_ direction: CullingStackNavigationDirection) throws -> Bool {
        guard let targetSetID = try persistedCullingStackSetID(direction) else {
            return false
        }
        let keepSurveyCompare = selectedView == .compare
        try applyAssetSet(id: targetSetID)
        let stackAssetIDs = selectedExplicitAssetIDs ?? []
        selectAssetID(recommendedCullingStackAssetID(in: stackAssetIDs) ?? stackAssetIDs.first)
        selectedView = keepSurveyCompare ? .compare : .loupe
        return true
    }
```

Add the advance helper near `updateCompareSetAfterSelectionChange` (~3712):

```swift
    // After a compare group decision, move the survey to the next group:
    // the next persisted stack for stack sessions, otherwise the frame after
    // the decided group (selection change re-anchors compareAssetIDs).
    private func advanceCompareGroupAfterDecision(previousGroup: [Asset]) throws {
        guard selectedView == .compare else { return }
        if try selectPersistedCullingStack(.next) {
            return
        }
        let groupAssetIDs = Set(previousGroup.map(\.id))
        guard let lastGroupIndex = assets.lastIndex(where: { groupAssetIDs.contains($0.id) }) else { return }
        if lastGroupIndex == assets.count - 1, hasMoreAssets {
            try loadMoreAssets()
        }
        let nextIndex = lastGroupIndex + 1
        guard assets.indices.contains(nextIndex) else { return }
        selectAssetID(assets[nextIndex].id)
    }
```

Call it from both decision paths, immediately BEFORE the `statusMessage` assignment so the decision feedback wins:

In `keepCompareAssetAndRejectAlternates(assetID:compareGroup:)` (~3566):

```swift
        let summary = try applyCompareFlags(
            compareGroup.reduce(into: [AssetID: PickFlag]()) { flags, compareAsset in
                flags[compareAsset.id] = compareAsset.id == assetID ? .pick : .reject
            },
            to: compareGroup
        )
        try advanceCompareGroupAfterDecision(previousGroup: compareGroup)

        statusMessage = summary.rejectedCount == 0
            ? "Kept \(keptAsset.originalURL.lastPathComponent)"
            : "Kept \(keptAsset.originalURL.lastPathComponent); rejected \(summary.rejectedCount) alternates"
```

In `keepAllCompareAssets()` (~3582):

```swift
        let summary = try applyCompareFlags(
            compareGroup.reduce(into: [AssetID: PickFlag]()) { flags, compareAsset in
                flags[compareAsset.id] = .pick
            },
            to: compareGroup
        )
        try advanceCompareGroupAfterDecision(previousGroup: compareGroup)

        statusMessage = "Kept all \(summary.pickedCount) compare frames"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppModelTests`
Expected: PASS (the whole class — compare and stack-navigation tests included)

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: advance survey compare to the next group after a decision"
```

---

### Task 5: Culling completion payoff — banner + "View Picks" (arc-blocker #3)

When the last frame of a culling session gets flagged, the session already flips to `.completed` silently. This task publishes a completion summary at that transition and renders a banner (loupe + compare) with the pick/reject tally and a "View Picks" action that applies the session's Picks output set.

**Estimated scope:** ~260 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`updateActiveCullingSessionProgressAfterFlagChange` at ~7413, `updatePersistedStackCullingSessionProgress` at ~7452, `beginCullingSession` at ~3465, `beginStackCullingFromLatestImportCompletion` at ~2946, `beginManualCullingFromCompareSet` at ~3017)
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`LoupeView.body` at ~2668, `CompareView.body` at ~4185)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `Self.cullingOutputSetID(sessionID:)` (:7754), `refreshCullingSessionOutputSet` (:7496 — runs before the status save, so `session.outputSetIDs` is current), `applyAssetSet(id:)` (:3292 — lands in `.grid`).
- Produces:
  - `public struct CullingSessionCompletionSummary: Equatable, Identifiable, Sendable { sessionID, title, pickCount, rejectCount, picksSetID }` with `var detailText: String`
  - `public private(set) var cullingSessionCompletion: CullingSessionCompletionSummary?`
  - `public func openCullingSessionPicks() throws`
  - `public func dismissCullingSessionCompletion()`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/AppModelTests.swift`:

```swift
    func testFlaggingLastStackFramePublishesCullingCompletionSummary() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "completion-summary",
            sessionID: "completion-summary-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)
        try fixture.model.applyCullingShortcut(.acceptStackSelection)
        XCTAssertNil(fixture.model.cullingSessionCompletion)

        // Auto-advance landed on the second stack; decide it too.
        try fixture.model.applyCullingShortcut(.acceptStackSelection)

        let completion = try XCTUnwrap(fixture.model.cullingSessionCompletion)
        XCTAssertEqual(completion.sessionID, WorkSessionID(rawValue: "completion-summary-session"))
        XCTAssertEqual(completion.title, "Cull persisted stacks")
        XCTAssertEqual(completion.pickCount, 2)
        XCTAssertEqual(completion.rejectCount, 2)
        XCTAssertEqual(completion.picksSetID, AssetSetID(rawValue: "work-output-completion-summary-session-picks"))
        XCTAssertEqual(completion.detailText, "2 picks · 2 rejects — Cull persisted stacks")
    }

    func testOpeningCullingCompletionPicksAppliesTheOutputSet() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "completion-open-picks",
            sessionID: "completion-open-picks-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)
        try fixture.model.applyCullingShortcut(.acceptStackSelection)
        try fixture.model.applyCullingShortcut(.acceptStackSelection)
        let completion = try XCTUnwrap(fixture.model.cullingSessionCompletion)
        let picksSetID = try XCTUnwrap(completion.picksSetID)

        try fixture.model.openCullingSessionPicks()

        XCTAssertEqual(fixture.model.selectedAssetSetID, picksSetID)
        XCTAssertEqual(fixture.model.selectedView, .grid)
        XCTAssertEqual(
            Set(fixture.model.assets.map(\.id)),
            [fixture.firstLead.id, fixture.secondLead.id]
        )
        XCTAssertNil(fixture.model.cullingSessionCompletion)
    }

    func testClearingAFlagWithdrawsTheCompletionSummary() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "completion-withdrawn",
            sessionID: "completion-withdrawn-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)
        try fixture.model.applyCullingShortcut(.acceptStackSelection)
        try fixture.model.applyCullingShortcut(.acceptStackSelection)
        XCTAssertNotNil(fixture.model.cullingSessionCompletion)

        fixture.model.select(fixture.secondAlternate.id)
        try fixture.model.setFlagForSelectedAsset(nil)

        XCTAssertNil(fixture.model.cullingSessionCompletion)
    }

    func testStartingANewCullingSessionClearsTheCompletionSummary() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "completion-cleared-on-start",
            sessionID: "completion-cleared-on-start-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)
        try fixture.model.applyCullingShortcut(.acceptStackSelection)
        try fixture.model.applyCullingShortcut(.acceptStackSelection)
        XCTAssertNotNil(fixture.model.cullingSessionCompletion)

        fixture.model.selectedAssetSetID = nil
        try fixture.model.reload()
        _ = try fixture.model.beginCullingSession(named: "Fresh Cull")

        XCTAssertNil(fixture.model.cullingSessionCompletion)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AppModelTests.testFlaggingLastStackFramePublishesCullingCompletionSummary|AppModelTests.testOpeningCullingCompletionPicksAppliesTheOutputSet|AppModelTests.testClearingAFlagWithdrawsTheCompletionSummary|AppModelTests.testStartingANewCullingSessionClearsTheCompletionSummary"`
Expected: compile FAILURE — `value of type 'AppModel' has no member 'cullingSessionCompletion'`

- [ ] **Step 3: Write the model implementation**

In `Sources/TeststripApp/AppModel.swift`, add the summary type near `CullingProgressSummary` (top of file, ~line 47):

```swift
public struct CullingSessionCompletionSummary: Equatable, Identifiable, Sendable {
    public var sessionID: WorkSessionID
    public var title: String
    public var pickCount: Int
    public var rejectCount: Int
    public var picksSetID: AssetSetID?

    public var id: String { sessionID.rawValue }

    public var detailText: String {
        let picksText = "\(pickCount) \(pickCount == 1 ? "pick" : "picks")"
        let rejectsText = "\(rejectCount) \(rejectCount == 1 ? "reject" : "rejects")"
        return "\(picksText) · \(rejectsText) — \(title)"
    }
}
```

Add the published state near `lastCullingMetadataDecision` (:1159):

```swift
    public private(set) var cullingSessionCompletion: CullingSessionCompletionSummary?
```

Add the transition helper near `refreshCullingSessionOutputSet` (~7496):

```swift
    // Publishes the payoff banner exactly when a session transitions into
    // .completed, and withdraws it if a later change reopens the session.
    private func updateCullingSessionCompletion(
        session: WorkSession,
        previousStatus: WorkSessionStatus,
        decisionCounts: (pick: Int, reject: Int)
    ) {
        if session.status == .completed, previousStatus != .completed {
            let picksSetID = Self.cullingOutputSetID(sessionID: session.id)
            cullingSessionCompletion = CullingSessionCompletionSummary(
                sessionID: session.id,
                title: session.title,
                pickCount: decisionCounts.pick,
                rejectCount: decisionCounts.reject,
                picksSetID: session.outputSetIDs.contains(picksSetID) ? picksSetID : nil
            )
            return
        }
        if session.status != .completed, cullingSessionCompletion?.sessionID == session.id {
            cullingSessionCompletion = nil
        }
    }
```

Wire it into BOTH progress functions. In `updateActiveCullingSessionProgressAfterFlagChange` (~7413): capture `let previousStatus = session.status` right after the `guard ... var session` line, then insert after the existing `try refreshCullingSessionOutputSet(session: &session, repository: catalog.repository)` line:

```swift
        updateCullingSessionCompletion(
            session: session,
            previousStatus: previousStatus,
            decisionCounts: decisionCounts
        )
```

Apply the identical two edits to `updatePersistedStackCullingSessionProgress` (~7452).

Add the public actions near `beginCullingSession` (~3465):

```swift
    public func openCullingSessionPicks() throws {
        guard let completion = cullingSessionCompletion else {
            throw TeststripError.invalidState("no completed culling session")
        }
        guard let picksSetID = completion.picksSetID else {
            throw TeststripError.invalidState("the completed session has no picks")
        }
        try applyAssetSet(id: picksSetID)
        cullingSessionCompletion = nil
        statusMessage = "Viewing \(completion.title) Picks"
    }

    public func dismissCullingSessionCompletion() {
        cullingSessionCompletion = nil
    }
```

Clear stale banners at session start: add `cullingSessionCompletion = nil` as the first statement of `beginCullingSession(named:intent:)`, `beginStackCullingFromLatestImportCompletion()`, and `beginManualCullingFromCompareSet()`.

- [ ] **Step 4: Run the model tests**

Run: `swift test --filter "AppModelTests.testFlaggingLastStackFramePublishesCullingCompletionSummary|AppModelTests.testOpeningCullingCompletionPicksAppliesTheOutputSet|AppModelTests.testClearingAFlagWithdrawsTheCompletionSummary|AppModelTests.testStartingANewCullingSessionClearsTheCompletionSummary"`
Expected: PASS

- [ ] **Step 5: Render the banner in loupe and compare**

In `Sources/TeststripApp/LibraryGridView.swift`, add a fileprivate banner view (place it near `LoupeView`, ~2660):

```swift
private struct CullingCompletionBannerView: View {
    var summary: CullingSessionCompletionSummary
    var canViewPicks: Bool
    var viewPicks: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Culling complete")
                    .font(.caption.weight(.semibold))
                Text(summary.detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("View Picks") {
                viewPicks()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)
            .disabled(!canViewPicks)
            .help(canViewPicks ? "Open this session's Picks output set" : "This session finished with no picks")
            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color.green.opacity(0.12))
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Culling session complete")
    }
}
```

In `LoupeView.body` (~2668), insert between `loupeStage`/`unavailableView` and `cullingStackRail(presentation: stackPresentation)`:

```swift
            if let completion = model.cullingSessionCompletion {
                CullingCompletionBannerView(
                    summary: completion,
                    canViewPicks: completion.picksSetID != nil,
                    viewPicks: { openCullingSessionPicks() },
                    dismiss: { model.dismissCullingSessionCompletion() }
                )
            }
```

Add the action helper to `LoupeView`:

```swift
    private func openCullingSessionPicks() {
        do {
            try model.openCullingSessionPicks()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
```

In `CompareView.body` (~4196), insert the identical `if let completion ...` block (and the same private helper) directly after `compareHeader(presentation)`.

- [ ] **Step 6: Run the full app test suite**

Run: `swift test --filter TeststripAppTests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: hand off completed culling sessions to their picks set"
```

---

### Task 6: Render the recommendation on stack chips and the filmstrip (arc-blocker #5)

`CullingStackRailPresentation.Item.isRecommended` is computed today and rendered nowhere. This task marks the recommended frame with `✦` on the stack rail chips (mockup 3a) and on the loupe filmstrip tile (2a). The survey-grid marker (2b) is deliberately NOT done here — the culling-signals plan Task 8 ships the `✦ BEST` badge on compare tiles; duplicating it would put two winner markers on the same tile.

**Estimated scope:** ~90 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`CullingStackRailPresentation` at ~3914, chip rendering at ~2899-2917, `cullingFilmstrip` at ~2824, `filmstripTile` at ~2948, `LoupeView.body` at ~2668)
- Test: `Tests/TeststripAppTests/CullingStackRailPresentationTests.swift`

**Interfaces:**
- Consumes: `CullingStackRailPresentation.Item.isRecommended` (LibraryGridView.swift:3919).
- Produces: `CullingStackRailPresentation.recommendedAssetID: AssetID?` (computed; Task 7's rail and the filmstrip consume it).

- [ ] **Step 1: Write the failing test**

Add to `Tests/TeststripAppTests/CullingStackRailPresentationTests.swift` (uses the file's existing `makeAsset(id:path:capturedAt:)` and `signal(assetID:kind:score:)` helpers):

```swift
    func testRecommendedAssetIDSurfacesTheRankedWinner() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let assets = [
            makeAsset(id: "lead", path: "/Photos/Job/lead.cr2", capturedAt: capturedAt),
            makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: capturedAt.addingTimeInterval(1)),
            makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1.8))
        ]
        let alternateID = AssetID(rawValue: "alternate")

        let ranked = CullingStackRailPresentation(
            assets: assets,
            selectedAssetID: AssetID(rawValue: "selected"),
            evaluationSignalsByAssetID: [
                alternateID: [signal(assetID: alternateID, kind: .focus, score: 0.94)]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )
        let unranked = CullingStackRailPresentation(
            assets: assets,
            selectedAssetID: AssetID(rawValue: "selected"),
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertEqual(ranked.recommendedAssetID, alternateID)
        XCTAssertNil(unranked.recommendedAssetID)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CullingStackRailPresentationTests.testRecommendedAssetIDSurfacesTheRankedWinner`
Expected: compile FAILURE — `value of type 'CullingStackRailPresentation' has no member 'recommendedAssetID'`

- [ ] **Step 3: Write the implementation**

In `Sources/TeststripApp/LibraryGridView.swift`, add to `CullingStackRailPresentation` (next to `var isVisible`, ~4032):

```swift
    var recommendedAssetID: AssetID? {
        items.first { $0.isRecommended }?.assetID
    }
```

Chip marker — in the chip `ForEach` (~2900), replace the button label `Text(item.label)` block with:

```swift
                            HStack(spacing: 2) {
                                if item.isRecommended {
                                    Text("✦")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text(item.label)
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                            }
                            .frame(width: item.isRecommended ? 32 : 24, height: 22)
                            .foregroundStyle(item.isSelected ? Color.black : Color.orange)
                            .background(item.isSelected ? Color.orange : Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.orange.opacity(item.isSelected ? 0.4 : 0.26))
                            }
```

and extend the chip accessibility line to:

```swift
                        .accessibilityValue(item.isSelected ? "Selected" : (item.isRecommended ? "Recommended" : "Not selected"))
```

Filmstrip marker — change `cullingFilmstrip` from a computed var to a function and thread the recommendation through:

1. In `LoupeView.body`, change the call `cullingFilmstrip` to `cullingFilmstrip(recommendedAssetID: stackPresentation.recommendedAssetID)`.
2. Change the declaration `private var cullingFilmstrip: some View {` to `private func cullingFilmstrip(recommendedAssetID: AssetID?) -> some View {`.
3. Change the tile call inside it to `filmstripTile(for: asset, isSelected: asset.id == model.selectedAssetID, isRecommended: asset.id == recommendedAssetID)`.
4. Change `filmstripTile` (~2948) to `private func filmstripTile(for asset: Asset, isSelected: Bool, isRecommended: Bool) -> some View` and add inside the tile's `ZStack`, after `filmstripDecisionOverlay(for: asset).padding(4)`:

```swift
                if isRecommended {
                    Text("✦")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(3)
                        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(3)
                }
```

and extend its accessibility value:

```swift
        .accessibilityValue(isSelected ? "Selected" : (isRecommended ? "Recommended" : "Not selected"))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CullingStackRailPresentationTests`
Expected: PASS (all existing + 1 new)

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/CullingStackRailPresentationTests.swift
git commit -m "feat: mark the recommended frame on stack chips and filmstrip"
```

---

### Task 7: Stack list rail with decided-state (arc-blocker #8)

Persisted stack-cull sessions get a visible left rail in the loupe: one row per stack (`Stack N`, frame count, lead thumbnail, done checkmark, active highlight) with click-to-jump. This replaces blind ↑/↓ navigation with the mockup 3a "STACKS · AUTO-GROUPED" model.

**Estimated scope:** ~290 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (near `selectedCullingStackScope` at ~3949 and `persistedCullingStackSetID` at ~7337)
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`LoupeView.body` at ~2668)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `activePersistedStackCullingSession(repository:)` (:7369 — requires `selectedAssetSetID` to be a work-stack set), `Self.isWorkStackSetID` (:7333), `assetIDs(in:repository:)` (:7573), `recommendedCullingStackAssetID(in:)` (Task 3), `selectPersistedCullingStack` final body (Task 4), `model.gridPreviewURL(for:)` / `model.previewCacheGeneration(for:)` (existing view helpers).
- Produces:
  - `public struct CullingStackListEntry: Equatable, Identifiable, Sendable { setID, title, frameCountText, leadAssetID, isDecided, isSelected }` with `id: String`
  - `public func cullingStackListEntries() -> [CullingStackListEntry]`
  - `public func selectCullingStackSet(id: AssetSetID) throws`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/AppModelTests.swift`:

```swift
    func testCullingStackListEntriesDescribeSessionStacksWithDecidedState() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "stack-list-entries",
            sessionID: "stack-list-entries-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)

        let initialEntries = fixture.model.cullingStackListEntries()
        XCTAssertEqual(initialEntries.map(\.setID), [fixture.firstSet.id, fixture.secondSet.id])
        XCTAssertEqual(initialEntries.map(\.title), ["Stack 1", "Stack 2"])
        XCTAssertEqual(initialEntries.map(\.frameCountText), ["2 frames", "2 frames"])
        XCTAssertEqual(initialEntries.map(\.leadAssetID), [fixture.firstLead.id, fixture.secondLead.id])
        XCTAssertEqual(initialEntries.map(\.isDecided), [false, false])
        XCTAssertEqual(initialEntries.map(\.isSelected), [true, false])

        try fixture.model.applyCullingShortcut(.acceptStackSelection)

        let advancedEntries = fixture.model.cullingStackListEntries()
        XCTAssertEqual(advancedEntries.map(\.isDecided), [true, false])
        XCTAssertEqual(advancedEntries.map(\.isSelected), [false, true])
    }

    func testCullingStackListEntriesAreEmptyOutsidePersistedStackSessions() throws {
        let first = makeAsset(id: "stack-list-none-first", path: "/Photos/Job/a.cr2", rating: 0)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "stack-list-entries-none",
            assets: [first]
        )
        model.select(first.id)

        XCTAssertEqual(model.cullingStackListEntries(), [])
    }

    func testSelectingAStackSetFromTheListJumpsToItsRecommendedFrame() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "stack-list-jump",
            sessionID: "stack-list-jump-session"
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "1", settingsHash: "default")
        try fixture.repository.recordEvaluationSignals([
            EvaluationSignal(assetID: fixture.secondAlternate.id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance)
        ])
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)

        try fixture.model.selectCullingStackSet(id: fixture.secondSet.id)

        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedAssetID, fixture.secondAlternate.id)
        XCTAssertEqual(fixture.model.selectedView, .loupe)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AppModelTests.testCullingStackListEntriesDescribeSessionStacksWithDecidedState|AppModelTests.testCullingStackListEntriesAreEmptyOutsidePersistedStackSessions|AppModelTests.testSelectingAStackSetFromTheListJumpsToItsRecommendedFrame"`
Expected: compile FAILURE — `value of type 'AppModel' has no member 'cullingStackListEntries'`

- [ ] **Step 3: Write the model implementation**

In `Sources/TeststripApp/AppModel.swift`, add the entry type near `CullingStackScope` (~66):

```swift
public struct CullingStackListEntry: Equatable, Identifiable, Sendable {
    public var setID: AssetSetID
    public var title: String
    public var frameCountText: String
    public var leadAssetID: AssetID
    public var isDecided: Bool
    public var isSelected: Bool

    public var id: String { setID.rawValue }
}
```

Add the accessors near `selectedCullingStackScope` (~3949):

```swift
    // One row per persisted stack in the active stack-cull session; empty
    // outside persisted stack sessions. A stack is decided only when every
    // frame carries a flag — matching session progress accounting.
    public func cullingStackListEntries() -> [CullingStackListEntry] {
        guard let catalog,
              let session = try? activePersistedStackCullingSession(repository: catalog.repository) else {
            return []
        }
        let stackSetIDs = session.inputSetIDs.filter(Self.isWorkStackSetID)
        return stackSetIDs.enumerated().compactMap { index, setID in
            guard let stackAssetIDs = try? assetIDs(in: setID, repository: catalog.repository),
                  let leadAssetID = stackAssetIDs.first else {
                return nil
            }
            let isDecided = (try? stackAssetIDs.allSatisfy { assetID in
                try catalog.repository.asset(id: assetID).metadata.flag != nil
            }) ?? false
            return CullingStackListEntry(
                setID: setID,
                title: "Stack \(index + 1)",
                frameCountText: "\(stackAssetIDs.count) \(stackAssetIDs.count == 1 ? "frame" : "frames")",
                leadAssetID: leadAssetID,
                isDecided: isDecided,
                isSelected: setID == selectedAssetSetID
            )
        }
    }

    public func selectCullingStackSet(id: AssetSetID) throws {
        guard let catalog,
              let session = try activePersistedStackCullingSession(repository: catalog.repository),
              session.inputSetIDs.contains(id) else {
            throw TeststripError.invalidState("stack set is not part of the active culling session")
        }
        let keepSurveyCompare = selectedView == .compare
        try applyAssetSet(id: id)
        let stackAssetIDs = selectedExplicitAssetIDs ?? []
        selectAssetID(recommendedCullingStackAssetID(in: stackAssetIDs) ?? stackAssetIDs.first)
        selectedView = keepSurveyCompare ? .compare : .loupe
    }
```

- [ ] **Step 4: Run the model tests**

Run: `swift test --filter "AppModelTests.testCullingStackListEntriesDescribeSessionStacksWithDecidedState|AppModelTests.testCullingStackListEntriesAreEmptyOutsidePersistedStackSessions|AppModelTests.testSelectingAStackSetFromTheListJumpsToItsRecommendedFrame"`
Expected: PASS

- [ ] **Step 5: Render the rail in LoupeView**

In `Sources/TeststripApp/LibraryGridView.swift`, restructure `LoupeView.body` so the stage column can sit beside the rail. Replace the body's `VStack` content between `cullingHeader(...)` and `cullingStackRail(...)` with:

```swift
            cullingHeader(stackPresentation: stackPresentation)
            HStack(spacing: 0) {
                cullingStackListRail
                VStack(spacing: 0) {
                    if let asset = model.selectedAsset {
                        loupeStage(for: asset)
                            .task(id: asset.id.rawValue) {
                                do {
                                    try model.requestVisibleLoupePreview(assetID: asset.id)
                                } catch {
                                    model.errorMessage = error.localizedDescription
                                }
                            }
                    } else {
                        unavailableView(title: "No photo selected", systemImage: "photo")
                    }
                }
            }
```

(The completion banner from Task 5 and `cullingStackRail`/`cullingFilmstrip`/`cullingCommandRail` stay below the `HStack`, unchanged.)

Add the rail view to `LoupeView`:

```swift
    @ViewBuilder
    private var cullingStackListRail: some View {
        let entries = model.cullingStackListEntries()
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("STACKS · AUTO-GROUPED")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(entries) { entry in
                            stackListRow(entry)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(width: 168)
            .background(Color.black.opacity(0.26))
            .overlay(alignment: .trailing) { Divider() }
        }
    }

    private func stackListRow(_ entry: CullingStackListEntry) -> some View {
        Button {
            do {
                try model.selectCullingStackSet(id: entry.setID)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.55))
                    if let previewURL = model.gridPreviewURL(for: entry.leadAssetID) {
                        CachedPreviewImage(
                            previewURL: previewURL,
                            scaling: .fit,
                            cacheGeneration: model.previewCacheGeneration(for: entry.leadAssetID)
                        )
                    } else {
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 36, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(entry.frameCountText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if entry.isDecided {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(6)
            .background(
                entry.isSelected ? Color.orange.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(entry.isSelected ? Color.orange.opacity(0.4) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.title)
        .accessibilityValue(entry.isDecided ? "Decided" : "Undecided")
    }
```

Note: `cullingStackListEntries()` queries the repository per body evaluation; it only renders for persisted stack sessions (dozens of small sets, not the whole library). If profiling later shows render-path cost, memoize behind the flag-change/session-change events — out of scope here.

- [ ] **Step 6: Run the full app suite**

Run: `swift test --filter TeststripAppTests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: add stack list rail with decided-state to stack culling"
```

---

### Task 8: Potential Picks — provisional likely-keepers review queue

A Narrative-Select-style "Potential Picks" scope that cuts review volume: unflagged frames with at least one strong quality read and no likely-issue defect. It is a query scope (new `SetQuery` predicate + `ReviewQueue` case) — it NEVER writes flags. Threshold judgment calls, surfaced for review: "strong" = focus/aesthetics/faceQuality ≥ 0.65; the defect exclusions mirror the existing `likelyIssue` thresholds (focus ≤ 0.5, motionBlur ≥ 0.5, exposure ≤ 0.12 or ≥ 0.88) plus `eyesOpen < 1.0` (raw-string SQL kind — matches nothing until the culling-signals provider ships; no compile dependency).

**Estimated scope:** ~210 LOC including tests.

**Files:**
- Modify: `Sources/TeststripCore/Search/SetQuery.swift:20` (add case)
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift:~1430` (SQL clause)
- Modify: `Sources/TeststripApp/AppModel.swift` (`ReviewQueue` at :199, presentation at :221, `potentialPicksFilter` touchpoints)
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`, `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `SetQuery.Predicate` (String-bound SQL compilation in `CatalogRepository.compile`), `ReviewQueue` plumbing (`reviewQueueSidebarOrder` :8734, `reviewQueueQuery` :8754, `applyReviewQueue` :6470, `selectSidebarTarget` :2856).
- Produces: `SetQuery.Predicate.likelyPick`; `ReviewQueue.potentialPicks` (raw `"potentialPicks"`, title `"Potential Picks"`, systemImage `"sparkles"`); `AppModel.potentialPicksFilter: Bool`.

- [ ] **Step 1: Write the failing core test**

Add to `Tests/TeststripCoreTests/CatalogDatabaseTests.swift` (uses the file's private `Asset.testAsset(id:path:rating:)` / `testAsset(id:path:metadata:)` helpers):

```swift
    func testLikelyPickMatchesStrongUnflaggedFramesWithoutDefects() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-likely-pick")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let strong = Asset.testAsset(id: AssetID(rawValue: "strong"), path: "/Volumes/NAS/Job/strong.jpg", rating: 0)
        let soft = Asset.testAsset(id: AssetID(rawValue: "soft"), path: "/Volumes/NAS/Job/soft.jpg", rating: 0)
        let strongButBlurred = Asset.testAsset(id: AssetID(rawValue: "strong-blurred"), path: "/Volumes/NAS/Job/strong-blurred.jpg", rating: 0)
        let alreadyPicked = Asset.testAsset(
            id: AssetID(rawValue: "already-picked"),
            path: "/Volumes/NAS/Job/already-picked.jpg",
            metadata: AssetMetadata(flag: .pick)
        )
        let unread = Asset.testAsset(id: AssetID(rawValue: "unread"), path: "/Volumes/NAS/Job/unread.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "1", settingsHash: "default")
        try repository.upsert([strong, soft, strongButBlurred, alreadyPicked, unread])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: strong.id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: soft.id, kind: .focus, value: .score(0.55), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: strongButBlurred.id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: strongButBlurred.id, kind: .motionBlur, value: .score(0.8), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: alreadyPicked.id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance)
        ])

        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyPick]), limit: 10).map(\.id),
            [strong.id]
        )
    }
```

If `AssetMetadata(flag:)` is not a valid initializer spelling, use `AssetMetadata(rating: 0, colorLabel: nil, flag: .pick, keywords: [])` (the labeled form used by `AppModelTests.makeAsset`).

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CatalogDatabaseTests.testLikelyPickMatchesStrongUnflaggedFramesWithoutDefects`
Expected: compile FAILURE — `type 'SetQuery.Predicate' has no member 'likelyPick'`

- [ ] **Step 3: Add the predicate and its SQL**

`Sources/TeststripCore/Search/SetQuery.swift` — add after `case likelyIssue`:

```swift
        case likelyPick
```

`Sources/TeststripCore/Catalog/CatalogRepository.swift` — in `compile(_:)`, add after the `case .likelyIssue:` clause:

```swift
            case .likelyPick:
                clauses.append(
                    """
                    json_extract(metadata_json, '$.flag') IS NULL
                    AND EXISTS (
                        SELECT 1
                        FROM evaluation_signals
                        WHERE evaluation_signals.asset_id = assets.id
                          AND (
                            (kind = 'focus' AND CAST(json_extract(value_json, '$.score._0') AS REAL) >= 0.65)
                            OR (kind = 'aesthetics' AND CAST(json_extract(value_json, '$.score._0') AS REAL) >= 0.65)
                            OR (kind = 'faceQuality' AND CAST(json_extract(value_json, '$.score._0') AS REAL) >= 0.65)
                          )
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM evaluation_signals
                        WHERE evaluation_signals.asset_id = assets.id
                          AND (
                            (kind = 'focus' AND CAST(json_extract(value_json, '$.score._0') AS REAL) <= 0.5)
                            OR (kind = 'motionBlur' AND CAST(json_extract(value_json, '$.score._0') AS REAL) >= 0.5)
                            OR (
                                kind = 'exposure'
                                AND (
                                    CAST(json_extract(value_json, '$.score._0') AS REAL) <= 0.12
                                    OR CAST(json_extract(value_json, '$.score._0') AS REAL) >= 0.88
                                )
                            )
                            OR (kind = 'eyesOpen' AND CAST(json_extract(value_json, '$.score._0') AS REAL) < 1.0)
                          )
                    )
                    """
                )
```

Run: `swift test --filter CatalogDatabaseTests.testLikelyPickMatchesStrongUnflaggedFramesWithoutDefects`
Expected: PASS

- [ ] **Step 4: Write the failing app test**

Add to `Tests/TeststripAppTests/AppModelTests.swift`:

```swift
    func testPotentialPicksReviewQueueFiltersToLikelyKeepersWithoutWritingFlags() throws {
        let strong = makeAsset(id: "potential-strong", path: "/Photos/Job/strong.cr2", rating: 0)
        let weak = makeAsset(id: "potential-weak", path: "/Photos/Job/weak.cr2", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "potential-picks-queue",
            assets: [strong, weak]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: strong.id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: weak.id, kind: .focus, value: .score(0.3), confidence: 0.9, provenance: provenance)
        ])

        try model.selectSidebarTarget(.reviewQueue(.potentialPicks))

        XCTAssertEqual(model.assets.map(\.id), [strong.id])
        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertTrue(model.potentialPicksFilter)
        XCTAssertNil(try repository.asset(id: strong.id).metadata.flag)
        XCTAssertEqual(model.suggestedSavedSearchName, "Potential Picks")
    }
```

Run: `swift test --filter AppModelTests.testPotentialPicksReviewQueueFiltersToLikelyKeepersWithoutWritingFlags`
Expected: compile FAILURE — `type 'ReviewQueue' has no member 'potentialPicks'`

- [ ] **Step 5: Wire the queue and the filter flag**

In `Sources/TeststripApp/AppModel.swift`:

1. `ReviewQueue` (:199) — add `case potentialPicks` after `case picks`.
2. `ReviewQueue.presentation` (:221) — add:

```swift
        case .potentialPicks:
            return ReviewQueuePresentation(title: "Potential Picks", systemImage: "sparkles")
```

3. `reviewQueueSidebarOrder` (:8734) — insert `.potentialPicks` immediately after `.picks`.
4. `reviewQueueQuery` (:8754) — add:

```swift
        case .potentialPicks:
            return SetQuery(predicates: [.likelyPick])
```

5. Declare the filter next to `likelyIssuesFilter` (:1182): `public var potentialPicksFilter: Bool` and initialize it to `false` where `likelyIssuesFilter` is initialized (~:2364).
6. Mirror every `likelyIssuesFilter` touchpoint with a `potentialPicksFilter` line (same shape, adjacent placement):
   - saved-search name parts (~:2143): `if potentialPicksFilter { Self.append("Potential Picks", to: &parts) }`
   - active filter rows (~:1867): `Self.append(ActiveLibraryFilterRow(title: "Potential Picks", target: .reviewQueue(.potentialPicks)), to: &rows)` guarded by the flag
   - active-filter removal switch (~:6980, next to `case .reviewQueue(.likelyIssues):`):

```swift
        case .reviewQueue(.potentialPicks):
            if potentialPicksFilter {
                potentialPicksFilter = false
                removed = true
            }
```
   - `currentLibraryQuery()` predicates (~:7159): `if potentialPicksFilter { Self.append(.likelyPick, to: &predicates) }`
   - `clearLibraryQueryFilters()` (~:7190): `potentialPicksFilter = false`
   - `applyReviewQueue` (:6470): `case .potentialPicks: potentialPicksFilter = true`

- [ ] **Step 6: Run tests to verify green**

Run: `swift test --filter "CatalogDatabaseTests.testLikelyPickMatchesStrongUnflaggedFramesWithoutDefects|AppModelTests.testPotentialPicksReviewQueueFiltersToLikelyKeepersWithoutWritingFlags"`
Expected: PASS

Then: `swift test`
Expected: PASS (if an existing test asserts the review-queue sidebar order or a full filter list, extend its expectation with Potential Picks in the positions specified above — that is the only permitted change).

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripCore/Search/SetQuery.swift Sources/TeststripCore/Catalog/CatalogRepository.swift Sources/TeststripApp/AppModel.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: add potential picks review queue over quality signals"
```

---

### Task 9: Visible verdict strip with a synthesized read (arc-blocker #6)

> **BLOCKED until culling-signals plan Tasks 2, 6, and 7 have landed on main.** Task 2 adds `EvaluationKind.eyesOpen`/`.eyeSharpness`/`.smile` (this task's switch is exhaustive over them); Tasks 6–7 rework `CullingAssistPresentation` internals and `CullingStackRecommendation.weightedQualityScore` (this task refactors that exact function and must include their eye-weight arms). Verify with `git log --oneline` (look for "add smile and eye culling signal kinds", "read eye and smile signals in culling verdict pill", "explain stack keep recommendations with eye and sharpness rationale") and rebase before starting.

The 148pt hover-only pill becomes a strip: a synthesized display-only read ("Keep read 78%" / "Toss read 16%" / "Mixed read 60%") plus the existing rationale detail rendered inline. The read is a confidence-weighted mean of the same per-kind quality components the stack ranking uses (motionBlur inverted), so pill and ranking can never disagree. It requires at least two scored quality kinds — one signal is not a verdict. NOTHING is written; the commit gesture remains Enter/P/X.

**Estimated scope:** ~230 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`CullingStackRecommendation` at ~4125, `CullingAssistPresentation` at ~6383, `cullingAssistPill` at ~2752)
- Modify: `Sources/TeststripApp/LiveMockupPlaceholder.swift` (`cullingAssistVerdict.currentFallback` copy)
- Test: `Tests/TeststripAppTests/CullingAssistPresentationTests.swift`

**Interfaces:**
- Consumes: `CullingAssistPresentation.title/detail/tone` and `presentation(for:stackGuidance:)` (existing, including culling-signals Task 6 phrase changes), `CullingStackRecommendation.weightedQualityScore` including the eye arms from culling-signals Task 7 (`.eyesOpen` weight 90, `.eyeSharpness` weight 70, smile unranked), `EvaluationSignalPresentation.percentage(_:)`.
- Produces:
  - `CullingStackRecommendation.qualityComponent(for signal: EvaluationSignal) -> (score: Double, weight: Double)?` (defect-inverted score, confidence-scaled weight; `weightedQualityScore` becomes `component.score * component.weight`, behavior-identical)
  - `CullingStackRecommendation.normalizedQualityRead(for signals: [EvaluationSignal]) -> (score: Double, kindCount: Int)?`
  - `CullingAssistPresentation.verdictText: String?` and `verdictTone: Tone` (thresholds: ≥ 0.7 "Keep read", ≤ 0.45 "Toss read", else "Mixed read"; nil below two scored kinds)

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/CullingAssistPresentationTests.swift` (uses the file's private `signal(kind:value:confidence:)` helper; the fixtures below use confidence 1.0 for exact arithmetic — focus weight 100, motionBlur 60 inverted, aesthetics 50):

```swift
    func testVerdictSynthesizesKeepReadFromStrongQualityKinds() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.96), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.9), confidence: 1.0)
        ])

        // (0.96 * 100 + 0.9 * 50) / 150 = 0.94
        XCTAssertEqual(presentation.verdictText, "Keep read 94%")
        XCTAssertEqual(presentation.verdictTone, .positive)
    }

    func testVerdictSynthesizesTossReadFromDefects() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.2), confidence: 1.0),
            signal(kind: .motionBlur, value: .score(0.9), confidence: 1.0)
        ])

        // (0.2 * 100 + (1 - 0.9) * 60) / 160 = 0.16
        XCTAssertEqual(presentation.verdictText, "Toss read 16%")
        XCTAssertEqual(presentation.verdictTone, .caution)
    }

    func testVerdictReportsMixedReadBetweenThresholds() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.6), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.6), confidence: 1.0)
        ])

        XCTAssertEqual(presentation.verdictText, "Mixed read 60%")
        XCTAssertEqual(presentation.verdictTone, .neutral)
    }

    func testVerdictRequiresAtLeastTwoScoredQualityKinds() {
        let single = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.96), confidence: 1.0)
        ])
        let none = CullingAssistPresentation.presentation(for: [])

        XCTAssertNil(single.verdictText)
        XCTAssertEqual(single.verdictTone, .waiting)
        XCTAssertNil(none.verdictText)
        XCTAssertEqual(none.verdictTone, .waiting)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CullingAssistPresentationTests`
Expected: compile FAILURE — `value of type 'CullingAssistPresentation' has no member 'verdictText'`

- [ ] **Step 3: Refactor the ranking components and add the read**

In `Sources/TeststripApp/LibraryGridView.swift`, inside `CullingStackRecommendation`, replace `weightedQualityScore(for:)` (which by now includes the culling-signals eye arms) with the component form — the switch below must carry ALL arms present at rebase time:

```swift
    // Defect-inverted score plus confidence-scaled weight for one signal.
    // weightedQualityScore and normalizedQualityRead both derive from this,
    // so the pill's read and the stack ranking can never disagree.
    static func qualityComponent(for signal: EvaluationSignal) -> (score: Double, weight: Double)? {
        guard case .score(let rawScore) = signal.value else { return nil }
        let clampedScore = min(max(rawScore, 0), 1)
        let confidence = min(max(signal.confidence, 0), 1)
        switch signal.kind {
        case .focus:
            return (clampedScore, confidence * 100)
        case .eyesOpen:
            return (clampedScore, confidence * 90)
        case .faceQuality:
            return (clampedScore, confidence * 80)
        case .eyeSharpness:
            return (clampedScore, confidence * 70)
        case .motionBlur:
            return (1 - clampedScore, confidence * 60)
        case .aesthetics:
            return (clampedScore, confidence * 50)
        case .framing:
            return (clampedScore, confidence * 45)
        default:
            return nil
        }
    }

    private static func weightedQualityScore(for signal: EvaluationSignal) -> Double? {
        guard let component = qualityComponent(for: signal) else { return nil }
        return component.score * component.weight
    }

    // Confidence-weighted mean of the best component per kind, 0...1.
    static func normalizedQualityRead(for signals: [EvaluationSignal]) -> (score: Double, kindCount: Int)? {
        var bestComponentByKind: [EvaluationKind: (score: Double, weight: Double)] = [:]
        for signal in signals {
            guard let component = qualityComponent(for: signal) else { continue }
            if let existing = bestComponentByKind[signal.kind],
               existing.score * existing.weight >= component.score * component.weight {
                continue
            }
            bestComponentByKind[signal.kind] = component
        }
        let totalWeight = bestComponentByKind.values.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let weightedScore = bestComponentByKind.values.reduce(0) { $0 + $1.score * $1.weight } / totalWeight
        return (weightedScore, bestComponentByKind.count)
    }
```

(If the pre-refactor `weightedQualityScore` at rebase time has arms not listed above, carry them into `qualityComponent` with the same weight and inversion — never drop an arm.)

In `CullingAssistPresentation`: add the stored members and compute them in `presentation(for:stackGuidance:)`. Add after `var tone: Tone`:

```swift
    var verdictText: String?
    var verdictTone: Tone
```

Add the synthesis helper:

```swift
    private static let keepReadThreshold = 0.7
    private static let tossReadThreshold = 0.45

    private static func verdict(for signals: [EvaluationSignal]) -> (text: String, tone: Tone)? {
        guard let read = CullingStackRecommendation.normalizedQualityRead(for: signals),
              read.kindCount >= 2 else {
            return nil
        }
        let percentText = EvaluationSignalPresentation.percentage(read.score)
        if read.score >= keepReadThreshold {
            return ("Keep read \(percentText)", .positive)
        }
        if read.score <= tossReadThreshold {
            return ("Toss read \(percentText)", .caution)
        }
        return ("Mixed read \(percentText)", .neutral)
    }
```

Update `presentation(for:stackGuidance:)`: compute `let verdict = verdict(for: signals)` first, then pass `verdictText: verdict?.text` and `verdictTone: verdict?.tone ?? .waiting` into every `CullingAssistPresentation(...)` construction in the function (all three paths: stack-guidance, no-signal, and primary-signal). The stack-guidance path keeps its stack title/detail but carries the selected frame's verdict members.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "CullingAssistPresentationTests|CullingStackRailPresentationTests|CompareSurveyPresentationTests"`
Expected: PASS — existing tests assert `title`/`detail`/`tone` individually, so the new members are additive; ranking behavior is unchanged by the component refactor.

- [ ] **Step 5: Widen the pill into a strip**

In `LoupeView.cullingAssistPill` (~2752), replace the label column and frame:

```swift
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("TESTSTRIP READS")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                    if let verdictText = presentation.verdictText {
                        Text(verdictText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(cullingAssistColor(for: presentation.verdictTone))
                            .lineLimit(1)
                    }
                }
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(presentation.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
```

and change `.frame(width: 148, height: 34, alignment: .leading)` to `.frame(minWidth: 148, maxWidth: 460, alignment: .leading)` (keep the `.help(presentation.detail)` tooltip for the untruncated text).

In `Sources/TeststripApp/LiveMockupPlaceholder.swift`, update `cullingAssistVerdict.currentFallback` (rebase first — culling-signals Task 6 rewrites it) to:

```swift
        currentFallback: "Selected-frame verdict synthesizes a provisional keep/toss read from persisted quality signals with inline rationale — including eye-state, eye-sharpness, and smile reads when present — and stack-level keep recommendations surface when persisted quality signals rank the active stack. Reads are display-only; Enter, P, or X commits."
```

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift Sources/TeststripApp/LiveMockupPlaceholder.swift Tests/TeststripAppTests/CullingAssistPresentationTests.swift
git commit -m "feat: synthesize a visible provisional keep/toss read in the culling strip"
```

---

### Task 10: Close-Ups panel — face crops beside the loupe

> **BLOCKED until culling-signals plan Task 5 has landed on main** (commit "run face expression pass in worker evaluation flow"), which ships `CoreImageFaceExpressionAnalyzer` and `DetectedFaceExpression` in TeststripCore. Verify and rebase before starting.

**Sequencing decision (from code evidence):** no per-face geometry persists anywhere today — `AppleVisionEvaluationProvider` records only photo-level `faceCount`/`faceQuality` (AppleVisionEvaluationProvider.swift:15-16, 54-58), and the culling-signals plan explicitly persists photo-level signals only ("no per-face persisted rows"). The face-recognition plan's face-observations tables are not on main. So the honest Close-Ups design available NOW is: run the culling-signals plan's `CoreImageFaceExpressionAnalyzer` on demand over the selected frame's cached preview, crop in memory, display, persist nothing. If detection finds no faces the panel is hidden (no fake content).

**Spacebar zoom-to-face is DEFERRED:** Space is already bound to next-photo advance (`CullingShortcut.init?`, AppModel.swift:94 — `case " ": self = .nextPhoto`), matching mockup 2a's "Space advances". Rebinding is a product decision for Jesse, not a plan default.

**Estimated scope:** ~270 LOC including tests.

**Files:**
- Create: `Sources/TeststripApp/CloseUpFacesPresentation.swift`
- Create: `Tests/TeststripAppTests/CloseUpFacesPresentationTests.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`LoupeView.loupeStage` at ~2805 and the stage column from Task 7)

**Interfaces:**
- Consumes: `DetectedFaceExpression.normalizedBounds: CGRect` (normalized 0–1, top-left origin) and `CoreImageFaceExpressionAnalyzer().detectFaces(previewURL:) throws -> [DetectedFaceExpression]` (culling-signals Task 3/5 Interfaces), `model.loupePreviewURL(for:)` (AppModel.swift:8537).
- Produces: `CloseUpFacesPresentation(faces:imagePixelSize:)` with `crops: [Crop]` where `Crop { id: Int, pixelRect: CGRect }`, ordered largest face first, capped at 4, padded 1.6× and clamped to the image, crops under 24 px skipped.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TeststripAppTests/CloseUpFacesPresentationTests.swift`:

```swift
import CoreGraphics
import Foundation
import TeststripCore
import XCTest
@testable import TeststripApp

final class CloseUpFacesPresentationTests: XCTestCase {
    func testCropsPadAndCenterOnTheFace() {
        let face = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: nil,
            rightEyeCenter: nil
        )

        let presentation = CloseUpFacesPresentation(faces: [face], imagePixelSize: CGSize(width: 1000, height: 1000))

        XCTAssertEqual(presentation.crops.count, 1)
        // Face is 200x200 px centered at (500, 500); padded side = 200 * 1.6 = 320.
        XCTAssertEqual(presentation.crops[0].pixelRect, CGRect(x: 340, y: 340, width: 320, height: 320))
    }

    func testCropsClampToImageBounds() {
        let cornerFace = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: nil,
            rightEyeCenter: nil
        )

        let presentation = CloseUpFacesPresentation(faces: [cornerFace], imagePixelSize: CGSize(width: 1000, height: 1000))

        let rect = presentation.crops[0].pixelRect
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, 1000)
        XCTAssertLessThanOrEqual(rect.maxY, 1000)
    }

    func testCropsOrderLargestFaceFirstAndCapAtFour() {
        func face(x: Double, size: Double) -> DetectedFaceExpression {
            DetectedFaceExpression(
                normalizedBounds: CGRect(x: x, y: 0.1, width: size, height: size),
                hasSmile: false,
                leftEyeClosed: false,
                rightEyeClosed: false,
                leftEyeCenter: nil,
                rightEyeCenter: nil
            )
        }
        let faces = [
            face(x: 0.05, size: 0.10),
            face(x: 0.25, size: 0.30),
            face(x: 0.60, size: 0.20),
            face(x: 0.85, size: 0.12),
            face(x: 0.45, size: 0.15)
        ]

        let presentation = CloseUpFacesPresentation(faces: faces, imagePixelSize: CGSize(width: 2000, height: 1000))

        XCTAssertEqual(presentation.crops.count, 4)
        let sides = presentation.crops.map(\.pixelRect.width)
        XCTAssertEqual(sides, sides.sorted(by: >))
    }

    func testTinyFacesAreSkipped() {
        let tinyFace = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.5, y: 0.5, width: 0.01, height: 0.01),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: nil,
            rightEyeCenter: nil
        )

        let presentation = CloseUpFacesPresentation(faces: [tinyFace], imagePixelSize: CGSize(width: 1000, height: 1000))

        XCTAssertTrue(presentation.crops.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CloseUpFacesPresentationTests`
Expected: compile FAILURE — `cannot find 'CloseUpFacesPresentation' in scope`

- [ ] **Step 3: Write the presentation implementation**

Create `Sources/TeststripApp/CloseUpFacesPresentation.swift`:

```swift
import CoreGraphics
import Foundation
import TeststripCore

/// Display-only close-up crop geometry for the loupe's face panel. Crops come
/// from on-demand face detection over the cached preview; nothing persists.
struct CloseUpFacesPresentation: Equatable {
    struct Crop: Equatable, Identifiable {
        var id: Int
        var pixelRect: CGRect
    }

    static let maximumCropCount = 4
    private static let cropPaddingFactor = 1.6
    private static let minimumCropSidePixels = 24.0

    var crops: [Crop]

    init(faces: [DetectedFaceExpression], imagePixelSize: CGSize) {
        let imageBounds = CGRect(origin: .zero, size: imagePixelSize)
        let orderedFaces = faces.sorted { lhs, rhs in
            lhs.normalizedBounds.width * lhs.normalizedBounds.height
                > rhs.normalizedBounds.width * rhs.normalizedBounds.height
        }
        var crops: [Crop] = []
        for face in orderedFaces {
            guard crops.count < Self.maximumCropCount else { break }
            let facePixelWidth = face.normalizedBounds.width * imagePixelSize.width
            let facePixelHeight = face.normalizedBounds.height * imagePixelSize.height
            let side = max(facePixelWidth, facePixelHeight) * Self.cropPaddingFactor
            guard side >= Self.minimumCropSidePixels else { continue }
            let center = CGPoint(
                x: face.normalizedBounds.midX * imagePixelSize.width,
                y: face.normalizedBounds.midY * imagePixelSize.height
            )
            var rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            if rect.minX < 0 { rect.origin.x = 0 }
            if rect.minY < 0 { rect.origin.y = 0 }
            if rect.maxX > imageBounds.maxX { rect.origin.x = imageBounds.maxX - rect.width }
            if rect.maxY > imageBounds.maxY { rect.origin.y = imageBounds.maxY - rect.height }
            rect = rect.intersection(imageBounds)
            guard rect.width >= Self.minimumCropSidePixels, rect.height >= Self.minimumCropSidePixels else { continue }
            crops.append(Crop(id: crops.count, pixelRect: rect))
        }
        self.crops = crops
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CloseUpFacesPresentationTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Wire the panel into LoupeView**

In `Sources/TeststripApp/LibraryGridView.swift`, add state to `LoupeView`:

```swift
    @State private var closeUpCrops: [(id: Int, image: CGImage)] = []
```

Add `import ImageIO` is NOT needed (CGImageSource comes via ImageIO which SwiftUI targets already link through CoreGraphics; if the compiler complains, add `import ImageIO` at the top of LibraryGridView.swift).

Wrap the stage from Task 7's stage column in an `HStack` with the panel — replace `loupeStage(for: asset)` with:

```swift
                        HStack(spacing: 0) {
                            loupeStage(for: asset)
                            closeUpsPanel
                        }
```

and extend the existing `.task(id: asset.id.rawValue)` on the stage column to also refresh the crops:

```swift
                            .task(id: asset.id.rawValue) {
                                do {
                                    try model.requestVisibleLoupePreview(assetID: asset.id)
                                } catch {
                                    model.errorMessage = error.localizedDescription
                                }
                                await refreshCloseUps(for: asset.id)
                            }
```

Add the panel and its loader to `LoupeView`:

```swift
    @ViewBuilder
    private var closeUpsPanel: some View {
        if !closeUpCrops.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("CLOSE-UPS")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(closeUpCrops, id: \.id) { crop in
                            Image(decorative: crop.image, scale: 1)
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .frame(width: 112, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.white.opacity(0.14))
                                }
                        }
                    }
                }
            }
            .padding(10)
            .frame(width: 136)
            .background(Color.black.opacity(0.26))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Face close-ups")
        }
    }

    // Detection is display-only and per-selection: the cached preview is read
    // off the main actor, cropped in memory, and nothing is persisted.
    private func refreshCloseUps(for assetID: AssetID) async {
        closeUpCrops = []
        guard let previewURL = model.loupePreviewURL(for: assetID) else { return }
        let crops = await Task.detached(priority: .utility) { () -> [(id: Int, image: CGImage)] in
            guard let faces = try? CoreImageFaceExpressionAnalyzer().detectFaces(previewURL: previewURL),
                  !faces.isEmpty,
                  let source = CGImageSourceCreateWithURL(previewURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return []
            }
            let presentation = CloseUpFacesPresentation(
                faces: faces,
                imagePixelSize: CGSize(width: image.width, height: image.height)
            )
            return presentation.crops.compactMap { crop in
                image.cropping(to: crop.pixelRect).map { (id: crop.id, image: $0) }
            }
        }.value
        guard model.selectedAssetID == assetID else { return }
        closeUpCrops = crops
    }
```

- [ ] **Step 6: Build and run the full suite**

Run: `swift build && swift test`
Expected: build succeeds; all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripApp/CloseUpFacesPresentation.swift Tests/TeststripAppTests/CloseUpFacesPresentationTests.swift Sources/TeststripApp/LibraryGridView.swift
git commit -m "feat: show face close-ups beside the loupe during culling"
```

---

## Deferred (explicitly out of this plan)

- **Spacebar zoom-to-face** — Space is bound to next-photo advance (mockup 2a's own legend); rebinding needs Jesse's call.
- **Survey-grid winner ring (2b)** — delivered as the `✦ BEST` badge by culling-signals Task 8; adding a second marker here would double-mark the tile.
- **Singles left over after stack culling** (audit polish #10), filmstrip dimming (#12), EXIF overlay (#13), contenders-only compare (#9) — polish items, not arc-blockers.

## Self-Review Notes

- **Arc coverage:** blocker #1 → Tasks 1–2; #2 → Task 3; #3 → Task 5; #4 → Task 4; #5 → Task 6 (+ signals Task 8 for 2b); #6 → Task 9; #7 → culling-signals plan (not duplicated); #8 → Task 7. Narrative Select alignment: Potential Picks → Task 8; Close-Ups → Task 10.
- **Type consistency:** `recommendedCullingStackAssetID(in:)` defined in Task 3, consumed in Tasks 4 and 7; `selectPersistedCullingStack` final body shown in Task 4 supersedes Task 3's intermediate edit and is stated as such; `CullingSessionCompletionSummary`/`cullingSessionCompletion` names match between Task 5's model and view steps; `CullingStackListEntry` fields match between Task 7's model and rail; `qualityComponent`/`normalizedQualityRead` defined and consumed only within Task 9.
- **Anchors:** all line numbers are against main at commit `92e6652`; re-locate by symbol name if drifted (both concurrent plans move code in `LibraryGridView.swift` and `AppModel.swift`).
- **Provisional rule check:** no task writes flags/metadata from machine output — Task 2 writes only `evaluation_signals` via the existing worker; Tasks 3/4/5/6/7 only move selection/view or render; Task 8 is a query; Tasks 9/10 are presentation-only.







