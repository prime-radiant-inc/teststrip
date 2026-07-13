import SwiftUI
import TeststripCore

/// Toolbar-anchored popover consolidating background work, import progress,
/// source availability, and XMP sync conflicts into a single Activity
/// surface - replacing the former sidebar Sources/AI/Sync sections, the
/// inspector-pinned Activity panel, and the footer/top-inset import
/// progress/error rows.
struct ActivityCenterView: View {
    var model: AppModel
    @State private var isShowingSourceReconnectSheet = false
    @State private var sourceReconnectDraft = SourceReconnectPathDraft()

    var body: some View {
        let presentation = model.activityCenterPresentation
        VStack(alignment: .leading, spacing: 14) {
            if let importError = presentation.importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if !presentation.kindRows.isEmpty {
                kindRowsSection(presentation.kindRows)
            }
            if let pauseNotice = model.backgroundWorkPauseNotice {
                Text(pauseNotice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let idleWorkerStatusText = model.idleWorkerStatusText {
                idleWorkerRow(idleWorkerStatusText)
            }
            if !presentation.sources.isEmpty {
                sourcesSection(presentation.sources)
            }
            if !presentation.xmpConflicts.isEmpty {
                conflictsSection(presentation.xmpConflicts)
            }
            if isQuiet(presentation) {
                Text("No active work")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isShowingSourceReconnectSheet) {
            SourceReconnectSheet(
                draft: $sourceReconnectDraft,
                isImporting: model.isImporting,
                cancel: cancelSourceReconnect,
                reconnect: reconnectSourceRoot
            )
        }
    }

    private func isQuiet(_ presentation: ActivityCenterPresentation) -> Bool {
        presentation.kindRows.isEmpty
            && presentation.sources.allSatisfy { $0.availability == .online }
            && presentation.xmpConflicts.isEmpty
    }

    // MARK: - Kind rows

    private func kindRowsSection(_ rows: [ActivityKindRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(rows) { row in
                kindRow(row)
            }
        }
    }

    private func kindRow(_ row: ActivityKindRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let total = row.totalUnitCount {
                    ProgressView(value: Double(row.completedUnitCount), total: Double(max(total, 1)))
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(row.title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(label(for: row.status))
                    .font(.caption2)
                    .foregroundStyle(color(for: row.status))
                if row.canPause {
                    Button {
                        model.pauseWork(kind: row.kind)
                    } label: {
                        Image(systemName: "pause.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Pause background work")
                }
                if row.canResume {
                    Button {
                        model.resumeWork(kind: row.kind)
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Resume background work")
                }
                if row.canCancel {
                    Button {
                        if row.kind == .ingest {
                            model.cancelImportWork()
                        } else {
                            model.cancelWork(kind: row.kind)
                        }
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .help(row.kind == .ingest ? "Cancel import" : "Cancel this work item")
                }
            }
            Text(row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func label(for status: WorkSessionStatus) -> String {
        switch status {
        case .queued: "Queued"
        case .running: "Running"
        case .paused: "Paused"
        case .completed: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    private func color(for status: WorkSessionStatus) -> Color {
        switch status {
        case .queued, .running, .paused:
            .secondary
        case .completed:
            .green
        case .failed, .cancelled:
            .red
        }
    }

    // MARK: - Idle worker

    private func idleWorkerRow(_ statusText: String) -> some View {
        HStack(spacing: 6) {
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                model.stopIdleWorkerProcess()
            } label: {
                Image(systemName: "stop.circle")
            }
            .buttonStyle(.plain)
            .help("Stop idle worker")
        }
    }

    // MARK: - Sources

    private func sourcesSection(_ sources: [SourceStatusRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(sources) { source in
                HStack(spacing: 6) {
                    Text(source.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if source.availability != .online {
                        Text(source.availability.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if source.refreshActionID != nil {
                        Button {
                            refreshSourceAvailability()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .help("Refresh source availability")
                    }
                    if let reconnectActionID = source.reconnectActionID {
                        Button {
                            showSourceReconnectSheet(oldRootPath: reconnectActionID)
                        } label: {
                            Image(systemName: DesignGlyph.availabilityStale.symbolName)
                        }
                        .buttonStyle(.plain)
                        .help("Reconnect \(source.name)")
                    }
                }
            }
        }
    }

    private func refreshSourceAvailability() {
        do {
            try model.refreshVisibleAssetAvailability()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func showSourceReconnectSheet(oldRootPath: String) {
        sourceReconnectDraft = SourceReconnectPathDraft(oldRootPath: oldRootPath)
        isShowingSourceReconnectSheet = true
    }

    private func cancelSourceReconnect() {
        isShowingSourceReconnectSheet = false
    }

    private func reconnectSourceRoot() {
        do {
            let roots = try sourceReconnectDraft.resolveRootURLs()
            try model.reconnectSourceRoot(from: roots.oldRoot, to: roots.newRoot)
            isShowingSourceReconnectSheet = false
        } catch {
            sourceReconnectDraft.recordError(error.localizedDescription)
        }
    }

    // MARK: - XMP conflicts

    private func conflictsSection(_ conflicts: [ConflictRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("XMP Conflicts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(conflicts) { conflict in
                Button {
                    selectConflict(conflict)
                } label: {
                    Text(conflict.displayName)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func selectConflict(_ conflict: ConflictRow) {
        do {
            try model.revealConflicts([conflict.assetID])
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
