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
    static let agenticSearch = LiveMockupPlaceholders.agenticSearch
}

public enum LiveMockupPlaceholders {
    public static let peopleSidebar = LiveMockupPlaceholder(
        id: "sidebar.people",
        title: "People sidebar",
        intendedBehavior: "Browse face groups and named people once people recognition and grouping are productized.",
        currentFallback: "Disabled sidebar row; face-related signals can appear under AI after evaluation."
    )

    public static let agenticSearch = LiveMockupPlaceholder(
        id: "search.agentic",
        title: "Agentic search",
        intendedBehavior: "Accept natural-language catalog questions and translate them into searches, sets, or review actions.",
        currentFallback: "Plain catalog text search plus explicit filter controls."
    )

    public static let all: [LiveMockupPlaceholder] = [
        peopleSidebar,
        agenticSearch
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
