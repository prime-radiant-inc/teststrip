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
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return DecodeMetadata(
            pixelWidth: width,
            pixelHeight: height,
            provenance: ProviderProvenance(provider: name, model: "ImageIO", version: "1", settingsHash: "default")
        )
    }
}
