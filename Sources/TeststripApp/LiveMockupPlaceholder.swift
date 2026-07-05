import SwiftUI

public struct LiveMockupPlaceholder: Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var intendedBehavior: String
    public var currentFallback: String

    public var accessibilityIdentifier: String {
        "live-mockup.\(id)"
    }
}

public extension LiveMockupPlaceholder {
    static let studioLibrary = LiveMockupPlaceholders.studioLibrary
    static let copilotLibrary = LiveMockupPlaceholders.copilotLibrary
    static let timelineLibrary = LiveMockupPlaceholders.timelineLibrary
    static let peopleSidebar = LiveMockupPlaceholders.peopleSidebar
    static let peopleFaceActions = LiveMockupPlaceholders.peopleFaceActions
    static let foldersEmpty = LiveMockupPlaceholders.foldersEmpty
    static let placesMap = LiveMockupPlaceholders.placesMap
    static let topChrome = LiveMockupPlaceholders.topChrome
    static let agenticSearch = LiveMockupPlaceholders.agenticSearch
    static let searchRefine = LiveMockupPlaceholders.searchRefine
    static let smartCollectionsBuilder = LiveMockupPlaceholders.smartCollectionsBuilder
    static let keywordingBatch = LiveMockupPlaceholders.keywordingBatch
    static let exportWorkflow = LiveMockupPlaceholders.exportWorkflow
    static let importPlan = LiveMockupPlaceholders.importPlan
    static let importCompleteSummary = LiveMockupPlaceholders.importCompleteSummary
    static let cullingAssistVerdict = LiveMockupPlaceholders.cullingAssistVerdict
    static let cullingFilmstrip = LiveMockupPlaceholders.cullingFilmstrip
    static let cullingStackCull = LiveMockupPlaceholders.cullingStackCull
    static let focusCompare = LiveMockupPlaceholders.focusCompare
    static let compareSurvey = LiveMockupPlaceholders.compareSurvey
    static let workHistory = LiveMockupPlaceholders.workHistory
}

public enum LiveMockupPlaceholders {
    public static let studioLibrary = LiveMockupPlaceholder(
        id: "library.studio",
        title: "Studio library direction",
        intendedBehavior: "Represent the refined classic pro layout with catalog navigation, adaptive grid, inspector, and quiet agentic affordances.",
        currentFallback: "Main Library route with real catalog/sidebar/grid/inspector behavior and ongoing mockup-parity passes."
    )

    public static let copilotLibrary = LiveMockupPlaceholder(
        id: "library.copilot",
        title: "Copilot library direction",
        intendedBehavior: "Put plain-language search, agentic culling, and background catalog work at the center of the library experience.",
        currentFallback: "Selectable Copilot route aggregates real review queues, local signal coverage, XMP state, and background work; autonomous planning and actions are not built."
    )

    public static let timelineLibrary = LiveMockupPlaceholder(
        id: "library.timeline",
        title: "Timeline library direction",
        intendedBehavior: "Navigate decade-scale catalogs through a year/month/day density ribbon and scrubber.",
        currentFallback: "Catalog-backed capture-day counts, day drill-down, year-density ribbon, focused month/day scrubber, month/year drill-down controls, and scroll-position syncing centers focused chips and sections."
    )

    public static let topChrome = LiveMockupPlaceholder(
        id: "library.top-chrome",
        title: "Library top chrome",
        intendedBehavior: "Unify catalog identity, breadcrumbs, agentic search, view switching, and import actions in the dense Studio header.",
        currentFallback: "In-content header backed by current library state with real catalog identity, breadcrumbs, view switching, search entry, and import actions while native toolbar controls remain available."
    )

    public static let peopleSidebar = LiveMockupPlaceholder(
        id: "sidebar.people",
        title: "People navigation",
        intendedBehavior: "Browse face groups and named people once people recognition and grouping are productized.",
        currentFallback: "Selectable People route with an unnamed face review strip, Apple Vision scan action for visible cached previews, face-review strip affordances backed by real face signals, persisted named people rows when user-confirmed groups exist, and a named-people empty state; automatic clustering and face-level naming remain disabled."
    )

    public static let peopleFaceActions = LiveMockupPlaceholder(
        id: "people.face-actions",
        title: "People face actions",
        intendedBehavior: "Confirm, name, merge, or dismiss face clusters created by local recognition.",
        currentFallback: "Disabled controls inside the placeholder People view."
    )

