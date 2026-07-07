import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ExportFormat: String, Hashable, Sendable, Codable, CaseIterable {
    case jpeg
    case png
}

public struct ExportSettings: Hashable, Sendable, Codable {
    public var format: ExportFormat
    public var jpegQuality: Double
    public var longEdgeMaximumPixels: Int?
    public var includeSourceMetadata: Bool
    /// When set, JPEG exports iteratively reduce quality (never below the
    /// requested `jpegQuality`) to fit this byte budget on a best-effort
    /// basis. Ignored for PNG, which has no comparable quality knob.
    public var targetFileSizeBytes: Int?

    public init(
        jpegQuality: Double,
        longEdgeMaximumPixels: Int? = nil,
        includeSourceMetadata: Bool = true,
        format: ExportFormat = .jpeg,
        targetFileSizeBytes: Int? = nil
    ) {
        self.format = format
        self.jpegQuality = min(max(jpegQuality, 0), 1)
        self.longEdgeMaximumPixels = longEdgeMaximumPixels
        self.includeSourceMetadata = includeSourceMetadata
        self.targetFileSizeBytes = targetFileSizeBytes
    }
}

public struct ExportPreset: Hashable, Sendable, Codable {
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

    // The design mock names this "Instagram 1080²" with a square crop, but
    // Teststrip never crops on export. This caps the long edge at 1080
    // instead — smaller than a true square crop would need, but honest
    // about what the export actually does to the frame.
    public static let instagramSquareCapped = ExportPreset(
        name: "Instagram 1080²",
        settings: ExportSettings(jpegQuality: 0.85, longEdgeMaximumPixels: 1080)
    )

    public static let print300dpi = ExportPreset(
        name: "Print 300dpi",
        settings: ExportSettings(jpegQuality: 0.95)
    )

    public static let email1MB = ExportPreset(
        name: "Email 1MB",
        settings: ExportSettings(jpegQuality: 0.85, targetFileSizeBytes: 1_000_000)
    )

    public static let all = [fullResolutionJPEG, web2048, instagramSquareCapped, print300dpi, email1MB]
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

    /// Returns the byte count of what exporting `sourceURL` at `settings`
    /// would produce, without writing anything to disk. Used by
    /// `ExportSizeEstimator` to sample a few representative assets and
    /// extrapolate a total-size estimate before the user commits to export.
    public func estimatedEncodedByteCount(for sourceURL: URL, settings: ExportSettings) -> Int64? {
        guard case .ready(let image, let destinationProperties) = decodeThumbnail(from: sourceURL, settings: settings) else {
            return nil
        }
        return encodedData(image: image, settings: settings, destinationProperties: destinationProperties).map { Int64($0.count) }
    }

    private func exportOutcome(
        sourceURL: URL,
        settings: ExportSettings,
        destinationDirectory: URL,
        claimedFilenames: inout Set<String>
    ) -> ExportOutcome {
        switch decodeThumbnail(from: sourceURL, settings: settings) {
        case .unavailable:
            return .skippedUnavailable
        case .unreadable:
            return .failed(message: "could not read \(sourceURL.lastPathComponent)")
        case .undecodable:
            return .failed(message: "could not decode \(sourceURL.lastPathComponent)")
        case .ready(let image, let destinationProperties):
            let destinationURL = availableDestinationURL(
                for: sourceURL,
                destinationDirectory: destinationDirectory,
                format: settings.format,
                claimedFilenames: &claimedFilenames
            )
            guard let data = encodedData(image: image, settings: settings, destinationProperties: destinationProperties) else {
                return .failed(message: "could not create \(destinationURL.lastPathComponent)")
            }
            do {
                try data.write(to: destinationURL)
            } catch {
                return .failed(message: "could not write \(destinationURL.lastPathComponent): \(error.localizedDescription)")
            }
            return .exported(destinationURL: destinationURL)
        }
    }

    private enum DecodedThumbnail {
        case unavailable
        case unreadable
        case undecodable
        case ready(image: CGImage, destinationProperties: [CFString: Any])
    }

