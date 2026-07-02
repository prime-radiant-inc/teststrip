import Foundation

public struct IngestService: Sendable {
    public var scanner: FolderScanner
    public var decodeRegistry: DecodeRegistry?

    public init(scanner: FolderScanner, decodeRegistry: DecodeRegistry? = nil) {
        self.scanner = scanner
        self.decodeRegistry = decodeRegistry
    }

    public func files(for plan: IngestPlan) throws -> [URL] {
        try Task.checkCancellation()
        return try scanner.scan(root: plan.sourceRoot)
    }

    public func ingest(plan: IngestPlan, repository: CatalogRepository) throws -> [Asset] {
        let sourceFiles = try files(for: plan)
        return try ingest(files: sourceFiles, plan: plan, repository: repository)
    }

    public func ingest(files sourceFiles: [URL], plan: IngestPlan, repository: CatalogRepository) throws -> [Asset] {
        var assets: [Asset] = []
        var importedSidecars: [ImportedSidecarSync] = []
        var sidecarConflicts: [SidecarSyncConflict] = []
        let sidecarStore = XMPSidecarStore()
        for sourceFile in sourceFiles {
            try Task.checkCancellation()
            let originalURL = try originalURL(for: sourceFile, plan: plan)
            let existingAsset = try repository.asset(originalURL: originalURL)
            let assetID = existingAsset?.id ?? .new()
            try prepareOriginalFile(sourceFile: sourceFile, originalURL: originalURL, plan: plan, existingAsset: existingAsset)
            let fingerprint = try fingerprint(for: originalURL)
            var metadata = existingAsset?.metadata ?? AssetMetadata()
            let sidecarURL = sidecarStore.sidecarURL(forOriginalAt: originalURL)
            if FileManager.default.fileExists(atPath: sidecarURL.path) {
                let sidecarData = try Data(contentsOf: sidecarURL)
                let catalogGeneration: Int
                let lastSynced: MetadataSyncItem?
                if existingAsset != nil {
                    catalogGeneration = try repository.catalogGeneration(assetID: assetID)
                    lastSynced = try repository.metadataSyncItem(assetID: assetID)
                } else {
                    catalogGeneration = 1
                    lastSynced = nil
                }
                let decision = try MetadataSyncPlanner().decision(
                    catalogMetadata: metadata,
                    catalogGeneration: catalogGeneration,
                    lastSynced: lastSynced,
                    sidecarData: sidecarData
                )
                if case .importSidecar(let sidecarMetadata) = decision {
                    metadata = sidecarMetadata
                    importedSidecars.append(ImportedSidecarSync(
                        assetID: assetID,
                        sidecarURL: sidecarURL,
                        sidecarData: sidecarData
                    ))
                } else if case .conflict = decision {
                    sidecarConflicts.append(SidecarSyncConflict(
                        assetID: assetID,
                        sidecarURL: sidecarURL,
                        lastSyncedFingerprint: try repository.lastMetadataSyncFingerprint(assetID: assetID)
                    ))
                }
            }
            let asset = Asset(
                id: assetID,
                originalURL: originalURL,
                volumeIdentifier: volumeIdentifier(for: originalURL),
                fingerprint: fingerprint,
                availability: .online,
                metadata: metadata,
                technicalMetadata: technicalMetadata(for: originalURL) ?? existingAsset?.technicalMetadata
            )
            assets.append(asset)
        }
        try repository.upsert(assets)
        for importedSidecar in importedSidecars {
            try repository.markMetadataSynced(
                assetID: importedSidecar.assetID,
                sidecarURL: importedSidecar.sidecarURL,
                catalogGeneration: repository.catalogGeneration(assetID: importedSidecar.assetID),
                fingerprint: XMPSidecarStore.fingerprint(for: importedSidecar.sidecarData)
            )
        }
        for sidecarConflict in sidecarConflicts {
            try repository.recordMetadataSyncConflict(MetadataSyncItem(
                assetID: sidecarConflict.assetID,
                sidecarURL: sidecarConflict.sidecarURL,
                catalogGeneration: repository.catalogGeneration(assetID: sidecarConflict.assetID),
                lastSyncedFingerprint: sidecarConflict.lastSyncedFingerprint
            ))
        }
        return assets
    }

    private func originalURL(for sourceFile: URL, plan: IngestPlan) throws -> URL {
        switch plan.mode {
        case .addInPlace:
            return sourceFile
        case .copyToDestination:
            guard let destinationRoot = plan.destinationRoot else {
                throw TeststripError.invalidState("copy ingest requires destination root")
            }
            return try destinationURL(for: sourceFile, sourceRoot: plan.sourceRoot, destinationRoot: destinationRoot)
        }
    }

    private func prepareOriginalFile(
        sourceFile: URL,
        originalURL: URL,
        plan: IngestPlan,
        existingAsset: Asset?
    ) throws {
        switch plan.mode {
        case .addInPlace:
            return
        case .copyToDestination:
            guard !FileManager.default.fileExists(atPath: originalURL.path) else {
                if existingAsset != nil {
                    return
                }
                throw TeststripError.io("ingest destination already exists \(originalURL.path)")
            }

            let destinationDirectory = originalURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            } catch {
                throw TeststripError.io("could not create ingest directory \(destinationDirectory.path): \(error.localizedDescription)")
            }
            do {
                try FileManager.default.copyItem(at: sourceFile, to: originalURL)
            } catch {
                throw TeststripError.io("could not copy \(sourceFile.path) to \(originalURL.path): \(error.localizedDescription)")
            }
        }
    }

    private func destinationURL(for sourceFile: URL, sourceRoot: URL, destinationRoot: URL) throws -> URL {
        let sourceRootPath = sourceRoot.resolvingSymlinksInPath().path
        let sourceFilePath = sourceFile.resolvingSymlinksInPath().path
        let sourceRootPrefix = sourceRootPath == "/" ? sourceRootPath : sourceRootPath + "/"
        guard sourceFilePath.hasPrefix(sourceRootPrefix) else {
            throw TeststripError.io("source file \(sourceFile.path) is outside ingest root \(sourceRoot.path)")
        }

        let relativePath = String(sourceFilePath.dropFirst(sourceRootPrefix.count))
        return destinationRoot.appendingPathComponent(relativePath)
    }

    private func fingerprint(for url: URL) throws -> FileFingerprint {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw TeststripError.io("could not fingerprint \(url.path): \(error.localizedDescription)")
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        return FileFingerprint(size: size, modificationDate: modificationDate)
    }

    private func volumeIdentifier(for url: URL) -> String? {
        guard let identifier = try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else {
            return nil
        }
        if let data = identifier as? Data {
            return data.base64EncodedString()
        }
        if let data = identifier as? NSData {
            return data.base64EncodedString()
        }
        if let string = identifier as? String {
            return string
        }
        return String(describing: identifier)
    }

    private func technicalMetadata(for url: URL) -> AssetTechnicalMetadata? {
        guard let decodeRegistry,
              let provider = try? decodeRegistry.provider(for: url),
              let metadata = try? provider.metadata(for: url) else {
            return nil
        }
        return metadata.assetTechnicalMetadata
    }
}

private struct ImportedSidecarSync {
    var assetID: AssetID
    var sidecarURL: URL
    var sidecarData: Data
}

private struct SidecarSyncConflict {
    var assetID: AssetID
    var sidecarURL: URL
    var lastSyncedFingerprint: String?
}
