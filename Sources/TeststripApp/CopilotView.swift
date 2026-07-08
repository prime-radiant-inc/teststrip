import SwiftUI
import TeststripCore

struct CopilotView: View {
    var model: AppModel
    var saveDynamicSet: () -> Void = {}
    var saveSnapshotSet: () -> Void = {}
    @State private var isAdvancedExpanded = false

    private var presentation: CopilotPresentation {
        CopilotPresentation(
            totalAssetCount: model.totalAssetCount,
            activeFilterChips: model.activeLibraryFilterChips,
            visibleWorkActivities: model.visibleWorkActivities,
            reviewQueueCounts: model.reviewQueueCounts,
            evaluationSummaries: model.catalogEvaluationKindSummaries,
            pendingMetadataSyncCount: model.pendingMetadataSyncCount,
            metadataSyncConflictCount: model.metadataSyncConflictCount,
            canRequestVisibleAssetEvaluations: model.canRequestVisibleAssetEvaluations,
            pendingProposalPickCount: model.pendingAutopilotProposals.filter { $0.kind == .pick || $0.kind == .reject }.count,
            pendingProposalKeywordCount: model.pendingAutopilotProposals.filter { $0.kind == .keyword }.count,
            detectedStackCount: model.autopilotVisibleStackCount,
            faceSuggestionCount: model.peopleFaceSuggestions.count,
            runningRecognitionCount: model.visibleWorkActivities.filter { $0.kind == .recognition && $0.status == .running }.count,
            suggestedName: model.suggestedSavedSearchName,
            canSaveDynamicSet: model.canSaveCurrentLibraryQuery,
            canSaveSnapshotSet: model.canSaveCurrentAssetScopeSnapshot
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                topPicksPanel
                needsEyesPanel
                DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        metricGrid
                        agentsPanel
                        if !presentation.scopeActions.isEmpty {
                            scopeActionsPanel
                        }
                        HStack(alignment: .top, spacing: 14) {
                            reviewPanel
                            signalPanel
                        }
                        activityPanel
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Advanced / Diagnostics")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.08))
        .liveMockupPlaceholder(.copilotLibrary)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.statusTitle)
                    .font(.title2.weight(.semibold))
                Text(presentation.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !presentation.readChips.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(presentation.readChips, id: \.self) { chip in
                            Text(chip)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            Spacer()
            if let primaryAction = presentation.primaryAction {
                Button {
                    perform(primaryAction.action)
                } label: {
                    Label(primaryAction.title, systemImage: primaryAction.systemImage)
                }
                .buttonStyle(.borderedProminent)
                .help(primaryAction.detail)
            }
        }
    }

    private var scopeActionsPanel: some View {
        panel(title: "Scope Actions", placeholderText: nil) {
            HStack(spacing: 10) {
                ForEach(presentation.scopeActions) { action in
                    Button {
                        perform(action.action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .help(action.detail)
                }
            }
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

    private var agentsPanel: some View {
        panel(title: "Agents", placeholderText: nil) {
            ForEach(presentation.agentRows) { row in
                agentRowView(row)
            }
        }
    }

    private func agentRowView(_ row: AutopilotAgentRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(row.isBusy ? Color.orange : Color.secondary)
                .frame(width: 28, height: 28)
                .background(Color.orange.opacity(row.isBusy ? 0.12 : 0.04), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.caption.weight(.semibold))
                Text(row.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(row.reviewCount)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(row.reviewCount > 0 ? .primary : .secondary)
            if agentHasRoute(row) {
                Button("Review") {
                    reviewAgent(row)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title): \(row.statusText)")
    }

    private func agentHasRoute(_ row: AutopilotAgentRow) -> Bool {
        switch row.id {
        case "culling", "auto-keywording", "face-grouping", "blur-eyes-closed":
            return row.reviewCount > 0
        default:
            return false
        }
    }

    private func reviewAgent(_ row: AutopilotAgentRow) {
        do {
            switch row.id {
            case "culling", "auto-keywording":
                try model.beginAutopilotReview()
            case "face-grouping":
                try model.selectSidebarTarget(.people)
            case "blur-eyes-closed":
                try model.selectSidebarTarget(.reviewQueue(.likelyIssues))
            default:
                break
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private var topPicksPanel: some View {
        panel(title: "Top Picks", placeholderText: nil) {
            ForEach(presentation.topPickRows) { row in
                actionRow(row)
            }
        }
    }

    private var needsEyesPanel: some View {
        panel(title: "Needs your eyes", placeholderText: nil) {
            ForEach(presentation.needsEyesRows) { row in
                actionRow(row)
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

    @ViewBuilder
    private func actionRow(_ row: CopilotActionRow) -> some View {
        if row.isActionEnabled {
            Button {
                select(row)
            } label: {
                actionRowContent(row)
            }
            .buttonStyle(.plain)
            .help("Open \(row.title)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(row.title), \(row.countText)")
            .accessibilityHint("Open \(row.title)")
        } else {
            actionRowContent(row)
                .help(row.statusText ?? row.detail)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.title), \(row.countText)")
                .accessibilityHint(row.statusText ?? row.detail)
        }
    }

    private func actionRowContent(_ row: CopilotActionRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(row.isActionEnabled ? Color.orange : Color.secondary)
                .frame(width: 28, height: 28)
                .background(Color.orange.opacity(row.isActionEnabled ? 0.12 : 0.04), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.caption.weight(.semibold))
                Text(row.isActionEnabled ? row.detail : (row.statusText ?? row.detail))
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
        .background(Color.black.opacity(row.isActionEnabled ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 7))
    }

    private func select(_ row: CopilotActionRow) {
        guard let target = row.target else { return }
        do {
            try model.selectSidebarTarget(target)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func perform(_ action: CopilotScopeAction) {
        switch action {
        case .saveDynamicSet:
            saveDynamicSet()
        case .saveSnapshotSet:
            saveSnapshotSet()
        }
    }

    private func perform(_ action: CopilotPrimaryAction) {
        do {
            switch action {
            case .open(let target):
                try model.selectSidebarTarget(target)
            case .evaluateVisibleAssets:
                try model.requestVisibleAssetEvaluations()
            }
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
    var statusText: String?
    var countText: String
    var systemImage: String
    var target: SidebarRowTarget?

    var isActionEnabled: Bool {
        target != nil
    }
}

enum CopilotPrimaryAction: Equatable {
    case open(SidebarRowTarget)
    case evaluateVisibleAssets
}

enum CopilotScopeAction: Equatable {
    case saveDynamicSet
    case saveSnapshotSet
}

struct CopilotPrimaryActionPresentation: Equatable {
    var title: String
    var detail: String
    var systemImage: String
    var action: CopilotPrimaryAction
}

struct CopilotScopeActionPresentation: Equatable, Identifiable {
    var action: CopilotScopeAction
    var title: String
    var detail: String
    var systemImage: String

    var id: String {
        switch action {
        case .saveDynamicSet:
            return "save-dynamic-set"
        case .saveSnapshotSet:
            return "save-snapshot-set"
        }
    }
}

struct AutopilotAgentRow: Equatable, Identifiable {
    var id: String
    var title: String
    var statusText: String
    var reviewCount: Int
    var isBusy: Bool
    var systemImage: String
}

struct CopilotPresentation: Equatable {
    var totalAssetCount: Int
    var activeFilterChips: [String]
    var visibleWorkActivities: [AppWorkActivity]
    var reviewQueueCounts: [ReviewQueue: Int]
    var evaluationSummaries: [CatalogEvaluationKindSummary]
    var pendingMetadataSyncCount: Int
    var metadataSyncConflictCount: Int
    var canRequestVisibleAssetEvaluations: Bool
    var pendingProposalPickCount: Int = 0
    var pendingProposalKeywordCount: Int = 0
    var detectedStackCount: Int = 0
    var faceSuggestionCount: Int = 0
    var runningRecognitionCount: Int = 0
    var suggestedName: String = "Current Scope"
    var canSaveDynamicSet: Bool = false
    var canSaveSnapshotSet: Bool = false

    var statusTitle: String {
        "REVIEW"
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

    // The output the photographer came for: their best shots, led with.
    var topPickRows: [CopilotActionRow] {
        [
            reviewRow(queue: .picks, detail: "Your flagged keepers"),
            reviewRow(queue: .potentialPicks, detail: "Ranked likely picks")
        ]
    }

    // Frames that still want a human look.
    var needsEyesRows: [CopilotActionRow] {
        [
            reviewRow(queue: .likelyIssues, detail: "Quality or source warnings"),
            reviewRow(queue: .needsEvaluation, detail: "Run Find Best Shots to analyze")
        ]
    }

    // Diagnostics-flavored queues, kept behind the Advanced disclosure.
    var reviewRows: [CopilotActionRow] {
        [
            reviewRow(queue: .needsKeywords, detail: "Missing keyword metadata"),
            reviewRow(queue: .facesFound, detail: "Face-count signals ready to review"),
            reviewRow(queue: .ocrFound, detail: "OCR text signals ready to review"),
            reviewRow(queue: .providerFailures, detail: "Evaluation jobs needing attention")
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

    // Honest projection of the named agents over REAL background state: pending
    // proposal counts, detected stacks, face suggestions, and running
    // recognition work. No theater — an idle agent reads "Idle" with a zero count.
    var agentRows: [AutopilotAgentRow] {
        let recognitionBusy = runningRecognitionCount > 0
        let likelyIssuesCount = reviewQueueCounts[.likelyIssues] ?? 0
        return [
            AutopilotAgentRow(
                id: "culling",
                title: "Culling",
                statusText: Self.agentStatusText(reviewCount: pendingProposalPickCount, reviewNoun: "proposed decisions to review", isBusy: recognitionBusy),
                reviewCount: pendingProposalPickCount,
                isBusy: recognitionBusy,
                systemImage: "checkmark.seal"
            ),
            AutopilotAgentRow(
                id: "auto-keywording",
                title: "Auto-keywording",
                statusText: Self.agentStatusText(reviewCount: pendingProposalKeywordCount, reviewNoun: "keyword suggestions to review", isBusy: recognitionBusy),
                reviewCount: pendingProposalKeywordCount,
                isBusy: recognitionBusy,
                systemImage: "tag"
            ),
            AutopilotAgentRow(
                id: "near-duplicate-stacking",
                title: "Near-duplicate stacking",
                statusText: Self.agentStatusText(reviewCount: detectedStackCount, reviewNoun: "stacks to review", isBusy: false),
                reviewCount: detectedStackCount,
                isBusy: false,
                systemImage: "square.stack.3d.down.right"
            ),
            AutopilotAgentRow(
                id: "face-grouping",
                title: "Face grouping",
                statusText: Self.agentStatusText(reviewCount: faceSuggestionCount, reviewNoun: "face groups to review", isBusy: false),
                reviewCount: faceSuggestionCount,
                isBusy: false,
                systemImage: "person.2.crop.square.stack.fill"
            ),
            AutopilotAgentRow(
                id: "blur-eyes-closed",
                title: "Blur & eyes-closed scan",
                statusText: Self.agentStatusText(reviewCount: likelyIssuesCount, reviewNoun: "flagged frames to review", isBusy: recognitionBusy),
                reviewCount: likelyIssuesCount,
                isBusy: recognitionBusy,
                systemImage: "eye.trianglebadge.exclamationmark"
            )
        ]
    }

    private static func agentStatusText(reviewCount: Int, reviewNoun: String, isBusy: Bool) -> String {
        if reviewCount > 0 {
            return "\(reviewCount) \(reviewNoun)"
        }
        if isBusy {
            return "Running…"
        }
        return "Idle"
    }

    var readChips: [String] {
        activeFilterChips.isEmpty ? ["All photographs"] : activeFilterChips
    }

    var scopeActions: [CopilotScopeActionPresentation] {
        var actions: [CopilotScopeActionPresentation] = []
        if canSaveDynamicSet {
            actions.append(CopilotScopeActionPresentation(
                action: .saveDynamicSet,
                title: "Save Dynamic Set",
                detail: "\(suggestedName) updates as the catalog changes",
                systemImage: "bookmark"
            ))
        }
        if canSaveSnapshotSet {
            actions.append(CopilotScopeActionPresentation(
                action: .saveSnapshotSet,
                title: totalAssetCount == 1 ? "Freeze 1 Result" : "Freeze \(totalAssetCount) Results",
                detail: "Capture this exact result set",
                systemImage: "camera.viewfinder"
            ))
        }
        return actions
    }

    var primaryAction: CopilotPrimaryActionPresentation? {
        if metadataSyncConflictCount > 0 {
            return CopilotPrimaryActionPresentation(
                title: "Review XMP Conflicts",
                detail: "\(metadataSyncConflictCount) metadata \(metadataSyncConflictCount == 1 ? "conflict" : "conflicts") need review",
                systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                action: .open(.metadataSyncConflicts)
            )
        }
        if (reviewQueueCounts[.providerFailures] ?? 0) > 0 {
            let count = reviewQueueCounts[.providerFailures] ?? 0
            return CopilotPrimaryActionPresentation(
                title: "Review Provider Failures",
                detail: "\(count) evaluation \(count == 1 ? "failure" : "failures") need attention",
                systemImage: "bolt.horizontal.circle",
                action: .open(.reviewQueue(.providerFailures))
            )
        }
        if (reviewQueueCounts[.likelyIssues] ?? 0) > 0 {
            let count = reviewQueueCounts[.likelyIssues] ?? 0
            return CopilotPrimaryActionPresentation(
                title: "Review Likely Issues",
                detail: "\(count) likely \(count == 1 ? "issue" : "issues") need review",
                systemImage: "exclamationmark.triangle",
                action: .open(.reviewQueue(.likelyIssues))
            )
        }
        if pendingMetadataSyncCount > 0 {
            return CopilotPrimaryActionPresentation(
                title: "Review XMP Pending",
                detail: "\(pendingMetadataSyncCount) metadata \(pendingMetadataSyncCount == 1 ? "write" : "writes") pending",
                systemImage: "arrow.triangle.2.circlepath",
                action: .open(.metadataSyncPending)
            )
        }
        if (reviewQueueCounts[.needsEvaluation] ?? 0) > 0 {
            let count = reviewQueueCounts[.needsEvaluation] ?? 0
            return CopilotPrimaryActionPresentation(
                title: "Review Needs Evaluation",
                detail: "\(count) \(count == 1 ? "photo" : "photos") without local signals",
                systemImage: "wand.and.stars",
                action: .open(.reviewQueue(.needsEvaluation))
            )
        }
        guard canRequestVisibleAssetEvaluations else { return nil }
        return CopilotPrimaryActionPresentation(
            title: "Run Local Signals",
            detail: "Evaluate loaded photos with local providers",
            systemImage: "sparkles",
            action: .evaluateVisibleAssets
        )
    }

    private var activeReviewCount: Int {
        reviewRows.reduce(0) { partialResult, row in
            partialResult + (Int(row.countText) ?? 0)
        }
    }

    private func reviewRow(queue: ReviewQueue, detail: String) -> CopilotActionRow {
        let count = reviewQueueCounts[queue] ?? 0
        let presentation = queue.presentation
        return CopilotActionRow(
            id: "review-\(queue.rawValue)",
            title: presentation.title,
            detail: detail,
            statusText: count == 0 ? reviewStatusText(for: queue) : nil,
            countText: String(count),
            systemImage: presentation.systemImage,
            target: count > 0 ? .reviewQueue(queue) : nil
        )
    }

    private func reviewStatusText(for queue: ReviewQueue) -> String {
        switch queue {
        case .needsKeywords:
            return "No photos missing keywords"
        case .needsEvaluation:
            return "All catalog photos have local signals"
        case .facesFound:
            return "No face signals recorded"
        case .ocrFound:
            return "No OCR text signals recorded"
        case .likelyIssues:
            return "No likely issues found"
        case .providerFailures:
            return "No provider failures recorded"
        default:
            return "No photos in this review queue"
        }
    }

    private var signalKindOrder: [EvaluationKind] {
        [.object, .focus, .ocrText, .faceCount, .faceQuality, .eyesOpen, .eyeSharpness, .smile, .motionBlur, .exposure, .aesthetics, .framing, .colorPalette, .novelty, .visualSimilarity]
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
        case .framing:
            return "Framing"
        case .visualSimilarity:
            return "Similarity"
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
        case .framing:
            return "crop"
        case .colorPalette:
            return "paintpalette"
        case .novelty:
            return "wand.and.stars"
        case .visualSimilarity:
            return "rectangle.3.group"
        case .smile:
            return "face.smiling"
        case .eyesOpen:
            return "eye"
        case .eyeSharpness:
            return "eye.circle"
        }
    }
}
