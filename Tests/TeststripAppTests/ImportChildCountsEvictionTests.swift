import XCTest
@testable import TeststripCore
@testable import TeststripApp

// M87: `importChildCountsBySessionID` is only ever inserted into; nothing
// removes an entry when its row collapses. After expand → collapse, the
// entry should be evicted so the dict doesn't grow unbounded.
final class ImportChildCountsEvictionTests: XCTestCase {

    @MainActor
    func testCollapseEvictsImportChildCountsEntry() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-counts-eviction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let paths = AppCatalog.defaultPaths(
            applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)
        )
        let catalog = try AppCatalog.open(paths: paths)

        // Create an import session with an output set so it appears in the
        // sidebar's Imports section.
        let sessionID = WorkSessionID(rawValue: "test-import-session")
        let outputSetID = AssetSetID(rawValue: "work-output-\(sessionID.rawValue)")
        let assetID = AssetID(rawValue: "test-asset")
        try catalog.repository.upsert(Asset(
            id: assetID,
            originalURL: URL(fileURLWithPath: "/Photos/test.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        ))
        try catalog.repository.upsert(AssetSet.manual(
            id: outputSetID,
            name: "Import photos",
            assetIDs: [assetID]
        ))
        try catalog.repository.save(WorkSession(
            id: sessionID,
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: "1 photo from /Photos",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [outputSetID],
            completedUnitCount: 1,
            totalUnitCount: 1,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        ))

        let model = try AppModel.load(catalog: catalog)

        // Find the sidebar row for this import session.
        let importRow = try XCTUnwrap(
            model.sidebarSections
                .first { $0.title == UnifiedSidebarPresentation.importsSectionTitle }?
                .rows
                .first { $0.id == "import-\(sessionID.rawValue)" },
            "expected an Imports sidebar row for the test session"
        )

        // Expand: should prime the counts dict.
        model.toggleSidebarExpansion(importRow)
        XCTAssertNotNil(
            model.importChildCountsBySessionID[sessionID.rawValue],
            "expand should populate importChildCountsBySessionID"
        )

        // Collapse: should evict the counts entry.
        model.toggleSidebarExpansion(importRow)
        XCTAssertNil(
            model.importChildCountsBySessionID[sessionID.rawValue],
            "collapse should evict the importChildCountsBySessionID entry to prevent unbounded growth"
        )
    }
}
