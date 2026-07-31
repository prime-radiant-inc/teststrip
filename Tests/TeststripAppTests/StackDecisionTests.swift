import Observation
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// Task 16: Return promotes the current frame (Pick) and rejects the rest of
// its stack in one gesture, then advances past the stack. Covers the single
// undo-group requirement and the confirm-before-write boundary (siblings
// only — nothing outside the stack is touched).
final class StackDecisionTests: XCTestCase {
    func testPromoteFlagsFrameAndSiblingsInOneUndoGroupAndAdvances() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let frame1 = makeAsset(
            id: "frame-1",
            path: "/Photos/Job/frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "frame-2",
            path: "/Photos/Job/frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let frame3 = makeAsset(
            id: "frame-3",
            path: "/Photos/Job/frame-3.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let frame4 = makeAsset(
            id: "frame-4",
            path: "/Photos/Job/frame-4.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(2.6))
        )
        let outsideStack = makeAsset(
            id: "outside-stack",
            path: "/Photos/Other/outside-stack.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(30))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "promote-stack",
            assets: [frame1, frame2, frame3, frame4, outsideStack]
        )
        model.select(frame2.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: frame2.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frame3.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: frame4.id).metadata.flag, .reject)
        // Confirm-before-write: promoting never touches assets outside the stack.
        XCTAssertNil(try repository.asset(id: outsideStack.id).metadata.flag)
        // Advances to the next stack's first undecided frame.
        XCTAssertEqual(model.selectedAssetID, outsideStack.id)

        // A single ⌘Z reverts all four flags it set.
        try model.undoMetadataChange()
        XCTAssertNil(try repository.asset(id: frame1.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frame2.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frame3.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frame4.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: outsideStack.id).metadata.flag)
    }

    func testReturnShortcutPromotesAndRejectsSiblings() throws {
        let capturedAt = Date(timeIntervalSince1970: 200)
        let frame1 = makeAsset(
            id: "return-frame-1",
            path: "/Photos/Job/return-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "return-frame-2",
            path: "/Photos/Job/return-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "return-shortcut-promotes",
            assets: [frame1, frame2]
        )
        model.select(frame1.id)

        XCTAssertEqual(CullingShortcut(key: .returnKey), .promoteAndRejectSiblings)
        try model.applyCullingShortcut(.promoteAndRejectSiblings)

        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frame2.id).metadata.flag, .reject)
    }

    // Maya's session (persona-1): pressing Return silently overrode her
    // explicit pick of a sibling with no toast, so she couldn't tell what
    // happened without reading the database. Promote must set the same
    // decision-feedback the P/X shortcuts set, naming the full effect.
    func testPromoteSetsDecisionFeedbackNamingSiblingCount() throws {
        let capturedAt = Date(timeIntervalSince1970: 300)
        let frame1 = makeAsset(
            id: "toast-frame-1",
            path: "/Photos/Job/toast-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "toast-frame-2",
            path: "/Photos/Job/toast-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let frame3 = makeAsset(
            id: "toast-frame-3",
            path: "/Photos/Job/toast-frame-3.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "promote-stack-toast",
            assets: [frame1, frame2, frame3]
        )
        model.select(frame1.id)

        XCTAssertNil(model.lastCullingMetadataDecision)
        try model.promoteCurrentFrameAndRejectSiblings()

        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertEqual(feedback.assetID, frame1.id)
        XCTAssertEqual(feedback.filename, "toast-frame-1.cr2")
        XCTAssertEqual(feedback.decisionText, "Kept toast-frame-1.cr2 · rejected 2 · ⌘Z undoes")
    }

    func testPromoteSingleSiblingUsesSingularWording() throws {
        let capturedAt = Date(timeIntervalSince1970: 400)
        let frame1 = makeAsset(
            id: "singular-frame-1",
            path: "/Photos/Job/singular-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "singular-frame-2",
            path: "/Photos/Job/singular-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "promote-stack-toast-singular",
            assets: [frame1, frame2]
        )
        model.select(frame1.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertEqual(feedback.decisionText, "Kept singular-frame-1.cr2 · rejected 1 · ⌘Z undoes")
    }

    // Jesse's ruling (2026-07-11): promoting must never reflag a sibling the
    // user already picked. Picked siblings are protected (flag provenance is
    // not recorded, so ALL picked siblings are protected — the safe reading),
    // only undecided/rejected siblings get rejected, and the toast discloses
    // the kept pick by filename.
    func testPromoteProtectsPickedSiblingAndDisclosesInToast() throws {
        let capturedAt = Date(timeIntervalSince1970: 600)
        let frameA = makeAsset(
            id: "protect-frame-a",
            path: "/Photos/Job/protect-frame-a.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt),
            metadata: AssetMetadata(flag: .pick)
        )
        let frameB = makeAsset(
            id: "protect-frame-b",
            path: "/Photos/Job/protect-frame-b.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let frameC = makeAsset(
            id: "protect-frame-c",
            path: "/Photos/Job/protect-frame-c.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let frameD = makeAsset(
            id: "protect-frame-d",
            path: "/Photos/Job/protect-frame-d.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(2.6))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "promote-protects-pick",
            assets: [frameA, frameB, frameC, frameD]
        )
        model.select(frameB.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        // Both picks stand; only the undecided siblings were rejected.
        XCTAssertEqual(try repository.asset(id: frameA.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frameB.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frameC.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: frameD.id).metadata.flag, .reject)

        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertEqual(feedback.assetID, frameB.id)
        XCTAssertEqual(
            feedback.decisionText,
            "Kept protect-frame-b.cr2 · rejected 2 · kept your pick of protect-frame-a.cr2 · ⌘Z undoes"
        )

        // Undo is still one group: reverts the promote's writes (B/C/D) and
        // leaves the protected pick untouched (it was never written).
        try model.undoMetadataChange()
        XCTAssertEqual(try repository.asset(id: frameA.id).metadata.flag, .pick)
        XCTAssertNil(try repository.asset(id: frameB.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frameC.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frameD.id).metadata.flag)
    }

    func testPromoteProtectsMultiplePickedSiblingsWithPluralToast() throws {
        let capturedAt = Date(timeIntervalSince1970: 700)
        let frameA = makeAsset(
            id: "plural-frame-a",
            path: "/Photos/Job/plural-frame-a.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt),
            metadata: AssetMetadata(flag: .pick)
        )
        let frameB = makeAsset(
            id: "plural-frame-b",
            path: "/Photos/Job/plural-frame-b.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)),
            metadata: AssetMetadata(flag: .pick)
        )
        let frameC = makeAsset(
            id: "plural-frame-c",
            path: "/Photos/Job/plural-frame-c.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let frameD = makeAsset(
            id: "plural-frame-d",
            path: "/Photos/Job/plural-frame-d.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(2.6))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "promote-protects-picks-plural",
            assets: [frameA, frameB, frameC, frameD]
        )
        model.select(frameC.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        XCTAssertEqual(try repository.asset(id: frameA.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frameB.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frameC.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frameD.id).metadata.flag, .reject)

        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertEqual(
            feedback.decisionText,
            "Kept plural-frame-c.cr2 · rejected 1 · kept your picks of 2 siblings · ⌘Z undoes"
        )
    }

    func testPromoteStillRejectsPreviouslyRejectedAndUndecidedSiblings() throws {
        let capturedAt = Date(timeIntervalSince1970: 800)
        let frameA = makeAsset(
            id: "rereject-frame-a",
            path: "/Photos/Job/rereject-frame-a.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt),
            metadata: AssetMetadata(flag: .reject)
        )
        let frameB = makeAsset(
            id: "rereject-frame-b",
            path: "/Photos/Job/rereject-frame-b.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "promote-rejects-rejected",
            assets: [frameA, frameB]
        )
        model.select(frameB.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        XCTAssertEqual(try repository.asset(id: frameA.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: frameB.id).metadata.flag, .pick)
        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertEqual(feedback.decisionText, "Kept rereject-frame-b.cr2 · rejected 1 · ⌘Z undoes")
    }

    // Persona-3 item 4: Return on a frame with no siblings at all used to be
    // a genuine silent no-op (the guard returned before anything fired) —
    // three presses read as the app hanging. Now it shows decision feedback
    // and writes nothing.
    func testPromoteOnSingleFrameShowsNoticeAndWritesNoMetadata() throws {
        let capturedAt = Date(timeIntervalSince1970: 500)
        let lonely = makeAsset(
            id: "lonely-frame",
            path: "/Photos/Job/lonely-frame.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let farAway = makeAsset(
            id: "far-away-frame",
            path: "/Photos/Job/far-away-frame.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(600))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "promote-single-frame",
            assets: [lonely, farAway]
        )
        model.select(lonely.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertEqual(feedback.assetID, lonely.id)
        XCTAssertEqual(feedback.decisionText, "No stack to promote — P picks this frame")
        XCTAssertTrue(feedback.isInformational)
        XCTAssertNil(try repository.asset(id: lonely.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: farAway.id).metadata.flag)
        // Stays put — nothing to advance past.
        XCTAssertEqual(model.selectedAssetID, lonely.id)
    }

    // Final-verify FAIL finding (cull-004/cull-014): the rail's "Keep frame 1
    // · cut 2" button could silently no-op while Return worked. The view
    // built the rail's stack from vectors scoped to the selected stack while
    // promote re-resolved membership from full-catalog vectors — two
    // different partitions. The model must expose its own resolved stack
    // scope for auto-grouped stacks (not just persisted work-stack sets) so
    // the rail displays, and the button acts on, exactly the stack promote
    // will write.
    func testSelectedCullingStackScopeResolvesAutoGroupedStack() throws {
        let capturedAt = Date(timeIntervalSince1970: 900)
        let frame1 = makeAsset(
            id: "scope-frame-1",
            path: "/Photos/Job/scope-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "scope-frame-2",
            path: "/Photos/Job/scope-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let frame3 = makeAsset(
            id: "scope-frame-3",
            path: "/Photos/Job/scope-frame-3.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let single = makeAsset(
            id: "scope-single",
            path: "/Photos/Job/scope-single.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(900))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "auto-stack-scope",
            assets: [frame1, frame2, frame3, single]
        )
        model.select(frame1.id)

        let scope = try XCTUnwrap(model.selectedCullingStackScope)
        XCTAssertEqual(scope.assetIDs, [frame1.id, frame2.id, frame3.id])

        // The rail built the way the view builds it must promise exactly what
        // promote then writes.
        let presentation = CullingStackRailPresentation(
            assets: model.assets,
            selectedAssetID: model.selectedAssetID,
            evaluationSignalsByAssetID: model.selectedCullingStackEvaluationSignals(),
            explicitStackScope: model.selectedCullingStackScope
        )
        XCTAssertEqual(presentation.keepActionTitle, "Keep frame 1 · cut 2")
        try model.promoteCurrentFrameAndRejectSiblings()
        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frame2.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: frame3.id).metadata.flag, .reject)
        XCTAssertNil(try repository.asset(id: single.id).metadata.flag)

        // A frame outside any multi-frame stack resolves no scope, so the
        // rail hides exactly when promote would take its informational path.
        model.select(single.id)
        XCTAssertNil(model.selectedCullingStackScope)
    }

    // SP-C: a gated Return arms the commit instead of dropping the keystroke.
    // No metadata write happens at arm time; the render is requested at
    // front placement so it lands as soon as possible.
    func testGatedReturnArmsCommitAndRequestsFrontRender() throws {
        let (model, repository, _, _, frame1, frame2) = try makeArmedStackFixture(named: "gated-return-arms")
        model.select(frame1.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        XCTAssertNil(try repository.asset(id: frame1.id).metadata.flag)   // no write yet
        XCTAssertNil(try repository.asset(id: frame2.id).metadata.flag)
        XCTAssertEqual(model.armedStackCommitAssetID, frame1.id)
        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertEqual(feedback.decisionText, "Rendering full preview… will keep when ready")
        XCTAssertTrue(feedback.isInformational)
        // The render was requested (front placement). Don't assert it is the
        // *running* item: with a supervisor present, select() may enqueue an
        // XMP selection check that occupies the single running slot first.
        let armedItem = model.backgroundWorkQueue.item(id: WorkSessionID(rawValue: "preview-\(frame1.id.rawValue)-large"))
        XCTAssertTrue([.queued, .running].contains(armedItem?.status))
    }

    @MainActor
    func testArmedCommitFiresWhenRenderLands() async throws {
        let (model, repository, previewCache, transport, frame1, frame2) = try makeArmedStackFixture(named: "armed-commit-fires")
        model.select(frame1.id)
        try model.promoteCurrentFrameAndRejectSiblings()
        XCTAssertEqual(model.armedStackCommitAssetID, frame1.id)

        // The armed preview item must be RUNNING before its terminal event
        // means anything: if select() put an XMP selection check in the
        // single running slot, drain it first (AppModelTests.swift:3173-3199
        // pattern), then wait for the armed item itself to become running.
        let itemID = WorkSessionID(rawValue: "preview-\(frame1.id.rawValue)-large")
        try await drainUntilRunning(itemID, transport: transport, model: model)
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: frame1.id, level: .large)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(itemID: itemID, message: "rendered")))
        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)

        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frame2.id).metadata.flag, .reject)
        // Provenance: the deferred commit is still the explicit user gesture —
        // a confirmed (user-origin) flag, not a tentative AI one.
        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.confirmedProjection.flag, .pick)
        XCTAssertNil(model.armedStackCommitAssetID)
        // Same single undo group as a direct Return.
        try model.undoMetadataChange()
        XCTAssertNil(try repository.asset(id: frame1.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frame2.id).metadata.flag)
    }

    @MainActor
    func testOtherShortcutDisarmsBeforeRenderLands() async throws {
        let (model, repository, previewCache, transport, frame1, frame2) = try makeArmedStackFixture(named: "other-shortcut-disarms")
        model.select(frame1.id)
        try model.promoteCurrentFrameAndRejectSiblings()
        XCTAssertEqual(model.armedStackCommitAssetID, frame1.id)

        // Arm, then any other input:
        try model.applyCullingShortcut(.toggleAutoAdvance)
        XCTAssertNil(model.armedStackCommitAssetID)

        // Render landing afterwards must NOT commit.
        let itemID = WorkSessionID(rawValue: "preview-\(frame1.id.rawValue)-large")
        try await drainUntilRunning(itemID, transport: transport, model: model)
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: frame1.id, level: .large)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(itemID: itemID, message: "rendered")))
        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)

        XCTAssertNil(try repository.asset(id: frame1.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frame2.id).metadata.flag)
    }

    @MainActor
    func testSelectionChangeDisarmsBeforeRenderLands() async throws {
        let (model, repository, previewCache, transport, frame1, frame2) = try makeArmedStackFixture(named: "selection-change-disarms")
        model.select(frame1.id)
        try model.promoteCurrentFrameAndRejectSiblings()
        XCTAssertEqual(model.armedStackCommitAssetID, frame1.id)

        // Arm, then any other selection:
        model.select(frame2.id)
        XCTAssertNil(model.armedStackCommitAssetID)

        // Render landing afterwards must NOT commit.
        let itemID = WorkSessionID(rawValue: "preview-\(frame1.id.rawValue)-large")
        try await drainUntilRunning(itemID, transport: transport, model: model)
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: frame1.id, level: .large)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(itemID: itemID, message: "rendered")))
        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)

        XCTAssertNil(try repository.asset(id: frame1.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frame2.id).metadata.flag)
    }

    // An original that can never render (offline source) must not arm —
    // arming would wait forever for a preview request the gate itself
    // refuses to make.
    func testReturnRefusesToArmWhenOriginalUnavailable() throws {
        let capturedAt = Date(timeIntervalSince1970: 2000)
        let frame1 = makeAsset(
            id: "unavailable-original-frame-1",
            path: "/Photos/Job/unavailable-original-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt),
            availability: .offline
        )
        let frame2 = makeAsset(
            id: "unavailable-original-frame-2",
            path: "/Photos/Job/unavailable-original-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, repository, _) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "return-refuses-unavailable",
            assets: [frame1, frame2],
            seedsLargePreviews: false
        )
        model.select(frame1.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        XCTAssertNil(model.armedStackCommitAssetID)
        XCTAssertEqual(try XCTUnwrap(model.lastCullingMetadataDecision).decisionText, "Preview unavailable — not committed")
        XCTAssertTrue(model.backgroundWorkQueue.items.filter { $0.kind == .previewGeneration }.isEmpty)
        XCTAssertNil(try repository.asset(id: frame1.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frame2.id).metadata.flag)
    }

    // A staged frame that has already exhausted its automatic preview-render
    // attempts must not arm either — the render the arm is waiting on is the
    // exact one the retry cap gave up on.
    func testReturnRefusesToArmWhenAttemptsExhausted() throws {
        let capturedAt = Date(timeIntervalSince1970: 2000)
        let frame1 = makeAsset(
            id: "attempts-exhausted-frame-1",
            path: "/Photos/Job/attempts-exhausted-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "attempts-exhausted-frame-2",
            path: "/Photos/Job/attempts-exhausted-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, repository, _) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "return-refuses-exhausted",
            assets: [frame1, frame2],
            seedsLargePreviews: false
        )
        for _ in 0..<3 {
            try repository.recordPreviewGenerationFailure(assetID: frame1.id, level: .large, errorMessage: "boom")
        }
        model.select(frame1.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        XCTAssertNil(model.armedStackCommitAssetID)
        XCTAssertEqual(try XCTUnwrap(model.lastCullingMetadataDecision).decisionText, "Preview unavailable — not committed")
        XCTAssertNil(try repository.asset(id: frame1.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frame2.id).metadata.flag)
    }

    @MainActor
    func testRenderFailureDisarmsWithUnavailableToast() async throws {
        let (model, repository, _, transport, frame1, frame2) = try makeArmedStackFixture(named: "render-failure-disarms")
        model.select(frame1.id)
        try model.promoteCurrentFrameAndRejectSiblings()
        XCTAssertEqual(model.armedStackCommitAssetID, frame1.id)

        let itemID = WorkSessionID(rawValue: "preview-\(frame1.id.rawValue)-large")
        try await drainUntilRunning(itemID, transport: transport, model: model)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(itemID: itemID, message: "render failed")))
        try await waitForBackgroundWorkStatus(.failed, itemID: itemID, in: model)

        XCTAssertNil(model.armedStackCommitAssetID)
        XCTAssertEqual(try XCTUnwrap(model.lastCullingMetadataDecision).decisionText, "Preview unavailable — not committed")
        XCTAssertNil(try repository.asset(id: frame1.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frame2.id).metadata.flag)
    }

    @MainActor
    func testArmedCommitFiresAtMostOnce() async throws {
        let (model, repository, previewCache, transport, frame1, frame2) = try makeArmedStackFixture(named: "fires-at-most-once")
        model.select(frame1.id)
        try model.promoteCurrentFrameAndRejectSiblings()
        XCTAssertEqual(model.armedStackCommitAssetID, frame1.id)

        let itemID = WorkSessionID(rawValue: "preview-\(frame1.id.rawValue)-large")
        try await drainUntilRunning(itemID, transport: transport, model: model)
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: frame1.id, level: .large)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(itemID: itemID, message: "rendered")))
        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)

        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frame2.id).metadata.flag, .reject)
        XCTAssertNil(model.armedStackCommitAssetID)
        let postCommitSelection = model.selectedAssetID

        // Fire normally, note the post-commit selection, then emit a second
        // .completed for the same itemID; flags and selection must be
        // unchanged and armedStackCommitAssetID must still be nil.
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(itemID: itemID, message: "rendered again")))
        // Give the (incorrect) re-fire a chance before asserting it didn't happen.
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frame2.id).metadata.flag, .reject)
        XCTAssertEqual(model.selectedAssetID, postCommitSelection)
        XCTAssertNil(model.armedStackCommitAssetID)
    }

    // Persona-1 (Maya) again: Return force-flips a sibling's staged frame
    // even when the frame itself already carries a confirmed reject — but
    // that override must be visible, not silent, so the toast discloses
    // "(was ✕)" and the single undo group restores the original reject too.
    func testPromoteForceFlipsRejectedStagedFrameAndDisclosesInToast() throws {
        let capturedAt = Date(timeIntervalSince1970: 1100)
        let frame1 = makeAsset(
            id: "force-flip-frame-1",
            path: "/Photos/Job/force-flip-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt),
            metadata: AssetMetadata(flag: .reject)
        )
        let frame2 = makeAsset(
            id: "force-flip-frame-2",
            path: "/Photos/Job/force-flip-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "promote-force-flip",
            assets: [frame1, frame2]
        )
        model.select(frame1.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frame2.id).metadata.flag, .reject)
        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertEqual(feedback.decisionText, "Kept force-flip-frame-1.cr2 (was ✕) · rejected 1 · ⌘Z undoes")
        // This decision writes metadata and has something to undo, so it must
        // NOT claim isInformational's no-metadata-written contract (queued
        // T7 review fix) — but decisionText is self-composed, so it must
        // still render verbatim (skip the generic toast wrap).
        XCTAssertFalse(feedback.isInformational)
        XCTAssertTrue(feedback.rendersVerbatim)

        // One ⌘Z restores everything, including the staged frame's original
        // reject — the force-flip is part of the same undo group.
        try model.undoMetadataChange()
        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .reject)
        XCTAssertNil(try repository.asset(id: frame2.id).metadata.flag)
    }

    // Negative case for the above: a tentative (AI-unconfirmed) reject was
    // never a real decision, so it must not read as a force-flip override —
    // no "(was ✕)" disclosure.
    func testPromoteWithTentativeRejectedStagedFrameOmitsWasRejectedDisclosure() throws {
        let capturedAt = Date(timeIntervalSince1970: 1200)
        let frame1 = makeAsset(
            id: "tentative-reject-frame-1",
            path: "/Photos/Job/tentative-reject-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt),
            metadata: AssetMetadata(flag: .reject, aiUnconfirmedFields: [.flag])
        )
        let frame2 = makeAsset(
            id: "tentative-reject-frame-2",
            path: "/Photos/Job/tentative-reject-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "promote-tentative-reject",
            assets: [frame1, frame2]
        )
        model.select(frame1.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .pick)
        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertFalse(feedback.decisionText.contains("(was ✕)"))
        XCTAssertEqual(feedback.decisionText, "Kept tentative-reject-frame-1.cr2 · rejected 1 · ⌘Z undoes")
    }

    // Carry-forward requirement (Task 2 trace): applyCullingStackDecision's
    // post-commit advance must land like ←/→ do — on the next stack's
    // AI-recommended frame (✦ or first tied leader), not just the literal
    // next asset in deck order, which would land on the next stack's first
    // frame instead.
    func testPromoteAdvancesToNextStacksRecommendedLandingFrame() throws {
        let capturedAt = Date(timeIntervalSince1970: 1300)
        let frame1 = makeAsset(
            id: "landing-stack-frame-1",
            path: "/Photos/Job/landing-stack-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "landing-stack-frame-2",
            path: "/Photos/Job/landing-stack-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let secondStackLead = makeAsset(
            id: "landing-second-stack-lead",
            path: "/Photos/Job/landing-second-stack-lead.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(30))
        )
        let secondStackBest = makeAsset(
            id: "landing-second-stack-best",
            path: "/Photos/Job/landing-second-stack-best.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(31))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "promote-advance-landing",
            assets: [frame1, frame2, secondStackLead, secondStackBest]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: secondStackLead.id, kind: .focus, value: .score(0.4), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: secondStackBest.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
        ])
        model.select(frame1.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frame2.id).metadata.flag, .reject)
        // Lands on the second stack's ✦ (highest focus score), not its lead
        // frame — the same landing ←/→ would use.
        XCTAssertEqual(model.selectedAssetID, secondStackBest.id)
    }

    // T7.5: Return's post-commit advance reuses the same landing helper as
    // ←/→, so `cullLandOnRecommendedFrame = false` must flip its target too —
    // frame 1 (capture order) instead of the second stack's ✦.
    func testPromoteAdvancesToNextStacksFirstFrameWhenLandOnRecommendedFrameDisabled() throws {
        let capturedAt = Date(timeIntervalSince1970: 1300)
        let frame1 = makeAsset(
            id: "landing-pref-off-frame-1",
            path: "/Photos/Job/landing-pref-off-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "landing-pref-off-frame-2",
            path: "/Photos/Job/landing-pref-off-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let secondStackLead = makeAsset(
            id: "landing-pref-off-second-lead",
            path: "/Photos/Job/landing-pref-off-second-lead.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(30))
        )
        let secondStackBest = makeAsset(
            id: "landing-pref-off-second-best",
            path: "/Photos/Job/landing-pref-off-second-best.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(31))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "promote-advance-landing-pref-off",
            assets: [frame1, frame2, secondStackLead, secondStackBest]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: secondStackLead.id, kind: .focus, value: .score(0.4), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: secondStackBest.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
        ])
        model.select(frame1.id)
        model.toggleCullLandOnRecommendedFrame()

        try model.promoteCurrentFrameAndRejectSiblings()

        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frame2.id).metadata.flag, .reject)
        XCTAssertEqual(model.selectedAssetID, secondStackLead.id)
    }

    // MARK: - Fixtures (mirrors AppModelTests' private helpers; kept local per file)

    private func makeAsset(
        id: String,
        path: String,
        technicalMetadata: AssetTechnicalMetadata? = nil,
        metadata: AssetMetadata = AssetMetadata(),
        availability: SourceAvailability = .online
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: availability,
            metadata: metadata,
            technicalMetadata: technicalMetadata
        )
    }

    private static func technicalMetadata(capturedAt: Date) -> AssetTechnicalMetadata {
        AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            capturedAt: capturedAt,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-app-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let result = try makeModelWithCatalogAssetsAndPreviewCache(named: name, assets: assets)
        return (result.model, result.repository)
    }

    // Every test in this file drives `promoteCurrentFrameAndRejectSiblings`,
    // which force-commits only once the staged frame's `.large` preview is
    // cached (Task 7's render gate) — so this seeds a placeholder for every
    // asset by default. The armed-commit tests withhold one via
    // `seedsLargePreviews: false` and the returned preview cache.
    private func makeModelWithCatalogAssetsAndPreviewCache(
        named name: String,
        assets: [Asset],
        workerSupervisor: WorkerSupervisor? = nil,
        seedsLargePreviews: Bool = true
    ) throws -> (model: AppModel, repository: CatalogRepository, previewCache: PreviewCache) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        if seedsLargePreviews {
            for asset in assets {
                try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))
            }
        }
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: workerSupervisor)
        return (model, repository, previewCache)
    }

    private func writePreviewPlaceholder(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("preview".utf8).write(to: url)
    }

    @MainActor
    private func waitForBackgroundWorkStatus(
        _ status: WorkSessionStatus,
        itemID: WorkSessionID,
        in model: AppModel
    ) async throws {
        for _ in 0..<100 {
            if model.backgroundWorkQueue.item(id: itemID)?.status == status {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for background work status \(status.rawValue)")
    }

    // Shared fixture for the armed-commit tests: a two-frame stack, a
    // `RecordingWorkerTransport` + single-slot `WorkerSupervisor`, and no
    // large preview seeded — the render gate starts closed so
    // `promoteCurrentFrameAndRejectSiblings()` arms instead of committing.
    private func makeArmedStackFixture(
        named name: String
    ) throws -> (
        model: AppModel,
        repository: CatalogRepository,
        previewCache: PreviewCache,
        transport: RecordingWorkerTransport,
        frame1: Asset,
        frame2: Asset
    ) {
        let capturedAt = Date(timeIntervalSince1970: 2000)
        let frame1 = makeAsset(
            id: "\(name)-frame-1",
            path: "/Photos/Job/\(name)-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "\(name)-frame-2",
            path: "/Photos/Job/\(name)-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 1), transport: transport)
        let (model, repository, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: name,
            assets: [frame1, frame2],
            workerSupervisor: supervisor,
            seedsLargePreviews: false
        )
        // The armed Return only ever fires from the cull loupe in real usage
        // (fireArmedStackCommitIfReady requires it); the model defaults to
        // .grid, so these tests set the stage explicitly.
        model.selectedView = .loupe
        return (model, repository, previewCache, transport, frame1, frame2)
    }

    // Drains whatever else occupies the single running slot (e.g. select()'s
    // XMP sync check) until `itemID` itself is running — the pattern
    // AppModelTests.swift:3173-3199 established for the same single-slot
    // supervisor setup.
    @MainActor
    private func drainUntilRunning(
        _ itemID: WorkSessionID,
        transport: RecordingWorkerTransport,
        model: AppModel
    ) async throws {
        while let runningItemID = model.backgroundWorkQueue.runningItems.first?.id, runningItemID != itemID {
            transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(itemID: runningItemID, message: "drained")))
            try await waitForBackgroundWorkStatus(.completed, itemID: runningItemID, in: model)
        }
        try await waitForBackgroundWorkStatus(.running, itemID: itemID, in: model)
    }
}

/// Records the JSON-lines commands `WorkerSupervisor` would send to the
/// out-of-process worker without ever completing them on its own, so tests
/// can drive terminal events (`.completed`/`.failed`) at exactly the moment
/// they want. Mirrors `AppModelTests`' private type of the same name (kept
/// local per file per Swift's file-private access).
private final class RecordingWorkerTransport: WorkerTransport {
    var outputHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?
    var terminationHandler: (() -> Void)?

    private(set) var lines: [String] = []
    private(set) var terminateCount = 0
    private(set) var isRunning = false

    func launch() throws {
        isRunning = true
    }

    func writeLine(_ line: String) throws {
        lines.append(line)
    }

    func terminate() {
        terminateCount += 1
        isRunning = false
    }

    func commands() throws -> [WorkerCommand] {
        try lines.map { try WorkerProtocolEncoder.decode($0) }
    }

    func emitOutputLine(_ line: String) {
        outputHandler?(line)
    }

    func emitErrorLine(_ line: String) {
        errorHandler?(line)
    }
}