    public static let foldersEmpty = LiveMockupPlaceholder(
        id: "sidebar.folders-empty",
        title: "Empty folders navigation",
        intendedBehavior: "Show imported/cataloged source folders in the Library sidebar once folder roots exist.",
        currentFallback: "Disabled sidebar row shown only before any folders have been cataloged."
    )

    public static let placesMap = LiveMockupPlaceholder(
        id: "places.map",
        title: "Places map",
        intendedBehavior: "Browse geotagged frames on a map with clusters, reverse-geocoded locations, and region drill-down.",
        currentFallback: "Out of scope for go-to-market; no map route is exposed."
    )

    public static let agenticSearch = LiveMockupPlaceholder(
        id: "search.agentic",
        title: "Agentic search",
        intendedBehavior: "Accept natural-language catalog questions and translate them into searches, sets, or review actions.",
        currentFallback: "Deterministic parsing for known photographer terms plus plain text fallback and explicit filter controls."
    )

    public static let searchRefine = LiveMockupPlaceholder(
        id: "search.refine",
        title: "Search refine rail",
        intendedBehavior: "Show parsed facets, query refinements, and agent-suggested set actions beside search results.",
        currentFallback: "Search view shows a deterministic Teststrip Reads rail from active filter chips, known target rows are actionable, generated refinements can apply concrete catalog rules, related filters are actionable, and existing save/freeze/review workflows appear as suggested actions; broader natural-language planning is not built."
    )

    public static let smartCollectionsBuilder = LiveMockupPlaceholder(
        id: "smart-collections.builder",
        title: "Smart collections builder",
        intendedBehavior: "Build saved dynamic sets with structured rules, natural-language criteria, and previews of matching assets.",
        currentFallback: "Builder saves the current library query as a dynamic saved set, previews loaded matches, offers Add Rule presets for concrete catalog filters, suggestion rows are actionable and derived from review queue counts, and saved sets have delete set confirmation; freeform rule editing and provider-generated suggestions are not built."
    )

    public static let keywordingBatch = LiveMockupPlaceholder(
        id: "keywording.batch",
        title: "Batch keywording",
        intendedBehavior: "Apply Teststrip-suggested keywords, captions, creator, and copyright to a selected batch.",
        currentFallback: "Single-selected metadata controls plus latest-import keyword review, current-scope keyword suggestions, and a selected/visible/current-scope metadata popover write command and shift selected assets through catalog and XMP with all-catalog confirmation; freeform bulk keyword review is not built."
    )

    public static let exportWorkflow = LiveMockupPlaceholder(
        id: "export.workflow",
        title: "Export workflow",
        intendedBehavior: "Export selected photos through presets for sizing, sharpening, color space, metadata, and watermarking.",
        currentFallback: "Out of scope for the no-editing v1; no export route is exposed."
    )

    public static let importPlan = LiveMockupPlaceholder(
        id: "import.plan",
        title: "Import plan",
        intendedBehavior: "Explain copy/catalog/XMP/preview/background work before import starts, including later agentic follow-up work.",
        currentFallback: "Folder and card confirmation sheets show the non-destructive cataloging plan, managed background-work summary, and honest follow-up setup rows for culling, stacks, keyword review, and face review."
    )

    public static let importCompleteSummary = LiveMockupPlaceholder(
        id: "import.complete-summary",
        title: "Import complete summary",
        intendedBehavior: "Show the import-complete payoff surface with imported-set actions, preview status, culling entrypoints, and follow-up workflow suggestions.",
        currentFallback: "Expanded post-import panel backed by the completed import work session and output set, with culling, stack-cull, compare, and keyword actions live while face follow-ups stay disabled and annotated."
    )

    public static let cullingAssistVerdict = LiveMockupPlaceholder(
        id: "culling.assist-verdict",
        title: "Culling assist verdict",
        intendedBehavior: "Show agentic keeper/reject guidance, rationale, and confidence for the current frame or burst.",
        currentFallback: "Selected-frame verdict uses persisted evaluation signals when present, but richer rationale and burst-level guidance are not built."
    )

    public static let cullingFilmstrip = LiveMockupPlaceholder(
        id: "culling.filmstrip",
        title: "Culling filmstrip",
        intendedBehavior: "Provide a bottom filmstrip for fast neighboring-frame navigation during loupe culling.",
        currentFallback: "Keyboard and selected-frame navigation through the loaded asset set."
    )

