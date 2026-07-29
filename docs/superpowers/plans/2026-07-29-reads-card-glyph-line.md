# Reads Card Glyph Line Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the reads card's percentage rows with a one-line micro-donut glyph row covering every scored rankable kind (face kinds included), per the approved spec `docs/superpowers/specs/2026-07-29-reads-card-glyph-line-design.md`.

**Architecture:** Presentation-only. `CullReadsCardPresentation` (pure, unit-tested) emits ordered glyph entries instead of signal rows; a new small reusable `SignalGlyphView` renders one donut+word pair; the card view in `LibraryGridView.swift` swaps its row stack for the glyph lines. No scorer, catalog, or worker changes.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI (macOS), XCTest.

## Global Constraints

- Composite math untouched: `CullingAssistPresentation.verdict`, `normalizedQualityRead`, weights, thresholds, `tooCloseToCallMargin` must not change.
- Exact copy, byte-for-byte: empty state `No read yet`; partial caveat `early read — 1 signal` (em dash U+2014); words `Focus`, `Motion`, `Framing`, `Looks`, `Eyes`, `Face`, `Eye sharp`.
- Glyph AX/help format: `<Word> <NN>%` via `EvaluationSignalPresentation.percentage` (e.g. `Focus 82%`). Verdict help format: `Composed read <0.NN> from <N> signals` where N = scored kind count.
- Honest states: absent kinds render nothing (no fake zeros); no-call (full read between thresholds) renders pure silence in the verdict slot; no verdict is ever computed off one signal.
- Component scores are already defect-inverted at the core layer (`CullingQualityScore.qualityComponent` returns `1 − score` for motionBlur). The presentation must NOT invert again.
- Card AX container value chain stays `emptyState ?? verdictText ?? earlyReadCaveat ?? ""`.
- Views stay inline in `LibraryGridView.swift` except the one new reusable component file `SignalGlyphView.swift` (SP-B reuses it).
- TDD with red-proof transcripts for every behavior change (project rule; capture failing output before implementing).

---

### Task 1: Presentation — glyph entries replace signal rows

**Files:**
- Modify: `Sources/TeststripApp/CullReadsCardPresentation.swift` (whole file, 108 lines today)
- Test: `Tests/TeststripAppTests/CullReadsCardPresentationTests.swift` (rewrite; keep the private `signal(kind:value:confidence:)` helper as-is)

**Interfaces:**
- Consumes: `CullingStackRecommendation.bestComponentByKind(for:)` and `.normalizedQualityRead(for:)` (existing, unchanged), `CullingAssistPresentation.verdict(for:)` (existing, unchanged), `EvaluationSignalPresentation.percentage(_:)` (existing).
- Produces (Task 2 and SP-B rely on these exact names):
  - `struct CullReadsCardPresentation.GlyphEntry: Equatable { var kind: EvaluationKind; var word: String; var score: Double; var accessibilityText: String }`
  - `var glyphEntries: [GlyphEntry]` (replaces `signalRows`; `SignalRow` is deleted)
  - `var wholePhotoGlyphEntries: [GlyphEntry]` and `var faceGlyphEntries: [GlyphEntry]` (computed split for the two-line layout)
  - `var verdictHelp: String?` (non-nil exactly when `verdictText` is non-nil)
  - `static let canonicalSignalOrder: [EvaluationKind]` (now 7 kinds)
  - `static func word(for kind: EvaluationKind) -> String?`

- [ ] **Step 1: Rewrite the test file with the new contract (failing first)**

Replace the seven existing test funcs (keep the file header, class, and the private `signal` helper) with:

