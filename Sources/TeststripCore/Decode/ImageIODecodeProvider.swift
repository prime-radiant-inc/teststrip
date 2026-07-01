import Foundation
import ImageIO

public struct ImageIODecodeProvider: DecodeProvider {
    public let name = "ImageIO"

    private let extensions: Set<String> = [
        "jpg", "jpeg", "heic", "tif", "tiff", "png",
        "dng", "cr2", "cr3", "nef", "arw", "raf", "rw2", "orf"
    ]

    public init() {}

    public func canDecode(url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    public func metadata(for url: URL) throws -> DecodeMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw TeststripError.unsupportedFormat("ImageIO could not read \(url.lastPathComponent)")
        }
        let dimensions = try Self.dimensions(from: properties, filename: url.lastPathComponent)
        return DecodeMetadata(
            pixelWidth: dimensions.pixelWidth,
            pixelHeight: dimensions.pixelHeight,
            provenance: ProviderProvenance(provider: name, model: "ImageIO", version: "1", settingsHash: "default")
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
}
