# Teststrip Design

Date: 2026-07-01
Branch: wip/teststrip-design

## Purpose

Teststrip is a macOS photo management and workflow system for pro and semi-pro photographers with external catalogs that may contain hundreds of thousands of images across decades. It is intended to replace the photo management side of Lightroom, not the editing side.

The product should feel clean, fast, and modern, while staying grounded in pro catalog workflows: browsing, ingest, culling, search, metadata, people, places, smart collections, and agent-assisted organization.

## Approved V1 Position

- V1 is macOS-native. iOS portability is a future consideration, not a constraint on the first UI architecture.
- The app is non-destructive and external-file based. Originals remain where the photographer keeps them.
- Lightroom catalog migration tools are out of scope.
- Folder import and card/camera ingest are in scope. Watched folders are out of scope.
- Pre-import culling is out of scope. Import preserves and catalogs first; culling happens after assets exist in the catalog.
- Local-first recognition/evaluation is in scope, with provider boundaries designed for future opt-in cloud or local HTTP model providers.
- The first implementation slice proves the catalog, preview, worker, native grid, metadata, and set/search foundation before building a polished culling or agent demo.

## Architecture

Teststrip v1 is a macOS-native app, not a Tauri app. The performance-critical UI should be Swift/SwiftUI where appropriate, with AppKit, Metal, Core Image, or lower-level native views available for the grid, loupe, compare, image presentation, and keyboard-heavy culling paths.

The app ships as one app bundle with two main runtime roles:

- UI app process: user interaction, catalog browsing, preview display, selection state, filters/search UI, metadata edits, work controls, and visible progress.
- Supervised local worker process: folder/card ingest, preview pyramid generation, RAW decoding, recognition/evaluation, indexing, XMP sync, availability scans, and long-running work.

The worker is not an uncontrolled daemon. It is launched and supervised by the UI app, visible in the Activity/Work UI, cancellable, throttleable, and normally stops when the app quits. Any "continue in background" mode must be explicit, visible, and killable.

Internally, Teststrip should use clean modules rather than many standalone services:

- Catalog database and asset model
- Asset/source availability tracker
- Preview cache and progressive loading pipeline
- Decoder registry
- Recognition/evaluation provider registry
- Metadata and XMP sync
- Search, set, and collection engine
- Work session/activity history
- UI adapters

The catalog is the coordination point, but shared state should be accessed through narrow APIs. The design should avoid casual writes from arbitrary UI and worker code.

## Catalog And Assets

Teststrip is catalog-first and non-destructive. Originals may live on local disks, removable drives, NAS volumes, cloud-synced folders, or card-ingest destinations. Teststrip owns the local catalog, previews, indexes, work-session history, recognition/evaluation outputs, and metadata sync state around those originals.

Each asset should track:

- Stable asset id
- Current path
- Volume/source identity where available
- File fingerprint/checkpoint data for move/change detection
- Original availability state: online, offline, missing, moved, or stale
- File/media metadata and capture metadata
- Rating, color label, pick/reject flag, keywords, captions, and supported portable metadata
- Decode and preview provenance: provider, version, settings, and generated levels
- Recognition/evaluation signals with provider, model, version, confidence, and provenance

The UI must remain useful when originals are unavailable. Grid browsing, search, metadata review, culling over previews, work history, and most organization workflows should operate from local catalog state and previews. Operations that need original pixels, such as full-quality export, full-res loupe, full preview re-rendering, and some recognition work, should queue or ask for reconnect.

Reconnect should be explicit and resumable. Teststrip should not silently churn through a NAS or cloud mount. Offline sources must be visible and manageable.

## Previews And Progressive Loading

Previews are a first-class performance subsystem. They are not just offline convenience; they are the primary way Teststrip avoids pulling 100MP+ originals from slow, remote, or removable storage during ordinary browsing and culling.

Teststrip should generate a local preview pyramid:

- Micro thumbnail for dense grids and timeline ribbons
- Grid thumbnail for normal browsing
- Medium preview for survey/compare and quick loupe
- Large smart preview for high-DPI culling and offline review
- Original/full decode only when source pixels are truly needed

