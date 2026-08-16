import XCTest
@testable import TeststripCore
@testable import TeststripApp

// One sidebar, top to bottom: Library, Imports, Smart Collections, Sets,
// Folders, Recent Work, Selection. Every count lives in exactly one place.
final class UnifiedSidebarPresentationTests: XCTestCase {
    private func summary(_ id: String, day: Int, count: Int, issues: Int = 0) -> ImportSidebarSummary {
        ImportSidebarSummary(
            sessionID: WorkSessionID(rawValue: id),
            createdAt: Date(timeIntervalSince1970: TimeInterval(day * 86_400)),
            detail: "Imported from /Cards/\(id)",
            assetCount: count,
            issues: (0..<issues).map { index in
                WorkSessionIssue(kind: .skippedSourceFile, sourceURL: nil, message: "skipped \(index)")
            }
        )
    }

    private func sections(
        importSummaries: [ImportSidebarSummary] = [],
        expandedImportSessionIDs: Set<String> = [],
        importChildCounts: [String: ImportChildCounts] = [:],
        isShowingAllImports: Bool = false,
        smartCollectionCounts: [SmartCollection: Int] = [:],
        autopilotGhostCount: Int = 0,
        savedAssetSets: [AssetSet] = [],
        assetSetCounts: [AssetSetID: Int] = [:],
        selectionCount: Int = 0
    ) -> [SidebarSection] {
        UnifiedSidebarPresentation.sections(
            totalAssetCount: 42,
            importSummaries: importSummaries,
            expandedImportSessionIDs: expandedImportSessionIDs,
            importChildCounts: importChildCounts,
            isShowingAllImports: isShowingAllImports,
            smartCollectionCounts: smartCollectionCounts,
            autopilotGhostCount: autopilotGhostCount,
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            catalogFolders: [],
            expandedFolderPaths: [],
            recentWork: [],
            starredWork: [],
            matchedWork: [],
            workSessionScopeCounts: [:],
            selectionCount: selectionCount
        )
    }

    func testLibrarySectionAlwaysLeadsWithAllPhotos() {
        let library = try? XCTUnwrap(sections().first)
        XCTAssertEqual(library?.title, "Library")
        XCTAssertEqual(library?.rows.first?.title, "All Photos")
        XCTAssertEqual(library?.rows.first?.target, LibrarySource.allPhotos)
        XCTAssertEqual(library?.rows.first?.countText, "42")
    }

    func testSmartCollectionsAndSetsRemainVisibleWhenEmpty() throws {
        let result = sections()

        XCTAssertEqual(result.map(\.title), ["Library", "Smart Collections", "Sets"])
        let smartCollections = try XCTUnwrap(
            result.first { $0.title == UnifiedSidebarPresentation.smartCollectionsSectionTitle }
        )
        let sets = try XCTUnwrap(
            result.first { $0.title == UnifiedSidebarPresentation.setsSectionTitle }
        )
        XCTAssertTrue(smartCollections.rows.isEmpty)
        XCTAssertTrue(sets.rows.isEmpty)
    }

    func testImportsShowTheRecentThreePlusAnAllImportsOverflowRow() throws {
        let summaries = (0..<7).map { summary("import-\($0)", day: $0, count: 10 + $0) }.reversed()
        let imports = try XCTUnwrap(sections(importSummaries: Array(summaries)).first { $0.title == "Imports" })

        XCTAssertEqual(imports.rows.count, 4)
        XCTAssertEqual(imports.rows.prefix(3).map(\.countText), ["16", "15", "14"])
        let overflow = try XCTUnwrap(imports.rows.last)
        XCTAssertEqual(overflow.id, UnifiedSidebarPresentation.allImportsRowID)
        XCTAssertEqual(overflow.title, "All imports…")
        XCTAssertEqual(overflow.countText, "7")
        XCTAssertEqual(overflow.disclosure, .collapsed)
    }

    func testAllImportsExpandsToEveryImportWithoutAnOverflowRow() throws {
        let summaries = (0..<7).map { summary("import-\($0)", day: $0, count: 10) }.reversed()
        let imports = try XCTUnwrap(
            sections(importSummaries: Array(summaries), isShowingAllImports: true).first { $0.title == "Imports" }
        )

        XCTAssertEqual(imports.rows.count, 8)
        XCTAssertEqual(imports.rows.last?.disclosure, .expanded)
    }

