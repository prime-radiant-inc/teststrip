import XCTest
@testable import TeststripCore
@testable import TeststripApp

// No lens ignores the nouns: the People lens over a narrowed source shows that
// source's people and that source's grouping queue. All Photos is the global
// queue, and naming/merge identity stays catalog-wide so a photographer can
// still name someone who is not in the current shoot.
final class PeopleSourceScopingTests: XCTestCase {
    private let faceProvenance = ProviderProvenance(
        provider: "apple-vision",
        model: "Vision",
        version: "1",
        settingsHash: "default"
    )

    func testPeopleScopeIsNilForAnUnfilteredCatalog() throws {
        let first = makeAsset(id: "scope-a", path: "/Photos/A/a.jpg")
        let second = makeAsset(id: "scope-b", path: "/Photos/B/b.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "people-scope-nil", assets: [first, second])

        XCTAssertNil(try model.peopleScopeAssetIDs())
    }

    func testPeopleScopeNarrowsWithTheSelectedSource() throws {
        let inside = makeAsset(id: "scope-inside", path: "/Photos/Inside/a.jpg")
        let outside = makeAsset(id: "scope-outside", path: "/Photos/Outside/b.jpg")
        let (model, _) = try makeModelWithCatalogAssets(
            named: "people-scope-folder",
            assets: [inside, outside]
        )

        try model.selectSource(.folder("/Photos/Inside"))

        XCTAssertEqual(try model.peopleScopeAssetIDs(), [inside.id])
    }

    func testPeopleInCurrentSourceOnlyListsPeopleInThatSource() throws {
        let inside = makeAsset(id: "people-inside", path: "/Photos/Inside/a.jpg")
        let outside = makeAsset(id: "people-outside", path: "/Photos/Outside/b.jpg")
        let (model, _) = try makeModelWithCatalogAssets(
            named: "people-in-source",
            assets: [inside, outside]
        ) { repository in
            try repository.upsertPerson(id: "person-inside", name: "Ada")
            try repository.upsertPerson(id: "person-outside", name: "Grace")
            try repository.assignAssets([inside.id], toPersonID: "person-inside")
            try repository.assignAssets([outside.id], toPersonID: "person-outside")
        }

        try model.selectSource(.folder("/Photos/Inside"))
        model.refreshPeopleFaceSuggestions()

        XCTAssertEqual(model.peopleInCurrentSource.map(\.name), ["Ada"])
        // Identity stays catalog-wide: naming and merging must still see Grace.
        XCTAssertEqual(Set(model.catalogPeople.map(\.name)), Set(["Ada", "Grace"]))
    }

    func testPeopleOverAllPhotosIsTheGlobalQueue() throws {
        let inside = makeAsset(id: "global-inside", path: "/Photos/Inside/a.jpg")
        let outside = makeAsset(id: "global-outside", path: "/Photos/Outside/b.jpg")
        let (model, _) = try makeModelWithCatalogAssets(
            named: "people-global",
            assets: [inside, outside]
        ) { repository in
            try repository.upsertPerson(id: "person-inside", name: "Ada")
            try repository.upsertPerson(id: "person-outside", name: "Grace")
            try repository.assignAssets([inside.id], toPersonID: "person-inside")
            try repository.assignAssets([outside.id], toPersonID: "person-outside")
        }

        try model.selectSource(.folder("/Photos/Inside"))
        model.refreshPeopleFaceSuggestions()
        try model.selectSource(.allPhotos)
        model.refreshPeopleFaceSuggestions()

        XCTAssertEqual(Set(model.peopleInCurrentSource.map(\.name)), Set(["Ada", "Grace"]))
    }

    func testSelectingFaceReviewOverAllPhotosRoutesToTheGlobalGridQuery() throws {
        let fixture = try makeFaceSignalFixture(named: "people-review-all-photos")
        fixture.model.selectLens(.people)

        try fixture.model.selectPeopleSignal(.faceCount)

        assertFaceReviewRoute(
            fixture.model,
            query: SetQuery(predicates: [.evaluationKind(.faceCount)]),
            assetIDs: [fixture.insideFace.id, fixture.outsideFace.id]
        )
    }

    func testSelectingFaceReviewIntersectsTheCurrentFolderScope() throws {
        let fixture = try makeFaceSignalFixture(named: "people-review-folder")
        try fixture.model.selectSource(.folder("/Photos/Inside"))
        fixture.model.selectLens(.people)

        try fixture.model.selectPeopleSignal(.faceCount)

        assertFaceReviewRoute(
            fixture.model,
            query: SetQuery(predicates: [
                .folderPrefix("/Photos/Inside"),
                .evaluationKind(.faceCount)
            ]),
            assetIDs: [fixture.insideFace.id]
        )
    }

    func testSelectingFaceReviewIntersectsTheCurrentStaticSetScope() throws {
        let fixture = try makeFaceSignalFixture(named: "people-review-static-set")
        let set = AssetSet.manual(
            id: AssetSetID(rawValue: "people-review-static-set"),
            name: "Inside selection",
            assetIDs: [fixture.insideFace.id, fixture.insidePlain.id]
        )
        try fixture.repository.upsert(set)
        try fixture.model.refreshSavedAssetSets()
        try fixture.model.selectSource(.assetSet(set.id, titled: set.name))
        fixture.model.selectLens(.people)

        try fixture.model.selectPeopleSignal(.faceCount)

        assertFaceReviewRoute(
            fixture.model,
            query: SetQuery(predicates: [
                .assetIDs([fixture.insideFace.id, fixture.insidePlain.id]),
                .evaluationKind(.faceCount)
            ]),
            assetIDs: [fixture.insideFace.id]
        )
    }

    func testSelectingFaceReviewPreservesAnEmptyExplicitScope() throws {
        let fixture = try makeFaceSignalFixture(named: "people-review-empty-set")
        let set = AssetSet.manual(
            id: AssetSetID(rawValue: "people-review-empty-set"),
            name: "Nothing selected",
            assetIDs: []
        )
        try fixture.repository.upsert(set)
        try fixture.model.refreshSavedAssetSets()
        try fixture.model.selectSource(.assetSet(set.id, titled: set.name))
        fixture.model.selectLens(.people)

        try fixture.model.selectPeopleSignal(.faceCount)

        assertFaceReviewRoute(
            fixture.model,
            query: SetQuery(predicates: [
                .assetIDs([]),
                .evaluationKind(.faceCount)
            ]),
            assetIDs: []
        )
    }

    func testSelectingFaceReviewIntersectsTheCurrentSelectionSource() throws {
        let fixture = try makeFaceSignalFixture(named: "people-review-selection")
        fixture.model.selectedAssetID = fixture.insideFace.id
        try fixture.model.selectSource(.selection)
        fixture.model.selectLens(.people)

        try fixture.model.selectPeopleSignal(.faceCount)

        assertFaceReviewRoute(
            fixture.model,
            query: SetQuery(predicates: [
                .assetIDs([fixture.insideFace.id]),
                .evaluationKind(.faceCount)
            ]),
            assetIDs: [fixture.insideFace.id]
        )
    }

    func testSelectingFaceReviewIntersectsTheCurrentDynamicSetQuery() throws {
        let fixture = try makeFaceSignalFixture(named: "people-review-dynamic-set")
        let set = AssetSet.dynamic(
            id: AssetSetID(rawValue: "people-review-dynamic-set"),
            name: "Inside folder",
            query: SetQuery(predicates: [.folderPrefix("/Photos/Inside")])
        )
        try fixture.repository.upsert(set)
        try fixture.model.refreshSavedAssetSets()
        try fixture.model.selectSource(.assetSet(set.id, titled: set.name))
        fixture.model.selectLens(.people)

        try fixture.model.selectPeopleSignal(.faceCount)

        assertFaceReviewRoute(
            fixture.model,
            query: SetQuery(predicates: [
                .folderPrefix("/Photos/Inside"),
                .evaluationKind(.faceCount)
            ]),
            assetIDs: [fixture.insideFace.id]
        )
    }

    func testSelectingFaceReviewIntersectsARealImportWorkSession() throws {
        let fixture = try makeFaceSignalFixture(named: "people-review-work-session")
        let session = try saveCompletedImport(
            id: "people-review-work-session",
            assetIDs: [fixture.insideFace.id, fixture.insidePlain.id],
            repository: fixture.repository
        )
        try fixture.model.selectSource(.workSession(session.id, titled: session.detail))
        fixture.model.selectLens(.people)

        try fixture.model.selectPeopleSignal(.faceCount)

        assertFaceReviewRoute(
            fixture.model,
            query: SetQuery(predicates: [
                .workSession(session.id.rawValue),
                .evaluationKind(.faceCount)
            ]),
            assetIDs: [fixture.insideFace.id]
        )
    }

    func testPeopleReviewFromAISuggestionsSnapshotsCurrentGhostIDsAndLoadsExactGrid() throws {
        var signaledGhost = makeAsset(id: "people-review-ai-signaled-ghost", path: "/Photos/AI/a-signaled.jpg")
        signaledGhost.metadata.flag = .pick
        signaledGhost.metadata.aiUnconfirmedFields = [.flag]
        var unsignaledGhost = makeAsset(id: "people-review-ai-unsignaled-ghost", path: "/Photos/AI/b-unsignaled.jpg")
        unsignaledGhost.metadata.flag = .pick
        unsignaledGhost.metadata.aiUnconfirmedFields = [.flag]
        let ordinaryOutside = makeAsset(id: "people-review-ai-ordinary", path: "/Photos/Outside/ordinary.jpg")
        var confirmedOutside = makeAsset(id: "people-review-ai-confirmed", path: "/Photos/Outside/confirmed.jpg")
        confirmedOutside.metadata.flag = .pick
        let (model, _) = try makeModelWithCatalogAssets(
            named: "people-review-ai",
            assets: [signaledGhost, unsignaledGhost, ordinaryOutside, confirmedOutside]
        ) { repository in
            try repository.recordEvaluationSignals(
                faceSignals(assetID: signaledGhost.id)
                    + faceSignals(assetID: ordinaryOutside.id)
                    + faceSignals(assetID: confirmedOutside.id)
            )
        }
        model.selectLens(.people)
        try model.selectSource(.autopilotSuggestions)
        let ghostIDs = model.autopilotGhostAssetIDs
        XCTAssertEqual(Set(ghostIDs), Set([signaledGhost.id, unsignaledGhost.id]))

        try model.selectPeopleSignal(.faceCount)

        assertFaceReviewRoute(
            model,
            query: SetQuery(predicates: [
                .assetIDs(ghostIDs),
                .evaluationKind(.faceCount)
            ]),
            assetIDs: [signaledGhost.id]
        )
    }

    func testSelectingAnotherPeopleSignalReplacesThePreviousKindOutsidePeople() throws {
        let faceCount = makeAsset(id: "people-review-replace-count", path: "/Photos/Signals/count.jpg")
        let faceQuality = makeAsset(id: "people-review-replace-quality", path: "/Photos/Signals/quality.jpg")
        let (model, _) = try makeModelWithCatalogAssets(
            named: "people-review-replace-kind",
            assets: [faceCount, faceQuality]
        ) { repository in
            try repository.recordEvaluationSignals([
                EvaluationSignal(
                    assetID: faceCount.id,
                    kind: .faceCount,
                    value: .count(1),
                    confidence: 0.9,
                    provenance: faceProvenance
                ),
                EvaluationSignal(
                    assetID: faceQuality.id,
                    kind: .faceQuality,
                    value: .score(0.8),
                    confidence: 0.8,
                    provenance: faceProvenance
                )
            ])
        }
        model.selectLens(.grid)

        try model.selectPeopleSignal(.faceCount)
        try model.selectPeopleSignal(.faceQuality)

        XCTAssertEqual(model.selectedLens, .grid)
        XCTAssertEqual(
            model.selectedSource.kind,
            .search(SetQuery(predicates: [.evaluationKind(.faceQuality)]))
        )
        XCTAssertEqual(model.assets.map(\.id), [faceQuality.id])
    }

    func testPeopleReviewFromEmptyAISuggestionsDoesNotFallBackToAllPhotos() throws {
        let outside = makeAsset(id: "people-review-empty-ai-outside", path: "/Photos/Outside/face.jpg")
        let (model, _) = try makeModelWithCatalogAssets(
            named: "people-review-empty-ai",
            assets: [outside]
        ) { repository in
            try repository.recordEvaluationSignals(faceSignals(assetID: outside.id))
        }
        model.selectLens(.people)
        try model.selectSource(.autopilotSuggestions)
        XCTAssertEqual(model.autopilotGhostAssetIDs, [])

        try model.selectPeopleSignal(.faceCount)

        assertFaceReviewRoute(
            model,
            query: SetQuery(predicates: [
                .assetIDs([]),
                .evaluationKind(.faceCount)
            ]),
            assetIDs: []
        )
    }

    func testShowingPersonPhotosIntersectsTheCurrentFolderScope() throws {
        let fixture = try makePersonDrillFixture(named: "people-person-folder")
        try fixture.model.selectSource(.folder("/Photos/Inside"))
        fixture.model.selectLens(.people)

        try fixture.model.showPersonPhotos(named: "Ada")

        assertPersonDrillRoute(
            fixture.model,
            query: SetQuery(predicates: [
                .folderPrefix("/Photos/Inside"),
                .person("Ada")
            ]),
            assetIDs: [fixture.inside.id],
            proposedAssetIDs: []
        )
    }

    func testShowingPersonPhotosPreservesPlainTextSourceScopeWithoutReinterpretingIt() throws {
        let inside = makeAsset(id: "people-person-text-inside", path: "/Photos/Inside/ada.jpg")
        var outside = makeAsset(id: "people-person-text-outside", path: "/Photos/Outside/ada.jpg")
        outside.metadata.flag = .pick
        let (model, _) = try makeModelWithCatalogAssets(
            named: "people-person-text",
            assets: [inside, outside]
        ) { repository in
            try repository.upsertPerson(id: "person-ada", name: "Ada")
            try repository.assignAssets([inside.id, outside.id], toPersonID: "person-ada")
            try repository.recordEvaluationSignals([
                EvaluationSignal(
                    assetID: inside.id,
                    kind: .ocrText,
                    value: .text("pick"),
                    confidence: 0.9,
                    provenance: faceProvenance
                )
            ])
        }
        let textSource = LibrarySource.search(
            SetQuery(predicates: [.text("pick")]),
            titled: "Pick text"
        )
        try model.selectSource(textSource)
        XCTAssertEqual(model.assets.map(\.id), [inside.id])
        model.selectLens(.people)

        try model.showPersonPhotos(named: "Ada")

        XCTAssertEqual(model.selectedLens, .grid)
        XCTAssertEqual(
            model.selectedSource,
            .search(SetQuery(predicates: [.text("pick"), .person("Ada")]), titled: "Ada")
        )
        XCTAssertEqual(model.assets.map(\.id), [inside.id])
        XCTAssertEqual(model.librarySearchText, "person:Ada")
        XCTAssertEqual(model.activeLibraryFilterChips, ["Search: pick", "Person: Ada"])
    }

    func testShowingPersonPhotosKeepsAnUnserializablePersonNameStructured() throws {
        let personName = "Ada \"Ace\" O'Neil"
        let inside = makeAsset(id: "people-person-quoted-inside", path: "/Photos/Inside/ada.jpg")
        let outside = makeAsset(id: "people-person-quoted-outside", path: "/Photos/Outside/plain.jpg")
        let (model, _) = try makeModelWithCatalogAssets(
            named: "people-person-quoted",
            assets: [inside, outside]
        ) { repository in
            try repository.upsertPerson(id: "person-ada", name: personName)
            try repository.assignAssets([inside.id], toPersonID: "person-ada")
        }
        model.selectLens(.people)

        try model.showPersonPhotos(named: personName)

        XCTAssertEqual(model.selectedLens, .grid)
        XCTAssertEqual(
            model.selectedSource,
            .search(SetQuery(predicates: [.person(personName)]), titled: personName)
        )
        XCTAssertEqual(model.assets.map(\.id), [inside.id])
        XCTAssertEqual(model.librarySearchText, "")
        XCTAssertEqual(model.activeLibraryFilterChips, ["Person: \(personName)"])

        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.map(\.id), [inside.id])
    }

