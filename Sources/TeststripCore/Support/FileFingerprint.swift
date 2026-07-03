import Foundation

public struct FileFingerprint: Codable, Equatable, Sendable {
    private static let modificationDateTolerance: TimeInterval = 0.001

    public var size: Int64
    public var modificationDate: Date
    public var contentHash: String?

    public init(size: Int64, modificationDate: Date, contentHash: String? = nil) {
        self.size = size
        self.modificationDate = modificationDate
        self.contentHash = contentHash
    }

    public func matches(_ other: FileFingerprint) -> Bool {
        guard size == other.size else {
            return false
        }
        if let contentHash, let otherContentHash = other.contentHash, contentHash != otherContentHash {
            return false
        }
        return abs(modificationDate.timeIntervalSince(other.modificationDate)) <= Self.modificationDateTolerance
    }
}