    func testTheImportsSectionIsAbsentWithNoImports() {
        XCTAssertNil(sections().first { $0.title == "Imports" })
    }

    func testImportRowLabelCarriesTheDateAndFolderNotTheConstantTitle() throws {
        let imports = try XCTUnwrap(
            sections(importSummaries: [summary("import-a", day: 5, count: 3)]).first { $0.title == "Imports" }
        )

        let row = try XCTUnwrap(imports.rows.first)
        XCTAssertTrue(row.title.hasSuffix("Imported from /Cards/import-a"), row.title)
        XCTAssertNotEqual(row.title, "Import photos")
    }

    func testExpandedImportRendersOnlyItsNonzeroChildren() throws {
        let imports = try XCTUnwrap(
            sections(
                importSummaries: [summary("import-a", day: 5, count: 30, issues: 2)],
                expandedImportSessionIDs: ["import-a"],
                importChildCounts: [
                    "import-a": ImportChildCounts(
                        stacks: 4,
                        skippedFiles: 2,
                        previewFailed: 0,
                        likelyIssues: 3,
                        facesFound: 0
                    )
                ]
            ).first { $0.title == "Imports" }
        )

        let children = imports.rows.filter { $0.depth == 1 }
        XCTAssertEqual(children.map(\.title), ["Stacks", "⚠ Skipped files", "⚠ Likely issues"])
        XCTAssertEqual(children.map(\.countText), ["4", "2", "3"])
        XCTAssertEqual(imports.rows.first?.disclosure, .expanded)
    }

    func testWarningChildrenCarryTheWarningTone() throws {
        let imports = try XCTUnwrap(
            sections(
                importSummaries: [summary("import-a", day: 5, count: 30, issues: 1)],
                expandedImportSessionIDs: ["import-a"],
                importChildCounts: [
                    "import-a": ImportChildCounts(stacks: 1, skippedFiles: 1, previewFailed: 1, likelyIssues: 1, facesFound: 1)
                ]
            ).first { $0.title == "Imports" }
        )

        let tonesByTitle = Dictionary(
            uniqueKeysWithValues: imports.rows.filter { $0.depth == 1 }.map { ($0.title, $0.tone) }
        )
        XCTAssertEqual(tonesByTitle["Stacks"], .neutral)
        XCTAssertEqual(tonesByTitle["⚠ Skipped files"], .warning)
        XCTAssertEqual(tonesByTitle["⚠ Preview failed"], .warning)
        XCTAssertEqual(tonesByTitle["⚠ Likely issues"], .warning)
        XCTAssertEqual(tonesByTitle["Faces found"], .neutral)
    }

    func testCollapsedImportHasNoChildren() throws {
        let imports = try XCTUnwrap(
            sections(
                importSummaries: [summary("import-a", day: 5, count: 30)],
                importChildCounts: ["import-a": ImportChildCounts(stacks: 4)]
            ).first { $0.title == "Imports" }
        )

        XCTAssertTrue(imports.rows.allSatisfy { $0.depth == 0 })
        XCTAssertEqual(imports.rows.first?.disclosure, .collapsed)
    }

    func testSmartCollectionsHoldAllTenSmartCollectionsWithNonzeroCounts() throws {
        var counts: [SmartCollection: Int] = [:]
        for (index, queue) in SmartCollection.allCases.enumerated() {
            counts[queue] = index + 1
        }
        let smart = try XCTUnwrap(
            sections(smartCollectionCounts: counts).first { $0.title == "Smart Collections" }
        )

        XCTAssertEqual(smart.rows.count, 10)
        XCTAssertTrue(smart.rowTitles.contains("Analysis Failures"))
        XCTAssertTrue(smart.rowTitles.contains("Potential Picks"))
    }

