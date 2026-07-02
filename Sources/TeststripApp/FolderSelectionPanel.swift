import AppKit

@MainActor
enum FolderSelectionPanel {
    private static let importFolderParentKey = "FolderSelectionPanel.importFolderParent"
    private static let cardSourceParentKey = "FolderSelectionPanel.cardSourceParent"
    private static let cardDestinationParentKey = "FolderSelectionPanel.cardDestinationParent"

    static func chooseImportFolder(defaults: UserDefaults = .standard) -> URL? {
        let panel = NSOpenPanel()
        configureImportFolderPanel(panel, startingDirectory: startingImportDirectory(defaults: defaults))
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        rememberImportFolder(url, defaults: defaults)
        return url
    }

    static func chooseCardSourceFolder(defaults: UserDefaults = .standard) -> URL? {
        let panel = NSOpenPanel()
        configureCardSourcePanel(panel, startingDirectory: startingCardSourceDirectory(defaults: defaults))
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        rememberCardSourceFolder(url, defaults: defaults)
        return url
    }

    static func chooseCardDestinationFolder(defaults: UserDefaults = .standard) -> URL? {
        let panel = NSOpenPanel()
        configureCardDestinationPanel(panel, startingDirectory: startingCardDestinationDirectory(defaults: defaults))
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        rememberCardDestinationFolder(url, defaults: defaults)
        return url
    }

    static func configureImportFolderPanel(_ panel: NSOpenPanel, startingDirectory: URL? = nil) {
        configureDirectoryPanel(
            panel,
            startingDirectory: startingDirectory,
            canCreateDirectories: false,
            prompt: "Import Folder",
            message: "Select a folder of photos. If you open it first, Import Folder uses the current folder."
        )
    }

    static func configureCardSourcePanel(_ panel: NSOpenPanel, startingDirectory: URL? = nil) {
        configureDirectoryPanel(
            panel,
            startingDirectory: startingDirectory,
            canCreateDirectories: false,
            prompt: "Choose Source",
            message: "Select the card or camera folder. If you open it first, Choose Source uses the current folder."
        )
    }

    static func configureCardDestinationPanel(_ panel: NSOpenPanel, startingDirectory: URL? = nil) {
        configureDirectoryPanel(
            panel,
            startingDirectory: startingDirectory,
            canCreateDirectories: true,
            prompt: "Choose Destination",
            message: "Select where copied photos should be stored. If you open it first, Choose Destination uses the current folder."
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

    static func rememberImportFolder(_ folderURL: URL, defaults: UserDefaults = .standard) {
        rememberDirectory(folderURL, for: importFolderParentKey, defaults: defaults)
    }

    static func rememberCardSourceFolder(_ folderURL: URL, defaults: UserDefaults = .standard) {
        rememberDirectory(folderURL, for: cardSourceParentKey, defaults: defaults)
    }

    static func rememberCardDestinationFolder(_ folderURL: URL, defaults: UserDefaults = .standard) {
        rememberDirectory(folderURL, for: cardDestinationParentKey, defaults: defaults)
    }

    private static func configureDirectoryPanel(
        _ panel: NSOpenPanel,
        startingDirectory: URL?,
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
        panel.directoryURL = startingDirectory
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
