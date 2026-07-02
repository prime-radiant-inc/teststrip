import SwiftUI
import TeststripCore

struct LibraryGridView: View {
    var model: AppModel
    @State private var isSavingSearch = false
    @State private var isSavingManualSet = false
    @State private var savedSearchName = ""
    @State private var savedSearchStarred = false
    @State private var manualSetName = ""
    @State private var manualSetStarred = false
    @State private var isShowingDateFilters = false
    @State private var cullingFocusRequest = 0

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    private var isImporting: Bool {
        model.isImporting
    }

    var body: some View {
        Group {
            if model.assets.isEmpty {
                ScrollView {
                    emptyLibraryView
                }
            } else if model.selectedView == .loupe {
                LoupeView(model: model)
            } else if model.selectedView == .compare {
                CompareView(model: model, focusCullingSurface: focusCullingSurface)
            } else {
                ScrollView {
                    assetGrid
                }
            }
        }
        .navigationTitle("All Photographs")
        .toolbar {
            Picker("View", selection: Binding(
                get: { model.selectedView },
                set: { model.selectedView = $0 }
            )) {
                Label("Grid", systemImage: "square.grid.3x3.fill")
                    .tag(LibraryViewMode.grid)
                Label("Loupe", systemImage: "rectangle.inset.filled")
                    .tag(LibraryViewMode.loupe)
                Label("Compare", systemImage: "rectangle.grid.2x2")
                    .tag(LibraryViewMode.compare)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Button {
                showImportFolderPanel()
            } label: {
                Label("Import Folder", systemImage: "square.and.arrow.down")
            }
            .disabled(isImporting)

            Button {
                showImportCardPanel()
            } label: {
                Label("Import Card", systemImage: "externaldrive.badge.plus")
            }
            .disabled(isImporting)

            Button {
                evaluateSelectedAsset()
            } label: {
                Label("Evaluate", systemImage: "sparkles")
            }
            .disabled(isImporting || !model.canRequestSelectedAssetEvaluation)
            .help("Evaluate selected photo")
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                filterBar
                if isImporting {
                    importProgressBanner
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .overlay(alignment: .topLeading) {
            CullingKeyCaptureView(focusRequest: cullingFocusRequest, onShortcut: handleCullingShortcut)
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TextField("Search filenames", text: Binding(
                    get: { model.librarySearchText },
                    set: { model.librarySearchText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit {
                    applyLibraryFilters()
                }

                TextField("Camera", text: Binding(
                    get: { model.cameraFilterText },
                    set: { model.cameraFilterText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 116)
                .onSubmit {
                    applyLibraryFilters()
                }

                TextField("Lens", text: Binding(
                    get: { model.lensFilterText },
                    set: { model.lensFilterText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 116)
                .onSubmit {
                    applyLibraryFilters()
                }

                TextField("ISO+", text: minimumISOTextBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 66)
                    .onSubmit {
                        applyLibraryFilters()
                    }

                Button {
                    isShowingDateFilters = true
                } label: {
                    Image(systemName: "calendar")
                }
                .buttonStyle(.borderless)
                .help("Date filters")
                .popover(isPresented: $isShowingDateFilters) {
                    dateFilterPopover
                }

                Button {
                    applyLibraryFilters()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Search")

                Picker("Rating", selection: minimumRatingBinding) {
                    Text("Any Rating").tag(0)
                    ForEach(Array(1...5), id: \.self) { rating in
                        Text("\(rating)+").tag(rating)
                    }
                }
                .frame(width: 118)

                Picker("Flag", selection: flagFilterBinding) {
                    Text("Any Flag").tag("")
                    Text("Pick").tag(PickFlag.pick.rawValue)
                    Text("Reject").tag(PickFlag.reject.rawValue)
                }
                .frame(width: 112)

                if hasActiveFilters {
                    Button {
                        clearLibraryFilters()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear filters")
                }

                Button {
                    savedSearchName = model.suggestedSavedSearchName
                    savedSearchStarred = false
                    isSavingSearch = true
                } label: {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canSaveCurrentLibraryQuery)
                .help("Save search")
                .popover(isPresented: $isSavingSearch) {
                    saveSearchPopover
                }

                Button {
                    manualSetName = model.suggestedManualSetName
                    manualSetStarred = false
                    isSavingManualSet = true
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canSaveSelectedAssetAsManualSet)
                .help("Save selected photo as set")
                .popover(isPresented: $isSavingManualSet) {
                    saveManualSetPopover
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private var importProgressBanner: some View {
        HStack(spacing: 10) {
            importProgressIndicator
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(importActivity?.title ?? "Import photos")
                    .font(.caption.weight(.semibold))
                Text(importActivityDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let importActivity, let total = importActivity.totalUnitCount {
                Text("\(importActivity.completedUnitCount) of \(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button {
                cancelImport()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Cancel import")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    @ViewBuilder
    private var importProgressIndicator: some View {
        if let importActivity, let total = importActivity.totalUnitCount {
            ProgressView(value: Double(importActivity.completedUnitCount), total: Double(max(total, 1)))
                .frame(width: 96)
        } else {
            ProgressView()
        }
    }

    private var dateFilterPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("From", isOn: Binding(
                get: { model.captureDateStartFilter != nil },
                set: { isOn in
                    model.captureDateStartFilter = isOn ? Calendar.current.startOfDay(for: Date()) : nil
                }
            ))
            if model.captureDateStartFilter != nil {
                DatePicker("From", selection: Binding(
                    get: { model.captureDateStartFilter ?? Calendar.current.startOfDay(for: Date()) },
                    set: { date in
                        model.captureDateStartFilter = Calendar.current.startOfDay(for: date)
                    }
                ), displayedComponents: .date)
            }

            Toggle("Before", isOn: Binding(
                get: { model.captureDateEndFilter != nil },
                set: { isOn in
                    model.captureDateEndFilter = isOn ? Calendar.current.startOfDay(for: Date()) : nil
                }
            ))
            if model.captureDateEndFilter != nil {
                DatePicker("Before", selection: Binding(
                    get: { model.captureDateEndFilter ?? Calendar.current.startOfDay(for: Date()) },
                    set: { date in
                        model.captureDateEndFilter = Calendar.current.startOfDay(for: date)
                    }
                ), displayedComponents: .date)
            }

            HStack {
                Spacer()
                Button {
                    model.captureDateStartFilter = nil
                    model.captureDateEndFilter = nil
                    applyLibraryFilters()
                    isShowingDateFilters = false
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help("Clear date filters")
                Button {
                    applyLibraryFilters()
                    isShowingDateFilters = false
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut(.defaultAction)
                .help("Apply date filters")
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private var saveSearchPopover: some View {
        SaveSetPopover(
            title: "Save Search",
            name: $savedSearchName,
            starred: $savedSearchStarred,
            cancel: { isSavingSearch = false },
            save: saveCurrentSearch
        )
    }

    private var saveManualSetPopover: some View {
        SaveSetPopover(
            title: "Save Selection",
            name: $manualSetName,
            starred: $manualSetStarred,
            cancel: { isSavingManualSet = false },
            save: saveSelectedManualSet
        )
    }

    private struct SaveSetPopover: View {
        var title: String
        @Binding var name: String
        @Binding var starred: Bool
        var cancel: () -> Void
        var save: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                Toggle("Starred", isOn: $starred)
                HStack {
                    Spacer()
                    Button("Cancel") {
                        cancel()
                    }
                    Button("Save") {
                        save()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
    }

    private var minimumRatingBinding: Binding<Int> {
        Binding(
            get: { model.minimumRatingFilter ?? 0 },
            set: { value in
                model.minimumRatingFilter = value == 0 ? nil : value
                applyLibraryFilters()
            }
        )
    }

    private var flagFilterBinding: Binding<String> {
        Binding(
            get: { model.flagFilter?.rawValue ?? "" },
            set: { value in
                model.flagFilter = PickFlag(rawValue: value)
                applyLibraryFilters()
            }
        )
    }

    private var minimumISOTextBinding: Binding<String> {
        Binding(
            get: { model.minimumISOFilter.map(String.init) ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                model.minimumISOFilter = trimmed.isEmpty ? nil : Int(trimmed)
            }
        )
    }

    private var hasActiveFilters: Bool {
        model.hasActiveLibraryFilters
    }

    private var assetGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(model.assets, id: \.id.rawValue) { asset in
                AssetGridCell(
                    asset: asset,
                    previewURL: model.gridPreviewURL(for: asset.id),
                    previewCacheGeneration: model.previewCacheGeneration(for: asset.id),
                    isSelected: model.selectedAssetID == asset.id
                )
                .assetActivation(for: asset, model: model, focusCullingSurface: focusCullingSurface)
                .task(id: asset.id.rawValue) {
                    do {
                        try model.requestVisibleGridPreview(assetID: asset.id)
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .padding(12)
    }

    private var emptyLibraryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No photographs in this catalog")
                .font(.headline)
            Button {
                showImportFolderPanel()
            } label: {
                Label("Import Folder", systemImage: "square.and.arrow.down")
            }
            .disabled(isImporting)
            Button {
                showImportCardPanel()
            } label: {
                Label("Import Card", systemImage: "externaldrive.badge.plus")
            }
            .disabled(isImporting)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(32)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(model.libraryCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if isImporting {
                ProgressView()
                    .controlSize(.small)
                Text(importActivityDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button {
                    cancelImport()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Cancel import")
            } else if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.hasPreviousAssets {
                Button {
                    loadPreviousAssets()
                } label: {
                    Label("Load Previous", systemImage: "arrow.up.circle")
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(isImporting)
                .help("Load previous photo page")
            }
            if model.hasMoreAssets {
                Button {
                    loadMoreAssets()
                } label: {
                    Label("Load More", systemImage: "arrow.down.circle")
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(isImporting)
                .help("Load next photo page")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.bar)
    }

    private func showImportFolderPanel() {
        guard let folderURL = FolderSelectionPanel.chooseImportFolder() else { return }
        importFolder(folderURL)
    }

    private func showImportCardPanel() {
        guard let source = FolderSelectionPanel.chooseCardSourceFolder() else { return }
        guard let destinationRoot = FolderSelectionPanel.chooseCardDestinationFolder() else { return }
        importCard(source: source, destinationRoot: destinationRoot)
    }

    private func importFolder(_ folderURL: URL) {
        model.beginImportFolder(folderURL)
    }

    private func importCard(source: URL, destinationRoot: URL) {
        model.beginImportCard(source: source, destinationRoot: destinationRoot)
    }

    private var importActivity: AppWorkActivity? {
        model.visibleImportActivity
    }

    private var importActivityDetail: String {
        importActivity?.detail ?? "Importing"
    }

    private func cancelImport() {
        if model.activeWork?.kind == .ingest {
            model.cancelActiveWork()
        } else {
            model.cancelBackgroundWork()
        }
    }

    private func loadMoreAssets() {
        do {
            try model.loadMoreAssets()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func loadPreviousAssets() {
        do {
            try model.loadPreviousAssets()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func applyLibraryFilters() {
        do {
            try model.applyLibraryFilters()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func clearLibraryFilters() {
        do {
            try model.clearLibraryFilters()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func saveCurrentSearch() {
        do {
            try model.saveCurrentLibraryQuery(named: savedSearchName, starred: savedSearchStarred)
            isSavingSearch = false
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func saveSelectedManualSet() {
        do {
            try model.saveSelectedAssetAsManualSet(named: manualSetName, starred: manualSetStarred)
            isSavingManualSet = false
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func evaluateSelectedAsset() {
        do {
            try model.requestSelectedAssetEvaluations()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func focusCullingSurface() {
        cullingFocusRequest += 1
    }

    private func handleCullingShortcut(_ shortcut: CullingShortcut) {
        do {
            try model.applyCullingShortcut(shortcut)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct LoupeView: View {
    var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
            if let asset = model.selectedAsset {
                loupeContent(for: asset)
                    .task(id: asset.id.rawValue) {
                        do {
                            try model.requestVisibleLoupePreview(assetID: asset.id)
                        } catch {
                            model.errorMessage = error.localizedDescription
                        }
                    }
            } else {
                unavailableView(title: "No photo selected", systemImage: "photo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func loupeContent(for asset: Asset) -> some View {
        if let previewURL = model.loupePreviewURL(for: asset.id) {
            CachedPreviewImage(previewURL: previewURL, scaling: .fit, cacheGeneration: model.previewCacheGeneration(for: asset.id))
                .padding(16)
                .overlay(alignment: .bottomLeading) {
                    loupeOverlay(for: asset)
                }
        } else {
            unavailableView(title: "No cached preview", systemImage: "photo.badge.exclamationmark")
                .overlay(alignment: .bottomLeading) {
                    loupeOverlay(for: asset)
                }
        }
    }

    private func loupeOverlay(for asset: Asset) -> some View {
        HStack(spacing: 10) {
            Text(asset.originalURL.lastPathComponent)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Text("Rating: \(asset.metadata.rating)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let flag = asset.metadata.flag {
                Text(flag.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(flag == .pick ? .green : .red)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(12)
    }

    private func unavailableView(title: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CompareView: View {
    var model: AppModel
    var focusCullingSurface: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(model.compareAssets(), id: \.id.rawValue) { asset in
                    AssetGridCell(
                        asset: asset,
                        previewURL: model.loupePreviewURL(for: asset.id),
                        previewCacheGeneration: model.previewCacheGeneration(for: asset.id),
                        isSelected: model.selectedAssetID == asset.id
                    )
                    .assetActivation(for: asset, model: model, focusCullingSurface: focusCullingSurface)
                }
            }
            .padding(12)
        }
        .background(Color.black.opacity(0.24))
        .task(id: comparePreviewTaskID) {
            requestComparePreviews()
        }
    }

    private var comparePreviewTaskID: String {
        model.compareAssets().map(\.id.rawValue).joined(separator: "\n")
    }

    private func requestComparePreviews() {
        do {
            try model.requestVisibleComparePreviews()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    func assetActivation(for asset: Asset, model: AppModel, focusCullingSurface: @escaping () -> Void) -> some View {
        let doubleClick = TapGesture(count: 2).onEnded {
            focusCullingSurface()
            model.openAssetInLoupe(asset.id)
        }
        return Button {
            focusCullingSurface()
            model.select(asset.id)
        } label: {
            contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .simultaneousGesture(doubleClick)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(asset.originalURL.lastPathComponent)
            .accessibilityAction {
                model.select(asset.id)
            }
    }
}

private struct AssetGridCell: View {
    var asset: Asset
    var previewURL: URL?
    var previewCacheGeneration: Int
    var isSelected: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                thumbnail
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                metadataOverlay
                    .padding(6)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.orange, lineWidth: 2)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.gray.opacity(0.35))
            )
        }
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        CachedPreviewImage(previewURL: previewURL, scaling: .fill, cacheGeneration: previewCacheGeneration)
    }

    private var metadataOverlay: some View {
        HStack(spacing: 5) {
            if asset.metadata.flag == .pick {
                flagBadge(systemName: "flag.fill", color: .green)
            } else if asset.metadata.flag == .reject {
                flagBadge(systemName: "xmark", color: .red)
            }
            if asset.metadata.rating > 0 {
                Text(String(repeating: "★", count: asset.metadata.rating))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            if let colorLabel = asset.metadata.colorLabel {
                Circle()
                    .fill(color(for: colorLabel))
                    .frame(width: 8, height: 8)
            }
            Spacer(minLength: 0)
        }
    }

    private func flagBadge(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.black.opacity(0.75))
            .frame(width: 15, height: 15)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func color(for label: ColorLabel) -> Color {
        switch label {
        case .red: .red
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }
}
