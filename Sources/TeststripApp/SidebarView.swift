import SwiftUI
import TeststripCore

struct SidebarView: View {
    var model: AppModel

    var body: some View {
        List {
            ForEach(model.sidebarSections) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        Button {
                            select(row)
                        } label: {
                            Label(row.title, systemImage: iconName(for: row.target))
                        }
                        .buttonStyle(.plain)
                        .disabled(!row.isSelectable)
                    }
                }
            }
        }
        .frame(minWidth: 220)
        .navigationTitle("Teststrip")
    }

    private func select(_ row: SidebarRow) {
        do {
            try model.selectSidebarRow(row)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func iconName(for target: SidebarRowTarget) -> String {
        switch target {
        case .allPhotographs:
            return "photo.on.rectangle"
        case .reviewQueue(let queue):
            return reviewQueueIconName(queue)
        case .folder:
            return "folder"
        case .sourceAvailability:
            return "externaldrive.badge.exclamationmark"
        case .evaluationKind(let kind):
            return evaluationKindIconName(kind)
        case .metadataSyncPending:
            return "arrow.triangle.2.circlepath"
        case .metadataSyncConflicts:
            return "exclamationmark.triangle"
        case .assetSet:
            return "rectangle.stack"
        case .workSession:
            return "clock.arrow.circlepath"
        case .placeholder:
            return "circle"
        }
    }

    private func reviewQueueIconName(_ queue: ReviewQueue) -> String {
        switch queue {
        case .picks:
            return "flag.fill"
        case .rejects:
            return "xmark.circle"
        case .fiveStars:
            return "star.fill"
        case .needsKeywords:
            return "tag"
        }
    }

    private func evaluationKindIconName(_ kind: EvaluationKind) -> String {
        switch kind {
        case .faceCount:
            return "person.2"
        case .faceQuality:
            return "person.crop.circle"
        case .object:
            return "tag"
        case .ocrText:
            return "text.viewfinder"
        case .focus:
            return "scope"
        case .motionBlur:
            return "wind"
        case .exposure:
            return "sun.max"
        case .aesthetics:
            return "sparkles"
        case .colorPalette:
            return "paintpalette"
        case .novelty:
            return "wand.and.stars"
        }
    }
}
