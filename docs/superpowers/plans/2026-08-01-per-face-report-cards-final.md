# Per-Face Report Cards (SP-B) Implementation Plan — FINAL

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every detected face on a culling frame a scannable four-signal report card (eyes, sharpness, facing, light) plus a traffic-light grade, and roll those grades up to a dot on each burst-rail thumb so "which frame has no ruined face" is answerable without visiting frames.

**Architecture:** One pure Core analyzer (`FaceReportAnalyzer`) turns the preview `CGImage` plus the CIDetector detections the close-ups pass already produces into one `FaceReport` per face. One app-layer `FaceReportStore` caches `[AssetID: FrameFaceReport]` keyed on the preview-cache generation *and* the preview level it was analyzed at, and sweeps the current stack's frames off the main actor with plain structured concurrency. Two surfaces read the store through one staleness-checked accessor: the close-ups panel (per-face chips, per-tile corner dot, header roll-up) and the burst rail (one roll-up dot per thumb). Nothing is persisted, no worker involvement, no schema change.

**Tech Stack:** Swift 6 / SwiftPM (`swift-tools-version: 6.0`, `.macOS(.v14)`), SwiftUI + AppKit, CoreImage `CIDetector` (existing detections), Vision `VNDetectFaceRectanglesRequest` (yaw/pitch only), CoreGraphics pixel sampling via the existing `PreviewPixelMetrics`, XCTest.

**Provenance of this plan:** merged from `docs/superpowers/plans/2026-08-01-per-face-report-cards-strict.md` (left untouched as the record) after an adversarial two-judge review that ran the strict plan's Task 1-3 code over `sample-data/photos/faces`. Fifteen confirmed amendments are folded in; the most consequential is that every grading constant is now **measured**, not reasoned (Task 0), because the reasoned values mis-graded the corpus 1 green / 9 yellow / 1 red across 11 clean portraits.

## Global Constraints

- **Nothing persists.** No new `EvaluationKind`, no catalog write, no `.xmp` write, no worker/protocol/schema change. Per-face signals live in memory for the session only. (Spec "Out of scope"; parent spec's explicit exclusions.)
- **Never a fake score, never a fake green.** A signal that could not be measured is `nil` and renders an empty ring with a "no read" hover — it never contributes to a grade. A failed Vision request leaves `facing == nil`.
- **Absence means "nothing known", never "known good".** No rail dot while a frame is uncomputed or has no faces.
- **Prominence-weighted roll-up.** Red requires BOTH a red-grade signal AND `prominence >= FaceReportGrading.prominenceFloor`; a below-floor face grades at worst yellow.
- **Grades must not flap as previews upgrade.** Reports are analyzed only from a preview at or above `FaceReportPreviewFloor` (below it there is simply "no report yet"), and a report is stale — and re-read as absent — once its asset's preview generation bumps *or* a better level becomes available.
- **Chip row is quality signals only, always all four, in fixed order:** eyes, sharpness, facing, light. Smile moves to hover/AX.
- **Threshold constants live in one place with a WHY comment** (same discipline as `tooCloseToCallMargin`, `LibraryGridView.swift:6659`) and every WHY cites Task 0's measurement.
- **`SignalGlyphView` (`Sources/TeststripApp/SignalGlyphView.swift`) is untouched except for its stale doc comment** (lines 5-6 claim the report cards reuse it; they do not — the chip is a sibling). Task 6 corrects the comment and nothing else in that file.
- **No `shutOK(context)` eye-state cases** — no context provider exists; never fake it.
- **No change to the composite quality read or verdict math**, the reads card, the run strip, or compare surfaces.
- **Tests run with `swift test`.** Baseline before this work: 2281 executed / 5 skipped on a models-present checkout (a model-less worktree skips 10 more face-model tests; the 2281 executed figure is what the gates grep). Coverage must never go down: any deleted test must be superseded by a named replacement in the same commit.
- **Work on a WIP branch**, not `main`: `git checkout -b feat/per-face-report-cards` before Task 0.
- **Interactive UI verification runs in the Tart VM only**, via `script/vm_scenario_run.sh` — never on the host console. Building and `swift test` stay on the host.
- **Adversarial test split for Tasks 1A-4B.** For the analyzer, facing/matching, grading, and store tasks, the test-writing task and the implementation task are executed by **separate subagents**. The implementer may not modify, delete, weaken, or add to the test file it was handed. If the implementer believes a test is wrong, it stops and returns a **BLOCKED** report naming the test and the reason — it does not edit it. The reviewer enforces this with `git log --follow --oneline -- <test file>`, which must show exactly one commit (the A task's). Tasks 5-9 are single-agent.

## Frozen constants (filled by Task 0, Step 8 — Tasks 1A onward MUST NOT start until this table is filled and committed)

Each constant has a deterministic derivation rule below. Task 0 runs the measurement, computes the value from the rule, writes it into the "Measured value" column of *this* table, and commits. Every WHY comment in the code cites the row.

**Task 0 completed with two acceptance legs documented as not fully met — read `.superpowers/sdd/2026-08-01-face-report-cards/task-0-report.md` before Task 1A.** In short: (1) clean-corpus green rate is 9/11, not the gated ≥10/11 — `commons-glenn-1962`'s -56.2°/-56.95° head is mathematically capped below any workable `greenSignalFloor` once `zeroAtRadians` is held to ≤90° (required by Task 2A's own `testAtOrBeyondTheZeroAngleScoresZero`), and `commons-armstrong-eva-training.jpg` is a full-body EVA-suit photo whose face-through-visor is far softer/smaller than the other 10 "clean" portraits. (2) 19 of 21 prominence-qualifying blur/EV-3 derivatives grade red, not 21/21 — two `blur-heavy` derivatives read sharper than a genuinely-sharp, low-texture clean portrait (`commons-glenn-senator.jpg`) on the gradient-based focus-score metric, which is a metric limitation, not a threshold-choice problem (proven: no single `redSignalCeiling` can separate 0.3728/0.4677 from 0.4253 when 0.4253 is the value that must stay *above* the ceiling). Both gaps fail toward under-alarming (yellow/green), never toward a false red or a false green on a photo that should read red — no gate produced a fake green.

| Constant | Derivation rule (deterministic given Task 0's measurements) | Measured value |
| --- | --- | --- |
| `FaceReportGrading.greenSignalFloor` | The minimum, across the four signals, of that signal's 10th percentile over the 11 clean corpus portraits, rounded **down** to 2 decimals. Acceptance: at most 1 of the 11 clean portraits may grade non-green at the chosen preview floor. | `0.42` — min(sharpness p10, light p10) = min(0.4253, 0.7502) over 11 portraits at `.medium`, floored. Gate note: yields 9/11 green, not 10/11 (see callout above); a lower floor that rescues the 10th is fragile — flaps green/yellow between `.medium` and `.original` (see report). |
| `FaceReportGrading.redSignalCeiling` | Midway between the clean corpus's 5th percentile and the synthesized-defect class's 95th percentile for the same signal, rounded to 2 decimals, taken as the value satisfying both acceptance legs. Acceptance: every synthesized ruined derivative (heavy blur; ±3EV exposure) grades red, and **no** clean portrait grades red. | `0.33` — highest 2-decimal value keeping `zeroAtRadians <= 90°` (see next row) while maximizing blur/EV-3 catch rate; exhaustive sweep of 0.20-0.36 found 0.33 gives the best catch rate (19/21) with the largest safety margin (0.0078) among values achieving it. Zero clean portraits red (floor 0.4253, 9.5% headroom). |
| `FaceFacingScore.zeroAtRadians` | Smallest value in whole degrees such that the corpus's strongest off-axis head (measured yaw — the strict plan's probe found `commons-glenn-1962` at yaw −56.2°, a usable frame) scores **at or above** `redSignalCeiling`, i.e. `zeroAtRadians >= 56.2° / (1 − redSignalCeiling)`. | `86°` (code: `Double.pi * 86 / 180`) — `ceil(56.95312.../(1-0.33)) = 86`; fresh measurement (real `PreviewRenderer`, all 4 levels) puts this head's worst yaw at 56.953° (original level), exceeding the plan's assumed 56.2° — used the real, higher number. |
| `FaceFacingScore.minimumBoxOverlap` | 0.8 × the **minimum** IoU observed across all correctly-matched CIDetector↔Vision pairs at **every** ladder level, rounded **down** to 2 decimals. The binding case found by the probe is IoU 0.228 at 1600px for a pair that scores 0.510 at 512px. | `0.14` — `0.8 × 0.1809`, the worst correctly-matched IoU across all 4 levels (`.medium`, `commons-armstrong-eva-training.jpg`; visually confirmed as a genuine same-face match with a box-overlay render, not a spurious pairing), floored. |
| `FaceReportGrading.prominenceFloor` | Geometric midpoint between the smallest measured subject-face area fraction and the largest measured background-face area fraction on the synthesized composite fixture, rounded to 3 decimals. | `0.021` — `sqrt(0.15929 × 0.00286)`, over composite fixtures at every level. Fixture note: the brief's `sources[0]`/`sources[1]` background pick landed on an undetectable face; re-ranked by measured face strength, and gave the background an independent -3EV crush so it is actually red-eligible (a merely-small clean face can't test the cap) — see full report. |
| `FaceReportPreviewFloor.lowestAcceptedLevel` | The lowest ladder level at which **every** clean corpus portrait's grade equals its grade at `.original`, and at which `facing` is non-nil for every portrait whose `facing` is non-nil at `.original`. Recommended and expected: `.medium`. | `.medium` — grid disagrees with `.original` for `commons-armstrong-gemini8.jpg` (yellow vs. green); medium and large both match `.original` exactly for all 11 clean portraits, and `facing` is non-nil for all 11 at every level. |

---

### Task 0: Measure the constants before writing any of them down

The strict plan's reasoned constants are empirically wrong: run over the faces corpus they grade 11 clean portraits as 1 green / 9 yellow / 1 red, `commons-glenn-1962` grades **red** on `facing = 0.064` alone (yaw −56.2°, a perfectly usable frame), and `minimumBoxOverlap = 0.3` rejects a correct CIDetector↔Vision match at IoU 0.228 (1600px) that the same pair scores 0.510 at 512px. Grades also flap across the preview ladder — green at 512px, yellow at 1600px and above; `facing` scored at 512px, nil at 1600px and above. Every constant in the frozen table above comes out of this task.

**Files:**
- Create (scratch, never committed to `Sources/`): `<scratchpad>/face-report-calibration/main.swift` and `<scratchpad>/face-report-calibration/run.sh`
- Modify: `docs/superpowers/plans/2026-08-01-per-face-report-cards-final.md` (fill the frozen-constants table)
- Modify: the SDD ledger under `.superpowers/sdd/` for this feature (record the measurement run and the derived values)

**Interfaces:**
- Consumes: `PreviewRenderer().render(sourceURL:level:destinationURL:)`, `PreviewLevel`, `CoreImageFaceExpressionAnalyzer().detectFaces(previewURL:)` — all existing public TeststripCore API.
- Produces: no code interfaces. Produces the six frozen constant values, and the per-level grade/signal tables recorded in the SDD ledger.

- [ ] **Step 1: Make sure the corpus is on disk**

Run:
```bash
ls sample-data/photos/faces/*.jpg | wc -l
```
Expected: `11`. If it prints `0`, run `script/download_sample_photos.sh --manifest sample-data/faces.tsv --destination sample-data/photos/faces` first.

- [ ] **Step 2: Synthesize the missing negative classes**

The corpus is 11 clean, well-exposed, sharp portraits — it contains no ruined faces, so it cannot by itself locate a red threshold. Derive the negatives deterministically from it. Write `<scratchpad>/face-report-calibration/derive.swift`:

```swift
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Deterministic defect derivatives of the clean corpus: the same subject,
// exactly one thing wrong. Filenames encode the class so the probe can bucket
// them without a manifest.
let arguments = CommandLine.arguments
let sourceDirectory = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let context = CIContext()

func write(_ image: CIImage, to url: URL) throws {
    guard let cgImage = context.createCGImage(image, from: image.extent),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
        fatalError("could not write \(url.lastPathComponent)")
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not finalize \(url.lastPathComponent)") }
}

let sources = try FileManager.default
    .contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension.lowercased() == "jpg" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

for source in sources {
    guard let input = CIImage(contentsOf: source) else { continue }
    let stem = source.deletingPathExtension().lastPathComponent

    // Soft: gaussian blur at two strengths, as a fraction of the image's
    // short edge so the defect is scale-independent.
    let shortEdge = min(input.extent.width, input.extent.height)
    for (label, fraction) in [("blur-mild", 0.004), ("blur-heavy", 0.012)] {
        let blurred = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(shortEdge) * fraction)
            .cropped(to: input.extent)
        try write(blurred, to: outputDirectory.appendingPathComponent("\(stem)__\(label).jpg"))
    }

    // Light: exposure shifts in stops. +-1EV is "off but usable", +-3EV is
    // blown/crushed.
    for stops in [-3.0, -1.0, 1.0, 3.0] {
        guard let filter = CIFilter(name: "CIExposureAdjust") else { continue }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(stops, forKey: kCIInputEVKey)
        guard let output = filter.outputImage else { continue }
        let label = stops < 0 ? "ev-minus\(Int(-stops))" : "ev-plus\(Int(stops))"
        try write(output, to: outputDirectory.appendingPathComponent("\(stem)__\(label).jpg"))
    }
}

// Prominence/multi-face: one composite per pairing of the two strongest
// portraits — full-frame subject plus the same second portrait downscaled
// into the top-right corner as a background face.
if sources.count >= 2,
   let subject = CIImage(contentsOf: sources[0]),
   let background = CIImage(contentsOf: sources[1]) {
    for backgroundWidthFraction in [0.06, 0.10, 0.16] {
        let scale = (subject.extent.width * backgroundWidthFraction) / background.extent.width
        let inset = subject.extent.width * 0.04
        let scaled = background
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let placed = scaled.transformed(by: CGAffineTransform(
            translationX: subject.extent.maxX - scaled.extent.width - inset,
            y: subject.extent.maxY - scaled.extent.height - inset
        ))
        let composite = placed.composited(over: subject).cropped(to: subject.extent)
        let label = String(format: "composite-%02d", Int(backgroundWidthFraction * 100))
        try write(composite, to: outputDirectory.appendingPathComponent("\(label).jpg"))
    }
}
print("derived \(try FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil).count) fixtures")
```

Run:
```bash
mkdir -p "$SCRATCH/face-report-calibration"
swift "$SCRATCH/face-report-calibration/derive.swift" \
  sample-data/photos/faces "$SCRATCH/face-report-calibration/derived"
```
Expected: `derived 69 fixtures` (11 originals × 6 defect derivatives + 3 composites). If the composite count is 0, the corpus has fewer than 2 files — stop and fix Step 1.

- [ ] **Step 3: Render every fixture at every ladder level through the real renderer**

Do not hand-roll a resize: the probe must see exactly the bytes the app will see. Write `<scratchpad>/face-report-calibration/render.swift`:

```swift
import Foundation
import TeststripCore

let arguments = CommandLine.arguments
let inputDirectories = arguments[1].split(separator: ":").map { URL(fileURLWithPath: String($0)) }
let outputRoot = URL(fileURLWithPath: arguments[2])
let renderer = PreviewRenderer()

for directory in inputDirectories {
    let sources = try FileManager.default
        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension.lowercased() == "jpg" }
    for source in sources {
        for level in [PreviewLevel.grid, .medium, .large, .original] {
            let destination = outputRoot
                .appendingPathComponent(level.rawValue, isDirectory: true)
                .appendingPathComponent(source.lastPathComponent)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try renderer.render(sourceURL: source, level: level, destinationURL: destination)
        }
    }
}
print("rendered")
```

Run it with the package's own module search path so `import TeststripCore` resolves:
```bash
swift build 2>&1 | tail -2
swiftc -I .build/debug -L .build/debug -lTeststripCore \
  "$SCRATCH/face-report-calibration/render.swift" \
  -o "$SCRATCH/face-report-calibration/render"
"$SCRATCH/face-report-calibration/render" \
  "$PWD/sample-data/photos/faces:$SCRATCH/face-report-calibration/derived" \
  "$SCRATCH/face-report-calibration/levels"
```
Expected: `rendered`, and `ls "$SCRATCH/face-report-calibration/levels"` shows `grid medium large original`.

- [ ] **Step 4: Write the probe harness**

This is the strict plan's Task 1B/2B/3B math inlined verbatim, with the constants left as *inputs* and every raw signal printed rather than graded — the whole point is to see the distributions before choosing thresholds. Write `<scratchpad>/face-report-calibration/probe.swift`:

