import Foundation
import ImageIO

public struct ImageIODecodeProvider: DecodeProvider {
    public let name = "ImageIO"

    public static let workingStillExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "tif", "tiff", "png"
    ]

    public static let bestEffortRawExtensions: Set<String> = [
        "dng", "crw", "cr2", "cr3", "nef", "arw", "raf", "rwl", "rw2", "srw", "orf"
    ]

    public static let knownUnsupportedRawExtensions: Set<String> = [
        "x3f"
    ]

    public static let supportedExtensions: Set<String> = [
        workingStillExtensions,
        bestEffortRawExtensions
    ].reduce(into: Set<String>()) { result, extensions in
        result.formUnion(extensions)
    }

    public static let catalogableExtensions: Set<String> = [
        supportedExtensions,
        knownUnsupportedRawExtensions
    ].reduce(into: Set<String>()) { result, extensions in
        result.formUnion(extensions)
    }

    private let extensions = Self.supportedExtensions

    public init() {}

    public func canDecode(url: URL) -> Bool {
        capability(forFileExtension: url.pathExtension)?.support != .unsupported
    }

    public func canCatalog(url: URL) -> Bool {
        Self.catalogableExtensions.contains(url.pathExtension.lowercased())
    }

    public func capability(forFileExtension fileExtension: String) -> DecodeCapability? {
        let normalizedExtension = fileExtension.lowercased()
        if Self.workingStillExtensions.contains(normalizedExtension) {
            return DecodeCapability(
                providerName: name,
                fileExtension: normalizedExtension,
                support: .working,
                canReadMetadata: true,
                canUseEmbeddedPreview: false,
                canRenderPreview: true,
                canRenderFullImage: true,
                note: "ImageIO supports this still-image format for metadata and preview rendering."
            )
        }
        if extensions.contains(normalizedExtension) {
            return DecodeCapability(
                providerName: name,
                fileExtension: normalizedExtension,
                support: .bestEffort,
                canReadMetadata: true,
                canUseEmbeddedPreview: true,
                canRenderPreview: true,
                canRenderFullImage: false,
                note: "ImageIO RAW support is OS and camera dependent; Teststrip catalogs the file and attempts cached previews without promising full RAW decode."
            )
        }
        if Self.knownUnsupportedRawExtensions.contains(normalizedExtension) {
            return DecodeCapability(
                providerName: name,
                fileExtension: normalizedExtension,
                support: .unsupported,
                canReadMetadata: false,
                canUseEmbeddedPreview: false,
                canRenderPreview: false,
                canRenderFullImage: false,
                note: "Sigma/Foveon X3F is recognized as a RAW family but needs a future non-ImageIO decode provider."
            )
        }
        return DecodeCapability(
            providerName: name,
            fileExtension: normalizedExtension,
            support: .unsupported,
            canReadMetadata: false,
            canUseEmbeddedPreview: false,
            canRenderPreview: false,
            canRenderFullImage: false,
            note: "ImageIO is not registered for this extension."
        )
    }

    public func metadata(for url: URL) throws -> DecodeMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw TeststripError.unsupportedFormat("ImageIO could not read \(url.lastPathComponent)")
        }
        return try Self.metadata(
            from: properties,
            provenance: ProviderProvenance(provider: name, model: "ImageIO", version: "1", settingsHash: "default"),
            filename: url.lastPathComponent
        )
    }

    static func metadata(
        from properties: [CFString: Any],
        provenance: ProviderProvenance,
        filename: String
    ) throws -> DecodeMetadata {
        let dimensions = try dimensions(from: properties, filename: filename)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        return DecodeMetadata(
            pixelWidth: dimensions.pixelWidth,
            pixelHeight: dimensions.pixelHeight,
            cameraMake: stringValue(tiff[kCGImagePropertyTIFFMake]),
            cameraModel: stringValue(tiff[kCGImagePropertyTIFFModel]),
            lensModel: stringValue(exif[kCGImagePropertyExifLensModel]),
            isoSpeed: isoSpeed(from: exif[kCGImagePropertyExifISOSpeedRatings]),
            capturedAt: capturedAt(from: exif[kCGImagePropertyExifDateTimeOriginal])
                ?? capturedAt(from: tiff[kCGImagePropertyTIFFDateTime]),
            provenance: provenance
        )
    }

    static func dimensions(from properties: [CFString: Any], filename: String) throws -> (pixelWidth: Int, pixelHeight: Int) {
        guard let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0 else {
            throw TeststripError.unsupportedFormat("ImageIO could not read dimensions for \(filename)")
        }
        if orientationRotatesDisplayBounds(properties[kCGImagePropertyOrientation]) {
            return (height, width)
        }
        return (width, height)
    }

    private static func orientationRotatesDisplayBounds(_ value: Any?) -> Bool {
        let orientation: Int?
        if let value = value as? NSNumber {
            orientation = value.intValue
        } else {
            orientation = value as? Int
        }
        guard let orientation else { return false }
        return [5, 6, 7, 8].contains(orientation)
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isoSpeed(from value: Any?) -> Int? {
        if let values = value as? [Int] {
            return values.first
        }
        if let values = value as? [NSNumber] {
            return values.first?.intValue
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func capturedAt(from value: Any?) -> Date? {
        guard let string = stringValue(value) else { return nil }
        let parts = string.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let dateParts = parts[0].split(separator: ":").compactMap { Int($0) }
        let timeParts = parts[1].split(separator: ":").compactMap { Int($0) }
        guard dateParts.count == 3, timeParts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = dateParts[0]
        components.month = dateParts[1]
        components.day = dateParts[2]
        components.hour = timeParts[0]
        components.minute = timeParts[1]
        components.second = timeParts[2]
        return components.date
    }
}
