import XCTest
@testable import TeststripCore
@testable import TeststripApp

/// Applies the derived-state consistency pattern
/// (`DerivedStateConsistency.swift`) to the mutating actions on each surface the
/// four-persona review found defects on: a scoped cull pass (and its
/// auto-advance), the People review queue, and plain-text search. Each test
/// drives real mutations and then asserts the model's derived state against a
/// fresh catalog query.
final class DerivedStateConsistencyTests: XCTestCase {

    // MARK: - Cull surface: scoped HUD counts + scope line

    /// Deciding a frame inside a scoped pass (with auto-advance on) must leave
    /// the HUD's ✓/✕/undecided cluster and the scope line agreeing with the
    /// catalog. The original defect: the cluster showed whole-session numbers
    /// even in a filtered scope.
    func testCullHUDAndScopeLineStayConsistentWithCatalogAcrossScopedDecisions() throws {
        let pick = makeAsset(id: "p1", path: "/Photos/Job/p1.cr2", flag: .pick)
        let reject = makeAsset(id: "r1", path: "/Photos/Job/r1.cr2", flag: .reject)
        let undecidedA = makeAsset(id: "u1", path: "/Photos/Job/u1.cr2", flag: nil)
        let undecidedB = makeAsset(id: "u2", path: "/Photos/Job/u2.cr2", flag: nil)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "derived-cull-hud",
            assets: [pick, reject, undecidedA, undecidedB]
        )
        try model.beginCullingSession(named: "Derived state")
        model.cycleCullScope() // .all -> .unrated
        XCTAssertEqual(model.cullScope, .unrated)
        model.select(undecidedA.id)

        try assertCullHUDMatchesCatalog(model, repository: repository)
        try assertCullScopeLineMatchesCatalog(model, repository: repository)

        // Decide in the scoped pass. Auto-advance moves the selection out of
        // the decided frame; the derived counts must follow the catalog.
        try model.applyCullingShortcut(.pick)
        XCTAssertEqual(try repository.asset(id: undecidedA.id).metadata.flag, .pick)
        try assertCullHUDMatchesCatalog(model, repository: repository)
        try assertCullScopeLineMatchesCatalog(model, repository: repository)

        model.cycleCullScope() // .unrated -> .picks
        XCTAssertEqual(model.cullScope, .picks)
        try assertCullHUDMatchesCatalog(model, repository: repository)

