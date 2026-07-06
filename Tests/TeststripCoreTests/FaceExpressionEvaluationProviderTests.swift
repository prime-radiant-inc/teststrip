import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
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

    func testEyeSharpnessUsesSharpestEyePerFaceFromPreviewCrops() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "face-expression-eye-sharpness")
        let previewURL = directory.appendingPathComponent("preview.png")
        // Checkerboard "eye" detail in the top-left quadrant, flat gray everywhere else.
        try writeEyePatchPNG(
            to: previewURL,
            width: 256,
            height: 256,
            patch: CGRect(x: 32, y: 32, width: 64, height: 64),
            cellSize: 4
        )
        // Face covering the left half; left eye over the detailed patch, right eye over flat gray.
        let face = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: CGPoint(x: 0.25, y: 0.25),
            rightEyeCenter: CGPoint(x: 0.75, y: 0.75)
        )
        let provider = FaceExpressionEvaluationProvider(analyzer: FakeFaceExpressionAnalyzer(faces: [face]))

        let signals = try provider.evaluate(assetID: AssetID(rawValue: "asset-1"), previewURL: previewURL)

        XCTAssertEqual(signals.map(\.kind), [.eyesOpen, .smile, .eyeSharpness])
        guard case .score(let sharpness)? = signals.last?.value else {
            return XCTFail("expected eye sharpness score")
        }
        // Sharpest eye per face: the checkerboard eye wins over the flat eye.
        XCTAssertGreaterThan(sharpness, 0.2)
        XCTAssertEqual(signals.last?.confidence, 0.6)
    }

    func testEyeSharpnessTakesWeakestFacePerPhoto() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "face-expression-eye-sharpness-min")
        let previewURL = directory.appendingPathComponent("preview.png")
        try writeEyePatchPNG(
            to: previewURL,
            width: 256,
            height: 256,
            patch: CGRect(x: 32, y: 32, width: 64, height: 64),
            cellSize: 4
        )
        let sharpFace = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: CGPoint(x: 0.25, y: 0.25),
            rightEyeCenter: nil
        )
        let softFace = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: CGPoint(x: 0.75, y: 0.75),
            rightEyeCenter: nil
        )
        let provider = FaceExpressionEvaluationProvider(
            analyzer: FakeFaceExpressionAnalyzer(faces: [sharpFace, softFace])
        )

        let signals = try provider.evaluate(assetID: AssetID(rawValue: "asset-1"), previewURL: previewURL)

        guard case .score(let sharpness)? = signals.last?.value else {
            return XCTFail("expected eye sharpness score")
        }
        // Photo score is the minimum across faces: the flat-eyed face drags it down.
        XCTAssertLessThan(sharpness, 0.05)
    }

    func testEyeSharpnessSkipsCropsSmallerThanMinimumPixels() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "face-expression-eye-sharpness-small")
        let previewURL = directory.appendingPathComponent("preview.png")
        try writeEyePatchPNG(
            to: previewURL,
            width: 256,
            height: 256,
            patch: CGRect(x: 32, y: 32, width: 64, height: 64),
            cellSize: 4
        )
        // 0.25 * 0.1 * 256 = 6.4 px crop side, below the 8 px floor.
        let tinyFace = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: CGPoint(x: 0.25, y: 0.25),
            rightEyeCenter: nil
        )
        let provider = FaceExpressionEvaluationProvider(analyzer: FakeFaceExpressionAnalyzer(faces: [tinyFace]))

        let signals = try provider.evaluate(assetID: AssetID(rawValue: "asset-1"), previewURL: previewURL)

        XCTAssertEqual(signals.map(\.kind), [.eyesOpen, .smile])
    }

    func testCoreImageAnalyzerFindsNoFacesInFacelessImage() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "core-image-face-analyzer")
        let previewURL = directory.appendingPathComponent("preview.jpg")
        try TestDirectories.writeTestJPEG(to: previewURL, width: 512, height: 340)

        XCTAssertEqual(try CoreImageFaceExpressionAnalyzer().detectFaces(previewURL: previewURL), [])
    }
}

struct FakeFaceExpressionAnalyzer: FaceExpressionAnalyzing {
    var faces: [DetectedFaceExpression]

    func detectFaces(previewURL: URL) throws -> [DetectedFaceExpression] {
        faces
    }
}

private func writeEyePatchPNG(to url: URL, width: Int, height: Int, patch: CGRect, cellSize: Int) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TeststripError.io("could not create test bitmap context")
    }
    context.setFillColor(CGColor(gray: 0.5, alpha: 1.0))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // CGContext draws with a bottom-left origin; `patch` is specified top-left.
    let flippedPatchMinY = Double(height) - patch.maxY
    for y in stride(from: 0, to: Int(patch.height), by: cellSize) {
        for x in stride(from: 0, to: Int(patch.width), by: cellSize) {
            let isLight = ((x / cellSize) + (y / cellSize)).isMultiple(of: 2)
            context.setFillColor(CGColor(gray: isLight ? 1.0 : 0.0, alpha: 1.0))
            context.fill(CGRect(
                x: patch.minX + Double(x),
                y: flippedPatchMinY + Double(y),
                width: Double(cellSize),
                height: Double(cellSize)
            ))
        }
    }
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw TeststripError.io("could not create test png")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TeststripError.io("could not write test png")
    }
}
