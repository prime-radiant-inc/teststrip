# Narrative Select Reference (Culling Workflow Model)

Jesse named [Narrative Select](https://narrative.so/select) as the reference model for Teststrip's culling workflow (2026-07-06). This summarizes their shipped feature set in their own terminology (fetched 2026-07-06) and maps each to Teststrip's implementation status. Use this when planning or auditing culling work.

## Their workflow

Import thousands of RAWs → cull with AI assessments and instant keyboard transitions → ship selects to Lightroom/Capture One. Speed is the product: next image renders the moment the arrow key is hit, previews never show low-res placeholders.

## Their features → Teststrip mapping

| Narrative Select feature | What it does | Teststrip status |
|---|---|---|
| **Eye Assessments** | Per-subject eyes open / closed / blinking / looking down | Planned (2026-07-06 culling-signals plan): open/closed via stock APIs; blinking/looking-down beyond stock — do not overclaim |
| **Focus Assessments** | Subject in/out of focus | Partial: whole-image focus signal exists; eye/face-region focus planned |
| **Image Assessments** | Flags relatively superior frames within a scene | Partial: focus/exposure/aesthetics signals exist; relative in-stack ranking drives Keep recommended |
| **Close-Ups Panel** | Auto-cropped enlarged faces beside the loupe; spacebar zooms to the most important face | Missing — high-value culling UI; face rectangles already persist |
| **Key Element Detection** | Saliency fallback when no faces present | Missing; Vision attention-saliency is a stock candidate; optional |
| **Scenes View** | Groups scene/near-dupes, ranks by sharpness, best frame first | Partial: time-adjacent + visual-similarity stacks exist; best-first ranked presentation needs audit |
| **People Filter** | Filter shoot by person(s); coverage counts | Planned (face-recognition plan): confirmed-person filtering |
| **Potential Picks filter** | AI cuts review volume ~50% by filtering to likely keepers | Missing as a first-class scope; review-queue infrastructure exists — a provisional "likely picks" queue must not auto-write flags |
| **One-click shipping** | To Lightroom Classic/CC, Photoshop, Capture One | Different approach: Teststrip writes XMP sidecars continuously + resized-JPEG export; LR reads sidecars |
| **Smile detection** | Not in their public list | Jesse wants it anyway; stock CIDetector supports it |

## Product rules that still bind

Machine assessments stay provisional until the user acts on them; nothing auto-writes catalog metadata or XMP. Formats: their RAW list overlaps Teststrip's ImageIO capability matrix; HEIC/HEIF matter for real libraries.
