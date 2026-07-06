# Teststrip Culling ML Signals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Culling can detect smiles, eyes open/closed, and eye-region sharpness as persisted evaluation signals, and the culling verdict pill, stack keep recommendations, Survey Compare badges, and focus-compare metric lanes read them.

**Architecture:** A new `FaceExpressionEvaluationProvider` (provider name `core-image-faces`) runs in the existing per-asset `runEvaluation` worker flow over cached previews. It wraps a `FaceExpressionAnalyzing` seam whose stock implementation is CoreImage's `CIDetector` face detector with the `CIDetectorSmile`/`CIDetectorEyeBlink` options (per-face booleans plus eye positions). Per-face results aggregate to three per-photo `EvaluationSignal` kinds — `eyesOpen`, `smile`, `eyeSharpness` — persisted through the existing `evaluation_signals` plumbing. Eye sharpness reuses the existing luminance-delta focus heuristic (extracted from `LocalImageMetricsEvaluationProvider` into a shared helper) applied to eye-region crops of the cached preview. UI consumption is presentation-model changes only, tested without SwiftUI snapshots.

**Tech Stack:** Swift 6 / macOS 14, SwiftPM, XCTest, stock CoreImage (`CIDetector`), CoreGraphics/ImageIO. No new dependencies.

## Global Constraints

- Machine labels stay PROVISIONAL until user acceptance — nothing auto-writes catalog metadata/XMP. These signals persist ONLY to `evaluation_signals`; no task writes `AssetMetadata`, flags, ratings, keywords, or sidecars.
- Evaluation providers run in TeststripWorker over CACHED PREVIEWS (never originals on hot paths). The new provider consumes the preview URL that `WorkerCommandExecutor.cachedPreviewURL(for:)` already resolves (preference order `.large` → `.medium` → `.grid` → `.micro`).
- No new worker protocol, no new review queues, no new background-work kinds. The provider registers in the existing `runEvaluation` command flow.
- UI claims must be honest and derived from persisted signals: `CompareSurveyPresentation.decisionBadges` stays metadata-only (existing tests enforce "without claiming best"); signal-derived claims live in new, separate presentation members.
- No SwiftUI snapshot tests. All UI tasks are presentation-model changes with XCTest model tests (repo pattern in `Tests/TeststripAppTests`).
- Follow existing copy style exactly where specified below; separators are the repo's `·` middle dots and `—` em dashes.
- Run commands from the repo root `/Users/jesse/git/projects/teststrip`.

## Design Decision: CIDetector vs. VNDetectFaceLandmarksRequest

Two stock candidates were evaluated for smile + eyes open/closed:

| | (a) CoreImage `CIDetector` (`CIDetectorSmile`, `CIDetectorEyeBlink`) | (b) Vision `VNDetectFaceLandmarksRequest` (eye landmark geometry) |
|---|---|---|
| Smile | Per-face `CIFaceFeature.hasSmile` boolean — **only stock per-face smile source on macOS** | **None.** Vision has no public smile signal; mouth-landmark curvature would be an invented heuristic |
| Eyes open/closed | Per-face `leftEyeClosed` / `rightEyeClosed` booleans, no thresholds to invent | Eye-openness ratio from landmark points requires inventing an aspect-ratio threshold tuned per Vision landmark revision |
| Eye regions for sharpness crops | `leftEyePosition` / `rightEyePosition` points + face `bounds` → crop as a fraction of face width (one documented constant) | Precise eye polygons, but adds a second face detector whose face set may disagree with CIDetector's smile faces |
| Code paths | One detection pass supplies smile, blink, and eye crop geometry from the same face set | Two detectors (CIDetector still required for smile) → cross-detector face aggregation problems |

**Decision: (a) CIDetector for the whole expression pass.** Smile forces CIDetector into the design regardless; taking blink booleans and eye positions from the same pass keeps one face set, zero invented thresholds for eye state, and exactly one documented geometry constant (eye crop = 0.25 × face width). Confidence semantics: CIDetector booleans carry no confidence, so signals use fixed honest confidences (0.7 for detector booleans, 0.6 for the crop-sharpness heuristic), matching how `local-image-metrics` reports fixed heuristic confidences (0.55–0.7). Upgrade path: if CIDetector blink/smile quality proves poor on the real corpus, re-derive `eyesOpen` from Vision landmarks behind the same `FaceExpressionAnalyzing` seam under a new provenance `model`/`version` — no schema or signal-kind changes.

**Aggregation semantics (per photo):**
- `eyesOpen` = `.score(fraction of detected faces with both eyes open)` — `1.0` means all eyes open, `0.0` all shut, between means some faces blinked. Score form (not a label) so it feeds the existing `.score`-only stack ranking.
- `smile` = `.score(fraction of detected faces smiling)`. Excluded from stack ranking (not smiling is not a defect).
- `eyeSharpness` = per eye: shared luminance-delta focus score of a square crop centered on the eye (side = 0.25 × face width in pixels, skipped under 8 px); per face: the sharpest of its scored eyes (nearest-eye-sharp acceptance, as in portraiture); per photo: the **minimum** across faces — a group frame is only as good as its weakest subject's eyes.
- No detected faces → the provider emits no signals (same convention as `AppleVisionEvaluationProvider.faceSignal`).

**Non-goals:** no `LocalHTTPModelProvider` prompt changes, no changes to `AssetStackBuilder`, no new review queues or worker commands, no per-face persisted rows (photo-level signals only), no smile weighting in keep ranking.

## File Map

- Create: `Sources/TeststripCore/Evaluation/PreviewPixelMetrics.swift` — shared RGBA sampling + edge-detail focus score.
- Create: `Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift` — seam protocol, detected-face value type, provider, CIDetector analyzer.
- Create: `Tests/TeststripCoreTests/FaceExpressionEvaluationProviderTests.swift`.
- Modify: `Sources/TeststripCore/Evaluation/EvaluationSignal.swift` — three new kinds.
- Modify: `Sources/TeststripCore/Evaluation/LocalImageMetricsEvaluationProvider.swift` — delegate to `PreviewPixelMetrics`.
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` — eyes-closed clause in the existing `likelyIssue` SQL.
- Modify: `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift` — register provider.
- Modify: `Sources/TeststripApp/AppModel.swift` — `displayName`, sidebar order, default provider names.
- Modify: `Sources/TeststripApp/CopilotView.swift`, `Sources/TeststripApp/InspectorView.swift`, `Sources/TeststripApp/LibrarySearchIntent.swift`, `Sources/TeststripApp/LiveMockupPlaceholder.swift` — kind plumbing/copy.
- Modify: `Sources/TeststripApp/LibraryGridView.swift` — `CullingAssistPresentation`, `CullingStackRecommendation`, `CullingStackRailPresentation.rankedAction`, `CompareSurveyPresentation`, `CompareDecisionBadge`, `CompareFocusMetricPresentation`, `EvaluationSignalPresentation`, filter options.
- Modify tests: `Tests/TeststripCoreTests/EvaluationProviderTests.swift`, `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`, `Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift`, `Tests/TeststripAppTests/LibrarySearchIntentTests.swift`, `Tests/TeststripAppTests/AppModelTests.swift`, `Tests/TeststripAppTests/CullingAssistPresentationTests.swift`, `Tests/TeststripAppTests/CullingStackRailPresentationTests.swift`, `Tests/TeststripAppTests/CompareSurveyPresentationTests.swift`.

---

### Task 1: Extract the shared preview focus metric

**Files:**
- Create: `Sources/TeststripCore/Evaluation/PreviewPixelMetrics.swift`
- Modify: `Sources/TeststripCore/Evaluation/LocalImageMetricsEvaluationProvider.swift`
- Test: `Tests/TeststripCoreTests/EvaluationProviderTests.swift`

**Interfaces:**
- Consumes: existing private pixel-sampling code in `LocalImageMetricsEvaluationProvider` (lines 65–132, 195–206).
- Produces (internal to TeststripCore, used by Tasks 4):
  - `enum PreviewPixelMetrics`
  - `static func rgbaSamples(of image: CGImage, width: Int, height: Int) throws -> [UInt8]`
  - `static func focusScore(in pixels: [UInt8], width: Int, height: Int) -> Double`
  - `static func luminance(atX x: Int, y: Int, in pixels: [UInt8], width: Int) -> Double`
  - `static func luminance(red: Double, green: Double, blue: Double) -> Double`

- [ ] **Step 1: Write the failing test**

Add to `Tests/TeststripCoreTests/EvaluationProviderTests.swift` (inside `EvaluationProviderTests`, which already has the private `writeSolidPNG`/`writeCheckerboardPNG` helpers at file scope):

```swift
    func testPreviewPixelMetricsFocusScoreReflectsEdgeDetailInSampledPixels() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-pixel-metrics")
        let flatURL = directory.appendingPathComponent("flat.png")
        let detailedURL = directory.appendingPathComponent("detailed.png")
        try writeSolidPNG(to: flatURL, width: 64, height: 64, red: 0.5, green: 0.5, blue: 0.5)
        try writeCheckerboardPNG(to: detailedURL, width: 64, height: 64, cellSize: 4)

        let flatFocus = try sampledFocusScore(at: flatURL)
        let detailedFocus = try sampledFocusScore(at: detailedURL)

        XCTAssertLessThan(flatFocus, 0.01)
        XCTAssertGreaterThan(detailedFocus, flatFocus + 0.2)
    }

    private func sampledFocusScore(at url: URL) throws -> Double {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TeststripError.unsupportedFormat("could not read \(url.lastPathComponent)")
        }
        let pixels = try PreviewPixelMetrics.rgbaSamples(of: image, width: 16, height: 16)
        return PreviewPixelMetrics.focusScore(in: pixels, width: 16, height: 16)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EvaluationProviderTests.testPreviewPixelMetricsFocusScoreReflectsEdgeDetailInSampledPixels`
Expected: compile FAILURE — `cannot find 'PreviewPixelMetrics' in scope`

- [ ] **Step 3: Create `Sources/TeststripCore/Evaluation/PreviewPixelMetrics.swift`**

Move (not duplicate) the sampling and focus code out of `LocalImageMetricsEvaluationProvider`:

```swift
import CoreGraphics
import Foundation

