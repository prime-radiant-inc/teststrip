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
    static let peopleSidebar = LiveMockupPlaceholders.peopleSidebar
    static let peopleFaceActions = LiveMockupPlaceholders.peopleFaceActions
    static let topChrome = LiveMockupPlaceholders.topChrome
    static let agenticSearch = LiveMockupPlaceholders.agenticSearch
    static let searchRefine = LiveMockupPlaceholders.searchRefine
    static let smartCollectionsBuilder = LiveMockupPlaceholders.smartCollectionsBuilder
    static let importCompleteSummary = LiveMockupPlaceholders.importCompleteSummary
    static let cullingAssistVerdict = LiveMockupPlaceholders.cullingAssistVerdict
    static let cullingFilmstrip = LiveMockupPlaceholders.cullingFilmstrip
    static let cullingStackCull = LiveMockupPlaceholders.cullingStackCull
    static let compareSurvey = LiveMockupPlaceholders.compareSurvey
    static let workHistory = LiveMockupPlaceholders.workHistory
}

public enum LiveMockupPlaceholders {
    public static let topChrome = LiveMockupPlaceholder(
        id: "library.top-chrome",
        title: "Library top chrome",
        intendedBehavior: "Unify catalog identity, breadcrumbs, agentic search, view switching, and import actions in the dense Studio header.",
        currentFallback: "In-content header backed by current library state while native toolbar controls remain available."
    )

    public static let peopleSidebar = LiveMockupPlaceholder(
        id: "sidebar.people",
        title: "People navigation",
        intendedBehavior: "Browse face groups and named people once people recognition and grouping are productized.",
        currentFallback: "Selectable live mockup with placeholder face groups and people counts."
    )

    public static let peopleFaceActions = LiveMockupPlaceholder(
        id: "people.face-actions",
        title: "People face actions",
        intendedBehavior: "Confirm, name, merge, or dismiss face clusters created by local recognition.",
        currentFallback: "Disabled controls inside the placeholder People view."
    )

    public static let agenticSearch = LiveMockupPlaceholder(
        id: "search.agentic",
        title: "Agentic search",
        intendedBehavior: "Accept natural-language catalog questions and translate them into searches, sets, or review actions.",
        currentFallback: "Plain catalog text search plus explicit filter controls."
    )

    public static let searchRefine = LiveMockupPlaceholder(
        id: "search.refine",
        title: "Search refine rail",
        intendedBehavior: "Show parsed facets, query refinements, and agent-suggested set actions beside search results.",
        currentFallback: "Explicit filter controls and active filter chips in the library toolbar."
    )

    public static let smartCollectionsBuilder = LiveMockupPlaceholder(
        id: "smart-collections.builder",
        title: "Smart collections builder",
        intendedBehavior: "Build saved dynamic sets with structured rules, natural-language criteria, and previews of matching assets.",
        currentFallback: "Save the current library query as a dynamic saved set."
    )

    public static let importCompleteSummary = LiveMockupPlaceholder(
        id: "import.complete-summary",
        title: "Import complete summary",
        intendedBehavior: "Show the import-complete payoff surface with imported-set actions, preview status, culling entrypoints, and follow-up workflow suggestions.",
        currentFallback: "Compact post-import banner backed by the completed import work session and output set."
    )

    public static let cullingAssistVerdict = LiveMockupPlaceholder(
        id: "culling.assist-verdict",
        title: "Culling assist verdict",
        intendedBehavior: "Show agentic keeper/reject guidance, rationale, and confidence for the current frame or burst.",
        currentFallback: "Static Assist indicator while real culling evaluation signals are still being productized."
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

    public static let compareSurvey = LiveMockupPlaceholder(
        id: "compare.survey",
        title: "Survey compare",
        intendedBehavior: "Show a survey-style comparison surface with primary candidate, alternates, and decision affordances.",
        currentFallback: "Adaptive compare grid over the current selected neighborhood."
    )

    public static let workHistory = LiveMockupPlaceholder(
        id: "work.history",
        title: "Work history",
        intendedBehavior: "Navigate recent and starred culling, collecting, searching, sorting, and editing sessions.",
        currentFallback: "Disabled sidebar rows until real work activities have been recorded."
    )

    public static let all: [LiveMockupPlaceholder] = [
        topChrome,
        peopleSidebar,
        peopleFaceActions,
        agenticSearch,
        searchRefine,
        smartCollectionsBuilder,
        importCompleteSummary,
        cullingAssistVerdict,
        cullingFilmstrip,
        cullingStackCull,
        compareSurvey,
        workHistory
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
