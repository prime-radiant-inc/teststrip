import Foundation
import TeststripCore

private enum ImportFolderPreflight {
    static func blockingReason(
        for folderURL: URL,
        label: String,
        requiresReadableAccess: Bool,
        requiresWritableAccess: Bool,
        fileManager: FileManager = .default
    ) -> String? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory) else {
            return "\(label) folder is missing"
        }
        guard isDirectory.boolValue else {
            return "\(label) is not a folder"
        }
        if requiresReadableAccess, !fileManager.isReadableFile(atPath: folderURL.path) {
            return "\(label) folder is not readable"
        }
        if requiresWritableAccess, !fileManager.isWritableFile(atPath: folderURL.path) {
            return "\(label) folder is not writable"
        }
        return nil
    }
}

enum ImportSourcePreflight {
    static func blockingReason(for sourceURL: URL, fileManager: FileManager = .default) -> String? {
        ImportFolderPreflight.blockingReason(
            for: sourceURL,
            label: "Source",
            requiresReadableAccess: true,
            requiresWritableAccess: false,
            fileManager: fileManager
        )
    }
}

struct ImportSourceSummary: Equatable {
    static let defaultScanLimit = 300
    static let defaultEntryLimit = 2_000

    var sourceURL: URL
    var photoCount: Int
    var byteCount: Int64
    var reachedLimit: Bool
    var reachedEntryLimit: Bool
    var scannedEntryCount: Int
    var unavailableReason: String?
    var blocksImport: Bool

    static func scan(
        sourceURL: URL,
        supportedExtensions: Set<String> = ImageIODecodeProvider.catalogableExtensions,
        limit: Int = defaultScanLimit,
        entryLimit: Int = defaultEntryLimit
    ) -> ImportSourceSummary {
        let boundedLimit = max(1, limit)
        let boundedEntryLimit = max(1, entryLimit)
        let supportedExtensions = Set(supportedExtensions.map { $0.lowercased() })
        if let blockingReason = ImportSourcePreflight.blockingReason(for: sourceURL) {
            return unavailableSummary(sourceURL: sourceURL, reason: blockingReason, blocksImport: true)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return unavailableSummary(
                sourceURL: sourceURL,
                reason: "Source will be scanned when import starts",
                blocksImport: false
            )
        }

        var photoCount = 0
        var byteCount: Int64 = 0
        var reachedLimit = false
        var reachedEntryLimit = false
        var scannedEntryCount = 0
        for case let fileURL as URL in enumerator {
            if scannedEntryCount == boundedEntryLimit {
                reachedEntryLimit = true
                break
            }
            scannedEntryCount += 1
            guard supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            if photoCount == boundedLimit {
                reachedLimit = true
                break
            }
            photoCount += 1
            byteCount += Int64(values?.fileSize ?? 0)
        }

        return ImportSourceSummary(
            sourceURL: sourceURL,
            photoCount: photoCount,
            byteCount: byteCount,
            reachedLimit: reachedLimit,
            reachedEntryLimit: reachedEntryLimit,
            scannedEntryCount: scannedEntryCount,
            unavailableReason: nil,
            blocksImport: false
        )
    }

    private static func unavailableSummary(sourceURL: URL, reason: String, blocksImport: Bool) -> ImportSourceSummary {
        ImportSourceSummary(
            sourceURL: sourceURL,
            photoCount: 0,
            byteCount: 0,
            reachedLimit: false,
            reachedEntryLimit: false,
            scannedEntryCount: 0,
            unavailableReason: reason,
            blocksImport: blocksImport
        )
    }

    var countText: String {
        if let unavailableReason {
            return unavailableReason
        }
        if photoCount == 0 {
            if reachedEntryLimit {
                return "No recognized photo files found yet"
            }
            return "No recognized photo files found"
        }
        let suffix = reachedLimit || reachedEntryLimit ? "+" : ""
        let noun = photoCount == 1 ? "photo file" : "photo files"
        return "\(photoCount)\(suffix) recognized \(noun)"
    }

