import Foundation

public struct SamplePreviewRenderBenchmarkResult: Equatable {
    public var sourceImageCount: Int
    public var catalogAssetCount: Int
    public var cachedPreviewCount: Int

    public init(sourceImageCount: Int, catalogAssetCount: Int, cachedPreviewCount: Int) {
        self.sourceImageCount = sourceImageCount
        self.catalogAssetCount = catalogAssetCount
        self.cachedPreviewCount = cachedPreviewCount
    }
}

public struct SamplePreviewRenderBenchmark {
    public var root: URL
    public var photoDirectory: URL

    public init(root: URL, photoDirectory: URL) {
        self.root = root
        self.photoDirectory = photoDirectory
    }

    public func run() throws -> SamplePreviewRenderBenchmarkResult {
        let result = try SampleCatalogSeeder(
            applicationSupportDirectory: root,
            photoDirectory: photoDirectory
        ).run()
        return SamplePreviewRenderBenchmarkResult(
            sourceImageCount: result.sourceImageCount,
            catalogAssetCount: result.assetCount,
            cachedPreviewCount: result.cachedPreviewCount
        )
    }
}
