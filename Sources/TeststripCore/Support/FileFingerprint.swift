import Foundation

public struct FileFingerprint: Codable, Equatable, Sendable {
    public var size: Int64
    public var modificationDate: Date
    public var contentHash: String?

    public init(size: Int64, modificationDate: Date, contentHash: String? = nil) {
        self.size = size
        self.modificationDate = modificationDate
        self.contentHash = contentHash
    }
}
