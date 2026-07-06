import Foundation

public struct ExportSettings: Hashable, Sendable {
    public var jpegQuality: Double
    public var longEdgeMaximumPixels: Int?

    public init(jpegQuality: Double, longEdgeMaximumPixels: Int? = nil) {
        self.jpegQuality = min(max(jpegQuality, 0), 1)
        self.longEdgeMaximumPixels = longEdgeMaximumPixels
    }
}

public struct ExportPreset: Hashable, Sendable {
    public var name: String
    public var settings: ExportSettings

    public init(name: String, settings: ExportSettings) {
        self.name = name
        self.settings = settings
    }

    public static let fullResolutionJPEG = ExportPreset(
        name: "Full-res JPEG",
        settings: ExportSettings(jpegQuality: 0.9)
    )

    public static let web2048 = ExportPreset(
        name: "Web 2048px",
        settings: ExportSettings(jpegQuality: 0.8, longEdgeMaximumPixels: 2048)
    )

    public static let all = [fullResolutionJPEG, web2048]
}
