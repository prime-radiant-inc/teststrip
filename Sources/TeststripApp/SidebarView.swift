import SwiftUI
import TeststripCore

struct SidebarView: View {
    var model: AppModel
    @State private var renamingAssetSetID: AssetSetID?
    @State private var assetSetRenameText = ""
    @State private var duplicatingAssetSetID: AssetSetID?
    @State private var assetSetDuplicateName = ""
    @State private var assetSetDuplicateStarred = false
    @State private var freezingAssetSetID: AssetSetID?
    @State private var assetSetSnapshotName = ""
    @State private var assetSetSnapshotStarred = false
    @State private var deletingAssetSetID: AssetSetID?
    @State private var deletingAssetSetName = ""
    @State private var isShowingSourceReconnectSheet = false
    @State private var sourceReconnectDraft = SourceReconnectPathDraft()

    var body: some View {
        List {
            ForEach(model.sidebarSections) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        sidebarRowContent(row)
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
        .sheet(isPresented: isRenamingAssetSet) {
            RenameAssetSetSheet(
                name: $assetSetRenameText,
                cancel: cancelAssetSetRename,
                rename: saveAssetSetRename
            )
        }
        .sheet(isPresented: isDuplicatingAssetSet) {
            SaveAssetSetSheet(
                title: "Duplicate Set",
                actionTitle: "Create",
                name: $assetSetDuplicateName,
                starred: $assetSetDuplicateStarred,
                cancel: cancelAssetSetDuplicate,
                save: saveAssetSetDuplicate
            )
        }
        .sheet(isPresented: isFreezingAssetSetSnapshot) {
            SaveAssetSetSheet(
                title: "Freeze Snapshot",
                actionTitle: "Create",
                name: $assetSetSnapshotName,
                starred: $assetSetSnapshotStarred,
                cancel: cancelAssetSetSnapshot,
                save: saveAssetSetSnapshot
            )
        }
        .sheet(isPresented: $isShowingSourceReconnectSheet) {
            SourceReconnectSheet(
                draft: $sourceReconnectDraft,
                isImporting: model.isImporting,
                cancel: cancelSourceReconnect,
                reconnect: reconnectSourceRoot
            )
        }
        .confirmationDialog("Delete Set?", isPresented: isDeletingAssetSet, titleVisibility: .visible) {
            Button("Delete Set", role: .destructive) {
                confirmAssetSetDelete()
            }
            Button("Cancel", role: .cancel) {
                cancelAssetSetDelete()
            }
        } message: {
            Text(assetSetDeleteMessage)
        }
    }

    private var isRenamingAssetSet: Binding<Bool> {
        Binding(
            get: { renamingAssetSetID != nil },
            set: { isPresented in
                if !isPresented {
                    cancelAssetSetRename()
                }
            }
        )
    }

    private var isDuplicatingAssetSet: Binding<Bool> {
        Binding(
            get: { duplicatingAssetSetID != nil },
            set: { isPresented in
                if !isPresented {
                    cancelAssetSetDuplicate()
                }
            }
        )
    }

    private var isFreezingAssetSetSnapshot: Binding<Bool> {
        Binding(
            get: { freezingAssetSetID != nil },
            set: { isPresented in
                if !isPresented {
                    cancelAssetSetSnapshot()
                }
            }
        )
    }

    private var isDeletingAssetSet: Binding<Bool> {
        Binding(
            get: { deletingAssetSetID != nil },
            set: { isPresented in
                if !isPresented {
                    cancelAssetSetDelete()
                }
            }
        )
    }

    private var assetSetDeleteMessage: String {
        let name = deletingAssetSetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = name.isEmpty ? "this saved set" : "\"\(name)\""
        return "This removes \(target) from Teststrip. Photos, originals, metadata, and XMP sidecars stay untouched. Work history that references this set may no longer reopen it."
    }

    private func select(_ row: SidebarRow) {
        if case .sourceBookmarkRepair(let path) = row.target {
            showSourceReconnectSheet(oldRootPath: path)
            return
        }
        do {
            try model.selectSidebarRow(row)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func toggleFolderExpansion(_ row: SidebarRow) {
        guard case .folder(let path) = row.target else { return }
        model.toggleFolderExpansion(path: path)
    }

    // Folders-sidebar tree rows need an expand/collapse control that's
    // independent of the row's own selection tap target, so the disclosure
    // triangle is a sibling button rather than nested inside the selection
    // Button - nesting an interactive control inside a Button's label
    // doesn't produce two separately tappable areas. Every other section's
    // rows (depth 0, no disclosure) render exactly as before: a single plain
    // Button with no extra wrapper, so this introduces no layout change
    // outside the Folders section.
    @ViewBuilder
    private func sidebarRowContent(_ row: SidebarRow) -> some View {
        if row.depth == 0, row.disclosure == .none {
            sidebarRowButton(row)
        } else {
            HStack(spacing: 4) {
                folderDisclosureControl(for: row)
                sidebarRowButton(row)
            }
            .padding(.leading, CGFloat(row.depth) * 14)
        }
    }

    private func sidebarRowButton(_ row: SidebarRow) -> some View {
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
    }

    @ViewBuilder
    private func folderDisclosureControl(for row: SidebarRow) -> some View {
        switch row.disclosure {
        case .none:
            Color.clear.frame(width: 12, height: 12)
        case .collapsed, .expanded:
            Button {
                toggleFolderExpansion(row)
            } label: {
                Image(systemName: row.disclosure == .expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.disclosure == .expanded ? "Collapse \(row.title)" : "Expand \(row.title)")
        }
    }

    @ViewBuilder
    private func sidebarContextMenu(for row: SidebarRow) -> some View {
        ForEach(model.sidebarContextActions(for: row)) { action in
            Button {
                performSidebarContextAction(action, row: row)
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
        }
    }

    private func performSidebarContextAction(_ action: SidebarRowContextAction, row: SidebarRow) {
        if case .renameAssetSet(let id) = action.kind {
            renamingAssetSetID = id
            assetSetRenameText = row.title
            return
        }
        if case .duplicateAssetSet(let id) = action.kind {
            duplicatingAssetSetID = id
            assetSetDuplicateName = "Copy of \(row.title)"
            assetSetDuplicateStarred = false
            return
        }
        if case .freezeAssetSetSnapshot(let id) = action.kind {
            freezingAssetSetID = id
            assetSetSnapshotName = "\(row.title) Snapshot"
            assetSetSnapshotStarred = false
            return
        }
        if case .deleteAssetSet(let id) = action.kind {
            deletingAssetSetID = id
            deletingAssetSetName = row.title
            return
        }
        do {
            try model.performSidebarContextAction(action)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func saveAssetSetRename() {
        guard let renamingAssetSetID else { return }
        do {
            try model.renameAssetSet(id: renamingAssetSetID, to: assetSetRenameText)
            cancelAssetSetRename()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func cancelAssetSetRename() {
        renamingAssetSetID = nil
        assetSetRenameText = ""
    }

    private func saveAssetSetDuplicate() {
        guard let duplicatingAssetSetID else { return }
        do {
            try model.duplicateAssetSet(
                id: duplicatingAssetSetID,
                named: assetSetDuplicateName,
                starred: assetSetDuplicateStarred
            )
            cancelAssetSetDuplicate()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func cancelAssetSetDuplicate() {
        duplicatingAssetSetID = nil
        assetSetDuplicateName = ""
        assetSetDuplicateStarred = false
    }

    private func saveAssetSetSnapshot() {
        guard let freezingAssetSetID else { return }
        do {
            try model.freezeAssetSetSnapshot(
                id: freezingAssetSetID,
                named: assetSetSnapshotName,
                starred: assetSetSnapshotStarred
            )
            cancelAssetSetSnapshot()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func cancelAssetSetSnapshot() {
        freezingAssetSetID = nil
        assetSetSnapshotName = ""
        assetSetSnapshotStarred = false
    }

    private func confirmAssetSetDelete() {
        guard let deletingAssetSetID else { return }
        do {
            try model.deleteAssetSet(id: deletingAssetSetID)
            cancelAssetSetDelete()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func cancelAssetSetDelete() {
        deletingAssetSetID = nil
        deletingAssetSetName = ""
    }

    private func showSourceReconnectSheet(oldRootPath: String) {
        sourceReconnectDraft = SourceReconnectPathDraft(oldRootPath: oldRootPath)
        isShowingSourceReconnectSheet = true
    }

    private func reconnectSourceRoot() {
        do {
            let roots = try sourceReconnectDraft.resolveRootURLs()
            try model.reconnectSourceRoot(from: roots.oldRoot, to: roots.newRoot)
            cancelSourceReconnect()
        } catch {
            sourceReconnectDraft.recordError(error.localizedDescription)
            model.errorMessage = error.localizedDescription
        }
    }

    private func cancelSourceReconnect() {
        isShowingSourceReconnectSheet = false
        sourceReconnectDraft.reset()
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
        case .places:
            return "map"
        case .reviewQueue(let queue):
            return reviewQueueIconName(queue)
        case .folder:
            return "folder"
        case .sourceAvailability:
            return "externaldrive.badge.exclamationmark"
        case .sourceBookmarkRepair:
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

private struct RenameAssetSetSheet: View {
    @Binding var name: String
    var cancel: () -> Void
    var rename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Set")
                .font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            HStack {
                Spacer()
                Button("Cancel") {
                    cancel()
                }
                Button("Rename") {
                    rename()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
    }
}

private struct SaveAssetSetSheet: View {
    var title: String
    var actionTitle: String
    @Binding var name: String
    @Binding var starred: Bool
    var cancel: () -> Void
    var save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            Toggle("Starred", isOn: $starred)
            HStack {
                Spacer()
                Button("Cancel") {
                    cancel()
                }
                Button(actionTitle) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
    }
}
