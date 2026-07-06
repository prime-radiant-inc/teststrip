import XCTest
import TeststripCore
@testable import TeststripApp

final class LoupeExifSummaryPresentationTests: XCTestCase {
    func testSummaryJoinsCameraLensISOApertureShutterAndFocalLength() {
        let metadata = AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            cameraMake: "Fujifilm",
            cameraModel: "X-T5",
            lensModel: "XF56mmF1.2",
            isoSpeed: 200,
            aperture: 1.2,
            shutterSpeed: 1.0 / 400.0,
            focalLength: 56,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )

        let presentation = LoupeExifSummaryPresentation(technicalMetadata: metadata)

        XCTAssertEqual(presentation.summaryText, "Fujifilm X-T5 · XF56mmF1.2 · ISO 200 · ƒ/1.2 · 1/400s · 56mm")
        XCTAssertTrue(presentation.isVisible)
    }

    func testSummaryOmitsMissingFields() {
        let metadata = AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            isoSpeed: 800,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )

        let presentation = LoupeExifSummaryPresentation(technicalMetadata: metadata)

        XCTAssertEqual(presentation.summaryText, "ISO 800")
    }

    func testSummaryIsNilWhenNoTechnicalMetadataExists() {
        let presentation = LoupeExifSummaryPresentation(technicalMetadata: nil)

        XCTAssertNil(presentation.summaryText)
        XCTAssertFalse(presentation.isVisible)
    }

    func testSummaryIsNilWhenTechnicalMetadataHasNoDisplayableFields() {
        let metadata = AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )

        let presentation = LoupeExifSummaryPresentation(technicalMetadata: metadata)

        XCTAssertNil(presentation.summaryText)
        XCTAssertFalse(presentation.isVisible)
    }
}