    func testShowingPersonPhotosIntersectsPopulatedAndEmptyStaticSets() throws {
        let fixture = try makePersonDrillFixture(named: "people-person-static-sets")
        let populated = AssetSet.manual(
            id: AssetSetID(rawValue: "people-person-populated"),
            name: "Inside selection",
            assetIDs: [fixture.inside.id, fixture.insidePlain.id]
        )
        let empty = AssetSet.manual(
            id: AssetSetID(rawValue: "people-person-empty"),
            name: "Empty selection",
            assetIDs: []
        )
        try fixture.repository.upsert(populated)
        try fixture.repository.upsert(empty)
        try fixture.model.refreshSavedAssetSets()
        try fixture.model.selectSource(.assetSet(populated.id, titled: populated.name))
        fixture.model.selectLens(.people)

        try fixture.model.showPersonPhotos(named: "Ada")

        assertPersonDrillRoute(
            fixture.model,
            query: SetQuery(predicates: [
                .assetIDs([fixture.inside.id, fixture.insidePlain.id]),
                .person("Ada")
            ]),
            assetIDs: [fixture.inside.id],
            proposedAssetIDs: []
        )

        try fixture.model.selectSource(.assetSet(empty.id, titled: empty.name))
        fixture.model.selectLens(.people)
        try fixture.model.showPersonPhotos(named: "Ada")

        assertPersonDrillRoute(
            fixture.model,
            query: SetQuery(predicates: [.assetIDs([]), .person("Ada")]),
            assetIDs: [],
            proposedAssetIDs: []
        )
    }

