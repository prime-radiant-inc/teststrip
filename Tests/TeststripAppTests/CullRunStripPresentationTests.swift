import XCTest
import TeststripCore
@testable import TeststripApp

// Task 6 (culling-flow shell): the run strip collapses `allCullingStacks`
// into one stop per stack — a pill for multi-frame stacks, a single frame
// for standalones — replacing the old flat 12-thumb filmstrip.
final class CullRunStripPresentationTests: XCTestCase {
    func testMixedScopeProducesStopsInCaptureOrderWithLabelsLeadAssetsAndStandaloneFlag() {
        let capturedAt = Date(timeIntervalSince1970: 1000)
        let stackA = [
            Self.asset(id: "a1", filename: "IMG_0001.jpg", capturedAt: capturedAt),
            Self.asset(id: "a2", filename: "IMG_0002.jpg", capturedAt: capturedAt.addingTimeInterval(1))
        ]
        let standalone1 = Self.asset(id: "b1", filename: "IMG_0100.jpg", capturedAt: capturedAt.addingTimeInterval(100))
        let stackB = [
            Self.asset(id: "c1", filename: "IMG_0200.jpg", capturedAt: capturedAt.addingTimeInterval(200)),
            Self.asset(id: "c2", filename: "IMG_0201.jpg", capturedAt: capturedAt.addingTimeInterval(201))
        ]
        let standalone2 = Self.asset(id: "d1", filename: "IMG_0300.jpg", capturedAt: capturedAt.addingTimeInterval(300))
        let assets = stackA + [standalone1] + stackB + [standalone2]
        let stacks = [
            AssetStack(assetIDs: stackA.map(\.id)),
            AssetStack(assetIDs: [standalone1.id]),
            AssetStack(assetIDs: stackB.map(\.id)),
            AssetStack(assetIDs: [standalone2.id])
        ]

        let (stops, windowStart) = CullRunStripPresentation.stops(
            assets: assets,
            stacks: stacks,
            selectedAssetID: nil,
            pendingSparkleAssetIDs: []
        )

        XCTAssertEqual(windowStart, 0)
        XCTAssertEqual(stops.map(\.leadAssetID), [stackA[0].id, standalone1.id, stackB[0].id, standalone2.id])
        XCTAssertEqual(stops.map(\.id), [stackA[0].id, standalone1.id, stackB[0].id, standalone2.id])
        XCTAssertEqual(stops.map(\.isStandalone), [false, true, false, true])
        XCTAssertEqual(stops.map(\.assetIDs), [stackA.map(\.id), [standalone1.id], stackB.map(\.id), [standalone2.id]])
        XCTAssertEqual(stops.map(\.label), [
            CullStackLabelPresentation.label(for: stackA),
            CullStackLabelPresentation.label(for: [standalone1]),
            CullStackLabelPresentation.label(for: stackB),
            CullStackLabelPresentation.label(for: [standalone2])
        ])
    }

    func testIsCurrentFollowsSelectedAssetsContainingStop() {
        let stackA = [Self.asset(id: "a1"), Self.asset(id: "a2")]
        let standalone = Self.asset(id: "b1")
        let stacks = [AssetStack(assetIDs: stackA.map(\.id)), AssetStack(assetIDs: [standalone.id])]

        let (stops, _) = CullRunStripPresentation.stops(
            assets: stackA + [standalone],
            stacks: stacks,
            selectedAssetID: AssetID(rawValue: "a2"),
            pendingSparkleAssetIDs: []
        )

        XCTAssertEqual(stops.map(\.isCurrent), [true, false])
    }

    func testIsDoneTrueWhenEveryMemberCarriesAConfirmedFlag() {
        let picked = Self.asset(id: "a1", flag: .pick)
        let rejected = Self.asset(id: "a2", flag: .reject)
        let stacks = [AssetStack(assetIDs: [picked.id, rejected.id])]

        let (stops, _) = CullRunStripPresentation.stops(
            assets: [picked, rejected],
            stacks: stacks,
            selectedAssetID: nil,
            pendingSparkleAssetIDs: []
        )

        XCTAssertEqual(stops.count, 1)
        XCTAssertTrue(stops[0].isDone)
    }

    // Invariant: a tentative (AI-unconfirmed) flag is not a decision. If this
    // regressed to reading the raw `metadata.flag` instead of
    // `confirmedProjection.flag`, a stack with an unreviewed AI pick would
    // wrongly show as done.
    func testTentativeAIFlagKeepsTheStopUndone() {
        let confirmedPick = Self.asset(id: "a1", flag: .pick)
        let tentativePick = Self.asset(id: "a2", flag: .pick, aiUnconfirmedFields: [.flag])
        let stacks = [AssetStack(assetIDs: [confirmedPick.id, tentativePick.id])]

        let (stops, _) = CullRunStripPresentation.stops(
            assets: [confirmedPick, tentativePick],
            stacks: stacks,
            selectedAssetID: nil,
            pendingSparkleAssetIDs: []
        )

        XCTAssertEqual(stops.count, 1)
        XCTAssertFalse(stops[0].isDone)
    }

