import CoreGraphics
import Foundation
import XCTest
@testable import TeststripCore

final class FaceExpressionEvaluationProviderTests: XCTestCase {
    func testFaceExpressionProviderMapsSmileAndEyeStateToPerPhotoFractions() throws {
        let faces = [
            DetectedFaceExpression(
                normalizedBounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.3),
                hasSmile: true,
                leftEyeClosed: false,
                rightEyeClosed: false,
                leftEyeCenter: nil,
                rightEyeCenter: nil
            ),
            DetectedFaceExpression(
                normalizedBounds: CGRect(x: 0.55, y: 0.25, width: 0.3, height: 0.3),
                hasSmile: false,
                leftEyeClosed: true,
                rightEyeClosed: false,
                leftEyeCenter: nil,
                rightEyeCenter: nil
            )
        ]
        let provider = FaceExpressionEvaluationProvider(analyzer: FakeFaceExpressionAnalyzer(faces: faces))
        let assetID = AssetID(rawValue: "asset-1")
        let provenance = ProviderProvenance(provider: "core-image-faces", model: "CIDetectorFace", version: "1", settingsHash: "default")

        let signals = try provider.evaluate(assetID: assetID, previewURL: URL(fileURLWithPath: "/tmp/preview.png"))

        XCTAssertEqual(signals, [
            EvaluationSignal(assetID: assetID, kind: .eyesOpen, value: .score(0.5), confidence: 0.7, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .smile, value: .score(0.5), confidence: 0.7, provenance: provenance)
        ])
    }

    func testFaceExpressionProviderReportsAllOpenAndAllSmilingAsFullScores() throws {
        let faces = [
            DetectedFaceExpression(
                normalizedBounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.3),
                hasSmile: true,
                leftEyeClosed: false,
                rightEyeClosed: false,
                leftEyeCenter: nil,
                rightEyeCenter: nil
            )
        ]
        let provider = FaceExpressionEvaluationProvider(analyzer: FakeFaceExpressionAnalyzer(faces: faces))

        let signals = try provider.evaluate(assetID: AssetID(rawValue: "asset-1"), previewURL: URL(fileURLWithPath: "/tmp/preview.png"))

        XCTAssertEqual(signals.map(\.kind), [.eyesOpen, .smile])
        XCTAssertEqual(signals.map(\.value), [.score(1.0), .score(1.0)])
    }

    func testFaceExpressionProviderEmitsNoSignalsWithoutFaces() throws {
        let provider = FaceExpressionEvaluationProvider(analyzer: FakeFaceExpressionAnalyzer(faces: []))

        let signals = try provider.evaluate(assetID: AssetID(rawValue: "asset-1"), previewURL: URL(fileURLWithPath: "/tmp/preview.png"))

        XCTAssertEqual(signals, [])
    }
}

struct FakeFaceExpressionAnalyzer: FaceExpressionAnalyzing {
    var faces: [DetectedFaceExpression]

    func detectFaces(previewURL: URL) throws -> [DetectedFaceExpression] {
        faces
    }
}
