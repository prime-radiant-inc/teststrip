import XCTest
import TeststripCore
@testable import TeststripApp

final class SearchWorkspacePresentationTests: XCTestCase {
    func testBuildsRefineRailFromCurrentSearchState() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "Pick 4+ Stars",
            totalAssetCount: 42,
            savedSetCount: 6,
            starredSetCount: 2,
            activeFilterChips: ["Pick", "Rating >= 4", "Camera: Canon"]
        )

        XCTAssertEqual(presentation.title, "Pick 4+ Stars")
        XCTAssertEqual(presentation.resultCountText, "42")
        XCTAssertEqual(presentation.savedSetCountText, "6")
        XCTAssertEqual(presentation.starredSetCountText, "2")
        XCTAssertEqual(presentation.refineRows, [
            SearchWorkspaceRefineRow(title: "Pick", value: "active"),
            SearchWorkspaceRefineRow(title: "Rating >= 4", value: "active"),
            SearchWorkspaceRefineRow(title: "Camera: Canon", value: "active")
        ])
    }

    func testSuggestedActionsExposeExistingSetAndReviewWorkflows() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "Pick 4+ Stars",
            totalAssetCount: 42,
            savedSetCount: 6,
            starredSetCount: 2,
            activeFilterChips: ["Pick", "Rating >= 4"],
            canSaveDynamicSet: true,
            canSaveSnapshotSet: true,
            reviewQueueCounts: [
                .needsKeywords: 9,
                .providerFailures: 0,
                .likelyIssues: 2
            ]
        )

        XCTAssertEqual(presentation.suggestedActions, [
            SearchWorkspaceSuggestedAction(
                action: .saveDynamicSet,
                title: "Save dynamic set",
                detail: "Pick 4+ Stars updates as the catalog changes",
                systemImage: "bookmark"
            ),
            SearchWorkspaceSuggestedAction(
                action: .saveSnapshotSet,
                title: "Freeze 42 results",
                detail: "Capture this exact result set",
                systemImage: "camera.viewfinder"
            ),
            SearchWorkspaceSuggestedAction(
                action: .openReviewQueue(.needsKeywords),
                title: "Review Needs Keywords",
                detail: "9 photos",
                systemImage: "tag"
            ),
            SearchWorkspaceSuggestedAction(
                action: .openReviewQueue(.likelyIssues),
                title: "Review Likely Issues",
                detail: "2 photos",
                systemImage: "exclamationmark.triangle"
            )
        ])
    }

    func testSuggestedActionsStayEmptyWithoutAvailableWorkflows() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "All Photographs",
            totalAssetCount: 0,
            savedSetCount: 0,
            starredSetCount: 0,
            activeFilterChips: [],
            canSaveDynamicSet: false,
            canSaveSnapshotSet: false,
            reviewQueueCounts: [
                .needsKeywords: 0
            ]
        )

        XCTAssertEqual(presentation.suggestedActions, [])
    }

    func testUsesAllPhotographsRefineRowWhenNoFiltersAreActive() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "All Photographs",
            totalAssetCount: 120,
            savedSetCount: 0,
            starredSetCount: 0,
            activeFilterChips: []
        )

        XCTAssertEqual(presentation.refineRows, [
            SearchWorkspaceRefineRow(title: "All photographs", value: "current scope", target: .allPhotographs)
        ])
    }

    func testRefineRowsPreserveActionTargetsWhenGrouped() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "Review Targets",
            totalAssetCount: 18,
            savedSetCount: 3,
            starredSetCount: 1,
            activeFilterChips: [],
            activeFilterRows: [
                ActiveLibraryFilterRow(title: "Pick", target: .reviewQueue(.picks)),
                ActiveLibraryFilterRow(title: "Signal: Face Quality", target: .evaluationKind(.faceQuality)),
                ActiveLibraryFilterRow(title: "XMP Pending", target: .metadataSyncPending),
                ActiveLibraryFilterRow(title: "Camera: Canon", target: nil)
            ]
        )

        XCTAssertEqual(presentation.refineRows.map(\.target), [
            .reviewQueue(.picks),
            .evaluationKind(.faceQuality),
            .metadataSyncPending,
            nil
        ])
        XCTAssertEqual(
            presentation.refineGroups.flatMap(\.rows).map(\.target),
            [
                .reviewQueue(.picks),
                nil,
                .evaluationKind(.faceQuality),
                .metadataSyncPending
            ]
        )
    }

    func testGroupsActiveFiltersIntoMockupRefineSections() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "Ceremony Review",
            totalAssetCount: 18,
            savedSetCount: 3,
            starredSetCount: 1,
            activeFilterChips: [
                "Pick",
                "Rating >= 4",
                "Camera: Canon",
                "Needs Keywords",
                "Signal: Face Quality",
                "Source: Offline",
                "XMP Pending",
                "Search: ceremony"
            ]
        )

        XCTAssertEqual(presentation.refineGroups, [
            SearchWorkspaceRefineGroup(title: "Decisions", rows: [
                SearchWorkspaceRefineRow(title: "Pick", value: "active"),
                SearchWorkspaceRefineRow(title: "Rating >= 4", value: "active")
            ]),
            SearchWorkspaceRefineGroup(title: "Metadata", rows: [
                SearchWorkspaceRefineRow(title: "Camera: Canon", value: "active"),
                SearchWorkspaceRefineRow(title: "Search: ceremony", value: "active")
            ]),
            SearchWorkspaceRefineGroup(title: "Review Queues", rows: [
                SearchWorkspaceRefineRow(title: "Needs Keywords", value: "active")
            ]),
            SearchWorkspaceRefineGroup(title: "Signals", rows: [
                SearchWorkspaceRefineRow(title: "Signal: Face Quality", value: "active")
            ]),
            SearchWorkspaceRefineGroup(title: "Source & XMP", rows: [
                SearchWorkspaceRefineRow(title: "Source: Offline", value: "active"),
                SearchWorkspaceRefineRow(title: "XMP Pending", value: "active")
            ])
        ])
    }

    func testGroupsSelectedSavedSetAsScopeAndShowsSavedRules() {
        let setID = AssetSetID(rawValue: "ceremony-keepers")
        let presentation = SearchWorkspacePresentation(
            suggestedName: "Ceremony Keepers",
            totalAssetCount: 18,
            savedSetCount: 3,
            starredSetCount: 1,
            activeFilterChips: [],
            activeFilterRows: [
                ActiveLibraryFilterRow(title: "Ceremony Keepers", target: .assetSet(setID)),
                ActiveLibraryFilterRow(title: "Search: ceremony"),
                ActiveLibraryFilterRow(title: "Pick", target: .reviewQueue(.picks)),
                ActiveLibraryFilterRow(title: "Rating >= 5", target: .reviewQueue(.fiveStars)),
                ActiveLibraryFilterRow(title: "Needs Keywords", target: .reviewQueue(.needsKeywords))
            ]
        )

        XCTAssertEqual(presentation.refineGroups, [
            SearchWorkspaceRefineGroup(title: "Scope", rows: [
                SearchWorkspaceRefineRow(title: "Ceremony Keepers", value: "active", target: .assetSet(setID))
            ]),
            SearchWorkspaceRefineGroup(title: "Decisions", rows: [
                SearchWorkspaceRefineRow(title: "Pick", value: "active", target: .reviewQueue(.picks)),
                SearchWorkspaceRefineRow(title: "Rating >= 5", value: "active", target: .reviewQueue(.fiveStars))
            ]),
            SearchWorkspaceRefineGroup(title: "Metadata", rows: [
                SearchWorkspaceRefineRow(title: "Search: ceremony", value: "active")
            ]),
            SearchWorkspaceRefineGroup(title: "Review Queues", rows: [
                SearchWorkspaceRefineRow(title: "Needs Keywords", value: "active", target: .reviewQueue(.needsKeywords))
            ])
        ])
    }
}