```swift
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import TeststripCore
import Vision

// --- the math under calibration, inlined so the probe has no dependency on
// --- unwritten production types ---

func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> Double {
    let intersection = lhs.intersection(rhs)
    guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
    let intersectionArea = Double(intersection.width * intersection.height)
    let unionArea = Double(lhs.width * lhs.height) + Double(rhs.width * rhs.height) - intersectionArea
    guard unionArea > 0 else { return 0 }
    return intersectionArea / unionArea
}

func rgbaSamples(of image: CGImage, side: Int) -> [UInt8]? {
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let ok: Bool = pixels.withUnsafeMutableBytes { buffer in
        guard let baseAddress = buffer.baseAddress,
              let context = CGContext(
                data: baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { return false }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return true
    }
    return ok ? pixels : nil
}

func luminance(_ pixels: [UInt8], _ x: Int, _ y: Int, _ side: Int) -> Double {
    let index = (y * side + x) * 4
    return 0.2126 * Double(pixels[index]) / 255.0
        + 0.7152 * Double(pixels[index + 1]) / 255.0
        + 0.0722 * Double(pixels[index + 2]) / 255.0
}

func focusScore(_ pixels: [UInt8], _ side: Int) -> Double {
    var total = 0.0
    var count = 0
    for y in 0..<side {
        for x in 0..<side {
            let current = luminance(pixels, x, y, side)
            if x + 1 < side { total += abs(current - luminance(pixels, x + 1, y, side)); count += 1 }
            if y + 1 < side { total += abs(current - luminance(pixels, x, y + 1, side)); count += 1 }
        }
    }
    guard count > 0 else { return 0 }
    return min(max((total / Double(count)) / 0.15, 0.0), 1.0)
}

func meanLuminance(_ pixels: [UInt8], _ side: Int) -> Double {
    var total = 0.0
    for y in 0..<side { for x in 0..<side { total += luminance(pixels, x, y, side) } }
    return total / Double(side * side)
}

func balancedExposure(_ mean: Double) -> Double { 1.0 - min(abs(mean - 0.5) * 2.0, 1.0) }

// --- probe ---

let sampleSide = 16
let minimumCropPixels = 8
let levelRoot = URL(fileURLWithPath: CommandLine.arguments[1])

print("level\tfile\tface\tprominence\teyesOpen\tsharpness\tlight\tyawDeg\tpitchDeg\tbestIoU")

for level in ["grid", "medium", "large", "original"] {
    let directory = levelRoot.appendingPathComponent(level, isDirectory: true)
    let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension.lowercased() == "jpg" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    for file in files {
        guard let detections = try? CoreImageFaceExpressionAnalyzer().detectFaces(previewURL: file),
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }

        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let observations = (request.results ?? []).map { observation -> (CGRect, Double?, Double?) in
            (
                CGRect(
                    x: observation.boundingBox.minX,
                    y: 1.0 - observation.boundingBox.maxY,
                    width: observation.boundingBox.width,
                    height: observation.boundingBox.height
                ),
                observation.yaw?.doubleValue,
                observation.pitch?.doubleValue
            )
        }

        for (faceIndex, detection) in detections.enumerated() {
            let bounds = detection.normalizedBounds
            let prominence = Double(bounds.width * bounds.height)

            let pixelRect = CGRect(
                x: (Double(bounds.minX) * Double(image.width)).rounded(.down),
                y: (Double(bounds.minY) * Double(image.height)).rounded(.down),
                width: (Double(bounds.width) * Double(image.width)).rounded(),
                height: (Double(bounds.height) * Double(image.height)).rounded()
            ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

            var sharpness = "nil"
            var light = "nil"
            if pixelRect.width >= Double(minimumCropPixels),
               pixelRect.height >= Double(minimumCropPixels),
               let crop = image.cropping(to: pixelRect),
               let samples = rgbaSamples(of: crop, side: sampleSide) {
                sharpness = String(format: "%.4f", focusScore(samples, sampleSide))
                light = String(format: "%.4f", balancedExposure(meanLuminance(samples, sampleSide)))
            }

            var bestIoU = 0.0
            var yaw: Double?
            var pitch: Double?
            for (observationBounds, observationYaw, observationPitch) in observations {
                let overlap = intersectionOverUnion(bounds, observationBounds)
                if overlap > bestIoU {
                    bestIoU = overlap
                    yaw = observationYaw
                    pitch = observationPitch
                }
            }

            print([
                level,
                file.lastPathComponent,
                "\(faceIndex)",
                String(format: "%.5f", prominence),
                detection.leftEyeClosed && detection.rightEyeClosed ? "0" : "1",
                sharpness,
                light,
                yaw.map { String(format: "%.2f", $0 * 180 / .pi) } ?? "nil",
                pitch.map { String(format: "%.2f", $0 * 180 / .pi) } ?? "nil",
                String(format: "%.4f", bestIoU)
            ].joined(separator: "\t"))
        }
    }
}
```

Build and run:
```bash
swiftc -I .build/debug -L .build/debug -lTeststripCore \
  "$SCRATCH/face-report-calibration/probe.swift" \
  -o "$SCRATCH/face-report-calibration/probe"
"$SCRATCH/face-report-calibration/probe" "$SCRATCH/face-report-calibration/levels" \
  > "$SCRATCH/face-report-calibration/measurements.tsv"
wc -l "$SCRATCH/face-report-calibration/measurements.tsv"
```
Expected: several hundred rows (roughly 4 levels × 69+ fixtures × ≥1 face each), header row included.

- [ ] **Step 5: Read the distributions**

Run:
```bash
cd "$SCRATCH/face-report-calibration"
# Clean-corpus rows only (no "__" defect suffix, no composite).
awk -F'\t' 'NR>1 && $2 !~ /__/ && $2 !~ /^composite/ {print}' measurements.tsv > clean.tsv
# Per level, per signal: min / p05 / p10 / median over the clean portraits.
for level in grid medium large original; do
  for column in 6 7; do
    awk -F'\t' -v L="$level" -v C="$column" '$1==L && $C!="nil" {print $C}' clean.tsv \
      | sort -n \
      | awk -v L="$level" -v C="$column" '{v[NR]=$1} END {
          if (NR==0) {print L"\tcol"C"\tNO DATA"; exit}
          printf "%s\tcol%s\tn=%d\tmin=%.4f\tp05=%.4f\tp10=%.4f\tmed=%.4f\n",
            L, C, NR, v[1], v[int(NR*0.05)+1], v[int(NR*0.10)+1], v[int(NR*0.5)+1]
        }'
  done
  # facing inputs and match overlap
  awk -F'\t' -v L="$level" '$1==L {print $8"\t"$10}' clean.tsv \
    | awk -v L="$level" '$1!="nil" {a=($1<0?-$1:$1); if(a>maxyaw) maxyaw=a; if(min==""||$2<min) min=$2; n++}
        END {printf "%s\tmaxAbsYawDeg=%.2f\tminMatchedIoU=%.4f\tposeRows=%d\n", L, maxyaw, min, n}'
done
# Defect classes: how bad does a ruined face actually score?
for class in blur-heavy blur-mild ev-plus3 ev-minus3 ev-plus1 ev-minus1; do
  awk -F'\t' -v K="$class" '$1=="medium" && index($2,K)>0 && $6!="nil" {print $6}' measurements.tsv \
    | sort -n | awk -v K="$class" '{v[NR]=$1} END {if(NR)printf "%s sharpness n=%d p95=%.4f max=%.4f\n", K, NR, v[int(NR*0.95)+1], v[NR]}'
  awk -F'\t' -v K="$class" '$1=="medium" && index($2,K)>0 && $7!="nil" {print $7}' measurements.tsv \
    | sort -n | awk -v K="$class" '{v[NR]=$1} END {if(NR)printf "%s light      n=%d p95=%.4f max=%.4f\n", K, NR, v[int(NR*0.95)+1], v[NR]}'
done
# Composite: subject vs background face area fractions.
awk -F'\t' '$1=="medium" && $2 ~ /^composite/ {print $2"\tface"$3"\tprominence="$4}' measurements.tsv
```
Expected: one summary line per level per signal, a `maxAbsYawDeg`/`minMatchedIoU` line per level, p95/max per defect class, and two prominence rows per composite fixture (a large subject and a small background face).

- [ ] **Step 6: Derive each constant from its rule**

Apply the frozen-constants table's derivation rules to the Step 5 output, longhand, writing the arithmetic down as you go:

1. `greenSignalFloor` = min over signals of that signal's p10 at the chosen level, rounded **down** to 2 decimals.
2. `redSignalCeiling` = the value midway between the clean p05 and the ruined-class p95, rounded to 2 decimals, that satisfies both acceptance legs (all `blur-heavy` and `ev-±3` derivatives red; no clean portrait red).
3. `zeroAtRadians` = smallest whole-degree value ≥ `maxAbsYawDeg / (1 − redSignalCeiling)`, expressed in the code as `Double.pi * <degrees> / 180`.
4. `minimumBoxOverlap` = `0.8 × minMatchedIoU` taken over **all four** levels, rounded **down** to 2 decimals.
5. `prominenceFloor` = `sqrt(smallestSubjectProminence × largestBackgroundProminence)`, rounded to 3 decimals.
6. `FaceReportPreviewFloor.lowestAcceptedLevel` = lowest level whose per-portrait grade vector (recomputed with the constants above) equals the `.original` vector, and whose `facing` non-nil set equals `.original`'s.

- [ ] **Step 7: Verify the derived constants against the acceptance legs**

Re-run the probe output through the chosen constants:
```bash
cd "$SCRATCH/face-report-calibration"
GREEN=<greenSignalFloor>; RED=<redSignalCeiling>; FLOOR=<prominenceFloor>; ZERO_DEG=<zeroAtRadians in degrees>
awk -F'\t' -v G="$GREEN" -v R="$RED" -v P="$FLOOR" -v Z="$ZERO_DEG" -v L=<lowestAcceptedLevel> '
  $1==L {
    worst = ($5=="1") ? 1.0 : 0.0
    if ($6!="nil" && $6+0 < worst) worst = $6+0
    if ($7!="nil" && $7+0 < worst) worst = $7+0
    if ($8!="nil") { a=($8<0?-$8:$8); f=1-a/Z; if(f<0)f=0; if(f<worst) worst=f }
    grade = (worst < R) ? (($4+0 >= P) ? "red" : "yellow") : ((worst < G) ? "yellow" : "green")
    print grade"\t"$2"\t"$3
  }' measurements.tsv | sort | uniq -c | sort -rn | head -20
```
Expected, and each is a hard gate — if any fails, go back to Step 6 and re-derive rather than shipping the value:
- Clean portraits (rows with no `__` and not `composite`): **at least 10 of 11 green, zero red.**
- Every `blur-heavy` and `ev-plus3`/`ev-minus3` derivative: **red.**
- `commons-glenn-1962` (the −56.2° head): **not red.**
- Composite fixtures: the background face's own grade may be anything, but the frame's worst grade must be **yellow, not red** — proving the prominence floor caps a bystander.

- [ ] **Step 8: Freeze the values into this plan and the ledger**

Edit this file's "Frozen constants" table, replacing every `_(Task 0)_` with the derived value, and add one sentence per row recording the measurement it came from (e.g. "clean p10 = 0.63 over 11 portraits at `.medium`"). Then record the same six values, the acceptance-leg results from Step 7, and the path to `measurements.tsv` in this feature's SDD ledger under `.superpowers/sdd/`.

- [ ] **Step 9: Commit**

```bash
git add docs/superpowers/plans/2026-08-01-per-face-report-cards-final.md .superpowers/sdd/
git commit -m "docs: measure per-face report-card grading constants from the faces corpus"
```

**Gate:** Task 1A must not begin until this commit exists and the frozen-constants table has no `_(Task 0)_` cells left.

---

### Task 1A: Write the failing tests for `FaceReport` and its grading rule

**Adversarial split:** this task writes tests only. It creates no file under `Sources/`. Task 1B's implementer may not touch the file this task commits.

**Files:**
- Test: `Tests/TeststripCoreTests/FaceReportGradingTests.swift`

**Interfaces:**
- Consumes: the frozen-constants table (Task 0). Substitute the measured `greenSignalFloor`, `redSignalCeiling`, and `prominenceFloor` values wherever the test comments below say so — the tests must exercise the *real* bands, not the placeholder numbers this file was drafted against.
- Produces: a red test file pinning the API Task 1B must implement — `FaceReportGrade`, `FaceReportGrading.grade(eyesOpen:sharpness:light:facing:prominence:)`, and `FaceReport(normalizedBounds:eyesOpen:hasSmile:sharpness:light:facing:prominence:)` with computed `eyesScore` and `grade`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripCoreTests/FaceReportGradingTests.swift`. Every literal marked `<…>` is read from the frozen-constants table and written in as a number; the surrounding comment records which band it sits in.

```swift
import CoreGraphics
import XCTest
@testable import TeststripCore

final class FaceReportGradingTests: XCTestCase {
    // Sample points chosen relative to the measured bands (Task 0): `clean`
    // sits above greenSignalFloor, `middling` strictly between the two
    // constants, `ruined` strictly below redSignalCeiling.
    private static let clean = <a value >= greenSignalFloor, e.g. greenSignalFloor + 0.15, capped at 1.0>
    private static let middling = <midpoint of redSignalCeiling and greenSignalFloor>
    private static let ruined = <a value < redSignalCeiling, e.g. redSignalCeiling / 2>
    private static let prominentArea = <a value >= prominenceFloor, e.g. prominenceFloor * 20>
    private static let bystanderArea = <a value < prominenceFloor, e.g. prominenceFloor / 10>

    func testEveryCleanSignalGradesGreen() {
        XCTAssertEqual(
            FaceReportGrading.grade(
                eyesOpen: true,
                sharpness: Self.clean,
                light: Self.clean,
                facing: Self.clean,
                prominence: Self.prominentArea
            ),
            .green
        )
    }

    func testMiddlingSignalGradesYellow() {
        XCTAssertEqual(
            FaceReportGrading.grade(
                eyesOpen: true,
                sharpness: Self.middling,
                light: Self.clean,
                facing: Self.clean,
                prominence: Self.prominentArea
            ),
            .yellow
        )
    }

    func testRedSignalOnAProminentFaceGradesRed() {
        XCTAssertEqual(
            FaceReportGrading.grade(
                eyesOpen: true,
                sharpness: Self.ruined,
                light: Self.clean,
                facing: Self.clean,
                prominence: Self.prominentArea
            ),
            .red
        )
    }

    // The prominence-weighted roll-up's whole point: a bystander can flag
    // yellow but must never grade a frame red.
    func testRedSignalBelowTheProminenceFloorCapsAtYellow() {
        XCTAssertEqual(
            FaceReportGrading.grade(
                eyesOpen: true,
                sharpness: Self.ruined,
                light: Self.clean,
                facing: Self.clean,
                prominence: Self.bystanderArea
            ),
            .yellow
        )
    }

    func testClosedEyesAreARedGradeSignalOnAProminentFace() {
        XCTAssertEqual(
            FaceReportGrading.grade(
                eyesOpen: false,
                sharpness: Self.clean,
                light: Self.clean,
                facing: Self.clean,
                prominence: Self.prominentArea
            ),
            .red
        )
    }

    func testUnscoredSignalsNeverContributeAGrade() {
        // nil facing/sharpness/light must not read as 0 — that would fake a red.
        XCTAssertEqual(
            FaceReportGrading.grade(
                eyesOpen: true,
                sharpness: nil,
                light: nil,
                facing: nil,
                prominence: Self.prominentArea
            ),
            .green
        )
    }

    // The corpus regression Task 0 exists to prevent: a usable off-axis head
    // (commons-glenn-1962, yaw -56.2 degrees) must not grade red on facing
    // alone. `zeroAtRadians` is chosen so that head scores at or above
    // redSignalCeiling.
    func testAUsableOffAxisHeadDoesNotGradeRedOnFacingAlone() {
        let facing = FaceFacingScore.score(yawRadians: -56.2 * .pi / 180, pitchRadians: 0)
        XCTAssertNotEqual(
            FaceReportGrading.grade(
                eyesOpen: true,
                sharpness: Self.clean,
                light: Self.clean,
                facing: facing,
                prominence: Self.prominentArea
            ),
            .red
        )
    }

