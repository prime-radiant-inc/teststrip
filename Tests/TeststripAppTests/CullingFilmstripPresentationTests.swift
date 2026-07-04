import XCTest
import TeststripCore
@testable import TeststripApp

final class CullingFilmstripPresentationTests: XCTestCase {
    func testFilmstripCentersSelectedAssetWhenPossible() {
        let assets = Self.assets(count: 20)

        let presentation = CullingFilmstripPresentation(
            assets: assets,
            selectedAssetID: assets[10].id,
            visibleLimit: 6
        )

        XCTAssertEqual(presentation.visibleAssets.map(\.id), assets[7..<13].map(\.id))
        XCTAssertEqual(presentation.positionText, "Frame 11 of 20")
    }

    func testFilmstripClampsNearBeginning() {
        let assets = Self.assets(count: 20)

        let presentation = CullingFilmstripPresentation(
            assets: assets,
            selectedAssetID: assets[1].id,
            visibleLimit: 6
        )

        XCTAssertEqual(presentation.visibleAssets.map(\.id), assets[0..<6].map(\.id))
        XCTAssertEqual(presentation.positionText, "Frame 2 of 20")
    }

    func testFilmstripClampsNearEnd() {
        let assets = Self.assets(count: 20)

        let presentation = CullingFilmstripPresentation(
            assets: assets,
            selectedAssetID: assets[19].id,
            visibleLimit: 6
        )

        XCTAssertEqual(presentation.visibleAssets.map(\.id), assets[14..<20].map(\.id))
        XCTAssertEqual(presentation.positionText, "Frame 20 of 20")
    }

    func testFilmstripFallsBackToStartWhenSelectionIsMissing() {
        let assets = Self.assets(count: 8)

        let presentation = CullingFilmstripPresentation(
            assets: assets,
            selectedAssetID: AssetID(rawValue: "missing"),
            visibleLimit: 4
        )

        XCTAssertEqual(presentation.visibleAssets.map(\.id), assets[0..<4].map(\.id))
        XCTAssertEqual(presentation.positionText, "8 frames")
    }

    private static func assets(count: Int) -> [Asset] {
        (0..<count).map { index in
            Asset(
                id: AssetID(rawValue: "asset-\(index)"),
                originalURL: URL(fileURLWithPath: "/Photos/asset-\(index).jpg"),
                volumeIdentifier: nil,
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1))),
                availability: .online,
                metadata: AssetMetadata()
            )
        }
    }
}