/// Shared low-level pixel sampling and edge-detail focus scoring for
/// evaluation providers that measure sharpness on cached previews.
enum PreviewPixelMetrics {
    /// Draws `image` into a `width` x `height` RGBA8 buffer and returns the pixels.
    static func rgbaSamples(of image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw TeststripError.io("could not allocate image sample buffer")
            }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                throw TeststripError.io("could not create image metrics context")
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    /// Average neighbor luminance delta over the sampled pixels, clamped to 0...1.
    static func focusScore(in pixels: [UInt8], width: Int, height: Int) -> Double {
        guard width > 1, height > 1 else { return 0 }
        var totalDelta = 0.0
        var comparisonCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let current = luminance(atX: x, y: y, in: pixels, width: width)
                if x + 1 < width {
                    totalDelta += abs(current - luminance(atX: x + 1, y: y, in: pixels, width: width))
                    comparisonCount += 1
                }
                if y + 1 < height {
                    totalDelta += abs(current - luminance(atX: x, y: y + 1, in: pixels, width: width))
                    comparisonCount += 1
                }
            }
        }
        guard comparisonCount > 0 else { return 0 }
        return min(max(totalDelta / Double(comparisonCount), 0.0), 1.0)
    }

    static func luminance(atX x: Int, y: Int, in pixels: [UInt8], width: Int) -> Double {
        let index = (y * width + x) * 4
        return luminance(
            red: Double(pixels[index]) / 255.0,
            green: Double(pixels[index + 1]) / 255.0,
            blue: Double(pixels[index + 2]) / 255.0
        )
    }

    static func luminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
```

- [ ] **Step 4: Refactor `LocalImageMetricsEvaluationProvider` to delegate**

In `Sources/TeststripCore/Evaluation/LocalImageMetricsEvaluationProvider.swift`:
- In `evaluate`, replace `Self.luminance(red: metrics.averageColor.red, ...)` with `PreviewPixelMetrics.luminance(red: metrics.averageColor.red, green: metrics.averageColor.green, blue: metrics.averageColor.blue)`.
- In `previewMetrics(of:)`, replace the inline 16×16 buffer/`CGContext` block with:

```swift
        let sampleWidth = 16
        let sampleHeight = 16
        let pixels = try PreviewPixelMetrics.rgbaSamples(of: image, width: sampleWidth, height: sampleHeight)
```

- Delete the provider's private `focusScore(in:width:height:)`, `luminance(atX:y:in:width:)`, and `luminance(red:green:blue:)` functions; point remaining callers (`framingScore`, `averageLuminance`, and the `PreviewImageMetrics` construction) at `PreviewPixelMetrics.focusScore` / `PreviewPixelMetrics.luminance(atX:y:in:width:)`.
- Keep `averageColor`, `framingScore`, `averageLuminance`, `motionBlurScore`, and `aestheticScore` in the provider unchanged otherwise.

- [ ] **Step 5: Run tests to verify green (new test + no regressions)**

Run: `swift test --filter EvaluationProviderTests`
Expected: PASS — all existing `LocalImageMetrics*` tests still green, plus the new test.

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripCore/Evaluation/PreviewPixelMetrics.swift Sources/TeststripCore/Evaluation/LocalImageMetricsEvaluationProvider.swift Tests/TeststripCoreTests/EvaluationProviderTests.swift
git commit -m "refactor: extract shared preview pixel focus metric"
```

---

### Task 2: Add `smile` / `eyesOpen` / `eyeSharpness` signal kinds everywhere kinds are enumerated

Adding enum cases breaks every exhaustive `EvaluationKind` switch in TeststripApp, so the cases and all enumeration-site arms land together. All arms below are final values.

**Files:**
- Modify: `Sources/TeststripCore/Evaluation/EvaluationSignal.swift:3-16`
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift:1430-1463` (likelyIssue SQL)
- Modify: `Sources/TeststripApp/AppModel.swift:336-365` (displayName), `:8671-8684` (sidebar order)
- Modify: `Sources/TeststripApp/CopilotView.swift:544-596` (order + icons)
- Modify: `Sources/TeststripApp/InspectorView.swift:152-191` (group + title)
- Modify: `Sources/TeststripApp/LibrarySearchIntent.swift:195-211` (field-token kinds)
- Modify: `Sources/TeststripApp/LibraryGridView.swift:1880-1882` (filter options), `:3656-3684` (`EvaluationSignalPresentation.displayName`), `:6311-6318` (`rationaleText` kind list), `:6329-6356` (`rank`)
- Test: `Tests/TeststripCoreTests/EvaluationProviderTests.swift`, `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`, `Tests/TeststripAppTests/LibrarySearchIntentTests.swift`

**Interfaces:**
- Consumes: `EvaluationKind` (String-raw Codable enum), `SetQuery.Predicate.evaluationKind`, `LibrarySearchIntent.parse`.
- Produces: `EvaluationKind.smile` (raw `"smile"`), `.eyesOpen` (raw `"eyesOpen"`), `.eyeSharpness` (raw `"eyeSharpness"`); `displayName` values `"Smile"` / `"Eyes Open"` / `"Eye Sharpness"` (AppModel) and `"Smile"` / `"Eyes open"` / `"Eye sharpness"` (LibraryGridView/Inspector); eyes-closed rows join the existing Likely Issues queue predicate.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/EvaluationProviderTests.swift`:

```swift
    func testCullingExpressionKindsRoundTripThroughJSON() throws {
        for kind in [EvaluationKind.smile, .eyesOpen, .eyeSharpness] {
            let data = try JSONEncoder().encode(kind)
            XCTAssertEqual(try JSONDecoder().decode(EvaluationKind.self, from: data), kind)
        }
    }
```

Add to `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`:

```swift
    func testEyesClosedSignalJoinsLikelyIssueQueue() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-eyes-closed-likely-issue")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let closed = Asset.testAsset(id: AssetID(rawValue: "closed"), path: "/Volumes/NAS/Job/closed.jpg", rating: 0)
        let open = Asset.testAsset(id: AssetID(rawValue: "open"), path: "/Volumes/NAS/Job/open.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "core-image-faces", model: "CIDetectorFace", version: "1", settingsHash: "default")
        try repository.upsert([closed, open])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: closed.id, kind: .eyesOpen, value: .score(0.0), confidence: 0.7, provenance: provenance),
            EvaluationSignal(assetID: open.id, kind: .eyesOpen, value: .score(1.0), confidence: 0.7, provenance: provenance)
        ])

        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyIssue]), limit: 10).map(\.id),
            [closed.id]
        )
        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.evaluationKind(.eyesOpen)]), limit: 10)
                .map(\.id.rawValue)
                .sorted(),
            ["closed", "open"]
        )
    }
```

Add to `Tests/TeststripAppTests/LibrarySearchIntentTests.swift`:

```swift
    func testParsesExpressionSignalFieldTokens() {
        let eyesOpen = LibrarySearchIntent.parse("signal:eyesopen")
        XCTAssertEqual(eyesOpen.predicates, [.evaluationKind(.eyesOpen)])
        XCTAssertEqual(eyesOpen.chips, ["Signal: Eyes Open"])

        let smile = LibrarySearchIntent.parse("signal:smile")
        XCTAssertEqual(smile.predicates, [.evaluationKind(.smile)])

        let eyeSharpness = LibrarySearchIntent.parse("signal:eyesharpness")
        XCTAssertEqual(eyeSharpness.predicates, [.evaluationKind(.eyeSharpness)])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EvaluationProviderTests.testCullingExpressionKindsRoundTripThroughJSON`
Expected: compile FAILURE — `type 'EvaluationKind' has no member 'smile'`

- [ ] **Step 3: Add the enum cases**

`Sources/TeststripCore/Evaluation/EvaluationSignal.swift` — append cases:

```swift
public enum EvaluationKind: String, Codable, Sendable {
    case focus
    case motionBlur
    case exposure
    case aesthetics
    case framing
    case object
    case faceCount
    case faceQuality
    case ocrText
    case colorPalette
    case novelty
    case visualSimilarity
    case smile
    case eyesOpen
    case eyeSharpness
}
```

- [ ] **Step 4: Fix every exhaustive switch and enumeration site**

Run `swift build 2>&1 | head -50` and fix each compile error with exactly these arms (the compiler must flag every site listed here; if it flags an additional site not listed, add the analogous honest arm and note it in the commit message):

1. `Sources/TeststripApp/AppModel.swift` `EvaluationKind.displayName` (line ~336) — add:

```swift
        case .smile:
            return "Smile"
        case .eyesOpen:
            return "Eyes Open"
        case .eyeSharpness:
            return "Eye Sharpness"
```

2. `Sources/TeststripApp/AppModel.swift` `evaluationKindSidebarOrder` (line ~8671) — insert after `.faceQuality`:

```swift
    private static let evaluationKindSidebarOrder: [EvaluationKind] = [
        .faceCount,
        .faceQuality,
        .eyesOpen,
        .eyeSharpness,
        .smile,
        .object,
        .ocrText,
        .focus,
        .motionBlur,
        .exposure,
        .aesthetics,
        .framing,
        .colorPalette,
        .novelty,
        .visualSimilarity
    ]
```

(`evaluationKindSidebarTitle` has a `default:` returning `displayName` — no change.)

3. `Sources/TeststripApp/CopilotView.swift` `signalKindOrder` (line ~544) — insert after `.faceQuality`:

```swift
    private var signalKindOrder: [EvaluationKind] {
        [.object, .focus, .ocrText, .faceCount, .faceQuality, .eyesOpen, .eyeSharpness, .smile, .motionBlur, .exposure, .aesthetics, .framing, .colorPalette, .novelty, .visualSimilarity]
    }
```

`signalIcon(for:)` (exhaustive, line ~569) — add:

```swift
        case .smile:
            return "face.smiling"
        case .eyesOpen:
            return "eye"
        case .eyeSharpness:
            return "eye.circle"
```

(`signalTitle` has `default:` — no change.)

4. `Sources/TeststripApp/InspectorView.swift` `groupTitle(for:)` (line ~152) — extend the Faces arm:

```swift
        case .faceCount, .faceQuality, .smile, .eyesOpen, .eyeSharpness:
            return "Faces"
```

`title(for:)` (line ~176) — add:

