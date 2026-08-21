import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PreviewDimensions: Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct PreviewRenderer: Sendable {
    public init() {}

    public func render(sourceURL: URL, level: PreviewLevel, destinationURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw TeststripError.unsupportedFormat("could not read \(sourceURL.lastPathComponent)")
        }
        // Levels without a pixel bound (.original) decode at the source's full
        // resolution so the loupe's 1:1 pixel zoom has real pixels to show.
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false
        ]
        if let maxDimension = level.maxPixelDimension {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxDimension
        }
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw TeststripError.unsupportedFormat("could not render preview for \(sourceURL.lastPathComponent)")
        }

        let destinationDirectory = destinationURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw TeststripError.io("could not create preview directory \(destinationDirectory.path): \(error.localizedDescription)")
        }
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType("public.heic")!.identifier as CFString,
            1,
            nil
        ) else {
            throw TeststripError.io("could not create HEIC preview destination")
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: Self.compressionQuality(for: level)
        ]
        CGImageDestinationAddImage(destination, thumbnail, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write preview \(destinationURL.path)")
        }
    }

    private static func compressionQuality(for level: PreviewLevel) -> Double {
        switch level {
        case .micro, .grid:   return 0.82
        case .medium, .large: return 0.40
        case .original:       return 0.25
        }
    }

    private static func physicalFile(for level: PreviewLevel) -> String {
        switch level {
        case .micro, .grid:   return "grid.heic"
        case .medium, .large: return "large.heic"
        case .original:       return "full.heic"
        }
    }

    public func renderLevels(
        fromLocalSource sourceURL: URL,
        levels: [PreviewLevel],
        destinationProvider: (PreviewLevel) -> URL
    ) throws {
        var seen = Set<String>()
        var toRender: [PreviewLevel] = []
        for level in levels {
            let file = Self.physicalFile(for: level)
            if !seen.contains(file) {
                seen.insert(file)
                toRender.append(level)
            }
        }
        for level in toRender {
            try render(
                sourceURL: sourceURL,
                level: level,
                destinationURL: destinationProvider(level)
            )
        }
    }

    public func dimensions(of url: URL) throws -> PreviewDimensions {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw TeststripError.unsupportedFormat("could not inspect \(url.lastPathComponent)")
        }
        return PreviewDimensions(width: width, height: height)
    }
}
