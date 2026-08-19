import Foundation
import Vision
import CoreImage

public struct AppleOrientationEvaluationProvider: OrientationEvaluationProvider, Sendable {
    public let name = "orientation"

    public init() {}

    public func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        []
    }

    public func evaluateWithOrientation(assetID: AssetID, previewURL: URL) throws -> OrientationEvaluationOutcome {
        guard let cgImage = loadCGImage(from: previewURL) else {
            throw TeststripError.invalidState("could not load preview image for orientation detection")
        }

        let faceRotation = detectFaceRotation(from: cgImage)
        if let rotation = faceRotation {
            return OrientationEvaluationOutcome(rotation: rotation)
        }

        let horizonRotation = detectHorizonRotation(from: cgImage)
        if let rotation = horizonRotation {
            return OrientationEvaluationOutcome(rotation: rotation)
        }

        return OrientationEvaluationOutcome(rotation: nil)
    }

    /// Quantizes an arbitrary angle to the nearest 90° increment, returning nil
    /// when the angle is within the dead zone (near 0°/360° — photo looks correct).
    static func quantizeRotation(_ degrees: Double) -> Int? {
        let tolerance = 25.0
        let normalized = ((degrees.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        let candidates: [(target: Double, value: Int)] = [
            (0, 0), (90, 90), (180, 180), (270, 270), (360, 0)
        ]
        for candidate in candidates {
            if abs(normalized - candidate.target) <= tolerance {
                return candidate.value == 0 ? nil : candidate.value
            }
        }
        return nil
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func detectFaceRotation(from cgImage: CGImage) -> Int? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let results = request.results as? [VNFaceObservation], !results.isEmpty else {
            return nil
        }
        let rolls = results.compactMap { $0.roll?.doubleValue }
        guard let dominantRoll = rolls.first else { return nil }
        let degrees = dominantRoll * 180 / .pi
        return Self.quantizeRotation(-degrees)
    }

    private func detectHorizonRotation(from cgImage: CGImage) -> Int? {
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let result = request.results?.first else { return nil }
        let degrees = Double(result.angle) * 180 / .pi
        return Self.quantizeRotation(degrees)
    }
}