    func testShowingPersonPhotosIntersectsARealImportWorkSession() throws {
        let fixture = try makePersonDrillFixture(named: "people-person-work-session")
        let session = try saveCompletedImport(
            id: "people-person-work-session",
            assetIDs: [fixture.inside.id, fixture.insidePlain.id],
            repository: fixture.repository
        )
        try fixture.model.selectSource(.workSession(session.id, titled: session.detail))
        fixture.model.selectLens(.people)

        try fixture.model.showPersonPhotos(named: "Ada")

        assertPersonDrillRoute(
            fixture.model,
            query: SetQuery(predicates: [
                .workSession(session.id.rawValue),
                .person("Ada")
            ]),
            assetIDs: [fixture.inside.id],
            proposedAssetIDs: []
        )
    }

    func testShowingPersonPhotosIntersectsPopulatedAndEmptyAISuggestions() throws {
        let fixture = try makePersonDrillFixture(named: "people-person-ai")
        fixture.model.selectLens(.people)
        try fixture.model.selectSource(.autopilotSuggestions)
        XCTAssertEqual(fixture.model.autopilotGhostAssetIDs, [fixture.inside.id])

        try fixture.model.showPersonPhotos(named: "Ada")

        assertPersonDrillRoute(
            fixture.model,
            query: SetQuery(predicates: [
                .assetIDs([fixture.inside.id]),
                .person("Ada")
            ]),
            assetIDs: [fixture.inside.id],
            proposedAssetIDs: []
        )

        try fixture.repository.updateMetadata(assetID: fixture.inside.id) { metadata in
            metadata.flag = nil
            metadata.aiUnconfirmedFields.remove(.flag)
        }
        try fixture.model.selectSource(.autopilotSuggestions)
        fixture.model.selectLens(.people)
        XCTAssertEqual(fixture.model.autopilotGhostAssetIDs, [])
        try fixture.model.showPersonPhotos(named: "Ada")

        assertPersonDrillRoute(
            fixture.model,
            query: SetQuery(predicates: [.assetIDs([]), .person("Ada")]),
            assetIDs: [],
            proposedAssetIDs: []
        )
    }

