import Foundation
import SwiftUI
import TeststripCore

/// Bridges AppModel's 13 structured library-filter properties to a single
/// stream of query tokens, on top of `LibrarySearchIntent`'s existing
/// deterministic grammar. Nothing here forks that grammar — every token's
/// text form is produced by / fed back into `LibrarySearchIntent.parse`.
public struct LibraryQueryToken: Equatable, Identifiable {
    public enum Field: Equatable {
        case rating
        case flag
        case keyword
        case folder
        case camera
        case lens
        case iso
        case dateFrom
        case dateBefore
        case color
        case source
        case signal
        case xmpPending
        case xmpConflict
        /// Recognized by `LibrarySearchIntent` but with no structured
        /// AppModel property backing it (e.g. `person:`). Round-trips
        /// through `librarySearchText` verbatim.
        case passthrough
    }

    public enum Value: Equatable {
        case int(Int)
        case text(String)
        case date(Date)
        case flag(PickFlag)
        case color(ColorLabel)
        case source(SourceAvailability)
        case signal(EvaluationKind)
    }

    public let field: Field
    public let display: String
    public let value: Value

    public var id: String { "\(field)" }

    /// The `LibrarySearchIntent`-compatible text form, e.g. `rating:3`.
    public var searchText: String {
        switch (field, value) {
        case (.rating, .int(let rating)):
            return "rating:\(rating)"
        case (.flag, .flag(let flag)):
            return flag == .pick ? "pick" : "reject"
        case (.keyword, .text(let text)):
            return "keyword:\(quoted(text))"
        case (.folder, .text(let text)):
            return "folder:\(quoted(text))"
        case (.camera, .text(let text)):
            return "camera:\(quoted(text))"
        case (.lens, .text(let text)):
            return "lens:\(quoted(text))"
        case (.iso, .int(let iso)):
            return "iso:\(iso)"
        case (.dateFrom, .date(let date)):
            return "from:\(Self.isoDay(date))"
        case (.dateBefore, .date(let date)):
            return "before:\(Self.isoDay(date))"
        case (.color, .color(let color)):
            return "color:\(color.rawValue)"
        case (.source, .source(let source)):
            return "source:\(source.rawValue)"
        case (.signal, .signal(let kind)):
            return "signal:\(kind.rawValue)"
        case (.xmpPending, _):
            return "xmp:pending"
        case (.xmpConflict, _):
            return "xmp:conflict"
        case (.passthrough, .text(let fragment)):
            return fragment
        default:
            return ""
        }
    }

    private func quoted(_ text: String) -> String {
        text.contains(" ") ? "\"\(text)\"" : text
    }

    private static func isoDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    // MARK: - Reading tokens from AppModel's structured filter state