```swift
        case .smile: "Smile"
        case .eyesOpen: "Eyes open"
        case .eyeSharpness: "Eye sharpness"
```

5. `Sources/TeststripApp/LibrarySearchIntent.swift` `evaluationKind(from:)` (line ~195) — append `.smile, .eyesOpen, .eyeSharpness` to the candidates array:

```swift
        return [
            EvaluationKind.focus,
            .motionBlur,
            .exposure,
            .aesthetics,
            .framing,
            .object,
            .faceCount,
            .faceQuality,
            .ocrText,
            .colorPalette,
            .novelty,
            .visualSimilarity,
            .smile,
            .eyesOpen,
            .eyeSharpness
        ].first { compactIdentifier($0.rawValue) == normalized }
```

6. `Sources/TeststripApp/LibraryGridView.swift` `evaluationKindFilterOptions` (line ~1880):

```swift
    private var evaluationKindFilterOptions: [EvaluationKind] {
        [.focus, .motionBlur, .exposure, .aesthetics, .framing, .object, .faceCount, .faceQuality, .eyesOpen, .eyeSharpness, .smile, .ocrText, .colorPalette, .novelty, .visualSimilarity]
    }
```

7. `Sources/TeststripApp/LibraryGridView.swift` `EvaluationSignalPresentation.displayName` (line ~3657) — add:

```swift
        case .smile:
            return "Smile"
        case .eyesOpen:
            return "Eyes open"
        case .eyeSharpness:
            return "Eye sharpness"
```

8. `Sources/TeststripApp/LibraryGridView.swift` `CullingAssistPresentation.rationaleText(for:)` (line ~6311) — for now the new kinds emit no rationale (Task 6 gives them phrases):

```swift
        case .object, .ocrText, .smile, .eyesOpen, .eyeSharpness:
            return nil
```

9. `Sources/TeststripApp/LibraryGridView.swift` `CullingAssistPresentation.rank(for:)` (line ~6329) — full replacement switch (new kinds slot after `faceQuality`; existing relative order preserved):

```swift
    private static func rank(for kind: EvaluationKind) -> Int {
        switch kind {
        case .aesthetics:
            return 0
        case .framing:
            return 1
        case .motionBlur:
            return 2
        case .focus:
            return 3
        case .faceQuality:
            return 4
        case .eyesOpen:
            return 5
        case .eyeSharpness:
            return 6
        case .smile:
            return 7
        case .faceCount:
            return 8
        case .exposure:
            return 9
        case .object:
            return 10
        case .ocrText:
            return 11
        case .novelty:
            return 12
        case .colorPalette:
            return 13
        case .visualSimilarity:
            return 14
        }
    }
```

- [ ] **Step 5: Add the eyes-closed clause to the likelyIssue SQL**

In `Sources/TeststripCore/Catalog/CatalogRepository.swift`, inside the `case .likelyIssue:` clause string (line ~1430), insert a new OR arm after the `exposure` group (line ~1446), before the `faceQuality` group:

```sql
                            OR (
                                kind = 'eyesOpen'
                                AND CAST(json_extract(value_json, '$.score._0') AS REAL) < 1.0
                            )
```

- [ ] **Step 6: Run tests to verify green**

Run: `swift test --filter "EvaluationProviderTests.testCullingExpressionKindsRoundTripThroughJSON|CatalogDatabaseTests.testEyesClosedSignalJoinsLikelyIssueQueue|LibrarySearchIntentTests.testParsesExpressionSignalFieldTokens"`
Expected: PASS

Then run the full suite to catch any enumeration site with baked-in expectations:

Run: `swift test`
Expected: PASS (if an existing test asserts a kind list that now differs, update that test's expectation to include the new kinds in the orders specified above — that is the only permitted change).

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripCore/Evaluation/EvaluationSignal.swift Sources/TeststripCore/Catalog/CatalogRepository.swift Sources/TeststripApp/AppModel.swift Sources/TeststripApp/CopilotView.swift Sources/TeststripApp/InspectorView.swift Sources/TeststripApp/LibrarySearchIntent.swift Sources/TeststripApp/LibraryGridView.swift Tests/TeststripCoreTests/EvaluationProviderTests.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift Tests/TeststripAppTests/LibrarySearchIntentTests.swift
git commit -m "feat: add smile and eye culling signal kinds"
```

---

### Task 3: Face expression provider — smile and eyes-open signals

**Files:**
- Create: `Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift`
- Create: `Tests/TeststripCoreTests/FaceExpressionEvaluationProviderTests.swift`

**Interfaces:**
- Consumes: `EvaluationProvider` protocol (`name: String`, `evaluate(assetID:previewURL:) throws -> [EvaluationSignal]`), kinds from Task 2.
- Produces (used by Tasks 4–5):
  - `public struct DetectedFaceExpression: Equatable, Sendable` with `normalizedBounds: CGRect`, `hasSmile: Bool`, `leftEyeClosed: Bool`, `rightEyeClosed: Bool`, `leftEyeCenter: CGPoint?`, `rightEyeCenter: CGPoint?` (all coordinates normalized 0–1, top-left origin)
  - `public protocol FaceExpressionAnalyzing: Sendable { func detectFaces(previewURL: URL) throws -> [DetectedFaceExpression] }`
  - `public struct FaceExpressionEvaluationProvider: EvaluationProvider` with `name == "core-image-faces"` and `public init(analyzer: any FaceExpressionAnalyzing)`
  - Signal emission order: `.eyesOpen`, `.smile` (Task 4 appends `.eyeSharpness` last)

- [ ] **Step 1: Write the failing tests**

Create `Tests/TeststripCoreTests/FaceExpressionEvaluationProviderTests.swift`:

```swift
import CoreGraphics
import Foundation
import XCTest
@testable import TeststripCore

final class FaceExpressionEvaluationProviderTests: XCTestCase {
    func testFaceExpressionProviderMapsSmileAndEyeStateToPerPhotoFractions() throws {
        let faces = [
            DetectedFaceExpression(
                normalizedBounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.3),
                hasSmile: true,
                leftEyeClosed: false,
                rightEyeClosed: false,
                leftEyeCenter: nil,
                rightEyeCenter: nil
            ),
            DetectedFaceExpression(
                normalizedBounds: CGRect(x: 0.55, y: 0.25, width: 0.3, height: 0.3),
                hasSmile: false,
                leftEyeClosed: true,
                rightEyeClosed: false,
                leftEyeCenter: nil,
                rightEyeCenter: nil
            )
        ]
        let provider = FaceExpressionEvaluationProvider(analyzer: FakeFaceExpressionAnalyzer(faces: faces))
        let assetID = AssetID(rawValue: "asset-1")
        let provenance = ProviderProvenance(provider: "core-image-faces", model: "CIDetectorFace", version: "1", settingsHash: "default")

        let signals = try provider.evaluate(assetID: assetID, previewURL: URL(fileURLWithPath: "/tmp/preview.png"))

        XCTAssertEqual(signals, [
            EvaluationSignal(assetID: assetID, kind: .eyesOpen, value: .score(0.5), confidence: 0.7, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .smile, value: .score(0.5), confidence: 0.7, provenance: provenance)
        ])
    }

    func testFaceExpressionProviderReportsAllOpenAndAllSmilingAsFullScores() throws {
        let faces = [
            DetectedFaceExpression(
                normalizedBounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.3),
                hasSmile: true,
                leftEyeClosed: false,
                rightEyeClosed: false,
                leftEyeCenter: nil,
                rightEyeCenter: nil
            )
        ]
        let provider = FaceExpressionEvaluationProvider(analyzer: FakeFaceExpressionAnalyzer(faces: faces))

        let signals = try provider.evaluate(assetID: AssetID(rawValue: "asset-1"), previewURL: URL(fileURLWithPath: "/tmp/preview.png"))

        XCTAssertEqual(signals.map(\.kind), [.eyesOpen, .smile])
        XCTAssertEqual(signals.map(\.value), [.score(1.0), .score(1.0)])
    }

    func testFaceExpressionProviderEmitsNoSignalsWithoutFaces() throws {
        let provider = FaceExpressionEvaluationProvider(analyzer: FakeFaceExpressionAnalyzer(faces: []))

        let signals = try provider.evaluate(assetID: AssetID(rawValue: "asset-1"), previewURL: URL(fileURLWithPath: "/tmp/preview.png"))

        XCTAssertEqual(signals, [])
    }
}

struct FakeFaceExpressionAnalyzer: FaceExpressionAnalyzing {
    var faces: [DetectedFaceExpression]

