import Observation
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// Task 18: Compare refill. Rejecting a frame in Compare removes it from the
// survey and, if the same candidate stack has an undecided sibling not
// already shown, pulls it in to backfill the slot — until the stack runs
// out. Entering Compare from a stack also auto-populates recommended-first,
// capped at 8.
final class CompareRefillTests: XCTestCase {
    func testRejectingAFrameRefillsFromTheSameStack() throws {
        let capturedAt = Date(timeIntervalSince1970: 300)
        // Nine frames in the same folder, captured a second apart: one stack
        // of nine, one more than the 8-frame compare cap.
        let frames = (0..<9).map { index in
            makeAsset(
                id: "refill-frame-\(index)",
                path: "/Photos/Job/refill-frame-\(index).cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(Double(index)))
            )
        }
        let (model, repository) = try makeModelWithCatalogAssets(named: "compare-refill-basic", assets: frames)
        model.select(frames[0].id)
        model.selectedView = .compare

        let initialCompareIDs = model.compareAssets().map(\.id)
        XCTAssertEqual(initialCompareIDs.count, 8)
        XCTAssertFalse(initialCompareIDs.contains(frames[8].id), "ninth frame waits outside the capped survey")

        let rejectedID = initialCompareIDs[0]
        model.select(rejectedID)
        try model.setFlagForSelectedAsset(.reject)

        let refilledIDs = model.compareAssets().map(\.id)
        XCTAssertEqual(refilledIDs.count, 8, "refill keeps the survey full")
        XCTAssertFalse(refilledIDs.contains(rejectedID), "the rejected frame leaves the survey")
        XCTAssertTrue(refilledIDs.contains(frames[8].id), "the waiting ninth frame backfills the slot")
        XCTAssertEqual(try repository.asset(id: rejectedID).metadata.flag, .reject)
    }

    func testNoRefillWhenTheStackIsExhausted() throws {
        let capturedAt = Date(timeIntervalSince1970: 400)
        // A five-frame stack — smaller than the 8-frame cap, so nothing is
        // ever waiting outside the survey to refill from.
        let frames = (0..<5).map { index in
            makeAsset(
                id: "exhausted-frame-\(index)",
                path: "/Photos/Job/exhausted-frame-\(index).cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(Double(index)))
            )
        }
        let (model, _) = try makeModelWithCatalogAssets(named: "compare-refill-exhausted", assets: frames)
        model.select(frames[0].id)
        model.selectedView = .compare

        let initialCompareIDs = model.compareAssets().map(\.id)
        XCTAssertEqual(initialCompareIDs.count, 5)

        let rejectedID = initialCompareIDs[0]
        model.select(rejectedID)
        try model.setFlagForSelectedAsset(.reject)

        let afterRejectIDs = model.compareAssets().map(\.id)
        XCTAssertEqual(afterRejectIDs.count, 4, "the survey shrinks; no stack frame is left to refill from")
        XCTAssertFalse(afterRejectIDs.contains(rejectedID))
    }

    func testRefillSkipsSiblingsThatAreAlreadyDecided() throws {
        let capturedAt = Date(timeIntervalSince1970: 500)
        // Ten frames in the stack: eight fill the initial survey, the ninth
        // is already rejected from an earlier pass, the tenth is undecided.
        let frames = (0..<10).map { index in
            makeAsset(
                id: "skip-decided-frame-\(index)",
                path: "/Photos/Job/skip-decided-frame-\(index).cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(Double(index)))
            )
        }
        let (model, _) = try makeModelWithCatalogAssets(named: "compare-refill-skip-decided", assets: frames)
        model.select(frames[8].id)
        try model.setFlagForSelectedAsset(.reject)
        model.select(frames[0].id)
        model.selectedView = .compare

        let initialCompareIDs = model.compareAssets().map(\.id)
        XCTAssertEqual(initialCompareIDs.count, 8)
        XCTAssertFalse(initialCompareIDs.contains(frames[8].id))
        XCTAssertFalse(initialCompareIDs.contains(frames[9].id))

        let rejectedID = initialCompareIDs[0]
        model.select(rejectedID)
        try model.setFlagForSelectedAsset(.reject)

        let refilledIDs = model.compareAssets().map(\.id)
        XCTAssertTrue(refilledIDs.contains(frames[9].id), "the already-decided eighth frame is skipped for the undecided tenth")
        XCTAssertFalse(refilledIDs.contains(frames[8].id))
    }

