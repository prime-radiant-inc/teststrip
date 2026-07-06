import Foundation
import Vision

public struct AppleVisionLabel: Equatable, Sendable {
    public var identifier: String
    public var confidence: Double

    public init(identifier: String, confidence: Double) {
        self.identifier = identifier
        self.confidence = confidence
    }
}

public struct AppleVisionAnalysis: Equatable, Sendable {
    public var faceCount: Int
    public var faceQualityScores: [Double]
    public var recognizedText: [String]
    public var classificationLabels: [AppleVisionLabel]
    public var imageFeaturePrintVector: [Double]

    public init(
        faceCount: Int,
        faceQualityScores: [Double],
        recognizedText: [String],
        classificationLabels: [AppleVisionLabel],
        imageFeaturePrintVector: [Double] = []
    ) {
        self.faceCount = faceCount
        self.faceQualityScores = faceQualityScores
        self.recognizedText = recognizedText
        self.classificationLabels = classificationLabels
        self.imageFeaturePrintVector = imageFeaturePrintVector
    }
}

public protocol AppleVisionAnalyzing: Sendable {
    func analyze(previewURL: URL) throws -> AppleVisionAnalysis
}

public struct AppleVisionEvaluationProvider: EvaluationProvider {
    public let name = "apple-vision"

    private let analyzer: any AppleVisionAnalyzing

    public init(analyzer: any AppleVisionAnalyzing = AppleVisionAnalyzer()) {
        self.analyzer = analyzer
    }

    public func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        let analysis = try analyzer.analyze(previewURL: previewURL)
        let provenance = ProviderProvenance(provider: name, model: "Vision", version: "1", settingsHash: "default")
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
        guard let label = labels.max(by: { $0.confidence < $1.confidence }) else { return nil }
        return EvaluationSignal(
            assetID: assetID,
            kind: .object,
            value: .label(label.identifier),
            confidence: min(max(label.confidence, 0.0), 1.0),
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

public struct AppleVisionAnalyzer: AppleVisionAnalyzing {
    public init() {}

    public func analyze(previewURL: URL) throws -> AppleVisionAnalysis {
        let faceQualityRequest = VNDetectFaceCaptureQualityRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        let classificationRequest = VNClassifyImageRequest()
        let imageFeaturePrintRequest = VNGenerateImageFeaturePrintRequest()

        let handler = VNImageRequestHandler(url: previewURL, options: [:])
        try handler.perform([faceQualityRequest, textRequest, classificationRequest, imageFeaturePrintRequest])

        return AppleVisionAnalysis(
            faceCount: (faceQualityRequest.results ?? []).count,
            faceQualityScores: (faceQualityRequest.results ?? []).compactMap { observation in
                observation.faceCaptureQuality.map(Double.init)
            },
            recognizedText: (textRequest.results ?? []).compactMap { observation in
                observation.topCandidates(1).first?.string
            },
            classificationLabels: (classificationRequest.results ?? [])
                .filter { $0.confidence > 0 }
                .map { AppleVisionLabel(identifier: $0.identifier, confidence: Double($0.confidence)) },
            imageFeaturePrintVector: Self.imageFeaturePrintVector(from: imageFeaturePrintRequest.results?.first)
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
