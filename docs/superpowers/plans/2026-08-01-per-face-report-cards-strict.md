# Per-Face Report Cards (SP-B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every detected face on a culling frame a scannable four-signal report card (eyes, sharpness, facing, light) plus a traffic-light grade, and roll those grades up to a dot on each burst-rail thumb so "which frame has no ruined face" is answerable without visiting frames.

**Architecture:** One pure Core analyzer (`FaceReportAnalyzer`) turns the preview `CGImage` plus the CIDetector detections the close-ups pass already produces into one `FaceReport` per face. One app-layer `FaceReportStore` caches `[AssetID: FrameFaceReport]` keyed on the preview-cache generation and sweeps the current stack's frames off the main actor with plain structured concurrency. Two surfaces read the store: the close-ups panel (per-face chips, per-tile corner dot, header roll-up) and the burst rail (one roll-up dot per thumb). Nothing is persisted, no worker involvement, no schema change.

**Tech Stack:** Swift 6 / SwiftPM (`swift-tools-version: 6.0`, `.macOS(.v14)`), SwiftUI + AppKit, CoreImage `CIDetector` (existing detections), Vision `VNDetectFaceRectanglesRequest` (yaw/pitch only), CoreGraphics pixel sampling via the existing `PreviewPixelMetrics`, XCTest.

## Global Constraints

