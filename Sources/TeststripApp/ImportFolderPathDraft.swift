import Foundation

struct ImportPlanStep: Equatable, Identifiable {
    var title: String
    var detail: String

    var id: String { title }
}

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

    var planSteps: [ImportPlanStep] {
        [
            ImportPlanStep(
                title: "Catalog originals in place",
                detail: "No original files are moved, rewritten, or copied from this folder."
            ),
            ImportPlanStep(
                title: "Mirror portable metadata to XMP",
                detail: "Ratings, labels, flags, keywords, captions, creator, and copyright stay file-based."
            ),
            ImportPlanStep(
                title: "Generate cached previews",
                detail: "Micro and grid previews are queued for fast browsing from slow or offline sources."
            ),
            ImportPlanStep(
                title: "Use the managed background queue",
                detail: "Preview and metadata work remains visible, pausable, and cancellable."
            )
        ]
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