    func testEnteringCompareFromAStackAutoPopulatesRecommendedFirstCappedAtEight() throws {
        let capturedAt = Date(timeIntervalSince1970: 600)
        let frames = (0..<6).map { index in
            makeAsset(
                id: "recommended-frame-\(index)",
                path: "/Photos/Job/recommended-frame-\(index).cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(Double(index)))
            )
        }
        let (model, repository) = try makeModelWithCatalogAssets(named: "compare-recommended-first", assets: frames)
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        // frames[4] is the standout: a much higher focus score than its siblings.
        try repository.recordEvaluationSignals(frames.enumerated().map { index, frame in
            EvaluationSignal(
                assetID: frame.id,
                kind: .focus,
                value: .score(index == 4 ? 0.98 : 0.3),
                confidence: 0.9,
                provenance: provenance
            )
        })

        // Anchor entry on a different frame than the recommended one.
        model.select(frames[1].id)
        model.selectedView = .compare

        let orderedIDs = model.compareAssets().map(\.id)
        XCTAssertEqual(orderedIDs.first, frames[4].id, "the recommended frame leads the survey")
        XCTAssertEqual(Set(orderedIDs), Set(frames.map(\.id)))
    }

    // Under a too-close-to-call tie the survey can't lead with a single
    // machine-crowned frame: the whole tied-leader set leads instead
    // (capture order), and survives the 8-frame cap together, so Compare —
    // the tie's resolution path — always opens with every tied frame
    // visible.
    func testEnteringCompareFromATiedStackLeadsWithTheTiedSetNotARawWinner() throws {
        let capturedAt = Date(timeIntervalSince1970: 650)
        let frames = (0..<10).map { index in
            makeAsset(
                id: "tied-lead-frame-\(index)",
                path: "/Photos/Job/tied-lead-frame-\(index).cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(Double(index)))
            )
        }
        let (model, repository) = try makeModelWithCatalogAssets(named: "compare-tied-lead", assets: frames)
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        // frames[7] (0.79) and frames[8] (0.80) tie within the 0.03 margin;
        // everything else is far below. Recommended-first ordering would
        // crown frames[8] and let the cap drop frames[7] entirely.
        try repository.recordEvaluationSignals(frames.enumerated().map { index, frame in
            EvaluationSignal(
                assetID: frame.id,
                kind: .focus,
                value: .score(index == 8 ? 0.80 : (index == 7 ? 0.79 : 0.3)),
                confidence: 0.9,
                provenance: provenance
            )
        })

        model.select(frames[0].id)
        model.selectedView = .compare

        let orderedIDs = model.compareAssets().map(\.id)
        XCTAssertEqual(orderedIDs.count, 8)
        XCTAssertEqual(
            Array(orderedIDs.prefix(2)),
            [frames[7].id, frames[8].id],
            "the tied set leads in capture order — no single raw winner in front"
        )
    }

    func testAutoPopulateCapsAtEightFramesForALargerStack() throws {
        let capturedAt = Date(timeIntervalSince1970: 700)
        let frames = (0..<10).map { index in
            makeAsset(
                id: "cap-frame-\(index)",
                path: "/Photos/Job/cap-frame-\(index).cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(Double(index)))
            )
        }
        let (model, _) = try makeModelWithCatalogAssets(named: "compare-cap-eight", assets: frames)
        model.select(frames[0].id)
        model.selectedView = .compare

        XCTAssertEqual(model.compareAssets().count, 8)
    }

    // MARK: - Fixtures (mirrors AppModelTests'/StackDecisionTests' private helpers; kept local per file)

    private func makeAsset(
        id: String,
        path: String,
        technicalMetadata: AssetTechnicalMetadata? = nil
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: technicalMetadata
        )
    }

    private static func technicalMetadata(capturedAt: Date) -> AssetTechnicalMetadata {
        AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            capturedAt: capturedAt,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-app-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
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
}