- **Nothing persists.** No new `EvaluationKind`, no catalog write, no `.xmp` write, no worker/protocol/schema change. Per-face signals live in memory for the session only. (Spec "Out of scope"; parent spec's explicit exclusions.)
- **Never a fake score, never a fake green.** A signal that could not be measured is `nil` and renders an empty ring with a "no read" hover — it never contributes to a grade. A failed Vision request leaves `facing == nil`.
- **Absence means "nothing known", never "known good".** No rail dot while a frame is uncomputed or has no faces.
- **Prominence-weighted roll-up.** Red requires BOTH a red-grade signal AND `prominence >= FaceReportGrading.prominenceFloor`; a below-floor face grades at worst yellow.
- **Chip row is quality signals only, always all four, in fixed order:** eyes, sharpness, facing, light. Smile moves to hover/AX.
- **Threshold constants live in one place with a WHY comment** (same discipline as `tooCloseToCallMargin`, `LibraryGridView.swift:6659`).
- **`SignalGlyphView` (`Sources/TeststripApp/SignalGlyphView.swift`) is untouched.** The chip view is a sibling component, not an edit to it.
- **No `shutOK(context)` eye-state cases** — no context provider exists; never fake it.
- **No change to the composite quality read or verdict math**, the reads card, the run strip, or compare surfaces.
- **Tests run with `swift test`.** Baseline before this work: 2281 passing / 15 skipped. Coverage must never go down: any deleted test must be superseded by a named replacement in the same commit.
- **Work on a WIP branch**, not `main`: `git checkout -b feat/per-face-report-cards` before Task 1.
- **Interactive UI verification runs in the Tart VM only**, via `script/vm_scenario_run.sh` — never on the host console. Building and `swift test` stay on the host.

---

### Task 1: Core — `FaceReport` and its grading rule

**Files:**
- Create: `Sources/TeststripCore/Evaluation/FaceReport.swift`
- Test: `Tests/TeststripCoreTests/FaceReportGradingTests.swift`

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - `public enum FaceReportGrade: Int, Sendable, Comparable, CaseIterable { case green = 0, yellow = 1, red = 2 }`
  - `public enum FaceReportGrading` with `public static let prominenceFloor: Double`, `redSignalCeiling: Double`, `greenSignalFloor: Double`, and
    `public static func grade(eyesOpen: Bool, sharpness: Double?, light: Double?, facing: Double?, prominence: Double) -> FaceReportGrade`
  - `public struct FaceReport: Equatable, Sendable` with stored `normalizedBounds: CGRect`, `eyesOpen: Bool`, `hasSmile: Bool`, `sharpness: Double?`, `light: Double?`, `facing: Double?`, `prominence: Double`; computed `eyesScore: Double` and `grade: FaceReportGrade`; memberwise `public init(normalizedBounds:eyesOpen:hasSmile:sharpness:light:facing:prominence:)`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripCoreTests/FaceReportGradingTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import TeststripCore

final class FaceReportGradingTests: XCTestCase {
    func testEveryCleanSignalGradesGreen() {
        XCTAssertEqual(
            FaceReportGrading.grade(eyesOpen: true, sharpness: 0.8, light: 0.7, facing: 0.9, prominence: 0.2),
            .green
        )
    }

    func testMiddlingSignalGradesYellow() {
        // 0.45 sits between redSignalCeiling (0.35) and greenSignalFloor (0.6).
        XCTAssertEqual(
            FaceReportGrading.grade(eyesOpen: true, sharpness: 0.45, light: 0.9, facing: 0.9, prominence: 0.2),
            .yellow
        )
    }

    func testRedSignalOnAProminentFaceGradesRed() {
        XCTAssertEqual(
            FaceReportGrading.grade(eyesOpen: true, sharpness: 0.1, light: 0.9, facing: 0.9, prominence: 0.2),
            .red
        )
    }

    // The prominence-weighted roll-up's whole point: a bystander can flag
    // yellow but must never grade a frame red.
    func testRedSignalBelowTheProminenceFloorCapsAtYellow() {
        XCTAssertEqual(
            FaceReportGrading.grade(eyesOpen: true, sharpness: 0.1, light: 0.9, facing: 0.9, prominence: 0.001),
            .yellow
        )
    }

    func testClosedEyesAreARedGradeSignalOnAProminentFace() {
        XCTAssertEqual(
            FaceReportGrading.grade(eyesOpen: false, sharpness: 0.9, light: 0.9, facing: 0.9, prominence: 0.2),
            .red
        )
    }

    func testUnscoredSignalsNeverContributeAGrade() {
        // nil facing/sharpness/light must not read as 0 — that would fake a red.
        XCTAssertEqual(
            FaceReportGrading.grade(eyesOpen: true, sharpness: nil, light: nil, facing: nil, prominence: 0.2),
            .green
        )
    }

    func testFaceReportDerivesItsGradeFromItsOwnScores() {
        let report = FaceReport(
            normalizedBounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            eyesOpen: true,
            hasSmile: false,
            sharpness: 0.1,
            light: 0.9,
            facing: 0.9,
            prominence: 0.04
        )

        XCTAssertEqual(report.grade, .red)
        XCTAssertEqual(report.eyesScore, 1.0)
    }

    func testGradesOrderGreenBeforeYellowBeforeRed() {
        XCTAssertEqual([FaceReportGrade.yellow, .green, .red].max(), .red)
        XCTAssertEqual([FaceReportGrade.yellow, .green].max(), .yellow)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FaceReportGradingTests 2>&1 | tail -20`
Expected: FAIL — compile error `cannot find 'FaceReportGrading' in scope` (and `cannot find 'FaceReport' in scope`).

- [ ] **Step 3: Write the implementation**

Create `Sources/TeststripCore/Evaluation/FaceReport.swift`:

```swift
import CoreGraphics
import Foundation

/// A face's traffic-light verdict. Ordered worst-last so a frame's roll-up is
/// just `reports.map(\.grade).max()`.
public enum FaceReportGrade: Int, Sendable, Comparable, CaseIterable {
    case green = 0
    case yellow = 1
    case red = 2

    public static func < (lhs: FaceReportGrade, rhs: FaceReportGrade) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The one home for the report card's thresholds — same discipline as
/// `tooCloseToCallMargin`: a number that decides what a photographer sees
/// gets a documented reason, not a magic literal at the call site.
public enum FaceReportGrading {
    /// A face smaller than this share of the frame is a bystander, not the
    /// subject. Below the floor a face can flag yellow but never grades a
    /// frame red — the rail dot answers "is anyone I care about ruined",
    /// not "is any face imperfect". 1.5% of frame area is roughly a head at
    /// an eighth of the frame's short edge, the size where a viewer stops
    /// reading expression at normal viewing distance.
    public static let prominenceFloor = 0.015

    /// Below this a signal is visibly wrong at 100% — a soft face, a blown
    /// or crushed face, a head turned most of the way away. This is the
    /// only band that can produce a red.
    public static let redSignalCeiling = 0.35

    /// At or above this every measured signal reads clean. Between the two
    /// constants the face is worth a second look but is not ruined.
    public static let greenSignalFloor = 0.6

    /// The face's grade is governed by its *worst measured* signal: one
    /// ruined signal ruins the face, and averaging would let a blown
    /// exposure hide behind a sharp, frontal, open-eyed read. Signals that
    /// could not be measured are absent from the vote rather than counted
    /// as zero — never a fake score, never a fake green.
    public static func grade(
        eyesOpen: Bool,
        sharpness: Double?,
        light: Double?,
        facing: Double?,
        prominence: Double
    ) -> FaceReportGrade {
        let measured = [eyesOpen ? 1.0 : 0.0] + [sharpness, light, facing].compactMap { $0 }
        guard let worst = measured.min() else { return .green }
        if worst < redSignalCeiling {
            return prominence >= prominenceFloor ? .red : .yellow
        }
        if worst < greenSignalFloor {
            return .yellow
        }
        return .green
    }
}

/// One face's report card for the frame currently under review. Display-only
/// and per-session: nothing here is persisted, mirrored to a sidecar, or fed
/// into the composite quality read.
public struct FaceReport: Equatable, Sendable {
    /// Normalized to [0, 1] with a top-left origin, matching
    /// `DetectedFaceExpression.normalizedBounds`.
    public var normalizedBounds: CGRect
    public var eyesOpen: Bool
    public var hasSmile: Bool
    /// nil when the face crop was too small to measure honestly.
    public var sharpness: Double?
    /// nil when the face crop was too small to measure honestly.
    public var light: Double?
    /// nil when no Vision observation matched this face, or the Vision
    /// request failed — the chip renders an empty ring, never a fake score.
    public var facing: Double?
    /// Face area over frame area, from the normalized bounds.
    public var prominence: Double

    public init(
        normalizedBounds: CGRect,
        eyesOpen: Bool,
        hasSmile: Bool,
        sharpness: Double?,
        light: Double?,
        facing: Double?,
        prominence: Double
    ) {
        self.normalizedBounds = normalizedBounds
        self.eyesOpen = eyesOpen
        self.hasSmile = hasSmile
        self.sharpness = sharpness
        self.light = light
        self.facing = facing
        self.prominence = prominence
    }

    /// Eyes as a 0-1 signal so grading and the chip row treat all four
    /// signals alike.
    public var eyesScore: Double { eyesOpen ? 1.0 : 0.0 }

    /// Computed, never stored: a report cannot carry a grade that disagrees
    /// with its own scores.
    public var grade: FaceReportGrade {
        FaceReportGrading.grade(
            eyesOpen: eyesOpen,
            sharpness: sharpness,
            light: light,
            facing: facing,
            prominence: prominence
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FaceReportGradingTests 2>&1 | tail -5`
Expected: PASS — `Executed 8 tests, with 0 failures`.

- [ ] **Step 5: Run the full suite**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2289 tests, with 0 failures` (2281 baseline + 8 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripCore/Evaluation/FaceReport.swift Tests/TeststripCoreTests/FaceReportGradingTests.swift
git commit -m "feat: per-face report card model and prominence-weighted grading"
```

---

### Task 2: Core — facing score and Vision↔CIDetector box matching

**Files:**
- Create: `Sources/TeststripCore/Evaluation/FaceOrientation.swift`
- Test: `Tests/TeststripCoreTests/FaceFacingScoreTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1 (independent pure math).
- Produces:
  - `public struct FaceOrientationObservation: Equatable, Sendable` with `normalizedBounds: CGRect` (top-left origin), `yawRadians: Double?`, `pitchRadians: Double?`, memberwise `public init(normalizedBounds:yawRadians:pitchRadians:)`.
  - `public protocol FaceOrientationDetecting: Sendable { func orientations(in image: CGImage) throws -> [FaceOrientationObservation] }`
  - `public enum FaceFacingScore` with `public static let zeroAtRadians: Double`, `public static let minimumBoxOverlap: Double`,
    `public static func score(yawRadians: Double?, pitchRadians: Double?) -> Double?`,
    `public static func matched(detectionBounds: [CGRect], orientations: [FaceOrientationObservation]) -> [Double?]`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripCoreTests/FaceFacingScoreTests.swift`:

```swift
import CoreGraphics
import Foundation
import XCTest
@testable import TeststripCore

final class FaceFacingScoreTests: XCTestCase {
    private static func degrees(_ value: Double) -> Double { value * .pi / 180.0 }

    func testFullFrontalScoresOne() {
        XCTAssertEqual(FaceFacingScore.score(yawRadians: 0, pitchRadians: 0), 1.0)
    }

    func testHalfWayToTheZeroAngleScoresHalf() {
        // zeroAtRadians is 60 degrees, so a 30-degree yaw is exactly half.
        let score = try? XCTUnwrap(FaceFacingScore.score(yawRadians: Self.degrees(30), pitchRadians: 0))
        XCTAssertEqual(score ?? 0, 0.5, accuracy: 0.0001)
    }

    func testDirectionOfTurnDoesNotMatter() {
        XCTAssertEqual(
            FaceFacingScore.score(yawRadians: Self.degrees(-30), pitchRadians: 0),
            FaceFacingScore.score(yawRadians: Self.degrees(30), pitchRadians: 0)
        )
    }

    func testAtOrBeyondTheZeroAngleScoresZero() {
        XCTAssertEqual(FaceFacingScore.score(yawRadians: Self.degrees(60), pitchRadians: 0), 0.0)
        XCTAssertEqual(FaceFacingScore.score(yawRadians: Self.degrees(89), pitchRadians: 0), 0.0)
    }

    func testTheWorseAxisGovernsRatherThanABlend() {
        let score = try? XCTUnwrap(FaceFacingScore.score(yawRadians: 0, pitchRadians: Self.degrees(-30)))
        XCTAssertEqual(score ?? 0, 0.5, accuracy: 0.0001)
    }

    func testAMissingAxisIsTreatedAsLevel() {
        XCTAssertEqual(FaceFacingScore.score(yawRadians: 0, pitchRadians: nil), 1.0)
    }

    func testBothAxesMissingIsUnscored() {
        XCTAssertNil(FaceFacingScore.score(yawRadians: nil, pitchRadians: nil))
    }

    func testGreatestOverlapObservationWins() {
        let detection = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let poorOverlap = FaceOrientationObservation(
            normalizedBounds: CGRect(x: 0.45, y: 0.45, width: 0.2, height: 0.2),
            yawRadians: Self.degrees(60),
            pitchRadians: 0
        )
        let exactOverlap = FaceOrientationObservation(
            normalizedBounds: detection,
            yawRadians: 0,
            pitchRadians: 0
        )

        let facing = FaceFacingScore.matched(
            detectionBounds: [detection],
            orientations: [poorOverlap, exactOverlap]
        )

        XCTAssertEqual(facing, [1.0])
    }

    func testADetectionWithNoOverlappingObservationIsUnscored() {
        let facing = FaceFacingScore.matched(
            detectionBounds: [CGRect(x: 0.0, y: 0.0, width: 0.1, height: 0.1)],
            orientations: [
                FaceOrientationObservation(
                    normalizedBounds: CGRect(x: 0.8, y: 0.8, width: 0.1, height: 0.1),
                    yawRadians: 0,
                    pitchRadians: 0
                )
            ]
        )

        XCTAssertEqual(facing, [nil])
    }

    func testOneObservationIsClaimedByOnlyOneDetection() {
        let close = CGRect(x: 0.40, y: 0.40, width: 0.20, height: 0.20)
        let overlapping = CGRect(x: 0.42, y: 0.42, width: 0.20, height: 0.20)
        let observation = FaceOrientationObservation(
            normalizedBounds: close,
            yawRadians: 0,
            pitchRadians: 0
        )

        let facing = FaceFacingScore.matched(
            detectionBounds: [overlapping, close],
            orientations: [observation]
        )

        // The exact-overlap detection wins the single observation; the other
        // is left unscored rather than borrowing a stranger's angles.
        XCTAssertEqual(facing, [nil, 1.0])
    }

    func testMatchedReturnsOneEntryPerDetectionInOrder() {
        let facing = FaceFacingScore.matched(detectionBounds: [], orientations: [])
        XCTAssertEqual(facing, [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FaceFacingScoreTests 2>&1 | tail -20`
Expected: FAIL — compile error `cannot find 'FaceFacingScore' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/TeststripCore/Evaluation/FaceOrientation.swift`:

```swift
import CoreGraphics
import Foundation

/// A head-pose read for one face, in the same normalized top-left coordinate
/// space `DetectedFaceExpression` uses, so the two detectors' boxes can be
/// compared directly.
public struct FaceOrientationObservation: Equatable, Sendable {
    public var normalizedBounds: CGRect
    /// Radians; nil when the detector did not compute this axis.
    public var yawRadians: Double?
    /// Radians; nil when the detector did not compute this axis.
    public var pitchRadians: Double?

    public init(normalizedBounds: CGRect, yawRadians: Double?, pitchRadians: Double?) {
        self.normalizedBounds = normalizedBounds
        self.yawRadians = yawRadians
        self.pitchRadians = pitchRadians
    }
}

/// Head-pose source for the report card's facing signal. A protocol so the
/// analyzer can be tested without Vision, mirroring `FaceExpressionAnalyzing`.
public protocol FaceOrientationDetecting: Sendable {
    func orientations(in image: CGImage) throws -> [FaceOrientationObservation]
}

public enum FaceFacingScore {
    /// Facing decays linearly from 1 at full frontal to 0 at 60 degrees off
    /// axis. Vision reports yaw and pitch in [-Pi/2, Pi/2]; by 60 degrees the
    /// far eye and half the expression are gone, so anything past it is a
    /// profile and scores the same zero.
    public static let zeroAtRadians = Double.pi / 3

    /// Two detectors' boxes for the same face overlap heavily. Below this
    /// intersection-over-union they are different faces, and the CIDetector
    /// face is left unscored rather than borrowing a stranger's angles.
    public static let minimumBoxOverlap = 0.3

    /// The worse axis governs: a head turned fully sideways is unreadable
    /// however level it is, so blending yaw and pitch would let a profile
    /// hide behind a level head. A missing axis contributes no evidence of a
    /// turn; both axes missing means there is no read at all.
    public static func score(yawRadians: Double?, pitchRadians: Double?) -> Double? {
        guard yawRadians != nil || pitchRadians != nil else { return nil }
        let worstAngle = max(abs(yawRadians ?? 0), abs(pitchRadians ?? 0))
        return min(max(1.0 - worstAngle / zeroAtRadians, 0.0), 1.0)
    }

    /// One facing score per detection, in detection order. Assignment is
    /// greedy on overlap so a single Vision observation is claimed by exactly
    /// one CIDetector face; everything left over stays unscored.
    public static func matched(
        detectionBounds: [CGRect],
        orientations: [FaceOrientationObservation]
    ) -> [Double?] {
        var facing = [Double?](repeating: nil, count: detectionBounds.count)
        var candidates: [(detectionIndex: Int, orientationIndex: Int, overlap: Double)] = []
        for (detectionIndex, bounds) in detectionBounds.enumerated() {
            for (orientationIndex, orientation) in orientations.enumerated() {
                let overlap = intersectionOverUnion(bounds, orientation.normalizedBounds)
                guard overlap >= minimumBoxOverlap else { continue }
                candidates.append((detectionIndex, orientationIndex, overlap))
            }
        }
        candidates.sort { lhs, rhs in
            if lhs.overlap != rhs.overlap { return lhs.overlap > rhs.overlap }
            if lhs.detectionIndex != rhs.detectionIndex { return lhs.detectionIndex < rhs.detectionIndex }
            return lhs.orientationIndex < rhs.orientationIndex
        }
        var claimedDetections = Set<Int>()
        var claimedOrientations = Set<Int>()
        for candidate in candidates {
            guard !claimedDetections.contains(candidate.detectionIndex),
                  !claimedOrientations.contains(candidate.orientationIndex) else {
                continue
            }
            claimedDetections.insert(candidate.detectionIndex)
            claimedOrientations.insert(candidate.orientationIndex)
            let orientation = orientations[candidate.orientationIndex]
            facing[candidate.detectionIndex] = score(
                yawRadians: orientation.yawRadians,
                pitchRadians: orientation.pitchRadians
            )
        }
        return facing
    }

    static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
        let intersectionArea = Double(intersection.width * intersection.height)
        let unionArea = Double(lhs.width * lhs.height) + Double(rhs.width * rhs.height) - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FaceFacingScoreTests 2>&1 | tail -5`
Expected: PASS — `Executed 11 tests, with 0 failures`.

- [ ] **Step 5: Run the full suite**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2300 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripCore/Evaluation/FaceOrientation.swift Tests/TeststripCoreTests/FaceFacingScoreTests.swift
git commit -m "feat: facing score from head pose and Vision-to-CIDetector box matching"
```

---

### Task 3: Core — `FaceReportAnalyzer` and the Vision orientation detector

**Files:**
- Create: `Sources/TeststripCore/Evaluation/FaceReportAnalyzer.swift`
- Modify: `Sources/TeststripCore/Evaluation/PreviewPixelMetrics.swift` (add `meanLuminance` and `balancedExposure`)
- Modify: `Sources/TeststripCore/Evaluation/LocalImageMetricsEvaluationProvider.swift:107-120` and `:152-162` (call the shared helpers instead of its private copies)
- Modify: `Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift:33-35` (add `bothEyesShut`)
- Test: `Tests/TeststripCoreTests/FaceReportAnalyzerTests.swift`

**Interfaces:**
- Consumes: `FaceReport(normalizedBounds:eyesOpen:hasSmile:sharpness:light:facing:prominence:)` (Task 1); `FaceOrientationObservation`, `FaceOrientationDetecting`, `FaceFacingScore.matched(detectionBounds:orientations:)` (Task 2); existing `DetectedFaceExpression` and `PreviewPixelMetrics`.
- Produces:
  - `public extension DetectedFaceExpression { var bothEyesShut: Bool }`
  - `PreviewPixelMetrics.meanLuminance(in:width:height:) -> Double` and `PreviewPixelMetrics.balancedExposure(meanLuminance:) -> Double` (both `static`, module-internal like the rest of that enum)
  - `public struct FaceReportAnalyzer: Sendable` with `public static let cropSampleSize: Int`, `public static let minimumCropPixels: Int`, `public init(orientationDetector: any FaceOrientationDetecting = VisionFaceOrientationDetector())`, and `public func reports(in image: CGImage, detections: [DetectedFaceExpression]) -> [FaceReport]`
  - `public struct VisionFaceOrientationDetector: FaceOrientationDetecting` with `public init()`

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripCoreTests/FaceReportAnalyzerTests.swift`:

```swift
import CoreGraphics
import Foundation
import XCTest
@testable import TeststripCore

final class FaceReportAnalyzerTests: XCTestCase {
    // MARK: - Fixtures

    /// Flat mid-gray everywhere, with an optional checkerboard patch (a
    /// stand-in for real face detail) and an optional flat-black patch (a
    /// stand-in for a crushed face).
    private func makeImage(
        width: Int = 400,
        height: Int = 400,
        checkerboard: CGRect? = nil,
        black: CGRect? = nil
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TeststripError.io("could not create face report test bitmap")
        }
        context.setFillColor(CGColor(gray: 0.5, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let black {
            context.setFillColor(CGColor(gray: 0.0, alpha: 1.0))
            context.fill(black)
        }
        if let checkerboard {
            let cell = 4
            for y in stride(from: 0, to: Int(checkerboard.height), by: cell) {
                for x in stride(from: 0, to: Int(checkerboard.width), by: cell) {
                    let isLight = ((x / cell) + (y / cell)).isMultiple(of: 2)
                    context.setFillColor(CGColor(gray: isLight ? 1.0 : 0.0, alpha: 1.0))
                    context.fill(CGRect(
                        x: checkerboard.minX + Double(x),
                        y: checkerboard.minY + Double(y),
                        width: Double(cell),
                        height: Double(cell)
                    ))
                }
            }
        }
        guard let image = context.makeImage() else {
            throw TeststripError.io("could not render face report test bitmap")
        }
        return image
    }

    private func face(
        x: Double = 0.0,
        y: Double = 0.0,
        side: Double = 0.5,
        hasSmile: Bool = false,
        leftEyeClosed: Bool = false,
        rightEyeClosed: Bool = false
    ) -> DetectedFaceExpression {
        DetectedFaceExpression(
            normalizedBounds: CGRect(x: x, y: y, width: side, height: side),
            hasSmile: hasSmile,
            leftEyeClosed: leftEyeClosed,
            rightEyeClosed: rightEyeClosed,
            leftEyeCenter: nil,
            rightEyeCenter: nil
        )
    }

    // `shouldFail` rather than a stored `any Error` so the stub stays
    // Sendable, which `FaceOrientationDetecting` requires.
    private struct StubOrientationDetector: FaceOrientationDetecting {
        var observations: [FaceOrientationObservation] = []
        var shouldFail = false

        func orientations(in image: CGImage) throws -> [FaceOrientationObservation] {
            if shouldFail { throw TeststripError.io("vision unavailable") }
            return observations
        }
    }

    // MARK: - Per-face sharpness and light

    func testDetailedFaceCropScoresSharperThanFlatFaceCrop() throws {
        // Top-left quadrant carries checkerboard detail; bottom-right is flat.
        let image = try makeImage(checkerboard: CGRect(x: 0, y: 200, width: 200, height: 200))
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        let reports = analyzer.reports(
            in: image,
            detections: [face(x: 0.0, y: 0.0, side: 0.5), face(x: 0.5, y: 0.5, side: 0.5)]
        )

        let detailed = try XCTUnwrap(reports[0].sharpness)
        let flat = try XCTUnwrap(reports[1].sharpness)
        XCTAssertGreaterThan(detailed, flat)
        XCTAssertLessThan(flat, 0.05)
    }

    func testMidGrayFaceCropScoresBetterLightThanCrushedBlackCrop() throws {
        let image = try makeImage(black: CGRect(x: 200, y: 0, width: 200, height: 200))
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        let reports = analyzer.reports(
            in: image,
            detections: [face(x: 0.0, y: 0.0, side: 0.5), face(x: 0.5, y: 0.5, side: 0.5)]
        )

        let balanced = try XCTUnwrap(reports[0].light)
        let crushed = try XCTUnwrap(reports[1].light)
        XCTAssertGreaterThan(balanced, crushed)
        XCTAssertGreaterThan(balanced, 0.8)
        XCTAssertLessThan(crushed, 0.1)
    }

    func testCropTooSmallToMeasureLeavesSharpnessAndLightUnscored() throws {
        let image = try makeImage()
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        // 0.01 * 400 = 4 px, below the 8 px measurement floor.
        let reports = analyzer.reports(in: image, detections: [face(x: 0.5, y: 0.5, side: 0.01)])

        XCTAssertNil(reports[0].sharpness)
        XCTAssertNil(reports[0].light)
    }

    // MARK: - Prominence

    func testProminenceIsFaceAreaOverFrameArea() throws {
        let image = try makeImage()
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        let reports = analyzer.reports(in: image, detections: [face(x: 0.1, y: 0.1, side: 0.5)])

        XCTAssertEqual(reports[0].prominence, 0.25, accuracy: 0.0001)
    }

    // MARK: - Eyes and smile carried through

    func testEyesOpenUsesTheSharedBothShutNoiseFloor() throws {
        let image = try makeImage()
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        let reports = analyzer.reports(in: image, detections: [
            face(leftEyeClosed: true, rightEyeClosed: true),
            face(x: 0.5, leftEyeClosed: true, rightEyeClosed: false)
        ])

        XCTAssertFalse(reports[0].eyesOpen)
        // A single detected-shut eye is detector noise, not closed eyes.
        XCTAssertTrue(reports[1].eyesOpen)
    }

    func testSmileIsCarriedThroughForHoverAndAccessibility() throws {
        let image = try makeImage()
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        let reports = analyzer.reports(in: image, detections: [face(hasSmile: true)])

        XCTAssertTrue(reports[0].hasSmile)
    }

    // MARK: - Facing

    func testFacingComesFromTheMatchedOrientationObservation() throws {
        let image = try makeImage()
        let bounds = CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5)
        let detector = StubOrientationDetector(observations: [
            FaceOrientationObservation(normalizedBounds: bounds, yawRadians: 0, pitchRadians: 0)
        ])
        let analyzer = FaceReportAnalyzer(orientationDetector: detector)

        let reports = analyzer.reports(in: image, detections: [face(x: 0.0, y: 0.0, side: 0.5)])

        XCTAssertEqual(reports[0].facing, 1.0)
    }

    func testFailedOrientationRequestLeavesEveryFacingUnscored() throws {
        let image = try makeImage()
        let detector = StubOrientationDetector(shouldFail: true)
        let analyzer = FaceReportAnalyzer(orientationDetector: detector)

        let reports = analyzer.reports(in: image, detections: [face(), face(x: 0.5)])

        XCTAssertEqual(reports.map(\.facing), [nil, nil])
        // A failed request must not fake a green: nothing here claims a score.
        XCTAssertEqual(reports.count, 2)
    }

    func testReportsAreReturnedOnePerDetectionInDetectionOrder() throws {
        let image = try makeImage()
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        let reports = analyzer.reports(in: image, detections: [
            face(x: 0.0, side: 0.2),
            face(x: 0.5, side: 0.4)
        ])

        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports[0].normalizedBounds.width, 0.2, accuracy: 0.0001)
        XCTAssertEqual(reports[1].normalizedBounds.width, 0.4, accuracy: 0.0001)
    }

    // MARK: - The real Vision detector

    func testVisionOrientationDetectorFindsNoFacesInAFacelessImage() throws {
        let image = try makeImage()

        XCTAssertEqual(try VisionFaceOrientationDetector().orientations(in: image), [])
    }

    // MARK: - Shared exposure helper

    func testBalancedExposurePeaksAtMidGrayAndBottomsOutAtTheExtremes() {
        XCTAssertEqual(PreviewPixelMetrics.balancedExposure(meanLuminance: 0.5), 1.0, accuracy: 0.0001)
        XCTAssertEqual(PreviewPixelMetrics.balancedExposure(meanLuminance: 0.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(PreviewPixelMetrics.balancedExposure(meanLuminance: 1.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(PreviewPixelMetrics.balancedExposure(meanLuminance: 0.25), 0.5, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FaceReportAnalyzerTests 2>&1 | tail -20`
Expected: FAIL — compile error `cannot find 'FaceReportAnalyzer' in scope`.

- [ ] **Step 3: Add the shared pixel helpers**

In `Sources/TeststripCore/Evaluation/PreviewPixelMetrics.swift`, insert after `focusScore(in:width:height:)` (currently ends at line 59):

```swift
    /// Mean luminance over the sampled pixels.
    static func meanLuminance(in pixels: [UInt8], width: Int, height: Int) -> Double {
        let pixelCount = Double(width * height)
        guard pixelCount > 0 else { return 0 }
        var total = 0.0
        for y in 0..<height {
            for x in 0..<width {
                total += luminance(atX: x, y: y, in: pixels, width: width)
            }
        }
        return total / pixelCount
    }

    /// How close a mean luminance sits to a balanced mid-gray exposure: 1 at
    /// 0.5, falling linearly to 0 at pure black or pure white. Shared by the
    /// whole-photo aesthetics term and the per-face light signal so both
    /// answer "is this correctly exposed" the same way.
    static func balancedExposure(meanLuminance: Double) -> Double {
        1.0 - min(abs(meanLuminance - 0.5) * 2.0, 1.0)
    }
```

- [ ] **Step 4: Point the existing provider at the shared helpers**

In `Sources/TeststripCore/Evaluation/LocalImageMetricsEvaluationProvider.swift`, replace the inline `balancedExposure` local inside `aestheticScore` (line 113):

```swift
        let balancedExposure = 1.0 - min(abs(exposure - 0.5) * 2.0, 1.0)
```

with:

```swift
        let balancedExposure = PreviewPixelMetrics.balancedExposure(meanLuminance: exposure)
```

and replace the whole private `averageLuminance` function (lines 152-162):

```swift
    private static func averageLuminance(in pixels: [UInt8], width: Int, height: Int) -> Double {
        let pixelCount = Double(width * height)
        guard pixelCount > 0 else { return 0 }
        var total = 0.0
        for y in 0..<height {
            for x in 0..<width {
                total += PreviewPixelMetrics.luminance(atX: x, y: y, in: pixels, width: width)
            }
        }
        return total / pixelCount
    }
```

with a call through at its one use site inside `framingScore` (line 123):

```swift
        let average = PreviewPixelMetrics.meanLuminance(in: pixels, width: width, height: height)
```

(delete the private `averageLuminance` function entirely).

- [ ] **Step 5: Give `DetectedFaceExpression` the shared blink noise floor**

In `Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift`, add below the existing `hasBothEyesOpen` (lines 33-35):

```swift
    /// The blink noise floor every culling surface shares: CIDetector reports
    /// a single shut eye often enough that one alone is noise, so only both
    /// eyes shut reads as closed. Distinct from `hasBothEyesOpen`, which the
    /// per-photo eyesOpen fraction uses.
    public var bothEyesShut: Bool {
        leftEyeClosed && rightEyeClosed
    }
```

- [ ] **Step 6: Write the analyzer**

Create `Sources/TeststripCore/Evaluation/FaceReportAnalyzer.swift`:

```swift
import CoreGraphics
import Foundation
import Vision

/// Turns the close-ups pass's CIDetector detections plus the preview image
/// into one report card per face. Pure with respect to app state: image and
/// detections in, reports out; nothing is read from or written to the
/// catalog, and nothing is persisted.
public struct FaceReportAnalyzer: Sendable {
    /// Face crops are resampled to this square before measurement, matching
    /// the sample size the whole-photo metrics provider already uses.
    public static let cropSampleSize = 16

    /// Crops narrower than this measure noise, not the face, so their
    /// sharpness and light stay unscored rather than fabricated.
    public static let minimumCropPixels = 8

    private let orientationDetector: any FaceOrientationDetecting

    public init(orientationDetector: any FaceOrientationDetecting = VisionFaceOrientationDetector()) {
        self.orientationDetector = orientationDetector
    }

    public func reports(in image: CGImage, detections: [DetectedFaceExpression]) -> [FaceReport] {
        guard !detections.isEmpty else { return [] }
        // A failed head-pose request leaves every facing unscored — an empty
        // ring and a "no read" hover, never a fake score and never a fake
        // green.
        let orientations = (try? orientationDetector.orientations(in: image)) ?? []
        let facing = FaceFacingScore.matched(
            detectionBounds: detections.map(\.normalizedBounds),
            orientations: orientations
        )
        return detections.enumerated().map { index, detection in
            let samples = cropSamples(of: image, normalizedBounds: detection.normalizedBounds)
            return FaceReport(
                normalizedBounds: detection.normalizedBounds,
                eyesOpen: !detection.bothEyesShut,
                hasSmile: detection.hasSmile,
                sharpness: samples.map {
                    PreviewPixelMetrics.focusScore(
                        in: $0,
                        width: Self.cropSampleSize,
                        height: Self.cropSampleSize
                    )
                },
                light: samples.map {
                    PreviewPixelMetrics.balancedExposure(
                        meanLuminance: PreviewPixelMetrics.meanLuminance(
                            in: $0,
                            width: Self.cropSampleSize,
                            height: Self.cropSampleSize
                        )
                    )
                },
                facing: facing[index],
                prominence: min(max(Double(detection.normalizedBounds.width * detection.normalizedBounds.height), 0.0), 1.0)
            )
        }
    }

    /// nil when the face's pixel crop is smaller than `minimumCropPixels` on
    /// either side, or the crop could not be made.
    private func cropSamples(of image: CGImage, normalizedBounds: CGRect) -> [UInt8]? {
        let imageWidth = Double(image.width)
        let imageHeight = Double(image.height)
        // CGImage cropping is top-left origin, the same convention
        // `DetectedFaceExpression.normalizedBounds` uses.
        let pixelRect = CGRect(
            x: (normalizedBounds.minX * imageWidth).rounded(.down),
            y: (normalizedBounds.minY * imageHeight).rounded(.down),
            width: (normalizedBounds.width * imageWidth).rounded(),
            height: (normalizedBounds.height * imageHeight).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        guard pixelRect.width >= Double(Self.minimumCropPixels),
              pixelRect.height >= Double(Self.minimumCropPixels),
              let crop = image.cropping(to: pixelRect) else {
            return nil
        }
        return try? PreviewPixelMetrics.rgbaSamples(
            of: crop,
            width: Self.cropSampleSize,
            height: Self.cropSampleSize
        )
    }
}

/// Head pose from Vision's face rectangle detector. Revision 3 is pinned
/// explicitly because it is the revision that reports pitch as well as yaw —
/// leaving it to the default would make the facing signal silently
/// half-blind if a future SDK changes the default.
public struct VisionFaceOrientationDetector: FaceOrientationDetecting {
    public init() {}

    public func orientations(in image: CGImage) throws -> [FaceOrientationObservation] {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).map { observation in
            // Vision's boundingBox is bottom-left origin; report cards use
            // top-left, the same flip `FaceBoxOverlayGeometry` applies.
            FaceOrientationObservation(
                normalizedBounds: CGRect(
                    x: observation.boundingBox.minX,
                    y: 1.0 - observation.boundingBox.maxY,
                    width: observation.boundingBox.width,
                    height: observation.boundingBox.height
                ),
                yawRadians: observation.yaw?.doubleValue,
                pitchRadians: observation.pitch?.doubleValue
            )
        }
    }
}
```

- [ ] **Step 7: Run test to verify it passes**

Run: `swift test --filter FaceReportAnalyzerTests 2>&1 | tail -5`
Expected: PASS — `Executed 11 tests, with 0 failures`.

- [ ] **Step 8: Prove the shared-helper refactor changed no whole-photo behavior**

Run: `swift test --filter EvaluationProviderTests 2>&1 | tail -5`
Expected: PASS, unchanged from baseline — the `exposure`/`aesthetics`/`framing` assertions still hold.

- [ ] **Step 9: Run the full suite**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2311 tests, with 0 failures`.

- [ ] **Step 10: Commit**

```bash
git add Sources/TeststripCore/Evaluation/FaceReportAnalyzer.swift \
        Sources/TeststripCore/Evaluation/PreviewPixelMetrics.swift \
        Sources/TeststripCore/Evaluation/LocalImageMetricsEvaluationProvider.swift \
        Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift \
        Tests/TeststripCoreTests/FaceReportAnalyzerTests.swift
git commit -m "feat: per-face report analyzer for sharpness, light, facing, and prominence"
```

---

### Task 4: App — `FaceReportStore` with the cancellable stack sweep

**Files:**
- Create: `Sources/TeststripApp/FaceReportStore.swift`
- Test: `Tests/TeststripAppTests/FaceReportStoreTests.swift`

**Interfaces:**
- Consumes: `FaceReport`, `FaceReportGrade` (Task 1); `FaceReportAnalyzer(orientationDetector:)` and `reports(in:detections:)` (Task 3); existing `AssetID`, `CoreImageFaceExpressionAnalyzer`.
- Produces:
  - `struct FrameFaceReport: Equatable` with `reports: [FaceReport]`, `previewCacheGeneration: Int`, computed `rolledUpGrade: FaceReportGrade?`, memberwise `init(reports:previewCacheGeneration:)`.
  - `struct FaceReportSweepFrame: Equatable, Sendable` with `assetID: AssetID`, `previewURL: URL?`, `previewCacheGeneration: Int`, memberwise `init(assetID:previewURL:previewCacheGeneration:)`.
  - `@Observable final class FaceReportStore` with
    `init(analyze: @escaping @Sendable (URL) async -> [FaceReport] = FaceReportStore.analyzeCachedPreview)`,
    `@MainActor func report(for assetID: AssetID) -> FrameFaceReport?`,
    `@MainActor func record(_ reports: [FaceReport], for assetID: AssetID, previewCacheGeneration: Int)`,
    `@MainActor func sweep(frames: [FaceReportSweepFrame], currentFrameID: AssetID?) async`,
    `static func sweepOrder(frames: [FaceReportSweepFrame], currentFrameID: AssetID?) -> [FaceReportSweepFrame]`,
    `static func analyzeCachedPreview(at previewURL: URL) async -> [FaceReport]`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripAppTests/FaceReportStoreTests.swift`:

```swift
import CoreGraphics
import Foundation
import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class FaceReportStoreTests: XCTestCase {
    private static func report(sharpness: Double, prominence: Double = 0.2) -> FaceReport {
        FaceReport(
            normalizedBounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            eyesOpen: true,
            hasSmile: false,
            sharpness: sharpness,
            light: 0.9,
            facing: 0.9,
            prominence: prominence
        )
    }

    private static func frame(_ id: String, generation: Int = 1, hasPreview: Bool = true) -> FaceReportSweepFrame {
        FaceReportSweepFrame(
            assetID: AssetID(rawValue: id),
            previewURL: hasPreview ? URL(fileURLWithPath: "/previews/\(id).jpg") : nil,
            previewCacheGeneration: generation
        )
    }

    /// Records every preview URL it is handed, and can be held open on a
    /// chosen URL so a test can act while one analysis is in flight.
    private actor AnalysisRecorder {
        private(set) var calls: [String] = []
        private var gateURL: String?
        private var gateOpened: CheckedContinuation<Void, Never>?
        private var gateReached: CheckedContinuation<Void, Never>?

        func gate(on lastPathComponent: String) {
            gateURL = lastPathComponent
        }

        func analyze(_ url: URL) async -> [FaceReport] {
            calls.append(url.lastPathComponent)
            if url.lastPathComponent == gateURL {
                gateReached?.resume()
                gateReached = nil
                await withCheckedContinuation { continuation in
                    gateOpened = continuation
                }
            }
            return [FaceReportStoreTests.report(sharpness: 0.9)]
        }

        func waitUntilGateReached() async {
            await withCheckedContinuation { continuation in
                gateReached = continuation
            }
        }

        func openGate() {
            gateOpened?.resume()
            gateOpened = nil
        }
    }

    // MARK: - Sweep order

    func testSweepOrderPutsTheCurrentFrameFirstThenRailOrder() {
        let frames = [Self.frame("a"), Self.frame("b"), Self.frame("c")]

        let ordered = FaceReportStore.sweepOrder(frames: frames, currentFrameID: AssetID(rawValue: "c"))

        XCTAssertEqual(ordered.map(\.assetID.rawValue), ["c", "a", "b"])
    }

    func testSweepOrderKeepsRailOrderWhenTheCurrentFrameIsNotInTheRail() {
        let frames = [Self.frame("a"), Self.frame("b")]

        let ordered = FaceReportStore.sweepOrder(frames: frames, currentFrameID: AssetID(rawValue: "z"))

        XCTAssertEqual(ordered.map(\.assetID.rawValue), ["a", "b"])
    }

    @MainActor
    func testSweepAnalyzesTheCurrentFrameBeforeTheRest() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(
            frames: [Self.frame("a"), Self.frame("b"), Self.frame("c")],
            currentFrameID: AssetID(rawValue: "b")
        )

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["b.jpg", "a.jpg", "c.jpg"])
        XCTAssertNotNil(store.report(for: AssetID(rawValue: "a")))
        XCTAssertNotNil(store.report(for: AssetID(rawValue: "b")))
        XCTAssertNotNil(store.report(for: AssetID(rawValue: "c")))
    }

    // MARK: - Preview availability and generation

    @MainActor
    func testFramesWithoutACachedPreviewAreSkipped() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(
            frames: [Self.frame("a"), Self.frame("b", hasPreview: false)],
            currentFrameID: nil
        )

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["a.jpg"])
        XCTAssertNil(store.report(for: AssetID(rawValue: "b")))
    }

    @MainActor
    func testASkippedFrameIsPickedUpOnceItsPreviewGenerationBumps() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(frames: [Self.frame("b", hasPreview: false)], currentFrameID: nil)
        await store.sweep(frames: [Self.frame("b", generation: 2)], currentFrameID: nil)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["b.jpg"])
        XCTAssertEqual(store.report(for: AssetID(rawValue: "b"))?.previewCacheGeneration, 2)
    }

    @MainActor
    func testAFrameAlreadyComputedAtTheSameGenerationIsNotReanalyzed() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(frames: [Self.frame("a", generation: 3)], currentFrameID: nil)
        await store.sweep(frames: [Self.frame("a", generation: 3)], currentFrameID: nil)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["a.jpg"])
    }

    @MainActor
    func testAGenerationBumpInvalidatesTheCachedReport() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(frames: [Self.frame("a", generation: 1)], currentFrameID: nil)
        await store.sweep(frames: [Self.frame("a", generation: 2)], currentFrameID: nil)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["a.jpg", "a.jpg"])
        XCTAssertEqual(store.report(for: AssetID(rawValue: "a"))?.previewCacheGeneration, 2)
    }

    // MARK: - Cancellation

    @MainActor
    func testCancellationStopsTheSweepAndDiscardsTheInFlightResult() async {
        let recorder = AnalysisRecorder()
        await recorder.gate(on: "a.jpg")
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        let sweep = Task { @MainActor in
            await store.sweep(
                frames: [Self.frame("a"), Self.frame("b"), Self.frame("c")],
                currentFrameID: nil
            )
        }
        await recorder.waitUntilGateReached()
        sweep.cancel()
        await recorder.openGate()
        await sweep.value

        let calls = await recorder.calls
        // The in-flight frame's result is dropped rather than published from
        // a sweep the user already navigated away from...
        XCTAssertNil(store.report(for: AssetID(rawValue: "a")))
        // ...and the frames behind it are never analyzed at all.
        XCTAssertEqual(calls, ["a.jpg"])
        XCTAssertNil(store.report(for: AssetID(rawValue: "b")))
        XCTAssertNil(store.report(for: AssetID(rawValue: "c")))
    }

    // MARK: - Roll-up and the close-ups hand-off

    @MainActor
    func testRecordStoresTheCloseUpsPassResultWithoutAnalyzingAgain() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        store.record([Self.report(sharpness: 0.9)], for: AssetID(rawValue: "a"), previewCacheGeneration: 4)
        await store.sweep(frames: [Self.frame("a", generation: 4)], currentFrameID: nil)

        let calls = await recorder.calls
        XCTAssertEqual(calls, [])
        XCTAssertEqual(store.report(for: AssetID(rawValue: "a"))?.reports.count, 1)
    }

    @MainActor
    func testRolledUpGradeIsTheWorstFaceGrade() {
        let store = FaceReportStore()

        store.record(
            [Self.report(sharpness: 0.9), Self.report(sharpness: 0.45)],
            for: AssetID(rawValue: "a"),
            previewCacheGeneration: 1
        )

        XCTAssertEqual(store.report(for: AssetID(rawValue: "a"))?.rolledUpGrade, .yellow)
    }

    @MainActor
    func testABackgroundFacesRuinedSignalNeverRollsTheFrameUpToRed() {
        let store = FaceReportStore()

        store.record(
            [
                Self.report(sharpness: 0.9, prominence: 0.3),
                // Ruined, but far below the prominence floor.
                Self.report(sharpness: 0.05, prominence: 0.001)
            ],
            for: AssetID(rawValue: "a"),
            previewCacheGeneration: 1
        )

        XCTAssertEqual(store.report(for: AssetID(rawValue: "a"))?.rolledUpGrade, .yellow)
    }

    @MainActor
    func testAFrameWithNoFacesHasNoRolledUpGrade() {
        let store = FaceReportStore()

        store.record([], for: AssetID(rawValue: "a"), previewCacheGeneration: 1)

        // Absence means "nothing known", never "known good".
        XCTAssertNil(store.report(for: AssetID(rawValue: "a"))?.rolledUpGrade)
    }

    @MainActor
    func testAnUncomputedFrameHasNoReportAtAll() {
        let store = FaceReportStore()

        XCTAssertNil(store.report(for: AssetID(rawValue: "never-swept")))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FaceReportStoreTests 2>&1 | tail -20`
Expected: FAIL — compile error `cannot find 'FaceReportStore' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/TeststripApp/FaceReportStore.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO
import Observation
import TeststripCore

/// One frame's face report cards, plus the preview-cache generation they were
/// computed from. A stale generation means the preview changed under us and
/// the frame is re-analyzed on the next sweep.
struct FrameFaceReport: Equatable {
    var reports: [FaceReport]
    var previewCacheGeneration: Int

    init(reports: [FaceReport], previewCacheGeneration: Int) {
        self.reports = reports
        self.previewCacheGeneration = previewCacheGeneration
    }

    /// The frame's traffic light: the worst grade any face earned. Grading
    /// already applied the prominence floor, so a background face can only
    /// push this to yellow. nil when the frame has no faces — absence means
    /// "nothing known", never "known good".
    var rolledUpGrade: FaceReportGrade? {
        reports.map(\.grade).max()
    }
}

/// One frame the sweep may analyze: its best cached preview (nil when it has
/// none yet) and the generation that preview belongs to.
struct FaceReportSweepFrame: Equatable, Sendable {
    var assetID: AssetID
    var previewURL: URL?
    var previewCacheGeneration: Int

    init(assetID: AssetID, previewURL: URL?, previewCacheGeneration: Int) {
        self.assetID = assetID
        self.previewURL = previewURL
        self.previewCacheGeneration = previewCacheGeneration
    }
}

/// The single in-app home for per-face report cards. Both surfaces read it —
/// the close-ups panel's chips and header roll-up, and the burst rail's dots
/// — so a frame can never show one grade in one place and another elsewhere.
/// In memory only: nothing here is persisted, and no worker is involved.
@Observable
final class FaceReportStore {
    /// Keyed on the same invalidation signal views already use
    /// (`AppModel.previewCacheGeneration(for:)`).
    private(set) var reportsByAssetID: [AssetID: FrameFaceReport] = [:]

    private let analyze: @Sendable (URL) async -> [FaceReport]

    init(analyze: @escaping @Sendable (URL) async -> [FaceReport] = FaceReportStore.analyzeCachedPreview) {
        self.analyze = analyze
    }

    @MainActor
    func report(for assetID: AssetID) -> FrameFaceReport? {
        reportsByAssetID[assetID]
    }

    /// The close-ups pass owns the selected frame's detections and crops, so
    /// it hands its already-computed reports straight in rather than making
    /// the sweep redo the same work — the selected frame's chips, its panel
    /// dot, and its rail dot all come from one computation.
    @MainActor
    func record(_ reports: [FaceReport], for assetID: AssetID, previewCacheGeneration: Int) {
        reportsByAssetID[assetID] = FrameFaceReport(
            reports: reports,
            previewCacheGeneration: previewCacheGeneration
        )
    }

    /// Analyzes the stack's frames one at a time, publishing each as it lands
    /// so dots appear progressively. Plain structured concurrency: the caller
    /// owns the task, so a stack change cancels and restarts the sweep for
    /// free. Cancellation is honored both before starting a frame and before
    /// publishing one, so a sweep the user navigated away from never writes.
    @MainActor
    func sweep(frames: [FaceReportSweepFrame], currentFrameID: AssetID?) async {
        for frame in Self.sweepOrder(frames: frames, currentFrameID: currentFrameID) {
            if Task.isCancelled { return }
            guard let previewURL = frame.previewURL else { continue }
            if let cached = reportsByAssetID[frame.assetID],
               cached.previewCacheGeneration == frame.previewCacheGeneration {
                continue
            }
            let reports = await analyze(previewURL)
            if Task.isCancelled { return }
            reportsByAssetID[frame.assetID] = FrameFaceReport(
                reports: reports,
                previewCacheGeneration: frame.previewCacheGeneration
            )
        }
    }

    /// Current frame first — the one the photographer is looking at — then
    /// the remaining frames in rail order.
    static func sweepOrder(
        frames: [FaceReportSweepFrame],
        currentFrameID: AssetID?
    ) -> [FaceReportSweepFrame] {
        guard let currentFrameID,
              let index = frames.firstIndex(where: { $0.assetID == currentFrameID }) else {
            return frames
        }
        var ordered = frames
        let current = ordered.remove(at: index)
        return [current] + ordered
    }

    /// Detection plus report-card analysis over one cached preview, entirely
    /// off the main actor. A preview that cannot be read yields no reports
    /// rather than a fabricated one.
    static func analyzeCachedPreview(at previewURL: URL) async -> [FaceReport] {
        await Task.detached(priority: .utility) { () -> [FaceReport] in
            guard let detections = try? CoreImageFaceExpressionAnalyzer().detectFaces(previewURL: previewURL),
                  !detections.isEmpty,
                  let source = CGImageSourceCreateWithURL(previewURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return []
            }
            return FaceReportAnalyzer().reports(in: image, detections: detections)
        }.value
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FaceReportStoreTests 2>&1 | tail -5`
Expected: PASS — `Executed 13 tests, with 0 failures`.

- [ ] **Step 5: Run the full suite**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2324 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripApp/FaceReportStore.swift Tests/TeststripAppTests/FaceReportStoreTests.swift
git commit -m "feat: face report store with a cancellable current-frame-first stack sweep"
```

---

### Task 5: App — chip and roll-up presentation, plus the chip view

**Files:**
- Create: `Sources/TeststripApp/FaceReportPresentation.swift`
- Create: `Sources/TeststripApp/FaceSignalChipView.swift`
- Test: `Tests/TeststripAppTests/FaceReportPresentationTests.swift`

**Interfaces:**
- Consumes: `FaceReport`, `FaceReportGrade` (Task 1); `FrameFaceReport` (Task 4).
- Produces:
  - `enum FaceReportSignal: String, CaseIterable { case eyes, sharpness, facing, light }` with `var word: String` and `var symbolName: String`.
  - `struct FaceReportChipPresentation: Equatable` with nested `struct Entry: Equatable, Identifiable { var signal: FaceReportSignal; var score: Double?; var accessibilityText: String; var id: String }`, `var entries: [Entry]`, and `init(report: FaceReport)`.
  - `enum FaceReportRollUpPresentation` with `static func word(for: FaceReportGrade) -> String`, `static func color(for: FaceReportGrade) -> Color`, `static func dotGrade(for: FrameFaceReport?) -> FaceReportGrade?`, `static func headerValue(for: FrameFaceReport?) -> String`, `static func tileAccessibilityValue(for: FaceReport) -> String`.
  - `struct FaceSignalChipView: View { let entry: FaceReportChipPresentation.Entry }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripAppTests/FaceReportPresentationTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class FaceReportPresentationTests: XCTestCase {
    private static func report(
        eyesOpen: Bool = true,
        hasSmile: Bool = false,
        sharpness: Double? = 0.82,
        light: Double? = 0.61,
        facing: Double? = 0.94,
        prominence: Double = 0.2
    ) -> FaceReport {
        FaceReport(
            normalizedBounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            eyesOpen: eyesOpen,
            hasSmile: hasSmile,
            sharpness: sharpness,
            light: light,
            facing: facing,
            prominence: prominence
        )
    }

    // MARK: - Chips

    func testChipRowIsAlwaysAllFourSignalsInFixedOrder() {
        let presentation = FaceReportChipPresentation(report: Self.report())

        XCTAssertEqual(presentation.entries.map(\.signal), [.eyes, .sharpness, .facing, .light])
    }

    func testEveryChipIsPresentEvenWhenNothingWasMeasured() {
        let presentation = FaceReportChipPresentation(
            report: Self.report(sharpness: nil, light: nil, facing: nil)
        )

        XCTAssertEqual(presentation.entries.count, 4)
        XCTAssertEqual(presentation.entries.map(\.score), [1.0, nil, nil, nil])
    }

    func testChipScoresMirrorTheReport() {
        let presentation = FaceReportChipPresentation(report: Self.report())

        XCTAssertEqual(presentation.entries.map(\.score), [1.0, 0.82, 0.94, 0.61])
    }

    func testClosedEyesScoreZeroRatherThanGoingUnscored() {
        let presentation = FaceReportChipPresentation(report: Self.report(eyesOpen: false))

        XCTAssertEqual(presentation.entries[0].score, 0.0)
        XCTAssertEqual(presentation.entries[0].accessibilityText, "Eyes 0%")
    }

    func testChipAccessibilityTextIsTheSignalWordAndPercent() {
        let presentation = FaceReportChipPresentation(report: Self.report())

        XCTAssertEqual(presentation.entries.map(\.accessibilityText), [
            "Eyes 100%",
            "Sharpness 82%",
            "Facing 94%",
            "Light 61%"
        ])
    }

    func testAnUnscoredSignalSaysNoReadRatherThanZeroPercent() {
        let presentation = FaceReportChipPresentation(report: Self.report(facing: nil))

        XCTAssertEqual(presentation.entries[2].score, nil)
        XCTAssertEqual(presentation.entries[2].accessibilityText, "Facing no read")
    }

    func testChipEntryIdentityIsItsSignal() {
        let presentation = FaceReportChipPresentation(report: Self.report())

        XCTAssertEqual(presentation.entries.map(\.id), ["eyes", "sharpness", "facing", "light"])
    }

    // MARK: - Tile accessibility (eyes state plus smile; smile is not a chip)

    func testTileAccessibilityValueCarriesEyesStateAndSmile() {
        XCTAssertEqual(
            FaceReportRollUpPresentation.tileAccessibilityValue(for: Self.report(hasSmile: true)),
            "Clean, Eyes open, Smiling"
        )
        XCTAssertEqual(
            FaceReportRollUpPresentation.tileAccessibilityValue(
                for: Self.report(eyesOpen: false, hasSmile: false)
            ),
            "Ruined, Eyes closed"
        )
    }

    // MARK: - Roll-up

    func testGradeWordsAreTheTrafficLightVocabulary() {
        XCTAssertEqual(FaceReportRollUpPresentation.word(for: .green), "Clean")
        XCTAssertEqual(FaceReportRollUpPresentation.word(for: .yellow), "Check")
        XCTAssertEqual(FaceReportRollUpPresentation.word(for: .red), "Ruined")
    }

    func testAnUncomputedFrameHasNoDotAndSaysSoInTheHeader() {
        XCTAssertNil(FaceReportRollUpPresentation.dotGrade(for: nil))
        XCTAssertEqual(FaceReportRollUpPresentation.headerValue(for: nil), "Faces not read yet")
    }

    func testAFacelessFrameHasNoDotAndKeepsTheHonestEmptyState() {
        let frame = FrameFaceReport(reports: [], previewCacheGeneration: 1)

        XCTAssertNil(FaceReportRollUpPresentation.dotGrade(for: frame))
        XCTAssertEqual(FaceReportRollUpPresentation.headerValue(for: frame), "No faces")
    }

    func testTheDotIsTheWorstProminentFacesGrade() {
        let frame = FrameFaceReport(
            reports: [
                Self.report(sharpness: 0.9, prominence: 0.3),
                Self.report(sharpness: 0.05, prominence: 0.3)
            ],
            previewCacheGeneration: 1
        )

        XCTAssertEqual(FaceReportRollUpPresentation.dotGrade(for: frame), .red)
    }

    func testABelowFloorRuinedFaceCapsTheDotAtYellow() {
        let frame = FrameFaceReport(
            reports: [
                Self.report(sharpness: 0.9, prominence: 0.3),
                Self.report(sharpness: 0.05, prominence: 0.001)
            ],
            previewCacheGeneration: 1
        )

        XCTAssertEqual(FaceReportRollUpPresentation.dotGrade(for: frame), .yellow)
    }

    func testTheHeaderReportsTheSameGradeAsTheDotForTheSameFrame() {
        let frame = FrameFaceReport(
            reports: [Self.report(sharpness: 0.45, prominence: 0.3)],
            previewCacheGeneration: 1
        )

        let grade = try? XCTUnwrap(FaceReportRollUpPresentation.dotGrade(for: frame))
        XCTAssertEqual(
            FaceReportRollUpPresentation.headerValue(for: frame),
            "1 face, \(FaceReportRollUpPresentation.word(for: grade ?? .green))"
        )
    }

    func testTheHeaderPluralizesTheFaceCount() {
        let frame = FrameFaceReport(
            reports: [Self.report(), Self.report(), Self.report()],
            previewCacheGeneration: 1
        )

        XCTAssertEqual(FaceReportRollUpPresentation.headerValue(for: frame), "3 faces, Clean")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FaceReportPresentationTests 2>&1 | tail -20`
Expected: FAIL — compile error `cannot find 'FaceReportChipPresentation' in scope`.

- [ ] **Step 3: Write the presentation**

Create `Sources/TeststripApp/FaceReportPresentation.swift`:

```swift
import SwiftUI
import TeststripCore

/// The four quality signals a face report card shows, in the fixed order the
/// chip row renders them. Smile is deliberately absent: a non-smiling face is
/// not a defect, so it lives in hover/AX only.
enum FaceReportSignal: String, CaseIterable {
    case eyes
    case sharpness
    case facing
    case light

    var word: String {
        switch self {
        case .eyes: return "Eyes"
        case .sharpness: return "Sharpness"
        case .facing: return "Facing"
        case .light: return "Light"
        }
    }

    /// Stylized monochrome SF Symbols that name the signal inside the donut.
    var symbolName: String {
        switch self {
        case .eyes: return "eye.fill"
        case .sharpness: return "scope"
        case .facing: return "person.fill"
        case .light: return "sun.max.fill"
        }
    }
}

/// One face tile's chip row: always all four signals, so a missing chip can
/// never be mistaken for a clean read.
struct FaceReportChipPresentation: Equatable {
    struct Entry: Equatable, Identifiable {
        var signal: FaceReportSignal
        /// nil renders an empty ring — the signal was not measured.
        var score: Double?
        var accessibilityText: String

        var id: String { signal.rawValue }
    }

    var entries: [Entry]

    init(report: FaceReport) {
        entries = FaceReportSignal.allCases.map { signal in
            let score: Double?
            switch signal {
            case .eyes: score = report.eyesScore
            case .sharpness: score = report.sharpness
            case .facing: score = report.facing
            case .light: score = report.light
            }
            return Entry(
                signal: signal,
                score: score,
                accessibilityText: Self.accessibilityText(signal: signal, score: score)
            )
        }
    }

    private static func accessibilityText(signal: FaceReportSignal, score: Double?) -> String {
        guard let score else { return "\(signal.word) no read" }
        return "\(signal.word) \(Int((min(max(score, 0), 1) * 100).rounded()))%"
    }
}

/// The traffic-light vocabulary shared by the face tile's corner dot, the
/// close-ups header, and the burst rail's dots — one home, so panel and rail
/// can never disagree about a frame.
enum FaceReportRollUpPresentation {
    static func word(for grade: FaceReportGrade) -> String {
        switch grade {
        case .green: return "Clean"
        case .yellow: return "Check"
        case .red: return "Ruined"
        }
    }

    static func color(for grade: FaceReportGrade) -> Color {
        switch grade {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    /// nil means no dot at all: either nothing has been computed for the
    /// frame yet, or the frame has no faces. Absence is never "known good".
    static func dotGrade(for frame: FrameFaceReport?) -> FaceReportGrade? {
        frame?.rolledUpGrade
    }

    /// The close-ups header's accessibility value. "No faces" is preserved
    /// verbatim as the faceless empty state that scenario cards assert on.
    static func headerValue(for frame: FrameFaceReport?) -> String {
        guard let frame else { return "Faces not read yet" }
        guard let grade = frame.rolledUpGrade else { return "No faces" }
        let count = frame.reports.count
        return "\(count) \(count == 1 ? "face" : "faces"), \(word(for: grade))"
    }

    /// One face tile's accessibility value: its grade, then the eyes state
    /// and smile that the chip row deliberately does not carry.
    static func tileAccessibilityValue(for report: FaceReport) -> String {
        var segments = [word(for: report.grade)]
        segments.append(report.eyesOpen ? "Eyes open" : "Eyes closed")
        if report.hasSmile {
            segments.append("Smiling")
        }
        return segments.joined(separator: ", ")
    }
}
```

- [ ] **Step 4: Write the chip view**

Create `Sources/TeststripApp/FaceSignalChipView.swift`:

```swift
import SwiftUI

/// One per-face signal chip: a 17pt donut ring whose sweep is the score, with
/// a stylized monochrome icon inside naming the signal. A sibling of
/// `SignalGlyphView` (the reads card's 11pt word-beside-donut glyph), not a
/// variant of it — the reads card shows whole-photo measures with room for a
/// word, a face tile shows four measures in 112pt with room only for icons.
struct FaceSignalChipView: View {
    let entry: FaceReportChipPresentation.Entry

    private static let donutSize: CGFloat = 17
    private static let ringWidth: CGFloat = 2.4
    private static let fillColor = Color(red: 0.35, green: 0.78, blue: 0.78)

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: Self.ringWidth)
            // An unscored signal leaves the ring empty: no sweep at all, so
            // "not measured" can never look like "measured zero" or a clean
            // full ring.
            if let score = entry.score {
                Circle()
                    .trim(from: 0, to: max(0, min(1, score)))
                    .stroke(Self.fillColor, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: entry.signal.symbolName)
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
        }
        .frame(width: Self.donutSize, height: Self.donutSize)
        .help(entry.accessibilityText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityText)
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter FaceReportPresentationTests 2>&1 | tail -5`
Expected: PASS — `Executed 15 tests, with 0 failures`.

- [ ] **Step 6: Run the full suite**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2339 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripApp/FaceReportPresentation.swift \
        Sources/TeststripApp/FaceSignalChipView.swift \
        Tests/TeststripAppTests/FaceReportPresentationTests.swift
git commit -m "feat: face report chip and traffic-light roll-up presentation"
```

---

### Task 6: App — close-ups panel renders chips, tile dots, and the header roll-up

**Files:**
- Modify: `Sources/TeststripApp/CloseUpFacesPresentation.swift` (whole file — geometry plus `faceIndex`; the asset-level sharpness attribution retires)
- Modify: `Sources/TeststripApp/LibraryGridView.swift:3784-3790` (`LoupeCloseUpCrop`), `:3811` (add the store), `:4110-4133` (`closeUpsRail`), `:4138-4182` (`closeUpCropCell`, `closeUpMarks`, `closeUpMarksAccessibilityValue`), `:4259-4297` (`refreshCloseUps`)
- Test: `Tests/TeststripAppTests/CloseUpFacesPresentationTests.swift`

**Interfaces:**
- Consumes: `FaceReport` (Task 1); `FaceReportAnalyzer().reports(in:detections:)` (Task 3); `FaceReportStore`, `FrameFaceReport` (Task 4); `FaceReportChipPresentation(report:)`, `FaceReportRollUpPresentation.color(for:)/.dotGrade(for:)/.headerValue(for:)/.tileAccessibilityValue(for:)`, `FaceSignalChipView(entry:)` (Task 5).
- Produces:
  - `CloseUpFacesPresentation.Crop` now `struct Crop: Equatable, Identifiable { var id: Int; var faceIndex: Int; var pixelRect: CGRect }` — `eyesState`, `isSmiling`, `sharpnessTone` and the `EyesState`/`SharpnessTone` enums are gone, as is the `wholePhotoSignals:` init parameter.
  - `CloseUpFacesPresentation.init(faces:imagePixelSize:)`
  - `LoupeView` holds `@State private var faceReportStore = FaceReportStore()`, used by Task 8's rail.

- [ ] **Step 1: Write the failing test**

Replace the whole contents of `Tests/TeststripAppTests/CloseUpFacesPresentationTests.swift` with the four geometry tests plus two new pairing tests. Seven tests are deleted here because the facts they covered moved to `FaceReport`; every one has a named successor:

| Deleted | Superseded by |
| --- | --- |
| `testEyesStateClosedOnlyWhenBothEyesShut` | `FaceReportAnalyzerTests.testEyesOpenUsesTheSharedBothShutNoiseFloor` (Task 3) |
| `testSmileMarkReflectsHasSmile` | `FaceReportAnalyzerTests.testSmileIsCarriedThroughForHoverAndAccessibility` (Task 3) + `FaceReportPresentationTests.testTileAccessibilityValueCarriesEyesStateAndSmile` (Task 5) |
| `testSharpnessMarkSharpWhenFaceQualityAboveThreshold` | `FaceReportAnalyzerTests.testDetailedFaceCropScoresSharperThanFlatFaceCrop` (Task 3) |
| `testSharpnessMarkSoftWhenFaceQualityBelowThreshold` | `FaceReportAnalyzerTests.testDetailedFaceCropScoresSharperThanFlatFaceCrop` (Task 3) |
| `testSharpnessMarkFallsBackToEyeSharpnessWhenNoFaceQuality` | Retired with the asset-level fallback itself — sharpness is measured per face now, so there is no asset-level signal to fall back to |
| `testSharpnessMarkAbsentWithoutASignal` | `FaceReportAnalyzerTests.testCropTooSmallToMeasureLeavesSharpnessAndLightUnscored` (Task 3) + `FaceReportPresentationTests.testAnUnscoredSignalSaysNoReadRatherThanZeroPercent` (Task 5) |
| `testSharpnessMarkAbsentOnEveryCropWhenMultipleFacesShareTheSignal` | Retired with the ambiguity itself — `FaceReportAnalyzerTests.testReportsAreReturnedOnePerDetectionInDetectionOrder` (Task 3) proves every face now gets its own read |

```swift
import CoreGraphics
import Foundation
import TeststripCore
import XCTest
@testable import TeststripApp

final class CloseUpFacesPresentationTests: XCTestCase {
    func testCropsPadAndCenterOnTheFace() {
        let face = Self.face(x: 0.4, size: 0.2)

        let presentation = CloseUpFacesPresentation(faces: [face], imagePixelSize: CGSize(width: 1000, height: 1000))

        XCTAssertEqual(presentation.crops.count, 1)
        // Face is 200x200 px centered at (500, 500); padded side = 200 * 1.6 = 320.
        XCTAssertEqual(presentation.crops[0].pixelRect, CGRect(x: 340, y: 340, width: 320, height: 320))
    }

    func testCropsClampToImageBounds() {
        let cornerFace = Self.face(x: 0.0, y: 0.0, size: 0.2)

        let presentation = CloseUpFacesPresentation(faces: [cornerFace], imagePixelSize: CGSize(width: 1000, height: 1000))

        let rect = presentation.crops[0].pixelRect
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, 1000)
        XCTAssertLessThanOrEqual(rect.maxY, 1000)
    }

    func testCropsOrderLargestFaceFirstAndCapAtFour() {
        let faces = [
            Self.face(x: 0.05, size: 0.10),
            Self.face(x: 0.25, size: 0.30),
            Self.face(x: 0.60, size: 0.20),
            Self.face(x: 0.85, size: 0.12),
            Self.face(x: 0.45, size: 0.15)
        ]

        let presentation = CloseUpFacesPresentation(faces: faces, imagePixelSize: CGSize(width: 2000, height: 1000))

        XCTAssertEqual(presentation.crops.count, 4)
        let sides = presentation.crops.map(\.pixelRect.width)
        XCTAssertEqual(sides, sides.sorted(by: >))
    }

    func testTinyFacesAreSkipped() {
        let tinyFace = Self.face(x: 0.5, y: 0.5, size: 0.01)

        let presentation = CloseUpFacesPresentation(faces: [tinyFace], imagePixelSize: CGSize(width: 1000, height: 1000))

        XCTAssertTrue(presentation.crops.isEmpty)
    }

    // Crops are sorted largest-first while reports stay in detection order,
    // so each crop has to say which detection it came from or the tile would
    // show another face's report card.
    func testEachCropCarriesTheIndexOfTheFaceItCameFrom() {
        let faces = [
            Self.face(x: 0.05, size: 0.10),
            Self.face(x: 0.25, size: 0.30),
            Self.face(x: 0.60, size: 0.20)
        ]

        let presentation = CloseUpFacesPresentation(faces: faces, imagePixelSize: CGSize(width: 2000, height: 1000))

        XCTAssertEqual(presentation.crops.map(\.faceIndex), [1, 2, 0])
        XCTAssertEqual(presentation.crops.map(\.id), [0, 1, 2])
    }

    func testSkippedTinyFacesDoNotShiftTheRemainingFaceIndices() {
        let faces = [
            Self.face(x: 0.05, size: 0.005),
            Self.face(x: 0.40, size: 0.30)
        ]

        let presentation = CloseUpFacesPresentation(faces: faces, imagePixelSize: CGSize(width: 2000, height: 1000))

        XCTAssertEqual(presentation.crops.map(\.faceIndex), [1])
    }

    private static func face(x: Double, y: Double = 0.1, size: Double) -> DetectedFaceExpression {
        DetectedFaceExpression(
            normalizedBounds: CGRect(x: x, y: y, width: size, height: size),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: nil,
            rightEyeCenter: nil
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CloseUpFacesPresentationTests 2>&1 | tail -20`
Expected: FAIL — compile error `value of type 'CloseUpFacesPresentation.Crop' has no member 'faceIndex'`.

- [ ] **Step 3: Rewrite `CloseUpFacesPresentation`**

Replace the whole contents of `Sources/TeststripApp/CloseUpFacesPresentation.swift`:

```swift
import CoreGraphics
import Foundation
import TeststripCore

/// Display-only close-up crop geometry for the loupe's close-ups rail. Crops
/// come from on-demand face detection over the cached preview; nothing
/// persists. Every read a crop shows now lives in its `FaceReport` (paired by
/// `faceIndex`), so this type owns geometry alone.
struct CloseUpFacesPresentation: Equatable {
    struct Crop: Equatable, Identifiable {
        var id: Int
        /// Index into the `faces` array this crop was built from. Crops sort
        /// largest-first while reports stay in detection order, so the tile
        /// needs this to pair with the right report card.
        var faceIndex: Int
        var pixelRect: CGRect
    }

    static let maximumCropCount = 4
    private static let cropPaddingFactor = 1.6
    private static let minimumCropSidePixels = 24.0

    var crops: [Crop]

    init(faces: [DetectedFaceExpression], imagePixelSize: CGSize) {
        let imageBounds = CGRect(origin: .zero, size: imagePixelSize)
        // Largest first: prominence is both the grading weight and the order
        // a photographer scans in.
        let orderedFaces = faces.enumerated().sorted { lhs, rhs in
            lhs.element.normalizedBounds.width * lhs.element.normalizedBounds.height
                > rhs.element.normalizedBounds.width * rhs.element.normalizedBounds.height
        }
        var crops: [Crop] = []
        for (faceIndex, face) in orderedFaces {
            guard crops.count < Self.maximumCropCount else { break }
            let facePixelWidth = face.normalizedBounds.width * imagePixelSize.width
            let facePixelHeight = face.normalizedBounds.height * imagePixelSize.height
            let side = max(facePixelWidth, facePixelHeight) * Self.cropPaddingFactor
            guard side >= Self.minimumCropSidePixels else { continue }
            let center = CGPoint(
                x: face.normalizedBounds.midX * imagePixelSize.width,
                y: face.normalizedBounds.midY * imagePixelSize.height
            )
            var rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            if rect.minX < 0 { rect.origin.x = 0 }
            if rect.minY < 0 { rect.origin.y = 0 }
            if rect.maxX > imageBounds.maxX { rect.origin.x = imageBounds.maxX - rect.width }
            if rect.maxY > imageBounds.maxY { rect.origin.y = imageBounds.maxY - rect.height }
            rect = rect.intersection(imageBounds)
            guard rect.width >= Self.minimumCropSidePixels, rect.height >= Self.minimumCropSidePixels else { continue }
            crops.append(Crop(id: crops.count, faceIndex: faceIndex, pixelRect: rect))
        }
        self.crops = crops
    }
}
```

- [ ] **Step 4: Re-shape the loupe's crop model and add the store**

In `Sources/TeststripApp/LibraryGridView.swift`, replace `LoupeCloseUpCrop` (lines 3782-3790):

```swift
/// A single close-up rail entry: the cropped face image plus the per-face
/// report card `FaceReportAnalyzer` produced from the same detections.
private struct LoupeCloseUpCrop {
    var id: Int
    var image: CGImage
    var report: FaceReport
}
```

and add the store beside `closeUpCrops` (line 3811):

```swift
    @State private var closeUpCrops: [LoupeCloseUpCrop] = []
    // The one home for per-face report cards this session. The close-ups
    // pass records the selected frame's reports here and the stack rail
    // sweeps the rest, so the panel's dot and the rail's dot for the same
    // frame always come from one computation.
    @State private var faceReportStore = FaceReportStore()
```

- [ ] **Step 5: Render the header roll-up, the tile dot, and the chip row**

Replace `closeUpsRail` (lines 4110-4133) with:

```swift
    private var closeUpsRail: some View {
        let frameReport = model.selectedAssetID.flatMap { faceReportStore.report(for: $0) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if let grade = FaceReportRollUpPresentation.dotGrade(for: frameReport) {
                    Circle()
                        .fill(FaceReportRollUpPresentation.color(for: grade))
                        .frame(width: Self.faceGradeDotSize, height: Self.faceGradeDotSize)
                }
                Text("CLOSE-UPS")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                if let frameReport, !frameReport.reports.isEmpty {
                    Text("\(frameReport.reports.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if closeUpCrops.isEmpty {
                Text("No faces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(closeUpCrops, id: \.id) { crop in
                            closeUpCropCell(crop)
                        }
                    }
                }
            }
        }
        .frame(width: Self.closeUpsRailWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Face close-ups")
        .accessibilityValue(FaceReportRollUpPresentation.headerValue(for: frameReport))
    }
```

Replace `closeUpCropCell`, `closeUpMarks`, and `closeUpMarksAccessibilityValue` (lines 4135-4182) with:

```swift
    // One face crop plus its report card: a corner traffic dot on the crop,
    // and one always-on row of four icon-in-donut chips below it (eyes,
    // sharpness, facing, light) in that fixed order. Always all four — a
    // missing chip must never read as a clean signal. Smile is not a defect,
    // so it lives in the tile's accessibility value, not the chip row.
    private func closeUpCropCell(_ crop: LoupeCloseUpCrop) -> some View {
        VStack(spacing: 4) {
            Image(decorative: crop.image, scale: 1)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: Self.closeUpCropSize, height: Self.closeUpCropSize)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.14))
                }
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(FaceReportRollUpPresentation.color(for: crop.report.grade))
                        .frame(width: Self.faceGradeDotSize, height: Self.faceGradeDotSize)
                        .overlay { Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                        .padding(5)
                }
            closeUpChips(crop)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Face")
        .accessibilityValue(FaceReportRollUpPresentation.tileAccessibilityValue(for: crop.report))
    }

    private func closeUpChips(_ crop: LoupeCloseUpCrop) -> some View {
        HStack(spacing: 4) {
            ForEach(FaceReportChipPresentation(report: crop.report).entries) { entry in
                FaceSignalChipView(entry: entry)
            }
        }
    }
```

Add the shared dot metric beside the existing close-ups metrics (line 4081):

```swift
    private static let closeUpCropSize: CGFloat = 112
    // One dot size for the face tile's corner dot, the close-ups header, and
    // the burst rail's roll-up dot — they mean the same thing, so they look
    // the same.
    private static let faceGradeDotSize: CGFloat = 9
```

- [ ] **Step 6: Feed the analyzer and the store from `refreshCloseUps`**

Replace `refreshCloseUps(for:)` (lines 4254-4297) with:

```swift
    // Detection is display-only and per-selection: the cached preview is read
    // off the main actor, analyzed and cropped in memory, and nothing is
    // persisted. The same detections feed the Close-Ups crops, their report
    // cards, the frame's entry in the shared report store (so its rail dot
    // agrees), and the Z zoom-to-face targets.
    private func refreshCloseUps(for assetID: AssetID) async {
        closeUpCrops = []
        guard let previewURL = model.loupePreviewURL(for: assetID) else {
            model.setLoupeFaceFocuses([])
            return
        }
        let previewCacheGeneration = model.previewCacheGeneration(for: assetID)
        let result = await Task.detached(priority: .utility) { () -> (crops: [LoupeCloseUpCrop], reports: [FaceReport], faceFocuses: [LoupeZoomFocus]) in
            guard let faces = try? CoreImageFaceExpressionAnalyzer().detectFaces(previewURL: previewURL),
                  !faces.isEmpty,
                  let source = CGImageSourceCreateWithURL(previewURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return ([], [], [])
            }
            let reports = FaceReportAnalyzer().reports(in: image, detections: faces)
            let presentation = CloseUpFacesPresentation(
                faces: faces,
                imagePixelSize: CGSize(width: image.width, height: image.height)
            )
            let crops = presentation.crops.compactMap { crop -> LoupeCloseUpCrop? in
                guard reports.indices.contains(crop.faceIndex),
                      let croppedImage = image.cropping(to: crop.pixelRect) else {
                    return nil
                }
                return LoupeCloseUpCrop(id: crop.id, image: croppedImage, report: reports[crop.faceIndex])
            }
            let faceFocuses = faces.map { face in
                LoupeZoomFocus(x: face.normalizedBounds.midX, y: face.normalizedBounds.midY)
            }
            return (crops, reports, faceFocuses)
        }.value
        guard model.selectedAssetID == assetID else { return }
        closeUpCrops = result.crops
        faceReportStore.record(result.reports, for: assetID, previewCacheGeneration: previewCacheGeneration)
        model.setLoupeFaceFocuses(result.faceFocuses)
    }
```

- [ ] **Step 7: Run test to verify it passes**

Run: `swift test --filter CloseUpFacesPresentationTests 2>&1 | tail -5`
Expected: PASS — `Executed 6 tests, with 0 failures`.

- [ ] **Step 8: Prove the app target still builds and nothing regressed**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` (no unresolved references to `sharpnessTone`, `EyesState`, or `wholePhotoSignals`).

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2334 tests, with 0 failures` — 2339 minus the 7 deleted eyes/smile/sharpness-mark tests, plus the 2 new `faceIndex` tests. If the number differs, read the diff and confirm every removed test has a named successor from Step 1's list before continuing; a bare count drop with no successor is a coverage regression and must be fixed, not accepted.

- [ ] **Step 9: Commit**

```bash
git add Sources/TeststripApp/CloseUpFacesPresentation.swift \
        Sources/TeststripApp/LibraryGridView.swift \
        Tests/TeststripAppTests/CloseUpFacesPresentationTests.swift
git commit -m "feat: close-ups tiles render per-face chips, corner grade dots, and a header roll-up"
```

---

### Task 7: App — burst-rail roll-up dots and the stack sweep

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift:4825-4827` (add a second `.task(id:)` that runs the sweep), `:4831-4882` (`cullStackRailCell` dot overlay), `:4911-4915` (`stackChipAccessibilityValue`)
- Modify: `Sources/TeststripApp/FaceReportPresentation.swift` (add `railAccessibilityText(for:)`)
- Test: `Tests/TeststripAppTests/FaceReportRailDotTests.swift`

**Interfaces:**
- Consumes: `FaceReportStore.report(for:)`, `FaceReportStore.sweep(frames:currentFrameID:)`, `FaceReportSweepFrame(assetID:previewURL:previewCacheGeneration:)` (Task 4); `FaceReportRollUpPresentation.dotGrade(for:)/.color(for:)/.word(for:)` (Task 5); existing `CullingStackRailPresentation.Item`, `AppModel.loupePreviewURL(for:)`, `AppModel.previewCacheGeneration(for:)`.
- Produces:
  - `FaceReportRollUpPresentation.railAccessibilityText(for frame: FrameFaceReport?) -> String?`
  - `LoupeView.faceReportSweepFrames(for:)` and `private struct FaceReportSweepKey: Equatable` (view-internal; nothing later depends on them).

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripAppTests/FaceReportRailDotTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import TeststripCore
@testable import TeststripApp

/// The burst rail's one overlay dot per thumb: what it says, and — just as
/// load-bearing — when it says nothing at all.
final class FaceReportRailDotTests: XCTestCase {
    private static func report(sharpness: Double, prominence: Double = 0.2) -> FaceReport {
        FaceReport(
            normalizedBounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            eyesOpen: true,
            hasSmile: false,
            sharpness: sharpness,
            light: 0.9,
            facing: 0.9,
            prominence: prominence
        )
    }

    func testAnUncomputedFrameSaysNothing() {
        XCTAssertNil(FaceReportRollUpPresentation.railAccessibilityText(for: nil))
    }

    func testAFacelessFrameSaysNothing() {
        let frame = FrameFaceReport(reports: [], previewCacheGeneration: 1)

        // Absence means "nothing known", never "known good" — a faceless
        // frame must not announce a clean read.
        XCTAssertNil(FaceReportRollUpPresentation.railAccessibilityText(for: frame))
    }

    func testACleanFrameAnnouncesItsGrade() {
        let frame = FrameFaceReport(reports: [Self.report(sharpness: 0.9)], previewCacheGeneration: 1)

        XCTAssertEqual(FaceReportRollUpPresentation.railAccessibilityText(for: frame), "Faces clean")
    }

    func testARuinedFrameAnnouncesItsGrade() {
        let frame = FrameFaceReport(reports: [Self.report(sharpness: 0.05)], previewCacheGeneration: 1)

        XCTAssertEqual(FaceReportRollUpPresentation.railAccessibilityText(for: frame), "Faces ruined")
    }

    func testTheRailDotAndThePanelHeaderReadTheSameFrameTheSameWay() {
        let frame = FrameFaceReport(
            reports: [Self.report(sharpness: 0.45)],
            previewCacheGeneration: 1
        )

        let grade = FaceReportRollUpPresentation.dotGrade(for: frame)
        XCTAssertEqual(grade, .yellow)
        XCTAssertEqual(FaceReportRollUpPresentation.headerValue(for: frame), "1 face, Check")
        XCTAssertEqual(FaceReportRollUpPresentation.railAccessibilityText(for: frame), "Faces check")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FaceReportRailDotTests 2>&1 | tail -20`
Expected: FAIL — compile error `type 'FaceReportRollUpPresentation' has no member 'railAccessibilityText'`.

- [ ] **Step 3: Add the rail accessibility text**

In `Sources/TeststripApp/FaceReportPresentation.swift`, add to `FaceReportRollUpPresentation` below `headerValue(for:)`:

```swift
    /// What a rail thumb's dot says out loud. nil exactly when there is no
    /// dot: uncomputed, or the frame has no faces.
    static func railAccessibilityText(for frame: FrameFaceReport?) -> String? {
        guard let grade = dotGrade(for: frame) else { return nil }
        return "Faces \(word(for: grade).lowercased())"
    }
```

- [ ] **Step 4: Draw the rail dot**

In `Sources/TeststripApp/LibraryGridView.swift`, inside `cullStackRailCell`'s `ZStack(alignment: .bottomLeading)`, add after the `if item.isRecommended { … }` block (line 4861) and before the closing brace of the `ZStack`:

```swift
                    // Top-leading, clear of the ✦ (top-trailing) and the 3pt
                    // decision bar that runs across the very top. No dot at
                    // all while the frame is uncomputed or has no faces —
                    // absence means "nothing known", never "known good".
                    if let grade = FaceReportRollUpPresentation.dotGrade(for: faceReportStore.report(for: item.assetID)) {
                        Circle()
                            .fill(FaceReportRollUpPresentation.color(for: grade))
                            .frame(width: Self.faceGradeDotSize, height: Self.faceGradeDotSize)
                            .overlay { Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.top, 5)
                            .padding(.leading, 3)
                    }
```

- [ ] **Step 5: Put the roll-up into the rail cell's accessibility value**

Replace `stackChipAccessibilityValue` (lines 4911-4915):

```swift
    private func stackChipAccessibilityValue(_ item: CullingStackRailPresentation.Item) -> String {
        var segments = [item.isSelected ? "Selected" : (item.isRecommended ? "Recommended" : "Not selected")]
        segments.append(contentsOf: item.flawBadges.map(\.text))
        if let facesText = FaceReportRollUpPresentation.railAccessibilityText(
            for: faceReportStore.report(for: item.assetID)
        ) {
            segments.append(facesText)
        }
        return segments.joined(separator: ", ")
    }
```

- [ ] **Step 6: Start the sweep when the stack (or a frame's preview) changes**

In `Sources/TeststripApp/LibraryGridView.swift`, add a second `.task(id:)` immediately after the existing one on `cullingStackRail` (currently lines 4825-4827), leaving that one untouched:

```swift
            .task(id: presentation.items.map(\.assetID.rawValue).joined(separator: "\n")) {
                requestVisiblePreviews(for: presentation.items.map(\.assetID))
            }
            // A separate task from the preview request above: this one also
            // re-keys on preview generations, so frames skipped for want of a
            // cached preview get picked up the moment one lands. `.task(id:)`
            // cancels the running sweep when the key changes, which is the
            // whole cancellation story — no queue, no worker items.
            .task(id: faceReportSweepKey(for: presentation)) {
                await faceReportStore.sweep(
                    frames: faceReportSweepFrames(for: presentation),
                    currentFrameID: model.selectedAssetID
                )
            }
```

Add the two helpers next to `cullStackRailCell` (after line 4882):

```swift
    // Re-keys the sweep on the stack's membership, which frame is current
    // (it goes first), and each frame's preview generation.
    private struct FaceReportSweepKey: Equatable {
        var frameIDs: [String]
        var currentFrameID: String?
        var previewGenerations: [Int]
    }

    private func faceReportSweepKey(for presentation: CullingStackRailPresentation) -> FaceReportSweepKey {
        FaceReportSweepKey(
            frameIDs: presentation.items.map(\.assetID.rawValue),
            currentFrameID: model.selectedAssetID?.rawValue,
            previewGenerations: presentation.items.map { model.previewCacheGeneration(for: $0.assetID) }
        )
    }

    private func faceReportSweepFrames(for presentation: CullingStackRailPresentation) -> [FaceReportSweepFrame] {
        presentation.items.map { item in
            FaceReportSweepFrame(
                assetID: item.assetID,
                previewURL: model.loupePreviewURL(for: item.assetID),
                previewCacheGeneration: model.previewCacheGeneration(for: item.assetID)
            )
        }
    }
```

- [ ] **Step 7: Run test to verify it passes**

Run: `swift test --filter FaceReportRailDotTests 2>&1 | tail -5`
Expected: PASS — `Executed 5 tests, with 0 failures`.

- [ ] **Step 8: Run the full suite**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -5`
Expected: `Build complete!` then `Executed 2339 tests, with 0 failures`.

- [ ] **Step 9: Smoke-launch to prove the assembled app still starts**

Run: `./script/build_and_run.sh --verify-smoke 2>&1 | tail -20`
Expected: the verifier's success line; no crash, no unhandled error output.

- [ ] **Step 10: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift \
        Sources/TeststripApp/FaceReportPresentation.swift \
        Tests/TeststripAppTests/FaceReportRailDotTests.swift
git commit -m "feat: burst-rail roll-up dots fed by the face report store's stack sweep"
```

---

### Task 8: Fixture — a `facestack` seed with a real multi-frame face stack

The `faces` seed's 11 Wikimedia portraits carry no EXIF capture date at all (verified: `mdls -name kMDItemContentCreationDate` is `(null)` for every file), so `AssetStackBuilder.isCaptureTimeNeighbor` can never group them and the burst rail only ever shows a standalone single-frame entry. Without a multi-frame stack that contains real faces there is no way to prove live that rail dots appear for frames the photographer never visited. This task builds that fixture.

**Files:**
- Create: `Sources/TeststripBench/FaceStackFixtureSeeder.swift`
- Modify: `Sources/TeststripBench/BenchmarkCommand.swift:19-25` (case) and `:78-86` (parse)
- Modify: `Sources/TeststripBench/main.swift:37-50` (dispatch) and near `:378` (runner)
- Modify: `script/vm_scenario_run.sh:44-53` (variant docs), `:160-161` (`seed_dir_for`), `:181-193` (`seed_variant`), `:269` (launch usage string)
- Modify: `script/build_and_run.sh:45` (usage) and `:209-222` (flag block)
- Test: `Tests/TeststripBenchTests/FaceStackFixtureSeederTests.swift`

**Interfaces:**
- Consumes: existing `CoreImageFaceExpressionAnalyzer` (TeststripCore), `BenchmarkImageFixtures.writeJPEG(to:index:)`.
- Produces:
  - `public struct FaceStackFixtureSeederResult: Equatable` with `stackFilenames: [String]`, `singleCount: Int`, `stackCaptureGapSeconds: TimeInterval`.
  - `public struct FaceStackFixtureSeeder` with `public init(directory: URL, sourcePhotoDirectory: URL)` and `public func run() throws -> FaceStackFixtureSeederResult`, plus `public static let stackFaceFilenames: [String]` and `public static let stackNoFaceFilename: String`.
  - `BenchmarkCommand.seedFaceStackFixtures(directory: URL, sourcePhotoDirectory: URL)`.
  - A `facestack` seed variant for `script/vm_scenario_run.sh` and a `--face-stack` flag for `script/build_and_run.sh`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripBenchTests/FaceStackFixtureSeederTests.swift`:

```swift
import XCTest
import TeststripCore
@testable import TeststripBench

final class FaceStackFixtureSeederTests: XCTestCase {
    func testSeedFaceStackFixturesCommandParsesBothDirectories() throws {
        let command = BenchmarkCommand.parse([
            "TeststripBench", "seed-face-stack-fixtures", "/tmp/out", "/tmp/faces"
        ])

        XCTAssertEqual(
            command,
            .seedFaceStackFixtures(
                directory: URL(fileURLWithPath: "/tmp/out"),
                sourcePhotoDirectory: URL(fileURLWithPath: "/tmp/faces")
            )
        )
    }

    func testSeededStackFramesShareACaptureWindowAndTheRestDoNot() throws {
        guard let sourceDirectory = Self.facesCorpusDirectory() else {
            throw XCTSkip("No downloaded sample photos (run script/download_sample_photos.sh --manifest sample-data/faces.tsv --destination sample-data/photos/faces)")
        }
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try FaceStackFixtureSeeder(
            directory: directory,
            sourcePhotoDirectory: sourceDirectory
        ).run()

        XCTAssertEqual(result.stackFilenames.count, 3)
        XCTAssertGreaterThan(result.singleCount, 0)

        let provider = ImageIODecodeProvider()
        let stackCaptures = try result.stackFilenames.map { filename -> Date in
            try XCTUnwrap(provider.metadata(for: directory.appendingPathComponent(filename)).capturedAt)
        }
        // Chained adjacent gaps inside AssetStackBuilder's 2s window.
        for (earlier, later) in zip(stackCaptures, stackCaptures.dropFirst()) {
            XCTAssertLessThanOrEqual(later.timeIntervalSince(earlier), AssetStackBuilder.defaultMaximumCaptureGap)
            XCTAssertGreaterThan(later.timeIntervalSince(earlier), 0)
        }

        let singleFiles = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .filter { !result.stackFilenames.contains($0.lastPathComponent) }
        for single in singleFiles {
            let capturedAt = try XCTUnwrap(provider.metadata(for: single).capturedAt)
            let gapToStack = abs(capturedAt.timeIntervalSince(try XCTUnwrap(stackCaptures.last)))
            XCTAssertGreaterThan(gapToStack, AssetStackBuilder.defaultMaximumCaptureGap)
        }
    }

    func testTheStackCarriesTwoDetectableFacesAndOneDeliberatelyFacelessFrame() throws {
        guard let sourceDirectory = Self.facesCorpusDirectory() else {
            throw XCTSkip("No downloaded sample photos (run script/download_sample_photos.sh --manifest sample-data/faces.tsv --destination sample-data/photos/faces)")
        }
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try FaceStackFixtureSeeder(
            directory: directory,
            sourcePhotoDirectory: sourceDirectory
        ).run()

        let analyzer = CoreImageFaceExpressionAnalyzer()
        for filename in FaceStackFixtureSeeder.stackFaceFilenames {
            let faces = try analyzer.detectFaces(previewURL: directory.appendingPathComponent(filename))
            XCTAssertFalse(faces.isEmpty, "\(filename) must carry a detectable face for the rail-dot card")
        }
        // The falsification leg: a frame in the same stack with no faces at
        // all, which must never get a rail dot.
        let facelessURL = directory.appendingPathComponent(FaceStackFixtureSeeder.stackNoFaceFilename)
        XCTAssertEqual(try analyzer.detectFaces(previewURL: facelessURL), [])
        XCTAssertTrue(result.stackFilenames.contains(FaceStackFixtureSeeder.stackNoFaceFilename))
    }

    private static func facesCorpusDirectory() -> URL? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("sample-data/photos/faces")
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.contains { $0.pathExtension.lowercased() == "jpg" } ? directory : nil
    }

    private static func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-face-stack-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FaceStackFixtureSeederTests 2>&1 | tail -20`
Expected: FAIL — compile error `cannot find 'FaceStackFixtureSeeder' in scope`.

- [ ] **Step 3: Write the seeder**

Create `Sources/TeststripBench/FaceStackFixtureSeeder.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO
import TeststripCore
import UniformTypeIdentifiers

public struct FaceStackFixtureSeederResult: Equatable {
    public var stackFilenames: [String]
    public var singleCount: Int
    public var stackCaptureGapSeconds: TimeInterval

    public init(stackFilenames: [String], singleCount: Int, stackCaptureGapSeconds: TimeInterval) {
        self.stackFilenames = stackFilenames
        self.singleCount = singleCount
        self.stackCaptureGapSeconds = stackCaptureGapSeconds
    }
}

/// Writes the fixture the per-face report-card card needs: one folder where
/// three frames fall inside `AssetStackBuilder`'s capture window (so the
/// burst rail shows a real multi-frame stack) and everything else is hours
/// apart (so it stays a standalone stop). Two of the stack frames are real
/// portraits from the faces corpus; the third is deliberately faceless, which
/// is the card's falsification leg — a frame with no faces must never get a
/// rail dot.
///
/// The faces corpus itself carries no EXIF capture date, so the copies made
/// here get one written in. Originals in `sample-data/photos/faces` are never
/// modified.
public struct FaceStackFixtureSeeder {
    public static let stackFaceFilenames = ["stack-1-face.jpg", "stack-2-face.jpg"]
    public static let stackNoFaceFilename = "stack-3-noface.jpg"

    /// Portraits picked because both are single, well-lit, front-facing
    /// subjects that the live CIDetector pass reliably finds (`run()` asserts
    /// this, so a corpus change fails loudly instead of silently producing a
    /// faceless "face" stack).
    private static let stackSourceFilenames = [
        "commons-glenn-senator-portrait.jpg",
        "commons-ride-1984-portrait.jpg"
    ]

    /// 1s apart: comfortably inside the 2s window, and chained so all three
    /// frames land in one stack.
    private static let stackGapSeconds: TimeInterval = 1
    /// An hour apart: far outside the window, so every other photo is its own
    /// standalone stop.
    private static let singleGapSeconds: TimeInterval = 3600
    private static let baseCapture = Date(timeIntervalSince1970: 1_767_268_800) // 2026-01-01T12:00:00Z

    public var directory: URL
    public var sourcePhotoDirectory: URL

    public init(directory: URL, sourcePhotoDirectory: URL) {
        self.directory = directory
        self.sourcePhotoDirectory = sourcePhotoDirectory
    }

    public func run() throws -> FaceStackFixtureSeederResult {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, sourceName) in Self.stackSourceFilenames.enumerated() {
            let sourceURL = sourcePhotoDirectory.appendingPathComponent(sourceName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw TeststripError.invalidState("face stack fixture source missing: \(sourceURL.path)")
            }
            let destinationURL = directory.appendingPathComponent(Self.stackFaceFilenames[index])
            try Self.copyJPEG(
                from: sourceURL,
                to: destinationURL,
                capturedAt: Self.baseCapture.addingTimeInterval(Double(index) * Self.stackGapSeconds)
            )
            let faces = try CoreImageFaceExpressionAnalyzer().detectFaces(previewURL: destinationURL)
            guard !faces.isEmpty else {
                throw TeststripError.invalidState("face stack fixture \(sourceName) yielded no detectable face")
            }
        }

        let facelessURL = directory.appendingPathComponent(Self.stackNoFaceFilename)
        try BenchmarkImageFixtures.writeJPEG(to: facelessURL, index: 0)
        try Self.stampCapture(
            at: facelessURL,
            capturedAt: Self.baseCapture.addingTimeInterval(Double(Self.stackFaceFilenames.count) * Self.stackGapSeconds)
        )

        let remaining = try FileManager.default
            .contentsOfDirectory(at: sourcePhotoDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .filter { !Self.stackSourceFilenames.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for (index, sourceURL) in remaining.enumerated() {
            try Self.copyJPEG(
                from: sourceURL,
                to: directory.appendingPathComponent(sourceURL.lastPathComponent),
                capturedAt: Self.baseCapture.addingTimeInterval(Double(index + 1) * Self.singleGapSeconds)
            )
        }

        return FaceStackFixtureSeederResult(
            stackFilenames: Self.stackFaceFilenames + [Self.stackNoFaceFilename],
            singleCount: remaining.count,
            stackCaptureGapSeconds: Self.stackGapSeconds
        )
    }

    /// Re-encodes the source's own compressed image data with an added EXIF
    /// capture date — the pixels the face detector sees are the originals'.
    private static func copyJPEG(from sourceURL: URL, to destinationURL: URL, capturedAt: Date) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw TeststripError.io("could not read face stack fixture source \(sourceURL.lastPathComponent)")
        }
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        var exif = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        exif[kCGImagePropertyExifDateTimeOriginal] = exifTimestamp(capturedAt)
        properties[kCGImagePropertyExifDictionary] = exif
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw TeststripError.io("could not create face stack fixture \(destinationURL.lastPathComponent)")
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write face stack fixture \(destinationURL.lastPathComponent)")
        }
    }

    private static func stampCapture(at url: URL, capturedAt: Date) throws {
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).jpg")
        try copyJPEG(from: url, to: temporaryURL, capturedAt: capturedAt)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: temporaryURL, to: url)
    }

    /// EXIF DateTimeOriginal is "yyyy:MM:dd HH:mm:ss" and
    /// `ImageIODecodeProvider` parses it as UTC.
    private static func exifTimestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d:%02d:%02d %02d:%02d:%02d",
            parts.year ?? 2026,
            parts.month ?? 1,
            parts.day ?? 1,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
    }
}
```

- [ ] **Step 4: Wire the bench subcommand**

In `Sources/TeststripBench/BenchmarkCommand.swift`, add the case beside `seedGeoFixtures` (line 19):

```swift
    case seedFaceStackFixtures(directory: URL, sourcePhotoDirectory: URL)
```

and the parse branch beside the `seed-geo-fixtures` branch (line 81):

```swift
        if firstArgument == "seed-face-stack-fixtures" {
            let directory = userArguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
            let sourceDirectory = userArguments.dropFirst(2).first ?? FileManager.default.currentDirectoryPath
            return .seedFaceStackFixtures(
                directory: URL(fileURLWithPath: directory),
                sourcePhotoDirectory: URL(fileURLWithPath: sourceDirectory)
            )
        }
```

In `Sources/TeststripBench/main.swift`, add the dispatch arm beside `.seedGeoFixtures` (line 37):

```swift
case .seedFaceStackFixtures(let directory, let sourcePhotoDirectory):
    try runSeedFaceStackFixtures(directory: directory, sourcePhotoDirectory: sourcePhotoDirectory)
```

and the runner beside `runSeedGeoFixtures` (after line 387):

```swift
private func runSeedFaceStackFixtures(directory: URL, sourcePhotoDirectory: URL) throws {
    print("TeststripBench seed face stack fixtures")
    print("directory: \(directory.path)")
    print("source photos: \(sourcePhotoDirectory.path)")
    let result = try FaceStackFixtureSeeder(
        directory: directory,
        sourcePhotoDirectory: sourcePhotoDirectory
    ).run()
    print("stack frames: \(result.stackFilenames.joined(separator: ", "))")
    print("stack capture gap: \(result.stackCaptureGapSeconds)s")
    print("standalone frames: \(result.singleCount)")
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter FaceStackFixtureSeederTests 2>&1 | tail -8`
Expected: PASS — `Executed 3 tests, with 0 failures`. If the corpus is not downloaded, two of the three SKIP; run `script/download_sample_photos.sh --manifest sample-data/faces.tsv --destination sample-data/photos/faces` and re-run so all three actually execute before moving on.

- [ ] **Step 6: Add the `facestack` VM seed variant**

In `script/vm_scenario_run.sh`, add to the seed-variant doc block (after the `faces` line, line 52):

```bash
#   facestack sample-data/photos/faces re-stamped with EXIF capture times so
#             three frames (two real portraits + one deliberately faceless
#             frame) form one burst stack; for the per-face report-card card
```

extend `seed_dir_for` (line 160):

```bash
    smoke|smokebig|burst|geo|faces|facestack|empty) echo "$SEED_ROOT/$1" ;;
    *) echo "unknown seed variant: $1 (want smoke|smokebig|burst|geo|faces|facestack|empty)" >&2; exit 2 ;;
```

add the seeding arm beside `faces` (after line 193):

```bash
    facestack)
      local photos="$ROOT_DIR/sample-data/photos/faces"
      [[ -d "$photos" ]] || "$ROOT_DIR/script/download_sample_photos.sh" --manifest "$ROOT_DIR/sample-data/faces.tsv" --destination "$photos"
      # Originals land inside the seed dir, so the host->VM rsync ships them
      # and `launch`'s original_path prefix rewrite relocates them for free.
      ( cd "$ROOT_DIR" \
        && swift run TeststripBench seed-face-stack-fixtures "$dir/FaceStackOriginals" "$photos" \
        && swift run TeststripBench seed-sample-catalog "$dir" "$dir/FaceStackOriginals" )
      ;;
```

and extend the `launch` usage string (line 269):

```bash
  local variant="${1:?usage: $0 launch VARIANT (smoke|smokebig|burst|geo|faces|facestack|empty)}"
```

- [ ] **Step 7: Add the host `--face-stack` flag**

In `script/build_and_run.sh`, extend the usage line (line 45) by adding `|--face-stack|--verify-face-stack` to the alternatives, and add the flag block beside `--faces` (after line 222):

```bash
  --face-stack|face-stack)
    MODE="run"
    ISOLATED=1
    FACE_STACK=1
    ;;
  --verify-face-stack|verify-face-stack)
    MODE="--verify"
    ISOLATED=1
    FACE_STACK=1
    ;;
```

Declare the flag beside the other seed flags near line 22 (`FACE_STACK=0`), and seed it in the same place `SAMPLE_PHOTOS` is handled (near line 141), before the `seed-sample-catalog` call:

```bash
if [[ "$FACE_STACK" == "1" ]]; then
  FACE_STACK_PHOTOS="$ROOT_DIR/sample-data/photos/faces"
  if [[ ! -d "$FACE_STACK_PHOTOS" ]] || [[ -z "$(find "$FACE_STACK_PHOTOS" -maxdepth 1 -type f -print -quit)" ]]; then
    "$ROOT_DIR/script/download_sample_photos.sh" --manifest "$ROOT_DIR/sample-data/faces.tsv" --destination "$FACE_STACK_PHOTOS"
  fi
  swift run "$BENCH_PRODUCT_NAME" seed-face-stack-fixtures "$ISOLATED_APPLICATION_SUPPORT/FaceStackOriginals" "$FACE_STACK_PHOTOS"
  swift run "$BENCH_PRODUCT_NAME" seed-sample-catalog "$ISOLATED_APPLICATION_SUPPORT" "$ISOLATED_APPLICATION_SUPPORT/FaceStackOriginals"
fi
```

- [ ] **Step 8: Prove the seed variant actually produces a stack**

Run:
```bash
rm -rf "$TMPDIR/teststrip-vm-seeds/facestack" && \
  script/vm_scenario_run.sh sync facestack 2>&1 | tail -20 && \
  sqlite3 "$TMPDIR/teststrip-vm-seeds/facestack/Teststrip/catalog.sqlite" \
    "SELECT original_path, json_extract(technical_metadata_json, '\$.capturedAt') FROM assets ORDER BY 2;" | head -6
```
Expected: `sync complete`, and the first three rows are `stack-1-face.jpg`, `stack-2-face.jpg`, `stack-3-noface.jpg` with capture values 1 second apart; every later row is at least an hour after them.

- [ ] **Step 9: Run the full suite**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2342 tests, with 0 failures`.

- [ ] **Step 10: Commit**

```bash
git add Sources/TeststripBench/FaceStackFixtureSeeder.swift \
        Sources/TeststripBench/BenchmarkCommand.swift \
        Sources/TeststripBench/main.swift \
        Tests/TeststripBenchTests/FaceStackFixtureSeederTests.swift \
        script/vm_scenario_run.sh \
        script/build_and_run.sh
git commit -m "feat: facestack seed variant with a real multi-frame face stack fixture"
```

---

### Task 9: End-to-end — scenario card, live VM run, and cull-012 reconciliation

**Files:**
- Create: `test/scenarios/cull-028-face-report-cards.md`
- Modify: `test/scenarios/cull-012-closeups-panel.md` (reconcile the retired symbol-marks row and sharpness dot)

**Interfaces:**
- Consumes: everything from Tasks 1-8 as assembled and rendered — `Face close-ups` AX label and its header value, the per-tile `Face` element's value, the chips' `--help`/AX labels (`"Eyes 100%"` etc.), the rail cell's `Stack frame N` value with its `Faces clean|check|ruined` segment, and the `facestack` seed variant.
- Produces: a runnable scenario card; no code interfaces.

- [ ] **Step 1: Write the scenario card**

Create `test/scenarios/cull-028-face-report-cards.md`:

```markdown
# cull-028-face-report-cards: per-face report cards and burst-rail roll-up dots

**What this covers**: As a photographer culling a burst I want to see, per
face, whether the eyes are open, the face is sharp, the head is facing me, and
the light is right — and I want one traffic-light dot per rail thumb so I can
tell which frame has no ruined face *without visiting every frame*. SP-B of
`docs/superpowers/specs/2026-07-16-culling-flow-implementation-design.md`;
design in `docs/superpowers/specs/2026-07-31-per-face-report-cards-design.md`.

**Source**: `FaceReportAnalyzer` (`Sources/TeststripCore/Evaluation/FaceReportAnalyzer.swift`)
produces one `FaceReport` per CIDetector detection; `FaceReportStore`
(`Sources/TeststripApp/FaceReportStore.swift`) caches them per asset keyed on
`previewCacheGeneration` and sweeps the current stack's frames (current frame
first, then rail order); `closeUpsRail`/`closeUpCropCell`/`closeUpChips` and
`cullStackRailCell` in `Sources/TeststripApp/LibraryGridView.swift` render the
header roll-up, the per-tile corner dot and chip row, and the rail dots.

**No worker involvement.** Unlike `cull-012-closeups-panel.md`, this card needs
**no** Evaluate Matches pass, no `face_observations`, and no AuraFace CoreML
model: every number on screen comes from the app's own live CIDetector +
Vision pass over the cached preview. Do not wait on the worker.

## Pre-state
```bash
script/vm_scenario_run.sh sync facestack
script/vm_scenario_run.sh launch facestack
script/vm_scenario_run.sh ax wait-vended Teststrip
```

The `facestack` seed (Task 8 of the SP-B plan) is
`sample-data/photos/faces` re-stamped with EXIF capture times: three frames
1s apart form one burst stack — `stack-1-face.jpg` and `stack-2-face.jpg`
(real portraits, faces guaranteed present, asserted at seed time) plus
`stack-3-noface.jpg` (a synthetic flat frame with **no** faces, the
falsification leg) — and every other photo is an hour away, so it stays a
standalone stop.

## Steps

1. Confirm the fixture really is one three-frame stack before asserting
   anything about it:
   ```bash
   script/vm_scenario_run.sh sql facestack \
     "SELECT original_path, json_extract(technical_metadata_json,'\$.capturedAt') FROM assets ORDER BY 2 LIMIT 4;"
   ```
   Expect `stack-1-face.jpg`, `stack-2-face.jpg`, `stack-3-noface.jpg` in
   that order, 1s apart, then a fourth asset at least an hour later.

2. Switch to the Cull workspace (⌘1) and select `stack-1-face.jpg`. Wait for
   the close-ups panel, then read the rail:
   ```bash
   script/vm_scenario_run.sh ax wait --role AXStaticText --contains "CLOSE-UPS"
   script/vm_scenario_run.sh ax find --contains "Face close-ups"
   script/vm_scenario_run.sh ax find --contains "No faces"   # expect exit nonzero
   ```

3. **Chips.** Each face tile carries exactly four chips in fixed order —
   eyes, sharpness, facing, light — each with a `--help`/AX label of the form
   `"<Signal> NN%"` (or `"<Signal> no read"` when the signal could not be
   measured). Assert all four are present for the selected frame:
   ```bash
   for signal in Eyes Sharpness Facing Light; do
     script/vm_scenario_run.sh ax find --contains "$signal " || echo "MISSING $signal"
   done
   ```
   Then dump the matched tile element's raw AX attributes (the composed tile
   value lands on `AXValueDescription`, not `AXValue` — the SwiftUI-AX quirk
   `cull-012-closeups-panel.md`'s 2026-07-29 run documented for
   `.accessibilityElement(children: .combine)`; `ax_drive.sh --contains` does
   not search that attribute):
   ```bash
   script/vm_scenario_run.sh ax find --label "Face"
   ```
   The tile value must read `"<Clean|Check|Ruined>, Eyes <open|closed>"`
   optionally followed by `", Smiling"`. Cross-check by eye against the crop
   image itself (this detection is in-memory only; it is not queryable from
   sqlite).

4. **Panel header roll-up.** The `Face close-ups` element's accessibility
   value must be `"N faces, <Clean|Check|Ruined>"` for this frame — never
   `"Faces not read yet"` once the crops have rendered, and never `"No faces"`
   while a crop is on screen.

5. **Rail dots without visiting.** Without ever selecting frames 2 or 3, read
   the stack rail cells' accessibility values:
   ```bash
   script/vm_scenario_run.sh ax find --contains "Stack frame 2"
   script/vm_scenario_run.sh ax find --contains "Stack frame 3"
   ```
   Frame 2's value must carry a `Faces clean|check|ruined` segment (the sweep
   reached it without a visit). Frame 3's value must carry **no** `Faces`
   segment at all, and no dot must be drawn on its thumb — capture a
   screenshot and confirm the absence visually:
   ```bash
   script/vm_scenario_run.sh shell 'cd ~/teststrip-vm && ./script/capture_app_window.sh Teststrip'
   ```

6. **Panel and rail agree.** Still on frame 1, compare the grade word in the
   panel header value (step 4) with the grade word in frame 1's own rail-cell
   value. They must be the same word for the same frame.

7. **Nothing is written.** Capture catalog counts before step 2 and again
   after step 6:
   ```bash
   script/vm_scenario_run.sh sql facestack "SELECT count(*) FROM evaluation_signals;"
   script/vm_scenario_run.sh sql facestack "SELECT count(*) FROM face_observations;"
   script/vm_scenario_run.sh sql facestack "SELECT count(*) FROM person_assets;"
   ```
   and confirm no `.xmp` sidecar appeared next to any stack original:
   ```bash
   script/vm_scenario_run.sh shell 'ls ~/teststrip-vm/run/facestack-*/FaceStackOriginals/*.xmp 2>/dev/null | wc -l'
   ```

## Expected

- Step 2: the close-ups rail renders at least one crop for
  `stack-1-face.jpg`. **Fails if** the `"No faces"` empty state is present
  while a portrait is selected.
- Step 3: all four chips are present on every tile, in the order eyes,
  sharpness, facing, light, each carrying a `"<Signal> NN%"` or
  `"<Signal> no read"` string. **Fails if** any chip is missing (a missing
  chip would read as a clean signal), if a chip shows `0%` for a signal that
  was not measured, or if a smile glyph appears in the chip row (smile is
  hover/AX only).
- Step 4: the header value is `"N faces, <word>"` with N matching the frame's
  detected face count. **Fails if** it reads `"Faces not read yet"` after
  crops have rendered.
- Step 5: frame 2 carries a `Faces …` segment; frame 3 carries none and shows
  no dot. **Fails if** frame 2 has no `Faces …` segment (the sweep never
  reached an unvisited frame — the feature's headline claim), **and equally
  fails if** frame 3 *does* get a dot (a faceless frame reporting a grade
  would mean absence had been turned into "known good").
- Step 6: the two grade words are identical. **Fails if** the panel and the
  rail disagree about the same frame — they must come from one computation.
- Step 7: all three counts are unchanged and zero `.xmp` files exist. **Fails
  if** anything was written — per-face report cards are display-only and
  nothing here is a confirming gesture.

## Cleanup
```bash
script/vm_scenario_run.sh shell 'rm -rf ~/teststrip-vm/run/facestack-*'
```

## Sharp edges

- **Do not cross-check face counts against `face_observations`.** This card's
  numbers come from the app's own live CIDetector pass, which is a different
  detector from the worker's face pipeline and can legitimately disagree. The
  card deliberately never runs Evaluate Matches.
- `ax_drive.sh --contains` does not search `AXValueDescription`, where
  SwiftUI parks composed values for `.accessibilityElement(children:)`
  constructions. Steps 3-6 need a raw attribute dump of the matched element,
  not a `--contains` match, exactly as `cull-012-closeups-panel.md` and
  `cull-024-honest-states.md` both found live.
- Frame 3's dot ABSENCE is the falsification leg. Do not weaken it to "the
  dot is grey" or "the dot is missing sometimes" — absence must be total and
  stable across the whole run.
- The chip row is 4 × 17pt inside a 112pt tile. If it wraps or truncates in
  the screenshot, that is a real layout bug, not a card problem.
```

- [ ] **Step 2: Reconcile `cull-012-closeups-panel.md`**

Append a reconciliation entry to that card's Run status section, and correct
its Step 5 / Expected step 5 / Sharp edges text so it no longer describes the
retired symbol-marks row:

```markdown
**Reconciled 2026-08-01 (SP-B per-face report cards, docs-only, not a live
run)**: the compact on-face marks this card described — an `eye`/`eye.slash`
glyph, a conditional `face.smiling` glyph, and a green/orange sharpness dot
attached only when the asset had exactly one face crop — are **retired**. Each
tile now carries a corner traffic-light dot plus an always-on row of four
icon-in-donut chips (eyes, sharpness, facing, light), all four rendered every
time, each with a `"<Signal> NN%"` (or `"<Signal> no read"`) hover/AX string;
smile moved to the tile's accessibility value only. The single-face-only
sharpness attribution limit is gone with it: sharpness is now measured per
face over that face's own crop (`FaceReportAnalyzer`), so a 2+-face frame
shows a sharpness chip on **every** tile — the old "no crop shows Sharp/Soft
with 2+ faces" assertion in Step 5 and Expected step 5 is superseded and must
not be re-asserted. `CloseUpFacesPresentation` no longer has `eyesState`,
`isSmiling`, `sharpnessTone`, or a `wholePhotoSignals:` parameter; it owns
crop geometry plus a `faceIndex` pairing only. Everything else this card
covers is unchanged: the 112px crop size, the Cull-chrome-only gate, the
`"No faces"` empty state, and the display-only/nothing-persisted behavior.
The replacement assertions live in `cull-028-face-report-cards.md`.
```

- [ ] **Step 3: Run the card live in the VM**

Run, in order:
```bash
script/vm_scenario_run.sh setup
script/vm_scenario_run.sh sync facestack
script/vm_scenario_run.sh launch facestack
script/vm_scenario_run.sh ax wait-vended Teststrip
```
then drive the card's Steps 1-7 with `script/vm_scenario_run.sh ax …` /
`sql …` calls, re-asserting frontmost (`ax wait-vended`) on every poll during
any wait so the app never idle-wedges.

Expected: every Expected bullet holds. Record the outcome — pass, partial, or
fail with the exact evidence — in a new **Run status** entry at the bottom of
`test/scenarios/cull-028-face-report-cards.md`, including the app commit, the
VM name, and the seed variant, matching the format of the existing entries in
`cull-012-closeups-panel.md`.

- [ ] **Step 4: Fix anything the live run found**

If the run turns up a defect, fix it with a test-first cycle in the owning
task's files (analyzer bugs in Task 3's files, store bugs in Task 4's,
rendering bugs in Task 6/7's), re-run `swift test`, and re-drive the failing
card step before continuing. Do not weaken a card assertion to make it pass.

- [ ] **Step 5: Run the full host gate**

Run: `make verify 2>&1 | tail -20`
Expected: the gate's success line — unit tests, sandboxed build, and all
headless verifiers pass.

- [ ] **Step 6: Commit**

```bash
git add test/scenarios/cull-028-face-report-cards.md \
        test/scenarios/cull-012-closeups-panel.md
git commit -m "test: scenario card for per-face report cards and rail roll-up dots"
```

---

## Self-Review

Run after writing; findings were fixed inline before this plan was saved.

**1. Spec coverage**

| Spec requirement | Task |
| --- | --- |
| Prominence-weighted roll-up; below-floor face caps at yellow | Task 1 (`FaceReportGrading.grade`, `prominenceFloor`) + Task 4 (`rolledUpGrade`) |
| Tile = crop + corner traffic dot + always-on row of four icon-in-donut chips (17pt ring, sweep = score, monochrome icon) | Task 5 (`FaceSignalChipView`) + Task 6 (`closeUpCropCell`, `closeUpChips`) |
| Smile moves to hover/AX | Task 5 (`tileAccessibilityValue`), Task 6 (chip row has no smile) |
| Approach A: one Core analyzer + one central in-app store, no worker, no schema | Task 3 + Task 4; asserted negatively by Task 9 Step 7 |
| Existing fields carried through (bounds, eyes, smile); eye centers stay on `DetectedFaceExpression` | Task 3 (`reports(in:detections:)` carries them; `leftEyeCenter`/`rightEyeCenter` untouched) |
| facing from one `VNDetectFaceRectanglesRequest`, matched by greatest IoU, unmatched → nil | Task 2 + Task 3 (`VisionFaceOrientationDetector`) |
| light = existing `balancedExposure` over the crop's luminance | Task 3 (extracted into `PreviewPixelMetrics.balancedExposure`) |
| sharpness = existing neighbor-delta metric over the crop; retires the single-face `sharpnessTone` limit | Task 3 + Task 6 (`sharpnessTone` deleted) |
| prominence = face area / frame area, used for grading and sort order | Task 3 (`prominence`) + Task 6 (crops already sort largest-first) |
| Grade thresholds in one place with a WHY comment | Task 1 (`FaceReportGrading`) |
| Analyzer pure w.r.t. app state; failed Vision → `facing == nil`, never a fake green | Task 3 (`testFailedOrientationRequestLeavesEveryFacingUnscored`) |
| `@MainActor` observable cache keyed on `previewCacheGeneration`; stale → recompute | Task 4 |
| Sweep: current frame first, then rail order, off main actor, publishing progressively | Task 4 (`sweepOrder`, `sweep`) + Task 7 (`.task(id:)`) |
| Frames with no cached preview skipped, picked up on generation bump | Task 4 (two dedicated tests) + Task 7 (`FaceReportSweepKey` includes generations) |
| Cancellation on stack change; no queue, no worker items | Task 4 (`Task.isCancelled` legs) + Task 7 (`.task(id:)` cancellation) |
| Single computation source: `refreshCloseUps` feeds analyzer → store | Task 6 (`record(...)` from `refreshCloseUps`) |
| Burst-rail thumb: one overlay dot, top-leading, no dot while uncomputed or faceless | Task 7 |
| Panel roll-up: header dot + face count, panel and rail always agree | Task 5 (`headerValue`, `dotGrade`) + Task 6 + Task 7 (`testTheRailDotAndThePanelHeaderReadTheSameFrameTheSameWay`) |
| `SignalGlyphView` untouched; chip is a sibling | Task 5 (new file; `SignalGlyphView.swift` is in no task's Files list) |
| Out of scope respected (no persistence, no `EvaluationKind`, no `shutOK(context)`, no run-strip dots, no reads-card or verdict change) | No task touches `CullReadsCardPresentation`, `CullRunStripPresentation`, `EvaluationKind`, or any catalog write |
| Unit tests: analyzer, store, presentation — including the stated negatives | Tasks 1-7 |
| E2E scenario card, faces fixtures, VM, ABSENCE falsification leg | Task 8 (fixture) + Task 9 (card + live run) |

No gaps.

**2. Placeholder scan** — no "TBD", "TODO", "implement later", "add error handling", "similar to Task N", or bare "write tests" appears. Every code step carries the actual code; every test step carries the actual test; every run step carries the exact command and its expected output.

**3. Type consistency** — checked across tasks:
- `FaceReport(normalizedBounds:eyesOpen:hasSmile:sharpness:light:facing:prominence:)` is constructed identically in Tasks 3, 4, 5, and 7; `grade` is computed, never passed.
- `sharpness`, `light`, and `facing` are `Double?` everywhere (Task 1 declares them optional; Task 3 returns nil for unmeasurable crops; Task 5's chips render nil as an empty ring; Task 1's grading `compactMap`s them out).
- `FrameFaceReport(reports:previewCacheGeneration:)` and `rolledUpGrade` match between Task 4's definition and Tasks 5/7's use.
- `FaceReportRollUpPresentation` members are declared in Task 5 (`word`, `color`, `dotGrade`, `headerValue`, `tileAccessibilityValue`) and extended once in Task 7 (`railAccessibilityText`); Task 6 uses only Task 5's members.
- `FaceReportSweepFrame(assetID:previewURL:previewCacheGeneration:)` is built the same way in Task 4's tests and Task 7's `faceReportSweepFrames(for:)`.
- `faceGradeDotSize` is declared once (Task 6) and reused by Task 7's rail dot.
- `CloseUpFacesPresentation.Crop.faceIndex` is introduced in Task 6 and consumed only there.
- `DetectedFaceExpression.bothEyesShut` is added in Task 3 and used only by Task 3's analyzer (Task 6's rewritten presentation no longer computes eye state at all).
