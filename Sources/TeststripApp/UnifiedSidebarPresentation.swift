import Foundation
import TeststripCore

/// One completed import, as the sidebar's Imports section sees it. Built from
/// the persisted `WorkSession` rather than `AppWorkActivity`, which drops both
/// dates — and from the unbounded `workSessions(kind:statuses:)` query rather
/// than the mixed-kind, limit-10 `recentWork` cache, which cannot promise
/// three imports.
///
/// Named `ImportSidebarSummary` rather than `ImportSourceSummary` because
/// `ImportConfirmationDraft.swift` already defines an unrelated
/// `ImportSourceSummary` (a pre-import folder scan), and `ImportCompletionSummary`
/// (the single-import banner) is also already taken.
public struct ImportSidebarSummary: Equatable, Sendable {
    public var sessionID: WorkSessionID
    public var createdAt: Date
    public var detail: String
    public var assetCount: Int
    public var issues: [WorkSessionIssue]
    /// Whether the session actually catalogued anything. A completed import
    /// with no output set imported nothing, and gets no Imports row — the
    /// bell receipt is its only record (Jesse 2026-08-08). The summary list
    /// itself still carries it, because it *is* a completed ingest session;
    /// only the section skips it. Defaults to true: a summary describing an
    /// import that happened is the ordinary case.
    public var producedOutputSet: Bool

    public init(
        sessionID: WorkSessionID,
        createdAt: Date,
        detail: String,
        assetCount: Int,
        issues: [WorkSessionIssue],
        producedOutputSet: Bool = true
    ) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.detail = detail
        self.assetCount = assetCount
        self.issues = issues
        self.producedOutputSet = producedOutputSet
    }

    /// An import's `title` and `intent` are both the constant "Import photos",
    /// so the row label is the session's date plus the source-folder text its
    /// `detail` carries — the only distinguishing field.
    public var title: String {
        let dateText = createdAt.formatted(.dateTime.month(.abbreviated).day())
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDetail.isEmpty ? dateText : "\(dateText) · \(trimmedDetail)"
    }
}

/// The counts behind an import row's disclosure children. `likelyIssues` and
/// `facesFound` are each the smart source's own `SetQuery` ANDed with
/// `.importBatch(sessionID)`, so neither can drift from its catalog-wide
/// sibling. The other three are not `SetQuery`s: `stacks` comes from the
/// stack-builder pipeline scoped by `activityID`, `skippedFiles` from the
/// session's stored issue list, and `previewFailed` from `.count` of the same
/// asset-ID list the child row displays.
public struct ImportChildCounts: Equatable, Sendable {
    public var stacks: Int
    public var skippedFiles: Int
    public var previewFailed: Int
    public var likelyIssues: Int
    public var facesFound: Int

    public init(
        stacks: Int = 0,
        skippedFiles: Int = 0,
        previewFailed: Int = 0,
        likelyIssues: Int = 0,
        facesFound: Int = 0
    ) {
        self.stacks = stacks
        self.skippedFiles = skippedFiles
        self.previewFailed = previewFailed
        self.likelyIssues = likelyIssues
        self.facesFound = facesFound
    }

    /// Children render only with nonzero counts, so an all-zero import row
    /// simply has no disclosure triangle.
    public var isEmpty: Bool {
        stacks == 0 && skippedFiles == 0 && previewFailed == 0 && likelyIssues == 0 && facesFound == 0
    }
}

/// The one sidebar, top to bottom: Library, Imports, Smart Collections, Sets,
/// Folders, Recent Work, Selection. Pure value logic — `SidebarView` is a thin
/// shell over this. Every count lives in exactly one place.
public enum UnifiedSidebarPresentation {
    public static let librarySectionTitle = "Library"
    public static let importsSectionTitle = "Imports"
    public static let smartCollectionsSectionTitle = "Smart Collections"
    public static let setsSectionTitle = "Sets"
    public static let foldersSectionTitle = "Folders"
    public static let recentWorkSectionTitle = "Recent Work"
    public static let selectionSectionTitle = "Selection"

    /// The Imports section shows this many rows plus an "All imports…"
    /// overflow row carrying the total.
    public static let recentImportRowLimit = 3
    public static let allImportsRowID = "imports-all"

    private static let smartCollectionOrder: [SmartCollection] = [
        .picks, .potentialPicks, .likelyIssues, .needsEvaluation,
        .rejects, .fiveStars, .needsKeywords, .facesFound, .ocrFound, .providerFailures
    ]

    /// Internal bookkeeping sets never appear as user-facing rows.
    public static func visibleSavedAssetSets(_ assetSets: [AssetSet]) -> [AssetSet] {
        assetSets.filter {
            !$0.id.rawValue.hasPrefix("work-output-")
                && !$0.id.rawValue.hasPrefix("work-input-")
                && !$0.id.rawValue.hasPrefix("work-stack-")
                && !$0.id.rawValue.hasPrefix("import-preview-failed-")
                && !$0.id.rawValue.hasPrefix("selection-source-")
                && !$0.id.rawValue.hasPrefix("cull-selection-")
        }
    }

