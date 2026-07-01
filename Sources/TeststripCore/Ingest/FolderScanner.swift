import Foundation

public struct FolderScanner: Sendable {
    private let supportedExtensions: Set<String>

    public init(supportedExtensions: Set<String>) {
        self.supportedExtensions = supportedExtensions
    }

    public func scan(root: URL) throws -> [URL] {
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
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            if supportedExtensions.contains(url.pathExtension.lowercased()) {
                files.append(visibleURL(for: url, resolvedRoot: resolvedRoot, requestedRoot: root))
            }
        }
        return files
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
