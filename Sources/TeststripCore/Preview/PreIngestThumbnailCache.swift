import CryptoKit
import Foundation

/// Temporary thumbnail cache for pre-ingest selection review.
/// Keyed by source file path; stores JPEGs in a temp directory.
/// After import, thumbnails can be promoted to the permanent
/// PreviewCache, avoiding re-rendering.
public struct PreIngestThumbnailCache: Sendable, Equatable {
    public let directoryURL: URL

    public static func == (lhs: PreIngestThumbnailCache, rhs: PreIngestThumbnailCache) -> Bool {
        lhs.directoryURL == rhs.directoryURL
    }

    public init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            self.directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("teststrip-pre-ingest-\(UUID().uuidString)")
        }
        try? FileManager.default.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
    }

    public func thumbnailURL(for sourceURL: URL) -> URL {
        let hash = SHA256.hash(data: Data(sourceURL.path.utf8))
        let safeName = hash.map { String(format: "%02x", $0) }.joined()
        return directoryURL.appendingPathComponent(safeName + ".jpg")
    }

    public func thumbnailExists(for sourceURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: thumbnailURL(for: sourceURL).path)
    }

    public func storeThumbnail(_ data: Data, for sourceURL: URL) throws {
        try data.write(to: thumbnailURL(for: sourceURL))
    }

    public func thumbnailData(for sourceURL: URL) -> Data? {
        let url = thumbnailURL(for: sourceURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Copy a temp thumbnail to a permanent PreviewCache location.
    /// No-op when no temp thumbnail exists for the source URL.
    public func promote(from sourceURL: URL, to destinationURL: URL) throws {
        let src = thumbnailURL(for: sourceURL)
        guard FileManager.default.fileExists(atPath: src.path) else { return }
        try? FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: src, to: destinationURL)
    }

    public func cleanup() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