The image display pipeline should progressively promote quality:

1. Show the nearest cached thumbnail immediately.
2. Promote to medium or large preview if the cell or loupe remains visible.
3. Decode the original only for explicit full-res zoom, export, re-rendering, or quality-critical recognition.
4. Cancel lower-priority work aggressively when the user scrolls or changes selection.

The scheduler should be viewport-aware, priority-based, and I/O-throttled. Visible images and the active loupe win. Nearby images prefetch. Remote and NAS sources get stricter concurrency and backoff. The worker should expose queue state so users can see when Teststrip is generating previews or waiting on offline volumes.

Routine navigation should prefer local previews. Pulling originals from NAS during ordinary browsing is a product bug unless the user explicitly asks for full-res pixels.

## Import And Ingest

V1 supports two import modes:

- Add existing folders: catalog photos in place without moving originals.
- Card/camera ingest: copy files from card/camera to a user-chosen folder structure, then catalog them.

Watched folders are out of scope for v1.

Import preserves first and analyzes second. Once assets exist in the catalog, worker tasks generate previews, read metadata/XMP, detect availability, fingerprint files, and run optional recognition/evaluation or culling workflows.

Imports must be durable and resumable. A quit, crash, or worker restart should not leave the catalog confused about copied files, indexed files, or pending previews.

During card ingest, Teststrip should show the planned destination, copy progress, new asset count, preview/indexing progress, and pending review work. Expensive downstream work is throttleable and cancellable without undoing the safe file copy/catalog step.

## Decode Provider Registry

RAW and image decoding should go through a clean provider registry rather than a single hardcoded path.

A decode provider should be responsible for:

- Identifying supported formats
- Extracting file and capture metadata
- Rendering embedded previews quickly
- Rendering working previews
- Rendering full-quality images when supported
- Reporting provider/version/settings provenance

Provider selection is per asset and recorded in the catalog. The browsing path should prefer the fastest safe representation, often embedded JPEG or existing preview data, before full RAW decode.

Apple ImageIO/RAW should be used where it is strong and hardware-integrated. Broader RAW support should be possible through additional providers such as LibRaw or RawSpeed-style integrations. The registry must make it practical to support formats such as DNG, CRW, CR2, Fuji RAW, and older specialty formats without forcing one decoder to handle everything. Lytro-style support is explicitly out of scope unless a provider is added later.

Unsupported or partially supported formats should still be catalogable when metadata or embedded previews can be read.

## Metadata And XMP

The catalog is the operational truth. UI reads and writes go to the catalog first so rating, flagging, labeling, keywording, and culling decisions feel instant.

XMP is the automatic portability layer for stable metadata. V1 should continuously write sidecars for supported portable fields:

- Ratings
- Color labels
- Keywords
- Captions
- Creator/copyright
- Other standard fields explicitly supported by the implementation

Agent-only state stays internal unless the user accepts it into normal catalog metadata. Raw machine guesses, confidence scores, clustering internals, embeddings, explanations, and work-session history should not automatically pollute XMP.

Conflict detection must not be "latest mtime wins." Teststrip should track the last XMP fingerprint it read or wrote plus local catalog generations. If sidecar changes are external and there are no unsynced local edits, Teststrip imports them automatically. If both sides changed, Teststrip creates a metadata conflict work item with field-level resolution where practical.

Offline or read-only sources do not block catalog work. XMP writes queue until the volume is available and writable. Pending sync state should be visible without making ordinary catalog work feel risky.

## Recognition And Evaluation

Recognition and evaluation are first-class subsystems in v1. They should be local-first, provider-backed, and provenance-rich.

The provider model should support:

- Apple-local provider paths using Vision, Core ML, Core Image, and Foundation Models where appropriate
- Local/cloud HTTP provider boundaries, with v1 smoke tests that exercise batching, retries, cancellation, provenance, and result import
- Future opt-in cloud providers without catalog/schema redesign
- Local HTTP model servers such as LM Studio or Ollama as early practical stand-ins for remote providers
- Reprocessing when providers or model versions change

