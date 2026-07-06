import Foundation

/// Shared display formatting for photographer-facing EXIF values. Used by
/// both the inspector's technical metadata rows and the culling loupe's
/// EXIF overlay so the two surfaces stay in sync.
enum ExifSummaryFormatting {
    static func apertureText(_ fNumber: Double) -> String {
        "ƒ/\(trimmedNumber(fNumber))"
    }

    static func shutterSpeedText(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0s" }
        guard seconds < 1 else {
            return "\(trimmedNumber(seconds))s"
        }
        let denominator = (1 / seconds).rounded()
        return "1/\(Int(denominator))s"
    }

    static func focalLengthText(_ millimeters: Double) -> String {
        "\(Int(millimeters.rounded()))mm"
    }

    private static func trimmedNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
