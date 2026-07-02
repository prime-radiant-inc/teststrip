import AppKit

@MainActor
enum FolderSelectionPanel {
    static func chooseImportFolder() -> URL? {
        let panel = NSOpenPanel()
        configureImportFolderPanel(panel)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func configureImportFolderPanel(_ panel: NSOpenPanel) {
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.prompt = "Import"
        panel.message = "Choose a folder of photos to import."
    }
}
