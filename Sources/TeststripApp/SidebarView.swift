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
                            SidebarRowView(
                                row: row,
                                systemImage: iconName(for: row.target)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!row.isSelectable)
                        .contextMenu {
                            sidebarContextMenu(for: row)
                        }
                        .liveMockupPlaceholder(row.liveMockupPlaceholder)
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

    @ViewBuilder
    private func sidebarContextMenu(for row: SidebarRow) -> some View {
        ForEach(model.sidebarContextActions(for: row)) { action in
            Button {
                performSidebarContextAction(action)
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
        }
    }

    private func performSidebarContextAction(_ action: SidebarRowContextAction) {
        do {
            try model.performSidebarContextAction(action)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func iconName(for target: SidebarRowTarget) -> String {
        switch target {
        case .allPhotographs:
            return "photo.on.rectangle"
        case .search:
            return "magnifyingglass"
        case .copilot:
            return "wand.and.stars"
        case .timeline:
            return "calendar"
        case .people:
            return "person.2"
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
        queue.presentation.systemImage
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

private struct SidebarRowView: View {
    var row: SidebarRow
    var systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let detailText = row.detailText, !detailText.isEmpty {
                    Text(detailText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if let countText = row.countText, !countText.isEmpty {
                Text(countText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .contentShape(Rectangle())
        .foregroundStyle(row.isSelectable ? .primary : .secondary)
        .opacity(row.isSelectable ? 1 : 0.62)
        .padding(.vertical, row.detailText == nil ? 3 : 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue(accessibilityValue)
    }

    private var tint: Color {
        switch row.tone {
        case .neutral:
            return .secondary
        case .accent:
            return .orange
        case .positive:
            return .green
        case .warning:
            return .yellow
        case .destructive:
            return .red
        }
    }

    private var accessibilityValue: String {
        [row.detailText, row.countText]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: ", ")
    }
}
