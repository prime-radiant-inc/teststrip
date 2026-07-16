# Narrative Select Reference (Culling Workflow Model)

Jesse named [Narrative Select](https://narrative.so/select) as the reference model for Teststrip's culling workflow (2026-07-06). This summarizes their shipped feature set in their own terminology (fetched 2026-07-06) and maps each to Teststrip's implementation status. Use this when planning or auditing culling work.

Updated 2026-07-16: the feature-mapping table below was re-audited against shipped code — see `docs/design-spikes/2026-07-16-culling-redesign/teststrip-signals-inventory.md` for file:line evidence. Most rows that read "Planned"/"Missing"/"Partial" as of 2026-07-06 are now built; the naming/fetch dates above are unchanged.

## Their workflow

Import thousands of RAWs → cull with AI assessments and instant keyboard transitions → ship selects to Lightroom/Capture One. Speed is the product: next image renders the moment the arrow key is hit, previews never show low-res placeholders.

## Their features → Teststrip mapping

| Narrative Select feature | What it does | Teststrip status |
|---|---|---|
| **Eye Assessments** | Per-subject eyes open / closed / blinking / looking down | Built: `eyesOpen` signal (CIDetector `CIDetectorEyeBlink`) surfaces open/closed in the verdict pill and rationale phrases ("Eyes open"/"Eyes shut"/"Some eyes shut") and factors into stack ranking; blinking/looking-down beyond open/closed remain unimplemented — do not overclaim |
| **Focus Assessments** | Subject in/out of focus | Built: whole-image `focus` signal plus per-face `eyeSharpness` (minimum-across-faces eye-crop sharpness); no other face-region (mouth/whole-head) focus metric |
| **Image Assessments** | Flags relatively superior frames within a scene | Built: `CullingQualityScore` ranks stack members on focus/exposure/aesthetics/face signals and renders as a ✦ recommended badge, Keep recommended/Keep top 2 actions, and the verdict pill's Keep/Toss read; rationale is honest, score-gated text (no defect iconography yet) |
| **Close-Ups Panel** | Auto-cropped enlarged faces beside the loupe; spacebar zooms to the most important face | Built: `CloseUpFacesPresentation` renders up to 4 padded face crops beside the loupe stage, auto-populated per selection. Binding differs from Narrative Select: Teststrip's zoom-to-face is `Shift+Z`, not spacebar (Space advances to the next photo) |
| **Key Element Detection** | Saliency fallback when no faces present | Missing; Vision attention-saliency is a stock candidate; optional |
| **Scenes View** | Groups scene/near-dupes, ranks by sharpness, best frame first | Built: `AssetStackBuilder` groups by time-adjacency/visual-similarity; `CullingQualityScore` ranks within a stack and renders as a ✦ recommended badge; the Cull sidebar's "Stacks · Auto-Grouped" section browses every detected stack with a done-checkmark per fully-decided stack |
| **People Filter** | Filter shoot by person(s); coverage counts | Built: `SetQuery.Predicate.person(String)`, the `person:` search token, and `PeopleView`'s tap-to-filter on named-person cards (with photo-count badges) |
| **Potential Picks filter** | AI cuts review volume ~50% by filtering to likely keepers | Built: `ReviewQueue.potentialPicks`, backed by the `likelyPick` SQL predicate (focus ≥0.8, aesthetics ≥0.65, or faceQuality ≥0.45, not already flagged); reachable from the Cull sidebar's "Top Picks" row and search. Display-only — never auto-writes flags |
| **One-click shipping** | To Lightroom Classic/CC, Photoshop, Capture One | Different approach: Teststrip writes XMP sidecars continuously + resized-JPEG export; LR reads sidecars |
| **Smile detection** | Not in their public list | Built: `smile` signal (CIDetector `CIDetectorSmile`, same detection pass as `eyesOpen`) — Jesse wanted it anyway |
| **A/B Compare** *(not in their public list)* | Two-up frame-vs-frame decision | Built: `ABCompareView`, a two-up comparison mode with dedicated `,`/`.` keyboard verdicts (keep A over B / keep B over A) — a genuinely new Teststrip surface with no Narrative Select equivalent |

## Product rules that still bind

Machine assessments auto-apply to the catalog immediately as tentative, reversible `origin=ai` labels — this supersedes the 2026-07-06 framing that "nothing auto-writes catalog metadata." They never write XMP sidecars, and a tentative-only flag/rating is never eligible for destructive or committing operations (move/trash-rejects, the persisted Picks set, export) until a user explicitly confirms (flips to `origin=user`, writes the sidecar for sidecar-eligible fields) or removes it (recorded so re-evaluation can't resurrect it). Formats: their RAW list overlaps Teststrip's ImageIO capability matrix; HEIC/HEIF matter for real libraries.
