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
