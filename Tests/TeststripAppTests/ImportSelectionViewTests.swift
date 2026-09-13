import XCTest
import AppKit
@testable import TeststripApp
@testable import TeststripCore

final class ImportSelectionViewTests: XCTestCase {
    @MainActor
    func testFilterAllShowsAllEntries() {
        let entries = makeEntries(count: 5, duplicateIndices: [2])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [entries[2].url])
        model.filter = .all
        XCTAssertEqual(model.filteredEntries.count, 5)
    }

    @MainActor
    func testFilterNewOnlyExcludesDuplicates() {
        let entries = makeEntries(count: 5, duplicateIndices: [1, 3])
        let dupes = Set([entries[1].url, entries[3].url])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: dupes)
        model.filter = .newOnly
        XCTAssertEqual(model.filteredEntries.count, 3)
        XCTAssertFalse(model.filteredEntries.contains { $0.url == entries[1].url })
        XCTAssertFalse(model.filteredEntries.contains { $0.url == entries[3].url })
    }

    @MainActor
    func testFilterDuplicatesOnlyShowsDuplicates() {
        let entries = makeEntries(count: 5, duplicateIndices: [0, 4])
        let dupes = Set([entries[0].url, entries[4].url])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: dupes)
        model.filter = .duplicates
        XCTAssertEqual(model.filteredEntries.count, 2)
    }

    @MainActor
    func testSelectAll() {
        let entries = makeEntries(count: 5, duplicateIndices: [])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [])
        model.selectAll()
        XCTAssertEqual(model.selectedURLs.count, 5)
    }

    @MainActor
    func testSelectNone() {
        let entries = makeEntries(count: 5, duplicateIndices: [])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [])
        model.selectAll()
        model.selectNone()
        XCTAssertTrue(model.selectedURLs.isEmpty)
    }

    @MainActor
    func testDefaultDeselectsDuplicates() {
        let entries = makeEntries(count: 3, duplicateIndices: [1])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [entries[1].url])
        XCTAssertEqual(model.selectedURLs.count, 2, "duplicates should be deselected by default")
        XCTAssertFalse(model.selectedURLs.contains(entries[1].url), "duplicate should not be selected")
    }

    @MainActor
    func testSelectedCountAfterDeselect() {
        let entries = makeEntries(count: 5, duplicateIndices: [])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [])
        model.toggle(entries[0].url)
        XCTAssertEqual(model.selectedURLs.count, 4)
    }

    @MainActor
    func testLoadThumbnailPopulatesFromCacheWithoutRendering() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("selection-thumb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = PreIngestThumbnailCache(directoryURL: dir)
        let entries = makeEntries(count: 1, duplicateIndices: [])
        let url = entries[0].url
        try cache.storeThumbnail(try makeImageData(), for: url)
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [], thumbnailCache: cache)

        model.loadThumbnail(for: url)

        XCTAssertNotNil(model.thumbnails[url])
        XCTAssertFalse(model.isRendering)
    }

    @MainActor
    func testLoadThumbnailKeepsAlreadyLoadedImage() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("selection-thumb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = PreIngestThumbnailCache(directoryURL: dir)
        let entries = makeEntries(count: 1, duplicateIndices: [])
        let url = entries[0].url
        try cache.storeThumbnail(try makeImageData(), for: url)
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [], thumbnailCache: cache)
        let sentinel = NSImage(size: NSSize(width: 2, height: 2))
        model.thumbnails[url] = sentinel

        model.loadThumbnail(for: url)

        XCTAssertTrue(model.thumbnails[url] === sentinel)
    }

    private func makeEntries(count: Int, duplicateIndices: Set<Int>) -> [ImportSelectionEntry] {
        (0..<count).map { i in
            ImportSelectionEntry(
                url: URL(fileURLWithPath: "/tmp/photo\(i).jpg"),
                byteSize: 1_000_000,
                isDuplicate: duplicateIndices.contains(i)
            )
        }
    }

    private func makeImageData() throws -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        return try XCTUnwrap(image.tiffRepresentation)
    }
}
