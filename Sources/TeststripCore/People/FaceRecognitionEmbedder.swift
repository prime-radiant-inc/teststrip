import CoreGraphics
import Foundation
import Vision

/// Orchestrates detect → landmarks → align → embed for one image, emitting an
/// `AppleVisionFaceObservation` per successfully embedded face. Replaces the
/// whole-image `VNGenerateImageFeaturePrint`-per-face descriptor with a real
/// face-identity embedding from `FaceEmbeddingModel`.
public struct FaceRecognitionEmbedder: Sendable {
    private let model: any FaceEmbeddingModel

    public init(model: any FaceEmbeddingModel) {
        self.model = model
    }

    public func faceObservations(in image: CGImage) throws -> [AppleVisionFaceObservation] {
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([landmarksRequest])
        let faces = landmarksRequest.results ?? []

        var observations: [AppleVisionFaceObservation] = []
        for face in faces {
            guard let sourcePoints = Self.landmarkPoints(from: face, imageWidth: image.width, imageHeight: image.height),
                  let aligned = FaceAligner.alignedFace(from: image, sourcePoints: sourcePoints) else {
                continue
            }
            let embedding: [Double]
            do {
                embedding = try model.embedding(for: aligned)
            } catch {
                // A face that cannot be embedded is skipped, never fatal.
                continue
            }
            observations.append(AppleVisionFaceObservation(
                boundingBox: FaceBoundingBox(
                    x: Double(face.boundingBox.origin.x),
                    y: Double(face.boundingBox.origin.y),
                    width: Double(face.boundingBox.width),
                    height: Double(face.boundingBox.height)
                ),
                captureQuality: face.faceCaptureQuality.map(Double.init),
                featurePrintVector: embedding
            ))
        }
        return observations
    }

    /// Extracts the five ArcFace landmark points in top-left image pixel
    /// coordinates. Vision reports landmarks normalized to the face bounding
    /// box, with a bottom-left origin; convert both.
    static func landmarkPoints(from face: VNFaceObservation, imageWidth: Int, imageHeight: Int) -> FaceLandmarkPoints? {
        guard let landmarks = face.landmarks,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye,
              let nose = landmarks.nose,
              let outerLips = landmarks.outerLips else {
            return nil
        }
        let box = face.boundingBox
        let width = CGFloat(imageWidth)
        let height = CGFloat(imageHeight)

        func toImagePixels(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
            region.normalizedPoints.map { point in
                let nx = box.origin.x + point.x * box.width
                let ny = box.origin.y + point.y * box.height
                // Vision origin is bottom-left; flip to top-left pixel space.
                return CGPoint(x: nx * width, y: (1 - ny) * height)
            }
        }

        func centroid(_ points: [CGPoint]) -> CGPoint? {
            guard !points.isEmpty else { return nil }
            let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
        }

        let lipPoints = toImagePixels(outerLips)
        guard let leftEyeCenter = centroid(toImagePixels(leftEye)),
              let rightEyeCenter = centroid(toImagePixels(rightEye)),
              let noseCenter = centroid(toImagePixels(nose)),
              !lipPoints.isEmpty else {
            return nil
        }

        // Mouth corners are the extreme-x points of the outer-lip contour.
        let leftMouth = lipPoints.min { $0.x < $1.x }!
        let rightMouth = lipPoints.max { $0.x < $1.x }!

        return FaceLandmarkPoints(
            leftEye: leftEyeCenter,
            rightEye: rightEyeCenter,
            nose: noseCenter,
            leftMouth: leftMouth,
            rightMouth: rightMouth
        )
    }
}
