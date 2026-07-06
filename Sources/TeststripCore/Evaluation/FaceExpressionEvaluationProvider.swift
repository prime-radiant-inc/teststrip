import CoreGraphics
import Foundation

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

    public init(analyzer: any FaceExpressionAnalyzing) {
        self.analyzer = analyzer
    }

    public func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        let faces = try analyzer.detectFaces(previewURL: previewURL)
        guard !faces.isEmpty else { return [] }
        let provenance = ProviderProvenance(provider: name, model: "CIDetectorFace", version: "1", settingsHash: "default")
        let faceCount = Double(faces.count)
        let eyesOpenFraction = Double(faces.filter(\.hasBothEyesOpen).count) / faceCount
        let smileFraction = Double(faces.filter(\.hasSmile).count) / faceCount
        return [
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
    }
}
