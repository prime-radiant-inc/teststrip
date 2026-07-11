import SwiftUI
import TeststripCore

/// The Cull workspace's sidebar: a source picker (recent import, the Top
/// Picks / Needs Eyes review-queue groups, and the current Library
/// selection) on top, with the auto-grouped stack rows — formerly the
/// in-stage rail in LoupeView — below. The standard sidebar toggle
/// collapses this view the same as it does `SidebarView`.
struct CullSidebarView: View {
    var model: AppModel

    var body: some View {
        let presentation = model.cullSourcePresentation
        List {
            Section("Cull From") {
                if presentation.isEmpty {
                    Text("Nothing to cull")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sourceGroups, id: \.self) { group in
                        ForEach(sourcesByGroup(presentation)[group] ?? []) { source in
                            sourceRow(source)
                        }
                    }
                }
            }
            let stackEntries = model.cullingStackListEntries()
            if !stackEntries.isEmpty {
                Section("Stacks · Auto-Grouped") {
                    ForEach(stackEntries) { entry in
                        stackRow(entry)
                    }
                }
            }
        }
        .frame(minWidth: 220)
    }

    // Diagnostics folds into the same list as every other group: these rows
    // (Rejects, Five Stars, Needs Keywords, Faces Found, OCR Found, Provider
    // Failures) are click-to-cull review queues, not background-job status,
    // so they belong beside Top Picks/Needs Eyes rather than in the Activity
    // popover.
    private var sourceGroups: [CullSourceGroup] {
        [.recentImport, .autopilotProposals, .topPicks, .needsEyes, .diagnostics, .selection]
    }

    private func sourcesByGroup(_ presentation: CullSourcePresentation) -> [CullSourceGroup: [CullSource]] {
        Dictionary(grouping: presentation.visibleSources, by: \.group)
    }

    private func sourceRow(_ source: CullSource) -> some View {
        Button {
            activate(source)
        } label: {
            HStack {
                Label(source.title, systemImage: source.systemImage)
                Spacer()
                Text(String(source.count))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func activate(_ source: CullSource) {
        do {
            try model.activateCullSource(source.target)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func stackRow(_ entry: CullingStackListEntry) -> some View {
        Button {
            do {
                try model.selectCullingStackSet(id: entry.setID)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.55))
                    if let previewURL = model.gridPreviewURL(for: entry.leadAssetID) {
                        CachedPreviewImage(
                            previewURL: previewURL,
                            scaling: .fit,
                            cacheGeneration: model.previewCacheGeneration(for: entry.leadAssetID)
                        )
                    } else {
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 36, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(entry.frameCountText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if entry.isDecided {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .listRowBackground(entry.isSelected ? Color.orange.opacity(0.18) : Color.clear)
        .accessibilityLabel(entry.title)
        .accessibilityValue(entry.isDecided ? "Decided" : "Undecided")
    }
}
