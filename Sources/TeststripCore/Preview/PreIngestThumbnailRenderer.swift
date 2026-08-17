import Foundation

/// Renders micro-level thumbnails into a PreIngestThumbnailCache for
/// the import selection window. Skips files that already have a cached
/// thumbnail. Uses concurrent rendering for batch operations.
public struct PreIngestThumbnailRenderer: Sendable {
    private let renderer: PreviewRenderer

    public init(renderer: PreviewRenderer = PreviewRenderer()) {
        self.renderer = renderer
    }

    /// Render a single thumbnail into the cache. Skips if already cached.
    public func render(sourceURL: URL, cache: PreIngestThumbnailCache) throws {
        guard !cache.thumbnailExists(for: sourceURL) else { return }
        let tempURL = cache.directoryURL
            .appendingPathComponent("rendering-\(UUID().uuidString).jpg")
        try renderer.render(sourceURL: sourceURL, level: .micro, destinationURL: tempURL)
        let finalURL = cache.thumbnailURL(for: sourceURL)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: finalURL)
    }

    /// Render thumbnails for multiple source files concurrently.
    /// Skips files that already have a cached thumbnail.
    public func renderBatch(
        _ sourceURLs: [URL],
        cache: PreIngestThumbnailCache,
        concurrency: Int = 4
    ) throws {
        let toRender = sourceURLs.filter { !cache.thumbnailExists(for: $0) }
        guard !toRender.isEmpty else { return }

        var renderErrors: [Error] = []
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: toRender.count) { index in
            let url = toRender[index]
            do {
                try render(sourceURL: url, cache: cache)
            } catch {
                lock.lock()
                renderErrors.append(error)
                lock.unlock()
            }
        }

        if let firstError = renderErrors.first {
            throw firstError
        }
    }
}
