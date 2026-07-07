import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import TeststripCore

extension Bundle {
    /// The downloaded astronaut face corpus directory, or nil when it has not
    /// been fetched (see script/build_and_run.sh --faces).
    static func faceCorpusDirectory() -> URL? {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("sample-data/photos/faces")
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// The first jpg in the downloaded face corpus, or nil when absent.
    static func faceCorpusImageURL() -> URL? {
        guard let dir = faceCorpusDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        return files.filter { $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }
}

enum TestDirectories {
    static func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func writeTestJPEG(to url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TeststripError.io("could not create test bitmap context")
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TeststripError.io("could not create test jpeg")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write test jpeg")
        }
    }

    /// Writes a JPEG carrying GPS EXIF for the given coordinate, so backfill /
    /// GPS-extraction tests can re-read real coordinates from a real file.
    static func writeTestJPEGWithGPS(
        to url: URL,
        width: Int = 8,
        height: Int = 8,
        latitude: Double,
        longitude: Double
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TeststripError.io("could not create GPS test bitmap context")
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TeststripError.io("could not create GPS test jpeg")
        }
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: abs(latitude),
            kCGImagePropertyGPSLatitudeRef: latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude: abs(longitude),
            kCGImagePropertyGPSLongitudeRef: longitude >= 0 ? "E" : "W"
        ]
        let properties: [CFString: Any] = [kCGImagePropertyGPSDictionary: gps]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write GPS test jpeg")
        }
    }

    /// Writes a JPEG filled with deterministic pseudo-random noise instead of
    /// a flat color. Flat-color JPEGs barely shrink across quality settings
    /// (a solid fill compresses to nearly nothing regardless of quality), so
    /// byte-budget quality-stepping tests need this noisier fixture to see a
    /// real, reproducible size difference between quality levels.
    static func writeNoisyTestJPEG(to url: URL, width: Int, height: Int, seed: UInt64 = 1) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let buffer = context.data else {
            throw TeststripError.io("could not create noisy test bitmap context")
        }
        var state: UInt64 = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        let byteCount = context.bytesPerRow * height
        let pointer = buffer.bindMemory(to: UInt8.self, capacity: byteCount)
        for index in 0..<byteCount {
            // xorshift64* — a small, deterministic PRNG so noisy fixtures are reproducible across runs.
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            let scrambled = state &* 0x2545_F491_4F6C_DD1D
            pointer[index] = UInt8(truncatingIfNeeded: scrambled >> 24)
        }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TeststripError.io("could not create noisy test jpeg")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write noisy test jpeg")
        }
    }
}
