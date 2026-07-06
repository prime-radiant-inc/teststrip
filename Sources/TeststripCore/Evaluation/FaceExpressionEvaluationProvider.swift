import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// One face found by the expression detector. All coordinates are normalized
/// to [0, 1] with a top-left origin so preview pixel math is size-independent.
public struct DetectedFaceExpression: Equatable, Sendable {
    public var normalizedBounds: CGRect
    public var hasSmile: Bool
    public var leftEyeClosed: Bool
    public var rightEyeClosed: Bool
    /// Eye centers; nil when the detector could not locate that eye.
    public var leftEyeCenter: CGPoint?
    public var rightEyeCenter: CGPoint?

    public init(
        normalizedBounds: CGRect,
        hasSmile: Bool,
        leftEyeClosed: Bool,
        rightEyeClosed: Bool,
        leftEyeCenter: CGPoint?,
        rightEyeCenter: CGPoint?
    ) {
        self.normalizedBounds = normalizedBounds
        self.hasSmile = hasSmile
        self.leftEyeClosed = leftEyeClosed
        self.rightEyeClosed = rightEyeClosed
        self.leftEyeCenter = leftEyeCenter
        self.rightEyeCenter = rightEyeCenter
    }

    var hasBothEyesOpen: Bool {
        !leftEyeClosed && !rightEyeClosed
    }
}

public protocol FaceExpressionAnalyzing: Sendable {
    func detectFaces(previewURL: URL) throws -> [DetectedFaceExpression]
}

/// Per-photo smile and eye-state culling signals aggregated from per-face
/// expression detection over the cached preview.
public struct FaceExpressionEvaluationProvider: EvaluationProvider {
    public let name = "core-image-faces"

    private let analyzer: any FaceExpressionAnalyzing

    public init(analyzer: any FaceExpressionAnalyzing = CoreImageFaceExpressionAnalyzer()) {
        self.analyzer = analyzer
    }

    public func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        let faces = try analyzer.detectFaces(previewURL: previewURL)
        guard !faces.isEmpty else { return [] }
        // Version 2: eyeSharpness is on the calibrated 0-1 focus scale rather
        // than the raw ~0.04-0.15 luminance-delta scale of version 1.
        let provenance = ProviderProvenance(provider: name, model: "CIDetectorFace", version: "2", settingsHash: "default")
        let faceCount = Double(faces.count)
        let eyesOpenFraction = Double(faces.filter(\.hasBothEyesOpen).count) / faceCount
        let smileFraction = Double(faces.filter(\.hasSmile).count) / faceCount
        var signals = [
            EvaluationSignal(
                assetID: assetID,
                kind: .eyesOpen,
                value: .score(eyesOpenFraction),
                confidence: 0.7,
                provenance: provenance
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .smile,
                value: .score(smileFraction),
                confidence: 0.7,
                provenance: provenance
            )
        ]
        if let eyeSharpness = try Self.eyeSharpnessScore(previewURL: previewURL, faces: faces) {
            signals.append(EvaluationSignal(
                assetID: assetID,
                kind: .eyeSharpness,
                value: .score(eyeSharpness),
                confidence: 0.6,
                provenance: provenance
            ))
        }
        return signals
    }

    /// Eye crops are squares of `eyeCropFractionOfFaceWidth` x face width centered
    /// on each detected eye; crops under `minimumEyeCropPixels` are skipped so
    /// tiny previews do not produce noise scores.
    private static let eyeCropFractionOfFaceWidth = 0.25
    private static let minimumEyeCropPixels = 8
    private static let sampleSize = 16

    private static func eyeSharpnessScore(previewURL: URL, faces: [DetectedFaceExpression]) throws -> Double? {
        let facesWithEyes = faces.filter { $0.leftEyeCenter != nil || $0.rightEyeCenter != nil }
        guard !facesWithEyes.isEmpty else { return nil }
        guard let source = CGImageSourceCreateWithURL(previewURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TeststripError.unsupportedFormat("ImageIO could not read \(previewURL.lastPathComponent)")
        }
        var perFaceScores: [Double] = []
        for face in facesWithEyes {
            var eyeScores: [Double] = []
            for eyeCenter in [face.leftEyeCenter, face.rightEyeCenter].compactMap({ $0 }) {
                guard let crop = eyeCrop(of: image, face: face, eyeCenter: eyeCenter) else { continue }
                let pixels = try PreviewPixelMetrics.rgbaSamples(of: crop, width: sampleSize, height: sampleSize)
                eyeScores.append(PreviewPixelMetrics.focusScore(in: pixels, width: sampleSize, height: sampleSize))
            }
            if let sharpestEye = eyeScores.max() {
                perFaceScores.append(sharpestEye)
            }
        }
        // A photo's eyes are only as sharp as its weakest subject's best eye.
        return perFaceScores.min()
    }

    private static func eyeCrop(of image: CGImage, face: DetectedFaceExpression, eyeCenter: CGPoint) -> CGImage? {
        let imageWidth = Double(image.width)
        let imageHeight = Double(image.height)
        let side = (eyeCropFractionOfFaceWidth * face.normalizedBounds.width * imageWidth).rounded()
        guard side >= Double(minimumEyeCropPixels) else { return nil }
        let cropRect = CGRect(
            x: (eyeCenter.x * imageWidth - side / 2).rounded(),
            y: (eyeCenter.y * imageHeight - side / 2).rounded(),
            width: side,
            height: side
        ).intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        guard cropRect.width >= Double(minimumEyeCropPixels),
              cropRect.height >= Double(minimumEyeCropPixels) else {
            return nil
        }
        return image.cropping(to: cropRect)
    }
}

