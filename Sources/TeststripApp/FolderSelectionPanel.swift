import AppKit
import TeststripCore

@MainActor
enum FolderSelectionPanel {
    private static let importFolderParentKey = "FolderSelectionPanel.importFolderParent"
    private static let cardSourceParentKey = "FolderSelectionPanel.cardSourceParent"
    private static let cardDestinationParentKey = "FolderSelectionPanel.cardDestinationParent"
    private static let cardSecondCopyParentKey = "FolderSelectionPanel.cardSecondCopyParent"
    private static let exportDestinationParentKey = "FolderSelectionPanel.exportDestinationParent"

    static func chooseImportFolder(defaults: UserDefaults = .standard) -> URL? {
        let panel = NSOpenPanel()
        configureImportFolderPanel(
            panel,
            startingDirectory: defaultStartingDirectory(),
            rememberedDirectory: rememberedDirectory(for: importFolderParentKey, defaults: defaults)
        )
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        rememberImportFolder(url, defaults: defaults)
        return url
    }

    static func chooseCardSourceFolder(defaults: UserDefaults = .standard) -> URL? {
        let panel = NSOpenPanel()
        configureCardSourcePanel(
            panel,
            startingDirectory: defaultStartingDirectory(),
            rememberedDirectory: rememberedDirectory(for: cardSourceParentKey, defaults: defaults)
        )
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        rememberCardSourceFolder(url, defaults: defaults)
        return url
    }

    static func chooseCardDestinationFolder(defaults: UserDefaults = .standard) -> URL? {
        let panel = NSOpenPanel()
        configureCardDestinationPanel(
            panel,
            startingDirectory: defaultStartingDirectory(),
            rememberedDirectory: rememberedDirectory(for: cardDestinationParentKey, defaults: defaults)
        )
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        rememberCardDestinationFolder(url, defaults: defaults)
        return url
    }

    static func chooseCardSecondCopyFolder(defaults: UserDefaults = .standard) -> URL? {
        let panel = NSOpenPanel()
        configureCardSecondCopyPanel(
            panel,
            startingDirectory: defaultStartingDirectory(),
            rememberedDirectory: rememberedDirectory(for: cardSecondCopyParentKey, defaults: defaults)
        )
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        rememberCardSecondCopyFolder(url, defaults: defaults)
        return url
    }

    static func chooseExportDestinationFolder(defaults: UserDefaults = .standard) -> URL? {
        let panel = NSOpenPanel()
        configureExportDestinationPanel(
            panel,
            startingDirectory: defaultStartingDirectory(),
            rememberedDirectory: rememberedDirectory(for: exportDestinationParentKey, defaults: defaults)
        )
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        rememberExportDestinationFolder(url, defaults: defaults)
        return url
    }

    static func configureImportFolderPanel(
        _ panel: NSOpenPanel,
        startingDirectory: URL? = nil,
        rememberedDirectory: URL? = nil
    ) {
        configureDirectoryPanel(
            panel,
            startingDirectory: startingDirectory,
            rememberedDirectory: rememberedDirectory,
            canCreateDirectories: false,
            prompt: "Import Folder",
            message: "Select the folder of photos to import."
        )
    }

    static func configureCardSourcePanel(
        _ panel: NSOpenPanel,
        startingDirectory: URL? = nil,
        rememberedDirectory: URL? = nil
    ) {
        configureDirectoryPanel(
            panel,
            startingDirectory: startingDirectory,
            rememberedDirectory: rememberedDirectory,
            canCreateDirectories: false,
            prompt: "Choose Source",
            message: "Select the card or camera folder."
        )
    }

    static func configureCardDestinationPanel(
        _ panel: NSOpenPanel,
        startingDirectory: URL? = nil,
        rememberedDirectory: URL? = nil
    ) {
        configureDirectoryPanel(
            panel,
            startingDirectory: startingDirectory,
            rememberedDirectory: rememberedDirectory,
            canCreateDirectories: true,
            prompt: "Choose Destination",
            message: "Select where copied photos should be stored."
        )
    }

    static func configureCardSecondCopyPanel(
        _ panel: NSOpenPanel,
        startingDirectory: URL? = nil,
        rememberedDirectory: URL? = nil
    ) {
        configureDirectoryPanel(
            panel,
            startingDirectory: startingDirectory,
            rememberedDirectory: rememberedDirectory,
            canCreateDirectories: true,
            prompt: "Choose Second Copy",
            message: "Select where backup copies of the card should be written."
        )
    }

