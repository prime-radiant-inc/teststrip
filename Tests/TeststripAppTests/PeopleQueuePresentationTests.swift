import SwiftUI
import XCTest
@testable import TeststripCore
@testable import TeststripApp

/// Covers Task 21's People queue keyboard flow: suggestion cards and review
/// cards folded into one focus-navigable queue, ←/→ wrapping focus, and
/// Return as the sole confirm gesture — it must act on the focused card only
/// and must never write to `people`/`person_assets` on its own (routing a
/// command through the queue is not the same as executing the write; the
/// write only happens once AppModel executes the routed action).
final class PeopleQueuePresentationTests: XCTestCase {
    private func suggestionCard(_ id: String, isOneTapConfirm: Bool = true) -> PeopleFaceSuggestionCard {
        let suggestion = PeopleFaceSuggestion(
            id: id,
            kind: isOneTapConfirm ? .matchExisting(personID: "person-\(id)", personName: "Name-\(id)") : .newPerson,
            faceIDs: [FaceID(assetID: AssetID(rawValue: id), faceIndex: 0)],
            representativeFace: FaceID(assetID: AssetID(rawValue: id), faceIndex: 0),
            representativeBoundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            assetIDs: [AssetID(rawValue: id)]
        )
        return PeopleFaceSuggestionCard(
            id: id,
            title: isOneTapConfirm ? "Is this Name-\(id)?" : "Who is this?",
            countText: "1 face · 1 photo",
            confirmActionTitle: isOneTapConfirm ? "Name-\(id)" : "Name…",
            isOneTapConfirm: isOneTapConfirm,
            suggestion: suggestion
        )
    }

    private func reviewCard(_ id: String) -> PeopleReviewCard {
        PeopleReviewCard(
            id: id,
            title: id,
            countText: "1 photo",
            suggestedActionTitle: "Review",
            filterKind: .faceCount,
            target: .reviewQueue(.facesFound),
            gradientColors: [.orange]
        )
    }

    // MARK: - Focus wrap

    func testFocusWrapsForwardPastTheLastCard() {
        let presentation = PeopleQueuePresentation(
            suggestionCards: [suggestionCard("a"), suggestionCard("b")],
            reviewCards: [reviewCard("c")]
        )
        XCTAssertEqual(presentation.focusedIndex, 0)

        let advanced = presentation
            .movingFocus(.next)
            .movingFocus(.next)
            .movingFocus(.next)

        XCTAssertEqual(advanced.focusedIndex, 0)
    }

    func testFocusWrapsBackwardBeforeTheFirstCard() {
        let presentation = PeopleQueuePresentation(
            suggestionCards: [suggestionCard("a"), suggestionCard("b")],
            reviewCards: []
        )

        let moved = presentation.movingFocus(.previous)

        XCTAssertEqual(moved.focusedIndex, 1)
    }

    func testEmptyQueueFocusMoveIsANoOp() {
        let presentation = PeopleQueuePresentation(suggestionCards: [], reviewCards: [])

        XCTAssertEqual(presentation.movingFocus(.next).focusedIndex, 0)
        XCTAssertNil(presentation.focusedCard)
    }

    // MARK: - Return confirms only the focused card

    func testConfirmActionTargetsOnlyTheFocusedSuggestionCard() {
        let presentation = PeopleQueuePresentation(
            suggestionCards: [suggestionCard("a"), suggestionCard("b")],
            reviewCards: [],
            focusedIndex: 1
        )

        let action = presentation.confirmAction()

        XCTAssertEqual(action, .confirmSuggestion(suggestionCard("b").suggestion))
    }

    func testConfirmActionRoutesNameableSuggestionsToNamingInsteadOfWriting() {
        let presentation = PeopleQueuePresentation(
            suggestionCards: [suggestionCard("a", isOneTapConfirm: false)],
            reviewCards: []
        )

        XCTAssertEqual(presentation.confirmAction(), .nameSuggestion(suggestionCard("a", isOneTapConfirm: false).suggestion))
    }

    func testConfirmActionOnFocusedReviewCardSelectsItsQueue() {
        let presentation = PeopleQueuePresentation(
            suggestionCards: [],
            reviewCards: [reviewCard("unnamed-faces")]
        )

        XCTAssertEqual(presentation.confirmAction(), .selectReview(.reviewQueue(.facesFound)))
    }

    func testConfirmActionOnEmptyQueueIsNone() {
        let presentation = PeopleQueuePresentation(suggestionCards: [], reviewCards: [])
        XCTAssertEqual(presentation.confirmAction(), .none)
    }

    // MARK: - Esc dismisses focus, never writes

    func testDismissActionDismissesFocusedSuggestionOnly() {
        let presentation = PeopleQueuePresentation(
            suggestionCards: [suggestionCard("a"), suggestionCard("b")],
            reviewCards: [],
            focusedIndex: 0
        )

        XCTAssertEqual(presentation.dismissAction(), .dismissSuggestion(suggestionCard("a").suggestion))
    }

    func testDismissActionOnReviewCardIsANoOp() {
        let presentation = PeopleQueuePresentation(
            suggestionCards: [],
            reviewCards: [reviewCard("unnamed-faces")]
        )

        XCTAssertEqual(presentation.dismissAction(), .none)
    }

    func testEscapeOnFocusedReviewCardAdvancesFocusToNextCardWrapping() {
        let presentation = PeopleQueuePresentation(
            suggestionCards: [],
            reviewCards: [reviewCard("unnamed-faces"), reviewCard("face-quality")],
            focusedIndex: 0
        )

        let advanced = presentation.focusAfterEscape()

        XCTAssertEqual(advanced.focusedIndex, 1)

        // Wraps back to 0 from the last card.
        let wrapped = advanced.focusAfterEscape()
        XCTAssertEqual(wrapped.focusedIndex, 0)
    }

