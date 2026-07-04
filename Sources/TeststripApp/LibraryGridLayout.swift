import CoreGraphics
import Foundation

struct LibraryGridLayout: Equatable {
    static let minimumThumbnailWidth: Double = 96
    static let defaultThumbnailWidth: Double = 140
    static let maximumThumbnailWidth: Double = 260

    var thumbnailWidth: Double

    init(thumbnailWidth: Double) {
        self.thumbnailWidth = Self.clampedThumbnailWidth(thumbnailWidth)
    }

    var gridItemMinimumWidth: CGFloat {
        CGFloat(thumbnailWidth)
    }

    var densityLabel: String {
        switch thumbnailWidth {
        case ..<120:
            "Compact"
        case 200...:
            "Large"
        default:
            "Comfortable"
        }
    }

    var accessibilityValue: String {
        "\(Int(thumbnailWidth.rounded())) px, \(densityLabel)"
    }

    static func clampedThumbnailWidth(_ value: Double) -> Double {
        min(max(value, minimumThumbnailWidth), maximumThumbnailWidth)
    }
}
