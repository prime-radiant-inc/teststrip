import Foundation
import TeststripCore

public struct RealCorpusSmokeResult: Equatable {
    public var candidatePhotoCount: Int
    public var selectedPhotoCount: Int
    public var importedAssetCount: Int
    public var catalogAssetCount: Int
    public var workingStillCount: Int
    public var bestEffortRawCount: Int
    public var unsupportedCount: Int
    public var previewEligibleCount: Int
    public var pendingPreviewCount: Int
    public var fullImageDecodeCount: Int
    public var adjacentSidecarCount: Int
    public var importedSidecarSyncCount: Int
    public var adjacentSidecarNotImportedCount: Int
    public var unchangedOriginalCount: Int
    public var unchangedSidecarCount: Int
    public var selectedExtensions: [String: Int]

    public init(
        candidatePhotoCount: Int,
        selectedPhotoCount: Int,
        importedAssetCount: Int,
        catalogAssetCount: Int,
        workingStillCount: Int,
        bestEffortRawCount: Int,
        unsupportedCount: Int,
        previewEligibleCount: Int,
        pendingPreviewCount: Int,
        fullImageDecodeCount: Int,
        adjacentSidecarCount: Int,
        importedSidecarSyncCount: Int,
        adjacentSidecarNotImportedCount: Int,
        unchangedOriginalCount: Int,
        unchangedSidecarCount: Int,
        selectedExtensions: [String: Int]
    ) {
        self.candidatePhotoCount = candidatePhotoCount
        self.selectedPhotoCount = selectedPhotoCount
        self.importedAssetCount = importedAssetCount
        self.catalogAssetCount = catalogAssetCount
        self.workingStillCount = workingStillCount
        self.bestEffortRawCount = bestEffortRawCount
        self.unsupportedCount = unsupportedCount
        self.previewEligibleCount = previewEligibleCount
        self.pendingPreviewCount = pendingPreviewCount
        self.fullImageDecodeCount = fullImageDecodeCount
        self.adjacentSidecarCount = adjacentSidecarCount
        self.importedSidecarSyncCount = importedSidecarSyncCount
        self.adjacentSidecarNotImportedCount = adjacentSidecarNotImportedCount
        self.unchangedOriginalCount = unchangedOriginalCount
        self.unchangedSidecarCount = unchangedSidecarCount
        self.selectedExtensions = selectedExtensions
    }
}

public struct RealCorpusSmoke {
    public var root: URL
    public var photoDirectory: URL

    public init(root: URL, photoDirectory: URL) {
        self.root = root
        self.photoDirectory = photoDirectory
    }

