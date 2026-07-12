import Foundation
import TeststripCore

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

    static func cardCopy(
        destinationName: String,
        destinationPolicy: ImportDestinationPolicy = .flat,
        secondCopyName: String? = nil
    ) -> [ImportPlanStep] {
        let copyDetail: String
        switch destinationPolicy {
        case .flat:
            copyDetail = "Originals are copied into \(destinationName) before Teststrip catalogs the copied files."
        case .capturedDate:
            copyDetail = "Originals are copied into dated folders (YYYY/YYYY-MM-DD) inside \(destinationName) before Teststrip catalogs the copied files."
        }
        var steps = [
            ImportPlanStep(
                title: "Copy card files first",
                detail: copyDetail
            )
        ]
        if let secondCopyName {
            steps.append(ImportPlanStep(
                title: "Write a second copy",
                detail: "Each copied original and its sidecar is also copied into \(secondCopyName); backup failures are reported per file and never stop the import."
            ))
        }
        return steps + sharedImportWorkSteps + [
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
            detail: "These photos stay selected so Open and Cull can resume them immediately.",
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

    static let autoEvaluation = ImportPlanStep(
        title: "Read imported frames",
        detail: "Focus, exposure, and face reads queue over cached previews as they finish; reads stay provisional until you act.",
        stage: .followUpSetup
    )

    static let autopilot = ImportPlanStep(
        title: "Autopilot cull",
        detail: "After reads finish, Autopilot proposes keeps and cuts for review — nothing is written until you commit.",
        stage: .followUpSetup
    )
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
    // Dated folders match the design's destination pattern and the
    // YYYY/YYYY-MM-DD library layout, so new card imports default to them.
    var organizeIntoDatedFolders = true
    var secondCopyPath: String = "" {
        didSet {
            if secondCopyPath != oldValue {
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
        ImportPlanSteps.cardCopy(
            destinationName: destinationDisplayName,
            destinationPolicy: destinationPolicy,
            secondCopyName: secondCopyDisplayName
        )
    }

    var destinationPolicy: ImportDestinationPolicy {
        organizeIntoDatedFolders ? .capturedDate : .flat
    }

    var primaryActionTitle: String {
        "Review Card Import"
    }

    mutating func reset() {
        sourcePath = ""
        destinationPath = ""
        organizeIntoDatedFolders = true
        secondCopyPath = ""
        errorMessage = nil
    }

    // A saved default only pre-fills an unset field; it never clobbers a
    // destination the caller already provided (e.g. restored from a draft).
    mutating func applyDefaultDestination(_ path: String) {
        guard !path.isEmpty else { return }
        destinationPath = path
    }

    @MainActor
    mutating func makeCardConfirmationDraft() throws -> ImportConfirmationDraft {
        let roots = try resolveCardURLs()
        return .card(
            source: roots.source,
            destinationRoot: roots.destinationRoot,
            destinationPolicy: destinationPolicy,
            secondCopyRootURL: roots.secondCopyRoot
        )
    }

    @MainActor
    mutating func resolveCardURLs() throws -> (source: URL, destinationRoot: URL, secondCopyRoot: URL?) {
        do {
            let sourceURL = try FolderSelectionPanel.importFolderURL(fromPath: sourcePath)
            let destinationURL = try FolderSelectionPanel.importFolderURL(fromPath: destinationPath)
            let secondCopyURL = trimmedSecondCopyPath.isEmpty
                ? nil
                : try FolderSelectionPanel.importFolderURL(fromPath: secondCopyPath)
            errorMessage = nil
            return (source: sourceURL, destinationRoot: destinationURL, secondCopyRoot: secondCopyURL)
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

    private var secondCopyDisplayName: String? {
        guard !trimmedSecondCopyPath.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmedSecondCopyPath, isDirectory: true).lastPathComponent
    }

    private var trimmedSecondCopyPath: String {
        secondCopyPath.trimmingCharacters(in: .whitespacesAndNewlines)
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
