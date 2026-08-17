import Foundation

/// Temporary thumbnail cache for pre-ingest selection review.
/// Keyed by source file path; stores JPEGs in a temp directory.
/// After import, thumbnails can be promoted to the permanent
/// PreviewCache, avoiding re-rendering.
public struct PreIngestThumbnailCache: Sendable {
    public let directoryURL: URL

    public init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            self.directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("teststrip-pre-ingest-\(UUID().uuidString)")
        }
        try? FileManager.default.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
    }

    private func thumbnailURL(for sourceURL: URL) -> URL {
        let safeName = sourceURL.path.replacingOccurrences(of: "/", with: "_")
        return directoryURL.appendingPathComponent(safeName + ".jpg")
    }

    public func thumbnailExists(for sourceURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: thumbnailURL(for: sourceURL).path)
    }

    public func storeThumbnail(_ data: Data, for sourceURL: URL) throws {
        try data.write(to: thumbnailURL(for: sourceURL))
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
