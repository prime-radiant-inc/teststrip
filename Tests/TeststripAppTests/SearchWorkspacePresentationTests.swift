import XCTest
import TeststripCore
@testable import TeststripApp

final class SearchWorkspacePresentationTests: XCTestCase {
    func testRefineRowsExposeActiveStateForRemovalControls() {
        XCTAssertTrue(SearchWorkspaceRefineRow(title: "Pick", value: "active").isActive)
        XCTAssertFalse(SearchWorkspaceRefineRow(title: "5 Stars", value: "2 photos").isActive)
    }

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
            canStartCulling: true,
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
                action: .startCulling,
                title: "Cull current scope",
                detail: "Start a culling session for 42 results",
                systemImage: "checkmark.seal"
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
            canStartCulling: true,
            reviewQueueCounts: [
                .needsKeywords: 0
            ]
        )

        XCTAssertEqual(presentation.suggestedActions, [])
    }

    func testSuggestedActionsCanOmitCurrentScopeCulling() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "All Photographs",
            totalAssetCount: 42,
            savedSetCount: 0,
            starredSetCount: 0,
            activeFilterChips: [],
            canStartCulling: false
        )

        XCTAssertFalse(presentation.suggestedActions.contains { $0.action == .startCulling })
    }

    func testRelatedFiltersSuggestNonActiveReviewQueuesWithCounts() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "Ceremony Review",
            totalAssetCount: 42,
            savedSetCount: 2,
            starredSetCount: 1,
            activeFilterChips: [],
            activeFilterRows: [
                ActiveLibraryFilterRow(title: "Pick", target: .reviewQueue(.picks)),
                ActiveLibraryFilterRow(title: "Needs Keywords", target: .reviewQueue(.needsKeywords))
            ],
            reviewQueueCounts: [
                .picks: 7,
                .rejects: 0,
                .fiveStars: 1,
                .needsKeywords: 9,
                .facesFound: 2,
                .providerFailures: 1
            ]
        )

        XCTAssertEqual(presentation.relatedFilterRows, [
            SearchWorkspaceRefineRow(title: "5 Stars", value: "1 photo", target: .reviewQueue(.fiveStars)),
            SearchWorkspaceRefineRow(title: "Faces Found", value: "2 photos", target: .reviewQueue(.facesFound)),
            SearchWorkspaceRefineRow(title: "Provider Failures", value: "1 photo", target: .reviewQueue(.providerFailures))
        ])
    }

    func testGeneratedRefinementsSuggestConcreteRulesWithoutRepeatingActiveFilters() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "Ceremony Review",
            totalAssetCount: 42,
            savedSetCount: 2,
            starredSetCount: 1,
            activeFilterChips: [],
            activeFilterRows: [
                ActiveLibraryFilterRow(title: "Pick", target: .reviewQueue(.picks)),
                ActiveLibraryFilterRow(title: "Camera: Canon", target: nil)
            ],
            reviewQueueCounts: [
                .picks: 7,
                .fiveStars: 4,
                .needsKeywords: 12,
                .facesFound: 3,
                .providerFailures: 1
            ]
        )

        XCTAssertEqual(presentation.generatedRefinements, [
            SearchWorkspaceGeneratedRefinement(
                preset: .ratingFourPlus,
                title: "Narrow to rated keepers",
                detail: "4 five-star photos available",
                systemImage: "star.fill"
            ),
            SearchWorkspaceGeneratedRefinement(
                preset: .needsKeywords,
                title: "Find missing keywords",
                detail: "12 photos need keywords",
                systemImage: "tag"
            ),
            SearchWorkspaceGeneratedRefinement(
                preset: .facesFound,
                title: "Review photos with faces",
                detail: "3 photos have face signals",
                systemImage: "person.2"
            )
        ])
    }

    func testGeneratedRefinementsIncludeProviderSignalRules() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "Signal Review",
            totalAssetCount: 42,
            savedSetCount: 2,
            starredSetCount: 1,
            activeFilterChips: [],
            activeFilterRows: [
                ActiveLibraryFilterRow(title: "Signal: OCR Text", target: .evaluationKind(.ocrText))
            ],
            reviewQueueCounts: [
                .needsKeywords: 6
            ],
            evaluationKindSummaries: [
                CatalogEvaluationKindSummary(kind: .focus, assetCount: 5),
                CatalogEvaluationKindSummary(kind: .object, assetCount: 8),
                CatalogEvaluationKindSummary(kind: .ocrText, assetCount: 3),
                CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 4)
            ]
        )

        XCTAssertEqual(presentation.generatedRefinements, [
            SearchWorkspaceGeneratedRefinement(
                preset: .needsKeywords,
                title: "Find missing keywords",
                detail: "6 photos need keywords",
                systemImage: "tag"
            ),
            SearchWorkspaceGeneratedRefinement(
                preset: .focusSignals,
                title: "Find focus-scored photos",
                detail: "5 photos have focus signals",
                systemImage: "scope"
            ),
            SearchWorkspaceGeneratedRefinement(
                preset: .objectSignals,
                title: "Find object-labeled photos",
                detail: "8 photos have object labels",
                systemImage: "shippingbox"
            ),
            SearchWorkspaceGeneratedRefinement(
                preset: .facesFound,
                title: "Review photos with people signals",
                detail: "4 photos have people signals",
                systemImage: "person.2"
            )
        ])
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
            SearchWorkspaceRefineRow(title: "All photos", value: "current scope", target: .allPhotographs)
        ])
    }

    func testPlainResidualSearchShowsHonestAskFallback() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "best group portraits",
            totalAssetCount: 12,
            savedSetCount: 0,
            starredSetCount: 0,
            activeFilterChips: [
                "Search: best group portraits"
            ]
        )

        XCTAssertEqual(presentation.askInterpretation, SearchWorkspaceAskInterpretation(
            queryText: "best group portraits",
            title: "Plain search fallback",
            detail: "No structured filters were recognized yet",
            systemImage: "text.magnifyingglass"
        ))
        XCTAssertEqual(presentation.generatedRefinements, [])
        XCTAssertEqual(presentation.refineGroups, [
            SearchWorkspaceRefineGroup(title: "Metadata", rows: [
                SearchWorkspaceRefineRow(title: "Search: best group portraits", value: "active")
            ])
        ])
    }

    func testMixedParsedAndResidualSearchShowsParsedAndRemainingAskState() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "Ceremony Picks",
            totalAssetCount: 8,
            savedSetCount: 0,
            starredSetCount: 0,
            activeFilterChips: [],
            activeFilterRows: [
                ActiveLibraryFilterRow(title: "Search: ceremony"),
                ActiveLibraryFilterRow(title: "Pick", target: .reviewQueue(.picks)),
                ActiveLibraryFilterRow(title: "Rating >= 4", target: .reviewQueue(.fiveStars))
            ]
        )

        XCTAssertEqual(presentation.askInterpretation?.queryText, "ceremony")
        XCTAssertEqual(presentation.askInterpretation?.detail, "Plain text remains after parsed filters")
        XCTAssertEqual(presentation.refineGroups, [
            SearchWorkspaceRefineGroup(title: "Decisions", rows: [
                SearchWorkspaceRefineRow(title: "Pick", value: "active", target: .reviewQueue(.picks)),
                SearchWorkspaceRefineRow(title: "Rating >= 4", value: "active", target: .reviewQueue(.fiveStars))
            ]),
            SearchWorkspaceRefineGroup(title: "Metadata", rows: [
                SearchWorkspaceRefineRow(title: "Search: ceremony", value: "active")
            ])
        ])
    }

    func testWorkHistoryRowsExposeReopenTargets() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "ceremony",
            totalAssetCount: 0,
            savedSetCount: 0,
            starredSetCount: 0,
            activeFilterChips: ["Search: ceremony"],
            workHistory: [
                AppWorkActivity(
                    id: "cull-42",
                    kind: .culling,
                    status: .completed,
                    title: "Cull Ceremony",
                    detail: "Reviewed ceremony candidates",
                    completedUnitCount: 42,
                    totalUnitCount: 42,
                    failureCount: 0
                )
            ]
        )

        XCTAssertEqual(presentation.workHistoryRows, [
            SearchWorkspaceRefineRow(
                title: "Cull Ceremony",
                value: "Reviewed ceremony candidates",
                target: .workSession(WorkSessionID(rawValue: "cull-42"))
            )
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
                ActiveLibraryFilterRow(title: "Camera: Canon", target: nil),
                ActiveLibraryFilterRow(title: "Session: cull-42", target: .workSession(WorkSessionID(rawValue: "cull-42")))
            ]
        )

        XCTAssertEqual(presentation.refineRows.map(\.target), [
            .reviewQueue(.picks),
            .evaluationKind(.faceQuality),
            .metadataSyncPending,
            nil,
            .workSession(WorkSessionID(rawValue: "cull-42"))
        ])
        XCTAssertEqual(
            presentation.refineGroups.flatMap(\.rows).map(\.target),
            [
                .workSession(WorkSessionID(rawValue: "cull-42")),
                .reviewQueue(.picks),
                nil,
                .evaluationKind(.faceQuality),
                .metadataSyncPending
            ]
        )
        XCTAssertEqual(presentation.refineGroups.first?.title, "Scope")
        XCTAssertEqual(presentation.refineGroups.first?.rows.map(\.title), ["Session: cull-42"])
    }

    func testGroupsSessionAndImportFiltersAsScope() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "Session Scope",
            totalAssetCount: 18,
            savedSetCount: 0,
            starredSetCount: 0,
            activeFilterChips: [],
            activeFilterRows: [
                ActiveLibraryFilterRow(title: "Import: latest-import"),
                ActiveLibraryFilterRow(title: "Session: cull-42", target: .workSession(WorkSessionID(rawValue: "cull-42"))),
                ActiveLibraryFilterRow(title: "Camera: Canon")
            ]
        )

        XCTAssertEqual(presentation.refineGroups.first, SearchWorkspaceRefineGroup(title: "Scope", rows: [
            SearchWorkspaceRefineRow(title: "Import: latest-import", value: "active"),
            SearchWorkspaceRefineRow(title: "Session: cull-42", value: "active", target: .workSession(WorkSessionID(rawValue: "cull-42")))
        ]))
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
                ActiveLibraryFilterRow(title: "Session: cull-42", target: .workSession(WorkSessionID(rawValue: "cull-42"))),
                ActiveLibraryFilterRow(title: "Import: import-7", target: .workSession(WorkSessionID(rawValue: "import-7"))),
                ActiveLibraryFilterRow(title: "Search: ceremony"),
                ActiveLibraryFilterRow(title: "Pick", target: .reviewQueue(.picks)),
                ActiveLibraryFilterRow(title: "Rating >= 5", target: .reviewQueue(.fiveStars)),
                ActiveLibraryFilterRow(title: "Needs Keywords", target: .reviewQueue(.needsKeywords))
            ]
        )

        XCTAssertEqual(presentation.refineGroups, [
            SearchWorkspaceRefineGroup(title: "Scope", rows: [
                SearchWorkspaceRefineRow(title: "Ceremony Keepers", value: "active", target: .assetSet(setID)),
                SearchWorkspaceRefineRow(title: "Session: cull-42", value: "active", target: .workSession(WorkSessionID(rawValue: "cull-42"))),
                SearchWorkspaceRefineRow(title: "Import: import-7", value: "active", target: .workSession(WorkSessionID(rawValue: "import-7")))
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
