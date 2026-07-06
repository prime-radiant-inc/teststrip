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
        XCTAssertEqual(compactControls.map(\.title), ["Compact", "Comfortable", "Large"])
        XCTAssertEqual(compactControls.map(\.thumbnailWidth), [96, 140, 220])
        XCTAssertEqual(compactControls.map(\.isSelected), [true, false, false])

        let comfortableControls = LibraryGridLayout(thumbnailWidth: 140).footerDensityControls
        XCTAssertEqual(comfortableControls.map(\.title), ["Compact", "Comfortable", "Large"])
        XCTAssertEqual(comfortableControls.map(\.thumbnailWidth), [96, 140, 220])
        XCTAssertEqual(comfortableControls.map(\.isSelected), [false, true, false])

        let largeControls = LibraryGridLayout(thumbnailWidth: 220).footerDensityControls
        XCTAssertEqual(largeControls.map(\.title), ["Compact", "Comfortable", "Large"])
        XCTAssertEqual(largeControls.map(\.thumbnailWidth), [96, 140, 220])
        XCTAssertEqual(largeControls.map(\.isSelected), [false, false, true])
    }

    func testOverviewThumbnailScalingPreservesFullImage() {
        XCTAssertEqual(AssetGridPreviewPolicy.thumbnailScaling, .fit)
    }

    func testGridPreviewStatusHidesWhenCachedPreviewExists() {
        let status = AssetGridPreviewStatusPresentation.presentation(
            previewURL: URL(fileURLWithPath: "/Previews/asset/grid.jpg"),
            queueStates: [
                PreviewGenerationQueueState(
                    item: PreviewGenerationItem(assetID: AssetID(rawValue: "asset"), level: .grid),
                    attemptCount: 0
                )
            ],
            activePreviewLevels: [.grid]
        )

        XCTAssertNil(status)
    }

    func testGridPreviewStatusShowsBuildingForActivePreviewWork() {
        let status = AssetGridPreviewStatusPresentation.presentation(
            previewURL: nil,
            queueStates: [],
            activePreviewLevels: [.grid]
        )

        XCTAssertEqual(status?.title, "Building preview")
        XCTAssertEqual(status?.systemImage, "clock.arrow.circlepath")
    }

    func testGridPreviewStatusShowsQueuedForPendingPreviewWork() {
        let status = AssetGridPreviewStatusPresentation.presentation(
            previewURL: nil,
            queueStates: [
                PreviewGenerationQueueState(
                    item: PreviewGenerationItem(assetID: AssetID(rawValue: "asset"), level: .grid),
                    attemptCount: 0
                )
            ],
            activePreviewLevels: []
        )

        XCTAssertEqual(status?.title, "Preview queued")
        XCTAssertEqual(status?.systemImage, "clock")
    }

    func testGridPreviewStatusShowsIssueForFailedPreviewWork() {
        let status = AssetGridPreviewStatusPresentation.presentation(
            previewURL: nil,
            queueStates: [
                PreviewGenerationQueueState(
                    item: PreviewGenerationItem(assetID: AssetID(rawValue: "asset"), level: .grid),
                    attemptCount: 1,
                    lastErrorMessage: "could not render preview"
                )
            ],
            activePreviewLevels: []
        )

        XCTAssertEqual(status?.title, "Preview issue")
        XCTAssertEqual(status?.systemImage, "exclamationmark.triangle.fill")
    }

    func testGridMetadataBadgesIncludeKeywordAcknowledgement() {
        let asset = Asset.gridLayoutTestAsset(
            metadata: AssetMetadata(
                rating: 4,
                colorLabel: .green,
                flag: .pick,
                keywords: ["portfolio", "client"]
            )
        )

        let presentation = AssetGridMetadataBadgePresentation.presentation(for: asset)

        XCTAssertEqual(presentation.flagSystemName, "flag.fill")
        XCTAssertEqual(presentation.ratingText, "★★★★")
        XCTAssertEqual(presentation.colorLabel, .green)
        XCTAssertEqual(presentation.keywordCountText, "2")
        XCTAssertEqual(presentation.keywordAccessibilityLabel, "2 keywords")
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
    static func gridLayoutTestAsset(metadata: AssetMetadata) -> Asset {
        Asset(
            id: AssetID(rawValue: "layout-metadata"),
            originalURL: URL(fileURLWithPath: "/Photos/layout.jpg"),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 0)),
            availability: .online,
            metadata: metadata
        )
    }

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