    func detectFaces(previewURL: URL) throws -> [DetectedFaceExpression] {
        faces
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FaceExpressionEvaluationProviderTests`
Expected: compile FAILURE — `cannot find 'DetectedFaceExpression' in scope`

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift`:

```swift
import CoreGraphics
import Foundation

/// One face found by the expression detector. All coordinates are normalized
/// to [0, 1] with a top-left origin so preview pixel math is size-independent.
public struct DetectedFaceExpression: Equatable, Sendable {
    public var normalizedBounds: CGRect
    public var hasSmile: Bool
    public var leftEyeClosed: Bool
    public var rightEyeClosed: Bool
    /// Eye centers; nil when the detector could not locate that eye.
    public var leftEyeCenter: CGPoint?
    public var rightEyeCenter: CGPoint?

    public init(
        normalizedBounds: CGRect,
        hasSmile: Bool,
        leftEyeClosed: Bool,
        rightEyeClosed: Bool,
        leftEyeCenter: CGPoint?,
        rightEyeCenter: CGPoint?
    ) {
        self.normalizedBounds = normalizedBounds
        self.hasSmile = hasSmile
        self.leftEyeClosed = leftEyeClosed
        self.rightEyeClosed = rightEyeClosed
        self.leftEyeCenter = leftEyeCenter
        self.rightEyeCenter = rightEyeCenter
    }

    var hasBothEyesOpen: Bool {
        !leftEyeClosed && !rightEyeClosed
    }
}

public protocol FaceExpressionAnalyzing: Sendable {
    func detectFaces(previewURL: URL) throws -> [DetectedFaceExpression]
}

/// Per-photo smile and eye-state culling signals aggregated from per-face
/// expression detection over the cached preview.
public struct FaceExpressionEvaluationProvider: EvaluationProvider {
    public let name = "core-image-faces"

    private let analyzer: any FaceExpressionAnalyzing

    public init(analyzer: any FaceExpressionAnalyzing) {
        self.analyzer = analyzer
    }

    public func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        let faces = try analyzer.detectFaces(previewURL: previewURL)
        guard !faces.isEmpty else { return [] }
        let provenance = ProviderProvenance(provider: name, model: "CIDetectorFace", version: "1", settingsHash: "default")
        let faceCount = Double(faces.count)
        let eyesOpenFraction = Double(faces.filter(\.hasBothEyesOpen).count) / faceCount
        let smileFraction = Double(faces.filter(\.hasSmile).count) / faceCount
        return [
            EvaluationSignal(
                assetID: assetID,
                kind: .eyesOpen,
                value: .score(eyesOpenFraction),
                confidence: 0.7,
                provenance: provenance
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .smile,
                value: .score(smileFraction),
                confidence: 0.7,
                provenance: provenance
            )
        ]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FaceExpressionEvaluationProviderTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift Tests/TeststripCoreTests/FaceExpressionEvaluationProviderTests.swift
git commit -m "feat: add core-image face expression evaluation provider"
```

---

### Task 4: Eye-region sharpness signal (`eyeSharpness`)

**Files:**
- Modify: `Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift`
- Test: `Tests/TeststripCoreTests/FaceExpressionEvaluationProviderTests.swift`

**Interfaces:**
- Consumes: `PreviewPixelMetrics.rgbaSamples(of:width:height:)` / `.focusScore(in:width:height:)` (Task 1), `DetectedFaceExpression` eye geometry (Task 3).
- Produces: `FaceExpressionEvaluationProvider.evaluate` appends an `.eyeSharpness` `.score` signal (confidence 0.6) after `.eyesOpen` and `.smile` whenever at least one eye crop is scoreable. Constants: eye crop side = `0.25 ×` face width in pixels, minimum crop side 8 px, 16×16 sampling.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/FaceExpressionEvaluationProviderTests.swift` (imports already include `CoreGraphics`; add `import ImageIO` and `import UniformTypeIdentifiers` at the top of the file):

```swift
    func testEyeSharpnessUsesSharpestEyePerFaceFromPreviewCrops() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "face-expression-eye-sharpness")
        let previewURL = directory.appendingPathComponent("preview.png")
        // Checkerboard "eye" detail in the top-left quadrant, flat gray everywhere else.
        try writeEyePatchPNG(
            to: previewURL,
            width: 256,
            height: 256,
            patch: CGRect(x: 32, y: 32, width: 64, height: 64),
            cellSize: 4
        )
        // Face covering the left half; left eye over the detailed patch, right eye over flat gray.
        let face = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: CGPoint(x: 0.25, y: 0.25),
            rightEyeCenter: CGPoint(x: 0.75, y: 0.75)
        )
        let provider = FaceExpressionEvaluationProvider(analyzer: FakeFaceExpressionAnalyzer(faces: [face]))

        let signals = try provider.evaluate(assetID: AssetID(rawValue: "asset-1"), previewURL: previewURL)

        XCTAssertEqual(signals.map(\.kind), [.eyesOpen, .smile, .eyeSharpness])
        guard case .score(let sharpness)? = signals.last?.value else {
            return XCTFail("expected eye sharpness score")
        }
        // Sharpest eye per face: the checkerboard eye wins over the flat eye.
        XCTAssertGreaterThan(sharpness, 0.2)
        XCTAssertEqual(signals.last?.confidence, 0.6)
    }

    func testEyeSharpnessTakesWeakestFacePerPhoto() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "face-expression-eye-sharpness-min")
        let previewURL = directory.appendingPathComponent("preview.png")
        try writeEyePatchPNG(
            to: previewURL,
            width: 256,
            height: 256,
            patch: CGRect(x: 32, y: 32, width: 64, height: 64),
            cellSize: 4
        )
        let sharpFace = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: CGPoint(x: 0.25, y: 0.25),
            rightEyeCenter: nil
        )
        let softFace = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: CGPoint(x: 0.75, y: 0.75),
            rightEyeCenter: nil
        )
        let provider = FaceExpressionEvaluationProvider(
            analyzer: FakeFaceExpressionAnalyzer(faces: [sharpFace, softFace])
        )

        let signals = try provider.evaluate(assetID: AssetID(rawValue: "asset-1"), previewURL: previewURL)

        guard case .score(let sharpness)? = signals.last?.value else {
            return XCTFail("expected eye sharpness score")
        }
        // Photo score is the minimum across faces: the flat-eyed face drags it down.
        XCTAssertLessThan(sharpness, 0.05)
    }

    func testEyeSharpnessSkipsCropsSmallerThanMinimumPixels() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "face-expression-eye-sharpness-small")
        let previewURL = directory.appendingPathComponent("preview.png")
        try writeEyePatchPNG(
            to: previewURL,
            width: 256,
            height: 256,
            patch: CGRect(x: 32, y: 32, width: 64, height: 64),
            cellSize: 4
        )
        // 0.25 * 0.1 * 256 = 6.4 px crop side, below the 8 px floor.
        let tinyFace = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: CGPoint(x: 0.25, y: 0.25),
            rightEyeCenter: nil
        )
        let provider = FaceExpressionEvaluationProvider(analyzer: FakeFaceExpressionAnalyzer(faces: [tinyFace]))

        let signals = try provider.evaluate(assetID: AssetID(rawValue: "asset-1"), previewURL: previewURL)

        XCTAssertEqual(signals.map(\.kind), [.eyesOpen, .smile])
    }
```

And the file-scope test helper at the bottom of the same file:

```swift
private func writeEyePatchPNG(to url: URL, width: Int, height: Int, patch: CGRect, cellSize: Int) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TeststripError.io("could not create test bitmap context")
    }
    context.setFillColor(CGColor(gray: 0.5, alpha: 1.0))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // CGContext draws with a bottom-left origin; `patch` is specified top-left.
    let flippedPatchMinY = Double(height) - patch.maxY
    for y in stride(from: 0, to: Int(patch.height), by: cellSize) {
        for x in stride(from: 0, to: Int(patch.width), by: cellSize) {
            let isLight = ((x / cellSize) + (y / cellSize)).isMultiple(of: 2)
            context.setFillColor(CGColor(gray: isLight ? 1.0 : 0.0, alpha: 1.0))
            context.fill(CGRect(
                x: patch.minX + Double(x),
                y: flippedPatchMinY + Double(y),
                width: Double(cellSize),
                height: Double(cellSize)
            ))
        }
    }
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw TeststripError.io("could not create test png")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TeststripError.io("could not write test png")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FaceExpressionEvaluationProviderTests`
Expected: FAIL — `testEyeSharpnessUsesSharpestEyePerFaceFromPreviewCrops` gets `[.eyesOpen, .smile]` (no `.eyeSharpness` signal); the other two new tests fail/pass respectively for the same reason (small-crop test may pass vacuously — that is fine, it locks the behavior).

- [ ] **Step 3: Write the minimal implementation**

In `Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift`, add `import ImageIO` at the top, change `evaluate` to append the sharpness signal, and add the private helpers:

```swift
    public func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        let faces = try analyzer.detectFaces(previewURL: previewURL)
        guard !faces.isEmpty else { return [] }
        let provenance = ProviderProvenance(provider: name, model: "CIDetectorFace", version: "1", settingsHash: "default")
        let faceCount = Double(faces.count)
        let eyesOpenFraction = Double(faces.filter(\.hasBothEyesOpen).count) / faceCount
        let smileFraction = Double(faces.filter(\.hasSmile).count) / faceCount
        var signals = [
            EvaluationSignal(
                assetID: assetID,
                kind: .eyesOpen,
                value: .score(eyesOpenFraction),
                confidence: 0.7,
                provenance: provenance
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .smile,
                value: .score(smileFraction),
                confidence: 0.7,
                provenance: provenance
            )
        ]
        if let eyeSharpness = try Self.eyeSharpnessScore(previewURL: previewURL, faces: faces) {
            signals.append(EvaluationSignal(
                assetID: assetID,
                kind: .eyeSharpness,
                value: .score(eyeSharpness),
                confidence: 0.6,
                provenance: provenance
            ))
        }
        return signals
    }

    /// Eye crops are squares of `eyeCropFractionOfFaceWidth` x face width centered
    /// on each detected eye; crops under `minimumEyeCropPixels` are skipped so
    /// tiny previews do not produce noise scores.
    private static let eyeCropFractionOfFaceWidth = 0.25
    private static let minimumEyeCropPixels = 8
    private static let sampleSize = 16

    private static func eyeSharpnessScore(previewURL: URL, faces: [DetectedFaceExpression]) throws -> Double? {
        let facesWithEyes = faces.filter { $0.leftEyeCenter != nil || $0.rightEyeCenter != nil }
        guard !facesWithEyes.isEmpty else { return nil }
        guard let source = CGImageSourceCreateWithURL(previewURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TeststripError.unsupportedFormat("ImageIO could not read \(previewURL.lastPathComponent)")
        }
        var perFaceScores: [Double] = []
        for face in facesWithEyes {
            var eyeScores: [Double] = []
            for eyeCenter in [face.leftEyeCenter, face.rightEyeCenter].compactMap({ $0 }) {
                guard let crop = eyeCrop(of: image, face: face, eyeCenter: eyeCenter) else { continue }
                let pixels = try PreviewPixelMetrics.rgbaSamples(of: crop, width: sampleSize, height: sampleSize)
                eyeScores.append(PreviewPixelMetrics.focusScore(in: pixels, width: sampleSize, height: sampleSize))
            }
            if let sharpestEye = eyeScores.max() {
                perFaceScores.append(sharpestEye)
            }
        }
        // A photo's eyes are only as sharp as its weakest subject's best eye.
        return perFaceScores.min()
    }

    private static func eyeCrop(of image: CGImage, face: DetectedFaceExpression, eyeCenter: CGPoint) -> CGImage? {
        let imageWidth = Double(image.width)
        let imageHeight = Double(image.height)
        let side = (eyeCropFractionOfFaceWidth * face.normalizedBounds.width * imageWidth).rounded()
        guard side >= Double(minimumEyeCropPixels) else { return nil }
        let cropRect = CGRect(
            x: (eyeCenter.x * imageWidth - side / 2).rounded(),
            y: (eyeCenter.y * imageHeight - side / 2).rounded(),
            width: side,
            height: side
        ).intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        guard cropRect.width >= Double(minimumEyeCropPixels),
              cropRect.height >= Double(minimumEyeCropPixels) else {
            return nil
        }
        return image.cropping(to: cropRect)
    }
