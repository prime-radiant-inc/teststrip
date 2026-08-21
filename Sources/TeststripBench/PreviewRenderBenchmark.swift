import Foundation
import TeststripCore

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

    private let renderedLevels: [PreviewLevel] = [.grid, .large]

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
            try BenchmarkImageFixtures.writeJPEG(to: sourceURL, index: index)

            try renderer.renderLevels(
                fromLocalSource: sourceURL,
                levels: renderedLevels,
                destinationProvider: { level in
                    previewCache.url(for: PreviewCacheKey(assetID: assetID, level: level))
                }
            )
            renderedPreviewCount += renderedLevels.count
        }

        return PreviewRenderBenchmarkResult(
            sourceImageCount: count,
            renderedPreviewCount: renderedPreviewCount,
            cachedPreviewCount: try PreviewCacheFileCounter.count(root: previewCache.root)
        )
    }
}
