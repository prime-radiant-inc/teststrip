import CoreGraphics
import Foundation
import ImageIO
import TeststripCore
import UniformTypeIdentifiers

public struct SmokeCatalogSeederResult: Equatable {
    public var catalogURL: URL
    public var previewCacheRoot: URL
    public var sourceImageCount: Int
    public var assetCount: Int
    public var cachedPreviewCount: Int

    public init(
        catalogURL: URL,
        previewCacheRoot: URL,
        sourceImageCount: Int,
        assetCount: Int,
        cachedPreviewCount: Int
    ) {
        self.catalogURL = catalogURL
        self.previewCacheRoot = previewCacheRoot
        self.sourceImageCount = sourceImageCount
        self.assetCount = assetCount
        self.cachedPreviewCount = cachedPreviewCount
    }
}

/// Capture-time layout for the `burst` seed variant: multi-frame groups whose
/// consecutive frames sit inside AssetStackBuilder's 2s auto-stack gap, plus
/// trailing singles far outside it, so a seeded catalog exercises auto
/// stacking without a real camera burst.
public enum BurstFixtureLayout {
    public static let burstFrameCounts = [3, 4, 3, 4]
    public static let singleCount = 4
    public static var totalAssetCount: Int {
        burstFrameCounts.reduce(0, +) + singleCount
    }

    public static func captureOffsets() -> [TimeInterval] {
        var offsets: [TimeInterval] = []
        var groupStart: TimeInterval = 0
        for frameCount in burstFrameCounts {
            for frame in 0..<frameCount {
                offsets.append(groupStart + TimeInterval(frame))
            }
            groupStart += 3600
        }
        for single in 0..<singleCount {
            offsets.append(groupStart + TimeInterval(single) * 3600)
        }
        return offsets
    }
}

/// Opt-in synthetic evaluation-signal fixtures the smoke/burst seeders can
/// attach, so scenario cards that depend on AI reads — the inspector's
/// suggested-keyword chips, the frame/rail flaw badges — can be driven from a
/// freshly seeded catalog without first running the evaluation lane.
///
/// The default (`[]`) writes no `evaluation_signals` rows at all, so every
/// scenario that asserts a baseline-relative count on the plain `--smoke` seed
/// is unaffected. See `SmokeSeedSignalLayout` for the documented subsets.
public struct SmokeSeedEvaluationFixtures: OptionSet, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// `.object` label signals on `SmokeSeedSignalLayout.keywordSignalAssetIndices`,
    /// driving the inspector's suggested-keyword chips (inspect-006).
    public static let keywordSuggestions = SmokeSeedEvaluationFixtures(rawValue: 1 << 0)

    /// Below-threshold `.focus`/`.eyesOpen` signals on every frame
    /// `AssetStackBuilder` groups into a multi-frame stack, driving the
    /// EYES CLOSED / SOFT flaw badges (cull-021, cull-004).
    public static let stackFlaws = SmokeSeedEvaluationFixtures(rawValue: 1 << 1)

    /// Parses the `seed-*-catalog` CLI's trailing fixture tokens. Unknown
    /// tokens are ignored so the seed commands stay forward-compatible.
    public static func parse(_ tokens: [String]) -> SmokeSeedEvaluationFixtures {
        var fixtures: SmokeSeedEvaluationFixtures = []
        for token in tokens {
            switch token {
            case "keyword-signals":
                fixtures.insert(.keywordSuggestions)
            case "stack-flaws":
                fixtures.insert(.stackFlaws)
            default:
                continue
            }
        }
        return fixtures
    }
}

/// The documented, bounded subsets `SmokeSeedEvaluationFixtures` writes into.
/// Asset indexes are into the `count` photos the seeder creates (asset id
/// `smoke-<index>`); every constant here is the single source of truth the
/// fixture tests assert against.
public enum SmokeSeedSignalLayout {
    /// The photos that carry `.object` keyword signals. Index 0 is included
    /// because the keyword cards locate their target with
    /// `SELECT ... ORDER BY id LIMIT 1`, which resolves to `smoke-0`.
    public static let keywordSignalAssetIndices = [0, 1, 3]

    /// Keyword labels written per asset index, one `.object` signal per label.
    /// Deliberately disjoint from the seed's own `metadata.keywords`
    /// (["smoke", "batch-N"]) so each label surfaces as an unaccepted
    /// suggestion rather than being suppressed as already-present.
    public static let keywordSignalsByAssetIndex: [Int: [String]] = [
        0: ["autumn", "leaves"],
        1: ["street", "market"],
        3: ["mountain", "lake"]
    ]

    public static let keywordSignalConfidence = 0.9

    /// Highest focus score handed to a flaw-frame — comfortably at or below
    /// the app's `CompareSurveyPresentation.softFocusBadgeThreshold` (0.4), so
    /// every seeded stack frame earns the SOFT badge.
    public static let highestFocusScore = 0.39

    /// Per-stack focus-score step. Descending scores give each multi-frame
    /// stack a unique ranking leader (no too-close-to-call tie) while keeping
    /// every frame badged; the floor stops the step from crossing zero.
    public static let focusScoreStep = 0.06