    public func run() throws -> RealCorpusSmokeResult {
        guard FileManager.default.fileExists(atPath: photoDirectory.path) else {
            throw TeststripError.invalidState("real corpus photo directory does not exist: \(photoDirectory.path)")
        }

        let decodeProvider = ImageIODecodeProvider()
        let decodeRegistry = DecodeRegistry(providers: [decodeProvider])
        let candidates = try Self.catalogablePhotos(under: photoDirectory)
        let selectedPhotos = try Self.representativeSelection(from: candidates, decodeRegistry: decodeRegistry)
        guard !selectedPhotos.isEmpty else {
            throw TeststripError.invalidState("real corpus smoke found no catalogable photos under \(photoDirectory.path)")
        }

        let beforeOriginals = try fingerprints(for: selectedPhotos)
        let adjacentSidecars = Self.adjacentSidecars(for: selectedPhotos)
        let beforeSidecars = try fingerprints(for: adjacentSidecars)
        let capabilities = selectedPhotos.compactMap { try? decodeRegistry.capability(for: $0) }

        let catalogRoot = root.appendingPathComponent("RealCorpusSmoke", isDirectory: true)
        let catalogURL = catalogRoot.appendingPathComponent("catalog.sqlite")
        let previewCache = PreviewCache(root: catalogRoot.appendingPathComponent("Previews", isDirectory: true))
        try FileManager.default.createDirectory(at: previewCache.root, withIntermediateDirectories: true)

        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let ingestService = IngestService(
            scanner: FolderScanner(supportedExtensions: ImageIODecodeProvider.catalogableExtensions),
            decodeRegistry: decodeRegistry
        )
        let importedAssets = try ingestService.ingest(
            files: selectedPhotos,
            plan: IngestPlanner.addFolder(photoDirectory),
            repository: repository
        )
        if !importedAssets.isEmpty {
            try repository.recordSourceRoot(photoDirectory)
        }

        let previewItems = importedAssets.flatMap { asset -> [PreviewGenerationItem] in
            guard (try? decodeRegistry.capability(for: asset.originalURL).canRenderPreview) == true else {
                return []
            }
            return [PreviewGenerationItem(assetID: asset.id, level: .micro), PreviewGenerationItem(assetID: asset.id, level: .grid)]
        }
        try repository.recordPreviewGenerationPending(previewItems)

        let afterOriginals = try fingerprints(for: selectedPhotos)
        let afterSidecars = try fingerprints(for: adjacentSidecars)
        let selectedExtensions = selectedPhotos.reduce(into: [String: Int]()) { counts, url in
            counts[url.pathExtension.lowercased(), default: 0] += 1
        }
        let importedSidecarSyncCount = try importedAssets.reduce(0) { count, asset in
            try count + (repository.metadataSyncItem(assetID: asset.id) == nil ? 0 : 1)
        }

        return RealCorpusSmokeResult(
            candidatePhotoCount: candidates.count,
            selectedPhotoCount: selectedPhotos.count,
            importedAssetCount: importedAssets.count,
            catalogAssetCount: try repository.assetCount(),
            workingStillCount: capabilities.filter { $0.support == .working }.count,
            bestEffortRawCount: capabilities.filter { $0.support == .bestEffort }.count,
            unsupportedCount: capabilities.filter { $0.support == .unsupported }.count,
            previewEligibleCount: capabilities.filter(\.canRenderPreview).count,
            pendingPreviewCount: try repository.pendingPreviewGenerationItems().count,
            fullImageDecodeCount: capabilities.filter(\.canRenderFullImage).count,
            adjacentSidecarCount: adjacentSidecars.count,
            importedSidecarSyncCount: importedSidecarSyncCount,
            adjacentSidecarNotImportedCount: max(adjacentSidecars.count - importedSidecarSyncCount, 0),
            unchangedOriginalCount: unchangedCount(before: beforeOriginals, after: afterOriginals),
            unchangedSidecarCount: unchangedCount(before: beforeSidecars, after: afterSidecars),
            selectedExtensions: selectedExtensions
        )
    }

    public static func catalogablePhotos(under root: URL) throws -> [URL] {
        try FolderScanner(supportedExtensions: ImageIODecodeProvider.catalogableExtensions).scan(root: root)
    }

    public static func representativeSelection(from candidates: [URL], decodeRegistry: DecodeRegistry) throws -> [URL] {
        var selected: [URL] = []
        appendFirst(.working, from: candidates, decodeRegistry: decodeRegistry, to: &selected)
        appendFirst(extension: "dng", from: candidates, to: &selected)
        appendFirst(extension: "raf", from: candidates, to: &selected)
        appendFirst(.unsupported, from: candidates, decodeRegistry: decodeRegistry, to: &selected)
        return selected
    }

    private static func appendFirst(
        _ support: DecodeSupportLevel,
        from candidates: [URL],
        decodeRegistry: DecodeRegistry,
        to selected: inout [URL]
    ) {
        guard let url = candidates.first(where: { candidate in
            guard !selected.contains(candidate),
                  let capability = try? decodeRegistry.capability(for: candidate) else {
                return false
            }
            return capability.support == support
        }) else {
            return
        }
        selected.append(url)
    }

    private static func appendFirst(extension fileExtension: String, from candidates: [URL], to selected: inout [URL]) {
        guard let url = candidates.first(where: {
            !selected.contains($0) && $0.pathExtension.localizedCaseInsensitiveCompare(fileExtension) == .orderedSame
        }) else {
            return
        }
        selected.append(url)
    }

    private static func adjacentSidecars(for photos: [URL]) -> [URL] {
        let sidecars = photos.flatMap { photo in
            [
                photo.appendingPathExtension("xmp"),
                photo.deletingPathExtension().appendingPathExtension("xmp")
            ]
        }
        return Array(Set(sidecars.filter { FileManager.default.fileExists(atPath: $0.path) })).sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private func fingerprints(for urls: [URL]) throws -> [URL: CorpusFingerprint] {
        try Dictionary(uniqueKeysWithValues: urls.map { url in
            (url, try CorpusFingerprint(url: url))
        })
    }

    private func unchangedCount(before: [URL: CorpusFingerprint], after: [URL: CorpusFingerprint]) -> Int {
        before.filter { url, fingerprint in
            after[url] == fingerprint
        }.count
    }
}

private struct CorpusFingerprint: Equatable {
    var size: Int64
    var modificationDate: Date

    init(url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        modificationDate = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
    }
}
