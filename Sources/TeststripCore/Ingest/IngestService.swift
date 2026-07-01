import Foundation

public struct IngestService: Sendable {
    public var scanner: FolderScanner

    public init(scanner: FolderScanner) {
        self.scanner = scanner
    }

    public func files(for plan: IngestPlan) throws -> [URL] {
        try scanner.scan(root: plan.sourceRoot)
    }

    public func ingest(plan: IngestPlan, repository: CatalogRepository) throws -> [Asset] {
        let sourceFiles = try files(for: plan)
        var assets: [Asset] = []
        for sourceFile in sourceFiles {
            let originalURL = try catalogURL(for: sourceFile, plan: plan)
            let fingerprint = try fingerprint(for: originalURL)
            let asset = Asset(
                id: .new(),
                originalURL: originalURL,
                volumeIdentifier: originalURL.pathComponents.dropFirst().first,
                fingerprint: fingerprint,
                availability: .online,
                metadata: AssetMetadata()
            )
            try repository.upsert(asset)
            assets.append(asset)
        }
        return assets
    }

    private func catalogURL(for sourceFile: URL, plan: IngestPlan) throws -> URL {
        switch plan.mode {
        case .addInPlace:
            return sourceFile
        case .copyToDestination:
            guard let destinationRoot = plan.destinationRoot else {
                throw TeststripError.invalidState("copy ingest requires destination root")
            }
            try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
            let destination = destinationRoot.appendingPathComponent(sourceFile.lastPathComponent)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: sourceFile, to: destination)
            }
            return destination
        }
    }

    private func fingerprint(for url: URL) throws -> FileFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        return FileFingerprint(size: size, modificationDate: modificationDate)
    }
}