    func testShowingPersonPhotosOverAllPhotosKeepsTheLonePersonProposedPhotoSemantics() throws {
        let fixture = try makePersonDrillFixture(named: "people-person-all-photos")
        fixture.model.selectLens(.people)

        try fixture.model.showPersonPhotos(named: "Ada")

        assertPersonDrillRoute(
            fixture.model,
            query: SetQuery(predicates: [.person("Ada")]),
            assetIDs: [fixture.inside.id, fixture.outside.id],
            proposedAssetIDs: [fixture.proposed.id]
        )
    }

    func testModelPresentationScopesFaceSignalSummariesToFolderAndAllPhotos() throws {
        let fixture = try makeFaceSignalFixture(named: "people-presentation-folder")
        let globalSummaries = faceSignalSummaries(assetCount: 2)
        XCTAssertEqual(fixture.model.catalogEvaluationKindSummaries, globalSummaries)
        fixture.model.selectLens(.people)

        try fixture.model.selectSource(.folder("/Photos/Inside"))

        XCTAssertEqual(fixture.model.peopleEvaluationKindSummaries, faceSignalSummaries(assetCount: 1))
        XCTAssertEqual(fixture.model.catalogEvaluationKindSummaries, globalSummaries)
        var presentation = peoplePresentation(fixture.model)
        XCTAssertEqual(presentation.photosWithDetectedFaces, 1)
        XCTAssertEqual(presentation.photosWithFaceQualitySignals, 1)
        XCTAssertEqual(presentation.reviewCards.map(\.filterKind), [.faceCount, .faceQuality])

        try fixture.model.selectSource(.allPhotos)

        XCTAssertNil(try fixture.model.peopleScopeAssetIDs())
        XCTAssertEqual(fixture.model.peopleEvaluationKindSummaries, globalSummaries)
        XCTAssertEqual(fixture.model.catalogEvaluationKindSummaries, globalSummaries)
        presentation = peoplePresentation(fixture.model)
        XCTAssertEqual(presentation.photosWithDetectedFaces, 2)
        XCTAssertEqual(presentation.photosWithFaceQualitySignals, 2)
    }

