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
    
    func testPromoteCopiesToDestination() throws {
        let cache = PreIngestThumbnailCache(directoryURL: makeTempDir())
        let sourceURL = URL(fileURLWithPath: "/tmp/test/photo.jpg")
        let thumbnailData = Data([0xFF, 0xD8, 0xFF])
        try cache.storeThumbnail(thumbnailData, for: sourceURL)
        
        let destDir = makeTempDir()
        let destURL = destDir.appendingPathComponent("micro.jpg")
        try cache.promote(from: sourceURL, to: destURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
        let promoted = try Data(contentsOf: destURL)
        XCTAssertEqual(promoted, thumbnailData)
        cache.cleanup()
    }
    
    func testPromoteNoopWhenThumbnailMissing() throws {
        let cache = PreIngestThumbnailCache(directoryURL: makeTempDir())
        let destURL = makeTempDir().appendingPathComponent("micro.jpg")
        try cache.promote(from: URL(fileURLWithPath: "/nonexistent.jpg"), to: destURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destURL.path))
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