```

(`DetectedFaceExpression` coordinates are top-left-origin, matching `CGImage.cropping(to:)` pixel space — no flip here; the analyzer in Task 5 does the CoreImage flip.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FaceExpressionEvaluationProviderTests`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift Tests/TeststripCoreTests/FaceExpressionEvaluationProviderTests.swift
git commit -m "feat: score eye-region sharpness from cached previews"
```

---

### Task 5: CIDetector analyzer + worker and app registration

**Files:**
- Modify: `Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift` (analyzer + default init argument)
- Modify: `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift:140-143`
- Modify: `Sources/TeststripApp/AppModel.swift:1215-1216`
- Test: `Tests/TeststripCoreTests/FaceExpressionEvaluationProviderTests.swift`, `Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift`, `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `FaceExpressionAnalyzing` (Task 3), `WorkerRuntimeConfiguration`-based `WorkerCommandExecutor.init` default provider list, `AppModel.defaultEvaluationProviderNames`.
- Produces: `public struct CoreImageFaceExpressionAnalyzer: FaceExpressionAnalyzing` with `public init()`; `FaceExpressionEvaluationProvider.init(analyzer:)` gains default `= CoreImageFaceExpressionAnalyzer()`; worker resolves provider name `"core-image-faces"`; `AppModel.defaultEvaluationProviderNames == ["local-image-metrics", "apple-vision", "core-image-faces"]` so every existing bulk-evaluation entry point (selected/visible/current-scope/latest-import/compare) schedules the pass with no further changes.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/FaceExpressionEvaluationProviderTests.swift`:

```swift
    func testCoreImageAnalyzerFindsNoFacesInFacelessImage() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "core-image-face-analyzer")
        let previewURL = directory.appendingPathComponent("preview.jpg")
        try TestDirectories.writeTestJPEG(to: previewURL, width: 512, height: 340)

        XCTAssertEqual(try CoreImageFaceExpressionAnalyzer().detectFaces(previewURL: previewURL), [])
    }
```

Add to `Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift` (mirror the scaffold of `testRuntimeConfigurationRegistersAppleVisionProvider` at line ~787 exactly, changing names):

```swift
    func testRuntimeConfigurationRegistersFaceExpressionProvider() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-runtime-face-expression")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
        let catalogURL = root.appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: previewURL, width: 512, height: 340)
        let executor = try WorkerCommandExecutor(configuration: WorkerRuntimeConfiguration(
            catalogURL: catalogURL,
            previewCacheRoot: previewCache.root
        ))

        let result = try executor.execute(.runEvaluation(assetID: asset.id, provider: "core-image-faces"))

        XCTAssertEqual(result, .completed("evaluated source.jpg with core-image-faces"))
        // The faceless test JPEG must record no expression signals rather than fake reads.
        XCTAssertEqual(try repository.evaluationSignals(assetID: asset.id), [])
    }
```

Add to `Tests/TeststripAppTests/AppModelTests.swift`:

```swift
    func testDefaultEvaluationProvidersIncludeFaceExpressionPass() {
        XCTAssertEqual(
            AppModel.defaultEvaluationProviderNames,
            ["local-image-metrics", "apple-vision", "core-image-faces"]
        )
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "FaceExpressionEvaluationProviderTests.testCoreImageAnalyzerFindsNoFacesInFacelessImage"`
Expected: compile FAILURE — `cannot find 'CoreImageFaceExpressionAnalyzer' in scope`

- [ ] **Step 3: Write the minimal implementation**

Append to `Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift` (add `import CoreImage` at the top):

```swift
/// Stock face expression detection via CoreImage's CIDetector with the
/// smile and eye-blink options. Chosen over Vision landmarks because it is
/// the only stock per-face smile source and supplies blink booleans and eye
/// positions from the same face set in one pass.
public struct CoreImageFaceExpressionAnalyzer: FaceExpressionAnalyzing {
    public init() {}

    public func detectFaces(previewURL: URL) throws -> [DetectedFaceExpression] {
        guard let image = CIImage(contentsOf: previewURL) else {
            throw TeststripError.unsupportedFormat("CoreImage could not read \(previewURL.lastPathComponent)")
        }
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            throw TeststripError.unsupportedFormat("empty image extent for \(previewURL.lastPathComponent)")
        }
        guard let detector = CIDetector(
            ofType: CIDetectorTypeFace,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ) else {
            throw TeststripError.invalidState("could not create CoreImage face detector")
        }
        return detector
            .features(in: image, options: [CIDetectorSmile: true, CIDetectorEyeBlink: true])
            .compactMap { $0 as? CIFaceFeature }
            .map { face in
                DetectedFaceExpression(
                    normalizedBounds: Self.normalizedTopLeftRect(face.bounds, in: extent),
                    hasSmile: face.hasSmile,
                    leftEyeClosed: face.leftEyeClosed,
                    rightEyeClosed: face.rightEyeClosed,
                    leftEyeCenter: face.hasLeftEyePosition
                        ? Self.normalizedTopLeftPoint(face.leftEyePosition, in: extent)
                        : nil,
                    rightEyeCenter: face.hasRightEyePosition
                        ? Self.normalizedTopLeftPoint(face.rightEyePosition, in: extent)
                        : nil
                )
            }
    }

    /// CoreImage geometry is bottom-left origin in pixels; signals consume
    /// normalized top-left coordinates, so normalize and flip Y.
    private static func normalizedTopLeftRect(_ rect: CGRect, in extent: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - extent.minX) / extent.width,
            y: 1.0 - (rect.maxY - extent.minY) / extent.height,
            width: rect.width / extent.width,
            height: rect.height / extent.height
        )
    }

    private static func normalizedTopLeftPoint(_ point: CGPoint, in extent: CGRect) -> CGPoint {
        CGPoint(
            x: (point.x - extent.minX) / extent.width,
            y: 1.0 - (point.y - extent.minY) / extent.height
        )
    }
}
```

Change the provider init to supply the default analyzer:

```swift
    public init(analyzer: any FaceExpressionAnalyzing = CoreImageFaceExpressionAnalyzer()) {
        self.analyzer = analyzer
    }
```

In `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift` (line ~140), register the provider:

```swift
        var evaluationProviders: [any EvaluationProvider] = [
            LocalImageMetricsEvaluationProvider(),
            AppleVisionEvaluationProvider(),
            FaceExpressionEvaluationProvider()
        ]
```

In `Sources/TeststripApp/AppModel.swift` (line ~1216):

```swift
    public static let defaultEvaluationProviderNames = [defaultEvaluationProviderName, "apple-vision", "core-image-faces"]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "FaceExpressionEvaluationProviderTests|WorkerCommandExecutorTests.testRuntimeConfigurationRegistersFaceExpressionProvider|AppModelTests.testDefaultEvaluationProvidersIncludeFaceExpressionPass"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift Sources/TeststripCore/Worker/WorkerCommandExecutor.swift Sources/TeststripApp/AppModel.swift Tests/TeststripCoreTests/FaceExpressionEvaluationProviderTests.swift Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: run face expression pass in worker evaluation flow"
```

---

### Task 6: Culling verdict pill reads eye and smile signals (mockup 2a)

Target copy shape (design 2a): "PICK 94% · sharp · eyes open · best of 6-frame burst". The pill's rationale strings are `CullingAssistPresentation.detail` parts; this task adds the eye/smile phrases and tones.

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` — `CullingAssistPresentation` (`rationaleText` line ~6311, `title` line ~6358, `tone` line ~6375)
- Modify: `Sources/TeststripApp/LiveMockupPlaceholder.swift` — `cullingAssistVerdict.currentFallback` copy refresh
- Test: `Tests/TeststripAppTests/CullingAssistPresentationTests.swift`

**Interfaces:**
- Consumes: signals of kinds `.eyesOpen`, `.eyeSharpness`, `.smile` with `.score` values (Tasks 3–4); `rank(for:)` values from Task 2 (`eyesOpen` 5, `eyeSharpness` 6, `smile` 7).
- Produces: rationale phrases `"Eyes open"` / `"Eyes shut"` / `"Some eyes shut"`, `"Eyes sharp"` / `"Eyes soft"`, `"Smiling"` / `"Some smiling"` (smile score 0 emits nothing); caution tone for shut eyes and soft eyes.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/CullingAssistPresentationTests.swift` (file already has the private `signal(kind:value:confidence:)` helper with provider `"local-http"`):

```swift
    func testEyeSignalsJoinVerdictRationaleAfterFocus() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.91), confidence: 0.82),
            signal(kind: .eyesOpen, value: .score(1.0), confidence: 0.7),
            signal(kind: .eyeSharpness, value: .score(0.84), confidence: 0.6)
        ])

        XCTAssertEqual(presentation.title, "Focus 91%")
        XCTAssertEqual(presentation.detail, "Focus - local-http - 82% confidence · Eyes open · Eyes sharp")
        XCTAssertEqual(presentation.tone, .positive)
    }

    func testAllEyesShutBecomesCautionVerdictWhenPrimary() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .eyesOpen, value: .score(0.0), confidence: 0.7)
        ])

        XCTAssertEqual(presentation.title, "Eyes shut")
        XCTAssertEqual(presentation.detail, "Eyes open - local-http - 70% confidence")
        XCTAssertEqual(presentation.tone, .caution)
    }

    func testPartialBlinkReadsAsSomeEyesShut() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.91), confidence: 0.82),
            signal(kind: .eyesOpen, value: .score(0.5), confidence: 0.7)
        ])

        XCTAssertEqual(presentation.detail, "Focus - local-http - 82% confidence · Some eyes shut")
    }

    func testSoftEyesUseCautionPhraseAndTone() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .eyeSharpness, value: .score(0.3), confidence: 0.6)
        ])

        XCTAssertEqual(presentation.title, "Eyes soft")
        XCTAssertEqual(presentation.tone, .caution)
    }

    func testSmilePhraseAppearsOnlyWhenSomeoneSmiles() {
        let noSmiles = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.91), confidence: 0.82),
            signal(kind: .smile, value: .score(0.0), confidence: 0.7)
        ])
        XCTAssertEqual(noSmiles.detail, "Focus - local-http - 82% confidence")

        let allSmiling = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.91), confidence: 0.82),
            signal(kind: .smile, value: .score(1.0), confidence: 0.7)
        ])
        XCTAssertEqual(allSmiling.detail, "Focus - local-http - 82% confidence · Smiling")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CullingAssistPresentationTests`
Expected: FAIL — new tests get generic strings like `"Eyes open 100%"` in detail / `"Eyes open 0%"` as title, no phrases.

- [ ] **Step 3: Write the minimal implementation**

In `Sources/TeststripApp/LibraryGridView.swift`, inside `CullingAssistPresentation`:

Add the phrase helper (near `rationaleText`):

```swift
    private static func expressionPhrase(for signal: EvaluationSignal) -> String? {
        guard case .score(let score) = signal.value else { return nil }
        switch signal.kind {
        case .eyesOpen:
            if score >= 1.0 { return "Eyes open" }
            if score <= 0.0 { return "Eyes shut" }
            return "Some eyes shut"
        case .eyeSharpness:
            return score >= 0.7 ? "Eyes sharp" : "Eyes soft"
        case .smile:
            if score >= 1.0 { return "Smiling" }
            if score > 0.0 { return "Some smiling" }
            return nil
        default:
            return nil
        }
    }
