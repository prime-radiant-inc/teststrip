import Foundation
import Observation
import SwiftUI
import TeststripCore

public enum LibraryViewMode: String, CaseIterable, Sendable {
    case grid
    case loupe
    case libraryLoupe
    case compare
    case abCompare
    case timeline
    case map
    case people
    /// The asset grid scoped to the active cull session (Task 18) — same grid
    /// rendering as `.grid`, but a distinct case so it stays in the `.cull`
    /// workspace (autopilot badges, cull sidebar, cull session scope) instead
    /// of jumping to Library the way plain `.grid` does.
    case cullGrid
}

extension LibraryViewMode: Codable {
    // Search used to be its own route (`.search`); it's now just the Library
    // grid with a query in the token field (Task 9). Copilot/Review was its
    // own route (`.copilot`) until the Cull sidebar's source picker absorbed
    // it (Task 13). A persisted session from before those migrations decodes
    // its stored "search"/"copilot" rawValue as `.grid` instead of failing
    // the whole `SessionRestoreState` decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "search" || rawValue == "copilot" {
            self = .grid
            return
        }
        guard let mode = LibraryViewMode(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown LibraryViewMode rawValue: \(rawValue)"
            )
        }
        self = mode
    }
}

/// The two top-level workspaces the UI is organized around; each
/// `LibraryViewMode` belongs to exactly one. People is *not* a workspace — it
/// is a Library sub-view (peer of Grid/Loupe/Timeline/Map), so it lives under
/// `.library` and is reached from the sub-view toggle, not the ⌘1/⌘2 switcher.
public enum Workspace: String, CaseIterable, Sendable {
    case cull
    case library

    /// The sub-view shown when a workspace is selected for the first time.
    var defaultSubView: LibraryViewMode {
        switch self {
        case .cull: return .loupe
        case .library: return .grid
        }
    }

    /// Display name shared by the toolbar switcher and the View menu.
    public var title: String {
        switch self {
        case .cull: return "Cull"
        case .library: return "Library"
        }
    }

    /// ⌘1/2, shared by the toolbar switcher and the View menu so the two
    /// never drift out of sync.
    public var keyEquivalent: KeyEquivalent {
        switch self {
        case .cull: return "1"
        case .library: return "2"
        }
    }
}

extension LibraryViewMode {
    public var workspace: Workspace {
        switch self {
        case .loupe, .compare, .abCompare, .cullGrid:
            return .cull
        case .grid, .timeline, .map, .libraryLoupe, .people:
            return .library
        }
    }
}

/// Which chrome `LoupeView` shows: the culling loupe (`.loupe`) gets the full
/// HUD/stack rail/pick-reject/assist toolset; the Library loupe (`.libraryLoupe`)
/// is plain navigation plus the EXIF metadata overlay only.
public struct LoupePresentation: Equatable, Sendable {
    public var showsCullChrome: Bool

    public init(showsCullChrome: Bool) {
        self.showsCullChrome = showsCullChrome
    }

    public init(mode: LibraryViewMode) {
        self.showsCullChrome = mode == .loupe
    }
}

public enum CompareGroupKind: Equatable, Sendable {
    case nearbyFrames
    case candidateStack
}

public enum CullingCommand: Equatable, Sendable {
    case rating(Int)
    case colorLabel(ColorLabel?)
    case pick
    case reject
    case clearFlag
}

public struct CullingProgressSummary: Equatable, Sendable {
    public var selectedPosition: Int?
    public var positionText: String?
    public var pickCount: Int
    public var rejectCount: Int
    public var totalCount: Int

    public var reviewedCount: Int {
        pickCount + rejectCount
    }

    public init(selectedPosition: Int?, positionText: String?, pickCount: Int, rejectCount: Int, totalCount: Int) {
        self.selectedPosition = selectedPosition
        self.positionText = positionText
        self.pickCount = pickCount
        self.rejectCount = rejectCount
        self.totalCount = totalCount
    }
}

public struct CullingSessionCompletionSummary: Equatable, Identifiable, Sendable {
    public var sessionID: WorkSessionID
    public var title: String
    public var pickCount: Int
    public var rejectCount: Int
    public var picksSetID: AssetSetID?
    /// Frames from the same import that never joined a multi-frame stack, so
    /// stack culling never asked about them. Empty for sessions that aren't a
    /// stack cull, or that have none left undecided.
    public var remainingSingleAssetIDs: [AssetID] = []

    public var id: String { sessionID.rawValue }

    public var remainingSingleCount: Int { remainingSingleAssetIDs.count }

    public var detailText: String {
        let picksText = "\(pickCount) \(pickCount == 1 ? "pick" : "picks")"
        let rejectsText = "\(rejectCount) \(rejectCount == 1 ? "reject" : "rejects")"
        return "\(picksText) · \(rejectsText) — \(title)"
    }
}

public struct CullingStackScope: Equatable, Sendable {
    public var assetIDs: [AssetID]
    public var stackIndex: Int?
    public var stackCount: Int?
    public var rationaleText: String?

    public init(
        assetIDs: [AssetID],
        stackIndex: Int? = nil,
        stackCount: Int? = nil,
        rationaleText: String? = nil
    ) {
        self.assetIDs = assetIDs
        self.stackIndex = stackIndex
        self.stackCount = stackCount
        self.rationaleText = rationaleText
    }
}

public struct CullingStackListEntry: Equatable, Identifiable, Sendable {
    public var setID: AssetSetID
    public var title: String
    public var frameCountText: String
    public var leadAssetID: AssetID
    public var isDecided: Bool
    public var isSelected: Bool

    public var id: String { setID.rawValue }
}

public enum CullingShortcut: Equatable, Sendable {
    case previousPhoto
    case nextPhoto
    case previousStack
    case nextStack
    /// ↑/↓ within-stack navigation (cull-stack-rail): moves the selection to
    /// the next/previous frame in the current stack, never crossing into a
    /// neighboring stack. See `AppModel.selectNextCandidateInStack()`/
    /// `selectPreviousCandidateInStack()`.
    case previousCandidateInStack
    case nextCandidateInStack
    case rating(Int)
    case colorLabel(ColorLabel?)
    case pick
    case reject
    case clearFlag
    case promoteAndRejectSiblings
    case toggleZoom
    case zoomToNearestFace
    case cycleExifOverlay
    case showKeyMap
    case cycleScope
    case showCullGrid
    case showCompare
    case showABCompare
    /// Esc in `.compare`/`.abCompare` (item 1's modal-trap fix): decoded
    /// directly by CullingKeyCaptureNSView, mode-gated there rather than
    /// through `init(key:)` — see that view for why `.loupe` is excluded.
    case exitCullSubView
    /// A/B Compare's keyboard verdicts (item 2): recognized only by the
    /// culling key-capture monitor — the Culling menu and `?` overlay list
    /// "," and "." for discoverability, but (like every bare culling key)
    /// carry no actual `.keyboardShortcut` binding, so there's no
    /// double-dispatch risk (see `CullingCommandMenuItem.menuDisplayTitle`).
    case keepAOverB
    case keepBOverA
    /// PgUp/PgDn while the ? key-map overlay is visible (item 3); a no-op
    /// otherwise. Monitor-only — decoded directly from the raw keycode.
    case keyMapPageUp
    case keyMapPageDown

    public init?(key: CullingShortcutKey) {
        switch key {
        case .leftArrow:
            self = .previousStack
        case .rightArrow:
            self = .nextStack
        case .upArrow:
            self = .previousCandidateInStack
        case .downArrow:
            self = .nextCandidateInStack
        case .returnKey:
            self = .promoteAndRejectSiblings
        // Shift-Z (exact-case match, checked before the lowercased switch
        // below) is a distinct shortcut from plain "z" toggle-zoom.
        case .character("Z"):
            self = .zoomToNearestFace
        case .character("?"):
            self = .showKeyMap
        case .character(let character):
            switch character.lowercased() {
            case " ": self = .nextPhoto
            case "0": self = .rating(0)
            case "1": self = .rating(1)
            case "2": self = .rating(2)
            case "3": self = .rating(3)
            case "4": self = .rating(4)
            case "5": self = .rating(5)
            case "6": self = .colorLabel(.red)
            case "7": self = .colorLabel(.yellow)
            case "8": self = .colorLabel(.green)
            case "9": self = .colorLabel(.blue)
            case "v": self = .colorLabel(.purple)
            case "-": self = .colorLabel(nil)
            case "p": self = .pick
            case "x": self = .reject
            case "u": self = .clearFlag
            case "z": self = .toggleZoom
            case "i": self = .cycleExifOverlay
            case "s": self = .cycleScope
            case "g": self = .showCullGrid
            case "c": self = .showCompare
            case "b": self = .showABCompare
            case ",": self = .keepAOverB
            case ".": self = .keepBOverA
            default: return nil
            }
        }
    }
}

/// The subset of in-progress frames the loupe/filmstrip/grid navigate
/// through while culling. Cycled with the `s` shortcut; `.all` disables
/// filtering.
public enum CullScope: String, CaseIterable, Equatable, Sendable {
    case unrated
    case picks
    case rejects
    case all

    public func next() -> CullScope {
        let cases = Self.allCases
        guard let index = cases.firstIndex(of: self) else { return .unrated }
        return cases[(index + 1) % cases.count]
    }

    /// Full user-facing name for the scope-change toast ("Scope: Unrated
    /// only"); the HUD chip uses the shorter `label`.
    public var displayName: String {
        switch self {
        case .unrated: return "Unrated only"
        case .picks: return "Picks only"
        case .rejects: return "Rejects only"
        case .all: return "All frames"
        }
    }

    public func matches(_ flag: PickFlag?) -> Bool {
        switch self {
        case .unrated: return flag == nil
        case .picks: return flag == .pick
        case .rejects: return flag == .reject
        case .all: return true
        }
    }

    public var label: String {
        switch self {
        case .unrated: return "Unrated"
        case .picks: return "Picks"
        case .rejects: return "Rejects"
        case .all: return "All"
        }
    }
}

/// Pure ordering helpers for `CullScope` filtering, kept free of `AppModel`
/// state so cycle/advance semantics are directly testable.
public enum CullScopeOrdering {
    public static func filteredAssetIDs(_ assets: [Asset], scope: CullScope) -> [AssetID] {
        assets.filter { scope.matches($0.metadata.flag) }.map(\.id)
    }

    public static func filteredAssets(_ assets: [Asset], scope: CullScope) -> [Asset] {
        assets.filter { scope.matches($0.metadata.flag) }
    }

    /// The frame to select after the scope changes: the current frame if it
    /// still matches, otherwise the nearest matching frame (checking forward
    /// and backward from the current position in lockstep), otherwise nil.
    public static func selectionAfterScopeChange(
        assets: [Asset],
        scope: CullScope,
        currentSelection: AssetID?
    ) -> AssetID? {
        if let currentSelection,
           let currentAsset = assets.first(where: { $0.id == currentSelection }),
           scope.matches(currentAsset.metadata.flag) {
            return currentSelection
        }
        guard let currentSelection,
              let currentIndex = assets.firstIndex(where: { $0.id == currentSelection }) else {
            return assets.first(where: { scope.matches($0.metadata.flag) })?.id
        }
        var forward = currentIndex + 1
        var backward = currentIndex - 1
        while forward < assets.count || backward >= 0 {
            if forward < assets.count, scope.matches(assets[forward].metadata.flag) {
                return assets[forward].id
            }
            if backward >= 0, scope.matches(assets[backward].metadata.flag) {
                return assets[backward].id
            }
            forward += 1
            backward -= 1
        }
        return nil
    }
}

/// Pure ordering for Compare refill (Task 18): when a frame is rejected out
/// of the survey, the next undecided sibling from the same candidate stack —
/// if any — takes its slot so the grid stays full until the stack runs out.
public enum CompareRefillOrdering {
    public static func afterReject(
        currentCompareAssetIDs: [AssetID],
        rejectedAssetID: AssetID,
        stackAssetIDs: [AssetID],
        isUndecided: (AssetID) -> Bool
    ) -> [AssetID] {
        var result = currentCompareAssetIDs.filter { $0 != rejectedAssetID }
        guard !stackAssetIDs.isEmpty else { return result }
        let present = Set(result)
        if let refill = stackAssetIDs.first(where: { $0 != rejectedAssetID && !present.contains($0) && isUndecided($0) }) {
            result.append(refill)
        }
        return result
    }
}

/// Pure ordering for auto-populating Compare when entering it from a stack
/// (Task 18): the top-recommended frame leads, the rest keep the stack's
/// original order, capped at `cap` frames.
public enum CompareAutoPopulateOrdering {
    public static func orderedStackAssetIDs(
        stackAssetIDs: [AssetID],
        recommendedAssetID: AssetID?,
        cap: Int
    ) -> [AssetID] {
        guard let recommendedAssetID, stackAssetIDs.contains(recommendedAssetID) else {
            return Array(stackAssetIDs.prefix(max(0, cap)))
        }
        var ordered = [recommendedAssetID]
        ordered.append(contentsOf: stackAssetIDs.filter { $0 != recommendedAssetID })
        return Array(ordered.prefix(max(0, cap)))
    }
}

/// Pure targeting math for the Z (zoom-to-face) shortcut: which detected
/// face is nearest a reference point, and which face a repeated press
/// cycles to next. Kept free of `AppModel` state so it's directly testable.
public enum LoupeFaceZoomTargeting {
    public static func nearestFaceIndex(to focus: LoupeZoomFocus, among faces: [LoupeZoomFocus]) -> Int? {
        guard !faces.isEmpty else { return nil }
        return faces.indices.min { lhs, rhs in
            distanceSquared(faces[lhs], focus) < distanceSquared(faces[rhs], focus)
        }
    }

    public static func wrappedIndex(current: Int, faceCount: Int) -> Int {
        guard faceCount > 0 else { return 0 }
        return (current + 1) % faceCount
    }

    private static func distanceSquared(_ a: LoupeZoomFocus, _ b: LoupeZoomFocus) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}

/// The loupe's EXIF overlay detail: hidden, a single exposure summary line,
/// or the full set of technical fields. Cycled with the `i` shortcut.
public enum ExifOverlayLevel: Int, CaseIterable, Equatable, Sendable {
    case off
    case exposureLine
    case full

    public func next() -> ExifOverlayLevel {
        let cases = Self.allCases
        guard let index = cases.firstIndex(of: self) else { return .off }
        return cases[(index + 1) % cases.count]
    }
}

public enum CullingShortcutKey: Equatable, Sendable {
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case returnKey
    case character(String)

    /// Human-readable key label for the ? key-map overlay.
    public var displayText: String {
        switch self {
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .returnKey: return "⏎"
        case .character(let character): return character
        }
    }
}

public struct CullingCommandMenuItem: Equatable, Identifiable, Sendable {
    public var title: String
    public var shortcut: CullingShortcut
    public var key: CullingShortcutKey

    public var id: String { title }

    public init(title: String, shortcut: CullingShortcut, key: CullingShortcutKey) {
        self.title = title
        self.shortcut = shortcut
        self.key = key
    }

    /// Menu-item label with the key advertised as a title suffix, e.g.
    /// "Pick (P)". The key is display-only here — no `.keyboardShortcut`
    /// binding accompanies it (see `menuKeyboardShortcut` in main.swift for
    /// why bare culling keys can't be bound in the menu without double-
    /// firing against the in-view key monitors). This is the one place the
    /// key glyph is derived from `CullingShortcutKey.displayText` for menu
    /// advertisement, so every culling menu item stays in sync with the
    /// same source the `?` key-map overlay uses.
    public var menuDisplayTitle: String {
        "\(title) (\(key.displayText))"
    }
}

public struct CullingCommandMenuSection: Equatable, Identifiable, Sendable {
    public var title: String
    public var items: [CullingCommandMenuItem]

    public var id: String { title }

    public init(title: String, items: [CullingCommandMenuItem]) {
        self.title = title
        self.items = items
    }
}

public enum CullingCommandMenuPresentation {
    public static let sections: [CullingCommandMenuSection] = [
        CullingCommandMenuSection(title: "Navigation", items: [
            CullingCommandMenuItem(title: "Previous Frame in Stack", shortcut: .previousCandidateInStack, key: .upArrow),
            CullingCommandMenuItem(title: "Next Frame in Stack", shortcut: .nextCandidateInStack, key: .downArrow),
            CullingCommandMenuItem(title: "Previous Stack", shortcut: .previousStack, key: .leftArrow),
            CullingCommandMenuItem(title: "Next Stack", shortcut: .nextStack, key: .rightArrow),
            CullingCommandMenuItem(title: "Promote Frame & Reject Siblings", shortcut: .promoteAndRejectSiblings, key: .returnKey)
        ]),
        CullingCommandMenuSection(title: "Ratings", items: [
            CullingCommandMenuItem(title: "Clear Rating", shortcut: .rating(0), key: .character("0")),
            CullingCommandMenuItem(title: "1 Star", shortcut: .rating(1), key: .character("1")),
            CullingCommandMenuItem(title: "2 Stars", shortcut: .rating(2), key: .character("2")),
            CullingCommandMenuItem(title: "3 Stars", shortcut: .rating(3), key: .character("3")),
            CullingCommandMenuItem(title: "4 Stars", shortcut: .rating(4), key: .character("4")),
            CullingCommandMenuItem(title: "5 Stars", shortcut: .rating(5), key: .character("5"))
        ]),
        CullingCommandMenuSection(title: "Color Labels", items: [
            CullingCommandMenuItem(title: "Red Label", shortcut: .colorLabel(.red), key: .character("6")),
            CullingCommandMenuItem(title: "Yellow Label", shortcut: .colorLabel(.yellow), key: .character("7")),
            CullingCommandMenuItem(title: "Green Label", shortcut: .colorLabel(.green), key: .character("8")),
            CullingCommandMenuItem(title: "Blue Label", shortcut: .colorLabel(.blue), key: .character("9")),
            CullingCommandMenuItem(title: "Purple Label", shortcut: .colorLabel(.purple), key: .character("v")),
            CullingCommandMenuItem(title: "Clear Label", shortcut: .colorLabel(nil), key: .character("-"))
        ]),
        CullingCommandMenuSection(title: "Flags", items: [
            CullingCommandMenuItem(title: "Pick", shortcut: .pick, key: .character("p")),
            CullingCommandMenuItem(title: "Reject", shortcut: .reject, key: .character("x")),
            CullingCommandMenuItem(title: "Clear Flag", shortcut: .clearFlag, key: .character("u"))
        ]),
        CullingCommandMenuSection(title: "Loupe", items: [
            CullingCommandMenuItem(title: "Toggle 1:1 Zoom", shortcut: .toggleZoom, key: .character("z")),
            CullingCommandMenuItem(title: "Zoom to Nearest Face", shortcut: .zoomToNearestFace, key: .character("Z")),
            CullingCommandMenuItem(title: "Cycle EXIF Overlay", shortcut: .cycleExifOverlay, key: .character("i")),
            CullingCommandMenuItem(title: "Show Key Map", shortcut: .showKeyMap, key: .character("?"))
        ]),
        CullingCommandMenuSection(title: "Filter", items: [
            CullingCommandMenuItem(title: "Cycle Filter", shortcut: .cycleScope, key: .character("s"))
        ]),
        CullingCommandMenuSection(title: "Compare", items: [
            CullingCommandMenuItem(title: "Keep A · Reject B", shortcut: .keepAOverB, key: .character(",")),
            CullingCommandMenuItem(title: "Keep B · Reject A", shortcut: .keepBOverA, key: .character("."))
        ])
    ]
}

/// Direction of a keyboard scroll through the ? key-map overlay (item 3).
public enum KeyMapOverlayScrollDirection: Equatable, Sendable {
    case up
    case down
    case pageUp
    case pageDown
}

/// Pure index arithmetic for scrolling the ? overlay by section, clamped at
/// its edges — kept free of `AppModel` state so it's directly testable.
public enum KeyMapOverlayScrolling {
    public static func nextIndex(
        current: Int,
        direction: KeyMapOverlayScrollDirection,
        sectionCount: Int
    ) -> Int {
        guard sectionCount > 0 else { return 0 }
        let step: Int
        switch direction {
        case .up: step = -1
        case .down: step = 1
        case .pageUp: step = -3
        case .pageDown: step = 3
        }
        return min(max(current + step, 0), sectionCount - 1)
    }
}

private enum CullingStackNavigationDirection {
    case previous
    case next
}

private struct IndexedCullingStack {
    var stack: AssetStack
    var firstIndex: Int
    var lastIndex: Int

    var firstAssetID: AssetID? {
        stack.assetIDs.first
    }
}

public enum ReviewQueue: String, CaseIterable, Equatable, Hashable, Sendable {
    case picks
    case potentialPicks
    case rejects
    case fiveStars
    case needsKeywords
    case needsEvaluation
    case facesFound
    case ocrFound
    case likelyIssues
    case providerFailures
}

public struct ReviewQueuePresentation: Equatable, Sendable {
    public var title: String
    public var systemImage: String

    public init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }
}

public extension ReviewQueue {
    var presentation: ReviewQueuePresentation {
        switch self {
        case .picks:
            return ReviewQueuePresentation(title: "Picks", systemImage: "flag.fill")
        case .potentialPicks:
            return ReviewQueuePresentation(title: "Potential Picks", systemImage: "sparkles")
        case .rejects:
            return ReviewQueuePresentation(title: "Rejects", systemImage: "xmark.circle")
        case .fiveStars:
            return ReviewQueuePresentation(title: "5 Stars", systemImage: "star.fill")
        case .needsKeywords:
            return ReviewQueuePresentation(title: "Needs Keywords", systemImage: "tag")
        case .needsEvaluation:
            return ReviewQueuePresentation(title: "Not analyzed yet", systemImage: "wand.and.stars")
        case .facesFound:
            return ReviewQueuePresentation(title: "Faces Found", systemImage: "person.2")
        case .ocrFound:
            return ReviewQueuePresentation(title: "OCR Found", systemImage: "text.viewfinder")
        case .likelyIssues:
            return ReviewQueuePresentation(title: "Likely Issues", systemImage: "exclamationmark.triangle")
        case .providerFailures:
            return ReviewQueuePresentation(title: "Analysis Failures", systemImage: "bolt.horizontal.circle")
        }
    }
}

/// The groupings the Cull sidebar's source picker presents. Recent Import,
/// Autopilot Proposals, and Selection are singletons; Top Picks and Needs
/// Eyes each carry the pair of review queues Copilot used to read
/// (picks/potentialPicks, likelyIssues/needsEvaluation) so the sidebar
/// row-per-queue reuses the same counts.
public enum CullSourceGroup: String, Equatable, Sendable {
    case recentImport
    case autopilotProposals
    case topPicks
    case needsEyes
    case diagnostics
    case selection
}

public struct CullSource: Equatable, Sendable, Identifiable {
    public enum Target: Equatable, Sendable {
        case recentImport
        case autopilotProposals
        case reviewQueue(ReviewQueue)
        case selection
    }

    public var id: String
    public var group: CullSourceGroup
    public var title: String
    public var systemImage: String
    public var count: Int
    public var target: Target

    public init(id: String, group: CullSourceGroup, title: String, systemImage: String, count: Int, target: Target) {
        self.id = id
        self.group = group
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.target = target
    }
}

public struct CullSourcePresentation: Equatable, Sendable {
    public var sources: [CullSource]

    public init(sources: [CullSource]) {
        self.sources = sources
    }

    /// Sources actually worth showing: zero-count rows are omitted rather
    /// than rendered disabled, so the sidebar never shows a dead-end row.
    public var visibleSources: [CullSource] {
        sources.filter { $0.count > 0 }
    }

    /// True when there is nothing actionable to cull from any source.
    public var isEmpty: Bool {
        visibleSources.isEmpty
    }
}

/// The plan the "Find Best Shots" marquee action follows: whether to kick off
/// evaluation over the current scope, and where to land the user. It never
/// dead-ends — when nothing ranks and there is nothing left to evaluate it
/// carries a plain-language message (reusing the autopilot "0 keepers"
/// avoidance) instead of routing to an empty queue.
public struct FindBestShotsPlan: Equatable, Sendable {
    public enum Route: Equatable, Sendable {
        case reviewQueue(ReviewQueue)
        case nothingRanked(message: String)
    }

    public var shouldTriggerEvaluation: Bool
    public var route: Route

    public init(shouldTriggerEvaluation: Bool, route: Route) {
        self.shouldTriggerEvaluation = shouldTriggerEvaluation
        self.route = route
    }
}

public enum FindBestShotsRouter {
    /// The plain-language result shown when the scope is fully evaluated but
    /// nothing rises to a pick — mirrors `AutopilotRunSummary.bannerText` so the
    /// user never sees a bare "0 keepers".
    public static let nothingRankedMessage = "These look too distinct to auto-rank — rate a few to rank"

    public static func plan(
        pickCount: Int,
        potentialPickCount: Int,
        canEvaluateScope: Bool,
        needsEvaluationCount: Int
    ) -> FindBestShotsPlan {
        let shouldEvaluate = canEvaluateScope && needsEvaluationCount > 0

        if potentialPickCount > 0 {
            return FindBestShotsPlan(shouldTriggerEvaluation: shouldEvaluate, route: .reviewQueue(.potentialPicks))
        }
        if pickCount > 0 {
            return FindBestShotsPlan(shouldTriggerEvaluation: shouldEvaluate, route: .reviewQueue(.picks))
        }
        // Nothing ranks yet. If there are still-unevaluated frames we can read,
        // trigger evaluation and land on Potential Picks so it fills in as the
        // worker reports; otherwise say what actually happened, never zero.
        if shouldEvaluate {
            return FindBestShotsPlan(shouldTriggerEvaluation: true, route: .reviewQueue(.potentialPicks))
        }
        return FindBestShotsPlan(shouldTriggerEvaluation: false, route: .nothingRanked(message: nothingRankedMessage))
    }
}

public enum SmartCollectionRulePreset: String, CaseIterable, Identifiable, Sendable {
    case ratingFourPlus
    case picked
    case rejected
    case needsKeywords
    case needsEvaluation
    case onlineSources
    case offlineSources
    case facesFound
    case ocrFound
    case focusSignals
    case objectSignals
    case likelyIssues
    case providerFailures
    case xmpPending
    case xmpConflicts

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ratingFourPlus:
            "4+ stars"
        case .picked:
            "Picked"
        case .rejected:
            "Rejected"
        case .needsKeywords:
            "Needs keywords"
        case .needsEvaluation:
            "Needs evaluation"
        case .onlineSources:
            "Online sources"
        case .offlineSources:
            "Offline sources"
        case .facesFound:
            "Faces found"
        case .ocrFound:
            "OCR found"
        case .focusSignals:
            "Focus signals"
        case .objectSignals:
            "Object signals"
        case .likelyIssues:
            "Likely issues"
        case .providerFailures:
            "Analysis failures"
        case .xmpPending:
            "XMP pending"
        case .xmpConflicts:
            "XMP conflicts"
        }
    }

    public var systemImage: String {
        switch self {
        case .ratingFourPlus:
            "star.fill"
        case .picked:
            "flag.fill"
        case .rejected:
            "xmark.circle"
        case .needsKeywords:
            "tag"
        case .needsEvaluation:
            "wand.and.stars"
        case .onlineSources:
            "externaldrive.fill.badge.checkmark"
        case .offlineSources:
            "externaldrive.badge.xmark"
        case .facesFound:
            "person.2"
        case .ocrFound:
            "text.viewfinder"
        case .focusSignals:
            "scope"
        case .objectSignals:
            "shippingbox"
        case .likelyIssues:
            "exclamationmark.triangle"
        case .providerFailures:
            "bolt.horizontal.circle"
        case .xmpPending:
            "arrow.triangle.2.circlepath"
        case .xmpConflicts:
            "exclamationmark.arrow.triangle.2.circlepath"
        }
    }
}

extension EvaluationKind {
    var displayName: String {
        switch self {
        case .focus:
            return "Focus"
        case .motionBlur:
            return "Motion Blur"
        case .exposure:
            return "Exposure"
        case .aesthetics:
            return "Aesthetics"
        case .framing:
            return "Framing"
        case .object:
            return "Object"
        case .faceCount:
            return "Face Count"
        case .faceQuality:
            return "Face Quality"
        case .ocrText:
            return "OCR Text"
        case .colorPalette:
            return "Color Palette"
        case .novelty:
            return "Novelty"
        case .visualSimilarity:
            return "Visual Similarity"
        case .smile:
            return "Smile"
        case .eyesOpen:
            return "Eyes Open"
        case .eyeSharpness:
            return "Eye Sharpness"
        }
    }
}

public struct PeopleFaceSuggestion: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case matchExisting(personID: String, personName: String)
        case newPerson
    }

    public var id: String
    public var kind: Kind
    public var faceIDs: [FaceID]
    public var representativeFace: FaceID
    public var representativeBoundingBox: FaceBoundingBox
    public var assetIDs: [AssetID]
}

public struct ProposedPersonPhoto: Identifiable, Equatable {
    public let asset: Asset
    public let faces: [ProposedPersonFace]
    public var id: String { asset.id.rawValue }
}

public enum SidebarRowTarget: Equatable, Sendable {
    case allPhotographs
    case search
    case timeline
    case people
    case places
    case placeholder
    case reviewQueue(ReviewQueue)
    case folder(String)
    case sourceAvailability(SourceAvailability)
    case evaluationKind(EvaluationKind)
    case metadataSyncPending
    case metadataSyncConflicts
    case assetSet(AssetSetID)
    case workSession(WorkSessionID)
}

public enum SidebarRowContextActionKind: Equatable, Sendable {
    case renameAssetSet(AssetSetID)
    case duplicateAssetSet(AssetSetID)
    case freezeAssetSetSnapshot(AssetSetID)
    case toggleAssetSetStarred(AssetSetID)
    case deleteAssetSet(AssetSetID)
    case toggleWorkSessionStarred(WorkSessionID)
}

public struct SidebarRowContextAction: Identifiable, Equatable, Sendable {
    public var kind: SidebarRowContextActionKind
    public var title: String
    public var systemImage: String

    public var id: String {
        switch kind {
        case .renameAssetSet(let id):
            return "rename-asset-set-\(id.rawValue)"
        case .duplicateAssetSet(let id):
            return "duplicate-asset-set-\(id.rawValue)"
        case .freezeAssetSetSnapshot(let id):
            return "freeze-asset-set-snapshot-\(id.rawValue)"
        case .toggleAssetSetStarred(let id):
            return "toggle-asset-set-starred-\(id.rawValue)"
        case .deleteAssetSet(let id):
            return "delete-asset-set-\(id.rawValue)"
        case .toggleWorkSessionStarred(let id):
            return "toggle-work-session-starred-\(id.rawValue)"
        }
    }

    public init(kind: SidebarRowContextActionKind, title: String, systemImage: String) {
        self.kind = kind
        self.title = title
        self.systemImage = systemImage
    }
}

public struct SidebarRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detailText: String?
    public var countText: String?
    public var tone: SidebarRowTone
    public var target: SidebarRowTarget
    public var liveMockupPlaceholder: LiveMockupPlaceholder?
    /// Indentation level for tree-shaped sections (currently only Folders).
    /// Zero for every other section's flat rows.
    public var depth: Int
    /// Expand/collapse affordance for tree-shaped rows. `.none` for rows
    /// that aren't part of a tree, or that are but have no children.
    public var disclosure: SidebarRowDisclosure

    public init(
        id: String,
        title: String,
        detailText: String? = nil,
        countText: String? = nil,
        tone: SidebarRowTone = .neutral,
        target: SidebarRowTarget = .placeholder,
        liveMockupPlaceholder: LiveMockupPlaceholder? = nil,
        depth: Int = 0,
        disclosure: SidebarRowDisclosure = .none
    ) {
        self.id = id
        self.title = title
        self.detailText = detailText
        self.countText = countText
        self.tone = tone
        self.target = target
        self.liveMockupPlaceholder = liveMockupPlaceholder
        self.depth = depth
        self.disclosure = disclosure
    }

    public var isSelectable: Bool {
        target != .placeholder
    }
}

public enum SidebarRowDisclosure: Equatable, Sendable {
    case none
    case collapsed
    case expanded
}

public struct ActiveLibraryFilterRow: Identifiable, Equatable, Sendable {
    public var title: String
    public var target: SidebarRowTarget?
    /// True when this row is the unparsed leftover of the top-bar search text (LibrarySearchIntent's
    /// residual text), which is matched as plain filename/text search rather than a structured filter.
    public var isPlainSearchFallback: Bool

    public var id: String { title }

    /// Second line on the filter chip explaining unusual rows in user
    /// language; nil for ordinary structured filters.
    public var subtitle: String? {
        isPlainSearchFallback ? "Not a filter — matching file names and photo text" : nil
    }

    public init(title: String, target: SidebarRowTarget? = nil, isPlainSearchFallback: Bool = false) {
        self.title = title
        self.target = target
        self.isPlainSearchFallback = isPlainSearchFallback
    }
}

public enum SidebarRowTone: String, Equatable, Sendable {
    case neutral
    case accent
    case positive
    case warning
    case destructive
}

public struct SidebarSection: Identifiable, Equatable {
    public var id: String { title }
    public var title: String
    public var rows: [SidebarRow]

    public var rowTitles: [String] {
        rows.map(\.title)
    }

    public init(title: String, rows: [String]) {
        self.title = title
        let sectionTitle = title
        self.rows = rows.enumerated().map { index, title in
            SidebarRow(id: "\(sectionTitle)-\(index)-\(title)", title: title)
        }
    }

    public init(title: String, rows: [SidebarRow]) {
        self.title = title
        self.rows = rows
    }
}

public struct CatalogSourceAvailabilitySummary: Equatable, Sendable {
    public var availability: SourceAvailability
    public var assetCount: Int

    public init(availability: SourceAvailability, assetCount: Int) {
        self.availability = availability
        self.assetCount = assetCount
    }
}

public struct AppDiagnosticsSourceRoot: Equatable, Sendable {
    public var path: String
    public var name: String
    public var assetCount: Int
    public var unavailableAssetCount: Int
    public var hasSecurityScopedBookmark: Bool
    public var needsSecurityScopedBookmarkRepair: Bool

    public init(
        path: String,
        name: String,
        assetCount: Int,
        unavailableAssetCount: Int,
        hasSecurityScopedBookmark: Bool = false,
        needsSecurityScopedBookmarkRepair: Bool = false
    ) {
        self.path = path
        self.name = name
        self.assetCount = assetCount
        self.unavailableAssetCount = unavailableAssetCount
        self.hasSecurityScopedBookmark = hasSecurityScopedBookmark
        self.needsSecurityScopedBookmarkRepair = needsSecurityScopedBookmarkRepair
    }
}

public struct AppDiagnosticsWorkStatusCount: Equatable, Sendable {
    public var status: WorkSessionStatus
    public var count: Int

    public init(status: WorkSessionStatus, count: Int) {
        self.status = status
        self.count = count
    }
}

public struct AppDiagnosticsWorkKindCount: Equatable, Sendable {
    public var kind: WorkSessionKind
    public var count: Int

    public init(kind: WorkSessionKind, count: Int) {
        self.kind = kind
        self.count = count
    }
}

public struct AppDiagnosticsSourceAvailabilityCount: Equatable, Sendable {
    public var availability: SourceAvailability
    public var count: Int

    public init(availability: SourceAvailability, count: Int) {
        self.availability = availability
        self.count = count
    }
}

public struct AppDiagnosticsBackgroundWork: Equatable, Sendable {
    public var maxRunningCount: Int
    public var kindRunningLimits: [AppDiagnosticsWorkKindCount]
    public var statusCounts: [AppDiagnosticsWorkStatusCount]
    public var kindCounts: [AppDiagnosticsWorkKindCount]

    public init(
        maxRunningCount: Int,
        kindRunningLimits: [AppDiagnosticsWorkKindCount],
        statusCounts: [AppDiagnosticsWorkStatusCount],
        kindCounts: [AppDiagnosticsWorkKindCount]
    ) {
        self.maxRunningCount = maxRunningCount
        self.kindRunningLimits = kindRunningLimits
        self.statusCounts = statusCounts
        self.kindCounts = kindCounts
    }
}

public struct AppDiagnosticsWorkFailure: Equatable, Sendable {
    public var id: String
    public var kind: WorkSessionKind
    public var title: String
    public var detail: String
    public var failureCount: Int

    public init(id: String, kind: WorkSessionKind, title: String, detail: String, failureCount: Int) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.failureCount = failureCount
    }
}

public struct AppDiagnosticsSnapshot: Equatable, Sendable {
    public var catalogRootPath: String?
    public var catalogDatabasePath: String?
    public var previewCacheRootPath: String?
    public var workerExecutablePath: String?
    public var workerConfigured: Bool
    public var workerEnabled: Bool
    public var workerProcessRunning: Bool
    public var loadedAssetCount: Int
    public var totalAssetCount: Int
    public var pendingBackgroundWorkCount: Int
    public var pendingMetadataSyncCount: Int
    public var metadataSyncConflictCount: Int
    public var backgroundWork: AppDiagnosticsBackgroundWork
    public var sourceAvailabilityCounts: [AppDiagnosticsSourceAvailabilityCount]
    public var sourceRoots: [AppDiagnosticsSourceRoot]
    public var recentFailures: [AppDiagnosticsWorkFailure]

    public var previewCachePath: String? {
        previewCacheRootPath
    }

    public init(
        catalogRootPath: String?,
        catalogDatabasePath: String?,
        previewCacheRootPath: String?,
        workerExecutablePath: String?,
        workerConfigured: Bool,
        workerEnabled: Bool,
        workerProcessRunning: Bool,
        loadedAssetCount: Int,
        totalAssetCount: Int,
        pendingBackgroundWorkCount: Int,
        pendingMetadataSyncCount: Int,
        metadataSyncConflictCount: Int,
        backgroundWork: AppDiagnosticsBackgroundWork,
        sourceAvailabilityCounts: [AppDiagnosticsSourceAvailabilityCount],
        sourceRoots: [AppDiagnosticsSourceRoot],
        recentFailures: [AppDiagnosticsWorkFailure]
    ) {
        self.catalogRootPath = catalogRootPath
        self.catalogDatabasePath = catalogDatabasePath
        self.previewCacheRootPath = previewCacheRootPath
        self.workerExecutablePath = workerExecutablePath
        self.workerConfigured = workerConfigured
        self.workerEnabled = workerEnabled
        self.workerProcessRunning = workerProcessRunning
        self.loadedAssetCount = loadedAssetCount
        self.totalAssetCount = totalAssetCount
        self.pendingBackgroundWorkCount = pendingBackgroundWorkCount
        self.pendingMetadataSyncCount = pendingMetadataSyncCount
        self.metadataSyncConflictCount = metadataSyncConflictCount
        self.backgroundWork = backgroundWork
        self.sourceAvailabilityCounts = sourceAvailabilityCounts
        self.sourceRoots = sourceRoots
        self.recentFailures = recentFailures
    }
}

public typealias AppDiagnosticsFailure = AppDiagnosticsWorkFailure

public enum AppDiagnosticsReport {
    public static func text(for snapshot: AppDiagnosticsSnapshot) -> String {
        let backgroundKindCounts = snapshot.backgroundWork.kindCounts
            .map { "  \($0.kind.rawValue): \($0.count)" }
        let backgroundStatusCounts = snapshot.backgroundWork.statusCounts
            .map { "  \($0.status.rawValue): \($0.count)" }
        let sourceCounts = snapshot.sourceAvailabilityCounts
            .map { "  \($0.availability.rawValue): \($0.count)" }
        let sourceRoots = snapshot.sourceRoots.map { root in
            let repairText = root.needsSecurityScopedBookmarkRepair ? ", bookmark repair needed" : ""
            let bookmarkText = root.hasSecurityScopedBookmark ? ", bookmark yes\(repairText)" : ", bookmark no"
            return "  \(root.name): \(root.path) (\(root.unavailableAssetCount) unavailable of \(root.assetCount)\(bookmarkText))"
        }
        let failures = snapshot.recentFailures.map { failure in
            "  \(failure.kind.rawValue) \(failure.id): \(failure.detail)"
        }

        return [
            "Teststrip Diagnostics",
            "Catalog root: \(snapshot.catalogRootPath ?? "Unavailable")",
            "Catalog database: \(snapshot.catalogDatabasePath ?? "Unavailable")",
            "Preview cache: \(snapshot.previewCachePath ?? "Unavailable")",
            "Worker executable: \(snapshot.workerExecutablePath ?? "Unavailable")",
            "Worker enabled: \(snapshot.workerEnabled ? "yes" : "no")",
            "Worker process: \(snapshot.workerProcessRunning ? "running" : "stopped")",
            "Assets loaded/total: \(snapshot.loadedAssetCount)/\(snapshot.totalAssetCount)",
            "Background active: \(snapshot.pendingBackgroundWorkCount)",
            "XMP pending/conflicts: \(snapshot.pendingMetadataSyncCount)/\(snapshot.metadataSyncConflictCount)",
            "Background by kind:",
            backgroundKindCounts.isEmpty ? "  none" : backgroundKindCounts.joined(separator: "\n"),
            "Background by status:",
            backgroundStatusCounts.isEmpty ? "  none" : backgroundStatusCounts.joined(separator: "\n"),
            "Source availability:",
            sourceCounts.isEmpty ? "  none" : sourceCounts.joined(separator: "\n"),
            "Source roots:",
            sourceRoots.isEmpty ? "  none" : sourceRoots.joined(separator: "\n"),
            "Recent failures:",
            failures.isEmpty ? "  none" : failures.joined(separator: "\n")
        ].joined(separator: "\n")
    }
}

public struct AppWorkActivity: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: WorkSessionKind
    public var status: WorkSessionStatus
    public var title: String
    public var detail: String
    public var completedUnitCount: Int
    public var totalUnitCount: Int?
    public var failureCount: Int
    public var issues: [WorkSessionIssue]
    public var starred: Bool
    public var inputSetIDs: [AssetSetID]
    public var outputSetIDs: [AssetSetID]

    public init(
        id: String = UUID().uuidString,
        kind: WorkSessionKind,
        status: WorkSessionStatus,
        title: String,
        detail: String,
        completedUnitCount: Int,
        totalUnitCount: Int?,
        failureCount: Int,
        issues: [WorkSessionIssue] = [],
        starred: Bool = false,
        inputSetIDs: [AssetSetID] = [],
        outputSetIDs: [AssetSetID] = []
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.detail = detail
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.failureCount = failureCount
        self.issues = issues
        self.starred = starred
        self.inputSetIDs = inputSetIDs
        self.outputSetIDs = outputSetIDs
    }

    public var showsProgress: Bool {
        totalUnitCount != nil && [.queued, .running, .paused].contains(status)
    }

    public init(workItem: BackgroundWorkItem) {
        self.init(
            id: workItem.id.rawValue,
            kind: workItem.kind,
            status: workItem.status,
            title: workItem.title,
            detail: workItem.detail,
            completedUnitCount: workItem.completedUnitCount,
            totalUnitCount: workItem.totalUnitCount,
            failureCount: 0
        )
    }

    public init(workSession: WorkSession) {
        self.init(
            id: workSession.id.rawValue,
            kind: workSession.kind,
            status: workSession.status,
            title: workSession.title.isEmpty ? workSession.kind.rawValue : workSession.title,
            detail: workSession.detail,
            completedUnitCount: workSession.completedUnitCount,
            totalUnitCount: workSession.totalUnitCount,
            failureCount: workSession.failureCount,
            issues: workSession.issues,
            starred: workSession.starred,
            inputSetIDs: workSession.inputSetIDs,
            outputSetIDs: workSession.outputSetIDs
        )
    }
}

public struct ImportCompletionSummary: Identifiable, Equatable, Sendable {
    public var activityID: String
    public var title: String
    public var detail: String
    public var importedPhotoCount: Int
    public var photoCountText: String
    public var newPhotoCount: Int
    public var existingPhotoCount: Int
    public var previewFailureCount: Int
    public var failureText: String?
    public var previewStatusText: String
    public var issues: [WorkSessionIssue]
    public var stackCount: Int = 0
    public var stackedPhotoCount: Int = 0
    public var cullingSessionName: String

    public var id: String { activityID }
}

public struct ExportCompletionSummary: Equatable, Sendable {
    public var exportedCount: Int
    public var skippedCount: Int
    public var failedCount: Int
    public var destinationFolder: URL
    public var firstFailureMessage: String?

    public init(
        exportedCount: Int,
        skippedCount: Int,
        failedCount: Int,
        destinationFolder: URL,
        firstFailureMessage: String?
    ) {
        self.exportedCount = exportedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.destinationFolder = destinationFolder
        self.firstFailureMessage = firstFailureMessage
    }

    public init(results: [ExportFileResult], destinationFolder: URL) {
        var exportedCount = 0
        var skippedCount = 0
        var failedCount = 0
        var firstFailureMessage: String?
        for result in results {
            switch result.outcome {
            case .exported:
                exportedCount += 1
            case .skippedUnavailable:
                skippedCount += 1
            case .failed(let message):
                failedCount += 1
                if firstFailureMessage == nil {
                    firstFailureMessage = message
                }
            }
        }
        self.init(
            exportedCount: exportedCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            destinationFolder: destinationFolder,
            firstFailureMessage: firstFailureMessage
        )
    }

    public var statusText: String {
        let exportedText = "Exported \(exportedCount) \(exportedCount == 1 ? "photo" : "photos") to \(destinationFolder.lastPathComponent)"
        var problems: [String] = []
        if skippedCount > 0 {
            problems.append("\(skippedCount) skipped")
        }
        if failedCount > 0 {
            problems.append("\(failedCount) failed")
        }
        guard !problems.isEmpty else { return exportedText }
        return "\(exportedText) (\(problems.joined(separator: ", ")))"
    }
}

public struct RejectRelocationPreflight: Equatable, Identifiable, Sendable {
    public var id: String { "\(mode == .trash ? "trash" : "folder")-\(destinationFolder.path)" }
    public var assetIDs: [AssetID]
    public var originalURLs: [URL]
    public var plans: [RejectRelocationPlan]
    public var sidecarCount: Int
    public var totalByteCount: Int64
    public var unavailableCount: Int
    public var alreadyInDestinationCount: Int
    public var destinationFolder: URL
    public var mode: RelocationMode
    // Rejects that exist in the catalog but are excluded by the active
    // library filter/scope (e.g. a Picks filter hiding all rejects) — the
    // sheet must disclose these rather than silently reporting "0 files"
    // (persona-4 Gloria's "THE WALL" scope-disclosure finding).
    public var outsideScopeCount: Int

    // The Trash isn't a single user-chosen folder, so a trash-mode preflight
    // carries this placeholder purely for display (title text, sheet id)
    // rather than an actual move destination.
    static let trashDisplayFolder = URL(fileURLWithPath: "/Trash", isDirectory: true)

    public init(
        assetIDs: [AssetID],
        originalURLs: [URL],
        plans: [RejectRelocationPlan],
        sidecarCount: Int,
        totalByteCount: Int64,
        unavailableCount: Int,
        alreadyInDestinationCount: Int,
        destinationFolder: URL,
        mode: RelocationMode? = nil,
        outsideScopeCount: Int = 0
    ) {
        self.assetIDs = assetIDs
        self.originalURLs = originalURLs
        self.plans = plans
        self.sidecarCount = sidecarCount
        self.totalByteCount = totalByteCount
        self.unavailableCount = unavailableCount
        self.alreadyInDestinationCount = alreadyInDestinationCount
        self.destinationFolder = destinationFolder
        self.mode = mode ?? .folder(destinationFolder)
        self.outsideScopeCount = outsideScopeCount
    }

    public var moveCount: Int { plans.count }

    public var hasMovableFiles: Bool { moveCount > 0 }

    public var confirmationText: String {
        "Move \(moveCount) reject \(moveCount == 1 ? "photo" : "photos") to \(destinationFolder.lastPathComponent)"
    }

    public var summaryText: String {
        // Nothing in the current view, but rejects exist elsewhere in the
        // catalog: say so explicitly rather than reading as "there are no
        // rejects" (persona-4 Gloria's "but I have rejects?!" moment).
        if moveCount == 0 && outsideScopeCount > 0 {
            return "0 in current view — \(outsideScopeCount) more outside filters"
        }
        let sidecarText = "\(sidecarCount) \(sidecarCount == 1 ? "sidecar" : "sidecars")"
        let sizeText = ByteCountFormatter.string(fromByteCount: totalByteCount, countStyle: .file)
        return "\(moveCount) \(moveCount == 1 ? "file" : "files") · \(sidecarText) · \(sizeText)"
    }

    public var destinationPreview: [String] {
        plans.prefix(8).map { plan in
            plan.originalTo.path.replacingOccurrences(
                of: destinationFolder.standardizedFileURL.path + "/",
                with: ""
            )
        }
    }

    public var warningText: String? {
        var parts: [String] = []
        if unavailableCount > 0 {
            parts.append("\(unavailableCount) unavailable \(unavailableCount == 1 ? "original is" : "originals are") skipped")
        }
        if alreadyInDestinationCount > 0 {
            parts.append("\(alreadyInDestinationCount) already in the destination")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

public struct RejectRelocationSummary: Equatable, Identifiable, Sendable {
    public var sessionID: WorkSessionID
    public var movedCount: Int
    public var sidecarCount: Int
    public var skippedCount: Int
    public var destinationFolder: URL
    /// Nil until a Move back ran for this session; then the banner reports
    /// the restore outcome instead of the original move.
    public var restoredCount: Int?
    /// Files whose Trash copy no longer exists (the user emptied the Trash):
    /// permanently unrecoverable, reported rather than silently skipped.
    public var unrestorableCount: Int
    /// Restore attempts that failed for transient reasons (still in the
    /// Trash, retryable) — distinct from unrestorableCount's gone-for-good.
    public var restoreFailureCount: Int
    /// False once nothing restorable remains — the banner retires its
    /// Move back button instead of inviting another no-op press.
    public var canMoveBack: Bool

    public init(
        sessionID: WorkSessionID,
        movedCount: Int,
        sidecarCount: Int,
        skippedCount: Int,
        destinationFolder: URL,
        restoredCount: Int? = nil,
        unrestorableCount: Int = 0,
        restoreFailureCount: Int = 0,
        canMoveBack: Bool = true
    ) {
        self.sessionID = sessionID
        self.movedCount = movedCount
        self.sidecarCount = sidecarCount
        self.skippedCount = skippedCount
        self.destinationFolder = destinationFolder
        self.restoredCount = restoredCount
        self.unrestorableCount = unrestorableCount
        self.restoreFailureCount = restoreFailureCount
        self.canMoveBack = canMoveBack
    }

    public var id: String { sessionID.rawValue }

    public var detailText: String {
        if let restoredCount {
            var parts: [String] = []
            if restoredCount > 0 {
                parts.append("Moved back \(restoredCount) \(restoredCount == 1 ? "photo" : "photos")")
            }
            if unrestorableCount > 0 {
                parts.append(
                    "\(unrestorableCount) \(unrestorableCount == 1 ? "file is" : "files are") no longer in the Trash and can't be restored"
                )
            }
            if restoreFailureCount > 0 {
                parts.append("\(restoreFailureCount) couldn't be restored")
            }
            return parts.joined(separator: " · ")
        }
        let movedText = "Moved \(movedCount) reject \(movedCount == 1 ? "photo" : "photos") to \(destinationFolder.lastPathComponent)"
        guard skippedCount > 0 else { return movedText }
        return "\(movedText) · \(skippedCount) skipped"
    }
}

public struct KeywordSuggestion: Identifiable, Equatable, Sendable {
    public var keyword: String
    public var sourceKind: EvaluationKind
    public var confidence: Double
    public var providerName: String
    public var modelName: String

    public var id: String {
        keyword.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    public var confidenceText: String {
        let clamped = min(max(confidence, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    public var provenanceText: String {
        "\(providerName)/\(modelName)"
    }
}

public struct CaptionSuggestion: Identifiable, Equatable, Sendable {
    public var caption: String
    public var sourceKind: EvaluationKind
    public var confidence: Double
    public var providerName: String
    public var modelName: String

    public var id: String {
        caption.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    public var confidenceText: String {
        let clamped = min(max(confidence, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    public var provenanceText: String {
        "\(providerName)/\(modelName)"
    }
}

public struct BatchKeywordSuggestion: Identifiable, Equatable, Sendable {
    public var keyword: String
    public var assetCount: Int
    public var averageConfidence: Double
    public var providerName: String
    public var modelName: String

    public var id: String {
        keyword.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    public var confidenceText: String {
        let clamped = min(max(averageConfidence, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    public var assetCountText: String {
        "\(assetCount) \(assetCount == 1 ? "photo" : "photos")"
    }

    public var provenanceText: String {
        "\(providerName)/\(modelName)"
    }
}

// Stable part of the latest-import panel: changes only when activities, metadata,
// or evaluations change, never on preview queue transitions. The summary's preview
// fields are placeholders until LatestImportPreviewStatus is patched in.
private struct LatestImportPresentationCore: Equatable, Sendable {
    var summary: ImportCompletionSummary?
    var flaggedReviewAssetCount: Int
    var faceReviewAssetCount: Int
    var batchKeywordSuggestions: [BatchKeywordSuggestion]
    var canRequestAssetEvaluations: Bool
    var outputAssetIDs: [AssetID]

    static let empty = LatestImportPresentationCore(
        summary: nil,
        flaggedReviewAssetCount: 0,
        faceReviewAssetCount: 0,
        batchKeywordSuggestions: [],
        canRequestAssetEvaluations: false,
        outputAssetIDs: []
    )
}

// Hands the coalesced-publication flush to WorkerTimeoutScheduling's @Sendable
// timer callback; the flush itself always runs on the main queue.
private final class BackgroundWorkPublicationFlush: @unchecked Sendable {
    private let flush: () -> Void

    init(_ flush: @escaping () -> Void) {
        self.flush = flush
    }

    func callAsFunction() {
        flush()
    }
}

// Live preview-drain part of the latest-import panel, rebuilt on preview queue
// transitions; its rebuild must stay limited to indexed count queries because those
// transitions fire for every preview of an import.
private struct LatestImportPreviewStatus: Equatable, Sendable {
    var previewFailureCount: Int
    var failureText: String?
    var previewStatusText: String

    static let empty = LatestImportPreviewStatus(
        previewFailureCount: 0,
        failureText: nil,
        previewStatusText: ""
    )
}

private struct BatchKeywordAccumulator {
    var keyword: String
    var assetCount: Int
    var confidenceTotal: Double
    var providerName: String
    var modelName: String
    var bestConfidence: Double

    var averageConfidence: Double {
        guard assetCount > 0 else { return 0 }
        return confidenceTotal / Double(assetCount)
    }
}

public struct AppImportOutput: Sendable {
    public var result: LibraryImportResult
    public var assets: [Asset]
    public var totalAssetCount: Int

    public init(result: LibraryImportResult, assets: [Asset], totalAssetCount: Int) {
        self.result = result
        self.assets = assets
        self.totalAssetCount = totalAssetCount
    }
}

public typealias AppImportTaskFactory = @Sendable (
    AppCatalogPaths,
    URL,
    DuplicateHandling,
    @escaping LibraryImportProgressHandler
) -> Task<AppImportOutput, Error>

public typealias AppCardImportTaskFactory = @Sendable (
    AppCatalogPaths,
    URL,
    URL,
    ImportDestinationPolicy,
    URL?,
    DuplicateHandling,
    @escaping LibraryImportProgressHandler
) -> Task<AppImportOutput, Error>

public struct SecurityScopedBookmarkResolution: Sendable {
    public var url: URL
    public var isStale: Bool

    public init(url: URL, isStale: Bool = false) {
        self.url = url
        self.isStale = isStale
    }
}

public struct SecurityScopedResourceAccess: Sendable {
    public var requiresSuccessfulAccess: Bool
    public var startAccessing: @Sendable (URL) -> Bool
    public var stopAccessing: @Sendable (URL) -> Void
    public var securityScopedBookmarkData: @Sendable (URL) throws -> Data?
    public var resolveSecurityScopedBookmarkData: @Sendable (Data) throws -> SecurityScopedBookmarkResolution

    public init(
        requiresSuccessfulAccess: Bool,
        startAccessing: @escaping @Sendable (URL) -> Bool,
        stopAccessing: @escaping @Sendable (URL) -> Void,
        securityScopedBookmarkData: @escaping @Sendable (URL) throws -> Data? = { _ in nil },
        resolveSecurityScopedBookmarkData: @escaping @Sendable (Data) throws -> SecurityScopedBookmarkResolution = { _ in
            throw TeststripError.invalidState("security-scoped bookmark resolution is unavailable")
        }
    ) {
        self.requiresSuccessfulAccess = requiresSuccessfulAccess
        self.startAccessing = startAccessing
        self.stopAccessing = stopAccessing
        self.securityScopedBookmarkData = securityScopedBookmarkData
        self.resolveSecurityScopedBookmarkData = resolveSecurityScopedBookmarkData
    }

    public static let permissive = SecurityScopedResourceAccess(
        requiresSuccessfulAccess: false,
        startAccessing: { $0.startAccessingSecurityScopedResource() },
        stopAccessing: { $0.stopAccessingSecurityScopedResource() },
        securityScopedBookmarkData: { url in
            try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        },
        resolveSecurityScopedBookmarkData: { data in
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return SecurityScopedBookmarkResolution(url: url, isStale: isStale)
        }
    )

    public static let required = SecurityScopedResourceAccess(
        requiresSuccessfulAccess: true,
        startAccessing: { $0.startAccessingSecurityScopedResource() },
        stopAccessing: { $0.stopAccessingSecurityScopedResource() },
        securityScopedBookmarkData: { url in
            try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        },
        resolveSecurityScopedBookmarkData: { data in
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return SecurityScopedBookmarkResolution(url: url, isStale: isStale)
        }
    )
}

private struct MetadataChange: Equatable {
    var assetID: AssetID
    var before: AssetMetadata
    var after: AssetMetadata
}

private struct MetadataChangeGroup: Equatable {
    var label: String
    var changes: [MetadataChange]
}

/// One touched asset's contribution to a run-time autopilot tentative batch
/// (`applyTentativeAutopilotProposals`): the pre-run/post-run snapshots plus
/// exactly which fields/keywords THIS run tentatively added. Recording the
/// delta (not just `before`) is what lets `revertAutopilotTentativeChange`
/// undo only the run's own contribution instead of blindly restoring the
/// whole pre-run snapshot and clobbering an unrelated edit the user made to
/// the same asset in between.
private struct AutopilotTentativeChange: Equatable {
    var assetID: AssetID
    var before: AssetMetadata
    var after: AssetMetadata
    /// Fields (`.flag` today) this run inserted into `aiUnconfirmedFields`.
    /// `.rating` follows the identical rule below if a future proposal kind
    /// ever tentatively writes it; `.caption`/`.keyword` never appear here —
    /// autopilot proposals never tentatively set a caption, and a tentative
    /// keyword is tracked in `tentativeKeywords` instead.
    var tentativeFields: Set<MetadataField>
    /// Keywords this run appended to `keywords` and marked `aiUnconfirmedKeywords`.
    var tentativeKeywords: Set<String>
}

private struct AutopilotTentativeChangeGroup: Equatable {
    var changes: [AutopilotTentativeChange]
}

public struct CullingMetadataDecisionFeedback: Equatable, Sendable {
    public var assetID: AssetID
    public var filename: String
    public var command: CullingCommand
    public var decisionText: String
    /// True for feedback that didn't write any metadata (item 4's
    /// single-frame-stack notice) — the toast shows `decisionText` verbatim,
    /// skipping the ✓/✕/★ symbol and "— ⌘Z undoes" suffix that would
    /// misleadingly imply something changed.
    public var isInformational: Bool

    public init(
        assetID: AssetID,
        filename: String,
        command: CullingCommand,
        decisionText: String,
        isInformational: Bool = false
    ) {
        self.assetID = assetID
        self.filename = filename
        self.command = command
        self.decisionText = decisionText
        self.isInformational = isInformational
    }

    /// True when the decision was a rating keystroke (including clear-to-zero),
    /// so the HUD's rating-echo window keys off the command itself rather than
    /// the rendered decision text.
    public var isRatingDecision: Bool {
        if case .rating = command { return true }
        return false
    }
}

public enum AutopilotScope: Equatable, Sendable {
    case visible
    case assetIDs([AssetID])
}

public struct AutopilotRunSummary: Equatable, Identifiable, Sendable {
    public var runID: AutopilotRunID
    public var keeperCount: Int
    public var rejectCount: Int
    public var keywordCount: Int
    public var stackCount: Int

    public init(
        runID: AutopilotRunID,
        keeperCount: Int,
        rejectCount: Int,
        keywordCount: Int,
        stackCount: Int
    ) {
        self.runID = runID
        self.keeperCount = keeperCount
        self.rejectCount = rejectCount
        self.keywordCount = keywordCount
        self.stackCount = stackCount
    }

    public var id: String { runID.rawValue }

    public var bannerText: String {
        // When the marquee keep/cut path honestly produces no verdicts (e.g. a
        // flat library of distinct singletons with no bursts to rank), never
        // report a bare "0 keepers · 0 rejects" after the user asked for keeps
        // and cuts — say what actually happened.
        if keeperCount == 0 && rejectCount == 0 {
            guard keywordCount > 0 else {
                return "These look too distinct to auto-rank — rate a few to rank"
            }
            let suggestions = keywordCount == 1
                ? "1 keyword suggestion"
                : "\(keywordCount) keyword suggestions"
            return "No clear cuts to propose — \(suggestions) ready to review"
        }
        var text = "\(keeperCount) keepers · \(rejectCount) rejects"
        if stackCount > 0 {
            text += " · dupes→stacks"
        }
        return text
    }
}

private struct CompareFlagChangeSummary {
    var changedCount = 0
    var pickedCount = 0
    var rejectedCount = 0
}

private struct WorkerImportContext {
    var source: URL
    var destinationRoot: URL?
    var secondCopyDestination: URL?
    var didAccessSource: Bool
    var didAccessDestination: Bool
    var didAccessSecondCopy: Bool
    var displayedCatalogedAssetID: AssetID?
}

private struct MetadataSyncStateSnapshot {
    var pendingItems: [MetadataSyncItem]
    var conflictItems: [MetadataSyncItem]
    var pendingCount: Int
    var conflictCount: Int
}

public enum MetadataSyncConflictSidecarMetadataState: Equatable {
    case none
    case readable(AssetMetadata)
    case unreadable
}

@Observable
public final class AppModel {
    public var sidebarSections: [SidebarSection]
    public var selectedView: LibraryViewMode {
        didSet {
            // .compare/.abCompare aren't sticky restore targets (item 1's
            // ⌘1 root cause): they're transient comparator overlays, not a
            // "home" sub-view. Without this, re-pressing ⌘1 while already in
            // Cull workspace but trapped in A/B Compare set
            // `selectedView = lastSubView[.cull]`, which *was* `.abCompare`
            // (recorded on the way in) — a silent no-op that read as ⌘1
            // being dead, when it was actually just restoring the trap.
            if selectedView != .compare && selectedView != .abCompare {
                lastSubView[selectedView.workspace] = selectedView
            }
            updateCompareSetAfterViewChange(from: oldValue)
            persistSessionState()
            if selectedView.workspace != oldValue.workspace {
                rebuildSidebarSections()
            }
            // The loupe's toast task re-fires whenever the view reappears,
            // re-rendering whatever feedback is still stored here — so a
            // stale decision toast (including the once-per-session hint
            // below) replayed on every re-entry to Cull. Expire it when the
            // workspace is left.
            if oldValue.workspace == .cull, selectedView.workspace != .cull {
                lastCullingMetadataDecision = nil
            }
            // The ? keymap overlay is the loupe's whole manual, but nothing
            // advertised it (persona-8) — announce it once per session on
            // first entry to the Cull workspace, via the decision toast.
            if selectedView.workspace == .cull,
               oldValue.workspace != .cull,
               !hasShownCullKeyboardHint {
                hasShownCullKeyboardHint = true
                lastCullingMetadataDecision = CullingMetadataDecisionFeedback(
                    assetID: selectedAsset?.id ?? assets.first?.id ?? AssetID(rawValue: "cull-keyboard-hint"),
                    filename: "",
                    command: .clearFlag,
                    decisionText: "Press ? for keyboard shortcuts",
                    isInformational: true
                )
            }
        }
    }

    /// Once per session: the keymap-overlay hint shown on first entry to Cull.
    private var hasShownCullKeyboardHint = false
    /// Which workspace `selectedView` currently belongs to.
    public var selectedWorkspace: Workspace {
        selectedView.workspace
    }

    /// Whether the Culling menu's shortcut items (Navigation/Ratings/Color
    /// Labels/Flags/Loupe/Scope) should be enabled right now. SwiftUI menu
    /// `.keyboardShortcut` bindings are workspace-blind — they fire from
    /// anywhere the app is frontmost, unlike `CullingKeyCaptureView`'s local
    /// key monitor, which `CullingKeyCaptureGate` scopes to the Cull
    /// workspace's loupe/compare/A-B sub-views. Mirroring that same gate here
    /// keeps the menu (bare "P"/"X"/etc, no modifiers) from writing flags or
    /// promoting frames while e.g. the Library Loupe is frontmost.
    public var isCullingMenuShortcutActive: Bool {
        CullingKeyCaptureGate.isActive(workspace: selectedWorkspace, selectedView: selectedView)
    }

    /// The sidebar sections for a given workspace. Library is navigation
    /// only (Collections/Saved Sets/Folders) — shared by every Library view,
    /// People included; Cull has its own sidebar (CullSidebarView).
    public func sidebarSections(for workspace: Workspace) -> [SidebarSection] {
        switch workspace {
        case .library:
            return Self.defaultSidebarSections(
                totalAssetCount: totalAssetCount,
                savedAssetSets: savedAssetSets,
                assetSetCounts: assetSetCounts,
                workSessionScopeCounts: workSessionScopeCounts,
                catalogFolders: catalogFolders,
                expandedFolderPaths: expandedFolderPaths,
                recentWork: recentWork,
                starredWork: starredWork,
                matchedWork: workHistorySearchResults
            )
        case .cull:
            return []
        }
    }
    /// The last sub-view shown in each workspace, so switching workspaces
    /// and back restores where the user left off.
    private var lastSubView: [Workspace: LibraryViewMode] = [:]
    public var assets: [Asset]
    public var totalAssetCount: Int
    // Global view history so ⌘⇧[ / ⌘⇧] step back and forth through the
    // sidebar destinations the user has visited this session.
    private var navigationBackStack: [SidebarRowTarget] = []
    private var navigationForwardStack: [SidebarRowTarget] = []
    private var currentNavigationTarget: SidebarRowTarget?
    private var isRestoringNavigation = false
    public var selectedAssetID: AssetID? {
        didSet {
            if oldValue != selectedAssetID {
                abContenderAssetID = nil
            }
            persistSessionState()
        }
    }
    // Loupe 1:1 zoom state: nil shows the fitted frame. Reset whenever the
    // selection moves so every new frame starts fitted.
    public private(set) var loupeZoomFocus: LoupeZoomFocus?
    // Detected-face targets for the current selection, reusing the Close-Ups
    // face-box pipeline (LoupeView populates this from on-demand detection).
    // Normalized (0...1) image-relative points, same space as LoupeZoomFocus.
    public private(set) var loupeFaceFocuses: [LoupeZoomFocus] = []
    // Which face in `loupeFaceFocuses` the Z shortcut last zoomed to, so a
    // repeated press cycles rather than re-picking the nearest face. Cleared
    // by any zoom that didn't come from face-cycling (manual pan/click,
    // fit-toggle, or selection change) so the next Z press starts fresh.
    public private(set) var loupeFaceZoomIndex: Int?
    // Cycles off/exposureLine/full for the loupe's EXIF overlay (I shortcut).
    public var exifOverlayLevel: ExifOverlayLevel = .off
    // Drives the ? key-map overlay, dismissed by Esc or a repeated ?.
    public var isKeyMapOverlayVisible = false
    /// Bumped on every culling keystroke so transient hover chrome (the cull
    /// loupe's hover-revealed decision controls) can hide when the user goes
    /// back to the keyboard.
    public private(set) var cullingKeystrokeToken = 0
    /// Which `CullingCommandMenuPresentation` section the ? overlay is
    /// scrolled to (item 3): keyboard-driven since the overlay owns
    /// navigation keys while visible and native NSScrollView keyboard
    /// scrolling never gets a first responder in this NSViewRepresentable
    /// overlay stack.
    public var keyMapOverlayScrollIndex = 0
    /// The subset of frames the loupe/filmstrip/grid navigate through while
    /// culling. `.all` means unfiltered. Cycled with the `s` shortcut.
    public private(set) var cullScope: CullScope = .all
    public private(set) var selectedBatchAssetIDs: Set<AssetID>
    /// Whether the on-demand inspector (⌘I) is shown, presented via
    /// `.inspector()` and gated by `WorkspaceChromePolicy.showsInspector`.
    public var isInspectorVisible = false
    /// Which stacked inspector section the ⌥⌘1..3 menu items (or a
    /// conflict deep-link) most recently asked to scroll to. Read alongside
    /// `inspectorScrollRequestToken`, which bumps on every request — even a
    /// repeat of the same section — so `InspectorView`'s `onChange` fires
    /// even when the user has since scrolled away and back.
    public private(set) var inspectorScrollTarget: InspectorTab = .info
    public private(set) var inspectorScrollRequestToken = 0
    private var selectedBatchAssetIDOrder: [AssetID]
    private var selectedBatchAssetSortKeys: [AssetID: Int]
    public var statusMessage: String?
    /// How long a transient confirmation toast ("Saved X") stays up before
    /// auto-clearing. Ongoing-work messages ("Importing …") never auto-clear.
    /// Injectable so tests don't wait out the real four seconds.
    var transientStatusMessageLifetime: Duration = .seconds(4)
    @ObservationIgnored private var transientStatusMessageClearTask: Task<Void, Never>?
    public var errorMessage: String?
    /// Import-scoped failures only, surfaced in the Activity Center's import
    /// row - unrelated model errors stay on `errorMessage` and never route here.
    public var importError: String?
    /// Drives the Activity Center popover (toolbar item + Window ▸ Activity).
    public var isActivityCenterPresented = false
    public private(set) var isExporting = false
    public var activeWork: AppWorkActivity?
    public var recentWork: [AppWorkActivity]
    public var starredWork: [AppWorkActivity]
    public var workHistorySearchResults: [AppWorkActivity]
    public var lastCullingMetadataDecision: CullingMetadataDecisionFeedback?
    public private(set) var cullingSessionCompletion: CullingSessionCompletionSummary?
    public private(set) var rejectRelocationSummary: RejectRelocationSummary?
    public private(set) var isRelocatingRejects = false
    private var rejectRelocationAbortRequested = false
    public private(set) var autopilotRunSummary: AutopilotRunSummary?
    public private(set) var pendingAutopilotProposals: [AutopilotProposal] = []
    public private(set) var isAutopilotReviewActive = false
    // The run-time metadata undo group for the most recent autopilot run's
    // tentative pick/reject/keyword writes (see `applyTentativeAutopilotProposals`)
    // and the run it belongs to, so `undoAutopilotRun` can revert the whole
    // batch and flip that run's proposals back to `pending` — independent of
    // the shared `metadataUndoStack` (which `commitAutopilotProposals`'
    // confirm step uses instead; reverting a catalog-only tentative write
    // through that generic, sidecar-syncing path would spuriously create a
    // sidecar for an asset that never had one). In-memory only.
    private var lastAutopilotRunUndoGroup: AutopilotTentativeChangeGroup?
    private var lastAutopilotRunUndoRunID: AutopilotRunID?
    // Tracks the in-progress whole-scope culling session (beginCullingSession
    // over a pure filter scope, selectedAssetSetID == nil) so
    // activeCullingSession(repository:) can still discover it for progress /
    // completion even though the filter scope — not the session's input
    // snapshot — stays the active selection. Cleared whenever the scope is
    // explicitly changed (clearLibraryQueryFilters).
    private var activeCullingSessionID: WorkSessionID?
    // Opt-in natural-language Ask translator. nil (default) keeps the Ask on
    // the always-available deterministic parser with byte-identical behavior.
    public var autopilotQueryTranslator: (any AutopilotQueryTranslator)?
    // Maps a scope's identity (sorted asset-id join) to the run that last
    // proposed for it, so re-running the same scope replaces its pending
    // proposals instead of stacking duplicates. In-memory only.
    private var lastAutopilotRunIDByScopeKey: [String: AutopilotRunID] = [:]
    // Tracks which stack-cull sessions came from beginStackCullingFromLatestImportCompletion()
    // and which import they scoped, so completion can offer to cull the
    // import's unstacked singles afterward. In-memory only; not persisted.
    private var stackCullingImportActivityIDBySessionID: [WorkSessionID: String] = [:]
    public var pendingMetadataSyncItems: [MetadataSyncItem]
    public var metadataSyncConflictItems: [MetadataSyncItem]
    public var pendingMetadataSyncCount: Int
    public var metadataSyncConflictCount: Int
    public var previewGenerationQueueStates: [PreviewGenerationQueueState]
    public var backgroundWorkQueue: BackgroundWorkQueue
    /// The query field's in-progress text. Committed filter state lives in
    /// `librarySearchText`; the field edits this draft so typing — and the
    /// first Esc, which clears only the field — never disturbs the active
    /// filter chips. In-memory only; programmatic changes to
    /// `librarySearchText` re-sync it via that property's didSet.
    public var librarySearchDraft: String = ""
    public var librarySearchText: String {
        didSet {
            librarySearchDraft = librarySearchText
            persistSessionState()
        }
    }
    public var keywordFilterText: String {
        didSet { persistSessionState() }
    }
    public var folderFilterText: String {
        didSet { persistSessionState() }
    }
    public var minimumRatingFilter: Int? {
        didSet { persistSessionState() }
    }
    public private(set) var librarySortOption: LibrarySortOption {
        didSet { persistSessionState() }
    }
    public var flagFilter: PickFlag? {
        didSet { persistSessionState() }
    }
    public var colorLabelFilter: ColorLabel? {
        didSet { persistSessionState() }
    }
    public var cameraFilterText: String {
        didSet { persistSessionState() }
    }
    public var lensFilterText: String {
        didSet { persistSessionState() }
    }
    public var minimumISOFilter: Int? {
        didSet { persistSessionState() }
    }
    public var captureDateStartFilter: Date? {
        didSet { persistSessionState() }
    }
    public var captureDateEndFilter: Date? {
        didSet { persistSessionState() }
    }
    public var availabilityFilter: SourceAvailability? {
        didSet { persistSessionState() }
    }
    public var evaluationKindFilter: EvaluationKind? {
        didSet { persistSessionState() }
    }
    public var needsKeywordsFilter: Bool {
        didSet { persistSessionState() }
    }
    public var needsEvaluationFilter: Bool {
        didSet { persistSessionState() }
    }
    public var likelyIssuesFilter: Bool {
        didSet { persistSessionState() }
    }
    public var potentialPicksFilter: Bool {
        didSet { persistSessionState() }
    }
    public var providerFailuresFilter: Bool {
        didSet { persistSessionState() }
    }
    public var metadataSyncPendingFilter: Bool {
        didSet { persistSessionState() }
    }
    public var metadataSyncConflictFilter: Bool {
        didSet { persistSessionState() }
    }
    /// The visible map region a cluster or top-location tap drilled into. Set
    /// from the map, applied through `.withinGeoBounds` in `currentLibraryQuery`,
    /// and cleared by `clearLibraryQueryFilters`. In-memory only — not part of
    /// session restore.
    public var geoBoundsFilter: GeoBounds?
    private var detachedLibraryFilterPredicates: [SetQuery.Predicate]
    public var savedAssetSets: [AssetSet]
    public var assetSetCounts: [AssetSetID: Int]
    public var workSessionScopeCounts: [WorkSessionID: Int]
    public var catalogFolders: [CatalogFolder]
    /// Folder-tree rows the user has expanded in the Folders sidebar
    /// section, keyed by the row's full folder path. In-memory only; not
    /// persisted across launches.
    public private(set) var expandedFolderPaths: Set<String>
    public var catalogTimelineDays: [CatalogTimelineDay]
    public private(set) var catalogPlaceClusters: [CatalogPlaceCluster] = []
    public private(set) var catalogTopLocations: [CatalogTopLocation] = []
    public private(set) var geotaggedCoverage = CatalogGeotaggedCoverage(geotaggedCount: 0, totalCount: 0)
    public var sourceRoots: [CatalogSourceRoot]
    public var sourceAvailabilitySummaries: [CatalogSourceAvailabilitySummary]
    public var catalogEvaluationKindSummaries: [CatalogEvaluationKindSummary]
    public var catalogPeople: [CatalogPerson]
    /// The best confirmed face per person (People-card key photo), derived at
    /// read time — kept in lockstep with `catalogPeople` via `loadCatalogPeople()`
    /// so a card never shows a face for a stale person set.
    public var personKeyFaces: [String: PersonKeyFace] = [:]
    public private(set) var peopleFaceSuggestions: [PeopleFaceSuggestion] = []
    public private(set) var peopleFaceObservationAssetCount = 0
    /// A person's PROPOSED photos (AI-unconfirmed face matches), shown as a
    /// separate section below the confirmed grid — kept out of `assets` so
    /// tentative matches never reach Picks/export/destructive ops. Populated
    /// only when the active query is exactly one `.person(name)` predicate;
    /// see `refreshProposedAssets()`.
    public var proposedPhotos: [ProposedPersonPhoto] = []
    /// The face row currently focused in the People inspector section (hover),
    /// so the loupe's face-box overlay (Task 8) can highlight the matching
    /// box, and vice versa — hovering a box focuses the list row.
    public var focusedFaceID: FaceID?
    public var reviewQueueCounts: [ReviewQueue: Int]
    public var selectedAssetSetID: AssetSetID? {
        didSet { persistSessionState() }
    }
    // Cached latest-import panel state so SwiftUI render passes never run catalog
    // queries; nil means the piece is rebuilt on the next getter access. Split in
    // two so per-preview queue transitions refresh only the cheap preview status,
    // not the full rebuild (asset loads, JSON decoding, stack detection).
    private var latestImportPresentationCore: LatestImportPresentationCore?
    private var latestImportPreviewStatus: LatestImportPreviewStatus?

    // Coalesced publication of background-work state: preview drains fire queue
    // transitions roughly twice per imported photo, and republishing tracked state
    // per transition re-renders every visible grid cell. Model logic reads the
    // always-current supervisor queue; views read the coalesced published copies.
    @ObservationIgnored
    private let backgroundWorkPublicationInterval: TimeInterval?

    @ObservationIgnored
    private let backgroundWorkPublicationScheduler: any WorkerTimeoutScheduling

    @ObservationIgnored
    private var backgroundWorkPublicationTimer: (any WorkerTimeoutCancellation)?

    @ObservationIgnored
    private var currentPreviewCacheGenerationsByAssetID: [AssetID: Int]

    @ObservationIgnored
    private var lastProcessedBackgroundWorkQueue: BackgroundWorkQueue?

    @ObservationIgnored
    private var pendingLatestImportPreviewStatusRefresh: Bool

    @ObservationIgnored
    private var pendingPreviewGenerationQueueStatesRefresh: Bool

    // Enables session restore and selects which UserDefaults it reads/writes; nil
    // (the default for every initializer) disables it entirely, so constructing an
    // AppModel never touches real app preferences unless a caller opts in.
    @ObservationIgnored
    private let sessionRestoreDefaults: UserDefaults?

    // Per-cell preview lookups hit the filesystem and scan the work queue; the grid
    // re-renders far more often than preview state can change, so both are memoized
    // until the next background-work publication or queue-state refresh.
    @ObservationIgnored
    private var gridPreviewURLCacheByAssetID: [AssetID: URL?]

    @ObservationIgnored
    private var gridPreviewStatusCacheByAssetID: [AssetID: AssetGridPreviewStatusPresentation?]

    @ObservationIgnored
    private var catalog: AppCatalog?

    @ObservationIgnored
    private let importTaskFactory: AppImportTaskFactory

    @ObservationIgnored
    private let cardImportTaskFactory: AppCardImportTaskFactory

    @ObservationIgnored
    private let workerSupervisor: WorkerSupervisor?

    @ObservationIgnored
    private let workerImportsEnabled: Bool

    @ObservationIgnored
    private let workerExecutableURL: URL?

    @ObservationIgnored
    private let resourceAccess: SecurityScopedResourceAccess

    @ObservationIgnored
    private var activeImportTask: Task<AppImportOutput, Error>?

    @ObservationIgnored
    private var displayedLocalImportCatalogedAssetID: AssetID?

    @ObservationIgnored
    private var workerImportContextsByItemID: [WorkSessionID: WorkerImportContext]

    // Captured per import at begin time; only one import runs at a time (isImporting guard).
    @ObservationIgnored
    private var importAutoEvaluationEnabled = true

    // Persisted "Autopilot on" toggle. When on, a finished import runs
    // runAutopilot over the imported set once its evaluations resolve. This
    // toggle only arms post-import runs; an on-demand run over the current
    // library scope is available separately via runAutopilotOnCurrentScope().
    public var autopilotEnabled = false {
        didSet {
            sessionRestoreDefaults?.set(autopilotEnabled, forKey: Self.autopilotEnabledDefaultsKey)
        }
    }
    static let autopilotEnabledDefaultsKey = "AppModel.autopilotEnabled"

    // A photographer's byline is the same on every frame. These persist across
    // sessions and pre-fill (never auto-write) the Creator/Copyright fields so a
    // wire shooter types them once, not every take.
    public var defaultCreator = "" {
        didSet {
            sessionRestoreDefaults?.set(defaultCreator, forKey: Self.defaultCreatorDefaultsKey)
        }
    }
    public var defaultCopyright = "" {
        didSet {
            sessionRestoreDefaults?.set(defaultCopyright, forKey: Self.defaultCopyrightDefaultsKey)
        }
    }
    static let defaultCreatorDefaultsKey = "AppModel.defaultCreator"
    static let defaultCopyrightDefaultsKey = "AppModel.defaultCopyright"

    // The folder a wire shooter dumps a card into is usually the same shoot
    // after shoot. This persists across sessions and pre-fills (never
    // auto-writes) the card-import destination picker.
    public var defaultCardImportDestination = "" {
        didSet {
            sessionRestoreDefaults?.set(defaultCardImportDestination, forKey: Self.defaultCardImportDestinationDefaultsKey)
        }
    }
    static let defaultCardImportDestinationDefaultsKey = "AppModel.defaultCardImportDestination"

    // Bumped by the Metadata ▸ Batch Metadata… menu command so the library view
    // can open the batch-metadata sheet from the keyboard without the action
    // having to live as a top-level toolbar button.
    public private(set) var batchMetadataRequestToken = 0
    public func requestBatchMetadataSheet() {
        batchMetadataRequestToken += 1
    }

    // Bumped by Edit ▸ Find ⌘F so LibraryGridView's @FocusState can move
    // keyboard focus into the query field. The query field only exists in the
    // Library *browse* views — not the Cull views, and not People (a Library
    // view that suppresses browse chrome) — so from anywhere that can't show
    // it, switch to the grid first rather than silently doing nothing.
    public private(set) var focusSearchRequestToken = 0
    public func requestFocusSearch() {
        if !WorkspaceChromePolicy.showsSearchField(selectedView) {
            selectedView = .grid
        }
        focusSearchRequestToken += 1
    }

    // Bumped by the File ▸ Import Folder…/Import From Card…/Import Path…/
    // Export… and Culling ▸ Move Rejects… menu commands (spec §6): these
    // actions open a panel or sheet that only the library view's own
    // @State can drive, so the menu commands (which only see AppModel) bump
    // a token here and LibraryGridView's onChange calls the same private
    // helper the matching toolbar button uses.
    public private(set) var importFolderRequestToken = 0
    public func requestImportFolder() {
        importFolderRequestToken += 1
    }

    public private(set) var importFromCardRequestToken = 0
    public func requestImportFromCard() {
        importFromCardRequestToken += 1
    }

    public private(set) var importPathRequestToken = 0
    public func requestImportPath() {
        importPathRequestToken += 1
    }

    public private(set) var exportRequestToken = 0
    // Export's sheet is a popover hosted on the Library toolbar's Export
    // button, which only the browse views show
    // (WorkspaceChromePolicy.showsExportButton) — not Cull, not People. So
    // bumping the token alone is a silent no-op while Cull is frontmost —
    // Maya's persona-1 finding ("File > Export does nothing in the Cull
    // workspace"). Switch to the grid first, so the token-consuming onChange
    // has somewhere to attach.
    public func requestExport() {
        if !WorkspaceChromePolicy.showsExportButton(selectedView) {
            selectedView = .grid
        }
        exportRequestToken += 1
    }

    public private(set) var moveRejectsRequestToken = 0
    public func requestMoveRejects() {
        moveRejectsRequestToken += 1
    }

    // Bumped by File ▸ New Set from Selection… and the Saved Sets sidebar
    // "+" (persona-2 item 2: set creation had no menu/sidebar discovery
    // path, only the result-header "Save ▾" control). Both reuse the same
    // manual-set save popover LibraryGridView's own Save ▾ control opens.
    public private(set) var newSetFromSelectionRequestToken = 0
    public func requestNewSetFromSelection() {
        newSetFromSelectionRequestToken += 1
    }

    public private(set) var moveRejectsToTrashRequestToken = 0
    public func requestMoveRejectsToTrash() {
        moveRejectsToTrashRequestToken += 1
    }

    // Set at import start from the import's autopilotAfterImport decision; the
    // imported asset IDs land in armedAutopilotImportAssetIDs once the import
    // completes, and autopilot runs once their evaluations all resolve.
    @ObservationIgnored
    private var autopilotArmedForActiveImport = false
    @ObservationIgnored
    private var armedAutopilotImportAssetIDs: Set<AssetID>?

    @ObservationIgnored
    private var pendingImportEvaluationAssetIDs: Set<AssetID> = []

    @ObservationIgnored
    private var activeSecurityScopedSourceRootURLs: [URL]

    @ObservationIgnored
    private var sourceRootBookmarkRepairPaths: Set<String>

    @ObservationIgnored
    private var evaluationAssetIDsByItemID: [WorkSessionID: AssetID]

    @ObservationIgnored
    private var evaluationProvidersByItemID: [WorkSessionID: String]

    @ObservationIgnored
    private var metadataSyncAssetIDsByItemID: [WorkSessionID: AssetID]

    @ObservationIgnored
    private var availabilityAssetIDsByItemID: [WorkSessionID: [AssetID]]

    private var previewCacheGenerationsByAssetID: [AssetID: Int]
    private var evaluationSignalGenerationsByAssetID: [AssetID: Int]
    /// IDs of activities recorded live in this app session (vs. restored
    /// from persisted history on launch) — see isCurrentSessionActivity.
    private var currentSessionActivityIDs: Set<String> = []
    private var metadataUndoStack: [MetadataChangeGroup]
    private var metadataRedoStack: [MetadataChangeGroup]
    private var compareAssetIDs: [AssetID]?
    /// The frame the user explicitly pinned as contender B in the A/B
    /// comparator. Nil means B follows the recommendation or the anchor's
    /// neighbor. Cleared whenever the anchor selection moves.
    public private(set) var abContenderAssetID: AssetID?

    public static let defaultEvaluationProviderName = "local-image-metrics"
    public static let defaultEvaluationProviderNames = [defaultEvaluationProviderName, "apple-vision", "core-image-faces"]
    private static let pendingPreviewRecoveryBatchSize = 40
    static let previewGenerationQueueStateDisplayLimit = pendingPreviewRecoveryBatchSize
    private static let pendingMetadataSyncRecoveryBatchSize = 200
    static let metadataSyncStateDisplayLimit = pendingMetadataSyncRecoveryBatchSize
    private static let currentScopeEvaluationBatchSize = 40
    private static let previewGenerationMaximumAutomaticAttempts = 3
    static let sourceAvailabilityBatchSize = 100
    private static let defaultCompareAssetLimit = 8
    private static let candidateStackMaximumCaptureGap: TimeInterval = 2
    private static let manualCullSessionTitle = "Compare Manual Cull"

    public var selectedAsset: Asset? {
        assets.first { $0.id == selectedAssetID }
    }

    public var selectedPreviewURL: URL? {
        selectedAssetID.flatMap { loupePreviewURL(for: $0) }
    }

    public var selectedPendingMetadataSyncItem: MetadataSyncItem? {
        guard let selectedAssetID else { return nil }
        return pendingMetadataSyncItems.first { $0.assetID == selectedAssetID }
    }

    public var selectedMetadataSyncConflictSidecarMetadataState: MetadataSyncConflictSidecarMetadataState {
        guard let selectedAssetID else {
            return .none
        }
        guard let conflictItem = metadataSyncConflictItems.first(where: { $0.assetID == selectedAssetID }) else {
            return .none
        }
        guard let sidecarData = try? Data(contentsOf: conflictItem.sidecarURL) else {
            return .unreadable
        }
        guard let metadata = try? XMPPacket.parse(sidecarData).metadata else {
            return .unreadable
        }
        return .readable(metadata)
    }

    public var selectedMetadataSyncConflictSidecarMetadata: AssetMetadata? {
        guard case .readable(let metadata) = selectedMetadataSyncConflictSidecarMetadataState else {
            return nil
        }
        return metadata
    }

    public var canRetrySelectedMetadataSync: Bool {
        guard let selectedAsset,
              let pendingItem = selectedPendingMetadataSyncItem else {
            return false
        }
        return canAutomaticallyRetryMetadataSync(for: selectedAsset, sidecarURL: pendingItem.sidecarURL)
    }

    public var canRetryPendingMetadataSyncInCurrentScope: Bool {
        guard metadataSyncPendingFilter,
              let catalog,
              workerSupervisor != nil else {
            return false
        }

        let candidates = try? metadataSyncRetryCandidatesInCurrentScope(
            repository: catalog.repository,
            limit: Self.metadataSyncStateDisplayLimit
        )
        return candidates?.isEmpty == false
    }

    public var selectedAssetPosition: Int? {
        guard let selectedAssetID,
              let selectedIndex = assets.firstIndex(where: { $0.id == selectedAssetID }) else {
            return nil
        }
        return selectedIndex + 1
    }

    public var selectedAssetPositionText: String? {
        guard let position = selectedAssetPosition else {
            return nil
        }
        let totalCount = max(totalAssetCount, position)
        return "Frame \(position) of \(totalCount)"
    }

    public var cullingProgressSummary: CullingProgressSummary {
        let decisionCounts = cullingDecisionCounts()
        return CullingProgressSummary(
            selectedPosition: selectedAssetPosition,
            positionText: selectedAssetPositionText,
            pickCount: decisionCounts.pickCount,
            rejectCount: decisionCounts.rejectCount,
            totalCount: totalAssetCount
        )
    }

    private func cullingDecisionCounts() -> (pickCount: Int, rejectCount: Int) {
        guard let catalog else {
            return loadedCullingDecisionCounts()
        }
        do {
            return (
                try cullingDecisionCount(flag: .pick, repository: catalog.repository),
                try cullingDecisionCount(flag: .reject, repository: catalog.repository)
            )
        } catch {
            return loadedCullingDecisionCounts()
        }
    }

    // Confirmed-only: a tentative AI pick/reject (autopilot proposal, not yet
    // confirmed by the user) counts as undecided here, matching the semantics
    // from before autopilot wrote tentative flags at run time (a pending
    // proposal never counted as a decision).
    private func cullingDecisionCount(flag: PickFlag, repository: CatalogRepository) throws -> Int {
        if let explicitAssetIDs = selectedExplicitAssetIDs {
            return try repository.assetCount(ids: explicitAssetIDs, confirmedFlag: flag)
        }
        let predicates = currentLibraryQuery()?.predicates ?? []
        return try repository.assetCount(matching: SetQuery(predicates: predicates), confirmedFlag: flag)
    }

    private func loadedCullingDecisionCounts() -> (pickCount: Int, rejectCount: Int) {
        (
            assets.filter { $0.metadata.confirmedProjection.flag == .pick }.count,
            assets.filter { $0.metadata.confirmedProjection.flag == .reject }.count
        )
    }

    public var libraryCountText: String {
        "\(assets.count) \(assets.count == 1 ? "photo" : "photos")"
    }

    public var libraryStatusText: String? {
        guard let statusMessage else { return nil }
        guard statusMessage.hasPrefix("Imported "),
              let previewStatus = activePreviewGenerationStatusText else {
            return statusMessage
        }
        return "\(statusMessage); \(previewStatus)"
    }

    // A transient confirmation left on screen indefinitely becomes noise
    // ("Saved …" still visible ten minutes later); ongoing-work messages are
    // left alone so an in-progress task's status is never yanked out from
    // under it. Invoked from the view's `.onChange(of: statusMessage)` —
    // `@Observable` and property observers don't mix under strict concurrency.
    @MainActor
    func scheduleTransientStatusMessageAutoClear() {
        transientStatusMessageClearTask?.cancel()
        transientStatusMessageClearTask = nil
        guard LibraryGridChromePolicy.isStatusMessageTransient(statusMessage) else { return }
        let message = statusMessage
        let lifetime = transientStatusMessageLifetime
        transientStatusMessageClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled, let self, self.statusMessage == message else { return }
            self.statusMessage = nil
        }
    }

    private var activePreviewGenerationStatusText: String? {
        activePreviewGenerationStatusText(assetIDs: nil)
    }

    private func activePreviewGenerationStatusText(assetIDs: Set<AssetID>?) -> String? {
        let previewItems = backgroundWorkQueue.items.filter { item in
            guard item.kind == .previewGeneration,
                  [.queued, .running, .paused].contains(item.status) else { return false }
            guard let assetIDs else { return true }
            guard let previewAssetID = Self.previewAssetID(from: item.id) else { return false }
            return assetIDs.contains(previewAssetID)
        }
        guard !previewItems.isEmpty else { return nil }
        if backgroundWorkQueue.isPaused || previewItems.contains(where: { $0.status == .paused }) {
            return "preview queue paused"
        }
        if previewItems.contains(where: { $0.status == .running }) {
            return "generating previews"
        }
        return "previews queued"
    }

    public var libraryTitle: String {
        if selectedView == .timeline {
            return "Timeline"
        }
        if selectedView == .people {
            return "People"
        }
        if selectedView == .map {
            return "Places"
        }
        if let selectedAssetSet {
            return selectedAssetSet.name
        }
        if currentLibraryQuery() != nil {
            return suggestedSavedSearchName
        }
        return "All Photographs"
    }

    public var catalogDisplayName: String {
        let name = catalog?.paths.root.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Local Catalog" : name
    }

    public var canUndoMetadataChange: Bool {
        !metadataUndoStack.isEmpty
    }

    public var canRedoMetadataChange: Bool {
        !metadataRedoStack.isEmpty
    }

    public var lastUndoableActionLabel: String? {
        metadataUndoStack.last?.label
    }

    public var visibleWorkActivity: AppWorkActivity? {
        visibleWorkActivities.first
    }

    public var visibleWorkActivities: [AppWorkActivity] {
        if let activeWork {
            return [activeWork]
        }
        let activeBackgroundItems = visibleActiveBackgroundWorkItems
        if !activeBackgroundItems.isEmpty {
            return activeBackgroundItems.map(AppWorkActivity.init)
        }
        if let backgroundItem = visibleInactiveBackgroundWorkItem {
            return [AppWorkActivity(workItem: backgroundItem)]
        }
        return recentWork.first.map { [$0] } ?? []
    }

    public var visibleImportActivity: AppWorkActivity? {
        if let activeWork, activeWork.kind == .ingest, [.queued, .running, .paused].contains(activeWork.status) {
            return activeWork
        }
        if let backgroundItem = activeBackgroundImportItem {
            return AppWorkActivity(workItem: backgroundItem)
        }
        return nil
    }

    public var selectedPreviewGenerationFailures: [PreviewGenerationQueueState] {
        guard let selectedAssetID else { return [] }
        return previewGenerationQueueStates.filter { state in
            state.item.assetID == selectedAssetID && state.attemptCount > 0
        }
    }

    public var canRetrySelectedPreviewGenerationFailures: Bool {
        guard workerSupervisor != nil,
              !selectedPreviewGenerationFailures.isEmpty else {
            return false
        }
        return selectedAsset?.availability.requiresCachedPreviewOnly != true
    }

    public var canPauseBackgroundWork: Bool {
        !backgroundWorkQueue.isPaused
            && backgroundWorkQueue.items.contains { [.queued, .running].contains($0.status) }
    }

    public var canResumeBackgroundWork: Bool {
        backgroundWorkQueue.isPaused
    }

    public var backgroundWorkPauseNotice: String? {
        guard backgroundWorkQueue.isPaused else { return nil }
        return backgroundWorkQueue.runningItems.isEmpty ? "Queue paused" : "Queue paused after current task"
    }

    public var isWorkerProcessRunning: Bool {
        workerSupervisor?.isWorkerProcessRunning ?? false
    }

    public var canStopIdleWorkerProcess: Bool {
        workerSupervisor?.canStopIdleWorkerProcess ?? false
    }

    public var idleWorkerStatusText: String? {
        canStopIdleWorkerProcess ? "Worker idle" : nil
    }

    public var canCancelBackgroundWork: Bool {
        backgroundWorkQueue.items.contains { [.queued, .running, .paused].contains($0.status) }
    }

    public func canCancelBackgroundWorkActivity(_ activity: AppWorkActivity) -> Bool {
        guard let item = backgroundWorkQueue.item(id: WorkSessionID(rawValue: activity.id)) else {
            return false
        }
        return Self.isActiveBackgroundWorkStatus(item.status)
    }

    /// All active work rolled up into one aggregate row per kind, for the
    /// Activity Center's per-kind progress bars. Folds in the foreground
    /// local import (`activeWork`, kind `.ingest`) alongside the background
    /// queue so import surfaces as the `.ingest` kind row.
    public var activeWorkKindRows: [ActivityKindRow] {
        let items = ([activeWork].compactMap { $0 }) + visibleActiveBackgroundWorkItems.map(AppWorkActivity.init)
        return ActivityKindRow.rows(from: items, canPause: canPauseBackgroundWork, canResume: canResumeBackgroundWork)
    }

    /// Aggregates background work, import progress, source availability, and
    /// XMP sync conflicts for the Activity Center toolbar popover - the single
    /// place a caller reads to render the toolbar's badge/progress and the
    /// popover's sections, replacing the former sidebar Sources/AI/Sync
    /// sections, the inspector-pinned Activity panel, and the footer/top-inset
    /// import surfaces.
    public var activityCenterPresentation: ActivityCenterPresentation {
        // Two independent row families, matching the retired sidebar's
        // "Sources" section: catalog-wide availability counts (no root
        // registration required) and bookmark-repair rows for registered
        // source roots whose security-scoped access needs to be refreshed.
        let availabilityRows = sourceAvailabilitySummaries
            .filter { $0.assetCount > 0 }
            .map { summary in
                SourceStatusRow(
                    id: "source-availability-\(summary.availability.rawValue)",
                    name: Self.sourceAvailabilityDisplayName(summary.availability),
                    availability: summary.availability,
                    reconnectActionID: nil,
                    refreshActionID: summary.availability.rawValue
                )
            }
        let repairRows = sourceRoots
            .filter { sourceRootBookmarkRepairPaths.contains($0.path) }
            .map { root in
                SourceStatusRow(
                    id: "source-bookmark-repair-\(root.path)",
                    name: root.name,
                    availability: .offline,
                    reconnectActionID: root.path,
                    refreshActionID: nil
                )
            }
        let sources = availabilityRows + repairRows
        let xmpConflicts = metadataSyncConflictItems.map { item in
            ConflictRow(
                assetID: item.assetID,
                displayName: item.sidecarURL.deletingPathExtension().lastPathComponent
            )
        }
        return ActivityCenterPresentation(
            kindRows: activeWorkKindRows,
            importActivity: visibleImportActivity,
            importError: importError,
            sources: sources,
            xmpConflicts: xmpConflicts,
            providerFailureCount: reviewQueueCounts[.providerFailures] ?? 0
        )
    }

    /// Deep-links from the Activity Center's conflict row(s) back to the
    /// affected assets: switches to Library, filters to the XMP-conflict
    /// scope, selects the assets, and reveals the inspector.
    public func revealConflicts(_ assetIDs: [AssetID]) throws {
        guard !assetIDs.isEmpty else { return }
        // Land in Grid regardless of which Library subview was last used —
        // the conflicted selection is only visible there.
        selectedView = .grid
        selectedAssetID = assetIDs.first
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        metadataSyncConflictFilter = true
        try reload()
        clearBatchSelection()
        for assetID in assetIDs {
            setBatchSelection(assetID, isSelected: true)
        }
        // The conflict resolver lives in the Info section (Task 11); scroll
        // there so the deep-link lands on it instead of wherever the
        // inspector was last scrolled.
        scrollInspector(to: .info)
        isInspectorVisible = true
    }

    public var diagnosticsSnapshot: AppDiagnosticsSnapshot {
        let paths = catalog?.paths
        return AppDiagnosticsSnapshot(
            catalogRootPath: paths?.root.path,
            catalogDatabasePath: paths?.catalogURL.path,
            previewCacheRootPath: paths?.previewCacheRoot.path,
            workerExecutablePath: workerExecutableURL?.path,
            workerConfigured: workerExecutableURL != nil,
            workerEnabled: workerSupervisor != nil,
            workerProcessRunning: isWorkerProcessRunning,
            loadedAssetCount: assets.count,
            totalAssetCount: totalAssetCount,
            pendingBackgroundWorkCount: backgroundWorkQueue.items.filter { Self.isActiveBackgroundWorkStatus($0.status) }.count,
            pendingMetadataSyncCount: pendingMetadataSyncCount,
            metadataSyncConflictCount: metadataSyncConflictCount,
            backgroundWork: Self.diagnosticsBackgroundWork(backgroundWorkQueue),
            sourceAvailabilityCounts: Self.sourceAvailabilityCounts(sourceAvailabilitySummaries),
            sourceRoots: sourceRoots.map {
                AppDiagnosticsSourceRoot(
                    path: $0.path,
                    name: $0.name,
                    assetCount: $0.assetCount,
                    unavailableAssetCount: $0.unavailableAssetCount,
                    hasSecurityScopedBookmark: $0.securityScopedBookmarkData != nil,
                    needsSecurityScopedBookmarkRepair: sourceRootBookmarkRepairPaths.contains($0.path)
                )
            },
            recentFailures: diagnosticsRecentFailures()
        )
    }

    public var diagnosticsReportText: String {
        AppDiagnosticsReport.text(for: diagnosticsSnapshot)
    }

    public var isImporting: Bool {
        if activeWork?.kind == .ingest, let status = activeWork?.status, Self.isActiveBackgroundWorkStatus(status) {
            return true
        }
        guard !workerImportContextsByItemID.isEmpty else { return false }
        // Read the always-current supervisor queue: the published copy can lag
        // by a coalescing interval, which would let a second import slip past
        // the "Another import is already running" guard.
        return workerImportContextsByItemID.keys.contains { itemID in
            guard let item = currentBackgroundWorkQueue.item(id: itemID), item.kind == .ingest else { return false }
            return Self.isActiveBackgroundWorkStatus(item.status)
        }
    }

    public var canRequestSelectedAssetEvaluation: Bool {
        guard workerSupervisor != nil, let selectedAssetID else { return false }
        return hasCachedPreview(for: selectedAssetID)
    }

    public func canRetrySelectedProviderFailure(provider: String) -> Bool {
        guard workerSupervisor != nil,
              let selectedAssetID,
              selectedProviderFailures.contains(where: { $0.provider == provider }),
              hasCachedPreview(for: selectedAssetID) else {
            return false
        }
        let itemID = WorkSessionID(rawValue: "evaluation-\(selectedAssetID.rawValue)-\(provider)")
        if let existingItem = backgroundWorkQueue.item(id: itemID),
           Self.isActiveBackgroundWorkStatus(existingItem.status) {
            return false
        }
        return true
    }

    public var canRequestVisibleAssetEvaluations: Bool {
        workerSupervisor != nil && assets.contains { hasCachedPreview(for: $0.id) }
    }

    public var canRequestLatestImportAssetEvaluations: Bool {
        latestImportCoreRebuildingIfNeeded().canRequestAssetEvaluations
    }

    public var canRequestCurrentScopeAssetEvaluations: Bool {
        guard workerSupervisor != nil,
              let catalog,
              let cachedAssetIDs = try? currentScopeCachedPreviewAssetIDs(repository: catalog.repository, limit: 1) else {
            return false
        }
        return !cachedAssetIDs.isEmpty
    }

    public var canRequestPeopleFaceScan: Bool {
        canRequestCurrentScopeAssetEvaluations
    }

    /// True when any catalog source root is unreachable — its recorded path
    /// no longer exists on this machine, or assets under it are offline.
    /// The People workspace uses this to say "sources offline" instead of
    /// advertising a scan that cannot enqueue any work.
    public var hasUnavailableSourceRoots: Bool {
        sourceRoots.contains { root in
            root.unavailableAssetCount > 0 || !FileManager.default.fileExists(atPath: root.path)
        }
    }

    public var canRequestCompareAssetEvaluations: Bool {
        workerSupervisor != nil && compareAssets().contains { hasCachedPreview(for: $0.id) }
    }

    public var canRefreshVisibleAssetAvailability: Bool {
        catalog != nil && !assets.isEmpty
    }

    public var canReconnectSourceRoot: Bool {
        catalog != nil && !suggestedReconnectOldRootPath.isEmpty
    }

    public var selectedEvaluationSignals: [EvaluationSignal] {
        guard let selectedAssetID else { return [] }
        return evaluationSignals(for: selectedAssetID)
    }

    public var selectedProviderFailures: [CatalogEvaluationFailure] {
        guard let catalog,
              let selectedAssetID else {
            return []
        }
        return (try? catalog.repository.evaluationFailures(assetID: selectedAssetID)) ?? []
    }

    public func evaluationSignals(for assetID: AssetID) -> [EvaluationSignal] {
        guard let catalog else { return [] }
        _ = evaluationSignalGeneration(for: assetID)
        return (try? catalog.repository.evaluationSignals(assetID: assetID)) ?? []
    }

    public var selectedSuggestedKeywords: [KeywordSuggestion] {
        guard let selectedAsset else { return [] }
        return Self.keywordSuggestions(
            from: selectedEvaluationSignals,
            existingKeywords: selectedAsset.metadata.keywords
        )
    }

    public var selectedSuggestedCaptions: [CaptionSuggestion] {
        guard let selectedAsset,
              selectedAsset.metadata.caption == nil else {
            return []
        }
        return Self.captionSuggestions(from: selectedEvaluationSignals)
    }

    public var visibleBatchKeywordSuggestions: [BatchKeywordSuggestion] {
        batchKeywordSuggestions(for: assets)
    }

    public var selectedBatchKeywordSuggestions: [BatchKeywordSuggestion] {
        guard let catalog,
              !selectedBatchAssetIDsInCatalogOrder.isEmpty,
              let selectedAssets = try? catalog.repository.assets(
                ids: selectedBatchAssetIDsInCatalogOrder,
                limit: selectedBatchAssetIDsInCatalogOrder.count
              ) else {
            return []
        }
        return batchKeywordSuggestions(for: selectedAssets)
    }

    public var latestImportBatchKeywordSuggestions: [BatchKeywordSuggestion] {
        latestImportCoreRebuildingIfNeeded().batchKeywordSuggestions
    }

    public var latestImportFaceReviewAssetCount: Int {
        latestImportCoreRebuildingIfNeeded().faceReviewAssetCount
    }

    public var latestImportFlaggedReviewAssetCount: Int {
        latestImportCoreRebuildingIfNeeded().flaggedReviewAssetCount
    }

    public var currentScopeBatchKeywordSuggestions: [BatchKeywordSuggestion] {
        guard let catalog,
              let assetIDs = try? currentAssetScopeIDs(repository: catalog.repository),
              !assetIDs.isEmpty,
              let scopeAssets = try? catalog.repository.assets(ids: assetIDs, limit: assetIDs.count) else {
            return []
        }
        return batchKeywordSuggestions(for: scopeAssets)
    }

    public var starredAssetSets: [AssetSet] {
        Self.visibleSavedAssetSets(savedAssetSets).filter(\.starred)
    }

    public var canSaveCurrentLibraryQuery: Bool {
        currentLibraryQuery() != nil
    }

    public var hasActiveLibraryFilters: Bool {
        selectedAssetSetID != nil || currentLibraryQuery() != nil
    }

    public var activeLibraryFilterChips: [String] {
        activeLibraryFilterRows.map(\.title)
    }

    public var activeLibraryFilterRows: [ActiveLibraryFilterRow] {
        var rows: [ActiveLibraryFilterRow] = []
        if let selectedAssetSet {
            Self.append(ActiveLibraryFilterRow(title: selectedAssetSet.name, target: .assetSet(selectedAssetSet.id)), to: &rows)
        }
        if let selectedDynamicSetQuery {
            for predicate in selectedDynamicSetQuery.predicates {
                guard let row = Self.activeLibraryFilterRow(for: predicate) else { continue }
                Self.append(row, to: &rows)
            }
        }
        for predicate in detachedLibraryFilterPredicates {
            guard let row = Self.activeLibraryFilterRow(for: predicate) else { continue }
            Self.append(row, to: &rows)
        }
        let searchIntent = LibrarySearchIntent.parse(librarySearchText)
        if let residualSearch = searchIntent.residualText {
            Self.append(
                ActiveLibraryFilterRow(title: "Search: \(residualSearch)", isPlainSearchFallback: true),
                to: &rows
            )
        }
        for (index, chip) in searchIntent.chips.enumerated() {
            let target = searchIntent.predicates.indices.contains(index)
                ? Self.sidebarTarget(for: searchIntent.predicates[index])
                : nil
            Self.append(ActiveLibraryFilterRow(title: chip, target: target), to: &rows)
        }
        let trimmedKeyword = keywordFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            Self.append(ActiveLibraryFilterRow(title: "Keyword: \(trimmedKeyword)"), to: &rows)
        }
        let trimmedFolder = folderFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFolder.isEmpty {
            Self.append(ActiveLibraryFilterRow(title: "Folder: \(URL(fileURLWithPath: trimmedFolder).lastPathComponent)"), to: &rows)
        }
        if let minimumRatingFilter {
            Self.append(
                ActiveLibraryFilterRow(
                    title: "Rating >= \(minimumRatingFilter)",
                    target: minimumRatingFilter == 5 ? .reviewQueue(.fiveStars) : nil
                ),
                to: &rows
            )
        }
        if let flagFilter {
            Self.append(
                ActiveLibraryFilterRow(title: flagFilter.rawValue.capitalized, target: Self.sidebarTarget(for: .flag(flagFilter))),
                to: &rows
            )
        }
        if let colorLabelFilter {
            Self.append(ActiveLibraryFilterRow(title: "\(colorLabelFilter.rawValue.capitalized) Label"), to: &rows)
        }
        let trimmedCamera = cameraFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCamera.isEmpty {
            Self.append(ActiveLibraryFilterRow(title: "Camera: \(trimmedCamera)"), to: &rows)
        }
        let trimmedLens = lensFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLens.isEmpty {
            Self.append(ActiveLibraryFilterRow(title: "Lens: \(trimmedLens)"), to: &rows)
        }
        if let minimumISOFilter {
            Self.append(ActiveLibraryFilterRow(title: "ISO >= \(minimumISOFilter)"), to: &rows)
        }
        if let captureDateStartFilter {
            Self.append(ActiveLibraryFilterRow(title: "From \(captureDateStartFilter.formatted(date: .abbreviated, time: .omitted))"), to: &rows)
        }
        if let captureDateEndFilter {
            Self.append(ActiveLibraryFilterRow(title: "Before \(captureDateEndFilter.formatted(date: .abbreviated, time: .omitted))"), to: &rows)
        }
        if let availabilityFilter {
            Self.append(
                ActiveLibraryFilterRow(title: "Source: \(availabilityFilter.rawValue.capitalized)", target: .sourceAvailability(availabilityFilter)),
                to: &rows
            )
        }
        if let evaluationKindFilter {
            Self.append(
                Self.activeLibraryFilterRow(forEvaluationKind: evaluationKindFilter),
                to: &rows
            )
        }
        if needsKeywordsFilter {
            Self.append(ActiveLibraryFilterRow(title: "Needs Keywords", target: .reviewQueue(.needsKeywords)), to: &rows)
        }
        if needsEvaluationFilter {
            Self.append(ActiveLibraryFilterRow(title: "Not analyzed yet", target: .reviewQueue(.needsEvaluation)), to: &rows)
        }
        if likelyIssuesFilter {
            Self.append(ActiveLibraryFilterRow(title: "Likely Issues", target: .reviewQueue(.likelyIssues)), to: &rows)
        }
        if potentialPicksFilter {
            Self.append(ActiveLibraryFilterRow(title: "Potential Picks", target: .reviewQueue(.potentialPicks)), to: &rows)
        }
        if providerFailuresFilter {
            Self.append(ActiveLibraryFilterRow(title: "Analysis Failures", target: .reviewQueue(.providerFailures)), to: &rows)
        }
        if metadataSyncPendingFilter {
            Self.append(ActiveLibraryFilterRow(title: "XMP Pending", target: .metadataSyncPending), to: &rows)
        }
        if metadataSyncConflictFilter {
            Self.append(ActiveLibraryFilterRow(title: "XMP Conflicts", target: .metadataSyncConflicts), to: &rows)
        }
        return rows
    }

    public var canSaveSelectedAssetAsManualSet: Bool {
        catalog != nil && !currentManualSelectionAssetIDs.isEmpty
    }

    public var canSaveCurrentAssetScopeSnapshot: Bool {
        catalog != nil && !assets.isEmpty
    }

    public var canBeginCullingSession: Bool {
        catalog != nil && !assets.isEmpty
    }

    public var latestImportCompletionSummary: ImportCompletionSummary? {
        let core = latestImportCoreRebuildingIfNeeded()
        guard var summary = core.summary else { return nil }
        let previewStatus = latestImportPreviewStatusRebuildingIfNeeded(core: core)
        summary.previewFailureCount = previewStatus.previewFailureCount
        summary.failureText = previewStatus.failureText
        summary.previewStatusText = previewStatus.previewStatusText
        return summary
    }

    /// Marks the cached latest-import panel state stale so the next getter access
    /// rebuilds it from the catalog. Call this from every event that can change the
    /// panel; the getters themselves must stay cheap because SwiftUI evaluates them
    /// on every render pass.
    public func refreshLatestImportPresentation() {
        latestImportPresentationCore = nil
        latestImportPreviewStatus = nil
    }

    /// Marks only the live preview-drain status stale. Preview queue transitions
    /// fire for every preview of an import, so they must not trigger the full
    /// presentation rebuild.
    private func refreshLatestImportPreviewStatus() {
        latestImportPreviewStatus = nil
        // A newly cached preview can flip the cached core's evaluate gate; patch
        // it in place instead of paying the full core rebuild per preview
        // transition. The recheck short-circuits on the first cached preview.
        if let core = latestImportPresentationCore,
           !core.canRequestAssetEvaluations,
           canRequestLatestImportAssetEvaluations(assetIDs: core.outputAssetIDs) {
            var updatedCore = core
            updatedCore.canRequestAssetEvaluations = true
            latestImportPresentationCore = updatedCore
        }
    }

    private func latestImportCoreRebuildingIfNeeded() -> LatestImportPresentationCore {
        if let latestImportPresentationCore {
            return latestImportPresentationCore
        }
        let core = buildLatestImportPresentationCore()
        latestImportPresentationCore = core
        return core
    }

    private func latestImportPreviewStatusRebuildingIfNeeded(core: LatestImportPresentationCore) -> LatestImportPreviewStatus {
        if let latestImportPreviewStatus {
            return latestImportPreviewStatus
        }
        let previewStatus = buildLatestImportPreviewStatus(core: core)
        latestImportPreviewStatus = previewStatus
        return previewStatus
    }

    private func buildLatestImportPresentationCore() -> LatestImportPresentationCore {
        guard let activity = recentWork.first(where: Self.isImportCompletionActivity) else {
            return .empty
        }
        let outputAssetIDs: [AssetID]
        if let catalog {
            outputAssetIDs = (try? latestImportOutputAssetIDs(activityID: activity.id, repository: catalog.repository)) ?? []
        } else {
            outputAssetIDs = []
        }
        let summary = latestImportCompletionSummary(activity: activity)
        return LatestImportPresentationCore(
            summary: summary,
            flaggedReviewAssetCount: latestImportFlaggedReviewAssetCount(summary: summary),
            faceReviewAssetCount: latestImportFaceReviewAssetCount(assetIDs: outputAssetIDs),
            batchKeywordSuggestions: latestImportBatchKeywordSuggestions(assetIDs: outputAssetIDs),
            canRequestAssetEvaluations: canRequestLatestImportAssetEvaluations(assetIDs: outputAssetIDs),
            outputAssetIDs: outputAssetIDs
        )
    }

    private func buildLatestImportPreviewStatus(core: LatestImportPresentationCore) -> LatestImportPreviewStatus {
        guard let summary = core.summary,
              let activity = recentWork.first(where: Self.isImportCompletionActivity) else {
            return .empty
        }
        let previewFailureCount = latestImportPreviewFailureCount(activity: activity, assetIDs: core.outputAssetIDs)
        let failureText = previewFailureCount > 0
            ? "\(previewFailureCount) preview \(previewFailureCount == 1 ? "failure" : "failures")"
            : nil
        return LatestImportPreviewStatus(
            previewFailureCount: previewFailureCount,
            failureText: failureText,
            previewStatusText: latestImportPreviewStatusText(
                assetIDs: core.outputAssetIDs,
                hasImportedPhotos: summary.importedPhotoCount > 0,
                failureText: failureText
            )
        )
    }

    private func latestImportBatchKeywordSuggestions(assetIDs: [AssetID]) -> [BatchKeywordSuggestion] {
        guard let catalog,
              !assetIDs.isEmpty,
              let importedAssets = try? catalog.repository.assets(ids: assetIDs, limit: assetIDs.count) else {
            return []
        }
        return batchKeywordSuggestions(for: importedAssets)
    }

    private func latestImportFaceReviewAssetCount(assetIDs: [AssetID]) -> Int {
        guard let catalog,
              !assetIDs.isEmpty,
              let faceAssetIDs = try? catalog.repository.assetIDs(
                ids: assetIDs,
                matching: Self.reviewQueueQuery(.facesFound)
              ) else {
            return 0
        }
        return faceAssetIDs.count
    }

    private func latestImportFlaggedReviewAssetCount(summary: ImportCompletionSummary?) -> Int {
        guard let catalog,
              let summary,
              let count = try? catalog.repository.assetCount(
                matching: SetQuery(predicates: [
                    .importBatch(summary.activityID),
                    .likelyIssue
                ])
              ) else {
            return 0
        }
        return count
    }

    private func canRequestLatestImportAssetEvaluations(assetIDs: [AssetID]) -> Bool {
        guard workerSupervisor != nil, catalog != nil else {
            return false
        }
        return assetIDs.contains { hasCachedPreview(for: $0) }
    }

    // The preview fields hold placeholders here; latestImportCompletionSummary
    // patches in the separately cached LatestImportPreviewStatus.
    private func latestImportCompletionSummary(activity: AppWorkActivity) -> ImportCompletionSummary {
        let importedPhotoCount = activity.totalUnitCount ?? activity.completedUnitCount
        let newPhotoCount = activity.completedUnitCount
        let existingPhotoCount = max(importedPhotoCount - newPhotoCount, 0)
        let hasImportedPhotos = importedPhotoCount > 0
        let stackSummary = hasImportedPhotos ? latestImportStackSummary(activity: activity) : (stackCount: 0, stackedPhotoCount: 0)
        return ImportCompletionSummary(
            activityID: activity.id,
            title: "Import complete",
            detail: activity.detail,
            importedPhotoCount: importedPhotoCount,
            photoCountText: Self.photoCountDescription(importedPhotoCount),
            newPhotoCount: newPhotoCount,
            existingPhotoCount: existingPhotoCount,
            previewFailureCount: 0,
            failureText: nil,
            previewStatusText: "",
            issues: activity.issues,
            stackCount: stackSummary.stackCount,
            stackedPhotoCount: stackSummary.stackedPhotoCount,
            cullingSessionName: "\(activity.detail) Cull"
        )
    }

    private func latestImportPreviewStatusText(
        assetIDs: [AssetID],
        hasImportedPhotos: Bool,
        failureText: String?
    ) -> String {
        if let failureText {
            return failureText
        }
        guard hasImportedPhotos else {
            return "No previews needed"
        }
        guard let catalog else {
            return activePreviewGenerationStatusText ?? "Previews ready"
        }
        do {
            let pendingPreviewCount = try catalog.repository.previewGenerationPendingAssetCount(assetIDs: assetIDs)
            guard pendingPreviewCount > 0 else {
                return "Previews ready"
            }
            return activePreviewGenerationStatusText(assetIDs: Set(assetIDs)) ?? "previews queued"
        } catch {
            return activePreviewGenerationStatusText ?? "Previews ready"
        }
    }

    private func latestImportPreviewFailureCount(activity: AppWorkActivity, assetIDs: [AssetID]) -> Int {
        guard let catalog else { return activity.failureCount }
        do {
            let deferredFailureCount = try catalog.repository.previewGenerationFailureAssetCount(assetIDs: assetIDs)
            return max(activity.failureCount, deferredFailureCount)
        } catch {
            return activity.failureCount
        }
    }

    private func latestImportStackSummary(activity: AppWorkActivity) -> (stackCount: Int, stackedPhotoCount: Int) {
        guard let catalog else { return (0, 0) }
        do {
            let stacks = try latestImportStacks(activityID: activity.id, repository: catalog.repository)
            return (
                stackCount: stacks.count,
                stackedPhotoCount: stacks.reduce(0) { $0 + $1.assetIDs.count }
            )
        } catch {
            return (0, 0)
        }
    }

    public var suggestedSavedSearchName: String {
        var parts: [String] = []
        let searchIntent = LibrarySearchIntent.parse(librarySearchText)
        if let residualSearch = searchIntent.residualText {
            parts.append(residualSearch)
        }
        for namePart in searchIntent.nameParts {
            Self.append(namePart, to: &parts)
        }
        let trimmedKeyword = keywordFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            Self.append(trimmedKeyword, to: &parts)
        }
        let trimmedFolder = folderFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFolder.isEmpty {
            Self.append(URL(fileURLWithPath: trimmedFolder).lastPathComponent, to: &parts)
        }
        if let minimumRatingFilter {
            Self.append("\(minimumRatingFilter)+ Stars", to: &parts)
        }
        if let flagFilter {
            Self.append(flagFilter.rawValue.capitalized, to: &parts)
        }
        if let colorLabelFilter {
            Self.append("\(colorLabelFilter.rawValue.capitalized) Label", to: &parts)
        }
        let trimmedCamera = cameraFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCamera.isEmpty {
            Self.append(trimmedCamera, to: &parts)
        }
        let trimmedLens = lensFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLens.isEmpty {
            Self.append(trimmedLens, to: &parts)
        }
        if let minimumISOFilter {
            Self.append("ISO \(minimumISOFilter)+", to: &parts)
        }
        if let availabilityFilter {
            Self.append(availabilityFilter.rawValue.capitalized, to: &parts)
        }
        if let evaluationKindFilter {
            Self.append(Self.filterName(for: evaluationKindFilter), to: &parts)
        }
        if needsKeywordsFilter {
            Self.append("Needs Keywords", to: &parts)
        }
        if needsEvaluationFilter {
            Self.append("Not analyzed yet", to: &parts)
        }
        if likelyIssuesFilter {
            Self.append("Likely Issues", to: &parts)
        }
        if potentialPicksFilter {
            Self.append("Potential Picks", to: &parts)
        }
        if providerFailuresFilter {
            Self.append("Analysis Failures", to: &parts)
        }
        if metadataSyncPendingFilter {
            Self.append("XMP Pending", to: &parts)
        }
        if metadataSyncConflictFilter {
            Self.append("XMP Conflicts", to: &parts)
        }
        return parts.isEmpty ? "Saved Search" : parts.joined(separator: " ")
    }

    public var suggestedManualSetName: String {
        let batchAssetIDs = selectedBatchAssetIDsInCatalogOrder
        if batchAssetIDs.count > 1 {
            return "\(batchAssetIDs.count) Selected Photos"
        }
        if let batchAssetID = batchAssetIDs.first,
           let batchAsset = assets.first(where: { $0.id == batchAssetID }) {
            return Self.manualSetName(for: batchAsset)
        }
        if batchAssetIDs.count == 1 {
            return "1 Selected Photo"
        }
        guard let selectedAsset else {
            return "Selection"
        }
        return Self.manualSetName(for: selectedAsset)
    }

    public var suggestedSnapshotSetName: String {
        if let selectedAssetSet {
            return "\(selectedAssetSet.name) Snapshot"
        }
        if currentLibraryQuery() != nil {
            return "\(suggestedSavedSearchName) Snapshot"
        }
        return "Catalog Snapshot"
    }

    public var suggestedCullingSessionName: String {
        if let selectedAssetSet {
            return "\(selectedAssetSet.name) Cull"
        }
        if currentLibraryQuery() != nil {
            return "\(suggestedSavedSearchName) Cull"
        }
        return "Catalog Cull"
    }

    public var canConfirmSelectedPerson: Bool {
        catalog != nil && !selectedPeopleCandidateAssetIDs.isEmpty
    }

    public var canDismissSelectedFaceReviewAssets: Bool {
        catalog != nil && !selectedPeopleCandidateAssetIDs.isEmpty
    }

    /// How many photos "Name Selection" would attach to the new person —
    /// surfaced in the sheet subtitle so a stale selection is visible
    /// before the confirming click.
    public var selectedPeopleCandidateAssetCount: Int {
        selectedPeopleCandidateAssetIDs.count
    }

    private var selectedPeopleCandidateAssetIDs: [AssetID] {
        let batchAssetIDs = selectedBatchAssetIDsInCatalogOrder
        if !batchAssetIDs.isEmpty {
            return batchAssetIDs
        }
        return selectedAssetID.map { [$0] } ?? []
    }

    public var suggestedReconnectOldRootPath: String {
        if let sourceRoot = sourceRoots.first(where: { $0.unavailableAssetCount > 0 }) {
            return sourceRoot.path
        }
        let unavailableFolders = assets
            .filter { $0.availability != .online }
            .map { $0.originalURL.deletingLastPathComponent().standardizedFileURL.path }
        return Self.commonAncestorPath(for: unavailableFolders) ?? ""
    }

    /// Loads confirmed-people + their key faces together so People cards never
    /// show a face for a stale person set. Replaces bare
    /// `catalogPeople = try catalog.repository.people()` assignments.
    private func loadCatalogPeople() throws {
        guard let catalog else { return }
        catalogPeople = try catalog.repository.people()
        personKeyFaces = try catalog.repository.keyFacesByPerson(provenance: AppleVisionEvaluationProvider.faceProvenance)
    }

    @discardableResult
    public func confirmSelectedAssetsAsPerson(named name: String, id: String = "person-\(UUID().uuidString)") throws -> CatalogPerson {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TeststripError.invalidState("person name is required")
        }
        let assetIDs = selectedPeopleCandidateAssetIDs
        guard !assetIDs.isEmpty else {
            throw TeststripError.invalidState("select photos before naming a person")
        }

        let targetID = existingPersonID(matchingName: trimmedName) ?? id
        try catalog.repository.upsertPerson(id: targetID, name: trimmedName)
        try catalog.repository.assignAssets(assetIDs, toPersonID: targetID)
        try loadCatalogPeople()
        refreshCatalogEvaluationKindSummaries()
        refreshPeopleFaceSuggestions()
        try loadCatalogPage(preferredSelection: nil)
        guard let person = catalogPeople.first(where: { $0.id == targetID }) else {
            throw CatalogError.notFound(targetID)
        }
        return person
    }

    /// An exact name match (trimmed, case-insensitive — the same
    /// normalization `showPersonPhotos`'s `person:` filter uses via
    /// `COLLATE NOCASE`) attaches confirmed assets/faces to the existing
    /// person instead of minting a duplicate.
    private func existingPersonID(matchingName trimmedName: String) -> String? {
        catalogPeople.first { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }?.id
    }

    public func mergePerson(sourceID: String, into targetID: String) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        try catalog.repository.mergePerson(sourceID: sourceID, into: targetID)
        try loadCatalogPeople()
        refreshPeopleFaceSuggestions()
    }

    public func dismissSelectedFaceReviewAssets() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetIDs = selectedPeopleCandidateAssetIDs
        guard !assetIDs.isEmpty else {
            throw TeststripError.invalidState("select photos before dismissing face review")
        }
        try catalog.repository.dismissFaceAssets(assetIDs)
        try loadCatalogPeople()
        refreshCatalogEvaluationKindSummaries()
        refreshPeopleFaceSuggestions()
        try loadCatalogPage(preferredSelection: nil)
    }

    public static let maximumFaceSuggestionInputCount = 2000

    public func refreshPeopleFaceSuggestions() {
        guard let catalog else { return }
        do {
            let provenance = AppleVisionEvaluationProvider.faceProvenance
            let unassigned = try catalog.repository.unassignedFaceObservations(
                provenance: provenance,
                limit: Self.maximumFaceSuggestionInputCount
            )
            var confirmedFacesByPerson = try catalog.repository.confirmedFaceEmbeddingsByPerson(provenance: provenance)
            for (personID, vectors) in try catalog.repository.contactReferenceEmbeddingsByPerson() {
                confirmedFacesByPerson[personID, default: []].append(contentsOf: vectors)
            }
            let suggestions = FaceSuggestionBuilder().suggestions(
                unassignedFaces: unassigned.map { FaceEmbedding(faceID: $0.faceID, vector: $0.embedding) },
                confirmedFacesByPerson: confirmedFacesByPerson
            )
            let observationsByFaceID = Dictionary(
                uniqueKeysWithValues: unassigned.map { ($0.faceID, $0) }
            )
            var personNamesByID = Dictionary(
                uniqueKeysWithValues: catalogPeople.map { ($0.id, $0.name) }
            )
            for (personID, name) in try catalog.repository.contactReferenceNamesByPerson() where personNamesByID[personID] == nil {
                personNamesByID[personID] = name
            }
            let rejectedPairs = try catalog.repository.rejectedFacePeople()
            peopleFaceSuggestions = Self.peopleFaceSuggestions(
                from: suggestions,
                observationsByFaceID: observationsByFaceID,
                personNamesByID: personNamesByID,
                rejectedPairs: rejectedPairs
            )
            peopleFaceObservationAssetCount = try catalog.repository.faceObservationAssetCount(provenance: provenance)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Auto-apply "promotion" for face matches: turns a face's match against
    /// a CONFIRMED person's centroid into a guarded, face-level
    /// `person_faces` row (`origin='ai'`, via `insertAIFace`) — provisional
    /// until a user gesture confirms it (`confirmFace`). Reuses the same
    /// match-distance and `rejected_face_people` filtering
    /// `refreshPeopleFaceSuggestions` uses to propose matches to existing
    /// people, applied automatically instead of surfaced for review. Only
    /// the match half of `FaceSuggestionBuilder`'s output is used — a face
    /// with no confirmed-person match (the cluster/new-person half) stays
    /// unassigned for "who is this" review, out of scope here.
    public func promoteFaceMatches(for assetID: AssetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let provenance = AppleVisionEvaluationProvider.faceProvenance
        let unassigned = try catalog.repository.unassignedFaceObservations(
            provenance: provenance,
            limit: Self.maximumFaceSuggestionInputCount
        )
        var confirmedFacesByPerson = try catalog.repository.confirmedFaceEmbeddingsByPerson(provenance: provenance)
        for (personID, vectors) in try catalog.repository.contactReferenceEmbeddingsByPerson() {
            confirmedFacesByPerson[personID, default: []].append(contentsOf: vectors)
        }
        let suggestions = FaceSuggestionBuilder().suggestions(
            unassignedFaces: unassigned.map { FaceEmbedding(faceID: $0.faceID, vector: $0.embedding) },
            confirmedFacesByPerson: confirmedFacesByPerson
        )
        let materializedPersonIDs = Set(try catalog.repository.people().map(\.id))
        let rejectedPairs = try catalog.repository.rejectedFacePeople()
        for match in suggestions.matches where materializedPersonIDs.contains(match.personID) {
            for faceID in match.faceIDs where faceID.assetID == assetID {
                guard !rejectedPairs.contains(
                    RejectedFacePerson(assetID: faceID.assetID, faceIndex: faceID.faceIndex, personID: match.personID)
                ) else { continue }
                try catalog.repository.insertAIFace(assetID: faceID.assetID, faceIndex: faceID.faceIndex, personID: match.personID)
            }
        }
    }

    public func confirmPeopleFaceSuggestion(_ suggestion: PeopleFaceSuggestion) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard case .matchExisting(let personID, let personName) = suggestion.kind else {
            throw TeststripError.invalidState("face suggestion has no matched person; name it instead")
        }
        // Materialize a latent contact person on first confirm (idempotent for
        // an already-real person: ON CONFLICT refreshes the name). Gated on a
        // contact reference actually backing this personID, so a stale
        // suggestion for a merged-away (non-contact) person still throws
        // `notFound` below instead of resurrecting it.
        if try catalog.repository.contactReferenceFace(personID: personID) != nil {
            try catalog.repository.upsertPerson(id: personID, name: personName)
        }
        try catalog.repository.assignFaces(suggestion.faceIDs, toPersonID: personID)
        try loadCatalogPeople()
        refreshCatalogEvaluationKindSummaries()
        refreshPeopleFaceSuggestions()
        try loadCatalogPage(preferredSelection: nil)
    }

    @discardableResult
    public func confirmPeopleFaceSuggestion(
        _ suggestion: PeopleFaceSuggestion,
        personName: String,
        personID: String = "person-\(UUID().uuidString)"
    ) throws -> CatalogPerson {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let trimmedName = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TeststripError.invalidState("person name is required")
        }
        let targetID = existingPersonID(matchingName: trimmedName) ?? personID
        try catalog.repository.upsertPerson(id: targetID, name: trimmedName)
        try catalog.repository.assignFaces(suggestion.faceIDs, toPersonID: targetID)
        try loadCatalogPeople()
        refreshCatalogEvaluationKindSummaries()
        refreshPeopleFaceSuggestions()
        try loadCatalogPage(preferredSelection: nil)
        guard let person = catalogPeople.first(where: { $0.id == targetID }) else {
            throw CatalogError.notFound(targetID)
        }
        return person
    }

    public func dismissPeopleFaceSuggestion(_ suggestion: PeopleFaceSuggestion) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        try catalog.repository.dismissFaces(suggestion.faceIDs)
        refreshCatalogEvaluationKindSummaries()
        refreshPeopleFaceSuggestions()
    }

    /// Assembles the per-photo People inspector section: one row per
    /// detected face, its state derived straight from the persisted
    /// `person_faces` row for that face index (Task 11) — `origin='user'` is
    /// confirmed, `origin='ai'` is a still-provisional suggestion (from
    /// `promoteFaceMatches`/`insertAIFace`), and no row at all is unnamed.
    /// Deliberately independent of the in-memory `peopleFaceSuggestions`
    /// (that array drives the separate cross-catalog "who is this" review,
    /// not this per-photo section).
    func photoFacesPresentation(for assetID: AssetID) -> PhotoFacesPresentation {
        guard let catalog else {
            return PhotoFacesPresentation(
                assetID: assetID,
                observations: [],
                confirmedByFaceIndex: [:],
                suggestionsByFaceIndex: [:]
            )
        }
        let observations = (try? catalog.repository.faceObservations(assetID: assetID)) ?? []
        let assignmentsByFaceIndex = (try? catalog.repository.personFaces(assetID: assetID)) ?? [:]
        let personNamesByID = Dictionary(uniqueKeysWithValues: catalogPeople.map { ($0.id, $0.name) })
        var confirmedByFaceIndex: [Int: (personID: String, name: String)] = [:]
        var suggestionsByFaceIndex: [Int: (personID: String, name: String)] = [:]
        for (faceIndex, assignment) in assignmentsByFaceIndex {
            guard let name = personNamesByID[assignment.personID] else { continue }
            if assignment.origin == "user" {
                confirmedByFaceIndex[faceIndex] = (personID: assignment.personID, name: name)
            } else {
                suggestionsByFaceIndex[faceIndex] = (personID: assignment.personID, name: name)
            }
        }
        return PhotoFacesPresentation(
            assetID: assetID,
            observations: observations,
            confirmedByFaceIndex: confirmedByFaceIndex,
            suggestionsByFaceIndex: suggestionsByFaceIndex
        )
    }

    /// Names one face as an existing person. A positive identification
    /// overrides any prior "not them" rejection recorded for this exact
    /// (face, person) pair.
    public func nameFace(_ faceID: FaceID, personID: String) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        try catalog.repository.assignFaces([faceID], toPersonID: personID)
        try catalog.repository.clearRejectedFacePerson(assetID: faceID.assetID, faceIndex: faceID.faceIndex, personID: personID)
        try loadCatalogPeople()
        refreshPeopleFaceSuggestions()
    }

    /// Names one face as a brand-new person.
    public func nameFace(_ faceID: FaceID, newPersonName: String) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let trimmedName = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TeststripError.invalidState("person name is required")
        }
        let personID = "person-\(UUID().uuidString)"
        try catalog.repository.upsertPerson(id: personID, name: trimmedName)
        try catalog.repository.assignFaces([faceID], toPersonID: personID)
        try loadCatalogPeople()
        refreshPeopleFaceSuggestions()
    }

    /// Clears one face's confirmed identity.
    public func removeFacePerson(_ faceID: FaceID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        try catalog.repository.unassignFaces([faceID])
        try loadCatalogPeople()
        refreshPeopleFaceSuggestions()
    }

    /// Confirms a machine-suggested face match ("Confirm" on a `.suggested`
    /// row): promotes the persisted `origin='ai'` `person_faces` row to
    /// `'user'` and links the asset into the person's confirmed set
    /// (`CatalogRepository.confirmFace`).
    public func confirmAIFace(assetID: AssetID, faceIndex: Int) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        try catalog.repository.confirmFace(assetID: assetID, faceIndex: faceIndex)
        try loadCatalogPeople()
        refreshPeopleFaceSuggestions()
    }

    /// Records that a suggested identity is wrong for one face ("not
    /// them"): deletes the persisted `origin='ai'` `person_faces` row (so
    /// the face goes back to unnamed instead of re-showing the same
    /// suggestion) and remembers the rejection so recognition stops
    /// re-proposing that person for it.
    public func rejectFaceSuggestion(_ faceID: FaceID, personID: String) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        try catalog.repository.unassignFaces([faceID])
        try catalog.repository.recordRejectedFacePerson(assetID: faceID.assetID, faceIndex: faceID.faceIndex, personID: personID)
        refreshPeopleFaceSuggestions()
    }

    /// ✓ on a proposed cell: confirm the person's proposed face(s) on this asset
    /// (promote `origin='ai'→'user'` + link into the confirmed set), then reload
    /// so the photo leaves Proposed and joins the confirmed grid.
    public func confirmProposedPhoto(_ photo: ProposedPersonPhoto) throws {
        for face in photo.faces {
            try confirmAIFace(assetID: face.assetID, faceIndex: face.faceIndex)
        }
        try reload()
    }

    /// ✗ on a proposed cell: sticky-reject the person's suggested face(s) on this
    /// asset (deletes the `origin='ai'` row + records `rejected_face_people`), then
    /// reload so the photo leaves Proposed for good.
    public func rejectProposedPhoto(_ photo: ProposedPersonPhoto) throws {
        for face in photo.faces {
            try rejectFaceSuggestion(FaceID(assetID: face.assetID, faceIndex: face.faceIndex), personID: face.personID)
        }
        try reload()
    }

    public func showPersonPhotos(named name: String) throws {
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        librarySearchText = Self.librarySearchText(residualText: nil, predicates: [.person(name)])
        selectedView = .grid
        try reload()
    }

    /// Builds the review-first surface behind a face-group suggestion: resolves
    /// each face's bounding box (`faceObservations`, grouped by asset) so every
    /// face in the group can be shown large and zoomed to the face. Tiles are
    /// ordered by asset then face index for a stable layout. A pure projection
    /// of `suggestion` — removals mutate the catalog and the caller rebuilds
    /// from the refreshed `peopleFaceSuggestions`.
    func faceGroupReview(for suggestion: PeopleFaceSuggestion) -> FaceGroupReviewPresentation {
        var boxesByFaceID: [FaceID: FaceBoundingBox] = [:]
        if let catalog {
            for assetID in Set(suggestion.faceIDs.map(\.assetID)) {
                let observations = (try? catalog.repository.faceObservations(assetID: assetID)) ?? []
                for observation in observations {
                    boxesByFaceID[observation.faceID] = observation.boundingBox
                }
            }
        }
        let tiles = suggestion.faceIDs
            .compactMap { faceID -> FaceReviewTile? in
                guard let box = boxesByFaceID[faceID] else { return nil }
                return FaceReviewTile(faceID: faceID, boundingBox: box)
            }
            .sorted { lhs, rhs in
                if lhs.faceID.assetID.rawValue != rhs.faceID.assetID.rawValue {
                    return lhs.faceID.assetID.rawValue < rhs.faceID.assetID.rawValue
                }
                return lhs.faceID.faceIndex < rhs.faceID.faceIndex
            }
        return FaceGroupReviewPresentation(
            suggestionID: suggestion.id,
            kind: suggestion.kind,
            tiles: tiles
        )
    }

    /// Removes one face from a face-group review before the group is
    /// confirmed/named. For a matched person it's a sticky "not them" reject
    /// (`rejectFaceSuggestion`); for a new cluster it dismisses the face from
    /// the review pool (`dismissFaces`). Neither writes a person assignment —
    /// confirm-before-write holds until the user confirms/names the remainder.
    public func removeFaceFromReviewGroup(_ suggestion: PeopleFaceSuggestion, faceID: FaceID) throws {
        switch suggestion.kind {
        case .matchExisting(let personID, _):
            try rejectFaceSuggestion(faceID, personID: personID)
        case .newPerson:
            guard let catalog else {
                throw TeststripError.invalidState("app model has no catalog")
            }
            try catalog.repository.dismissFaces([faceID])
            refreshCatalogEvaluationKindSummaries()
            refreshPeopleFaceSuggestions()
        }
    }

    private static func peopleFaceSuggestions(
        from suggestions: FaceSuggestions,
        observationsByFaceID: [FaceID: CatalogFaceObservation],
        personNamesByID: [String: String],
        rejectedPairs: Set<RejectedFacePerson>
    ) -> [PeopleFaceSuggestion] {
        var result: [PeopleFaceSuggestion] = []
        for match in suggestions.matches {
            let acceptedFaceIDs = match.faceIDs.filter { faceID in
                !rejectedPairs.contains(
                    RejectedFacePerson(assetID: faceID.assetID, faceIndex: faceID.faceIndex, personID: match.personID)
                )
            }
            guard let personName = personNamesByID[match.personID],
                  let representative = acceptedFaceIDs.first,
                  let observation = observationsByFaceID[representative] else { continue }
            result.append(PeopleFaceSuggestion(
                id: "face-match-\(match.personID)",
                kind: .matchExisting(personID: match.personID, personName: personName),
                faceIDs: acceptedFaceIDs,
                representativeFace: representative,
                representativeBoundingBox: observation.boundingBox,
                assetIDs: Self.uniqueAssetIDs(acceptedFaceIDs)
            ))
        }
        for cluster in suggestions.clusters {
            guard let representative = cluster.faceIDs.first,
                  let observation = observationsByFaceID[representative] else { continue }
            result.append(PeopleFaceSuggestion(
                id: "face-cluster-\(representative.assetID.rawValue)-\(representative.faceIndex)",
                kind: .newPerson,
                faceIDs: cluster.faceIDs,
                representativeFace: representative,
                representativeBoundingBox: observation.boundingBox,
                assetIDs: Self.uniqueAssetIDs(cluster.faceIDs)
            ))
        }
        return result
    }

    private static func uniqueAssetIDs(_ faceIDs: [FaceID]) -> [AssetID] {
        var seen = Set<AssetID>()
        return faceIDs.compactMap { seen.insert($0.assetID).inserted ? $0.assetID : nil }
    }

    public init(
        sidebarSections: [SidebarSection],
        selectedView: LibraryViewMode,
        assets: [Asset],
        totalAssetCount: Int? = nil,
        catalog: AppCatalog? = nil,
        statusMessage: String? = nil,
        errorMessage: String? = nil,
        activeWork: AppWorkActivity? = nil,
        recentWork: [AppWorkActivity] = [],
        starredWork: [AppWorkActivity] = [],
        workHistorySearchResults: [AppWorkActivity] = [],
        pendingMetadataSyncItems: [MetadataSyncItem] = [],
        metadataSyncConflictItems: [MetadataSyncItem] = [],
        pendingMetadataSyncCount: Int? = nil,
        metadataSyncConflictCount: Int? = nil,
        previewGenerationQueueStates: [PreviewGenerationQueueState] = [],
        backgroundWorkQueue: BackgroundWorkQueue = BackgroundWorkQueue(maxRunningCount: 2),
        savedAssetSets: [AssetSet] = [],
        assetSetCounts: [AssetSetID: Int] = [:],
        workSessionScopeCounts: [WorkSessionID: Int] = [:],
        catalogFolders: [CatalogFolder] = [],
        catalogTimelineDays: [CatalogTimelineDay] = [],
        sourceRoots: [CatalogSourceRoot] = [],
        sourceAvailabilitySummaries: [CatalogSourceAvailabilitySummary] = [],
        catalogEvaluationKindSummaries: [CatalogEvaluationKindSummary] = [],
        catalogPeople: [CatalogPerson] = [],
        reviewQueueCounts: [ReviewQueue: Int] = [:],
        selectedAssetSetID: AssetSetID? = nil,
        workerSupervisor: WorkerSupervisor? = nil,
        importTaskFactory: AppImportTaskFactory? = nil,
        cardImportTaskFactory: AppCardImportTaskFactory? = nil,
        workerExecutableURL: URL? = nil,
        resourceAccess: SecurityScopedResourceAccess = .permissive,
        workerImportsEnabled: Bool? = nil,
        backgroundWorkPublicationInterval: TimeInterval? = nil,
        backgroundWorkPublicationScheduler: any WorkerTimeoutScheduling = DispatchWorkerTimeoutScheduler(),
        sessionRestoreDefaults: UserDefaults? = nil
    ) {
        let resolvedWorkerImportsEnabled = workerImportsEnabled ?? (workerSupervisor != nil)
        let resolvedTotalAssetCount = totalAssetCount ?? assets.count
        let resolvedPendingMetadataSyncCount = pendingMetadataSyncCount ?? pendingMetadataSyncItems.count
        let resolvedMetadataSyncConflictCount = metadataSyncConflictCount ?? metadataSyncConflictItems.count
        self.sidebarSections = sidebarSections.isEmpty ? Self.defaultSidebarSections(
            totalAssetCount: resolvedTotalAssetCount,
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            workSessionScopeCounts: workSessionScopeCounts,
            catalogFolders: catalogFolders,
            catalogTimelineDays: catalogTimelineDays,
            sourceAvailabilitySummaries: sourceAvailabilitySummaries,
            catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
            reviewQueueCounts: reviewQueueCounts,
            pendingMetadataSyncItems: pendingMetadataSyncItems,
            metadataSyncConflictItems: metadataSyncConflictItems,
            pendingMetadataSyncCount: resolvedPendingMetadataSyncCount,
            metadataSyncConflictCount: resolvedMetadataSyncConflictCount,
            recentWork: recentWork,
            starredWork: starredWork
        ) : sidebarSections
        self.selectedView = selectedView
        self.assets = assets
        self.totalAssetCount = resolvedTotalAssetCount
        self.selectedAssetID = assets.first?.id
        self.selectedBatchAssetIDs = []
        self.selectedBatchAssetIDOrder = []
        self.selectedBatchAssetSortKeys = [:]
        self.statusMessage = statusMessage
        self.errorMessage = errorMessage
        self.activeWork = activeWork
        self.recentWork = recentWork
        self.starredWork = starredWork
        self.workHistorySearchResults = workHistorySearchResults
        self.lastCullingMetadataDecision = nil
        self.pendingMetadataSyncItems = pendingMetadataSyncItems
        self.metadataSyncConflictItems = metadataSyncConflictItems
        self.pendingMetadataSyncCount = resolvedPendingMetadataSyncCount
        self.metadataSyncConflictCount = resolvedMetadataSyncConflictCount
        self.previewGenerationQueueStates = previewGenerationQueueStates
        self.backgroundWorkQueue = workerSupervisor?.queue ?? backgroundWorkQueue
        self.librarySearchText = ""
        self.keywordFilterText = ""
        self.folderFilterText = ""
        self.minimumRatingFilter = nil
        self.librarySortOption = .importOrder
        self.flagFilter = nil
        self.colorLabelFilter = nil
        self.cameraFilterText = ""
        self.lensFilterText = ""
        self.minimumISOFilter = nil
        self.captureDateStartFilter = nil
        self.captureDateEndFilter = nil
        self.availabilityFilter = nil
        self.evaluationKindFilter = nil
        self.needsKeywordsFilter = false
        self.needsEvaluationFilter = false
        self.likelyIssuesFilter = false
        self.potentialPicksFilter = false
        self.providerFailuresFilter = false
        self.metadataSyncPendingFilter = false
        self.metadataSyncConflictFilter = false
        self.detachedLibraryFilterPredicates = []
        self.savedAssetSets = savedAssetSets
        self.assetSetCounts = assetSetCounts
        self.workSessionScopeCounts = workSessionScopeCounts
        self.catalogFolders = catalogFolders
        self.expandedFolderPaths = []
        self.catalogTimelineDays = catalogTimelineDays
        self.sourceRoots = sourceRoots
        self.sourceAvailabilitySummaries = sourceAvailabilitySummaries
        self.catalogEvaluationKindSummaries = catalogEvaluationKindSummaries
        self.catalogPeople = catalogPeople
        self.reviewQueueCounts = reviewQueueCounts
        self.selectedAssetSetID = selectedAssetSetID
        self.latestImportPresentationCore = nil
        self.latestImportPreviewStatus = nil
        self.catalog = catalog
        self.workerSupervisor = workerSupervisor
        self.workerImportsEnabled = resolvedWorkerImportsEnabled
        self.workerExecutableURL = workerExecutableURL
        self.resourceAccess = resourceAccess
        self.previewCacheGenerationsByAssetID = [:]
        self.backgroundWorkPublicationInterval = backgroundWorkPublicationInterval
        self.backgroundWorkPublicationScheduler = backgroundWorkPublicationScheduler
        self.sessionRestoreDefaults = sessionRestoreDefaults
        self.backgroundWorkPublicationTimer = nil
        self.currentPreviewCacheGenerationsByAssetID = [:]
        self.lastProcessedBackgroundWorkQueue = nil
        self.pendingLatestImportPreviewStatusRefresh = false
        self.pendingPreviewGenerationQueueStatesRefresh = false
        self.gridPreviewURLCacheByAssetID = [:]
        self.gridPreviewStatusCacheByAssetID = [:]
        self.evaluationAssetIDsByItemID = [:]
        self.evaluationProvidersByItemID = [:]
        self.metadataSyncAssetIDsByItemID = [:]
        self.availabilityAssetIDsByItemID = [:]
        self.evaluationSignalGenerationsByAssetID = [:]
        // User-selected file grants are process-scoped, so local imports must render
        // their first previews before releasing a required security-scoped folder.
        let importPreviewPolicy: LibraryImportPreviewPolicy = workerSupervisor == nil || !resolvedWorkerImportsEnabled ? .generateImmediately : .deferGeneration
        self.importTaskFactory = importTaskFactory ?? { paths, folderURL, duplicateHandling, progress in
            Self.defaultImportTask(
                paths: paths,
                folderURL: folderURL,
                previewPolicy: importPreviewPolicy,
                duplicateHandling: duplicateHandling,
                progress: progress
            )
        }
        self.cardImportTaskFactory = cardImportTaskFactory ?? { paths, source, destinationRoot, destinationPolicy, secondCopyDestination, duplicateHandling, progress in
            Self.defaultCardImportTask(
                paths: paths,
                source: source,
                destinationRoot: destinationRoot,
                destinationPolicy: destinationPolicy,
                secondCopyDestination: secondCopyDestination,
                previewPolicy: importPreviewPolicy,
                duplicateHandling: duplicateHandling,
                progress: progress
            )
        }
        self.metadataUndoStack = []
        self.metadataRedoStack = []
        self.compareAssetIDs = nil
        self.workerImportContextsByItemID = [:]
        self.activeSecurityScopedSourceRootURLs = []
        self.sourceRootBookmarkRepairPaths = []
        restoreSecurityScopedSourceRootAccess()
        rebuildSidebarSections()
        self.workerSupervisor?.onQueueChanged = { [weak self] queue in
            guard let self else { return }
            let previousQueue = self.lastProcessedBackgroundWorkQueue ?? self.backgroundWorkQueue
            let previousPreviewFailureIDs = Self.failedPreviewGenerationItemIDs(in: previousQueue)
            self.lastProcessedBackgroundWorkQueue = queue
            if Self.previewGenerationWorkChanged(from: previousQueue, to: queue) {
                self.pendingLatestImportPreviewStatusRefresh = true
            }
            self.publishBackgroundWorkState()
            self.recordPersistedActiveBackgroundWorkActivities(in: queue)
            if Self.metadataSyncWorkChanged(from: previousQueue, to: queue) {
                try? self.refreshMetadataSyncState()
            }
            let failedPreviewItemIDs = Self.failedPreviewGenerationItemIDs(in: queue)
            let newFailedPreviewItemIDs = failedPreviewItemIDs.subtracting(previousPreviewFailureIDs)
            if !newFailedPreviewItemIDs.isEmpty {
                try? self.refreshPreviewGenerationQueueStates()
                self.refreshLoadedAssetAvailabilityForPreviewFailures(newFailedPreviewItemIDs)
                try? self.enqueuePendingPreviewGeneration(excluding: newFailedPreviewItemIDs)
            }
            self.releaseInactiveWorkerImportContexts(in: queue)
            self.releaseInactiveEvaluationContexts(in: queue)
            self.releaseInactiveMetadataSyncContexts(in: queue)
            self.releaseInactiveAvailabilityContexts(in: queue)
        }
        self.workerSupervisor?.onCommandProgress = { [weak self] event in
            self?.handleWorkerCommandProgress(event)
        }
        self.workerSupervisor?.onCommandCompleted = { [weak self] event in
            self?.handleWorkerCommandCompleted(event)
        }
        if selectedView == .compare {
            compareAssetIDs = compareWindowAssetIDs(limit: Self.defaultCompareAssetLimit, anchor: selectedAssetID)
        }
    }

    deinit {
        for url in activeSecurityScopedSourceRootURLs {
            resourceAccess.stopAccessing(url)
        }
    }

    private func restoreSecurityScopedSourceRootAccess() {
        for sourceRoot in sourceRoots {
            guard let bookmarkData = sourceRoot.securityScopedBookmarkData else {
                continue
            }
            do {
                let resolution = try resourceAccess.resolveSecurityScopedBookmarkData(bookmarkData)
                if resolution.isStale {
                    sourceRootBookmarkRepairPaths.insert(sourceRoot.path)
                }
                guard resourceAccess.startAccessing(resolution.url) else {
                    sourceRootBookmarkRepairPaths.insert(sourceRoot.path)
                    continue
                }
                activeSecurityScopedSourceRootURLs.append(resolution.url)
            } catch {
                sourceRootBookmarkRepairPaths.insert(sourceRoot.path)
            }
        }
    }

    public static func demo() -> AppModel {
        let asset = Asset(
            id: AssetID(rawValue: "demo-1"),
            originalURL: URL(fileURLWithPath: "/Photos/demo.jpg"),
            volumeIdentifier: "Demo",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(rating: 4, colorLabel: .green, flag: .pick, keywords: ["demo"])
        )
        return AppModel(
            sidebarSections: defaultSidebarSections(totalAssetCount: 1),
            selectedView: .grid,
            assets: [asset]
        )
    }

    public static func load(repository: CatalogRepository) throws -> AppModel {
        try reconcileInterruptedIngestWorkSessions(repository: repository)
        let assets = try repository.allAssets()
        let savedAssetSets = try repository.assetSets()
        let assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: repository)
        let catalogFolders = try repository.folders()
        let catalogTimelineDays = try repository.timelineDays()
        let sourceRoots = try repository.sourceRoots()
        let sourceAvailabilitySummaries = try Self.sourceAvailabilitySummaries(repository: repository)
        let catalogEvaluationKindSummaries = try repository.evaluationKindSummaries()
        let catalogPeople = try repository.people()
        let reviewQueueCounts = try Self.reviewQueueCounts(repository: repository)
        let metadataSyncState = try Self.metadataSyncState(
            repository: repository,
            selectedAssetID: assets.first?.id
        )
        let recentWork = try repository.workSessions(limit: 10).map(AppWorkActivity.init)
        let starredWork = try repository.workSessions(limit: 10, starredOnly: true).map(AppWorkActivity.init)
        let workSessionScopeCounts = try Self.workSessionScopeCounts(
            activities: recentWork + starredWork,
            repository: repository
        )
        let totalAssetCount = try repository.assetCount()
        return AppModel(
            sidebarSections: defaultSidebarSections(
                totalAssetCount: totalAssetCount,
                savedAssetSets: savedAssetSets,
                assetSetCounts: assetSetCounts,
                workSessionScopeCounts: workSessionScopeCounts,
                catalogFolders: catalogFolders,
                catalogTimelineDays: catalogTimelineDays,
                sourceAvailabilitySummaries: sourceAvailabilitySummaries,
                catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
                reviewQueueCounts: reviewQueueCounts,
                pendingMetadataSyncItems: metadataSyncState.pendingItems,
                metadataSyncConflictItems: metadataSyncState.conflictItems,
                pendingMetadataSyncCount: metadataSyncState.pendingCount,
                metadataSyncConflictCount: metadataSyncState.conflictCount,
                recentWork: recentWork,
                starredWork: starredWork
            ),
            selectedView: .grid,
            assets: assets,
            totalAssetCount: totalAssetCount,
            recentWork: recentWork,
            starredWork: starredWork,
            pendingMetadataSyncItems: metadataSyncState.pendingItems,
            metadataSyncConflictItems: metadataSyncState.conflictItems,
            pendingMetadataSyncCount: metadataSyncState.pendingCount,
            metadataSyncConflictCount: metadataSyncState.conflictCount,
            previewGenerationQueueStates: try previewGenerationQueueStates(
                repository: repository,
                selectedAssetID: assets.first?.id
            ),
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            workSessionScopeCounts: workSessionScopeCounts,
            catalogFolders: catalogFolders,
            catalogTimelineDays: catalogTimelineDays,
            sourceRoots: sourceRoots,
            sourceAvailabilitySummaries: sourceAvailabilitySummaries,
            catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
            catalogPeople: catalogPeople,
            reviewQueueCounts: reviewQueueCounts
        )
    }

    public static func load(
        catalog: AppCatalog,
        importTaskFactory: AppImportTaskFactory? = nil,
        cardImportTaskFactory: AppCardImportTaskFactory? = nil,
        workerSupervisor: WorkerSupervisor? = nil,
        workerExecutableURL: URL? = nil,
        resourceAccess: SecurityScopedResourceAccess = .permissive,
        workerImportsEnabled: Bool? = nil,
        backgroundWorkPublicationInterval: TimeInterval? = nil,
        backgroundWorkPublicationScheduler: any WorkerTimeoutScheduling = DispatchWorkerTimeoutScheduler(),
        sessionRestoreDefaults: UserDefaults? = nil
    ) throws -> AppModel {
        try reconcileInterruptedIngestWorkSessions(repository: catalog.repository)
        let assets = try catalog.repository.allAssets()
        let savedAssetSets = try catalog.repository.assetSets()
        let assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        let catalogFolders = try catalog.repository.folders()
        let catalogTimelineDays = try catalog.repository.timelineDays()
        let sourceRoots = try catalog.repository.sourceRoots()
        let sourceAvailabilitySummaries = try Self.sourceAvailabilitySummaries(repository: catalog.repository)
        let catalogEvaluationKindSummaries = try catalog.repository.evaluationKindSummaries()
        let catalogPeople = try catalog.repository.people()
        let reviewQueueCounts = try Self.reviewQueueCounts(repository: catalog.repository)
        let metadataSyncState = try Self.metadataSyncState(
            repository: catalog.repository,
            selectedAssetID: assets.first?.id
        )
        let recentWork = try catalog.repository.workSessions(limit: 10).map(AppWorkActivity.init)
        let starredWork = try catalog.repository.workSessions(limit: 10, starredOnly: true).map(AppWorkActivity.init)
        let workSessionScopeCounts = try Self.workSessionScopeCounts(
            activities: recentWork + starredWork,
            repository: catalog.repository
        )
        let totalAssetCount = try catalog.repository.assetCount()
        let model = AppModel(
            sidebarSections: defaultSidebarSections(
                totalAssetCount: totalAssetCount,
                savedAssetSets: savedAssetSets,
                assetSetCounts: assetSetCounts,
                workSessionScopeCounts: workSessionScopeCounts,
                catalogFolders: catalogFolders,
                catalogTimelineDays: catalogTimelineDays,
                sourceAvailabilitySummaries: sourceAvailabilitySummaries,
                catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
                reviewQueueCounts: reviewQueueCounts,
                pendingMetadataSyncItems: metadataSyncState.pendingItems,
                metadataSyncConflictItems: metadataSyncState.conflictItems,
                pendingMetadataSyncCount: metadataSyncState.pendingCount,
                metadataSyncConflictCount: metadataSyncState.conflictCount,
                recentWork: recentWork,
                starredWork: starredWork
            ),
            selectedView: .grid,
            assets: assets,
            totalAssetCount: totalAssetCount,
            catalog: catalog,
            recentWork: recentWork,
            starredWork: starredWork,
            pendingMetadataSyncItems: metadataSyncState.pendingItems,
            metadataSyncConflictItems: metadataSyncState.conflictItems,
            pendingMetadataSyncCount: metadataSyncState.pendingCount,
            metadataSyncConflictCount: metadataSyncState.conflictCount,
            previewGenerationQueueStates: try previewGenerationQueueStates(
                repository: catalog.repository,
                selectedAssetID: assets.first?.id
            ),
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            workSessionScopeCounts: workSessionScopeCounts,
            catalogFolders: catalogFolders,
            catalogTimelineDays: catalogTimelineDays,
            sourceRoots: sourceRoots,
            sourceAvailabilitySummaries: sourceAvailabilitySummaries,
            catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
            catalogPeople: catalogPeople,
            reviewQueueCounts: reviewQueueCounts,
            workerSupervisor: workerSupervisor,
            importTaskFactory: importTaskFactory,
            cardImportTaskFactory: cardImportTaskFactory,
            workerExecutableURL: workerExecutableURL,
            resourceAccess: resourceAccess,
            workerImportsEnabled: workerImportsEnabled,
            backgroundWorkPublicationInterval: backgroundWorkPublicationInterval,
            backgroundWorkPublicationScheduler: backgroundWorkPublicationScheduler,
            sessionRestoreDefaults: sessionRestoreDefaults
        )
        // `catalogPeople` above already seeded the init; this also derives
        // `personKeyFaces` so People cards show key faces on first launch,
        // not just after the next mutating action.
        try model.loadCatalogPeople()
        try model.enqueuePendingPreviewGeneration()
        try model.enqueuePendingMetadataSync()
        try model.enqueuePendingGeocoding()
        try model.restoreSessionStateIfAvailable()
        try model.reconstructAutopilotStateAfterLoad()
        if let sessionRestoreDefaults {
            model.autopilotEnabled = sessionRestoreDefaults.bool(forKey: autopilotEnabledDefaultsKey)
            model.defaultCreator = sessionRestoreDefaults.string(forKey: defaultCreatorDefaultsKey) ?? ""
            model.defaultCopyright = sessionRestoreDefaults.string(forKey: defaultCopyrightDefaultsKey) ?? ""
            model.defaultCardImportDestination = sessionRestoreDefaults.string(forKey: defaultCardImportDestinationDefaultsKey) ?? ""
        }
        return model
    }

    private static func metadataSyncState(
        repository: CatalogRepository,
        selectedAssetID: AssetID?
    ) throws -> MetadataSyncStateSnapshot {
        var snapshot = MetadataSyncStateSnapshot(
            pendingItems: try repository.pendingMetadataSyncItems(limit: metadataSyncStateDisplayLimit),
            conflictItems: try repository.metadataSyncConflictItems(limit: metadataSyncStateDisplayLimit),
            pendingCount: try repository.pendingMetadataSyncItemCount(),
            conflictCount: try repository.metadataSyncConflictItemCount()
        )
        if let selectedAssetID {
            try mergeMetadataSyncState(for: selectedAssetID, repository: repository, into: &snapshot)
        }
        return snapshot
    }

    private static func mergeMetadataSyncState(
        for assetID: AssetID,
        repository: CatalogRepository,
        into snapshot: inout MetadataSyncStateSnapshot
    ) throws {
        snapshot.pendingItems.removeAll { $0.assetID == assetID }
        snapshot.conflictItems.removeAll { $0.assetID == assetID }
        if let pendingItem = try repository.pendingMetadataSyncItem(assetID: assetID) {
            snapshot.pendingItems.append(pendingItem)
        }
        if let conflictItem = try repository.metadataSyncConflictItem(assetID: assetID) {
            snapshot.conflictItems.append(conflictItem)
        }
    }

    private static func previewGenerationQueueStates(
        repository: CatalogRepository,
        selectedAssetID: AssetID?
    ) throws -> [PreviewGenerationQueueState] {
        var states = try repository.previewGenerationQueueStates(limit: previewGenerationQueueStateDisplayLimit)
        if let selectedAssetID {
            try mergePreviewGenerationQueueStates(for: selectedAssetID, repository: repository, into: &states)
        }
        return states
    }

    private static func mergePreviewGenerationQueueStates(
        for assetID: AssetID,
        repository: CatalogRepository,
        into states: inout [PreviewGenerationQueueState]
    ) throws {
        states.removeAll { $0.item.assetID == assetID }
        for level in PreviewLevel.allCases {
            if let state = try repository.previewGenerationQueueState(assetID: assetID, level: level) {
                states.append(state)
            }
        }
    }

    private static func reconcileInterruptedIngestWorkSessions(repository: CatalogRepository) throws {
        let interruptedStatuses: [WorkSessionStatus] = [.queued, .running, .paused]
        for session in try repository.workSessions(kind: .ingest, statuses: interruptedStatuses) {
            var interruptedSession = session
            interruptedSession.status = .failed
            interruptedSession.detail = interruptedIngestDetail(previousDetail: session.detail)
            interruptedSession.failureCount += 1
            interruptedSession.updatedAt = Date()
            try repository.save(interruptedSession)
        }
    }

    private static func interruptedIngestDetail(previousDetail: String) -> String {
        let baseDetail = "Import interrupted before completion"
        guard !previousDetail.isEmpty, !previousDetail.hasPrefix("Importing from ") else {
            return baseDetail
        }
        return "\(baseDetail) (last progress: \(previousDetail))"
    }

    public func select(_ assetID: AssetID) {
        clearCullingMetadataDecisionFeedback()
        clearBatchSelection()
        selectAssetID(assetID)
    }

    public var selectedBatchAssetCount: Int {
        selectedBatchAssetIDs.count
    }

    public func isBatchSelected(_ assetID: AssetID) -> Bool {
        selectedBatchAssetIDs.contains(assetID)
    }

    public func setBatchSelection(_ assetID: AssetID, isSelected: Bool) {
        if isSelected {
            guard let loadedIndex = assets.firstIndex(where: { $0.id == assetID }) else { return }
            if selectedBatchAssetIDs.insert(assetID).inserted {
                selectedBatchAssetIDOrder.append(assetID)
                selectedBatchAssetSortKeys[assetID] = loadedIndex
            }
        } else {
            if selectedBatchAssetIDs.remove(assetID) != nil {
                selectedBatchAssetIDOrder.removeAll { $0 == assetID }
                selectedBatchAssetSortKeys.removeValue(forKey: assetID)
            }
        }
    }

    public func toggleBatchSelection(_ assetID: AssetID) {
        setBatchSelection(assetID, isSelected: !selectedBatchAssetIDs.contains(assetID))
    }

    public func selectBatchRange(to assetID: AssetID) {
        guard let targetIndex = assets.firstIndex(where: { $0.id == assetID }) else { return }
        let anchorID = selectedBatchRangeAnchorID(fallback: assetID)
        guard let anchorIndex = assets.firstIndex(where: { $0.id == anchorID }) else { return }
        let lowerIndex = min(anchorIndex, targetIndex)
        let upperIndex = max(anchorIndex, targetIndex)
        for asset in assets[lowerIndex...upperIndex] {
            setBatchSelection(asset.id, isSelected: true)
        }
    }

    public func clearBatchSelection() {
        selectedBatchAssetIDs.removeAll()
        selectedBatchAssetIDOrder.removeAll()
        selectedBatchAssetSortKeys.removeAll()
    }

    private func selectAssetID(_ assetID: AssetID?) {
        if assetID != selectedAssetID {
            resetLoupeZoom()
        }
        selectedAssetID = assetID
        updateCompareSetAfterSelectionChange(to: assetID)
        guard let assetID else { return }
        do {
            try refreshSelectedPreviewGenerationQueueStates(for: assetID)
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            try refreshSelectedMetadataSyncState(for: assetID)
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            try enqueueMetadataSyncCheck(for: assetID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public var selectedBatchAssetIDsInCatalogOrder: [AssetID] {
        let fallbackOrder = Dictionary(uniqueKeysWithValues: selectedBatchAssetIDOrder.enumerated().map { ($0.element, $0.offset) })
        return selectedBatchAssetIDOrder
            .filter { selectedBatchAssetIDs.contains($0) }
            .sorted { lhs, rhs in
                let lhsSortKey = selectedBatchAssetSortKeys[lhs] ?? Int.max
                let rhsSortKey = selectedBatchAssetSortKeys[rhs] ?? Int.max
                if lhsSortKey != rhsSortKey {
                    return lhsSortKey < rhsSortKey
                }
                return (fallbackOrder[lhs] ?? Int.max) < (fallbackOrder[rhs] ?? Int.max)
            }
    }

    private var currentManualSelectionAssetIDs: [AssetID] {
        let batchAssetIDs = selectedBatchAssetIDsInCatalogOrder
        if !batchAssetIDs.isEmpty {
            return batchAssetIDs
        }
        return selectedAssetID.map { [$0] } ?? []
    }

    private func selectedBatchRangeAnchorID(fallback: AssetID) -> AssetID {
        if let selectedAssetID, assets.contains(where: { $0.id == selectedAssetID }) {
            return selectedAssetID
        }
        if let latestVisibleBatchID = selectedBatchAssetIDOrder.reversed().first(where: { batchID in
            assets.contains(where: { $0.id == batchID })
        }) {
            return latestVisibleBatchID
        }
        return fallback
    }

    private static func manualSetName(for asset: Asset) -> String {
        let filename = asset.originalURL.deletingPathExtension().lastPathComponent
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedFilename.isEmpty ? "Selection" : trimmedFilename
    }

    public func selectSidebarRow(_ row: SidebarRow) throws {
        try selectSidebarTarget(row.target)
    }

    /// Expands or collapses a Folders-sidebar tree row without changing the
    /// current library scope/selection - purely a rendering concern, so it
    /// never calls `reload()`.
    public func toggleFolderExpansion(path: String) {
        if expandedFolderPaths.contains(path) {
            expandedFolderPaths.remove(path)
        } else {
            expandedFolderPaths.insert(path)
        }
        rebuildSidebarSections()
    }

    public func selectSidebarTarget(_ target: SidebarRowTarget) throws {
        try applySidebarTarget(target)
        recordNavigation(to: target)
    }

    /// Switches to a workspace, restoring whichever sub-view was last shown
    /// there (defaulting to each workspace's primary view).
    public func selectWorkspace(_ workspace: Workspace) {
        selectedView = lastSubView[workspace] ?? workspace.defaultSubView
    }

    /// ⌘I. Toggles the on-demand inspector, reachable in every workspace
    /// (Task 5 unified it onto the Cull loupe alongside Library/People).
    public func toggleInspector() {
        isInspectorVisible.toggle()
    }

    /// ⌥⌘1..3 (or a conflict deep-link). Scrolls the on-demand inspector to
    /// a stacked section, presenting the inspector if the current workspace
    /// can show one.
    public func scrollInspector(to section: InspectorTab) {
        inspectorScrollTarget = section
        inspectorScrollRequestToken += 1
        if WorkspaceChromePolicy.showsInspector(selectedView) {
            isInspectorVisible = true
        }
    }

    /// True when there is an earlier view to return to via `navigateBack()`.
    public var canNavigateBack: Bool { !navigationBackStack.isEmpty }

    /// True when a `navigateBack()` can be undone via `navigateForward()`.
    public var canNavigateForward: Bool { !navigationForwardStack.isEmpty }

    public func navigateBack() throws {
        guard let previous = navigationBackStack.last else { return }
        navigationBackStack.removeLast()
        if let current = currentNavigationTarget {
            navigationForwardStack.append(current)
        }
        try restoreNavigation(to: previous)
    }

    public func navigateForward() throws {
        guard let next = navigationForwardStack.last else { return }
        navigationForwardStack.removeLast()
        if let current = currentNavigationTarget {
            navigationBackStack.append(current)
        }
        try restoreNavigation(to: next)
    }

    private func recordNavigation(to target: SidebarRowTarget) {
        guard !isRestoringNavigation else { return }
        if let current = currentNavigationTarget, current != target {
            navigationBackStack.append(current)
            navigationForwardStack.removeAll()
        }
        currentNavigationTarget = target
    }

    private func restoreNavigation(to target: SidebarRowTarget) throws {
        isRestoringNavigation = true
        defer { isRestoringNavigation = false }
        try applySidebarTarget(target)
        currentNavigationTarget = target
    }

    private func applySidebarTarget(_ target: SidebarRowTarget) throws {
        switch target {
        case .allPhotographs:
            selectedAssetSetID = nil
            selectedView = .grid
            try clearLibraryFilters()
        case .search:
            // Search's permanent home is the Library grid's token query
            // field and result header (Task 9) — SidebarRowTarget.search
            // just routes there now instead of a dedicated route.
            selectedAssetSetID = nil
            selectedView = .grid
        case .timeline:
            selectedAssetSetID = nil
            selectedView = .timeline
        case .people:
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            selectedView = .people
            refreshPeopleFaceSuggestions()
        case .places:
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            selectedView = .map
            try refreshPlaceData()
        case .reviewQueue(let queue):
            try applyReviewQueue(queue)
        case .folder(let path):
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            folderFilterText = path
            selectedView = .grid
            try reload()
        case .sourceAvailability(let availability):
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            availabilityFilter = availability
            selectedView = .grid
            try reload()
        case .evaluationKind(let kind):
            try applyEvaluationKindFilter(kind)
        case .metadataSyncPending:
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            metadataSyncPendingFilter = true
            selectedView = .grid
            try reload()
        case .metadataSyncConflicts:
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            metadataSyncConflictFilter = true
            selectedView = .grid
            try reload()
        case .assetSet(let id):
            try applyAssetSet(id: id)
        case .workSession(let id):
            try applyWorkSession(id: id)
        case .placeholder:
            break
        }
    }

    public func applyWorkSession(id: WorkSessionID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let session = try catalog.repository.session(id: id)
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        librarySearchText = Self.librarySearchText(
            residualText: nil,
            predicates: [.workSession(id.rawValue)]
        )
        selectedView = session.kind == .culling ? .loupe : .grid
        try reload()
        statusMessage = session.detail.isEmpty ? session.title : session.detail
    }

    @discardableResult
    public func openLatestImportCompletion() throws -> ImportCompletionSummary {
        guard let summary = latestImportCompletionSummary else {
            throw TeststripError.invalidState("no completed import")
        }
        try applyWorkSession(id: WorkSessionID(rawValue: summary.activityID))
        return summary
    }

    @discardableResult
    public func beginCullingFromLatestImportCompletion() throws -> WorkSession {
        let summary = try openLatestImportCompletion()
        return try beginCullingSession(named: summary.cullingSessionName)
    }

    @discardableResult
    public func beginStackCullingFromLatestImportCompletion() throws -> WorkSession {
        cullingSessionCompletion = nil
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard let summary = latestImportCompletionSummary else {
            throw TeststripError.invalidState("no completed import")
        }
        let stackIntent = summary.stackCount > 0
            ? "Cull \(Self.stackCountDescription(summary.stackCount)) from latest import"
            : ""
        let stacks = try latestImportStacks(activityID: summary.activityID, repository: catalog.repository)
        guard !stacks.isEmpty else {
            _ = try openLatestImportCompletion()
            let session = try beginCullingSession(named: summary.cullingSessionName, intent: stackIntent)
            statusMessage = "Started \(session.title); no time-adjacent stacks found"
            return session
        }

        let sessionID = WorkSessionID.new()
        let inputSetIDs = try saveCullingStackInputSets(
            sessionID: sessionID,
            title: summary.cullingSessionName,
            stacks: stacks
        )
        guard let firstStackSetID = inputSetIDs.first else {
            throw TeststripError.invalidState("no stack sets were created")
        }
        stackCullingImportActivityIDBySessionID[sessionID] = summary.activityID
        try applyAssetSet(id: firstStackSetID)
        if let firstStackAssetIDs = stacks.first?.assetIDs {
            selectAssetID(recommendedCullingStackAssetID(in: firstStackAssetIDs) ?? firstStackAssetIDs.first)
        }
        selectedView = .loupe

        let totalUnitCount = stacks.reduce(0) { $0 + $1.assetIDs.count }
        let activity = AppWorkActivity(
            id: sessionID.rawValue,
            kind: .culling,
            status: .running,
            title: summary.cullingSessionName,
            detail: stackIntent,
            completedUnitCount: 0,
            totalUnitCount: totalUnitCount,
            failureCount: 0
        )
        recordRecentActivity(
            activity,
            intent: stackIntent,
            inputSetIDs: inputSetIDs
        )
        statusMessage = "Started stack cull with \(Self.stackCountDescription(stacks.count))"
        return try catalog.repository.session(id: sessionID)
    }

    public func reviewLatestImportInCompare() throws {
        _ = try openLatestImportCompletion()
        selectedView = .compare
    }

    public func reviewLatestImportFlagged() throws {
        guard let summary = latestImportCompletionSummary else {
            throw TeststripError.invalidState("there is no completed import to review")
        }
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        librarySearchText = "import:\(summary.activityID)"
        likelyIssuesFilter = true
        selectedView = .grid
        try reload()
    }

    @discardableResult
    public func beginManualCullingFromCompareSet() throws -> WorkSession {
        cullingSessionCompletion = nil
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let compareGroup = compareAssets()
        guard compareGroup.count > 1 else {
            throw TeststripError.invalidState("there is no compare set to cull")
        }

        let selectedCompareAssetID = selectedAssetID.flatMap { selectedID in
            compareGroup.contains { $0.id == selectedID } ? selectedID : nil
        } ?? compareGroup[0].id

        if let existingSession = try openManualCullingSession(
            forAssetIDs: Set(compareGroup.map(\.id)),
            repository: catalog.repository
        ), let existingStackSetID = existingSession.inputSetIDs.first {
            try applyAssetSet(id: existingStackSetID)
            selectAssetID(selectedCompareAssetID)
            selectedView = .loupe
            statusMessage = "Resumed manual cull for \(Self.photoCountDescription(compareGroup.count))"
            return existingSession
        }

        let title = Self.manualCullSessionTitle
        let intent = "Manually cull current compare set"
        let sessionID = WorkSessionID.new()
        let inputSetIDs = try saveCullingStackInputSets(
            sessionID: sessionID,
            title: title,
            stacks: [AssetStack(assetIDs: compareGroup.map(\.id))]
        )
        guard let stackSetID = inputSetIDs.first else {
            throw TeststripError.invalidState("no compare stack set was created")
        }

        try applyAssetSet(id: stackSetID)
        selectAssetID(selectedCompareAssetID)
        selectedView = .loupe

        let activity = AppWorkActivity(
            id: sessionID.rawValue,
            kind: .culling,
            status: .running,
            title: title,
            detail: intent,
            completedUnitCount: 0,
            totalUnitCount: compareGroup.count,
            failureCount: 0
        )
        recordRecentActivity(
            activity,
            intent: intent,
            inputSetIDs: inputSetIDs
        )
        statusMessage = "Started manual cull for \(Self.photoCountDescription(compareGroup.count))"
        return try catalog.repository.session(id: sessionID)
    }

    @discardableResult
    public func acceptLatestImportBatchKeywordSuggestion(_ keyword: String) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetIDs = try latestImportOutputAssetIDs(repository: catalog.repository)
        _ = try openLatestImportCompletion()
        return try acceptBatchKeywordSuggestion(keyword, assetIDs: assetIDs)
    }

    @discardableResult
    public func acceptCurrentScopeBatchKeywordSuggestion(_ keyword: String) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        return try acceptBatchKeywordSuggestion(
            keyword,
            assetIDs: currentAssetScopeIDs(repository: catalog.repository)
        )
    }

    public func canToggleWorkSessionStarred(_ row: SidebarRow) -> Bool {
        guard catalog != nil,
              case .workSession(let id) = row.target else {
            return false
        }
        return persistedWorkActivityIDs.contains(id.rawValue)
    }

    public func sidebarContextActions(for row: SidebarRow) -> [SidebarRowContextAction] {
        switch row.target {
        case .assetSet(let id):
            guard canToggleAssetSetStarred(row),
                  let assetSet = savedAssetSets.first(where: { $0.id == id }) else {
                return []
            }
            var actions = [
                SidebarRowContextAction(
                    kind: .renameAssetSet(id),
                    title: "Rename Set",
                    systemImage: "pencil"
                )
            ]
            actions.append(SidebarRowContextAction(
                kind: .duplicateAssetSet(id),
                title: "Duplicate Set...",
                systemImage: "plus.square.on.square"
            ))
            if case .dynamic = assetSet.membership {
                actions.append(SidebarRowContextAction(
                    kind: .freezeAssetSetSnapshot(id),
                    title: "Freeze Snapshot...",
                    systemImage: "camera.aperture"
                ))
            }
            actions.append(
                SidebarRowContextAction(
                    kind: .toggleAssetSetStarred(id),
                    title: assetSet.starred ? "Remove Star" : "Star Set",
                    systemImage: assetSet.starred ? "star.slash" : "star"
                )
            )
            actions.append(SidebarRowContextAction(
                kind: .deleteAssetSet(id),
                title: "Delete Set...",
                systemImage: "trash"
            ))
            return actions
        case .workSession(let id):
            guard canToggleWorkSessionStarred(row),
                  let activity = workActivity(id: id) else {
                return []
            }
            return [
                SidebarRowContextAction(
                    kind: .toggleWorkSessionStarred(id),
                    title: activity.starred ? "Remove Star" : "Star Work",
                    systemImage: activity.starred ? "star.slash" : "star"
                )
            ]
        default:
            return []
        }
    }

    public func performSidebarContextAction(_ action: SidebarRowContextAction) throws {
        switch action.kind {
        case .renameAssetSet:
            throw TeststripError.invalidState("rename requires a new saved set name")
        case .duplicateAssetSet(let id):
            try duplicateAssetSet(id: id)
        case .freezeAssetSetSnapshot(let id):
            try freezeAssetSetSnapshot(id: id)
        case .toggleAssetSetStarred(let id):
            try toggleAssetSetStarred(id: id)
        case .deleteAssetSet(let id):
            try deleteAssetSet(id: id)
        case .toggleWorkSessionStarred(let id):
            try toggleWorkSessionStarred(id: id)
        }
    }

    public func toggleWorkSessionStarred(id: WorkSessionID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let session = try catalog.repository.session(id: id)
        try setWorkSessionStarred(id: id, starred: !session.starred)
    }

    public func setWorkSessionStarred(id: WorkSessionID, starred: Bool) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        var session = try catalog.repository.session(id: id)
        session.starred = starred
        try catalog.repository.save(session)
        try refreshWorkSessions()
    }

    public func canToggleAssetSetStarred(_ row: SidebarRow) -> Bool {
        guard catalog != nil,
              case .assetSet(let id) = row.target else {
            return false
        }
        return savedAssetSets.contains { $0.id == id }
    }

    public func toggleAssetSetStarred(id: AssetSetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetSet = try catalog.repository.assetSet(id: id)
        try setAssetSetStarred(id: id, starred: !assetSet.starred)
    }

    public func setAssetSetStarred(id: AssetSetID, starred: Bool) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        var assetSet = try catalog.repository.assetSet(id: id)
        assetSet.starred = starred
        try catalog.repository.upsert(assetSet)
        try refreshSavedAssetSets()
    }

    public func renameAssetSet(id: AssetSetID, to name: String) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TeststripError.invalidState("saved set name is required")
        }
        var assetSet = try catalog.repository.assetSet(id: id)
        assetSet.name = trimmedName
        try catalog.repository.upsert(assetSet)
        try refreshSavedAssetSets()
        statusMessage = "Renamed \(trimmedName)"
    }

    public func deleteAssetSet(id: AssetSetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetSet = try catalog.repository.assetSet(id: id)
        try catalog.repository.deleteAssetSet(id: id)
        if selectedAssetSetID == id {
            selectedAssetSetID = nil
            try reload()
        }
        try refreshSavedAssetSets()
        statusMessage = "Deleted \(assetSet.name)"
    }

    @discardableResult
    public func duplicateAssetSet(id: AssetSetID, named name: String? = nil, starred: Bool = false) throws -> AssetSet {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let source = try catalog.repository.assetSet(id: id)
        let duplicateName = (name ?? "Copy of \(source.name)").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !duplicateName.isEmpty else {
            throw TeststripError.invalidState("saved set name is required")
        }
        let duplicate = AssetSet(
            id: .new(),
            name: duplicateName,
            membership: source.membership,
            starred: starred
        )
        return try saveAndSelect(duplicate)
    }

    @discardableResult
    public func freezeAssetSetSnapshot(id: AssetSetID, named name: String? = nil, starred: Bool = false) throws -> AssetSet {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let source = try catalog.repository.assetSet(id: id)
        guard case .dynamic(let query) = source.membership else {
            throw TeststripError.invalidState("only smart collections can be frozen")
        }
        let snapshotName = (name ?? "\(source.name) Snapshot").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snapshotName.isEmpty else {
            throw TeststripError.invalidState("snapshot set name is required")
        }
        let assetIDs = try catalog.repository.assetIDs(matching: query)
        guard !assetIDs.isEmpty else {
            throw TeststripError.invalidState("there are no photos to snapshot")
        }
        let snapshot = AssetSet(
            id: .new(),
            name: snapshotName,
            membership: .snapshot(assetIDs),
            starred: starred
        )
        return try saveAndSelect(snapshot)
    }

    private func workActivity(id: WorkSessionID) -> AppWorkActivity? {
        recentWork.first { $0.id == id.rawValue } ?? starredWork.first { $0.id == id.rawValue }
    }

    public func applyAssetSet(id: AssetSetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetSet = try assetSetForSelection(id: id, repository: catalog.repository)
        if !savedAssetSets.contains(where: { $0.id == assetSet.id }) {
            savedAssetSets.append(assetSet)
            assetSetCounts[assetSet.id] = try Self.assetCount(for: assetSet, repository: catalog.repository)
            rebuildSidebarSections()
        }
        selectedAssetSetID = id
        clearLibraryQueryFilters()
        selectedView = .grid
        try reload()
    }

    public func refreshSavedAssetSets() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        savedAssetSets = try catalog.repository.assetSets()
        assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        rebuildSidebarSections()
    }

    private func refreshWorkSessions() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        recentWork = try catalog.repository.workSessions(limit: 10).map(AppWorkActivity.init)
        starredWork = try catalog.repository.workSessions(limit: 10, starredOnly: true).map(AppWorkActivity.init)
        workSessionScopeCounts = try Self.workSessionScopeCounts(
            activities: recentWork + starredWork,
            repository: catalog.repository
        )
        refreshLatestImportPresentation()
        rebuildSidebarSections()
    }

    @discardableResult
    public func saveCurrentLibraryQuery(named name: String, starred: Bool = false) throws -> AssetSet {
        guard catalog != nil else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TeststripError.invalidState("saved search name is required")
        }
        guard let query = currentLibraryQuery() else {
            throw TeststripError.invalidState("there is no active search to save")
        }
        let assetSet = AssetSet(
            id: .new(),
            name: trimmedName,
            membership: .dynamic(query),
            starred: starred
        )
        return try saveAndSelect(assetSet)
    }

    public func applySmartCollectionRulePreset(_ preset: SmartCollectionRulePreset) throws {
        if selectedAssetSet?.isDynamic != true {
            selectedAssetSetID = nil
        }
        switch preset {
        case .ratingFourPlus:
            minimumRatingFilter = max(minimumRatingFilter ?? 0, 4)
        case .picked:
            flagFilter = .pick
        case .rejected:
            flagFilter = .reject
        case .needsKeywords:
            needsKeywordsFilter = true
        case .needsEvaluation:
            needsEvaluationFilter = true
        case .onlineSources:
            availabilityFilter = .online
        case .offlineSources:
            availabilityFilter = .offline
        case .facesFound:
            evaluationKindFilter = .faceCount
        case .ocrFound:
            evaluationKindFilter = .ocrText
        case .focusSignals:
            evaluationKindFilter = .focus
        case .objectSignals:
            evaluationKindFilter = .object
        case .likelyIssues:
            likelyIssuesFilter = true
        case .providerFailures:
            providerFailuresFilter = true
        case .xmpPending:
            metadataSyncPendingFilter = true
            metadataSyncConflictFilter = false
        case .xmpConflicts:
            metadataSyncPendingFilter = false
            metadataSyncConflictFilter = true
        }
        try reload()
    }

    /// Applies a natural-language Ask as a library filter. When an opt-in
    /// translator is configured it maps the text to the deterministic parser's
    /// field syntax (rendered as the same removable chips); with no translator,
    /// or on any translation error, the raw text flows through the deterministic
    /// parser unchanged. Filtering only — never runs autopilot.
    public func applyNaturalLanguageAsk(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var queryText = trimmed
        if let translator = autopilotQueryTranslator, !trimmed.isEmpty {
            do {
                let translated = try translator.translate(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
                queryText = translated.isEmpty ? trimmed : translated
            } catch {
                queryText = trimmed
                statusMessage = "Ask used plain-text search (model unavailable)"
            }
        }
        librarySearchText = queryText
        try reload()
    }

    public func applySmartCollectionRuleText(_ text: String) throws {
        let normalizedText = Self.normalizedRuleText(text)
        guard !normalizedText.isEmpty else {
            throw TeststripError.invalidState("smart collection rule text is required")
        }
        if selectedAssetSet?.isDynamic != true {
            selectedAssetSetID = nil
        }
        librarySearchText = normalizedText
        try reload()
    }

    @discardableResult
    public func saveSelectedAssetAsManualSet(named name: String, starred: Bool = false) throws -> AssetSet {
        guard catalog != nil else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetIDs = currentManualSelectionAssetIDs
        guard !assetIDs.isEmpty else {
            throw TeststripError.invalidState("no selected assets")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TeststripError.invalidState("manual set name is required")
        }
        let assetSet = AssetSet(
            id: .new(),
            name: trimmedName,
            membership: .manual(assetIDs),
            starred: starred
        )
        return try saveAndSelect(assetSet)
    }

    @discardableResult
    public func saveCurrentAssetScopeSnapshot(named name: String, starred: Bool = false) throws -> AssetSet {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TeststripError.invalidState("snapshot set name is required")
        }
        let assetIDs = try currentAssetScopeIDs(repository: catalog.repository)
        guard !assetIDs.isEmpty else {
            throw TeststripError.invalidState("there are no photos to snapshot")
        }
        let assetSet = AssetSet(
            id: .new(),
            name: trimmedName,
            membership: .snapshot(assetIDs),
            starred: starred
        )
        return try saveAndSelect(assetSet)
    }

    private func saveAndSelect(_ assetSet: AssetSet) throws -> AssetSet {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        try catalog.repository.upsert(assetSet)
        savedAssetSets = try catalog.repository.assetSets()
        assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        selectedAssetSetID = assetSet.id
        clearLibraryQueryFilters()
        rebuildSidebarSections()
        try reload()
        statusMessage = "Saved \(assetSet.name)"
        return assetSet
    }

    public func openCullingSessionPicks() throws {
        guard let completion = cullingSessionCompletion else {
            throw TeststripError.invalidState("no completed culling session")
        }
        guard let picksSetID = completion.picksSetID else {
            throw TeststripError.invalidState("the completed session has no picks")
        }
        try applyAssetSet(id: picksSetID)
        cullingSessionCompletion = nil
        statusMessage = "Viewing \(completion.title) Picks"
    }

    public func dismissCullingSessionCompletion() {
        cullingSessionCompletion = nil
    }

    // Starts a normal (non-stack) culling session over the singles a stack
    // cull left unreviewed, reusing beginCullingSession's session-start path
    // by first scoping the library to exactly those frames.
    @discardableResult
    public func cullRemainingSinglesFromCullingCompletion() throws -> WorkSession {
        guard let completion = cullingSessionCompletion else {
            throw TeststripError.invalidState("no completed culling session")
        }
        guard !completion.remainingSingleAssetIDs.isEmpty else {
            throw TeststripError.invalidState("there are no remaining singles to cull")
        }
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let title = "\(completion.title) Singles"
        let singlesSetID = AssetSetID(rawValue: "work-input-singles-\(UUID().uuidString)")
        let singlesSet = AssetSet(
            id: singlesSetID,
            name: title,
            membership: .snapshot(completion.remainingSingleAssetIDs)
        )
        try catalog.repository.upsert(singlesSet)
        savedAssetSets = try catalog.repository.assetSets()
        assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        try applyAssetSet(id: singlesSetID)
        return try beginCullingSession(
            named: title,
            intent: "Cull remaining singles from \(completion.title)"
        )
    }

    @discardableResult
    public func beginCullingSession(named name: String, intent: String = "") throws -> WorkSession {
        cullingSessionCompletion = nil
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard !assets.isEmpty else {
            throw TeststripError.invalidState("there are no photos to cull")
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw TeststripError.invalidState("culling session name is required")
        }
        let trimmedIntent = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionID = WorkSessionID.new()
        let totalUnitCount = try currentLibraryAssetCount(repository: catalog.repository)
        let inputSetID = try cullingInputSetID(sessionID: sessionID, title: title)
        let previousSelection = selectedAssetID

        if selectedAssetSetID == nil && activeWorkSessionFilterID == nil {
            // Pure filter scope: the cull overlays the live filtered `assets`
            // rather than snapshotting into a selected set, so the filters
            // stay intact when navigating back to Library. A `session:`
            // search token (e.g. from openLatestImportCompletion) is its own
            // explicit re-scoping gesture, not a persisted filter scope —
            // that path keeps applying the input snapshot below.
            selectedView = .loupe
        } else {
            try applyAssetSet(id: inputSetID)
            if let previousSelection, assets.contains(where: { $0.id == previousSelection }) {
                selectedAssetID = previousSelection
            }
            selectedView = .loupe
        }
        activeCullingSessionID = sessionID

        let detail = trimmedIntent.isEmpty ? "Culling \(Self.photoCountDescription(totalUnitCount))" : trimmedIntent
        let activity = AppWorkActivity(
            id: sessionID.rawValue,
            kind: .culling,
            status: .running,
            title: title,
            detail: detail,
            completedUnitCount: 0,
            totalUnitCount: totalUnitCount,
            failureCount: 0
        )
        recordRecentActivity(
            activity,
            intent: trimmedIntent.isEmpty ? title : trimmedIntent,
            inputSetIDs: [inputSetID]
        )
        statusMessage = "Started \(title)"
        return try catalog.repository.session(id: sessionID)
    }

    /// Scopes a fresh culling session to whatever the Library has selected —
    /// the multi-select batch if there is one, else the single loupe/grid
    /// selection — and switches into the Cull workspace on it. Exposed as the
    /// Library context-menu item "Cull These".
    @discardableResult
    public func cullCurrentSelection() throws -> WorkSession {
        let selectionIDs = selectedBatchAssetIDsInCatalogOrder.isEmpty
            ? (selectedAssetID.map { [$0] } ?? [])
            : selectedBatchAssetIDsInCatalogOrder
        guard !selectionIDs.isEmpty else {
            throw TeststripError.invalidState("no photos selected to cull")
        }
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let setID = AssetSetID(rawValue: "cull-selection-\(UUID().uuidString)")
        let selectionSet = AssetSet.manual(id: setID, name: "Cull These", assetIDs: selectionIDs)
        try catalog.repository.upsert(selectionSet)
        savedAssetSets = try catalog.repository.assetSets()
        assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        try applyAssetSet(id: setID)
        return try beginCullingSession(named: "Cull These")
    }

    /// Activates a Cull sidebar source: reuses the same routes Copilot's
    /// Top Picks / Needs Eyes panels and "Cull remaining from latest import"
    /// action used, scoping a fresh culling session to the source's assets.
    /// Autopilot proposals route into the confirm-before-write review flow
    /// instead of a culling session — nothing is written until the user
    /// keeps them.
    public func activateCullSource(_ target: CullSource.Target) throws {
        switch target {
        case .recentImport:
            try beginCullingFromLatestImportCompletion()
        case .autopilotProposals:
            try beginAutopilotReview()
        case .reviewQueue(let queue):
            try applyReviewQueue(queue)
            _ = try beginCullingSession(named: queue.presentation.title)
        case .selection:
            try cullCurrentSelection()
        }
    }

    /// The Cull sidebar's source picker: recent import, the Top Picks /
    /// Needs Eyes review-queue groups Copilot used to read, and whatever the
    /// Library currently has selected.
    public var cullSourcePresentation: CullSourcePresentation {
        var sources: [CullSource] = []
        if let summary = latestImportCompletionSummary {
            sources.append(CullSource(
                id: "recent-import",
                group: .recentImport,
                title: summary.title,
                systemImage: "tray.and.arrow.down",
                count: summary.importedPhotoCount,
                target: .recentImport
            ))
        }
        // The confirm-before-write review path for machine labels: present
        // only while proposals are pending so it never renders as a dead row.
        if !pendingAutopilotProposals.isEmpty {
            sources.append(CullSource(
                id: "autopilot-proposals",
                group: .autopilotProposals,
                title: "Autopilot Proposals",
                systemImage: "wand.and.stars",
                count: pendingAutopilotProposals.count,
                target: .autopilotProposals
            ))
        }
        for queue in [ReviewQueue.picks, .potentialPicks] {
            sources.append(CullSource(
                id: "queue-\(queue.rawValue)",
                group: .topPicks,
                title: queue.presentation.title,
                systemImage: queue.presentation.systemImage,
                count: reviewQueueCounts[queue] ?? 0,
                target: .reviewQueue(queue)
            ))
        }
        for queue in [ReviewQueue.likelyIssues, .needsEvaluation] {
            sources.append(CullSource(
                id: "queue-\(queue.rawValue)",
                group: .needsEyes,
                title: queue.presentation.title,
                systemImage: queue.presentation.systemImage,
                count: reviewQueueCounts[queue] ?? 0,
                target: .reviewQueue(queue)
            ))
        }
        for queue in [ReviewQueue.rejects, .fiveStars, .needsKeywords, .facesFound, .ocrFound, .providerFailures] {
            sources.append(CullSource(
                id: "queue-\(queue.rawValue)",
                group: .diagnostics,
                title: queue.presentation.title,
                systemImage: queue.presentation.systemImage,
                count: reviewQueueCounts[queue] ?? 0,
                target: .reviewQueue(queue)
            ))
        }
        let selectionCount = selectedBatchAssetIDs.isEmpty
            ? (selectedAssetID != nil ? 1 : 0)
            : selectedBatchAssetIDs.count
        sources.append(CullSource(
            id: "selection",
            group: .selection,
            title: "Selection",
            systemImage: "checkmark.circle",
            count: selectionCount,
            target: .selection
        ))
        return CullSourcePresentation(sources: sources)
    }

    public func openAssetInLoupe(_ assetID: AssetID) {
        select(assetID)
        selectedView = .loupe
    }

    // Enter/Space from the Library grid opens the plain-chrome Library loupe,
    // not the culling loupe (which stays reachable only from the Cull workspace).
    public func openAssetInLibraryLoupe(_ assetID: AssetID) {
        select(assetID)
        selectedView = .libraryLoupe
    }

    public func compareAssets(limit: Int = 8) -> [Asset] {
        let boundedLimit = max(1, limit)
        if let persistedStack = persistedWorkStackAssets(limit: boundedLimit, anchor: selectedAssetID) {
            return persistedStack
        }
        if let compareAssetIDs {
            let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
            let anchoredAssets = compareAssetIDs.compactMap { assetsByID[$0] }
            if !anchoredAssets.isEmpty {
                return Array(anchoredAssets.prefix(boundedLimit))
            }
        }
        if let candidateStack = candidateStackAssets(limit: boundedLimit, anchor: selectedAssetID) {
            return candidateStack
        }
        return compareWindowAssets(limit: boundedLimit, anchor: selectedAssetID)
    }

    public func compareGroupKind(limit: Int = 8) -> CompareGroupKind {
        let boundedLimit = max(1, limit)
        if persistedWorkStackAssets(limit: boundedLimit, anchor: selectedAssetID) != nil {
            return .candidateStack
        }
        let candidateStackIDs = candidateStackAssets(limit: boundedLimit, anchor: selectedAssetID)?.map(\.id)
        if let compareAssetIDs, !compareAssetIDs.isEmpty {
            return compareAssetIDs == candidateStackIDs ? .candidateStack : .nearbyFrames
        }
        return candidateStackIDs == nil ? .nearbyFrames : .candidateStack
    }

    /// Pins a specific frame as the A/B comparator's contender (B). Passing the
    /// current anchor's id clears the override so B follows the recommendation.
    public func selectABContender(_ assetID: AssetID?) {
        if let assetID, assetID == selectedAssetID {
            abContenderAssetID = nil
        } else {
            abContenderAssetID = assetID
        }
    }

    public var canKeepComparePrimaryAndRejectAlternates: Bool {
        catalog != nil && !compareAssets().isEmpty
    }

    public func keepComparePrimaryAndRejectAlternates() throws {
        guard catalog != nil else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let compareGroup = compareAssets()
        guard let primaryAsset = comparePrimaryAsset(in: compareGroup) else {
            throw TeststripError.invalidState("no compare set")
        }
        try keepCompareAssetAndRejectAlternates(assetID: primaryAsset.id, compareGroup: compareGroup)
    }

    public func keepCompareAssetAndRejectAlternates(assetID: AssetID) throws {
        guard catalog != nil else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let compareGroup = compareAssets()
        try keepCompareAssetAndRejectAlternates(assetID: assetID, compareGroup: compareGroup)
    }

    /// A/B comparator decision: keep one of the two side-by-side frames and
    /// reject the other, leaving every other loaded frame untouched.
    public func keepABFrame(keeping keptID: AssetID, over rejectedID: AssetID) throws {
        guard catalog != nil else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let group = [keptID, rejectedID].compactMap { id in assets.first { $0.id == id } }
        guard group.count == 2 else {
            throw TeststripError.invalidState("A/B compare needs two loaded frames")
        }
        _ = try applyCompareFlags([keptID: .pick, rejectedID: .reject], to: group)
        let keptName = group.first { $0.id == keptID }?.originalURL.lastPathComponent ?? "frame"
        statusMessage = "Kept \(keptName); rejected the alternate"
    }

    private func keepCompareAssetAndRejectAlternates(assetID: AssetID, compareGroup: [Asset]) throws {
        guard let keptAsset = compareGroup.first(where: { $0.id == assetID }) else {
            throw TeststripError.invalidState("recommended asset is not in the current compare set")
        }
        let summary = try applyCompareFlags(
            compareGroup.reduce(into: [AssetID: PickFlag]()) { flags, compareAsset in
                flags[compareAsset.id] = compareAsset.id == assetID ? .pick : .reject
            },
            to: compareGroup
        )
        try advanceCompareGroupAfterDecision(previousGroup: compareGroup)

        statusMessage = summary.rejectedCount == 0
            ? "Kept \(keptAsset.originalURL.lastPathComponent)"
            : "Kept \(keptAsset.originalURL.lastPathComponent); rejected \(summary.rejectedCount) alternates"
    }

    public func keepAllCompareAssets() throws {
        guard catalog != nil else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let compareGroup = compareAssets()
        guard !compareGroup.isEmpty else {
            throw TeststripError.invalidState("no compare set")
        }

        let summary = try applyCompareFlags(
            compareGroup.reduce(into: [AssetID: PickFlag]()) { flags, compareAsset in
                flags[compareAsset.id] = .pick
            },
            to: compareGroup
        )
        try advanceCompareGroupAfterDecision(previousGroup: compareGroup)

        statusMessage = "Kept all \(summary.pickedCount) compare frames"
    }

    /// Focus-compare tie-break: pick the top 2 ranked contenders and reject
    /// the third, touching only the visible contenders subset — unlike the
    /// other compare group decisions, frames outside that subset (including
    /// the rest of the compare group) are left untouched, since only the
    /// top contenders were ever "in the running" for this decision.
    public func keepTopTwoCompareContendersAndRejectAlternates(assetIDs: [AssetID]) throws {
        guard catalog != nil else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let compareGroup = compareAssets()
        let signalsByAssetID = Dictionary(uniqueKeysWithValues: compareGroup.map { asset in
            (asset.id, evaluationSignals(for: asset.id))
        })
        let rankedContenders = CullingStackRecommendation.rankedCandidates(
            stackAssetIDs: compareGroup.map(\.id),
            evaluationSignalsByAssetID: signalsByAssetID
        )
        guard rankedContenders.count >= CompareSurveyPresentation.contenderCount else {
            throw TeststripError.invalidState("compare set needs at least three ranked contenders")
        }
        let contenders = Array(rankedContenders.prefix(CompareSurveyPresentation.contenderCount))
        guard Set(assetIDs) == Set(contenders.prefix(2).map(\.assetID)) else {
            throw TeststripError.invalidState("kept frames must be the top two ranked contenders")
        }

        let keepSet = Set(assetIDs)
        let contenderGroup = contenders.compactMap { contender in
            compareGroup.first { $0.id == contender.assetID }
        }
        let summary = try applyCompareFlags(
            contenderGroup.reduce(into: [AssetID: PickFlag]()) { flags, asset in
                flags[asset.id] = keepSet.contains(asset.id) ? .pick : .reject
            },
            to: contenderGroup
        )

        statusMessage = "Kept top 2 contenders; rejected \(summary.rejectedCount) contender\(summary.rejectedCount == 1 ? "" : "s")"
    }

    private func applyCompareFlags(
        _ flagsByAssetID: [AssetID: PickFlag],
        to compareGroup: [Asset]
    ) throws -> CompareFlagChangeSummary {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        var summary = CompareFlagChangeSummary()
        var changes: [MetadataChange] = []
        for compareAsset in compareGroup {
            guard let targetFlag = flagsByAssetID[compareAsset.id] else { continue }
            switch targetFlag {
            case .pick:
                summary.pickedCount += 1
            case .reject:
                summary.rejectedCount += 1
            }
            let originalAsset = try catalog.repository.asset(id: compareAsset.id)
            guard originalAsset.metadata.flag != targetFlag else { continue }
            var updatedMetadata = originalAsset.metadata
            updatedMetadata.flag = targetFlag
            try applyMetadataSnapshot(assetID: compareAsset.id, metadata: updatedMetadata)
            changes.append(MetadataChange(
                assetID: compareAsset.id,
                before: originalAsset.metadata,
                after: updatedMetadata
            ))
            summary.changedCount += 1
        }

        recordMetadataChangeGroup(
            label: Self.cullingDecisionLabel(picked: summary.pickedCount, rejected: summary.rejectedCount),
            changes: changes
        )
        if summary.changedCount > 0 {
            try updateActiveCullingSessionProgressAfterFlagChange()
        }
        return summary
    }

    private func comparePrimaryAsset(in compareGroup: [Asset]) -> Asset? {
        if let selectedAssetID,
           let selectedAsset = compareGroup.first(where: { $0.id == selectedAssetID }) {
            return selectedAsset
        }
        return compareGroup.first
    }

    private func compareWindowAssets(limit: Int, anchor: AssetID?) -> [Asset] {
        Self.limitedCompareAssets(assets, limit: limit, anchor: anchor)
    }

    private func persistedWorkStackAssets(limit: Int, anchor: AssetID?) -> [Asset]? {
        guard let selectedWorkStackAssetIDs,
              let anchor,
              selectedWorkStackAssetIDs.contains(anchor) else {
            return nil
        }
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let stackAssets = selectedWorkStackAssetIDs.compactMap { assetsByID[$0] }
        guard stackAssets.count > 1 else {
            return nil
        }
        return Self.limitedCompareAssets(stackAssets, limit: limit, anchor: anchor)
    }

    private func candidateStackAssets(limit: Int, anchor: AssetID?) -> [Asset]? {
        guard !assets.isEmpty else { return nil }
        guard let selectedAssetID = anchor,
              assets.contains(where: { $0.id == selectedAssetID }) else {
            return nil
        }
        let stack = stackBuilder()
            .stacks(
                from: assets,
                visualSimilarityVectorsByAssetID: visualSimilarityVectorsByAssetID(for: assets)
            )
            .first { $0.assetIDs.contains(selectedAssetID) }
        guard let stack, stack.assetIDs.count > 1 else {
            return nil
        }

        let stackAssetIDSet = Set(stack.assetIDs)
        let stackAssets = assets.filter { stackAssetIDSet.contains($0.id) }
        let stackAssetIDs = stackAssets.map(\.id)

        // Recommended-first ordering (Task 18) only kicks in once the stack
        // has evaluation signals to recommend from; otherwise this keeps the
        // pre-existing anchor-windowed behavior (a stack larger than the cap,
        // with no recommendation yet, centers the window on the selection).
        let evaluationSignalsByAssetID = Dictionary(uniqueKeysWithValues: stackAssetIDs.map { ($0, evaluationSignals(for: $0)) })
        guard let recommendedAssetID = CullingStackRecommendation.rankedCandidates(
            stackAssetIDs: stackAssetIDs,
            evaluationSignalsByAssetID: evaluationSignalsByAssetID
        ).first?.assetID else {
            return Self.limitedCompareAssets(stackAssets, limit: limit, anchor: anchor)
        }

        let orderedIDs = CompareAutoPopulateOrdering.orderedStackAssetIDs(
            stackAssetIDs: stackAssetIDs,
            recommendedAssetID: recommendedAssetID,
            cap: limit
        )
        let assetsByID = Dictionary(uniqueKeysWithValues: stackAssets.map { ($0.id, $0) })
        return orderedIDs.compactMap { assetsByID[$0] }
    }

    private static func limitedCompareAssets(_ assets: [Asset], limit: Int, anchor: AssetID?) -> [Asset] {
        guard !assets.isEmpty else { return [] }
        let boundedLimit = max(1, limit)
        let selectedIndex = anchor.flatMap { selectedID in
            assets.firstIndex { $0.id == selectedID }
        } ?? 0
        let maximumStartIndex = max(assets.count - boundedLimit, 0)
        let startIndex = min(max(selectedIndex - 1, 0), maximumStartIndex)
        let endIndex = min(startIndex + boundedLimit, assets.count)
        return Array(assets[startIndex..<endIndex])
    }

    private func compareWindowAssetIDs(limit: Int, anchor: AssetID?) -> [AssetID] {
        if let candidateStack = candidateStackAssets(limit: limit, anchor: anchor) {
            return candidateStack.map(\.id)
        }
        return compareWindowAssets(limit: limit, anchor: anchor).map(\.id)
    }

    private func updateCompareSetAfterViewChange(from previousView: LibraryViewMode) {
        guard selectedView == .compare else {
            compareAssetIDs = nil
            return
        }
        guard previousView != .compare else { return }
        compareAssetIDs = compareWindowAssetIDs(limit: Self.defaultCompareAssetLimit, anchor: selectedAssetID)
    }

    private func updateCompareSetAfterSelectionChange(to assetID: AssetID?) {
        guard selectedView == .compare else { return }
        guard let assetID else {
            compareAssetIDs = nil
            return
        }
        if let compareAssetIDs, compareAssetIDs.contains(assetID) {
            return
        }
        compareAssetIDs = compareWindowAssetIDs(limit: Self.defaultCompareAssetLimit, anchor: assetID)
    }

    // After a compare group decision, move the survey to the next group:
    // the next persisted stack for stack sessions, otherwise the frame after
    // the decided group (selection change re-anchors compareAssetIDs).
    private func advanceCompareGroupAfterDecision(previousGroup: [Asset]) throws {
        guard selectedView == .compare else { return }
        if try selectPersistedCullingStack(.next) {
            return
        }
        let groupAssetIDs = Set(previousGroup.map(\.id))
        guard let lastGroupIndex = assets.lastIndex(where: { groupAssetIDs.contains($0.id) }) else { return }
        let nextIndex = lastGroupIndex + 1
        guard assets.indices.contains(nextIndex) else { return }
        selectAssetID(assets[nextIndex].id)
    }

    public func selectNextAsset() {
        guard !assets.isEmpty else {
            selectAssetID(nil)
            return
        }
        guard let currentSelection = selectedAssetID,
              let index = assets.firstIndex(where: { $0.id == currentSelection }) else {
            selectAssetID(assets.first?.id)
            return
        }
        selectAssetID(assets[min(index + 1, assets.count - 1)].id)
    }

    public func selectPreviousAsset() {
        guard !assets.isEmpty else {
            selectAssetID(nil)
            return
        }
        guard let currentSelection = selectedAssetID,
              let index = assets.firstIndex(where: { $0.id == currentSelection }) else {
            selectAssetID(assets.first?.id)
            return
        }
        selectAssetID(assets[max(index - 1, 0)].id)
    }

    public func moveGridSelection(_ direction: GridMoveDirection, columns: Int) {
        let scopedAssets = CullScopeOrdering.filteredAssets(assets, scope: cullScope)
        guard !scopedAssets.isEmpty else { return }
        let currentIndex = selectedAssetID.flatMap { id in
            scopedAssets.firstIndex(where: { $0.id == id })
        } ?? 0
        guard let nextIndex = GridSelectionMovement.nextIndex(
            from: currentIndex,
            direction: direction,
            count: scopedAssets.count,
            columns: columns
        ) else { return }
        selectAssetID(scopedAssets[nextIndex].id)
    }

    public func returnToLibraryGrid() {
        selectedView = .grid
    }

    public func applyGridKeyCommand(_ command: GridKeyCommand, columns: Int) throws {
        // While the ? key-map overlay is up it owns Esc. The overlay's own
        // .onExitCommand never fires (the key monitors consume Esc before the
        // responder chain), so the Esc-derived grid commands must dismiss the
        // overlay instead of navigating — otherwise Esc in the cull loupe
        // switches to the Library grid underneath the overlay, gating off the
        // culling monitor's ? toggle and leaving the overlay undismissable.
        if isKeyMapOverlayVisible {
            switch command {
            case .returnToGrid, .switchCullSubView:
                isKeyMapOverlayVisible = false
                return
            default:
                break
            }
        }
        switch command {
        case .move(let direction):
            moveGridSelection(direction, columns: columns)
        case .rating(let rating):
            try setRatingForSelectedAssets(rating)
        case .pick:
            try setFlagForSelectedAssets(.pick)
        case .reject:
            try setFlagForSelectedAssets(.reject)
        case .clearFlag:
            try setFlagForSelectedAssets(nil)
        case .openLoupe:
            guard let selectedAssetID else { return }
            if selectedView == .cullGrid {
                select(selectedAssetID)
                selectedView = .loupe
            } else {
                openAssetInLibraryLoupe(selectedAssetID)
            }
        case .returnToGrid:
            returnToLibraryGrid()
        case .switchCullSubView(let mode):
            selectedView = mode
        }
    }

    public func applyCullingCommand(_ command: CullingCommand) throws {
        switch command {
        case .rating(let rating):
            try setRatingForSelectedAsset(rating)
        case .colorLabel(let colorLabel):
            try setColorLabelForSelectedAsset(colorLabel)
        case .pick:
            try setFlagForSelectedAsset(.pick)
        case .reject:
            try setFlagForSelectedAsset(.reject)
        case .clearFlag:
            try setFlagForSelectedAsset(nil)
        }
    }

    public func promoteCurrentFrameAndRejectSiblings() throws {
        guard let selectedAssetID else { return }
        let isInMultiFrameStack = selectedWorkStackAssetIDs?.contains(selectedAssetID) == true
            || cullingStacks().contains(where: { $0.assetIDs.contains(selectedAssetID) })
        // Item 4: Return on a frame with no siblings used to silently do
        // nothing at all — three presses read as the app hanging. Show
        // decision feedback instead; no metadata write happens (there are no
        // siblings to reject).
        guard isInMultiFrameStack else {
            if let originalAsset = selectedAsset {
                lastCullingMetadataDecision = Self.singleFrameStackFeedback(asset: originalAsset)
            }
            return
        }
        let context = try selectedCullingStackDecisionContext()
        let originalAsset = selectedAsset
        // Jesse's ruling (2026-07-11): a sibling the user already picked is
        // protected — promote never reflags a pick to reject. Flag provenance
        // isn't recorded (autopilot commits write plain picks), so ALL picked
        // siblings are protected: the simple, safe reading. The toast
        // discloses the kept picks so the full effect is visible without
        // reading the catalog (Maya's persona-1 scare).
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let protectedPickedSiblings: [Asset] = try context.stack.assetIDs
            .filter { $0 != context.selectedAssetID }
            .compactMap { assetID in
                let asset = try catalog.repository.asset(id: assetID)
                return asset.metadata.flag == .pick ? asset : nil
            }
        let pickedAssetIDs = Set([context.selectedAssetID] + protectedPickedSiblings.map(\.id))
        try applyCullingStackDecision(context: context, pickedAssetIDs: pickedAssetIDs)
        if let originalAsset {
            lastCullingMetadataDecision = Self.promoteDecisionFeedback(
                asset: originalAsset,
                siblingCount: context.stack.assetIDs.count - 1 - protectedPickedSiblings.count,
                protectedPickedSiblings: protectedPickedSiblings
            )
        }
    }

    private static func singleFrameStackFeedback(asset: Asset) -> CullingMetadataDecisionFeedback {
        CullingMetadataDecisionFeedback(
            assetID: asset.id,
            filename: asset.originalURL.lastPathComponent,
            command: .clearFlag,
            decisionText: "No stack to promote — P picks this frame",
            isInformational: true
        )
    }

    private static func promoteDecisionFeedback(
        asset: Asset,
        siblingCount: Int,
        protectedPickedSiblings: [Asset] = []
    ) -> CullingMetadataDecisionFeedback {
        var components: [String] = ["Picked"]
        if siblingCount > 0 {
            components.append("\(siblingCount) sibling\(siblingCount == 1 ? "" : "s") rejected")
        }
        if protectedPickedSiblings.count == 1, let kept = protectedPickedSiblings.first {
            components.append("kept your pick of \(kept.originalURL.lastPathComponent)")
        } else if protectedPickedSiblings.count > 1 {
            components.append("kept your picks of \(protectedPickedSiblings.count) siblings")
        }
        let decisionText = components.count > 1
            ? components.joined(separator: " · ")
            : cullingMetadataDecisionText(.pick)
        return CullingMetadataDecisionFeedback(
            assetID: asset.id,
            filename: asset.originalURL.lastPathComponent,
            command: .pick,
            decisionText: decisionText
        )
    }

    public func keepAllFramesInSelectedCullingStack() throws {
        let context = try selectedCullingStackDecisionContext()
        try applyCullingStackDecision(context: context, pickedAssetIDs: Set(context.stack.assetIDs))
    }

    public func keepTopRankedFramesInSelectedCullingStack(assetIDs: [AssetID]) throws {
        let context = try selectedCullingStackDecisionContext()
        let keepSet = Set(assetIDs)
        guard !keepSet.isEmpty,
              keepSet.isSubset(of: Set(context.stack.assetIDs)) else {
            throw TeststripError.invalidState("top-ranked frames must belong to the selected culling stack")
        }
        try applyCullingStackDecision(context: context, pickedAssetIDs: keepSet)
    }

    private func applyCullingStackDecision(
        context: (
            stack: AssetStack,
            selectedAssetID: AssetID,
            selectedWorkStackSetID: AssetSetID?,
            nextAssetID: AssetID?
        ),
        pickedAssetIDs: Set<AssetID>
    ) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }

        var changes: [MetadataChange] = []
        for assetID in context.stack.assetIDs {
            let originalAsset = try catalog.repository.asset(id: assetID)
            var metadata = originalAsset.metadata
            metadata.flag = pickedAssetIDs.contains(assetID) ? .pick : .reject
            // A stack decision is a direct user gesture too: it confirms the
            // flag even when the decided value matches a tentative AI one
            // already there (the marker removal makes the no-op guard below
            // see a real change and write it through).
            metadata.aiUnconfirmedFields.remove(.flag)
            guard metadata != originalAsset.metadata else { continue }
            try applyMetadataSnapshot(assetID: assetID, metadata: metadata)
            changes.append(MetadataChange(assetID: assetID, before: originalAsset.metadata, after: metadata))
        }
        let scopedLabel = changes.count > 1 ? "Flag · \(Self.photoCountDescription(changes.count))" : "Flag"
        recordMetadataChangeGroup(label: scopedLabel, changes: changes)

        if let selectedWorkStackSetID = context.selectedWorkStackSetID {
            try updatePersistedStackCullingSessionProgress(selectedStackSetID: selectedWorkStackSetID)
        } else {
            try updateActiveCullingSessionProgressAfterFlagChange()
        }

        if try selectPersistedCullingStack(.next) {
            return
        } else if let nextAssetID = context.nextAssetID {
            selectAssetID(nextAssetID)
        }
    }

    /// Called from the key-capture path (not from clicks on the hover
    /// controls themselves) so hover chrome hides when the user goes back
    /// to the keyboard.
    public func noteCullingKeystroke() {
        cullingKeystrokeToken &+= 1
    }

    public func applyCullingShortcut(_ shortcut: CullingShortcut) throws {
        // While the ? key-map overlay is visible it owns navigation entirely
        // (item 3): arrows/PgUp/PgDn scroll the overlay instead of moving the
        // deck underneath, and every other shortcut is swallowed. Esc/? are
        // the only ways out.
        if isKeyMapOverlayVisible {
            switch shortcut {
            case .showKeyMap, .exitCullSubView:
                isKeyMapOverlayVisible = false
            case .previousCandidateInStack:
                scrollKeyMapOverlay(.up)
            case .nextCandidateInStack:
                scrollKeyMapOverlay(.down)
            case .keyMapPageUp:
                scrollKeyMapOverlay(.pageUp)
            case .keyMapPageDown:
                scrollKeyMapOverlay(.pageDown)
            default:
                break
            }
            return
        }
        switch shortcut {
        case .previousPhoto:
            clearCullingMetadataDecisionFeedback()
            try selectPreviousAssetForCulling()
        case .nextPhoto:
            clearCullingMetadataDecisionFeedback()
            try selectNextAssetForCulling()
        case .previousStack:
            clearCullingMetadataDecisionFeedback()
            try selectPreviousStackForCulling()
        case .nextStack:
            clearCullingMetadataDecisionFeedback()
            try selectNextStackForCulling()
        case .previousCandidateInStack:
            clearCullingMetadataDecisionFeedback()
            selectPreviousCandidateInStack()
        case .nextCandidateInStack:
            clearCullingMetadataDecisionFeedback()
            selectNextCandidateInStack()
        case .rating(let rating):
            try applyCullingCommandAndAdvance(.rating(rating))
        case .colorLabel(let colorLabel):
            try applyCullingCommandAndAdvance(.colorLabel(colorLabel))
        case .pick:
            try applyCullingCommandAndAdvance(.pick)
        case .reject:
            try applyCullingCommandAndAdvance(.reject)
        case .clearFlag:
            try applyCullingCommandAndAdvance(.clearFlag)
        case .promoteAndRejectSiblings:
            clearCullingMetadataDecisionFeedback()
            try promoteCurrentFrameAndRejectSiblings()
        case .toggleZoom:
            toggleLoupeZoom()
        case .zoomToNearestFace:
            zoomToNearestFaceOrCycleFace()
        case .cycleExifOverlay:
            exifOverlayLevel = exifOverlayLevel.next()
        case .showKeyMap:
            keyMapOverlayScrollIndex = 0
            isKeyMapOverlayVisible.toggle()
        case .cycleScope:
            cycleCullScope()
        case .showCullGrid:
            selectedView = .cullGrid
        case .showCompare:
            selectedView = .compare
        case .showABCompare:
            // "b" toggles (item 1): pressed again from inside .abCompare, it
            // exits back to .loupe instead of re-entering a no-op.
            selectedView = selectedView == .abCompare ? .loupe : .abCompare
        case .exitCullSubView:
            selectedView = .loupe
        case .keepAOverB:
            try keepCurrentABPair(preferPrimary: true)
        case .keepBOverA:
            try keepCurrentABPair(preferPrimary: false)
        case .keyMapPageUp, .keyMapPageDown:
            break
        }
    }

    private func scrollKeyMapOverlay(_ direction: KeyMapOverlayScrollDirection) {
        keyMapOverlayScrollIndex = KeyMapOverlayScrolling.nextIndex(
            current: keyMapOverlayScrollIndex,
            direction: direction,
            sectionCount: CullingCommandMenuPresentation.sections.count
        )
    }

    /// A/B Compare's keyboard verdicts (item 2): recomputes the same
    /// primary/contender pairing `ABCompareView` renders, from the same
    /// model state, so the key path and the button path always agree.
    private func keepCurrentABPair(preferPrimary: Bool) throws {
        guard selectedView == .abCompare else {
            throw TeststripError.invalidState("Keep A/Keep B only apply in A/B Compare")
        }
        let recommendedAssetID = CullingStackRailPresentation(
            assets: assets,
            selectedAssetID: selectedAssetID,
            evaluationSignalsByAssetID: selectedCullingStackEvaluationSignals(),
            explicitStackScope: selectedCullingStackScope
        ).recommendedAssetID
        let presentation = ABComparePresentation(
            assets: assets,
            selectedAssetID: selectedAssetID,
            recommendedAssetID: recommendedAssetID,
            contenderOverrideID: abContenderAssetID
        )
        guard let primary = presentation.primaryAsset, let contender = presentation.contenderAsset else {
            throw TeststripError.invalidState("A/B compare needs two loaded frames")
        }
        if preferPrimary {
            try keepABFrame(keeping: primary.id, over: contender.id)
        } else {
            try keepABFrame(keeping: contender.id, over: primary.id)
        }
    }

    public func cycleCullScope() {
        cullScope = cullScope.next()
        selectAssetID(CullScopeOrdering.selectionAfterScopeChange(
            assets: assets,
            scope: cullScope,
            currentSelection: selectedAssetID
        ))
        // Scope is an easy-to-miss mode change (the filmstrip just renumbers);
        // announce it through the same toast the rating keys use. It writes
        // no metadata, so the toast is informational (no ⌘Z suffix).
        let toastAsset = selectedAsset ?? assets.first
        lastCullingMetadataDecision = CullingMetadataDecisionFeedback(
            assetID: toastAsset?.id ?? AssetID(rawValue: "cull-scope"),
            filename: toastAsset?.originalURL.lastPathComponent ?? "",
            command: .clearFlag,
            decisionText: "Scope: \(cullScope.displayName)",
            isInformational: true
        )
    }

    /// Count of unflagged (undecided) frames in the session, for driving
    /// `CullCompletionPresentation`. Deliberately NOT filtered by
    /// `cullScope`: the `.picks`/`.rejects` review scopes exclude unflagged
    /// frames by definition, so a scope-filtered count would be trivially
    /// zero there and falsely report completion. Computed from the in-memory
    /// `assets` array (the same array `CullScopeOrdering` navigates, and which
    /// now holds the whole catalog), not a full-catalog query: cheap, and
    /// consistent with how scope-based nav already treats `assets` as the
    /// session's universe elsewhere in this file. A tentative AI flag
    /// (unconfirmed autopilot proposal) counts as undecided too — it isn't a
    /// user decision yet.
    public var cullUndecidedCount: Int {
        assets.filter { $0.metadata.confirmedProjection.flag == nil }.count
    }

    /// The `.reviewPicks` action from `CullCompletionPresentation`.
    public func applyCullCompletionReviewPicks() {
        cullScope = .picks
        selectAssetID(CullScopeOrdering.selectionAfterScopeChange(
            assets: assets,
            scope: cullScope,
            currentSelection: selectedAssetID
        ))
    }

    public func toggleLoupeZoom() {
        loupeZoomFocus = loupeZoomFocus == nil ? .center : nil
        loupeFaceZoomIndex = nil
    }

    public func zoomLoupe(to focus: LoupeZoomFocus) {
        loupeZoomFocus = focus
        loupeFaceZoomIndex = nil
    }

    public func resetLoupeZoom() {
        loupeZoomFocus = nil
        loupeFaceZoomIndex = nil
    }

    /// Reuses the Close-Ups face-box pipeline's detections as zoom targets
    /// for the current selection. Called by LoupeView after it refreshes its
    /// close-up crops. Out-of-range face-cycle state is dropped.
    public func setLoupeFaceFocuses(_ focuses: [LoupeZoomFocus]) {
        loupeFaceFocuses = focuses
        if let index = loupeFaceZoomIndex, !focuses.indices.contains(index) {
            loupeFaceZoomIndex = nil
        }
    }

    /// Z (shift-z): zooms 1:1 to the detected face nearest the current focus
    /// (or image center) the first time it's pressed; a repeated press while
    /// still face-zoomed cycles to the next face, wrapping. Falls back to a
    /// plain centered 1:1 zoom when no faces were detected.
    public func zoomToNearestFaceOrCycleFace() {
        guard !loupeFaceFocuses.isEmpty else {
            loupeFaceZoomIndex = nil
            loupeZoomFocus = .center
            return
        }
        let nextIndex: Int
        if let currentIndex = loupeFaceZoomIndex {
            nextIndex = LoupeFaceZoomTargeting.wrappedIndex(current: currentIndex, faceCount: loupeFaceFocuses.count)
        } else {
            nextIndex = LoupeFaceZoomTargeting.nearestFaceIndex(
                to: loupeZoomFocus ?? .center,
                among: loupeFaceFocuses
            ) ?? 0
        }
        loupeFaceZoomIndex = nextIndex
        loupeZoomFocus = loupeFaceFocuses[nextIndex]
    }

    private func applyCullingCommandAndAdvance(_ command: CullingCommand) throws {
        let originalSelection = selectedAssetID
        let originalAsset = selectedAsset
        try applyCullingCommand(command)
        if let originalAsset {
            lastCullingMetadataDecision = Self.cullingMetadataDecisionFeedback(command: command, asset: originalAsset)
        }
        if selectedAssetID == originalSelection {
            try selectNextAssetForCulling()
        }
    }

    private func clearCullingMetadataDecisionFeedback() {
        lastCullingMetadataDecision = nil
    }

    private static func cullingMetadataDecisionFeedback(
        command: CullingCommand,
        asset: Asset
    ) -> CullingMetadataDecisionFeedback {
        CullingMetadataDecisionFeedback(
            assetID: asset.id,
            filename: asset.originalURL.lastPathComponent,
            command: command,
            decisionText: cullingMetadataDecisionText(command)
        )
    }

    private static func cullingMetadataDecisionText(_ command: CullingCommand) -> String {
        switch command {
        case .rating(let rating):
            return rating > 0 ? "Rated \(rating)" : "Cleared rating"
        case .colorLabel(let colorLabel):
            guard let colorLabel else { return "Cleared label" }
            return "\(colorLabel.rawValue.capitalized) label"
        case .pick:
            return "Picked"
        case .reject:
            return "Rejected"
        case .clearFlag:
            return "Cleared flag"
        }
    }

    private func selectNextAssetForCulling() throws {
        guard !assets.isEmpty else {
            selectAssetID(nil)
            return
        }
        guard let selectedAssetID,
              let index = assets.firstIndex(where: { $0.id == selectedAssetID }) else {
            selectAssetID(CullScopeOrdering.filteredAssets(assets, scope: cullScope).first?.id)
            return
        }
        if let nextID = Self.assetID(in: assets, after: index, matching: cullScope) {
            selectAssetID(nextID)
        }
    }

    private static func assetID(in assets: [Asset], after index: Int, matching scope: CullScope) -> AssetID? {
        var candidate = index + 1
        while assets.indices.contains(candidate) {
            if scope.matches(assets[candidate].metadata.flag) {
                return assets[candidate].id
            }
            candidate += 1
        }
        return nil
    }

    private static func assetID(in assets: [Asset], before index: Int, matching scope: CullScope) -> AssetID? {
        var candidate = index - 1
        while assets.indices.contains(candidate) {
            if scope.matches(assets[candidate].metadata.flag) {
                return assets[candidate].id
            }
            candidate -= 1
        }
        return nil
    }

    private func nextAssetID(after stack: AssetStack) -> AssetID? {
        let stackAssetIDs = Set(stack.assetIDs)
        guard let lastStackIndex = assets.lastIndex(where: { stackAssetIDs.contains($0.id) }) else {
            return nil
        }
        let nextIndex = assets.index(after: lastStackIndex)
        guard assets.indices.contains(nextIndex) else {
            return nil
        }
        return assets[nextIndex].id
    }

    private func cullingStacks() -> [AssetStack] {
        allCullingStacks(for: assets).filter { $0.assetIDs.count > 1 }
    }

    /// The full auto-grouped stack partition (including singleton stacks) for
    /// the given assets, in scope order — used by the filmstrip's dividers,
    /// which need every frame accounted for, not just multi-frame stacks.
    public func allCullingStacks(for assets: [Asset]) -> [AssetStack] {
        stackBuilder()
            .stacks(
                from: assets,
                visualSimilarityVectorsByAssetID: visualSimilarityVectorsByAssetID(for: assets)
            )
    }

    public func selectedCullingStackEvaluationSignals() -> [AssetID: [EvaluationSignal]] {
        if let selectedAssetID,
           let selectedWorkStackAssetIDs,
           selectedWorkStackAssetIDs.contains(selectedAssetID) {
            return Dictionary(uniqueKeysWithValues: selectedWorkStackAssetIDs.map { assetID in
                (assetID, evaluationSignals(for: assetID))
            })
        }
        guard let selectedAssetID,
              let stack = cullingStacks().first(where: { $0.assetIDs.contains(selectedAssetID) }) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: stack.assetIDs.map { assetID in
            (assetID, evaluationSignals(for: assetID))
        })
    }

    // One row per persisted stack in the active stack-cull session; empty
    // outside persisted stack sessions. A stack is decided only when every
    // frame carries a flag — matching session progress accounting.
    public func cullingStackListEntries() -> [CullingStackListEntry] {
        guard let catalog,
              let session = try? activePersistedStackCullingSession(repository: catalog.repository) else {
            return []
        }
        let stackSetIDs = session.inputSetIDs.filter(Self.isWorkStackSetID)
        return stackSetIDs.enumerated().compactMap { index, setID in
            guard let stackAssetIDs = try? assetIDs(in: setID, repository: catalog.repository),
                  let leadAssetID = stackAssetIDs.first else {
                return nil
            }
            let isDecided = (try? stackAssetIDs.allSatisfy { assetID in
                try catalog.repository.asset(id: assetID).metadata.flag != nil
            }) ?? false
            return CullingStackListEntry(
                setID: setID,
                title: "Stack \(index + 1)",
                frameCountText: "\(stackAssetIDs.count) \(stackAssetIDs.count == 1 ? "frame" : "frames")",
                leadAssetID: leadAssetID,
                isDecided: isDecided,
                isSelected: setID == selectedAssetSetID
            )
        }
    }

    public func selectCullingStackSet(id: AssetSetID) throws {
        guard let catalog,
              let session = try activePersistedStackCullingSession(repository: catalog.repository),
              session.inputSetIDs.contains(id) else {
            throw TeststripError.invalidState("stack set is not part of the active culling session")
        }
        let keepSurveyCompare = selectedView == .compare
        try applyAssetSet(id: id)
        let stackAssetIDs = selectedExplicitAssetIDs ?? []
        selectAssetID(recommendedCullingStackAssetID(in: stackAssetIDs) ?? stackAssetIDs.first)
        selectedView = keepSurveyCompare ? .compare : .loupe
    }

    // The ranked best-of-stack frame, or nil when no frame carries quality signals.
    private func recommendedCullingStackAssetID(in assetIDs: [AssetID]) -> AssetID? {
        guard assetIDs.count > 1 else { return nil }
        let signalsByAssetID = Dictionary(uniqueKeysWithValues: assetIDs.map { assetID in
            (assetID, evaluationSignals(for: assetID))
        })
        return CullingStackRecommendation.rankedCandidates(
            stackAssetIDs: assetIDs,
            evaluationSignalsByAssetID: signalsByAssetID
        ).first?.assetID
    }

    // The one stack the culling surfaces (rail, A/B compare) and the promote
    // gesture agree on. Persisted work-stack sets win; otherwise this resolves
    // the same auto-grouped stack `promoteCurrentFrameAndRejectSiblings` uses
    // (full-catalog similarity vectors). The rail must never rebuild stacks
    // from partial inputs and display a membership promote won't write —
    // that made the rail's Keep button a silent no-op (cull-004/cull-014).
    public var selectedCullingStackScope: CullingStackScope? {
        if let selectedWorkStackAssetIDs {
            let position = try? selectedPersistedCullingStackPosition()
            return CullingStackScope(
                assetIDs: selectedWorkStackAssetIDs,
                stackIndex: position?.index,
                stackCount: position?.count,
                rationaleText: "Saved stack from culling session"
            )
        }
        guard let selectedAssetID else { return nil }
        let stacks = cullingStacks()
        guard let stackIndex = stacks.firstIndex(where: { $0.assetIDs.contains(selectedAssetID) }) else {
            return nil
        }
        let stack = stacks[stackIndex]
        return CullingStackScope(
            assetIDs: stack.assetIDs,
            stackIndex: stackIndex + 1,
            stackCount: stacks.count,
            rationaleText: stack.rationale
        )
    }

    private func selectNextStackForCulling() throws {
        if try selectPersistedCullingStack(.next) {
            return
        }
        selectCullingStack(.next)
    }

    private func selectPreviousStackForCulling() throws {
        if try selectPersistedCullingStack(.previous) {
            return
        }
        selectCullingStack(.previous)
    }

    // ↑/↓ within-stack navigation: moves the selection to the next/previous
    // frame in the current stack's ordered assetIDs (the same membership the
    // rail displays via `selectedCullingStackScope`), stopping at the ends —
    // no wrap, no crossing into a neighboring stack.
    public func selectNextCandidateInStack() {
        moveSelectionWithinCurrentCullingStack(by: 1)
    }

    public func selectPreviousCandidateInStack() {
        moveSelectionWithinCurrentCullingStack(by: -1)
    }

    private func moveSelectionWithinCurrentCullingStack(by offset: Int) {
        guard let selectedAssetID,
              let stackAssetIDs = selectedCullingStackScope?.assetIDs,
              let currentIndex = stackAssetIDs.firstIndex(of: selectedAssetID) else {
            return
        }
        let targetIndex = currentIndex + offset
        guard stackAssetIDs.indices.contains(targetIndex) else {
            return
        }
        selectAssetID(stackAssetIDs[targetIndex])
    }

    private func selectedCullingStackDecisionContext() throws -> (
        stack: AssetStack,
        selectedAssetID: AssetID,
        selectedWorkStackSetID: AssetSetID?,
        nextAssetID: AssetID?
    ) {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }

        let selectedWorkStackSetID = selectedWorkStackAssetIDs?.contains(selectedAssetID) == true ? selectedAssetSetID : nil
        let stack: AssetStack?
        let nextAssetID: AssetID?
        if let selectedWorkStackAssetIDs,
           selectedWorkStackAssetIDs.contains(selectedAssetID) {
            stack = AssetStack(assetIDs: selectedWorkStackAssetIDs)
            nextAssetID = nil
        } else {
            let stacks = cullingStacks()
            stack = stacks.first { $0.assetIDs.contains(selectedAssetID) }
            nextAssetID = stack.map(nextAssetID(after:)) ?? nil
        }
        guard let stack, stack.assetIDs.count > 1 else {
            throw TeststripError.invalidState("selected asset is not in a culling stack")
        }
        return (stack, selectedAssetID, selectedWorkStackSetID, nextAssetID)
    }

    @discardableResult
    private func selectPersistedCullingStack(_ direction: CullingStackNavigationDirection) throws -> Bool {
        guard let targetSetID = try persistedCullingStackSetID(direction) else {
            return false
        }
        let keepSurveyCompare = selectedView == .compare
        try applyAssetSet(id: targetSetID)
        let stackAssetIDs = selectedExplicitAssetIDs ?? []
        selectAssetID(recommendedCullingStackAssetID(in: stackAssetIDs) ?? stackAssetIDs.first)
        selectedView = keepSurveyCompare ? .compare : .loupe
        return true
    }

    private func selectCullingStack(_ direction: CullingStackNavigationDirection) {
        let indexedStacks = cullingStacks().compactMap { stack -> IndexedCullingStack? in
            let stackAssetIDs = Set(stack.assetIDs)
            guard let firstIndex = assets.firstIndex(where: { stackAssetIDs.contains($0.id) }),
                  let lastIndex = assets.lastIndex(where: { stackAssetIDs.contains($0.id) }) else {
                return nil
            }
            return IndexedCullingStack(stack: stack, firstIndex: firstIndex, lastIndex: lastIndex)
        }
        guard !indexedStacks.isEmpty else { return }

        guard let selectedAssetID,
              let selectedIndex = assets.firstIndex(where: { $0.id == selectedAssetID }) else {
            let fallbackStack = direction == .next ? indexedStacks.first : indexedStacks.last
            if let fallbackStack {
                selectAssetID(recommendedStackLandingAssetID(for: fallbackStack))
            }
            return
        }

        let selectedStackIndex = indexedStacks.firstIndex { indexedStack in
            indexedStack.stack.assetIDs.contains(selectedAssetID)
        }
        let targetStack: IndexedCullingStack?
        switch direction {
        case .previous:
            if let selectedStackIndex {
                targetStack = indexedStacks.indices.contains(selectedStackIndex - 1) ? indexedStacks[selectedStackIndex - 1] : nil
            } else {
                targetStack = indexedStacks.last { $0.lastIndex < selectedIndex }
            }
        case .next:
            if let selectedStackIndex {
                targetStack = indexedStacks.indices.contains(selectedStackIndex + 1) ? indexedStacks[selectedStackIndex + 1] : nil
            } else {
                targetStack = indexedStacks.first { $0.firstIndex > selectedIndex }
            }
        }

        if let targetStack {
            selectAssetID(recommendedStackLandingAssetID(for: targetStack))
        }
    }

    // ←/→ stack-to-stack navigation lands on the new stack's AI-recommended
    // frame (the same ranking the rail's Keep-recommended action uses), not
    // always the first frame.
    private func recommendedStackLandingAssetID(for indexedStack: IndexedCullingStack) -> AssetID? {
        recommendedCullingStackAssetID(in: indexedStack.stack.assetIDs) ?? indexedStack.firstAssetID
    }

    private func selectPreviousAssetForCulling() throws {
        guard !assets.isEmpty else {
            selectAssetID(nil)
            return
        }
        guard let selectedAssetID,
              let index = assets.firstIndex(where: { $0.id == selectedAssetID }) else {
            selectAssetID(CullScopeOrdering.filteredAssets(assets, scope: cullScope).first?.id)
            return
        }
        if let previousID = Self.assetID(in: assets, before: index, matching: cullScope) {
            selectAssetID(previousID)
        }
    }

    public func setRatingForSelectedAsset(_ rating: Int) throws {
        guard (0...5).contains(rating) else {
            throw TeststripError.invalidState("rating must be between 0 and 5")
        }
        try updateSelectedAssetMetadata(label: "Rating") { metadata in
            metadata.rating = rating
            // A direct user rating gesture is authoritative: it confirms an
            // AI-proposed rating even when the value happens to match what
            // was already there (the marker removal alone still makes this a
            // real change, so the no-op early-return below doesn't skip it).
            metadata.aiUnconfirmedFields.remove(.rating)
        }
    }

    public func setFlagForSelectedAsset(_ flag: PickFlag?) throws {
        let rejectedAssetID = (flag == .reject) ? selectedAssetID : nil
        try updateSelectedAssetMetadata(label: "Flag") { metadata in
            metadata.flag = flag
            // Same authoritative-gesture reasoning as the rating setter above:
            // agreeing with (or overriding) a tentative AI flag must confirm
            // it, not just possibly change its value.
            metadata.aiUnconfirmedFields.remove(.flag)
        }
        try updateActiveCullingSessionProgressAfterFlagChange()
        if let rejectedAssetID {
            refillCompareSetAfterReject(rejectedAssetID)
        }
    }

    // Compare refill (Task 18): rejecting a frame removes it from the survey
    // and, if the same candidate stack has an undecided frame not already in
    // the set, pulls that in to backfill the slot. No-op outside Compare, and
    // when the stack has no undecided frames left to offer.
    private func refillCompareSetAfterReject(_ rejectedAssetID: AssetID) {
        guard selectedView == .compare,
              let compareAssetIDs,
              compareAssetIDs.contains(rejectedAssetID) else {
            return
        }
        let stackAssetIDs = candidateStackAssets(limit: Int.max, anchor: rejectedAssetID)?.map(\.id) ?? []
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        self.compareAssetIDs = CompareRefillOrdering.afterReject(
            currentCompareAssetIDs: compareAssetIDs,
            rejectedAssetID: rejectedAssetID,
            stackAssetIDs: stackAssetIDs,
            isUndecided: { assetID in assetsByID[assetID]?.metadata.flag == nil }
        )
    }

    public func setColorLabelForSelectedAsset(_ colorLabel: ColorLabel?) throws {
        try updateSelectedAssetMetadata(label: "Color label") { metadata in
            metadata.colorLabel = colorLabel
        }
    }

    /// Batch rating/flag/color across the whole grid multi-selection when one is
    /// active, otherwise the single focused asset. One undo group covers every
    /// changed photo, so "select 12 near-dupes, reject 11" is a single gesture.
    public func setRatingForSelectedAssets(_ rating: Int) throws {
        guard (0...5).contains(rating) else {
            throw TeststripError.invalidState("rating must be between 0 and 5")
        }
        try updateSelectedAssetsMetadata(label: "Rating") { metadata in
            metadata.rating = rating
            metadata.aiUnconfirmedFields.remove(.rating)
        }
    }

    public func setFlagForSelectedAssets(_ flag: PickFlag?) throws {
        try updateSelectedAssetsMetadata(label: "Flag") { metadata in
            metadata.flag = flag
            metadata.aiUnconfirmedFields.remove(.flag)
        }
        try updateActiveCullingSessionProgressAfterFlagChange()
    }

    public func setColorLabelForSelectedAssets(_ colorLabel: ColorLabel?) throws {
        try updateSelectedAssetsMetadata(label: "Color label") { metadata in
            metadata.colorLabel = colorLabel
        }
    }

    public func setKeywordTextForSelectedAsset(_ keywordText: String) throws {
        try updateSelectedAssetMetadata(label: "Keywords") { metadata in
            metadata.keywords = Self.keywords(from: keywordText)
        }
    }

    /// Batch keywords/caption/creator/copyright across the whole grid
    /// multi-selection when one is active, otherwise the single focused
    /// asset — the Describe panel's counterpart to
    /// `setRatingForSelectedAssets`/`setFlagForSelectedAssets`/
    /// `setColorLabelForSelectedAssets`. Keyword edits APPEND (dedup per
    /// asset, so distinct existing keywords on other assets survive);
    /// caption/creator/copyright OVERWRITE across the batch, matching the
    /// single-asset field semantics. One undo group per gesture.
    public func setKeywordTextForSelectedAssets(_ keywordText: String) throws {
        let parsedKeywords = Self.keywords(from: keywordText)
        guard currentManualSelectionAssetIDs.count > 1 else {
            try updateSelectedAssetsMetadata(label: "Keywords") { metadata in
                metadata.keywords = parsedKeywords
            }
            return
        }
        try updateSelectedAssetsMetadata(label: "Keywords") { metadata in
            for keyword in parsedKeywords where !Self.keywordList(metadata.keywords, contains: keyword) {
                metadata.keywords.append(keyword)
            }
        }
    }

    public func removeKeywordFromSelectedAsset(_ keyword: String) throws {
        let key = Self.keywordKey(keyword)
        guard !key.isEmpty else { return }
        try updateSelectedAssetMetadata(label: "Keywords") { metadata in
            metadata.keywords.removeAll { Self.keywordKey($0) == key }
        }
    }

    /// Batch-remove a keyword chip from every selected asset (or the single
    /// focused asset when no batch is active).
    public func removeKeywordFromSelectedAssets(_ keyword: String) throws {
        let key = Self.keywordKey(keyword)
        guard !key.isEmpty else { return }
        try updateSelectedAssetsMetadata(label: "Keywords") { metadata in
            metadata.keywords.removeAll { Self.keywordKey($0) == key }
        }
    }

    public func acceptSuggestedKeywordForSelectedAsset(_ keyword: String) throws {
        let cleanedKeyword = Self.cleanedKeyword(keyword)
        guard !cleanedKeyword.isEmpty else { return }
        try updateSelectedAssetMetadata(label: "Keywords") { metadata in
            if !Self.keywordList(metadata.keywords, contains: cleanedKeyword) {
                metadata.keywords.append(cleanedKeyword)
            }
            // Accepting a suggestion is a direct user gesture: it confirms
            // the keyword even when auto-apply already added it tentatively
            // (marker removal alone still makes this a real change, so the
            // no-op early-return in updateSelectedAssetMetadata doesn't skip
            // it) — same reasoning as the direct setters' Blocker-2 fix.
            metadata.aiUnconfirmedKeywords.remove(cleanedKeyword)
        }
    }

    /// Batch-accept a suggested keyword: appends it to every selected asset
    /// that doesn't already have it (dedup per asset).
    public func acceptSuggestedKeywordForSelectedAssets(_ keyword: String) throws {
        let cleanedKeyword = Self.cleanedKeyword(keyword)
        guard !cleanedKeyword.isEmpty else { return }
        try updateSelectedAssetsMetadata(label: "Keywords") { metadata in
            if !Self.keywordList(metadata.keywords, contains: cleanedKeyword) {
                metadata.keywords.append(cleanedKeyword)
            }
            metadata.aiUnconfirmedKeywords.remove(cleanedKeyword)
        }
    }

    public func acceptSuggestedCaptionForSelectedAsset(_ caption: String) throws {
        guard let portableCaption = Self.portableCaption(from: caption) else { return }
        try updateSelectedAssetMetadata(label: "Caption") { metadata in
            metadata.caption = portableCaption
            // Same authoritative-gesture reasoning as the keyword accept
            // above: confirm even when auto-apply already set this same
            // caption text tentatively.
            metadata.aiUnconfirmedFields.remove(.caption)
        }
    }

    /// Batch-accept a suggested caption: overwrites it across every
    /// selected asset.
    public func acceptSuggestedCaptionForSelectedAssets(_ caption: String) throws {
        guard let portableCaption = Self.portableCaption(from: caption) else { return }
        try updateSelectedAssetsMetadata(label: "Caption") { metadata in
            metadata.caption = portableCaption
            metadata.aiUnconfirmedFields.remove(.caption)
        }
    }

    @discardableResult
    public func acceptVisibleBatchKeywordSuggestion(_ keyword: String) throws -> Int {
        try acceptBatchKeywordSuggestion(keyword, assetIDs: assets.map(\.id))
    }

    @discardableResult
    public func acceptSelectedBatchKeywordSuggestion(_ keyword: String) throws -> Int {
        try acceptBatchKeywordSuggestion(keyword, assetIDs: selectedBatchAssetIDsInCatalogOrder)
    }

    @discardableResult
    private func acceptBatchKeywordSuggestion(_ keyword: String, assetIDs: [AssetID]) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let cleanedKeyword = Self.cleanedKeyword(keyword)
        guard !cleanedKeyword.isEmpty else { return 0 }
        var appliedCount = 0
        var changes: [MetadataChange] = []

        for assetID in assetIDs {
            guard try assetNeedsSuggestedKeyword(assetID: assetID, keyword: cleanedKeyword) else {
                continue
            }
            let originalAsset = try catalog.repository.asset(id: assetID)
            var updatedMetadata = originalAsset.metadata
            guard !Self.keywordList(updatedMetadata.keywords, contains: cleanedKeyword) else {
                continue
            }
            updatedMetadata.keywords.append(cleanedKeyword)

            try applyMetadataSnapshot(assetID: assetID, metadata: updatedMetadata)
            changes.append(MetadataChange(
                assetID: assetID,
                before: originalAsset.metadata,
                after: updatedMetadata
            ))
            appliedCount += 1
        }

        recordMetadataChangeGroup(
            label: "Applied \(cleanedKeyword) to \(Self.photoCountDescription(appliedCount))",
            changes: changes
        )
        if appliedCount > 0 {
            statusMessage = "Applied \(cleanedKeyword) to \(Self.photoCountDescription(appliedCount))"
        }
        return appliedCount
    }

    @discardableResult
    public func applyVisibleBatchMetadata(
        keywordText: String,
        caption: String,
        creator: String,
        copyright: String
    ) throws -> Int {
        try applyBatchMetadata(
            assetIDs: assets.map(\.id),
            keywordText: keywordText,
            caption: caption,
            creator: creator,
            copyright: copyright
        )
    }

    @discardableResult
    public func applySelectedBatchMetadata(
        keywordText: String,
        caption: String,
        creator: String,
        copyright: String
    ) throws -> Int {
        try applyBatchMetadata(
            assetIDs: selectedBatchAssetIDsInCatalogOrder,
            keywordText: keywordText,
            caption: caption,
            creator: creator,
            copyright: copyright
        )
    }

    @discardableResult
    public func applyCurrentScopeBatchMetadata(
        keywordText: String,
        caption: String,
        creator: String,
        copyright: String
    ) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        return try applyBatchMetadata(
            assetIDs: currentAssetScopeIDs(repository: catalog.repository),
            keywordText: keywordText,
            caption: caption,
            creator: creator,
            copyright: copyright
        )
    }

    @discardableResult
    private func applyBatchMetadata(
        assetIDs: [AssetID],
        keywordText: String,
        caption: String,
        creator: String,
        copyright: String
    ) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let keywords = Self.keywords(from: keywordText)
        let caption = Self.portableText(from: caption)
        let creator = Self.portableText(from: creator)
        let copyright = Self.portableText(from: copyright)
        guard !keywords.isEmpty || caption != nil || creator != nil || copyright != nil else {
            return 0
        }

        var seenAssetIDs: Set<AssetID> = []
        var changes: [(original: Asset, updated: Asset)] = []
        for assetID in assetIDs {
            guard seenAssetIDs.insert(assetID).inserted else { continue }
            let originalAsset = try catalog.repository.asset(id: assetID)
            var updatedMetadata = originalAsset.metadata
            var changed = false

            for keyword in keywords where !Self.keywordList(updatedMetadata.keywords, contains: keyword) {
                updatedMetadata.keywords.append(keyword)
                changed = true
            }
            if let caption, updatedMetadata.caption != caption {
                updatedMetadata.caption = caption
                changed = true
            }
            if let creator, updatedMetadata.creator != creator {
                updatedMetadata.creator = creator
                changed = true
            }
            if let copyright, updatedMetadata.copyright != copyright {
                updatedMetadata.copyright = copyright
                changed = true
            }
            guard changed else { continue }

            var updatedAsset = originalAsset
            updatedAsset.metadata = updatedMetadata
            changes.append((original: originalAsset, updated: updatedAsset))
        }

        guard !changes.isEmpty else {
            return 0
        }

        try catalog.repository.upsert(changes.map(\.updated))
        if workerSupervisor != nil {
            let pendingItems = try changes.map { change in
                let generation = try catalog.repository.catalogGeneration(assetID: change.updated.id)
                let lastFingerprint = try catalog.repository.lastMetadataSyncFingerprint(assetID: change.updated.id)
                return (
                    asset: change.updated,
                    item: MetadataSyncItem(
                        assetID: change.updated.id,
                        sidecarURL: catalog.metadataSidecarStore.sidecarURL(forOriginalAt: change.updated.originalURL),
                        catalogGeneration: generation,
                        lastSyncedFingerprint: lastFingerprint
                    )
                )
            }
            for pendingItem in pendingItems.map(\.item) {
                try catalog.repository.recordMetadataSyncPending(pendingItem)
                upsertPendingMetadataSyncItem(pendingItem)
            }
            let retryablePendingItems = pendingItems.compactMap { pendingItem in
                canAutomaticallyRetryMetadataSync(for: pendingItem.asset, sidecarURL: pendingItem.item.sidecarURL)
                    ? pendingItem.item
                    : nil
            }
            try enqueueMetadataSyncWork(pendingItems: retryablePendingItems)
        } else {
            for change in changes {
                try syncMetadataSidecar(for: change.updated)
            }
        }

        let updatedAssetsByID = Dictionary(uniqueKeysWithValues: changes.map { ($0.updated.id, $0.updated) })
        for index in assets.indices {
            guard let updatedAsset = updatedAssetsByID[assets[index].id] else { continue }
            assets[index] = updatedAsset
        }
        recordMetadataChangeGroup(
            label: "Applied metadata to \(Self.photoCountDescription(changes.count))",
            changes: changes.map { change in
                MetadataChange(
                    assetID: change.updated.id,
                    before: change.original.metadata,
                    after: change.updated.metadata
                )
            }
        )
        try refreshCatalogSidebarCounts()
        statusMessage = "Applied batch metadata to \(Self.photoCountDescription(changes.count))"
        return changes.count
    }

    @discardableResult
    @MainActor
    public func exportVisibleAssets(
        settings: ExportSettings,
        destinationFolder: URL,
        collisionResolution: ExportCollisionResolution = .keepBoth
    ) async throws -> ExportCompletionSummary {
        try await exportAssets(
            assetIDs: assets.map(\.id),
            settings: settings,
            destinationFolder: destinationFolder,
            collisionResolution: collisionResolution
        )
    }

    @discardableResult
    @MainActor
    public func exportSelectedAssets(
        settings: ExportSettings,
        destinationFolder: URL,
        collisionResolution: ExportCollisionResolution = .keepBoth
    ) async throws -> ExportCompletionSummary {
        try await exportAssets(
            assetIDs: selectedBatchAssetIDsInCatalogOrder,
            settings: settings,
            destinationFolder: destinationFolder,
            collisionResolution: collisionResolution
        )
    }

    @discardableResult
    @MainActor
    public func exportCurrentScopeAssets(
        settings: ExportSettings,
        destinationFolder: URL,
        collisionResolution: ExportCollisionResolution = .keepBoth
    ) async throws -> ExportCompletionSummary {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        return try await exportAssets(
            assetIDs: try currentAssetScopeIDs(repository: catalog.repository),
            settings: settings,
            destinationFolder: destinationFolder,
            collisionResolution: collisionResolution
        )
    }

    /// Filenames the export would write that already exist in the
    /// destination — checked before writing so the export flow can ask once
    /// (Replace All / Keep Both / Cancel) instead of silently suffixing
    /// (Jesse's ruling 2026-07-11).
    @MainActor
    public func exportCollisionFilenames(
        assetIDs: [AssetID],
        format: ExportFormat,
        destinationFolder: URL
    ) throws -> [String] {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        var seenAssetIDs: Set<AssetID> = []
        var originalURLs: [URL] = []
        for assetID in assetIDs {
            guard seenAssetIDs.insert(assetID).inserted else { continue }
            originalURLs.append(try catalog.repository.asset(id: assetID).originalURL)
        }
        return ExportService().collidingFilenames(
            originalURLs: originalURLs,
            format: format,
            destinationDirectory: destinationFolder
        )
    }

    @MainActor
    public func visibleExportAssetIDs() -> [AssetID] {
        assets.map(\.id)
    }

    @MainActor
    public func currentScopeExportAssetIDs() throws -> [AssetID] {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        return try currentAssetScopeIDs(repository: catalog.repository)
    }

    @MainActor
    private func exportAssets(
        assetIDs: [AssetID],
        settings: ExportSettings,
        destinationFolder: URL,
        collisionResolution: ExportCollisionResolution = .keepBoth
    ) async throws -> ExportCompletionSummary {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard !isExporting else {
            throw TeststripError.invalidState("another export is already running")
        }
        var seenAssetIDs: Set<AssetID> = []
        var originalURLs: [URL] = []
        // Catalog-authored metadata rides into the exported files when
        // "Include EXIF/IPTC metadata" is on (persona-6 defect: exports
        // used to carry only the source file's EXIF, stripping the work).
        // Only the CONFIRMED projection is embedded — an AI-unconfirmed
        // keyword/caption/rating is still provisional and must never land in
        // an exported deliverable (same discipline as the sidecar/relocation
        // edges: confirmed wins for anything committing/destructive/portable).
        var catalogMetadataBySourceURL: [URL: AssetMetadata] = [:]
        for assetID in assetIDs {
            guard seenAssetIDs.insert(assetID).inserted else { continue }
            let asset = try catalog.repository.asset(id: assetID)
            originalURLs.append(asset.originalURL)
            catalogMetadataBySourceURL[asset.originalURL] = asset.metadata.confirmedProjection
        }
        guard !originalURLs.isEmpty else {
            throw TeststripError.invalidState("no photos to export")
        }
        isExporting = true
        defer { isExporting = false }
        errorMessage = nil
        statusMessage = "Exporting \(Self.photoCountDescription(originalURLs.count)) to \(destinationFolder.lastPathComponent)..."
        let sink = AppExportProgressSink(model: self, destinationName: destinationFolder.lastPathComponent)
        let service = ExportService()
        let urls = originalURLs
        let destination = destinationFolder
        let results: [ExportFileResult]
        do {
            results = try await Task.detached(priority: .userInitiated) {
                try service.export(
                    originalURLs: urls,
                    settings: settings,
                    destinationDirectory: destination,
                    catalogMetadataBySourceURL: catalogMetadataBySourceURL,
                    collisionResolution: collisionResolution
                ) { completedCount, totalCount in
                    sink.handle(completedCount: completedCount, totalCount: totalCount)
                }
            }.value
        } catch {
            statusMessage = nil
            throw error
        }
        let summary = ExportCompletionSummary(results: results, destinationFolder: destinationFolder)
        statusMessage = summary.statusText
        if summary.failedCount > 0 {
            errorMessage = summary.firstFailureMessage
        }
        return summary
    }

    public func setCaptionForSelectedAsset(_ caption: String) throws {
        try updateSelectedAssetMetadata(label: "Caption") { metadata in
            metadata.caption = Self.portableText(from: caption)
            // Directly typing a caption is authoritative, same as the flag
            // and rating setters above.
            metadata.aiUnconfirmedFields.remove(.caption)
        }
    }

    /// Overwrites the caption across every selected asset (or the single
    /// focused asset when no batch is active) — same overwrite semantics
    /// as the single-asset field, just widened to the batch.
    public func setCaptionForSelectedAssets(_ caption: String) throws {
        try updateSelectedAssetsMetadata(label: "Caption") { metadata in
            metadata.caption = Self.portableText(from: caption)
            metadata.aiUnconfirmedFields.remove(.caption)
        }
    }

    public func setCreatorForSelectedAsset(_ creator: String) throws {
        try updateSelectedAssetMetadata(label: "Creator") { metadata in
            metadata.creator = Self.portableText(from: creator)
        }
    }

    /// Overwrites the creator across every selected asset.
    public func setCreatorForSelectedAssets(_ creator: String) throws {
        try updateSelectedAssetsMetadata(label: "Creator") { metadata in
            metadata.creator = Self.portableText(from: creator)
        }
    }

    public func setCopyrightForSelectedAsset(_ copyright: String) throws {
        try updateSelectedAssetMetadata(label: "Copyright") { metadata in
            metadata.copyright = Self.portableText(from: copyright)
        }
    }

    /// Overwrites the copyright across every selected asset.
    public func setCopyrightForSelectedAssets(_ copyright: String) throws {
        try updateSelectedAssetsMetadata(label: "Copyright") { metadata in
            metadata.copyright = Self.portableText(from: copyright)
        }
    }

    public func resolveSelectedMetadataConflictUsingCatalog() throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        try resolveMetadataConflictUsingCatalog(assetID: selectedAssetID)
    }

    public func resolveSelectedMetadataConflictUsingSidecar() throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        try resolveMetadataConflictUsingSidecar(assetID: selectedAssetID)
    }

    public func resolveSelectedMetadataConflictByMergingMissingSidecarFields() throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        try resolveMetadataConflictByMergingMissingSidecarFields(assetID: selectedAssetID)
    }

    public func retrySelectedMetadataSync() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        let pendingItem = try pendingMetadataSyncItem(assetID: selectedAssetID, repository: catalog.repository)
        let asset = try catalog.repository.asset(id: selectedAssetID)
        guard canAutomaticallyRetryMetadataSync(for: asset, sidecarURL: pendingItem.sidecarURL) else {
            throw TeststripError.invalidState("XMP sidecar folder is not writable or original is unavailable")
        }

        if workerSupervisor != nil {
            try enqueueMetadataSyncWork(pendingItem: pendingItem, placement: .front)
            return
        }

        try syncMetadataSidecar(for: asset)
        try refreshMetadataSyncState()
    }

    @discardableResult
    public func retryPendingMetadataSyncInCurrentScope(
        limit: Int? = nil
    ) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard workerSupervisor != nil else {
            throw TeststripError.invalidState("worker supervisor is not configured")
        }

        let resolvedLimit = limit ?? Self.metadataSyncStateDisplayLimit
        var queuedCount = 0
        let candidates = try metadataSyncRetryCandidatesInCurrentScope(
            repository: catalog.repository,
            limit: max(0, resolvedLimit)
        )
        for (_, pendingItem) in candidates {
            try enqueueMetadataSyncWork(pendingItem: pendingItem)
            queuedCount += 1
        }

        statusMessage = queuedCount == 1
            ? "Queued 1 XMP retry"
            : "Queued \(queuedCount) XMP retries"
        return queuedCount
    }

    private func recordMetadataChangeGroup(label: String, changes: [MetadataChange]) {
        let effectiveChanges = changes.filter { $0.before != $0.after }
        guard !effectiveChanges.isEmpty else { return }
        metadataUndoStack.append(MetadataChangeGroup(label: label, changes: effectiveChanges))
        metadataRedoStack.removeAll()
    }

    public func undoMetadataChange() throws {
        guard let group = metadataUndoStack.popLast() else { return }
        for change in group.changes.reversed() {
            try applyMetadataSnapshot(assetID: change.assetID, metadata: change.before)
        }
        metadataRedoStack.append(group)
        statusMessage = "Undid: \(group.label)"
    }

    public func redoMetadataChange() throws {
        guard let group = metadataRedoStack.popLast() else { return }
        for change in group.changes {
            try applyMetadataSnapshot(assetID: change.assetID, metadata: change.after)
        }
        metadataUndoStack.append(group)
        statusMessage = "Redid: \(group.label)"
    }

    private func updateSelectedAssetMetadata(
        label: String = "Edit",
        _ update: (inout AssetMetadata) throws -> Void
    ) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        let originalAsset = try catalog.repository.asset(id: selectedAssetID)
        var updatedMetadata = originalAsset.metadata
        try update(&updatedMetadata)
        guard updatedMetadata != originalAsset.metadata else { return }

        try applyMetadataSnapshot(assetID: selectedAssetID, metadata: updatedMetadata)
        recordMetadataChangeGroup(label: label, changes: [MetadataChange(
            assetID: selectedAssetID,
            before: originalAsset.metadata,
            after: updatedMetadata
        )])
    }

    private func updateSelectedAssetsMetadata(
        label: String,
        _ update: (inout AssetMetadata) throws -> Void
    ) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetIDs = currentManualSelectionAssetIDs
        guard !assetIDs.isEmpty else {
            throw TeststripError.invalidState("no selected asset")
        }
        var changes: [MetadataChange] = []
        for assetID in assetIDs {
            let originalAsset = try catalog.repository.asset(id: assetID)
            var updatedMetadata = originalAsset.metadata
            try update(&updatedMetadata)
            guard updatedMetadata != originalAsset.metadata else { continue }
            try applyMetadataSnapshot(assetID: assetID, metadata: updatedMetadata)
            changes.append(MetadataChange(
                assetID: assetID,
                before: originalAsset.metadata,
                after: updatedMetadata
            ))
        }
        guard !changes.isEmpty else { return }
        let scopedLabel = changes.count > 1
            ? "\(label) · \(Self.photoCountDescription(changes.count))"
            : label
        recordMetadataChangeGroup(label: scopedLabel, changes: changes)
    }

    private static func keywords(from keywordText: String) -> [String] {
        var seen = Set<String>()
        return keywordText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private static func keywordSuggestions(
        from signals: [EvaluationSignal],
        existingKeywords: [String]
    ) -> [KeywordSuggestion] {
        let candidates = signals.flatMap { signal -> [(keyword: String, signal: EvaluationSignal)] in
            objectLabels(from: signal).compactMap { label in
                let keyword = cleanedKeyword(label)
                guard !keyword.isEmpty else { return nil }
                return (keyword, signal)
            }
        }
        .sorted { lhs, rhs in
            if lhs.signal.confidence != rhs.signal.confidence {
                return lhs.signal.confidence > rhs.signal.confidence
            }
            return lhs.keyword.localizedCaseInsensitiveCompare(rhs.keyword) == .orderedAscending
        }

        var seen = Set(existingKeywords.map(keywordKey).filter { !$0.isEmpty })
        return candidates.compactMap { candidate in
            let key = keywordKey(candidate.keyword)
            guard seen.insert(key).inserted else { return nil }
            return KeywordSuggestion(
                keyword: candidate.keyword,
                sourceKind: candidate.signal.kind,
                confidence: candidate.signal.confidence,
                providerName: candidate.signal.provenance.provider,
                modelName: candidate.signal.provenance.model
            )
        }
    }

    private static func captionSuggestions(from signals: [EvaluationSignal]) -> [CaptionSuggestion] {
        let candidates = signals.compactMap { signal -> (caption: String, signal: EvaluationSignal)? in
            guard signal.kind == .ocrText,
                  case .text(let text) = signal.value,
                  let caption = portableCaption(from: text) else {
                return nil
            }
            return (caption, signal)
        }
        .sorted { lhs, rhs in
            if lhs.signal.confidence != rhs.signal.confidence {
                return lhs.signal.confidence > rhs.signal.confidence
            }
            return lhs.caption.localizedCaseInsensitiveCompare(rhs.caption) == .orderedAscending
        }

        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            let key = candidate.caption.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard seen.insert(key).inserted else { return nil }
            return CaptionSuggestion(
                caption: candidate.caption,
                sourceKind: candidate.signal.kind,
                confidence: candidate.signal.confidence,
                providerName: candidate.signal.provenance.provider,
                modelName: candidate.signal.provenance.model
            )
        }
    }

    private func batchKeywordSuggestions(for assets: [Asset]) -> [BatchKeywordSuggestion] {
        var accumulatorsByKey: [String: BatchKeywordAccumulator] = [:]

        for asset in assets {
            let existingKeys = Set(asset.metadata.keywords.map(Self.keywordKey).filter { !$0.isEmpty })
            var assetKeys = Set<String>()
            for signal in evaluationSignals(for: asset.id) {
                for label in Self.objectLabels(from: signal) {
                    let keyword = Self.cleanedKeyword(label)
                    let key = Self.keywordKey(keyword)
                    guard !key.isEmpty,
                          !existingKeys.contains(key),
                          assetKeys.insert(key).inserted else {
                        continue
                    }

                    var accumulator = accumulatorsByKey[key] ?? BatchKeywordAccumulator(
                        keyword: keyword,
                        assetCount: 0,
                        confidenceTotal: 0,
                        providerName: signal.provenance.provider,
                        modelName: signal.provenance.model,
                        bestConfidence: signal.confidence
                    )
                    accumulator.assetCount += 1
                    accumulator.confidenceTotal += signal.confidence
                    if signal.confidence > accumulator.bestConfidence {
                        accumulator.providerName = signal.provenance.provider
                        accumulator.modelName = signal.provenance.model
                        accumulator.bestConfidence = signal.confidence
                    }
                    accumulatorsByKey[key] = accumulator
                }
            }
        }

        return accumulatorsByKey.values
            .map { accumulator in
                BatchKeywordSuggestion(
                    keyword: accumulator.keyword,
                    assetCount: accumulator.assetCount,
                    averageConfidence: accumulator.averageConfidence,
                    providerName: accumulator.providerName,
                    modelName: accumulator.modelName
                )
            }
            .sorted { lhs, rhs in
                if lhs.assetCount != rhs.assetCount {
                    return lhs.assetCount > rhs.assetCount
                }
                if lhs.averageConfidence != rhs.averageConfidence {
                    return lhs.averageConfidence > rhs.averageConfidence
                }
                return lhs.keyword.localizedCaseInsensitiveCompare(rhs.keyword) == .orderedAscending
            }
    }

    private func assetNeedsSuggestedKeyword(assetID: AssetID, keyword: String) throws -> Bool {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let key = Self.keywordKey(keyword)
        guard !key.isEmpty else { return false }

        let asset = try catalog.repository.asset(id: assetID)
        guard !Self.keywordList(asset.metadata.keywords, contains: keyword) else {
            return false
        }

        return try catalog.repository.evaluationSignals(assetID: assetID).contains { signal in
            Self.objectLabels(from: signal).contains { label in
                Self.keywordKey(label) == key
            }
        }
    }

    /// Minimum object-detection confidence required before a label is
    /// eligible for auto-promotion into `metadata.keywords`.
    public static let objectKeywordConfidenceFloor = 0.5

    /// Auto-apply "promotion": turns AI reads (object-label and caption
    /// evaluation signals) into catalog labels, marked AI-unconfirmed so they
    /// stay provisional until a user gesture confirms them (see
    /// `AssetMetadata.confirmedProjection`). A label the user has previously
    /// rejected (`removedAILabels`) is never re-added. Catalog-only write —
    /// no XMP sidecar sync, since an AI-unconfirmed delta never syncs
    /// (`MetadataSyncPlanner` treats it as up to date; see Task 6).
    public func promoteMetadataLabels(for assetID: AssetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let signals = try catalog.repository.evaluationSignals(assetID: assetID)
        let removedLabels = try catalog.repository.removedAILabels(assetID: assetID)
        let captionCandidate = Self.captionSuggestions(from: signals).first

        try catalog.repository.updateMetadata(assetID: assetID) { metadata in
            for signal in signals where signal.kind == .object && signal.confidence >= Self.objectKeywordConfidenceFloor {
                for label in Self.objectLabels(from: signal) {
                    guard !Self.keywordList(metadata.keywords, contains: label),
                          !removedLabels.contains(RemovedAILabel(field: .keyword, value: label)) else {
                        continue
                    }
                    metadata.keywords.append(label)
                    metadata.aiUnconfirmedKeywords.insert(label)
                }
            }

            if let captionCandidate,
               metadata.caption == nil || metadata.aiUnconfirmedFields.contains(.caption),
               !removedLabels.contains(RemovedAILabel(field: .caption, value: captionCandidate.caption)) {
                metadata.caption = captionCandidate.caption
                metadata.aiUnconfirmedFields.insert(.caption)
            }
        }
    }

    /// Confirms an AI-proposed keyword: it stays in `keywords`, just no
    /// longer marked `aiUnconfirmedKeywords`, so it's now part of the
    /// confirmed projection. Goes through the sidecar-syncing write path
    /// (`applyMetadataSnapshot`) since a confirm is exactly the user gesture
    /// that makes a previously AI-only label portable.
    public func confirmAIKeyword(_ keyword: String, for assetID: AssetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        var metadata = try catalog.repository.asset(id: assetID).metadata
        metadata.aiUnconfirmedKeywords.remove(keyword)
        try applyMetadataSnapshot(assetID: assetID, metadata: metadata)
    }

    /// Removes an AI-proposed keyword the user rejected: dropped from both
    /// `keywords` and `aiUnconfirmedKeywords`, and remembered in
    /// `removed_ai_labels` so a later `promoteMetadataLabels` never re-adds
    /// it. Catalog-only write — nothing confirmed changed (the keyword was
    /// never in the confirmed projection), so there's no sidecar delta to
    /// sync.
    public func removeAIKeyword(_ keyword: String, for assetID: AssetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        try catalog.repository.updateMetadata(assetID: assetID) { metadata in
            metadata.keywords.removeAll { $0 == keyword }
            metadata.aiUnconfirmedKeywords.remove(keyword)
        }
        try catalog.repository.recordRemovedAILabel(assetID: assetID, field: .keyword, value: keyword)
        try refreshInMemoryAsset(assetID)
    }

    /// Confirms an AI-proposed `.caption`/`.flag`/`.rating`: the value stays,
    /// just no longer marked unconfirmed. Sidecar-syncing write path, same
    /// reasoning as `confirmAIKeyword`.
    public func confirmAIField(_ field: MetadataField, for assetID: AssetID) throws {
        guard field != .keyword else {
            throw TeststripError.invalidState("confirmAIField does not handle .keyword; use confirmAIKeyword")
        }
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        var metadata = try catalog.repository.asset(id: assetID).metadata
        metadata.aiUnconfirmedFields.remove(field)
        try applyMetadataSnapshot(assetID: assetID, metadata: metadata)
    }

    /// Removes an AI-proposed `.caption`/`.flag`/`.rating` the user rejected:
    /// clears the field's value, drops it from `aiUnconfirmedFields`, and
    /// records the removal keyed by a stable string of the value that was
    /// rejected — the exact caption text (matching `promoteMetadataLabels`'s
    /// keying), the flag's raw value (`"pick"`/`"reject"`), or the rating as
    /// a decimal string — so a future promoter (autopilot) can recognize and
    /// skip re-proposing that same value. Catalog-only write, same reasoning
    /// as `removeAIKeyword`.
    public func removeAIField(_ field: MetadataField, for assetID: AssetID) throws {
        guard field != .keyword else {
            throw TeststripError.invalidState("removeAIField does not handle .keyword; use removeAIKeyword")
        }
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let currentMetadata = try catalog.repository.asset(id: assetID).metadata
        let removedValue = Self.removedAILabelValue(for: field, in: currentMetadata)
        try catalog.repository.updateMetadata(assetID: assetID) { metadata in
            switch field {
            case .caption:
                metadata.caption = nil
            case .flag:
                metadata.flag = nil
            case .rating:
                metadata.rating = 0
            case .keyword:
                break
            }
            metadata.aiUnconfirmedFields.remove(field)
        }
        try catalog.repository.recordRemovedAILabel(assetID: assetID, field: field, value: removedValue)
        try refreshInMemoryAsset(assetID)
    }

    private static func removedAILabelValue(for field: MetadataField, in metadata: AssetMetadata) -> String {
        switch field {
        case .caption:
            return metadata.caption ?? ""
        case .flag:
            return metadata.flag?.rawValue ?? ""
        case .rating:
            return String(metadata.rating)
        case .keyword:
            return ""
        }
    }

    /// Fetch-and-splice a single asset's catalog state into the in-memory
    /// `assets` cache (and, transitively, `selectedAsset`, derived from it)
    /// after a catalog-only write that skips the sidecar-syncing
    /// `applyMetadataSnapshot` path — same pattern `promoteEvaluationResults`
    /// uses after promotion.
    private func refreshInMemoryAsset(_ assetID: AssetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let updatedAsset = try catalog.repository.asset(id: assetID)
        if let index = assets.firstIndex(where: { $0.id == assetID }) {
            assets[index] = updatedAsset
        }
    }

    private static func objectLabels(from signal: EvaluationSignal) -> [String] {
        guard signal.kind == .object else { return [] }
        switch signal.value {
        case .label(let label):
            return [label]
        case .labels(let labels):
            return labels
        case .score, .text, .count, .vector:
            return []
        }
    }

    private static func keywordList(_ keywords: [String], contains keyword: String) -> Bool {
        let key = keywordKey(keyword)
        guard !key.isEmpty else { return false }
        return keywords.contains { keywordKey($0) == key }
    }

    private static func metadataByMergingMissingSidecarFields(
        catalogMetadata: AssetMetadata,
        sidecarMetadata: AssetMetadata
    ) -> AssetMetadata {
        var mergedMetadata = catalogMetadata
        if mergedMetadata.rating == 0 {
            mergedMetadata.rating = sidecarMetadata.rating
        }
        if mergedMetadata.colorLabel == nil {
            mergedMetadata.colorLabel = sidecarMetadata.colorLabel
        }
        if mergedMetadata.flag == nil {
            mergedMetadata.flag = sidecarMetadata.flag
        }
        for keyword in sidecarMetadata.keywords where !keywordList(mergedMetadata.keywords, contains: keyword) {
            mergedMetadata.keywords.append(keyword)
        }
        if mergedMetadata.caption == nil {
            mergedMetadata.caption = sidecarMetadata.caption
        }
        if mergedMetadata.creator == nil {
            mergedMetadata.creator = sidecarMetadata.creator
        }
        if mergedMetadata.copyright == nil {
            mergedMetadata.copyright = sidecarMetadata.copyright
        }
        return mergedMetadata
    }

    private static func cleanedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func keywordKey(_ keyword: String) -> String {
        cleanedKeyword(keyword).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func portableText(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func portableCaption(from text: String) -> String? {
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return portableText(from: collapsed)
    }

    private func applyMetadataSnapshot(assetID: AssetID, metadata: AssetMetadata) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        try catalog.repository.updateMetadata(assetID: assetID) { currentMetadata in
            currentMetadata = metadata
        }
        let updatedAsset = try catalog.repository.asset(id: assetID)
        try syncMetadataSidecar(for: updatedAsset)
        try refreshCatalogSidebarCounts()
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else {
            return
        }
        assets[index] = updatedAsset
    }

    private func syncMetadataSidecar(for asset: Asset) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let generation = try catalog.repository.catalogGeneration(assetID: asset.id)
        let lastFingerprint = try catalog.repository.lastMetadataSyncFingerprint(assetID: asset.id)
        let pendingItem = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: catalog.metadataSidecarStore.sidecarURL(forOriginalAt: asset.originalURL),
            catalogGeneration: generation,
            lastSyncedFingerprint: lastFingerprint
        )
        if workerSupervisor != nil {
            try catalog.repository.recordMetadataSyncPending(pendingItem)
            upsertPendingMetadataSyncItem(pendingItem)
            try cancelStaleQueuedMetadataSyncWrites(
                keeping: asset.id,
                generation: generation
            )
            guard canAutomaticallyRetryMetadataSync(for: asset, sidecarURL: pendingItem.sidecarURL) else {
                statusMessage = "XMP write pending for \(asset.originalURL.lastPathComponent)"
                return
            }
            try enqueueMetadataSyncWork(pendingItem: pendingItem)
            return
        }
        do {
            let result = try catalog.metadataSidecarStore.write(metadata: asset.metadata, forOriginalAt: asset.originalURL)
            try catalog.repository.markMetadataSynced(
                assetID: asset.id,
                sidecarURL: result.sidecarURL,
                catalogGeneration: generation,
                fingerprint: result.fingerprint
            )
            pendingMetadataSyncItems.removeAll { $0.assetID == asset.id }
        } catch {
            try catalog.repository.recordMetadataSyncPending(pendingItem)
            upsertPendingMetadataSyncItem(pendingItem)
            statusMessage = "XMP write pending for \(asset.originalURL.lastPathComponent)"
        }
    }

    private func resolveMetadataConflictUsingCatalog(assetID: AssetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let conflict = try metadataSyncConflictItem(assetID: assetID, repository: catalog.repository)
        let asset = try catalog.repository.asset(id: assetID)
        let generation = try catalog.repository.catalogGeneration(assetID: assetID)
        let pendingItem = MetadataSyncItem(
            assetID: assetID,
            sidecarURL: conflict.sidecarURL,
            catalogGeneration: generation,
            lastSyncedFingerprint: conflict.lastSyncedFingerprint
        )

        do {
            let result = try catalog.metadataSidecarStore.write(metadata: asset.metadata, forOriginalAt: asset.originalURL)
            try catalog.repository.markMetadataSynced(
                assetID: assetID,
                sidecarURL: result.sidecarURL,
                catalogGeneration: generation,
                fingerprint: result.fingerprint
            )
            clearMetadataSyncState(assetID: assetID)
            try refreshAfterMetadataConflictResolution()
            statusMessage = "Resolved XMP conflict using catalog metadata"
        } catch {
            try catalog.repository.recordMetadataSyncPending(pendingItem)
            metadataSyncConflictItems.removeAll { $0.assetID == assetID }
            upsertPendingMetadataSyncItem(pendingItem)
            try refreshAfterMetadataConflictResolution()
            statusMessage = "XMP write pending for \(asset.originalURL.lastPathComponent)"
        }
    }

    private func resolveMetadataConflictUsingSidecar(assetID: AssetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let conflict = try metadataSyncConflictItem(assetID: assetID, repository: catalog.repository)
        let originalAsset = try catalog.repository.asset(id: assetID)
        let sidecarData = try Data(contentsOf: conflict.sidecarURL)
        let sidecarMetadata = try XMPPacket.parse(sidecarData).metadata

        let mergedMetadata = originalAsset.metadata.mergingConfirmedSidecar(sidecarMetadata)
        try catalog.repository.updateMetadata(assetID: assetID) { metadata in
            metadata = mergedMetadata
        }
        let updatedAsset = try catalog.repository.asset(id: assetID)
        let generation = try catalog.repository.catalogGeneration(assetID: assetID)
        try catalog.repository.markMetadataSynced(
            assetID: assetID,
            sidecarURL: conflict.sidecarURL,
            catalogGeneration: generation,
            fingerprint: XMPSidecarStore.fingerprint(for: sidecarData)
        )
        if let index = assets.firstIndex(where: { $0.id == assetID }) {
            assets[index] = updatedAsset
        }
        try refreshCatalogSidebarCounts()
        if originalAsset.metadata != mergedMetadata {
            recordMetadataChangeGroup(label: "Resolved XMP conflict", changes: [MetadataChange(
                assetID: assetID,
                before: originalAsset.metadata,
                after: mergedMetadata
            )])
        }
        clearMetadataSyncState(assetID: assetID)
        try refreshAfterMetadataConflictResolution()
        statusMessage = "Resolved XMP conflict using sidecar metadata"
    }

    private func resolveMetadataConflictByMergingMissingSidecarFields(assetID: AssetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let conflict = try metadataSyncConflictItem(assetID: assetID, repository: catalog.repository)
        let originalAsset = try catalog.repository.asset(id: assetID)
        let sidecarData = try Data(contentsOf: conflict.sidecarURL)
        let sidecarMetadata = try XMPPacket.parse(sidecarData).metadata
        let mergedMetadata = Self.metadataByMergingMissingSidecarFields(
            catalogMetadata: originalAsset.metadata,
            sidecarMetadata: sidecarMetadata
        )

        try catalog.repository.updateMetadata(assetID: assetID) { metadata in
            metadata = mergedMetadata
        }
        let updatedAsset = try catalog.repository.asset(id: assetID)
        let generation = try catalog.repository.catalogGeneration(assetID: assetID)
        let pendingItem = MetadataSyncItem(
            assetID: assetID,
            sidecarURL: conflict.sidecarURL,
            catalogGeneration: generation,
            lastSyncedFingerprint: conflict.lastSyncedFingerprint
        )

        if let index = assets.firstIndex(where: { $0.id == assetID }) {
            assets[index] = updatedAsset
        }
        try refreshCatalogSidebarCounts()
        if originalAsset.metadata != mergedMetadata {
            recordMetadataChangeGroup(label: "Resolved XMP conflict", changes: [MetadataChange(
                assetID: assetID,
                before: originalAsset.metadata,
                after: mergedMetadata
            )])
        }

        do {
            let result = try catalog.metadataSidecarStore.write(metadata: mergedMetadata, forOriginalAt: updatedAsset.originalURL)
            try catalog.repository.markMetadataSynced(
                assetID: assetID,
                sidecarURL: result.sidecarURL,
                catalogGeneration: generation,
                fingerprint: result.fingerprint
            )
            clearMetadataSyncState(assetID: assetID)
            try refreshAfterMetadataConflictResolution()
            statusMessage = "Resolved XMP conflict by merging sidecar fields"
        } catch {
            try catalog.repository.recordMetadataSyncPending(pendingItem)
            metadataSyncConflictItems.removeAll { $0.assetID == assetID }
            upsertPendingMetadataSyncItem(pendingItem)
            try refreshAfterMetadataConflictResolution()
            statusMessage = "XMP write pending for \(updatedAsset.originalURL.lastPathComponent)"
        }
    }

    private func metadataSyncConflictItem(assetID: AssetID, repository: CatalogRepository) throws -> MetadataSyncItem {
        if let item = metadataSyncConflictItems.first(where: { $0.assetID == assetID }) {
            return item
        }
        if let item = try repository.metadataSyncConflictItem(assetID: assetID) {
            return item
        }
        throw TeststripError.invalidState("selected asset has no XMP conflict")
    }

    private func pendingMetadataSyncItem(assetID: AssetID, repository: CatalogRepository) throws -> MetadataSyncItem {
        if let item = pendingMetadataSyncItems.first(where: { $0.assetID == assetID }) {
            return item
        }
        if let item = try repository.pendingMetadataSyncItem(assetID: assetID) {
            return item
        }
        throw TeststripError.invalidState("selected asset has no pending XMP sync")
    }

    private func clearMetadataSyncState(assetID: AssetID) {
        if pendingMetadataSyncItems.contains(where: { $0.assetID == assetID }) {
            pendingMetadataSyncCount = max(0, pendingMetadataSyncCount - 1)
        }
        if metadataSyncConflictItems.contains(where: { $0.assetID == assetID }) {
            metadataSyncConflictCount = max(0, metadataSyncConflictCount - 1)
        }
        pendingMetadataSyncItems.removeAll { $0.assetID == assetID }
        metadataSyncConflictItems.removeAll { $0.assetID == assetID }
    }

    private func refreshAfterMetadataConflictResolution() throws {
        rebuildSidebarSections()
        if metadataSyncConflictFilter {
            try reload()
        }
    }

    private func enqueueMetadataSyncCheck(for assetID: AssetID) throws {
        guard let catalog, let workerSupervisor else { return }
        let generation = try catalog.repository.catalogGeneration(assetID: assetID)
        try cancelStaleQueuedMetadataSyncChecks(keeping: assetID, generation: generation)
        guard !hasActiveMetadataSyncWork(assetID: assetID, generation: generation) else { return }
        let itemID = WorkSessionID(rawValue: "xmp-check-\(assetID.rawValue)-\(generation)-\(UUID().uuidString)")
        let item = BackgroundWorkItem(
            id: itemID,
            kind: .xmpSync,
            title: "Check XMP",
            detail: "Checking XMP sidecar",
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        metadataSyncAssetIDsByItemID[itemID] = assetID
        do {
            try workerSupervisor.enqueue(item, command: .syncMetadata(assetID: assetID))
        } catch {
            metadataSyncAssetIDsByItemID[itemID] = nil
            throw error
        }
        syncBackgroundWorkQueueFromSupervisor()
    }

    private func cancelStaleQueuedMetadataSyncChecks(keeping assetID: AssetID, generation: Int) throws {
        guard let workerSupervisor else { return }
        let keptPrefix = metadataSyncCheckPrefix(assetID: assetID, generation: generation)
        let staleQueuedChecks = currentBackgroundWorkQueue.queuedItems.filter { item in
            isSelectionMetadataSyncCheck(item) && !item.id.rawValue.hasPrefix(keptPrefix)
        }
        for item in staleQueuedChecks {
            try workerSupervisor.cancel(id: item.id)
        }
        if !staleQueuedChecks.isEmpty {
            syncBackgroundWorkQueueFromSupervisor()
        }
    }

    private func cancelStaleQueuedMetadataSyncWrites(keeping assetID: AssetID, generation: Int) throws {
        guard let workerSupervisor else { return }
        let keptID = Self.metadataSyncWorkItemID(assetID: assetID, catalogGeneration: generation).rawValue
        let staleQueuedWrites = currentBackgroundWorkQueue.queuedItems.filter { item in
            isMetadataSyncWrite(item, assetID: assetID) && item.id.rawValue != keptID
        }
        for item in staleQueuedWrites {
            try workerSupervisor.cancel(id: item.id)
            metadataSyncAssetIDsByItemID[item.id] = nil
        }
        if !staleQueuedWrites.isEmpty {
            syncBackgroundWorkQueueFromSupervisor()
        }
    }

    private func hasActiveMetadataSyncWork(assetID: AssetID, generation: Int) -> Bool {
        let writeSyncID = Self.metadataSyncWorkItemID(assetID: assetID, catalogGeneration: generation).rawValue
        let selectionCheckPrefix = metadataSyncCheckPrefix(assetID: assetID, generation: generation)
        return currentBackgroundWorkQueue.items.contains { item in
            item.kind == .xmpSync
                && [.queued, .running, .paused].contains(item.status)
                && (item.id.rawValue == writeSyncID || item.id.rawValue.hasPrefix(selectionCheckPrefix))
        }
    }

    private func metadataSyncCheckPrefix(assetID: AssetID, generation: Int) -> String {
        "xmp-check-\(assetID.rawValue)-\(generation)-"
    }

    private static func metadataSyncWorkItemID(assetID: AssetID, catalogGeneration: Int) -> WorkSessionID {
        WorkSessionID(rawValue: "xmp-\(assetID.rawValue)-\(catalogGeneration)")
    }

    private func enqueueMetadataSyncWork(
        pendingItem: MetadataSyncItem,
        placement: BackgroundWorkQueuePlacement = .back
    ) throws {
        try enqueueMetadataSyncWork(pendingItems: [pendingItem], placement: placement)
    }

    private func enqueueMetadataSyncWork(
        pendingItems: [MetadataSyncItem],
        placement: BackgroundWorkQueuePlacement = .back
    ) throws {
        guard let workerSupervisor else {
            throw TeststripError.invalidState("worker supervisor is not configured")
        }
        var requests: [(item: BackgroundWorkItem, command: WorkerCommand, placement: BackgroundWorkQueuePlacement)] = []
        for pendingItem in pendingItems {
            let itemID = Self.metadataSyncWorkItemID(
                assetID: pendingItem.assetID,
                catalogGeneration: pendingItem.catalogGeneration
            )
            if let existingItem = currentBackgroundWorkQueue.item(id: itemID),
               [.queued, .running, .paused].contains(existingItem.status) {
                continue
            }
            let item = BackgroundWorkItem(
                id: itemID,
                kind: .xmpSync,
                title: "Sync XMP",
                detail: "Writing XMP sidecar",
                completedUnitCount: 0,
                totalUnitCount: 1
            )
            metadataSyncAssetIDsByItemID[itemID] = pendingItem.assetID
            requests.append((
                item: item,
                command: .syncMetadata(assetID: pendingItem.assetID),
                placement: placement
            ))
        }
        guard !requests.isEmpty else { return }
        do {
            try workerSupervisor.enqueue(requests)
        } catch {
            for request in requests {
                metadataSyncAssetIDsByItemID[request.item.id] = nil
            }
            throw error
        }
        syncBackgroundWorkQueueFromSupervisor()
    }

    private func isSelectionMetadataSyncCheck(_ item: BackgroundWorkItem) -> Bool {
        item.kind == .xmpSync && item.title == "Check XMP"
    }

    private func isMetadataSyncWrite(_ item: BackgroundWorkItem, assetID: AssetID) -> Bool {
        item.kind == .xmpSync
            && item.title == "Sync XMP"
            && item.id.rawValue.hasPrefix("xmp-\(assetID.rawValue)-")
    }

    private func upsertPendingMetadataSyncItem(_ item: MetadataSyncItem) {
        let hadPendingItem = pendingMetadataSyncItems.contains { $0.assetID == item.assetID }
        let hadConflictItem = metadataSyncConflictItems.contains { $0.assetID == item.assetID }
        pendingMetadataSyncItems.removeAll { $0.assetID == item.assetID }
        metadataSyncConflictItems.removeAll { $0.assetID == item.assetID }
        pendingMetadataSyncItems.append(item)
        if !hadPendingItem {
            pendingMetadataSyncCount += 1
        }
        if hadConflictItem {
            metadataSyncConflictCount = max(0, metadataSyncConflictCount - 1)
        }
    }

    private func refreshMetadataSyncState() throws {
        guard let catalog else { return }
        let snapshot = try Self.metadataSyncState(repository: catalog.repository, selectedAssetID: selectedAssetID)
        pendingMetadataSyncItems = snapshot.pendingItems
        metadataSyncConflictItems = snapshot.conflictItems
        pendingMetadataSyncCount = snapshot.pendingCount
        metadataSyncConflictCount = snapshot.conflictCount
        rebuildSidebarSections()
    }

    private func refreshSelectedMetadataSyncState(for assetID: AssetID) throws {
        guard let catalog else { return }
        var snapshot = MetadataSyncStateSnapshot(
            pendingItems: pendingMetadataSyncItems,
            conflictItems: metadataSyncConflictItems,
            pendingCount: pendingMetadataSyncCount,
            conflictCount: metadataSyncConflictCount
        )
        try Self.mergeMetadataSyncState(for: assetID, repository: catalog.repository, into: &snapshot)
        pendingMetadataSyncItems = snapshot.pendingItems
        metadataSyncConflictItems = snapshot.conflictItems
    }

    private func refreshPreviewGenerationQueueStates() throws {
        guard let catalog else { return }
        clearGridPreviewCaches()
        previewGenerationQueueStates = try Self.previewGenerationQueueStates(
            repository: catalog.repository,
            selectedAssetID: selectedAssetID
        )
    }

    private func refreshSelectedPreviewGenerationQueueStates(for assetID: AssetID) throws {
        guard let catalog else { return }
        clearGridPreviewCaches()
        try Self.mergePreviewGenerationQueueStates(
            for: assetID,
            repository: catalog.repository,
            into: &previewGenerationQueueStates
        )
    }

    private func refreshSourceAvailabilitySummaries() throws {
        guard let catalog else { return }
        sourceRoots = try catalog.repository.sourceRoots()
        sourceAvailabilitySummaries = try Self.sourceAvailabilitySummaries(repository: catalog.repository)
        rebuildSidebarSections()
    }

    public func enqueueBackgroundWork(_ item: BackgroundWorkItem) {
        backgroundWorkQueue.enqueue(item)
        backgroundWorkQueue.activateRunnableItems()
    }

    public func pauseBackgroundWork() {
        do {
            if let workerSupervisor {
                try workerSupervisor.pause()
                syncBackgroundWorkQueueFromSupervisor()
            } else {
                backgroundWorkQueue.pause()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func resumeBackgroundWork() {
        do {
            if let workerSupervisor {
                try workerSupervisor.resume()
                syncBackgroundWorkQueueFromSupervisor()
            } else {
                backgroundWorkQueue.resume()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func cancelBackgroundWork() {
        do {
            let hadWorkerImport = !workerImportContextsByItemID.isEmpty
            if let workerSupervisor {
                try workerSupervisor.cancelAll()
                cancelWorkerImportContexts()
                if hadWorkerImport {
                    statusMessage = "Cancelled import"
                }
                syncBackgroundWorkQueueFromSupervisor()
            } else {
                backgroundWorkQueue.cancelAll()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func stopIdleWorkerProcess() {
        guard workerSupervisor?.stopIdleWorkerProcess() == true else { return }
        syncBackgroundWorkQueueFromSupervisor()
        statusMessage = "Worker stopped"
    }

    public func cancelBackgroundWork(id itemID: WorkSessionID) {
        do {
            if let workerSupervisor {
                try workerSupervisor.cancel(id: itemID)
                syncBackgroundWorkQueueFromSupervisor()
            } else {
                backgroundWorkQueue.cancel(id: itemID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func cancelWork(kind: WorkSessionKind) {
        let ids = backgroundWorkQueue.items
            .filter { $0.kind == kind && Self.isActiveBackgroundWorkStatus($0.status) }
            .map(\.id)
        for id in ids { cancelBackgroundWork(id: id) }
    }

    // Intentionally delegate to the queue-wide pause/resume: true per-kind
    // pause (suspending only this kind's lane while others keep running) is
    // deferred, so `kind` is currently unused.
    public func pauseWork(kind: WorkSessionKind) {
        pauseBackgroundWork()
    }

    // See pauseWork(kind:) above — same queue-wide delegation, `kind` unused.
    public func resumeWork(kind: WorkSessionKind) {
        resumeBackgroundWork()
    }

    @MainActor
    public func cancelImportWork() {
        if activeWork?.kind == .ingest || activeImportTask != nil {
            cancelActiveWork()
            return
        }

        do {
            guard let workerSupervisor, !workerImportContextsByItemID.isEmpty else { return }
            for itemID in Array(workerImportContextsByItemID.keys) {
                try workerSupervisor.cancel(id: itemID)
            }
            statusMessage = "Cancelled import"
            syncBackgroundWorkQueueFromSupervisor()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func requestPreview(
        assetID: AssetID,
        level: PreviewLevel,
        placement: BackgroundWorkQueuePlacement = .back
    ) throws {
        try requestPreview(
            assetID: assetID,
            level: level,
            placement: placement,
            recordsPendingPreview: true,
            refreshesPreviewGenerationQueueState: true
        )
    }

    private func requestPreview(
        assetID: AssetID,
        level: PreviewLevel,
        placement: BackgroundWorkQueuePlacement = .back,
        recordsPendingPreview: Bool,
        refreshesPreviewGenerationQueueState: Bool
    ) throws {
        if previewURL(for: assetID, levels: [level]) != nil {
            return
        }
        guard let workerSupervisor else {
            throw TeststripError.invalidState("worker supervisor is not configured")
        }
        let itemID = Self.previewWorkItemID(assetID: assetID, level: level)
        if let existingItem = currentBackgroundWorkQueue.item(id: itemID),
           Self.isActiveBackgroundWorkStatus(existingItem.status) {
            if placement == .front, try workerSupervisor.promoteQueuedItem(id: itemID) {
                syncBackgroundWorkQueueFromSupervisor()
            }
            return
        }
        if recordsPendingPreview, let catalog {
            try catalog.repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: assetID, level: level))
            if refreshesPreviewGenerationQueueState {
                try refreshPreviewGenerationQueueStates()
            }
        }

        let item = BackgroundWorkItem(
            id: itemID,
            kind: .previewGeneration,
            title: "Generate preview",
            detail: "Rendering \(level.rawValue) preview",
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        try workerSupervisor.enqueue(
            item,
            command: .generatePreview(assetID: assetID, level: level),
            placement: placement
        )
        syncBackgroundWorkQueueFromSupervisor()
    }

    public func retrySelectedPreviewGenerationFailures() throws {
        let failures = selectedPreviewGenerationFailures
        guard !failures.isEmpty else { return }
        guard selectedAsset?.availability.requiresCachedPreviewOnly != true else {
            throw TeststripError.invalidState("original is unavailable")
        }
        for failure in failures {
            try requestPreview(assetID: failure.item.assetID, level: failure.item.level, placement: .front)
        }
    }

    private func enqueuePendingPreviewGeneration(excluding excludedItemIDs: Set<WorkSessionID> = []) throws {
        guard let catalog, let workerSupervisor else { return }
        var existingPreviewWorkItemIDs = Self.previewGenerationWorkItemIDs(in: currentBackgroundWorkQueue)
        let availableSlotCount = max(
            0,
            Self.pendingPreviewRecoveryBatchSize - Self.activePreviewGenerationWorkCount(in: currentBackgroundWorkQueue)
        )
        guard availableSlotCount > 0 else {
            schedulePreviewGenerationQueueStatesRefresh()
            return
        }
        var enqueuedCount = 0
        var requests: [(item: BackgroundWorkItem, command: WorkerCommand, placement: BackgroundWorkQueuePlacement)] = []
        for pendingItem in try catalog.repository.pendingPreviewGenerationItems(
            limit: Self.pendingPreviewRecoveryBatchSize,
            maximumAttemptCount: Self.previewGenerationMaximumAutomaticAttempts,
            requiresAvailableOriginal: true
        ) {
            let itemID = Self.previewWorkItemID(assetID: pendingItem.assetID, level: pendingItem.level)
            if excludedItemIDs.contains(itemID) {
                continue
            }
            if existingPreviewWorkItemIDs.contains(itemID) {
                continue
            }
            let asset = try catalog.repository.asset(id: pendingItem.assetID)
            if asset.availability.requiresCachedPreviewOnly {
                continue
            }
            if previewURL(for: pendingItem.assetID, levels: [pendingItem.level]) != nil {
                try catalog.repository.markPreviewGenerated(assetID: pendingItem.assetID, level: pendingItem.level)
                continue
            }
            let workItem = BackgroundWorkItem(
                id: itemID,
                kind: .previewGeneration,
                title: "Generate preview",
                detail: "Rendering \(pendingItem.level.rawValue) preview",
                completedUnitCount: 0,
                totalUnitCount: 1
            )
            requests.append((
                item: workItem,
                command: .generatePreview(assetID: pendingItem.assetID, level: pendingItem.level),
                placement: .back
            ))
            existingPreviewWorkItemIDs.insert(itemID)
            enqueuedCount += 1
            if enqueuedCount >= availableSlotCount {
                break
            }
        }
        try workerSupervisor.enqueue(requests)
        schedulePreviewGenerationQueueStatesRefresh()
    }

    // One geocoding activity at a time; a completed batch re-dispatches under the
    // same ID until the queue drains (Task 7). Offline is graceful: no queued
    // coordinates means no dispatch, and worker failures re-queue rather than
    // erroring the UI.
    static let geocodeWorkItemID = WorkSessionID(rawValue: "geocode-batch")
    static let geocodeBatchSize = 50
    static let geocodeEnqueueScanLimit = 500

    func enqueuePendingGeocoding() throws {
        guard let catalog, let workerSupervisor else { return }
        _ = try catalog.repository.enqueueMissingGeocodeCoordinates(limit: Self.geocodeEnqueueScanLimit)
        // Gate on rows still eligible for a retry, not raw queue depth: a
        // terminally-failed coordinate (attempt_count at the max) stays in
        // geocode_queue for visibility but must never be redispatched, or a
        // completed-but-empty batch would requeue itself in a tight loop.
        let queueDepth = try catalog.repository.pendingGeocodeQueueDepth(
            maximumAttemptCount: WorkerCommandExecutor.reverseGeocodeMaximumAttemptCount
        )
        guard queueDepth > 0 else { return }
        if let existingItem = currentBackgroundWorkQueue.item(id: Self.geocodeWorkItemID),
           Self.isActiveBackgroundWorkStatus(existingItem.status) {
            return
        }
        let item = BackgroundWorkItem(
            id: Self.geocodeWorkItemID,
            kind: .geocoding,
            title: "Geocoding",
            detail: "Reading locations",
            completedUnitCount: 0,
            totalUnitCount: queueDepth
        )
        try workerSupervisor.enqueue(item, command: .reverseGeocodeBatch(limit: Self.geocodeBatchSize))
        syncBackgroundWorkQueueFromSupervisor()
    }

    // Backfills coordinates for catalogs imported before GPS extraction shipped.
    // Bounded and resumable: each batch re-reads only online originals still
    // missing a latitude, and a completed batch re-dispatches until none remain,
    // then hands the newly-read coordinates to the geocoding pipeline.
    static let coordinateBackfillWorkItemID = WorkSessionID(rawValue: "coordinate-backfill")
    static let coordinateBackfillBatchSize = 200

    public func beginCoordinateBackfill() throws {
        guard let catalog, let workerSupervisor else { return }
        let assetIDs = try catalog.repository.assetsMissingCoordinates(limit: Self.coordinateBackfillBatchSize)
        guard !assetIDs.isEmpty else { return }
        if let existingItem = currentBackgroundWorkQueue.item(id: Self.coordinateBackfillWorkItemID),
           Self.isActiveBackgroundWorkStatus(existingItem.status) {
            return
        }
        let item = BackgroundWorkItem(
            id: Self.coordinateBackfillWorkItemID,
            kind: .locationBackfill,
            title: "Reading locations",
            detail: "Reading locations for existing photos",
            completedUnitCount: 0,
            totalUnitCount: assetIDs.count
        )
        try workerSupervisor.enqueue(item, command: .backfillCoordinates(assetIDs: assetIDs))
        syncBackgroundWorkQueueFromSupervisor()
    }

    // MARK: - Sidecar rescan (out-of-band edit detection, Jesse's ruling 2026-07-11)

    /// Fingerprint-checks synced sidecars for out-of-band edits and re-enters
    /// changed ones into the existing planner flow (pending or conflict).
    /// Runs the file walk off the main actor on its own catalog connection,
    /// then refreshes sync counts and hands new pending rows to the worker.
    @MainActor
    @discardableResult
    public func checkSidecarsForChanges(
        scopeAssetIDs: [AssetID]? = nil,
        announceWhenUnchanged: Bool = false
    ) async throws -> SidecarRescanSummary {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let paths = catalog.paths
        let scope = scopeAssetIDs.map(Set.init)
        let summary = try await Task.detached(priority: .utility) {
            let backgroundCatalog = try AppCatalog.open(paths: paths)
            return try SidecarRescanService().rescanSyncedSidecars(
                repository: backgroundCatalog.repository,
                assetIDs: scope
            )
        }.value
        if summary.pendingCount > 0 || summary.conflictCount > 0 {
            try refreshMetadataSyncState()
            try enqueuePendingMetadataSync()
            statusMessage = Self.sidecarRescanStatusText(summary)
        } else if announceWhenUnchanged {
            statusMessage = Self.sidecarRescanStatusText(summary)
        }
        return summary
    }

    /// Metadata ▸ Check Sidecars for Changes: on-demand rescan over the
    /// whole catalog. Deliberately not filter-scoped — persona-6 Priya's
    /// still-active Pick chip silently excluded the edited asset and a real
    /// out-of-band edit went unnoticed; an integrity check must not depend
    /// on whatever library filters happen to be stacked. Always reports a
    /// completion summary ("Checked N sidecars — …").
    @MainActor
    public func checkSidecarsForChangesInCurrentScope() async {
        do {
            _ = try await checkSidecarsForChanges(announceWhenUnchanged: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Launch-time rescan (catalog open): whole-catalog, quiet when nothing
    /// changed, never blocks the UI. Failures are non-fatal — the menu
    /// command re-runs the same check on demand.
    @MainActor
    public func performLaunchSidecarRescan() async {
        _ = try? await checkSidecarsForChanges()
    }

    static func sidecarRescanStatusText(_ summary: SidecarRescanSummary) -> String {
        let checked = "Checked \(summary.scannedCount) sidecar\(summary.scannedCount == 1 ? "" : "s")"
        var parts: [String] = []
        if summary.pendingCount > 0 {
            parts.append("\(summary.pendingCount) changed on disk, queued to re-sync")
        }
        if summary.conflictCount > 0 {
            parts.append("\(summary.conflictCount) conflict\(summary.conflictCount == 1 ? "" : "s")")
        }
        guard !parts.isEmpty else {
            return "\(checked) — no changes"
        }
        return "\(checked) — \(parts.joined(separator: " · "))"
    }

    private func enqueuePendingMetadataSync() throws {
        guard let catalog, workerSupervisor != nil else { return }
        var enqueuedCount = 0
        for pendingItem in try catalog.repository.pendingMetadataSyncItems() {
            guard enqueuedCount < Self.pendingMetadataSyncRecoveryBatchSize else {
                break
            }
            // A pending row whose asset is gone (trashed, or a historic orphan)
            // must not abort the scan — this runs during AppModel.load, where a
            // thrown notFound is fatal. Drop the dangling row and move on.
            let asset: Asset
            do {
                asset = try catalog.repository.asset(id: pendingItem.assetID)
            } catch CatalogError.notFound {
                try catalog.repository.deleteMetadataSyncState(assetID: pendingItem.assetID)
                continue
            }
            guard canAutomaticallyRetryMetadataSync(for: asset, sidecarURL: pendingItem.sidecarURL) else {
                continue
            }
            let itemID = Self.metadataSyncWorkItemID(
                assetID: pendingItem.assetID,
                catalogGeneration: pendingItem.catalogGeneration
            )
            if let existingItem = currentBackgroundWorkQueue.item(id: itemID),
               [.queued, .running, .paused].contains(existingItem.status) {
                continue
            }
            try enqueueMetadataSyncWork(pendingItem: pendingItem)
            enqueuedCount += 1
        }
    }

    private func metadataSyncRetryCandidatesInCurrentScope(
        repository: CatalogRepository,
        limit: Int
    ) throws -> [(asset: Asset, pendingItem: MetadataSyncItem)] {
        guard limit > 0 else { return [] }
        let scopeAssets = try metadataSyncRetryScopeAssets(repository: repository, limit: limit)
        var candidates: [(asset: Asset, pendingItem: MetadataSyncItem)] = []
        for asset in scopeAssets {
            guard let pendingItem = try repository.pendingMetadataSyncItem(assetID: asset.id),
                  canAutomaticallyRetryMetadataSync(for: asset, sidecarURL: pendingItem.sidecarURL),
                  !hasActiveMetadataSyncWork(assetID: asset.id, generation: pendingItem.catalogGeneration) else {
                continue
            }
            candidates.append((asset, pendingItem))
        }
        return candidates
    }

    private func metadataSyncRetryScopeAssets(
        repository: CatalogRepository,
        limit: Int
    ) throws -> [Asset] {
        if let explicitAssetIDs = selectedExplicitAssetIDs {
            return try repository.assets(ids: explicitAssetIDs, limit: limit)
        }
        if let query = currentLibraryQuery() {
            return try repository.allAssets(matching: query, limit: limit)
        }
        return try repository.allAssets(limit: limit)
    }

    private func canAutomaticallyRetryMetadataSync(for asset: Asset, sidecarURL: URL) -> Bool {
        guard !asset.availability.requiresCachedPreviewOnly else {
            return false
        }
        let sidecarDirectory = sidecarURL.deletingLastPathComponent()
        return FileManager.default.isWritableFile(atPath: sidecarDirectory.path)
    }

    public func requestVisibleGridPreview(assetID: AssetID) throws {
        if let asset = assets.first(where: { $0.id == assetID }),
           asset.availability.requiresCachedPreviewOnly {
            return
        }

        let request = PreviewScheduler().request(
            assetID: assetID,
            context: .grid(distanceFromViewport: 0)
        )
        try requestPreview(assetID: request.assetID, level: request.level, placement: .front)
    }

    public func previewCacheGeneration(for assetID: AssetID) -> Int {
        previewCacheGenerationsByAssetID[assetID] ?? 0
    }

    public func evaluationSignalGeneration(for assetID: AssetID) -> Int {
        evaluationSignalGenerationsByAssetID[assetID] ?? 0
    }

    public func requestVisibleLoupePreview(assetID: AssetID) throws {
        try requestVisibleLoupeAssetPreview(assetID: assetID)
        try prefetchLoupeNeighborLargePreviews(around: assetID)
    }

    private func requestVisibleLoupeAssetPreview(assetID: AssetID) throws {
        let request = PreviewScheduler().request(
            assetID: assetID,
            context: .loupe(isVisible: true, requestedFullResolution: false)
        )
        if previewURL(for: assetID, levels: [request.level]) != nil {
            return
        }
        if [.offline, .missing].contains(try refreshAvailability(for: assetID)) {
            return
        }
        if request.level == .large, previewURL(for: assetID, levels: [.medium]) == nil {
            try requestPreview(assetID: assetID, level: .medium, placement: .front)
        }
        try requestPreview(assetID: assetID, level: request.level, placement: .front)
    }

    // Warms the immediate neighbors' large previews so arrow-key advance in
    // the loupe lands on a sharp frame. Bounded to one ahead and one behind;
    // frames whose originals are unreachable are skipped.
    private func prefetchLoupeNeighborLargePreviews(around assetID: AssetID) throws {
        guard workerSupervisor != nil else { return }
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }
        for neighborIndex in [index + 1, index - 1] where assets.indices.contains(neighborIndex) {
            let neighbor = assets[neighborIndex]
            guard !neighbor.availability.requiresCachedPreviewOnly else { continue }
            let request = PreviewScheduler().request(
                assetID: neighbor.id,
                context: .loupe(isVisible: false, requestedFullResolution: false)
            )
            try requestPreview(assetID: request.assetID, level: request.level, placement: .back)
        }
    }

    // Escalates the zoomed loupe frame to an original-resolution render when
    // the best cached preview cannot cover the asset's pixels at 1:1. The
    // render happens in the worker through the normal preview queue; nothing
    // decodes on the main thread.
    public func requestLoupeFullResolutionPreview(assetID: AssetID) throws {
        guard LoupeZoomRenderPolicy.fullResolutionIsRequired(
            cachedLevel: cachedLoupePreviewLevel(for: assetID),
            assetMaxPixelDimension: assetMaxPixelDimension(for: assetID)
        ) else {
            return
        }
        guard let asset = assets.first(where: { $0.id == assetID }),
              !asset.availability.requiresCachedPreviewOnly else {
            return
        }
        let request = PreviewScheduler().request(
            assetID: assetID,
            context: .loupe(isVisible: true, requestedFullResolution: true)
        )
        try requestPreview(assetID: request.assetID, level: request.level, placement: .front)
    }

    public func loupeZoomFullResolutionStatus(for assetID: AssetID) -> LoupeZoomFullResolutionStatus {
        guard LoupeZoomRenderPolicy.fullResolutionIsRequired(
            cachedLevel: cachedLoupePreviewLevel(for: assetID),
            assetMaxPixelDimension: assetMaxPixelDimension(for: assetID)
        ) else {
            return .satisfied
        }
        if let asset = assets.first(where: { $0.id == assetID }),
           asset.availability.requiresCachedPreviewOnly {
            return .unavailable
        }
        let itemID = Self.previewWorkItemID(assetID: assetID, level: .original)
        if backgroundWorkQueue.item(id: itemID)?.status == .failed {
            return .unavailable
        }
        return .loading
    }

    private func assetMaxPixelDimension(for assetID: AssetID) -> Int? {
        guard let metadata = assets.first(where: { $0.id == assetID })?.technicalMetadata else {
            return nil
        }
        return max(metadata.pixelWidth, metadata.pixelHeight)
    }

    public func requestVisibleComparePreviews() throws {
        let compareAssets = compareAssets()
        if let selectedAssetID,
           compareAssets.contains(where: { $0.id == selectedAssetID && !$0.availability.requiresCachedPreviewOnly }),
           previewURL(for: selectedAssetID, levels: [.medium]) != nil {
            try requestPreview(assetID: selectedAssetID, level: .large, placement: .front)
        }

        for asset in compareAssets {
            guard !asset.availability.requiresCachedPreviewOnly else { continue }
            try requestPreview(assetID: asset.id, level: .medium, placement: .front)
        }
    }

    public func requestEvaluation(assetID: AssetID, provider: String = AppModel.defaultEvaluationProviderName) throws {
        guard let workerSupervisor else {
            throw TeststripError.invalidState("worker supervisor is not configured")
        }
        guard hasCachedPreview(for: assetID) else {
            throw TeststripError.invalidState("no cached preview for \(assetID.rawValue)")
        }
        let itemID = WorkSessionID(rawValue: "evaluation-\(assetID.rawValue)-\(provider)")
        if let existingItem = currentBackgroundWorkQueue.item(id: itemID),
           Self.isActiveBackgroundWorkStatus(existingItem.status) {
            return
        }

        let item = BackgroundWorkItem(
            id: itemID,
            kind: .recognition,
            title: "Evaluate photo",
            detail: "Running \(provider)",
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        evaluationAssetIDsByItemID[itemID] = assetID
        evaluationProvidersByItemID[itemID] = provider
        do {
            try workerSupervisor.enqueue(item, command: .runEvaluation(assetID: assetID, provider: provider))
        } catch {
            evaluationAssetIDsByItemID[itemID] = nil
            evaluationProvidersByItemID[itemID] = nil
            throw error
        }
        syncBackgroundWorkQueueFromSupervisor()
    }

    public func requestSelectedAssetEvaluation(provider: String = AppModel.defaultEvaluationProviderName) throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        try requestEvaluation(assetID: selectedAssetID, provider: provider)
    }

    public func retrySelectedProviderFailure(provider: String) throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        try requestEvaluation(assetID: selectedAssetID, provider: provider)
    }

    public func requestSelectedAssetEvaluations(providers: [String] = AppModel.defaultEvaluationProviderNames) throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        for provider in providers {
            try requestEvaluation(assetID: selectedAssetID, provider: provider)
        }
    }

    public func requestVisibleAssetEvaluations(providers: [String] = AppModel.defaultEvaluationProviderNames) throws {
        guard !assets.isEmpty else {
            throw TeststripError.invalidState("no visible assets")
        }
        let evaluableAssets = assets.filter { hasCachedPreview(for: $0.id) }
        guard !evaluableAssets.isEmpty else {
            throw TeststripError.invalidState("no visible assets with cached previews")
        }
        for asset in evaluableAssets {
            for provider in providers {
                try requestEvaluation(assetID: asset.id, provider: provider)
            }
        }
    }

    /// Runs autopilot over a scope: gathers already-computed signals, plans
    /// provisional pick/reject/keyword proposals with the pure planner,
    /// replaces any prior pending proposals for the identical scope, persists
    /// the new set for run tracking/rationale, and immediately applies each
    /// proposal's pick/reject/keyword to `metadata_json` as AI-unconfirmed
    /// (tentative) — see `applyTentativeAutopilotProposals`. Catalog-only: an
    /// unconfirmed write never syncs to the XMP sidecar
    /// (`AssetMetadata.confirmedProjection`) and (Task 13) never drives
    /// destructive/committing operations. A later `commitAutopilotProposals`
    /// confirms them (portable, sidecar-synced); `undoAutopilotRun` reverts
    /// this run's whole tentative batch in one gesture.
    @discardableResult
    public func runAutopilot(scope: AutopilotScope = .visible) throws -> AutopilotRunSummary {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let scopeAssets = try autopilotScopeAssets(scope, repository: catalog.repository)

        var signalsByAssetID: [AssetID: [EvaluationSignal]] = [:]
        var keywordCandidatesByAssetID: [AssetID: [String]] = [:]
        for asset in scopeAssets {
            let signals = (try? catalog.repository.evaluationSignals(assetID: asset.id)) ?? []
            signalsByAssetID[asset.id] = signals
            // Only a *confirmed* existing keyword should block re-proposing
            // it: an unconfirmed one is still this same tentative mechanism's
            // own prior proposal, and excluding it here would silently drop
            // its proposal row (and thus its reviewability) on a re-run of
            // the identical scope, even though the tentative keyword stays
            // stuck in metadata forever.
            let confirmedKeywords = asset.metadata.keywords.filter {
                !asset.metadata.aiUnconfirmedKeywords.contains($0)
            }
            let candidates = Self.autopilotKeywordCandidates(
                from: signals,
                existingKeywords: confirmedKeywords
            )
            if !candidates.isEmpty {
                keywordCandidatesByAssetID[asset.id] = candidates
            }
        }

        let scopeKey = scopeAssets.map(\.id.rawValue).sorted().joined(separator: ",")
        if let priorRunID = lastAutopilotRunIDByScopeKey[scopeKey] {
            try catalog.repository.deleteAutopilotProposals(runID: priorRunID)
        }

        let runID = AutopilotRunID.new()
        let planner = AutopilotProposalPlanner(stackBuilder: stackBuilder())
        let input = AutopilotPlanInput(
            assets: scopeAssets,
            signalsByAssetID: signalsByAssetID,
            keywordCandidatesByAssetID: keywordCandidatesByAssetID
        )
        let proposals = planner.proposals(for: input, runID: runID, now: Date())
        try catalog.repository.save(proposals)
        lastAutopilotRunIDByScopeKey[scopeKey] = runID
        try applyTentativeAutopilotProposals(proposals, runID: runID)

        let summary = AutopilotRunSummary(
            runID: runID,
            keeperCount: proposals.filter { $0.kind == .pick }.count,
            rejectCount: proposals.filter { $0.kind == .reject }.count,
            keywordCount: proposals.filter { $0.kind == .keyword }.count,
            stackCount: autopilotStackCount(for: scopeAssets)
        )
        autopilotRunSummary = summary
        pendingAutopilotProposals = (try? catalog.repository.autopilotProposals(status: .pending)) ?? []
        statusMessage = "Autopilot: \(summary.bannerText)"
        return summary
    }

    /// Applies one run's `.pick`/`.reject`/`.keyword` proposals to
    /// `metadata_json` immediately, marked AI-unconfirmed — the fold-in of
    /// autopilot into the auto-apply provenance model (`promoteMetadataLabels`,
    /// Task 7). Skips a proposal whose asset already carries a *confirmed*
    /// flag (the user decided already) or whose specific value the user
    /// previously removed (`removed_ai_labels`) — same skip rule
    /// `promoteMetadataLabels` uses for captions/keywords. Catalog-only write
    /// (`updateMetadata`, not `applyMetadataSnapshot`) since an AI-unconfirmed
    /// delta never has a portable projection to sync. Records the touched
    /// assets' pre-run/post-run snapshots as one run-time undo group so
    /// `undoAutopilotRun` can revert the whole batch.
    private func applyTentativeAutopilotProposals(_ proposals: [AutopilotProposal], runID: AutopilotRunID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        var changes: [AutopilotTentativeChange] = []
        let proposalsByAssetID = Dictionary(grouping: proposals, by: { $0.assetID })
        for (assetID, assetProposals) in proposalsByAssetID {
            let removedLabels = try catalog.repository.removedAILabels(assetID: assetID)
            let originalAsset = try catalog.repository.asset(id: assetID)
            var updatedMetadata = originalAsset.metadata
            var tentativeFields: Set<MetadataField> = []
            var tentativeKeywords: Set<String> = []
            for proposal in assetProposals {
                switch proposal.kind {
                case .pick, .reject:
                    let flagValue: PickFlag = proposal.kind == .pick ? .pick : .reject
                    let hasConfirmedFlag = updatedMetadata.flag != nil && !updatedMetadata.aiUnconfirmedFields.contains(.flag)
                    guard !hasConfirmedFlag,
                          !removedLabels.contains(RemovedAILabel(field: .flag, value: flagValue.rawValue)) else {
                        continue
                    }
                    updatedMetadata.flag = flagValue
                    updatedMetadata.aiUnconfirmedFields.insert(.flag)
                    tentativeFields.insert(.flag)
                case .keyword:
                    guard let keyword = proposal.keyword,
                          !Self.keywordList(updatedMetadata.keywords, contains: keyword),
                          !removedLabels.contains(RemovedAILabel(field: .keyword, value: keyword)) else {
                        continue
                    }
                    updatedMetadata.keywords.append(keyword)
                    updatedMetadata.aiUnconfirmedKeywords.insert(keyword)
                    tentativeKeywords.insert(keyword)
                }
            }
            guard updatedMetadata != originalAsset.metadata else { continue }
            try catalog.repository.updateMetadata(assetID: assetID) { $0 = updatedMetadata }
            try refreshInMemoryAsset(assetID)
            changes.append(AutopilotTentativeChange(
                assetID: assetID,
                before: originalAsset.metadata,
                after: updatedMetadata,
                tentativeFields: tentativeFields,
                tentativeKeywords: tentativeKeywords
            ))
        }
        lastAutopilotRunUndoGroup = changes.isEmpty ? nil : AutopilotTentativeChangeGroup(changes: changes)
        lastAutopilotRunUndoRunID = changes.isEmpty ? nil : runID
    }

    /// On-demand autopilot entry point for the assets currently loaded in the
    /// library grid. This is a new *entry point* into `runAutopilot(scope:)`:
    /// it reuses the same run→banner→review→commit/undo machinery as the
    /// post-import path, but is triggered by an explicit user gesture on a
    /// static catalog rather than by an armed import finishing. Autopilot
    /// proposes only from evaluation signals, so if none of the visible frames
    /// carry evaluations there is nothing to propose from; in that case it
    /// surfaces a status message rather than creating an empty run. Tentative
    /// only: the run applies its proposals to catalog metadata as
    /// AI-unconfirmed; the user commits to confirm them (portable, synced).
    @discardableResult
    public func runAutopilotOnCurrentScope() throws -> AutopilotRunSummary? {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let hasEvaluations = assets.contains { asset in
            !((try? catalog.repository.evaluationSignals(assetID: asset.id)) ?? []).isEmpty
        }
        guard hasEvaluations else {
            statusMessage = "Autopilot: no evaluated photos in view to run on"
            return nil
        }
        return try runAutopilot(scope: .visible)
    }

    /// The marquee "Find Best Shots" action. It ensures the current scope has
    /// been evaluated (triggering a read pass if frames still need one), then
    /// lands the user on their ranked best shots — Potential Picks if the
    /// likely-pick queue has anything, else their committed Picks. When the
    /// scope is fully evaluated and nothing ranks, it surfaces a plain-language
    /// status instead of routing to an empty queue, so the user is never
    /// dead-ended on a bare zero. Reads only; writes nothing.
    @discardableResult
    public func findBestShots() throws -> FindBestShotsPlan {
        let plan = FindBestShotsRouter.plan(
            pickCount: reviewQueueCounts[.picks] ?? 0,
            potentialPickCount: reviewQueueCounts[.potentialPicks] ?? 0,
            canEvaluateScope: canRequestCurrentScopeAssetEvaluations,
            needsEvaluationCount: reviewQueueCounts[.needsEvaluation] ?? 0
        )
        if plan.shouldTriggerEvaluation {
            try? requestCurrentScopeAssetEvaluations()
        }
        switch plan.route {
        case .reviewQueue(let queue):
            try selectSidebarTarget(.reviewQueue(queue))
        case .nothingRanked(let message):
            statusMessage = message
        }
        return plan
    }

    public var canFindBestShots: Bool {
        catalog != nil && !assets.isEmpty
    }

    public func autopilotProposalDecision(for assetID: AssetID) -> AutopilotProposalKind? {
        pendingAutopilotProposals.first {
            $0.assetID == assetID && ($0.kind == .pick || $0.kind == .reject)
        }?.kind
    }

    public func dismissAutopilotRunSummary() {
        autopilotRunSummary = nil
    }

    public var autopilotReviewProposalCount: Int {
        pendingAutopilotProposals.count
    }

    /// Narrows the grid to just the assets that carry a pending proposal so the
    /// user can review the provisional keeps/cuts (KEEP/CUT badges stay
    /// visible) and commit or dismiss them. Reads only; writes nothing.
    public func beginAutopilotReview() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetIDs = distinctPendingAutopilotProposalAssetIDs()
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        let loadedAssets = try catalog.repository.assets(ids: assetIDs, limit: assetIDs.count)
        replaceAssets(loadedAssets)
        totalAssetCount = try catalog.repository.assetCount(ids: assetIDs)
        isAutopilotReviewActive = true
        selectedView = .grid
    }

    private func distinctPendingAutopilotProposalAssetIDs() -> [AssetID] {
        var seen = Set<AssetID>()
        var orderedIDs: [AssetID] = []
        for proposal in pendingAutopilotProposals where seen.insert(proposal.assetID).inserted {
            orderedIDs.append(proposal.assetID)
        }
        return orderedIDs
    }

    /// Confirms the pending proposals for the given assets: each one's
    /// pick/reject/keyword is already sitting in `metadata_json` as
    /// AI-unconfirmed (`applyTentativeAutopilotProposals`, run time) — commit
    /// graduates it to confirmed by clearing `aiUnconfirmedFields`/
    /// `aiUnconfirmedKeywords`, through the grouped-undo, sidecar-syncing
    /// metadata path (`applyMetadataSnapshot`) as ONE undo group labeled
    /// "Autopilot" (the same generic Cmd+Z path `confirmAIField`/
    /// `confirmAIKeyword` feed for a single asset — batched here since
    /// committing is a multi-asset gesture), then marks those proposals
    /// `committed`. This is the explicit user gesture that makes a tentative
    /// autopilot decision portable to the XMP sidecar.
    @discardableResult
    public func commitAutopilotProposals(assetIDs: [AssetID]) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let targetAssetIDs = Set(assetIDs)
        let targetProposals = pendingAutopilotProposals.filter { targetAssetIDs.contains($0.assetID) }
        guard !targetProposals.isEmpty else { return 0 }

        let proposalsByAsset = Dictionary(grouping: targetProposals, by: { $0.assetID })
        var orderedTargetAssetIDs: [AssetID] = []
        var seenAssets = Set<AssetID>()
        for proposal in pendingAutopilotProposals where targetAssetIDs.contains(proposal.assetID) {
            if seenAssets.insert(proposal.assetID).inserted {
                orderedTargetAssetIDs.append(proposal.assetID)
            }
        }

        var changes: [MetadataChange] = []
        var committedProposalIDs: [AutopilotProposalID] = []
        var staleProposalIDs: [AutopilotProposalID] = []
        for assetID in orderedTargetAssetIDs {
            guard let assetProposals = proposalsByAsset[assetID] else { continue }
            let originalAsset: Asset
            do {
                originalAsset = try catalog.repository.asset(id: assetID)
            } catch CatalogError.notFound {
                // The asset was trashed/deleted after the proposal was
                // generated. Its cascade should already have removed the
                // proposal row, but mark it stale defensively and keep
                // committing the rest of the batch rather than aborting.
                staleProposalIDs.append(contentsOf: assetProposals.map(\.id))
                continue
            }
            var updatedMetadata = originalAsset.metadata
            for proposal in assetProposals {
                switch proposal.kind {
                case .pick, .reject:
                    updatedMetadata.aiUnconfirmedFields.remove(.flag)
                case .keyword:
                    if let keyword = proposal.keyword {
                        updatedMetadata.aiUnconfirmedKeywords.remove(keyword)
                    }
                }
                committedProposalIDs.append(proposal.id)
            }
            if updatedMetadata != originalAsset.metadata {
                try applyMetadataSnapshot(assetID: assetID, metadata: updatedMetadata)
                changes.append(MetadataChange(
                    assetID: assetID,
                    before: originalAsset.metadata,
                    after: updatedMetadata
                ))
            }
        }

        recordMetadataChangeGroup(label: "Autopilot", changes: changes)
        try catalog.repository.updateAutopilotProposalStatus(ids: committedProposalIDs, to: .committed)
        if !staleProposalIDs.isEmpty {
            try catalog.repository.updateAutopilotProposalStatus(ids: staleProposalIDs, to: .dismissed)
        }
        pendingAutopilotProposals = (try? catalog.repository.autopilotProposals(status: .pending)) ?? []
        try refreshCatalogSidebarCounts()
        statusMessage = staleProposalIDs.isEmpty
            ? "Committed \(committedProposalIDs.count) autopilot decisions"
            : "Committed \(committedProposalIDs.count) autopilot decisions (\(staleProposalIDs.count) skipped — asset no longer available)"
        return committedProposalIDs.count
    }

    @discardableResult
    public func commitAllAutopilotProposals() throws -> Int {
        try commitAutopilotProposals(assetIDs: distinctPendingAutopilotProposalAssetIDs())
    }

    /// Dismisses the pending proposals for the given assets. Since the
    /// proposal's pick/reject/keyword was already written to `metadata_json`
    /// as AI-unconfirmed at run time, dismissing it also clears that specific
    /// tentative value — but only if it's still unconfirmed, never touching a
    /// value the user has since confirmed — so nothing is left stuck in limbo
    /// once it's no longer reviewable. Catalog-only, same as the original
    /// tentative write.
    @discardableResult
    public func dismissAutopilotProposals(assetIDs: [AssetID]) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let targetAssetIDs = Set(assetIDs)
        let targetProposals = pendingAutopilotProposals.filter { targetAssetIDs.contains($0.assetID) }
        guard !targetProposals.isEmpty else { return 0 }

        let proposalsByAsset = Dictionary(grouping: targetProposals, by: { $0.assetID })
        for (assetID, assetProposals) in proposalsByAsset {
            try catalog.repository.updateMetadata(assetID: assetID) { metadata in
                for proposal in assetProposals {
                    switch proposal.kind {
                    case .pick, .reject:
                        guard metadata.aiUnconfirmedFields.contains(.flag) else { continue }
                        metadata.flag = nil
                        metadata.aiUnconfirmedFields.remove(.flag)
                    case .keyword:
                        guard let keyword = proposal.keyword,
                              metadata.aiUnconfirmedKeywords.contains(keyword) else { continue }
                        metadata.keywords.removeAll { $0 == keyword }
                        metadata.aiUnconfirmedKeywords.remove(keyword)
                    }
                }
            }
            try refreshInMemoryAsset(assetID)
        }
        try catalog.repository.updateAutopilotProposalStatus(ids: targetProposals.map(\.id), to: .dismissed)
        pendingAutopilotProposals = (try? catalog.repository.autopilotProposals(status: .pending)) ?? []
        statusMessage = "Dismissed \(targetProposals.count) proposals"
        return targetProposals.count
    }

    public var canUndoAutopilotRun: Bool {
        lastAutopilotRunUndoGroup != nil
    }

    /// Reverses the last autopilot run's tentative writes in one gesture:
    /// reverts the run-time metadata undo group captured when the run first
    /// applied its pick/reject/keyword proposals
    /// (`applyTentativeAutopilotProposals`) — independent of the shared
    /// `metadataUndoStack`/Cmd+Z, which `commitAutopilotProposals`'s confirm
    /// step uses instead — then returns that run's proposals (including any
    /// since committed) to `pending` so they are reviewable again (and their
    /// KEEP/CUT badges reappear).
    public func undoAutopilotRun() throws {
        guard let group = lastAutopilotRunUndoGroup else { return }
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        for change in group.changes.reversed() {
            try revertAutopilotTentativeChange(change)
        }
        if let runID = lastAutopilotRunUndoRunID {
            let committedProposalIDs = try catalog.repository.autopilotProposals(runID: runID)
                .filter { $0.status == .committed }
                .map(\.id)
            try catalog.repository.updateAutopilotProposalStatus(ids: committedProposalIDs, to: .pending)
            pendingAutopilotProposals = (try? catalog.repository.autopilotProposals(status: .pending)) ?? []
        }
        lastAutopilotRunUndoGroup = nil
        lastAutopilotRunUndoRunID = nil
        statusMessage = "Undid autopilot batch"
    }

    /// Reverts one asset's run-time tentative contribution, merge-aware:
    /// touches only the fields/keywords THIS run added
    /// (`change.tentativeFields`/`tentativeKeywords`), and only where the
    /// current value still matches what the run left it as — an intervening
    /// user edit to that same field (a direct re-flag, an explicit
    /// confirm/reject) changes the value or clears the AI-unconfirmed marker
    /// in a way this check can't distinguish from "untouched", so on any
    /// mismatch it leaves the field alone rather than guess. Fields/keywords
    /// the run never touched (caption, colorLabel, rating, other keywords)
    /// are never referenced here at all, so an unrelated edit made between
    /// the run and the undo always survives. A field is still reverted even
    /// after `commitAutopilotProposals` confirmed it (matching value, marker
    /// just cleared) — undo-run intentionally reaches back through a commit,
    /// per `undoAutopilotRun`'s "including any since committed" contract.
    /// The one case that needs a real sidecar fix-up is exactly that
    /// since-committed case: the asset's confirmed projection changes as a
    /// result of the revert, and leaving the sidecar alone would strand a
    /// stale confirmed value on disk underneath the reverted catalog state.
    private func revertAutopilotTentativeChange(_ change: AutopilotTentativeChange) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let beforeRevertMetadata: AssetMetadata
        do {
            beforeRevertMetadata = try catalog.repository.asset(id: change.assetID).metadata
        } catch CatalogError.notFound {
            return
        }

        try catalog.repository.updateMetadata(assetID: change.assetID) { metadata in
            for field in change.tentativeFields {
                switch field {
                case .flag:
                    guard metadata.flag == change.after.flag else { continue }
                    metadata.flag = change.before.flag
                case .rating:
                    guard metadata.rating == change.after.rating else { continue }
                    metadata.rating = change.before.rating
                case .caption, .keyword:
                    continue
                }
                if change.before.aiUnconfirmedFields.contains(field) {
                    metadata.aiUnconfirmedFields.insert(field)
                } else {
                    metadata.aiUnconfirmedFields.remove(field)
                }
            }
            for keyword in change.tentativeKeywords {
                guard metadata.keywords.contains(keyword) else { continue }
                metadata.keywords.removeAll { $0 == keyword }
                if change.before.aiUnconfirmedKeywords.contains(keyword) {
                    metadata.aiUnconfirmedKeywords.insert(keyword)
                } else {
                    metadata.aiUnconfirmedKeywords.remove(keyword)
                }
            }
        }

        let revertedAsset = try catalog.repository.asset(id: change.assetID)
        if beforeRevertMetadata.confirmedProjection != revertedAsset.metadata.confirmedProjection {
            try syncMetadataSidecar(for: revertedAsset)
            try refreshCatalogSidebarCounts()
        }
        try refreshInMemoryAsset(change.assetID)
    }

    private func autopilotScopeAssets(_ scope: AutopilotScope, repository: CatalogRepository) throws -> [Asset] {
        switch scope {
        case .visible:
            return assets
        case .assetIDs(let ids):
            guard !ids.isEmpty else { return [] }
            return try repository.assets(ids: ids, limit: ids.count)
        }
    }

    private func autopilotStackCount(for scopeAssets: [Asset]) -> Int {
        stackBuilder()
            .stacks(from: scopeAssets, visualSimilarityVectorsByAssetID: [:])
            .filter { $0.assetIDs.count > 1 }
            .count
    }

    /// Multi-frame near-duplicate stacks detected across the visible scope, for
    /// the Agents panel's honest projection.
    public var autopilotVisibleStackCount: Int {
        autopilotStackCount(for: assets)
    }

    private static func autopilotKeywordCandidates(
        from signals: [EvaluationSignal],
        existingKeywords: [String]
    ) -> [String] {
        var seen = Set(existingKeywords.map(keywordKey).filter { !$0.isEmpty })
        var candidates: [String] = []
        for signal in signals {
            for label in objectLabels(from: signal) {
                let keyword = cleanedKeyword(label)
                let key = keywordKey(keyword)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                candidates.append(keyword)
            }
        }
        return candidates
    }

    /// Rebuilds provisional-proposal state after a session restore so KEEP/CUT
    /// badges and the auto-cull banner survive relaunch. Reads only persisted
    /// `pending` proposals; never writes.
    private func reconstructAutopilotStateAfterLoad() throws {
        guard let catalog else { return }
        let pending = try catalog.repository.autopilotProposals(status: .pending)
        pendingAutopilotProposals = pending
        guard let latestRunID = pending.max(by: { $0.createdAt < $1.createdAt })?.runID else {
            return
        }
        let latestRunProposals = pending.filter { $0.runID == latestRunID }
        let keeperCount = latestRunProposals.filter { $0.kind == .pick }.count
        autopilotRunSummary = AutopilotRunSummary(
            runID: latestRunID,
            keeperCount: keeperCount,
            rejectCount: latestRunProposals.filter { $0.kind == .reject }.count,
            keywordCount: latestRunProposals.filter { $0.kind == .keyword }.count,
            stackCount: keeperCount
        )
    }

    public func requestCurrentScopeAssetEvaluations(providers: [String] = AppModel.defaultEvaluationProviderNames) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard try currentLibraryAssetCount(repository: catalog.repository) > 0 else {
            throw TeststripError.invalidState("no current scope assets")
        }
        let evaluableAssetIDs = try currentScopeCachedPreviewAssetIDs(repository: catalog.repository)
        guard !evaluableAssetIDs.isEmpty else {
            throw TeststripError.invalidState("no current scope assets with cached previews")
        }
        let batchAssetIDs = Array(evaluableAssetIDs.prefix(Self.currentScopeEvaluationBatchSize))
        for assetID in batchAssetIDs {
            for provider in providers {
                try requestEvaluation(assetID: assetID, provider: provider)
            }
        }
        let remainingAssetCount = evaluableAssetIDs.count - batchAssetIDs.count
        if remainingAssetCount > 0 {
            let remainingLabel = remainingAssetCount == 1 ? "cached photo remains" : "cached photos remain"
            statusMessage = "Queued local reads for \(Self.photoCountDescription(batchAssetIDs.count)); \(remainingAssetCount) \(remainingLabel)"
        }
    }

    public func requestPeopleFaceScan() throws {
        try requestCurrentScopeAssetEvaluations(providers: ["apple-vision"])
    }

    public func requestLatestImportAssetEvaluations(providers: [String] = AppModel.defaultEvaluationProviderNames) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetIDs = try latestImportOutputAssetIDs(repository: catalog.repository)
        guard !assetIDs.isEmpty else {
            throw TeststripError.invalidState("no latest import assets")
        }
        let evaluableAssetIDs = assetIDs.filter { hasCachedPreview(for: $0) }
        guard !evaluableAssetIDs.isEmpty else {
            throw TeststripError.invalidState("no latest import assets with cached previews")
        }
        for assetID in evaluableAssetIDs {
            for provider in providers {
                try requestEvaluation(assetID: assetID, provider: provider)
            }
        }
    }

    // Seeds the provisional read pass for a finished import. Bounded by the
    // import's asset list; each queued pass is a normal cancellable
    // .recognition work item, so Activity shows and controls all of it.
    private func scheduleImportAutoEvaluationIfEnabled(result: LibraryImportResult) {
        guard importAutoEvaluationEnabled, workerSupervisor != nil else { return }
        let importedAssetIDs = result.importedAssets.map(\.id)
        guard !importedAssetIDs.isEmpty else { return }
        // Union, not assignment: a prior import's assets may still be awaiting
        // their preview-completion evaluations while this import finishes.
        // requestEvaluation dedups against the live queue, so this cannot
        // double-enqueue.
        pendingImportEvaluationAssetIDs.formUnion(importedAssetIDs)
        if autopilotArmedForActiveImport {
            armedAutopilotImportAssetIDs = (armedAutopilotImportAssetIDs ?? []).union(importedAssetIDs)
        }
        enqueueImportEvaluationsForCachedPreviews(assetIDs: importedAssetIDs)
        runImportAutopilotIfArmedAndResolved()
    }

    // Runs autopilot over the armed import set once every armed asset's
    // evaluations have resolved (nothing queued waiting on a preview, nothing
    // in-flight in the worker). Runs at most once per armed import, then disarms.
    private func runImportAutopilotIfArmedAndResolved() {
        guard let armed = armedAutopilotImportAssetIDs, !armed.isEmpty else { return }
        if armed.contains(where: { pendingImportEvaluationAssetIDs.contains($0) }) { return }
        let inFlightEvaluationAssetIDs = Set(evaluationAssetIDsByItemID.values)
        if armed.contains(where: { inFlightEvaluationAssetIDs.contains($0) }) { return }
        armedAutopilotImportAssetIDs = nil
        autopilotArmedForActiveImport = false
        runArmedImportAutopilot(importedAssetIDs: Array(armed))
    }

    private func runArmedImportAutopilot(importedAssetIDs: [AssetID]) {
        // No global-preference guard here: reaching this point means the
        // import was explicitly armed (see runImportAutopilotIfArmedAndResolved),
        // an explicit per-import opt-in that must run regardless of the
        // standing `autopilotEnabled` default. That default only seeds the
        // sheet toggle's initial checked state, not a second gate.
        do {
            _ = try runAutopilot(scope: .assetIDs(importedAssetIDs))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enqueueImportEvaluationsForCachedPreviews(assetIDs: [AssetID]) {
        guard workerSupervisor != nil else { return }
        for assetID in assetIDs where pendingImportEvaluationAssetIDs.contains(assetID) {
            guard hasCachedPreview(for: assetID) else { continue }
            pendingImportEvaluationAssetIDs.remove(assetID)
            for provider in AppModel.defaultEvaluationProviderNames {
                do {
                    try requestEvaluation(assetID: assetID, provider: provider)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    public func requestCompareAssetEvaluations(providers: [String] = AppModel.defaultEvaluationProviderNames) throws {
        let compareAssets = compareAssets()
        guard !compareAssets.isEmpty else {
            throw TeststripError.invalidState("no compare assets")
        }
        let evaluableAssets = compareAssets.filter { hasCachedPreview(for: $0.id) }
        guard !evaluableAssets.isEmpty else {
            throw TeststripError.invalidState("no compare assets with cached previews")
        }
        for asset in evaluableAssets {
            for provider in providers {
                try requestEvaluation(assetID: asset.id, provider: provider)
            }
        }
    }

    private func syncBackgroundWorkQueueFromSupervisor() {
        guard workerSupervisor != nil else { return }
        publishBackgroundWorkState()
    }

    // Always-current queue for model logic. The published backgroundWorkQueue may
    // lag behind by up to one coalescing interval while previews drain, so dedup
    // checks and completion bookkeeping must never read it.
    private var currentBackgroundWorkQueue: BackgroundWorkQueue {
        workerSupervisor?.queue ?? backgroundWorkQueue
    }

    private func publishBackgroundWorkState() {
        guard let backgroundWorkPublicationInterval else {
            flushBackgroundWorkPublication()
            return
        }
        guard backgroundWorkPublicationTimer == nil else { return }
        let flush = BackgroundWorkPublicationFlush { [weak self] in
            self?.backgroundWorkPublicationTimer = nil
            self?.flushBackgroundWorkPublication()
        }
        backgroundWorkPublicationTimer = backgroundWorkPublicationScheduler.schedule(
            after: backgroundWorkPublicationInterval
        ) {
            flush()
        }
    }

    private func flushBackgroundWorkPublication() {
        clearGridPreviewCaches()
        backgroundWorkQueue = currentBackgroundWorkQueue
        previewCacheGenerationsByAssetID = currentPreviewCacheGenerationsByAssetID
        if pendingLatestImportPreviewStatusRefresh {
            pendingLatestImportPreviewStatusRefresh = false
            refreshLatestImportPreviewStatus()
        }
        if pendingPreviewGenerationQueueStatesRefresh {
            pendingPreviewGenerationQueueStatesRefresh = false
            try? refreshPreviewGenerationQueueStates()
        }
    }

    private func clearGridPreviewCaches() {
        gridPreviewURLCacheByAssetID.removeAll(keepingCapacity: true)
        gridPreviewStatusCacheByAssetID.removeAll(keepingCapacity: true)
    }

    // Defers the repository-backed queue-state refresh to the coalesced publication
    // flush; the preview drain calls this once per completed preview.
    private func schedulePreviewGenerationQueueStatesRefresh() {
        pendingPreviewGenerationQueueStatesRefresh = true
        publishBackgroundWorkState()
    }

    private static func failedPreviewGenerationItemIDs(in queue: BackgroundWorkQueue?) -> Set<WorkSessionID> {
        Set(
            queue?.items.compactMap { item in
                guard item.kind == .previewGeneration, item.status == .failed else { return nil }
                return item.id
            } ?? []
        )
    }

    private static func metadataSyncWorkChanged(
        from previousQueue: BackgroundWorkQueue?,
        to queue: BackgroundWorkQueue
    ) -> Bool {
        metadataSyncWorkStatuses(in: previousQueue) != metadataSyncWorkStatuses(in: queue)
    }

    private static func metadataSyncWorkStatuses(in queue: BackgroundWorkQueue?) -> [WorkSessionID: WorkSessionStatus] {
        Dictionary(
            uniqueKeysWithValues: queue?.items.compactMap { item in
                guard item.kind == .xmpSync else { return nil }
                return (item.id, item.status)
            } ?? []
        )
    }

    private static func previewGenerationWorkChanged(
        from previousQueue: BackgroundWorkQueue?,
        to queue: BackgroundWorkQueue
    ) -> Bool {
        previewGenerationWorkStatuses(in: previousQueue) != previewGenerationWorkStatuses(in: queue)
    }

    private static func previewGenerationWorkStatuses(in queue: BackgroundWorkQueue?) -> [WorkSessionID: WorkSessionStatus] {
        Dictionary(
            uniqueKeysWithValues: queue?.items.compactMap { item in
                guard item.kind == .previewGeneration else { return nil }
                return (item.id, item.status)
            } ?? []
        )
    }

    private func enqueueWorkerImport(
        source: URL,
        destinationRoot: URL?,
        secondCopyDestination: URL? = nil,
        command: WorkerCommand
    ) {
        guard let workerSupervisor else { return }
        let itemID = WorkSessionID(rawValue: "import-\(UUID().uuidString)")
        let didAccessSource: Bool
        let didAccessDestination: Bool
        let didAccessSecondCopy: Bool
        do {
            didAccessSource = try startAccessingImportResource(source)
            do {
                if let destinationRoot {
                    didAccessDestination = try startAccessingImportResource(destinationRoot)
                } else {
                    didAccessDestination = false
                }
            } catch {
                stopAccessingImportResource(source, didAccess: didAccessSource)
                throw error
            }
            do {
                didAccessSecondCopy = try secondCopyDestination.map(startAccessingImportResource) ?? false
            } catch {
                if let destinationRoot {
                    stopAccessingImportResource(destinationRoot, didAccess: didAccessDestination)
                }
                stopAccessingImportResource(source, didAccess: didAccessSource)
                throw error
            }
        } catch {
            failImportBeforeStart(folderURL: source, destinationRoot: destinationRoot, reason: error.localizedDescription)
            return
        }
        let context = WorkerImportContext(
            source: source,
            destinationRoot: destinationRoot,
            secondCopyDestination: secondCopyDestination,
            didAccessSource: didAccessSource,
            didAccessDestination: didAccessDestination,
            didAccessSecondCopy: didAccessSecondCopy
        )
        let item = BackgroundWorkItem(
            id: itemID,
            kind: .ingest,
            title: "Import photos",
            detail: "Importing from \(importSourceDescription(folderURL: source, destinationRoot: destinationRoot))",
            completedUnitCount: 0,
            totalUnitCount: nil
        )
        workerImportContextsByItemID[itemID] = context
        do {
            try workerSupervisor.enqueue(item, command: command)
            recordRecentActivity(AppWorkActivity(workItem: workerSupervisor.queue.item(id: itemID) ?? item))
            syncBackgroundWorkQueueFromSupervisor()
        } catch {
            workerImportContextsByItemID[itemID] = nil
            stopAccessingWorkerImportResources(context)
            statusMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func handleWorkerCommandCompleted(_ event: WorkerEvent) {
        switch event {
        case .completed(let itemID, _):
            let completedPreview = invalidatePreviewCacheIfNeeded(itemID: itemID)
            invalidateEvaluationSignalsIfNeeded(itemID: itemID)
            refreshLoadedAssetMetadataIfNeeded(itemID: itemID)
            refreshLoadedAssetAvailabilityIfNeeded(itemID: itemID)
            if completedPreview {
                do {
                    try enqueuePendingPreviewGeneration()
                    workerSupervisor?.pruneCompletedItems(kind: .previewGeneration, keepingLast: 1)
                    syncBackgroundWorkQueueFromSupervisor()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            if completedPreview,
               let itemID,
               let previewAssetID = Self.previewAssetID(from: itemID) {
                enqueueImportEvaluationsForCachedPreviews(assetIDs: [previewAssetID])
            }
            runImportAutopilotIfArmedAndResolved()
            if itemID == Self.geocodeWorkItemID {
                do {
                    try enqueuePendingGeocoding()
                    workerSupervisor?.pruneCompletedItems(kind: .geocoding, keepingLast: 1)
                    syncBackgroundWorkQueueFromSupervisor()
                    if selectedView == .map {
                        try refreshPlaceData()
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            if itemID == Self.coordinateBackfillWorkItemID {
                do {
                    try loadCatalogPage(preferredSelection: selectedAssetID)
                    try beginCoordinateBackfill()
                    try enqueuePendingGeocoding()
                    workerSupervisor?.pruneCompletedItems(kind: .locationBackfill, keepingLast: 1)
                    syncBackgroundWorkQueueFromSupervisor()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .completedImport(
            let itemID,
            _,
            let importedAssetIDs,
            let newAssetCount,
            let existingAssetCount,
            let skippedSourceFileCount,
            let skippedSourceFiles
        ):
            handleWorkerImportCompleted(
                itemID: itemID,
                importedAssetIDs: importedAssetIDs,
                newAssetCount: newAssetCount,
                existingAssetCount: existingAssetCount,
                skippedSourceFileCount: skippedSourceFileCount,
                skippedSourceFiles: skippedSourceFiles
            )
        case .accepted, .progress, .failed:
            return
        }
    }

    private func handleWorkerCommandProgress(_ event: WorkerEvent) {
        guard case .progress(let itemID, _, _, _, let catalogedAssetIDs) = event,
              let itemID,
              var context = workerImportContextsByItemID[itemID],
              context.displayedCatalogedAssetID == nil,
              let firstCatalogedAssetID = catalogedAssetIDs.first else {
            return
        }
        do {
            try loadCatalogPage(preferredSelection: firstCatalogedAssetID)
            context.displayedCatalogedAssetID = firstCatalogedAssetID
            workerImportContextsByItemID[itemID] = context
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLoadedAssetAvailabilityIfNeeded(itemID: WorkSessionID?) {
        guard let itemID,
              currentBackgroundWorkQueue.item(id: itemID)?.kind == .sourceScan,
              let assetIDs = availabilityAssetIDsByItemID.removeValue(forKey: itemID),
              let catalog else {
            return
        }
        do {
            for assetID in assetIDs {
                let updatedAsset = try catalog.repository.asset(id: assetID)
                if let index = assets.firstIndex(where: { $0.id == assetID }) {
                    assets[index] = updatedAsset
                }
            }
            try refreshSourceAvailabilitySummaries()
            try enqueuePendingPreviewGeneration()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLoadedAssetAvailabilityForPreviewFailures(_ itemIDs: Set<WorkSessionID>) {
        let assetIDs = itemIDs.compactMap(Self.previewAssetID)
        guard !assetIDs.isEmpty, catalog != nil else { return }
        do {
            try reload()
            try refreshSourceAvailabilitySummaries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLoadedAssetMetadataIfNeeded(itemID: WorkSessionID?) {
        guard let itemID,
              currentBackgroundWorkQueue.item(id: itemID)?.kind == .xmpSync,
              let assetID = metadataSyncAssetIDsByItemID.removeValue(forKey: itemID),
              let catalog else {
            return
        }
        do {
            let updatedAsset = try catalog.repository.asset(id: assetID)
            if let index = assets.firstIndex(where: { $0.id == assetID }) {
                assets[index] = updatedAsset
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func invalidatePreviewCacheIfNeeded(itemID: WorkSessionID?) -> Bool {
        guard let itemID,
              currentBackgroundWorkQueue.item(id: itemID)?.kind == .previewGeneration,
              let assetID = Self.previewAssetID(from: itemID) else {
            return false
        }
        currentPreviewCacheGenerationsByAssetID[assetID, default: 0] += 1
        publishBackgroundWorkState()
        return true
    }

    private func invalidateEvaluationSignalsIfNeeded(itemID: WorkSessionID?) {
        guard let itemID,
              currentBackgroundWorkQueue.item(id: itemID)?.kind == .recognition,
              let assetID = evaluationAssetIDsByItemID.removeValue(forKey: itemID) else {
            return
        }
        let provider = evaluationProvidersByItemID.removeValue(forKey: itemID)
        if let provider {
            do {
                try catalog?.repository.clearEvaluationFailure(assetID: assetID, provider: provider)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        promoteEvaluationResults(for: assetID)
        evaluationSignalGenerationsByAssetID[assetID, default: 0] += 1
        refreshCatalogEvaluationKindSummaries()
        if providerFailuresFilter {
            do {
                try reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Auto-applies the machine-label-provenance promoters for one
    /// just-evaluated asset, then refreshes the in-memory `assets` cache
    /// (and, transitively, `selectedAsset`, which is derived from it) and
    /// face-suggestion state so the promoted labels/faces are visible right
    /// away — the fetch-and-splice half mirrors
    /// `refreshLoadedAssetMetadataIfNeeded`'s pattern after other
    /// catalog-mutating background work completes; the suggestion refresh
    /// mirrors what runs after every other face-table mutation (confirm/
    /// dismiss a face suggestion, dismiss face review). Bounded to the one
    /// asset that just finished evaluating — never scans the whole catalog.
    private func promoteEvaluationResults(for assetID: AssetID) {
        guard catalog != nil else { return }
        do {
            try promoteMetadataLabels(for: assetID)
            try promoteFaceMatches(for: assetID)
            try refreshInMemoryAsset(assetID)
            refreshPeopleFaceSuggestions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func previewAssetID(from itemID: WorkSessionID) -> AssetID? {
        let rawValue = itemID.rawValue
        guard rawValue.hasPrefix("preview-") else {
            return nil
        }
        let prefixedAssetID = rawValue.dropFirst("preview-".count)
        for level in PreviewLevel.allCases {
            let suffix = "-\(level.rawValue)"
            if prefixedAssetID.hasSuffix(suffix) {
                return AssetID(rawValue: String(prefixedAssetID.dropLast(suffix.count)))
            }
        }
        return nil
    }

    private static func previewWorkItemID(assetID: AssetID, level: PreviewLevel) -> WorkSessionID {
        WorkSessionID(rawValue: "preview-\(assetID.rawValue)-\(level.rawValue)")
    }

    private static func previewGenerationWorkItemIDs(in queue: BackgroundWorkQueue) -> Set<WorkSessionID> {
        Set(queue.items.compactMap { item in
            guard item.kind == .previewGeneration,
                  Self.isActiveBackgroundWorkStatus(item.status) else { return nil }
            return item.id
        })
    }

    private static func activePreviewGenerationWorkCount(in queue: BackgroundWorkQueue) -> Int {
        queue.items.filter { item in
            item.kind == .previewGeneration && Self.isActiveBackgroundWorkStatus(item.status)
        }.count
    }

    private static func diagnosticsBackgroundWork(_ queue: BackgroundWorkQueue) -> AppDiagnosticsBackgroundWork {
        AppDiagnosticsBackgroundWork(
            maxRunningCount: queue.maxRunningCount,
            kindRunningLimits: sortedKindCounts(queue.kindRunningLimits),
            statusCounts: sortedStatusCounts(queue.items),
            kindCounts: sortedKindCounts(queue.items.reduce(into: [:]) { counts, item in
                counts[item.kind, default: 0] += 1
            })
        )
    }

    private static func sortedStatusCounts(_ items: [BackgroundWorkItem]) -> [AppDiagnosticsWorkStatusCount] {
        let counts = items.reduce(into: [WorkSessionStatus: Int]()) { counts, item in
            counts[item.status, default: 0] += 1
        }
        return counts
            .map { AppDiagnosticsWorkStatusCount(status: $0.key, count: $0.value) }
            .sorted { statusSortIndex($0.status) < statusSortIndex($1.status) }
    }

    private static func sortedKindCounts(_ counts: [WorkSessionKind: Int]) -> [AppDiagnosticsWorkKindCount] {
        counts
            .map { AppDiagnosticsWorkKindCount(kind: $0.key, count: $0.value) }
            .sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    private static func statusSortIndex(_ status: WorkSessionStatus) -> Int {
        switch status {
        case .queued:
            return 0
        case .running:
            return 1
        case .paused:
            return 2
        case .completed:
            return 3
        case .failed:
            return 4
        case .cancelled:
            return 5
        }
    }

    private static func sourceAvailabilityCounts(_ summaries: [CatalogSourceAvailabilitySummary]) -> [AppDiagnosticsSourceAvailabilityCount] {
        var counts: [SourceAvailability: Int] = [:]
        for summary in summaries {
            counts[summary.availability, default: 0] += summary.assetCount
        }
        return counts
            .map { AppDiagnosticsSourceAvailabilityCount(availability: $0.key, count: $0.value) }
            .sorted { $0.availability.rawValue < $1.availability.rawValue }
    }

    private func diagnosticsRecentFailures(limit: Int = 5) -> [AppDiagnosticsWorkFailure] {
        var seenIDs: Set<String> = []
        var failures: [AppDiagnosticsWorkFailure] = []

        for item in backgroundWorkQueue.items where item.status == .failed {
            let failure = AppDiagnosticsWorkFailure(
                id: item.id.rawValue,
                kind: item.kind,
                title: item.title,
                detail: item.detail,
                failureCount: 0
            )
            if seenIDs.insert(failure.id).inserted {
                failures.append(failure)
            }
        }

        for activity in recentWork where activity.status == .failed {
            let failure = AppDiagnosticsWorkFailure(
                id: activity.id,
                kind: activity.kind,
                title: activity.title,
                detail: activity.detail,
                failureCount: activity.failureCount
            )
            if seenIDs.insert(failure.id).inserted {
                failures.append(failure)
            }
        }

        return Array(failures.prefix(limit))
    }

    private static func isActiveBackgroundWorkStatus(_ status: WorkSessionStatus) -> Bool {
        [.queued, .running, .paused].contains(status)
    }

    private func handleWorkerImportCompleted(
        itemID: WorkSessionID?,
        importedAssetIDs: [AssetID],
        newAssetCount: Int,
        existingAssetCount: Int,
        skippedSourceFileCount: Int,
        skippedSourceFiles: [LibrarySkippedSourceFile]
    ) {
        guard let itemID,
              let context = workerImportContextsByItemID.removeValue(forKey: itemID) else {
            return
        }
        defer {
            stopAccessingWorkerImportResources(context)
        }
        guard let catalog else {
            errorMessage = TeststripError.invalidState("app model has no catalog").localizedDescription
            return
        }
        do {
            try loadCatalogPage(preferredSelection: importedAssetIDs.first)
            try enqueuePendingPreviewGeneration()
            try enqueuePendingGeocoding()
            let importedAssets = try catalog.repository.assets(ids: importedAssetIDs, limit: importedAssetIDs.count)
            let result = LibraryImportResult(
                importedAssets: importedAssets,
                previewFailures: [],
                skippedSourceFiles: skippedSourceFiles,
                skippedSourceFileCount: skippedSourceFileCount,
                newAssetCount: newAssetCount,
                existingAssetCount: existingAssetCount
            )
            updateImportStatus(with: result)
            let outputSetIDs = recordCompletedImportActivity(
                id: itemID.rawValue,
                folderURL: context.source,
                destinationRoot: context.destinationRoot,
                result: result
            )
            scheduleImportAutoEvaluationIfEnabled(result: result)
            presentCompletedImportResultIfNeeded(result: result, outputSetIDs: outputSetIDs)
        } catch {
            statusMessage = nil
            errorMessage = error.localizedDescription
            failImportActivity(id: itemID.rawValue, folderURL: context.source, destinationRoot: context.destinationRoot, error: error)
        }
    }

    private func releaseInactiveWorkerImportContexts(in queue: BackgroundWorkQueue) {
        for itemID in Array(workerImportContextsByItemID.keys) {
            guard let item = queue.item(id: itemID), [.cancelled, .failed].contains(item.status) else {
                continue
            }
            if let context = workerImportContextsByItemID.removeValue(forKey: itemID) {
                stopAccessingWorkerImportResources(context)
                if item.status == .cancelled {
                    cancelImportActivity(
                        id: itemID.rawValue,
                        folderURL: context.source,
                        destinationRoot: context.destinationRoot
                    )
                } else if item.status == .failed {
                    failImportActivity(
                        id: itemID.rawValue,
                        folderURL: context.source,
                        destinationRoot: context.destinationRoot,
                        error: TeststripError.io(item.detail)
                    )
                }
            }
            if item.status == .failed {
                statusMessage = nil
                errorMessage = item.detail
            }
        }
    }

    private func releaseInactiveEvaluationContexts(in queue: BackgroundWorkQueue) {
        for itemID in Array(evaluationAssetIDsByItemID.keys) {
            guard let item = queue.item(id: itemID), [.cancelled, .failed].contains(item.status) else {
                continue
            }
            let assetID = evaluationAssetIDsByItemID.removeValue(forKey: itemID)
            let provider = evaluationProvidersByItemID.removeValue(forKey: itemID)
            if item.status == .failed,
               let assetID,
               let provider,
               let catalog {
                do {
                    try catalog.repository.recordEvaluationFailure(assetID: assetID, provider: provider, message: item.detail)
                    try refreshCatalogSidebarCounts()
                    if providerFailuresFilter {
                        try reload()
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func releaseInactiveMetadataSyncContexts(in queue: BackgroundWorkQueue) {
        for itemID in metadataSyncAssetIDsByItemID.keys {
            guard let item = queue.item(id: itemID), [.cancelled, .failed].contains(item.status) else {
                continue
            }
            metadataSyncAssetIDsByItemID[itemID] = nil
        }
    }

    private func releaseInactiveAvailabilityContexts(in queue: BackgroundWorkQueue) {
        for itemID in availabilityAssetIDsByItemID.keys {
            guard let item = queue.item(id: itemID), [.cancelled, .failed].contains(item.status) else {
                continue
            }
            availabilityAssetIDsByItemID[itemID] = nil
        }
    }

    private func cancelWorkerImportContexts() {
        for context in workerImportContextsByItemID.values {
            stopAccessingWorkerImportResources(context)
        }
        workerImportContextsByItemID.removeAll()
    }

    private func startAccessingImportResource(_ url: URL) throws -> Bool {
        let didAccess = resourceAccess.startAccessing(url)
        if resourceAccess.requiresSuccessfulAccess && !didAccess {
            throw TeststripError.invalidState("Import permission was not granted for \(url.lastPathComponent)")
        }
        return didAccess
    }

    private func stopAccessingImportResource(_ url: URL, didAccess: Bool) {
        guard didAccess else { return }
        resourceAccess.stopAccessing(url)
    }

    private func stopAccessingWorkerImportResources(_ context: WorkerImportContext) {
        stopAccessingImportResource(context.source, didAccess: context.didAccessSource)
        if let destinationRoot = context.destinationRoot {
            stopAccessingImportResource(destinationRoot, didAccess: context.didAccessDestination)
        }
        if let secondCopyDestination = context.secondCopyDestination {
            stopAccessingImportResource(secondCopyDestination, didAccess: context.didAccessSecondCopy)
        }
    }

    private var visibleActiveBackgroundWorkItems: [BackgroundWorkItem] {
        backgroundWorkQueue.items.compactMap { item in
            guard [.running, .paused, .queued].contains(item.status) else { return nil }
            return userFacingBackgroundWorkItem(item)
        }
    }

    private var visibleInactiveBackgroundWorkItem: BackgroundWorkItem? {
        backgroundWorkQueue.items.last { isVisibleInactiveBackgroundWork($0) }
    }

    private var persistedWorkActivityIDs: Set<String> {
        Set((recentWork + starredWork).map(\.id))
    }

    private var activeBackgroundImportItem: BackgroundWorkItem? {
        let importItems = workerImportContextsByItemID.keys.compactMap { backgroundWorkQueue.item(id: $0) }
        let item = importItems.first { $0.kind == .ingest && $0.status == .running } ??
            importItems.first { $0.kind == .ingest && $0.status == .paused } ??
            importItems.first { $0.kind == .ingest && $0.status == .queued }
        return item.map(userFacingWorkerImportItem)
    }

    private func userFacingWorkerImportItem(_ item: BackgroundWorkItem) -> BackgroundWorkItem {
        userFacingBackgroundWorkItem(item)
    }

    private func userFacingBackgroundWorkItem(_ item: BackgroundWorkItem) -> BackgroundWorkItem {
        guard item.status == .running,
              workerSupervisor?.isCommandDispatched(for: item.id) == false else {
            return item
        }
        var waitingItem = item
        waitingItem.status = .queued
        return waitingItem
    }

    private func recordPersistedActiveBackgroundWorkActivities(in queue: BackgroundWorkQueue) {
        let persistedIDs = persistedWorkActivityIDs
        for item in queue.items where persistedIDs.contains(item.id.rawValue) && [.queued, .running, .paused].contains(item.status) {
            let activity = AppWorkActivity(workItem: item)
            // Queue changes fire per preview transition; re-recording an unchanged
            // activity would republish recentWork, rebuild the sidebar, and rewrite
            // the work session for every transition of an active import.
            if recentWork.first(where: { $0.id == activity.id }) == activity {
                continue
            }
            recordRecentActivity(activity)
        }
    }

    private func isVisibleInactiveBackgroundWork(_ item: BackgroundWorkItem) -> Bool {
        guard [.cancelled, .failed, .completed].contains(item.status) else {
            return false
        }
        return !isSelectionMetadataSyncCheck(item)
    }

    public func reload() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        isAutopilotReviewActive = false
        try refreshProposedAssets()
        try refreshWorkHistorySearchResults(repository: catalog.repository)
        // reload() is the single funnel after bulk mutations (trash, move
        // back, relocation, deletes), so every count surface refreshes here
        // together — otherwise the sidebar keeps stale review-queue/folder
        // counts while the HUD and catalog already tell the new story
        // (persona-7's "three surfaces, three stories").
        try refreshCatalogSidebarCounts()
        refreshCatalogFolders()
        if let explicitAssetIDs = selectedExplicitAssetIDs {
            let loadedAssets = try catalog.repository.assets(ids: explicitAssetIDs, flag: flagFilter, limit: explicitAssetIDs.count)
            replaceAssets(loadedAssets)
            totalAssetCount = try catalog.repository.assetCount(ids: explicitAssetIDs, flag: flagFilter)
            pruneBatchSelection(retaining: Set(explicitAssetIDs))
            if selectedView == .map {
                try refreshPlaceData()
            }
            return
        }
        let loadedAssets: [Asset]
        let count: Int
        if let query = currentLibraryQuery() {
            loadedAssets = try catalog.repository.allAssets(matching: query)
            count = try catalog.repository.assetCount(matching: query)
        } else {
            loadedAssets = try catalog.repository.allAssets()
            count = try catalog.repository.assetCount()
        }
        replaceAssets(loadedAssets)
        totalAssetCount = count
        try pruneBatchSelectionToCurrentLibraryQuery(repository: catalog.repository)
        // Map is a view of the current filtered result set (spec §4): keep its
        // geo aggregates in sync whenever the token/filter set that drives
        // `reload()` changes, not just on first appearance.
        if selectedView == .map {
            try refreshPlaceData()
        }
    }

    /// A person's PROPOSED photos — shown as a separate section below the
    /// confirmed grid — are computed only when the active query is exactly one
    /// `.person(name)` predicate; otherwise cleared. Proposed assets are kept in
    /// their own array (never `model.assets`) so tentative matches never reach
    /// Picks/export/destructive ops.
    private func refreshProposedAssets() throws {
        guard let catalog,
              selectedExplicitAssetIDs == nil,
              let query = currentLibraryQuery(),
              query.predicates.count == 1,
              case .person(let name) = query.predicates[0] else {
            proposedPhotos = []
            return
        }
        let proposed = try catalog.repository.proposedPersonFaces(personName: name)
        guard !proposed.isEmpty else {
            proposedPhotos = []
            return
        }
        var order: [AssetID] = []
        var byAsset: [AssetID: [ProposedPersonFace]] = [:]
        for face in proposed {
            if byAsset[face.assetID] == nil { order.append(face.assetID) }
            byAsset[face.assetID, default: []].append(face)
        }
        let assets = try catalog.repository.assets(ids: order, flag: nil, limit: order.count)
        let assetByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        proposedPhotos = order.compactMap { id in
            guard let asset = assetByID[id] else { return nil }
            return ProposedPersonPhoto(asset: asset, faces: byAsset[id] ?? [])
        }
    }

    private func refreshWorkHistorySearchResults(repository: CatalogRepository) throws {
        let previousResults = workHistorySearchResults
        let residualText = LibrarySearchIntent.parse(librarySearchText).residualText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let residualText, !residualText.isEmpty {
            workHistorySearchResults = try repository.workSessions(matching: residualText, limit: 5)
                .map(AppWorkActivity.init)
        } else {
            workHistorySearchResults = []
        }
        // The Collections group's Recent Work rows show the matched sessions
        // while a query is active, so a result change re-renders the sidebar.
        if workHistorySearchResults != previousResults {
            rebuildSidebarSections()
        }
    }

    public func applyLibraryFilters() throws {
        try reload()
    }

    public func setLibrarySortOption(_ option: LibrarySortOption) throws {
        guard librarySortOption != option else { return }
        librarySortOption = option
        try loadCatalogPage(preferredSelection: nil)
    }

    public func selectPeopleSignal(_ kind: EvaluationKind) throws {
        try applyEvaluationKindFilter(kind)
    }

    public func selectTimelineDay(_ day: CatalogTimelineDay, calendar: Calendar = .current) throws {
        try selectTimelineDateRange(startDate: day.startDate(calendar: calendar), endDate: day.endDate(calendar: calendar))
    }

    public func selectTimelineMonth(year: Int, month: Int, calendar: Calendar = .current) throws {
        let startDate = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        let endDate = startDate.flatMap { calendar.date(byAdding: .month, value: 1, to: $0) }
        try selectTimelineDateRange(startDate: startDate, endDate: endDate)
    }

    public func selectTimelineYear(_ year: Int, calendar: Calendar = .current) throws {
        let startDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        let endDate = startDate.flatMap { calendar.date(byAdding: .year, value: 1, to: $0) }
        try selectTimelineDateRange(startDate: startDate, endDate: endDate)
    }

    private func selectTimelineDateRange(startDate: Date?, endDate: Date?) throws {
        guard let startDate, let endDate else {
            throw TeststripError.invalidState("timeline selection has an invalid date")
        }
        selectedAssetSetID = nil
        captureDateStartFilter = startDate
        captureDateEndFilter = endDate
        selectedView = .timeline
        try reload()
    }

    public func selectPlaceBounds(_ bounds: GeoBounds) throws {
        selectedAssetSetID = nil
        geoBoundsFilter = bounds
        selectedView = .grid
        try reload()
    }

    /// Fills the place-data properties the map surface reads. Bounded: cluster
    /// counts come from SQL aggregation, top locations from a LIMIT-ed cache
    /// join, and coverage from a COUNT — no task loads all assets. Called on
    /// route entry and on map region change; nil bounds fits the whole world.
    func refreshPlaceData(
        bounds: GeoBounds? = nil,
        cellSize: Double = AppModel.defaultPlaceClusterCellSize
    ) throws {
        guard let catalog else { return }
        let query = currentLibraryQuery()
        catalogPlaceClusters = try catalog.repository.placeClusters(bounds: bounds, cellSize: cellSize, matching: query)
        catalogTopLocations = try catalog.repository.topLocations(limit: Self.topLocationsDisplayLimit, matching: query)
        geotaggedCoverage = try catalog.repository.geotaggedCoverage(matching: query)
    }

    static let defaultPlaceClusterCellSize = 10.0
    static let topLocationsDisplayLimit = 12

    private func applyEvaluationKindFilter(_ kind: EvaluationKind) throws {
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        evaluationKindFilter = kind
        selectedView = .grid
        try reload()
    }

    public func clearLibraryFilters() throws {
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        try reload()
    }

    public func removeActiveLibraryFilter(_ row: ActiveLibraryFilterRow) throws {
        var removed = false
        if let selectedAssetSet,
           row.title == selectedAssetSet.name || row.target == .assetSet(selectedAssetSet.id) {
            self.selectedAssetSetID = nil
            removed = true
        } else if removeSelectedDynamicSetRuleFilter(row) {
            removed = true
        } else {
            removed = removeDetachedLibraryFilter(row) || removed
            removed = removeExplicitLibraryFilter(row) || removed
            removed = removeLibrarySearchIntentFilter(row) || removed
        }
        guard removed else { return }
        try reload()
    }

    private func applyReviewQueue(_ queue: ReviewQueue) throws {
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        switch queue {
        case .picks:
            flagFilter = .pick
        case .potentialPicks:
            potentialPicksFilter = true
        case .rejects:
            flagFilter = .reject
        case .fiveStars:
            minimumRatingFilter = 5
        case .needsKeywords:
            needsKeywordsFilter = true
        case .needsEvaluation:
            needsEvaluationFilter = true
        case .facesFound:
            evaluationKindFilter = .faceCount
        case .ocrFound:
            evaluationKindFilter = .ocrText
        case .likelyIssues:
            likelyIssuesFilter = true
        case .providerFailures:
            providerFailuresFilter = true
        }
        selectedView = .grid
        try reload()
    }

    public func refreshSelectedAssetAvailability() throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        _ = try refreshAvailability(for: selectedAssetID)
        try refreshSourceAvailabilitySummaries()
    }

    public func refreshVisibleAssetAvailability() throws {
        guard catalog != nil else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        if workerSupervisor != nil {
            try requestAvailabilityRefresh(assetIDs: assets.map(\.id))
            return
        }
        let visibleAssetIDs = assets.map(\.id)
        for assetID in visibleAssetIDs {
            _ = try refreshAvailability(for: assetID)
        }
        try refreshSourceAvailabilitySummaries()
    }

    @discardableResult
    public func reconnectSourceRoot(from oldRoot: URL, to newRoot: URL) throws -> SourceRootReconnectResult {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let preferredSelection = selectedAssetID
        let result = try catalog.repository.reconnectSourceRoot(from: oldRoot, to: newRoot)
        guard result.reconnectedAssetCount > 0 else {
            throw TeststripError.invalidState(Self.sourceReconnectFailureMessage(
                result: result,
                oldRoot: oldRoot,
                newRoot: newRoot
            ))
        }
        persistSecurityScopedBookmarkForSourceRoot(newRoot)
        try loadCatalogPage(preferredSelection: preferredSelection)
        catalogFolders = try catalog.repository.folders()
        sourceRoots = try catalog.repository.sourceRoots()
        sourceAvailabilitySummaries = try Self.sourceAvailabilitySummaries(repository: catalog.repository)
        rebuildSidebarSections()
        try enqueuePendingPreviewGeneration()
        let sourceLabel = result.reconnectedAssetCount == 1 ? "source" : "sources"
        statusMessage = "Reconnected \(result.reconnectedAssetCount) \(sourceLabel)"
        return result
    }

    private static func sourceReconnectFailureMessage(
        result: SourceRootReconnectResult,
        oldRoot: URL,
        newRoot: URL
    ) -> String {
        let oldRootName = sourceRootDisplayName(oldRoot)
        let newRootName = sourceRootDisplayName(newRoot)
        if result.scannedAssetCount == 0 {
            return "No catalog photos use \(oldRootName). Check the old source root."
        }
        if result.missingFileCount == result.scannedAssetCount {
            let photoLabel = result.scannedAssetCount == 1 ? "photo was" : "photos were"
            let fileLabel = result.scannedAssetCount == 1 ? "file was" : "files were"
            return "No files were reconnected from \(newRootName). \(result.scannedAssetCount) catalog \(photoLabel) found under \(oldRootName), but the matching \(fileLabel) missing under the new root."
        }
        if result.fingerprintMismatchCount == result.scannedAssetCount {
            let fileLabel = result.scannedAssetCount == 1 ? "file was" : "files were"
            let matchLabel = result.scannedAssetCount == 1 ? "it did" : "they did"
            return "No files were reconnected from \(newRootName). \(result.scannedAssetCount) \(fileLabel) found under the new root, but \(matchLabel) not match the catalog fingerprint."
        }
        return "No files were reconnected from \(newRootName). Check that the new root contains the same files from \(oldRootName)."
    }

    private static func sourceRootDisplayName(_ url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    private func requestAvailabilityRefresh(assetID: AssetID) throws {
        guard let workerSupervisor else {
            throw TeststripError.invalidState("worker supervisor is not configured")
        }
        if availabilityAssetIDsByItemID.contains(where: { $0.value.contains(assetID) }) {
            return
        }
        let itemID = WorkSessionID(rawValue: "source-\(UUID().uuidString)")
        let assetName = assets.first { $0.id == assetID }?.originalURL.lastPathComponent ?? assetID.rawValue
        let item = BackgroundWorkItem(
            id: itemID,
            kind: .sourceScan,
            title: "Refresh sources",
            detail: "Checking \(assetName)",
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        availabilityAssetIDsByItemID[itemID] = [assetID]
        do {
            try workerSupervisor.enqueue(item, command: .refreshAvailability(assetID: assetID))
        } catch {
            availabilityAssetIDsByItemID[itemID] = nil
            throw error
        }
        syncBackgroundWorkQueueFromSupervisor()
    }

    private func requestAvailabilityRefresh(assetIDs: [AssetID]) throws {
        guard let workerSupervisor else {
            throw TeststripError.invalidState("worker supervisor is not configured")
        }
        let activeAssetIDs = Set(availabilityAssetIDsByItemID.values.flatMap { $0 })
        let refreshAssetIDs = assetIDs.filter { !activeAssetIDs.contains($0) }
        guard !refreshAssetIDs.isEmpty else { return }

        for batch in sourceAvailabilityRefreshBatches(for: refreshAssetIDs) {
            let itemID = WorkSessionID(rawValue: "source-\(UUID().uuidString)")
            let item = BackgroundWorkItem(
                id: itemID,
                kind: .sourceScan,
                title: "Refresh sources",
                detail: "Checking \(Self.sourceCountDescription(batch.count))",
                completedUnitCount: 0,
                totalUnitCount: batch.count
            )
            availabilityAssetIDsByItemID[itemID] = batch
            do {
                try workerSupervisor.enqueue(item, command: .refreshAvailabilityBatch(assetIDs: batch))
            } catch {
                availabilityAssetIDsByItemID[itemID] = nil
                throw error
            }
        }
        syncBackgroundWorkQueueFromSupervisor()
    }

    private func sourceAvailabilityRefreshBatches(for assetIDs: [AssetID]) -> [[AssetID]] {
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        var sourceOrder: [String] = []
        var assetIDsBySource: [String: [AssetID]] = [:]

        for assetID in assetIDs {
            let sourceKey = assetsByID[assetID]?.volumeIdentifier ?? ""
            if assetIDsBySource[sourceKey] == nil {
                sourceOrder.append(sourceKey)
                assetIDsBySource[sourceKey] = []
            }
            assetIDsBySource[sourceKey]?.append(assetID)
        }

        return sourceOrder.flatMap { sourceKey -> [[AssetID]] in
            guard let sourceAssetIDs = assetIDsBySource[sourceKey] else { return [] }
            return stride(from: 0, to: sourceAssetIDs.count, by: Self.sourceAvailabilityBatchSize).map { start in
                let end = min(start + Self.sourceAvailabilityBatchSize, sourceAssetIDs.count)
                return Array(sourceAssetIDs[start..<end])
            }
        }
    }

    private static func sourceCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "source" : "sources")"
    }

    @discardableResult
    private func refreshAvailability(for assetID: AssetID) throws -> SourceAvailability {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let asset = try catalog.repository.asset(id: assetID)
        let availability = SourceAvailabilityProbe().availability(for: asset)
        try catalog.repository.updateAvailability(assetID: assetID, availability: availability)
        let updatedAsset = try catalog.repository.asset(id: assetID)
        if let index = assets.firstIndex(where: { $0.id == assetID }) {
            assets[index] = updatedAsset
        }
        return availability
    }

    private func replaceAssets(
        _ loadedAssets: [Asset],
        preferredSelection: AssetID? = nil
    ) {
        let previousSelection = selectedAssetID
        assets = loadedAssets
        if let preferredSelection, assets.contains(where: { $0.id == preferredSelection }) {
            selectedAssetID = preferredSelection
        } else if let previousSelection, assets.contains(where: { $0.id == previousSelection }) {
            selectedAssetID = previousSelection
        } else {
            selectedAssetID = assets.first?.id
        }
    }

    private func pruneBatchSelectionToCurrentLibraryQuery(repository: CatalogRepository) throws {
        guard !selectedBatchAssetIDs.isEmpty,
              let query = currentLibraryQuery() else {
            return
        }
        let matchingSelectedAssetIDs = try repository.assetIDs(
            ids: selectedBatchAssetIDsInCatalogOrder,
            matching: query
        )
        pruneBatchSelection(retaining: Set(matchingSelectedAssetIDs))
    }

    private func pruneBatchSelection(retaining retainedAssetIDs: Set<AssetID>) {
        guard !selectedBatchAssetIDs.isSubset(of: retainedAssetIDs) else {
            return
        }
        selectedBatchAssetIDs = selectedBatchAssetIDs.intersection(retainedAssetIDs)
        selectedBatchAssetIDOrder.removeAll { !selectedBatchAssetIDs.contains($0) }
        selectedBatchAssetSortKeys = selectedBatchAssetSortKeys.filter { selectedBatchAssetIDs.contains($0.key) }
    }

    private func loadCatalogPage(preferredSelection: AssetID?) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let contents = try Self.catalogContents(
            repository: catalog.repository,
            query: currentLibraryQuery(),
            sort: librarySortOption
        )
        replaceAssets(contents.assets, preferredSelection: preferredSelection)
        totalAssetCount = contents.totalAssetCount
    }

    private static func append(_ predicate: SetQuery.Predicate, to predicates: inout [SetQuery.Predicate]) {
        guard !predicates.contains(predicate) else { return }
        predicates.append(predicate)
    }

    private static func append(_ value: String, to values: inout [String]) {
        guard !values.contains(value) else { return }
        values.append(value)
    }

    private static func append(_ row: ActiveLibraryFilterRow, to rows: inout [ActiveLibraryFilterRow]) {
        guard !rows.contains(where: { $0.title == row.title }) else { return }
        rows.append(row)
    }

    private static func normalizedRuleText(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func activeLibraryFilterRow(for predicate: SetQuery.Predicate) -> ActiveLibraryFilterRow? {
        switch predicate {
        case .text(let text):
            ActiveLibraryFilterRow(title: "Search: \(text)")
        case .ratingAtLeast(let rating):
            ActiveLibraryFilterRow(title: "Rating >= \(rating)", target: sidebarTarget(for: predicate))
        case .flag(let flag):
            ActiveLibraryFilterRow(title: flag.rawValue.capitalized, target: sidebarTarget(for: predicate))
        case .colorLabel(let label):
            ActiveLibraryFilterRow(title: "\(label.rawValue.capitalized) Label")
        case .keyword(let keyword):
            ActiveLibraryFilterRow(title: "Keyword: \(keyword)")
        case .person(let name):
            ActiveLibraryFilterRow(title: "Person: \(name)")
        case .missingKeywords:
            ActiveLibraryFilterRow(title: "Needs Keywords", target: sidebarTarget(for: predicate))
        case .availability(let availability):
            ActiveLibraryFilterRow(title: "Source: \(availability.rawValue.capitalized)", target: sidebarTarget(for: predicate))
        case .folderPrefix(let path):
            ActiveLibraryFilterRow(title: "Folder: \(URL(fileURLWithPath: path).lastPathComponent)")
        case .camera(let camera):
            ActiveLibraryFilterRow(title: "Camera: \(camera)")
        case .lens(let lens):
            ActiveLibraryFilterRow(title: "Lens: \(lens)")
        case .isoAtLeast(let iso):
            ActiveLibraryFilterRow(title: "ISO >= \(iso)")
        case .capturedAtOrAfter(let date):
            ActiveLibraryFilterRow(title: "From \(date.formatted(date: .abbreviated, time: .omitted))")
        case .capturedBefore(let date):
            ActiveLibraryFilterRow(title: "Before \(date.formatted(date: .abbreviated, time: .omitted))")
        case .withinGeoBounds:
            ActiveLibraryFilterRow(title: "Location")
        case .evaluationKind(let kind):
            activeLibraryFilterRow(forEvaluationKind: kind)
        case .unevaluated:
            ActiveLibraryFilterRow(title: "Not analyzed yet", target: sidebarTarget(for: predicate))
        case .likelyIssue:
            ActiveLibraryFilterRow(title: "Likely Issues", target: sidebarTarget(for: predicate))
        case .likelyPick:
            ActiveLibraryFilterRow(title: "Potential Picks", target: sidebarTarget(for: predicate))
        case .evaluationFailure:
            ActiveLibraryFilterRow(title: "Analysis Failures", target: sidebarTarget(for: predicate))
        case .metadataSyncPending:
            ActiveLibraryFilterRow(title: "XMP Pending", target: sidebarTarget(for: predicate))
        case .metadataSyncConflict:
            ActiveLibraryFilterRow(title: "XMP Conflicts", target: sidebarTarget(for: predicate))
        case .importBatch(let id):
            ActiveLibraryFilterRow(title: "Import: \(id)", target: sidebarTarget(for: predicate))
        case .workSession(let id):
            ActiveLibraryFilterRow(title: "Session: \(id)", target: sidebarTarget(for: predicate))
        }
    }

    private static func activeLibraryFilterRow(forEvaluationKind kind: EvaluationKind) -> ActiveLibraryFilterRow {
        if let queue = reviewQueue(forEvaluationKind: kind) {
            return ActiveLibraryFilterRow(title: queue.presentation.title, target: .reviewQueue(queue))
        }
        return ActiveLibraryFilterRow(title: "Signal: \(kind.displayName)", target: .evaluationKind(kind))
    }

    private static func filterName(for kind: EvaluationKind) -> String {
        reviewQueue(forEvaluationKind: kind)?.presentation.title ?? "\(kind.displayName) Signal"
    }

    private static func reviewQueue(forEvaluationKind kind: EvaluationKind) -> ReviewQueue? {
        switch kind {
        case .faceCount:
            .facesFound
        case .ocrText:
            .ocrFound
        default:
            nil
        }
    }

    private static func sidebarTarget(for predicate: SetQuery.Predicate) -> SidebarRowTarget? {
        switch predicate {
        case .ratingAtLeast(let rating):
            rating == 5 ? .reviewQueue(.fiveStars) : nil
        case .flag(.pick):
            .reviewQueue(.picks)
        case .flag(.reject):
            .reviewQueue(.rejects)
        case .missingKeywords:
            .reviewQueue(.needsKeywords)
        case .availability(let availability):
            .sourceAvailability(availability)
        case .evaluationKind(let kind):
            if let queue = reviewQueue(forEvaluationKind: kind) {
                .reviewQueue(queue)
            } else {
                .evaluationKind(kind)
            }
        case .unevaluated:
            .reviewQueue(.needsEvaluation)
        case .likelyIssue:
            .reviewQueue(.likelyIssues)
        case .likelyPick:
            .reviewQueue(.potentialPicks)
        case .evaluationFailure:
            .reviewQueue(.providerFailures)
        case .metadataSyncPending:
            .metadataSyncPending
        case .metadataSyncConflict:
            .metadataSyncConflicts
        case .importBatch(let id):
            .workSession(WorkSessionID(rawValue: id))
        case .workSession(let id):
            .workSession(WorkSessionID(rawValue: id))
        default:
            nil
        }
    }

    private func removeExplicitLibraryFilter(_ row: ActiveLibraryFilterRow) -> Bool {
        var removed = false
        let trimmedKeyword = keywordFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if row.title == "Keyword: \(trimmedKeyword)" && !trimmedKeyword.isEmpty {
            keywordFilterText = ""
            removed = true
        }
        let trimmedFolder = folderFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if row.title == "Folder: \(URL(fileURLWithPath: trimmedFolder).lastPathComponent)" && !trimmedFolder.isEmpty {
            folderFilterText = ""
            removed = true
        }
        if row.title == "Rating >= \(minimumRatingFilter ?? 0)" && minimumRatingFilter != nil {
            minimumRatingFilter = nil
            removed = true
        }
        if row.title == flagFilter?.rawValue.capitalized {
            flagFilter = nil
            removed = true
        }
        if row.title == colorLabelFilter.map({ "\($0.rawValue.capitalized) Label" }) {
            colorLabelFilter = nil
            removed = true
        }
        let trimmedCamera = cameraFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if row.title == "Camera: \(trimmedCamera)" && !trimmedCamera.isEmpty {
            cameraFilterText = ""
            removed = true
        }
        let trimmedLens = lensFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if row.title == "Lens: \(trimmedLens)" && !trimmedLens.isEmpty {
            lensFilterText = ""
            removed = true
        }
        if row.title == "ISO >= \(minimumISOFilter ?? 0)" && minimumISOFilter != nil {
            minimumISOFilter = nil
            removed = true
        }
        if row.title == captureDateStartFilter.map({ "From \($0.formatted(date: .abbreviated, time: .omitted))" }) {
            captureDateStartFilter = nil
            removed = true
        }
        if row.title == captureDateEndFilter.map({ "Before \($0.formatted(date: .abbreviated, time: .omitted))" }) {
            captureDateEndFilter = nil
            removed = true
        }
        switch row.target {
        case .reviewQueue(.picks):
            if flagFilter == .pick {
                flagFilter = nil
                removed = true
            }
        case .reviewQueue(.rejects):
            if flagFilter == .reject {
                flagFilter = nil
                removed = true
            }
        case .reviewQueue(.fiveStars):
            if minimumRatingFilter == 5 {
                minimumRatingFilter = nil
                removed = true
            }
        case .reviewQueue(.needsKeywords):
            if needsKeywordsFilter {
                needsKeywordsFilter = false
                removed = true
            }
        case .reviewQueue(.needsEvaluation):
            if needsEvaluationFilter {
                needsEvaluationFilter = false
                removed = true
            }
        case .reviewQueue(.facesFound):
            if evaluationKindFilter == .faceCount {
                evaluationKindFilter = nil
                removed = true
            }
        case .reviewQueue(.ocrFound):
            if evaluationKindFilter == .ocrText {
                evaluationKindFilter = nil
                removed = true
            }
        case .reviewQueue(.likelyIssues):
            if likelyIssuesFilter {
                likelyIssuesFilter = false
                removed = true
            }
        case .reviewQueue(.potentialPicks):
            if potentialPicksFilter {
                potentialPicksFilter = false
                removed = true
            }
        case .reviewQueue(.providerFailures):
            if providerFailuresFilter {
                providerFailuresFilter = false
                removed = true
            }
        case .sourceAvailability(let availability):
            if availabilityFilter == availability {
                availabilityFilter = nil
                removed = true
            }
        case .evaluationKind(let kind):
            if evaluationKindFilter == kind {
                evaluationKindFilter = nil
                removed = true
            }
        case .metadataSyncPending:
            if metadataSyncPendingFilter {
                metadataSyncPendingFilter = false
                removed = true
            }
        case .metadataSyncConflicts:
            if metadataSyncConflictFilter {
                metadataSyncConflictFilter = false
                removed = true
            }
        default:
            break
        }
        return removed
    }

    private func removeSelectedDynamicSetRuleFilter(_ row: ActiveLibraryFilterRow) -> Bool {
        guard let selectedDynamicSetQuery else { return false }
        var removed = false
        let remainingPredicates = selectedDynamicSetQuery.predicates.filter { predicate in
            guard let predicateRow = Self.activeLibraryFilterRow(for: predicate),
                  predicateRow.title == row.title else {
                return true
            }
            if let rowTarget = row.target {
                let keepPredicate = predicateRow.target != rowTarget
                removed = removed || !keepPredicate
                return keepPredicate
            }
            removed = true
            return false
        }
        guard removed else { return false }

        selectedAssetSetID = nil
        mergePredicatesIntoDetachedLibraryFilters(remainingPredicates)
        return true
    }

    private func mergePredicatesIntoDetachedLibraryFilters(_ newPredicates: [SetQuery.Predicate]) {
        for predicate in newPredicates {
            switch predicate {
            case .text(let text):
                appendLibrarySearchToken(text)
            default:
                Self.append(predicate, to: &detachedLibraryFilterPredicates)
            }
        }
    }

    private func appendLibrarySearchToken(_ token: String) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return }
        let trimmedSearch = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        librarySearchText = trimmedSearch.isEmpty ? trimmedToken : "\(trimmedSearch) \(trimmedToken)"
    }

    private func removeDetachedLibraryFilter(_ row: ActiveLibraryFilterRow) -> Bool {
        let originalCount = detachedLibraryFilterPredicates.count
        detachedLibraryFilterPredicates.removeAll { predicate in
            guard let predicateRow = Self.activeLibraryFilterRow(for: predicate),
                  predicateRow.title == row.title else {
                return false
            }
            if let rowTarget = row.target {
                return predicateRow.target == rowTarget
            }
            return true
        }
        return detachedLibraryFilterPredicates.count != originalCount
    }

    private func removeLibrarySearchIntentFilter(_ row: ActiveLibraryFilterRow) -> Bool {
        let intent = LibrarySearchIntent.parse(librarySearchText)
        var residualText = intent.residualText
        var predicates = intent.predicates
        var removed = false

        if let currentResidualText = residualText,
           row.title == "Search: \(currentResidualText)" {
            self.librarySearchText = ""
            residualText = nil
            removed = true
        }

        predicates.removeAll { predicate in
            guard let predicateRow = Self.activeLibraryFilterRow(for: predicate),
                  predicateRow.title == row.title else {
                return false
            }
            if let rowTarget = row.target {
                return predicateRow.target == rowTarget
            }
            return true
        }
        if predicates.count != intent.predicates.count {
            removed = true
        }

        guard removed else { return false }
        librarySearchText = Self.librarySearchText(residualText: residualText, predicates: predicates)
        return true
    }

    private func currentLibraryQuery() -> SetQuery? {
        var predicates: [SetQuery.Predicate] = []
        if let selectedDynamicSetQuery {
            predicates.append(contentsOf: selectedDynamicSetQuery.predicates)
        }
        for predicate in detachedLibraryFilterPredicates {
            Self.append(predicate, to: &predicates)
        }
        let searchIntent = LibrarySearchIntent.parse(librarySearchText)
        if let residualSearch = searchIntent.residualText {
            Self.append(.text(residualSearch), to: &predicates)
        }
        for predicate in searchIntent.predicates {
            Self.append(predicate, to: &predicates)
        }
        let trimmedKeyword = keywordFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            Self.append(.keyword(trimmedKeyword), to: &predicates)
        }
        let trimmedFolder = folderFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFolder.isEmpty {
            Self.append(.folderPrefix(trimmedFolder), to: &predicates)
        }
        if let minimumRatingFilter {
            Self.append(.ratingAtLeast(minimumRatingFilter), to: &predicates)
        }
        if let flagFilter {
            Self.append(.flag(flagFilter), to: &predicates)
        }
        if let colorLabelFilter {
            Self.append(.colorLabel(colorLabelFilter), to: &predicates)
        }
        let trimmedCamera = cameraFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCamera.isEmpty {
            Self.append(.camera(trimmedCamera), to: &predicates)
        }
        let trimmedLens = lensFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLens.isEmpty {
            Self.append(.lens(trimmedLens), to: &predicates)
        }
        if let minimumISOFilter, minimumISOFilter > 0 {
            Self.append(.isoAtLeast(minimumISOFilter), to: &predicates)
        }
        if let captureDateStartFilter {
            Self.append(.capturedAtOrAfter(captureDateStartFilter), to: &predicates)
        }
        if let captureDateEndFilter {
            Self.append(.capturedBefore(captureDateEndFilter), to: &predicates)
        }
        if let geoBoundsFilter {
            Self.append(.withinGeoBounds(geoBoundsFilter), to: &predicates)
        }
        if let availabilityFilter {
            Self.append(.availability(availabilityFilter), to: &predicates)
        }
        if let evaluationKindFilter {
            Self.append(.evaluationKind(evaluationKindFilter), to: &predicates)
        }
        if needsKeywordsFilter {
            Self.append(.missingKeywords, to: &predicates)
        }
        if needsEvaluationFilter {
            Self.append(.unevaluated, to: &predicates)
        }
        if likelyIssuesFilter {
            Self.append(.likelyIssue, to: &predicates)
        }
        if potentialPicksFilter {
            Self.append(.likelyPick, to: &predicates)
        }
        if providerFailuresFilter {
            Self.append(.evaluationFailure, to: &predicates)
        }
        if metadataSyncPendingFilter {
            Self.append(.metadataSyncPending, to: &predicates)
        }
        if metadataSyncConflictFilter {
            Self.append(.metadataSyncConflict, to: &predicates)
        }
        return predicates.isEmpty ? nil : SetQuery(predicates: predicates)
    }

    private func clearLibraryQueryFilters() {
        librarySearchText = ""
        keywordFilterText = ""
        folderFilterText = ""
        minimumRatingFilter = nil
        flagFilter = nil
        colorLabelFilter = nil
        cameraFilterText = ""
        lensFilterText = ""
        minimumISOFilter = nil
        captureDateStartFilter = nil
        captureDateEndFilter = nil
        geoBoundsFilter = nil
        availabilityFilter = nil
        evaluationKindFilter = nil
        needsKeywordsFilter = false
        needsEvaluationFilter = false
        likelyIssuesFilter = false
        potentialPicksFilter = false
        providerFailuresFilter = false
        metadataSyncPendingFilter = false
        metadataSyncConflictFilter = false
        detachedLibraryFilterPredicates = []
        activeCullingSessionID = nil
    }

    // MARK: - Session restore
    //
    // Persists the library-browsing surface (route, scope, filters, search text,
    // selection, sort) so relaunching lands back where the user left off, the same
    // way LibraryGridView.thumbnailWidth already persists via app preferences.
    // Mid-culling-session state is out of scope on purpose: culling sessions already
    // survive as work sessions and are reopened explicitly via Recent Work, so
    // `.loupe`/`.compare` routes and in-progress work-stack asset sets are never
    // written or restored here.

    private func persistSessionState() {
        guard let sessionRestoreDefaults, let catalog else { return }
        SessionRestoreStore(defaults: sessionRestoreDefaults, catalogRoot: catalog.paths.root)
            .save(currentSessionRestoreState())
    }

    private func currentSessionRestoreState() -> SessionRestoreState {
        SessionRestoreState(
            selectedView: selectedView,
            selectedAssetSetID: selectedAssetSetID,
            selectedAssetID: selectedAssetID,
            sortOption: librarySortOption,
            librarySearchText: librarySearchText,
            keywordFilterText: keywordFilterText,
            folderFilterText: folderFilterText,
            minimumRatingFilter: minimumRatingFilter,
            flagFilter: flagFilter,
            colorLabelFilter: colorLabelFilter,
            cameraFilterText: cameraFilterText,
            lensFilterText: lensFilterText,
            minimumISOFilter: minimumISOFilter,
            captureDateStartFilter: captureDateStartFilter,
            captureDateEndFilter: captureDateEndFilter,
            availabilityFilter: availabilityFilter,
            evaluationKindFilter: evaluationKindFilter,
            needsKeywordsFilter: needsKeywordsFilter,
            needsEvaluationFilter: needsEvaluationFilter,
            likelyIssuesFilter: likelyIssuesFilter,
            potentialPicksFilter: potentialPicksFilter,
            providerFailuresFilter: providerFailuresFilter,
            metadataSyncPendingFilter: metadataSyncPendingFilter,
            metadataSyncConflictFilter: metadataSyncConflictFilter
        )
    }

    private func restoreSessionStateIfAvailable() throws {
        guard let sessionRestoreDefaults, let catalog else { return }
        guard let state = SessionRestoreStore(defaults: sessionRestoreDefaults, catalogRoot: catalog.paths.root).load() else {
            return
        }
        try applyRestoredSessionState(state, catalog: catalog)
    }

    // Applies a restored snapshot best-effort: references to sets or assets that no
    // longer exist are silently dropped rather than surfaced as errors, and routes
    // or scopes that belong to an in-progress culling session are never restored.
    private func applyRestoredSessionState(_ state: SessionRestoreState, catalog: AppCatalog) throws {
        librarySortOption = state.sortOption
        librarySearchText = state.librarySearchText
        keywordFilterText = state.keywordFilterText
        folderFilterText = state.folderFilterText
        minimumRatingFilter = state.minimumRatingFilter
        flagFilter = state.flagFilter
        colorLabelFilter = state.colorLabelFilter
        cameraFilterText = state.cameraFilterText
        lensFilterText = state.lensFilterText
        minimumISOFilter = state.minimumISOFilter
        captureDateStartFilter = state.captureDateStartFilter
        captureDateEndFilter = state.captureDateEndFilter
        availabilityFilter = state.availabilityFilter
        evaluationKindFilter = state.evaluationKindFilter
        needsKeywordsFilter = state.needsKeywordsFilter
        needsEvaluationFilter = state.needsEvaluationFilter
        likelyIssuesFilter = state.likelyIssuesFilter
        potentialPicksFilter = state.potentialPicksFilter
        providerFailuresFilter = state.providerFailuresFilter
        metadataSyncPendingFilter = state.metadataSyncPendingFilter
        metadataSyncConflictFilter = state.metadataSyncConflictFilter

        if let assetSetID = state.selectedAssetSetID,
           !Self.isWorkStackSetID(assetSetID),
           savedAssetSets.contains(where: { $0.id == assetSetID }) {
            selectedAssetSetID = assetSetID
        }

        selectedView = Self.isRestorableSessionRoute(state.selectedView) ? state.selectedView : .grid
        selectedAssetID = state.selectedAssetID

        try refreshWorkHistorySearchResults(repository: catalog.repository)
        if let explicitAssetIDs = selectedExplicitAssetIDs {
            let loadedAssets = try catalog.repository.assets(ids: explicitAssetIDs, flag: flagFilter, limit: explicitAssetIDs.count)
            replaceAssets(loadedAssets, preferredSelection: state.selectedAssetID)
            totalAssetCount = try catalog.repository.assetCount(ids: explicitAssetIDs, flag: flagFilter)
        } else {
            let contents = try Self.catalogContents(
                repository: catalog.repository,
                query: currentLibraryQuery(),
                sort: librarySortOption
            )
            replaceAssets(contents.assets, preferredSelection: state.selectedAssetID)
            totalAssetCount = contents.totalAssetCount
        }
        try refreshProposedAssets()
    }

    // Routes that only ever exist mid-culling-session; never auto-restored.
    private static func isRestorableSessionRoute(_ view: LibraryViewMode) -> Bool {
        switch view {
        case .grid, .timeline, .people, .map:
            return true
        case .loupe, .libraryLoupe, .compare, .abCompare, .cullGrid:
            return false
        }
    }

    private static func librarySearchText(residualText: String?, predicates: [SetQuery.Predicate]) -> String {
        ([residualText].compactMap { $0 } + predicates.compactMap(searchTextToken(for:)))
            .joined(separator: " ")
    }

    private static func searchTextToken(for predicate: SetQuery.Predicate) -> String? {
        switch predicate {
        case .text(let text):
            text
        case .ratingAtLeast(let rating):
            "rating:\(rating)"
        case .flag(let flag):
            flag == .pick ? "pick" : "reject"
        case .colorLabel(let label):
            "color:\(label.rawValue)"
        case .keyword(let keyword):
            "keyword:\(searchFieldValue(keyword))"
        case .person(let name):
            "person:\(searchFieldValue(name))"
        case .missingKeywords:
            "needs keywords"
        case .availability(let availability):
            "source:\(availability.rawValue)"
        case .folderPrefix(let path):
            "folder:\(searchFieldValue(path))"
        case .camera(let camera):
            "camera:\(searchFieldValue(camera))"
        case .lens(let lens):
            "lens:\(searchFieldValue(lens))"
        case .isoAtLeast(let iso):
            "iso:\(iso)"
        case .capturedAtOrAfter(let date):
            "from:\(searchDateString(for: date))"
        case .capturedBefore(let date):
            "before:\(searchDateString(for: date))"
        case .withinGeoBounds:
            nil
        case .evaluationKind(let kind):
            "signal:\(kind.rawValue)"
        case .unevaluated:
            "needs evaluation"
        case .likelyIssue:
            nil
        case .likelyPick:
            nil
        case .evaluationFailure:
            nil
        case .metadataSyncPending:
            "xmp:pending"
        case .metadataSyncConflict:
            "xmp:conflicts"
        case .importBatch(let id):
            "import:\(searchFieldValue(id))"
        case .workSession(let id):
            "session:\(searchFieldValue(id))"
        }
    }

    private static func searchFieldValue(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
            return value
        }
        if !value.contains("\"") {
            return "\"\(value)\""
        }
        if !value.contains("'") {
            return "'\(value)'"
        }
        return value
    }

    private static func searchDateString(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func currentLibraryAssetCount(repository: CatalogRepository) throws -> Int {
        if let explicitAssetIDs = selectedExplicitAssetIDs {
            return try repository.assetCount(ids: explicitAssetIDs, flag: flagFilter)
        }
        if let query = currentLibraryQuery() {
            return try repository.assetCount(matching: query)
        }
        return try repository.assetCount()
    }

    public func rejectRelocationPreflight(destinationFolder: URL) throws -> RejectRelocationPreflight {
        let scope = try rejectRelocationScope(destinationFolder: destinationFolder)
        let plans = RejectRelocationPlanner(destinationRoot: destinationFolder).plan(originals: scope.originalURLs)
        return RejectRelocationPreflight(
            assetIDs: scope.assetIDs,
            originalURLs: scope.originalURLs,
            plans: plans,
            sidecarCount: scope.sidecarCount,
            totalByteCount: scope.totalByteCount,
            unavailableCount: scope.unavailableCount,
            alreadyInDestinationCount: scope.alreadyInDestinationCount,
            destinationFolder: destinationFolder,
            outsideScopeCount: scope.outsideScopeCount
        )
    }

    /// Trash-mode counterpart of `rejectRelocationPreflight(destinationFolder:)`.
    /// There's no destination collision to check (the Trash isn't a catalog
    /// location), so this only counts rejects in scope and flags unavailable
    /// originals. `plans` carries identity from/to pairs — trash mode doesn't
    /// plan a destination path, `moveRejectsToTrash` only reads `originalFrom`.
    public func rejectRelocationTrashPreflight() throws -> RejectRelocationPreflight {
        let scope = try rejectRelocationScope(destinationFolder: nil)
        let plans = scope.originalURLs.map { RejectRelocationPlan(originalFrom: $0, originalTo: $0) }
        return RejectRelocationPreflight(
            assetIDs: scope.assetIDs,
            originalURLs: scope.originalURLs,
            plans: plans,
            sidecarCount: scope.sidecarCount,
            totalByteCount: scope.totalByteCount,
            unavailableCount: scope.unavailableCount,
            alreadyInDestinationCount: 0,
            destinationFolder: RejectRelocationPreflight.trashDisplayFolder,
            mode: .trash,
            outsideScopeCount: scope.outsideScopeCount
        )
    }

    private struct RejectRelocationScope {
        var assetIDs: [AssetID] = []
        var originalURLs: [URL] = []
        var sidecarCount = 0
        var totalByteCount: Int64 = 0
        var unavailableCount = 0
        var alreadyInDestinationCount = 0
        var outsideScopeCount = 0
    }

    /// Counts the rejects in the current scope that can be moved: on-disk
    /// originals plus their sidecar/byte totals. `destinationFolder` (folder
    /// mode) additionally excludes originals already under the destination;
    /// trash mode passes nil — the Trash can't already contain a catalog file.
    /// A reject whose flag is still AI-unconfirmed (an autopilot proposal the
    /// user hasn't acted on) is excluded outright, regardless of destination —
    /// only a user-confirmed reject is ever eligible for relocation/trash.
    private func rejectRelocationScope(destinationFolder: URL?) throws -> RejectRelocationScope {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let scopeIDs = try currentAssetScopeIDs(repository: catalog.repository)
        let rejectIDs = try catalog.repository.assetIDs(
            ids: scopeIDs,
            matching: SetQuery(predicates: [.flag(.reject)])
        )
        // Rejects that exist catalog-wide but fall outside the active
        // filter/scope — the sheet discloses this count instead of reading
        // as "there are no rejects" when a filter like Picks hides them all.
        let allRejectCount = try catalog.repository.assetCount(matching: SetQuery(predicates: [.flag(.reject)]))
        let sidecarStore = XMPSidecarStore()
        let destinationRootPath = destinationFolder?.standardizedFileURL.path
        var scope = RejectRelocationScope()
        for assetID in rejectIDs {
            let asset = try catalog.repository.asset(id: assetID)
            // A tentative AI reject (autopilot proposal, not yet confirmed by
            // the user) is excluded outright — it must never be moved or
            // trashed. This is the safety-critical guard: confirmed rejects
            // only ever reach `scope.assetIDs`/`originalURLs` below.
            guard !asset.metadata.aiUnconfirmedFields.contains(.flag) else {
                continue
            }
            guard FileManager.default.fileExists(atPath: asset.originalURL.path) else {
                scope.unavailableCount += 1
                continue
            }
            if let destinationRootPath,
               asset.originalURL.standardizedFileURL.path.hasPrefix(destinationRootPath + "/") {
                scope.alreadyInDestinationCount += 1
                continue
            }
            scope.assetIDs.append(assetID)
            scope.originalURLs.append(asset.originalURL)
            scope.totalByteCount += Self.fileByteCount(at: asset.originalURL)
            if let sidecarURL = sidecarStore.existingSidecarURL(forOriginalAt: asset.originalURL) {
                scope.sidecarCount += 1
                scope.totalByteCount += Self.fileByteCount(at: sidecarURL)
            }
        }
        scope.outsideScopeCount = max(0, allRejectCount - rejectIDs.count)
        return scope
    }

    private static func fileByteCount(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    @discardableResult
    public func moveRejectsToFolder(_ preflight: RejectRelocationPreflight) throws -> RejectRelocationSummary {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard !isRelocatingRejects else {
            throw TeststripError.invalidState("a relocation is already running")
        }
        isRelocatingRejects = true
        rejectRelocationAbortRequested = false
        defer { isRelocatingRejects = false }

        let sessionID = WorkSessionID(rawValue: "relocation-\(UUID().uuidString)")
        let service = RejectRelocationService()
        // Persist a running session before the loop so a crash still leaves an
        // Activity row and a partial, reversible manifest.
        try catalog.repository.save(Self.relocationWorkSession(
            id: sessionID,
            status: .running,
            destinationFolder: preflight.destinationFolder,
            movedCount: 0,
            skippedCount: 0,
            issues: []
        ))

        var movedCount = 0
        var sidecarCount = 0
        var issues: [WorkSessionIssue] = []
        // Per-file loop: move file N's bytes (original + sidecar), then rewrite
        // file N's catalog row, then record file N's manifest entry, then advance.
        // The abort flag is checked at the top of each iteration so whatever
        // already moved stays truthful and reversible.
        for (assetID, plan) in zip(preflight.assetIDs, preflight.plans) {
            if rejectRelocationAbortRequested { break }
            do {
                let result = try service.move(originalFrom: plan.originalFrom, originalTo: plan.originalTo)
                try catalog.repository.relocateOriginal(assetID: assetID, to: result.originalTo)
                try catalog.repository.saveRelocationManifestEntry(
                    RelocationManifestEntry(
                        assetID: assetID,
                        originalFrom: result.originalFrom,
                        originalTo: result.originalTo,
                        sidecarFrom: result.sidecarFrom,
                        sidecarTo: result.sidecarTo
                    ),
                    sessionID: sessionID
                )
                movedCount += 1
                if result.sidecarTo != nil { sidecarCount += 1 }
            } catch {
                // Skip-with-issue: a file that can't move is recorded and the
                // loop continues; its catalog row is left untouched.
                issues.append(WorkSessionIssue(
                    kind: .skippedSourceFile,
                    sourceURL: plan.originalFrom,
                    message: error.localizedDescription
                ))
            }
        }

        let finalStatus: WorkSessionStatus = rejectRelocationAbortRequested ? .cancelled : .completed
        let session = Self.relocationWorkSession(
            id: sessionID,
            status: finalStatus,
            destinationFolder: preflight.destinationFolder,
            movedCount: movedCount,
            skippedCount: issues.count,
            issues: issues
        )
        try catalog.repository.save(session)
        recordRecentActivity(AppWorkActivity(workSession: session))
        try reload()

        let summary = RejectRelocationSummary(
            sessionID: sessionID,
            movedCount: movedCount,
            sidecarCount: sidecarCount,
            skippedCount: issues.count,
            destinationFolder: preflight.destinationFolder
        )
        rejectRelocationSummary = summary
        statusMessage = summary.detailText
        return summary
    }

    /// Trash-mode counterpart of `moveRejectsToFolder`: files go to the
    /// platform Trash via `Recycler` (recoverable through Finder "Put Back"),
    /// and — unlike folder relocation, which just repoints the catalog row's
    /// path — the catalog row and cached previews are removed entirely. The
    /// manifest entry snapshots the removed row so Move Back can re-insert it
    /// verbatim. Machine-derived face/evaluation rows are removed with the
    /// row and deliberately NOT restored by Move Back — re-detection and
    /// re-evaluation regenerate them for the restored asset.
    @discardableResult
    public func moveRejectsToTrash(_ preflight: RejectRelocationPreflight) throws -> RejectRelocationSummary {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard !isRelocatingRejects else {
            throw TeststripError.invalidState("a relocation is already running")
        }
        isRelocatingRejects = true
        rejectRelocationAbortRequested = false
        defer { isRelocatingRejects = false }

        let sessionID = WorkSessionID(rawValue: "relocation-\(UUID().uuidString)")
        let service = RejectRelocationService()
        let recycler = FileManagerRecycler()
        // Persist a running session before the loop so a crash still leaves an
        // Activity row and a partial, reversible manifest.
        try catalog.repository.save(Self.relocationWorkSession(
            id: sessionID,
            status: .running,
            destinationFolder: RejectRelocationPreflight.trashDisplayFolder,
            movedCount: 0,
            skippedCount: 0,
            issues: []
        ))

        var movedCount = 0
        var sidecarCount = 0
        var issues: [WorkSessionIssue] = []
        // Per-file loop: snapshot asset N's row, trash its bytes (original +
        // sidecar), then remove its catalog row and cached previews, then
        // record its manifest entry, then advance. The abort flag is checked
        // at the top of each iteration so whatever already moved stays
        // truthful and reversible.
        for (assetID, plan) in zip(preflight.assetIDs, preflight.plans) {
            if rejectRelocationAbortRequested { break }
            do {
                let assetSnapshot = try catalog.repository.asset(id: assetID)
                // Person links live outside the asset row and are removed with
                // it; capture them so Move Back is a true undo.
                let personIDs = try catalog.repository.personIDs(assetID: assetID)
                let result = try service.trash(originalFrom: plan.originalFrom, recycler: recycler)
                try catalog.repository.deleteAsset(id: assetID)
                try catalog.previewCache.deleteAll(for: assetID)
                try catalog.repository.saveRelocationManifestEntry(
                    RelocationManifestEntry(
                        assetID: assetID,
                        originalFrom: result.originalFrom,
                        originalTo: result.originalTo,
                        sidecarFrom: result.sidecarFrom,
                        sidecarTo: result.sidecarTo,
                        assetSnapshot: assetSnapshot,
                        personIDs: personIDs
                    ),
                    sessionID: sessionID
                )
                movedCount += 1
                if result.sidecarTo != nil { sidecarCount += 1 }
            } catch {
                // Skip-with-issue: a file that can't be trashed is recorded and
                // the loop continues; its catalog row is left untouched.
                issues.append(WorkSessionIssue(
                    kind: .skippedSourceFile,
                    sourceURL: plan.originalFrom,
                    message: error.localizedDescription
                ))
            }
        }

        let finalStatus: WorkSessionStatus = rejectRelocationAbortRequested ? .cancelled : .completed
        let session = Self.relocationWorkSession(
            id: sessionID,
            status: finalStatus,
            destinationFolder: RejectRelocationPreflight.trashDisplayFolder,
            movedCount: movedCount,
            skippedCount: issues.count,
            issues: issues
        )
        try catalog.repository.save(session)
        recordRecentActivity(AppWorkActivity(workSession: session))
        try reload()

        let summary = RejectRelocationSummary(
            sessionID: sessionID,
            movedCount: movedCount,
            sidecarCount: sidecarCount,
            skippedCount: issues.count,
            destinationFolder: RejectRelocationPreflight.trashDisplayFolder
        )
        rejectRelocationSummary = summary
        statusMessage = summary.detailText
        return summary
    }

    public func abortRejectRelocation() {
        rejectRelocationAbortRequested = true
    }

    public func dismissRejectRelocationSummary() {
        rejectRelocationSummary = nil
    }

    @discardableResult
    public func moveBackRelocation(sessionID: WorkSessionID) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let entries = try catalog.repository.relocationManifestEntries(sessionID: sessionID)
        guard !entries.isEmpty else { return 0 }
        let service = RejectRelocationService()
        var restoredCount = 0
        // The relocated copy no longer exists (the user emptied the Trash or
        // deleted the moved file): permanently unrecoverable — reported on
        // the banner, never a reason to keep a live Move back button.
        var unrestorableCount = 0
        // Transient failures (I/O, permissions): the manifest survives so a
        // retry can still restore these.
        var restoreFailureCount = 0
        // Reverse order so nested-directory recreations undo cleanly.
        for entry in entries.reversed() {
            do {
                try service.moveBack(entry)
                if FileManager.default.fileExists(atPath: entry.originalFrom.path) {
                    if let assetSnapshot = entry.assetSnapshot {
                        // Trash-mode entry: the catalog row was removed when the
                        // asset was trashed, so restore re-inserts it verbatim
                        // (same asset ID and metadata) rather than repointing it,
                        // along with the person assignments captured at trash
                        // time. A person deleted since then is reported, not a
                        // reason to fail the asset's restore. Face/evaluation
                        // rows are not restored: they're machine-derived and
                        // regenerate via re-detection/re-evaluation.
                        try catalog.repository.upsert(assetSnapshot)
                        for personID in entry.personIDs {
                            do {
                                try catalog.repository.assignAssets([entry.assetID], toPersonID: personID)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    } else {
                        try catalog.repository.relocateOriginal(assetID: entry.assetID, to: entry.originalFrom)
                    }
                    restoredCount += 1
                } else {
                    // The Trash URL is gone (the user emptied the Trash): the
                    // asset is unrecoverable. Report it and continue restoring
                    // the rest rather than failing the whole batch.
                    unrestorableCount += 1
                }
            } catch {
                restoreFailureCount += 1
                errorMessage = error.localizedDescription
            }
        }
        // Only transient failures keep the manifest (a retry can still
        // succeed). Unrecoverable files never come back, so they must not
        // hold the manifest — and its Move back button — alive.
        if restoreFailureCount == 0 {
            try catalog.repository.deleteRelocationManifest(sessionID: sessionID)
        }
        if rejectRelocationSummary?.sessionID == sessionID {
            if unrestorableCount == 0 && restoreFailureCount == 0 {
                // Clean full restore: the banner's job is done.
                rejectRelocationSummary = nil
            } else {
                // Truthful banner update: report what restored, what is gone
                // for good, and retire Move back once nothing restorable
                // remains.
                rejectRelocationSummary?.restoredCount = restoredCount
                rejectRelocationSummary?.unrestorableCount = unrestorableCount
                rejectRelocationSummary?.restoreFailureCount = restoreFailureCount
                rejectRelocationSummary?.canMoveBack = restoreFailureCount > 0
            }
        }
        try reload()
        if unrestorableCount > 0 || restoreFailureCount > 0, let summary = rejectRelocationSummary {
            statusMessage = summary.detailText
        } else {
            statusMessage = "Moved back \(restoredCount) \(restoredCount == 1 ? "photo" : "photos")"
        }
        return restoredCount
    }

    private static func relocationWorkSession(
        id: WorkSessionID,
        status: WorkSessionStatus,
        destinationFolder: URL,
        movedCount: Int,
        skippedCount: Int,
        issues: [WorkSessionIssue]
    ) -> WorkSession {
        WorkSession(
            id: id,
            kind: .relocation,
            intent: "move-rejects-to-folder",
            title: "Move rejects to \(destinationFolder.lastPathComponent)",
            detail: "Moved \(movedCount) · skipped \(skippedCount)",
            status: status,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: movedCount,
            totalUnitCount: movedCount + skippedCount,
            failureCount: skippedCount,
            issues: issues,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func currentAssetScopeIDs(repository: CatalogRepository) throws -> [AssetID] {
        if let explicitAssetIDs = selectedExplicitAssetIDs {
            // A manual/snapshot AssetSet's membership_json can retain a
            // trashed asset's ID (deleteAsset doesn't rewrite it). Filter
            // on read rather than cascade-editing the JSON, matching how
            // assets(ids:)/assetCount(ids:) already resolve ghosts away —
            // otherwise a batch op here hits notFound and aborts entirely.
            guard !explicitAssetIDs.isEmpty else { return [] }
            return try repository.assets(ids: explicitAssetIDs, limit: explicitAssetIDs.count).map(\.id)
        }
        if let query = currentLibraryQuery() {
            return try repository.assetIDs(matching: query)
        }
        return try repository.assetIDs()
    }

    private func currentScopeCachedPreviewAssetIDs(repository: CatalogRepository, limit: Int? = nil) throws -> [AssetID] {
        var cachedAssetIDs: [AssetID] = []
        for assetID in try currentAssetScopeIDs(repository: repository) where hasCachedPreview(for: assetID) {
            cachedAssetIDs.append(assetID)
            if let limit, cachedAssetIDs.count >= limit {
                break
            }
        }
        return cachedAssetIDs
    }

    private var selectedAssetSet: AssetSet? {
        guard let selectedAssetSetID else { return nil }
        return savedAssetSets.first { $0.id == selectedAssetSetID }
    }

    private var selectedDynamicSetQuery: SetQuery? {
        guard let selectedAssetSet else { return nil }
        if case .dynamic(let query) = selectedAssetSet.membership {
            return query
        }
        return nil
    }

    private var selectedExplicitAssetIDs: [AssetID]? {
        guard let selectedAssetSet else { return nil }
        switch selectedAssetSet.membership {
        case .manual(let ids), .snapshot(let ids):
            return ids
        case .dynamic:
            return nil
        }
    }

    private var selectedWorkStackAssetIDs: [AssetID]? {
        guard let selectedAssetSetID,
              Self.isWorkStackSetID(selectedAssetSetID),
              let selectedExplicitAssetIDs,
              selectedExplicitAssetIDs.count > 1 else {
            return nil
        }
        return selectedExplicitAssetIDs
    }

    private static func isWorkStackSetID(_ id: AssetSetID) -> Bool {
        id.rawValue.hasPrefix("work-stack-")
    }

    private func persistedCullingStackSetID(_ direction: CullingStackNavigationDirection) throws -> AssetSetID? {
        guard let catalog,
              let selectedAssetSetID,
              Self.isWorkStackSetID(selectedAssetSetID),
              let session = try activePersistedStackCullingSession(repository: catalog.repository),
              let selectedIndex = session.inputSetIDs.firstIndex(of: selectedAssetSetID) else {
            return nil
        }
        let targetIndex: Int
        switch direction {
        case .previous:
            targetIndex = selectedIndex - 1
        case .next:
            targetIndex = selectedIndex + 1
        }
        guard session.inputSetIDs.indices.contains(targetIndex) else {
            return nil
        }
        return session.inputSetIDs[targetIndex]
    }

    private func selectedPersistedCullingStackPosition() throws -> (index: Int, count: Int)? {
        guard let catalog,
              let selectedAssetSetID,
              Self.isWorkStackSetID(selectedAssetSetID),
              let session = try activePersistedStackCullingSession(repository: catalog.repository),
              let selectedIndex = session.inputSetIDs.firstIndex(of: selectedAssetSetID) else {
            return nil
        }
        return (selectedIndex + 1, session.inputSetIDs.count)
    }

    private func activePersistedStackCullingSession(repository: CatalogRepository) throws -> WorkSession? {
        guard let selectedAssetSetID else { return nil }
        return try activePersistedStackCullingSession(for: selectedAssetSetID, repository: repository)
    }

    private func activePersistedStackCullingSession(
        for selectedAssetSetID: AssetSetID,
        repository: CatalogRepository
    ) throws -> WorkSession? {
        try activeCullingSession(for: selectedAssetSetID, repository: repository)
    }

    private func activeCullingSession(
        for selectedAssetSetID: AssetSetID,
        repository: CatalogRepository
    ) throws -> WorkSession? {
        let cullingSessions = try repository.workSessions(
            kind: .culling,
            statuses: [.queued, .running, .paused, .completed, .failed, .cancelled]
        )
        return cullingSessions.first { session in
            session.inputSetIDs.contains(selectedAssetSetID) || session.outputSetIDs.contains(selectedAssetSetID)
        }
    }

    private func activeCullingSession(repository: CatalogRepository) throws -> WorkSession? {
        if let selectedAssetSetID {
            return try activeCullingSession(for: selectedAssetSetID, repository: repository)
        }
        if let workSessionID = activeWorkSessionFilterID {
            let session = try repository.session(id: workSessionID)
            return session.kind == .culling ? session : nil
        }
        if let activeCullingSessionID {
            let session = try repository.session(id: activeCullingSessionID)
            return session.kind == .culling ? session : nil
        }
        return nil
    }

    private var activeWorkSessionFilterID: WorkSessionID? {
        LibrarySearchIntent.parse(librarySearchText)
            .predicates
            .compactMap { predicate -> WorkSessionID? in
                guard case .workSession(let id) = predicate else { return nil }
                return WorkSessionID(rawValue: id)
            }
            .first
    }

    private func updateActiveCullingSessionProgressAfterFlagChange() throws {
        guard let catalog,
              var session = try activeCullingSession(repository: catalog.repository) else {
            return
        }
        let previousStatus = session.status
        switch session.status {
        case .failed, .cancelled:
            return
        case .queued, .running, .paused, .completed:
            break
        }
        if let selectedAssetSetID, Self.isWorkStackSetID(selectedAssetSetID) {
            try updatePersistedStackCullingSessionProgress(selectedStackSetID: selectedAssetSetID)
            return
        }

        let inputAssetIDs = try cullingInputAssetIDs(in: session, repository: catalog.repository)
        let totalUnitCount = session.totalUnitCount ?? inputAssetIDs.count
        let completedUnitCount = try inputAssetIDs.reduce(into: 0) { count, assetID in
            // A TENTATIVE (unconfirmed autopilot) flag doesn't count as decided —
            // it's still awaiting a user confirm gesture, matching Task 13's
            // undecided semantics.
            if try catalog.repository.asset(id: assetID).metadata.confirmedProjection.flag != nil {
                count += 1
            }
        }
        session.completedUnitCount = min(completedUnitCount, totalUnitCount)
        session.totalUnitCount = totalUnitCount
        session.status = totalUnitCount > 0 && session.completedUnitCount >= totalUnitCount ? .completed : .running
        let decisionCounts = try cullingDecisionCounts(in: session, repository: catalog.repository)
        session.detail = Self.cullingProgressDetail(
            reviewedCount: session.completedUnitCount,
            totalUnitCount: totalUnitCount,
            pickCount: decisionCounts.pick,
            rejectCount: decisionCounts.reject
        )
        try refreshCullingSessionOutputSet(session: &session, repository: catalog.repository)
        updateCullingSessionCompletion(
            session: session,
            previousStatus: previousStatus,
            decisionCounts: decisionCounts,
            remainingSingleAssetIDs: try remainingUnstackedSingleAssetIDs(sessionID: session.id, repository: catalog.repository)
        )
        session.updatedAt = Date()
        try catalog.repository.save(session)
        try refreshWorkSessions()
    }

    private func updatePersistedStackCullingSessionProgress(selectedStackSetID: AssetSetID) throws {
        guard let catalog,
              var session = try activePersistedStackCullingSession(
                for: selectedStackSetID,
                repository: catalog.repository
              ) else {
            return
        }
        let previousStatus = session.status
        switch session.status {
        case .failed, .cancelled:
            return
        case .queued, .running, .paused, .completed:
            break
        }

        let completedUnitCount = try decidedPersistedStackUnitCount(
            session: session,
            repository: catalog.repository
        )
        let totalUnitCount: Int
        if let existingTotalUnitCount = session.totalUnitCount {
            totalUnitCount = existingTotalUnitCount
        } else {
            totalUnitCount = try persistedStackUnitCount(
                session: session,
                repository: catalog.repository
            )
        }
        session.completedUnitCount = min(completedUnitCount, totalUnitCount)
        session.totalUnitCount = totalUnitCount
        session.status = totalUnitCount > 0 && session.completedUnitCount >= totalUnitCount ? .completed : .running
        let decisionCounts = try cullingDecisionCounts(in: session, repository: catalog.repository)
        session.detail = Self.cullingProgressDetail(
            reviewedCount: session.completedUnitCount,
            totalUnitCount: totalUnitCount,
            pickCount: decisionCounts.pick,
            rejectCount: decisionCounts.reject
        )
        try refreshCullingSessionOutputSet(session: &session, repository: catalog.repository)
        updateCullingSessionCompletion(
            session: session,
            previousStatus: previousStatus,
            decisionCounts: decisionCounts,
            remainingSingleAssetIDs: try remainingUnstackedSingleAssetIDs(sessionID: session.id, repository: catalog.repository)
        )
        session.updatedAt = Date()
        try catalog.repository.save(session)
        try refreshWorkSessions()
    }

    // Publishes the payoff banner exactly when a session transitions into
    // .completed, and withdraws it if a later change reopens the session.
    private func updateCullingSessionCompletion(
        session: WorkSession,
        previousStatus: WorkSessionStatus,
        decisionCounts: (pick: Int, reject: Int),
        remainingSingleAssetIDs: [AssetID]
    ) {
        if session.status == .completed, previousStatus != .completed {
            let picksSetID = Self.cullingOutputSetID(sessionID: session.id)
            cullingSessionCompletion = CullingSessionCompletionSummary(
                sessionID: session.id,
                title: session.title,
                pickCount: decisionCounts.pick,
                rejectCount: decisionCounts.reject,
                picksSetID: session.outputSetIDs.contains(picksSetID) ? picksSetID : nil,
                remainingSingleAssetIDs: remainingSingleAssetIDs
            )
            return
        }
        if session.status != .completed, cullingSessionCompletion?.sessionID == session.id {
            cullingSessionCompletion = nil
        }
    }

    private func refreshCullingSessionOutputSet(
        session: inout WorkSession,
        repository: CatalogRepository
    ) throws {
        let pickedAssetIDs = try pickedAssetIDs(in: session, repository: repository)
        let outputSetID = Self.cullingOutputSetID(sessionID: session.id)
        guard !pickedAssetIDs.isEmpty else {
            if session.outputSetIDs.contains(outputSetID) {
                session.outputSetIDs.removeAll { $0 == outputSetID }
                try repository.deleteAssetSet(id: outputSetID)
                savedAssetSets = try repository.assetSets()
                assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: repository)
                rebuildSidebarSections()
            }
            return
        }
        let outputSet = AssetSet(
            id: outputSetID,
            name: "\(session.title) Picks",
            membership: .snapshot(pickedAssetIDs)
        )
        try repository.upsert(outputSet)
        if !session.outputSetIDs.contains(outputSetID) {
            session.outputSetIDs.insert(outputSetID, at: 0)
        }
        savedAssetSets = try repository.assetSets()
        assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: repository)
        rebuildSidebarSections()
    }

    // Only CONFIRMED picks — never a TENTATIVE (unconfirmed autopilot)
    // proposal — feed the persisted output set. That set is reachable to
    // Export (openCullingSessionPicks -> applyAssetSet -> exportVisibleAssets),
    // so an unconfirmed AI pick must never flow into it (confirm-before-write).
    private func pickedAssetIDs(
        in session: WorkSession,
        repository: CatalogRepository
    ) throws -> [AssetID] {
        var pickedAssetIDs: [AssetID] = []
        for assetID in try cullingInputAssetIDs(in: session, repository: repository) {
            if try repository.asset(id: assetID).metadata.confirmedProjection.flag == .pick {
                pickedAssetIDs.append(assetID)
            }
        }
        return pickedAssetIDs
    }

    private func cullingDecisionCounts(
        in session: WorkSession,
        repository: CatalogRepository
    ) throws -> (pick: Int, reject: Int) {
        var pickCount = 0
        var rejectCount = 0
        for assetID in try cullingInputAssetIDs(in: session, repository: repository) {
            // A tentative (AI-unconfirmed) flag doesn't count toward the
            // pick/reject tally — matches the non-stack progress path's use
            // of `confirmedProjection.flag` (Task 13).
            switch try repository.asset(id: assetID).metadata.confirmedProjection.flag {
            case .pick:
                pickCount += 1
            case .reject:
                rejectCount += 1
            case nil:
                break
            }
        }
        return (pickCount, rejectCount)
    }

    private func cullingInputAssetIDs(
        in session: WorkSession,
        repository: CatalogRepository
    ) throws -> [AssetID] {
        var sessionAssetIDs: [AssetID] = []
        var seenAssetIDs: Set<AssetID> = []
        for inputSetID in session.inputSetIDs {
            let inputAssetIDs = try assetIDs(in: inputSetID, repository: repository)
            for assetID in inputAssetIDs where seenAssetIDs.insert(assetID).inserted {
                sessionAssetIDs.append(assetID)
            }
        }
        return sessionAssetIDs
    }

    private func assetIDs(
        in assetSetID: AssetSetID,
        repository: CatalogRepository
    ) throws -> [AssetID] {
        let assetSet = try assetSetForSelection(id: assetSetID, repository: repository)
        return try assetIDs(in: assetSet, repository: repository)
    }

    private func assetIDs(
        in assetSet: AssetSet,
        repository: CatalogRepository
    ) throws -> [AssetID] {
        switch assetSet.membership {
        case .manual(let ids), .snapshot(let ids):
            return ids
        case .dynamic(let query):
            return try repository.assetIDs(matching: query)
        }
    }

    private func decidedPersistedStackUnitCount(
        session: WorkSession,
        repository: CatalogRepository
    ) throws -> Int {
        var count = 0
        for stackSetID in session.inputSetIDs where Self.isWorkStackSetID(stackSetID) {
            let stackAssetIDs = try explicitAssetIDs(in: stackSetID, repository: repository)
            guard !stackAssetIDs.isEmpty else { continue }
            // A stack with only tentative (AI-unconfirmed) flags is not
            // decided — matches the non-stack progress path's use of
            // `confirmedProjection.flag` (Task 13); otherwise an autopilot
            // proposal alone could flip a session to `.completed`.
            let isDecided = try stackAssetIDs.allSatisfy { assetID in
                try repository.asset(id: assetID).metadata.confirmedProjection.flag != nil
            }
            if isDecided {
                count += stackAssetIDs.count
            }
        }
        return count
    }

    private func persistedStackUnitCount(
        session: WorkSession,
        repository: CatalogRepository
    ) throws -> Int {
        var count = 0
        for stackSetID in session.inputSetIDs where Self.isWorkStackSetID(stackSetID) {
            count += try explicitAssetIDs(in: stackSetID, repository: repository).count
        }
        return count
    }

    private func explicitAssetIDs(
        in assetSetID: AssetSetID,
        repository: CatalogRepository
    ) throws -> [AssetID] {
        let assetSet = try assetSetForSelection(id: assetSetID, repository: repository)
        if case .dynamic = assetSet.membership {
            return []
        }
        return try assetIDs(in: assetSet, repository: repository)
    }

    // Avoids "Compare Manual Cull" sessions piling up in Recent work when the
    // user clicks "Choose manually" repeatedly for the same compare set.
    private func openManualCullingSession(
        forAssetIDs assetIDs: Set<AssetID>,
        repository: CatalogRepository
    ) throws -> WorkSession? {
        let openSessions = try repository.workSessions(
            kind: .culling,
            statuses: [.queued, .running, .paused]
        )
        for session in openSessions where session.title == Self.manualCullSessionTitle {
            guard let stackSetID = session.inputSetIDs.first else { continue }
            let sessionAssetIDs = try explicitAssetIDs(in: stackSetID, repository: repository)
            if Set(sessionAssetIDs) == assetIDs {
                return session
            }
        }
        return nil
    }

    private func latestImportOutputAssetIDs(repository: CatalogRepository) throws -> [AssetID] {
        guard let activity = recentWork.first(where: Self.isImportCompletionActivity) else {
            throw TeststripError.invalidState("no completed import")
        }
        return try latestImportOutputAssetIDs(activityID: activity.id, repository: repository)
    }

    private func latestImportOutputAssetIDs(activityID: String, repository: CatalogRepository) throws -> [AssetID] {
        let session = try repository.session(id: WorkSessionID(rawValue: activityID))
        guard let outputSetID = session.outputSetIDs.first else {
            return []
        }
        let assetSet = try assetSetForSelection(id: outputSetID, repository: repository)
        switch assetSet.membership {
        case .manual(let ids), .snapshot(let ids):
            return ids
        case .dynamic(let query):
            return try repository.assetIDs(matching: query)
        }
    }

    private func stackBuilder() -> AssetStackBuilder {
        AssetStackBuilder(maximumCaptureGap: Self.candidateStackMaximumCaptureGap)
    }

    private func visualSimilarityVectorsByAssetID(for assets: [Asset]) -> [AssetID: [Double]] {
        guard catalog != nil else { return [:] }
        return visualSimilarityVectorsByAssetID(for: assets) { assetID in
            evaluationSignals(for: assetID)
        }
    }

    private func visualSimilarityVectorsByAssetID(
        for assets: [Asset],
        repository: CatalogRepository
    ) -> [AssetID: [Double]] {
        visualSimilarityVectorsByAssetID(for: assets) { assetID in
            (try? repository.evaluationSignals(assetID: assetID)) ?? []
        }
    }

    private func visualSimilarityVectorsByAssetID(
        for assets: [Asset],
        signalsForAssetID: (AssetID) -> [EvaluationSignal]
    ) -> [AssetID: [Double]] {
        Dictionary(uniqueKeysWithValues: assets.compactMap { asset in
            let vector = signalsForAssetID(asset.id)
                .filter { $0.kind == .visualSimilarity }
                .compactMap { signal -> (vector: [Double], confidence: Double)? in
                    guard case .vector(let vector) = signal.value else { return nil }
                    return (vector, signal.confidence)
                }
                .sorted { lhs, rhs in lhs.confidence > rhs.confidence }
                .first?
                .vector
            return vector.map { (asset.id, $0) }
        })
    }

    private struct LatestImportStackGroups {
        var multiFrameStacks: [AssetStack]
        var singleAssetIDs: [AssetID]
    }

    private func latestImportStackGroups(activityID: String, repository: CatalogRepository) throws -> LatestImportStackGroups {
        let assetIDs = try latestImportOutputAssetIDs(activityID: activityID, repository: repository)
        let importAssets = try repository.assets(ids: assetIDs, limit: assetIDs.count)
        let allStacks = stackBuilder()
            .stacks(
                from: importAssets,
                visualSimilarityVectorsByAssetID: visualSimilarityVectorsByAssetID(for: importAssets, repository: repository)
            )
        return LatestImportStackGroups(
            multiFrameStacks: allStacks.filter { $0.assetIDs.count > 1 },
            singleAssetIDs: allStacks.filter { $0.assetIDs.count == 1 }.flatMap(\.assetIDs)
        )
    }

    private func latestImportStacks(activityID: String, repository: CatalogRepository) throws -> [AssetStack] {
        try latestImportStackGroups(activityID: activityID, repository: repository).multiFrameStacks
    }

    // Frames the stack builder left as singles, filtered to those that
    // haven't been flagged yet — the "leftover singles" a stack-cull session
    // never asked about.
    private func remainingUnstackedSingleAssetIDs(
        sessionID: WorkSessionID,
        repository: CatalogRepository
    ) throws -> [AssetID] {
        guard let activityID = stackCullingImportActivityIDBySessionID[sessionID] else {
            return []
        }
        let singleAssetIDs = try latestImportStackGroups(activityID: activityID, repository: repository).singleAssetIDs
        guard !singleAssetIDs.isEmpty else { return [] }
        return try singleAssetIDs.filter { try repository.asset(id: $0).metadata.flag == nil }
    }

    private func saveCullingStackInputSets(
        sessionID: WorkSessionID,
        title: String,
        stacks: [AssetStack]
    ) throws -> [AssetSetID] {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let stackSets = stacks.enumerated().map { index, stack in
            AssetSet.manual(
                id: AssetSetID(rawValue: "work-stack-\(sessionID.rawValue)-\(index + 1)"),
                name: "\(title) Stack \(index + 1)",
                assetIDs: stack.assetIDs
            )
        }
        for stackSet in stackSets {
            try catalog.repository.upsert(stackSet)
        }
        savedAssetSets = try catalog.repository.assetSets()
        assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        rebuildSidebarSections()
        return stackSets.map(\.id)
    }

    private func cullingInputSetID(sessionID: WorkSessionID, title: String) throws -> AssetSetID {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        if let selectedAssetSetID {
            let selectedSet = try assetSetForSelection(id: selectedAssetSetID, repository: catalog.repository)
            switch selectedSet.membership {
            case .manual, .snapshot:
                return selectedAssetSetID
            case .dynamic:
                break
            }
        }
        let inputSetID = AssetSetID(rawValue: "work-input-\(sessionID.rawValue)")
        let inputAssetIDs = try currentAssetScopeIDs(repository: catalog.repository)
        let inputSet = AssetSet(
            id: inputSetID,
            name: "\(title) Input",
            membership: .snapshot(inputAssetIDs)
        )
        try catalog.repository.upsert(inputSet)
        savedAssetSets = try catalog.repository.assetSets()
        assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        rebuildSidebarSections()
        return inputSetID
    }

    private static func cullingOutputSetID(sessionID: WorkSessionID) -> AssetSetID {
        AssetSetID(rawValue: "work-output-\(sessionID.rawValue)-picks")
    }

    private func assetSetForSelection(id: AssetSetID, repository: CatalogRepository) throws -> AssetSet {
        if let assetSet = savedAssetSets.first(where: { $0.id == id }) {
            return assetSet
        }
        return try repository.assetSet(id: id)
    }

    private func rebuildSidebarSections() {
        sidebarSections = sidebarSections(for: selectedWorkspace)
    }

    private func refreshCatalogFolders() {
        guard let catalog else { return }
        do {
            catalogFolders = try catalog.repository.folders()
            catalogTimelineDays = try catalog.repository.timelineDays()
            sourceRoots = try catalog.repository.sourceRoots()
            rebuildSidebarSections()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshCatalogEvaluationKindSummaries() {
        guard let catalog else { return }
        do {
            catalogEvaluationKindSummaries = try catalog.repository.evaluationKindSummaries()
            reviewQueueCounts = try Self.reviewQueueCounts(repository: catalog.repository)
            refreshLatestImportPresentation()
            if selectedView == .people {
                refreshPeopleFaceSuggestions()
            }
            rebuildSidebarSections()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshCatalogSidebarCounts() throws {
        guard let catalog else { return }
        reviewQueueCounts = try Self.reviewQueueCounts(repository: catalog.repository)
        assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        refreshLatestImportPresentation()
        rebuildSidebarSections()
    }

    // Exposed so the import sheet can open a read-only catalog off the main
    // actor to preview how a source folder splits into new and known content.
    public var catalogPaths: AppCatalogPaths? {
        catalog?.paths
    }

    @discardableResult
    public func importFolder(_ folderURL: URL) throws -> LibraryImportResult {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        errorMessage = nil
        statusMessage = "Importing \(folderURL.lastPathComponent)..."
        startImportActivity(folderURL: folderURL)
        do {
            let result = try catalog.importService.addFolderInPlace(
                folderURL,
                repository: catalog.repository,
                previewPolicy: .generateImmediately
            )
            try loadCatalogPage(preferredSelection: result.importedAssets.first?.id)
            updateImportStatus(with: result)
            let outputSetIDs = recordCompletedImportActivity(folderURL: folderURL, result: result)
            presentCompletedImportResultIfNeeded(result: result, outputSetIDs: outputSetIDs)
            return result
        } catch {
            failImportActivity(folderURL: folderURL, error: error)
            throw error
        }
    }

    @discardableResult
    @MainActor
    public func importFolderInBackground(_ folderURL: URL, importNewOnly: Bool = true) async throws -> LibraryImportResult {
        importAutoEvaluationEnabled = true
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        errorMessage = nil
        statusMessage = "Importing \(folderURL.lastPathComponent)..."
        startImportActivity(folderURL: folderURL)
        guard let activityID = activeWork?.id else {
            throw TeststripError.invalidState("import activity was not created")
        }
        let paths = catalog.paths
        do {
            let output = try await importTaskFactory(
                paths,
                folderURL,
                importNewOnly ? .skipCatalogedContent : .importAll,
                importProgressHandler(activityID: activityID)
            ).value
            replaceAssets(
                output.assets,
                preferredSelection: output.result.importedAssets.first?.id
            )
            totalAssetCount = output.totalAssetCount
            try enqueuePendingPreviewGeneration()
            updateImportStatus(with: output.result)
            let outputSetIDs = recordCompletedImportActivity(folderURL: folderURL, result: output.result)
            scheduleImportAutoEvaluationIfEnabled(result: output.result)
            presentCompletedImportResultIfNeeded(result: output.result, outputSetIDs: outputSetIDs)
            return output.result
        } catch {
            failImportActivity(folderURL: folderURL, error: error)
            throw error
        }
    }

    @discardableResult
    @MainActor
    public func importCardInBackground(
        source: URL,
        destinationRoot: URL,
        destinationPolicy: ImportDestinationPolicy = .flat,
        secondCopyDestination: URL? = nil,
        importNewOnly: Bool = true
    ) async throws -> LibraryImportResult {
        importAutoEvaluationEnabled = true
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        errorMessage = nil
        statusMessage = "Importing \(source.lastPathComponent)..."
        startImportActivity(folderURL: source, destinationRoot: destinationRoot)
        guard let activityID = activeWork?.id else {
            throw TeststripError.invalidState("import activity was not created")
        }
        let paths = catalog.paths
        do {
            let output = try await cardImportTaskFactory(
                paths,
                source,
                destinationRoot,
                destinationPolicy,
                secondCopyDestination,
                importNewOnly ? .skipCatalogedContent : .importAll,
                importProgressHandler(activityID: activityID)
            ).value
            replaceAssets(
                output.assets,
                preferredSelection: output.result.importedAssets.first?.id
            )
            totalAssetCount = output.totalAssetCount
            try enqueuePendingPreviewGeneration()
            updateImportStatus(with: output.result)
            let outputSetIDs = recordCompletedImportActivity(folderURL: source, destinationRoot: destinationRoot, result: output.result)
            scheduleImportAutoEvaluationIfEnabled(result: output.result)
            presentCompletedImportResultIfNeeded(result: output.result, outputSetIDs: outputSetIDs)
            return output.result
        } catch {
            failImportActivity(folderURL: source, destinationRoot: destinationRoot, error: error)
            throw error
        }
    }

    @MainActor
    public func beginImportFolder(
        _ folderURL: URL,
        evaluateAfterImport: Bool = true,
        importNewOnly: Bool = true,
        autopilotAfterImport: Bool = false
    ) {
        guard let catalog else {
            errorMessage = TeststripError.invalidState("app model has no catalog").localizedDescription
            return
        }
        guard !isImporting else {
            errorMessage = "Another import is already running"
            return
        }
        // Set only after the concurrency guard so a rejected call cannot change
        // the in-flight import's auto-evaluation outcome.
        importAutoEvaluationEnabled = evaluateAfterImport
        let duplicateHandling: DuplicateHandling = importNewOnly ? .skipCatalogedContent : .importAll
        autopilotArmedForActiveImport = autopilotAfterImport
        if let blockingReason = ImportSourcePreflight.blockingReason(for: folderURL) {
            failImportBeforeStart(folderURL: folderURL, reason: blockingReason)
            return
        }
        errorMessage = nil
        statusMessage = "Importing \(folderURL.lastPathComponent)..."
        if workerSupervisor != nil && workerImportsEnabled {
            enqueueWorkerImport(
                source: folderURL,
                destinationRoot: nil,
                command: .importFolder(root: folderURL, duplicateHandling: duplicateHandling)
            )
            return
        }
        let didAccess: Bool
        do {
            didAccess = try startAccessingImportResource(folderURL)
        } catch {
            failImportBeforeStart(folderURL: folderURL, reason: error.localizedDescription)
            return
        }
        startImportActivity(folderURL: folderURL)
        guard let activityID = activeWork?.id else {
            stopAccessingImportResource(folderURL, didAccess: didAccess)
            return
        }

        let task = importTaskFactory(
            catalog.paths,
            folderURL,
            duplicateHandling,
            importProgressHandler(activityID: activityID)
        )
        activeImportTask = task
        Task { @MainActor [weak self] in
            defer {
                self?.stopAccessingImportResource(folderURL, didAccess: didAccess)
            }
            do {
                let output = try await task.value
                guard let self, self.activeWork?.id == activityID else { return }
                self.replaceAssets(
                    output.assets,
                    preferredSelection: output.result.importedAssets.first?.id
                )
                self.totalAssetCount = output.totalAssetCount
                try self.enqueuePendingPreviewGeneration()
                self.updateImportStatus(with: output.result)
                let outputSetIDs = self.recordCompletedImportActivity(folderURL: folderURL, result: output.result)
                self.scheduleImportAutoEvaluationIfEnabled(result: output.result)
                self.presentCompletedImportResultIfNeeded(result: output.result, outputSetIDs: outputSetIDs)
                self.activeImportTask = nil
            } catch is CancellationError {
                guard let self, self.activeWork?.id == activityID else { return }
                self.cancelImportActivity(folderURL: folderURL)
                self.activeImportTask = nil
            } catch {
                guard let self, self.activeWork?.id == activityID else { return }
                self.statusMessage = nil
                self.errorMessage = error.localizedDescription
                self.failImportActivity(folderURL: folderURL, error: error)
                self.activeImportTask = nil
            }
        }
    }

    @MainActor
    public func beginImportCard(
        source: URL,
        destinationRoot: URL,
        destinationPolicy: ImportDestinationPolicy = .flat,
        secondCopyDestination: URL? = nil,
        evaluateAfterImport: Bool = true,
        importNewOnly: Bool = true,
        autopilotAfterImport: Bool = false
    ) {
        guard let catalog else {
            errorMessage = TeststripError.invalidState("app model has no catalog").localizedDescription
            return
        }
        guard !isImporting else {
            errorMessage = "Another import is already running"
            return
        }
        // Set only after the concurrency guard so a rejected call cannot change
        // the in-flight import's auto-evaluation outcome.
        importAutoEvaluationEnabled = evaluateAfterImport
        let duplicateHandling: DuplicateHandling = importNewOnly ? .skipCatalogedContent : .importAll
        autopilotArmedForActiveImport = autopilotAfterImport
        if let blockingReason = ImportSourcePreflight.blockingReason(for: source) {
            failImportBeforeStart(folderURL: source, destinationRoot: destinationRoot, reason: blockingReason)
            return
        }
        if let blockingReason = CardImportDestinationPreflight.blockingReason(source: source, destinationRoot: destinationRoot) {
            failImportBeforeStart(folderURL: source, destinationRoot: destinationRoot, reason: blockingReason)
            return
        }
        if let secondCopyDestination,
           let blockingReason = CardImportDestinationPreflight.secondCopyBlockingReason(
               source: source,
               destinationRoot: destinationRoot,
               secondCopyDestination: secondCopyDestination
           ) {
            failImportBeforeStart(folderURL: source, destinationRoot: destinationRoot, reason: blockingReason)
            return
        }
        errorMessage = nil
        statusMessage = "Importing \(source.lastPathComponent)..."
        if workerSupervisor != nil && workerImportsEnabled {
            enqueueWorkerImport(
                source: source,
                destinationRoot: destinationRoot,
                secondCopyDestination: secondCopyDestination,
                command: .importCard(
                    source: source,
                    destinationRoot: destinationRoot,
                    destinationPolicy: destinationPolicy,
                    secondCopyDestination: secondCopyDestination,
                    duplicateHandling: duplicateHandling
                )
            )
            return
        }
        let didAccessSource: Bool
        let didAccessDestination: Bool
        let didAccessSecondCopy: Bool
        do {
            didAccessSource = try startAccessingImportResource(source)
            do {
                didAccessDestination = try startAccessingImportResource(destinationRoot)
            } catch {
                stopAccessingImportResource(source, didAccess: didAccessSource)
                throw error
            }
            do {
                didAccessSecondCopy = try secondCopyDestination.map(startAccessingImportResource) ?? false
            } catch {
                stopAccessingImportResource(destinationRoot, didAccess: didAccessDestination)
                stopAccessingImportResource(source, didAccess: didAccessSource)
                throw error
            }
        } catch {
            failImportBeforeStart(folderURL: source, destinationRoot: destinationRoot, reason: error.localizedDescription)
            return
        }
        startImportActivity(folderURL: source, destinationRoot: destinationRoot)
        guard let activityID = activeWork?.id else {
            stopAccessingImportResource(source, didAccess: didAccessSource)
            stopAccessingImportResource(destinationRoot, didAccess: didAccessDestination)
            if let secondCopyDestination {
                stopAccessingImportResource(secondCopyDestination, didAccess: didAccessSecondCopy)
            }
            return
        }

        let task = cardImportTaskFactory(
            catalog.paths,
            source,
            destinationRoot,
            destinationPolicy,
            secondCopyDestination,
            duplicateHandling,
            importProgressHandler(activityID: activityID)
        )
        activeImportTask = task
        Task { @MainActor [weak self] in
            defer {
                self?.stopAccessingImportResource(source, didAccess: didAccessSource)
                self?.stopAccessingImportResource(destinationRoot, didAccess: didAccessDestination)
                if let secondCopyDestination {
                    self?.stopAccessingImportResource(secondCopyDestination, didAccess: didAccessSecondCopy)
                }
            }
            do {
                let output = try await task.value
                guard let self, self.activeWork?.id == activityID else { return }
                self.replaceAssets(
                    output.assets,
                    preferredSelection: output.result.importedAssets.first?.id
                )
                self.totalAssetCount = output.totalAssetCount
                try self.enqueuePendingPreviewGeneration()
                self.updateImportStatus(with: output.result)
                let outputSetIDs = self.recordCompletedImportActivity(folderURL: source, destinationRoot: destinationRoot, result: output.result)
                self.scheduleImportAutoEvaluationIfEnabled(result: output.result)
                self.presentCompletedImportResultIfNeeded(result: output.result, outputSetIDs: outputSetIDs)
                self.activeImportTask = nil
            } catch is CancellationError {
                guard let self, self.activeWork?.id == activityID else { return }
                self.cancelImportActivity(folderURL: source, destinationRoot: destinationRoot)
                self.activeImportTask = nil
            } catch {
                guard let self, self.activeWork?.id == activityID else { return }
                self.statusMessage = nil
                self.errorMessage = error.localizedDescription
                self.failImportActivity(folderURL: source, destinationRoot: destinationRoot, error: error)
                self.activeImportTask = nil
            }
        }
    }

    @MainActor
    public func cancelActiveWork() {
        guard let activeImportTask else { return }
        statusMessage = "Cancelling import..."
        activeImportTask.cancel()
    }

    private func updateImportStatus(with result: LibraryImportResult) {
        try? refreshPreviewGenerationQueueStates()
        try? refreshCatalogSidebarCounts()
        statusMessage = Self.importCompletionStatus(result: result)
        if let warningText = Self.importCompletionWarningText(result: result) {
            statusMessage?.append(" (\(warningText))")
        }
    }

    private static func importCompletionStatus(result: LibraryImportResult) -> String {
        guard !result.importedAssets.isEmpty else {
            if result.skippedSourceFileCount > 0 {
                return "No photos imported"
            }
            return "No supported photos found"
        }
        guard result.newAssetCount > 0 else {
            return "No new photos found"
        }
        let photoLabel = result.newAssetCount == 1 ? "photo" : "photos"
        var status = "Imported \(result.newAssetCount) \(photoLabel)"
        if result.existingAssetCount > 0 {
            let existingLabel = result.existingAssetCount == 1 ? "photo" : "photos"
            status.append(" (\(result.existingAssetCount) \(existingLabel) already in catalog)")
        }
        return status
    }

    private static func importCompletionWarningText(result: LibraryImportResult) -> String? {
        var warnings: [String] = []
        if result.skippedSourceFileCount > 0 {
            let fileLabel = result.skippedSourceFileCount == 1 ? "file" : "files"
            warnings.append("\(result.skippedSourceFileCount) \(fileLabel) skipped")
        }
        if result.backupFailureCount > 0 {
            let copyLabel = result.backupFailureCount == 1 ? "backup copy" : "backup copies"
            warnings.append("\(result.backupFailureCount) \(copyLabel) failed")
        }
        if !result.previewFailures.isEmpty {
            let previewLabel = result.previewFailures.count == 1 ? "preview failure" : "preview failures"
            warnings.append("\(result.previewFailures.count) \(previewLabel)")
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: ", ")
    }

    private func startImportActivity(folderURL: URL, destinationRoot: URL? = nil) {
        displayedLocalImportCatalogedAssetID = nil
        importError = nil
        let activity = AppWorkActivity(
            kind: .ingest,
            status: .running,
            title: "Import photos",
            detail: "Importing from \(importSourceDescription(folderURL: folderURL, destinationRoot: destinationRoot))",
            completedUnitCount: 0,
            totalUnitCount: nil,
            failureCount: 0
        )
        activeWork = activity
        recordRecentActivity(activity)
    }

    private func failImportBeforeStart(folderURL: URL, destinationRoot: URL? = nil, reason: String) {
        statusMessage = nil
        errorMessage = reason
        failImportActivity(
            folderURL: folderURL,
            destinationRoot: destinationRoot,
            error: TeststripError.invalidState(reason)
        )
    }

    private func importProgressHandler(activityID: String) -> LibraryImportProgressHandler {
        let sink = AppImportProgressSink(model: self, activityID: activityID)
        return { progress in
            sink.handle(progress)
        }
    }

    fileprivate func applyImportProgress(_ progress: LibraryImportProgress) {
        if displayedLocalImportCatalogedAssetID == nil,
           let firstCatalogedAssetID = progress.catalogedAssetIDs.first {
            do {
                try loadCatalogPage(preferredSelection: firstCatalogedAssetID)
                displayedLocalImportCatalogedAssetID = firstCatalogedAssetID
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        guard var activity = activeWork else { return }
        activity.detail = progress.detail
        activity.completedUnitCount = progress.completedUnitCount
        activity.totalUnitCount = progress.totalUnitCount
        activeWork = activity
    }

    private func recordCompletedImportActivity(
        id: String? = nil,
        folderURL: URL,
        destinationRoot: URL? = nil,
        result: LibraryImportResult
    ) -> [AssetSetID] {
        let activity = AppWorkActivity(
            id: id ?? activeWork?.id ?? UUID().uuidString,
            kind: .ingest,
            status: .completed,
            title: "Import photos",
            detail: Self.importCompletionDetail(
                result: result,
                sourceDescription: importSourceDescription(folderURL: folderURL, destinationRoot: destinationRoot)
            ),
            completedUnitCount: result.newAssetCount,
            totalUnitCount: result.importedAssets.count,
            failureCount: result.previewFailures.count,
            issues: Self.workSessionIssues(for: result)
        )
        let outputSetIDs = saveImportOutputSet(for: activity, result: result)
        persistSecurityScopedBookmarkForImportedSource(
            folderURL: folderURL,
            destinationRoot: destinationRoot,
            result: result
        )
        refreshCatalogFolders()
        activeWork = nil
        displayedLocalImportCatalogedAssetID = nil
        recordRecentActivity(activity, outputSetIDs: outputSetIDs)
        return outputSetIDs
    }

    private func presentCompletedImportResultIfNeeded(result: LibraryImportResult, outputSetIDs: [AssetSetID]) {
        guard let firstImportedAssetID = result.importedAssets.first?.id,
              let outputSetID = outputSetIDs.first else {
            return
        }
        let activeScopeWouldHideImport = selectedAssetSetID != nil || currentLibraryQuery() != nil
        let loadedPageHidesImport = !assets.contains { $0.id == firstImportedAssetID }
        guard activeScopeWouldHideImport || loadedPageHidesImport else { return }
        do {
            try applyAssetSet(id: outputSetID)
            selectAssetID(firstImportedAssetID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistSecurityScopedBookmarkForImportedSource(
        folderURL: URL,
        destinationRoot: URL?,
        result: LibraryImportResult
    ) {
        guard !result.importedAssets.isEmpty else { return }
        let sourceRoot = destinationRoot ?? folderURL
        persistSecurityScopedBookmarkForSourceRoot(sourceRoot)
    }

    private func persistSecurityScopedBookmarkForSourceRoot(_ sourceRoot: URL) {
        guard let catalog, let bookmarkData = try? resourceAccess.securityScopedBookmarkData(sourceRoot) else { return }
        do {
            try catalog.repository.recordSourceRoot(sourceRoot, securityScopedBookmarkData: bookmarkData)
            sourceRootBookmarkRepairPaths.remove(Self.normalizedSourceRootPath(sourceRoot))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func normalizedSourceRootPath(_ sourceRoot: URL) -> String {
        var path = sourceRoot.standardizedFileURL.path
        if path != "/", path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private static func importCompletionDetail(result: LibraryImportResult, sourceDescription: String) -> String {
        let warningSuffix = importCompletionWarningText(result: result).map { " (\($0))" } ?? ""
        if result.importedAssets.isEmpty {
            if result.skippedSourceFileCount == 0 {
                return "No supported photos found in \(sourceDescription)"
            }
            return "No photos imported from \(sourceDescription)\(warningSuffix)"
        }
        if result.newAssetCount == 0 {
            return "No new photos found in \(sourceDescription)\(warningSuffix)"
        }
        return "\(importCompletionStatus(result: result)) from \(sourceDescription)\(warningSuffix)"
    }

    private static func workSessionIssues(for result: LibraryImportResult) -> [WorkSessionIssue] {
        result.skippedSourceFiles.map { skippedSourceFile in
            WorkSessionIssue(
                kind: .skippedSourceFile,
                sourceURL: skippedSourceFile.sourceURL,
                message: skippedSourceFile.message
            )
        }
    }

    private func failImportActivity(id: String? = nil, folderURL: URL, destinationRoot: URL? = nil, error: Error) {
        let activity = AppWorkActivity(
            id: id ?? activeWork?.id ?? UUID().uuidString,
            kind: .ingest,
            status: .failed,
            title: "Import photos",
            detail: "Import failed from \(importSourceDescription(folderURL: folderURL, destinationRoot: destinationRoot)): \(error.localizedDescription)",
            completedUnitCount: 0,
            totalUnitCount: nil,
            failureCount: 1
        )
        activeWork = nil
        displayedLocalImportCatalogedAssetID = nil
        importError = error.localizedDescription
        recordRecentActivity(activity)
    }

    private func cancelImportActivity(id: String? = nil, folderURL: URL, destinationRoot: URL? = nil) {
        let activity = AppWorkActivity(
            id: id ?? activeWork?.id ?? UUID().uuidString,
            kind: .ingest,
            status: .cancelled,
            title: "Import photos",
            detail: "Cancelled import from \(importSourceDescription(folderURL: folderURL, destinationRoot: destinationRoot))",
            completedUnitCount: activeWork?.completedUnitCount ?? 0,
            totalUnitCount: activeWork?.totalUnitCount,
            failureCount: 0
        )
        activeWork = nil
        displayedLocalImportCatalogedAssetID = nil
        statusMessage = "Cancelled import"
        recordRecentActivity(activity)
    }

    private func importSourceDescription(folderURL: URL, destinationRoot: URL?) -> String {
        guard let destinationRoot else {
            return folderURL.lastPathComponent
        }
        return "\(folderURL.lastPathComponent) to \(destinationRoot.lastPathComponent)"
    }

    private static func photoCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "photo" : "photos")"
    }

    private static func cullingDecisionLabel(picked: Int, rejected: Int) -> String {
        "Kept \(picked), rejected \(rejected)"
    }

    private static func stackCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "stack" : "stacks")"
    }

    private static func cullingProgressDetail(
        reviewedCount: Int,
        totalUnitCount: Int,
        pickCount: Int,
        rejectCount: Int
    ) -> String {
        [
            "Reviewed \(reviewedCount) of \(frameCountDescription(totalUnitCount))",
            "\(pickCount) \(pickCount == 1 ? "pick" : "picks")",
            "\(rejectCount) \(rejectCount == 1 ? "reject" : "rejects")"
        ].joined(separator: " · ")
    }

    private static func frameCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "frame" : "frames")"
    }

    private static func isImportCompletionActivity(_ activity: AppWorkActivity) -> Bool {
        activity.kind == .ingest && activity.status == .completed
    }

    private func saveImportOutputSet(for activity: AppWorkActivity, result: LibraryImportResult) -> [AssetSetID] {
        guard let catalog, !result.importedAssets.isEmpty else {
            return []
        }
        let outputSetID = AssetSetID(rawValue: "work-output-\(activity.id)")
        let outputSet = AssetSet.manual(
            id: outputSetID,
            name: activity.detail,
            assetIDs: result.importedAssets.map(\.id)
        )
        do {
            try catalog.repository.upsert(outputSet)
            if !savedAssetSets.contains(where: { $0.id == outputSetID }) {
                savedAssetSets.append(outputSet)
                assetSetCounts[outputSetID] = result.importedAssets.count
            }
            return [outputSetID]
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Whether this activity was recorded live during the current app
    /// session, as opposed to restored from the persisted work history on
    /// launch. Completion banners/panels are session-scoped: only live
    /// work may auto-show one (persona-7's relaunch-zombie panel).
    public func isCurrentSessionActivity(id: String) -> Bool {
        currentSessionActivityIDs.contains(id)
    }

    private func recordRecentActivity(
        _ activity: AppWorkActivity,
        intent: String? = nil,
        inputSetIDs: [AssetSetID] = [],
        outputSetIDs: [AssetSetID] = []
    ) {
        var recordedActivity = activity
        recordedActivity.inputSetIDs = inputSetIDs
        recordedActivity.outputSetIDs = outputSetIDs
        currentSessionActivityIDs.insert(recordedActivity.id)
        recentWork.removeAll { $0.id == recordedActivity.id }
        recentWork.insert(recordedActivity, at: 0)
        refreshLatestImportPresentation()
        guard let catalog else {
            rebuildSidebarSections()
            return
        }
        do {
            try catalog.repository.save(recordedActivity.workSession(
                intent: intent,
                inputSetIDs: inputSetIDs,
                outputSetIDs: outputSetIDs
            ))
            let sessionID = WorkSessionID(rawValue: recordedActivity.id)
            workSessionScopeCounts[sessionID] = try catalog.repository.assetCount(
                matching: SetQuery(predicates: [.workSession(recordedActivity.id)])
            )
            rebuildSidebarSections()
        } catch {
            rebuildSidebarSections()
            errorMessage = error.localizedDescription
        }
    }

    private static func defaultImportTask(
        paths: AppCatalogPaths,
        folderURL: URL,
        previewPolicy: LibraryImportPreviewPolicy,
        duplicateHandling: DuplicateHandling,
        progress: @escaping LibraryImportProgressHandler
    ) -> Task<AppImportOutput, Error> {
        Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let backgroundCatalog = try AppCatalog.open(paths: paths)
            let result = try backgroundCatalog.importService.addFolderInPlace(
                folderURL,
                repository: backgroundCatalog.repository,
                previewPolicy: previewPolicy,
                duplicateHandling: duplicateHandling,
                progress: progress
            )
            try Task.checkCancellation()
            let contents = try Self.catalogContents(
                repository: backgroundCatalog.repository,
                query: nil
            )
            return AppImportOutput(
                result: result,
                assets: contents.assets,
                totalAssetCount: contents.totalAssetCount
            )
        }
    }

    private static func defaultCardImportTask(
        paths: AppCatalogPaths,
        source: URL,
        destinationRoot: URL,
        destinationPolicy: ImportDestinationPolicy,
        secondCopyDestination: URL?,
        previewPolicy: LibraryImportPreviewPolicy,
        duplicateHandling: DuplicateHandling,
        progress: @escaping LibraryImportProgressHandler
    ) -> Task<AppImportOutput, Error> {
        Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let backgroundCatalog = try AppCatalog.open(paths: paths)
            let result = try backgroundCatalog.importService.copyFromCard(
                source: source,
                destinationRoot: destinationRoot,
                destinationPolicy: destinationPolicy,
                secondCopyDestination: secondCopyDestination,
                repository: backgroundCatalog.repository,
                previewPolicy: previewPolicy,
                duplicateHandling: duplicateHandling,
                progress: progress
            )
            try Task.checkCancellation()
            let contents = try Self.catalogContents(
                repository: backgroundCatalog.repository,
                query: nil
            )
            return AppImportOutput(
                result: result,
                assets: contents.assets,
                totalAssetCount: contents.totalAssetCount
            )
        }
    }

    // Loads the whole catalog (optionally filtered by `query`) for the library
    // grid, which relies on display-level windowing rather than a load window.
    private static func catalogContents(
        repository: CatalogRepository,
        query: SetQuery?,
        sort: LibrarySortOption = .importOrder
    ) throws -> (assets: [Asset], totalAssetCount: Int) {
        if let query {
            let assets = try repository.allAssets(matching: query, sort: sort)
            let totalAssetCount = try repository.assetCount(matching: query)
            return (assets, totalAssetCount)
        }
        let assets = try repository.allAssets(sort: sort)
        let totalAssetCount = try repository.assetCount()
        return (assets, totalAssetCount)
    }

    private static func commonAncestorPath(for paths: [String]) -> String? {
        guard var commonComponents = paths.first.map({ URL(fileURLWithPath: $0).standardizedFileURL.pathComponents }) else {
            return nil
        }
        for path in paths.dropFirst() {
            let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
            var sharedComponents: [String] = []
            for (lhs, rhs) in zip(commonComponents, components) {
                guard lhs == rhs else { break }
                sharedComponents.append(lhs)
            }
            commonComponents = sharedComponents
        }
        guard !commonComponents.isEmpty else { return nil }
        let path = NSString.path(withComponents: commonComponents)
        guard path != "/", path != "/Volumes" else { return nil }
        return path
    }

    public func gridPreviewURL(for assetID: AssetID) -> URL? {
        if let cachedURL = gridPreviewURLCacheByAssetID[assetID] {
            return cachedURL
        }
        let url = previewURL(for: assetID, levels: [.grid, .micro])
        gridPreviewURLCacheByAssetID[assetID] = url
        return url
    }

    func gridPreviewStatus(for assetID: AssetID) -> AssetGridPreviewStatusPresentation? {
        if let cachedStatus = gridPreviewStatusCacheByAssetID[assetID] {
            return cachedStatus
        }
        let previewURL = gridPreviewURL(for: assetID)
        let thumbnailLevels: [PreviewLevel] = [.grid, .micro]
        let queueStates = previewGenerationQueueStates.filter { state in
            state.item.assetID == assetID && thumbnailLevels.contains(state.item.level)
        }
        let activePreviewLevels = thumbnailLevels.filter { level in
            let itemID = Self.previewWorkItemID(assetID: assetID, level: level)
            guard let item = backgroundWorkQueue.item(id: itemID) else { return false }
            return Self.isActiveBackgroundWorkStatus(item.status)
        }
        let status = AssetGridPreviewStatusPresentation.presentation(
            previewURL: previewURL,
            queueStates: queueStates,
            activePreviewLevels: activePreviewLevels
        )
        gridPreviewStatusCacheByAssetID[assetID] = status
        return status
    }

    public func loupePreviewURL(for assetID: AssetID) -> URL? {
        previewURL(for: assetID, levels: [.large, .medium, .grid, .micro])
    }

    // The zoomed loupe prefers an original-resolution render when one has
    // been cached; the fitted loupe keeps using loupePreviewURL so frame
    // advance never decodes full-resolution files it does not need.
    public func loupeZoomPreviewURL(for assetID: AssetID) -> URL? {
        previewURL(for: assetID, levels: [.original, .large, .medium, .grid, .micro])
    }

    private func cachedLoupePreviewLevel(for assetID: AssetID) -> PreviewLevel? {
        [PreviewLevel.original, .large, .medium, .grid, .micro].first { level in
            previewURL(for: assetID, levels: [level]) != nil
        }
    }

    public func originalAccessURL(for assetID: AssetID) throws -> URL? {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let availability = try refreshAvailability(for: assetID)
        try refreshSourceAvailabilitySummaries()
        guard !availability.requiresCachedPreviewOnly else { return nil }
        return try catalog.repository.asset(id: assetID).originalURL
    }

    public func previewURL(for assetID: AssetID, levels: [PreviewLevel]) -> URL? {
        guard let catalog else { return nil }
        for level in levels {
            let url = catalog.previewCache.url(for: PreviewCacheKey(assetID: assetID, level: level))
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// The cached address-book photo (+ its face box) for a person that was
    /// seeded from Contacts, or nil if this person has no contact reference.
    public func contactReferencePhoto(forPersonID personID: String) -> (url: URL, box: FaceBoundingBox)? {
        guard let catalog,
              let reference = try? catalog.repository.contactReferenceFace(personID: personID) else { return nil }
        let url = catalog.contactPhotoCache.url(for: reference.contactIdentifier)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (url, reference.boundingBox)
    }

    private func hasCachedPreview(for assetID: AssetID) -> Bool {
        previewURL(for: assetID, levels: [.large, .medium, .grid, .micro]) != nil
    }

    private static func defaultSidebarSections(
        totalAssetCount: Int? = nil,
        savedAssetSets: [AssetSet] = [],
        assetSetCounts: [AssetSetID: Int] = [:],
        workSessionScopeCounts: [WorkSessionID: Int] = [:],
        catalogFolders: [CatalogFolder] = [],
        expandedFolderPaths: Set<String> = [],
        catalogTimelineDays: [CatalogTimelineDay] = [],
        sourceAvailabilitySummaries: [CatalogSourceAvailabilitySummary] = [],
        catalogEvaluationKindSummaries: [CatalogEvaluationKindSummary] = [],
        reviewQueueCounts: [ReviewQueue: Int] = [:],
        pendingMetadataSyncItems: [MetadataSyncItem] = [],
        metadataSyncConflictItems: [MetadataSyncItem] = [],
        pendingMetadataSyncCount: Int? = nil,
        metadataSyncConflictCount: Int? = nil,
        recentWork: [AppWorkActivity] = [],
        starredWork: [AppWorkActivity] = [],
        matchedWork: [AppWorkActivity] = [],
        sourceRoots: [CatalogSourceRoot] = [],
        sourceRootBookmarkRepairPaths: Set<String> = []
    ) -> [SidebarSection] {
        // Library is navigation only: Collections (All Photographs, Recent
        // Import, Starred, Recent Work), Saved Sets, Folders. Search/Review/
        // Timeline/People/Places routes moved to the workspace switcher, the
        // Library view toggle, and the Cull source picker; review-queue data
        // (`reviewQueueCounts`) stays available for the Cull sidebar even
        // though its Library rows are gone.
        var collectionsRows = [
            SidebarRow(
                id: "library-all",
                title: "All Photographs",
                countText: totalAssetCount.map(sidebarCountText),
                target: .allPhotographs
            )
        ]
        if let recentImportRow = recentlyAddedSidebarRow(recentWork) {
            collectionsRows.append(recentImportRow)
        }
        let visibleSavedAssetSets = Self.visibleSavedAssetSets(savedAssetSets)
        let starredRows = visibleSavedAssetSets.filter(\.starred).map { Self.sidebarRow(for: $0, count: assetSetCounts[$0.id]) }
        collectionsRows.append(contentsOf: starredRows)
        if matchedWork.isEmpty {
            collectionsRows.append(contentsOf: mergedRecentWorkSidebarRows(
                recentWork: recentWork,
                starredWork: starredWork,
                scopeCounts: workSessionScopeCounts
            ))
        } else {
            // An active Library query narrows Recent Work to the sessions
            // matching its plain-text remainder (the SearchWorkspace "Work
            // History" rail's home after Task 9), keeping their reopen targets.
            collectionsRows.append(contentsOf: Self.workSidebarRows(
                for: matchedWork,
                idPrefix: "work-matched",
                scopeCounts: workSessionScopeCounts
            ))
        }

        var sections = [SidebarSection(title: "Collections", rows: collectionsRows)]
        if !visibleSavedAssetSets.isEmpty {
            sections.append(SidebarSection(title: "Saved Sets", rows: visibleSavedAssetSets.map { Self.sidebarRow(for: $0, count: assetSetCounts[$0.id]) }))
        }
        if !catalogFolders.isEmpty {
            sections.append(SidebarSection(
                title: "Folders",
                rows: folderTreeSidebarRows(catalogFolders: catalogFolders, expandedFolderPaths: expandedFolderPaths)
            ))
        }
        return sections
    }

    /// Folds the Recent Work and Starred Work rows into one list: the most
    /// recent sessions, plus any starred session old enough to have fallen
    /// out of that recent window (deduplicated by session id).
    private static func mergedRecentWorkSidebarRows(
        recentWork: [AppWorkActivity],
        starredWork: [AppWorkActivity],
        scopeCounts: [WorkSessionID: Int]
    ) -> [SidebarRow] {
        let recentSlice = Array(recentWork.prefix(5))
        let recentIDs = Set(recentSlice.map(\.id))
        let extraStarred = starredWork.filter { !recentIDs.contains($0.id) }
        return Self.workSidebarRows(for: recentSlice, idPrefix: "work-recent", scopeCounts: scopeCounts)
            + Self.workSidebarRows(for: Array(extraStarred.prefix(5)), idPrefix: "work-starred", scopeCounts: scopeCounts)
    }

    /// Flattens the folder tree into sidebar rows, only descending into a
    /// node's children when its full path is in `expandedFolderPaths` -
    /// expand-on-demand, so a deep or wide tree never renders more than the
    /// rows the user has actually opened.
    private static func folderTreeSidebarRows(
        catalogFolders: [CatalogFolder],
        expandedFolderPaths: Set<String>
    ) -> [SidebarRow] {
        FolderTreePresentation.build(from: catalogFolders).flatMap { node in
            folderTreeSidebarRows(for: node, depth: 0, expandedFolderPaths: expandedFolderPaths)
        }
    }

    private static func folderTreeSidebarRows(
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
            countText: sidebarCountText(node.assetCount),
            target: .folder(node.fullPath),
            depth: depth,
            disclosure: disclosure
        )
        guard isExpanded else {
            return [row]
        }
        return [row] + node.children.flatMap { child in
            folderTreeSidebarRows(for: child, depth: depth + 1, expandedFolderPaths: expandedFolderPaths)
        }
    }

    private static func reviewQueueSidebarRows(reviewQueueCounts: [ReviewQueue: Int]) -> [SidebarRow] {
        reviewQueueSidebarOrder.compactMap { queue in
            guard let count = reviewQueueCounts[queue],
                  count > 0 else {
                return nil
            }
            return SidebarRow(
                id: "review-\(queue.rawValue)",
                title: queue.presentation.title,
                countText: sidebarCountText(count),
                target: .reviewQueue(queue)
            )
        }
    }

    private static let reviewQueueSidebarOrder: [ReviewQueue] = [
        .picks,
        .potentialPicks,
        .rejects,
        .fiveStars,
        .needsKeywords,
        .needsEvaluation,
        .facesFound,
        .ocrFound,
        .likelyIssues,
        .providerFailures
    ]

    private static func reviewQueueCounts(repository: CatalogRepository) throws -> [ReviewQueue: Int] {
        var counts: [ReviewQueue: Int] = [:]
        for queue in reviewQueueSidebarOrder {
            counts[queue] = try repository.assetCount(matching: reviewQueueQuery(queue))
        }
        return counts
    }

    private static func reviewQueueQuery(_ queue: ReviewQueue) -> SetQuery {
        switch queue {
        case .picks:
            return SetQuery(predicates: [.flag(.pick)])
        case .potentialPicks:
            return SetQuery(predicates: [.likelyPick])
        case .rejects:
            return SetQuery(predicates: [.flag(.reject)])
        case .fiveStars:
            return SetQuery(predicates: [.ratingAtLeast(5)])
        case .needsKeywords:
            return SetQuery(predicates: [.missingKeywords])
        case .needsEvaluation:
            return SetQuery(predicates: [.unevaluated])
        case .facesFound:
            return SetQuery(predicates: [.evaluationKind(.faceCount)])
        case .ocrFound:
            return SetQuery(predicates: [.evaluationKind(.ocrText)])
        case .likelyIssues:
            return SetQuery(predicates: [.likelyIssue])
        case .providerFailures:
            return SetQuery(predicates: [.evaluationFailure])
        }
    }

    private static func sourceAvailabilitySummaries(repository: CatalogRepository) throws -> [CatalogSourceAvailabilitySummary] {
        try sourceAvailabilitySidebarOrder.compactMap { availability in
            let count = try repository.assetCount(matching: SetQuery(predicates: [.availability(availability)]))
            guard count > 0 else { return nil }
            return CatalogSourceAvailabilitySummary(availability: availability, assetCount: count)
        }
    }

    private static let sourceAvailabilitySidebarOrder: [SourceAvailability] = [
        .offline,
        .missing,
        .moved,
        .stale
    ]

    /// Display name for the Activity Center's per-availability source row.
    fileprivate static func sourceAvailabilityDisplayName(_ availability: SourceAvailability) -> String {
        switch availability {
        case .online:
            return "Online Originals"
        case .offline:
            return "Offline Originals"
        case .missing:
            return "Missing Originals"
        case .moved:
            return "Moved Originals"
        case .stale:
            return "Stale Originals"
        }
    }

    private static func recentlyAddedSidebarRow(_ recentWork: [AppWorkActivity]) -> SidebarRow? {
        guard let activity = recentWork.first(where: { activity in
            isImportCompletionActivity(activity)
                && !activity.outputSetIDs.isEmpty
                && (activity.totalUnitCount ?? activity.completedUnitCount) > 0
        }) else {
            return nil
        }
        return SidebarRow(
            id: "library-recently-added",
            title: "Recent Import",
            detailText: activity.detail.isEmpty ? "Latest import" : activity.detail,
            countText: sidebarCountText(activity.totalUnitCount ?? activity.completedUnitCount),
            tone: .positive,
            target: .workSession(WorkSessionID(rawValue: activity.id))
        )
    }

    private static func visibleSavedAssetSets(_ assetSets: [AssetSet]) -> [AssetSet] {
        assetSets.filter {
            !$0.id.rawValue.hasPrefix("work-output-")
                && !$0.id.rawValue.hasPrefix("work-input-")
                && !$0.id.rawValue.hasPrefix("work-stack-")
        }
    }

    private static func sidebarRow(for assetSet: AssetSet, count: Int?) -> SidebarRow {
        SidebarRow(
            id: "asset-set-\(assetSet.id.rawValue)",
            title: assetSet.name,
            detailText: assetSet.sidebarDetailText,
            countText: count.map(sidebarCountText),
            tone: assetSet.isDynamic ? .accent : .neutral,
            target: .assetSet(assetSet.id)
        )
    }

    private static func assetSetCounts(_ assetSets: [AssetSet], repository: CatalogRepository) throws -> [AssetSetID: Int] {
        let visibleAssetSets = visibleSavedAssetSets(assetSets)
        var counts: [AssetSetID: Int] = [:]
        for assetSet in visibleAssetSets {
            counts[assetSet.id] = try assetCount(for: assetSet, repository: repository)
        }
        return counts
    }

    private static func assetCount(for assetSet: AssetSet, repository: CatalogRepository) throws -> Int {
        switch assetSet.membership {
        case .manual(let ids), .snapshot(let ids):
            return try repository.assetCount(ids: ids)
        case .dynamic(let query):
            return try repository.assetCount(matching: query)
        }
    }

    private static func workSessionScopeCounts(
        activities: [AppWorkActivity],
        repository: CatalogRepository
    ) throws -> [WorkSessionID: Int] {
        var counts: [WorkSessionID: Int] = [:]
        for activity in activities {
            let sessionID = WorkSessionID(rawValue: activity.id)
            do {
                counts[sessionID] = try repository.assetCount(matching: SetQuery(predicates: [.workSession(activity.id)]))
            } catch CatalogError.notFound {
                continue
            }
        }
        return counts
    }

    private static func workSidebarRows(
        for activities: [AppWorkActivity],
        idPrefix: String,
        scopeCounts: [WorkSessionID: Int]
    ) -> [SidebarRow] {
        activities.map { activity in
            let sessionID = WorkSessionID(rawValue: activity.id)
            return SidebarRow(
                id: "\(idPrefix)-\(activity.id)",
                title: workSidebarTitle(for: activity),
                detailText: activity.sidebarDetailText,
                countText: activity.sidebarCountText(scopeCount: scopeCounts[sessionID]),
                tone: activity.sidebarTone,
                target: .workSession(sessionID)
            )
        }
    }

    fileprivate static func sidebarCountText(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }

    private static func workSidebarTitle(for activity: AppWorkActivity) -> String {
        let trimmedTitle = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = activity.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle == "Import photos", !trimmedDetail.isEmpty {
            return trimmedDetail
        }
        return trimmedTitle.isEmpty && !trimmedDetail.isEmpty ? trimmedDetail : activity.title
    }

    fileprivate static func workKindTitle(_ kind: WorkSessionKind) -> String {
        switch kind {
        case .ingest:
            return "Import"
        case .previewGeneration:
            return "Previews"
        case .recognition:
            return "Recognition"
        case .culling:
            return "Culling"
        case .collecting:
            return "Collecting"
        case .searchSort:
            return "Search"
        case .keywording:
            return "Keywording"
        case .xmpSync:
            return "XMP"
        case .sourceScan:
            return "Source scan"
        case .export:
            return "Export"
        case .relocation:
            return "Move rejects"
        case .geocoding:
            return "Geocoding"
        case .locationBackfill:
            return "Reading locations"
        }
    }
}

private extension AssetSet {
    var sidebarDetailText: String {
        switch membership {
        case .dynamic:
            return "Smart collection"
        case .manual:
            return "Manual set"
        case .snapshot:
            return "Snapshot"
        }
    }
}

private extension AppWorkActivity {
    var sidebarDetailText: String? {
        switch status {
        case .running:
            return detail.isEmpty ? "Running" : detail
        case .paused:
            return detail.isEmpty ? "Paused" : detail
        case .queued:
            return detail.isEmpty ? "Queued" : detail
        case .failed:
            return detail.isEmpty ? "Failed" : detail
        case .cancelled:
            return detail.isEmpty ? "Cancelled" : detail
        case .completed:
            return AppModel.workKindTitle(kind)
        }
    }

    func sidebarCountText(scopeCount: Int?) -> String? {
        if let scopeCount {
            return AppModel.sidebarCountText(scopeCount)
        }
        guard let totalUnitCount, totalUnitCount > 0 else {
            return completedUnitCount > 0 ? AppModel.sidebarCountText(completedUnitCount) : nil
        }
        return "\(completedUnitCount)/\(totalUnitCount)"
    }

    var sidebarTone: SidebarRowTone {
        switch status {
        case .completed:
            return .positive
        case .failed:
            return .destructive
        case .paused, .cancelled:
            return .warning
        case .queued, .running:
            return .accent
        }
    }

    func workSession(
        now: Date = Date(),
        intent: String? = nil,
        inputSetIDs: [AssetSetID] = [],
        outputSetIDs: [AssetSetID] = []
    ) -> WorkSession {
        WorkSession(
            id: WorkSessionID(rawValue: id),
            kind: kind,
            intent: intent ?? title,
            title: title,
            detail: detail,
            status: status,
            inputSetIDs: inputSetIDs,
            outputSetIDs: outputSetIDs,
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            failureCount: failureCount,
            issues: issues,
            starred: starred,
            createdAt: now,
            updatedAt: now
        )
    }
}

extension SourceAvailability {
    var requiresCachedPreviewOnly: Bool {
        switch self {
        case .offline, .missing, .moved:
            return true
        case .online, .stale:
            return false
        }
    }
}

private final class AppImportProgressSink: @unchecked Sendable {
    private weak var model: AppModel?
    private let activityID: String

    init(model: AppModel, activityID: String) {
        self.model = model
        self.activityID = activityID
    }

    func handle(_ progress: LibraryImportProgress) {
        Task { @MainActor in
            self.apply(progress)
        }
    }

    @MainActor
    private func apply(_ progress: LibraryImportProgress) {
        guard let model, model.activeWork?.id == activityID else { return }
        model.applyImportProgress(progress)
    }
}

private final class AppExportProgressSink: @unchecked Sendable {
    private weak var model: AppModel?
    private let destinationName: String

    init(model: AppModel, destinationName: String) {
        self.model = model
        self.destinationName = destinationName
    }

    func handle(completedCount: Int, totalCount: Int) {
        Task { @MainActor in
            // Late-arriving progress hops are dropped once the export summary
            // has landed, so the completion message is never overwritten.
            guard let model = self.model, model.isExporting else { return }
            model.statusMessage = "Exporting photo \(completedCount) of \(totalCount) to \(self.destinationName)..."
        }
    }
}
