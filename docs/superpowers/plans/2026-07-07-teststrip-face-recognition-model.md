# On-Device Face-Identity Recognition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the whole-image feature-print embedding used for face grouping with a bundled Core ML ArcFace identity model, so same-person faces cluster together and different people stay apart.

**Architecture:** Swap only the embedding *source*. A new `FaceAligner` (Vision landmarks → canonical 112×112 crop) feeds a bundled Core ML ArcFace model (`FaceEmbeddingModel` protocol / `ArcFaceCoreMLModel`) that emits 512-d L2-normalized identity embeddings. These flow through the existing `AppleVisionFaceObservation` → `replaceFaceObservations` → `FaceSuggestionBuilder` path unchanged, under a new `ProviderProvenance` so old feature-print observations are inert. Clustering thresholds are re-derived for the ArcFace scale.

**Tech Stack:** Swift 6, SwiftPM, Apple Vision (`VNDetectFaceLandmarks`), Core ML (`MLModel` — first use in this codebase), Core Graphics. Model conversion uses Python `coremltools` (implementer's toolchain, one-time).

## Global Constraints

- Follow CLAUDE.md: TDD (failing test first, `swift test` green before every commit), smallest reasonable changes, match surrounding style, commit frequently.
- Model provenance for face identity embeddings is exactly `ProviderProvenance(provider: "face-recognition", model: "arcface-w600k-r50", version: "1", settingsHash: "default")`.
- Embeddings are 512-d and L2-normalized (‖v‖ ≈ 1.0).
- The `.mlpackage` is NOT committed to git — it is downloaded via a checksum-verified manifest and copied into the app bundle at build. Add its download destination to `.gitignore`.
- Confirm-before-write is invariant: nothing persists to `people`/`person_assets` until the user confirms a suggestion. No task changes that.
- License note: the InsightFace weights are research/non-commercial — acceptable for the personal alpha, a recorded pre-release blocker. Do not spend effort resolving licensing in this plan.

## File Structure

- Create `Sources/TeststripCore/People/FaceAligner.swift` — landmark→112×112 alignment (pure geometry).
- Create `Sources/TeststripCore/People/FaceEmbeddingModel.swift` — the `FaceEmbeddingModel` protocol + `FaceEmbeddingModelError`.
- Create `Sources/TeststripCore/People/ArcFaceCoreMLModel.swift` — Core ML implementation.
- Create `Sources/TeststripCore/People/FaceRecognitionEmbedder.swift` — detect→landmarks→align→embed orchestration.
- Modify `Sources/TeststripCore/Evaluation/AppleVisionEvaluationProvider.swift` — `evaluateWithFaces` uses the new embedder + face-recognition provenance for face observations (the whole-image analysis provenance is unchanged).
- Modify `Sources/TeststripCore/People/FaceSuggestionBuilder.swift` — retune thresholds.
- Create `sample-data/face-recognition-model.tsv` — download manifest (filename, url, md5, size, source_url).
- Modify `script/download_sample_photos.sh` usage (already `--manifest`/`--destination` parameterized) — no code change; a new wrapper `script/download_face_model.sh` calls it with the model manifest and destination.
- Modify `script/build_and_run.sh` — copy the downloaded `.mlpackage` into `$APP_RESOURCES` if present.
- Modify `.gitignore` — ignore the model download destination.
- Create tests under `Tests/TeststripCoreTests/`: `FaceAlignerTests.swift`, `ArcFaceCoreMLModelTests.swift`, `FaceRecognitionEmbedderTests.swift`, `FaceIdentityClusteringTests.swift`, and extend the existing `FaceCorpusGroupingTests.swift` for acceptance.
- Create `test/scenarios/people-cluster-by-identity.md` and update `test/scenarios/people-name-face-group-happy-path.md`.

---

### Task 1: FaceAligner — landmark-based 112×112 alignment

**Files:**
- Create: `Sources/TeststripCore/People/FaceAligner.swift`
- Test: `Tests/TeststripCoreTests/FaceAlignerTests.swift`

**Interfaces:**
- Consumes: nothing (pure geometry + Core Graphics).
- Produces: `FaceAligner.similarityTransform(fromLeftEye:rightEye:nose:leftMouth:rightMouth:) -> CGAffineTransform?` (nil if points are degenerate) and `FaceAligner.alignedFace(from image: CGImage, sourcePoints: FaceLandmarkPoints) -> CGImage?`. `FaceLandmarkPoints` is a struct of five `CGPoint`s in image pixel coordinates. The canonical ArcFace reference points (for a 112×112 output) are the InsightFace standard: leftEye (38.29, 51.69), rightEye (73.53, 51.69), nose (56.02, 71.74), leftMouth (41.55, 92.37), rightMouth (70.73, 92.37).

- [ ] **Step 1: Write the failing test for the transform**

```swift
import XCTest
import CoreGraphics
@testable import TeststripCore

final class FaceAlignerTests: XCTestCase {
    func testTransformMapsSourceLandmarksToCanonicalPositions() {
        // Source landmarks already at canonical positions must map ~identity.
        let canonical = FaceAligner.canonicalPoints
        let points = FaceLandmarkPoints(
            leftEye: canonical.leftEye, rightEye: canonical.rightEye,
            nose: canonical.nose, leftMouth: canonical.leftMouth, rightMouth: canonical.rightMouth
        )
        let t = try XCTUnwrap(FaceAligner.similarityTransform(from: points))
        for p in [canonical.leftEye, canonical.rightEye, canonical.nose] {
            let mapped = p.applying(t)
            XCTAssertEqual(mapped.x, p.x, accuracy: 0.5)
            XCTAssertEqual(mapped.y, p.y, accuracy: 0.5)
        }
    }

    func testTransformRecoversAKnownScaleAndTranslation() {
        // Source = canonical scaled 2x and shifted (+10,+20): transform must undo it.
        let c = FaceAligner.canonicalPoints
        func f(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * 2 + 10, y: p.y * 2 + 20) }
        let points = FaceLandmarkPoints(leftEye: f(c.leftEye), rightEye: f(c.rightEye),
            nose: f(c.nose), leftMouth: f(c.leftMouth), rightMouth: f(c.rightMouth))
        let t = try XCTUnwrap(FaceAligner.similarityTransform(from: points))
        let mapped = f(c.leftEye).applying(t)
        XCTAssertEqual(mapped.x, c.leftEye.x, accuracy: 0.5)
        XCTAssertEqual(mapped.y, c.leftEye.y, accuracy: 0.5)
    }

    func testDegeneratePointsReturnNil() {
        let zero = CGPoint.zero
        let points = FaceLandmarkPoints(leftEye: zero, rightEye: zero, nose: zero, leftMouth: zero, rightMouth: zero)
        XCTAssertNil(FaceAligner.similarityTransform(from: points))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FaceAlignerTests`
Expected: FAIL — `FaceAligner` / `FaceLandmarkPoints` undefined.

- [ ] **Step 3: Implement `FaceAligner`**

Implement a least-squares similarity transform (Umeyama, rotation+uniform-scale+translation) from the five source points to `canonicalPoints`. Use the closed-form 2D similarity solution (compute means, centered covariance, scale = ‖canonical-centered‖/‖source-centered‖ combined with the rotation from the cross/dot of centered vectors). Return `nil` when the source points are degenerate (zero variance). Provide `alignedFace(from:sourcePoints:)` that draws `image` into a 112×112 `CGContext` using the transform and returns the `CGImage`.

```swift
import CoreGraphics
import Foundation

public struct FaceLandmarkPoints: Equatable, Sendable {
    public var leftEye: CGPoint
    public var rightEye: CGPoint
    public var nose: CGPoint
    public var leftMouth: CGPoint
    public var rightMouth: CGPoint
    public init(leftEye: CGPoint, rightEye: CGPoint, nose: CGPoint, leftMouth: CGPoint, rightMouth: CGPoint) {
        self.leftEye = leftEye; self.rightEye = rightEye; self.nose = nose
        self.leftMouth = leftMouth; self.rightMouth = rightMouth
    }
    var array: [CGPoint] { [leftEye, rightEye, nose, leftMouth, rightMouth] }
}

public enum FaceAligner {
    public static let outputSize = 112
    public static let canonicalPoints = FaceLandmarkPoints(
        leftEye: CGPoint(x: 38.2946, y: 51.6963),
        rightEye: CGPoint(x: 73.5318, y: 51.5014),
        nose: CGPoint(x: 56.0252, y: 71.7366),
        leftMouth: CGPoint(x: 41.5493, y: 92.3655),
        rightMouth: CGPoint(x: 70.7299, y: 92.2041))

    public static func similarityTransform(from src: FaceLandmarkPoints) -> CGAffineTransform? {
        let from = src.array, to = canonicalPoints.array
        let n = CGFloat(from.count)
        let fMean = from.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x/n, y: $0.y + $1.y/n) }
        let tMean = to.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x/n, y: $0.y + $1.y/n) }
        var varF: CGFloat = 0, a: CGFloat = 0, b: CGFloat = 0
        for i in from.indices {
            let fx = from[i].x - fMean.x, fy = from[i].y - fMean.y
            let tx = to[i].x - tMean.x, ty = to[i].y - tMean.y
            varF += fx*fx + fy*fy
            a += fx*tx + fy*ty        // dot
            b += fx*ty - fy*tx        // cross
        }
        guard varF > 1e-6 else { return nil }
        let scale = (a*a + b*b).squareRoot() / varF
        let cos = a / (varF * scale), sin = b / (varF * scale)
        // Map source point p to: scale*R*(p - fMean) + tMean
        var t = CGAffineTransform(a: scale*cos, b: scale*sin, c: -scale*sin, d: scale*cos,
                                  tx: 0, ty: 0)
        let shifted = CGPoint(x: fMean.x, y: fMean.y).applying(t)
        t.tx = tMean.x - shifted.x
        t.ty = tMean.y - shifted.y
        return t
    }

    public static func alignedFace(from image: CGImage, sourcePoints: FaceLandmarkPoints) -> CGImage? {
        guard let transform = similarityTransform(from: sourcePoints) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: outputSize, height: outputSize, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // CGContext origin is bottom-left; landmark math above is top-left. Flip Y.
        ctx.translateBy(x: 0, y: CGFloat(outputSize))
        ctx.scaleBy(x: 1, y: -1)
        ctx.concatenate(transform)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter FaceAlignerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/People/FaceAligner.swift Tests/TeststripCoreTests/FaceAlignerTests.swift
git commit -m "feat: FaceAligner — landmark similarity transform to canonical 112x112"
```

---

### Task 2: Model acquisition, conversion, download manifest, and bundle wiring

**Files:**
- Create: `script/convert_face_model.py` (one-time conversion recipe)
- Create: `sample-data/face-recognition-model.tsv`
- Create: `script/download_face_model.sh`
- Modify: `script/build_and_run.sh:34` region (copy model into `$APP_RESOURCES`)
- Modify: `.gitignore`

**Interfaces:**
- Produces: a Core ML model file at `sample-data/models/arcface-w600k-r50.mlpackage` (gitignored) and, at build, `dist/Teststrip.app/Contents/Resources/arcface-w600k-r50.mlpackage`. The model takes a 112×112 RGB image and outputs a 512-float vector.

- [ ] **Step 1: Write the conversion recipe `script/convert_face_model.py`**

Document, in an executable Python script with a module docstring stating when/why to run it, the conversion of InsightFace `w600k_r50.onnx` (from the `buffalo_l` pack) to Core ML:

```python
"""Convert InsightFace w600k_r50 ArcFace ONNX to Core ML.

When to use: one-time, to (re)generate the bundled face-recognition model.
Requires: pip install insightface onnx coremltools onnxruntime. The buffalo_l
pack ships w600k_r50.onnx (input 1x3x112x112, BGR, normalized (x-127.5)/128,
output 1x512). Emits arcface-w600k-r50.mlpackage with a 112x112 RGB image input.
"""
import coremltools as ct, numpy as np, onnx
# 1) Load w600k_r50.onnx (download via insightface model_zoo or the buffalo_l zip).
# 2) Convert with ct.convert(onnx_model, inputs=[ct.ImageType(name="input",
#      shape=(1,3,112,112), scale=1/128.0, bias=[-127.5/128]*3, color_layout=ct.colorlayout.BGR)]).
# 3) Save mlpackage; print the md5 + byte size for the manifest.
```
Keep it as the reproducible record; the implementer runs it locally to produce the artifact and its md5/size.

- [ ] **Step 2: Produce the `.mlpackage` and fill the manifest**

Run the conversion locally, host the resulting `.mlpackage` (zipped) at a stable URL you control, and write `sample-data/face-recognition-model.tsv`:

```
# filename	url	md5	size	source_url
arcface-w600k-r50.mlpackage.zip	<stable-url>	<md5>	<bytes>	https://github.com/deepinsight/insightface
```

- [ ] **Step 3: Write `script/download_face_model.sh`**

A wrapper that calls the existing `download_sample_photos.sh --manifest sample-data/face-recognition-model.tsv --destination sample-data/models`, then unzips the `.mlpackage.zip` in place. Include help text and checksum verification (the underlying script already verifies md5+size).

- [ ] **Step 4: Wire `build_and_run.sh` to bundle the model**

After the app bundle's `$APP_RESOURCES` is created, add:
```bash
FACE_MODEL="$ROOT_DIR/sample-data/models/arcface-w600k-r50.mlpackage"
if [[ -d "$FACE_MODEL" ]]; then
  /usr/bin/ditto "$FACE_MODEL" "$APP_RESOURCES/arcface-w600k-r50.mlpackage"
fi
```
(If the model is absent, the build still succeeds; face embedding will be disabled at runtime — see Task 3.)

- [ ] **Step 5: Gitignore the download destination**

Add to `.gitignore`:
```
sample-data/models/
```

- [ ] **Step 6: Verify download + bundle**

Run: `./script/download_face_model.sh && ls -d sample-data/models/arcface-w600k-r50.mlpackage`
Expected: the `.mlpackage` directory exists.

- [ ] **Step 7: Commit**

```bash
git add script/convert_face_model.py sample-data/face-recognition-model.tsv script/download_face_model.sh script/build_and_run.sh .gitignore
git commit -m "build: face-recognition model conversion recipe, download manifest, and bundle wiring"
```

---

### Task 3: FaceEmbeddingModel protocol + ArcFaceCoreMLModel

**Files:**
- Create: `Sources/TeststripCore/People/FaceEmbeddingModel.swift`
- Create: `Sources/TeststripCore/People/ArcFaceCoreMLModel.swift`
- Test: `Tests/TeststripCoreTests/ArcFaceCoreMLModelTests.swift`

**Interfaces:**
- Consumes: `FaceAligner` output (`CGImage` 112×112).
- Produces:
  - `protocol FaceEmbeddingModel { var provenance: ProviderProvenance { get }; func embedding(for alignedFace: CGImage) throws -> [Double] }`
  - `enum FaceEmbeddingModelError: Error { case modelUnavailable; case inferenceFailed }`
  - `final class ArcFaceCoreMLModel: FaceEmbeddingModel` with `init?(modelURL: URL)` (nil if the model can't load) and a convenience `static func bundled() -> ArcFaceCoreMLModel?` that looks for `arcface-w600k-r50.mlpackage` in `Bundle.main` (and the SwiftPM test bundle / a `TESTSTRIP_FACE_MODEL_PATH` env override for tests).

- [ ] **Step 1: Write the failing test (model-gated)**

```swift
import XCTest
import CoreGraphics
@testable import TeststripCore

final class ArcFaceCoreMLModelTests: XCTestCase {
    private func model() throws -> ArcFaceCoreMLModel {
        guard let m = ArcFaceCoreMLModel.bundled() else {
            throw XCTSkip("Face model not downloaded (run script/download_face_model.sh)")
        }
        return m
    }

    func testEmbeddingIs512DimAndL2Normalized() throws {
        let m = try model()
        // A solid gray 112x112 image is a valid input; we assert shape+norm, not identity.
        let ctx = CGContext(data: nil, width: 112, height: 112, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 112, height: 112))
        let img = ctx.makeImage()!
        let v = try m.embedding(for: img)
        XCTAssertEqual(v.count, 512)
        let norm = v.map { $0 * $0 }.reduce(0, +).squareRoot()
        XCTAssertEqual(norm, 1.0, accuracy: 1e-3)
    }

    func testProvenanceIsFaceRecognition() throws {
        let m = try model()
        XCTAssertEqual(m.provenance, ProviderProvenance(provider: "face-recognition", model: "arcface-w600k-r50", version: "1", settingsHash: "default"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ArcFaceCoreMLModelTests`
Expected: FAIL — types undefined (or SKIP if the model isn't downloaded; download it first so the test truly exercises the model).

- [ ] **Step 3: Implement the protocol + Core ML model**

Load the `.mlpackage` with `MLModel(contentsOf:)` (compile with `MLModel.compileModel(at:)` if a raw `.mlpackage`). Build the input as a 112×112 `CVPixelBuffer` from the `CGImage`. Run prediction, read the 512-length `MLMultiArray` output, convert to `[Double]`, and **L2-normalize** before returning (do not assume the model already normalizes). Map load failure to `init?` → nil and inference failure to `FaceEmbeddingModelError.inferenceFailed`.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter ArcFaceCoreMLModelTests`
Expected: PASS (with the model downloaded).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/People/FaceEmbeddingModel.swift Sources/TeststripCore/People/ArcFaceCoreMLModel.swift Tests/TeststripCoreTests/ArcFaceCoreMLModelTests.swift
git commit -m "feat: ArcFace Core ML face-embedding model behind FaceEmbeddingModel protocol"
```

---

### Task 4: FaceRecognitionEmbedder + integrate into evaluateWithFaces

**Files:**
- Create: `Sources/TeststripCore/People/FaceRecognitionEmbedder.swift`
- Modify: `Sources/TeststripCore/Evaluation/AppleVisionEvaluationProvider.swift` (`analyze` face block ~lines 250-280; `evaluateWithFaces` ~line 196)
- Test: `Tests/TeststripCoreTests/FaceRecognitionEmbedderTests.swift`

**Interfaces:**
- Consumes: `FaceAligner`, `FaceEmbeddingModel`, `VNDetectFaceLandmarksRequest`.
- Produces: `FaceRecognitionEmbedder(model: FaceEmbeddingModel)` with `func faceObservations(in image: CGImage) throws -> [AppleVisionFaceObservation]`, populating `featurePrintVector` with the ArcFace embedding. Face observations persisted by `evaluateWithFaces` now carry `provenance = model.provenance` (face-recognition), distinct from the whole-image analysis provenance.

- [ ] **Step 1: Write the failing test with a stub model**

```swift
import XCTest
import CoreGraphics
@testable import TeststripCore

private struct StubModel: FaceEmbeddingModel {
    let provenance = ProviderProvenance(provider: "face-recognition", model: "stub", version: "1", settingsHash: "default")
    func embedding(for alignedFace: CGImage) throws -> [Double] {
        var v = [Double](repeating: 0, count: 512); v[0] = 1; return v   // unit vector
    }
}

final class FaceRecognitionEmbedderTests: XCTestCase {
    func testProducesOneNormalizedObservationPerDetectedFace() throws {
        guard let url = Bundle.faceCorpusImageURL() else { throw XCTSkip("face corpus not downloaded") }
        let cg = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let embedder = FaceRecognitionEmbedder(model: StubModel())
        let observations = try embedder.faceObservations(in: cg)
        XCTAssertGreaterThanOrEqual(observations.count, 1)
        for o in observations { XCTAssertEqual(o.featurePrintVector.count, 512) }
    }
}
```
(Add a small `Bundle.faceCorpusImageURL()` test helper in `TestSupport.swift` that returns the first jpg under `sample-data/photos/faces`, or nil.)

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FaceRecognitionEmbedderTests`
Expected: FAIL — `FaceRecognitionEmbedder` undefined.

- [ ] **Step 3: Implement the embedder**

For the input image: run `VNDetectFaceRectanglesRequest` then `VNDetectFaceLandmarksRequest`; for each face with the five required landmark points (`leftEye`, `rightEye`, `nose`, `outerLips`/mouth corners) converted from Vision normalized coordinates to image pixels, call `FaceAligner.alignedFace`, then `model.embedding(for:)`. Build `AppleVisionFaceObservation(boundingBox:captureQuality:featurePrintVector:)`. Skip faces missing landmarks or that fail inference (log, continue).

- [ ] **Step 4: Integrate into `evaluateWithFaces`**

In `AppleVisionEvaluationProvider`, replace the `VNGenerateImageFeaturePrint`-per-face block in `analyze` with the new embedder when a model is available; persist face observations under `ArcFaceCoreMLModel.bundled()?.provenance ?? <fallback>`. If the model is unavailable (`bundled()` returns nil), log one line and produce no face embeddings (detection/quality/other signals continue unchanged). The whole-image `imageFeaturePrintVector` analysis is untouched.

- [ ] **Step 5: Run to verify pass + full suite**

Run: `swift test --filter FaceRecognitionEmbedderTests` then `swift test`
Expected: PASS; full suite 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripCore/People/FaceRecognitionEmbedder.swift Sources/TeststripCore/Evaluation/AppleVisionEvaluationProvider.swift Tests/TeststripCoreTests/FaceRecognitionEmbedderTests.swift Tests/TeststripCoreTests/TestSupport.swift
git commit -m "feat: FaceRecognitionEmbedder wires aligned ArcFace embeddings into evaluateWithFaces"
```

---

### Task 5: Retune FaceSuggestionBuilder thresholds for the ArcFace scale

**Files:**
- Modify: `Sources/TeststripCore/People/FaceSuggestionBuilder.swift:47-49`
- Test: `Tests/TeststripCoreTests/FaceIdentityClusteringTests.swift`

**Interfaces:**
- Consumes: `FaceEmbedding` (unchanged), `FaceSuggestionBuilder.suggestions(...)` (unchanged signature).
- Produces: new `defaultMaximumClusterDistance` / `defaultMaximumMatchDistance` calibrated to L2-normalized ArcFace embeddings. For unit-normalized vectors, Euclidean distance d relates to cosine similarity s by d = √(2−2s); same-person ArcFace cosine ≳ 0.4 → d ≲ 1.10, different-person cosine ≲ 0.2 → d ≳ 1.26. Choose `defaultMaximumClusterDistance = 1.10`, `defaultMaximumMatchDistance = 1.10` (re-derive precisely from Task 6's measured corpus distances and update if needed).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import TeststripCore

final class FaceIdentityClusteringTests: XCTestCase {
    private func unit(_ seed: [Double]) -> [Double] {
        let n = seed.map { $0*$0 }.reduce(0,+).squareRoot(); return seed.map { $0/n }
    }
    func testSamePersonClustersDifferentPersonDoesNot() {
        // Two "person A" vectors ~cos 0.5 apart (d≈1.0), person B ~cos 0.0 (d≈1.41 from A).
        let a1 = unit([1,0,0]); let a2 = unit([0.7,0.7,0]); let b = unit([0,0,1])
        let faces = [FaceEmbedding(faceID: FaceID(rawValue: "a1"), vector: a1),
                     FaceEmbedding(faceID: FaceID(rawValue: "a2"), vector: a2),
                     FaceEmbedding(faceID: FaceID(rawValue: "b"), vector: b)]
        let s = FaceSuggestionBuilder().suggestions(unassignedFaces: faces, confirmedPeople: [:])
        // a1,a2 cluster together; b is a singleton and dropped by minimum cluster size.
        XCTAssertEqual(s.clusters.count, 1)
        XCTAssertEqual(Set(s.clusters[0].faceIDs.map(\.rawValue)), ["a1", "a2"])
    }
}
```
(Confirm the exact `suggestions(...)` argument labels against the current source and match them.)

- [ ] **Step 2: Run to verify it fails at the old thresholds**

Run: `swift test --filter FaceIdentityClusteringTests`
Expected: FAIL — at 0.85 the d≈1.0 same-person pair does not cluster.

- [ ] **Step 3: Update the thresholds**

Set `defaultMaximumClusterDistance = 1.10` and `defaultMaximumMatchDistance = 1.10`, with a comment documenting the ArcFace cosine↔Euclidean relation and that the values are re-derived from the astronaut corpus in Task 6.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter FaceIdentityClusteringTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/People/FaceSuggestionBuilder.swift Tests/TeststripCoreTests/FaceIdentityClusteringTests.swift
git commit -m "feat: calibrate face clustering thresholds to L2-normalized ArcFace scale"
```

---

### Task 6: Acceptance — the astronaut corpus clusters by identity

**Files:**
- Modify: `Tests/TeststripCoreTests/FaceCorpusGroupingTests.swift`

**Interfaces:**
- Consumes: `FaceRecognitionEmbedder(model: ArcFaceCoreMLModel.bundled())`, `FaceSuggestionBuilder`, the downloaded faces corpus.

- [ ] **Step 1: Write the acceptance test (model + corpus gated)**

```swift
func testAstronautCorpusClustersByIdentity() throws {
    guard let model = ArcFaceCoreMLModel.bundled() else { throw XCTSkip("face model not downloaded") }
    guard let dir = Bundle.faceCorpusDirectory() else { throw XCTSkip("face corpus not downloaded") }
    let embedder = FaceRecognitionEmbedder(model: model)
    var faces: [FaceEmbedding] = []
    var personByFace: [String: String] = [:]   // faceID -> person, from filename prefix
    for url in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension == "jpg" {
        let cg = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }!
        for (i, o) in try embedder.faceObservations(in: cg).enumerated() {
            let id = "\(url.lastPathComponent)#\(i)"
            faces.append(FaceEmbedding(faceID: FaceID(rawValue: id), vector: o.featurePrintVector))
            personByFace[id] = url.lastPathComponent.contains("glenn") ? "glenn"
                : url.lastPathComponent.contains("ride") ? "ride"
                : url.lastPathComponent.contains("armstrong") ? "armstrong" : "aldrin"
        }
    }
    let clusters = FaceSuggestionBuilder().suggestions(unassignedFaces: faces, confirmedPeople: [:]).clusters
    // No cluster mixes two different people.
    for c in clusters {
        let people = Set(c.faceIDs.compactMap { personByFace[$0.rawValue] })
        XCTAssertEqual(people.count, 1, "cluster mixes people: \(people)")
    }
    // Glenn and Ride each form a multi-face cluster.
    let glennClustered = clusters.contains { c in c.faceIDs.allSatisfy { personByFace[$0.rawValue] == "glenn" } && c.faceIDs.count >= 2 }
    let rideClustered = clusters.contains { c in c.faceIDs.allSatisfy { personByFace[$0.rawValue] == "ride" } && c.faceIDs.count >= 2 }
    XCTAssertTrue(glennClustered, "Glenn's faces did not cluster")
    XCTAssertTrue(rideClustered, "Ride's faces did not cluster")
}
```

- [ ] **Step 2: Run it**

Run: `./script/download_face_model.sh && ./script/download_sample_photos.sh --manifest sample-data/faces.tsv --destination sample-data/photos/faces && swift test --filter FaceCorpusGroupingTests`
Expected: PASS. If it fails on the mixing assertion, measure the real same/different-person distances (print them), re-derive the Task 5 thresholds to the tightest value that keeps Aldrin out of Glenn while keeping Glenn/Ride pairs together, update Task 5's constants, and re-run. If no single threshold separates them, STOP and report — that means the model/alignment is wrong, not the threshold.

- [ ] **Step 3: Commit**

```bash
git add Tests/TeststripCoreTests/FaceCorpusGroupingTests.swift Sources/TeststripCore/People/FaceSuggestionBuilder.swift
git commit -m "test: astronaut corpus clusters by identity with the ArcFace embedding"
```

---

### Task 7: E2E scenario cards

**Files:**
- Create: `test/scenarios/people-cluster-by-identity.md`
- Modify: `test/scenarios/people-name-face-group-happy-path.md`

**Interfaces:** none (documentation/scenario cards).

- [ ] **Step 1: Write the identity-clustering scenario card**

Author `people-cluster-by-identity.md` following the existing card format (see `test/scenarios/README.md`), with the falsification lines copied verbatim from the spec's "E2E scenario cards" table:
- **Falsification:** two confirmed-different people appear in one suggested group, OR one person's faces split across multiple un-mergeable groups, OR the astronaut corpus still merges Aldrin into a Glenn group.
Pre-state: `./script/download_face_model.sh` then `./script/build_and_run.sh --faces`; drive with `ax_drive.sh`; ground-truth via `people`/`person_faces`/`person_assets` and the clustering result.

- [ ] **Step 2: Update the happy-path card**

Update `people-name-face-group-happy-path.md` to note grouping now uses the ArcFace identity model (not feature prints) and that suggestions should be identity-coherent; keep its confirm-before-write assertions.

- [ ] **Step 3: Commit**

```bash
git add test/scenarios/people-cluster-by-identity.md test/scenarios/people-name-face-group-happy-path.md
git commit -m "test: e2e scenario cards for identity-based face clustering"
```

---

## Self-Review Notes

- **Spec coverage:** FaceAligner (Task 1), model+delivery (Task 2), FaceEmbeddingModel/ArcFace (Task 3), FaceRecognitionEmbedder + evaluateWithFaces integration + new provenance (Task 4), clustering retune (Task 5), acceptance/astronaut corpus (Task 6), scenario cards incl. both spec table rows (Task 7). Error handling (model missing → face embedding disabled, others continue) is in Task 4 Step 4. Migration (new provenance, recompute via Evaluate) is inherent in Task 4.
- **Model realism:** Task 2 is the genuine risk — it depends on an external conversion toolchain and a stable host for the artifact; everything downstream is gated on `bundled()` / the corpus so the suite stays green when the model is absent, and the acceptance test is the true gate.
- **Type consistency:** `FaceLandmarkPoints`, `FaceAligner.canonicalPoints/similarityTransform/alignedFace`, `FaceEmbeddingModel.embedding(for:)/provenance`, `ArcFaceCoreMLModel.bundled()`, `FaceRecognitionEmbedder.faceObservations(in:)`, and `ProviderProvenance(provider:"face-recognition", model:"arcface-w600k-r50", version:"1")` are used consistently across tasks. Confirm `FaceSuggestionBuilder.suggestions(...)` argument labels against the live source in Task 5.
