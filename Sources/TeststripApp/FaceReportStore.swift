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
    static let lowestAcceptedLevel: PreviewLevel = .medium

    /// Highest first, so a lookup takes the best cached preview available.
    static let acceptedLevelsHighestFirst: [PreviewLevel] = PreviewLevel.allCases
        .filter { accepts($0) }
        .sorted { $0.faceReportRank > $1.faceReportRank }

    static func accepts(_ level: PreviewLevel) -> Bool {
        level.faceReportRank >= lowestAcceptedLevel.faceReportRank
    }
}

/// The cached preview a frame's report cards are measured from, and the level
/// it came from — both halves of the staleness key. Public: `AppModel`'s
/// `faceReportPreviewSource(for:)` hands this out as part of its public
/// surface, matching `loupePreviewURL`/`loupeZoomPreviewURL` beside it.
public struct FaceReportPreviewSource: Equatable, Sendable {
    public var previewURL: URL
    public var level: PreviewLevel

    public init(previewURL: URL, level: PreviewLevel) {
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