        model.cycleCullScope() // .picks -> .rejects
        XCTAssertEqual(model.cullScope, .rejects)
        try assertCullHUDMatchesCatalog(model, repository: repository)
    }

    // MARK: - Cull surface: stack rail vs the scoped partition

    /// The stack rail's "Stack N of M" must equal a partition rebuilt from the
    /// visible (scope-filtered) assets after a decision + scope change — the
    /// pre-fix rail counted the unfiltered set.
    func testCullingStackRailTracksScopedPartitionAfterDecision() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let burstALead = makeStackAsset(id: "a1", capturedAt: capturedAt, offset: 0, flag: nil)
        let burstAMate = makeStackAsset(id: "a2", capturedAt: capturedAt, offset: 1, flag: nil)
        let burstBLead = makeStackAsset(id: "b1", capturedAt: capturedAt, offset: 60, flag: .pick)
        let burstBMate = makeStackAsset(id: "b2", capturedAt: capturedAt, offset: 61, flag: .pick)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "derived-stack-rail",
            assets: [burstALead, burstAMate, burstBLead, burstBMate]
        )
        try model.beginCullingSession(named: "Rail")
        model.select(burstALead.id)

        // .all: both bursts are visible → the rail counts both.
        assertCullingStackRailMatchesScopedPartition(model)

        // Decide a1; auto-advance lands on a2 (still inside burst A).
        try model.applyCullingShortcut(.pick)

        // .unrated: a1 is now out of scope, so burst A has only a2 visible —
        // no in-scope burstmates, so the rail reads Standalone.
        model.cycleCullScope() // .all -> .unrated
        XCTAssertEqual(model.cullScope, .unrated)
        assertCullingStackRailMatchesScopedPartition(model)

        // .picks: burst B is the only visible multi-frame stack; a1 (now a
        // pick) is a singleton.
        model.cycleCullScope() // .unrated -> .picks
        XCTAssertEqual(model.cullScope, .picks)
        assertCullingStackRailMatchesScopedPartition(model)

        // .rejects: nothing is visible, so there is no selection and no rail.
        model.cycleCullScope() // .picks -> .rejects
        XCTAssertEqual(model.cullScope, .rejects)
        assertCullingStackRailMatchesScopedPartition(model)
    }

    // MARK: - People surface: confirm a person, then work the review queue

    /// Confirming a matched person must leave the People lens showing exactly
    /// what `person_assets` holds, and navigating into (and back out of) the
    /// face-review queue must not drop that person — the pre-fix lens scope
    /// lost every confirmed person on return.
    func testPeopleLensTracksCatalogAcrossConfirmAndReviewQueue() throws {
        let provenance = AppleVisionEvaluationProvider.faceProvenance
        let known = makeAsset(id: "known", path: "/Volumes/NAS/Wedding/known.jpg", flag: nil)
        let incoming = makeAsset(id: "incoming", path: "/Volumes/NAS/Wedding/incoming.jpg", flag: nil)
        let clusterA = makeAsset(id: "cluster-a", path: "/Volumes/NAS/Wedding/cluster-a.jpg", flag: nil)
        let clusterB = makeAsset(id: "cluster-b", path: "/Volumes/NAS/Wedding/cluster-b.jpg", flag: nil)

        let (model, repository) = try makeModelWithCatalogAssets(
            named: "derived-people-lens",
            assets: [known, incoming, clusterA, clusterB]
        ) { repository in
            try repository.replaceFaceObservations(assetID: known.id, provenance: provenance, with: [
                Self.faceObservation(assetID: known.id, embedding: [1, 0, 0], provenance: provenance)
            ])
            try repository.replaceFaceObservations(assetID: incoming.id, provenance: provenance, with: [
                Self.faceObservation(assetID: incoming.id, embedding: [0.99, 0.1, 0], provenance: provenance)
            ])
            try repository.replaceFaceObservations(assetID: clusterA.id, provenance: provenance, with: [
                Self.faceObservation(assetID: clusterA.id, embedding: [0, 1, 0], provenance: provenance)
            ])
            try repository.replaceFaceObservations(assetID: clusterB.id, provenance: provenance, with: [
                Self.faceObservation(assetID: clusterB.id, embedding: [0, 0.99, 0.14], provenance: provenance)
            ])
            try repository.recordEvaluationSignals(
                [known, incoming, clusterA, clusterB].flatMap { Self.faceSignals(assetID: $0.id) }
            )
            try repository.upsertPerson(id: "person-maya", name: "Maya")
            try repository.assignFaces([FaceID(assetID: known.id, faceIndex: 0)], toPersonID: "person-maya")
        }
        model.selectLens(.people)
        model.refreshPeopleFaceSuggestions()

        // Seed state: Maya (1 photo) is the only confirmed person.
        try assertPeopleLensMatchesCatalog(model, repository: repository)
        XCTAssertEqual(try repository.people(assetIDs: nil).map(\.assetCount), [1])

        // Confirm the matched face group through the queue's confirm gesture.
        let match = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })
        try model.confirmPeopleFaceSuggestion(match)
        model.refreshPeopleFaceSuggestions()

        try assertPeopleLensMatchesCatalog(model, repository: repository)
        XCTAssertEqual(
            try repository.people(assetIDs: nil).first { $0.id == "person-maya" }?.assetCount, 2,
            "the confirm gesture must write the second photo to person_assets"
        )

        // The queue's remaining face suggestions must cover exactly the
        // catalog's unassigned faces — nothing confirmed lingers, nothing
        // unassigned is dropped.
        let suggestionFaces = Set(model.peopleFaceSuggestions.flatMap(\.faceIDs))
        let unassignedFaces = Set(
            try repository.unassignedFaceObservations(provenance: provenance, limit: 100).map(\.faceID)
        )
        XCTAssertEqual(suggestionFaces, unassignedFaces)

        // Work the review queue (the face-signal source deliberately excludes
        // person-assigned assets), then return to People: the confirmed person
        // must still be listed.
        try model.selectPeopleSignal(.faceCount)
        model.selectLens(.people)
        model.refreshPeopleFaceSuggestions()

        try assertPeopleLensMatchesCatalog(model, repository: repository)
        XCTAssertEqual(
            model.peopleInCurrentSource.map(\.id), ["person-maya"],
            "a confirmed person must survive a round trip through the face-review queue"
        )
    }

    // MARK: - Search surface: keyword/caption plain-text matches

    /// The result header's match count must equal a fresh repository count for
    /// the live search, for matches that come from metadata keywords/captions —
    /// the pre-fix plain-text search matched only file names and signals.
    func testLibraryResultHeaderTracksCatalogForKeywordAndCaptionSearch() throws {
        let keywordHit = makeAsset(
            id: "keyword-hit",
            path: "/Volumes/NAS/Job/frame-001.jpg",
            flag: nil,
            metadata: AssetMetadata(rating: 0, keywords: ["batch-0"])
        )
        let captionHit = makeAsset(
            id: "caption-hit",
            path: "/Volumes/NAS/Job/frame-002.jpg",
            flag: nil,
            metadata: AssetMetadata(rating: 0, caption: "Smoke frame 4")
        )
        let filenameHit = makeAsset(id: "filename-hit", path: "/Volumes/NAS/Job/beach-sunset.jpg", flag: nil)
        let miss = makeAsset(id: "miss", path: "/Volumes/NAS/Job/frame-003.jpg", flag: nil)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "derived-search-header",
            assets: [keywordHit, captionHit, filenameHit, miss]
        )

        try search("batch-0", in: model)
        try assertLibraryResultHeaderMatchesCatalog(model, repository: repository)
        XCTAssertEqual(model.assets.map(\.id), [keywordHit.id], "keyword search must find the keyword hit")

        try search("smoke frame 4", in: model)
        try assertLibraryResultHeaderMatchesCatalog(model, repository: repository)
        XCTAssertEqual(model.assets.map(\.id), [captionHit.id], "caption search must find the caption hit")

        try search("BEACH-SUNSET", in: model)
        try assertLibraryResultHeaderMatchesCatalog(model, repository: repository)
        XCTAssertEqual(model.assets.map(\.id), [filenameHit.id], "filename search must stay case-insensitive")

        try search("no-such-token-anywhere", in: model)
        try assertLibraryResultHeaderMatchesCatalog(model, repository: repository)
        XCTAssertTrue(model.assets.isEmpty)
        let header = LibraryResultHeaderPresentation(
            totalAssetCount: model.totalAssetCount,
            librarySearchText: model.librarySearchText,
            canSaveDynamicSet: model.canSaveCurrentLibraryQuery,
            canSaveSnapshotSet: model.canSaveCurrentAssetScopeSnapshot,
            canSaveManualSet: model.canSaveSelectedAssetAsManualSet
        )
        XCTAssertTrue(header.isZeroMatchSearch, "a genuine miss must render the explicit no-matches state")
    }

    // MARK: - Fixtures

    private func search(_ text: String, in model: AppModel) throws {
        model.librarySearchText = text
        try model.applyLibraryFilters()
    }

    private func makeAsset(
        id: String,
        path: String,
        flag: PickFlag?,
        metadata: AssetMetadata? = nil
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "NAS",
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: metadata ?? AssetMetadata(flag: flag)
        )
    }

    private func makeStackAsset(id: String, capturedAt: Date, offset: TimeInterval, flag: PickFlag?) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/Job/\(id).cr2"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(flag: flag),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                capturedAt: capturedAt.addingTimeInterval(offset),
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        )
    }

    private static func faceObservation(
        assetID: AssetID,
        embedding: [Double],
        provenance: ProviderProvenance
    ) -> CatalogFaceObservation {
        CatalogFaceObservation(
            assetID: assetID,
            faceIndex: 0,
            boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            captureQuality: 0.9,
            embedding: embedding,
            provenance: provenance
        )
    }

    private static func faceSignals(assetID: AssetID) -> [EvaluationSignal] {
        let provenance = AppleVisionEvaluationProvider.faceProvenance
        return [
            EvaluationSignal(assetID: assetID, kind: .faceCount, value: .count(1), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .faceQuality, value: .score(0.8), confidence: 0.8, provenance: provenance)
        ]
    }
}