    public static func countText(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }

    public static func sections(
        totalAssetCount: Int,
        importSummaries: [ImportSidebarSummary],
        runningImport: AppWorkActivity? = nil,
        expandedImportSessionIDs: Set<String>,
        importChildCounts: [String: ImportChildCounts],
        isShowingAllImports: Bool,
        smartCollectionCounts: [SmartCollection: Int],
        autopilotGhostCount: Int,
        savedAssetSets: [AssetSet],
        assetSetCounts: [AssetSetID: Int],
        catalogFolders: [CatalogFolder],
        expandedFolderPaths: Set<String>,
        recentWork: [AppWorkActivity],
        starredWork: [AppWorkActivity],
        matchedWork: [AppWorkActivity],
        isWorkHistorySearchActive: Bool = false,
        workSessionScopeCounts: [WorkSessionID: Int],
        selectionCount: Int
    ) -> [SidebarSection] {
        var sections: [SidebarSection] = [
            SidebarSection(title: librarySectionTitle, rows: [
                SidebarRow(
                    id: "library-all",
                    title: "All Photos",
                    countText: countText(totalAssetCount),
                    target: .allPhotos
                )
            ])
        ]

        let importRows = importSectionRows(
            importSummaries: importSummaries,
            runningImport: runningImport,
            expandedImportSessionIDs: expandedImportSessionIDs,
            importChildCounts: importChildCounts,
            isShowingAllImports: isShowingAllImports
        )
        if !importRows.isEmpty {
            sections.append(SidebarSection(title: importsSectionTitle, rows: importRows))
        }

        let visibleSets = visibleSavedAssetSets(savedAssetSets)
        var smartRows = smartCollectionOrder.compactMap { collection -> SidebarRow? in
            guard let count = smartCollectionCounts[collection], count > 0 else { return nil }
            return SidebarRow(
                id: "smart-\(collection.rawValue)",
                title: collection.presentation.title,
                countText: countText(count),
                tone: collection == .providerFailures ? .warning : .neutral,
                target: .smartCollection(collection)
            )
        }
        if autopilotGhostCount > 0 {
            smartRows.append(SidebarRow(
                id: "smart-ai-suggestions",
                title: "AI Suggestions",
                countText: countText(autopilotGhostCount),
                tone: .accent,
                target: .autopilotSuggestions
            ))
        }
        // A saved dynamic search IS a smart collection — that is exactly what
        // the section header's "+ New from search…" produces.
        smartRows.append(contentsOf: visibleSets.filter(\.isDynamic).map { assetSet in
            row(for: assetSet, count: assetSetCounts[assetSet.id])
        })
        sections.append(SidebarSection(title: smartCollectionsSectionTitle, rows: smartRows))

        // Sets are static membership only, starred first.
        let staticSets = visibleSets.filter { !$0.isDynamic }
        let setRows = (staticSets.filter(\.starred) + staticSets.filter { !$0.starred })
            .map { row(for: $0, count: assetSetCounts[$0.id]) }
        sections.append(SidebarSection(title: setsSectionTitle, rows: setRows))

        if !catalogFolders.isEmpty {
            sections.append(SidebarSection(
                title: foldersSectionTitle,
                rows: folderRows(catalogFolders: catalogFolders, expandedFolderPaths: expandedFolderPaths)
            ))
        }

        // Imports have their own section, so Recent Work carries only the
        // other work kinds — culling, export, relocation, collecting.
        let workActivities = isWorkHistorySearchActive || !matchedWork.isEmpty
            ? matchedWork
            : mergedWorkActivities(recentWork: recentWork, starredWork: starredWork)
        let workRows = workActivities
            .filter { $0.kind != .ingest }
            .map { activity -> SidebarRow in
                let sessionID = WorkSessionID(rawValue: activity.id)
                return SidebarRow(
                    id: "work-\(activity.id)",
                    title: activity.title,
                    detailText: activity.sidebarDetailText,
                    countText: activity.sidebarCountText(scopeCount: workSessionScopeCounts[sessionID]),
                    tone: activity.sidebarTone,
                    target: .workSession(sessionID, titled: activity.title)
                )
            }
        if !workRows.isEmpty {
            sections.append(SidebarSection(title: recentWorkSectionTitle, rows: workRows))
        }

        if selectionCount > 0 {
            sections.append(SidebarSection(title: selectionSectionTitle, rows: [
                SidebarRow(
                    id: "selection",
                    title: "Selection",
                    countText: countText(selectionCount),
                    target: .selection
                )
            ]))
        }

        return sections
    }

