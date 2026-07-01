import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PreviewDimensions: Equatable, Sendable {
    public var width: Int
    public var height: Int
}

public struct PreviewRenderer: Sendable {
    public init() {}

    public func render(sourceURL: URL, level: PreviewLevel, destinationURL: URL) throws {
        guard let maxDimension = level.maxPixelDimension else {
            throw TeststripError.invalidState("original preview level is not rendered into cache")
        }
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw TeststripError.unsupportedFormat("could not read \(sourceURL.lastPathComponent)")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw TeststripError.unsupportedFormat("could not render preview for \(sourceURL.lastPathComponent)")
        }

        let destinationDirectory = destinationURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw TeststripError.io("could not create preview directory \(destinationDirectory.path): \(error.localizedDescription)")
        }
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TeststripError.io("could not create preview destination")
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write preview \(destinationURL.path)")
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
