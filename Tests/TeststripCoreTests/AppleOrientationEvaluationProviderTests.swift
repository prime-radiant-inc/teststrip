import XCTest
@testable import TeststripCore

final class AppleOrientationEvaluationProviderTests: XCTestCase {
    func testProviderNameIsOrientation() {
        let provider = AppleOrientationEvaluationProvider()
        XCTAssertEqual(provider.name, "orientation")
    }

    func testEvaluateReturnsEmptySignals() throws {
        let provider = AppleOrientationEvaluationProvider()
        let signals = try provider.evaluate(
            assetID: AssetID(rawValue: "test"),
            previewURL: URL(fileURLWithPath: "/tmp/nonexistent.jpg")
        )
        XCTAssertTrue(signals.isEmpty)
    }

    func testEvaluateWithOrientationReturnsNilForMissingFile() {
        let provider = AppleOrientationEvaluationProvider()
        XCTAssertThrowsError(
            try provider.evaluateWithOrientation(
                assetID: AssetID(rawValue: "test"),
                previewURL: URL(fileURLWithPath: "/tmp/nonexistent.jpg")
            )
        )
    }

    func testRotationAngleQuantization() {
        XCTAssertNil(AppleOrientationEvaluationProvider.quantizeRotation(0))
        XCTAssertNil(AppleOrientationEvaluationProvider.quantizeRotation(5))
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(85), 90)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(90), 90)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(95), 90)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(175), 180)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(180), 180)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(185), 180)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(265), 270)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(270), 270)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(275), 270)
        XCTAssertNil(AppleOrientationEvaluationProvider.quantizeRotation(355))
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(-90), 270)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(-180), 180)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(-270), 90)
    }
}