    private static func importSectionRows(
        importSummaries: [ImportSidebarSummary],
        runningImport: AppWorkActivity?,
        expandedImportSessionIDs: Set<String>,
        importChildCounts: [String: ImportChildCounts],
        isShowingAllImports: Bool
    ) -> [SidebarRow] {
        // An import that catalogued nothing is not an import to look at.
        // Filtered before anything else so the "All imports…" total counts
        // the same rows expanding it reveals.
        let importSummaries = importSummaries.filter(\.producedOutputSet)
        guard !importSummaries.isEmpty || runningImport != nil else { return [] }
        let visible = isShowingAllImports ? importSummaries : Array(importSummaries.prefix(recentImportRowLimit))
        var rows: [SidebarRow] = runningImport.map { [runningImportRow($0)] } ?? []
        for summary in visible {
            let counts = importChildCounts[summary.sessionID.rawValue] ?? ImportChildCounts()
            let isExpanded = expandedImportSessionIDs.contains(summary.sessionID.rawValue)
            rows.append(SidebarRow(
                id: "import-\(summary.sessionID.rawValue)",
                title: summary.title,
                countText: countText(summary.assetCount),
                tone: summary.issues.isEmpty ? .neutral : .warning,
                target: .workSession(summary.sessionID, titled: summary.title),
                disclosure: counts.isEmpty ? .none : (isExpanded ? .expanded : .collapsed)
            ))
            guard isExpanded else { continue }
            rows.append(contentsOf: childRows(sessionID: summary.sessionID, counts: counts))
        }
        if importSummaries.count > recentImportRowLimit {
            rows.append(SidebarRow(
                id: allImportsRowID,
                title: "All imports…",
                countText: countText(importSummaries.count),
                target: nil,
                disclosure: isShowingAllImports ? .expanded : .collapsed
            ))
        }
        return rows
    }

    /// The in-flight ingest leads the section: its live narration and unit
    /// count, and deliberately no target — a half-finished import is not a
    /// stable set to select, and `SidebarRow.isSelectable` keys off exactly
    /// that (Jesse 2026-08-08). When the session finishes it is replaced by
    /// the session's own selectable row, in the same leading position.
    private static func runningImportRow(_ activity: AppWorkActivity) -> SidebarRow {
        let trimmedDetail = activity.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return SidebarRow(
            id: "import-running-\(activity.id)",
            title: trimmedDetail.isEmpty ? activity.title : trimmedDetail,
            countText: activity.sidebarCountText(scopeCount: nil),
            tone: activity.sidebarTone,
            target: nil
        )
    }

    /// Children render only with nonzero counts, in a fixed order.
    private static func childRows(sessionID: WorkSessionID, counts: ImportChildCounts) -> [SidebarRow] {
        let ordered: [(ImportChildKind, Int)] = [
            (.stacks, counts.stacks),
            (.skippedFiles, counts.skippedFiles),
            (.previewFailed, counts.previewFailed),
            (.likelyIssues, counts.likelyIssues),
            (.facesFound, counts.facesFound)
        ]
        return ordered.compactMap { child, count in
            guard count > 0 else { return nil }
            return SidebarRow(
                id: "import-\(sessionID.rawValue)-\(child.rawValue)",
                title: child.title,
                countText: countText(count),
                tone: child.isDiagnostic || child == .likelyIssues ? .warning : .neutral,
                target: .importChild(session: sessionID, child: child),
                depth: 1
            )
        }
    }

    private static func row(for assetSet: AssetSet, count: Int?) -> SidebarRow {
        SidebarRow(
            id: "asset-set-\(assetSet.id.rawValue)",
            title: assetSet.name,
            detailText: assetSet.sidebarDetailText,
            countText: count.map(countText),
            tone: assetSet.isDynamic ? .accent : .neutral,
            target: .assetSet(assetSet.id, titled: assetSet.name)
        )
    }

    private static func mergedWorkActivities(
        recentWork: [AppWorkActivity],
        starredWork: [AppWorkActivity]
    ) -> [AppWorkActivity] {
        // AppModel supplies eligibility-filtered caches, so these prefixes are
        // display caps only. Keep the kind guards because this pure presenter
        // is also constructed directly by tests and previews.
        let recentSlice = Array(recentWork.filter { $0.kind != .ingest }.prefix(5))
        let recentIDs = Set(recentSlice.map(\.id))
        return recentSlice + starredWork
            .filter { $0.kind != .ingest && !recentIDs.contains($0.id) }
            .prefix(5)
    }

    private static func folderRows(
        catalogFolders: [CatalogFolder],
        expandedFolderPaths: Set<String>
    ) -> [SidebarRow] {
        FolderTreePresentation.build(from: catalogFolders).flatMap { node in
            folderRows(for: node, depth: 0, expandedFolderPaths: expandedFolderPaths)
        }
    }

    private static func folderRows(
        for node: FolderTreeNode,
        depth: Int,
        expandedFolderPaths: Set<String>
    ) -> [SidebarRow] {
        let isExpanded = expandedFolderPaths.contains(node.fullPath)
        let disclosure: SidebarRowDisclosure = node.hasChildren ? (isExpanded ? .expanded : .collapsed) : .none
        let row = SidebarRow(
            id: "folder-\(node.fullPath)",
            title: node.title,
            detailText: node.fullPath,
            countText: countText(node.assetCount),
            target: .folder(node.fullPath),
            depth: depth,
            disclosure: disclosure
        )
        guard isExpanded else { return [row] }
        return [row] + node.children.flatMap {
            folderRows(for: $0, depth: depth + 1, expandedFolderPaths: expandedFolderPaths)
        }
    }
}