    /// Round-robin focus score for a frame at `position` within its stack.
    public static func focusScore(atStackPosition position: Int) -> Double {
        max(highestFocusScore - focusScoreStep * Double(position), 0.03)
    }
}

public struct SmokeCatalogSeeder {
    public var applicationSupportDirectory: URL
    public var count: Int
    /// Per-index capture-time offsets (seconds from the seed epoch). Nil keeps
    /// the default 15-minute spacing, which never auto-stacks.
    public var captureOffsets: [TimeInterval]?
    /// Opt-in synthetic evaluation-signal fixtures. Empty (the default) keeps
    /// the baseline seed byte-for-byte identical: no `evaluation_signals` rows,
    /// so every scenario that asserts a baseline-relative count is unaffected.
    public var evaluationFixtures: SmokeSeedEvaluationFixtures

    private let renderedLevels: [PreviewLevel] = [.grid, .large]

    public init(
        applicationSupportDirectory: URL,
        count: Int,
        captureOffsets: [TimeInterval]? = nil,
        evaluationFixtures: SmokeSeedEvaluationFixtures = []
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.count = max(0, count)
        self.captureOffsets = captureOffsets
        self.evaluationFixtures = evaluationFixtures
    }

    public func run() throws -> SmokeCatalogSeederResult {
        let appRoot = applicationSupportDirectory.appendingPathComponent("Teststrip", isDirectory: true)
        let sourceRoot = appRoot.appendingPathComponent("SmokeOriginals", isDirectory: true)
        let catalogURL = appRoot.appendingPathComponent("catalog.sqlite")
        let previewCache = PreviewCache(root: appRoot.appendingPathComponent("Previews", isDirectory: true))

        if FileManager.default.fileExists(atPath: catalogURL.path) {
            throw TeststripError.invalidState("refusing to seed smoke catalog over existing catalog: \(catalogURL.path)")
        }

        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previewCache.root, withIntermediateDirectories: true)

        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let renderer = PreviewRenderer()
        var sourceImageCount = 0
        var seededAssets: [Asset] = []

        for index in 0..<count {
            let assetID = AssetID(rawValue: "smoke-\(index)")
            let sourceURL = sourceRoot.appendingPathComponent("\(assetID.rawValue).jpg")
            try Self.writeSmokeJPEG(to: sourceURL, index: index)
            sourceImageCount += 1

            let seeded = asset(
                id: assetID,
                originalURL: sourceURL,
                index: index,
                fingerprint: try fingerprint(for: sourceURL)
            )
            try repository.upsert(seeded)
            seededAssets.append(seeded)

            try renderer.renderLevels(
                fromLocalSource: sourceURL,
                levels: renderedLevels,
                destinationProvider: { level in
                    previewCache.url(for: PreviewCacheKey(assetID: assetID, level: level))
                }
            )
        }
        let pickAssetIDs = seededAssets.enumerated()
            .filter { $0.offset % 6 >= 4 }
            .map { $0.element.id }
        if !pickAssetIDs.isEmpty {
            try repository.upsert(AssetSet(
                id: AssetSetID(rawValue: "smoke-picks"),
                name: "Smoke Picks",
                membership: .manual(pickAssetIDs),
                starred: true
            ))
        }

        try recordEvaluationFixtures(for: seededAssets, repository: repository)