    private func decodeThumbnail(from sourceURL: URL, settings: ExportSettings) -> DecodedThumbnail {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .unavailable
        }
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            return .unreadable
        }
        var thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if let longEdgeMaximumPixels = settings.longEdgeMaximumPixels {
            thumbnailOptions[kCGImageSourceThumbnailMaxPixelSize] = longEdgeMaximumPixels
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return .undecodable
        }
        let destinationProperties: [CFString: Any] = settings.includeSourceMetadata
            ? carriedSourceProperties(from: source)
            : [:]
        return .ready(image: image, destinationProperties: destinationProperties)
    }

    private func encodedData(image: CGImage, settings: ExportSettings, destinationProperties: [CFString: Any]) -> Data? {
        switch settings.format {
        case .jpeg:
            return jpegData(for: image, settings: settings, destinationProperties: destinationProperties)
        case .png:
            return encodedPNGData(image: image, properties: destinationProperties)
        }
    }

    private func encodedPNGData(image: CGImage, properties: [CFString: Any]) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, ExportFormat.png.utType.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return mutableData as Data
    }

    /// Encodes a JPEG at `settings.jpegQuality`, then — only when
    /// `targetFileSizeBytes` is set and that initial encode is too large —
    /// binary-searches quality downward to fit the budget. Never fails the
    /// export just because the budget is unreachable: it returns the
    /// smallest encoding it found (best effort).
    private func jpegData(
        for image: CGImage,
        settings: ExportSettings,
        destinationProperties: [CFString: Any]
    ) -> Data? {
        guard let initialData = encodedJPEGData(image: image, quality: settings.jpegQuality, properties: destinationProperties) else {
            return nil
        }
        guard let targetByteBudget = settings.targetFileSizeBytes, initialData.count > targetByteBudget else {
            return initialData
        }
        var lowQuality = 0.0
        var highQuality = settings.jpegQuality
        var bestFit: Data?
        var smallestSeen = initialData
        for _ in 0..<Self.qualitySteppingMaxIterations {
            let midQuality = (lowQuality + highQuality) / 2
            guard let midData = encodedJPEGData(image: image, quality: midQuality, properties: destinationProperties) else {
                break
            }
            if midData.count < smallestSeen.count {
                smallestSeen = midData
            }
            if midData.count <= targetByteBudget {
                bestFit = midData
                lowQuality = midQuality
            } else {
                highQuality = midQuality
            }
        }
        return bestFit ?? smallestSeen
    }

    private func encodedJPEGData(image: CGImage, quality: Double, properties: [CFString: Any]) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, ExportFormat.jpeg.utType.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties = properties
        properties[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return mutableData as Data
    }

    private static let qualitySteppingMaxIterations = 8

    private func carriedSourceProperties(from source: CGImageSource) -> [CFString: Any] {
        guard var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return [:]
        }
        // The thumbnail render bakes the source orientation into the pixels,
        // so carried metadata must say "up" or consumers would rotate twice.
        properties[kCGImagePropertyOrientation] = 1
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        // Resizing changes pixel dimensions; the destination derives them from
        // the written image instead of stale source values.
        properties.removeValue(forKey: kCGImagePropertyPixelWidth)
        properties.removeValue(forKey: kCGImagePropertyPixelHeight)
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
            properties[kCGImagePropertyExifDictionary] = exif
        }
        return properties
    }

    private func availableDestinationURL(
        for sourceURL: URL,
        destinationDirectory: URL,
        format: ExportFormat,
        claimedFilenames: inout Set<String>
    ) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let extensionSuffix = format.fileExtension
        var candidateName = "\(baseName).\(extensionSuffix)"
        var suffix = 2
        while claimedFilenames.contains(candidateName.lowercased())
            || FileManager.default.fileExists(atPath: destinationDirectory.appendingPathComponent(candidateName).path) {
            candidateName = "\(baseName)-\(suffix).\(extensionSuffix)"
            suffix += 1
        }
        claimedFilenames.insert(candidateName.lowercased())
        return destinationDirectory.appendingPathComponent(candidateName)
    }
}

private extension ExportFormat {
    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }
}
