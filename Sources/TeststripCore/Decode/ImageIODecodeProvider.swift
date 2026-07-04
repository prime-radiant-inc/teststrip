import Foundation
import ImageIO

public struct ImageIODecodeProvider: DecodeProvider {
    public let name = "ImageIO"

    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "tif", "tiff", "png",
        "dng", "crw", "cr2", "cr3", "nef", "arw", "raf", "rw2", "orf", "x3f"
    ]

    private let extensions = Self.supportedExtensions

    public init() {}

    public func canDecode(url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
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
        return (width, height)
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
