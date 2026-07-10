import AppKit
import CoreLocation
import MapKit
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
    @State private var isShowingSearchTips = false
    @State private var batchMetadataDraft = BatchMetadataDraft()
    @State private var batchMetadataScope: BatchScopeMode = .visible
    @State private var isAllCatalogBatchMetadataConfirmed = false
    @State private var isReviewingExport = false
    @State private var exportScope: BatchScopeMode = .visible
    @State private var exportPresets: [ExportPreset] = ExportPresetStore.loadPresets()
    @State private var selectedExportPresetName = ExportPresetStore.lastUsedPresetOrDefault().name
    @State private var exportSettings = ExportPresetStore.lastUsedPresetOrDefault().settings
    @State private var isAllCatalogExportConfirmed = false
    @State private var isNamingNewExportPreset = false
    @State private var newExportPresetName = ""
    @State private var exportSizeEstimateText: String?
    @State private var rejectRelocationPreflight: RejectRelocationPreflight?
    @State private var isRejectRelocationConfirmed = false
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
    @State private var gridFocusRequest = 0
    @State private var gridColumnCount = 1
    @State private var suppressedSelectionScrollAssetID: String?
    @AppStorage("LibraryGridView.thumbnailWidth") private var storedThumbnailWidth = LibraryGridLayout.defaultThumbnailWidth

    private var gridLayout: LibraryGridLayout {
        LibraryGridLayout(thumbnailWidth: storedThumbnailWidth)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: gridLayout.gridItemMinimumWidth), spacing: gridLayout.gridSpacing)]
    }

    // Horizontal padding applied around the asset grid (`.padding(12)` on each side).
    private let gridContentInset: CGFloat = 24

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
            } else if model.selectedView == .timeline {
                TimelineWorkspaceView(
                    model: model,
                    columns: columns,
                    focusCullingSurface: focusCullingSurface
                ) { assetID in
                    selectAssetFromGrid(assetID)
                }
            } else if model.selectedView == .map {
                PlacesWorkspaceView(model: model)
            } else if model.assets.isEmpty {
                ScrollView {
                    emptyLibraryView
                }
            } else if model.selectedView == .loupe || model.selectedView == .libraryLoupe {
                LoupeView(model: model)
            } else if model.selectedView == .compare {
                CompareView(model: model, focusCullingSurface: focusCullingSurface)
            } else if model.selectedView == .abCompare {
                ABCompareView(model: model)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        assetGrid
                            .background {
                                GeometryReader { geometry in
                                    Color.clear
                                        .onAppear { updateGridColumnCount(width: geometry.size.width) }
                                        .onChange(of: geometry.size.width) { _, width in
                                            updateGridColumnCount(width: width)
                                        }
                                }
                            }
                    }
                    .onChange(of: model.selectedAssetID?.rawValue) { _, selectedAssetID in
                        handleSelectedAssetChange(selectedAssetID, with: proxy)
                    }
                    .onAppear { gridFocusRequest += 1 }
                }
            }
        }
        .navigationTitle(model.catalogDisplayName)
        .onChange(of: model.batchMetadataRequestToken) { _, _ in
            openBatchMetadataSheet()
        }
        .toolbar {
            libraryToolbarContent
        }
        .safeAreaInset(edge: .top) {
            topInsetContent
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let summary = model.rejectRelocationSummary {
                    RejectRelocationBannerView(
                        summary: summary,
                        moveBack: { moveBackRejectRelocation(sessionID: summary.sessionID) },
                        dismiss: { model.dismissRejectRelocationSummary() }
                    )
                }
                if WorkspaceChromePolicy.showsFooter(model.selectedWorkspace) {
                    footer
                }
            }
        }
        .sheet(item: $rejectRelocationPreflight) { preflight in
            rejectRelocationSheet(preflight)
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
            CullingKeyCaptureView(
                focusRequest: cullingFocusRequest,
                // The Library loupe has no pick/reject/rating chrome, so its
                // keyboard monitor is the plain-nav GridKeyCaptureView below
                // instead — leaving this one active here would let culling
                // shortcuts write metadata behind hidden chrome.
                isActive: model.selectedView != .grid && model.selectedView != .libraryLoupe,
                onShortcut: handleCullingShortcut
            )
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            GridKeyCaptureView(
                mode: model.selectedView,
                focusRequest: gridFocusRequest,
                onCommand: handleGridCommand
            )
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            workspaceSwitcher
        }

        ToolbarItem {
            Menu {
                Button {
                    showImportFolderPanel()
                } label: {
                    Label("Folder…", systemImage: "square.and.arrow.down")
                }
                .disabled(isImporting)

                Button {
                    showPrimaryCardImportRoute()
                } label: {
                    Label("From Card…", systemImage: "externaldrive.badge.plus")
                }
                .disabled(isImporting)
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .disabled(isImporting)
            .help("Import photos from a folder or a memory card")
        }

        if LibraryGridChromePolicy.shouldExposeImportPathControl(
            environment: ProcessInfo.processInfo.environment
        ) {
            ToolbarItem {
                Button {
                    showImportPathSheet()
                } label: {
                    Label("Import Path", systemImage: "folder.badge.plus")
                }
                .disabled(isImporting)
                .help("Import a folder by typed path (dev/automation)")
            }
        }

        ToolbarItem {
            Button {
                findBestShots()
            } label: {
                Label("Find Best Shots", systemImage: "wand.and.stars")
            }
            .disabled(isImporting || !model.canFindBestShots)
            .accessibilityLabel("Find Best Shots")
            .help("Evaluate the photos in view and show you your best shots, ranked. Nothing is saved until you keep them.")
        }

        ToolbarItem {
            Button {
                showStartCullingPopover()
            } label: {
                Label("Cull", systemImage: "checkmark.seal")
            }
            .disabled(isImporting || !model.canBeginCullingSession)
            .help("Review photos one at a time to rate, pick, and reject by hand with the keyboard. (Find Best Shots ranks them for you.)")
            .popover(isPresented: $isStartingCullingSession) {
                cullingSessionPopover
            }
        }

        ToolbarItem {
            Button {
                exportScope = model.selectedBatchAssetCount > 0 ? .selected : .visible
                isAllCatalogExportConfirmed = false
                isReviewingExport = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(isImporting || model.assets.isEmpty || model.isExporting)
            .help("Export photo copies to a folder")
            .popover(isPresented: $isReviewingExport) {
                exportPopover
            }
        }

        ToolbarItem {
            Menu {
                Button {
                    beginRejectRelocation()
                } label: {
                    Label("Move Rejects…", systemImage: "tray.and.arrow.down")
                }
                .disabled(isImporting || model.assets.isEmpty || model.isRelocatingRejects)

                Button {
                    showSourceReconnectSheet()
                } label: {
                    Label("Reconnect Sources…", systemImage: "externaldrive")
                }
                .disabled(isImporting || !model.canReconnectSourceRoot)

                Button {
                    openBatchMetadataSheet()
                } label: {
                    Label("Batch Metadata…", systemImage: "tag")
                }
                .disabled(isImporting || model.assets.isEmpty)

                Divider()

                Toggle(isOn: Binding(
                    get: { model.autopilotEnabled },
                    set: { model.autopilotEnabled = $0 }
                )) {
                    Label("Auto-cull after import", systemImage: "wand.and.stars")
                }

                Divider()

                Button {
                    evaluateSelectedAsset()
                } label: {
                    Label("Evaluate Photo", systemImage: "sparkles")
                }
                .disabled(isImporting || !model.canRequestSelectedAssetEvaluation)

                Button {
                    evaluateVisibleAssets()
                } label: {
                    Label("Evaluate Visible", systemImage: "sparkles")
                }
                .disabled(isImporting || !model.canRequestVisibleAssetEvaluations)

                Button {
                    evaluateCurrentScopeAssets()
                } label: {
                    Label("Evaluate Scope", systemImage: "sparkles.rectangle.stack")
                }
                .disabled(isImporting || !model.canRequestCurrentScopeAssetEvaluations)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .popover(isPresented: $isReviewingBatchMetadata) {
                batchMetadataPopover
            }
            .help("More actions")
        }

        ToolbarItem {
            activityToolbarButton
        }
    }

    private var activityToolbarButton: some View {
        let presentation = model.activityCenterPresentation
        return Button {
            model.isActivityCenterPresented.toggle()
        } label: {
            activityToolbarIcon(presentation)
        }
        .help(activityToolbarHelp(presentation))
        .popover(isPresented: Binding(
            get: { model.isActivityCenterPresented },
            set: { model.isActivityCenterPresented = $0 }
        )) {
            ScrollView {
                ActivityCenterView(model: model)
                    .padding(14)
            }
            .frame(width: 340)
        }
    }

    @ViewBuilder
    private func activityToolbarIcon(_ presentation: ActivityCenterPresentation) -> some View {
        ZStack(alignment: .topTrailing) {
            if presentation.isWorking {
                ProgressView(value: presentation.importProgress?.fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "bell")
            }
            if case .problems(let count) = presentation.badge {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(Color.red))
                    .offset(x: 8, y: -8)
            }
        }
    }

    private func activityToolbarHelp(_ presentation: ActivityCenterPresentation) -> String {
        if case .problems(let count) = presentation.badge {
            return count == 1 ? "Activity - 1 problem" : "Activity - \(count) problems"
        }
        return presentation.isWorking ? "Activity - working" : "Activity"
    }

    private var workspaceSwitcher: some View {
        Picker("Workspace", selection: Binding(
            get: { model.selectedWorkspace },
            set: { model.selectWorkspace($0) }
        )) {
            ForEach(Workspace.allCases, id: \.self) { workspace in
                Text(workspace.title).tag(workspace)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
    }

    // Grid/Loupe/Timeline/Map: the Library workspace's own sub-view toggle
    // (as distinct from the Cull sub-views reachable via the temporary View
    // menu routes). Loupe here opens the plain-chrome Library loupe, not the
    // culling loupe.
    private var librarySubViewToggle: some View {
        Picker("Library View", selection: Binding(
            get: { model.selectedView },
            set: { model.selectedView = $0 }
        )) {
            Text("Grid").tag(LibraryViewMode.grid)
            Text("Loupe").tag(LibraryViewMode.libraryLoupe)
            Text("Timeline").tag(LibraryViewMode.timeline)
            Text("Map").tag(LibraryViewMode.map)
        }
        .pickerStyle(.segmented)
        .frame(width: 280)
        .accessibilityLabel("Library View")
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
        HStack(spacing: 12) {
            if WorkspaceChromePolicy.showsLibraryViewToggle(model.selectedWorkspace) {
                librarySubViewToggle
            }
            Spacer(minLength: 12)
            if WorkspaceChromePolicy.showsImportButton(model.selectedWorkspace) {
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



    /// The token query field: one text field that both free-text searches and,
    /// via `LibraryQueryToken`, writes recognized filter tokens (rating:,
    /// camera:, etc.) into AppModel's structured filter properties. Replaces
    /// the old compact top-bar search box and the 13-picker filter bar.
    private var queryTokenField: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            TextField("Search photos, people, places, or rating:3 camera:… ", text: Binding(
                get: { model.librarySearchText },
                set: { model.librarySearchText = $0 }
            ))
            .textFieldStyle(.plain)
            .onSubmit {
                submitQueryTokenField()
            }
            .help("Search your library, or type filter tokens like rating:3, camera:, keyword:. Click the info button for the full list.")
            .accessibilityLabel("Search Catalog")
            Button {
                isShowingSearchTips = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Search tips and filter tokens")
            .accessibilityLabel("Search tips")
            .popover(isPresented: $isShowingSearchTips, arrowEdge: .bottom) {
                searchTipsPopover
            }
            Button {
                submitQueryTokenField()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Search")
            .accessibilityLabel("Search")
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 262, maxWidth: .infinity, minHeight: 31)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.09))
        }
        .liveMockupPlaceholder(.agenticSearch)
    }

    private func submitQueryTokenField() {
        LibraryQueryToken.parse(model.librarySearchText, applyingTo: model)
        applyLibraryFilters()
    }

    private var searchTipsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search tips")
                .font(.headline)
            Text("Type anything for a plain text search, or use filter tokens:")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Self.searchTokenTips, id: \.token) { tip in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(tip.token)
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 96, alignment: .leading)
                        Text(tip.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("Repeat person: to require every name, e.g. person:\"Anna\" person:\"Ben\".")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 360)
    }

    private static let searchTokenTips: [(token: String, detail: String)] = [
        ("person:\"Name\"", "Photos of a confirmed person"),
        ("keyword:", "A keyword you've applied"),
        ("folder:", "Photos in a folder"),
        ("camera: / lens:", "By camera body or lens"),
        ("iso:", "By ISO speed"),
        ("rating: / color:", "By star rating or color label"),
        ("from: / before: / date:", "By capture date"),
        ("source: / signal: / xmp:", "By availability, AI signal, or sync state")
    ]

    @ViewBuilder
    private var topInsetContent: some View {
        VStack(spacing: 0) {
            libraryTopBar
            if WorkspaceChromePolicy.showsFilterTokens(model.selectedWorkspace) {
                libraryQueryBar
                libraryResultHeader
            }
            if let summary = visibleImportCompletionSummary {
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

    /// One query surface: a persistent sort picker, the token query field,
    /// an "Add filter" menu covering every option the deleted pickers
    /// offered, and the save/snapshot/refresh/clear button cluster. Replaces
    /// the old 13-picker filter bar.
    private var libraryQueryBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                librarySortPicker

                queryTokenField

                addFilterMenu

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
                    .help("Retry pending metadata sync in current results")
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

            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if !model.activeLibraryFilterChips.isEmpty {
                activeFilterChips
            }
            currentBatchKeywordSuggestionBar
        }
        .padding(.bottom, 7)
        .background(.bar)
        .liveMockupPlaceholder(.searchRefine)
    }

    private var libraryResultHeaderPresentation: LibraryResultHeaderPresentation {
        LibraryResultHeaderPresentation(
            totalAssetCount: model.totalAssetCount,
            librarySearchText: model.librarySearchText,
            canSaveDynamicSet: model.canSaveCurrentLibraryQuery,
            canSaveSnapshotSet: model.canSaveCurrentAssetScopeSnapshot,
            canSaveManualSet: model.canSaveSelectedAssetAsManualSet,
            reviewQueueCounts: model.reviewQueueCounts,
            evaluationKindSummaries: model.catalogEvaluationKindSummaries,
            activeTokens: LibraryQueryToken.tokens(from: model)
        )
    }

    /// Match count + a plain-English "read as" line for whatever's left
    /// after `LibrarySearchIntent` parses out structured filters, plus
    /// catalog-backed suggested filters and the Save ▾ menu. Replaces
    /// SearchWorkspaceView: search results are just the Library in a
    /// filtered state, not a separate route.
    private var libraryResultHeader: some View {
        let presentation = libraryResultHeaderPresentation
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(presentation.matchCount == 1 ? "1 photo" : "\(presentation.matchCount) photos")
                .font(.caption.weight(.semibold))
            if let interpretation = presentation.interpretation {
                Text(interpretation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !presentation.suggestedTokens.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(presentation.suggestedTokens) { token in
                            suggestedTokenChip(token)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if !presentation.saveActions.isEmpty {
                saveMenu(presentation.saveActions)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func suggestedTokenChip(_ token: LibraryQueryToken) -> some View {
        Button {
            LibraryQueryToken.apply(token, to: model)
            applyLibraryFilters()
        } label: {
            Text(token.display)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .help("Add \(token.display) filter")
    }

    private func saveMenu(_ actions: [LibraryResultHeaderPresentation.SaveAction]) -> some View {
        Menu {
            ForEach(actions) { action in
                Button {
                    performSaveAction(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
        } label: {
            Text("Save \u{25BE}")
        }
        .buttonStyle(.borderless)
        .disabled(actions.isEmpty)
        .help("Save this result set")
        .accessibilityLabel("Save")
        .liveMockupPlaceholder(.smartCollectionsBuilder)
        .popover(isPresented: $isSavingSearch) { saveSearchPopover }
        .popover(isPresented: $isSavingSnapshotSet) { saveSnapshotSetPopover }
        .popover(isPresented: $isSavingManualSet) { saveManualSetPopover }
    }

    private func performSaveAction(_ action: LibraryResultHeaderPresentation.SaveAction) {
        switch action {
        case .dynamicSearch:
            showSaveSearchPopover()
        case .frozenSnapshot:
            showSaveSnapshotSetPopover()
        case .manualSet:
            manualSetName = model.suggestedManualSetName
            manualSetStarred = false
            isSavingManualSet = true
        }
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

    /// Covers every option the deleted rating/flag/color/source/signal/xmp
    /// pickers offered. Free-text fields (keyword, folder, camera, lens,
    /// iso, date) stay reachable via typed tokens in the query field itself
    /// (documented in the search-tips popover), plus a date-range shortcut
    /// here since that one has no plain-text UI equivalent.
    private var addFilterMenu: some View {
        Menu {
            Menu("Rating") {
                ForEach(LibraryQueryToken.ratingOptions, id: \.self) { rating in
                    Button("\(rating)+ Stars") {
                        model.minimumRatingFilter = rating
                        applyLibraryFilters()
                    }
                }
            }
            Menu("Flag") {
                ForEach(LibraryQueryToken.flagOptions, id: \.self) { flag in
                    Button(flag.rawValue.capitalized) {
                        model.flagFilter = flag
                        applyLibraryFilters()
                    }
                }
            }
            Menu("Color Label") {
                ForEach(LibraryQueryToken.colorOptions, id: \.self) { color in
                    Button(color.rawValue.capitalized) {
                        model.colorLabelFilter = color
                        applyLibraryFilters()
                    }
                }
            }
            Menu("Source") {
                ForEach(LibraryQueryToken.sourceOptions, id: \.rawValue) { source in
                    Button(source.rawValue.capitalized) {
                        model.availabilityFilter = source
                        applyLibraryFilters()
                    }
                }
            }
            Menu("AI Signal") {
                ForEach(LibraryQueryToken.signalOptions, id: \.rawValue) { signal in
                    Button(signal.displayName) {
                        model.evaluationKindFilter = signal
                        applyLibraryFilters()
                    }
                }
            }
            Menu("Metadata Sync") {
                // Single-select, matching the old MetadataSyncFilterOption
                // picker: choosing one clears the other.
                Button("Pending") {
                    model.metadataSyncPendingFilter = true
                    model.metadataSyncConflictFilter = false
                    applyLibraryFilters()
                }
                Button("Conflicts") {
                    model.metadataSyncConflictFilter = true
                    model.metadataSyncPendingFilter = false
                    applyLibraryFilters()
                }
            }
            Menu("Review Queue") {
                Button("Needs Keywords") {
                    model.needsKeywordsFilter = true
                    applyLibraryFilters()
                }
                Button("Needs Evaluation") {
                    model.needsEvaluationFilter = true
                    applyLibraryFilters()
                }
                Button("Likely Issues") {
                    model.likelyIssuesFilter = true
                    applyLibraryFilters()
                }
                Button("Provider Failures") {
                    model.providerFailuresFilter = true
                    applyLibraryFilters()
                }
            }
            Button("Date Range…") {
                isShowingDateFilters = true
            }
        } label: {
            Image(systemName: "plus.circle")
        }
        .buttonStyle(.borderless)
        .help("Add a filter")
        .accessibilityLabel("Add filter")
        .popover(isPresented: $isShowingDateFilters) {
            dateFilterPopover
        }
    }

    /// Structured-filter chips render straight from `LibraryQueryToken`
    /// (removal goes through the bridge), so the token field, chips, and
    /// AppModel's 13 filter properties are one system. Chips the bridge
    /// doesn't cover — selected asset set, dynamic set rules, detached
    /// predicates, and `librarySearchText`'s own chips/residual — still come
    /// from `activeLibraryFilterRows`, deduplicated by filter identity via
    /// `LibraryQueryToken.legacyRows(_:notCoveredBy:)`.
    private var activeFilterChips: some View {
        let tokens = LibraryQueryToken.tokens(from: model)
        let legacyRows = LibraryQueryToken.legacyRows(model.activeLibraryFilterRows, notCoveredBy: tokens)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Text found")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.orange)
                ForEach(tokens) { token in
                    filterChip(title: token.display, isPlainSearchFallback: false) {
                        LibraryQueryToken.remove(token, from: model)
                        applyLibraryFilters()
                    }
                }
                ForEach(legacyRows) { row in
                    filterChip(title: row.title, isPlainSearchFallback: row.isPlainSearchFallback) {
                        removeActiveLibraryFilter(row)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func filterChip(
        title: String,
        isPlainSearchFallback: Bool,
        remove: @escaping () -> Void
    ) -> some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .lineLimit(1)
                    if isPlainSearchFallback {
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
            isPlainSearchFallback
                ? "Remove plain search fallback filter \(title)"
                : "Remove filter \(title)"
        )
        .help("Remove \(title) filter")
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
                    Text("Suggestions")
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
                    Text("Suggestions")
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
                    Text("Export Photos")
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

            exportPresetPickerRow

            Divider()

            exportSettingsPanel

            if let exportSizeEstimateText {
                Text(exportSizeEstimateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
        .frame(width: 380)
        .task(id: exportSizeEstimateTrigger) {
            await updateExportSizeEstimate()
        }
    }

    private var exportPresetPickerRow: some View {
        HStack(spacing: 6) {
            Picker("Preset", selection: $selectedExportPresetName) {
                ForEach(exportPresets, id: \.name) { preset in
                    Text(preset.name).tag(preset.name)
                }
            }
            .labelsHidden()
            .onChange(of: selectedExportPresetName) { _, newName in
                if let preset = exportPresets.first(where: { $0.name == newName }) {
                    exportSettings = preset.settings
                }
            }

            Button {
                newExportPresetName = ""
                isNamingNewExportPreset = true
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Save current settings as a new preset")

            Button {
                deleteSelectedExportPreset()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(exportPresets.count <= 1)
            .help("Delete this preset")
        }
        .popover(isPresented: $isNamingNewExportPreset) {
            newExportPresetPopover
        }
    }

    private var newExportPresetPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Preset")
                .font(.headline)
            TextField("Preset name", text: $newExportPresetName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") {
                    isNamingNewExportPreset = false
                }
                Spacer()
                Button("Save") {
                    saveNewExportPreset()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newExportPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 240)
    }

    private var exportSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Format", selection: $exportSettings.format) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.rawValue.uppercased()).tag(format)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Quality")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((exportSettings.jpegQuality * 100).rounded()))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $exportSettings.jpegQuality, in: 0...1)
            }
            .disabled(exportSettings.format == .png)
            .opacity(exportSettings.format == .png ? 0.4 : 1)

            HStack {
                Text("Long edge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("No cap", text: exportLongEdgeFieldBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
            }

            Toggle("Include EXIF/IPTC metadata", isOn: $exportSettings.includeSourceMetadata)
                .font(.caption)
        }
    }

    private var exportLongEdgeFieldBinding: Binding<String> {
        Binding(
            get: { exportSettings.longEdgeMaximumPixels.map(String.init) ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                exportSettings.longEdgeMaximumPixels = trimmed.isEmpty ? nil : Int(trimmed)
            }
        )
    }

    private var exportSizeEstimateTrigger: ExportSizeEstimateTrigger {
        ExportSizeEstimateTrigger(
            settings: exportSettings,
            scope: exportScope,
            visibleAssetCount: model.assets.count,
            selectedAssetCount: model.selectedBatchAssetCount,
            totalAssetCount: model.totalAssetCount
        )
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
            Toggle("Organize into dated folders (YYYY/YYYY-MM-DD)", isOn: $importCardPathDraft.organizeIntoDatedFolders)
                .toggleStyle(.checkbox)
                .font(.caption)
                .disabled(isReviewingImportCardPath)
                .help("Files each copied original into year/date folders from its capture date; files without a capture date use their modification date.")
            TextField("Second copy folder path (optional)", text: $importCardPathDraft.secondCopyPath)
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
                if draft.mode == .card {
                    LabeledContent("Second copy", value: draft.secondCopyName ?? "None")
                }
                LabeledContent("Photos", value: draft.sourceSummary.countText)
                if let dedupCountText = draft.dedupCountText {
                    LabeledContent("Duplicates", value: dedupCountText)
                }
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
                if let secondCopyUnavailableReason = draft.secondCopyUnavailableReason {
                    Text(secondCopyUnavailableReason)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if draft.mode == .card {
                Toggle(
                    "Organize into dated folders (YYYY/YYYY-MM-DD)",
                    isOn: Binding(
                        get: { (importConfirmationDraft?.destinationPolicy ?? .capturedDate) == .capturedDate },
                        set: { importConfirmationDraft?.destinationPolicy = $0 ? .capturedDate : .flat }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Files each copied original into year/date folders from its capture date; files without a capture date use their modification date.")
                HStack(spacing: 8) {
                    Button(draft.secondCopyRootURL == nil ? "Second copy to..." : "Change second copy...") {
                        chooseImportSecondCopyDestination()
                    }
                    .font(.caption)
                    if draft.secondCopyRootURL != nil {
                        Button("Remove second copy") {
                            importConfirmationDraft?.setSecondCopyRoot(nil)
                        }
                        .font(.caption)
                    }
                }
            }
            importPlanView(steps: draft.planSteps, width: 440)
            Toggle(
                "Import new photos only",
                isOn: Binding(
                    get: { importConfirmationDraft?.importNewOnly ?? true },
                    set: { importConfirmationDraft?.importNewOnly = $0 }
                )
            )
            .toggleStyle(.checkbox)
            .font(.caption)
            .help("Skips source files whose content is already in the catalog — re-inserting a card copies only the new frames. Turn off to import everything, keeping intentional duplicates.")
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
            Toggle(
                "Autopilot cull after reading",
                isOn: Binding(
                    get: { importConfirmationDraft?.autopilotAfterImport ?? false },
                    set: { importConfirmationDraft?.autopilotAfterImport = $0 }
                )
            )
            .toggleStyle(.checkbox)
            .font(.caption)
            .disabled(!(importConfirmationDraft?.evaluateAfterImport ?? true))
            .help("Once the imported reads finish, Autopilot proposes keeps and cuts for review. Proposals stay provisional; nothing is written until you commit.")
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

    private var librarySortBinding: Binding<LibrarySortOption> {
        Binding(
            get: { model.librarySortOption },
            set: { option in
                applyLibrarySort(option)
            }
        )
    }

    private var hasActiveFilters: Bool {
        model.hasActiveLibraryFilters
    }

    private var assetGrid: some View {
        VStack(spacing: 0) {
            if let summary = model.autopilotRunSummary {
                AutopilotBannerView(
                    presentation: AutopilotBannerPresentation(summary: summary, canUndoAll: model.canUndoAutopilotRun),
                    review: { beginAutopilotReview() },
                    undoAll: { undoAutopilotRun() },
                    dismiss: { model.dismissAutopilotRunSummary() }
                )
            }
            if model.isAutopilotReviewActive {
                autopilotReviewToolbar
            }
            LazyVGrid(columns: columns, spacing: gridLayout.gridSpacing) {
                ForEach(model.assets, id: \.id.rawValue) { asset in
                    AssetGridCell(
                        asset: asset,
                        previewURL: model.gridPreviewURL(for: asset.id),
                        previewCacheGeneration: model.previewCacheGeneration(for: asset.id),
                        previewStatus: model.gridPreviewStatus(for: asset.id),
                        isSelected: model.selectedAssetID == asset.id,
                        isBatchSelected: model.isBatchSelected(asset.id),
                        autopilotDecision: model.autopilotProposalDecision(for: asset.id)
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
    }

    private func beginAutopilotReview() {
        do {
            try model.beginAutopilotReview()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func undoAutopilotRun() {
        do {
            try model.undoAutopilotRun()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private var autopilotReviewToolbar: some View {
        let selectedIDs = model.selectedBatchAssetIDsInCatalogOrder
        return HStack(spacing: 8) {
            Text("Reviewing \(model.autopilotReviewProposalCount) proposals")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            Button("Commit \(selectedIDs.count)") {
                commitAutopilotProposals(assetIDs: selectedIDs)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)
            .disabled(selectedIDs.isEmpty)
            .help("Commit the selected proposals' keeps, cuts, and keywords")
            Button("Commit all \(model.autopilotReviewProposalCount)") {
                commitAllAutopilotProposals()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button("Dismiss selected") {
                dismissAutopilotProposals(assetIDs: selectedIDs)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color.purple.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func commitAutopilotProposals(assetIDs: [AssetID]) {
        do {
            try model.commitAutopilotProposals(assetIDs: assetIDs)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func commitAllAutopilotProposals() {
        do {
            try model.commitAllAutopilotProposals()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func dismissAutopilotProposals(assetIDs: [AssetID]) {
        do {
            try model.dismissAutopilotProposals(assetIDs: assetIDs)
        } catch {
            model.errorMessage = error.localizedDescription
        }
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
                Text("No photos yet")
                    .font(.headline)
                Text("Bring in a folder or memory card to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Menu {
                    Button {
                        showImportFolderPanel()
                    } label: {
                        Label("Folder…", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        showPrimaryCardImportRoute()
                    } label: {
                        Label("From Card…", systemImage: "externaldrive.badge.plus")
                    }
                } label: {
                    Label("Import photos to get started", systemImage: "square.and.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.orange)
                .fixedSize()
                .help("Import photos from a folder or a memory card")
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
            if let statusText = model.libraryStatusText {
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
        presentImportConfirmation(.folder(folderURL))
    }

    // Seeds the draft's Autopilot-after-import toggle from the persisted app
    // setting so the sheet reflects the standing "Autopilot on" preference.
    private func presentImportConfirmation(_ draft: ImportConfirmationDraft) {
        var draft = draft
        draft.autopilotAfterImport = model.autopilotEnabled
        importConfirmationDraft = draft
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
        presentImportConfirmation(.card(source: source, destinationRoot: destinationRoot))
    }

    private func importFolderPath() {
        do {
            let folderURL = try importPathDraft.resolveFolderURL()
            let reviewID = UUID()
            importPathReviewID = reviewID
            isReviewingImportPath = true
            let catalogPaths = model.catalogPaths
            Task {
                let confirmationDraft = await Task.detached(priority: .userInitiated) {
                    var draft = ImportConfirmationDraft.folder(folderURL)
                    draft.dedupPreview = Self.dedupPreview(for: folderURL, catalogPaths: catalogPaths)
                    return draft
                }.value
                await MainActor.run {
                    guard importPathReviewID == reviewID else { return }
                    importPathReviewID = nil
                    isReviewingImportPath = false
                    isShowingImportPathSheet = false
                    presentImportConfirmation(confirmationDraft)
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
            let destinationPolicy = importCardPathDraft.destinationPolicy
            let reviewID = UUID()
            importCardPathReviewID = reviewID
            isReviewingImportCardPath = true
            let catalogPaths = model.catalogPaths
            Task {
                let confirmationDraft = await Task.detached(priority: .userInitiated) {
                    var draft = ImportConfirmationDraft.card(
                        source: roots.source,
                        destinationRoot: roots.destinationRoot,
                        destinationPolicy: destinationPolicy,
                        secondCopyRootURL: roots.secondCopyRoot
                    )
                    draft.dedupPreview = Self.dedupPreview(for: roots.source, catalogPaths: catalogPaths)
                    return draft
                }.value
                await MainActor.run {
                    guard importCardPathReviewID == reviewID else { return }
                    importCardPathReviewID = nil
                    isReviewingImportCardPath = false
                    isShowingImportCardPathSheet = false
                    presentImportConfirmation(confirmationDraft)
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
            importFolder(
                draft.sourceURL,
                evaluateAfterImport: draft.evaluateAfterImport,
                importNewOnly: draft.importNewOnly,
                autopilotAfterImport: draft.autopilotAfterImport
            )
        case .card:
            guard let destinationRootURL = draft.destinationRootURL else {
                model.errorMessage = "Card import destination is missing"
                return
            }
            importCard(
                source: draft.sourceURL,
                destinationRoot: destinationRootURL,
                destinationPolicy: draft.destinationPolicy,
                secondCopyDestination: draft.secondCopyRootURL,
                evaluateAfterImport: draft.evaluateAfterImport,
                importNewOnly: draft.importNewOnly,
                autopilotAfterImport: draft.autopilotAfterImport
            )
        }
    }

    // Opens a short-lived read-only catalog connection off the main actor so the
    // import sheet can promise the new/known split before any copy runs.
    private nonisolated static func dedupPreview(for sourceURL: URL, catalogPaths: AppCatalogPaths?) -> ImportDedupPreview? {
        guard let catalogPaths,
              let database = try? CatalogDatabase.open(at: catalogPaths.catalogURL) else {
            return nil
        }
        return ImportDedupPreview.scan(sourceURL: sourceURL, repository: CatalogRepository(database: database))
    }

    private func chooseImportSecondCopyDestination() {
        guard let secondCopyRootURL = FolderSelectionPanel.chooseCardSecondCopyFolder() else { return }
        importConfirmationDraft?.setSecondCopyRoot(secondCopyRootURL)
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

    private func importFolder(
        _ folderURL: URL,
        evaluateAfterImport: Bool = true,
        importNewOnly: Bool = true,
        autopilotAfterImport: Bool = false
    ) {
        model.beginImportFolder(
            folderURL,
            evaluateAfterImport: evaluateAfterImport,
            importNewOnly: importNewOnly,
            autopilotAfterImport: autopilotAfterImport
        )
    }

    private func importCard(
        source: URL,
        destinationRoot: URL,
        destinationPolicy: ImportDestinationPolicy,
        secondCopyDestination: URL?,
        evaluateAfterImport: Bool = true,
        importNewOnly: Bool = true,
        autopilotAfterImport: Bool = false
    ) {
        model.beginImportCard(
            source: source,
            destinationRoot: destinationRoot,
            destinationPolicy: destinationPolicy,
            secondCopyDestination: secondCopyDestination,
            evaluateAfterImport: evaluateAfterImport,
            importNewOnly: importNewOnly,
            autopilotAfterImport: autopilotAfterImport
        )
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

    private func openBatchMetadataSheet() {
        batchMetadataDraft = BatchMetadataDraft(
            creator: model.defaultCreator,
            copyright: model.defaultCopyright
        )
        batchMetadataScope = model.selectedBatchAssetCount > 0 ? .selected : .visible
        isAllCatalogBatchMetadataConfirmed = false
        isReviewingBatchMetadata = true
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

    private func resolvedDestinationFolder(override: URL?, panel: () -> URL?) -> URL? {
        guard let override else { return panel() }
        do {
            try FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
        } catch {
            model.errorMessage = error.localizedDescription
            return nil
        }
        return override
    }

    private func chooseExportDestinationAndExport() {
        guard let destination = resolvedDestinationFolder(
            override: LibraryGridChromePolicy.exportDestinationDirectoryOverride(
                environment: ProcessInfo.processInfo.environment
            ),
            panel: { FolderSelectionPanel.chooseExportDestinationFolder() }
        ) else { return }
        let settings = exportSettings
        let scope = exportScope
        ExportPresetStore.rememberLastUsedPreset(named: selectedExportPresetName)
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

    private func beginRejectRelocation() {
        guard let destination = resolvedDestinationFolder(
            override: LibraryGridChromePolicy.rejectDestinationDirectoryOverride(
                environment: ProcessInfo.processInfo.environment
            ),
            panel: { FolderSelectionPanel.chooseRejectDestinationFolder() }
        ) else { return }
        isRejectRelocationConfirmed = false
        do {
            rejectRelocationPreflight = try model.rejectRelocationPreflight(destinationFolder: destination)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func confirmRejectRelocation(_ preflight: RejectRelocationPreflight) {
        rejectRelocationPreflight = nil
        isRejectRelocationConfirmed = false
        do {
            try model.moveRejectsToFolder(preflight)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func moveBackRejectRelocation(sessionID: WorkSessionID) {
        do {
            try model.moveBackRelocation(sessionID: sessionID)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func rejectRelocationSheet(_ preflight: RejectRelocationPreflight) -> some View {
        let presentation = RejectRelocationSheetPresentation(
            preflight: preflight,
            isConfirmed: isRejectRelocationConfirmed
        )
        VStack(alignment: .leading, spacing: 12) {
            Text(presentation.titleText)
                .font(.headline)
            Text(presentation.summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let warningText = presentation.warningText {
                Label(warningText, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !presentation.destinationPreviewRows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(presentation.destinationPreviewRows, id: \.self) { row in
                            Text(row)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
            if preflight.hasMovableFiles {
                Toggle(preflight.confirmationText, isOn: $isRejectRelocationConfirmed)
                    .font(.caption)
            }
            HStack {
                Button("Cancel") {
                    rejectRelocationPreflight = nil
                    isRejectRelocationConfirmed = false
                }
                Spacer()
                Button(presentation.moveButtonTitle) {
                    confirmRejectRelocation(preflight)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!presentation.isMoveEnabled)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func saveNewExportPreset() {
        let trimmedName = newExportPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let preset = ExportPreset(name: trimmedName, settings: exportSettings)
        exportPresets = ExportPresetListEditing.upserting(preset, into: exportPresets)
        ExportPresetStore.savePresets(exportPresets)
        selectedExportPresetName = trimmedName
        isNamingNewExportPreset = false
    }

    private func deleteSelectedExportPreset() {
        exportPresets = ExportPresetListEditing.removing(named: selectedExportPresetName, from: exportPresets)
        ExportPresetStore.savePresets(exportPresets)
        if let firstRemaining = exportPresets.first, firstRemaining.name != selectedExportPresetName {
            selectedExportPresetName = firstRemaining.name
            exportSettings = firstRemaining.settings
        }
    }

    private func updateExportSizeEstimate() async {
        let scope = exportScope
        let settings = exportSettings
        let sampleURLs: [URL]
        let totalAssetCount: Int
        switch scope {
        case .selected:
            sampleURLs = model.assets.filter { model.isBatchSelected($0.id) }.map(\.originalURL)
            totalAssetCount = model.selectedBatchAssetCount
        case .visible:
            sampleURLs = model.assets.map(\.originalURL)
            totalAssetCount = model.assets.count
        case .currentScope:
            // The full current-scope asset list may extend past the loaded
            // page; sampling from what's loaded is an approximation the
            // "estimated" framing already accounts for.
            sampleURLs = model.assets.map(\.originalURL)
            totalAssetCount = model.totalAssetCount
        }
        guard !sampleURLs.isEmpty, totalAssetCount > 0 else {
            exportSizeEstimateText = nil
            return
        }
        let estimate = await Task.detached(priority: .utility) {
            ExportSizeEstimator().estimate(sampleURLs: sampleURLs, settings: settings, totalAssetCount: totalAssetCount)
        }.value
        guard !Task.isCancelled else { return }
        exportSizeEstimateText = estimate.map(Self.formattedExportSizeEstimateText)
    }

    private static func formattedExportSizeEstimateText(_ estimate: ExportSizeEstimate) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "≈ \(formatter.string(fromByteCount: estimate.estimatedTotalBytes)) estimated"
    }

    private func evaluateSelectedAsset() {
        do {
            try model.requestSelectedAssetEvaluations()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func findBestShots() {
        do {
            try model.findBestShots()
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

    private func handleGridCommand(_ command: GridKeyCommand) {
        do {
            try model.applyGridKeyCommand(command, columns: gridColumnCount)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func updateGridColumnCount(width: CGFloat) {
        gridColumnCount = LibraryGridColumnCount.columns(
            availableWidth: width - gridContentInset,
            minimumItemWidth: gridLayout.gridItemMinimumWidth,
            spacing: gridLayout.gridSpacing
        )
    }
}

struct AutopilotBadgePresentation: Equatable {
    // Maps a pending proposal's decision to the grid cell's KEEP/CUT badge.
    // Keyword proposals and undecided cells carry no keep/cut badge.
    static func badge(for kind: AutopilotProposalKind?) -> (text: String, isKeep: Bool)? {
        switch kind {
        case .pick:
            return (text: "KEEP", isKeep: true)
        case .reject:
            return (text: "CUT", isKeep: false)
        case .keyword, nil:
            return nil
        }
    }
}

struct AutopilotBannerPresentation: Equatable {
    var title: String
    var detailText: String
    var canUndoAll: Bool

    init(summary: AutopilotRunSummary, canUndoAll: Bool = false) {
        let frameCount = summary.keeperCount + summary.rejectCount
        let formattedFrames = Self.frameCountFormatter.string(from: NSNumber(value: frameCount)) ?? "\(frameCount)"
        self.title = "Autopilot reviewed \(formattedFrames) frames"
        self.detailText = summary.bannerText
        self.canUndoAll = canUndoAll
    }

    private static let frameCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter
    }()
}

private struct AutopilotBannerView: View {
    var presentation: AutopilotBannerPresentation
    var review: () -> Void
    var undoAll: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                Text(presentation.detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Review") {
                review()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.purple)
            .help("Open the proposed keeps and cuts to commit or dismiss")
            Button("Undo all") {
                undoAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!presentation.canUndoAll)
            .help(presentation.canUndoAll ? "Revert the last committed autopilot batch" : "Nothing committed to undo yet")
            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color.purple.opacity(0.12))
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Autopilot run summary")
        .accessibilityValue(presentation.detailText)
    }
}

private struct CullingCompletionBannerView: View {
    var summary: CullingSessionCompletionSummary
    var canViewPicks: Bool
    var viewPicks: () -> Void
    var cullRemainingSingles: () -> Void
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
            if summary.remainingSingleCount > 0 {
                Button("Cull remaining \(summary.remainingSingleCount) singles") {
                    cullRemainingSingles()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Start a rapid-cull session over the frames this stack cull left unstacked and undecided")
            }
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

private struct RejectRelocationBannerView: View {
    var summary: RejectRelocationSummary
    var moveBack: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(.blue)
            Text(summary.detailText)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Move back") {
                moveBack()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Move these photos back to where they came from")
            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color.blue.opacity(0.12))
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reject relocation complete")
    }
}

private struct LoupeView: View {
    var model: AppModel

    @State private var closeUpCrops: [(id: Int, image: CGImage)] = []

    private var loupePresentation: LoupePresentation {
        LoupePresentation(mode: model.selectedView)
    }

    var body: some View {
        let stackPresentation = cullingStackPresentation
        let presentation = loupePresentation
        VStack(spacing: 0) {
            if presentation.showsCullChrome {
                if let summary = model.autopilotRunSummary {
                    AutopilotBannerView(
                        presentation: AutopilotBannerPresentation(summary: summary, canUndoAll: model.canUndoAutopilotRun),
                        review: {
                            do {
                                try model.beginAutopilotReview()
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                        },
                        undoAll: {
                            do {
                                try model.undoAutopilotRun()
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                        },
                        dismiss: { model.dismissAutopilotRunSummary() }
                    )
                }
                cullingHeader(stackPresentation: stackPresentation)
            }
            HStack(spacing: 0) {
                if presentation.showsCullChrome {
                    cullingStackListRail
                }
                VStack(spacing: 0) {
                    if let asset = model.selectedAsset {
                        HStack(spacing: 0) {
                            loupeStage(for: asset)
                            if presentation.showsCullChrome {
                                closeUpsPanel
                            }
                        }
                        .task(id: asset.id.rawValue) {
                            do {
                                try model.requestVisibleLoupePreview(assetID: asset.id)
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                            if presentation.showsCullChrome {
                                await refreshCloseUps(for: asset.id)
                            }
                        }
                    } else {
                        unavailableView(title: "No photo selected", systemImage: "photo")
                    }
                }
            }
            if presentation.showsCullChrome {
                if let completion = model.cullingSessionCompletion {
                    CullingCompletionBannerView(
                        summary: completion,
                        canViewPicks: completion.picksSetID != nil,
                        viewPicks: { openCullingSessionPicks() },
                        cullRemainingSingles: { cullRemainingSingles() },
                        dismiss: { model.dismissCullingSessionCompletion() }
                    )
                }
                cullingStackRail(presentation: stackPresentation)
                cullingFilmstrip(recommendedAssetID: stackPresentation.recommendedAssetID)
                cullingCommandRail(stackPresentation: stackPresentation)
            } else {
                libraryLoupeNavBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.34))
    }

    // Plain prev/next navigation for the Library loupe: no pick/reject,
    // rating, color-label, or assist chrome — just stepping through the
    // current result set and a reminder of how to get back to the grid.
    private var libraryLoupeNavBar: some View {
        HStack(spacing: 14) {
            cullingNavChevron(direction: .previous)
            cullingNavChevron(direction: .next)
            Spacer(minLength: 0)
            Text("Esc: Grid")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(.bar)
    }

    private func openCullingSessionPicks() {
        do {
            try model.openCullingSessionPicks()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func cullRemainingSingles() {
        do {
            try model.cullRemainingSinglesFromCullingCompletion()
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
                    Text("Text found")
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
            if model.loupeZoomPreviewURL(for: asset.id) != nil {
                LoupeZoomStageView(model: model, asset: asset)
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

    private func cullingCommandRail(stackPresentation: CullingStackRailPresentation) -> some View {
        HStack(spacing: 14) {
            cullingNavChevron(direction: .previous)
            cullingNavChevron(direction: .next)

            Divider()
                .frame(height: 22)

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
            Text(CullingNavLegendPresentation(isStackActive: stackPresentation.isVisible).legendText)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(.bar)
    }

    private enum CullingNavDirection {
        case previous
        case next

        var shortcut: CullingShortcut {
            switch self {
            case .previous: .previousPhoto
            case .next: .nextPhoto
            }
        }

        var systemImage: String {
            switch self {
            case .previous: "chevron.left"
            case .next: "chevron.right"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .previous: "Previous photo"
            case .next: "Next photo"
            }
        }
    }

    private func cullingNavChevron(direction: CullingNavDirection) -> some View {
        Button {
            applyCullingShortcut(direction.shortcut)
        } label: {
            Image(systemName: direction.systemImage)
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 34)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .help(direction.accessibilityLabel)
        .accessibilityLabel(direction.accessibilityLabel)
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
            if let summaryText = LoupeExifSummaryPresentation(technicalMetadata: asset.technicalMetadata).summaryText {
                Text(summaryText)
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

/// Which filter controls stay on the always-visible primary row versus which
/// tuck behind "More filters ▾". The primary row is deliberately the four a
/// photographer reaches for constantly; everything technical lives behind the
/// disclosure.
enum LibraryFilterControl: String, CaseIterable, Equatable {
    case sort
    case rating
    case flag
    case keyword
    case folder
    case camera
    case lens
    case iso
    case date
    case colorLabel
    case source
    case aiScore
    case metadataSync
}

enum LibraryFilterBarLayout {
    static let defaultControls: [LibraryFilterControl] = [.sort, .rating, .flag, .keyword]

    static let moreControls: [LibraryFilterControl] = [
        .folder, .camera, .lens, .iso, .date, .colorLabel, .source, .aiScore, .metadataSync
    ]
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

    // The top switcher controls only *how* you view the current set. Which set
    // you're looking at (Search, Review, Timeline, People, Places) lives in the
    // sidebar, so those routes are deliberately absent here.
    private static let modeItems = [
        LibraryTopBarModeItem(title: "Grid", systemImage: "square.grid.3x3.fill", mode: .grid),
        LibraryTopBarModeItem(title: "Loupe", systemImage: "rectangle.inset.filled", mode: .loupe),
        LibraryTopBarModeItem(title: "Compare", systemImage: "rectangle.grid.2x2", mode: .compare, liveMockupPlaceholder: .compareSurvey),
        LibraryTopBarModeItem(title: "A/B", systemImage: "rectangle.split.2x1", mode: .abCompare, liveMockupPlaceholder: .focusCompare)
    ]

    private static func breadcrumbItems(scopeTitle: String, selectedView: LibraryViewMode) -> [String] {
        if selectedView == .copilot || selectedView == .timeline || selectedView == .people || selectedView == .map {
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

struct RejectRelocationSheetPresentation: Equatable {
    var titleText: String
    var summaryText: String
    var warningText: String?
    var destinationPreviewRows: [String]
    var isMoveEnabled: Bool
    var moveButtonTitle: String

    init(preflight: RejectRelocationPreflight, isConfirmed: Bool) {
        titleText = "Move rejects to \(preflight.destinationFolder.lastPathComponent)"
        summaryText = preflight.summaryText
        warningText = preflight.warningText
        destinationPreviewRows = preflight.destinationPreview
        isMoveEnabled = preflight.hasMovableFiles && isConfirmed
        moveButtonTitle = preflight.confirmationText
    }
}

/// Drives the export popover's `.task(id:)` size-estimate recompute: any
/// change re-triggers sampling (and SwiftUI auto-cancels the in-flight
/// estimate for the stale inputs).
struct ExportSizeEstimateTrigger: Equatable {
    var settings: ExportSettings
    var scope: BatchScopeMode
    var visibleAssetCount: Int
    var selectedAssetCount: Int
    var totalAssetCount: Int
}

struct CompareSurveyPresentation: Equatable {
    private static let maximumSurveyColumnCount = 4
    /// Tie-break focus-compare (mockup 3b) narrows to the top 3 ranked
    /// contenders; unrelated to the 8-frame survey grid limit above.
    static let contenderCount = 3

    var primaryAsset: Asset?
    var alternateAssets: [Asset]
    var framePositionText: String?
    var groupCountText: String
    var groupKindText: String
    var recommendationText: String
    var recommendedAssetID: AssetID?
    var isContendersModeAvailable: Bool
    var isContendersOnly: Bool
    var contenderAssets: [Asset]
    var comparativeVerdictText: String?
    private var recommendedFrameLabel: String?
    private var signalBadgesByAssetID: [AssetID: [CompareDecisionBadge]]

    init(
        assets: [Asset],
        selectedAssetID: AssetID?,
        evaluationSignalsByAssetID: [AssetID: [EvaluationSignal]] = [:],
        groupKind: CompareGroupKind = .nearbyFrames,
        contendersOnly: Bool = false
    ) {
        guard !assets.isEmpty else {
            self.primaryAsset = nil
            self.alternateAssets = []
            self.framePositionText = nil
            self.groupCountText = "No frames"
            self.groupKindText = "Compare set"
            self.recommendationText = "No comparison set"
            self.recommendedAssetID = nil
            self.isContendersModeAvailable = false
            self.isContendersOnly = false
            self.contenderAssets = []
            self.comparativeVerdictText = nil
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
        self.isContendersModeAvailable = !rankedCandidates.isEmpty
        self.isContendersOnly = contendersOnly && isContendersModeAvailable
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let topContenders = Array(rankedCandidates.prefix(Self.contenderCount))
        self.contenderAssets = topContenders.compactMap { assetsByID[$0.assetID] }
        if self.isContendersOnly, topContenders.count >= 2 {
            let leader = topContenders[0]
            let runnerUp = topContenders[1]
            let qualifiers = CullingStackRecommendation.comparativeQualifiers(
                leader: leader.assetID,
                runnerUp: runnerUp.assetID,
                evaluationSignalsByAssetID: evaluationSignalsByAssetID
            )
            self.comparativeVerdictText = qualifiers.isEmpty
                ? "Frame \(leader.frameLabel) edges it"
                : "Frame \(leader.frameLabel) edges it — \(qualifiers.joined(separator: ", "))"
        } else {
            self.comparativeVerdictText = nil
        }
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

    /// Title for the reversible contenders-only toggle; independent of
    /// availability so the disabled button still reads correctly.
    var contendersToggleTitle: String {
        isContendersOnly ? "Full set" : "Top \(Self.contenderCount) contenders"
    }

    var contendersToggleHelp: String {
        isContendersOnly
            ? "Shows the full compare set again"
            : "Narrows the compare grid to the top \(Self.contenderCount) ranked contenders"
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
        if isContendersOnly {
            return contenderAssets
        }
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

    /// A tie-break action for contenders-only mode: pick the top 2 ranked
    /// contenders and reject the third. Only present with 3+ ranked
    /// contenders, since with fewer there is nothing left to reject.
    func contendersKeepTopTwoAction(canApplyPrimaryChoice: Bool) -> CompareSurveyActionPresentation? {
        guard isContendersOnly, contenderAssets.count >= Self.contenderCount else {
            return nil
        }
        let topTwoAssetIDs = contenderAssets.prefix(2).map(\.id)
        return CompareSurveyActionPresentation(
            action: .keepTopContendersAndRejectRemaining(topTwoAssetIDs),
            title: "Keep #1 & #2",
            isEnabled: canApplyPrimaryChoice,
            help: "Keeps the top two ranked contenders and rejects the remaining visible contender",
            liveMockupPlaceholder: nil
        )
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

    /// #1/#2/#3 rank chips for contenders-only mode; silent otherwise so
    /// rank and signal badges never both claim a tile.
    func rankBadges(for asset: Asset) -> [CompareDecisionBadge] {
        guard isContendersOnly, let rank = contenderAssets.firstIndex(where: { $0.id == asset.id }) else {
            return []
        }
        return [CompareDecisionBadge(text: "#\(rank + 1)", tone: .rank)]
    }

    /// Badges for a compare tile: metadata decision badges plus rank chips
    /// in contenders-only mode, or signal reads (BEST / EYES CLOSED / SOFT)
    /// otherwise.
    func tileBadges(for asset: Asset) -> [CompareDecisionBadge] {
        decisionBadges(for: asset) + (isContendersOnly ? rankBadges(for: asset) : signalBadges(for: asset))
    }

    // Same calibrated defect anchor as the likelyIssue focus term: the
    // study's p5 (raw 0.06 / 0.15 = 0.4). The old 0.5 flagged every real
    // frame on the raw scale.
    private static let softFocusBadgeThreshold = 0.4

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
        // Fractional eyesOpen is CIDetector noise on tiny/occluded faces;
        // only 0.0 (all eyes shut) earns the destructive badge.
        if let eyesOpen = highestConfidenceScore(kind: .eyesOpen, in: signals), eyesOpen <= 0.0 {
            badges.append(CompareDecisionBadge(text: "EYES CLOSED", tone: .destructive))
        }
        if let focus = highestConfidenceScore(kind: .focus, in: signals), focus <= softFocusBadgeThreshold {
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
        case keepTopContendersAndRejectRemaining([AssetID])
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
        case .keepTopContendersAndRejectRemaining(let assetIDs):
            return "keep-top-contenders-and-reject-remaining-\(assetIDs.map(\.rawValue).joined(separator: "-"))"
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
        case rank
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
    // a bare percentage: eyes/smile as plain-language state, exposure as a
    // brightness delta from neutral. The exposure signal is average preview
    // luminance, not metered exposure, so the copy must not claim EV stops.
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
    private static let exposureDeltaRange = 4.0

    private static func exposureDeltaText(score: Double) -> String {
        let delta = (score - exposureNeutralScore) * exposureDeltaRange
        let rounded = (delta * 10).rounded() / 10
        guard rounded != 0 else { return "Balanced" }
        let direction = rounded > 0 ? "Bright +" : "Dark -"
        return "\(direction)\(String(format: "%.1f", abs(rounded)))"
    }

    private static func tone(for signal: EvaluationSignal) -> CompareFocusMetric.Tone {
        switch (signal.kind, signal.value) {
        case (.motionBlur, .score(let score)):
            return score >= 0.5 ? .caution : .positive
        case (.focus, .score(let score)),
             (.framing, .score(let score)),
             (.aesthetics, .score(let score)):
            return score >= 0.7 ? .positive : .caution
        case (.faceQuality, .score(let score)):
            return score >= EvaluationSignalPresentation.faceQualityStrongThreshold ? .positive : .caution
        case (.exposure, _):
            return .neutral
        case (.eyeSharpness, .score(let score)):
            return score >= EvaluationSignalPresentation.eyeSharpnessSharpThreshold ? .positive : .caution
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
    // Calibrated eyeSharpness p75 from the 2026-07-06 calibration study
    // (raw 0.05 / 0.15 ceiling): eyes at or above the corpus top quartile
    // read as sharp everywhere eye sharpness is phrased or toned.
    static let eyeSharpnessSharpThreshold = 0.33

    // faceQuality p75 from the same study; matches the likelyPick
    // strong-read anchor (CatalogRepository). Vision faceCaptureQuality
    // tops out near 0.703 on the corpus, so the old shared 0.7 line
    // rendered virtually every face lane as caution.
    static let faceQualityStrongThreshold = 0.45

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

/// A compact one-line reminder of the culling keyboard shortcuts, shown next
/// to the on-screen prev/next chevrons. Keyboard already does everything
/// this legend describes; it exists purely for discoverability.
struct CullingNavLegendPresentation: Equatable {
    var legendText: String

    init(isStackActive: Bool) {
        var segments = ["← → navigate", "Space advances", "Z 1:1"]
        if isStackActive {
            segments.append("↑↓ stacks")
            segments.append("↵ accept best")
        }
        legendText = segments.joined(separator: " · ")
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

/// Pairs the anchor frame (A) with a single contender (B) for the A/B
/// side-by-side comparator. The contender is chosen by priority: an explicit
/// override (the user clicked another frame in the filmstrip), else the
/// recommended frame, else the next neighbor of the anchor.
struct ABComparePresentation: Equatable {
    var primaryAsset: Asset?
    var contenderAsset: Asset?

    var canCompare: Bool { primaryAsset != nil && contenderAsset != nil }

    init(
        assets: [Asset],
        selectedAssetID: AssetID?,
        recommendedAssetID: AssetID? = nil,
        contenderOverrideID: AssetID? = nil
    ) {
        let primary = selectedAssetID.flatMap { id in assets.first { $0.id == id } } ?? assets.first
        primaryAsset = primary

        guard let primary, assets.count > 1 else {
            contenderAsset = nil
            return
        }

        contenderAsset = Self.resolveContender(
            assets: assets,
            primary: primary,
            recommendedAssetID: recommendedAssetID,
            contenderOverrideID: contenderOverrideID
        )
    }

    private static func resolveContender(
        assets: [Asset],
        primary: Asset,
        recommendedAssetID: AssetID?,
        contenderOverrideID: AssetID?
    ) -> Asset? {
        if let overrideID = contenderOverrideID,
           overrideID != primary.id,
           let override = assets.first(where: { $0.id == overrideID }) {
            return override
        }
        if let recommendedAssetID,
           recommendedAssetID != primary.id,
           let recommended = assets.first(where: { $0.id == recommendedAssetID }) {
            return recommended
        }
        guard let anchorIndex = assets.firstIndex(where: { $0.id == primary.id }) else {
            return nil
        }
        let neighborIndex = anchorIndex + 1 < assets.count ? anchorIndex + 1 : anchorIndex - 1
        guard assets.indices.contains(neighborIndex) else { return nil }
        return assets[neighborIndex]
    }

    var positionText: String {
        guard let primaryAsset, let contenderAsset else {
            return "Need two frames to compare"
        }
        return "Comparing \(Self.shortName(primaryAsset)) vs \(Self.shortName(contenderAsset))"
    }

    private static func shortName(_ asset: Asset) -> String {
        asset.originalURL.deletingPathExtension().lastPathComponent
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
        CullingQualityScore.qualityScore(for: signals)
    }

    // Defect-inverted score plus confidence-scaled weight for one signal.
    // The pill's read, the stack ranking, and the autopilot planner all derive
    // from the shared Core scorer, so they can never disagree.
    static func qualityComponent(for signal: EvaluationSignal) -> (score: Double, weight: Double)? {
        CullingQualityScore.qualityComponent(for: signal)
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

    /// A focus-score percentage delta is only honest when the runner-up's
    /// score is comfortably above zero: the metric is an average
    /// neighbor-luminance delta, a true ratio scale starting at zero, but a
    /// near-zero denominator turns a small absolute gap into an inflated,
    /// noise-driven percentage.
    private static let minimumRunnerUpFocusForPercentageDelta = 0.1

    /// Honest, comparative one-line qualifiers between the leader and
    /// runner-up of a tie-break, in display order. A sharpness claim only
    /// appears when the leader's own raw focus score actually exceeds the
    /// runner-up's — the composite ranking score can favor a leader who
    /// wins on a different signal instead, and this must not overclaim that.
    static func comparativeQualifiers(
        leader: AssetID,
        runnerUp: AssetID,
        evaluationSignalsByAssetID: [AssetID: [EvaluationSignal]]
    ) -> [String] {
        var qualifiers: [String] = []
        let leaderSignals = evaluationSignalsByAssetID[leader] ?? []
        let runnerUpSignals = evaluationSignalsByAssetID[runnerUp] ?? []

        if let leaderFocus = bestScore(kind: .focus, in: leaderSignals),
           let runnerUpFocus = bestScore(kind: .focus, in: runnerUpSignals),
           leaderFocus > runnerUpFocus {
            if runnerUpFocus >= minimumRunnerUpFocusForPercentageDelta {
                let percentage = Int(((leaderFocus - runnerUpFocus) / runnerUpFocus * 100).rounded())
                qualifiers.append("\(percentage)% sharper")
            } else {
                qualifiers.append("sharper")
            }
        }
        if let leaderEyesOpen = bestScore(kind: .eyesOpen, in: leaderSignals), leaderEyesOpen >= 1.0 {
            qualifiers.append("eyes open")
        }
        return qualifiers
    }
}

private struct ABCompareView: View {
    var model: AppModel

    private var recommendedAssetID: AssetID? {
        CullingStackRailPresentation(
            assets: model.assets,
            selectedAssetID: model.selectedAssetID,
            evaluationSignalsByAssetID: model.selectedCullingStackEvaluationSignals(),
            explicitStackScope: model.selectedCullingStackScope
        ).recommendedAssetID
    }

    var body: some View {
        let presentation = ABComparePresentation(
            assets: model.assets,
            selectedAssetID: model.selectedAssetID,
            recommendedAssetID: recommendedAssetID,
            contenderOverrideID: model.abContenderAssetID
        )
        return VStack(spacing: 0) {
            header(presentation)
            if let primary = presentation.primaryAsset, let contender = presentation.contenderAsset {
                HStack(spacing: 2) {
                    pane(asset: primary, label: "A", isAnchor: true)
                    pane(asset: contender, label: "B", isAnchor: false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                keepActionBar(primary: primary, contender: contender)
            } else {
                singleFrameNotice
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            abFilmstrip(primaryID: presentation.primaryAsset?.id)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.34))
        .task(id: abPreviewTaskID(presentation)) {
            requestPreviews(for: [presentation.primaryAsset, presentation.contenderAsset].compactMap { $0 })
        }
        .liveMockupPlaceholder(.focusCompare)
    }

    private func header(_ presentation: ABComparePresentation) -> some View {
        HStack(spacing: 8) {
            Text("A/B")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            Text(presentation.positionText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                model.toggleLoupeZoom()
            } label: {
                Label(model.loupeZoomFocus == nil ? "Zoom 1:1" : "Fit", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Zoom both frames to the same region (synced)")
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.18))
    }

    private func pane(asset: Asset, label: String, isAnchor: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.22)
            if model.loupePreviewURL(for: asset.id) != nil {
                LoupeZoomStageView(model: model, asset: asset)
                    .padding(16)
            } else {
                unavailablePane
            }
            paneLabel(label, asset: asset, isAnchor: isAnchor)
                .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            Rectangle()
                .strokeBorder(isAnchor ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.18), lineWidth: isAnchor ? 2 : 1)
        )
    }

    private func paneLabel(_ label: String, asset: Asset, isAnchor: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.monospaced().weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isAnchor ? Color.accentColor.opacity(0.85) : Color.black.opacity(0.55), in: Capsule())
            Text(asset.originalURL.lastPathComponent)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.85))
            if asset.isRawOriginal {
                Text("RAW")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.4), in: Capsule())
    }

    private var unavailablePane: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No cached preview")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func keepActionBar(primary: Asset, contender: Asset) -> some View {
        HStack(spacing: 10) {
            Button {
                keep(primary.id, over: contender.id)
            } label: {
                Label("Keep A · Reject B", systemImage: "checkmark.circle")
            }
            Button {
                keep(contender.id, over: primary.id)
            } label: {
                Label("Keep B · Reject A", systemImage: "checkmark.circle")
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.18))
    }

    private var singleFrameNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Load at least two frames to compare A/B")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func abFilmstrip(primaryID: AssetID?) -> some View {
        let presentation = CullingFilmstripPresentation(
            assets: model.assets,
            selectedAssetID: model.selectedAssetID
        )
        return VStack(spacing: 6) {
            HStack {
                Text("Click a frame to set B")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 7) {
                ForEach(presentation.visibleAssets, id: \.id.rawValue) { asset in
                    abFilmstripTile(asset: asset, isAnchor: asset.id == primaryID)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 86)
        .background(Color.black.opacity(0.18))
        .task(id: presentation.requestID) {
            requestPreviews(for: presentation.visibleAssets)
        }
    }

    private func abFilmstripTile(asset: Asset, isAnchor: Bool) -> some View {
        let isContender = asset.id == model.abContenderAssetID
        return Button {
            if isAnchor {
                model.selectABContender(nil)
            } else {
                model.selectABContender(asset.id)
            }
        } label: {
            Group {
                if let url = model.loupePreviewURL(for: asset.id), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.black.opacity(0.3)
                }
            }
            .frame(width: 92, height: 62)
            .clipped()
            .overlay(
                Rectangle().strokeBorder(
                    isAnchor ? Color.accentColor : (isContender ? Color.white.opacity(0.9) : Color.clear),
                    lineWidth: 2
                )
            )
        }
        .buttonStyle(.plain)
        .help(isAnchor ? "Anchor (A)" : "Set as contender (B)")
    }

    private func abPreviewTaskID(_ presentation: ABComparePresentation) -> String {
        [presentation.primaryAsset?.id.rawValue, presentation.contenderAsset?.id.rawValue]
            .map { $0 ?? "none" }
            .joined(separator: "|")
    }

    private func requestPreviews(for assets: [Asset]) {
        do {
            for asset in assets {
                try model.requestVisibleGridPreview(assetID: asset.id)
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func keep(_ keptID: AssetID, over rejectedID: AssetID) {
        do {
            try model.keepABFrame(keeping: keptID, over: rejectedID)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct CompareView: View {
    var model: AppModel
    var focusCullingSurface: () -> Void

    @State private var isContendersOnly = false

    private let focusMetricColumns = [GridItem(.adaptive(minimum: 78), spacing: 5)]

    var body: some View {
        let compareAssets = model.compareAssets()
        let presentation = CompareSurveyPresentation(
            assets: compareAssets,
            selectedAssetID: model.selectedAssetID,
            evaluationSignalsByAssetID: Dictionary(uniqueKeysWithValues: compareAssets.map { asset in
                (asset.id, model.evaluationSignals(for: asset.id))
            }),
            groupKind: model.compareGroupKind(),
            contendersOnly: isContendersOnly
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                compareHeader(presentation)
                if let completion = model.cullingSessionCompletion {
                    CullingCompletionBannerView(
                        summary: completion,
                        canViewPicks: completion.picksSetID != nil,
                        viewPicks: { openCullingSessionPicks() },
                        cullRemainingSingles: { cullRemainingSingles() },
                        dismiss: { model.dismissCullingSessionCompletion() }
                    )
                }
                if let primaryAsset = presentation.primaryAsset {
                    surveyLayout(presentation)
                    if let comparativeVerdictText = presentation.comparativeVerdictText {
                        comparativeVerdictStrip(comparativeVerdictText)
                    }
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

    private func cullRemainingSingles() {
        do {
            try model.cullRemainingSinglesFromCullingCompletion()
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
                isContendersOnly.toggle()
            } label: {
                Label(presentation.contendersToggleTitle, systemImage: "3.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!presentation.isContendersModeAvailable)
            .help(presentation.contendersToggleHelp)
            .liveMockupPlaceholder(.focusCompare)
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
            compareDecisionBadges(presentation.tileBadges(for: asset))
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
        case .primary, .rating, .best, .rank:
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
        case .best, .rank:
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

    private func comparativeVerdictStrip(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .liveMockupPlaceholder(.focusCompare)
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
            if let keepTopTwoAction = presentation.contendersKeepTopTwoAction(
                canApplyPrimaryChoice: model.canKeepComparePrimaryAndRejectAlternates
            ) {
                Button(keepTopTwoAction.title) {
                    applyCompareGroupAction(keepTopTwoAction.action)
                }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!keepTopTwoAction.isEnabled)
                    .help(keepTopTwoAction.help)
                    .liveMockupPlaceholder(keepTopTwoAction.liveMockupPlaceholder)
            }
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
        case .keepTopContendersAndRejectRemaining(let assetIDs):
            applyKeepTopTwoContenders(assetIDs)
        }
    }

    private func applyKeepTopTwoContenders(_ assetIDs: [AssetID]) {
        do {
            focusCullingSurface()
            try model.keepTopTwoCompareContendersAndRejectAlternates(assetIDs: assetIDs)
        } catch {
            model.errorMessage = error.localizedDescription
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

// Places browse route (design 5b): a MapKit map of cluster bubbles sized by
// photo count, a TOP LOCATIONS list, and a coverage badge. A thin shell over the
// tested PlacesPresentation — no snapshot tests. Region changes re-query bounded
// SQL cluster counts; a bubble or top-location tap drills the grid via the
// indexed geo predicate.
private struct PlacesWorkspaceView: View {
    var model: AppModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var lastCellSize: Double = AppModel.defaultPlaceClusterCellSize

    private var presentation: PlacesPresentation {
        PlacesPresentation(
            clusters: model.catalogPlaceClusters,
            topLocations: model.catalogTopLocations,
            coverage: model.geotaggedCoverage
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            if presentation.hasGeotaggedPhotos {
                mapSurface
            } else {
                placesEmptyState
            }
            placesSidebar
                .frame(width: 300)
        }
        .background(Color.black.opacity(0.18))
        .liveMockupPlaceholder(.placesMap)
        .onAppear {
            try? model.refreshPlaceData()
        }
    }

    private var placesEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("No places yet")
                .font(.title3.weight(.semibold))
            Text(presentation.emptyStateText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var mapSurface: some View {
        Map(position: $cameraPosition) {
            ForEach(presentation.bubbles) { bubble in
                Annotation(
                    "",
                    coordinate: CLLocationCoordinate2D(latitude: bubble.latitude, longitude: bubble.longitude)
                ) {
                    bubbleMarker(bubble)
                }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            handleRegionChange(context.region)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bubbleMarker(_ bubble: PlaceBubblePresentation) -> some View {
        Button {
            drill(latitude: bubble.latitude, longitude: bubble.longitude, half: max(lastCellSize / 2, 0.01))
        } label: {
            Text(bubble.labelText)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: bubble.radius, height: bubble.radius)
                .background(Color.orange.opacity(0.82), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("\(bubble.labelText) photos")
    }

    private var placesSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(presentation.coverageText, systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(presentation.summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.geotaggedCoverage.totalCount > model.geotaggedCoverage.geotaggedCount {
                Button("Read locations for existing photos") {
                    try? model.beginCoordinateBackfill()
                }
                .font(.caption)
                .buttonStyle(.link)
            }
            Text("TOP LOCATIONS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if presentation.topLocations.isEmpty {
                Text("Locations appear here as geocoding finishes.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(presentation.topLocations) { location in
                            topLocationRow(location)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.bar)
    }

    private func topLocationRow(_ location: PlaceRowPresentation) -> some View {
        Button {
            drill(latitude: location.latitude, longitude: location.longitude, half: 0.05)
        } label: {
            HStack(spacing: 8) {
                Text(location.title)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(location.countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func handleRegionChange(_ region: MKCoordinateRegion) {
        let cellSize = max(region.span.latitudeDelta / 8, 0.0005)
        lastCellSize = cellSize
        let bounds = GeoBounds(
            minLatitude: region.center.latitude - region.span.latitudeDelta / 2,
            maxLatitude: region.center.latitude + region.span.latitudeDelta / 2,
            minLongitude: region.center.longitude - region.span.longitudeDelta / 2,
            maxLongitude: region.center.longitude + region.span.longitudeDelta / 2
        )
        try? model.refreshPlaceData(bounds: bounds, cellSize: cellSize)
    }

    private func drill(latitude: Double, longitude: Double, half: Double) {
        let bounds = GeoBounds(
            minLatitude: latitude - half,
            maxLatitude: latitude + half,
            minLongitude: longitude - half,
            maxLongitude: longitude + half
        )
        try? model.selectPlaceBounds(bounds)
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
        .accessibilityLabel("\(year.year), \(year.assetCount) photos")
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
                            isBatchSelected: model.isBatchSelected(asset.id),
                            autopilotDecision: model.autopilotProposalDecision(for: asset.id)
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

/// Which browse-oriented chrome (search, filters, footer, inspector) a
/// workspace shows. Views branch on this policy, never on raw `Workspace`
/// cases, so the test matrix pins the behavior. Library shows all of it;
/// Cull and People are focused surfaces that hide it.
enum WorkspaceChromePolicy {
    static func showsSearchField(_ workspace: Workspace) -> Bool {
        workspace == .library
    }

    static func showsFilterTokens(_ workspace: Workspace) -> Bool {
        workspace == .library
    }

    static func showsImportButton(_ workspace: Workspace) -> Bool {
        workspace == .library
    }

    static func showsLibraryViewToggle(_ workspace: Workspace) -> Bool {
        workspace == .library
    }

    static func showsFooter(_ workspace: Workspace) -> Bool {
        workspace == .library
    }

    static func showsInspector(_ workspace: Workspace) -> Bool {
        workspace == .library
    }
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

    /// The typed-path "Import Path" control is a dev/automation entry, not part
    /// of the primary bar a photographer sees. It surfaces only when the app is
    /// launched against an isolated automation catalog (every `build_and_run.sh
    /// --isolated/--smoke` launch sets this), so the scenario seeders that drive
    /// the typed-path sheet keep working while real users only see Import ▾.
    static func shouldExposeImportPathControl(environment: [String: String]) -> Bool {
        guard let path = environment["TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY"] else { return false }
        return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func rejectDestinationDirectoryOverride(environment: [String: String]) -> URL? {
        destinationDirectoryOverride(environment: environment, key: "TESTSTRIP_REJECT_DESTINATION_DIR")
    }

    static func exportDestinationDirectoryOverride(environment: [String: String]) -> URL? {
        destinationDirectoryOverride(environment: environment, key: "TESTSTRIP_EXPORT_DESTINATION_DIR")
    }

    private static func destinationDirectoryOverride(environment: [String: String], key: String) -> URL? {
        guard let path = environment[key],
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let expandedPath = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath, isDirectory: true)
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
        case .ratingHighestFirst, .ratingLowestFirst:
            return "Rating"
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
        case .ratingHighestFirst:
            return "Highest first"
        case .ratingLowestFirst:
            return "Lowest first"
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
                return chip == "Not analyzed yet"
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

    // Anchored to the 2026-07-06 calibration study on the calibrated
    // focus-family scale: Keep >= 0.7 selects the jointly-strong top quarter
    // of the corpus and Toss <= 0.5 the weak quarter (eyes-shut and
    // bottom-decile-focus frames), leaving roughly half Mixed.
    private static let keepReadThreshold = 0.7
    private static let tossReadThreshold = 0.5

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
            return score >= EvaluationSignalPresentation.eyeSharpnessSharpThreshold ? "Eyes sharp" : "Eyes soft"
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
        case (.focus, .score(let score)):
            return score >= 0.7 ? .positive : .caution
        case (.faceQuality, .score(let score)):
            return score >= EvaluationSignalPresentation.faceQualityStrongThreshold ? .positive : .caution
        case (.aesthetics, .label(let label)), (.framing, .label(let label)):
            return cautionLabels.contains(label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ? .caution : .positive
        case (.faceCount, .count(let count)):
            return count > 0 ? .positive : .neutral
        case (.eyesOpen, .score(let score)):
            return score >= 1.0 ? .positive : .caution
        case (.eyeSharpness, .score(let score)):
            return score >= EvaluationSignalPresentation.eyeSharpnessSharpThreshold ? .positive : .caution
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

/// Compact single-line EXIF summary for the culling loupe: camera · lens ·
/// ISO · aperture · shutter · focal length, omitting fields the asset lacks.
struct LoupeExifSummaryPresentation: Equatable {
    var summaryText: String?

    init(technicalMetadata: AssetTechnicalMetadata?) {
        guard let technicalMetadata else {
            summaryText = nil
            return
        }
        var components: [String] = []
        let camera = [technicalMetadata.cameraMake, technicalMetadata.cameraModel]
            .compactMap(Self.trimmed)
            .joined(separator: " ")
        if !camera.isEmpty {
            components.append(camera)
        }
        if let lensModel = Self.trimmed(technicalMetadata.lensModel) {
            components.append(lensModel)
        }
        if let isoSpeed = technicalMetadata.isoSpeed {
            components.append("ISO \(isoSpeed)")
        }
        if let aperture = technicalMetadata.aperture {
            components.append(ExifSummaryFormatting.apertureText(aperture))
        }
        if let shutterSpeed = technicalMetadata.shutterSpeed {
            components.append(ExifSummaryFormatting.shutterSpeedText(shutterSpeed))
        }
        if let focalLength = technicalMetadata.focalLength {
            components.append(ExifSummaryFormatting.focalLengthText(focalLength))
        }
        summaryText = components.isEmpty ? nil : components.joined(separator: " · ")
    }

    var isVisible: Bool { summaryText != nil }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
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
    var autopilotDecision: AutopilotProposalKind? = nil

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
                HStack(spacing: 4) {
                    if isBatchSelected {
                        batchSelectionBadge
                    }
                    if let badge = AutopilotBadgePresentation.badge(for: autopilotDecision) {
                        autopilotBadge(badge)
                    }
                }
                .padding(6)
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

    private func autopilotBadge(_ badge: (text: String, isKeep: Bool)) -> some View {
        Text(badge.text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(badge.isKeep ? Color.green : Color.red)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
            .accessibilityLabel(badge.isKeep ? "Proposed keep" : "Proposed cut")
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
