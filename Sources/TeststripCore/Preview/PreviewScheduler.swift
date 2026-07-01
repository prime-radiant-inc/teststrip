public enum PreviewContext: Equatable, Sendable {
    case grid(distanceFromViewport: Int)
    case loupe(isVisible: Bool, requestedFullResolution: Bool)
    case timeline
}

public enum PreviewPriority: Int, Codable, Sendable {
    case visible = 0
    case nearby = 1
    case background = 2
}

public struct PreviewRequest: Equatable, Sendable {
    public var assetID: AssetID
    public var level: PreviewLevel
    public var priority: PreviewPriority

    public init(assetID: AssetID, level: PreviewLevel, priority: PreviewPriority) {
        self.assetID = assetID
        self.level = level
        self.priority = priority
    }
}

public struct PreviewScheduler: Sendable {
    public init() {}

    public func request(assetID: AssetID, context: PreviewContext) -> PreviewRequest {
        switch context {
        case .timeline:
            return PreviewRequest(assetID: assetID, level: .micro, priority: .background)
        case .grid(let distance):
            let priority: PreviewPriority = distance <= 0 ? .visible : (distance <= 24 ? .nearby : .background)
            return PreviewRequest(assetID: assetID, level: .grid, priority: priority)
        case .loupe(let isVisible, let requestedFullResolution):
            return PreviewRequest(
                assetID: assetID,
                level: requestedFullResolution ? .original : .large,
                priority: isVisible ? .visible : .nearby
            )
        }
    }
}