        return SmokeCatalogSeederResult(
            catalogURL: catalogURL,
            previewCacheRoot: previewCache.root,
            sourceImageCount: sourceImageCount,
            assetCount: try repository.assetCount(includeBondedSecondaries: true),
            cachedPreviewCount: try PreviewCacheFileCounter.count(root: previewCache.root)
        )
    }

    /// Writes the opt-in signal fixtures (see `SmokeSeedEvaluationFixtures`)
    /// into the freshly seeded catalog. No-op for the default empty set.
    private func recordEvaluationFixtures(for assets: [Asset], repository: CatalogRepository) throws {
        var signals: [EvaluationSignal] = []

        if evaluationFixtures.contains(.keywordSuggestions) {
            signals.append(contentsOf: Self.keywordSignals(for: assets))
        }
        if evaluationFixtures.contains(.stackFlaws) {
            signals.append(contentsOf: Self.stackFlawSignals(for: assets))
        }

        try repository.recordEvaluationSignals(signals)
    }

    /// `.object` label signals on `SmokeSeedSignalLayout.keywordSignalAssetIndices`
    /// only. The labels are disjoint from the seed's own metadata keywords
    /// (["smoke", "batch-N"]), so every one surfaces as an unaccepted
    /// suggested-keyword chip.
    static func keywordSignals(for assets: [Asset]) -> [EvaluationSignal] {
        assets.enumerated().flatMap { index, asset -> [EvaluationSignal] in
            guard let labels = SmokeSeedSignalLayout.keywordSignalsByAssetIndex[index] else { return [] }
            return labels.map { label in
                EvaluationSignal(
                    assetID: asset.id,
                    kind: .object,
                    value: .label(label),
                    confidence: SmokeSeedSignalLayout.keywordSignalConfidence,
                    provenance: objectFixtureProvenance
                )
            }
        }
    }

    /// Below-threshold `.focus`/`.eyesOpen` signals on every frame
    /// `AssetStackBuilder` groups into a multi-frame stack — the same grouping
    /// the app uses — so the flawed frames really are stack frames. Standalone
    /// photos get nothing. Focus scores descend by position within each stack
    /// (all at or below the app's SOFT threshold), giving every stack a unique
    /// leader while every frame still earns a flaw badge.
    static func stackFlawSignals(for assets: [Asset]) -> [EvaluationSignal] {
        var signals: [EvaluationSignal] = []
        let stacks = AssetStackBuilder().stacks(from: assets)
        for stack in stacks where stack.assetIDs.count > 1 {
            for (position, assetID) in stack.assetIDs.enumerated() {
                signals.append(EvaluationSignal(
                    assetID: assetID,
                    kind: .focus,
                    value: .score(SmokeSeedSignalLayout.focusScore(atStackPosition: position)),
                    confidence: 1,
                    provenance: focusFixtureProvenance
                ))
                if position == stack.assetIDs.count - 1 {
                    signals.append(EvaluationSignal(
                        assetID: assetID,
                        kind: .eyesOpen,
                        value: .score(0),
                        confidence: 1,
                        provenance: faceFixtureProvenance
                    ))
                }
            }
        }
        return signals
    }

    /// The calibrated focus-family provider identity. `CatalogRepository`
    /// treats focus-family rows from any other provenance version as stale and
    /// hides them, so the fixture writes the real provider name + version to
    /// stay readable through the same path production reads use.
    private static let focusFixtureProvenance = ProviderProvenance(
        provider: LocalImageMetricsEvaluationProvider.providerName,
        model: "preview-color-focus-metrics",
        version: LocalImageMetricsEvaluationProvider.provenanceVersion,
        settingsHash: "default"
    )

    private static let faceFixtureProvenance = ProviderProvenance(
        provider: FaceExpressionEvaluationProvider.providerName,
        model: "CIDetectorFace",
        version: FaceExpressionEvaluationProvider.provenanceVersion,
        settingsHash: "default"
    )

    private static let objectFixtureProvenance = ProviderProvenance(
        provider: "teststrip-bench-fixtures",
        model: "smoke-keyword-fixture",
        version: "1",
        settingsHash: "default"
    )

    private func asset(id: AssetID, originalURL: URL, index: Int, fingerprint: FileFingerprint) -> Asset {
        let colorLabels = ColorLabel.allCases
        let colorLabel = colorLabels[index % colorLabels.count]
        let captureOffset = captureOffsets?[index] ?? TimeInterval(index * 900)
        let capturedAt = Date(timeIntervalSince1970: 1_704_067_200 + captureOffset)
        return Asset(
            id: id,
            originalURL: originalURL,
            volumeIdentifier: "Smoke",
            fingerprint: fingerprint,
            availability: .online,
            metadata: AssetMetadata(
                rating: index % 6,
                colorLabel: colorLabel,
                flag: index.isMultiple(of: 5) ? .reject : (index.isMultiple(of: 3) ? .pick : nil),
                keywords: ["smoke", "batch-\(index / 6)"],
                caption: "Smoke frame \(index + 1)"
            ),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 1200,
                pixelHeight: 800,
                cameraMake: "Teststrip",
                cameraModel: "SmokeCam \(index % 3 + 1)",
                lensModel: "\(35 + (index % 4) * 15)mm",
                isoSpeed: 100 + (index % 5) * 200,
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

    private func fingerprint(for url: URL) throws -> FileFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        // Store the real content hash, as the app's importer does: seeded
        // catalogs must exercise the same content-dedup paths (import
        // preflight, re-import skipping) as user-imported ones.
        return FileFingerprint(
            size: size,
            modificationDate: modificationDate,
            contentHash: try ContentHash.compute(forFileAt: url)
        )
    }

    private static func writeSmokeJPEG(to url: URL, index: Int) throws {
        let width = 1200
        let height = 800
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TeststripError.io("could not create smoke bitmap context")
        }

        let red = CGFloat((index % 5) + 1) / 5.0
        let green = CGFloat((index % 7) + 1) / 7.0
        let blue = CGFloat((index % 11) + 1) / 11.0
        context.setFillColor(CGColor(
            red: red * 0.65,
            green: green * 0.65,
            blue: blue * 0.65,
            alpha: 1.0
        ))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setFillColor(CGColor(
            red: min(red + 0.25, 1.0),
            green: min(green + 0.15, 1.0),
            blue: min(blue + 0.1, 1.0),
            alpha: 1.0
        ))
        context.fill(CGRect(x: 80 + (index % 4) * 70, y: 90, width: 420, height: 260))
        context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 0.45))
        context.fill(CGRect(x: 620, y: 180 + (index % 5) * 35, width: 360, height: 380))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TeststripError.io("could not create smoke jpeg")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write smoke jpeg")
        }
    }

}
