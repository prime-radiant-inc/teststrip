import Foundation

public struct MetadataSyncItem: Codable, Equatable, Sendable {
    public var assetID: AssetID
    public var sidecarURL: URL
    public var catalogGeneration: Int
    public var lastSyncedFingerprint: String?
    public var lastSyncedAt: Date?

    public init(
        assetID: AssetID,
        sidecarURL: URL,
        catalogGeneration: Int,
        lastSyncedFingerprint: String?,
        lastSyncedAt: Date? = nil
    ) {
        self.assetID = assetID
        self.sidecarURL = sidecarURL
        self.catalogGeneration = catalogGeneration
        self.lastSyncedFingerprint = lastSyncedFingerprint
        self.lastSyncedAt = lastSyncedAt
    }
}