    func testSmartCollectionsDropZeroCountQueuesAndShowAISuggestionsOnlyWhenGhostsExist() throws {
        let withoutGhosts = sections(smartCollectionCounts: [.picks: 2, .rejects: 0]).first { $0.title == "Smart Collections" }
        XCTAssertEqual(withoutGhosts?.rowTitles, ["Picks"])

        let withGhosts = try XCTUnwrap(
            sections(smartCollectionCounts: [.picks: 2], autopilotGhostCount: 5).first { $0.title == "Smart Collections" }
        )
        XCTAssertEqual(withGhosts.rowTitles, ["Picks", "AI Suggestions"])
        XCTAssertEqual(withGhosts.rows.last?.target, LibrarySource.autopilotSuggestions)
    }

    // A saved dynamic set IS a smart collection — that is what the header's
    // "+ New from search…" produces. Static membership belongs in Sets.
    func testDynamicSavedSetsJoinSmartCollectionsAndStaticOnesJoinSets() throws {
        let dynamic = AssetSet.dynamic(
            id: AssetSetID(rawValue: "dyn"),
            name: "Recent Keepers",
            query: SetQuery(predicates: [.flag(.pick)])
        )
        let manual = AssetSet.manual(id: AssetSetID(rawValue: "man"), name: "Portfolio", assetIDs: [])
        let starredManual = AssetSet(
            id: AssetSetID(rawValue: "star"),
            name: "Starred Set",
            membership: .snapshot([]),
            starred: true
        )
        let result = sections(
            smartCollectionCounts: [.picks: 1],
            savedAssetSets: [dynamic, manual, starredManual],
            assetSetCounts: [dynamic.id: 7, manual.id: 3, starredManual.id: 1]
        )

        let smart = try XCTUnwrap(result.first { $0.title == "Smart Collections" })
        XCTAssertTrue(smart.rowTitles.contains("Recent Keepers"))

        let sets = try XCTUnwrap(result.first { $0.title == "Sets" })
        XCTAssertEqual(sets.rowTitles, ["Starred Set", "Portfolio"], "starred sets sort first")
        XCTAssertFalse(sets.rowTitles.contains("Recent Keepers"))
    }

    func testInternalWorkSetsNeverAppearAsRows() throws {
        let output = AssetSet.manual(id: AssetSetID(rawValue: "work-output-1"), name: "Imported", assetIDs: [])
        let input = AssetSet.manual(id: AssetSetID(rawValue: "work-input-1"), name: "Cull input", assetIDs: [])
        let stack = AssetSet.manual(id: AssetSetID(rawValue: "work-stack-1"), name: "Stack 1", assetIDs: [])
        let previewFailure = AssetSet.manual(
            id: AssetSetID(rawValue: "import-preview-failed-1"),
            name: "Preview failures",
            assetIDs: []
        )
        let selectionSource = AssetSet.manual(
            id: AssetSetID(rawValue: "selection-source-1"),
            name: "Selection source",
            assetIDs: []
        )
        let cullSelection = AssetSet.manual(
            id: AssetSetID(rawValue: "cull-selection-1"),
            name: "Cull selection",
            assetIDs: []
        )

        let result = sections(
            savedAssetSets: [output, input, stack, previewFailure, selectionSource, cullSelection]
        )

        let sets = try XCTUnwrap(
            result.first { $0.title == UnifiedSidebarPresentation.setsSectionTitle }
        )
        XCTAssertTrue(sets.rows.isEmpty)
    }

    func testSelectionSectionIsTransientAndLast() throws {
        XCTAssertNil(sections(selectionCount: 0).first { $0.title == "Selection" })

        let result = sections(selectionCount: 4)
        XCTAssertEqual(result.last?.title, "Selection")
        XCTAssertEqual(result.last?.rows.first?.countText, "4")
        XCTAssertEqual(result.last?.rows.first?.target, LibrarySource.selection)
    }

    func testSectionOrderIsLibraryImportsSmartCollectionsSetsSelection() {
        let result = sections(
            importSummaries: [summary("import-a", day: 1, count: 3)],
            smartCollectionCounts: [.picks: 1],
            savedAssetSets: [AssetSet.manual(id: AssetSetID(rawValue: "man"), name: "Portfolio", assetIDs: [])],
            assetSetCounts: [AssetSetID(rawValue: "man"): 3],
            selectionCount: 2
        )

        XCTAssertEqual(
            result.map(\.title),
            ["Library", "Imports", "Smart Collections", "Sets", "Selection"]
        )
    }
}