Teststrip should not assume Apple exposes the full Photos.app people-identification stack for external catalogs. Teststrip owns catalog-level clustering, naming, review, confidence, and reprocessing state.

Evaluators produce typed signals, not one magic verdict. Useful signal families include:

- Technical quality: focus, motion blur, exposure, noise, lens smudge, face/eye sharpness
- Human quality: eyes open, expression, gaze, face visibility, group-photo best-frame ranking
- Composition: framing, subject placement, crop safety, saliency, horizon/tilt, clutter
- Aesthetics: visual appeal scores where available, treated as one signal rather than truth
- Content: objects, scenes, people, OCR, landmarks/places, activities
- Similarity and novelty: duplicates, near-duplicates, burst grouping, different-enough frames, portfolio variety
- Color and look: dominant colors, palette, saturation, contrast, warmth, black-and-white, style clusters
- Workflow usefulness: likely portfolio pick, client-deliverable candidate, needs keywords, export candidate, review needed

All evaluation outputs should include provider/model/version/confidence/provenance. Jobs and searches combine those signals according to user intent. "Best group portrait" and "best landscape portfolio candidate" should rank differently.

Provisional machine outputs should not automatically become user keywords or XMP. The user must accept or configure that promotion.

Reference products and frameworks worth learning from:

- Narrative Select for fast culling, scene grouping, close-up review, face/focus assessment, and human-confirmed ranking
- Apple Vision for text recognition, image classification, aesthetics scoring, saliency, and feature-print similarity
- LM Studio and Ollama for local OpenAI-compatible or local HTTP model provider patterns

## Search, Sets, And Collections

Teststrip needs one query/set model that supports classic navigation, saved organization, and agentic workflows.

A set is the asset membership concept. It can be:

- Transient search result
- Saved search or smart collection
- Manual collection
- Import batch
- Folder, date, person, or place scope
- Cluster output: bursts, near-duplicates, similar looks, same person, same location, novelty groups
- Work-session-derived set: input, candidate, review, accepted, rejected, output

Sets can be named, saved, starred, dynamic, or frozen snapshots. Dynamic sets re-evaluate as metadata and evaluation signals change. Snapshot sets preserve exact membership. Manual collections are explicit user membership plus ordering.

The query system should combine normal metadata, file/source state, XMP metadata, recognition/evaluation signals, and human decisions. Search-first UX and filter bars are two faces of the same model: plain-language search parses into structured predicates; the filter UI exposes and edits those predicates.

Jobs/work sessions do not own asset membership directly. They record activity and point to sets:

- Input set: what the user started from
- Generated sets/clusters: near-duplicate groups, likely keepers, review candidates
- Output set: accepted portfolio candidates, client selects, rejected frames, exported group

This makes "photos that are part of a work session" a set whose source is that session, not a separate membership system.

## Work Sessions And Activity

Teststrip should model workflow as work sessions and activity history rather than top-level "working sets."

A work session is a record of work performed against one or more sets with intent. Session types include import, preview generation, recognition, culling, collecting, search/sort, keywording, XMP sync, export, and eventually editing.

Work sessions track:

- Intent
- Input and output sets
- Status and progress
- Timestamps
- Operations performed
- Suggestions generated
- Human decisions
- Errors and recovery state
- Provider/tool provenance

Most sessions live in history. Starred/pinned sessions and recent active sessions appear in the sidebar under a Work section. The full Activity/Work view shows everything with filtering, recovery controls, and auditability.

Culling is a work session over an arbitrary set, not only an import batch. The input set can come from an import, folder, date range, search, smart collection, person, place, manual selection, or saved query. Detectors propose scenes, bursts, stacks, duplicates, and quality assessments inside that set. Users can provide intent such as "one hero per burst," "best expression for group portraits," or "sharp wildlife keepers."

Recommendations are separate from accepted decisions. Suggestions include explanation, confidence, and provenance. Human confirmation writes normal catalog metadata or set membership. Bulk decisions must be reversible and reviewable.

## UI Direction

The starting UI hypothesis should be closest to the designer's 1a Studio direction:

- Familiar pro workspace
- Dense library grid
- Left catalog/work sidebar
- Top search/filter bar
- Right inspector
- Fast view switches for grid, loupe, compare, map, people, and timeline

The 1b Copilot direction should be integrated rather than replacing the shell. Teststrip should have command/search, agent/task review surfaces, and suggestion chips, but photographers should not feel trapped in a chat-first product.

The 1c Timeline direction becomes a navigation lens: year/month/day density over the same catalog/query model, not a separate data path.

The Work section in the sidebar shows recent and starred work sessions. Library sections show normal catalog scopes, saved searches, collections, people, places, folders, and other navigable views.

The culling UI should learn from Narrative Select: instant transitions, keyboard-first decisions, group/scene/stack ranking, face/detail close-ups, focus/eye indicators, and human-confirmed bulk decisions. Teststrip's culling works over arbitrary sets, not only fresh shoots.

This UI direction is a starting hypothesis. The architecture should make it cheap to rebalance Studio, Copilot, and Timeline emphasis after trying the app with real catalogs.

## Performance Targets

V1 should be designed and tested against explicit scale targets:

- Baseline catalog: 500k images
- Stress catalog: 1M images
- Grid scroll: no visible blanking once previews exist
- Keyboard culling and metadata decisions: immediate UI acknowledgement, target under 50 ms
- Common indexed metadata filters/searches: target under 200 ms after indexing
- Import/indexing/preview generation: durable, resumable, throttleable, and unable to starve the UI

Remote/NAS/cloud/removable originals are normal, not edge cases. Local previews and catalog indexes must keep the product useful when sources are slow or offline.

## First Vertical Slice

The first implementation target is foundation, not a polished agent demo.

It should include:

- Native macOS app shell with the Studio-style layout hypothesis
- Catalog DB and asset model for external originals
- Folder import and card/camera ingest
- Decode provider abstraction
- Preview pyramid generation
- Progressive image loading in the native grid
- Basic metadata state: rating, color label, pick/reject, keywords
- Catalog-first metadata writes with queued XMP mirroring
- Supervised worker with visible activity, pause/cancel/throttle, and durable resume
- Basic set/search model for folders, imports, manual selection, and saved searches
- Recognition/evaluation provider scaffolding, including Apple-local path and local/cloud HTTP smoke-provider boundaries
- Performance harness targeting 500k baseline and 1M stress catalogs

The first slice succeeds if Teststrip can import/catalog a large set, generate previews without UI starvation, browse and progressively load images quickly, change metadata instantly, survive offline originals, and show/manage background work.

## Deferred Scope

The following are intentionally deferred:

- Photo editing/develop tools
- Lightroom .lrcat migration
- Pre-import culling
- Watched folders
- iOS UI
- Always-on uncontrolled background agents
- Lytro support
- Automatic promotion of provisional agent labels into XMP/user keywords
- Many separate local services before the native app plus supervised worker model proves insufficient

## External References

- Narrative Select: https://narrative.so/select
- Narrative Select Scenes View: https://narrative.so/select/scenes-view
- Narrative Select Close-Ups Panel: https://narrative.so/select/the-close-ups-panel
- Narrative Select Face Assessments: https://narrative.so/select/face-assessments
- Apple Vision: https://developer.apple.com/documentation/vision
- Apple Vision feature-print similarity: https://developer.apple.com/documentation/vision/analyzing-image-similarity-with-feature-print
- Apple Vision saliency cropping: https://developer.apple.com/documentation/vision/cropping-images-using-saliency
- Apple Vision aesthetics scoring: https://developer.apple.com/documentation/vision/calculateimageaestheticsscoresrequest
- Apple Foundation Models: https://developer.apple.com/documentation/foundationmodels
- LM Studio OpenAI compatibility: https://lmstudio.ai/docs/developer/openai-compat
- LM Studio local server: https://lmstudio.ai/docs/developer/core/server
- Ollama OpenAI compatibility: https://docs.ollama.com/api/openai-compatibility
- Ollama vision models: https://docs.ollama.com/capabilities/vision