    /// One token per active structured filter on `model`. Free text /
    /// `person:` etc. already round-trip through `librarySearchText` and are
    /// not represented here — they remain visible via the plain text field.
    public static func tokens(from model: AppModel) -> [LibraryQueryToken] {
        var tokens: [LibraryQueryToken] = []

        if let rating = model.minimumRatingFilter {
            tokens.append(LibraryQueryToken(field: .rating, display: "Rating >= \(rating)", value: .int(rating)))
        }
        if let flag = model.flagFilter {
            tokens.append(LibraryQueryToken(field: .flag, display: flag.rawValue.capitalized, value: .flag(flag)))
        }
        let trimmedKeyword = model.keywordFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            tokens.append(LibraryQueryToken(field: .keyword, display: "Keyword: \(trimmedKeyword)", value: .text(trimmedKeyword)))
        }
        let trimmedFolder = model.folderFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFolder.isEmpty {
            let title = URL(fileURLWithPath: trimmedFolder).lastPathComponent
            tokens.append(LibraryQueryToken(field: .folder, display: "Folder: \(title)", value: .text(trimmedFolder)))
        }
        let trimmedCamera = model.cameraFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCamera.isEmpty {
            tokens.append(LibraryQueryToken(field: .camera, display: "Camera: \(trimmedCamera)", value: .text(trimmedCamera)))
        }
        let trimmedLens = model.lensFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLens.isEmpty {
            tokens.append(LibraryQueryToken(field: .lens, display: "Lens: \(trimmedLens)", value: .text(trimmedLens)))
        }
        if let iso = model.minimumISOFilter, iso > 0 {
            tokens.append(LibraryQueryToken(field: .iso, display: "ISO >= \(iso)", value: .int(iso)))
        }
        if let start = model.captureDateStartFilter {
            let title = start.formatted(date: .abbreviated, time: .omitted)
            tokens.append(LibraryQueryToken(field: .dateFrom, display: "From \(title)", value: .date(start)))
        }
        if let end = model.captureDateEndFilter {
            let title = end.formatted(date: .abbreviated, time: .omitted)
            tokens.append(LibraryQueryToken(field: .dateBefore, display: "Before \(title)", value: .date(end)))
        }
        if let color = model.colorLabelFilter {
            tokens.append(LibraryQueryToken(field: .color, display: "\(color.rawValue.capitalized) Label", value: .color(color)))
        }
        if let source = model.availabilityFilter {
            tokens.append(LibraryQueryToken(field: .source, display: "Source: \(source.rawValue.capitalized)", value: .source(source)))
        }
        if let signal = model.evaluationKindFilter {
            tokens.append(LibraryQueryToken(field: .signal, display: "Signal: \(signal.displayName)", value: .signal(signal)))
        }
        if model.metadataSyncPendingFilter {
            tokens.append(LibraryQueryToken(field: .xmpPending, display: "XMP Pending", value: .int(0)))
        }
        if model.metadataSyncConflictFilter {
            tokens.append(LibraryQueryToken(field: .xmpConflict, display: "XMP Conflicts", value: .int(0)))
        }