    func testFaceReportDerivesItsGradeFromItsOwnScores() {
        let report = FaceReport(
            normalizedBounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            eyesOpen: true,
            hasSmile: false,
            sharpness: Self.ruined,
            light: Self.clean,
            facing: Self.clean,
            prominence: Self.prominentArea
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

Note the off-axis test depends on `FaceFacingScore` from Task 2B. Tasks 1B and 2B therefore land before this file goes green; that is expected and is why Step 2's red is a compile failure naming both types.

- [ ] **Step 2: Run the test to capture the red transcript**

Run: `swift test --filter FaceReportGradingTests 2>&1 | tail -20`
Expected: FAIL — compile errors `cannot find 'FaceReportGrading' in scope`, `cannot find 'FaceReport' in scope`, `cannot find 'FaceFacingScore' in scope`. Paste the transcript into the task's completion report; a red that names any *other* error means the test file itself is wrong and must be fixed here, not in 1B.

- [ ] **Step 3: Commit the tests alone**

```bash
git add Tests/TeststripCoreTests/FaceReportGradingTests.swift
git commit -m "test: pin per-face grading bands against the measured constants"
```

---

### Task 1B: Implement `FaceReport` and its grading rule

**Adversarial split:** a different subagent from Task 1A. **You may not modify, delete, weaken, or extend `Tests/TeststripCoreTests/FaceReportGradingTests.swift`.** If you believe a test is wrong, stop and return a **BLOCKED** report naming the test and the reason. The reviewer will run `git log --follow --oneline -- Tests/TeststripCoreTests/FaceReportGradingTests.swift` and reject the task if it shows more than the one commit from Task 1A.

**Files:**
- Create: `Sources/TeststripCore/Evaluation/FaceReport.swift`

**Interfaces:**
- Consumes: the frozen-constants table (Task 0).
- Produces:
  - `public enum FaceReportGrade: Int, Sendable, Comparable, CaseIterable { case green = 0, yellow = 1, red = 2 }`
  - `public enum FaceReportGrading` with `public static let prominenceFloor: Double`, `redSignalCeiling: Double`, `greenSignalFloor: Double`, and
    `public static func grade(eyesOpen: Bool, sharpness: Double?, light: Double?, facing: Double?, prominence: Double) -> FaceReportGrade`
  - `public struct FaceReport: Equatable, Sendable` with stored `normalizedBounds: CGRect`, `eyesOpen: Bool`, `hasSmile: Bool`, `sharpness: Double?`, `light: Double?`, `facing: Double?`, `prominence: Double`; computed `eyesScore: Double` and `grade: FaceReportGrade`; memberwise `public init(normalizedBounds:eyesOpen:hasSmile:sharpness:light:facing:prominence:)`.

- [ ] **Step 1: Write the implementation**

Create `Sources/TeststripCore/Evaluation/FaceReport.swift`. The three `<…>` values come from the frozen-constants table, and each WHY comment must be completed with the measurement recorded in that table's row.

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
/// gets a documented reason, not a magic literal at the call site. Every
/// value here was measured over `sample-data/photos/faces` and deterministic
/// defect derivatives of it, not reasoned; see the plan's frozen-constants
/// table and the SDD ledger entry for the run.
public enum FaceReportGrading {
    /// A face smaller than this share of the frame is a bystander, not the
    /// subject. Below the floor a face can flag yellow but never grades a
    /// frame red — the rail dot answers "is anyone I care about ruined", not
    /// "is any face imperfect". Measured: <geometric midpoint between the
    /// smallest subject-face area and the largest background-face area on the
    /// composite fixtures>.
    public static let prominenceFloor = <prominenceFloor>

    /// Below this a signal is visibly wrong — a soft face, a blown or crushed
    /// face, a head turned most of the way away. This is the only band that
    /// can produce a red. Measured: <clean p05 vs ruined p95 for the binding
    /// signal>; every heavy-blur and +-3EV derivative lands below it and no
    /// clean corpus portrait does.
    public static let redSignalCeiling = <redSignalCeiling>

    /// At or above this every measured signal reads clean. Between the two
    /// constants the face is worth a second look but is not ruined. Measured:
    /// <the minimum across signals of that signal's 10th percentile over the
    /// 11 clean corpus portraits>; at least 10 of the 11 grade green.
    public static let greenSignalFloor = <greenSignalFloor>

    /// The face's grade is governed by its *worst measured* signal: one
    /// ruined signal ruins the face, and averaging would let a blown exposure
    /// hide behind a sharp, frontal, open-eyed read. Signals that could not be
    /// measured are absent from the vote rather than counted as zero — never
    /// a fake score, never a fake green.
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

- [ ] **Step 2: Run the test — it stays red on `FaceFacingScore` only**

Run: `swift test --filter FaceReportGradingTests 2>&1 | tail -20`
Expected: still FAIL, but the only remaining error is `cannot find 'FaceFacingScore' in scope` (Task 2B supplies it). Any error naming `FaceReport` or `FaceReportGrading` means this implementation is incomplete.

- [ ] **Step 3: Commit**

```bash
git add Sources/TeststripCore/Evaluation/FaceReport.swift
git commit -m "feat: per-face report card model and prominence-weighted grading"
```

---

### Task 2A: Write the failing tests for the facing score and box matching

**Adversarial split:** this task writes tests only. It creates no file under `Sources/`. Task 2B's implementer may not touch the file this task commits.

**Files:**
- Test: `Tests/TeststripCoreTests/FaceFacingScoreTests.swift`

**Interfaces:**
- Consumes: the frozen-constants table (Task 0) — `zeroAtRadians` and `minimumBoxOverlap`; `FaceReportGrading.redSignalCeiling` (Task 1B).
- Produces: a red test file pinning `FaceOrientationObservation`, `FaceOrientationDetecting`, `FaceFacingScore.zeroAtRadians`, `FaceFacingScore.minimumBoxOverlap`, `FaceFacingScore.score(yawRadians:pitchRadians:)`, and `FaceFacingScore.matched(detectionBounds:orientations:)`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripCoreTests/FaceFacingScoreTests.swift`. The tests are written **relative to the measured constants** rather than against hard-coded angles, so a future re-measurement moves the constant without silently invalidating the test.

```swift
import CoreGraphics
import Foundation
import XCTest
@testable import TeststripCore

final class FaceFacingScoreTests: XCTestCase {
    private static func degrees(_ value: Double) -> Double { value * .pi / 180.0 }

    // MARK: - Score

    func testFullFrontalScoresOne() {
        XCTAssertEqual(FaceFacingScore.score(yawRadians: 0, pitchRadians: 0), 1.0)
    }

    func testHalfWayToTheZeroAngleScoresHalf() {
        let score = FaceFacingScore.score(yawRadians: FaceFacingScore.zeroAtRadians / 2, pitchRadians: 0)
        XCTAssertEqual(score ?? 0, 0.5, accuracy: 0.0001)
    }

    func testDirectionOfTurnDoesNotMatter() {
        XCTAssertEqual(
            FaceFacingScore.score(yawRadians: -FaceFacingScore.zeroAtRadians / 3, pitchRadians: 0),
            FaceFacingScore.score(yawRadians: FaceFacingScore.zeroAtRadians / 3, pitchRadians: 0)
        )
    }

    func testAtOrBeyondTheZeroAngleScoresZero() {
        XCTAssertEqual(FaceFacingScore.score(yawRadians: FaceFacingScore.zeroAtRadians, pitchRadians: 0), 0.0)
        // Vision reports yaw in [-Pi/2, Pi/2]; a full profile clamps, never
        // goes negative.
        XCTAssertEqual(FaceFacingScore.score(yawRadians: .pi / 2, pitchRadians: 0), 0.0)
    }

    func testTheWorseAxisGovernsRatherThanABlend() {
        let score = FaceFacingScore.score(yawRadians: 0, pitchRadians: -FaceFacingScore.zeroAtRadians / 2)
        XCTAssertEqual(score ?? 0, 0.5, accuracy: 0.0001)
    }

    func testAMissingAxisIsTreatedAsLevel() {
        XCTAssertEqual(FaceFacingScore.score(yawRadians: 0, pitchRadians: nil), 1.0)
    }

    func testBothAxesMissingIsUnscored() {
        XCTAssertNil(FaceFacingScore.score(yawRadians: nil, pitchRadians: nil))
    }

    // The corpus regression `zeroAtRadians` was measured to prevent
    // (commons-glenn-1962, yaw -56.2 degrees): a usable off-axis head must
    // score at or above redSignalCeiling so facing alone cannot grade it red.
    func testTheCorpusStrongestOffAxisHeadStaysOutOfTheRedBand() {
        let score = FaceFacingScore.score(yawRadians: Self.degrees(-56.2), pitchRadians: 0)
        XCTAssertGreaterThanOrEqual(score ?? 0, FaceReportGrading.redSignalCeiling)
    }

    // MARK: - Matching

    func testGreatestOverlapObservationWins() {
        let detection = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let partial = CGRect(x: 0.45, y: 0.45, width: 0.2, height: 0.2)
        // Both candidates must clear the floor, so this test is about ranking
        // rather than filtering. If the measured floor ever rises above this,
        // the assertion fails loudly instead of quietly changing meaning.
        XCTAssertGreaterThan(
            FaceFacingScore.intersectionOverUnion(detection, partial),
            FaceFacingScore.minimumBoxOverlap
        )
        let poorOverlap = FaceOrientationObservation(
            normalizedBounds: partial,
            yawRadians: FaceFacingScore.zeroAtRadians,
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

    // The amendment-1 finding: the two detectors' boxes for the SAME face
    // agreed at IoU 0.228 at 1600px (and 0.510 at 512px). A floor that
    // rejects 0.228 throws away a correct match and blanks the facing chip on
    // a frame that has a perfectly good head-pose read.
    func testTheCorpusWorstCorrectMatchIsStillMatched() {
        // Two concentric boxes whose IoU is 0.228: side ratio r satisfies
        // r^2 = 0.228 for nested squares, so r ~= 0.4775.
        let detection = CGRect(x: 0.3, y: 0.3, width: 0.40, height: 0.40)
        let observationBounds = CGRect(x: 0.3955, y: 0.3955, width: 0.191, height: 0.191)
        XCTAssertEqual(
            FaceFacingScore.intersectionOverUnion(detection, observationBounds),
            0.228,
            accuracy: 0.01
        )

        let facing = FaceFacingScore.matched(
            detectionBounds: [detection],
            orientations: [
                FaceOrientationObservation(normalizedBounds: observationBounds, yawRadians: 0, pitchRadians: 0)
            ]
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
        XCTAssertEqual(FaceFacingScore.matched(detectionBounds: [], orientations: []), [])
    }
}
```

- [ ] **Step 2: Run the test to capture the red transcript**

Run: `swift test --filter FaceFacingScoreTests 2>&1 | tail -20`
Expected: FAIL — compile error `cannot find 'FaceFacingScore' in scope`. Paste the transcript into the completion report.

- [ ] **Step 3: Commit the tests alone**

```bash
git add Tests/TeststripCoreTests/FaceFacingScoreTests.swift
git commit -m "test: pin facing score and Vision-to-CIDetector matching behavior"
```

---

### Task 2B: Implement the facing score and box matching

**Adversarial split:** a different subagent from Task 2A. **You may not modify `Tests/TeststripCoreTests/FaceFacingScoreTests.swift`.** A test you believe is wrong is a **BLOCKED** report, not an edit. Reviewer gate: `git log --follow --oneline -- Tests/TeststripCoreTests/FaceFacingScoreTests.swift` shows exactly one commit.

**Files:**
- Create: `Sources/TeststripCore/Evaluation/FaceOrientation.swift`

**Interfaces:**
- Consumes: the frozen-constants table (Task 0).
- Produces:
  - `public struct FaceOrientationObservation: Equatable, Sendable` with `normalizedBounds: CGRect` (top-left origin), `yawRadians: Double?`, `pitchRadians: Double?`, memberwise `public init(normalizedBounds:yawRadians:pitchRadians:)`.
  - `public protocol FaceOrientationDetecting: Sendable { func orientations(in image: CGImage) throws -> [FaceOrientationObservation] }`
  - `public enum FaceFacingScore` with `public static let zeroAtRadians: Double`, `public static let minimumBoxOverlap: Double`, `public static func score(yawRadians: Double?, pitchRadians: Double?) -> Double?`, `public static func matched(detectionBounds: [CGRect], orientations: [FaceOrientationObservation]) -> [Double?]`, and `static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> Double` (module-internal — Task 2A's tests call it through `@testable`).

- [ ] **Step 1: Write the implementation**

Create `Sources/TeststripCore/Evaluation/FaceOrientation.swift`. The two `<…>` values come from the frozen-constants table.

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
    /// Facing decays linearly from 1 at full frontal to 0 at this angle off
    /// axis. Measured, not guessed: the faces corpus's strongest usable
    /// off-axis head sits at yaw -56.2 degrees, and a 60-degree zero point
    /// scored it 0.064, which graded a perfectly usable frame red. This value
    /// is the smallest whole-degree zero point that keeps that head at or
    /// above `FaceReportGrading.redSignalCeiling`. See the plan's
    /// frozen-constants table.
    public static let zeroAtRadians = Double.pi * <zeroAtRadians in degrees> / 180

    /// Two detectors' boxes for the same face overlap, but not nearly as much
    /// as intuition suggests: measured across the whole preview ladder, a
    /// correctly-matched CIDetector/Vision pair fell as low as IoU 0.228 (at
    /// 1600px; the same pair scores 0.510 at 512px, because the two detectors
    /// disagree about how much forehead and chin a "face" includes, and that
    /// disagreement grows with resolution). This floor is 0.8x the worst
    /// correct match observed, so a real pair is never thrown away — below it
    /// the CIDetector face is left unscored rather than borrowing a
    /// stranger's angles.
    public static let minimumBoxOverlap = <minimumBoxOverlap>

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

- [ ] **Step 2: Run both Core test suites to verify they pass**

Run: `swift test --filter FaceFacingScoreTests 2>&1 | tail -5`
Expected: PASS — `Executed 12 tests, with 0 failures`.

Run: `swift test --filter FaceReportGradingTests 2>&1 | tail -5`
Expected: PASS — `Executed 9 tests, with 0 failures` (Task 1A's file goes green now that `FaceFacingScore` exists).

- [ ] **Step 3: Run the full suite**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2302 tests, with 0 failures` (2281 baseline + 9 + 12).

- [ ] **Step 4: Commit**

```bash
git add Sources/TeststripCore/Evaluation/FaceOrientation.swift
git commit -m "feat: facing score from head pose and Vision-to-CIDetector box matching"
```

---

### Task 3A: Write the failing tests for `FaceReportAnalyzer` and the Vision detector

**Adversarial split:** this task writes tests only. It creates no file under `Sources/`. Task 3B's implementer may not touch the file this task commits.

**Files:**
- Test: `Tests/TeststripCoreTests/FaceReportAnalyzerTests.swift`

**Interfaces:**
- Consumes: `FaceReport` (Task 1B), `FaceOrientationObservation` / `FaceOrientationDetecting` (Task 2B), existing `DetectedFaceExpression` and `PreviewPixelMetrics`.
- Produces: a red test file pinning `FaceReportAnalyzer(orientationDetector:)`, `reports(in:detections:)`, `VisionFaceOrientationDetector`, `VisionFaceOrientationDetector.orientation(from:)`, `DetectedFaceExpression.bothEyesShut`, `PreviewPixelMetrics.meanLuminance(in:width:height:)`, and `PreviewPixelMetrics.balancedExposure(meanLuminance:)`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripCoreTests/FaceReportAnalyzerTests.swift`:

```swift
import CoreGraphics
import Foundation
import Vision
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

    func testBothEyesShutIsTheOneSharedRule() {
        XCTAssertTrue(face(leftEyeClosed: true, rightEyeClosed: true).bothEyesShut)
        XCTAssertFalse(face(leftEyeClosed: true, rightEyeClosed: false).bothEyesShut)
        XCTAssertFalse(face().bothEyesShut)
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

    // MARK: - The real Vision detector's coordinate and pose mapping

    // Vision's boundingBox is bottom-left origin; report cards are top-left.
    // A constructed observation exercises the flip directly, which a
    // faceless-image test can never reach.
    func testVisionObservationBoundingBoxFlipsToTopLeftOrigin() {
        let observation = VNFaceObservation(
            requestRevision: VNDetectFaceRectanglesRequestRevision3,
            boundingBox: CGRect(x: 0.2, y: 0.7, width: 0.1, height: 0.2),
            roll: nil,
            yaw: NSNumber(value: 0.3),
            pitch: NSNumber(value: -0.1)
        )

        let mapped = VisionFaceOrientationDetector.orientation(from: observation)

        XCTAssertEqual(Double(mapped.normalizedBounds.minX), 0.2, accuracy: 0.0001)
        // bottom-left maxY 0.9 -> top-left minY 0.1
        XCTAssertEqual(Double(mapped.normalizedBounds.minY), 0.1, accuracy: 0.0001)
        XCTAssertEqual(Double(mapped.normalizedBounds.width), 0.1, accuracy: 0.0001)
        XCTAssertEqual(Double(mapped.normalizedBounds.height), 0.2, accuracy: 0.0001)
        XCTAssertEqual(mapped.yawRadians ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(mapped.pitchRadians ?? 0, -0.1, accuracy: 0.0001)
    }

    func testVisionObservationWithoutPoseMapsToUnscoredAxes() {
        let observation = VNFaceObservation(
            requestRevision: VNDetectFaceRectanglesRequestRevision3,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            roll: nil,
            yaw: nil,
            pitch: nil
        )

        let mapped = VisionFaceOrientationDetector.orientation(from: observation)

        XCTAssertNil(mapped.yawRadians)
        XCTAssertNil(mapped.pitchRadians)
        XCTAssertNil(FaceFacingScore.score(yawRadians: mapped.yawRadians, pitchRadians: mapped.pitchRadians))
    }

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

- [ ] **Step 2: Run the test to capture the red transcript**

Run: `swift test --filter FaceReportAnalyzerTests 2>&1 | tail -20`
Expected: FAIL — compile errors `cannot find 'FaceReportAnalyzer' in scope` and `cannot find 'VisionFaceOrientationDetector' in scope`. Paste the transcript into the completion report.

- [ ] **Step 3: Commit the tests alone**

```bash
git add Tests/TeststripCoreTests/FaceReportAnalyzerTests.swift
git commit -m "test: pin per-face analyzer measurement and Vision pose mapping"
```

---

### Task 3B: Implement `FaceReportAnalyzer` and the Vision orientation detector

**Adversarial split:** a different subagent from Task 3A. **You may not modify `Tests/TeststripCoreTests/FaceReportAnalyzerTests.swift`.** A test you believe is wrong is a **BLOCKED** report, not an edit. Reviewer gate: `git log --follow --oneline -- Tests/TeststripCoreTests/FaceReportAnalyzerTests.swift` shows exactly one commit.

**Files:**
- Create: `Sources/TeststripCore/Evaluation/FaceReportAnalyzer.swift`
- Modify: `Sources/TeststripCore/Evaluation/PreviewPixelMetrics.swift` (add `meanLuminance` and `balancedExposure` after `focusScore`, which currently ends at line 59)
- Modify: `Sources/TeststripCore/Evaluation/LocalImageMetricsEvaluationProvider.swift:113` and `:122-162` (call the shared helpers instead of its private copies)
- Modify: `Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift:33-35` (add `bothEyesShut`)

**Interfaces:**
- Consumes: `FaceReport(normalizedBounds:eyesOpen:hasSmile:sharpness:light:facing:prominence:)` (Task 1B); `FaceOrientationObservation`, `FaceOrientationDetecting`, `FaceFacingScore.matched(detectionBounds:orientations:)` (Task 2B); existing `DetectedFaceExpression` and `PreviewPixelMetrics`.
- Produces:
  - `public extension DetectedFaceExpression { var bothEyesShut: Bool }`
  - `PreviewPixelMetrics.meanLuminance(in:width:height:) -> Double` and `PreviewPixelMetrics.balancedExposure(meanLuminance:) -> Double` (both `static`, module-internal like the rest of that enum)
  - `public struct FaceReportAnalyzer: Sendable` with `public static let cropSampleSize: Int`, `public static let minimumCropPixels: Int`, `public init(orientationDetector: any FaceOrientationDetecting = VisionFaceOrientationDetector())`, and `public func reports(in image: CGImage, detections: [DetectedFaceExpression]) -> [FaceReport]`
  - `public struct VisionFaceOrientationDetector: FaceOrientationDetecting` with `public init()` and `static func orientation(from observation: VNFaceObservation) -> FaceOrientationObservation`

- [ ] **Step 1: Add the shared pixel helpers**

In `Sources/TeststripCore/Evaluation/PreviewPixelMetrics.swift`, insert after `focusScore(in:width:height:)`:

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

- [ ] **Step 2: Point the existing provider at the shared helpers**

In `Sources/TeststripCore/Evaluation/LocalImageMetricsEvaluationProvider.swift`, replace the inline `balancedExposure` local inside `aestheticScore` (line 113):

```swift
        let balancedExposure = 1.0 - min(abs(exposure - 0.5) * 2.0, 1.0)
```

with:

```swift
        let balancedExposure = PreviewPixelMetrics.balancedExposure(meanLuminance: exposure)
```

Then replace the first line of `framingScore` (line 123):

```swift
        let average = averageLuminance(in: pixels, width: width, height: height)
```

with:

```swift
        let average = PreviewPixelMetrics.meanLuminance(in: pixels, width: width, height: height)
```

and delete the now-unused private `averageLuminance` function entirely (lines 152-162).

- [ ] **Step 3: Give `DetectedFaceExpression` the shared blink noise floor**

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

- [ ] **Step 4: Write the analyzer**

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
            x: (Double(normalizedBounds.minX) * imageWidth).rounded(.down),
            y: (Double(normalizedBounds.minY) * imageHeight).rounded(.down),
            width: (Double(normalizedBounds.width) * imageWidth).rounded(),
            height: (Double(normalizedBounds.height) * imageHeight).rounded()
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
        return (request.results ?? []).map(Self.orientation(from:))
    }

    /// Vision's boundingBox is bottom-left origin; report cards use top-left,
    /// the same flip `FaceBoxOverlayGeometry` applies. Factored out so the
    /// mapping is directly testable against constructed observations rather
    /// than only through a live request.
    static func orientation(from observation: VNFaceObservation) -> FaceOrientationObservation {
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter FaceReportAnalyzerTests 2>&1 | tail -5`
Expected: PASS — `Executed 14 tests, with 0 failures`.

- [ ] **Step 6: Prove the shared-helper refactor changed no whole-photo behavior**

Run: `swift test --filter EvaluationProviderTests 2>&1 | tail -5`
Expected: PASS, unchanged from baseline — the `exposure`/`aesthetics`/`framing` assertions still hold.

- [ ] **Step 7: Run the full suite**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2316 tests, with 0 failures`.

- [ ] **Step 8: Commit**

```bash
git add Sources/TeststripCore/Evaluation/FaceReportAnalyzer.swift \
        Sources/TeststripCore/Evaluation/PreviewPixelMetrics.swift \
        Sources/TeststripCore/Evaluation/LocalImageMetricsEvaluationProvider.swift \
        Sources/TeststripCore/Evaluation/FaceExpressionEvaluationProvider.swift
git commit -m "feat: per-face report analyzer for sharpness, light, facing, and prominence"
```

---

### Task 4A: Write the failing tests for `FaceReportStore`

**Adversarial split:** this task writes tests only. It creates no file under `Sources/`. Task 4B's implementer may not touch the file this task commits.

**Files:**
- Test: `Tests/TeststripAppTests/FaceReportStoreTests.swift`

**Interfaces:**
- Consumes: `FaceReport`, `FaceReportGrade` (Task 1B); `PreviewLevel` (existing Core).
- Produces: a red test file pinning `FrameFaceReport(reports:previewCacheGeneration:analyzedLevel:)` with computed `rolledUpGrade`, `FaceReportPreviewSource(previewURL:level:)`, `FaceReportSweepFrame(assetID:source:previewCacheGeneration:)`, `FaceReportPreviewFloor.lowestAcceptedLevel` / `.accepts(_:)`, and `FaceReportStore` with `init(analyze:)`, `report(for:currentGeneration:bestAvailableLevel:)`, `record(_:for:previewCacheGeneration:analyzedLevel:)`, `sweep(frames:currentFrameID:)`, and `sweepOrder(frames:currentFrameID:)`.

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

    /// A clean face and a ruined one, expressed against the measured bands so
    /// these fixtures cannot drift out from under Task 0's constants.
    private static var cleanReport: FaceReport {
        report(sharpness: min(FaceReportGrading.greenSignalFloor + 0.15, 1.0))
    }

    private static var ruinedReport: FaceReport {
        report(sharpness: FaceReportGrading.redSignalCeiling / 2)
    }

    private static func frame(
        _ id: String,
        generation: Int = 1,
        level: PreviewLevel? = .medium
    ) -> FaceReportSweepFrame {
        FaceReportSweepFrame(
            assetID: AssetID(rawValue: id),
            source: level.map {
                FaceReportPreviewSource(previewURL: URL(fileURLWithPath: "/previews/\(id).jpg"), level: $0)
            },
            previewCacheGeneration: generation
        )
    }

    /// Records every preview URL it is handed, and can be held open on a
    /// chosen URL so a test can act while one analysis is in flight.
    private actor AnalysisRecorder {
        private(set) var calls: [String] = []
        private var gateURL: String?
        private var hasReachedGate = false
        private var gateOpened: CheckedContinuation<Void, Never>?
        private var gateReachedWaiter: CheckedContinuation<Void, Never>?

        func gate(on lastPathComponent: String) {
            gateURL = lastPathComponent
        }

        func analyze(_ url: URL) async -> [FaceReport] {
            calls.append(url.lastPathComponent)
            if url.lastPathComponent == gateURL {
                // Record arrival BEFORE suspending, and resume any waiter that
                // already installed itself. `waitUntilGateReached` checks the
                // flag first, so a gate reached before the waiter arrives can
                // never deadlock the suite.
                hasReachedGate = true
                gateReachedWaiter?.resume()
                gateReachedWaiter = nil
                await withCheckedContinuation { continuation in
                    gateOpened = continuation
                }
            }
            return [FaceReportStoreTests.cleanReport]
        }

        func waitUntilGateReached() async {
            if hasReachedGate { return }
            await withCheckedContinuation { continuation in
                gateReachedWaiter = continuation
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
        for id in ["a", "b", "c"] {
            XCTAssertNotNil(
                store.report(for: AssetID(rawValue: id), currentGeneration: 1, bestAvailableLevel: .medium)
            )
        }
    }

    // MARK: - Preview floor, generation, and level

    @MainActor
    func testFramesWithoutAPreviewAtOrAboveTheFloorAreSkipped() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(
            frames: [Self.frame("a"), Self.frame("b", level: nil)],
            currentFrameID: nil
        )

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["a.jpg"])
        XCTAssertNil(
            store.report(for: AssetID(rawValue: "b"), currentGeneration: 1, bestAvailableLevel: nil)
        )
    }

    func testThePreviewFloorRejectsThumbnailLevelsAndAcceptsEverythingAbove() {
        XCTAssertFalse(FaceReportPreviewFloor.accepts(.micro))
        XCTAssertFalse(FaceReportPreviewFloor.accepts(.grid))
        XCTAssertTrue(FaceReportPreviewFloor.accepts(FaceReportPreviewFloor.lowestAcceptedLevel))
        XCTAssertTrue(FaceReportPreviewFloor.accepts(.original))
    }

    @MainActor
    func testASkippedFrameIsPickedUpOnceAFloorQualityPreviewLands() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(frames: [Self.frame("b", level: nil)], currentFrameID: nil)
        await store.sweep(frames: [Self.frame("b", generation: 2, level: .medium)], currentFrameID: nil)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["b.jpg"])
        XCTAssertEqual(
            store.report(for: AssetID(rawValue: "b"), currentGeneration: 2, bestAvailableLevel: .medium)?
                .previewCacheGeneration,
            2
        )
    }

    @MainActor
    func testAFrameAlreadyComputedAtTheSameGenerationAndLevelIsNotReanalyzed() async {
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
        XCTAssertEqual(
            store.report(for: AssetID(rawValue: "a"), currentGeneration: 2, bestAvailableLevel: .medium)?
                .previewCacheGeneration,
            2
        )
    }

    // Grades must not flap as previews upgrade: a report measured off a
    // 1600px preview is superseded the moment a 3200px one is cached.
    @MainActor
    func testABetterPreviewLevelInvalidatesTheCachedReport() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(frames: [Self.frame("a", level: .medium)], currentFrameID: nil)
        await store.sweep(frames: [Self.frame("a", level: .large)], currentFrameID: nil)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["a.jpg", "a.jpg"])
        XCTAssertEqual(
            store.report(for: AssetID(rawValue: "a"), currentGeneration: 1, bestAvailableLevel: .large)?
                .analyzedLevel,
            .large
        )
    }

    // MARK: - Staleness is enforced on READ, not only on sweep

    @MainActor
    func testAStaleGenerationReadsAsNoReportRatherThanTheCachedEntry() {
        let store = FaceReportStore()

        store.record(
            [Self.cleanReport],
            for: AssetID(rawValue: "a"),
            previewCacheGeneration: 1,
            analyzedLevel: .medium
        )

        XCTAssertNotNil(store.report(for: AssetID(rawValue: "a"), currentGeneration: 1, bestAvailableLevel: .medium))
        XCTAssertNil(store.report(for: AssetID(rawValue: "a"), currentGeneration: 2, bestAvailableLevel: .medium))
    }

    @MainActor
    func testAStaleLevelReadsAsNoReportRatherThanTheCachedEntry() {
        let store = FaceReportStore()

        store.record(
            [Self.cleanReport],
            for: AssetID(rawValue: "a"),
            previewCacheGeneration: 1,
            analyzedLevel: .medium
        )

        XCTAssertNil(store.report(for: AssetID(rawValue: "a"), currentGeneration: 1, bestAvailableLevel: .large))
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
        XCTAssertNil(store.report(for: AssetID(rawValue: "a"), currentGeneration: 1, bestAvailableLevel: .medium))
        // ...and the frames behind it are never analyzed at all.
        XCTAssertEqual(calls, ["a.jpg"])
        XCTAssertNil(store.report(for: AssetID(rawValue: "b"), currentGeneration: 1, bestAvailableLevel: .medium))
        XCTAssertNil(store.report(for: AssetID(rawValue: "c"), currentGeneration: 1, bestAvailableLevel: .medium))
    }

    // MARK: - Roll-up and the close-ups hand-off

    @MainActor
    func testRecordStoresTheCloseUpsPassResultWithoutAnalyzingAgain() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        store.record(
            [Self.cleanReport],
            for: AssetID(rawValue: "a"),
            previewCacheGeneration: 4,
            analyzedLevel: .medium
        )
        await store.sweep(frames: [Self.frame("a", generation: 4, level: .medium)], currentFrameID: nil)

        let calls = await recorder.calls
        XCTAssertEqual(calls, [])
        XCTAssertEqual(
            store.report(for: AssetID(rawValue: "a"), currentGeneration: 4, bestAvailableLevel: .medium)?
                .reports.count,
            1
        )
    }

    @MainActor
    func testRolledUpGradeIsTheWorstFaceGrade() {
        let frame = FrameFaceReport(
            reports: [
                Self.cleanReport,
                Self.report(sharpness: (FaceReportGrading.redSignalCeiling + FaceReportGrading.greenSignalFloor) / 2)
            ],
            previewCacheGeneration: 1,
            analyzedLevel: .medium
        )

        XCTAssertEqual(frame.rolledUpGrade, .yellow)
    }

    @MainActor
    func testABackgroundFacesRuinedSignalNeverRollsTheFrameUpToRed() {
        let frame = FrameFaceReport(
            reports: [
                Self.report(sharpness: min(FaceReportGrading.greenSignalFloor + 0.15, 1.0), prominence: 0.3),
                // Ruined, but below the prominence floor.
                Self.report(sharpness: FaceReportGrading.redSignalCeiling / 2, prominence: FaceReportGrading.prominenceFloor / 10)
            ],
            previewCacheGeneration: 1,
            analyzedLevel: .medium
        )

        XCTAssertEqual(frame.rolledUpGrade, .yellow)
    }

    @MainActor
    func testAFrameWithNoFacesHasNoRolledUpGrade() {
        let frame = FrameFaceReport(reports: [], previewCacheGeneration: 1, analyzedLevel: .medium)

        // Absence means "nothing known", never "known good".
        XCTAssertNil(frame.rolledUpGrade)
    }

    @MainActor
    func testAnUncomputedFrameHasNoReportAtAll() {
        let store = FaceReportStore()

        XCTAssertNil(
            store.report(for: AssetID(rawValue: "never-swept"), currentGeneration: 1, bestAvailableLevel: .medium)
        )
    }
}
```

- [ ] **Step 2: Run the test to capture the red transcript**

Run: `swift test --filter FaceReportStoreTests 2>&1 | tail -20`
Expected: FAIL — compile error `cannot find 'FaceReportStore' in scope` (and the sibling types). Paste the transcript into the completion report.

- [ ] **Step 3: Commit the tests alone**

```bash
git add Tests/TeststripAppTests/FaceReportStoreTests.swift
git commit -m "test: pin face report store caching, staleness, sweep order, and cancellation"
```

---

### Task 4B: Implement `FaceReportStore`

**Adversarial split:** a different subagent from Task 4A. **You may not modify `Tests/TeststripAppTests/FaceReportStoreTests.swift`.** A test you believe is wrong is a **BLOCKED** report, not an edit. Reviewer gate: `git log --follow --oneline -- Tests/TeststripAppTests/FaceReportStoreTests.swift` shows exactly one commit.

**Files:**
- Create: `Sources/TeststripApp/FaceReportStore.swift`

**Interfaces:**
- Consumes: `FaceReport`, `FaceReportGrade` (Task 1B); `FaceReportAnalyzer(orientationDetector:)` and `reports(in:detections:)` (Task 3B); existing `AssetID`, `PreviewLevel`, `CoreImageFaceExpressionAnalyzer`.
- Produces:
  - `enum FaceReportPreviewFloor` with `static let lowestAcceptedLevel: PreviewLevel` and `static func accepts(_ level: PreviewLevel) -> Bool`, plus `static let acceptedLevelsHighestFirst: [PreviewLevel]`.
  - `extension PreviewLevel { var faceReportRank: Int }`
  - `struct FaceReportPreviewSource: Equatable, Sendable { var previewURL: URL; var level: PreviewLevel }`
  - `struct FrameFaceReport: Equatable { var reports: [FaceReport]; var previewCacheGeneration: Int; var analyzedLevel: PreviewLevel; var rolledUpGrade: FaceReportGrade? }`
  - `struct FaceReportSweepFrame: Equatable, Sendable { var assetID: AssetID; var source: FaceReportPreviewSource?; var previewCacheGeneration: Int }`
  - `@Observable final class FaceReportStore` with `init(analyze: @escaping @Sendable (URL) async -> [FaceReport] = FaceReportStore.analyzeCachedPreview)`, `@MainActor func report(for:currentGeneration:bestAvailableLevel:) -> FrameFaceReport?`, `@MainActor func record(_:for:previewCacheGeneration:analyzedLevel:)`, `@MainActor func sweep(frames:currentFrameID:) async`, `static func sweepOrder(frames:currentFrameID:) -> [FaceReportSweepFrame]`, `static func analyzeCachedPreview(at:) async -> [FaceReport]`.

- [ ] **Step 1: Write the implementation**

Create `Sources/TeststripApp/FaceReportStore.swift`. The one `<…>` value comes from the frozen-constants table.

```swift
import CoreGraphics
import Foundation
import ImageIO
import Observation
import TeststripCore

extension PreviewLevel {
    /// Ordering for face-report staleness: a better level supersedes a worse
    /// one, so a report measured off a 1600px preview is stale the moment a
    /// 3200px one is cached.
    var faceReportRank: Int {
        switch self {
        case .micro: return 0
        case .grid: return 1
        case .medium: return 2
        case .large: return 3
        case .original: return 4
        }
    }
}

/// Report cards are only ever measured off a preview at or above this level.
/// Measured, not assumed: the same face graded green off a 512px preview and
/// yellow off 1600px and above, and its head pose was scored at 512px but
/// nil above it, so a report card read off a thumbnail would visibly flap as
/// previews upgraded under the photographer. Below the floor there is simply
/// "no report yet" — never a provisional grade. See the plan's
/// frozen-constants table.
enum FaceReportPreviewFloor {
    static let lowestAcceptedLevel: PreviewLevel = <lowestAcceptedLevel>

    /// Highest first, so a lookup takes the best cached preview available.
    static let acceptedLevelsHighestFirst: [PreviewLevel] = PreviewLevel.allCases
        .filter { accepts($0) }
        .sorted { $0.faceReportRank > $1.faceReportRank }

    static func accepts(_ level: PreviewLevel) -> Bool {
        level.faceReportRank >= lowestAcceptedLevel.faceReportRank
    }
}

/// The cached preview a frame's report cards are measured from, and the level
/// it came from — both halves of the staleness key.
struct FaceReportPreviewSource: Equatable, Sendable {
    var previewURL: URL
    var level: PreviewLevel

    init(previewURL: URL, level: PreviewLevel) {
        self.previewURL = previewURL
        self.level = level
    }
}

/// One frame's face report cards, plus the preview generation and level they
/// were computed from. Either going stale means the frame is re-analyzed and,
/// until then, reads as absent.
struct FrameFaceReport: Equatable {
    var reports: [FaceReport]
    var previewCacheGeneration: Int
    var analyzedLevel: PreviewLevel

    init(reports: [FaceReport], previewCacheGeneration: Int, analyzedLevel: PreviewLevel) {
        self.reports = reports
        self.previewCacheGeneration = previewCacheGeneration
        self.analyzedLevel = analyzedLevel
    }

    /// The frame's traffic light: the worst grade any face earned. Grading
    /// already applied the prominence floor, so a background face can only
    /// push this to yellow. nil when the frame has no faces — absence means
    /// "nothing known", never "known good".
    var rolledUpGrade: FaceReportGrade? {
        reports.map(\.grade).max()
    }
}

/// One frame the sweep may analyze. `source` is nil when nothing at or above
/// the preview floor is cached yet.
struct FaceReportSweepFrame: Equatable, Sendable {
    var assetID: AssetID
    var source: FaceReportPreviewSource?
    var previewCacheGeneration: Int

    init(assetID: AssetID, source: FaceReportPreviewSource?, previewCacheGeneration: Int) {
        self.assetID = assetID
        self.source = source
        self.previewCacheGeneration = previewCacheGeneration
    }
}

/// The single in-app home for per-face report cards. Both surfaces read it
/// through `report(for:currentGeneration:bestAvailableLevel:)` — the
/// close-ups panel's chips and header roll-up, and the burst rail's dots — so
/// a frame can never show one grade in one place and another elsewhere, and
/// neither can show a grade measured off a preview that has since been
/// replaced. In memory only: nothing here is persisted, and no worker is
/// involved.
///
/// Un-annotated at the class level (matching `AppModel`) so a SwiftUI view can
/// hold it in `@State` without a main-actor initializer; every method that
/// touches the cache is `@MainActor`.
@Observable
final class FaceReportStore {
    private(set) var reportsByAssetID: [AssetID: FrameFaceReport] = [:]

    private let analyze: @Sendable (URL) async -> [FaceReport]

    init(analyze: @escaping @Sendable (URL) async -> [FaceReport] = FaceReportStore.analyzeCachedPreview) {
        self.analyze = analyze
    }

    /// A staleness-checked read: a cached entry is only returned while it
    /// still matches the asset's current preview generation AND was measured
    /// at a level at least as good as the best one now available. Anything
    /// else reads as absent, which every surface renders as "no dot, nothing
    /// known" rather than as a stale grade.
    @MainActor
    func report(
        for assetID: AssetID,
        currentGeneration: Int,
        bestAvailableLevel: PreviewLevel?
    ) -> FrameFaceReport? {
        guard let cached = reportsByAssetID[assetID],
              cached.previewCacheGeneration == currentGeneration,
              let bestAvailableLevel,
              cached.analyzedLevel.faceReportRank >= bestAvailableLevel.faceReportRank else {
            return nil
        }
        return cached
    }

    /// The close-ups pass owns the selected frame's detections and crops, so
    /// it hands its already-computed reports straight in rather than making
    /// the sweep redo the same work — the selected frame's chips, its panel
    /// dot, and its rail dot all come from one computation.
    @MainActor
    func record(
        _ reports: [FaceReport],
        for assetID: AssetID,
        previewCacheGeneration: Int,
        analyzedLevel: PreviewLevel
    ) {
        reportsByAssetID[assetID] = FrameFaceReport(
            reports: reports,
            previewCacheGeneration: previewCacheGeneration,
            analyzedLevel: analyzedLevel
        )
    }

    /// Analyzes the stack's frames one at a time, publishing each as it lands
    /// so dots appear progressively. Plain structured concurrency: the caller
    /// owns the task, so a stack change cancels and restarts the sweep for
    /// free. Cancellation is honored both before starting a frame and before
    /// publishing one, so a sweep the user navigated away from never writes.
    /// `currentFrameID` only picks the order — it is deliberately NOT part of
    /// the caller's task key, because re-keying on selection would cancel and
    /// restart the whole sweep on every arrow-key press and unvisited frames
    /// could then never finish computing.
    @MainActor
    func sweep(frames: [FaceReportSweepFrame], currentFrameID: AssetID?) async {
        for frame in Self.sweepOrder(frames: frames, currentFrameID: currentFrameID) {
            if Task.isCancelled { return }
            guard let source = frame.source else { continue }
            // Already computed at this generation and at least this level:
            // a re-trigger must not redo work it already has.
            if let cached = reportsByAssetID[frame.assetID],
               cached.previewCacheGeneration == frame.previewCacheGeneration,
               cached.analyzedLevel.faceReportRank >= source.level.faceReportRank {
                continue
            }
            let reports = await analyze(source.previewURL)
            if Task.isCancelled { return }
            reportsByAssetID[frame.assetID] = FrameFaceReport(
                reports: reports,
                previewCacheGeneration: frame.previewCacheGeneration,
                analyzedLevel: source.level
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

- [ ] **Step 2: Run the test to verify it passes**

Run: `swift test --filter FaceReportStoreTests 2>&1 | tail -5`
Expected: PASS — `Executed 16 tests, with 0 failures`.

- [ ] **Step 3: Run the full suite**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2332 tests, with 0 failures`.

- [ ] **Step 4: Commit**

```bash
git add Sources/TeststripApp/FaceReportStore.swift
git commit -m "feat: face report store with level-aware staleness and a cancellable stack sweep"
```

---

### Task 5: Chip and roll-up presentation, plus the chip view

Single-agent from here on.

**Files:**
- Create: `Sources/TeststripApp/FaceReportPresentation.swift`
- Create: `Sources/TeststripApp/FaceSignalChipView.swift`
- Test: `Tests/TeststripAppTests/FaceReportPresentationTests.swift`

**Interfaces:**
- Consumes: `FaceReport`, `FaceReportGrade`, `FaceReportGrading` (Task 1B); `FrameFaceReport` (Task 4B).
- Produces:
  - `enum FaceReportSignal: String, CaseIterable { case eyes, sharpness, facing, light }` with `var word: String` and `var symbolName: String`.
  - `struct FaceReportChipPresentation: Equatable` with nested `struct Entry: Equatable, Identifiable { var signal: FaceReportSignal; var score: Double?; var accessibilityText: String; var id: String }`, `var entries: [Entry]`, and `init(report: FaceReport)`.
  - `enum FaceReportRailState: Equatable { case notRead; case noFaces; case faces(count: Int, grade: FaceReportGrade) }`
  - `enum FaceReportRollUpPresentation` with `static func word(for: FaceReportGrade) -> String`, `static func color(for: FaceReportGrade) -> Color`, `static func dotGrade(for: FrameFaceReport?) -> FaceReportGrade?`, `static func railState(for: FrameFaceReport?) -> FaceReportRailState`, `static func headerValue(for: FrameFaceReport?) -> String`, `static func tileAccessibilityValue(for: FaceReport) -> String`.
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

    /// Band-relative fixtures so these tests survive a re-measurement of the
    /// Task 0 constants.
    private static var cleanScore: Double { min(FaceReportGrading.greenSignalFloor + 0.15, 1.0) }
    private static var middlingScore: Double {
        (FaceReportGrading.redSignalCeiling + FaceReportGrading.greenSignalFloor) / 2
    }
    private static var ruinedScore: Double { FaceReportGrading.redSignalCeiling / 2 }

    private static func frame(_ reports: [FaceReport]) -> FrameFaceReport {
        FrameFaceReport(reports: reports, previewCacheGeneration: 1, analyzedLevel: .medium)
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

    // MARK: - Tile accessibility

    // The tile is an `.accessibilityElement(children: .combine)`, which
    // collapses the chips' own labels into one composed value — so a card
    // driving the live app can only assert what THIS string carries. It
    // therefore has to carry every signal's percentage, not just the grade.
    func testTileAccessibilityValueCarriesGradeEyesSmileAndEveryChipPercentage() {
        XCTAssertEqual(
            FaceReportRollUpPresentation.tileAccessibilityValue(
                for: Self.report(hasSmile: true, sharpness: Self.cleanScore, light: Self.cleanScore, facing: Self.cleanScore)
            ),
            "Clean, Eyes open, Smiling, Eyes 100%, "
                + "Sharpness \(Int((Self.cleanScore * 100).rounded()))%, "
                + "Facing \(Int((Self.cleanScore * 100).rounded()))%, "
                + "Light \(Int((Self.cleanScore * 100).rounded()))%"
        )
    }

    func testTileAccessibilityValueChipStringsAreExactlyTheChipRowsStrings() {
        let report = Self.report(facing: nil)
        let chipStrings = FaceReportChipPresentation(report: report).entries.map(\.accessibilityText)

        let value = FaceReportRollUpPresentation.tileAccessibilityValue(for: report)

        for chipString in chipStrings {
            XCTAssertTrue(value.contains(chipString), "tile value is missing chip string \(chipString)")
        }
        // Closed eyes still read as a word, not only as a percentage.
        XCTAssertTrue(
            FaceReportRollUpPresentation
                .tileAccessibilityValue(for: Self.report(eyesOpen: false))
                .contains("Eyes closed")
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
        let frame = Self.frame([])

        XCTAssertNil(FaceReportRollUpPresentation.dotGrade(for: frame))
        XCTAssertEqual(FaceReportRollUpPresentation.headerValue(for: frame), "No faces")
    }

    func testTheDotIsTheWorstProminentFacesGrade() {
        let frame = Self.frame([
            Self.report(sharpness: Self.cleanScore, light: Self.cleanScore, facing: Self.cleanScore, prominence: 0.3),
            Self.report(sharpness: Self.ruinedScore, light: Self.cleanScore, facing: Self.cleanScore, prominence: 0.3)
        ])

        XCTAssertEqual(FaceReportRollUpPresentation.dotGrade(for: frame), .red)
    }

    func testABelowFloorRuinedFaceCapsTheDotAtYellow() {
        let frame = Self.frame([
            Self.report(sharpness: Self.cleanScore, light: Self.cleanScore, facing: Self.cleanScore, prominence: 0.3),
            Self.report(
                sharpness: Self.ruinedScore,
                light: Self.cleanScore,
                facing: Self.cleanScore,
                prominence: FaceReportGrading.prominenceFloor / 10
            )
        ])

        XCTAssertEqual(FaceReportRollUpPresentation.dotGrade(for: frame), .yellow)
    }

    func testTheHeaderReportsTheSameGradeAsTheDotForTheSameFrame() {
        let frame = Self.frame([
            Self.report(sharpness: Self.middlingScore, light: Self.cleanScore, facing: Self.cleanScore, prominence: 0.3)
        ])

        XCTAssertEqual(FaceReportRollUpPresentation.dotGrade(for: frame), .yellow)
        XCTAssertEqual(FaceReportRollUpPresentation.headerValue(for: frame), "1 face, Check")
    }

    func testTheHeaderPluralizesTheFaceCount() {
        let clean = Self.report(sharpness: Self.cleanScore, light: Self.cleanScore, facing: Self.cleanScore)
        let frame = Self.frame([clean, clean, clean])

        XCTAssertEqual(FaceReportRollUpPresentation.headerValue(for: frame), "3 faces, Clean")
    }

    // MARK: - Rail state (the panel's text and its dot come from one source)

    func testRailStateIsNotReadForAnUncomputedFrame() {
        XCTAssertEqual(FaceReportRollUpPresentation.railState(for: nil), .notRead)
    }

    func testRailStateIsNoFacesForAFacelessFrame() {
        XCTAssertEqual(FaceReportRollUpPresentation.railState(for: Self.frame([])), .noFaces)
    }

    func testRailStateIsFacesWithCountAndGradeOtherwise() {
        let clean = Self.report(sharpness: Self.cleanScore, light: Self.cleanScore, facing: Self.cleanScore)

        XCTAssertEqual(
            FaceReportRollUpPresentation.railState(for: Self.frame([clean, clean])),
            .faces(count: 2, grade: .green)
        )
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

/// What the close-ups rail knows about the selected frame. One value drives
/// both the header's dot and the rail's body text, so the panel can never say
/// "No faces" beside a live grade dot.
enum FaceReportRailState: Equatable {
    case notRead
    case noFaces
    case faces(count: Int, grade: FaceReportGrade)
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

    static func railState(for frame: FrameFaceReport?) -> FaceReportRailState {
        guard let frame else { return .notRead }
        guard let grade = frame.rolledUpGrade else { return .noFaces }
        return .faces(count: frame.reports.count, grade: grade)
    }

    /// nil means no dot at all: either nothing has been computed for the
    /// frame yet, or the frame has no faces. Absence is never "known good".
    static func dotGrade(for frame: FrameFaceReport?) -> FaceReportGrade? {
        frame?.rolledUpGrade
    }

    /// The close-ups header's accessibility value. "No faces" is preserved
    /// verbatim as the faceless empty state that scenario cards assert on.
    static func headerValue(for frame: FrameFaceReport?) -> String {
        switch railState(for: frame) {
        case .notRead:
            return "Faces not read yet"
        case .noFaces:
            return "No faces"
        case .faces(let count, let grade):
            return "\(count) \(count == 1 ? "face" : "faces"), \(word(for: grade))"
        }
    }

    /// One face tile's accessibility value. SwiftUI's
    /// `.accessibilityElement(children: .combine)` collapses the chips' own
    /// labels away, so this composed string is the ONLY thing a live driver
    /// can read — it therefore carries the grade, the eyes state and smile
    /// the chip row deliberately omits, AND every chip's percentage, reusing
    /// `FaceReportChipPresentation` so the two can never drift apart.
    static func tileAccessibilityValue(for report: FaceReport) -> String {
        var segments = [word(for: report.grade)]
        segments.append(report.eyesOpen ? "Eyes open" : "Eyes closed")
        if report.hasSmile {
            segments.append("Smiling")
        }
        segments.append(contentsOf: FaceReportChipPresentation(report: report).entries.map(\.accessibilityText))
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
Expected: PASS — `Executed 19 tests, with 0 failures`.

- [ ] **Step 6: Run the full suite**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2351 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripApp/FaceReportPresentation.swift \
        Sources/TeststripApp/FaceSignalChipView.swift \
        Tests/TeststripAppTests/FaceReportPresentationTests.swift
git commit -m "feat: face report chip and traffic-light roll-up presentation"
```

---

### Task 6: Close-ups panel renders chips, tile dots, and the header roll-up

**Files:**
- Modify: `Sources/TeststripApp/CloseUpFacesPresentation.swift` (whole file — geometry plus `faceIndex`; the asset-level sharpness attribution retires)
- Modify: `Sources/TeststripApp/AppModel.swift:14125-14134` (add `faceReportPreviewSource(for:)` beside `loupePreviewURL`/`loupeZoomPreviewURL`)
- Modify: `Sources/TeststripApp/LibraryGridView.swift:3782-3790` (`LoupeCloseUpCrop`), `:3811` (add the store), `:3894-3907` (split the loupe content task), `:4079-4081` (dot metric), `:4110-4133` (`closeUpsRail`), `:4135-4182` (`closeUpCropCell`, `closeUpMarks`, `closeUpMarksAccessibilityValue`), `:4254-4297` (`refreshCloseUps`)
- Modify: `Sources/TeststripApp/SignalGlyphView.swift:3-6` (correct the stale doc comment)
- Test: `Tests/TeststripAppTests/CloseUpFacesPresentationTests.swift`

**Interfaces:**
- Consumes: `FaceReport` (Task 1B); `FaceReportAnalyzer().reports(in:detections:)` (Task 3B); `FaceReportStore`, `FrameFaceReport`, `FaceReportPreviewSource`, `FaceReportPreviewFloor` (Task 4B); `FaceReportChipPresentation(report:)`, `FaceReportRailState`, `FaceReportRollUpPresentation.color(for:)/.dotGrade(for:)/.railState(for:)/.headerValue(for:)/.tileAccessibilityValue(for:)`, `FaceSignalChipView(entry:)` (Task 5).
- Produces:
  - `CloseUpFacesPresentation.Crop` becomes `struct Crop: Equatable, Identifiable { var id: Int; var faceIndex: Int; var pixelRect: CGRect }` — `eyesState`, `isSmiling`, `sharpnessTone`, the `EyesState`/`SharpnessTone` enums, and the `wholePhotoSignals:` init parameter are all gone.
  - `CloseUpFacesPresentation.init(faces:imagePixelSize:)`
  - `AppModel.faceReportPreviewSource(for assetID: AssetID) -> FaceReportPreviewSource?` (public)
  - `LoupeView` holds `@State private var faceReportStore = FaceReportStore()` and a `currentFaceReport(for:)` helper, both used by Task 7's rail.
  - `LoupeCloseUpCrop { var id: Int; var image: CGImage; var report: FaceReport }`

- [ ] **Step 1: Write the failing test**

Replace the whole contents of `Tests/TeststripAppTests/CloseUpFacesPresentationTests.swift` with the four geometry tests plus two new pairing tests. Seven tests are deleted; every one has a named successor:

| Deleted | Superseded by |
| --- | --- |
| `testEyesStateClosedOnlyWhenBothEyesShut` | `FaceReportAnalyzerTests.testEyesOpenUsesTheSharedBothShutNoiseFloor` + `testBothEyesShutIsTheOneSharedRule` (Task 3A) |
| `testSmileMarkReflectsHasSmile` | `FaceReportAnalyzerTests.testSmileIsCarriedThroughForHoverAndAccessibility` (Task 3A) + `FaceReportPresentationTests.testTileAccessibilityValueCarriesGradeEyesSmileAndEveryChipPercentage` (Task 5) |
| `testSharpnessMarkSharpWhenFaceQualityAboveThreshold` | `FaceReportAnalyzerTests.testDetailedFaceCropScoresSharperThanFlatFaceCrop` (Task 3A) |
| `testSharpnessMarkSoftWhenFaceQualityBelowThreshold` | `FaceReportAnalyzerTests.testDetailedFaceCropScoresSharperThanFlatFaceCrop` (Task 3A) |
| `testSharpnessMarkFallsBackToEyeSharpnessWhenNoFaceQuality` | Retired with the asset-level fallback itself — sharpness is measured per face now, so there is no asset-level signal to fall back to |
| `testSharpnessMarkAbsentWithoutASignal` | `FaceReportAnalyzerTests.testCropTooSmallToMeasureLeavesSharpnessAndLightUnscored` (Task 3A) + `FaceReportPresentationTests.testAnUnscoredSignalSaysNoReadRatherThanZeroPercent` (Task 5) |
| `testSharpnessMarkAbsentOnEveryCropWhenMultipleFacesShareTheSignal` | Retired with the ambiguity itself — `FaceReportAnalyzerTests.testReportsAreReturnedOnePerDetectionInDetectionOrder` (Task 3A) proves every face now gets its own read |

```swift
import CoreGraphics
import Foundation
import TeststripCore
import XCTest
@testable import TeststripApp

final class CloseUpFacesPresentationTests: XCTestCase {
    func testCropsPadAndCenterOnTheFace() {
        let face = Self.face(x: 0.4, y: 0.4, size: 0.2)

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

- [ ] **Step 4: Teach `AppModel` to hand out a floor-quality preview**

In `Sources/TeststripApp/AppModel.swift`, add after `loupeZoomPreviewURL(for:)` (which ends at line 14134):

```swift
    /// The best cached preview at or above the face-report analysis floor,
    /// with the level it came from. nil when nothing good enough is cached
    /// yet — the report store leaves that frame unread rather than grading a
    /// thumbnail, because a grade measured off a 512px preview visibly
    /// changes once the real preview lands (see `FaceReportPreviewFloor`).
    public func faceReportPreviewSource(for assetID: AssetID) -> FaceReportPreviewSource? {
        for level in FaceReportPreviewFloor.acceptedLevelsHighestFirst {
            if let url = previewURL(for: assetID, levels: [level]) {
                return FaceReportPreviewSource(previewURL: url, level: level)
            }
        }
        return nil
    }
```

- [ ] **Step 5: Re-shape the loupe's crop model and add the store**

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

- [ ] **Step 6: Split the loupe content task so the close-ups pass re-runs when a better preview lands**

The existing `.task(id: LoupeContentKey(...))` at lines 3894-3907 both requests previews and refreshes the close-ups. Requesting previews must stay keyed exactly as it is — re-keying it on preview generation would re-dispatch a guaranteed-to-fail request on every bump for a stale asset (the unbounded-retry finding in `cull-012-closeups-panel.md`'s 2026-07-28 run). The close-ups pass, on the other hand, must re-run when the preview improves. Split them:

```swift
                        .task(id: LoupeContentKey(assetID: asset.id.rawValue, showsCullChrome: presentation.showsCullChrome)) {
                            do {
                                if presentation.showsCullChrome {
                                    try model.requestVisibleCullPreview(assetID: asset.id)
                                } else {
                                    try model.requestVisibleLoupePreview(assetID: asset.id)
                                }
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                        }
                        // Re-keyed on the preview generation: report cards are
                        // only measured off a floor-quality preview, so the
                        // pass has to re-run once one lands. This task never
                        // requests a preview, so it cannot re-dispatch work.
                        .task(id: CloseUpsRefreshKey(
                            assetID: asset.id.rawValue,
                            showsCullChrome: presentation.showsCullChrome,
                            previewCacheGeneration: model.previewCacheGeneration(for: asset.id)
                        )) {
                            if presentation.showsCullChrome {
                                await refreshCloseUps(for: asset.id)
                            }
                        }
```

Add the key struct beside `LoupeContentKey` (after line 3801):

```swift
// Like `LoupeContentKey`, but also re-fires when the asset's cached preview
// improves: the close-ups pass only measures report cards off a preview at or
// above `FaceReportPreviewFloor`, so a frame that had only a thumbnail when
// the loupe opened has to be re-read once a real preview is cached.
private struct CloseUpsRefreshKey: Equatable {
    var assetID: String
    var showsCullChrome: Bool
    var previewCacheGeneration: Int
}
```

- [ ] **Step 7: Render the header roll-up, the tile dot, and the chip row**

Add the shared dot metric beside the existing close-ups metrics (after line 4081):

```swift
    // One dot size for the face tile's corner dot, the close-ups header, and
    // the burst rail's roll-up dot — they mean the same thing, so they look
    // the same.
    private static let faceGradeDotSize: CGFloat = 9
```

Add the staleness-checked read helper next to `refreshCloseUps` so every surface goes through one place:

```swift
    // Every face-report read in this view goes through here, so no surface
    // can accidentally render a grade measured off a preview that has since
    // been replaced.
    private func currentFaceReport(for assetID: AssetID) -> FrameFaceReport? {
        faceReportStore.report(
            for: assetID,
            currentGeneration: model.previewCacheGeneration(for: assetID),
            bestAvailableLevel: model.faceReportPreviewSource(for: assetID)?.level
        )
    }
```

Replace `closeUpsRail` (lines 4110-4133) with a version whose text and dot come from the same `FaceReportRailState`:

```swift
    private var closeUpsRail: some View {
        let frameReport = model.selectedAssetID.flatMap { currentFaceReport(for: $0) }
        let state = FaceReportRollUpPresentation.railState(for: frameReport)
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
                if case .faces(let count, _) = state {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            // Body text and header dot are driven by the same state, so the
            // panel can never print "No faces" beside a live grade dot.
            switch state {
            case .notRead:
                Text("Not read yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .noFaces:
                Text("No faces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .faces:
                if closeUpCrops.isEmpty {
                    // Faces were found but every one of them is smaller than
                    // the minimum crop — say so rather than claiming there
                    // are none.
                    Text("Faces too small to crop")
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
    // so it lives in the tile's accessibility value, not the chip row. That
    // value also repeats every chip's percentage, because
    // `.accessibilityElement(children: .combine)` collapses the chips' own
    // labels and a live driver can read nothing else.
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

- [ ] **Step 8: Feed the analyzer and the store from `refreshCloseUps`**

Replace `refreshCloseUps(for:)` (lines 4254-4297) with:

```swift
    // Detection is display-only and per-selection: the cached preview is read
    // off the main actor, analyzed and cropped in memory, and nothing is
    // persisted. The same detections feed the Close-Ups crops, their report
    // cards, the frame's entry in the shared report store (so its rail dot
    // agrees), and the Z zoom-to-face targets. Crops and report cards come
    // from the SAME floor-quality preview, so a tile's chips always describe
    // the face pictured above them.
    private func refreshCloseUps(for assetID: AssetID) async {
        closeUpCrops = []
        guard let source = model.faceReportPreviewSource(for: assetID) else {
            // Nothing at or above the analysis floor is cached yet. Leave the
            // panel in its honest "not read yet" state; the preview request
            // this view already made will bump the generation and re-fire
            // this pass.
            model.setLoupeFaceFocuses([])
            return
        }
        let previewURL = source.previewURL
        let previewCacheGeneration = model.previewCacheGeneration(for: assetID)
        let result = await Task.detached(priority: .utility) { () -> (crops: [LoupeCloseUpCrop], reports: [FaceReport], faceFocuses: [LoupeZoomFocus]) in
            guard let faces = try? CoreImageFaceExpressionAnalyzer().detectFaces(previewURL: previewURL),
                  !faces.isEmpty,
                  let imageSource = CGImageSourceCreateWithURL(previewURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
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
        faceReportStore.record(
            result.reports,
            for: assetID,
            previewCacheGeneration: previewCacheGeneration,
            analyzedLevel: source.level
        )
        model.setLoupeFaceFocuses(result.faceFocuses)
    }
```

- [ ] **Step 9: Correct the stale `SignalGlyphView` doc comment**

In `Sources/TeststripApp/SignalGlyphView.swift`, replace lines 3-6:

```swift
/// One micro signal glyph: an 11pt donut ring (arc sweep = score) with the
/// measure's word beside it. The reads card's glyph line is built from
/// these, and SP-B's per-face report cards reuse the same component —
/// change it here, both surfaces follow.
```

with:

```swift
/// One micro signal glyph: an 11pt donut ring (arc sweep = score) with the
/// measure's word beside it. The reads card's glyph line is built from these
/// and is this view's only consumer. SP-B's per-face report cards do NOT
/// reuse it — `FaceSignalChipView` is a sibling with its own 17pt
/// icon-in-donut geometry, because a 112pt face tile has room for four icons
/// but not four words. Changing this view does not change the face tiles.
```

- [ ] **Step 10: Run test to verify it passes**

Run: `swift test --filter CloseUpFacesPresentationTests 2>&1 | tail -5`
Expected: PASS — `Executed 6 tests, with 0 failures`.

- [ ] **Step 11: Prove the app target still builds and nothing regressed**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` (no unresolved references to `sharpnessTone`, `EyesState`, or `wholePhotoSignals`).

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2346 tests, with 0 failures` — 2351 minus the 7 deleted mark tests, plus the 2 new `faceIndex` tests. If the number differs, read the diff and confirm every removed test has a named successor from Step 1's table before continuing; a bare count drop with no successor is a coverage regression and must be fixed, not accepted.

- [ ] **Step 12: Commit**

```bash
git add Sources/TeststripApp/CloseUpFacesPresentation.swift \
        Sources/TeststripApp/AppModel.swift \
        Sources/TeststripApp/LibraryGridView.swift \
        Sources/TeststripApp/SignalGlyphView.swift \
        Tests/TeststripAppTests/CloseUpFacesPresentationTests.swift
git commit -m "feat: close-ups tiles render per-face chips, corner grade dots, and a header roll-up"
```

---

### Task 7: Burst-rail roll-up dots and the stack sweep

**Files:**
- Modify: `Sources/TeststripApp/FaceReportPresentation.swift` (add `railAccessibilityText(for:)`)
- Modify: `Sources/TeststripApp/LibraryGridView.swift:4825-4827` (add a second `.task(id:)` that runs the sweep), `:4831-4882` (`cullStackRailCell` dot overlay and the new helpers), `:4911-4915` (`stackChipAccessibilityValue`)
- Test: `Tests/TeststripAppTests/FaceReportRailDotTests.swift`

**Interfaces:**
- Consumes: `FaceReportStore.sweep(frames:currentFrameID:)`, `FaceReportSweepFrame(assetID:source:previewCacheGeneration:)` (Task 4B); `FaceReportRollUpPresentation.dotGrade(for:)/.color(for:)/.word(for:)` (Task 5); `LoupeView.currentFaceReport(for:)`, `AppModel.faceReportPreviewSource(for:)` (Task 6); existing `CullingStackRailPresentation.Item`, `AppModel.previewCacheGeneration(for:)`.
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
            light: min(FaceReportGrading.greenSignalFloor + 0.15, 1.0),
            facing: min(FaceReportGrading.greenSignalFloor + 0.15, 1.0),
            prominence: prominence
        )
    }

    private static func frame(_ reports: [FaceReport]) -> FrameFaceReport {
        FrameFaceReport(reports: reports, previewCacheGeneration: 1, analyzedLevel: .medium)
    }

    private static var cleanScore: Double { min(FaceReportGrading.greenSignalFloor + 0.15, 1.0) }
    private static var middlingScore: Double {
        (FaceReportGrading.redSignalCeiling + FaceReportGrading.greenSignalFloor) / 2
    }
    private static var ruinedScore: Double { FaceReportGrading.redSignalCeiling / 2 }

    func testAnUncomputedFrameSaysNothing() {
        XCTAssertNil(FaceReportRollUpPresentation.railAccessibilityText(for: nil))
    }

    func testAFacelessFrameSaysNothing() {
        // Absence means "nothing known", never "known good" — a faceless
        // frame must not announce a clean read.
        XCTAssertNil(FaceReportRollUpPresentation.railAccessibilityText(for: Self.frame([])))
    }

    func testACleanFrameAnnouncesItsGrade() {
        XCTAssertEqual(
            FaceReportRollUpPresentation.railAccessibilityText(for: Self.frame([Self.report(sharpness: Self.cleanScore)])),
            "Faces clean"
        )
    }

    func testARuinedFrameAnnouncesItsGrade() {
        XCTAssertEqual(
            FaceReportRollUpPresentation.railAccessibilityText(for: Self.frame([Self.report(sharpness: Self.ruinedScore)])),
            "Faces ruined"
        )
    }

    func testTheRailDotAndThePanelHeaderReadTheSameFrameTheSameWay() {
        let frame = Self.frame([Self.report(sharpness: Self.middlingScore)])

        XCTAssertEqual(FaceReportRollUpPresentation.dotGrade(for: frame), .yellow)
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
                    // all while the frame is uncomputed, its report is stale,
                    // or it has no faces — absence means "nothing known",
                    // never "known good".
                    if let grade = FaceReportRollUpPresentation.dotGrade(for: currentFaceReport(for: item.assetID)) {
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
            for: currentFaceReport(for: item.assetID)
        ) {
            segments.append(facesText)
        }
        return segments.joined(separator: ", ")
    }
```

- [ ] **Step 6: Start the sweep when the stack membership or any frame's preview changes**

Add a second `.task(id:)` immediately after the existing one on `cullingStackRail` (currently lines 4825-4827), leaving that one untouched:

```swift
            .task(id: presentation.items.map(\.assetID.rawValue).joined(separator: "\n")) {
                requestVisiblePreviews(for: presentation.items.map(\.assetID))
            }
            // A separate task from the preview request above: this one also
            // re-keys on each frame's preview generation and level, so frames
            // skipped for want of a floor-quality preview get picked up the
            // moment one lands, and a level upgrade re-measures. `.task(id:)`
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
    // Deliberately NOT keyed on the selected frame. Selection only decides
    // which frame the sweep does first; keying on it would cancel and restart
    // the whole sweep on every arrow-key press, and a frame further down a
    // stack the photographer is paging through could then never finish
    // computing — exactly the "dots appear for frames you never visited"
    // promise this feature exists to keep.
    private struct FaceReportSweepKey: Equatable {
        var frameIDs: [String]
        var previewGenerations: [Int]
        var previewLevels: [String]
    }

    private func faceReportSweepKey(for presentation: CullingStackRailPresentation) -> FaceReportSweepKey {
        FaceReportSweepKey(
            frameIDs: presentation.items.map(\.assetID.rawValue),
            previewGenerations: presentation.items.map { model.previewCacheGeneration(for: $0.assetID) },
            previewLevels: presentation.items.map {
                model.faceReportPreviewSource(for: $0.assetID)?.level.rawValue ?? ""
            }
        )
    }

    private func faceReportSweepFrames(for presentation: CullingStackRailPresentation) -> [FaceReportSweepFrame] {
        presentation.items.map { item in
            FaceReportSweepFrame(
                assetID: item.assetID,
                source: model.faceReportPreviewSource(for: item.assetID),
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
Expected: `Build complete!` then `Executed 2351 tests, with 0 failures`.

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

### Task 8: A `facestack` seed with a real multi-frame face stack

The `faces` seed's 11 Wikimedia portraits carry no EXIF capture date at all (verified: `mdls -name kMDItemContentCreationDate` is `(null)` for every file), so `AssetStackBuilder.isCaptureTimeNeighbor` can never group them and the burst rail only ever shows a standalone single-frame entry. Without a multi-frame stack containing real faces — plus a faceless frame and a two-face frame — there is no way to prove live that rail dots appear for frames the photographer never visited, that absence is total, or that a background face caps a frame at yellow.

**Files:**
- Create: `Sources/TeststripBench/FaceStackFixtureSeeder.swift`
- Modify: `Sources/TeststripBench/BenchmarkCommand.swift:19` (case) and `:81` (parse)
- Modify: `Sources/TeststripBench/main.swift:37` (dispatch) and after `:387` (runner)
- Modify: `script/vm_scenario_run.sh:44-53` (variant docs), `:160-161` (`seed_dir_for`), after `:195` (`seed_variant`), `:269` (launch usage string)
- Modify: `script/build_and_run.sh:19-26` (flag declaration), `:45` (usage), `:84-89` (dispatch), after `:152` (seed function), `:209-222` vicinity (flag block)
- Test: `Tests/TeststripBenchTests/FaceStackFixtureSeederTests.swift`

**Interfaces:**
- Consumes: existing `CoreImageFaceExpressionAnalyzer`, `BenchmarkImageFixtures.writeJPEG(to:index:)` (module-internal, same pattern `GeoFixtureSeeder` already uses), `FaceReportGrading.prominenceFloor` (Task 1B).
- Produces:
  - `public struct FaceStackFixtureSeederResult: Equatable` with `stackFilenames: [String]`, `singleCount: Int`, `stackCaptureGapSeconds: TimeInterval`, `backgroundFaceProminence: Double`.
  - `public struct FaceStackFixtureSeeder` with `public init(directory: URL, sourcePhotoDirectory: URL)`, `public func run() throws -> FaceStackFixtureSeederResult`, `public static let stackFaceFilenames: [String]`, `public static let stackCompositeFilename: String`, `public static let stackNoFaceFilename: String`.
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
        guard let sourceDirectory = Self.facesCorpusDirectory() else { throw Self.corpusSkip }
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try FaceStackFixtureSeeder(
            directory: directory,
            sourcePhotoDirectory: sourceDirectory
        ).run()

        XCTAssertEqual(result.stackFilenames.count, 4)
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

    func testTheStackCarriesDetectableFacesAndOneDeliberatelyFacelessFrame() throws {
        guard let sourceDirectory = Self.facesCorpusDirectory() else { throw Self.corpusSkip }
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

    // The prominence-cap rule needs a live subject: one frame with a large
    // subject face and one genuinely small background face, so the card can
    // prove that a ruined bystander caps the frame at yellow rather than red.
    func testTheCompositeFrameCarriesASubjectAndABelowFloorBackgroundFace() throws {
        guard let sourceDirectory = Self.facesCorpusDirectory() else { throw Self.corpusSkip }
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try FaceStackFixtureSeeder(
            directory: directory,
            sourcePhotoDirectory: sourceDirectory
        ).run()

        let compositeURL = directory.appendingPathComponent(FaceStackFixtureSeeder.stackCompositeFilename)
        let faces = try CoreImageFaceExpressionAnalyzer().detectFaces(previewURL: compositeURL)

        XCTAssertEqual(faces.count, 2, "composite must present exactly one subject and one background face")
        let areas = faces
            .map { Double($0.normalizedBounds.width * $0.normalizedBounds.height) }
            .sorted()
        XCTAssertLessThan(areas[0], FaceReportGrading.prominenceFloor, "background face must sit below the prominence floor")
        XCTAssertGreaterThan(areas[1], FaceReportGrading.prominenceFloor, "subject face must sit above the prominence floor")
        XCTAssertEqual(result.backgroundFaceProminence, areas[0], accuracy: 0.0001)
    }

    private static var corpusSkip: XCTSkip {
        XCTSkip("No downloaded sample photos (run script/download_sample_photos.sh --manifest sample-data/faces.tsv --destination sample-data/photos/faces)")
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
import CoreImage
import Foundation
import ImageIO
import TeststripCore
import UniformTypeIdentifiers

public struct FaceStackFixtureSeederResult: Equatable {
    public var stackFilenames: [String]
    public var singleCount: Int
    public var stackCaptureGapSeconds: TimeInterval
    public var backgroundFaceProminence: Double

    public init(
        stackFilenames: [String],
        singleCount: Int,
        stackCaptureGapSeconds: TimeInterval,
        backgroundFaceProminence: Double
    ) {
        self.stackFilenames = stackFilenames
        self.singleCount = singleCount
        self.stackCaptureGapSeconds = stackCaptureGapSeconds
        self.backgroundFaceProminence = backgroundFaceProminence
    }
}

/// Writes the fixture the per-face report-card card needs: one folder where
/// four frames fall inside `AssetStackBuilder`'s capture window (so the burst
/// rail shows a real multi-frame stack) and everything else is hours apart
/// (so it stays a standalone stop). Two stack frames are real portraits; a
/// third is a composite carrying one subject face and one genuinely small
/// background face, so the prominence cap can be proved live; the fourth is
/// deliberately faceless, which is the card's falsification leg — a frame
/// with no faces must never get a rail dot.
///
/// The faces corpus itself carries no EXIF capture date, so the copies made
/// here get one written in. Originals in `sample-data/photos/faces` are never
/// modified.
public struct FaceStackFixtureSeeder {
    public static let stackFaceFilenames = ["stack-1-face.jpg", "stack-2-face.jpg"]
    public static let stackCompositeFilename = "stack-3-two-faces.jpg"
    public static let stackNoFaceFilename = "stack-4-noface.jpg"

    /// Portraits picked because both are single, well-lit, front-facing
    /// subjects that the live CIDetector pass reliably finds (`run()` asserts
    /// this, so a corpus change fails loudly instead of silently producing a
    /// faceless "face" stack).
    private static let stackSourceFilenames = [
        "commons-glenn-senator-portrait.jpg",
        "commons-ride-1984-portrait.jpg"
    ]

    /// Candidate widths for the composited background face, as a fraction of
    /// the subject frame's width. `run()` walks them smallest-first and keeps
    /// the first that CIDetector actually finds while still landing below
    /// `FaceReportGrading.prominenceFloor` — measured acceptance, not a
    /// guessed size.
    private static let backgroundWidthFractions = [0.06, 0.08, 0.10, 0.13, 0.16]

    /// 1s apart: comfortably inside the 2s window, and chained so all four
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
        let analyzer = CoreImageFaceExpressionAnalyzer()

        var sourceURLs: [URL] = []
        for (index, sourceName) in Self.stackSourceFilenames.enumerated() {
            let sourceURL = sourcePhotoDirectory.appendingPathComponent(sourceName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw TeststripError.invalidState("face stack fixture source missing: \(sourceURL.path)")
            }
            sourceURLs.append(sourceURL)
            let destinationURL = directory.appendingPathComponent(Self.stackFaceFilenames[index])
            try Self.copyJPEG(
                from: sourceURL,
                to: destinationURL,
                capturedAt: Self.baseCapture.addingTimeInterval(Double(index) * Self.stackGapSeconds)
            )
            guard try !analyzer.detectFaces(previewURL: destinationURL).isEmpty else {
                throw TeststripError.invalidState("face stack fixture \(sourceName) yielded no detectable face")
            }
        }

        let compositeURL = directory.appendingPathComponent(Self.stackCompositeFilename)
        let backgroundProminence = try Self.writeComposite(
            subjectURL: sourceURLs[0],
            backgroundURL: sourceURLs[1],
            to: compositeURL,
            capturedAt: Self.baseCapture.addingTimeInterval(2 * Self.stackGapSeconds),
            analyzer: analyzer
        )

        let facelessURL = directory.appendingPathComponent(Self.stackNoFaceFilename)
        try BenchmarkImageFixtures.writeJPEG(to: facelessURL, index: 0)
        try Self.stampCapture(
            at: facelessURL,
            capturedAt: Self.baseCapture.addingTimeInterval(3 * Self.stackGapSeconds)
        )
        guard try analyzer.detectFaces(previewURL: facelessURL).isEmpty else {
            throw TeststripError.invalidState("the deliberately faceless stack frame grew a detectable face")
        }

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
            stackFilenames: Self.stackFaceFilenames + [Self.stackCompositeFilename, Self.stackNoFaceFilename],
            singleCount: remaining.count,
            stackCaptureGapSeconds: Self.stackGapSeconds,
            backgroundFaceProminence: backgroundProminence
        )
    }

    /// Composites `backgroundURL` into the top-right corner of `subjectURL` at
    /// the smallest candidate size CIDetector still finds while staying below
    /// the prominence floor, and returns that background face's measured area
    /// fraction. Throws if no candidate satisfies both — a silently oversized
    /// "background" face would make the card's prominence-cap leg vacuous.
    private static func writeComposite(
        subjectURL: URL,
        backgroundURL: URL,
        to destinationURL: URL,
        capturedAt: Date,
        analyzer: CoreImageFaceExpressionAnalyzer
    ) throws -> Double {
        guard let subject = CIImage(contentsOf: subjectURL),
              let background = CIImage(contentsOf: backgroundURL) else {
            throw TeststripError.io("could not read composite fixture sources")
        }
        let context = CIContext()
        for fraction in backgroundWidthFractions {
            let scale = (subject.extent.width * fraction) / background.extent.width
            let scaled = background.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let inset = subject.extent.width * 0.04
            let placed = scaled.transformed(by: CGAffineTransform(
                translationX: subject.extent.maxX - scaled.extent.width - inset,
                y: subject.extent.maxY - scaled.extent.height - inset
            ))
            let composite = placed.composited(over: subject).cropped(to: subject.extent)
            guard let cgImage = context.createCGImage(composite, from: composite.extent),
                  let destination = CGImageDestinationCreateWithURL(
                    destinationURL as CFURL,
                    UTType.jpeg.identifier as CFString,
                    1,
                    nil
                  ) else {
                throw TeststripError.io("could not render composite fixture")
            }
            CGImageDestinationAddImage(destination, cgImage, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw TeststripError.io("could not write composite fixture")
            }
            try stampCapture(at: destinationURL, capturedAt: capturedAt)

            let faces = try analyzer.detectFaces(previewURL: destinationURL)
            let areas = faces
                .map { Double($0.normalizedBounds.width * $0.normalizedBounds.height) }
                .sorted()
            if areas.count == 2,
               areas[0] < FaceReportGrading.prominenceFloor,
               areas[1] >= FaceReportGrading.prominenceFloor {
                return areas[0]
            }
        }
        throw TeststripError.invalidState(
            "no composite scale produced one subject face above and one background face below the prominence floor"
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
    print("background face prominence: \(result.backgroundFaceProminence)")
    print("standalone frames: \(result.singleCount)")
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter FaceStackFixtureSeederTests 2>&1 | tail -8`
Expected: PASS — `Executed 4 tests, with 0 failures`. If the corpus is not downloaded, three of the four SKIP; run `script/download_sample_photos.sh --manifest sample-data/faces.tsv --destination sample-data/photos/faces` and re-run so all four actually execute before moving on.

- [ ] **Step 6: Add the `facestack` VM seed variant**

In `script/vm_scenario_run.sh`, add to the seed-variant doc block (after the `faces` line, line 52):

```bash
#   facestack sample-data/photos/faces re-stamped with EXIF capture times so
#             four frames form one burst stack: two real portraits, one
#             composite (subject + small background face), and one
#             deliberately faceless frame; for the per-face report-card card
```

extend `seed_dir_for` (lines 160-161):

```bash
    smoke|smokebig|burst|geo|faces|facestack|empty) echo "$SEED_ROOT/$1" ;;
    *) echo "unknown seed variant: $1 (want smoke|smokebig|burst|geo|faces|facestack|empty)" >&2; exit 2 ;;
```

add the seeding arm **after line 195** — the `;;` that closes the `faces)` arm, so the new arm sits between `faces)` and `empty)`:

```bash
    facestack)
      local photos="$ROOT_DIR/sample-data/photos/faces"
      [[ -d "$photos" ]] || "$ROOT_DIR/script/download_sample_photos.sh" --manifest "$ROOT_DIR/sample-data/faces.tsv" --destination "$photos"
      # Originals land inside the seed dir, so the host->VM rsync ships them
      # and `launch`'s original_path prefix rewrite relocates them for free
      # (the same reason the `geo` arm writes into "$dir/GeoOriginals").
      ( cd "$ROOT_DIR" \
        && swift run TeststripBench seed-face-stack-fixtures "$dir/FaceStackOriginals" "$photos" \
        && swift run TeststripBench seed-sample-catalog "$dir" "$dir/FaceStackOriginals" )
      ;;
```

and extend the `launch` usage string (line 269):

```bash
  local variant="${1:?usage: $0 launch VARIANT (smoke|smokebig|burst|geo|faces|facestack|empty)}"
```

- [ ] **Step 7: Add the host `--face-stack` flag, dispatched where the other seeds are**

`--faces` works by setting `SAMPLE_PHOTOS=1` and overriding the manifest/dir, so it reaches `seed_sample_catalog`. A `FACE_STACK=1` flag reaches nothing unless it gets its own dispatch arm — wire all four pieces:

1. Declare the flag beside the other seed flags (after line 25):

```bash
FACE_STACK=0
```

2. Add the dispatch arm inside `open_app`'s `ISOLATED` block, after the `REAL_CORPUS` arm (line 89):

```bash
    if [[ "$FACE_STACK" == "1" ]]; then
      seed_face_stack_catalog
    fi
```

3. Add the seed function after `seed_sample_catalog` (after line 152):

```bash
seed_face_stack_catalog() {
  cd "$ROOT_DIR"
  local photos="$ROOT_DIR/sample-data/photos/faces"
  if [[ ! -d "$photos" ]] || [[ -z "$(find "$photos" -maxdepth 1 -type f -print -quit)" ]]; then
    "$ROOT_DIR/script/download_sample_photos.sh" --manifest "$ROOT_DIR/sample-data/faces.tsv" --destination "$photos"
  fi
  local originals="$ISOLATED_APPLICATION_SUPPORT/FaceStackOriginals"
  swift run "$BENCH_PRODUCT_NAME" seed-face-stack-fixtures "$originals" "$photos"
  swift run "$BENCH_PRODUCT_NAME" seed-sample-catalog "$ISOLATED_APPLICATION_SUPPORT" "$originals"
}
```

4. Add the flag block beside `--faces` (after the `--verify-faces` arm, line 222), and add `|--face-stack|--verify-face-stack` to the usage line (line 45):

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

- [ ] **Step 8: Prove the host flag actually seeds, then prove the VM variant does**

Run: `./script/build_and_run.sh --verify-face-stack 2>&1 | tail -20`
Expected: the seeder's `stack frames: stack-1-face.jpg, stack-2-face.jpg, stack-3-two-faces.jpg, stack-4-noface.jpg` line appears, followed by the verifier's success line. An immediate app launch with **no** seeding output means the dispatch arm is not reached — fix Step 7 before continuing.

Run:
```bash
rm -rf "$TMPDIR/teststrip-vm-seeds/facestack" && \
  script/vm_scenario_run.sh sync facestack 2>&1 | tail -20 && \
  sqlite3 "$TMPDIR/teststrip-vm-seeds/facestack/Teststrip/catalog.sqlite" \
    "SELECT original_path, json_extract(technical_metadata_json, '\$.capturedAt') FROM assets ORDER BY 2;" | head -6
```
Expected: `sync complete`, and the first four rows are `stack-1-face.jpg`, `stack-2-face.jpg`, `stack-3-two-faces.jpg`, `stack-4-noface.jpg` with capture values 1 second apart; every later row is at least an hour after them.

- [ ] **Step 9: Run the full suite**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 2355 tests, with 0 failures`.

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
- Consumes everything from Tasks 0-8 as assembled and rendered: the `Face close-ups` AX label and its header value, each face tile's combined AX value (which carries the grade, eyes state, smile, and all four chip percentages), the rail cell's `Stack frame N` value with its `Faces clean|check|ruined` segment, and the `facestack` seed variant.
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
`previewCacheGeneration` **and** the preview level they were measured at, and
sweeps the current stack's frames (current frame first, then rail order);
`closeUpsRail`/`closeUpCropCell`/`closeUpChips` and `cullStackRailCell` in
`Sources/TeststripApp/LibraryGridView.swift` render the header roll-up, the
per-tile corner dot and chip row, and the rail dots. Grading constants were
measured over this same corpus — see the frozen-constants table in
`docs/superpowers/plans/2026-08-01-per-face-report-cards-final.md`.

**No worker involvement.** Unlike `cull-012-closeups-panel.md`, this card needs
**no** Evaluate Matches pass, no `face_observations`, and no AuraFace CoreML
model: every number on screen comes from the app's own live CIDetector +
Vision pass over the cached preview. Do not wait on the worker.

**AX reality this card is built around.** Each face tile is an
`.accessibilityElement(children: .combine)`, which collapses the chips' own
labels — `ax find --contains "Sharpness 82%"` will NEVER match, exactly as
`cull-012-closeups-panel.md`'s 2026-07-29 run found live for the same
construction (see that card's lines 349-360: the composed string lands on
`AXValueDescription`, `AXValue` is absent entirely, and `ax_drive.sh`'s
`--contains` does not search `AXValueDescription`). Every chip assertion here
therefore reads the **tile's combined value** out of a raw attribute dump.
`FaceReportRollUpPresentation.tileAccessibilityValue` exists in exactly that
shape for exactly this reason: it repeats all four chip strings.

## Pre-state
```bash
script/vm_scenario_run.sh sync facestack
script/vm_scenario_run.sh launch facestack
script/vm_scenario_run.sh ax wait-vended Teststrip
```

The `facestack` seed is `sample-data/photos/faces` re-stamped with EXIF
capture times: four frames 1s apart form one burst stack —
`stack-1-face.jpg` and `stack-2-face.jpg` (real portraits, faces guaranteed
present, asserted at seed time), `stack-3-two-faces.jpg` (a composite with one
subject face above the prominence floor and one background face below it, both
asserted at seed time), and `stack-4-noface.jpg` (a synthetic flat frame with
**no** faces, the falsification leg) — and every other photo is an hour away,
so it stays a standalone stop.

## Steps

1. Confirm the fixture really is one four-frame stack before asserting
   anything about it:
   ```bash
   script/vm_scenario_run.sh sql facestack \
     "SELECT original_path, json_extract(technical_metadata_json,'\$.capturedAt') FROM assets ORDER BY 2 LIMIT 5;"
   ```
   Expect `stack-1-face.jpg`, `stack-2-face.jpg`, `stack-3-two-faces.jpg`,
   `stack-4-noface.jpg` in that order, 1s apart, then a fifth asset at least
   an hour later.

2. Switch to the Cull workspace (⌘1) and select `stack-1-face.jpg`. Wait for
   the close-ups panel, then read the rail:
   ```bash
   script/vm_scenario_run.sh ax wait --role AXStaticText --contains "CLOSE-UPS"
   script/vm_scenario_run.sh ax find --contains "Face close-ups"
   script/vm_scenario_run.sh ax find --contains "No faces"       # expect exit nonzero
   script/vm_scenario_run.sh ax find --contains "Not read yet"   # expect exit nonzero
   ```
   If `Not read yet` matches and does not clear within ~10s, the frame has no
   cached preview at or above `FaceReportPreviewFloor` yet — poll
   `ax find --contains "Not read yet"` until it stops matching (re-asserting
   frontmost with `ax wait-vended` on every poll) before continuing.

3. **Chips, read off the tile's combined value.** Locate the tile, then dump
   its raw AX attributes — do **not** try to `--contains` an individual chip
   string:
   ```bash
   script/vm_scenario_run.sh ax find --label "Face"
   # then dump the matched element's attributes (AXValueDescription carries
   # the composed value; AXValue is absent for this construction)
   ```
   The composed value must match the shape
   `"<Clean|Check|Ruined>, Eyes <open|closed>[, Smiling], Eyes <NN>%, Sharpness <NN>%, Facing <NN|no read>, Light <NN>%"`
   — grade first, then eyes state and smile, then all four chip readings in
   the fixed order eyes, sharpness, facing, light. Assert every one of the
   four signal words is present in that single string, and that the four
   readings are either `<NN>%` or the literal `no read`.

4. **Panel header roll-up.** The `Face close-ups` element's accessibility
   value must be `"N faces, <Clean|Check|Ruined>"` for this frame — never
   `"Faces not read yet"` once tiles have rendered, and never `"No faces"`
   while a tile is on screen.

5. **Rail dots without visiting.** Without ever selecting frames 2, 3 or 4,
   read the stack rail cells' accessibility values:
   ```bash
   script/vm_scenario_run.sh ax find --contains "Stack frame 2"
   script/vm_scenario_run.sh ax find --contains "Stack frame 3"
   script/vm_scenario_run.sh ax find --contains "Stack frame 4"
   ```
   Frames 2 and 3 must each carry a `Faces clean|check|ruined` segment (the
   sweep reached them without a visit). Frame 4 must carry **no** `Faces`
   segment at all, and no dot may be drawn on its thumb — capture a
   screenshot and confirm the absence visually:
   ```bash
   script/vm_scenario_run.sh shell 'cd ~/teststrip-vm && ./script/capture_app_window.sh Teststrip'
   ```

6. **The prominence cap, live.** Select `stack-3-two-faces.jpg`. Its panel
   header must report **2 faces**, and its rail dot and header grade must be
   `Clean` or `Check` — **never** `Ruined` — even if the composited
   background face's own tile shows a ruined signal. Dump both tiles' combined
   values and record the background tile's own grade word alongside the
   frame's roll-up.

7. **Panel and rail agree.** Back on frame 1, compare the grade word in the
   panel header value (step 4) with the grade word in frame 1's own rail-cell
   value. They must be the same word for the same frame. Repeat for frame 3.

8. **Nothing is written.** Capture catalog counts before step 2 and again
   after step 7:
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

- Step 2: the close-ups rail renders at least one tile for
  `stack-1-face.jpg`. **Fails if** `"No faces"` is present while a portrait is
  selected, or if `"Not read yet"` never clears.
- Step 3: the tile's combined value carries the grade word, the eyes state,
  and all four signal readings in the fixed order. **Fails if** any of the
  four words is missing from that string (a missing chip would read as a clean
  signal), if an unmeasured signal shows `0%` instead of `no read`, or if the
  string mentions a smile glyph in the chip positions (smile is a separate
  segment, never a chip).
- Step 4: the header value is `"N faces, <word>"` with N matching the frame's
  detected face count.
- Step 5: frames 2 and 3 carry a `Faces …` segment; frame 4 carries none and
  shows no dot. **Fails if** frames 2/3 have no `Faces …` segment (the sweep
  never reached an unvisited frame — the feature's headline claim), **and
  equally fails if** frame 4 *does* get a dot (absence turned into "known
  good").
- Step 6: the composite frame reports 2 faces and rolls up to at worst
  `Check`. **Fails if** it rolls up `Ruined` — that would mean a background
  face below the prominence floor graded the frame red, breaking the
  prominence-weighted roll-up the whole design rests on.
- Step 7: the two grade words are identical for each frame tested. **Fails
  if** the panel and the rail disagree — they must come from one computation
  through one staleness-checked accessor.
- Step 8: all three counts are unchanged and zero `.xmp` files exist. **Fails
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
- **Never assert an individual chip with `ax find --contains`.** The tile
  combines its children, so per-chip labels do not survive into the AX tree.
  Steps 3, 6 and 7 read the tile's composed value from a raw attribute dump
  (`AXValueDescription`), the same technique `cull-012-closeups-panel.md` and
  `cull-024-honest-states.md` both had to fall back to.
- Frame 4's dot ABSENCE is the falsification leg. Do not weaken it to "the dot
  is grey" or "the dot is missing sometimes" — absence must be total and
  stable across the whole run.
- Report cards are only measured off a preview at or above
  `FaceReportPreviewFloor`. A frame showing `"Not read yet"` is not a bug
  unless it persists after its preview lands; grades that *changed* as
  previews upgraded would be the bug, and that is what the floor exists to
  prevent.
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
time; because the tile still combines its children for accessibility, the
per-chip readings are repeated inside the tile's own composed value
(`"<Grade>, Eyes <open|closed>[, Smiling], Eyes NN%, Sharpness NN%, Facing
NN%, Light NN%"`), which is the only string a live driver can read. Smile is
a segment of that value, never a chip. The single-face-only sharpness
attribution limit is gone with it: sharpness is now measured per face over
that face's own crop (`FaceReportAnalyzer`), so a 2+-face frame shows a
sharpness chip on **every** tile — the old "no crop shows Sharp/Soft with 2+
faces" assertion in Step 5 and Expected step 5 is superseded and must not be
re-asserted. `CloseUpFacesPresentation` no longer has `eyesState`,
`isSmiling`, `sharpnessTone`, or a `wholePhotoSignals:` parameter; it owns
crop geometry plus a `faceIndex` pairing only. Two further behavior changes
this card's future runs will see: the panel's body text is now driven by the
report store rather than by the crop list (so a frame whose faces are all too
small to crop reads "Faces too small to crop", not "No faces"), and report
cards are only measured off a preview at or above `FaceReportPreviewFloor`, so
a freshly-selected frame can briefly read "Not read yet". Everything else this
card covers is unchanged: the 112px crop size, the Cull-chrome-only gate, the
`"No faces"` empty state for a genuinely faceless frame, and the
display-only/nothing-persisted behavior. The replacement assertions live in
`cull-028-face-report-cards.md`.
```

- [ ] **Step 3: Run the card live in the VM**

Run, in order:
```bash
script/vm_scenario_run.sh setup
script/vm_scenario_run.sh sync facestack
script/vm_scenario_run.sh launch facestack
script/vm_scenario_run.sh ax wait-vended Teststrip
```
then drive the card's Steps 1-8 with `script/vm_scenario_run.sh ax …` /
`sql …` calls, re-asserting frontmost (`ax wait-vended`) on every poll during
any wait so the app never idle-wedges.

Expected: every Expected bullet holds. Record the outcome — pass, partial, or
fail with the exact evidence — in a new **Run status** entry at the bottom of
`test/scenarios/cull-028-face-report-cards.md`, including the app commit, the
VM name, and the seed variant, matching the format of the existing entries in
`cull-012-closeups-panel.md`.

- [ ] **Step 4: Fix anything the live run found**

If the run turns up a defect, fix it with a test-first cycle in the owning
task's files (analyzer bugs in Task 3B's files, store bugs in Task 4B's,
rendering bugs in Task 6/7's), re-run `swift test`, and re-drive the failing
card step before continuing. Do not weaken a card assertion to make it pass.
If a *grading* constant looks wrong on the live corpus, that is a Task 0
re-measurement — re-derive from the rules and update the frozen-constants
table, never hand-tune a literal in `FaceReportGrading`.

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

Re-run after amending. Findings were fixed inline before this file was saved.

**1. Spec coverage**

| Spec requirement | Task |
| --- | --- |
| Prominence-weighted roll-up; below-floor face caps at yellow | Task 0 (measured floor) + 1B (`FaceReportGrading.grade`) + 4B (`rolledUpGrade`) + 8 (live composite fixture) + 9 Step 6 |
| Tile = crop + corner traffic dot + always-on row of four icon-in-donut chips (17pt ring, sweep = score, monochrome icon) | Task 5 (`FaceSignalChipView`) + Task 6 (`closeUpCropCell`, `closeUpChips`) |
| Smile moves to hover/AX | Task 5 (`tileAccessibilityValue`), Task 6 (chip row has no smile) |
| Approach A: one Core analyzer + one central in-app store, no worker, no schema | Tasks 3B + 4B; asserted negatively by Task 9 Step 8 |
| Existing fields carried through (bounds, eyes, smile); eye centers stay on `DetectedFaceExpression` | Task 3B (`reports(in:detections:)`; `leftEyeCenter`/`rightEyeCenter` untouched) |
| facing from one `VNDetectFaceRectanglesRequest`, matched by greatest IoU, unmatched → nil | Tasks 2B + 3B (`VisionFaceOrientationDetector`), with the flip and pose extraction directly tested (Task 3A) |
| light = existing `balancedExposure` over the crop's luminance | Task 3B (extracted into `PreviewPixelMetrics.balancedExposure`) |
| sharpness = existing neighbor-delta metric over the crop; retires the single-face `sharpnessTone` limit | Task 3B + Task 6 (`sharpnessTone` deleted, with a successor table) |
| prominence = face area / frame area, used for grading and sort order | Task 3B + Task 6 (crops sort largest-first) |
| Grade thresholds in one place with a WHY comment | Task 0 (measurement) + Task 1B (`FaceReportGrading`) |
| Analyzer pure w.r.t. app state; failed Vision → `facing == nil`, never a fake green | Task 3A `testFailedOrientationRequestLeavesEveryFacingUnscored` |
| `@MainActor` observable cache keyed on `previewCacheGeneration`; stale → recompute **on next read or sweep** | Task 4B (`report(for:currentGeneration:bestAvailableLevel:)` returns nil on stale; sweep re-analyzes) |
| Sweep: current frame first, then rail order, off main actor, publishing progressively | Task 4B (`sweepOrder`, `sweep`) + Task 7 (`.task(id:)`) |
| Frames with no cached preview skipped, picked up on generation bump | Task 4A (two dedicated tests) + Task 7 (`FaceReportSweepKey` carries generations and levels) |
| Cancellation on stack change; no queue, no worker items | Task 4A/4B (cancellation legs) + Task 7 (`.task(id:)` cancellation, selection deliberately excluded from the key) |
| Single computation source: `refreshCloseUps` feeds analyzer → store | Task 6 (`record(...)` from `refreshCloseUps`, same preview for crops and reports) |
| Burst-rail thumb: one overlay dot, top-leading, no dot while uncomputed or faceless | Task 7 |
| Panel roll-up: header dot + face count, panel and rail always agree | Task 5 (`railState`, `headerValue`, `dotGrade`) + Tasks 6/7 (both read `currentFaceReport(for:)`) + Task 7 test + Task 9 Step 7 |
| `SignalGlyphView` untouched; chip is a sibling | Task 5 (new file) + Task 6 Step 9 (its stale comment corrected, nothing else) |
| Out of scope respected (no persistence, no `EvaluationKind`, no `shutOK(context)`, no run-strip dots, no reads-card or verdict change) | No task touches `CullReadsCardPresentation`, `CullRunStripPresentation`, `EvaluationKind`, or any catalog write |
| Unit tests: analyzer, store, presentation — including the stated negatives | Tasks 1A-7 |
| E2E scenario card, faces fixtures, VM, ABSENCE falsification leg | Task 8 (fixture) + Task 9 (card + live run) |

No gaps.

**2. Placeholder scan**

No "TBD", "TODO", "implement later", "add error handling", "similar to Task N", or bare "write tests" appears. The only intentionally unfilled values are the frozen-constants table's six cells and the `<…>` slots that read from it; each has a stated deterministic derivation rule, a hard gate blocking Task 1A until Task 0 fills and commits them, and acceptance legs that fail loudly if a value is wrong. That is a computed value with a specified computation, not a "figure it out later".

**3. Type consistency (swept after the amendments moved types)**

- `FrameFaceReport(reports:previewCacheGeneration:analyzedLevel:)` — the three-argument form is used identically in Task 4A's tests, Task 4B's `sweep`/`record`, Task 5's `frame(_:)` helper, and Task 7's `frame(_:)` helper. No two-argument call survives anywhere.
- `report(for:currentGeneration:bestAvailableLevel:)` — every read goes through it: Task 4A's tests call it directly; Tasks 6 and 7 call it only via `LoupeView.currentFaceReport(for:)`, which supplies both arguments from `AppModel.previewCacheGeneration(for:)` and `AppModel.faceReportPreviewSource(for:)?.level`. No unconditional cache read remains.
- `record(_:for:previewCacheGeneration:analyzedLevel:)` — four arguments in Task 4A's tests, Task 4B's definition, and Task 6's `refreshCloseUps`.
- `FaceReportSweepFrame(assetID:source:previewCacheGeneration:)` — `source: FaceReportPreviewSource?` (not `previewURL:`) in Task 4A's helper, Task 4B's definition, and Task 7's `faceReportSweepFrames(for:)`.
- `FaceReportPreviewSource(previewURL:level:)` — constructed in Task 4A's helper, `AppModel.faceReportPreviewSource(for:)` (Task 6), and consumed by Task 6's `refreshCloseUps` (`source.previewURL`, `source.level`) and Task 7's sweep frames.
- `FaceReportPreviewFloor.lowestAcceptedLevel` / `.accepts(_:)` / `.acceptedLevelsHighestFirst` — defined in Task 4B, tested in Task 4A, consumed by `AppModel.faceReportPreviewSource(for:)` in Task 6.
- `FaceReport(normalizedBounds:eyesOpen:hasSmile:sharpness:light:facing:prominence:)` is constructed identically in Tasks 3B, 4A, 5 and 7; `grade` is computed, never passed.
- `sharpness`, `light`, `facing` are `Double?` everywhere (Task 1B declares them optional; Task 3B returns nil for unmeasurable crops; Task 5 renders nil as an empty ring and `"no read"`; Task 1B's grading `compactMap`s them out).
- `FaceReportRollUpPresentation` members are declared in Task 5 (`word`, `color`, `railState`, `dotGrade`, `headerValue`, `tileAccessibilityValue`) and extended once in Task 7 (`railAccessibilityText`). Task 6 uses only Task 5's members.
- `FaceReportRailState` is produced by Task 5 and consumed only by Task 6's `closeUpsRail`, which drives both the body text and the header dot from it — the "No faces beside a live dot" contradiction cannot recur.
- `faceGradeDotSize` is declared once (Task 6) and reused by Task 7's rail dot.
- `CloseUpFacesPresentation.Crop.faceIndex` is introduced in Task 6 and consumed only there. `testCropsPadAndCenterOnTheFace` passes `y: 0.4` explicitly, so its `CGRect(x: 340, y: 340, …)` assertion matches the helper's actual geometry rather than the helper's `y: 0.1` default.
- `DetectedFaceExpression.bothEyesShut` is added in Task 3B and used by Task 3B's analyzer and Task 3A's test; Task 6's rewritten presentation no longer computes eye state at all.
- `FaceStackFixtureSeeder.stackFaceFilenames` / `.stackCompositeFilename` / `.stackNoFaceFilename` are declared in Task 8 and referenced by Task 8's tests and Task 9's card; the card's four filenames match the seeder's four exactly.
- Test-count arithmetic reconciles end to end: 2281 → 2290 (1A/1B, 9) → 2302 (2A/2B, 12) → 2316 (3A/3B, 14) → 2332 (4A/4B, 16) → 2351 (5, 19) → 2346 (6, −11 +6) → 2351 (7, 5) → 2355 (8, 4).