    static func configureExportDestinationPanel(
        _ panel: NSOpenPanel,
        startingDirectory: URL? = nil,
        rememberedDirectory: URL? = nil
    ) {
        configureDirectoryPanel(
            panel,
            startingDirectory: startingDirectory,
            rememberedDirectory: rememberedDirectory,
            canCreateDirectories: true,
            prompt: "Export Here",
            message: "Select where exported JPEGs should be written."
        )
    }

    static func startingImportDirectory(defaults: UserDefaults = .standard) -> URL? {
        rememberedDirectory(for: importFolderParentKey, defaults: defaults) ?? defaultStartingDirectory()
    }

    static func startingCardSourceDirectory(defaults: UserDefaults = .standard) -> URL? {
        rememberedDirectory(for: cardSourceParentKey, defaults: defaults) ?? defaultStartingDirectory()
    }

    static func startingCardDestinationDirectory(defaults: UserDefaults = .standard) -> URL? {
        rememberedDirectory(for: cardDestinationParentKey, defaults: defaults) ?? defaultStartingDirectory()
    }

    static func startingCardSecondCopyDirectory(defaults: UserDefaults = .standard) -> URL? {
        rememberedDirectory(for: cardSecondCopyParentKey, defaults: defaults) ?? defaultStartingDirectory()
    }

    static func startingExportDestinationDirectory(defaults: UserDefaults = .standard) -> URL? {
        rememberedDirectory(for: exportDestinationParentKey, defaults: defaults) ?? defaultStartingDirectory()
    }

    static func rememberImportFolder(_ folderURL: URL, defaults: UserDefaults = .standard) {
        rememberDirectory(folderURL, for: importFolderParentKey, defaults: defaults)
    }

    static func rememberCardSourceFolder(_ folderURL: URL, defaults: UserDefaults = .standard) {
        rememberDirectory(folderURL, for: cardSourceParentKey, defaults: defaults)
    }

    static func rememberCardDestinationFolder(_ folderURL: URL, defaults: UserDefaults = .standard) {
        rememberDirectory(folderURL, for: cardDestinationParentKey, defaults: defaults)
    }

    static func rememberCardSecondCopyFolder(_ folderURL: URL, defaults: UserDefaults = .standard) {
        rememberDirectory(folderURL, for: cardSecondCopyParentKey, defaults: defaults)
    }

    static func rememberExportDestinationFolder(_ folderURL: URL, defaults: UserDefaults = .standard) {
        rememberDirectory(folderURL, for: exportDestinationParentKey, defaults: defaults)
    }

    static func importFolderURL(fromPath path: String) throws -> URL {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw TeststripError.invalidState("Enter a folder path")
        }
        let expandedPath = (trimmedPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw TeststripError.invalidState("Folder path does not exist")
        }
        guard isDirectory.boolValue else {
            throw TeststripError.invalidState("Folder path is not a folder")
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw TeststripError.invalidState("Folder path is not readable")
        }
        return url.standardizedFileURL
    }

    private static func configureDirectoryPanel(
        _ panel: NSOpenPanel,
        startingDirectory: URL?,
        rememberedDirectory: URL?,
        canCreateDirectories: Bool,
        prompt: String,
        message: String
    ) {
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = canCreateDirectories
        panel.resolvesAliases = true
        panel.prompt = prompt
        panel.message = message
        if let rememberedDirectory,
           let directory = existingDirectory(rememberedDirectory) {
            panel.directoryURL = directory
        } else {
            panel.directoryURL = startingDirectory
        }
    }

    private static func rememberDirectory(_ folderURL: URL, for key: String, defaults: UserDefaults) {
        defaults.set(folderURL.standardizedFileURL.path, forKey: key)
    }

    private static func rememberedDirectory(for key: String, defaults: UserDefaults) -> URL? {
        guard let path = defaults.string(forKey: key), !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return existingDirectory(url)
    }

    private static func defaultStartingDirectory() -> URL? {
        let fileManager = FileManager.default
        if let pictures = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first,
           let existingPictures = existingDirectory(pictures) {
            return existingPictures
        }
        return existingDirectory(fileManager.homeDirectoryForCurrentUser)
    }

    private static func existingDirectory(_ url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return url
    }
}