    public static let cullingStackCull = LiveMockupPlaceholder(
        id: "culling.stack-cull",
        title: "Stack cull",
        intendedBehavior: "Group bursts or near-duplicates into stacks and cull the strongest candidate within each stack.",
        currentFallback: "Loupe culling can keep a selected frame from persisted import stack sets or same-folder capture-time fallback stacks through the Keep frame action, reject alternates, and refresh persisted culling session progress; Keep top and Keep all are visible disabled placeholders, and real similarity and near-duplicate grouping are still pending."
    )

    public static let focusCompare = LiveMockupPlaceholder(
        id: "compare.focus",
        title: "Focus compare",
        intendedBehavior: "Line up close contenders and use sharpness, eye state, exposure, and frame signals to break ties.",
        currentFallback: "Survey Compare shows persisted focus, motion blur, exposure, and face-quality signals for visible contenders; eye-state and richer frame rationale depend on future providers."
    )

    public static let compareSurvey = LiveMockupPlaceholder(
        id: "compare.survey",
        title: "Survey compare",
        intendedBehavior: "Show a survey-style comparison surface with primary candidate, alternates, and decision affordances.",
        currentFallback: "Four-column 4x2 survey grid over up to eight frames from persisted culling stack sets when active, loaded-scope candidate stacks otherwise, or the current selected neighborhood with heuristic recommendation text."
    )

    public static let workHistory = LiveMockupPlaceholder(
        id: "work.history",
        title: "Work history",
        intendedBehavior: "Navigate recent and starred culling, collecting, searching, sorting, and editing sessions.",
        currentFallback: "Recent and starred work-session sidebar rows are catalog-backed when activities exist; richer history search and editing are not built."
    )

    public static let all: [LiveMockupPlaceholder] = [
        studioLibrary,
        copilotLibrary,
        timelineLibrary,
        topChrome,
        peopleSidebar,
        peopleFaceActions,
        foldersEmpty,
        placesMap,
        agenticSearch,
        searchRefine,
        smartCollectionsBuilder,
        keywordingBatch,
        exportWorkflow,
        importPlan,
        importCompleteSummary,
        cullingAssistVerdict,
        cullingFilmstrip,
        cullingStackCull,
        focusCompare,
        compareSurvey,
        workHistory
    ]
}

public enum LiveMockupSurfaceStatus: String, Equatable, Sendable {
    case shipped
    case partial
    case liveMockup
    case deferred
}

public struct LiveMockupDesignSurface: Equatable, Identifiable, Sendable {
    public var designID: String
    public var title: String
    public var status: LiveMockupSurfaceStatus
    public var placeholder: LiveMockupPlaceholder?
    public var currentImplementation: String

    public var id: String {
        designID
    }
}

