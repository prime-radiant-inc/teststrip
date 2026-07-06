import XCTest
import TeststripCore

final class AssetStackBuilderTests: XCTestCase {
    func testGroupsSameFolderFramesWithinCaptureGap() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let assets = [
            makeAsset(id: "frame-1", path: "/Photos/Job/frame-1.cr2", capturedAt: capturedAt),
            makeAsset(id: "frame-2", path: "/Photos/Job/frame-2.cr2", capturedAt: capturedAt.addingTimeInterval(1.2)),
            makeAsset(id: "frame-3", path: "/Photos/Job/frame-3.cr2", capturedAt: capturedAt.addingTimeInterval(2.8))
        ]

        let stacks = AssetStackBuilder(maximumCaptureGap: 2).stacks(from: assets)

        XCTAssertEqual(stacks, [
            AssetStack(
                assetIDs: assets.map(\.id),
                rationale: "Same folder, captured within 2s"
            )
        ])
    }

    func testSplitsStacksAcrossFoldersAndLargeCaptureGaps() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(id: "first", path: "/Photos/Job/first.cr2", capturedAt: capturedAt)
        let otherFolder = makeAsset(id: "other-folder", path: "/Photos/Other/other-folder.cr2", capturedAt: capturedAt.addingTimeInterval(1))
        let late = makeAsset(id: "late", path: "/Photos/Job/late.cr2", capturedAt: capturedAt.addingTimeInterval(10))
        let lateNeighbor = makeAsset(id: "late-neighbor", path: "/Photos/Job/late-neighbor.cr2", capturedAt: capturedAt.addingTimeInterval(11))

        let stacks = AssetStackBuilder(maximumCaptureGap: 2).stacks(from: [first, otherFolder, late, lateNeighbor])

        XCTAssertEqual(stacks, [
            AssetStack(assetIDs: [first.id], rationale: nil),
            AssetStack(assetIDs: [otherFolder.id], rationale: nil),
            AssetStack(
                assetIDs: [late.id, lateNeighbor.id],
                rationale: "Same folder, captured within 2s"
            )
        ])
    }

    func testKeepsUndatedAndUngroupedFramesAsSingletonStacks() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let undated = makeAsset(id: "undated", path: "/Photos/Job/undated.cr2", capturedAt: nil)
        let dated = makeAsset(id: "dated", path: "/Photos/Job/dated.cr2", capturedAt: capturedAt)

        let stacks = AssetStackBuilder(maximumCaptureGap: 2).stacks(from: [undated, dated])

        XCTAssertEqual(stacks, [
            AssetStack(assetIDs: [undated.id], rationale: nil),
            AssetStack(assetIDs: [dated.id], rationale: nil)
        ])
    }

    func testGroupsFramesWithNearMatchingVisualSimilarityVectors() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(id: "first", path: "/Photos/Job/first.cr2", capturedAt: capturedAt)
        let similar = makeAsset(id: "similar", path: "/Photos/Other/similar.cr2", capturedAt: capturedAt.addingTimeInterval(60))
        let different = makeAsset(id: "different", path: "/Photos/Job/different.cr2", capturedAt: capturedAt.addingTimeInterval(120))

        let stacks = AssetStackBuilder(maximumCaptureGap: 2).stacks(
            from: [first, similar, different],
            visualSimilarityVectorsByAssetID: [
                first.id: [0.1, 0.2, 0.3],
                similar.id: [0.11, 0.2, 0.29],
                different.id: [0.8, 0.1, 0.1]
            ]
        )

        XCTAssertEqual(stacks, [
            AssetStack(assetIDs: [first.id, similar.id], rationale: "Visual similarity"),
            AssetStack(assetIDs: [different.id], rationale: nil)
        ])
    }

    private func makeAsset(id: String, path: String, capturedAt: Date?) -> Asset {
        let technicalMetadata = capturedAt.map { date in
            AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                capturedAt: date,
                provenance: ProviderProvenance(provider: "test", model: "test", version: "1", settingsHash: "test")
            )
        }
        return Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: capturedAt ?? Date(timeIntervalSince1970: 0)),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: technicalMetadata
        )
    }
}