```swift
    func testThreeScoredKindsRenderVerdictAndGlyphEntriesIncludingFaceKinds() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.96), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.9), confidence: 1.0),
            signal(kind: .eyesOpen, value: .score(1.0), confidence: 0.7)
        ])

        // (0.96 * 100 + 0.9 * 50 + 1.0 * 63) / 213 = 0.9577..., above Keep.
        XCTAssertEqual(presentation.verdictText, "Keep")
        XCTAssertEqual(presentation.verdictTone, .positive)
        // Every verdict input is visible on the card now — face kinds
        // included, in canonical order after the whole-photo kinds.
        XCTAssertEqual(presentation.glyphEntries, [
            CullReadsCardPresentation.GlyphEntry(
                kind: .focus, word: "Focus", score: 0.96, accessibilityText: "Focus 96%"),
            CullReadsCardPresentation.GlyphEntry(
                kind: .aesthetics, word: "Looks", score: 0.9, accessibilityText: "Looks 90%"),
            CullReadsCardPresentation.GlyphEntry(
                kind: .eyesOpen, word: "Eyes", score: 1.0, accessibilityText: "Eyes 100%")
        ])
        XCTAssertEqual(presentation.wholePhotoGlyphEntries.map(\.kind), [.focus, .aesthetics])
        XCTAssertEqual(presentation.faceGlyphEntries.map(\.kind), [.eyesOpen])
        XCTAssertEqual(presentation.verdictHelp, "Composed read 0.96 from 3 signals")
        XCTAssertNil(presentation.emptyState)
        XCTAssertNil(presentation.earlyReadCaveat)
    }

    // Order is fixed canonical order, independent of score: the four
    // whole-photo kinds, then the three face kinds.
    func testGlyphOrderIsCanonicalAndValueIndependent() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .eyeSharpness, value: .score(0.99), confidence: 1.0),
            signal(kind: .framing, value: .score(0.95), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.9), confidence: 1.0),
            signal(kind: .faceQuality, value: .score(0.97), confidence: 1.0),
            signal(kind: .motionBlur, value: .score(0.2), confidence: 1.0),
            signal(kind: .eyesOpen, value: .score(1.0), confidence: 1.0),
            signal(kind: .focus, value: .score(0.1), confidence: 1.0)
        ])

        XCTAssertEqual(
            presentation.glyphEntries.map(\.kind),
            [.focus, .motionBlur, .framing, .aesthetics, .eyesOpen, .faceQuality, .eyeSharpness]
        )
        XCTAssertEqual(
            presentation.glyphEntries.map(\.kind),
            CullReadsCardPresentation.canonicalSignalOrder
        )
    }

    // Kinds with no signal are simply absent — never a fake zero glyph.
    // smile is not rankable and never appears at all.
    func testMissingAndUnrankableKindsAreOmittedNotFakedAsZero() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.8), confidence: 1.0),
            signal(kind: .smile, value: .score(1.0), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.4), confidence: 1.0)
        ])

        XCTAssertEqual(presentation.glyphEntries.map(\.kind), [.focus, .aesthetics])
        XCTAssertTrue(presentation.faceGlyphEntries.isEmpty)
    }

    // motionBlur components are defect-inverted at the core layer; the
    // glyph shows that component score as-is (0.2 raw blur -> 0.8 shown).
    func testMotionGlyphUsesTheAlreadyInvertedComponentScore() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .motionBlur, value: .score(0.2), confidence: 1.0),
            signal(kind: .focus, value: .score(0.5), confidence: 1.0)
        ])

        let motion = presentation.glyphEntries.first { $0.kind == .motionBlur }
        XCTAssertEqual(motion?.score, 0.8)
        XCTAssertEqual(motion?.word, "Motion")
        XCTAssertEqual(motion?.accessibilityText, "Motion 80%")
    }

    // Exactly one scored kind — of ANY rankable kind, face included — is a
    // PARTIAL read: the one glyph renders with the early-read caveat and no
    // verdict. This retires the 2026-07-28 face-only fallback: face kinds
    // are first-class glyphs now, so there is nothing dishonest to fall
    // back from.
    func testExactlyOneScoredKindOfAnyKindIsAPartialRead() {
        for (kind, word) in [(EvaluationKind.focus, "Focus"), (.faceQuality, "Face")] {
            let presentation = CullReadsCardPresentation.presentation(for: [
                signal(kind: kind, value: .score(0.9), confidence: 1.0)
            ])

            XCTAssertNil(presentation.emptyState, "\(kind)")
            XCTAssertNil(presentation.verdictText, "\(kind)")
            XCTAssertNil(presentation.verdictHelp, "\(kind)")
            XCTAssertEqual(presentation.verdictTone, .waiting, "\(kind)")
            XCTAssertEqual(presentation.glyphEntries.map(\.word), [word], "\(kind)")
            XCTAssertEqual(presentation.earlyReadCaveat, "early read — 1 signal", "\(kind)")
        }
    }

    // A full read between the Toss and Keep thresholds is pure silence in
    // the verdict slot: glyphs render, verdictText/verdictHelp stay nil.
    func testNoCallFullReadRendersGlyphsWithPureSilence() {
        // (0.6 * 100 + 0.6 * 50) / 150 = 0.6 — between 0.5 and 0.7.
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.6), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.6), confidence: 1.0)
        ])

        XCTAssertNil(presentation.verdictText)
        XCTAssertNil(presentation.verdictHelp)
        XCTAssertEqual(presentation.verdictTone, .waiting)
        XCTAssertEqual(presentation.glyphEntries.count, 2)
        XCTAssertNil(presentation.emptyState)
        XCTAssertNil(presentation.earlyReadCaveat)
    }

    // Zero scored kinds is the only "No read yet" state now.
    func testZeroSignalsGatesTheWholeCard() {
        let presentation = CullReadsCardPresentation.presentation(for: [])

        XCTAssertEqual(presentation.emptyState, "No read yet")
        XCTAssertNil(presentation.verdictText)
        XCTAssertNil(presentation.verdictHelp)
        XCTAssertEqual(presentation.verdictTone, .waiting)
        XCTAssertEqual(presentation.glyphEntries, [])
        XCTAssertNil(presentation.earlyReadCaveat)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter CullReadsCardPresentationTests 2>&1 | tail -20`
