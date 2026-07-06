import Foundation
import TeststripCore

public struct OfflineReconnectSmokeResult: Equatable {
    public var catalogAssetCount: Int
    public var cachedPreviewReadableBeforeReconnect: Bool
    public var cachedPreviewReadableAfterReconnect: Bool
    public var reconnectedAssetCount: Int
    public var onlineAssetCountAfterReconnect: Int
    public var sidecarPathUpdatedCount: Int
    public var unchangedOriginalCount: Int
    public var unchangedSidecarCount: Int
}

public struct OfflineReconnectSmoke {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public func run() throws -> OfflineReconnectSmokeResult {
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let sidecarStore = XMPSidecarStore()

        let oldRoot = root.appendingPathComponent("OfflineArchive", isDirectory: true)
        let newRoot = root.appendingPathComponent("MountedArchive", isDirectory: true)
        let newOriginalURL = newRoot.appendingPathComponent("Job/frame.dng")
        try FileManager.default.createDirectory(
            at: newOriginalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let originalData = Data("offline reconnect smoke original".utf8)
        try originalData.write(to: newOriginalURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_783_024_800)],
            ofItemAtPath: newOriginalURL.path
        )

        let newSidecarURL = newOriginalURL.deletingPathExtension().appendingPathExtension("xmp")
        let sidecarData = Data("offline reconnect smoke sidecar".utf8)
        try sidecarData.write(to: newSidecarURL)

        let assetID = AssetID(rawValue: "offline-reconnect-frame")
        let oldOriginalURL = oldRoot.appendingPathComponent("Job/frame.dng")
        let oldSidecarURL = oldOriginalURL.deletingPathExtension().appendingPathExtension("xmp")
        let asset = Asset(
            id: assetID,
            originalURL: oldOriginalURL,
            volumeIdentifier: "OfflineArchive",
            fingerprint: try Self.fileFingerprint(for: newOriginalURL),
            availability: .missing,
            metadata: AssetMetadata(rating: 4)
        )
        try repository.upsert(asset)
        try repository.markMetadataSynced(
            assetID: asset.id,
            sidecarURL: oldSidecarURL,
            catalogGeneration: try repository.catalogGeneration(assetID: asset.id),
            fingerprint: XMPSidecarStore.fingerprint(for: sidecarData)
        )

        let previewData = Data("cached preview".utf8)
        let previewURL = PreviewCache(root: root.appendingPathComponent("Previews", isDirectory: true))
            .url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try FileManager.default.createDirectory(
            at: previewURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try previewData.write(to: previewURL)
        let cachedPreviewReadableBeforeReconnect = (try? Data(contentsOf: previewURL)) == previewData

        let reconnect = try repository.reconnectSourceRoot(from: oldRoot, to: newRoot)
        let reconnectedAsset = try repository.asset(id: asset.id)
        let syncItem = try repository.metadataSyncItem(assetID: asset.id)

        let cachedPreviewReadableAfterReconnect = (try? Data(contentsOf: previewURL)) == previewData
        let currentSidecarURL = sidecarStore.sidecarURL(forOriginalAt: reconnectedAsset.originalURL)

        return OfflineReconnectSmokeResult(
            catalogAssetCount: try repository.assetCount(),
            cachedPreviewReadableBeforeReconnect: cachedPreviewReadableBeforeReconnect,
            cachedPreviewReadableAfterReconnect: cachedPreviewReadableAfterReconnect,
            reconnectedAssetCount: reconnect.reconnectedAssetCount,
            onlineAssetCountAfterReconnect: try repository.assetCount(matching: SetQuery(predicates: [.availability(.online)])),
            sidecarPathUpdatedCount: syncItem?.sidecarURL == currentSidecarURL ? 1 : 0,
            unchangedOriginalCount: ((try? Data(contentsOf: newOriginalURL)) == originalData) ? 1 : 0,
            unchangedSidecarCount: ((try? Data(contentsOf: newSidecarURL)) == sidecarData) ? 1 : 0
        )
    }

    private static func fileFingerprint(for url: URL) throws -> FileFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileFingerprint(
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        )
    }
}
