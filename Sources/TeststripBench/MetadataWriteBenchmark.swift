import Foundation
import TeststripCore

public struct MetadataWriteBenchmarkResult: Equatable {
    public var updatedAssetCount: Int
    public var catalogAssetCount: Int
    public var sidecarCount: Int
    public var matchingSidecarMetadataCount: Int
    public var syncedFingerprintCount: Int
    public var pendingSyncCount: Int
    public var unchangedOriginalCount: Int

    public init(
        updatedAssetCount: Int,
        catalogAssetCount: Int,
        sidecarCount: Int,
        matchingSidecarMetadataCount: Int,
        syncedFingerprintCount: Int,
        pendingSyncCount: Int,
        unchangedOriginalCount: Int
    ) {
        self.updatedAssetCount = updatedAssetCount
        self.catalogAssetCount = catalogAssetCount
        self.sidecarCount = sidecarCount
        self.matchingSidecarMetadataCount = matchingSidecarMetadataCount
        self.syncedFingerprintCount = syncedFingerprintCount
        self.pendingSyncCount = pendingSyncCount
        self.unchangedOriginalCount = unchangedOriginalCount
    }
}

public struct MetadataWriteBenchmark {
    public var count: Int
    public var root: URL

    public init(count: Int, root: URL) {
        self.count = count
        self.root = root
    }

    public func run() throws -> MetadataWriteBenchmarkResult {
        let photoRoot = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoRoot, withIntermediateDirectories: true)

        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let sidecarStore = XMPSidecarStore()
        let assets = try seedAssets(photoRoot: photoRoot, repository: repository)
        var updatedAssetCount = 0

        for (index, asset) in assets.enumerated() {
            try repository.updateMetadata(assetID: asset.id) { metadata in
                metadata = Self.metadata(for: index)
            }
            let catalogGeneration = try repository.catalogGeneration(assetID: asset.id)
            let updatedAsset = try repository.asset(id: asset.id)
            let write = try sidecarStore.write(metadata: updatedAsset.metadata, forOriginalAt: updatedAsset.originalURL)
            try repository.markMetadataSynced(
                assetID: asset.id,
                sidecarURL: write.sidecarURL,
                catalogGeneration: catalogGeneration,
                fingerprint: write.fingerprint
            )
            updatedAssetCount += 1
        }

        return MetadataWriteBenchmarkResult(
            updatedAssetCount: updatedAssetCount,
            catalogAssetCount: try repository.assetCount(),
            sidecarCount: sidecarCount(for: assets, sidecarStore: sidecarStore),
            matchingSidecarMetadataCount: try matchingSidecarMetadataCount(for: assets, repository: repository, sidecarStore: sidecarStore),
            syncedFingerprintCount: try syncedFingerprintCount(for: assets, repository: repository),
            pendingSyncCount: try repository.pendingMetadataSyncItems().count,
            unchangedOriginalCount: try unchangedOriginalCount(for: assets)
        )
    }

    private func seedAssets(photoRoot: URL, repository: CatalogRepository) throws -> [Asset] {
        let assets = try (0..<count).map { index in
            let originalURL = photoRoot.appendingPathComponent("image-\(index).jpg")
            try Self.originalData(for: index).write(to: originalURL)
            return Asset(
                id: AssetID(rawValue: "metadata-write-\(index)"),
                originalURL: originalURL,
                volumeIdentifier: "local",
                fingerprint: try Self.fileFingerprint(for: originalURL),
                availability: .online,
                metadata: AssetMetadata()
            )
        }
        try repository.upsert(assets)
        return assets
    }

    private static func metadata(for index: Int) -> AssetMetadata {
        AssetMetadata(
            rating: index % 6,
            colorLabel: ColorLabel.allCases[index % ColorLabel.allCases.count],
            flag: index.isMultiple(of: 2) ? .pick : .reject,
            keywords: ["bench", "asset-\(index)"],
            caption: "Benchmark caption \(index)",
            creator: "TeststripBench",
            copyright: "Copyright TeststripBench"
        )
    }

    private func sidecarCount(for assets: [Asset], sidecarStore: XMPSidecarStore) -> Int {
        assets.reduce(into: 0) { count, asset in
            if FileManager.default.fileExists(atPath: sidecarStore.sidecarURL(forOriginalAt: asset.originalURL).path) {
                count += 1
            }
        }
    }

    private func matchingSidecarMetadataCount(for assets: [Asset], repository: CatalogRepository, sidecarStore: XMPSidecarStore) throws -> Int {
        try assets.reduce(into: 0) { count, asset in
            let sidecarURL = sidecarStore.sidecarURL(forOriginalAt: asset.originalURL)
            guard FileManager.default.fileExists(atPath: sidecarURL.path) else { return }
            let sidecarMetadata = try XMPPacket.parse(Data(contentsOf: sidecarURL)).metadata
            let catalogMetadata = try repository.asset(id: asset.id).metadata
            if sidecarMetadata == catalogMetadata {
                count += 1
            }
        }
    }

    private func syncedFingerprintCount(for assets: [Asset], repository: CatalogRepository) throws -> Int {
        try assets.reduce(into: 0) { count, asset in
            if try repository.lastMetadataSyncFingerprint(assetID: asset.id) != nil {
                count += 1
            }
        }
    }

    private func unchangedOriginalCount(for assets: [Asset]) throws -> Int {
        try assets.enumerated().reduce(into: 0) { count, pair in
            let (index, asset) = pair
            if try Data(contentsOf: asset.originalURL) == Self.originalData(for: index) {
                count += 1
            }
        }
    }

    private static func originalData(for index: Int) -> Data {
        Data("jpg-\(index)".utf8)
    }

    private static func fileFingerprint(for url: URL) throws -> FileFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileFingerprint(
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        )
    }
}
