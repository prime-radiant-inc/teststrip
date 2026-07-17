# Teststrip Culling Workflow Gap Audit

*Status superseded as of 2026-07-16 — all 8 "Blocks the arc" gaps below (#1–#8) are now closed. See `docs/product/narrative-select-reference.md` and `docs/design-spikes/2026-07-16-culling-redesign/teststrip-signals-inventory.md` for current state.*

> **For agentic workers:** This is an AUDIT REPORT, not an implementation plan — there are no tasks to execute. It exists to seed the next implementation plan. When that plan is written, use superpowers:writing-plans against the evidence below; every finding here is verified against code, not against prior plan documents.

**Goal of this audit:** Verify, end-to-end in code, whether the app delivers the full narrative-select culling arc the design concept promises — import → auto-grouped stacks → best-of-set decisions → N-up survey confirm → metric tie-break → picks as the story's selects, with keyboard-fast single-frame rapid cull throughout — and produce a ranked, evidence-cited gap list.

**Design reference:** `design-concept/Teststrip.dc.html` — turn 2a "Rapid cull" (lines 720–811), 2b "Survey & compare" (812–861), 3a "Stack cull" (527–632), 3b "Focus compare" (633–713).

**Evidence anchors:** All `AppModel.swift` line numbers are as of commit `5648488` (HEAD at audit time; the working tree copy was being concurrently modified by an unrelated background-work-publication change, shifting lines by ~+46 in the 7000s). `LibraryGridView.swift`, `CullingKeyCaptureView.swift`, `main.swift`, and all TeststripCore files are identical between HEAD and the working tree, so their line numbers hold in both. Re-locate by symbol name if lines have shifted.

**Product rule reminder (hard):** Machine labels stay PROVISIONAL until user acceptance — nothing auto-writes catalog metadata/XMP. Every gap fix below that involves "assist pre-picks" must present the recommendation without writing `metadata.flag`; only an explicit user action (key press, button) may write. Note that design 2a's "Assist auto-picked — press X to override" copy, taken literally, would violate this rule; see Open Questions.

---

## Verdict summary

| Design turn | Verdict | One-line reason |
|---|---|---|
| 2a Rapid cull | **PARTIAL** (manual loop BUILT; assist layer thin) | Keyboard loop, auto-advance, progress, filmstrip, counts all real; but no per-frame PICK/REJECT verdict with confidence, rationale is hover-only, and signals are empty in the default arc because nothing auto-evaluates after import |
| 2b Survey & compare | **PARTIAL** | N-up grid, suggests-pill, keep-best/keep-all/choose-manually all real; but no per-frame flaw badges, no visible pre-pick ring, and no next-group advance after confirming — the survey loop dead-ends after one group |
| 3a Stack cull | **PARTIAL** | Auto-grouping, persisted per-import stack sets, whole-set keep/cut decisions, auto-advance to next stack, Picks output set all real; but Enter accepts the *selected* (default: first) frame, not the recommended best; the recommended frame is computed and never rendered; no stack list rail; no completion handoff |
| 3b Focus compare | **PARTIAL, weakest** | Per-frame metric lanes with real persisted signals exist; but no contenders-only mode, no rank badges, no comparative rationale, no eye-state signal at all (no provider emits one), no "Keep #1 & #2" in compare |

The connective tissue (import completion card → culling entry points → picks output set → sidebar browse) is **BUILT** with two breaks: no automatic evaluation pass after import, and no end-of-session handoff from culling to the picks set.

---

## 1. The arc, walked end-to-end

### 1.1 Import → culling entry: BUILT

The import completion card offers the full fan-out (`ImportCompletionPresentation.presentation`, LibraryGridView.swift:6415–6500):

- **Start culling** (primary, orange) → `beginCullingFromLatestImportCompletion()` (AppModel.swift:2805) → opens the import work-session scope, starts a named session ("<import> Cull" via `ImportCompletionSummary.cullingSessionName`, AppModel.swift:792), switches to `.loupe` (`beginCullingSession`, AppModel.swift:3330–3371).
- **Cull stacks** (enabled iff `summary.stackCount > 0`, LibraryGridView.swift:6483) → `beginStackCullingFromLatestImportCompletion()` (AppModel.swift:2811–2862): rebuilds time-adjacent/visual-similarity stacks from the import output (`latestImportStacks`, AppModel.swift:7421), persists one `work-stack-<session>-N` manual set per stack (`saveCullingStackInputSets`, AppModel.swift:7432–7454), applies the first stack set, selects its first frame, `.loupe`. Falls back to a plain culling session with an honest status message when no stacks exist (AppModel.swift:2822–2827).
- **Review imported frames** → `reviewLatestImportInCompare()` (AppModel.swift:2864) → `.compare` over the import scope.
- **Open imported set / Evaluate import / Review flagged / faces / keywords** — all wired (LibraryGridView.swift:1107–1128).

Dispatch is real: `performImportCompletionAction` (LibraryGridView.swift:1107) calls the model methods and `focusCullingSurface()` re-arms key capture (LibraryGridView.swift:2533–2535).

### 1.2 The rapid-cull loop (2a): BUILT for manual, thin for assist

- Key capture: `CullingKeyCaptureNSView` installs a local `keyDown` monitor that swallows culling keys whenever the app window is key and the first responder is not a text editor (CullingKeyCaptureView.swift:74–96, 59–72), so the loop works from grid, loupe, and compare without clicking first. Key map: arrows, space, return, P/X/U, 0–5, 6/7/8/9/V/`-` (CullingKeyCaptureView.swift:100–127 → `CullingShortcut.init?(key:)`, AppModel.swift:80–113).
- Decisions auto-advance: `applyCullingCommandAndAdvance` applies the flag/rating/label then `selectNextAssetForCulling()` (AppModel.swift:3711–3721), which pages through the loaded scope with `loadMoreAssets()` at the boundary (AppModel.swift:3754–3773, 6071).
- Decisions write real catalog metadata through the undoable path (`setFlagForSelectedAsset`, AppModel.swift:4021; `applyCompareFlags`, AppModel.swift:3466–3500 maintains `metadataUndoStack`), and session progress + Picks output refresh on every flag (`updateActiveCullingSessionProgressAfterFlagChange`, AppModel.swift:7142–7179).
- Header parity with the mockup: "Culling" label, `Frame N of M`, progress bar, pick/reject count pills, last-decision feedback pill, TESTSTRIP READS pill (LibraryGridView.swift:2574–2605). Missing vs mockup: the session *name* ("Culling · Patagonia_2024") is not shown.
- Filmstrip: 12 visible thumbs anchored on selection, flag/rating overlays, click-to-select, position text (LibraryGridView.swift:2705–2735, presentation 3712–3754). Missing vs mockup: rejected frames are not dimmed, no pick/reject color bar on tiles, no recommended-ring.
- Command rail: on-screen P/X/U buttons, 1–5 star buttons + 0, five label dots + clear (LibraryGridView.swift:2884–2954). Missing vs mockup: no prev/next chevrons on the stage, no "← → navigate · Space advances" legend.
- The Culling macOS menu mirrors every shortcut in four sections (main.swift:89–115, `CullingCommandMenuPresentation`, AppModel.swift:151–182) — this is complete and matches the key capture map exactly (verified pair-by-pair).

**Where 2a falls short of its mockup:** the verdict layer. The mockup's centerpiece is `TESTSTRIP | PICK 94% | sharp · strong side light · eyes open · best of 6-frame burst` plus "Assist auto-picked — press X to override". What exists is `cullingAssistPill` (LibraryGridView.swift:2633–2662) rendering `CullingAssistPresentation` (LibraryGridView.swift:6225–6399): title = stack guidance when a ranked stack is active, otherwise the single top signal (rank order puts aesthetics first — LibraryGridView.swift:6329–6356 — so with only local-image-metrics signals the pill usually reads "Aesthetics NN%"). There is **no pick/reject verdict, no confidence, no burst-context sentence**, and the multi-signal rationale (`detail`) is attached only as a hover tooltip (`.help(presentation.detail)`, LibraryGridView.swift:2653) in a fixed 148pt pill — invisible during keyboard-speed culling.

### 1.3 Stack cull (3a): decisions work, guidance doesn't reach the keyboard

- Grouping: `AssetStackBuilder` stacks by same-folder capture gap ≤ 2s or visual-similarity vector distance ≤ 0.05, with per-stack rationale strings ("Same folder, captured within 2s" / "Visual similarity distance 0.041 <= 0.050") (AssetStackBuilder.swift:28–130). Visual-similarity vectors come from persisted `visualSimilarity` signals (Apple Vision feature prints; AppleVisionEvaluationProvider.swift:155).
- The loupe stack rail (LibraryGridView.swift:2737–2806) shows "Stack N of M", "Frame N of M", the rationale, numbered frame chips, and three actions from `CullingStackRailPresentation` (LibraryGridView.swift:3756–3919): "Keep frame N · cut M" / "Keep recommended N" or "Keep top 2" / "Keep all N" — mockup-parity action set.
- Whole-set decision: `applyCullingStackDecision` flags every stack frame pick-or-reject in one pass, refreshes session progress, then auto-advances to the next persisted stack (AppModel.swift:3650–3679). Stack navigation: ↑/↓ walk `session.inputSetIDs` for persisted sessions (`persistedCullingStackSetID`, AppModel.swift:7066–7085) with a loaded-scope fallback (`selectCullingStack`, AppModel.swift:3949).
- Progress is honest: a stack only counts when *every* frame is flagged (`decidedPersistedStackUnitCount`, AppModel.swift:7322–7338); the session detail shows "Reviewed X of Y · picks/rejects" (`cullingProgressDetail`, AppModel.swift:8052).

**Three verified breaks vs the 3a mockup:**

1. **Enter keeps the wrong frame.** Mockup legend: "↵ accept best". Implementation: `acceptSelectedStackSelectionForCulling` → `keepSelectedStackFrameAndRejectAlternates` keeps the **currently selected** frame (AppModel.swift:3901–3908, 3630), and entering a stack always selects its **first** frame (`selectPersistedCullingStack`: `selectAssetID(selectedExplicitAssetIDs?.first)`, AppModel.swift:3939–3947). So the keyboard-only "one decision per moment" flow — Enter, Enter, Enter — keeps frame 1 of every stack regardless of what the ranking recommends. The recommendation is only reachable by mouse ("Keep recommended N" button) or by manually arrowing to the recommended frame — which brings us to:
2. **The recommended frame is computed but never rendered.** `CullingStackRailPresentation.Item.isRecommended` is populated (LibraryGridView.swift:3842) and consumed nowhere — the chip rendering uses only `label` and `isSelected` (LibraryGridView.swift:2781–2798). No ✦ BEST OF SET badge, no hero treatment, no way to *see* which frame the ranking picked except reading the "Keep recommended 3" button title.
3. **No stack rail sidebar, no completion handoff.** The mockup's left rail (per-stack thumbs, frame counts, done checkmarks, active dot) does not exist; ↑/↓ navigation is blind. And after the last stack is decided, `selectPersistedCullingStack(.next)` returns false and `context.nextAssetID` is nil for persisted stacks (AppModel.swift:3674–3679, 3666), so **nothing happens** — the user sits on a fully-flagged stack with no "31 keepers · 112 cut — view picks" moment. The session silently flips to `.completed` in the Activity panel (ActivityView.swift:125–133) and the Picks set appears in the sidebar, but nothing in the culling surface says so.

Also verified: stack-cull sessions contain **only** frames in stacks of ≥ 2 (`latestImportStacks` filters `assetIDs.count > 1`, AppModel.swift:7421–7430); singles from the import are never part of the session and nothing prompts the user to rapid-cull the remainder afterward.

### 1.4 Survey confirm (2b): one good group, then a dead end

- `CompareView` renders up to 8 frames in a ≤4-column grid, primary first (LibraryGridView.swift:4021–4128; `CompareSurveyPresentation`, 3326–3421). Group source priority: persisted work stack → sticky `compareAssetIDs` → on-the-fly candidate stack around the selection → selected neighborhood (`compareAssets`, AppModel.swift:3378–3394).
- Header carries the mockup's suggests-pill: "Suggests: keep 1 · reject N" when the top-ranked frame is primary, "Top signal: frame N" otherwise (LibraryGridView.swift:3392–3407, rendered 4094–4103).
- Footer actions match the mockup trio: "Keep primary/top signal · reject N" (borderedProminent), "Keep all", "Choose manually" (LibraryGridView.swift:3444–3474, 4293–4317), backed by `keepCompareAssetAndRejectAlternates` / `keepAllCompareAssets` (AppModel.swift:3423, 3447) and `beginManualCullingFromCompareSet` (AppModel.swift:2882–2927) which hands the exact compare set to stack-aware loupe culling — a genuinely good handoff.
- Decision badges (PRIMARY / PICKED / REJECTED / N STAR / label) render on tiles (LibraryGridView.swift:3476–3497, 4154–4169).

**Breaks vs the 2b mockup:**

1. **No next-group advance.** After "Keep best · reject 7", the compare set stays put — `compareAssetIDs` only recomputes when the selection leaves the set or the view is re-entered (AppModel.swift:3568–3587). The mockup's implied loop (confirm group → next burst) requires leaving compare, moving the selection, and coming back. For persisted stack sessions, ↓ (next stack) works but **switches the view to loupe** (`selectPersistedCullingStack` sets `selectedView = .loupe`, AppModel.swift:3944), kicking the user out of survey mode.
2. **No per-frame flaw flags.** The mockup badges frames "BLINK", "SOFT". Tiles show decision badges only; the flaw information lives in the metric lanes as raw percentages with caution tones (LibraryGridView.swift:3639–3653) — nothing names the defect, and no ring marks the pre-picked frame (`recommendedAssetID` is used for header text and action title only).
3. **No group rationale sentence** ("picked the sharpest, eyes-open frame · flagged 2 soft & 1 blink"). Footer shows "Primary · <decision state>" (LibraryGridView.swift:4265).

### 1.5 Metric tie-break (3b): lanes exist, the tie-break story doesn't

- The metric lane is real and consumes persisted signals: focus, motion blur, exposure, framing, aesthetics, face quality, highest-confidence per kind, with provider provenance in the detail line (`CompareFocusMetricPresentation`, LibraryGridView.swift:3581–3653, rendered per-tile at 4207–4237). "No read yet / Evaluate" placeholder when signals are absent (3595–3602).
- "Evaluate Compare" runs both providers over cached previews for the visible set (LibraryGridView.swift:4084–4093; `requestCompareAssetEvaluations`, AppModel.swift:5462; gated on cached previews at AppModel.swift:1561).

**Missing vs the 3b mockup:** contenders-only layout ("comparing the 3 sharpest of 9" — there is no way to narrow to the top-ranked subset); rank badges (#1 BEST/#2/#3); winner ring; comparative rationale ("Frame 3 edges it — 8% sharper than #2 with eyes open" — all current copy is absolute per-frame, never comparative); "Keep #1 & #2" (the top-2 action exists only in the loupe stack rail, LibraryGridView.swift:3893–3907); eye state (see §2); sharpness bars (values render as numbers); exposure as EV delta (rendered as a 0–100% luminance score — LocalImageMetricsEvaluationProvider.swift:12–21).

### 1.6 Picks as the story's selects: BUILT, minus the handoff

- Every flag change refreshes the session's output set: `refreshCullingSessionOutputSet` upserts a snapshot `AssetSet` named "<session title> Picks" (`work-output-<id>-picks`) containing exactly the picked input frames, deletes it if picks drop to zero, and rebuilds the sidebar (AppModel.swift:7225–7253). This satisfies "picks output set" structurally — the selects exist as a browsable, exportable set from the first pick onward.
- Browsing works three ways: sidebar saved-set row ("<title> Picks"); the Picks review queue (`ReviewQueue.picks`, AppModel.swift:199–244); reopening the work session from Recent work (`applyWorkSession`, AppModel.swift:2779–2793 — lands in `.loupe` over the union of the session's input *and* output sets, CatalogRepository.swift:1510–1529).
- **The missing link is the moment of completion:** nothing in the culling surface ever points at the Picks set. No completion banner, no "View picks" action, no status message on the completion transition (verified: the only `statusMessage` writes in the culling path are at session *start*, AppModel.swift:2825/2860/2925/3369). The user must know to look in the sidebar.

---

## 2. Signal surfacing matrix — where existing signals actually appear

Providers emit: `local-image-metrics` → exposure, colorPalette, focus, motionBlur, framing, aesthetics (LocalImageMetricsEvaluationProvider.swift:14–62); `apple-vision` → faceCount, faceQuality, ocrText, object, visualSimilarity (AppleVisionEvaluationProvider.swift:83–155). `EvaluationKind` has **no eye-state case** (EvaluationSignal.swift:3–16) — every "eyes open"/"blink" element in mockups 2a/2b/3a/3b is unimplementable until a provider emits one.

| Surface | focus | motionBlur | exposure | aesthetics | framing | faceQuality | Notes |
|---|---|---|---|---|---|---|---|
| Loupe verdict pill (2a) | tooltip/title | tooltip | tooltip | **title** (rank 0) | tooltip | tooltip | Only ONE signal visible as title; rest hover-only (LibraryGridView.swift:2653, 6284–6309) |
| Stack rail + ranking (3a) | ✔ weight 100 | ✔ weight 60 inv. | ✘ ignored | ✔ 50 | ✔ 45 | ✔ 80 | Ranking real (`CullingStackRecommendation.weightedQualityScore`, LibraryGridView.swift:4000–4018) but result rendered only as button title — no frame marker |
| Survey lanes (2b/3b) | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | Full lane per tile (LibraryGridView.swift:3582–3589) — the best signal surface in the app |
| Compare suggests-pill (2b) | ✔ via ranking | ✔ | ✘ | ✔ | ✔ | ✔ | Same ranking as stack rail (LibraryGridView.swift:3373–3384) |
| Grid cells | ✘ | ✘ | ✘ | ✘ | ✘ | ✘ | No verdict/signal badges in grid (`AssetGridMetadataBadgePresentation` carries flag/rating/label/keyword-count only, LibraryGridView.swift:5773–5806) |
| Inspector | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | "TESTSTRIP READS" grouped rows (InspectorView.swift:54, 119–168) |

**The systemic problem is upstream of the surfaces:** nothing evaluates automatically. Every evaluation is user-triggered — toolbar Evaluate/Visible/Scope buttons (LibraryGridView.swift:2509–2531), import card "Evaluate import" (2425–2432), compare "Evaluate Compare" (4084), Copilot (CopilotView.swift:251). The import pipeline schedules zero evaluation work (grep of `LibraryImportService.swift` and `IngestService.swift` for evaluate/Evaluation: no hits). So in the promised arc — import finishes, click "Start culling" — **every frame shows "No read yet", stack ranking has nothing to rank (no Keep recommended/Keep top 2 actions render), survey lanes show placeholders, and the visual-similarity stacking criterion is inert** (only 2s time-adjacency groups). The entire assist layer of all four mockups is dark by default.

---

## 3. Keyboard completeness vs mockup 2a legend

| Mockup 2a legend | Implemented | Evidence |
|---|---|---|
| P Pick | ✔ pick + auto-advance | AppModel.swift:107, 3711 |
| X Reject | ✔ reject + auto-advance | AppModel.swift:108 |
| 1–5 stars | ✔ plus 0 = clear | AppModel.swift:95–100 |
| Color labels (4 dots) | ✔ 6/7/8/9 + V purple + `-` clear (5 labels) | AppModel.swift:101–106 |
| ← → navigate | ✔ | CullingKeyCaptureView.swift:105–108 |
| Space advances | ✔ (alias of next photo) | CullingKeyCaptureView.swift:113–114 |
| "Assist auto-picks" | ✘ no auto-pick / pre-pick mechanism | no code path writes or displays a provisional flag |
| (3a) ↑↓ stacks | ✔ | AppModel.swift:86–89 |
| (3a) ↵ accept **best** | ✘ accepts **selected** (defaults to frame 1) | AppModel.swift:3901–3908, 3939–3947 |
| U clear flag (extra) | ✔ beyond mockup | AppModel.swift:109 |
| Menu parity | ✔ full Culling menu, keyEquivalents | main.swift:89–115 |

Keyboard is the strongest part of the implementation. The only semantic miss is Enter-accepts-selected-not-best, and the only absent concept is assist pre-picking.

---

## 4. What "best of set" currently means

`CullingStackRecommendation.rankedCandidates` (LibraryGridView.swift:3972–3988) scores each stack frame by summing, per kind, the max of `score × confidence × weight`: focus 100, faceQuality 80, motionBlur 60 (inverted), aesthetics 50, framing 45; exposure and all non-score signals excluded (4000–4018). Frames with zero score-signals are excluded entirely, so ranking silently degrades to "no recommendation" without evaluations. The same ranking drives: the stack rail "Keep recommended N"/"Keep top 2" actions, the assist pill's stack-guidance mode (LibraryGridView.swift:2817–2827, 6241–6248), and the compare suggests-pill/primary action.

**Where it shows no rationale:** everywhere. The ranking never explains *why* — no "sharpest, eyes open", no per-kind contribution readout, no comparison against the runner-up. The stack rail's `rationaleText` is the *grouping* rationale ("Same folder, captured within 2s" from AssetStackBuilder.swift:123–126, or the fixed "Saved stack from culling session" for persisted stacks, AppModel.swift:3814–3825) — grouping provenance, not keeper reasoning. The mockups' "Best of 9 is frame 3 — sharpest, eyes open" has no implementation anywhere.

---

## 5. Filmstrip / progress / session-completion vs mockups

- **Filmstrip (2a):** BUILT minus states — 12-thumb window centered on selection, flag/rating overlay, selected ring, position text (LibraryGridView.swift:3712–3754, 2829–2882). Mockup shows rejected frames dimmed and pick/reject color bars; neither exists.
- **Progress (2a header):** BUILT — "Frame N of M" + reviewed/total progress bar + live pick/reject counts, catalog-backed counts scoped to the session query (`cullingProgressSummary` / `cullingDecisionCounts`, AppModel.swift:1267–1299). Note the loupe header's Frame N of M covers the *loaded scope* (current stack set during stack cull); global stack position lives in the rail's "Stack N of M" (`selectedPersistedCullingStackPosition`, AppModel.swift:7087).
- **Session completion:** the state machine is correct — status flips to `.completed` when every input frame is flagged (AppModel.swift:7167, 7211), detail shows reviewed/picks/rejects, ActivityView shows green "Done" (ActivityView.swift:130). The *experience* is absent: no banner, no next-step actions, no automatic navigation. Compare the import side, which has a full completion card with a fan-out of next actions — culling has no equivalent.

---

## 6. Ranked gap list

### Blocks the arc

| # | Gap | Evidence | Impact on the narrative-select arc | Size |
|---|---|---|---|---|
| 1 | **No automatic evaluation after import.** All evaluation is manual; import schedules none. | grep of Ingest services: no evaluation calls; only call sites LibraryGridView.swift:2427/2511/2519/2527, 4084, CopilotView.swift:251 | The assist layer of all four mockups is dark in the default flow: verdict pill says "No read yet", stack ranking produces no Keep recommended/Keep top 2, survey lanes show placeholders, similarity stacking inert. The "Teststrip verdict on every frame" promise fails at step one. | ~150–300 LOC (enqueue provider passes for import output once previews land, reusing `requestLatestImportAssetEvaluations` internals + BackgroundWorkQueue; plus tests) |
| 2 | **Enter accepts selected frame, not the recommended best; stack entry selects frame 1.** | AppModel.swift:3901–3908, 3939–3947 | The core 3a promise — "one decision per moment", "↵ accept best" — actually keeps frame 1 of every stack for a keyboard-only user. Worse than no assist: it feels assisted while shipping the wrong frame. | ~40–80 LOC (select recommended frame on stack entry, or route `.acceptStackSelection` through the ranking when one exists; tests) |
| 3 | **No culling-session completion handoff to Picks.** | No completion UI anywhere; only silent status flip AppModel.swift:7167/7211; Picks set exists (7225–7253) but unreferenced from the culling surface | The arc's payoff — "picks output set → browse the picks" — requires the user to spontaneously check the sidebar. The story ends mid-sentence. | ~80–150 LOC (completion detection already exists; add banner/prompt in LoupeView + "View picks" action that applies the output set) |
| 4 | **Survey confirm has no next-group loop.** | `compareAssetIDs` sticky (AppModel.swift:3568–3587); ↓ jumps to `.loupe` (3944); no group navigation in CompareView | 2b's confirm-group-move-on rhythm is impossible; compare is a one-group cul-de-sac reached from the import card or mode bar. | ~60–120 LOC (after a group decision advance the compare anchor to the next stack/window; keep `.compare` on ↑/↓ when compare is active) |
| 5 | **Recommended frame is invisible on every frame surface.** `isRecommended` computed, never rendered; no ring in survey grid. | LibraryGridView.swift:3842 vs 2781–2798; `recommendedAssetID` used only in text (3400–3406, 3444–3450) | Users can't see what the assist picked in 3a's set grid, 2a's filmstrip, or 2b's survey grid — the pre-pick visual language of all three mockups. | ~40–80 LOC (✦ badge on rail chip + ring on survey tile + filmstrip marker) |
| 6 | **No per-frame verdict with confidence + visible rationale (2a centerpiece).** | `CullingAssistPresentation` shows one signal title; detail hover-only (LibraryGridView.swift:2653, 6250–6262) | At culling speed nobody hovers; the "confirm at a glance" claim fails even with signals present. Needs a synthesized keep/toss read + inline rationale strip (provisional only — no metadata writes). | ~120–200 LOC (presentation-layer verdict from the existing ranking weights + rationale text; widen pill into a strip; tests) |
| 7 | **No eye-state signal exists anywhere in the stack.** | EvaluationSignal.swift:3–16 (no case); providers emit none (AppleVisionEvaluationProvider.swift:83–155) | "Eyes open / blink" appears in all four mockups as the marquee human-relevant read; every downstream rationale ("eyes open", "BLINK" badge) is blocked on it. | ~150–250 LOC (Vision landmarks-based eye-openness in AppleVisionEvaluationProvider + new kind + migration-safe decode + surfacing) |
| 8 | **Stack cull is blind: no stack rail/list, set grid is numbered chips without thumbnails or flaw reasons.** | LibraryGridView.swift:2780–2799 (chips); no stack sidebar exists in LoupeView (2546–3120) | 3a's set-by-set movement ("STACKS · AUTO-GROUPED" rail, done checkmarks, thumbnail set grid, per-frame "blink" captions) is the mockup's whole navigation model; without it users can't see where they are in the take or why frames were cut. | ~200–350 LOC (stack list presentation + view over persisted `inputSetIDs` with decided-state; thumbnail chips) |

### Polish (does not block the arc)

| # | Gap | Evidence | Impact | Size |
|---|---|---|---|---|
| 9 | Focus-compare tie-break affordances: contenders-only subset, rank badges, comparative delta copy, "Keep #1 & #2" in compare | LibraryGridView.swift:4110–4128 (always whole set); 3893–3907 (top-2 loupe-only) | Tie-breaks work via lanes + suggests-pill, just without the mockup's obviousness | ~150–250 LOC |
| 10 | Stack-cull session excludes non-stacked singles and never says so | AppModel.swift:7421–7430 (`count > 1` filter), 2811–2862 | After finishing stacks, leftover singles are silently unreviewed; user must start a second session by hand | ~60–100 LOC (completion prompt offering "Cull remaining N singles") |
| 11 | Per-frame flaw badges in survey/stack grids ("SOFT", "BLINK") | tiles show decision badges only (LibraryGridView.swift:4137–4152) | Lanes carry the data; badges are the glanceable form (blink part blocked on #7) | ~60–100 LOC |
| 12 | Filmstrip decision states: dim rejects, pick/reject bars | LibraryGridView.swift:2863–2882 | Glanceability during rapid cull | ~30–60 LOC |
| 13 | Loupe EXIF overlay (camera · lens · ISO); session name in header | LibraryGridView.swift:2983–3026, 2577; data exists partially (`AssetTechnicalMetadata` has make/model/lens/ISO but **no aperture/shutter/focal** — Metadata.swift:89–118) | Mockup parity; full parity needs extraction of aperture/shutter/focal at ingest | ~40 LOC display; +~80 LOC ingest fields |
| 14 | On-screen nav affordances: prev/next chevrons, keyboard legend | LoupeView has neither (2686–2703, 2884–2954) | Discoverability; keyboard already works | ~30–50 LOC |
| 15 | Exposure surfaced as EV-style delta; sharpness bars in lanes | LocalImageMetricsEvaluationProvider.swift:12–21; LibraryGridView.swift:4217–4219 | Readability of the lanes | ~40–80 LOC |
| 16 | "Choose manually" creates a new "Compare Manual Cull" session per click; sessions proliferate in Recent work | AppModel.swift:2882–2927 | Housekeeping noise in work history | ~20–40 LOC (reuse open manual-cull session for same set) |

---

## Open questions for Jesse

1. **Assist auto-pick vs the PROVISIONAL rule.** Design 2a says "Assist auto-picked — press X to override," which implies writing pick flags without user acceptance — that violates the hard product rule. Proposed reading: assist *pre-selects and displays* a provisional verdict, and a single accept gesture (Enter/P) commits it per frame or per stack. Confirm before the verdict work (gap #6) is planned.
2. **Auto-evaluation scope and budget (gap #1).** Should the post-import evaluation pass run both providers over every imported frame unconditionally (worker over cached previews, so hot-path-safe), or be gated (e.g., only stacked frames first, then the rest at idle)? This determines queue-pressure design.
3. **Enter semantics (gap #2).** Two fixes are possible: (a) stack entry selects the recommended frame so Enter-accepts-selected is naturally right, or (b) Enter routes through the recommendation when one exists. (a) is simpler and keeps one mental model ("Enter keeps what's highlighted") — preference?
4. **Eye-state provider (gap #7).** Vision's face-landmarks path gives eye-openness geometry but is a heavier per-frame cost than the current requests. Acceptable in the same evaluation pass, or a second-tier pass for face-bearing frames only (faceCount > 0)?
5. Does the next implementation plan take the blockers as one plan (rough total ~850–1,530 LOC) or split assist-layer work (#1/#2/#5/#6) from workflow-shell work (#3/#4/#8)?
