import Foundation

public enum CardImportDestinationPreflight {
    public static func blockingReason(
        source: URL,
        destinationRoot: URL,
        destinationLabel: String = "Destination",
        fileManager: FileManager = .default
    ) -> String? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destinationRoot.path, isDirectory: &isDirectory) else {
            return "\(destinationLabel) folder is missing"
        }
        guard isDirectory.boolValue else {
            return "\(destinationLabel) is not a folder"
        }
        guard fileManager.isWritableFile(atPath: destinationRoot.path) else {
            return "\(destinationLabel) folder is not writable"
        }

        let sourcePath = normalizedDirectoryPath(source)
        let destinationPath = normalizedDirectoryPath(destinationRoot)
        if destinationPath == sourcePath {
            return "\(destinationLabel) must be different from the card source"
        }
        if isDirectoryPath(destinationPath, inside: sourcePath) {
            return "\(destinationLabel) cannot be inside the card source"
        }
        if isDirectoryPath(sourcePath, inside: destinationPath) {
            return "Card source cannot be inside the \(destinationLabel.lowercased())"
        }
        return nil
    }

    private static func normalizedDirectoryPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if path == "/" { return path }
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private static func isDirectoryPath(_ childPath: String, inside parentPath: String) -> Bool {
        guard parentPath != "/" else { return childPath != "/" }
        return childPath.hasPrefix(parentPath + "/")
    }
}