/// Stock face expression detection via CoreImage's CIDetector with the
/// smile and eye-blink options. Chosen over Vision landmarks because it is
/// the only stock per-face smile source and supplies blink booleans and eye
/// positions from the same face set in one pass.
public struct CoreImageFaceExpressionAnalyzer: FaceExpressionAnalyzing {
    public init() {}

    public func detectFaces(previewURL: URL) throws -> [DetectedFaceExpression] {
        guard let image = CIImage(contentsOf: previewURL) else {
            throw TeststripError.unsupportedFormat("CoreImage could not read \(previewURL.lastPathComponent)")
        }
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            throw TeststripError.unsupportedFormat("empty image extent for \(previewURL.lastPathComponent)")
        }
        guard let detector = CIDetector(
            ofType: CIDetectorTypeFace,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ) else {
            throw TeststripError.invalidState("could not create CoreImage face detector")
        }
        return detector
            .features(in: image, options: [CIDetectorSmile: true, CIDetectorEyeBlink: true])
            .compactMap { $0 as? CIFaceFeature }
            .map { face in
                DetectedFaceExpression(
                    normalizedBounds: Self.normalizedTopLeftRect(face.bounds, in: extent),
                    hasSmile: face.hasSmile,
                    leftEyeClosed: face.leftEyeClosed,
                    rightEyeClosed: face.rightEyeClosed,
                    leftEyeCenter: face.hasLeftEyePosition
                        ? Self.normalizedTopLeftPoint(face.leftEyePosition, in: extent)
                        : nil,
                    rightEyeCenter: face.hasRightEyePosition
                        ? Self.normalizedTopLeftPoint(face.rightEyePosition, in: extent)
                        : nil
                )
            }
    }

    /// CoreImage geometry is bottom-left origin in pixels; signals consume
    /// normalized top-left coordinates, so normalize and flip Y.
    private static func normalizedTopLeftRect(_ rect: CGRect, in extent: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - extent.minX) / extent.width,
            y: 1.0 - (rect.maxY - extent.minY) / extent.height,
            width: rect.width / extent.width,
            height: rect.height / extent.height
        )
    }

    private static func normalizedTopLeftPoint(_ point: CGPoint, in extent: CGRect) -> CGPoint {
        CGPoint(
            x: (point.x - extent.minX) / extent.width,
            y: 1.0 - (point.y - extent.minY) / extent.height
        )
    }
}
