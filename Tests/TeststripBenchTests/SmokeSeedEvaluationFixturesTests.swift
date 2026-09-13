import TeststripCore
import XCTest

@testable import TeststripBench

final class SmokeSeedEvaluationFixturesTests: XCTestCase {
    // MARK: - Fixture parsing / layout

    func testFixtureParserMapsDocumentedTokensAndIgnoresUnknownOnes() {
        XCTAssertEqual(SmokeSeedEvaluationFixtures.parse([]), [])
        XCTAssertEqual(SmokeSeedEvaluationFixtures.parse(["keyword-signals"]), .keywordSuggestions)
        XCTAssertEqual(SmokeSeedEvaluationFixtures.parse(["stack-flaws"]), .stackFlaws)
        XCTAssertEqual(
            SmokeSeedEvaluationFixtures.parse(["keyword-signals", "stack-flaws"]),
            [.keywordSuggestions, .stackFlaws]
        )
        XCTAssertEqual(
            SmokeSeedEvaluationFixtures.parse(["stack-flaws", "keyword-signals"]),
            [.keywordSuggestions, .stackFlaws]
        )
        XCTAssertEqual(SmokeSeedEvaluationFixtures.parse(["not-a-fixture"]), [])
    }

    func testKeywordLayoutDocumentsAFirstAssetSoTheKeywordCardsCanFindIt() {
        // The keyword cards resolve their target with `ORDER BY id LIMIT 1`,
        // which lands on `smoke-0`; the fixture must include it or the chip
        // can never appear.
        XCTAssertTrue(SmokeSeedSignalLayout.keywordSignalAssetIndices.contains(0))
        XCTAssertEqual(
            SmokeSeedSignalLayout.keywordSignalAssetIndices.sorted(),
            SmokeSeedSignalLayout.keywordSignalsByAssetIndex.keys.sorted()
        )
        XCTAssertEqual(SmokeSeedSignalLayout.keywordSignalAssetIndices, [0, 1, 3])
    }

    func testFocusScoreLadderStaysBelowTheSoftBadgeThresholdAndIsUnique() {
        // The app's SOFT badge fires at focus <= 0.4 and the rail's ranking
        // needs one clear leader per stack; the ladder must keep every frame
        // badged while never tying within a four-frame burst.
        let scores = (0..<4).map(SmokeSeedSignalLayout.focusScore(atStackPosition:))
        for (score, expected) in zip(scores, [0.39, 0.33, 0.27, 0.21]) {
            XCTAssertEqual(score, expected, accuracy: 0.0001)
        }
        for score in scores {
            XCTAssertLessThanOrEqual(score, 0.4, "every flaw frame must earn the SOFT badge")
            XCTAssertGreaterThan(score, 0, "a zero score would be a degenerate ranking")
        }
        XCTAssertEqual(Set(scores).count, scores.count, "positions must rank distinctly")
    }

    // MARK: - Command parsing

    func testSeedAppCatalogParsesKeywordSignalToken() {
        XCTAssertEqual(
            BenchmarkCommand.parse([
                "TeststripBench", "seed-app-catalog", "/tmp/smoke", "12", "keyword-signals"
            ]),
            .seedAppCatalogWithFixtures(
                applicationSupportDirectory: URL(fileURLWithPath: "/tmp/smoke"),
                count: 12,
                fixtures: .keywordSuggestions
            )
        )
    }

    func testSeedAppCatalogWithoutTokensKeepsThePlainCase() {
        XCTAssertEqual(
            BenchmarkCommand.parse(["TeststripBench", "seed-app-catalog", "/tmp/smoke", "12"]),
            .seedAppCatalog(applicationSupportDirectory: URL(fileURLWithPath: "/tmp/smoke"), count: 12)
        )
    }

    func testSeedBurstCatalogParsesStackFlawToken() {
        XCTAssertEqual(
            BenchmarkCommand.parse(["TeststripBench", "seed-burst-catalog", "/tmp/burst", "stack-flaws"]),
            .seedBurstCatalogWithFixtures(
                applicationSupportDirectory: URL(fileURLWithPath: "/tmp/burst"),
                fixtures: .stackFlaws
            )
        )
    }