public enum LiveMockupDesignSurfaces {
    public static let all: [LiveMockupDesignSurface] = [
        LiveMockupDesignSurface(
            designID: "1a",
            title: "Studio",
            status: .partial,
            placeholder: .studioLibrary,
            currentImplementation: "Main Library route has real catalog navigation, adaptive true-aspect grid cells, top chrome, and inspector passes; remaining work is deeper visual parity and density tuning."
        ),
        LiveMockupDesignSurface(
            designID: "1b",
            title: "Copilot",
            status: .partial,
            placeholder: .copilotLibrary,
            currentImplementation: "Copilot route aggregates real review queues, local signal coverage, XMP state, and background work beside deterministic search parsing and explicit filters; natural-language planning and autonomous actions are not built."
        ),
        LiveMockupDesignSurface(
            designID: "1c",
            title: "Timeline",
            status: .partial,
            placeholder: .timelineLibrary,
            currentImplementation: "Timeline route uses catalog-backed capture-day counts, a year-density ribbon, focused month/day scrubber, day drill-down, month/year drill-down into existing date predicates, and scroll-position syncing centers focused chips and sections."
        ),
        LiveMockupDesignSurface(
            designID: "2a",
            title: "Rapid cull",
            status: .partial,
            placeholder: .cullingAssistVerdict,
            currentImplementation: "Loupe-first culling has keyboard pick/reject/rating/labels, Space advances, progress, filmstrip, and selected-frame signal verdicts; burst-level agentic rationale remains pending."
        ),
        LiveMockupDesignSurface(
            designID: "2b",
            title: "Survey and compare",
            status: .partial,
            placeholder: .compareSurvey,
            currentImplementation: "Compare shows up to eight frames in a four-column survey grid with selected primary first, persisted culling stack membership when active, loaded-scope candidate stacks when adjacent same-folder capture times are available, alternates, metadata-backed badges, a focus metric lane, and a current-compare-set action to keep the primary and reject visible alternates; richer stack mutations are not built."
        ),
        LiveMockupDesignSurface(
            designID: "3a",
            title: "Stack cull",
            status: .partial,
            placeholder: .cullingStackCull,
            currentImplementation: "Current app culls arbitrary sets, compare neighborhoods, persisted import stack sets, and loaded-scope same-folder capture-time stacks with a keep-selected/reject-alternates action; Return accepts the selected stack frame when a persisted or loaded stack is active, persisted stack culling sessions refresh progress and complete from decided stack flags, and automatic burst/near-duplicate similarity grouping is not built."
        ),
        LiveMockupDesignSurface(
            designID: "3b",
            title: "Focus compare",
            status: .partial,
            placeholder: .focusCompare,
            currentImplementation: "Compare has a persisted focus/motion/exposure/face-quality lane and cached-preview evaluation action; eye-state and richer frame rationale depend on future providers."
        ),
        LiveMockupDesignSurface(
            designID: "4a",
            title: "Import",
            status: .partial,
            placeholder: .importPlan,
            currentImplementation: "Folder/card import confirmation explains non-destructive cataloging, XMP, previews, managed background work, and follow-up setup for imported-set culling, likely stacks, keyword review, and face review; geo/map follow-up and automatic naming are not run during import."
        ),
        LiveMockupDesignSurface(
            designID: "4b",
            title: "Import complete",
            status: .partial,
            placeholder: .importCompleteSummary,
            currentImplementation: "Expanded import-complete panel exposes imported count, preview status, Open, culling, stack-cull, compare, and keyword actions; face naming remains a disabled placeholder."
        ),
        LiveMockupDesignSurface(
            designID: "5a",
            title: "People",
            status: .partial,
            placeholder: .peopleSidebar,
            currentImplementation: "People route is selectable and shows an unnamed face review strip, Apple Vision scan action for visible cached previews, face-review strip affordances, catalog-backed review entrypoints, persisted named people rows when user-confirmed groups exist, and a named-people empty state; automatic clustering and face-level naming remain disabled."
        ),
        LiveMockupDesignSurface(
            designID: "5b",
            title: "Places",
            status: .deferred,
            placeholder: .placesMap,
            currentImplementation: "Out of scope for go-to-market; no map, clustering, or reverse-geocode route is exposed."
        ),
        LiveMockupDesignSurface(
            designID: "5c",
            title: "Search",
            status: .partial,
            placeholder: .agenticSearch,
            currentImplementation: "Search route preserves catalog query/filter state, parsed chips, saved-set counts, results grid, deterministic generated refinements, related filters, and suggested actions for existing save/freeze/review workflows; broader natural-language planning is not built."
        ),
        LiveMockupDesignSurface(
            designID: "5d",
            title: "Smart collections",
            status: .partial,
            placeholder: .smartCollectionsBuilder,
            currentImplementation: "Builder saves the current dynamic query with parsed rule presentation, loaded-result preview, Add Rule presets for concrete filters, suggestion rows are actionable and derived from review queue counts, and saved-set delete set confirmation; freeform rule editing and provider-generated suggestions are not built."
        ),
        LiveMockupDesignSurface(
            designID: "5e",
            title: "Keywording",
            status: .partial,
            placeholder: .keywordingBatch,
            currentImplementation: "Selected asset metadata controls edit keywords, caption, creator, and copyright with XMP writeback, plus single-asset suggestions, latest-import keyword review, current-scope keyword suggestions, and a selected/visible/current-scope metadata popover from object evaluation labels that writes command and shift selected assets with all-catalog confirmation; freeform bulk keyword review is not built."
        ),
        LiveMockupDesignSurface(
            designID: "5f",
            title: "Export",
            status: .deferred,
            placeholder: .exportWorkflow,
            currentImplementation: "Out of scope for the no-editing v1; no export preset/settings route is exposed."
        )
    ]
}

private struct LiveMockupPlaceholderModifier: ViewModifier {
    var placeholder: LiveMockupPlaceholder?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let placeholder {
            content.accessibilityIdentifier(placeholder.accessibilityIdentifier)
        } else {
            content
        }
    }
}

extension View {
    func liveMockupPlaceholder(_ placeholder: LiveMockupPlaceholder?) -> some View {
        modifier(LiveMockupPlaceholderModifier(placeholder: placeholder))
    }
}
