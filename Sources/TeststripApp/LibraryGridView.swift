import AppKit
import SwiftUI
import TeststripCore

struct LibraryGridView: View {
    var model: AppModel
    @State private var isSavingSearch = false
    @State private var isSavingManualSet = false
    @State private var isSavingSnapshotSet = false
    @State private var isStartingCullingSession = false
    @State private var isReviewingBatchMetadata = false
    @State private var isShowingSourceReconnectSheet = false
    @State private var savedSearchName = ""
    @State private var savedSearchStarred = false
    @State private var savedSearchRuleText = ""
    @State private var manualSetName = ""
    @State private var manualSetStarred = false
    @State private var snapshotSetName = ""
    @State private var snapshotSetStarred = false
    @State private var cullingSessionName = ""
    @State private var cullingSessionIntent = ""
    @State private var batchMetadataDraft = BatchMetadataDraft()
    @State private var batchMetadataScope: BatchScopeMode = .visible
    @State private var isAllCatalogBatchMetadataConfirmed = false
    @State private var isReviewingExport = false
    @State private var exportScope: BatchScopeMode = .visible
    @State private var exportPreset: ExportPreset = .fullResolutionJPEG
    @State private var isAllCatalogExportConfirmed = false
    @State private var includeSourceMetadataInExport = true
    @State private var isShowingDateFilters = false
    @State private var isShowingImportPathSheet = false
    @State private var isShowingImportCardPathSheet = false
    @State private var dismissedImportCompletionSummaryID: String?
    @State private var importIssueReview: ImportIssueReview?
    @State private var importPathDraft = ImportFolderPathDraft()
    @State private var importCardPathDraft = ImportCardPathDraft()
    @State private var isReviewingImportPath = false
    @State private var isReviewingImportCardPath = false
    @State private var importPathReviewID: UUID?
    @State private var importCardPathReviewID: UUID?
    @State private var importConfirmationDraft: ImportConfirmationDraft?
    @State private var sourceReconnectDraft = SourceReconnectPathDraft()
    @State private var cullingFocusRequest = 0
    @State private var suppressedSelectionScrollAssetID: String?
    @AppStorage("LibraryGridView.thumbnailWidth") private var storedThumbnailWidth = LibraryGridLayout.defaultThumbnailWidth