    // MARK: - Default seed writes no signals

    func testDefaultSeedWritesNoEvaluationSignals() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try SmokeCatalogSeeder(applicationSupportDirectory: directory, count: 6).run()
        let repository = try CatalogRepository(database: CatalogDatabase.open(at: result.catalogURL))

        for index in 0..<6 {
            let signals = try repository.evaluationSignals(assetID: AssetID(rawValue: "smoke-\(index)"))
            XCTAssertTrue(signals.isEmpty, "default seed must carry no signals (smoke-\(index))")
        }
    }

    // MARK: - Keyword-signal subset

    func testKeywordSignalGenerationTargetsTheDocumentedIndicesOnly() {
        let assets = (0..<8).map { Self.fixtureAsset(index: $0) }
        let signals = SmokeCatalogSeeder.keywordSignals(for: assets)
        let byAsset = Dictionary(grouping: signals, by: \.assetID)

        for index in 0..<8 {
            let assetID = AssetID(rawValue: "smoke-\(index)")
            guard let expected = SmokeSeedSignalLayout.keywordSignalsByAssetIndex[index] else {
                XCTAssertNil(byAsset[assetID], "smoke-\(index) must get no keyword signals")
                continue
            }
            let labels = (byAsset[assetID] ?? []).flatMap { signal -> [String] in
                guard signal.kind == .object else { return [] }
                switch signal.value {
                case .label(let label): return [label]
                case .labels(let labels): return labels
                default: return []
                }
            }
            XCTAssertEqual(labels.sorted(), expected.sorted(), "smoke-\(index) labels")
        }
    }

    func testKeywordFixturesLandOnTheDocumentedSubsetOnly() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try SmokeCatalogSeeder(
            applicationSupportDirectory: directory,
            count: 8,
            evaluationFixtures: .keywordSuggestions
        ).run()
        let repository = try CatalogRepository(database: CatalogDatabase.open(at: result.catalogURL))

        for index in 0..<8 {
            let assetID = AssetID(rawValue: "smoke-\(index)")
            let signals = try repository.evaluationSignals(assetID: assetID)
            guard let expectedLabels = SmokeSeedSignalLayout.keywordSignalsByAssetIndex[index] else {
                XCTAssertTrue(signals.isEmpty, "smoke-\(index) must stay signal-free")
                continue
            }

            let objectLabels = signals.flatMap { signal -> [String] in
                guard signal.kind == .object else { return [] }
                switch signal.value {
                case .label(let label): return [label]
                case .labels(let labels): return labels
                default: return []
                }
            }
            XCTAssertEqual(objectLabels.sorted(), expectedLabels.sorted(), "smoke-\(index) labels")
            // One `.object` signal per asset carries all of its labels.
            XCTAssertEqual(signals.count, 1, "smoke-\(index) signal count")

            // The fixture only guarantees a chip if the label isn't already a
            // metadata keyword — the inspector suppresses those.
            let asset = try repository.asset(id: assetID)
            for label in expectedLabels {
                XCTAssertFalse(
                    asset.metadata.keywords.contains { $0.caseInsensitiveCompare(label) == .orderedSame },
                    "\(label) is already a metadata keyword on smoke-\(index)"
                )
            }
        }
    }

    func testKeywordFixtureConfidenceIsAboveThePromotionFloor() throws {
        // promoteMetadataLabels only auto-applies object labels at >= 0.5; a
        // fixture below that could never round-trip to a real keyword.
        XCTAssertGreaterThanOrEqual(SmokeSeedSignalLayout.keywordSignalConfidence, 0.5)

        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try SmokeCatalogSeeder(
            applicationSupportDirectory: directory,
            count: 4,
            evaluationFixtures: .keywordSuggestions
        ).run()
        let repository = try CatalogRepository(database: CatalogDatabase.open(at: result.catalogURL))
        let signals = try repository.evaluationSignals(assetID: AssetID(rawValue: "smoke-0"))
        XCTAssertFalse(signals.isEmpty)
        for signal in signals {
            XCTAssertGreaterThanOrEqual(signal.confidence, 0.5)
        }
    }

    // MARK: - Stack-flaw subset

    func testStackFlawSignalGenerationMarksOnlyMultiFrameStackFrames() throws {
        let offsets = BurstFixtureLayout.captureOffsets()
        let assets = (0..<offsets.count).map { Self.fixtureAsset(index: $0, captureOffset: offsets[$0]) }
        let signals = SmokeCatalogSeeder.stackFlawSignals(for: assets)
        let stacks = AssetStackBuilder().stacks(from: assets).filter { $0.assetIDs.count > 1 }
        let expectedIDs = Set(stacks.flatMap(\.assetIDs))

        XCTAssertEqual(Set(signals.map(\.assetID)), expectedIDs)
        for stack in stacks {
            for (position, assetID) in stack.assetIDs.enumerated() {
                let assetSignals = signals.filter { $0.assetID == assetID }
                let focus = try XCTUnwrap(Self.score(kind: .focus, in: assetSignals))
                XCTAssertEqual(
                    focus,
                    SmokeSeedSignalLayout.focusScore(atStackPosition: position),
                    accuracy: 0.0001
                )
                let eyesOpen = Self.score(kind: .eyesOpen, in: assetSignals)
                if position == stack.assetIDs.count - 1 {
                    XCTAssertEqual(eyesOpen, 0)
                } else {
                    XCTAssertNil(eyesOpen)
                }
            }
        }
    }

    func testGeneratedFixturesRoundTripThroughTheCatalogRepository() throws {
        // Proves the generated signals survive a real catalog write/read —
        // including the focus-family provenance filter — without going
        // through preview rendering.
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        let offsets = BurstFixtureLayout.captureOffsets()
        let assets = (0..<offsets.count).map { Self.fixtureAsset(index: $0, captureOffset: offsets[$0]) }
        for asset in assets {
            try repository.upsert(asset)
        }
        try repository.recordEvaluationSignals(
            SmokeCatalogSeeder.keywordSignals(for: assets) + SmokeCatalogSeeder.stackFlawSignals(for: assets)
        )

        let signalsByAsset = try repository.evaluationSignals(forAssetIDs: assets.map(\.id))
        let stacks = AssetStackBuilder().stacks(from: assets).filter { $0.assetIDs.count > 1 }
        let stackedIDs = Set(stacks.flatMap(\.assetIDs))
        for asset in assets where stackedIDs.contains(asset.id) {
            let focus = try XCTUnwrap(Self.score(kind: .focus, in: signalsByAsset[asset.id] ?? []))
            XCTAssertLessThanOrEqual(focus, 0.4, "focus read for \(asset.id.rawValue) must survive the provenance filter")
        }
        let keywordAssetID = AssetID(rawValue: "smoke-0")
        XCTAssertTrue(
            (signalsByAsset[keywordAssetID] ?? []).contains { $0.kind == .object },
            "keyword signals must survive the catalog round-trip"
        )
    }

    func testStackFlawFixturesBadgeEveryStackFrameAndNoneOfTheSingles() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try SmokeCatalogSeeder(
            applicationSupportDirectory: directory,
            count: BurstFixtureLayout.totalAssetCount,
            captureOffsets: BurstFixtureLayout.captureOffsets(),
            evaluationFixtures: .stackFlaws
        ).run()
        let repository = try CatalogRepository(database: CatalogDatabase.open(at: result.catalogURL))
        let assets = try repository.allAssets(
            limit: BurstFixtureLayout.totalAssetCount,
            sort: .importOrder
        )
        let stacks = AssetStackBuilder().stacks(from: assets)
        let stackFrames = stacks.filter { $0.assetIDs.count > 1 }
        XCTAssertEqual(stackFrames.map(\.assetIDs.count), BurstFixtureLayout.burstFrameCounts)

        let signalCache = try repository.evaluationSignals(forAssetIDs: assets.map(\.id))

        for stack in stackFrames {
            var focusScores: [Double] = []
            for (position, assetID) in stack.assetIDs.enumerated() {
                let signals = signalCache[assetID] ?? []
                let focus = Self.score(kind: .focus, in: signals)
                let focusValue = try XCTUnwrap(focus, "\(assetID.rawValue) must carry a focus read")
                XCTAssertLessThanOrEqual(focusValue, 0.4, "\(assetID.rawValue) must earn the SOFT badge")
                focusScores.append(focusValue)

                let eyesOpen = Self.score(kind: .eyesOpen, in: signals)
                if position == stack.assetIDs.count - 1 {
                    XCTAssertEqual(eyesOpen, 0, "the worst frame of \(assetID.rawValue)'s stack must earn EYES CLOSED")
                } else {
                    XCTAssertNil(eyesOpen, "only the worst frame of a stack carries EYES CLOSED")
                }
            }
            XCTAssertEqual(
                Set(focusScores).count,
                focusScores.count,
                "each stack needs a unique ranking leader, got \(focusScores)"
            )
        }

        let stackedIDs = Set(stackFrames.flatMap(\.assetIDs))
        for asset in assets where !stackedIDs.contains(asset.id) {
            XCTAssertTrue(
                (signalCache[asset.id] ?? []).isEmpty,
                "standalone \(asset.id.rawValue) must stay signal-free"
            )
        }
    }

    func testStackFlawFocusReadsSurviveTheCalibratedProvenanceFilter() throws {
        // CatalogRepository hides focus-family rows written by a non-current
        // provenance version. If the fixture used a fabricated provider
        // identity, every read would come back empty and the badges would
        // silently vanish.
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try SmokeCatalogSeeder(
            applicationSupportDirectory: directory,
            count: BurstFixtureLayout.totalAssetCount,
            captureOffsets: BurstFixtureLayout.captureOffsets(),
            evaluationFixtures: .stackFlaws
        ).run()
        let repository = try CatalogRepository(database: CatalogDatabase.open(at: result.catalogURL))
        let signals = try repository.evaluationSignals(assetID: AssetID(rawValue: "smoke-0"))
        let focus = try XCTUnwrap(signals.first { $0.kind == .focus })
        XCTAssertEqual(focus.provenance.provider, LocalImageMetricsEvaluationProvider.providerName)
        XCTAssertEqual(focus.provenance.version, LocalImageMetricsEvaluationProvider.provenanceVersion)
    }

    func testCombinedFixturesCoexist() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try SmokeCatalogSeeder(
            applicationSupportDirectory: directory,
            count: BurstFixtureLayout.totalAssetCount,
            captureOffsets: BurstFixtureLayout.captureOffsets(),
            evaluationFixtures: [.keywordSuggestions, .stackFlaws]
        ).run()
        let repository = try CatalogRepository(database: CatalogDatabase.open(at: result.catalogURL))
        let keywordSignals = try repository.evaluationSignals(assetID: AssetID(rawValue: "smoke-0"))
        XCTAssertTrue(keywordSignals.contains { $0.kind == .object })
        // smoke-0 is inside the first burst group, so it also carries a flaw read.
        XCTAssertTrue(keywordSignals.contains { $0.kind == .focus })
    }

    // MARK: - Helpers

    private static func score(kind: EvaluationKind, in signals: [EvaluationSignal]) -> Double? {
        signals
            .filter { $0.kind == kind }
            .compactMap { signal -> Double? in
                guard case .score(let score) = signal.value else { return nil }
                return score
            }
            .first
    }

    private static func fixtureAsset(index: Int, captureOffset: TimeInterval? = nil) -> Asset {
        let capturedAt = Date(timeIntervalSince1970: 1_704_067_200 + (captureOffset ?? TimeInterval(index * 900)))
        return Asset(
            id: AssetID(rawValue: "smoke-\(index)"),
            originalURL: URL(fileURLWithPath: "/tmp/smoke-fixture/smoke-\(index).jpg"),
            volumeIdentifier: "Smoke",
            fingerprint: FileFingerprint(size: 0, modificationDate: capturedAt),
            availability: .online,
            metadata: AssetMetadata(keywords: ["smoke", "batch-\(index / 6)"], caption: "Smoke frame \(index + 1)"),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 1200,
                pixelHeight: 800,
                capturedAt: capturedAt,
                provenance: ProviderProvenance(
                    provider: "TeststripBench",
                    model: "SmokeCatalogSeeder",
                    version: "1",
                    settingsHash: "default"
                )
            )
        )
    }

    private static func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-smoke-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
