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
            let destination = try destinationURL(for: sourceFile, sourceRoot: plan.sourceRoot, destinationRoot: destinationRoot)
            let destinationDirectory = destination.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            } catch {
                throw TeststripError.io("could not create ingest directory \(destinationDirectory.path): \(error.localizedDescription)")
            }
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw TeststripError.io("ingest destination already exists \(destination.path)")
            }
            do {
                try FileManager.default.copyItem(at: sourceFile, to: destination)
            } catch {
                throw TeststripError.io("could not copy \(sourceFile.path) to \(destination.path): \(error.localizedDescription)")
            }
            return destination
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
}