    func testModelPresentationScopesFaceSignalsToStaticAndEmptySets() throws {
        let fixture = try makeFaceSignalFixture(named: "people-presentation-static-sets")
        let populated = AssetSet.manual(
            id: AssetSetID(rawValue: "people-presentation-populated"),
            name: "Inside selection",
            assetIDs: [fixture.insideFace.id, fixture.insidePlain.id]
        )
        let empty = AssetSet.manual(
            id: AssetSetID(rawValue: "people-presentation-empty"),
            name: "Empty selection",
            assetIDs: []
        )
        try fixture.repository.upsert(populated)
        try fixture.repository.upsert(empty)
        try fixture.model.refreshSavedAssetSets()
        fixture.model.selectLens(.people)

        try fixture.model.selectSource(.assetSet(populated.id, titled: populated.name))

        XCTAssertEqual(
            try fixture.model.peopleScopeAssetIDs(),
            [fixture.insideFace.id, fixture.insidePlain.id]
        )
        XCTAssertEqual(fixture.model.peopleEvaluationKindSummaries, faceSignalSummaries(assetCount: 1))
        XCTAssertEqual(peoplePresentation(fixture.model).reviewCards.map(\.filterKind), [.faceCount, .faceQuality])

        try fixture.model.selectSource(.assetSet(empty.id, titled: empty.name))

        XCTAssertEqual(try fixture.model.peopleScopeAssetIDs(), [])
        XCTAssertTrue(fixture.model.peopleEvaluationKindSummaries.isEmpty)
        XCTAssertEqual(fixture.model.catalogEvaluationKindSummaries, faceSignalSummaries(assetCount: 2))
        let presentation = peoplePresentation(fixture.model)
        XCTAssertEqual(presentation.photosWithFaceSignals, 0)
        XCTAssertEqual(presentation.reviewCards, [])
    }

