import XCTest
import TeststripCore
@testable import TeststripApp

final class LibraryGridLayoutTests: XCTestCase {
    func testThumbnailWidthClampsToSupportedRange() {
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 40).thumbnailWidth, 96)
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 140).thumbnailWidth, 140)
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 400).thumbnailWidth, 260)
    }

    func testDensityLabelReflectsThumbnailWidth() {
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 96).densityLabel, "Compact")
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 140).densityLabel, "Comfortable")
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 220).densityLabel, "Large")
    }

    func testAccessibilityValueIncludesRoundedWidthAndDensity() {
        XCTAssertEqual(
            LibraryGridLayout(thumbnailWidth: 139.7).accessibilityValue,
            "140 px, Comfortable"
        )
    }

    func testGridSpacingFollowsFooterDensityPresentation() {
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 96).gridSpacing, 5)
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 140).gridSpacing, 11)
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 260).gridSpacing, 11)
    }

    func testFooterDensityControlsReflectSelectedPresentation() {
        let compactControls = LibraryGridLayout(thumbnailWidth: 96).footerDensityControls
        XCTAssertEqual(compactControls.map(\.title), ["Comfortable", "Compact"])
        XCTAssertEqual(compactControls.map(\.thumbnailWidth), [140, 96])
        XCTAssertEqual(compactControls.map(\.isSelected), [false, true])

        let comfortableControls = LibraryGridLayout(thumbnailWidth: 140).footerDensityControls
        XCTAssertEqual(comfortableControls.map(\.title), ["Comfortable", "Compact"])
        XCTAssertEqual(comfortableControls.map(\.thumbnailWidth), [140, 96])
        XCTAssertEqual(comfortableControls.map(\.isSelected), [true, false])

        let largeControls = LibraryGridLayout(thumbnailWidth: 220).footerDensityControls
        XCTAssertEqual(largeControls.map(\.isSelected), [true, false])
    }

    func testOverviewThumbnailScalingPreservesFullImage() {
        XCTAssertEqual(AssetGridPreviewPolicy.thumbnailScaling, .fit)
    }

    func testGridSelectionFromPointerDoesNotAutoScroll() {
        XCTAssertFalse(
            LibraryGridSelectionScrollPolicy.shouldScrollSelectedAssetIntoView(
                selectedAssetID: "asset-2",
                suppressedSelectionScrollAssetID: "asset-2"
            )
        )
    }

    func testProgrammaticGridSelectionStillAutoScrolls() {
        XCTAssertTrue(
            LibraryGridSelectionScrollPolicy.shouldScrollSelectedAssetIntoView(
                selectedAssetID: "asset-2",
                suppressedSelectionScrollAssetID: nil
            )
        )
    }

    func testClearedGridSelectionDoesNotAutoScroll() {
        XCTAssertFalse(
            LibraryGridSelectionScrollPolicy.shouldScrollSelectedAssetIntoView(
                selectedAssetID: nil,
                suppressedSelectionScrollAssetID: nil
            )
        )
    }

    func testGridCellAspectRatioUsesCatalogedImageDimensions() {
        let portrait = Asset.gridLayoutTestAsset(width: 4000, height: 6000)
        let panoramic = Asset.gridLayoutTestAsset(width: 6000, height: 2000)

        XCTAssertEqual(AssetGridCellLayout.aspectRatio(for: portrait), 2.0 / 3.0)
        XCTAssertEqual(AssetGridCellLayout.aspectRatio(for: panoramic), 3.0)
    }

    func testGridCellAspectRatioFallsBackWhenDimensionsAreMissing() {
        let asset = Asset.gridLayoutTestAsset(width: nil, height: nil)

        XCTAssertEqual(AssetGridCellLayout.aspectRatio(for: asset), 3.0 / 2.0)
    }

    func testGridCellAspectRatioFallsBackWhenDimensionsAreInvalid() {
        let asset = Asset.gridLayoutTestAsset(width: 4000, height: 0)

        XCTAssertEqual(AssetGridCellLayout.aspectRatio(for: asset), 3.0 / 2.0)
    }
}

private extension Asset {
    static func gridLayoutTestAsset(width: Int?, height: Int?) -> Asset {
        Asset(
            id: AssetID(rawValue: "layout-\(width ?? 0)-\(height ?? 0)"),
            originalURL: URL(fileURLWithPath: "/Photos/layout.jpg"),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 0)),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: technicalMetadata(width: width, height: height)
        )
    }

    private static func technicalMetadata(width: Int?, height: Int?) -> AssetTechnicalMetadata? {
        guard let width, let height else { return nil }
        return AssetTechnicalMetadata(
            pixelWidth: width,
            pixelHeight: height,
            provenance: ProviderProvenance(provider: "test", model: "test", version: "1", settingsHash: "test")
        )
    }
}
