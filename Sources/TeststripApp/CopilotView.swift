import SwiftUI
import TeststripCore

struct CopilotView: View {
    var model: AppModel

    private var presentation: CopilotPresentation {
        CopilotPresentation(
            totalAssetCount: model.totalAssetCount,
            activeFilterChips: model.activeLibraryFilterChips,
            visibleWorkActivities: model.visibleWorkActivities,
            reviewQueueCounts: model.reviewQueueCounts,
            evaluationSummaries: model.catalogEvaluationKindSummaries,
            pendingMetadataSyncCount: model.pendingMetadataSyncCount,
            metadataSyncConflictCount: model.metadataSyncConflictCount
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metricGrid
                HStack(alignment: .top, spacing: 14) {
                    reviewPanel
                    signalPanel
                }
                activityPanel
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.08))
        .liveMockupPlaceholder(.copilotLibrary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.statusTitle)
                .font(.title2.weight(.semibold))
            Text(presentation.statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 156), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(presentation.metricRows) { row in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: row.systemImage)
                            .foregroundStyle(row.tint)
                        Text(row.title)
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(row.value)
                        .font(.title3.monospacedDigit().weight(.semibold))
                    Text(row.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.07))
                }
            }
        }
    }

    private var reviewPanel: some View {
        panel(title: "Review Queues", placeholderText: nil) {
            ForEach(presentation.reviewRows) { row in
                actionRow(row)
            }
        }
    }

    private var signalPanel: some View {
        panel(title: "Local Signals", placeholderText: presentation.signalRows.isEmpty ? "No signal coverage yet" : nil) {
            ForEach(presentation.signalRows) { row in
                actionRow(row)
            }
        }
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ActivityView(model: model)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.07))
        }
    }

    private func panel<Content: View>(
        title: String,
        placeholderText: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            if let placeholderText {
                Text(placeholderText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.07))
        }
    }

    private func actionRow(_ row: CopilotActionRow) -> some View {
        Button {
            select(row)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: row.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(row.isActionEnabled ? Color.orange : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.orange.opacity(row.isActionEnabled ? 0.12 : 0.04), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.caption.weight(.semibold))
                    Text(row.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(row.countText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(row.isActionEnabled ? .primary : .secondary)
                if row.isActionEnabled {
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!row.isActionEnabled)
        .help(row.isActionEnabled ? "Open \(row.title)" : row.detail)
    }

    private func select(_ row: CopilotActionRow) {
        guard let target = row.target else { return }
        do {
            try model.selectSidebarTarget(target)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

struct CopilotMetricRow: Equatable, Identifiable {
    enum Tone: Equatable {
        case neutral
        case accent
        case warning
        case destructive
    }

    var id: String
    var title: String
    var value: String
    var detail: String
    var systemImage: String
    var tone: Tone

    var tint: Color {
        switch tone {
        case .neutral:
            return .secondary
        case .accent:
            return .orange
        case .warning:
            return .yellow
        case .destructive:
            return .red
        }
    }
}

struct CopilotActionRow: Equatable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var countText: String
    var systemImage: String
    var target: SidebarRowTarget?

    var isActionEnabled: Bool {
        target != nil
    }
}

struct CopilotPresentation: Equatable {
    var totalAssetCount: Int
    var activeFilterChips: [String]
    var visibleWorkActivities: [AppWorkActivity]
    var reviewQueueCounts: [ReviewQueue: Int]
    var evaluationSummaries: [CatalogEvaluationKindSummary]
    var pendingMetadataSyncCount: Int
    var metadataSyncConflictCount: Int

    var statusTitle: String {
        "TESTSTRIP COPILOT"
    }

    var statusDetail: String {
        if visibleWorkActivities.isEmpty,
           activeReviewCount == 0,
           evaluationSummaries.allSatisfy({ $0.assetCount == 0 }),
           pendingMetadataSyncCount == 0,
           metadataSyncConflictCount == 0 {
            return "Local evaluation, review queues, and background work are idle."
        }
        return "Local signals, review queues, and background work are ready for review."
    }

    var metricRows: [CopilotMetricRow] {
        let xmpIssueCount = pendingMetadataSyncCount + metadataSyncConflictCount
        return [
            CopilotMetricRow(
                id: "scope",
                title: "Scope",
                value: String(totalAssetCount),
                detail: "catalog photos",
                systemImage: "photo.on.rectangle",
                tone: .neutral
            ),
            CopilotMetricRow(
                id: "filters",
                title: "Filters",
                value: String(activeFilterChips.count),
                detail: activeFilterChips.isEmpty ? "current scope" : "active chips",
                systemImage: "line.3.horizontal.decrease.circle",
                tone: .accent
            ),
            CopilotMetricRow(
                id: "work",
                title: "Work",
                value: String(visibleWorkActivities.count),
                detail: visibleWorkActivities.isEmpty ? "idle" : "visible items",
                systemImage: "clock.arrow.circlepath",
                tone: visibleWorkActivities.isEmpty ? .neutral : .accent
            ),
            CopilotMetricRow(
                id: "xmp",
                title: "XMP",
                value: String(xmpIssueCount),
                detail: xmpIssueCount == 0 ? "synced" : "pending/conflict",
                systemImage: "arrow.triangle.2.circlepath",
                tone: metadataSyncConflictCount > 0 ? .destructive : (pendingMetadataSyncCount > 0 ? .warning : .neutral)
            )
        ]
    }

    var reviewRows: [CopilotActionRow] {
        [
            reviewRow(queue: .needsEvaluation, title: "Needs Evaluation", detail: "No persisted local signals", systemImage: "wand.and.stars"),
            reviewRow(queue: .likelyIssues, title: "Likely Issues", detail: "Quality or source warnings", systemImage: "exclamationmark.triangle"),
            reviewRow(queue: .providerFailures, title: "Provider Failures", detail: "Evaluation jobs needing attention", systemImage: "bolt.horizontal.circle")
        ]
    }

    var signalRows: [CopilotActionRow] {
        let summariesByKind = Dictionary(uniqueKeysWithValues: evaluationSummaries.map { ($0.kind, $0.assetCount) })
        return signalKindOrder.compactMap { kind in
            guard let count = summariesByKind[kind], count > 0 else { return nil }
            return CopilotActionRow(
                id: "signal-\(kind.rawValue)",
                title: signalTitle(for: kind),
                detail: "Persisted \(kind.displayName.lowercased()) signals",
                countText: String(count),
                systemImage: signalIcon(for: kind),
                target: .evaluationKind(kind)
            )
        }
    }

    private var activeReviewCount: Int {
        reviewRows.reduce(0) { partialResult, row in
            partialResult + (Int(row.countText) ?? 0)
        }
    }

    private func reviewRow(queue: ReviewQueue, title: String, detail: String, systemImage: String) -> CopilotActionRow {
        let count = reviewQueueCounts[queue] ?? 0
        return CopilotActionRow(
            id: "review-\(queue.rawValue)",
            title: title,
            detail: detail,
            countText: String(count),
            systemImage: systemImage,
            target: count > 0 ? .reviewQueue(queue) : nil
        )
    }

    private var signalKindOrder: [EvaluationKind] {
        [.object, .focus, .ocrText, .faceCount, .faceQuality, .motionBlur, .exposure, .aesthetics, .colorPalette, .novelty]
    }

    private func signalTitle(for kind: EvaluationKind) -> String {
        switch kind {
        case .object:
            return "Objects"
        case .ocrText:
            return "Text"
        case .faceCount:
            return "People"
        case .faceQuality:
            return "Faces"
        case .colorPalette:
            return "Color"
        default:
            return kind.displayName
        }
    }

    private func signalIcon(for kind: EvaluationKind) -> String {
        switch kind {
        case .object:
            return "tag"
        case .ocrText:
            return "text.viewfinder"
        case .faceCount:
            return "person.2"
        case .faceQuality:
            return "person.crop.circle"
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
