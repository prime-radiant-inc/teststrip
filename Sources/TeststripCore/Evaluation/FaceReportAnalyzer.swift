import CoreGraphics
import Foundation
import Vision

/// Turns the close-ups pass's CIDetector detections plus the preview image
/// into one report card per face. Pure with respect to app state: image and
/// detections in, reports out; nothing is read from or written to the
/// catalog, and nothing is persisted.
public struct FaceReportAnalyzer: Sendable {
    /// Face crops are resampled to this square before measurement, matching
    /// the sample size the whole-photo metrics provider already uses.
    public static let cropSampleSize = 16

    /// Crops narrower than this measure noise, not the face, so their
    /// sharpness and light stay unscored rather than fabricated.
    public static let minimumCropPixels = 8

    private let orientationDetector: any FaceOrientationDetecting

    public init(orientationDetector: any FaceOrientationDetecting = VisionFaceOrientationDetector()) {
        self.orientationDetector = orientationDetector
    }

    public func reports(in image: CGImage, detections: [DetectedFaceExpression]) -> [FaceReport] {
        guard !detections.isEmpty else { return [] }
        // A failed head-pose request leaves every facing unscored — an empty
        // ring and a "no read" hover, never a fake score and never a fake
        // green.
        let orientations = (try? orientationDetector.orientations(in: image)) ?? []
        let facing = FaceFacingScore.matched(
            detectionBounds: detections.map(\.normalizedBounds),
            orientations: orientations
        )
        return detections.enumerated().map { index, detection in
            let samples = cropSamples(of: image, normalizedBounds: detection.normalizedBounds)
            return FaceReport(
                normalizedBounds: detection.normalizedBounds,
                eyesOpen: !detection.bothEyesShut,
                hasSmile: detection.hasSmile,
                sharpness: samples.map {
                    PreviewPixelMetrics.focusScore(
                        in: $0,
                        width: Self.cropSampleSize,
                        height: Self.cropSampleSize
                    )
                },
                light: samples.map {
                    PreviewPixelMetrics.balancedExposure(
                        meanLuminance: PreviewPixelMetrics.meanLuminance(
                            in: $0,
                            width: Self.cropSampleSize,
                            height: Self.cropSampleSize
                        )
                    )
                },
                facing: facing[index],
                prominence: min(max(Double(detection.normalizedBounds.width * detection.normalizedBounds.height), 0.0), 1.0)
            )
        }
    }

    /// nil when the face's pixel crop is smaller than `minimumCropPixels` on
    /// either side, or the crop could not be made.
    private func cropSamples(of image: CGImage, normalizedBounds: CGRect) -> [UInt8]? {
        let imageWidth = Double(image.width)
        let imageHeight = Double(image.height)
        // CGImage cropping is top-left origin, the same convention
        // `DetectedFaceExpression.normalizedBounds` uses.
        let pixelRect = CGRect(
            x: (Double(normalizedBounds.minX) * imageWidth).rounded(.down),
            y: (Double(normalizedBounds.minY) * imageHeight).rounded(.down),
            width: (Double(normalizedBounds.width) * imageWidth).rounded(),
            height: (Double(normalizedBounds.height) * imageHeight).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        guard pixelRect.width >= Double(Self.minimumCropPixels),
              pixelRect.height >= Double(Self.minimumCropPixels),
              let crop = image.cropping(to: pixelRect) else {
            return nil
        }
        return try? PreviewPixelMetrics.rgbaSamples(
            of: crop,
            width: Self.cropSampleSize,
            height: Self.cropSampleSize
        )
    }
}

/// Head pose from Vision's face rectangle detector. Revision 3 is pinned
/// explicitly because it is the revision that reports pitch as well as yaw —
/// leaving it to the default would make the facing signal silently
/// half-blind if a future SDK changes the default.
public struct VisionFaceOrientationDetector: FaceOrientationDetecting {
    public init() {}

    public func orientations(in image: CGImage) throws -> [FaceOrientationObservation] {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).map(Self.orientation(from:))
    }

    /// Vision's boundingBox is bottom-left origin; report cards use top-left,
    /// the same flip `FaceBoxOverlayGeometry` applies. Factored out so the
    /// mapping is directly testable against constructed observations rather
    /// than only through a live request.
    static func orientation(from observation: VNFaceObservation) -> FaceOrientationObservation {
        FaceOrientationObservation(
            normalizedBounds: CGRect(
                x: observation.boundingBox.minX,
                y: 1.0 - observation.boundingBox.maxY,
                width: observation.boundingBox.width,
                height: observation.boundingBox.height
            ),
            yawRadians: observation.yaw?.doubleValue,
            pitchRadians: observation.pitch?.doubleValue
        )
    }
}
