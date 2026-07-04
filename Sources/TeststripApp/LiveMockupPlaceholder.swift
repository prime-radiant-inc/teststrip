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
        currentFallback: "Agentic search copy currently maps to explicit catalog search, filters, review queues, and persisted evaluation signals."
    )

    public static let timelineLibrary = LiveMockupPlaceholder(
        id: "library.timeline",
        title: "Timeline library direction",
        intendedBehavior: "Navigate decade-scale catalogs through a year/month/day density ribbon and scrubber.",
        currentFallback: "Catalog-backed capture-day counts, day drill-down, and year-density ribbon exist; month/day scrubber remains pending."
    )

    public static let topChrome = LiveMockupPlaceholder(
        id: "library.top-chrome",
        title: "Library top chrome",
        intendedBehavior: "Unify catalog identity, breadcrumbs, agentic search, view switching, and import actions in the dense Studio header.",
        currentFallback: "In-content header backed by current library state while native toolbar controls remain available; catalog identity is static placeholder copy."
    )

    public static let peopleSidebar = LiveMockupPlaceholder(
        id: "sidebar.people",
        title: "People navigation",
        intendedBehavior: "Browse face groups and named people once people recognition and grouping are productized.",
        currentFallback: "Selectable live mockup that shows real face-signal coverage but no named identities until clustering and naming ship."
    )

    public static let peopleFaceActions = LiveMockupPlaceholder(
        id: "people.face-actions",
        title: "People face actions",
        intendedBehavior: "Confirm, name, merge, or dismiss face clusters created by local recognition.",
        currentFallback: "Disabled controls inside the placeholder People view."
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
        currentFallback: "Search view now shows a deterministic Teststrip Reads rail from active filter chips; suggested refinements and agent set actions are not built."
    )

    public static let smartCollectionsBuilder = LiveMockupPlaceholder(
        id: "smart-collections.builder",
        title: "Smart collections builder",
        intendedBehavior: "Build saved dynamic sets with structured rules, natural-language criteria, and previews of matching assets.",
        currentFallback: "Save the current library query as a dynamic saved set."
    )

    public static let keywordingBatch = LiveMockupPlaceholder(
        id: "keywording.batch",
        title: "Batch keywording",
        intendedBehavior: "Apply Teststrip-suggested keywords, captions, creator, and copyright to a selected batch.",
        currentFallback: "Single-selected asset keyword/caption/creator/copyright controls write through catalog and XMP; batch keywording surface is not built."
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
        currentFallback: "Folder and card confirmation sheets show the non-destructive cataloging plan and managed background-work summary."
    )

    public static let importCompleteSummary = LiveMockupPlaceholder(
        id: "import.complete-summary",
        title: "Import complete summary",
        intendedBehavior: "Show the import-complete payoff surface with imported-set actions, preview status, culling entrypoints, and follow-up workflow suggestions.",
        currentFallback: "Expanded post-import panel backed by the completed import work session and output set, with unbuilt stack/face/keyword follow-ups disabled and annotated."
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
        currentFallback: "Manual compare and ordinary culling over the current asset set."
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
        currentFallback: "Adaptive compare grid over the current selected neighborhood with heuristic recommendation text, not real stack membership."
    )

    public static let workHistory = LiveMockupPlaceholder(
        id: "work.history",
        title: "Work history",
        intendedBehavior: "Navigate recent and starred culling, collecting, searching, sorting, and editing sessions.",
        currentFallback: "Disabled sidebar rows until real work activities have been recorded."
    )

    public static let all: [LiveMockupPlaceholder] = [
        studioLibrary,
        copilotLibrary,
        timelineLibrary,
        topChrome,
        peopleSidebar,
        peopleFaceActions,
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
            currentImplementation: "Agentic search copy is wired to deterministic catalog query parsing, a Teststrip Reads refine rail, explicit filters, review queues, and visible evaluation signals; natural-language planning and autonomous actions are not built."
        ),
        LiveMockupDesignSurface(
            designID: "1c",
            title: "Timeline",
            status: .partial,
            placeholder: .timelineLibrary,
            currentImplementation: "Timeline route uses catalog-backed capture-day counts, a year-density ribbon, and day drill-down into existing date predicates; month/day scrubber remains pending."
        ),
        LiveMockupDesignSurface(
            designID: "2a",
            title: "Rapid cull",
            status: .partial,
            placeholder: .cullingAssistVerdict,
            currentImplementation: "Loupe-first culling has keyboard pick/reject/rating/labels, progress, filmstrip, and selected-frame signal verdicts; burst-level agentic rationale remains pending."
        ),
        LiveMockupDesignSurface(
            designID: "2b",
            title: "Survey and compare",
            status: .partial,
            placeholder: .compareSurvey,
            currentImplementation: "Compare shows selected primary first, alternates, metadata-backed badges, a focus metric lane, and a current-compare-set action to keep the primary and reject visible alternates; real stack membership and richer stack mutations are not built."
        ),
        LiveMockupDesignSurface(
            designID: "3a",
            title: "Stack cull",
            status: .liveMockup,
            placeholder: .cullingStackCull,
            currentImplementation: "Current app culls arbitrary sets and compare neighborhoods; automatic burst/near-duplicate stack grouping is not built."
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
            currentImplementation: "Folder/card import confirmation explains non-destructive cataloging, XMP, previews, and managed background work; automatic stack/cull/keyword/face follow-up is not run during import."
        ),
        LiveMockupDesignSurface(
            designID: "4b",
            title: "Import complete",
            status: .partial,
            placeholder: .importCompleteSummary,
            currentImplementation: "Expanded import-complete panel exposes imported count, preview status, Open, Cull, and dismiss; stack grouping, face naming, and batch keyword suggestions remain disabled placeholders."
        ),
        LiveMockupDesignSurface(
            designID: "5a",
            title: "People",
            status: .liveMockup,
            placeholder: .peopleSidebar,
            currentImplementation: "People route is selectable and shows catalog face-signal coverage, but real face clustering, identity names, suggestions, and naming workflows are pending."
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
            currentImplementation: "Search route preserves catalog query/filter state, parsed chips, saved-set counts, and results grid; suggested refinements and broader natural-language planning are not built."
        ),
        LiveMockupDesignSurface(
            designID: "5d",
            title: "Smart collections",
            status: .partial,
            placeholder: .smartCollectionsBuilder,
            currentImplementation: "Builder saves the current dynamic query with parsed rule presentation and loaded-result preview; editable arbitrary rule rows and real suggestions are not built."
        ),
        LiveMockupDesignSurface(
            designID: "5e",
            title: "Keywording",
            status: .partial,
            placeholder: .keywordingBatch,
            currentImplementation: "Selected asset metadata controls edit keywords, caption, creator, and copyright with XMP writeback, plus accepting single-asset suggested keywords from object evaluation labels; batch keywording is not built."
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
