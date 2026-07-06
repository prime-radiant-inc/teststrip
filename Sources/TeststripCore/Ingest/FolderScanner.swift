import Foundation

public struct FolderScanProgress: Equatable, Sendable {
    public var supportedFileCount: Int
    public var url: URL

    public init(supportedFileCount: Int, url: URL) {
        self.supportedFileCount = supportedFileCount
        self.url = url
    }
}

public typealias FolderScanProgressHandler = @Sendable (FolderScanProgress) -> Void

public struct FolderScanSkippedFile: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case videoFile
        case unrecognizedFile
    }

    public var url: URL
    public var reason: Reason

    public init(url: URL, reason: Reason) {
        self.url = url
        self.reason = reason
    }
}

public typealias FolderScanSkippedFileHandler = (FolderScanSkippedFile) -> Void

public struct FolderScanner: Sendable {
    /// Camera and general-purpose video containers Teststrip recognizes but cannot catalog.
    public static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mts", "m2ts", "mpg", "mpeg", "mkv", "wmv", "3gp", "mxf", "webm"
    ]

    // XMP sidecars ride along with photos and are handled by metadata sync, so
    // they are expected rather than skipped. Hidden files and directories never
    // reach classification because the enumerator excludes them.
    private static let ancillaryExtensions: Set<String> = ["xmp"]

    private let supportedExtensions: Set<String>

    public init(supportedExtensions: Set<String>) {
        self.supportedExtensions = Set(supportedExtensions.map { $0.lowercased() })
    }

    public func scan(
        root: URL,
        progress: FolderScanProgressHandler? = nil,
        skipped: FolderScanSkippedFileHandler? = nil
    ) throws -> [URL] {
        let resolvedRoot = root.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw TeststripError.io("unable to scan \(root.path)")
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: [.isRegularFileKey])
            } catch {
                throw TeststripError.io("could not inspect \(url.path): \(error.localizedDescription)")
            }
            guard values.isRegularFile == true else { continue }
            let fileExtension = url.pathExtension.lowercased()
            if supportedExtensions.contains(fileExtension) {
                let visibleURL = visibleURL(for: url, resolvedRoot: resolvedRoot, requestedRoot: root)
                files.append(visibleURL)
                progress?(FolderScanProgress(supportedFileCount: files.count, url: visibleURL))
            } else if let reason = Self.skipReason(forFileExtension: fileExtension) {
                skipped?(FolderScanSkippedFile(
                    url: visibleURL(for: url, resolvedRoot: resolvedRoot, requestedRoot: root),
                    reason: reason
                ))
            }
        }
        return files.sorted { first, second in
            first.path.localizedStandardCompare(second.path) == .orderedAscending
        }
    }

    private static func skipReason(forFileExtension fileExtension: String) -> FolderScanSkippedFile.Reason? {
        if ancillaryExtensions.contains(fileExtension) {
            return nil
        }
        if videoExtensions.contains(fileExtension) {
            return .videoFile
        }
        return .unrecognizedFile
    }

    private func visibleURL(for url: URL, resolvedRoot: URL, requestedRoot: URL) -> URL {
        let resolvedRootPath = resolvedRoot.path
        let urlPath = url.resolvingSymlinksInPath().path
        guard urlPath.hasPrefix(resolvedRootPath) else {
            return url
        }

        let relativePath = String(urlPath.dropFirst(resolvedRootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return requestedRoot.appendingPathComponent(relativePath)
    }
}
