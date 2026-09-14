import XCTest
@testable import TeststripCore

final class PreIngestThumbnailCacheTests: XCTestCase {
    func testStoreAndCheckExistence() throws {
        let cache = PreIngestThumbnailCache(directoryURL: makeTempDir())
        let sourceURL = URL(fileURLWithPath: "/tmp/test/photo.jpg")
        let thumbnailData = Data([0xFF, 0xD8, 0xFF]) // JPEG magic bytes
        
        XCTAssertFalse(cache.thumbnailExists(for: sourceURL))
        try cache.storeThumbnail(thumbnailData, for: sourceURL)
        XCTAssertTrue(cache.thumbnailExists(for: sourceURL))
        cache.cleanup()
    }
    
    func testCleanupRemovesDirectory() throws {
        let dir = makeTempDir()
        let cache = PreIngestThumbnailCache(directoryURL: dir)
        try cache.storeThumbnail(Data([0xFF]), for: URL(fileURLWithPath: "/tmp/x.jpg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        cache.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
    
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("thumb-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