        return tokens
    }

    // MARK: - Writing a token back into AppModel's structured filter state

    public static func apply(_ token: LibraryQueryToken, to model: AppModel) {
        switch (token.field, token.value) {
        case (.rating, .int(let rating)):
            model.minimumRatingFilter = rating
        case (.flag, .flag(let flag)):
            model.flagFilter = flag
        case (.keyword, .text(let text)):
            model.keywordFilterText = text
        case (.folder, .text(let text)):
            model.folderFilterText = text
        case (.camera, .text(let text)):
            model.cameraFilterText = text
        case (.lens, .text(let text)):
            model.lensFilterText = text
        case (.iso, .int(let iso)):
            model.minimumISOFilter = iso
        case (.dateFrom, .date(let date)):
            model.captureDateStartFilter = date
        case (.dateBefore, .date(let date)):
            model.captureDateEndFilter = date
        case (.color, .color(let color)):
            model.colorLabelFilter = color
        case (.source, .source(let source)):
            model.availabilityFilter = source
        case (.signal, .signal(let signal)):
            model.evaluationKindFilter = signal
        case (.xmpPending, _):
            model.metadataSyncPendingFilter = true
        case (.xmpConflict, _):
            model.metadataSyncConflictFilter = true
        default:
            // .passthrough tokens live in librarySearchText, which
            // parse(_:applyingTo:) reconstructs itself — applying one here
            // would double-append its fragment.
            break
        }
    }

    /// Clears exactly this token's backing property, leaving every sibling
    /// filter untouched.
    public static func remove(_ token: LibraryQueryToken, from model: AppModel) {
        switch token.field {
        case .rating:
            model.minimumRatingFilter = nil
        case .flag:
            model.flagFilter = nil
        case .keyword:
            model.keywordFilterText = ""
        case .folder:
            model.folderFilterText = ""
        case .camera:
            model.cameraFilterText = ""
        case .lens:
            model.lensFilterText = ""
        case .iso:
            model.minimumISOFilter = nil
        case .dateFrom:
            model.captureDateStartFilter = nil
        case .dateBefore:
            model.captureDateEndFilter = nil
        case .color:
            model.colorLabelFilter = nil
        case .source:
            model.availabilityFilter = nil
        case .signal:
            model.evaluationKindFilter = nil
        case .xmpPending:
            model.metadataSyncPendingFilter = false
        case .xmpConflict:
            model.metadataSyncConflictFilter = false
        case .passthrough:
            if case .text(let fragment) = token.value {
                let updated = model.librarySearchText
                    .replacingOccurrences(of: fragment, with: "")
                model.librarySearchText = updated
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
        }
    }

    // MARK: - Parsing typed free text

    public struct ParseResult {
        public let recognizedTokens: [LibraryQueryToken]
        public let freeText: String?
    }

    /// Parses `text` with `LibrarySearchIntent`, writes every recognized
    /// structured predicate into `model`'s matching property, and leaves
    /// anything without a structured AppModel backing (e.g. `person:`) plus
    /// plain free text in `model.librarySearchText`.
    @discardableResult
    public static func parse(_ text: String, applyingTo model: AppModel) -> ParseResult {
        let intent = LibrarySearchIntent.parse(text)
        var recognized: [LibraryQueryToken] = []
        var passthroughChips: [String] = []

        for predicate in intent.predicates {
            if let token = structuredToken(for: predicate) {
                apply(token, to: model)
                recognized.append(token)
            } else {
                // No structured AppModel property backs this predicate
                // (e.g. person:) — keep it expressed in librarySearchText's
                // own syntax so it keeps round-tripping through
                // LibrarySearchIntent as it does today.
                let fragment = searchTextFragment(for: predicate)
                if !fragment.isEmpty {
                    passthroughChips.append(fragment)
                    recognized.append(LibraryQueryToken(field: .passthrough, display: fragment, value: .text(fragment)))
                }
            }
        }

        var remainder = passthroughChips
        if let freeText = intent.residualText {
            remainder.append(freeText)
        }
        model.librarySearchText = remainder.joined(separator: " ")

        return ParseResult(recognizedTokens: recognized, freeText: intent.residualText)
    }

    private static func structuredToken(for predicate: SetQuery.Predicate) -> LibraryQueryToken? {
        switch predicate {
        case .ratingAtLeast(let rating):
            return LibraryQueryToken(field: .rating, display: "Rating >= \(rating)", value: .int(rating))
        case .flag(let flag):
            return LibraryQueryToken(field: .flag, display: flag.rawValue.capitalized, value: .flag(flag))
        case .keyword(let keyword):
            return LibraryQueryToken(field: .keyword, display: "Keyword: \(keyword)", value: .text(keyword))
        case .folderPrefix(let path):
            let title = URL(fileURLWithPath: path).lastPathComponent
            return LibraryQueryToken(field: .folder, display: "Folder: \(title)", value: .text(path))
        case .camera(let camera):
            return LibraryQueryToken(field: .camera, display: "Camera: \(camera)", value: .text(camera))
        case .lens(let lens):
            return LibraryQueryToken(field: .lens, display: "Lens: \(lens)", value: .text(lens))
        case .isoAtLeast(let iso):
            return LibraryQueryToken(field: .iso, display: "ISO >= \(iso)", value: .int(iso))
        case .capturedAtOrAfter(let date):
            let title = date.formatted(date: .abbreviated, time: .omitted)
            return LibraryQueryToken(field: .dateFrom, display: "From \(title)", value: .date(date))
        case .capturedBefore(let date):
            let title = date.formatted(date: .abbreviated, time: .omitted)
            return LibraryQueryToken(field: .dateBefore, display: "Before \(title)", value: .date(date))
        case .colorLabel(let color):
            return LibraryQueryToken(field: .color, display: "\(color.rawValue.capitalized) Label", value: .color(color))
        case .availability(let source):
            return LibraryQueryToken(field: .source, display: "Source: \(source.rawValue.capitalized)", value: .source(source))
        case .evaluationKind(let signal):
            return LibraryQueryToken(field: .signal, display: "Signal: \(signal.displayName)", value: .signal(signal))
        case .metadataSyncPending:
            return LibraryQueryToken(field: .xmpPending, display: "XMP Pending", value: .int(0))
        case .metadataSyncConflict:
            return LibraryQueryToken(field: .xmpConflict, display: "XMP Conflicts", value: .int(0))
        default:
            return nil
        }
    }

    /// Reconstructs the original `field:value` syntax for a predicate that
    /// has no structured AppModel property (currently only `person:`), so it
    /// can be preserved verbatim in `librarySearchText`.
    private static func searchTextFragment(for predicate: SetQuery.Predicate) -> String {
        switch predicate {
        case .person(let name):
            return "person:\(name.contains(" ") ? "\"\(name)\"" : name)"
        case .workSession(let id):
            return "session:\(id)"
        case .importBatch(let id):
            return "import:\(id)"
        default:
            return ""
        }
    }

    // MARK: - Deduplicating legacy chip rows against tokens

    /// Filters `activeLibraryFilterRows` down to rows not already rendered
    /// as a structured token chip. Dedupe is by filter identity, not just
    /// title: `.faceCount`/`.ocrText` legacy rows carry review-queue titles
    /// ("Faces Found"/"Text Found") that never match the token's
    /// "Signal: …" display, so title-only matching would double-render.
    public static func legacyRows(
        _ rows: [ActiveLibraryFilterRow],
        notCoveredBy tokens: [LibraryQueryToken]
    ) -> [ActiveLibraryFilterRow] {
        let tokenTitles = Set(tokens.map(\.display))
        let tokenTargets = tokens.flatMap(sidebarTargets(for:))
        return rows.filter { row in
            if tokenTitles.contains(row.title) { return false }
            if let target = row.target, tokenTargets.contains(target) { return false }
            return true
        }
    }

    /// Every `SidebarRowTarget` a legacy row for this token's filter could
    /// carry (mirrors `AppModel.activeLibraryFilterRows`'s target choices).
    private static func sidebarTargets(for token: LibraryQueryToken) -> [SidebarRowTarget] {
        switch (token.field, token.value) {
        case (.rating, .int(let rating)):
            return rating == 5 ? [.reviewQueue(.fiveStars)] : []
        case (.flag, .flag(let flag)):
            return [.reviewQueue(flag == .pick ? .picks : .rejects)]
        case (.source, .source(let source)):
            return [.sourceAvailability(source)]
        case (.signal, .signal(let kind)):
            switch kind {
            case .faceCount:
                return [.evaluationKind(kind), .reviewQueue(.facesFound)]
            case .ocrText:
                return [.evaluationKind(kind), .reviewQueue(.ocrFound)]
            default:
                return [.evaluationKind(kind)]
            }
        case (.xmpPending, _):
            return [.metadataSyncPending]
        case (.xmpConflict, _):
            return [.metadataSyncConflicts]
        default:
            return []
        }
    }

    // MARK: - Autocomplete option lists (parity with the deleted pickers)

    public static let ratingOptions = Array(1...5)
    public static let flagOptions: [PickFlag] = [.pick, .reject]
    public static let colorOptions = ColorLabel.allCases
    public static let sourceOptions: [SourceAvailability] = [.online, .offline, .missing, .moved, .stale]
    public static let signalOptions: [EvaluationKind] = [
        .focus, .motionBlur, .exposure, .aesthetics, .framing, .object,
        .faceCount, .faceQuality, .eyesOpen, .eyeSharpness, .smile,
        .ocrText, .colorPalette, .novelty, .visualSimilarity
    ]
}
