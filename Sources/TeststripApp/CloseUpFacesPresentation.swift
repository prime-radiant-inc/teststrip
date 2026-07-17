import CoreGraphics
import Foundation
import TeststripCore

/// Display-only close-up crop geometry and per-face read marks for the
/// loupe's close-ups rail. Crops come from on-demand face detection over the
/// cached preview; nothing persists.
struct CloseUpFacesPresentation: Equatable {
    /// Both eyes shut, straight from the detector — always known the moment
    /// a face is detected, so there's no "unknown" third state to hide.
    enum EyesState: Equatable {
        case open
        case closed
    }

    enum SharpnessTone: Equatable {
        case sharp
        case soft
    }

    struct Crop: Equatable, Identifiable {
        var id: Int
        var pixelRect: CGRect
        var eyesState: EyesState
        var isSmiling: Bool
        /// nil when there's no honest way to attribute a sharpness/quality
        /// read to this specific face (see `sharpnessTone(for:)`).
        var sharpnessTone: SharpnessTone?
    }

    static let maximumCropCount = 4
    private static let cropPaddingFactor = 1.6
    private static let minimumCropSidePixels = 24.0

    var crops: [Crop]

    init(faces: [DetectedFaceExpression], imagePixelSize: CGSize, wholePhotoSignals: [EvaluationSignal] = []) {
        let imageBounds = CGRect(origin: .zero, size: imagePixelSize)
        let orderedFaces = faces.sorted { lhs, rhs in
            lhs.normalizedBounds.width * lhs.normalizedBounds.height
                > rhs.normalizedBounds.width * rhs.normalizedBounds.height
        }
        var crops: [Crop] = []
        for face in orderedFaces {
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
            crops.append(Crop(
                id: crops.count,
                pixelRect: rect,
                // Fractional eye state is the same CIDetector noise floor
                // the rest of the app treats as inconclusive elsewhere
                // (CompareSurveyPresentation.flawBadges) — only both eyes
                // shut reads as closed.
                eyesState: (face.leftEyeClosed && face.rightEyeClosed) ? .closed : .open,
                isSmiling: face.hasSmile,
                sharpnessTone: nil
            ))
        }
        // faceQuality/eyeSharpness are asset-level evaluation signals — they
        // carry no per-face location — so attributing one to a specific crop
        // is only honest when exactly one face is on the frame; otherwise
        // which face it describes is ambiguous, and no mark beats a
        // misleading one.
        if crops.count == 1, let tone = Self.sharpnessTone(for: wholePhotoSignals) {
            crops[0].sharpnessTone = tone
        }
        self.crops = crops
    }

    // Face quality already reflects the detector's overall read on the face
    // (sharpness plus expression), so it's the primary signal; eye sharpness
    // is the fallback when face quality wasn't scored.
    private static func sharpnessTone(for signals: [EvaluationSignal]) -> SharpnessTone? {
        if let score = bestScore(kind: .faceQuality, in: signals) {
            return score >= EvaluationSignalPresentation.faceQualityStrongThreshold ? .sharp : .soft
        }
        if let score = bestScore(kind: .eyeSharpness, in: signals) {
            return score >= EvaluationSignalPresentation.eyeSharpnessSharpThreshold ? .sharp : .soft
        }
        return nil
    }

    private static func bestScore(kind: EvaluationKind, in signals: [EvaluationSignal]) -> Double? {
        signals
            .filter { $0.kind == kind }
            .sorted { $0.confidence > $1.confidence }
            .compactMap { signal -> Double? in
                guard case .score(let score) = signal.value else { return nil }
                return score
            }
            .first
    }
}