```

Update `rationaleText(for:)` — replace the Task 2 placement:

```swift
    private static func rationaleText(for signal: EvaluationSignal) -> String? {
        switch signal.kind {
        case .eyesOpen, .eyeSharpness, .smile:
            return expressionPhrase(for: signal)
        case .focus, .motionBlur, .exposure, .aesthetics, .framing, .faceQuality, .faceCount, .novelty, .colorPalette, .visualSimilarity:
            return title(for: signal)
        case .object, .ocrText:
            return nil
        }
    }
```

Update `title(for:)` — first line becomes a phrase check (rest of the body is today's code, unchanged):

```swift
    private static func title(for signal: EvaluationSignal) -> String {
        if let phrase = expressionPhrase(for: signal) {
            return phrase
        }
        switch signal.value {
        case .score(let score):
            return "\(EvaluationSignalPresentation.displayName(for: signal.kind)) \(EvaluationSignalPresentation.percentage(score))"
        case .label(let label):
            return EvaluationSignalPresentation.capitalized(label, fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .labels(let labels):
            return EvaluationSignalPresentation.capitalized(labels.joined(separator: ", "), fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .text(let text):
            return EvaluationSignalPresentation.capitalized(text, fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .count(let count):
            return "\(EvaluationSignalPresentation.displayName(for: signal.kind)) \(count)"
        case .vector:
            return "\(EvaluationSignalPresentation.displayName(for: signal.kind)) sampled"
        }
    }
```

Update `tone(for:)` — add before `default:`:

```swift
        case (.eyesOpen, .score(let score)):
            return score >= 1.0 ? .positive : .caution
        case (.eyeSharpness, .score(let score)):
            return score >= 0.7 ? .positive : .caution
        case (.smile, .score(let score)):
            return score > 0.0 ? .positive : .neutral
```

Note: `testSmilePhraseAppearsOnlyWhenSomeoneSmiles` relies on a smile score of 0 producing no rationale (`expressionPhrase` returns nil) — with `title(for:)` falling back to the generic `"Smile 0%"` only if smile were the primary signal, which its rank (7) prevents whenever any quality signal exists.

In `Sources/TeststripApp/LiveMockupPlaceholder.swift`, update `cullingAssistVerdict.currentFallback` to:

```swift
        currentFallback: "Selected-frame verdict uses persisted evaluation signals with compact supporting quality rationale — including eye-state, eye-sharpness, and smile reads when present — and stack-level keep recommendations surface when persisted quality signals rank the active stack."
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CullingAssistPresentationTests`
Expected: PASS (all existing + 5 new)

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift Sources/TeststripApp/LiveMockupPlaceholder.swift Tests/TeststripAppTests/CullingAssistPresentationTests.swift
git commit -m "feat: read eye and smile signals in culling verdict pill"
```

---

### Task 7: Stack keep recommendations rank on eyes and explain why (mockup 3a)

Target copy shape (design 3a): "Best of 9 is frame 3 — sharpest, eyes open". Here that becomes the `keepRecommended` action help: `"Keep frame 2 — sharpest, eyes open."`.

Branch behavior note: in stacks larger than 2 frames with 2+ ranked candidates, the ranked action is the existing `Keep top 2` (`keepTopRanked`) and carries no per-frame rationale — `keepRecommended` (and therefore this rationale copy) surfaces for two-frame stacks and for larger stacks where only one candidate has quality signals. Best-of-set rationale for larger sets is delivered by the Survey Compare `recommendationText` in Task 8, which computes the same phrases for any set size.

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` — `CullingStackRecommendation` (line ~3967), `CullingStackRailPresentation.rankedAction` (line ~3893) and its call site (line ~3863)
- Test: `Tests/TeststripAppTests/CullingStackRailPresentationTests.swift`

**Interfaces:**
- Consumes: `.eyesOpen` / `.eyeSharpness` `.score` signals; existing `weightedQualityScore` shape (`clampedScore * confidence * weight`).
- Produces:
  - `weightedQualityScore` weights: `.eyesOpen` → 90, `.eyeSharpness` → 70 (smile deliberately unranked)
  - `static func rationalePhrases(forWinner:stackAssetIDs:evaluationSignalsByAssetID:) -> [String]` on `CullingStackRecommendation`, phrases in order: `"sharpest"` (winner strictly tops focus among ≥2 focus-scored candidates), `"eyes open"` (winner's eyesOpen == 1.0). Task 8 reuses this.
  - `keepRecommended` help copy: `"Keep frame N — <phrases joined by ", ">."` when phrases exist, otherwise the existing `"Keep frame N based on focus and quality signals."`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/CullingStackRailPresentationTests.swift` (uses the existing `makeAsset(id:path:capturedAt:)` and `signal(assetID:kind:score:)` helpers; the signal helper uses confidence 0.9):

```swift
    func testRecommendedActionExplainsSharpestEyesOpenRationale() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let selected = makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: capturedAt)
        let alternate = makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1))

        let presentation = CullingStackRailPresentation(
            assets: [selected, alternate],
            selectedAssetID: selected.id,
            evaluationSignalsByAssetID: [
                selected.id: [
                    signal(assetID: selected.id, kind: .focus, score: 0.62)
                ],
                alternate.id: [
                    signal(assetID: alternate.id, kind: .focus, score: 0.94),
                    signal(assetID: alternate.id, kind: .eyesOpen, score: 1.0)
                ]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertEqual(presentation.items.map(\.isRecommended), [false, true])
        XCTAssertEqual(presentation.actions[1].action, .keepRecommended(alternate.id))
        XCTAssertEqual(presentation.actions[1].help, "Keep frame 2 — sharpest, eyes open.")
        XCTAssertEqual(presentation.actions[1].assistTitle, "Recommended frame 2")
    }

    func testEyesOpenSignalBreaksFocusTieInRecommendation() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let selected = makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: capturedAt)
        let alternate = makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1))

        let presentation = CullingStackRailPresentation(
            assets: [selected, alternate],
            selectedAssetID: selected.id,
            evaluationSignalsByAssetID: [
                selected.id: [
                    signal(assetID: selected.id, kind: .focus, score: 0.9),
                    signal(assetID: selected.id, kind: .eyesOpen, score: 0.0)
                ],
                alternate.id: [
                    signal(assetID: alternate.id, kind: .focus, score: 0.9),
                    signal(assetID: alternate.id, kind: .eyesOpen, score: 1.0)
                ]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertEqual(presentation.items.map(\.isRecommended), [false, true])
        XCTAssertEqual(presentation.actions[1].action, .keepRecommended(alternate.id))
        // Focus is tied, so "sharpest" is not claimed; eyes decide.
        XCTAssertEqual(presentation.actions[1].help, "Keep frame 2 — eyes open.")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CullingStackRailPresentationTests`
Expected: FAIL — help is `"Keep frame 2 based on focus and quality signals."`; the tie-break test does not recommend the eyes-open frame because `eyesOpen` has no ranking weight yet.

- [ ] **Step 3: Write the minimal implementation**

In `Sources/TeststripApp/LibraryGridView.swift`:

1. `CullingStackRecommendation.weightedQualityScore` — add before `default:`:

```swift
        case .eyesOpen:
            return clampedScore * confidence * 90
        case .eyeSharpness:
            return clampedScore * confidence * 70
```

(smile stays in `default: return nil` — not smiling is not a defect, so it must not sink a frame's rank.)

2. Add to `CullingStackRecommendation`:

```swift
    /// Short honest reasons why the winner leads the stack, in display order.
    static func rationalePhrases(
        forWinner winner: AssetID,
        stackAssetIDs: [AssetID],
        evaluationSignalsByAssetID: [AssetID: [EvaluationSignal]]
    ) -> [String] {
        var phrases: [String] = []
        let focusScores = stackAssetIDs.compactMap { assetID in
            bestScore(kind: .focus, in: evaluationSignalsByAssetID[assetID] ?? []).map { (assetID: assetID, score: $0) }
        }
        if focusScores.count >= 2,
           let winnerFocus = focusScores.first(where: { $0.assetID == winner })?.score,
           focusScores.allSatisfy({ $0.assetID == winner || $0.score < winnerFocus }) {
            phrases.append("sharpest")
        }
        if let eyesOpen = bestScore(kind: .eyesOpen, in: evaluationSignalsByAssetID[winner] ?? []),
           eyesOpen >= 1.0 {
            phrases.append("eyes open")
        }
        return phrases
    }

    private static func bestScore(kind: EvaluationKind, in signals: [EvaluationSignal]) -> Double? {
        signals
            .filter { $0.kind == kind }
            .compactMap { signal -> Double? in
                guard case .score(let score) = signal.value else { return nil }
                return score
            }
            .max()
    }
```

3. Rework `CullingStackRailPresentation.rankedAction` to build the help copy (and update its call site at line ~3863):

```swift
            Self.rankedAction(
                for: rankedCandidates,
                stackAssetIDs: stackScope.assetIDs,
                evaluationSignalsByAssetID: evaluationSignalsByAssetID
            ),
```

```swift
    private static func rankedAction(
        for rankedCandidates: [CullingStackRecommendation],
        stackAssetIDs: [AssetID],
        evaluationSignalsByAssetID: [AssetID: [EvaluationSignal]]
    ) -> CullingStackActionPresentation? {
        let topTwo = Array(rankedCandidates.prefix(2))
        if stackAssetIDs.count > 2, topTwo.count >= 2 {
            return CullingStackActionPresentation(
                action: .keepTopRanked(topTwo.map(\.assetID)),
                title: "Keep top 2",
                isEnabled: true,
                help: "Keep the two top-ranked frames based on focus and quality signals.",
                liveMockupPlaceholder: nil,
                assistTitle: "Top 2 frames"
            )
        }

        guard let recommendation = rankedCandidates.first else { return nil }

        let phrases = CullingStackRecommendation.rationalePhrases(
            forWinner: recommendation.assetID,
            stackAssetIDs: stackAssetIDs,
            evaluationSignalsByAssetID: evaluationSignalsByAssetID
        )
        let help = phrases.isEmpty
            ? "Keep frame \(recommendation.frameLabel) based on focus and quality signals."
            : "Keep frame \(recommendation.frameLabel) — \(phrases.joined(separator: ", "))."
        return CullingStackActionPresentation(
            action: .keepRecommended(recommendation.assetID),
            title: "Keep recommended \(recommendation.frameLabel)",
            isEnabled: true,
            help: help,
            liveMockupPlaceholder: nil,
            assistTitle: "Recommended frame \(recommendation.frameLabel)"
        )
    }
```

Existing-test compatibility check (do not change these tests): `testRecommendedActionUsesPersistedQualitySignals` has focus on only one candidate → fewer than 2 focus-scored candidates → phrases empty → old help retained → its `contains("focus")` assertion still passes. `testTwoFrameStackWithTwoSignalsStillOffersSingleRecommendedFrame` asserts titles only. `testKeepTopActionUsesTwoHighestPersistedQualitySignals` exercises the unchanged top-2 branch.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CullingStackRailPresentationTests`
Expected: PASS (all existing + 2 new)

Also run: `swift test --filter CullingAssistPresentationTests`
Expected: PASS (stack-guidance detail embeds the action help; fixtures construct their own actions so copy is unchanged)

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/CullingStackRailPresentationTests.swift
git commit -m "feat: explain stack keep recommendations with eye and sharpness rationale"
```

---

### Task 8: Survey Compare signal badges and recommendation rationale (mockup 2b)

Target badges (design 2b): `✦ BEST` on the ranked winner, `EYES CLOSED` on blink frames, `SOFT` on low-focus frames. Signal badges are a NEW presentation member so the metadata-honesty guarantees of `decisionBadges` stay intact.

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` — `CompareSurveyPresentation` (line ~3326), `CompareDecisionBadge.Tone` (line ~3546), `compareTile` (line ~4149), `compareBadgeForeground`/`compareBadgeBackground` (line ~4171)
- Test: `Tests/TeststripAppTests/CompareSurveyPresentationTests.swift`

**Interfaces:**
- Consumes: `CullingStackRecommendation.rankedCandidates` + `rationalePhrases` (Task 7), `.eyesOpen`/`.focus` `.score` signals.
- Produces:
  - `CompareDecisionBadge.Tone.best` (amber, black text)
  - `func signalBadges(for asset: Asset) -> [CompareDecisionBadge]` — `✦ BEST` (tone `.best`) only on the top-ranked asset when ≥2 candidates ranked; otherwise `EYES CLOSED` (tone `.destructive`) when best-confidence eyesOpen score < 1.0 and `SOFT` (tone `.destructive`) when best-confidence focus score < 0.5; `[]` with no signals
  - `recommendationText` gains rationale: `"Top signal: frame 3 — sharpest, eyes open"` when the ranked winner is not primary and phrases exist

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/CompareSurveyPresentationTests.swift`:

```swift
    func testSignalBadgesFlagBestEyesClosedAndSoftFrames() {
        let best = makeAsset(id: "best")
        let blink = makeAsset(id: "blink")
        let soft = makeAsset(id: "soft")
        let presentation = CompareSurveyPresentation(
            assets: [best, blink, soft],
            selectedAssetID: best.id,
            evaluationSignalsByAssetID: [
                best.id: [
                    signal(assetID: best.id, kind: .focus, score: 0.94),
                    signal(assetID: best.id, kind: .eyesOpen, score: 1.0)
                ],
                blink.id: [
                    signal(assetID: blink.id, kind: .focus, score: 0.9),
                    signal(assetID: blink.id, kind: .eyesOpen, score: 0.0)
                ],
                soft.id: [
                    signal(assetID: soft.id, kind: .focus, score: 0.3)
                ]
            ]
        )

        XCTAssertEqual(presentation.signalBadges(for: best), [
            CompareDecisionBadge(text: "✦ BEST", tone: .best)
        ])
        XCTAssertEqual(presentation.signalBadges(for: blink), [
            CompareDecisionBadge(text: "EYES CLOSED", tone: .destructive)
        ])
        XCTAssertEqual(presentation.signalBadges(for: soft), [
            CompareDecisionBadge(text: "SOFT", tone: .destructive)
        ])
    }

    func testSignalBadgesStaySilentWithoutRankedContendersOrSignals() {
        let only = makeAsset(id: "only")
        let unread = makeAsset(id: "unread")
        let presentation = CompareSurveyPresentation(
            assets: [only, unread],
            selectedAssetID: only.id,
            evaluationSignalsByAssetID: [
                only.id: [signal(assetID: only.id, kind: .focus, score: 0.94)]
            ]
        )

        // A single ranked candidate is not a comparison; no BEST claim.
        XCTAssertEqual(presentation.signalBadges(for: only), [])
        XCTAssertEqual(presentation.signalBadges(for: unread), [])
    }

    func testRecommendationTextExplainsWhyTopSignalFrameLeads() {
        let assets = [
            makeAsset(id: "primary"),
            makeAsset(id: "second"),
            makeAsset(id: "third")
        ]

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: [
                assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.72)],
                assets[2].id: [
                    signal(assetID: assets[2].id, kind: .focus, score: 0.95),
                    signal(assetID: assets[2].id, kind: .eyesOpen, score: 1.0)
                ]
            ]
        )

        XCTAssertEqual(presentation.recommendationText, "Top signal: frame 3 — sharpest, eyes open")
    }
```

Also update ONE existing expectation in `testRecommendationTextDoesNotSuggestPrimaryWhenAnotherFrameRanksHighest` (line ~62): its fixtures give two focus-scored candidates with a strict winner, so it now carries the sharpest phrase:

```swift
        XCTAssertEqual(presentation.recommendationText, "Top signal: frame 3 — sharpest")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CompareSurveyPresentationTests`
Expected: compile FAILURE — `value of type 'CompareSurveyPresentation' has no member 'signalBadges'`

- [ ] **Step 3: Write the minimal implementation**

In `Sources/TeststripApp/LibraryGridView.swift`:

1. `CompareDecisionBadge.Tone` — add case:

```swift
    enum Tone: String, Equatable {
        case primary
        case positive
        case destructive
        case rating
        case label
        case best
    }
```

2. Badge colors (line ~4171):

```swift
    private func compareBadgeForeground(for tone: CompareDecisionBadge.Tone) -> Color {
        switch tone {
        case .primary, .rating, .best:
            return .black
        case .positive, .destructive, .label:
            return .white
        }
    }
```

```swift
        case .best:
            return .orange
```
(added as a new case in `compareBadgeBackground`.)

3. `CompareSurveyPresentation` — add a stored property and accessor, compute in both init paths:

```swift
    private var signalBadgesByAssetID: [AssetID: [CompareDecisionBadge]]
```

In the empty-assets guard branch add `self.signalBadgesByAssetID = [:]`. In the main init body, after `rankedCandidates` is computed:

```swift
        self.signalBadgesByAssetID = Self.signalBadges(
            assetIDs: assets.map(\.id),
            bestAssetID: rankedCandidates.count >= 2 ? rankedCandidates.first?.assetID : nil,
            evaluationSignalsByAssetID: evaluationSignalsByAssetID
        )
```

And replace the `recommendationText` assignment with a phrase-aware call:

```swift
        let recommendationPhrases = recommendation.map { winner in
            CullingStackRecommendation.rationalePhrases(
                forWinner: winner.assetID,
                stackAssetIDs: assets.map(\.id),
                evaluationSignalsByAssetID: evaluationSignalsByAssetID
            )
        } ?? []
        self.recommendationText = Self.recommendationText(
            rankedCandidates: rankedCandidates,
            recommendationPhrases: recommendationPhrases,
            primaryAsset: self.primaryAsset,
            rejectCount: max(assets.count - 1, 0)
        )
```

Update the static `recommendationText` (line ~3392):

```swift
    private static func recommendationText(
        rankedCandidates: [CullingStackRecommendation],
        recommendationPhrases: [String],
        primaryAsset: Asset?,
        rejectCount: Int
    ) -> String {
        guard let recommendation = rankedCandidates.first else {
            return "No ranking yet"
        }
        guard recommendation.assetID == primaryAsset?.id else {
            guard recommendationPhrases.isEmpty else {
                return "Top signal: frame \(recommendation.frameLabel) — \(recommendationPhrases.joined(separator: ", "))"
            }
            return "Top signal: frame \(recommendation.frameLabel)"
        }
        guard rejectCount > 0 else {
            return "Suggests: keep 1"
        }
        return "Suggests: keep 1 · reject \(rejectCount)"
    }
```

Add the badge members:

```swift
    /// Signal-derived read badges (BEST / EYES CLOSED / SOFT). Separate from
    /// decisionBadges so metadata badges never claim machine reads.
    func signalBadges(for asset: Asset) -> [CompareDecisionBadge] {
        signalBadgesByAssetID[asset.id] ?? []
    }

    private static let softFocusBadgeThreshold = 0.5

    private static func signalBadges(
        assetIDs: [AssetID],
        bestAssetID: AssetID?,
        evaluationSignalsByAssetID: [AssetID: [EvaluationSignal]]
    ) -> [AssetID: [CompareDecisionBadge]] {
        var badgesByAssetID: [AssetID: [CompareDecisionBadge]] = [:]
        for assetID in assetIDs {
            if assetID == bestAssetID {
                badgesByAssetID[assetID] = [CompareDecisionBadge(text: "✦ BEST", tone: .best)]
                continue
            }
            var badges: [CompareDecisionBadge] = []
            let signals = evaluationSignalsByAssetID[assetID] ?? []
            if let eyesOpen = highestConfidenceScore(kind: .eyesOpen, in: signals), eyesOpen < 1.0 {
                badges.append(CompareDecisionBadge(text: "EYES CLOSED", tone: .destructive))
            }
            if let focus = highestConfidenceScore(kind: .focus, in: signals), focus < softFocusBadgeThreshold {
                badges.append(CompareDecisionBadge(text: "SOFT", tone: .destructive))
            }
            badgesByAssetID[assetID] = badges
        }
        return badgesByAssetID
    }

    private static func highestConfidenceScore(kind: EvaluationKind, in signals: [EvaluationSignal]) -> Double? {
        signals
            .filter { $0.kind == kind }
            .sorted { $0.confidence > $1.confidence }
            .compactMap { signal -> Double? in
                guard case .score(let score) = signal.value else { return nil }
                return score
            }
            .first
    }
```

4. `compareTile` (line ~4149) — render both badge rows:

```swift
            compareDecisionBadges(presentation.decisionBadges(for: asset) + presentation.signalBadges(for: asset))
                .padding(8)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CompareSurveyPresentationTests`
Expected: PASS (all existing including the untouched `testDecisionBadgesUseRealMetadataWithoutClaimingBest`, the one updated expectation, and 3 new tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/CompareSurveyPresentationTests.swift
git commit -m "feat: badge survey compare frames with best, eyes-closed, and soft reads"
```

---

### Task 9: Focus-compare metric lanes show eyes open/shut per frame (mockup 3b)

Target lanes (design 3b): per-frame sharpness %, eyes open/shut, exposure. Adds Eye sharpness / Eyes open / Smile lanes with kind-specific value text and tones.

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` — `CompareFocusMetricPresentation` (`qualityKinds` line ~3582, `valueText` line ~3622, `tone` line ~3639)
- Modify: `Sources/TeststripApp/LiveMockupPlaceholder.swift` — `focusCompare.currentFallback` copy refresh (line ~165)
- Test: `Tests/TeststripAppTests/CompareSurveyPresentationTests.swift`

**Interfaces:**
- Consumes: `.eyesOpen` / `.eyeSharpness` / `.smile` `.score` signals; `EvaluationSignalPresentation.displayName` values from Task 2 (`"Eyes open"`, `"Eye sharpness"`, `"Smile"`).
- Produces: lane order `[.focus, .motionBlur, .exposure, .framing, .aesthetics, .faceQuality, .eyeSharpness, .eyesOpen, .smile]`; eyesOpen lane values `"Open"` / `"Shut"` / `"Some shut"`; smile lane values `"Smiling"` / `"Some smiling"` / `"No smile"`; eyeSharpness lane shows the percent.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/CompareSurveyPresentationTests.swift`:

```swift
    func testFocusMetricsIncludeEyeStateAndEyeSharpnessLanes() {
        let assetID = AssetID(rawValue: "expression-frame")
        let provenance = ProviderProvenance(
            provider: "core-image-faces",
            model: "CIDetectorFace",
            version: "1",
            settingsHash: "default"
        )

        let metrics = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .focus, value: .score(0.88), confidence: 0.81, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .eyeSharpness, value: .score(0.74), confidence: 0.6, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .eyesOpen, value: .score(1.0), confidence: 0.7, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .smile, value: .score(1.0), confidence: 0.7, provenance: provenance)
        ])

        XCTAssertEqual(metrics.map(\.title), ["Focus", "Eye sharpness", "Eyes open", "Smile"])
        XCTAssertEqual(metrics.map(\.value), ["88%", "74%", "Open", "Smiling"])
        XCTAssertEqual(metrics.map(\.tone), [.positive, .positive, .positive, .neutral])
    }

    func testShutEyesAndSoftEyeLanesUseCautionTones() {
        let assetID = AssetID(rawValue: "blink-frame")
        let provenance = ProviderProvenance(
            provider: "core-image-faces",
            model: "CIDetectorFace",
            version: "1",
            settingsHash: "default"
        )

        let metrics = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .eyeSharpness, value: .score(0.4), confidence: 0.6, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .eyesOpen, value: .score(0.0), confidence: 0.7, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .smile, value: .score(0.0), confidence: 0.7, provenance: provenance)
        ])

        XCTAssertEqual(metrics.map(\.title), ["Eye sharpness", "Eyes open", "Smile"])
        XCTAssertEqual(metrics.map(\.value), ["40%", "Shut", "No smile"])
        XCTAssertEqual(metrics.map(\.tone), [.caution, .caution, .neutral])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "CompareSurveyPresentationTests.testFocusMetricsIncludeEyeStateAndEyeSharpnessLanes|CompareSurveyPresentationTests.testShutEyesAndSoftEyeLanesUseCautionTones"`
Expected: FAIL — new kinds are missing from `qualityKinds`, so titles arrays come back short.

- [ ] **Step 3: Write the minimal implementation**

In `Sources/TeststripApp/LibraryGridView.swift`, inside `CompareFocusMetricPresentation`:

1. `qualityKinds`:

```swift
    private static let qualityKinds: [EvaluationKind] = [
        .focus,
        .motionBlur,
        .exposure,
        .framing,
        .aesthetics,
        .faceQuality,
        .eyeSharpness,
        .eyesOpen,
        .smile
    ]
