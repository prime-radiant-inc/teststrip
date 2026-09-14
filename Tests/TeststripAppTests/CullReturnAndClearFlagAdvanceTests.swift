import XCTest
@testable import TeststripCore
@testable import TeststripApp

// Live-review cull key-behaviour minors (Reviewer 1, `burst` fixture):
//
// (a) Return on a standalone frame is a no-op (correct — there are no
//     siblings to reject), but its feedback was a ~2s transient toast, so a
//     reviewer could not tell whether the key was broken or the frame just
//     wasn't part of a stack. A "nothing changed" notice must persist until
//     the next cull action replaces or clears it.
//
// (b) `U` (clear flag) on the LAST frame of a stack wrapped the selection
//     backward to the first frame. Clearing un-sets the current frame, and
//     the wrapping next-undecided search then teleported to the earliest
//     undecided sibling — a frame the user had already passed. Clearing must
//     never move the selection toward an earlier index; it advances forward
//     (out of the stack when there is no undecided sibling ahead).
final class CullReturnAndClearFlagAdvanceTests: XCTestCase {

    // MARK: - (a) standalone Return no-op feedback

    func testStandaloneReturnNoOpNoticeDoesNotAutoFade() throws {
        let capturedAt = Date(timeIntervalSince1970: 500)
        let lonely = makeAsset(
            id: "standalone-lonely",
            path: "/Photos/Job/standalone-lonely.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let farAway = makeAsset(
            id: "standalone-far-away",
            path: "/Photos/Job/standalone-far-away.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(600))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "standalone-return-notice",
            assets: [lonely, farAway],
            seedsLargePreviews: true
        )
        model.select(lonely.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertEqual(feedback.assetID, lonely.id)
        XCTAssertTrue(feedback.isInformational, "the no-op writes no metadata")
        XCTAssertFalse(
            feedback.autoFades,
            "a 'nothing happened' notice must persist until the next cull action, not vanish after 2s"
        )
        // The no-op itself is preserved: no metadata written.
        XCTAssertNil(try repository.asset(id: lonely.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: farAway.id).metadata.flag)
        XCTAssertEqual(model.selectedAssetID, lonely.id)
    }

    func testDecisionToastStillAutoFades() throws {
        let capturedAt = Date(timeIntervalSince1970: 700)
        let frame = makeAsset(
            id: "decision-fades",
            path: "/Photos/Job/decision-fades.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "decision-toast-fades",
            assets: [frame]
        )
        model.select(frame.id)

        try model.applyCullingShortcut(.pick)

        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertFalse(feedback.isInformational, "a pick writes metadata and is undoable")
        XCTAssertTrue(feedback.autoFades, "a real decision toast keeps its 2s echo window")
    }

    // MARK: - (b) U on the last frame of a stack

    func testClearFlagOnLastStackFrameAdvancesForwardNotBackward() throws {
        let capturedAt = Date(timeIntervalSince1970: 1000)
        let frame1 = makeAsset(
            id: "clear-frame-1",
            path: "/Photos/Job/clear-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "clear-frame-2",
            path: "/Photos/Job/clear-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        // The frame we clear: it carries a flag so `U` is meaningful.
        let frame3 = makeAsset(
            id: "clear-frame-3",
            path: "/Photos/Job/clear-frame-3.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8)),
            metadata: AssetMetadata(flag: .pick)
        )
        let nextStackLead = makeAsset(
            id: "clear-next-lead",
            path: "/Photos/Job/clear-next-lead.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(30))
        )
        let nextStackMate = makeAsset(
            id: "clear-next-mate",
            path: "/Photos/Job/clear-next-mate.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(31))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "clear-last-stack-frame",
            assets: [frame1, frame2, frame3, nextStackLead, nextStackMate],
            seedsLargePreviews: true
        )
        model.select(frame3.id)

        try model.applyCullingShortcut(.clearFlag)

        XCTAssertNil(try repository.asset(id: frame3.id).metadata.flag, "U clears the flag")
        // Forward-only: leave the stack toward the next stop. The wrapping
        // search used to land back on `frame1` (the first undecided sibling).
        XCTAssertNotEqual(model.selectedAssetID, frame1.id)
        XCTAssertNotEqual(model.selectedAssetID, frame2.id)
        XCTAssertEqual(model.selectedAssetID, nextStackLead.id)
    }

    // A forward undecided sibling is still the advance target (the collapse
    // flow is unchanged for every non-last frame).
    func testClearFlagStillAdvancesToForwardUndecidedSibling() throws {
        let capturedAt = Date(timeIntervalSince1970: 2000)
        let frame1 = makeAsset(
            id: "fwd-frame-1",
            path: "/Photos/Job/fwd-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt),
            metadata: AssetMetadata(flag: .pick)
        )
        // frame2 is undecided, frame3 is decided — clearing frame1 must land on
        // frame2, not skip past it to frame3.
        let frame2 = makeAsset(
            id: "fwd-frame-2",
            path: "/Photos/Job/fwd-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let frame3 = makeAsset(
            id: "fwd-frame-3",
            path: "/Photos/Job/fwd-frame-3.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8)),
            metadata: AssetMetadata(flag: .reject)
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "clear-forward-sibling",
            assets: [frame1, frame2, frame3],
            seedsLargePreviews: true
        )
        model.select(frame1.id)

        try model.applyCullingShortcut(.clearFlag)

        XCTAssertEqual(model.selectedAssetID, frame2.id)
    }

    // MARK: - Fixtures (local; mirrors CullAutoAdvanceTests' helpers)

    private func makeAsset(
        id: String,
        path: String,
        technicalMetadata: AssetTechnicalMetadata? = nil,
        metadata: AssetMetadata = AssetMetadata()
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
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
}
