# Face Recognition (Automatic Grouping + Confirm Flow) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatic grouping of detected faces with a user confirm flow, extending (not replacing) the existing manual People workflow. Per-face embeddings (Vision feature prints computed on padded face-rectangle crops of cached previews) persist in the catalog with provenance whenever the `apple-vision` evaluation runs. App-side distance-threshold clustering over persisted embeddings produces PROVISIONAL suggestion groups that surface in a "N FACES NEED A NAME" band on the People route (design mockup 5a): clusters near a confirmed person's confirmed-face centroid become one-tap "Is this Maya?" confirmations; unmatched clusters become "Who is this?" → name-it cards; every card has a dismiss (✕). Only user confirmation writes people state — automatic matches never write anything.

**Architecture:** Three layers, built strictly in this order:

1. **Per-face persistence (core + worker).** New catalog tables `face_observations` (per detected face: normalized bounding box, capture quality, embedding vector, full provider/model/version/settings-hash provenance — mirroring `evaluation_signals`), `person_faces` (confirmed face→person links), and `dismissed_faces` (per-face suggestion dismissals). `AppleVisionAnalyzer` gains per-face output: for each `VNFaceObservation` from the existing `VNDetectFaceCaptureQualityRequest`, it runs a `VNGenerateImageFeaturePrintRequest` with `regionOfInterest` set to the padded face box (both APIs use the same normalized lower-left-origin coordinate space). A new `FaceObservationEvaluationProvider` protocol (refining `EvaluationProvider`) lets `WorkerCommandExecutor.runEvaluation` persist face rows alongside signals from ONE analysis pass — embeddings ride the existing `.runEvaluation(assetID:provider:)` command flow over cached previews; originals are never touched.
2. **Clustering + suggestions model (core + app model).** A pure `FaceSuggestionBuilder` (sibling in spirit to `AssetStackBuilder`) takes unassigned face embeddings plus confirmed-face embeddings grouped by person, unit-normalizes vectors, matches faces to confirmed-person centroids first (conservative threshold), then greedily clusters the remainder, dropping singletons. `AppModel.refreshPeopleFaceSuggestions()` loads bounded inputs from the repository (`LIMIT`-capped, provenance-filtered), runs the builder, and publishes `peopleFaceSuggestions`. It runs when the user enters the People route, after confirm/dismiss actions, and after evaluation completions while the People route is visible — never on hot import/preview paths.
3. **People UI consumption.** `PeoplePresentation` gains the needs-a-name band (title, status, suggestion cards) above the existing review-queue cards; `PeopleView` renders cards with real face-crop avatars (cropped from cached previews via the persisted bounding box), a one-tap confirm button (match) or Name… sheet (new cluster, reusing the existing naming-sheet pattern and the existing `upsertPerson`/assign repository path), a dismiss ✕, and a show-photos handoff that batch-selects the group's photos in the grid. The manual Name selection / Dismiss face review / merge workflow is untouched.

**Tech Stack:** Swift 6 / SwiftPM, macOS 14+, SwiftUI + AppKit, Apple Vision (`VNDetectFaceCaptureQualityRequest`, `VNGenerateImageFeaturePrintRequest` with `regionOfInterest`), SQLite via the existing `CatalogDatabase`, XCTest. No external ML dependencies.

**What exists today (verified against `dd18246`):**
- Face signals persist per-photo only: `faceCount` (`.count`) and `faceQuality` (averaged `.score`) rows in `evaluation_signals` (`AppleVisionEvaluationProvider.swift:73-105`). No bounding boxes, no per-face rows, no face embeddings — the whole-image feature print persists as a `visualSimilarity` vector signal.
- Manual People workflow: `upsertPerson` / `assignAssets` / `mergePerson` / `dismissFaceAssets` / `people()` in `CatalogRepository.swift:435-556`; `AppModel.confirmSelectedAssetsAsPerson` (AppModel.swift:2127), `mergePerson` (2151), `dismissSelectedFaceReviewAssets` (2159); `PeopleView` review strip + ALL PEOPLE grid.
- Evaluation flow: `AppModel.requestEvaluation` → `WorkerSupervisor.enqueue(.runEvaluation)` → `WorkerCommandExecutor.runEvaluation` (WorkerCommandExecutor.swift:288-298) resolves a cached preview and records signals; completion invalidates via `invalidateEvaluationSignalsIfNeeded` → `refreshCatalogEvaluationKindSummaries()` (AppModel.swift:5725-5748, 7562-7572).
- Because prior scans recorded only per-photo aggregates, existing catalogs have zero face rows until the user re-runs "Scan current scope" — the band copy must say so honestly (Task 8).

**Decision — face-crop feature prints, not a face-identity model:** Apple ships no public face-identity embedding API. `VNGenerateImageFeaturePrintRequest` over a padded face crop is a generic image embedding, weaker than a true face embedding, so thresholds are conservative and every group is confirm-gated. This is exactly the mitigation the product rule requires anyway (PROVISIONAL until confirmed). Bundling an external face model is out of scope.

**Decision — per-face table, replace-per-run semantics:** Face identity is `(asset_id, face_index)` under a given provenance. Re-running a scan can change the face count, so `replaceFaceObservations` deletes the asset's rows for that provenance and re-inserts, never leaving stale `face_index` rows behind (plain upsert would).

**Decision — clustering thresholds are named, injectable constants:** `FaceSuggestionBuilder` defaults (`maximumMatchDistance = 0.35`, `maximumClusterDistance = 0.3`, Euclidean distance over unit-normalized vectors, so 0…2 scale) follow the `AssetStackBuilder` pattern (injectable via init, defaults as `static let`). They are engineering estimates that need empirical tuning on a real catalog — flagged as an open question; conservative-by-default plus mandatory confirm keeps mistakes cheap.

**Decision — confirmation writes through the existing people primitives:** Confirming a cluster calls the existing `upsertPerson` path and the same `person_assets` + `dismissed_face_assets` bookkeeping as `assignAssets`, plus new `person_faces` rows so confirmed-face centroids exist for future matching. `assignFaces` inlines the asset-level SQL inside one transaction because `CatalogDatabase.transaction` cannot nest (`BEGIN IMMEDIATE` inside `BEGIN IMMEDIATE` fails).

## Global Constraints

- **Hard product rule:** machine labels stay PROVISIONAL until user acceptance. Nothing in this plan auto-writes catalog people state, metadata, or XMP. The ONLY writes to `people`/`person_assets`/`person_faces` happen inside explicit user actions (`confirmPeopleFaceSuggestion`, the naming sheet, and the pre-existing manual flows). Dismissal writes only to `dismissed_faces`.
- TDD is mandatory: every behavior lands as failing test → run and observe the expected failure → minimal implementation → green → commit.
- Providers run over CACHED PREVIEWS only; nothing here reads originals.
- Clustering runs app-side over persisted embeddings with a bounded input (`AppModel.maximumFaceSuggestionInputCount = 2000`, most recent first) and only on People-route entry, confirm/dismiss, or evaluation completion while People is visible.
- All suggestion queries filter by exact provenance (`AppleVisionEvaluationProvider.faceProvenance`) so embeddings from different models/settings never mix.
- No split-person, no face-box-level naming UI beyond the confirm cards, no re-clustering settings UI, no avatar changes to the ALL PEOPLE grid, no XMP face regions. YAGNI.
- Run tests from `/Users/jesse/git/projects/teststrip`. Full gate at the end: `swift test` and `./script/build_and_run.sh --build`.
- Work on a WIP branch (e.g. `git checkout -b face-recognition`) if not already on one. Commit after every green step.
- Line numbers are anchors as of commit `dd18246`; re-locate by the quoted code if they have shifted.

---

## Task 1: Persist per-face observations in the catalog

**Files:**
- Create: `Sources/TeststripCore/Catalog/CatalogFaceObservation.swift`
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift` (version 13 → 14, three new tables)
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (append after `dismissedFaceAssetIDs()`, line 556)
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Produces: `FaceBoundingBox(x:y:width:height:)` (Codable, Equatable, Sendable; normalized, lower-left origin — Vision's coordinate space)
- Produces: `FaceID(assetID:faceIndex:)` (Hashable, Sendable)
- Produces: `CatalogFaceObservation(assetID:faceIndex:boundingBox:captureQuality:embedding:provenance:)` (Equatable, Sendable) with `var faceID: FaceID`
- Produces: `CatalogRepository.replaceFaceObservations(assetID: AssetID, provenance: ProviderProvenance, with observations: [CatalogFaceObservation]) throws`
- Produces: `CatalogRepository.faceObservations(assetID: AssetID) throws -> [CatalogFaceObservation]`
- Consumes: `CatalogDatabase.execute/transaction/rows`, `ProviderProvenance`, the repository's private `encode`/`decode` helpers (CatalogRepository.swift:1875-1881)

**Steps:**

- [ ] Add the failing test to `Tests/TeststripCoreTests/CatalogDatabaseTests.swift` (below `testAssignedPersonAssetRemovesItFromFaceReviewQueries`):

```swift
    func testFaceObservationsReplacePerAssetAndProvenance() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-face-observations")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(id: AssetID(rawValue: "group-frame"), path: "/Volumes/NAS/Job/group-frame.jpg", rating: 0)
        try repository.upsert(asset)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "face-crop-pad-25")
        let firstRun = [
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: 0,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                captureQuality: 0.8,
                embedding: [0.1, 0.2, 0.3],
                provenance: provenance
            ),
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: 1,
                boundingBox: FaceBoundingBox(x: 0.6, y: 0.5, width: 0.2, height: 0.25),
                captureQuality: nil,
                embedding: [0.9, 0.8, 0.7],
                provenance: provenance
            )
        ]

        try repository.replaceFaceObservations(assetID: asset.id, provenance: provenance, with: firstRun)

        XCTAssertEqual(try repository.faceObservations(assetID: asset.id), firstRun)

        let secondRun = [firstRun[0]]
        try repository.replaceFaceObservations(assetID: asset.id, provenance: provenance, with: secondRun)

        XCTAssertEqual(try repository.faceObservations(assetID: asset.id), secondRun)
        XCTAssertEqual(try repository.faceObservations(assetID: AssetID(rawValue: "other")), [])
    }
```

- [ ] Run `swift test --filter CatalogDatabaseTests.testFaceObservationsReplacePerAssetAndProvenance` — expect compile failure: `cannot find 'CatalogFaceObservation' in scope`.
- [ ] Create `Sources/TeststripCore/Catalog/CatalogFaceObservation.swift`:

```swift
import Foundation

