import Foundation

public struct SourceAvailabilityProbe: Sendable {
    private static let modificationDateTolerance: TimeInterval = 0.001

    public init() {}

    public func availability(for asset: Asset) -> SourceAvailability {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: asset.originalURL.path) else {
            return .missing
        }

        let currentSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let currentModificationDate = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        let modificationDateDelta = abs(currentModificationDate.timeIntervalSince(asset.fingerprint.modificationDate))
        if currentSize != asset.fingerprint.size || modificationDateDelta > Self.modificationDateTolerance {
            return .stale
        }
        return .online
    }
}
