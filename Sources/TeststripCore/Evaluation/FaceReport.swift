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
    /// "is any face imperfect". Measured: geometric midpoint between the
    /// smallest subject-face area (0.15929) and the largest background-face
    /// area (0.00286) on the composite fixtures — `sqrt(0.15929 × 0.00286) =
    /// 0.0213`, rounded to 3dp.
    public static let prominenceFloor = 0.021

    /// Below this a signal is visibly wrong — a soft face, a blown or crushed
    /// face, a head turned most of the way away. This is the only band that
    /// can produce a red. Measured: the highest 2-decimal value that (a)
    /// keeps `zeroAtRadians <= 90°` for the corpus's worst measured yaw
    /// (-56.95°) and (b) maximizes the catch rate among prominence-qualifying
    /// blur/EV-±3 derivatives (19/21, exhaustive sweep of 0.20-0.36); every
    /// heavy-blur and ±3EV derivative that qualifies lands below it and no
    /// clean corpus portrait does (clean floor 0.4253, 9.5% headroom).
    public static let redSignalCeiling = 0.33

    /// At or above this every measured signal reads clean. Between the two
    /// constants the face is worth a second look but is not ruined. Measured:
    /// the minimum across signals of that signal's 10th percentile over the
    /// 11 clean corpus portraits — min(sharpness p10, light p10) = min(0.4253,
    /// 0.7502) at `.medium`, floored to 2dp; 9 of the 11 grade green (see
    /// Task 0's report for the two structurally-forced yellow outliers).
    public static let greenSignalFloor = 0.42

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
