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

    public var maximumCaptureGap: TimeInterval

    public init(maximumCaptureGap: TimeInterval = Self.defaultMaximumCaptureGap) {
        self.maximumCaptureGap = maximumCaptureGap
    }

    public func stacks(from assets: [Asset]) -> [AssetStack] {
        guard !assets.isEmpty else { return [] }

        var stacks: [AssetStack] = []
        var currentStack: [Asset] = [assets[0]]

        for asset in assets.dropFirst() {
            guard let previousAsset = currentStack.last,
                  isStackNeighbor(previousAsset, asset) else {
                stacks.append(stack(from: currentStack))
                currentStack = [asset]
                continue
            }
            currentStack.append(asset)
        }

        stacks.append(stack(from: currentStack))
        return stacks
    }

    private func stack(from assets: [Asset]) -> AssetStack {
        AssetStack(
            assetIDs: assets.map(\.id),
            rationale: assets.count > 1 ? Self.burstRationale(maximumCaptureGap: maximumCaptureGap) : nil
        )
    }

    private func isStackNeighbor(_ first: Asset, _ second: Asset) -> Bool {
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

    private static func burstRationale(maximumCaptureGap: TimeInterval) -> String {
        let seconds = Int(maximumCaptureGap.rounded())
        return "Same folder, captured within \(seconds)s"
    }
}