Expected: compile errors — `GlyphEntry`, `glyphEntries`, `verdictHelp`, `word(for:)` do not exist. Save this output; it is the red-proof for the API surface. (A semantic red for the retired fallback comes free: the old `testSingleFaceSpecificSignalFallsBackToNoReadYet...` asserted the opposite of the new partial test — note its deletion in the report.)

- [ ] **Step 3: Rewrite the presentation**

Replace the whole of `CullReadsCardPresentation.swift` with:

```swift
import TeststripCore

/// The right-panel reads card model: a fast triage cue — the frame's
/// Keep/Toss verdict plus one micro-glyph (donut + word) per scored rankable
/// kind, face kinds included, so every verdict input is visible in one
/// place. Reuses `CullingAssistPresentation`'s verdict computation and
/// `CullingStackRecommendation`'s per-kind component scoring rather than
/// re-deriving either; the close-ups rail keeps per-face detail (these
/// entries are the photo-level best component per kind, exactly what the
/// composite consumes, so the line and the verdict can never disagree).
///
/// Three states, gated on scored rankable kind count:
/// - Zero kinds: `emptyState` only ("No read yet").
/// - Exactly one kind (any kind, face included): a PARTIAL read — the one
///   glyph plus `earlyReadCaveat` in place of the verdict; no verdict is
///   ever computed off one signal.
/// - Two or more kinds: the full glyph line plus the verdict word — or pure
///   silence in the verdict slot when the composed read lands between the
///   Toss and Keep thresholds (a read that can't commit says nothing).
struct CullReadsCardPresentation: Equatable {
    struct GlyphEntry: Equatable {
        var kind: EvaluationKind
        var word: String
        var score: Double
        var accessibilityText: String
    }

    /// Fixed display order, identical for every photo regardless of score:
    /// the four whole-photo kinds, then the three face kinds.
    static let canonicalSignalOrder: [EvaluationKind] = [
        .focus, .motionBlur, .framing, .aesthetics,
        .eyesOpen, .faceQuality, .eyeSharpness
    ]

    /// The measure's inline word. "Looks" stands in for aesthetics so the
    /// line stays one line; nil for unrankable kinds (e.g. smile).
    static func word(for kind: EvaluationKind) -> String? {
        switch kind {
        case .focus: return "Focus"
        case .motionBlur: return "Motion"
        case .framing: return "Framing"
        case .aesthetics: return "Looks"
        case .eyesOpen: return "Eyes"
        case .faceQuality: return "Face"
        case .eyeSharpness: return "Eye sharp"
        default: return nil
        }
    }

    var verdictText: String?
    var verdictTone: CullingAssistPresentation.Tone
    /// Non-nil exactly when `verdictText` is — the one place the composition
    /// is stated, as hover/AX help, never on screen.
    var verdictHelp: String?
    var glyphEntries: [GlyphEntry]
    var emptyState: String?
    /// Non-nil only for a PARTIAL (exactly one scored kind) read.
    var earlyReadCaveat: String?

    /// The line wraps by domain, not by measurement: whole-photo glyphs on
    /// the first line, face glyphs on the second when present.
    var wholePhotoGlyphEntries: [GlyphEntry] {
        glyphEntries.filter { !Self.faceKinds.contains($0.kind) }
    }

    var faceGlyphEntries: [GlyphEntry] {
        glyphEntries.filter { Self.faceKinds.contains($0.kind) }
    }

    private static let faceKinds: Set<EvaluationKind> = [.eyesOpen, .faceQuality, .eyeSharpness]

    static func presentation(for signals: [EvaluationSignal]) -> CullReadsCardPresentation {
        guard let read = CullingStackRecommendation.normalizedQualityRead(for: signals) else {
            return CullReadsCardPresentation(
                verdictText: nil,
                verdictTone: .waiting,
                verdictHelp: nil,
                glyphEntries: [],
                emptyState: "No read yet",
                earlyReadCaveat: nil
            )
        }
        let entries = glyphEntries(for: signals)
        guard read.kindCount >= 2 else {
            // PARTIAL read: one scored kind of any rankable kind. Never a
            // verdict off one signal — CullingAssistPresentation.verdict is
            // not consulted here.
            return CullReadsCardPresentation(
                verdictText: nil,
                verdictTone: .waiting,
                verdictHelp: nil,
                glyphEntries: entries,
                emptyState: nil,
                earlyReadCaveat: "early read — 1 signal"
            )
        }
        let verdict = CullingAssistPresentation.verdict(for: signals)
        return CullReadsCardPresentation(
            verdictText: verdict?.text,
            verdictTone: verdict?.tone ?? .waiting,
            verdictHelp: verdict.map { _ in
                String(format: "Composed read %.2f from %d signals", read.score, read.kindCount)
            },
            glyphEntries: entries,
            emptyState: nil,
            earlyReadCaveat: nil
        )
    }

    // Canonical order, not score order. Kinds with no signal are simply
    // absent (never a fake zero glyph). Component scores arrive already
    // defect-inverted from the core scorer — no second inversion here.
    private static func glyphEntries(for signals: [EvaluationSignal]) -> [GlyphEntry] {
        let bestComponentByKind = CullingStackRecommendation.bestComponentByKind(for: signals)
        return canonicalSignalOrder.compactMap { kind in
            guard let component = bestComponentByKind[kind], let word = word(for: kind) else {
                return nil
            }
            return GlyphEntry(
                kind: kind,
                word: word,
                score: component.score,
                accessibilityText: "\(word) \(EvaluationSignalPresentation.percentage(component.score))"
            )
        }
    }
}
```

