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

    public func renderLevels(
        fromLocalSource sourceURL: URL,
        levels: [PreviewLevel],
        destinationProvider: (PreviewLevel) -> URL
    ) throws {
        // Deduplicate by physical file. For each file, always render at the
        // highest maxPixelDimension among ALL co-located levels — not just
        // the ones in the input array — so the file is at full resolution
        // for every level it serves. E.g. if only .medium (1600px) is
        // requested, large.heic is still rendered at .large's 3200px so
        // .large is not starved when its queue entry is cleared.
        var seen = Set<String>()
        for level in levels {
            let file = PreviewCache.physicalFile(for: level)
            if seen.contains(file) { continue }
            seen.insert(file)
            let renderLevel = PreviewLevel.allCases
                .filter { PreviewCache.physicalFile(for: $0) == file }
                .max { Self.maxDimensionRank($0) < Self.maxDimensionRank($1) }!
            try render(
                sourceURL: sourceURL,
                level: renderLevel,
                destinationURL: destinationProvider(renderLevel)
            )
        }
    }

    /// Higher = larger maxPixelDimension. `.original` (nil) ranks highest.
    private static func maxDimensionRank(_ level: PreviewLevel) -> Int {
        level.maxPixelDimension ?? Int.max
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
