import Foundation

public struct AssetStack: Codable, Equatable, Sendable {
    public var assetIDs: [AssetID]
    public var rationale: String?

    public init(assetIDs: [AssetID], rationale: String? = nil) {
        self.assetIDs = assetIDs
        self.rationale = rationale
    }
}

public struct AssetStackBuilder: Sendable {
    public static let defaultMaximumCaptureGap: TimeInterval = 2
    public static let defaultMaximumVisualSimilarityDistance = 0.05

    public var maximumCaptureGap: TimeInterval
    public var maximumVisualSimilarityDistance: Double

    public init(
        maximumCaptureGap: TimeInterval = Self.defaultMaximumCaptureGap,
        maximumVisualSimilarityDistance: Double = Self.defaultMaximumVisualSimilarityDistance
    ) {
        self.maximumCaptureGap = maximumCaptureGap
        self.maximumVisualSimilarityDistance = maximumVisualSimilarityDistance
    }

    public func stacks(
        from assets: [Asset],
        visualSimilarityVectorsByAssetID: [AssetID: [Double]] = [:]
    ) -> [AssetStack] {
        guard !assets.isEmpty else { return [] }

        var stacks: [AssetStack] = []
        var currentStack: [Asset] = [assets[0]]
        var currentRationale: String?

        for asset in assets.dropFirst() {
            guard let previousAsset = currentStack.last else {
                stacks.append(stack(from: currentStack, rationale: currentRationale))
                currentStack = [asset]
                currentRationale = nil
                continue
            }
            let rationale = stackRationale(
                first: previousAsset,
                second: asset,
                visualSimilarityVectorsByAssetID: visualSimilarityVectorsByAssetID
            )
            guard let rationale else {
                stacks.append(stack(from: currentStack, rationale: currentRationale))
                currentStack = [asset]
                currentRationale = nil
                continue
            }
            currentRationale = currentRationale ?? rationale
            currentStack.append(asset)
        }

        stacks.append(stack(from: currentStack, rationale: currentRationale))
        return stacks
    }

    private func stack(from assets: [Asset], rationale: String?) -> AssetStack {
        AssetStack(
            assetIDs: assets.map(\.id),
            rationale: assets.count > 1 ? rationale : nil
        )
    }

    private func stackRationale(
        first: Asset,
        second: Asset,
        visualSimilarityVectorsByAssetID: [AssetID: [Double]]
    ) -> String? {
        if isCaptureTimeNeighbor(first, second) {
            return Self.burstRationale(maximumCaptureGap: maximumCaptureGap)
        }
        if let distance = visualSimilarityDistance(first, second, visualSimilarityVectorsByAssetID: visualSimilarityVectorsByAssetID),
           distance <= maximumVisualSimilarityDistance {
            return Self.visualSimilarityRationale(
                distance: distance,
                maximumDistance: maximumVisualSimilarityDistance
            )
        }
        return nil
    }

    private func isCaptureTimeNeighbor(_ first: Asset, _ second: Asset) -> Bool {
        guard let firstCapture = first.technicalMetadata?.capturedAt,
              let secondCapture = second.technicalMetadata?.capturedAt else {
            return false
        }
        guard first.originalURL.deletingLastPathComponent().standardizedFileURL.path
            == second.originalURL.deletingLastPathComponent().standardizedFileURL.path else {
            return false
        }
        return abs(firstCapture.timeIntervalSince(secondCapture)) <= maximumCaptureGap
    }

    private func visualSimilarityDistance(
        _ first: Asset,
        _ second: Asset,
        visualSimilarityVectorsByAssetID: [AssetID: [Double]]
    ) -> Double? {
        guard let firstVector = visualSimilarityVectorsByAssetID[first.id],
              let secondVector = visualSimilarityVectorsByAssetID[second.id],
              firstVector.count == secondVector.count,
              !firstVector.isEmpty else {
            return nil
        }
        return zip(firstVector, secondVector)
            .map { lhs, rhs in
                let delta = lhs - rhs
                return delta * delta
            }
            .reduce(0.0) { partialResult, value in
                partialResult + value
            }
            .squareRoot()
    }

    private static func burstRationale(maximumCaptureGap: TimeInterval) -> String {
        let seconds = Int(maximumCaptureGap.rounded())
        return "Same folder, captured within \(seconds)s"
    }

    private static func visualSimilarityRationale(distance: Double, maximumDistance: Double) -> String {
        String(format: "Visual similarity distance %.3f <= %.3f", distance, maximumDistance)
    }
}
