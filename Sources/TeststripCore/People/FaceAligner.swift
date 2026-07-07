import CoreGraphics
import Foundation

/// Five facial landmark points in image pixel coordinates, used to align a
/// detected face onto the canonical ArcFace reference frame.
public struct FaceLandmarkPoints: Equatable, Sendable {
    public var leftEye: CGPoint
    public var rightEye: CGPoint
    public var nose: CGPoint
    public var leftMouth: CGPoint
    public var rightMouth: CGPoint
    public init(leftEye: CGPoint, rightEye: CGPoint, nose: CGPoint, leftMouth: CGPoint, rightMouth: CGPoint) {
        self.leftEye = leftEye; self.rightEye = rightEye; self.nose = nose
        self.leftMouth = leftMouth; self.rightMouth = rightMouth
    }
    var array: [CGPoint] { [leftEye, rightEye, nose, leftMouth, rightMouth] }
}

/// Landmark-based alignment onto the canonical 112×112 crop ArcFace expects.
/// Pure geometry (Umeyama similarity transform) plus a Core Graphics resample.
public enum FaceAligner {
    public static let outputSize = 112
    public static let canonicalPoints = FaceLandmarkPoints(
        leftEye: CGPoint(x: 38.2946, y: 51.6963),
        rightEye: CGPoint(x: 73.5318, y: 51.5014),
        nose: CGPoint(x: 56.0252, y: 71.7366),
        leftMouth: CGPoint(x: 41.5493, y: 92.3655),
        rightMouth: CGPoint(x: 70.7299, y: 92.2041))

    /// Least-squares 2D similarity (rotation + uniform scale + translation)
    /// mapping the source landmarks onto `canonicalPoints`. Returns nil when
    /// the source points are degenerate (zero variance).
    public static func similarityTransform(from src: FaceLandmarkPoints) -> CGAffineTransform? {
        let from = src.array, to = canonicalPoints.array
        let n = CGFloat(from.count)
        let fMean = from.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x / n, y: $0.y + $1.y / n) }
        let tMean = to.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x / n, y: $0.y + $1.y / n) }
        var varF: CGFloat = 0, a: CGFloat = 0, b: CGFloat = 0
        for i in from.indices {
            let fx = from[i].x - fMean.x, fy = from[i].y - fMean.y
            let tx = to[i].x - tMean.x, ty = to[i].y - tMean.y
            varF += fx * fx + fy * fy
            a += fx * tx + fy * ty        // dot
            b += fx * ty - fy * tx        // cross
        }
        guard varF > 1e-6 else { return nil }
        let scale = (a * a + b * b).squareRoot() / varF
        guard scale > 1e-9 else { return nil }
        let cos = a / (varF * scale), sin = b / (varF * scale)
        // Map source point p to: scale*R*(p - fMean) + tMean
        var t = CGAffineTransform(a: scale * cos, b: scale * sin, c: -scale * sin, d: scale * cos,
                                  tx: 0, ty: 0)
        let shifted = CGPoint(x: fMean.x, y: fMean.y).applying(t)
        t.tx = tMean.x - shifted.x
        t.ty = tMean.y - shifted.y
        return t
    }

    /// Resamples `image` into a 112×112 crop aligned to the canonical frame.
    public static func alignedFace(from image: CGImage, sourcePoints: FaceLandmarkPoints) -> CGImage? {
        guard let transform = similarityTransform(from: sourcePoints) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: outputSize, height: outputSize, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // CGContext origin is bottom-left; landmark math above is top-left. Flip Y.
        ctx.translateBy(x: 0, y: CGFloat(outputSize))
        ctx.scaleBy(x: 1, y: -1)
        ctx.concatenate(transform)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }
}