    private var gridLayout: LibraryGridLayout {
        LibraryGridLayout(thumbnailWidth: storedThumbnailWidth)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: gridLayout.gridItemMinimumWidth), spacing: gridLayout.gridSpacing)]
    }

    private var isImporting: Bool {
        model.isImporting
    }

    var body: some View {
        Group {
            if model.selectedView == .people {
                PeopleView(model: model)
            } else if model.selectedView == .copilot {
                CopilotView(
                    model: model,
                    saveDynamicSet: showSaveSearchPopover,
                    saveSnapshotSet: showSaveSnapshotSetPopover
                )
            } else if model.selectedView == .search {
                SearchWorkspaceView(
                    model: model,
                    assetGrid: AnyView(assetGrid),
                    saveDynamicSet: showSaveSearchPopover,
                    saveSnapshotSet: showSaveSnapshotSetPopover,
                    startCulling: showStartCullingPopover
                )
            } else if model.selectedView == .timeline {
                TimelineWorkspaceView(
                    model: model,
                    columns: columns,
                    focusCullingSurface: focusCullingSurface
                ) { assetID in
                    selectAssetFromGrid(assetID)
                }
            } else if model.assets.isEmpty {
                ScrollView {
                    emptyLibraryView
                }
            } else if model.selectedView == .loupe {
                LoupeView(model: model)
            } else if model.selectedView == .compare {
                CompareView(model: model, focusCullingSurface: focusCullingSurface)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        assetGrid
                    }
                    .onChange(of: model.selectedAssetID?.rawValue) { _, selectedAssetID in
                        handleSelectedAssetChange(selectedAssetID, with: proxy)
                    }
                }
            }
        }
        .navigationTitle(model.libraryTitle)
        .toolbar {
            Button {
                showStartCullingPopover()
            } label: {
                Label("Cull", systemImage: "checkmark.seal")
            }
            .disabled(isImporting || !model.canBeginCullingSession)
            .help("Start culling session")
            .popover(isPresented: $isStartingCullingSession) {
                cullingSessionPopover
            }

            Button {
                showImportFolderPanel()
            } label: {
                Label("Import Folder", systemImage: "square.and.arrow.down")
            }
            .disabled(isImporting)

            Button {
                showImportPathSheet()
            } label: {
                Label("Import Path", systemImage: "folder.badge.plus")
            }
            .disabled(isImporting)
            .help("Import a folder by path")

            Button {
                showPrimaryCardImportRoute()
            } label: {
                Label("Import Card", systemImage: "externaldrive.badge.plus")
            }
            .disabled(isImporting)

            Button {
                showSourceReconnectSheet()
            } label: {
                Label("Reconnect Sources", systemImage: "externaldrive")
            }
            .disabled(isImporting || !model.canReconnectSourceRoot)
            .help("Reconnect moved or mounted source roots")

            Button {
                evaluateSelectedAsset()
            } label: {
                Label("Evaluate", systemImage: "sparkles")
            }
            .disabled(isImporting || !model.canRequestSelectedAssetEvaluation)
            .help("Evaluate selected photo")

            Button {
                evaluateVisibleAssets()
            } label: {
                Label("Evaluate Visible", systemImage: "sparkles")
            }
            .disabled(isImporting || !model.canRequestVisibleAssetEvaluations)
            .help("Evaluate visible photos")

            Button {
                evaluateCurrentScopeAssets()
            } label: {
                Label("Evaluate Scope", systemImage: "sparkles.rectangle.stack")
            }
            .disabled(isImporting || !model.canRequestCurrentScopeAssetEvaluations)
            .help("Evaluate cached photos in the current search, set, or filter scope")

            Button {
                batchMetadataDraft = BatchMetadataDraft()
                batchMetadataScope = model.selectedBatchAssetCount > 0 ? .selected : .visible
                isAllCatalogBatchMetadataConfirmed = false
                isReviewingBatchMetadata = true
            } label: {
                Label("Batch Metadata", systemImage: "tag")
            }
            .disabled(isImporting || model.assets.isEmpty)
            .help("Review visible batch metadata")
            .popover(isPresented: $isReviewingBatchMetadata) {
                batchMetadataPopover
            }
            .liveMockupPlaceholder(.keywordingBatch)

            Button {
                exportScope = model.selectedBatchAssetCount > 0 ? .selected : .visible
                isAllCatalogExportConfirmed = false
                isReviewingExport = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(isImporting || model.assets.isEmpty || model.isExporting)
            .help("Export JPEG copies to a folder")
            .popover(isPresented: $isReviewingExport) {
                exportPopover
            }
        }
        .safeAreaInset(edge: .top) {
            topInsetContent
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .sheet(isPresented: $isShowingImportPathSheet) {
            importPathSheet
        }
        .sheet(isPresented: $isShowingImportCardPathSheet) {
            importCardPathSheet
        }
        .sheet(item: $importConfirmationDraft) { draft in
            importConfirmationSheet(draft)
        }
        .sheet(item: $importIssueReview) { review in
            importIssueReviewSheet(review)
        }
        .sheet(isPresented: $isShowingSourceReconnectSheet) {
            sourceReconnectSheet
        }
        .overlay(alignment: .topLeading) {
            CullingKeyCaptureView(focusRequest: cullingFocusRequest, onShortcut: handleCullingShortcut)
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }
    }

    private var thumbnailSizeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { gridLayout.thumbnailWidth },
                    set: { storedThumbnailWidth = LibraryGridLayout.clampedThumbnailWidth($0) }
                ),
                in: LibraryGridLayout.minimumThumbnailWidth...LibraryGridLayout.maximumThumbnailWidth,
                step: 8
            ) {
                Text("Thumbnail Size")
            }
            .frame(width: 120)
            .accessibilityLabel("Thumbnail Size")
            .accessibilityValue(gridLayout.accessibilityValue)
            Image(systemName: "rectangle.grid.1x2")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help("Thumbnail size: \(gridLayout.accessibilityValue)")
    }

    private var thumbnailDensityControl: some View {
        HStack(spacing: 2) {
            ForEach(gridLayout.footerDensityControls) { control in
                Button {
                    storedThumbnailWidth = control.thumbnailWidth
                } label: {
                    Text(control.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(control.isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .frame(height: 22)
                        .background(
                            control.isSelected ? Color.white.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .help("\(control.title) grid density")
                .accessibilityLabel(control.title)
                .accessibilityValue(control.isSelected ? "Selected" : "Not selected")
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Grid Density")
    }

    private var libraryTopBar: some View {
        let presentation = LibraryTopBarPresentation(
            catalogTitle: model.catalogDisplayName,
            libraryTitle: model.libraryTitle,
            libraryCountText: model.libraryCountText,
            selectedView: model.selectedView,
            activeFilterChips: model.activeLibraryFilterChips
        )
        return HStack(spacing: 12) {
            topBarCatalogIdentity(presentation)
            Divider()
                .frame(height: 26)
            topBarBreadcrumb(presentation)
            Spacer(minLength: 12)
            topBarSearchField
            topBarViewSwitcher(presentation)
            Button {
                showImportFolderPanel()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
            .disabled(isImporting)
            .help("Import folder")
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor).opacity(0.92),
                    Color.black.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
        .liveMockupPlaceholder(.topChrome)
    }

    private func topBarCatalogIdentity(_ presentation: LibraryTopBarPresentation) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.catalogTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(presentation.catalogSubtitle)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 174, alignment: .leading)
    }

    private func topBarBreadcrumb(_ presentation: LibraryTopBarPresentation) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(presentation.breadcrumbItems.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(item)
                    .font(.caption.weight(index == presentation.breadcrumbItems.count - 1 ? .semibold : .regular))
                    .foregroundStyle(index == presentation.breadcrumbItems.count - 1 ? .primary : .secondary)
                    .lineLimit(1)
            }
            if let filterSummaryText = presentation.filterSummaryText {
                Text(filterSummaryText)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .frame(minWidth: 160, alignment: .leading)
    }

    private var topBarSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            TextField("Ask Teststrip or search...", text: Binding(
                get: { model.librarySearchText },
                set: { model.librarySearchText = $0 }
            ))
            .textFieldStyle(.plain)
            .onSubmit {
                applyLibraryFilters()
            }
            .accessibilityLabel("Top Search Catalog")
            Button {
                applyLibraryFilters()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Search")
        }
        .padding(.horizontal, 10)
        .frame(width: 262, height: 31)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.09))
        }
        .liveMockupPlaceholder(.agenticSearch)
    }

    private func topBarViewSwitcher(_ presentation: LibraryTopBarPresentation) -> some View {
        HStack(spacing: 2) {
            ForEach(presentation.modeItems) { item in
                topBarModeButton(item)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library View")
    }

    private func topBarModeButton(_ item: LibraryTopBarModeItem) -> some View {
        let isSelected = model.selectedView == item.mode
        return Button {
            model.selectedView = item.mode
        } label: {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 30, height: 26)
                .background(isSelected ? Color.white.opacity(0.11) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .liveMockupPlaceholder(item.liveMockupPlaceholder)
    }

    @ViewBuilder
    private var topInsetContent: some View {
        VStack(spacing: 0) {
            libraryTopBar
            if model.selectedView == .grid || model.selectedView == .search || model.selectedView == .timeline {
                filterBar
            }
            if LibraryGridChromePolicy.shouldShowImportProgressBanner(
                isImporting: isImporting,
                visibleAssetCount: model.assets.count
            ) {
                importProgressBanner
            } else if let summary = visibleImportCompletionSummary {
                importCompletionSummary(summary)
            }
        }
    }

    private var visibleImportCompletionSummary: ImportCompletionSummary? {
        guard let summary = model.latestImportCompletionSummary else { return nil }
        guard LibraryGridChromePolicy.shouldShowImportCompletionSummary(
            isImporting: isImporting,
            summaryID: summary.id,
            dismissedSummaryID: dismissedImportCompletionSummaryID
        ) else {
            return nil
        }
        return summary
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    searchControl

                    librarySortPicker

                    filterTextField(
                        "Keyword",
                        text: Binding(
                            get: { model.keywordFilterText },
                            set: { model.keywordFilterText = $0 }
                        ),
                        width: 96
                    )

                    filterTextField(
                        "Folder",
                        text: Binding(
                            get: { model.folderFilterText },
                            set: { model.folderFilterText = $0 }
                        ),
                        width: 128
                    )

                    filterTextField(
                        "Camera",
                        text: Binding(
                            get: { model.cameraFilterText },
                            set: { model.cameraFilterText = $0 }
                        ),
                        width: 96
                    )

                    filterTextField(
                        "Lens",
                        text: Binding(
                            get: { model.lensFilterText },
                            set: { model.lensFilterText = $0 }
                        ),
                        width: 96
                    )

                    filterTextField("ISO+", text: minimumISOTextBinding, width: 48)

                    dateFilterButton

                    ratingFilterPicker

                    flagFilterPicker

                    colorLabelFilterPicker

                    sourceFilterPicker

                    signalFilterPicker

                    metadataSyncFilterPicker

                    if LibraryGridChromePolicy.shouldShowPendingMetadataSyncRetryAction(
                        isPendingFilterActive: model.metadataSyncPendingFilter
                    ) {
                        Button {
                            retryPendingMetadataSync()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderless)
                        .disabled(LibraryGridChromePolicy.isPendingMetadataSyncRetryActionDisabled(
                            isImporting: isImporting,
                            canRetry: model.canRetryPendingMetadataSyncInCurrentScope
                        ))
                        .help("Retry pending XMP sync in current results")
                    }

                    Button {
                        refreshVisibleAvailability()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!model.canRefreshVisibleAssetAvailability)
                    .help("Refresh source status")

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
                        showSaveSearchPopover()
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!model.canSaveCurrentLibraryQuery)
                    .help("Save search")
                    .popover(isPresented: $isSavingSearch) {
                        saveSearchPopover
                    }
                    .liveMockupPlaceholder(.smartCollectionsBuilder)

                    Button {
                        showSaveSnapshotSetPopover()
                    } label: {
                        Image(systemName: "camera.viewfinder")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!model.canSaveCurrentAssetScopeSnapshot)
                    .help("Save current results as snapshot")
                    .popover(isPresented: $isSavingSnapshotSet) {
                        saveSnapshotSetPopover
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
                    .help("Save selected photos as set")
                    .popover(isPresented: $isSavingManualSet) {
                        saveManualSetPopover
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            if !model.activeLibraryFilterChips.isEmpty {
                activeFilterChips
            }
            currentBatchKeywordSuggestionBar
        }
        .padding(.bottom, 7)
        .background(.bar)
        .liveMockupPlaceholder(.searchRefine)
    }

    private var searchControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            TextField("Ask Teststrip or search...", text: Binding(
                get: { model.librarySearchText },
                set: { model.librarySearchText = $0 }
            ))
            .textFieldStyle(.plain)
            .frame(width: 210)
            .onSubmit {
                applyLibraryFilters()
            }
            .accessibilityLabel("Search catalog")
            Button {
                applyLibraryFilters()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Search")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.25))
        }
        .liveMockupPlaceholder(.agenticSearch)
    }

    private var librarySortPicker: some View {
        Picker("Sort", selection: librarySortBinding) {
            ForEach(LibrarySortOptionPresentation.options(selected: model.librarySortOption), id: \.option) { option in
                Text("\(option.title): \(option.subtitle)").tag(option.option)
            }
        }
        .frame(width: 158)
        .controlSize(.small)
        .help("Sort library")
    }

    private func filterTextField(_ title: String, text: Binding<String>, width: CGFloat) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .frame(width: width)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(.quaternary)
            }
            .onSubmit {
                applyLibraryFilters()
            }
            .accessibilityLabel(title)
    }

    private var dateFilterButton: some View {
        Button {
            isShowingDateFilters = true
        } label: {
            Image(systemName: "calendar")
                .frame(width: 20)
        }
        .buttonStyle(.borderless)
        .help("Date filters")
        .popover(isPresented: $isShowingDateFilters) {
            dateFilterPopover
        }
    }

    private var ratingFilterPicker: some View {
        Picker("Rating", selection: minimumRatingBinding) {
            Text("Any Rating").tag(0)
            ForEach(Array(1...5), id: \.self) { rating in
                Text("\(rating)+").tag(rating)
            }
        }
        .frame(width: 112)
        .controlSize(.small)
    }

    private var flagFilterPicker: some View {
        Picker("Flag", selection: flagFilterBinding) {
            Text("Any Flag").tag("")
            Text("Pick").tag(PickFlag.pick.rawValue)
            Text("Reject").tag(PickFlag.reject.rawValue)
        }
        .frame(width: 104)
        .controlSize(.small)
    }

    private var colorLabelFilterPicker: some View {
        Picker("Label", selection: colorLabelFilterBinding) {
            Text("Any Label").tag("")
            ForEach(ColorLabel.allCases, id: \.self) { label in
                Text(label.rawValue.capitalized).tag(label.rawValue)
            }
        }
        .frame(width: 116)
        .controlSize(.small)
    }

    private var sourceFilterPicker: some View {
        Picker("Source", selection: availabilityFilterBinding) {
            Text("Any Source").tag("")
            ForEach(availabilityFilterOptions, id: \.rawValue) { availability in
                Text(availability.rawValue.capitalized).tag(availability.rawValue)
            }
        }
        .frame(width: 118)
        .controlSize(.small)
    }

    private var signalFilterPicker: some View {
        Picker("Signal", selection: evaluationKindFilterBinding) {
            Text("Any Signal").tag("")
            ForEach(evaluationKindFilterOptions, id: \.rawValue) { kind in
                Text(kind.displayName).tag(kind.rawValue)
            }
        }
        .frame(width: 130)
        .controlSize(.small)
    }

    private var metadataSyncFilterPicker: some View {
        Picker("XMP", selection: metadataSyncFilterBinding) {
            Text("Any XMP").tag(MetadataSyncFilterOption.any.rawValue)
            Text("Pending").tag(MetadataSyncFilterOption.pending.rawValue)
            Text("Conflicts").tag(MetadataSyncFilterOption.conflicts.rawValue)
        }
        .frame(width: 112)
        .controlSize(.small)
    }

    private var activeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("TESTSTRIP READS")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.orange)
                ForEach(model.activeLibraryFilterRows) { row in
                    Button {
                        removeActiveLibraryFilter(row)
                    } label: {
                        HStack(spacing: 5) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title)
                                    .lineLimit(1)
                                if row.isPlainSearchFallback {
                                    Text("Plain search fallback")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.orange.opacity(0.18))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        row.isPlainSearchFallback
                            ? "Remove plain search fallback filter \(row.title)"
                            : "Remove filter \(row.title)"
                    )
                    .help("Remove \(row.title) filter")
                }
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private var currentBatchKeywordSuggestionBar: some View {
        let rows = BatchKeywordSuggestionPresentation.rows(for: model.visibleBatchKeywordSuggestions)
        if !rows.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Image(systemName: "tag")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("TESTSTRIP SUGGESTS")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.orange)
                    ForEach(rows) { row in
                        Button {
                            applyVisibleBatchKeywordSuggestion(row.keyword)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(row.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.orange.opacity(0.2))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!row.isEnabled)
                        .help(row.detail)
                    }
                }
                .padding(.horizontal, 12)
            }
            .liveMockupPlaceholder(.keywordingBatch)
        }
    }

    private var batchMetadataPopover: some View {
        let presentation = BatchMetadataReviewPresentation(
            visibleAssetCount: model.assets.count,
            selectedAssetCount: model.selectedBatchAssetCount,
            currentScopeAssetCount: model.totalAssetCount,
            selectedScope: batchMetadataScope,
            requiresAllCatalogConfirmation: batchMetadataScope == .currentScope && !model.hasActiveLibraryFilters,
            isAllCatalogConfirmed: isAllCatalogBatchMetadataConfirmed,
            suggestions: batchMetadataSuggestions(),
            draft: batchMetadataDraft
        )
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batch Metadata")
                        .font(.headline)
                    Text(presentation.countText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "tag")
                    .foregroundStyle(.orange)
            }

            Picker("Batch scope", selection: $batchMetadataScope) {
                ForEach(BatchScopeMode.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: batchMetadataScope) { _, _ in
                isAllCatalogBatchMetadataConfirmed = false
            }

            if !presentation.suggestionRows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TESTSTRIP SUGGESTS")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.orange)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(presentation.suggestionRows) { row in
                                Button {
                                    applyBatchMetadataKeywordSuggestion(row.keyword)
                                } label: {
                                    Text(row.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help(row.detail)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Keywords", text: $batchMetadataDraft.keywords)
                if !presentation.draftKeywordChips.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(presentation.draftKeywordCountText ?? "")
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(presentation.draftKeywordChips, id: \.self) { keyword in
                                    Text(keyword)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.orange)
                                        .lineLimit(1)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                        .overlay {
                                            Capsule()
                                                .strokeBorder(Color.orange.opacity(0.24))
                                        }
                                }
                            }
                        }
                    }
                }
                TextField("Caption", text: $batchMetadataDraft.caption)
                TextField("Creator", text: $batchMetadataDraft.creator)
                TextField("Copyright", text: $batchMetadataDraft.copyright)
            }
            .textFieldStyle(.roundedBorder)

            if let confirmationText = presentation.confirmationText {
                Toggle(confirmationText, isOn: $isAllCatalogBatchMetadataConfirmed)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    isReviewingBatchMetadata = false
                }
                Spacer()
                Button(presentation.applyTitle) {
                    applyVisibleBatchMetadataDraft()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!presentation.isApplyEnabled)
            }
        }
        .padding(14)
        .frame(width: 360)
        .liveMockupPlaceholder(.keywordingBatch)
    }

    private var exportPopover: some View {
        let presentation = ExportReviewPresentation(
            visibleAssetCount: model.assets.count,
            selectedAssetCount: model.selectedBatchAssetCount,
            currentScopeAssetCount: model.totalAssetCount,
            selectedScope: exportScope,
            requiresAllCatalogConfirmation: exportScope == .currentScope && !model.hasActiveLibraryFilters,
            isAllCatalogConfirmed: isAllCatalogExportConfirmed,
            isExporting: model.isExporting
        )
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export JPEGs")
                        .font(.headline)
                    Text(presentation.countText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.orange)
            }

            Picker("Export scope", selection: $exportScope) {
                ForEach(BatchScopeMode.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: exportScope) { _, _ in
                isAllCatalogExportConfirmed = false
            }

            Picker("Export preset", selection: $exportPreset) {
                ForEach(ExportPreset.all, id: \.name) { preset in
                    Text(preset.name).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle("Include EXIF/IPTC metadata", isOn: $includeSourceMetadataInExport)
                .font(.caption)

            if let confirmationText = presentation.confirmationText {
                Toggle(confirmationText, isOn: $isAllCatalogExportConfirmed)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    isReviewingExport = false
                }
                Spacer()
                Button(presentation.exportTitle) {
                    chooseExportDestinationAndExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!presentation.isExportEnabled)
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private var importProgressBanner: some View {
        let presentation = importProgressPresentation
        return HStack(spacing: 10) {
            importProgressIndicator
                .controlSize(.small)
            Text(presentation.phaseText)
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.orange.opacity(0.22))
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(presentation.reassuranceText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let countText = presentation.countText {
                Text(countText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button {
                cancelImport()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(presentation.cancelHelp)
            .help(presentation.cancelHelp)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func importCompletionSummary(_ summary: ImportCompletionSummary) -> some View {
        let presentation = ImportCompletionPresentation.presentation(
            for: summary,
            batchKeywordSuggestions: model.latestImportBatchKeywordSuggestions,
            faceReviewAssetCount: model.latestImportFaceReviewAssetCount,
            flaggedReviewAssetCount: model.latestImportFlaggedReviewAssetCount,
            canEvaluateImport: model.canRequestLatestImportAssetEvaluations
        )
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text(presentation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button {
                    dismissedImportCompletionSummaryID = summary.id
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Dismiss import summary")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                ForEach(presentation.metricRows) { metric in
                    importCompletionMetric(metric)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 8)], spacing: 8) {
                ForEach(presentation.actionRows) { action in
                    importCompletionAction(action)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.bar)
        .liveMockupPlaceholder(.importCompleteSummary)
    }

    private func importCompletionMetric(_ metric: ImportCompletionMetricRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: metric.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(metric.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                Text(metric.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(metric.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .padding(9)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary)
        }
    }

    @ViewBuilder
    private func importCompletionAction(_ action: ImportCompletionActionPresentation) -> some View {
        if action.isEnabled {
            Button {
                performImportCompletionAction(action.kind)
            } label: {
                importCompletionActionLabel(action)
            }
            .buttonStyle(.plain)
            .help(action.detail)
        } else {
            Button {} label: {
                importCompletionActionLabel(action)
            }
            .buttonStyle(.plain)
            .disabled(true)
            .help(action.detail)
            .liveMockupPlaceholder(action.placeholder)
        }
    }

    private func importCompletionActionLabel(_ action: ImportCompletionActionPresentation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: action.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(action.detail)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(action.isPrimary ? Color.black.opacity(0.72) : Color.secondary)
            }
        }
        .foregroundStyle(action.isPrimary ? Color.black : Color.primary)
        .frame(minWidth: 126, maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 10)
        .background(action.isPrimary ? Color.orange : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(action.isPrimary ? Color.orange.opacity(0.5) : Color.white.opacity(0.08))
        }
        .opacity(action.isEnabled ? 1 : 0.55)
    }

    private func performImportCompletionAction(_ kind: ImportCompletionActionPresentation.Kind) {
        switch kind {
        case .startCulling:
            beginCullingFromLatestImportCompletion()
        case .reviewImportedFrames:
            reviewLatestImportInCompare()
        case .openInLibrary:
            openLatestImportCompletion()
        case .evaluateImport:
            requestLatestImportEvaluations()
        case .reviewImportIssues:
            reviewImportIssuesFromCompletion()
        case .reviewFlaggedFrames:
            reviewLatestImportFlagged()
        case .keywordSuggestions:
            reviewLatestImportKeywordSuggestions()
        case .stackGrouping:
            beginStackCullingFromLatestImportCompletion()
        case .faceNaming:
            reviewFaceQueueFromImportCompletion()
        }
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
        SmartCollectionBuilderPopover(
            name: $savedSearchName,
            starred: $savedSearchStarred,
            ruleText: $savedSearchRuleText,
            presentation: SmartCollectionBuilderPresentation(
                proposedName: savedSearchName,
                ruleChips: model.activeLibraryFilterChips,
                activeFilterRows: model.activeLibraryFilterRows,
                matchCount: model.totalAssetCount,
                typedRuleText: savedSearchRuleText,
                reviewQueueCounts: model.reviewQueueCounts,
                evaluationKindSummaries: model.catalogEvaluationKindSummaries
            ),
            previewAssets: Array(model.assets.prefix(18)),
            previewURL: { model.gridPreviewURL(for: $0) },
            previewCacheGeneration: { model.previewCacheGeneration(for: $0) },
            cancel: { isSavingSearch = false },
            applyRulePreset: applySmartCollectionRulePreset,
            applyRuleText: applySmartCollectionRuleText,
            removeRule: removeActiveLibraryFilter,
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

    private var saveSnapshotSetPopover: some View {
        SaveSetPopover(
            title: "Save Snapshot",
            name: $snapshotSetName,
            starred: $snapshotSetStarred,
            cancel: { isSavingSnapshotSet = false },
            save: saveCurrentSnapshotSet
        )
    }

    private var cullingSessionPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start Culling")
                .font(.headline)
            TextField("Name", text: $cullingSessionName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            TextField("Intent", text: $cullingSessionIntent)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            HStack {
                Spacer()
                Button("Cancel") {
                    isStartingCullingSession = false
                }
                Button("Start") {
                    beginCullingSession()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(cullingSessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }

    private var importPathSheet: some View {
        let reviewPresentation = ImportFolderPathReviewPresentation(
            draft: importPathDraft,
            isReviewing: isReviewingImportPath,
            isImporting: isImporting
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text("Import Folder Path")
                .font(.headline)
            TextField("Folder path", text: $importPathDraft.path)
                .textFieldStyle(.roundedBorder)
                .frame(width: 420)
                .disabled(isReviewingImportPath)
            importPlanView(steps: importPathDraft.planSteps, width: 420)
            if reviewPresentation.showsProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(reviewPresentation.statusText ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage = importPathDraft.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    importPathReviewID = nil
                    isReviewingImportPath = false
                    isShowingImportPathSheet = false
                }
                Button(reviewPresentation.primaryActionTitle) {
                    importFolderPath()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!reviewPresentation.isPrimaryActionEnabled)
            }
        }
        .padding(18)
        .onDisappear {
            importPathReviewID = nil
            isReviewingImportPath = false
        }
    }

    private var importCardPathSheet: some View {
        let reviewPresentation = ImportCardPathReviewPresentation(
            draft: importCardPathDraft,
            isReviewing: isReviewingImportCardPath,
            isImporting: isImporting
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text("Import Card Paths")
                .font(.headline)
            TextField("Card or source folder path", text: $importCardPathDraft.sourcePath)
                .textFieldStyle(.roundedBorder)
                .frame(width: 420)
                .disabled(isReviewingImportCardPath)
            TextField("Destination folder path", text: $importCardPathDraft.destinationPath)
                .textFieldStyle(.roundedBorder)
                .frame(width: 420)
                .disabled(isReviewingImportCardPath)
            importPlanView(steps: importCardPathDraft.planSteps, width: 420)
            if reviewPresentation.showsProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(reviewPresentation.statusText ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage = importCardPathDraft.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    importCardPathReviewID = nil
                    isReviewingImportCardPath = false
                    isShowingImportCardPathSheet = false
                }
                Button(reviewPresentation.primaryActionTitle) {
                    importCardPath()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!reviewPresentation.isPrimaryActionEnabled)
            }
        }
        .padding(18)
        .onDisappear {
            importCardPathReviewID = nil
            isReviewingImportCardPath = false
        }
    }

    private func importConfirmationSheet(_ draft: ImportConfirmationDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Source", value: draft.sourceName)
                if let destinationName = draft.destinationName {
                    LabeledContent("Destination", value: destinationName)
                }
                LabeledContent("Photos", value: draft.sourceSummary.countText)
                LabeledContent("Size", value: draft.sourceSummary.byteCountText)
                Text(draft.sourceSummary.detailText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let destinationUnavailableReason = draft.destinationUnavailableReason {
                    Text(destinationUnavailableReason)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            importPlanView(steps: draft.planSteps, width: 440)
            Toggle(
                "Read imported frames automatically",
                isOn: Binding(
                    get: { importConfirmationDraft?.evaluateAfterImport ?? true },
                    set: { importConfirmationDraft?.evaluateAfterImport = $0 }
                )
            )
            .toggleStyle(.checkbox)
            .font(.caption)
            .help("Queues the standard evaluation passes over the imported set's cached previews as previews complete. Reads stay provisional; nothing is written without your action.")
            HStack {
                Spacer()
                Button("Cancel") {
                    importConfirmationDraft = nil
                }
                Button(draft.primaryActionTitle) {
                    confirmImport(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isImporting || !draft.canStartImport)
            }
        }
        .padding(18)
        .frame(width: 480)
    }

    private func importIssueReviewSheet(_ review: ImportIssueReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(review.title)
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(review.issues.enumerated()), id: \.offset) { _, issue in
                        importIssueRow(issue)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(width: 520, height: 260)
            HStack {
                Spacer()
                Button("Done") {
                    importIssueReview = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 560)
    }

    private func importIssueRow(_ issue: WorkSessionIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.yellow)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(importIssueTitle(issue))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let path = issue.sourceURL?.path, !path.isEmpty {
                    Text(path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(issue.message)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func importIssueTitle(_ issue: WorkSessionIssue) -> String {
        switch issue.kind {
        case .skippedSourceFile:
            let fileName = issue.sourceURL?.lastPathComponent ?? ""
            return fileName.isEmpty ? "Skipped source file" : "Skipped \(fileName)"
        }
    }

    private func importPlanView(steps: [ImportPlanStep], width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Teststrip will", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: importPlanStepSystemImage(for: step.stage))
                        .font(.caption)
                        .foregroundStyle(importPlanStepTint(for: step.stage))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.caption.weight(.semibold))
                        Text(step.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: width, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func importPlanStepSystemImage(for stage: ImportPlanStepStage) -> String {
        switch stage {
        case .importWork:
            "checkmark.circle.fill"
        case .followUpSetup:
            "sparkles"
        }
    }

    private func importPlanStepTint(for stage: ImportPlanStepStage) -> Color {
        switch stage {
        case .importWork:
            .green
        case .followUpSetup:
            .orange
        }
    }

    private var sourceReconnectSheet: some View {
        SourceReconnectSheet(
            draft: $sourceReconnectDraft,
            isImporting: isImporting,
            cancel: { isShowingSourceReconnectSheet = false },
            reconnect: reconnectSourceRoot
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

    private struct SmartCollectionBuilderPopover: View {
        @Binding var name: String
        @Binding var starred: Bool
        @Binding var ruleText: String
        var presentation: SmartCollectionBuilderPresentation
        var previewAssets: [Asset]
        var previewURL: (AssetID) -> URL?
        var previewCacheGeneration: (AssetID) -> Int
        var cancel: () -> Void
        var applyRulePreset: (SmartCollectionRulePreset) -> Void
        var applyRuleText: () -> Void
        var removeRule: (ActiveLibraryFilterRow) -> Void
        var save: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    builderPanel
                        .frame(width: 360)
                    Divider()
                    previewPanel
                        .frame(width: 420)
                }
                Divider()
                footer
            }
            .frame(width: 780, height: 520)
            .liveMockupPlaceholder(.smartCollectionsBuilder)
        }

        private var builderPanel: some View {
            VStack(alignment: .leading, spacing: 16) {
                Label("New Smart Collection", systemImage: "sparkles")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("Match")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("All")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        Text("of these rules")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(presentation.ruleCountText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ruleStack
                }

                suggestedTemplates
                Toggle("Starred", isOn: $starred)
                Spacer(minLength: 0)
            }
            .padding(16)
        }

        private var ruleStack: some View {
            VStack(alignment: .leading, spacing: 8) {
                if presentation.ruleRows.isEmpty {
                    Text("No active filters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                } else {
                    ForEach(presentation.ruleRows) { rule in
                        HStack(spacing: 7) {
                            Text(rule.field)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .frame(width: 98, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                            Text(rule.operation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                            Text(rule.value)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .frame(width: 82, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                            Button {
                                removeRule(rule.activeFilterRow)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.borderless)
                            .help("Remove rule")
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("Rule", text: $ruleText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            applyRuleText()
                        }
                    Button {
                        applyRuleText()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!presentation.canApplyTypedRule)
                    .help("Apply typed rule")
                }
                Menu {
                    ForEach(presentation.addRuleRows) { row in
                        Button {
                            applyRulePreset(row.preset)
                        } label: {
                            Label(row.title, systemImage: row.systemImage)
                        }
                    }
                } label: {
                    Label("Add rule", systemImage: "plus")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.quaternary)
                        }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .liveMockupPlaceholder(.smartCollectionsBuilder)
            }
        }

        private var suggestedTemplates: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label("Teststrip suggests", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(presentation.suggestedTemplateRows) { template in
                        Button {
                            applySuggestedTemplate(template)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: template.systemImage)
                                    .font(.caption.weight(.semibold))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(template.title)
                                        .font(.caption.weight(.medium))
                                    Text(template.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.orange.opacity(0.82))
                                }
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.orange.opacity(0.24))
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Add \(template.detail)")
                    }
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .liveMockupPlaceholder(.smartCollectionsBuilder)
        }

        private func applySuggestedTemplate(_ template: SmartCollectionSuggestedTemplateRow) {
            for preset in template.presets {
                applyRulePreset(preset)
            }
        }

        private var previewPanel: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(presentation.matchCountText)
                        .font(.headline.monospacedDigit())
                    Text(presentation.previewCountText(visibleCount: previewAssets.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                if previewAssets.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.grid.3x3")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No preview matches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                            ForEach(previewAssets, id: \.id.rawValue) { asset in
                                AssetGridCell(
                                    asset: asset,
                                    previewURL: previewURL(asset.id),
                                    previewCacheGeneration: previewCacheGeneration(asset.id),
                                    isSelected: false
                                )
                                .aspectRatio(AssetGridCellLayout.aspectRatio(for: asset), contentMode: .fit)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }

        private var footer: some View {
            HStack {
                Spacer()
                Button("Cancel") {
                    cancel()
                }
                Button("Create collection") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!presentation.canCreate)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
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

    private var librarySortBinding: Binding<LibrarySortOption> {
        Binding(
            get: { model.librarySortOption },
            set: { option in
                applyLibrarySort(option)
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

    private var colorLabelFilterBinding: Binding<String> {
        Binding(
            get: { model.colorLabelFilter?.rawValue ?? "" },
            set: { value in
                model.colorLabelFilter = ColorLabel(rawValue: value)
                applyLibraryFilters()
            }
        )
    }

    private var availabilityFilterBinding: Binding<String> {
        Binding(
            get: { model.availabilityFilter?.rawValue ?? "" },
            set: { value in
                model.availabilityFilter = SourceAvailability(rawValue: value)
                applyLibraryFilters()
            }
        )
    }

    private var availabilityFilterOptions: [SourceAvailability] {
        [.online, .offline, .missing, .moved, .stale]
    }

    private var evaluationKindFilterBinding: Binding<String> {
        Binding(
            get: { model.evaluationKindFilter?.rawValue ?? "" },
            set: { value in
                model.evaluationKindFilter = evaluationKindFilterOptions.first { $0.rawValue == value }
                applyLibraryFilters()
            }
        )
    }

    private var evaluationKindFilterOptions: [EvaluationKind] {
        [.focus, .motionBlur, .exposure, .aesthetics, .framing, .object, .faceCount, .faceQuality, .eyesOpen, .eyeSharpness, .smile, .ocrText, .colorPalette, .novelty, .visualSimilarity]
    }

    private var metadataSyncFilterBinding: Binding<String> {
        Binding(
            get: {
                MetadataSyncFilterOption(
                    pending: model.metadataSyncPendingFilter,
                    conflict: model.metadataSyncConflictFilter
                ).rawValue
            },
            set: { value in
                let option = MetadataSyncFilterOption(rawValue: value) ?? .any
                model.metadataSyncPendingFilter = option.pendingFilter
                model.metadataSyncConflictFilter = option.conflictFilter
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
        LazyVGrid(columns: columns, spacing: gridLayout.gridSpacing) {
            ForEach(model.assets, id: \.id.rawValue) { asset in
                AssetGridCell(
                    asset: asset,
                    previewURL: model.gridPreviewURL(for: asset.id),
                    previewCacheGeneration: model.previewCacheGeneration(for: asset.id),
                    previewStatus: model.gridPreviewStatus(for: asset.id),
                    isSelected: model.selectedAssetID == asset.id,
                    isBatchSelected: model.isBatchSelected(asset.id)
                )
                .assetActivation(for: asset, model: model, focusCullingSurface: focusCullingSurface) { assetID in
                    selectAssetFromGrid(assetID)
                }
                .id(asset.id.rawValue)
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
            if isImporting {
                Text(importProgressPresentation.title)
                    .font(.headline)
                importProgressIndicator
                    .controlSize(.small)
                Text(importProgressPresentation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let countText = importProgressPresentation.countText {
                    Text(countText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button {
                    cancelImport()
                } label: {
                    Label("Cancel Import", systemImage: "xmark.circle")
                }
            } else {
                Text("No photographs in this catalog")
                    .font(.headline)
                Button {
                    showImportFolderPanel()
                } label: {
                    Label("Import Folder", systemImage: "square.and.arrow.down")
                }
                Button {
                    showImportPathSheet()
                } label: {
                    Label("Import Path", systemImage: "folder.badge.plus")
                }
                Button {
                    showPrimaryCardImportRoute()
                } label: {
                    Label("Import Card", systemImage: "externaldrive.badge.plus")
                }
            }
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
                Text(importProgressPresentation.detail)
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
            } else if let statusText = model.libraryStatusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if model.selectedBatchAssetCount > 0 {
                Label("\(model.selectedBatchAssetCount) selected", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button {
                    model.clearBatchSelection()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Clear selected batch")
            }
            Spacer()
            thumbnailDensityControl
            thumbnailSizeControl
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
        .frame(height: 38)
        .background(.bar)
    }

    private func showImportFolderPanel() {
        guard let folderURL = FolderSelectionPanel.chooseImportFolder() else { return }
        importConfirmationDraft = .folder(folderURL)
    }

    private func showImportPathSheet() {
        importPathDraft.reset()
        importPathReviewID = nil
        isReviewingImportPath = false
        isShowingImportPathSheet = true
    }

    private func showImportCardPathSheet() {
        importCardPathDraft.reset()
        importCardPathReviewID = nil
        isReviewingImportCardPath = false
        isShowingImportCardPathSheet = true
    }

    private func showPrimaryCardImportRoute() {
        switch LibraryGridChromePolicy.primaryCardImportRoute(environment: ProcessInfo.processInfo.environment) {
        case .userGrantedPanel:
            showImportCardPanel()
        case .typedPathSheet:
            showImportCardPathSheet()
        }
    }

    private func showSourceReconnectSheet() {
        sourceReconnectDraft = SourceReconnectPathDraft(oldRootPath: model.suggestedReconnectOldRootPath)
        isShowingSourceReconnectSheet = true
    }

    private func showImportCardPanel() {
        guard let source = FolderSelectionPanel.chooseCardSourceFolder() else { return }
        guard let destinationRoot = FolderSelectionPanel.chooseCardDestinationFolder() else { return }
        importConfirmationDraft = .card(source: source, destinationRoot: destinationRoot)
    }

    private func importFolderPath() {
        do {
            let folderURL = try importPathDraft.resolveFolderURL()
            let reviewID = UUID()
            importPathReviewID = reviewID
            isReviewingImportPath = true
            Task {
                let confirmationDraft = await Task.detached(priority: .userInitiated) {
                    ImportConfirmationDraft.folder(folderURL)
                }.value
                await MainActor.run {
                    guard importPathReviewID == reviewID else { return }
                    importPathReviewID = nil
                    isReviewingImportPath = false
                    isShowingImportPathSheet = false
                    importConfirmationDraft = confirmationDraft
                }
            }
        } catch {
            importPathReviewID = nil
            isReviewingImportPath = false
            return
        }
    }

    private func importCardPath() {
        do {
            let roots = try importCardPathDraft.resolveCardURLs()
            let reviewID = UUID()
            importCardPathReviewID = reviewID
            isReviewingImportCardPath = true
            Task {
                let confirmationDraft = await Task.detached(priority: .userInitiated) {
                    ImportConfirmationDraft.card(source: roots.source, destinationRoot: roots.destinationRoot)
                }.value
                await MainActor.run {
                    guard importCardPathReviewID == reviewID else { return }
                    importCardPathReviewID = nil
                    isReviewingImportCardPath = false
                    isShowingImportCardPathSheet = false
                    importConfirmationDraft = confirmationDraft
                }
            }
        } catch {
            importCardPathReviewID = nil
            isReviewingImportCardPath = false
            return
        }
    }

    private func confirmImport(_ draft: ImportConfirmationDraft) {
        importConfirmationDraft = nil
        switch draft.mode {
        case .folder:
            FolderSelectionPanel.rememberImportFolder(draft.sourceURL)
            importFolder(draft.sourceURL, evaluateAfterImport: draft.evaluateAfterImport)
        case .card:
            guard let destinationRootURL = draft.destinationRootURL else {
                model.errorMessage = "Card import destination is missing"
                return
            }
            importCard(source: draft.sourceURL, destinationRoot: destinationRootURL, evaluateAfterImport: draft.evaluateAfterImport)
        }
    }

    private func reconnectSourceRoot() {
        do {
            let roots = try sourceReconnectDraft.resolveRootURLs()
            try model.reconnectSourceRoot(from: roots.oldRoot, to: roots.newRoot)
            isShowingSourceReconnectSheet = false
        } catch {
            sourceReconnectDraft.recordError(error.localizedDescription)
            model.errorMessage = error.localizedDescription
        }
    }

    private func importFolder(_ folderURL: URL, evaluateAfterImport: Bool = true) {
        model.beginImportFolder(folderURL, evaluateAfterImport: evaluateAfterImport)
    }

    private func importCard(source: URL, destinationRoot: URL, evaluateAfterImport: Bool = true) {
        model.beginImportCard(source: source, destinationRoot: destinationRoot, evaluateAfterImport: evaluateAfterImport)
    }

    private var importActivity: AppWorkActivity? {
        model.visibleImportActivity
    }

    private var importProgressPresentation: ImportProgressPresentation {
        ImportProgressPresentation.presentation(for: importActivity)
    }

    private func cancelImport() {
        model.cancelImportWork()
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

    private func applyLibrarySort(_ option: LibrarySortOption) {
        do {
            try model.setLibrarySortOption(option)
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

    private func removeActiveLibraryFilter(_ row: ActiveLibraryFilterRow) {
        do {
            try model.removeActiveLibraryFilter(row)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func refreshVisibleAvailability() {
        do {
            try model.refreshVisibleAssetAvailability()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func retryPendingMetadataSync() {
        do {
            try model.retryPendingMetadataSyncInCurrentScope()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func handleSelectedAssetChange(_ selectedAssetID: String?, with proxy: ScrollViewProxy) {
        defer {
            suppressedSelectionScrollAssetID = nil
        }
        guard LibraryGridSelectionScrollPolicy.shouldScrollSelectedAssetIntoView(
            selectedAssetID: selectedAssetID,
            suppressedSelectionScrollAssetID: suppressedSelectionScrollAssetID
        ) else { return }
        scrollSelectedAssetIntoView(selectedAssetID, with: proxy)
    }

    private func scrollSelectedAssetIntoView(_ selectedAssetID: String?, with proxy: ScrollViewProxy) {
        guard let selectedAssetID else { return }
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.12)) {
                proxy.scrollTo(selectedAssetID, anchor: .center)
            }
        }
    }

    private func selectAssetFromGrid(_ assetID: AssetID) {
        if model.selectedAssetID != assetID {
            suppressedSelectionScrollAssetID = assetID.rawValue
        }
        model.select(assetID)
    }

    private func showSaveSearchPopover() {
        savedSearchName = model.suggestedSavedSearchName
        savedSearchStarred = false
        savedSearchRuleText = model.librarySearchText
        isSavingSearch = true
    }

    private func showSaveSnapshotSetPopover() {
        snapshotSetName = model.suggestedSnapshotSetName
        snapshotSetStarred = false
        isSavingSnapshotSet = true
    }

    private func saveCurrentSearch() {
        do {
            try model.saveCurrentLibraryQuery(named: savedSearchName, starred: savedSearchStarred)
            isSavingSearch = false
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func applySmartCollectionRulePreset(_ preset: SmartCollectionRulePreset) {
        do {
            try model.applySmartCollectionRulePreset(preset)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func applySmartCollectionRuleText() {
        let intent = LibrarySearchIntent.parse(savedSearchRuleText)
        guard intent.residualText != nil || !intent.predicates.isEmpty else { return }
        do {
            try model.applySmartCollectionRuleText(savedSearchRuleText)
            savedSearchRuleText = ""
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

    private func saveCurrentSnapshotSet() {
        do {
            try model.saveCurrentAssetScopeSnapshot(named: snapshotSetName, starred: snapshotSetStarred)
            isSavingSnapshotSet = false
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func beginCullingSession() {
        do {
            try model.beginCullingSession(named: cullingSessionName, intent: cullingSessionIntent)
            isStartingCullingSession = false
            focusCullingSurface()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func showStartCullingPopover() {
        cullingSessionName = model.suggestedCullingSessionName
        cullingSessionIntent = ""
        isStartingCullingSession = true
    }

    private func openLatestImportCompletion() {
        do {
            try model.openLatestImportCompletion()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func beginCullingFromLatestImportCompletion() {
        do {
            try model.beginCullingFromLatestImportCompletion()
            focusCullingSurface()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func beginStackCullingFromLatestImportCompletion() {
        do {
            try model.beginStackCullingFromLatestImportCompletion()
            focusCullingSurface()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func reviewLatestImportInCompare() {
        do {
            try model.reviewLatestImportInCompare()
            focusCullingSurface()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func reviewLatestImportFlagged() {
        do {
            try model.reviewLatestImportFlagged()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func reviewImportIssuesFromCompletion() {
        guard let summary = visibleImportCompletionSummary, !summary.issues.isEmpty else { return }
        importIssueReview = ImportIssueReview(summaryID: summary.id, issues: summary.issues)
    }

    private func reviewLatestImportKeywordSuggestions() {
        do {
            try model.openLatestImportCompletion()
            batchMetadataScope = .visible
            batchMetadataDraft = BatchMetadataDraft()
            isAllCatalogBatchMetadataConfirmed = false
            isReviewingBatchMetadata = true
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func requestLatestImportEvaluations() {
        do {
            try model.requestLatestImportAssetEvaluations()
            model.statusMessage = "Evaluating latest import"
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func reviewFaceQueueFromImportCompletion() {
        do {
            try model.selectSidebarTarget(.reviewQueue(.facesFound))
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func applyVisibleBatchKeywordSuggestion(_ keyword: String) {
        do {
            try model.acceptVisibleBatchKeywordSuggestion(keyword)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func applyBatchMetadataKeywordSuggestion(_ keyword: String) {
        do {
            switch batchMetadataScope {
            case .selected:
                try model.acceptSelectedBatchKeywordSuggestion(keyword)
            case .visible:
                try model.acceptVisibleBatchKeywordSuggestion(keyword)
            case .currentScope:
                try model.acceptCurrentScopeBatchKeywordSuggestion(keyword)
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func batchMetadataSuggestions() -> [BatchKeywordSuggestion] {
        switch batchMetadataScope {
        case .selected:
            return model.selectedBatchKeywordSuggestions
        case .visible:
            return model.visibleBatchKeywordSuggestions
        case .currentScope:
            return model.currentScopeBatchKeywordSuggestions
        }
    }

    private func applyVisibleBatchMetadataDraft() {
        do {
            switch batchMetadataScope {
            case .selected:
                try model.applySelectedBatchMetadata(
                    keywordText: batchMetadataDraft.keywords,
                    caption: batchMetadataDraft.caption,
                    creator: batchMetadataDraft.creator,
                    copyright: batchMetadataDraft.copyright
                )
            case .visible:
                try model.applyVisibleBatchMetadata(
                    keywordText: batchMetadataDraft.keywords,
                    caption: batchMetadataDraft.caption,
                    creator: batchMetadataDraft.creator,
                    copyright: batchMetadataDraft.copyright
                )
            case .currentScope:
                try model.applyCurrentScopeBatchMetadata(
                    keywordText: batchMetadataDraft.keywords,
                    caption: batchMetadataDraft.caption,
                    creator: batchMetadataDraft.creator,
                    copyright: batchMetadataDraft.copyright
                )
            }
            batchMetadataDraft = BatchMetadataDraft()
            isAllCatalogBatchMetadataConfirmed = false
            isReviewingBatchMetadata = false
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func chooseExportDestinationAndExport() {
        guard let destination = FolderSelectionPanel.chooseExportDestinationFolder() else { return }
        var settings = exportPreset.settings
        settings.includeSourceMetadata = includeSourceMetadataInExport
        let scope = exportScope
        isReviewingExport = false
        isAllCatalogExportConfirmed = false
        Task { @MainActor in
            do {
                switch scope {
                case .selected:
                    try await model.exportSelectedAssets(settings: settings, destinationFolder: destination)
                case .visible:
                    try await model.exportVisibleAssets(settings: settings, destinationFolder: destination)
                case .currentScope:
                    try await model.exportCurrentScopeAssets(settings: settings, destinationFolder: destination)
                }
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func evaluateSelectedAsset() {
        do {
            try model.requestSelectedAssetEvaluations()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func evaluateVisibleAssets() {
        do {
            try model.requestVisibleAssetEvaluations()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func evaluateCurrentScopeAssets() {
        do {
            try model.requestCurrentScopeAssetEvaluations()
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

private struct CullingCompletionBannerView: View {
    var summary: CullingSessionCompletionSummary
    var canViewPicks: Bool
    var viewPicks: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Culling complete")
                    .font(.caption.weight(.semibold))
                Text(summary.detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("View Picks") {
                viewPicks()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)
            .disabled(!canViewPicks)
            .help(canViewPicks ? "Open this session's Picks output set" : "This session finished with no picks")
            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color.green.opacity(0.12))
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Culling session complete")
    }
}

private struct LoupeView: View {
    var model: AppModel

    @State private var closeUpCrops: [(id: Int, image: CGImage)] = []

    var body: some View {
        let stackPresentation = cullingStackPresentation
        VStack(spacing: 0) {
            cullingHeader(stackPresentation: stackPresentation)
            HStack(spacing: 0) {
                cullingStackListRail
                VStack(spacing: 0) {
                    if let asset = model.selectedAsset {
                        HStack(spacing: 0) {
                            loupeStage(for: asset)
                            closeUpsPanel
                        }
                        .task(id: asset.id.rawValue) {
                            do {
                                try model.requestVisibleLoupePreview(assetID: asset.id)
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                            await refreshCloseUps(for: asset.id)
                        }
                    } else {
                        unavailableView(title: "No photo selected", systemImage: "photo")
                    }
                }
            }
            if let completion = model.cullingSessionCompletion {
                CullingCompletionBannerView(
                    summary: completion,
                    canViewPicks: completion.picksSetID != nil,
                    viewPicks: { openCullingSessionPicks() },
                    dismiss: { model.dismissCullingSessionCompletion() }
                )
            }
            cullingStackRail(presentation: stackPresentation)
            cullingFilmstrip(recommendedAssetID: stackPresentation.recommendedAssetID)
            cullingCommandRail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.34))
    }

    private func openCullingSessionPicks() {
        do {
            try model.openCullingSessionPicks()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var cullingStackListRail: some View {
        let entries = model.cullingStackListEntries()
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("STACKS · AUTO-GROUPED")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(entries) { entry in
                            stackListRow(entry)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(width: 168)
            .background(Color.black.opacity(0.26))
            .overlay(alignment: .trailing) { Divider() }
        }
    }

    private func stackListRow(_ entry: CullingStackListEntry) -> some View {
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
            .padding(6)
            .background(
                entry.isSelected ? Color.orange.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(entry.isSelected ? Color.orange.opacity(0.4) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.title)
        .accessibilityValue(entry.isDecided ? "Decided" : "Undecided")
    }

    @ViewBuilder
    private var closeUpsPanel: some View {
        if !closeUpCrops.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("CLOSE-UPS")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(closeUpCrops, id: \.id) { crop in
                            Image(decorative: crop.image, scale: 1)
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .frame(width: 112, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.white.opacity(0.14))
                                }
                        }
                    }
                }
            }
            .padding(10)
            .frame(width: 136)
            .background(Color.black.opacity(0.26))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Face close-ups")
        }
    }

    // Detection is display-only and per-selection: the cached preview is read
    // off the main actor, cropped in memory, and nothing is persisted.
    private func refreshCloseUps(for assetID: AssetID) async {
        closeUpCrops = []
        guard let previewURL = model.loupePreviewURL(for: assetID) else { return }
        let crops = await Task.detached(priority: .utility) { () -> [(id: Int, image: CGImage)] in
            guard let faces = try? CoreImageFaceExpressionAnalyzer().detectFaces(previewURL: previewURL),
                  !faces.isEmpty,
                  let source = CGImageSourceCreateWithURL(previewURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return []
            }
            let presentation = CloseUpFacesPresentation(
                faces: faces,
                imagePixelSize: CGSize(width: image.width, height: image.height)
            )
            return presentation.crops.compactMap { crop in
                image.cropping(to: crop.pixelRect).map { (id: crop.id, image: $0) }
            }
        }.value
        guard model.selectedAssetID == assetID else { return }
        closeUpCrops = crops
    }

    @ViewBuilder
    private func cullingHeader(stackPresentation: CullingStackRailPresentation) -> some View {
        let summary = model.cullingProgressSummary
        HStack(spacing: 10) {
            Label("Culling", systemImage: "checkmark.seal")
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if let positionText = summary.positionText {
                Text(positionText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if summary.totalCount > 0 {
                ProgressView(value: Double(summary.reviewedCount), total: Double(max(summary.totalCount, 1)))
                    .tint(.orange)
                    .frame(width: 96)
                    .accessibilityLabel("Culling Progress")
            }
            Spacer(minLength: 0)
            if let feedback = model.lastCullingMetadataDecision {
                cullingDecisionFeedbackPill(CullingDecisionFeedbackPresentation(feedback: feedback))
            }
            cullingCountPill(title: "Picks", count: summary.pickCount, color: .green, systemImage: "flag.fill")
            cullingCountPill(title: "Rejects", count: summary.rejectCount, color: .red, systemImage: "xmark.circle.fill")
            cullingAssistPill(stackGuidanceAction: cullingStackGuidanceAction(in: stackPresentation))
                .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(.bar)
    }

    private func cullingDecisionFeedbackPill(_ presentation: CullingDecisionFeedbackPresentation) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(presentation.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 142, height: 34, alignment: .leading)
        .background(Color.green.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.green.opacity(0.25))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last culling decision")
        .accessibilityValue(presentation.accessibilityValue)
    }

    private func cullingAssistPill(stackGuidanceAction: CullingStackActionPresentation?) -> some View {
        let presentation = CullingAssistPresentation.presentation(
            for: model.selectedEvaluationSignals,
            stackGuidance: stackGuidanceAction
        )
        let color = cullingAssistColor(for: presentation.tone)
        return HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("TESTSTRIP READS")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                    if let verdictText = presentation.verdictText {
                        Text(verdictText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(cullingAssistColor(for: presentation.verdictTone))
                            .lineLimit(1)
                    }
                }
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(presentation.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .help(presentation.detail)
        .padding(.horizontal, 10)
        .frame(minWidth: 148, maxWidth: 460, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.28))
        }
        .liveMockupPlaceholder(.cullingAssistVerdict)
    }

    private func cullingAssistColor(for tone: CullingAssistPresentation.Tone) -> Color {
        switch tone {
        case .waiting:
            return .secondary
        case .positive:
            return .green
        case .caution:
            return .red
        case .neutral:
            return .orange
        }
    }

    private func cullingCountPill(title: String, count: Int, color: Color, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text("\(count) \(title.lowercased())")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
    }

    private func loupeStage(for asset: Asset) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.opacity(0.22)
            if let previewURL = model.loupePreviewURL(for: asset.id) {
                CachedPreviewImage(
                    previewURL: previewURL,
                    scaling: .fit,
                    cacheGeneration: model.previewCacheGeneration(for: asset.id)
                )
                .padding(24)
            } else {
                unavailableView(title: "No cached preview", systemImage: "photo.badge.exclamationmark")
            }
            loupeMetadataOverlay(for: asset)
                .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cullingFilmstrip(recommendedAssetID: AssetID?) -> some View {
        let presentation = CullingFilmstripPresentation(
            assets: model.assets,
            selectedAssetID: model.selectedAssetID
        )
        return VStack(spacing: 6) {
            HStack {
                Text("Filmstrip")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(presentation.positionText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 7) {
                ForEach(presentation.visibleAssets, id: \.id.rawValue) { asset in
                    filmstripTile(
                        for: asset,
                        isSelected: asset.id == model.selectedAssetID,
                        isRecommended: asset.id == recommendedAssetID,
                        decisionState: presentation.decisionState(for: asset)
                    )
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 82)
        .background(Color.black.opacity(0.18))
        .liveMockupPlaceholder(.cullingFilmstrip)
        .task(id: presentation.requestID) {
            requestFilmstripPreviews(for: presentation.visibleAssets)
        }
    }

    @ViewBuilder
    private func cullingStackRail(presentation: CullingStackRailPresentation) -> some View {
        if presentation.isVisible {
            HStack(spacing: 10) {
                Label(presentation.titleText, systemImage: "rectangle.stack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                Text(presentation.positionText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let rationaleText = presentation.rationaleText {
                    Text(rationaleText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let primaryAction = presentation.actions.first {
                    Button {
                        keepSelectedStackFrame()
                    } label: {
                        Label(primaryAction.title, systemImage: "checkmark.circle.fill")
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
                    .disabled(!primaryAction.isEnabled)
                    .help(primaryAction.help)
                    .liveMockupPlaceholder(primaryAction.liveMockupPlaceholder)
                }
                ForEach(Array(presentation.actions.dropFirst())) { action in
                    Button(action.title) {
                        performCullingStackAction(action.action)
                    }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!action.isEnabled)
                        .help(action.help)
                        .liveMockupPlaceholder(action.liveMockupPlaceholder)
                }
                HStack(spacing: 5) {
                    ForEach(presentation.items, id: \.assetID.rawValue) { item in
                        Button {
                            model.select(item.assetID)
                        } label: {
                            HStack(spacing: 2) {
                                if item.isRecommended {
                                    Text("✦")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text(item.label)
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                            }
                            .frame(width: item.isRecommended ? 32 : 24, height: 22)
                            .foregroundStyle(item.isSelected ? Color.black : Color.orange)
                            .background(item.isSelected ? Color.orange : Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.orange.opacity(item.isSelected ? 0.4 : 0.26))
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if !item.flawBadges.isEmpty {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 6, height: 6)
                                        .offset(x: 1, y: 1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(stackChipFlawHelpText(item))
                        .accessibilityLabel("Stack frame \(item.label)")
                        .accessibilityValue(stackChipAccessibilityValue(item))
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Color.black.opacity(0.23))
            .liveMockupPlaceholder(.cullingStackCull)
        }
    }

    private func stackChipFlawHelpText(_ item: CullingStackRailPresentation.Item) -> String {
        guard !item.flawBadges.isEmpty else { return "" }
        return "Frame \(item.label): \(item.flawBadges.map(\.text).joined(separator: ", "))"
    }

    private func stackChipAccessibilityValue(_ item: CullingStackRailPresentation.Item) -> String {
        var segments = [item.isSelected ? "Selected" : (item.isRecommended ? "Recommended" : "Not selected")]
        segments.append(contentsOf: item.flawBadges.map(\.text))
        return segments.joined(separator: ", ")
    }

    private var cullingStackPresentation: CullingStackRailPresentation {
        CullingStackRailPresentation(
            assets: model.assets,
            selectedAssetID: model.selectedAssetID,
            evaluationSignalsByAssetID: model.selectedCullingStackEvaluationSignals(),
            explicitStackScope: model.selectedCullingStackScope
        )
    }

    private func cullingStackGuidanceAction(in presentation: CullingStackRailPresentation) -> CullingStackActionPresentation? {
        presentation.actions.dropFirst().first { action in
            guard action.isEnabled else { return false }
            switch action.action {
            case .keepRecommended, .keepTopRanked:
                return true
            case .keepSelectedAndRejectAlternates, .keepAll:
                return false
            }
        }
    }

    private func filmstripTile(
        for asset: Asset,
        isSelected: Bool,
        isRecommended: Bool,
        decisionState: CullingFilmstripPresentation.DecisionState
    ) -> some View {
        Button {
            model.select(asset.id)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black.opacity(0.55))
                if let previewURL = model.gridPreviewURL(for: asset.id) {
                    CachedPreviewImage(
                        previewURL: previewURL,
                        scaling: .fit,
                        cacheGeneration: model.previewCacheGeneration(for: asset.id)
                    )
                    .padding(2)
                } else {
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                filmstripDecisionOverlay(for: asset)
                    .padding(4)
                if isRecommended {
                    Text("✦")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(3)
                        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(3)
                }
            }
            .frame(width: 64, height: 44)
            .opacity(decisionState.isDimmed ? 0.45 : 1.0)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .top) {
                filmstripDecisionBar(decisionState)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isSelected ? Color.orange : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(asset.originalURL.lastPathComponent)
        .accessibilityValue(filmstripTileAccessibilityValue(isSelected: isSelected, isRecommended: isRecommended, decisionState: decisionState))
    }

    @ViewBuilder
    private func filmstripDecisionBar(_ decisionState: CullingFilmstripPresentation.DecisionState) -> some View {
        switch decisionState {
        case .undecided:
            EmptyView()
        case .picked:
            Rectangle().fill(Color.green).frame(height: 3)
        case .rejected:
            Rectangle().fill(Color.red).frame(height: 3)
        }
    }

    private func filmstripTileAccessibilityValue(
        isSelected: Bool,
        isRecommended: Bool,
        decisionState: CullingFilmstripPresentation.DecisionState
    ) -> String {
        var segments = [isSelected ? "Selected" : (isRecommended ? "Recommended" : "Not selected")]
        switch decisionState {
        case .undecided:
            break
        case .picked:
            segments.append("Picked")
        case .rejected:
            segments.append("Rejected")
        }
        return segments.joined(separator: ", ")
    }

    @ViewBuilder
    private func filmstripDecisionOverlay(for asset: Asset) -> some View {
        if asset.metadata.flag != nil || asset.metadata.rating > 0 {
            HStack(spacing: 4) {
                if let flag = asset.metadata.flag {
                    Image(systemName: flag == .pick ? "flag.fill" : "xmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(flag == .pick ? .green : .red)
                }
                if asset.metadata.rating > 0 {
                    Text("\(asset.metadata.rating)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private var cullingCommandRail: some View {
        HStack(spacing: 14) {
            cullingActionButton(key: "P", title: "Pick", color: .green, shortcut: .pick)
            cullingActionButton(key: "X", title: "Reject", color: .red, shortcut: .reject)
            cullingActionButton(key: "U", title: "Clear", color: .secondary, shortcut: .clearFlag)

            Divider()
                .frame(height: 22)

            HStack(spacing: 4) {
                ForEach(Array(1...5), id: \.self) { rating in
                    Button {
                        applyCullingShortcut(.rating(rating))
                    } label: {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(rating <= (model.selectedAsset?.metadata.rating ?? 0) ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 22, height: 24)
                    .help("Rate \(rating)")
                }
                Button {
                    applyCullingShortcut(.rating(0))
                } label: {
                    Text("0")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 24)
                .help("Clear rating")
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))

            HStack(spacing: 8) {
                ForEach(ColorLabel.allCases, id: \.self) { label in
                    Button {
                        applyCullingShortcut(.colorLabel(label))
                    } label: {
                        Circle()
                            .fill(color(for: label))
                            .frame(width: 13, height: 13)
                            .overlay {
                                if model.selectedAsset?.metadata.colorLabel == label {
                                    Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help("\(label.rawValue.capitalized) label")
                }
                Button {
                    applyCullingShortcut(.colorLabel(nil))
                } label: {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("Clear label")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(.bar)
    }

    private func cullingActionButton(key: String, title: String, color: Color, shortcut: CullingShortcut) -> some View {
        Button {
            applyCullingShortcut(shortcut)
        } label: {
            HStack(spacing: 7) {
                Text(key)
                    .font(.caption2.monospaced().weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(color.opacity(0.55))
                    }
            }
            .foregroundStyle(color)
            .frame(width: 34)
            .frame(height: 34)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(color.opacity(0.28))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func loupeMetadataOverlay(for asset: Asset) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
                Button {
                    revealOriginal(for: asset)
                } label: {
                    Image(systemName: "folder")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(asset.availability.requiresCachedPreviewOnly)
                .help("Reveal original")
                .accessibilityLabel("Reveal original")
            }
            if let positionText = model.selectedAssetPositionText {
                Text(positionText)
                    .foregroundStyle(.secondary)
                    .font(.caption2.monospaced())
                    .lineLimit(1)
            }
            if let status = AssetSourceStatusPresentation.presentation(for: asset.availability) {
                Label(status.detail, systemImage: status.systemImage)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(status.tint)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func applyCullingShortcut(_ shortcut: CullingShortcut) {
        do {
            try model.applyCullingShortcut(shortcut)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func keepSelectedStackFrame() {
        do {
            try model.keepSelectedStackFrameAndRejectAlternates()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func keepRecommendedStackFrame(_ assetID: AssetID) {
        model.select(assetID)
        keepSelectedStackFrame()
    }

    private func keepTopRankedStackFrames(_ assetIDs: [AssetID]) {
        do {
            try model.keepTopRankedFramesInSelectedCullingStack(assetIDs: assetIDs)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func performCullingStackAction(_ action: CullingStackAction) {
        switch action {
        case .keepSelectedAndRejectAlternates:
            keepSelectedStackFrame()
        case .keepRecommended(let assetID):
            keepRecommendedStackFrame(assetID)
        case .keepTopRanked(let assetIDs):
            keepTopRankedStackFrames(assetIDs)
        case .keepAll:
            keepAllFramesInSelectedStack()
        }
    }

    private func keepAllFramesInSelectedStack() {
        do {
            try model.keepAllFramesInSelectedCullingStack()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func requestFilmstripPreviews(for assets: [Asset]) {
        do {
            for asset in assets {
                try model.requestVisibleGridPreview(assetID: asset.id)
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func revealOriginal(for asset: Asset) {
        do {
            guard let originalURL = try model.originalAccessURL(for: asset.id) else {
                model.errorMessage = "Original is unavailable"
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([originalURL])
        } catch {
            model.errorMessage = error.localizedDescription
        }
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

struct LibraryTopBarModeItem: Equatable, Identifiable {
    var title: String
    var systemImage: String
    var mode: LibraryViewMode
    var liveMockupPlaceholder: LiveMockupPlaceholder?

    var id: String {
        mode.rawValue
    }
}

struct LibraryTopBarPresentation: Equatable {
    var catalogTitle: String
    var catalogSubtitle: String
    var scopeTitle: String
    var breadcrumbItems: [String]
    var filterSummaryText: String?
    var selectedView: LibraryViewMode

    init(
        catalogTitle: String,
        libraryTitle: String,
        libraryCountText: String,
        selectedView: LibraryViewMode,
        activeFilterChips: [String]
    ) {
        let trimmedCatalogTitle = catalogTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = libraryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCatalogTitle = trimmedCatalogTitle.isEmpty ? "Local Catalog" : trimmedCatalogTitle
        let resolvedTitle = trimmedTitle.isEmpty ? "All Photographs" : trimmedTitle

        self.catalogTitle = resolvedCatalogTitle
        self.catalogSubtitle = libraryCountText
        self.scopeTitle = resolvedTitle
        self.breadcrumbItems = Self.breadcrumbItems(scopeTitle: resolvedTitle, selectedView: selectedView)
        self.filterSummaryText = Self.filterSummaryText(for: activeFilterChips)
        self.selectedView = selectedView
    }

    var modeItems: [LibraryTopBarModeItem] {
        Self.modeItems
    }

    private static let modeItems = [
        LibraryTopBarModeItem(title: "Grid", systemImage: "square.grid.3x3.fill", mode: .grid),
        LibraryTopBarModeItem(title: "Search", systemImage: "magnifyingglass", mode: .search, liveMockupPlaceholder: .agenticSearch),
        LibraryTopBarModeItem(title: "Copilot", systemImage: "wand.and.stars", mode: .copilot, liveMockupPlaceholder: .copilotLibrary),
        LibraryTopBarModeItem(title: "Timeline", systemImage: "calendar", mode: .timeline, liveMockupPlaceholder: .timelineLibrary),
        LibraryTopBarModeItem(title: "Loupe", systemImage: "rectangle.inset.filled", mode: .loupe),
        LibraryTopBarModeItem(title: "Compare", systemImage: "rectangle.grid.2x2", mode: .compare, liveMockupPlaceholder: .compareSurvey),
        LibraryTopBarModeItem(title: "People", systemImage: "person.2", mode: .people, liveMockupPlaceholder: .peopleSidebar)
    ]

    private static func breadcrumbItems(scopeTitle: String, selectedView: LibraryViewMode) -> [String] {
        if selectedView == .search || selectedView == .copilot || selectedView == .timeline || selectedView == .people {
            return ["Library", scopeTitle]
        }
        if scopeTitle == "All Photographs" {
            return ["Library", scopeTitle]
        }
        return ["Library", "All Photographs", scopeTitle]
    }

    private static func filterSummaryText(for chips: [String]) -> String? {
        guard !chips.isEmpty else { return nil }
        return "\(chips.count) \(chips.count == 1 ? "filter" : "filters")"
    }
}

struct BatchKeywordSuggestionPresentation: Equatable, Identifiable {
    var keyword: String
    var title: String
    var detail: String
    var isEnabled: Bool
    var placeholder: LiveMockupPlaceholder?

    var id: String { keyword }

    static func rows(for suggestions: [BatchKeywordSuggestion], limit: Int = 3) -> [BatchKeywordSuggestionPresentation] {
        guard limit > 0 else { return [] }
        return suggestions.prefix(limit).map { suggestion in
            BatchKeywordSuggestionPresentation(
                keyword: suggestion.keyword,
                title: "Apply \(suggestion.keyword)",
                detail: "\(suggestion.assetCountText) at \(suggestion.confidenceText)",
                isEnabled: true,
                placeholder: nil
            )
        }
    }
}

struct BatchMetadataDraft: Equatable {
    var keywords: String = ""
    var caption: String = ""
    var creator: String = ""
    var copyright: String = ""

    var hasContentToApply: Bool {
        !keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !creator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !copyright.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var keywordChips: [String] {
        Self.keywordChips(from: keywords)
    }

    mutating func appendKeyword(_ keyword: String) {
        let cleanedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedKeyword.isEmpty else { return }
        var existingKeywords = keywordChips
        let key = cleanedKeyword.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !existingKeywords.contains(where: {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) == key
        }) else { return }
        existingKeywords.append(cleanedKeyword)
        keywords = existingKeywords.joined(separator: ", ")
    }

    private static func keywordChips(from text: String) -> [String] {
        var seen: Set<String> = []
        return text
            .split(separator: ",")
            .compactMap { token -> String? in
                let keyword = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !keyword.isEmpty else { return nil }
                let key = keyword.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                guard seen.insert(key).inserted else { return nil }
                return keyword
            }
    }
}

enum BatchScopeMode: String, CaseIterable, Identifiable {
    case selected
    case visible
    case currentScope

    var id: Self { self }

    var title: String {
        switch self {
        case .selected:
            return "Selected"
        case .visible:
            return "Visible"
        case .currentScope:
            return "Current Scope"
        }
    }
}

struct BatchMetadataReviewPresentation: Equatable {
    var countText: String
    var suggestionRows: [BatchKeywordSuggestionPresentation]
    var draftKeywordChips: [String]
    var draftKeywordCountText: String?
    var isApplyEnabled: Bool
    var applyTitle: String
    var confirmationText: String?

    init(
        visibleAssetCount: Int,
        selectedAssetCount: Int,
        currentScopeAssetCount: Int,
        selectedScope: BatchScopeMode,
        requiresAllCatalogConfirmation: Bool,
        isAllCatalogConfirmed: Bool,
        suggestions: [BatchKeywordSuggestion],
        draft: BatchMetadataDraft
    ) {
        draftKeywordChips = draft.keywordChips
        draftKeywordCountText = draftKeywordChips.isEmpty
            ? nil
            : "\(draftKeywordChips.count) \(draftKeywordChips.count == 1 ? "keyword" : "keywords") to add"
        switch selectedScope {
        case .selected:
            countText = "\(selectedAssetCount) selected \(selectedAssetCount == 1 ? "photo" : "photos")"
            suggestionRows = BatchKeywordSuggestionPresentation.rows(for: suggestions, limit: 6)
            isApplyEnabled = selectedAssetCount > 0 && draft.hasContentToApply
            applyTitle = "Apply to selected batch"
            confirmationText = nil
        case .visible:
            countText = "\(visibleAssetCount) visible \(visibleAssetCount == 1 ? "photo" : "photos")"
            suggestionRows = BatchKeywordSuggestionPresentation.rows(for: suggestions, limit: 6)
            isApplyEnabled = visibleAssetCount > 0 && draft.hasContentToApply
            applyTitle = "Apply to visible batch"
            confirmationText = nil
        case .currentScope:
            countText = "\(currentScopeAssetCount) \(currentScopeAssetCount == 1 ? "photo" : "photos") in current scope"
            suggestionRows = BatchKeywordSuggestionPresentation.rows(for: suggestions, limit: 6)
            confirmationText = requiresAllCatalogConfirmation
                ? "Confirm applying metadata to all \(currentScopeAssetCount) catalog \(currentScopeAssetCount == 1 ? "photo" : "photos")."
                : nil
            isApplyEnabled = currentScopeAssetCount > 0
                && draft.hasContentToApply
                && (!requiresAllCatalogConfirmation || isAllCatalogConfirmed)
            applyTitle = "Apply to current scope"
        }
    }
}

struct ExportReviewPresentation: Equatable {
    var countText: String
    var isExportEnabled: Bool
    var exportTitle: String
    var confirmationText: String?

    init(
        visibleAssetCount: Int,
        selectedAssetCount: Int,
        currentScopeAssetCount: Int,
        selectedScope: BatchScopeMode,
        requiresAllCatalogConfirmation: Bool,
        isAllCatalogConfirmed: Bool,
        isExporting: Bool
    ) {
        switch selectedScope {
        case .selected:
            countText = "\(selectedAssetCount) selected \(selectedAssetCount == 1 ? "photo" : "photos")"
            confirmationText = nil
            isExportEnabled = selectedAssetCount > 0 && !isExporting
            exportTitle = "Export selected batch"
        case .visible:
            countText = "\(visibleAssetCount) visible \(visibleAssetCount == 1 ? "photo" : "photos")"
            confirmationText = nil
            isExportEnabled = visibleAssetCount > 0 && !isExporting
            exportTitle = "Export visible batch"
        case .currentScope:
            countText = "\(currentScopeAssetCount) \(currentScopeAssetCount == 1 ? "photo" : "photos") in current scope"
            confirmationText = requiresAllCatalogConfirmation
                ? "Confirm exporting all \(currentScopeAssetCount) catalog \(currentScopeAssetCount == 1 ? "photo" : "photos")."
                : nil
            isExportEnabled = currentScopeAssetCount > 0
                && !isExporting
                && (!requiresAllCatalogConfirmation || isAllCatalogConfirmed)
            exportTitle = "Export current scope"
        }
    }
}

struct CompareSurveyPresentation: Equatable {
    private static let maximumSurveyColumnCount = 4

    var primaryAsset: Asset?
    var alternateAssets: [Asset]
    var framePositionText: String?
    var groupCountText: String
    var groupKindText: String
    var recommendationText: String
    var recommendedAssetID: AssetID?
    private var recommendedFrameLabel: String?
    private var signalBadgesByAssetID: [AssetID: [CompareDecisionBadge]]

    init(
        assets: [Asset],
        selectedAssetID: AssetID?,
        evaluationSignalsByAssetID: [AssetID: [EvaluationSignal]] = [:],
        groupKind: CompareGroupKind = .nearbyFrames
    ) {
        guard !assets.isEmpty else {
            self.primaryAsset = nil
            self.alternateAssets = []
            self.framePositionText = nil
            self.groupCountText = "No frames"
            self.groupKindText = "Compare set"
            self.recommendationText = "No comparison set"
            self.recommendedAssetID = nil
            self.recommendedFrameLabel = nil
            self.signalBadgesByAssetID = [:]
            return
        }

        let primaryIndex = selectedAssetID.flatMap { selectedID in
            assets.firstIndex { $0.id == selectedID }
        } ?? 0

        self.primaryAsset = assets[primaryIndex]
        self.alternateAssets = assets.enumerated().compactMap { index, asset in
            index == primaryIndex ? nil : asset
        }
        self.framePositionText = "Frame \(primaryIndex + 1) of \(assets.count)"
        self.groupCountText = "\(assets.count) \(assets.count == 1 ? "frame" : "frames")"
        self.groupKindText = switch groupKind {
        case .candidateStack:
            "Candidate stack"
        case .nearbyFrames:
            "Compare set"
        }

        let rankedCandidates = CullingStackRecommendation.rankedCandidates(
            stackAssetIDs: assets.map(\.id),
            evaluationSignalsByAssetID: evaluationSignalsByAssetID
        )
        let recommendation = rankedCandidates.first
        self.recommendedAssetID = recommendation?.assetID
        self.recommendedFrameLabel = recommendation?.frameLabel
        self.signalBadgesByAssetID = Self.signalBadges(
            assetIDs: assets.map(\.id),
            bestAssetID: rankedCandidates.count >= 2 ? rankedCandidates.first?.assetID : nil,
            evaluationSignalsByAssetID: evaluationSignalsByAssetID
        )
        let recommendationPhrases = recommendation.map { winner in
            CullingStackRecommendation.rationalePhrases(
                forWinner: winner.assetID,
                stackAssetIDs: assets.map(\.id),
                evaluationSignalsByAssetID: evaluationSignalsByAssetID
            )
        } ?? []
        self.recommendationText = Self.recommendationText(
            rankedCandidates: rankedCandidates,
            recommendationPhrases: recommendationPhrases,
            primaryAsset: self.primaryAsset,
            rejectCount: max(assets.count - 1, 0)
        )
    }

    var primaryDecisionText: String {
        guard let primaryAsset else { return "No frame selected" }
        return Self.decisionSummary(for: primaryAsset)
    }

    private static func recommendationText(
        rankedCandidates: [CullingStackRecommendation],
        recommendationPhrases: [String],
        primaryAsset: Asset?,
        rejectCount: Int
    ) -> String {
        guard let recommendation = rankedCandidates.first else {
            return "No ranking yet"
        }
        guard recommendation.assetID == primaryAsset?.id else {
            guard recommendationPhrases.isEmpty else {
                return "Top signal: frame \(recommendation.frameLabel) — \(recommendationPhrases.joined(separator: ", "))"
            }
            return "Top signal: frame \(recommendation.frameLabel)"
        }
        guard rejectCount > 0 else {
            return "Suggests: keep 1"
        }
        return "Suggests: keep 1 · reject \(rejectCount)"
    }

    var orderedAssets: [Asset] {
        guard let primaryAsset else { return alternateAssets }
        return [primaryAsset] + alternateAssets
    }

    var surveyColumnCount: Int {
        min(Self.maximumSurveyColumnCount, max(orderedAssets.count, 1))
    }

    var surveyRowCount: Int {
        guard !orderedAssets.isEmpty else { return 0 }
        return (orderedAssets.count + surveyColumnCount - 1) / surveyColumnCount
    }

    var groupActionText: String {
        guard primaryAsset != nil else { return "No group action" }
        let rejectCount = alternateAssets.count
        if let recommendedFrameLabel,
           let recommendedAssetID,
           recommendedAssetID != primaryAsset?.id,
           rejectCount > 0 {
            return "Keep top signal \(recommendedFrameLabel) · reject \(rejectCount)"
        }
        guard rejectCount > 0 else { return "Keep primary" }
        return "Keep primary · reject \(rejectCount)"
    }

    var groupActionHelp: String {
        if let recommendedAssetID,
           recommendedAssetID != primaryAsset?.id {
            return "Marks the top signal frame as Pick and the visible alternates as Reject"
        }
        return "Marks the current compare primary as Pick and the visible alternates as Reject"
    }

    func groupActions(canApplyPrimaryChoice: Bool) -> [CompareSurveyActionPresentation] {
        let primaryAction: CompareSurveyActionPresentation.Action = if let recommendedAssetID,
                                                                       recommendedAssetID != primaryAsset?.id {
            .keepRecommendedAndRejectAlternates(recommendedAssetID)
        } else {
            .keepPrimaryAndRejectAlternates
        }
        return [
            CompareSurveyActionPresentation(
                action: primaryAction,
                title: groupActionText,
                isEnabled: canApplyPrimaryChoice && primaryAsset != nil,
                help: groupActionHelp,
                liveMockupPlaceholder: nil
            ),
            CompareSurveyActionPresentation(
                action: .keepAll,
                title: "Keep all",
                isEnabled: canApplyPrimaryChoice && !orderedAssets.isEmpty,
                help: "Marks every frame in the current compare set as Pick",
                liveMockupPlaceholder: nil
            ),
            CompareSurveyActionPresentation(
                action: .chooseManually,
                title: "Choose manually",
                isEnabled: canApplyPrimaryChoice && orderedAssets.count > 1,
                help: "Open this compare set in stack-aware manual culling",
                liveMockupPlaceholder: nil
            )
        ]
    }

    func decisionBadges(for asset: Asset) -> [CompareDecisionBadge] {
        var badges: [CompareDecisionBadge] = []
        if asset.id == primaryAsset?.id {
            badges.append(CompareDecisionBadge(text: "PRIMARY", tone: .primary))
        }
        if let flag = asset.metadata.flag {
            switch flag {
            case .pick:
                badges.append(CompareDecisionBadge(text: "PICKED", tone: .positive))
            case .reject:
                badges.append(CompareDecisionBadge(text: "REJECTED", tone: .destructive))
            }
            return badges
        }
        if asset.metadata.rating > 0 {
            badges.append(CompareDecisionBadge(text: "\(asset.metadata.rating) STAR", tone: .rating))
        }
        if let colorLabel = asset.metadata.colorLabel {
            badges.append(CompareDecisionBadge(text: colorLabel.rawValue.uppercased(), tone: .label))
        }
        return badges
    }

    /// Signal-derived read badges (BEST / EYES CLOSED / SOFT). Separate from
    /// decisionBadges so metadata badges never claim machine reads.
    func signalBadges(for asset: Asset) -> [CompareDecisionBadge] {
        signalBadgesByAssetID[asset.id] ?? []
    }

    private static let softFocusBadgeThreshold = 0.5

    private static func signalBadges(
        assetIDs: [AssetID],
        bestAssetID: AssetID?,
        evaluationSignalsByAssetID: [AssetID: [EvaluationSignal]]
    ) -> [AssetID: [CompareDecisionBadge]] {
        var badgesByAssetID: [AssetID: [CompareDecisionBadge]] = [:]
        for assetID in assetIDs {
            if assetID == bestAssetID {
                badgesByAssetID[assetID] = [CompareDecisionBadge(text: "✦ BEST", tone: .best)]
                continue
            }
            badgesByAssetID[assetID] = flawBadges(for: evaluationSignalsByAssetID[assetID] ?? [])
        }
        return badgesByAssetID
    }

    /// Compact flaw reads (EYES CLOSED / SOFT) derived straight from
    /// persisted signals. Shared with other frame surfaces (e.g. the stack
    /// rail chips) so the wording and tone stay identical everywhere a flaw
    /// badge appears.
    static func flawBadges(for signals: [EvaluationSignal]) -> [CompareDecisionBadge] {
        var badges: [CompareDecisionBadge] = []
        if let eyesOpen = highestConfidenceScore(kind: .eyesOpen, in: signals), eyesOpen < 1.0 {
            badges.append(CompareDecisionBadge(text: "EYES CLOSED", tone: .destructive))
        }
        if let focus = highestConfidenceScore(kind: .focus, in: signals), focus < softFocusBadgeThreshold {
            badges.append(CompareDecisionBadge(text: "SOFT", tone: .destructive))
        }
        return badges
    }

    private static func highestConfidenceScore(kind: EvaluationKind, in signals: [EvaluationSignal]) -> Double? {
        signals
            .filter { $0.kind == kind }
            .sorted { $0.confidence > $1.confidence }
            .compactMap { signal -> Double? in
                guard case .score(let score) = signal.value else { return nil }
                return score
            }
            .first
    }

    static func decisionSummary(for asset: Asset) -> String {
        if let flag = asset.metadata.flag {
            switch flag {
            case .pick:
                return "Picked"
            case .reject:
                return "Rejected"
            }
        }
        if asset.metadata.rating > 0 {
            return "\(asset.metadata.rating) \(asset.metadata.rating == 1 ? "star" : "stars")"
        }
        if let colorLabel = asset.metadata.colorLabel {
            return "\(colorLabel.rawValue.capitalized) label"
        }
        return "Unreviewed"
    }
}

struct CompareSurveyActionPresentation: Equatable, Identifiable {
    enum Action: Equatable {
        case keepPrimaryAndRejectAlternates
        case keepRecommendedAndRejectAlternates(AssetID)
        case keepAll
        case chooseManually
    }

    var action: Action
    var title: String
    var isEnabled: Bool
    var help: String
    var liveMockupPlaceholder: LiveMockupPlaceholder?

    var id: String {
        switch action {
        case .keepPrimaryAndRejectAlternates:
            return "keep-primary-and-reject-alternates"
        case .keepRecommendedAndRejectAlternates(let assetID):
            return "keep-recommended-and-reject-alternates-\(assetID.rawValue)"
        case .keepAll:
            return "keep-all"
        case .chooseManually:
            return "choose-manually"
        }
    }
}

struct CompareDecisionBadge: Equatable, Identifiable {
    enum Tone: String, Equatable {
        case primary
        case positive
        case destructive
        case rating
        case label
        case best
    }

    var text: String
    var tone: Tone

    var id: String {
        "\(tone.rawValue):\(text)"
    }
}

struct CompareFocusMetric: Equatable, Identifiable {
    enum Tone: String, Equatable {
        case waiting
        case positive
        case caution
        case neutral
    }

    var title: String
    var value: String
    var detail: String
    var tone: Tone

    var id: String {
        "\(tone.rawValue):\(title):\(value):\(detail)"
    }
}

enum CompareFocusMetricPresentation {
    private static let qualityKinds: [EvaluationKind] = [
        .focus,
        .motionBlur,
        .exposure,
        .framing,
        .aesthetics,
        .faceQuality,
        .eyeSharpness,
        .eyesOpen,
        .smile
    ]

    static func metrics(for signals: [EvaluationSignal]) -> [CompareFocusMetric] {
        let metrics = qualityKinds.compactMap { kind in
            highestConfidenceSignal(for: kind, in: signals).map(metric(for:))
        }
        guard !metrics.isEmpty else {
            return [CompareFocusMetric(
                title: "No read yet",
                value: "Evaluate",
                detail: "No compare quality signals",
                tone: .waiting
            )]
        }
        return metrics
    }

    private static func highestConfidenceSignal(for kind: EvaluationKind, in signals: [EvaluationSignal]) -> EvaluationSignal? {
        signals
            .filter { $0.kind == kind }
            .sorted { lhs, rhs in lhs.confidence > rhs.confidence }
            .first
    }

    private static func metric(for signal: EvaluationSignal) -> CompareFocusMetric {
        CompareFocusMetric(
            title: EvaluationSignalPresentation.displayName(for: signal.kind),
            value: valueText(for: signal),
            detail: "\(EvaluationSignalPresentation.percentage(signal.confidence)) confidence - \(signal.provenance.provider)",
            tone: tone(for: signal)
        )
    }

    private static func valueText(for signal: EvaluationSignal) -> String {
        if let overrideValue = overrideValueText(for: signal) {
            return overrideValue
        }
        switch signal.value {
        case .score(let score):
            return EvaluationSignalPresentation.percentage(score)
        case .label(let label):
            return EvaluationSignalPresentation.capitalized(label, fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .labels(let labels):
            return EvaluationSignalPresentation.capitalized(labels.joined(separator: ", "), fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .text(let text):
            return EvaluationSignalPresentation.capitalized(text, fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .count(let count):
            return String(count)
        case .vector:
            return "Sampled"
        }
    }

    // Signal kinds whose raw 0...1 score reads better as something other than
    // a bare percentage: eyes/smile as plain-language state, exposure as an
    // EV-style delta from neutral so over/under exposure reads at a glance.
    private static func overrideValueText(for signal: EvaluationSignal) -> String? {
        guard case .score(let score) = signal.value else { return nil }
        switch signal.kind {
        case .eyesOpen:
            if score >= 1.0 { return "Open" }
            if score <= 0.0 { return "Shut" }
            return "Some shut"
        case .smile:
            if score >= 1.0 { return "Smiling" }
            if score > 0.0 { return "Some smiling" }
            return "No smile"
        case .exposure:
            return exposureDeltaText(score: score)
        default:
            return nil
        }
    }

    private static let exposureNeutralScore = 0.5
    private static let exposureEVRange = 4.0

    private static func exposureDeltaText(score: Double) -> String {
        let delta = (score - exposureNeutralScore) * exposureEVRange
        let rounded = (delta * 10).rounded() / 10
        guard rounded != 0 else { return "0.0 EV" }
        let sign = rounded > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", rounded)) EV"
    }

    private static func tone(for signal: EvaluationSignal) -> CompareFocusMetric.Tone {
        switch (signal.kind, signal.value) {
        case (.motionBlur, .score(let score)):
            return score >= 0.5 ? .caution : .positive
        case (.focus, .score(let score)),
             (.framing, .score(let score)),
             (.aesthetics, .score(let score)),
             (.faceQuality, .score(let score)):
            return score >= 0.7 ? .positive : .caution
        case (.exposure, _):
            return .neutral
        case (.eyeSharpness, .score(let score)):
            return score >= 0.7 ? .positive : .caution
        case (.eyesOpen, .score(let score)):
            return score >= 1.0 ? .positive : .caution
        case (.smile, _):
            return .neutral
        default:
            return .neutral
        }
    }
}

private enum EvaluationSignalPresentation {
    static func displayName(for kind: EvaluationKind) -> String {
        switch kind {
        case .focus:
            return "Focus"
        case .motionBlur:
            return "Motion blur"
        case .exposure:
            return "Exposure"
        case .aesthetics:
            return "Aesthetics"
        case .framing:
            return "Framing"
        case .object:
            return "Object"
        case .faceCount:
            return "Faces"
        case .faceQuality:
            return "Face quality"
        case .ocrText:
            return "Text"
        case .colorPalette:
            return "Color"
        case .novelty:
            return "Novelty"
        case .visualSimilarity:
            return "Visual similarity"
        case .smile:
            return "Smile"
        case .eyesOpen:
            return "Eyes open"
        case .eyeSharpness:
            return "Eye sharpness"
        }
    }

    static func percentage(_ value: Double) -> String {
        let clamped = min(max(value, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    static func capitalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else {
            return fallback
        }
        return first.uppercased() + trimmed.dropFirst()
    }
}

struct CullingDecisionFeedbackPresentation: Equatable {
    var title: String
    var detail: String
    var accessibilityValue: String

    init(feedback: CullingMetadataDecisionFeedback) {
        title = feedback.decisionText
        detail = feedback.filename
        accessibilityValue = "\(feedback.decisionText), \(feedback.filename)"
    }
}

struct CullingFilmstripPresentation: Equatable {
    static let defaultVisibleLimit = 12

    var visibleAssets: [Asset]
    var selectedIndex: Int?
    var totalCount: Int

    init(
        assets: [Asset],
        selectedAssetID: AssetID?,
        visibleLimit: Int = CullingFilmstripPresentation.defaultVisibleLimit
    ) {
        totalCount = assets.count
        selectedIndex = selectedAssetID.flatMap { selectedID in
            assets.firstIndex { $0.id == selectedID }
        }
        let boundedLimit = max(1, visibleLimit)
        guard assets.count > boundedLimit else {
            visibleAssets = assets
            return
        }
        let anchorIndex = selectedIndex ?? 0
        let proposedStart = anchorIndex - boundedLimit / 2
        let startIndex = min(max(proposedStart, 0), assets.count - boundedLimit)
        visibleAssets = Array(assets[startIndex..<(startIndex + boundedLimit)])
    }

    var positionText: String {
        guard totalCount > 0 else { return "0 frames" }
        guard let selectedIndex else {
            return "\(totalCount) \(totalCount == 1 ? "frame" : "frames")"
        }
        return "Frame \(selectedIndex + 1) of \(totalCount)"
    }

    var requestID: String {
        [
            visibleAssets.map(\.id.rawValue).joined(separator: "\n"),
            selectedIndex.map(String.init) ?? "none",
            String(totalCount)
        ].joined(separator: "\n")
    }

    /// A tile's pick/reject state, so the filmstrip can dim rejects and show
    /// a decision color bar without the view reaching into asset metadata.
    enum DecisionState: Equatable {
        case undecided
        case picked
        case rejected

        init(flag: PickFlag?) {
            switch flag {
            case .pick: self = .picked
            case .reject: self = .rejected
            case nil: self = .undecided
            }
        }

        var isDimmed: Bool { self == .rejected }
    }

    func decisionState(for asset: Asset) -> DecisionState {
        DecisionState(flag: asset.metadata.flag)
    }
}

struct CullingStackRailPresentation: Equatable {
    struct Item: Equatable {
        var assetID: AssetID
        var label: String
        var isSelected: Bool
        var isRecommended: Bool
        var flawBadges: [CompareDecisionBadge]
    }

    var items: [Item]
    var titleText: String
    var positionText: String
    var rationaleText: String?
    var keepActionTitle: String
    var keepActionHelp: String
    var actions: [CullingStackActionPresentation]

    init(
        assets: [Asset],
        selectedAssetID: AssetID?,
        evaluationSignalsByAssetID: [AssetID: [EvaluationSignal]] = [:],
        explicitStackScope: CullingStackScope? = nil,
        stackBuilder: AssetStackBuilder = AssetStackBuilder()
    ) {
        guard let selectedAssetID else {
            items = []
            titleText = ""
            positionText = ""
            rationaleText = nil
            keepActionTitle = ""
            keepActionHelp = ""
            actions = []
            return
        }

        let stackScope: CullingStackScope
        if let explicitStackScope,
           explicitStackScope.assetIDs.contains(selectedAssetID) {
            stackScope = explicitStackScope
        } else {
            let stacks = stackBuilder.stacks(
                from: assets,
                visualSimilarityVectorsByAssetID: Self.visualSimilarityVectorsByAssetID(
                    from: evaluationSignalsByAssetID
                )
            )
            guard let stackIndex = stacks.firstIndex(where: { $0.assetIDs.contains(selectedAssetID) }) else {
                items = []
                titleText = ""
                positionText = ""
                rationaleText = nil
                keepActionTitle = ""
                keepActionHelp = ""
                actions = []
                return
            }
            let stack = stacks[stackIndex]
            stackScope = CullingStackScope(
                assetIDs: stack.assetIDs,
                stackIndex: stackIndex + 1,
                stackCount: stacks.count,
                rationaleText: stack.rationale
            )
        }

        guard stackScope.assetIDs.count > 1,
              let selectedIndex = stackScope.assetIDs.firstIndex(of: selectedAssetID) else {
            items = []
            titleText = ""
            positionText = ""
            rationaleText = nil
            keepActionTitle = ""
            keepActionHelp = ""
            actions = []
            return
        }
        let rankedCandidates = CullingStackRecommendation.rankedCandidates(
            stackAssetIDs: stackScope.assetIDs,
            evaluationSignalsByAssetID: evaluationSignalsByAssetID
        )
        let recommendation = rankedCandidates.first

        items = stackScope.assetIDs.enumerated().map { index, assetID in
            Item(
                assetID: assetID,
                label: "\(index + 1)",
                isSelected: assetID == selectedAssetID,
                isRecommended: assetID == recommendation?.assetID,
                flawBadges: CompareSurveyPresentation.flawBadges(for: evaluationSignalsByAssetID[assetID] ?? [])
            )
        }
        if let stackIndex = stackScope.stackIndex,
           let stackCount = stackScope.stackCount {
            titleText = "Stack \(stackIndex) of \(stackCount)"
        } else {
            titleText = "Stack"
        }
        positionText = "Frame \(selectedIndex + 1) of \(stackScope.assetIDs.count)"
        rationaleText = stackScope.rationaleText
        keepActionTitle = "Keep frame \(selectedIndex + 1) · cut \(stackScope.assetIDs.count - 1)"
        keepActionHelp = "Keep selected frame and reject stack alternates"
        actions = [
            CullingStackActionPresentation(
                action: .keepSelectedAndRejectAlternates,
                title: keepActionTitle,
                isEnabled: true,
                help: keepActionHelp,
                liveMockupPlaceholder: nil
            ),
            Self.rankedAction(
                for: rankedCandidates,
                stackAssetIDs: stackScope.assetIDs,
                evaluationSignalsByAssetID: evaluationSignalsByAssetID
            ),
            CullingStackActionPresentation(
                action: .keepAll,
                title: "Keep all \(stackScope.assetIDs.count)",
                isEnabled: true,
                help: "Keep every frame in this stack.",
                liveMockupPlaceholder: nil
            )
        ].compactMap { $0 }
    }

    var isVisible: Bool {
        !items.isEmpty
    }

    var recommendedAssetID: AssetID? {
        items.first { $0.isRecommended }?.assetID
    }

    private static func visualSimilarityVectorsByAssetID(
        from evaluationSignalsByAssetID: [AssetID: [EvaluationSignal]]
    ) -> [AssetID: [Double]] {
        evaluationSignalsByAssetID.compactMapValues { signals in
            signals
                .filter { $0.kind == .visualSimilarity }
                .compactMap { signal -> (vector: [Double], confidence: Double)? in
                    guard case .vector(let vector) = signal.value else { return nil }
                    return (vector, signal.confidence)
                }
                .max { lhs, rhs in lhs.confidence < rhs.confidence }?
                .vector
        }
    }

    private static func rankedAction(
        for rankedCandidates: [CullingStackRecommendation],
        stackAssetIDs: [AssetID],
        evaluationSignalsByAssetID: [AssetID: [EvaluationSignal]]
    ) -> CullingStackActionPresentation? {
        let topTwo = Array(rankedCandidates.prefix(2))
        if stackAssetIDs.count > 2, topTwo.count >= 2 {
            return CullingStackActionPresentation(
                action: .keepTopRanked(topTwo.map(\.assetID)),
                title: "Keep top 2",
                isEnabled: true,
                help: "Keep the two top-ranked frames based on focus and quality signals.",
                liveMockupPlaceholder: nil,
                assistTitle: "Top 2 frames"
            )
        }

        guard let recommendation = rankedCandidates.first else { return nil }

        let phrases = CullingStackRecommendation.rationalePhrases(
            forWinner: recommendation.assetID,
            stackAssetIDs: stackAssetIDs,
            evaluationSignalsByAssetID: evaluationSignalsByAssetID
        )
        let help = phrases.isEmpty
            ? "Keep frame \(recommendation.frameLabel) based on focus and quality signals."
            : "Keep frame \(recommendation.frameLabel) — \(phrases.joined(separator: ", "))."
        return CullingStackActionPresentation(
            action: .keepRecommended(recommendation.assetID),
            title: "Keep recommended \(recommendation.frameLabel)",
            isEnabled: true,
            help: help,
            liveMockupPlaceholder: nil,
            assistTitle: "Recommended frame \(recommendation.frameLabel)"
        )
    }
}

enum CullingStackAction: Equatable {
    case keepSelectedAndRejectAlternates
    case keepTopRanked([AssetID])
    case keepRecommended(AssetID)
    case keepAll
}

struct CullingStackActionPresentation: Equatable, Identifiable {
    var action: CullingStackAction
    var title: String
    var isEnabled: Bool
    var help: String
    var liveMockupPlaceholder: LiveMockupPlaceholder?
    var assistTitle: String?

    init(
        action: CullingStackAction,
        title: String,
        isEnabled: Bool,
        help: String,
        liveMockupPlaceholder: LiveMockupPlaceholder?,
        assistTitle: String? = nil
    ) {
        self.action = action
        self.title = title
        self.isEnabled = isEnabled
        self.help = help
        self.liveMockupPlaceholder = liveMockupPlaceholder
        self.assistTitle = assistTitle
    }

    var id: String {
        switch action {
        case .keepSelectedAndRejectAlternates:
            return "keep-selected-and-reject-alternates"
        case .keepTopRanked(let assetIDs):
            return "keep-top-ranked-\(assetIDs.map(\.rawValue).joined(separator: "-"))"
        case .keepRecommended(let assetID):
            return "keep-recommended-\(assetID.rawValue)"
        case .keepAll:
            return "keep-all"
        }
    }
}

struct CullingStackRecommendation: Equatable {
    var assetID: AssetID
    var frameLabel: String
    var score: Double

    static func rankedCandidates(
        stackAssetIDs: [AssetID],
        evaluationSignalsByAssetID: [AssetID: [EvaluationSignal]]
    ) -> [CullingStackRecommendation] {
        let candidates = stackAssetIDs.enumerated().compactMap { index, assetID -> CullingStackRecommendation? in
            guard let score = qualityScore(for: evaluationSignalsByAssetID[assetID] ?? []) else {
                return nil
            }
            return CullingStackRecommendation(assetID: assetID, frameLabel: "\(index + 1)", score: score)
        }
        return candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.frameLabel < rhs.frameLabel
        }
    }

    private static func qualityScore(for signals: [EvaluationSignal]) -> Double? {
        var scoreByKind: [EvaluationKind: Double] = [:]
        for signal in signals {
            guard let weightedScore = weightedQualityScore(for: signal) else { continue }
            scoreByKind[signal.kind] = max(scoreByKind[signal.kind] ?? 0, weightedScore)
        }
        guard !scoreByKind.isEmpty else { return nil }
        return scoreByKind.values.reduce(0, +)
    }

    // Defect-inverted score plus confidence-scaled weight for one signal.
    // weightedQualityScore and normalizedQualityRead both derive from this,
    // so the pill's read and the stack ranking can never disagree.
    static func qualityComponent(for signal: EvaluationSignal) -> (score: Double, weight: Double)? {
        guard case .score(let rawScore) = signal.value else { return nil }
        let clampedScore = min(max(rawScore, 0), 1)
        let confidence = min(max(signal.confidence, 0), 1)
        switch signal.kind {
        case .focus:
            return (clampedScore, confidence * 100)
        case .eyesOpen:
            return (clampedScore, confidence * 90)
        case .faceQuality:
            return (clampedScore, confidence * 80)
        case .eyeSharpness:
            return (clampedScore, confidence * 70)
        case .motionBlur:
            return (1 - clampedScore, confidence * 60)
        case .aesthetics:
            return (clampedScore, confidence * 50)
        case .framing:
            return (clampedScore, confidence * 45)
        default:
            return nil
        }
    }

    private static func weightedQualityScore(for signal: EvaluationSignal) -> Double? {
        guard let component = qualityComponent(for: signal) else { return nil }
        return component.score * component.weight
    }

    // Confidence-weighted mean of the best component per kind, 0...1.
    static func normalizedQualityRead(for signals: [EvaluationSignal]) -> (score: Double, kindCount: Int)? {
        var bestComponentByKind: [EvaluationKind: (score: Double, weight: Double)] = [:]
        for signal in signals {
            guard let component = qualityComponent(for: signal) else { continue }
            if let existing = bestComponentByKind[signal.kind],
               existing.score * existing.weight >= component.score * component.weight {
                continue
            }
            bestComponentByKind[signal.kind] = component
        }
        let totalWeight = bestComponentByKind.values.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let weightedScore = bestComponentByKind.values.reduce(0) { $0 + $1.score * $1.weight } / totalWeight
        return (weightedScore, bestComponentByKind.count)
    }

    /// Short honest reasons why the winner leads the stack, in display order.
    static func rationalePhrases(
        forWinner winner: AssetID,
        stackAssetIDs: [AssetID],
        evaluationSignalsByAssetID: [AssetID: [EvaluationSignal]]
    ) -> [String] {
        var phrases: [String] = []
        let focusScores = stackAssetIDs.compactMap { assetID in
            bestScore(kind: .focus, in: evaluationSignalsByAssetID[assetID] ?? []).map { (assetID: assetID, score: $0) }
        }
        if focusScores.count >= 2,
           let winnerFocus = focusScores.first(where: { $0.assetID == winner })?.score,
           focusScores.allSatisfy({ $0.assetID == winner || $0.score < winnerFocus }) {
            phrases.append("sharpest")
        }
        if let eyesOpen = bestScore(kind: .eyesOpen, in: evaluationSignalsByAssetID[winner] ?? []),
           eyesOpen >= 1.0 {
            phrases.append("eyes open")
        }
        return phrases
    }

    private static func bestScore(kind: EvaluationKind, in signals: [EvaluationSignal]) -> Double? {
        signals
            .filter { $0.kind == kind }
            .compactMap { signal -> Double? in
                guard case .score(let score) = signal.value else { return nil }
                return score
            }
            .max()
    }
}

private struct CompareView: View {
    var model: AppModel
    var focusCullingSurface: () -> Void

    private let focusMetricColumns = [GridItem(.adaptive(minimum: 78), spacing: 5)]

    var body: some View {
        let compareAssets = model.compareAssets()
        let presentation = CompareSurveyPresentation(
            assets: compareAssets,
            selectedAssetID: model.selectedAssetID,
            evaluationSignalsByAssetID: Dictionary(uniqueKeysWithValues: compareAssets.map { asset in
                (asset.id, model.evaluationSignals(for: asset.id))
            }),
            groupKind: model.compareGroupKind()
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                compareHeader(presentation)
                if let completion = model.cullingSessionCompletion {
                    CullingCompletionBannerView(
                        summary: completion,
                        canViewPicks: completion.picksSetID != nil,
                        viewPicks: { openCullingSessionPicks() },
                        dismiss: { model.dismissCullingSessionCompletion() }
                    )
                }
                if let primaryAsset = presentation.primaryAsset {
                    surveyLayout(presentation)
                    compareActionStrip(primaryAsset: primaryAsset, presentation: presentation)
                } else {
                    emptyCompareSet
                        .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
        }
        .background(Color.black.opacity(0.24))
        .task(id: comparePreviewTaskID) {
            requestComparePreviews()
        }
        .liveMockupPlaceholder(.compareSurvey)
    }

    private func openCullingSessionPicks() {
        do {
            try model.openCullingSessionPicks()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private var emptyCompareSet: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No compare set")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func compareHeader(_ presentation: CompareSurveyPresentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label("Survey Compare", systemImage: "rectangle.grid.2x2")
                .font(.headline)
            Text(presentation.groupKindText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(presentation.groupCountText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if let framePositionText = presentation.framePositionText {
                Text(framePositionText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                requestCompareEvaluations()
            } label: {
                Label("Evaluate Compare", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!model.canRequestCompareAssetEvaluations)
            .help("Runs evaluation for compare frames with cached previews")
            .liveMockupPlaceholder(.focusCompare)
            Label(presentation.recommendationText, systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.orange.opacity(0.26))
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func surveyLayout(_ presentation: CompareSurveyPresentation) -> some View {
        LazyVGrid(columns: surveyColumns(for: presentation), alignment: .leading, spacing: 14) {
            ForEach(presentation.orderedAssets, id: \.id.rawValue) { asset in
                VStack(alignment: .leading, spacing: 7) {
                    compareTile(asset, presentation: presentation)
                    assetCaption(asset, label: surveyLabel(for: asset, presentation: presentation))
                    compareFocusMetricLane(for: asset)
                }
            }
        }
        .padding(16)
    }

    private func surveyColumns(for presentation: CompareSurveyPresentation) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 160), spacing: 12),
            count: presentation.surveyColumnCount
        )
    }

    private func surveyLabel(for asset: Asset, presentation: CompareSurveyPresentation) -> String {
        if asset.id == presentation.primaryAsset?.id {
            return "Primary"
        }
        return CompareSurveyPresentation.decisionSummary(for: asset)
    }

    private func compareTile(_ asset: Asset, presentation: CompareSurveyPresentation) -> some View {
        ZStack(alignment: .topLeading) {
            AssetGridCell(
                asset: asset,
                previewURL: model.loupePreviewURL(for: asset.id),
                previewCacheGeneration: model.previewCacheGeneration(for: asset.id),
                isSelected: model.selectedAssetID == asset.id,
                isBatchSelected: model.isBatchSelected(asset.id)
            )
            .assetActivation(for: asset, model: model, focusCullingSurface: focusCullingSurface) { assetID in
                model.select(assetID)
            }
            compareDecisionBadges(presentation.decisionBadges(for: asset) + presentation.signalBadges(for: asset))
                .padding(8)
        }
    }

    @ViewBuilder
    private func compareDecisionBadges(_ badges: [CompareDecisionBadge]) -> some View {
        if !badges.isEmpty {
            HStack(spacing: 5) {
                ForEach(badges) { badge in
                    Text(badge.text)
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(compareBadgeForeground(for: badge.tone))
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(compareBadgeBackground(for: badge.tone), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    private func compareBadgeForeground(for tone: CompareDecisionBadge.Tone) -> Color {
        switch tone {
        case .primary, .rating, .best:
            return .black
        case .positive, .destructive, .label:
            return .white
        }
    }

    private func compareBadgeBackground(for tone: CompareDecisionBadge.Tone) -> Color {
        switch tone {
        case .primary:
            return .orange
        case .positive:
            return .green.opacity(0.92)
        case .destructive:
            return .red.opacity(0.92)
        case .rating:
            return .yellow
        case .label:
            return .blue.opacity(0.9)
        case .best:
            return .orange
        }
    }

    private func assetCaption(_ asset: Asset, label: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
            Text(asset.originalURL.lastPathComponent)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func compareFocusMetricLane(for asset: Asset) -> some View {
        let metrics = CompareFocusMetricPresentation.metrics(for: model.evaluationSignals(for: asset.id))

        return LazyVGrid(columns: focusMetricColumns, alignment: .leading, spacing: 5) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(metric.value)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(compareFocusMetricAccent(for: metric.tone))
                        .lineLimit(1)
                    Text(metric.detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(compareFocusMetricAccent(for: metric.tone).opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(compareFocusMetricAccent(for: metric.tone).opacity(0.18))
                }
            }
        }
        .liveMockupPlaceholder(.focusCompare)
    }

    private func compareFocusMetricAccent(for tone: CompareFocusMetric.Tone) -> Color {
        switch tone {
        case .positive:
            return .green
        case .caution:
            return .yellow
        case .neutral:
            return .secondary
        case .waiting:
            return .orange
        }
    }

    private func compareActionStrip(
        primaryAsset: Asset,
        presentation: CompareSurveyPresentation
    ) -> some View {
        HStack(spacing: 10) {
            let groupActions = presentation.groupActions(canApplyPrimaryChoice: model.canKeepComparePrimaryAndRejectAlternates)
            let primaryGroupAction = groupActions[0]
            let keepAllAction = groupActions[1]
            let chooseManuallyAction = groupActions[2]

            Label("Teststrip", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Primary · \(presentation.primaryDecisionText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                applyPrimaryFlag(.pick, to: primaryAsset)
            } label: {
                Label("Pick", systemImage: "flag.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                applyPrimaryFlag(.reject, to: primaryAsset)
            } label: {
                Label("Reject", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                openPrimaryInLoupe(primaryAsset)
            } label: {
                Label("Loupe", systemImage: "rectangle.inset.filled")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Divider()
                .frame(height: 22)
            Button(primaryGroupAction.title) {
                applyCompareGroupAction(primaryGroupAction.action)
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!primaryGroupAction.isEnabled)
                .help(primaryGroupAction.help)
                .liveMockupPlaceholder(primaryGroupAction.liveMockupPlaceholder)
            Button(keepAllAction.title) {
                applyCompareKeepAll()
            }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!keepAllAction.isEnabled)
                .help(keepAllAction.help)
                .liveMockupPlaceholder(keepAllAction.liveMockupPlaceholder)
            Button(chooseManuallyAction.title) {
                beginManualCompareCulling()
            }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!chooseManuallyAction.isEnabled)
                .help(chooseManuallyAction.help)
                .liveMockupPlaceholder(chooseManuallyAction.liveMockupPlaceholder)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .liveMockupPlaceholder(.compareSurvey)
    }

    private var comparePreviewTaskID: String {
        ComparePreviewRequestID.make(for: model)
    }

    private func requestComparePreviews() {
        do {
            try model.requestVisibleComparePreviews()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func requestCompareEvaluations() {
        do {
            try model.requestCompareAssetEvaluations()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func applyCompareGroupChoice() {
        do {
            focusCullingSurface()
            try model.keepComparePrimaryAndRejectAlternates()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func applyCompareGroupAction(_ action: CompareSurveyActionPresentation.Action) {
        switch action {
        case .keepPrimaryAndRejectAlternates:
            applyCompareGroupChoice()
        case .keepRecommendedAndRejectAlternates(let assetID):
            applyCompareRecommendedChoice(assetID)
        case .keepAll:
            applyCompareKeepAll()
        case .chooseManually:
            beginManualCompareCulling()
        }
    }

    private func applyCompareRecommendedChoice(_ assetID: AssetID) {
        do {
            focusCullingSurface()
            try model.keepCompareAssetAndRejectAlternates(assetID: assetID)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func applyCompareKeepAll() {
        do {
            focusCullingSurface()
            try model.keepAllCompareAssets()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func beginManualCompareCulling() {
        do {
            focusCullingSurface()
            try model.beginManualCullingFromCompareSet()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func applyPrimaryFlag(_ flag: PickFlag, to asset: Asset) {
        do {
            focusCullingSurface()
            model.select(asset.id)
            try model.setFlagForSelectedAsset(flag)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func openPrimaryInLoupe(_ asset: Asset) {
        focusCullingSurface()
        model.openAssetInLoupe(asset.id)
    }
}

enum ComparePreviewRequestID {
    static func make(for model: AppModel) -> String {
        [
            model.compareAssets().map(\.id.rawValue).joined(separator: "\n"),
            model.selectedAssetID?.rawValue ?? "",
            model.selectedAssetID.map { String(model.previewCacheGeneration(for: $0)) } ?? "0"
        ].joined(separator: "\n")
    }
}

enum AssetActivationFocusPolicy {
    enum Activation {
        case singleClickSelection
        case batchSelection
        case openInLoupe
        case accessibilitySelection
    }

    static func shouldFocusCullingSurface(for activation: Activation) -> Bool {
        switch activation {
        case .singleClickSelection, .batchSelection:
            return false
        case .openInLoupe, .accessibilitySelection:
            return true
        }
    }
}

private extension View {
    func assetActivation(
        for asset: Asset,
        model: AppModel,
        focusCullingSurface: @escaping () -> Void,
        selectAsset: @escaping (AssetID) -> Void
    ) -> some View {
        let doubleClick = TapGesture(count: 2).onEnded {
            if AssetActivationFocusPolicy.shouldFocusCullingSurface(for: .openInLoupe) {
                focusCullingSurface()
            }
            model.openAssetInLoupe(asset.id)
        }
        return Button {
            if NSEvent.modifierFlags.contains(.shift) {
                if AssetActivationFocusPolicy.shouldFocusCullingSurface(for: .batchSelection) {
                    focusCullingSurface()
                }
                model.selectBatchRange(to: asset.id)
            } else if NSEvent.modifierFlags.contains(.command) {
                if AssetActivationFocusPolicy.shouldFocusCullingSurface(for: .batchSelection) {
                    focusCullingSurface()
                }
                model.toggleBatchSelection(asset.id)
            } else {
                if AssetActivationFocusPolicy.shouldFocusCullingSurface(for: .singleClickSelection) {
                    focusCullingSurface()
                }
                selectAsset(asset.id)
            }
        } label: {
            contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .simultaneousGesture(doubleClick)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(asset.originalURL.lastPathComponent)
            .accessibilityValue(assetSelectionAccessibilityValue(for: asset, model: model))
            .accessibilityAction {
                if AssetActivationFocusPolicy.shouldFocusCullingSurface(for: .accessibilitySelection) {
                    focusCullingSurface()
                }
                selectAsset(asset.id)
            }
    }

    private func assetSelectionAccessibilityValue(for asset: Asset, model: AppModel) -> String {
        let primaryState = model.selectedAssetID == asset.id ? "Selected" : "Not selected"
        guard model.isBatchSelected(asset.id) else { return primaryState }
        return "\(primaryState), batch selected"
    }
}

struct SearchWorkspaceRefineRow: Equatable, Identifiable {
    var title: String
    var value: String
    var target: SidebarRowTarget? = nil

    var id: String { "\(title)|\(value)" }
    var isActive: Bool { value == "active" }
}

struct SearchWorkspaceRefineGroup: Equatable, Identifiable {
    var title: String
    var rows: [SearchWorkspaceRefineRow]

    var id: String { title }
}

enum SearchWorkspaceSuggestedActionKind: Equatable {
    case saveDynamicSet
    case saveSnapshotSet
    case startCulling
    case openReviewQueue(ReviewQueue)
}

struct SearchWorkspaceSuggestedAction: Equatable, Identifiable {
    var action: SearchWorkspaceSuggestedActionKind
    var title: String
    var detail: String
    var systemImage: String

    var id: String {
        switch action {
        case .saveDynamicSet:
            return "save-dynamic-set"
        case .saveSnapshotSet:
            return "save-snapshot-set"
        case .startCulling:
            return "start-culling"
        case .openReviewQueue(let queue):
            return "review-\(queue.rawValue)"
        }
    }
}

struct SearchWorkspaceGeneratedRefinement: Equatable, Identifiable {
    var preset: SmartCollectionRulePreset
    var title: String
    var detail: String
    var systemImage: String

    var id: String { preset.id }
}

struct SearchWorkspaceAskInterpretation: Equatable {
    var queryText: String
    var title: String
    var detail: String
    var systemImage: String
}

private extension Array where Element == SearchWorkspaceGeneratedRefinement {
    func containsPreset(_ preset: SmartCollectionRulePreset) -> Bool {
        contains { $0.preset == preset }
    }
}

struct SearchWorkspacePresentation: Equatable {
    var title: String
    var resultCountText: String
    var savedSetCountText: String
    var starredSetCountText: String
    var askInterpretation: SearchWorkspaceAskInterpretation?
    var refineRows: [SearchWorkspaceRefineRow]
    var refineGroups: [SearchWorkspaceRefineGroup]
    var workHistoryRows: [SearchWorkspaceRefineRow]
    var generatedRefinements: [SearchWorkspaceGeneratedRefinement]
    var relatedFilterRows: [SearchWorkspaceRefineRow]
    var suggestedActions: [SearchWorkspaceSuggestedAction]

    init(
        suggestedName: String,
        totalAssetCount: Int,
        savedSetCount: Int,
        starredSetCount: Int,
        activeFilterChips: [String],
        activeFilterRows: [ActiveLibraryFilterRow]? = nil,
        canSaveDynamicSet: Bool = false,
        canSaveSnapshotSet: Bool = false,
        canStartCulling: Bool = false,
        reviewQueueCounts: [ReviewQueue: Int] = [:],
        evaluationKindSummaries: [CatalogEvaluationKindSummary] = [],
        workHistory: [AppWorkActivity] = []
    ) {
        title = suggestedName
        resultCountText = "\(totalAssetCount)"
        savedSetCountText = "\(savedSetCount)"
        starredSetCountText = "\(starredSetCount)"
        let rows = activeFilterRows ?? activeFilterChips.map { ActiveLibraryFilterRow(title: $0) }
        if rows.isEmpty {
            refineRows = [SearchWorkspaceRefineRow(title: "All photographs", value: "current scope", target: .allPhotographs)]
        } else {
            refineRows = rows.map { SearchWorkspaceRefineRow(title: $0.title, value: "active", target: $0.target) }
        }
        askInterpretation = Self.askInterpretation(for: refineRows)
        refineGroups = Self.groupRefineRows(refineRows)
        workHistoryRows = workHistory.map { activity in
            SearchWorkspaceRefineRow(
                title: activity.title,
                value: activity.detail.isEmpty ? activity.status.rawValue : activity.detail,
                target: .workSession(WorkSessionID(rawValue: activity.id))
            )
        }
        generatedRefinements = Self.generatedRefinements(
            reviewQueueCounts: reviewQueueCounts,
            evaluationKindSummaries: evaluationKindSummaries,
            activeRows: refineRows
        )
        relatedFilterRows = Self.relatedFilterRows(
            reviewQueueCounts: reviewQueueCounts,
            activeRows: refineRows
        )
        suggestedActions = Self.suggestedActions(
            suggestedName: suggestedName,
            totalAssetCount: totalAssetCount,
            canSaveDynamicSet: canSaveDynamicSet,
            canSaveSnapshotSet: canSaveSnapshotSet,
            canStartCulling: canStartCulling,
            reviewQueueCounts: reviewQueueCounts
        )
    }

    private static func askInterpretation(for rows: [SearchWorkspaceRefineRow]) -> SearchWorkspaceAskInterpretation? {
        let searchRows = rows.filter { $0.title.hasPrefix("Search:") }
        guard let searchRow = searchRows.first else { return nil }
        let queryText = String(searchRow.title.dropFirst("Search:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryText.isEmpty else { return nil }
        let hasParsedFilters = rows.contains { row in
            !row.title.hasPrefix("Search:") && row.title != "All photographs"
        }
        return SearchWorkspaceAskInterpretation(
            queryText: queryText,
            title: "Plain search fallback",
            detail: hasParsedFilters ? "Plain text remains after parsed filters" : "No structured filters were recognized yet",
            systemImage: "text.magnifyingglass"
        )
    }

    private static func groupRefineRows(_ rows: [SearchWorkspaceRefineRow]) -> [SearchWorkspaceRefineGroup] {
        let order = ["Scope", "Decisions", "Metadata", "Review Queues", "Signals", "Source & XMP"]
        var groupedRows: [String: [SearchWorkspaceRefineRow]] = [:]
        for row in rows {
            groupedRows[groupTitle(for: row), default: []].append(row)
        }
        return order.compactMap { title in
            guard let rows = groupedRows[title], !rows.isEmpty else { return nil }
            return SearchWorkspaceRefineGroup(title: title, rows: rows)
        }
    }

    private static func groupTitle(for row: SearchWorkspaceRefineRow) -> String {
        switch row.target {
        case .assetSet?, .workSession?:
            return "Scope"
        default:
            return groupTitle(for: row.title)
        }
    }

    private static func groupTitle(for rowTitle: String) -> String {
        if rowTitle == "All photographs" {
            return "Scope"
        }
        if rowTitle.hasPrefix("Session:")
            || rowTitle.hasPrefix("Import:") {
            return "Scope"
        }
        if rowTitle == "Pick"
            || rowTitle == "Reject"
            || rowTitle.hasPrefix("Rating")
            || rowTitle.hasSuffix("Label") {
            return "Decisions"
        }
        if rowTitle.hasPrefix("Search:")
            || rowTitle.hasPrefix("Camera:")
            || rowTitle.hasPrefix("Lens:")
            || rowTitle.hasPrefix("Keyword:")
            || rowTitle.hasPrefix("Folder:")
            || rowTitle.hasPrefix("ISO")
            || rowTitle.hasPrefix("From ")
            || rowTitle.hasPrefix("Before ") {
            return "Metadata"
        }
        if rowTitle == "Needs Keywords"
            || rowTitle == "Needs Evaluation"
            || rowTitle == "Likely Issues"
            || rowTitle == "Provider Failures" {
            return "Review Queues"
        }
        if rowTitle.hasPrefix("Signal:") {
            return "Signals"
        }
        if rowTitle.hasPrefix("Source:")
            || rowTitle.hasPrefix("XMP") {
            return "Source & XMP"
        }
        return "Metadata"
    }

    private static func generatedRefinements(
        reviewQueueCounts: [ReviewQueue: Int],
        evaluationKindSummaries: [CatalogEvaluationKindSummary],
        activeRows: [SearchWorkspaceRefineRow]
    ) -> [SearchWorkspaceGeneratedRefinement] {
        let rowLimit = evaluationKindSummaries.isEmpty ? 3 : 5
        let candidates: [(queue: ReviewQueue, preset: SmartCollectionRulePreset)] = [
            (.fiveStars, .ratingFourPlus),
            (.picks, .picked),
            (.needsKeywords, .needsKeywords),
            (.facesFound, .facesFound),
            (.needsEvaluation, .needsEvaluation),
            (.likelyIssues, .likelyIssues),
            (.providerFailures, .providerFailures)
        ]
        var rows: [SearchWorkspaceGeneratedRefinement] = candidates.compactMap { candidate in
            guard let count = reviewQueueCounts[candidate.queue], count > 0 else { return nil }
            guard !isPresetActive(candidate.preset, activeRows: activeRows) else { return nil }
            return generatedRefinement(preset: candidate.preset, count: count)
        }
        .prefix(rowLimit)
        .map { $0 }

        for row in providerSignalGeneratedRefinements(
            evaluationKindSummaries: evaluationKindSummaries,
            activeRows: activeRows
        ) {
            guard rows.count < rowLimit else { break }
            guard !rows.containsPreset(row.preset) else { continue }
            rows.append(row)
        }
        return rows
    }

    private static func providerSignalGeneratedRefinements(
        evaluationKindSummaries: [CatalogEvaluationKindSummary],
        activeRows: [SearchWorkspaceRefineRow]
    ) -> [SearchWorkspaceGeneratedRefinement] {
        let summariesByKind = Dictionary(uniqueKeysWithValues: evaluationKindSummaries.map { ($0.kind, $0) })
        let candidates: [(kind: EvaluationKind, preset: SmartCollectionRulePreset)] = [
            (.focus, .focusSignals),
            (.object, .objectSignals),
            (.ocrText, .ocrFound),
            (.faceCount, .facesFound)
        ]
        return candidates.compactMap { candidate in
            guard let summary = summariesByKind[candidate.kind], summary.assetCount > 0 else { return nil }
            guard !isPresetActive(candidate.preset, activeRows: activeRows) else { return nil }
            return providerSignalGeneratedRefinement(
                preset: candidate.preset,
                kind: candidate.kind,
                count: summary.assetCount
            )
        }
    }

    private static func providerSignalGeneratedRefinement(
        preset: SmartCollectionRulePreset,
        kind: EvaluationKind,
        count: Int
    ) -> SearchWorkspaceGeneratedRefinement {
        switch kind {
        case .focus:
            return SearchWorkspaceGeneratedRefinement(
                preset: preset,
                title: "Find focus-scored photos",
                detail: count == 1 ? "1 photo has focus signals" : "\(count) photos have focus signals",
                systemImage: preset.systemImage
            )
        case .object:
            return SearchWorkspaceGeneratedRefinement(
                preset: preset,
                title: "Find object-labeled photos",
                detail: count == 1 ? "1 photo has object labels" : "\(count) photos have object labels",
                systemImage: preset.systemImage
            )
        case .ocrText:
            return SearchWorkspaceGeneratedRefinement(
                preset: preset,
                title: "Find OCR text",
                detail: count == 1 ? "1 photo has OCR text" : "\(count) photos have OCR text",
                systemImage: preset.systemImage
            )
        case .faceCount:
            return SearchWorkspaceGeneratedRefinement(
                preset: preset,
                title: "Review photos with people signals",
                detail: count == 1 ? "1 photo has people signals" : "\(count) photos have people signals",
                systemImage: preset.systemImage
            )
        default:
            return SearchWorkspaceGeneratedRefinement(
                preset: preset,
                title: preset.title,
                detail: count == 1 ? "1 matching signal" : "\(count) matching signals",
                systemImage: preset.systemImage
            )
        }
    }

    private static func generatedRefinement(
        preset: SmartCollectionRulePreset,
        count: Int
    ) -> SearchWorkspaceGeneratedRefinement {
        switch preset {
        case .ratingFourPlus:
            return SearchWorkspaceGeneratedRefinement(
                preset: preset,
                title: "Narrow to rated keepers",
                detail: count == 1 ? "1 five-star photo available" : "\(count) five-star photos available",
                systemImage: preset.systemImage
            )
        case .picked:
            return SearchWorkspaceGeneratedRefinement(
                preset: preset,
                title: "Narrow to picks",
                detail: count == 1 ? "1 picked photo available" : "\(count) picked photos available",
                systemImage: preset.systemImage
            )
        case .needsKeywords:
            return SearchWorkspaceGeneratedRefinement(
                preset: preset,
                title: "Find missing keywords",
                detail: count == 1 ? "1 photo needs keywords" : "\(count) photos need keywords",
                systemImage: preset.systemImage
            )
        case .facesFound:
            return SearchWorkspaceGeneratedRefinement(
                preset: preset,
                title: "Review photos with faces",
                detail: count == 1 ? "1 photo has face signals" : "\(count) photos have face signals",
                systemImage: preset.systemImage
            )
        case .needsEvaluation:
            return SearchWorkspaceGeneratedRefinement(
                preset: preset,
                title: "Find unevaluated photos",
                detail: count == 1 ? "1 photo needs evaluation" : "\(count) photos need evaluation",
                systemImage: preset.systemImage
            )
        case .likelyIssues:
            return SearchWorkspaceGeneratedRefinement(
                preset: preset,
                title: "Review likely issues",
                detail: count == 1 ? "1 photo has likely issues" : "\(count) photos have likely issues",
                systemImage: preset.systemImage
            )
        case .providerFailures:
            return SearchWorkspaceGeneratedRefinement(
                preset: preset,
                title: "Check provider failures",
                detail: count == 1 ? "1 provider failure" : "\(count) provider failures",
                systemImage: preset.systemImage
            )
        default:
            return SearchWorkspaceGeneratedRefinement(
                preset: preset,
                title: preset.title,
                detail: count == 1 ? "1 matching photo" : "\(count) matching photos",
                systemImage: preset.systemImage
            )
        }
    }

    private static func isPresetActive(
        _ preset: SmartCollectionRulePreset,
        activeRows: [SearchWorkspaceRefineRow]
    ) -> Bool {
        activeRows.contains { row in
            switch preset {
            case .ratingFourPlus:
                return row.target == .reviewQueue(.fiveStars) || row.title.hasPrefix("Rating")
            case .picked:
                return row.target == .reviewQueue(.picks) || row.title == "Pick"
            case .rejected:
                return row.target == .reviewQueue(.rejects) || row.title == "Reject"
            case .needsKeywords:
                return row.target == .reviewQueue(.needsKeywords) || row.title == "Needs Keywords"
            case .needsEvaluation:
                return row.target == .reviewQueue(.needsEvaluation) || row.title == "Needs Evaluation"
            case .onlineSources:
                return row.target == .sourceAvailability(.online) || row.title == "Source: Online"
            case .offlineSources:
                return row.target == .sourceAvailability(.offline) || row.title == "Source: Offline"
            case .facesFound:
                return row.target == .reviewQueue(.facesFound)
                    || row.target == .evaluationKind(.faceCount)
                    || row.title == "Faces Found"
                    || row.title == "Signal: Face Count"
            case .ocrFound:
                return row.target == .reviewQueue(.ocrFound)
                    || row.target == .evaluationKind(.ocrText)
                    || row.title == "OCR Found"
                    || row.title == "Signal: OCR Text"
            case .focusSignals:
                return row.target == .evaluationKind(.focus) || row.title == "Signal: Focus"
            case .objectSignals:
                return row.target == .evaluationKind(.object) || row.title == "Signal: Object"
            case .likelyIssues:
                return row.target == .reviewQueue(.likelyIssues) || row.title == "Likely Issues"
            case .providerFailures:
                return row.target == .reviewQueue(.providerFailures) || row.title == "Provider Failures"
            case .xmpPending:
                return row.target == .metadataSyncPending || row.title == "XMP Pending"
            case .xmpConflicts:
                return row.target == .metadataSyncConflicts || row.title == "XMP Conflicts"
            }
        }
    }

    private static func relatedFilterRows(
        reviewQueueCounts: [ReviewQueue: Int],
        activeRows: [SearchWorkspaceRefineRow]
    ) -> [SearchWorkspaceRefineRow] {
        reviewQueueFilterOrder.compactMap { queue in
            guard let count = reviewQueueCounts[queue], count > 0 else { return nil }
            let presentation = queue.presentation
            let isActive = activeRows.contains { row in
                row.target == .reviewQueue(queue) || row.title == presentation.title
            }
            guard !isActive else { return nil }
            return SearchWorkspaceRefineRow(
                title: presentation.title,
                value: count == 1 ? "1 photo" : "\(count) photos",
                target: .reviewQueue(queue)
            )
        }
    }

    private static func suggestedActions(
        suggestedName: String,
        totalAssetCount: Int,
        canSaveDynamicSet: Bool,
        canSaveSnapshotSet: Bool,
        canStartCulling: Bool,
        reviewQueueCounts: [ReviewQueue: Int]
    ) -> [SearchWorkspaceSuggestedAction] {
        var actions: [SearchWorkspaceSuggestedAction] = []
        if canSaveDynamicSet {
            actions.append(SearchWorkspaceSuggestedAction(
                action: .saveDynamicSet,
                title: "Save dynamic set",
                detail: "\(suggestedName) updates as the catalog changes",
                systemImage: "bookmark"
            ))
        }
        if canSaveSnapshotSet {
            actions.append(SearchWorkspaceSuggestedAction(
                action: .saveSnapshotSet,
                title: totalAssetCount == 1 ? "Freeze 1 result" : "Freeze \(totalAssetCount) results",
                detail: "Capture this exact result set",
                systemImage: "camera.viewfinder"
            ))
        }
        if canStartCulling, totalAssetCount > 0 {
            actions.append(SearchWorkspaceSuggestedAction(
                action: .startCulling,
                title: "Cull current scope",
                detail: totalAssetCount == 1
                    ? "Start a culling session for 1 result"
                    : "Start a culling session for \(totalAssetCount) results",
                systemImage: "checkmark.seal"
            ))
        }
        for queue in reviewQueueActionOrder {
            guard let count = reviewQueueCounts[queue], count > 0 else { continue }
            actions.append(SearchWorkspaceSuggestedAction(
                action: .openReviewQueue(queue),
                title: "Review \(queue.presentation.title)",
                detail: count == 1 ? "1 photo" : "\(count) photos",
                systemImage: queue.presentation.systemImage
            ))
        }
        return actions
    }

    private static let reviewQueueActionOrder: [ReviewQueue] = [
        .needsKeywords,
        .needsEvaluation,
        .facesFound,
        .ocrFound,
        .likelyIssues,
        .providerFailures
    ]

    private static let reviewQueueFilterOrder: [ReviewQueue] = [
        .picks,
        .rejects,
        .fiveStars,
        .needsKeywords,
        .needsEvaluation,
        .facesFound,
        .ocrFound,
        .likelyIssues,
        .providerFailures
    ]
}

private struct SearchWorkspaceView: View {
    var model: AppModel
    var assetGrid: AnyView
    var saveDynamicSet: () -> Void
    var saveSnapshotSet: () -> Void
    var startCulling: () -> Void

    private var presentation: SearchWorkspacePresentation {
        SearchWorkspacePresentation(
            suggestedName: model.suggestedSavedSearchName,
            totalAssetCount: model.totalAssetCount,
            savedSetCount: model.savedAssetSets.count,
            starredSetCount: model.starredAssetSets.count,
            activeFilterChips: model.activeLibraryFilterChips,
            activeFilterRows: model.activeLibraryFilterRows,
            canSaveDynamicSet: model.canSaveCurrentLibraryQuery,
            canSaveSnapshotSet: model.canSaveCurrentAssetScopeSnapshot,
            canStartCulling: !model.isImporting && model.canBeginCullingSession,
            reviewQueueCounts: model.reviewQueueCounts,
            evaluationKindSummaries: model.catalogEvaluationKindSummaries,
            workHistory: model.workHistorySearchResults
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchHeader
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    refineRail
                    Divider()
                    if model.assets.isEmpty {
                        emptySearchResults
                            .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        assetGrid
                    }
                }
            }
        }
        .background(Color.black.opacity(0.18))
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Search", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(presentation.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                searchMetric(title: "Results", value: presentation.resultCountText)
                searchMetric(title: "Sets", value: presentation.savedSetCountText)
                searchMetric(title: "Starred", value: presentation.starredSetCountText)
            }
            if presentation.refineRows.count == 1,
               presentation.refineRows.first?.title == "All photographs" {
                Text("All photographs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(presentation.refineRows) { row in
                            refineChip(row)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.bar)
        .liveMockupPlaceholder(.searchRefine)
    }

    private var refineRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teststrip Reads")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let askInterpretation = presentation.askInterpretation {
                askInterpretationRow(askInterpretation)
            }
            if !presentation.workHistoryRows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Work History")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(presentation.workHistoryRows) { row in
                        refineRailRow(row)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(presentation.refineGroups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(group.rows) { row in
                            refineRailRow(row)
                        }
                    }
                }
            }
            if !presentation.generatedRefinements.isEmpty {
                Divider()
                    .padding(.vertical, 2)
                Text("Generated Refinements")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(presentation.generatedRefinements) { refinement in
                        generatedRefinementRow(refinement)
                    }
                }
            }
            if !presentation.relatedFilterRows.isEmpty {
                Divider()
                    .padding(.vertical, 2)
                Text("Related Filters")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(presentation.relatedFilterRows) { row in
                        refineRailRow(row)
                    }
                }
            }
            if !presentation.suggestedActions.isEmpty {
                Divider()
                    .padding(.vertical, 2)
                Text("Suggested Actions")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(presentation.suggestedActions) { action in
                        suggestedActionRow(action)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 214, alignment: .topLeading)
        .liveMockupPlaceholder(.searchRefine)
    }

    private func askInterpretationRow(_ interpretation: SearchWorkspaceAskInterpretation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: interpretation.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(interpretation.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(interpretation.queryText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(interpretation.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(interpretation.title)
        .accessibilityValue("\(interpretation.queryText), \(interpretation.detail)")
    }

    @ViewBuilder
    private func refineChip(_ row: SearchWorkspaceRefineRow) -> some View {
        let chip = HStack(spacing: 5) {
            Text(row.title)
                .lineLimit(1)
            if row.isActive {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        if row.isActive {
            Button {
                removeActiveRefineRow(row)
            } label: {
                chip
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove filter \(row.title)")
            .help("Remove \(row.title) filter")
        } else if row.target != nil {
            Button {
                selectRefineRow(row)
            } label: {
                chip
            }
            .buttonStyle(.plain)
            .help("Open \(row.title)")
        } else {
            chip
        }
    }

    @ViewBuilder
    private func refineRailRow(_ row: SearchWorkspaceRefineRow) -> some View {
        let content = HStack(spacing: 8) {
            Image(systemName: row.isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(row.isActive ? .orange : .secondary)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(row.value)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        if row.isActive {
            Button {
                removeActiveRefineRow(row)
            } label: {
                HStack(spacing: 8) {
                    content
                    Spacer(minLength: 0)
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove filter \(row.title)")
            .help("Remove \(row.title) filter")
        } else if row.target != nil {
            Button {
                selectRefineRow(row)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .help("Open \(row.title)")
        } else {
            content
        }
    }

    private func generatedRefinementRow(_ refinement: SearchWorkspaceGeneratedRefinement) -> some View {
        Button {
            applyGeneratedRefinement(refinement)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: refinement.systemImage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(refinement.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(refinement.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(refinement.detail)
    }

    private func suggestedActionRow(_ suggestedAction: SearchWorkspaceSuggestedAction) -> some View {
        Button {
            performSuggestedAction(suggestedAction.action)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: suggestedAction.systemImage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestedAction.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(suggestedAction.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(suggestedAction.detail)
    }

    private func applyGeneratedRefinement(_ refinement: SearchWorkspaceGeneratedRefinement) {
        do {
            try model.applySmartCollectionRulePreset(refinement.preset)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func performSuggestedAction(_ action: SearchWorkspaceSuggestedActionKind) {
        switch action {
        case .saveDynamicSet:
            saveDynamicSet()
        case .saveSnapshotSet:
            saveSnapshotSet()
        case .startCulling:
            startCulling()
        case .openReviewQueue(let queue):
            do {
                try model.selectSidebarTarget(.reviewQueue(queue))
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func removeActiveRefineRow(_ row: SearchWorkspaceRefineRow) {
        do {
            try model.removeActiveLibraryFilter(ActiveLibraryFilterRow(title: row.title, target: row.target))
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func selectRefineRow(_ row: SearchWorkspaceRefineRow) {
        guard let target = row.target else { return }
        do {
            try model.selectSidebarTarget(target)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func searchMetric(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var emptySearchResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No matches")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TimelineWorkspaceView: View {
    var model: AppModel
    var columns: [GridItem]
    var focusCullingSurface: () -> Void
    var selectAsset: (AssetID) -> Void

    private var presentation: TimelinePresentation {
        TimelinePresentation(
            timelineDays: model.catalogTimelineDays,
            loadedAssets: model.assets,
            totalAssetCount: model.totalAssetCount
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    timelineHeader
                    if presentation.months.isEmpty {
                        emptyTimeline
                            .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        ForEach(presentation.months) { month in
                            monthSection(month)
                                .id(TimelineContentScrollPolicy.monthTargetID(for: month.id))
                        }
                    }
                }
                .padding(12)
            }
            .background(Color.black.opacity(0.18))
            .liveMockupPlaceholder(.timelineLibrary)
            .onAppear {
                scrollTimelineTarget(TimelineContentScrollPolicy.focusedTargetID(for: presentation.scrubber), with: proxy)
            }
            .onChange(of: TimelineContentScrollPolicy.focusedTargetID(for: presentation.scrubber)) { _, targetID in
                scrollTimelineTarget(targetID, with: proxy)
            }
        }
    }

    private var timelineHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Timeline", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(presentation.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                timelineMetric(title: "Months", value: "\(presentation.months.count)")
                timelineMetric(title: "Loaded", value: "\(model.assets.count)")
            }

            if !presentation.yearRibbon.years.isEmpty {
                timelineYearRibbon(presentation.yearRibbon)
            }

            if !presentation.scrubber.months.isEmpty {
                timelineMonthDayScrubber(presentation.scrubber)
            }
        }
        .padding(14)
        .background(.bar, in: RoundedRectangle(cornerRadius: 8))
    }

    private func timelineYearRibbon(_ ribbon: TimelineYearRibbonPresentation) -> some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Catalog Timeline")
                    .font(.caption2.monospaced().weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(ribbon.rangeText)
                    .font(.title3.weight(.semibold))
                Text(ribbon.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)

            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(ribbon.years) { year in
                        Button {
                            selectTimelineYear(year.year)
                        } label: {
                            timelineYearBar(year, focusText: ribbon.focusText)
                        }
                        .buttonStyle(.plain)
                        .help("Show photos from \(year.year)")
                    }
                }
                .frame(height: 86)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                HStack(spacing: 2) {
                    ForEach(ribbon.years) { year in
                        Text(year.tickText.isEmpty ? " " : year.tickText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func timelineMonthDayScrubber(_ scrubber: TimelineScrubberPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let focusText = scrubber.focusText {
                Text(focusText)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.orange)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(scrubber.months) { month in
                            Button {
                                selectTimelineMonth(year: month.year, month: month.month)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(month.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(month.countText)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 118, height: 42, alignment: .leading)
                                .padding(.horizontal, 8)
                                .background(
                                    month.isFocused ? Color.orange.opacity(0.18) : Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(month.isFocused ? Color.orange.opacity(0.75) : Color.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Show photos from \(month.title)")
                            .id(month.id)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .onAppear {
                    scrollTimelineTarget(scrubber.focusedMonthID, with: proxy)
                }
                .onChange(of: scrubber.focusedMonthID) { _, focusedMonthID in
                    scrollTimelineTarget(focusedMonthID, with: proxy)
                }
            }

            if !scrubber.days.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(scrubber.days) { day in
                                Button {
                                    selectTimelineDay(day.timelineDay)
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(day.title)
                                            .font(.caption2.weight(.semibold))
                                            .lineLimit(1)
                                        Text(day.countText)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 92, height: 26)
                                    .background(
                                        day.isFocused ? Color.orange.opacity(0.16) : Color.white.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 5)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(day.isFocused ? Color.orange.opacity(0.65) : Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("Show photos from \(day.title)")
                                .id(day.id)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .onAppear {
                        scrollTimelineTarget(scrubber.focusedDayID, with: proxy)
                    }
                    .onChange(of: scrubber.focusedDayID) { _, focusedDayID in
                        scrollTimelineTarget(focusedDayID, with: proxy)
                    }
                }
            }
        }
    }

    private func scrollTimelineTarget(_ targetID: String?, with proxy: ScrollViewProxy) {
        guard let targetID else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            proxy.scrollTo(targetID, anchor: .center)
        }
    }

    private func timelineYearBar(_ year: TimelineYearPresentation, focusText: String?) -> some View {
        let barHeight = max(5, CGFloat(year.heightRatio) * 58)
        return ZStack(alignment: .bottom) {
            Color.clear
            RoundedRectangle(cornerRadius: 3)
                .fill(year.isFocused ? Color.orange : Color.white.opacity(0.22))
                .frame(width: 12, height: barHeight)
                .shadow(
                    color: year.isFocused ? Color.orange.opacity(0.55) : .clear,
                    radius: year.isFocused ? 7 : 0
                )
            if year.isFocused, let focusText {
                Text(focusText)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 4))
                    .fixedSize()
                    .offset(y: -barHeight - 7)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(year.year), \(year.assetCount) photographs")
    }

    private func monthSection(_ month: TimelineMonthPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(month.title)
                    .font(.title3.weight(.semibold))
                Text(month.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            ForEach(month.days) { day in
                daySection(day)
                    .id(TimelineContentScrollPolicy.dayTargetID(for: day.id))
            }
        }
    }

    private func daySection(_ day: TimelineDayPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(day.title)
                    .font(.subheadline.weight(.semibold))
                Text(day.countText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let timelineDay = day.timelineDay {
                    Button("Show") {
                        selectTimelineDay(timelineDay)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .help("Show photos from \(day.title)")
                }
            }

            if !day.assets.isEmpty {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(day.assets, id: \.id.rawValue) { asset in
                        AssetGridCell(
                            asset: asset,
                            previewURL: model.gridPreviewURL(for: asset.id),
                            previewCacheGeneration: model.previewCacheGeneration(for: asset.id),
                            previewStatus: model.gridPreviewStatus(for: asset.id),
                            isSelected: model.selectedAssetID == asset.id,
                            isBatchSelected: model.isBatchSelected(asset.id)
                        )
                        .assetActivation(for: asset, model: model, focusCullingSurface: focusCullingSurface) { assetID in
                            selectAsset(assetID)
                        }
                        .id("timeline-\(asset.id.rawValue)")
                        .task(id: asset.id.rawValue) {
                            do {
                                try model.requestVisibleGridPreview(assetID: asset.id)
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
    }

    private func timelineMetric(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func selectTimelineDay(_ day: CatalogTimelineDay) {
        do {
            try model.selectTimelineDay(day)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func selectTimelineMonth(year: Int, month: Int) {
        do {
            try model.selectTimelineMonth(year: year, month: month)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func selectTimelineYear(_ year: Int) {
        do {
            try model.selectTimelineYear(year)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private var emptyTimeline: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No loaded timeline")
                .font(.headline)
            Text("Import photos or change filters to populate the timeline.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

enum AssetGridPreviewPolicy {
    static let thumbnailScaling: CachedPreviewImage.Scaling = .fit
}

struct AssetGridPreviewStatusPresentation: Equatable {
    var title: String
    var detail: String
    var systemImage: String

    static func presentation(
        previewURL: URL?,
        queueStates: [PreviewGenerationQueueState],
        activePreviewLevels: [PreviewLevel]
    ) -> AssetGridPreviewStatusPresentation? {
        guard previewURL == nil else { return nil }
        let thumbnailLevels: Set<PreviewLevel> = [.grid, .micro]
        if activePreviewLevels.contains(where: { thumbnailLevels.contains($0) }) {
            return AssetGridPreviewStatusPresentation(
                title: "Building preview",
                detail: "Cached preview is being generated",
                systemImage: "clock.arrow.circlepath"
            )
        }

        let thumbnailStates = queueStates.filter { thumbnailLevels.contains($0.item.level) }
        guard !thumbnailStates.isEmpty else { return nil }
        if thumbnailStates.contains(where: { state in
            state.attemptCount > 0 || state.lastErrorMessage?.isEmpty == false
        }) {
            return AssetGridPreviewStatusPresentation(
                title: "Preview issue",
                detail: "Cached preview needs attention",
                systemImage: "exclamationmark.triangle.fill"
            )
        }
        return AssetGridPreviewStatusPresentation(
            title: "Preview queued",
            detail: "Cached preview is queued",
            systemImage: "clock"
        )
    }
}

struct AssetGridMetadataBadgePresentation: Equatable {
    enum FlagTone: Equatable {
        case pick
        case reject

        var systemName: String {
            switch self {
            case .pick: "flag.fill"
            case .reject: "xmark"
            }
        }
    }

    var flagTone: FlagTone?
    var ratingText: String?
    var colorLabel: ColorLabel?
    var keywordCountText: String?
    var keywordAccessibilityLabel: String?

    var flagSystemName: String? {
        flagTone?.systemName
    }

    static func presentation(for asset: Asset) -> AssetGridMetadataBadgePresentation {
        let keywordCount = asset.metadata.keywords.count
        return AssetGridMetadataBadgePresentation(
            flagTone: flagTone(for: asset.metadata.flag),
            ratingText: asset.metadata.rating > 0 ? String(repeating: "★", count: asset.metadata.rating) : nil,
            colorLabel: asset.metadata.colorLabel,
            keywordCountText: keywordCount > 0 ? "\(keywordCount)" : nil,
            keywordAccessibilityLabel: keywordCount > 0 ? "\(keywordCount) \(keywordCount == 1 ? "keyword" : "keywords")" : nil
        )
    }

    private static func flagTone(for flag: PickFlag?) -> FlagTone? {
        switch flag {
        case .pick: .pick
        case .reject: .reject
        case nil: nil
        }
    }
}

enum LibraryGridSelectionScrollPolicy {
    static func shouldScrollSelectedAssetIntoView(
        selectedAssetID: String?,
        suppressedSelectionScrollAssetID: String?
    ) -> Bool {
        guard let selectedAssetID else { return false }
        return selectedAssetID != suppressedSelectionScrollAssetID
    }
}

enum ImportCardEntryRoute: Equatable {
    case userGrantedPanel
    case typedPathSheet
}

enum LibraryGridChromePolicy {
    static let primaryCardImportRoute: ImportCardEntryRoute = .userGrantedPanel

    static func primaryCardImportRoute(environment: [String: String]) -> ImportCardEntryRoute {
        switch environment["TESTSTRIP_CARD_IMPORT_ROUTE"] {
        case "typed-path":
            return .typedPathSheet
        default:
            return .userGrantedPanel
        }
    }

    static func shouldShowImportProgressBanner(isImporting: Bool, visibleAssetCount _: Int) -> Bool {
        isImporting
    }

    static func shouldShowImportCompletionSummary(
        isImporting: Bool,
        summaryID: String?,
        dismissedSummaryID: String?
    ) -> Bool {
        guard !isImporting, let summaryID else { return false }
        return summaryID != dismissedSummaryID
    }

    static func shouldShowPendingMetadataSyncRetryAction(isPendingFilterActive: Bool) -> Bool {
        isPendingFilterActive
    }

    static func isPendingMetadataSyncRetryActionDisabled(isImporting: Bool, canRetry: Bool) -> Bool {
        isImporting || !canRetry
    }
}

struct LibrarySortOptionPresentation: Equatable {
    var option: LibrarySortOption
    var title: String
    var subtitle: String
    var isSelected: Bool

    static func options(selected: LibrarySortOption) -> [LibrarySortOptionPresentation] {
        LibrarySortOption.allCases.map { option in
            LibrarySortOptionPresentation(
                option: option,
                title: title(for: option),
                subtitle: subtitle(for: option),
                isSelected: option == selected
            )
        }
    }

    private static func title(for option: LibrarySortOption) -> String {
        switch option {
        case .importOrder:
            return "Import Order"
        case .captureTimeNewestFirst, .captureTimeOldestFirst:
            return "Capture Time"
        case .filename:
            return "Filename"
        }
    }

    private static func subtitle(for option: LibrarySortOption) -> String {
        switch option {
        case .importOrder:
            return "Oldest import first"
        case .captureTimeNewestFirst:
            return "Newest first"
        case .captureTimeOldestFirst:
            return "Oldest first"
        case .filename:
            return "A to Z"
        }
    }
}

enum MetadataSyncFilterOption: String, Equatable {
    case any
    case pending
    case conflicts

    init(pending: Bool, conflict: Bool) {
        if conflict {
            self = .conflicts
        } else if pending {
            self = .pending
        } else {
            self = .any
        }
    }

    var pendingFilter: Bool {
        self == .pending
    }

    var conflictFilter: Bool {
        self == .conflicts
    }
}

struct SmartCollectionBuilderPresentation: Equatable {
    var proposedName: String
    var ruleChips: [String]
    var activeFilterRows: [ActiveLibraryFilterRow]? = nil
    var matchCount: Int
    var typedRuleText: String = ""
    var reviewQueueCounts: [ReviewQueue: Int] = [:]
    var evaluationKindSummaries: [CatalogEvaluationKindSummary] = []

    var suggestedTemplateRows: [SmartCollectionSuggestedTemplateRow] {
        Self.suggestedTemplateRows(
            reviewQueueCounts: reviewQueueCounts,
            evaluationKindSummaries: evaluationKindSummaries,
            activeRuleChips: ruleChips
        )
    }

    var ruleCountText: String {
        "\(resolvedActiveFilterRows.count) \(resolvedActiveFilterRows.count == 1 ? "rule" : "rules")"
    }

    var ruleRows: [SmartCollectionRuleRow] {
        resolvedActiveFilterRows.map(SmartCollectionRuleRow.init)
    }

    var addRuleRows: [SmartCollectionAddRuleRow] {
        SmartCollectionRulePreset.allCases.map(SmartCollectionAddRuleRow.init)
    }

    var matchCountText: String {
        "\(matchCount) \(matchCount == 1 ? "match" : "matches")"
    }

    var canCreate: Bool {
        !proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !resolvedActiveFilterRows.isEmpty
    }

    var canApplyTypedRule: Bool {
        let intent = LibrarySearchIntent.parse(typedRuleText)
        return intent.residualText != nil || !intent.predicates.isEmpty
    }

    func previewCountText(visibleCount: Int) -> String {
        guard matchCount > 0 else { return "no live preview yet" }
        return "showing \(min(max(visibleCount, 0), matchCount))"
    }

    private static func suggestedTemplateRows(
        reviewQueueCounts: [ReviewQueue: Int],
        evaluationKindSummaries: [CatalogEvaluationKindSummary],
        activeRuleChips: [String]
    ) -> [SmartCollectionSuggestedTemplateRow] {
        var rows: [SmartCollectionSuggestedTemplateRow] = []
        let rowLimit = evaluationKindSummaries.isEmpty ? 3 : 5
        let ratedCount = reviewQueueCounts[.fiveStars] ?? 0
        let pickedCount = reviewQueueCounts[.picks] ?? 0
        if ratedCount > 0,
           pickedCount > 0,
           !isPresetActive(.ratingFourPlus, activeRuleChips: activeRuleChips),
           !isPresetActive(.picked, activeRuleChips: activeRuleChips) {
            rows.append(SmartCollectionSuggestedTemplateRow(
                title: "Picked keepers",
                detail: "\(pickedCount) \(pickedCount == 1 ? "pick" : "picks"), \(ratedCount) rated",
                systemImage: "star.circle",
                presets: [.ratingFourPlus, .picked]
            ))
        }

        for row in providerSignalTemplateRows(
            evaluationKindSummaries: evaluationKindSummaries,
            activeRuleChips: activeRuleChips
        ) {
            guard rows.count < rowLimit else { break }
            rows.append(row)
        }

        let candidates: [(queue: ReviewQueue, preset: SmartCollectionRulePreset, title: String, systemImage: String)] = [
            (.facesFound, .facesFound, "Face review", "person.2.circle"),
            (.needsKeywords, .needsKeywords, "Needs keywords", "tag.circle"),
            (.needsEvaluation, .needsEvaluation, "Needs evaluation", "wand.and.stars.inverse"),
            (.likelyIssues, .likelyIssues, "Likely issues", "exclamationmark.triangle"),
            (.providerFailures, .providerFailures, "Provider failures", "bolt.horizontal.circle")
        ]
        for candidate in candidates {
            guard rows.count < rowLimit else { break }
            guard let count = reviewQueueCounts[candidate.queue], count > 0 else { continue }
            guard !isPresetActive(candidate.preset, activeRuleChips: activeRuleChips) else { continue }
            guard !rows.containsPreset(candidate.preset) else { continue }
            rows.append(SmartCollectionSuggestedTemplateRow(
                title: candidate.title,
                detail: suggestionDetail(for: candidate.queue, count: count),
                systemImage: candidate.systemImage,
                presets: [candidate.preset]
            ))
        }
        return rows
    }

    private static func providerSignalTemplateRows(
        evaluationKindSummaries: [CatalogEvaluationKindSummary],
        activeRuleChips: [String]
    ) -> [SmartCollectionSuggestedTemplateRow] {
        let summariesByKind = Dictionary(uniqueKeysWithValues: evaluationKindSummaries.map { ($0.kind, $0) })
        let candidates: [(kind: EvaluationKind, preset: SmartCollectionRulePreset, title: String, systemImage: String)] = [
            (.focus, .focusSignals, "Focus signals", "scope"),
            (.object, .objectSignals, "Object labels", "shippingbox.circle"),
            (.ocrText, .ocrFound, "Text found", "text.viewfinder"),
            (.faceCount, .facesFound, "People found", "person.2.circle")
        ]
        return candidates.compactMap { candidate in
            guard let summary = summariesByKind[candidate.kind], summary.assetCount > 0 else { return nil }
            guard !isPresetActive(candidate.preset, activeRuleChips: activeRuleChips) else { return nil }
            return SmartCollectionSuggestedTemplateRow(
                title: candidate.title,
                detail: providerSignalSuggestionDetail(kind: candidate.kind, count: summary.assetCount),
                systemImage: candidate.systemImage,
                presets: [candidate.preset]
            )
        }
    }

    private static func providerSignalSuggestionDetail(kind: EvaluationKind, count: Int) -> String {
        switch kind {
        case .focus:
            return count == 1 ? "1 photo has focus signals" : "\(count) photos have focus signals"
        case .object:
            return count == 1 ? "1 photo has object labels" : "\(count) photos have object labels"
        case .ocrText:
            return count == 1 ? "1 photo has OCR text" : "\(count) photos have OCR text"
        case .faceCount:
            return count == 1 ? "1 photo has people signals" : "\(count) photos have people signals"
        default:
            return count == 1 ? "1 photo has provider signals" : "\(count) photos have provider signals"
        }
    }

    private static func suggestionDetail(for queue: ReviewQueue, count: Int) -> String {
        switch queue {
        case .facesFound:
            return count == 1 ? "1 photo has faces" : "\(count) photos have faces"
        case .needsKeywords:
            return count == 1 ? "1 photo needs keywords" : "\(count) photos need keywords"
        case .needsEvaluation:
            return count == 1 ? "1 photo needs evaluation" : "\(count) photos need evaluation"
        case .likelyIssues:
            return count == 1 ? "1 photo has likely issues" : "\(count) photos have likely issues"
        case .providerFailures:
            return count == 1 ? "1 provider failure" : "\(count) provider failures"
        default:
            return count == 1 ? "1 matching photo" : "\(count) matching photos"
        }
    }

    private static func isPresetActive(
        _ preset: SmartCollectionRulePreset,
        activeRuleChips: [String]
    ) -> Bool {
        activeRuleChips.contains { chip in
            switch preset {
            case .ratingFourPlus:
                return chip.hasPrefix("Rating")
            case .picked:
                return chip == "Pick"
            case .rejected:
                return chip == "Reject"
            case .needsKeywords:
                return chip == "Needs Keywords"
            case .needsEvaluation:
                return chip == "Needs Evaluation"
            case .onlineSources:
                return chip == "Source: Online"
            case .offlineSources:
                return chip == "Source: Offline"
            case .facesFound:
                return chip == "Faces Found" || chip == "Signal: Face Count"
            case .ocrFound:
                return chip == "OCR Found" || chip == "Signal: OCR Text"
            case .focusSignals:
                return chip == "Signal: Focus"
            case .objectSignals:
                return chip == "Signal: Object"
            case .likelyIssues:
                return chip == "Likely Issues"
            case .providerFailures:
                return chip == "Provider Failures"
            case .xmpPending:
                return chip == "XMP Pending"
            case .xmpConflicts:
                return chip == "XMP Conflicts"
            }
        }
    }

    private var resolvedActiveFilterRows: [ActiveLibraryFilterRow] {
        activeFilterRows ?? ruleChips.map { ActiveLibraryFilterRow(title: $0) }
    }
}

struct SmartCollectionSuggestedTemplateRow: Equatable, Identifiable {
    var title: String
    var detail: String
    var systemImage: String
    var presets: [SmartCollectionRulePreset]

    var id: String { title }
}

private extension Array where Element == SmartCollectionSuggestedTemplateRow {
    func containsPreset(_ preset: SmartCollectionRulePreset) -> Bool {
        contains { $0.presets.contains(preset) }
    }
}

struct SmartCollectionAddRuleRow: Equatable, Identifiable {
    var preset: SmartCollectionRulePreset
    var title: String
    var systemImage: String

    var id: String { preset.id }

    init(preset: SmartCollectionRulePreset) {
        self.preset = preset
        self.title = preset.title
        self.systemImage = preset.systemImage
    }
}

struct SmartCollectionRuleRow: Equatable, Identifiable {
    var id: String {
        "\(field)\n\(operation)\n\(value)"
    }

    var field: String
    var operation: String
    var value: String
    var target: SidebarRowTarget?
    private var title: String

    var activeFilterRow: ActiveLibraryFilterRow {
        ActiveLibraryFilterRow(title: title, target: target)
    }

    init(field: String, operation: String, value: String, target: SidebarRowTarget? = nil) {
        self.field = field
        self.operation = operation
        self.value = value
        self.target = target
        if operation == "matches", field == "Filter" {
            self.title = value
        } else if operation == "matches" {
            self.title = "\(field): \(value)"
        } else if operation == "is at least" {
            self.title = "\(field) >= \(value)"
        } else {
            self.title = "\(field) \(operation) \(value)"
        }
    }

    init(chip: String) {
        self.init(activeFilterRow: ActiveLibraryFilterRow(title: chip))
    }

    init(activeFilterRow: ActiveLibraryFilterRow) {
        let chip = activeFilterRow.title
        let trimmed = chip.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: ":") {
            field = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            operation = "matches"
            value = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let range = trimmed.range(of: ">=") {
            field = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            operation = "is at least"
            value = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let range = trimmed.range(of: "≥") {
            field = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            operation = "is at least"
            value = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            field = "Filter"
            operation = "matches"
            value = trimmed
        }

        if field.isEmpty {
            field = "Filter"
        }
        if value.isEmpty {
            value = trimmed.isEmpty ? "Any" : trimmed
        }
        target = activeFilterRow.target
        title = activeFilterRow.title
    }
}

struct CullingAssistPresentation: Equatable {
    enum Tone: Equatable {
        case waiting
        case positive
        case caution
        case neutral
    }

    var title: String
    var detail: String
    var tone: Tone
    var verdictText: String?
    var verdictTone: Tone

    private static let keepReadThreshold = 0.7
    private static let tossReadThreshold = 0.45

    static func presentation(
        for signals: [EvaluationSignal],
        stackGuidance: CullingStackActionPresentation? = nil
    ) -> CullingAssistPresentation {
        let verdict = verdict(for: signals)
        if let stackGuidance,
           stackGuidance.isEnabled,
           let stackTitle = stackGuidanceTitle(for: stackGuidance) {
            return CullingAssistPresentation(
                title: stackTitle,
                detail: stackGuidanceDetail(for: stackGuidance, selectedSignals: signals),
                tone: .positive,
                verdictText: verdict?.text,
                verdictTone: verdict?.tone ?? .waiting
            )
        }
        guard let signal = signals.sorted(by: signalSort).first else {
            return CullingAssistPresentation(
                title: "No read yet",
                detail: "Evaluate frame to show culling signals",
                tone: .waiting,
                verdictText: verdict?.text,
                verdictTone: verdict?.tone ?? .waiting
            )
        }
        return CullingAssistPresentation(
            title: title(for: signal),
            detail: detail(primarySignal: signal, signals: signals),
            tone: tone(for: signal),
            verdictText: verdict?.text,
            verdictTone: verdict?.tone ?? .waiting
        )
    }

    // Synthesized display-only read over the same components the stack
    // ranking uses; at least two scored quality kinds are required because
    // one signal is not a verdict.
    private static func verdict(for signals: [EvaluationSignal]) -> (text: String, tone: Tone)? {
        guard let read = CullingStackRecommendation.normalizedQualityRead(for: signals),
              read.kindCount >= 2 else {
            return nil
        }
        let percentText = EvaluationSignalPresentation.percentage(read.score)
        if read.score >= keepReadThreshold {
            return ("Keep read \(percentText)", .positive)
        }
        if read.score <= tossReadThreshold {
            return ("Toss read \(percentText)", .caution)
        }
        return ("Mixed read \(percentText)", .neutral)
    }

    private static func stackGuidanceTitle(for action: CullingStackActionPresentation) -> String? {
        switch action.action {
        case .keepRecommended, .keepTopRanked:
            return action.assistTitle ?? action.title
        case .keepSelectedAndRejectAlternates, .keepAll:
            return nil
        }
    }

    private static func stackGuidanceDetail(
        for action: CullingStackActionPresentation,
        selectedSignals: [EvaluationSignal]
    ) -> String {
        var parts = ["Stack recommendation - \(action.help)"]
        if let selectedSignal = selectedSignals.sorted(by: signalSort).first {
            parts.append("Selected: \(detail(primarySignal: selectedSignal, signals: selectedSignals))")
        }
        return parts.joined(separator: " · ")
    }

    private static func detail(primarySignal: EvaluationSignal, signals: [EvaluationSignal]) -> String {
        var parts = [
            "\(EvaluationSignalPresentation.displayName(for: primarySignal.kind)) - \(primarySignal.provenance.provider) - \(EvaluationSignalPresentation.percentage(primarySignal.confidence)) confidence"
        ]
        parts.append(contentsOf: rationaleTexts(for: signals, excluding: primarySignal))
        return parts.joined(separator: " · ")
    }

    private static func rationaleTexts(
        for signals: [EvaluationSignal],
        excluding primarySignal: EvaluationSignal,
        limit: Int = 3
    ) -> [String] {
        var seenKinds = [primarySignal.kind]
        var rationales: [String] = []
        for signal in signals.sorted(by: signalSort) where signal != primarySignal {
            guard rationales.count < limit,
                  !seenKinds.contains(signal.kind),
                  let rationale = rationaleText(for: signal) else {
                continue
            }
            rationales.append(rationale)
            seenKinds.append(signal.kind)
        }
        return rationales
    }

    private static func expressionPhrase(for signal: EvaluationSignal) -> String? {
        guard case .score(let score) = signal.value else { return nil }
        switch signal.kind {
        case .eyesOpen:
            if score >= 1.0 { return "Eyes open" }
            if score <= 0.0 { return "Eyes shut" }
            return "Some eyes shut"
        case .eyeSharpness:
            return score >= 0.7 ? "Eyes sharp" : "Eyes soft"
        case .smile:
            if score >= 1.0 { return "Smiling" }
            if score > 0.0 { return "Some smiling" }
            return nil
        default:
            return nil
        }
    }

    private static func rationaleText(for signal: EvaluationSignal) -> String? {
        switch signal.kind {
        case .eyesOpen, .eyeSharpness, .smile:
            return expressionPhrase(for: signal)
        case .focus, .motionBlur, .exposure, .aesthetics, .framing, .faceQuality, .faceCount, .novelty, .colorPalette, .visualSimilarity:
            return title(for: signal)
        case .object, .ocrText:
            return nil
        }
    }

    private static func signalSort(_ lhs: EvaluationSignal, _ rhs: EvaluationSignal) -> Bool {
        let lhsRank = rank(for: lhs.kind)
        let rhsRank = rank(for: rhs.kind)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        return lhs.confidence > rhs.confidence
    }

    private static func rank(for kind: EvaluationKind) -> Int {
        switch kind {
        case .aesthetics:
            return 0
        case .framing:
            return 1
        case .motionBlur:
            return 2
        case .focus:
            return 3
        case .faceQuality:
            return 4
        case .eyesOpen:
            return 5
        case .eyeSharpness:
            return 6
        case .smile:
            return 7
        case .faceCount:
            return 8
        case .exposure:
            return 9
        case .object:
            return 10
        case .ocrText:
            return 11
        case .novelty:
            return 12
        case .colorPalette:
            return 13
        case .visualSimilarity:
            return 14
        }
    }

    private static func title(for signal: EvaluationSignal) -> String {
        if let phrase = expressionPhrase(for: signal) {
            return phrase
        }
        switch signal.value {
        case .score(let score):
            return "\(EvaluationSignalPresentation.displayName(for: signal.kind)) \(EvaluationSignalPresentation.percentage(score))"
        case .label(let label):
            return EvaluationSignalPresentation.capitalized(label, fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .labels(let labels):
            return EvaluationSignalPresentation.capitalized(labels.joined(separator: ", "), fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .text(let text):
            return EvaluationSignalPresentation.capitalized(text, fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .count(let count):
            return "\(EvaluationSignalPresentation.displayName(for: signal.kind)) \(count)"
        case .vector:
            return "\(EvaluationSignalPresentation.displayName(for: signal.kind)) sampled"
        }
    }

    private static func tone(for signal: EvaluationSignal) -> Tone {
        switch (signal.kind, signal.value) {
        case (.motionBlur, .score(let score)):
            return score >= 0.5 ? .caution : .positive
        case (.focus, .score(let score)), (.faceQuality, .score(let score)):
            return score >= 0.7 ? .positive : .caution
        case (.aesthetics, .label(let label)), (.framing, .label(let label)):
            return cautionLabels.contains(label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ? .caution : .positive
        case (.faceCount, .count(let count)):
            return count > 0 ? .positive : .neutral
        case (.eyesOpen, .score(let score)):
            return score >= 1.0 ? .positive : .caution
        case (.eyeSharpness, .score(let score)):
            return score >= 0.7 ? .positive : .caution
        case (.smile, .score(let score)):
            return score > 0.0 ? .positive : .neutral
        default:
            return .neutral
        }
    }

    private static let cautionLabels: Set<String> = [
        "blur",
        "blurry",
        "reject",
        "soft",
        "eyes closed",
        "closed eyes"
    ]

}

struct ImportCompletionPresentation: Equatable {
    var title: String
    var detail: String
    var metricRows: [ImportCompletionMetricRow]
    var actionRows: [ImportCompletionActionPresentation]

    var enabledActions: [ImportCompletionActionPresentation] {
        actionRows.filter(\.isEnabled)
    }

    var placeholderActions: [ImportCompletionActionPresentation] {
        actionRows.filter { !$0.isEnabled && $0.placeholder != nil }
    }

    static func presentation(
        for summary: ImportCompletionSummary,
        batchKeywordSuggestions: [BatchKeywordSuggestion] = [],
        faceReviewAssetCount: Int = 0,
        flaggedReviewAssetCount: Int = 0,
        canEvaluateImport: Bool = false
    ) -> ImportCompletionPresentation {
        let hasImportedSet = summary.importedPhotoCount > 0
        let existingOnlyImport = isExistingOnlyImport(summary)
        var metricRows = [
            importedSetMetric(for: summary),
            previewMetric(for: summary),
            cullScopeMetric(for: summary)
        ]
        if let issueMetric = issueMetric(for: summary) {
            metricRows.append(issueMetric)
        }
        var actionRows: [ImportCompletionActionPresentation] = []
        if hasImportedSet {
            actionRows.append(ImportCompletionActionPresentation(
                kind: .startCulling,
                title: "Start culling",
                detail: existingOnlyImport ? "Use the matched set" : "Use the imported set",
                systemImage: "checkmark.seal.fill",
                isEnabled: true,
                isPrimary: true,
                placeholder: nil
            ))
            actionRows.append(ImportCompletionActionPresentation(
                kind: .reviewImportedFrames,
                title: existingOnlyImport ? "Review matched frames" : "Review imported frames",
                detail: existingOnlyImport ? "Manual Compare over already-cataloged photos" : "Manual Compare over this import",
                systemImage: "rectangle.grid.2x2",
                isEnabled: true,
                isPrimary: false,
                placeholder: nil
            ))
            actionRows.append(ImportCompletionActionPresentation(
                kind: .openInLibrary,
                title: existingOnlyImport ? "Open matched set" : "Open imported set",
                detail: existingOnlyImport ? "Browse already-cataloged photos" : "Browse this import",
                systemImage: "rectangle.stack",
                isEnabled: true,
                isPrimary: false,
                placeholder: nil
            ))
            actionRows.append(ImportCompletionActionPresentation(
                kind: .evaluateImport,
                title: "Evaluate import",
                detail: canEvaluateImport ? "Run local reads on this import" : "Waiting for cached previews",
                systemImage: "sparkles",
                isEnabled: canEvaluateImport,
                isPrimary: false,
                placeholder: nil
            ))
        }
        if let issueAction = importIssueAction(for: summary) {
            actionRows.append(issueAction)
        }
        if let flaggedAction = flaggedReviewAction(flaggedReviewAssetCount: flaggedReviewAssetCount) {
            actionRows.append(flaggedAction)
        }
        if hasImportedSet {
            actionRows.append(ImportCompletionActionPresentation(
                kind: .stackGrouping,
                title: "Cull stacks",
                detail: stackCullActionDetail(for: summary),
                systemImage: "square.stack.3d.up",
                isEnabled: summary.stackCount > 0,
                isPrimary: false,
                placeholder: nil
            ))
        }
        if let faceAction = faceReviewAction(faceReviewAssetCount: faceReviewAssetCount) {
            actionRows.append(faceAction)
        }
        if let keywordAction = keywordSuggestionAction(batchKeywordSuggestions: batchKeywordSuggestions) {
            actionRows.append(keywordAction)
        }
        return ImportCompletionPresentation(
            title: title(for: summary),
            detail: summary.detail,
            metricRows: metricRows,
            actionRows: actionRows
        )
    }

    private static func title(for summary: ImportCompletionSummary) -> String {
        if summary.importedPhotoCount == 0 {
            return "No photos imported"
        }
        if isExistingOnlyImport(summary) {
            return "No new photos imported"
        }
        return "\(photoCountText(summary.newPhotoCount)) imported"
    }

    private static func isExistingOnlyImport(_ summary: ImportCompletionSummary) -> Bool {
        summary.newPhotoCount == 0 && summary.existingPhotoCount > 0
    }

    private static func importedSetMetric(for summary: ImportCompletionSummary) -> ImportCompletionMetricRow {
        if summary.importedPhotoCount == 0 {
            return ImportCompletionMetricRow(
                id: "imported-set",
                value: photoCountText(0),
                label: "Import result",
                detail: "Nothing was added",
                systemImage: "exclamationmark.triangle",
                tone: .yellow
            )
        }
        if summary.newPhotoCount == 0, summary.existingPhotoCount > 0 {
            return ImportCompletionMetricRow(
                id: "imported-set",
                value: "\(photoCountText(summary.existingPhotoCount)) already in catalog",
                label: "Matched set",
                detail: "No new files added",
                systemImage: "rectangle.stack",
                tone: .yellow
            )
        }

        let detail: String
        if summary.existingPhotoCount > 0 {
            detail = "\(photoCountText(summary.existingPhotoCount)) already in catalog"
        } else {
            detail = "Ready to browse and cull"
        }
        return ImportCompletionMetricRow(
            id: "imported-set",
            value: photoCountText(summary.newPhotoCount),
            label: "Imported set",
            detail: detail,
            systemImage: "rectangle.stack.fill",
            tone: .green
        )
    }

    private static func photoCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "photo" : "photos")"
    }

    private static func stackCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "stack" : "stacks")"
    }

    private static func flaggedReviewAction(flaggedReviewAssetCount: Int) -> ImportCompletionActionPresentation? {
        guard flaggedReviewAssetCount > 0 else { return nil }
        return ImportCompletionActionPresentation(
            kind: .reviewFlaggedFrames,
            title: "Review \(flaggedReviewAssetCount) flagged",
            detail: "Review likely issues from this import",
            systemImage: "exclamationmark.triangle",
            isEnabled: true,
            isPrimary: false,
            placeholder: nil
        )
    }

    private static func issueMetric(for summary: ImportCompletionSummary) -> ImportCompletionMetricRow? {
        guard !summary.issues.isEmpty else { return nil }
        let issueCount = summary.issues.count
        let skippedCount = summary.issues.filter { $0.kind == .skippedSourceFile }.count
        let detail = summary.issues.first.map(issueDetail) ?? "\(issueCount) import issues"
        return ImportCompletionMetricRow(
            id: "import-issues",
            value: issueCount == 1 ? "1 issue" : "\(issueCount) issues",
            label: skippedCount == issueCount ? "Skipped files" : "Import issues",
            detail: detail,
            systemImage: "exclamationmark.triangle",
            tone: .yellow
        )
    }

    private static func issueDetail(_ issue: WorkSessionIssue) -> String {
        let message = issue.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sourceURL = issue.sourceURL else { return message }
        let fileName = sourceURL.lastPathComponent
        guard !fileName.isEmpty else { return message }
        guard !message.isEmpty else { return fileName }
        return "\(fileName): \(message)"
    }

    private static func importIssueAction(for summary: ImportCompletionSummary) -> ImportCompletionActionPresentation? {
        guard !summary.issues.isEmpty else { return nil }
        let skippedCount = summary.issues.filter { $0.kind == .skippedSourceFile }.count
        let title: String
        if skippedCount == summary.issues.count {
            title = skippedCount == 1 ? "Review 1 skipped file" : "Review \(skippedCount) skipped files"
        } else {
            title = summary.issues.count == 1 ? "Review 1 import issue" : "Review \(summary.issues.count) import issues"
        }
        return ImportCompletionActionPresentation(
            kind: .reviewImportIssues,
            title: title,
            detail: summary.issues.first.map(issueDetail) ?? "Review import issues",
            systemImage: "exclamationmark.triangle",
            isEnabled: true,
            isPrimary: false,
            placeholder: nil
        )
    }

    private static func cullScopeMetric(for summary: ImportCompletionSummary) -> ImportCompletionMetricRow {
        guard summary.importedPhotoCount > 0 else {
            return ImportCompletionMetricRow(
                id: "cull-scope",
                value: "Unavailable",
                label: "Cull scope",
                detail: "No imported set",
                systemImage: "slash.circle",
                tone: .yellow
            )
        }
        guard summary.stackCount > 0 else {
            return ImportCompletionMetricRow(
                id: "cull-scope",
                value: "Ready",
                label: "Cull scope",
                detail: isExistingOnlyImport(summary) ? "Uses the matched set" : "Uses the imported set",
                systemImage: "checkmark.seal.fill",
                tone: .orange
            )
        }
        return ImportCompletionMetricRow(
            id: "cull-scope",
            value: stackCountText(summary.stackCount),
            label: "Cull scope",
            detail: "\(photoCountText(summary.stackedPhotoCount)) in time-adjacent stacks",
            systemImage: "square.stack.3d.up.fill",
            tone: .orange
        )
    }

    private static func stackCullActionDetail(for summary: ImportCompletionSummary) -> String {
        guard summary.stackCount > 0 else {
            return "No time-adjacent stacks"
        }
        return "\(stackCountText(summary.stackCount)) · \(photoCountText(summary.stackedPhotoCount))"
    }

    private static func keywordSuggestionAction(
        batchKeywordSuggestions: [BatchKeywordSuggestion]
    ) -> ImportCompletionActionPresentation? {
        guard let suggestion = batchKeywordSuggestions.first else { return nil }

        let suggestionCount = batchKeywordSuggestions.count
        return ImportCompletionActionPresentation(
            kind: .keywordSuggestions,
            title: suggestionCount == 1
                ? "Review 1 keyword suggestion"
                : "Review \(suggestionCount) keyword suggestions",
            detail: "Top: \(suggestion.keyword) - \(suggestion.assetCountText) at \(suggestion.confidenceText)",
            systemImage: "tag.fill",
            isEnabled: true,
            isPrimary: false,
            placeholder: nil
        )
    }

    private static func faceReviewAction(faceReviewAssetCount: Int) -> ImportCompletionActionPresentation? {
        guard faceReviewAssetCount > 0 else { return nil }
        return ImportCompletionActionPresentation(
            kind: .faceNaming,
            title: faceReviewAssetCount == 1 ? "Review 1 face photo" : "Review \(faceReviewAssetCount) face photos",
            detail: "Open Faces Found review",
            systemImage: "person.2.fill",
            isEnabled: true,
            isPrimary: false,
            placeholder: nil
        )
    }

    private static func previewMetric(for summary: ImportCompletionSummary) -> ImportCompletionMetricRow {
        guard summary.importedPhotoCount > 0 else {
            return ImportCompletionMetricRow(
                id: "previews",
                value: "Not needed",
                label: "Previews",
                detail: summary.previewStatusText,
                systemImage: "photo.stack",
                tone: .blue
            )
        }
        if summary.previewFailureCount > 0 {
            return ImportCompletionMetricRow(
                id: "previews",
                value: "\(summary.previewFailureCount) \(summary.previewFailureCount == 1 ? "issue" : "issues")",
                label: "Previews",
                detail: summary.failureText ?? summary.previewStatusText,
                systemImage: "exclamationmark.triangle.fill",
                tone: .yellow
            )
        }

        let status = summary.previewStatusText.lowercased()
        let value: String
        if status.contains("queued") {
            value = "Queued"
        } else if status.contains("generating") || status.contains("building") {
            value = "Building"
        } else if status.contains("paused") {
            value = "Paused"
        } else {
            value = "Ready"
        }
        return ImportCompletionMetricRow(
            id: "previews",
            value: value,
            label: "Previews",
            detail: summary.previewStatusText,
            systemImage: "photo.stack",
            tone: value == "Ready" ? .blue : .yellow
        )
    }
}

struct ImportCompletionMetricRow: Equatable, Identifiable {
    enum Tone: Equatable {
        case green
        case blue
        case yellow
        case orange
    }

    var id: String
    var value: String
    var label: String
    var detail: String
    var systemImage: String
    var tone: Tone

    var tint: Color {
        switch tone {
        case .green:
            return .green
        case .blue:
            return .blue
        case .yellow:
            return .yellow
        case .orange:
            return .orange
        }
    }
}

struct ImportCompletionActionPresentation: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case startCulling
        case reviewImportedFrames
        case openInLibrary
        case evaluateImport
        case reviewImportIssues
        case reviewFlaggedFrames
        case stackGrouping
        case faceNaming
        case keywordSuggestions
    }

    var kind: Kind
    var title: String
    var detail: String
    var systemImage: String
    var isEnabled: Bool
    var isPrimary: Bool
    var placeholder: LiveMockupPlaceholder?

    var id: String {
        kind.rawValue
    }
}

struct ImportIssueReview: Equatable, Identifiable {
    var summaryID: String
    var issues: [WorkSessionIssue]

    var id: String { summaryID }

    var title: String {
        issues.count == 1 ? "1 Import Issue" : "\(issues.count) Import Issues"
    }
}

struct ImportProgressPresentation: Equatable {
    var title: String
    var phaseText: String
    var detail: String
    var reassuranceText: String
    var countText: String?
    var cancelHelp: String

    static func presentation(for activity: AppWorkActivity?) -> ImportProgressPresentation {
        guard let activity else {
            return ImportProgressPresentation(
                title: "Import photos",
                phaseText: "Starting",
                detail: "Preparing import",
                reassuranceText: "Preparing safe catalog import.",
                countText: nil,
                cancelHelp: "Cancel import"
            )
        }
        return ImportProgressPresentation(
            title: activity.title,
            phaseText: phaseText(for: activity),
            detail: detail(for: activity),
            reassuranceText: reassuranceText(for: activity),
            countText: countText(for: activity),
            cancelHelp: cancelHelp(for: activity)
        )
    }

    private static func detail(for activity: AppWorkActivity) -> String {
        let detail = activity.detail.isEmpty ? "Preparing import" : activity.detail
        guard activity.status == .queued else { return detail }
        return "\(detail) - queued for the background worker"
    }

    private static func cancelHelp(for activity: AppWorkActivity) -> String {
        let prefix = "Importing from "
        if activity.detail.hasPrefix(prefix) {
            return "Cancel import from \(activity.detail.dropFirst(prefix.count))"
        }
        return "Cancel import"
    }

    private static func reassuranceText(for activity: AppWorkActivity) -> String {
        switch activity.status {
        case .queued:
            return "Queued safely; originals will not be modified."
        case .paused:
            return "Import is paused; catalog state is preserved."
        case .running:
            break
        case .completed:
            return "Import finished."
        case .failed:
            return "Import stopped before completing."
        case .cancelled:
            return "Import was cancelled."
        }
        let lowercasedDetail = activity.detail.lowercased()
        if lowercasedDetail.contains("preview") || lowercasedDetail.contains("generated") {
            return "Catalog is updated; preview building may continue after import."
        }
        return "Import is underway; thumbnails appear as previews become ready."
    }

    private static func phaseText(for activity: AppWorkActivity) -> String {
        switch activity.status {
        case .queued:
            return "Waiting"
        case .paused:
            return "Paused"
        case .running:
            break
        case .completed, .failed, .cancelled:
            break
        }
        let lowercasedDetail = activity.detail.lowercased()
        if lowercasedDetail.contains("preview") || lowercasedDetail.contains("generated") {
            return "Building previews"
        }
        if lowercasedDetail.contains("catalog") || activity.totalUnitCount != nil {
            return "Cataloging"
        }
        if lowercasedDetail.contains("copy") {
            return "Copying"
        }
        return "Scanning source"
    }

    private static func countText(for activity: AppWorkActivity) -> String? {
        guard let total = activity.totalUnitCount else {
            guard [.running, .paused].contains(activity.status) else { return nil }
            return activity.completedUnitCount > 0 ? "\(activity.completedUnitCount) found" : "Counting photos"
        }
        return "\(activity.completedUnitCount) of \(total)"
    }
}

struct AssetSourceStatusPresentation: Equatable {
    var title: String
    var detail: String
    var systemImage: String

    static func presentation(for availability: SourceAvailability) -> AssetSourceStatusPresentation? {
        switch availability {
        case .online:
            return nil
        case .offline:
            return AssetSourceStatusPresentation(
                title: "Offline",
                detail: "Original offline; cached previews only",
                systemImage: "externaldrive.badge.xmark"
            )
        case .missing:
            return AssetSourceStatusPresentation(
                title: "Missing",
                detail: "Original missing; cached previews only",
                systemImage: "photo.badge.exclamationmark"
            )
        case .moved:
            return AssetSourceStatusPresentation(
                title: "Moved",
                detail: "Original moved; cached previews only",
                systemImage: "arrowshape.turn.up.right"
            )
        case .stale:
            return AssetSourceStatusPresentation(
                title: "Stale",
                detail: "Original changed on disk",
                systemImage: "clock.badge.exclamationmark"
            )
        }
    }

    var tint: Color {
        switch title {
        case "Stale":
            return .yellow
        default:
            return .orange
        }
    }
}

enum AssetGridCellLayout {
    static let fallbackAspectRatio = 3.0 / 2.0

    static func aspectRatio(for asset: Asset) -> Double {
        guard let technicalMetadata = asset.technicalMetadata,
              technicalMetadata.pixelWidth > 0,
              technicalMetadata.pixelHeight > 0 else {
            return fallbackAspectRatio
        }
        return Double(technicalMetadata.pixelWidth) / Double(technicalMetadata.pixelHeight)
    }
}

enum AssetGridSelectionChrome {
    enum Border: Equatable {
        case none
        case primary
        case batch
    }

    static func border(isSelected: Bool, isBatchSelected: Bool) -> Border {
        if isSelected { return .primary }
        if isBatchSelected { return .batch }
        return .none
    }
}

private struct AssetGridCell: View {
    var asset: Asset
    var previewURL: URL?
    var previewCacheGeneration: Int
    var previewStatus: AssetGridPreviewStatusPresentation?
    var isSelected: Bool
    var isBatchSelected = false

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
                if previewURL == nil, let previewStatus {
                    previewStatusBadge(previewStatus)
                }
                metadataOverlay
                    .padding(6)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay {
                selectionBorder
            }
            .overlay(alignment: .topTrailing) {
                if let status = AssetSourceStatusPresentation.presentation(for: asset.availability) {
                    sourceStatusBadge(status)
                        .padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                if isBatchSelected {
                    batchSelectionBadge
                        .padding(6)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.gray.opacity(0.35))
            )
        }
        .aspectRatio(AssetGridCellLayout.aspectRatio(for: asset), contentMode: .fit)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var selectionBorder: some View {
        switch AssetGridSelectionChrome.border(isSelected: isSelected, isBatchSelected: isBatchSelected) {
        case .none:
            EmptyView()
        case .primary:
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.orange, lineWidth: 3)
                .shadow(color: Color.orange.opacity(0.45), radius: 3)
        case .batch:
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.orange.opacity(0.72), lineWidth: 2)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        CachedPreviewImage(
            previewURL: previewURL,
            scaling: AssetGridPreviewPolicy.thumbnailScaling,
            cacheGeneration: previewCacheGeneration
        )
    }

    private func previewStatusBadge(_ status: AssetGridPreviewStatusPresentation) -> some View {
        VStack(spacing: 5) {
            Image(systemName: status.systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(status.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel(status.detail)
    }

    private var batchSelectionBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.black.opacity(0.82), Color.orange)
            .accessibilityLabel("Batch selected")
    }

    private var metadataOverlay: some View {
        let presentation = AssetGridMetadataBadgePresentation.presentation(for: asset)
        return HStack(spacing: 5) {
            if let flagTone = presentation.flagTone {
                flagBadge(systemName: flagTone.systemName, color: color(for: flagTone))
            }
            if let ratingText = presentation.ratingText {
                Text(ratingText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            if let colorLabel = presentation.colorLabel {
                Circle()
                    .fill(color(for: colorLabel))
                    .frame(width: 8, height: 8)
            }
            if let keywordCountText = presentation.keywordCountText,
               let keywordAccessibilityLabel = presentation.keywordAccessibilityLabel {
                keywordBadge(countText: keywordCountText, accessibilityLabel: keywordAccessibilityLabel)
            }
            Spacer(minLength: 0)
        }
    }

    private func keywordBadge(countText: String, accessibilityLabel: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "tag.fill")
                .font(.system(size: 8, weight: .bold))
            Text(countText)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.black.opacity(0.75))
        .padding(.horizontal, 4)
        .frame(height: 15)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 3))
        .accessibilityLabel(accessibilityLabel)
    }

    private func sourceStatusBadge(_ status: AssetSourceStatusPresentation) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .font(.system(size: 9, weight: .bold))
            Text(status.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.black.opacity(0.82))
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(status.tint, in: RoundedRectangle(cornerRadius: 4))
        .accessibilityLabel(status.detail)
    }

    private func flagBadge(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.black.opacity(0.75))
            .frame(width: 15, height: 15)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func color(for tone: AssetGridMetadataBadgePresentation.FlagTone) -> Color {
        switch tone {
        case .pick: .green
        case .reject: .red
        }
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
