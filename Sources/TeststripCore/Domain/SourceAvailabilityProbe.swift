import Foundation

public struct SourceAvailabilityProbe: Sendable {
    public init() {}

    public func availability(for asset: Asset) -> SourceAvailability {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: asset.originalURL.path) else {
            return .missing
        }

        let currentSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let currentModificationDate = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        if currentSize != asset.fingerprint.size || currentModificationDate != asset.fingerprint.modificationDate {
            return .stale
        }
        return .online
    }
}
