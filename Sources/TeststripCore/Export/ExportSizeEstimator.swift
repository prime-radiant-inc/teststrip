import Foundation

/// A best-effort, sample-based estimate of an export's total output size.
/// Encoding every asset in a scope just to show a size preview would be far
/// too slow for large scopes, so this samples a handful of representative
/// assets, encodes only those, and extrapolates. It is explicitly an
/// estimate, not a guarantee — callers should label it as such in the UI.
public struct ExportSizeEstimate: Equatable, Sendable {
    public var estimatedTotalBytes: Int64
    public var sampledCount: Int
    public var totalAssetCount: Int

    public init(estimatedTotalBytes: Int64, sampledCount: Int, totalAssetCount: Int) {
        self.estimatedTotalBytes = estimatedTotalBytes
        self.sampledCount = sampledCount
        self.totalAssetCount = totalAssetCount
    }
}

public struct ExportSizeEstimator: Sendable {
    public init() {}

    /// Encodes up to `sampleCount` representative assets from `sampleURLs`
    /// at `settings` and extrapolates their average size across
    /// `totalAssetCount`. Returns `nil` when there's nothing to sample from,
    /// no assets to extrapolate to, or every sampled asset failed to encode
    /// (missing or undecodable).
    public func estimate(
        sampleURLs: [URL],
        settings: ExportSettings,
        totalAssetCount: Int,
        sampleCount: Int = 3
    ) -> ExportSizeEstimate? {
        guard totalAssetCount > 0, !sampleURLs.isEmpty else { return nil }
        let chosenURLs = Self.representativeSample(from: sampleURLs, count: sampleCount)
        let service = ExportService()
        let sampledSizes = chosenURLs.compactMap { service.estimatedEncodedByteCount(for: $0, settings: settings) }
        guard !sampledSizes.isEmpty else { return nil }
        let averageBytes = Double(sampledSizes.reduce(0, +)) / Double(sampledSizes.count)
        let estimatedTotalBytes = Int64((averageBytes * Double(totalAssetCount)).rounded())
        return ExportSizeEstimate(
            estimatedTotalBytes: estimatedTotalBytes,
            sampledCount: sampledSizes.count,
            totalAssetCount: totalAssetCount
        )
    }

    /// Picks `count` URLs evenly spaced across `urls` rather than just the
    /// first `count`, so the sample isn't skewed toward whatever a caller
    /// happened to load first (e.g. the front of an import batch).
    public static func representativeSample(from urls: [URL], count: Int) -> [URL] {
        guard count > 0 else { return [] }
        guard urls.count > count else { return urls }
        return (0..<count).map { urls[$0 * urls.count / count] }
    }
}
