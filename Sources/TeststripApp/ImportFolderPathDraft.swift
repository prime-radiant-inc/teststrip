import Foundation

enum ImportPlanStepStage: String, Equatable {
    case importWork
    case followUpSetup
}

struct ImportPlanStep: Equatable, Identifiable {
    var title: String
    var detail: String
    var stage: ImportPlanStepStage = .importWork

    var id: String { title }
}

enum ImportPlanSteps {
    static var folderInPlace: [ImportPlanStep] {
        [
            ImportPlanStep(
                title: "Catalog originals in place",
                detail: "No original files are moved, rewritten, or copied from this folder."
            )
        ] + sharedImportWorkSteps + [
            ImportPlanStep(
                title: "Use the managed background queue",
                detail: "Preview and metadata work remains visible, pausable, and cancellable."
            )
        ] + followUpSetupSteps
    }

    static func cardCopy(destinationName: String) -> [ImportPlanStep] {
        [
            ImportPlanStep(
                title: "Copy card files first",
                detail: "Originals are copied into \(destinationName) before Teststrip catalogs the copied files."
            )
        ] + sharedImportWorkSteps + [
            ImportPlanStep(
                title: "Use the managed background queue",
                detail: "Copy, preview, and metadata work remains visible, pausable, and cancellable."
            )
        ] + followUpSetupSteps
    }

    private static let sharedImportWorkSteps = [
        ImportPlanStep(
            title: "Mirror portable metadata to XMP",
            detail: "Ratings, labels, flags, keywords, captions, creator, and copyright stay file-based."
        ),
        ImportPlanStep(
            title: "Generate cached previews",
            detail: "Micro and grid previews are queued for fast browsing from slow or offline sources."
        )
    ]

    private static let followUpSetupSteps = [
        ImportPlanStep(
            title: "Prepare imported-set culling",
            detail: "The imported output set is kept as a working scope so Open and Cull can resume it immediately.",
            stage: .followUpSetup
        ),
        ImportPlanStep(
            title: "Detect likely stacks",
            detail: "Time-adjacent frames unlock stack culling when a burst or sequence is found after import.",
            stage: .followUpSetup
        ),
        ImportPlanStep(
            title: "Prepare keyword review",
            detail: "Local object labels stay provisional until you accept them into keywords/XMP.",
            stage: .followUpSetup
        ),
        ImportPlanStep(
            title: "Prepare face review",
            detail: "Detected faces route to Faces Found review; naming waits for future clustering.",
            stage: .followUpSetup
        )
    ]
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
        ImportPlanSteps.folderInPlace
    }

    var primaryActionTitle: String {
        "Review Import"
    }

    mutating func reset() {
        path = ""
        errorMessage = nil
    }

    @MainActor
    mutating func makeFolderConfirmationDraft() throws -> ImportConfirmationDraft {
        .folder(try resolveFolderURL())
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

struct ImportCardPathDraft: Equatable {
    var sourcePath: String {
        didSet {
            if sourcePath != oldValue {
                errorMessage = nil
            }
        }
    }
    var destinationPath: String {
        didSet {
            if destinationPath != oldValue {
                errorMessage = nil
            }
        }
    }
    private(set) var errorMessage: String?

    init(sourcePath: String = "", destinationPath: String = "", errorMessage: String? = nil) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.errorMessage = errorMessage
    }

    var planSteps: [ImportPlanStep] {
        ImportPlanSteps.cardCopy(destinationName: destinationDisplayName)
    }

    var primaryActionTitle: String {
        "Review Card Import"
    }

    mutating func reset() {
        sourcePath = ""
        destinationPath = ""
        errorMessage = nil
    }

    @MainActor
    mutating func makeCardConfirmationDraft() throws -> ImportConfirmationDraft {
        let roots = try resolveCardURLs()
        return .card(source: roots.source, destinationRoot: roots.destinationRoot)
    }

    @MainActor
    mutating func resolveCardURLs() throws -> (source: URL, destinationRoot: URL) {
        do {
            let sourceURL = try FolderSelectionPanel.importFolderURL(fromPath: sourcePath)
            let destinationURL = try FolderSelectionPanel.importFolderURL(fromPath: destinationPath)
            errorMessage = nil
            return (source: sourceURL, destinationRoot: destinationURL)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private var destinationDisplayName: String {
        let trimmed = destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "the destination" }
        return URL(fileURLWithPath: trimmed, isDirectory: true).lastPathComponent
    }
}

struct ImportFolderPathReviewPresentation: Equatable {
    var primaryActionTitle: String
    var isPrimaryActionEnabled: Bool
    var showsProgress: Bool
    var statusText: String?

    init(draft: ImportFolderPathDraft, isReviewing: Bool, isImporting: Bool) {
        let hasPath = !draft.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        primaryActionTitle = isReviewing ? "Reviewing..." : draft.primaryActionTitle
        isPrimaryActionEnabled = hasPath && !isReviewing && !isImporting
        showsProgress = isReviewing
        statusText = isReviewing ? "Reviewing folder before import..." : nil
    }
}

struct ImportCardPathReviewPresentation: Equatable {
    var primaryActionTitle: String
    var isPrimaryActionEnabled: Bool
    var showsProgress: Bool
    var statusText: String?

    init(draft: ImportCardPathDraft, isReviewing: Bool, isImporting: Bool) {
        let hasSourcePath = !draft.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasDestinationPath = !draft.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        primaryActionTitle = isReviewing ? "Reviewing..." : draft.primaryActionTitle
        isPrimaryActionEnabled = hasSourcePath && hasDestinationPath && !isReviewing && !isImporting
        showsProgress = isReviewing
        statusText = isReviewing ? "Reviewing card import before copy..." : nil
    }
}
