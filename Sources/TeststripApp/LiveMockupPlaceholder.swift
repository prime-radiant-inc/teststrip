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
    static let agenticSearch = LiveMockupPlaceholders.agenticSearch
    static let importCompleteSummary = LiveMockupPlaceholders.importCompleteSummary
    static let workHistory = LiveMockupPlaceholders.workHistory
}

public enum LiveMockupPlaceholders {
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

    public static let importCompleteSummary = LiveMockupPlaceholder(
        id: "import.complete-summary",
        title: "Import complete summary",
        intendedBehavior: "Show the import-complete payoff surface with imported-set actions, preview status, culling entrypoints, and follow-up workflow suggestions.",
        currentFallback: "Compact post-import banner backed by the completed import work session and output set."
    )

    public static let workHistory = LiveMockupPlaceholder(
        id: "work.history",
        title: "Work history",
        intendedBehavior: "Navigate recent and starred culling, collecting, searching, sorting, and editing sessions.",
        currentFallback: "Disabled sidebar rows until real work activities have been recorded."
    )

    public static let all: [LiveMockupPlaceholder] = [
        peopleSidebar,
        peopleFaceActions,
        agenticSearch,
        importCompleteSummary,
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
