import Foundation

struct ImportConfirmationDraft: Equatable, Identifiable {
    enum Mode: Equatable {
        case folder
        case card
    }

    var mode: Mode
    var sourceURL: URL
    var destinationRootURL: URL?

    var id: String {
        [
            title,
            sourceURL.standardizedFileURL.path,
            destinationRootURL?.standardizedFileURL.path ?? ""
        ].joined(separator: "|")
    }

    static func folder(_ sourceURL: URL) -> ImportConfirmationDraft {
        ImportConfirmationDraft(mode: .folder, sourceURL: sourceURL)
    }

    static func card(source sourceURL: URL, destinationRoot destinationRootURL: URL) -> ImportConfirmationDraft {
        ImportConfirmationDraft(mode: .card, sourceURL: sourceURL, destinationRootURL: destinationRootURL)
    }

    var title: String {
        switch mode {
        case .folder:
            return "Import Folder"
        case .card:
            return "Import Card"
        }
    }

    var sourceName: String {
        sourceURL.lastPathComponent
    }

    var destinationName: String? {
        destinationRootURL?.lastPathComponent
    }

    var primaryActionTitle: String {
        switch mode {
        case .folder:
            return "Start Import"
        case .card:
            return "Start Card Import"
        }
    }

    var planSteps: [ImportPlanStep] {
        switch mode {
        case .folder:
            return ImportPlanSteps.folderInPlace
        case .card:
            return ImportPlanSteps.cardCopy(destinationName: destinationName ?? "the destination")
        }
    }
}
