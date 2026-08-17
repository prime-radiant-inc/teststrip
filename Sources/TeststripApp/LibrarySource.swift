import Foundation
import TeststripCore

/// The import-scoped child rows an import row discloses.
public enum ImportChildKind: String, Codable, Equatable, Sendable {
    case stacks
    case skippedFiles
    case previewFailed
    case likelyIssues
    case facesFound

    public var title: String {
        switch self {
        case .stacks: return "Stacks"
        case .skippedFiles: return "⚠ Skipped files"
        case .previewFailed: return "⚠ Preview failed"
        case .likelyIssues: return "⚠ Likely issues"
        case .facesFound: return "Faces found"
        }
    }

    public var systemImage: String {
        switch self {
        case .stacks: return "square.stack"
        case .skippedFiles: return "exclamationmark.triangle"
        case .previewFailed: return "exclamationmark.triangle"
        case .likelyIssues: return "exclamationmark.triangle"
        case .facesFound: return "person.2"
        }
    }

    /// Skipped files are not in the catalog at all, so that child opens the
    /// issue-review sheet (`AppModel.requestImportIssueReview`) rather than a
    /// Grid scope; a failed preview's asset is catalogued and opens in Grid
    /// for inspection. The Cull lens disables on both.
    public var isDiagnostic: Bool {
        self == .skippedFiles || self == .previewFailed
    }
}

/// What a source *is*. Every case names a set of photos; none of them names a
/// way of looking at one — `.timeline`, `.people`, and `.places` were lenses
/// masquerading as sources and are gone.
public enum LibrarySourceKind: Equatable, Codable, Sendable {
    case allPhotos
    case search(SetQuery)
    case smartCollection(SmartCollection)
    case autopilotSuggestions
    case folder(String)
    case sourceAvailability(SourceAvailability)
    case evaluationKind(EvaluationKind)
    case metadataSyncPending
    case metadataSyncConflicts
    case assetSet(AssetSetID)
    case workSession(WorkSessionID)
    case importChild(session: WorkSessionID, child: ImportChildKind)
    case selection
}

/// A named set of photos: the stored answer to "what am I looking at". The
/// title travels with the kind because several kinds (a saved set, an import,
/// a search) cannot derive their own display name.
public struct LibrarySource: Equatable, Codable, Sendable {
    public var kind: LibrarySourceKind
    public var title: String

    public init(kind: LibrarySourceKind, title: String) {
        self.kind = kind
        self.title = title
    }

    /// Identity is the set of photos a source names (`kind`), not its display
    /// title. Two sources with the same kind but different titles (a work
    /// session constructed from different code paths) must compare equal so
    /// nav-history dedupe and `LibraryQueryToken.legacyRows` don't create
    /// spurious back-stack entries or double-render.
    public static func == (lhs: LibrarySource, rhs: LibrarySource) -> Bool {
        lhs.kind == rhs.kind
    }

    /// Diagnostic sources hold problems rather than photographs. The Cull lens
    /// disables on them; they open in Grid for inspection.
    public var isDiagnostic: Bool {
        switch kind {
        case .importChild(_, let child):
            return child.isDiagnostic
        case .smartCollection(let collection):
            return collection == .providerFailures
        case .metadataSyncConflicts, .metadataSyncPending, .sourceAvailability:
            return true
        case .allPhotos, .search, .autopilotSuggestions, .folder, .evaluationKind,
             .assetSet, .workSession, .selection:
            return false
        }
    }

    public static let allPhotos = LibrarySource(kind: .allPhotos, title: "All Photos")
    public static let autopilotSuggestions = LibrarySource(kind: .autopilotSuggestions, title: "AI Suggestions")
    public static let metadataSyncPending = LibrarySource(kind: .metadataSyncPending, title: "XMP Pending")
    public static let metadataSyncConflicts = LibrarySource(kind: .metadataSyncConflicts, title: "XMP Conflicts")
    public static let selection = LibrarySource(kind: .selection, title: "Selection")

    public static func search(_ query: SetQuery, titled title: String) -> LibrarySource {
        LibrarySource(kind: .search(query), title: title)
    }

    public static func smartCollection(_ collection: SmartCollection) -> LibrarySource {
        LibrarySource(kind: .smartCollection(collection), title: collection.presentation.title)
    }

    public static func folder(_ path: String) -> LibrarySource {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return LibrarySource(kind: .folder(path), title: name.isEmpty ? path : name)
    }

    public static func sourceAvailability(_ availability: SourceAvailability) -> LibrarySource {
        LibrarySource(
            kind: .sourceAvailability(availability),
            title: "\(availability.rawValue.capitalized) Originals"
        )
    }

    public static func evaluationKind(_ kind: EvaluationKind, titled title: String) -> LibrarySource {
        LibrarySource(kind: .evaluationKind(kind), title: title)
    }

    public static func assetSet(_ id: AssetSetID, titled title: String) -> LibrarySource {
        LibrarySource(kind: .assetSet(id), title: title)
    }

    public static func workSession(_ id: WorkSessionID, titled title: String) -> LibrarySource {
        LibrarySource(kind: .workSession(id), title: title)
    }

    public static func importChild(session: WorkSessionID, child: ImportChildKind) -> LibrarySource {
        LibrarySource(kind: .importChild(session: session, child: child), title: child.title)
    }
}