    func testModelPresentationScopesFaceSignalsToARealImportWorkSession() throws {
        let fixture = try makeFaceSignalFixture(named: "people-presentation-import")
        let outputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "people-presentation-import-output"),
            name: "Imported photos",
            assetIDs: [fixture.insideFace.id, fixture.insidePlain.id]
        )
        let session = WorkSession(
            id: WorkSessionID(rawValue: "people-presentation-import"),
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: "Imported from /Cards/CARD-A",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [outputSet.id],
            completedUnitCount: 2,
            totalUnitCount: 2,
            failureCount: 0,
            issues: [],
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        try fixture.repository.upsert(outputSet)
        try fixture.repository.save(session)
        fixture.model.selectLens(.people)

        try fixture.model.selectSource(.workSession(session.id, titled: session.detail))

        XCTAssertEqual(fixture.model.selectedSource, .workSession(session.id, titled: session.detail))
        XCTAssertEqual(
            try fixture.model.peopleScopeAssetIDs(),
            [fixture.insideFace.id, fixture.insidePlain.id]
        )
        XCTAssertEqual(fixture.model.peopleEvaluationKindSummaries, faceSignalSummaries(assetCount: 1))
        XCTAssertEqual(fixture.model.catalogEvaluationKindSummaries, faceSignalSummaries(assetCount: 2))
        XCTAssertEqual(peoplePresentation(fixture.model).reviewCards.map(\.filterKind), [.faceCount, .faceQuality])
    }

    func testAISuggestionsRefreshPeoplePresentationImmediatelyIncludingTheZeroTransition() throws {
        var ghost = makeAsset(id: "people-ai-ghost", path: "/Photos/AI/ghost.jpg")
        ghost.metadata.flag = .pick
        ghost.metadata.aiUnconfirmedFields = [.flag]
        let outside = makeAsset(id: "people-ai-outside", path: "/Photos/Outside/face.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "people-presentation-ai",
            assets: [ghost, outside]
        ) { repository in
            try repository.recordEvaluationSignals(
                faceSignals(assetID: ghost.id) + faceSignals(assetID: outside.id)
            )
        }
        model.selectLens(.people)

        try model.selectSource(.autopilotSuggestions)

        XCTAssertEqual(model.autopilotGhostAssetIDs, [ghost.id])
        XCTAssertEqual(model.assets.map(\.id), [ghost.id])
        XCTAssertEqual(try model.peopleScopeAssetIDs(), [ghost.id])
        XCTAssertEqual(model.peopleEvaluationKindSummaries, faceSignalSummaries(assetCount: 1))
        XCTAssertEqual(model.catalogEvaluationKindSummaries, faceSignalSummaries(assetCount: 2))
        XCTAssertEqual(peoplePresentation(model).reviewCards.map(\.filterKind), [.faceCount, .faceQuality])

        try repository.updateMetadata(assetID: ghost.id) { metadata in
            metadata.flag = nil
            metadata.aiUnconfirmedFields.remove(.flag)
        }
        try model.applyLibraryFilters()

        XCTAssertEqual(model.autopilotGhostAssetIDs, [])
        XCTAssertEqual(model.assets.map(\.id), [])
        XCTAssertEqual(try model.peopleScopeAssetIDs(), [])
        XCTAssertTrue(model.peopleEvaluationKindSummaries.isEmpty)
        XCTAssertEqual(model.catalogEvaluationKindSummaries, faceSignalSummaries(assetCount: 2))
        XCTAssertEqual(peoplePresentation(model).reviewCards, [])
    }

    func testUnavailableSourceStatusOnlyDescribesRootsIntersectingThePeopleScope() throws {
        let rootContainer = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-people-source-roots-\(UUID().uuidString)", isDirectory: true)
        let healthyRoot = rootContainer.appendingPathComponent("Healthy", isDirectory: true)
        let unavailableRoot = rootContainer.appendingPathComponent("Unavailable", isDirectory: true)
        try FileManager.default.createDirectory(at: healthyRoot, withIntermediateDirectories: true)
        let healthy = makeAsset(id: "people-root-healthy", path: healthyRoot.appendingPathComponent("healthy.jpg").path)
        let unavailable = makeAsset(id: "people-root-unavailable", path: unavailableRoot.appendingPathComponent("unavailable.jpg").path)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "people-source-root-status",
            assets: [healthy, unavailable]
        ) { repository in
            try repository.recordSourceRoot(healthyRoot)
            try repository.recordSourceRoot(unavailableRoot)
        }
        let empty = AssetSet.manual(
            id: AssetSetID(rawValue: "people-root-empty"),
            name: "Empty selection",
            assetIDs: []
        )
        try repository.upsert(empty)
        try model.refreshSavedAssetSets()
        model.selectLens(.people)
        model.refreshPeopleFaceSuggestions()

        XCTAssertTrue(model.hasUnavailableSourceRoots)
        XCTAssertTrue(model.peopleHasUnavailableSources)
        XCTAssertEqual(peoplePresentation(model).reviewStripStatusText, "Photo sources offline — reconnect to scan")

        try model.selectSource(.folder(healthyRoot.path))

        XCTAssertTrue(model.hasUnavailableSourceRoots, "the unrelated unavailable catalog root remains a global fact")
        XCTAssertFalse(model.peopleHasUnavailableSources)
        XCTAssertEqual(peoplePresentation(model).reviewStripStatusText, "0 queues")

        try model.selectSource(.folder(unavailableRoot.path))

        XCTAssertTrue(model.peopleHasUnavailableSources)
        XCTAssertEqual(peoplePresentation(model).reviewStripStatusText, "Photo sources offline — reconnect to scan")

        try model.selectSource(.assetSet(empty.id, titled: empty.name))

        XCTAssertEqual(try model.peopleScopeAssetIDs(), [])
        XCTAssertFalse(model.peopleHasUnavailableSources)
        XCTAssertEqual(peoplePresentation(model).reviewStripStatusText, "0 queues")
    }

    func testReconnectSourceRootRefreshesScopedPeopleOfflineStatusImmediately() throws {
        let rootContainer = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-people-source-reconnect-\(UUID().uuidString)", isDirectory: true)
        let oldRoot = rootContainer.appendingPathComponent("Unavailable", isDirectory: true)
        let newRoot = rootContainer.appendingPathComponent("Reconnected", isDirectory: true)
        let newOriginalURL = newRoot.appendingPathComponent("Job/ada.jpg")
        try FileManager.default.createDirectory(
            at: newOriginalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("same original bytes".utf8).write(to: newOriginalURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: newOriginalURL.path)
        let asset = Asset(
            id: AssetID(rawValue: "people-source-reconnect"),
            originalURL: oldRoot.appendingPathComponent("Job/ada.jpg"),
            volumeIdentifier: "Unavailable",
            fingerprint: FileFingerprint(
                size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                modificationDate: attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
            ),
            availability: .missing,
            metadata: AssetMetadata()
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "people-source-reconnect",
            assets: [asset]
        ) { repository in
            try repository.recordSourceRoot(oldRoot)
        }
        let scopedSource = LibrarySource.search(
            SetQuery(predicates: [.assetIDs([asset.id])]),
            titled: "Unavailable source"
        )
        model.selectLens(.people)
        try model.selectSource(scopedSource)
        XCTAssertTrue(model.peopleHasUnavailableSources)
        XCTAssertEqual(peoplePresentation(model).reviewStripStatusText, "Photo sources offline — reconnect to scan")

        let result = try model.reconnectSourceRoot(from: oldRoot, to: newRoot)

        XCTAssertEqual(result.reconnectedAssetCount, 1)
        XCTAssertEqual(model.selectedLens, .people)
        XCTAssertEqual(model.selectedSource, scopedSource)
        XCTAssertEqual(model.assets.map(\.id), [asset.id])
        XCTAssertEqual(model.assets.map(\.originalURL), [newOriginalURL])
        XCTAssertFalse(model.peopleHasUnavailableSources)
        XCTAssertEqual(peoplePresentation(model).reviewStripStatusText, "0 queues")
    }

    func testScopedNamedPeopleKeepGlobalMergeCandidatesAndKeyFaceIdentity() throws {
        let inside = makeAsset(id: "people-identity-inside", path: "/Photos/Inside/ada.jpg")
        let outside = makeAsset(id: "people-identity-outside", path: "/Photos/Outside/grace.jpg")
        let (model, _) = try makeModelWithCatalogAssets(
            named: "people-identity-scope",
            assets: [inside, outside]
        ) { repository in
            try repository.replaceFaceObservations(
                assetID: inside.id,
                provenance: AppleVisionEvaluationProvider.faceProvenance,
                with: [faceObservation(asset: inside, embedding: [1, 0, 0])]
            )
            try repository.replaceFaceObservations(
                assetID: outside.id,
                provenance: AppleVisionEvaluationProvider.faceProvenance,
                with: [faceObservation(asset: outside, embedding: [0, 1, 0])]
            )
            try repository.upsertPerson(id: "person-ada", name: "Ada")
            try repository.upsertPerson(id: "person-grace", name: "Grace")
            try repository.assignFaces([FaceID(assetID: inside.id, faceIndex: 0)], toPersonID: "person-ada")
            try repository.assignFaces([FaceID(assetID: outside.id, faceIndex: 0)], toPersonID: "person-grace")
        }
        model.selectLens(.people)

        try model.selectSource(.folder("/Photos/Inside"))

        let presentation = peoplePresentation(model)
        let mergeCandidates: [NamedPersonPresentation] = presentation.mergeCandidates
        let mergeTargets: [NamedPersonPresentation] = presentation.mergeTargets(for: "person-ada")
        XCTAssertEqual(presentation.namedPeople.map(\.name), ["Ada"])
        XCTAssertEqual(presentation.namedPeople.map(\.keyFace?.assetID), [inside.id])
        XCTAssertEqual(Set(mergeCandidates.map(\.name)), Set(["Ada", "Grace"]))
        XCTAssertEqual(
            Set(mergeCandidates.compactMap(\.keyFace?.assetID)),
            Set([inside.id, outside.id])
        )
        XCTAssertEqual(mergeTargets.map(\.name), ["Grace"])
        XCTAssertEqual(mergeTargets.map(\.keyFace?.assetID), [outside.id])
        XCTAssertEqual(Set(model.catalogPeople.map(\.name)), Set(["Ada", "Grace"]))
        XCTAssertEqual(Set(model.personKeyFaces.values.map(\.assetID)), Set([inside.id, outside.id]))
    }

    // MARK: - Fixtures

    private func makeAsset(id: String, path: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(id.count + 1), modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    private func makeFaceSignalFixture(
        named name: String
    ) throws -> (
        model: AppModel,
        repository: CatalogRepository,
        insideFace: Asset,
        insidePlain: Asset,
        outsideFace: Asset
    ) {
        let insideFace = makeAsset(id: "\(name)-inside-face", path: "/Photos/Inside/face.jpg")
        let insidePlain = makeAsset(id: "\(name)-inside-plain", path: "/Photos/Inside/plain.jpg")
        let outsideFace = makeAsset(id: "\(name)-outside-face", path: "/Photos/Outside/face.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: name,
            assets: [insideFace, insidePlain, outsideFace]
        ) { repository in
            try repository.recordEvaluationSignals(
                faceSignals(assetID: insideFace.id) + faceSignals(assetID: outsideFace.id)
            )
        }
        return (model, repository, insideFace, insidePlain, outsideFace)
    }

    private func makePersonDrillFixture(
        named name: String
    ) throws -> (
        model: AppModel,
        repository: CatalogRepository,
        inside: Asset,
        insidePlain: Asset,
        outside: Asset,
        proposed: Asset
    ) {
        var inside = makeAsset(id: "\(name)-inside", path: "/Photos/Inside/ada.jpg")
        inside.metadata.flag = .pick
        inside.metadata.aiUnconfirmedFields = [.flag]
        let insidePlain = makeAsset(id: "\(name)-inside-plain", path: "/Photos/Inside/plain.jpg")
        let outside = makeAsset(id: "\(name)-outside", path: "/Photos/Outside/ada.jpg")
        let proposed = makeAsset(id: "\(name)-proposed", path: "/Photos/Proposed/ada.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: name,
            assets: [inside, insidePlain, outside, proposed]
        ) { repository in
            try repository.upsertPerson(id: "person-ada", name: "Ada")
            try repository.assignAssets([inside.id, outside.id], toPersonID: "person-ada")
            try repository.insertAIFace(assetID: proposed.id, faceIndex: 0, personID: "person-ada")
        }
        return (model, repository, inside, insidePlain, outside, proposed)
    }

    private func saveCompletedImport(
        id: String,
        assetIDs: [AssetID],
        repository: CatalogRepository
    ) throws -> WorkSession {
        let outputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "\(id)-output"),
            name: "Imported photos",
            assetIDs: assetIDs
        )
        let session = WorkSession(
            id: WorkSessionID(rawValue: id),
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: "Imported from /Cards/CARD-A",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [outputSet.id],
            completedUnitCount: assetIDs.count,
            totalUnitCount: assetIDs.count,
            failureCount: 0,
            issues: [],
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        try repository.upsert(outputSet)
        try repository.save(session)
        return session
    }

    private func faceSignals(assetID: AssetID) -> [EvaluationSignal] {
        [
            EvaluationSignal(
                assetID: assetID,
                kind: .faceCount,
                value: .count(1),
                confidence: 0.9,
                provenance: faceProvenance
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .faceQuality,
                value: .score(0.8),
                confidence: 0.8,
                provenance: faceProvenance
            )
        ]
    }

    private func faceSignalSummaries(assetCount: Int) -> [CatalogEvaluationKindSummary] {
        [
            CatalogEvaluationKindSummary(kind: .faceCount, assetCount: assetCount),
            CatalogEvaluationKindSummary(kind: .faceQuality, assetCount: assetCount)
        ]
    }

    private func faceObservation(asset: Asset, embedding: [Double]) -> CatalogFaceObservation {
        CatalogFaceObservation(
            assetID: asset.id,
            faceIndex: 0,
            boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            captureQuality: 0.9,
            embedding: embedding,
            provenance: AppleVisionEvaluationProvider.faceProvenance
        )
    }

    private func peoplePresentation(_ model: AppModel) -> PeoplePresentation {
        PeoplePresentation(model: model)
    }

    private func assertFaceReviewRoute(
        _ model: AppModel,
        query: SetQuery,
        assetIDs: [AssetID],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(model.selectedLens, .grid, file: file, line: line)
        XCTAssertEqual(
            model.selectedSource,
            .search(query, titled: SmartCollection.facesFound.presentation.title),
            file: file,
            line: line
        )
        XCTAssertEqual(Set(model.assets.map(\.id)), Set(assetIDs), file: file, line: line)
    }

    private func assertPersonDrillRoute(
        _ model: AppModel,
        query: SetQuery,
        assetIDs: [AssetID],
        proposedAssetIDs: [AssetID],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(model.selectedLens, .grid, file: file, line: line)
        XCTAssertEqual(model.selectedSource, .search(query, titled: "Ada"), file: file, line: line)
        XCTAssertEqual(Set(model.assets.map(\.id)), Set(assetIDs), file: file, line: line)
        XCTAssertEqual(Set(model.proposedPhotos.map(\.asset.id)), Set(proposedAssetIDs), file: file, line: line)
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset],
        configureRepository: (CatalogRepository) throws -> Void = { _ in }
    ) throws -> (AppModel, CatalogRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-people-scoping-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        try configureRepository(repository)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: nil)
        return (model, repository)
    }
}
