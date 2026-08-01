import CoreGraphics
import Foundation
import TeststripCore

/// Display-only close-up crop geometry for the loupe's close-ups rail. Crops
/// come from on-demand face detection over the cached preview; nothing
/// persists. Every read a crop shows now lives in its `FaceReport` (paired by
/// `faceIndex`), so this type owns geometry alone.
struct CloseUpFacesPresentation: Equatable {
    struct Crop: Equatable, Identifiable {
        var id: Int
        /// Index into the `faces` array this crop was built from. Crops sort
        /// largest-first while reports stay in detection order, so the tile
        /// needs this to pair with the right report card.
        var faceIndex: Int
        var pixelRect: CGRect
    }

    static let maximumCropCount = 4
    private static let cropPaddingFactor = 1.6
    private static let minimumCropSidePixels = 24.0

    var crops: [Crop]

    init(faces: [DetectedFaceExpression], imagePixelSize: CGSize) {
        let imageBounds = CGRect(origin: .zero, size: imagePixelSize)
        // Largest first: prominence is both the grading weight and the order
        // a photographer scans in.
        let orderedFaces = faces.enumerated().sorted { lhs, rhs in
            lhs.element.normalizedBounds.width * lhs.element.normalizedBounds.height
                > rhs.element.normalizedBounds.width * rhs.element.normalizedBounds.height
        }
        var crops: [Crop] = []
        for (faceIndex, face) in orderedFaces {
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
            crops.append(Crop(id: crops.count, faceIndex: faceIndex, pixelRect: rect))
        }
        self.crops = crops
    }
}
