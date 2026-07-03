import CoreGraphics
import Foundation
import ImageIO
import TeststripCore
import UniformTypeIdentifiers

public struct PreviewRenderBenchmarkResult: Equatable {
    public var sourceImageCount: Int
    public var renderedPreviewCount: Int
    public var cachedPreviewCount: Int

    public init(sourceImageCount: Int, renderedPreviewCount: Int, cachedPreviewCount: Int) {
        self.sourceImageCount = sourceImageCount
        self.renderedPreviewCount = renderedPreviewCount
        self.cachedPreviewCount = cachedPreviewCount
    }
}

public struct PreviewRenderBenchmark {
    public var count: Int
    public var root: URL

    private let renderedLevels: [PreviewLevel] = [.micro, .grid, .medium, .large]

    public init(count: Int, root: URL) {
        self.count = count
        self.root = root
    }

    public func run() throws -> PreviewRenderBenchmarkResult {
        let sourceRoot = root.appendingPathComponent("sources", isDirectory: true)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        let renderer = PreviewRenderer()
        var renderedPreviewCount = 0

        for index in 0..<count {
            let assetID = AssetID(rawValue: "preview-\(index)")
            let sourceURL = sourceRoot.appendingPathComponent("\(assetID.rawValue).jpg")
            try Self.writeBenchmarkJPEG(to: sourceURL, index: index)

            for level in renderedLevels {
                let destinationURL = previewCache.url(for: PreviewCacheKey(assetID: assetID, level: level))
                try renderer.render(sourceURL: sourceURL, level: level, destinationURL: destinationURL)
                renderedPreviewCount += 1
            }
        }

        return PreviewRenderBenchmarkResult(
            sourceImageCount: count,
            renderedPreviewCount: renderedPreviewCount,
            cachedPreviewCount: try cachedPreviewCount(root: previewCache.root)
        )
    }

    private static func writeBenchmarkJPEG(to url: URL, index: Int) throws {
        let width = 1200
        let height = 800
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TeststripError.io("could not create benchmark bitmap context")
        }
        let red = CGFloat((index % 5) + 1) / 5.0
        let green = CGFloat((index % 7) + 1) / 7.0
        let blue = CGFloat((index % 11) + 1) / 11.0
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TeststripError.io("could not create benchmark jpeg")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write benchmark jpeg")
        }
    }

    private func cachedPreviewCount(root: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try urls.reduce(0) { count, assetDirectory in
            count + (try FileManager.default.contentsOfDirectory(
                at: assetDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "jpg" }.count)
        }
    }
}