```

2. `valueText(for:)` — add an expression-aware branch at the top (rest of the body is today's code, unchanged):

```swift
    private static func valueText(for signal: EvaluationSignal) -> String {
        if let expressionValue = expressionValueText(for: signal) {
            return expressionValue
        }
        switch signal.value {
        case .score(let score):
            return EvaluationSignalPresentation.percentage(score)
        case .label(let label):
            return EvaluationSignalPresentation.capitalized(label, fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .labels(let labels):
            return EvaluationSignalPresentation.capitalized(labels.joined(separator: ", "), fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .text(let text):
            return EvaluationSignalPresentation.capitalized(text, fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .count(let count):
            return String(count)
        case .vector:
            return "Sampled"
        }
    }

    private static func expressionValueText(for signal: EvaluationSignal) -> String? {
        guard case .score(let score) = signal.value else { return nil }
        switch signal.kind {
        case .eyesOpen:
            if score >= 1.0 { return "Open" }
            if score <= 0.0 { return "Shut" }
            return "Some shut"
        case .smile:
            if score >= 1.0 { return "Smiling" }
            if score > 0.0 { return "Some smiling" }
            return "No smile"
        default:
            return nil
        }
    }
```

3. `tone(for:)` — add before `default:`:

```swift
        case (.eyeSharpness, .score(let score)):
            return score >= 0.7 ? .positive : .caution
        case (.eyesOpen, .score(let score)):
            return score >= 1.0 ? .positive : .caution
        case (.smile, _):
            return .neutral
```

4. In `Sources/TeststripApp/LiveMockupPlaceholder.swift`, update `focusCompare.currentFallback` (its "eye-state ... depend on future providers" claim is now stale):

```swift
        currentFallback: "Survey Compare shows persisted focus, motion blur, exposure, framing, aesthetics, face-quality, eye-sharpness, eye-state, and smile signals for visible contenders."
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CompareSurveyPresentationTests`
Expected: PASS (existing focus-metric tests keep passing — their fixtures contain none of the new kinds)

Then run the full suite as the final gate:

Run: `swift test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift Sources/TeststripApp/LiveMockupPlaceholder.swift Tests/TeststripAppTests/CompareSurveyPresentationTests.swift
git commit -m "feat: add eye and smile lanes to focus compare metrics"
```

---

## Self-Review Notes

- **Spec coverage:** smiles → Tasks 3/5 (signal) + 6/9 (display); eyes open/closed → Tasks 3/5 + 6 (pill), 7 (ranking + "eyes open" rationale), 8 (EYES CLOSED badge), 9 (per-frame Open/Shut lanes = mockup 3b); eyes-in-focus → Task 4 (signal from eye-region crops of the cached preview via the shared heuristic) + 6/9 (display); rapid-cull verdict rationale (2a) → Task 6; survey badges BEST/EYES CLOSED/SOFT (2b) → Task 8; stack best-of-set rationale (3a) → Task 7 + recommendationText in Task 8; deterministic search/review fallout → Task 2 only (existing `signal:` field tokens, existing sidebar signal rows, one OR clause in the existing Likely Issues predicate — no new queues built).
- **Type consistency:** `DetectedFaceExpression` / `FaceExpressionAnalyzing` / `FaceExpressionEvaluationProvider` names are used identically in Tasks 3–5; `CullingStackRecommendation.rationalePhrases(forWinner:stackAssetIDs:evaluationSignalsByAssetID:)` is defined in Task 7 and consumed with the same signature in Task 8; `PreviewPixelMetrics` API defined in Task 1 is consumed unchanged in Task 4.
- **Provenance honesty:** provider `core-image-faces`, model `CIDetectorFace`, version `1`, settingsHash `default` everywhere; heuristic confidences fixed at 0.7 (detector booleans) / 0.6 (crop sharpness) and asserted in tests.
- **Known judgment calls surfaced to the reviewer:** eye-crop fraction 0.25 of face width and 8 px floor (Task 4 constants); EYES CLOSED badge fires for any blink fraction < 1.0; SOFT badge threshold 0.5 mirrors the likely-issue focus threshold; `eyeSharpness` uses the same luminance-delta scale as the existing `focus` signal, so real-photo percentages read low but comparable across frames.
