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

struct ImportConfirmationDraft: Equatable, Identifiable {
    enum Mode: Equatable {
        case folder
        case card
    }

    var mode: Mode
    var sourceURL: URL
    var destinationRootURL: URL?
    var destinationUnavailableReason: String?
    var sourceSummary: ImportSourceSummary

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

    static func card(
        source sourceURL: URL,
        destinationRoot destinationRootURL: URL,
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
            sourceSummary: ImportSourceSummary.scan(sourceURL: sourceURL, supportedExtensions: supportedExtensions)
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

    var destinationName: String? {
        destinationRootURL?.lastPathComponent
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
        sourceSummary.canStartImport && destinationUnavailableReason == nil
    }

    var planSteps: [ImportPlanStep] {
        switch mode {
        case .folder:
            return ImportPlanSteps.folderInPlace
        case .card:
            return ImportPlanSteps.cardCopy(destinationName: destinationName ?? "the destination")
        }
    }
}