public struct FaceBoundingBox: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct FaceID: Hashable, Sendable {
    public var assetID: AssetID
    public var faceIndex: Int

    public init(assetID: AssetID, faceIndex: Int) {
        self.assetID = assetID
        self.faceIndex = faceIndex
    }
}

public struct CatalogFaceObservation: Equatable, Sendable {
    public var assetID: AssetID
    public var faceIndex: Int
    public var boundingBox: FaceBoundingBox
    public var captureQuality: Double?
    public var embedding: [Double]
    public var provenance: ProviderProvenance

    public init(
        assetID: AssetID,
        faceIndex: Int,
        boundingBox: FaceBoundingBox,
        captureQuality: Double?,
        embedding: [Double],
        provenance: ProviderProvenance
    ) {
        self.assetID = assetID
        self.faceIndex = faceIndex
        self.boundingBox = boundingBox
        self.captureQuality = captureQuality
        self.embedding = embedding
        self.provenance = provenance
    }

    public var faceID: FaceID {
        FaceID(assetID: assetID, faceIndex: faceIndex)
    }
}
```

- [ ] In `CatalogMigrations.swift`, bump `static let version = 13` to `14` and append to `statements` (after the `dismissed_face_assets` statement):

```swift
        """
        CREATE TABLE IF NOT EXISTS face_observations (
            asset_id TEXT NOT NULL,
            face_index INTEGER NOT NULL,
            face_json TEXT NOT NULL,
            provenance_json TEXT NOT NULL,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            version TEXT NOT NULL,
            settings_hash TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY (asset_id, face_index, provider, model, version, settings_hash)
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_face_observations_asset ON face_observations(asset_id)",
        """
        CREATE TABLE IF NOT EXISTS person_faces (
            person_id TEXT NOT NULL,
            asset_id TEXT NOT NULL,
            face_index INTEGER NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY (asset_id, face_index)
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_person_faces_person ON person_faces(person_id)",
        """
        CREATE TABLE IF NOT EXISTS dismissed_faces (
            asset_id TEXT NOT NULL,
            face_index INTEGER NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY (asset_id, face_index)
        )
        """
```

(`face_json` holds bounding box + capture quality + embedding as one JSON payload, the same pattern as `value_json` on `evaluation_signals`; `capture_quality` cannot be its own nullable column because `CatalogDatabase.bind` only binds text.)

- [ ] Append to `CatalogRepository.swift` after `dismissedFaceAssetIDs()` (line 556):

```swift
    public func replaceFaceObservations(
        assetID: AssetID,
        provenance: ProviderProvenance,
        with observations: [CatalogFaceObservation]
    ) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.transaction {
            try database.execute(
                """
                DELETE FROM face_observations
                WHERE asset_id = ? AND provider = ? AND model = ? AND version = ? AND settings_hash = ?
                """,
                bindings: [
                    assetID.rawValue,
                    provenance.provider,
                    provenance.model,
                    provenance.version,
                    provenance.settingsHash
                ]
            )
            for observation in observations {
                try database.execute(
                    """
                    INSERT INTO face_observations (
                        asset_id, face_index, face_json, provenance_json,
                        provider, model, version, settings_hash, created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    bindings: [
                        observation.assetID.rawValue,
                        "\(observation.faceIndex)",
                        try encode(FaceObservationPayload(
                            boundingBox: observation.boundingBox,
                            captureQuality: observation.captureQuality,
                            embedding: observation.embedding
                        )),
                        try encode(observation.provenance),
                        observation.provenance.provider,
                        observation.provenance.model,
                        observation.provenance.version,
                        observation.provenance.settingsHash,
                        now,
                        now
                    ]
                )
            }
        }
    }

    public func faceObservations(assetID: AssetID) throws -> [CatalogFaceObservation] {
        let rows = try database.rows(
            """
            SELECT asset_id, face_index, face_json, provenance_json
            FROM face_observations
            WHERE asset_id = ?
            ORDER BY provider ASC, model ASC, version ASC, settings_hash ASC, face_index ASC
            """,
            bindings: [assetID.rawValue]
        )
        return try rows.map(decodeFaceObservation)
    }

    private func decodeFaceObservation(_ row: [String: String]) throws -> CatalogFaceObservation {
        guard let assetID = row["asset_id"],
              let faceIndexValue = row["face_index"],
              let faceIndex = Int(faceIndexValue),
              let faceJSON = row["face_json"],
              let provenanceJSON = row["provenance_json"] else {
            throw CatalogError.sqlite("face observation row is missing required columns")
        }
        let payload = try decode(FaceObservationPayload.self, from: faceJSON)
        return CatalogFaceObservation(
            assetID: AssetID(rawValue: assetID),
            faceIndex: faceIndex,
            boundingBox: payload.boundingBox,
            captureQuality: payload.captureQuality,
            embedding: payload.embedding,
            provenance: try decode(ProviderProvenance.self, from: provenanceJSON)
        )
    }
```

and add the private payload type near the bottom of the file (above the private `encode` helper):

```swift
private struct FaceObservationPayload: Codable {
    var boundingBox: FaceBoundingBox
    var captureQuality: Double?
    var embedding: [Double]
}
```

- [ ] Run `swift test --filter CatalogDatabaseTests` — expect all green (existing migration tests confirm the new statements are idempotent `IF NOT EXISTS`).
- [ ] Commit: `git add -u && git add Sources/TeststripCore/Catalog/CatalogFaceObservation.swift && git commit -m "Persist per-face observations in the catalog"`

---

## Task 2: Compute per-face crop feature prints in the Apple Vision analyzer

**Files:**
- Modify: `Sources/TeststripCore/Evaluation/AppleVisionEvaluationProvider.swift`
- Test: `Tests/TeststripCoreTests/EvaluationProviderTests.swift`

**Interfaces:**
- Produces: `AppleVisionFaceObservation(boundingBox:captureQuality:featurePrintVector:)` (Equatable, Sendable)
- Modifies: `AppleVisionAnalysis` gains `public var faces: [AppleVisionFaceObservation]` with init default `faces: [AppleVisionFaceObservation] = []` (existing memberwise call sites, including `FakeAppleVisionAnalyzer` tests, keep compiling)
- Produces: `AppleVisionAnalyzer.faceCropPadding: Double` (`0.25`) and `static func paddedRegionOfInterest(_ box: FaceBoundingBox, padding: Double = faceCropPadding) -> CGRect`
- Consumes: `VNDetectFaceCaptureQualityRequest` results (`VNFaceObservation.boundingBox` is normalized with lower-left origin — the same space `VNImageBasedRequest.regionOfInterest` expects), `VNGenerateImageFeaturePrintRequest`, the existing `imageFeaturePrintVector(from:)` helper (AppleVisionEvaluationProvider.swift:192-200)

**Steps:**

- [ ] Add failing tests to `Tests/TeststripCoreTests/EvaluationProviderTests.swift` (below `testAppleVisionAnalyzerProducesImageFeaturePrintVector`):

```swift
    func testPaddedRegionOfInterestExpandsAndClampsFaceBox() {
        let padded = AppleVisionAnalyzer.paddedRegionOfInterest(
            FaceBoundingBox(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            padding: 0.25
        )
        XCTAssertEqual(padded.origin.x, 0.35, accuracy: 0.0001)
        XCTAssertEqual(padded.origin.y, 0.35, accuracy: 0.0001)
        XCTAssertEqual(padded.width, 0.3, accuracy: 0.0001)
        XCTAssertEqual(padded.height, 0.3, accuracy: 0.0001)

        let clamped = AppleVisionAnalyzer.paddedRegionOfInterest(
            FaceBoundingBox(x: 0.0, y: 0.9, width: 0.2, height: 0.2),
            padding: 0.25
        )
        XCTAssertGreaterThanOrEqual(clamped.minX, 0)
        XCTAssertGreaterThanOrEqual(clamped.minY, 0)
        XCTAssertLessThanOrEqual(clamped.maxX, 1)
        XCTAssertLessThanOrEqual(clamped.maxY, 1)

        XCTAssertEqual(
            AppleVisionAnalyzer.paddedRegionOfInterest(FaceBoundingBox(x: 0.5, y: 0.5, width: 0, height: 0)),
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )
    }

    func testAppleVisionAnalyzerFaceObservationsMatchFaceCount() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "apple-vision-face-observations")
        let previewURL = directory.appendingPathComponent("preview.jpg")
        try TestDirectories.writeTestJPEG(to: previewURL, width: 128, height: 128)

        let analysis = try AppleVisionAnalyzer().analyze(previewURL: previewURL)

        XCTAssertEqual(analysis.faces.count, analysis.faceCount)
    }
```

(Synthetic JPEGs contain no faces, so the second test asserts the per-face array stays consistent with `faceCount` — real face detection cannot be asserted deterministically from generated fixtures. This is the same honesty bar as `testAppleVisionAnalyzerProducesImageFeaturePrintVector`.)

- [ ] Run `swift test --filter EvaluationProviderTests.testPaddedRegionOfInterestExpandsAndClampsFaceBox` — expect compile failure: `type 'AppleVisionAnalyzer' has no member 'paddedRegionOfInterest'`.
- [ ] Implement in `AppleVisionEvaluationProvider.swift`:
  - Add the face observation value type above `AppleVisionAnalysis`:

```swift
public struct AppleVisionFaceObservation: Equatable, Sendable {
    public var boundingBox: FaceBoundingBox
    public var captureQuality: Double?
    public var featurePrintVector: [Double]

    public init(boundingBox: FaceBoundingBox, captureQuality: Double?, featurePrintVector: [Double]) {
        self.boundingBox = boundingBox
        self.captureQuality = captureQuality
        self.featurePrintVector = featurePrintVector
    }
}
```

  - Add `public var faces: [AppleVisionFaceObservation]` to `AppleVisionAnalysis`, with init parameter `faces: [AppleVisionFaceObservation] = []` appended after `imageFeaturePrintVector`.
  - In `AppleVisionAnalyzer`, add:

```swift
    public static let faceCropPadding = 0.25

    public static func paddedRegionOfInterest(_ box: FaceBoundingBox, padding: Double = faceCropPadding) -> CGRect {
        guard box.width > 0, box.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let inset = padding * max(box.width, box.height)
        let minX = max(0.0, box.x - inset)
        let minY = max(0.0, box.y - inset)
        let maxX = min(1.0, box.x + box.width + inset)
        let maxY = min(1.0, box.y + box.height + inset)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
```

  - In `analyze(previewURL:)`, after the existing `handler.perform([...])` call, compute per-face prints from the same handler (Vision allows repeated `perform` calls on one `VNImageRequestHandler`):

```swift
        let faceResults = faceQualityRequest.results ?? []
        let facePrintRequests = faceResults.map { observation -> VNGenerateImageFeaturePrintRequest in
            let request = VNGenerateImageFeaturePrintRequest()
            request.regionOfInterest = Self.paddedRegionOfInterest(FaceBoundingBox(
                x: Double(observation.boundingBox.origin.x),
                y: Double(observation.boundingBox.origin.y),
                width: Double(observation.boundingBox.width),
                height: Double(observation.boundingBox.height)
            ))
            return request
        }
        if !facePrintRequests.isEmpty {
            try handler.perform(facePrintRequests)
        }
        let faces = zip(faceResults, facePrintRequests).map { observation, request in
            AppleVisionFaceObservation(
                boundingBox: FaceBoundingBox(
                    x: Double(observation.boundingBox.origin.x),
                    y: Double(observation.boundingBox.origin.y),
                    width: Double(observation.boundingBox.width),
                    height: Double(observation.boundingBox.height)
                ),
                captureQuality: observation.faceCaptureQuality.map(Double.init),
                featurePrintVector: Self.imageFeaturePrintVector(from: request.results?.first)
            )
        }
```

    and pass `faces: faces` into the returned `AppleVisionAnalysis`. Keep `faceCount: faceResults.count` so the two stay in lockstep.
- [ ] Run `swift test --filter EvaluationProviderTests` — expect all green.
- [ ] Commit: `git add -u && git commit -m "Compute per-face crop feature prints in Apple Vision analyzer"`

---

## Task 3: Map Apple Vision faces to catalog face observations

**Files:**
- Modify: `Sources/TeststripCore/Evaluation/EvaluationProvider.swift` (add outcome type + protocol)
- Modify: `Sources/TeststripCore/Evaluation/AppleVisionEvaluationProvider.swift` (conform)
- Test: `Tests/TeststripCoreTests/EvaluationProviderTests.swift`

**Interfaces:**
- Produces: `FaceEvaluationOutcome(signals:faceObservations:)` (Equatable, Sendable)
- Produces: `protocol FaceObservationEvaluationProvider: EvaluationProvider { var faceProvenance: ProviderProvenance { get }; func evaluateWithFaces(assetID: AssetID, previewURL: URL) throws -> FaceEvaluationOutcome }`
- Produces: `AppleVisionEvaluationProvider.faceProvenance` = `ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "face-crop-pad-25")` (settings hash names the crop padding; changing the padding requires a new settings hash so old rows are distinguishable)
- Consumes: `AppleVisionAnalysis.faces` from Task 2; existing signal mapping (AppleVisionEvaluationProvider.swift:49-71)

**Steps:**

- [ ] Add the failing test to `EvaluationProviderTests.swift` (below `testAppleVisionProviderPreservesMultipleClassificationLabelsInOneObjectSignal`):

```swift
    func testAppleVisionProviderMapsFacesToCatalogObservations() throws {
        let faces = [
            AppleVisionFaceObservation(
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                captureQuality: 0.8,
                featurePrintVector: [0.1, 0.2]
            ),
            AppleVisionFaceObservation(
                boundingBox: FaceBoundingBox(x: 0.6, y: 0.5, width: 0.2, height: 0.25),
                captureQuality: nil,
                featurePrintVector: [0.9, 0.8]
            )
        ]
        let provider = AppleVisionEvaluationProvider(analyzer: FakeAppleVisionAnalyzer(analysis: AppleVisionAnalysis(
            faceCount: 2,
            faceQualityScores: [0.8],
            recognizedText: [],
            classificationLabels: [],
            imageFeaturePrintVector: [],
            faces: faces
        )))
        let assetID = AssetID(rawValue: "asset-faces")

        let outcome = try provider.evaluateWithFaces(assetID: assetID, previewURL: URL(fileURLWithPath: "/tmp/preview.jpg"))

        XCTAssertEqual(outcome.signals, try provider.evaluate(assetID: assetID, previewURL: URL(fileURLWithPath: "/tmp/preview.jpg")))
        XCTAssertEqual(outcome.faceObservations, [
            CatalogFaceObservation(
                assetID: assetID,
                faceIndex: 0,
                boundingBox: faces[0].boundingBox,
                captureQuality: 0.8,
                embedding: [0.1, 0.2],
                provenance: AppleVisionEvaluationProvider.faceProvenance
            ),
            CatalogFaceObservation(
                assetID: assetID,
                faceIndex: 1,
                boundingBox: faces[1].boundingBox,
                captureQuality: nil,
                embedding: [0.9, 0.8],
                provenance: AppleVisionEvaluationProvider.faceProvenance
            )
        ])
    }
```

- [ ] Run `swift test --filter EvaluationProviderTests.testAppleVisionProviderMapsFacesToCatalogObservations` — expect compile failure: `value of type 'AppleVisionEvaluationProvider' has no member 'evaluateWithFaces'`.
- [ ] Append to `EvaluationProvider.swift`:

```swift
public struct FaceEvaluationOutcome: Equatable, Sendable {
    public var signals: [EvaluationSignal]
    public var faceObservations: [CatalogFaceObservation]

    public init(signals: [EvaluationSignal], faceObservations: [CatalogFaceObservation]) {
        self.signals = signals
        self.faceObservations = faceObservations
    }
}

public protocol FaceObservationEvaluationProvider: EvaluationProvider {
    var faceProvenance: ProviderProvenance { get }
    func evaluateWithFaces(assetID: AssetID, previewURL: URL) throws -> FaceEvaluationOutcome
}
```

- [ ] In `AppleVisionEvaluationProvider`, refactor without changing behavior: extract the body of `evaluate` (everything after `analyzer.analyze`) into `private static func signals(assetID: AssetID, analysis: AppleVisionAnalysis) -> [EvaluationSignal]`, then:

```swift
extension AppleVisionEvaluationProvider: FaceObservationEvaluationProvider {
    public static let faceProvenance = ProviderProvenance(
        provider: "apple-vision",
        model: "Vision",
        version: "1",
        settingsHash: "face-crop-pad-25"
    )

    public var faceProvenance: ProviderProvenance {
        Self.faceProvenance
    }

    public func evaluateWithFaces(assetID: AssetID, previewURL: URL) throws -> FaceEvaluationOutcome {
        let analysis = try analyzer.analyze(previewURL: previewURL)
        return FaceEvaluationOutcome(
            signals: Self.signals(assetID: assetID, analysis: analysis),
            faceObservations: analysis.faces.enumerated().map { index, face in
                CatalogFaceObservation(
                    assetID: assetID,
                    faceIndex: index,
                    boundingBox: face.boundingBox,
                    captureQuality: face.captureQuality,
                    embedding: face.featurePrintVector,
                    provenance: Self.faceProvenance
                )
            }
        )
    }
}
```

    and make `evaluate` delegate: `try evaluateWithFaces(assetID: assetID, previewURL: previewURL).signals`.
- [ ] Run `swift test --filter EvaluationProviderTests` — expect all green (existing signal-mapping tests prove the refactor preserved behavior).
- [ ] Commit: `git add -u && git commit -m "Map Apple Vision faces to catalog face observations"`

---

## Task 4: Persist face observations through worker evaluation

**Files:**
- Modify: `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift` (`runEvaluation`, line 288)
- Test: `Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift`

**Interfaces:**
- Modifies: `WorkerCommandExecutor.runEvaluation(assetID:providerName:)` — when the provider is a `FaceObservationEvaluationProvider`, record signals AND replace face observations from one `evaluateWithFaces` call; other providers unchanged
- Consumes: `CatalogRepository.replaceFaceObservations` (Task 1), `FaceObservationEvaluationProvider` (Task 3)

**Steps:**

- [ ] Add the failing test to `WorkerCommandExecutorTests.swift` (below the local-http evaluation test, ~line 873), plus the stub provider at file scope next to `PreviewPathEvaluationProvider` (~line 961):

```swift
    func testRunEvaluationPersistsAndReplacesFaceObservationsFromFaceProviders() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-face-observations")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
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
        let provenance = ProviderProvenance(provider: "stub-faces", model: "stub", version: "1", settingsHash: "default")
        let twoFaces = [
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: 0,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                captureQuality: 0.9,
                embedding: [1, 0],
                provenance: provenance
            ),
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: 1,
                boundingBox: FaceBoundingBox(x: 0.5, y: 0.5, width: 0.2, height: 0.2),
                captureQuality: nil,
                embedding: [0, 1],
                provenance: provenance
            )
        ]

        let firstExecutor = WorkerCommandExecutor(
            repository: repository,
            previewCache: previewCache,
            evaluationProviders: [StubFaceEvaluationProvider(
                name: "stub-faces",
                faceProvenance: provenance,
                outcome: FaceEvaluationOutcome(signals: [], faceObservations: twoFaces)
            )]
        )
        _ = try firstExecutor.execute(.runEvaluation(assetID: asset.id, provider: "stub-faces"))

        XCTAssertEqual(try repository.faceObservations(assetID: asset.id), twoFaces)

        let secondExecutor = WorkerCommandExecutor(
            repository: repository,
            previewCache: previewCache,
            evaluationProviders: [StubFaceEvaluationProvider(
                name: "stub-faces",
                faceProvenance: provenance,
                outcome: FaceEvaluationOutcome(signals: [], faceObservations: [twoFaces[0]])
            )]
        )
        _ = try secondExecutor.execute(.runEvaluation(assetID: asset.id, provider: "stub-faces"))

        XCTAssertEqual(try repository.faceObservations(assetID: asset.id), [twoFaces[0]])
    }
```

```swift
private struct StubFaceEvaluationProvider: FaceObservationEvaluationProvider {
    var name: String
    var faceProvenance: ProviderProvenance
    var outcome: FaceEvaluationOutcome

    func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        outcome.signals
    }

    func evaluateWithFaces(assetID: AssetID, previewURL: URL) throws -> FaceEvaluationOutcome {
        outcome
    }
}
```

- [ ] Run `swift test --filter WorkerCommandExecutorTests.testRunEvaluationPersistsAndReplacesFaceObservationsFromFaceProviders` — expect assertion failure: `faceObservations` is `[]` (executor never persists faces yet).
- [ ] Replace the body of `runEvaluation` (WorkerCommandExecutor.swift:288-298) — keep the asset/provider/preview guards, then:

```swift
        if let faceProvider = provider as? any FaceObservationEvaluationProvider {
            let outcome = try faceProvider.evaluateWithFaces(assetID: assetID, previewURL: previewURL)
            try repository.recordEvaluationSignals(outcome.signals)
            try repository.replaceFaceObservations(
                assetID: assetID,
                provenance: faceProvider.faceProvenance,
                with: outcome.faceObservations
            )
        } else {
            try repository.recordEvaluationSignals(try provider.evaluate(assetID: assetID, previewURL: previewURL))
        }
        return .completed("evaluated \(Self.displayName(for: asset)) with \(providerName)")
```

- [ ] Run `swift test --filter WorkerCommandExecutorTests` — expect all green.
- [ ] Commit: `git add -u && git commit -m "Persist face observations through worker evaluation"`

---

## Task 5: Face suggestion queries and confirmed-face writes

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (append after Task 1's face methods; also touch `mergePerson` line 481 and `dismissFaceAssets` line 503)
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Produces: `CatalogRepository.unassignedFaceObservations(provenance: ProviderProvenance, limit: Int) throws -> [CatalogFaceObservation]` — excludes faces in `person_faces`, faces in `dismissed_faces`, and faces on assets in `dismissed_face_assets` or `person_assets` (matching the manual flow's asset-level semantics in `evaluationKindSummaries`, CatalogRepository.swift:752-785); most recent first
- Produces: `CatalogRepository.confirmedFaceEmbeddingsByPerson(provenance: ProviderProvenance) throws -> [String: [[Double]]]`
- Produces: `CatalogRepository.faceObservationAssetCount(provenance: ProviderProvenance) throws -> Int` (drives honest "re-scan needed" copy in Task 8)
- Produces: `CatalogRepository.assignFaces(_ faceIDs: [FaceID], toPersonID personID: String) throws` — one transaction: upsert `person_faces` rows, clear their `dismissed_faces` rows, insert `person_assets` rows for the distinct assets, clear `dismissed_face_assets` (inlines the `assignAssets` SQL because `CatalogDatabase.transaction` cannot nest)
- Produces: `CatalogRepository.dismissFaces(_ faceIDs: [FaceID]) throws` — inserts `dismissed_faces`, removes matching `person_faces`
- Modifies: `mergePerson` moves `person_faces` rows to the target before deleting the source person; `dismissFaceAssets` also deletes the asset's `person_faces` rows

**Steps:**

- [ ] Add failing tests to `CatalogDatabaseTests.swift`:

```swift
    func testUnassignedFaceObservationsExcludeConfirmedDismissedAndAssignedAssets() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-unassigned-faces")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "face-crop-pad-25")
        let otherProvenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "2", settingsHash: "face-crop-pad-25")
        let open = Asset.testAsset(id: AssetID(rawValue: "open"), path: "/Volumes/NAS/Job/open.jpg", rating: 0)
        let confirmed = Asset.testAsset(id: AssetID(rawValue: "confirmed"), path: "/Volumes/NAS/Job/confirmed.jpg", rating: 0)
        let dismissedFace = Asset.testAsset(id: AssetID(rawValue: "dismissed-face"), path: "/Volumes/NAS/Job/dismissed-face.jpg", rating: 0)
        let dismissedAsset = Asset.testAsset(id: AssetID(rawValue: "dismissed-asset"), path: "/Volumes/NAS/Job/dismissed-asset.jpg", rating: 0)
        try repository.upsert([open, confirmed, dismissedFace, dismissedAsset])
        func face(_ asset: Asset, _ index: Int, _ prov: ProviderProvenance = provenance) -> CatalogFaceObservation {
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: index,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                captureQuality: 0.5,
                embedding: [1, 0, 0],
                provenance: prov
            )
        }
        try repository.replaceFaceObservations(assetID: open.id, provenance: provenance, with: [face(open, 0)])
        try repository.replaceFaceObservations(assetID: open.id, provenance: otherProvenance, with: [face(open, 0, otherProvenance)])
        try repository.replaceFaceObservations(assetID: confirmed.id, provenance: provenance, with: [face(confirmed, 0)])
        try repository.replaceFaceObservations(assetID: dismissedFace.id, provenance: provenance, with: [face(dismissedFace, 0)])
        try repository.replaceFaceObservations(assetID: dismissedAsset.id, provenance: provenance, with: [face(dismissedAsset, 0)])
        try repository.upsertPerson(id: "person-maya", name: "Maya")
        try repository.assignFaces([FaceID(assetID: confirmed.id, faceIndex: 0)], toPersonID: "person-maya")
        try repository.dismissFaces([FaceID(assetID: dismissedFace.id, faceIndex: 0)])
        try repository.dismissFaceAssets([dismissedAsset.id])

        let unassigned = try repository.unassignedFaceObservations(provenance: provenance, limit: 10)

        XCTAssertEqual(unassigned.map(\.faceID), [FaceID(assetID: open.id, faceIndex: 0)])
        XCTAssertEqual(try repository.faceObservationAssetCount(provenance: provenance), 4)
    }

    func testAssignFacesRecordsPersonFacesAndPersonAssets() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-assign-faces")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "face-crop-pad-25")
        let frame = Asset.testAsset(id: AssetID(rawValue: "frame"), path: "/Volumes/NAS/Job/frame.jpg", rating: 0)
        try repository.upsert(frame)
        try repository.replaceFaceObservations(assetID: frame.id, provenance: provenance, with: [
            CatalogFaceObservation(
                assetID: frame.id,
                faceIndex: 0,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                captureQuality: 0.5,
                embedding: [0.6, 0.8, 0],
                provenance: provenance
            )
        ])
        try repository.upsertPerson(id: "person-maya", name: "Maya")

        try repository.assignFaces([FaceID(assetID: frame.id, faceIndex: 0)], toPersonID: "person-maya")

        XCTAssertEqual(try repository.assetIDs(personID: "person-maya"), [frame.id])
        XCTAssertEqual(
            try repository.confirmedFaceEmbeddingsByPerson(provenance: provenance),
            ["person-maya": [[0.6, 0.8, 0]]]
        )
        XCTAssertEqual(try repository.unassignedFaceObservations(provenance: provenance, limit: 10), [])
    }

    func testMergePersonMovesConfirmedFacesAndDismissFaceAssetsClearsThem() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-face-merge-dismiss")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "face-crop-pad-25")
        let frame = Asset.testAsset(id: AssetID(rawValue: "frame"), path: "/Volumes/NAS/Job/frame.jpg", rating: 0)
        try repository.upsert(frame)
        try repository.replaceFaceObservations(assetID: frame.id, provenance: provenance, with: [
            CatalogFaceObservation(
                assetID: frame.id,
                faceIndex: 0,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                captureQuality: 0.5,
                embedding: [1, 0, 0],
                provenance: provenance
            )
        ])
        try repository.upsertPerson(id: "source", name: "Maya duplicate")
        try repository.upsertPerson(id: "target", name: "Maya")
        try repository.assignFaces([FaceID(assetID: frame.id, faceIndex: 0)], toPersonID: "source")

        try repository.mergePerson(sourceID: "source", into: "target")

        XCTAssertEqual(
            try repository.confirmedFaceEmbeddingsByPerson(provenance: provenance),
            ["target": [[1, 0, 0]]]
        )

        try repository.dismissFaceAssets([frame.id])

        XCTAssertEqual(try repository.confirmedFaceEmbeddingsByPerson(provenance: provenance), [:])
    }
```

- [ ] Run `swift test --filter CatalogDatabaseTests.testAssignFacesRecordsPersonFacesAndPersonAssets` — expect compile failure: `value of type 'CatalogRepository' has no member 'assignFaces'`.
- [ ] Implement in `CatalogRepository.swift` (append after `faceObservations(assetID:)`):

```swift
    public func unassignedFaceObservations(provenance: ProviderProvenance, limit: Int) throws -> [CatalogFaceObservation] {
        let rows = try database.rows(
            """
            SELECT asset_id, face_index, face_json, provenance_json
            FROM face_observations
            WHERE provider = ? AND model = ? AND version = ? AND settings_hash = ?
              AND NOT EXISTS (
                  SELECT 1 FROM person_faces
                  WHERE person_faces.asset_id = face_observations.asset_id
                    AND person_faces.face_index = face_observations.face_index
              )
              AND NOT EXISTS (
                  SELECT 1 FROM dismissed_faces
                  WHERE dismissed_faces.asset_id = face_observations.asset_id
                    AND dismissed_faces.face_index = face_observations.face_index
              )
              AND NOT EXISTS (
                  SELECT 1 FROM dismissed_face_assets
                  WHERE dismissed_face_assets.asset_id = face_observations.asset_id
              )
              AND NOT EXISTS (
                  SELECT 1 FROM person_assets
                  WHERE person_assets.asset_id = face_observations.asset_id
              )
            ORDER BY created_at DESC, asset_id ASC, face_index ASC
            LIMIT ?
            """,
            bindings: [provenance.provider, provenance.model, provenance.version, provenance.settingsHash, "\(limit)"]
        )
        return try rows.map(decodeFaceObservation)
    }

    public func confirmedFaceEmbeddingsByPerson(provenance: ProviderProvenance) throws -> [String: [[Double]]] {
        let rows = try database.rows(
            """
            SELECT person_faces.person_id AS person_id, face_observations.face_json AS face_json
            FROM person_faces
            JOIN face_observations
              ON face_observations.asset_id = person_faces.asset_id
             AND face_observations.face_index = person_faces.face_index
            WHERE face_observations.provider = ? AND face_observations.model = ?
              AND face_observations.version = ? AND face_observations.settings_hash = ?
            ORDER BY person_faces.person_id ASC, person_faces.asset_id ASC, person_faces.face_index ASC
            """,
            bindings: [provenance.provider, provenance.model, provenance.version, provenance.settingsHash]
        )
        var embeddingsByPerson: [String: [[Double]]] = [:]
        for row in rows {
            guard let personID = row["person_id"], let faceJSON = row["face_json"] else {
                throw CatalogError.sqlite("confirmed face row is missing required columns")
            }
            let payload = try decode(FaceObservationPayload.self, from: faceJSON)
            embeddingsByPerson[personID, default: []].append(payload.embedding)
        }
        return embeddingsByPerson
    }

    public func faceObservationAssetCount(provenance: ProviderProvenance) throws -> Int {
        let rows = try database.rows(
            """
            SELECT COUNT(DISTINCT asset_id) AS asset_count
            FROM face_observations
            WHERE provider = ? AND model = ? AND version = ? AND settings_hash = ?
            """,
            bindings: [provenance.provider, provenance.model, provenance.version, provenance.settingsHash]
        )
        return rows.first.flatMap { $0["asset_count"] }.flatMap(Int.init) ?? 0
    }

    public func assignFaces(_ faceIDs: [FaceID], toPersonID personID: String) throws {
        let trimmedPersonID = personID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPersonID.isEmpty else {
            throw TeststripError.invalidState("person id is required")
        }
        guard !faceIDs.isEmpty else { return }
        let now = "\(Date().timeIntervalSince1970)"
        try database.transaction {
            for faceID in faceIDs {
                try database.execute(
                    """
                    INSERT INTO person_faces (person_id, asset_id, face_index, created_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(asset_id, face_index) DO UPDATE SET person_id = excluded.person_id
                    """,
                    bindings: [trimmedPersonID, faceID.assetID.rawValue, "\(faceID.faceIndex)", now]
                )
                try database.execute(
                    "DELETE FROM dismissed_faces WHERE asset_id = ? AND face_index = ?",
                    bindings: [faceID.assetID.rawValue, "\(faceID.faceIndex)"]
                )
            }
            for assetID in Set(faceIDs.map(\.assetID)).sorted(by: { $0.rawValue < $1.rawValue }) {
                try database.execute(
                    "INSERT OR IGNORE INTO person_assets (person_id, asset_id, created_at) VALUES (?, ?, ?)",
                    bindings: [trimmedPersonID, assetID.rawValue, now]
                )
                try database.execute(
                    "DELETE FROM dismissed_face_assets WHERE asset_id = ?",
                    bindings: [assetID.rawValue]
                )
            }
        }
    }

    public func dismissFaces(_ faceIDs: [FaceID]) throws {
        guard !faceIDs.isEmpty else { return }
        let now = "\(Date().timeIntervalSince1970)"
        try database.transaction {
            for faceID in faceIDs {
                try database.execute(
                    "INSERT OR IGNORE INTO dismissed_faces (asset_id, face_index, created_at) VALUES (?, ?, ?)",
                    bindings: [faceID.assetID.rawValue, "\(faceID.faceIndex)", now]
                )
                try database.execute(
                    "DELETE FROM person_faces WHERE asset_id = ? AND face_index = ?",
                    bindings: [faceID.assetID.rawValue, "\(faceID.faceIndex)"]
                )
            }
        }
    }
```

- [ ] In `mergePerson` (line 481), inside the existing transaction before `DELETE FROM person_assets`, add:

```swift
            try database.execute(
                "UPDATE person_faces SET person_id = ? WHERE person_id = ?",
                bindings: [trimmedTargetID, trimmedSourceID]
            )
```

- [ ] In `dismissFaceAssets` (line 503), inside the per-asset loop after the `person_assets` delete, add:

```swift
                try database.execute("DELETE FROM person_faces WHERE asset_id = ?", bindings: [assetID.rawValue])
```

- [ ] Run `swift test --filter CatalogDatabaseTests` — expect all green (including the pre-existing merge/dismiss tests).
- [ ] Commit: `git add -u && git commit -m "Add face suggestion queries and confirmed-face writes"`

---

## Task 6: Face suggestion builder — centroid matching and greedy clustering

**Files:**
- Create: `Sources/TeststripCore/People/FaceSuggestionBuilder.swift`
- Create: `Tests/TeststripCoreTests/FaceSuggestionBuilderTests.swift`

**Interfaces:**
- Produces: `FaceEmbedding(faceID:vector:)` (Equatable, Sendable)
- Produces: `FaceMatchSuggestion(personID:faceIDs:)`, `FaceClusterSuggestion(faceIDs:)`, `FaceSuggestions(matches:clusters:)` (all Equatable, Sendable)
- Produces: `FaceSuggestionBuilder(maximumMatchDistance:maximumClusterDistance:minimumClusterFaceCount:)` (Sendable) with `static let defaultMaximumMatchDistance = 0.35`, `defaultMaximumClusterDistance = 0.3`, `defaultMinimumClusterFaceCount = 2` and `func suggestions(unassignedFaces: [FaceEmbedding], confirmedFacesByPerson: [String: [[Double]]]) -> FaceSuggestions`
- Consumes: `FaceID` (Task 1). Pure — no I/O, mirrors `AssetStackBuilder`'s style (Sources/TeststripCore/Search/AssetStackBuilder.swift)

**Algorithm (all deterministic):**
1. Unit-normalize every vector; faces with empty or zero vectors are excluded. Distances between vectors of different dimensions are undefined → treated as no-match.
2. Per person: normalize confirmed vectors, take the arithmetic mean, re-normalize → centroid.
3. Process unassigned faces sorted by `(assetID.rawValue, faceIndex)`. A face whose nearest centroid is within `maximumMatchDistance` joins that person's match suggestion.
4. Remaining faces cluster greedily: join the nearest existing cluster whose current mean (re-normalized) is within `maximumClusterDistance`, else start a new cluster.
5. Drop clusters with fewer than `minimumClusterFaceCount` faces. Matches sort by face count descending then `personID`; clusters by face count descending then first `FaceID`.

**Steps:**

- [ ] Create the failing test file `Tests/TeststripCoreTests/FaceSuggestionBuilderTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class FaceSuggestionBuilderTests: XCTestCase {
    private func faceID(_ asset: String, _ index: Int = 0) -> FaceID {
        FaceID(assetID: AssetID(rawValue: asset), faceIndex: index)
    }

    func testClustersNearbyFacesAndDropsSingletons() {
        let suggestions = FaceSuggestionBuilder().suggestions(
            unassignedFaces: [
                FaceEmbedding(faceID: faceID("a"), vector: [1, 0, 0]),
                FaceEmbedding(faceID: faceID("b"), vector: [0.99, 0.14, 0]),
                FaceEmbedding(faceID: faceID("c"), vector: [0, 1, 0])
            ],
            confirmedFacesByPerson: [:]
        )

        XCTAssertEqual(suggestions.matches, [])
        XCTAssertEqual(suggestions.clusters, [
            FaceClusterSuggestion(faceIDs: [faceID("a"), faceID("b")])
        ])
    }

    func testMatchesFacesToConfirmedPersonCentroidBeforeClustering() {
        let suggestions = FaceSuggestionBuilder().suggestions(
            unassignedFaces: [
                FaceEmbedding(faceID: faceID("new-a"), vector: [0.99, 0.1, 0]),
                FaceEmbedding(faceID: faceID("new-b"), vector: [1, 0.05, 0]),
                FaceEmbedding(faceID: faceID("other"), vector: [0, 0, 1])
            ],
            confirmedFacesByPerson: ["person-maya": [[1, 0, 0], [0.98, 0.2, 0]]]
        )

        XCTAssertEqual(suggestions.matches, [
            FaceMatchSuggestion(personID: "person-maya", faceIDs: [faceID("new-a"), faceID("new-b")])
        ])
        XCTAssertEqual(suggestions.clusters, [])
    }

    func testIgnoresEmptyAndMismatchedDimensionEmbeddings() {
        let suggestions = FaceSuggestionBuilder().suggestions(
            unassignedFaces: [
                FaceEmbedding(faceID: faceID("empty"), vector: []),
                FaceEmbedding(faceID: faceID("short"), vector: [1]),
                FaceEmbedding(faceID: faceID("a"), vector: [1, 0, 0]),
                FaceEmbedding(faceID: faceID("b"), vector: [0.99, 0.14, 0])
            ],
            confirmedFacesByPerson: [:]
        )

        XCTAssertEqual(suggestions.matches, [])
        XCTAssertEqual(suggestions.clusters, [
            FaceClusterSuggestion(faceIDs: [faceID("a"), faceID("b")])
        ])
    }

    func testLargerClustersSortFirst() {
        let suggestions = FaceSuggestionBuilder().suggestions(
            unassignedFaces: [
                FaceEmbedding(faceID: faceID("solo-a"), vector: [1, 0, 0]),
                FaceEmbedding(faceID: faceID("solo-b"), vector: [0.99, 0.14, 0]),
                FaceEmbedding(faceID: faceID("trio-a"), vector: [0, 1, 0]),
                FaceEmbedding(faceID: faceID("trio-b"), vector: [0, 0.99, 0.14]),
                FaceEmbedding(faceID: faceID("trio-c"), vector: [0.14, 0.99, 0])
            ],
            confirmedFacesByPerson: [:]
        )

        XCTAssertEqual(suggestions.clusters.map { $0.faceIDs.count }, [3, 2])
    }
}
```

- [ ] Run `swift test --filter FaceSuggestionBuilderTests` — expect compile failure: `cannot find 'FaceSuggestionBuilder' in scope`.
- [ ] Create `Sources/TeststripCore/People/FaceSuggestionBuilder.swift`:

```swift
import Foundation

public struct FaceEmbedding: Equatable, Sendable {
    public var faceID: FaceID
    public var vector: [Double]

    public init(faceID: FaceID, vector: [Double]) {
        self.faceID = faceID
        self.vector = vector
    }
}

public struct FaceMatchSuggestion: Equatable, Sendable {
    public var personID: String
    public var faceIDs: [FaceID]

    public init(personID: String, faceIDs: [FaceID]) {
        self.personID = personID
        self.faceIDs = faceIDs
    }
}

public struct FaceClusterSuggestion: Equatable, Sendable {
    public var faceIDs: [FaceID]

    public init(faceIDs: [FaceID]) {
        self.faceIDs = faceIDs
    }
}

public struct FaceSuggestions: Equatable, Sendable {
    public var matches: [FaceMatchSuggestion]
    public var clusters: [FaceClusterSuggestion]

    public init(matches: [FaceMatchSuggestion] = [], clusters: [FaceClusterSuggestion] = []) {
        self.matches = matches
        self.clusters = clusters
    }
}

public struct FaceSuggestionBuilder: Sendable {
    public static let defaultMaximumMatchDistance = 0.35
    public static let defaultMaximumClusterDistance = 0.3
    public static let defaultMinimumClusterFaceCount = 2

    public var maximumMatchDistance: Double
    public var maximumClusterDistance: Double
    public var minimumClusterFaceCount: Int

    public init(
        maximumMatchDistance: Double = Self.defaultMaximumMatchDistance,
        maximumClusterDistance: Double = Self.defaultMaximumClusterDistance,
        minimumClusterFaceCount: Int = Self.defaultMinimumClusterFaceCount
    ) {
        self.maximumMatchDistance = maximumMatchDistance
        self.maximumClusterDistance = maximumClusterDistance
        self.minimumClusterFaceCount = minimumClusterFaceCount
    }

    public func suggestions(
        unassignedFaces: [FaceEmbedding],
        confirmedFacesByPerson: [String: [[Double]]]
    ) -> FaceSuggestions {
        let normalizedFaces: [(faceID: FaceID, vector: [Double])] = unassignedFaces
            .compactMap { face in
                Self.normalized(face.vector).map { (faceID: face.faceID, vector: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.faceID.assetID.rawValue != rhs.faceID.assetID.rawValue {
                    return lhs.faceID.assetID.rawValue < rhs.faceID.assetID.rawValue
                }
                return lhs.faceID.faceIndex < rhs.faceID.faceIndex
            }
        let centroidsByPerson = confirmedFacesByPerson.compactMapValues(Self.centroid)

        var matchedFaceIDsByPerson: [String: [FaceID]] = [:]
        var unmatchedFaces: [(faceID: FaceID, vector: [Double])] = []
        for face in normalizedFaces {
            let nearest = centroidsByPerson
                .compactMap { personID, centroid in
                    Self.distance(face.vector, centroid).map { (personID: personID, distance: $0) }
                }
                .min { lhs, rhs in
                    if lhs.distance != rhs.distance {
                        return lhs.distance < rhs.distance
                    }
                    return lhs.personID < rhs.personID
                }
            if let nearest, nearest.distance <= maximumMatchDistance {
                matchedFaceIDsByPerson[nearest.personID, default: []].append(face.faceID)
            } else {
                unmatchedFaces.append(face)
            }
        }

        var clusters: [(faceIDs: [FaceID], vectorSum: [Double])] = []
        for face in unmatchedFaces {
            let nearestIndex = clusters.indices
                .compactMap { index -> (index: Int, distance: Double)? in
                    guard let mean = Self.normalized(clusters[index].vectorSum),
                          let distance = Self.distance(face.vector, mean) else {
                        return nil
                    }
                    return (index: index, distance: distance)
                }
                .min { $0.distance < $1.distance }
            if let nearestIndex, nearestIndex.distance <= maximumClusterDistance {
                clusters[nearestIndex.index].faceIDs.append(face.faceID)
                clusters[nearestIndex.index].vectorSum = zip(clusters[nearestIndex.index].vectorSum, face.vector).map(+)
            } else {
                clusters.append((faceIDs: [face.faceID], vectorSum: face.vector))
            }
        }

        let matches = matchedFaceIDsByPerson
            .map { FaceMatchSuggestion(personID: $0.key, faceIDs: $0.value) }
            .sorted { lhs, rhs in
                if lhs.faceIDs.count != rhs.faceIDs.count {
                    return lhs.faceIDs.count > rhs.faceIDs.count
                }
                return lhs.personID < rhs.personID
            }
        let clusterSuggestions = clusters
            .filter { $0.faceIDs.count >= minimumClusterFaceCount }
            .map { FaceClusterSuggestion(faceIDs: $0.faceIDs) }
            .sorted { lhs, rhs in
                if lhs.faceIDs.count != rhs.faceIDs.count {
                    return lhs.faceIDs.count > rhs.faceIDs.count
                }
                return (lhs.faceIDs.first?.assetID.rawValue ?? "") < (rhs.faceIDs.first?.assetID.rawValue ?? "")
            }
        return FaceSuggestions(matches: matches, clusters: clusterSuggestions)
    }

    private static func normalized(_ vector: [Double]) -> [Double]? {
        guard !vector.isEmpty else { return nil }
        let magnitude = vector.map { $0 * $0 }.reduce(0, +).squareRoot()
        guard magnitude > 0 else { return nil }
        return vector.map { $0 / magnitude }
    }

    private static func centroid(of vectors: [[Double]]) -> [Double]? {
        let normalizedVectors = vectors.compactMap(normalized)
        guard let dimension = normalizedVectors.first?.count else { return nil }
        let matching = normalizedVectors.filter { $0.count == dimension }
        var sum = [Double](repeating: 0, count: dimension)
        for vector in matching {
            for index in vector.indices {
                sum[index] += vector[index]
            }
        }
        return normalized(sum)
    }

    private static func distance(_ lhs: [Double], _ rhs: [Double]) -> Double? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        return zip(lhs, rhs)
            .map { first, second in
                let delta = first - second
                return delta * delta
            }
            .reduce(0, +)
            .squareRoot()
    }
}
```

- [ ] Run `swift test --filter FaceSuggestionBuilderTests` — expect 4 tests passing.
- [ ] Commit: `git add Sources/TeststripCore/People/FaceSuggestionBuilder.swift Tests/TeststripCoreTests/FaceSuggestionBuilderTests.swift && git commit -m "Add face suggestion builder with match and cluster grouping"`

---

## Task 7: Surface provisional face suggestions in the app model

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift`
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Produces (top-level type in AppModel.swift, immediately above `public enum SidebarRowTarget`, line 367):

```swift
public struct PeopleFaceSuggestion: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case matchExisting(personID: String, personName: String)
        case newPerson
    }

    public var id: String
    public var kind: Kind
    public var faceIDs: [FaceID]
    public var representativeFace: FaceID
    public var representativeBoundingBox: FaceBoundingBox
    public var assetIDs: [AssetID]
}
```

- Produces on `AppModel`:
  - `public private(set) var peopleFaceSuggestions: [PeopleFaceSuggestion] = []` and `public private(set) var peopleFaceObservationAssetCount = 0` (declare next to `catalogPeople`, line 1114)
  - `public static let maximumFaceSuggestionInputCount = 2000`
  - `public func refreshPeopleFaceSuggestions()`
  - `public func confirmPeopleFaceSuggestion(_ suggestion: PeopleFaceSuggestion) throws` (match kind only; throws `TeststripError.invalidState("face suggestion has no matched person; name it instead")` for `.newPerson`)
  - `@discardableResult public func confirmPeopleFaceSuggestion(_ suggestion: PeopleFaceSuggestion, personName: String, personID: String = "person-\(UUID().uuidString)") throws -> CatalogPerson` (new-person kind; trims/validates the name exactly like `confirmSelectedAssetsAsPerson`, AppModel.swift:2127-2149)
  - `public func dismissPeopleFaceSuggestion(_ suggestion: PeopleFaceSuggestion) throws`
  - `public func showPeopleFaceSuggestionPhotos(_ suggestion: PeopleFaceSuggestion) throws`
- Modifies: `selectSidebarTarget` case `.people` (AppModel.swift:2770-2773) appends `refreshPeopleFaceSuggestions()`; `refreshCatalogEvaluationKindSummaries()` (AppModel.swift:7562-7572) appends `if selectedView == .people { refreshPeopleFaceSuggestions() }` before `rebuildSidebarSections()`
- Consumes: `CatalogRepository.unassignedFaceObservations/confirmedFaceEmbeddingsByPerson/faceObservationAssetCount/assignFaces/dismissFaces` (Task 5), `FaceSuggestionBuilder` (Task 6), `AppleVisionEvaluationProvider.faceProvenance` (Task 3), `selectSidebarTarget(.allPhotographs)`, `clearBatchSelection()` (line 2700), `setBatchSelection(_:isSelected:)` (line 2654)

**Behavior notes (write these, not more):**
- `refreshPeopleFaceSuggestions()` loads `unassignedFaceObservations(provenance: AppleVisionEvaluationProvider.faceProvenance, limit: Self.maximumFaceSuggestionInputCount)` and `confirmedFaceEmbeddingsByPerson(...)`, runs `FaceSuggestionBuilder()`, maps results to `PeopleFaceSuggestion` (match id `"face-match-\(personID)"`, cluster id `"face-cluster-\(assetID)-\(faceIndex)"` from the first face; person names resolved from `catalogPeople`, matches with unknown person IDs skipped; `assetIDs` = unique asset IDs preserving face order; representative = first face). Also refreshes `peopleFaceObservationAssetCount`. Errors set `errorMessage` (the `refreshCatalogFolders` pattern, line 7550).
- Confirm (match): `assignFaces(suggestion.faceIDs, toPersonID:)`, then `catalogPeople = try catalog.repository.people()`, `refreshCatalogEvaluationKindSummaries()`, `refreshPeopleFaceSuggestions()`, `try loadCatalogPage(preferredSelection: nil)` — the same refresh set as `confirmSelectedAssetsAsPerson`.
- Confirm (new person): `upsertPerson(id:name:)` + `assignFaces` + the same refresh set; returns the created `CatalogPerson`.
- Dismiss: `dismissFaces(suggestion.faceIDs)` + `refreshCatalogEvaluationKindSummaries()` + `refreshPeopleFaceSuggestions()`.
- Show photos: `try selectSidebarTarget(.allPhotographs)`, `clearBatchSelection()`, `setBatchSelection(_, isSelected: true)` per asset, `selectedAssetID = suggestion.assetIDs.first`.

**Steps:**

- [ ] Add failing tests to `AppModelTests.swift` (below `testMergePersonPersistsAndRefreshesCatalogPeople`, ~line 4918). Use this shared seed helper (private in the test class) and tests:

```swift
    private func makeFaceSuggestionModel(
        named name: String
    ) throws -> (model: AppModel, repository: CatalogRepository, incoming: Asset, groupA: Asset, groupB: Asset) {
        let known = makeAsset(id: "known", path: "/Volumes/NAS/Wedding/known.jpg", rating: 0)
        let incoming = makeAsset(id: "incoming", path: "/Volumes/NAS/Wedding/incoming.jpg", rating: 0)
        let groupA = makeAsset(id: "group-a", path: "/Volumes/NAS/Wedding/group-a.jpg", rating: 0)
        let groupB = makeAsset(id: "group-b", path: "/Volumes/NAS/Wedding/group-b.jpg", rating: 0)
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
        return (model, repository, incoming, groupA, groupB)
    }

    func testRefreshPeopleFaceSuggestionsBuildsMatchAndClusterSuggestions() throws {
        let (model, _, incoming, groupA, groupB) = try makeFaceSuggestionModel(named: "app-model-face-suggestions")

        model.refreshPeopleFaceSuggestions()

        XCTAssertEqual(model.peopleFaceSuggestions.count, 2)
        XCTAssertEqual(model.peopleFaceObservationAssetCount, 4)
        let match = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })
        XCTAssertEqual(match.kind, .matchExisting(personID: "person-maya", personName: "Maya"))
        XCTAssertEqual(match.faceIDs, [FaceID(assetID: incoming.id, faceIndex: 0)])
        XCTAssertEqual(match.assetIDs, [incoming.id])
        let cluster = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.kind == .newPerson })
        XCTAssertEqual(cluster.faceIDs, [
            FaceID(assetID: groupA.id, faceIndex: 0),
            FaceID(assetID: groupB.id, faceIndex: 0)
        ])
        XCTAssertEqual(cluster.id, "face-cluster-\(groupA.id.rawValue)-0")
    }

    func testConfirmMatchSuggestionAssignsFacesToExistingPerson() throws {
        let (model, repository, incoming, _, _) = try makeFaceSuggestionModel(named: "app-model-face-confirm-match")
        model.refreshPeopleFaceSuggestions()
        let match = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })

        try model.confirmPeopleFaceSuggestion(match)

        XCTAssertEqual(Set(try repository.assetIDs(personID: "person-maya")).contains(incoming.id), true)
        XCTAssertNil(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })
        XCTAssertEqual(model.catalogPeople.first?.assetCount, 2)
    }

    func testConfirmClusterSuggestionCreatesNamedPersonThroughExistingPath() throws {
        let (model, repository, _, groupA, groupB) = try makeFaceSuggestionModel(named: "app-model-face-confirm-cluster")
        model.refreshPeopleFaceSuggestions()
        let cluster = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.kind == .newPerson })

        let person = try model.confirmPeopleFaceSuggestion(cluster, personName: " Lee ", personID: "person-lee")

        XCTAssertEqual(person, CatalogPerson(id: "person-lee", name: "Lee", assetCount: 2))
        XCTAssertEqual(try repository.assetIDs(personID: "person-lee"), [groupA.id, groupB.id])
        XCTAssertNil(model.peopleFaceSuggestions.first { $0.kind == .newPerson })
    }

    func testDismissSuggestionRemovesItFromFutureSuggestions() throws {
        let (model, repository, _, _, _) = try makeFaceSuggestionModel(named: "app-model-face-dismiss")
        model.refreshPeopleFaceSuggestions()
        let cluster = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.kind == .newPerson })

        try model.dismissPeopleFaceSuggestion(cluster)

        XCTAssertNil(model.peopleFaceSuggestions.first { $0.kind == .newPerson })
        XCTAssertEqual(try repository.people(), model.catalogPeople)
        XCTAssertEqual(try repository.assetIDs(personID: "person-lee"), [])
    }

    func testSelectingPeopleSidebarTargetRefreshesFaceSuggestions() throws {
        let (model, _, _, _, _) = try makeFaceSuggestionModel(named: "app-model-face-people-entry")
        XCTAssertEqual(model.peopleFaceSuggestions, [])

        try model.selectSidebarTarget(.people)

        XCTAssertEqual(model.peopleFaceSuggestions.count, 2)
    }
```

- [ ] Run `swift test --filter AppModelTests.testRefreshPeopleFaceSuggestionsBuildsMatchAndClusterSuggestions` — expect compile failure: `value of type 'AppModel' has no member 'refreshPeopleFaceSuggestions'`.
- [ ] Implement per the interfaces and behavior notes above. Place the action methods directly after `dismissSelectedFaceReviewAssets` (line 2171). The mapping helper:

```swift
    private static func peopleFaceSuggestions(
        from suggestions: FaceSuggestions,
        observationsByFaceID: [FaceID: CatalogFaceObservation],
        personNamesByID: [String: String]
    ) -> [PeopleFaceSuggestion] {
        var result: [PeopleFaceSuggestion] = []
        for match in suggestions.matches {
            guard let personName = personNamesByID[match.personID],
                  let representative = match.faceIDs.first,
                  let observation = observationsByFaceID[representative] else { continue }
            result.append(PeopleFaceSuggestion(
                id: "face-match-\(match.personID)",
                kind: .matchExisting(personID: match.personID, personName: personName),
                faceIDs: match.faceIDs,
                representativeFace: representative,
                representativeBoundingBox: observation.boundingBox,
                assetIDs: Self.uniqueAssetIDs(match.faceIDs)
            ))
        }
        for cluster in suggestions.clusters {
            guard let representative = cluster.faceIDs.first,
                  let observation = observationsByFaceID[representative] else { continue }
            result.append(PeopleFaceSuggestion(
                id: "face-cluster-\(representative.assetID.rawValue)-\(representative.faceIndex)",
                kind: .newPerson,
                faceIDs: cluster.faceIDs,
                representativeFace: representative,
                representativeBoundingBox: observation.boundingBox,
                assetIDs: Self.uniqueAssetIDs(cluster.faceIDs)
            ))
        }
        return result
    }

    private static func uniqueAssetIDs(_ faceIDs: [FaceID]) -> [AssetID] {
        var seen = Set<AssetID>()
        return faceIDs.compactMap { seen.insert($0.assetID).inserted ? $0.assetID : nil }
    }
```

- [ ] Run `swift test --filter AppModelTests` — expect all green.
- [ ] Commit: `git add -u && git commit -m "Surface provisional face suggestions in the app model"`

---

## Task 8: Present the faces-need-a-name band in PeoplePresentation

**Files:**
- Modify: `Sources/TeststripApp/PeopleView.swift` (`PeoplePresentation`, line 327; new `PeopleFaceSuggestionCard` struct)
- Test: `Tests/TeststripAppTests/PeoplePresentationTests.swift`

**Interfaces:**
- Modifies: `PeoplePresentation.init(totalAssetCount:namedPeople:evaluationSummaries:canRequestCurrentScopeFaceScan:faceSuggestions:faceObservationAssetCount:)` — two new params with defaults `faceSuggestions: [PeopleFaceSuggestion] = []`, `faceObservationAssetCount: Int = 0` (all existing call sites and tests keep compiling)
- Produces: `PeoplePresentation.suggestionCards: [PeopleFaceSuggestionCard]` where:

```swift
struct PeopleFaceSuggestionCard: Equatable, Identifiable {
    var id: String
    var title: String              // "Is this Maya?" / "Who is this?"
    var countText: String          // "1 face · 1 photo" / "2 faces · 2 photos"
    var confirmActionTitle: String // "Maya" / "Name…"
    var isOneTapConfirm: Bool
    var suggestion: PeopleFaceSuggestion
}
```

- Modifies presentation copy (exact strings):
  - `reviewStripTitle` when `faceSuggestions` is non-empty: `"TESTSTRIP · \(totalFaces) FACES NEED A NAME"` (`totalFaces` = sum of `faceIDs.count`; singular: `"TESTSTRIP · 1 FACE NEEDS A NAME"`). Existing titles unchanged otherwise.
  - `reviewStripStatusText` when suggestions exist: match count > 0 → `"1 group matches confirmed people"` / `"\(n) groups match confirmed people"`; otherwise `"\(count) new group"`/`"\(count) new groups"`.
  - `reviewStripDetail` when suggestions exist: `"Face groups are provisional until you confirm. Confirming writes people to the catalog; dismissing hides the group."`
  - `reviewStripDetail` when suggestions are empty AND `photosWithFaceSignals > 0` AND `faceObservationAssetCount == 0`: `"Face signals predate grouping; run Scan current scope to compute face embeddings."` (honest re-scan prompt for pre-existing catalogs).
  - `deferredFaceActionStatus` becomes: `"Split person and face-box naming are deferred; automatic grouping suggestions, one-tap confirm, manual naming, and merge are available now."`

**Steps:**

- [ ] Add failing tests to `PeoplePresentationTests.swift`:

```swift
    private func matchSuggestion() -> PeopleFaceSuggestion {
        PeopleFaceSuggestion(
            id: "face-match-person-maya",
            kind: .matchExisting(personID: "person-maya", personName: "Maya"),
            faceIDs: [FaceID(assetID: AssetID(rawValue: "incoming"), faceIndex: 0)],
            representativeFace: FaceID(assetID: AssetID(rawValue: "incoming"), faceIndex: 0),
            representativeBoundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            assetIDs: [AssetID(rawValue: "incoming")]
        )
    }

    private func clusterSuggestion() -> PeopleFaceSuggestion {
        PeopleFaceSuggestion(
            id: "face-cluster-group-a-0",
            kind: .newPerson,
            faceIDs: [
                FaceID(assetID: AssetID(rawValue: "group-a"), faceIndex: 0),
                FaceID(assetID: AssetID(rawValue: "group-b"), faceIndex: 0)
            ],
            representativeFace: FaceID(assetID: AssetID(rawValue: "group-a"), faceIndex: 0),
            representativeBoundingBox: FaceBoundingBox(x: 0.2, y: 0.3, width: 0.25, height: 0.25),
            assetIDs: [AssetID(rawValue: "group-a"), AssetID(rawValue: "group-b")]
        )
    }

    func testFaceSuggestionBandPresentsNeedsANameCards() {
        let presentation = PeoplePresentation(
            totalAssetCount: 100,
            evaluationSummaries: [CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 3)],
            faceSuggestions: [matchSuggestion(), clusterSuggestion()],
            faceObservationAssetCount: 4
        )

        XCTAssertEqual(presentation.reviewStripTitle, "TESTSTRIP · 3 FACES NEED A NAME")
        XCTAssertEqual(presentation.reviewStripStatusText, "1 group matches confirmed people")
        XCTAssertEqual(
            presentation.reviewStripDetail,
            "Face groups are provisional until you confirm. Confirming writes people to the catalog; dismissing hides the group."
        )
        XCTAssertEqual(presentation.suggestionCards.map(\.title), ["Is this Maya?", "Who is this?"])
        XCTAssertEqual(presentation.suggestionCards.map(\.confirmActionTitle), ["Maya", "Name…"])
        XCTAssertEqual(presentation.suggestionCards.map(\.countText), ["1 face · 1 photo", "2 faces · 2 photos"])
        XCTAssertEqual(presentation.suggestionCards.map(\.isOneTapConfirm), [true, false])
    }

    func testFaceBandPromptsRescanWhenSignalsPredateGrouping() {
        let presentation = PeoplePresentation(
            totalAssetCount: 100,
            evaluationSummaries: [CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 3)],
            faceSuggestions: [],
            faceObservationAssetCount: 0
        )

        XCTAssertEqual(presentation.suggestionCards, [])
        XCTAssertEqual(
            presentation.reviewStripDetail,
            "Face signals predate grouping; run Scan current scope to compute face embeddings."
        )
    }
```

    and update `testPresentationTracksDeferredFaceActionsAsStatusCopyInsteadOfDisabledButtons` (line 135) to assert the new truth:

```swift
        XCTAssertTrue(presentation.visibleDeferredFaceActionTitles.isEmpty)
        XCTAssertTrue(presentation.deferredFaceActionStatus.localizedCaseInsensitiveContains("automatic grouping"))
        XCTAssertTrue(presentation.deferredFaceActionStatus.localizedCaseInsensitiveContains("split"))
        XCTAssertTrue(presentation.deferredFaceActionStatus.localizedCaseInsensitiveContains("face-box naming"))
```

- [ ] Run `swift test --filter PeoplePresentationTests` — expect compile failure on the new init parameters.
- [ ] Implement in `PeopleView.swift`: store `faceSuggestions` and `faceObservationAssetCount` on `PeoplePresentation`, add the `suggestionCards` computed property and the copy changes above. `countText` pluralization: `"\(faces) \(faces == 1 ? "face" : "faces") · \(photos) \(photos == 1 ? "photo" : "photos")"`.
- [ ] Run `swift test --filter PeoplePresentationTests` — expect all green.
- [ ] Commit: `git add -u && git commit -m "Present the faces-need-a-name band in People"`

---

## Task 9: Render face suggestion cards with face-crop avatars

**Files:**
- Create: `Sources/TeststripApp/FaceCropAvatar.swift`
- Modify: `Sources/TeststripApp/PeopleView.swift` (view body + wiring)
- Create: `Tests/TeststripAppTests/FaceCropAvatarTests.swift`

**Interfaces:**
- Produces: `enum FaceCropGeometry { static func pixelCropRect(boundingBox: FaceBoundingBox, imagePixelWidth: Int, imagePixelHeight: Int, padding: Double = 0.25) -> CGRect }` — pads by `padding * max(width, height)`, clamps to the unit box, flips Vision's lower-left origin to image top-left (`topLeftY = 1 - y - height`), scales to pixels, returns `.integral` intersected with the image bounds; degenerate boxes (zero width/height or non-positive image dims) return the full image rect
- Produces: `struct FaceCropAvatar: View` with `var previewURL: URL?`, `var boundingBox: FaceBoundingBox`, `var diameter: CGFloat = 52` — async-loads the preview off the main actor (mirroring `PreviewImageDataLoader`, CachedPreviewImage.swift:4-19), crops via `NSImage.cgImage(forProposedRect:context:hints:)` + `CGImage.cropping(to:)`, renders circle-clipped; fallback is `Circle().fill(.quaternary)`
- Modifies `PeopleView`:
  - `presentation` passes `faceSuggestions: model.peopleFaceSuggestions, faceObservationAssetCount: model.peopleFaceObservationAssetCount`
  - `recognitionStatusPanel` renders `presentation.suggestionCards` in a `LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], ...)` ABOVE the existing `reviewCards` grid. Each card: `FaceCropAvatar(previewURL: model.previewURL(for: card.suggestion.representativeFace.assetID, levels: [.grid, .medium, .micro]), boundingBox: card.suggestion.representativeBoundingBox)`, `card.countText` + `card.title` text column, a prominent confirm button (`card.confirmActionTitle`), and a ✕ dismiss button. Card body tap (outside the buttons) calls `showPhotos`.
  - Confirm button: `isOneTapConfirm` → `model.confirmPeopleFaceSuggestion(card.suggestion)`; otherwise sets `@State private var namingSuggestion: PeopleFaceSuggestion?` which drives `.sheet(item: $namingSuggestion)` reusing the existing name-sheet layout (`TextField` + Cancel/Create, PeopleView.swift:170-191) but calling `model.confirmPeopleFaceSuggestion(suggestion, personName: personName)`.
  - Dismiss: `model.dismissPeopleFaceSuggestion(card.suggestion)`. Show photos: `model.showPeopleFaceSuggestionPhotos(card.suggestion)`. All wrapped in the file's existing `do/catch { model.errorMessage = ... }` pattern.
  - Add `.task { model.refreshPeopleFaceSuggestions() }` on the People `ScrollView` so direct view entry (not just sidebar selection) refreshes suggestions.

**Steps:**

- [ ] Create failing `Tests/TeststripAppTests/FaceCropAvatarTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class FaceCropAvatarTests: XCTestCase {
    func testPixelCropRectFlipsPadsAndClamps() {
        let rect = FaceCropGeometry.pixelCropRect(
            boundingBox: FaceBoundingBox(x: 0.4, y: 0.2, width: 0.2, height: 0.2),
            imagePixelWidth: 1000,
            imagePixelHeight: 500,
            padding: 0.25
        )
        // Padded unit box: x 0.35...0.65; Vision y 0.15...0.65 flips to top-left y 0.35...0.85.
        XCTAssertEqual(rect.minX, 350, accuracy: 1)
        XCTAssertEqual(rect.minY, 175, accuracy: 1)
        XCTAssertEqual(rect.width, 300, accuracy: 1)
        XCTAssertEqual(rect.height, 250, accuracy: 1)

        let clamped = FaceCropGeometry.pixelCropRect(
            boundingBox: FaceBoundingBox(x: 0.9, y: 0.0, width: 0.2, height: 0.2),
            imagePixelWidth: 100,
            imagePixelHeight: 100,
            padding: 0.25
        )
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 100, height: 100).contains(clamped))
    }

    func testDegenerateBoxFallsBackToFullImage() {
        XCTAssertEqual(
            FaceCropGeometry.pixelCropRect(
                boundingBox: FaceBoundingBox(x: 0.5, y: 0.5, width: 0, height: 0),
                imagePixelWidth: 640,
                imagePixelHeight: 480
            ),
            CGRect(x: 0, y: 0, width: 640, height: 480)
        )
    }
}
```

    (Flip check for the first assertion: padded Vision box y-range is 0.15–0.65; top-left-origin minY = (1 − 0.65) × 500 = 175, height = 0.5 × 500 = 250.)
- [ ] Run `swift test --filter FaceCropAvatarTests` — expect compile failure: `cannot find 'FaceCropGeometry' in scope`.
- [ ] Create `Sources/TeststripApp/FaceCropAvatar.swift` implementing `FaceCropGeometry` and `FaceCropAvatar` per the interface description. The crop loader:

```swift
    private static func loadCroppedFace(previewURL: URL, boundingBox: FaceBoundingBox) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: previewURL, options: [.mappedIfSafe]),
                  let image = NSImage(data: data),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            let rect = FaceCropGeometry.pixelCropRect(
                boundingBox: boundingBox,
                imagePixelWidth: cgImage.width,
                imagePixelHeight: cgImage.height
            )
            guard let cropped = cgImage.cropping(to: rect) else { return nil }
            return NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
        }.value
    }
```

- [ ] Run `swift test --filter FaceCropAvatarTests` — expect green.
- [ ] Wire the band into `PeopleView` per the interface description (no new presentation logic — everything displayable comes from `PeoplePresentation.suggestionCards`, Task 8).
- [ ] Run `swift test` (TeststripAppTests are cheap enough here) — expect all green.
- [ ] Commit: `git add Sources/TeststripApp/FaceCropAvatar.swift Tests/TeststripAppTests/FaceCropAvatarTests.swift && git add -u && git commit -m "Render face suggestion cards with face-crop avatars"`

---

## Task 10: Update People surface truth copy and run the full gate

**Files:**
- Modify: `Sources/TeststripApp/LiveMockupPlaceholder.swift` (lines 67-79, 295-301)
- Test: `Tests/TeststripAppTests/PlaceholderTests.swift` (lines 175-176, 185-186)

**Interfaces:** copy-only; no signatures change.

**Steps:**

- [ ] Update `PlaceholderTests.swift` assertions first (failing test): replace the two `"automatic clustering"` / `"face-box-level naming remain disabled"` assertion pairs with:

```swift
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("automatic grouping"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("split and face-box-level naming remain disabled"))
```

    (and the same two lines against `surface.currentImplementation` in the 5a surface test).
- [ ] Run `swift test --filter PlaceholderTests` — expect the two updated tests failing against the old copy.
- [ ] Update `LiveMockupPlaceholders.peopleSidebar.currentFallback` to:

    `"Selectable People route with a faces-need-a-name band of automatic grouping suggestions over persisted face embeddings, one-tap confirm for matches to confirmed people, name-the-group confirmation for new clusters, per-group dismissal, Apple Vision scan action for cached previews in the current scope, manual Name selection confirmation, selected-photo face-review dismissal, persisted named people rows, and manual merge between confirmed people; suggestions stay provisional until confirmed, and split and face-box-level naming remain disabled."`

    Update `LiveMockupPlaceholders.peopleFaceActions.currentFallback` to:

    `"Confirm, name, and dismiss are live on automatic grouping suggestion cards; nothing is written until the user confirms, and Split person and face-box-level naming remain disabled future actions."`

    Update the `designID: "5a"` surface `currentImplementation` to:

    `"People route shows automatic grouping suggestions with one-tap confirm and dismiss backed by persisted per-face embeddings, plus the manual review strip, scan action, Name selection, face-review dismissal, persisted named people rows, and merge; suggestions are provisional until confirmed, and split and face-box-level naming remain disabled."`

- [ ] Run `swift test --filter PlaceholderTests` — expect green.
- [ ] Full gate: run `swift test` — expect the entire suite green with pristine output.
- [ ] Build gate: run `./script/build_and_run.sh --build` — expect a clean build.
- [ ] Commit: `git add -u && git commit -m "Update People surface truth copy for automatic grouping"`

---

## Deferred / explicitly out of scope

- Split person, face-box-level naming UI, and re-clustering settings (product-deferred; the copy in Task 10 says so).
- Threshold tuning harness / bench command — thresholds ship as injectable constants; tune against a real catalog after the flow exists (open question below).
- Face-crop avatars in the ALL PEOPLE grid (keeps existing gradient circles).
- Any XMP face-region writing (never automatic anyway; not part of this feature).
- Automatically re-running scans on catalogs whose face signals predate face rows (the band prompts the user to use the existing "Scan current scope" action instead).
