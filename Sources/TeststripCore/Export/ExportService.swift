import Foundation
import ImageIO
import UniformTypeIdentifiers

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

public enum ExportOutcome: Equatable, Sendable {
    case exported(destinationURL: URL)
    case skippedUnavailable
    case failed(message: String)
}

public struct ExportFileResult: Equatable, Sendable {
    public var sourceURL: URL
    public var outcome: ExportOutcome

    public init(sourceURL: URL, outcome: ExportOutcome) {
        self.sourceURL = sourceURL
        self.outcome = outcome
    }
}

public typealias ExportProgressHandler = @Sendable (_ completedCount: Int, _ totalCount: Int) -> Void

public struct ExportService: Sendable {
    public init() {}

    public func export(
        originalURLs: [URL],
        settings: ExportSettings,
        destinationDirectory: URL,
        progress: ExportProgressHandler? = nil
    ) throws -> [ExportFileResult] {
        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw TeststripError.io("could not create export destination \(destinationDirectory.path): \(error.localizedDescription)")
        }
        var claimedFilenames: Set<String> = []
        var results: [ExportFileResult] = []
        for (index, sourceURL) in originalURLs.enumerated() {
            progress?(index + 1, originalURLs.count)
            results.append(ExportFileResult(
                sourceURL: sourceURL,
                outcome: exportOutcome(
                    sourceURL: sourceURL,
                    settings: settings,
                    destinationDirectory: destinationDirectory,
                    claimedFilenames: &claimedFilenames
                )
            ))
        }
        return results
    }

    private func exportOutcome(
        sourceURL: URL,
        settings: ExportSettings,
        destinationDirectory: URL,
        claimedFilenames: inout Set<String>
    ) -> ExportOutcome {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .skippedUnavailable
        }
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            return .failed(message: "could not read \(sourceURL.lastPathComponent)")
        }
        var thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if let longEdgeMaximumPixels = settings.longEdgeMaximumPixels {
            thumbnailOptions[kCGImageSourceThumbnailMaxPixelSize] = longEdgeMaximumPixels
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return .failed(message: "could not decode \(sourceURL.lastPathComponent)")
        }
        let destinationURL = availableDestinationURL(
            for: sourceURL,
            destinationDirectory: destinationDirectory,
            claimedFilenames: &claimedFilenames
        )
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return .failed(message: "could not create \(destinationURL.lastPathComponent)")
        }
        let destinationProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: settings.jpegQuality
        ]
        CGImageDestinationAddImage(destination, image, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return .failed(message: "could not write \(destinationURL.lastPathComponent)")
        }
        return .exported(destinationURL: destinationURL)
    }

    private func availableDestinationURL(
        for sourceURL: URL,
        destinationDirectory: URL,
        claimedFilenames: inout Set<String>
    ) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var candidateName = "\(baseName).jpg"
        var suffix = 2
        while claimedFilenames.contains(candidateName.lowercased())
            || FileManager.default.fileExists(atPath: destinationDirectory.appendingPathComponent(candidateName).path) {
            candidateName = "\(baseName)-\(suffix).jpg"
            suffix += 1
        }
        claimedFilenames.insert(candidateName.lowercased())
        return destinationDirectory.appendingPathComponent(candidateName)
    }
}
