import Foundation

public struct PreviewGenerationItem: Equatable, Sendable {
    public var assetID: AssetID
    public var level: PreviewLevel

    public init(assetID: AssetID, level: PreviewLevel) {
        self.assetID = assetID
        self.level = level
    }
}

public struct PreviewGenerationQueueState: Equatable, Sendable {
    public var item: PreviewGenerationItem
    public var attemptCount: Int
    public var lastErrorMessage: String?
    public var lastAttemptedAt: Date?

    public init(
        item: PreviewGenerationItem,
        attemptCount: Int,
        lastErrorMessage: String? = nil,
        lastAttemptedAt: Date? = nil
    ) {
        self.item = item
        self.attemptCount = attemptCount
        self.lastErrorMessage = lastErrorMessage
        self.lastAttemptedAt = lastAttemptedAt
    }
}
