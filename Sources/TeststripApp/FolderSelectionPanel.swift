import AppKit

@MainActor
enum FolderSelectionPanel {
    static func chooseImportFolder() -> URL? {
        let panel = NSOpenPanel()
        configureImportFolderPanel(panel)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseCardSourceFolder() -> URL? {
        let panel = NSOpenPanel()
        configureCardSourcePanel(panel)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseCardDestinationFolder() -> URL? {
        let panel = NSOpenPanel()
        configureCardDestinationPanel(panel)
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

    static func configureCardSourcePanel(_ panel: NSOpenPanel) {
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.prompt = "Choose"
        panel.message = "Choose the card or camera folder to copy photos from."
    }

    static func configureCardDestinationPanel(_ panel: NSOpenPanel) {
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true
        panel.prompt = "Choose"
        panel.message = "Choose where copied photos should be stored."
    }
}
