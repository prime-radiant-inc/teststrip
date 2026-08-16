import SwiftUI
import TeststripCore

/// How you are looking at the selected source. Six lenses, switched by one
/// toolbar control and ⌘1–⌘6 in the same order. This replaces `Workspace`:
/// there is no Cull|Library split any more, only a lens over a source.
///
/// Compare, A/B Compare, and the cull grid are deliberately NOT lenses — they
/// stay transient sub-modes inside the Cull lens, reached by g/c/b.
public enum LibraryLens: String, CaseIterable, Codable, Sendable {
    case cull
    case grid
    case loupe
    case timeline
    case map
    case people

    /// Display name shared by the toolbar switcher and the View menu so the
    /// two never drift out of sync.
    public var title: String {
        switch self {
        case .cull: return "Cull"
        case .grid: return "Grid"
        case .loupe: return "Loupe"
        case .timeline: return "Timeline"
        case .map: return "Map"
        case .people: return "People"
        }
    }

    /// ⌘1–⌘6 in declaration order. Modifier-bearing on purpose: a bare menu
    /// key equivalent fires through AppKit's performKeyEquivalent path
    /// independently of the in-view NSEvent monitors, so one keypress
    /// dispatches twice (run-cull-iter2 cull-003/005/007).
    public var keyEquivalent: KeyEquivalent {
        switch self {
        case .cull: return "1"
        case .grid: return "2"
        case .loupe: return "3"
        case .timeline: return "4"
        case .map: return "5"
        case .people: return "6"
        }
    }

    /// The route a lens lands on when it has no remembered sub-mode.
    public var defaultViewMode: LibraryViewMode {
        switch self {
        case .cull: return .loupe
        case .grid: return .grid
        case .loupe: return .libraryLoupe
        case .timeline: return .timeline
        case .map: return .map
        case .people: return .people
        }
    }
}

public extension LibraryViewMode {
    /// Which lens this route belongs to. The four cull sub-modes all belong to
    /// the Cull lens, which is what keeps g/c/b transient rather than
    /// promoting them to top-level lenses.
    var lens: LibraryLens {
        switch self {
        case .loupe, .compare, .abCompare, .cullGrid:
            return .cull
        case .grid:
            return .grid
        case .libraryLoupe:
            return .loupe
        case .timeline:
            return .timeline
        case .map:
            return .map
        case .people:
            return .people
        }
    }
}

/// Whether a lens can be entered over a given source, and why not — rendered
/// as a disabled segment with the reason on hover.
public struct LensAvailability: Equatable, Sendable {
    public var lens: LibraryLens
    public var isEnabled: Bool
    public var disabledReason: String?

    public init(lens: LibraryLens, isEnabled: Bool, disabledReason: String? = nil) {
        self.lens = lens
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }
}

public enum LensRules {
    /// Cull disables on diagnostic sources — nothing there is cullable, and
    /// skipped files aren't even in the catalog — and on empty sources.
    /// Everything else works everywhere.
    public static func availability(
        for lens: LibraryLens,
        sourceIsDiagnostic: Bool,
        sourceAssetCount: Int
    ) -> LensAvailability {
        guard lens == .cull else {
            return LensAvailability(lens: lens, isEnabled: true)
        }
        if sourceIsDiagnostic {
            return LensAvailability(lens: lens, isEnabled: false, disabledReason: "Nothing here is cullable")
        }
        if sourceAssetCount == 0 {
            return LensAvailability(lens: lens, isEnabled: false, disabledReason: "No photos to cull")
        }
        return LensAvailability(lens: lens, isEnabled: true)
    }

    public static func availabilities(
        sourceIsDiagnostic: Bool,
        sourceAssetCount: Int
    ) -> [LensAvailability] {
        LibraryLens.allCases.map {
            availability(for: $0, sourceIsDiagnostic: sourceIsDiagnostic, sourceAssetCount: sourceAssetCount)
        }
    }

    /// Selecting a source the current lens disables on falls back to Grid.
    public static func resolvedLens(
        _ lens: LibraryLens,
        sourceIsDiagnostic: Bool,
        sourceAssetCount: Int
    ) -> LibraryLens {
        availability(for: lens, sourceIsDiagnostic: sourceIsDiagnostic, sourceAssetCount: sourceAssetCount).isEnabled
            ? lens
            : .grid
    }
}
