import Foundation
import ImageIO
import Vision

public struct AppleVisionLabel: Equatable, Sendable {
    public var identifier: String
    public var confidence: Double

    public init(identifier: String, confidence: Double) {
        self.identifier = identifier
        self.confidence = confidence
    }
}

public struct AppleVisionFaceObservation: Equatable, Sendable {
    public var boundingBox: FaceBoundingBox
    public var captureQuality: Double?
    public var featurePrintVector: [Double]

    public init(boundingBox: FaceBoundingBox, captureQuality: Double?, featurePrintVector: [Double]) {
        self.boundingBox = boundingBox
        self.captureQuality = captureQuality
        self.featurePrintVector = featurePrintVector
    }
}

public struct AppleVisionAnalysis: Equatable, Sendable {
    public var faceCount: Int
    public var faceQualityScores: [Double]
    public var recognizedText: [String]
    public var classificationLabels: [AppleVisionLabel]
    public var imageFeaturePrintVector: [Double]
    public var faces: [AppleVisionFaceObservation]

    public init(
        faceCount: Int,
        faceQualityScores: [Double],
        recognizedText: [String],
        classificationLabels: [AppleVisionLabel],
        imageFeaturePrintVector: [Double] = [],
        faces: [AppleVisionFaceObservation] = []
    ) {
        self.faceCount = faceCount
        self.faceQualityScores = faceQualityScores
        self.recognizedText = recognizedText
        self.classificationLabels = classificationLabels
        self.imageFeaturePrintVector = imageFeaturePrintVector
        self.faces = faces
    }
}

public protocol AppleVisionAnalyzing: Sendable {
    func analyze(previewURL: URL) throws -> AppleVisionAnalysis
}

public struct AppleVisionEvaluationProvider: EvaluationProvider {
    public let name = "apple-vision"

    private let analyzer: any AppleVisionAnalyzing
    private let faceEmbedder: FaceRecognitionEmbedder?

    /// The bundled face-identity embedder (AuraFace-v1, Apache-2.0), compiled
    /// once per process. Nil when the model has not been downloaded.
    public static let sharedFaceEmbedder: FaceRecognitionEmbedder? =
        CoreMLFaceEmbeddingModel.auraFace().map { FaceRecognitionEmbedder(model: $0) }

    public init(
        analyzer: any AppleVisionAnalyzing = AppleVisionAnalyzer(),
        faceEmbedder: FaceRecognitionEmbedder? = AppleVisionEvaluationProvider.sharedFaceEmbedder
    ) {
        self.analyzer = analyzer
        self.faceEmbedder = faceEmbedder
    }

    public func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        try evaluateWithFaces(assetID: assetID, previewURL: previewURL).signals
    }

    private static func signals(assetID: AssetID, analysis: AppleVisionAnalysis) -> [EvaluationSignal] {
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        var signals: [EvaluationSignal] = []

        if let faceCountSignal = Self.faceCountSignal(assetID: assetID, count: analysis.faceCount, scores: analysis.faceQualityScores, provenance: provenance) {
            signals.append(faceCountSignal)
        }
        if let faceSignal = Self.faceSignal(assetID: assetID, scores: analysis.faceQualityScores, provenance: provenance) {
            signals.append(faceSignal)
        }
        if let textSignal = Self.textSignal(assetID: assetID, text: analysis.recognizedText, provenance: provenance) {
            signals.append(textSignal)
        }
        if let objectSignal = Self.objectSignal(assetID: assetID, labels: analysis.classificationLabels, provenance: provenance) {
            signals.append(objectSignal)
        }
        if let imageSimilaritySignal = Self.imageSimilaritySignal(assetID: assetID, vector: analysis.imageFeaturePrintVector, provenance: provenance) {
            signals.append(imageSimilaritySignal)
        }

        return signals
    }

    private static func faceCountSignal(
        assetID: AssetID,
        count: Int,
        scores: [Double],
        provenance: ProviderProvenance
    ) -> EvaluationSignal? {
        guard count > 0 else { return nil }
        let boundedScores = scores.map { min(max($0, 0.0), 1.0) }
        return EvaluationSignal(
            assetID: assetID,
            kind: .faceCount,
            value: .count(count),
            confidence: boundedScores.max() ?? 1.0,
            provenance: provenance
        )
    }

    private static func faceSignal(
        assetID: AssetID,
        scores: [Double],
        provenance: ProviderProvenance
    ) -> EvaluationSignal? {
        guard !scores.isEmpty else { return nil }
        let boundedScores = scores.map { min(max($0, 0.0), 1.0) }
        let averageScore = boundedScores.reduce(0.0, +) / Double(boundedScores.count)
        return EvaluationSignal(
            assetID: assetID,
            kind: .faceQuality,
            value: .score(averageScore),
            confidence: boundedScores.max() ?? averageScore,
            provenance: provenance
        )
    }

    private static func textSignal(
        assetID: AssetID,
        text: [String],
        provenance: ProviderProvenance
    ) -> EvaluationSignal? {
        let lines = text
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        return EvaluationSignal(
            assetID: assetID,
            kind: .ocrText,
            value: .text(lines.joined(separator: "\n")),
            confidence: 1.0,
            provenance: provenance
        )
    }

    private static func objectSignal(
        assetID: AssetID,
        labels: [AppleVisionLabel],
        provenance: ProviderProvenance
    ) -> EvaluationSignal? {
        let rankedLabels = labels.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return lhs.identifier.localizedCaseInsensitiveCompare(rhs.identifier) == .orderedAscending
        }
        guard let topLabel = rankedLabels.first else { return nil }
        let identifiers = rankedLabels.map(\.identifier)
        return EvaluationSignal(
            assetID: assetID,
            kind: .object,
            value: identifiers.count == 1 ? .label(topLabel.identifier) : .labels(identifiers),
            confidence: min(max(topLabel.confidence, 0.0), 1.0),
            provenance: provenance
        )
    }

    private static func imageSimilaritySignal(
        assetID: AssetID,
        vector: [Double],
        provenance: ProviderProvenance
    ) -> EvaluationSignal? {
        guard !vector.isEmpty else { return nil }
        return EvaluationSignal(
            assetID: assetID,
            kind: .visualSimilarity,
            value: .vector(vector),
            confidence: 1.0,
            provenance: provenance
        )
    }
}

