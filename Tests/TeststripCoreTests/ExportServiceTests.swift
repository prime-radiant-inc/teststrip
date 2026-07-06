import Foundation
import XCTest
import TeststripCore

final class ExportServiceTests: XCTestCase {
    func testPresetsMatchApprovedSpecValues() {
        XCTAssertEqual(ExportPreset.fullResolutionJPEG.name, "Full-res JPEG")
        XCTAssertEqual(ExportPreset.fullResolutionJPEG.settings.jpegQuality, 0.9)
        XCTAssertNil(ExportPreset.fullResolutionJPEG.settings.longEdgeMaximumPixels)
        XCTAssertEqual(ExportPreset.web2048.name, "Web 2048px")
        XCTAssertEqual(ExportPreset.web2048.settings.jpegQuality, 0.8)
        XCTAssertEqual(ExportPreset.web2048.settings.longEdgeMaximumPixels, 2048)
        XCTAssertEqual(ExportPreset.all, [.fullResolutionJPEG, .web2048])
    }

    func testSettingsClampJpegQualityToUnitRange() {
        XCTAssertEqual(ExportSettings(jpegQuality: 1.5).jpegQuality, 1.0)
        XCTAssertEqual(ExportSettings(jpegQuality: -0.2).jpegQuality, 0.0)
        XCTAssertEqual(ExportSettings(jpegQuality: 0.8, longEdgeMaximumPixels: 2048).longEdgeMaximumPixels, 2048)
    }
}
