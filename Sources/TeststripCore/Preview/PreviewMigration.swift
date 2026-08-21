import Foundation

public enum PreviewMigration {
    /// Delete old JPEG preview files from the preview cache root.
    /// Called once at launch after the HEIC migration to clean up
    /// legacy `.jpg`/`.jpeg` files from the old per-level preview system.
    public static func deleteExistingJPEGPreviews(in cache: PreviewCache) throws {
        let root = cache.root
        guard FileManager.default.fileExists(atPath: root.path) else { return }

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        guard let enumerator else { return }

        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            if ext == "jpg" || ext == "jpeg" {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Reset the preview generation queue: clear all entries and re-queue
    /// one item per physical file for every cataloged asset.
    /// Levels: `.grid` (serves micro+grid), `.large` (serves medium+large),
    /// `.original` (serves original).
    public static func resetPreviewGenerationQueue(repository: CatalogRepository) throws {
        try repository.resetAllPreviewGenerationQueue()
    }
}
