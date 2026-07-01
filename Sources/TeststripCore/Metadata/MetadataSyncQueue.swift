import Foundation

public struct MetadataSyncItem: Codable, Equatable, Sendable {
    public var assetID: AssetID
    public var sidecarURL: URL
    public var catalogGeneration: Int
    public var lastSyncedFingerprint: String?

    public init(assetID: AssetID, sidecarURL: URL, catalogGeneration: Int, lastSyncedFingerprint: String?) {
        self.assetID = assetID
        self.sidecarURL = sidecarURL
        self.catalogGeneration = catalogGeneration
        self.lastSyncedFingerprint = lastSyncedFingerprint
    }
}
