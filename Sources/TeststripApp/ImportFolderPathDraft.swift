import Foundation

struct ImportFolderPathDraft: Equatable {
    var path: String {
        didSet {
            if path != oldValue {
                errorMessage = nil
            }
        }
    }
    private(set) var errorMessage: String?

    init(path: String = "", errorMessage: String? = nil) {
        self.path = path
        self.errorMessage = errorMessage
    }

    mutating func reset() {
        path = ""
        errorMessage = nil
    }

    @MainActor
    mutating func resolveFolderURL() throws -> URL {
        do {
            let folderURL = try FolderSelectionPanel.importFolderURL(fromPath: path)
            errorMessage = nil
            return folderURL
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