extension AppleVisionEvaluationProvider: FaceObservationEvaluationProvider {
    // Face observations carry AuraFace-v1 identity embeddings; reads filter to
    // this provenance so older feature-print observations are inert.
    public static let faceProvenance = ProviderProvenance(
        provider: "face-recognition",
        model: "auraface-v1",
        version: "1",
        settingsHash: "default"
    )

    public var faceProvenance: ProviderProvenance {
        Self.faceProvenance
    }

    public func evaluateWithFaces(assetID: AssetID, previewURL: URL) throws -> FaceEvaluationOutcome {
        let analysis = try analyzer.analyze(previewURL: previewURL)
        return FaceEvaluationOutcome(
            signals: Self.signals(assetID: assetID, analysis: analysis),
            faceObservations: faceObservations(assetID: assetID, previewURL: previewURL)
        )
    }

    private func faceObservations(assetID: AssetID, previewURL: URL) -> [CatalogFaceObservation] {
        guard let faceEmbedder else {
            // Model absent: detection/quality/other signals continue; no
            // identity embeddings are produced.
            return []
        }
        guard let source = CGImageSourceCreateWithURL(previewURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return []
        }
        guard let observations = try? faceEmbedder.faceObservations(in: image) else {
            return []
        }
        return observations.enumerated().map { index, face in
            CatalogFaceObservation(
                assetID: assetID,
                faceIndex: index,
                boundingBox: face.boundingBox,
                captureQuality: face.captureQuality,
                embedding: face.featurePrintVector,
                provenance: Self.faceProvenance
            )
        }
    }
}

public struct AppleVisionAnalyzer: AppleVisionAnalyzing {
    public static let faceCropPadding = 0.25

    /// Pinned feature-print revision. Feature prints from different revisions
    /// have different lengths and are not distance-comparable, so the revision
    /// must never follow the SDK default: an Xcode/SDK update would otherwise
    /// silently mix vector dimensions under one provenance.
    public static let featurePrintRevision = VNGenerateImageFeaturePrintRequestRevision2

    public static func makeFeaturePrintRequest() -> VNGenerateImageFeaturePrintRequest {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = featurePrintRevision
        return request
    }

    public static func paddedRegionOfInterest(_ box: FaceBoundingBox, padding: Double = faceCropPadding) -> CGRect {
        guard box.width > 0, box.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let inset = padding * max(box.width, box.height)
        let minX = max(0.0, box.x - inset)
        let minY = max(0.0, box.y - inset)
        let maxX = min(1.0, box.x + box.width + inset)
        let maxY = min(1.0, box.y + box.height + inset)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public init() {}

    public func analyze(previewURL: URL) throws -> AppleVisionAnalysis {
        let faceQualityRequest = VNDetectFaceCaptureQualityRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        let classificationRequest = VNClassifyImageRequest()
        let imageFeaturePrintRequest = Self.makeFeaturePrintRequest()

        let handler = VNImageRequestHandler(url: previewURL, options: [:])
        try handler.perform([faceQualityRequest, textRequest, classificationRequest, imageFeaturePrintRequest])

        let faceResults = faceQualityRequest.results ?? []
        // Face identity embeddings come from the ArcFace embedder in
        // evaluateWithFaces; the analyzer only reports detection geometry and
        // capture quality here (no whole-image feature print per face).
        let faces = faceResults.map { observation in
            AppleVisionFaceObservation(
                boundingBox: FaceBoundingBox(
                    x: Double(observation.boundingBox.origin.x),
                    y: Double(observation.boundingBox.origin.y),
                    width: Double(observation.boundingBox.width),
                    height: Double(observation.boundingBox.height)
                ),
                captureQuality: observation.faceCaptureQuality.map(Double.init),
                featurePrintVector: []
            )
        }

        return AppleVisionAnalysis(
            faceCount: faceResults.count,
            faceQualityScores: faceResults.compactMap { observation in
                observation.faceCaptureQuality.map(Double.init)
            },
            recognizedText: (textRequest.results ?? []).compactMap { observation in
                observation.topCandidates(1).first?.string
            },
            classificationLabels: (classificationRequest.results ?? [])
                // VNClassifyImageRequest scores Apple's full ~1,300-label
                // taxonomy; confidence > 0 keeps ~100+ noise labels per photo.
                // The precision/recall filter is Apple's intended way to keep
                // only the labels that actually describe the image.
                .filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
                .map { AppleVisionLabel(identifier: $0.identifier, confidence: Double($0.confidence)) },
            imageFeaturePrintVector: Self.imageFeaturePrintVector(from: imageFeaturePrintRequest.results?.first),
            faces: faces
        )
    }

    private static func imageFeaturePrintVector(from observation: VNFeaturePrintObservation?) -> [Double] {
        guard let observation,
              observation.elementType == .float else {
            return []
        }
        return observation.data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self).prefix(observation.elementCount)).map(Double.init)
        }
    }
}