Note: if `EvaluationSignalPresentation.percentage` produces a different shape than `NN%` (check its implementation before writing the tests' expected strings — e.g. rounding of 0.96), adjust the expected `accessibilityText` values in Step 1 to the helper's real output rather than changing the helper.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter CullReadsCardPresentationTests 2>&1 | tail -5`
Expected: all 7 tests pass. NOTE: `LibraryGridView.swift` still references `signalRows` — the app target will not compile until Task 2. Run the focused test target only; if `swift test --filter` forces a full app build that fails on `readsCard`, do Task 2's minimal view swap in the same commit and say so in the report (the review treats Tasks 1+2 as one gate in that case).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/CullReadsCardPresentation.swift Tests/TeststripAppTests/CullReadsCardPresentationTests.swift
git commit -m "feat: reads card presentation emits glyph entries for all rankable kinds"
```

---

### Task 2: SignalGlyphView + card view swap

**Files:**
- Create: `Sources/TeststripApp/SignalGlyphView.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift:4180-4223` (the `readsCard` function and its doc comment; container AX at 4098-4103 is unchanged — verify, don't edit)

**Interfaces:**
- Consumes: `CullReadsCardPresentation.GlyphEntry`, `.wholePhotoGlyphEntries`, `.faceGlyphEntries`, `.verdictHelp` (Task 1).
- Produces: `struct SignalGlyphView: View { let entry: CullReadsCardPresentation.GlyphEntry }` — SP-B's per-face report cards reuse this exact view.

- [ ] **Step 1: Create the component**

`Sources/TeststripApp/SignalGlyphView.swift`:

```swift
import SwiftUI

/// One micro signal glyph: an 11pt donut ring (arc sweep = score) with the
/// measure's word beside it. The reads card's glyph line is built from
/// these, and SP-B's per-face report cards reuse the same component —
/// change it here, both surfaces follow.
struct SignalGlyphView: View {
    let entry: CullReadsCardPresentation.GlyphEntry

    private static let donutSize: CGFloat = 11
    private static let ringWidth: CGFloat = 2.2
    private static let fillColor = Color(red: 0.35, green: 0.78, blue: 0.78)

    var body: some View {
        HStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.18), lineWidth: Self.ringWidth)
                Circle()
                    .trim(from: 0, to: max(0, min(1, entry.score)))
                    .stroke(Self.fillColor, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: Self.donutSize, height: Self.donutSize)
            Text(entry.word)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(entry.accessibilityText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityText)
    }
}
```

- [ ] **Step 2: Swap the card body**

In `LibraryGridView.swift`, replace the `readsCard` doc comment and function (currently lines 4180-4223) with:

```swift
    // The frame's whole-frame read as a fast triage cue: the verdict word
    // (or pure silence when a full read lands between the thresholds — a
    // read that can't commit says nothing), over one micro-glyph per scored
    // rankable kind. Face kinds render here too — every verdict input
    // visible in one place — as a second line, while the close-ups rail
    // keeps per-face detail. With zero scored kinds only the honest "No
    // read yet" empty state renders; with exactly one, the lone glyph plus
    // a quiet early-read caveat. The card's home in the panel never
    // disappears. Composition detail lives in hover/AX help, never on
    // screen.
    private func readsCard(_ presentation: CullReadsCardPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("READS")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            if let emptyState = presentation.emptyState {
                Text(emptyState)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if let verdictText = presentation.verdictText {
                    Text(verdictText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(readsToneColor(presentation.verdictTone))
                        .lineLimit(1)
                        .help(presentation.verdictHelp ?? "")
                } else if let earlyReadCaveat = presentation.earlyReadCaveat {
                    Text(earlyReadCaveat)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                signalGlyphLine(presentation.wholePhotoGlyphEntries)
                signalGlyphLine(presentation.faceGlyphEntries)
            }
        }
        .liveMockupPlaceholder(.cullingAssistVerdict)
    }

    // One line of glyph pairs; renders nothing at all for an empty domain
    // (no gaps, no fake zeros).
    @ViewBuilder
    private func signalGlyphLine(_ entries: [CullReadsCardPresentation.GlyphEntry]) -> some View {
        if !entries.isEmpty {
            HStack(spacing: 8) {
                ForEach(entries, id: \.kind.rawValue) { entry in
                    SignalGlyphView(entry: entry)
                }
            }
        }
    }
```

Keep `readsToneColor` (lines 4225-4234) unchanged. Verify (do not edit) that the panel container's `accessibilityValue` chain at ~4098-4103 still reads `emptyState ?? verdictText ?? earlyReadCaveat ?? ""`.

Width note: the card's usable width inside the 340pt panel is ~176pt (rail 132 + spacing/padding). Four pairs at 9pt words should fit, but if the whole-photo line visibly truncates or clips in Task 4's live run, the sanctioned fallback is splitting that line 2+2 (`Array(entries.prefix(2))` / `.dropFirst(2)` through the same `signalGlyphLine`) — do NOT shrink the font below 9 or drop words to make one line fit.

- [ ] **Step 3: Build and run the full suite**

Run: `swift build 2>&1 | tail -3` — expect success, no warnings from the new file.
Run: `swift test 2>&1 | tail -3` — expect 0 failures (suite count ≈ 2257 + Task 1 delta; report exact numbers).

- [ ] **Step 4: Commit**

```bash
git add Sources/TeststripApp/SignalGlyphView.swift Sources/TeststripApp/LibraryGridView.swift
git commit -m "feat: reads card renders the signal glyph line via reusable SignalGlyphView"
```

---

### Task 3: Scenario-card reconciliation (cull-024, cull-012)

**Files:**
- Modify: `test/scenarios/cull-024-honest-states.md` (third reconciliation: reads-panel expectations)
- Modify: `test/scenarios/cull-012-closeups-panel.md` (reads-panel probes only; close-ups rail sections untouched)

**Interfaces:**
- Consumes: the Task 1/2 behavior (glyph entries, retired face-only fallback, unchanged container AX chain).

- [ ] **Step 1: Reconcile cull-024**

Read the whole card first. Update every passage that asserts the old contract, at minimum: (a) per-kind row/percentage-text probes → the panel container AX value is UNCHANGED (`No read yet` / verdict word / caveat), but inner `AXStaticText` matches for `Focus 82%`-style row text are gone — per-glyph AX labels are now `<Word> <NN>%` on `SignalGlyphView` elements (e.g. probe `ax find --contains "Focus "` against the glyph's accessibilityLabel); (b) the face-specific-only branch: single face-only signal is now a PARTIAL read (one glyph + `early read — 1 signal`), NOT `No read yet` — rewrite that step's Expected and its falsification condition; (c) the three-floors Sharp-edges narrative: face kinds now render on the card. Keep every assertion falsifiable; verify every citation you touch by reading the cited lines at final HEAD.

- [ ] **Step 2: Reconcile cull-012's reads probes**

Grep the card for `No read yet`, `early read`, `Reads`, and per-kind percentage probes; update to the glyph-line contract (the face-only fallback passage from the 2026-07-28 runs is the load-bearing change: that scenario now yields a partial read on the card). Do not touch close-ups rail steps.

- [ ] **Step 3: Commit**

```bash
git add test/scenarios/cull-024-honest-states.md test/scenarios/cull-012-closeups-panel.md
git commit -m "docs: reconcile cull-024 and cull-012 reads probes with the glyph line"
```

---

### Task 4: Live VM verification (cull-024 + cull-012 reads legs)

**Files:**
- Modify: `test/scenarios/cull-024-honest-states.md`, `test/scenarios/cull-012-closeups-panel.md` (Run status sections only)

**Interfaces:**
- Consumes: the built branch; `script/vm_scenario_run.sh` (setup/sync/launch/ax/sql verbs; read `test/scenarios/README.md` first — idle-wedge, locked-console, AX realities).

- [ ] **Step 1: Boot and sync**

```bash
script/vm_scenario_run.sh setup
script/vm_scenario_run.sh sync burst faces
```

Run sync FROM THIS BRANCH's checkout so the VM gets this build. Known environment traps: (a) if the checkout is a worktree without `sample-data/photos/faces`, the final photos rsync fails with exit 23 — benign if the VM already has the photos from a prior sync, but verify the app-bundle rsync line appeared; (b) seed templates under `$TMPDIR/teststrip-vm-seeds/` may be mutated from the 2026-07-28 runs — after `launch burst`, run `script/vm_scenario_run.sh sql burst "SELECT count(*) FROM autopilot_proposals;"`; if non-zero, the template carries cull-025's patch — stop and have the template regenerated (deleting `$TMPDIR/teststrip-vm-seeds/burst/Teststrip` requires Jesse's rm) before trusting reads-state assertions.

- [ ] **Step 2: Run cull-024 end to end**

Execute the reconciled card's steps via `vm_scenario_run.sh ax ...`/`sql burst ...`, capturing per-step PASS/FAIL with observations. The three states to hit live: no-read (pre-evaluation), full read with verdict, and no-call silence (the card names the fixture assets for each). Glyph probes: `ax find` against `<Word> <NN>%` accessibility labels.

- [ ] **Step 3: Run cull-012's reads legs**

`launch faces`; trigger the face pass per the card; verify the face-only-signal window now shows a partial read (one glyph + caveat) instead of `No read yet`, and that face glyphs join the line once whole-photo evaluation lands. Keep the app warm during worker waits (`ax wait-vended` every poll).

- [ ] **Step 4: Update Run status + commit**

Append the run (date, app commit, per-step verdicts) to both cards' Run status sections.

```bash
git add test/scenarios/cull-024-honest-states.md test/scenarios/cull-012-closeups-panel.md
git commit -m "docs: cull-024 and cull-012 live runs against the glyph line"
```

If either card FAILs on a real app defect: stop, capture evidence (screenshot + SQL), and report — do not patch code inside this task.
