import Foundation

public struct SourceAvailabilityProbe: Sendable {
    public init() {}

    public func availability(for asset: Asset) -> SourceAvailability {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: asset.originalURL.path) else {
            if let volumeRoot = Self.volumeRoot(for: asset.originalURL),
               !FileManager.default.fileExists(atPath: volumeRoot.path) {
                return .offline
            }
            return .missing
        }

        let currentSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let currentModificationDate = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        let currentFingerprint = FileFingerprint(size: currentSize, modificationDate: currentModificationDate)
        if !asset.fingerprint.matches(currentFingerprint) {
            return .stale
        }
        return .online
    }

    private static func volumeRoot(for url: URL) -> URL? {
        let components = url.standardizedFileURL.pathComponents
        guard components.count >= 3, components[0] == "/", components[1] == "Volumes" else {
            return nil
        }
        return URL(fileURLWithPath: "/Volumes/\(components[2])", isDirectory: true)
    }
}
