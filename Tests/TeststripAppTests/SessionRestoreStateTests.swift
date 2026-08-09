import XCTest
import TeststripCore
@testable import TeststripApp

final class SessionRestoreStateTests: XCTestCase {
    func testRoundTripPreservesAllFields() throws {
        let state = SessionRestoreState(
            lens: .timeline,
            source: .smartCollection(.likelyIssues),
            selectedAssetSetID: AssetSetID(rawValue: "set-1"),
            selectedAssetID: AssetID(rawValue: "asset-1"),
            sortOption: .captureTimeNewestFirst,
            librarySearchText: "patagonia",
            keywordFilterText: "sunset",
            folderFilterText: "2026/2026-01-01",
            minimumRatingFilter: 4,
            flagFilter: .pick,
            colorLabelFilter: .green,
            cameraFilterText: "Fuji",
            lensFilterText: "35mm",
            minimumISOFilter: 400,
            captureDateStartFilter: Date(timeIntervalSince1970: 1_000),
            captureDateEndFilter: Date(timeIntervalSince1970: 2_000),
            availabilityFilter: .offline,
            evaluationKindFilter: .faceCount,
            needsKeywordsFilter: true,
            needsEvaluationFilter: true,
            likelyIssuesFilter: true,
            potentialPicksFilter: true,
            providerFailuresFilter: true,
            metadataSyncPendingFilter: true,
            metadataSyncConflictFilter: true,
            detachedFilterPredicates: [.likelyIssue, .importBatch("import-9")]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SessionRestoreState.self, from: data)

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.version, SessionRestoreState.currentVersion)
    }

    func testStoreSaveThenLoadReturnsSameState() throws {
        let defaults = try makeIsolatedDefaults()
        let catalogRoot = URL(fileURLWithPath: "/tmp/catalog-a", isDirectory: true)
        let store = SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot)
        let state = Self.minimalState(lens: .timeline, searchText: "roll 12")

        store.save(state)

        XCTAssertEqual(store.load(), state)
    }

    func testStoreLoadReturnsNilWhenNothingSaved() throws {
        let defaults = try makeIsolatedDefaults()
        let store = SessionRestoreStore(defaults: defaults, catalogRoot: URL(fileURLWithPath: "/tmp/catalog-empty", isDirectory: true))

        XCTAssertNil(store.load())
    }

    func testStoreNamespacesPerCatalogRoot() throws {
        let defaults = try makeIsolatedDefaults()
        let catalogRootA = URL(fileURLWithPath: "/tmp/catalog-a", isDirectory: true)
        let catalogRootB = URL(fileURLWithPath: "/tmp/catalog-b", isDirectory: true)
        let storeA = SessionRestoreStore(defaults: defaults, catalogRoot: catalogRootA)
        let storeB = SessionRestoreStore(defaults: defaults, catalogRoot: catalogRootB)
        let stateA = Self.minimalState(lens: .grid, searchText: "from A")
        let stateB = Self.minimalState(lens: .people, searchText: "from B")

        storeA.save(stateA)
        storeB.save(stateB)

        XCTAssertEqual(storeA.load(), stateA)
        XCTAssertEqual(storeB.load(), stateB)
    }

    func testStoreLoadReturnsNilForVersionMismatch() throws {
        let defaults = try makeIsolatedDefaults()
        let catalogRoot = URL(fileURLWithPath: "/tmp/catalog-version", isDirectory: true)
        let store = SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot)
        var futureState = Self.minimalState(lens: .grid, searchText: "")
        futureState.version = SessionRestoreState.currentVersion + 1
        let data = try JSONEncoder().encode(futureState)
        defaults.set(data, forKey: SessionRestoreStore.key(forCatalogRoot: catalogRoot))

        XCTAssertNil(store.load())
    }

    func testStoreLoadReturnsNilForCorruptData() throws {
        let defaults = try makeIsolatedDefaults()
        let catalogRoot = URL(fileURLWithPath: "/tmp/catalog-corrupt", isDirectory: true)
        let store = SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot)
        defaults.set(Data("not json".utf8), forKey: SessionRestoreStore.key(forCatalogRoot: catalogRoot))

        XCTAssertNil(store.load())
    }

    // A smart collection is now a set of predicates rather than a bag of
    // boolean filter properties, so the predicates are what has to survive a
    // relaunch — otherwise reopening the app drops you out of the collection.
    func testDetachedPredicatesSurviveTheStoreRoundTrip() throws {
        let defaults = try makeIsolatedDefaults()
        let store = SessionRestoreStore(
            defaults: defaults,
            catalogRoot: URL(fileURLWithPath: "/tmp/catalog-detached", isDirectory: true)
        )
        var state = Self.minimalState(lens: .grid, searchText: "")
        state.detachedFilterPredicates = [.evaluationFailure]

        store.save(state)

        XCTAssertEqual(store.load()?.detachedFilterPredicates, [.evaluationFailure])
    }

    func testTheStoredVersionIsTwo() {
        XCTAssertEqual(SessionRestoreState.currentVersion, 2)
    }

    // No back-compat: a v1 blob is discarded rather than migrated, so the
    // app cold-starts on All Photos in Grid instead of restoring a shape that
    // no longer exists.
    func testAVersionOneBlobIsDiscarded() throws {
        let defaults = try makeIsolatedDefaults()
        let catalogRoot = URL(fileURLWithPath: "/tmp/catalog-v1", isDirectory: true)
        let key = SessionRestoreStore.key(forCatalogRoot: catalogRoot)
        let legacy = #"{"version":1,"selectedView":"grid","sortOption":"importOrder","librarySearchText":""}"#
        defaults.set(Data(legacy.utf8), forKey: key)

        XCTAssertNil(SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot).load())
    }

    private static func minimalState(lens: LibraryLens, source: LibrarySource = .allPhotos, searchText: String) -> SessionRestoreState {
        SessionRestoreState(
            lens: lens,
            source: source,
            selectedAssetSetID: nil,
            selectedAssetID: nil,
            sortOption: .importOrder,
            librarySearchText: searchText,
            keywordFilterText: "",
            folderFilterText: "",
            minimumRatingFilter: nil,
            flagFilter: nil,
            colorLabelFilter: nil,
            cameraFilterText: "",
            lensFilterText: "",
            minimumISOFilter: nil,
            captureDateStartFilter: nil,
            captureDateEndFilter: nil,
            availabilityFilter: nil,
            evaluationKindFilter: nil,
            needsKeywordsFilter: false,
            needsEvaluationFilter: false,
            likelyIssuesFilter: false,
            potentialPicksFilter: false,
            providerFailuresFilter: false,
            metadataSyncPendingFilter: false,
            metadataSyncConflictFilter: false,
            detachedFilterPredicates: []
        )
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "teststrip.session-restore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "SessionRestoreStateTests", code: 1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
