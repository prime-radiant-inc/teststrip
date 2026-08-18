import XCTest
@testable import TeststripApp

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
    func testDefaultAllSelected() {
        let entries = makeEntries(count: 3, duplicateIndices: [1])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [entries[1].url])
        XCTAssertEqual(model.selectedURLs.count, 3, "all should be selected by default")
    }

    @MainActor
    func testSelectedCountAfterDeselect() {
        let entries = makeEntries(count: 5, duplicateIndices: [])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [])
        model.toggle(entries[0].url)
        XCTAssertEqual(model.selectedURLs.count, 4)
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
}
