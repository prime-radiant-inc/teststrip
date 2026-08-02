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
    /// off-axis head sits at yaw -56.95 degrees (Task 0's measured
    /// original-level worst case), and an 86-degree zero point is the
    /// smallest whole-degree zero point that keeps that head at or above
    /// `FaceReportGrading.redSignalCeiling`. See the plan's frozen-constants
    /// table.
    public static let zeroAtRadians = Double.pi * 86 / 180

    /// Two detectors' boxes for the same face overlap, but not nearly as much
    /// as intuition suggests: measured across the whole preview ladder, a
    /// correctly-matched CIDetector/Vision pair fell as low as IoU 0.228 (at
    /// 1600px; the same pair scores 0.510 at 512px, because the two detectors
    /// disagree about how much forehead and chin a "face" includes, and that
    /// disagreement grows with resolution). This floor is 0.8x the worst
    /// correct match observed, so a real pair is never thrown away — below it
    /// the CIDetector face is left unscored rather than borrowing a
    /// stranger's angles.
    public static let minimumBoxOverlap = 0.14

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
