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

    // The second copy exists to survive a primary-disk failure, so beyond the
    // source-relative checks it must also be a different folder than the
    // primary destination; equal roots would make every backup copy a no-op.
    public static func secondCopyBlockingReason(
        source: URL,
        destinationRoot: URL,
        secondCopyDestination: URL,
        fileManager: FileManager = .default
    ) -> String? {
        if let blockingReason = blockingReason(
            source: source,
            destinationRoot: secondCopyDestination,
            destinationLabel: "Second copy destination",
            fileManager: fileManager
        ) {
            return blockingReason
        }
        if normalizedDirectoryPath(secondCopyDestination) == normalizedDirectoryPath(destinationRoot) {
            return "Second copy destination must be different from the primary destination"
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