    func testEscapeOnFocusedSuggestionCardDoesNotMoveFocus() {
        // Esc on a suggestion card still dismisses it (via dismissAction());
        // focus itself doesn't need to move here.
        let presentation = PeopleQueuePresentation(
            suggestionCards: [suggestionCard("a"), suggestionCard("b")],
            reviewCards: [],
            focusedIndex: 0
        )

        XCTAssertEqual(presentation.focusAfterEscape().focusedIndex, 0)
    }

    // MARK: - Negative-invariant integration: only Return-routed confirms write

    private func makeFaceSuggestionModel(
        named name: String
    ) throws -> (model: AppModel, repository: CatalogRepository, known: Asset, incoming: Asset, groupA: Asset, groupB: Asset) {
        let known = makeAsset(id: "known", path: "/Volumes/NAS/Wedding/known.jpg")
        let incoming = makeAsset(id: "incoming", path: "/Volumes/NAS/Wedding/incoming.jpg")
        let groupA = makeAsset(id: "group-a", path: "/Volumes/NAS/Wedding/group-a.jpg")
        let groupB = makeAsset(id: "group-b", path: "/Volumes/NAS/Wedding/group-b.jpg")
        let provenance = AppleVisionEvaluationProvider.faceProvenance
        func observation(_ asset: Asset, _ embedding: [Double]) -> CatalogFaceObservation {
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: 0,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                captureQuality: 0.9,
                embedding: embedding,
                provenance: provenance
            )
        }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: name,
            assets: [known, incoming, groupA, groupB],
            configureRepository: { repository in
                try repository.replaceFaceObservations(assetID: known.id, provenance: provenance, with: [observation(known, [1, 0, 0])])
                try repository.replaceFaceObservations(assetID: incoming.id, provenance: provenance, with: [observation(incoming, [0.99, 0.1, 0])])
                try repository.replaceFaceObservations(assetID: groupA.id, provenance: provenance, with: [observation(groupA, [0, 1, 0])])
                try repository.replaceFaceObservations(assetID: groupB.id, provenance: provenance, with: [observation(groupB, [0, 0.99, 0.14])])
                try repository.upsertPerson(id: "person-maya", name: "Maya")
                try repository.assignFaces([FaceID(assetID: known.id, faceIndex: 0)], toPersonID: "person-maya")
            }
        )
        return (model, repository, known, incoming, groupA, groupB)
    }

    func testReturnAppliedThroughTheQueueWritesOnlyTheFocusedSuggestion() throws {
        let (model, repository, known, incoming, groupA, groupB) = try makeFaceSuggestionModel(named: "people-queue-return-confirms-focused")
        model.refreshPeopleFaceSuggestions()
        let presentation = PeopleQueuePresentation(
            suggestionCards: model.peopleFaceSuggestions.map { suggestionCardFrom($0) },
            reviewCards: []
        )
        let matchCard = try XCTUnwrap(presentation.cards.first { $0.id == "face-match-person-maya" })
        let focusedOnMatch = PeopleQueuePresentation(
            suggestionCards: presentation.cards.compactMap { if case .suggestion(let card) = $0.kind { return card } else { return nil } },
            reviewCards: [],
            focusedIndex: presentation.cards.firstIndex(of: matchCard) ?? 0
        )

        // NEGATIVE ASSERTION: focus movement and queue construction alone
        // must never write to the people tables — only an explicit Return
        // (applied below) does.
        XCTAssertEqual(try repository.people().count, 1) // only the pre-seeded Maya, nothing confirmed yet
        XCTAssertEqual(try repository.assetIDs(personID: "person-maya"), [known.id]) // fixture seed, not a Return write

        guard case .confirmSuggestion(let suggestion) = focusedOnMatch.confirmAction() else {
            return XCTFail("expected the focused match card to confirm directly")
        }
        try model.confirmPeopleFaceSuggestion(suggestion)

        // The focused (match) suggestion was written…
        XCTAssertEqual(try repository.assetIDs(personID: "person-maya"), [known.id, incoming.id])
        // …but the un-focused cluster suggestion was left untouched: no new
        // person was created for groupA/groupB.
        XCTAssertNil(model.catalogPeople.first { $0.name != "Maya" })
        XCTAssertTrue(model.peopleFaceSuggestions.contains { $0.faceIDs.contains(FaceID(assetID: groupA.id, faceIndex: 0)) })
        XCTAssertTrue(model.peopleFaceSuggestions.contains { $0.faceIDs.contains(FaceID(assetID: groupB.id, faceIndex: 0)) })
    }

    private func suggestionCardFrom(_ suggestion: PeopleFaceSuggestion) -> PeopleFaceSuggestionCard {
        switch suggestion.kind {
        case .matchExisting(_, let personName):
            return PeopleFaceSuggestionCard(
                id: suggestion.id,
                title: "Is this \(personName)?",
                countText: "",
                confirmActionTitle: personName,
                isOneTapConfirm: true,
                suggestion: suggestion
            )
        case .newPerson:
            return PeopleFaceSuggestionCard(
                id: suggestion.id,
                title: "Who is this?",
                countText: "",
                confirmActionTitle: "Name…",
                isOneTapConfirm: false,
                suggestion: suggestion
            )
        }
    }

    // MARK: - Test support

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset],
        configureRepository: (CatalogRepository) throws -> Void = { _ in }
    ) throws -> (AppModel, CatalogRepository) {
        let directory = try makeTemporaryDirectory(named: name)
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
        let model = try AppModel.load(catalog: catalog)
        return (model, repository)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-people-queue-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeAsset(id: String, path: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Test",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(rating: 0)
        )
    }
}
