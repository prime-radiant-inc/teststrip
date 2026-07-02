import Foundation

public struct AssetID: StableID {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct Asset: Codable, Equatable, Sendable {
    public var id: AssetID
    public var originalURL: URL
    public var volumeIdentifier: String?
    public var fingerprint: FileFingerprint
    public var availability: SourceAvailability
    public var metadata: AssetMetadata
    public var technicalMetadata: AssetTechnicalMetadata?

    public init(
        id: AssetID,
        originalURL: URL,
        volumeIdentifier: String?,
        fingerprint: FileFingerprint,
        availability: SourceAvailability,
        metadata: AssetMetadata,
        technicalMetadata: AssetTechnicalMetadata? = nil
    ) {
        self.id = id
        self.originalURL = originalURL
        self.volumeIdentifier = volumeIdentifier
        self.fingerprint = fingerprint
        self.availability = availability
        self.metadata = metadata
        self.technicalMetadata = technicalMetadata
    }
}
