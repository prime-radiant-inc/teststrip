import Foundation
import CoreImage

public enum RotationTransform {
    /// Maps a clockwise rotation in degrees to the matching EXIF orientation
    /// for CIImage.oriented(forExifOrientation:).
    /// - 0° → .up (1)
    /// - 90° CW → .right (6)
    /// - 180° → .down (3)
    /// - 270° CW → .left (8)
    public static func exifOrientation(forRotation rotation: Int) -> CGImagePropertyOrientation {
        switch rotation {
        case 0: return .up
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    /// Returns the pixel dimensions after rotation. For 90°/270°, width and
    /// height are swapped.
    public static func rotatedDimensions(width: Int, height: Int, rotation: Int) -> (width: Int, height: Int) {
        switch rotation {
        case 90, 270:
            return (height, width)
        default:
            return (width, height)
        }
    }
}