    var byteCountText: String {
        if unavailableReason != nil {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var canStartImport: Bool {
        !blocksImport && (unavailableReason != nil || photoCount > 0 || reachedEntryLimit)
    }

    var detailText: String {
        if let unavailableReason {
            return unavailableReason
        }
        if reachedEntryLimit {
            let noun = scannedEntryCount == 1 ? "file" : "files"
            return "Preview scanned the first \(scannedEntryCount) \(noun); import will keep scanning"
        }
        if reachedLimit {
            let noun = photoCount == 1 ? "photo file" : "photo files"
            return "Preview counted the first \(photoCount) recognized \(noun)"
        }
        if photoCount == 0 {
            return "Choose a folder with recognized photo files before importing"
        }
        let sourceName = sourceURL.lastPathComponent.isEmpty ? sourceURL.path : sourceURL.lastPathComponent
        return "Ready to catalog from \(sourceName)"
    }
}

// A bounded preview of how a source folder splits into content the catalog has
// never seen and content already present, so the import sheet can promise "N
// new · M already in catalog" before any copy runs. Counts mirror the ingest
// dedup outcome: newContentCount is distinct never-seen content; every other
// scanned photo (a catalog match or a within-batch duplicate) will be skipped.
struct ImportDedupPreview: Equatable {
    var newContentCount: Int
    var existingContentCount: Int
    var reachedLimit: Bool

    static func scan(
        sourceURL: URL,
        supportedExtensions: Set<String> = ImageIODecodeProvider.catalogableExtensions,
        repository: CatalogRepository,
        limit: Int = ImportSourceSummary.defaultScanLimit,
        entryLimit: Int = ImportSourceSummary.defaultEntryLimit
    ) -> ImportDedupPreview? {
        let boundedLimit = max(1, limit)
        let boundedEntryLimit = max(1, entryLimit)
        let supportedExtensions = Set(supportedExtensions.map { $0.lowercased() })
        guard let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var scannedPhotoCount = 0
        var contentHashes: [String] = []
        var scannedEntryCount = 0
        var reachedLimit = false
        for case let fileURL as URL in enumerator {
            if scannedEntryCount == boundedEntryLimit {
                reachedLimit = true
                break
            }
            scannedEntryCount += 1
            guard supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            if scannedPhotoCount == boundedLimit {
                reachedLimit = true
                break
            }
            scannedPhotoCount += 1
            if let hash = try? ContentHash.compute(forFileAt: fileURL) {
                contentHashes.append(hash)
            }
        }

        let uniqueHashes = Set(contentHashes)
        let existingHashes = (try? repository.containedContentHashes(uniqueHashes)) ?? []
        let newContentCount = uniqueHashes.subtracting(existingHashes).count
        return ImportDedupPreview(
            newContentCount: newContentCount,
            existingContentCount: max(scannedPhotoCount - newContentCount, 0),
            reachedLimit: reachedLimit
        )
    }
}

struct ImportConfirmationDraft: Equatable, Identifiable {
    enum Mode: Equatable {
        case folder
        case card
    }

    var mode: Mode
    var sourceURL: URL
    var destinationRootURL: URL?
    var destinationUnavailableReason: String?
    var destinationPolicy: ImportDestinationPolicy = .flat
    private(set) var secondCopyRootURL: URL?
    private(set) var secondCopyUnavailableReason: String?
    var sourceSummary: ImportSourceSummary
    var evaluateAfterImport = true
    var importNewOnly = true
    var dedupPreview: ImportDedupPreview?

    var id: String {
        [
            title,
            sourceURL.standardizedFileURL.path,
            destinationRootURL?.standardizedFileURL.path ?? "",
            destinationUnavailableReason ?? ""
        ].joined(separator: "|")
    }

    static func folder(
        _ sourceURL: URL,
        supportedExtensions: Set<String> = ImageIODecodeProvider.catalogableExtensions
    ) -> ImportConfirmationDraft {
        ImportConfirmationDraft(
            mode: .folder,
            sourceURL: sourceURL,
            destinationRootURL: nil,
            destinationUnavailableReason: nil,
            sourceSummary: ImportSourceSummary.scan(sourceURL: sourceURL, supportedExtensions: supportedExtensions)
        )
    }

    // New card imports organize into dated folders by default; it matches the
    // design's destination pattern and the YYYY/YYYY-MM-DD library layout.
    static func card(
        source sourceURL: URL,
        destinationRoot destinationRootURL: URL,
        destinationPolicy: ImportDestinationPolicy = .capturedDate,
        secondCopyRootURL: URL? = nil,
        supportedExtensions: Set<String> = ImageIODecodeProvider.catalogableExtensions
    ) -> ImportConfirmationDraft {
        ImportConfirmationDraft(
            mode: .card,
            sourceURL: sourceURL,
            destinationRootURL: destinationRootURL,
            destinationUnavailableReason: CardImportDestinationPreflight.blockingReason(
                source: sourceURL,
                destinationRoot: destinationRootURL
            ),
            destinationPolicy: destinationPolicy,
            secondCopyRootURL: secondCopyRootURL,
            secondCopyUnavailableReason: Self.secondCopyBlockingReason(
                source: sourceURL,
                destinationRoot: destinationRootURL,
                secondCopyRootURL: secondCopyRootURL
            ),
            sourceSummary: ImportSourceSummary.scan(sourceURL: sourceURL, supportedExtensions: supportedExtensions)
        )
    }

    mutating func setSecondCopyRoot(_ secondCopyRootURL: URL?) {
        self.secondCopyRootURL = secondCopyRootURL
        secondCopyUnavailableReason = Self.secondCopyBlockingReason(
            source: sourceURL,
            destinationRoot: destinationRootURL,
            secondCopyRootURL: secondCopyRootURL
        )
    }

    private static func secondCopyBlockingReason(source: URL, destinationRoot: URL?, secondCopyRootURL: URL?) -> String? {
        guard let secondCopyRootURL else { return nil }
        guard let destinationRoot else {
            return CardImportDestinationPreflight.blockingReason(
                source: source,
                destinationRoot: secondCopyRootURL,
                destinationLabel: "Second copy destination"
            )
        }
        return CardImportDestinationPreflight.secondCopyBlockingReason(
            source: source,
            destinationRoot: destinationRoot,
            secondCopyDestination: secondCopyRootURL
        )
    }

    var title: String {
        switch mode {
        case .folder:
            return "Import Folder"
        case .card:
            return "Import Card"
        }
    }

    var sourceName: String {
        sourceURL.lastPathComponent
    }

    // "2,310 new · 418 already in catalog" — the new count alone when nothing is
    // recognized, with a "+" when the preview stopped at its scan cap.
    var dedupCountText: String? {
        guard let dedupPreview else { return nil }
        let newText = "\(Self.grouped(dedupPreview.newContentCount))\(dedupPreview.reachedLimit ? "+" : "") new"
        guard dedupPreview.existingContentCount > 0 else {
            return newText
        }
        return "\(newText) · \(Self.grouped(dedupPreview.existingContentCount)) already in catalog"
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    var destinationName: String? {
        destinationRootURL?.lastPathComponent
    }

    var secondCopyName: String? {
        secondCopyRootURL?.lastPathComponent
    }

    var primaryActionTitle: String {
        switch mode {
        case .folder:
            return "Start Import"
        case .card:
            return "Start Card Import"
        }
    }

    var canStartImport: Bool {
        sourceSummary.canStartImport && destinationUnavailableReason == nil && secondCopyUnavailableReason == nil
    }

    var planSteps: [ImportPlanStep] {
        let baseSteps: [ImportPlanStep]
        switch mode {
        case .folder:
            baseSteps = ImportPlanSteps.folderInPlace
        case .card:
            baseSteps = ImportPlanSteps.cardCopy(
                destinationName: destinationName ?? "the destination",
                destinationPolicy: destinationPolicy,
                secondCopyName: secondCopyName
            )
        }
        guard evaluateAfterImport else { return baseSteps }
        return baseSteps + [ImportPlanSteps.autoEvaluation]
    }
}