    func testSparkleCountCountsPendingSparkleAssetIDsWithinTheStop() {
        let a1 = Self.asset(id: "a1")
        let a2 = Self.asset(id: "a2")
        let b1 = Self.asset(id: "b1")
        let c1 = Self.asset(id: "c1")
        let stacks = [
            AssetStack(assetIDs: [a1.id, a2.id]),
            AssetStack(assetIDs: [b1.id]),
            AssetStack(assetIDs: [c1.id])
        ]

        let (stops, _) = CullRunStripPresentation.stops(
            assets: [a1, a2, b1, c1],
            stacks: stacks,
            selectedAssetID: nil,
            pendingSparkleAssetIDs: [a1.id, a2.id, b1.id]
        )

        XCTAssertEqual(stops.map(\.sparkleCount), [2, 1, 0])
    }

    func testWindowingCentersTheCurrentStopWithinVisibleLimit() {
        let assets = (0..<20).map { Self.asset(id: "a\($0)") }
        let stacks = assets.map { AssetStack(assetIDs: [$0.id]) }

        let (stops, windowStart) = CullRunStripPresentation.stops(
            assets: assets,
            stacks: stacks,
            selectedAssetID: assets[10].id,
            pendingSparkleAssetIDs: [],
            visibleLimit: 6
        )

        XCTAssertEqual(windowStart, 7)
        XCTAssertEqual(stops.map(\.leadAssetID), assets[7..<13].map(\.id))
    }

    func testWindowingClampsNearTheStart() {
        let assets = (0..<20).map { Self.asset(id: "a\($0)") }
        let stacks = assets.map { AssetStack(assetIDs: [$0.id]) }

        let (stops, windowStart) = CullRunStripPresentation.stops(
            assets: assets,
            stacks: stacks,
            selectedAssetID: assets[1].id,
            pendingSparkleAssetIDs: [],
            visibleLimit: 6
        )

        XCTAssertEqual(windowStart, 0)
        XCTAssertEqual(stops.map(\.leadAssetID), assets[0..<6].map(\.id))
    }

    func testWindowingClampsNearTheEnd() {
        let assets = (0..<20).map { Self.asset(id: "a\($0)") }
        let stacks = assets.map { AssetStack(assetIDs: [$0.id]) }

        let (stops, windowStart) = CullRunStripPresentation.stops(
            assets: assets,
            stacks: stacks,
            selectedAssetID: assets[19].id,
            pendingSparkleAssetIDs: [],
            visibleLimit: 6
        )

        XCTAssertEqual(windowStart, 14)
        XCTAssertEqual(stops.map(\.leadAssetID), assets[14..<20].map(\.id))
    }

    func testAllStopsReturnedWhenWithinVisibleLimit() {
        let stackA = [Self.asset(id: "a1"), Self.asset(id: "a2")]
        let standalone = Self.asset(id: "b1")
        let stacks = [AssetStack(assetIDs: stackA.map(\.id)), AssetStack(assetIDs: [standalone.id])]

        let (stops, windowStart) = CullRunStripPresentation.stops(
            assets: stackA + [standalone],
            stacks: stacks,
            selectedAssetID: nil,
            pendingSparkleAssetIDs: [],
            visibleLimit: 12
        )

        XCTAssertEqual(windowStart, 0)
        XCTAssertEqual(stops.count, 2)
    }

    private static func asset(
        id: String,
        filename: String? = nil,
        capturedAt: Date? = nil,
        flag: PickFlag? = nil,
        aiUnconfirmedFields: Set<MetadataField> = []
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(filename ?? id).jpg"),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(flag: flag, aiUnconfirmedFields: aiUnconfirmedFields),
            technicalMetadata: capturedAt.map { date in
                AssetTechnicalMetadata(
                    pixelWidth: 6000,
                    pixelHeight: 4000,
                    capturedAt: date,
                    provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
                )
            }
        )
    }
}

// MARK: - CullStripWindowing

// The shared centering/clamping helper behind both CullRunStripPresentation's
// stop windowing and the A/B compare filmstrip's raw-asset windowing
// (LibraryGridView.windowedAssets) — one algorithm, tested once here, so the
// two call sites can never drift apart on the centering math.
final class CullStripWindowingTests: XCTestCase {
    func testAnchorAtStartClampsToTheFront() {
        let window = CullStripWindowing.centeredWindow(count: 20, anchorIndex: 0, limit: 6)

        XCTAssertEqual(window, 0..<6)
    }

    func testAnchorInTheMiddleCenters() {
        let window = CullStripWindowing.centeredWindow(count: 20, anchorIndex: 10, limit: 6)

        XCTAssertEqual(window, 7..<13)
    }

    func testAnchorNearTheEndClampsToTheBack() {
        let window = CullStripWindowing.centeredWindow(count: 20, anchorIndex: 19, limit: 6)

        XCTAssertEqual(window, 14..<20)
    }

    func testCountBelowLimitReturnsTheWholeRange() {
        let window = CullStripWindowing.centeredWindow(count: 4, anchorIndex: 1, limit: 6)

        XCTAssertEqual(window, 0..<4)
    }

    func testCountEqualToLimitReturnsTheWholeRange() {
        let window = CullStripWindowing.centeredWindow(count: 6, anchorIndex: 3, limit: 6)

        XCTAssertEqual(window, 0..<6)
    }

    func testLimitBelowOneIsTreatedAsOne() {
        let window = CullStripWindowing.centeredWindow(count: 20, anchorIndex: 5, limit: 0)

        XCTAssertEqual(window, 5..<6)
    }
}
